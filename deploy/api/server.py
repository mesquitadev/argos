"""A API do Vigia: sessão, armazenamento e exportação de trechos.

Só biblioteca padrão. Um framework traria roteamento e validação que aqui
caberiam em cinquenta linhas, ao custo de dezenas de megabytes na imagem e de
uma cadeia de dependências para manter num aparelho que precisa ficar anos no ar
sem ninguém olhar.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import threading
import time
import urllib.parse
import uuid
from datetime import datetime, timedelta
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import auth
import retention

RECORDINGS = Path(os.environ.get("RECORDINGS_DIR", "/recordings"))
EXPORTS = Path(os.environ.get("EXPORTS_DIR", "/exports"))
CAMERA = os.environ.get("CAMERA_ID", "cam1")
SEGMENT_SECONDS = int(os.environ.get("SEGMENT_SECONDS", "300"))
USERS_FILE = Path(os.environ.get("USERS_FILE", "/config/users.json"))

NAME_RE = re.compile(r"^(.+)_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})\.mp4$")

# Trabalhos de exportação em memória. Perdê-los num restart é aceitável: o
# arquivo pronto continua no disco, e um trabalho interrompido seria refeito
# mais rápido do que valeria persistir estado para ele.
jobs: dict[str, dict] = {}
jobs_lock = threading.Lock()


# ---------- usuários ----------

def load_users() -> dict:
    if USERS_FILE.exists():
        return json.loads(USERS_FILE.read_text())
    return {}


def save_users(users: dict) -> None:
    USERS_FILE.parent.mkdir(parents=True, exist_ok=True)
    USERS_FILE.write_text(json.dumps(users, indent=2))
    # Contém hashes de senha: ninguém além do dono precisa ler.
    USERS_FILE.chmod(0o600)


def ensure_seed_user() -> None:
    """Cria o primeiro usuário a partir do ambiente, se ainda não houver nenhum.

    Sem isso o sistema subiria trancado e sem forma de entrar. A senha vem do
    `.env`, que já guarda a da câmera.
    """
    if load_users():
        return
    user = os.environ.get("ADMIN_USER")
    password = os.environ.get("ADMIN_PASSWORD")
    if not user or not password:
        print("[api] nenhum usuário e sem ADMIN_USER/ADMIN_PASSWORD — login ficará indisponível", flush=True)
        return
    save_users({user: {"password": auth.hash_password(password), "role": "admin"}})
    print(f"[api] usuário inicial criado: {user}", flush=True)


# ---------- gravações ----------

def started_at(path: Path) -> datetime | None:
    m = NAME_RE.match(path.name)
    if not m:
        return None
    try:
        return datetime.strptime(f"{m.group(2)}_{m.group(3)}", "%Y-%m-%d_%H-%M-%S")
    except ValueError:
        return None


def all_segments() -> list[tuple[Path, datetime, int]]:
    out = []
    for path in RECORDINGS.rglob("*.mp4"):
        at = started_at(path)
        if at:
            try:
                out.append((path, at, path.stat().st_size))
            except OSError:
                pass
    return sorted(out, key=lambda t: t[1])


def storage_report() -> dict:
    """O que o disco está guardando, e por quanto tempo ainda.

    A pergunta que importa num DVR não é "quantos GB", é "quantos dias tenho" —
    e, principalmente, "quando isto começa a apagar". Nenhuma das duas é visível
    olhando o disco.
    """
    segments = all_segments()
    total = sum(size for _, _, size in segments)
    usage = shutil.disk_usage(RECORDINGS)

    oldest = segments[0][1] if segments else None
    newest = segments[-1][1] if segments else None
    span_days = ((newest - oldest).total_seconds() / 86400) if oldest and newest else 0

    # Média dos últimos sete dias: mais honesta que a média de todo o histórico,
    # que dilui mudanças recentes de qualidade ou de movimento na cena.
    cutoff = datetime.now() - timedelta(days=7)
    recent = [(at, size) for _, at, size in segments if at >= cutoff]
    recent_days = max(1e-6, (max(a for a, _ in recent) - min(a for a, _ in recent)).total_seconds() / 86400) if len(recent) > 1 else 1
    per_day = (sum(s for _, s in recent) / recent_days) if recent else 0

    days_left = (usage.free / per_day) if per_day > 0 else None

    by_day: dict[str, int] = {}
    for _, at, size in segments:
        by_day[at.strftime("%Y-%m-%d")] = by_day.get(at.strftime("%Y-%m-%d"), 0) + size

    return {
        "segments": len(segments),
        "bytes": total,
        "disk": {"total": usage.total, "used": usage.used, "free": usage.free},
        "oldest": oldest.isoformat() if oldest else None,
        "newest": newest.isoformat() if newest else None,
        "span_days": round(span_days, 2),
        "bytes_per_day": round(per_day),
        "days_until_full": round(days_left, 1) if days_left else None,
        "by_day": [{"day": d, "bytes": b} for d, b in sorted(by_day.items())],
    }


# ---------- exportação ----------

def run_export(job_id: str, start: datetime, end: datetime) -> None:
    """Junta os trechos que cobrem o intervalo num único MP4.

    Concatena sem recodificar: um intervalo de meia hora sai em segundos, e a
    imagem é exatamente a que a câmera mandou. Recodificar custaria minutos de
    CPU e perderia qualidade, para nada.
    """
    job = jobs[job_id]
    try:
        segments = [(p, at) for p, at, _ in all_segments()
                    if at + timedelta(seconds=SEGMENT_SECONDS) > start and at < end]
        if not segments:
            raise RuntimeError("nenhuma gravação nesse intervalo")

        listing = EXPORTS / f"{job_id}.txt"
        listing.write_text("".join(f"file '{p}'\n" for p, _ in segments))

        output = EXPORTS / f"{job_id}.mp4"
        # O primeiro trecho quase nunca começa exatamente no instante pedido;
        # `-ss` corta a diferença, e `-t` limita ao tamanho do intervalo.
        offset = max(0.0, (start - segments[0][1]).total_seconds())
        duration = (end - start).total_seconds()

        cmd = [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "concat", "-safe", "0", "-i", str(listing),
            "-ss", f"{offset:.3f}", "-t", f"{duration:.3f}",
            "-c", "copy", "-movflags", "+faststart",
            # O mesmo motivo do gravador: a Apple recusa HEVC marcado `hev1`.
            "-tag:v", "hvc1",
            str(output),
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
        listing.unlink(missing_ok=True)

        if result.returncode != 0 or not output.exists():
            raise RuntimeError(result.stderr.strip()[:300] or "ffmpeg falhou")

        with jobs_lock:
            job.update(state="ready", size=output.stat().st_size,
                       url=f"/api/export/{job_id}/file")
    except Exception as err:  # noqa: BLE001 — o erro precisa chegar à interface
        with jobs_lock:
            job.update(state="error", error=str(err))


def cleanup_exports() -> None:
    """Apaga exportações antigas.

    Sem isto, cada pedido deixaria um arquivo para sempre e o disco das
    gravações — o mesmo — encolheria em silêncio.
    """
    while True:
        try:
            limit = time.time() - 6 * 3600
            for f in EXPORTS.glob("*.mp4"):
                if f.stat().st_mtime < limit:
                    f.unlink(missing_ok=True)
        except Exception:
            pass
        time.sleep(1800)


# ---------- HTTP ----------

class Handler(BaseHTTPRequestHandler):
    server_version = "vigia"

    def log_message(self, *args):  # silencia o log por requisição
        pass

    # -- utilidades --

    def session(self) -> dict | None:
        raw = self.headers.get("Cookie", "")
        if not raw:
            return None
        cookie = SimpleCookie()
        cookie.load(raw)
        token = cookie.get(auth.COOKIE)
        return auth.read(token.value) if token else None

    def send_json(self, data, status=200, headers=None):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (headers or {}):
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def body_json(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
            return {}
        try:
            return json.loads(self.rfile.read(length))
        except Exception:
            return {}

    # -- rotas --

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path

        # O nginx pergunta aqui antes de servir qualquer coisa protegida.
        if path == "/api/auth":
            if self.session():
                self.send_response(200)
                self.end_headers()
            else:
                self.send_response(401)
                self.end_headers()
            return

        if path == "/api/session":
            s = self.session()
            self.send_json({"user": s["u"], "role": s["r"]} if s else {"user": None},
                           200 if s else 401)
            return

        if not self.session():
            self.send_json({"error": "não autenticado"}, 401)
            return

        if path == "/api/storage":
            self.send_json(storage_report())
            return

        if path == "/api/retention":
            self.send_json({"policy": retention.read(), "plan": retention.plan()})
            return

        m = re.match(r"^/api/export/([0-9a-f-]+)$", path)
        if m:
            with jobs_lock:
                job = jobs.get(m.group(1))
            self.send_json(job or {"error": "não encontrado"}, 200 if job else 404)
            return

        m = re.match(r"^/api/export/([0-9a-f-]+)/file$", path)
        if m:
            f = EXPORTS / f"{m.group(1)}.mp4"
            if not f.exists():
                self.send_json({"error": "não encontrado"}, 404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Content-Length", str(f.stat().st_size))
            self.send_header("Content-Disposition",
                             f'attachment; filename="vigia_{m.group(1)[:8]}.mp4"')
            self.end_headers()
            with f.open("rb") as fh:
                shutil.copyfileobj(fh, self.wfile)
            return

        self.send_json({"error": "rota desconhecida"}, 404)

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path

        if path == "/api/login":
            data = self.body_json()
            users = load_users()
            entry = users.get(data.get("user", ""))
            if not entry or not auth.verify_password(data.get("password", ""), entry["password"]):
                # Atraso pequeno e uniforme: torna a força bruta cara sem
                # travar o serviço nem revelar se o usuário existe.
                time.sleep(0.5)
                self.send_json({"error": "usuário ou senha inválidos"}, 401)
                return
            token = auth.issue(data["user"], entry.get("role", "admin"))
            self.send_json({"user": data["user"], "role": entry.get("role", "admin")},
                           200, [("Set-Cookie", auth.cookie_header(token))])
            return

        if path == "/api/logout":
            self.send_json({"ok": True}, 200,
                           [("Set-Cookie", f"{auth.COOKIE}=; Path=/; Max-Age=0")])
            return

        if not self.session():
            self.send_json({"error": "não autenticado"}, 401)
            return

        if path == "/api/retention":
            try:
                policy = retention.write(self.body_json())
            except ValueError as err:
                self.send_json({"error": str(err)}, 400)
                return
            self.send_json({"policy": policy, "plan": retention.plan(policy)})
            return

        if path == "/api/retention/purge":
            # Apagar gravação é irreversível: exige a confirmação explícita que
            # a interface manda junto, para um clique errado não levar o
            # histórico.
            if self.body_json().get("confirm") is not True:
                self.send_json({"error": "confirmação ausente"}, 400)
                return
            self.send_json(retention.purge())
            return

        if path == "/api/export":
            data = self.body_json()
            try:
                start = datetime.fromisoformat(data["start"])
                end = datetime.fromisoformat(data["end"])
            except Exception:
                self.send_json({"error": "intervalo inválido"}, 400)
                return
            if not 0 < (end - start).total_seconds() <= 3600:
                self.send_json({"error": "o intervalo deve ter entre 1 segundo e 1 hora"}, 400)
                return

            job_id = str(uuid.uuid4())
            with jobs_lock:
                jobs[job_id] = {"id": job_id, "state": "working",
                                "start": start.isoformat(), "end": end.isoformat()}
            threading.Thread(target=run_export, args=(job_id, start, end), daemon=True).start()
            self.send_json({"id": job_id, "state": "working"}, 202)
            return

        self.send_json({"error": "rota desconhecida"}, 404)


def main():
    EXPORTS.mkdir(parents=True, exist_ok=True)
    ensure_seed_user()
    threading.Thread(target=cleanup_exports, daemon=True).start()
    port = int(os.environ.get("PORT", "8090"))
    print(f"[api] ouvindo na porta {port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()

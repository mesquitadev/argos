#!/usr/bin/env python3
"""Registra os eventos de movimento que a câmera publica.

A câmera mantém uma conexão aberta e empurra eventos conforme acontecem —
não há polling. Cada início e fim de movimento vira uma linha no arquivo de
eventos, que o app usa para marcar a linha do tempo.

Guardar em arquivo de linhas, e não em banco: é o mesmo princípio das
gravações. O que existe é o que está no disco, e um índice separado que
discorde disso seria pior do que índice nenhum.
"""
import hashlib
import json
import os
import re
import socket
import threading
import time
from datetime import datetime, timezone

# A câmera vem do registro, não do ambiente: uma thread por câmera, cada uma
# escrevendo no próprio arquivo. Um arquivo só para todas obrigaria a filtrar a
# cada leitura e faria o crescimento de uma poluir a busca das outras.
REGISTRO = os.environ.get("CAMERAS_FILE", "/config-cameras/cameras.json")
PATH = "/cgi-bin/eventManager.cgi?action=attach&codes=[All]"


def carregar_cameras():
    try:
        with open(REGISTRO) as handle:
            return [c for c in json.load(handle) if c.get("enabled", True)]
    except (OSError, ValueError):
        return []


def caminho_eventos(camera_id):
    destino = os.path.join("/hls", camera_id)
    os.makedirs(destino, exist_ok=True)
    return os.path.join(destino, "events.jsonl")


def md5(text):
    return hashlib.md5(text.encode()).hexdigest()


def digest_header(challenge, method, uri, user, password):
    """Monta a resposta Digest. A câmera não aceita Basic."""
    fields = dict(re.findall(r'(\w+)="([^"]*)"', challenge))
    realm, nonce = fields.get("realm", ""), fields.get("nonce", "")
    qop = fields.get("qop")
    ha1 = md5(f"{user}:{realm}:{password}")
    ha2 = md5(f"{method}:{uri}")

    parts = [f'username="{user}"', f'realm="{realm}"', f'nonce="{nonce}"', f'uri="{uri}"']
    if qop:
        cnonce = md5(str(time.time()))[:16]
        response = md5(f"{ha1}:{nonce}:00000001:{cnonce}:auth:{ha2}")
        parts += ["qop=auth", "nc=00000001", f'cnonce="{cnonce}"']
    else:
        response = md5(f"{ha1}:{nonce}:{ha2}")
    parts.append(f'response="{response}"')
    if "opaque" in fields:
        parts.append(f'opaque="{fields["opaque"]}"')
    return "Digest " + ", ".join(parts)


def record(camera, code, action, index):
    entry = {
        "camera": camera['id'],
        "code": code,
        "action": action,
        "index": index,
        "at": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
    }
    with open(caminho_eventos(camera['id']), "a") as handle:
        handle.write(json.dumps(entry, ensure_ascii=False) + "\n")
    print(f"[vigia-events] {entry['at']} {code} {action}", flush=True)


def listen(camera):
    """Abre a conexão e lê eventos até ela cair."""
    with socket.create_connection((camera['host'], 80), timeout=15) as sock:
        request = f"GET {PATH} HTTP/1.1\r\nHost: {camera['host']}\r\nConnection: keep-alive\r\n\r\n"
        sock.sendall(request.encode())
        head = sock.recv(4096).decode("utf-8", "ignore")

        # A primeira resposta é sempre 401 com o desafio; a segunda já traz os
        # eventos. Reabrimos a conexão porque a câmera fecha depois do 401.
        if "401" in head.split("\r\n")[0]:
            challenge = ""
            for line in head.split("\r\n"):
                if line.lower().startswith("www-authenticate:"):
                    challenge = line.split(":", 1)[1].strip()
            if not challenge:
                raise RuntimeError("sem desafio de autenticação")
            sock.close()
            with socket.create_connection((camera['host'], 80), timeout=None) as authed:
                header = digest_header(challenge, "GET", PATH,
                                       camera["user"], camera["password"])
                authed.sendall(
                    f"GET {PATH} HTTP/1.1\r\nHost: {camera['host']}\r\n"
                    f"Authorization: {header}\r\nConnection: keep-alive\r\n\r\n".encode()
                )
                consume(camera, authed)
        else:
            consume(camera, sock)


def consume(camera, sock):
    """Lê o fluxo multipart, linha a linha, sem esperar o fim — ele não tem fim."""
    buffer = b""
    sock.settimeout(None)
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            return
        buffer += chunk
        while b"\r\n" in buffer:
            line, buffer = buffer.split(b"\r\n", 1)
            text = line.decode("utf-8", "ignore").strip()
            if not text.startswith("Code="):
                continue
            fields = dict(part.split("=", 1) for part in text.split(";") if "=" in part)
            code = fields.get("Code", "")
            action = fields.get("action", "")
            # NTPAdjustTime e afins chegam junto e não interessam à linha do tempo.
            if code in {"VideoMotion", "CrossLineDetection", "CrossRegionDetection",
                        "AlarmLocal", "VideoLoss", "VideoBlind"}:
                record(camera, code, action, fields.get("index", "0"))


def vigiar(camera):
    """Mantém a escuta de uma câmera viva, com espera crescente entre quedas.

    Reconectar em rajada contra uma câmera que reiniciou só atrasa a volta e
    enche o log; dobrar a espera até trinta segundos reata rápido quando é
    piscada de rede e desiste com calma quando é queda de verdade.
    """
    delay = 1
    while True:
        try:
            print(f"[vigia-events] escutando {camera['id']} ({camera['host']})", flush=True)
            listen(camera)
            delay = 1
        except Exception as failure:      # noqa: BLE001
            print(f"[vigia-events] {camera['id']}: {failure}", flush=True)
        time.sleep(delay)
        delay = min(30, delay * 2)


if __name__ == "__main__":
    ativas = {}
    while True:
        for camera in carregar_cameras():
            thread = ativas.get(camera["id"])
            if thread and thread.is_alive():
                continue
            # Uma thread por câmera: a escuta é bloqueante e passa horas
            # parada esperando evento, então threads custam quase nada aqui e
            # evitam que uma câmera fora do ar cale as outras.
            thread = threading.Thread(target=vigiar, args=(camera,), daemon=True)
            thread.start()
            ativas[camera["id"]] = thread
        # Relê o registro: adotar uma câmera deve começar a escutá-la sem
        # reiniciar o serviço.
        time.sleep(15)

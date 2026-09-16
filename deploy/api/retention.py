"""Política de retenção: ler, validar, prever e aplicar.

Prever antes de aplicar não é luxo. Apagar gravação é irreversível, e a
diferença entre "7 dias" e "7 dias apaga 40 GB e leva até anteontem" é o que
faz alguém parar antes de confirmar.
"""
from __future__ import annotations

import os
import re
import shutil
from datetime import datetime, timedelta
from pathlib import Path

RECORDINGS = Path(os.environ.get("RECORDINGS_DIR", "/recordings"))
CONF = Path(os.environ.get("RETENTION_CONF", "/config/retention.conf"))

# Sete dias cobrem "aconteceu na semana passada", que é o alcance real de quem
# procura uma gravação em casa. Guardar mais é ocupar disco por um caso raro.
DEFAULTS = {
    "MAX_DAYS": 7,
    "MAX_GB": 700,
    "MIN_FREE_GB": 20,
    "CHECK_MINUTES": 10,
    "ENABLED": 1,
}

LIMITS = {
    # Menos de um dia transformaria a retenção em apagador contínuo; mais de um
    # ano, num disco que enche muito antes disso.
    "MAX_DAYS": (1, 365),
    "MAX_GB": (1, 100000),
    # Sem alguma folga o disco chega a zero e quem para de gravar é o próprio
    # sistema, no pior momento.
    "MIN_FREE_GB": (5, 5000),
    "CHECK_MINUTES": (1, 1440),
    "ENABLED": (0, 1),
}

NAME_RE = re.compile(r"_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})\.mp4$")


def read() -> dict:
    values = dict(DEFAULTS)
    if CONF.exists():
        for line in CONF.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, raw = line.partition("=")
            key = key.strip()
            if key in DEFAULTS:
                try:
                    values[key] = int(raw.strip().strip('"'))
                except ValueError:
                    pass
    return values


def write(values: dict) -> dict:
    current = read()
    for key, raw in values.items():
        if key not in DEFAULTS:
            continue
        try:
            number = int(raw)
        except (TypeError, ValueError):
            raise ValueError(f"{key} precisa ser um número inteiro")
        low, high = LIMITS[key]
        if not low <= number <= high:
            raise ValueError(f"{key} precisa estar entre {low} e {high}")
        current[key] = number

    CONF.parent.mkdir(parents=True, exist_ok=True)
    body = "# Escrito pelo Vigia. O container de retenção relê a cada volta.\n"
    body += "".join(f"{k}={v}\n" for k, v in current.items())
    CONF.write_text(body)
    return current


def _segments():
    for path in RECORDINGS.rglob("*.mp4"):
        m = NAME_RE.search(path.name)
        if not m:
            continue
        try:
            at = datetime.strptime(f"{m.group(1)}_{m.group(2)}", "%Y-%m-%d_%H-%M-%S")
            yield path, at, path.stat().st_size
        except (ValueError, OSError):
            continue


def plan(policy: dict | None = None) -> dict:
    """O que a política atual apagaria agora, sem apagar nada."""
    policy = policy or read()
    segments = sorted(_segments(), key=lambda t: t[1])
    if not segments:
        return {"count": 0, "bytes": 0, "oldest": None, "newest": None, "reason": None}

    cutoff = datetime.now() - timedelta(days=policy["MAX_DAYS"])
    doomed = [s for s in segments if s[1] < cutoff]
    reason = "idade" if doomed else None

    # Depois da idade, o espaço: continua apagando do mais antigo até caber.
    survivors = [s for s in segments if s[1] >= cutoff]
    used = sum(size for _, _, size in survivors)
    usage = shutil.disk_usage(RECORDINGS)
    free = usage.free + sum(size for _, _, size in doomed)
    limit = policy["MAX_GB"] * 1024**3
    floor = policy["MIN_FREE_GB"] * 1024**3

    index = 0
    while index < len(survivors) and (used > limit or free < floor):
        _, _, size = survivors[index]
        used -= size
        free += size
        index += 1
    if index:
        doomed += survivors[:index]
        reason = "espaço" if reason is None else "idade e espaço"

    return {
        "count": len(doomed),
        "bytes": sum(size for _, _, size in doomed),
        "oldest": min(at for _, at, _ in doomed).isoformat() if doomed else None,
        "newest": max(at for _, at, _ in doomed).isoformat() if doomed else None,
        "reason": reason,
    }


def purge() -> dict:
    """Aplica a política agora, em vez de esperar a próxima volta."""
    policy = read()
    before = plan(policy)
    removed = 0
    freed = 0

    cutoff = datetime.now() - timedelta(days=policy["MAX_DAYS"])
    segments = sorted(_segments(), key=lambda t: t[1])

    for path, at, size in segments:
        if at >= cutoff:
            break
        try:
            path.unlink()
            removed += 1
            freed += size
        except OSError:
            pass

    # O laço por espaço fica com o container de retenção, que já o faz de forma
    # incremental e verificando o disco a cada remoção. Duplicar essa lógica
    # aqui seria dois lugares para errar.
    return {"removed": removed, "bytes": freed, "planned": before}

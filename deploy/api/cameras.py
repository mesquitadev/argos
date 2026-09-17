"""O registro de câmeras.

O sistema nasceu com uma câmera fixa no ambiente. Para ser um NVR de verdade,
câmera vira dado: entra, sai e muda sem recriar container nem editar arquivo
por SSH.

As credenciais ficam aqui porque é preciso montar a URL RTSP. O arquivo é
0600 e nunca sai pela API — a interface recebe a câmera sem a senha.
"""
from __future__ import annotations

import json
import os
import re
import socket
import uuid
from pathlib import Path
from urllib.parse import quote

REGISTRO = Path(os.environ.get("CAMERAS_FILE", "/config/cameras.json"))

# Identificador vira nome de pasta no disco: manter estreito evita travessia de
# caminho e nomes que o sistema de arquivos rejeita.
ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{1,30}$")


def carregar() -> list[dict]:
    if not REGISTRO.exists():
        return []
    try:
        return json.loads(REGISTRO.read_text())
    except json.JSONDecodeError:
        return []


def salvar(cameras: list[dict]) -> None:
    REGISTRO.parent.mkdir(parents=True, exist_ok=True)
    REGISTRO.write_text(json.dumps(cameras, indent=2, ensure_ascii=False))
    REGISTRO.chmod(0o600)


def publica(camera: dict) -> dict:
    """A câmera como a interface pode vê-la — sem a senha."""
    visivel = {k: v for k, v in camera.items() if k != "password"}
    visivel["tem_senha"] = bool(camera.get("password"))
    return visivel


def rtsp_url(camera: dict) -> str:
    """Monta a URL do fluxo.

    A senha vai codificada: `@` e `/` numa senha quebram a URL de forma que o
    erro do ffmpeg não explica — ele reclama de host inválido.
    """
    user = quote(camera.get("user", ""), safe="")
    senha = quote(camera.get("password", ""), safe="")
    credencial = f"{user}:{senha}@" if user else ""
    caminho = camera.get("path", "/cam/realmonitor?channel=1&subtype=0")
    porta = camera.get("rtsp_port", 554)
    return f"rtsp://{credencial}{camera['host']}:{porta}{caminho}"


def validar(dados: dict, existentes: list[dict], criando: bool) -> dict:
    ident = (dados.get("id") or "").strip().lower()
    if not ID_RE.match(ident):
        raise ValueError("identificador: use 2 a 31 letras minúsculas, números, hífen ou sublinhado")

    conflito = any(c["id"] == ident for c in existentes)
    if criando and conflito:
        raise ValueError(f"já existe uma câmera com o identificador '{ident}'")
    if not criando and not conflito:
        raise ValueError(f"não existe câmera com o identificador '{ident}'")

    host = (dados.get("host") or "").strip()
    if not host:
        raise ValueError("endereço da câmera é obrigatório")

    return {
        "id": ident,
        "name": (dados.get("name") or ident).strip()[:60],
        "host": host,
        "rtsp_port": int(dados.get("rtsp_port") or 554),
        "user": (dados.get("user") or "").strip(),
        "password": dados.get("password") or "",
        "path": (dados.get("path") or "/cam/realmonitor?channel=1&subtype=0").strip(),
        "enabled": bool(dados.get("enabled", True)),
    }


# ---------- descoberta ----------

MULTICAST = ("239.255.255.250", 3702)

_PROBE = """<?xml version="1.0" encoding="UTF-8"?>
<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"
 xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"
 xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery"
 xmlns:dn="http://www.onvif.org/ver10/network/wsdl">
 <e:Header>
  <w:MessageID>uuid:{id}</w:MessageID>
  <w:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
  <w:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
 </e:Header>
 <e:Body><d:Probe><d:Types>dn:NetworkVideoTransmitter</d:Types></d:Probe></e:Body>
</e:Envelope>"""

_ESCOPO_RE = re.compile(r"onvif://www\.onvif\.org/(\w+)/([^\s<]+)")


def descobrir(segundos: float = 4.0) -> list[dict]:
    """Procura câmeras ONVIF na rede local.

    Toda câmera ONVIF responde a este multicast dizendo fabricante e modelo, o
    que dispensa alguém descobrir e digitar um IP — que é a pior primeira
    pergunta que um sistema desses pode fazer.

    Exige rede do host: de dentro de uma rede isolada do Docker o multicast não
    sai, e a resposta não teria como voltar.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
    sock.settimeout(segundos)

    try:
        sock.sendto(_PROBE.format(id=uuid.uuid4()).encode(), MULTICAST)
    except OSError as err:
        sock.close()
        raise RuntimeError(f"não consegui enviar a busca: {err}") from err

    achadas: dict[str, dict] = {}
    try:
        while True:
            dados, origem = sock.recvfrom(65535)
            ip = origem[0]
            if ip in achadas:
                continue
            texto = dados.decode(errors="ignore")
            escopos = dict(_ESCOPO_RE.findall(texto))
            achadas[ip] = {
                "host": ip,
                "name": escopos.get("name", "").replace("_", " ") or ip,
                "hardware": escopos.get("hardware", "").replace("_", " "),
                "ja_registrada": False,
            }
    except socket.timeout:
        pass
    finally:
        sock.close()

    registradas = {c["host"] for c in carregar()}
    for ip, info in achadas.items():
        info["ja_registrada"] = ip in registradas

    return sorted(achadas.values(), key=lambda c: c["host"])

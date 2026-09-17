"""Um gravador por câmera, vivos enquanto a câmera existir.

O sistema nasceu com um `ffmpeg` fixo numa câmera escrita no ambiente. Para
várias, a escolha é entre gerar um container por câmera — que exige recriar o
stack a cada mudança — ou um processo que lê o registro e mantém os filhos
certos no ar. O segundo permite adicionar câmera pela tela e ver gravação em
segundos, que é o comportamento esperado de um NVR.

Cada câmera tem dois filhos: o que grava em disco e o que produz HLS para a
visualização ao vivo. São separados de propósito — se a transcodificação do ao
vivo falhar, a gravação continua, que é a função que não pode parar.
"""
from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import quote

REGISTRO = Path(os.environ.get("CAMERAS_FILE", "/config/cameras.json"))
GRAVACOES = Path(os.environ.get("RECORDINGS_DIR", "/recordings"))
HLS = Path(os.environ.get("HLS_DIR", "/hls"))
SEGMENTO = os.environ.get("SEGMENT_SECONDS", "300")
INTERVALO = 5

processos: dict[str, subprocess.Popen] = {}
assinaturas: dict[str, str] = {}
parando = False


def log(mensagem: str) -> None:
    print(f"[supervisor] {mensagem}", flush=True)


def rtsp_url(camera: dict) -> str:
    """A senha vai codificada: `@` ou `/` numa senha quebram a URL, e o ffmpeg
    reclama de host inválido — um erro que não aponta para a causa."""
    user = quote(camera.get("user", ""), safe="")
    senha = quote(camera.get("password", ""), safe="")
    credencial = f"{user}:{senha}@" if user else ""
    caminho = camera.get("path") or "/cam/realmonitor?channel=1&subtype=0"
    return f"rtsp://{credencial}{camera['host']}:{camera.get('rtsp_port', 554)}{caminho}"


def comando_gravacao(camera: dict) -> list[str]:
    ident = camera["id"]
    (GRAVACOES / ident).mkdir(parents=True, exist_ok=True)
    return [
        "ffmpeg", "-hide_banner", "-loglevel", "warning",
        "-rtsp_transport", "tcp", "-timeout", "10000000",
        "-i", rtsp_url(camera),
        # Copia sem recodificar: gravar 24h de várias câmeras recodificando
        # consumiria a máquina inteira, e a imagem sairia pior que a original.
        "-c", "copy",
        # A Apple recusa HEVC marcado `hev1`; sem isto o vídeo abre e não toca.
        "-tag:v", "hvc1",
        "-f", "segment", "-segment_time", SEGMENTO,
        "-reset_timestamps", "1", "-strftime", "1", "-strftime_mkdir", "1",
        f"{GRAVACOES}/{ident}/%Y-%m-%d/{ident}_%Y-%m-%d_%H-%M-%S.mp4",
    ]


def comando_hls(camera: dict) -> list[str]:
    ident = camera["id"]
    destino = HLS / ident
    destino.mkdir(parents=True, exist_ok=True)
    return [
        "ffmpeg", "-hide_banner", "-loglevel", "warning",
        "-rtsp_transport", "tcp", "-timeout", "10000000",
        "-i", rtsp_url(camera),
        "-c", "copy", "-tag:v", "hvc1",
        "-f", "hls",
        # Segmentos curtos e lista curta: é o que mantém o ao vivo perto do
        # presente. Lista longa vira atraso acumulado.
        "-hls_time", "1", "-hls_list_size", "8",
        "-hls_flags", "delete_segments+append_list+omit_endlist+independent_segments",
        # HEVC exige fMP4; em MPEG-TS o AVPlayer da Apple simplesmente não toca.
        "-hls_segment_type", "fmp4",
        "-hls_fmp4_init_filename", f"{ident}_init.mp4",
        "-hls_segment_filename", f"{destino}/{ident}_%d.m4s",
        f"{destino}/{ident}.m3u8",
    ]


def assinatura(camera: dict) -> str:
    """O que, mudando, obriga a reiniciar os filhos daquela câmera."""
    return json.dumps({k: camera.get(k) for k in
                       ("host", "rtsp_port", "user", "password", "path", "enabled")},
                      sort_keys=True)


def carregar() -> list[dict] | None:
    """As câmeras ativas, ou `None` se o registro estiver ilegível.

    A distinção importa: registro vazio significa "pare tudo"; registro
    corrompido — surpreendido no meio de uma gravação, por exemplo — significa
    "não mexa", porque parar todas as câmeras por causa de uma leitura ruim
    seria o pior desfecho possível.
    """
    if not REGISTRO.exists():
        return []
    try:
        return [c for c in json.loads(REGISTRO.read_text()) if c.get("enabled", True)]
    except json.JSONDecodeError:
        log("registro ilegível; mantendo o que já está no ar")
        return None


def encerrar(chave: str) -> None:
    proc = processos.pop(chave, None)
    if not proc:
        return
    proc.terminate()
    try:
        proc.wait(timeout=8)
    except subprocess.TimeoutExpired:
        proc.kill()
    log(f"parado: {chave}")


def sincronizar() -> None:
    cameras = carregar()
    if cameras is None:            # registro ilegível: não mexe em nada
        return

    desejadas = {c["id"] for c in cameras}

    # Some quem saiu do registro ou foi desativada.
    for chave in list(processos):
        if chave.split(":")[0] not in desejadas:
            encerrar(chave)
            assinaturas.pop(chave, None)

    for camera in cameras:
        ident = camera["id"]
        marca = assinatura(camera)

        for papel, montar in (("rec", comando_gravacao), ("hls", comando_hls)):
            chave = f"{ident}:{papel}"
            proc = processos.get(chave)

            # Mudou endereço ou credencial: reinicia, senão seguiria gravando
            # da câmera antiga até alguém perceber.
            if proc and assinaturas.get(chave) != marca:
                log(f"configuração mudou: {chave}")
                encerrar(chave)
                proc = None

            if proc and proc.poll() is None:
                continue
            if proc:
                log(f"caiu (código {proc.returncode}): {chave}")
                processos.pop(chave, None)

            processos[chave] = subprocess.Popen(
                montar(camera), stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
            assinaturas[chave] = marca
            log(f"iniciado: {chave} ({camera.get('name', ident)})")


def ao_encerrar(*_):
    global parando
    parando = True


def main() -> None:
    signal.signal(signal.SIGTERM, ao_encerrar)
    signal.signal(signal.SIGINT, ao_encerrar)
    log(f"vigiando {REGISTRO}")

    while not parando:
        try:
            sincronizar()
        except Exception as err:            # noqa: BLE001
            # Uma falha aqui não pode derrubar o supervisor: ele é quem mantém
            # todas as gravações de pé.
            log(f"erro ao sincronizar: {err}")
        time.sleep(INTERVALO)

    log("encerrando filhos")
    for chave in list(processos):
        encerrar(chave)


if __name__ == "__main__":
    sys.exit(main())

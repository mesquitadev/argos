"""Anuncia o gravador na rede local, para o app achá-lo sozinho.

Roda como container na rede do host — mDNS é multicast, e de dentro de uma
rede isolada do Docker os pacotes não chegam a ninguém.

Vive em container em vez de como pacote no host pelo mesmo motivo que o resto
do Vigia: sobe junto com o stack, some junto com ele, e não pede root.
"""
import os
import signal
import socket
import time

from zeroconf import ServiceInfo, Zeroconf

PORT = int(os.environ.get("WEB_PORT", "8088"))
CAMERA = os.environ.get("CAMERA_ID", "cam1")
NOME = os.environ.get("RECORDER_NAME") or f"Gravador Vigia ({socket.gethostname()})"
TIPO = "_vigia._tcp.local."


def endereco_local() -> str:
    """O IP pelo qual esta máquina é vista na rede local.

    `gethostbyname` devolveria 127.0.0.1 em máquina com hostname local, e um
    gravador que se anuncia como localhost não serve para ninguém. Abrir um
    socket UDP para fora revela o endereço da interface que realmente sai —
    sem enviar pacote algum, porque UDP não conecta de verdade.
    """
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.connect(("8.8.8.8", 80))
        return sock.getsockname()[0]


def main() -> None:
    ip = endereco_local()
    info = ServiceInfo(
        TIPO,
        f"{NOME}.{TIPO}",
        addresses=[socket.inet_aton(ip)],
        port=PORT,
        properties={
            "camera": CAMERA,
            "path": "/live/index.json",
            "versao": "1",
        },
        server=f"{socket.gethostname()}.local.",
    )

    zeroconf = Zeroconf()
    zeroconf.register_service(info)
    print(f"[vigia-mdns] anunciado: {NOME} em {ip}:{PORT}", flush=True)

    parar = signal.Event() if hasattr(signal, "Event") else None
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass
    finally:
        # Retirar o anúncio ao sair evita que o app continue oferecendo um
        # gravador que acabou de ser desligado.
        zeroconf.unregister_service(info)
        zeroconf.close()
        print("[vigia-mdns] anúncio retirado", flush=True)


if __name__ == "__main__":
    main()

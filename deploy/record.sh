#!/bin/sh
# Mantém a gravação viva. Se a câmera cair, espera e tenta de novo — um
# gravador que desiste na primeira falha não é um gravador.
set -u
DELAY=1
while true; do
    mkdir -p "/recordings/${CAMERA_ID}"

    # -c copy: a câmera já entrega H.264 pronto. Recodificar gastaria CPU o dia
    # inteiro para produzir imagem pior do que a que chegou.
    # TCP em vez de UDP: em rede doméstica, UDP perde pacote e o vídeo fica com
    # blocos quebrados que ninguém consegue usar.
    # -tag:v hvc1 é obrigatório: o ffmpeg etiqueta HEVC como "hev1" por padrão e
    # a Apple só reproduz "hvc1". Sem isso o arquivo é válido, tem duração, abre
    # no VLC — e o AVPlayer devolve "não reproduzível" sem dizer por quê.
    #
    # MP4 comum, não fragmentado: o AVPlayer recusa fMP4 progressivo, e sem
    # isso as gravações abrem em tudo menos no app que as exibe. Em troca,
    # perde-se o segmento em escrita numa queda de energia — por isso os
    # segmentos caíram para 5 minutos, que é o tamanho do prejuízo possível.
    # A data entra no caminho, não numa variável: calculada em shell ela seria
# resolvida uma única vez, e este ffmpeg roda por dias — todas as gravações
# acabavam na pasta do dia em que o container subiu. `-strftime_mkdir` deixa o
# próprio ffmpeg criar a pasta de cada dia ao virar a meia-noite.
ffmpeg -hide_banner -loglevel warning \
        -rtsp_transport tcp -timeout 10000000 \
        -i "$RTSP_URL" \
        -c copy -tag:v hvc1 -f segment -segment_time "$SEGMENT_SECONDS" \
        -reset_timestamps 1 -strftime 1 -strftime_mkdir 1 \
        "/recordings/${CAMERA_ID}/%Y-%m-%d/${CAMERA_ID}_%Y-%m-%d_%H-%M-%S.mp4"

    echo "[argos] captura encerrou; nova tentativa em ${DELAY}s"
    sleep "$DELAY"
    # Espera progressiva até 30s: insistir a cada segundo numa câmera desligada
    # só enche o log e a rede.
    DELAY=$(( DELAY * 2 )); [ "$DELAY" -gt 30 ] && DELAY=30
done

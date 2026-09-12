#!/bin/sh
# Converte o fluxo da câmera em HLS, que o macOS reproduz nativamente.
#
# Sem recodificar: os pacotes H.265 são apenas reempacotados, então o custo é
# quase zero de CPU — o mesmo motivo pelo qual a gravação copia em vez de
# transcodificar.
#
# O empacotamento é fMP4, não MPEG-TS: a Apple só reproduz HEVC em HLS quando
# os segmentos são fMP4. Com H.264 o TS funcionaria, mas a câmera foi ajustada
# para H.265 — que ocupa metade do espaço — e o formato precisa acompanhar.
set -u
DELAY=1
mkdir -p /hls
while true; do
    # Segmentos de 1 segundo e uma janela de 8: janela curta demais faz o
    # player ficar sem material e travar a cada engasgo da rede; longa demais
    # atrasa o ao vivo. Oito segundos é o equilíbrio.
    #
    # independent_segments diz ao player que cada segmento começa em
    # quadro-chave, e é o que permite entrar no fluxo sem esperar o próximo.
    ffmpeg -hide_banner -loglevel warning \
        -rtsp_transport tcp -timeout 10000000 \
        -i "$RTSP_URL" \
        -c copy -tag:v hvc1 -f hls \
        -hls_time 1 -hls_list_size 8 -hls_flags delete_segments+append_list+omit_endlist+independent_segments \
        -hls_segment_type fmp4 \
        -hls_fmp4_init_filename "${CAMERA_ID}_init.mp4" \
        -hls_segment_filename "/hls/${CAMERA_ID}_%03d.m4s" \
        "/hls/${CAMERA_ID}.m3u8"

    echo "[vigia-hls] fluxo encerrou; nova tentativa em ${DELAY}s"
    sleep "$DELAY"
    DELAY=$(( DELAY * 2 )); [ "$DELAY" -gt 30 ] && DELAY=30
done

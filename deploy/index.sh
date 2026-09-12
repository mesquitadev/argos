#!/bin/sh
# Gera o índice das gravações que o app consome.
#
# É um arquivo JSON reescrito de tempos em tempos, não um banco: o disco é a
# verdade sobre o que existe, e um índice que discorde dele seria pior que
# índice nenhum — mostraria na linha do tempo gravações já apagadas.
set -u
while true; do
    printf '{"camera":"%s","generated":"%s","segments":[' "$CAMERA_ID" "$(date -Iseconds)" > /hls/index.json.tmp
    FIRST=1
    find /recordings -name "*.mp4" -type f 2>/dev/null | sort | while read -r FILE; do
        NAME=$(basename "$FILE" .mp4)
        STAMP=${NAME#*_}
        SIZE=$(stat -c %s "$FILE" 2>/dev/null || echo 0)
        REL=${FILE#/recordings/}
        [ "$FIRST" = "1" ] && FIRST=0 || printf ',' >> /hls/index.json.tmp
        printf '{"id":"%s","started":"%s","bytes":%s,"path":"%s"}' \
            "$NAME" "$STAMP" "$SIZE" "$REL" >> /hls/index.json.tmp
    done
    printf ']}' >> /hls/index.json.tmp
    # Troca atômica: o app nunca lê um índice pela metade.
    mv /hls/index.json.tmp /hls/index.json
    sleep 60
done

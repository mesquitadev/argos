#!/bin/sh
# Apaga o passado para caber o presente, como um DVR.
#
# Três limites agem juntos e o mais restritivo vence: teto de espaço, idade
# máxima, e uma folga livre que nunca pode ser consumida — sem ela o disco
# enche e quem para de gravar é o próprio sistema, no pior momento.
set -u
while true; do
    # Idade: remove o que passou do limite de dias.
    find /recordings -name "*.mp4" -type f -mtime "+${MAX_DAYS}" -delete 2>/dev/null

    # Espaço: enquanto estiver acima do teto ou com pouca folga, apaga o mais
    # antigo — um por vez, conferindo de novo a cada remoção. Apagar um dia
    # inteiro de uma vez faria a linha do tempo saltar sem necessidade.
    while true; do
        USED_GB=$(du -sm /recordings 2>/dev/null | awk '{print int($1/1024)}')
        FREE_GB=$(df -Pm /recordings 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
        [ -z "$USED_GB" ] && break
        if [ "$USED_GB" -le "$MAX_GB" ] && [ "$FREE_GB" -ge "$MIN_FREE_GB" ]; then break; fi

        OLDEST=$(find /recordings -name "*.mp4" -type f 2>/dev/null | sort | head -1)
        [ -z "$OLDEST" ] && break
        echo "[vigia] espaço: ${USED_GB}GB usados, ${FREE_GB}GB livres — removendo $(basename "$OLDEST")"
        rm -f "$OLDEST"
    done

    # Pastas de dia vazias só poluem a navegação.
    find /recordings -mindepth 2 -type d -empty -delete 2>/dev/null
    sleep $(( CHECK_MINUTES * 60 ))
done

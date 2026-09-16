#!/bin/sh
# Apaga o passado para caber o presente, como um DVR.
#
# Quatro limites agem juntos e o mais restritivo vence: idade máxima, teto de
# espaço, uma folga livre que nunca pode ser consumida, e — se ligado — apagar
# só o que não teve movimento.
#
# A política é relida a cada volta, de um arquivo que a interface escreve.
# Antes ela vinha só do ambiente, e mudar exigia recriar o container: quem
# ajusta retenção quer o efeito agora, não depois de um deploy.
set -u

CONF=/config/retention.conf

carregar() {
    # Padrões: valem na primeira execução e cobrem qualquer chave que o arquivo
    # não traga, para uma configuração incompleta nunca deixar o sistema sem
    # limite nenhum — que é como um disco enche.
    MAX_DAYS=7
    MAX_GB=700
    MIN_FREE_GB=20
    CHECK_MINUTES=10
    ENABLED=1

    # shellcheck disable=SC1090
    [ -f "$CONF" ] && . "$CONF"
}

while true; do
    carregar

    if [ "$ENABLED" = "1" ]; then
        # Idade: remove o que passou do limite de dias.
        find /recordings -name "*.mp4" -type f -mtime "+${MAX_DAYS}" -delete 2>/dev/null

        # Espaço: enquanto estiver acima do teto ou com pouca folga, apaga o
        # mais antigo — um por vez, conferindo de novo a cada remoção. Apagar um
        # dia inteiro de uma vez faria a linha do tempo saltar sem necessidade.
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
    fi

    sleep $(( CHECK_MINUTES * 60 ))
done

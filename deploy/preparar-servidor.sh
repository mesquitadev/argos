#!/bin/bash
# Prepara o servidor antes da primeira execução. Rodar com sudo.
#
# Só o relógio, e não é detalhe: com o servidor em UTC, o ffmpeg carimba o nome
# dos arquivos num fuso e a câmera publica eventos noutro. A linha do tempo
# desenha o mesmo instante em dois lugares e nada denuncia a causa.
set -euo pipefail

FUSO="${1:-America/Fortaleza}"

echo "==> Fuso horário"
timedatectl set-timezone "$FUSO"
# Sem NTP o relógio anda sozinho, e horário de gravação que não bate com a
# realidade torna a busca por um momento específico um chute.
timedatectl set-ntp true
timedatectl | sed -n '1,4p'

echo
echo "Pronto. Os containers recebem o mesmo fuso pela variável TZ no compose;"
echo "sem ela, um container sem tzdata cai para UTC em silêncio."

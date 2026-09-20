#!/bin/bash
# Acerta o fuso do servidor. Rodar com sudo.
#
# A descoberta na rede não está aqui: quem anuncia o gravador é o serviço
# `mdns` do compose, que sobe junto com o stack e não precisa de root. Este
# script cuida só do relógio, que é coisa do sistema.
set -euo pipefail

TZ_DESEJADO="America/Fortaleza"

echo "==> Fuso horário"
# Em UTC, o ffmpeg carimbava o nome dos arquivos três horas à frente da hora
# dos eventos, e as duas pistas da linha do tempo desenhavam o mesmo instante
# em lugares diferentes.
timedatectl set-timezone "$TZ_DESEJADO"
timedatectl set-ntp true
timedatectl | sed -n '1,4p'

echo
echo "==> Agora renomeie o acervo gravado sob o fuso antigo:"
echo "    sudo ./corrige-fuso-arquivos.sh /srv/argos -3"
echo "==> E recrie os containers, para pegarem o fuso novo:"
echo "    docker compose up -d"

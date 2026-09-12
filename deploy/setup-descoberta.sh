#!/bin/bash
# Põe o gravador no ar para a descoberta automática, e acerta o fuso.
#
# Rodar no servidor com sudo. É idempotente: pode rodar de novo sem estragar.
set -euo pipefail

TZ_DESEJADO="America/Fortaleza"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> Fuso horário"
# O servidor estava em UTC, então o ffmpeg carimbava os nomes dos arquivos três
# horas à frente da hora dos eventos — as duas pistas da linha do tempo ficavam
# desalinhadas mostrando o mesmo instante.
timedatectl set-timezone "$TZ_DESEJADO"
timedatectl set-ntp true
timedatectl | sed -n '1,4p'

echo "==> Anúncio na rede (Bonjour/mDNS)"
if ! command -v avahi-daemon >/dev/null; then
    apt-get update -qq && apt-get install -y -qq avahi-daemon avahi-utils
fi
install -m 644 "$DIR/avahi-vigia.service" /etc/avahi/services/vigia.service
systemctl enable --now avahi-daemon
systemctl reload avahi-daemon 2>/dev/null || systemctl restart avahi-daemon

echo "==> Liberando mDNS no firewall"
ufw allow 5353/udp comment "mDNS - descoberta do Vigia" >/dev/null 2>&1 || true

echo "==> Pronto. Anunciado como:"
avahi-browse -ptr _vigia._tcp 2>/dev/null | grep "^=" | head -3 || \
    echo "   (aguarde alguns segundos e rode: avahi-browse -rt _vigia._tcp)"

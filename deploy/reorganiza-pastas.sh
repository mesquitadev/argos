#!/bin/bash
# Move cada gravação para a pasta do dia que o nome indica.
#
# Necessário uma vez: o gravador calculava a data da pasta em shell, o que
# acontecia só ao iniciar, e todas as gravações caíam na pasta do dia em que o
# container subiu. O nome sempre esteve certo; a pasta é que não acompanhava.
#
# Simula por padrão. Use --aplicar para valer.
set -euo pipefail
RAIZ="${1:-/srv/vigia}"
APLICAR="${2:-}"

python3 - "$RAIZ" "$APLICAR" <<'PY'
import os, re, sys
from datetime import datetime, timedelta

raiz, aplicar = sys.argv[1], sys.argv[2] == "--aplicar"
padrao = re.compile(r"^(.+)_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})\.mp4$")
# O arquivo mais novo está sendo escrito agora: mover puxaria o chão do ffmpeg.
corte = datetime.now() - timedelta(minutes=10)
movidos = ok = 0

for pasta, _, arquivos in os.walk(raiz):
    for nome in sorted(arquivos):
        m = padrao.match(nome)
        if not m:
            continue
        dia = m.group(2)
        quando = datetime.strptime(f"{dia}_{m.group(3)}", "%Y-%m-%d_%H-%M-%S")
        if quando > corte:
            continue
        if os.path.basename(pasta) == dia:
            ok += 1
            continue

        destino_dir = os.path.join(os.path.dirname(pasta), dia)
        destino = os.path.join(destino_dir, nome)
        if aplicar:
            os.makedirs(destino_dir, exist_ok=True)
            if not os.path.exists(destino):
                os.rename(os.path.join(pasta, nome), destino)
        movidos += 1

print(f"{movidos} a mover, {ok} já no lugar" + ("" if aplicar else "  — SIMULAÇÃO"))
PY

if [ "$APLICAR" = "--aplicar" ]; then
    find "$RAIZ" -mindepth 2 -type d -empty -delete 2>/dev/null || true
fi

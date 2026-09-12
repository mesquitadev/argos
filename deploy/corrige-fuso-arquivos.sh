#!/bin/bash
# Renomeia as gravações feitas enquanto o servidor estava em UTC.
#
# Precisa acontecer junto com a troca de fuso. A retenção escolhe "o mais
# antigo" ordenando por nome: deixar arquivos UTC (00-xx) convivendo com
# arquivos locais (21-xx) faria os novos parecerem os mais velhos, e o DVR
# apagaria justamente o que acabou de gravar.
set -euo pipefail

RAIZ="${1:-/srv/vigia}"
HORAS="${2:--3}"

python3 - "$RAIZ" "$HORAS" <<'PY'
import os, re, sys
from datetime import datetime, timedelta

raiz, horas = sys.argv[1], int(sys.argv[2])
padrao = re.compile(r"^(.+)_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})\.mp4$")
movidos = 0

for pasta, _, arquivos in os.walk(raiz):
    for nome in arquivos:
        m = padrao.match(nome)
        if not m:
            continue
        camera, dia, hora = m.groups()
        quando = datetime.strptime(f"{dia}_{hora}", "%Y-%m-%d_%H-%M-%S") + timedelta(hours=horas)
        novo_dia = quando.strftime("%Y-%m-%d")
        novo_nome = f"{camera}_{quando.strftime('%Y-%m-%d_%H-%M-%S')}.mp4"

        destino_dir = os.path.join(os.path.dirname(pasta), novo_dia)
        os.makedirs(destino_dir, exist_ok=True)
        destino = os.path.join(destino_dir, novo_nome)
        if os.path.exists(destino):
            continue
        os.rename(os.path.join(pasta, nome), destino)
        movidos += 1
        print(f"  {nome} -> {novo_dia}/{novo_nome}")

print(f"{movidos} gravações reposicionadas")
PY

find "$RAIZ" -mindepth 2 -type d -empty -delete 2>/dev/null || true

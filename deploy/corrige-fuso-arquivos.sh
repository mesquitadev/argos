#!/bin/bash
# Corrige o horário no nome das gravações.
#
# Uso:  ./corrige-fuso-arquivos.sh [RAIZ] [HORAS]        # simula, não muda nada
#       ./corrige-fuso-arquivos.sh [RAIZ] [HORAS] --aplicar
#
# HORAS é quanto o nome está ADIANTADO e será subtraído; é sempre positivo.
# Simular por padrão é proposital: um sinal trocado aqui move o acervo inteiro
# para o lado errado, e foi o que já aconteceu uma vez.
#
# Só mexe em arquivo cujo nome aponta para o futuro. Gravação com nome correto
# está sempre no passado, então esse teste separa sozinho o que já está certo —
# inclusive o que o gravador escreveu depois do fuso ter sido acertado.
set -euo pipefail

RAIZ="${1:-/srv/vigia}"
HORAS="${2:-6}"
APLICAR="${3:-}"

python3 - "$RAIZ" "$HORAS" "$APLICAR" <<'PY'
import os, re, sys
from datetime import datetime, timedelta

raiz, horas, aplicar = sys.argv[1], abs(int(sys.argv[2])), sys.argv[3] == "--aplicar"
padrao = re.compile(r"^(.+)_(\d{4}-\d{2}-\d{2})_(\d{2}-\d{2}-\d{2})\.mp4$")
limite = datetime.now() + timedelta(minutes=1)
mudar = []
ok = 0

for pasta, _, arquivos in os.walk(raiz):
    for nome in sorted(arquivos):
        m = padrao.match(nome)
        if not m:
            continue
        camera, dia, hora = m.groups()
        no_nome = datetime.strptime(f"{dia}_{hora}", "%Y-%m-%d_%H-%M-%S")
        if no_nome <= limite:
            ok += 1
            continue
        certo = no_nome - timedelta(hours=horas)
        mudar.append((os.path.join(pasta, nome), camera, certo, nome))

for origem, camera, certo, nome in mudar:
    novo_nome = f"{camera}_{certo.strftime('%Y-%m-%d_%H-%M-%S')}.mp4"
    destino_dir = os.path.join(os.path.dirname(os.path.dirname(origem)),
                               certo.strftime("%Y-%m-%d"))
    destino = os.path.join(destino_dir, novo_nome)
    print(f"  {nome}  ->  {certo.strftime('%Y-%m-%d')}/{novo_nome}")
    if aplicar:
        os.makedirs(destino_dir, exist_ok=True)
        if os.path.exists(destino):
            print("     (destino ja existe, pulando)")
            continue
        os.rename(origem, destino)

print()
print(f"{len(mudar)} a corrigir, {ok} ja corretas")
if not aplicar and mudar:
    print("SIMULACAO - nada foi alterado. Repita com --aplicar para valer.")
PY

if [ "$APLICAR" = "--aplicar" ]; then
    find "$RAIZ" -mindepth 2 -type d -empty -delete 2>/dev/null || true
fi

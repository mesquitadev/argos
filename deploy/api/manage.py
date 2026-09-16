"""Administração de usuários do Vigia.

Existe porque trocar senha por comando de uma linha com Python embutido é
frágil: qualquer indentação acidental ao colar quebra, e a senha passa pelo
histórico do shell. Aqui ela é digitada sem eco e não fica em lugar nenhum.

Uso:
    docker exec -it vigia-api python3 /api/manage.py listar
    docker exec -it vigia-api python3 /api/manage.py senha <usuário>
    docker exec -it vigia-api python3 /api/manage.py criar <usuário> [--leitura]
    docker exec -it vigia-api python3 /api/manage.py remover <usuário>
"""
from __future__ import annotations

import getpass
import json
import os
import sys
from pathlib import Path

import auth

USERS_FILE = Path(os.environ.get("USERS_FILE", "/config/users.json"))


def load() -> dict:
    return json.loads(USERS_FILE.read_text()) if USERS_FILE.exists() else {}


def save(users: dict) -> None:
    USERS_FILE.parent.mkdir(parents=True, exist_ok=True)
    USERS_FILE.write_text(json.dumps(users, indent=2))
    USERS_FILE.chmod(0o600)


def ask_password(user: str) -> str | None:
    first = getpass.getpass(f"Nova senha para {user}: ")
    if len(first) < 8:
        print("A senha precisa de pelo menos 8 caracteres.")
        return None
    if first != getpass.getpass("Repita: "):
        print("As senhas não conferem.")
        return None
    return first


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 1

    command, rest = args[0], args[1:]
    users = load()

    if command == "listar":
        if not users:
            print("Nenhum usuário.")
        for name, data in users.items():
            print(f"  {name}  ({data.get('role', 'admin')})")
        return 0

    if command in {"senha", "criar"} and rest:
        user = rest[0]
        if command == "senha" and user not in users:
            print(f"Usuário '{user}' não existe.")
            return 1
        if command == "criar" and user in users:
            print(f"Usuário '{user}' já existe — use 'senha' para trocar.")
            return 1

        password = ask_password(user)
        if not password:
            return 1

        role = "leitura" if "--leitura" in rest else users.get(user, {}).get("role", "admin")
        users[user] = {"password": auth.hash_password(password), "role": role}
        save(users)
        print(f"Pronto: {user} ({role}).")
        # A senha inicial do ambiente só é usada quando não há usuário nenhum,
        # mas deixá-la desatualizada no .env confunde quem for ler depois.
        print("Lembre de atualizar ADMIN_PASSWORD no .env, se for este o usuário inicial.")
        return 0

    if command == "remover" and rest:
        user = rest[0]
        if user not in users:
            print(f"Usuário '{user}' não existe.")
            return 1
        if len(users) == 1:
            print("Este é o único usuário; remover deixaria o sistema sem acesso.")
            return 1
        del users[user]
        save(users)
        print(f"Removido: {user}.")
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

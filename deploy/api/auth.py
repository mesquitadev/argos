"""Sessão e senha.

Cookie assinado em vez de sessão guardada no servidor: reiniciar o container
não desloga ninguém, e não há estado para sincronizar se um dia houver mais de
uma instância. O preço é não conseguir revogar uma sessão específica — aceitável
numa casa, onde trocar a senha invalida todas de uma vez.
"""
# Anotações adiadas: o container roda 3.12, mas ferramentas locais podem ser
# mais antigas, e um arquivo que só carrega numa versão é armadilha.
from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import time

# Um dia sem mexer desloga. Curto o bastante para um aparelho esquecido não
# ficar aberto para sempre, longo o bastante para não pedir senha toda hora.
SESSION_SECONDS = 86400 * 7

SECRET = os.environ.get("SESSION_SECRET", "").encode() or secrets.token_bytes(32)
COOKIE = "argos_session"


def hash_password(password: str, salt: bytes | None = None) -> str:
    """Deriva a senha com scrypt.

    Não é um hash rápido de propósito: se o arquivo vazar, quem pegar precisa
    gastar tempo real por tentativa, em vez de testar bilhões por segundo.
    """
    salt = salt or secrets.token_bytes(16)
    key = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return f"scrypt${base64.b64encode(salt).decode()}${base64.b64encode(key).decode()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        kind, salt_b64, key_b64 = stored.split("$")
        if kind != "scrypt":
            return False
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(key_b64)
        key = hashlib.scrypt(password.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
        # Comparação em tempo constante: comparar com `==` vaza, pelo tempo,
        # quantos bytes iniciais estavam certos.
        return hmac.compare_digest(key, expected)
    except Exception:
        return False


def issue(username: str, role: str = "admin") -> str:
    payload = {"u": username, "r": role, "exp": int(time.time()) + SESSION_SECONDS}
    raw = json.dumps(payload, separators=(",", ":")).encode()
    body = base64.urlsafe_b64encode(raw).rstrip(b"=")
    sig = hmac.new(SECRET, body, hashlib.sha256).digest()
    return f"{body.decode()}.{base64.urlsafe_b64encode(sig).rstrip(b'=').decode()}"


def read(token: str) -> dict | None:
    """Valida o cookie. Devolve o conteúdo, ou None se for inválido ou vencido."""
    try:
        body, sig = token.split(".")
        expected = hmac.new(SECRET, body.encode(), hashlib.sha256).digest()
        given = base64.urlsafe_b64decode(sig + "=" * (-len(sig) % 4))
        if not hmac.compare_digest(expected, given):
            return None
        payload = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
        if payload.get("exp", 0) < time.time():
            return None
        return payload
    except Exception:
        return None


def cookie_header(token: str, secure: bool = False) -> str:
    # HttpOnly para o JavaScript da página não conseguir ler o cookie: se algum
    # dia houver XSS, o token não vai junto. SameSite=Lax barra o cookie em
    # requisições vindas de outro site.
    flags = "HttpOnly; SameSite=Lax; Path=/; Max-Age=" + str(SESSION_SECONDS)
    if secure:
        flags += "; Secure"
    return f"{COOKIE}={token}; {flags}"

"""Пароли, токены и ограничение числа попыток.

* Пароль хранится как scrypt-хэш со случайной солью (стандартная библиотека Python).
* Токен доступа — JWT на 1 час (подписан SECRET_KEY), токен обновления — случайная строка
  на 180 дней; в базе хранится только её SHA-256, поэтому утечка базы не даёт войти.
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import uuid
from datetime import datetime, timedelta, timezone

import jwt

from app.config import get_settings
from app.redis_client import get_redis

ACCESS_TTL = timedelta(hours=1)
REFRESH_TTL = timedelta(days=180)

_SCRYPT_N, _SCRYPT_R, _SCRYPT_P = 2**14, 8, 1


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P, dklen=32)
    b64 = lambda b: base64.b64encode(b).decode()  # noqa: E731
    return f"scrypt${_SCRYPT_N}${_SCRYPT_R}${_SCRYPT_P}${b64(salt)}${b64(digest)}"


def verify_password(password: str, stored: str | None) -> bool:
    if not stored:
        return False
    try:
        algo, n, r, p, salt_b64, digest_b64 = stored.split("$")
        if algo != "scrypt":
            return False
        salt, expected = base64.b64decode(salt_b64), base64.b64decode(digest_b64)
        got = hashlib.scrypt(password.encode(), salt=salt, n=int(n), r=int(r), p=int(p), dklen=len(expected))
        return hmac.compare_digest(got, expected)
    except (ValueError, TypeError):
        return False


def create_access_token(player_id: uuid.UUID) -> str:
    now = datetime.now(timezone.utc)
    payload = {"sub": str(player_id), "iat": now, "exp": now + ACCESS_TTL, "typ": "access"}
    return jwt.encode(payload, get_settings().secret_key, algorithm="HS256")


def decode_access_token(token: str) -> uuid.UUID | None:
    try:
        payload = jwt.decode(token, get_settings().secret_key, algorithms=["HS256"])
        if payload.get("typ") != "access":
            return None
        return uuid.UUID(payload["sub"])
    except (jwt.PyJWTError, ValueError, KeyError):
        return None


def new_refresh_token() -> tuple[str, str]:
    """Вернуть (токен для клиента, хэш для базы)."""
    token = secrets.token_urlsafe(48)
    return token, hash_refresh(token)


def hash_refresh(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class RateLimited(Exception):
    def __init__(self, retry_after: int):
        super().__init__(retry_after)
        self.retry_after = retry_after


async def check_rate_limit(key: str, limit: int, window_seconds: int) -> None:
    """Счётчик в Redis: не больше limit попыток за window_seconds. Иначе — RateLimited."""
    redis = get_redis()
    full = f"rl:{key}"
    count = await redis.incr(full)
    if count == 1:
        await redis.expire(full, window_seconds)
    if count > limit:
        ttl = await redis.ttl(full)
        raise RateLimited(max(ttl, 1))


async def reset_rate_limit(key: str) -> None:
    await get_redis().delete(f"rl:{key}")

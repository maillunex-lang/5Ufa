"""Вход в админку: пароль (scrypt), токены сессий (в базе только хэш), лимит неудачных попыток, TOTP (2FA).

Пароли и ключи нигде в коде не хранятся: админ создаётся командой на VPS (python -m app.cli admin create).
"""
from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
import struct
import time
from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import client_ip
from app.config import get_settings
from app.db import get_session
from app.models import AdminAudit, AdminSession, AdminUser
from app.redis_client import get_redis

TOKEN_PREFIX = "adm_"


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def new_token() -> str:
    return TOKEN_PREFIX + secrets.token_urlsafe(32)


# --- Лимит неудачных попыток: считаем только ошибки ---------------------------------

async def locked_for(key: str) -> int:
    """Сколько секунд ещё действует блокировка (0 — можно пробовать)."""
    s = get_settings()
    redis = get_redis()
    count = int(await redis.get(f"adm_fail:{key}") or 0)
    if count >= s.admin_login_attempts:
        return max(1, int(await redis.ttl(f"adm_fail:{key}")))
    return 0


async def register_failure(key: str) -> None:
    s = get_settings()
    redis = get_redis()
    n = await redis.incr(f"adm_fail:{key}")
    if n == 1:
        await redis.expire(f"adm_fail:{key}", s.admin_login_window)


async def clear_failures(key: str) -> None:
    await get_redis().delete(f"adm_fail:{key}")


# --- TOTP (RFC 6238): 6 цифр, шаг 30 с, допускаем соседний шаг ----------------------

def totp_new_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode().rstrip("=")


def totp_code(secret: str, step: int) -> str:
    key = base64.b32decode(secret + "=" * (-len(secret) % 8))
    digest = hmac.new(key, struct.pack(">Q", step), hashlib.sha1).digest()
    off = digest[-1] & 0x0F
    value = (struct.unpack(">I", digest[off:off + 4])[0] & 0x7FFFFFFF) % 1_000_000
    return f"{value:06d}"


def totp_verify(secret: str, code: str, now: float | None = None) -> bool:
    code = (code or "").strip().replace(" ", "")
    if len(code) != 6 or not code.isdigit():
        return False
    step = int((now or time.time()) // 30)
    return any(hmac.compare_digest(totp_code(secret, step + d), code) for d in (-1, 0, 1))


def totp_uri(secret: str, login: str) -> str:
    return f"otpauth://totp/UfaGame%20admin:{login}?secret={secret}&issuer=UfaGame%20admin&digits=6&period=30"


# --- Журнал --------------------------------------------------------------------------

async def audit(session: AsyncSession, request: Request | None, admin: AdminUser | None, action: str,
                summary: str = "", details: dict | None = None, login: str = "") -> None:
    session.add(AdminAudit(
        admin_id=admin.id if admin else None, login=admin.login if admin else login, action=action,
        summary=summary[:2000], details=details or {}, ip=client_ip(request) if request else "",
    ))
    await session.flush()


# --- Текущий администратор ----------------------------------------------------------

def _bearer(request: Request) -> str:
    header = request.headers.get("authorization", "")
    return header[7:].strip() if header.lower().startswith("bearer ") else ""


async def current_admin(request: Request, session: AsyncSession = Depends(get_session)) -> AdminUser:
    token = _bearer(request)
    if not token.startswith(TOKEN_PREFIX):
        raise HTTPException(401, "Нужно войти в админку")
    row = (await session.execute(select(AdminSession).where(AdminSession.token_hash == token_hash(token)))).scalar_one_or_none()
    now = datetime.now(timezone.utc)
    limit = timedelta(days=get_settings().admin_session_days)
    if row is None:
        raise HTTPException(401, "Сессия не найдена — войдите заново")
    last = row.last_seen_at.replace(tzinfo=row.last_seen_at.tzinfo or timezone.utc)
    if now - last > limit:
        await session.delete(row)
        await session.commit()
        raise HTTPException(401, "Сессия истекла — войдите заново")
    admin = await session.get(AdminUser, row.admin_id)
    if admin is None or admin.disabled:
        raise HTTPException(401, "Администратор отключён")
    if now - last > timedelta(minutes=1):
        row.last_seen_at = now  # продлеваем сессию не чаще раза в минуту
    request.state.admin_session_id = row.id
    return admin


def require_role(*roles: str):
    """Зависимость: owner может всё; остальные — только перечисленные роли."""
    async def dep(admin: AdminUser = Depends(current_admin)) -> AdminUser:
        if admin.role != "owner" and admin.role not in roles:
            raise HTTPException(403, "Недостаточно прав для этого раздела")
        return admin
    return dep

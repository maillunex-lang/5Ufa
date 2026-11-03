"""Аккаунты: вход гостем, привязка почты, вход по почте, обновление токена, профиль."""
from __future__ import annotations

import re
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import client_ip, current_player, ensure_not_banned
from app.auth.security import (
    REFRESH_TTL,
    RateLimited,
    check_rate_limit,
    create_access_token,
    hash_password,
    hash_refresh,
    new_refresh_token,
    reset_rate_limit,
    verify_password,
)
from app.db import get_session
from app.models import Player, PlayerSession, utcnow

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

# Лимиты попыток входа (за 15 минут)
LOGIN_WINDOW = 15 * 60
LOGIN_LIMIT_PER_IP = 20
LOGIN_LIMIT_PER_EMAIL = 5
GUEST_LIMIT_PER_IP = 30


class DeviceInfo(BaseModel):
    device_id: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_\-]+$")
    client_version: str = Field(default="", max_length=32)


class EmailLogin(DeviceInfo):
    email: str = Field(max_length=254)
    password: str = Field(max_length=128)


class LinkEmail(BaseModel):
    email: str = Field(max_length=254)
    password: str = Field(max_length=128)


class RefreshIn(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=200)


def player_public(p: Player) -> dict:
    return {
        "id": str(p.id),
        "number": p.number,
        "display_name": p.display_name,
        "is_guest": p.is_guest,
        "email": p.email,
        "is_test": p.is_test,
        "created_at": p.created_at.isoformat() if p.created_at else None,
    }


def _too_many(e: RateLimited) -> HTTPException:
    minutes = max(1, (e.retry_after + 59) // 60)
    return HTTPException(429, f"Слишком много попыток. Попробуйте через {minutes} мин.",
                         headers={"Retry-After": str(e.retry_after)})


def _normalize_email(email: str) -> str:
    email = email.strip().lower()
    if not EMAIL_RE.match(email):
        raise HTTPException(422, "Неверный формат почты")
    return email


def _check_password(password: str) -> None:
    if len(password) < 8:
        raise HTTPException(422, "Пароль должен быть не короче 8 символов")
    if password.isdigit() or password.isalpha():
        raise HTTPException(422, "Пароль должен содержать и буквы, и цифры")


async def _issue_tokens(session: AsyncSession, player: Player, device: DeviceInfo, ip: str) -> dict:
    token, token_hash = new_refresh_token()
    session.add(PlayerSession(
        player_id=player.id, device_id=device.device_id, refresh_hash=token_hash,
        expires_at=datetime.now(timezone.utc) + REFRESH_TTL,
        client_version=device.client_version, ip=ip,
    ))
    player.last_login_at = utcnow()
    await session.commit()
    return {
        "access_token": create_access_token(player.id),
        "refresh_token": token,
        "expires_in": 3600,
        "player": player_public(player),
    }


async def _new_guest(session: AsyncSession) -> Player:
    for _ in range(5):
        number = ((await session.execute(select(func.max(Player.number)))).scalar() or 1000) + 1
        player = Player(number=number, display_name=f"Путник-{number}")
        session.add(player)
        try:
            await session.flush()
            return player
        except IntegrityError:
            await session.rollback()
    raise HTTPException(503, "Не удалось создать аккаунт, попробуйте ещё раз")


@router.post("/guest")
async def guest_login(body: DeviceInfo, request: Request, session: AsyncSession = Depends(get_session)):
    """Вход гостем. Если на этом устройстве уже есть гостевой аккаунт — возвращается он."""
    ip = client_ip(request)
    try:
        await check_rate_limit(f"guest:ip:{ip}", GUEST_LIMIT_PER_IP, LOGIN_WINDOW)
    except RateLimited as e:
        raise _too_many(e)
    existing = (await session.execute(
        select(Player).join(PlayerSession, PlayerSession.player_id == Player.id)
        .where(PlayerSession.device_id == body.device_id, Player.email.is_(None))
        .order_by(PlayerSession.created_at.desc()).limit(1)
    )).scalar_one_or_none()
    player = existing or await _new_guest(session)
    ensure_not_banned(player)
    return await _issue_tokens(session, player, body, ip)


@router.post("/login")
async def email_login(body: EmailLogin, request: Request, session: AsyncSession = Depends(get_session)):
    """Вход по почте и паролю (например, на новом телефоне)."""
    ip = client_ip(request)
    email = _normalize_email(body.email)
    try:
        await check_rate_limit(f"login:ip:{ip}", LOGIN_LIMIT_PER_IP, LOGIN_WINDOW)
        await check_rate_limit(f"login:email:{email}", LOGIN_LIMIT_PER_EMAIL, LOGIN_WINDOW)
    except RateLimited as e:
        raise _too_many(e)
    player = (await session.execute(select(Player).where(Player.email == email))).scalar_one_or_none()
    if player is None or not verify_password(body.password, player.password_hash):
        raise HTTPException(401, "Неверная почта или пароль")
    ensure_not_banned(player)
    await reset_rate_limit(f"login:email:{email}")
    return await _issue_tokens(session, player, body, ip)


@router.post("/refresh")
async def refresh(body: RefreshIn, session: AsyncSession = Depends(get_session)):
    """Обменять токен обновления на новую пару токенов (старый токен становится недействительным)."""
    sess = (await session.execute(
        select(PlayerSession).where(PlayerSession.refresh_hash == hash_refresh(body.refresh_token))
    )).scalar_one_or_none()
    now = datetime.now(timezone.utc)
    if sess is None or sess.revoked or sess.expires_at.replace(tzinfo=sess.expires_at.tzinfo or timezone.utc) < now:
        raise HTTPException(401, "Сессия истекла, выполните вход заново")
    player = await session.get(Player, sess.player_id)
    if player is None:
        raise HTTPException(401, "Аккаунт не найден")
    ensure_not_banned(player)
    token, token_hash = new_refresh_token()
    sess.refresh_hash = token_hash
    sess.expires_at = now + REFRESH_TTL
    player.last_login_at = utcnow()
    await session.commit()
    return {"access_token": create_access_token(player.id), "refresh_token": token,
            "expires_in": 3600, "player": player_public(player)}


@router.post("/link-email")
async def link_email(body: LinkEmail, player: Player = Depends(current_player),
                     session: AsyncSession = Depends(get_session)):
    """Привязать почту и пароль к гостевому аккаунту — после этого прогресс можно перенести."""
    if not player.is_guest:
        raise HTTPException(409, "К этому аккаунту уже привязана почта")
    email = _normalize_email(body.email)
    _check_password(body.password)
    if (await session.execute(select(Player.id).where(Player.email == email))).first():
        raise HTTPException(409, "Эта почта уже привязана к другому аккаунту")
    player = await session.merge(player)
    player.email = email
    player.password_hash = hash_password(body.password)
    try:
        await session.commit()
    except IntegrityError:
        raise HTTPException(409, "Эта почта уже привязана к другому аккаунту")
    return {"player": player_public(player)}


@router.post("/logout")
async def logout(body: RefreshIn, session: AsyncSession = Depends(get_session)):
    sess = (await session.execute(
        select(PlayerSession).where(PlayerSession.refresh_hash == hash_refresh(body.refresh_token))
    )).scalar_one_or_none()
    if sess:
        sess.revoked = True
        await session.commit()
    return JSONResponse({"ok": True})


me_router = APIRouter(prefix="/api/v1", tags=["player"])


@me_router.get("/me")
async def me(player: Player = Depends(current_player)):
    return {"player": player_public(player), "server_time": datetime.now(timezone.utc).isoformat()}

"""Зависимости FastAPI: текущий игрок по заголовку Authorization: Bearer <токен>."""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import Depends, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.security import decode_access_token
from app.db import get_session
from app.models import Player


def _bearer(request: Request) -> str | None:
    header = request.headers.get("authorization", "")
    if header.lower().startswith("bearer "):
        return header[7:].strip()
    return None


def ensure_not_banned(player: Player) -> None:
    if player.banned_until and player.banned_until.replace(tzinfo=player.banned_until.tzinfo or timezone.utc) > datetime.now(timezone.utc):
        until = player.banned_until.strftime("%d.%m.%Y %H:%M")
        reason = f" Причина: {player.ban_reason}." if player.ban_reason else ""
        raise HTTPException(403, f"Аккаунт заблокирован до {until} (UTC).{reason}")


async def optional_player(request: Request, session: AsyncSession = Depends(get_session)) -> Player | None:
    token = _bearer(request)
    if not token:
        return None
    player_id = decode_access_token(token)
    if player_id is None:
        return None
    return await session.get(Player, player_id)


async def current_player(request: Request, session: AsyncSession = Depends(get_session)) -> Player:
    token = _bearer(request)
    if not token:
        raise HTTPException(401, "Нужно войти в игру")
    player_id = decode_access_token(token)
    if player_id is None:
        raise HTTPException(401, "Сессия истекла, выполните вход заново")
    player = await session.get(Player, player_id)
    if player is None:
        raise HTTPException(401, "Аккаунт не найден")
    ensure_not_banned(player)
    return player


def client_ip(request: Request) -> str:
    return request.client.host if request.client else ""

"""API админки, этап 6б: игроки, бэкапы, версии APK игры, загрузка веб-версии админки.

Игроки — роль moderator (и owner); бэкапы и версии APK — только owner. Всё пишется в журнал.
"""
from __future__ import annotations

import io
import os
import re
import shutil
import uuid
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.admin.security import audit, require_role
from app.config import get_settings
from app.db import get_session
from app.models import (AdminUser, CampaignProgress, ClientRelease, Player, PlayerHero, PlayerItem, PlayerSession,
                        WalletEntry)
from app.progression import wallet

router = APIRouter(prefix="/api/v1/admin", tags=["admin"])
moderator = require_role("moderator")
owner_only = require_role()

MAX_AMOUNT = 10**12


def _player_brief(p: Player) -> dict:
    now = datetime.now(timezone.utc)
    banned = p.banned_until is not None and p.banned_until.replace(tzinfo=p.banned_until.tzinfo or timezone.utc) > now
    return {"id": str(p.id), "number": p.number, "name": p.display_name, "email": p.email, "is_test": p.is_test,
            "banned_until": p.banned_until.isoformat() if banned else None, "ban_reason": p.ban_reason if banned else "",
            "created_at": p.created_at.isoformat(), "last_login_at": p.last_login_at.isoformat() if p.last_login_at else None}


async def _get_player(session: AsyncSession, player_id: str) -> Player:
    try:
        p = await session.get(Player, uuid.UUID(player_id))
    except ValueError:
        p = None
    if p is None:
        raise HTTPException(404, "Игрок не найден")
    return p


# --- Игроки ---------------------------------------------------------------------------

@router.get("/players")
async def players(q: str = Query("", max_length=100), limit: int = Query(30, ge=1, le=100),
                  admin: AdminUser = Depends(moderator), session: AsyncSession = Depends(get_session)):
    """Поиск: номер (#1001 или 1001), часть имени или почты. Пусто — последние игроки."""
    stmt = select(Player).order_by(Player.number.desc()).limit(limit)
    q = q.strip()
    if q:
        conds = [func.lower(Player.display_name).contains(q.lower()), func.lower(Player.email).contains(q.lower())]
        num = q.lstrip("#")
        if num.isdigit():
            conds.append(Player.number == int(num))
        stmt = stmt.where(or_(*conds))
    rows = (await session.execute(stmt)).scalars()
    return {"items": [_player_brief(p) for p in rows]}


@router.get("/players/{player_id}")
async def player_card(player_id: str, admin: AdminUser = Depends(moderator), session: AsyncSession = Depends(get_session)):
    p = await _get_player(session, player_id)
    heroes = list((await session.execute(select(PlayerHero).where(PlayerHero.player_id == p.id)
                                         .order_by(PlayerHero.level.desc()))).scalars())
    items = int((await session.execute(select(func.count()).select_from(PlayerItem)
                                       .where(PlayerItem.player_id == p.id))).scalar_one())
    progress = await session.get(CampaignProgress, p.id)
    sessions = int((await session.execute(select(func.count()).select_from(PlayerSession)
                                          .where(PlayerSession.player_id == p.id))).scalar_one())
    return {**_player_brief(p), "wallet": await wallet.balances(session, p.id),
            "heroes": [{"id": h.id, "hero": h.hero_id, "tier": h.tier, "level": h.level, "crystal": h.crystal_slot is not None,
                        "signature": h.signature_level} for h in heroes],
            "items": items, "campaign_cleared": progress.cleared if progress else 0, "sessions": sessions}


class WalletIn(BaseModel):
    changes: dict[str, int] = Field(description="код валюты -> сколько добавить (минус — списать)")
    reason: str = Field(min_length=3, max_length=500)


@router.post("/players/{player_id}/wallet")
async def change_wallet(player_id: str, body: WalletIn, request: Request,
                        admin: AdminUser = Depends(moderator), session: AsyncSession = Depends(get_session)):
    from app.progression.heroes import lock_player
    p = await _get_player(session, player_id)
    changes = {k: int(v) for k, v in body.changes.items() if int(v) != 0}
    if not changes:
        raise HTTPException(422, "Укажите, сколько добавить или списать")
    for code, v in changes.items():
        if not re.fullmatch(r"[a-z][a-z0-9_]{0,47}", code):
            raise HTTPException(422, f"Неверный код валюты «{code}»")
        if abs(v) > MAX_AMOUNT:
            raise HTTPException(422, f"Слишком большое число для «{code}»")
    await lock_player(session, p.id)
    before = await wallet.balances(session, p.id)
    await wallet.spend(session, p.id, {k: -v for k, v in changes.items() if v < 0})  # не уйти в минус
    await wallet.add(session, p.id, {k: v for k, v in changes.items() if v > 0})
    after = await wallet.balances(session, p.id)
    text = ", ".join(f"{wallet.currency_name(k)} {'+' if v > 0 else ''}{v}" for k, v in changes.items())
    await audit(session, request, admin, "player_wallet", f"Игрок #{p.number}: {text}. Причина: {body.reason}",
                {"player": str(p.id), "number": p.number, "changes": changes, "reason": body.reason,
                 "before": {k: before.get(k, 0) for k in changes}, "after": {k: after.get(k, 0) for k in changes}})
    await session.commit()
    return {"ok": True, "wallet": after}


class TestIn(BaseModel):
    on: bool


@router.post("/players/{player_id}/test")
async def set_test(player_id: str, body: TestIn, request: Request,
                   admin: AdminUser = Depends(moderator), session: AsyncSession = Depends(get_session)):
    p = await _get_player(session, player_id)
    p.is_test = body.on
    await audit(session, request, admin, "player_test",
                f"Игрок #{p.number}: {'тестовый аккаунт (видит канал test)' if body.on else 'обычный аккаунт'}",
                {"player": str(p.id), "number": p.number, "on": body.on})
    await session.commit()
    return {"ok": True, "player": _player_brief(p)}


class BanIn(BaseModel):
    days: int = Field(ge=0, le=36500, description="0 — снять бан")
    reason: str = Field(default="", max_length=500)


@router.post("/players/{player_id}/ban")
async def ban(player_id: str, body: BanIn, request: Request,
              admin: AdminUser = Depends(moderator), session: AsyncSession = Depends(get_session)):
    p = await _get_player(session, player_id)
    if body.days == 0:
        p.banned_until, p.ban_reason = None, ""
        summary = f"Игрок #{p.number}: бан снят"
    else:
        if len(body.reason.strip()) < 3:
            raise HTTPException(422, "Укажите причину бана")
        p.banned_until = datetime.now(timezone.utc) + timedelta(days=body.days)
        p.ban_reason = body.reason.strip()
        summary = f"Игрок #{p.number}: бан на {body.days} дн. Причина: {p.ban_reason}"
    await audit(session, request, admin, "player_ban", summary,
                {"player": str(p.id), "number": p.number, "days": body.days, "reason": body.reason})
    await session.commit()
    return {"ok": True, "player": _player_brief(p)}


# --- Бэкапы -------------------------------------------------------------------------------

def _backup_dir() -> Path:
    return get_settings().backup_dir


def _dir_size(path: Path) -> int:
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file())


@router.get("/backups")
async def backups(admin: AdminUser = Depends(owner_only)):
    root = _backup_dir()
    items = []
    if root.is_dir():
        for d in sorted((p for p in root.iterdir() if p.is_dir() and p.name.startswith("20")), reverse=True):
            items.append({"name": d.name, "size": _dir_size(d), "complete": (d / "SHA256SUMS").is_file(),
                          "at": datetime.fromtimestamp(d.stat().st_mtime, timezone.utc).isoformat()})
    status = (root / ".last_result").read_text(encoding="utf-8").strip() if (root / ".last_result").is_file() else ""
    return {"available": root.is_dir(), "items": items, "pending": (root / ".requests" / "run").is_file(), "last_result": status,
            "restore_command": "cd ~/ufagame && bash scripts/restore.sh <имя_папки>",
            "retention_days": int(os.environ.get("BACKUP_RETENTION_DAYS", "14"))}


@router.post("/backups/run")
async def backup_run(request: Request, admin: AdminUser = Depends(owner_only), session: AsyncSession = Depends(get_session)):
    """Попросить сервис бэкапов сделать копию сейчас (он проверяет запрос каждые 30 секунд)."""
    req = _backup_dir() / ".requests"
    if not req.is_dir():
        raise HTTPException(503, "Сервис бэкапов ещё не готов (нет папки запросов). Перезапустите его: docker compose up -d backup")
    (req / "run").write_text(datetime.now(timezone.utc).isoformat() + " " + admin.login, encoding="utf-8")
    await audit(session, request, admin, "backup_request", "Запрошен бэкап вручную")
    await session.commit()
    return {"ok": True, "message": "Бэкап начнётся в течение 30 секунд. Обновите список через минуту."}


# --- Версии APK игры ----------------------------------------------------------------------

@router.get("/client-releases")
async def client_releases(admin: AdminUser = Depends(owner_only), session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(select(ClientRelease).order_by(ClientRelease.version_code.desc()).limit(50))).scalars()
    return {"items": [{"code": r.version_code, "name": r.version_name, "size": r.size, "active": r.active,
                       "mandatory": r.mandatory, "notes": r.notes, "at": r.created_at.isoformat()} for r in rows]}


class ClientSetIn(BaseModel):
    active: bool | None = None
    mandatory: bool | None = None


@router.post("/client-releases/{code}")
async def client_release_set(code: int, body: ClientSetIn, request: Request,
                             admin: AdminUser = Depends(owner_only), session: AsyncSession = Depends(get_session)):
    r = (await session.execute(select(ClientRelease).where(ClientRelease.version_code == code))).scalar_one_or_none()
    if r is None:
        raise HTTPException(404, f"Версия с кодом {code} не найдена")
    if body.active is not None:
        r.active = body.active
        if not body.active:
            r.mandatory = False
    if body.mandatory is not None:
        r.mandatory = body.mandatory and r.active
    await audit(session, request, admin, "client_release",
                f"APK {r.version_name}: {'включена' if r.active else 'выключена'}{', обязательная' if r.mandatory else ''}",
                {"code": code, "active": r.active, "mandatory": r.mandatory})
    await session.commit()
    return {"ok": True}


# --- Веб-версия админки (загружает GitHub Actions) -------------------------------------------

web_router = APIRouter(prefix="/api/v1/admin-web", tags=["admin"])


@web_router.put("/{version}")
async def upload_admin_web(version: str, request: Request, x_upload_token: str = Header(default="")):
    """ZIP с веб-экспортом админки → content-store/admin-web/<версия>, «current» указывает на последнюю."""
    s = get_settings()
    if not s.client_upload_token or x_upload_token != s.client_upload_token:
        raise HTTPException(403, "Неверный токен загрузки")
    if not re.fullmatch(r"[0-9]+(\.[0-9]+){1,3}", version):
        raise HTTPException(422, "Версия вида 0.1.42")
    data = await request.body()
    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        raise HTTPException(422, "Это не ZIP")
    if "index.html" not in zf.namelist():
        raise HTTPException(422, "В архиве нет index.html")
    root = s.content_store_dir / "admin-web"
    dest = root / version
    tmp = root / f".tmp_{version}"
    shutil.rmtree(tmp, ignore_errors=True)
    tmp.mkdir(parents=True)
    for name in zf.namelist():
        p = Path(name)
        if name.endswith("/") or p.is_absolute() or ".." in p.parts:
            continue
        out = tmp / p
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(zf.read(name))
        os.chmod(out, 0o644)
    shutil.rmtree(dest, ignore_errors=True)
    os.replace(tmp, dest)
    link = root / "current"
    tmp_link = root / ".current_tmp"
    tmp_link.unlink(missing_ok=True)
    os.symlink(version, tmp_link)
    os.replace(tmp_link, link)
    # Храним три последние версии
    versions = sorted((p for p in root.iterdir() if p.is_dir() and not p.is_symlink() and not p.name.startswith(".")),
                      key=lambda p: p.stat().st_mtime, reverse=True)
    for old in versions[3:]:
        shutil.rmtree(old, ignore_errors=True)
    return {"ok": True, "version": version}

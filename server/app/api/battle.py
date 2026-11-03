"""Бои. Этап 3: тестовый бой (свой отряд против готового отряда из контента)."""
from __future__ import annotations

import secrets
import asyncio
import time

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import current_player, ensure_not_banned
from app.auth.security import RateLimited, check_rate_limit, decode_access_token
from app.battle.sim import Battle, BattleError
from app.content.releases import get_channel_release
from app.content.view import ContentView, view_for
from app.db import get_session, get_sessionmaker
from app.models import Player

router = APIRouter(prefix="/api/v1/battle", tags=["battle"])
ws_router = APIRouter()


class TeamUnit(BaseModel):
    hero: str = Field(min_length=1, max_length=64)
    slot: int = Field(ge=0, le=4)


class TestBattleIn(BaseModel):
    team: list[TeamUnit] = Field(min_length=1, max_length=5)
    enemy: str = Field(min_length=1, max_length=64)


async def content_for(player: Player, session: AsyncSession) -> ContentView:
    channel = "test" if player.is_test else "live"
    release = await get_channel_release(session, channel)
    if release is None:
        raise HTTPException(503, "Контент ещё не опубликован")
    return view_for(release)


def validate_team(team: list[TeamUnit], heroes: dict) -> list[dict]:
    if len({u.slot for u in team}) != len(team):
        raise HTTPException(422, "Два героя не могут стоять на одном месте")
    if len({u.hero for u in team}) != len(team):
        raise HTTPException(422, "Один герой не может быть в отряде дважды")
    for u in team:
        if u.hero not in heroes:
            raise HTTPException(422, f"Неизвестный герой «{u.hero}»")
    return [{"hero": u.hero, "slot": u.slot} for u in team]


@router.get("/test-teams")
async def test_teams(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    view = await content_for(player, session)
    return {"teams": list(view.teams().values())}


@router.post("/test")
async def test_battle(body: TestBattleIn, player: Player = Depends(current_player),
                      session: AsyncSession = Depends(get_session)):
    """Мгновенный бой с автоматическими ультимейтами: сервер считает, клиент проигрывает журнал."""
    try:
        await check_rate_limit(f"battle:test:{player.id}", 30, 60)
    except RateLimited as e:
        raise HTTPException(429, f"Слишком много боёв подряд. Подождите {e.retry_after} с.")
    view = await content_for(player, session)
    heroes = view.heroes()
    team = validate_team(body.team, heroes)
    enemy = view.teams().get(body.enemy)
    if enemy is None:
        raise HTTPException(422, f"Неизвестный отряд противника «{body.enemy}»")
    seed = secrets.randbits(31)
    try:
        battle = Battle(view.battle_config(), view.factions(), heroes, team, enemy["units"], seed)
    except BattleError as e:
        raise HTTPException(422, str(e))
    log = battle.run()
    log["content_release"] = view.release_id
    return {"enemy": {"id": enemy["id"], "name": enemy["name"]}, "log": log}


@ws_router.websocket("/ws/battle/test")
async def live_test_battle(ws: WebSocket):
    """Живой тестовый бой. Токен передаётся заголовком, не в URL."""
    await ws.accept()
    battle = None
    try:
        header = ws.headers.get("authorization", "")
        player_id = decode_access_token(header[7:].strip()) if header.lower().startswith("bearer ") else None
        async with get_sessionmaker()() as session:
            player = await session.get(Player, player_id) if player_id else None
            if player is None:
                raise HTTPException(401, "Нужно войти в игру")
            ensure_not_banned(player)
            try:
                await check_rate_limit(f"battle:test:{player.id}", 30, 60)
            except RateLimited:
                raise HTTPException(429, "Слишком много боёв подряд")
            raw = await asyncio.wait_for(ws.receive_json(), 10)
            body = TestBattleIn.model_validate(raw)
            view = await content_for(player, session)
            heroes = view.heroes()
            team = validate_team(body.team, heroes)
            enemy = view.teams().get(body.enemy)
            if enemy is None:
                raise HTTPException(422, "Неизвестный отряд противника")
            battle = Battle(view.battle_config(), view.factions(), heroes, team, enemy["units"],
                            secrets.randbits(31), auto=(False, True))
            initial = battle.log()
            initial["content_release"] = view.release_id
            initial.pop("result")
            await ws.send_json({"type": "start", "log": initial})
        sent = len(battle.events)
        start = time.monotonic()
        while not battle.finished:
            # Сервер рассчитывает на два тика вперёд относительно клиента.
            deadline = start + max(0, battle.t - 2) / battle.tick_rate
            timeout = max(0, deadline - time.monotonic())
            try:
                msg = await asyncio.wait_for(ws.receive_json(), timeout=max(timeout, 0.001))
                if isinstance(msg, dict) and msg.get("type") == "ult":
                    uid = msg.get("uid")
                    if type(uid) is int and 0 <= uid < len(battle.units):
                        unit = battle.units[uid]
                        if unit.side == 0 and unit.alive and unit.energy >= battle.cfg["energy"]["max"]:
                            battle.request_ult(uid)
                elif isinstance(msg, dict) and msg.get("type") == "auto" and type(msg.get("on")) is bool:
                    battle.set_auto(0, msg["on"])
                elif isinstance(msg, dict) and msg.get("type") == "skip":
                    battle.set_auto(0, True)
                    battle.run()
                continue
            except asyncio.TimeoutError:
                pass
            battle.step()
            await ws.send_json({"type": "events", "until": battle.t, "events": battle.events[sent:]})
            sent = len(battle.events)
        # После пропуска журнал может быть больше буфера одного пакета клиента.
        for offset in range(sent, len(battle.events), 40):
            await ws.send_json({"type": "events", "until": battle.t, "events": battle.events[offset:offset + 40]})
        await ws.send_json({"type": "end", "events": [], "result": battle.log()["result"]})
        # Дождаться обработки результата клиентом до закрытия соединения.
        await asyncio.wait_for(ws.receive_json(), 5)
    except WebSocketDisconnect:
        pass
    except (HTTPException, ValueError, asyncio.TimeoutError, BattleError) as exc:
        try:
            await ws.send_json({"type": "error", "message": str(getattr(exc, "detail", "Не удалось начать бой"))})
        except (WebSocketDisconnect, RuntimeError):
            pass
    finally:
        if battle is not None and not battle.finished:
            battle.set_auto(0, True)
            battle.run()
        try:
            await ws.close()
        except (RuntimeError, WebSocketDisconnect):
            pass

"""Бои. Этап 3: тестовый бой (свой отряд против готового отряда из контента)."""
from __future__ import annotations

import secrets
import asyncio
import time
from datetime import datetime, timezone

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


async def owned_team(session: AsyncSession, player: Player, view: ContentView, team: list[dict]) -> list[dict]:
    """Отряд из своих героев игрока: уровень и редкость влияют на характеристики.

    Тестовые аккаунты в тестовом бою могут брать любых героев (базовые характеристики) —
    для проверки контента; во всех остальных случаях — только своих.
    """
    from app.progression import heroes as prog
    try:
        cfg = view.json("config/progression.json")
    except KeyError:
        return team  # правила прогрессии ещё не опубликованы — как раньше
    await prog.lock_player(session, player.id)
    await prog.ensure_starter(session, player.id, cfg)
    return await prog.build_team(session, player.id, cfg, view.heroes(), team)


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
    if not player.is_test:
        team = await owned_team(session, player, view, team)
        await session.commit()
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


@ws_router.websocket("/ws/battle/campaign")
@ws_router.websocket("/ws/battle/test")
async def live_test_battle(ws: WebSocket):
    """Живой бой. Токен передаётся заголовком, не в URL."""
    await ws.accept()
    battle = None
    campaign_context = None
    campaign_awarded = False
    campaign_reward = None
    try:
        header = ws.headers.get("authorization", "")
        player_id = decode_access_token(header[7:].strip()) if header.lower().startswith("bearer ") else None
        async with get_sessionmaker()() as session:
            player = await session.get(Player, player_id) if player_id else None
            if player is None:
                raise HTTPException(401, "Нужно войти в игру")
            ensure_not_banned(player)
            try:
                mode = "campaign" if ws.url.path.endswith("/campaign") else "test"
                await check_rate_limit(f"battle:{mode}:{player.id}", 30, 60)
            except RateLimited:
                raise HTTPException(429, "Слишком много боёв подряд")
            raw = await asyncio.wait_for(ws.receive_json(), 10)
            view = await content_for(player, session)
            heroes = view.heroes()
            if mode == "campaign":
                # Импорт отложен: модуль кампании использует общую проверку отряда.
                from app.api.campaign import FightIn, data
                from app.campaign.service import locked_progress
                body = FightIn.model_validate(raw)
                config, _, stages = data(view)
                progress = await locked_progress(session, player.id)
                if body.stage > progress.cleared + 1:
                    raise HTTPException(403, "Сначала пройдите предыдущий этап")
                stage = stages[body.stage - 1]
                enemy = view.teams().get(stage["enemy"])
                campaign_context = (player.id, body.stage, stage["reward"], config)
            else:
                body = TestBattleIn.model_validate(raw)
                enemy = view.teams().get(body.enemy)
            team = validate_team(body.team, heroes)
            if mode == "campaign" or not player.is_test:
                team = await owned_team(session, player, view, team)
            if enemy is None:
                raise HTTPException(422, "Неизвестный отряд противника")
            enemy_units = ([{**unit, "stat_multiplier": stage["enemy_multiplier"]} for unit in enemy["units"]]
                           if mode == "campaign" else enemy["units"])
            battle = Battle(view.battle_config(), view.factions(), heroes, team, enemy_units,
                            secrets.randbits(31), auto=(False, True))
            initial = battle.log()
            initial["content_release"] = view.release_id
            initial.pop("result")
            await session.commit()
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
        if campaign_context:
            campaign_reward = await _award_campaign(battle, campaign_context)
            campaign_awarded = True
        await ws.send_json({"type": "end", "events": [], "result": battle.log()["result"],
                            "campaign_reward": campaign_reward})
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
        if battle is not None and campaign_context and not campaign_awarded:
            await _award_campaign(battle, campaign_context)
        try:
            await ws.close()
        except (RuntimeError, WebSocketDisconnect):
            pass


async def _award_campaign(battle: Battle, context: tuple) -> dict:
    from app.campaign.rewards import settle
    from app.campaign.service import locked_progress

    player_id, stage_number, stage_reward, config = context
    async with get_sessionmaker()() as session:
        from app.progression import wallet
        progress = await locked_progress(session, player_id)
        settle(progress, config, datetime.now(timezone.utc))
        reward = {"gold": 0, "hero_xp": 0}
        if battle.winner == 0 and stage_number == progress.cleared + 1:
            reward = dict(stage_reward)
            await wallet.add(session, player_id, reward)
            progress.cleared += 1
        await session.commit()
        return reward

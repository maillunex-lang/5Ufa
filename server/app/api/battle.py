"""Бои. Этап 3: тестовый бой (свой отряд против готового отряда из контента)."""
from __future__ import annotations

import secrets

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.deps import current_player
from app.auth.security import RateLimited, check_rate_limit
from app.battle.sim import Battle, BattleError
from app.content.releases import get_channel_release
from app.content.view import ContentView, view_for
from app.db import get_session
from app.models import Player

router = APIRouter(prefix="/api/v1/battle", tags=["battle"])


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

"""Кампания и AFK-награды, расчёт и сохранение на сервере."""
import secrets
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from app.api.battle import TeamUnit, content_for, owned_team, validate_team
from app.auth.deps import current_player
from app.auth.security import RateLimited, check_rate_limit
from app.battle.sim import Battle, BattleError
from app.campaign.rewards import UFA, claim, pending, quick, settle
from app.campaign.service import locked_progress
from app.progression import equipment as eq
from app.progression import wallet
from app.db import get_session
from app.models import Player

router = APIRouter(prefix="/api/v1/campaign", tags=["campaign"])

class FightIn(BaseModel):
    stage: int = Field(ge=1, le=25)
    team: list[TeamUnit] = Field(min_length=1, max_length=5)

def data(view):
    try:
        config = view.json("config/campaign.json")
        chapters = [view.json(f"campaign/chapter_{i}/chapter.json") for i in range(1, 6)]
        stages = [stage for chapter in chapters for stage in chapter["stages"]]
        if [s["number"] for s in stages] != list(range(1, 26)):
            raise ValueError("Некорректные этапы")
        return config, chapters, stages
    except (KeyError, ValueError, TypeError):
        raise HTTPException(503, "Кампания ещё не опубликована")

def _eq_cfg(view):
    try:
        return view.json("config/equipment.json")
    except KeyError:
        return None


async def credit(session, player_id, view, reward: dict, stage_for_quality: int) -> dict:
    """Начислить награду: валюты — в кошелёк, "equipment" — создать столько случайных предметов."""
    from app.progression.heroes import lock_player
    await lock_player(session, player_id)  # тот же порядок блокировок, что в бою: прогресс → игрок
    reward = dict(reward)
    count = int(reward.get("equipment", 0))
    await wallet.add(session, player_id, {k: v for k, v in reward.items() if k != "equipment"})
    cfg = _eq_cfg(view)
    if not count or cfg is None:
        reward.pop("equipment", None)
        return {"reward": reward, "items": [], "ore_instead": 0}
    got = await eq.grant_items(session, player_id, cfg, count, eq.chapter_quality(cfg, stage_for_quality),
                               sorted(view.factions().keys()))
    if got["ore_instead"]:
        reward["ore"] = reward.get("ore", 0) + got["ore_instead"]
    return {"reward": reward, **got}


async def award_stage(session, player_id, view, progress, stage_number: int, stage_reward: dict, won: bool) -> dict:
    """Награда только за первую победу на этапе: валюты этапа, гарантированный предмет,
    в конце главы — осколки наследия. Повторная победа ничего не даёт."""
    if not won or stage_number != progress.cleared + 1:
        return {"reward": {"gold": 0, "hero_xp": 0}, "items": [], "ore_instead": 0}
    reward = dict(stage_reward)
    eq_cfg = _eq_cfg(view)
    if eq_cfg:
        reward["equipment"] = reward.get("equipment", 0) + 1
        shards = int(eq_cfg["drops"].get("chapter_end_legacy_shards", 0))
        if stage_number % 5 == 0 and shards:
            reward["legacy_shards"] = reward.get("legacy_shards", 0) + shards
    got = await credit(session, player_id, view, reward, stage_number)
    progress.cleared += 1
    return got


def status(progress, config, now, balance):
    return {"cleared": progress.cleared, "gold": balance.get("gold", 0), "hero_xp": balance.get("hero_xp", 0),
            "wallet": balance,
            "pending": pending(progress), "elapsed_seconds": progress.elapsed_us // 1_000_000,
            "cap_seconds": config["afk_cap_seconds"],
            "quick_available": progress.quick_day != now.astimezone(UFA).date().isoformat() or progress.quick_count < config["quick_daily_limit"],
            "rate_percent": 100 + progress.cleared * config["stage_bonus_percent"], "server_time": now.isoformat()}

@router.get("")
async def campaign_status(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    config, chapters, _ = data(await content_for(player, session))
    progress = await locked_progress(session, player.id)
    now = datetime.now(timezone.utc)
    settle(progress, config, now)
    result = status(progress, config, now, await wallet.balances(session, player.id))
    result["chapters"] = chapters
    await session.commit()
    return result

@router.post("/claim")
async def claim_afk(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    view = await content_for(player, session)
    config, _, _ = data(view)
    progress = await locked_progress(session, player.id)
    now = datetime.now(timezone.utc)
    settle(progress, config, now)
    reward = claim(progress)
    got = await credit(session, player.id, view, reward, max(1, progress.cleared))
    result = status(progress, config, now, await wallet.balances(session, player.id))
    await session.commit()
    return {**got, "status": result}

@router.post("/quick")
async def claim_quick(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    view = await content_for(player, session)
    config, _, _ = data(view)
    progress = await locked_progress(session, player.id)
    now = datetime.now(timezone.utc)
    settle(progress, config, now)
    reward = quick(progress, config, now)
    if reward is None:
        raise HTTPException(409, "Быстрая награда сегодня уже получена")
    got = await credit(session, player.id, view, reward, max(1, progress.cleared))
    result = status(progress, config, now, await wallet.balances(session, player.id))
    await session.commit()
    return {**got, "status": result}

@router.post("/fight")
async def fight(body: FightIn, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    try:
        await check_rate_limit(f"battle:campaign:{player.id}", 30, 60)
    except RateLimited:
        raise HTTPException(429, "Слишком много боёв подряд")
    view = await content_for(player, session)
    config, _, stages = data(view)
    heroes = view.heroes()
    team = validate_team(body.team, heroes)
    progress = await locked_progress(session, player.id)
    if body.stage > progress.cleared + 1:
        raise HTTPException(403, "Сначала пройдите предыдущий этап")
    stage = stages[body.stage - 1]
    enemy = view.teams().get(stage["enemy"])
    if not enemy:
        raise HTTPException(503, "Противник этапа не найден")
    team = await owned_team(session, player, view, team)
    units = [{**unit, "stat_multiplier": stage["enemy_multiplier"]} for unit in enemy["units"]]
    try:
        log = Battle(view.battle_config(), view.factions(), heroes, team, units, secrets.randbits(31)).run()
    except BattleError as exc:
        raise HTTPException(422, str(exc))
    now = datetime.now(timezone.utc)
    settle(progress, config, now)
    got = await award_stage(session, player.id, view, progress, body.stage, stage["reward"],
                            log["result"]["winner"] == 0)
    log["content_release"] = view.release_id
    result = status(progress, config, now, await wallet.balances(session, player.id))
    await session.commit()
    return {"log": log, **got, "status": result, "enemy": enemy["name"]}

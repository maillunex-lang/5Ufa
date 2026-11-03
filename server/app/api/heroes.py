"""Коллекция героев, уровни, Кристалл резонанса, вознесение и призыв (этап 5а)."""
from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.battle import content_for
from app.auth.deps import current_player
from app.content.view import ContentView
from app.db import get_session
from app.models import Player, SummonState
from app.progression import heroes as prog
from app.progression import summon as summ
from app.progression import wallet

router = APIRouter(prefix="/api/v1", tags=["heroes"])


def progression_config(view: ContentView) -> dict:
    try:
        return view.json("config/progression.json")
    except KeyError:
        raise HTTPException(503, "Правила прогрессии ещё не опубликованы")


def summon_config(view: ContentView) -> dict:
    try:
        return view.json("summon/banners.json")
    except KeyError:
        raise HTTPException(503, "Призыв ещё не опубликован")


async def _roster_payload(session, player_id, cfg, content_heroes) -> dict:
    roster = await prog.heroes_of(session, player_id)
    crystal = prog.crystal_level(cfg, roster)
    items = [prog.hero_public(cfg, content_heroes, h, crystal) for h in roster]
    items.sort(key=lambda x: (-x["power"], x["name"]))
    return {
        "heroes": items,
        "wallet": await wallet.balances(session, player_id),
        "crystal": {"level": crystal, "slots": int(cfg["resonance"]["slots"]), "top": int(cfg["resonance"]["top"]),
                    "used": sum(1 for h in roster if h.crystal_slot is not None)},
        "tiers": [{"id": t["id"], "name": t["name"], "level_cap": t["level_cap"], "color": t.get("color", "#FFFFFF")}
                  for t in cfg["tiers"]],
    }


async def _prepare(player: Player, session: AsyncSession):
    view = await content_for(player, session)
    cfg = progression_config(view)
    await prog.lock_player(session, player.id)
    await prog.ensure_starter(session, player.id, cfg)
    return view, cfg


@router.get("/heroes")
async def roster(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    view, cfg = await _prepare(player, session)
    payload = await _roster_payload(session, player.id, cfg, view.heroes())
    await session.commit()
    return payload


class LevelUpIn(BaseModel):
    times: int = Field(default=1, ge=1, le=100)


@router.post("/heroes/{instance_id}/level-up")
async def level_up(instance_id: int, body: LevelUpIn, player: Player = Depends(current_player),
                   session: AsyncSession = Depends(get_session)):
    view, cfg = await _prepare(player, session)
    await prog.level_up(session, player.id, cfg, instance_id, body.times)
    payload = await _roster_payload(session, player.id, cfg, view.heroes())
    await session.commit()
    return payload


@router.post("/heroes/{instance_id}/ascend")
async def ascend(instance_id: int, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    view, cfg = await _prepare(player, session)
    hero, spent = await prog.ascend(session, player.id, cfg, view.heroes(), instance_id)
    tier = prog.tier_name(cfg, hero.tier)
    payload = await _roster_payload(session, player.id, cfg, view.heroes())
    await session.commit()
    return {**payload, "message": f"Вознесение: теперь «{tier}»", "spent": spent}


class CrystalIn(BaseModel):
    put: bool


@router.post("/heroes/{instance_id}/crystal")
async def crystal(instance_id: int, body: CrystalIn, player: Player = Depends(current_player),
                  session: AsyncSession = Depends(get_session)):
    view, cfg = await _prepare(player, session)
    await prog.set_crystal(session, player.id, cfg, instance_id, body.put)
    payload = await _roster_payload(session, player.id, cfg, view.heroes())
    await session.commit()
    return payload


@router.post("/heroes/{instance_id}/dismiss")
async def dismiss(instance_id: int, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    view, cfg = await _prepare(player, session)
    essence = await prog.dismiss(session, player.id, cfg, instance_id)
    payload = await _roster_payload(session, player.id, cfg, view.heroes())
    await session.commit()
    return {**payload, "message": f"Получено {essence} эссенции"}


@router.get("/summon")
async def summon_info(player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    view, cfg = await _prepare(player, session)
    scfg = summon_config(view)
    content_heroes = view.heroes()
    now = datetime.now(timezone.utc)
    banners = []
    for b in summ.active_banners(scfg, now):
        st = await session.get(SummonState, (player.id, b["id"]))
        banners.append({
            "id": b["id"], "name": b["name"], "type": b["type"], "description": b.get("description", ""),
            "costs": b["costs"], "ends_at": b.get("ends_at"), "featured": b.get("featured", []),
            "rates": summ.rates_table(scfg, b, content_heroes),
            "pity": st.pity if st else 0, "pity_cap": int(scfg["pity_legendary"]),
            "first_legendary": b["type"] == "normal" and bool(scfg.get("first_summon_legendary")) and not (st and st.total),
            "pool": [{"hero": h, "name": content_heroes[h]["name"]} for h in summ.pools(b, content_heroes)["legendary"]],
        })
    wallet_now = await wallet.balances(session, player.id)
    await session.commit()
    return {"banners": banners, "wallet": wallet_now}


class SummonIn(BaseModel):
    banner: str = Field(min_length=1, max_length=64)
    count: int = Field(ge=1, le=10)


@router.post("/summon")
async def summon(body: SummonIn, player: Player = Depends(current_player), session: AsyncSession = Depends(get_session)):
    view, cfg = await _prepare(player, session)
    result = await summ.summon(session, player.id, summon_config(view), view.heroes(), body.banner, body.count)
    result["wallet"] = await wallet.balances(session, player.id)
    await session.commit()
    return result

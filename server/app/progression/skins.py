"""Скины героев (этап 6в-2): обычный вид «default», бесплатные скины — у всех, остальные — выданные.

Скин меняет только внешний вид: картинки частей, портрет и полный арт лежат в heroes/<id>/skins/<скин>/
по тем же путям, что у обычного вида. Характеристики героя не меняются.
"""
from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy import delete, select

from app.models import PlayerSkin, PlayerSkinChoice

DEFAULT = "default"


def skins_of(hero: dict) -> list[dict]:
    return [{"id": DEFAULT, "name": "Обычный", "free": True}] + [
        {"id": s["id"], "name": s["name"], "free": bool(s.get("free", False)), "description": s.get("description", "")}
        for s in hero.get("skins", [])]


async def owned(session, player_id) -> dict[str, set[str]]:
    rows = (await session.execute(select(PlayerSkin).where(PlayerSkin.player_id == player_id))).scalars()
    out: dict[str, set[str]] = {}
    for r in rows:
        out.setdefault(r.hero_id, set()).add(r.skin_id)
    return out


async def choices(session, player_id) -> dict[str, str]:
    rows = (await session.execute(select(PlayerSkinChoice).where(PlayerSkinChoice.player_id == player_id))).scalars()
    return {r.hero_id: r.skin_id for r in rows}


def available(hero: dict, owned_ids: set[str]) -> list[dict]:
    return [{**s, "owned": s["free"] or s["id"] in owned_ids} for s in skins_of(hero)]


def effective(hero: dict, chosen: str | None, owned_ids: set[str]) -> str:
    """Выбранный скин, если он ещё существует и доступен; иначе обычный вид."""
    for s in available(hero, owned_ids):
        if s["id"] == chosen and s["owned"]:
            return chosen
    return DEFAULT


async def choose(session, player_id, content_heroes: dict, hero_id: str, skin_id: str) -> None:
    hero = content_heroes.get(hero_id)
    if hero is None:
        raise HTTPException(404, "Герой не найден")
    have = (await owned(session, player_id)).get(hero_id, set())
    skin = next((s for s in available(hero, have) if s["id"] == skin_id), None)
    if skin is None:
        raise HTTPException(404, "Такого скина нет")
    if not skin["owned"]:
        raise HTTPException(409, f"Скин «{skin['name']}» ещё не получен")
    row = await session.get(PlayerSkinChoice, (player_id, hero_id))
    if row is None:
        session.add(PlayerSkinChoice(player_id=player_id, hero_id=hero_id, skin_id=skin_id))
    else:
        row.skin_id = skin_id
    await session.flush()


async def grant(session, player_id, hero_id: str, skin_id: str, give: bool) -> None:
    row = await session.get(PlayerSkin, (player_id, hero_id, skin_id))
    if give and row is None:
        session.add(PlayerSkin(player_id=player_id, hero_id=hero_id, skin_id=skin_id))
    elif not give and row is not None:
        await session.delete(row)
        await session.execute(delete(PlayerSkinChoice).where(
            PlayerSkinChoice.player_id == player_id, PlayerSkinChoice.hero_id == hero_id,
            PlayerSkinChoice.skin_id == skin_id))
    await session.flush()

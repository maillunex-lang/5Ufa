"""Призыв героев. Правила и шансы — в контенте summon/banners.json (схема summon.schema.json).

- Результат: редкий герой, элитная или легендарная копия одного из героев пула баннера.
- Гарант: легенда не позже pity_legendary-го призыва на этом баннере (счётчик сбрасывается при легенде).
- Первый в жизни призыв на обычном баннере — легенда (first_summon_legendary).
- Случайность — криптографическая (secrets.SystemRandom), сервер — единственный источник результата.
"""
from __future__ import annotations

import secrets
from datetime import datetime, timezone

from fastapi import HTTPException

from app.models import PlayerHero, SummonState
from app.progression import wallet
from app.progression.heroes import MAX_ROSTER, heroes_of

RESULT_TIERS = ("rare", "elite", "legendary")
_rng = secrets.SystemRandom()


def _parse_time(value: str | None):
    return datetime.fromisoformat(value) if value else None


def active_banners(cfg: dict, now: datetime) -> list[dict]:
    out = []
    for b in cfg["banners"]:
        start, end = _parse_time(b.get("starts_at")), _parse_time(b.get("ends_at"))
        if (start and now < start) or (end and now > end):
            continue
        out.append(b)
    return out


def pools(banner: dict, content_heroes: dict) -> dict[str, list[str]]:
    factions = set(banner["factions"])
    main = sorted(h for h, d in content_heroes.items() if d.get("faction") in factions and d.get("rarity") != "rare")
    rare = sorted(h for h, d in content_heroes.items() if d.get("faction") in factions and d.get("rarity") == "rare")
    return {"rare": rare, "elite": main, "legendary": main}


def rates_table(cfg: dict, banner: dict, content_heroes: dict) -> list[dict]:
    """Шансы для экрана призыва (в процентах)."""
    rates = banner.get("rates", cfg["rates"])
    names = {"rare": "Редкий герой", "elite": "Элитный герой", "legendary": "Легендарный герой"}
    out = [{"tier": t, "name": names[t], "percent": round(float(rates[t]) * 100, 2)} for t in RESULT_TIERS]
    featured = banner.get("featured") or []
    if featured:
        share = float(banner.get("featured_share", 0.5))
        for hid in featured:
            out.append({"tier": "legendary", "name": f"из них «{content_heroes.get(hid, {}).get('name', hid)}»",
                        "percent": round(float(rates["legendary"]) * share / len(featured) * 100, 2)})
    return out


def _roll_tier(rates: dict) -> str:
    x = _rng.random()
    acc = 0.0
    for t in ("legendary", "elite", "rare"):
        acc += float(rates[t])
        if x < acc:
            return t
    return "rare"


def choose_cost(banner: dict, count: int, balance: dict[str, int]) -> dict[str, int]:
    """Первый вариант оплаты, на который хватает валюты (например, свитки, иначе кристаллы)."""
    options = [{k: int(v) * count for k, v in opt.items()} for opt in banner["costs"]]
    for opt in options:
        if all(balance.get(k, 0) >= v for k, v in opt.items()):
            return opt
    variants = " или ".join(", ".join(f"{v} {wallet.currency_name(k)}" for k, v in opt.items()) for opt in options)
    raise HTTPException(409, f"Не хватает валюты: нужно {variants}")


async def summon(session, player_id, cfg: dict, content_heroes: dict, banner_id: str, count: int,
                 now: datetime | None = None) -> dict:
    now = now or datetime.now(timezone.utc)
    banner = next((b for b in active_banners(cfg, now) if b["id"] == banner_id), None)
    if banner is None:
        raise HTTPException(404, "Баннер призыва не найден или уже закончился")
    if count not in (1, 10):
        raise HTTPException(422, "Можно призвать 1 или 10 героев")
    roster = await heroes_of(session, player_id)
    if len(roster) + count > MAX_ROSTER:
        raise HTTPException(409, f"В коллекции не больше {MAX_ROSTER} героев. Распустите или используйте лишних для вознесения")
    pool = pools(banner, content_heroes)
    if not pool["elite"]:
        raise HTTPException(503, "Пул героев баннера пуст")
    cost = choose_cost(banner, count, await wallet.balances(session, player_id))
    await wallet.spend(session, player_id, cost)

    state = await session.get(SummonState, (player_id, banner_id))
    if state is None:
        state = SummonState(player_id=player_id, banner_id=banner_id, pity=0, total=0)
        session.add(state)
        await session.flush()
    rates = banner.get("rates", cfg["rates"])
    pity_cap = int(cfg["pity_legendary"])
    owned = {h.hero_id for h in roster}
    results = []
    for i in range(count):
        first_ever = banner["type"] == "normal" and cfg.get("first_summon_legendary") and state.total == 0
        tier = "legendary" if first_ever or state.pity + 1 >= pity_cap else _roll_tier(rates)
        candidates = pool[tier] or pool["elite"]
        hero_id = _rng.choice(candidates)
        featured = banner.get("featured") or []
        if tier == "legendary" and featured and _rng.random() < float(banner.get("featured_share", 0.5)):
            hero_id = _rng.choice(featured)
        state.total += 1
        state.pity = 0 if tier == "legendary" else state.pity + 1
        result_tier = "rare" if tier == "rare" else tier
        inst = PlayerHero(player_id=player_id, hero_id=hero_id, tier=result_tier, level=1)
        session.add(inst)
        await session.flush()
        results.append({"id": inst.id, "hero": hero_id, "name": content_heroes.get(hero_id, {}).get("name", hero_id),
                        "tier": result_tier, "new": hero_id not in owned})
        owned.add(hero_id)
    return {"results": results, "cost": cost, "pity": state.pity, "pity_cap": pity_cap, "total": state.total}

"""Снаряжение героев (этап 5б): 4 слота, типы по ролям, редкости, улучшение рудой, разбор,
стартовый набор, добыча из кампании, уникальный предмет героя.

Правила — в контенте config/equipment.json (схема equipment.schema.json).
Все функции, меняющие данные, вызываются после heroes.lock_player() — блокировки строки игрока.
"""
from __future__ import annotations

import secrets

from fastapi import HTTPException
from sqlalchemy import func, select

from app.models import PlayerHero, PlayerItem, PlayerState
from app.progression import heroes as prog
from app.progression import wallet

_rng = secrets.SystemRandom()


# --- Справочники из конфига ----------------------------------------------------------

def slots(cfg: dict) -> dict[str, dict]:
    return {s["id"]: s for s in cfg["slots"]}


def kinds(cfg: dict) -> dict[str, dict]:
    return {k["id"]: k for k in cfg["kinds"]}


def qualities(cfg: dict) -> dict[str, dict]:
    return {q["id"]: {**q, "index": i} for i, q in enumerate(cfg["qualities"])}


def kind_for_role(cfg: dict, role: str | None) -> str | None:
    return next((k["id"] for k in cfg["kinds"] if role in k["roles"]), None)


def item_name(cfg: dict, item: PlayerItem) -> str:
    k = kinds(cfg).get(item.kind, {})
    return k.get("item_names", {}).get(item.slot) or slots(cfg).get(item.slot, {}).get("name", item.slot)


# --- Характеристики -------------------------------------------------------------------

def item_stats(cfg: dict, item: PlayerItem, hero_faction: str | None = None) -> dict[str, int]:
    base = slots(cfg)[item.slot]["stats"]
    q = qualities(cfg)[item.quality]
    k = float(q["mult"]) * (1 + float(cfg["upgrade"]["stat_percent_per_level"]) / 100 * item.level)
    if hero_faction and item.faction == hero_faction:
        k *= 1 + float(cfg["faction_bonus_percent"]) / 100
    return {stat: int(round(float(v) * k)) for stat, v in base.items()}


def stats_power(stats: dict) -> int:
    """Та же формула силы, что у героя: здоровье/10 + атака×2 + защита."""
    return int(round(stats.get("hp", 0) / 10 + stats.get("atk", 0) * 2 + stats.get("def", 0)))


def upgrade_cost(cfg: dict, item: PlayerItem) -> dict[str, int] | None:
    up = cfg["upgrade"]
    if item.level >= int(up["max_level"]):
        return None
    n = (item.level + 1) * (qualities(cfg)[item.quality]["index"] + 1)
    return {"gold": int(up["gold_base"]) * n, "ore": int(up["ore_base"]) * n}


def dismantle_ore(cfg: dict, item: PlayerItem) -> int:
    q = qualities(cfg)[item.quality]
    return int(q["dismantle_ore"]) + item.ore_spent * int(cfg["upgrade"]["refund_percent"]) // 100


def item_public(cfg: dict, item: PlayerItem, hero_faction: str | None = None, worn_by: dict | None = None) -> dict:
    q = qualities(cfg)[item.quality]
    st = item_stats(cfg, item, hero_faction)
    return {
        "id": item.id, "slot": item.slot, "slot_name": slots(cfg)[item.slot]["name"],
        "kind": item.kind, "kind_name": kinds(cfg).get(item.kind, {}).get("name", item.kind),
        "quality": item.quality, "quality_name": q["name"], "quality_color": q.get("color", "#FFFFFF"),
        "quality_index": q["index"], "faction": item.faction, "level": item.level,
        "max_level": int(cfg["upgrade"]["max_level"]), "name": item_name(cfg, item),
        "stats": st, "power": stats_power(st),
        "upgrade_cost": upgrade_cost(cfg, item), "dismantle_ore": dismantle_ore(cfg, item),
        "hero_instance_id": item.hero_instance_id, "worn_by": worn_by,
    }


# --- Уникальный предмет ----------------------------------------------------------------

def signature_unlocked(prog_cfg: dict, cfg: dict, hero: PlayerHero) -> bool:
    t = prog.tiers(prog_cfg)
    need = t.get(cfg["signature"]["unlock_tier"])
    return need is not None and t[hero.tier]["index"] >= need["index"]


def signature_cost(cfg: dict, level: int) -> dict[str, int] | None:
    sig = cfg["signature"]
    if level >= int(sig["max_level"]):
        return None
    return {code: int(r["base"]) + int(r["per_level"]) * level for code, r in sig["cost"].items()}


def signature_stat_mult(cfg: dict, level: int) -> float:
    return 1 + float(cfg["signature"]["stat_percent_per_level"]) / 100 * level


def signature_ult_percent(cfg: dict, level: int) -> float:
    best = 0.0
    for b in cfg["signature"]["ult_bonus"]:
        if level >= int(b["level"]):
            best = max(best, float(b["percent"]))
    return best


def signature_public(prog_cfg: dict, cfg: dict, hero: PlayerHero) -> dict:
    lvl = hero.signature_level
    return {
        "unlocked": signature_unlocked(prog_cfg, cfg, hero), "level": lvl, "max_level": int(cfg["signature"]["max_level"]),
        "unlock_tier_name": prog.tier_name(prog_cfg, cfg["signature"]["unlock_tier"]),
        "stat_percent": round((signature_stat_mult(cfg, lvl) - 1) * 100, 2),
        "ult_percent": signature_ult_percent(cfg, lvl), "cost": signature_cost(cfg, lvl),
        "next_ult": next(({"level": int(b["level"]), "percent": b["percent"]} for b in cfg["signature"]["ult_bonus"]
                          if int(b["level"]) > lvl), None),
    }


# --- Запросы к базе ------------------------------------------------------------------

async def items_of(session, player_id) -> list[PlayerItem]:
    rows = await session.execute(select(PlayerItem).where(PlayerItem.player_id == player_id).order_by(PlayerItem.id))
    return list(rows.scalars())


async def count_items(session, player_id) -> int:
    return int((await session.execute(select(func.count()).select_from(PlayerItem)
                                      .where(PlayerItem.player_id == player_id))).scalar_one())


async def get_item(session, player_id, item_id: int) -> PlayerItem:
    item = await session.get(PlayerItem, item_id)
    if item is None or item.player_id != player_id:
        raise HTTPException(404, "Предмет не найден")
    return item


def worn_map(items: list[PlayerItem]) -> dict[int, dict[str, PlayerItem]]:
    """hero_instance_id -> {слот: предмет}"""
    out: dict[int, dict[str, PlayerItem]] = {}
    for it in items:
        if it.hero_instance_id is not None:
            out.setdefault(it.hero_instance_id, {})[it.slot] = it
    return out


def hero_bonus(cfg: dict, worn: dict[str, PlayerItem], faction: str | None) -> dict[str, int]:
    total = {"hp": 0, "atk": 0, "def": 0}
    for it in worn.values():
        for stat, v in item_stats(cfg, it, faction).items():
            total[stat] = total.get(stat, 0) + v
    return total


# --- Создание предметов ----------------------------------------------------------------

def _random_item(cfg: dict, player_id, quality: str, factions: list[str], kind: str | None = None,
                 slot: str | None = None) -> PlayerItem:
    return PlayerItem(
        player_id=player_id, quality=quality, level=0, ore_spent=0,
        slot=slot or _rng.choice([s["id"] for s in cfg["slots"]]),
        kind=kind or _rng.choice([k["id"] for k in cfg["kinds"]]),
        faction=_rng.choice(factions) if factions else None,
    )


async def grant_items(session, player_id, cfg: dict, count: int, quality: str, factions: list[str]) -> dict:
    """Выдать count случайных предметов. При полном инвентаре лишние сразу разбираются в руду."""
    if count <= 0:
        return {"items": [], "ore_instead": 0}
    have = await count_items(session, player_id)
    room = max(0, int(cfg["inventory_limit"]) - have)
    created, ore = [], 0
    for i in range(count):
        it = _random_item(cfg, player_id, quality, factions)
        if i < room:
            session.add(it)
            created.append(it)
        else:
            ore += int(qualities(cfg)[quality]["dismantle_ore"])
    if ore:
        await wallet.add(session, player_id, {"ore": ore})
    await session.flush()
    return {"items": [item_public(cfg, it) for it in created], "ore_instead": ore}


def chapter_quality(cfg: dict, stage_number: int) -> str:
    table = cfg["drops"]["campaign_quality_by_chapter"]
    chapter = max(1, (stage_number - 1) // 5 + 1)
    return table[min(chapter, len(table)) - 1]


async def ensure_starter(session, player_id, cfg: dict) -> bool:
    """Один раз: по per_kind обычных предметов каждого типа (новым и уже существующим игрокам)."""
    state = await session.get(PlayerState, player_id)
    if state is None:
        state = PlayerState(player_id=player_id, starter_granted=False, equipment_starter_granted=False)
        session.add(state)
        await session.flush()
    if state.equipment_starter_granted:
        return False
    slot_ids = [s["id"] for s in cfg["slots"]]
    for k in cfg["kinds"]:
        for i in range(int(cfg["start"]["per_kind"])):
            session.add(PlayerItem(player_id=player_id, slot=slot_ids[i % len(slot_ids)], kind=k["id"],
                                   quality=cfg["start"]["quality"], faction=None, level=0, ore_spent=0))
    state.equipment_starter_granted = True
    await session.flush()
    return True


# --- Действия игрока ---------------------------------------------------------------------

def _check_fits(cfg: dict, content_heroes: dict, hero: PlayerHero, item: PlayerItem) -> None:
    role = content_heroes.get(hero.hero_id, {}).get("role")
    need = kind_for_role(cfg, role)
    if item.kind != need:
        kname = kinds(cfg).get(item.kind, {}).get("name", item.kind)
        hname = content_heroes.get(hero.hero_id, {}).get("name", hero.hero_id)
        need_name = kinds(cfg).get(need, {}).get("name", "?")
        raise HTTPException(409, f"«{hname}» носит снаряжение типа «{need_name}», а этот предмет — «{kname}»")


async def equip(session, player_id, cfg, content_heroes, hero_id: int, item_id: int) -> PlayerItem:
    hero = await prog.get_owned(session, player_id, hero_id)
    item = await get_item(session, player_id, item_id)
    _check_fits(cfg, content_heroes, hero, item)
    for other in await items_of(session, player_id):
        if other.hero_instance_id == hero.id and other.slot == item.slot and other.id != item.id:
            other.hero_instance_id = None  # прежний предмет этого слота — в сумку
    item.hero_instance_id = hero.id  # если был надет на другого героя — переходит
    await session.flush()
    return item


async def unequip(session, player_id, hero_id: int, slot: str | None) -> int:
    hero = await prog.get_owned(session, player_id, hero_id)
    n = 0
    for it in await items_of(session, player_id):
        if it.hero_instance_id == hero.id and (slot is None or it.slot == slot):
            it.hero_instance_id = None
            n += 1
    await session.flush()
    return n


async def auto_equip(session, player_id, cfg, content_heroes, hero_id: int) -> int:
    """Лучшее из свободных предметов (и уже надетых на этого героя). У других героев не забираем."""
    hero = await prog.get_owned(session, player_id, hero_id)
    data = content_heroes.get(hero.hero_id, {})
    need = kind_for_role(cfg, data.get("role"))
    faction = data.get("faction")
    changed = 0
    items = await items_of(session, player_id)
    for slot_id in slots(cfg):
        pool = [it for it in items if it.slot == slot_id and it.kind == need
                and it.hero_instance_id in (None, hero.id)]
        if not pool:
            continue
        best = max(pool, key=lambda it: (stats_power(item_stats(cfg, it, faction)), it.level, -it.id))
        for it in pool:
            if it.hero_instance_id == hero.id and it.id != best.id:
                it.hero_instance_id = None
        if best.hero_instance_id != hero.id:
            best.hero_instance_id = hero.id
            changed += 1
    await session.flush()
    return changed


async def upgrade(session, player_id, cfg, item_id: int, times: int) -> PlayerItem:
    item = await get_item(session, player_id, item_id)
    for i in range(times):
        cost = upgrade_cost(cfg, item)
        if cost is None:
            if i == 0:
                raise HTTPException(409, f"Предмет уже улучшен до предела (+{cfg['upgrade']['max_level']})")
            break
        await wallet.spend(session, player_id, cost)
        item.level += 1
        item.ore_spent += int(cost.get("ore", 0))
    await session.flush()
    return item


async def dismantle(session, player_id, cfg, item_ids: list[int]) -> int:
    """Разобрать предметы в руду. Надетые разобрать нельзя — сначала снять."""
    items = [await get_item(session, player_id, i) for i in dict.fromkeys(item_ids)]
    worn = [it for it in items if it.hero_instance_id is not None]
    if worn:
        raise HTTPException(409, "Надетый предмет нельзя разобрать — сначала снимите его с героя")
    ore = sum(dismantle_ore(cfg, it) for it in items)
    for it in items:
        await session.delete(it)
    await wallet.add(session, player_id, {"ore": ore})
    await session.flush()
    return ore


async def upgrade_signature(session, player_id, prog_cfg, cfg, hero_id: int) -> PlayerHero:
    hero = await prog.get_owned(session, player_id, hero_id)
    if not signature_unlocked(prog_cfg, cfg, hero):
        need = prog.tier_name(prog_cfg, cfg["signature"]["unlock_tier"])
        raise HTTPException(409, f"Уникальный предмет откроется, когда герой достигнет ступени «{need}»")
    cost = signature_cost(cfg, hero.signature_level)
    if cost is None:
        raise HTTPException(409, "Уникальный предмет уже максимального уровня")
    await wallet.spend(session, player_id, cost)
    hero.signature_level += 1
    await session.flush()
    return hero


async def release_from(session, hero_ids: list[int]) -> None:
    """Снять снаряжение с героев, которые уходят (вознесение, роспуск)."""
    if not hero_ids:
        return
    rows = await session.execute(select(PlayerItem).where(PlayerItem.hero_instance_id.in_(hero_ids)))
    for it in rows.scalars():
        it.hero_instance_id = None
    await session.flush()

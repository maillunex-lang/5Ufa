"""Коллекция героев игрока: уровни, Кристалл резонанса, вознесение, стартовый набор.

Правила — в контенте config/progression.json (схема progression.schema.json).
Все функции, меняющие данные, вызываются после lock_player() — блокировки строки игрока.
"""
from __future__ import annotations

from fastapi import HTTPException
from sqlalchemy import select

from app.models import Player, PlayerHero, PlayerState
from app.progression import wallet

MAX_ROSTER = 300


async def lock_player(session, player_id) -> None:
    """Сериализует все изменения одного игрока (награды, валюта, герои)."""
    await session.execute(select(Player.id).where(Player.id == player_id).with_for_update())


def tiers(cfg: dict) -> dict[str, dict]:
    return {t["id"]: {**t, "index": i} for i, t in enumerate(cfg["tiers"])}


def tier_name(cfg: dict, tier: str) -> str:
    return tiers(cfg).get(tier, {}).get("name", tier)


def stat_multiplier(cfg: dict, tier: str, level: int) -> float:
    t = tiers(cfg)[tier]
    return round(float(t["stat_mult"]) * (1 + float(cfg["level"]["stat_growth_percent"]) / 100 * (level - 1)), 6)


def level_cost(cfg: dict, level: int) -> dict[str, int]:
    """Стоимость перехода с уровня level на level+1."""
    out = {}
    for code in ("gold", "hero_xp", "essence"):
        rule = cfg["level"].get(code)
        if not rule or level < int(rule.get("from_level", 1)):
            continue
        n = level - int(rule.get("from_level", 1)) + 1
        out[code] = int(round(float(rule["base"]) * n ** float(rule["exponent"])))
    return out


async def heroes_of(session, player_id) -> list[PlayerHero]:
    rows = (await session.execute(select(PlayerHero).where(PlayerHero.player_id == player_id)
                                  .order_by(PlayerHero.id))).scalars()
    return list(rows)


def _strength_key(cfg, h: PlayerHero):
    return (h.level, tiers(cfg)[h.tier]["index"], -h.id)


def crystal_level(cfg: dict, roster: list[PlayerHero]) -> int | None:
    """Уровень героев в кристалле = уровень пятого сильнейшего героя вне кристалла (None — кристалл не работает)."""
    top_n = int(cfg["resonance"]["top"])
    outside = sorted((h for h in roster if h.crystal_slot is None), key=lambda h: _strength_key(cfg, h), reverse=True)
    if len(outside) < top_n:
        return None
    return outside[top_n - 1].level


def effective_level(cfg: dict, h: PlayerHero, crystal: int | None) -> int:
    if h.crystal_slot is not None and crystal is not None:
        cap = int(tiers(cfg)[h.tier]["level_cap"])
        return max(h.level, min(crystal, cap))
    return h.level


def hero_public(cfg: dict, content_heroes: dict, h: PlayerHero, crystal: int | None,
                eq_cfg: dict | None = None, worn: dict | None = None, skin_info: dict | None = None) -> dict:
    """worn — {слот: PlayerItem} надетого снаряжения; eq_cfg — config/equipment.json (None — без снаряжения)."""
    from app.progression import equipment as eq
    data = content_heroes.get(h.hero_id, {})
    lvl = effective_level(cfg, h, crystal)
    mult = stat_multiplier(cfg, h.tier, lvl)
    st = data.get("stats", {})
    t = tiers(cfg)[h.tier]
    nxt = next((r for r in cfg["ascension"] if r["from"] == h.tier), None)
    sig_mult = eq.signature_stat_mult(eq_cfg, h.signature_level) if eq_cfg else 1.0
    bonus = eq.hero_bonus(eq_cfg, worn or {}, data.get("faction")) if eq_cfg else {}
    stats = {k: round(st.get(k, 0) * mult * sig_mult) + bonus.get(k, 0) for k in ("hp", "atk", "def")}
    out = {
        "id": h.id, "hero": h.hero_id, "name": data.get("name", h.hero_id), "faction": data.get("faction"),
        "role": data.get("role"), "tier": h.tier, "tier_name": t["name"], "tier_color": t.get("color", "#FFFFFF"),
        "level": lvl, "own_level": h.level, "level_cap": int(t["level_cap"]), "crystal_slot": h.crystal_slot,
        "power": int(round(stats["hp"] / 10 + stats["atk"] * 2 + stats["def"])),
        "stats": stats,
        "level_cost": level_cost(cfg, h.level) if h.level < int(t["level_cap"]) and h.crystal_slot is None else None,
        "next_tier": nxt["to"] if nxt else None,
        "next_tier_name": tier_name(cfg, nxt["to"]) if nxt else None,
        "ascension_requires": [_describe_req(cfg, content_heroes, h, r) for r in nxt["requires"]] if nxt else [],
        "dismiss_essence": int(cfg.get("dismiss_essence", {}).get(h.tier, 0)),
    }
    if skin_info is not None:  # {"owned": {hero: set}, "chosen": {hero: skin}}
        from app.progression import skins as sk
        have = skin_info["owned"].get(h.hero_id, set())
        out["skins"] = sk.available(data, have)
        out["skin"] = sk.effective(data, skin_info["chosen"].get(h.hero_id), have)
    if eq_cfg:
        out["equipment_kind"] = eq.kind_for_role(eq_cfg, data.get("role"))
        out["equipment"] = {slot: eq.item_public(eq_cfg, it, data.get("faction")) for slot, it in (worn or {}).items()}
        out["signature"] = eq.signature_public(cfg, eq_cfg, h)
    return out


def _describe_req(cfg, content_heroes, h, req) -> str:
    tname = tier_name(cfg, req["tier"]).lower()
    if req["kind"] == "same":
        return f"{req['count']} × «{content_heroes.get(h.hero_id, {}).get('name', h.hero_id)}» ({tname})"
    return f"{req['count']} × любой герой той же фракции ({tname})"


async def ensure_starter(session, player_id, cfg: dict) -> bool:
    """Выдать стартовый набор один раз (новым и уже существующим игрокам)."""
    state = await session.get(PlayerState, player_id)
    if state is None:
        state = PlayerState(player_id=player_id, starter_granted=False)
        session.add(state)
        await session.flush()
    if state.starter_granted:
        return False
    for entry in cfg["start"]["heroes"]:
        session.add(PlayerHero(player_id=player_id, hero_id=entry["hero"], tier=entry["tier"], level=1))
    await wallet.add(session, player_id, cfg["start"].get("currencies", {}))
    state.starter_granted = True
    await session.flush()
    return True


async def get_owned(session, player_id, instance_id: int) -> PlayerHero:
    h = await session.get(PlayerHero, instance_id)
    if h is None or h.player_id != player_id:
        raise HTTPException(404, "Герой не найден")
    return h


async def level_up(session, player_id, cfg, instance_id: int, times: int) -> PlayerHero:
    h = await get_owned(session, player_id, instance_id)
    if h.crystal_slot is not None:
        raise HTTPException(409, "Герой в Кристалле резонанса — его уровень задаёт кристалл")
    cap = int(tiers(cfg)[h.tier]["level_cap"])
    for _ in range(times):
        if h.level >= cap:
            if _ == 0:
                raise HTTPException(409, f"Достигнут предел уровня для редкости «{tier_name(cfg, h.tier)}» ({cap}). Нужно вознесение")
            break
        await wallet.spend(session, player_id, level_cost(cfg, h.level))
        h.level += 1
    return h


def _pick_fodder(cfg, content_heroes, target: PlayerHero, roster: list[PlayerHero], req, used: set[int]) -> list[PlayerHero]:
    faction = content_heroes.get(target.hero_id, {}).get("faction")
    candidates = [h for h in roster
                  if h.id != target.id and h.id not in used and h.crystal_slot is None and h.tier == req["tier"]
                  and (h.hero_id == target.hero_id if req["kind"] == "same"
                       else content_heroes.get(h.hero_id, {}).get("faction") == faction)]
    # Сначала тратим самые «дешёвые»: низкий уровень, другого героя (для faction), более новые копии
    candidates.sort(key=lambda h: (h.level, h.hero_id == target.hero_id, -h.id))
    return candidates[:int(req["count"])]


async def ascend(session, player_id, cfg, content_heroes, instance_id: int) -> tuple[PlayerHero, list[dict]]:
    h = await get_owned(session, player_id, instance_id)
    rule = next((r for r in cfg["ascension"] if r["from"] == h.tier), None)
    if rule is None:
        raise HTTPException(409, f"Редкость «{tier_name(cfg, h.tier)}» — максимальная для этого героя")
    roster = await heroes_of(session, player_id)
    used: set[int] = set()
    chosen: list[PlayerHero] = []
    missing = []
    # Сначала требования «тот же герой», потом «любой той же фракции» — чтобы не потратить нужную копию
    for req in sorted(rule["requires"], key=lambda r: r["kind"] != "same"):
        got = _pick_fodder(cfg, content_heroes, h, roster, req, used)
        if len(got) < int(req["count"]):
            missing.append(_describe_req(cfg, content_heroes, h, req))
        used.update(x.id for x in got)
        chosen.extend(got)
    if missing:
        raise HTTPException(409, "Для вознесения не хватает: " + "; ".join(missing))
    spent = [{"id": x.id, "hero": x.hero_id, "tier": x.tier} for x in chosen]
    from app.progression import equipment as eq
    await eq.release_from(session, [x.id for x in chosen])  # снаряжение корма — в сумку
    for x in chosen:
        await session.delete(x)
    h.tier = rule["to"]
    await session.flush()
    return h, spent


async def set_crystal(session, player_id, cfg, instance_id: int, put: bool) -> PlayerHero:
    h = await get_owned(session, player_id, instance_id)
    roster = await heroes_of(session, player_id)
    if not put:
        h.crystal_slot = None
        return h
    if h.crystal_slot is not None:
        return h
    slots = int(cfg["resonance"]["slots"])
    taken = {x.crystal_slot for x in roster if x.crystal_slot is not None}
    free = [s for s in range(slots) if s not in taken]
    if not free:
        raise HTTPException(409, f"Все {slots} мест в Кристалле резонанса заняты")
    outside = sorted((x for x in roster if x.crystal_slot is None), key=lambda x: _strength_key(cfg, x), reverse=True)
    top_n = int(cfg["resonance"]["top"])
    if h in outside[:top_n]:
        raise HTTPException(409, f"Это один из {top_n} сильнейших героев — они задают уровень кристалла и не могут стоять в нём")
    if len(outside) - 1 < top_n:
        raise HTTPException(409, f"Нужно минимум {top_n} героев вне кристалла")
    h.crystal_slot = free[0]
    return h


async def dismiss(session, player_id, cfg, instance_id: int) -> int:
    h = await get_owned(session, player_id, instance_id)
    essence = int(cfg.get("dismiss_essence", {}).get(h.tier, 0))
    if essence <= 0:
        raise HTTPException(409, f"Героя редкости «{tier_name(cfg, h.tier)}» нельзя распустить")
    from app.progression import equipment as eq
    await eq.release_from(session, [h.id])
    await session.delete(h)
    await wallet.add(session, player_id, {"essence": essence})
    return essence


async def build_team(session, player_id, cfg, content_heroes, team: list[dict], eq_cfg: dict | None = None) -> list[dict]:
    """Отряд для боя из своих героев: для каждого выбранного героя берётся сильнейший экземпляр.
    С eq_cfg учитываются снаряжение (прибавка bonus) и уникальный предмет (множитель и сила ультимейта)."""
    from app.progression import equipment as eq
    roster = await heroes_of(session, player_id)
    crystal = crystal_level(cfg, roster)
    worn = eq.worn_map(await eq.items_of(session, player_id)) if eq_cfg else {}
    from app.progression import skins as sk
    owned_skins = await sk.owned(session, player_id)
    chosen_skins = await sk.choices(session, player_id)
    out = []
    for unit in team:
        own = [h for h in roster if h.hero_id == unit["hero"]]
        if not own:
            name = content_heroes.get(unit["hero"], {}).get("name", unit["hero"])
            raise HTTPException(422, f"У вас нет героя «{name}»")
        faction = content_heroes.get(unit["hero"], {}).get("faction")

        def strength(h):
            m = stat_multiplier(cfg, h.tier, effective_level(cfg, h, crystal))
            if eq_cfg:
                m *= eq.signature_stat_mult(eq_cfg, h.signature_level)
                b = eq.hero_bonus(eq_cfg, worn.get(h.id, {}), faction)
                return (m, b["hp"] / 10 + b["atk"] * 2 + b["def"], h.id)
            return (m, 0, h.id)

        best = max(own, key=strength)
        lvl = effective_level(cfg, best, crystal)
        mult = stat_multiplier(cfg, best.tier, lvl)
        entry = {"hero": unit["hero"], "slot": unit["slot"], "level": lvl, "tier": best.tier,
                 "skin": sk.effective(content_heroes.get(unit["hero"], {}), chosen_skins.get(unit["hero"]),
                                      owned_skins.get(unit["hero"], set()))}
        if eq_cfg:
            mult = round(mult * eq.signature_stat_mult(eq_cfg, best.signature_level), 6)
            entry["bonus"] = eq.hero_bonus(eq_cfg, worn.get(best.id, {}), faction)
            ult = eq.signature_ult_percent(eq_cfg, best.signature_level)
            if ult:
                entry["ult_power"] = round(1 + ult / 100, 4)
        entry["stat_multiplier"] = mult
        out.append(entry)
    return out

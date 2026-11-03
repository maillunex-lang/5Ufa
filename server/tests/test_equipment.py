"""Этап 5б: снаряжение, улучшение, разбор, уникальный предмет, влияние на бой."""
import json
import uuid
from pathlib import Path

from app.progression import equipment as eq
from tests.test_progression import add_heroes, give, guest, published  # noqa: F401

C = Path(__file__).resolve().parents[2] / "content"
EQ = json.loads((C / "config/equipment.json").read_text("utf-8"))


def hero_by(roster, hero_id):
    return next(h for h in roster["heroes"] if h["hero"] == hero_id)


def test_config_consistent():
    roles = {r for k in EQ["kinds"] for r in k["roles"]}
    assert roles == {"tank", "warrior", "archer", "mage", "support", "assassin"}
    mults = [q["mult"] for q in EQ["qualities"]]
    assert mults == sorted(mults)
    qids = {q["id"] for q in EQ["qualities"]}
    assert set(EQ["drops"]["campaign_quality_by_chapter"]) <= qids and EQ["start"]["quality"] in qids
    for k in EQ["kinds"]:
        assert set(k["item_names"]) == {s["id"] for s in EQ["slots"]}


def test_item_math():
    it = eq.PlayerItem(slot="weapon", kind="strength", quality="rare", level=0, ore_spent=0, faction="ural_batyrs")
    assert eq.item_stats(EQ, it) == {"atk": 32}                      # 20 × 1,6
    assert eq.item_stats(EQ, it, "ural_batyrs") == {"atk": 37}       # +15% за фракцию
    it.level = 10
    assert eq.item_stats(EQ, it) == {"atk": 58}                      # × (1 + 0,08 × 10)
    assert eq.upgrade_cost(EQ, it) is None
    it.level = 0
    assert eq.upgrade_cost(EQ, it) == {"gold": 200, "ore": 6}        # (0+1) × (1+1)


async def test_starter_and_inventory(published):
    c = published
    hdr, _ = await guest(c, "eq-start-1")
    inv = (await c.get("/api/v1/inventory", headers=hdr)).json()
    inv2 = (await c.get("/api/v1/inventory", headers=hdr)).json()
    assert len(inv["items"]) == 12 and len(inv2["items"]) == 12
    assert all(i["quality"] == "common" and i["level"] == 0 and i["worn_by"] is None for i in inv["items"])
    by_kind = {}
    for i in inv["items"]:
        by_kind.setdefault(i["kind"], set()).add(i["slot"])
    assert all(v == {"weapon", "armor", "helmet", "boots"} for v in by_kind.values()) and len(by_kind) == 3


async def test_equip_rules_and_stats(published):
    c = published
    hdr, _ = await guest(c, "eq-equip-1")
    roster = (await c.get("/api/v1/heroes", headers=hdr)).json()
    inv = (await c.get("/api/v1/inventory", headers=hdr)).json()
    ural = hero_by(roster, "ural_batyr")          # воин -> «Сила»
    humai = hero_by(roster, "humai")              # поддержка -> «Мистика»
    alpa = hero_by(roster, "alpamysha")           # танк -> «Сила»
    assert ural["equipment_kind"] == "strength" and humai["equipment_kind"] == "mystic"
    mystic_weapon = next(i for i in inv["items"] if i["kind"] == "mystic" and i["slot"] == "weapon")
    sword = next(i for i in inv["items"] if i["kind"] == "strength" and i["slot"] == "weapon")
    bad = await c.post(f"/api/v1/heroes/{ural['id']}/equip", headers=hdr, json={"item_id": mystic_weapon["id"]})
    assert bad.status_code == 409 and "Сила" in bad.json()["detail"]
    r = (await c.post(f"/api/v1/heroes/{ural['id']}/equip", headers=hdr, json={"item_id": sword["id"]})).json()
    after = hero_by(r, "ural_batyr")
    assert after["equipment"]["weapon"]["id"] == sword["id"]
    assert after["stats"]["atk"] == ural["stats"]["atk"] + 20 and after["power"] > ural["power"]
    # Тот же предмет на другого героя — переходит, у первого слот пустеет
    r = (await c.post(f"/api/v1/heroes/{alpa['id']}/equip", headers=hdr, json={"item_id": sword["id"]})).json()
    assert "weapon" not in hero_by(r, "ural_batyr")["equipment"]
    assert hero_by(r, "alpamysha")["equipment"]["weapon"]["id"] == sword["id"]
    inv = (await c.get("/api/v1/inventory", headers=hdr)).json()
    worn = next(i for i in inv["items"] if i["id"] == sword["id"])
    assert worn["worn_by"]["name"] == "Алпамыша"
    # «Надеть лучшее» не забирает у других героев: свободных мечей у «Силы» больше нет
    r = (await c.post(f"/api/v1/heroes/{ural['id']}/auto-equip", headers=hdr)).json()
    ural_eq = hero_by(r, "ural_batyr")["equipment"]
    assert "weapon" not in ural_eq and set(ural_eq) == {"armor", "helmet", "boots"}
    assert hero_by(r, "alpamysha")["equipment"]["weapon"]["id"] == sword["id"]
    # Снять всё
    r = (await c.post(f"/api/v1/heroes/{ural['id']}/unequip", headers=hdr, json={})).json()
    assert hero_by(r, "ural_batyr")["equipment"] == {}


async def test_upgrade_and_dismantle(published):
    c = published
    hdr, pid = await guest(c, "eq-upgrade-1")
    roster = (await c.get("/api/v1/heroes", headers=hdr)).json()
    inv = (await c.get("/api/v1/inventory", headers=hdr)).json()
    item = inv["items"][0]
    no_ore = await c.post(f"/api/v1/items/{item['id']}/upgrade", headers=hdr, json={"times": 1})
    assert no_ore.status_code == 409 and "Не хватает" in no_ore.json()["detail"]
    await give(pid, gold=100000)
    no_ore = await c.post(f"/api/v1/items/{item['id']}/upgrade", headers=hdr, json={"times": 1})
    assert no_ore.status_code == 409 and "руды" in no_ore.json()["detail"]
    await give(pid, ore=1000)
    r = (await c.post(f"/api/v1/items/{item['id']}/upgrade", headers=hdr, json={"times": 3})).json()
    up = next(i for i in r["items"] if i["id"] == item["id"])
    assert up["level"] == 3 and r["wallet"]["ore"] == 1000 - (3 + 6 + 9)  # обычный: 3 × (L+1)
    assert r["wallet"]["gold"] == 100000 - (100 + 200 + 300)
    r = (await c.post(f"/api/v1/items/{item['id']}/upgrade", headers=hdr, json={"times": 10})).json()
    up = next(i for i in r["items"] if i["id"] == item["id"])
    assert up["level"] == 10 and up["upgrade_cost"] is None
    maxed = await c.post(f"/api/v1/items/{item['id']}/upgrade", headers=hdr, json={"times": 1})
    assert maxed.status_code == 409
    # Надетый разобрать нельзя
    ural = hero_by(roster, "ural_batyr")
    sword = next(i for i in inv["items"] if i["kind"] == "strength" and i["slot"] == "weapon")
    await c.post(f"/api/v1/heroes/{ural['id']}/equip", headers=hdr, json={"item_id": sword["id"]})
    worn = await c.post("/api/v1/items/dismantle", headers=hdr, json={"ids": [sword["id"]]})
    assert worn.status_code == 409
    # Разбор: 2 руды за обычный + 50% руды улучшений (3+6+...+30 = 165 -> 82)
    ore_before = r["wallet"]["ore"]
    r = (await c.post("/api/v1/items/dismantle", headers=hdr, json={"ids": [item["id"]]})).json()
    assert r["wallet"]["ore"] == ore_before + 2 + 165 * 50 // 100
    assert all(i["id"] != item["id"] for i in r["items"])
    other = await c.post("/api/v1/items/dismantle", headers=hdr, json={"ids": [999999]})
    assert other.status_code == 404


async def test_signature_item(published):
    c = published
    hdr, pid = await guest(c, "eq-signature-1")
    roster = (await c.get("/api/v1/heroes", headers=hdr)).json()
    elite = hero_by(roster, "humai")
    locked = await c.post(f"/api/v1/heroes/{elite['id']}/signature", headers=hdr)
    assert locked.status_code == 409 and "Миф" in locked.json()["detail"]
    await add_heroes(pid, ("deyeu", "mythic", 1))
    roster = (await c.get("/api/v1/heroes", headers=hdr)).json()
    myth = hero_by(roster, "deyeu")
    assert myth["signature"]["unlocked"] and myth["signature"]["level"] == 0
    no = await c.post(f"/api/v1/heroes/{myth['id']}/signature", headers=hdr)
    assert no.status_code == 409 and "осколков наследия" in no.json()["detail"]
    await give(pid, legacy_shards=1000, gold=10**6)
    for _ in range(5):
        r = (await c.post(f"/api/v1/heroes/{myth['id']}/signature", headers=hdr)).json()
    sig = hero_by(r, "deyeu")["signature"]
    assert sig["level"] == 5 and sig["ult_percent"] == 10 and sig["stat_percent"] == 15
    # 10+15+20+25+30 осколков, 2000+4000+...+10000 золота
    assert r["wallet"]["legacy_shards"] == 1000 - 100 and r["wallet"]["gold"] == 10**6 - 30000
    assert hero_by(r, "deyeu")["stats"]["hp"] > myth["stats"]["hp"]


async def test_battle_uses_equipment(published):
    from app.api.battle import content_for
    from app.db import get_sessionmaker
    from app.models import Player
    from app.progression import heroes as prog
    c = published
    hdr, pid = await guest(c, "eq-battle-1")
    roster = (await c.get("/api/v1/heroes", headers=hdr)).json()
    ural = hero_by(roster, "ural_batyr")
    await c.post(f"/api/v1/heroes/{ural['id']}/auto-equip", headers=hdr)
    async with get_sessionmaker()() as s:
        player = await s.get(Player, uuid.UUID(pid))
        view = await content_for(player, s)
        team = await prog.build_team(s, player.id, view.json("config/progression.json"), view.heroes(),
                                     [{"hero": "ural_batyr", "slot": 0}], view.json("config/equipment.json"))
    assert team[0]["bonus"] == {"hp": 620, "atk": 26, "def": 8}  # обычные: шлем 300 + доспех 200 + сапоги 120
    from app.battle.sim import Battle
    units = [{"hero": "deyeu", "slot": 0}]
    plain = Battle(view.battle_config(), view.factions(), view.heroes(), [{"hero": "ural_batyr", "slot": 0}], units, 1)
    geared = Battle(view.battle_config(), view.factions(), view.heroes(), team, units, 1)
    assert geared.units[0].max_hp == plain.units[0].max_hp + 620
    assert geared.units[0].atk_base == plain.units[0].atk_base + 26


async def test_inventory_limit_turns_into_ore(published):
    from app.db import get_sessionmaker
    c = published
    hdr, pid = await guest(c, "eq-limit-1")
    await c.get("/api/v1/inventory", headers=hdr)  # 12 стартовых
    small = {**EQ, "inventory_limit": 13}
    async with get_sessionmaker()() as s:
        got = await eq.grant_items(s, uuid.UUID(pid), small, 3, "rare", ["ural_batyrs"])
        await s.commit()
    assert len(got["items"]) == 1 and got["ore_instead"] == 2 * 5
    inv = (await c.get("/api/v1/inventory", headers=hdr)).json()
    assert len(inv["items"]) == 13 and inv["wallet"]["ore"] == 10


async def test_ascension_returns_fodder_gear(published):
    c = published
    hdr, pid = await guest(c, "eq-ascend-1")
    await add_heroes(pid, ("ural_batyr", "elite", 1))
    roster = (await c.get("/api/v1/heroes", headers=hdr)).json()
    copies = sorted((h for h in roster["heroes"] if h["hero"] == "ural_batyr"), key=lambda h: h["id"])
    target, fodder = copies[0], copies[1]
    await c.post(f"/api/v1/heroes/{fodder['id']}/auto-equip", headers=hdr)
    r = await c.post(f"/api/v1/heroes/{target['id']}/ascend", headers=hdr)
    assert r.status_code == 200 and hero_by(r.json(), "ural_batyr")["tier"] == "elite_plus"
    inv = (await c.get("/api/v1/inventory", headers=hdr)).json()
    assert len(inv["items"]) == 12 and all(i["worn_by"] is None for i in inv["items"])

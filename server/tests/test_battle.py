import copy
import hashlib
import json
from pathlib import Path

import pytest

from app.battle.sim import Battle, BattleError, simulate
from app.content.validation import get_schema_registry

C = Path(__file__).resolve().parents[2] / "content"


def load():
    cfg = json.loads((C / "config/battle.json").read_text("utf-8"))
    fac = {f["id"]: f for f in json.loads((C / "factions/factions.json").read_text("utf-8"))["factions"]}
    heroes = {}
    for p in C.glob("heroes/*/hero.json"):
        h = json.loads(p.read_text("utf-8"))
        heroes[h["id"]] = h
    teams = {t["id"]: t["units"] for t in json.loads((C / "battle/test_teams.json").read_text("utf-8"))["teams"]}
    return cfg, fac, heroes, teams


CFG, FAC, HEROES, TEAMS = load()
MINE = [{"hero": "alpamysha", "slot": 0}, {"hero": "ural_batyr", "slot": 1}, {"hero": "zayatulyak", "slot": 2},
        {"hero": "humai", "slot": 3}, {"hero": "hyuhylu", "slot": 4}]


def h(log):
    return hashlib.sha256(json.dumps(log, sort_keys=True).encode()).hexdigest()


def test_15_heroes_4_factions():
    assert len(HEROES) == 15
    assert {x["faction"] for x in HEROES.values()} == set(FAC)
    for hero in HEROES.values():
        types = [s["type"] for s in hero["skills"]]
        assert types.count("ultimate") == 1 and len(types) == 4, hero["id"]


def test_deterministic():
    a = simulate(CFG, FAC, HEROES, MINE, TEAMS["test_evil"], seed=123)
    b = simulate(CFG, FAC, HEROES, MINE, TEAMS["test_evil"], seed=123)
    assert h(a) == h(b)
    others = {h(simulate(CFG, FAC, HEROES, MINE, TEAMS["test_evil"], seed=s)) for s in range(5)}
    assert len(others) > 1  # seed действительно влияет


def test_log_structure_and_schema():
    log = simulate(CFG, FAC, HEROES, MINE, TEAMS["test_forest"], seed=7)
    assert get_schema_registry().validate(log, "battle_log.schema.json", "log") == []
    ts = [e["t"] for e in log["events"]]
    assert ts == sorted(ts)
    assert log["events"][-1]["e"] in ("end", "victory")
    assert log["result"]["ticks"] <= log["max_ticks"]
    assert len(log["units"]) == 10


def test_mirror_is_fair():
    wins = sum(simulate(CFG, FAC, HEROES, TEAMS["test_evil"], TEAMS["test_evil"], seed=s)["result"]["winner"] == 0
               for s in range(200))
    assert 70 <= wins <= 130, wins


def test_faction_advantage():
    # Урал-батыр (батыры) бьёт Шульгена (нечисть) сильнее, чем Шульген его
    cfg = copy.deepcopy(CFG)
    cfg["damage"].update(variance=0, crit_chance=0)
    heroes = copy.deepcopy(HEROES)
    for x in heroes.values():
        x["stats"].pop("crit_chance", None)
    b = Battle(cfg, FAC, heroes, [{"hero": "ural_batyr", "slot": 0}], [{"hero": "deyeu", "slot": 0}], seed=1)
    log = b.run()
    first = {}
    for e in log["events"]:
        if e["e"] == "damage" and e["kind"] == "attack" and e["src"] not in first:
            first[e["src"]] = e["amount"]
    u = b.units[0]
    k = cfg["damage"]["defense_constant"]
    deyeu_def = b.units[1].def_base
    expected = round(u.atk_base * 1.25 * (1 - deyeu_def / (deyeu_def + k)))
    assert first[0] == expected


def test_timeout_is_defender_win():
    # Два лекаря не могут убить друг друга за 90 с
    log = simulate(CFG, FAC, HEROES, [{"hero": "humai", "slot": 0}], [{"hero": "humai", "slot": 0}], seed=1)
    assert log["result"]["ticks"] == log["max_ticks"] and log["result"]["winner"] == 1


def test_manual_ult_waits_for_request():
    b = Battle(CFG, FAC, HEROES, MINE, TEAMS["test_evil"], seed=5, auto=(False, True))
    casts_before_request = 0
    while not b.finished and b.t < 600:
        b.step()
    casts = [e for e in b.events if e["e"] == "cast" and e["kind"] == "ultimate" and e["u"] < 5]
    assert casts == []  # без нажатия ульты игрока не срабатывают
    full = [u for u in b.units if u.side == 0 and u.alive and u.energy >= 1000]
    if full:
        b.request_ult(full[0].uid)
        b.step()
        assert any(e["e"] == "cast" and e["kind"] == "ultimate" and e["u"] == full[0].uid for e in b.events)


def test_validation_errors():
    with pytest.raises(BattleError):
        Battle(CFG, FAC, HEROES, [{"hero": "nobody", "slot": 0}], TEAMS["test_evil"], seed=1)
    with pytest.raises(BattleError):
        Battle(CFG, FAC, HEROES, [{"hero": "humai", "slot": 0}, {"hero": "bisura", "slot": 0}], TEAMS["test_evil"], seed=1)


async def test_battle_api(client, tmp_path):
    import shutil

    from app.config import get_settings
    from app.content.releases import import_directory, publish
    from app.db import get_sessionmaker
    content = tmp_path / "content"
    shutil.copytree(get_settings().base_content_dir, content)
    async with get_sessionmaker()() as s:
        rel, _ = await import_directory(s, content)
        await publish(s, rel.id, "live")
        await s.commit()
    g = (await client.post("/api/v1/auth/guest", json={"device_id": "device-battle-1"})).json()
    hdr = {"Authorization": f"Bearer {g['access_token']}"}
    teams = (await client.get("/api/v1/battle/test-teams", headers=hdr)).json()["teams"]
    assert {t["id"] for t in teams} >= {"test_evil", "test_forest"}
    r = await client.post("/api/v1/battle/test", headers=hdr, json={"team": MINE, "enemy": "test_evil"})
    assert r.status_code == 200, r.text
    log = r.json()["log"]
    assert log["result"]["winner"] in (0, 1) and log["content_release"] == rel.id
    r = await client.post("/api/v1/battle/test", headers=hdr,
                          json={"team": [{"hero": "humai", "slot": 0}, {"hero": "humai", "slot": 1}], "enemy": "test_evil"})
    assert r.status_code == 422 and "дважды" in r.json()["detail"]
    assert (await client.post("/api/v1/battle/test", json={"team": MINE, "enemy": "test_evil"})).status_code == 401

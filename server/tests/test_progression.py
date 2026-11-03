import json
import shutil
from collections import Counter
from pathlib import Path

import pytest

from app.progression import summon as summ

C = Path(__file__).resolve().parents[2] / "content"
PROG = json.loads((C / "config/progression.json").read_text("utf-8"))
SUMMON = json.loads((C / "summon/banners.json").read_text("utf-8"))
STARTER = ["alpamysha", "ural_batyr", "zayatulyak", "humai", "hyuhylu"]


@pytest.fixture
async def published(client, tmp_path):
    from app.config import get_settings
    from app.content.releases import import_directory, publish
    from app.db import get_sessionmaker
    content = tmp_path / "content"
    shutil.copytree(get_settings().base_content_dir, content)
    async with get_sessionmaker()() as s:
        rel, _ = await import_directory(s, content)
        await publish(s, rel.id, "live")
        await s.commit()
    return client


async def guest(client, device):
    g = (await client.post("/api/v1/auth/guest", json={"device_id": device})).json()
    return {"Authorization": f"Bearer {g['access_token']}"}, g["player"]["id"]


async def give(player_id, **amounts):
    import uuid
    from app.db import get_sessionmaker
    from app.progression import wallet
    async with get_sessionmaker()() as s:
        await wallet.add(s, uuid.UUID(player_id), amounts)
        await s.commit()


async def add_heroes(player_id, *items):
    import uuid
    from app.db import get_sessionmaker
    from app.models import PlayerHero
    async with get_sessionmaker()() as s:
        for hero, tier, level in items:
            s.add(PlayerHero(player_id=uuid.UUID(player_id), hero_id=hero, tier=tier, level=level))
        await s.commit()


def test_rates_and_tiers_config():
    assert abs(sum(SUMMON["rates"].values()) - 1.0) < 1e-9
    assert SUMMON["pity_legendary"] == 30
    caps = [t["level_cap"] for t in PROG["tiers"]]
    assert caps == sorted(caps) and caps[-1] == 240
    tiers = {t["id"] for t in PROG["tiers"]}
    for rule in PROG["ascension"]:
        assert rule["from"] in tiers and rule["to"] in tiers


def test_roll_distribution():
    n = 200_000
    got = Counter(summ._roll_tier(SUMMON["rates"]) for _ in range(n))
    for tier, rate in SUMMON["rates"].items():
        assert abs(got[tier] / n - rate) < 0.006, (tier, got[tier] / n)


async def test_starter_once_and_wallet(published):
    c = published
    hdr, pid = await guest(c, "prog-starter-1")
    r1 = (await c.get("/api/v1/heroes", headers=hdr)).json()
    r2 = (await c.get("/api/v1/heroes", headers=hdr)).json()
    assert sorted(h["hero"] for h in r2["heroes"]) == sorted(STARTER)
    assert len(r2["heroes"]) == 5 and r2["wallet"]["crystals"] == 1000 and r2["wallet"]["scrolls"] == 10
    assert all(h["tier"] == "elite" and h["level"] == 1 for h in r1["heroes"])


async def test_level_up_costs_and_cap(published):
    c = published
    hdr, pid = await guest(c, "prog-level-1")
    heroes = (await c.get("/api/v1/heroes", headers=hdr)).json()["heroes"]
    h = heroes[0]
    r = await c.post(f"/api/v1/heroes/{h['id']}/level-up", headers=hdr, json={"times": 1})
    assert r.status_code == 409 and "Не хватает золота" in r.json()["detail"]
    await give(pid, gold=10_000_000, hero_xp=10_000_000, essence=10_000_000)
    r = await c.post(f"/api/v1/heroes/{h['id']}/level-up", headers=hdr, json={"times": 5})
    after = next(x for x in r.json()["heroes"] if x["id"] == h["id"])
    assert after["level"] == 6 and after["stats"]["hp"] > h["stats"]["hp"]
    spent = 10_000_000 - r.json()["wallet"]["gold"]
    assert spent == sum(round(15 * n ** 1.2) for n in range(1, 6))
    # предел уровня элиты — 100
    r = await c.post(f"/api/v1/heroes/{h['id']}/level-up", headers=hdr, json={"times": 100})
    r = await c.post(f"/api/v1/heroes/{h['id']}/level-up", headers=hdr, json={"times": 1})
    assert r.status_code == 409 and "предел уровня" in r.json()["detail"]


async def test_ascend_and_missing_fodder(published):
    c = published
    hdr, pid = await guest(c, "prog-ascend-1")
    heroes = (await c.get("/api/v1/heroes", headers=hdr)).json()["heroes"]
    humai = next(h for h in heroes if h["hero"] == "humai")
    r = await c.post(f"/api/v1/heroes/{humai['id']}/ascend", headers=hdr)
    assert r.status_code == 409 and "«Хумай»" in r.json()["detail"]
    await add_heroes(pid, ("humai", "elite", 1), ("humai", "elite", 1), ("ural_batyr", "elite", 1))
    r = await c.post(f"/api/v1/heroes/{humai['id']}/ascend", headers=hdr)
    assert r.status_code == 200, r.text
    assert next(h for h in r.json()["heroes"] if h["id"] == humai["id"])["tier"] == "elite_plus"
    # Элита+ -> Легенда: копия Хумай (элита) + любой элитный герой Батыров
    r = await c.post(f"/api/v1/heroes/{humai['id']}/ascend", headers=hdr)
    assert r.status_code == 200, r.text
    roster = r.json()["heroes"]
    assert next(h for h in roster if h["id"] == humai["id"])["tier"] == "legendary"
    # потрачены 3 копии, герои стартового отряда (кроме использованного Урал-батыра) на месте
    assert len(roster) == 5


async def test_crystal_of_resonance(published):
    c = published
    hdr, pid = await guest(c, "prog-crystal-1")
    await c.get("/api/v1/heroes", headers=hdr)
    await add_heroes(pid, ("mergen", "elite", 1))
    await give(pid, gold=10_000_000, hero_xp=10_000_000)
    roster = (await c.get("/api/v1/heroes", headers=hdr)).json()["heroes"]
    for h in roster:
        if h["hero"] != "mergen":
            await c.post(f"/api/v1/heroes/{h['id']}/level-up", headers=hdr, json={"times": 19 if h["hero"] != "humai" else 29})
    roster = (await c.get("/api/v1/heroes", headers=hdr)).json()["heroes"]
    strong = next(h for h in roster if h["hero"] == "humai")
    r = await c.post(f"/api/v1/heroes/{strong['id']}/crystal", headers=hdr, json={"put": True})
    assert r.status_code == 409 and "сильнейших" in r.json()["detail"]
    mergen = next(h for h in roster if h["hero"] == "mergen")
    r = await c.post(f"/api/v1/heroes/{mergen['id']}/crystal", headers=hdr, json={"put": True})
    assert r.status_code == 200, r.text
    m = next(h for h in r.json()["heroes"] if h["hero"] == "mergen")
    assert m["level"] == 20 and m["own_level"] == 1 and r.json()["crystal"]["level"] == 20
    r = await c.post(f"/api/v1/heroes/{mergen['id']}/level-up", headers=hdr, json={"times": 1})
    assert r.status_code == 409
    # убрали из кристалла — вернулся свой уровень
    r = await c.post(f"/api/v1/heroes/{mergen['id']}/crystal", headers=hdr, json={"put": False})
    assert next(h for h in r.json()["heroes"] if h["hero"] == "mergen")["level"] == 1


async def test_summon_first_legendary_pity_and_costs(published):
    c = published
    hdr, pid = await guest(c, "prog-summon-1")
    info = (await c.get("/api/v1/summon", headers=hdr)).json()
    normal = next(b for b in info["banners"] if b["id"] == "normal")
    assert normal["first_legendary"] and normal["pity_cap"] == 30
    assert {r["tier"]: r["percent"] for r in normal["rates"]} == {"rare": 51.6, "elite": 43.7, "legendary": 4.7}
    assert all(p["hero"] not in ("samrau", "katil") for p in normal["pool"])  # отдельные фракции — не в обычном пуле
    r = (await c.post("/api/v1/summon", headers=hdr, json={"banner": "normal", "count": 1})).json()
    assert r["results"][0]["tier"] == "legendary" and r["cost"] == {"scrolls": 1}
    r = (await c.post("/api/v1/summon", headers=hdr, json={"banner": "normal", "count": 1})).json()
    assert r["total"] == 2 and r["wallet"]["scrolls"] == 8
    # свитки кончились — оплата кристаллами (300 за призыв)
    await c.post("/api/v1/summon", headers=hdr, json={"banner": "normal", "count": 1})
    for _ in range(7):
        await c.post("/api/v1/summon", headers=hdr, json={"banner": "normal", "count": 1})
    r = await c.post("/api/v1/summon", headers=hdr, json={"banner": "normal", "count": 1})
    assert r.json()["cost"] == {"crystals": 300} and r.json()["wallet"]["crystals"] == 700
    r = await c.post("/api/v1/summon", headers=hdr, json={"banner": "normal", "count": 10})
    assert r.status_code == 409 and "10 свитков призыва или 3000 кристаллов" in r.json()["detail"]
    # гарант: без легенды не больше 29 призывов подряд
    await give(pid, crystals=1_000_000)
    streak = worst = 0
    for _ in range(25):  # 250 призывов (предел коллекции — 300 героев)
        res = (await c.post("/api/v1/summon", headers=hdr, json={"banner": "normal", "count": 10})).json()["results"]
        for x in res:
            streak = 0 if x["tier"] == "legendary" else streak + 1
            worst = max(worst, streak)
    assert worst <= 29


async def test_faction_and_event_banner(published):
    c = published
    hdr, pid = await guest(c, "prog-summon-2")
    await c.get("/api/v1/heroes", headers=hdr)
    r = await c.post("/api/v1/summon", headers=hdr, json={"banner": "faction_ural_batyrs", "count": 1})
    assert r.status_code == 409 and "свитков фракции" in r.json()["detail"], r.json()
    await give(pid, faction_scroll_ural_batyrs=20)
    r = (await c.post("/api/v1/summon", headers=hdr, json={"banner": "faction_ural_batyrs", "count": 10})).json()
    heroes = json.loads((C / "heroes/ural_batyr/hero.json").read_text("utf-8"))  # noqa: F841
    for x in r["results"]:
        h = json.loads((C / f"heroes/{x['hero']}/hero.json").read_text("utf-8"))
        assert h["faction"] == "ural_batyrs"
    info = (await c.get("/api/v1/summon", headers=hdr)).json()
    event = next(b for b in info["banners"] if b["id"] == "event_humai")
    assert any("Хумай" in r["name"] for r in event["rates"])


async def test_dismiss_rare_and_campaign_uses_own_heroes(published):
    c = published
    hdr, pid = await guest(c, "prog-dismiss-1")
    await c.get("/api/v1/heroes", headers=hdr)
    await add_heroes(pid, ("militia_ural", "rare", 1))
    roster = (await c.get("/api/v1/heroes", headers=hdr)).json()["heroes"]
    rare = next(h for h in roster if h["tier"] == "rare")
    r = await c.post(f"/api/v1/heroes/{rare['id']}/dismiss", headers=hdr)
    assert r.status_code == 200 and r.json()["wallet"]["essence"] == 100
    elite = next(h for h in roster if h["tier"] == "elite")
    assert (await c.post(f"/api/v1/heroes/{elite['id']}/dismiss", headers=hdr)).status_code == 409
    # Кампания: чужим героем нельзя
    r = await c.post("/api/v1/campaign/fight", headers=hdr, json={"stage": 1, "team": [{"hero": "samrau", "slot": 2}]})
    assert r.status_code == 422 and "нет героя" in r.json()["detail"]
    # Прокачанный герой сильнее в бою
    team = [{"hero": "alpamysha", "slot": 0}]
    log1 = (await c.post("/api/v1/campaign/fight", headers=hdr, json={"stage": 1, "team": team})).json()["log"]
    await give(pid, gold=10_000_000, hero_xp=10_000_000)
    alp = next(h for h in roster if h["hero"] == "alpamysha")
    await c.post(f"/api/v1/heroes/{alp['id']}/level-up", headers=hdr, json={"times": 10})
    log2 = (await c.post("/api/v1/campaign/fight", headers=hdr, json={"stage": 1, "team": team})).json()["log"]
    assert log2["units"][0]["max_hp"] > log1["units"][0]["max_hp"]

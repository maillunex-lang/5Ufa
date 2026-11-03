import asyncio
import threading
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace

from fastapi.testclient import TestClient
from app.campaign.rewards import DENOMINATOR, claim, pending, quick, settle
from app.config import get_settings
from app.content.releases import import_directory, publish
from app.db import get_sessionmaker

CONFIG = {"afk_cap_seconds": 43200, "gold_per_hour": 60, "hero_xp_per_hour": 30,
          "stage_bonus_percent": 5, "quick_seconds": 7200, "quick_daily_limit": 1}


def progress(now):
    return SimpleNamespace(cleared=0, gold=0, hero_xp=0, gold_fraction=0, xp_fraction=0,
                           crystal_fraction=0, essence_fraction=0,
                           elapsed_us=0, updated_at=now, quick_day="", quick_count=0)


def test_rewards_cap_and_change_of_rate():
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    p = progress(start)
    settle(p, CONFIG, start + timedelta(hours=1))
    p.cleared = 1
    settle(p, CONFIG, start + timedelta(hours=2))
    assert pending(p) == {"gold": 123, "hero_xp": 61, "crystals": 0, "essence": 0}
    assert claim(p) == {"gold": 123, "hero_xp": 61, "crystals": 0, "essence": 0}
    assert p.xp_fraction == DENOMINATOR // 2
    settle(p, CONFIG, start + timedelta(hours=30))
    assert p.elapsed_us == 43200 * 1_000_000
    assert pending(p) == {"gold": 756, "hero_xp": 378, "crystals": 0, "essence": 0}


def test_quick_ufa_day_and_does_not_empty_chest():
    now = datetime(2026, 1, 1, 18, 59, tzinfo=timezone.utc)
    p = progress(now)
    settle(p, CONFIG, now + timedelta(minutes=1))
    before = p.elapsed_us
    assert quick(p, CONFIG, now) == {"gold": 120, "hero_xp": 60, "crystals": 0, "essence": 0}
    assert quick(p, CONFIG, now) is None
    assert quick(p, CONFIG, now + timedelta(minutes=1)) == {"gold": 120, "hero_xp": 60, "crystals": 0, "essence": 0}
    assert p.elapsed_us == before


async def test_api_quick_and_locked_stage(client):
    async with get_sessionmaker()() as session:
        release, _ = await import_directory(session, get_settings().base_content_dir)
        await publish(session, release.id, "live")
        await session.commit()
    guest = (await client.post("/api/v1/auth/guest", json={"device_id": "campaign-device-123"})).json()
    headers = {"Authorization": "Bearer " + guest["access_token"]}
    initial = (await client.get("/api/v1/campaign", headers=headers)).json()
    assert len(initial["chapters"]) == 5 and initial["cleared"] == 0
    reward = await client.post("/api/v1/campaign/quick", headers=headers)
    assert reward.json()["reward"] == {"gold": 120, "hero_xp": 60, "crystals": 10, "essence": 20}
    assert (await client.post("/api/v1/campaign/quick", headers=headers)).status_code == 409
    locked = await client.post("/api/v1/campaign/fight", headers=headers,
                               json={"stage": 2, "team": [{"hero": "ural_batyr", "slot": 0}]})
    assert locked.status_code == 403


async def test_victory_reward_only_once(client, monkeypatch):
    from app.api import campaign
    async with get_sessionmaker()() as session:
        release, _ = await import_directory(session, get_settings().base_content_dir)
        await publish(session, release.id, "live")
        await session.commit()
    monkeypatch.setattr(campaign.secrets, "randbits", lambda _: 7)
    guest = (await client.post("/api/v1/auth/guest", json={"device_id": "campaign-fight-123"})).json()
    headers = {"Authorization": "Bearer " + guest["access_token"]}
    team = [{"hero": h, "slot": i} for i, h in enumerate(["alpamysha", "ural_batyr", "zayatulyak", "humai", "hyuhylu"])]
    body = {"stage": 1, "team": team}
    first = (await client.post("/api/v1/campaign/fight", headers=headers, json=body)).json()
    assert first["log"]["result"]["winner"] == 0
    assert first["reward"] == {"gold": 100, "hero_xp": 50, "crystals": 20}
    repeat = (await client.post("/api/v1/campaign/fight", headers=headers, json=body)).json()
    assert repeat["reward"] == {"gold": 0, "hero_xp": 0}
    assert repeat["status"]["cleared"] == 1


async def test_live_campaign_rewards_and_disconnect(client, monkeypatch):
    from app.api import battle
    from app.main import app
    async with get_sessionmaker()() as session:
        release, _ = await import_directory(session, get_settings().base_content_dir)
        await publish(session, release.id, "live")
        await session.commit()
    monkeypatch.setattr(battle.secrets, "randbits", lambda _: 7)
    settled = threading.Event()
    original_award = battle._award_campaign
    async def record_award(game, context):
        result = await original_award(game, context)
        if context[1] == 2:
            settled.set()
        return result
    monkeypatch.setattr(battle, "_award_campaign", record_award)
    guest = (await client.post("/api/v1/auth/guest", json={"device_id": "campaign-live-123"})).json()
    headers = {"Authorization": "Bearer " + guest["access_token"]}
    team = [{"hero": h, "slot": i} for i, h in enumerate(["alpamysha", "ural_batyr", "zayatulyak", "humai", "hyuhylu"])]

    def exercise():
        with TestClient(app) as sync:
            with sync.websocket_connect("/ws/battle/campaign", headers=headers) as ws:
                ws.send_json({"stage": 1, "team": team})
                assert ws.receive_json()["type"] == "start"
                ws.send_json({"type": "skip"})
                while True:
                    msg = ws.receive_json()
                    if msg["type"] == "end":
                        assert msg["result"]["winner"] == 0
                        assert msg["campaign_reward"] == {"gold": 100, "hero_xp": 50, "crystals": 20}
                        ws.send_json({"type": "ack"})
                        break
            with sync.websocket_connect("/ws/battle/campaign", headers=headers) as ws:
                ws.send_json({"stage": 2, "team": team})
                assert ws.receive_json()["type"] == "start"
                ws.close()
                assert settled.wait(3), "После обрыва бой не был завершён"
    await asyncio.to_thread(exercise)
    result = (await client.get("/api/v1/campaign", headers=headers)).json()
    assert result["cleared"] == 2 and result["gold"] == 200 and result["hero_xp"] == 100

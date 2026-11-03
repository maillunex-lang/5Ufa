import asyncio
import threading

from fastapi.testclient import TestClient

from app.config import get_settings
from app.content.releases import import_directory, publish
from app.db import get_sessionmaker
from app.main import app


async def test_live_battle_and_authorization(client, monkeypatch):
    from app.api import battle as battle_api
    auto_finished = threading.Event()

    class ReadyBattle(battle_api.Battle):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            self.units[0].energy = self.cfg["energy"]["max"]

        def run(self):
            result = super().run()
            if self.auto[0]:
                auto_finished.set()
            return result

    monkeypatch.setattr(battle_api, "Battle", ReadyBattle)
    async with get_sessionmaker()() as session:
        release, _ = await import_directory(session, get_settings().base_content_dir)
        await publish(session, release.id, "live")
        await session.commit()
    guest = (await client.post("/api/v1/auth/guest", json={"device_id": "live-test-device-123"})).json()
    headers = {"Authorization": "Bearer " + guest["access_token"]}
    teams = (await client.get("/api/v1/battle/test-teams", headers=headers)).json()["teams"]
    team = teams[0]["units"][:1]
    body = {"team": [{"hero": team[0]["hero"], "slot": 0}], "enemy": teams[0]["id"]}

    def exercise():
        with TestClient(app) as sync:
            with sync.websocket_connect("/ws/battle/test") as ws:
                assert ws.receive_json()["type"] == "error"
            with sync.websocket_connect("/ws/battle/test", headers=headers) as ws:
                ws.send_json(body)
                start = ws.receive_json()
                assert start["type"] == "start"
                assert start["log"]["units"][0]["side"] == 0
                ws.send_json({"type": "ult", "uid": 999})
                ws.send_json({"type": "ult", "uid": 0})
                manual_cast = False
                for _ in range(30):
                    msg = ws.receive_json()
                    manual_cast |= any(e["e"] == "cast" and e.get("u") == 0 and e.get("kind") == "ultimate"
                                       for e in msg.get("events", []))
                    if manual_cast:
                        break
                assert manual_cast
                ws.send_json({"type": "auto", "on": True})
                ws.send_json({"type": "skip"})
                events = []
                while True:
                    msg = ws.receive_json()
                    events.extend(msg.get("events", []))
                    if msg["type"] == "end":
                        assert msg["result"]["winner"] in (0, 1)
                        assert any(e["e"] == "end" for e in events)
                        ws.send_json({"type": "ack"})
                        break
            auto_finished.clear()
            with sync.websocket_connect("/ws/battle/test", headers=headers) as ws:
                ws.send_json(body)
                assert ws.receive_json()["type"] == "start"
                ws.close()
            assert auto_finished.wait(3), "После обрыва бой не досчитан на авто"
    await asyncio.to_thread(exercise)

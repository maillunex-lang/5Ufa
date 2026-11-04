"""Этап 6б: игроки, бэкапы, версии APK, веб-админка; деплой контента без потери правок из админки."""
import io
import json
import shutil
import zipfile

from tests.test_admin import admin_headers, channel_release, make_admin
from tests.test_progression import guest, published  # noqa: F401


async def test_players_search_card_wallet_test_ban(published):
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    phdr, pid = await guest(c, "ops-player-0001")
    await c.get("/api/v1/heroes", headers=phdr)  # стартовый набор
    found = (await c.get("/api/v1/admin/players", params={"q": ""}, headers=hdr)).json()["items"]
    me = next(p for p in found if p["id"] == pid)
    by_num = (await c.get("/api/v1/admin/players", params={"q": f"#{me['number']}"}, headers=hdr)).json()["items"]
    assert [p["id"] for p in by_num] == [pid]
    card = (await c.get(f"/api/v1/admin/players/{pid}", headers=hdr)).json()
    assert len(card["heroes"]) == 5 and card["wallet"]["crystals"] == 1000
    # Ресурсы: причина обязательна, в минус уйти нельзя
    assert (await c.post(f"/api/v1/admin/players/{pid}/wallet", headers=hdr, json={"changes": {"gold": 500}})).status_code == 422
    r = (await c.post(f"/api/v1/admin/players/{pid}/wallet", headers=hdr,
                      json={"changes": {"gold": 500, "crystals": -100}, "reason": "компенсация"})).json()
    assert r["wallet"]["gold"] == 500 and r["wallet"]["crystals"] == 900
    neg = await c.post(f"/api/v1/admin/players/{pid}/wallet", headers=hdr, json={"changes": {"gold": -501}, "reason": "ошибка"})
    assert neg.status_code == 409
    assert (await c.get("/api/v1/heroes", headers=phdr)).json()["wallet"]["gold"] == 500
    # Тестовый аккаунт и бан
    t = (await c.post(f"/api/v1/admin/players/{pid}/test", headers=hdr, json={"on": True})).json()
    assert t["player"]["is_test"]
    assert (await c.post(f"/api/v1/admin/players/{pid}/ban", headers=hdr, json={"days": 3})).status_code == 422
    b = (await c.post(f"/api/v1/admin/players/{pid}/ban", headers=hdr, json={"days": 3, "reason": "мат в чате"})).json()
    assert b["player"]["banned_until"]
    assert (await c.get("/api/v1/heroes", headers=phdr)).status_code == 403
    await c.post(f"/api/v1/admin/players/{pid}/ban", headers=hdr, json={"days": 0})
    await c.post(f"/api/v1/admin/players/{pid}/test", headers=hdr, json={"on": False})  # канала test в тесте нет
    assert (await c.get("/api/v1/heroes", headers=phdr)).status_code == 200
    log = (await c.get("/api/v1/admin/audit", headers=hdr)).json()["items"]
    w = next(x for x in log if x["action"] == "player_wallet")
    assert "компенсация" in w["summary"] and w["details"]["before"]["gold"] == 0 and w["details"]["after"]["gold"] == 500
    assert {"player_test", "player_ban"} <= {x["action"] for x in log}


async def test_roles(published):
    c = published
    await make_admin("mod", role="moderator")
    await make_admin("ed", role="editor")
    mod = await admin_headers(c, "mod")
    ed = await admin_headers(c, "ed")
    assert (await c.get("/api/v1/admin/players", headers=mod)).status_code == 200
    assert (await c.get("/api/v1/admin/players", headers=ed)).status_code == 403
    assert (await c.get("/api/v1/admin/backups", headers=mod)).status_code == 403
    assert (await c.get("/api/v1/admin/sections", headers=ed)).status_code == 200


async def test_backups_and_client_releases(published, tmp_path, monkeypatch):
    from app.config import get_settings
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    monkeypatch.setattr(get_settings(), "backup_dir", tmp_path)
    (tmp_path / "2026-11-01_0000").mkdir()
    (tmp_path / "2026-11-01_0000" / "db.dump").write_bytes(b"x" * 10)
    (tmp_path / "2026-11-01_0000" / "SHA256SUMS").write_text("ok")
    lst = (await c.get("/api/v1/admin/backups", headers=hdr)).json()
    assert lst["items"][0]["name"] == "2026-11-01_0000" and lst["items"][0]["complete"]
    assert (await c.post("/api/v1/admin/backups/run", headers=hdr)).status_code == 503  # сервис ещё не готов
    (tmp_path / ".requests").mkdir()
    assert (await c.post("/api/v1/admin/backups/run", headers=hdr)).status_code == 200
    assert (tmp_path / ".requests" / "run").is_file()
    assert (await c.get("/api/v1/admin/backups", headers=hdr)).json()["pending"]
    # Версии APK
    from app.db import get_sessionmaker
    from app.models import ClientRelease
    async with get_sessionmaker()() as s:
        s.add(ClientRelease(version_code=5, version_name="0.1.5", sha256="a" * 64, size=1))
        await s.commit()
    r = await c.post("/api/v1/admin/client-releases/5", headers=hdr, json={"mandatory": True})
    assert r.status_code == 200
    items = (await c.get("/api/v1/admin/client-releases", headers=hdr)).json()["items"]
    assert items[0]["mandatory"]
    await c.post("/api/v1/admin/client-releases/5", headers=hdr, json={"active": False})
    items = (await c.get("/api/v1/admin/client-releases", headers=hdr)).json()["items"]
    assert not items[0]["active"] and not items[0]["mandatory"]


async def test_admin_web_upload(published, monkeypatch):
    from app.config import get_settings
    c = published
    monkeypatch.setattr(get_settings(), "client_upload_token", "tok")
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("index.html", "<html>admin</html>")
        zf.writestr("index.wasm", b"\0asm")
        zf.writestr("../evil.txt", "x")
    assert (await c.put("/api/v1/admin-web/0.1.20", content=buf.getvalue(), headers={"X-Upload-Token": "bad"})).status_code == 403
    r = await c.put("/api/v1/admin-web/0.1.20", content=buf.getvalue(), headers={"X-Upload-Token": "tok"})
    assert r.status_code == 200
    root = get_settings().content_store_dir / "admin-web"
    assert (root / "current" / "index.html").read_text() == "<html>admin</html>"
    assert not (root / "evil.txt").exists() and not (root.parent / "evil.txt").exists()


async def test_deploy_keeps_admin_changes(published, tmp_path):
    """Деплой с изменённым контентом репозитория не затирает правки, опубликованные из админки."""
    from app.config import get_settings
    from app.content.releases import import_base_merged
    from app.db import get_sessionmaker
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    # Первый базовый импорт (как при деплое)
    repo = tmp_path / "repo"
    shutil.copytree(get_settings().base_content_dir, repo)
    async with get_sessionmaker()() as s:
        base1, msg = await import_base_merged(s, repo, "деплой 1")
        await s.commit()
    assert base1 is None and "не изменился" in msg  # тот же контент уже опубликован
    # Правка в админке и публикация: имя Хумай
    hero = (await c.get("/api/v1/admin/sections/heroes/objects/humai", headers=hdr)).json()["data"]
    await c.put("/api/v1/admin/sections/heroes/objects/humai", headers=hdr, json={"data": {**hero, "name": "Хумай А"}})
    pub = (await c.post("/api/v1/admin/draft/publish", headers=hdr, json={"confirm": True})).json()
    # В репозитории поменялся другой файл: фракции
    f = json.loads((repo / "factions/factions.json").read_text("utf-8"))
    f["factions"][0]["name"] = "Батыры Урала (репо)"
    (repo / "factions/factions.json").write_text(json.dumps(f, ensure_ascii=False), "utf-8")
    async with get_sessionmaker()() as s:
        merged, msg = await import_base_merged(s, repo, "деплой 2")
        await s.commit()
    assert merged is not None and merged.source == "merge" and "сохранены" in msg
    assert await channel_release("live") == merged.id != pub["release"]
    h = (await c.get("/api/v1/admin/sections/heroes/objects/humai", headers=hdr)).json()["data"]
    fac = (await c.get("/api/v1/admin/sections/factions/objects/ural_batyrs", headers=hdr)).json()["data"]
    assert h["name"] == "Хумай А" and fac["name"] == "Батыры Урала (репо)"
    # Повторный деплой без изменений ничего не публикует
    async with get_sessionmaker()() as s:
        again, msg = await import_base_merged(s, repo, "деплой 3")
        await s.commit()
    assert again is None and await channel_release("live") == merged.id

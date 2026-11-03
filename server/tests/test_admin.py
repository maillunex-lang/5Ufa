"""Этап 6а: вход в админку, журнал, черновик → тест → публикация → откат, ZIP-патчи."""
import io
import json
import zipfile

import pytest

from tests.test_progression import published  # noqa: F401

PASSWORD = "very-secret-42"


async def make_admin(login="owner", role="owner", totp_secret=None):
    from app.auth.security import hash_password
    from app.db import get_sessionmaker
    from app.models import AdminUser
    async with get_sessionmaker()() as s:
        s.add(AdminUser(login=login, password_hash=hash_password(PASSWORD), role=role,
                        totp_secret=totp_secret, totp_enabled=bool(totp_secret)))
        await s.commit()


async def admin_headers(c, login="owner"):
    r = await c.post("/api/v1/admin/auth/login", json={"login": login, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return {"Authorization": "Bearer " + r.json()["token"]}


def zip_of(patch: dict, files: dict | None = None) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr("patch.json", json.dumps(patch, ensure_ascii=False))
        for p, d in (files or {}).items():
            zf.writestr("files/" + p, d)
    return buf.getvalue()


async def channel_release(name):
    from app.content.releases import get_channel_release
    from app.db import get_sessionmaker
    async with get_sessionmaker()() as s:
        r = await get_channel_release(s, name)
        return r.id if r else None


async def test_login_limit_and_auth(published):
    c = published
    await make_admin()
    assert (await c.get("/api/v1/admin/me")).status_code == 401
    assert (await c.get("/api/v1/admin/me", headers={"Authorization": "Bearer adm_fake"})).status_code == 401
    for _ in range(5):
        r = await c.post("/api/v1/admin/auth/login", json={"login": "owner", "password": "wrong-password"})
        assert r.status_code == 401
    blocked = await c.post("/api/v1/admin/auth/login", json={"login": "owner", "password": PASSWORD})
    assert blocked.status_code == 429 and "попыток" in blocked.json()["detail"]
    from app.redis_client import get_redis
    await get_redis().flushall()
    hdr = await admin_headers(c)
    me = (await c.get("/api/v1/admin/me", headers=hdr)).json()
    assert me == {"login": "owner", "role": "owner", "totp_enabled": False}
    log = (await c.get("/api/v1/admin/audit", headers=hdr)).json()["items"]
    assert [x["action"] for x in log][:1] == ["login"] and sum(x["action"] == "login_failed" for x in log) == 5
    assert (await c.post("/api/v1/admin/auth/logout", headers=hdr)).status_code == 200
    assert (await c.get("/api/v1/admin/me", headers=hdr)).status_code == 401
    # Игроковый токен в админку не пускает
    g = (await c.post("/api/v1/auth/guest", json={"device_id": "admin-test-player"})).json()
    assert (await c.get("/api/v1/admin/me", headers={"Authorization": "Bearer " + g["access_token"]})).status_code == 401


async def test_totp_login(published):
    from app.admin.security import totp_code, totp_new_secret
    import time
    c = published
    secret = totp_new_secret()
    await make_admin("guard", totp_secret=secret)
    r = await c.post("/api/v1/admin/auth/login", json={"login": "guard", "password": PASSWORD})
    assert r.status_code == 401 and r.json()["totp_required"]
    bad = await c.post("/api/v1/admin/auth/login", json={"login": "guard", "password": PASSWORD, "code": "000000"})
    assert bad.status_code == 401
    code = totp_code(secret, int(time.time() // 30))
    ok = await c.post("/api/v1/admin/auth/login", json={"login": "guard", "password": PASSWORD, "code": code})
    assert ok.status_code == 200


async def test_moderator_cannot_edit_content(published):
    c = published
    await make_admin("mod", role="moderator")
    hdr = await admin_headers(c, "mod")
    assert (await c.get("/api/v1/admin/sections", headers=hdr)).status_code == 403


async def test_draft_test_publish_rollback(published):
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    live0 = await channel_release("live")
    secs = (await c.get("/api/v1/admin/sections", headers=hdr)).json()
    ids = {s["id"] for s in secs["sections"]}
    assert {"heroes", "factions", "campaign", "summon", "equipment", "hub", "settings"} <= ids
    heroes = (await c.get("/api/v1/admin/sections/heroes", headers=hdr)).json()
    assert any(o["id"] == "humai" for o in heroes["objects"])
    hero = (await c.get("/api/v1/admin/sections/heroes/objects/humai", headers=hdr)).json()
    assert hero["schema"] == "hero.schema.json"
    # Ошибка схемы — понятный список, черновик не меняется
    broken = dict(hero["data"])
    broken.pop("stats")
    bad = await c.put("/api/v1/admin/sections/heroes/objects/humai", headers=hdr, json={"data": broken})
    assert bad.status_code == 422 and bad.json()["detail"]["errors"]
    assert (await c.get("/api/v1/admin/draft", headers=hdr)).json()["changes"] == []
    # Правка имени -> черновик
    data = {**hero["data"], "name": "Хумай Светлая"}
    r = await c.put("/api/v1/admin/sections/heroes/objects/humai", headers=hdr, json={"data": data})
    assert r.status_code == 200, r.text
    draft = (await c.get("/api/v1/admin/draft", headers=hdr)).json()
    assert draft["changes"] == [{"path": "heroes/humai/hero.json", "change": "update", "size": draft["changes"][0]["size"],
                                 "updated_at": draft["changes"][0]["updated_at"]}]
    # Вернуть как было — правка исчезает сама
    await c.put("/api/v1/admin/sections/heroes/objects/humai", headers=hdr, json={"data": hero["data"]})
    assert (await c.get("/api/v1/admin/draft", headers=hdr)).json()["changes"] == []
    await c.put("/api/v1/admin/sections/heroes/objects/humai", headers=hdr, json={"data": data})
    # На тест: видит только канал test
    t = (await c.post("/api/v1/admin/draft/test", headers=hdr, json={"comment": "имя Хумай"})).json()
    assert await channel_release("test") == t["release"] and await channel_release("live") == live0
    # Публикация без подтверждения — нельзя
    assert (await c.post("/api/v1/admin/draft/publish", headers=hdr, json={})).status_code == 400
    p = (await c.post("/api/v1/admin/draft/publish", headers=hdr, json={"confirm": True, "comment": "релиз"})).json()
    assert await channel_release("live") == p["release"]
    assert (await c.get("/api/v1/admin/draft", headers=hdr)).json()["changes"] == []
    manifest = (await c.get("/api/v1/content/manifest")).json()
    assert manifest["release"] == p["release"]
    # Откат к исходной версии
    assert (await c.post(f"/api/v1/admin/releases/{live0}/publish", headers=hdr, json={"channel": "live"})).status_code == 400
    rb = await c.post(f"/api/v1/admin/releases/{live0}/publish", headers=hdr, json={"channel": "live", "confirm": True})
    assert rb.status_code == 200 and await channel_release("live") == live0
    rel = (await c.get("/api/v1/admin/releases", headers=hdr)).json()
    assert rel["channels"]["live"] == live0 and rel["items"][0]["source"] == "admin"
    actions = [x["action"] for x in (await c.get("/api/v1/admin/audit", headers=hdr)).json()["items"]]
    assert "rollback" in actions and "publish" in actions and "draft_test" in actions and "object_update" in actions


async def test_files_and_array_sections(published):
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    png = b"\x89PNG\r\n\x1a\n" + b"0" * 100
    r = await c.put("/api/v1/admin/files", params={"path": "ui/hub/background.webp"}, headers=hdr, content=png)
    assert r.status_code == 200 and r.json()["changed"]
    got = await c.get("/api/v1/admin/files", params={"path": "ui/hub/background.webp"}, headers=hdr)
    assert got.content == png
    assert (await c.put("/api/v1/admin/files", params={"path": "../etc/passwd"}, headers=hdr, content=b"x")).status_code == 422
    assert (await c.put("/api/v1/admin/files", params={"path": "ui/x.exe"}, headers=hdr, content=b"x")).status_code == 422
    # Объект в массиве: фракция
    f = (await c.get("/api/v1/admin/sections/factions/objects/ural_batyrs", headers=hdr)).json()
    upd = {**f["data"], "name": "Батыры"}
    assert (await c.put("/api/v1/admin/sections/factions/objects/ural_batyrs", headers=hdr, json={"data": upd})).status_code == 200
    f2 = (await c.get("/api/v1/admin/sections/factions/objects/ural_batyrs", headers=hdr)).json()
    assert f2["data"]["name"] == "Батыры"
    # Удалить героя, на которого ссылаются отряды и стартовый набор, нельзя
    d = await c.delete("/api/v1/admin/sections/heroes/objects/humai", headers=hdr)
    assert d.status_code == 422 and any("humai" in e for e in d.json()["detail"]["errors"])
    rv = (await c.post("/api/v1/admin/draft/revert", headers=hdr, json={})).json()
    assert rv["reverted"] == 2


async def test_zip_patch_preview_and_apply(published):
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    patch = {"id": "heroes-test-1", "format_version": 1, "section": "heroes", "description": "Тест",
             "operations": [
                 {"op": "update", "id": "humai", "data": {"stats": {"atk": 150}}, "files": ["heroes/humai/portrait.png"]},
                 {"op": "put_file", "path": "heroes/humai/extra.png"},
             ]}
    files = {"heroes/humai/portrait.png": b"\x89PNG-new", "heroes/humai/extra.png": b"\x89PNG-extra", "junk/a.png": b"x"}
    pv = (await c.post("/api/v1/admin/patches/preview", headers=hdr, content=zip_of(patch, files))).json()
    assert pv["ok"], pv["errors"]
    assert {x["path"] for x in pv["changes"]} == {"heroes/humai/hero.json", "heroes/humai/portrait.png", "heroes/humai/extra.png"}
    assert pv["warnings"] and "junk/a.png" in pv["warnings"][0]
    assert (await c.get("/api/v1/admin/draft", headers=hdr)).json()["changes"] == []  # предпросмотр ничего не меняет
    ap = await c.post("/api/v1/admin/patches/apply", headers=hdr, content=zip_of(patch, files))
    assert ap.status_code == 200
    hero = (await c.get("/api/v1/admin/sections/heroes/objects/humai", headers=hdr)).json()["data"]
    assert hero["stats"]["atk"] == 150 and hero["stats"]["hp"] > 0  # слияние, остальные поля на месте
    # Ошибки — по-русски и без изменений
    bad = {"id": "bad-1", "format_version": 1, "section": "heroes", "description": "x",
           "operations": [{"op": "add", "id": "humai", "data": {}}, {"op": "update", "id": "nobody", "data": {}},
                          {"op": "update", "id": "humai", "data": {"stats": {"atk": "много"}}}]}
    r = (await c.post("/api/v1/admin/patches/preview", headers=hdr, content=zip_of(bad))).json()
    assert not r["ok"] and any("уже есть" in e for e in r["errors"]) and any("nobody" in e for e in r["errors"])
    assert (await c.post("/api/v1/admin/patches/apply", headers=hdr, content=zip_of(bad))).status_code == 422
    junk = (await c.post("/api/v1/admin/patches/preview", headers=hdr, content=b"not a zip")).json()
    assert not junk["ok"] and "ZIP" in junk["errors"][0]


async def test_export_and_prompt(published):
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    z = await c.get("/api/v1/admin/sections/summon/export", headers=hdr)
    assert z.status_code == 200
    zf = zipfile.ZipFile(io.BytesIO(z.content))
    patch = json.loads(zf.read("patch.json"))
    assert patch["section"] == "summon" and any(op["id"] == "normal" for op in patch["operations"] if "id" in op)
    # Выгрузку можно сразу загрузить обратно как патч (add уже существующих — ошибка, это ожидаемо)
    pr = (await c.get("/api/v1/admin/sections/heroes/prompt", headers=hdr)).json()["prompt"]
    assert "hero.schema.json" in pr and "patch.json" in pr and "humai" in pr
    exp = await c.get("/api/v1/admin/sections/hub/export", headers=hdr)
    names = zipfile.ZipFile(io.BytesIO(exp.content)).namelist()
    assert "files/ui/hub/background.webp" in names


async def test_publish_build_errors_are_readable(published):
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    # Файл вне всех пакетов — сборка версии должна объяснить ошибку
    await c.put("/api/v1/admin/files", params={"path": "nowhere/pic.png"}, headers=hdr, content=b"\x89PNG")
    r = await c.post("/api/v1/admin/draft/test", headers=hdr, json={})
    assert r.status_code == 422 and any("пакет" in e for e in r.json()["detail"]["errors"])

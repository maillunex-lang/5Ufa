"""Этап 6в-2: скины героев, выгрузка героя ZIP."""
import io
import json
import zipfile

from tests.test_admin import admin_headers, make_admin
from tests.test_progression import guest, published  # noqa: F401


def hero_of(roster, hero_id):
    return next(h for h in roster["heroes"] if h["hero"] == hero_id)


async def test_skin_create_publish_grant_choose_battle(published):
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    # Новый скин: копия картинок обычного вида
    r = await c.post("/api/v1/admin/heroes/humai/skins", headers=hdr, json={"skin": "winter", "name": "Зимняя"})
    assert r.status_code == 200 and r.json()["files"] >= 10, r.text
    draft = (await c.get("/api/v1/admin/draft", headers=hdr)).json()
    paths = {x["path"] for x in draft["changes"]}
    assert "heroes/humai/hero.json" in paths and "heroes/humai/skins/winter/portrait.png" in paths
    assert any(p.startswith("heroes/humai/skins/winter/rig/") for p in paths)
    assert (await c.post("/api/v1/admin/heroes/humai/skins", headers=hdr,
                         json={"skin": "winter", "name": "x"})).status_code == 409
    assert (await c.post("/api/v1/admin/draft/publish", headers=hdr, json={"confirm": True})).status_code == 200
    # Игрок: скин виден, но не получен
    phdr, pid = await guest(c, "skin-player-001")
    roster = (await c.get("/api/v1/heroes", headers=phdr)).json()
    h = hero_of(roster, "humai")
    assert h["skin"] == "default" and {s["id"]: s["owned"] for s in h["skins"]} == {"default": True, "winter": False}
    no = await c.post("/api/v1/heroes/skin", headers=phdr, json={"hero": "humai", "skin": "winter"})
    assert no.status_code == 409
    # Админ выдаёт — игрок выбирает — в бою виден скин
    g = await c.post(f"/api/v1/admin/players/{pid}/skins", headers=hdr,
                     json={"hero": "humai", "skin": "winter", "reason": "подарок"})
    assert g.status_code == 200
    r = (await c.post("/api/v1/heroes/skin", headers=phdr, json={"hero": "humai", "skin": "winter"})).json()
    assert hero_of(r, "humai")["skin"] == "winter"
    team = [{"hero": "humai", "slot": 0}, {"hero": "alpamysha", "slot": 1}]
    fight = (await c.post("/api/v1/campaign/fight", headers=phdr, json={"stage": 1, "team": team})).json()
    skins = {u["hero"]: u["skin"] for u in fight["log"]["units"] if u["side"] == 0}
    assert skins == {"humai": "winter", "alpamysha": "default"}
    card = (await c.get(f"/api/v1/admin/players/{pid}", headers=hdr)).json()
    assert card["skins"] == ["humai:winter"]
    # Забрали скин — снова обычный вид
    await c.post(f"/api/v1/admin/players/{pid}/skins", headers=hdr,
                 json={"hero": "humai", "skin": "winter", "give": False, "reason": "ошибка"})
    assert hero_of((await c.get("/api/v1/heroes", headers=phdr)).json(), "humai")["skin"] == "default"


async def test_free_skin_and_delete(published):
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    await c.post("/api/v1/admin/heroes/ural_batyr/skins", headers=hdr, json={"skin": "gold", "name": "Золотой", "free": True})
    await c.post("/api/v1/admin/draft/publish", headers=hdr, json={"confirm": True})
    phdr, _ = await guest(c, "skin-player-002")
    r = (await c.post("/api/v1/heroes/skin", headers=phdr, json={"hero": "ural_batyr", "skin": "gold"})).json()
    assert hero_of(r, "ural_batyr")["skin"] == "gold"
    # Скин удалили из игры — у игрока снова обычный вид, без ошибок
    assert (await c.delete("/api/v1/admin/heroes/ural_batyr/skins/gold", headers=hdr)).status_code == 200
    draft = (await c.get("/api/v1/admin/draft", headers=hdr)).json()
    assert all(x["change"] == "delete" for x in draft["changes"] if "/skins/gold/" in x["path"])
    await c.post("/api/v1/admin/draft/publish", headers=hdr, json={"confirm": True})
    assert hero_of((await c.get("/api/v1/heroes", headers=phdr)).json(), "ural_batyr")["skin"] == "default"


async def test_hero_zip_roundtrip(published):
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    z = await c.get("/api/v1/admin/heroes/humai/export", headers=hdr)
    assert z.status_code == 200
    zf = zipfile.ZipFile(io.BytesIO(z.content))
    names = zf.namelist()
    assert "patch.json" in names and "files/heroes/humai/skeleton.json" in names
    assert any(n.startswith("files/heroes/humai/rig/") for n in names)
    patch = json.loads(zf.read("patch.json"))
    # Художник заменил картинку и имя — загрузка обратно
    patch["operations"][0]["data"]["name"] = "Хумай (новая)"
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as out:
        out.writestr("patch.json", json.dumps(patch, ensure_ascii=False))
        for n in names:
            if n.startswith("files/"):
                data = b"\x89PNG-new" if n.endswith("portrait.png") else zf.read(n)
                out.writestr(n, data)
    pv = (await c.post("/api/v1/admin/patches/preview", headers=hdr, content=buf.getvalue())).json()
    assert pv["ok"], pv["errors"]
    ap = await c.post("/api/v1/admin/patches/apply", headers=hdr, content=buf.getvalue())
    assert ap.status_code == 200
    draft = (await c.get("/api/v1/admin/draft", headers=hdr)).json()
    paths = {x["path"] for x in draft["changes"]}
    assert paths == {"heroes/humai/hero.json", "heroes/humai/portrait.png"}  # неизменённые файлы не считаются правкой

"""Этап 6в-3: нарезчик героя — фон, автонарезка, ИИ (Gemini подменён), сборка скелета и скина."""
import asyncio
import io
import json
import zipfile

import numpy as np
from PIL import Image, ImageDraw

from tests.test_admin import admin_headers, make_admin
from tests.test_progression import published  # noqa: F401

MAGENTA = (255, 0, 255)
# Части тестового героя (смотрит вправо): прямоугольники на холсте 400×600
SHAPES = {
    "head": (165, 40, 235, 120, (230, 190, 150)),
    "torso": (150, 120, 250, 330, (40, 120, 60)),
    "arm_back": (120, 140, 150, 330, (200, 160, 40)),
    "arm_front": (250, 140, 280, 330, (210, 170, 50)),
    "leg_back": (155, 330, 195, 560, (90, 60, 30)),
    "leg_front": (205, 330, 245, 560, (100, 70, 40)),
}


def textured(w, h, color, seed):
    rng = np.random.default_rng(seed)
    a = np.zeros((h, w, 3), np.int16) + np.array(color, np.int16)
    a += rng.integers(-40, 40, (h, w, 1)).astype(np.int16)
    for i in range(0, w, 7):  # узор, чтобы SIFT нашёл точки
        a[:, i:i + 2] -= 50
    for j in range(0, h, 11):
        a[j:j + 2, :] += 40
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def figure(bg=MAGENTA):
    im = Image.new("RGB", (400, 600), bg)
    for i, (n, (x0, y0, x1, y1, col)) in enumerate(SHAPES.items()):
        im.paste(textured(x1 - x0, y1 - y0, col, i), (x0, y0))
    buf = io.BytesIO()
    im.save(buf, "PNG")
    return buf.getvalue(), im


def fake_atlas():
    """«Лист частей» как от Gemini: те же части вразброс на белом фоне + подписи."""
    _, im = figure()
    sheet = Image.new("RGB", (900, 700), (255, 255, 255))
    boxes, x = [], 20
    for n, (x0, y0, x1, y1, _) in SHAPES.items():
        piece = im.crop((x0, y0, x1, y1))
        y = 30 if n in ("head", "torso") else 300
        sheet.paste(piece, (x, y))
        boxes.append({"label": n, "box": (x / 900, y / 700, (x + piece.width) / 900, (y + piece.height) / 700)})
        x += piece.width + 40
    buf = io.BytesIO()
    sheet.save(buf, "PNG")
    return buf.getvalue(), boxes


async def upload(c, hdr, data, name="hero.png"):
    r = await c.post("/api/v1/admin/cutter", headers={**hdr, "X-Filename": name}, content=data)
    assert r.status_code == 200, r.text
    return r.json()


async def test_background_and_auto_cut_build(published):
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    t = (await c.get("/api/v1/admin/cutter/templates", headers=hdr)).json()
    assert {x["id"] for x in t["templates"]} == {"humanoid", "winged", "beast"}
    png, _ = figure()
    meta = await upload(c, hdr, png)
    src = Image.open(io.BytesIO((await c.get(f"/api/v1/admin/cutter/{meta['id']}/image", headers=hdr)).content))
    a = np.array(src.convert("RGBA"))
    assert a[5, 5, 3] == 0 and a[300, 200, 3] == 255  # пурпурный фон убран, персонаж на месте
    auto = (await c.post(f"/api/v1/admin/cutter/{meta['id']}/auto", headers=hdr, json={"template": "humanoid"})).json()
    parts = {p["name"]: p for p in auto["parts"]}
    assert parts["head"]["polygons"] and parts["leg_front"]["polygons"] and not parts["weapon"]["polygons"]
    hx, hy = auto["joints"]["head"]
    assert 160 < hx < 240 and 80 < hy < 150  # шея — у низа головы
    pv = (await c.post(f"/api/v1/admin/cutter/{meta['id']}/preview", headers=hdr,
                       json={"part": parts["head"]})).json()
    assert not pv["empty"] and 60 <= pv["w"] <= 170
    # Мазок «стереть» по части
    head = dict(parts["head"], strokes=[{"mode": "erase", "r": 200, "pts": [[200, 80]]}])
    assert (await c.post(f"/api/v1/admin/cutter/{meta['id']}/preview", headers=hdr, json={"part": head})).json()["empty"]
    b = await c.post(f"/api/v1/admin/cutter/{meta['id']}/build", headers=hdr,
                     json={"hero": "shulgen", "template": "humanoid", "parts": auto["parts"],
                           "joints": auto["joints"], "art": True})
    assert b.status_code == 200, b.text
    rep = b.json()["report"]
    assert rep["animations"] == "прежние анимации героя" and "weapon" in rep["empty"] and rep["removed"] >= 5
    draft = (await c.get("/api/v1/admin/draft", headers=hdr)).json()
    ch = {x["path"]: x["change"] for x in draft["changes"]}
    assert ch["heroes/shulgen/rig/head.png"] == "add" and ch["heroes/shulgen/parts/arm.png"] == "delete"
    assert ch["heroes/shulgen/skeleton.json"] == "update" and "heroes/shulgen/portrait.png" in ch
    sk = json.loads((await c.get("/api/v1/admin/files?path=heroes/shulgen/skeleton.json", headers=hdr)).content)
    assert [s["name"] for s in sk["slots"]][:2] == ["arm_back", "leg_back"]
    assert sk["bones"][0] == {"name": "root", "scale_x": 0.5, "scale_y": 0.5}
    assert "attack" in sk["animations"] and sk["size"][1] == 130
    # Черновик публикуется (скелет проходит проверку схемы)
    assert (await c.post("/api/v1/admin/draft/publish", headers=hdr, json={"confirm": True})).status_code == 200

    # Скин из нового рисунка: свои картинки и точки крепления, скелет прежний
    await c.post("/api/v1/admin/heroes/shulgen/skins", headers=hdr, json={"skin": "dark", "name": "Тёмный"})
    meta2 = await upload(c, hdr, png)
    auto2 = (await c.post(f"/api/v1/admin/cutter/{meta2['id']}/auto", headers=hdr, json={"template": "humanoid"})).json()
    b2 = await c.post(f"/api/v1/admin/cutter/{meta2['id']}/build", headers=hdr,
                      json={"hero": "shulgen", "skin": "dark", "template": "humanoid", "parts": auto2["parts"],
                            "joints": auto2["joints"]})
    assert b2.status_code == 200, b2.text
    sk2 = json.loads((await c.get("/api/v1/admin/files?path=heroes/shulgen/skeleton.json", headers=hdr)).content)
    head_slot = next(s for s in sk2["slots"] if s["name"] == "head")
    assert head_slot["skins"]["dark"]["image"] == "rig/head.png" and sk2["bones"] == sk["bones"]
    draft = (await c.get("/api/v1/admin/draft", headers=hdr)).json()
    assert "heroes/shulgen/skins/dark/rig/head.png" in {x["path"] for x in draft["changes"]}


async def test_sheet_crop_and_layers_zip(published):
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    png, im = figure(bg=(255, 255, 255))
    sheet = Image.new("RGB", (900, 600), (255, 255, 255))
    sheet.paste(im, (0, 0))
    sheet.paste(im, (450, 0))
    buf = io.BytesIO()
    sheet.save(buf, "PNG")
    meta = await upload(c, hdr, buf.getvalue())
    cr = (await c.post(f"/api/v1/admin/cutter/{meta['id']}/crop", headers=hdr,
                       json={"x": 450, "y": 0, "w": 450, "h": 600})).json()
    assert cr["w"] == 450 and cr["h"] == 600
    # ZIP слоёв: имена слоёв = части шаблона
    zbuf = io.BytesIO()
    with zipfile.ZipFile(zbuf, "w") as zf:
        for n, (x0, y0, x1, y1, col) in SHAPES.items():
            layer = Image.new("RGBA", (400, 600))
            layer.paste(textured(x1 - x0, y1 - y0, col, 1), (x0, y0))
            b = io.BytesIO()
            layer.save(b, "PNG")
            zf.writestr(f"layers/{n}.png", b.getvalue())
    meta = await upload(c, hdr, zbuf.getvalue(), "layers.zip")
    assert meta["mode"] == "layers" and len(meta["layers"]) == 6
    auto = (await c.post(f"/api/v1/admin/cutter/{meta['id']}/auto", headers=hdr, json={"template": "humanoid"})).json()
    assert {p["name"]: p["layer"] for p in auto["parts"]}["torso"] == "torso"
    assert set(auto["layers_matched"]) == set(SHAPES)


async def test_ai_cut_with_fake_gemini(published, monkeypatch):
    from app.ai import gemini
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    atlas, boxes = fake_atlas()
    calls = []
    monkeypatch.setenv("GEMINI_API_KEY", "test")
    monkeypatch.setattr(gemini, "generate_image", lambda prompt, png: calls.append(prompt) or atlas)
    monkeypatch.setattr(gemini, "detect_boxes", lambda png, labels: boxes)
    png, _ = figure()
    meta = await upload(c, hdr, png)
    r = await c.post(f"/api/v1/admin/cutter/{meta['id']}/ai", headers=hdr, json={"template": "humanoid"})
    assert r.json()["status"] == "running"
    for _ in range(100):
        st = (await c.get(f"/api/v1/admin/cutter/{meta['id']}/ai", headers=hdr)).json()
        if st["status"] != "running":
            break
        await asyncio.sleep(0.1)
    assert st["status"] == "done", st
    res = st["result"]
    assert set(res["ai"]["parts"]) == set(SHAPES) and res["ai"]["unplaced"] == 0
    assert "the far (back) arm" in calls[0] and "faces right" in calls[0]
    head = next(p for p in res["parts"] if p["name"] == "head")
    assert head["layer"] == "ai_head"
    pv = (await c.post(f"/api/v1/admin/cutter/{meta['id']}/preview", headers=hdr, json={"part": head})).json()
    assert abs(pv["x"] - 165) <= 3 and abs(pv["y"] - 40) <= 3  # часть легла на своё место рисунка


async def test_ai_without_key(published, monkeypatch):
    c = published
    await make_admin()
    hdr = await admin_headers(c)
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    png, _ = figure()
    meta = await upload(c, hdr, png)
    r = await c.post(f"/api/v1/admin/cutter/{meta['id']}/ai", headers=hdr, json={"template": "humanoid"})
    assert r.status_code == 422 and "ключа Gemini" in r.text

#!/usr/bin/env python3
"""Нарезка цельного рисунка героя (вид сбоку, смотрит вправо, фон уже убран) на части для скелетной анимации.

Запуск из корня репозитория:
    python3 scripts/import_flat_hero.py рисунок_без_фона.png ural_batyr

Фон убирается заранее (например, rembg с моделью isnet-anime). Области частей заданы многоугольниками
в координатах исходного рисунка (PARTS) — под другой рисунок их нужно разметить заново.
Части рисуются в порядке ORDER; кость каждой части — в её точке вращения (PIVOT).
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1] / "content"
K = 0.3        # уменьшение слоёв
HEIGHT = 150   # рост героя в бою, пиксели
FEET_X = 640   # центр между ступнями (исходные координаты)

# Многоугольники частей (исходный рисунок 1536×1024). Корпус = всё, что не попало в другие части.
PARTS = {
    "head": [(522, 0), (745, 0), (745, 182), (700, 196), (612, 200), (566, 176), (522, 150)],
    "cape": [(0, 290), (330, 175), (440, 165), (452, 380), (444, 600), (380, 700), (300, 840), (0, 840)],
    "arm_front": [(714, 150), (760, 90), (1536, 90), (1536, 345), (714, 330)],
    "leg_back": [(380, 652), (642, 652), (642, 1024), (380, 1024)],
    "leg_front": [(642, 652), (960, 652), (960, 1024), (642, 1024)],
}
PIVOT = {
    "torso": (620, 640), "head": (650, 192), "cape": (450, 240),
    "arm_front": (712, 232), "leg_back": (565, 660), "leg_front": (700, 660),
}
PARENT = {"torso": "hips", "head": "torso", "cape": "torso", "arm_front": "torso",
          "leg_back": "hips", "leg_front": "hips"}
ORDER = ["cape", "leg_back", "leg_front", "torso", "head", "arm_front"]
ARM_REST = 28  # в покое меч опущен вперёд-вниз (градусы по часовой)


def mask_of(size, poly):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    return m


def main(src_png: Path, hero_id: str) -> None:
    src = Image.open(src_png).convert("RGBA")
    a = src.split()[3].point(lambda v: 0 if v < 60 else v)  # убираем остатки свечения
    keep = a.point(lambda v: 255 if v else 0).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(7))
    src.putalpha(ImageChops.multiply(a, keep))  # и одиночные точки вокруг героя
    hero_dir = ROOT / "heroes" / hero_id
    out = hero_dir / "rig"
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()
    for old in (hero_dir / "parts").glob("*.png") if (hero_dir / "parts").is_dir() else []:
        old.unlink()
    if (hero_dir / "parts").is_dir():
        (hero_dir / "parts").rmdir()

    feet_y = src.getbbox()[3]
    taken = Image.new("L", src.size, 0)
    layers = {}
    for name, poly in PARTS.items():
        m = ImageChops.subtract(mask_of(src.size, poly), taken)
        taken = ImageChops.lighter(taken, m)
        layers[name] = m
    layers["torso"] = ImageChops.invert(taken)

    boxes = {}
    for name, m in layers.items():
        part = src.copy()
        # чуть размытая граница разреза, чтобы при поворотах не было «ступенек»
        part.putalpha(ImageChops.multiply(src.split()[3], m.filter(ImageFilter.GaussianBlur(1.2))))
        core = part.split()[3].point(lambda v: 255 if v > 100 else 0).filter(ImageFilter.MinFilter(9))
        cb = core.getbbox()  # рамка без одиночных точек
        bbox = (max(0, cb[0] - 6), max(0, cb[1] - 6), min(src.width, cb[2] + 6), min(src.height, cb[3] + 6))
        boxes[name] = bbox
        part = part.crop(bbox)
        part = part.resize((max(1, round(part.width * K)), max(1, round(part.height * K))), Image.LANCZOS)
        part.save(out / f"{name}.png", optimize=True)

    root_scale = round(HEIGHT / (feet_y * K), 4)
    hips = PIVOT["torso"]
    bones = [{"name": "root", "scale_x": root_scale, "scale_y": root_scale},
             {"name": "hips", "parent": "root", "x": round((hips[0] - FEET_X) * K, 2),
              "y": round((hips[1] - feet_y) * K, 2)}]
    for name in ["torso", "head", "cape", "arm_front", "leg_back", "leg_front"]:
        p = PIVOT[name]
        pp = hips if PARENT[name] == "hips" else PIVOT[PARENT[name]]
        bone = {"name": name, "parent": PARENT[name], "x": round((p[0] - pp[0]) * K, 2),
                "y": round((p[1] - pp[1]) * K, 2)}
        if name == "arm_front":
            bone["rotation"] = ARM_REST
        bones.append(bone)
    bones.append({"name": "weapon", "parent": "arm_front", "x": round((1300 - PIVOT["arm_front"][0]) * K, 2), "y": 0})
    slots = []
    for name in ORDER:
        bx, by = boxes[name][:2]
        px, py = PIVOT[name]
        slots.append({"name": name, "bone": name, "image": f"rig/{name}.png",
                      "pivot": [round((px - bx) * K, 2), round((py - by) * K, 2)]})

    anims = {
        "idle": {"duration": 1.4, "loop": True, "bones": {
            "torso": {"scale": [[0, 1, 1], [0.7, 1.0, 1.015], [1.4, 1, 1]]},
            "head": {"rotate": [[0, 0], [0.7, -2], [1.4, 0]]},
            "cape": {"rotate": [[0, 0], [0.7, 3], [1.4, 0]]},
            "arm_front": {"rotate": [[0, 0], [0.7, -4], [1.4, 0]]}}},
        "walk": {"duration": 0.6, "loop": True, "bones": {
            "leg_front": {"rotate": [[0, -14], [0.3, 12], [0.6, -14]]},
            "leg_back": {"rotate": [[0, 12], [0.3, -14], [0.6, 12]]},
            "hips": {"translate": [[0, 0, 0], [0.15, 0, -7], [0.3, 0, 0], [0.45, 0, -7], [0.6, 0, 0]]},
            "cape": {"rotate": [[0, 4], [0.3, 8], [0.6, 4]]},
            "arm_front": {"rotate": [[0, -6], [0.3, 4], [0.6, -6]]}}},
        "attack": {"duration": 0.6, "bones": {
            "arm_front": {"rotate": [[0, 0], [0.2, -75], [0.35, 18], [0.6, 0]]},
            "torso": {"rotate": [[0, 0], [0.2, -4], [0.35, 5], [0.6, 0]]},
            "hips": {"translate": [[0, 0, 0], [0.35, 30, 0], [0.6, 0, 0]]},
            "cape": {"rotate": [[0, 0], [0.35, 10], [0.6, 0]]}},
            "events": [{"t": 0.35, "name": "hit"}]},
        "skill": {"duration": 0.8, "bones": {
            "arm_front": {"rotate": [[0, 0], [0.3, -120], [0.5, 25], [0.8, 0]]},
            "torso": {"rotate": [[0, 0], [0.3, -8], [0.5, 8], [0.8, 0]]},
            "hips": {"translate": [[0, 0, 0], [0.3, -10, -10], [0.5, 40, 0], [0.8, 0, 0]]},
            "cape": {"rotate": [[0, 0], [0.5, 14], [0.8, 0]]}},
            "events": [{"t": 0.5, "name": "hit"}]},
        "ultimate": {"duration": 1.2, "bones": {
            "hips": {"translate": [[0, 0, 0], [0.3, 0, 12], [0.6, 20, -90], [0.9, 50, 0], [1.2, 0, 0]]},
            "arm_front": {"rotate": [[0, 0], [0.6, -150], [0.9, 30], [1.2, 0]]},
            "cape": {"rotate": [[0, 0], [0.6, 18], [0.9, 6], [1.2, 0]]},
            "leg_front": {"rotate": [[0, 0], [0.6, -20], [0.9, 0]]},
            "leg_back": {"rotate": [[0, 0], [0.6, 20], [0.9, 0]]},
            "root": {"scale": [[0, 1, 1], [0.6, 1.12, 1.12], [1.0, 1.04, 1.04], [1.2, 1, 1]]}},
            "events": [{"t": 0.9, "name": "hit"}]},
        "hit": {"duration": 0.3, "bones": {
            "torso": {"rotate": [[0, 0], [0.1, -7], [0.3, 0]]},
            "head": {"rotate": [[0, 0], [0.1, -8], [0.3, 0]]},
            "root": {"translate": [[0, 0, 0], [0.1, -6, 0], [0.3, 0, 0]]}}},
        "death": {"duration": 0.9, "bones": {
            "root": {"rotate": [[0, 0], [0.5, -85], [0.9, -90]], "translate": [[0, 0, 0], [0.5, -14, -6], [0.9, -16, 0]]}},
            "alpha": [[0, 1], [0.6, 1], [0.9, 0.35]]},
        "victory": {"duration": 1.0, "loop": True, "bones": {
            "root": {"translate": [[0, 0, 0], [0.3, 0, -14], [0.6, 0, 0], [1.0, 0, 0]]},
            "arm_front": {"rotate": [[0, -95], [0.5, -85], [1.0, -95]]},
            "cape": {"rotate": [[0, 6], [0.5, 12], [1.0, 6]]}}},
    }
    skel = {
        "format": "ufa-skeleton", "version": 1, "size": [90, HEIGHT],
        "bones": bones, "slots": slots,
        "anchors": {"projectile": {"bone": "weapon", "x": 0, "y": 0},
                    "hit": {"bone": "torso", "x": 0, "y": round(-260 * K, 2)},
                    "overhead": {"bone": "head", "x": 0, "y": round(-210 * K, 2)}},
        "animations": anims,
    }
    (hero_dir / "skeleton.json").write_text(json.dumps(skel, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    hb = boxes["head"]
    side = max(hb[2] - hb[0], hb[3] - hb[1]) + 40
    cx, cy = (hb[0] + hb[2]) // 2, (hb[1] + hb[3]) // 2 + 30
    src.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2)).resize((128, 128), Image.LANCZOS) \
        .save(hero_dir / "portrait.png", optimize=True)
    full = src.crop(src.getbbox())
    k = min(160 / full.width, 200 / full.height)
    full = full.resize((round(full.width * k), round(full.height * k)), Image.LANCZOS)
    canvas = Image.new("RGBA", (160, 200), (0, 0, 0, 0))
    canvas.alpha_composite(full, ((160 - full.width) // 2, 200 - full.height))
    canvas.save(hero_dir / "full.png", optimize=True)
    print(f"{hero_id}: {len(slots)} частей, масштаб {root_scale} -> {hero_dir}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), sys.argv[2])

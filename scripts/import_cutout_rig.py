#!/usr/bin/env python3
"""Импорт вырезанного 2D-рига (папка assets/parts/*.png + assets/bones.json, все слои на общем холсте)
в формат игры ufa-skeleton для героя.

Запуск из корня репозитория:
    python3 scripts/import_cutout_rig.py путь/к/Samraya_Hero_Godot_Rig_V2 humai

Слои обрезаются по видимой части и уменьшаются (K), рост героя на экране — около HEIGHT пикселей.
Руки в исходнике разведены (T-поза) — в покое опускаем их костями (ARM_REST).
Анимации в формате игры: idle, walk, attack, skill, ultimate, hit, death, victory.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "content"
K = 0.25           # уменьшение слоёв (запас резкости для экранов высокой плотности)
HEIGHT = 150       # рост героя на экране боя, пиксели
ARM_REST = 68      # на сколько градусов опустить руки из T-позы
DRAW_ORDER = ["back_hair", "left_leg", "right_leg", "left_upper_arm", "left_forearm", "left_hand",
              "left_skirt", "right_skirt", "center_skirt", "torso", "head", "left_braid", "right_braid",
              "right_upper_arm", "right_forearm", "right_hand"]


def main(src: Path, hero_id: str) -> None:
    bones_src = json.loads((src / "assets/bones.json").read_text(encoding="utf-8"))
    hero_dir = ROOT / "heroes" / hero_id
    out = hero_dir / "rig"
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.png"):
        old.unlink()

    feet_y = 0
    boxes = {}
    for name in bones_src:
        im = Image.open(src / f"assets/parts/{name}.png").convert("RGBA")
        bbox = im.split()[3].point(lambda v: 255 if v > 8 else 0).getbbox()
        boxes[name] = bbox
        feet_y = max(feet_y, bbox[3])
        part = im.crop(bbox)
        part = part.resize((max(1, round(part.width * K)), max(1, round(part.height * K))), Image.LANCZOS)
        part.save(out / f"{name}.png", optimize=True)
    center_x = bones_src["torso"]["pivot"][0]
    root_scale = round(HEIGHT / (feet_y * K), 4)

    bones = [{"name": "root", "scale_x": root_scale, "scale_y": root_scale},
             {"name": "hips", "parent": "root", "x": 0, "y": round((bones_src["torso"]["pivot"][1] - feet_y) * K, 2)}]
    hips_pivot = bones_src["torso"]["pivot"]
    for name, b in bones_src.items():
        parent = b["parent"] or "hips"
        ppivot = hips_pivot if parent == "hips" else bones_src[parent]["pivot"]
        bone = {"name": name, "parent": parent,
                "x": round((b["pivot"][0] - ppivot[0]) * K, 2), "y": round((b["pivot"][1] - ppivot[1]) * K, 2)}
        if name == "left_upper_arm":
            bone["rotation"] = -ARM_REST
        if name == "right_upper_arm":
            bone["rotation"] = ARM_REST
        bones.append(bone)
    slots = []
    for name in DRAW_ORDER:
        bx, by = boxes[name][:2]
        px, py = bones_src[name]["pivot"]
        slots.append({"name": name, "bone": name, "image": f"rig/{name}.png",
                      "pivot": [round((px - bx) * K, 2), round((py - by) * K, 2)]})

    fa, ba = "right_upper_arm", "left_upper_arm"   # рука «вперёд» (к врагу) и «назад»
    anims = {
        "idle": {"duration": 1.6, "loop": True, "bones": {
            "torso": {"scale": [[0, 1, 1], [0.8, 1.0, 1.015], [1.6, 1, 1]]},
            "head": {"rotate": [[0, 0], [0.8, 2], [1.6, 0]]},
            "left_braid": {"rotate": [[0, 0], [0.8, 3], [1.6, 0]]},
            "right_braid": {"rotate": [[0, 0], [0.8, -3], [1.6, 0]]},
            "left_skirt": {"rotate": [[0, 0], [0.8, 1.5], [1.6, 0]]},
            "right_skirt": {"rotate": [[0, 0], [0.8, -1.5], [1.6, 0]]},
            fa: {"rotate": [[0, 0], [0.8, -4], [1.6, 0]]},
            ba: {"rotate": [[0, 0], [0.8, 4], [1.6, 0]]}}},
        "walk": {"duration": 0.6, "loop": True, "bones": {
            "left_leg": {"rotate": [[0, -10], [0.3, 10], [0.6, -10]]},
            "right_leg": {"rotate": [[0, 10], [0.3, -10], [0.6, 10]]},
            "hips": {"translate": [[0, 0, 0], [0.15, 0, -8], [0.3, 0, 0], [0.45, 0, -8], [0.6, 0, 0]]},
            "left_skirt": {"rotate": [[0, -4], [0.3, 4], [0.6, -4]]},
            "right_skirt": {"rotate": [[0, 4], [0.3, -4], [0.6, 4]]},
            "left_braid": {"rotate": [[0, 4], [0.3, -4], [0.6, 4]]},
            "right_braid": {"rotate": [[0, -4], [0.3, 4], [0.6, -4]]},
            fa: {"rotate": [[0, 10], [0.3, -10], [0.6, 10]]},
            ba: {"rotate": [[0, -10], [0.3, 10], [0.6, -10]]}}},
        "attack": {"duration": 0.6, "bones": {
            fa: {"rotate": [[0, 0], [0.25, -75], [0.45, -65], [0.6, 0]]},
            "right_forearm": {"rotate": [[0, 0], [0.25, -10], [0.6, 0]]},
            "torso": {"rotate": [[0, 0], [0.3, 3], [0.6, 0]]}},
            "events": [{"t": 0.35, "name": "projectile"}]},
        "skill": {"duration": 0.8, "bones": {
            fa: {"rotate": [[0, 0], [0.35, -110], [0.6, -100], [0.8, 0]]},
            ba: {"rotate": [[0, 0], [0.35, 110], [0.6, 100], [0.8, 0]]},
            "root": {"scale": [[0, 1, 1], [0.5, 1.06, 1.06], [0.8, 1, 1]]}},
            "events": [{"t": 0.5, "name": "hit"}]},
        "ultimate": {"duration": 1.2, "bones": {
            "hips": {"translate": [[0, 0, 0], [0.3, 0, 10], [0.6, 0, -60], [0.9, 0, 0], [1.2, 0, 0]]},
            fa: {"rotate": [[0, 0], [0.6, -150], [0.9, -40], [1.2, 0]]},
            ba: {"rotate": [[0, 0], [0.6, 150], [0.9, 40], [1.2, 0]]},
            "left_braid": {"rotate": [[0, 0], [0.6, 12], [1.2, 0]]},
            "right_braid": {"rotate": [[0, 0], [0.6, -12], [1.2, 0]]},
            "root": {"scale": [[0, 1, 1], [0.6, 1.15, 1.15], [1.0, 1.05, 1.05], [1.2, 1, 1]]}},
            "events": [{"t": 0.9, "name": "hit"}]},
        "hit": {"duration": 0.3, "bones": {
            "torso": {"rotate": [[0, 0], [0.1, -6], [0.3, 0]]},
            "head": {"rotate": [[0, 0], [0.1, -8], [0.3, 0]]},
            "root": {"translate": [[0, 0, 0], [0.1, -6, 0], [0.3, 0, 0]]}}},
        "death": {"duration": 0.9, "bones": {
            "root": {"rotate": [[0, 0], [0.5, -85], [0.9, -90]], "translate": [[0, 0, 0], [0.5, -14, -6], [0.9, -16, 0]]}},
            "alpha": [[0, 1], [0.6, 1], [0.9, 0.35]]},
        "victory": {"duration": 1.0, "loop": True, "bones": {
            "root": {"translate": [[0, 0, 0], [0.3, 0, -14], [0.6, 0, 0], [1.0, 0, 0]]},
            fa: {"rotate": [[0, -120], [0.5, -105], [1.0, -120]]},
            ba: {"rotate": [[0, 120], [0.5, 105], [1.0, 120]]}}},
    }
    head_top = (bones_src["head"]["pivot"][1] - boxes["head"][1]) * K
    skel = {
        "format": "ufa-skeleton", "version": 1, "size": [70, HEIGHT],
        "bones": bones, "slots": slots,
        "anchors": {"projectile": {"bone": "right_hand", "x": 0, "y": 0},
                    "hit": {"bone": "torso", "x": 0, "y": -40},
                    "overhead": {"bone": "head", "x": 0, "y": round(-head_top - 20, 2)}},
        "animations": anims,
    }
    (hero_dir / "skeleton.json").write_text(json.dumps(skel, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    orig = Image.open(src / "assets/original.png").convert("RGBA")
    hb = boxes["head"]
    side = max(hb[2] - hb[0], hb[3] - hb[1]) + 120
    cx, top = (hb[0] + hb[2]) // 2, max(0, hb[1] - 10)
    orig.crop((cx - side // 2, top, cx + side // 2, top + side)).resize((128, 128), Image.LANCZOS) \
        .save(hero_dir / "portrait.png", optimize=True)
    full = orig.crop(orig.getbbox())
    k = min(160 / full.width, 200 / full.height)
    full = full.resize((round(full.width * k), round(full.height * k)), Image.LANCZOS)
    canvas = Image.new("RGBA", (160, 200), (0, 0, 0, 0))
    canvas.alpha_composite(full, ((160 - full.width) // 2, 200 - full.height))
    canvas.save(hero_dir / "full.png", optimize=True)
    print(f"{hero_id}: {len(slots)} слоёв, масштаб {root_scale}, -> {hero_dir}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), sys.argv[2])

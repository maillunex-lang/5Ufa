#!/usr/bin/env python3
"""Вырезает иконки и здания из листа-макета (тёмно-синий фон → прозрачность).

Запуск из корня репозитория:  python3 scripts/cut_icons.py путь/к/листу.png
Координаты областей — для листа 1536×1024 «Меню и навигация / Здания и локации / ...».
"""
from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "content" / "ui" / "hub"

# имя: (x0, y0, x1, y1, размер на выходе; для зданий — ширина)
ICONS = {
    "icon_heroes": (30, 45, 134, 128, 128), "icon_inventory": (146, 45, 250, 128, 128),
    "icon_city": (258, 42, 376, 130, 160), "icon_quests": (384, 40, 486, 128, 128),
    "icon_world": (492, 40, 598, 128, 128), "icon_mail": (728, 40, 832, 128, 128),
    "icon_settings": (840, 40, 944, 128, 128),
    "icon_tasks": (114, 730, 202, 800, 128), "icon_power": (294, 730, 378, 800, 96),
    "icon_daily": (378, 730, 466, 800, 128), "icon_events": (722, 728, 806, 800, 128),
    "icon_rewards": (548, 730, 634, 800, 128), "icon_battle_pass": (634, 726, 720, 790, 128),
    "icon_coin": (786, 388, 876, 472, 96), "icon_crystal": (882, 388, 980, 472, 96),
}
BUILDINGS = {
    "building_fortress": (34, 217, 178, 306, 300), "building_summon": (186, 217, 296, 306, 230),
    "building_tavern": (302, 217, 444, 306, 290), "building_arena": (444, 217, 556, 306, 260),
    "building_guild": (560, 217, 686, 306, 270), "building_campaign": (690, 217, 806, 306, 230),
    "building_dungeon": (810, 217, 950, 306, 280),
}


def is_bg(p, limit=72):
    r, g, b = p[:3]
    return (r + g + b) / 3 < limit and b - r >= 10


# центр и радиус нарисованного «!» (координаты листа)
BADGES = {"icon_quests": (466, 59, 21), "icon_mail": (811, 61, 21)}
DARK_ONLY = {"building_dungeon": 40}  # серые камни похожи на фон — снимаем только совсем тёмное


def cut(sheet, box, name=""):
    img = sheet.crop(box[:4]).convert("RGBA")
    w, h = img.size
    px = img.load()
    seen = [[False] * w for _ in range(h)]
    q = deque((x, y) for x in range(w) for y in (0, h - 1))
    q.extend((x, y) for y in range(h) for x in (0, w - 1))
    mask = Image.new("L", (w, h), 255)
    mp = mask.load()
    while q:
        x, y = q.popleft()
        if not (0 <= x < w and 0 <= y < h) or seen[y][x]:
            continue
        seen[y][x] = True
        if not is_bg(px[x, y], DARK_ONLY.get(name, 72)):
            continue
        mp[x, y] = 0
        q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    if name in BADGES:  # «!» на листе убираем — красную точку рисует сама игра
        cx, cy, r = BADGES[name]
        cx, cy = cx - box[0], cy - box[1]
        mp = mask.load()
        for y in range(h):
            for x in range(w):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    mp[x, y] = 0
    img.putalpha(mask)
    return img.crop(img.getbbox())


def fit(img, size, square=True):
    if not square:
        k = size / img.width
        return img.resize((size, round(img.height * k)), Image.LANCZOS)
    k = size / max(img.size)
    small = img.resize((round(img.width * k), round(img.height * k)), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(small, ((size - small.width) // 2, (size - small.height) // 2))
    return out


def main(sheet_path):
    sheet = Image.open(sheet_path).convert("RGB")
    OUT.mkdir(parents=True, exist_ok=True)
    for name, box in ICONS.items():
        fit(cut(sheet, box, name), box[4]).save(OUT / f"{name}.png", optimize=True)
    for name, box in BUILDINGS.items():
        fit(cut(sheet, box, name), box[4], square=False).save(OUT / f"{name}.png", optimize=True)
    print("готово:", len(ICONS) + len(BUILDINGS), "картинок в", OUT)


if __name__ == "__main__":
    main(sys.argv[1])

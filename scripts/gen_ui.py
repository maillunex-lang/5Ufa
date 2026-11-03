#!/usr/bin/env python3
"""Генератор заглушек главного экрана «Город»: эмблема под названием и кнопка «+».

Фон города (background.webp, 720×1400) — готовый арт; здания и иконки вырезаются из листа
скриптом scripts/cut_icons.py.

Стиль: светлое фэнтези Урала — снежные вершины, водопады, зелень, белый камень, золото.
Позже всё заменяется артом через админку (те же имена файлов, см. content/ui/hub.json).
Запуск из корня репозитория:  python3 scripts/gen_ui.py   (нужен Pillow)
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "content" / "ui" / "hub"
S = 2  # рисуем в 2x, потом уменьшаем — сглаженные края
INK = (34, 24, 40, 255)


def c(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


GOLD, GOLD_L, GOLD_D = c("#F2B544"), c("#FFE29A"), c("#9A6A1A")


def new(w, h):
    img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def P(pts):
    return [(x * S, y * S) for x, y in pts]


def B(box):
    return [v * S for v in box]


def glow(img, color, radius=10):
    alpha = img.split()[3].filter(ImageFilter.GaussianBlur(radius * S))
    halo = Image.new("RGBA", img.size, color[:3] + (0,))
    halo.putalpha(alpha.point(lambda v: int(v * color[3] / 255)))
    halo.alpha_composite(img)
    return halo


def save(img, name, w=None, h=None, webp=False):
    OUT.mkdir(parents=True, exist_ok=True)
    small = img.resize((w or img.width // S, h or img.height // S), Image.LANCZOS)
    path = OUT / name
    if webp:
        small.convert("RGB").save(path, "WEBP", quality=84, method=6)
    else:
        small.save(path, optimize=True)
    print(f"{path.relative_to(OUT.parents[2])}  {path.stat().st_size // 1024} КБ")


# --------------------------------------------------------------------------- иконки

def icon_plus(size=96):
    img, d = new(96, 96)
    d.ellipse(B([6, 6, 90, 90]), fill=GOLD, outline=GOLD_D, width=4 * S)
    d.rectangle(B([42, 22, 54, 74]), fill=c("#3A2A10"))
    d.rectangle(B([22, 42, 74, 54]), fill=c("#3A2A10"))
    save(img, "icon_plus.png", size, size)


def emblem():
    """Подложка под название: золотая рамка и синяя вершина."""
    img, d = new(520, 200)
    d.polygon(P([(140, 150), (230, 30), (260, 10), (290, 30), (380, 150)]), fill=c("#3E6FD0"), outline=INK)
    d.polygon(P([(230, 30), (260, 10), (290, 30), (276, 60), (260, 44), (244, 62)]), fill=c("#F0F6FF"))
    d.polygon(P([(30, 150), (90, 120), (430, 120), (490, 150), (430, 180), (90, 180)]), fill=c("#2A1E48", 230),
              outline=GOLD, width=4 * S)
    d.polygon(P([(250, 182), (260, 196), (270, 182)]), fill=GOLD)
    save(glow(img, (255, 220, 140, 160), 10), "emblem.png")


if __name__ == "__main__":
    icon_plus()
    emblem()

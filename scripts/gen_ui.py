#!/usr/bin/env python3
"""Генератор заглушек главного экрана «Город»: здания, иконки меню, эмблема.

Фон города (content/ui/hub/background.webp, 720×1400) — готовый арт, этим скриптом не создаётся.

Стиль: светлое фэнтези Урала — снежные вершины, водопады, зелень, белый камень, золото.
Позже всё заменяется артом через админку (те же имена файлов, см. content/ui/hub.json).
Запуск из корня репозитория:  python3 scripts/gen_ui.py   (нужен Pillow)
"""
from __future__ import annotations

import math
import random
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


# --------------------------------------------------------------------------- здания

def tower(d, x, base, w, hgt, roof="#3E6FD0", wall="#F1ECE2"):
    d.rectangle(B([x, base - hgt, x + w, base]), fill=c(wall), outline=INK, width=2 * S)
    d.polygon(P([(x - 6, base - hgt), (x + w / 2, base - hgt - w * 1.5), (x + w + 6, base - hgt)]), fill=c(roof), outline=INK)
    d.line(P([(x + w / 2, base - hgt - w * 1.5), (x + w / 2, base - hgt - w * 1.5 - 14)]), fill=GOLD, width=2 * S)
    d.rounded_rectangle(B([x + w / 2 - 4, base - hgt + 14, x + w / 2 + 4, base - hgt + 30]), 4 * S, fill=c("#FFD27A"))


def banner(d, x, y, col="#C0392B", h=40):
    d.line(P([(x, y - 8), (x, y + h + 10)]), fill=INK, width=2 * S)
    d.polygon(P([(x + 1, y), (x + 18, y), (x + 18, y + h), (x + 9, y + h - 8), (x + 1, y + h)]), fill=c(col), outline=INK)
    d.ellipse(B([x + 5, y + 10, x + 14, y + 19]), fill=GOLD)


def fortress():
    img, d = new(320, 300)
    base = 270
    d.rectangle(B([50, base - 90, 270, base]), fill=c("#ECE6DA"), outline=INK, width=3 * S)
    for i in range(12):
        x = 50 + i * 18.5
        d.rectangle(B([x, base - 102, x + 10, base - 90]), fill=c("#ECE6DA"), outline=INK, width=2 * S)
    tower(d, 30, base, 40, 130)
    tower(d, 250, base, 40, 130)
    tower(d, 95, base - 60, 34, 90)
    tower(d, 190, base - 60, 34, 90)
    tower(d, 136, base - 70, 48, 140)
    d.rounded_rectangle(B([140, base - 60, 180, base]), 18 * S, fill=c("#5A3A22"), outline=INK, width=3 * S)
    for x in (70, 230):
        banner(d, x, base - 80)
    d.ellipse(B([10, base - 8, 310, base + 26]), fill=c("#7A7480", 200))
    return glow(img, (255, 236, 180, 150), 10)


def summon():
    img, d = new(220, 250)
    d.ellipse(B([20, 214, 200, 246]), fill=c("#6A6C80"), outline=INK, width=2 * S)
    d.rounded_rectangle(B([40, 40, 180, 228]), 70 * S, fill=c("#8E7BB8"), outline=INK, width=3 * S)
    d.rounded_rectangle(B([58, 60, 162, 226]), 52 * S, fill=c("#2A1A5E"))
    d.polygon(P([(110, 78), (140, 140), (110, 206), (80, 140)]), fill=c("#7FD6FF"), outline=c("#FFFFFF"))
    d.polygon(P([(110, 78), (120, 140), (110, 206), (100, 140)]), fill=c("#D4F2FF"))
    for x in (40, 180):
        tower(d, x - 14, 228, 28, 120, roof="#6A4FC0")
    img = glow(img, (150, 120, 255, 220), 16)
    return img


def guild():
    img, d = new(260, 230)
    base = 210
    d.rectangle(B([40, base - 90, 220, base]), fill=c("#E7D2A8"), outline=INK, width=3 * S)
    for x in (70, 120, 170):
        d.rounded_rectangle(B([x, base - 70, x + 20, base - 40]), 6 * S, fill=c("#FFD27A"), outline=INK, width=2 * S)
    d.rectangle(B([118, base - 34, 142, base]), fill=c("#5A3A22"))
    # изогнутая крыша в два яруса
    for y0, w0 in ((base - 90, 120), (base - 150, 80)):
        d.polygon(P([(130 - w0 - 10, y0 + 6), (130 - w0 + 20, y0 - 34), (130 + w0 - 20, y0 - 34),
                     (130 + w0 + 10, y0 + 6)]), fill=c("#23407A"), outline=INK)
        d.line(P([(130 - w0 - 10, y0 + 6), (130 + w0 + 10, y0 + 6)]), fill=GOLD, width=3 * S)
    d.rectangle(B([80, base - 150, 180, base - 124]), fill=c("#E7D2A8"), outline=INK, width=2 * S)
    banner(d, 20, base - 120, "#2E5BC0", 60)
    banner(d, 225, base - 120, "#C0392B", 60)
    d.ellipse(B([20, base - 6, 240, base + 18]), fill=c("#6A7050", 170))
    return glow(img, (255, 220, 150, 110), 8)


def tavern():
    img, d = new(250, 210)
    base = 190
    d.rectangle(B([30, base - 80, 220, base]), fill=c("#B47A44"), outline=INK, width=3 * S)
    for x in range(36, 220, 16):
        d.line(P([(x, base - 80), (x, base)]), fill=c("#9A6436"), width=1 * S)
    for x in (50, 160):
        d.rectangle(B([x, base - 60, x + 36, base - 30]), fill=c("#FFC35A"), outline=INK, width=2 * S)
    d.rectangle(B([108, base - 50, 142, base]), fill=c("#5A3A22"), outline=INK, width=2 * S)
    d.polygon(P([(14, base - 76), (60, base - 150), (190, base - 150), (236, base - 76)]), fill=c("#C8662A"), outline=INK)
    d.polygon(P([(90, base - 150), (125, base - 190), (160, base - 150)]), fill=c("#C8662A"), outline=INK)
    d.rectangle(B([168, base - 186, 186, base - 140]), fill=c("#8A8290"), outline=INK, width=2 * S)
    for x in (40, 75, 110, 145, 180, 210):  # фонарики
        d.ellipse(B([x, base - 84, x + 10, base - 72]), fill=c("#FFDD70"))
    d.ellipse(B([10, base - 6, 240, base + 18]), fill=c("#6A7050", 170))
    return glow(img, (255, 200, 110, 170), 10)


def arena():
    img, d = new(270, 200)
    d.ellipse(B([10, 60, 260, 190]), fill=c("#E6DFD2"), outline=INK, width=3 * S)
    d.rectangle(B([10, 100, 260, 125]), fill=c("#E6DFD2"))
    d.ellipse(B([10, 30, 260, 150]), fill=c("#F2ECE0"), outline=INK, width=3 * S)
    d.ellipse(B([10, 30, 260, 150]), outline=c("#C0392B"), width=10 * S)
    d.ellipse(B([45, 50, 225, 130]), fill=c("#C9A877"), outline=INK, width=2 * S)
    for i in range(14):  # арки
        a = math.pi * (0.1 + 0.8 * i / 13)
        x = 135 - math.cos(a) * 118
        y = 140 + math.sin(a) * 30
        d.rounded_rectangle(B([x - 6, y - 18, x + 6, y + 4]), 6 * S, fill=c("#5A4636"))
    for x in (40, 110, 160, 230):
        banner(d, x, 0, "#C0392B", 34)
    return glow(img, (255, 230, 190, 110), 8)


def campaign():
    img, d = new(230, 220)
    base = 200
    d.polygon(P([(20, base), (115, base - 120), (210, base)]), fill=c("#E7C898"), outline=INK)
    d.polygon(P([(95, base), (115, base - 70), (135, base)]), fill=c("#5A3A22"))
    d.line(P([(115, base - 120), (115, base - 150)]), fill=INK, width=3 * S)
    d.polygon(P([(115, base - 150), (150, base - 140), (115, base - 128)]), fill=c("#C0392B"))
    # стяг со скрещёнными мечами
    d.rectangle(B([60, 14, 170, 90]), fill=c("#A8262B"), outline=GOLD, width=3 * S)
    for sx in (1, -1):
        x0, x1 = 115 - 40 * sx, 115 + 40 * sx
        d.line(P([(x0, 24), (x1, 80)]), fill=c("#E8ECF2"), width=6 * S)
        d.line(P([(x1 - 12 * sx, 66), (x1 + 4 * sx, 76)]), fill=GOLD, width=5 * S)
    for x in (20, 200):
        banner(d, x, 70, "#2E5BC0", 50)
    d.ellipse(B([10, base - 6, 220, base + 16]), fill=c("#6A7050", 170))
    return glow(img, (255, 210, 120, 140), 8)


def dungeon():
    img, d = new(240, 210)
    d.polygon(P([(10, 200), (20, 90), (70, 30), (150, 18), (210, 60), (232, 200)]), fill=c("#7C7888"), outline=INK)
    for pts in (((40, 120), (70, 60), (100, 80)), ((150, 40), (200, 80), (180, 120)), ((30, 170), (60, 140), (70, 190))):
        d.polygon(P(pts), fill=c("#96909E"))
    d.ellipse(B([62, 80, 178, 210]), fill=c("#2A0F4A"), outline=INK, width=3 * S)
    d.ellipse(B([76, 96, 164, 206]), fill=c("#B04CFF"))
    d.ellipse(B([96, 118, 144, 200]), fill=c("#EBC8FF"))
    return glow(img, (190, 90, 255, 230), 16)


def statue():
    img, d = new(170, 230)
    d.rectangle(B([40, 150, 130, 220]), fill=c("#ECE6DA"), outline=INK, width=3 * S)
    d.rectangle(B([30, 140, 140, 156]), fill=c("#F6F0E6"), outline=INK, width=2 * S)
    d.rectangle(B([74, 180, 96, 220]), fill=c("#C9A877"), outline=INK, width=2 * S)
    # белый волк (Кукбуре — небесный волк-проводник)
    d.polygon(P([(50, 140), (56, 90), (82, 70), (100, 30), (112, 22), (118, 40), (128, 48), (116, 60), (112, 92),
                 (124, 140)]), fill=c("#F7F7FA"), outline=INK)
    d.polygon(P([(102, 32), (106, 10), (114, 28)]), fill=c("#F7F7FA"), outline=INK)
    d.polygon(P([(52, 120), (26, 100), (40, 134)]), fill=c("#F7F7FA"), outline=INK)
    for x in (16, 144):
        banner(d, x, 110, "#2E5BC0", 60)
    return glow(img, (200, 230, 255, 150), 10)


BUILDINGS = {"fortress": fortress, "summon": summon, "guild": guild, "tavern": tavern, "arena": arena,
             "campaign": campaign, "dungeon": dungeon, "statue": statue}


# --------------------------------------------------------------------------- иконки (золото + цвет)

def icon(name, size=96):
    img, d = new(96, 96)
    if name == "events":  # подарок
        d.rectangle(B([16, 42, 80, 86]), fill=GOLD, outline=INK, width=3 * S)
        d.rectangle(B([10, 30, 86, 46]), fill=GOLD_L, outline=INK, width=3 * S)
        d.rectangle(B([42, 30, 54, 86]), fill=c("#D63C3C"))
        d.ellipse(B([24, 12, 48, 34]), outline=c("#D63C3C"), width=5 * S)
        d.ellipse(B([48, 12, 72, 34]), outline=c("#D63C3C"), width=5 * S)
    elif name == "tasks":  # планшет с галочкой
        d.rounded_rectangle(B([18, 16, 78, 88]), 8 * S, fill=c("#C98A3C"), outline=INK, width=3 * S)
        d.rounded_rectangle(B([26, 26, 70, 80]), 4 * S, fill=c("#F7EBCF"))
        d.rounded_rectangle(B([36, 10, 60, 22]), 4 * S, fill=GOLD, outline=INK, width=2 * S)
        d.line(P([(34, 54), (44, 66), (64, 38)]), fill=c("#D63C3C"), width=6 * S)
    elif name == "rewards":  # сундук
        d.rounded_rectangle(B([12, 44, 84, 86]), 6 * S, fill=c("#B5733A"), outline=INK, width=3 * S)
        d.pieslice(B([12, 20, 84, 68]), 180, 360, fill=c("#C98A3C"), outline=INK, width=3 * S)
        d.rectangle(B([12, 42, 84, 50]), fill=GOLD, outline=INK, width=2 * S)
        d.rounded_rectangle(B([40, 46, 56, 64]), 3 * S, fill=GOLD_L, outline=INK, width=2 * S)
    elif name == "battle_pass":  # щит
        d.polygon(P([(48, 8), (84, 20), (80, 56), (48, 90), (16, 56), (12, 20)]), fill=GOLD, outline=INK)
        d.polygon(P([(48, 18), (74, 27), (71, 54), (48, 78), (25, 54), (22, 27)]), fill=c("#3E5FB0"))
        d.polygon(P([(48, 28), (60, 50), (48, 66), (36, 50)]), fill=GOLD_L)
    elif name == "daily":  # календарь
        d.rounded_rectangle(B([12, 18, 84, 86]), 8 * S, fill=c("#F7EBCF"), outline=INK, width=3 * S)
        d.rounded_rectangle(B([12, 18, 84, 38]), 8 * S, fill=c("#D63C3C"), outline=INK, width=3 * S)
        for x in (28, 68):
            d.rounded_rectangle(B([x - 4, 8, x + 4, 28]), 3 * S, fill=GOLD, outline=INK, width=2 * S)
        d.line(P([(32, 60), (44, 72), (66, 46)]), fill=c("#D63C3C"), width=6 * S)
    elif name == "mail":
        d.rounded_rectangle(B([10, 22, 86, 78]), 6 * S, fill=c("#F4F0E8"), outline=INK, width=3 * S)
        d.line(P([(12, 26), (48, 54), (84, 26)]), fill=INK, width=3 * S)
        d.line(P([(12, 76), (38, 50)]), fill=INK, width=2 * S)
        d.line(P([(84, 76), (58, 50)]), fill=INK, width=2 * S)
    elif name == "settings":  # шестерёнка
        pts = []
        for i in range(32):
            a = math.pi * 2 * i / 32
            r = 40 if (i // 2) % 2 == 0 else 30
            pts.append((48 + math.cos(a) * r, 48 + math.sin(a) * r))
        d.polygon(P(pts), fill=c("#E8ECF2"), outline=INK)
        d.ellipse(B([34, 34, 62, 62]), fill=c("#2A2440"), outline=INK, width=2 * S)
    elif name == "heroes":  # шлем
        d.pieslice(B([16, 10, 80, 86]), 180, 360, fill=GOLD, outline=INK, width=3 * S)
        d.rectangle(B([16, 46, 80, 84]), fill=GOLD, outline=INK, width=3 * S)
        d.rectangle(B([30, 50, 66, 60]), fill=c("#2A2440"))
        d.rectangle(B([44, 58, 52, 84]), fill=c("#2A2440"))
        d.polygon(P([(48, 4), (40, 24), (56, 24)]), fill=c("#D63C3C"), outline=INK)
    elif name == "inventory":  # сумка
        d.rounded_rectangle(B([12, 30, 84, 88]), 14 * S, fill=c("#C98A3C"), outline=INK, width=3 * S)
        d.arc(B([30, 10, 66, 46]), 180, 360, fill=INK, width=5 * S)
        d.rounded_rectangle(B([12, 30, 84, 56]), 12 * S, fill=c("#B5733A"), outline=INK, width=3 * S)
        d.rounded_rectangle(B([40, 46, 56, 62]), 3 * S, fill=GOLD, outline=INK, width=2 * S)
    elif name == "city":  # замок
        d.rectangle(B([16, 44, 80, 88]), fill=GOLD, outline=INK, width=3 * S)
        for x, w, top in ((12, 20, 30), (64, 20, 30), (36, 24, 18)):
            d.rectangle(B([x, top + 14, x + w, 88]), fill=GOLD_L, outline=INK, width=2 * S)
            d.polygon(P([(x - 3, top + 14), (x + w / 2, top - 10), (x + w + 3, top + 14)]), fill=GOLD, outline=INK)
        d.rounded_rectangle(B([40, 64, 56, 88]), 8 * S, fill=c("#5A3A22"))
    elif name == "quests":  # свиток
        d.rectangle(B([22, 18, 74, 80]), fill=c("#F2E2C0"), outline=INK, width=3 * S)
        for y in (16, 80):
            d.rounded_rectangle(B([14, y - 6, 82, y + 6]), 6 * S, fill=c("#C98A3C"), outline=INK, width=2 * S)
        for y in (34, 46, 58):
            d.line(P([(32, y), (64, y)]), fill=c("#8A6A3A"), width=3 * S)
    elif name == "world":  # компас
        d.ellipse(B([8, 8, 88, 88]), fill=c("#2A2440"), outline=GOLD, width=5 * S)
        d.polygon(P([(48, 12), (56, 48), (48, 84), (40, 48)]), fill=GOLD_L, outline=INK)
        d.polygon(P([(12, 48), (48, 40), (84, 48), (48, 56)]), fill=GOLD, outline=INK)
        d.polygon(P([(48, 12), (56, 48), (40, 48)]), fill=c("#D63C3C"))
    elif name == "coin":
        d.ellipse(B([8, 8, 88, 88]), fill=GOLD, outline=GOLD_D, width=5 * S)
        d.ellipse(B([24, 24, 72, 72]), outline=GOLD_L, width=4 * S)
        d.polygon(P([(48, 32), (56, 48), (48, 64), (40, 48)]), fill=GOLD_L)
    elif name == "crystal":
        d.polygon(P([(48, 6), (84, 34), (48, 90), (12, 34)]), fill=c("#4FA8FF"), outline=c("#FFFFFF"))
        d.polygon(P([(48, 6), (60, 34), (48, 90), (36, 34)]), fill=c("#A8DCFF"))
        d.line(P([(12, 34), (84, 34)]), fill=c("#FFFFFF"), width=2 * S)
    elif name == "power":  # скрещённые мечи
        for sx in (1, -1):
            x0, x1 = 48 - 34 * sx, 48 + 30 * sx
            d.line(P([(x0, 12), (x1, 78)]), fill=c("#E8ECF2"), width=8 * S)
            d.line(P([(x1 - 14 * sx, 64), (x1 + 6 * sx, 74)]), fill=GOLD, width=6 * S)
    elif name == "plus":
        d.ellipse(B([6, 6, 90, 90]), fill=GOLD, outline=GOLD_D, width=4 * S)
        d.rectangle(B([42, 22, 54, 74]), fill=c("#3A2A10"))
        d.rectangle(B([22, 42, 74, 54]), fill=c("#3A2A10"))
    else:
        raise ValueError(name)
    save(img, f"icon_{name}.png", size, size)


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
    for name, fn in BUILDINGS.items():
        save(fn(), f"building_{name}.png")
    for i in ("events", "tasks", "rewards", "battle_pass", "daily", "mail", "settings", "heroes", "inventory",
              "quests", "world", "coin", "crystal", "power", "plus"):
        icon(i)
    icon("city", 128)
    emblem()

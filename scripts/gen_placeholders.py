#!/usr/bin/env python3
"""Генератор PNG-заглушек в едином стиле (тёмно-фиолетовый + золото).

Только стандартная библиотека Python — ничего ставить не нужно.
Запуск из корня репозитория:  python3 scripts/gen_placeholders.py
Заглушки затем заменяются ИИ-артом через админку.
"""
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "content"

DARK = (22, 14, 36)
PURPLE = (59, 31, 92)
GOLD = (242, 181, 68)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def write_png(path: Path, w: int, h: int, pixel) -> None:
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            raw.extend(pixel(x, y))
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
    print(f"{path.relative_to(ROOT.parent)}  {len(png)} байт")


def gradient_bg(top, bottom, w, h):
    def px(x, y):
        c = lerp(top, bottom, y / (h - 1))
        # золотая рамка
        if x < 3 or y < 3 or x >= w - 3 or y >= h - 3:
            c = GOLD
        return (*c, 255)
    return px


def button(w, h):
    def px(x, y):
        edge = min(x, y, w - 1 - x, h - 1 - y)
        if edge < 2:
            return (*GOLD, 255)
        return (*lerp(PURPLE, DARK, y / h), 255)
    return px


def logo(size):
    c = size / 2
    def px(x, y):
        d = ((x - c) ** 2 + (y - c) ** 2) ** 0.5 / c
        if d > 1:
            return (0, 0, 0, 0)
        if d > 0.88:
            return (*GOLD, 255)
        # стилизованная «гора Урала» — треугольник
        if y > size * 0.35 and abs(x - c) < (y - size * 0.35) * 0.9 and y < size * 0.75:
            return (*GOLD, 255)
        return (*lerp(PURPLE, DARK, d), 255)
    return px


if __name__ == "__main__":
    write_png(ROOT / "ui/logo.png", 128, 128, logo(128))
    write_png(ROOT / "ui/button.png", 96, 32, button(96, 32))
    write_png(ROOT / "ui/loading_bg.png", 90, 160, gradient_bg(PURPLE, DARK, 90, 160))
    write_png(ROOT / "campaign/chapter_1/background.png", 90, 160, gradient_bg((40, 70, 60), DARK, 90, 160))
    write_png(ROOT / "campaign/chapter_2/background.png", 90, 160, gradient_bg((70, 80, 110), DARK, 90, 160))

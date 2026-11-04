#!/usr/bin/env python3
"""Генерация собственной графики интерфейса боя (авторская работа проекта, без сторонних источников):
каменная круглая арена, диск, значки ролей. Запуск: python3 tools/gen_ui_assets.py (нужен Pillow).
Результат кладётся в client/assets/ui/. Временная графика до выбора финальной визуальной концепции."""
import math, random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "client" / "assets" / "ui"
OUT.mkdir(parents=True, exist_ok=True)
random.seed(7)


def arena_floor(size=1024):
    S = 2  # суперсэмплинг
    N = size * S
    c = N // 2
    R = int(N * 0.49)
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    grout = (66, 58, 70, 255)
    d.ellipse((c - R, c - R, c + R, c + R), fill=grout)
    ring_h = R / 8.0
    r0 = ring_h * 0.9  # центральная медальон-плита
    # кольца плит
    r_in = r0
    ri = 0
    while r_in < R - ring_h * 0.4:
        r_out = min(R, r_in + ring_h * (1.0 if ri % 2 == 0 else 0.8))
        circ = 2 * math.pi * (r_in + r_out) / 2
        n = max(8, int(circ / ((r_out - r_in) * 1.7)))
        off = random.random() * 2 * math.pi
        for k in range(n):
            a0 = off + 2 * math.pi * k / n
            a1 = off + 2 * math.pi * (k + 1) / n
            gap = 0.012
            pts = []
            steps = 8
            for t in range(steps + 1):
                a = a0 + gap + (a1 - a0 - 2 * gap) * t / steps
                pts.append((c + (r_out - 2 * S) * math.cos(a), c + (r_out - 2 * S) * math.sin(a)))
            for t in range(steps, -1, -1):
                a = a0 + gap + (a1 - a0 - 2 * gap) * t / steps
                pts.append((c + (r_in + 2 * S) * math.cos(a), c + (r_in + 2 * S) * math.sin(a)))
            v = random.randint(-14, 14)
            shade = 1.0 - 0.18 * (r_in / R)  # к краю чуть темнее
            base = (int((150 + v) * shade), int((138 + v) * shade), int((152 + v) * shade), 255)
            d.polygon(pts, fill=base)
            # блик на плите
            if random.random() < 0.35:
                am = (a0 + a1) / 2
                rm = (r_in + r_out) / 2
                d.ellipse((c + rm * math.cos(am) - 6 * S, c + rm * math.sin(am) - 3 * S, c + rm * math.cos(am) + 6 * S, c + rm * math.sin(am) + 3 * S), fill=(base[0] + 12, base[1] + 12, base[2] + 12, 255))
        r_in = r_out
        ri += 1
    # центр
    d.ellipse((c - r0, c - r0, c + r0, c + r0), fill=(132, 120, 138, 255))
    d.ellipse((c - r0 * 0.78, c - r0 * 0.78, c + r0 * 0.78, c + r0 * 0.78), outline=(205, 165, 80, 255), width=3 * S)
    for k in range(8):
        a = k * math.pi / 4
        d.line((c, c, c + r0 * 0.7 * math.cos(a), c + r0 * 0.7 * math.sin(a)), fill=(205, 165, 80, 255), width=2 * S)
    # золотые кольца
    for rr, w in ((R * 0.50, 3), (R * 0.985, 5)):
        d.ellipse((c - rr, c - rr, c + rr, c + rr), outline=(214, 172, 84, 255), width=w * S)
    d.ellipse((c - R, c - R, c + R, c + R), outline=(90, 74, 60, 255), width=4 * S)
    img = img.filter(ImageFilter.GaussianBlur(0.8 * S / 2))
    # зерно
    px = img.load()
    for _ in range(N * N // 14):
        x, y = random.randrange(N), random.randrange(N)
        p = px[x, y]
        if p[3] > 0:
            n = random.randint(-9, 9)
            px[x, y] = (max(0, min(255, p[0] + n)), max(0, min(255, p[1] + n)), max(0, min(255, p[2] + n)), p[3])
    # круговая маска
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).ellipse((c - R, c - R, c + R, c + R), fill=255)
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (N, N), 0), mask))
    return img.resize((size, size), Image.LANCZOS)


def icon_canvas(size=128, S=4):
    N = size * S
    return Image.new("RGBA", (N, N), (0, 0, 0, 0)), N, S


def finish(img, size=128):
    return img.resize((size, size), Image.LANCZOS)


W = (255, 255, 255, 255)


def disc():
    im, N, S = icon_canvas(128)
    ImageDraw.Draw(im).ellipse((4 * S, 4 * S, N - 4 * S, N - 4 * S), fill=W)
    return finish(im)


def shield():
    im, N, S = icon_canvas()
    d = ImageDraw.Draw(im)
    pts = [(N * .22, N * .18), (N * .78, N * .18), (N * .78, N * .5), (N * .5, N * .86), (N * .22, N * .5)]
    d.polygon(pts, fill=W)
    d.polygon([(N * .34, N * .3), (N * .66, N * .3), (N * .66, N * .48), (N * .5, N * .7), (N * .34, N * .48)], fill=(0, 0, 0, 0))
    return finish(im)


def sword(angle_deg=45, canvas=None):
    im, N, S = canvas or icon_canvas()
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.polygon([(N * .5, N * .08), (N * .57, N * .62), (N * .43, N * .62)], fill=W)       # клинок
    d.rectangle((N * .32, N * .62, N * .68, N * .68), fill=W)                              # гарда
    d.rectangle((N * .46, N * .68, N * .54, N * .86), fill=W)                              # рукоять
    d.ellipse((N * .43, N * .84, N * .57, N * .92), fill=W)
    layer = layer.rotate(-angle_deg, resample=Image.BICUBIC)
    im.alpha_composite(layer)
    return im, N, S


def bow():
    im, N, S = icon_canvas()
    d = ImageDraw.Draw(im)
    d.arc((N * .1, N * .12, N * .78, N * .88), 270, 90, fill=W, width=int(N * .06))
    d.line((N * .44, N * .12, N * .44, N * .88), fill=W, width=int(N * .025))
    d.line((N * .22, N * .5, N * .92, N * .5), fill=W, width=int(N * .045))
    d.polygon([(N * .96, N * .5), (N * .8, N * .4), (N * .8, N * .6)], fill=W)
    return finish(im)


def star4():
    im, N, S = icon_canvas()
    d = ImageDraw.Draw(im)
    c = N / 2
    pts = []
    for k in range(8):
        r = N * (.42 if k % 2 == 0 else .13)
        a = math.pi / 4 * k - math.pi / 2
        pts.append((c + r * math.cos(a), c + r * math.sin(a)))
    d.polygon(pts, fill=W)
    d.ellipse((N * .74, N * .16, N * .84, N * .26), fill=W)
    return finish(im)


def cross():
    im, N, S = icon_canvas()
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((N * .4, N * .14, N * .6, N * .86), radius=int(N * .05), fill=W)
    d.rounded_rectangle((N * .14, N * .4, N * .86, N * .6), radius=int(N * .05), fill=W)
    return finish(im)


def swords():
    im, N, S = icon_canvas()
    for ang in (35, -35):
        layer, _, _ = sword(ang, (Image.new("RGBA", (N, N), (0, 0, 0, 0)), N, S))
        im.alpha_composite(layer)
    return finish(im)


def melee():
    im, N, S = sword(0)
    return finish(im)


if __name__ == "__main__":
    arena_floor().save(OUT / "arena_floor.png", optimize=True)
    for name, fn in (("disc", disc), ("role_tank", shield), ("role_melee", melee), ("role_ranged", bow), ("role_mage", star4), ("role_healer", cross), ("swords", swords)):
        fn().save(OUT / f"{name}.png", optimize=True)
    print("готово:", sorted(p.name for p in OUT.iterdir()))

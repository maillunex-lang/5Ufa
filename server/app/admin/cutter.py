"""Нарезчик героя (админка, этап 6в-3): рисунок → части тела → скелет из шаблона → файлы героя.

Сессия нарезки — папка на диске сервера (CONTENT_STORE_DIR/.cutter/<id>/):
  source.png   — рабочий рисунок (фон удалён, после выбора позы на листе — только она)
  original.png — загруженный рисунок целиком (для «листа персонажа»)
  layers/*.png — слои того же размера, что source: из ZIP слоёв или нарезка ИИ
  meta.json    — размеры, режим, список слоёв

Часть героя (то, что присылает админка):
  {"name": "head", "layer": "source" | "<слой>", "polygons": [[[x, y], ...], ...],
   "strokes": [{"mode": "add" | "erase", "r": 12, "pts": [[x, y], ...]}]}
Маска части = закрашенные многоугольники (если их нет и слой не source — весь слой) + мазки «добавить»
− мазки «стереть»; пиксели берутся из слоя. Координаты — пиксели рисунка source.
"""
from __future__ import annotations

import io
import json
import re
import shutil
import time
import uuid
import zipfile
from functools import lru_cache
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps

from app.config import get_settings

MAX_SIDE = 1600
SESSION_TTL = 2 * 24 * 3600
ROOT_SCALE = 0.5          # картинки частей в 2 раза крупнее экрана — запас резкости
NAME_RE = re.compile(r"^[a-z][a-z0-9_]{0,40}$")


class CutterError(Exception):
    pass


# --- Шаблоны ---------------------------------------------------------------------------------

@lru_cache
def templates() -> dict:
    doc = json.loads((get_settings().shared_dir / "admin" / "rig_templates.json").read_text(encoding="utf-8"))
    return {t["id"]: t for t in doc["templates"]}


def template(tid: str) -> dict:
    t = templates().get(tid)
    if t is None:
        raise CutterError(f"Нет шаблона скелета «{tid}»")
    return t


def templates_public() -> list[dict]:
    return [{"id": t["id"], "name": t["name"], "parts": t["parts"], "bones": t["bones"],
             "same_as": t.get("same_as", {})} for t in templates().values()]


# --- Сессии ----------------------------------------------------------------------------------

def _root() -> Path:
    return Path(get_settings().content_store_dir) / ".cutter"


def _cleanup() -> None:
    root = _root()
    if not root.exists():
        return
    now = time.time()
    for d in root.iterdir():
        try:
            if d.is_dir() and now - d.stat().st_mtime > SESSION_TTL:
                shutil.rmtree(d, ignore_errors=True)
        except OSError:
            pass


def session_dir(sid: str) -> Path:
    if not re.fullmatch(r"[0-9a-f]{32}", sid or ""):
        raise CutterError("Сессия нарезки не найдена")
    d = _root() / sid
    if not (d / "meta.json").exists():
        raise CutterError("Сессия нарезки не найдена (устарела — загрузите рисунок заново)")
    return d


def read_meta(sid: str) -> dict:
    return json.loads((session_dir(sid) / "meta.json").read_text(encoding="utf-8"))


def _write_meta(d: Path, meta: dict) -> None:
    (d / "meta.json").write_text(json.dumps(meta, ensure_ascii=False), encoding="utf-8")


def load_rgba(path: Path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"))


def save_png(arr: np.ndarray, path: Path | None = None) -> bytes:
    buf = io.BytesIO()
    Image.fromarray(arr).save(buf, "PNG", optimize=True)
    data = buf.getvalue()
    if path is not None:
        path.write_bytes(data)
    return data


def _open_image(data: bytes) -> Image.Image:
    try:
        im = Image.open(io.BytesIO(data))
        im = ImageOps.exif_transpose(im)
        im = im.convert("RGBA")
    except Exception:  # noqa: BLE001 — любой битый файл
        raise CutterError("Не удалось открыть картинку (нужен PNG, JPG или WEBP)") from None
    return im


def _fit(im: Image.Image, side: int = MAX_SIDE) -> Image.Image:
    if max(im.size) > side:
        k = side / max(im.size)
        im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    return im


def remove_background(rgba: np.ndarray, tol: int = 40) -> np.ndarray:
    """Фон — сплошной цвет у краёв (белый, пурпурный #FF00FF и т. п.), связанный с краем картинки.
    Если у картинки уже есть прозрачность — она сохраняется."""
    alpha = rgba[:, :, 3]
    if (alpha < 250).mean() > 0.02:
        return rgba
    rgb = rgba[:, :, :3].astype(np.int16)
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    bg = np.median(border, axis=0)
    dist = np.abs(rgb - bg).max(axis=2)
    bgmask = (dist < tol).astype(np.uint8)
    _, labels = cv2.connectedComponents(bgmask, connectivity=4)
    edge = np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])
    edge_bg = np.concatenate([bgmask[0], bgmask[-1], bgmask[:, 0], bgmask[:, -1]])
    ids = np.unique(edge[edge_bg == 1])
    is_bg = np.isin(labels, ids) & (bgmask == 1)
    a = np.where(is_bg, 0, 255).astype(np.uint8)
    a = cv2.erode(a, np.ones((2, 2), np.uint8))
    a = cv2.GaussianBlur(a, (3, 3), 0)
    out = rgba.copy()
    # Убираем цвет фона с полупрозрачного края (иначе остаётся розовая/белая кайма)
    edge_px = (a > 0) & (a < 255)
    if edge_px.any():
        al = (a[edge_px].astype(np.float32) / 255.0)[:, None]
        col = out[edge_px][:, :3].astype(np.float32)
        un = (col - bg[None, :] * (1 - al)) / np.maximum(al, 0.05)
        out[edge_px, :3] = np.clip(un, 0, 255).astype(np.uint8)
    out[:, :, 3] = a
    return out


def figure_bbox(alpha: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.nonzero(alpha > 16)
    if len(xs) == 0:
        raise CutterError("На рисунке не найден персонаж (всё прозрачное или фон не удалился)")
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def _safe_layer(name: str) -> str:
    n = re.sub(r"[^a-z0-9_]+", "_", Path(name).stem.lower()).strip("_")
    if not n or not n[0].isalpha():
        n = "layer_" + n
    return n[:40]


def create_session(data: bytes, filename: str = "") -> dict:
    """Загрузка: картинка (цельный рисунок или лист персонажа) или ZIP слоёв на общем холсте."""
    _cleanup()
    sid = uuid.uuid4().hex
    d = _root() / sid
    (d / "layers").mkdir(parents=True)
    layers: list[str] = []
    if data[:2] == b"PK" or filename.lower().endswith(".zip"):
        try:
            zf = zipfile.ZipFile(io.BytesIO(data))
        except zipfile.BadZipFile:
            raise CutterError("ZIP повреждён") from None
        imgs = []
        for info in zf.infolist():
            if info.is_dir() or not info.filename.lower().endswith((".png", ".webp")):
                continue
            if info.file_size > 40 * 1024 * 1024:
                raise CutterError(f"Слишком большой слой: {info.filename}")
            imgs.append((info.filename, _open_image(zf.read(info))))
        if not imgs:
            raise CutterError("В ZIP нет слоёв PNG")
        if len(imgs) > 40:
            raise CutterError("Слишком много слоёв (больше 40)")
        w = max(im.width for _, im in imgs)
        h = max(im.height for _, im in imgs)
        k = min(1.0, MAX_SIDE / max(w, h))
        cw, ch = max(1, round(w * k)), max(1, round(h * k))
        canvas = Image.new("RGBA", (cw, ch))
        for fname, im in imgs:
            if k < 1:
                im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
            full = Image.new("RGBA", (cw, ch))
            full.paste(im, (0, 0))
            name = _safe_layer(fname)
            while name in layers:
                name += "_2"
            layers.append(name)
            full.save(d / "layers" / f"{name}.png")
            canvas.alpha_composite(full)
        src = np.array(canvas)
        mode = "layers"
    else:
        src = remove_background(np.array(_fit(_open_image(data))))
        mode = "image"
    figure_bbox(src[:, :, 3])
    save_png(src, d / "original.png")
    save_png(src, d / "source.png")
    meta = {"id": sid, "mode": mode, "w": int(src.shape[1]), "h": int(src.shape[0]), "layers": layers,
            "created": time.time()}
    _write_meta(d, meta)
    return meta


def crop_session(sid: str, x: int, y: int, w: int, h: int) -> dict:
    """Лист персонажа: оставить одну позу (прямоугольник на исходной картинке)."""
    d = session_dir(sid)
    meta = read_meta(sid)
    if meta["mode"] == "layers":
        raise CutterError("Слои уже на общем холсте — выбирать позу не нужно")
    orig = load_rgba(d / "original.png")
    H, W = orig.shape[:2]
    x0, y0 = max(0, int(x)), max(0, int(y))
    x1, y1 = min(W, int(x + w)), min(H, int(y + h))
    if x1 - x0 < 16 or y1 - y0 < 16:
        raise CutterError("Слишком маленькая область")
    part = orig[y0:y1, x0:x1].copy()
    figure_bbox(part[:, :, 3])
    save_png(part, d / "source.png")
    for f in (d / "layers").glob("*.png"):
        f.unlink()
    meta.update(w=int(part.shape[1]), h=int(part.shape[0]), layers=[], crop=[x0, y0, x1 - x0, y1 - y0])
    _write_meta(d, meta)
    return meta


def image_png(sid: str, which: str = "source") -> bytes:
    d = session_dir(sid)
    if which in ("source", "original"):
        return (d / f"{which}.png").read_bytes()
    p = d / "layers" / f"{_safe_layer(which)}.png"
    if not p.exists():
        raise CutterError(f"Нет слоя «{which}»")
    return p.read_bytes()


# --- Маски частей ----------------------------------------------------------------------------

def _layer(d: Path, name: str, cache: dict) -> np.ndarray:
    if name not in cache:
        p = d / "source.png" if name in ("", "source") else d / "layers" / f"{_safe_layer(name)}.png"
        if not p.exists():
            raise CutterError(f"Нет слоя «{name}»")
        cache[name] = load_rgba(p)
    return cache[name]


def part_mask(part: dict, layer: np.ndarray, is_source: bool) -> np.ndarray:
    h, w = layer.shape[:2]
    m = np.zeros((h, w), np.uint8)
    polys = [np.array(p, np.float32).round().astype(np.int32) for p in part.get("polygons") or [] if len(p) >= 3]
    if polys:
        cv2.fillPoly(m, polys, 255)
    elif not is_source:
        m[layer[:, :, 3] > 0] = 255
    for st in part.get("strokes") or []:
        val = 255 if st.get("mode", "add") == "add" else 0
        r = max(1, min(400, int(round(float(st.get("r", 10))))))
        pts = [(int(round(p[0])), int(round(p[1]))) for p in st.get("pts") or []]
        for i, p in enumerate(pts):
            cv2.circle(m, p, r, val, -1, lineType=cv2.LINE_AA)
            if i:
                cv2.line(m, pts[i - 1], p, val, 2 * r, lineType=cv2.LINE_AA)
    return m


def render_parts(sid: str, parts: list[dict]) -> dict[str, np.ndarray]:
    """Пиксели каждой части на холсте рисунка (RGBA)."""
    d = session_dir(sid)
    cache: dict = {}
    out = {}
    for part in parts:
        lname = str(part.get("layer") or "source")
        layer = _layer(d, lname, cache)
        m = part_mask(part, layer, lname == "source")
        rgba = layer.copy()
        rgba[:, :, 3] = (layer[:, :, 3].astype(np.uint16) * m // 255).astype(np.uint8)
        out[str(part["name"])] = rgba
    return out


def part_preview(sid: str, part: dict) -> dict:
    """Картинка одной части (обрезана по видимому) + где она на рисунке."""
    rgba = render_parts(sid, [part])[str(part["name"])]
    ys, xs = np.nonzero(rgba[:, :, 3] > 8)
    if len(xs) == 0:
        return {"empty": True}
    x0, y0, x1, y1 = int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1
    import base64
    return {"empty": False, "x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0,
            "png": base64.b64encode(save_png(rgba[y0:y1, x0:x1])).decode("ascii")}


def _mask_polygons(mask: np.ndarray, min_area: float = 30) -> list[list[list[float]]]:
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    out = []
    for c in contours:
        if cv2.contourArea(c) < min_area:
            continue
        c = cv2.approxPolyDP(c, 1.2, True)
        if len(c) >= 3:
            out.append([[float(p[0][0]), float(p[0][1])] for p in c])
    return out


def _px(pt, box) -> list[float]:
    x0, y0, x1, y1 = box
    return [round(x0 + float(pt[0]) * (x1 - x0), 1), round(y0 + float(pt[1]) * (y1 - y0), 1)]


def default_joints(tpl: dict, box) -> dict:
    return {k: _px(v, box) for k, v in tpl["joints"].items()}


def _joint_from_mask(mask: np.ndarray, side: str) -> list[float] | None:
    ys, xs = np.nonzero(mask)
    if len(xs) < 20:
        return None
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    w, h = x1 - x0 + 1, y1 - y0 + 1
    if side == "top":
        band = ys <= y0 + 0.15 * h
        return [round(float(xs[band].mean()), 1), round(float(y0 + 0.1 * h), 1)]
    if side == "bottom":
        band = ys >= y1 - 0.15 * h
        return [round(float(xs[band].mean()), 1), round(float(y1 - 0.12 * h), 1)]
    if side == "left":
        band = xs <= x0 + 0.15 * w
        return [round(float(x0 + 0.15 * w), 1), round(float(ys[band].mean()), 1)]
    if side == "right":
        band = xs >= x1 - 0.15 * w
        return [round(float(x1 - 0.1 * w), 1), round(float(ys[band].mean()), 1)]
    return None


def fit_joints(tpl: dict, joints: dict, masks: dict[str, np.ndarray]) -> dict:
    """Уточнить суставы по вырезанным частям (сустав — у стороны части, указанной в шаблоне)."""
    j = dict(joints)
    for part in tpl["parts"]:
        side = part.get("joint_at")
        m = masks.get(part["name"])
        if side and m is not None:
            p = _joint_from_mask(m, side)
            if p:
                j[part["name"]] = p
    legs = [j[n] for n in ("leg_back", "leg_front") if n in j and masks.get(n) is not None]
    if tpl["id"] != "beast" and legs:
        j["hips"] = [round(sum(p[0] for p in legs) / len(legs), 1), round(min(p[1] for p in legs) - 2, 1)]
    for a, b in tpl.get("same_as", {}).items():
        j[a] = list(j[b])
    return j


def auto_cut(sid: str, tid: str) -> dict:
    """Автонарезка без ИИ: пиксели персонажа делятся по областям шаблона."""
    tpl = template(tid)
    d = session_dir(sid)
    meta = read_meta(sid)
    src = load_rgba(d / "source.png")
    fg = src[:, :, 3] > 16
    box = figure_bbox(src[:, :, 3])
    names = [p["name"] for p in tpl["parts"]]
    # Слои с именами частей шаблона (ZIP слоёв) — часть = весь слой
    if meta.get("layers"):
        parts = []
        for n in names:
            if n in meta["layers"]:
                parts.append({"name": n, "layer": n, "polygons": [], "strokes": []})
            else:
                parts.append({"name": n, "layer": "source", "polygons": [], "strokes": []})
        masks = {p["name"]: (load_rgba(d / "layers" / f"{p['name']}.png")[:, :, 3] > 16).astype(np.uint8)
                 for p in parts if p["layer"] != "source"}
        return {"parts": parts, "joints": fit_joints(tpl, default_joints(tpl, box), masks), "box": box,
                "layers_matched": sorted(masks)}
    label = np.full(fg.shape, -1, np.int16)
    for i, (name, poly) in enumerate(tpl["regions"].items()):
        rm = np.zeros(fg.shape, np.uint8)
        cv2.fillPoly(rm, [np.array([_px(p, box) for p in poly], np.float32).round().astype(np.int32)], 1)
        sel = (rm == 1) & fg & (label < 0)
        label[sel] = names.index(name) if name in names else -1
    label[fg & (label < 0)] = names.index(tpl.get("fallback_part", names[0]))
    parts, masks = [], {}
    kernel = np.ones((3, 3), np.uint8)
    for i, n in enumerate(names):
        m = (label == i).astype(np.uint8) * 255
        m = cv2.morphologyEx(m, cv2.MORPH_OPEN, kernel)
        polys = _mask_polygons(m)
        parts.append({"name": n, "layer": "source", "polygons": polys, "strokes": []})
        if polys:
            masks[n] = (m > 0).astype(np.uint8)
    return {"parts": parts, "joints": fit_joints(tpl, default_joints(tpl, box), masks), "box": box}


# --- Нарезка ИИ (spine-animation-ai) ----------------------------------------------------------

def ai_cut(sid: str, tid: str, generate_image, detect_boxes) -> dict:
    """Gemini рисует лист частей, части ищутся на рисунке и переносятся слоями на его холст.
    generate_image(prompt, png) -> png; detect_boxes(png, labels) -> [{"label", "box"}]."""
    from app.vendor.spine_ai import atlas as sa

    tpl = template(tid)
    d = session_dir(sid)
    src = load_rgba(d / "source.png")
    H, W = src.shape[:2]
    box = figure_bbox(src[:, :, 3])
    # Образец для ИИ — персонаж на белом фоне
    white = np.full((H, W, 3), 255, np.float32)
    al = src[:, :, 3:4].astype(np.float32) / 255
    ref_rgb = (src[:, :, :3] * al + white * (1 - al)).astype(np.uint8)
    buf = io.BytesIO()
    Image.fromarray(ref_rgb).save(buf, "PNG")
    prompt = sa.prompt_for([p["ai"] for p in tpl["parts"]])
    atlas_png = generate_image(prompt, buf.getvalue())
    (d / "ai_atlas.png").write_bytes(atlas_png)
    atlas = np.array(Image.open(io.BytesIO(atlas_png)).convert("RGB"))
    comps = sa.segment_parts(atlas)
    if not comps:
        raise CutterError("ИИ вернул лист без частей — попробуйте ещё раз")
    names = [p["name"] for p in tpl["parts"]]
    labels = detect_boxes(atlas_png, names)
    places = sa.place_parts(src, comps)
    ah, aw = atlas.shape[:2]
    layers: dict[str, np.ndarray] = {}
    placed = unplaced = 0
    for comp, place in zip(comps, places):
        x, y, w, h = comp["box"]
        cx, cy = (x + w / 2) / aw, (y + h / 2) / ah
        lab = None
        best = 0.0
        for b in labels:  # подпись — рамка ИИ, в которой центр части (или с наибольшим перекрытием)
            bx0, by0, bx1, by1 = b["box"]
            ix = max(0.0, min(bx1, (x + w) / aw) - max(bx0, x / aw))
            iy = max(0.0, min(by1, (y + h) / ah) - max(by0, y / ah))
            ov = ix * iy + (1.0 if bx0 <= cx <= bx1 and by0 <= cy <= by1 else 0.0)
            if ov > best:
                best, lab = ov, b["label"]
        if place is None:
            unplaced += 1
            continue
        warped = cv2.warpAffine(comp["rgba"], place["M"], (W, H), flags=cv2.INTER_LINEAR,
                                borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))
        if lab is None:  # без подписи — по области шаблона, где оказался центр
            ys, xs = np.nonzero(warped[:, :, 3] > 128)
            if len(xs) == 0:
                unplaced += 1
                continue
            px, py = (xs.mean() - box[0]) / max(1, box[2] - box[0]), (ys.mean() - box[1]) / max(1, box[3] - box[1])
            for n, poly in tpl["regions"].items():
                if cv2.pointPolygonTest(np.array(poly, np.float32), (float(px), float(py)), False) >= 0:
                    lab = n
                    break
            lab = lab or tpl.get("fallback_part", names[0])
        if lab in layers:  # несколько кусков одной части — объединяем
            cur = layers[lab]
            a = warped[:, :, 3:4].astype(np.float32) / 255
            cur[:, :, :3] = (warped[:, :, :3] * a + cur[:, :, :3] * (1 - a)).astype(np.uint8)
            cur[:, :, 3] = np.maximum(cur[:, :, 3], warped[:, :, 3])
        else:
            layers[lab] = warped
        placed += 1
    if not layers:
        raise CutterError("ИИ нарисовал части, но их не удалось совместить с рисунком — используйте автонарезку")
    meta = read_meta(sid)
    for n, arr in layers.items():
        save_png(arr, d / "layers" / f"ai_{n}.png")
    meta["layers"] = sorted(set(meta.get("layers", [])) | {f"ai_{n}" for n in layers})
    _write_meta(d, meta)
    parts, masks = [], {}
    for n in names:
        if n in layers:
            parts.append({"name": n, "layer": f"ai_{n}", "polygons": [], "strokes": []})
            masks[n] = (layers[n][:, :, 3] > 16).astype(np.uint8)
        else:
            parts.append({"name": n, "layer": "source", "polygons": [], "strokes": []})
    return {"parts": parts, "joints": fit_joints(tpl, default_joints(tpl, box), masks), "box": box,
            "ai": {"pieces": len(comps), "placed": placed, "unplaced": unplaced, "parts": sorted(layers)}}


# --- Сборка героя ----------------------------------------------------------------------------

def _crop(rgba: np.ndarray):
    ys, xs = np.nonzero(rgba[:, :, 3] > 8)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def _resize(arr: np.ndarray, k: float) -> Image.Image:
    im = Image.fromarray(arr)
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)


def _png(im: Image.Image) -> bytes:
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return buf.getvalue()


def _anim_extras(tpl: dict, anims: dict) -> dict:
    """Взмахи крыльев и хвоста поверх анимаций шаблона."""
    out = json.loads(json.dumps(anims))
    for name, a in out.items():
        dur = float(a.get("duration", 1.0))
        bones = a.setdefault("bones", {})
        for i, b in enumerate(tpl.get("flap", [])):
            amp = -18 if name in ("attack", "skill", "ultimate", "victory") else -10
            bones.setdefault(b, {})["rotate"] = [[0, 0], [round(dur / 2, 3), amp * (1 if i == 0 else 0.8)], [dur, 0]]
        for b in tpl.get("wag", []):
            bones.setdefault(b, {})["rotate"] = [[0, 0], [round(dur / 3, 3), 8], [round(2 * dur / 3, 3), -8], [dur, 0]]
    return out


DEFAULT_ANIMS = {
    "idle": {"duration": 1.6, "loop": True, "bones": {"torso": {"rotate": [[0, 0], [0.8, 2], [1.6, 0]]}}},
    "attack": {"duration": 0.6, "bones": {"arm_front": {"rotate": [[0, 0], [0.22, -150], [0.35, 30], [0.6, 0]]}},
               "events": [{"t": 0.35, "name": "hit"}]},
    "hit": {"duration": 0.3, "bones": {"root": {"translate": [[0, 0, 0], [0.1, -6, 0], [0.3, 0, 0]]}}},
    "death": {"duration": 0.8, "bones": {"root": {"rotate": [[0, 0], [0.8, -80]]}}},
}


def build_rig(sid: str, tid: str, parts: list[dict], joints: dict, *, existing: dict | None = None,
              skin: str | None = None, base_anims: dict | None = None) -> tuple[dict[str, bytes], dict, dict]:
    """Файлы героя из нарезки. Возвращает (файлы {путь от папки героя: байты}, skeleton.json, отчёт).

    skin=None — обычный вид: новый скелет по шаблону, картинки rig/<часть>.png.
    skin="<id>" — скин: скелет и анимации героя прежние, у частей — свои картинки и точки крепления
    (поле slots[].skins), картинки skins/<скин>/rig/<часть>.png.
    """
    tpl = template(tid)
    names = {p["name"] for p in tpl["parts"]}
    for p in parts:
        if p.get("name") not in names:
            raise CutterError(f"Часть «{p.get('name')}» не из шаблона «{tpl['name']}»")
    j = {k: [float(v[0]), float(v[1])] for k, v in joints.items()}
    for a, b in tpl.get("same_as", {}).items():
        if b in j:
            j[a] = list(j[b])
    for b in tpl["bones"]:
        if b["name"] not in j:
            raise CutterError(f"Не задан сустав «{b['name']}»")
    pix = render_parts(sid, parts)
    crops = {n: _crop(a) for n, a in pix.items()}
    crops = {n: c for n, c in crops.items() if c}
    if not crops:
        raise CutterError("Все части пустые — вырежьте хотя бы одну часть")
    fx0 = min(c[0] for c in crops.values())
    fy0 = min(c[1] for c in crops.values())
    fx1 = max(c[2] for c in crops.values())
    fy1 = max(c[3] for c in crops.values())
    fig_h = max(1, fy1 - fy0)
    files: dict[str, bytes] = {}
    report = {"parts": sorted(crops), "empty": sorted(names - set(crops))}

    if skin:
        if not existing:
            raise CutterError("У героя ещё нет скелета — сначала нарежьте обычный вид")
        skel = json.loads(json.dumps(existing))
        bones = {b["name"]: b for b in skel["bones"]}
        root_scale = float(bones.get("root", {}).get("scale_y", 1.0))
        size_h = float((skel.get("size") or [0, 130])[1]) or 130.0
        k = size_h / (fig_h * root_scale)
        slots = {s["name"]: s for s in skel["slots"]}
        missing = []
        for n, (x0, y0, x1, y1) in crops.items():
            slot = slots.get(n)
            if slot is None:
                missing.append(n)
                continue
            img = _resize(pix[n][y0:y1, x0:x1], k)
            jp = j[slot["bone"]] if slot["bone"] in j else j.get(n)
            rel = f"rig/{n}.png"
            files[f"skins/{skin}/{rel}"] = _png(img)
            slot.setdefault("skins", {})[skin] = {"image": rel,
                                                  "pivot": [round((jp[0] - x0) * k, 2), round((jp[1] - y0) * k, 2)]}
        report["not_in_skeleton"] = missing
        return files, skel, report

    height = float(tpl["height"])
    if existing and existing.get("size"):
        height = float(existing["size"][1]) or height
    k = height / (fig_h * ROOT_SCALE)
    origin = [j["hips"][0], float(fy1)]
    bones = [{"name": "root", "scale_x": ROOT_SCALE, "scale_y": ROOT_SCALE}]
    for b in tpl["bones"]:
        par = b["parent"]
        pp = origin if par == "root" else j[par]
        bones.append({"name": b["name"], "parent": par,
                      "x": round((j[b["name"]][0] - pp[0]) * k, 2), "y": round((j[b["name"]][1] - pp[1]) * k, 2)})
    slots = []
    for p in tpl["parts"]:
        n = p["name"]
        if n not in crops:
            continue
        x0, y0, x1, y1 = crops[n]
        img = _resize(pix[n][y0:y1, x0:x1], k)
        files[f"rig/{n}.png"] = _png(img)
        jp = j[n]
        slots.append({"name": n, "bone": n, "image": f"rig/{n}.png",
                      "pivot": [round((jp[0] - x0) * k, 2), round((jp[1] - y0) * k, 2)]})

    def center(n):
        c = crops[n]
        return [(c[0] + c[2]) / 2, (c[1] + c[3]) / 2]

    anchors = {"overhead": {"bone": "head", "x": 0, "y": round((fy0 - j["head"][1]) * k - 16, 1)}}
    if "torso" in crops:
        c = center("torso")
        anchors["hit"] = {"bone": "torso", "x": round((c[0] - j["torso"][0]) * k, 1), "y": round((c[1] - j["torso"][1]) * k, 1)}
    else:
        anchors["hit"] = {"bone": "torso", "x": 0, "y": round(-0.2 * fig_h * k, 1)}
    if "weapon" in crops:
        c = crops["weapon"]
        anchors["projectile"] = {"bone": "weapon", "x": round(((c[0] + c[2]) / 2 - j["weapon"][0]) * k, 1),
                                 "y": round((c[1] - j["weapon"][1]) * k, 1)}
    else:
        anchors["projectile"] = {"bone": "weapon", "x": 0, "y": 0}

    bone_names = {b["name"] for b in bones}
    anims = None
    if existing and {b["name"] for b in existing.get("bones", [])} >= bone_names:
        anims = existing.get("animations")
        report["animations"] = "прежние анимации героя"
    if not anims and base_anims:
        anims = base_anims
        report["animations"] = "шаблонные (с героя той же роли)"
    if not anims:
        anims = DEFAULT_ANIMS
        report["animations"] = "простые по умолчанию"
    clean = {}
    for name, a in anims.items():
        a2 = dict(a)
        a2["bones"] = {b: v for b, v in a.get("bones", {}).items() if b in bone_names}
        clean[name] = a2
    if report["animations"] != "прежние анимации героя":
        clean = _anim_extras(tpl, clean)
    skel = {"format": "ufa-skeleton", "version": 1,
            "size": [round((fx1 - fx0) * k * ROOT_SCALE), round(height)],
            "bones": bones, "slots": slots, "anchors": anchors, "animations": clean}
    # Свои картинки скинов — сохраняем у тех же частей
    if existing:
        old = {s["name"]: s for s in existing.get("slots", [])}
        for s in slots:
            if old.get(s["name"], {}).get("skins"):
                s["skins"] = old[s["name"]]["skins"]
    return files, skel, report


def portrait_and_full(sid: str) -> dict[str, bytes]:
    """Портрет (голова) и полный арт из рисунка — по желанию при сборке."""
    src = load_rgba(session_dir(sid) / "source.png")
    x0, y0, x1, y1 = figure_bbox(src[:, :, 3])
    fig = Image.fromarray(src[y0:y1, x0:x1])
    full = Image.new("RGBA", (640, 800))
    k = min(600 / fig.width, 760 / fig.height)
    f2 = fig.resize((max(1, round(fig.width * k)), max(1, round(fig.height * k))), Image.LANCZOS)
    full.alpha_composite(f2, ((640 - f2.width) // 2, 800 - f2.height - 20))
    side = min(fig.width, int(fig.height * 0.38))
    cx = fig.width // 2
    head = fig.crop((max(0, cx - side // 2), 0, max(0, cx - side // 2) + side, side))
    portrait = head.resize((256, 256), Image.LANCZOS)
    return {"full.png": _png(full), "portrait.png": _png(portrait)}

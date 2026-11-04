"""Нарезка героя ИИ по подходу spine-animation-ai (см. NOTICE.md, лицензия PolyForm Noncommercial).

1. Gemini рисует «лист частей»: тот же персонаж, разобранный на отдельные части на белом фоне
   (скрытые места дорисованы).
2. Части выделяются как связные области (connected components).
3. Каждая часть ищется на исходном рисунке (SIFT + RANSAC; запасной — поиск по шаблону),
   получаем матрицу 2×3 для переноса части на холст исходника.
"""
from __future__ import annotations

import math

import cv2
import numpy as np

POSITIVE_PROMPT = (
    "A complete 2D game sprite sheet texture atlas for skeletal animation of the "
    "exact character in the reference image. The character is completely "
    "deconstructed into separated, isolated body parts. Separated individual "
    "parts laid out flatly: {parts}. Spread out with clear "
    "space between every single body part. No overlapping parts. Hidden areas of each part "
    "(covered by other parts in the reference) are fully drawn. Every part keeps the same size, "
    "orientation and angle as in the reference, the character faces right. Clean solid "
    "white background. CRITICAL: Maintain the exact same art style, exact same "
    "shading, exact face, and exact color palette as the reference image. "
    "Identical style match, 2D game asset, flat layout, character design sheet."
)

NEGATIVE_PROMPT = (
    "3D, realistic, altered style, different art style, different face, "
    "redesign, overlapping parts, connected limbs, full body standing, dynamic "
    "pose, background scenery, shadows, gradients on background, messy layout, "
    "missing limbs, merged layers, text, watermarks."
)


def prompt_for(part_texts: list[str]) -> str:
    return POSITIVE_PROMPT.format(parts="; ".join(part_texts)) + "\nNegative prompt: " + NEGATIVE_PROMPT


def segment_parts(atlas_rgb: np.ndarray, min_area_ratio: float = 0.0015, padding: int = 6,
                  bg_threshold: int = 240) -> list[dict]:
    """Части листа: [{"rgba": HxWx4, "box": (x, y, w, h)}] — по связным областям не-белых пикселей."""
    gray = cv2.cvtColor(atlas_rgb, cv2.COLOR_RGB2GRAY)
    _, mask = cv2.threshold(gray, bg_threshold, 255, cv2.THRESH_BINARY_INV)
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, k)
    num, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    h_img, w_img = mask.shape
    min_area = max(200, int(min_area_ratio * h_img * w_img))
    out = []
    for lid in range(1, num):
        x, y, w, h, area = stats[lid]
        if area < min_area:
            continue
        x1, y1 = max(x - padding, 0), max(y - padding, 0)
        x2, y2 = min(x + w + padding, w_img), min(y + h + padding, h_img)
        rgba = np.zeros((y2 - y1, x2 - x1, 4), np.uint8)
        rgba[:, :, :3] = atlas_rgb[y1:y2, x1:x2]
        rgba[:, :, 3] = np.where(labels[y1:y2, x1:x2] == lid, 255, 0).astype(np.uint8)
        out.append({"rgba": rgba, "box": (int(x1), int(y1), int(x2 - x1), int(y2 - y1))})
    return out


def _sift():
    return cv2.SIFT_create(nfeatures=0, contrastThreshold=0.02, edgeThreshold=20)


def sift_place(ref_gray, ref_kp, ref_des, part_rgba, sift, ratio=0.8, min_matches=4):
    """Место части на исходнике: {"M": 2×3, "scale", "rotation", "score"} или None."""
    part_gray = cv2.cvtColor(part_rgba[:, :, :3], cv2.COLOR_RGB2GRAY)
    part_mask = (part_rgba[:, :, 3] > 128).astype(np.uint8) * 255
    kp, des = sift.detectAndCompute(part_gray, part_mask)
    if des is None or len(kp) < 2 or ref_des is None:
        return None
    flann = cv2.FlannBasedMatcher(dict(algorithm=1, trees=5), dict(checks=150))
    try:
        matches = flann.knnMatch(des, ref_des, k=2)
    except cv2.error:
        return None
    good = [p[0] for p in matches if len(p) == 2 and p[0].distance < ratio * p[1].distance]
    if len(good) < min_matches:
        return None
    src = np.float32([kp[m.queryIdx].pt for m in good]).reshape(-1, 1, 2)
    dst = np.float32([ref_kp[m.trainIdx].pt for m in good]).reshape(-1, 1, 2)
    M, inl = cv2.estimateAffinePartial2D(src, dst, method=cv2.RANSAC, ransacReprojThreshold=5.0)
    if M is None or inl is None or int(inl.sum()) < min_matches:
        return None
    scale = math.sqrt(M[0, 0] ** 2 + M[1, 0] ** 2)
    rotation = math.degrees(math.atan2(M[1, 0], M[0, 0]))
    if not 0.3 <= scale <= 3.0 or abs(rotation) > 20:
        return None
    return {"M": M, "scale": scale, "rotation": rotation, "score": int(inl.sum()) / len(good), "method": "sift"}


def template_place(ref_rgb, ref_fg, part_rgba, scales):
    """Запасной поиск по шаблону (без поворота) — для мелких частей без особых точек."""
    ref_h, ref_w = ref_rgb.shape[:2]
    best = None
    for s in scales:
        sw, sh = max(1, int(part_rgba.shape[1] * s)), max(1, int(part_rgba.shape[0] * s))
        if sw >= ref_w - 2 or sh >= ref_h - 2:
            continue
        scaled = cv2.resize(part_rgba, (sw, sh), interpolation=cv2.INTER_AREA if s < 1 else cv2.INTER_LINEAR)
        mask = (scaled[:, :, 3] > 128).astype(np.uint8) * 255
        opaque = int(np.count_nonzero(mask))
        if opaque < 20:
            continue
        try:
            res = cv2.matchTemplate(ref_rgb, np.ascontiguousarray(scaled[:, :, :3]), cv2.TM_CCORR_NORMED, mask=mask)
        except cv2.error:
            continue
        _, val, _, loc = cv2.minMaxLoc(res)
        reg = ref_fg[loc[1]:loc[1] + sh, loc[0]:loc[0] + sw]
        fg_ratio = np.count_nonzero(reg[mask > 128] > 128) / max(1, opaque) if reg.shape == (sh, sw) else 0.0
        score = val * (0.3 + 0.7 * fg_ratio)
        if best is None or score > best["score"]:
            M = np.float32([[s, 0, loc[0]], [0, s, loc[1]]])
            best = {"M": M, "scale": s, "rotation": 0.0, "score": float(score), "method": "template"}
    return best


def place_parts(ref_rgba: np.ndarray, parts: list[dict]) -> list[dict | None]:
    """Для каждой части листа — её место на исходнике (или None)."""
    ref_rgb = np.ascontiguousarray(ref_rgba[:, :, :3])
    ref_fg = (ref_rgba[:, :, 3] > 128).astype(np.uint8) * 255
    ref_gray = cv2.cvtColor(ref_rgb, cv2.COLOR_RGB2GRAY)
    sift = _sift()
    ref_kp, ref_des = sift.detectAndCompute(ref_gray, None)
    found: list[dict | None] = [sift_place(ref_gray, ref_kp, ref_des, p["rgba"], sift) for p in parts]
    good = [f["scale"] for f in found if f]
    med = float(np.median(good)) if good else 1.0
    scales = tuple(med * f for f in (0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2))
    for i, f in enumerate(found):
        if f is None:
            t = template_place(ref_rgb, ref_fg, parts[i]["rgba"], scales)
            if t and t["score"] > 0.6:
                found[i] = t
    return found

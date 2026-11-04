"""Доступ к Gemini (Google AI Studio). Ключ — только из окружения (GEMINI_API_KEY в .env на VPS)."""
import json
import os
import urllib.error
import urllib.request

API = "https://generativelanguage.googleapis.com/v1beta"


def api_key() -> str:
    return os.environ.get("GEMINI_API_KEY", "").strip()


def _explain(code: int, body: str) -> tuple[str, str]:
    low = body.lower()
    if "location is not supported" in low or "user location" in low:
        return "region", "Google не обслуживает страну сервера (нужен прокси или другой ИИ)"
    if code in (400, 401, 403) and ("api key" in low or "api_key" in low or "permission" in low):
        return "bad_key", "ключ не принят Google (проверьте, что скопирован целиком)"
    if code == 429:
        return "quota", "ключ работает, но исчерпан лимит запросов"
    return "error", f"ответ Google: HTTP {code}"


def check(timeout: float = 15) -> dict:
    """Проверка доступа без траты лимита генерации: запрашивает список моделей.
    Ключ никогда не попадает в результат."""
    key = api_key()
    if not key:
        return {"ok": False, "status": "no_key", "message": "ключ не задан (GEMINI_API_KEY в .env)"}
    req = urllib.request.Request(API + "/models?pageSize=100", headers={"x-goog-api-key": key})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:2000]
        status, msg = _explain(e.code, body)
        return {"ok": False, "status": status, "message": msg}
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        return {"ok": False, "status": "network", "message": f"нет связи с Google: {type(e).__name__}"}
    names = [m.get("name", "").removeprefix("models/") for m in data.get("models", [])]
    image = [n for n in names if "image" in n]
    return {"ok": True, "status": "ok", "message": f"доступ есть, моделей: {len(names)}",
            "models": len(names), "image_models": image[:10]}


# --- Запросы для нарезки героя ----------------------------------------------------------------

IMAGE_MODELS = ("gemini-3.1-flash-image", "gemini-3.1-flash-image-preview", "gemini-2.5-flash-image",
                "gemini-3-pro-image")
TEXT_MODEL = "gemini-2.5-flash"


class GeminiError(Exception):
    pass


def _post(model: str, body: dict, timeout: float) -> dict:
    key = api_key()
    if not key:
        raise GeminiError("ключ Gemini не задан на сервере (GEMINI_API_KEY в .env)")
    req = urllib.request.Request(f"{API}/models/{model}:generateContent", data=json.dumps(body).encode("utf-8"),
                                 headers={"x-goog-api-key": key, "Content-Type": "application/json"}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        _, msg = _explain(e.code, e.read().decode("utf-8", "replace")[:2000])
        raise GeminiError(f"Gemini ({model}): {msg}") from None
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise GeminiError(f"нет связи с Gemini: {type(e).__name__}") from None


def _image_part(png: bytes) -> dict:
    import base64
    return {"inline_data": {"mime_type": "image/png", "data": base64.b64encode(png).decode("ascii")}}


def generate_image(prompt: str, png: bytes, timeout: float = 180) -> bytes:
    """Картинка по образцу. Пробует модели по очереди (какая доступна ключу)."""
    import base64
    last = None
    for model in IMAGE_MODELS:
        try:
            data = _post(model, {"contents": [{"role": "user", "parts": [{"text": prompt}, _image_part(png)]}],
                                 "generationConfig": {"responseModalities": ["IMAGE", "TEXT"]}}, timeout)
        except GeminiError as e:
            last = e
            if "HTTP 404" in str(e) or "HTTP 400" in str(e):
                continue
            raise
        for cand in data.get("candidates", []):
            for part in cand.get("content", {}).get("parts", []):
                inline = part.get("inlineData") or part.get("inline_data")
                if inline and inline.get("data"):
                    return base64.b64decode(inline["data"])
        last = GeminiError(f"Gemini ({model}) не вернул картинку")
    raise last or GeminiError("нет доступной модели Gemini для картинок")


def detect_boxes(png: bytes, labels: list[str], timeout: float = 90) -> list[dict]:
    """Подписи частей на листе: [{"label", "box": (x0, y0, x1, y1) в долях 0..1}]."""
    prompt = ("This is a sprite sheet of separated body parts of one character. Detect every separate part and "
              "label it with exactly one of: " + ", ".join(labels) + ". Return a JSON list of objects "
              '{"label": <label>, "box_2d": [ymin, xmin, ymax, xmax]} with coordinates normalized to 0-1000.')
    data = _post(TEXT_MODEL, {"contents": [{"role": "user", "parts": [{"text": prompt}, _image_part(png)]}],
                              "generationConfig": {"responseMimeType": "application/json", "temperature": 0}}, timeout)
    text = ""
    for cand in data.get("candidates", []):
        for part in cand.get("content", {}).get("parts", []):
            text += part.get("text", "")
    try:
        items = json.loads(text)
    except ValueError:
        return []
    out = []
    for it in items if isinstance(items, list) else []:
        try:
            y0, x0, y1, x1 = (float(v) / 1000 for v in it["box_2d"])
        except (KeyError, TypeError, ValueError):
            continue
        if it.get("label") in labels:
            out.append({"label": it["label"], "box": (x0, y0, x1, y1)})
    return out

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

"""Проверка здоровья сервера. Используется автодеплоем и Docker."""
from fastapi import APIRouter
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.config import get_settings
from app.content.releases import get_channel_release
from app.db import get_sessionmaker
from app.redis_client import get_redis

router = APIRouter()


@router.get("/health", tags=["service"])
async def health() -> JSONResponse:
    result: dict = {"status": "ok", "version": get_settings().git_sha}
    ok = True
    try:
        async with get_sessionmaker()() as session:
            await session.execute(text("SELECT 1"))
            live = await get_channel_release(session, "live")
            result["content_release"] = live.id if live else None
        result["database"] = "ok"
    except Exception as e:  # noqa: BLE001
        ok = False
        result["database"] = f"error: {type(e).__name__}"
    try:
        await get_redis().ping()
        result["redis"] = "ok"
    except Exception as e:  # noqa: BLE001
        ok = False
        result["redis"] = f"error: {type(e).__name__}"
    if not ok:
        result["status"] = "error"
    return JSONResponse(result, status_code=200 if ok else 503)

"""Точка входа API-сервера."""
import logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.api import admin, auth, battle, heroes, campaign, client, content, health
from app.content.validation import ContentError
from app.config import get_settings

settings = get_settings()
logging.basicConfig(
    level=settings.log_level,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)

app = FastAPI(
    title="UfaGame API",
    version=settings.git_sha,
    docs_url="/api/docs",
    openapi_url="/api/openapi.json",
    redoc_url=None,
    root_path=settings.path_prefix,
)

app.include_router(health.router)
app.include_router(content.router)
app.include_router(auth.router)
app.include_router(auth.me_router)
app.include_router(client.router)
app.include_router(battle.router)
app.include_router(heroes.router)
app.include_router(battle.ws_router)
app.include_router(campaign.router)
app.include_router(admin.router)


@app.exception_handler(ContentError)
async def _content_error(request: Request, exc: ContentError):
    return JSONResponse({"detail": {"message": "Контент не прошёл проверку", "errors": exc.messages[:200]}}, 422)

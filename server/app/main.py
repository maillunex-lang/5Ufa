"""Точка входа API-сервера."""
import logging

from fastapi import FastAPI

from app.api import auth, client, content, health
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

"""Общая настройка тестов: SQLite вместо PostgreSQL и fakeredis вместо Redis."""
import os
import sys
from pathlib import Path

import pytest
import pytest_asyncio

SERVER_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = SERVER_DIR.parent
sys.path.insert(0, str(SERVER_DIR))


@pytest.fixture(scope="session", autouse=True)
def _env(tmp_path_factory):
    tmp = tmp_path_factory.mktemp("srv")
    os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{tmp / 'test.db'}"
    os.environ["CONTENT_STORE_DIR"] = str(tmp / "store")
    os.environ["SHARED_DIR"] = str(REPO_ROOT / "shared")
    os.environ["BASE_CONTENT_DIR"] = str(REPO_ROOT / "content")
    from app.config import get_settings
    get_settings.cache_clear()
    yield


@pytest_asyncio.fixture
async def db():
    from app import models  # noqa: F401
    from app.db import Base, get_engine, reset_engine
    reset_engine()
    engine = get_engine()
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield
    await engine.dispose()


@pytest_asyncio.fixture
async def client(db):
    import fakeredis
    import fakeredis.aioredis
    from httpx import ASGITransport, AsyncClient

    from app.main import app
    from app.redis_client import set_redis
    set_redis(fakeredis.aioredis.FakeRedis(server=fakeredis.FakeServer(), decode_responses=True))  # свой Redis на каждый тест
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        yield c

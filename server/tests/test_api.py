import shutil

from app.config import get_settings
from app.content.releases import import_directory, publish
from app.db import get_sessionmaker


async def test_health(client):
    r = await client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok" and body["database"] == "ok" and body["redis"] == "ok"


async def test_manifest_not_published(client):
    r = await client.get("/api/v1/content/manifest")
    assert r.status_code == 503


async def test_manifest_publish_rollback(client, tmp_path):
    content = tmp_path / "content"
    shutil.copytree(get_settings().base_content_dir, content)
    async with get_sessionmaker()() as s:
        rel1, created = await import_directory(s, content)
        assert created
        await publish(s, rel1.id, "live")
        again, created2 = await import_directory(s, content)
        assert not created2 and again.id == rel1.id
        await s.commit()

    r = await client.get("/api/v1/content/manifest")
    assert r.status_code == 200
    m = r.json()
    assert m["release"] == rel1.id and m["base_url"] == "/content/files/"
    etag = r.headers["etag"]
    r304 = await client.get("/api/v1/content/manifest", headers={"If-None-Match": etag})
    assert r304.status_code == 304

    # Новый релиз в канал test, live остаётся старым
    (content / "localization/ru.json").write_text(
        '{"language": "ru", "strings": {"ui.button.play": "Вперёд"}}', "utf-8")
    async with get_sessionmaker()() as s:
        rel2, _ = await import_directory(s, content, source="manual")
        await publish(s, rel2.id, "test")
        await s.commit()
    assert (await client.get("/api/v1/content/manifest")).json()["release"] == rel1.id
    assert (await client.get("/api/v1/content/manifest?channel=test")).json()["release"] == rel2.id

    # Публикация и откат
    async with get_sessionmaker()() as s:
        await publish(s, rel2.id, "live")
        await s.commit()
    assert (await client.get("/api/v1/content/manifest")).json()["release"] == rel2.id
    async with get_sessionmaker()() as s:
        await publish(s, rel1.id, "live")
        await s.commit()
    assert (await client.get("/api/v1/content/manifest")).json()["release"] == rel1.id


async def test_path_prefix(db, monkeypatch, tmp_path):
    """Сервер за внешним прокси на /games/server: base_url с префиксом, маршруты без него."""
    import importlib

    import fakeredis.aioredis
    from httpx import ASGITransport, AsyncClient

    from app.config import get_settings
    from app.redis_client import set_redis
    monkeypatch.setenv("PUBLIC_PATH_PREFIX", "/games/server/")
    get_settings.cache_clear()
    try:
        import app.main
        importlib.reload(app.main)
        set_redis(fakeredis.aioredis.FakeRedis(decode_responses=True))
        content = tmp_path / "content"
        shutil.copytree(get_settings().base_content_dir, content)
        async with get_sessionmaker()() as s:
            rel, _ = await import_directory(s, content)
            await publish(s, rel.id, "live")
            await s.commit()
        async with AsyncClient(transport=ASGITransport(app=app.main.app), base_url="http://test") as c:
            assert (await c.get("/health")).status_code == 200
            m = (await c.get("/api/v1/content/manifest")).json()
            assert m["base_url"] == "/games/server/content/files/"
            spec = (await c.get("/api/openapi.json")).json()
            assert spec["servers"][0]["url"] == "/games/server"
    finally:
        monkeypatch.delenv("PUBLIC_PATH_PREFIX")
        get_settings.cache_clear()
        importlib.reload(app.main)

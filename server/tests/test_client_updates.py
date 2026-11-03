import base64

TOKEN = "test-upload-token"


def _apk(n=4096):
    return b"PK\x03\x04" + b"x" * n


async def test_updates_flow(client, monkeypatch):
    from app.config import get_settings
    monkeypatch.setattr(get_settings(), "client_upload_token", TOKEN)

    r = await client.get("/api/v1/client/latest?code=1")
    assert r.json() == {"update_available": False, "required": False, "latest": None}

    # Без токена / с неверным токеном — отказ
    r = await client.put("/api/v1/client/releases/5?version_name=0.1.5", content=_apk())
    assert r.status_code == 403
    r = await client.put("/api/v1/client/releases/5?version_name=0.1.5", content=_apk(),
                         headers={"X-Upload-Token": "wrong"})
    assert r.status_code == 403
    # Не APK
    r = await client.put("/api/v1/client/releases/5?version_name=0.1.5", content=b"hello" * 500,
                         headers={"X-Upload-Token": TOKEN})
    assert r.status_code == 422

    notes = base64.b64encode("Новые герои".encode()).decode()
    r = await client.put("/api/v1/client/releases/5?version_name=0.1.5", content=_apk(),
                         headers={"X-Upload-Token": TOKEN, "X-Notes": notes})
    assert r.status_code == 200, r.text
    rel = r.json()["release"]
    assert rel["notes"] == "Новые герои" and rel["url"].startswith("/content/files/")
    # Повторная загрузка того же кода — конфликт
    r = await client.put("/api/v1/client/releases/5?version_name=0.1.5", content=_apk(),
                         headers={"X-Upload-Token": TOKEN})
    assert r.status_code == 409

    r = (await client.get("/api/v1/client/latest?code=3")).json()
    assert r["update_available"] and not r["required"] and r["latest"]["version_code"] == 5
    assert (await client.get("/api/v1/client/latest?code=5")).json()["update_available"] is False

    # Обязательная версия 6
    r = await client.put("/api/v1/client/releases/6?version_name=0.1.6&mandatory=true", content=_apk(5000),
                         headers={"X-Upload-Token": TOKEN})
    assert r.status_code == 200
    r = (await client.get("/api/v1/client/latest?code=5")).json()
    assert r["required"] and r["latest"]["version_code"] == 6

    # Файл реально лежит в хранилище и совпадает по SHA-256
    import hashlib
    from app.content.releases import get_store
    assert hashlib.sha256(get_store().path_for(r["latest"]["sha256"]).read_bytes()).hexdigest() == r["latest"]["sha256"]


async def test_upload_disabled_without_token(client):
    r = await client.put("/api/v1/client/releases/9?version_name=0.1.9", content=_apk(),
                         headers={"X-Upload-Token": ""})
    assert r.status_code == 403


async def test_upload_limit_enforced_without_large_fixture(client, monkeypatch):
    from app.config import get_settings
    monkeypatch.setattr(get_settings(), "client_upload_token", TOKEN)
    monkeypatch.setattr(get_settings(), "client_max_apk_mb", 1)
    headers = {"X-Upload-Token": TOKEN}
    accepted = await client.put("/api/v1/client/releases/10?version_name=0.1.10",
                                content=_apk(1024 * 1024 - 4), headers=headers)
    assert accepted.status_code == 200
    rejected = await client.put("/api/v1/client/releases/11?version_name=0.1.11",
                                content=_apk(1024 * 1024 - 3), headers=headers)
    assert rejected.status_code == 413

from app.auth.security import hash_password, verify_password


def test_password_hash():
    h = hash_password("secret123")
    assert verify_password("secret123", h)
    assert not verify_password("secret124", h)
    assert not verify_password("x", None)


async def test_guest_link_login_flow(client):
    r = await client.post("/api/v1/auth/guest", json={"device_id": "device-aaaa-1", "client_version": "0.1.0"})
    assert r.status_code == 200, r.text
    g = r.json()
    assert g["player"]["is_guest"] and g["player"]["display_name"].startswith("Путник-")
    hdr = {"Authorization": f"Bearer {g['access_token']}"}

    # Тот же device_id -> тот же гость
    again = (await client.post("/api/v1/auth/guest", json={"device_id": "device-aaaa-1"})).json()
    assert again["player"]["id"] == g["player"]["id"]

    me = await client.get("/api/v1/me", headers=hdr)
    assert me.status_code == 200 and me.json()["player"]["number"] == g["player"]["number"]
    assert (await client.get("/api/v1/me")).status_code == 401

    # Плохой пароль / почта — понятные ошибки
    r = await client.post("/api/v1/auth/link-email", headers=hdr, json={"email": "a@b.ru", "password": "short"})
    assert r.status_code == 422 and "8 символов" in r.json()["detail"]
    r = await client.post("/api/v1/auth/link-email", headers=hdr, json={"email": "плохо", "password": "abcd1234"})
    assert r.status_code == 422 and "почты" in r.json()["detail"]

    r = await client.post("/api/v1/auth/link-email", headers=hdr, json={"email": "Hero@Mail.ru", "password": "abcd1234"})
    assert r.status_code == 200, r.text
    assert r.json()["player"]["email"] == "hero@mail.ru" and not r.json()["player"]["is_guest"]

    # Вторая привязка той же почты другим гостем — 409
    g2 = (await client.post("/api/v1/auth/guest", json={"device_id": "device-bbbb-2"})).json()
    r = await client.post("/api/v1/auth/link-email", headers={"Authorization": f"Bearer {g2['access_token']}"},
                          json={"email": "hero@mail.ru", "password": "abcd1234"})
    assert r.status_code == 409

    # Вход на «другом телефоне»
    r = await client.post("/api/v1/auth/login", json={"device_id": "device-cccc-3", "email": "hero@mail.ru", "password": "abcd1234"})
    assert r.status_code == 200 and r.json()["player"]["id"] == g["player"]["id"]
    r = await client.post("/api/v1/auth/login", json={"device_id": "device-cccc-3", "email": "hero@mail.ru", "password": "wrong999"})
    assert r.status_code == 401 and "Неверная" in r.json()["detail"]


async def test_refresh_rotation(client):
    g = (await client.post("/api/v1/auth/guest", json={"device_id": "device-rrrr-1"})).json()
    r = await client.post("/api/v1/auth/refresh", json={"refresh_token": g["refresh_token"]})
    assert r.status_code == 200
    new = r.json()
    assert new["refresh_token"] != g["refresh_token"]
    # старый токен больше не работает
    assert (await client.post("/api/v1/auth/refresh", json={"refresh_token": g["refresh_token"]})).status_code == 401
    assert (await client.post("/api/v1/auth/logout", json={"refresh_token": new["refresh_token"]})).status_code == 200
    assert (await client.post("/api/v1/auth/refresh", json={"refresh_token": new["refresh_token"]})).status_code == 401


async def test_login_rate_limit(client):
    g = (await client.post("/api/v1/auth/guest", json={"device_id": "device-limit-1"})).json()
    await client.post("/api/v1/auth/link-email", headers={"Authorization": f"Bearer {g['access_token']}"},
                      json={"email": "lim@test.ru", "password": "abcd1234"})
    codes = []
    for _ in range(7):
        r = await client.post("/api/v1/auth/login", json={"device_id": "device-limit-1", "email": "lim@test.ru", "password": "bad00000"})
        codes.append(r.status_code)
    assert codes[:5] == [401] * 5 and codes[5] == 429
    assert "Слишком много попыток" in r.json()["detail"]


async def test_ban(client):
    from datetime import datetime, timedelta, timezone
    import uuid
    from app.db import get_sessionmaker
    from app.models import Player
    g = (await client.post("/api/v1/auth/guest", json={"device_id": "device-ban-1"})).json()
    async with get_sessionmaker()() as s:
        p = await s.get(Player, uuid.UUID(g["player"]["id"]))
        p.banned_until = datetime.now(timezone.utc) + timedelta(days=1)
        p.ban_reason = "тест"
        await s.commit()
    r = await client.get("/api/v1/me", headers={"Authorization": f"Bearer {g['access_token']}"})
    assert r.status_code == 403 and "заблокирован" in r.json()["detail"]

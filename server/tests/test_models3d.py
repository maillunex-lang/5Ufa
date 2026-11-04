import io
import json
import struct
import zipfile

import pytest
from app.models3d.inspect_glb import ModelError, inspect_glb
from app.api.admin_models3d import unpack
from tests.test_admin import admin_headers, make_admin
from tests.test_progression import published  # noqa: F401


def glb(doc, blob=b""):
    raw = json.dumps({"asset": {"version": "2.0"}, **doc}).encode()
    raw += b" " * (-len(raw) % 4)
    blob += b"\0" * (-len(blob) % 4)
    size = 20 + len(raw) + (8 + len(blob) if blob else 0)
    return struct.pack("<4sII", b"glTF", 2, size) + struct.pack("<I4s", len(raw), b"JSON") + raw + (struct.pack("<I4s", len(blob), b"BIN\0") + blob if blob else b"")


def model(count=3):
    positions = bytes(count * 12)
    times = struct.pack("<2f", 0, 1)
    translations = bytes(24)
    blob = positions + times + translations
    doc = {"buffers": [{"byteLength": len(blob)}],
           "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(positions)},
                           {"buffer": 0, "byteOffset": len(positions), "byteLength": len(times)},
                           {"buffer": 0, "byteOffset": len(positions) + len(times), "byteLength": len(translations)}],
           "accessors": [{"count": count, "bufferView": 0, "componentType": 5126, "type": "VEC3"},
                         {"count": 2, "bufferView": 1, "componentType": 5126, "type": "SCALAR"},
                         {"count": 2, "bufferView": 2, "componentType": 5126, "type": "VEC3"}],
           "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
           "nodes": [{"name": "hips", "mesh": 0}], "skins": [{"joints": [0]}],
           "animations": [{"name": "Walk", "samplers": [{"input": 1, "output": 2}],
                           "channels": [{"sampler": 0, "target": {"node": 0, "path": "translation"}}]}]}
    return glb(doc, blob)


def test_inspect_mesh_and_warning():
    report = inspect_glb(model(30003))
    assert report["triangles"] == 10001 and report["bones"] == ["hips"] and report["animations"] == ["Walk"]
    assert any("10 000" in w for w in report["warnings"])
    with pytest.raises(ModelError):
        inspect_glb(b"glTFbroken")
    with pytest.raises(ModelError):
        inspect_glb(glb({"buffers": [{"uri": "https://example.com/file", "byteLength": 1}]}))


def test_zip_rejects_path_escape_and_other_formats():
    def archive(name, data):
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w") as z:
            z.writestr(name, data)
        return buf.getvalue()
    with pytest.raises(ModelError):
        unpack(archive("../model.glb", model()))
    with pytest.raises(ModelError):
        unpack(archive("readme.txt", b"hi"))
    assert unpack(archive("folder/hero.glb", model()))[0][1] == model()


def test_texture_size_and_invalid_buffer():
    from PIL import Image
    image = io.BytesIO()
    Image.new("RGB", (2048, 2)).save(image, format="PNG")
    raw = image.getvalue()
    report = inspect_glb(glb({"buffers": [{"byteLength": len(raw)}],
                              "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(raw)}],
                              "images": [{"bufferView": 0, "mimeType": "image/png"}]}, raw))
    assert report["textures"][0]["width"] == 2048
    assert any("1024" in warning for warning in report["warnings"])
    broken = glb({"buffers": [{"byteLength": 4}], "bufferViews": [{"buffer": 0, "byteLength": 999}],
                  "images": [{"bufferView": 0, "mimeType": "image/png"}]}, b"1234")
    with pytest.raises(ModelError):
        inspect_glb(broken)


async def test_upload_to_draft_and_publish(published):
    client = published
    await make_admin()
    headers = await admin_headers(client)
    endpoint = "/api/v1/admin/models3d/ural_batyr/upload"
    assert (await client.post(endpoint, content=model())).status_code == 401
    result = await client.post(endpoint, headers=headers, content=model())
    assert result.status_code == 200, result.text
    report = result.json()["files"][0]
    assert report["bones"] == ["hips"] and report["triangles"] == 1
    path = report["path"]
    assert (await client.get("/api/v1/admin/files", params={"path": path}, headers=headers)).content == model()
    assert (await client.get("/api/v1/admin/models3d/ural_batyr/inspect", params={"path": path}, headers=headers)).status_code == 200
    model_config = {"file": path, "scale": 1.0, "height": 0, "rotation_degrees": [0, 0, 0],
                    "animations": {"walk": {"file": path, "clip": "Walk", "impact_ms": 500}},
                    "anchors": {"hit": {"bone": "hips", "offset": [0, 0, 0]}}}
    save = await client.put("/api/v1/admin/models3d/ural_batyr/config", headers=headers,
                            json={"model": model_config})
    assert save.status_code == 200, save.text
    bad_config = {**model_config, "file": "heroes/humai/models3d/other.glb"}
    assert (await client.put("/api/v1/admin/models3d/ural_batyr/config", headers=headers,
                             json={"model": bad_config})).status_code == 422
    assert (await client.put("/api/v1/admin/models3d/ural_batyr/config", headers=headers,
                             json={"model": {**model_config, "animations": {"walk": {"file": path, "clip": "absent"}}}})).status_code == 422
    other = {**model_config, "file": "heroes/ural_batyr/models3d/missing.glb"}
    hero = (await client.get("/api/v1/admin/sections/heroes/objects/ural_batyr", headers=headers)).json()["data"]
    hero["model_3d"] = other
    raw_save = await client.put("/api/v1/admin/sections/heroes/objects/ural_batyr", headers=headers, json={"data": hero})
    assert raw_save.status_code == 200
    blocked = await client.post("/api/v1/admin/draft/test", headers=headers, json={"comment": "ошибка"})
    assert blocked.status_code == 422
    assert (await client.put("/api/v1/admin/models3d/ural_batyr/config", headers=headers,
                            json={"model": model_config})).status_code == 200
    released = await client.post("/api/v1/admin/draft/test", headers=headers, json={"comment": "3D"})
    assert released.status_code == 200, released.text
    denied = await client.post(endpoint, headers=headers, content=b"bad")
    assert denied.status_code == 422


async def test_zip_skin_upload(published):
    client = published
    await make_admin()
    headers = await admin_headers(client)
    create = await client.post("/api/v1/admin/heroes/ural_batyr/skins", headers=headers,
                               json={"skin": "winter", "name": "Зимний", "free": False})
    assert create.status_code == 200, create.text
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        archive.writestr("model.glb", model())
        archive.writestr("animation.glb", model(6))
    upload = await client.post("/api/v1/admin/models3d/ural_batyr/upload?skin=winter", headers=headers, content=output.getvalue())
    assert upload.status_code == 200, upload.text
    files = upload.json()["files"]
    assert len(files) == 2 and all("/skins/winter/models3d/" in f["path"] for f in files)
    config = {"file": files[0]["path"], "animations": {"walk": {"file": files[1]["path"], "clip": "Walk"}},
              "anchors": {"hit": {"bone": "@root", "offset": [0, 1, 0]}}}
    save = await client.put("/api/v1/admin/models3d/ural_batyr/config", headers=headers,
                            json={"skin": "winter", "model": config})
    assert save.status_code == 200, save.text
    hero = (await client.get("/api/v1/admin/sections/heroes/objects/ural_batyr", headers=headers)).json()["data"]
    skin = next(s for s in hero["skins"] if s["id"] == "winter")
    assert skin["model_3d"] == config
    test_release = await client.post("/api/v1/admin/draft/test", headers=headers, json={"comment": "скин 3D"})
    assert test_release.status_code == 200, test_release.text


def test_repeated_mesh_is_counted_per_instance_and_sparse_draco_rejected():
    positions = bytes(36)
    blob = positions
    doc = {"buffers": [{"byteLength": len(blob)}],
           "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(positions)}],
           "accessors": [{"count": 3, "bufferView": 0, "componentType": 5126, "type": "VEC3"}],
           "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
           "nodes": [{"name": "a", "mesh": 0}, {"name": "b", "mesh": 0}]}
    report = inspect_glb(glb(doc, blob))
    assert report["meshes"] == 1 and report["mesh_instances"] == 2
    assert report["unique_triangles"] == 1 and report["triangles"] == 2
    assert any("несколько раз" in warning for warning in report["warnings"])
    with pytest.raises(ModelError, match="Разреженные"):
        inspect_glb(glb({"accessors": [{"count": 1, "componentType": 5126, "type": "SCALAR", "sparse": {"count": 1}}]}))
    with pytest.raises(ModelError, match="Draco"):
        inspect_glb(glb({"extensionsUsed": ["KHR_draco_mesh_compression"]}))


def test_zip_caps_real_size_and_rejects_escape_and_encryption():
    payload = b"A" * 3000
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("model.glb", payload)
    with pytest.raises(ModelError):
        unpack(buf.getvalue(), max_bytes=1000)
    # Заголовок врёт о размере. Нельзя ни прочитать больше лимита, ни поверить крошечному file_size.
    raw = bytearray(buf.getvalue())
    struct.pack_into("<I", raw, 22, 10)
    central = raw.find(b"PK\x01\x02")
    struct.pack_into("<I", raw, central + 24, 10)
    try:
        files = unpack(bytes(raw), max_bytes=1000)
    except ModelError:
        files = []
    assert all(len(item) <= 1000 for _, item in files)
    encrypted = bytearray(buf.getvalue())
    struct.pack_into("<H", encrypted, 6, encrypted[6] | 1)
    central = encrypted.find(b"PK\x01\x02")
    struct.pack_into("<H", encrypted, central + 8, encrypted[central + 8] | 1)
    with pytest.raises(ModelError, match="Зашифрованный"):
        unpack(bytes(encrypted))
    with pytest.raises(ModelError):
        unpack(b"PK\x03\x04not-a-zip")


def test_model_path_cannot_escape_content_tree(tmp_path):
    from app.content.builder import _validate_hero_models
    content = tmp_path / "content"
    own = content / "heroes" / "ural_batyr" / "models3d"
    other = content / "heroes" / "humai" / "models3d"
    own.mkdir(parents=True)
    other.mkdir(parents=True)
    (own / "body.glb").write_bytes(model())
    (other / "real.glb").write_bytes(model())
    (tmp_path / "outside.glb").write_bytes(model())
    hero_path = "heroes/ural_batyr/hero.json"
    escaped = {"model_3d": {"file": "heroes/ural_batyr/../humai/models3d/real.glb"}}
    outside = {"model_3d": {"file": "heroes/ural_batyr/../../outside.glb"}}
    assert _validate_hero_models(content, hero_path, escaped)
    assert _validate_hero_models(content, hero_path, outside)
    missing = {"model_3d": {"file": "heroes/ural_batyr/models3d/missing.glb"}}
    assert _validate_hero_models(content, hero_path, missing)
    static = glb({"buffers": [{"byteLength": 36}],
                   "bufferViews": [{"buffer": 0, "byteLength": 36}],
                   "accessors": [{"count": 3, "bufferView": 0, "componentType": 5126, "type": "VEC3"}],
                   "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
                   "nodes": [{"mesh": 0}]}, bytes(36))
    (own / "static.glb").write_bytes(static)
    root_only = {"model_3d": {"file": "heroes/ural_batyr/models3d/static.glb",
                              "anchors": {"hit": {"bone": "@root", "offset": [0, 1, 0]}}}}
    assert _validate_hero_models(content, hero_path, root_only) == []
    bad_bone = {"model_3d": {"file": "heroes/ural_batyr/models3d/static.glb",
                             "anchors": {"hit": {"bone": "hips", "offset": [0, 0, 0]}}}}
    assert _validate_hero_models(content, hero_path, bad_bone)
    good = {"model_3d": {"file": "heroes/ural_batyr/models3d/body.glb",
                         "anchors": {"hit": {"bone": "hips", "offset": [0, 0, 0]}}}}
    assert _validate_hero_models(content, hero_path, good) == []


async def test_bad_zip_does_not_leave_partial_draft(published):
    client = published
    await make_admin()
    headers = await admin_headers(client)
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as archive:
        archive.writestr("good.glb", model())
        archive.writestr("bad.glb", b"glTF" + b"\x00" * 32)
    upload = await client.post("/api/v1/admin/models3d/ural_batyr/upload", headers=headers, content=buf.getvalue())
    assert upload.status_code == 422, upload.text
    draft = (await client.get("/api/v1/admin/draft", headers=headers)).json()
    assert all("models3d" not in item["path"] for item in draft["changes"])


async def test_patch_and_form_cannot_publish_missing_model(published):
    from tests.test_admin import zip_of
    client = published
    await make_admin()
    headers = await admin_headers(client)
    hero = (await client.get("/api/v1/admin/sections/heroes/objects/ural_batyr", headers=headers)).json()["data"]
    assert "model_3d" not in hero
    # Форма и «Как JSON» пишут в один и тот же метод. Ссылки проверяются при сборке релиза.
    hero["model_3d"] = {"file": "heroes/ural_batyr/models3d/missing.glb"}
    saved = await client.put("/api/v1/admin/sections/heroes/objects/ural_batyr", headers=headers, json={"data": hero})
    assert saved.status_code == 200, saved.text
    blocked = await client.post("/api/v1/admin/draft/test", headers=headers, json={"comment": "форма"})
    assert blocked.status_code == 422
    await client.post("/api/v1/admin/draft/revert", headers=headers, json={})
    patch = {"id": "missing-model", "format_version": 1, "section": "heroes", "description": "нет glb",
             "operations": [{"op": "update", "id": "ural_batyr",
                             "data": {"model_3d": {"file": "heroes/ural_batyr/../humai/models3d/x.glb"}}}]}
    applied = await client.post("/api/v1/admin/patches/apply", headers=headers, content=zip_of(patch))
    assert applied.status_code == 200, applied.text
    blocked_patch = await client.post("/api/v1/admin/draft/test", headers=headers, json={"comment": "патч"})
    assert blocked_patch.status_code == 422
    await client.post("/api/v1/admin/draft/revert", headers=headers, json={})
    path = "heroes/ural_batyr/models3d/pilot.glb"
    ok_patch = {"id": "pilot-model", "format_version": 1, "section": "heroes", "description": "glb",
                "operations": [{"op": "update", "id": "ural_batyr", "files": [path],
                                "data": {"model_3d": {"file": path, "anchors": {"hit": {"bone": "@root", "offset": [0, 0, 0]}}}}}]}
    applied_ok = await client.post("/api/v1/admin/patches/apply", headers=headers, content=zip_of(ok_patch, {path: model()}))
    assert applied_ok.status_code == 200, applied_ok.text
    released = await client.post("/api/v1/admin/draft/test", headers=headers, json={"comment": "патч с моделью"})
    assert released.status_code == 200, released.text
    again = (await client.get("/api/v1/admin/sections/heroes/objects/ural_batyr", headers=headers)).json()["data"]
    assert again["model_3d"]["file"] == path and again["model_3d"]["anchors"]["hit"]["bone"] == "@root"


def test_oversize_names_file_size_and_limit(monkeypatch):
    import app.models3d.inspect_glb as glbmod
    monkeypatch.setattr(glbmod, "MAX_GLB_BYTES", 1024 * 1024)
    with pytest.raises(ModelError, match=r"файл 2 МиБ, предел 1 МиБ"):
        glbmod.inspect_glb(b"x" * (2 * 1024 * 1024))
    assert glbmod.size_limit_message(86 * 1024 * 1024 + 410 * 1024, 200 * 1024 * 1024) == "файл 86.5 МиБ, предел 200 МиБ"


async def test_upload_over_limit_reports_size(published, monkeypatch):
    import app.api.admin_models3d as api
    monkeypatch.setattr(api, "MAX_GLB_BYTES", 1024 * 1024)
    client = published
    await make_admin()
    headers = await admin_headers(client)
    body = b"x" * (2 * 1024 * 1024)
    upload = await client.post("/api/v1/admin/models3d/ural_batyr/upload", headers=headers, content=body)
    assert upload.status_code == 413
    assert upload.json()["detail"] == "файл 2 МиБ, предел 1 МиБ"



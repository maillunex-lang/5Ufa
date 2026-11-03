import json
import shutil
from pathlib import Path

import pytest

from app.config import get_settings
from app.content.builder import build_manifest
from app.content.store import ContentStore
from app.content.validation import ContentError, get_schema_registry, glob_to_regex


def test_glob():
    assert glob_to_regex("ui/**").match("ui/a/b.png")
    assert glob_to_regex("localization/*.json").match("localization/ru.json")
    assert not glob_to_regex("localization/*.json").match("localization/x/ru.json")
    assert glob_to_regex("**/*.png").match("a.png")


def test_base_content_is_valid():
    result = build_manifest(get_settings().base_content_dir, None, get_schema_registry())
    ids = [p["id"] for p in result.manifest["packages"]]
    assert ids[0] == "core"
    assert {"core", "tutorial", "chapter_1", "chapter_2"} <= set(ids)
    assert result.files_count > 0
    # Манифест соответствует собственной схеме (после добавления полей ответа)
    reg = get_schema_registry()
    full = {**result.manifest, "release": 1, "channel": "live", "base_url": "/content/files/"}
    assert reg.validate(full, "manifest.schema.json", "manifest") == []


def _copy_content(tmp_path: Path) -> Path:
    dst = tmp_path / "content"
    shutil.copytree(get_settings().base_content_dir, dst)
    return dst


def test_schema_errors_are_russian(tmp_path):
    d = _copy_content(tmp_path)
    (d / "config/game_settings.json").write_text(json.dumps({"game_name": "", "languages": ["ru"]}), "utf-8")
    with pytest.raises(ContentError) as e:
        build_manifest(d, None, get_schema_registry())
    text = str(e.value)
    assert "default_language" in text and "обязательное" in text
    assert "слишком короткий" in text


def test_unassigned_and_bad_files(tmp_path):
    d = _copy_content(tmp_path)
    (d / "stray").mkdir()
    (d / "stray/x.png").write_bytes(b"x")
    (d / "ui/virus.exe").write_bytes(b"x")
    (d / "ui/broken.json").write_text("{oops", "utf-8")
    with pytest.raises(ContentError) as e:
        build_manifest(d, None, get_schema_registry())
    msgs = e.value.messages
    assert any("stray/x.png" in m and "ни в один пакет" in m for m in msgs)
    assert any("virus.exe" in m and "неподдерживаемый" in m for m in msgs)
    assert any("broken.json" in m and "ошибка JSON" in m for m in msgs)


def test_store_and_change_detection(tmp_path):
    d = _copy_content(tmp_path)
    store = ContentStore(tmp_path / "store")
    a = build_manifest(d, store, get_schema_registry())
    for p in a.manifest["packages"]:
        for f in p["files"]:
            assert store.path_for(f["sha256"]).stat().st_size == f["size"]
    # Меняем один файл — меняется только версия его пакета
    (d / "campaign/chapter_2/chapter.json").write_text('{"id": "chapter_2", "stages": [1]}', "utf-8")
    b = build_manifest(d, store, get_schema_registry())
    va = {p["id"]: p["version"] for p in a.manifest["packages"]}
    vb = {p["id"]: p["version"] for p in b.manifest["packages"]}
    assert va["chapter_2"] != vb["chapter_2"]
    assert all(va[k] == vb[k] for k in va if k != "chapter_2")
    assert a.content_hash != b.content_hash


def test_all_schemas_are_valid():
    from jsonschema import Draft202012Validator
    reg = get_schema_registry()
    for name, schema in reg.schemas.items():
        Draft202012Validator.check_schema(schema)
    example = {
        "id": "heroes-2026-11-batch1", "format_version": 1, "section": "heroes",
        "description": "пример", "operations": [
            {"op": "update", "id": "hero_ural_batyr", "data": {"x": 1},
             "files": ["heroes/hero_ural_batyr/portrait.png"]},
            {"op": "delete", "id": "hero_test_dummy"},
        ],
    }
    assert reg.validate(example, "patch.schema.json", "patch.json") == []
    bad = {**example, "operations": [{"op": "add", "id": "hero_x"}]}
    assert any("data" in m for m in reg.validate(bad, "patch.schema.json", "patch.json"))

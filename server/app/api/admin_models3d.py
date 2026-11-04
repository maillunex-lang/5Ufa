"""Загрузка GLB героя в общий черновик. Файлы архива не извлекаются на диск по своим именам."""
from __future__ import annotations

import hashlib
import io
import posixpath
import re
import zipfile
import zlib
from pathlib import PurePosixPath

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.admin import draft as drf
from app.admin.security import audit, require_role
from app.content.validation import ContentError
from app.db import get_session
from app.models import AdminUser
from app.models3d.inspect_glb import MAX_GLB_BYTES, ModelError, inspect_glb, require_owned_model_path

router = APIRouter(prefix="/api/v1/admin/models3d", tags=["admin"])
editor = require_role("editor")
ID = re.compile(r"^[a-z][a-z0-9_]{0,63}$")
INSPECT_PATH = re.compile(
    r"^heroes/[a-z][a-z0-9_]{0,63}(?:/skins/[a-z][a-z0-9_]{0,63})?/models3d/[a-z0-9][a-z0-9_.-]{0,180}\.glb$"
)
MAX_FILES = 16


class ModelConfigIn(BaseModel):
    skin: str = Field(default="", max_length=64)
    model: dict


def _prefix(hero_id: str, skin: str) -> str:
    return f"heroes/{hero_id}/" + (f"skins/{skin}/" if skin else "") + "models3d/"


@router.put("/{hero_id}/config")
async def save_config(hero_id: str, body: ModelConfigIn, request: Request,
                      admin: AdminUser = Depends(editor), session: AsyncSession = Depends(get_session)):
    if not ID.fullmatch(hero_id) or (body.skin and not ID.fullmatch(body.skin)):
        raise HTTPException(422, "Некорректный идентификатор героя или скина")
    ws = await drf.workspace(session)
    hero_path = f"heroes/{hero_id}/hero.json"
    if not ws.exists(hero_path):
        raise HTTPException(404, "Герой не найден")
    hero = ws.read_json(hero_path)
    target = hero
    if body.skin:
        target = next((s for s in hero.get("skins", []) if s.get("id") == body.skin), None)
        if target is None:
            raise HTTPException(404, "Скин не найден")
    target["model_3d"] = body.model
    try:
        # Сначала схема, затем файловые ссылки; некорректный ввод не меняет черновик.
        from app.content.validation import get_schema_registry
        errors = get_schema_registry().validate(hero, "hero.schema.json", hero_path)
        if errors:
            raise ContentError(errors)
        prefix = _prefix(hero_id, body.skin)
        cache = {}

        def report(path):
            require_owned_model_path(path, prefix)
            if path not in cache:
                try:
                    cache[path] = inspect_glb(ws.read_bytes(path))
                except KeyError as exc:
                    raise ModelError("Файл модели или анимации не найден в черновике") from exc
            return cache[path]

        main = report(body.model["file"])
        if not main["mesh_instances"]:
            raise ModelError("Основной GLB не содержит отображаемую сетку модели")
        for name, anim in body.model.get("animations", {}).items():
            if anim["clip"] not in report(anim["file"])["animations"]:
                raise ModelError(f"Анимация «{name}» не найдена в выбранном файле")
        for name, anchor in body.model.get("anchors", {}).items():
            if anchor["bone"] != "@root" and anchor["bone"] not in main["bones"]:
                raise ModelError(f"Кость точки «{name}» не найдена в основной модели")
        await drf.put_json(session, admin.id, hero_path, hero)
        await audit(session, request, admin, "model3d_config", f"3D-настройки героя «{hero_id}»",
                    {"hero": hero_id, "skin": body.skin})
        await session.commit()
        return {"ok": True}
    except (ModelError, ContentError) as exc:
        raise HTTPException(422, str(exc)) from exc


@router.get("/{hero_id}/inspect")
async def inspect_saved(hero_id: str, path: str, admin: AdminUser = Depends(editor),
                        session: AsyncSession = Depends(get_session)):
    if (not ID.fullmatch(hero_id) or posixpath.normpath(path) != path or not INSPECT_PATH.fullmatch(path)
            or not path.startswith(f"heroes/{hero_id}/")):
        raise HTTPException(422, "Некорректный путь модели")
    ws = await drf.workspace(session)
    try:
        result = inspect_glb(ws.read_bytes(path))
    except KeyError as exc:
        raise HTTPException(404, "Модель не найдена") from exc
    except ModelError as exc:
        raise HTTPException(422, str(exc)) from exc
    await session.commit()
    return {"path": path, **result}


def unpack(data: bytes, max_bytes: int = MAX_GLB_BYTES) -> list[tuple[str, bytes]]:
    """GLB как есть или ZIP только из GLB. Размер берётся по фактически прочитанным байтам, не по заголовку."""
    if data.startswith(b"glTF"):
        if len(data) > max_bytes:
            raise ModelError("GLB больше 50 МиБ")
        return [("model.glb", data)]
    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except (zipfile.BadZipFile, OSError) as exc:
        raise ModelError("Ожидается GLB или ZIP-архив с файлами GLB") from exc
    with archive:
        entries = [x for x in archive.infolist() if not x.is_dir()]
        if not entries or len(entries) > MAX_FILES:
            raise ModelError(f"Архив должен содержать от 1 до {MAX_FILES} файлов GLB")
        names = set()
        for entry in entries:
            name = entry.filename.replace("\\", "/")
            parts = name.split("/")
            if name.startswith("/") or any(part in ("", ".", "..") for part in parts):
                raise ModelError("Недопустимый путь в архиве")
            if not name.lower().endswith(".glb") or name.lower() in names:
                raise ModelError("В ZIP допустимы только GLB с разными именами")
            if entry.flag_bits & 1 or entry.file_size < 0 or entry.file_size > max_bytes:
                raise ModelError("Зашифрованный или слишком большой файл в архиве")
            names.add(name.lower())
        if sum(x.file_size for x in entries) > max_bytes:
            raise ModelError("Распакованные модели занимают больше 50 МиБ")
        out = []
        total = 0
        for entry in entries:
            try:
                with archive.open(entry, "r") as src:
                    payload = src.read(max_bytes + 1)
            except (zipfile.BadZipFile, RuntimeError, OSError, EOFError, zlib.error) as exc:
                raise ModelError("Не удалось прочитать ZIP-архив") from exc
            if len(payload) > max_bytes:
                raise ModelError("Распакованные модели занимают больше 50 МиБ")
            total += len(payload)
            if total > max_bytes:
                raise ModelError("Распакованные модели занимают больше 50 МиБ")
            out.append((entry.filename, payload))
        return out


@router.post("/{hero_id}/upload")
async def upload(hero_id: str, request: Request, skin: str = "", admin: AdminUser = Depends(editor),
                 session: AsyncSession = Depends(get_session)):
    if not ID.fullmatch(hero_id) or (skin and not ID.fullmatch(skin)):
        raise HTTPException(422, "Некорректный идентификатор героя или скина")
    data = bytearray()
    async for chunk in request.stream():
        data.extend(chunk)
        if len(data) > MAX_GLB_BYTES:
            raise HTTPException(413, "GLB или ZIP больше 50 МиБ")
    if not data:
        raise HTTPException(422, "Пустой файл")
    try:
        files = unpack(bytes(data))
        # Сначала проверяем все файлы. При ошибке в черновик не пишется ничего.
        reports = [(name, payload, inspect_glb(payload)) for name, payload in files]
        ws = await drf.workspace(session)
        hero_path = f"heroes/{hero_id}/hero.json"
        if not ws.exists(hero_path):
            raise HTTPException(404, "Герой не найден")
        hero = ws.read_json(hero_path)
        if skin and not any(s.get("id") == skin for s in hero.get("skins", [])):
            raise HTTPException(404, "Скин не найден")
        prefix = _prefix(hero_id, skin)
        result = []
        for name, payload, report in reports:
            digest = hashlib.sha256(payload).hexdigest()
            stem = PurePosixPath(name.replace("\\", "/")).stem.lower()
            safe_name = re.sub(r"[^a-z0-9_-]+", "_", stem).strip("_-.")[:40] or "model"
            path = prefix + safe_name + "_" + digest + ".glb"
            await drf.put_file(session, admin.id, path, payload)
            result.append({"name": name, "path": path, **report})
        await audit(session, request, admin, "model3d_upload", f"3D-модель героя «{hero_id}»: файлов {len(result)}",
                    {"hero": hero_id, "skin": skin, "files": [f["path"] for f in result]})
        await session.commit()
        return {"files": result}
    except (ModelError, ContentError) as exc:
        raise HTTPException(422, str(exc)) from exc

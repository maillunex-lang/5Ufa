"""Обновления приложения: проверка новой версии и загрузка APK из GitHub Actions."""
from __future__ import annotations

import base64
import hashlib
import hmac
import os
import tempfile
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.content.releases import get_store
from app.db import get_session
from app.models import ClientRelease

router = APIRouter(prefix="/api/v1/client", tags=["client"])


def release_public(r: ClientRelease) -> dict:
    s = get_settings()
    return {
        "version_code": r.version_code,
        "version_name": r.version_name,
        "size": r.size,
        "sha256": r.sha256,
        "notes": r.notes,
        "mandatory": r.mandatory,
        # Путь от корня домена, как base_url в манифесте
        "url": s.public_content_files_url + get_store().relative_url(r.sha256),
    }


@router.get("/latest")
async def latest(code: int = Query(0, ge=0, description="versionCode установленного приложения"),
                 session: AsyncSession = Depends(get_session)):
    """Есть ли новая версия приложения. required=true — без обновления играть нельзя."""
    newest = (await session.execute(
        select(ClientRelease).where(ClientRelease.active.is_(True))
        .order_by(ClientRelease.version_code.desc()).limit(1)
    )).scalar_one_or_none()
    if newest is None or newest.version_code <= code:
        return {"update_available": False, "required": False, "latest": None}
    required = (await session.execute(
        select(ClientRelease.id).where(ClientRelease.active.is_(True), ClientRelease.mandatory.is_(True),
                                       ClientRelease.version_code > code).limit(1)
    )).first() is not None
    return {"update_available": True, "required": required, "latest": release_public(newest)}


@router.put("/releases/{version_code}")
async def upload_release(version_code: int, request: Request,
                         version_name: str = Query(..., pattern=r"^\d+\.\d+\.\d+$"),
                         mandatory: bool = False,
                         session: AsyncSession = Depends(get_session)):
    """Загрузка новой сборки APK (вызывает GitHub Actions). Тело запроса — сам файл APK.

    Заголовок X-Upload-Token — секрет CLIENT_UPLOAD_TOKEN; X-Notes — описание в base64 (UTF-8).
    """
    s = get_settings()
    token = request.headers.get("x-upload-token", "")
    if not s.client_upload_token or not hmac.compare_digest(token, s.client_upload_token):
        raise HTTPException(403, "Неверный токен загрузки")
    notes = ""
    if request.headers.get("x-notes"):
        try:
            notes = base64.b64decode(request.headers["x-notes"]).decode("utf-8")[:2000]
        except ValueError:
            notes = ""
    existing = (await session.execute(
        select(ClientRelease).where(ClientRelease.version_code == version_code)
    )).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(409, f"Версия с кодом {version_code} уже загружена")

    limit = s.client_max_apk_mb * 1024 * 1024
    store = get_store()
    store.files_dir.mkdir(parents=True, exist_ok=True)
    h = hashlib.sha256()
    size = 0
    fd, tmp = tempfile.mkstemp(dir=store.files_dir, prefix=".upload_")
    try:
        with os.fdopen(fd, "wb") as f:
            async for chunk in request.stream():
                size += len(chunk)
                if size > limit:
                    raise HTTPException(413, f"APK больше {s.client_max_apk_mb} МБ")
                h.update(chunk)
                f.write(chunk)
        if size < 1024:
            raise HTTPException(422, "Файл слишком маленький — это не APK")
        with open(tmp, "rb") as f:
            if f.read(2) != b"PK":
                raise HTTPException(422, "Файл не похож на APK (ZIP)")
        sha = h.hexdigest()
        store.put_file(Path(tmp), sha)
    finally:
        Path(tmp).unlink(missing_ok=True)

    rel = ClientRelease(version_code=version_code, version_name=version_name, sha256=sha,
                        size=size, notes=notes, mandatory=mandatory)
    session.add(rel)
    await session.commit()
    return {"ok": True, "release": release_public(rel)}

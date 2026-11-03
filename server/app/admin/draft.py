"""Общий черновик контента.

Черновик — набор изменённых файлов (content_draft_files) поверх базового релиза (content_draft_meta).
Файлы хранятся в том же хранилище по SHA-256, что и опубликованный контент.
«Собрать» = базовый релиз + правки черновика → проверка всего контента → новый релиз.
"""
from __future__ import annotations

import json
import os
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.content.builder import ALLOWED_EXTENSIONS
from app.content.releases import get_channel_release, get_store, import_directory
from app.content.validation import ContentError, get_schema_registry, glob_to_regex
from app.models import ContentRelease, DraftFile, DraftMeta

PACKAGES = "packages.json"


def check_path(path: str) -> str:
    """Безопасный путь в контенте: латиница, цифры, _ - . /, без .. и ведущего /."""
    import re
    p = (path or "").strip()
    if not re.fullmatch(r"[a-z0-9_\-./]{1,300}", p) or p.startswith("/") or ".." in p.split("/") or "//" in p:
        raise ContentError([f"Недопустимый путь «{path}»: только латиница в нижнем регистре, цифры и _ - . /"])
    if p != PACKAGES and Path(p).suffix.lower() not in ALLOWED_EXTENSIONS:
        raise ContentError([f"{p}: неподдерживаемый формат. Разрешены: {', '.join(sorted(ALLOWED_EXTENSIONS))}"])
    return p


class Workspace:
    """Содержимое контента «как будет после публикации черновика»."""

    def __init__(self, base: ContentRelease | None, overlay: dict[str, str | None]):
        self.base = base
        self.base_files: dict[str, str] = {}
        if base is not None:
            for pkg in base.manifest.get("packages", []):
                for f in pkg["files"]:
                    self.base_files[f["path"]] = f["sha256"]
        self.overlay = dict(overlay)
        self.store = get_store()

    # --- чтение ---
    def files(self) -> dict[str, str]:
        out = dict(self.base_files)
        out[PACKAGES] = "packages"  # особый файл, см. read_bytes
        for p, sha in self.overlay.items():
            if sha is None:
                out.pop(p, None)
            else:
                out[p] = sha
        return out

    def exists(self, path: str) -> bool:
        return path in self.files()

    def read_bytes(self, path: str) -> bytes:
        if path in self.overlay:
            sha = self.overlay[path]
            if sha is None:
                raise KeyError(path)
            return self.store.path_for(sha).read_bytes()
        if path == PACKAGES:
            return self._base_packages()
        sha = self.base_files.get(path)
        if sha is None:
            raise KeyError(path)
        return self.store.path_for(sha).read_bytes()

    def read_json(self, path: str):
        return json.loads(self.read_bytes(path).decode("utf-8"))

    def _base_packages(self) -> bytes:
        if self.base is not None and "packages_def" in self.base.manifest:
            return json.dumps(self.base.manifest["packages_def"], ensure_ascii=False, indent=2).encode()
        return (get_settings().base_content_dir / PACKAGES).read_bytes()

    def glob(self, pattern: str) -> list[str]:
        rx = glob_to_regex(pattern)
        return sorted(p for p in self.files() if rx.match(p))

    # --- сборка во временную папку (ссылки на файлы хранилища, без копирования) ---
    def materialize(self, target: Path) -> None:
        for path, sha in self.files().items():
            dest = target / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            if path == PACKAGES:
                dest.write_bytes(self.read_bytes(PACKAGES))
            else:
                os.symlink(self.store.path_for(sha), dest)


# --- Черновик в базе ----------------------------------------------------------------

async def meta(session: AsyncSession) -> DraftMeta:
    m = await session.get(DraftMeta, 1, with_for_update=True)
    if m is None:
        live = await get_channel_release(session, "live")
        m = DraftMeta(id=1, base_release_id=live.id if live else None)
        session.add(m)
        await session.flush()
    return m


async def workspace(session: AsyncSession) -> Workspace:
    m = await meta(session)
    base = await session.get(ContentRelease, m.base_release_id) if m.base_release_id else None
    rows = (await session.execute(select(DraftFile))).scalars()
    return Workspace(base, {r.path: r.sha256 for r in rows})


def validate_file(path: str, data: bytes) -> list[str]:
    """Проверка одного файла перед записью в черновик: JSON и схема раздела."""
    if not path.endswith(".json"):
        return []
    try:
        obj = json.loads(data.decode("utf-8"))
    except UnicodeDecodeError:
        return [f"{path}: файл должен быть в кодировке UTF-8"]
    except json.JSONDecodeError as e:
        return [f"{path}: ошибка JSON в строке {e.lineno}, столбце {e.colno}: {e.msg}"]
    reg = get_schema_registry()
    schema = "content-packages.schema.json" if path == PACKAGES else reg.schema_for_path(path)
    return reg.validate(obj, schema, path) if schema else []


async def put_file(session: AsyncSession, admin_id: int | None, path: str, data: bytes) -> dict:
    path = check_path(path)
    limit = get_settings().admin_file_max_mb * 1024 * 1024
    if len(data) > limit:
        raise ContentError([f"{path}: файл больше {get_settings().admin_file_max_mb} МБ"])
    errors = validate_file(path, data)
    if errors:
        raise ContentError(errors)
    ws = await workspace(session)
    sha = get_store().put_bytes(data)
    base_sha = ws.base_files.get(path)
    row = await session.get(DraftFile, path)
    same = base_sha == sha
    if not same and base_sha and path.endswith(".json"):
        # Тот же JSON по смыслу (1 и 1.0, другой порядок ключей) — не считаем правкой
        try:
            same = json.loads(data.decode("utf-8")) == json.loads(get_store().path_for(base_sha).read_bytes())
        except (ValueError, OSError):
            same = False
    if path != PACKAGES and same:
        if row is not None:  # вернули как было — правка больше не нужна
            await session.delete(row)
        await session.flush()
        return {"path": path, "sha256": sha, "changed": False}
    if row is None:
        row = DraftFile(path=path)
        session.add(row)
    row.sha256, row.size, row.admin_id = sha, len(data), admin_id
    row.updated_at = datetime.now(timezone.utc)
    await session.flush()
    return {"path": path, "sha256": sha, "changed": True}


async def put_json(session: AsyncSession, admin_id: int | None, path: str, obj) -> dict:
    data = (json.dumps(obj, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    return await put_file(session, admin_id, path, data)


async def delete_file(session: AsyncSession, admin_id: int | None, path: str) -> None:
    path = check_path(path)
    if path == PACKAGES:
        raise ContentError(["packages.json удалить нельзя"])
    ws = await workspace(session)
    row = await session.get(DraftFile, path)
    if path not in ws.base_files:
        if row is not None:
            await session.delete(row)  # файл был только в черновике
            await session.flush()
            return
        raise ContentError([f"Файла {path} нет в контенте"])
    if row is None:
        row = DraftFile(path=path)
        session.add(row)
    row.sha256, row.size, row.admin_id = None, 0, admin_id
    row.updated_at = datetime.now(timezone.utc)
    await session.flush()


async def revert(session: AsyncSession, path: str | None) -> int:
    """Отменить правку одного файла или (path=None) весь черновик."""
    if path is None:
        n = len(list((await session.execute(select(DraftFile))).scalars()))
        await session.execute(delete(DraftFile))
        m = await meta(session)
        live = await get_channel_release(session, "live")
        m.base_release_id = live.id if live else None
        await session.flush()
        return n
    row = await session.get(DraftFile, path)
    if row is None:
        return 0
    await session.delete(row)
    await session.flush()
    return 1


async def changes(session: AsyncSession) -> dict:
    ws = await workspace(session)
    live = await get_channel_release(session, "live")
    rows = list((await session.execute(select(DraftFile).order_by(DraftFile.path))).scalars())
    items = []
    for r in rows:
        if r.sha256 is None:
            kind = "delete"
        elif r.path in ws.base_files or r.path == PACKAGES:
            kind = "update"
        else:
            kind = "add"
        items.append({"path": r.path, "change": kind, "size": r.size,
                      "updated_at": r.updated_at.isoformat() if r.updated_at else None})
    return {
        "base_release": ws.base.id if ws.base else None,
        "live_release": live.id if live else None,
        "outdated": bool(ws.base and live and ws.base.id != live.id),
        "changes": items,
    }


async def rebase(session: AsyncSession) -> None:
    """Перенести черновик на текущую live-версию (после отката или публикации извне)."""
    m = await meta(session)
    live = await get_channel_release(session, "live")
    m.base_release_id = live.id if live else None
    await session.flush()


async def build_release(session: AsyncSession, comment: str) -> tuple[ContentRelease, bool]:
    """Собрать релиз из черновика. Ошибки контента — ContentError со списком на русском."""
    ws = await workspace(session)
    with tempfile.TemporaryDirectory(prefix="draft_") as tmp:
        ws.materialize(Path(tmp))
        return await import_directory(session, Path(tmp), source="admin", comment=comment)


async def clear_after_publish(session: AsyncSession, release: ContentRelease) -> None:
    await session.execute(delete(DraftFile))
    m = await meta(session)
    m.base_release_id = release.id
    await session.flush()

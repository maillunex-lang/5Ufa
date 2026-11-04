"""Работа с релизами контента: создание, публикация в канал, откат."""
from __future__ import annotations

from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.content.builder import build_manifest
from app.content.store import ContentStore
from app.content.validation import ContentError, get_schema_registry
from app.models import CHANNELS, ContentChannel, ContentRelease


def get_store() -> ContentStore:
    return ContentStore(get_settings().content_store_dir)


async def import_directory(
    session: AsyncSession, content_dir: Path, *, source: str = "base", comment: str = ""
) -> tuple[ContentRelease, bool]:
    """Собрать релиз из папки. Возвращает (релиз, создан_ли_новый).

    Если точно такой же контент уже есть в последнем релизе — новый не создаётся.
    """
    result = build_manifest(content_dir, get_store(), get_schema_registry())
    latest = (
        await session.execute(select(ContentRelease).order_by(ContentRelease.id.desc()).limit(1))
    ).scalar_one_or_none()
    if latest is not None and latest.content_hash == result.content_hash:
        return latest, False
    release = ContentRelease(
        source=source,
        comment=comment,
        content_hash=result.content_hash,
        files_count=result.files_count,
        total_size=result.total_size,
        manifest=result.manifest,
    )
    session.add(release)
    await session.flush()
    return release, True


async def _rebase_empty_draft(session: AsyncSession, release_id: int) -> None:
    """Пустой черновик админки сразу переводим на новую версию (непустой — админ перенесёт сам)."""
    from app.models import DraftFile, DraftMeta
    if (await session.execute(select(DraftFile.path).limit(1))).first() is None:
        m = await session.get(DraftMeta, 1)
        if m is not None:
            m.base_release_id = release_id
            await session.flush()


async def import_base_merged(session: AsyncSession, content_dir: Path, comment: str) -> tuple[ContentRelease | None, str]:
    """Деплой: перенести в игру изменения базового контента из репозитория, не затирая правки из админки.

    1. Контент репозитория импортируется как релиз source="base" (если не изменился — ничего не делаем).
    2. Если у игроков сейчас прошлый базовый релиз (правок из админки не было) — публикуется новый как есть.
    3. Иначе берётся то, что опубликовано сейчас, и поверх кладутся только файлы, изменённые в репозитории
       с прошлого базового импорта (новые/изменённые/удалённые). Результат — релиз source="merge".
    Возвращает (опубликованный релиз или None, пояснение).
    """
    import tempfile
    result = build_manifest(content_dir, get_store(), get_schema_registry())
    prev_base = (await session.execute(select(ContentRelease).where(ContentRelease.source == "base")
                                       .order_by(ContentRelease.id.desc()).limit(1))).scalar_one_or_none()
    if prev_base is not None and prev_base.content_hash == result.content_hash:
        return None, f"Базовый контент не изменился (релиз №{prev_base.id})"
    base = ContentRelease(source="base", comment=comment, content_hash=result.content_hash,
                          files_count=result.files_count, total_size=result.total_size, manifest=result.manifest)
    session.add(base)
    await session.flush()
    live = await get_channel_release(session, "live")
    if live is None or prev_base is None or live.id == prev_base.id:
        for ch in CHANNELS:
            await publish(session, base.id, ch)
        await _rebase_empty_draft(session, base.id)
        return base, f"Опубликован базовый контент №{base.id}"

    def files_of(r: ContentRelease) -> dict[str, str]:
        return {f["path"]: f["sha256"] for p in r.manifest.get("packages", []) for f in p["files"]}

    old, new = files_of(prev_base), files_of(base)
    overlay: dict[str, str | None] = {p: sha for p, sha in new.items() if old.get(p) != sha}
    overlay.update({p: None for p in old if p not in new})
    if prev_base.manifest.get("packages_def") != base.manifest.get("packages_def"):
        import json
        overlay["packages.json"] = get_store().put_bytes(
            json.dumps(base.manifest["packages_def"], ensure_ascii=False, indent=2).encode())
    from app.admin.draft import Workspace  # отложенный импорт: модуль админки зависит от этого
    ws = Workspace(live, overlay)
    with tempfile.TemporaryDirectory(prefix="merge_") as tmp:
        ws.materialize(Path(tmp))
        merged, _ = await import_directory(session, Path(tmp), source="merge",
                                           comment=f"{comment} + правки из админки (версия №{live.id})")
    for ch in CHANNELS:
        await publish(session, merged.id, ch)
    await _rebase_empty_draft(session, merged.id)
    changed = sorted(overlay)
    return merged, (f"Изменения репозитория ({len(changed)} файлов) перенесены поверх версии №{live.id} "
                    f"(правки из админки сохранены): релиз №{merged.id}")


async def publish(session: AsyncSession, release_id: int, channel: str) -> ContentChannel:
    """Направить канал (live/test) на релиз. Это же — откат к старой версии."""
    if channel not in CHANNELS:
        raise ContentError([f"Неизвестный канал «{channel}». Доступны: {', '.join(CHANNELS)}"])
    release = await session.get(ContentRelease, release_id)
    if release is None:
        raise ContentError([f"Релиз контента №{release_id} не найден"])
    ch = await session.get(ContentChannel, channel)
    if ch is None:
        ch = ContentChannel(name=channel, release_id=release_id)
        session.add(ch)
    else:
        ch.release_id = release_id
    await session.flush()
    return ch


async def get_channel_release(session: AsyncSession, channel: str) -> ContentRelease | None:
    ch = await session.get(ContentChannel, channel)
    if ch is None:
        return None
    return await session.get(ContentRelease, ch.release_id)


def public_manifest(release: ContentRelease, channel: str) -> dict:
    """Манифест в том виде, в каком его получает клиент."""
    s = get_settings()
    m = dict(release.manifest)
    return {
        "schema_version": m["schema_version"],
        "release": release.id,
        "channel": channel,
        "content_hash": release.content_hash,
        "created_at": release.created_at.isoformat() if release.created_at else None,
        "min_client_version": m["min_client_version"],
        "base_url": s.public_content_files_url,
        "total_size": m["total_size"],
        "packages": m["packages"],
    }

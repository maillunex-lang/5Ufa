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
        "base_url": s.content_files_url,
        "total_size": m["total_size"],
        "packages": m["packages"],
    }

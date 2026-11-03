"""Консольные команды сервера.

Запуск на VPS (из папки проекта):
    docker compose exec api python -m app.cli content status
    docker compose exec api python -m app.cli content list
    docker compose exec api python -m app.cli content import --publish
    docker compose exec api python -m app.cli content publish 3 --channel live
    docker compose exec api python -m app.cli content validate
"""
from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

from sqlalchemy import select

from app.config import get_settings
from app.content.builder import build_manifest
from app.content.releases import get_channel_release, import_directory, publish
from app.content.validation import ContentError, get_schema_registry
from app.db import get_sessionmaker
from app.models import CHANNELS, ContentRelease


def _mb(n: int) -> str:
    return f"{n / 1024 / 1024:.2f} МБ"


async def cmd_import(args) -> int:
    content_dir = Path(args.dir or get_settings().base_content_dir)
    async with get_sessionmaker()() as session:
        if args.if_empty:
            exists = (await session.execute(select(ContentRelease.id).limit(1))).first()
            if exists:
                print("Контент уже импортирован ранее — пропускаю (--if-empty).")
                return 0
        release, created = await import_directory(session, content_dir, source="base", comment=args.comment)
        print(("Создан релиз" if created else "Контент не изменился, релиз") +
              f" №{release.id}: файлов {release.files_count}, размер {_mb(release.total_size)}")
        if args.publish:
            for ch in CHANNELS:
                await publish(session, release.id, ch)
            print(f"Релиз №{release.id} опубликован в каналы: {', '.join(CHANNELS)}")
        await session.commit()
    return 0


async def cmd_list(args) -> int:
    async with get_sessionmaker()() as session:
        rows = (await session.execute(
            select(ContentRelease).order_by(ContentRelease.id.desc()).limit(args.limit)
        )).scalars().all()
        channels = {ch: await get_channel_release(session, ch) for ch in CHANNELS}
        if not rows:
            print("Релизов контента пока нет. Выполните: content import --publish")
        for r in rows:
            marks = [ch for ch, rel in channels.items() if rel and rel.id == r.id]
            mark = f"  <- {', '.join(marks)}" if marks else ""
            print(f"№{r.id:<4} {r.created_at:%Y-%m-%d %H:%M}  {r.source:<7} файлов {r.files_count:<5} "
                  f"{_mb(r.total_size):>10}  {r.comment}{mark}")
    return 0


async def cmd_publish(args) -> int:
    async with get_sessionmaker()() as session:
        await publish(session, args.release_id, args.channel)
        await session.commit()
    print(f"Канал «{args.channel}» теперь указывает на релиз №{args.release_id}")
    return 0


async def cmd_status(args) -> int:
    async with get_sessionmaker()() as session:
        for ch in CHANNELS:
            rel = await get_channel_release(session, ch)
            print(f"{ch:<5}: " + (f"релиз №{rel.id}, файлов {rel.files_count}, {_mb(rel.total_size)}" if rel else "—"))
    return 0


async def cmd_validate(args) -> int:
    content_dir = Path(args.dir or get_settings().base_content_dir)
    result = build_manifest(content_dir, None, get_schema_registry())
    print(f"Контент в порядке: пакетов {len(result.manifest['packages'])}, "
          f"файлов {result.files_count}, размер {_mb(result.total_size)}")
    for p in result.manifest["packages"]:
        req = "обязательный" if p["required"] else "фоновый"
        print(f"  {p['id']:<14} {req:<12} файлов {len(p['files']):<4} {_mb(p['size'])}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="app.cli")
    sub = parser.add_subparsers(dest="group", required=True)
    content = sub.add_parser("content", help="Управление контентом").add_subparsers(dest="cmd", required=True)

    p = content.add_parser("import", help="Импортировать контент из папки в новый релиз")
    p.add_argument("--dir", help="Папка контента (по умолчанию базовый контент из образа)")
    p.add_argument("--publish", action="store_true", help="Сразу опубликовать в live и test")
    p.add_argument("--if-empty", action="store_true", help="Только если релизов ещё нет (первый запуск)")
    p.add_argument("--comment", default="Базовый контент", help="Комментарий к релизу")
    p.set_defaults(func=cmd_import)

    p = content.add_parser("list", help="Список релизов")
    p.add_argument("--limit", type=int, default=20)
    p.set_defaults(func=cmd_list)

    p = content.add_parser("publish", help="Опубликовать релиз / откатиться к старому")
    p.add_argument("release_id", type=int)
    p.add_argument("--channel", default="live", choices=CHANNELS)
    p.set_defaults(func=cmd_publish)

    content.add_parser("status", help="Какие релизы сейчас в каналах").set_defaults(func=cmd_status)

    p = content.add_parser("validate", help="Проверить контент без импорта")
    p.add_argument("--dir")
    p.set_defaults(func=cmd_validate)

    args = parser.parse_args(argv)
    try:
        return asyncio.run(args.func(args))
    except ContentError as e:
        print("ОШИБКИ КОНТЕНТА:", file=sys.stderr)
        for m in e.messages:
            print("  - " + m, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

"""Консольные команды сервера.

Запуск на VPS (из папки проекта):
    docker compose exec api python -m app.cli content status
    docker compose exec api python -m app.cli content list
    docker compose exec api python -m app.cli content import --publish
    docker compose exec api python -m app.cli content publish 3 --channel live
    docker compose exec api python -m app.cli content validate
    docker compose exec api python -m app.cli player list
    docker compose exec api python -m app.cli player set-test 1001
    docker compose exec api python -m app.cli player ban 1001 --days 7 --reason "мат в чате"
    docker compose exec api python -m app.cli client list
    docker compose exec api python -m app.cli client set 12 mandatory
    docker compose exec -it api python -m app.cli admin create owner      (пароль спросит, на экране не виден)
    docker compose exec -it api python -m app.cli admin set-password owner
    docker compose exec api python -m app.cli admin list
    docker compose exec api python -m app.cli admin 2fa-enable owner     (включить код из приложения)
    docker compose exec api python -m app.cli admin 2fa-disable owner
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
from app.models import CHANNELS, ClientRelease, ContentRelease, Player


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
        if args.publish or (args.publish_if_new and created):
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


async def _find_player(session, ref: str) -> Player:
    """Найти игрока по номеру (1001), почте или id."""
    import uuid as _uuid
    q = select(Player)
    if ref.isdigit():
        q = q.where(Player.number == int(ref))
    elif "@" in ref:
        q = q.where(Player.email == ref.strip().lower())
    else:
        try:
            q = q.where(Player.id == _uuid.UUID(ref))
        except ValueError:
            raise ContentError([f"Не понимаю «{ref}»: укажите номер игрока, почту или id"])
    p = (await session.execute(q)).scalar_one_or_none()
    if p is None:
        raise ContentError([f"Игрок «{ref}» не найден"])
    return p


def _player_line(p: Player) -> str:
    kind = p.email or "гость"
    flags = []
    if p.is_test:
        flags.append("ТЕСТОВЫЙ")
    if p.banned_until:
        flags.append(f"бан до {p.banned_until:%Y-%m-%d}")
    return f"#{p.number:<6} {p.display_name:<16} {kind:<30} {' '.join(flags)}"


async def cmd_player_list(args) -> int:
    async with get_sessionmaker()() as session:
        rows = (await session.execute(select(Player).order_by(Player.number.desc()).limit(args.limit))).scalars()
        for p in rows:
            print(_player_line(p))
    return 0


async def cmd_player_set_test(args) -> int:
    async with get_sessionmaker()() as session:
        p = await _find_player(session, args.player)
        p.is_test = not args.off
        await session.commit()
        print(_player_line(p))
        print("Теперь получает контент из канала test." if p.is_test else "Снова обычный игрок (канал live).")
    return 0


async def cmd_player_ban(args) -> int:
    from datetime import datetime, timedelta, timezone
    async with get_sessionmaker()() as session:
        p = await _find_player(session, args.player)
        if args.days <= 0:
            p.banned_until, p.ban_reason = None, ""
        else:
            p.banned_until = datetime.now(timezone.utc) + timedelta(days=args.days)
            p.ban_reason = args.reason
        await session.commit()
        print(_player_line(p))
    return 0


async def cmd_client_list(args) -> int:
    async with get_sessionmaker()() as session:
        rows = (await session.execute(select(ClientRelease).order_by(ClientRelease.version_code.desc()).limit(20))).scalars()
        for r in rows:
            flags = ("" if r.active else " ВЫКЛЮЧЕНА") + (" ОБЯЗАТЕЛЬНАЯ" if r.mandatory else "")
            print(f"код {r.version_code:<5} {r.version_name:<10} {_mb(r.size):>9}  {r.created_at:%Y-%m-%d %H:%M}{flags}")
    return 0


async def cmd_client_set(args) -> int:
    async with get_sessionmaker()() as session:
        r = (await session.execute(select(ClientRelease).where(ClientRelease.version_code == args.code))).scalar_one_or_none()
        if r is None:
            raise ContentError([f"Версия с кодом {args.code} не найдена"])
        if args.action == "disable":
            r.active = False
        elif args.action == "enable":
            r.active = True
        elif args.action == "mandatory":
            r.mandatory = True
        elif args.action == "optional":
            r.mandatory = False
        await session.commit()
        print(f"Версия {r.version_name} (код {r.version_code}): активна={r.active}, обязательная={r.mandatory}")
    return 0


# --- Администраторы админки -----------------------------------------------------------

def _ask_password() -> str:
    import getpass
    import os
    pw = os.environ.get("ADMIN_PASSWORD", "")  # для автоматизации; обычно пароль спрашивается
    if pw:
        return pw
    pw = getpass.getpass("Пароль (от 10 символов, на экране не виден): ")
    if pw != getpass.getpass("Повторите пароль: "):
        raise SystemExit("Пароли не совпадают")
    return pw


def _check_password(pw: str) -> None:
    if len(pw) < 10 or pw.isdigit() or pw.isalpha():
        raise SystemExit("Пароль слишком простой: нужно от 10 символов, буквы и цифры")


async def cmd_admin_create(args) -> int:
    from app.auth.security import hash_password
    from app.models import ADMIN_ROLES, AdminUser
    login = args.login.strip().lower()
    if args.role not in ADMIN_ROLES:
        raise SystemExit(f"Роль: {', '.join(ADMIN_ROLES)}")
    pw = _ask_password()
    _check_password(pw)
    async with get_sessionmaker()() as session:
        if (await session.execute(select(AdminUser).where(AdminUser.login == login))).scalar_one_or_none():
            raise SystemExit(f"Администратор {login} уже есть. Сменить пароль: admin set-password {login}")
        session.add(AdminUser(login=login, password_hash=hash_password(pw), role=args.role))
        await session.commit()
    print(f"Создан администратор {login} (роль {args.role}). Войдите в админку с этим логином и паролем.")
    return 0


async def _get_admin(session, login: str):
    from app.models import AdminUser
    admin = (await session.execute(select(AdminUser).where(AdminUser.login == login.strip().lower()))).scalar_one_or_none()
    if admin is None:
        raise SystemExit(f"Администратор {login} не найден (список: admin list)")
    return admin


async def cmd_admin_password(args) -> int:
    from sqlalchemy import delete as sql_delete
    from app.auth.security import hash_password
    from app.models import AdminSession
    pw = _ask_password()
    _check_password(pw)
    async with get_sessionmaker()() as session:
        admin = await _get_admin(session, args.login)
        admin.password_hash = hash_password(pw)
        admin.disabled = False
        await session.execute(sql_delete(AdminSession).where(AdminSession.admin_id == admin.id))  # выйти везде
        await session.commit()
    print(f"Пароль {args.login} изменён, все сессии закрыты.")
    return 0


async def cmd_admin_list(args) -> int:
    from app.models import AdminUser
    async with get_sessionmaker()() as session:
        rows = (await session.execute(select(AdminUser).order_by(AdminUser.id))).scalars()
        for a in rows:
            print(f"{a.login:<20} роль={a.role:<9} 2FA={'вкл' if a.totp_enabled else 'выкл'} "
                  f"{'ОТКЛЮЧЁН ' if a.disabled else ''}последний вход={a.last_login_at or '—'}")
    return 0


async def cmd_admin_2fa(args) -> int:
    from app.admin.security import totp_new_secret, totp_uri
    async with get_sessionmaker()() as session:
        admin = await _get_admin(session, args.login)
        if args.enable:
            admin.totp_secret = totp_new_secret()
            admin.totp_enabled = True
            await session.commit()
            print("2FA включена. Добавьте ключ в приложение-аутентификатор (Яндекс Ключ, Google Authenticator):")
            print("  ключ:   ", admin.totp_secret)
            print("  ссылка: ", totp_uri(admin.totp_secret, admin.login))
            print("Теперь при входе в админку нужен 6-значный код из приложения.")
        else:
            admin.totp_enabled = False
            admin.totp_secret = None
            await session.commit()
            print("2FA выключена.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="app.cli")
    sub = parser.add_subparsers(dest="group", required=True)
    content = sub.add_parser("content", help="Управление контентом").add_subparsers(dest="cmd", required=True)

    p = content.add_parser("import", help="Импортировать контент из папки в новый релиз")
    p.add_argument("--dir", help="Папка контента (по умолчанию базовый контент из образа)")
    p.add_argument("--publish", action="store_true", help="Сразу опубликовать в live и test")
    p.add_argument("--if-empty", action="store_true", help="Только если релизов ещё нет (первый запуск)")
    p.add_argument("--publish-if-new", action="store_true",
                   help="Опубликовать, только если контент изменился (при деплое; ручной откат не перетирается)")
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

    player = sub.add_parser("player", help="Игроки").add_subparsers(dest="cmd", required=True)
    p = player.add_parser("list", help="Последние игроки")
    p.add_argument("--limit", type=int, default=30)
    p.set_defaults(func=cmd_player_list)
    p = player.add_parser("set-test", help="Сделать игрока тестовым (видит канал test)")
    p.add_argument("player", help="номер (#1001 -> 1001), почта или id")
    p.add_argument("--off", action="store_true", help="снять отметку")
    p.set_defaults(func=cmd_player_set_test)
    p = player.add_parser("ban", help="Заблокировать игрока (--days 0 — разблокировать)")
    p.add_argument("player")
    p.add_argument("--days", type=int, default=3650)
    p.add_argument("--reason", default="")
    p.set_defaults(func=cmd_player_ban)

    client = sub.add_parser("client", help="Версии приложения (APK)").add_subparsers(dest="cmd", required=True)
    client.add_parser("list", help="Загруженные версии").set_defaults(func=cmd_client_list)
    p = client.add_parser("set", help="Изменить версию")
    p.add_argument("code", type=int, help="код версии (versionCode)")
    p.add_argument("action", choices=["disable", "enable", "mandatory", "optional"],
                   help="disable — не предлагать игрокам; mandatory — обновление обязательно")
    p.set_defaults(func=cmd_client_set)

    adm = sub.add_parser("admin", help="Администраторы админки").add_subparsers(dest="cmd", required=True)
    p = adm.add_parser("create", help="Создать администратора (пароль спросит)")
    p.add_argument("login")
    p.add_argument("--role", default="owner")
    p.set_defaults(func=cmd_admin_create)
    p = adm.add_parser("set-password", help="Сменить пароль (и выйти на всех устройствах)")
    p.add_argument("login")
    p.set_defaults(func=cmd_admin_password)
    adm.add_parser("list", help="Список администраторов").set_defaults(func=cmd_admin_list)
    p = adm.add_parser("2fa-enable", help="Включить вход с кодом из приложения")
    p.add_argument("login")
    p.set_defaults(func=cmd_admin_2fa, enable=True)
    p = adm.add_parser("2fa-disable", help="Выключить 2FA")
    p.add_argument("login")
    p.set_defaults(func=cmd_admin_2fa, enable=False)

    args = parser.parse_args(argv)
    try:
        return asyncio.run(args.func(args))
    except ContentError as e:
        print("ОШИБКА:", file=sys.stderr)
        for m in e.messages:
            print("  - " + m, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

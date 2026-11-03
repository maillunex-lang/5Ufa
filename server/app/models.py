"""Таблицы базы данных.

Этап 1: версии контента (релизы) и каналы публикации.
  * content_releases — неизменяемый снимок всего контента (манифест).
  * content_channels — указатель «какой релиз сейчас видят игроки»:
      live — все игроки, test — тестовые аккаунты (черновик → тест → публикация).
    Публикация и откат = перестановка указателя, файлы не копируются.
"""
from datetime import datetime, timezone

from sqlalchemy import JSON, BigInteger, DateTime, ForeignKey, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class ContentRelease(Base):
    __tablename__ = "content_releases"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    # base — импорт из /content, patch — ZIP-патч из админки, manual — правка в админке
    source: Mapped[str] = mapped_column(String(32), nullable=False, default="base")
    comment: Mapped[str] = mapped_column(Text, nullable=False, default="")
    # Хэш содержимого: одинаковый контент -> одинаковый хэш (повторный импорт не создаёт дубль)
    content_hash: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    files_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_size: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    # Полный манифест (формат: shared/schemas/manifest.schema.json, без поля release)
    manifest: Mapped[dict] = mapped_column(JSON, nullable=False)


class ContentChannel(Base):
    __tablename__ = "content_channels"

    name: Mapped[str] = mapped_column(String(32), primary_key=True)
    release_id: Mapped[int] = mapped_column(ForeignKey("content_releases.id"), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=utcnow, onupdate=utcnow, nullable=False
    )

    release: Mapped[ContentRelease] = relationship(lazy="joined")


CHANNELS = ("live", "test")


# ---------------------------------------------------------------------------
# Этап 2: игроки и сессии
# ---------------------------------------------------------------------------
import uuid  # noqa: E402

from sqlalchemy import Boolean, Uuid  # noqa: E402


class Player(Base):
    """Аккаунт игрока. Сначала гость (без почты), потом можно привязать почту и пароль."""
    __tablename__ = "players"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    # Короткий номер для поддержки и админки: «Игрок #1024»
    number: Mapped[int] = mapped_column(Integer, unique=True, nullable=False)
    display_name: Mapped[str] = mapped_column(String(32), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    last_login_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    email: Mapped[str | None] = mapped_column(String(254), unique=True, nullable=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    # Тестовый аккаунт получает контент из канала test (черновик → тест → публикация)
    is_test: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    banned_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    ban_reason: Mapped[str] = mapped_column(Text, default="", nullable=False)

    @property
    def is_guest(self) -> bool:
        return self.email is None


class PlayerSession(Base):
    """Вход с устройства. Хранит хэш токена обновления (сам токен знает только клиент)."""
    __tablename__ = "player_sessions"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    device_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    refresh_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    client_version: Mapped[str] = mapped_column(String(32), default="", nullable=False)
    ip: Mapped[str] = mapped_column(String(64), default="", nullable=False)

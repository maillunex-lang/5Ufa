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

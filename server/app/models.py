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


class CampaignProgress(Base):
    __tablename__ = "campaign_progress"

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), primary_key=True)
    cleared: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    gold: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    hero_xp: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    gold_fraction: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    xp_fraction: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    crystal_fraction: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    essence_fraction: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    ore_fraction: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    equipment_fraction: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    elapsed_us: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, default=utcnow)
    quick_day: Mapped[str] = mapped_column(String(10), nullable=False, default="")
    quick_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


# ---------------------------------------------------------------------------
# Обновления приложения: APK хранится в хранилище контента (по SHA-256),
# GitHub Actions загружает каждую новую сборку на сервер.
# ---------------------------------------------------------------------------
class ClientRelease(Base):
    __tablename__ = "client_releases"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    version_code: Mapped[int] = mapped_column(Integer, unique=True, nullable=False)
    version_name: Mapped[str] = mapped_column(String(32), nullable=False)
    sha256: Mapped[str] = mapped_column(String(64), nullable=False)
    size: Mapped[int] = mapped_column(BigInteger, nullable=False)
    notes: Mapped[str] = mapped_column(Text, default="", nullable=False)
    # Обязательное обновление: старые версии не пустит в игру, пока не обновятся
    mandatory: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    # Выключенную версию игроки не получают (откат неудачной сборки)
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)


# ---------------------------------------------------------------------------
# Этап 5а: герои игрока, кошелёк, призыв
# ---------------------------------------------------------------------------
class PlayerHero(Base):
    """Экземпляр героя у игрока. Копии одного героя — отдельные строки (нужны для вознесения)."""
    __tablename__ = "player_heroes"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    hero_id: Mapped[str] = mapped_column(String(64), nullable=False)
    tier: Mapped[str] = mapped_column(String(32), nullable=False)
    level: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    crystal_slot: Mapped[int | None] = mapped_column(Integer, nullable=True)
    signature_level: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)


class WalletEntry(Base):
    __tablename__ = "player_wallet"

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), primary_key=True)
    code: Mapped[str] = mapped_column(String(48), primary_key=True)
    amount: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)


class SummonState(Base):
    __tablename__ = "summon_state"

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), primary_key=True)
    banner_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    pity: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class PlayerState(Base):
    __tablename__ = "player_state"

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), primary_key=True)
    starter_granted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    equipment_starter_granted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)


# ---------------------------------------------------------------------------
# Этап 5б: снаряжение
# ---------------------------------------------------------------------------
class PlayerItem(Base):
    """Предмет снаряжения в инвентаре. hero_instance_id — на ком надет (NULL — лежит в сумке)."""
    __tablename__ = "player_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    slot: Mapped[str] = mapped_column(String(32), nullable=False)
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    quality: Mapped[str] = mapped_column(String(32), nullable=False)
    faction: Mapped[str | None] = mapped_column(String(64), nullable=True)
    level: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    ore_spent: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    hero_instance_id: Mapped[int | None] = mapped_column(
        ForeignKey("player_heroes.id", ondelete="SET NULL"), nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)


# ---------------------------------------------------------------------------
# Этап 6: админка — администраторы, сессии, журнал действий, черновик контента
# ---------------------------------------------------------------------------
ADMIN_ROLES = ("owner", "editor", "moderator")


class AdminUser(Base):
    __tablename__ = "admin_users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    login: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    password_hash: Mapped[str] = mapped_column(String(256), nullable=False)
    # owner — всё; editor — контент; moderator — игроки и модерация (выдаются позже)
    role: Mapped[str] = mapped_column(String(16), nullable=False, default="owner")
    # Двухфакторная защита: заготовлена, включается командой `admin 2fa-enable`
    totp_secret: Mapped[str | None] = mapped_column(String(64), nullable=True)
    totp_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    disabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class AdminSession(Base):
    """Сессия админки. Хранится только хэш токена. Истекает после N дней без действий."""
    __tablename__ = "admin_sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    admin_id: Mapped[int] = mapped_column(ForeignKey("admin_users.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    ip: Mapped[str] = mapped_column(String(64), nullable=False, default="")
    user_agent: Mapped[str] = mapped_column(String(256), nullable=False, default="")


class AdminAudit(Base):
    """Журнал всех действий администратора (и неудачных попыток входа)."""
    __tablename__ = "admin_audit"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False, index=True)
    admin_id: Mapped[int | None] = mapped_column(ForeignKey("admin_users.id", ondelete="SET NULL"), nullable=True)
    login: Mapped[str] = mapped_column(String(64), nullable=False, default="")
    action: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    summary: Mapped[str] = mapped_column(Text, nullable=False, default="")
    details: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)
    ip: Mapped[str] = mapped_column(String(64), nullable=False, default="")


class DraftFile(Base):
    """Общий черновик контента: файл, изменённый относительно базового релиза.
    sha256 = NULL — файл удалён в черновике."""
    __tablename__ = "content_draft_files"

    path: Mapped[str] = mapped_column(String(512), primary_key=True)
    sha256: Mapped[str | None] = mapped_column(String(64), nullable=True)
    size: Mapped[int] = mapped_column(BigInteger, nullable=False, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)
    admin_id: Mapped[int | None] = mapped_column(ForeignKey("admin_users.id", ondelete="SET NULL"), nullable=True)


class DraftMeta(Base):
    """Одна строка (id=1): от какого релиза начат черновик."""
    __tablename__ = "content_draft_meta"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    base_release_id: Mapped[int | None] = mapped_column(ForeignKey("content_releases.id"), nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)


# ---------------------------------------------------------------------------
# Этап 6в-2: скины героев
# ---------------------------------------------------------------------------
class PlayerSkin(Base):
    """Скин, полученный игроком (обычный и бесплатные скины есть у всех без записи)."""
    __tablename__ = "player_skins"

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), primary_key=True)
    hero_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    skin_id: Mapped[str] = mapped_column(String(32), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utcnow, nullable=False)


class PlayerSkinChoice(Base):
    """Какой скин игрок выбрал для героя (для всех копий героя)."""
    __tablename__ = "player_skin_choice"

    player_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), primary_key=True)
    hero_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    skin_id: Mapped[str] = mapped_column(String(32), nullable=False)

"""Настройки сервера. Все значения берутся из переменных окружения (.env на VPS)."""
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

_REPO_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=None, extra="ignore")

    database_url: str = "postgresql+asyncpg://ufagame:ufagame@localhost:5432/ufagame"
    redis_url: str = "redis://localhost:6379/0"
    secret_key: str = "dev-secret-change-me"
    log_level: str = "INFO"
    git_sha: str = "dev"
    public_domain: str = ""
    # Путь на домене, под которым работает сервер (например /games/server).
    # Внешний веб-сервер убирает этот префикс перед отправкой запроса к нам,
    # но в ссылках, которые получает клиент, он должен быть.
    public_path_prefix: str = ""
    # Токен, с которым GitHub Actions загружает новые APK (пусто — загрузка выключена)
    client_upload_token: str = ""
    # Максимальный размер загружаемого APK
    client_max_apk_mb: int = 95

    # Хранилище файлов контента (адресация по SHA-256)
    content_store_dir: Path = _REPO_ROOT / "data" / "content-store"
    # Папка со схемами JSON (/shared) и базовым контентом (/content)
    shared_dir: Path = _REPO_ROOT / "shared"
    base_content_dir: Path = _REPO_ROOT / "content"

    # URL-префикс, по которому Nginx раздаёт файлы контента
    content_files_url: str = "/content/files/"

    @property
    def path_prefix(self) -> str:
        p = self.public_path_prefix.strip().rstrip("/")
        return "/" + p.lstrip("/") if p else ""

    @property
    def public_content_files_url(self) -> str:
        return self.path_prefix + self.content_files_url


@lru_cache
def get_settings() -> Settings:
    return Settings()

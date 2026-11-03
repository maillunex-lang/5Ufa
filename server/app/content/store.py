"""Хранилище файлов контента, адресуемое по SHA-256.

Файл с хэшем abcdef... лежит в  <store>/files/ab/abcdef...
Nginx отдаёт его по URL      /content/files/ab/abcdef...

Плюсы: один и тот же файл хранится один раз; файлы неизменяемы (можно кэшировать
навсегда); откат к старой версии мгновенный — старые файлы никуда не деваются.
"""
from __future__ import annotations

import hashlib
import os
import shutil
import tempfile
from pathlib import Path


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


class ContentStore:
    def __init__(self, root: Path):
        self.root = Path(root)
        self.files_dir = self.root / "files"

    @staticmethod
    def relative_url(sha: str) -> str:
        return f"{sha[:2]}/{sha}"

    def path_for(self, sha: str) -> Path:
        return self.files_dir / sha[:2] / sha

    def has(self, sha: str) -> bool:
        return self.path_for(sha).is_file()

    def put_file(self, src: Path, sha: str | None = None) -> str:
        sha = sha or sha256_file(src)
        dest = self.path_for(sha)
        if dest.is_file():
            return sha
        dest.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=dest.parent, prefix=".tmp_")
        try:
            with os.fdopen(fd, "wb") as output, src.open("rb") as input_file:
                shutil.copyfileobj(input_file, output, length=1024 * 1024)
            os.chmod(tmp, 0o644)
            os.replace(tmp, dest)
        except BaseException:
            Path(tmp).unlink(missing_ok=True)
            raise
        return sha

    def put_bytes(self, data: bytes, sha: str | None = None) -> str:
        sha = sha or sha256_bytes(data)
        dest = self.path_for(sha)
        if dest.is_file():
            return sha
        dest.parent.mkdir(parents=True, exist_ok=True)
        # Атомарная запись: сначала во временный файл, потом переименование
        fd, tmp = tempfile.mkstemp(dir=dest.parent, prefix=".tmp_")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data)
            os.chmod(tmp, 0o644)
            os.replace(tmp, dest)
        except BaseException:
            Path(tmp).unlink(missing_ok=True)
            raise
        return sha

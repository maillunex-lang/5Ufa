#!/usr/bin/env python3
"""Справочник промптов для ИИ (/patch-prompts): по одному файлу на раздел админки.

Текст строится тем же кодом, что кнопка «Промпт для ИИ» в админке (server/app/admin/sections.py),
по базовому контенту из /content. Запуск из корня репозитория (нужны зависимости сервера):
    cd server && python ../scripts/gen_patch_prompts.py
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "server"))

from app.admin import sections as sec  # noqa: E402
from app.content.validation import glob_to_regex  # noqa: E402


class DirWorkspace:
    """Workspace поверх папки /content (без базы и хранилища)."""

    def __init__(self, root: Path):
        self.root = root
        self._files = {p.relative_to(root).as_posix(): "" for p in root.rglob("*") if p.is_file()}

    def files(self):
        return self._files

    def exists(self, path):
        return path in self._files

    def read_bytes(self, path):
        return (self.root / path).read_bytes()

    def read_json(self, path):
        return json.loads(self.read_bytes(path).decode("utf-8"))

    def glob(self, pattern):
        rx = glob_to_regex(pattern)
        return sorted(p for p in self._files if rx.match(p))


def main():
    ws = DirWorkspace(ROOT / "content")
    out = ROOT / "patch-prompts"
    for sid, s in sec.sections().items():
        text = sec.ai_prompt(ws, s)
        (out / f"{sid}.md").write_text(f"# Промпт для ИИ: {s['title']}\n\n"
                                       "Скопируйте текст ниже в ИИ-ассистента. Актуальная версия (с вашими правками) — "
                                       "кнопка «Промпт для ИИ» в разделе админки.\n\n````text\n" + text + "\n````\n",
                                       encoding="utf-8")
        print(f"patch-prompts/{sid}.md")


if __name__ == "__main__":
    main()

"""Чтение опубликованного контента на сервере (формулы боя, герои, отряды).

Сервер использует тот же релиз, что получает игрок: тестовые аккаунты — канал test,
остальные — live. Данные кэшируются по номеру релиза.
"""
from __future__ import annotations

import json
from functools import lru_cache

from app.content.releases import get_store
from app.content.validation import glob_to_regex


class ContentView:
    def __init__(self, release_id: int, manifest: dict):
        self.release_id = release_id
        self.files: dict[str, str] = {}
        for pkg in manifest.get("packages", []):
            for f in pkg["files"]:
                self.files[f["path"]] = f["sha256"]
        self._json_cache: dict[str, object] = {}

    def has(self, path: str) -> bool:
        return path in self.files

    def json(self, path: str):
        if path not in self._json_cache:
            sha = self.files.get(path)
            if sha is None:
                raise KeyError(f"В контенте нет файла {path}")
            self._json_cache[path] = json.loads(get_store().path_for(sha).read_text(encoding="utf-8"))
        return self._json_cache[path]

    def glob(self, pattern: str) -> list[str]:
        rx = glob_to_regex(pattern)
        return sorted(p for p in self.files if rx.match(p))

    # --- Игровые данные ---------------------------------------------------------

    def battle_config(self) -> dict:
        return self.json("config/battle.json")

    def factions(self) -> dict[str, dict]:
        return {f["id"]: f for f in self.json("factions/factions.json")["factions"]}

    def heroes(self) -> dict[str, dict]:
        out = {}
        for p in self.glob("heroes/*/hero.json"):
            h = self.json(p)
            out[h["id"]] = h
        return out

    def teams(self) -> dict[str, dict]:
        out = {}
        for p in self.glob("battle/*teams.json"):
            for t in self.json(p)["teams"]:
                out[t["id"]] = t
        return out


@lru_cache(maxsize=8)
def _cached(release_id: int, manifest_key: str, manifest_json: str) -> ContentView:
    return ContentView(release_id, json.loads(manifest_json))


def view_for(release) -> ContentView:
    return _cached(release.id, release.content_hash, json.dumps(release.manifest))

"""Сборка манифеста контента из папки (базовый контент /content или распакованный патч).

Структура папки:
    packages.json         — список пакетов и какие файлы в них входят (маски путей)
    <любые файлы>         — PNG/WebP/OGG/JSON и т.д.

Результат — манифест (см. shared/schemas/manifest.schema.json): для каждого пакета
список файлов с путём, размером и SHA-256. Клиент сравнивает хэши и качает
только изменённые файлы.
"""
from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path

from app.content.store import ContentStore, sha256_file
from app.content.validation import ContentError, SchemaRegistry, glob_to_regex

MANIFEST_SCHEMA_VERSION = 1

# Разрешённые открытые форматы контента
ALLOWED_EXTENSIONS = {
    ".png", ".webp", ".jpg", ".jpeg",       # графика
    ".ogg", ".wav",                          # звук и музыка
    ".json",                                 # данные, скелеты, анимации
    ".ttf", ".otf",                          # шрифты
    ".txt",                                  # тексты (лицензии и т.п.)
    ".glb",                                  # встроенная модель glTF 2.0
}
# Файлы, которые не попадают в манифест (служебные)
SKIP_NAMES = {"packages.json", "README.md", ".gitkeep", ".DS_Store", "Thumbs.db"}


@dataclass
class PackageDef:
    id: str
    title: str
    required: bool
    priority: int
    include: list[str]
    patterns: list = field(default_factory=list)


@dataclass
class BuildResult:
    manifest: dict
    content_hash: str
    files_count: int
    total_size: int


def _load_packages(content_dir: Path, schemas: SchemaRegistry) -> tuple[dict, list[PackageDef]]:
    path = content_dir / "packages.json"
    if not path.is_file():
        raise ContentError(["Не найден файл packages.json — в нём описываются пакеты загрузки"])
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        raise ContentError([f"packages.json: ошибка JSON в строке {e.lineno}, столбце {e.colno}: {e.msg}"])
    errors = schemas.validate(data, "content-packages.schema.json", "packages.json")
    if errors:
        raise ContentError(errors)
    defs = []
    for p in data["packages"]:
        d = PackageDef(
            id=p["id"], title=p["title"], required=p["required"],
            priority=p.get("priority", 100), include=p["include"],
        )
        d.patterns = [glob_to_regex(g) for g in d.include]
        defs.append(d)
    ids = [d.id for d in defs]
    dupes = {i for i in ids if ids.count(i) > 1}
    if dupes:
        raise ContentError([f"packages.json: пакет «{i}» описан несколько раз" for i in sorted(dupes)])
    return data, defs


def build_manifest(content_dir: Path, store: ContentStore | None, schemas: SchemaRegistry) -> BuildResult:
    """Проверить контент, (если store задан) положить файлы в хранилище и вернуть манифест."""
    content_dir = Path(content_dir)
    meta, defs = _load_packages(content_dir, schemas)
    errors: list[str] = []
    files_by_pkg: dict[str, list[dict]] = {d.id: [] for d in defs}

    for path in sorted(content_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(content_dir).as_posix()
        if path.name in SKIP_NAMES or any(part.startswith(".") for part in rel.split("/")):
            continue
        ext = path.suffix.lower()
        if ext not in ALLOWED_EXTENSIONS:
            errors.append(f"{rel}: неподдерживаемый формат «{ext}». Разрешены: {', '.join(sorted(ALLOWED_EXTENSIONS))}")
            continue
        if ext == ".glb":
            from app.models3d.inspect_glb import MAX_GLB_BYTES, ModelError, inspect_glb, size_limit_message
            try:
                if path.stat().st_size > MAX_GLB_BYTES:
                    raise ModelError(size_limit_message(path.stat().st_size))
                inspect_glb(path.read_bytes())
            except (ModelError, OSError) as exc:
                errors.append(f"{rel}: {exc}")
                continue
        if ext == ".json":
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
            except UnicodeDecodeError:
                errors.append(f"{rel}: файл должен быть в кодировке UTF-8")
                continue
            except json.JSONDecodeError as e:
                errors.append(f"{rel}: ошибка JSON в строке {e.lineno}, столбце {e.colno}: {e.msg}")
                continue
            schema = schemas.schema_for_path(rel)
            if schema:
                doc_errors = schemas.validate(data, schema, rel)
                errors.extend(doc_errors)
                if not doc_errors and schema == "hero.schema.json":
                    errors.extend(_validate_hero_models(content_dir, rel, data))

        pkg = next((d for d in defs if any(p.match(rel) for p in d.patterns)), None)
        if pkg is None:
            errors.append(f"{rel}: файл не входит ни в один пакет (добавьте маску в packages.json)")
            continue
        sha = store.put_file(path) if store else sha256_file(path)
        files_by_pkg[pkg.id].append({"path": rel, "size": path.stat().st_size, "sha256": sha})

    if errors:
        raise ContentError(errors)

    packages = []
    total_size = 0
    files_count = 0
    for d in sorted(defs, key=lambda d: (d.priority, d.id)):
        files = files_by_pkg[d.id]
        size = sum(f["size"] for f in files)
        version = hashlib.sha256(
            "\n".join(f"{f['path']}:{f['sha256']}" for f in files).encode()
        ).hexdigest()[:16]
        packages.append({
            "id": d.id,
            "title": d.title,
            "required": d.required,
            "priority": d.priority,
            "version": version,
            "size": size,
            "files": files,
        })
        total_size += size
        files_count += len(files)

    content_hash = hashlib.sha256(
        "\n".join(f"{p['id']}:{p['version']}" for p in packages).encode()
        + json.dumps(meta.get("min_client_version", "0.0.0")).encode()
    ).hexdigest()

    manifest = {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "content_hash": content_hash,
        "min_client_version": meta.get("min_client_version", "0.0.0"),
        "total_size": total_size,
        "packages": packages,
        # Описание пакетов (packages.json) — нужно админке, чтобы собрать следующий релиз из черновика.
        # Клиенту не отдаётся (см. releases.public_manifest).
        "packages_def": meta,
    }
    return BuildResult(manifest=manifest, content_hash=content_hash, files_count=files_count, total_size=total_size)


def _validate_hero_models(content_dir: Path, hero_path: str, hero: dict) -> list[str]:
    """Проверить ссылки 3D до выпуска релиза, включая правки из формы, JSON и ZIP."""
    from pathlib import PurePosixPath

    from app.models3d.inspect_glb import MAX_GLB_BYTES, ModelError, inspect_glb, require_owned_model_path, size_limit_message

    errors = []
    hero_dir = Path(hero_path).parent.as_posix()
    kinds = [("", hero.get("model_3d"))]
    kinds.extend((skin["id"], skin.get("model_3d")) for skin in hero.get("skins", []))
    root = content_dir.resolve()
    for skin, model in kinds:
        if not model:
            continue
        prefix = hero_dir + (f"/skins/{skin}" if skin else "") + "/models3d/"
        cache = {}

        def report(path):
            require_owned_model_path(path, prefix)
            if path not in cache:
                candidate = root.joinpath(*PurePosixPath(path).parts)
                parent = candidate.parent.resolve()
                if not parent.is_relative_to(root) or not candidate.is_file():
                    raise ModelError("файл модели отсутствует")
                if candidate.stat().st_size > MAX_GLB_BYTES:
                    raise ModelError(size_limit_message(candidate.stat().st_size))
                cache[path] = inspect_glb(candidate.read_bytes())
            return cache[path]

        try:
            main = report(model["file"])
            if not main["mesh_instances"]:
                raise ModelError("основной GLB не содержит отображаемой сетки")
            for event, anim in model.get("animations", {}).items():
                if anim["clip"] not in report(anim["file"])["animations"]:
                    raise ModelError(f"анимация «{event}» не найдена")
            for name, anchor in model.get("anchors", {}).items():
                if anchor["bone"] != "@root" and anchor["bone"] not in main["bones"]:
                    raise ModelError(f"кость точки «{name}» не найдена")
        except (ModelError, OSError, KeyError) as exc:
            errors.append(f"{hero_path}: 3D{' скина ' + skin if skin else ''}: {exc}")
    return errors

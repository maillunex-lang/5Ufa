"""Разделы админки (shared/admin/sections.json): объекты раздела, ZIP-патчи, выгрузка, промпт для ИИ.

Формат патча — docs/patch-format.md, схема patch.json — shared/schemas/patch.schema.json.
"""
from __future__ import annotations

import copy
import io
import json
import zipfile
from functools import lru_cache
from pathlib import PurePosixPath

from app.admin.draft import PACKAGES, Workspace, check_path, validate_file
from app.config import get_settings
from app.content.validation import ContentError, get_schema_registry, glob_to_regex

MAX_PATCH_FILES = 2000


@lru_cache
def sections() -> dict[str, dict]:
    data = json.loads((get_settings().shared_dir / "admin" / "sections.json").read_text(encoding="utf-8"))
    return {s["id"]: s for s in data["sections"]}


def get_section(section_id: str) -> dict:
    s = sections().get(section_id)
    if s is None:
        raise ContentError([f"Неизвестный раздел «{section_id}». Есть: {', '.join(sections())}"])
    return s


def _match(patterns: list[str], path: str) -> bool:
    return any(glob_to_regex(p).match(path) for p in patterns)


def section_files(ws: Workspace, s: dict) -> dict[str, list[str]]:
    files = ws.files()
    return {"files": sorted(p for p in files if _match(s["files"], p)),
            "assets": sorted(p for p in files if _match(s.get("assets", []), p) and not p.endswith(".json"))}


def section_of(path: str) -> str | None:
    for sid, s in sections().items():
        if _match(s["files"], path) or _match(s.get("assets", []), path):
            return sid
    return None


# --- Объекты раздела --------------------------------------------------------------

def _path_pattern(objects: dict) -> tuple[str, str]:
    prefix, suffix = objects["path"].split("{id}")
    return prefix, suffix


def list_objects(ws: Workspace, s: dict) -> list[dict]:
    o = s["objects"]
    out = []
    if o["kind"] == "single":
        if ws.exists(o["file"]):
            out.append({"id": o["id"], "file": o["file"], "title": s["title"]})
    elif o["kind"] == "array_in_file":
        if ws.exists(o["file"]):
            for item in ws.read_json(o["file"]).get(o["key"], []):
                out.append({"id": item.get("id"), "file": o["file"], "title": item.get("name") or item.get("title") or item.get("id")})
    else:
        prefix, suffix = _path_pattern(o)
        for p in sorted(ws.files()):
            if p.startswith(prefix) and p.endswith(suffix):
                oid = p[len(prefix):len(p) - len(suffix)]
                if "/" in oid:
                    continue
                title = oid
                try:
                    d = ws.read_json(p)
                    title = d.get("name") or d.get("title") or oid
                except (ValueError, KeyError):
                    pass
                out.append({"id": oid, "file": p, "title": title})
    return out


def get_object(ws: Workspace, s: dict, oid: str):
    o = s["objects"]
    if o["kind"] == "single":
        return ws.read_json(o["file"]) if oid == o["id"] and ws.exists(o["file"]) else None
    if o["kind"] == "array_in_file":
        if not ws.exists(o["file"]):
            return None
        return next((x for x in ws.read_json(o["file"]).get(o["key"], []) if x.get("id") == oid), None)
    path = o["path"].replace("{id}", oid)
    return ws.read_json(path) if ws.exists(path) else None


def deep_merge(base, patch):
    """Объекты сливаются по ключам, списки и значения заменяются целиком."""
    if isinstance(base, dict) and isinstance(patch, dict):
        out = copy.deepcopy(base)
        for k, v in patch.items():
            out[k] = deep_merge(out.get(k), v) if k in out else copy.deepcopy(v)
        return out
    return copy.deepcopy(patch)


# --- ZIP-патчи --------------------------------------------------------------------

class PatchPlan:
    """Результат разбора патча: файлы, которые запишутся в черновик, и понятный список изменений."""

    def __init__(self):
        self.writes: dict[str, bytes] = {}
        self.deletes: set[str] = set()
        self.changes: list[dict] = []
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.patch: dict = {}


def _read_zip(data: bytes) -> tuple[dict, dict[str, bytes]]:
    limit = get_settings().admin_patch_max_mb * 1024 * 1024
    if len(data) > limit:
        raise ContentError([f"Архив больше {get_settings().admin_patch_max_mb} МБ"])
    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile:
        raise ContentError(["Это не ZIP-архив или архив повреждён"])
    names = [n for n in zf.namelist() if not n.endswith("/")]
    if len(names) > MAX_PATCH_FILES:
        raise ContentError([f"В архиве больше {MAX_PATCH_FILES} файлов"])
    total = sum(i.file_size for i in zf.infolist())
    if total > limit * 3:
        raise ContentError(["Распакованный архив слишком большой"])
    # Архив, упакованный вместе с папкой: patch.json лежит в одной папке верхнего уровня
    root = ""
    if "patch.json" not in names:
        cands = [n for n in names if n.endswith("/patch.json") and n.count("/") == 1]
        if len(cands) != 1:
            raise ContentError(["В корне архива нет patch.json (см. docs/patch-format.md)"])
        root = cands[0][: -len("patch.json")]
    try:
        patch = json.loads(zf.read(root + "patch.json").decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise ContentError([f"patch.json: ошибка JSON — {e}"])
    files: dict[str, bytes] = {}
    for n in names:
        rel = n[len(root):]
        if not rel.startswith("files/"):
            continue
        p = PurePosixPath(rel[len("files/"):]).as_posix()
        files[check_path(p)] = zf.read(n)
    return patch, files


def plan_patch(ws: Workspace, data: bytes) -> PatchPlan:
    plan = PatchPlan()
    try:
        patch, files = _read_zip(data)
    except ContentError as e:
        plan.errors.extend(e.messages)
        return plan
    plan.patch = patch
    reg = get_schema_registry()
    plan.errors.extend(reg.validate(patch, "patch.schema.json", "patch.json"))
    if plan.errors:
        return plan
    try:
        s = get_section(patch["section"])
    except ContentError as e:
        plan.errors.extend(e.messages)
        return plan
    o = s["objects"]
    arrays: dict[str, dict] = {}  # файл массива -> текущий документ (накапливаем правки)
    used_files: set[str] = set()

    def doc_for(path):
        if path not in arrays:
            arrays[path] = ws.read_json(path) if ws.exists(path) else {o.get("key", "items"): []}
        return arrays[path]

    for i, op in enumerate(patch["operations"], 1):
        kind, oid, data_ = op["op"], op.get("id"), op.get("data")
        where = f"операция {i} ({kind} {oid or op.get('path', '')})"
        for f in op.get("files", []):
            if f not in files:
                plan.errors.append(f"{where}: файла files/{f} нет в архиве")
            used_files.add(f)
        if kind in ("put_file", "delete_file"):
            path = op["path"]
            if kind == "put_file":
                if path not in files:
                    plan.errors.append(f"{where}: файла files/{path} нет в архиве")
                else:
                    plan.writes[path] = files[path]
                    used_files.add(path)
                    plan.changes.append({"op": "update" if ws.exists(path) else "add", "path": path, "object": None})
            else:
                if not ws.exists(path):
                    plan.errors.append(f"{where}: файла {path} нет в контенте")
                plan.deletes.add(path)
                plan.changes.append({"op": "delete", "path": path, "object": None})
            continue
        current = get_object(ws, s, oid) if not (o["kind"] == "array_in_file" and o["file"] in arrays) else \
            next((x for x in doc_for(o["file"]).get(o["key"], []) if x.get("id") == oid), None)
        if kind == "add" and current is not None:
            plan.errors.append(f"{where}: объект «{oid}» уже есть — используйте update")
            continue
        if kind in ("update", "delete") and current is None:
            plan.errors.append(f"{where}: объекта «{oid}» нет в разделе «{s['title']}»")
            continue
        new = data_ if kind == "add" else deep_merge(current, data_) if kind == "update" else None
        if o["kind"] == "single":
            path = o["file"]
            if kind == "delete":
                plan.errors.append(f"{where}: этот раздел — один объект, его можно только изменить")
                continue
            plan.writes[path] = _dump(new)
        elif o["kind"] == "array_in_file":
            doc = doc_for(o["file"])
            items = doc.setdefault(o["key"], [])
            idx = next((k for k, x in enumerate(items) if x.get("id") == oid), None)
            if kind == "delete":
                items.pop(idx)
            elif idx is None:
                items.append({**new, "id": oid} if isinstance(new, dict) else new)
            else:
                items[idx] = new
            path = o["file"]
        else:
            path = o["path"].replace("{id}", oid)
            if kind == "delete":
                plan.deletes.add(path)
                if "dir" in o:
                    d = o["dir"].replace("{id}", oid)
                    plan.deletes.update(p for p in ws.files() if p.startswith(d))
            else:
                plan.writes[path] = _dump(new)
        plan.changes.append({"op": kind, "path": path, "object": oid,
                             "fields": sorted(data_.keys()) if kind == "update" and isinstance(data_, dict) else None})
        for f in op.get("files", []):
            if f in files:
                plan.writes[f] = files[f]
                plan.changes.append({"op": "update" if ws.exists(f) else "add", "path": f, "object": oid})
    for path, doc in arrays.items():
        plan.writes[path] = _dump(doc)
    extra = sorted(set(files) - used_files)
    if extra:
        plan.warnings.append("Эти файлы есть в архиве, но не указаны ни в одной операции и будут пропущены: "
                             + ", ".join(extra[:20]) + (" …" if len(extra) > 20 else ""))
    # Проверка по схемам всего, что запишется
    for path, data_bytes in plan.writes.items():
        plan.errors.extend(validate_file(path, data_bytes))
    # Ссылки на удаляемые объекты из оставшегося контента
    deleted_ids = [c["object"] for c in plan.changes if c["op"] == "delete" and c.get("object")]
    if deleted_ids:
        plan.errors.extend(find_references(ws, plan, deleted_ids))
    return plan


def _dump(obj) -> bytes:
    return (json.dumps(obj, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def find_references(ws: Workspace, plan: PatchPlan, ids: list[str]) -> list[str]:
    """Удалять объект нельзя, если на него ссылаются другие данные (по строковому значению id)."""
    errors = []
    targets = set(ids)

    def walk(v):
        if isinstance(v, str):
            if v in targets:
                yield v
        elif isinstance(v, dict):
            for k, x in v.items():
                if k == "id":
                    continue
                yield from walk(x)
        elif isinstance(v, list):
            for x in v:
                yield from walk(x)

    for path in ws.files():
        if not path.endswith(".json") or path in plan.deletes or path == PACKAGES:
            continue
        try:
            doc = json.loads(plan.writes[path]) if path in plan.writes else ws.read_json(path)
        except (ValueError, KeyError):
            continue
        for ref in sorted(set(walk(doc))):
            errors.append(f"Нельзя удалить «{ref}»: на него ссылается {path}")
    return errors


def export_section(ws: Workspace, s: dict) -> bytes:
    """ZIP раздела в формате патча: все объекты как add + все файлы ресурсов раздела."""
    ops = []
    o = s["objects"]
    files = section_files(ws, s)
    for obj in list_objects(ws, s):
        data = get_object(ws, s, obj["id"])
        op = {"op": "add" if o["kind"] != "single" else "update", "id": obj["id"], "data": data}
        if o["kind"] == "file_per_object" and "dir" in o:
            d = o["dir"].replace("{id}", obj["id"])
            op["files"] = [p for p in files["assets"] if p.startswith(d)]
        ops.append(op)
    used = {f for op in ops for f in op.get("files", [])}
    for p in files["assets"]:
        if p not in used:
            ops.append({"op": "put_file", "path": p})
    for p in files["files"]:
        if not any(p == x["file"] for x in list_objects(ws, s)) and o["kind"] != "file_per_object":
            ops.append({"op": "put_file", "path": p})
    patch = {"id": f"export-{s['id']}", "format_version": 1, "section": s["id"],
             "description": f"Выгрузка раздела «{s['title']}»", "operations": ops or [{"op": "update", "id": "none", "data": {}}]}
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("patch.json", json.dumps(patch, ensure_ascii=False, indent=2))
        for op in ops:
            for f in op.get("files", []) + ([op["path"]] if op["op"] == "put_file" else []):
                zf.writestr("files/" + f, ws.read_bytes(f))
    return buf.getvalue()


def ai_prompt(ws: Workspace, s: dict) -> str:
    """Готовый промпт для ИИ: задача, схема раздела, пример данных, правила патча."""
    reg = get_schema_registry()
    shared = get_settings().shared_dir / "schemas"
    files = section_files(ws, s)["files"]
    schemas = sorted({reg.schema_for_path(p) for p in files if reg.schema_for_path(p)})
    objs = list_objects(ws, s)
    example = get_object(ws, s, objs[0]["id"]) if objs else None
    parts = [
        f"Ты помогаешь наполнять контент мобильной игры (AFK RPG по мотивам башкирских легенд). Раздел: «{s['title']}» ({s['id']}).",
        "Сделай ZIP-патч для админки. Структура архива:\n  patch.json — описание патча\n  files/<путь в контенте> — картинки и другие файлы",
        "patch.json: {\"id\": \"<латиница-и-дефисы>\", \"format_version\": 1, \"section\": \"" + s["id"] + "\", "
        "\"description\": \"что меняется\", \"operations\": [ ... ]}",
        "Операции: add (новый объект, data — полный объект), update (data — только изменяемые поля; объекты сливаются, "
        "списки заменяются целиком), delete (удалить объект), put_file (положить файл: {\"op\":\"put_file\",\"path\":\"...\"}), "
        "delete_file. Для add/update можно указать files — пути картинок из архива.",
        "Правила: id и пути — латиница в нижнем регистре, цифры, _ - . /; JSON в UTF-8; графика PNG/WebP, звук OGG. Тексты — на русском.",
        f"Устройство объектов раздела: {json.dumps(s['objects'], ensure_ascii=False)}",
        "Текущие объекты: " + ", ".join(f"{x['id']} ({x['title']})" for x in objs[:60]),
    ]
    for name in schemas:
        try:
            parts.append(f"JSON Schema {name}:\n" + (shared / name).read_text(encoding="utf-8"))
        except OSError:
            pass
    if example is not None:
        parts.append("Пример объекта из игры:\n" + json.dumps(example, ensure_ascii=False, indent=2)[:12000])
    parts.append("Верни только готовый patch.json и список файлов, которые нужно положить в files/.")
    return "\n\n".join(parts)

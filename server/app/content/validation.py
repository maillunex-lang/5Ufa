"""Проверка контента по JSON Schema из /shared с понятными сообщениями на русском."""
from __future__ import annotations

import json
import re
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError
from referencing import Registry, Resource

from app.config import get_settings


class ContentError(Exception):
    """Ошибка контента. В args[0] — список строк-сообщений на русском."""

    def __init__(self, messages: list[str]):
        super().__init__(messages)
        self.messages = messages

    def __str__(self) -> str:
        return "\n".join(self.messages)


@dataclass(frozen=True)
class SchemaRule:
    pattern: re.Pattern[str]
    schema: str


def glob_to_regex(pattern: str) -> re.Pattern[str]:
    """Простые маски путей: ** — любые папки, * — любые символы кроме /, ? — один символ."""
    out = []
    i = 0
    while i < len(pattern):
        c = pattern[i]
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
            continue
        if pattern.startswith("**", i):
            out.append(".*")
            i += 2
            continue
        if c == "*":
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    return re.compile("^" + "".join(out) + "$")


class SchemaRegistry:
    def __init__(self, shared_dir: Path):
        self.schemas_dir = shared_dir / "schemas"
        self.schemas: dict[str, dict] = {}
        resources = []
        for path in sorted(self.schemas_dir.glob("*.schema.json")):
            schema = json.loads(path.read_text(encoding="utf-8"))
            self.schemas[path.name] = schema
            resources.append((schema["$id"], Resource.from_contents(schema)))
        self.registry = Registry().with_resources(resources)
        reg = json.loads((self.schemas_dir / "registry.json").read_text(encoding="utf-8"))
        self.rules = [SchemaRule(glob_to_regex(r["pattern"]), r["schema"]) for r in reg["content_files"]]

    def validator(self, schema_name: str) -> Draft202012Validator:
        if schema_name not in self.schemas:
            raise ContentError([f"Схема «{schema_name}» не найдена в shared/schemas"])
        return Draft202012Validator(self.schemas[schema_name], registry=self.registry)

    def schema_for_path(self, rel_path: str) -> str | None:
        for rule in self.rules:
            if rule.pattern.match(rel_path):
                return rule.schema
        return None

    def validate(self, data: object, schema_name: str, where: str) -> list[str]:
        errors = sorted(self.validator(schema_name).iter_errors(data), key=lambda e: list(e.absolute_path))
        return [f"{where}: {humanize_error(e)}" for e in errors]


@lru_cache
def get_schema_registry() -> SchemaRegistry:
    return SchemaRegistry(get_settings().shared_dir)


_TYPE_NAMES = {
    "object": "объект",
    "array": "список",
    "string": "строка",
    "integer": "целое число",
    "number": "число",
    "boolean": "да/нет (true/false)",
    "null": "пусто (null)",
}


def _field(error: ValidationError) -> str:
    parts = [str(p) for p in error.absolute_path]
    return "поле «" + ".".join(parts) + "»" if parts else "документ"


def humanize_error(error: ValidationError) -> str:
    """Перевести ошибку jsonschema в понятное сообщение на русском."""
    v = error.validator
    val = error.validator_value
    field = _field(error)
    if v == "required":
        missing = [r for r in val if isinstance(error.instance, dict) and r not in error.instance]
        return f"{field}: не заполнено обязательное поле «{', '.join(missing)}»"
    if v == "type":
        types = val if isinstance(val, list) else [val]
        return f"{field}: ожидается {' или '.join(_TYPE_NAMES.get(t, t) for t in types)}"
    if v == "enum":
        return f"{field}: допустимые значения — {', '.join(map(str, val))}"
    if v == "const":
        return f"{field}: должно быть равно {val!r}"
    if v == "minimum":
        return f"{field}: значение должно быть не меньше {val}"
    if v == "maximum":
        return f"{field}: значение должно быть не больше {val}"
    if v == "exclusiveMinimum":
        return f"{field}: значение должно быть больше {val}"
    if v == "minLength":
        return f"{field}: слишком короткий текст (минимум {val} симв.)"
    if v == "maxLength":
        return f"{field}: слишком длинный текст (максимум {val} симв.)"
    if v == "minItems":
        return f"{field}: должно быть не меньше {val} элементов"
    if v == "maxItems":
        return f"{field}: должно быть не больше {val} элементов"
    if v == "pattern":
        return f"{field}: неверный формат (значение «{error.instance}» не подходит под шаблон {val})"
    if v == "additionalProperties":
        extra = []
        if isinstance(error.instance, dict):
            allowed = set(error.schema.get("properties", {}))
            extra = [k for k in error.instance if k not in allowed]
        return f"{field}: лишние поля, которых нет в схеме: {', '.join(extra)}"
    if v == "uniqueItems":
        return f"{field}: элементы списка повторяются"
    return f"{field}: {error.message}"

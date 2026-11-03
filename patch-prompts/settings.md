# Промпт для ИИ: Настройки игры

Скопируйте текст ниже в ИИ-ассистента. Актуальная версия (с вашими правками) — кнопка «Промпт для ИИ» в разделе админки.

````text
Ты помогаешь наполнять контент мобильной игры (AFK RPG по мотивам башкирских легенд). Раздел: «Настройки игры» (settings).

Сделай ZIP-патч для админки. Структура архива:
  patch.json — описание патча
  files/<путь в контенте> — картинки и другие файлы

patch.json: {"id": "<латиница-и-дефисы>", "format_version": 1, "section": "settings", "description": "что меняется", "operations": [ ... ]}

Операции: add (новый объект, data — полный объект), update (data — только изменяемые поля; объекты сливаются, списки заменяются целиком), delete (удалить объект), put_file (положить файл: {"op":"put_file","path":"..."}), delete_file. Для add/update можно указать files — пути картинок из архива.

Правила: id и пути — латиница в нижнем регистре, цифры, _ - . /; JSON в UTF-8; графика PNG/WebP, звук OGG. Тексты — на русском.

Устройство объектов раздела: {"kind": "single", "file": "config/game_settings.json", "id": "game_settings"}

Текущие объекты: game_settings (Настройки игры)

JSON Schema game_settings.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://schemas.ufagame.local/game_settings.schema.json",
  "title": "Общие настройки игры (config/game_settings.json)",
  "type": "object",
  "required": ["game_name", "default_language", "languages"],
  "additionalProperties": false,
  "properties": {
    "$schema": {"type": "string"},
    "game_name": {"type": "string", "minLength": 1, "maxLength": 64, "description": "Название игры (показывается в игре)"},
    "default_language": {"type": "string", "pattern": "^[a-z]{2}$"},
    "languages": {"type": "array", "minItems": 1, "uniqueItems": true, "items": {"type": "string", "pattern": "^[a-z]{2}$"}},
    "support_email": {"type": "string"},
    "theme": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "primary": {"$ref": "common.schema.json#/$defs/color"},
        "accent": {"$ref": "common.schema.json#/$defs/color"},
        "background": {"$ref": "common.schema.json#/$defs/color"},
        "text": {"$ref": "common.schema.json#/$defs/color"}
      }
    }
  }
}


Пример объекта из игры:
{
  "game_name": "[НАЗВАНИЕ]",
  "default_language": "ru",
  "languages": [
    "ru"
  ],
  "support_email": "",
  "theme": {
    "primary": "#3B1F5C",
    "accent": "#F2B544",
    "background": "#160E24",
    "text": "#F4ECDD"
  }
}

Верни только готовый patch.json и список файлов, которые нужно положить в files/.
````

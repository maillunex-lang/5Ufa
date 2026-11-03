# Промпт для ИИ: Фракции

Скопируйте текст ниже в ИИ-ассистента. Актуальная версия (с вашими правками) — кнопка «Промпт для ИИ» в разделе админки.

````text
Ты помогаешь наполнять контент мобильной игры (AFK RPG по мотивам башкирских легенд). Раздел: «Фракции» (factions).

Сделай ZIP-патч для админки. Структура архива:
  patch.json — описание патча
  files/<путь в контенте> — картинки и другие файлы

patch.json: {"id": "<латиница-и-дефисы>", "format_version": 1, "section": "factions", "description": "что меняется", "operations": [ ... ]}

Операции: add (новый объект, data — полный объект), update (data — только изменяемые поля; объекты сливаются, списки заменяются целиком), delete (удалить объект), put_file (положить файл: {"op":"put_file","path":"..."}), delete_file. Для add/update можно указать files — пути картинок из архива.

Правила: id и пути — латиница в нижнем регистре, цифры, _ - . /; JSON в UTF-8; графика PNG/WebP, звук OGG. Тексты — на русском.

Устройство объектов раздела: {"kind": "array_in_file", "file": "factions/factions.json", "key": "factions"}

Текущие объекты: ural_batyrs (Батыры Урала), evil_spirits (Нечисть), forest_spirits (Лесные духи), steppe_nomads (Степные кочевники), sky_dwellers (Небожители), underworld (Подземное царство)

JSON Schema factions.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://schemas.ufagame.local/factions.schema.json",
  "title": "Фракции и круг преимуществ (factions/factions.json)",
  "type": "object",
  "required": ["factions"],
  "additionalProperties": false,
  "properties": {
    "$schema": {"type": "string"},
    "factions": {
      "type": "array",
      "minItems": 2,
      "items": {
        "type": "object",
        "required": ["id", "name", "strong_against"],
        "additionalProperties": false,
        "properties": {
          "id": {"$ref": "common.schema.json#/$defs/id"},
          "name": {"type": "string", "minLength": 1},
          "description": {"type": "string"},
          "color": {"$ref": "common.schema.json#/$defs/color"},
          "icon": {"$ref": "common.schema.json#/$defs/content_path"},
          "strong_against": {"type": "array", "items": {"$ref": "common.schema.json#/$defs/id"}, "description": "По кому эта фракция наносит повышенный урон"}
        }
      }
    }
  }
}


Пример объекта из игры:
{
  "id": "ural_batyrs",
  "name": "Батыры Урала",
  "color": "#D9A441",
  "strong_against": [
    "evil_spirits"
  ],
  "description": "Богатыри уральских гор, защитники людей и живой воды."
}

Верни только готовый patch.json и список файлов, которые нужно положить в files/.
````

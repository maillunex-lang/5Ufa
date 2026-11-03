# Промпт для ИИ: Призыв

Скопируйте текст ниже в ИИ-ассистента. Актуальная версия (с вашими правками) — кнопка «Промпт для ИИ» в разделе админки.

````text
Ты помогаешь наполнять контент мобильной игры (AFK RPG по мотивам башкирских легенд). Раздел: «Призыв» (summon).

Сделай ZIP-патч для админки. Структура архива:
  patch.json — описание патча
  files/<путь в контенте> — картинки и другие файлы

patch.json: {"id": "<латиница-и-дефисы>", "format_version": 1, "section": "summon", "description": "что меняется", "operations": [ ... ]}

Операции: add (новый объект, data — полный объект), update (data — только изменяемые поля; объекты сливаются, списки заменяются целиком), delete (удалить объект), put_file (положить файл: {"op":"put_file","path":"..."}), delete_file. Для add/update можно указать files — пути картинок из архива.

Правила: id и пути — латиница в нижнем регистре, цифры, _ - . /; JSON в UTF-8; графика PNG/WebP, звук OGG. Тексты — на русском.

Устройство объектов раздела: {"kind": "array_in_file", "file": "summon/banners.json", "key": "banners"}

Текущие объекты: normal (Обычный призыв), faction_ural_batyrs (Призыв: Батыры Урала), faction_evil_spirits (Призыв: Нечисть), faction_forest_spirits (Призыв: Лесные духи), faction_steppe_nomads (Призыв: Степные кочевники), event_humai (Баннер: Хумай)

JSON Schema summon.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://schemas.ufagame.local/summon.schema.json",
  "title": "Призыв (summon/banners.json): шансы, гарант, баннеры",
  "type": "object",
  "required": ["pity_legendary", "rates", "banners"],
  "additionalProperties": false,
  "properties": {
    "$schema": {"type": "string"},
    "pity_legendary": {"type": "integer", "minimum": 1, "description": "Легенда не позже этого номера призыва"},
    "first_summon_legendary": {"type": "boolean", "description": "Первый призыв на обычном баннере — легенда"},
    "rates": {"$ref": "#/$defs/rates"},
    "banners": {
      "type": "array", "minItems": 1,
      "items": {
        "type": "object", "required": ["id", "name", "type", "costs", "factions"], "additionalProperties": false,
        "properties": {
          "id": {"$ref": "common.schema.json#/$defs/id"},
          "name": {"type": "string", "minLength": 1},
          "description": {"type": "string"},
          "type": {"enum": ["normal", "faction", "event"]},
          "costs": {
            "type": "array", "minItems": 1,
            "description": "Варианты оплаты одного призыва, по порядку (например, свиток, иначе кристаллы)",
            "items": {"type": "object", "minProperties": 1, "additionalProperties": {"type": "integer", "minimum": 1}}
          },
          "factions": {"type": "array", "minItems": 1, "items": {"$ref": "common.schema.json#/$defs/id"}},
          "rates": {"$ref": "#/$defs/rates"},
          "featured": {"type": "array", "items": {"$ref": "common.schema.json#/$defs/id"}, "description": "Герои с повышенным шансом"},
          "featured_share": {"type": "number", "minimum": 0, "maximum": 1, "description": "Доля легенд, приходящаяся на героев баннера"},
          "starts_at": {"type": "string", "format": "date-time"},
          "ends_at": {"type": "string", "format": "date-time"}
        }
      }
    }
  },
  "$defs": {
    "rates": {
      "type": "object", "required": ["rare", "elite", "legendary"], "additionalProperties": false,
      "properties": {
        "rare": {"type": "number", "minimum": 0, "maximum": 1},
        "elite": {"type": "number", "minimum": 0, "maximum": 1},
        "legendary": {"type": "number", "minimum": 0, "maximum": 1}
      }
    }
  }
}


Пример объекта из игры:
{
  "id": "normal",
  "name": "Обычный призыв",
  "type": "normal",
  "description": "Герои четырёх основных фракций",
  "costs": [
    {
      "scrolls": 1
    },
    {
      "crystals": 300
    }
  ],
  "factions": [
    "ural_batyrs",
    "evil_spirits",
    "forest_spirits",
    "steppe_nomads"
  ]
}

Верни только готовый patch.json и список файлов, которые нужно положить в files/.
````

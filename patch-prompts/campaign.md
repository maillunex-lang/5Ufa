# Промпт для ИИ: Кампания и AFK

Скопируйте текст ниже в ИИ-ассистента. Актуальная версия (с вашими правками) — кнопка «Промпт для ИИ» в разделе админки.

````text
Ты помогаешь наполнять контент мобильной игры (AFK RPG по мотивам башкирских легенд). Раздел: «Кампания и AFK» (campaign).

Сделай ZIP-патч для админки. Структура архива:
  patch.json — описание патча
  files/<путь в контенте> — картинки и другие файлы

patch.json: {"id": "<латиница-и-дефисы>", "format_version": 1, "section": "campaign", "description": "что меняется", "operations": [ ... ]}

Операции: add (новый объект, data — полный объект), update (data — только изменяемые поля; объекты сливаются, списки заменяются целиком), delete (удалить объект), put_file (положить файл: {"op":"put_file","path":"..."}), delete_file. Для add/update можно указать files — пути картинок из архива.

Правила: id и пути — латиница в нижнем регистре, цифры, _ - . /; JSON в UTF-8; графика PNG/WebP, звук OGG. Тексты — на русском.

Устройство объектов раздела: {"kind": "file_per_object", "path": "campaign/{id}/chapter.json", "dir": "campaign/{id}/"}

Текущие объекты: chapter_1 (Уфа), chapter_2 (Иремель), chapter_3 (Шульган-Таш), chapter_4 (Янган-Тау), chapter_5 (Озеро Аслыкуль)

JSON Schema campaign_chapter.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://ufa.game/schemas/campaign_chapter.schema.json",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "id",
    "number",
    "title",
    "subtitle",
    "dialogue_start",
    "dialogue_end",
    "stages"
  ],
  "properties": {
    "id": {
      "type": "string",
      "pattern": "^chapter_[1-5]$"
    },
    "number": {
      "type": "integer",
      "minimum": 1,
      "maximum": 5
    },
    "title": {
      "type": "string",
      "minLength": 1
    },
    "subtitle": {
      "type": "string",
      "minLength": 1
    },
    "dialogue_start": {
      "type": "string",
      "minLength": 1
    },
    "dialogue_end": {
      "type": "string",
      "minLength": 1
    },
    "stages": {
      "type": "array",
      "minItems": 5,
      "maxItems": 5,
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": [
          "id",
          "number",
          "enemy",
          "enemy_multiplier",
          "reward"
        ],
        "properties": {
          "id": {
            "type": "string",
            "minLength": 1
          },
          "number": {
            "type": "integer",
            "minimum": 1
          },
          "enemy": {
            "type": "string",
            "minLength": 1
          },
          "enemy_multiplier": {
            "type": "number",
            "exclusiveMinimum": 0
          },
          "reward": {
            "type": "object",
            "additionalProperties": false,
            "required": [
              "gold",
              "hero_xp"
            ],
            "properties": {
              "gold": {
                "type": "integer",
                "minimum": 0
              },
              "hero_xp": {
                "type": "integer",
                "minimum": 0
              },
              "crystals": {
                "type": "integer",
                "minimum": 0
              },
              "scrolls": {
                "type": "integer",
                "minimum": 0
              }
            }
          }
        }
      }
    }
  }
}

JSON Schema campaign_config.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://ufa.game/schemas/campaign_config.schema.json",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "afk_cap_seconds",
    "gold_per_hour",
    "hero_xp_per_hour",
    "stage_bonus_percent",
    "quick_seconds",
    "quick_daily_limit"
  ],
  "properties": {
    "afk_cap_seconds": {
      "type": "integer",
      "minimum": 0
    },
    "gold_per_hour": {
      "type": "integer",
      "minimum": 0
    },
    "hero_xp_per_hour": {
      "type": "integer",
      "minimum": 0
    },
    "stage_bonus_percent": {
      "type": "integer",
      "minimum": 0
    },
    "quick_seconds": {
      "type": "integer",
      "minimum": 0
    },
    "quick_daily_limit": {
      "type": "integer",
      "minimum": 0
    },
    "crystals_per_hour": {
      "type": "integer",
      "minimum": 0
    },
    "essence_per_hour": {
      "type": "integer",
      "minimum": 0
    },
    "ore_per_hour": {
      "type": "integer",
      "minimum": 0,
      "description": "Руда в AFK-сундуке за час"
    },
    "equipment_per_100h": {
      "type": "integer",
      "minimum": 0,
      "description": "Предметов снаряжения за 100 часов AFK (50 = 1 предмет в 2 часа)"
    }
  }
}


Пример объекта из игры:
{
  "id": "chapter_1",
  "number": 1,
  "title": "Уфа",
  "subtitle": "Защитники города",
  "dialogue_start": "Урал-батыр: У стен Уфы замечена нечисть.\nХумай: Соберём отряд и защитим город.",
  "dialogue_end": "Урал-батыр: Мы нашли их предводителя.\nХумай: Вместе мы остановим его.",
  "stages": [
    {
      "id": "1-1",
      "number": 1,
      "enemy": "test_evil",
      "enemy_multiplier": 0.52,
      "reward": {
        "gold": 100,
        "hero_xp": 50,
        "crystals": 20
      }
    },
    {
      "id": "1-2",
      "number": 2,
      "enemy": "test_evil",
      "enemy_multiplier": 0.545,
      "reward": {
        "gold": 100,
        "hero_xp": 50,
        "crystals": 20
      }
    },
    {
      "id": "1-3",
      "number": 3,
      "enemy": "test_evil",
      "enemy_multiplier": 0.57,
      "reward": {
        "gold": 100,
        "hero_xp": 50,
        "crystals": 20
      }
    },
    {
      "id": "1-4",
      "number": 4,
      "enemy": "test_evil",
      "enemy_multiplier": 0.595,
      "reward": {
        "gold": 100,
        "hero_xp": 50,
        "crystals": 20
      }
    },
    {
      "id": "1-5",
      "number": 5,
      "enemy": "test_evil",
      "enemy_multiplier": 0.7,
      "reward": {
        "gold": 100,
        "hero_xp": 50,
        "crystals": 20,
        "scrolls": 1
      }
    }
  ]
}

Верни только готовый patch.json и список файлов, которые нужно положить в files/.
````

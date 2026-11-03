# Промпт для ИИ: Прогрессия героев

Скопируйте текст ниже в ИИ-ассистента. Актуальная версия (с вашими правками) — кнопка «Промпт для ИИ» в разделе админки.

````text
Ты помогаешь наполнять контент мобильной игры (AFK RPG по мотивам башкирских легенд). Раздел: «Прогрессия героев» (progression).

Сделай ZIP-патч для админки. Структура архива:
  patch.json — описание патча
  files/<путь в контенте> — картинки и другие файлы

patch.json: {"id": "<латиница-и-дефисы>", "format_version": 1, "section": "progression", "description": "что меняется", "operations": [ ... ]}

Операции: add (новый объект, data — полный объект), update (data — только изменяемые поля; объекты сливаются, списки заменяются целиком), delete (удалить объект), put_file (положить файл: {"op":"put_file","path":"..."}), delete_file. Для add/update можно указать files — пути картинок из архива.

Правила: id и пути — латиница в нижнем регистре, цифры, _ - . /; JSON в UTF-8; графика PNG/WebP, звук OGG. Тексты — на русском.

Устройство объектов раздела: {"kind": "single", "file": "config/progression.json", "id": "progression"}

Текущие объекты: progression (Прогрессия героев)

JSON Schema progression.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://schemas.ufagame.local/progression.schema.json",
  "title": "Прогрессия героев (config/progression.json): редкости, уровни, вознесение, кристалл, старт",
  "type": "object",
  "required": ["tiers", "level", "ascension", "resonance", "start"],
  "additionalProperties": false,
  "properties": {
    "$schema": {"type": "string"},
    "tiers": {
      "type": "array", "minItems": 2,
      "description": "Ступени редкости по возрастанию",
      "items": {
        "type": "object", "required": ["id", "name", "level_cap", "stat_mult"], "additionalProperties": false,
        "properties": {
          "id": {"$ref": "common.schema.json#/$defs/id"},
          "name": {"type": "string", "minLength": 1},
          "level_cap": {"type": "integer", "minimum": 1, "description": "Предел уровня на этой ступени"},
          "stat_mult": {"type": "number", "exclusiveMinimum": 0, "description": "Множитель характеристик ступени"},
          "color": {"$ref": "common.schema.json#/$defs/color"}
        }
      }
    },
    "level": {
      "type": "object", "required": ["stat_growth_percent", "gold", "hero_xp"], "additionalProperties": false,
      "properties": {
        "stat_growth_percent": {"type": "number", "minimum": 0, "description": "Прирост характеристик за уровень, %"},
        "gold": {"$ref": "#/$defs/cost"},
        "hero_xp": {"$ref": "#/$defs/cost"},
        "essence": {"$ref": "#/$defs/cost"}
      }
    },
    "ascension": {
      "type": "array",
      "items": {
        "type": "object", "required": ["from", "to", "requires"], "additionalProperties": false,
        "properties": {
          "from": {"$ref": "common.schema.json#/$defs/id"},
          "to": {"$ref": "common.schema.json#/$defs/id"},
          "requires": {
            "type": "array", "minItems": 1,
            "items": {
              "type": "object", "required": ["kind", "tier", "count"], "additionalProperties": false,
              "properties": {
                "kind": {"enum": ["same", "faction"], "description": "same — копия того же героя; faction — любой герой той же фракции"},
                "tier": {"$ref": "common.schema.json#/$defs/id"},
                "count": {"type": "integer", "minimum": 1}
              }
            }
          }
        }
      }
    },
    "resonance": {
      "type": "object", "required": ["slots", "top"], "additionalProperties": false,
      "properties": {
        "slots": {"type": "integer", "minimum": 0, "description": "Мест в Кристалле резонанса"},
        "top": {"type": "integer", "minimum": 1, "description": "Сколько сильнейших героев задают уровень кристалла"}
      }
    },
    "start": {
      "type": "object", "required": ["heroes"], "additionalProperties": false,
      "properties": {
        "heroes": {"type": "array", "items": {"type": "object", "required": ["hero", "tier"], "additionalProperties": false,
                   "properties": {"hero": {"$ref": "common.schema.json#/$defs/id"}, "tier": {"$ref": "common.schema.json#/$defs/id"}}}},
        "currencies": {"type": "object", "additionalProperties": {"type": "integer", "minimum": 0}}
      }
    },
    "dismiss_essence": {"type": "object", "additionalProperties": {"type": "integer", "minimum": 0},
                        "description": "Сколько эссенции за роспуск героя данной редкости (0/нет — нельзя)"}
  },
  "$defs": {
    "cost": {
      "type": "object", "required": ["base", "exponent"], "additionalProperties": false,
      "description": "Стоимость уровня L = round(base × n^exponent), n = L − from_level + 1",
      "properties": {
        "base": {"type": "number", "minimum": 0},
        "exponent": {"type": "number", "minimum": 0},
        "from_level": {"type": "integer", "minimum": 1}
      }
    }
  }
}


Пример объекта из игры:
{
  "tiers": [
    {
      "id": "rare",
      "name": "Редкий",
      "level_cap": 60,
      "stat_mult": 0.85,
      "color": "#5AA9E6"
    },
    {
      "id": "elite",
      "name": "Элита",
      "level_cap": 100,
      "stat_mult": 1.0,
      "color": "#B06CE0"
    },
    {
      "id": "elite_plus",
      "name": "Элита+",
      "level_cap": 120,
      "stat_mult": 1.15,
      "color": "#C88CF0"
    },
    {
      "id": "legendary",
      "name": "Легенда",
      "level_cap": 140,
      "stat_mult": 1.3,
      "color": "#F2B544"
    },
    {
      "id": "legendary_plus",
      "name": "Легенда+",
      "level_cap": 160,
      "stat_mult": 1.45,
      "color": "#FFD27A"
    },
    {
      "id": "mythic",
      "name": "Миф",
      "level_cap": 180,
      "stat_mult": 1.65,
      "color": "#E2504A"
    },
    {
      "id": "mythic_plus",
      "name": "Миф+",
      "level_cap": 200,
      "stat_mult": 1.85,
      "color": "#FF7A6E"
    },
    {
      "id": "ascended",
      "name": "Вознесённый",
      "level_cap": 240,
      "stat_mult": 2.2,
      "color": "#F4ECDD"
    }
  ],
  "level": {
    "stat_growth_percent": 2.0,
    "gold": {
      "base": 15,
      "exponent": 1.2
    },
    "hero_xp": {
      "base": 10,
      "exponent": 1.25
    },
    "essence": {
      "from_level": 100,
      "base": 20,
      "exponent": 1.2
    }
  },
  "ascension": [
    {
      "from": "elite",
      "to": "elite_plus",
      "requires": [
        {
          "kind": "same",
          "tier": "elite",
          "count": 1
        }
      ]
    },
    {
      "from": "elite_plus",
      "to": "legendary",
      "requires": [
        {
          "kind": "same",
          "tier": "elite",
          "count": 1
        },
        {
          "kind": "faction",
          "tier": "elite",
          "count": 1
        }
      ]
    },
    {
      "from": "legendary",
      "to": "legendary_plus",
      "requires": [
        {
          "kind": "same",
          "tier": "legendary",
          "count": 1
        }
      ]
    },
    {
      "from": "legendary_plus",
      "to": "mythic",
      "requires": [
        {
          "kind": "faction",
          "tier": "legendary_plus",
          "count": 2
        }
      ]
    },
    {
      "from": "mythic",
      "to": "mythic_plus",
      "requires": [
        {
          "kind": "same",
          "tier": "elite",
          "count": 1
        },
        {
          "kind": "faction",
          "tier": "mythic",
          "count": 1
        }
      ]
    },
    {
      "from": "mythic_plus",
      "to": "ascended",
      "requires": [
        {
          "kind": "faction",
          "tier": "elite_plus",
          "count": 2
        }
      ]
    }
  ],
  "resonance": {
    "slots": 5,
    "top": 5
  },
  "start": {
    "heroes": [
      {
        "hero": "alpamysha",
        "tier": "elite"
      },
      {
        "hero": "ural_batyr",
        "tier": "elite"
      },
      {
        "hero": "zayatulyak",
        "tier": "elite"
      },
      {
        "hero": "humai",
        "tier": "elite"
      },
      {
        "hero": "hyuhylu",
        "tier": "elite"
      }
    ],
    "currencies": {
      "scrolls": 10,
      "crystals": 1000
    }
  },
  "dismiss_essence": {
    "rare": 100
  }
}

Верни только готовый patch.json и список файлов, которые нужно положить в files/.
````

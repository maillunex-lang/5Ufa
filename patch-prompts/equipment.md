# Промпт для ИИ: Снаряжение

Скопируйте текст ниже в ИИ-ассистента. Актуальная версия (с вашими правками) — кнопка «Промпт для ИИ» в разделе админки.

````text
Ты помогаешь наполнять контент мобильной игры (AFK RPG по мотивам башкирских легенд). Раздел: «Снаряжение» (equipment).

Сделай ZIP-патч для админки. Структура архива:
  patch.json — описание патча
  files/<путь в контенте> — картинки и другие файлы

patch.json: {"id": "<латиница-и-дефисы>", "format_version": 1, "section": "equipment", "description": "что меняется", "operations": [ ... ]}

Операции: add (новый объект, data — полный объект), update (data — только изменяемые поля; объекты сливаются, списки заменяются целиком), delete (удалить объект), put_file (положить файл: {"op":"put_file","path":"..."}), delete_file. Для add/update можно указать files — пути картинок из архива.

Правила: id и пути — латиница в нижнем регистре, цифры, _ - . /; JSON в UTF-8; графика PNG/WebP, звук OGG. Тексты — на русском.

Устройство объектов раздела: {"kind": "single", "file": "config/equipment.json", "id": "equipment"}

Текущие объекты: equipment (Снаряжение)

JSON Schema equipment.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://schemas.ufagame.local/equipment.schema.json",
  "title": "Снаряжение (config/equipment.json): слоты, типы, редкости, улучшение, добыча, уникальный предмет",
  "type": "object",
  "required": ["slots", "kinds", "qualities", "faction_bonus_percent", "upgrade", "inventory_limit", "drops", "start", "signature"],
  "additionalProperties": false,
  "$defs": {
    "stats": {
      "type": "object", "additionalProperties": false, "minProperties": 1,
      "properties": {"hp": {"type": "number", "minimum": 0}, "atk": {"type": "number", "minimum": 0}, "def": {"type": "number", "minimum": 0}}
    },
    "lin": {
      "type": "object", "required": ["base", "per_level"], "additionalProperties": false,
      "description": "Цена уровня L→L+1 = base + per_level × L",
      "properties": {"base": {"type": "integer", "minimum": 0}, "per_level": {"type": "integer", "minimum": 0}}
    }
  },
  "properties": {
    "$schema": {"type": "string"},
    "slots": {
      "type": "array", "minItems": 1,
      "items": {
        "type": "object", "required": ["id", "name", "stats"], "additionalProperties": false,
        "properties": {
          "id": {"$ref": "common.schema.json#/$defs/id"},
          "name": {"type": "string", "minLength": 1},
          "stats": {"$ref": "#/$defs/stats", "description": "Характеристики обычного предмета +0"}
        }
      }
    },
    "kinds": {
      "type": "array", "minItems": 1,
      "description": "Типы предметов; герой носит только тип своей роли",
      "items": {
        "type": "object", "required": ["id", "name", "roles", "item_names"], "additionalProperties": false,
        "properties": {
          "id": {"$ref": "common.schema.json#/$defs/id"},
          "name": {"type": "string", "minLength": 1},
          "roles": {"type": "array", "minItems": 1, "items": {"enum": ["tank", "warrior", "archer", "mage", "support", "assassin"]}},
          "item_names": {"type": "object", "additionalProperties": {"type": "string", "minLength": 1}}
        }
      }
    },
    "qualities": {
      "type": "array", "minItems": 1, "description": "Редкости по возрастанию",
      "items": {
        "type": "object", "required": ["id", "name", "mult", "dismantle_ore"], "additionalProperties": false,
        "properties": {
          "id": {"$ref": "common.schema.json#/$defs/id"},
          "name": {"type": "string", "minLength": 1},
          "mult": {"type": "number", "exclusiveMinimum": 0},
          "color": {"$ref": "common.schema.json#/$defs/color"},
          "dismantle_ore": {"type": "integer", "minimum": 0}
        }
      }
    },
    "faction_bonus_percent": {"type": "number", "minimum": 0, "description": "Прибавка к предмету, если фракция совпала с героем"},
    "upgrade": {
      "type": "object", "required": ["max_level", "stat_percent_per_level", "gold_base", "ore_base", "refund_percent"],
      "additionalProperties": false,
      "description": "Цена L→L+1: золото gold_base×(L+1)×(редкость+1), руда ore_base×(L+1)×(редкость+1)",
      "properties": {
        "max_level": {"type": "integer", "minimum": 0},
        "stat_percent_per_level": {"type": "number", "minimum": 0},
        "gold_base": {"type": "integer", "minimum": 0},
        "ore_base": {"type": "integer", "minimum": 0},
        "refund_percent": {"type": "number", "minimum": 0, "maximum": 100, "description": "Сколько руды улучшений возвращает разбор"}
      }
    },
    "inventory_limit": {"type": "integer", "minimum": 1},
    "drops": {
      "type": "object", "required": ["campaign_quality_by_chapter"], "additionalProperties": false,
      "properties": {
        "campaign_quality_by_chapter": {"type": "array", "minItems": 1, "items": {"type": "string"},
                                        "description": "Редкость предмета за первую победу и из сундука по номеру главы"},
        "chapter_end_legacy_shards": {"type": "integer", "minimum": 0}
      }
    },
    "start": {
      "type": "object", "required": ["per_kind", "quality"], "additionalProperties": false,
      "properties": {"per_kind": {"type": "integer", "minimum": 0}, "quality": {"type": "string"}}
    },
    "signature": {
      "type": "object", "required": ["unlock_tier", "max_level", "stat_percent_per_level", "cost", "ult_bonus"],
      "additionalProperties": false,
      "properties": {
        "unlock_tier": {"type": "string", "description": "С какой ступени героя открывается уникальный предмет"},
        "max_level": {"type": "integer", "minimum": 1},
        "stat_percent_per_level": {"type": "number", "minimum": 0},
        "cost": {"type": "object", "additionalProperties": {"$ref": "#/$defs/lin"}},
        "ult_bonus": {
          "type": "array",
          "items": {"type": "object", "required": ["level", "percent"], "additionalProperties": false,
                    "properties": {"level": {"type": "integer", "minimum": 1}, "percent": {"type": "number", "minimum": 0}}}
        }
      }
    }
  }
}


Пример объекта из игры:
{
  "$schema": "../../shared/schemas/equipment.schema.json",
  "slots": [
    {
      "id": "weapon",
      "name": "Оружие",
      "stats": {
        "atk": 20
      }
    },
    {
      "id": "armor",
      "name": "Доспех",
      "stats": {
        "hp": 200,
        "def": 8
      }
    },
    {
      "id": "helmet",
      "name": "Шлем",
      "stats": {
        "hp": 300
      }
    },
    {
      "id": "boots",
      "name": "Сапоги",
      "stats": {
        "atk": 6,
        "hp": 120
      }
    }
  ],
  "kinds": [
    {
      "id": "strength",
      "name": "Сила",
      "roles": [
        "tank",
        "warrior"
      ],
      "item_names": {
        "weapon": "Меч",
        "armor": "Латы",
        "helmet": "Шлем",
        "boots": "Сапоги"
      }
    },
    {
      "id": "agility",
      "name": "Ловкость",
      "roles": [
        "archer",
        "assassin"
      ],
      "item_names": {
        "weapon": "Лук",
        "armor": "Кожаный доспех",
        "helmet": "Капюшон",
        "boots": "Лёгкие сапоги"
      }
    },
    {
      "id": "mystic",
      "name": "Мистика",
      "roles": [
        "mage",
        "support"
      ],
      "item_names": {
        "weapon": "Посох",
        "armor": "Мантия",
        "helmet": "Венец",
        "boots": "Туфли"
      }
    }
  ],
  "qualities": [
    {
      "id": "common",
      "name": "Обычный",
      "mult": 1.0,
      "color": "#B8B8B8",
      "dismantle_ore": 2
    },
    {
      "id": "rare",
      "name": "Редкий",
      "mult": 1.6,
      "color": "#5AA9E6",
      "dismantle_ore": 5
    },
    {
      "id": "elite",
      "name": "Элитный",
      "mult": 2.56,
      "color": "#B06CE0",
      "dismantle_ore": 12
    },
    {
      "id": "legendary",
      "name": "Легендарный",
      "mult": 4.1,
      "color": "#F2B544",
      "dismantle_ore": 30
    },
    {
      "id": "mythic",
      "name": "Мифический",
      "mult": 6.55,
      "color": "#FF7A3A",
      "dismantle_ore": 75
    }
  ],
  "faction_bonus_percent": 15,
  "upgrade": {
    "max_level": 10,
    "stat_percent_per_level": 8,
    "gold_base": 100,
    "ore_base": 3,
    "refund_percent": 50
  },
  "inventory_limit": 500,
  "drops": {
    "campaign_quality_by_chapter": [
      "common",
      "rare",
      "rare",
      "elite",
      "elite"
    ],
    "chapter_end_legacy_shards": 20
  },
  "start": {
    "per_kind": 4,
    "quality": "common"
  },
  "signature": {
    "unlock_tier": "mythic",
    "max_level": 10,
    "stat_percent_per_level": 3,
    "cost": {
      "legacy_shards": {
        "base": 10,
        "per_level": 5
      },
      "gold": {
        "base": 2000,
        "per_level": 2000
      }
    },
    "ult_bonus": [
      {
        "level": 5,
        "percent": 10
      },
      {
        "level": 10,
        "percent": 20
      }
    ]
  }
}

Верни только готовый patch.json и список файлов, которые нужно положить в files/.
````

# Промпт для ИИ: Бой и отряды

Скопируйте текст ниже в ИИ-ассистента. Актуальная версия (с вашими правками) — кнопка «Промпт для ИИ» в разделе админки.

````text
Ты помогаешь наполнять контент мобильной игры (AFK RPG по мотивам башкирских легенд). Раздел: «Бой и отряды» (battle).

Сделай ZIP-патч для админки. Структура архива:
  patch.json — описание патча
  files/<путь в контенте> — картинки и другие файлы

patch.json: {"id": "<латиница-и-дефисы>", "format_version": 1, "section": "battle", "description": "что меняется", "operations": [ ... ]}

Операции: add (новый объект, data — полный объект), update (data — только изменяемые поля; объекты сливаются, списки заменяются целиком), delete (удалить объект), put_file (положить файл: {"op":"put_file","path":"..."}), delete_file. Для add/update можно указать files — пути картинок из архива.

Правила: id и пути — латиница в нижнем регистре, цифры, _ - . /; JSON в UTF-8; графика PNG/WebP, звук OGG. Тексты — на русском.

Устройство объектов раздела: {"kind": "array_in_file", "file": "battle/test_teams.json", "key": "teams"}

Текущие объекты: test_evil (Отряд Шульгена), test_forest (Лесная засада), test_underworld (Подземное войско), test_weak (Учебный отряд)

JSON Schema battle_config.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://schemas.ufagame.local/battle_config.schema.json",
  "title": "Формулы и правила боя (config/battle.json)",
  "type": "object",
  "required": ["tick_rate", "max_duration_sec", "energy", "damage", "field", "roles"],
  "additionalProperties": false,
  "properties": {
    "$schema": {"type": "string"},
    "tick_rate": {"type": "integer", "minimum": 5, "maximum": 60, "description": "Тиков расчёта в секунду"},
    "max_duration_sec": {"type": "integer", "minimum": 10, "maximum": 600, "description": "По истечении — победа защиты"},
    "energy": {
      "type": "object",
      "required": ["max", "on_attack", "on_hit_per_hp_percent", "on_kill"],
      "additionalProperties": false,
      "properties": {
        "max": {"type": "integer", "minimum": 1},
        "start": {"type": "integer", "minimum": 0},
        "on_attack": {"type": "integer", "minimum": 0, "description": "За обычную атаку"},
        "on_hit_per_hp_percent": {"type": "number", "minimum": 0, "description": "За каждый потерянный 1% здоровья"},
        "on_kill": {"type": "integer", "minimum": 0},
        "on_skill": {"type": "integer", "minimum": 0}
      }
    },
    "damage": {
      "type": "object",
      "required": ["defense_constant", "faction_bonus", "crit_chance", "crit_damage"],
      "additionalProperties": false,
      "properties": {
        "defense_constant": {"type": "number", "exclusiveMinimum": 0, "description": "Снижение урона = защита / (защита + это_число)"},
        "max_reduction": {"type": "number", "minimum": 0, "maximum": 0.95},
        "faction_bonus": {"type": "number", "minimum": 0, "description": "0.25 = +25% урона по фракции, которую бьёшь по кругу"},
        "crit_chance": {"type": "number", "minimum": 0, "maximum": 1, "description": "Базовый шанс крита"},
        "crit_damage": {"type": "number", "minimum": 1},
        "variance": {"type": "number", "minimum": 0, "maximum": 0.5, "description": "Случайный разброс урона ±"},
        "min_damage": {"type": "integer", "minimum": 0}
      }
    },
    "field": {
      "type": "object",
      "required": ["front_x", "back_x", "lanes"],
      "additionalProperties": false,
      "properties": {
        "front_x": {"type": "number", "description": "Где стоит передний ряд (расстояние от центра)"},
        "back_x": {"type": "number"},
        "lanes": {"type": "array", "items": {"type": "number"}, "minItems": 5, "maxItems": 5, "description": "Вертикальная позиция (для отрисовки) слотов 0..4: 0-1 передние, 2-4 задние"}
      }
    },
    "roles": {
      "type": "object",
      "description": "Значения по умолчанию для ролей (если у героя не указано)",
      "additionalProperties": {
        "type": "object",
        "additionalProperties": false,
        "properties": {
          "range": {"type": "number"},
          "move_speed": {"type": "number"},
          "attack_windup_ms": {"type": "integer", "minimum": 0, "description": "Через сколько после начала атаки урон (ближний бой)"},
          "projectile_speed": {"type": "number", "description": "Скорость снаряда (дальний бой), единиц/сек; 0 — без снаряда"},
          "targeting": {"enum": ["nearest", "backline", "lowest_hp", "frontline"]}
        }
      }
    }
  }
}


JSON Schema teams.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://schemas.ufagame.local/teams.schema.json",
  "title": "Готовые отряды противников (battle/test_teams.json, позже — враги этапов кампании)",
  "type": "object",
  "required": ["teams"],
  "additionalProperties": false,
  "properties": {
    "$schema": {"type": "string"},
    "teams": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["id", "name", "units"],
        "additionalProperties": false,
        "properties": {
          "id": {"$ref": "common.schema.json#/$defs/id"},
          "name": {"type": "string"},
          "units": {
            "type": "array",
            "minItems": 1,
            "maxItems": 5,
            "items": {
              "type": "object",
              "required": ["hero", "slot"],
              "additionalProperties": false,
              "properties": {
                "hero": {"$ref": "common.schema.json#/$defs/id"},
                "slot": {"type": "integer", "minimum": 0, "maximum": 4, "description": "0-1 передний ряд, 2-4 задний"},
                "level": {"type": "integer", "minimum": 1},
                "stat_multiplier": {"type": "number", "exclusiveMinimum": 0, "description": "Усиление врага (1.0 — как у героя)"}
              }
            }
          }
        }
      }
    }
  }
}


Пример объекта из игры:
{
  "id": "test_evil",
  "name": "Отряд Шульгена",
  "units": [
    {
      "hero": "deyeu",
      "slot": 0
    },
    {
      "hero": "shulgen",
      "slot": 1
    },
    {
      "hero": "albasty",
      "slot": 2
    },
    {
      "hero": "azhdaha",
      "slot": 3
    },
    {
      "hero": "baksy",
      "slot": 4
    }
  ]
}

Верни только готовый patch.json и список файлов, которые нужно положить в files/.
````

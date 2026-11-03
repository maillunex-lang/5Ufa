# Промпт для ИИ: Герои

Скопируйте текст ниже в ИИ-ассистента. Актуальная версия (с вашими правками) — кнопка «Промпт для ИИ» в разделе админки.

````text
Ты помогаешь наполнять контент мобильной игры (AFK RPG по мотивам башкирских легенд). Раздел: «Герои» (heroes).

Сделай ZIP-патч для админки. Структура архива:
  patch.json — описание патча
  files/<путь в контенте> — картинки и другие файлы

patch.json: {"id": "<латиница-и-дефисы>", "format_version": 1, "section": "heroes", "description": "что меняется", "operations": [ ... ]}

Операции: add (новый объект, data — полный объект), update (data — только изменяемые поля; объекты сливаются, списки заменяются целиком), delete (удалить объект), put_file (положить файл: {"op":"put_file","path":"..."}), delete_file. Для add/update можно указать files — пути картинок из архива.

Правила: id и пути — латиница в нижнем регистре, цифры, _ - . /; JSON в UTF-8; графика PNG/WebP, звук OGG. Тексты — на русском.

Устройство объектов раздела: {"kind": "file_per_object", "path": "heroes/{id}/hero.json", "dir": "heroes/{id}/"}

Текущие объекты: aihylu (Айхылыу), albasty (Албасты), alpamysha (Алпамыша), azhdaha (Аждаха), baksy (Баксы), bisura (Бисура), deyeu (Дейеу), forest_archer (Лесной стрелок), humai (Хумай), hyuhylu (Хыухылу), imp_evil (Упырь), katil (Катил-падиша), kusyak_biy (Кусяк-бий), mergen (Мерген), militia_ural (Ополченец Урала), samrau (Самрау), shulgen (Шульген), shurale (Шурале), sky_guard (Небесный страж), steppe_rider (Степной всадник), under_guard (Подземный страж), ural_batyr (Урал-батыр), urman_huzha (Урман-хужа), zarkum (Заркум), zayatulyak (Заятуляк)

JSON Schema hero.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://schemas.ufagame.local/hero.schema.json",
  "title": "Герой (heroes/<id>/hero.json)",
  "type": "object",
  "required": ["id", "name", "faction", "role", "rarity", "stats", "skills", "art"],
  "additionalProperties": false,
  "properties": {
    "$schema": {"type": "string"},
    "id": {"$ref": "common.schema.json#/$defs/id"},
    "name": {"type": "string", "minLength": 1, "maxLength": 40},
    "title": {"type": "string", "maxLength": 60, "description": "Прозвище, например «Сын Янбирде»"},
    "faction": {"$ref": "common.schema.json#/$defs/id", "description": "id фракции из factions/factions.json"},
    "role": {"enum": ["tank", "warrior", "archer", "mage", "support", "assassin"]},
    "rarity": {"enum": ["common", "rare", "elite", "legendary", "mythic", "ascended"], "description": "Базовая редкость героя"},
    "description": {"type": "string", "maxLength": 500},
    "lore": {"type": "string", "maxLength": 4000},
    "stats": {
      "type": "object",
      "required": ["hp", "atk", "def", "attack_interval_ms"],
      "additionalProperties": false,
      "properties": {
        "hp": {"type": "integer", "minimum": 1},
        "atk": {"type": "integer", "minimum": 0},
        "def": {"type": "integer", "minimum": 0},
        "attack_interval_ms": {"type": "integer", "minimum": 200, "description": "Пауза между обычными атаками"},
        "crit_chance": {"type": "number", "minimum": 0, "maximum": 1},
        "crit_damage": {"type": "number", "minimum": 1, "description": "Множитель крита, например 1.5"},
        "move_speed": {"type": "number", "minimum": 0, "description": "Скорость перемещения (единиц поля в секунду)"},
        "range": {"type": "number", "minimum": 0.5, "description": "Дальность атаки (единиц поля). Ближний бой ~1.5"}
      }
    },
    "skills": {
      "type": "array",
      "minItems": 1,
      "maxItems": 6,
      "items": {"$ref": "#/$defs/skill"},
      "description": "Ультимейт + 3 навыка"
    },
    "art": {
      "type": "object",
      "required": ["portrait", "skeleton"],
      "additionalProperties": false,
      "properties": {
        "portrait": {"$ref": "common.schema.json#/$defs/content_path"},
        "full": {"$ref": "common.schema.json#/$defs/content_path"},
        "skeleton": {"$ref": "common.schema.json#/$defs/content_path"},
        "projectile": {"$ref": "common.schema.json#/$defs/content_path", "description": "Снаряд (для стрелков и магов)"}
      }
    },
    "sounds": {
      "type": "object",
      "additionalProperties": {"$ref": "common.schema.json#/$defs/content_path"},
      "description": "Звуки по событиям: attack, skill, ultimate, hit, death"
    }
  },
  "$defs": {
    "target": {
      "type": "object",
      "required": ["side", "select"],
      "additionalProperties": false,
      "properties": {
        "side": {"enum": ["enemy", "ally"]},
        "select": {
          "enum": ["current", "nearest", "farthest", "lowest_hp", "highest_atk", "frontline", "backline", "random", "all", "self"],
          "description": "current — текущая цель атаки; lowest_hp — у кого меньше % здоровья; backline/frontline — задний/передний ряд"
        },
        "count": {"type": "integer", "minimum": 1, "maximum": 5}
      }
    },
    "effect": {
      "type": "object",
      "required": ["kind"],
      "additionalProperties": false,
      "properties": {
        "kind": {"enum": ["damage", "heal", "shield", "stun", "buff", "dot", "energy", "stat"]},
        "target": {"$ref": "#/$defs/target"},
        "multiplier": {"type": "number", "minimum": 0, "description": "Доля атаки героя (damage, heal, shield, dot за секунду)"},
        "stat": {"enum": ["atk", "def", "crit_chance", "attack_speed", "hp"], "description": "Для buff и stat"},
        "percent": {"type": "number", "description": "Изменение характеристики в %, отрицательное — ослабление"},
        "amount": {"type": "integer", "description": "Для energy: сколько энергии добавить (может быть отрицательным)"},
        "duration_ms": {"type": "integer", "minimum": 0},
        "chance": {"type": "number", "minimum": 0, "maximum": 1}
      }
    },
    "skill": {
      "type": "object",
      "required": ["id", "name", "type", "effects"],
      "additionalProperties": false,
      "properties": {
        "id": {"$ref": "common.schema.json#/$defs/id"},
        "name": {"type": "string", "minLength": 1, "maxLength": 40},
        "description": {"type": "string", "maxLength": 400},
        "type": {"enum": ["ultimate", "active", "passive"], "description": "ultimate — по полной энергии; active — по перезарядке; passive — по условию"},
        "trigger": {"enum": ["battle_start", "low_hp", "kill"], "description": "Только для passive"},
        "cooldown_ms": {"type": "integer", "minimum": 0, "description": "Для active"},
        "first_cast_ms": {"type": "integer", "minimum": 0, "description": "Для active: когда первый раз (от начала боя)"},
        "cast_time_ms": {"type": "integer", "minimum": 0, "description": "Сколько длится анимация применения"},
        "animation": {"enum": ["attack", "skill", "ultimate"]},
        "effects": {"type": "array", "minItems": 1, "items": {"$ref": "#/$defs/effect"}}
      }
    }
  }
}


JSON Schema skeleton.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://schemas.ufagame.local/skeleton.schema.json",
  "title": "Скелетная 2D-анимация героя (heroes/<id>/skeleton.json)",
  "description": "Открытый формат. Координаты в пикселях, ось Y вниз, герой смотрит вправо. Описание: docs/skeleton-format.md",
  "type": "object",
  "required": ["format", "version", "bones", "slots", "animations"],
  "additionalProperties": false,
  "properties": {
    "$schema": {"type": "string"},
    "format": {"const": "ufa-skeleton"},
    "version": {"const": 1},
    "size": {"type": "array", "items": {"type": "number"}, "minItems": 2, "maxItems": 2, "description": "Примерный размер героя [ширина, высота] для расстановки"},
    "bones": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["name"],
        "additionalProperties": false,
        "properties": {
          "name": {"type": "string", "pattern": "^[a-z][a-z0-9_]*$"},
          "parent": {"type": "string", "description": "Родительская кость; у корня отсутствует"},
          "x": {"type": "number", "description": "Смещение от родителя"},
          "y": {"type": "number"},
          "rotation": {"type": "number", "description": "Градусы, по часовой"},
          "scale_x": {"type": "number"},
          "scale_y": {"type": "number"}
        }
      }
    },
    "slots": {
      "type": "array",
      "description": "Картинки частей тела. Порядок в списке = порядок отрисовки (первая — сзади)",
      "items": {
        "type": "object",
        "required": ["name", "bone", "image"],
        "additionalProperties": false,
        "properties": {
          "name": {"type": "string"},
          "bone": {"type": "string"},
          "image": {"type": "string", "description": "Путь к PNG относительно папки героя"},
          "x": {"type": "number", "description": "Сдвиг картинки относительно кости"},
          "y": {"type": "number"},
          "rotation": {"type": "number"},
          "pivot": {"type": "array", "items": {"type": "number"}, "minItems": 2, "maxItems": 2, "description": "Точка картинки, совпадающая с костью, в пикселях от левого верхнего угла"}
        }
      }
    },
    "anchors": {
      "type": "object",
      "description": "Точки крепления: projectile (вылет снаряда), hit (куда попадают), overhead (над головой)",
      "additionalProperties": {
        "type": "object",
        "required": ["bone"],
        "additionalProperties": false,
        "properties": {"bone": {"type": "string"}, "x": {"type": "number"}, "y": {"type": "number"}}
      }
    },
    "animations": {
      "type": "object",
      "required": ["idle", "attack", "hit", "death"],
      "additionalProperties": {"$ref": "#/$defs/animation"}
    }
  },
  "$defs": {
    "key": {
      "type": "array",
      "minItems": 2,
      "maxItems": 3,
      "items": {"type": "number"},
      "description": "[время_сек, значение] или [время_сек, x, y]"
    },
    "animation": {
      "type": "object",
      "required": ["duration", "bones"],
      "additionalProperties": false,
      "properties": {
        "duration": {"type": "number", "exclusiveMinimum": 0},
        "loop": {"type": "boolean"},
        "bones": {
          "type": "object",
          "additionalProperties": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "rotate": {"type": "array", "items": {"$ref": "#/$defs/key"}, "description": "Поворот в градусах относительно позы покоя"},
              "translate": {"type": "array", "items": {"$ref": "#/$defs/key"}, "description": "Сдвиг [t, x, y] относительно позы покоя"},
              "scale": {"type": "array", "items": {"$ref": "#/$defs/key"}, "description": "Масштаб [t, sx, sy]"}
            }
          }
        },
        "alpha": {"type": "array", "items": {"$ref": "#/$defs/key"}, "description": "Прозрачность всего героя [t, 0..1]"},
        "events": {
          "type": "array",
          "items": {
            "type": "object",
            "required": ["t", "name"],
            "additionalProperties": false,
            "properties": {"t": {"type": "number"}, "name": {"enum": ["hit", "projectile", "sound", "effect"]}, "value": {"type": "string"}}
          }
        }
      }
    }
  }
}


Пример объекта из игры:
{
  "id": "aihylu",
  "name": "Айхылыу",
  "title": "Лунная дева",
  "faction": "sky_dwellers",
  "role": "support",
  "rarity": "legendary",
  "description": "Дочь Самрау, хранительница лунного света.",
  "lore": "Айхылыу выходит на небо по ночам. Её свет возвращает силы раненым и не даёт тьме подойти близко.",
  "stats": {
    "hp": 3150,
    "atk": 140,
    "def": 85,
    "attack_interval_ms": 1400
  },
  "skills": [
    {
      "id": "aih_ult",
      "name": "Полнолуние",
      "description": "Лечит всех союзников на 220% атаки и даёт щит на 120% атаки.",
      "type": "ultimate",
      "cast_time_ms": 900,
      "animation": "ultimate",
      "effects": [
        {
          "kind": "heal",
          "target": {
            "side": "ally",
            "select": "all"
          },
          "multiplier": 2.2
        },
        {
          "kind": "shield",
          "target": {
            "side": "ally",
            "select": "all"
          },
          "multiplier": 1.2,
          "duration_ms": 6000
        }
      ]
    },
    {
      "id": "aih_s1",
      "name": "Лунный свет",
      "description": "Лечит самого раненого союзника на 320% атаки.",
      "type": "active",
      "cooldown_ms": 7000,
      "first_cast_ms": 4000,
      "cast_time_ms": 500,
      "animation": "skill",
      "effects": [
        {
          "kind": "heal",
          "target": {
            "side": "ally",
            "select": "lowest_hp"
          },
          "multiplier": 3.2
        }
      ]
    },
    {
      "id": "aih_s2",
      "name": "Сон",
      "description": "Оглушает врага с наибольшей атакой на 2 с.",
      "type": "active",
      "cooldown_ms": 13000,
      "first_cast_ms": 7000,
      "cast_time_ms": 500,
      "animation": "skill",
      "effects": [
        {
          "kind": "stun",
          "target": {
            "side": "enemy",
            "select": "highest_atk"
          },
          "duration_ms": 2000
        }
      ]
    },
    {
      "id": "aih_p",
      "name": "Тихий свет",
      "description": "В начале боя союзники получают щит на 100% атаки.",
      "type": "passive",
      "trigger": "battle_start",
      "effects": [
        {
          "kind": "shield",
          "target": {
            "side": "ally",
            "select": "all"
          },
          "multiplier": 1.0,
          "duration_ms": 8000
        }
      ]
    }
  ],
  "art": {
    "portrait": "heroes/aihylu/portrait.png",
    "full": "heroes/aihylu/full.png",
    "skeleton": "heroes/aihylu/skeleton.json",
    "projectile": "heroes/aihylu/projectile.png"
  }
}

Верни только готовый patch.json и список файлов, которые нужно положить в files/.
````

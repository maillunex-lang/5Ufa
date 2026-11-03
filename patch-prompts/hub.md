# Промпт для ИИ: Главный экран

Скопируйте текст ниже в ИИ-ассистента. Актуальная версия (с вашими правками) — кнопка «Промпт для ИИ» в разделе админки.

````text
Ты помогаешь наполнять контент мобильной игры (AFK RPG по мотивам башкирских легенд). Раздел: «Главный экран» (hub).

Сделай ZIP-патч для админки. Структура архива:
  patch.json — описание патча
  files/<путь в контенте> — картинки и другие файлы

patch.json: {"id": "<латиница-и-дефисы>", "format_version": 1, "section": "hub", "description": "что меняется", "operations": [ ... ]}

Операции: add (новый объект, data — полный объект), update (data — только изменяемые поля; объекты сливаются, списки заменяются целиком), delete (удалить объект), put_file (положить файл: {"op":"put_file","path":"..."}), delete_file. Для add/update можно указать files — пути картинок из архива.

Правила: id и пути — латиница в нижнем регистре, цифры, _ - . /; JSON в UTF-8; графика PNG/WebP, звук OGG. Тексты — на русском.

Устройство объектов раздела: {"kind": "single", "file": "ui/hub.json", "id": "hub"}

Текущие объекты: hub (Главный экран)

JSON Schema hub.schema.json:
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://schemas.ufagame.local/hub.schema.json",
  "title": "Главный экран «Город» (ui/hub.json): здания, меню, навигация",
  "type": "object",
  "required": ["background", "background_height", "buildings", "side_menu", "top_buttons", "bottom_nav"],
  "additionalProperties": false,
  "$defs": {
    "path": {"type": "string", "pattern": "^ui/.+\\.(png|webp|jpg)$", "description": "Картинка из контента"},
    "action": {
      "type": "object", "additionalProperties": false, "minProperties": 1, "maxProperties": 1,
      "properties": {
        "scene": {"enum": ["campaign", "heroes", "summon", "inventory", "test_battle", "hub", "more"], "description": "Открыть экран"},
        "soon": {"type": "string", "minLength": 1, "description": "Показать сообщение (раздел ещё не готов)"}
      }
    },
    "badge": {"enum": ["heroes", "summon", "campaign"], "description": "Красная точка: можно улучшить героя / есть свитки / AFK-награда"},
    "item": {
      "type": "object", "required": ["id", "title", "icon", "action"], "additionalProperties": false,
      "properties": {
        "id": {"$ref": "common.schema.json#/$defs/id"},
        "title": {"type": "string"},
        "icon": {"$ref": "#/$defs/path"},
        "badge": {"$ref": "#/$defs/badge"},
        "big": {"type": "boolean"},
        "action": {"$ref": "#/$defs/action"}
      }
    }
  },
  "properties": {
    "$schema": {"type": "string"},
    "subtitle": {"type": "string"},
    "emblem": {"$ref": "#/$defs/path"},
    "background": {"$ref": "#/$defs/path"},
    "background_height": {"type": "integer", "minimum": 1280, "maximum": 4000},
    "start_scroll": {"type": "integer", "minimum": 0},
    "buildings": {
      "type": "array",
      "items": {
        "type": "object", "required": ["id", "image", "x", "y", "action"], "additionalProperties": false,
        "properties": {
          "id": {"$ref": "common.schema.json#/$defs/id"},
          "title": {"type": "string", "description": "Подпись-табличка; без неё — просто украшение"},
          "image": {"$ref": "#/$defs/path"},
          "x": {"type": "number", "minimum": 0, "maximum": 720, "description": "Центр здания"},
          "y": {"type": "number", "minimum": 0},
          "scale": {"type": "number", "exclusiveMinimum": 0, "maximum": 3},
          "badge": {"$ref": "#/$defs/badge"},
          "action": {"$ref": "#/$defs/action"}
        }
      }
    },
    "side_menu": {"type": "array", "maxItems": 7, "items": {"$ref": "#/$defs/item"}},
    "top_buttons": {"type": "array", "maxItems": 3, "items": {"$ref": "#/$defs/item"}},
    "bottom_nav": {"type": "array", "minItems": 1, "maxItems": 5, "items": {"$ref": "#/$defs/item"}},
    "shop_soon": {"type": "string"}
  }
}


Пример объекта из игры:
{
  "$schema": "../../shared/schemas/hub.schema.json",
  "subtitle": "Пробуждение легенд",
  "emblem": "ui/hub/emblem.png",
  "background": "ui/hub/background.webp",
  "background_height": 1400,
  "start_scroll": 0,
  "buildings": [
    {
      "id": "fortress",
      "title": "Крепость",
      "image": "ui/hub/building_fortress.png",
      "x": 370,
      "y": 425,
      "scale": 0.95,
      "badge": "heroes",
      "action": {
        "scene": "heroes"
      }
    },
    {
      "id": "summon",
      "title": "Призыв",
      "image": "ui/hub/building_summon.png",
      "x": 225,
      "y": 580,
      "scale": 0.85,
      "badge": "summon",
      "action": {
        "scene": "summon"
      }
    },
    {
      "id": "guild",
      "title": "Гильдия",
      "image": "ui/hub/building_guild.png",
      "x": 575,
      "y": 580,
      "scale": 0.8,
      "action": {
        "soon": "Гильдии появятся на этапе 8."
      }
    },
    {
      "id": "tavern",
      "title": "Таверна",
      "image": "ui/hub/building_tavern.png",
      "x": 185,
      "y": 840,
      "scale": 0.8,
      "action": {
        "soon": "Таверна с доской заданий появится на этапе 7."
      }
    },
    {
      "id": "arena",
      "title": "Арена",
      "image": "ui/hub/building_arena.png",
      "x": 565,
      "y": 820,
      "scale": 0.8,
      "action": {
        "soon": "Арена появится на этапе 8."
      }
    },
    {
      "id": "campaign",
      "title": "Кампания",
      "image": "ui/hub/building_campaign.png",
      "x": 215,
      "y": 1000,
      "scale": 0.8,
      "badge": "campaign",
      "action": {
        "scene": "campaign"
      }
    },
    {
      "id": "dungeon",
      "title": "Подземелья",
      "image": "ui/hub/building_dungeon.png",
      "x": 555,
      "y": 1015,
      "scale": 0.72,
      "action": {
        "soon": "Подземелья (башня испытаний и лабиринт) появятся на этапе 7."
      }
    }
  ],
  "side_menu": [
    {
      "id": "events",
      "title": "События",
      "icon": "ui/hub/icon_events.png",
      "action": {
        "soon": "События появятся позже."
      }
    },
    {
      "id": "tasks",
      "title": "Задания",
      "icon": "ui/hub/icon_tasks.png",
      "action": {
        "soon": "Ежедневные задания появятся на этапе 7."
      }
    },
    {
      "id": "rewards",
      "title": "Награды",
      "icon": "ui/hub/icon_rewards.png",
      "badge": "campaign",
      "action": {
        "scene": "campaign"
      }
    },
    {
      "id": "battle_pass",
      "title": "Боевой\nпропуск",
      "icon": "ui/hub/icon_battle_pass.png",
      "action": {
        "soon": "Боевой пропуск появится на этапе 9."
      }
    },
    {
      "id": "daily",
      "title": "Ежедневный\nвход",
      "icon": "ui/hub/icon_daily.png",
      "action": {
        "soon": "Награды за вход появятся позже."
      }
    }
  ],
  "top_buttons": [
    {
      "id": "mail",
      "title": "",
      "icon": "ui/hub/icon_mail.png",
      "action": {
        "soon": "Почта появится позже."
      }
    },
    {
      "id": "settings",
      "title": "",
      "icon": "ui/hub/icon_settings.png",
      "action": {
        "scene": "more"
      }
    }
  ],
  "bottom_nav": [
    {
      "id": "nav_heroes",
      "title": "Герои",
      "icon": "ui/hub/icon_heroes.png",
      "badge": "heroes",
      "action": {
        "scene": "heroes"
      }
    },
    {
      "id": "inventory",
      "title": "Инвентарь",
      "icon": "ui/hub/icon_inventory.png",
      "action": {
        "scene": "inventory"
      }
    },
    {
      "id": "city",
      "title": "Город",
      "icon": "ui/hub/icon_city.png",
      "big": true,
      "action": {
        "scene": "hub"
      }
    },
    {
      "id": "quests",
      "title": "Квесты",
      "icon": "ui/hub/icon_quests.png",
      "action": {
        "soon": "Квесты появятся на этапе 7."
      }
    },
    {
      "id": "world",
      "title": "Мир",
      "icon": "ui/hub/icon_world.png",
      "badge": "campaign",
      "action": {
        "scene": "campaign"
      }
    }
  ],
  "shop_soon": "Магазин появится на этапе 9."
}

Верни только готовый patch.json и список файлов, которые нужно положить в files/.
````

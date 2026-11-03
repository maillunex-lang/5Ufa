# Промпт для ИИ: Пакеты загрузки

Скопируйте текст ниже в ИИ-ассистента. Актуальная версия (с вашими правками) — кнопка «Промпт для ИИ» в разделе админки.

````text
Ты помогаешь наполнять контент мобильной игры (AFK RPG по мотивам башкирских легенд). Раздел: «Пакеты загрузки» (packages).

Сделай ZIP-патч для админки. Структура архива:
  patch.json — описание патча
  files/<путь в контенте> — картинки и другие файлы

patch.json: {"id": "<латиница-и-дефисы>", "format_version": 1, "section": "packages", "description": "что меняется", "operations": [ ... ]}

Операции: add (новый объект, data — полный объект), update (data — только изменяемые поля; объекты сливаются, списки заменяются целиком), delete (удалить объект), put_file (положить файл: {"op":"put_file","path":"..."}), delete_file. Для add/update можно указать files — пути картинок из архива.

Правила: id и пути — латиница в нижнем регистре, цифры, _ - . /; JSON в UTF-8; графика PNG/WebP, звук OGG. Тексты — на русском.

Устройство объектов раздела: {"kind": "single", "file": "packages.json", "id": "packages"}

Текущие объекты: packages (Пакеты загрузки)

Пример объекта из игры:
{
  "$schema": "../shared/schemas/content-packages.schema.json",
  "min_client_version": "0.1.0",
  "packages": [
    {
      "id": "core",
      "title": "Интерфейс и настройки",
      "required": true,
      "priority": 0,
      "include": [
        "config/**",
        "localization/**",
        "ui/**",
        "fonts/**",
        "factions/**",
        "battle/**",
        "summon/**"
      ]
    },
    {
      "id": "heroes",
      "title": "Герои",
      "required": true,
      "priority": 5,
      "include": [
        "heroes/**"
      ]
    },
    {
      "id": "tutorial",
      "title": "Обучение",
      "required": true,
      "priority": 10,
      "include": [
        "tutorial/**"
      ]
    },
    {
      "id": "chapter_1",
      "title": "Глава 1",
      "required": true,
      "priority": 20,
      "include": [
        "campaign/chapter_1/**"
      ]
    },
    {
      "id": "chapter_2",
      "title": "Глава 2",
      "required": false,
      "priority": 30,
      "include": [
        "campaign/chapter_2/**"
      ]
    },
    {
      "id": "chapter_3",
      "title": "Глава 3",
      "required": false,
      "priority": 50,
      "include": [
        "campaign/chapter_3/**"
      ]
    },
    {
      "id": "chapter_4",
      "title": "Глава 4",
      "required": false,
      "priority": 60,
      "include": [
        "campaign/chapter_4/**"
      ]
    },
    {
      "id": "chapter_5",
      "title": "Глава 5",
      "required": false,
      "priority": 70,
      "include": [
        "campaign/chapter_5/**"
      ]
    }
  ]
}

Верни только готовый patch.json и список файлов, которые нужно положить в files/.
````

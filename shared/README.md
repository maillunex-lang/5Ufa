# /shared — JSON Schema контента

Единый источник правды о формате данных для сервера, админки и игры.

| Файл | Что описывает |
|---|---|
| `schemas/common.schema.json` | Общие типы: id, sha256, цвет, путь к файлу, ключ текста |
| `schemas/content-packages.schema.json` | `content/packages.json` — деление контента на пакеты загрузки |
| `schemas/manifest.schema.json` | Ответ сервера с манифестом загрузки |
| `schemas/game_settings.schema.json` | `config/game_settings.json` — название игры, языки, цвета |
| `schemas/localization.schema.json` | `localization/<язык>.json` — тексты |
| `schemas/patch.schema.json` | `patch.json` в ZIP-патчах |
| `schemas/registry.json` | Какая схема проверяет какой файл контента |

Стандарт: JSON Schema draft 2020-12. Ссылки между схемами — через `$ref` на `$id`.

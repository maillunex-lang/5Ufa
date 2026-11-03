# /content — базовый контент

Из этой папки при первом запуске сервера собирается релиз контента №1.
Сейчас здесь заглушки; ИИ-арт и правки приходят через админку и ZIP-патчи.

- `packages.json` — пакеты загрузки (какие файлы обязательны при старте, какие качаются в фоне).
- Заглушки PNG генерирует `python3 scripts/gen_placeholders.py`.
- Проверка: `cd server && python -m app.cli content validate` (или на VPS
  `docker compose exec api python -m app.cli content validate`).

Важно: после первого запуска изменения этой папки **не** публикуются автоматически,
чтобы не затереть правки, сделанные в админке. Обновить базовый контент вручную:
`docker compose exec api python -m app.cli content import --publish` (после деплоя).

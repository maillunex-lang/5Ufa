# Доставка контента: манифест, пакеты, докачка

APK содержит только код-загрузчик. Вся графика, звук, музыка и данные скачиваются с VPS.

## Как устроено на сервере

1. Контент — это папка с файлами (базовый — `/content` в репозитории; позже — изменения из админки и ZIP-патчей).
2. `content/packages.json` делит файлы на **пакеты** по маскам путей. Пакет помечен
   `required: true` (качается до входа в игру: интерфейс, обучение, 1-я глава) или `false` (в фоне).
3. Импорт проверяет каждый JSON по схемам из `/shared/schemas` (какая схема к какому файлу —
   в `shared/schemas/registry.json`), кладёт файлы в хранилище **по SHA-256** и создаёт **релиз** —
   неизменяемый снимок (манифест) в базе.
4. **Каналы**: `live` (видят все игроки) и `test` (тестовые аккаунты). Публикация и откат —
   это просто переключение канала на нужный релиз; файлы старых релизов остаются в хранилище.

## API

### `GET /api/v1/content/manifest`

Полный адрес: `https://tts-ufa.ru/games/server/api/v1/content/manifest`

Ответ (схема: `shared/schemas/manifest.schema.json`):

```json
{
  "schema_version": 1,
  "release": 1,
  "channel": "live",
  "content_hash": "6578…",
  "min_client_version": "0.1.0",
  "base_url": "/games/server/content/files/",
  "total_size": 7061,
  "packages": [
    {
      "id": "core", "title": "Интерфейс и настройки",
      "required": true, "priority": 0,
      "version": "ffb276cfc5790d9f", "size": 4996,
      "files": [
        {"path": "ui/logo.png", "size": 3360, "sha256": "115d0c03…"}
      ]
    }
  ]
}
```

- Канал выбирает сервер: тестовые аккаунты получают `test`, остальные `live` (нужен заголовок `Authorization`).
- Заголовок `ETag`; при повторном запросе с `If-None-Match: <etag>` сервер отвечает `304` без тела.
- `version` пакета меняется, только если изменился хотя бы один его файл.
- Если версия APK меньше `min_client_version` — клиент просит обновить приложение.

### Файлы

`GET {base_url}{sha256[0:2]}/{sha256}` — например `https://tts-ufa.ru/games/server/content/files/11/115d0c03…`

`base_url` учитывает `PUBLIC_PATH_PREFIX` из `.env`; клиент склеивает его с адресом домена.

- Отдаёт Nginx напрямую (быстро, без нагрузки на API).
- Поддерживается `Range: bytes=N-` → ответ `206` — **докачка после обрыва**.
- `Cache-Control: immutable` — файл по этому адресу никогда не меняется.

## Алгоритм клиента (`client/scripts/content.gd`)

1. Запросить манифест (с `If-None-Match`). При `304` — всё актуально.
2. Сравнить с локальным `user://content/state.json` (путь → sha256).
3. Список к скачиванию = файлы, у которых локальный sha256 отсутствует или отличается.
4. Сначала пакеты `required` по `priority`, экран загрузки показывает «N МБ из M МБ».
5. Каждый файл качается во `user://content/.partial/<sha256>`; при обрыве — продолжение с `Range`.
6. После скачивания — проверка SHA-256; при несовпадении — файл удаляется и качается заново.
7. Готовый файл переносится в `user://content/<path>`, запись в `state.json`.
8. Пакеты `required: false` — в фоне во время игры.
9. Файлы, которых больше нет в манифесте, удаляются.

## Команды на VPS

```bash
docker compose exec api python -m app.cli content validate        # проверить базовый контент
docker compose exec api python -m app.cli content list            # все релизы
docker compose exec api python -m app.cli content status          # что в каналах live/test
docker compose exec api python -m app.cli content publish 3 --channel test   # релиз 3 в тест
docker compose exec api python -m app.cli content publish 3 --channel live   # опубликовать
docker compose exec api python -m app.cli content publish 2 --channel live   # откат к релизу 2
```
На этапе 6 всё это делается кнопками в админке.

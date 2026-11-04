# Развёртывание тестового окружения

Деплой автоматический: push в `main` → GitHub Actions (`.github/workflows/deploy.yml`) прогоняет тесты → по SSH запускает `scripts/deploy.sh` в папке `VPS_APP_DIR` (сейчас `/root/ufagame`). Нужны уже заданные секреты репозитория: `VPS_HOST`, `VPS_PORT`, `VPS_USER`, `VPS_SSH_KEY`, `VPS_KNOWN_HOSTS`, `VPS_APP_DIR`.

Что делает `scripts/deploy.sh`:
1. Если в папке код другой раскладки (старая игра), сохраняет его в локальную git-ветку `backup/old-game-*`, затем `reset --hard` на `origin/main`. Файлы вне git (`.env`, `backups/`) не трогаются.
2. Порт берёт из `HTTP_PORT` старого `.env` (там 8085, он уже подключён к nginx как `https://tts-ufa.ru/games/server/`), записывает в `.5ufa.env`. Слушает только `127.0.0.1`.
3. `docker compose up -d --build` для проекта `5ufa` (чужие контейнеры не затрагиваются), ждёт `/health`.

Данные игроков лежат в docker volume `5ufa-data`; ежедневный бэкап SQLite — в `/data/backups` (14 копий, `BACKUP_KEEP`).

## Первый пароль админки
Создаётся при первом запуске и в журнал не печатается (репозиторий публичный):
```
cd /root/ufagame && ./scripts/admin-password.sh
```
Админка: https://tts-ufa.ru/games/server/admin/ — смените пароль и удалите файл. Свой пароль можно задать заранее: `ADMIN_PASSWORD=` в `.5ufa.env`.

## Ограничения
- Работа через HTTPS домена tts-ufa.ru, порт сервера наружу не открыт.
- Восстановление из бэкапа: остановить контейнер, заменить `/data/game.db` копией из `/data/backups`.

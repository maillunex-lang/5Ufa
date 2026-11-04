#!/usr/bin/env bash
# Деплой тестового сервера 5Ufa на VPS. Запускается GitHub Actions по SSH или вручную:
#   bash scripts/deploy.sh [ветка]
# Чужие проекты не затрагиваются: свой docker-проект "5ufa", порт только на 127.0.0.1.
set -euo pipefail

# git reset ниже перезапишет этот файл, а bash читает скрипт по частям: выполняемся из копии.
if [ -z "${DEPLOY_APP_DIR:-}" ]; then
  DEPLOY_APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
  TMP_SELF="$(mktemp /tmp/5ufa-deploy.XXXXXX.sh)"
  cp "$0" "$TMP_SELF"
  DEPLOY_APP_DIR="$DEPLOY_APP_DIR" exec bash "$TMP_SELF" "$@"
fi
trap 'rm -f "$0"' EXIT
cd "$DEPLOY_APP_DIR"
BRANCH="${1:-main}"
ENV_FILE=".5ufa.env"
log() { echo "[deploy $(date -u +%H:%M:%S)] $*"; }

command -v docker >/dev/null 2>&1 || { log "Docker не найден"; exit 1; }

# 1. Код. Старая игра (другая раскладка файлов) сохраняется в локальной ветке backup/old-game-*.
# Репозиторий публичный: читаем по HTTPS (ключ GitHub на VPS не нужен), адрес origin переводим на HTTPS.
git remote set-url origin https://github.com/maillunex-lang/5Ufa.git
git fetch --quiet origin "$BRANCH"
if [ ! -f server/src/app.js ]; then
  b="backup/old-game-$(date -u +%Y%m%d-%H%M%S)"
  git branch -f "$b" HEAD && log "прежний код сохранён в ветке $b"
fi
if ! git diff --quiet HEAD 2>/dev/null; then git stash push -q -m "5ufa-predeploy-$(date -u +%s)" && log "локальные правки отложены в git stash"; fi
git reset --hard --quiet "origin/$BRANCH"
log "код: $(git rev-parse --short HEAD)"

# 2. Порт: тот, что уже подключён к nginx для /games/server (HTTP_PORT из .env старого проекта), иначе 8085.
if [ ! -f "$ENV_FILE" ]; then
  port="$(sed -n 's/^HTTP_PORT=//p' .env 2>/dev/null | tail -n1 | tr -d '[:space:]"'"'")"
  echo "PORT=${port:-8085}" > "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"
PORT="$(sed -n 's/^PORT=//p' "$ENV_FILE" | tail -n1)"
if ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":${PORT}\$" && ! docker ps --format '{{.Names}}' | grep -qx 5ufa-server; then
  log "ОШИБКА: порт $PORT занят чужим процессом. Измените PORT в $ENV_FILE (и в nginx-сниппете)"; exit 1
fi

# 3. Сборка и запуск. Данные игроков лежат в docker volume 5ufa-data и не затрагиваются.
docker compose --env-file "$ENV_FILE" up -d --build --remove-orphans

# 4. Проверка
for i in $(seq 1 30); do
  if curl -fsS --max-time 5 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    log "health OK: $(curl -fsS --max-time 5 "http://127.0.0.1:${PORT}/health")"
    mkdir -p .deploy && echo "$(git rev-parse HEAD) $(date -u +%FT%TZ)" > .deploy/last_success
    log "готово: https://tts-ufa.ru/games/server/admin/"
    exit 0
  fi
  sleep 2
done
log "health НЕ отвечает на порту $PORT"; docker compose --env-file "$ENV_FILE" logs --tail=40 server || true
exit 1

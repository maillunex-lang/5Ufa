#!/usr/bin/env bash
# Деплой на VPS. Запускается GitHub Actions по SSH (или вручную):
#   bash scripts/deploy.sh            # обновиться до последнего main
#   bash scripts/deploy.sh main       # явно указать ветку
#
# Шаги: бэкап базы -> git обновление -> сборка -> миграции -> запуск -> проверка /health.
# При любой ошибке: откат миграций и кода к прошлой версии, повторный запуск.
set -euo pipefail

# git reset ниже перезапишет этот файл, а bash читает скрипт по частям.
# Поэтому сначала копируем себя во временный файл и выполняемся из копии.
if [ -z "${DEPLOY_APP_DIR:-}" ]; then
    DEPLOY_APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
    TMP_SELF="$(mktemp /tmp/ufagame-deploy.XXXXXX.sh)"
    cp "$0" "$TMP_SELF"
    DEPLOY_APP_DIR="$DEPLOY_APP_DIR" exec bash "$TMP_SELF" "$@"
fi
trap 'rm -f "$0"' EXIT

cd "$DEPLOY_APP_DIR"
BRANCH="${1:-main}"
LOG_DIR=".deploy"
mkdir -p "$LOG_DIR"

if [ ! -f .env ]; then
    echo "ОШИБКА: нет файла .env. Создайте его: cp .env.example .env && nano .env" >&2
    exit 1
fi
# Токен загрузки APK (обновления приложения): создаём один раз, если его ещё нет
if ! grep -qE '^CLIENT_UPLOAD_TOKEN=.+' .env; then
    sed -i '/^CLIENT_UPLOAD_TOKEN=/d' .env
    echo "CLIENT_UPLOAD_TOKEN=$(openssl rand -hex 32)" >> .env
    echo "[deploy] создан CLIENT_UPLOAD_TOKEN в .env (добавьте его в секреты GitHub, см. docs/app-updates.md)"
fi
# Секреты из GitHub Actions приходят строками ИМЯ=значение на стандартный вход (не в командной строке,
# чтобы не попасть в список процессов и логи). Разрешены только имена из списка.
if [ ! -t 0 ]; then
    while IFS= read -r -t 10 line; do
        name="${line%%=*}"; value="${line#*=}"
        case "$name" in
            GEMINI_API_KEY) ;;
            *) continue ;;
        esac
        # Ключи — только буквы, цифры, . - и _ ; всё прочее (пробелы, переносы при вставке) отбрасываем
        value="$(printf '%s' "$value" | tr -cd 'A-Za-z0-9._-')"
        [ -n "$value" ] || continue
        # Сравниваем без передачи ключа в аргументах команд (их видно в списке процессов)
        current="$(sed -n "s/^$name=//p" .env | tail -n 1)"
        if [ "$current" != "$value" ]; then
            sed -i "/^$name=/d" .env
            printf '%s=%s\n' "$name" "$value" >> .env
            echo "[deploy] $name обновлён в .env из секретов GitHub"
        fi
    done || true
fi
chmod 600 .env 2>/dev/null || true
set -a; . ./.env; set +a
HTTP_PORT="${HTTP_PORT:-8085}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
mkdir -p "$BACKUP_DIR/predeploy"

log() { echo "[deploy $(date -u +%H:%M:%S)] $*"; }

health_check() {
    local url="http://127.0.0.1:${HTTP_PORT}/health"
    for i in $(seq 1 30); do
        if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
            log "health OK: $(curl -fsS --max-time 5 "$url")"
            return 0
        fi
        sleep 3
    done
    log "health НЕ отвечает: $url"
    curl -sS --max-time 5 "$url" || true
    return 1
}

current_db_revision() {
    # Текущая версия схемы базы (пусто, если сервис ещё не запущен)
    docker compose exec -T api alembic current 2>/dev/null | grep -oE '^[0-9A-Za-z_]+' | head -1 || true
}

PREV_SHA="$(git rev-parse HEAD)"
PREV_REV="$(current_db_revision)"
log "текущая версия кода: ${PREV_SHA:0:8}, схема БД: ${PREV_REV:-нет}"

# 1. Бэкап базы перед изменениями (если база уже работает)
if docker compose ps --status running postgres 2>/dev/null | grep -q postgres; then
    DUMP="$BACKUP_DIR/predeploy/db-$(date -u +%Y%m%d-%H%M%S)-${PREV_SHA:0:8}.dump"
    log "бэкап базы -> $DUMP"
    docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom > "$DUMP"
    # храним 10 последних предеплойных дампов
    ls -1t "$BACKUP_DIR"/predeploy/db-*.dump 2>/dev/null | tail -n +11 | xargs -r rm --
fi

# 2. Обновление кода
log "получаю код из origin/$BRANCH"
git fetch --quiet origin "$BRANCH"
git reset --hard --quiet "origin/$BRANCH"
NEW_SHA="$(git rev-parse HEAD)"
export GIT_SHA="$NEW_SHA"
log "новая версия кода: ${NEW_SHA:0:8}"

rollback() {
    set +e
    log "!!! ОШИБКА ДЕПЛОЯ — ОТКАТ к ${PREV_SHA:0:8}"
    if [ -n "$PREV_REV" ]; then
        local now_rev
        now_rev="$(docker compose run --rm -T api alembic current 2>/dev/null | grep -oE '^[0-9A-Za-z_]+' | head -1)"
        if [ -n "$now_rev" ] && [ "$now_rev" != "$PREV_REV" ]; then
            log "откат схемы БД $now_rev -> $PREV_REV"
            docker compose run --rm -T api alembic downgrade "$PREV_REV"
        fi
    fi
    git reset --hard --quiet "$PREV_SHA"
    export GIT_SHA="$PREV_SHA"
    docker compose up -d --build --remove-orphans
    docker compose up -d --force-recreate --no-deps nginx
    if health_check; then
        log "откат выполнен, работает прежняя версия ${PREV_SHA:0:8}"
    else
        log "!!! после отката сервер тоже не отвечает — нужна ручная проверка: docker compose logs --tail=200"
    fi
    exit 1
}
trap rollback ERR

# 3. Сборка и миграции
log "сборка образов"
docker compose build
log "запуск базы и Redis"
docker compose up -d postgres redis
log "миграции базы"
docker compose run --rm -T api alembic upgrade head
# Базовый контент из репозитория (/content): если изменился — изменённые файлы переносятся поверх текущей
# версии игры, правки из админки сохраняются (см. docs/admin.md, «Деплой и правки из админки»).
# Чтобы деплой не трогал контент, поставьте в .env AUTO_PUBLISH_BASE_CONTENT=false
if [ "${AUTO_PUBLISH_BASE_CONTENT:-true}" = "true" ]; then
    log "импорт базового контента (только изменения репозитория, правки админки сохраняются)"
    docker compose run --rm -T api python -m app.cli content import --publish-if-new --comment "Базовый контент ${NEW_SHA:0:8}"
else
    log "первичный импорт контента (только если база пустая)"
    docker compose run --rm -T api python -m app.cli content import --if-empty --publish
fi

# 4. Запуск всего стека
log "запуск сервисов"
docker compose up -d --remove-orphans
# Конфиг Nginx монтируется из папки и применяется только при старте контейнера,
# поэтому пересоздаём Nginx всегда (перерыв ~1 секунда).
docker compose up -d --force-recreate --no-deps nginx

# 5. Проверка
health_check

trap - ERR
echo "$NEW_SHA" > "$LOG_DIR/last_success"
docker image prune -f >/dev/null 2>&1 || true
log "ДЕПЛОЙ УСПЕШЕН: ${NEW_SHA:0:8}"
# Проверка доступа к ИИ (не влияет на результат деплоя, ключ в лог не выводится)
if [ -n "${GEMINI_API_KEY:-}" ]; then
    log "$(docker compose exec -T api python -m app.cli ai check 2>&1 | tr '\n' ' ' || true)"
fi

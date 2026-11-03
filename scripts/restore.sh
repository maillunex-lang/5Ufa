#!/usr/bin/env bash
# Восстановление из бэкапа (база + контент).
#   bash scripts/restore.sh                 # показать список бэкапов
#   bash scripts/restore.sh 2026-11-03_0300 # восстановить выбранный
# ВНИМАНИЕ: текущие данные базы будут ЗАМЕНЕНЫ. Перед восстановлением
# автоматически делается свежий бэкап текущего состояния.
# (На этапе 6 восстановление появится кнопкой в админке.)
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
BACKUP_DIR="${BACKUP_DIR:-./backups}"

if [ $# -lt 1 ]; then
    echo "Доступные бэкапы:"
    ls -1 "$BACKUP_DIR" | grep -E '^20' || echo "  (пока нет)"
    echo
    echo "Использование: bash scripts/restore.sh <имя_папки>"
    exit 0
fi

SRC="$BACKUP_DIR/$1"
[ -f "$SRC/db.dump" ] || { echo "Нет файла $SRC/db.dump" >&2; exit 1; }

echo ">>> Проверка целостности бэкапа"
(cd "$SRC" && sha256sum -c SHA256SUMS)

read -r -p "Восстановить $1? Текущие данные будут заменены. Введите YES: " ans
[ "$ans" = "YES" ] || { echo "Отменено"; exit 1; }

echo ">>> Свежий бэкап текущего состояния"
docker compose exec -T backup /bin/sh /backup/backup-now.sh

echo ">>> Останавливаю API"
docker compose stop nginx api

echo ">>> Восстанавливаю базу"
docker compose exec -T postgres pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner < "$SRC/db.dump"

echo ">>> Восстанавливаю файлы контента (добавляются недостающие)"
docker compose run --rm -T --no-deps -v "$(realpath "$SRC")":/restore:ro api \
    sh -c 'tar -xzf /restore/content.tar.gz -C /data/content-store'

echo ">>> Запускаю сервисы"
docker compose up -d
echo "Готово. Проверка: curl http://127.0.0.1:${HTTP_PORT:-8085}/health"

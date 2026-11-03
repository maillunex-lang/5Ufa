#!/bin/sh
# Контейнер бэкапов: раз в сутки в BACKUP_HOUR (UTC) делает
#   1) дамп базы PostgreSQL  -> /backups/YYYY-MM-DD_HHMM/db.dump
#   2) архив хранилища контента -> /backups/YYYY-MM-DD_HHMM/content.tar.gz
# и удаляет бэкапы старше BACKUP_RETENTION_DAYS дней.
# Ручной запуск: docker compose exec backup /bin/sh /backup/backup-now.sh
set -eu

HOUR="${BACKUP_HOUR:-0}"
echo "[backup] сервис бэкапов запущен, ежедневный бэкап в ${HOUR}:00 UTC, хранение ${BACKUP_RETENTION_DAYS:-14} дн."

last_day=""
while true; do
    now_hour=$(date -u +%H | sed 's/^0//')
    [ -z "$now_hour" ] && now_hour=0
    today=$(date -u +%F)
    if [ "$now_hour" -eq "$HOUR" ] && [ "$today" != "$last_day" ]; then
        if /bin/sh /backup/backup-now.sh; then
            last_day="$today"
        else
            echo "[backup] ОШИБКА бэкапа, повтор через 10 минут"
        fi
    fi
    sleep 600
done

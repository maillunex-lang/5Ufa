#!/bin/sh
# Контейнер бэкапов: раз в сутки в BACKUP_HOUR (UTC) делает
#   1) дамп базы PostgreSQL  -> /backups/YYYY-MM-DD_HHMM/db.dump
#   2) архив хранилища контента -> /backups/YYYY-MM-DD_HHMM/content.tar.gz
# и удаляет бэкапы старше BACKUP_RETENTION_DAYS дней.
# Ручной запуск: docker compose exec backup /bin/sh /backup/backup-now.sh
# или кнопка в админке: она создаёт файл /backups/.requests/run, который проверяется каждые 30 секунд.
set -eu

HOUR="${BACKUP_HOUR:-0}"
echo "[backup] сервис бэкапов запущен, ежедневный бэкап в ${HOUR}:00 UTC, хранение ${BACKUP_RETENTION_DAYS:-14} дн."

last_day=""
# Папка запросов от админки (API работает не от root, поэтому папка открыта на запись)
mkdir -p /backups/.requests && chmod 777 /backups/.requests
run_backup() {
    if /bin/sh /backup/backup-now.sh; then
        echo "ok $(date -u +%FT%TZ)" > /backups/.last_result
        return 0
    fi
    echo "error $(date -u +%FT%TZ)" > /backups/.last_result
    return 1
}
fail_at=0
while true; do
    if [ -f /backups/.requests/run ]; then
        rm -f /backups/.requests/run
        echo "[backup] бэкап по запросу из админки"
        run_backup || echo "[backup] ОШИБКА бэкапа по запросу"
    fi
    now_hour=$(date -u +%H | sed 's/^0//')
    [ -z "$now_hour" ] && now_hour=0
    today=$(date -u +%F)
    now_s=$(date -u +%s)
    if [ "$now_hour" -eq "$HOUR" ] && [ "$today" != "$last_day" ] && [ $((now_s - fail_at)) -ge 600 ]; then
        if run_backup; then
            last_day="$today"
        else
            fail_at=$now_s
            echo "[backup] ОШИБКА бэкапа, повтор через 10 минут"
        fi
    fi
    sleep 30
done

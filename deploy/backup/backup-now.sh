#!/bin/sh
# Сделать бэкап прямо сейчас (база + контент) и удалить старые.
set -eu

STAMP=$(date -u +%Y-%m-%d_%H%M)
DEST="/backups/${STAMP}"
TMP="/backups/.tmp_${STAMP}"
RETENTION="${BACKUP_RETENTION_DAYS:-14}"

mkdir -p "$TMP"
echo "[backup] дамп базы..."
pg_dump --format=custom --no-owner --file="$TMP/db.dump"
echo "[backup] архив контента..."
tar -czf "$TMP/content.tar.gz" -C /data/content-store .
(cd "$TMP" && sha256sum db.dump content.tar.gz > SHA256SUMS)
mv "$TMP" "$DEST"
echo "[backup] готово: $DEST ($(du -sh "$DEST" | cut -f1))"

# Удаление бэкапов старше RETENTION дней
find /backups -mindepth 1 -maxdepth 1 -type d -name '20*' -mtime +"$RETENTION" -print -exec rm -r -- {} \; || true

# Место для будущей копии во внешнее хранилище (Яндекс Диск и т.п.), см. docs/backups.md
if [ -x /backup/remote-upload.sh ]; then
    /backup/remote-upload.sh "$DEST" || echo "[backup] внешняя копия не удалась"
fi

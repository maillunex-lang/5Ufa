#!/usr/bin/env sh
# Одноразовая подготовка чистого VPS (Debian/Ubuntu): Docker + запуск. Запускать от root.
set -eu
command -v docker >/dev/null 2>&1 || curl -fsSL https://get.docker.com | sh
"$(dirname "$0")/redeploy.sh"
echo "--- Пароль владельца админки (первый запуск) ---"
docker compose exec -T server cat /data/ADMIN_INITIAL_PASSWORD.txt 2>/dev/null || echo "(уже создан ранее или задан в .env)"

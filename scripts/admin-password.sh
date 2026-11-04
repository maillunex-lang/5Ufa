#!/usr/bin/env bash
# Показать первичный логин/пароль админки (создаётся при первом запуске). Запускать на VPS в папке проекта.
cd "$(dirname "$0")/.."
docker compose --env-file .5ufa.env exec -T server cat /data/ADMIN_INITIAL_PASSWORD.txt

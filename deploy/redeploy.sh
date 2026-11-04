#!/usr/bin/env sh
# Идемпотентное обновление тестового сервера. Вызывайте после каждой выгрузки из GitHub.
# Не требует аргументов и ручных шагов; данные игроков лежат в docker volume и не затрагиваются.
set -eu
cd "$(dirname "$0")/.."
docker compose up -d --build --remove-orphans
for i in 1 2 3 4 5 6 7 8 9 10; do
  if docker compose exec -T server wget -qO- http://127.0.0.1:8080/health >/dev/null 2>&1; then echo "OK: сервер отвечает"; exit 0; fi
  sleep 2
done
echo "ОШИБКА: сервер не ответил на /health" >&2; docker compose logs --tail=50 server >&2; exit 1

#!/usr/bin/env sh
# Одноразовая установка на VPS с другими проектами. Ничего чужого не останавливает и не удаляет.
# Что делает: ставит Docker только если его нет; выбирает свободный порт (слушает только 127.0.0.1);
# запускает проект 5ufa; создаёт nginx-сниппет для /games (сам nginx не правит).
set -eu
cd "$(dirname "$0")/.."
command -v docker >/dev/null 2>&1 || curl -fsSL https://get.docker.com | sh
if [ ! -f .env ] || ! grep -q '^PORT=' .env; then
  port=18080
  while ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":$port\$"; do port=$((port+1)); done
  echo "PORT=$port" >> .env
fi
. ./.env
echo "Выбран свободный порт: $PORT (только 127.0.0.1)"
./deploy/redeploy.sh
SNIP=deploy/nginx-games.conf
cat > "$SNIP" <<CONF
location /games/ {
    proxy_pass http://127.0.0.1:$PORT/;
    proxy_set_header Host \$host;
    proxy_set_header X-Forwarded-For \$remote_addr;
    proxy_set_header X-Forwarded-Proto \$scheme;
    client_max_body_size 8m;
}
CONF
echo
echo "=== Пароль владельца админки ==="
docker compose exec -T server cat /data/ADMIN_INITIAL_PASSWORD.txt 2>/dev/null || echo "(уже создан ранее или задан в .env)"
echo
echo "=== Последний ручной шаг: подключить nginx ==="
echo "В server-блоке tts-ufa.ru (listen 443) добавьте строку:"
echo "    include $(pwd)/$SNIP;"
echo "затем: nginx -t && systemctl reload nginx"
echo "Проверка: https://tts-ufa.ru/games/health  и  https://tts-ufa.ru/games/admin/"

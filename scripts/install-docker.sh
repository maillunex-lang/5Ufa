#!/usr/bin/env bash
# Установка Docker Engine + Docker Compose из официального репозитория Docker (Ubuntu).
# Если Docker уже установлен — ничего не ломает, просто сообщает версию.
# Запуск: bash scripts/install-docker.sh
set -euo pipefail

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    echo "Docker уже установлен:"
    docker --version
    docker compose version
    exit 0
fi

echo ">>> Устанавливаю зависимости"
sudo apt-get update
sudo apt-get install -y ca-certificates curl git

echo ">>> Добавляю официальный репозиторий Docker"
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

echo ">>> Устанавливаю Docker"
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo ">>> Разрешаю пользователю $USER запускать docker без sudo"
sudo usermod -aG docker "$USER"

echo
docker --version
docker compose version
echo
echo "ГОТОВО. Выйдите из SSH (exit) и зайдите снова, чтобы права на docker вступили в силу."

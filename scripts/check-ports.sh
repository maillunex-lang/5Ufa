#!/usr/bin/env bash
# Показывает, какие порты на VPS уже заняты, и предлагает свободный порт для игры.
# Ничего не меняет — только смотрит.
# Запуск: bash scripts/check-ports.sh
set -uo pipefail

echo "=== Занятые TCP-порты (кто слушает) ==="
if command -v ss >/dev/null 2>&1; then
    sudo ss -tlnp 2>/dev/null | awk 'NR==1 || /LISTEN/' || ss -tln
else
    echo "Команда ss не найдена (установите: sudo apt install iproute2)"
fi

busy() { ss -tln 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$1\$"; }

echo
echo "=== Проверка стандартных портов ==="
for p in 80 443 5000; do
    if busy "$p"; then echo "  $p — ЗАНЯТ"; else echo "  $p — свободен"; fi
done

echo
echo "=== Кандидаты для игры (HTTP_PORT в .env) ==="
SUGGEST=""
for p in 8085 8080 8081 8088 8090 8180 8280 18080 28080; do
    if busy "$p"; then
        echo "  $p — занят"
    else
        echo "  $p — свободен"
        [ -z "$SUGGEST" ] && SUGGEST=$p
    fi
done

echo
if [ -n "$SUGGEST" ]; then
    echo "Рекомендую: HTTP_PORT=$SUGGEST"
else
    echo "Все кандидаты заняты — выберите любой свободный порт 1024-65535."
fi
if busy 80 || busy 443; then
    echo "ВНИМАНИЕ: порт 80/443 уже занят другим сервисом (вероятно, вашим Nginx/Apache)."
    echo "Для HTTPS с доменом подключим игру через него — см. docs/https.md"
fi

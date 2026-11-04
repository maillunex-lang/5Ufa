#!/usr/bin/env bash
# Сборка веб-версии админки (Godot, пресет «Admin Web», без потоков — работает на любом хостинге).
# Результат: client/build/admin-web.zip (index.html, .js, .wasm, .pck). Сервер раздаёт её по адресу /admin/.
#   GODOT — путь к Godot 4.7.x (по умолчанию godot); VERSION_NAME — версия (для заголовка)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/client"
GODOT="${GODOT:-godot}"
OUT_DIR="$CLIENT/build/admin-web"
rm -rf "$OUT_DIR" "$CLIENT/build/admin-web.zip"
mkdir -p "$OUT_DIR"
"$GODOT" --headless --path "$CLIENT" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$CLIENT" --export-release "Admin Web" "$OUT_DIR/index.html" 2>&1 | grep -vE "^\s*$" | tail -20
for f in index.html index.js index.wasm index.pck; do
    [ -f "$OUT_DIR/$f" ] || { echo "ОШИБКА: нет $f — веб-экспорт не удался" >&2; exit 1; }
done
(cd "$OUT_DIR" && zip -qr ../admin-web.zip .)
echo ">>> Веб-админка: $CLIENT/build/admin-web.zip ($(du -h "$CLIENT/build/admin-web.zip" | cut -f1))"

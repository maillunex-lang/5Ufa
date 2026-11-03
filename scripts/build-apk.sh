#!/usr/bin/env bash
# Сборка APK игры (Godot headless export). Используется в GitHub Actions (.github/workflows/apk.yml).
#
# Переменные окружения:
#   GODOT            — путь к Godot 4.7.x (по умолчанию: godot)
#   ANDROID_SDK      — путь к Android SDK (нужен apksigner из build-tools)
#   JAVA_HOME        — путь к JDK 17+
#   VERSION_NAME     — например 0.1.42 (по умолчанию из client/project.godot)
#   VERSION_CODE     — целое, растёт с каждой сборкой (по умолчанию 1)
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD — ключ подписи
#   APK_MAX_MB       — ограничение размера (95)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/client"
GODOT="${GODOT:-godot}"
OUT="$CLIENT/build/ufa.apk"
APK_MAX_MB="${APK_MAX_MB:-95}"
VERSION_CODE="${VERSION_CODE:-1}"
VERSION_NAME="${VERSION_NAME:-$(grep -oP '^config/version="\K[^"]+' "$CLIENT/project.godot")}"

: "${ANDROID_SDK:?Укажите ANDROID_SDK — путь к Android SDK}"
: "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?Нет ключа подписи (GODOT_ANDROID_KEYSTORE_RELEASE_PATH)}"

echo ">>> Версия $VERSION_NAME (код $VERSION_CODE)"
sed -i "s/^config\/version=.*/config\/version=\"$VERSION_NAME\"/" "$CLIENT/project.godot"
sed -i "s/^version\/code=.*/version\/code=$VERSION_CODE/; s/^version\/name=.*/version\/name=\"$VERSION_NAME\"/" "$CLIENT/export_presets.cfg"
# Номер сборки нужен игре, чтобы спрашивать у сервера про обновления
sed -i "s/^version_code=.*/version_code=$VERSION_CODE/" "$CLIENT/project.godot"

echo ">>> Импорт ресурсов проекта"
"$GODOT" --headless --path "$CLIENT" --import >/dev/null 2>&1 || true

# Пути к Android SDK и Java в настройках редактора Godot
SETTINGS="$(ls "$HOME"/.config/godot/editor_settings-4*.tres 2>/dev/null | sort -V | tail -1)"
if [ -z "$SETTINGS" ]; then
    echo "Не найден файл настроек редактора Godot" >&2
    exit 1
fi
set_setting() {
    local key="$1" value="$2"
    if grep -q "^$key = " "$SETTINGS"; then
        sed -i "s#^$key = .*#$key = \"$value\"#" "$SETTINGS"
    else
        echo "$key = \"$value\"" >> "$SETTINGS"
    fi
}
set_setting "export/android/android_sdk_path" "$ANDROID_SDK"
[ -n "${JAVA_HOME:-}" ] && set_setting "export/android/java_sdk_path" "$JAVA_HOME"

echo ">>> Экспорт APK"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
"$GODOT" --headless --path "$CLIENT" --export-release "Android" "$OUT" 2>&1 | tee /tmp/godot-export.log | grep -vE "^\s*$" | tail -40
if [ ! -f "$OUT" ]; then
    echo "ОШИБКА: APK не создан, см. лог выше" >&2
    exit 1
fi

SIZE=$(stat -c %s "$OUT")
SIZE_MB=$(awk "BEGIN{printf \"%.1f\", $SIZE/1048576}")
echo ">>> APK: $OUT ($SIZE_MB МБ)"
if [ "$SIZE" -gt $((APK_MAX_MB * 1048576)) ]; then
    echo "ОШИБКА: APK больше $APK_MAX_MB МБ" >&2
    exit 1
fi

# Проверка подписи
APKSIGNER="$(ls "$ANDROID_SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
if [ -n "$APKSIGNER" ]; then
    "$APKSIGNER" verify --print-certs "$OUT" | grep -E "Signer #1 certificate (DN|SHA-256)" || true
fi
echo "apk_path=$OUT" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "apk_size_mb=$SIZE_MB" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "version_name=$VERSION_NAME" >> "${GITHUB_OUTPUT:-/dev/null}"

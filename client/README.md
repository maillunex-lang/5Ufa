# /client — игра (Godot 4.7, Android)

APK — только код-загрузчик (~25 МБ). Весь контент скачивается с сервера `https://tts-ufa.ru/games/server`.

| Файл | Назначение |
|---|---|
| `scripts/config.gd` | Адрес сервера, версия, флаги запуска |
| `scripts/api.gd` | Запросы к серверу, токены, вход гостем / по почте |
| `scripts/content.gd` | Манифест, загрузка пакетов, SHA-256, `user://content` |
| `scripts/download_worker.gd` | Загрузка файла с докачкой (HTTP Range) |
| `scripts/ui.gd` | Стиль интерфейса загрузчика |
| `scenes/boot.*` | Экран загрузки |
| `scenes/main.*` | Главный экран + аккаунт (этап 2) |
| `export_presets.cfg` | Экспорт Android: `lunex.ufa`, arm64, портрет |

## Запуск на компьютере

1. Скачайте Godot 4.7.2: https://godotengine.org/download
2. Godot → **Импорт** → выберите `client/project.godot` → **F5**.

Против своего сервера (например, локального):
```bash
godot --path client -- --server=http://127.0.0.1:8085
```
Автопроверка без окна (как в CI):
```bash
godot --headless --path client -- --server=http://127.0.0.1:8085 --autotest
```

## Сборка APK
Автоматически в GitHub Actions (`.github/workflows/apk.yml`), ключ подписи — `docs/apk-signing.md`.

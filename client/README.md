# Клиент (Godot 4.4, Android, вертикальная ориентация)

Статус: **C-1** — загрузчик, гостевой вход, `/api/config`, `/api/me`, пробный бой с выводом результата текстом. Анимация боя, город и остальные экраны — C-2…C-4 (`docs/ROADMAP.md`).

- Адрес сервера: константа `DEFAULT_SERVER_URL` в `api.gd` (для тестов переопределяется переменной `FIVEUFA_SERVER`). Токен хранится в `user://session.cfg`.
- Клиент ничего не считает: бой и награды приходят с сервера (`docs/api.md`).
- APK собирает GitHub Actions (`.github/workflows/client.yml`); тестовый APK появляется в Releases как prerelease. Подпись тестовая, см. `deploy/test-signing/README.md`.
- Локально: Godot 4.4.1, открыть папку `client/`.

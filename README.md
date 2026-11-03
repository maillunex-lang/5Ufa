# [НАЗВАНИЕ] — idle/AFK RPG по мотивам башкирских легенд

Онлайн-игра для Android (Godot 4) + отдельное приложение-админка + сервер (FastAPI).
Тёмное фэнтези в ярком мультяшном стиле, кампания по карте Республики Башкортостан.

Сервер: `https://tts-ufa.ru/games/server` · ID приложения: `lunex.ufa` · язык: русский.

## Структура репозитория

| Папка | Что внутри |
|---|---|
| `/server` | Сервер: Python 3.12 + FastAPI, PostgreSQL, Redis, миграции Alembic |
| `/client` | Игра (Godot 4.7, APK-загрузчик) |
| `/admin` | Админка (Godot 4, отдельный APK) — этап 6 |
| `/shared` | JSON Schema всех типов контента — единый источник правды |
| `/content` | Базовый контент (заглушки), из него собирается первый релиз |
| `/patch-prompts` | Справочник промптов для ИИ по разделам контента |
| `/docs` | Документация |
| `/deploy` | Конфиги Nginx и бэкапов для Docker |
| `/scripts` | Скрипты для VPS: установка, деплой, проверка портов, восстановление |

## С чего начать

1. **Первичная настройка VPS и GitHub** — [docs/setup-guide.md](docs/setup-guide.md) (пошагово, с командами).
2. План разработки по этапам — [docs/roadmap.md](docs/roadmap.md).
3. Как устроена система — [docs/architecture.md](docs/architecture.md).
4. Загрузка контента (манифест) — [docs/content-delivery.md](docs/content-delivery.md).
5. Формат ZIP-патчей — [docs/patch-format.md](docs/patch-format.md).
6. Бэкапы и восстановление — [docs/backups.md](docs/backups.md).
7. HTTPS и подключение к домену — [docs/https.md](docs/https.md).
8. Принятые решения — [docs/decisions.md](docs/decisions.md).
9. Аккаунты игроков — [docs/accounts.md](docs/accounts.md).
10. Ключ подписи и сборка APK — [docs/apk-signing.md](docs/apk-signing.md).
11. Обновление приложения из игры — [docs/app-updates.md](docs/app-updates.md).
12. Бой: правила, формулы, журнал — [docs/battle.md](docs/battle.md).
13. Формат скелетной анимации — [docs/skeleton-format.md](docs/skeleton-format.md).
14. Прогрессия героев и призыв — [docs/progression.md](docs/progression.md).
15. Главный экран «Город» — [docs/hub.md](docs/hub.md).
16. Снаряжение и уникальный предмет — [docs/equipment.md](docs/equipment.md).

## Правило безопасности

Пароли и ключи хранятся **только** в GitHub Secrets и в файле `.env` на сервере.
Файл `.env` никогда не попадает в git (он в `.gitignore`).

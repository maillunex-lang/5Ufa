# Аккаунты игроков

1. **Первый запуск** — вход гостем автоматически. На устройстве сохраняется случайный `device_id`
   и токен обновления (`user://auth.cfg`). Игрок получает номер (`#1001`) и имя `Путник-1001`.
2. **Привязка почты** (главный экран → «Привязать почту») — почта + пароль (от 8 символов, буквы и цифры).
3. **Другой телефон** — «Войти в другой аккаунт» → почта и пароль → тот же аккаунт и прогресс.

## Безопасность
- Пароли: scrypt со случайной солью. Токены обновления в базе — только как SHA-256.
- Токен доступа живёт 1 час, токен обновления — 180 дней и меняется при каждом обновлении.
- Лимиты: 5 попыток входа на почту и 20 на IP за 15 минут; 30 гостевых входов на IP за 15 минут.
- Сервер — источник истины: клиент ничего не меняет сам.

## API
| Метод | Путь | Что делает |
|---|---|---|
| POST | `/api/v1/auth/guest` | `{device_id}` → токены и игрок (тот же гость для того же устройства) |
| POST | `/api/v1/auth/login` | `{device_id, email, password}` → токены |
| POST | `/api/v1/auth/refresh` | `{refresh_token}` → новая пара токенов |
| POST | `/api/v1/auth/link-email` | (с токеном) `{email, password}` — привязать почту к гостю |
| POST | `/api/v1/auth/logout` | `{refresh_token}` — завершить сессию |
| GET | `/api/v1/me` | (с токеном) профиль |
| GET | `/api/v1/content/manifest` | тестовые аккаунты получают канал `test`, остальные — `live` |

Ошибки возвращаются как `{"detail": "текст на русском"}`.

## Команды на VPS
```bash
cd ~/ufagame
docker compose exec api python -m app.cli player list                 # последние игроки
docker compose exec api python -m app.cli player set-test 1001        # сделать тестовым (канал test)
docker compose exec api python -m app.cli player set-test 1001 --off  # снять отметку
docker compose exec api python -m app.cli player ban 1001 --days 7 --reason "причина"
docker compose exec api python -m app.cli player ban 1001 --days 0    # разблокировать
```
Вместо номера можно указать почту. На этапе 6 всё это — в админке.

# Первичная настройка: VPS + GitHub + первый запуск

Время: ~30–40 минут. Делается один раз. Каждый шаг: **команда → что она делает → что должно получиться**.

Обозначения, которые нужно заменить своими значениями:

| В инструкции | Что подставить | Пример |
|---|---|---|
| `IP_VPS` | IP-адрес вашего VPS | `185.10.20.30` |
| `ПОЛЬЗОВАТЕЛЬ` | имя пользователя, под которым вы входите на VPS | `ubuntu` |

> Команды копируйте целиком. Строки, начинающиеся с `#`, — комментарии, их вводить не нужно.

---

## Шаг 1. Ветка `main` на GitHub

Автодеплой срабатывает на push в ветку `main`.

1. Откройте https://github.com/maillunex-lang/5Ufa
2. Убедитесь, что рядом с названием написано **Private**. Если **Public** —
   Settings → General → внизу «Danger Zone» → **Change visibility** → Private.
3. Если ветки `main` ещё нет: вкладка **Pull requests** → **New pull request**,
   слева (base) выберите `main` — если GitHub предложит создать её, создайте;
   иначе: **Code** → кнопка со списком веток → введите `main` → **Create branch main from ...**
   (из ветки, где лежит код этапа). Затем Settings → General → **Default branch** → `main`.

**Проверка:** на странице репозитория в списке веток есть `main`, в ней есть папки `server`, `docs`, `scripts`.

---

## Шаг 2. Подготовка VPS

### 2.1. Войти на VPS

На своём компьютере (Windows: программа «Терминал» или PowerShell; Mac/Linux: «Терминал»):

```bash
ssh ПОЛЬЗОВАТЕЛЬ@IP_VPS
```
Что делает: подключается к серверу. При первом входе спросит `Are you sure you want to continue connecting` — введите `yes`.
Результат: приглашение вида `ПОЛЬЗОВАТЕЛЬ@имя-сервера:~$`.

Все дальнейшие команды шага 2 выполняются **на VPS**.

### 2.2. Посмотреть занятые порты (ничего не меняет)

```bash
sudo ss -tlnp
```
Что делает: показывает все программы, которые слушают сетевые порты.
Результат: таблица; в колонке `Local Address:Port` видно занятые порты (например, `0.0.0.0:5000` — ваш существующий сервис).
Запомните, заняты ли порты **80** и **443** — это понадобится для HTTPS.

### 2.3. Ключ, чтобы VPS мог скачивать код из приватного репозитория

```bash
sudo apt-get update && sudo apt-get install -y git curl openssl
```
Что делает: устанавливает git, curl и openssl (если уже есть — ничего не сломает).

```bash
ssh-keygen -t ed25519 -f ~/.ssh/github_deploy -N "" -C "vps-deploy-key"
```
Что делает: создаёт пару ключей без пароля: `~/.ssh/github_deploy` (секретный, остаётся на VPS) и `~/.ssh/github_deploy.pub` (публичный).

```bash
cat >> ~/.ssh/config <<'EOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_deploy
    IdentitiesOnly yes
EOF
chmod 600 ~/.ssh/config
```
Что делает: говорит SSH использовать этот ключ при обращении к GitHub.

```bash
cat ~/.ssh/github_deploy.pub
```
Что делает: показывает публичный ключ — строку, начинающуюся с `ssh-ed25519`. Скопируйте её целиком.

На GitHub: репозиторий → **Settings** → **Deploy keys** → **Add deploy key**:
- Title: `VPS`
- Key: вставьте скопированную строку
- галочку **Allow write access НЕ ставьте** (VPS нужно только читать)
- **Add key**

Проверка (на VPS):
```bash
ssh -T git@github.com
```
При первом запуске введите `yes`. Ожидается: `Hi maillunex-lang/5Ufa! You've successfully authenticated, but GitHub does not provide shell access.`

### 2.4. Скачать проект

```bash
git clone -b main git@github.com:maillunex-lang/5Ufa.git ~/ufagame
cd ~/ufagame
ls
```
Что делает: скачивает код в папку `~/ufagame` и переходит в неё.
Результат: список `README.md  client  content  docker-compose.yml  docs  scripts  server  shared ...`

### 2.5. Установить Docker

```bash
bash scripts/install-docker.sh
```
Что делает: ставит Docker и Docker Compose из официального репозитория Docker. Если Docker уже стоит — только покажет версию.
Результат: в конце `Docker version 2x.x.x` и `Docker Compose version v2.x.x`.

**Обязательно** после установки выйдите и зайдите снова (чтобы заработали права на docker):
```bash
exit
```
```bash
ssh ПОЛЬЗОВАТЕЛЬ@IP_VPS
cd ~/ufagame
docker ps
```
Результат: таблица (возможно, с вашими существующими контейнерами), **без** ошибки `permission denied`.

### 2.6. Убедиться, что порт 8085 свободен

```bash
bash scripts/check-ports.sh
```
Что делает: показывает занятые порты. Ничего не меняет.
Результат: в списке кандидатов строка `8085 — свободен`.
Там же видно, кто занимает 80/443 (ваш основной веб-сервер для tts-ufa.ru).

### 2.7. Создать файл настроек `.env` с паролями

```bash
cp .env.example .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" .env
sed -i "s/^SECRET_KEY=.*/SECRET_KEY=$(openssl rand -hex 32)/" .env
chmod 600 .env
```
Что делает: копирует пример настроек, генерирует случайные надёжные пароль базы и секретный ключ,
записывает их в `.env` и закрывает файл от других пользователей.
Порт `8085`, домен `tts-ufa.ru`, путь `/games/server` и время бэкапа (05:00 по Уфе) уже прописаны в примере.

Проверка:
```bash
grep -E "HTTP_PORT|HTTP_BIND|DOMAIN|PUBLIC_PATH_PREFIX|BACKUP_HOUR|POSTGRES_PASSWORD" .env
```
Результат:
```
HTTP_PORT=8085
HTTP_BIND=127.0.0.1
DOMAIN=tts-ufa.ru
PUBLIC_PATH_PREFIX=/games/server
POSTGRES_PASSWORD=<длинная строка из букв и цифр, не CHANGE_ME>
BACKUP_HOUR=0
```

> Пароли знать не нужно — они используются только внутри сервера. Не публикуйте содержимое `.env`.
> Файрвол (ufw) трогать **не нужно**: порт 8085 слушает только `127.0.0.1` и снаружи недоступен.

### 2.8. Первый запуск

```bash
bash scripts/deploy.sh main
```
Что делает: собирает образы, запускает базу, Redis, API, Nginx игры и бэкапы, применяет миграции,
загружает базовый контент и проверяет `/health`. Первый раз занимает 3–7 минут (скачиваются образы).
Результат — последние строки:
```
[deploy ..] health OK: {"status":"ok",...}
[deploy ..] ДЕПЛОЙ УСПЕШЕН: xxxxxxxx
```

Проверка:
```bash
docker compose ps
```
Результат: 5 сервисов (`api`, `nginx`, `postgres`, `redis`, `backup`) в состоянии `Up`,
у `api`/`postgres`/`redis` — `(healthy)`. Порт есть только у `nginx`: `127.0.0.1:8085->80/tcp`.

```bash
curl http://127.0.0.1:8085/health
```
Результат: `{"status":"ok","version":"...","content_release":1,"database":"ok","redis":"ok"}`

### 2.9. Подключить игру к tts-ufa.ru/games/server

Сначала — пробный прогон, он **ничего не меняет**, только показывает, что будет сделано:
```bash
sudo python3 scripts/connect_host_nginx.py --dry-run
```
Ожидаемый результат:
```
Домен: tts-ufa.ru   путь: /games/server/   ->   127.0.0.1:8085
Порты 80/443 занимает: nginx
  подключить в: /etc/nginx/sites-available/<файл вашего сайта> (строка N, блок SSL)
--- Будет создан файл /etc/nginx/snippets/ufagame-server.conf ---
...
(--dry-run: ничего не изменено)
```
Если вместо этого скрипт пишет, что веб-сервер — не Nginx, что он в Docker, или что блок для
домена не найден, — **остановитесь** и пришлите мне его вывод.

Если всё как в примере — выполняем по-настоящему:
```bash
sudo python3 scripts/connect_host_nginx.py
```
Что делает: создаёт файл с правилами для `/games/server/`, добавляет в блок вашего сайта одну строку
`include snippets/ufagame-server.conf;`, делает резервную копию в `/etc/nginx/ufagame-backups/`,
проверяет конфигурацию (`nginx -t`) и мягко перезагружает Nginx (без обрыва соединений).
Если проверка не прошла — сам возвращает всё как было.
Результат:
```
nginx -t: OK
Nginx перезагружен.
Проверка:  curl https://tts-ufa.ru/games/server/health
```

Проверка:
```bash
curl https://tts-ufa.ru/games/server/health
```
Результат: `{"status":"ok",...,"database":"ok","redis":"ok"}`.
Откройте этот же адрес в браузере телефона — тот же текст.

```bash
curl -s https://tts-ufa.ru/games/server/api/v1/content/manifest | head -c 300
```
Результат: начало JSON с `"release":1` и `"base_url":"/games/server/content/files/"`.

**Обязательно** проверьте, что ваш сайт tts-ufa.ru и сервис на порту 5000 работают как раньше.

Если что-то не так — отключение одной командой (возвращает конфиг вашего Nginx в исходное состояние):
```bash
sudo python3 scripts/connect_host_nginx.py --remove
```

---

## Шаг 3. Ключ для автодеплоя из GitHub Actions

GitHub Actions будет заходить на VPS по SSH и запускать `scripts/deploy.sh`.

На VPS:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/gh_actions -N "" -C "github-actions"
cat ~/.ssh/gh_actions.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```
Что делает: создаёт отдельный ключ для GitHub и разрешает вход по нему на VPS под вашим пользователем.

Показать секретную часть (понадобится для GitHub):
```bash
cat ~/.ssh/gh_actions
```
Результат: текст от `-----BEGIN OPENSSH PRIVATE KEY-----` до `-----END OPENSSH PRIVATE KEY-----`.

Отпечаток сервера (чтобы GitHub был уверен, что подключается именно к вашему VPS; замените `IP_VPS` и при необходимости порт SSH `22`):
```bash
ssh-keyscan -p 22 IP_VPS 2>/dev/null
```
Результат: 2–3 строки, начинающиеся с `IP_VPS ssh-...`.

Узнать полный путь к проекту:
```bash
cd ~/ufagame && pwd
```
Результат, например: `/home/ubuntu/ufagame`.

### 3.1. Добавить секреты в GitHub

Репозиторий → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.
Добавьте 6 секретов (Name — точно как в таблице):

| Name | Value |
|---|---|
| `VPS_HOST` | `IP_VPS` |
| `VPS_PORT` | `22` (или ваш SSH-порт) |
| `VPS_USER` | `ПОЛЬЗОВАТЕЛЬ` |
| `VPS_SSH_KEY` | весь вывод `cat ~/.ssh/gh_actions`, включая строки BEGIN/END |
| `VPS_KNOWN_HOSTS` | весь вывод `ssh-keyscan ...` |
| `VPS_APP_DIR` | вывод `pwd`, например `/home/ubuntu/ufagame` |

**Проверка:** на странице Secrets видны все 6 имён (значения GitHub не показывает — это нормально).

Необязательный секрет `GEMINI_API_KEY` — ключ из Google AI Studio (нарезка героев с ИИ в админке).
При каждом деплое он записывается в `.env` на VPS через вход SSH (в логи и командную строку не попадает),
после деплоя в логе шага «Деплой на VPS» есть строка `Gemini: ...` — есть ли доступ к Gemini с сервера.

---

## Шаг 4. Проверка автодеплоя

1. На GitHub откройте файл `README.md` в ветке `main` → значок карандаша → добавьте пустую строку → **Commit changes**.
2. Вкладка **Actions** → появится запуск **Deploy**. Внутри две задачи: `checks` (тесты) и `deploy`.
3. Через 2–5 минут обе должны быть с зелёной галочкой.
4. Проверка на VPS:
   ```bash
   curl https://tts-ufa.ru/games/server/health
   ```
   Поле `version` должно совпадать с хэшем последнего коммита (виден на GitHub рядом с коммитом).

Если `deploy` красный — откройте его, разверните шаг «Деплой на VPS» и посмотрите последние строки.
Сервер при ошибке **сам откатывается** на прошлую версию (в логе будет `ОТКАТ ... откат выполнен`).

> Приватный репозиторий: GitHub даёт бесплатно 2000 минут Actions в месяц — одного деплоя хватает ~3–5 минут.

---

## Частые проблемы

| Симптом | Причина и решение |
|---|---|
| `permission denied ... docker.sock` | Не перезашли после установки Docker: `exit`, снова `ssh ...` |
| `Bind for 127.0.0.1:8085 failed: port is already allocated` | Порт занят: `bash scripts/check-ports.sh`, поменяйте `HTTP_PORT` в `.env`, снова `bash scripts/deploy.sh main` и `sudo python3 scripts/connect_host_nginx.py` |
| `ERROR: нет файла .env` | Не выполнен шаг 2.7 |
| В Actions: `Permission denied (publickey)` | Проверьте `VPS_USER`, `VPS_SSH_KEY` (весь текст с BEGIN/END) и что выполнена команда `cat ~/.ssh/gh_actions.pub >> ~/.ssh/authorized_keys` |
| В Actions: `Host key verification failed` | Пересоздайте секрет `VPS_KNOWN_HOSTS` командой из шага 3 (с правильным IP и портом) |
| `curl http://127.0.0.1:8085/health` работает, а `https://tts-ufa.ru/games/server/health` — нет | Не выполнен шаг 2.9, или он завершился ошибкой — пришлите его вывод |
| `https://tts-ufa.ru/games/server/health` отвечает `502 Bad Gateway` | Игра не запущена: `docker compose ps`, `docker compose logs --tail=100 api` |
| Нужно посмотреть логи | `docker compose logs --tail=100 api` (или `nginx`, `postgres`) |

## Полезные команды (на VPS, в папке `~/ufagame`)

```bash
docker compose ps                                   # состояние сервисов
docker compose logs --tail=100 api                  # последние логи API
docker compose restart api                          # перезапустить API
docker compose exec api python -m app.cli content list     # релизы контента
docker compose exec backup /bin/sh /backup/backup-now.sh   # бэкап прямо сейчас
bash scripts/restore.sh                             # список бэкапов / восстановление
```

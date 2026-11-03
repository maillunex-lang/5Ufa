# HTTPS и подключение к домену

**Решение:** сервер игры работает по адресу `https://tts-ufa.ru/games/server`.

Домен tts-ufa.ru уже обслуживает основной веб-сервер VPS (порты 80/443). Игра его не заменяет,
а встаёт «за ним»:

```
Телефон ──HTTPS──> tts-ufa.ru:443 (ваш Nginx, ваш сертификат)
                      ├─ /games/server/...  ──> 127.0.0.1:8085 (Nginx игры в Docker)  ← новое
                      └─ всё остальное      ──> как сейчас (ваш сайт / сервис на 5000)
```

- Ваш Nginx срезает префикс `/games/server` и передаёт запрос игре.
- Игра знает свой префикс (`PUBLIC_PATH_PREFIX=/games/server` в `.env`) и ставит его в ссылки
  манифеста: `base_url = /games/server/content/files/`.
- Порт 8085 открыт только на `127.0.0.1` — из интернета напрямую недоступен, в файрволе открывать не нужно.
- Правило `location ^~ /games/server/` имеет приоритет над остальными правилами вашего сайта,
  включая правила по расширениям файлов, поэтому ваши настройки ему не мешают и наоборот.

## Подключение

Выполняется скриптом `scripts/connect_host_nginx.py` — см. **шаг 2.10** в [setup-guide.md](setup-guide.md).

Скрипт меняет у вашего Nginx ровно одно: добавляет строку
```
include snippets/ufagame-server.conf;  # ufagame: сервер игры
```
в блок `server { ... server_name tts-ufa.ru ... listen 443 ssl ... }` и создаёт файл
`/etc/nginx/snippets/ufagame-server.conf`. Перед изменением — резервная копия в
`/etc/nginx/ufagame-backups/`, после — `nginx -t`; при ошибке всё возвращается обратно.

Отключить: `sudo python3 scripts/connect_host_nginx.py --remove`

## Если у домена ещё нет HTTPS

Скрипт предупредит («нет HTTPS-блока»). Тогда после него выполните:
```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d tts-ufa.ru
```
certbot сам выпустит бесплатный сертификат Let's Encrypt, настроит его и будет продлевать.
Затем запустите скрипт подключения ещё раз — он перенесёт игру в HTTPS-блок.

## Если основной веб-сервер — не Nginx (Apache, Caddy, Nginx в Docker)

Скрипт это определит и ничего не будет менять. Пришлите вывод `sudo ss -tlnp` и `docker ps` —
подготовлю инструкцию под ваш вариант.

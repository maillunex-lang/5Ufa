# Ключ подписи APK

Android устанавливает **обновление** приложения только если оно подписано **тем же ключом**,
что и установленная версия. RuStore и Google Play тоже требуют один и тот же ключ.

> ⚠️ **Потерять ключ = навсегда потерять возможность обновлять игру** у игроков и в магазине.
> Сделайте 2 копии в разных местах (например, флешка + менеджер паролей / облако с шифрованием).

Пока секретов нет, GitHub собирает APK с **временным** ключом. Такой APK можно поставить и
проверить, но следующая сборка не установится «поверх» — придётся удалять игру.

---

## Шаг 1. Создать ключ (на VPS, один раз)

```bash
mkdir -p ~/ufa-keys && chmod 700 ~/ufa-keys && cd ~/ufa-keys
```
Создаёт закрытую папку для ключа.

```bash
openssl rand -hex 16 > password.txt && chmod 600 password.txt
```
Генерирует надёжный пароль ключа и сохраняет его в `password.txt`.

```bash
docker run --rm -v "$PWD":/k eclipse-temurin:17-jre keytool -genkeypair -keystore /k/release.keystore -storetype PKCS12 -alias ufa -keyalg RSA -keysize 4096 -validity 10000 -storepass "$(cat password.txt)" -keypass "$(cat password.txt)" -dname "CN=lunex, O=lunex, C=RU"
```
Что делает: временно запускает Java в Docker (на сервер ничего не устанавливается) и создаёт
файл `release.keystore` с ключом на ~27 лет. Первый раз скачает образ Java (~100 МБ).

Проверка:
```bash
ls -la ~/ufa-keys && docker run --rm -v "$PWD":/k eclipse-temurin:17-jre keytool -list -keystore /k/release.keystore -storepass "$(cat password.txt)" | grep -E "ufa|SHA-256"
```
Ожидается: файлы `release.keystore` и `password.txt`; строка `ufa, ..., PrivateKeyEntry` и отпечаток `SHA-256`.

## Шаг 2. Добавить 3 секрета в GitHub

Репозиторий → **Settings → Secrets and variables → Actions → New repository secret**.

**`ANDROID_KEY_ALIAS`** — значение:
```
ufa
```

**`ANDROID_KEYSTORE_PASSWORD`** — показать пароль:
```bash
cat ~/ufa-keys/password.txt
```
Скопируйте строку из 32 символов.

**`ANDROID_KEYSTORE_BASE64`** — показать ключ в текстовом виде:
```bash
base64 -w0 ~/ufa-keys/release.keystore; echo
```
Выведется одна длинная строка (~5000 символов, без пробелов). Скопируйте её **целиком**.
Лишние переносы строк при вставке с телефона не страшны — сборка их убирает.

Проверить, что строка скопирована полностью, можно по длине:
```bash
base64 -w0 ~/ufa-keys/release.keystore | wc -c
```

## Шаг 3. Сделать резервные копии ключа

Ключ сейчас только на VPS. Скачайте папку `~/ufa-keys` к себе. С компьютера (Windows PowerShell, Mac, Linux):
```bash
scp -r root@144.31.254.99:/root/ufa-keys .
```
Результат: на компьютере появится папка `ufa-keys` с двумя файлами. Сохраните её ещё в одно место.

## Шаг 4. Собрать APK

GitHub → **Actions** → слева **APK** → **Run workflow** → **Run workflow**.
Через ~5–10 минут (первый раз дольше — скачивается Godot) в разделе **Releases**
появится `client-v0.1.N` с файлом `ufa-0.1.N.apk`.

## Установка на телефон

1. На телефоне откройте https://github.com/maillunex-lang/5Ufa/releases (нужно войти в GitHub — репозиторий приватный).
2. В последнем релизе нажмите `ufa-0.1.N.apk` — файл скачается.
3. Откройте скачанный файл. Android попросит разрешить установку из этого источника (браузера) — разрешите.
4. Если ранее стояла сборка с **временным** ключом — сначала удалите её.

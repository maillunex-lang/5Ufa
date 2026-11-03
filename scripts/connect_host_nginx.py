#!/usr/bin/env python3
"""Подключение сервера игры к основному Nginx на VPS: https://DOMAIN/PREFIX/ -> 127.0.0.1:HTTP_PORT

Запуск (из папки проекта):
    sudo python3 scripts/connect_host_nginx.py --dry-run   # только показать, что будет сделано
    sudo python3 scripts/connect_host_nginx.py             # выполнить

Что делает:
  1. Определяет, какой веб-сервер занимает порты 80/443.
  2. Создаёт файл /etc/nginx/snippets/ufagame-server.conf (правила проксирования).
  3. Находит блок server { ... server_name DOMAIN ... } с HTTPS (listen 443)
     и добавляет в него ОДНУ строку:  include snippets/ufagame-server.conf;
  4. Делает резервную копию изменяемого файла, проверяет конфиг (nginx -t).
     Если проверка не прошла — возвращает файл как был. Ваши сайты не пострадают.
  5. Перезагружает Nginx мягко (reload — без обрыва текущих соединений).

Отключить обратно:  sudo python3 scripts/connect_host_nginx.py --remove
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
SNIPPET_NAME = "ufagame-server.conf"
MARK = "# ufagame: сервер игры"


def read_env() -> dict[str, str]:
    env_file = PROJECT / ".env"
    if not env_file.is_file():
        sys.exit("ОШИБКА: нет файла .env в папке проекта (см. docs/setup-guide.md, шаг 2.7)")
    env = {}
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def snippet_text(prefix: str, port: str) -> str:
    return f"""{MARK}. Файл создан scripts/connect_host_nginx.py — не редактируйте вручную.
# https://<домен>{prefix}/  ->  контейнеры игры на 127.0.0.1:{port}
location = {prefix} {{
    return 301 {prefix}/;
}}
location ^~ {prefix}/ {{
    proxy_pass http://127.0.0.1:{port}/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Prefix {prefix};
    # WebSocket (чат)
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $http_connection;
    proxy_read_timeout 3600s;
    # ZIP-патчи из админки и крупные файлы контента
    client_max_body_size 200m;
    proxy_max_temp_file_size 0;
}}
"""


def detect_webserver() -> str:
    """Кто слушает 443 (или 80): nginx / apache2 / caddy / docker-proxy / none / unknown."""
    try:
        out = subprocess.run(["ss", "-tlnpH"], capture_output=True, text=True, check=False).stdout
    except FileNotFoundError:
        return "unknown"
    found = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        port = parts[3].rsplit(":", 1)[-1]
        m = re.search(r'users:\(\("([^"]+)"', line)
        if port in ("80", "443"):
            found[port] = m.group(1) if m else "unknown"
    return found.get("443") or found.get("80") or "none"


def strip_comment(line: str) -> str:
    return line.split("#", 1)[0]


def find_server_blocks(lines: list[str]) -> list[dict]:
    """Найти блоки server { } верхнего уровня внутри файла (с учётом вложенности)."""
    blocks = []
    stack: list[dict | None] = []
    for i, raw in enumerate(lines):
        code = strip_comment(raw)
        for m in re.finditer(r"\bserver\s*\{|\{|\}", code):
            tok = m.group(0)
            if tok == "}":
                if stack:
                    b = stack.pop()
                    if b is not None:
                        b["end"] = i
                        blocks.append(b)
            elif tok.startswith("server"):
                stack.append({"start": i, "end": None, "depth": len(stack)})
            else:
                stack.append(None)
    for b in blocks:
        b["lines"] = range(b["start"], b["end"] + 1)
    return blocks


def analyze_block(lines: list[str], b: dict, domain: str) -> None:
    b["server_name_line"] = None
    b["ssl"] = False
    b["ports"] = []
    b["has_include"] = False
    for i in b["lines"]:
        code = strip_comment(lines[i]).strip()
        if code.startswith("server_name") and b["server_name_line"] is None:
            names = code.rstrip(";").split()[1:]
            if domain in names:
                b["server_name_line"] = i
        if code.startswith("listen"):
            parts = code.rstrip(";").split()
            if len(parts) > 1:
                m = re.search(r"(?:^|:)(\d+)$", parts[1])
                b["ports"].append(int(m.group(1)) if m else 80)
            if "ssl" in parts[2:] or "443" in code:
                b["ssl"] = True
        if SNIPPET_NAME in lines[i]:
            b["has_include"] = True


def candidate_files(nginx_dir: Path) -> list[Path]:
    seen, result = set(), []
    for pattern in ("nginx.conf", "conf.d/*.conf", "sites-enabled/*"):
        for p in sorted(nginx_dir.glob(pattern)):
            real = p.resolve()
            if real.is_file() and real not in seen:
                seen.add(real)
                result.append(real)
    return result


def run(cmd: str) -> tuple[bool, str]:
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return r.returncode == 0, (r.stdout + r.stderr).strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="ничего не менять, только показать")
    ap.add_argument("--remove", action="store_true", help="отключить игру от основного Nginx")
    ap.add_argument("--nginx-dir", default="/etc/nginx")
    ap.add_argument("--test-cmd", default="nginx -t")
    ap.add_argument("--reload-cmd", default="systemctl reload nginx")
    ap.add_argument("--skip-detect", action="store_true", help="не проверять, кто слушает 80/443")
    ap.add_argument("--file", help="явно указать файл конфигурации сайта (если скрипт выбрал не тот)")
    args = ap.parse_args()

    env = read_env()
    domain = env.get("DOMAIN", "").strip()
    prefix = "/" + env.get("PUBLIC_PATH_PREFIX", "").strip().strip("/")
    port = env.get("HTTP_PORT", "8085")
    if not domain or prefix == "/":
        sys.exit("ОШИБКА: в .env должны быть заполнены DOMAIN и PUBLIC_PATH_PREFIX")
    nginx_dir = Path(args.nginx_dir)
    print(f"Домен: {domain}   путь: {prefix}/   ->   127.0.0.1:{port}")

    if not args.skip_detect:
        ws = detect_webserver()
        print(f"Порты 80/443 занимает: {ws}")
        if ws == "docker-proxy":
            print("\nВаш основной веб-сервер работает внутри Docker. Автоматически подключить нельзя.\n"
                  "Пришлите вывод команд:  docker ps   и   sudo ss -tlnp  — подготовлю инструкцию.")
            return 3
        if ws in ("apache2", "httpd", "caddy"):
            print(f"\nОсновной веб-сервер — {ws}, а не Nginx. Пришлите вывод  sudo ss -tlnp  — "
                  "подготовлю инструкцию для него.")
            return 3
        if ws == "none":
            print("\nПорты 80/443 никто не занимает — значит, сайт tts-ufa.ru обслуживается не этим VPS,\n"
                  "или веб-сервер выключен. Проверьте: куда указывает домен —  getent hosts " + domain)
            return 3
    if not nginx_dir.is_dir():
        sys.exit(f"ОШИБКА: папка {nginx_dir} не найдена — Nginx не установлен на хосте?")

    # Ищем блоки server для домена
    targets = []
    for f in candidate_files(nginx_dir):
        try:
            lines = f.read_text(encoding="utf-8").splitlines(keepends=True)
        except (UnicodeDecodeError, PermissionError):
            continue
        for b in find_server_blocks(lines):
            analyze_block(lines, b, domain)
            if b["server_name_line"] is not None:
                targets.append((f, lines, b))

    if not targets:
        print(f"\nНе найден блок server с  server_name {domain}  в {nginx_dir}.\n"
              f"Пришлите вывод:  sudo grep -rn server_name {nginx_dir}/  — подготовлю инструкцию.")
        return 4

    print("Найдены блоки server для домена:")
    for f, _, b in targets:
        ports = ", ".join(map(str, sorted(set(b["ports"])))) or "80"
        print(f"  {f}  (строка {b['server_name_line'] + 1}, порты: {ports}{', SSL' if b['ssl'] else ''})")

    if args.remove:
        chosen = [t for t in targets if t[2]["has_include"]]
    else:
        pool = targets
        if args.file:
            want = Path(args.file).resolve()
            pool = [t for t in targets if t[0] == want]
            if not pool:
                sys.exit(f"ОШИБКА: в файле {args.file} нет блока server с server_name {domain}")
        # Нужен блок, который обслуживает именно https://домен — порт 443
        on443 = [t for t in pool if 443 in t[2]["ports"]]
        ssl_any = [t for t in pool if t[2]["ssl"]]
        if on443:
            # Если домен на 443 описан в нескольких местах, Nginx использует ПЕРВЫЙ
            # загруженный блок (остальные игнорирует с предупреждением "conflicting server name").
            chosen = [on443[0]]
            if len(on443) > 1:
                print(f"\nВНИМАНИЕ: домен на порту 443 описан в нескольких блоках. Nginx использует первый —\n"
                      f"  {on443[0][0]}\nостальные он игнорирует, поэтому подключаю только туда.\n"
                      f"Если это не так, укажите файл явно:  --file /etc/nginx/sites-enabled/<имя>")
        elif ssl_any:
            chosen = [ssl_any[0]]
            print("\nВНИМАНИЕ: HTTPS-блок домена слушает нестандартный порт, не 443. Проверьте выбор ниже.")
        else:
            chosen = [pool[0]]
            print("\nВНИМАНИЕ: для домена нет HTTPS-блока (listen 443). Подключаю к HTTP-блоку.\n"
                  "Включить HTTPS после этого: sudo certbot --nginx -d " + domain + "  (см. docs/https.md)")
    print("Выбрано:")

    snippet_path = nginx_dir / "snippets" / SNIPPET_NAME
    include_line_tpl = "{indent}include snippets/" + SNIPPET_NAME + ";  " + MARK + "\n"

    changes: dict[Path, list[str]] = {}
    for f, lines, b in chosen:
        new = changes.get(f, list(lines))
        if args.remove:
            new = [l for l in new if SNIPPET_NAME not in l]
        elif not b["has_include"]:
            sn = b["server_name_line"]
            offset = len(new) - len(lines)  # если в одном файле несколько блоков
            indent = re.match(r"\s*", lines[sn]).group(0) or "    "
            new.insert(sn + 1 + offset, include_line_tpl.format(indent=indent))
        changes[f] = new
        state = "SSL" if b["ssl"] else "HTTP"
        print(f"  {'убрать из' if args.remove else 'подключить в'}: {f} (строка {b['server_name_line'] + 1}, блок {state})")

    changes = {f: c for f, c in changes.items() if c != f.read_text(encoding='utf-8').splitlines(keepends=True)}
    if not changes and not args.remove and snippet_path.is_file() \
            and snippet_path.read_text(encoding="utf-8") == snippet_text(prefix, port):
        print("\nУже подключено, изменений не требуется.")
        return 0

    if args.dry_run:
        print("\n--- Будет создан файл", snippet_path, "---")
        print(snippet_text(prefix, port))
        print("(--dry-run: ничего не изменено)")
        return 0

    # Применение с резервными копиями
    stamp = time.strftime("%Y%m%d-%H%M%S") + f"-{time.time_ns() // 1_000_000 % 1000:03d}"
    backups: list[tuple[Path, Path | None]] = []
    try:
        if not args.remove:
            snippet_path.parent.mkdir(parents=True, exist_ok=True)
            old = snippet_path.with_name(snippet_path.name + f".bak-{stamp}") if snippet_path.exists() else None
            if old:
                shutil.copy2(snippet_path, old)
            backups.append((snippet_path, old))
            snippet_path.write_text(snippet_text(prefix, port), encoding="utf-8")
        for f, new in changes.items():
            # копию кладём рядом с ИМЕНЕМ .ufagame-bak (не в sites-enabled, чтобы nginx её не читал)
            bak_dir = nginx_dir / "ufagame-backups"
            bak_dir.mkdir(exist_ok=True)
            bak = bak_dir / f"{f.name}.{stamp}"
            shutil.copy2(f, bak)
            backups.append((f, bak))
            f.write_text("".join(new), encoding="utf-8")
            print(f"  резервная копия: {bak}")
        ok, out = run(args.test_cmd)
        if not ok:
            raise RuntimeError(out)
    except Exception as e:  # noqa: BLE001
        print("\nОШИБКА проверки конфигурации — возвращаю всё как было:\n" + str(e))
        for target, bak in reversed(backups):
            if bak is None:
                target.unlink(missing_ok=True)
            else:
                shutil.copy2(bak, target)
        print("Файлы восстановлены. Ваш Nginx продолжает работать со старой конфигурацией.")
        return 5

    if args.remove:
        snippet_path.unlink(missing_ok=True)
    print("nginx -t: OK")
    ok, out = run(args.reload_cmd)
    if not ok:
        print("Не удалось перезагрузить Nginx:\n" + out)
        return 6
    print("Nginx перезагружен.")
    if not args.remove:
        print(f"\nПроверка:  curl https://{domain}{prefix}/health")
    return 0


if __name__ == "__main__":
    sys.exit(main())

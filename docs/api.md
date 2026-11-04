# API сервера v0.1 (контракт между server, client, admin)

База: `https://tts-ufa.ru/games/server/` (локально `http://localhost:8080/`). JSON, UTF-8. Ошибки: `{ "error": "<код>", "message": "<текст>" }` и HTTP-статус. Заголовок игрока: `Authorization: Bearer <token>`.

## Публичные
| Метод | Путь | Тело → ответ |
| --- | --- | --- |
| GET | `/health` | → `{ok,version,uptimeSec}` |
| GET | `/api/config` | → `{server,maintenance,maintenanceMessage,contentVersion,update}`. `update` — `null` или обязательное обновление, см. ниже |
| GET | `/api/media/:sha` | → файл по хешу: GLB, PNG или JPEG (без входа, кэшируется навсегда) |
| POST | `/api/guest` | → `{token,accountId}` (создаёт аккаунт, 5 героев, стартовые ресурсы) |
| POST | `/api/login` | `{login,password}` → `{token,accountId}` |
| POST | `/api/recover` | `{login,code,newPassword}` → `{token,accountId,recoveryCode}` (новый код) |

### `update` в `/api/config`
`null`, если обязательного обновления нет. Иначе:

`{versionCode, versionName, package, sha256, size, url, tag}`

Сервер смотрит последние 100 релизов GitHub (`maillunex-lang/5Ufa`, другой репозиторий — `RELEASES_REPO`) и кэширует ответ около 10 минут. Файл APK не скачивается: `sha256` берётся из текста релиза. При сбое GitHub остаётся прошлый удачный ответ (или `null`). Токен `GITHUB_TOKEN` не обязателен и в журнал не пишется.

Релиз подходит, только если всё сразу:
- не draft и не prerelease (тестовые `client-test-N` не подходят);
- тег ровно `client-vX.Y.Z`, и это не старая игра `client-v0.1.*`;
- в описании есть строки `package: ru.ttsufa.fiveufa`, `versionCode: <целое 1…2000000000>`, `versionName: X.Y.Z` (как в теге), `sha256: <64 hex>`;
- ровно один файл `.apk` по https-ссылке GitHub, размер от 1 байта до 99 МБ включительно.

Если подходят несколько, берётся больший `versionCode`. Два релиза с одним номером не выбираются. Клиент показывает экран обновления до входа, только если `versionCode` больше номера этой сборки и `url` начинается с `https://`. Исходники держат номер 1; тестовый APK подставляет номер сборки Actions. Обычного релиза нового пакета пока нет, поэтому на сервере `update` остаётся `null`.


## Игрок (нужен токен)
| Метод | Путь | Тело → ответ |
| --- | --- | --- |
| GET | `/api/me` | → `{account,heroes[{id,key,level}],balances,formation[5 id],clearedStages,storyDone[id заданий],contentVersion,maxLevel}` |
| GET | `/api/content` | → герои, враги, этапы, прогрессия, параметры боя, `abilities` (общая библиотека), `world` (карта, сезоны, задания; `null`, если в версии контента ещё нет), `ui` (цвета и рамки, рабочее предложение), `tutorial.steps` (шаги обучения: id, text, highlight[], done), `arena.bounds` (прямоугольник арены xMin, xMax, yMin, yMax: бойцы за него не выходят), `arena.camera` (position[3], lookAt[3], fov, depth: камера боя), `media` (манифест: имя → `{kind,version,sha,size,bundled}`; у картинки ещё `ext`, `.png` или `.jpg`). У героя и врага `abilities` в этом ответе уже раскрыты в полные описания. В сохранённом контенте это ссылки на `content.abilities` (строки id). Поле `anim` — какое движение играть (пусто = как раньше, по роли). |
| POST | `/api/bind` | `{login,password}` → `{recoveryCode}` (показать игроку один раз) |
| POST | `/api/formation` | `{slots:[5 id героев]}` (0–1 перед, 2–4 зад) |
| POST | `/api/tutorial/done` | → `{ok}` |
| POST | `/api/story/complete` | `{questId}` → `{storyDone[]}`. Только сюжетное задание. Награду не даёт. Повтор ничего не дублирует. Закрытое задание: 403 `locked`. |
| POST | `/api/hero/upgrade` | `{heroId}` → `{level,spent,balances}` |
| POST | `/api/hero/reset` | `{heroId}` → `{level,refunded,balances}` |
| POST | `/api/battle/start` | `{stage}` → `{battleId,winner,timeout,duration,reward,events,balances,contentVersion}` |
| GET | `/api/battle/:id` | → тот же результат (для переподключения; награду повторно не даёт) |

## События боя (`events[]`, время `t` в секундах игрового времени)
`start{units[{id,key,side:'a'|'d',slot,level,hp,x,y}]}` · `move{id,to:[x,y],speed}` (повторяется при смене цели пути) · `stop{id,x,y}` (боец остановился, точная позиция) · `attack{src,dst,ability}` · `skill{src,dst,ability}` · `damage{src,dst,amount,crit,ability,hp}` · `heal{src,dst,amount,hp,ability}` · `death{id}` · `energy{id,value}` (значение 0–100, только у героев с главной способностью) · `end{winner,timeout}`.
Координаты в условных единицах арены: игрок слева (x<0), враги справа. Клиент воспроизводит события с нужной скоростью; сам ничего не считает.

## Админ-API (`Authorization: Bearer <admin token>`, префикс `/admin/api/`)
`POST login{login,password}` · `GET status` · `POST maintenance{on,message}` · `POST backup`.

Контент (версии линейные, активна последняя; правка и откат создают новую версию, история не переписывается):
| Метод | Путь | Тело → ответ |
| --- | --- | --- |
| GET | `content/current` | → `{id,content,note,source,author,parent,created,active}` активная версия |
| GET | `content/versions?limit=` | → список `{id,hash,note,source,author,parent,created,active}` (source: file, admin, rollback) |
| GET | `content/version/:id` | → та же структура для любой версии |
| GET | `content/diff?from=&to=` | → `{from,to,total,changes[{path,from,to}],truncated}` (путь вида `heroes[tank].stats.hp`) |
| POST | `content/save` | `{content,note,baseVersion}` → `{version,changes}`; ошибки: 422 `invalid_content` с `details[]`, 409 `version_conflict`, 409 `hero_in_use`, 400 `no_changes` |
| POST | `content/rollback` | `{version,note}` → `{version,restoredFrom}`; 400 `already_current`, 404 `no_version` |
| POST | `content/reload` | `{force}` → `{changed,version}`: повторный импорт `content/game.json` |

Медиатека (модели и анимации GLB, картинки PNG/JPEG и фоны; имена логические, файлы хранятся по хешу в `data/media`):
| Метод | Путь | Тело → ответ |
| --- | --- | --- |
| GET | `media` | → `[{name,kind,folder,tags,used[{where,key,label,field}],active,versions[]}]`. Версия: `{version,sha,size,filename,source,note,author,created,active,meta,license,requirements,prompt}`. `source`: `bundled` или `upload`. У картинки `meta` — `{format,width,height}`. `used` — где имя есть в текущем контенте (герой, враг, место). |
| POST | `media/upload?name=&kind=model\|animation\|image\|background&filename=&note=&activate=0\|1` | двоичное тело. GLB до 40 МБ, картинка до 8 МБ, сторона до 4096. Новое имя активно сразу, новая версия существующего имени **не активна** до включения. Ошибки: 422 `bad_glb`, `bad_image`, `image_too_big`, `glb_too_complex`, `no_clips`; 409 `kind_mismatch`; 413 `too_large`; 400 `bad_name`, `no_changes` |
| POST | `media/activate` | `{name,version}` → запись; включение и откат версии файла |
| POST | `media/card` | `{name,folder,tags,license,requirements,prompt}` → запись на все версии этого имени. Папка без `/` и `..`. Генерации по промпту нет. |
| GET | `media/file/:sha` | → файл версии (нужен вход). Картинка отдаётся как PNG или JPEG. |

Новые редакторы добавляют свои методы здесь.

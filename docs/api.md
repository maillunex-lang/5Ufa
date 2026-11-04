# API сервера v0.1 (контракт между server, client, admin)

База: `https://tts-ufa.ru/games/server/` (локально `http://localhost:8080/`). JSON, UTF-8. Ошибки: `{ "error": "<код>", "message": "<текст>" }` и HTTP-статус. Заголовок игрока: `Authorization: Bearer <token>`.

## Публичные
| Метод | Путь | Тело → ответ |
| --- | --- | --- |
| GET | `/health` | → `{ok,version,uptimeSec}` |
| GET | `/api/config` | → `{server,maintenance,maintenanceMessage,contentVersion,update}`; `update` пока `null` (будет у трека Releases) |
| GET | `/api/media/:sha` | → GLB по хешу (без входа, кэшируется навсегда) |
| POST | `/api/guest` | → `{token,accountId}` (создаёт аккаунт, 5 героев, стартовые ресурсы) |
| POST | `/api/login` | `{login,password}` → `{token,accountId}` |
| POST | `/api/recover` | `{login,code,newPassword}` → `{token,accountId,recoveryCode}` (новый код) |

## Игрок (нужен токен)
| Метод | Путь | Тело → ответ |
| --- | --- | --- |
| GET | `/api/me` | → `{account,heroes[{id,key,level}],balances,formation[5 id],clearedStages,contentVersion,maxLevel}` |
| GET | `/api/content` | → герои, враги, этапы, прогрессия, параметры боя, `tutorial.steps` (шаги обучения: id, text, highlight[], done), `arena.bounds` (прямоугольник арены xMin, xMax, yMin, yMax: бойцы за него не выходят), `arena.camera` (position[3], lookAt[3], fov, depth: камера боя), `media` (манифест: имя → `{kind,version,sha,size,bundled}`) |
| POST | `/api/bind` | `{login,password}` → `{recoveryCode}` (показать игроку один раз) |
| POST | `/api/formation` | `{slots:[5 id героев]}` (0–1 перед, 2–4 зад) |
| POST | `/api/tutorial/done` | → `{ok}` |
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

Медиатека (модели и анимации GLB; имена логические, файлы хранятся по хешу в `data/media`):
| Метод | Путь | Тело → ответ |
| --- | --- | --- |
| GET | `media` | → `[{name,kind,active,versions[]}]`; версия: `{version,sha,size,filename,source,note,author,created,active,meta{clips[],bones[],triangles,...}}` |
| POST | `media/upload?name=&kind=model\|animation&filename=&note=&activate=0\|1` | двоичное тело GLB (до 40 МБ) → запись версии. Новое имя активно сразу, новая версия существующего имени **не активна** до включения. Ошибки: 422 `bad_glb`, `glb_too_complex`, `no_clips`; 409 `kind_mismatch`; 413; 400 `bad_name`, `no_changes` |
| POST | `media/activate` | `{name,version}` → запись; включение и откат версии файла |
| GET | `media/file/:sha` | → GLB (нужен вход) |

Новые редакторы добавляют свои методы здесь.

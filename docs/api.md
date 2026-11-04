# API сервера v0.1 (контракт между server, client, admin)

База: `https://tts-ufa.ru/games/server/` (локально `http://localhost:8080/`). JSON, UTF-8. Ошибки: `{ "error": "<код>", "message": "<текст>" }` и HTTP-статус. Заголовок игрока: `Authorization: Bearer <token>`.

## Публичные
| Метод | Путь | Тело → ответ |
| --- | --- | --- |
| GET | `/health` | → `{ok,version,uptimeSec}` |
| GET | `/api/config` | → `{server,maintenance,maintenanceMessage,contentVersion,update}`; `update` пока `null` (будет у трека Releases) |
| POST | `/api/guest` | → `{token,accountId}` (создаёт аккаунт, 5 героев, стартовые ресурсы) |
| POST | `/api/login` | `{login,password}` → `{token,accountId}` |
| POST | `/api/recover` | `{login,code,newPassword}` → `{token,accountId,recoveryCode}` (новый код) |

## Игрок (нужен токен)
| Метод | Путь | Тело → ответ |
| --- | --- | --- |
| GET | `/api/me` | → `{account,heroes[{id,key,level}],balances,formation[5 id],clearedStages,contentVersion,maxLevel}` |
| GET | `/api/content` | → герои, враги, этапы, прогрессия, параметры боя, `tutorial.steps` (шаги обучения: id, text, highlight[], done) |
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
`POST login{login,password}` · `GET status` · `POST maintenance{on,message}` · `POST backup` · `GET content/versions` · `POST content/reload`. Новые редакторы добавляют свои методы здесь и в этом файле.

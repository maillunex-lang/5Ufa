// Редактор мира. Сохранение — общая кнопка «Сохранить»: она сразу создаёт версию контента.
// Отдельного черновика на сервере нет.

function ruText(obj, key, rows) {
  obj[key] ||= { ru: '' };
  if (typeof obj[key] === 'string') obj[key] = { ru: obj[key] };
  return rows ? area(obj[key], 'ru', rows) : text(obj[key], 'ru');
}

function labelOf(x) {
  if (!x) return '';
  if (typeof x.name === 'string') return x.name;
  return x.name?.ru || x.id;
}

function worldUsers(id) {
  const w = D.world || {};
  const out = [];
  const add = (cond, text) => { if (cond) out.push(text); };
  for (const p of w.places || []) add(p.districtId === id, `место «${labelOf(p)}»`);
  for (const s of w.placeStates || []) add(s.placeId === id || s.seasonId === id, `состояние «${labelOf(s)}»`);
  for (const s of w.seasons || []) add(s.unlock === `quest:${id}`, `сезон «${labelOf(s)}»`);
  for (const c of w.chains || []) add(c.seasonId === id || c.placeId === id || c.unlock === `quest:${id}`, `цепочка «${labelOf(c)}»`);
  for (const q of w.quests || []) {
    add((q.id !== id && q.unlock === `quest:${id}`) || q.chainId === id || q.sceneId === id, `задание «${labelOf(q)}»`);
  }
  for (const hUnit of [...(D.heroes || []), ...(D.enemies || [])]) add(hUnit.faction === id, `боец «${hUnit.name}»`);
  return out;
}

function removeWorld(list, id) {
  const users = worldUsers(id);
  if (users.length) { toast('Сначала уберите ссылки: ' + users.join(', '), true); return; }
  D.world[list] = D.world[list].filter((x) => x.id !== id);
  touch();
  render();
}

function addId(list, extra) {
  const id = prompt('Ключ латиницей, например cave_hall');
  if (!id) return;
  if (!/^[a-z][a-z0-9_]{1,31}$/.test(id)) { toast('Ключ: латиница в нижнем регистре, 2–32 символа', true); return; }
  if (D.world[list].some((x) => x.id === id)) { toast('Такой ключ уже есть', true); return; }
  D.world[list].push({ id, name: { ru: 'Новая запись' }, ...extra });
  touch();
  render();
}

function viewWorld(view) {
  if (!D.world) {
    view.append(h('h2', {}, 'Мир и сезоны'), h('div', { class: 'card' }, h('p', {}, 'В этой версии контента карты ещё нет. Старые этапы от этого не ломаются.'),
      h('button', { onclick: () => { toast('Полный пример уже лежит в content/game.json. Пустой мир лучше не собирать вручную: сервер отвергнет неполные ссылки.', true); } }, 'Как добавить')));
    return;
  }
  const w = D.world;
  const used = (id) => worldUsers(id).join(', ') || 'никем';
  view.append(
    h('h2', {}, 'Мир и сезоны'),
    h('p', { style: 'color:var(--mut)' }, 'Факты и вымысел пишите в разные поля. Имена духа и виновника не закрепляйте: они в блоке вариантов. Кнопка «Сохранить» внизу сразу включает проверку и новую версию. Пока она не нажата, правка только на этом экране.'),
    h('div', { class: 'card' }, h('b', {}, w.republic?.name?.ru || 'Республика'),
      field('Факт', ruText(w.republic, 'fact', 4)),
      h('p', { style: 'color:var(--mut);font-size:13px' }, 'Источники: ' + (w.republic?.sources || []).join(' '))),
    h('div', { class: 'card' }, h('b', {}, 'Неутверждённые варианты'),
      h('p', { style: 'color:var(--mut)' }, 'Статус: ' + (w.proposals?.status || 'proposal') + '. Поле chosen сервер не примет.'),
      ...['spiritNames', 'culprits', 'startDistricts'].map((k) => h('div', {}, h('div', { class: 'meta' }, k), ...(w.proposals?.[k] || []).map((item) => text(item, 'ru'))))),
  );
  if (D.ui?.colors && D.ui.frame && D.ui.type) {
    const u = D.ui;
    view.append(h('div', { class: 'card' }, h('b', {}, 'Цвета, рамка и текст'),
      h('p', { style: 'color:var(--mut)' }, 'Рабочее предложение, не утверждённый стиль. Бой от этих чисел не меняется.'),
      h('div', { class: 'grid' }, ...['bg', 'panel', 'gold', 'magic', 'text', 'muted', 'danger'].map((k) => field(k, color(u.colors, k)))),
      field('Толщина рамки, px', num(u, 'frame.width', { int: true, min: 1, max: 4 })),
      field('Скругление, px', num(u, 'frame.radius', { int: true, min: 0, max: 24 })),
      field('Заголовок', num(u, 'type.title', { int: true, min: 12, max: 48 })),
      field('Основной текст', num(u, 'type.body', { int: true, min: 12, max: 48 })),
      field('Пометки', num(u, 'type.small', { int: true, min: 12, max: 48 }))));
  }
  const block = (title, list, extra, fields) => {
    view.append(h('div', { class: 'card' }, h('b', {}, title),
      h('button', { class: 'sec', onclick: () => addId(list, extra) }, 'Добавить'),
      ...(w[list] || []).map((item) => h('div', { class: 'card', style: 'margin-top:10px' },
        h('div', {}, h('b', {}, item.name?.ru || item.id), h('span', { class: 'tag' }, item.id)),
        field('Название', ruText(item, 'name')),
        ...fields(item),
        h('p', { class: 'meta' }, 'Где используется: ' + used(item.id)),
        h('button', { class: 'danger', onclick: () => removeWorld(list, item.id) }, 'Удалить, если никто не ссылается')))));
  };
  block('Районы и города', 'districts', { kind: 'district', order: (w.districts || []).length + 1, fact: { ru: 'Факт со ссылкой на источник' }, fiction: { ru: '' }, sources: ['https://base.garant.ru/17754606/1951ecdb73f11153fa950663aa181d1b/'], prompt: '' }, (d) => [
    field('Вид', select(d, 'kind', [['district', 'район'], ['city', 'город']])),
    field('Порядок', num(d, 'order', { int: true })),
    field('Факт', ruText(d, 'fact', 3)),
    field('Вымысел', ruText(d, 'fiction', 3)),
    field('Промпт', area(d, 'prompt', 2, { optional: true })),
  ]);
  block('Места', 'places', { districtId: w.districts?.[0]?.id || '', order: 1, fact: { ru: 'Факт' }, fiction: { ru: '' }, sources: ['https://base.garant.ru/17754606/1951ecdb73f11153fa950663aa181d1b/'], prompt: '', art: { background: '', status: 'temporary', need: ['Финальный фон ещё не нарисован'] } }, (p) => [
    field('Район', select(p, 'districtId', (w.districts || []).map((d) => [d.id, d.name?.ru || d.id]))),
    field('Порядок', num(p, 'order', { int: true })),
    field('Факт', ruText(p, 'fact', 3)),
    field('Вымысел', ruText(p, 'fiction', 3)),
    field('Файл фона', text(p.art ||= { status: 'temporary', need: [] }, 'background', { optional: true, placeholder: 'cave_demo или cave_demo.jpg' }), 'Имя из медиатеки или файл, вшитый в приложение'),
    field('Статус картинки', select(p.art, 'status', [['temporary', 'временная'], ['final', 'финальная']])),
    field('Промпт', area(p, 'prompt', 2, { optional: true })),
  ]);
  block('Состояния мест', 'placeStates', { placeId: w.places?.[0]?.id || '', seasonId: w.seasons?.[0]?.id || '', fiction: { ru: '' }, prompt: '' }, (s) => [
    field('Место', select(s, 'placeId', (w.places || []).map((p) => [p.id, p.name?.ru || p.id]))),
    field('Сезон', select(s, 'seasonId', (w.seasons || []).map((p) => [p.id, p.name?.ru || p.id]))),
    field('Вымысел', ruText(s, 'fiction', 3)),
    field('Промпт', area(s, 'prompt', 2, { optional: true })),
  ]);
  block('Сезоны', 'seasons', { kind: 'story', forever: true, order: (w.seasons || []).length + 1, unlock: 'always', summary: { ru: '' }, prompt: '' }, (s) => [
    field('Вид', select(s, 'kind', [['story', 'сюжет, навсегда'], ['arena', 'сезон арены'], ['event', 'временное событие']], { on: () => { s.forever = s.kind === 'story'; render(); } })),
    field('Навсегда', boolSelect(s, 'forever')),
    field('Порядок', num(s, 'order', { int: true })),
    field('Открытие', unlockField(s)),
    field('Описание', ruText(s, 'summary', 3)),
    field('Промпт', area(s, 'prompt', 2, { optional: true })),
  ]);
  block('Цепочки', 'chains', { seasonId: w.seasons?.[0]?.id || '', placeId: w.places?.[0]?.id || '', order: 1, unlock: 'always', prompt: '' }, (c) => [
    field('Сезон', select(c, 'seasonId', (w.seasons || []).map((p) => [p.id, p.name?.ru || p.id]))),
    field('Место', select(c, 'placeId', (w.places || []).map((p) => [p.id, p.name?.ru || p.id]))),
    field('Порядок', num(c, 'order', { int: true })),
    field('Открытие', unlockField(c)),
    field('Промпт', area(c, 'prompt', 2, { optional: true })),
  ]);
  block('Задания', 'quests', { chainId: w.chains?.[0]?.id || '', kind: 'story', order: 1, unlock: 'always', sceneId: w.scenes?.[0]?.id, prompt: '' }, (q) => [
    field('Цепочка', select(q, 'chainId', (w.chains || []).map((p) => [p.id, p.name?.ru || p.id]))),
    field('Вид', select(q, 'kind', [['story', 'сюжет'], ['battle', 'бой']], { on: () => { if (q.kind === 'battle') { delete q.sceneId; q.stage = q.stage || 1; } else { delete q.stage; q.sceneId = q.sceneId || w.scenes?.[0]?.id; } render(); } })),
    field('Порядок', num(q, 'order', { int: true })),
    field('Открытие', unlockField(q)),
    q.kind === 'battle' ? field('Этап', stageSelect(q)) : field('Сцена', select(q, 'sceneId', (w.scenes || []).map((p) => [p.id, p.name?.ru || p.id]))),
    field('Промпт', area(q, 'prompt', 2, { optional: true })),
  ]);
  block('Сцены', 'scenes', { prompt: '', lines: [{ who: 'рассказчик', text: { ru: '' } }] }, (sc) => [
    h('div', {}, ...(sc.lines || []).map((ln, i) => h('div', { class: 'toolbar' },
      field('Кто', text(ln, 'who')),
      field('Текст', ruText(ln, 'text', 2)),
      h('button', { class: 'sec', onclick: () => { sc.lines.splice(i, 1); touch(); render(); } }, 'Убрать реплику')))),
    h('button', { class: 'sec', onclick: () => { (sc.lines ||= []).push({ who: 'рассказчик', text: { ru: '' } }); touch(); render(); } }, 'Добавить реплику'),
    field('Промпт', area(sc, 'prompt', 2, { optional: true })),
  ]);
  block('Фракции', 'factions', { note: { ru: 'Только подпись, без боевых бонусов.' }, prompt: '' }, (f) => [
    field('Пояснение', ruText(f, 'note', 2)),
    field('Промпт эмблемы', area(f, 'prompt', 2, { optional: true })),
    h('p', { class: 'meta' }, 'Бонусы фракций сервер не примет.'),
  ]);
  view.append(h('div', { class: 'card' }, h('b', {}, 'Ресурсы'),
    h('p', { style: 'color:var(--mut)' }, 'Новые валюты не добавляются. Здесь только подписи уже существующих.'),
    ...(w.resources || []).map((r) => h('div', {}, field(r.id, ruText(r, 'name')), field('Промпт', area(r, 'prompt', 2, { optional: true }))))));
}

function boolSelect(obj, key) {
  const s = h('select', {}, [['true', 'да'], ['false', 'нет']].map(([v, l]) => h('option', { value: v, selected: String(obj[key]) === v }, l)));
  s.addEventListener('change', () => { obj[key] = s.value === 'true'; touch(); });
  return s;
}

function stageSelect(q) {
  const s = h('select', {}, (D.stages || []).map((st) => h('option', { value: String(st.n), selected: st.n === q.stage }, `${st.n}. ${st.name}`)));
  s.addEventListener('change', () => { q.stage = Number(s.value); touch(); });
  return s;
}

function unlockField(obj) {
  const opts = [['always', 'сразу']];
  for (const s of D.stages || []) opts.push([`stage:${s.n}`, `после этапа ${s.n}`]);
  for (const q of D.world?.quests || []) if (q.id !== obj.id) opts.push([`quest:${q.id}`, `после задания ${q.name?.ru || q.id}`]);
  if (obj.unlock && !opts.some(([v]) => String(v) === String(obj.unlock))) opts.push([obj.unlock, obj.unlock]);
  return select(obj, 'unlock', opts);
}

if (location.hash.startsWith('#/world')) render();

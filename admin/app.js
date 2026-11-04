'use strict';
// Админка 5Ufa. Без сборки и библиотек. Контент редактируется как черновик в браузере и сохраняется ОДНИМ действием:
// «Сохранить» публикует корректную правку новой версией (бои, которые уже идут, остаются на прежней версии).
// Незавершённая правка формы никуда не уходит; предпросмотр показывает черновик и не меняет сохранённую версию.

const $ = (id) => document.getElementById(id);
let T = sessionStorage.getItem('t');
let D = null;      // черновик контента
let BASE = 0;      // версия, на которой основан черновик
let SAVED = '';    // JSON сохранённой версии (для определения «есть правки»)
const UI = { q: '', role: '', tab: 'main', media: '' };

const ROLE_L = { tank: 'Танк', melee: 'Боец ближнего боя', ranged: 'Стрелок', mage: 'Маг', healer: 'Целитель' };
const TYPE_L = { regular: 'Обычный', cool: 'Крутой' };
const KIND_L = { basic: 'Базовая атака', skill: 'Обычная способность', main: 'Главная способность', passive: 'Пассивная' };
const EFFECT_L = { single: 'Один враг', aoe: 'Все враги', heal: 'Лечение союзника с минимальным здоровьем' };
const STAT_L = { hp: 'Здоровье', atk: 'Атака', def: 'Защита', critChance: 'Шанс крита (0–1, только базовая атака)', critPower: 'Сила крита (множитель)', range: 'Дальность атаки', interval: 'Интервал атак (с)', speed: 'Скорость бега' };
const SRC_L = { file: 'файл', admin: 'админка', rollback: 'откат' };

// ---------------------------------------------------------------- утилиты

function h(tag, props, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (v === false || v == null) continue;
    if (k === 'class') e.className = v;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k === 'value') e.value = v;
    else if (v === true) e.setAttribute(k, '');
    else e.setAttribute(k, v);
  }
  for (const k of kids.flat(Infinity)) if (k != null && k !== false) e.append(k.nodeType ? k : document.createTextNode(String(k)));
  return e;
}
const clone = (o) => JSON.parse(JSON.stringify(o));
const fmtTime = (ts) => new Date(ts).toLocaleString();

async function api(path, body) {
  const r = await fetch('api/' + path, { method: body ? 'POST' : 'GET', headers: { 'content-type': 'application/json', authorization: 'Bearer ' + T }, body: body ? JSON.stringify(body) : undefined });
  if (r.status === 401 && path !== 'login') { T = null; sessionStorage.removeItem('t'); showApp(); throw new Error('Сессия истекла, войдите снова'); }
  const j = await r.json();
  if (!r.ok) { const e = new Error(j.message || r.status); e.details = j.details; e.code = j.error; throw e; }
  return j;
}

let toastTimer;
function toast(msg, bad) {
  const t = $('toast');
  t.textContent = msg;
  t.style.display = 'block';
  t.style.borderColor = bad ? 'var(--bad)' : 'var(--acc)';
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.style.display = 'none'; }, 3500);
}

function modal(content) {
  const m = h('div', { class: 'modal', onclick: (e) => { if (e.target === m) m.remove(); } }, h('div', { class: 'card' }, content));
  document.body.append(m);
  return m;
}

// Доступ по пути вида 'progression.upgradeCost.gold'. Чтение ничего не создаёт: вложенные объекты появляются только при записи.
function acc(obj, path) {
  const parts = path.split('.');
  const last = parts.pop();
  const parent = (create) => {
    let o = obj;
    for (const k of parts) {
      if (o[k] == null || typeof o[k] !== 'object') { if (!create) return null; o[k] = {}; }
      o = o[k];
    }
    return o;
  };
  return { get: () => parent(false)?.[last], set: (v) => { parent(true)[last] = v; }, del: () => { const p = parent(false); if (p) delete p[last]; } };
}

// ---------------------------------------------------------------- поля формы

function field(label, input, hint) {
  return h('label', { class: 'f' }, h('span', { class: 'lb' }, label), input, hint ? h('small', {}, hint) : null);
}
function num(obj, path, o = {}) {
  const r = acc(obj, path);
  const i = h('input', { type: 'number', step: o.step ?? 'any', min: o.min, max: o.max, value: r.get() ?? '' });
  i.addEventListener('input', () => {
    if (i.value === '') return;
    let v = Number(i.value);
    if (o.int) v = Math.round(v);
    r.set(v);
    touch();
    if (o.on) o.on();
  });
  return i;
}
function text(obj, path, o = {}) {
  const r = acc(obj, path);
  const i = h('input', { type: 'text', value: r.get() ?? '', placeholder: o.placeholder, disabled: o.disabled });
  i.addEventListener('input', () => { if (i.value === '' && o.optional) r.del(); else r.set(i.value); touch(); });
  return i;
}
function area(obj, path, rows = 3, o = {}) {
  const r = acc(obj, path);
  const i = h('textarea', { rows, placeholder: o.placeholder });
  i.value = r.get() ?? '';
  i.addEventListener('input', () => { if (i.value === '' && o.optional) r.del(); else r.set(i.value); touch(); });
  return i;
}
function select(obj, path, options, o = {}) {
  const r = acc(obj, path);
  const s = h('select', { disabled: o.disabled }, options.map(([v, l]) => h('option', { value: v }, l)));
  s.value = r.get() ?? options[0][0];
  s.addEventListener('change', () => { if (s.value === '' && o.optional) r.del(); else r.set(s.value); touch(); if (o.on) o.on(); });
  return s;
}
function check(obj, path, label, o = {}) {
  const r = acc(obj, path);
  const c = h('input', { type: 'checkbox', disabled: o.disabled });
  c.checked = !!r.get();
  c.addEventListener('change', () => { r.set(c.checked); touch(); });
  return h('label', { class: 'f' }, c, ' ', label);
}
function color(obj, path) {
  const r = acc(obj, path);
  const i = h('input', { type: 'color', value: /^#[0-9a-f]{6}$/i.test(r.get() || '') ? r.get() : '#ffffff' });
  i.addEventListener('input', () => { r.set(i.value); touch(); });
  return i;
}
// JSON-поле для сложных настроек (названия анимаций, крепления): принимается только корректный JSON
function jsonField(obj, path, rows = 4) {
  const r = acc(obj, path);
  const i = h('textarea', { rows, spellcheck: 'false', style: 'font:12px monospace' });
  i.value = r.get() === undefined ? '' : JSON.stringify(r.get(), null, 1);
  i.addEventListener('input', () => {
    if (i.value.trim() === '') { r.del(); i.style.borderColor = ''; touch(); return; }
    try { r.set(JSON.parse(i.value)); i.style.borderColor = ''; touch(); } catch { i.style.borderColor = 'var(--bad)'; }
  });
  return i;
}
const grid = (...fields) => h('div', { class: 'grid' }, fields);

// ---------------------------------------------------------------- черновик и панель сохранения

function dirty() { return D && JSON.stringify(D) !== SAVED; }

function touch() { drawSavebar(); }

let saveErr = null;
function drawSavebar() {
  const bar = $('savebar');
  if (!dirty()) { bar.hidden = true; bar.replaceChildren(); saveErr = null; return; }
  const note = bar.querySelector('input')?.value || '';
  bar.hidden = false;
  bar.replaceChildren(...[
    h('div', { class: 't' }, 'Есть несохранённые изменения. Сохранение сразу создаёт новую версию, действует со следующего боя.'),
    h('input', { placeholder: 'Комментарий к изменению (необязательно)', value: note, id: 'savenote' }),
    h('button', { onclick: saveDraft }, 'Сохранить'),
    h('button', { class: 'sec', onclick: discard }, 'Отменить правки'),
    saveErr ? h('div', { class: 'err' }, saveErr.message, saveErr.details ? h('ul', {}, saveErr.details.map((d) => h('li', {}, typeof d === 'string' ? d : JSON.stringify(d)))) : null) : null,
  ].filter(Boolean));
}

async function loadContent() {
  const c = await api('content/current');
  D = clone(c.content);
  BASE = c.id;
  SAVED = JSON.stringify(c.content);
  saveErr = null;
  drawSavebar();
}

async function saveDraft() {
  try {
    const r = await api('content/save', { content: D, note: ($('savenote')?.value || '').slice(0, 300), baseVersion: BASE });
    toast(`Сохранено: версия #${r.version}, изменений ${r.changes}`);
    await loadContent();
    render();
  } catch (e) {
    saveErr = e;
    drawSavebar();
    if (e.code === 'version_conflict') toast('Контент уже изменили в другом месте. Обновите страницу.', true);
  }
}

async function discard() {
  if (!confirm('Отменить все несохранённые правки?')) return;
  D = JSON.parse(SAVED);
  saveErr = null;
  drawSavebar();
  render();
}

window.addEventListener('beforeunload', (e) => { if (dirty()) { e.preventDefault(); e.returnValue = ''; } });

// ---------------------------------------------------------------- навигация

const NAV = [
  ['', [['home', 'Главная']]],
  ['Контент', [['heroes', 'Герои'], ['enemies', 'Враги и боссы'], ['balance', 'Баланс и прогрессия'], ['stages', 'Этапы: награды и сила'], ['arena', 'Арена и камера'], ['tutorial', 'Обучение']]],
  ['Интерфейс', [['soon:ui', 'Экраны (скоро)']]],
  ['Игроки', [['soon:players', 'Аккаунты (скоро)']]],
  ['Система', [['media', 'Медиатека (модели)'], ['versions', 'Версии контента']]],
];

function drawNav(cur) {
  const nav = $('nav');
  nav.replaceChildren(...NAV.flatMap(([title, items]) => [
    title ? h('b', {}, title) : null,
    ...items.map(([id, label]) => (id.startsWith('soon:')
      ? h('a', { class: 'soon' }, label)
      : h('a', { class: cur === id ? 'cur' : '', onclick: () => { location.hash = '#/' + id; nav.classList.remove('open'); } }, label))),
  ]).filter(Boolean));
}

function route() {
  const parts = (location.hash.replace(/^#\/?/, '') || 'home').split('/');
  return { page: parts[0], arg: parts[1] };
}

let LIVE = [];
function disposeLive() { LIVE.forEach((r) => r.dispose?.()); LIVE = []; }

function render() {
  if (!D) return;
  disposeLive();
  const { page, arg } = route();
  drawNav(page);
  const view = $('view');
  const fn = { home: viewHome, heroes: () => viewUnits('heroes', arg), enemies: () => viewUnits('enemies', arg), balance: viewBalance, stages: viewStages, arena: viewArena, tutorial: viewTutorial, media: viewMedia, versions: viewVersions }[page] || viewHome;
  view.replaceChildren();
  Promise.resolve(fn(view)).catch((e) => view.replaceChildren(h('div', { class: 'card bad' }, e.message)));
}
window.addEventListener('hashchange', render);

// ---------------------------------------------------------------- Главная

async function viewHome(view) {
  const s = await api('status');
  const card = (a, b) => h('div', { class: 'card' }, h('small', {}, a), h('strong', {}, b));
  view.append(
    h('div', { class: 'grid' }, card('Сервер', 'v' + s.version), card('Аптайм', Math.round(s.uptimeSec / 60) + ' мин'), card('Версия контента', '#' + s.contentVersion),
      card('Аккаунты', s.accounts), card('Бои всего / за сутки', `${s.battles} / ${s.battlesLastDay}`), card('Бэкап', s.lastBackup || '—'), card('Режим', s.maintenance ? 'ТЕХРАБОТЫ' : 'работает')),
    h('div', { class: 'card' }, h('b', {}, 'Быстрые переходы'),
      h('p', {}, ...[['heroes', 'Герои'], ['enemies', 'Враги'], ['balance', 'Баланс'], ['arena', 'Арена и камера'], ['versions', 'Версии']].map(([id, l]) => h('button', { class: 'sec', style: 'margin:0 6px 6px 0', onclick: () => { location.hash = '#/' + id; } }, l)))),
    h('div', { class: 'card' }, h('b', {}, 'Действия'),
      h('p', {},
        h('button', { class: 'sec', style: 'margin:0 6px 6px 0', onclick: async () => {
          if (!s.maintenance && !confirm('Новые бои будут заблокированы. Включить техработы?')) return;
          await api('maintenance', { on: !s.maintenance, message: s.maintenance ? '' : 'Технические работы' }); render();
        } }, s.maintenance ? 'Выключить техработы' : 'Включить техработы'),
        h('button', { class: 'sec', style: 'margin:0 6px 6px 0', onclick: async () => { toast('Бэкап создан: ' + (await api('backup', {})).name); } }, 'Бэкап сейчас'))),
    h('div', { class: 'card' }, h('b', {}, 'Ошибки'),
      h('table', {}, s.errors.length ? s.errors.map((e) => h('tr', {}, h('td', {}, fmtTime(e.ts)), h('td', {}, e.source), h('td', {}, e.message.slice(0, 200)))) : h('tr', {}, h('td', { class: 'ok' }, 'Ошибок нет')))),
    h('div', { class: 'card' }, h('b', {}, 'Последние изменения'),
      h('table', {}, s.changes.map((e) => h('tr', {}, h('td', {}, fmtTime(e.ts)), h('td', {}, e.action), h('td', {}, e.detail || ''))))),
  );
}

// ---------------------------------------------------------------- Версии контента

async function viewVersions(view) {
  const list = await api('content/versions?limit=30');
  const cur = (list.find((v) => v.active) || {}).id || 0;
  const diffBox = h('pre', { hidden: true });
  const jerr = h('div', { class: 'bad' });
  const ta = h('textarea', { spellcheck: 'false', style: 'height:260px;font:12px monospace' });
  const note = h('input', { placeholder: 'Комментарий к изменению (необязательно)' });
  const reloadJson = async () => { ta.value = JSON.stringify((await api('content/current')).content, null, 1); };
  reloadJson();
  view.append(
    h('div', { class: 'card' }, h('b', {}, 'Версии контента'),
      h('p', { style: 'color:var(--mut)' }, `Активна #${cur}. Правка и откат создают новую версию, история сохраняется.`),
      list.map((v) => h('div', { class: 'vrow' },
        h('b', {}, `#${v.id}${v.active ? ' ✓ активна' : ''}`), ' ', h('span', {}, fmtTime(v.created)), h('span', {}, (SRC_L[v.source] || v.source || '') + (v.author ? ', ' + v.author : '')),
        h('div', { class: 'nt' }, v.note || ''),
        v.active ? null : [
          h('button', { class: 'sec', onclick: async () => {
            const d = await api(`content/diff?from=${v.id}&to=${cur}`);
            diffBox.hidden = false;
            diffBox.textContent = d.total ? `Отличия версии #${d.from} от активной #${d.to} (${d.total}):\n` + d.changes.map((c) => `${c.path}: ${c.from} → ${c.to}`).join('\n') : 'Содержимое совпадает.';
          } }, 'Отличия'),
          h('button', { class: 'sec', onclick: async () => {
            if (dirty() && !confirm('Несохранённые правки в черновике будут потеряны. Продолжить?')) return;
            if (!confirm(`Откатить контент к версии #${v.id}? Будет создана новая версия. Аккаунты игроков не меняются.`)) return;
            try { const r = await api('content/rollback', { version: v.id }); toast('Откат: новая версия #' + r.version); await loadContent(); render(); } catch (e) { toast(e.message, true); }
          } }, 'Откатить')])),
      diffBox),
    h('details', { class: 'card' }, h('summary', {}, 'Редактор JSON целиком (для опытных)'),
      h('p', { style: 'color:var(--mut);font-size:13px' }, 'Сохраняется как новая версия. Формы в разделах слева удобнее и безопаснее.'),
      ta, note, h('p', {}, h('button', { onclick: async () => {
        jerr.replaceChildren();
        let obj;
        try { obj = JSON.parse(ta.value); } catch (e) { jerr.textContent = 'Не JSON: ' + e.message; return; }
        try { const r = await api('content/save', { content: obj, note: note.value, baseVersion: BASE }); toast('Сохранено: версия #' + r.version); await loadContent(); render(); }
        catch (e) { jerr.append(e.message, e.details ? h('ul', {}, e.details.map((d) => h('li', {}, typeof d === 'string' ? d : JSON.stringify(d)))) : null); }
      } }, 'Сохранить как новую версию'), ' ', h('button', { class: 'sec', onclick: reloadJson }, 'Загрузить текущую')), jerr),
  );
}

// ---------------------------------------------------------------- Герои и враги

function growthFactor(level) { return 1 + (D.progression.growth || 0) * (level - 1); }
function passiveMult(u, stat) {
  return (u.abilities || []).filter((a) => a.kind === 'passive').reduce((m, a) => m * (a.mods?.[stat] ?? 1), 1);
}

function viewUnits(kind, key) {
  const list = D[kind];
  if (key) return viewUnit(kind, list.find((u) => u.key === key));
  const isHero = kind === 'heroes';
  const q = UI.q.toLowerCase();
  const items = list.filter((u) => (!q || u.key.includes(q) || (u.name || '').toLowerCase().includes(q)) && (!isHero || !UI.role || u.role === UI.role));
  const view = $('view');
  view.append(
    h('h2', {}, isHero ? 'Герои' : 'Враги и боссы'),
    h('div', { class: 'toolbar' },
      h('input', { placeholder: 'Поиск по имени или ключу', value: UI.q, oninput: (e) => { UI.q = e.target.value; const pos = e.target.selectionStart; render(); const i = $('view').querySelector('input'); i.focus(); i.setSelectionRange(pos, pos); } }),
      isHero ? h('select', { onchange: (e) => { UI.role = e.target.value; render(); } }, [['', 'Все роли'], ...Object.entries(ROLE_L)].map(([v, l]) => h('option', { value: v, selected: UI.role === v }, l))) : null,
      h('button', { onclick: () => createDialog(kind) }, isHero ? 'Создать героя' : 'Создать врага')),
    ...(items.length ? items.map((u) => h('div', { class: 'item', onclick: () => { UI.tab = 'main'; location.hash = `#/${kind}/${u.key}`; } },
      h('div', {}, h('b', {}, u.name), h('span', { class: 'tag' }, u.key), isHero ? h('span', { class: 'tag' }, ROLE_L[u.role] || u.role) : null, isHero && u.type === 'cool' ? h('span', { class: 'tag' }, 'крутой') : null, isHero && u.starter ? h('span', { class: 'tag' }, 'стартовый') : null,
        h('div', { class: 'meta' }, `HP ${u.stats.hp} · атака ${u.stats.atk} · защита ${u.stats.def} · способностей ${u.abilities.length}`)),
      h('span', {}, '›'))) : [h('div', { class: 'card' }, 'Ничего не найдено')]),
  );
}

function createDialog(kind) {
  const isHero = kind === 'heroes';
  const list = D[kind];
  const opts = [];
  if (isHero) for (const r of Object.keys(ROLE_L)) { const t = D.heroes.find((x) => x.role === r); if (t) opts.push([`role:${r}`, `Шаблон роли: ${ROLE_L[r]}`]); }
  for (const u of list) opts.push([`copy:${u.key}`, `Независимая копия: ${u.name}`]);
  const key = h('input', { placeholder: 'Ключ: латиница, цифры, _ (например paladin)' });
  const name = h('input', { placeholder: 'Название (например Паладин)' });
  const tpl = h('select', {}, opts.map(([v, l]) => h('option', { value: v }, l)));
  const err = h('div', { class: 'bad' });
  const m = modal([h('h3', {}, isHero ? 'Новый герой' : 'Новый враг'), field('Ключ', key, 'Менять нельзя после создания'), field('Название', name), field('Основа', tpl, 'Создаётся независимая копия: правки не затрагивают оригинал'),
    err, h('button', { onclick: () => {
      const k = key.value.trim();
      if (!/^[a-z][a-z0-9_]{1,31}$/.test(k)) { err.textContent = 'Ключ: латиница в нижнем регистре, цифры и _, 2–32 символа, первая — буква'; return; }
      if ([...D.heroes, ...D.enemies].some((u) => u.key === k)) { err.textContent = 'Такой ключ уже есть'; return; }
      const [mode, ref0] = tpl.value.split(':');
      const src = mode === 'role' ? D.heroes.find((x) => x.role === ref0) : list.find((x) => x.key === ref0);
      const u = clone(src);
      u.key = k; u.name = name.value.trim() || k;
      if (isHero) u.starter = false;
      const used = new Set([...D.heroes, ...D.enemies].flatMap((x) => x.abilities.map((a) => a.id)));
      u.abilities.forEach((a) => {
        const suffix = a.id.includes('_') ? a.id.split('_').slice(1).join('_') : a.kind;
        let id = `${k}_${suffix}`, n = 2;
        while (used.has(id)) id = `${k}_${suffix}${n++}`;
        used.add(id); a.id = id;
      });
      delete u.visual?.prompt;
      list.push(u);
      touch();
      m.remove();
      location.hash = `#/${kind}/${k}`;
    } }, 'Создать'), ' ', h('button', { class: 'sec', onclick: () => m.remove() }, 'Отмена')]);
}

function viewUnit(kind, u) {
  const view = $('view');
  if (!u) { view.append(h('div', { class: 'card bad' }, 'Не найдено'), h('button', { class: 'sec', onclick: () => { location.hash = `#/${kind}`; } }, '← К списку')); return; }
  const isHero = kind === 'heroes';
  const tabs = [['main', 'Основное'], ['look', 'Внешний вид и анимации'], ['stats', 'Характеристики и рост'], ['abil', 'Способности']];
  const body = h('div', {});
  const draw = () => {
    disposeLive();
    body.replaceChildren(...({ main: tabMain, look: tabLook, stats: tabStats, abil: tabAbil }[UI.tab])(u, isHero, draw));
    tabBar.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset.t === UI.tab));
  };
  const tabBar = h('div', { class: 'tabs' }, tabs.map(([id, l]) => h('button', { 'data-t': id, onclick: () => { UI.tab = id; draw(); } }, l)));
  view.append(
    h('button', { class: 'sec', onclick: () => { location.hash = `#/${kind}`; } }, '← К списку'),
    h('h2', {}, u.name, h('span', { class: 'tag' }, u.key)),
    tabBar, body,
    h('div', { class: 'card', style: 'margin-top:16px' }, h('b', {}, 'Удаление'),
      h('p', { style: 'color:var(--mut);font-size:13px' }, isHero ? 'Героя, которым уже владеют игроки, удалить нельзя: сервер откажет. Удаление с компенсацией будет добавлено отдельно.' : 'Врага, который стоит в этапах кампании, удалить нельзя: сначала уберите его из этапов.'),
      h('button', { class: 'danger', onclick: () => {
        if (!confirm(`Удалить «${u.name}» из черновика? Окончательно удалится после «Сохранить».`)) return;
        D[kind] = D[kind].filter((x) => x !== u); touch(); location.hash = `#/${kind}`;
      } }, 'Удалить из черновика')),
  );
  draw();
}

function tabMain(u, isHero) {
  return [h('div', { class: 'card' },
    grid(field('Ключ (стабильный идентификатор)', h('input', { value: u.key, disabled: true })), field('Название', text(u, 'name'))),
    isHero ? grid(
      field('Роль', select(u, 'role', Object.entries(ROLE_L))),
      field('Тип', select(u, 'type', Object.entries(TYPE_L)), 'Крутой: базовая, главная и 2 пассивные. Обычный: базовая и одна способность.')) : null,
    isHero ? h('p', { style: 'color:var(--mut);font-size:13px' }, u.starter ? 'Стартовый герой: выдаётся каждому новому аккаунту (их должно быть ровно 5).' : 'Не стартовый: игрок получит его позже (призыв, награды; пока не реализовано).') : null)];
}

function tabLook(u) {
  const mk = () => `Персонаж для мобильной RPG, ${u.name}${u.role ? ' (' + (ROLE_L[u.role] || u.role) + ')' : ''}. Стиль: мультяшный, чибби, низкополигональный, простые цвета, как KayKit Adventurers. A-поза, руки чуть в стороны, ноги раздельно, одежда выше щиколоток, без плаща и лент, одна фигура, без подставки. Скелет Mixamo (гуманоид). Анимации: стойка, бег, удар, умение, получение удара, смерть. Формат GLB, текстура внутри, до 15 тысяч треугольников.`;
  const prompt = area(u, 'visual.prompt', 6, { optional: true, placeholder: 'Инструкция для внешнего ИИ (Meshy и др.): стиль, ракурс, размеры, список анимаций' });
  return [
    h('div', { class: 'card' }, h('b', {}, '3D-просмотр, графика и анимации'), modelBlock({ unit: u })),
    h('div', { class: 'card' }, h('b', {}, 'Модель'),
      grid(field('Файл модели', text(u, 'visual.model', { optional: true }), 'Имя файла из client/assets/models без .glb (загрузка через медиатеку появится позже)'),
        field('Масштаб', num(u, 'visual.scale', { step: 0.05, min: 0.1, max: 10 })), field('Поворот модели, °', num(u, 'visual.yaw', { step: 5 }), 'Если модель смотрит не туда'),
        field('Смещение по высоте', num(u, 'visual.y_offset', { step: 0.05 })), field('Высота полосы здоровья', num(u, 'visual.bar_height', { step: 0.1 })),
        field('Цвет магии', color(u, 'visual.magic_color')),
        field('Стиль атаки', select(u, 'visual.attack_style', [['', 'По роли (маги и целитель — магия)'], ['magic', 'Магия (снаряд)'], ['melee', 'Ближний бой'], ['ranged', 'Дальний бой']], { optional: true }))),
      check(u, 'visual.root_lock', 'Блокировать смещение таза в анимациях (если анимации «уезжают» вперёд/назад)')),
    h('div', { class: 'card' }, h('b', {}, 'Дополнительно (JSON)'),
      field('Названия анимаций модели (idle, run, attack_melee, attack_melee_strong, cast, cast_strong, hit, death)', jsonField(u, 'visual.anims', 5), 'Если пусто, используются названия набора KayKit'),
      field('Скорость проигрывания анимаций', jsonField(u, 'visual.anim_speed', 3), 'Например {"attack_melee": 2.0}: ускорить длинные анимации'),
      field('Предметы в руках', jsonField(u, 'visual.attachments', 5), 'Например меч: [{"bone":"mixamorig:RightHand","prop":"sword","pos":[0,0.05,0],"rot":[0,0,-90],"scale":1}]'),
      field('Скрыть части модели', jsonField(u, 'visual.hide', 2), 'Список названий, например ["Spike_Shield"]')),
    h('div', { class: 'card' }, h('b', {}, 'Промпт для внешнего ИИ'),
      field('Инструкция', prompt),
      h('button', { class: 'sec', onclick: () => { if (!prompt.value) { prompt.value = mk(); prompt.dispatchEvent(new Event('input')); } } }, 'Подставить шаблон'), ' ',
      h('button', { class: 'sec', onclick: async () => { await navigator.clipboard.writeText(prompt.value); toast('Промпт скопирован'); } }, 'Копировать'),
      h('p', { style: 'color:var(--mut);font-size:12px' }, 'Генерация идёт вне игры (Meshy и т. п.), готовый GLB загружается вручную.')),
  ];
}

function tabStats(u, isHero, draw) {
  const maxLv = Math.min(D.progression.maxLevel || 10, 10);
  const levels = Array.from({ length: maxLv }, (_, i) => i + 1);
  const tbl = h('table', {});
  const redraw = () => {
    tbl.replaceChildren(
      h('tr', {}, h('th', {}, 'Уровень'), levels.map((l) => h('th', {}, l))),
      ...['hp', 'atk', 'def'].map((s) => h('tr', {}, h('td', {}, STAT_L[s].split(' ')[0]), levels.map((l) => h('td', {}, Math.round(u.stats[s] * growthFactor(l) * passiveMult(u, s)))))));
  };
  redraw();
  const g = Math.round((D.progression.growth || 0) * 100);
  const pas = ['hp', 'atk', 'def'].map((s) => [s, passiveMult(u, s)]).filter(([, m]) => m !== 1).map(([s, m]) => `${s} ×${m}`).join(', ');
  return [
    h('div', { class: 'card' }, h('b', {}, 'Базовые характеристики (уровень 1, без пассивных бонусов)'),
      grid(...Object.entries(STAT_L).map(([k, l]) => field(l, num(u, 'stats.' + k, { step: k === 'critChance' ? 0.01 : k === 'interval' || k === 'critPower' || k === 'range' || k === 'speed' ? 0.1 : 1, min: 0, on: redraw }))))),
    h('div', { class: 'card' }, h('b', {}, 'Итог по уровням'),
      tbl,
      h('p', { style: 'color:var(--mut);font-size:12px' }, `Источник значения: база × (1 + рост × (уровень − 1)) × пассивные бонусы. Рост за уровень ${g}% общий для всех, меняется в разделе «Баланс и прогрессия». Пассивные бонусы этого юнита: ${pas || 'нет'}.${isHero ? '' : ' У врагов на этапе hp и атака дополнительно умножаются на силу этапа.'}`)),
  ];
}

function tabAbil(u, isHero, draw) {
  const cards = u.abilities.map((a) => abilityCard(u, a, draw));
  const kind = h('select', {}, Object.entries(KIND_L).filter(([k]) => k !== 'basic').map(([v, l]) => h('option', { value: v }, l)));
  return [
    ...cards,
    h('div', { class: 'card' }, h('b', {}, 'Добавить способность'), h('div', { class: 'toolbar' }, kind, h('button', { onclick: () => {
      const used = new Set([...D.heroes, ...D.enemies].flatMap((x) => x.abilities.map((a) => a.id)));
      let n = 1; while (used.has(`${u.key}_${kind.value}${n}`)) n++;
      const id = `${u.key}_${kind.value}${n}`;
      const a = { id, kind: kind.value };
      if (kind.value === 'passive') a.mods = { hp: 1.1 }; else { a.effect = 'single'; a.mult = 1.5; if (kind.value === 'skill') a.cooldown = 6; }
      u.abilities.push(a); touch(); draw();
    } }, 'Добавить')),
    h('p', { style: 'color:var(--mut);font-size:12px' }, 'Правила: ровно одна базовая атака, не больше одной главной. Критический удар — только у базовой атаки. Общую библиотеку способностей и конструктор блоков добавим позже.')),
  ];
}

function abilityCard(u, a, draw) {
  const parts = [h('div', { style: 'display:flex;justify-content:space-between;gap:8px;align-items:center' },
    h('b', {}, KIND_L[a.kind] || a.kind, h('span', { class: 'tag' }, a.id)),
    a.kind === 'basic' ? null : h('button', { class: 'danger', onclick: () => { u.abilities = u.abilities.filter((x) => x !== a); touch(); draw(); } }, 'Удалить'))];
  parts.push(grid(field('Название', text(a, 'name', { optional: true, placeholder: 'Например Огненная комета' })), a.kind === 'basic' ? null : field('Вид', select(a, 'kind', Object.entries(KIND_L).filter(([k]) => k !== 'basic'), { on: () => { if (a.kind === 'passive') { delete a.effect; delete a.mult; delete a.cooldown; a.mods ||= { hp: 1.1 }; } else { delete a.mods; a.effect ||= 'single'; a.mult ||= 1.5; if (a.kind === 'skill') a.cooldown ??= 6; else delete a.cooldown; } draw(); } }))));
  if (a.kind === 'passive') {
    const mods = (a.mods ||= {});
    parts.push(h('p', { style: 'color:var(--mut);font-size:13px' }, 'Пассивный бонус: множитель к характеристике (1.1 = +10%).'),
      ...Object.keys(mods).map((s) => h('div', { class: 'toolbar' },
        h('select', { onchange: (e) => { const v = mods[s]; delete mods[s]; mods[e.target.value] = v; touch(); draw(); } }, ['hp', 'atk', 'def', 'critChance', 'critPower', 'range', 'interval', 'speed'].map((x) => h('option', { value: x, selected: x === s }, STAT_L[x].split(' (')[0]))),
        num(mods, s, { step: 0.05, min: 0.1, max: 10 }),
        h('button', { class: 'sec', onclick: () => { delete mods[s]; touch(); draw(); } }, 'Убрать'))),
      h('button', { class: 'sec', onclick: () => { const free = ['hp', 'atk', 'def', 'critChance', 'critPower', 'range', 'interval', 'speed'].find((x) => !(x in mods)); if (free) { mods[free] = 1.1; touch(); draw(); } } }, 'Добавить бонус'));
  } else {
    parts.push(grid(
      a.kind === 'basic' ? null : field('Действие', select(a, 'effect', Object.entries(EFFECT_L))),
      field('Множитель атаки (урон или лечение = атака × множитель)', num(a, 'mult', { step: 0.1, min: 0.1 })),
      a.kind === 'skill' ? field('Перезарядка, с', num(a, 'cooldown', { step: 0.5, min: 0 })) : null));
    if (a.kind !== 'basic') parts.push(h('div', { class: 'toolbar' }, field('Описание', text(a, 'description', { optional: true })),
      field('Эффект при применении', select(a, 'vfx.style', [['', 'По умолчанию (по роли)'], ['none', 'Без снаряда'], ['magic_bolt', 'Магический снаряд'], ['fire_comet', 'Огненная комета']], { optional: true, on: () => { if (a.vfx && !a.vfx.style && !a.vfx.color) delete a.vfx; touch(); } })),
      field('Цвет эффекта', color(a, 'vfx.color'))));
    if (a.kind === 'main') parts.push(h('p', { style: 'color:var(--mut);font-size:12px' }, 'Главная срабатывает автоматически при полной энергии. Энергию дают атаки и полученный урон (раздел «Баланс»).'));
  }
  return h('div', { class: 'card' }, parts);
}

// ---------------------------------------------------------------- Баланс

function viewBalance(view) {
  view.append(h('h2', {}, 'Баланс и прогрессия'), h('p', { style: 'color:var(--mut)' }, 'Все значения тестовые. Изменения действуют со следующего боя; уже начатые бои остаются на прежних правилах.'),
    h('div', { class: 'card' }, h('b', {}, 'Прокачка героев'),
      grid(field('Максимальный уровень', num(D, 'progression.maxLevel', { int: true, min: 1, max: 100 })),
        field('Рост характеристик за уровень (0.12 = +12% от базы)', num(D, 'progression.growth', { step: 0.01, min: 0, max: 5 })),
        field('Цена улучшения: золото × текущий уровень', num(D, 'progression.upgradeCost.gold', { int: true, min: 0 })),
        field('Цена улучшения: опыт героев × текущий уровень', num(D, 'progression.upgradeCost.hero_exp', { int: true, min: 0 })),
        field('Стартовое золото', num(D, 'progression.startBalance.gold', { int: true, min: 0 })),
        field('Стартовый опыт героев', num(D, 'progression.startBalance.hero_exp', { int: true, min: 0 }))),
      h('p', { style: 'color:var(--mut);font-size:12px' }, 'Сброс уровня возвращает фактически потраченное, поэтому смена цен не создаёт ресурсов.')),
    h('div', { class: 'card' }, h('b', {}, 'Правила боя'),
      grid(field('Шаг симуляции, с', num(D, 'battle.tick', { step: 0.05, min: 0.05, max: 1 })), field('Лимит боя, с', num(D, 'battle.timeLimit', { int: true, min: 10, max: 600 }), 'По истечении побеждает защитник'),
        field('Энергия: максимум', num(D, 'battle.energyMax', { int: true, min: 1 })), field('Энергия за действие', num(D, 'battle.energyOnAttack', { int: true, min: 0 })),
        field('Энергия за полученный удар', num(D, 'battle.energyOnDamaged', { int: true, min: 0 })), field('Константа защиты', num(D, 'battle.defConst', { min: 1 }), 'Урон = атака × множитель × K / (K + защита)'))),
    h('div', { class: 'card' }, h('b', {}, '«Мощь» отряда (показывается над боем)'),
      grid(field('Вес здоровья', num(D, 'battle.powerWeights.hp', { step: 0.05, min: 0 })), field('Вес атаки', num(D, 'battle.powerWeights.atk', { step: 0.5, min: 0 })), field('Вес защиты', num(D, 'battle.powerWeights.def', { step: 0.5, min: 0 })))),
    h('div', { class: 'card' }, h('b', {}, 'Скорость боя'),
      grid(field('Скорость x2 открывается после этапа', num(D, 'battle.speed.x2UnlockStage', { int: true, min: 0, max: 10 }), 'Тестовое условие. x4 пока недоступна (VIP).'))),
  );
}

// ---------------------------------------------------------------- Этапы

function viewStages(view) {
  const nameOf = (k) => (D.enemies.find((e) => e.key === k) || { name: k }).name;
  view.append(h('h2', {}, 'Этапы: награды и сила'),
    h('p', { style: 'color:var(--mut)' }, 'Награда выдаётся только за первую победу. Расстановка врагов по позициям будет в редакторе кампании.'),
    h('div', { class: 'card' }, h('table', {},
      h('tr', {}, ['№', 'Название', 'Сила врагов (×hp и атака)', 'Золото', 'Опыт героев', 'Враги'].map((t) => h('th', {}, t))),
      ...D.stages.map((s) => h('tr', {}, h('td', {}, s.n), h('td', {}, text(s, 'name')), h('td', {}, num(s, 'power', { step: 0.01, min: 0.05 })),
        h('td', {}, num(s, 'reward.gold', { int: true, min: 0 })), h('td', {}, num(s, 'reward.hero_exp', { int: true, min: 0 })),
        h('td', { style: 'font-size:12px;color:var(--mut)' }, s.enemies.filter(Boolean).map((e) => `${nameOf(e.key)} ур.${e.level}`).join(', ')))))));
}

// ---------------------------------------------------------------- Арена и камера

function drawArena(cv) {
  const B = D.arena.bounds, C = D.arena.camera;
  const ctx = cv.getContext('2d');
  const W = cv.width, H = cv.height;
  ctx.clearRect(0, 0, W, H);
  ctx.font = '12px system-ui';
  const depth = C.depth;
  const [cx, cy, cz] = C.position, [lx, ly, lz] = C.lookAt;
  // --- вид сверху (слева)
  const topW = W * 0.5 - 10;
  const sx = topW / 24, ox = topW / 2;                   // x мира: -12..12
  const zMin = -9, zMax = 18, sz = (H - 30) / (zMax - zMin);
  const X = (x) => ox + x * sx, Z = (z) => 22 + (z - zMin) * sz;
  ctx.fillStyle = '#9aa3b8'; ctx.fillText('Вид сверху', 6, 14);
  ctx.strokeStyle = '#e0a63a'; ctx.lineWidth = 2;
  ctx.strokeRect(X(B.xMin), Z(B.yMin * depth), (B.xMax - B.xMin) * sx, (B.yMax - B.yMin) * depth * sz);
  for (const [x, y, side] of [[-2, -1.2, 0], [-2, 1.2, 0], [-4, -2.4, 0], [-4, 0, 0], [-4, 2.4, 0], [2, -1.2, 1], [2, 1.2, 1], [4, -2.4, 1], [4, 0, 1], [4, 2.4, 1]]) {
    ctx.fillStyle = side ? '#e5645b' : '#5aa0ff'; ctx.beginPath(); ctx.arc(X(x), Z(y * depth), 4, 0, 7); ctx.fill();
  }
  // камера и конус обзора (горизонтальный угол)
  const dir = Math.atan2(lz - cz, lx - cx), half = (C.fov * Math.PI / 180) / 2, len = 14;
  ctx.fillStyle = 'rgba(224,166,58,.15)'; ctx.strokeStyle = '#e0a63a'; ctx.lineWidth = 1;
  ctx.beginPath(); ctx.moveTo(X(cx), Z(cz));
  ctx.lineTo(X(cx + len * Math.cos(dir - half)), Z(cz + len * Math.sin(dir - half)));
  ctx.lineTo(X(cx + len * Math.cos(dir + half)), Z(cz + len * Math.sin(dir + half))); ctx.closePath(); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#fff'; ctx.fillRect(X(cx) - 4, Z(cz) - 4, 8, 8); ctx.fillText('камера', X(cx) + 7, Z(cz) + 4);
  // --- вид сбоку (справа): горизонталь — глубина (z), вертикаль — высота (y)
  const ox2 = W * 0.5 + 10, sw = W * 0.5 - 20;
  const zr = zMax - zMin, s2 = sw / zr, gy = H - 24, sy = (H - 50) / 16;
  const Z2 = (z) => ox2 + (z - zMin) * s2, Y2 = (y) => gy - y * sy;
  ctx.fillStyle = '#9aa3b8'; ctx.fillText('Вид сбоку', ox2, 14);
  ctx.strokeStyle = '#555'; ctx.beginPath(); ctx.moveTo(ox2, gy); ctx.lineTo(ox2 + sw, gy); ctx.stroke();
  ctx.strokeStyle = '#e0a63a'; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(Z2(B.yMin * depth), gy); ctx.lineTo(Z2(B.yMax * depth), gy); ctx.stroke();
  const pitch = Math.atan2(cy - ly, cz - lz);               // угол вниз
  const aspect = 720 / 1280, vh = 2 * Math.atan(Math.tan(half) / aspect) / 2;
  ctx.lineWidth = 1; ctx.fillStyle = 'rgba(224,166,58,.15)';
  const edges = [pitch - vh, pitch + vh].map((p) => { const t = p <= 0.02 ? 40 : cy / Math.tan(p); return [cz - t, Math.max(0, cy - t * Math.tan(p))]; });
  ctx.beginPath(); ctx.moveTo(Z2(cz), Y2(cy)); edges.forEach(([z, y]) => ctx.lineTo(Z2(z), Y2(y))); ctx.closePath(); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#fff'; ctx.fillRect(Z2(cz) - 4, Y2(cy) - 4, 8, 8); ctx.fillText('камера', Z2(cz) + 7, Y2(cy));
  ctx.strokeStyle = '#fff'; ctx.setLineDash([4, 3]); ctx.beginPath(); ctx.moveTo(Z2(cz), Y2(cy)); ctx.lineTo(Z2(lz), Y2(ly)); ctx.stroke(); ctx.setLineDash([]);
  return { pitch: pitch * 180 / Math.PI, dist: Math.hypot(cx - lx, cy - ly, cz - lz) };
}

function viewArena(view) {
  const cv = h('canvas', { width: 640, height: 300 });
  const info = h('p', { style: 'color:var(--mut);font-size:13px' });
  const redraw = () => {
    const r = drawArena(cv);
    const visW = 2 * r.dist * Math.tan((D.arena.camera.fov * Math.PI / 180) / 2);
    info.textContent = `Угол камеры над землёй ≈ ${r.pitch.toFixed(0)}°, расстояние до точки взгляда ${r.dist.toFixed(1)}, ширина кадра в этой точке ≈ ${visW.toFixed(1)} при арене шириной ${(D.arena.bounds.xMax - D.arena.bounds.xMin).toFixed(1)}. Синие точки — стартовые позиции отряда, красные — врагов.`;
  };
  const cam = D.arena.camera;
  view.append(h('h2', {}, 'Арена и камера'),
    h('p', { style: 'color:var(--mut)' }, 'Схема ниже показывает черновик и не меняет сохранённую камеру. Точный вид в игре с моделями и фоном появится в предпросмотре (следующий этап); пока проверяйте на телефоне после «Сохранить».'),
    h('div', { class: 'card' }, cv, info),
    h('div', { class: 'card' }, h('b', {}, 'Камера'),
      grid(...['X', 'Y (высота)', 'Z (к игроку)'].map((l, i) => field('Позиция ' + l, num(cam, 'position.' + i, { step: 0.1, on: redraw }))),
        ...['X', 'Y', 'Z'].map((l, i) => field('Точка взгляда ' + l, num(cam, 'lookAt.' + i, { step: 0.1, on: redraw }))),
        field('Угол обзора по ширине, °', num(cam, 'fov', { step: 1, min: 20, max: 90, on: redraw }), '20–90, шире — герои мельче'),
        field('Растяжение арены по глубине', num(cam, 'depth', { step: 0.05, min: 0.2, on: redraw }), 'Только на экране, на сервере координаты прежние'))),
    h('div', { class: 'card' }, h('b', {}, 'Границы арены (за них бойцы не выходят)'),
      grid(field('X от', num(D, 'arena.bounds.xMin', { step: 0.1, on: redraw })), field('X до', num(D, 'arena.bounds.xMax', { step: 0.1, on: redraw })), field('Глубина от', num(D, 'arena.bounds.yMin', { step: 0.1, on: redraw })), field('Глубина до', num(D, 'arena.bounds.yMax', { step: 0.1, on: redraw })))),
  );
  redraw();
}

// ---------------------------------------------------------------- Обучение

function viewTutorial(view) {
  const steps = D.tutorial?.steps || [];
  view.append(h('h2', {}, 'Обучение'), h('p', { style: 'color:var(--mut)' }, 'Тексты шагов. Условия завершения и подсветка выбираются из каталога игры, их менять можно только через редактор JSON.'),
    ...steps.map((st, i) => h('div', { class: 'card' }, h('b', {}, `Шаг ${i + 1}`, h('span', { class: 'tag' }, st.id)),
      field('Текст', area(st, 'text', 4)), h('p', { style: 'color:var(--mut);font-size:12px' }, `Подсветка: ${(st.highlight || []).join(', ') || '—'} · завершается: ${st.done}`))));
}


// ---------------------------------------------------------------- Медиатека и 3D-просмотр

let MEDIA = [];
let VMOD = null;
const viewerModule = async () => (VMOD ||= await import('./viewer.js'));
async function loadMedia() { MEDIA = await api('media'); }
const mediaEntry = (name) => MEDIA.find((m) => m.name === name);
const safeName = (s) => { let n = String(s).replace(/\.glb$/i, '').replace(/[^A-Za-z0-9_-]+/g, '_').replace(/^_+|_+$/g, ''); if (!/^[A-Za-z]/.test(n)) n = 'M_' + n; return n.slice(0, 64) || 'Model'; };
const fmtMB = (b) => (b / 1048576).toFixed(1) + ' МБ';

async function blobUrl(sha) {
  const r = await fetch('api/media/file/' + sha, { headers: { authorization: 'Bearer ' + T } });
  if (!r.ok) throw new Error('Файл не получен (' + r.status + ')');
  return URL.createObjectURL(await r.blob());
}

async function uploadFile(file, { name, kind, note, activate }) {
  if (file.size > 40 * 1048576) throw new Error('Файл больше 40 МБ');
  const q = new URLSearchParams({ name, kind, filename: file.name, note: note || '' });
  if (activate !== undefined) q.set('activate', activate ? '1' : '0');
  const r = await fetch('api/media/upload?' + q, { method: 'POST', headers: { authorization: 'Bearer ' + T, 'content-type': 'application/octet-stream' }, body: file });
  const j = await r.json().catch(() => ({ message: 'Ответ не прочитан (' + r.status + ')' }));
  if (!r.ok) throw new Error(j.message || r.status);
  return j;
}

function pickFile() {
  return new Promise((resolve) => {
    const i = h('input', { type: 'file', accept: '.glb,model/gltf-binary', style: 'display:none' });
    i.addEventListener('change', () => { resolve(i.files[0] || null); i.remove(); });
    document.body.append(i);
    i.click();
  });
}

const SLOTS = [['idle', 'Стойка'], ['run', 'Бег'], ['attack_melee', 'Удар в ближнем бою'], ['attack_melee_strong', 'Сильный удар (умение)'], ['attack_ranged', 'Выстрел'], ['cast', 'Каст (обычный)'], ['cast_strong', 'Каст (сильный)'], ['hit', 'Получение удара'], ['death', 'Смерть']];
const DEFAULT_ANIMS = { idle: 'Idle', run: 'Running_A', attack_melee: '1H_Melee_Attack_Slice_Horizontal', attack_melee_strong: '2H_Melee_Attack_Spin', attack_ranged: '1H_Ranged_Shoot', cast: 'Spellcast_Shoot', cast_strong: 'Spellcast_Long', hit: 'Hit_A', death: 'Death_A' };

// Блок просмотра модели. unit — герой/враг (тогда есть выбор модели и назначение анимаций); без unit — просмотр записи медиатеки.
function modelBlock({ unit, fixedName }) {
  const root = h('div', {});
  const host = h('div', { style: 'width:100%' });
  const status = h('div', { style: 'color:var(--mut);font-size:13px;margin:6px 0' });
  const clipsBox = h('div', {});
  const slotsBox = h('div', {});
  const versBox = h('div', {});
  const toolsBox = h('div', { class: 'toolbar' });
  let viewer = null, shownName = null, shownVer = null, token = 0;
  const modelName = () => (unit ? unit.visual?.model : fixedName);

  async function ensureViewer() {
    if (viewer) return viewer;
    const mod = await viewerModule();
    viewer = mod.createViewer(host, { height: 340 });
    return viewer;
  }

  async function show(name, sha) {
    const my = ++token;
    clipsBox.replaceChildren(); versBox.replaceChildren();
    const e = mediaEntry(name);
    if (!name || !e) { status.textContent = name ? `Модели «${name}» нет в медиатеке: в игре используется вшитая в приложение (если есть). Загрузите файл, чтобы её видеть и менять.` : 'Модель не выбрана.'; drawSlots(); return; }
    if (e.kind !== 'model') { status.textContent = 'Это файл анимаций, а не модель.'; return; }
    const ver = sha ? e.versions.find((v) => v.sha === sha) : e.active;
    status.textContent = 'Загрузка модели…';
    try {
      const vw = await ensureViewer();
      if (!vw) { status.textContent = 'WebGL недоступен в этом браузере.'; return; }
      const url = await blobUrl(ver.sha);
      await vw.load(url);
      URL.revokeObjectURL(url);
      if (my !== token) return;
      shownName = name; shownVer = ver;
      if (unit) { vw.setScale(unit.visual?.scale || 1); vw.setYaw(unit.visual?.yaw || 0); vw.hideParts(unit.visual?.hide); }
      status.textContent = `${name} · версия ${ver.version}${ver.active ? ' (активна)' : ' (НЕ активна, игроки её не видят)'} · ${ver.meta.triangles} треугольников · костей ${ver.meta.boneCount} · анимаций ${ver.meta.clips.length} · ${fmtMB(ver.size)}`;
      drawClips(); drawSlots(); drawVersions(e);
    } catch (err) { status.textContent = 'Ошибка просмотра: ' + err.message; }
  }

  function drawClips() {
    clipsBox.replaceChildren(h('div', { style: 'color:var(--mut);font-size:13px;margin:6px 0' }, 'Анимации в модели (нажмите, чтобы посмотреть):'),
      ...viewer.clipKeys().map((k) => h('button', { class: 'sec chip', onclick: () => viewer.play(k, { loop: !/dead|death|die/i.test(k) }) }, k)),
      h('div', {}, h('button', { class: 'sec chip', onclick: () => viewer.setPlaying(!viewer.isPlaying()) }, 'Пауза / продолжить'),
        h('label', { style: 'font-size:13px;margin-left:6px' }, h('input', { type: 'checkbox', onchange: (e) => viewer.showSkeleton(e.target.checked) }), ' скелет'),
        h('label', { style: 'font-size:13px;margin-left:10px' }, 'скорость ', h('select', { style: 'width:auto;padding:3px', onchange: (e) => viewer.setSpeed(Number(e.target.value)) }, [0.25, 0.5, 1, 2].map((v) => h('option', { value: v, selected: v === 1 }, '×' + v))))));
  }

  // слоты: событие игры -> анимация модели (или из отдельного файла анимаций)
  function slotValue(slot) {
    const v = unit.visual || {};
    const file = v.anim_files?.[slot];
    const clip = v.anims?.[slot];
    return file ? `${file}::${clip ?? ''}` : (clip ?? '');
  }
  function setSlot(slot, val) {
    if (val === '') { acc(unit, 'visual.anims.' + slot).del(); acc(unit, 'visual.anim_files.' + slot).del(); }
    else if (val.includes('::')) { const [f, c] = val.split('::'); acc(unit, 'visual.anims.' + slot).set(c); acc(unit, 'visual.anim_files.' + slot).set(f); }
    else { acc(unit, 'visual.anims.' + slot).set(val); acc(unit, 'visual.anim_files.' + slot).del(); }
    for (const k of ['anims', 'anim_files']) if (unit.visual?.[k] && !Object.keys(unit.visual[k]).length) delete unit.visual[k];
    touch();
  }
  async function previewSlot(slot) {
    const val = slotValue(slot) || DEFAULT_ANIMS[slot];
    if (val.includes('::')) {
      const [f, c] = val.split('::');
      const fe = mediaEntry(f);
      if (fe && !viewer.clipKeys().some((k) => k === `${f}::${c}`)) { const url = await blobUrl(fe.active.sha); await viewer.addClips(url, f); URL.revokeObjectURL(url); }
      if (!viewer.play(`${f}::${c}`, { loop: slot !== 'death' })) toast('Нет такого клипа: ' + c, true);
    } else if (!viewer.play(val, { loop: slot !== 'death' })) toast(`В модели нет анимации «${val}»`, true);
  }
  function drawSlots() {
    slotsBox.replaceChildren();
    if (!unit || !shownVer) return;
    const own = shownVer.meta.clips.map((c) => c.name);
    const files = MEDIA.filter((m) => m.kind === 'animation');
    slotsBox.append(h('div', { style: 'color:var(--mut);font-size:13px;margin:10px 0 4px' }, 'Какая анимация играет на каждое событие боя (изменения попадают в черновик, действуют после «Сохранить»):'),
      ...SLOTS.map(([slot, label]) => {
        const sel = h('select', { onchange: (e) => setSlot(slot, e.target.value) },
          h('option', { value: '' }, 'По умолчанию (' + DEFAULT_ANIMS[slot] + ')'),
          h('optgroup', { label: 'Из модели' }, own.map((n) => h('option', { value: n }, n))),
          files.map((f) => h('optgroup', { label: 'Файл анимаций ' + f.name }, f.active.meta.clips.map((c) => h('option', { value: `${f.name}::${c.name}` }, c.name)))));
        sel.value = slotValue(slot);
        if (sel.value !== slotValue(slot)) { sel.append(h('option', { value: slotValue(slot) }, slotValue(slot) + ' (нет в модели)')); sel.value = slotValue(slot); }
        return h('div', { class: 'slot' }, h('span', {}, label), sel, h('button', { class: 'sec', onclick: () => previewSlot(slot) }, '▶'));
      }));
  }

  function drawVersions(e) {
    versBox.replaceChildren(h('div', { style: 'color:var(--mut);font-size:13px;margin:10px 0 4px' }, 'Версии файла (включение версии меняет модель у всех игроков при следующем входе):'),
      ...e.versions.map((v) => h('div', { class: 'vrow' }, h('b', {}, `v${v.version}${v.active ? ' ✓ активна' : ''}`), ' ', h('span', {}, fmtTime(v.created)), h('span', {}, fmtMB(v.size) + (v.source === 'bundled' ? ', вшита' : '')), h('div', { class: 'nt' }, [v.filename, v.note].filter(Boolean).join(' · ')),
        h('button', { class: 'sec', onclick: () => show(e.name, v.sha) }, 'Смотреть'),
        v.active ? null : h('button', { class: 'sec', onclick: async () => {
          if (!confirm(`Сделать версию ${v.version} активной для всех игроков?`)) return;
          try { await api('media/activate', { name: e.name, version: v.version }); await loadMedia(); toast('Версия включена'); show(e.name); } catch (er) { toast(er.message, true); }
        } }, 'Сделать активной'))));
  }

  async function uploadModelFlow() {
    const f = await pickFile();
    if (!f) return;
    const cur = modelName();
    const replaceable = cur && mediaEntry(cur)?.kind === 'model';
    const nameIn = h('input', { value: safeName(f.name) });
    const mode = h('select', {}, replaceable ? h('option', { value: 'replace' }, `Заменить «${cur}» (новая версия, сначала просмотр)`) : null, h('option', { value: 'new' }, 'Новая модель с именем:'));
    const err = h('div', { class: 'bad' });
    const m = modal([h('h3', {}, 'Загрузка модели'), h('p', { style: 'color:var(--mut);font-size:13px' }, `${f.name}, ${fmtMB(f.size)}`), field('Что сделать', mode), field('Имя новой модели', nameIn, 'Латиница, цифры, _ и -'), err,
      h('button', { onclick: async () => {
        err.textContent = '';
        const replace = mode.value === 'replace';
        const name = replace ? cur : nameIn.value.trim();
        try {
          const r = await uploadFile(f, { name, kind: 'model', note: 'из админки' });
          await loadMedia();
          m.remove();
          if (unit && !replace) { acc(unit, 'visual.model').set(name); touch(); }
          toast(replace ? `Версия ${r.version} загружена, не активна: посмотрите и включите` : 'Модель загружена');
          renderTools();
          show(name, r.sha);
        } catch (e) { err.textContent = e.message; }
      } }, 'Загрузить'), ' ', h('button', { class: 'sec', onclick: () => m.remove() }, 'Отмена')]);
  }

  async function addAnimFlow() {
    const f = await pickFile();
    if (!f) return;
    const base = safeName((modelName() || 'Anim') + '_' + f.name.replace(/\.glb$/i, ''));
    const nameIn = h('input', { value: base });
    const err = h('div', { class: 'bad' });
    const m = modal([h('h3', {}, 'Добавить анимации из файла'), h('p', { style: 'color:var(--mut);font-size:13px' }, `${f.name}, ${fmtMB(f.size)}. Скелет должен совпадать с моделью (те же имена костей).`), field('Имя файла анимаций в медиатеке', nameIn), err,
      h('button', { onclick: async () => {
        try {
          const r = await uploadFile(f, { name: nameIn.value.trim(), kind: 'animation', note: 'анимации из админки', activate: true });
          await loadMedia(); m.remove(); toast(`Добавлено анимаций: ${r.meta.clips.length}`);
          if (viewer) { const url = await blobUrl(r.sha); await viewer.addClips(url, r.name); URL.revokeObjectURL(url); }
          drawSlots();
        } catch (e) { err.textContent = e.message; }
      } }, 'Добавить'), ' ', h('button', { class: 'sec', onclick: () => m.remove() }, 'Отмена')]);
  }

  function renderTools() {
    toolsBox.replaceChildren();
    if (unit) {
      const names = MEDIA.filter((m) => m.kind === 'model').map((m) => m.name);
      const cur = modelName();
      const sel = h('select', { onchange: (e) => { acc(unit, 'visual.model').set(e.target.value); touch(); show(e.target.value); } },
        h('option', { value: '' }, '— модель не выбрана —'), (cur && !names.includes(cur) ? [cur] : []).concat(names).map((n) => h('option', { value: n }, n)));
      sel.value = cur || '';
      toolsBox.append(sel);
    }
    toolsBox.append(h('button', { class: 'sec', onclick: uploadModelFlow }, unit ? 'Загрузить / заменить модель…' : 'Загрузить новую версию…'), h('button', { class: 'sec', onclick: addAnimFlow }, 'Добавить анимации из файла…'));
  }

  root.append(toolsBox, host, status, clipsBox, slotsBox, versBox);
  (async () => { await loadMedia(); renderTools(); show(modelName()); })();
  root.dispose = () => { token++; viewer?.dispose(); viewer = null; };
  LIVE.push(root);
  return root;
}

async function viewMedia(view) {
  await loadMedia();
  const sel = UI.media && mediaEntry(UI.media) ? UI.media : (MEDIA.find((m) => m.kind === 'model') || {}).name;
  view.append(h('h2', {}, 'Медиатека: модели и анимации'),
    h('p', { style: 'color:var(--mut)' }, 'Все файлы моделей и анимаций. Замена файла создаёт новую версию, которую сначала можно посмотреть и только потом включить. Вшитые в приложение модели помечены. Файлы анимаций лежат отдельно и подключаются к героям в карточке героя.'),
    h('div', { class: 'card' }, ...MEDIA.map((m) => h('div', { class: 'item', onclick: () => { UI.media = m.name; render(); } },
      h('div', {}, h('b', {}, m.name), h('span', { class: 'tag' }, m.kind === 'model' ? 'модель' : 'анимации'), m.name === sel ? h('span', { class: 'tag' }, 'открыта') : null,
        h('div', { class: 'meta' }, `v${m.active.version} · ${fmtMB(m.active.size)} · ${m.active.meta.triangles} треуг. · анимаций ${m.active.meta.clips.length}${m.active.source === 'bundled' ? ' · вшита в приложение' : ''}`)),
      h('span', {}, '›')))));
  const e = sel && mediaEntry(sel);
  if (e && e.kind === 'model') view.append(h('div', { class: 'card' }, h('b', {}, e.name), modelBlock({ fixedName: e.name })));
  else if (e) view.append(h('div', { class: 'card' }, h('b', {}, e.name), h('table', {}, e.active.meta.clips.map((c) => h('tr', {}, h('td', {}, c.name), h('td', {}, c.duration + ' с'))))));
}

// ---------------------------------------------------------------- вход и запуск

async function showApp() {
  $('login').hidden = !!T;
  $('app').hidden = !T;
  if (!T) return;
  try { await loadContent(); } catch (e) { return; }
  render();
}

$('go').onclick = async () => {
  try { const j = await api('login', { login: $('l').value, password: $('p').value }); T = j.token; sessionStorage.setItem('t', T); showApp(); } catch (e) { $('lerr').textContent = e.message; }
};
$('p').onkeydown = (e) => { if (e.key === 'Enter') $('go').click(); };
$('out').onclick = () => { if (dirty() && !confirm('Есть несохранённые правки. Выйти?')) return; T = null; sessionStorage.removeItem('t'); D = null; showApp(); };
$('menu').onclick = () => $('nav').classList.toggle('open');
showApp();

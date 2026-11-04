// Мир, сезоны и оформление. Старый контент без этих блоков остаётся верным.
// Боевые числа сюда не входят: этап по-прежнему считается в battle.js.

export const KEYRE = /^[a-z][a-z0-9_]{1,31}$/;
const RARITIES = ['common', 'uncommon', 'rare', 'epic', 'legendary'];
const SEASON_KINDS = ['story', 'arena', 'event'];
const QUEST_KINDS = ['story', 'battle'];
const DISTRICT_KINDS = ['district', 'city'];
const HEX = /^#[0-9a-fA-F]{6}$/;
const FILE = /^[A-Za-z0-9_][A-Za-z0-9_.-]{0,80}$/;
const LIMIT = 400;

export function textOf(v, locale = 'ru') {
  if (typeof v === 'string') return v;
  if (v && typeof v === 'object') return String(v[locale] ?? v.ru ?? '');
  return '';
}

function loc(need, v, path, max) {
  if (typeof v === 'string') {
    need(v.trim().length > 0 && v.length <= max, `${path}: текст 1–${max} символов`);
    return;
  }
  need(v && typeof v === 'object' && !Array.isArray(v), `${path}: строка или тексты по языкам`);
  if (!v || typeof v !== 'object' || Array.isArray(v)) return;
  const keys = Object.keys(v);
  need(keys.length > 0 && keys.length <= 8, `${path}: нужен хотя бы один язык`);
  for (const k of keys) {
    need(/^[a-z]{2}$/.test(k), `${path}: код языка «${k}» — две буквы`);
    need(typeof v[k] === 'string' && v[k].length <= max, `${path}.${k}: текст до ${max} символов`);
  }
  need(typeof v.ru === 'string' && v.ru.trim().length > 0, `${path}: нужен русский текст (ru)`);
}

function optText(need, v, path, max) {
  if (v === undefined) return;
  loc(need, v, path, max);
}

function idList(need, arr, path) {
  need(Array.isArray(arr), `${path}: нужен список`);
  if (!Array.isArray(arr)) return [];
  need(arr.length <= LIMIT, `${path}: больше ${LIMIT} записей в одной версии. Полная карта подгружается частями, это ещё не сделано`);
  const ids = new Set();
  for (const x of arr) {
    need(x && typeof x === 'object', `${path}: запись должна быть объектом`);
    if (!x || typeof x !== 'object') continue;
    need(typeof x.id === 'string' && KEYRE.test(x.id), `${path}: id «${x.id}» — латиница в нижнем регистре, 2–32 символа`);
    if (typeof x.id === 'string') {
      need(!ids.has(x.id), `${path}: id ${x.id} повторяется`);
      ids.add(x.id);
    }
  }
  return arr.filter((x) => x && typeof x === 'object');
}

function unlockOkShape(need, unlock, path, stages, questIds) {
  need(typeof unlock === 'string', `${path}: нужно условие открытия`);
  if (unlock === 'always') return;
  const st = /^stage:(\d+)$/.exec(unlock || '');
  if (st) {
    need(stages.has(Number(st[1])), `${path}: нет этапа ${st[1]}`);
    return;
  }
  const q = /^quest:([a-z][a-z0-9_]{1,31})$/.exec(unlock || '');
  if (q) {
    need(questIds.has(q[1]), `${path}: нет задания ${q[1]}`);
    return;
  }
  need(false, `${path}: условие «${unlock}» не из каталога (always, stage:N, quest:id)`);
}

export function unlockPasses(unlock, { cleared, done }) {
  if (!unlock || unlock === 'always') return true;
  const st = /^stage:(\d+)$/.exec(unlock);
  if (st) return cleared.has(Number(st[1]));
  const q = /^quest:(.+)$/.exec(unlock);
  if (q) return done.has(q[1]);
  return false;
}

export function validateUi(c, need) {
  if (c.ui === undefined) return;
  const u = c.ui;
  need(u && typeof u === 'object', 'ui: нужен объект');
  if (!u || typeof u !== 'object') return;
  need(u.schema === 1, 'ui.schema: нужна версия 1');
  const colors = u.colors || {};
  for (const k of ['bg', 'panel', 'gold', 'magic', 'text', 'muted', 'danger']) {
    need(HEX.test(colors[k] || ''), `ui.colors.${k}: цвет #RRGGBB`);
  }
  need(Number.isInteger(u.frame?.width) && u.frame.width >= 1 && u.frame.width <= 4, 'ui.frame.width: целое 1–4');
  need(Number.isInteger(u.frame?.radius) && u.frame.radius >= 0 && u.frame.radius <= 24, 'ui.frame.radius: целое 0–24');
  for (const k of ['title', 'body', 'small']) {
    need(Number.isInteger(u.type?.[k]) && u.type[k] >= 12 && u.type[k] <= 48, `ui.type.${k}: целое 12–48`);
  }
}

export function validateUnitExtras(u, need) {
  if (u.prompt !== undefined) need(typeof u.prompt === 'string' && u.prompt.length <= 2000, `${u.key}: prompt длиннее 2000 символов`);
  if (u.rarity !== undefined) need(RARITIES.includes(u.rarity), `${u.key}: редкость ${u.rarity} не из списка`);
  if (u.faction !== undefined) need(typeof u.faction === 'string' && KEYRE.test(u.faction), `${u.key}: фракция задана неверно`);
}

export function validateWorld(c, need) {
  if (c.world === undefined) {
    for (const u of [...(c.heroes || []), ...(c.enemies || [])]) {
      if (u?.faction) need(false, `${u.key}: фракция требует блок world.factions`);
    }
    return;
  }
  const w = c.world;
  need(w && typeof w === 'object', 'world: нужен объект');
  if (!w || typeof w !== 'object') return;
  need(w.schema === 1, 'world.schema: нужна версия 1');
  need(w._demo === true || w._demo === false, 'world._demo: явно отметьте, демонстрация это или нет');
  const rep = w.republic;
  need(rep && typeof rep === 'object', 'world.republic: нужна запись республики');
  if (rep && typeof rep === 'object') {
    need(rep.id === 'bashkortostan', 'world.republic.id: в этой игре карта одна, id bashkortostan');
    loc(need, rep.name, 'world.republic.name', 80);
    loc(need, rep.fact, 'world.republic.fact', 1200);
    sources(need, rep.sources, 'world.republic.sources');
  }
  const proposals = w.proposals;
  need(proposals && typeof proposals === 'object', 'world.proposals: нужны непринятые варианты имён, отдельно от фактов');
  if (proposals && typeof proposals === 'object') {
    need(proposals.status === 'proposal' || proposals.status === 'approved', 'world.proposals.status: proposal или approved');
    for (const k of ['spiritNames', 'culprits', 'startDistricts']) {
      need(Array.isArray(proposals[k]) && proposals[k].length >= 1 && proposals[k].length <= 8, `world.proposals.${k}: от 1 до 8 вариантов`);
      for (const item of proposals[k] || []) loc(need, item, `world.proposals.${k}`, 200);
    }
    need(proposals.chosen === undefined, 'world.proposals.chosen: имя духа, виновник и стартовый район ещё нельзя закреплять');
  }

  const districts = idList(need, w.districts, 'world.districts');
  const places = idList(need, w.places, 'world.places');
  const states = idList(need, w.placeStates, 'world.placeStates');
  const seasons = idList(need, w.seasons, 'world.seasons');
  const chains = idList(need, w.chains, 'world.chains');
  const quests = idList(need, w.quests, 'world.quests');
  const scenes = idList(need, w.scenes, 'world.scenes');
  const factions = idList(need, w.factions, 'world.factions');
  const resources = idList(need, w.resources, 'world.resources');

  const dIds = new Set(districts.map((d) => d.id));
  const pIds = new Set(places.map((d) => d.id));
  const sIds = new Set(seasons.map((d) => d.id));
  const cIds = new Set(chains.map((d) => d.id));
  const qIds = new Set(quests.map((d) => d.id));
  const scIds = new Set(scenes.map((d) => d.id));
  const fIds = new Set(factions.map((d) => d.id));
  const stageNs = new Set((c.stages || []).map((s) => s.n));

  for (const d of districts) {
    loc(need, d.name, `район ${d.id}`, 80);
    need(DISTRICT_KINDS.includes(d.kind), `район ${d.id}: kind district или city`);
    loc(need, d.fact, `район ${d.id} fact`, 1200);
    optText(need, d.fiction, `район ${d.id} fiction`, 1200);
    sources(need, d.sources, `район ${d.id}`);
    need(Number.isInteger(d.order), `район ${d.id}: нужен порядок order`);
    optPrompt(need, d.prompt, `район ${d.id}`);
  }
  for (const p of places) {
    loc(need, p.name, `место ${p.id}`, 80);
    need(dIds.has(p.districtId), `место ${p.id}: нет района ${p.districtId}`);
    loc(need, p.fact, `место ${p.id} fact`, 1200);
    optText(need, p.fiction, `место ${p.id} fiction`, 1200);
    sources(need, p.sources, `место ${p.id}`);
    need(Number.isInteger(p.order), `место ${p.id}: нужен порядок order`);
    optPrompt(need, p.prompt, `место ${p.id}`);
    if (p.art !== undefined) {
      need(p.art && typeof p.art === 'object', `место ${p.id}: art должен быть объектом`);
      if (p.art && typeof p.art === 'object') {
        if (p.art.background) need(FILE.test(p.art.background), `место ${p.id}: файл фона назван неверно`);
        need(p.art.status === 'temporary' || p.art.status === 'final', `место ${p.id}: art.status temporary или final`);
        need(Array.isArray(p.art.need), `место ${p.id}: art.need — список недостающих файлов`);
      }
    }
  }
  const stateKey = new Set();
  for (const st of states) {
    loc(need, st.name, `состояние ${st.id}`, 80);
    need(pIds.has(st.placeId), `состояние ${st.id}: нет места ${st.placeId}`);
    need(sIds.has(st.seasonId), `состояние ${st.id}: нет сезона ${st.seasonId}`);
    const k = `${st.placeId}:${st.seasonId}`;
    need(!stateKey.has(k), `состояние ${st.id}: у места в одном сезоне уже есть состояние`);
    stateKey.add(k);
    optText(need, st.fiction, `состояние ${st.id} fiction`, 1200);
    optPrompt(need, st.prompt, `состояние ${st.id}`);
  }
  for (const s of seasons) {
    loc(need, s.name, `сезон ${s.id}`, 80);
    need(SEASON_KINDS.includes(s.kind), `сезон ${s.id}: kind story, arena или event`);
    need(s.forever === true || s.forever === false, `сезон ${s.id}: forever — да или нет`);
    if (s.kind === 'story') need(s.forever === true, `сезон ${s.id}: сюжетный сезон остаётся доступен навсегда`);
    if (s.kind !== 'story') need(s.forever === false, `сезон ${s.id}: временный сезон арены или события не помечайте вечным`);
    need(Number.isInteger(s.order), `сезон ${s.id}: нужен порядок order`);
    unlockOkShape(need, s.unlock, `сезон ${s.id}`, stageNs, qIds);
    optText(need, s.summary, `сезон ${s.id} summary`, 1200);
    optPrompt(need, s.prompt, `сезон ${s.id}`);
    if (s.reward !== undefined) need(false, `сезон ${s.id}: награда сезона не выдаётся отдельно от этапа`);
  }
  for (const ch of chains) {
    loc(need, ch.name, `цепочка ${ch.id}`, 80);
    need(sIds.has(ch.seasonId), `цепочка ${ch.id}: нет сезона ${ch.seasonId}`);
    need(pIds.has(ch.placeId), `цепочка ${ch.id}: нет места ${ch.placeId}`);
    need(Number.isInteger(ch.order), `цепочка ${ch.id}: нужен порядок order`);
    unlockOkShape(need, ch.unlock, `цепочка ${ch.id}`, stageNs, qIds);
    optPrompt(need, ch.prompt, `цепочка ${ch.id}`);
  }
  for (const q of quests) {
    loc(need, q.name, `задание ${q.id}`, 80);
    need(QUEST_KINDS.includes(q.kind), `задание ${q.id}: kind story или battle`);
    need(cIds.has(q.chainId), `задание ${q.id}: нет цепочки ${q.chainId}`);
    need(Number.isInteger(q.order), `задание ${q.id}: нужен порядок order`);
    unlockOkShape(need, q.unlock, `задание ${q.id}`, stageNs, qIds);
    need(q.unlock !== `quest:${q.id}`, `задание ${q.id}: нельзя открывать само себя`);
    optPrompt(need, q.prompt, `задание ${q.id}`);
    if (q.kind === 'story') {
      need(scIds.has(q.sceneId), `задание ${q.id}: нет сцены ${q.sceneId}`);
      need(q.stage === undefined, `задание ${q.id}: сюжетное задание не запускает бой`);
      need(q.reward === undefined, `задание ${q.id}: сюжетная сцена не выдаёт награду`);
    } else {
      need(stageNs.has(q.stage), `задание ${q.id}: нет боевого этапа ${q.stage}`);
      need(q.sceneId === undefined, `задание ${q.id}: боевой этап не смешивайте со сценой`);
    }
  }
  const seenQ = new Set();
  const cycle = (id, stack) => {
    if (stack.has(id)) { need(false, `задания зациклены вокруг ${id}`); return; }
    if (seenQ.has(id)) return;
    const q = quests.find((x) => x.id === id);
    const m = /^quest:([a-z][a-z0-9_]{1,31})$/.exec(q?.unlock || '');
    if (!m) { seenQ.add(id); return; }
    stack.add(id);
    cycle(m[1], stack);
    stack.delete(id);
    seenQ.add(id);
  };
  for (const q of quests) cycle(q.id, new Set());
  for (const sc of scenes) {
    loc(need, sc.name, `сцена ${sc.id}`, 80);
    need(Array.isArray(sc.lines) && sc.lines.length >= 1 && sc.lines.length <= 30, `сцена ${sc.id}: от 1 до 30 реплик`);
    for (const ln of sc.lines || []) {
      need(ln && typeof ln.who === 'string' && ln.who.length <= 40, `сцена ${sc.id}: who до 40 символов`);
      loc(need, ln?.text, `сцена ${sc.id}`, 800);
    }
    if (sc.reward !== undefined) need(false, `сцена ${sc.id}: сцена не выдаёт награду и не меняет бой`);
    optPrompt(need, sc.prompt, `сцена ${sc.id}`);
  }
  for (const f of factions) {
    loc(need, f.name, `фракция ${f.id}`, 40);
    optText(need, f.note, `фракция ${f.id}`, 400);
    optPrompt(need, f.prompt, `фракция ${f.id}`);
    if (f.mods !== undefined || f.bonus !== undefined) need(false, `фракция ${f.id}: это только подпись, без боевых бонусов`);
  }
  const knownRes = new Set(['gold', 'hero_exp']);
  for (const r of resources) {
    need(knownRes.has(r.id), `ресурс ${r.id}: к игре подключены только gold и hero_exp`);
    loc(need, r.name, `ресурс ${r.id}`, 40);
    optPrompt(need, r.prompt, `ресурс ${r.id}`);
  }
  for (const u of [...(c.heroes || []), ...(c.enemies || [])]) {
    if (u?.faction) need(fIds.has(u.faction), `${u.key}: нет фракции ${u.faction}`);
  }
}

function sources(need, list, path) {
  need(Array.isArray(list) && list.length >= 1 && list.length <= 6, `${path}: нужен список источников`);
  for (const s of list || []) need(typeof s === 'string' && s.startsWith('https://') && s.length <= 300, `${path}: источник должен быть ссылкой https`);
}

function optPrompt(need, v, path) {
  if (v === undefined) return;
  need(typeof v === 'string' && v.length <= 2000, `${path}: prompt — текст до 2000 символов`);
}

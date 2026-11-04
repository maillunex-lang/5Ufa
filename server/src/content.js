import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

export function validateContent(c) {
  const errs = [];
  const need = (cond, msg) => { if (!cond) errs.push(msg); };
  need(c && typeof c === 'object', 'content must be object');
  if (errs.length) return errs;
  const ROLES = ['tank', 'melee', 'ranged', 'mage', 'healer'];
  const TYPES = ['regular', 'cool'];
  const KINDS = ['basic', 'skill', 'main', 'passive'];
  const EFFECTS = ['single', 'aoe', 'heal'];
  const KEYRE = /^[a-z][a-z0-9_]{1,31}$/;
  const STAT_RANGES = { hp: [1, 1e6], atk: [0, 1e5], def: [0, 1e5], critChance: [0, 1], critPower: [1, 10], range: [0.5, 20], interval: [0.2, 10], speed: [0.5, 20] };
  const heroes = Array.isArray(c.heroes) ? c.heroes : [];
  const enemies = Array.isArray(c.enemies) ? c.enemies : [];
  need(heroes.length >= 5, 'нужно минимум 5 героев');
  need(heroes.filter((h) => h.starter === true).length === 5, 'стартовых героев (starter: true) должно быть ровно 5: их получает каждый новый аккаунт');
  const hk = new Set(heroes.map((h) => h.key));
  const ek = new Set(enemies.map((h) => h.key));
  need(hk.size === heroes.length, 'ключи героев не уникальны');
  need(ek.size === enemies.length, 'ключи врагов не уникальны');
  for (const k of hk) need(!ek.has(k), `ключ ${k} есть и у героя, и у врага`);
  const abilityIds = new Set();
  for (const u of [...heroes, ...enemies]) {
    need(typeof u.key === 'string' && KEYRE.test(u.key), `ключ «${u.key}»: латиница в нижнем регистре, цифры и _, 2–32 символа, первая буква`);
    need(typeof u.name === 'string' && u.name.trim().length > 0, `${u.key}: нужно имя`);
    if (heroes.includes(u)) {
      need(ROLES.includes(u.role), `${u.key}: неизвестная роль ${u.role}`);
      need(TYPES.includes(u.type), `${u.key}: неизвестный тип ${u.type} (regular или cool)`);
    }
    for (const [s, [lo, hi]] of Object.entries(STAT_RANGES)) {
      const v = u.stats?.[s];
      need(Number.isFinite(v), `${u.key}: нет характеристики ${s}`);
      if (Number.isFinite(v)) need(v >= lo && v <= hi, `${u.key}: ${s}=${v} вне допустимых ${lo}–${hi}`);
    }
    const ab = Array.isArray(u.abilities) ? u.abilities : [];
    need(ab.filter((a) => a.kind === 'basic').length === 1, `${u.key}: нужна ровно одна базовая атака`);
    need(ab.filter((a) => a.kind === 'main').length <= 1, `${u.key}: главная способность не больше одной`);
    for (const a of ab) {
      need(typeof a.id === 'string' && KEYRE.test(a.id), `${u.key}: id способности «${a.id}» некорректен`);
      need(!abilityIds.has(a.id), `id способности ${a.id} не уникален`);
      abilityIds.add(a.id);
      need(KINDS.includes(a.kind), `${a.id}: неизвестный вид ${a.kind}`);
      if (a.kind === 'passive') {
        for (const [k, m] of Object.entries(a.mods || {})) need(k in STAT_RANGES && Number.isFinite(m) && m > 0 && m <= 10, `${a.id}: пассивный бонус ${k}=${m} некорректен`);
      } else {
        need(Number.isFinite(a.mult) && a.mult > 0 && a.mult <= 50, `${a.id}: множитель mult должен быть больше 0`);
        if (a.kind !== 'basic') need(EFFECTS.includes(a.effect), `${a.id}: неизвестное действие ${a.effect}`);
        if (a.kind === 'skill') need(Number.isFinite(a.cooldown) && a.cooldown >= 0, `${a.id}: нужна перезарядка cooldown`);
      }
    }
  }
  need(c.stages?.length === 10, 'нужно 10 этапов');
  (c.stages || []).forEach((s) => {
    need(s.enemies?.length === 5, `этап ${s.n}: нужно 5 позиций`);
    for (const e of s.enemies || []) if (e) need(ek.has(e.key), `этап ${s.n}: неизвестный враг ${e.key}`);
    need(s.enemies?.some(Boolean), `этап ${s.n}: нет врагов`);
    for (const e of s.enemies || []) if (e) need(Number.isInteger(e.level) && e.level >= 1 && e.level <= 99, `этап ${s.n}: уровень врага ${e.level} вне 1–99`);
    need(Number.isFinite(s.power) && s.power > 0 && s.power <= 20, `этап ${s.n}: сила power должна быть больше 0`);
    need(typeof s.name === 'string' && s.name.trim().length > 0, `этап ${s.n}: нужно название`);
    for (const cur of ['gold', 'hero_exp']) need(Number.isInteger(s.reward?.[cur]) && s.reward[cur] >= 0, `этап ${s.n}: награда ${cur} — целое число не меньше 0`);
  });
  const B = c.arena?.bounds;
  need(B && [B.xMin, B.xMax, B.yMin, B.yMax].every(Number.isFinite) && B.xMin < B.xMax && B.yMin < B.yMax, 'арена: нужны границы bounds (xMin<xMax, yMin<yMax)');
  if (B) for (const x of [-4, -2, 2, 4]) need(x >= B.xMin && x <= B.xMax, `арена: стартовая позиция x=${x} вне границ`);
  if (B) need(B.yMin <= -2.4 && B.yMax >= 2.4, 'арена: стартовые позиции по глубине вне границ');
  const CAM = c.arena?.camera;
  const vec3 = (v) => Array.isArray(v) && v.length === 3 && v.every(Number.isFinite);
  need(CAM && vec3(CAM.position) && vec3(CAM.lookAt) && Number.isFinite(CAM.fov) && CAM.fov >= 20 && CAM.fov <= 90 && Number.isFinite(CAM.depth) && CAM.depth > 0,
    'арена: нужна камера camera {position[3], lookAt[3], fov 20–90, depth>0}');
  const DONE = /^(stage_cleared:\d+|hero_upgraded|button_ack)$/;
  const HL = /^(tab:[0-3]|stage:(\d+|next)|upgrade:first)$/;
  const ids = new Set();
  for (const st of c.tutorial?.steps || []) {
    need(typeof st.id === 'string' && st.id && !ids.has(st.id), 'обучение: id шага обязателен и уникален');
    ids.add(st.id);
    need(typeof st.text === 'string' && st.text.length > 0, `обучение ${st.id}: нужен текст`);
    need(DONE.test(st.done || ''), `обучение ${st.id}: неизвестное условие завершения ${st.done}`);
    for (const h of st.highlight || []) need(HL.test(h), `обучение ${st.id}: неизвестная подсветка ${h}`);
  }
  const P = c.progression || {};
  need(Number.isInteger(P.maxLevel) && P.maxLevel >= 1 && P.maxLevel <= 100, 'progression.maxLevel: целое 1–100');
  need(Number.isFinite(P.growth) && P.growth >= 0 && P.growth <= 5, 'progression.growth: 0–5');
  for (const cur of ['gold', 'hero_exp']) {
    need(Number.isInteger(P.upgradeCost?.[cur]) && P.upgradeCost[cur] >= 0, `progression.upgradeCost.${cur}: целое не меньше 0`);
    need(Number.isInteger(P.startBalance?.[cur]) && P.startBalance[cur] >= 0, `progression.startBalance.${cur}: целое не меньше 0`);
  }
  const BT = c.battle || {};
  need(Number.isFinite(BT.tick) && BT.tick >= 0.05 && BT.tick <= 1, 'battle.tick: 0,05–1 с');
  need(Number.isFinite(BT.timeLimit) && BT.timeLimit >= 10 && BT.timeLimit <= 600, 'battle.timeLimit: 10–600 с');
  for (const k of ['energyMax', 'energyOnAttack', 'energyOnDamaged']) need(Number.isFinite(BT[k]) && BT[k] >= 0, `battle.${k}: число не меньше 0`);
  need(Number.isFinite(BT.defConst) && BT.defConst > 0, 'battle.defConst: больше 0');
  return errs;
}

export function loadContentFile(path) {
  const text = readFileSync(path, 'utf8');
  const json = JSON.parse(text);
  const errs = validateContent(json);
  if (errs.length) throw new Error('Некорректный контент: ' + errs.join('; '));
  return { json: JSON.stringify(json), hash: createHash('sha256').update(JSON.stringify(json)).digest('hex') };
}


// Плоский список листьев контента: путь вида heroes[tank].stats.hp. Элементы массивов называются по key, id или n.
function flat(obj, path = '', out = {}) {
  if (Array.isArray(obj)) {
    obj.forEach((el, i) => {
      const id = el && typeof el === 'object' ? (el.key ?? el.id ?? el.n) : undefined;
      flat(el, `${path}[${id ?? i}]`, out);
    });
  } else if (obj && typeof obj === 'object') {
    for (const k of Object.keys(obj)) flat(obj[k], path ? `${path}.${k}` : k, out);
  } else out[path] = obj;
  return out;
}

const short = (v) => (v === undefined ? '(нет)' : String(JSON.stringify(v)).slice(0, 80));

// Список отличий между двумя версиями контента (для показа перед откатом и в журнале)
export function diffContent(a, b, limit = 300) {
  const fa = flat(a), fb = flat(b);
  const out = [];
  for (const p of new Set([...Object.keys(fa), ...Object.keys(fb)])) {
    if (JSON.stringify(fa[p]) !== JSON.stringify(fb[p])) out.push({ path: p, from: short(fa[p]), to: short(fb[p]) });
  }
  return { total: out.length, changes: out.slice(0, limit), truncated: out.length > limit };
}

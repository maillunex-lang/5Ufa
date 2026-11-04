import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

export function validateContent(c) {
  const errs = [];
  const need = (cond, msg) => { if (!cond) errs.push(msg); };
  need(c && typeof c === 'object', 'content must be object');
  if (errs.length) return errs;
  need(c.heroes?.length === 5, 'нужно ровно 5 героев в первой версии');
  const hk = new Set((c.heroes || []).map((h) => h.key));
  const ek = new Set((c.enemies || []).map((h) => h.key));
  need(hk.size === (c.heroes || []).length, 'ключи героев не уникальны');
  for (const u of [...(c.heroes || []), ...(c.enemies || [])]) {
    for (const s of ['hp', 'atk', 'def', 'critChance', 'critPower', 'range', 'interval', 'speed'])
      need(Number.isFinite(u.stats?.[s]), `${u.key}: нет характеристики ${s}`);
    need(u.abilities?.filter((a) => a.kind === 'basic').length === 1, `${u.key}: нужна ровно одна базовая атака`);
  }
  need(c.stages?.length === 10, 'нужно 10 этапов');
  (c.stages || []).forEach((s) => {
    need(s.enemies?.length === 5, `этап ${s.n}: нужно 5 позиций`);
    for (const e of s.enemies || []) if (e) need(ek.has(e.key), `этап ${s.n}: неизвестный враг ${e.key}`);
    need(s.enemies?.some(Boolean), `этап ${s.n}: нет врагов`);
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
  need(Number.isInteger(c.progression?.maxLevel) && c.progression.maxLevel >= 1, 'progression.maxLevel');
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

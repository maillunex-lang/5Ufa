import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync, renameSync, existsSync, readdirSync, readFileSync, statSync, copyFileSync } from 'node:fs';
import { join, basename } from 'node:path';
import { GameError } from './game.js';

// Медиатека: модели, анимации (GLB) и картинки (PNG/JPEG, в том числе фоны).
// Файлы хранятся по хешу содержимого и не меняются. Логическое имя стабильно:
// замена создаёт новую версию того же имени, старые версии остаются (откат).
// Контент ссылается на имя. GLB лежит как <sha>.glb (так уже хранятся файлы на сервере).

export const MAX_MEDIA_BYTES = 40 * 1024 * 1024;
export const MAX_IMAGE_BYTES = 8 * 1024 * 1024;
const MAX_IMAGE_SIDE = 4096;
const NAME_RE = /^[A-Za-z][A-Za-z0-9_-]{1,63}$/;
const KINDS = ['model', 'animation', 'image', 'background'];
const IMAGE_KINDS = ['image', 'background'];
const SHA_RE = /^[0-9a-f]{64}$/;
export const isSha = (s) => SHA_RE.test(s);

// Разбор GLB без загрузки в память графики: проверка формата и сводка для админки.
export function parseGlb(buf) {
  if (buf.length < 28 || buf.readUInt32LE(0) !== 0x46546c67) throw new GameError('bad_glb', 'Это не файл GLB (ожидается бинарный glTF)', 422);
  if (buf.readUInt32LE(4) !== 2) throw new GameError('bad_glb', 'Поддерживается только glTF версии 2', 422);
  if (buf.readUInt32LE(8) !== buf.length) throw new GameError('bad_glb', 'Файл повреждён: размер в заголовке не совпадает', 422);
  const jsonLen = buf.readUInt32LE(12);
  if (buf.readUInt32LE(16) !== 0x4e4f534a || 20 + jsonLen > buf.length) throw new GameError('bad_glb', 'Файл повреждён: нет блока JSON', 422);
  let j;
  try { j = JSON.parse(buf.toString('utf8', 20, 20 + jsonLen)); } catch { throw new GameError('bad_glb', 'Файл повреждён: JSON не читается', 422); }
  if (!j.asset || !String(j.asset.version).startsWith('2')) throw new GameError('bad_glb', 'Файл повреждён: нет описания asset', 422);
  const acc = j.accessors || [];
  const clips = (j.animations || []).map((a, i) => {
    let d = 0;
    for (const s of a.samplers || []) d = Math.max(d, acc[s.input]?.max?.[0] || 0);
    return { name: a.name || `animation_${i}`, duration: Math.round(d * 100) / 100 };
  });
  const joints = j.skins?.[0]?.joints || [];
  const bones = joints.map((n) => j.nodes?.[n]?.name || `bone_${n}`);
  let triangles = 0;
  for (const m of j.meshes || []) for (const p of m.primitives || []) {
    const mode = p.mode ?? 4;
    const n = p.indices !== undefined ? acc[p.indices]?.count : acc[p.attributes?.POSITION]?.count;
    if (n && mode === 4) triangles += Math.floor(n / 3);
  }
  if (bones.length > 300) throw new GameError('glb_too_complex', `Слишком много костей (${bones.length}), максимум 300`, 422);
  if (triangles > 200000) throw new GameError('glb_too_complex', `Слишком много треугольников (${triangles}), максимум 200 000`, 422);
  return { clips, bones, boneCount: bones.length, triangles, meshes: (j.meshes || []).length, images: (j.images || []).length, generator: j.asset.generator || '' };
}

function checkSide(width, height) {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1) throw new GameError('bad_image', 'У картинки нет размера', 422);
  if (width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE) throw new GameError('image_too_big', `Сторона картинки больше ${MAX_IMAGE_SIDE} пикселей`, 422);
}

// Заголовок PNG или JPEG, без распаковки пикселей.
export function parseImage(buf) {
  if (buf.length < 24) throw new GameError('bad_image', 'Файл слишком маленький для картинки', 422);
  if (buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47) {
    if (buf.toString('ascii', 12, 16) !== 'IHDR') throw new GameError('bad_image', 'PNG повреждён: нет заголовка', 422);
    const width = buf.readUInt32BE(16);
    const height = buf.readUInt32BE(20);
    checkSide(width, height);
    return { format: 'png', width, height };
  }
  if (buf[0] === 0xff && buf[1] === 0xd8) {
    let i = 2;
    while (i + 8 < buf.length) {
      if (buf[i] !== 0xff) break;
      while (buf[i] === 0xff && i < buf.length) i++;
      const marker = buf[i];
      i++;
      if (marker === 0xd9 || marker === 0xda) break;
      if (marker === 0x00 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) continue;
      if (i + 1 >= buf.length) break;
      const len = buf.readUInt16BE(i);
      if (len < 2 || i + len > buf.length) throw new GameError('bad_image', 'JPEG повреждён', 422);
      if (marker >= 0xc0 && marker <= 0xc2) {
        const height = buf.readUInt16BE(i + 3);
        const width = buf.readUInt16BE(i + 5);
        checkSide(width, height);
        return { format: 'jpeg', width, height };
      }
      i += len;
    }
    throw new GameError('bad_image', 'JPEG повреждён: нет размера кадра', 422);
  }
  throw new GameError('bad_image', 'Нужен файл PNG или JPEG', 422);
}

function extOf(kind, meta) {
  if (kind === 'model' || kind === 'animation') return '.glb';
  return meta?.format === 'jpeg' ? '.jpg' : '.png';
}

function labelOf(v) {
  if (typeof v === 'string') return v;
  if (v && typeof v === 'object') return String(v.ru || '');
  return '';
}

// Где имя файла упомянуто в текущем контенте. Фон места может быть именем или именем с расширением.
export function mediaUsages(content) {
  const out = {};
  const add = (name, item) => {
    if (typeof name !== 'string' || !name) return;
    const list = out[name] ||= [];
    const id = `${item.where}:${item.key}:${item.field}`;
    if (!list.some((x) => `${x.where}:${x.key}:${x.field}` === id)) list.push(item);
  };
  for (const where of ['heroes', 'enemies']) {
    for (const u of content?.[where] || []) {
      const who = where === 'heroes' ? 'герой' : 'враг';
      if (u?.visual?.model) add(u.visual.model, { where, key: u.key, label: `${who} «${u.name || u.key}»`, field: 'model' });
      for (const [slot, file] of Object.entries(u?.visual?.anim_files || {})) {
        if (file) add(file, { where, key: u.key, label: `${who} «${u.name || u.key}»`, field: `anim_files.${slot}` });
      }
    }
  }
  for (const p of content?.world?.places || []) {
    const bg = p?.art?.background;
    if (typeof bg !== 'string' || !bg) continue;
    const item = { where: 'place', key: p.id, label: `место «${labelOf(p.name) || p.id}»`, field: 'background' };
    add(bg, item);
    const stem = bg.replace(/\.(png|jpe?g)$/i, '');
    if (stem !== bg) add(stem, item);
  }
  return out;
}

export function createMedia({ db, dir, audit }) {
  mkdirSync(dir, { recursive: true });
  const q = (sql, ...p) => db.prepare(sql).all(...p);
  const one = (sql, ...p) => db.prepare(sql).get(...p);
  const run = (sql, ...p) => db.prepare(sql).run(...p);
  const filePath = (sha, ext = '.glb') => join(dir, sha + ext);

  const pub = (r) => r && ({ id: r.id, name: r.name, kind: r.kind, version: r.version, sha: r.sha, size: r.size, filename: r.filename, source: r.source, note: r.note, author: r.author, created: r.created, active: !!r.active, meta: r.meta ? JSON.parse(r.meta) : null, folder: r.folder || '', tags: r.tags || '', license: r.license || '', requirements: r.requirements || '', prompt: r.prompt || '' });

  function store(buf, sha, ext) {
    const target = filePath(sha, ext);
    if (!existsSync(target)) {
      const tmp = target + '.tmp';
      writeFileSync(tmp, buf);
      renameSync(tmp, target);
    }
  }

  // name: логическое имя; при повторной загрузке с тем же именем появляется новая версия.
  // Новая версия уже существующего имени по умолчанию НЕ активируется: сначала её смотрят, потом включают.
  // Первая загрузка нового имени активна сразу (его пока никто не использует).
  function upload({ name, kind = 'model', buf, filename = null, note = '', author = 'owner', source = 'upload', activate }) {
    if (!NAME_RE.test(name || '')) throw new GameError('bad_name', 'Имя: латиница, цифры, _ и -, 2–64 символа, первая буква', 400);
    if (!KINDS.includes(kind)) throw new GameError('bad_kind', 'Вид файла: model, animation, image или background', 400);
    if (buf.length > MAX_MEDIA_BYTES) throw new GameError('too_large', `Файл больше ${MAX_MEDIA_BYTES / 1048576} МБ`, 413);
    const image = IMAGE_KINDS.includes(kind);
    if (image && buf.length > MAX_IMAGE_BYTES) throw new GameError('too_large', `Картинка больше ${MAX_IMAGE_BYTES / 1048576} МБ`, 413);
    const meta = image ? parseImage(buf) : parseGlb(buf);
    if (kind === 'animation' && meta.clips.length === 0) throw new GameError('no_clips', 'В файле нет анимаций', 422);
    const sha = createHash('sha256').update(buf).digest('hex');
    const prev = one('SELECT kind, MAX(version) v FROM media WHERE name=?', name);
    if (prev?.v && prev.kind !== kind) throw new GameError('kind_mismatch', `Имя «${name}» уже занято файлом вида ${prev.kind}`, 409);
    const act = one('SELECT sha FROM media WHERE name=? AND active=1', name);
    if (act?.sha === sha) throw new GameError('no_changes', 'Такой же файл уже активен', 400);
    store(buf, sha, extOf(kind, meta));
    const version = (prev?.v || 0) + 1;
    const makeActive = activate ?? !prev?.v;
    if (version > 1 && one('SELECT 1 x FROM media WHERE name=? AND sha=?', name, sha)) throw new GameError('no_changes', 'Такая версия файла уже есть в истории', 400);
    if (makeActive) run('UPDATE media SET active=0 WHERE name=?', name);
    const card = one('SELECT folder, tags, license, requirements, prompt FROM media WHERE name=? ORDER BY version DESC LIMIT 1', name);
    run('INSERT INTO media(name,kind,version,sha,size,filename,source,note,author,created,active,meta,folder,tags,license,requirements,prompt) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      name, kind, version, sha, buf.length, filename ? basename(String(filename)).slice(0, 120) : null, source, String(note).slice(0, 300), author, Date.now(), makeActive ? 1 : 0, JSON.stringify(meta),
      card?.folder ?? null, card?.tags ?? null, card?.license ?? null, card?.requirements ?? null, card?.prompt ?? null);
    audit?.(author, 'media_upload', { name, kind, version, sha: sha.slice(0, 12), size: buf.length, source, active: makeActive });
    return pub(one('SELECT * FROM media WHERE name=? AND version=?', name, version));
  }

  function activate(name, version, author = 'owner') {
    const row = one('SELECT * FROM media WHERE name=? AND version=?', name, version);
    if (!row) throw new GameError('no_media', 'Версия файла не найдена', 404);
    if (row.active) throw new GameError('already_active', 'Эта версия уже активна', 400);
    const cur = one('SELECT version FROM media WHERE name=? AND active=1', name);
    run('UPDATE media SET active=0 WHERE name=?', name);
    run('UPDATE media SET active=1 WHERE name=? AND version=?', name, version);
    audit?.(author, 'media_activate', { name, from: cur?.version ?? null, to: version });
    return pub(one('SELECT * FROM media WHERE name=? AND version=?', name, version));
  }

  function list(content) {
    const used = content ? mediaUsages(content) : {};
    const names = q('SELECT DISTINCT name FROM media ORDER BY name').map((r) => r.name);
    return names.map((name) => {
      const versions = q('SELECT * FROM media WHERE name=? ORDER BY version DESC', name).map(pub);
      const active = versions.find((v) => v.active) || versions[0];
      return { name, kind: active.kind, folder: active.folder || '', tags: active.tags || '', used: used[name] || [], active, versions };
    });
  }

  function byHash(sha) {
    if (!isSha(sha)) return null;
    const row = one('SELECT kind, meta FROM media WHERE sha=? LIMIT 1', sha);
    if (!row) return null;
    const meta = row.meta ? JSON.parse(row.meta) : null;
    const p = filePath(sha, extOf(row.kind, meta));
    return existsSync(p) ? p : null;
  }

  // Что получает клиент: активные файлы. bundled: true — файл уже вшит в приложение, качать не нужно.
  // ext есть только у картинок: клиент кладёт файл с этим расширением.
  function manifest() {
    const out = {};
    for (const r of q('SELECT name,kind,version,sha,size,source,meta FROM media WHERE active=1')) {
      const meta = r.meta ? JSON.parse(r.meta) : null;
      const item = { kind: r.kind, version: r.version, sha: r.sha, size: r.size, bundled: r.source === 'bundled' && r.version === 1 };
      if (IMAGE_KINDS.includes(r.kind)) item.ext = extOf(r.kind, meta);
      out[r.name] = item;
    }
    return out;
  }

  // Папка, теги, лицензия, требования к файлу и промпт относятся к имени, а не к одной версии.
  function setCard(name, card = {}, author = 'owner') {
    if (!one('SELECT 1 x FROM media WHERE name=?', name)) throw new GameError('no_media', 'Файл не найден', 404);
    const folder = cleanFolder(card.folder);
    const tags = cleanTags(card.tags);
    const license = String(card.license || '').trim().slice(0, 300);
    const requirements = String(card.requirements || '').trim().slice(0, 500);
    const prompt = String(card.prompt || '').trim().slice(0, 2000);
    run('UPDATE media SET folder=?, tags=?, license=?, requirements=?, prompt=? WHERE name=?', folder, tags, license, requirements, prompt, name);
    audit?.(author, 'media_card', { name, folder, tags });
    return list().find((m) => m.name === name);
  }

  function cleanFolder(v) {
    const s = String(v || '').trim();
    if (!s) return null;
    if (s.length > 40 || /[\\/]|\.\./.test(s)) throw new GameError('bad_folder', 'Папка: до 40 символов, без / и без ..', 400);
    return s;
  }

  function cleanTags(v) {
    const parts = String(v || '').split(',').map((s) => s.trim()).filter(Boolean);
    if (parts.length > 12) throw new GameError('bad_tags', 'Тегов не больше 12', 400);
    for (const p of parts) if (p.length > 24) throw new GameError('bad_tags', 'Тег длиннее 24 символов', 400);
    return parts.length ? parts.join(', ') : null;
  }

  // Модели, вшитые в приложение, появляются в медиатеке при первом запуске (чтобы их можно было смотреть и заменять).
  function seed(seedDir) {
    if (!seedDir || !existsSync(seedDir)) return 0;
    let n = 0;
    for (const f of readdirSync(seedDir).filter((x) => x.toLowerCase().endsWith('.glb')).sort()) {
      const name = f.slice(0, -4);
      if (!NAME_RE.test(name) || one('SELECT 1 x FROM media WHERE name=?', name)) continue;
      const p = join(seedDir, f);
      if (statSync(p).size > MAX_MEDIA_BYTES) continue;
      try { upload({ name, kind: 'model', buf: readFileSync(p), filename: f, note: 'Вшито в приложение', author: 'система', source: 'bundled' }); n++; } catch { /* битый файл пропускаем */ }
    }
    return n;
  }

  // Картинки, вшитые в приложение (фоны). Имя — имя файла без расширения.
  function seedImages(seedDir) {
    if (!seedDir || !existsSync(seedDir)) return 0;
    const notes = {
      arena_mountains: 'Вшитый фон боя. Пока активна эта версия, игра берёт файл из приложения.',
      arena_wizardtower: 'Старый фон. В бою сейчас не используется.',
      cave_demo: 'Вшитый временный фон места. Это не фотография пещеры.',
    };
    const licenses = {
      arena_mountains: 'CC0, OpenGameArt, Oil painting landscapes',
      arena_wizardtower: 'CC0, OpenGameArt, Oil painting landscapes',
      cave_demo: 'Собственная иллюстрация проекта, не фотография',
    };
    let n = 0;
    for (const f of readdirSync(seedDir).filter((x) => /\.(png|jpe?g)$/i.test(x)).sort()) {
      const name = f.replace(/\.(png|jpe?g)$/i, '');
      if (!NAME_RE.test(name) || one('SELECT 1 x FROM media WHERE name=?', name)) continue;
      const p = join(seedDir, f);
      if (statSync(p).size > MAX_IMAGE_BYTES) continue;
      try {
        upload({ name, kind: 'background', buf: readFileSync(p), filename: f, note: notes[name] || 'Вшито в приложение', author: 'система', source: 'bundled' });
        if (licenses[name]) setCard(name, { license: licenses[name], requirements: 'PNG или JPEG, сторона до 4096, до 8 МБ' });
        n++;
      } catch { /* битый файл пропускаем */ }
    }
    return n;
  }

  return { upload, activate, list, byHash, manifest, seed, seedImages, filePath, setCard };
}

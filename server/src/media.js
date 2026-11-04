import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync, renameSync, existsSync, readdirSync, readFileSync, statSync, copyFileSync } from 'node:fs';
import { join, basename } from 'node:path';
import { GameError } from './game.js';

// Медиатека: модели и анимации (GLB). Файлы хранятся по хешу содержимого (data/media/<sha256>.glb), логическое имя
// стабильно: замена файла создаёт новую версию того же имени, старые версии остаются (откат). Контент ссылается на имя.

export const MAX_MEDIA_BYTES = 40 * 1024 * 1024;
const NAME_RE = /^[A-Za-z][A-Za-z0-9_-]{1,63}$/;
const KINDS = ['model', 'animation'];
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

export function createMedia({ db, dir, audit }) {
  mkdirSync(dir, { recursive: true });
  const q = (sql, ...p) => db.prepare(sql).all(...p);
  const one = (sql, ...p) => db.prepare(sql).get(...p);
  const run = (sql, ...p) => db.prepare(sql).run(...p);
  const filePath = (sha) => join(dir, sha + '.glb');

  const pub = (r) => r && ({ id: r.id, name: r.name, kind: r.kind, version: r.version, sha: r.sha, size: r.size, filename: r.filename, source: r.source, note: r.note, author: r.author, created: r.created, active: !!r.active, meta: r.meta ? JSON.parse(r.meta) : null, folder: r.folder || '', tags: r.tags || '', license: r.license || '', requirements: r.requirements || '', prompt: r.prompt || '' });

  function store(buf, sha) {
    const target = filePath(sha);
    if (!existsSync(target)) {
      const tmp = target + '.tmp';
      writeFileSync(tmp, buf);
      renameSync(tmp, target);
    }
  }

  // name: логическое имя; при повторной загрузке с тем же именем появляется новая версия (становится активной)
  // Новая версия уже существующего имени по умолчанию НЕ активируется: сначала её смотрят в админке, потом включают.
  // Первая загрузка нового имени активна сразу (его пока никто не использует).
  function upload({ name, kind = 'model', buf, filename = null, note = '', author = 'owner', source = 'upload', activate }) {
    if (!NAME_RE.test(name || '')) throw new GameError('bad_name', 'Имя: латиница, цифры, _ и -, 2–64 символа, первая буква', 400);
    if (!KINDS.includes(kind)) throw new GameError('bad_kind', 'Вид файла: model или animation', 400);
    if (buf.length > MAX_MEDIA_BYTES) throw new GameError('too_large', `Файл больше ${MAX_MEDIA_BYTES / 1048576} МБ`, 413);
    const meta = parseGlb(buf);
    if (kind === 'animation' && meta.clips.length === 0) throw new GameError('no_clips', 'В файле нет анимаций', 422);
    const sha = createHash('sha256').update(buf).digest('hex');
    const prev = one('SELECT kind, MAX(version) v FROM media WHERE name=?', name);
    if (prev?.v && prev.kind !== kind) throw new GameError('kind_mismatch', `Имя «${name}» уже занято файлом вида ${prev.kind}`, 409);
    const act = one('SELECT sha FROM media WHERE name=? AND active=1', name);
    if (act?.sha === sha) throw new GameError('no_changes', 'Такой же файл уже активен', 400);
    store(buf, sha);
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

  function list() {
    const names = q('SELECT DISTINCT name FROM media ORDER BY name').map((r) => r.name);
    return names.map((name) => {
      const versions = q('SELECT * FROM media WHERE name=? ORDER BY version DESC', name).map(pub);
      const active = versions.find((v) => v.active) || versions[0];
      return { name, kind: active.kind, folder: active.folder || '', tags: active.tags || '', active, versions };
    });
  }

  function byHash(sha) {
    if (!isSha(sha)) return null;
    const p = filePath(sha);
    return existsSync(p) && one('SELECT 1 x FROM media WHERE sha=?', sha) ? p : null;
  }

  // Что получает клиент: активные файлы. bundled: true — файл уже вшит в приложение, качать не нужно.
  function manifest() {
    const out = {};
    for (const r of q('SELECT name,kind,version,sha,size,source FROM media WHERE active=1')) {
      out[r.name] = { kind: r.kind, version: r.version, sha: r.sha, size: r.size, bundled: r.source === 'bundled' && r.version === 1 };
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

  return { upload, activate, list, byHash, manifest, seed, filePath, setCard };
}

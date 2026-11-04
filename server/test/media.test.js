import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { openDb } from '../src/db.js';
import { createMedia, parseGlb } from '../src/media.js';
import { createApp } from '../src/app.js';

const root = fileURLToPath(new URL('../../', import.meta.url));

// Минимальный корректный GLB: скелет из двух костей и одна анимация
function glb(extra = {}, clipName = 'Idle') {
  const json = {
    asset: { version: '2.0', generator: 'test' },
    nodes: [{ name: 'mixamorig:Hips' }, { name: 'mixamorig:Spine' }],
    skins: [{ joints: [0, 1] }],
    accessors: [{ count: 2, type: 'SCALAR', componentType: 5126, max: [1.5], min: [0] }, { count: 2, type: 'VEC3', componentType: 5126 }],
    animations: clipName ? [{ name: clipName, samplers: [{ input: 0, output: 1 }], channels: [] }] : [],
    ...extra,
  };
  let j = Buffer.from(JSON.stringify(json));
  j = Buffer.concat([j, Buffer.alloc((4 - (j.length % 4)) % 4, 0x20)]);
  const head = Buffer.alloc(20);
  head.writeUInt32LE(0x46546c67, 0); head.writeUInt32LE(2, 4); head.writeUInt32LE(20 + j.length, 8);
  head.writeUInt32LE(j.length, 12); head.writeUInt32LE(0x4e4f534a, 16);
  return Buffer.concat([head, j]);
}
const setup = () => {
  const db = openDb(':memory:');
  const audit = [];
  const media = createMedia({ db, dir: mkdtempSync(join(tmpdir(), '5ufa-media-')), audit: (a, b, c) => audit.push([a, b, c]) });
  return { db, media, audit };
};

test('разбор GLB: клипы, кости, отказ на неверных файлах', () => {
  const info = parseGlb(glb());
  assert.deepEqual(info.clips, [{ name: 'Idle', duration: 1.5 }]);
  assert.deepEqual(info.bones, ['mixamorig:Hips', 'mixamorig:Spine']);
  assert.throws(() => parseGlb(Buffer.from('это не glb, а просто текст, достаточно длинный')), (e) => e.code === 'bad_glb');
  const bad = glb(); bad.writeUInt32LE(2, 4 + 4); // размер в заголовке не совпадает
  assert.throws(() => parseGlb(bad), (e) => e.code === 'bad_glb');
  const v1 = glb(); v1.writeUInt32LE(1, 4);
  assert.throws(() => parseGlb(v1), (e) => e.code === 'bad_glb');
});

test('загрузка: версии одного имени, активна последняя, журнал, откат', () => {
  const { media, audit } = setup();
  const a = media.upload({ name: 'Hero_A', kind: 'model', buf: glb({}, 'Idle'), filename: 'a.glb', note: 'первая' });
  assert.equal(a.version, 1); assert.equal(a.active, true); assert.equal(a.meta.clips[0].name, 'Idle');
  const b = media.upload({ name: 'Hero_A', kind: 'model', buf: glb({}, 'Run'), note: 'замена' });
  assert.equal(b.version, 2);
  assert.equal(b.active, false); // замена не включается сама: сначала просмотр
  assert.equal(media.list()[0].active.version, 1);
  assert.equal(media.manifest().Hero_A.version, 1); // игроки пока получают прежнюю
  assert.throws(() => media.upload({ name: 'Hero_A', kind: 'model', buf: glb({}, 'Run') }), (e) => e.code === 'no_changes');
  const on = media.activate('Hero_A', 2);
  assert.equal(on.active, true);
  const l = media.list();
  assert.equal(l.length, 1);
  assert.equal(l[0].active.version, 2);
  assert.equal(l[0].versions.length, 2);
  assert.equal(l[0].versions.find((v) => v.version === 1).active, false);
  assert.equal(media.manifest().Hero_A.version, 2);
  const forced = media.upload({ name: 'Hero_A', kind: 'model', buf: glb({}, 'Third'), activate: true });
  assert.equal(forced.active, true);
  const back = media.activate('Hero_A', 1);
  assert.equal(back.active, true);
  assert.equal(media.list()[0].active.version, 1);
  assert.throws(() => media.activate('Hero_A', 1), (e) => e.code === 'already_active');
  assert.throws(() => media.activate('Hero_A', 9), (e) => e.code === 'no_media');
  assert.ok(audit.some(([, act]) => act === 'media_upload') && audit.some(([, act]) => act === 'media_activate'));
});

test('проверки при загрузке: имя, вид, анимации, занятость имени', () => {
  const { media } = setup();
  assert.throws(() => media.upload({ name: '../x', buf: glb() }), (e) => e.code === 'bad_name');
  assert.throws(() => media.upload({ name: 'A', buf: glb() }), (e) => e.code === 'bad_name');
  assert.throws(() => media.upload({ name: 'Ok_name', kind: 'video', buf: glb() }), (e) => e.code === 'bad_kind');
  assert.throws(() => media.upload({ name: 'No_clips', kind: 'animation', buf: glb({}, null) }), (e) => e.code === 'no_clips');
  media.upload({ name: 'Walk_set', kind: 'animation', buf: glb({}, 'Walk') });
  assert.throws(() => media.upload({ name: 'Walk_set', kind: 'model', buf: glb({}, 'Other') }), (e) => e.code === 'kind_mismatch');
});

test('манифест и посев вшитых моделей: один раз, замены не затираются', () => {
  const { media } = setup();
  const seed = mkdtempSync(join(tmpdir(), '5ufa-seed-'));
  writeFileSync(join(seed, 'Knight.glb'), glb({}, 'Idle'));
  writeFileSync(join(seed, 'Mage.glb'), glb({}, 'Spell'));
  writeFileSync(join(seed, 'readme.txt'), 'не модель');
  assert.equal(media.seed(seed), 2);
  assert.equal(media.seed(seed), 0); // повторно не дублирует
  let m = media.manifest();
  assert.equal(m.Knight.bundled, true);
  assert.equal(m.Knight.kind, 'model');
  media.upload({ name: 'Knight', kind: 'model', buf: glb({}, 'Different'), note: 'новая графика' });
  assert.equal(media.manifest().Knight.bundled, true); // пока не включена, игроки видят вшитую
  media.activate('Knight', 2);
  assert.equal(media.seed(seed), 0); // замена не откатывается посевом
  m = media.manifest();
  assert.equal(m.Knight.bundled, false); // клиенту нужно скачать
  assert.equal(m.Knight.version, 2);
  assert.equal(m.Mage.bundled, true);
});

test('HTTP: загрузка и замена модели из админки, выдача файла по хешу, манифест в контенте', async () => {
  const dir = mkdtempSync(join(tmpdir(), '5ufa-mh-'));
  const file = join(dir, 'game.json');
  copyFileSync(root + 'content/game.json', file);
  const app = createApp({ dataDir: join(dir, 'data'), contentPath: file, adminDir: root + 'admin', env: { ADMIN_PASSWORD: 'secret-pass-1', SEED_MEDIA_DIR: '' } });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const tok = async () => (await (await fetch(base + '/admin/api/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ login: 'owner', password: 'secret-pass-1' }) })).json()).token;
  try {
    const t = await tok();
    const auth = { authorization: 'Bearer ' + t };
    const up = (name, buf, extra = '') => fetch(`${base}/admin/api/media/upload?name=${name}&kind=model&filename=x.glb${extra}`, { method: 'POST', headers: { ...auth, 'content-type': 'application/octet-stream' }, body: buf });
    assert.equal((await fetch(`${base}/admin/api/media/upload?name=Hero_B`, { method: 'POST', body: glb() })).status, 401); // без входа нельзя
    const buf = glb({}, 'Idle');
    const r1 = await up('Hero_B', buf, '&note=%D0%BF%D1%80%D0%BE%D0%B1%D0%B0');
    assert.equal(r1.status, 200);
    const j1 = await r1.json();
    const sha = createHash('sha256').update(buf).digest('hex');
    assert.equal(j1.sha, sha);
    assert.equal(j1.note, 'проба');
    // неверный файл
    const bad = await up('Hero_C', Buffer.from('не glb не glb не glb не glb не glb'));
    assert.equal(bad.status, 422);
    assert.equal((await bad.json()).error, 'bad_glb');
    // слишком большой
    const big = await up('Hero_D', Buffer.alloc(41 * 1024 * 1024));
    assert.equal(big.status, 413);
    // замена (новая версия) и список
    const r2 = await up('Hero_B', glb({}, 'Run'));
    const j2 = await r2.json();
    assert.equal(j2.version, 2);
    assert.equal(j2.active, false);
    const list = await (await fetch(base + '/admin/api/media', { headers: auth })).json();
    assert.equal(list.length, 1);
    assert.equal(list[0].versions.length, 2);
    // откат версии
    const actFn = (version) => fetch(base + '/admin/api/media/activate', { method: 'POST', headers: { ...auth, 'content-type': 'application/json' }, body: JSON.stringify({ name: 'Hero_B', version }) });
    assert.equal((await actFn(1)).status, 400); // версия 1 уже активна
    assert.equal((await actFn(2)).status, 200); // включили замену
    assert.equal((await actFn(1)).status, 200); // и откатили
    // файл: админу и публично по хешу (с кэшем), чужой хеш и мусор — 404
    const pubFile = await fetch(`${base}/api/media/${sha}`);
    assert.equal(pubFile.status, 200);
    assert.match(pubFile.headers.get('cache-control'), /immutable/);
    assert.equal(Buffer.from(await pubFile.arrayBuffer()).equals(buf), true);
    assert.equal((await fetch(`${base}/admin/api/media/file/${sha}`, { headers: auth })).status, 200);
    assert.equal((await fetch(`${base}/admin/api/media/file/${sha}`)).status, 401);
    assert.equal((await fetch(`${base}/api/media/${'0'.repeat(64)}`)).status, 404);
    assert.equal((await fetch(`${base}/api/media/..%2f..%2fetc%2fpasswd`)).status, 401); // не хеш: идёт как обычный закрытый метод
    // манифест в контенте для клиента
    const guest = await (await fetch(base + '/api/guest', { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}' })).json();
    const content = await (await fetch(base + '/api/content', { headers: { authorization: 'Bearer ' + guest.token } })).json();
    assert.equal(content.media.Hero_B.sha, sha);
    assert.equal(content.media.Hero_B.version, 1);
    assert.equal(content.media.Hero_B.bundled, false);
  } finally { app.close(); }
});

test('реальная модель из репозитория разбирается: скелет и анимации', () => {
  const info = parseGlb(readFileSync(root + 'client/assets/models/Priest.glb'));
  assert.ok(info.clips.some((c) => c.name === 'Charged_Spell_Cast'));
  assert.ok(info.bones.includes('mixamorig:RightHand'));
  assert.ok(info.triangles > 5000 && info.triangles < 20000);
});

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, copyFileSync, readFileSync, unlinkSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { openDb } from '../src/db.js';
import { createMedia, parseGlb, parseImage, mediaUsages } from '../src/media.js';
import { createGame } from '../src/game.js';
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

function png(w, h) {
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8;
  const len = Buffer.alloc(4);
  len.writeUInt32BE(ihdr.length);
  return Buffer.concat([sig, len, Buffer.from('IHDR'), ihdr, Buffer.alloc(4), Buffer.from([0, 0, 0, 0, 73, 69, 78, 68, 0, 0, 0, 0])]);
}

function jpeg(w, h) {
  const sof = Buffer.alloc(19);
  sof[0] = 0xff; sof[1] = 0xc0;
  sof.writeUInt16BE(17, 2);
  sof[4] = 8;
  sof.writeUInt16BE(h, 5);
  sof.writeUInt16BE(w, 7);
  sof[9] = 3;
  return Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 0x4a, 0x46, 0x49, 0x46, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]), sof, Buffer.from([0xff, 0xd9])]);
}

test('картинки: PNG и JPEG, отказ на мусоре и на слишком большой стороне', () => {
  assert.deepEqual(parseImage(png(32, 48)), { format: 'png', width: 32, height: 48 });
  assert.deepEqual(parseImage(jpeg(20, 10)), { format: 'jpeg', width: 20, height: 10 });
  const cave = parseImage(readFileSync(root + 'client/assets/backgrounds/cave_demo.jpg'));
  assert.equal(cave.format, 'jpeg');
  assert.ok(cave.width >= 64 && cave.height >= 64);
  assert.throws(() => parseImage(Buffer.from('не картинка, но достаточно длинная строка')), (e) => e.code === 'bad_image');
  assert.throws(() => parseImage(png(5000, 10)), (e) => e.code === 'image_too_big');
});

test('загрузка фона: версии, расширение, где используется, посев', () => {
  const { media } = setup();
  const a = media.upload({ name: 'cave_demo', kind: 'background', buf: jpeg(8, 8), filename: 'cave_demo.jpg' });
  assert.equal(a.active, true);
  assert.equal(a.meta.format, 'jpeg');
  assert.equal(media.manifest().cave_demo.ext, '.jpg');
  assert.ok(media.byHash(a.sha).endsWith('.jpg'));
  const b = media.upload({ name: 'cave_demo', kind: 'background', buf: png(8, 8) });
  assert.equal(b.active, false);
  assert.equal(media.manifest().cave_demo.ext, '.jpg');
  media.activate('cave_demo', 2);
  assert.equal(media.manifest().cave_demo.ext, '.png');
  assert.throws(() => media.upload({ name: 'cave_demo', kind: 'model', buf: glb() }), (e) => e.code === 'kind_mismatch');
  assert.throws(() => media.upload({ name: 'big_pic', kind: 'image', buf: Buffer.alloc(8 * 1024 * 1024 + 1) }), (e) => e.code === 'too_large');
  const used = media.list({
    heroes: [{ key: 'tank', name: 'Танк', visual: { model: 'Knight', anim_files: { run: 'RunSet' } } }],
    enemies: [],
    world: { places: [{ id: 'shulgan', name: { ru: 'Пещера' }, art: { background: 'cave_demo.jpg' } }] },
  });
  assert.deepEqual(used.find((m) => m.name === 'cave_demo').used.map((x) => x.key), ['shulgan']);
  const map = mediaUsages({ heroes: [{ key: 'tank', name: 'Танк', visual: { model: 'Knight' } }], world: { places: [] } });
  assert.equal(map.Knight[0].where, 'heroes');
  const seed = mkdtempSync(join(tmpdir(), '5ufa-img-'));
  writeFileSync(join(seed, 'cave_demo.jpg'), jpeg(4, 4));
  writeFileSync(join(seed, 'note.txt'), 'нет');
  assert.equal(media.seedImages(seed), 0); // имя уже есть, замену не затирает
  const fresh = setup().media;
  assert.equal(fresh.seedImages(seed), 1);
  assert.equal(fresh.manifest().cave_demo.bundled, true);
  assert.equal(fresh.seedImages(seed), 0);
});

test('HTTP: картинка отдаётся как PNG, в списке есть «где используется»', async () => {
  const dir = mkdtempSync(join(tmpdir(), '5ufa-imgh-'));
  const file = join(dir, 'game.json');
  copyFileSync(root + 'content/game.json', file);
  const app = createApp({ dataDir: join(dir, 'data'), contentPath: file, adminDir: root + 'admin', env: { ADMIN_PASSWORD: 'secret-pass-1', SEED_MEDIA_DIR: '', SEED_IMAGE_DIR: '' } });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${app.server.address().port}`;
  try {
    const t = (await (await fetch(base + '/admin/api/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ login: 'owner', password: 'secret-pass-1' }) })).json()).token;
    const buf = png(16, 16);
    const up = await fetch(base + '/admin/api/media/upload?name=Knight&kind=model&filename=x.glb', { method: 'POST', headers: { authorization: 'Bearer ' + t, 'content-type': 'application/octet-stream' }, body: glb() });
    assert.equal(up.status, 200);
    const pic = await fetch(base + '/admin/api/media/upload?name=Poster&kind=image&filename=p.png', { method: 'POST', headers: { authorization: 'Bearer ' + t, 'content-type': 'application/octet-stream' }, body: buf });
    assert.equal(pic.status, 200);
    const body = await pic.json();
    const got = await fetch(base + '/api/media/' + body.sha);
    assert.equal(got.status, 200);
    assert.equal(got.headers.get('content-type'), 'image/png');
    const list = await (await fetch(base + '/admin/api/media', { headers: { authorization: 'Bearer ' + t } })).json();
    const knight = list.find((m) => m.name === 'Knight');
    assert.ok(knight.used.some((u) => u.key === 'tank' && u.field === 'model'));
    assert.deepEqual(list.find((m) => m.name === 'Poster').used, []);
  } finally { app.close(); }
});

test('бой хранит версии ресурсов на момент старта', () => {
  const dir = mkdtempSync(join(tmpdir(), '5ufa-pin-'));
  const file = join(dir, 'game.json');
  copyFileSync(root + 'content/game.json', file);
  const db = openDb(join(dir, 'game.db'));
  const game = createGame(db, { contentPath: file });
  const media = createMedia({ db, dir: join(dir, 'media') });
  const v1 = media.upload({ name: 'Knight', kind: 'model', buf: glb({}, 'Idle'), filename: 'a.glb' });
  const acc = game.guest().accountId;
  const b1 = game.startBattle(acc, 1, { seed: 1, media: media.manifest() });
  assert.equal(b1.media.Knight.sha, v1.sha);
  assert.equal(b1.media.Knight.version, 1);
  const v2 = media.upload({ name: 'Knight', kind: 'model', buf: glb({}, 'Run'), filename: 'b.glb' });
  media.activate('Knight', v2.version);
  assert.equal(media.manifest().Knight.sha, v2.sha);
  const again = game.getBattle(acc, b1.battleId);
  assert.equal(again.media.Knight.sha, v1.sha);
  assert.equal(again.media.Knight.version, 1);
  const b2 = game.startBattle(acc, 1, { seed: 2, media: media.manifest() });
  assert.equal(b2.media.Knight.sha, v2.sha);
  const plain = game.startBattle(acc, 1, { seed: 3 });
  assert.equal(plain.media, null);
  assert.equal(game.getBattle(acc, plain.battleId).media, null);
});

test('бэкап копирует файлы медиатеки и не затирает копию', () => {
  const dir = mkdtempSync(join(tmpdir(), '5ufa-bak-'));
  const file = join(dir, 'game.json');
  copyFileSync(root + 'content/game.json', file);
  const dataDir = join(dir, 'data');
  const app = createApp({ dataDir, contentPath: file, adminDir: root + 'admin', env: { ADMIN_PASSWORD: 'secret-pass-1', SEED_MEDIA_DIR: join(dir, 'no-models'), SEED_IMAGE_DIR: join(dir, 'no-images'), RELEASES_DISABLED: '1' } });
  try {
    const model = app.media.upload({ name: 'Hero_A', kind: 'model', buf: glb(), filename: 'a.glb', author: 'test' });
    const pic = app.media.upload({ name: 'Poster', kind: 'image', buf: png(4, 4), filename: 'p.png', author: 'test' });
    writeFileSync(join(dataDir, 'media', 'notes.txt'), 'не файл медиатеки');
    const first = app.backup('manual');
    assert.match(first.name, /-manual\.db$/);
    assert.equal(first.mediaCopied, 2);
    const modelCopy = join(dataDir, 'backups', 'media', `${model.sha}.glb`);
    const picCopy = join(dataDir, 'backups', 'media', `${pic.sha}.png`);
    const modelBytes = readFileSync(join(dataDir, 'media', `${model.sha}.glb`));
    assert.deepEqual(readFileSync(modelCopy), modelBytes);
    assert.ok(existsSync(picCopy));
    assert.equal(existsSync(join(dataDir, 'backups', 'media', 'notes.txt')), false);
    unlinkSync(join(dataDir, 'media', `${model.sha}.glb`));
    const second = app.backup('manual');
    assert.equal(second.mediaCopied, 0);
    assert.deepEqual(readFileSync(modelCopy), modelBytes);
  } finally { app.close(); }
});

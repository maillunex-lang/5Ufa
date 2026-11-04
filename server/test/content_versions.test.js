import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, copyFileSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDb } from '../src/db.js';
import { createGame } from '../src/game.js';
import { createApp } from '../src/app.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
const SRC = root + 'content/game.json';

function setup() {
  const dir = mkdtempSync(join(tmpdir(), '5ufa-cv-'));
  const file = join(dir, 'game.json');
  copyFileSync(SRC, file);
  const db = openDb(':memory:');
  const game = createGame(db, { contentPath: file });
  return { dir, file, db, game };
}
const clone = (o) => JSON.parse(JSON.stringify(o));
const edit = (game, fn) => { const c = clone(game.getVersion(game.currentVersionId()).content); fn(c); return c; };

test('первый запуск: версия 1 из файла, записана в журнал', () => {
  const { game, db } = setup();
  assert.equal(game.currentVersionId(), 1);
  const v = game.listVersions();
  assert.equal(v.length, 1);
  assert.equal(v[0].source, 'file');
  assert.equal(v[0].active, true);
  assert.equal(db.prepare("SELECT COUNT(*) n FROM audit WHERE action='content_file_import'").get().n, 1);
});

test('правка из админки: новая версия, журнал, список отличий', () => {
  const { game, db } = setup();
  const c = edit(game, (x) => { x.arena.camera.fov = 48; x.heroes[0].stats.hp = 1500; });
  const r = game.publishContent(c, { author: 'owner', note: 'камера и танк', baseVersion: 1 });
  assert.equal(r.version, 2);
  assert.equal(r.changes, 2);
  assert.equal(game.currentVersionId(), 2);
  assert.equal(game.getContent().arena.camera.fov, 48);
  const d = game.diffVersions(1, 2);
  assert.equal(d.total, 2);
  assert.ok(d.changes.some((x) => x.path === 'arena.camera.fov' && x.from === '56' && x.to === '48'));
  assert.ok(d.changes.some((x) => x.path === 'heroes[tank].stats.hp'));
  const a = db.prepare("SELECT actor, detail FROM audit WHERE action='content_save'").get();
  assert.equal(a.actor, 'owner');
  assert.equal(JSON.parse(a.detail).note, 'камера и танк');
  const v = game.listVersions();
  assert.equal(v[0].source, 'admin');
  assert.equal(v[0].parent, 1);
});

test('неверный контент не записывается, причины возвращаются', () => {
  const { game, db } = setup();
  const c = edit(game, (x) => { x.arena.camera.fov = 5; x.stages.pop(); });
  try { game.publishContent(c, { baseVersion: 1 }); assert.fail('должна быть ошибка'); } catch (e) {
    assert.equal(e.code, 'invalid_content');
    assert.equal(e.status, 422);
    assert.ok(e.details.length >= 2);
  }
  assert.equal(game.currentVersionId(), 1);
  assert.equal(db.prepare("SELECT COUNT(*) n FROM audit WHERE action='content_save'").get().n, 0);
});

test('одинаковое содержимое и устаревшая базовая версия отклоняются', () => {
  const { game } = setup();
  assert.throws(() => game.publishContent(edit(game, () => {}), { baseVersion: 1 }), (e) => e.code === 'no_changes');
  game.publishContent(edit(game, (x) => { x.arena.camera.depth = 1.5; }), { baseVersion: 1 });
  assert.throws(() => game.publishContent(edit(game, (x) => { x.arena.camera.depth = 1.6; }), { baseVersion: 1 }), (e) => e.code === 'version_conflict' && e.status === 409);
  assert.equal(game.currentVersionId(), 2);
});

test('идущий бой остаётся на своей версии, новый бой берёт свежую', () => {
  const { game } = setup();
  const acc = game.authenticate(game.guest().token);
  const b1 = game.startBattle(acc, 1, { seed: 1 });
  assert.equal(b1.contentVersion, 1);
  game.publishContent(edit(game, (x) => { x.stages[0].reward.gold = 999; }), { baseVersion: 1 });
  assert.equal(game.getBattle(acc, b1.battleId).contentVersion, 1);
  const b2 = game.startBattle(acc, 1, { seed: 2 });
  assert.equal(b2.contentVersion, 2);
});

test('откат создаёт новую версию со старым содержимым и не трогает аккаунты', () => {
  const { game, db } = setup();
  const acc = game.authenticate(game.guest().token);
  const goldBefore = game.balances(acc).gold;
  game.publishContent(edit(game, (x) => { x.progression.upgradeCost.gold = 777; }), { baseVersion: 1 });
  assert.equal(game.getContent().progression.upgradeCost.gold, 777);
  const r = game.rollbackTo(1, { author: 'owner' });
  assert.equal(r.version, 3);
  assert.equal(r.restoredFrom, 1);
  assert.equal(game.getContent().progression.upgradeCost.gold, 40);
  assert.equal(game.listVersions().length, 3); // история не переписывается
  assert.equal(game.listVersions()[0].source, 'rollback');
  assert.equal(game.balances(acc).gold, goldBefore);
  assert.equal(db.prepare("SELECT COUNT(*) n FROM audit WHERE action='content_rollback'").get().n, 1);
  assert.throws(() => game.rollbackTo(3), (e) => e.code === 'already_current');
  assert.throws(() => game.rollbackTo(99), (e) => e.code === 'no_version');
});

test('нельзя убрать героя, которым владеют игроки', () => {
  const { game } = setup();
  game.guest();
  const c = edit(game, (x) => { x.heroes = x.heroes.filter((h) => h.key !== 'archer'); });
  // валидатор требует 5 героев, поэтому подменяем героя ключом, а не просто удаляем
  const c2 = edit(game, (x) => { x.heroes.find((h) => h.key === 'archer').key = 'archer2'; });
  assert.throws(() => game.publishContent(c, { baseVersion: 1 }), (e) => e.code === 'invalid_content');
  assert.throws(() => game.publishContent(c2, { baseVersion: 1 }), (e) => e.code === 'hero_in_use' && e.status === 409);
  assert.equal(game.currentVersionId(), 1);
});

test('файл-«зерно»: без изменений файла правки админки не затираются, при изменении файла появляется новая версия', () => {
  const { game, file } = setup();
  game.publishContent(edit(game, (x) => { x.arena.camera.depth = 2.2; }), { baseVersion: 1 });
  // повторный «деплой» с тем же файлом
  const r1 = game.syncContentFromFile();
  assert.equal(r1.changed, false);
  assert.equal(game.getContent().arena.camera.depth, 2.2);
  // изменили сам файл
  const f = JSON.parse(readFileSync(file, 'utf8'));
  f.progression.upgradeCost.gold = 55;
  writeFileSync(file, JSON.stringify(f));
  const r2 = game.syncContentFromFile();
  assert.equal(r2.changed, true);
  assert.equal(game.getContent().progression.upgradeCost.gold, 55);
  assert.equal(game.listVersions()[0].source, 'file');
  // принудительный повтор того же файла новой версии не создаёт, если содержимое совпадает с текущим
  assert.equal(game.syncContentFromFile({ force: true }).changed, false);
});

test('миграция старой базы: openDb добавляет колонки версий, данные сохраняются', async () => {
  const { DatabaseSync } = await import('node:sqlite');
  const file = join(mkdtempSync(join(tmpdir(), '5ufa-mig-')), 'old.db');
  const old = new DatabaseSync(file);
  old.exec('CREATE TABLE content_versions(id INTEGER PRIMARY KEY, hash TEXT NOT NULL, json TEXT NOT NULL, note TEXT, created INTEGER NOT NULL)');
  old.prepare('INSERT INTO content_versions(hash,json,note,created) VALUES(?,?,?,?)').run('h', JSON.stringify({ x: 1 }), 'старая', 1);
  old.exec('CREATE TABLE battles(id TEXT PRIMARY KEY, account_id INTEGER NOT NULL, stage INTEGER NOT NULL, content_version INTEGER NOT NULL, seed INTEGER NOT NULL, winner TEXT NOT NULL, timeout INTEGER NOT NULL, duration REAL NOT NULL, events TEXT NOT NULL, reward TEXT, created INTEGER NOT NULL)');
  old.prepare('INSERT INTO battles(id,account_id,stage,content_version,seed,winner,timeout,duration,events,created) VALUES(?,?,?,?,?,?,?,?,?,?)').run('b1', 1, 1, 1, 1, 'attacker', 0, 1.5, '[]', 1);
  old.close();
  const db = openDb(file); // настоящая функция открытия с миграцией
  const cols = db.prepare('PRAGMA table_info(content_versions)').all().map((c) => c.name);
  for (const c of ['source', 'author', 'parent']) assert.ok(cols.includes(c), `нет колонки ${c}`);
  assert.equal(db.prepare('SELECT note FROM content_versions').get().note, 'старая');
  assert.ok(db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='story_progress'").get());
  const mediaCols = db.prepare('PRAGMA table_info(media)').all().map((c) => c.name);
  for (const c of ['folder', 'tags', 'license', 'requirements', 'prompt']) assert.ok(mediaCols.includes(c), `нет колонки media.${c}`);
  const battleCols = db.prepare('PRAGMA table_info(battles)').all().map((c) => c.name);
  assert.ok(battleCols.includes('media'));
  assert.equal(db.prepare("SELECT media FROM battles WHERE id='b1'").get().media, null);
  db.close();
  openDb(file).close(); // повторное открытие не падает (колонки уже есть)
});

test('HTTP админка: вход обязателен, сохранение, список, отличия, откат', async () => {
  const dir = mkdtempSync(join(tmpdir(), '5ufa-cvh-'));
  const file = join(dir, 'game.json');
  copyFileSync(SRC, file);
  const app = createApp({ dataDir: join(dir, 'data'), contentPath: file, adminDir: root + 'admin', env: { ADMIN_PASSWORD: 'secret-pass-1' } });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const call = async (path, { body, token } = {}) => {
    const r = await fetch(base + path, { method: body ? 'POST' : 'GET', headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) }, body: body ? JSON.stringify(body) : undefined });
    return { status: r.status, body: await r.json().catch(() => null) };
  };
  try {
    assert.equal((await call('/admin/api/content/versions')).status, 401);
    const t = (await call('/admin/api/login', { body: { login: 'owner', password: 'secret-pass-1' } })).body.token;
    const cur = (await call('/admin/api/content/current', { token: t })).body;
    assert.equal(cur.id, 1);
    cur.content.arena.camera.fov = 50;
    const save = await call('/admin/api/content/save', { body: { content: cur.content, note: 'проба', baseVersion: cur.id }, token: t });
    assert.equal(save.status, 200);
    assert.equal(save.body.version, 2);
    const again = await call('/admin/api/content/save', { body: { content: cur.content, baseVersion: 1 }, token: t });
    assert.equal(again.status, 409);
    cur.content.arena.camera.fov = 1;
    const bad = await call('/admin/api/content/save', { body: { content: cur.content, baseVersion: 2 }, token: t });
    assert.equal(bad.status, 422);
    assert.ok(bad.body.details.length > 0);
    const list = (await call('/admin/api/content/versions', { token: t })).body;
    assert.equal(list.length, 2);
    assert.equal(list[0].active, true);
    const diff = (await call('/admin/api/content/diff?from=1&to=2', { token: t })).body;
    assert.equal(diff.total, 1);
    assert.equal((await call('/api/content')).status, 401); // игровой метод без токена закрыт
    const rb = await call('/admin/api/content/rollback', { body: { version: 1 }, token: t });
    assert.equal(rb.status, 200);
    assert.equal(rb.body.version, 3);
    assert.equal(app.game.getContent().arena.camera.fov, 56);
  } finally { app.close(); }
});

test('аккаунт получает только стартовых героев, новый нестартовый герой в формацию не попадает', () => {
  const { game } = setup();
  const c = edit(game, (x) => {
    const h = clone(x.heroes[0]); h.key = 'paladin'; h.name = 'Паладин'; h.starter = false;
    h.abilities = h.abilities.map((id) => {
      const copy = clone(x.abilities.find((a) => a.id === id));
      copy.id = 'pal_' + id;
      x.abilities.push(copy);
      return copy.id;
    });
    x.heroes.push(h);
  });
  game.publishContent(c, { baseVersion: 1 });
  const acc = game.authenticate(game.guest().token);
  const me = game.me(acc);
  assert.equal(me.heroes.length, 5);
  assert.equal(me.formation.length, 5);
  assert.ok(!me.heroes.some((h) => h.key === 'paladin'));
});

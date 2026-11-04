import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApp } from '../src/app.js';
import { PACKAGE, MAX_APK_BYTES, parseRelease, pickUpdate, createReleaseCheck } from '../src/releases.js';

const root = fileURLToPath(new URL('../../', import.meta.url));
const SHA = '0123456789abcdef'.repeat(4);

function apk(name, size, url = `https://github.com/maillunex-lang/5Ufa/releases/download/client-v0.2.0/${name}`) {
  return { name, size, state: 'uploaded', browser_download_url: url };
}

function body(over = {}) {
  const f = { package: PACKAGE, versionCode: 2, versionName: '0.2.0', sha256: SHA, ...over };
  return `Заметки\npackage: ${f.package}\nversionCode: ${f.versionCode}\nversionName: ${f.versionName}\nsha256: ${f.sha256}\n`;
}

function rel(over = {}) {
  return {
    tag_name: 'client-v0.2.0', draft: false, prerelease: false, name: '0.2.0',
    body: body(), assets: [apk('5ufa.apk', 48_000_000)], ...over,
  };
}

const oldGame = {
  tag_name: 'client-v0.1.21', draft: false, prerelease: false, name: 'Игра 0.1.21',
  body: 'Установите APK. Это сборка старой игры, без package и sha256.',
  assets: [
    apk('ufa-0.1.21.apk', 27_600_813, 'https://github.com/maillunex-lang/5Ufa/releases/download/client-v0.1.21/ufa-0.1.21.apk'),
    apk('ufa-admin-0.1.21.apk', 27_761_287, 'https://github.com/maillunex-lang/5Ufa/releases/download/client-v0.1.21/ufa-admin-0.1.21.apk'),
  ],
};

test('релиз новой игры принимается, старая игра и тестовые сборки — нет', () => {
  const ok = parseRelease(rel());
  assert.equal(ok.versionCode, 2);
  assert.equal(ok.versionName, '0.2.0');
  assert.equal(ok.package, PACKAGE);
  assert.equal(ok.sha256, SHA);
  assert.equal(ok.tag, 'client-v0.2.0');
  assert.equal(ok.size, 48_000_000);
  assert.equal(ok.url.endsWith('/5ufa.apk'), true);

  assert.equal(parseRelease(oldGame), null);
  // даже если к старому тегу дописать правильные строки и один apk
  assert.equal(parseRelease({ ...oldGame, body: body({ versionName: '0.1.21' }), assets: [apk('ufa.apk', 1000)] }), null);
  assert.equal(parseRelease(rel({ tag_name: 'client-v0.1.0', body: body({ versionName: '0.1.0' }) })), null);

  const testApk = rel({
    tag_name: 'client-test-34', prerelease: true, name: 'Тестовый APK #34',
    body: body() + '\nprerelease игрой игнорируется.',
  });
  assert.equal(parseRelease(testApk), null);
  assert.equal(parseRelease({ ...testApk, prerelease: false }), null); // тег не client-vX.Y.Z
  assert.equal(parseRelease(rel({ prerelease: true })), null);
  assert.equal(parseRelease(rel({ draft: true })), null);
});

test('пакет, хеш, размер и неоднозначный apk отбраковываются', () => {
  assert.equal(parseRelease(rel({ body: body({ package: 'ru.other.game' }) })), null);
  assert.equal(parseRelease(rel({ body: body({ sha256: 'abc' }) })), null);
  assert.equal(parseRelease(rel({ body: body({ sha256: '' }) })), null);
  assert.equal(parseRelease(rel({ body: 'package: ' + PACKAGE })), null);
  assert.equal(parseRelease(rel({ body: body({ versionName: '0.2.1' }) })), null);
  assert.equal(parseRelease(rel({ body: body({ versionCode: 0 }) })), null);
  assert.equal(parseRelease(rel({ body: body({ versionCode: '02' }) })), null);
  assert.equal(parseRelease(rel({ body: body() + 'sha256: ' + 'f'.repeat(64) })), null); // две разные строки
  assert.equal(parseRelease(rel({ assets: [] })), null);
  assert.equal(parseRelease(rel({ assets: [apk('a.apk', 10), apk('b.apk', 10)] })), null);
  assert.equal(parseRelease(rel({ assets: [apk('a.apk', MAX_APK_BYTES + 1)] })), null);
  assert.equal(parseRelease(rel({ assets: [apk('a.apk', 0)] })), null);
  assert.equal(parseRelease(rel({ assets: [apk('a.APK', MAX_APK_BYTES)] })).size, MAX_APK_BYTES);
  assert.equal(parseRelease(rel({ assets: [apk('a.apk', 10, 'http://github.com/a.apk')] })), null);
  assert.equal(parseRelease(rel({ assets: [apk('a.apk', 10, 'https://evil.example/a.apk')] })), null);
  assert.equal(parseRelease(rel({ assets: [apk('a.apk', 10, 'https://user:pw@github.com/a.apk')] })), null);
  assert.equal(parseRelease(rel({ assets: [{ ...apk('a.apk', 10), state: 'starter' }] })), null);
  assert.equal(parseRelease(rel()).sha256, SHA);
  assert.equal(parseRelease(rel({ body: body({ sha256: SHA.toUpperCase() }) })).sha256, SHA);
});

test('из списка берётся больший versionCode, старый релиз не перебивает', () => {
  const newer = rel({
    tag_name: 'client-v0.3.0',
    body: body({ versionCode: 5, versionName: '0.3.0' }),
  });
  const picked = pickUpdate([oldGame, rel({ prerelease: true }), newer, rel(), { draft: true }]);
  assert.equal(picked.tag, 'client-v0.3.0');
  assert.equal(picked.versionCode, 5);
  assert.equal(pickUpdate([oldGame]), null);
  assert.equal(pickUpdate([]), null);
  assert.equal(pickUpdate({ message: 'Not Found' }), null);
  const tie = rel({ tag_name: 'client-v0.4.0', body: body({ versionCode: 5, versionName: '0.4.0' }) });
  assert.equal(pickUpdate([newer, tie]), null);
  const ten = rel({ tag_name: 'client-v0.10.0', body: body({ versionCode: 9, versionName: '0.10.0' }) });
  assert.equal(pickUpdate([ten]).tag, 'client-v0.10.0');
});

test('опрос кэшируется, сбой сети не стирает прошлый ответ и не скачивает apk', async () => {
  let t = 1_000_000;
  let mode = 'ok';
  const urls = [];
  const logs = [];
  const fetchImpl = async (url, opts) => {
    urls.push(url);
    assert.equal(opts.headers.authorization, 'Bearer secret-token');
    assert.equal(String(opts.headers.authorization).includes('secret-token'), true);
    assert.equal(url.includes('secret'), false);
    assert.equal(url, 'https://api.github.com/repos/maillunex-lang/5Ufa/releases?per_page=100');
    if (mode === 'boom') throw new Error('network down Bearer secret-token');
    if (mode === 'limit') return { ok: false, status: 403, json: async () => ({ message: 'rate' }) };
    if (mode === 'weird') return { ok: true, status: 200, json: async () => ({ message: 'nope' }) };
    if (mode === 'empty') return { ok: true, status: 200, json: async () => [] };
    return { ok: true, status: 200, json: async () => [oldGame, rel()] };
  };
  const check = createReleaseCheck({ fetchImpl, now: () => t, ttlMs: 1000, token: 'secret-token', log: (m) => logs.push(m) });
  assert.equal((await check.update()).tag, 'client-v0.2.0');
  t += 500;
  await check.update();
  assert.equal(urls.length, 1);

  let release;
  const slow = createReleaseCheck({
    fetchImpl: () => new Promise((r) => { release = r; }),
    now: () => t,
  });
  const a = slow.update();
  const b = slow.update();
  release({ ok: true, status: 200, json: async () => [rel()] });
  assert.equal((await a).versionCode, 2);
  assert.equal((await b).versionCode, 2);

  mode = 'boom';
  t += 1000;
  assert.equal((await check.update()).tag, 'client-v0.2.0');
  assert.equal(logs.at(-1).includes('secret-token'), false);
  t += 30_000;
  await check.update();
  assert.equal(urls.length, 2); // ещё внутри минуты повтора нет
  t += 30_000;
  mode = 'limit';
  assert.equal((await check.update()).tag, 'client-v0.2.0');
  mode = 'weird';
  t += 60_000;
  assert.equal((await check.update()).tag, 'client-v0.2.0'); // кривой ответ не стирает прошлый
  mode = 'empty';
  t += 60_000;
  assert.equal(await check.update(), null);
  assert.throws(() => createReleaseCheck({ repo: 'https://evil.example/x' }), /bad_repo/);
});

test('GET /api/config отдаёт выбранный релиз и без опроса остаётся null', async () => {
  let n = 0;
  const fetchImpl = async (url) => {
    n += 1;
    assert.match(url, /^https:\/\/api\.github\.com\/repos\/owner\/game\/releases/);
    return { ok: true, status: 200, json: async () => [oldGame, rel()] };
  };
  const app = createApp({
    dataDir: mkdtempSync(join(tmpdir(), '5ufa-rel-')),
    contentPath: root + 'content/game.json',
    adminDir: root + 'admin',
    env: { ADMIN_PASSWORD: 'secret-pass-1', RELEASES_REPO: 'owner/game' },
    releaseFetch: fetchImpl,
  });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const off = createApp({
    dataDir: mkdtempSync(join(tmpdir(), '5ufa-off-')),
    contentPath: root + 'content/game.json',
    adminDir: root + 'admin',
    env: { ADMIN_PASSWORD: 'secret-pass-1', RELEASES_DISABLED: '1' },
    releaseFetch: () => { throw new Error('не должны звать сеть'); },
  });
  await new Promise((r) => off.server.listen(0, '127.0.0.1', r));
  const offBase = `http://127.0.0.1:${off.server.address().port}`;
  try {
    const c = await (await fetch(base + '/api/config')).json();
    assert.equal(c.maintenance, false);
    assert.equal(c.update.tag, 'client-v0.2.0');
    assert.equal(c.update.package, PACKAGE);
    assert.equal(c.update.sha256, SHA);
    await fetch(base + '/api/config');
    assert.equal(n, 1);
    const quiet = await (await fetch(offBase + '/api/config')).json();
    assert.equal(quiet.update, null);
  } finally {
    app.close();
    off.close();
  }
});

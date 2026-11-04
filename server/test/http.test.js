import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createApp } from '../src/app.js';

const root = fileURLToPath(new URL('../../', import.meta.url));

test('HTTP: гость → бой → админка → техработы', async () => {
  const app = createApp({ dataDir: mkdtempSync(join(tmpdir(), '5ufa-')), contentPath: root + 'content/game.json', adminDir: root + 'admin', env: { ADMIN_PASSWORD: 'secret-pass-1' } });
  await new Promise((r) => app.server.listen(0, '127.0.0.1', r));
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const call = async (path, { body, token, method } = {}) => {
    const r = await fetch(base + path, { method: method || (body ? 'POST' : 'GET'), headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer ' + token } : {}) }, body: body ? JSON.stringify(body) : undefined });
    return { status: r.status, body: await r.json().catch(() => null) };
  };
  try {
    assert.equal((await call('/health')).body.ok, true);
    assert.equal((await call('/api/me')).status, 401);
    const { token } = (await call('/api/guest', { body: {} })).body;
    assert.equal((await call('/api/me', { token })).body.heroes.length, 5);
    const b = await call('/api/battle/start', { body: { stage: 1 }, token });
    assert.equal(b.status, 200);
    assert.ok(b.body.events.length > 5);
    assert.equal((await call('/api/battle/' + b.body.battleId, { token })).body.winner, b.body.winner);

    assert.equal((await call('/admin/api/status')).status, 401);
    assert.equal((await call('/admin/api/login', { body: { login: 'owner', password: 'bad' } })).status, 401);
    const a = (await call('/admin/api/login', { body: { login: 'owner', password: 'secret-pass-1' } })).body.token;
    const st = (await call('/admin/api/status', { token: a })).body;
    assert.equal(st.accounts, 1);
    await call('/admin/api/maintenance', { body: { on: true, message: 'x' }, token: a });
    assert.equal((await call('/api/battle/start', { body: { stage: 1 }, token })).status, 503);
    assert.equal((await call('/api/config')).body.maintenance, true);
    const page = await fetch(base + '/admin/');
    assert.equal(page.status, 200);
    assert.equal((await fetch(base + '/admin/../server/package.json')).status, 404);
  } finally { app.close(); }
});

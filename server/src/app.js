import { createServer } from 'node:http';
import { readFileSync, existsSync, mkdirSync, writeFileSync, readdirSync, statSync, unlinkSync, chmodSync, createReadStream } from 'node:fs';
import { join, extname, normalize, sep, dirname } from 'node:path';
import { randomBytes } from 'node:crypto';
import { createMedia, isSha, MAX_MEDIA_BYTES } from './media.js';
import { createGame, GameError } from './game.js';
import { openDb } from './db.js';
import { hashPassword, checkPassword, makeLimiter, newToken, sha } from './auth.js';
import { createReleaseCheck } from './releases.js';

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml' };
const VERSION = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')).version;

export function createApp({ dataDir, contentPath, adminDir, env = process.env, releaseFetch }) {
  mkdirSync(dataDir, { recursive: true });
  const db = openDb(join(dataDir, 'game.db'));
  const game = createGame(db, { contentPath });
  const media = createMedia({ db, dir: join(dataDir, 'media'), audit: game.audit });
  media.seed(env.SEED_MEDIA_DIR || join(dirname(contentPath), '..', 'client', 'assets', 'models'));
  media.seedImages(env.SEED_IMAGE_DIR || join(dirname(contentPath), '..', 'client', 'assets', 'backgrounds'));
  const started = Date.now();
  const audit = (actor, action, detail) => db.prepare('INSERT INTO audit(ts,actor,action,detail) VALUES(?,?,?,?)').run(Date.now(), actor, action, detail ? JSON.stringify(detail) : null);
  const logError = (source, e) => db.prepare('INSERT INTO error_log(ts,source,message) VALUES(?,?,?)').run(Date.now(), source, String(e?.stack || e).slice(0, 2000));
  let releases = { update: async () => null };
  if (env.RELEASES_DISABLED !== '1') {
    try {
      releases = createReleaseCheck({
        repo: env.RELEASES_REPO || 'maillunex-lang/5Ufa',
        token: env.GITHUB_TOKEN || '',
        fetchImpl: releaseFetch || globalThis.fetch,
        log: (m) => logError('releases', m),
      });
    } catch (e) { logError('releases', e); }
  }

  // ---------- владелец админки ----------
  const adminUser = env.ADMIN_USER || 'owner';
  if (!db.prepare("SELECT 1 FROM settings WHERE k='admin_pass'").get()) {
    const pw = env.ADMIN_PASSWORD || randomBytes(12).toString('base64url');
    db.prepare("INSERT INTO settings(k,v) VALUES('admin_pass',?)").run(hashPassword(pw));
    if (!env.ADMIN_PASSWORD) {
      const f = join(dataDir, 'ADMIN_INITIAL_PASSWORD.txt');
      writeFileSync(f, `login: ${adminUser}\npassword: ${pw}\n(смените пароль в админке и удалите этот файл)\n`);
      try { chmodSync(f, 0o600); } catch { /* ignore */ }
      console.log(`[admin] первый запуск: логин/пароль записаны в ${f}`);
    }
  }
  const adminSessions = new Map(); // tokenHash -> {last}
  const ADMIN_IDLE = 30 * 60 * 1000;
  const loginLimit = makeLimiter(5, 60_000);
  const guestLimit = makeLimiter(20, 60_000);

  // ---------- бэкапы ----------
  function backup(reason) {
    const dir = join(dataDir, 'backups');
    mkdirSync(dir, { recursive: true });
    const name = `game-${new Date().toISOString().replace(/[:.]/g, '-')}-${reason}.db`;
    db.exec(`VACUUM INTO '${join(dir, name).replace(/'/g, "''")}'`);
    const keep = Number(env.BACKUP_KEEP || 14);
    const files = readdirSync(dir).filter((f) => f.endsWith('-daily.db')).sort();
    for (const f of files.slice(0, Math.max(0, files.length - keep))) unlinkSync(join(dir, f));
    return name;
  }
  const dayKey = () => new Date().toISOString().slice(0, 10);
  function dailyBackupIfDue() {
    const last = db.prepare("SELECT v FROM settings WHERE k='last_daily_backup'").get()?.v;
    if (last !== dayKey()) { backup('daily'); db.prepare("INSERT OR REPLACE INTO settings(k,v) VALUES('last_daily_backup',?)").run(dayKey()); }
  }
  dailyBackupIfDue();
  const timer = setInterval(() => { try { dailyBackupIfDue(); } catch (e) { logError('backup', e); } }, 3600_000);
  timer.unref();

  // ---------- http ----------
  const json = (res, status, obj) => { const b = JSON.stringify(obj); res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' }); res.end(b); };
  const readBody = (req, max = 65536) => new Promise((ok, fail) => {
    let n = 0; const ch = [];
    req.on('data', (d) => { n += d.length; if (n > max) { fail(new GameError('too_large', 'Слишком большой запрос', 413)); req.destroy(); } else ch.push(d); });
    req.on('end', () => { try { ok(ch.length ? JSON.parse(Buffer.concat(ch).toString('utf8')) : {}); } catch { fail(new GameError('bad_json', 'Некорректный JSON')); } });
  });
  const readRaw = (req, max) => new Promise((ok, fail) => {
    const tooBig = () => { req.removeAllListeners('data'); req.resume(); fail(new GameError('too_large', `Файл больше ${Math.floor(max / 1048576)} МБ`, 413)); }; // дочитываем и отбрасываем, чтобы ответить понятной ошибкой
    if (Number(req.headers['content-length']) > max) return tooBig();
    let n = 0; const ch = []; let dead = false;
    req.on('data', (d) => { if (dead) return; n += d.length; if (n > max) { dead = true; tooBig(); } else ch.push(d); });
    req.on('end', () => { if (!dead) ok(Buffer.concat(ch)); });
    req.on('error', fail);
  });
  const sendFile = (res, path) => {
    const type = { '.glb': 'model/gltf-binary', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg' }[extname(path).toLowerCase()] || 'application/octet-stream';
    res.writeHead(200, { 'content-type': type, 'cache-control': 'public, max-age=31536000, immutable', 'content-length': statSync(path).size, 'x-content-type-options': 'nosniff' });
    createReadStream(path).pipe(res);
  };
  const bearer = (req) => (req.headers.authorization || '').replace(/^Bearer /, '');
  const ip = (req) => req.headers['x-forwarded-for']?.split(',')[0].trim() || req.socket.remoteAddress;

  function requireAdmin(req) {
    const h = sha(bearer(req));
    const s = adminSessions.get(h);
    if (!s || Date.now() - s.last > ADMIN_IDLE) { adminSessions.delete(h); throw new GameError('unauthorized', 'Войдите в админку', 401); }
    s.last = Date.now();
  }

  async function route(req, res, url) {
    const p = url.pathname, m = req.method;
    // --- публичное ---
    if (p === '/health') return json(res, 200, { ok: true, version: VERSION, uptimeSec: Math.round((Date.now() - started) / 1000) });
    if (p === '/api/config' && m === 'GET') {
      let update = null;
      try { update = await releases.update(); } catch (e) { logError('releases', e); }
      return json(res, 200, { server: VERSION, maintenance: game.isMaintenance(), maintenanceMessage: db.prepare("SELECT v FROM settings WHERE k='maintenance_msg'").get()?.v ?? '', contentVersion: game.getContent().id, update });
    }
    const mf = p.match(/^\/api\/media\/([0-9a-f]{64})$/);
    if (mf && m === 'GET') { const f = media.byHash(mf[1]); if (!f) throw new GameError('not_found', 'Файл не найден', 404); return sendFile(res, f); }
    if (p === '/api/guest' && m === 'POST') {
      if (!guestLimit(ip(req))) throw new GameError('rate_limited', 'Слишком часто', 429);
      return json(res, 200, game.guest());
    }
    if (p === '/api/login' && m === 'POST') {
      const b = await readBody(req);
      if (!loginLimit(`u:${ip(req)}`) || !loginLimit(`l:${String(b.login).toLowerCase()}`)) throw new GameError('rate_limited', 'Слишком много попыток', 429);
      return json(res, 200, game.login(b.login, b.password));
    }
    if (p === '/api/recover' && m === 'POST') {
      const b = await readBody(req);
      if (!loginLimit(`u:${ip(req)}`) || !loginLimit(`l:${String(b.login).toLowerCase()}`)) throw new GameError('rate_limited', 'Слишком много попыток', 429);
      return json(res, 200, game.recover(b.login, b.code, b.newPassword));
    }
    // --- игрок ---
    if (p.startsWith('/api/')) {
      const acc = game.authenticate(bearer(req));
      if (p === '/api/me' && m === 'GET') return json(res, 200, game.me(acc));
      if (p === '/api/content' && m === 'GET') { const c = game.getContent(); return json(res, 200, { id: c.id, abilities: c.abilities || [], heroes: c.heroes, enemies: c.enemies, stages: c.stages.map(({ n, name, enemies, reward }) => ({ n, name, enemies, reward })), progression: c.progression, battle: c.battle, tutorial: c.tutorial || { steps: [] }, arena: c.arena, world: c.world || null, ui: c.ui || null, media: media.manifest() }); }
      const b = m === 'POST' ? await readBody(req) : {};
      if (p === '/api/bind') return json(res, 200, game.bind(acc, b.login, b.password));
      if (p === '/api/formation') return json(res, 200, game.setFormation(acc, b.slots));
      if (p === '/api/tutorial/done') return json(res, 200, game.setTutorialDone(acc));
      if (p === '/api/story/complete' && m === 'POST') return json(res, 200, game.completeStory(acc, String(b.questId || '')));
      if (p === '/api/hero/upgrade') return json(res, 200, game.upgradeHero(acc, b.heroId));
      if (p === '/api/hero/reset') return json(res, 200, game.resetHero(acc, b.heroId));
      if (p === '/api/battle/start') return json(res, 200, game.startBattle(acc, Number(b.stage)));
      const mb = p.match(/^\/api\/battle\/([\w-]+)$/);
      if (mb && m === 'GET') return json(res, 200, game.getBattle(acc, mb[1]));
      throw new GameError('not_found', 'Нет такого метода', 404);
    }
    // --- админка ---
    if (p === '/admin/api/login' && m === 'POST') {
      const b = await readBody(req);
      if (!loginLimit(`a:${ip(req)}`)) throw new GameError('rate_limited', 'Слишком много попыток', 429);
      const ok = b.login === adminUser && checkPassword(String(b.password || ''), db.prepare("SELECT v FROM settings WHERE k='admin_pass'").get().v);
      audit(adminUser, ok ? 'admin_login' : 'admin_login_failed', { ip: ip(req) });
      if (!ok) throw new GameError('bad_credentials', 'Неверный логин или пароль', 401);
      const t = newToken();
      adminSessions.set(sha(t), { last: Date.now() });
      return json(res, 200, { token: t });
    }
    if (p.startsWith('/admin/api/')) {
      requireAdmin(req);
      if (p === '/admin/api/media/upload' && m === 'POST') {
        const q = url.searchParams;
        const buf = await readRaw(req, MAX_MEDIA_BYTES);
        return json(res, 200, media.upload({ name: q.get('name'), kind: q.get('kind') || 'model', buf, filename: q.get('filename'), note: q.get('note') || '', author: adminUser, activate: q.has('activate') ? q.get('activate') === '1' : undefined }));
      }
      const fm = p.match(/^\/admin\/api\/media\/file\/([0-9a-f]{64})$/);
      if (fm && m === 'GET') { const f = media.byHash(fm[1]); if (!f) throw new GameError('not_found', 'Файл не найден', 404); return sendFile(res, f); }
      if (p === '/admin/api/media' && m === 'GET') return json(res, 200, media.list(game.getContent()));
      const b = m === 'POST' ? await readBody(req, p.startsWith('/admin/api/content') ? 3_000_000 : 65536) : {};
      if (p === '/admin/api/media/activate' && m === 'POST') return json(res, 200, media.activate(String(b.name), Number(b.version), adminUser));
      if (p === '/admin/api/media/card' && m === 'POST') return json(res, 200, media.setCard(String(b.name), b, adminUser));
      if (p === '/admin/api/status') {
        const n = (sql) => db.prepare(sql).get().n;
        return json(res, 200, {
          version: VERSION, uptimeSec: Math.round((Date.now() - started) / 1000),
          contentVersion: game.getContent().id, maintenance: game.isMaintenance(),
          accounts: n('SELECT COUNT(*) n FROM accounts'), battles: n('SELECT COUNT(*) n FROM battles'),
          battlesLastDay: n(`SELECT COUNT(*) n FROM battles WHERE created>${Date.now() - 864e5}`),
          lastBackup: db.prepare("SELECT v FROM settings WHERE k='last_daily_backup'").get()?.v ?? null,
          errors: db.prepare('SELECT ts,source,message FROM error_log ORDER BY id DESC LIMIT 10').all(),
          changes: db.prepare('SELECT ts,actor,action,detail FROM audit ORDER BY id DESC LIMIT 15').all(),
        });
      }
      if (p === '/admin/api/maintenance') {
        const on = !!b.on;
        db.prepare("INSERT OR REPLACE INTO settings(k,v) VALUES('maintenance',?)").run(on ? '1' : '0');
        db.prepare("INSERT OR REPLACE INTO settings(k,v) VALUES('maintenance_msg',?)").run(String(b.message || '').slice(0, 300));
        audit(adminUser, 'maintenance', { on });
        return json(res, 200, { maintenance: on });
      }
      if (p === '/admin/api/backup' && m === 'POST') { const name = backup('manual'); audit(adminUser, 'backup', { name }); return json(res, 200, { name }); }
      if (p === '/admin/api/content/current' && m === 'GET') { const id = game.currentVersionId(); return json(res, 200, game.getVersion(id)); }
      if (p === '/admin/api/content/versions' && m === 'GET') return json(res, 200, game.listVersions(Number(url.searchParams.get('limit')) || 50));
      const mv = p.match(/^\/admin\/api\/content\/version\/(\d+)$/);
      if (mv && m === 'GET') return json(res, 200, game.getVersion(Number(mv[1])));
      if (p === '/admin/api/content/diff' && m === 'GET') return json(res, 200, game.diffVersions(Number(url.searchParams.get('from')), Number(url.searchParams.get('to'))));
      if (p === '/admin/api/content/save' && m === 'POST') {
        const r = game.publishContent(b.content, { author: adminUser, note: String(b.note || '').slice(0, 300), baseVersion: b.baseVersion });
        return json(res, 200, r);
      }
      if (p === '/admin/api/content/rollback' && m === 'POST') return json(res, 200, game.rollbackTo(Number(b.version), { author: adminUser, note: String(b.note || '').slice(0, 300) }));
      if (p === '/admin/api/content/reload' && m === 'POST') { const r = game.syncContentFromFile({ force: !!b.force, author: adminUser }); return json(res, 200, { ...r, contentVersion: game.currentVersionId() }); }
      throw new GameError('not_found', 'Нет такого метода', 404);
    }
    // --- статика админки ---
    if (p === '/admin' || p.startsWith('/admin/')) {
      const rel = normalize(p === '/admin' || p === '/admin/' ? 'index.html' : p.slice(7)).replace(/^(\.\.[/\\])+/, '');
      const f = join(adminDir, rel);
      if (!f.startsWith(adminDir + sep) || !existsSync(f) || !statSync(f).isFile()) throw new GameError('not_found', 'Нет файла', 404);
      res.writeHead(200, { 'content-type': MIME[extname(f)] || 'application/octet-stream', 'x-content-type-options': 'nosniff' });
      return res.end(readFileSync(f));
    }
    throw new GameError('not_found', 'Не найдено', 404);
  }

  const server = createServer(async (req, res) => {
    try {
      await route(req, res, new URL(req.url, 'http://x'));
    } catch (e) {
      if (e instanceof GameError) return json(res, e.status, { error: e.code, message: e.message, ...(e.details ? { details: e.details } : {}) });
      logError('server', e);
      console.error(e);
      json(res, 500, { error: 'internal', message: 'Внутренняя ошибка' });
    }
  });
  return { server, game, db, media, backup, close: () => { clearInterval(timer); server.close(); db.close(); } };
}

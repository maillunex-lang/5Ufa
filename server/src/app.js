import { createServer } from 'node:http';
import { readFileSync, existsSync, mkdirSync, writeFileSync, readdirSync, statSync, unlinkSync, chmodSync } from 'node:fs';
import { join, extname, normalize, sep } from 'node:path';
import { randomBytes } from 'node:crypto';
import { createGame, GameError } from './game.js';
import { openDb } from './db.js';
import { hashPassword, checkPassword, makeLimiter, newToken, sha } from './auth.js';

const MIME = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.svg': 'image/svg+xml' };
const VERSION = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8')).version;

export function createApp({ dataDir, contentPath, adminDir, env = process.env }) {
  mkdirSync(dataDir, { recursive: true });
  const db = openDb(join(dataDir, 'game.db'));
  const game = createGame(db, { contentPath });
  const started = Date.now();
  const audit = (actor, action, detail) => db.prepare('INSERT INTO audit(ts,actor,action,detail) VALUES(?,?,?,?)').run(Date.now(), actor, action, detail ? JSON.stringify(detail) : null);
  const logError = (source, e) => db.prepare('INSERT INTO error_log(ts,source,message) VALUES(?,?,?)').run(Date.now(), source, String(e?.stack || e).slice(0, 2000));

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
  const readBody = (req) => new Promise((ok, fail) => {
    let n = 0; const ch = [];
    req.on('data', (d) => { n += d.length; if (n > 65536) { fail(new GameError('too_large', 'Слишком большой запрос', 413)); req.destroy(); } else ch.push(d); });
    req.on('end', () => { try { ok(ch.length ? JSON.parse(Buffer.concat(ch).toString('utf8')) : {}); } catch { fail(new GameError('bad_json', 'Некорректный JSON')); } });
  });
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
      // Клиент спрашивает при запуске. Принудительное обновление (updates) заполняется модулем релизов (этап 6).
      return json(res, 200, { server: VERSION, maintenance: game.isMaintenance(), maintenanceMessage: db.prepare("SELECT v FROM settings WHERE k='maintenance_msg'").get()?.v ?? '', contentVersion: game.getContent().id, update: null });
    }
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
      if (p === '/api/content' && m === 'GET') { const c = game.getContent(); return json(res, 200, { id: c.id, heroes: c.heroes, enemies: c.enemies, stages: c.stages.map(({ n, name, enemies, reward }) => ({ n, name, enemies, reward })), progression: c.progression, battle: c.battle, tutorial: c.tutorial || { steps: [] } }); }
      const b = m === 'POST' ? await readBody(req) : {};
      if (p === '/api/bind') return json(res, 200, game.bind(acc, b.login, b.password));
      if (p === '/api/formation') return json(res, 200, game.setFormation(acc, b.slots));
      if (p === '/api/tutorial/done') return json(res, 200, game.setTutorialDone(acc));
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
      const b = m === 'POST' ? await readBody(req) : {};
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
      if (p === '/admin/api/content/versions') return json(res, 200, db.prepare('SELECT id,hash,note,created FROM content_versions ORDER BY id DESC LIMIT 50').all());
      if (p === '/admin/api/content/reload' && m === 'POST') { const before = game.getContent().id; game.syncContentFromFile(); audit(adminUser, 'content_reload', { before, after: game.getContent().id }); return json(res, 200, { contentVersion: game.getContent().id }); }
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
      if (e instanceof GameError) return json(res, e.status, { error: e.code, message: e.message });
      logError('server', e);
      console.error(e);
      json(res, 500, { error: 'internal', message: 'Внутренняя ошибка' });
    }
  });
  return { server, game, db, backup, close: () => { clearInterval(timer); server.close(); db.close(); } };
}

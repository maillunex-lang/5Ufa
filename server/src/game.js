import { randomUUID, randomInt, createHash } from 'node:crypto';
import { tx } from './db.js';
import { buildUnit, simulate } from './battle.js';
import { sha, newToken, hashPassword, checkPassword, newRecoveryCode, normCode } from './auth.js';
import { loadContentFile, validateContent, diffContent } from './content.js';

export class GameError extends Error {
  constructor(code, msg, status = 400, details) { super(msg || code); this.code = code; this.status = status; this.details = details; }
}
const now = () => Date.now();

export function createGame(db, { contentPath }) {
  const q = (sql, ...p) => db.prepare(sql).all(...p);
  const one = (sql, ...p) => db.prepare(sql).get(...p);
  const run = (sql, ...p) => db.prepare(sql).run(...p);

  // ---------- контент и версии ----------
  // Версии линейные: активна последняя. Правка и откат создают НОВУЮ версию (история не переписывается).
  // Бой закрепляет версию в момент старта (battles.content_version), поэтому правки действуют со следующего боя.
  const audit = (actor, action, detail) => run('INSERT INTO audit(ts,actor,action,detail) VALUES(?,?,?,?)', now(), actor, action, detail ? JSON.stringify(detail) : null);
  const hashOf = (text) => createHash('sha256').update(text).digest('hex');
  const currentVersionId = () => one('SELECT MAX(id) m FROM content_versions').m;
  const versionRow = (id) => one('SELECT id,hash,json,note,source,author,parent,created FROM content_versions WHERE id=?', id);

  function insertVersion(obj, { source, author, note, parent }) {
    const json = JSON.stringify(obj);
    const r = run('INSERT INTO content_versions(hash,json,note,created,source,author,parent) VALUES(?,?,?,?,?,?,?)',
      hashOf(json), json, note ?? null, now(), source, author ?? null, parent ?? null);
    return Number(r.lastInsertRowid);
  }

  const contentCache = new Map();
  function getContent(version) {
    const id = version ?? currentVersionId();
    if (!contentCache.has(id)) {
      const row = versionRow(id);
      if (!row) throw new GameError('no_version', 'Версия контента не найдена', 404);
      contentCache.set(id, { id, ...JSON.parse(row.json) });
    }
    return contentCache.get(id);
  }

  // Файл content/game.json — «зерно»: импортируется только когда изменился сам файл (по хешу), иначе каждый деплой
  // затирал бы правки из админки. Первый запуск на пустой базе тоже импортирует файл.
  function syncContentFromFile({ force = false, author = 'система' } = {}) {
    const { json, hash } = loadContentFile(contentPath);
    const seen = one("SELECT v FROM settings WHERE k='content_file_hash'")?.v;
    const cur = currentVersionId();
    if (!force && seen === hash && cur) return { changed: false, version: cur };
    run("INSERT OR REPLACE INTO settings(k,v) VALUES('content_file_hash',?)", hash);
    if (cur && versionRow(cur).hash === hash) return { changed: false, version: cur };
    const id = insertVersion(JSON.parse(json), { source: 'file', author, note: 'Импорт из content/game.json', parent: cur });
    audit(author, 'content_file_import', { from: cur ?? null, to: id });
    return { changed: true, version: id };
  }

  // Нельзя убрать героя, которым владеют игроки: удаление возможно только с компенсацией (отдельная задача S-5).
  function assertHeroesKept(obj) {
    const keep = new Set((obj.heroes || []).map((h) => h.key));
    const gone = q('SELECT hero_key, COUNT(*) n FROM heroes GROUP BY hero_key').filter((r) => !keep.has(r.hero_key));
    if (gone.length) throw new GameError('hero_in_use', `Нельзя удалить героев, которые есть у игроков: ${gone.map((r) => `${r.hero_key} (${r.n})`).join(', ')}. Удаление с компенсацией будет добавлено отдельно.`, 409, gone);
  }

  function listVersions(limit = 50) {
    const cur = currentVersionId();
    return q('SELECT id,hash,note,source,author,parent,created FROM content_versions ORDER BY id DESC LIMIT ?', limit)
      .map((r) => ({ ...r, hash: r.hash.slice(0, 12), active: r.id === cur }));
  }

  function getVersion(id) {
    const row = versionRow(id);
    if (!row) throw new GameError('no_version', 'Версия контента не найдена', 404);
    return { id: row.id, note: row.note, source: row.source, author: row.author, parent: row.parent, created: row.created, active: row.id === currentVersionId(), content: JSON.parse(row.json) };
  }

  function diffVersions(from, to) {
    return { from, to, ...diffContent(getVersion(from).content, getVersion(to).content) };
  }

  // Сохранение правки из админки: проверка до записи, защита от гонки по базовой версии, журнал.
  function publishContent(obj, { author = 'owner', note = '', baseVersion } = {}) {
    const errs = validateContent(obj);
    if (errs.length) throw new GameError('invalid_content', 'Контент не прошёл проверку', 422, errs);
    return tx(db, () => {
      const cur = currentVersionId();
      if (baseVersion !== undefined && Number(baseVersion) !== cur) {
        throw new GameError('version_conflict', `Контент уже изменили: сейчас версия ${cur}, а вы правили версию ${baseVersion}. Обновите страницу и повторите.`, 409);
      }
      const text = JSON.stringify(obj);
      if (hashOf(text) === versionRow(cur).hash) throw new GameError('no_changes', 'Изменений нет', 400);
      assertHeroesKept(obj);
      const diff = diffContent(getVersion(cur).content, obj);
      const id = insertVersion(obj, { source: 'admin', author, note, parent: cur });
      audit(author, 'content_save', { from: cur, to: id, note, changes: diff.total });
      return { version: id, changes: diff.total };
    });
  }

  // Откат: создаёт новую версию с содержимым старой. Аккаунты игроков не затрагиваются.
  function rollbackTo(targetId, { author = 'owner', note = '' } = {}) {
    return tx(db, () => {
      const target = versionRow(targetId);
      if (!target) throw new GameError('no_version', 'Версия контента не найдена', 404);
      const cur = currentVersionId();
      if (target.id === cur) throw new GameError('already_current', 'Эта версия уже активна', 400);
      const obj = JSON.parse(target.json);
      assertHeroesKept(obj);
      const id = insertVersion(obj, { source: 'rollback', author, note: note || `Откат к версии ${target.id}`, parent: cur });
      audit(author, 'content_rollback', { target: target.id, from: cur, to: id, note });
      return { version: id, restoredFrom: target.id };
    });
  }
  syncContentFromFile();

  // ---------- ресурсы ----------
  function addRes(acc, currency, delta, kind, ref) {
    run('INSERT OR IGNORE INTO balances(account_id,currency,amount) VALUES(?,?,0)', acc, currency);
    const cur = one('SELECT amount FROM balances WHERE account_id=? AND currency=?', acc, currency).amount;
    if (cur + delta < 0) throw new GameError('not_enough', `Не хватает ${currency}`);
    run('UPDATE balances SET amount=amount+? WHERE account_id=? AND currency=?', delta, acc, currency);
    run('INSERT INTO resource_ops(account_id,kind,currency,delta,ref,created) VALUES(?,?,?,?,?,?)', acc, kind, currency, delta, ref ?? null, now());
  }
  const balances = (acc) => Object.fromEntries(q('SELECT currency,amount FROM balances WHERE account_id=?', acc).map((r) => [r.currency, r.amount]));

  // ---------- аккаунты ----------
  function createSession(acc) {
    const token = newToken();
    run('INSERT INTO sessions(token_hash,account_id,created,last_seen) VALUES(?,?,?,?)', sha(token), acc, now(), now());
    return token;
  }

  function guest() {
    return tx(db, () => {
      const c = getContent();
      const acc = Number(run('INSERT INTO accounts(created) VALUES(?)', now()).lastInsertRowid);
      for (const h of c.heroes.filter((x) => x.starter)) run('INSERT INTO heroes(account_id,hero_key,level) VALUES(?,?,1)', acc, h.key); // стартовые 5 героев сразу
      for (const [cur, amt] of Object.entries(c.progression.startBalance)) addRes(acc, cur, amt, 'start', null);
      const ids = q('SELECT id FROM heroes WHERE account_id=? ORDER BY id', acc).map((r) => r.id);
      run('INSERT INTO formations(account_id,slots) VALUES(?,?)', acc, JSON.stringify(ids));
      return { token: createSession(acc), accountId: acc };
    });
  }

  function authenticate(token) {
    if (!token) throw new GameError('unauthorized', 'Нет сессии', 401);
    const s = one('SELECT s.account_id, a.banned FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE token_hash=?', sha(token));
    if (!s) throw new GameError('unauthorized', 'Сессия недействительна', 401);
    if (s.banned) throw new GameError('banned', 'Аккаунт заблокирован', 403);
    run('UPDATE sessions SET last_seen=? WHERE token_hash=?', now(), sha(token));
    return s.account_id;
  }

  function bind(acc, login, password) {
    login = String(login || '').trim().toLowerCase();
    if (!/^[a-z0-9_.-]{3,32}$/.test(login)) throw new GameError('bad_login', 'Логин: 3–32 символа a-z, 0-9, _ . -');
    if (String(password || '').length < 8) throw new GameError('weak_password', 'Пароль не короче 8 символов');
    const a = one('SELECT login FROM accounts WHERE id=?', acc);
    if (a.login) throw new GameError('already_bound', 'Аккаунт уже привязан');
    if (one('SELECT 1 FROM accounts WHERE login=?', login)) throw new GameError('login_taken', 'Логин занят', 409);
    const code = newRecoveryCode();
    run('UPDATE accounts SET login=?, pass_hash=?, recovery_hash=? WHERE id=?', login, hashPassword(password), sha(normCode(code)), acc);
    return { recoveryCode: code }; // единственный показ
  }

  function login(loginName, password) {
    const a = one('SELECT id,pass_hash,banned FROM accounts WHERE login=?', String(loginName || '').trim().toLowerCase());
    if (!a || !checkPassword(String(password || ''), a.pass_hash)) throw new GameError('bad_credentials', 'Неверный логин или пароль', 401);
    if (a.banned) throw new GameError('banned', 'Аккаунт заблокирован', 403);
    return { token: createSession(a.id), accountId: a.id };
  }

  function recover(loginName, code, newPassword) {
    if (String(newPassword || '').length < 8) throw new GameError('weak_password', 'Пароль не короче 8 символов');
    const a = one('SELECT id,recovery_hash FROM accounts WHERE login=?', String(loginName || '').trim().toLowerCase());
    if (!a || !a.recovery_hash || a.recovery_hash !== sha(normCode(code))) throw new GameError('bad_credentials', 'Неверный логин или код', 401);
    return tx(db, () => {
      const fresh = newRecoveryCode(); // старый код сгорает, выдаётся новый
      run('UPDATE accounts SET pass_hash=?, recovery_hash=? WHERE id=?', hashPassword(newPassword), sha(normCode(fresh)), a.id);
      run('DELETE FROM sessions WHERE account_id=?', a.id);
      return { token: createSession(a.id), accountId: a.id, recoveryCode: fresh };
    });
  }

  // ---------- состояние игрока ----------
  function me(acc) {
    const c = getContent();
    const a = one('SELECT id,login,tutorial_done FROM accounts WHERE id=?', acc);
    const heroes = q('SELECT id,hero_key key,level FROM heroes WHERE account_id=? ORDER BY id', acc);
    const cleared = q('SELECT stage FROM stage_progress WHERE account_id=? AND cleared=1 ORDER BY stage', acc).map((r) => r.stage);
    return {
      account: { id: a.id, bound: !!a.login, login: a.login, tutorialDone: !!a.tutorial_done },
      heroes, balances: balances(acc),
      formation: JSON.parse(one('SELECT slots FROM formations WHERE account_id=?', acc).slots),
      clearedStages: cleared, contentVersion: c.id, maxLevel: c.progression.maxLevel,
    };
  }

  function setFormation(acc, slots) {
    const ids = q('SELECT id FROM heroes WHERE account_id=?', acc).map((r) => r.id);
    if (!Array.isArray(slots) || slots.length !== 5 || new Set(slots).size !== 5 || !slots.every((s) => ids.includes(s)))
      throw new GameError('bad_formation', 'Нужно 5 разных своих героев (слоты 0–1 перед, 2–4 зад)');
    run('UPDATE formations SET slots=? WHERE account_id=?', JSON.stringify(slots), acc);
    return { formation: slots };
  }

  function setTutorialDone(acc) { run('UPDATE accounts SET tutorial_done=1 WHERE id=?', acc); return { ok: true }; }

  // ---------- прокачка ----------
  function heroOf(acc, heroId) {
    const h = one('SELECT id,hero_key,level FROM heroes WHERE id=? AND account_id=?', heroId, acc);
    if (!h) throw new GameError('no_hero', 'Герой не найден', 404);
    return h;
  }

  function upgradeHero(acc, heroId) {
    return tx(db, () => {
      const c = getContent();
      const h = heroOf(acc, heroId);
      if (h.level >= c.progression.maxLevel) throw new GameError('max_level', 'Максимальный уровень');
      const cost = { gold: c.progression.upgradeCost.gold * h.level, hero_exp: c.progression.upgradeCost.hero_exp * h.level };
      addRes(acc, 'gold', -cost.gold, 'upgrade', `hero:${h.id}`);
      addRes(acc, 'hero_exp', -cost.hero_exp, 'upgrade', `hero:${h.id}`);
      // фактическая цена фиксируется — при смене цен возврат берётся отсюда
      run('INSERT INTO level_ops(hero_id,from_level,to_level,gold,hero_exp,created) VALUES(?,?,?,?,?,?)', h.id, h.level, h.level + 1, cost.gold, cost.hero_exp, now());
      run('UPDATE heroes SET level=level+1 WHERE id=?', h.id);
      return { level: h.level + 1, spent: cost, balances: balances(acc) };
    });
  }

  function resetHero(acc, heroId) {
    return tx(db, () => {
      const h = heroOf(acc, heroId);
      const s = one('SELECT COALESCE(SUM(gold),0) g, COALESCE(SUM(hero_exp),0) e FROM level_ops WHERE hero_id=? AND reverted=0', h.id);
      if (h.level > 1 || s.g || s.e) {
        if (s.g) addRes(acc, 'gold', s.g, 'reset_refund', `hero:${h.id}`);
        if (s.e) addRes(acc, 'hero_exp', s.e, 'reset_refund', `hero:${h.id}`);
        run('UPDATE level_ops SET reverted=1 WHERE hero_id=? AND reverted=0', h.id);
        run('UPDATE heroes SET level=1 WHERE id=?', h.id);
      }
      return { level: 1, refunded: { gold: s.g, hero_exp: s.e }, balances: balances(acc) };
    });
  }

  // ---------- бой ----------
  const isMaintenance = () => one("SELECT v FROM settings WHERE k='maintenance'")?.v === '1';
  const defOf = (list, key) => list.find((x) => x.key === key);

  function startBattle(acc, stageN, opts = {}) {
    if (isMaintenance()) throw new GameError('maintenance', 'Технические работы', 503);
    const c = getContent(); // версия закрепляется на момент начала
    const stage = c.stages.find((s) => s.n === stageN);
    if (!stage) throw new GameError('no_stage', 'Этап не найден', 404);
    const cleared = new Set(q('SELECT stage FROM stage_progress WHERE account_id=? AND cleared=1', acc).map((r) => r.stage));
    if (stageN > 1 && !cleared.has(stageN - 1)) throw new GameError('locked', `Сначала пройдите этап ${stageN - 1}`, 403);

    const slots = JSON.parse(one('SELECT slots FROM formations WHERE account_id=?', acc).slots);
    const owned = Object.fromEntries(q('SELECT id,hero_key,level FROM heroes WHERE account_id=?', acc).map((r) => [r.id, r]));
    const g = c.progression.growth;
    const attackers = slots.map((hid, i) => { const o = owned[hid]; return buildUnit(defOf(c.heroes, o.hero_key), o.level, g, 'a', i, `a${i}`); });
    const defenders = stage.enemies.map((e, i) => {
      if (!e) return null;
      const d = structuredClone(defOf(c.enemies, e.key));
      d.stats.hp *= stage.power; d.stats.atk *= stage.power;
      return buildUnit(d, e.level, g, 'd', i, `d${i}`);
    });
    const seed = opts.seed ?? randomInt(1, 2 ** 31);
    const res = simulate({ attackers, defenders, seed, config: { ...c.battle, bounds: c.arena?.bounds } });
    const id = randomUUID();

    // Бой, результат и награда — одна транзакция; награда за первую победу выдаётся ровно один раз.
    return tx(db, () => {
      let reward = null;
      if (res.winner === 'attacker') {
        const claimed = one('SELECT 1 FROM reward_claims WHERE account_id=? AND stage=?', acc, stageN);
        run('INSERT OR IGNORE INTO stage_progress(account_id,stage,cleared) VALUES(?,?,1)', acc, stageN);
        if (!claimed) {
          run('INSERT INTO reward_claims(account_id,stage,battle_id) VALUES(?,?,?)', acc, stageN, id);
          for (const [cur, amt] of Object.entries(stage.reward)) addRes(acc, cur, amt, 'stage_first_win', `battle:${id}`);
          reward = stage.reward;
        }
      }
      run('INSERT INTO battles(id,account_id,stage,content_version,seed,winner,timeout,duration,events,reward,created) VALUES(?,?,?,?,?,?,?,?,?,?,?)',
        id, acc, stageN, c.id, seed, res.winner, res.timeout ? 1 : 0, res.duration, JSON.stringify(res.events), reward ? JSON.stringify(reward) : null, now());
      return { battleId: id, stage: stageN, contentVersion: c.id, winner: res.winner, timeout: res.timeout, duration: res.duration, reward, events: res.events, balances: balances(acc) };
    });
  }

  // Повторное получение результата после обрыва связи — награда уже выдана и повторно не начисляется.
  function getBattle(acc, id) {
    const b = one('SELECT * FROM battles WHERE id=? AND account_id=?', id, acc);
    if (!b) throw new GameError('no_battle', 'Бой не найден', 404);
    return { battleId: b.id, stage: b.stage, contentVersion: b.content_version, winner: b.winner, timeout: !!b.timeout, duration: b.duration, reward: b.reward ? JSON.parse(b.reward) : null, events: JSON.parse(b.events), balances: balances(acc) };
  }

  return { db, audit, syncContentFromFile, getContent, currentVersionId, listVersions, getVersion, diffVersions, publishContent, rollbackTo, getContent, guest, authenticate, bind, login, recover, me, setFormation, setTutorialDone, upgradeHero, resetHero, startBattle, getBattle, addRes, balances, isMaintenance, q, one, run };
}

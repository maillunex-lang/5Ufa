import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

const SCHEMA = `
CREATE TABLE IF NOT EXISTS accounts(id INTEGER PRIMARY KEY, created INTEGER NOT NULL, login TEXT UNIQUE, pass_hash TEXT, recovery_hash TEXT, banned INTEGER NOT NULL DEFAULT 0, tutorial_done INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY, account_id INTEGER NOT NULL, created INTEGER NOT NULL, last_seen INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS heroes(id INTEGER PRIMARY KEY, account_id INTEGER NOT NULL, hero_key TEXT NOT NULL, level INTEGER NOT NULL DEFAULT 1, UNIQUE(account_id, hero_key));
CREATE TABLE IF NOT EXISTS balances(account_id INTEGER NOT NULL, currency TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount>=0), PRIMARY KEY(account_id, currency));
CREATE TABLE IF NOT EXISTS resource_ops(id INTEGER PRIMARY KEY, account_id INTEGER NOT NULL, kind TEXT NOT NULL, currency TEXT NOT NULL, delta INTEGER NOT NULL, ref TEXT, created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS level_ops(id INTEGER PRIMARY KEY, hero_id INTEGER NOT NULL, from_level INTEGER NOT NULL, to_level INTEGER NOT NULL, gold INTEGER NOT NULL, hero_exp INTEGER NOT NULL, reverted INTEGER NOT NULL DEFAULT 0, created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS formations(account_id INTEGER PRIMARY KEY, slots TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS stage_progress(account_id INTEGER NOT NULL, stage INTEGER NOT NULL, cleared INTEGER NOT NULL, PRIMARY KEY(account_id, stage));
CREATE TABLE IF NOT EXISTS reward_claims(account_id INTEGER NOT NULL, stage INTEGER NOT NULL, battle_id TEXT NOT NULL, PRIMARY KEY(account_id, stage));
CREATE TABLE IF NOT EXISTS battles(id TEXT PRIMARY KEY, account_id INTEGER NOT NULL, stage INTEGER NOT NULL, content_version INTEGER NOT NULL, seed INTEGER NOT NULL, winner TEXT NOT NULL, timeout INTEGER NOT NULL, duration REAL NOT NULL, events TEXT NOT NULL, reward TEXT, created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS content_versions(id INTEGER PRIMARY KEY, hash TEXT NOT NULL, json TEXT NOT NULL, note TEXT, created INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS settings(k TEXT PRIMARY KEY, v TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS audit(id INTEGER PRIMARY KEY, ts INTEGER NOT NULL, actor TEXT NOT NULL, action TEXT NOT NULL, detail TEXT);
CREATE TABLE IF NOT EXISTS error_log(id INTEGER PRIMARY KEY, ts INTEGER NOT NULL, source TEXT NOT NULL, message TEXT NOT NULL);
`;

function ensureColumn(db, table, col, ddl) {
  const cols = db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
  if (!cols.includes(col)) db.exec(`ALTER TABLE ${table} ADD COLUMN ${ddl}`);
}

export function openDb(path) {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec('PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;');
  db.exec(SCHEMA);
  // миграции существующих баз (версии контента получили источник, автора и родителя)
  ensureColumn(db, 'content_versions', 'source', 'source TEXT');
  ensureColumn(db, 'content_versions', 'author', 'author TEXT');
  ensureColumn(db, 'content_versions', 'parent', 'parent INTEGER');
  return db;
}

// Атомарная транзакция; исключение откатывает всё.
export function tx(db, fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const r = fn();
    db.exec('COMMIT');
    return r;
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}

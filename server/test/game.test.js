import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { openDb } from '../src/db.js';
import { createGame, GameError } from '../src/game.js';
import { buildUnit, simulate } from '../src/battle.js';
import { loadContentFile } from '../src/content.js';

const contentPath = fileURLToPath(new URL('../../content/game.json', import.meta.url));
const mk = () => createGame(openDb(':memory:'), { contentPath });
const content = () => JSON.parse(loadContentFile(contentPath).json);

function unit(c, key, side, slot, over = {}) {
  const d = structuredClone([...c.heroes, ...c.enemies].find((x) => x.key === key));
  Object.assign(d.stats, over);
  return buildUnit(d, 1, c.progression.growth, side, slot, `${side}${slot}`);
}
const sim = (c, a, d, seed = 1) => simulate({ attackers: a, defenders: d, seed, config: c.battle });

// ---- бой ----
test('крит бывает только у базовой атаки', () => {
  const c = content();
  const A = [unit(c, 'archer', 'a', 0, { critChance: 1 }), null, null, null, null];
  const D = [unit(c, 'e_boss', 'd', 0, { hp: 99999 }), null, null, null, null];
  const r = sim(c, A, D);
  const dmg = r.events.filter((e) => e.type === 'damage' && e.src === 'a0');
  assert.ok(dmg.some((e) => e.ability === 'arc_basic' && e.crit));
  assert.ok(dmg.some((e) => e.ability === 'arc_power'));
  assert.ok(dmg.filter((e) => e.ability !== 'arc_basic').every((e) => !e.crit));
});

test('главная способность срабатывает автоматически при полной энергии и обнуляет её', () => {
  const c = content();
  const r = sim(c, [unit(c, 'mage', 'a', 0), null, null, null, null], [unit(c, 'e_boss', 'd', 0, { hp: 99999 }), null, null, null, null]);
  assert.ok(r.events.some((e) => e.type === 'skill' && e.ability === 'mage_main'));
});

test('целитель лечит минимальный % здоровья, включая себя', () => {
  const c = content();
  const healer = unit(c, 'healer', 'a', 0); healer.hp = Math.round(healer.maxHp * 0.3);
  const tank = unit(c, 'tank', 'a', 1); tank.hp = Math.round(tank.maxHp * 0.6);
  const r = sim(c, [healer, tank, null, null, null], [unit(c, 'e_fighter', 'd', 0, { hp: 99999, atk: 1 }), null, null, null, null]);
  const first = r.events.find((e) => e.type === 'heal');
  assert.equal(first.dst, 'a0'); // сам целитель — 30% против 60%
});

test('целитель не тратит лечение при полном здоровье команды', () => {
  const c = content();
  const r = sim(c, [unit(c, 'healer', 'a', 0), unit(c, 'tank', 'a', 1), null, null, null], [unit(c, 'e_fighter', 'd', 0, { hp: 400, atk: 1 }), null, null, null, null]);
  assert.equal(r.events.filter((e) => e.type === 'heal').length, 0);
  assert.ok(r.events.some((e) => e.type === 'damage' && e.src === 'a0')); // атакует уроном
});

test('тайм-аут 90 с = поражение атакующего', () => {
  const c = content();
  const r = sim(c, [unit(c, 'healer', 'a', 0, { atk: 1 }), null, null, null, null], [unit(c, 'e_boss', 'd', 0, { hp: 1e7, atk: 1 }), null, null, null, null]);
  assert.equal(r.timeout, true);
  assert.equal(r.winner, 'defender');
  assert.ok(r.duration >= 89.9 && r.duration <= 90.1);
});

test('симуляция детерминирована по seed', () => {
  const c = content();
  const mkTeam = () => [[unit(c, 'archer', 'a', 0), unit(c, 'tank', 'a', 1), null, null, null], [unit(c, 'e_fighter', 'd', 0), unit(c, 'e_mage', 'd', 1), null, null, null]];
  const [a1, d1] = mkTeam(), [a2, d2] = mkTeam();
  assert.deepEqual(sim(c, a1, d1, 7).events, sim(c, a2, d2, 7).events);
});

// ---- контент ----
test('в контенте 5 героев, 10 этапов, босс на 10-м', () => {
  const c = content();
  assert.equal(c.heroes.length, 5);
  assert.equal(c.stages.length, 10);
  assert.equal(c.stages[9].enemies[0].key, 'e_boss');
  const kinds = (k) => c.heroes.find((h) => h.key === k).abilities.map((a) => a.kind).sort();
  assert.deepEqual(kinds('tank'), ['basic', 'main', 'passive', 'passive']);
  assert.deepEqual(kinds('mage'), ['basic', 'main', 'passive', 'passive']);
  for (const k of ['warrior', 'archer', 'healer']) assert.deepEqual(kinds(k), ['basic', 'skill']);
});

// ---- аккаунты и прогресс ----
test('гость получает 5 героев и расстановку; привязка и восстановление', () => {
  const g = mk();
  const { token } = g.guest();
  const acc = g.authenticate(token);
  const m = g.me(acc);
  assert.equal(m.heroes.length, 5);
  assert.equal(m.formation.length, 5);
  const { recoveryCode } = g.bind(acc, 'Player_1', 'password123');
  assert.throws(() => g.login('player_1', 'wrongpass1'), GameError);
  assert.equal(g.authenticate(g.login('player_1', 'password123').token), acc);
  const rec = g.recover('player_1', recoveryCode.toLowerCase(), 'newpassword1');
  assert.notEqual(rec.recoveryCode, recoveryCode);
  assert.throws(() => g.recover('player_1', recoveryCode, 'another-pass1'), GameError); // старый код сгорел
  assert.equal(g.authenticate(rec.token), acc);
  assert.throws(() => g.authenticate(token), GameError); // старые сессии закрыты
});

test('награда за первую победу выдаётся ровно один раз', () => {
  const g = mk();
  const acc = g.authenticate(g.guest().token);
  // усилим героев, чтобы победа была надёжной
  for (let i = 0; i < 3; i++) for (const h of g.me(acc).heroes) { try { g.upgradeHero(acc, h.id); } catch { /* ресурсов может не хватить */ } }
  let first;
  for (let s = 0; s < 5 && !first?.reward; s++) first = g.startBattle(acc, 1, { seed: 100 + s });
  assert.equal(first.winner, 'attacker', 'тестовые герои должны побеждать на этапе 1');
  assert.ok(first.reward);
  const gold1 = g.balances(acc).gold;
  const again = g.startBattle(acc, 1, { seed: 5 });
  assert.equal(again.reward, null);
  assert.equal(g.balances(acc).gold, gold1);
  // повторный запрос результата (реконнект) не меняет баланс
  assert.equal(g.getBattle(acc, first.battleId).reward.gold, first.reward.gold);
  assert.equal(g.balances(acc).gold, gold1);
});

test('сброс уровня возвращает фактически потраченное, даже если цены изменились', () => {
  const g = mk();
  const acc = g.authenticate(g.guest().token);
  const before = g.balances(acc);
  const hid = g.me(acc).heroes[0].id;
  g.upgradeHero(acc, hid); g.upgradeHero(acc, hid); g.upgradeHero(acc, hid);
  // меняем цены: публикуем новую версию контента
  const c = structuredClone(g.getContent()); delete c.id;
  c.progression.upgradeCost = { gold: 9999, hero_exp: 9999 };
  g.run('INSERT INTO content_versions(hash,json,note,created) VALUES(?,?,?,?)', 'x', JSON.stringify(c), 'test', Date.now());
  const r = g.resetHero(acc, hid);
  assert.deepEqual(g.balances(acc), before);
  assert.equal(r.level, 1);
  assert.deepEqual(g.resetHero(acc, hid).refunded, { gold: 0, hero_exp: 0 }); // повторный сброс ничего не создаёт
  assert.deepEqual(g.balances(acc), before);
});

test('текущий бой остаётся на версии контента, закреплённой при старте', () => {
  const g = mk();
  const acc = g.authenticate(g.guest().token);
  const b = g.startBattle(acc, 1, { seed: 1 });
  const v1 = b.contentVersion;
  const c = structuredClone(g.getContent()); delete c.id;
  g.run('INSERT INTO content_versions(hash,json,note,created) VALUES(?,?,?,?)', 'y', JSON.stringify(c), 'test', Date.now());
  assert.equal(g.getBattle(acc, b.battleId).contentVersion, v1);
  assert.equal(g.startBattle(acc, 1, { seed: 2 }).contentVersion, v1 + 1);
});

test('этапы открываются по порядку; техработы блокируют новые бои', () => {
  const g = mk();
  const acc = g.authenticate(g.guest().token);
  assert.throws(() => g.startBattle(acc, 2), (e) => e.code === 'locked');
  g.run("INSERT OR REPLACE INTO settings(k,v) VALUES('maintenance','1')");
  assert.throws(() => g.startBattle(acc, 1), (e) => e.code === 'maintenance');
});

test('формация валидируется; нельзя списать больше, чем есть', () => {
  const g = mk();
  const acc = g.authenticate(g.guest().token);
  const ids = g.me(acc).heroes.map((h) => h.id);
  assert.throws(() => g.setFormation(acc, [ids[0], ids[0], ids[1], ids[2], ids[3]]), GameError);
  assert.deepEqual(g.setFormation(acc, [...ids].reverse()).formation, [...ids].reverse());
  assert.throws(() => g.addRes(acc, 'gold', -999999, 'x'), (e) => e.code === 'not_enough');
});

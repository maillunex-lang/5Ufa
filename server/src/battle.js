// Серверная симуляция боя 5x5. Детерминирована по seed. Клиент лишь воспроизводит events.
// ВСЕ числа (тик, энергия, формула защиты) — ТЕСТОВЫЕ, берутся из config (content/game.json -> battle).

export function makeRng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const r1 = (n) => Math.round(n * 10) / 10;

// def: {key,name,stats,abilities}; level; growth — рост за уровень (доля от базы)
export function buildUnit(def, level, growth, side, slot, id) {
  const g = 1 + growth * (level - 1);
  const s = { ...def.stats };
  for (const k of ['hp', 'atk', 'def']) s[k] = s[k] * g;
  for (const a of def.abilities) {
    if (a.kind !== 'passive') continue;
    for (const [k, m] of Object.entries(a.mods || {})) if (s[k] !== undefined) s[k] *= m;
  }
  const abilities = def.abilities.filter((a) => a.kind !== 'passive').map((a) => ({ ...a, cd: 0 }));
  return {
    id, key: def.key, side, slot, level,
    hp: Math.round(s.hp), maxHp: Math.round(s.hp),
    atk: s.atk, def: s.def, critChance: s.critChance, critPower: s.critPower,
    range: s.range, interval: s.interval, speed: s.speed,
    energy: 0, atkTimer: 0, target: null, alive: true, abilities,
    // стартовая позиция: перед (2) x=±2, зад (3) x=±4; игрок слева (x<0)
    x: (side === 'a' ? -1 : 1) * (slot < 2 ? 2 : 4),
    y: (slot < 2 ? [-1, 1][slot] * 1.2 : [-2.4, 0, 2.4][slot - 2]),
    moving: false,
    moveTarget: null,
  };
}

export function simulate({ attackers, defenders, seed, config }) {
  const rand = makeRng(seed);
  const C = config;
  const units = [...attackers.filter(Boolean), ...defenders.filter(Boolean)];
  const events = [];
  let t = 0;
  const ev = (type, o) => events.push({ t: r1(t), type, ...o });
  const alive = (side) => units.filter((u) => u.alive && u.side === side);
  const foes = (u) => alive(u.side === 'a' ? 'd' : 'a');
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

  ev('start', { units: units.map((u) => ({ id: u.id, key: u.key, side: u.side, slot: u.slot, level: u.level, hp: u.maxHp, x: u.x, y: u.y })) });

  const gainEnergy = (u, n) => {
    if (!u.alive || !u.abilities.some((a) => a.kind === 'main')) return;
    u.energy = Math.min(C.energyMax, u.energy + n);
    ev('energy', { id: u.id, value: u.energy }); // для полосы энергии в клиенте
  };

  function hit(src, dst, mult, canCrit, abilityId) {
    let dmg = src.atk * mult * (C.defConst / (C.defConst + dst.def));
    let crit = false;
    if (canCrit && rand() < src.critChance) { dmg *= src.critPower; crit = true; }
    dmg = Math.max(1, Math.round(dmg));
    dst.hp = Math.max(0, dst.hp - dmg);
    ev('damage', { src: src.id, dst: dst.id, amount: dmg, crit, ability: abilityId, hp: dst.hp });
    gainEnergy(dst, C.energyOnDamaged);
    if (dst.hp === 0) { dst.alive = false; dst.moving = false; dst.moveTarget = null; ev('death', { id: dst.id }); }
  }

  function lowestAlly(u) {
    return alive(u.side).reduce((best, c) => {
      if (!best) return c;
      const pc = c.hp / c.maxHp, pb = best.hp / best.maxHp;
      return pc < pb || (pc === pb && c.slot < best.slot) ? c : best; // ничья: меньший слот
    }, null);
  }

  function pickTarget(u) {
    const cur = u.target;
    if (cur && cur.alive) return cur; // цель сохраняется до недоступности
    const list = foes(u);
    let best = null;
    for (const f of list) if (!best || dist(u, f) < dist(u, best) - 1e-9 || (Math.abs(dist(u, f) - dist(u, best)) < 1e-9 && f.slot < best.slot)) best = f;
    u.target = best;
    return best;
  }

  function act(u) {
    const main = u.abilities.find((a) => a.kind === 'main');
    const mainReady = main && u.energy >= C.energyMax;
    const cand = [];
    if (mainReady) cand.push(main);
    for (const a of u.abilities) if (a.kind === 'skill' && a.cd <= 0) cand.push(a); // приоритет: главная > навык > базовая
    cand.push(u.abilities.find((a) => a.kind === 'basic'));
    for (const a of cand) {
      if (!a) continue;
      if (a.effect === 'heal') {
        const ally = lowestAlly(u);
        if (!ally || ally.hp >= ally.maxHp) continue; // все здоровы — лечение не тратится
        const amt = Math.min(ally.maxHp - ally.hp, Math.round(u.atk * a.mult));
        ally.hp += amt;
        a.cd = a.cooldown;
        ev('heal', { src: u.id, dst: ally.id, amount: amt, hp: ally.hp, ability: a.id });
        gainEnergy(u, C.energyOnAttack);
        return true;
      }
      const tgt = u.target;
      if (dist(u, tgt) > u.range + 1e-6) continue;
      ev(a.kind === 'basic' ? 'attack' : 'skill', { src: u.id, dst: tgt.id, ability: a.id });
      const targets = a.effect === 'aoe' ? foes(u) : [tgt];
      for (const d of targets) if (d.alive) hit(u, d, a.mult, a.kind === 'basic', a.id);
      if (a.kind === 'main') { u.energy = 0; ev('energy', { id: u.id, value: 0 }); } else gainEnergy(u, C.energyOnAttack);
      if (a.cooldown) a.cd = a.cooldown;
      return true;
    }
    return false;
  }

  const total = Math.round(C.timeLimit / C.tick);
  for (let i = 0; i < total && alive('a').length && alive('d').length; i++) {
    t = i * C.tick;
    for (const u of units) {
      if (!u.alive) continue;
      u.atkTimer = Math.max(0, u.atkTimer - C.tick);
      for (const a of u.abilities) a.cd = Math.max(0, a.cd - C.tick);
      const tgt = pickTarget(u);
      if (!tgt) break;
      if (dist(u, tgt) > u.range) {
        // подбегание к своей свободной точке рядом с целью (без расталкивания)
        const dir = u.side === 'a' ? -1 : 1;
        let gx = tgt.x + dir * Math.max(0.6, u.range * 0.9);
        let gy = tgt.y + (u.slot - 2) * 0.5;
        const B = C.bounds; // прямоугольник арены: за него бойцы не выходят (цель внутри, значит точка после обрезки только ближе к ней)
        if (B) { gx = Math.min(B.xMax, Math.max(B.xMin, gx)); gy = Math.min(B.yMax, Math.max(B.yMin, gy)); }
        const dx = gx - u.x, dy = gy - u.y, d = Math.hypot(dx, dy);
        if (d < 1e-6) continue; // уже в точке (упёрлись в границу), ждём без лишних событий
        const step = Math.min(d, u.speed * C.tick);
        // Клиент двигает бойца только по событиям: заново сообщаем цель пути при старте и при смене цели
        if (!u.moving || u.moveTarget !== tgt.id) {
          u.moving = true;
          u.moveTarget = tgt.id;
          ev('move', { id: u.id, to: [r1(gx), r1(gy)], speed: u.speed });
        }
        if (d > 1e-6) { u.x += (dx / d) * step; u.y += (dy / d) * step; }
        if (d - step < 1e-6 || dist(u, tgt) <= u.range) { // остановился: сообщаем точное место
          u.moving = false;
          u.moveTarget = null;
          ev('stop', { id: u.id, x: r1(u.x), y: r1(u.y) });
        }
        continue;
      }
      if (u.moving) { // цель оказалась в зоне досягаемости без дохода до точки
        u.moving = false;
        u.moveTarget = null;
        ev('stop', { id: u.id, x: r1(u.x), y: r1(u.y) });
      }
      if (u.atkTimer <= 0 && act(u)) u.atkTimer = u.interval;
    }
  }
  t = Math.min(C.timeLimit, t + C.tick);
  const aLeft = alive('a').length, dLeft = alive('d').length;
  const timeout = aLeft > 0 && dLeft > 0;
  const winner = dLeft === 0 && aLeft > 0 ? 'attacker' : 'defender'; // таймаут — проигрыш атакующего
  ev('end', { winner, timeout });
  return { winner, timeout, duration: r1(t), events, survivors: units.filter((u) => u.alive).map((u) => ({ id: u.id, hp: u.hp, x: u.x, y: u.y })) };
}

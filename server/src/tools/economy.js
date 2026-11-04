// Проверка экономики на тестовых значениях: проходит кампанию, вкладывая ресурсы поровну в героев.
// Запуск: npm run economy
import { fileURLToPath } from 'node:url';
import { openDb } from '../db.js';
import { createGame } from '../game.js';

const contentPath = fileURLToPath(new URL('../../../content/game.json', import.meta.url));
const g = createGame(openDb(':memory:'), { contentPath });
const acc = g.authenticate(g.guest().token);
const spend = () => {
  for (let moved = true; moved;) {
    moved = false;
    const hs = g.me(acc).heroes.sort((a, b) => a.level - b.level);
    for (const h of hs) { try { g.upgradeHero(acc, h.id); moved = true; break; } catch { /* нет ресурсов/макс */ } }
  }
};
for (let s = 1; s <= 10; s++) {
  spend();
  const lv = g.me(acc).heroes.map((h) => h.level).join(',');
  let wins = 0, tries = 8;
  for (let i = 0; i < tries; i++) {
    // пробные прогоны на копии не нужны: награда одноразовая, проигрыши ничего не стоят
    const r = g.startBattle(acc, s, { seed: 1000 * s + i });
    if (r.winner === 'attacker') wins++;
    if (r.winner === 'attacker' && i === 0) { /* первая победа забрала награду */ }
  }
  console.log(`этап ${s}: уровни героев [${lv}] побед ${wins}/${tries}`, JSON.stringify(g.balances(acc)));
  if (wins === 0) { console.log('  ! этап не проходится при уровнях выше — баланс/награды надо править'); break; }
}

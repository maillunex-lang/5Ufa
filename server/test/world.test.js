import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openDb } from '../src/db.js';
import { createGame } from '../src/game.js';
import { validateContent, loadContentFile } from '../src/content.js';
import { createMedia } from '../src/media.js';

const contentPath = fileURLToPath(new URL('../../content/game.json', import.meta.url));
const raw = () => JSON.parse(loadContentFile(contentPath).json);

function glb(clipName = 'Idle') {
  const json = {
    asset: { version: '2.0', generator: 'test' },
    nodes: [{ name: 'mixamorig:Hips' }, { name: 'mixamorig:Spine' }],
    skins: [{ joints: [0, 1] }],
    accessors: [{ count: 2, type: 'SCALAR', componentType: 5126, max: [1.5], min: [0] }, { count: 2, type: 'VEC3', componentType: 5126 }],
    animations: [{ name: clipName, samplers: [{ input: 0, output: 1 }], channels: [] }],
  };
  let j = Buffer.from(JSON.stringify(json));
  j = Buffer.concat([j, Buffer.alloc((4 - (j.length % 4)) % 4, 0x20)]);
  const head = Buffer.alloc(20);
  head.writeUInt32LE(0x46546c67, 0); head.writeUInt32LE(2, 4); head.writeUInt32LE(20 + j.length, 8);
  head.writeUInt32LE(j.length, 12); head.writeUInt32LE(0x4e4f534a, 16);
  return Buffer.concat([head, j]);
}

test('демо-мир проходит проверку и не заменяет боевые этапы', () => {
  const c = raw();
  assert.equal(c.world.schema, 1);
  assert.equal(c.world._demo, true);
  assert.equal(c.stages.length, 10);
  assert.equal(c.world.quests.find((q) => q.id === 'q_trail').stage, 1);
  assert.equal(c.world.proposals.status, 'proposal');
  assert.equal(c.world.proposals.chosen, undefined);
  assert.ok(c.world.placeStates.length >= 2);
  assert.deepEqual(validateContent(c), []);
  assert.equal(c.ui.shell.buildings.map((b) => b.id).join(','), 'portal,arena,dungeons,guild,shop');
});

test('старый контент без мира по-прежнему принимается, битая ссылка — нет', () => {
  const c = raw();
  delete c.world;
  delete c.ui;
  for (const h of c.heroes) { delete h.faction; delete h.rarity; delete h.prompt; delete h._display_test; }
  assert.deepEqual(validateContent(c), []);
  const bad = raw();
  bad.world.places[0].districtId = 'no_such';
  assert.ok(validateContent(bad).some((e) => e.includes('нет района')));
  const loop = raw();
  loop.world.quests[0].unlock = 'quest:q_light';
  loop.world.quests[2].unlock = 'quest:q_whisper';
  assert.ok(validateContent(loop).some((e) => e.includes('зациклены')));
  const shell = raw();
  delete shell.ui.shell;
  assert.deepEqual(validateContent(shell), []);
  const fake = raw();
  fake.ui.shell.buildings[2].action = 'tab:1';
  assert.ok(validateContent(fake).some((e) => e.includes('не открывает экран')));
});

test('сюжет не выдаёт награду и не мешает старому прогрессу этапа', () => {
  const game = createGame(openDb(':memory:'), { contentPath });
  const acc = game.authenticate(game.guest().token);
  const before = game.me(acc);
  assert.deepEqual(before.storyDone, []);
  assert.deepEqual(before.clearedStages, []);
  const gold = before.balances.gold;
  const done = game.completeStory(acc, 'q_whisper');
  assert.deepEqual(done.storyDone, ['q_whisper']);
  assert.equal(game.completeStory(acc, 'q_whisper').storyDone.length, 1);
  assert.throws(() => game.completeStory(acc, 'q_light'), (e) => e.code === 'locked');
  assert.throws(() => game.completeStory(acc, 'q_trail'), (e) => e.code === 'no_quest');
  const me = game.me(acc);
  assert.equal(me.balances.gold, gold);
  assert.deepEqual(me.clearedStages, []);
  game.run('INSERT INTO stage_progress(account_id, stage, cleared) VALUES(?,?,1)', acc, 1);
  const later = game.completeStory(acc, 'q_light');
  assert.deepEqual(later.storyDone, ['q_light', 'q_whisper']);
  const after = game.me(acc);
  assert.deepEqual(after.clearedStages, [1]);
  assert.equal(after.balances.gold, gold);
});

test('карточка медиатеки: папка и теги живут на имени и копируются в новую версию', () => {
  const db = openDb(':memory:');
  const media = createMedia({ db, dir: mkdtempSync(join(tmpdir(), '5ufa-media-')), audit: () => {} });
  media.upload({ name: 'Hero_A', kind: 'model', buf: glb(), filename: 'a.glb' });
  const card = media.setCard('Hero_A', { folder: 'герои', tags: 'временное, тест', license: 'проект', requirements: 'GLB до 40 МБ', prompt: 'портрет' });
  assert.equal(card.folder, 'герои');
  assert.equal(card.tags, 'временное, тест');
  media.upload({ name: 'Hero_A', kind: 'model', buf: glb('Run'), filename: 'b.glb' });
  const again = media.list().find((m) => m.name === 'Hero_A');
  assert.equal(again.folder, 'герои');
  assert.equal(again.versions.length, 2);
  assert.throws(() => media.setCard('Hero_A', { folder: '../secret' }), (e) => e.code === 'bad_folder');
});

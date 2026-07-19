import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('..', import.meta.url));
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const legacyRoster = [
  'fengying', 'lieyan', 'tianqiong', 'anmu', 'lieying', 'shengyu', 'leiyi',
  'zhuying', 'lanqie', 'qingzhen', 'lingshi', 'yinglie', 'meiying', 'lingyu',
];

test('selection and HUD use generated official media', () => {
  const main = read('scripts/main.gd');
  const hud = read('scripts/hud.gd');
  assert.match(main, /a\["portrait"\]/);
  assert.match(main, /TextureRect/);
  assert.match(main, /var diffs := HFlowContainer\.new\(\)/);
  assert.match(main, /var btn_row := HFlowContainer\.new\(\)/);
  assert.doesNotMatch(main, /WASD 移动/);
  assert.match(hud, /sl\["def"\]\["icon"\]/);
  assert.match(hud, /resource_l/);
  assert.match(hud, /cd_until/);
  assert.match(hud, /ability_state/);
});

test('user-visible source no longer advertises the legacy roster or counts', () => {
  const visible = [read('scripts/main.gd'), read('scripts/hud.gd'), read('README.md')].join('\n');
  for (const id of legacyRoster) assert.doesNotMatch(visible, new RegExp(id, 'i'), id);
  assert.doesNotMatch(visible, /10 张地图|11 名特工|11 特工/);
  assert.match(visible, /29 名特工/);
  assert.match(visible, /16 张地图/);
});

test('player input drives controlled scout mode', () => {
  const player = read('scripts/player.gd');
  assert.match(player, /main\.steer_controlled_unit\(self, dt\)/);
  assert.match(player, /main\.activate_controlled_unit\(self\)/);
  assert.match(player, /main\.end_controlled_unit\(self\)/);
});

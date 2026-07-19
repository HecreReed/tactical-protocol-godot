import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('..', import.meta.url));
const read = (path) => readFileSync(resolve(root, path), 'utf8');
const readBuffer = (path) => readFileSync(resolve(root, path));
const legacyRoster = [
  'fengying', 'lieyan', 'tianqiong', 'anmu', 'lieying', 'shengyu', 'leiyi',
  'zhuying', 'lanqie', 'qingzhen', 'lingshi', 'yinglie', 'meiying', 'lingyu',
];

const u16 = (buffer, offset) => buffer.readUInt16BE(offset);
const u32 = (buffer, offset) => buffer.readUInt32BE(offset);

function cmapSubtables(font) {
  const tableCount = u16(font, 4);
  let cmapOffset = -1;
  for (let index = 0; index < tableCount; index += 1) {
    const record = 12 + index * 16;
    if (font.toString('ascii', record, record + 4) === 'cmap') {
      cmapOffset = u32(font, record + 8);
      break;
    }
  }
  assert.notEqual(cmapOffset, -1, 'font must contain a cmap table');
  const subtables = [];
  const count = u16(font, cmapOffset + 2);
  for (let index = 0; index < count; index += 1) {
    const record = cmapOffset + 4 + index * 8;
    const offset = cmapOffset + u32(font, record + 4);
    const format = u16(font, offset);
    if (format === 4 || format === 12) subtables.push({ format, offset });
  }
  return subtables;
}

function format4Glyph(font, offset, codePoint) {
  if (codePoint > 0xffff) return 0;
  const segmentCount = u16(font, offset + 6) / 2;
  const endCodes = offset + 14;
  const startCodes = endCodes + segmentCount * 2 + 2;
  const deltas = startCodes + segmentCount * 2;
  const rangeOffsets = deltas + segmentCount * 2;
  for (let index = 0; index < segmentCount; index += 1) {
    const end = u16(font, endCodes + index * 2);
    if (codePoint > end) continue;
    const start = u16(font, startCodes + index * 2);
    if (codePoint < start) return 0;
    const delta = font.readInt16BE(deltas + index * 2);
    const rangeOffsetAddress = rangeOffsets + index * 2;
    const rangeOffset = u16(font, rangeOffsetAddress);
    if (rangeOffset === 0) return (codePoint + delta) & 0xffff;
    const glyphAddress = rangeOffsetAddress + rangeOffset + (codePoint - start) * 2;
    const glyph = u16(font, glyphAddress);
    return glyph === 0 ? 0 : (glyph + delta) & 0xffff;
  }
  return 0;
}

function format12Glyph(font, offset, codePoint) {
  const groupCount = u32(font, offset + 12);
  for (let index = 0; index < groupCount; index += 1) {
    const group = offset + 16 + index * 12;
    const start = u32(font, group);
    const end = u32(font, group + 4);
    if (codePoint < start) return 0;
    if (codePoint <= end) return u32(font, group + 8) + codePoint - start;
  }
  return 0;
}

function hasGlyph(font, subtables, codePoint) {
  return subtables.some(({ format, offset }) => (
    format === 12
      ? format12Glyph(font, offset, codePoint) !== 0
      : format4Glyph(font, offset, codePoint) !== 0
  ));
}

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

test('bundled font covers synchronized Chinese UI text', () => {
  const font = readBuffer('assets/fonts/NotoSansSC-sub.otf');
  const subtables = cmapSubtables(font);
  const dataText = [read('data/agents.json'), read('data/maps.json')].join('\n');
  const scriptText = [
    'scripts/main.gd', 'scripts/hud.gd', 'scripts/player.gd',
    'scripts/match_mgr.gd', 'scripts/abilities.gd',
  ].flatMap((path) => [...read(path).matchAll(/"(?:\\.|[^"\\])*"/g)].map((match) => match[0])).join('\n');
  const required = new Set([...dataText, ...scriptText]
    .map((character) => character.codePointAt(0))
    .filter((codePoint) => (
      (codePoint >= 0x2e80 && codePoint <= 0x9fff)
      || (codePoint >= 0xf900 && codePoint <= 0xfaff)
    )));

  for (const codePoint of required) {
    assert.ok(
      hasGlyph(font, subtables, codePoint),
      `font missing U+${codePoint.toString(16).toUpperCase()} (${String.fromCodePoint(codePoint)})`,
    );
  }
});

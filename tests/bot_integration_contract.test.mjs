import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = fileURLToPath(new URL('..', import.meta.url));
const bot = readFileSync(`${root}/scripts/bot_ai.gd`, 'utf8');

test('combat bots feed the upstream generic utility context', () => {
  assert.match(bot, /Ab\.bot_utility_intent/);
  assert.match(bot, /safe_time/);
  assert.match(bot, /enemy_channeling/);
  assert.match(bot, /safe_escape/);
  assert.match(bot, /retaking/);
  assert.match(bot, /dangerous_sightline/);
  assert.match(bot, /team_role/);
  assert.match(bot, /has_primary/);
});

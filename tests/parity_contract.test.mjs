import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import test from 'node:test';

const repoRoot = fileURLToPath(new URL('..', import.meta.url));
const commonDirOutput = execFileSync(
  'git',
  ['rev-parse', '--git-common-dir'],
  { cwd: repoRoot, encoding: 'utf8' },
).trim();
const commonDir = resolve(repoRoot, commonDirOutput);
const csgoDir = process.env.TP_CSGO_DIR ?? resolve(dirname(commonDir), '..', 'csgo');

const { AGENTS: upstreamAgents, AGENT_LIST } = await import(
  pathToFileURL(resolve(csgoDir, 'src/agentCatalog.js'))
);
const { MAPS: upstreamMaps, WORLD: upstreamWorld } = await import(
  pathToFileURL(resolve(csgoDir, 'src/mapData.js'))
);

const readJson = (path) => JSON.parse(readFileSync(path, 'utf8'));
const colorHex = (color) => `#${color.toString(16).padStart(6, '0')}`;
const expectedAssetPath = (id, filename) => `res://assets/agents/${id}/${filename}`;

test('generated Godot catalog matches the current csgo source', () => {
  const generated = readJson(resolve(repoRoot, 'data/agents.json'));

  assert.equal(typeof generated.sourceCommit, 'string');
  assert.match(generated.sourceCommit, /^[0-9a-f]{7,40}$/);
  assert.equal(typeof generated.sourceDirty, 'boolean');
  assert.equal(generated.agents.length, 29);
  assert.equal(generated.agents.flatMap((agent) => Object.values(agent.ab)).length, 116);
  assert.deepEqual(generated.agents.map((agent) => agent.id), AGENT_LIST);
  assert.deepEqual(generated.maps, upstreamMaps.map((map) => map.id));
  assert.deepEqual(generated.summary, { agents: 29, abilities: 116, media: 145, maps: 11 });

  const implementations = [];
  for (const agent of generated.agents) {
    const upstream = upstreamAgents[agent.id];
    assert.ok(upstream, `unknown generated agent: ${agent.id}`);
    assert.deepEqual(
      {
        name: agent.name,
        role: agent.role,
        color: agent.color,
        ultCost: agent.ultCost,
        desc: agent.desc,
      },
      {
        name: upstream.name,
        role: upstream.role,
        color: colorHex(upstream.color),
        ultCost: upstream.ultCost,
        desc: upstream.desc,
      },
      `${agent.id} metadata`,
    );
    assert.equal(agent.portrait, expectedAssetPath(agent.id, 'portrait.webp'));
    assert.ok(existsSync(resolve(repoRoot, agent.portrait.replace('res://', ''))), agent.portrait);

    assert.deepEqual(Object.keys(agent.ab), ['c', 'q', 'e', 'x'], `${agent.id} slot order`);
    for (const key of ['c', 'q', 'e', 'x']) {
      const slot = agent.ab[key];
      const sourceSlot = upstream.ab[key];
      const { icon: _generatedIcon, ...generatedContract } = slot;
      const { icon: _upstreamIcon, ...upstreamContract } = sourceSlot;
      assert.deepEqual(generatedContract, upstreamContract, `${agent.id}.${key}`);
      assert.equal(slot.icon, expectedAssetPath(agent.id, `${key}.png`));
      assert.ok(existsSync(resolve(repoRoot, slot.icon.replace('res://', ''))), slot.icon);
      implementations.push(slot.impl);
    }
  }

  assert.equal(new Set(implementations).size, 116, 'ability implementation ids must be unique');
});

test('generated Godot maps match all current upstream maps', () => {
  const generated = readJson(resolve(repoRoot, 'data/maps.json'));

  assert.equal(generated.world, upstreamWorld);
  assert.equal(generated.maps.length, 11);
  assert.deepEqual(generated.maps.map((map) => map.id), upstreamMaps.map((map) => map.id));
  assert.deepEqual(generated.maps, upstreamMaps);
});

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const workflowUrl = new URL('../.github/workflows/deploy-web.yml', import.meta.url);
const smokeUrl = new URL('../tools/smoke_maps.sh', import.meta.url);
const catalogUrl = new URL('../data/agents.json', import.meta.url);
const exportPresetUrl = new URL('../export_presets.cfg', import.meta.url);
const gitignoreUrl = new URL('../.gitignore', import.meta.url);

test('web deployment fails closed and smokes every synchronized map', async () => {
  const [workflow, smoke, catalogSource, exportPreset, gitignore] = await Promise.all([
    readFile(workflowUrl, 'utf8'),
    readFile(smokeUrl, 'utf8'),
    readFile(catalogUrl, 'utf8'),
    readFile(exportPresetUrl, 'utf8'),
    readFile(gitignoreUrl, 'utf8'),
  ]);
  const catalog = JSON.parse(catalogSource);

  assert.equal(catalog.maps.length, 16);
  assert.doesNotMatch(workflow, /--import\s*\|\|\s*true/);
  assert.match(workflow, /bash tools\/smoke_maps\.sh/);
  assert.match(workflow, /--export-release "Web"/);
  assert.match(smoke, /data\/agents\.json/);
  assert.match(smoke, /SCRIPT ERROR/);
  assert.match(smoke, /ERROR:/);
  assert.match(smoke, /Failed to load script/);
  assert.match(smoke, /Parse Error/);
  assert.match(smoke, /Compile Error/);
  assert.match(smoke, /TP_AUTOSTART/);
  assert.match(smoke, /TP\\\] t=8/);
  assert.match(exportPreset, /exclude_filter="build\/\*\*"/);
  assert.match(gitignore, /^build\/$/m);
});

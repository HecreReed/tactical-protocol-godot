import { readFile } from 'node:fs/promises';

const dataPaths = ['data/agents.json', 'data/maps.json'];
const scriptPaths = [
  'scripts/main.gd',
  'scripts/hud.gd',
  'scripts/player.gd',
  'scripts/match_mgr.gd',
  'scripts/abilities.gd',
];

const dataText = (await Promise.all(dataPaths.map((path) => readFile(path, 'utf8')))).join('\n');
const scriptText = (await Promise.all(scriptPaths.map(async (path) => {
  const source = await readFile(path, 'utf8');
  return [...source.matchAll(/"(?:\\.|[^"\\])*"/g)].map((match) => match[0]).join('\n');
}))).join('\n');

process.stdout.write([...new Set([...dataText, ...scriptText])].join(''));

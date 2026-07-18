import { execFileSync } from 'node:child_process';
import { cp, mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const repoRoot = fileURLToPath(new URL('..', import.meta.url));
const commonDirOutput = execFileSync(
  'git',
  ['rev-parse', '--git-common-dir'],
  { cwd: repoRoot, encoding: 'utf8' },
).trim();
const commonDir = resolve(repoRoot, commonDirOutput);
const csgoDir = process.env.TP_CSGO_DIR ?? resolve(dirname(commonDir), '..', 'csgo');

const sourceCommit = execFileSync('git', ['rev-parse', 'HEAD'], {
  cwd: csgoDir,
  encoding: 'utf8',
}).trim();
const sourceDirty = execFileSync('git', ['status', '--porcelain'], {
  cwd: csgoDir,
  encoding: 'utf8',
}).trim().length > 0;

const { AGENTS, AGENT_LIST } = await import(
  pathToFileURL(resolve(csgoDir, 'src/agentCatalog.js'))
);
const { MAPS, WORLD } = await import(pathToFileURL(resolve(csgoDir, 'src/mapData.js')));

const slots = ['c', 'q', 'e', 'x'];
const colorHex = (color) => `#${color.toString(16).padStart(6, '0')}`;
const mediaPath = (id, filename) => `res://assets/agents/${id}/${filename}`;

const agents = AGENT_LIST.map((id) => {
  const source = AGENTS[id];
  const abilities = Object.fromEntries(slots.map((key) => [
    key,
    { ...source.ab[key], icon: mediaPath(id, `${key}.png`) },
  ]));
  return {
    id,
    name: source.name,
    role: source.role,
    color: colorHex(source.color),
    ultCost: source.ultCost,
    desc: source.desc,
    portrait: mediaPath(id, 'portrait.webp'),
    ab: abilities,
  };
});

const implementations = agents.flatMap((agent) => slots.map((key) => agent.ab[key].impl));
if (agents.length !== 29) throw new Error(`expected 29 agents, found ${agents.length}`);
if (implementations.length !== 116) {
  throw new Error(`expected 116 abilities, found ${implementations.length}`);
}
if (new Set(implementations).size !== implementations.length) {
  throw new Error('ability implementation ids are not unique');
}
if (MAPS.length !== 11) throw new Error(`expected 11 maps, found ${MAPS.length}`);

const sourceAssets = resolve(csgoDir, 'assets/agents');
const expectedMedia = agents.flatMap((agent) => [
  resolve(sourceAssets, agent.id, 'portrait.webp'),
  ...slots.map((key) => resolve(sourceAssets, agent.id, `${key}.png`)),
]);
await Promise.all(expectedMedia.map(async (path) => readFile(path)));

const targetAssets = resolve(repoRoot, 'assets/agents');
await rm(targetAssets, { recursive: true, force: true });
await mkdir(dirname(targetAssets), { recursive: true });
await cp(sourceAssets, targetAssets, { recursive: true });

const copiedFiles = [];
for (const agent of await readdir(targetAssets, { withFileTypes: true })) {
  if (!agent.isDirectory()) continue;
  for (const file of await readdir(resolve(targetAssets, agent.name), { withFileTypes: true })) {
    if (file.isFile()) copiedFiles.push(`${agent.name}/${file.name}`);
  }
}
if (copiedFiles.length !== 145) {
  throw new Error(`expected 145 copied media files, found ${copiedFiles.length}`);
}

const catalog = {
  sourceCommit,
  sourceDirty,
  agents,
  maps: MAPS.map((map) => map.id),
  summary: { agents: 29, abilities: 116, media: 145, maps: 11 },
};
const maps = { world: WORLD, maps: MAPS };

await mkdir(resolve(repoRoot, 'data'), { recursive: true });
await writeFile(resolve(repoRoot, 'data/agents.json'), `${JSON.stringify(catalog, null, 2)}\n`);
await writeFile(resolve(repoRoot, 'data/maps.json'), `${JSON.stringify(maps)}\n`);

console.log(
  `Synced ${agents.length} agents, ${implementations.length} abilities, `
    + `${copiedFiles.length} media files, and ${MAPS.length} maps from ${sourceCommit.slice(0, 12)}`
    + `${sourceDirty ? ' (dirty source worktree)' : ''}.`,
);

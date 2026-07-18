# Official Godot Parity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the Godot project's fictional 14-agent layer with the current `../csgo` 29-agent official catalog and reproduce its 116 ability, 11-map, combat, AI, HUD, and round contracts while preserving Godot-native physics effects.

**Architecture:** Generate immutable Godot data and local media from the read-only `../csgo` worktree, then run all gameplay through native GDScript catalog, runtime, mechanics, and world-adapter layers. Node contract tests prove source parity; headless GDScript tests prove behavior; Web smoke tests prove layout, interaction, rendering, and deployment.

**Tech Stack:** Godot 4.6, typed GDScript, Node.js test runner, JSON generation, Playwright, GitHub Actions, GitHub Pages.

---

### Task 1: Add the upstream synchronization contract

**Files:**
- Create: `package.json`
- Create: `tools/sync_from_csgo.mjs`
- Create: `tests/parity_contract.test.mjs`
- Generate: `data/agents.json`
- Modify: `data/maps.json`
- Copy: `assets/agents/**`

**Step 1: Write the failing parity test**

The test imports `../csgo/src/agentCatalog.js`, reads `data/agents.json`, and asserts:

```js
assert.equal(godot.agents.length, 29);
assert.equal(godot.agents.flatMap(agent => Object.values(agent.ab)).length, 116);
assert.deepEqual(godot.agents.map(agent => agent.id), upstream.AGENT_LIST);
assert.deepEqual(godot.maps.map(map => map.id), upstreamMaps.map(map => map.id));
```

It also checks name, role, color, ultimate cost, slot name/type/impl/cost/max/start/cooldown/intent, local portrait/icon files, unique implementation ids, and exactly 11 maps.

**Step 2: Run the test to verify it fails**

Run: `node --test tests/parity_contract.test.mjs`

Expected: FAIL because `data/agents.json` and the eleventh map do not exist.

**Step 3: Implement the sync tool**

Import the upstream ES modules, serialize colors as `#rrggbb`, preserve C/Q/E/X order, copy media with `fs.cp`, and write stable sorted JSON containing `sourceCommit`, `sourceDirty`, `agents`, and `maps`. Never write into `../csgo`.

**Step 4: Generate data and verify green**

Run: `npm run sync:csgo && node --test tests/parity_contract.test.mjs`

Expected: PASS with `29 agents`, `116 abilities`, `145 media files`, and `11 maps`.

**Step 5: Commit**

```bash
git add package.json tools/sync_from_csgo.mjs tests/parity_contract.test.mjs data assets/agents
git commit -m "feat: sync official catalog and maps from web game"
```

### Task 2: Add the native catalog and deterministic runtime core

**Files:**
- Create: `scripts/agent_catalog.gd`
- Create: `scripts/ability_runtime.gd`
- Create: `tests/run_tests.gd`
- Modify: `project.godot`

**Step 1: Write failing catalog and runtime tests**

Use a `SceneTree` test runner with explicit failure counting. Cover catalog count/schema/unique ids, failed and successful charge commits, resource clamping, status extension, recast expiry/single consumption, scheduled game-clock events, stable utility ids, damage/team filtering, recall ownership, projectile interception, expiry, controlled-unit handoff, and teleport validation.

```gdscript
assert_eq(Catalog.agent_ids().size(), 29, "official roster")
var slot := {"n": 2}
assert_true(Runtime.commit_ability(slot, true), "commit succeeds")
assert_eq(slot.n, 1, "one charge spent")
```

**Step 2: Verify red**

Run: `godot --headless --path . --script tests/run_tests.gd`

Expected: FAIL because the catalog and runtime scripts are missing.

**Step 3: Implement minimal catalog/runtime APIs**

Mirror the pure behavior of upstream `abilityCore.js` and `abilityRuntime.js`. Runtime objects contain `id`, `type`, `team`, `owner`, `hp`, `active`, `pos`, `radius`, `until`, and callbacks/signals where needed.

**Step 4: Verify green and parse the project**

Run: `godot --headless --path . --script tests/run_tests.gd`

Run: `godot --headless --editor --path . --quit-after 3`

Expected: all runtime tests pass and no script errors appear.

**Step 5: Commit**

```bash
git add scripts/agent_catalog.gd scripts/ability_runtime.gd tests/run_tests.gd project.godot
git commit -m "refactor: add native ability runtime core"
```

### Task 3: Port agent resource and lifecycle mechanics

**Files:**
- Create: `scripts/agent_mechanics.gd`
- Modify: `tests/run_tests.gd`

**Step 1: Add failing representative mechanics tests**

Port the upstream `agentMechanics.js` contracts for Astra stars, Jett Tailwind prime/recast and knife refill, Phoenix return anchor, KAY/O downed state, Raze recharge, Reyna soul orbs, Neon energy/slide, Chamber Rendezvous, Cypher corpse gate, Skye Regrowth, Clove post-death smoke/revive, Gekko reclaim, Iso shield, Miks Harmonize, Veto immunity, Waylay/Yoru return anchors, Tejo target selection, Viper fuel, and deterministic round reset.

**Step 2: Verify red**

Run: `godot --headless --path . --script tests/run_tests.gd`

Expected: new mechanics tests fail on missing APIs.

**Step 3: Implement agent mechanics**

Keep state in `ability_state` and `resources` dictionaries on combatants. Expose `init_agent_state`, `on_round_start`, `on_kill`, `on_death`, `resolve_fatality`, `tick`, and focused helper methods matching upstream behavior.

**Step 4: Verify green**

Run: `godot --headless --path . --script tests/run_tests.gd`

Expected: all core and mechanics tests pass.

**Step 5: Commit**

```bash
git add scripts/agent_mechanics.gd tests/run_tests.gd
git commit -m "feat: port official agent lifecycle mechanics"
```

### Task 4: Rebuild the cast lifecycle and handler registry

**Files:**
- Modify: `scripts/abilities.gd`
- Modify: `scripts/player.gd`
- Modify: `scripts/bot_ai.gd`
- Modify: `tests/run_tests.gd`

**Step 1: Add failing cast contract tests**

Test life/phase/channel/suppression validation, successful-only spending, ultimate spending, cooldowns, alternate fire, equip/cancel, recasts, post-death allowances, and handler coverage for every catalog `type`.

```gdscript
for agent_id in Catalog.agent_ids():
    for key in ["c", "q", "e", "x"]:
        assert_true(Abilities.has_handler(Catalog.ability(agent_id, key).type), agent_id + "." + key)
```

**Step 2: Verify red**

Run: `godot --headless --path . --script tests/run_tests.gd`

Expected: FAIL for missing official types and legacy roster ids.

**Step 3: Implement data-driven slots and cast lifecycle**

Replace the hard-coded `AGENTS` table with `AgentCatalog`. Add `start_cast`, `confirm_cast`, `cancel_cast`, `recast`, and `cast_for_bot`. Keep shared handlers for genuinely shared primitives, but register every official type explicitly and never silently fall back.

**Step 4: Verify green and audit legacy names**

Run: `godot --headless --path . --script tests/run_tests.gd`

Run: `rg -n "fengying|lieyan|tianqiong|anmu|lieying|shengyu|leiyi|zhuying|lanqie|qingzhen|lingshi|yinglie|meiying|lingyu" scripts README.md`

Expected: tests pass and no user-visible legacy roster remains.

**Step 5: Commit**

```bash
git add scripts/abilities.gd scripts/player.gd scripts/bot_ai.gd tests/run_tests.gd
git commit -m "feat: add official ability cast registry"
```

### Task 5: Port world primitives and high-risk ability families

**Files:**
- Modify: `scripts/main.gd`
- Modify: `scripts/abilities.gd`
- Modify: `scripts/player.gd`
- Modify: `scripts/match_mgr.gd`
- Modify: `tests/run_tests.gd`

**Step 1: Add failing behavior tests**

Cover destructible/recallable utility, projectile interception, ballistic bounce, LOS reveals, wall penetration, tethers, map targeting, directed walls, temporary weapons, bullet-blocking Cove, controlled scouts, teleports with clearance, agent fatality interception, post-death casting, and deterministic cleanup.

**Step 2: Verify red**

Run: `godot --headless --path . --script tests/run_tests.gd`

Expected: FAIL on missing world adapter methods and cleanup state.

**Step 3: Implement Godot-native primitives**

Use `RigidBody3D` for ballistic projectiles and physical drops, `StaticBody3D`/`Area3D` for destructible utility and zones, physics ray queries for LOS/wall checks, and game-clock queues instead of wall-clock timers for gameplay state. Preserve particles, impulses, ragdolls, smoke collision layers, and native navigation.

**Step 4: Integrate combat and round hooks**

Route damage through utility interception and agent shields/fatality hooks. On round transition clear runtime events, control mode, transient utility, temporary weapons, agent round state, and orphaned physics nodes.

**Step 5: Verify green**

Run: `godot --headless --path . --script tests/run_tests.gd`

Run: `TP_AUTOSTART=yiji godot --headless --path . --quit-after 12000`

Expected: tests pass; the smoke run completes a round loop without `SCRIPT ERROR` or `ERROR`.

**Step 6: Commit**

```bash
git add scripts/main.gd scripts/abilities.gd scripts/player.gd scripts/match_mgr.gd tests/run_tests.gd
git commit -m "feat: port official ability world primitives"
```

### Task 6: Integrate all official agents with bots and combat

**Files:**
- Modify: `scripts/bot_ai.gd`
- Modify: `scripts/match_mgr.gd`
- Modify: `scripts/player.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/run_tests.gd`

**Step 1: Add failing AI/combat contract tests**

Assert all 29 agents can be assigned, all 116 abilities have a supported intent, bot casts use the common validator, sound information reaches opponents, controlled and post-death modes do not corrupt normal AI, and kill/death/damage hooks update agent resources.

**Step 2: Verify red**

Run: `godot --headless --path . --script tests/run_tests.gd`

Expected: FAIL on missing intent and roster integration.

**Step 3: Port data-driven bot intents**

Translate upstream intents (`entry`, `cover`, `control`, `damage`, `escape`, `heal`, `info`, `setup`, `weapon`, `ultimate`) and agent-specific decision hooks. Bots provide targets but use the same cast and resource rules as players.

**Step 4: Verify green and run all maps**

Run: `godot --headless --path . --script tests/run_tests.gd`

Run: `for map in yiji santa liexia tiangang xuefeng rongcheng gumiao huanjie sixiang chongqing tianshu; do TP_AUTOSTART=$map godot --headless --path . --quit-after 3000 || exit 1; done`

Expected: all tests pass and all 11 map startups reach live play without errors.

**Step 5: Commit**

```bash
git add scripts/bot_ai.gd scripts/match_mgr.gd scripts/player.gd scripts/main.gd tests/run_tests.gd
git commit -m "feat: integrate official roster with combat AI"
```

### Task 7: Replace roster UI, HUD, icons, and settings data

**Files:**
- Modify: `scripts/main.gd`
- Modify: `scripts/hud.gd`
- Modify: `scripts/icons.gd`
- Modify: `README.md`
- Create: `tests/web_smoke.mjs`
- Modify: `package.json`

**Step 1: Add failing UI source and browser tests**

Assert 29 data-driven cards, local portraits/icons, no clipped names, no card overlap, no horizontal overflow, live resources/recasts/cooldowns in the HUD, settings persistence, and no fictional names in user-visible files.

**Step 2: Verify red**

Run: `node --test tests/parity_contract.test.mjs`

Run: `npm run smoke:web`

Expected: FAIL on the 14-card procedural roster and missing official media use.

**Step 3: Implement roster and HUD**

Load portraits and icons from `assets/agents/<id>/`. Use responsive scrollable grid/card sizing for desktop and mobile. Render charges, cooldowns, resources, recast availability, controlled mode, post-death abilities, ultimate points, and official roles/names from catalog state.

**Step 4: Verify green visually and structurally**

Run: `node --test tests/parity_contract.test.mjs`

Run: `npm run smoke:web`

Expected: desktop/mobile screenshots show 29 usable cards and gameplay; canvas pixel checks and console audit pass.

**Step 5: Commit**

```bash
git add scripts/main.gd scripts/hud.gd scripts/icons.gd README.md tests/web_smoke.mjs package.json
git commit -m "feat: ship official roster UI and HUD"
```

### Task 8: Harden CI and complete deployment verification

**Files:**
- Modify: `.github/workflows/deploy-web.yml`
- Modify: `export_presets.cfg`
- Modify: `README.md`

**Step 1: Add CI gates**

Run parity tests, GDScript tests, all-map startup smoke, release Web export, and browser smoke before deployment. Preserve command exit codes and reject `SCRIPT ERROR`, engine `ERROR`, missing handlers, blank frames, broken assets, or incomplete round loops.

**Step 2: Run the complete local verification suite**

Run: `npm test`

Run: `godot --headless --path . --script tests/run_tests.gd`

Run: `npm run smoke:web`

Run: `npm run smoke:maps`

Run: `godot --headless --path . --export-release Web build/web/index.html`

Expected: every command exits 0 with no script, engine, console, asset, layout, or canvas failures.

**Step 3: Commit release gates**

```bash
git add .github/workflows/deploy-web.yml export_presets.cfg README.md package.json tests tools
git commit -m "test: gate official parity deployment"
```

**Step 4: Push and monitor deployment**

Run: `git push origin main`

Run: `gh run list --workflow "Build & Deploy Web" --limit 1`

Wait for both the build workflow and Pages deployment to complete successfully.

**Step 5: Verify production**

Open `https://hecrereed.github.io/tactical-protocol-godot/`, verify the deployed source version, 29-agent roster, official media, live match, representative high-risk abilities, nonblank 3D canvas, and zero console errors.

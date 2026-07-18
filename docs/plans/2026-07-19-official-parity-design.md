# Godot Official VALORANT Parity Design

Date: 2026-07-19

## Goal

Make the Godot project reproduce the current `../csgo` game contract while retaining Godot-specific physical presentation such as rigid-body grenades and weapon drops, particles, ragdolls, and native collision. The parity target is the current 29-agent official roster, 116 standard ability slots, 11 maps, weapons, round rules, economy, AI behavior, HUD, and local official portrait/icon media.

The Godot project will replace its fictional Chinese agent roster with the official names and assets already stored in `../csgo`. JavaScript remains a read-only upstream source during development; the shipped Godot game does not execute or fetch JavaScript at runtime.

## Chosen Approach

Use a generated catalog plus a native GDScript ability runtime. A sync tool imports the current `csgo` catalog and map data, emits deterministic local JSON, and copies media into the Godot project. GDScript owns all live state and uses Godot physics for effects.

Rejected alternatives:

- Extending the existing monolithic `abilities.gd` would make 116 skills, recasts, resources, post-death casts, and controlled units difficult to audit and test.
- Executing the JavaScript game inside the Godot Web export would split desktop and Web behavior and create two competing physics/state authorities.

## Architecture

`tools/sync_from_csgo.mjs` imports `../csgo/src/agentCatalog.js`, generates `data/agents.json`, copies 29 portraits and 116 ability icons, and synchronizes `data/maps.json`. Generated data records its source commit/worktree fingerprint and a validation summary.

`scripts/agent_catalog.gd` loads and validates roster metadata. `scripts/ability_runtime.gd` owns stable runtime ids, scheduled game-clock events, utility registration, destructibility, recalls, projectile interception, controlled-unit handoff, and round cleanup. `scripts/agent_mechanics.gd` owns resources and agent-specific kill, death, damage, recast, and round hooks. `scripts/abilities.gd` remains the cast lifecycle and Godot world adapter. `scripts/main.gd` continues to implement raycasts, collision, rigid bodies, particles, zones, devices, and damage delivery.

Players and bots call the same validation and commit path. Bot decision code supplies intent and targets but cannot bypass charges, range, line of sight, cast delays, destructibility, resources, or phase restrictions. The HUD reads catalog definitions and live runtime state rather than maintaining duplicate ability rules.

## Data Flow

1. A player or bot requests C, Q, E, or X.
2. The cast layer validates life state, round phase, suppression, channel state, charges, cooldown, resource, target, range, line of sight, and placement.
3. Agent mechanics handles resources, recast windows, kill/death hooks, post-death access, and temporary agent modes.
4. The runtime creates projectiles, zones, devices, controlled units, temporary weapons, teleports, or scheduled effects.
5. `main.gd` realizes the effect through Godot-native physics and rendering.
6. Charges or ultimate points are spent only after a successful commit. HUD and bots observe the resulting shared state.

## Failure And Cleanup Rules

Invalid placement, missing targets, expired recasts, insufficient resources, suppression, blocked destinations, or disallowed phases fail without spending a charge. Missing catalog media, duplicate ability ids, absent Godot handlers, or schema mismatches fail synchronization and tests instead of silently falling back to an unrelated skill.

Round end, death, halftime, match end, or control interruption deterministically clears scheduled events, transient projectiles, temporary weapons, controlled cameras, channels, agent modes, and round-scoped utility. Persistent equipment and resources follow the upstream `csgo` rules.

## Fidelity Scope

- Official 29-agent names, roles, portraits, ability names, ability icons, charge/cost/cooldown data, and ultimate costs.
- All 116 slots have explicit Godot dispatch and preserve the upstream gameplay decision, including alternate fire, recasts, recalls, destructible utility, post-death casts, controlled units, agent resources, kill contracts, anchors, and temporary weapons.
- All 11 current maps, weapons, economy, spike rules, side swap, sudden death, bot intents, sound information, HUD, selection, buy menu, scoreboard, minimap, observer mode, and settings.
- Godot-specific rigid bodies, impulses, particles, ragdolls, native 3D navigation, and physical effects remain when they do not change the upstream gameplay contract.

## Testing

`tests/parity_contract.mjs` compares the upstream and generated catalogs and maps. It requires exactly 29 agents, 116 unique ability slots, matching gameplay metadata, complete local media, 11 matching maps, and one registered Godot handler for every ability type.

`tests/run_tests.gd` runs headlessly and exercises charge commit behavior, invalid casts, recasts, resources, kill/death hooks, destructible utility, control handoff, event cleanup, and representative high-risk kits including Jett, Phoenix, Sova, Viper, KAY/O, Clove, Gekko, Reyna, Neon, Chamber, Astra, and Yoru.

Web smoke tests render desktop and mobile roster layouts, verify all media, enter matches, equip/cancel/cast/recast abilities, exercise control and revival paths, run a complete round, audit console errors, and check nonblank canvas pixels. Every map receives a headless startup test.

## Delivery

Implementation is committed to the Godot repository's `main` branch and pushed to `origin/main`. The `Build & Deploy Web` and Pages workflows must complete successfully. The deployed build at `https://hecrereed.github.io/tactical-protocol-godot/` is then checked for its version marker, 29-agent roster, live gameplay, rendered canvas, and clean console.

The upstream `csgo` worktree is read-only. Its current local `tools/smoke_game.mjs` modification is preserved.

extends SceneTree

const Catalog := preload("res://scripts/agent_catalog.gd")
const Runtime := preload("res://scripts/ability_runtime.gd")
const Mechanics := preload("res://scripts/agent_mechanics.gd")
const Abilities := preload("res://scripts/abilities.gd")
const MainScript := preload("res://scripts/main.gd")

class FakeScoutOwner:
	extends CharacterBody3D
	var team := "ally"
	var alive := true
	var resources := {"globules": {}}
	var pitch := 0.0
	var yaw := 0.0

	func eye_pos() -> Vector3:
		return global_position + Vector3.UP * 1.55

	func aim_dir() -> Vector3:
		return Vector3.FORWARD

class FakeAbilityWorld:
	extends RefCounted
	var clock := 0.0
	var ability_events: Array = []
	var explosions: Array = []
	var orbitals: Array = []
	var scouts: Array = []
	var fighters: Array = []
	var slow_zones: Array = []
	var legacy_units: Array[String] = []

	func can_fight() -> bool:
		return true

	func now() -> float:
		return clock

	func combatants() -> Array:
		return fighters

	func explode(owner: Variant, point: Vector3, radius: float, near_damage: float, far_damage: float) -> void:
		explosions.append({
			"owner": owner, "point": point, "radius": radius,
			"near": near_damage, "far": far_damage,
		})

	func orbital_strike(owner: Variant, origin: Vector3, direction: Vector3) -> void:
		orbitals.append({"owner": owner, "point": origin, "direction": direction})

	func orbital_strike_at(owner: Variant, point: Vector3) -> void:
		orbitals.append({"owner": owner, "point": point})

	func spawn_slow_zone(owner: Variant, point: Vector3, radius: float, duration: float) -> void:
		slow_zones.append({
			"owner": owner, "point": point, "radius": radius, "duration": duration,
		})

	func spawn_drone(_owner: Variant, _direction: Vector3) -> void:
		legacy_units.append("drone")

	func spawn_boom_bot(_owner: Variant, _direction: Vector3) -> void:
		legacy_units.append("boombot")

	func spawn_controlled_scout(
		owner: Variant,
		scout_type: String,
		duration: float,
		speed: float,
		controlled: bool = true,
		globule_key: String = "",
		start_point: Variant = null,
	) -> void:
		scouts.append({
			"owner": owner, "type": scout_type, "duration": duration, "speed": speed,
			"controlled": controlled, "globule": globule_key, "start": start_point,
		})

var failures := 0
var checks := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_catalog()
	_test_core_runtime()
	_test_utility_runtime()
	_test_agent_mechanics()
	_test_cast_contracts()
	_test_combat_and_round_integration()
	_test_bot_intents()
	if failures == 0:
		print("PASS: %d checks" % checks)
	else:
		push_error("FAIL: %d of %d checks failed" % [failures, checks])
	quit(1 if failures > 0 else 0)

func _test_catalog() -> void:
	var ids := Catalog.agent_ids()
	assert_eq(ids.size(), 29, "official roster count")
	assert_eq(ids[0], "astra", "catalog preserves upstream order")
	assert_eq(ids[-1], "yoru", "catalog includes latest tail agent")
	assert_eq(Catalog.all_abilities().size(), 116, "official ability count")
	assert_eq(Catalog.map_ids().size(), 16, "official map count")
	assert_eq(Catalog.agent("kayo")["name"], "KAY/O", "official display name")
	assert_eq(Catalog.ability("astra", "e")["type"], "astraNebula", "ability lookup")
	assert_true(FileAccess.file_exists(Catalog.agent("jett")["portrait"]), "portrait is local")
	assert_true(FileAccess.file_exists(Catalog.ability("jett", "x")["icon"]), "ability icon is local")
	assert_eq(Catalog.validation_errors(), [], "catalog schema validates")

	var implementations := {}
	for ability in Catalog.all_abilities():
		implementations[ability["impl"]] = true
	assert_eq(implementations.size(), 116, "ability implementation ids are unique")

func _test_core_runtime() -> void:
	assert_eq(MainScript.menu_content_scale(Vector2i(1280, 720)), 1.0, "desktop menu keeps native content scale")
	assert_eq(MainScript.menu_content_scale(Vector2i(390, 844)), 4.0, "portrait menu expands to a readable mobile scale")
	assert_eq(MainScript.menu_content_scale(Vector2i(844, 390)), 1.0, "landscape menu keeps native content scale")

	var failed_slot := {"n": 1}
	assert_false(Runtime.commit_ability(failed_slot, false), "failed cast is rejected")
	assert_eq(failed_slot["n"], 1, "failed cast keeps its charge")
	var successful_slot := {"n": 2}
	assert_true(Runtime.commit_ability(successful_slot, true), "successful cast commits")
	assert_eq(successful_slot["n"], 1, "successful cast spends one charge")

	assert_eq(Runtime.clamp_resource(112.0, 0.0, 100.0), 100.0, "resource upper clamp")
	assert_eq(Runtime.clamp_resource(-4.0, 0.0, 100.0), 0.0, "resource lower clamp")
	var status := {"slow_until": 10.0}
	Runtime.extend_status(status, "slow_until", 8.0)
	assert_eq(status["slow_until"], 10.0, "short status cannot replace long status")
	Runtime.extend_status(status, "slow_until", 12.0)
	assert_eq(status["slow_until"], 12.0, "long status extends duration")

	var combatant := {"ability_state": {}}
	Runtime.open_recast(combatant, "gatecrash", 15.0, {"x": 2})
	assert_eq(Runtime.consume_recast(combatant, "gatecrash", 16.0), null, "expired recast fails")
	Runtime.open_recast(combatant, "gatecrash", 20.0, {"x": 4})
	assert_eq(Runtime.consume_recast(combatant, "gatecrash", 18.0), {"x": 4}, "live recast returns payload")
	assert_eq(Runtime.consume_recast(combatant, "gatecrash", 18.0), null, "recast is consumed once")

	var queue: Array = []
	var calls: Array[String] = []
	Runtime.schedule_ability_event(queue, 5.0, func(): calls.append("pulse"), "recon")
	Runtime.run_ability_events(queue, 4.9)
	assert_eq(calls, [], "event waits for game clock")
	Runtime.run_ability_events(queue, 5.0)
	assert_eq(calls, ["pulse"], "event runs on game clock")
	assert_eq(queue.size(), 0, "completed event is removed")

func _test_utility_runtime() -> void:
	var store := Runtime.create_utility_store()
	var destroyed: Array[String] = []
	var turret := Runtime.register_utility(store, {
		"type": "turret", "team": "ally", "owner_id": 7, "hp": 100.0,
		"on_destroy": func(utility, _reason): destroyed.append(utility["id"]),
	})
	assert_eq(turret["id"], "utility-1", "utility receives stable id")
	assert_false(Runtime.damage_utility(store, turret["id"], 40.0, "enemy"), "surviving damage reports false")
	assert_eq(turret["hp"], 60.0, "utility takes hostile damage")
	assert_true(Runtime.damage_utility(store, turret["id"], 60.0, "enemy"), "fatal damage destroys utility")
	assert_eq(destroyed, ["utility-1"], "destroy callback receives stable id")
	assert_eq(store["items"].size(), 0, "destroyed utility leaves store")

	var camera := Runtime.register_utility(store, {
		"type": "camera", "team": "ally", "owner_id": 3, "hp": 20.0,
	})
	assert_false(Runtime.damage_utility(store, camera["id"], 50.0, "ally"), "friendly utility damage is ignored")
	assert_eq(camera["hp"], 20.0, "friendly damage keeps hp")
	var anchor := Runtime.register_utility(store, {
		"type": "anchor", "team": "ally", "owner_id": 3, "recallable": true,
	})
	assert_eq(Runtime.recall_utility(store, anchor["id"], 8), null, "non-owner cannot recall")
	assert_eq(Runtime.recall_utility(store, anchor["id"], 3), anchor, "owner recalls utility")

	var intercepts := [0]
	Runtime.register_utility(store, {
		"type": "interceptor", "team": "ally", "owner_id": 2,
		"radius": 5.0, "pos": Vector3.ZERO,
		"on_intercept": func(_projectile): intercepts[0] += 1,
	})
	assert_true(Runtime.intercept_projectile(store, {
		"team": "enemy", "pos": Vector3(3, 0, 0), "interceptable": true,
	}), "near hostile projectile is intercepted")
	assert_false(Runtime.intercept_projectile(store, {
		"team": "ally", "pos": Vector3(2, 0, 0), "interceptable": true,
	}), "friendly projectile is not intercepted")
	assert_false(Runtime.intercept_projectile(store, {
		"team": "enemy", "pos": Vector3(1, 0, 0), "interceptable": false,
	}), "beam opts out of interception")
	assert_eq(intercepts[0], 1, "interception callback count")

	Runtime.register_utility(store, {
		"type": "smoke-anchor", "team": "ally", "owner_id": 1, "until": 12.0,
	})
	var before_expiry: int = store["items"].size()
	Runtime.tick_utilities(store, 11.9)
	assert_eq(store["items"].size(), before_expiry, "utility waits for expiry clock")
	Runtime.tick_utilities(store, 12.0)
	assert_eq(store["items"].size(), before_expiry - 1, "expired utility is removed")

	var state := {"control_mode": null}
	var owner := {"id": 1}
	var unit := {"id": "drone-1"}
	Runtime.begin_control(state, owner, unit, 10.0)
	assert_eq(state["control_mode"]["unit"], unit, "controlled unit handoff")
	assert_eq(Runtime.end_control(state), owner, "control returns to owner")
	assert_eq(state["control_mode"], null, "control mode clears")

	unit = {"id": "trailblazer-1", "vel": Vector3.ZERO, "active": true}
	Runtime.begin_control(state, owner, unit, 10.0)
	assert_true(Runtime.steer_controlled_unit(
		state, owner, 2.0, 0.2, Vector3.FORWARD, 1.0,
	), "controlled unit accepts owner movement")
	assert_eq(unit["vel"], Vector3.FORWARD * 8.0, "forward control uses upstream speed")
	assert_false(Runtime.steer_controlled_unit(
		state, owner, 10.0, 0.1, Vector3.FORWARD, 1.0,
	), "expired controlled unit returns control")
	assert_eq(state["control_mode"], null, "expired control mode clears")
	assert_eq(Runtime.controlled_impact("trailblazer"), {
		"daze_until": 3.0, "slow_until": 3.0, "ends_unit": true,
	}, "Trailblazer impact contract")
	assert_eq(Runtime.controlled_impact("thrash"), {
		"suppressed_until": 6.0, "slow_until": 6.0, "ends_unit": true,
	}, "Thrash impact contract")
	assert_eq(Runtime.controlled_impact("prowler"), {
		"flash_until": 2.5, "terror_trail_until": 6.0, "ends_unit": true,
	}, "Prowler impact contract")
	assert_eq(Runtime.controlled_impact("sova"), {
		"reveal_radius": 10.0, "reveal_duration": 3.0, "ends_unit": false,
	}, "generic scout impact reveals")

	var scout_world := MainScript.new()
	root.add_child(scout_world)
	var scout_owner := FakeScoutOwner.new()
	scout_world.add_child(scout_owner)
	scout_world.player = scout_owner
	var live_scout: Dictionary = scout_world.spawn_controlled_scout(
		scout_owner, "trailblazer", 6.0, 8.0,
	)
	assert_eq(live_scout["kind"], "controlled_scout", "world keeps controlled unit family")
	assert_eq(live_scout["scout_type"], "trailblazer", "world keeps scout identity")
	assert_eq(live_scout["vel"], Vector3.FORWARD * 8.0, "world applies scout launch speed")
	assert_true(live_scout in scout_world.devices, "world registers controlled scout")
	assert_eq(scout_world.control_state["control_mode"]["unit"], live_scout, "player enters scout control")
	assert_true(scout_world.is_controlling(scout_owner), "world reports active owner control")
	scout_world.end_controlled_unit(scout_owner)
	assert_eq(scout_world.control_state["control_mode"], null, "world returns control to player")
	scout_world._t = 0.01
	scout_world._tick_devices(0.01)
	assert_false(live_scout in scout_world.devices, "ended controlled scout leaves device registry")

	scout_world._t = 1.0
	var gekko_scout: Dictionary = scout_world.spawn_controlled_scout(
		scout_owner, "wingman", 1.0, 7.0, true, "wingman",
	)
	scout_world._t = 2.01
	scout_world._tick_devices(0.01)
	assert_false(gekko_scout in scout_world.devices, "expired Gekko scout leaves device registry")
	assert_eq(scout_world.control_state["control_mode"], null, "expired Gekko scout returns control")
	assert_true(
		is_equal_approx(scout_owner.resources["globules"]["wingman"]["until"], 22.01),
		"expired Gekko scout creates a twenty second reclaim window",
	)
	scout_world.free()

	var point := Vector3(5, 0, 4)
	assert_true(Runtime.valid_teleport_destination(
		point, func(_p): return true, func(_p): return false,
	), "walkable clear teleport succeeds")
	assert_false(Runtime.valid_teleport_destination(
		point, func(_p): return false, func(_p): return false,
	), "out of bounds teleport fails")
	assert_false(Runtime.valid_teleport_destination(
		point, func(_p): return true, func(_p): return true,
	), "blocked teleport fails")

func _test_agent_mechanics() -> void:
	var astra := _actor("astra")
	Mechanics.init_agent_state(astra)
	var star = Mechanics.place_astra_star(astra, Vector3(4, 0, 2))
	assert_eq(astra["resources"]["stars"], 3, "Astra spends a finite star")
	assert_true(Mechanics.consume_astra_star(astra, star["id"], "gravity"), "Astra consumes a live star")
	assert_false(Mechanics.consume_astra_star(astra, star["id"], "nova"), "Astra star is single use")

	var jett := _actor("jett")
	Mechanics.init_agent_state(jett)
	Mechanics.prime_jett_dash(jett, 10.0)
	assert_false(Mechanics.consume_jett_dash(jett, 9.9), "Jett dash cannot prefire")
	assert_true(Mechanics.consume_jett_dash(jett, 10.1), "Jett consumes primed dash")
	assert_false(Mechanics.consume_jett_dash(jett, 10.2), "Jett dash is single use")
	jett["knife_ult"] = 1
	Mechanics.on_kill(jett, _actor("sage"), 12.0)
	assert_eq(jett["knife_ult"], 5, "Jett knives refill on kill")

	var phoenix := _actor("phoenix")
	phoenix["pos"] = Vector3(8, 0, 4)
	Mechanics.activate_return_anchor(phoenix, 20.0)
	phoenix["pos"] = Vector3(30, 0, 30)
	phoenix["hp"] = -20.0
	var phoenix_fatality := Mechanics.resolve_fatality(phoenix, 12.0)
	assert_true(phoenix_fatality["prevented"], "Phoenix anchor prevents death")
	assert_eq(phoenix["pos"], Vector3(8, 0, 4), "Phoenix returns to anchor")
	assert_eq(phoenix["hp"], 100.0, "Phoenix returns at full hp")

	var kayo := _actor("kayo")
	Mechanics.init_agent_state(kayo)
	kayo["ability_state"]["null_cmd_until"] = 30.0
	var kayo_fatality := Mechanics.resolve_fatality(kayo, 20.0)
	assert_true(kayo_fatality["prevented"], "KAY/O ultimate prevents immediate death")
	assert_eq(kayo["channel"], "downed", "KAY/O enters downed channel")
	assert_eq(kayo["ability_state"]["downed_until"], 35.0, "KAY/O downed window")

	var raze := _actor("raze")
	raze["ability_slots"] = {"e": {"n": 0, "def": {"max": 1}}}
	Mechanics.init_agent_state(raze)
	Mechanics.on_kill(raze, _actor("sage"), 1.0)
	assert_eq(raze["ability_slots"]["e"]["n"], 0, "Raze waits for second kill")
	Mechanics.on_kill(raze, _actor("sage"), 2.0)
	assert_eq(raze["ability_slots"]["e"]["n"], 1, "Raze signature recharges after two kills")

	var reyna := _actor("reyna")
	Mechanics.init_agent_state(reyna)
	var victim := _actor("sage")
	victim["pos"] = Vector3(4, 0, 5)
	Mechanics.on_kill(reyna, victim, 10.0)
	assert_true(Mechanics.consume_reyna_soul(reyna, "devour", 12.0), "Reyna consumes live soul")
	assert_false(Mechanics.consume_reyna_soul(reyna, "dismiss", 12.0), "Reyna soul is single use")
	Mechanics.on_kill(reyna, victim, 20.0)
	assert_false(Mechanics.consume_reyna_soul(reyna, "dismiss", 24.0), "Reyna soul expires")

	var neon := _actor("neon")
	Mechanics.init_agent_state(neon)
	assert_true(Mechanics.start_neon_sprint(neon), "Neon can sprint with energy")
	assert_true(Mechanics.use_neon_slide(neon), "Neon spends slide charge")
	assert_false(Mechanics.use_neon_slide(neon), "Neon cannot overspend slide")
	Mechanics.on_kill(neon, victim, 2.0)
	Mechanics.on_kill(neon, victim, 3.0)
	assert_true(Mechanics.use_neon_slide(neon), "Neon slide recharges after two kills")

	var chamber := _actor("chamber")
	Mechanics.init_agent_state(chamber)
	assert_false(Mechanics.use_rendezvous(chamber), "Chamber requires anchor")
	Mechanics.place_rendezvous(chamber, Vector3(3, 0, 4))
	chamber["pos"] = Vector3(20, 0, 20)
	assert_true(Mechanics.use_rendezvous(chamber), "Chamber uses Rendezvous")
	assert_eq(chamber["pos"], Vector3(3, 0, 4), "Chamber returns to Rendezvous")

	var cypher := _actor("cypher")
	assert_false(Mechanics.can_neural_theft(cypher, [], 10.0), "Cypher needs a corpse")
	assert_true(Mechanics.can_neural_theft(cypher, [
		{"entity": {"team": "enemy"}, "died_at": 4.0},
	], 10.0), "Cypher accepts recent enemy corpse")
	assert_false(Mechanics.can_neural_theft(cypher, [
		{"entity": {"team": "enemy"}, "died_at": 1.0},
	], 10.0), "Cypher rejects old corpse")

	var skye := _actor("skye")
	var ally := _actor("jett")
	var enemy := _actor("jett")
	ally["id"] = 2
	ally["hp"] = 40.0
	enemy["id"] = 3
	enemy["team"] = "enemy"
	enemy["hp"] = 40.0
	Mechanics.init_agent_state(skye)
	assert_true(Mechanics.apply_skye_regrowth(skye, [skye, ally, enemy], 1.0), "Skye heals a valid ally")
	assert_eq(skye["hp"], 100.0, "Skye does not heal herself")
	assert_eq(ally["hp"], 60.0, "Skye heals ally over time")
	assert_eq(enemy["hp"], 40.0, "Skye never heals enemy")

	var clove := _actor("clove")
	clove["alive"] = false
	Mechanics.on_death(clove, 10.0)
	assert_true(Mechanics.can_clove_post_death_cast(clove, "cloveRuse", 15.0), "Clove casts Ruse after death")
	assert_false(Mechanics.can_clove_post_death_cast(clove, "cloveMeddle", 15.0), "Clove post-death cast is restricted")
	clove["ability_state"]["clove_revive_until"] = 18.0
	assert_true(Mechanics.activate_clove_revive(clove, 17.0), "Clove revives inside ultimate window")
	assert_true(clove["alive"], "Clove revive restores life state")

	var gekko := _actor("gekko")
	Mechanics.init_agent_state(gekko)
	gekko["resources"]["globules"]["wingman"] = {"until": 12.0}
	assert_true(Mechanics.reclaim_gekko_globule(gekko, "wingman", 10.0), "Gekko reclaims live globule")
	assert_false(Mechanics.reclaim_gekko_globule(gekko, "wingman", 10.0), "Gekko globule is single use")

	var iso := _actor("iso")
	iso["ability_state"]["iso_shield"] = true
	assert_true(Mechanics.consume_iso_shield(iso), "Iso shield blocks one hit")
	assert_false(Mechanics.consume_iso_shield(iso), "Iso shield is consumed")

	var miks := _actor("miks")
	Mechanics.harmonize_pair(miks, ally, 10.0)
	assert_eq(miks["ability_state"]["harmonize_until"], 20.0, "Miks Harmonize self window")
	assert_eq(ally["ability_state"]["harmonize_until"], 20.0, "Miks Harmonize ally window")

	var veto := _actor("veto")
	veto["ability_state"]["evolution_until"] = 30.0
	assert_true(Mechanics.is_debuff_immune(veto, 20.0), "Veto Evolution blocks debuffs")
	assert_false(Mechanics.is_debuff_immune(veto, 31.0), "Veto Evolution expires")

	for agent_id in ["waylay", "yoru"]:
		var actor := _actor(agent_id)
		actor["pos"] = Vector3(3, 0, 4)
		Mechanics.place_return_anchor(actor, agent_id, 20.0)
		actor["pos"] = Vector3(20, 0, 20)
		assert_true(Mechanics.return_to_light_anchor(actor, agent_id, 10.0), "%s return anchor" % agent_id)
		assert_eq(actor["pos"], Vector3(3, 0, 4), "%s return position" % agent_id)

	var tejo := _actor("tejo")
	assert_eq(Mechanics.select_tejo_target(tejo, Vector3(1, 0, 2)), 1, "Tejo first target")
	assert_eq(Mechanics.select_tejo_target(tejo, Vector3(3, 0, 4)), 2, "Tejo second target")
	assert_eq(Mechanics.select_tejo_target(tejo, Vector3(5, 0, 6)), 2, "Tejo target limit")

	var viper := _actor("viper")
	Mechanics.init_agent_state(viper)
	Mechanics.set_viper_emitter(viper, "screen", true)
	Mechanics.tick(viper, 1.0, 2.0)
	assert_eq(viper["resources"]["fuel"], 70.0, "Viper active fuel drain")
	Mechanics.set_viper_emitter(viper, "screen", false)
	Mechanics.tick(viper, 3.0, 2.0)
	assert_eq(viper["resources"]["fuel"], 80.0, "Viper inactive fuel regeneration")

	neon["ability_state"]["temporary"] = true
	neon["resources"]["energy"] = 1.0
	neon["ability_slots"] = {"e": {"n": 0, "cd_until": 99.0, "def": {"start": 1}}}
	Mechanics.on_round_start(neon)
	assert_eq(neon["ability_state"], {}, "round reset clears transient agent state")
	assert_eq(neon["resources"]["energy"], 100.0, "round reset restores agent resource")
	assert_eq(neon["ability_slots"]["e"]["n"], 1, "round reset restores starting charge")
	assert_eq(neon["ability_slots"]["e"]["cd_until"], 0.0, "round reset clears cooldown")

func _test_cast_contracts() -> void:
	var registered_types := {}
	for definition in Catalog.all_abilities():
		var type := String(definition["type"])
		registered_types[type] = true
		assert_true(Abilities.has_handler(type), "registered handler: %s" % type)
	assert_eq(Abilities.handler_types().size(), registered_types.size(), "no hidden handler fallback")

	var slots := Abilities.make_slots("astra")
	assert_eq(slots["c"]["n"], 1, "catalog starting charge")
	assert_eq(slots["e"]["n"], 2, "catalog multi-charge signature")
	assert_eq(slots["x"]["n"], 0, "ultimate starts uncharged")

	var actor := _cast_actor("jett")
	var failed_phase := Abilities.start_cast(actor, "c", 10.0, false, "buy")
	assert_false(failed_phase["ok"], "buy phase cast is rejected")
	actor["alive"] = false
	assert_false(Abilities.start_cast(actor, "c", 10.0, true)["ok"], "dead cast is rejected")
	actor["alive"] = true
	actor["channel"] = "plant"
	assert_false(Abilities.start_cast(actor, "c", 10.0, true)["ok"], "channeling cast is rejected")
	actor["channel"] = ""
	actor["suppressed_until"] = 11.0
	assert_false(Abilities.start_cast(actor, "c", 10.0, true)["ok"], "suppressed cast is rejected")
	actor["suppressed_until"] = 0.0
	actor["ability_slots"]["c"]["n"] = 0
	assert_false(Abilities.start_cast(actor, "c", 10.0, true)["ok"], "empty slot is rejected")
	actor["ability_slots"]["c"]["n"] = 1
	actor["ability_slots"]["c"]["cd_until"] = 11.0
	assert_false(Abilities.start_cast(actor, "c", 10.0, true)["ok"], "cooldown is rejected")
	actor["ability_slots"]["c"]["cd_until"] = 0.0

	var failed_cast := Abilities.start_cast(actor, "c", 10.0, true)
	assert_true(failed_cast["ok"], "valid cast prepares")
	assert_false(Abilities.confirm_cast(
		null, actor, failed_cast, false, func(_world, _entity, _key, _definition, _alt): return false,
	), "failed handler rejects cast")
	assert_eq(actor["ability_slots"]["c"]["n"], 1, "failed handler spends no charge")

	var alternate := [false]
	var successful_cast := Abilities.start_cast(actor, "c", 10.0, true)
	assert_true(Abilities.confirm_cast(
		null, actor, successful_cast, true,
		func(_world, _entity, _key, _definition, alt):
			alternate[0] = alt
			return true,
	), "successful handler commits cast")
	assert_true(alternate[0], "alternate fire reaches handler")
	assert_eq(actor["ability_slots"]["c"]["n"], 0, "successful handler spends one charge")

	actor = _cast_actor("jett")
	actor["ult_points"] = 7
	assert_false(Abilities.start_cast(actor, "x", 20.0, true)["ok"], "insufficient ultimate points")
	actor["ult_points"] = 8
	var ultimate := Abilities.start_cast(actor, "x", 20.0, true)
	assert_true(Abilities.confirm_cast(
		null, actor, ultimate, false, func(_w, _e, _k, _d, _a): return true,
	), "ultimate commits")
	assert_eq(actor["ult_points"], 0, "ultimate points are spent on success")

	actor = _cast_actor("jett")
	actor["ability_slots"]["e"]["n"] = 0
	Mechanics.prime_jett_dash(actor, 30.0)
	var recast := Abilities.start_cast(actor, "e", 31.0, true)
	assert_true(recast["ok"], "live Jett recast bypasses empty charge")
	assert_true(recast["recast"], "cast is marked as recast")
	assert_true(Abilities.confirm_cast(
		null, actor, recast, false, func(_w, _e, _k, _d, _a): return true,
	), "recast confirms")
	assert_eq(actor["ability_slots"]["e"]["n"], 0, "recast spends no second charge")

	actor = _cast_actor("omen")
	var canceled := Abilities.start_cast(actor, "c", 40.0, true)
	Abilities.cancel_cast(canceled)
	assert_false(Abilities.confirm_cast(
		null, actor, canceled, false, func(_w, _e, _k, _d, _a): return true,
	), "canceled cast cannot confirm")
	assert_eq(actor["ability_slots"]["c"]["n"], 1, "cancel keeps charge")

	var clove := _cast_actor("clove")
	clove["alive"] = false
	clove["ability_state"]["clove_death_until"] = 60.0
	assert_true(Abilities.start_cast(clove, "e", 50.0, true)["ok"], "Clove Ruse is allowed post-death")
	assert_false(Abilities.start_cast(clove, "q", 50.0, true)["ok"], "other Clove casts stay blocked post-death")

	actor = _cast_actor("sova")
	actor["ability_slots"]["q"]["n"] = 2
	actor["suppressed_until"] = 100.0
	assert_false(Abilities.cast_for_bot(
		null, actor, "q", 50.0, func(_w, _e, _k, _d, _a): return true,
	), "Bot cast uses suppression validator")
	assert_eq(actor["ability_slots"]["q"]["n"], 2, "rejected Bot cast keeps charge")
	actor["suppressed_until"] = 0.0
	assert_true(Abilities.cast_for_bot(
		null, actor, "q", 50.0, func(_w, _e, _k, _d, _a): return true,
	), "Bot cast uses common commit path")
	assert_eq(actor["ability_slots"]["q"]["n"], 1, "successful Bot cast spends one charge")

	var tejo := _cast_actor("tejo")
	var salvo_world := FakeAbilityWorld.new()
	salvo_world.clock = 10.0
	var salvo := Abilities.start_cast(tejo, "e", salvo_world.clock, true)
	assert_true(Abilities.confirm_cast(salvo_world, tejo, salvo), "Tejo Guided Salvo schedules")
	assert_eq(salvo_world.explosions.size(), 0, "Guided Salvo does not explode immediately")
	assert_eq(salvo_world.ability_events.size(), 2, "Guided Salvo schedules both targets")
	Runtime.run_ability_events(salvo_world.ability_events, 11.19)
	assert_eq(salvo_world.explosions.size(), 0, "Guided Salvo waits 1.2 seconds")
	Runtime.run_ability_events(salvo_world.ability_events, 11.2)
	assert_eq(salvo_world.explosions.size(), 2, "Guided Salvo lands both targets together")

	var armageddon_world := FakeAbilityWorld.new()
	armageddon_world.clock = 20.0
	tejo = _cast_actor("tejo")
	tejo["ult_points"] = int(Catalog.agent("tejo")["ultCost"])
	var armageddon := Abilities.start_cast(tejo, "x", armageddon_world.clock, true)
	assert_true(Abilities.confirm_cast(armageddon_world, tejo, armageddon), "Tejo Armageddon schedules")
	assert_eq(armageddon_world.orbitals.size(), 0, "Armageddon does not strike immediately")
	assert_eq(armageddon_world.ability_events.size(), 6, "Armageddon schedules six advancing strikes")
	Runtime.run_ability_events(armageddon_world.ability_events, 20.44)
	assert_eq(armageddon_world.orbitals.size(), 0, "Armageddon waits for first warning")
	Runtime.run_ability_events(armageddon_world.ability_events, 20.45)
	assert_eq(armageddon_world.orbitals.size(), 1, "Armageddon first strike lands at 0.45 seconds")
	assert_eq(armageddon_world.orbitals[0]["point"], Vector3(1, 0, -3), "Armageddon advances five metres")
	armageddon_world.ability_events.clear()

	var scout_world := FakeAbilityWorld.new()
	var scout_casts := [
		["sova", "c"], ["cypher", "e"], ["fade", "c"],
		["gekko", "q"], ["gekko", "e"], ["gekko", "x"],
		["tejo", "c"], ["skye", "q"], ["yoru", "c"],
	]
	for entry in scout_casts:
		var scout_actor := _cast_actor(entry[0])
		if entry[1] == "x":
			scout_actor["ult_points"] = int(Catalog.agent(entry[0])["ultCost"])
		var scout_cast := Abilities.start_cast(scout_actor, entry[1], 1.0, true)
		assert_true(Abilities.confirm_cast(scout_world, scout_actor, scout_cast), "%s scout cast" % entry[0])
	assert_eq(scout_world.legacy_units, [], "official scouts never use legacy drone/boombot proxies")
	assert_eq(scout_world.scouts.size(), 9, "all nine scout abilities keep distinct units")
	if scout_world.scouts.size() == 9:
		var expected_scouts := [
			["sova", 8.0, 7.0, true, ""], ["camera", 12.0, 0.0, false, ""],
			["prowler", 6.0, 8.0, true, ""], ["wingman", 7.0, 7.0, true, "wingman"],
			["dizzy", 5.0, 5.0, true, "dizzy"], ["thrash", 8.0, 9.0, true, "thrash"],
			["tejo", 8.0, 7.0, true, ""], ["trailblazer", 6.0, 8.0, true, ""],
			["decoy", 10.0, 6.0, false, ""],
		]
		for index in expected_scouts.size():
			var actual: Dictionary = scout_world.scouts[index]
			var expected: Array = expected_scouts[index]
			assert_eq(actual["type"], expected[0], "scout %d type" % index)
			assert_eq(actual["duration"], expected[1], "scout %d duration" % index)
			assert_eq(actual["speed"], expected[2], "scout %d speed" % index)
			assert_eq(actual["controlled"], expected[3], "scout %d control mode" % index)
			assert_eq(actual["globule"], expected[4], "scout %d globule" % index)

	var reyna := _cast_actor("reyna")
	reyna["resources"]["soul_orbs"] = [{"until": 13.0}]
	var reyna_world := FakeAbilityWorld.new()
	reyna_world.clock = 10.0
	var devour := Abilities.start_cast(reyna, "q", reyna_world.clock, true)
	assert_true(Abilities.confirm_cast(reyna_world, reyna, devour), "Reyna Devour consumes a live soul")
	assert_eq(reyna["heal_queue"], 100.0, "Reyna Devour queues full healing")
	assert_eq(reyna["armor"], 25.0, "Reyna Devour grants 25 armor")

	var harbor := _cast_actor("harbor")
	var storm_target := _actor("sage")
	storm_target["team"] = "enemy"
	storm_target["pos"] = Vector3(1, 0, -10)
	storm_target["flash_until"] = 0.0
	var harbor_world := FakeAbilityWorld.new()
	harbor_world.clock = 10.0
	harbor_world.fighters = [harbor, storm_target]
	var storm := Abilities.start_cast(harbor, "c", harbor_world.clock, true)
	assert_true(Abilities.confirm_cast(harbor_world, harbor, storm), "Harbor Storm Surge schedules")
	assert_eq(harbor_world.slow_zones.size(), 0, "Storm Surge waits through warning")
	Runtime.run_ability_events(harbor_world.ability_events, 10.89)
	assert_eq(harbor_world.slow_zones.size(), 0, "Storm Surge does not land before 0.9 seconds")
	Runtime.run_ability_events(harbor_world.ability_events, 10.9)
	assert_eq(harbor_world.slow_zones.size(), 1, "Storm Surge creates its slow zone")
	assert_eq(storm_target["flash_until"], 12.9, "Storm Surge flashes enemies in its radius")

	var fade := _cast_actor("fade")
	var seized := _actor("sage")
	seized["team"] = "enemy"
	seized["pos"] = Vector3(1, 0, -10)
	var fade_world := FakeAbilityWorld.new()
	fade_world.clock = 20.0
	fade_world.fighters = [fade, seized]
	var seize := Abilities.start_cast(fade, "q", fade_world.clock, true)
	assert_true(Abilities.confirm_cast(fade_world, fade, seize), "Fade Seize schedules")
	assert_false(seized["ability_state"].has("tether"), "Fade Seize waits through warning")
	Runtime.run_ability_events(fade_world.ability_events, 20.69)
	assert_eq(seized["hp"], 100.0, "Fade Seize does not decay health early")
	Runtime.run_ability_events(fade_world.ability_events, 20.7)
	assert_eq(seized["hp"], 75.0, "Fade Seize caps current health at 75")
	assert_eq(seized["slow_until"], 25.7, "Fade Seize slows for five seconds")
	assert_eq(seized["ability_state"]["tether"]["until"], 25.7, "Fade Seize tethers for five seconds")

	var deadlock := _cast_actor("deadlock")
	deadlock["ult_points"] = int(Catalog.agent("deadlock")["ultCost"])
	var cocooned := _actor("sage")
	cocooned["team"] = "enemy"
	cocooned["pos"] = Vector3(1, 0, -8)
	cocooned["slow_until"] = 0.0
	cocooned["suppressed_until"] = 0.0
	var deadlock_world := FakeAbilityWorld.new()
	deadlock_world.clock = 30.0
	deadlock_world.fighters = [deadlock, cocooned]
	var annihilation := Abilities.start_cast(deadlock, "x", deadlock_world.clock, true)
	assert_true(Abilities.confirm_cast(deadlock_world, deadlock, annihilation), "Deadlock Annihilation finds a target")
	assert_true(cocooned["ability_state"].has("cocoon"), "Annihilation applies cocoon state")
	assert_eq(cocooned["slow_until"], 37.0, "Annihilation slows for seven seconds")
	assert_eq(cocooned["suppressed_until"], 37.0, "Annihilation suppresses for seven seconds")
	Runtime.run_ability_events(deadlock_world.ability_events, 36.99)
	assert_true(cocooned["alive"], "Annihilation target survives before seven seconds")
	Runtime.run_ability_events(deadlock_world.ability_events, 37.0)
	assert_false(cocooned["alive"], "Annihilation kills an attached target after seven seconds")

	var iso := _cast_actor("iso")
	iso["ult_points"] = int(Catalog.agent("iso")["ultCost"])
	var duelist := _actor("sage")
	duelist["team"] = "enemy"
	duelist["pos"] = Vector3(41, 0, 2)
	duelist["revealed_until"] = 0.0
	var iso_world := FakeAbilityWorld.new()
	iso_world.clock = 40.0
	iso_world.fighters = [iso, duelist]
	var contract := Abilities.start_cast(iso, "x", iso_world.clock, true)
	assert_true(Abilities.confirm_cast(iso_world, iso, contract), "Iso Kill Contract selects the nearest living enemy")
	assert_true(iso["ability_state"].has("duel"), "Kill Contract marks Iso's duel target")
	assert_true(duelist["ability_state"].has("duel"), "Kill Contract marks the enemy's duel target")
	if iso["ability_state"].has("duel") and duelist["ability_state"].has("duel"):
		assert_eq(iso["ability_state"]["duel"]["target"], duelist, "Iso duel points to enemy")
		assert_eq(duelist["ability_state"]["duel"]["target"], iso, "enemy duel points to Iso")
		assert_eq(iso["ability_state"]["duel"]["until"], 55.0, "Iso duel lasts fifteen seconds")
	assert_eq(duelist["revealed_until"], 55.0, "Kill Contract reveals the enemy for the duel")

func _test_combat_and_round_integration() -> void:
	var iso := _actor("iso")
	iso["ability_state"]["iso_shield"] = true
	var shielded := Mechanics.resolve_damage(iso, 150.0, 10.0)
	assert_true(shielded["blocked"], "Iso shield blocks one complete damage instance")
	assert_eq(iso["hp"], 100.0, "Iso shield preserves hp")
	var lethal := Mechanics.resolve_damage(iso, 150.0, 11.0)
	assert_true(lethal["killed"], "unshielded lethal damage kills")

	var armored := _actor("sage")
	armored["armor"] = 50.0
	armored["armor_max"] = 50.0
	var armored_hit := Mechanics.resolve_damage(armored, 60.0, 1.0)
	assert_eq(armored_hit["absorbed"], 39.6, "armor absorbs configured damage share")
	assert_eq(armored["hp"], 79.6, "armor leaves remainder for hp")

	var phoenix := _actor("phoenix")
	phoenix["pos"] = Vector3(2, 0, 3)
	Mechanics.activate_return_anchor(phoenix, 20.0)
	phoenix["pos"] = Vector3(20, 0, 20)
	var returned := Mechanics.resolve_damage(phoenix, 200.0, 10.0)
	assert_true(returned["prevented"], "Phoenix fatality hook runs inside damage resolver")
	assert_false(returned["killed"], "Phoenix return is not a death")
	assert_eq(phoenix["pos"], Vector3(2, 0, 3), "damage resolver restores Phoenix anchor")

	var queue: Array = []
	Runtime.schedule_ability_event(queue, 5.0, func(): pass)
	var utility_store := Runtime.create_utility_store()
	Runtime.register_utility(utility_store, {"type": "turret", "team": "ally"})
	var control_state := {"control_mode": {"owner": 1, "unit": 2}}
	Runtime.clear_round_state(queue, utility_store, control_state)
	assert_eq(queue, [], "round cleanup clears scheduled gameplay events")
	assert_eq(utility_store["items"], [], "round cleanup clears runtime utility")
	assert_eq(utility_store["next_id"], 1, "round cleanup resets stable id sequence")
	assert_eq(control_state["control_mode"], null, "round cleanup ends controlled unit mode")

func _test_bot_intents() -> void:
	var intents := {}
	for definition in Catalog.all_abilities():
		var intent := String(definition["intent"])
		intents[intent] = true
		assert_true(Abilities.supports_intent(intent), "supported Bot intent: %s" % intent)
	assert_eq(intents.size(), 10, "upstream exposes ten ability intents")
	assert_eq(Abilities.supported_intents().size(), 10, "Bot supports exactly upstream intents")

	assert_eq(Abilities.bot_utility_intent({"enemy_channeling": true}), "deny", "channel denial intent")
	assert_eq(Abilities.bot_utility_intent({"hurt": true, "safe_escape": true}), "escape", "hurt escape intent")
	assert_eq(Abilities.bot_utility_intent({"retaking": true, "contact_confidence": 0.2}), "info", "retake info intent")
	assert_eq(Abilities.bot_utility_intent({"executing": true, "dangerous_sightline": true}), "cover", "execute cover intent")
	assert_eq(Abilities.bot_utility_intent({"executing": true}), "entry", "execute entry intent")
	assert_eq(Abilities.bot_utility_intent({}), "hold", "default hold intent")

	assert_eq(Abilities.bot_ability_order("astra", {
		"in_combat": true, "executing": false, "enemy_channeling": false,
		"tactical_intent": "hold",
	}), ["x", "e", "q", "c"], "combat uses upstream X/E/Q/C order")
	assert_eq(Abilities.bot_ability_order("sage", {
		"in_combat": true, "hurt": true, "safe_time": true,
		"executing": false, "enemy_channeling": false, "tactical_intent": "hold",
	}), ["x", "e", "q"], "Sage filters heal and combat intents")
	assert_eq(Abilities.bot_ability_order("omen", {
		"in_combat": true, "hurt": true, "safe_time": false,
		"executing": false, "enemy_channeling": false, "tactical_intent": "escape",
	}), ["x", "q", "c"], "Omen considers escape only under escape intent")
	assert_eq(Abilities.bot_ability_order("chamber", {
		"state": "hold", "in_combat": false, "executing": false,
		"enemy_channeling": false, "tactical_intent": "hold", "has_primary": true,
	}), ["c"], "out-of-combat Chamber only considers setup")
	assert_eq(Abilities.bot_ability_order("sova", {
		"state": "execute", "in_combat": false, "executing": true,
		"enemy_channeling": false, "tactical_intent": "entry", "team_role": "info",
	}), ["x", "e", "q", "c"], "executing info Bot considers all eligible Sova slots")

func _actor(agent_id: String) -> Dictionary:
	return {
		"agent": agent_id,
		"id": 1,
		"team": "ally",
		"alive": true,
		"hp": 100.0,
		"armor": 0.0,
		"armor_max": 0.0,
		"pos": Vector3(1, 0, 2),
		"ability_state": {},
		"resources": {},
		"ability_slots": {},
		"channel": null,
		"heal_queue": 0.0,
		"knife_ult": 0,
		"stim_until": 0.0,
		"speed_mul": 1.0,
	}

func _cast_actor(agent_id: String) -> Dictionary:
	var actor := _actor(agent_id)
	actor["agent_id"] = agent_id
	actor["ability_slots"] = Abilities.make_slots(agent_id)
	actor["ult_points"] = 0
	actor["suppressed_until"] = 0.0
	return actor

func assert_true(value: bool, label: String) -> void:
	checks += 1
	if not value:
		_fail(label, true, value)

func assert_false(value: bool, label: String) -> void:
	checks += 1
	if value:
		_fail(label, false, value)

func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected:
		_fail(label, expected, actual)

func _fail(label: String, expected: Variant, actual: Variant) -> void:
	failures += 1
	push_error("%s: expected %s, got %s" % [label, str(expected), str(actual)])

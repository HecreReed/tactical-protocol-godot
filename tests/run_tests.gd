extends SceneTree

const Catalog := preload("res://scripts/agent_catalog.gd")
const Runtime := preload("res://scripts/ability_runtime.gd")

var failures := 0
var checks := 0

func _init() -> void:
	_test_catalog()
	_test_core_runtime()
	_test_utility_runtime()
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
	assert_eq(Catalog.map_ids().size(), 11, "official map count")
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

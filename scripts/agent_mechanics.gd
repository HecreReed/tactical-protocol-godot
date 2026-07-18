class_name AgentMechanics
extends RefCounted

static func init_agent_state(entity: Variant) -> void:
	var state := _ensure_dictionary(entity, "ability_state")
	var resources := _ensure_dictionary(entity, "resources")
	match _agent_id(entity):
		"viper":
			resources["fuel"] = 100.0
		"neon":
			resources["energy"] = 100.0
			resources["slide_charges"] = 1
			resources["slide_kills"] = 0
		"reyna":
			resources["soul_orbs"] = []
		"astra":
			resources["stars"] = 4
			resources["star_sequence"] = 1
			resources["placed_stars"] = []
		"skye":
			resources["regrowth"] = 100.0
		"raze":
			resources["paint_kills"] = 0
		"gekko":
			resources["globules"] = {}
	if state.is_empty():
		_write_value(entity, "ability_state", state)

static func on_round_start(entity: Variant) -> void:
	_write_value(entity, "ability_state", {})
	_write_value(entity, "resources", {})
	_set_if_present(entity, "channel", null)
	_set_if_present(entity, "heal_queue", 0.0)
	_set_if_present(entity, "speed_mul", 1.0)
	init_agent_state(entity)
	var slots := _ability_slots(entity)
	for key in slots:
		var slot: Dictionary = slots[key]
		var definition: Dictionary = slot.get("def", {})
		slot["n"] = int(definition.get("start", 0 if String(key) == "x" else 1))
		slot["cd_until"] = 0.0

static func place_astra_star(entity: Variant, position: Variant) -> Variant:
	var resources := _resources(entity)
	if int(resources.get("stars", 0)) <= 0:
		return null
	var sequence := int(resources.get("star_sequence", 1))
	var star := {
		"id": "star-%d" % sequence,
		"pos": _clone_point(position),
		"active": true,
	}
	resources["star_sequence"] = sequence + 1
	resources["stars"] = int(resources.get("stars", 0)) - 1
	var stars: Array = resources.get("placed_stars", [])
	stars.append(star)
	resources["placed_stars"] = stars
	return star

static func consume_astra_star(entity: Variant, id: String, effect: String) -> bool:
	for star in _resources(entity).get("placed_stars", []):
		if String(star.get("id", "")) == id and bool(star.get("active", false)):
			star["active"] = false
			star["effect"] = effect
			return true
	return false

static func prime_jett_dash(entity: Variant, now: float) -> void:
	_state(entity)["jett_dash"] = {"primed_at": now, "until": now + 7.5}

static func consume_jett_dash(entity: Variant, now: float) -> bool:
	var state := _state(entity)
	var dash: Dictionary = state.get("jett_dash", {})
	if dash.is_empty() or now < float(dash.get("primed_at", INF)) or now > float(dash.get("until", -INF)):
		return false
	state.erase("jett_dash")
	return true

static func activate_return_anchor(entity: Variant, until: float) -> void:
	_state(entity)["run_it_back"] = {"pos": _position(entity), "until": until}

static func return_to_anchor(entity: Variant) -> bool:
	var state := _state(entity)
	var anchor: Dictionary = state.get("run_it_back", {})
	if anchor.is_empty():
		return false
	_set_position(entity, anchor.get("pos", Vector3.ZERO))
	_write_value(entity, "hp", 100.0)
	_set_if_present(entity, "heal_queue", 0.0)
	_set_if_present(entity, "channel", null)
	state.erase("run_it_back")
	return true

static func resolve_fatality(entity: Variant, now: float) -> Dictionary:
	var state := _state(entity)
	if _agent_id(entity) == "phoenix":
		var anchor: Dictionary = state.get("run_it_back", {})
		if not anchor.is_empty() and now <= float(anchor.get("until", 0.0)):
			return_to_anchor(entity)
			return {"prevented": true, "mode": "return"}
	if _agent_id(entity) == "kayo" and now <= float(state.get("null_cmd_until", 0.0)):
		_write_value(entity, "hp", 1.0)
		_write_value(entity, "channel", "downed")
		state["downed_until"] = now + 15.0
		return {"prevented": true, "mode": "downed"}
	return {"prevented": false}

static func on_kill(killer: Variant, target: Variant, now: float) -> void:
	var agent := _agent_id(killer)
	var state := _state(killer)
	var resources := _resources(killer)
	if agent == "jett" and int(_read_value(killer, "knife_ult", 0)) > 0:
		_write_value(killer, "knife_ult", 5)
	if agent == "raze":
		resources["paint_kills"] = int(resources.get("paint_kills", 0)) + 1
		if int(resources["paint_kills"]) >= 2:
			resources["paint_kills"] = 0
			var signature: Dictionary = _ability_slots(killer).get("e", {})
			if not signature.is_empty():
				var definition: Dictionary = signature.get("def", {})
				signature["n"] = mini(
					int(definition.get("max", 1)), int(signature.get("n", 0)) + 1,
				)
	if agent == "reyna":
		var souls: Array = resources.get("soul_orbs", [])
		souls.append({"pos": _position(target, _position(killer)), "until": now + 3.0})
		resources["soul_orbs"] = souls
	if agent == "neon":
		resources["energy"] = minf(100.0, float(resources.get("energy", 0.0)) + 25.0)
		resources["slide_kills"] = int(resources.get("slide_kills", 0)) + 1
		if int(resources["slide_kills"]) >= 2:
			resources["slide_kills"] = 0
			resources["slide_charges"] = 1
	if agent == "iso" and now < float(state.get("double_tap_until", 0.0)):
		state["iso_shield"] = true
	if agent == "clove":
		state["pick_me_up_until"] = now + 10.0
		state.erase("clove_prove_until")
	if agent == "miks" and now < float(state.get("harmonize_until", 0.0)):
		state["harmonize_until"] = now + 10.0

static func consume_reyna_soul(entity: Variant, mode: String, now: float) -> bool:
	var resources := _resources(entity)
	var souls: Array = resources.get("soul_orbs", [])
	var live_index := -1
	for index in souls.size():
		if now <= float(souls[index].get("until", 0.0)):
			live_index = index
			break
	if live_index < 0:
		return false
	souls.remove_at(live_index)
	if mode == "devour":
		_write_value(entity, "heal_queue", maxf(float(_read_value(entity, "heal_queue", 0.0)), 100.0))
		_state(entity)["overheal_hold_until"] = now + 30.0
	elif mode == "dismiss":
		_state(entity)["dismiss_until"] = now + 2.0
	return true

static func start_neon_sprint(entity: Variant) -> bool:
	if float(_resources(entity).get("energy", 0.0)) <= 0.0:
		return false
	_state(entity)["neon_sprinting"] = true
	return true

static func use_neon_slide(entity: Variant) -> bool:
	var resources := _resources(entity)
	if int(resources.get("slide_charges", 0)) <= 0:
		return false
	resources["slide_charges"] = int(resources["slide_charges"]) - 1
	_state(entity)["neon_slide"] = true
	return true

static func place_rendezvous(entity: Variant, position: Variant) -> void:
	_state(entity)["rendezvous"] = {"pos": _clone_point(position), "active": true}

static func use_rendezvous(entity: Variant) -> bool:
	var anchor: Dictionary = _state(entity).get("rendezvous", {})
	if anchor.is_empty() or not bool(anchor.get("active", false)):
		return false
	_set_position(entity, anchor.get("pos", Vector3.ZERO))
	anchor["active"] = false
	return true

static func can_neural_theft(entity: Variant, corpses: Array, now: float) -> bool:
	for corpse in corpses:
		var victim = corpse.get("entity", corpse.get("ent"))
		var died_at := float(corpse.get("died_at", corpse.get("diedAt", -INF)))
		if victim != null and _read_value(victim, "team", null) != _read_value(entity, "team", null) and now - died_at <= 6.0:
			return true
	return false

static func apply_skye_regrowth(skye: Variant, entities: Array, delta: float) -> bool:
	var resources := _resources(skye)
	if float(resources.get("regrowth", 0.0)) <= 0.0:
		return false
	var healed := false
	for entity in entities:
		var hp := float(_read_value(entity, "hp", 0.0))
		if entity == skye or _read_value(entity, "team", null) != _read_value(skye, "team", null):
			continue
		if not bool(_read_value(entity, "alive", hp > 0.0)) or hp <= 0.0 or hp >= 100.0:
			continue
		_write_value(entity, "hp", minf(100.0, hp + 20.0 * delta))
		healed = true
	if healed:
		resources["regrowth"] = maxf(0.0, float(resources["regrowth"]) - 20.0 * delta)
	return healed

static func can_clove_post_death_cast(entity: Variant, type: String, now: float) -> bool:
	return (
		_agent_id(entity) == "clove"
		and not bool(_read_value(entity, "alive", false))
		and type == "cloveRuse"
		and now <= float(_state(entity).get("clove_death_until", 0.0))
	)

static func activate_clove_revive(entity: Variant, now: float) -> bool:
	var state := _state(entity)
	if _agent_id(entity) != "clove" or now > float(state.get("clove_revive_until", 0.0)):
		return false
	_write_value(entity, "alive", true)
	_write_value(entity, "hp", 100.0)
	_set_if_present(entity, "channel", null)
	state.erase("clove_revive_until")
	return true

static func on_death(entity: Variant, now: float) -> void:
	if _agent_id(entity) == "clove":
		_state(entity)["clove_death_until"] = now + 30.0

static func reclaim_gekko_globule(entity: Variant, key: String, now: float) -> bool:
	var globules: Dictionary = _resources(entity).get("globules", {})
	var globule: Dictionary = globules.get(key, {})
	if globule.is_empty() or now > float(globule.get("until", 0.0)):
		return false
	globules.erase(key)
	return true

static func consume_iso_shield(entity: Variant) -> bool:
	var state := _state(entity)
	if not bool(state.get("iso_shield", false)):
		return false
	state["iso_shield"] = false
	return true

static func harmonize_pair(miks: Variant, ally: Variant, now: float) -> void:
	_state(miks)["harmonize_until"] = now + 10.0
	_state(ally)["harmonize_until"] = now + 10.0
	_write_value(miks, "stim_until", now + 10.0)
	_write_value(ally, "stim_until", now + 10.0)

static func is_debuff_immune(entity: Variant, now: float) -> bool:
	return _agent_id(entity) == "veto" and now < float(_state(entity).get("evolution_until", 0.0))

static func place_return_anchor(entity: Variant, key: String, until: float) -> void:
	_state(entity)["%s_anchor" % key] = {"pos": _position(entity), "until": until}

static func return_to_light_anchor(entity: Variant, key: String, now: float) -> bool:
	var state := _state(entity)
	var state_key := "%s_anchor" % key
	var anchor: Dictionary = state.get(state_key, {})
	if anchor.is_empty() or now > float(anchor.get("until", 0.0)):
		return false
	_set_position(entity, anchor.get("pos", Vector3.ZERO))
	state.erase(state_key)
	return true

static func select_tejo_target(entity: Variant, position: Variant) -> int:
	var state := _state(entity)
	var targets: Array = state.get("tejo_targets", [])
	if targets.size() < 2:
		targets.append(_clone_point(position))
	state["tejo_targets"] = targets
	return targets.size()

static func set_viper_emitter(entity: Variant, key: String, active: bool) -> void:
	var state := _state(entity)
	var emitters: Dictionary = state.get("viper_emitters", {})
	emitters[key] = active
	state["viper_emitters"] = emitters

static func tick(entity: Variant, now: float, delta: float) -> void:
	var agent := _agent_id(entity)
	var state := _state(entity)
	var resources := _resources(entity)
	if agent == "phoenix":
		var anchor: Dictionary = state.get("run_it_back", {})
		if not anchor.is_empty() and now >= float(anchor.get("until", INF)):
			return_to_anchor(entity)
	if agent == "kayo" and _read_value(entity, "channel", null) == "downed":
		if now >= float(state.get("downed_until", INF)):
			_write_value(entity, "hp", 0.0)
	if agent == "viper":
		var emitters: Dictionary = state.get("viper_emitters", {})
		var active := false
		for value in emitters.values():
			if bool(value):
				active = true
				break
		var rate := -15.0 if active else 5.0
		resources["fuel"] = clampf(float(resources.get("fuel", 100.0)) + rate * delta, 0.0, 100.0)
		if float(resources["fuel"]) <= 0.0:
			for key in emitters:
				emitters[key] = false
	if agent == "neon":
		var sprinting := bool(state.get("neon_sprinting", false))
		var rate := -10.0 if sprinting else 5.0
		resources["energy"] = clampf(float(resources.get("energy", 100.0)) + rate * delta, 0.0, 100.0)
		if float(resources["energy"]) <= 0.0:
			state["neon_sprinting"] = false
	if agent == "clove" and bool(_read_value(entity, "alive", false)):
		if state.has("clove_prove_until") and now >= float(state["clove_prove_until"]):
			state.erase("clove_prove_until")
			state["force_death"] = true
	if agent == "yoru" and float(_read_value(entity, "speed_mul", 1.0)) > 1.0:
		if now >= float(state.get("drift_until", 0.0)):
			_write_value(entity, "speed_mul", 1.0)
	if agent == "reyna":
		var armor := float(_read_value(entity, "armor", 0.0))
		var armor_max := float(_read_value(entity, "armor_max", 0.0))
		if armor > armor_max and now >= float(state.get("overheal_hold_until", 0.0)):
			_write_value(entity, "armor", maxf(armor_max, armor - 2.0 * delta))

static func _state(entity: Variant) -> Dictionary:
	return _ensure_dictionary(entity, "ability_state")

static func _resources(entity: Variant) -> Dictionary:
	return _ensure_dictionary(entity, "resources")

static func _ability_slots(entity: Variant) -> Dictionary:
	var slots = _read_value(entity, "ability_slots", null)
	if slots is Dictionary:
		return slots
	slots = _read_value(entity, "ab", null)
	return slots if slots is Dictionary else {}

static func _agent_id(entity: Variant) -> String:
	var id := String(_read_value(entity, "agent", ""))
	return id if not id.is_empty() else String(_read_value(entity, "agent_id", ""))

static func _position(entity: Variant, fallback: Variant = Vector3.ZERO) -> Variant:
	var position = _read_value(entity, "pos", null)
	if position == null:
		position = _read_value(entity, "global_position", fallback)
	return _clone_point(position)

static func _set_position(entity: Variant, position: Variant) -> void:
	if entity is Dictionary:
		entity["pos"] = _clone_point(position)
	elif entity is Object:
		if _has_property(entity, "pos"):
			entity.set("pos", _clone_point(position))
		elif _has_property(entity, "global_position"):
			entity.set("global_position", _as_vector3(position))

static func _clone_point(point: Variant) -> Variant:
	if point is Vector3:
		return point
	if point is Dictionary:
		return {
			"x": float(point.get("x", 0.0)),
			"y": float(point.get("y", 0.0)),
			"z": float(point.get("z", 0.0)),
		}
	return Vector3.ZERO

static func _as_vector3(point: Variant) -> Vector3:
	if point is Vector3:
		return point
	if point is Dictionary:
		return Vector3(
			float(point.get("x", 0.0)),
			float(point.get("y", 0.0)),
			float(point.get("z", 0.0)),
		)
	return Vector3.ZERO

static func _ensure_dictionary(entity: Variant, key: String) -> Dictionary:
	var value = _read_value(entity, key, null)
	if value is Dictionary:
		return value
	var dictionary := {}
	_write_value(entity, key, dictionary)
	return dictionary

static func _read_value(entity: Variant, key: String, default: Variant = null) -> Variant:
	if entity is Dictionary:
		return entity.get(key, default)
	if entity is Object and _has_property(entity, key):
		return entity.get(key)
	return default

static func _write_value(entity: Variant, key: String, value: Variant) -> void:
	if entity is Dictionary:
		entity[key] = value
	elif entity is Object and _has_property(entity, key):
		entity.set(key, value)

static func _set_if_present(entity: Variant, key: String, value: Variant) -> void:
	if entity is Dictionary:
		if entity.has(key):
			entity[key] = value
	elif entity is Object and _has_property(entity, key):
		entity.set(key, value)

static func _has_property(entity: Object, key: String) -> bool:
	for property in entity.get_property_list():
		if String(property.get("name", "")) == key:
			return true
	return false

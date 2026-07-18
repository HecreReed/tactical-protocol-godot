class_name AbilityRuntime
extends RefCounted

static func commit_ability(slot: Dictionary, used: bool) -> bool:
	if not used:
		return false
	slot["n"] = maxi(0, int(slot.get("n", 0)) - 1)
	return true

static func clamp_resource(value: float, minimum: float = 0.0, maximum: float = 100.0) -> float:
	return clampf(value, minimum, maximum)

static func extend_status(entity: Dictionary, key: String, until: float) -> float:
	var extended := maxf(float(entity.get(key, 0.0)), until)
	entity[key] = extended
	return extended

static func open_recast(entity: Dictionary, key: String, until: float, payload: Variant = null) -> void:
	if not entity.has("ability_state") or not entity["ability_state"] is Dictionary:
		entity["ability_state"] = {}
	entity["ability_state"][key] = {"until": until, "payload": payload}

static func consume_recast(entity: Dictionary, key: String, now: float) -> Variant:
	var state: Dictionary = entity.get("ability_state", {})
	if not state.has(key):
		return null
	var recast: Dictionary = state[key]
	state.erase(key)
	if now > float(recast.get("until", 0.0)):
		return null
	return recast.get("payload")

static func schedule_ability_event(
	queue: Array, at: float, callback: Callable, tag: String = "ability",
) -> Dictionary:
	var event := {"at": at, "callback": callback, "tag": tag}
	queue.append(event)
	queue.sort_custom(func(a, b): return float(a["at"]) < float(b["at"]))
	return event

static func run_ability_events(queue: Array, now: float) -> void:
	while not queue.is_empty() and float(queue[0]["at"]) <= now:
		var event: Dictionary = queue.pop_front()
		var callback: Callable = event.get("callback", Callable())
		if callback.is_valid():
			callback.call()

static func create_utility_store() -> Dictionary:
	return {"items": [], "next_id": 1}

static func register_utility(store: Dictionary, spec: Dictionary) -> Dictionary:
	var utility := {
		"id": "utility-%d" % int(store.get("next_id", 1)),
		"type": "utility",
		"team": "",
		"owner_id": null,
		"hp": 1.0,
		"active": true,
		"recallable": false,
		"radius": 0.0,
		"until": INF,
		"pos": Vector3.ZERO,
	}
	store["next_id"] = int(store.get("next_id", 1)) + 1
	for key in spec:
		utility[key] = spec[key]
	var items: Array = store["items"]
	items.append(utility)
	return utility

static func damage_utility(store: Dictionary, id: String, amount: float, source_team: Variant) -> bool:
	var utility := _find_utility(store, id)
	if utility.is_empty() or utility.get("team") == source_team:
		return false
	utility["hp"] = float(utility.get("hp", 1.0)) - maxf(0.0, amount)
	if float(utility["hp"]) > 0.0:
		return false
	_remove_utility(store, utility, "damage")
	return true

static func recall_utility(store: Dictionary, id: String, owner_id: Variant) -> Variant:
	var utility := _find_utility(store, id)
	if utility.is_empty() or not bool(utility.get("recallable", false)):
		return null
	if utility.get("owner_id") != owner_id:
		return null
	return _remove_utility(store, utility, "recall")

static func intercept_projectile(store: Dictionary, projectile: Dictionary) -> bool:
	if not bool(projectile.get("interceptable", false)):
		return false
	var projectile_position := _as_vector3(projectile.get("pos", Vector3.ZERO))
	for utility in store.get("items", []):
		if not bool(utility.get("active", false)):
			continue
		if utility.get("type") != "interceptor" or utility.get("team") == projectile.get("team"):
			continue
		var radius := float(utility.get("radius", 0.0))
		var utility_position := _as_vector3(utility.get("pos", Vector3.ZERO))
		if utility_position.distance_squared_to(projectile_position) <= radius * radius:
			var callback: Callable = utility.get("on_intercept", Callable())
			if callback.is_valid():
				callback.call(projectile)
			return true
	return false

static func tick_utilities(store: Dictionary, now: float) -> void:
	var items: Array = store.get("items", [])
	for index in range(items.size() - 1, -1, -1):
		var utility: Dictionary = items[index]
		var update: Callable = utility.get("update", Callable())
		if update.is_valid():
			update.call(utility, now)
		if now >= float(utility.get("until", INF)):
			_remove_utility(store, utility, "expired")

static func begin_control(
	state: Dictionary, owner: Variant, unit: Variant, until: float = INF,
) -> Dictionary:
	state["control_mode"] = {"owner": owner, "unit": unit, "until": until}
	return state["control_mode"]

static func end_control(state: Dictionary) -> Variant:
	var mode = state.get("control_mode")
	var owner = mode.get("owner") if mode is Dictionary else null
	state["control_mode"] = null
	return owner

static func clear_round_state(queue: Array, utility_store: Dictionary, control_state: Dictionary) -> void:
	queue.clear()
	var items: Array = utility_store.get("items", [])
	for utility in items.duplicate():
		_remove_utility(utility_store, utility, "round-cleanup")
	utility_store["next_id"] = 1
	control_state["control_mode"] = null

static func valid_teleport_destination(
	point: Variant, in_bounds: Callable, blocked: Callable,
) -> bool:
	return point != null and bool(in_bounds.call(point)) and not bool(blocked.call(point))

static func _find_utility(store: Dictionary, id: String) -> Dictionary:
	for utility in store.get("items", []):
		if String(utility.get("id", "")) == id:
			return utility
	return {}

static func _remove_utility(store: Dictionary, utility: Dictionary, reason: String) -> Dictionary:
	var items: Array = store.get("items", [])
	var index := items.find(utility)
	if index >= 0:
		items.remove_at(index)
	utility["active"] = false
	var callback: Callable = utility.get("on_destroy", Callable())
	if callback.is_valid():
		callback.call(utility, reason)
	return utility

static func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Dictionary:
		return Vector3(
			float(value.get("x", 0.0)),
			float(value.get("y", 0.0)),
			float(value.get("z", 0.0)),
		)
	return Vector3.ZERO

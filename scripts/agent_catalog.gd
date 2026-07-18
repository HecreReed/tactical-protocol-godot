class_name AgentCatalog
extends RefCounted

const DATA_PATH := "res://data/agents.json"
const SLOT_KEYS := ["c", "q", "e", "x"]

static var _loaded := false
static var _data: Dictionary = {}
static var _agents_by_id: Dictionary = {}
static var _load_error := ""

static func reload() -> void:
	_loaded = false
	_data.clear()
	_agents_by_id.clear()
	_load_error = ""
	_ensure_loaded()

static func source_commit() -> String:
	_ensure_loaded()
	return String(_data.get("sourceCommit", ""))

static func source_dirty() -> bool:
	_ensure_loaded()
	return bool(_data.get("sourceDirty", false))

static func agent_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for entry in _data.get("agents", []):
		if entry is Dictionary:
			ids.append(String(entry.get("id", "")))
	return ids

static func map_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for map_id in _data.get("maps", []):
		ids.append(String(map_id))
	return ids

static func has_agent(agent_id: String) -> bool:
	_ensure_loaded()
	return _agents_by_id.has(agent_id)

static func agent(agent_id: String) -> Dictionary:
	_ensure_loaded()
	return _agents_by_id.get(agent_id, {})

static func ability(agent_id: String, key: String) -> Dictionary:
	var definition := agent(agent_id)
	if definition.is_empty():
		return {}
	var abilities: Dictionary = definition.get("ab", {})
	return abilities.get(key, {})

static func all_abilities() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for agent_id in agent_ids():
		for key in SLOT_KEYS:
			var definition := ability(agent_id, key)
			if not definition.is_empty():
				result.append(definition)
	return result

static func validation_errors() -> Array[String]:
	_ensure_loaded()
	var errors: Array[String] = []
	if not _load_error.is_empty():
		errors.append(_load_error)
		return errors

	var ids := agent_ids()
	if ids.size() != 29:
		errors.append("expected 29 agents, found %d" % ids.size())
	if map_ids().size() != 11:
		errors.append("expected 11 maps")

	var seen_agents := {}
	var seen_impls := {}
	var ability_count := 0
	for agent_id in ids:
		if agent_id.is_empty() or seen_agents.has(agent_id):
			errors.append("invalid or duplicate agent id: %s" % agent_id)
		seen_agents[agent_id] = true
		var definition := agent(agent_id)
		for field in ["name", "role", "color", "ultCost", "desc", "portrait", "ab"]:
			if not definition.has(field):
				errors.append("%s missing %s" % [agent_id, field])
		var portrait := String(definition.get("portrait", ""))
		if portrait.is_empty() or not FileAccess.file_exists(portrait):
			errors.append("%s portrait missing: %s" % [agent_id, portrait])
		for key in SLOT_KEYS:
			var slot := ability(agent_id, key)
			ability_count += 1
			for field in ["name", "type", "impl", "cost", "max", "start", "cd", "intent", "icon"]:
				if not slot.has(field):
					errors.append("%s.%s missing %s" % [agent_id, key, field])
			var implementation := String(slot.get("impl", ""))
			if implementation.is_empty() or seen_impls.has(implementation):
				errors.append("invalid or duplicate implementation: %s" % implementation)
			seen_impls[implementation] = true
			var icon := String(slot.get("icon", ""))
			if icon.is_empty() or not FileAccess.file_exists(icon):
				errors.append("%s.%s icon missing: %s" % [agent_id, key, icon])
	if ability_count != 116:
		errors.append("expected 116 abilities, found %d" % ability_count)
	return errors

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		_load_error = "cannot open %s" % DATA_PATH
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_load_error = "%s is not a JSON object" % DATA_PATH
		return
	_data = parsed
	for entry in _data.get("agents", []):
		if entry is Dictionary:
			_agents_by_id[String(entry.get("id", ""))] = entry

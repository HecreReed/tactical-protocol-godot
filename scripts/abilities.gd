class_name Abilities
extends RefCounted

const Catalog := preload("res://scripts/agent_catalog.gd")
const Runtime := preload("res://scripts/ability_runtime.gd")
const Mechanics := preload("res://scripts/agent_mechanics.gd")
const Weapons := preload("res://scripts/weapons.gd")
const SLOT_KEYS := ["c", "q", "e", "x"]
const BOT_SLOT_ORDER := ["x", "e", "q", "c"]
const SUPPORTED_INTENTS := [
	"entry", "cover", "control", "damage", "escape", "heal", "info", "setup", "weapon", "ultimate",
]

# Every upstream runtime type is registered explicitly. Values name the world adapter family.
const HANDLERS := {
	"astraGravity": "astra", "astraNova": "astra", "astraNebula": "astra", "astraDivide": "wall",
	"quake": "quake", "wallFlash": "blind", "stunWave": "daze", "bigStun": "daze",
	"stimBeacon": "device", "molly": "projectile", "smokeSky": "smoke", "orbital": "orbital",
	"chamberTrademark": "device", "chamberHeadhunter": "weapon", "chamberRendezvous": "recast", "chamberTourDeForce": "weapon",
	"clovePickMeUp": "self_buff", "cloveMeddle": "projectile", "cloveRuse": "smoke", "cloveRevive": "revive",
	"cypherTrapwire": "device", "cypherCage": "recast", "cypherSpycam": "control", "cypherNeuralTheft": "reveal",
	"deadlockGravNet": "projectile", "deadlockSensor": "device", "deadlockBarrier": "wall", "deadlockAnnihilation": "tether",
	"fadeProwler": "control", "fadeSeize": "tether", "fadeHaunt": "reveal", "fadeNightfall": "reveal",
	"gekkoMosh": "projectile", "gekkoWingman": "control", "gekkoDizzy": "control", "gekkoThrash": "control",
	"harborStormSurge": "zone", "harborHighTide": "wall", "harborCove": "recast", "harborReckoning": "daze",
	"isoContingency": "wall", "isoUndercut": "debuff", "isoDoubleTap": "self_buff", "isoKillContract": "tether",
	"smokeProj": "projectile", "updraft": "movement", "jettTailwind": "recast", "knifeUlt": "weapon",
	"fragNade": "projectile", "flash": "projectile", "suppressNade": "projectile", "kayoNullCmd": "suppress",
	"nanoSwarm": "projectile", "alarmBot": "device", "turret": "device", "lockdown": "device",
	"miksPulse": "zone", "miksHarmonize": "heal", "miksWaveform": "smoke", "miksBassquake": "daze",
	"neonFastLane": "wall", "neonRelayBolt": "projectile", "neonHighGear": "recast", "neonOverdrive": "weapon",
	"shadowStep": "teleport", "paranoia": "blind", "shadowUlt": "teleport",
	"firewall": "wall", "hotHands": "projectile", "phoenixRunItBack": "recast",
	"boomBot": "control", "razeBlastPack": "recast", "bignade": "projectile", "rocketUlt": "weapon",
	"reynaLeer": "blind", "reynaDevour": "heal", "reynaDismiss": "movement", "reynaEmpress": "self_buff",
	"wall": "wall", "slowProj": "projectile", "heal": "heal", "rez": "revive",
	"skyeRegrowth": "heal", "skyeTrailblazer": "control", "skyeGuidingLight": "projectile", "skyeSeekers": "reveal",
	"sovaDrone": "control", "shock": "projectile", "recon": "projectile", "hunterUlt": "weapon",
	"tejoDrone": "control", "tejoDelivery": "projectile", "tejoSalvo": "orbital", "tejoArmageddon": "orbital",
	"vetoCrosscut": "recast", "vetoChokehold": "projectile", "vetoInterceptor": "device", "vetoEvolution": "self_buff",
	"acidPool": "projectile", "toxicSmoke": "recast", "toxicWall": "recast", "toxicDome": "zone",
	"vyseRazorvine": "projectile", "vyseShear": "device", "vyseArcRose": "blind", "vyseSteelGarden": "debuff",
	"waylaySaturate": "projectile", "waylayLightspeed": "movement", "waylayRefract": "recast", "waylayConvergent": "daze",
	"yoruFakeout": "control", "yoruBlindside": "projectile", "yoruGatecrash": "recast", "yoruDrift": "self_buff",
}

static var AGENTS: Dictionary = _build_compat_agents()

static func agent_ids() -> Array[String]:
	return Catalog.agent_ids()

static func has_handler(type: String) -> bool:
	return HANDLERS.has(type)

static func handler_types() -> Array[String]:
	var result: Array[String] = []
	for type in HANDLERS:
		result.append(String(type))
	result.sort()
	return result

static func supports_intent(intent: String) -> bool:
	return intent in SUPPORTED_INTENTS

static func supported_intents() -> Array[String]:
	var result: Array[String] = []
	result.assign(SUPPORTED_INTENTS)
	return result

static func bot_utility_intent(context: Dictionary) -> String:
	if bool(context.get("enemy_channeling", false)):
		return "deny"
	if bool(context.get("hurt", false)) and bool(context.get("safe_escape", false)):
		return "escape"
	if bool(context.get("retaking", false)) and float(context.get("contact_confidence", 0.0)) < 0.55:
		return "info"
	if bool(context.get("executing", false)) and bool(context.get("dangerous_sightline", false)):
		return "cover"
	if bool(context.get("executing", false)):
		return "entry"
	return "hold"

static func bot_ability_order(agent_id: String, context: Dictionary) -> Array[String]:
	if not Catalog.has_agent(agent_id):
		return []
	var result: Array[String] = []
	var in_combat := bool(context.get("in_combat", false))
	var executing := bool(context.get("executing", false))
	var enemy_channeling := bool(context.get("enemy_channeling", false))
	var tactical_intent := String(context.get("tactical_intent", "hold"))
	for key in BOT_SLOT_ORDER:
		var intent := String(Catalog.ability(agent_id, key).get("intent", "entry"))
		var should_use := false
		match intent:
			"heal":
				should_use = bool(context.get("hurt", false)) and bool(context.get("safe_time", false))
			"escape":
				should_use = tactical_intent == "escape" and bool(context.get("hurt", false)) and in_combat
			"cover":
				should_use = tactical_intent in ["cover", "deny"]
			"info":
				should_use = tactical_intent == "info" or (executing and String(context.get("team_role", "")) == "info")
			"setup":
				should_use = not in_combat and (String(context.get("state", "")) in ["hold", "post"] or executing)
			"weapon":
				should_use = in_combat and not bool(context.get("has_primary", false))
			"ultimate", "control", "damage", "entry":
				should_use = in_combat or executing or enemy_channeling
		if should_use:
			result.append(key)
	return result

static func requires_equip(type: String) -> bool:
	return HANDLERS.get(type, "") in [
		"projectile", "wall", "smoke", "orbital", "teleport", "blind", "device", "zone", "tether",
	]

static func make_slots(agent_id: String) -> Dictionary:
	if not Catalog.has_agent(agent_id):
		return {}
	var slots := {}
	for key in SLOT_KEYS:
		var definition := Catalog.ability(agent_id, key)
		slots[key] = {
			"def": definition,
			"n": int(definition.get("start", 0)),
			"cd_until": 0.0,
		}
	return slots

static func start_cast(
	entity: Variant,
	key: String,
	now: float,
	fight_enabled: bool,
	phase: String = "live",
) -> Dictionary:
	var agent_id := _agent_id(entity)
	if not Catalog.has_agent(agent_id) or not key in SLOT_KEYS:
		return _rejected("unknown-slot")
	var definition := Catalog.ability(agent_id, key)
	var type := String(definition.get("type", ""))
	if not has_handler(type):
		return _rejected("missing-handler")

	var alive := bool(_read_value(entity, "alive", true))
	var clove_afterlife := (
		agent_id == "clove"
		and not alive
		and (
			type == "cloveRevive"
			or Mechanics.can_clove_post_death_cast(entity, type, now)
		)
	)
	if not alive and not clove_afterlife:
		return _rejected("dead")
	if not fight_enabled or not phase in ["live", "planted"]:
		return _rejected("phase")
	var channel = _read_value(entity, "channel", "")
	if channel != null and String(channel) != "":
		return _rejected("channel")
	if now < float(_read_value(entity, "suppressed_until", 0.0)):
		return _rejected("suppressed")

	var slots := _ability_slots(entity)
	if not slots.has(key):
		return _rejected("missing-slot-state")
	var slot: Dictionary = slots[key]
	var recast := _is_recast(entity, type, now)
	if key == "x":
		var ultimate_cost := int(Catalog.agent(agent_id).get("ultCost", 0))
		if int(_read_value(entity, "ult_points", 0)) < ultimate_cost:
			return _rejected("ultimate-points")
	elif not recast and int(slot.get("n", 0)) <= 0:
		return _rejected("charges")
	if not recast and now < float(slot.get("cd_until", 0.0)):
		return _rejected("cooldown")
	return {
		"ok": true,
		"reason": "",
		"agent_id": agent_id,
		"key": key,
		"type": type,
		"definition": definition,
		"slot": slot,
		"now": now,
		"recast": recast,
		"canceled": false,
		"confirmed": false,
	}

static func confirm_cast(
	world: Variant,
	entity: Variant,
	cast_state: Dictionary,
	alt: bool = false,
	executor: Callable = Callable(),
) -> bool:
	if (
		cast_state.is_empty()
		or not bool(cast_state.get("ok", false))
		or bool(cast_state.get("canceled", false))
		or bool(cast_state.get("confirmed", false))
	):
		return false
	if world != null:
		if not bool(world.can_fight()):
			return false
		if not bool(_read_value(entity, "alive", true)) and String(cast_state["type"]) != "cloveRevive" \
				and not Mechanics.can_clove_post_death_cast(entity, String(cast_state["type"]), float(world.now())):
			return false
		if float(world.now()) < float(_read_value(entity, "suppressed_until", 0.0)):
			return false
		cast_state["now"] = float(world.now())
	var used := false
	if executor.is_valid():
		used = bool(executor.call(
			world,
			entity,
			String(cast_state["key"]),
			cast_state["definition"],
			alt,
		))
	else:
		used = _perform(
			world,
			entity,
			String(cast_state["key"]),
			cast_state["definition"],
			float(cast_state["now"]),
			bool(cast_state["recast"]),
			alt,
		)
	if not used:
		return false
	cast_state["confirmed"] = true
	var key := String(cast_state["key"])
	if key == "x":
		_write_value(entity, "ult_points", 0)
	elif not bool(cast_state["recast"]):
		Runtime.commit_ability(cast_state["slot"], true)
	var cooldown := float(cast_state["definition"].get("cd", 0.0))
	if key != "x" and not bool(cast_state["recast"]) and cooldown > 0.0:
		cast_state["slot"]["cd_until"] = float(cast_state["now"]) + cooldown
	return true

static func cancel_cast(cast_state: Dictionary) -> void:
	if not cast_state.is_empty():
		cast_state["canceled"] = true

static func cast(world: Variant, entity: Variant, key: String, alt: bool = false) -> bool:
	if world == null:
		return false
	var now := float(world.now())
	var phase := "live" if world.can_fight() else "inactive"
	var prepared := start_cast(entity, key, now, bool(world.can_fight()), phase)
	return confirm_cast(world, entity, prepared, alt)

static func cast_for_bot(
	world: Variant,
	entity: Variant,
	key: String,
	now: float = -1.0,
	executor: Callable = Callable(),
) -> bool:
	var clock := now
	var fight_enabled := true
	if world != null:
		if clock < 0.0:
			clock = float(world.now())
		fight_enabled = bool(world.can_fight())
	if clock < 0.0:
		clock = 0.0
	var prepared := start_cast(entity, key, clock, fight_enabled)
	return confirm_cast(world, entity, prepared, false, executor)

static func _perform(
	world: Variant,
	entity: Variant,
	key: String,
	definition: Dictionary,
	now: float,
	recast: bool,
	alt: bool,
) -> bool:
	if world == null:
		return false
	var type := String(definition["type"])
	var position := _position(entity)
	var direction := _aim_direction(entity)
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	if forward.is_zero_approx():
		forward = Vector3.FORWARD
	var target_point := position + forward * 12.0
	var state := _state(entity)
	var resources := _resources(entity)
	match type:
		"smokeProj": world.throw_grenade(entity, "smoke_throw", _eye_position(entity), direction)
		"flash", "skyeGuidingLight", "yoruBlindside": world.throw_grenade(entity, "flash_throw", _eye_position(entity), direction)
		"molly": world.throw_grenade(entity, "molly_throw", _eye_position(entity), direction)
		"slowProj": world.throw_grenade(entity, "slow_throw", _eye_position(entity), direction)
		"shock": world.throw_grenade(entity, "shock_throw", _eye_position(entity), direction)
		"recon": world.throw_grenade(entity, "recon_throw", _eye_position(entity), direction)
		"fragNade", "bignade": world.throw_grenade(entity, type, _eye_position(entity), direction)
		"suppressNade": world.throw_grenade(entity, "suppress_throw", _eye_position(entity), direction)
		"nanoSwarm": world.throw_grenade(entity, "nano_throw", _eye_position(entity), direction)
		"acidPool": world.throw_grenade(entity, "acid_throw", _eye_position(entity), direction)
		"toxicSmoke":
			if recast:
				state["toxicSmoke"]["active"] = not bool(state["toxicSmoke"].get("active", false))
				Mechanics.set_viper_emitter(entity, "cloud", state["toxicSmoke"]["active"])
				if state["toxicSmoke"]["active"]:
					world.spawn_smoke(state["toxicSmoke"]["pos"], 3.8, 12.0)
				return true
			state["toxicSmoke"] = {"pos": target_point, "active": true}
			Mechanics.set_viper_emitter(entity, "cloud", true)
			world.spawn_smoke(target_point, 3.8, 12.0)
		"hotHands": world.throw_grenade(entity, "hot_hands", _eye_position(entity), direction)
		"deadlockGravNet", "cloveMeddle", "gekkoMosh", "tejoDelivery", "vetoChokehold", "vyseRazorvine", "waylaySaturate", "neonRelayBolt":
			world.throw_grenade(entity, type, _eye_position(entity), direction)
		"updraft":
			var velocity := _velocity(entity)
			velocity.y = 11.0
			_set_velocity(entity, velocity)
		"jettTailwind":
			if not state.has("jett_dash"):
				Mechanics.prime_jett_dash(entity, now)
				return false
			if not Mechanics.consume_jett_dash(entity, now):
				return false
			_set_velocity(entity, forward * 18.0 + Vector3.UP * 0.5)
		"knifeUlt": _write_value(entity, "knife_ult", 5)
		"rocketUlt": _write_value(entity, "rocket_ult", 1)
		"hunterUlt": _write_value(entity, "arrow_ult", 3)
		"neonOverdrive":
			state["overdrive_until"] = now + 20.0
			resources["energy"] = 100.0
		"chamberHeadhunter": _grant_weapon(entity, "sheriff", false, true)
		"chamberTourDeForce":
			_grant_weapon(entity, "operator", true, true)
			state["tour_de_force"] = true
		"wall": world.spawn_wall(position, _yaw(entity), 30.0)
		"firewall": world.spawn_firewall(entity, position, direction)
		"deadlockBarrier": world.spawn_wall(position + forward * 4.0, _yaw(entity), 30.0)
		"astraDivide": world.spawn_wall(position + forward * 8.0, _yaw(entity), 21.0)
		"harborHighTide":
			for index in range(1, 13):
				world.spawn_smoke(position + forward * index * 2.2, 1.6, 12.0)
		"neonFastLane":
			var side := Vector3(-forward.z, 0.0, forward.x)
			for index in range(1, 9):
				for sign in [-1.0, 1.0]:
					world.spawn_smoke(position + forward * index * 2.5 + side * sign * 2.2, 1.15, 6.0)
		"isoContingency":
			for index in range(1, 8):
				world.spawn_smoke(position + forward * index * 2.2, 1.7, 5.0)
		"quake": world.delayed_quake(entity, position + forward * 7.5)
		"wallFlash", "paranoia": world.cone_blind(entity, 20.0, 0.65, 1.6)
		"stunWave": world.cone_daze(entity, 18.0, 0.72, 2.4)
		"bigStun", "waylayConvergent": world.cone_daze(entity, 26.0, 0.55, 3.2)
		"miksBassquake": world.cone_daze(entity, 28.0, 0.55, 2.5)
		"harborReckoning":
			world.cone_daze(entity, 32.0, 0.65, 3.0)
			for enemy in _enemies(world, entity):
				if _position(enemy).distance_to(position) < 32.0:
					_write_value(enemy, "flash_until", maxf(
						float(_read_value(enemy, "flash_until", 0.0)), now + 2.0,
					))
		"stimBeacon": world.spawn_device(entity, "beacon", position + forward * 1.2)
		"alarmBot", "deadlockSensor", "chamberTrademark": world.spawn_device(entity, "alarm", target_point)
		"turret": world.spawn_device(entity, "turret", position + forward * 1.4)
		"lockdown": world.spawn_device(entity, "lockdown", position)
		"cypherTrapwire", "vyseShear": world.spawn_device(entity, "trap", target_point)
		"vetoInterceptor": world.spawn_device(entity, "interceptor", target_point)
		"smokeSky", "miksWaveform": world.smoke_site_chokes(entity)
		"cloveRuse": world.spawn_smoke(target_point, 4.5, 13.5)
		"orbital": world.orbital_strike(entity, _eye_position(entity), direction)
		"tejoSalvo":
			state["tejo_targets"] = []
			Mechanics.select_tejo_target(entity, target_point)
			Mechanics.select_tejo_target(entity, target_point + Vector3.RIGHT * 4.0)
			for point in state.get("tejo_targets", []):
				var salvo_point: Vector3 = point
				Runtime.schedule_ability_event(world.ability_events, now + 1.2, func():
					if world.can_fight():
						world.explode(entity, salvo_point, 4.0, 70.0, 35.0), "guided-salvo")
		"tejoArmageddon":
			for index in range(1, 7):
				var strike_point := position + forward * index * 5.0
				Runtime.schedule_ability_event(world.ability_events, now + index * 0.45, func():
					if world.can_fight():
						world.orbital_strike_at(entity, strike_point), "armageddon")
		"shadowStep": world.teleport_forward(entity, 9.0)
		"shadowUlt": world.teleport_site(entity)
		"razeBlastPack":
			if state.has("blast_pack"):
				var pack: Dictionary = state["blast_pack"]
				world.explode(entity, pack["pos"], 4.0, 50.0, 15.0)
				state.erase("blast_pack")
				return true
			state["blast_pack"] = {"pos": position + forward * 2.0, "until": now + 5.0}
		"waylayLightspeed", "reynaDismiss":
			_set_velocity(entity, forward * (20.0 if type == "waylayLightspeed" else 18.0))
			if type == "reynaDismiss":
				if not Mechanics.consume_reyna_soul(entity, "dismiss", now):
					return false
				_write_value(entity, "resist_until", now + 2.0)
		"neonHighGear":
			if bool(state.get("neon_sprinting", false)):
				state["neon_sprinting"] = false
			else:
				if not Mechanics.start_neon_sprint(entity):
					return false
			return true
		"chamberRendezvous":
			if recast:
				return Mechanics.use_rendezvous(entity)
			Mechanics.place_rendezvous(entity, target_point)
		"vetoCrosscut", "waylayRefract", "yoruGatecrash":
			var anchor_key := "veto" if type == "vetoCrosscut" else ("waylay" if type == "waylayRefract" else "yoru")
			if recast:
				return Mechanics.return_to_light_anchor(entity, anchor_key, now)
			Mechanics.place_return_anchor(entity, anchor_key, now + (12.0 if anchor_key == "waylay" else 30.0))
		"phoenixRunItBack": Mechanics.activate_return_anchor(entity, now + 10.0)
		"cypherCage":
			if recast:
				world.spawn_smoke(state["cypher_cage"]["pos"], 3.4, 7.0)
				state.erase("cypher_cage")
				return true
			state["cypher_cage"] = {"pos": target_point}
		"harborCove":
			if recast:
				state["harbor_cove"]["shielded"] = true
				world.spawn_device(entity, "cove", state["harbor_cove"]["pos"])
				return true
			state["harbor_cove"] = {"pos": target_point, "shielded": false}
			world.spawn_smoke(target_point, 3.8, 15.0)
		"toxicWall":
			if recast:
				state["toxicWall"]["active"] = not bool(state["toxicWall"].get("active", false))
				Mechanics.set_viper_emitter(entity, "screen", state["toxicWall"]["active"])
				if state["toxicWall"]["active"]:
					world.toxic_wall(entity, direction)
				return true
			state["toxicWall"] = {"active": true}
			Mechanics.set_viper_emitter(entity, "screen", true)
			world.toxic_wall(entity, direction)
		"heal":
			var ally: Variant = _nearest_ally(world, entity, 14.0)
			if ally == null:
				ally = entity
			if float(_read_value(ally, "hp", 100.0)) >= 100.0:
				return false
			_write_value(ally, "hp", minf(100.0, float(_read_value(ally, "hp", 0.0)) + 60.0))
		"skyeRegrowth":
			if not Mechanics.apply_skye_regrowth(entity, world.combatants(), 1.5):
				return false
		"miksHarmonize":
			var harmonized: Variant = _nearest_ally(world, entity, 14.0)
			Mechanics.harmonize_pair(entity, harmonized if harmonized != null else entity, now)
		"reynaDevour":
			if not Mechanics.consume_reyna_soul(entity, "devour", now):
				return false
			_write_value(entity, "armor", minf(50.0, float(_read_value(entity, "armor", 0.0)) + 25.0))
		"rez":
			if not bool(world.try_revive(entity)):
				return false
		"cloveRevive":
			state["clove_revive_until"] = now + 5.0
			if not Mechanics.activate_clove_revive(entity, now):
				return false
			state["clove_prove_until"] = now + 12.0
		"clovePickMeUp":
			if now > float(state.get("pick_me_up_until", 0.0)):
				return false
			_write_value(entity, "hp", minf(100.0, float(_read_value(entity, "hp", 0.0)) + 50.0))
			_write_value(entity, "stim_until", now + 8.0)
		"reynaEmpress":
			_write_value(entity, "empress_until", now + 30.0)
			_write_value(entity, "stim_until", now + 30.0)
		"isoDoubleTap": state["double_tap_until"] = now + 12.0
		"vetoEvolution":
			state["evolution_until"] = now + 15.0
			_write_value(entity, "stim_until", now + 15.0)
			_write_value(entity, "hp", 100.0)
		"yoruDrift":
			state["drift_until"] = now + 10.0
			_write_value(entity, "resist_until", now + 10.0)
			_write_value(entity, "speed_mul", 1.25)
		"kayoNullCmd":
			world.suppress_burst(position, 18.0, 4.0, entity)
			state["null_cmd_until"] = now + 12.0
			_write_value(entity, "stim_until", now + 12.0)
		"reynaLeer", "vyseArcRose": world.flash_burst(target_point + Vector3.UP * 1.8, entity)
		"cypherNeuralTheft": world.reveal_enemies(entity)
		"fadeHaunt": world.reveal_area(target_point, 16.0, entity)
		"fadeNightfall":
			world.reveal_area(position, 30.0, entity, 4.0)
			world.cone_daze(entity, 30.0, 0.45, 4.0)
			for enemy in _enemies(world, entity):
				if _position(enemy).distance_to(position) < 30.0:
					_write_value(enemy, "hp", minf(75.0, float(_read_value(enemy, "hp", 100.0))))
		"skyeSeekers":
			var enemies := _enemies(world, entity)
			if enemies.is_empty():
				return false
			for enemy in enemies.slice(0, 3):
				world.send_seeker(entity, enemy)
		"sovaDrone": world.spawn_controlled_scout(entity, "sova", 8.0, 7.0)
		"cypherSpycam": world.spawn_controlled_scout(
			entity, "camera", 12.0, 0.0, true, "", target_point + Vector3.UP * 1.8,
		)
		"fadeProwler": world.spawn_controlled_scout(entity, "prowler", 6.0, 8.0)
		"gekkoWingman": world.spawn_controlled_scout(entity, "wingman", 7.0, 7.0, true, "wingman")
		"gekkoDizzy": world.spawn_controlled_scout(entity, "dizzy", 5.0, 5.0, true, "dizzy")
		"gekkoThrash": world.spawn_controlled_scout(entity, "thrash", 8.0, 9.0, true, "thrash")
		"tejoDrone": world.spawn_controlled_scout(entity, "tejo", 8.0, 7.0)
		"skyeTrailblazer": world.spawn_controlled_scout(entity, "trailblazer", 6.0, 8.0)
		"yoruFakeout": world.spawn_controlled_scout(entity, "decoy", 10.0, 6.0)
		"harborStormSurge":
			Runtime.schedule_ability_event(world.ability_events, now + 0.9, func():
				world.spawn_slow_zone(entity, target_point, 4.0, 5.0)
				for enemy in _enemies(world, entity):
					if _position(enemy).distance_to(target_point) < 4.0:
						_write_value(enemy, "flash_until", maxf(
							float(_read_value(enemy, "flash_until", 0.0)), now + 2.9,
						)), "storm-surge")
		"toxicDome": world.toxic_dome(entity, _eye_position(entity), direction)
		"fadeSeize":
			Runtime.schedule_ability_event(world.ability_events, now + 0.7, func():
				for enemy in _enemies(world, entity):
					if _position(enemy).distance_to(target_point) < 4.5:
						_state(enemy)["tether"] = {"pos": target_point, "until": now + 5.7}
						_write_value(enemy, "slow_until", now + 5.7)
						_write_value(enemy, "hp", minf(75.0, float(_read_value(enemy, "hp", 100.0)))),
				"fade-seize",
			)
		"deadlockAnnihilation":
			var target: Variant = _nearest_enemy(world, entity, 24.0)
			if target == null:
				return false
			_state(target)["cocoon"] = {"owner": entity, "until": now + 7.0}
			_write_value(target, "slow_until", now + 7.0)
			_write_value(target, "suppressed_until", now + 7.0)
			Runtime.schedule_ability_event(world.ability_events, now + 7.0, func():
				if (
					bool(_read_value(target, "alive", false))
					and _state(target).has("cocoon")
				):
					_apply_lethal_damage(target, entity), "annihilation")
		"isoKillContract":
			var target: Variant = _nearest_enemy(world, entity, INF)
			if target == null:
				return false
			_state(entity)["duel"] = {"target": target, "until": now + 15.0}
			_state(target)["duel"] = {"target": entity, "until": now + 15.0}
			_write_value(target, "revealed_until", now + 15.0)
		"isoUndercut":
			for enemy in _enemies(world, entity):
				var offset := _position(enemy) - position
				if offset.length() < 24.0 and forward.dot(offset.normalized()) > 0.75:
					_state(enemy)["vulnerable_until"] = now + 5.0
		"miksPulse":
			if alt:
				var ally: Variant = _nearest_ally(world, entity, 22.0)
				if ally != null:
					_write_value(ally, "hp", minf(100.0, float(_read_value(ally, "hp", 0.0)) + 35.0))
			else:
				world.cone_daze(entity, 22.0, 0.65, 3.0)
		"vyseSteelGarden":
			for enemy in _enemies(world, entity):
				if _position(enemy).distance_to(position) < 28.0:
					_state(enemy)["primary_disabled_until"] = now + 8.0
		_:
			return false
	return true

static func _is_recast(entity: Variant, type: String, now: float) -> bool:
	var state := _state(entity)
	match type:
		"jettTailwind":
			var dash: Dictionary = state.get("jett_dash", {})
			return not dash.is_empty() and now <= float(dash.get("until", 0.0))
		"razeBlastPack": return state.has("blast_pack")
		"toxicSmoke": return state.has("toxicSmoke")
		"toxicWall": return state.has("toxicWall")
		"cypherCage": return state.has("cypher_cage")
		"chamberRendezvous": return state.has("rendezvous")
		"harborCove": return state.has("harbor_cove")
		"vetoCrosscut": return state.has("veto_anchor")
		"waylayRefract": return state.has("waylay_anchor")
		"yoruGatecrash": return state.has("yoru_anchor")
	return false

static func _build_compat_agents() -> Dictionary:
	var result := {}
	for agent_id in Catalog.agent_ids():
		var source := Catalog.agent(agent_id)
		var definition := source.duplicate(true)
		definition["color"] = Color(String(source["color"]))
		definition["ult_cost"] = int(source["ultCost"])
		for key in SLOT_KEYS:
			definition[key] = source["ab"][key]
		result[agent_id] = definition
	return result

static func _grant_weapon(entity: Variant, weapon_id: String, primary: bool, temporary: bool) -> void:
	var weapon := Weapons.make(weapon_id)
	if weapon.is_empty():
		return
	if entity is Dictionary:
		entity["primary" if primary else "secondary"] = weapon
		entity["weapon"] = weapon
		entity["slot"] = "primary" if primary else "secondary"
	else:
		if primary:
			entity.primary = weapon
		else:
			entity.secondary = weapon
		entity.weapon = weapon
		entity.slot = "primary" if primary else "secondary"
	if temporary:
		_state(entity)["temporary_weapon"] = weapon_id

static func _nearest_enemy(world: Variant, entity: Variant, maximum: float) -> Variant:
	var best = null
	var best_distance := maximum
	for enemy in _enemies(world, entity):
		var distance := _position(enemy).distance_to(_position(entity))
		if distance < best_distance:
			best = enemy
			best_distance = distance
	return best

static func _nearest_ally(world: Variant, entity: Variant, maximum: float) -> Variant:
	var best = null
	var best_hp := INF
	for ally in world.combatants():
		if ally == entity or not bool(_read_value(ally, "alive", false)):
			continue
		if _read_value(ally, "team", null) != _read_value(entity, "team", null):
			continue
		if _position(ally).distance_to(_position(entity)) > maximum:
			continue
		var hp := float(_read_value(ally, "hp", 100.0))
		if hp < best_hp:
			best = ally
			best_hp = hp
	return best

static func _enemies(world: Variant, entity: Variant) -> Array:
	var result: Array = []
	for combatant in world.combatants():
		if bool(_read_value(combatant, "alive", false)) and _read_value(combatant, "team", null) != _read_value(entity, "team", null):
			result.append(combatant)
	return result

static func _rejected(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _agent_id(entity: Variant) -> String:
	var result := String(_read_value(entity, "agent_id", ""))
	return result if not result.is_empty() else String(_read_value(entity, "agent", ""))

static func _ability_slots(entity: Variant) -> Dictionary:
	var slots = _read_value(entity, "ability_slots", null)
	if slots is Dictionary:
		return slots
	slots = _read_value(entity, "ab", null)
	return slots if slots is Dictionary else {}

static func _state(entity: Variant) -> Dictionary:
	var state = _read_value(entity, "ability_state", null)
	if state is Dictionary:
		return state
	var created := {}
	_write_value(entity, "ability_state", created)
	return created

static func _resources(entity: Variant) -> Dictionary:
	var resources = _read_value(entity, "resources", null)
	if resources is Dictionary:
		return resources
	var created := {}
	_write_value(entity, "resources", created)
	return created

static func _position(entity: Variant) -> Vector3:
	var value = _read_value(entity, "pos", null)
	if value == null:
		value = _read_value(entity, "global_position", Vector3.ZERO)
	return _as_vector3(value)

static func _eye_position(entity: Variant) -> Vector3:
	if entity is Object and entity.has_method("eye_pos"):
		return entity.eye_pos()
	return _position(entity) + Vector3.UP * 1.55

static func _aim_direction(entity: Variant) -> Vector3:
	if entity is Object and entity.has_method("aim_dir"):
		return entity.aim_dir()
	return Vector3.FORWARD

static func _yaw(entity: Variant) -> float:
	if entity is Object and entity.has_method("yaw_angle"):
		return float(entity.yaw_angle())
	return float(_read_value(entity, "yaw", 0.0))

static func _velocity(entity: Variant) -> Vector3:
	return _as_vector3(_read_value(entity, "velocity", Vector3.ZERO))

static func _set_velocity(entity: Variant, velocity: Vector3) -> void:
	_write_value(entity, "velocity", velocity)

static func _apply_lethal_damage(target: Variant, owner: Variant) -> void:
	if target is Object:
		if not is_instance_valid(target):
			return
		if target.has_method("take_damage"):
			target.take_damage(999.0, owner, false)
			return
	_write_value(target, "hp", 0.0)
	_write_value(target, "alive", false)

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

static func _has_property(entity: Object, key: String) -> bool:
	for property in entity.get_property_list():
		if String(property.get("name", "")) == key:
			return true
	return false

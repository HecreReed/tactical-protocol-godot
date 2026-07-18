# player.gd — 玩家：移动/射击/技能(11特工)/护甲/买卖/拾取/大招
extends CharacterBody3D

const Weapons := preload("res://scripts/weapons.gd")
const Ab := preload("res://scripts/abilities.gd")

const SPEED := 6.0
const JUMP_VEL := 5.6
const GRAV := 19.0
const SENS := 0.0022

var main: Node3D
var cam: Camera3D
var agent_id := "fengying"
var ability_slots: Dictionary = {}
var ult_points := 0
var hp := 100.0
var armor := 0
var armor_bought_round := -1
var money := 800
var team := "ally"
var yaw := 0.0
var pitch := 0.0
var weapon: Dictionary = {}
var secondary: Dictionary = {}
var primary: Dictionary = {}
var slot := "secondary"
var crouching := false
var bloom := 0.0
var recoil := 0.0
var scope_toggle := false
var alive := true
var channel := ""
var kills := 0
var deaths := 0
# 状态
var flash_until := 0.0
var daze_until := 0.0
var slow_until := 0.0
var stim_until := 0.0
var resist_until := 0.0
var suppressed_until := 0.0
var revealed_until := 0.0
var knife_ult := 0
var arrow_ult := 0
var rocket_ult := 0

func _ready() -> void:
	cam = Camera3D.new()
	cam.position = Vector3(0, 1.55, 0)
	cam.fov = 71
	add_child(cam)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.75
	col.shape = cap
	col.position = Vector3(0, 0.875, 0)
	add_child(col)
	collision_mask = 1 | 8
	secondary = Weapons.make("classic")
	weapon = secondary
	ability_slots = Ab.make_slots(agent_id)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func eye_pos() -> Vector3:
	return cam.global_position

func aim_dir() -> Vector3:
	return -cam.global_transform.basis.z

func yaw_angle() -> float:
	return yaw

func _unhandled_input(event: InputEvent) -> void:
	if not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := SENS * (0.35 if _scoped() else 1.0)
		yaw -= event.relative.x * s
		pitch = clampf(pitch - event.relative.y * s, -1.55, 1.55)
		rotation.y = yaw
		cam.rotation.x = pitch
	if event.is_action_pressed("ads") and weapon["def"].get("scope", false):
		scope_toggle = not scope_toggle
	if event.is_action_pressed("slot1") and primary.size() > 0:
		weapon = primary
		slot = "primary"
	if event.is_action_pressed("slot2"):
		weapon = secondary
		slot = "secondary"
	if event.is_action_pressed("reload"):
		_start_reload()
	if event.is_action_pressed("ability_c"):
		Ab.cast(main, self, "c")
	if event.is_action_pressed("ability_q"):
		Ab.cast(main, self, "q")
	if event.is_action_pressed("ability_e"):
		Ab.cast(main, self, "e")
	if event.is_action_pressed("ability_x"):
		Ab.cast(main, self, "x")
	if event.is_action_pressed("buy_menu"):
		main.hud.toggle_buy()
	if event.is_action_pressed("scoreboard"):
		main.hud.show_board(true)
	if event.is_action_released("scoreboard"):
		main.hud.show_board(false)
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _scoped() -> bool:
	return weapon["def"].get("scope", false) and scope_toggle

func _physics_process(dt: float) -> void:
	if not alive:
		return
	var now: float = main.now()
	crouching = Input.is_action_pressed("crouch")
	var walk := Input.is_action_pressed("walk")
	var dir := Vector3.ZERO
	var f := -transform.basis.z
	var r := transform.basis.x
	if Input.is_action_pressed("move_forward"): dir += f
	if Input.is_action_pressed("move_back"): dir -= f
	if Input.is_action_pressed("move_left"): dir -= r
	if Input.is_action_pressed("move_right"): dir += r
	dir.y = 0
	dir = dir.normalized()
	var spd := SPEED * (0.52 if walk else 1.0) * (0.55 if crouching else 1.0)
	if now < slow_until: spd *= 0.45
	if now < daze_until: spd *= 0.6
	if now < stim_until: spd *= 1.12
	velocity.x = move_toward(velocity.x, dir.x * spd, 40 * dt)
	velocity.z = move_toward(velocity.z, dir.z * spd, 40 * dt)
	if not is_on_floor():
		velocity.y -= GRAV * dt
	elif Input.is_action_pressed("jump") and channel == "":
		velocity.y = JUMP_VEL
	move_and_slide()

	cam.position.y = 1.15 if crouching else 1.55
	cam.fov = lerpf(cam.fov, 30.0 if _scoped() else 71.0, dt * 14.0)

	# 换弹结算
	if weapon["reload_end"] > 0 and now >= weapon["reload_end"]:
		var need: int = weapon["def"]["mag"] - weapon["ammo"]
		var take: int = mini(need, weapon["reserve"])
		weapon["ammo"] += take
		weapon["reserve"] -= take
		weapon["reload_end"] = 0.0
	# 射击（含大招武器）
	if Input.is_action_pressed("fire") and main.can_fight() and now >= weapon["next_fire"] and weapon["reload_end"] == 0.0:
		if rocket_ult > 0:
			rocket_ult -= 1
			weapon["next_fire"] = now + 0.9
			main.throw_grenade(self, "nade_throw", eye_pos(), aim_dir())
		elif knife_ult > 0:
			knife_ult -= 1
			weapon["next_fire"] = now + 0.33
			main.hitscan(self, eye_pos(), aim_dir(), {"range": 60, "dmg": {"h": 150, "b": 50, "l": 50}})
		elif weapon["ammo"] > 0:
			_shoot(now)
		else:
			_start_reload()
	bloom = move_toward(bloom, 0, 4.4 * dt)
	recoil = move_toward(recoil, 0, 8.0 * dt)

	channel = ""
	if Input.is_action_pressed("interact"):
		main.match_mgr.player_interact(self, dt)
		_try_pickup()

func _try_pickup() -> void:
	var d: Dictionary = main.nearest_drop(global_position, 1.8)
	if d.is_empty():
		return
	var w: Dictionary = main.take_drop(d)
	if w["def"]["cat"] == "pistol":
		secondary = w
	else:
		if primary.size() > 0 and main.match_mgr.phase != "buy":
			main.drop_weapon(self, primary)
		primary = w
		weapon = primary
		slot = "primary"

func _shoot(now: float) -> void:
	weapon["ammo"] -= 1
	weapon["next_fire"] = now + weapon["def"]["fi"] * (0.85 if now < stim_until else 1.0)
	var spread: float = weapon["def"]["spread"] * 0.01 + bloom * 0.01
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv > 2.0: spread *= 2.2
	elif bloom < 0.4: spread *= 0.3   # 首发精准
	if crouching: spread *= 0.8
	if _scoped(): spread *= 0.25
	if now < daze_until: spread *= 1.8
	var pellets: int = weapon["def"].get("pellets", 1)
	for i in range(pellets):
		var d := aim_dir()
		d += Vector3(randfn(0, spread), randfn(0, spread) + recoil * 0.012, randfn(0, spread))
		main.hitscan(self, eye_pos(), d.normalized(), weapon["def"])
	bloom += 0.5
	recoil += 1.4
	cam.rotation.x = clampf(cam.rotation.x + 0.006, -1.55, 1.55)
	main.spawn_particles(eye_pos() + aim_dir() * 0.9, Color(1.0, 0.85, 0.5), 3, 1.5, 0.1)

func _start_reload() -> void:
	if weapon["reload_end"] > 0 or weapon["reserve"] <= 0 or weapon["ammo"] >= weapon["def"]["mag"]:
		return
	weapon["reload_end"] = main.now() + weapon["def"]["rl"]

func take_damage(dmg: float, killer: Node = null, _hs: bool = false) -> void:
	if not alive:
		return
	if main.now() < resist_until:
		dmg *= 0.55
	var absorb: float = minf(armor, dmg * 0.66)
	armor -= int(absorb)
	hp -= dmg - absorb
	main.hud.damaged()
	if hp <= 0:
		alive = false
		deaths += 1
		visible = false
		if primary.size() > 0:
			main.drop_weapon(self, primary)
			primary = {}
		main.spawn_ragdoll(self, (global_position - (killer.global_position if killer != null and is_instance_valid(killer) else global_position)).normalized())
		main.match_mgr.on_death(self, killer)

func revive_at(pos: Vector3) -> void:
	alive = true
	hp = 100
	visible = true
	global_position = pos

func revive_reset(pos: Vector3) -> void:
	alive = true
	hp = 100
	visible = true
	global_position = pos
	velocity = Vector3.ZERO
	channel = ""
	knife_ult = 0
	rocket_ult = 0
	flash_until = 0.0
	daze_until = 0.0
	suppressed_until = 0.0
	weapon["ammo"] = weapon["def"]["mag"]
	weapon["reserve"] = weapon["def"]["res"]
	for k in ["c", "q", "e"]:
		var sl: Dictionary = ability_slots[k]
		if sl["def"]["cost"] == 0 and sl["n"] < sl["def"].get("max", 1):
			sl["n"] = sl["def"].get("max", 1)

# player.gd — 第一人称控制器：移动/跳蹲/静步/射击/ADS/狙击切换镜/换弹/下包拆包/技能
extends CharacterBody3D

const Weapons := preload("res://scripts/weapons.gd")

const SPEED := 6.0
const WALK_MUL := 0.52
const CROUCH_MUL := 0.55
const JUMP_VEL := 5.6
const GRAV := 19.0
const SENS := 0.0022

var main: Node3D
var cam: Camera3D
var hp := 100.0
var armor := 0
var money := 800
var team := "ally"
var yaw := 0.0
var pitch := 0.0
var weapon: Dictionary = {}
var secondary: Dictionary = {}
var slot := "secondary"
var crouching := false
var bloom := 0.0
var recoil := 0.0
var scope_toggle := false
var smoke_charges := 2
var flash_charges := 2
var alive := true
var channel := ""

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
	secondary = Weapons.make("classic")
	weapon = secondary
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := SENS * (0.35 if _scoped() else 1.0)
		yaw -= event.relative.x * s
		pitch = clampf(pitch - event.relative.y * s, -1.55, 1.55)
		rotation.y = yaw
		cam.rotation.x = pitch
	if event.is_action_pressed("ads") and weapon["def"].get("scope", false):
		scope_toggle = not scope_toggle
	if event.is_action_pressed("slot1") and main.primary_weapon.size() > 0:
		weapon = main.primary_weapon
		slot = "primary"
	if event.is_action_pressed("slot2"):
		weapon = secondary
		slot = "secondary"
	if event.is_action_pressed("reload"):
		_start_reload()
	if event.is_action_pressed("ability_c"):
		_throw_util("smoke")
	if event.is_action_pressed("ability_q"):
		_throw_util("flash")
	if event.is_action_pressed("buy_menu"):
		main.hud.toggle_buy()
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _scoped() -> bool:
	return weapon["def"].get("scope", false) and scope_toggle

func _physics_process(dt: float) -> void:
	if not alive:
		return
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
	var spd := SPEED * (WALK_MUL if walk else 1.0) * (CROUCH_MUL if crouching else 1.0)
	velocity.x = move_toward(velocity.x, dir.x * spd, 40 * dt)
	velocity.z = move_toward(velocity.z, dir.z * spd, 40 * dt)
	if not is_on_floor():
		velocity.y -= GRAV * dt
	elif Input.is_action_pressed("jump") and channel == "":
		velocity.y = JUMP_VEL
	move_and_slide()

	cam.position.y = 1.15 if crouching else 1.55
	cam.fov = lerpf(cam.fov, 30.0 if _scoped() else 71.0, dt * 14.0)

	# 射击
	var now: float = main.now()
	if weapon["reload_end"] > 0 and now >= weapon["reload_end"]:
		var need: int = weapon["def"]["mag"] - weapon["ammo"]
		var take: int = mini(need, weapon["reserve"])
		weapon["ammo"] += take
		weapon["reserve"] -= take
		weapon["reload_end"] = 0.0
	if Input.is_action_pressed("fire") and main.can_fight() and now >= weapon["next_fire"] and weapon["reload_end"] == 0.0:
		if weapon["ammo"] > 0:
			_shoot(now)
		else:
			_start_reload()
	bloom = move_toward(bloom, 0, 4.4 * dt)
	recoil = move_toward(recoil, 0, 8.0 * dt)

	# 下包 / 拆包
	channel = ""
	if Input.is_action_pressed("interact"):
		main.match_mgr.player_interact(self, dt)

func _shoot(now: float) -> void:
	weapon["ammo"] -= 1
	weapon["next_fire"] = now + weapon["def"]["fi"]
	var spread: float = weapon["def"]["spread"] * 0.01 + bloom * 0.01
	var hv := Vector2(velocity.x, velocity.z).length()
	if hv > 2.0: spread *= 2.2
	if crouching: spread *= 0.8
	if _scoped(): spread *= 0.3
	var pellets: int = weapon["def"].get("pellets", 1)
	for i in range(pellets):
		var dir := -cam.global_transform.basis.z
		dir += Vector3(randfn(0, spread), randfn(0, spread) + recoil * 0.012, randfn(0, spread))
		dir = dir.normalized()
		main.hitscan(self, cam.global_position, dir, weapon["def"])
	bloom += 0.5
	recoil += 1.4
	cam.rotation.x = clampf(cam.rotation.x + 0.006, -1.55, 1.55)
	main.hud.flash_crosshair()

func _start_reload() -> void:
	if weapon["reload_end"] > 0 or weapon["reserve"] <= 0 or weapon["ammo"] >= weapon["def"]["mag"]:
		return
	weapon["reload_end"] = main.now() + weapon["def"]["rl"]

func _throw_util(kind: String) -> void:
	if kind == "smoke":
		if smoke_charges <= 0: return
		smoke_charges -= 1
	else:
		if flash_charges <= 0: return
		flash_charges -= 1
	main.throw_projectile(self, kind, cam.global_position, -cam.global_transform.basis.z)

func take_damage(dmg: float) -> void:
	var absorb: float = minf(armor, dmg * 0.66)
	armor -= int(absorb)
	hp -= dmg - absorb
	main.hud.damaged()
	if hp <= 0:
		alive = false
		main.match_mgr.on_death(self, null)
		visible = false

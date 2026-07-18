# bot_ai.gd — AI：导航寻路 + 状态机（推进/执行/下包/驻守/拆包/追猎）+ 视线交战
extends CharacterBody3D

const Weapons := preload("res://scripts/weapons.gd")

const SPEED := 6.0
const GRAV := 19.0

var main: Node3D
var team := "enemy"
var agent_name := "Bot"
var hp := 100.0
var alive := true
var weapon: Dictionary = {}
var nav: NavigationAgent3D
var state := "wait"
var goal := Vector3.ZERO
var hold_look := Vector3.ZERO
var target: CharacterBody3D = null
var next_think := 0.0
var next_fire := 0.0
var acq := 0.0
var plant_role := false
var channel := ""
var yaw := 0.0
var body_mesh: MeshInstance3D
var wd_best := 1e9
var wd_at := 0.0

func setup(m: Node3D, t: String, nm: String, color: Color) -> void:
	main = m
	team = t
	agent_name = nm
	nav = NavigationAgent3D.new()
	nav.radius = 0.42
	nav.path_desired_distance = 0.8
	nav.target_desired_distance = 1.2
	add_child(nav)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.75
	col.shape = cap
	col.position = Vector3(0, 0.875, 0)
	add_child(col)
	body_mesh = MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.32
	bm.height = 1.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.25
	bm.material = mat
	body_mesh.mesh = bm
	body_mesh.position = Vector3(0, 0.875, 0)
	add_child(body_mesh)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.17
	hm.height = 0.34
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.9, 0.85, 0.8) if t == "ally" else Color(0.85, 0.4, 0.4)
	hm.material = hmat
	head.mesh = hm
	head.position = Vector3(0, 1.66, 0)
	add_child(head)
	weapon = Weapons.make(["spectre", "bulldog", "vandal", "phantom"].pick_random())

func set_goal(p: Vector3) -> void:
	goal = p
	nav.target_position = p
	wd_best = 1e9
	wd_at = main.now()

func _physics_process(dt: float) -> void:
	if not alive:
		return
	var now: float = main.now()
	if now >= next_think:
		next_think = now + 0.15
		_think(now)
	if target != null and (not is_instance_valid(target) or not target.alive):
		target = null
	if target != null:
		_combat(dt, now)
	else:
		_navigate(dt, now)
	if not is_on_floor():
		velocity.y -= GRAV * dt
	move_and_slide()
	rotation.y = yaw

func _think(now: float) -> void:
	# 目标搜寻：视距 + 视野角 + 遮挡
	var best: CharacterBody3D = null
	var bd := 55.0
	for e in main.combatants():
		if e == self or e.team == team or not e.alive:
			continue
		var d: float = global_position.distance_to(e.global_position)
		if d < bd and main.has_los(_eye(), e.global_position + Vector3(0, 1.4, 0), [self, e]):
			bd = d
			best = e
	if best != target:
		target = best
		acq = 0.0
	if target != null:
		return
	main.match_mgr.bot_think(self, now)

func _navigate(dt: float, now: float) -> void:
	if channel != "":
		velocity.x = 0
		velocity.z = 0
		return
	if nav.is_navigation_finished():
		velocity.x = move_toward(velocity.x, 0, 30 * dt)
		velocity.z = move_toward(velocity.z, 0, 30 * dt)
		if hold_look != Vector3.ZERO:
			var ty := atan2(-(hold_look.x - global_position.x), -(hold_look.z - global_position.z))
			yaw = lerp_angle(yaw, ty + sin(now * 0.55) * 0.3, dt * 4.0)
		return
	# 进度看门狗（下包/拆包状态豁免）
	var gd := global_position.distance_to(goal)
	if state != "plant" and state != "defuse" and gd > 2.4:
		if gd < wd_best - 0.45:
			wd_best = gd
			wd_at = now
		elif now - wd_at > 6.0:
			set_goal(goal + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)))
	var next := nav.get_next_path_position()
	var dir := (next - global_position)
	dir.y = 0
	if dir.length() > 0.05:
		dir = dir.normalized()
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
		yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z) + sin(now * 1.15) * 0.2, dt * 8.0)

func _combat(dt: float, now: float) -> void:
	acq += dt
	var to := target.global_position - global_position
	var d := Vector2(to.x, to.z).length()
	yaw = lerp_angle(yaw, atan2(-to.x, -to.z), dt * 10.0)
	# 拉打走位
	var strafe := sin(now * 3.0 + get_instance_id() % 7) * 0.5
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var adv := 0.0
	if d > 30: adv = 0.7
	elif d < 8: adv = -0.5
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	velocity.x = (fwd.x * adv + right.x * strafe) * SPEED * 0.8
	velocity.z = (fwd.z * adv + right.z * strafe) * SPEED * 0.8
	# 开火（成长精度）
	if now >= next_fire and weapon["ammo"] > 0:
		next_fire = now + weapon["def"]["fi"] * randf_range(1.0, 1.15)
		weapon["ammo"] -= 1
		var err: float = (0.05 + d * 0.0012) * clampf(2.2 - acq * 1.4, 0.6, 2.2) / main.difficulty
		var aim: Vector3 = (target.global_position + Vector3(0, 1.25, 0) - _eye()).normalized()
		aim += Vector3(randfn(0, err), randfn(0, err), randfn(0, err))
		main.hitscan(self, _eye(), aim.normalized(), weapon["def"])
	elif weapon["ammo"] <= 0:
		weapon["ammo"] = weapon["def"]["mag"]   # 简化换弹
		next_fire = now + weapon["def"]["rl"]

func _eye() -> Vector3:
	return global_position + Vector3(0, 1.55, 0)

func take_damage(dmg: float) -> void:
	hp -= dmg
	if hp <= 0 and alive:
		alive = false
		visible = false
		set_physics_process(false)
		main.match_mgr.on_death(self, null)

func revive_reset(pos: Vector3) -> void:
	alive = true
	hp = 100
	visible = true
	set_physics_process(true)
	global_position = pos
	velocity = Vector3.ZERO
	state = "wait"
	target = null
	channel = ""
	weapon["ammo"] = weapon["def"]["mag"]
	weapon["reserve"] = weapon["def"]["res"]

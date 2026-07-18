# bot_ai.gd — AI：导航/状态机/技能使用/捡枪拼刀/布娃娃死亡
extends CharacterBody3D

const Weapons := preload("res://scripts/weapons.gd")
const Ab := preload("res://scripts/abilities.gd")

const SPEED := 6.0
const GRAV := 19.0

var main: Node3D
var team := "enemy"
var agent_id := "fengying"
var agent_name := "Bot"
var ability_slots: Dictionary = {}
var ult_points := 0
var hp := 100.0
var alive := true
var weapon: Dictionary = {}
var path: PackedVector2Array = []
var path_i := 0
var state := "wait"
var goal := Vector3.ZERO
var hold_look := Vector3.ZERO
var target: CharacterBody3D = null
var next_think := 0.0
var next_fire := 0.0
var acq := 0.0
var channel := ""
var yaw := 0.0
var kills := 0
var deaths := 0
var wd_best := 1e9
var wd_at := 0.0
var wd_kick := 0
var used_util := false
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

func setup(m: Node3D, t: String, aid: String) -> void:
	main = m
	team = t
	agent_id = aid
	agent_name = Ab.AGENTS[aid]["name"]
	ability_slots = Ab.make_slots(aid)
	collision_mask = 1 | 8
	var color: Color = Ab.AGENTS[aid]["color"]
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.75
	col.shape = cap
	col.position = Vector3(0, 0.875, 0)
	add_child(col)
	var body_mesh := MeshInstance3D.new()
	var bm := CapsuleMesh.new()
	bm.radius = 0.32
	bm.height = 1.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color if t == "ally" else color.lerp(Color(0.9, 0.3, 0.32), 0.5)
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.3
	bm.material = mat
	body_mesh.mesh = bm
	body_mesh.position = Vector3(0, 0.875, 0)
	add_child(body_mesh)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.17
	hm.height = 0.34
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.9, 0.85, 0.8)
	hm.material = hmat
	head.mesh = hm
	head.position = Vector3(0, 1.66, 0)
	add_child(head)
	# 队伍色面甲（发光，醒目辨识）
	var visor := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.24, 0.07, 0.05)
	var vmat := StandardMaterial3D.new()
	vmat.emission_enabled = true
	vmat.emission = Color(0.25, 0.85, 0.8) if t == "ally" else Color(1.0, 0.3, 0.35)
	vmat.emission_energy_multiplier = 2.0
	vb.material = vmat
	visor.mesh = vb
	visor.position = Vector3(0, 1.67, -0.16)
	add_child(visor)
	weapon = Weapons.make(["spectre", "bulldog", "vandal", "phantom"].pick_random())

func eye_pos() -> Vector3:
	return global_position + Vector3(0, 1.55, 0)

func aim_dir() -> Vector3:
	if target != null and is_instance_valid(target):
		return (target.global_position + Vector3(0, 1.2, 0) - eye_pos()).normalized()
	return Vector3(-sin(yaw), 0, -cos(yaw))

func yaw_angle() -> float:
	return yaw

func set_goal(p: Vector3) -> void:
	goal = p
	path = main.map.nav_path(global_position, p)
	path_i = 0
	wd_best = 1e9
	wd_at = main.now()

func nav_finished() -> bool:
	return path_i >= path.size() and global_position.distance_to(Vector3(goal.x, global_position.y, goal.z)) < 1.4

func _physics_process(dt: float) -> void:
	if not alive:
		return
	var now: float = main.now()
	if now >= next_think:
		next_think = now + 0.15
		_think(now)
	if target != null and (not is_instance_valid(target) or not target.alive):
		target = null
	if target != null and now >= flash_until:
		_combat(dt, now)
	else:
		_navigate(dt, now)
	if not is_on_floor():
		velocity.y -= GRAV * dt
	move_and_slide()
	rotation.y = yaw

func _think(now: float) -> void:
	if now < flash_until:
		target = null
		return
	var best: CharacterBody3D = null
	var bd := 55.0
	for e in main.combatants():
		if e == self or e.team == team or not e.alive:
			continue
		var d: float = global_position.distance_to(e.global_position)
		var score: float = d * (0.55 + e.hp / 220.0)
		if score < bd and main.has_los(eye_pos(), e.global_position + Vector3(0, 1.4, 0), [self, e]):
			bd = score
			best = e
	if best != target:
		target = best
		acq = 0.0
	if target != null:
		_combat_abilities(now)
		return
	# 弹尽：捡枪或拼刀
	if weapon["ammo"] <= 0 and weapon["reserve"] <= 0:
		var d: Dictionary = main.nearest_drop(global_position, 45.0)
		if not d.is_empty():
			state = "loot"
			set_goal(d["body"].global_position)
			if global_position.distance_to(d["body"].global_position) < 1.6:
				weapon = main.take_drop(d)
				state = "wait"
			return
	main.match_mgr.bot_think(self, now)
	_util_abilities(now)

func _combat_abilities(now: float) -> void:
	# 交战中大招：残血涅槃 / 锋刃 / 火箭
	if hp < 35 and ult_points >= Ab.AGENTS[agent_id]["ult_cost"]:
		var xt: String = Ab.AGENTS[agent_id]["x"]["type"]
		if xt in ["phoenix_ult", "knife_ult", "null_pulse", "big_stun"]:
			Ab.cast(main, self, "x")

func _util_abilities(now: float) -> void:
	if used_util or not main.can_fight():
		return
	var side: String = main.match_mgr.side_of(self)
	# 进攻执行：烟/闪开路；防守就位：装置布防
	if side == "atk" and state == "execute":
		used_util = true
		Ab.cast(main, self, "e")
		Ab.cast(main, self, "q")
	elif side == "def" and state == "post" and nav_finished():
		used_util = true
		Ab.cast(main, self, "e")
		Ab.cast(main, self, "c")

func _navigate(dt: float, now: float) -> void:
	if channel != "":
		velocity.x = 0
		velocity.z = 0
		return
	# 路点推进
	while path_i < path.size():
		var wp := Vector3(path[path_i].x + 0.5, 0, path[path_i].y + 0.5)
		if Vector2(global_position.x - wp.x, global_position.z - wp.z).length() < 0.9:
			path_i += 1
		else:
			break
	if nav_finished():
		velocity.x = move_toward(velocity.x, 0, 30 * dt)
		velocity.z = move_toward(velocity.z, 0, 30 * dt)
		if hold_look != Vector3.ZERO:
			var ty := atan2(-(hold_look.x - global_position.x), -(hold_look.z - global_position.z))
			yaw = lerp_angle(yaw, ty + sin(now * 0.55) * 0.3, dt * 4.0)
		return
	var gd := global_position.distance_to(goal)
	if state != "plant" and state != "defuse" and gd > 2.4:
		if gd < wd_best - 0.45:
			wd_best = gd
			wd_at = now
		elif now - wd_at > 6.0:
			wd_at = now
			wd_kick += 1
			if wd_kick >= 2:
				wd_kick = 0
				var c: Vector2i = main.map._nearest_cell(global_position)
				global_position = Vector3(c.x + 0.5, global_position.y, c.y + 0.5)
				velocity = Vector3.ZERO
			set_goal(goal + Vector3(randf_range(-2.5, 2.5), 0, randf_range(-2.5, 2.5)))
	var next: Vector3 = Vector3(goal.x, 0, goal.z)
	if path_i < path.size():
		next = Vector3(path[path_i].x + 0.5, 0, path[path_i].y + 0.5)
	var dir := next - global_position
	dir.y = 0
	if dir.length() > 0.05:
		dir = dir.normalized()
		var spd := SPEED
		if now < slow_until: spd *= 0.45
		if now < daze_until: spd *= 0.6
		if now < stim_until: spd *= 1.12
		velocity.x = dir.x * spd
		velocity.z = dir.z * spd
		yaw = lerp_angle(yaw, atan2(-dir.x, -dir.z) + sin(now * 1.15) * 0.2, dt * 8.0)

func _combat(dt: float, now: float) -> void:
	acq += dt
	var to := target.global_position - global_position
	var d := Vector2(to.x, to.z).length()
	yaw = lerp_angle(yaw, atan2(-to.x, -to.z), dt * 10.0)
	# 弹尽拼刀：直冲
	var dry: bool = weapon["ammo"] <= 0 and weapon["reserve"] <= 0
	var strafe := sin(now * 3.0 + get_instance_id() % 7) * 0.5
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var adv := 0.0
	if dry: adv = 1.0
	elif d > 30: adv = 0.7
	elif d < 8: adv = -0.5
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var spd := SPEED * (0.8 if not dry else 1.05)
	velocity.x = (fwd.x * adv + right.x * strafe) * spd
	velocity.z = (fwd.z * adv + right.z * strafe) * spd
	if not main.can_fight():
		return
	if dry:
		if d < 2.1 and now >= next_fire:
			next_fire = now + 0.75
			target.take_damage(50.0, self, false)
		return
	if now >= next_fire and weapon["ammo"] > 0:
		next_fire = now + weapon["def"]["fi"] * randf_range(1.0, 1.15) * (0.85 if now < stim_until else 1.0)
		weapon["ammo"] -= 1
		var err: float = (0.02 + d * 0.0006) * clampf(2.0 - acq * 1.5, 0.5, 2.0) / main.difficulty
		if now < daze_until: err *= 2.3
		var aim: Vector3 = aim_dir()
		aim += Vector3(randfn(0, err), randfn(0, err), randfn(0, err))
		main.hitscan(self, eye_pos(), aim.normalized(), weapon["def"])
	elif weapon["ammo"] <= 0 and weapon["reserve"] > 0:
		var take: int = mini(weapon["def"]["mag"], weapon["reserve"])
		weapon["reserve"] -= take
		weapon["ammo"] = take
		next_fire = now + weapon["def"]["rl"]

func take_damage(dmg: float, killer: Node = null, _hs: bool = false) -> void:
	if not alive:
		return
	if main.now() < resist_until:
		dmg *= 0.55
	hp -= dmg
	if hp <= 0:
		alive = false
		deaths += 1
		visible = false
		set_physics_process(false)
		main.drop_weapon(self, weapon.duplicate(true))
		main.spawn_ragdoll(self, (global_position - (killer.global_position if killer != null and is_instance_valid(killer) else global_position)).normalized())
		main.match_mgr.on_death(self, killer)

func revive_at(pos: Vector3) -> void:
	alive = true
	hp = 100
	visible = true
	set_physics_process(true)
	global_position = pos

func revive_reset(pos: Vector3) -> void:
	revive_at(pos)
	velocity = Vector3.ZERO
	state = "wait"
	target = null
	channel = ""
	used_util = false
	flash_until = 0.0
	daze_until = 0.0
	suppressed_until = 0.0
	weapon["ammo"] = weapon["def"]["mag"]
	weapon["reserve"] = weapon["def"]["res"]
	for k in ["c", "q", "e"]:
		var sl: Dictionary = ability_slots[k]
		if sl["def"]["cost"] == 0 and sl["n"] < sl["def"].get("max", 1):
			sl["n"] = sl["def"].get("max", 1)

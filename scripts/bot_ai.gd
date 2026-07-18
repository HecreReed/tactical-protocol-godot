# bot_ai.gd — AI：导航/状态机/技能使用/捡枪拼刀/布娃娃死亡
extends CharacterBody3D

const Weapons := preload("res://scripts/weapons.gd")
const Ab := preload("res://scripts/abilities.gd")
const CharRig := preload("res://scripts/char_rig.gd")

const SPEED := 6.0
const GRAV := 18.0

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
var last_seen := Vector3.ZERO
var hunt_until := 0.0
var next_regroup := 0.0
var rig: Node3D
var react_at := 0.0
var burst_left := 0
var burst_pause := 0.0
var strafe_t := 0.0
var strafe_dir := 1.0
var last_shot_at := -9.0
var crouching := false
var next_repath := 0.0

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
	rig = CharRig.new()
	add_child(rig)
	rig.build(t, color, agent_name, t == "ally")
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
	if rig != null:
		rig.animate(Vector2(velocity.x, velocity.z).length(), crouching, now)

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
		# 丢失目标 → 短暂追击最后目击点（不打断关键任务状态）
		if best == null and target != null and is_instance_valid(target) and target.alive:
			last_seen = target.global_position
			hunt_until = now + 4.5
			if state in ["wait", "advance", "hunt", "post"] and channel == "" and main.can_fight():
				state = "hunt"
				set_goal(last_seen)
		target = best
		acq = 0.0
		if target != null:
			# 反应时间：难度越高反应越快
			react_at = now + clampf(0.42 - 0.22 * main.difficulty, 0.08, 0.42) + randf() * 0.1
			burst_left = 0
			burst_pause = 0.0
	if target != null:
		hunt_until = 0.0
		_combat_abilities(now)
		return
	# 追击超时 → 回归任务
	if state == "hunt" and (now > hunt_until or nav_finished()):
		state = "wait"
	# 空闲战术换弹（像人：脱战 1.6s 且弹匣<55% 就补弹）
	if weapon["ammo"] < int(weapon["def"]["mag"] * 0.55) and weapon["reserve"] > 0 and now - last_shot_at > 1.6 and now >= next_fire:
		var take: int = mini(weapon["def"]["mag"] - weapon["ammo"], weapon["reserve"])
		weapon["reserve"] -= take
		weapon["ammo"] += take
		next_fire = now + weapon["def"]["rl"]
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
	if path_i >= path.size() and not nav_finished() and now > next_repath:
		next_repath = now + 1.5
		path = main.map.nav_path(global_position, goal)
		path_i = 0
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
	# 弹尽拼刀：直冲蛇皮走位
	var dry: bool = weapon["ammo"] <= 0 and weapon["reserve"] <= 0
	strafe_t -= dt
	if strafe_t <= 0:
		strafe_t = randf_range(0.35, 0.7)
		strafe_dir = -1.0 if randf() < 0.5 else 1.0
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	# 瞄准（带移动预判）：目标位置 + 速度提前量
	var lead_k: float = d * 0.022 * (0.3 + 0.7 * main.difficulty)
	var aim_p: Vector3 = target.global_position + Vector3(
		clampf(target.velocity.x * lead_k, -1.4, 1.4), 1.2,
		clampf(target.velocity.z * lead_k, -1.4, 1.4))
	var aim_spd: float = (7.0 + main.difficulty * 8.0) * (0.45 if now < daze_until else 1.0)
	yaw = lerp_angle(yaw, atan2(-(aim_p.x - global_position.x), -(aim_p.z - global_position.z)), minf(1.0, dt * aim_spd))
	if dry:
		var adv_dir := (target.global_position - global_position).normalized()
		velocity.x = (adv_dir.x + right.x * strafe_dir * 0.4) * SPEED * 1.05
		velocity.z = (adv_dir.z + right.z * strafe_dir * 0.4) * SPEED * 1.05
		crouching = false
		if not main.can_fight():
			return
		if d < 2.1 and now >= next_fire:
			next_fire = now + 0.75
			main.sfx.shot("melee", main.player.global_position.distance_to(global_position))
			target.take_damage(50.0, self, false)
		return
	# 走位：Valorant 式"停住再打"+ 远距蹲射
	var firing: bool = burst_left > 0 and now >= react_at
	crouching = firing and d > 22 and main.difficulty > 0.75
	var want_stand: bool = weapon["def"].get("scope", false) or d > 35 or (firing and d > 8)
	if not want_stand and channel == "":
		var spd := SPEED * 0.7
		velocity.x = right.x * strafe_dir * spd
		velocity.z = right.z * strafe_dir * spd
	else:
		velocity.x *= 0.5
		velocity.z *= 0.5
	if not main.can_fight():
		return
	if now < react_at:
		return
	if now >= next_fire and weapon["ammo"] > 0:
		# 点射节奏：近距长点射，远距短点射+停顿
		if burst_left <= 0:
			if now < burst_pause:
				return
			burst_left = randi_range(3, 7) + (4 if d < 12 else 0)
		burst_left -= 1
		if burst_left <= 0:
			burst_pause = now + randf_range(0.25, 0.5) + d * 0.006
		next_fire = now + weapon["def"]["fi"] * randf_range(1.0, 1.15) * (0.85 if now < stim_until else 1.0)
		weapon["ammo"] -= 1
		last_shot_at = now
		var acq_norm := clampf(acq / (1.0 - 0.45 * minf(main.difficulty, 1.2)), 0.0, 1.0)
		var err: float = (0.02 + d * 0.0006) * (2.3 - 1.3 * acq_norm) / main.difficulty
		if now < daze_until: err *= 2.3
		if crouching: err *= 0.8
		var aim: Vector3 = (aim_p - eye_pos()).normalized()
		aim += Vector3(randfn(0, err), randfn(0, err), randfn(0, err))
		main.sfx.shot(weapon["def"]["cat"], main.player.global_position.distance_to(global_position))
		main.hitscan(self, eye_pos(), aim.normalized(), weapon["def"])
	elif weapon["ammo"] <= 0 and weapon["reserve"] > 0:
		var take: int = mini(weapon["def"]["mag"], weapon["reserve"])
		weapon["reserve"] -= take
		weapon["ammo"] = take
		next_fire = now + weapon["def"]["rl"]
		# 换弹拉开距离
		var away := (global_position - target.global_position).normalized()
		velocity.x = (away.x * 0.8 + right.x * strafe_dir * 0.5) * SPEED * 0.85
		velocity.z = (away.z * 0.8 + right.z * strafe_dir * 0.5) * SPEED * 0.85

func take_damage(dmg: float, killer: Node = null, _hs: bool = false) -> void:
	if not alive:
		return
	if main.now() < resist_until:
		dmg *= 0.55
	hp -= dmg
	# 受击反应：没有目标时转向攻击者并短暂追击
	if hp > 0 and killer != null and is_instance_valid(killer) and "team" in killer and killer.team != team:
		var kp: Vector3 = killer.global_position
		yaw = atan2(-(kp.x - global_position.x), -(kp.z - global_position.z))
		if target == null and channel == "" and state in ["wait", "advance", "hunt", "post"] and main.can_fight():
			last_seen = kp
			hunt_until = main.now() + 4.0
			state = "hunt"
			set_goal(kp)
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
	if rig != null:
		rig.visible = true
	set_physics_process(true)
	global_position = pos

func revive_reset(pos: Vector3) -> void:
	revive_at(pos)
	velocity = Vector3.ZERO
	state = "wait"
	target = null
	channel = ""
	used_util = false
	hunt_until = 0.0
	next_regroup = 0.0
	goal = pos
	path = PackedVector2Array()
	path_i = 0
	hold_look = Vector3.ZERO
	flash_until = 0.0
	daze_until = 0.0
	suppressed_until = 0.0
	weapon["ammo"] = weapon["def"]["mag"]
	weapon["reserve"] = weapon["def"]["res"]
	for k in ["c", "q", "e"]:
		var sl: Dictionary = ability_slots[k]
		if sl["def"]["cost"] == 0 and sl["n"] < sl["def"].get("max", 1):
			sl["n"] = sl["def"].get("max", 1)

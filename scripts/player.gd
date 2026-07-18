# player.gd — 玩家：移动/射击/技能(11特工)/护甲/买卖/拾取/大招
extends CharacterBody3D

const Weapons := preload("res://scripts/weapons.gd")
const Ab := preload("res://scripts/abilities.gd")

const SPEED := 6.0
const CAT_SPEED := { "melee": 1.12, "pistol": 1.0, "smg": 0.96, "rifle": 0.9, "sniper": 0.84, "heavy": 0.82, "shotgun": 0.96 }
const JUMP_VEL := 6.2
const GRAV := 18.0
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
# 视模 / 观战
var vm_group: Node3D
var _vm_weapon_id := ""
var vm_kick := 0.0
var bob_t := 0.0
var spectate_idx := 0
var spectating: Node = null
var observer := false
var knife_w: Dictionary = {}
var ads := false
var sens_mult := 1.0
var fov_base := 71.0
var step_acc := 0.0
var cast_mode := ""
var next_pickup_t := 0.0
var mouse_ignore_until := 0.0
var _was_captured := true

func _ready() -> void:
	cam = Camera3D.new()
	cam.position = Vector3(0, 1.55, 0)
	cam.fov = 71
	add_child(cam)
	vm_group = Node3D.new()
	cam.add_child(vm_group)
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.75
	col.shape = cap
	col.position = Vector3(0, 0.875, 0)
	add_child(col)
	collision_mask = 1 | 8
	secondary = Weapons.make("classic")
	knife_w = { "id": "knife", "def": { "name": "战术刀", "cat": "melee", "cost": 0, "mag": -1, "res": -1, "fi": 0.55, "rl": 0.0, "dmg": {"h": 100, "b": 50, "l": 50}, "spread": 0.0, "range": 2.6 }, "ammo": -1, "reserve": -1, "reload_end": 0.0, "next_fire": 0.0 }
	weapon = secondary
	ability_slots = Ab.make_slots(agent_id)
	if observer:
		alive = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ---------------- 第一人称枪模（1:1 移植网页版 buildViewModel） ----------------
static func _vm_mat(c: Color, rough: float, metal: float, emis: Color = Color.BLACK, ei: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if ei > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = ei
	m.render_priority = 1
	return m

static func _vm_box(size: Vector3, mat: StandardMaterial3D, pos: Vector3, rot_x: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.rotation.x = rot_x
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func _vm_cyl(r: float, h: float, mat: StandardMaterial3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.material = mat
	mi.mesh = cm
	mi.rotation.x = PI / 2
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _rebuild_viewmodel() -> void:
	for c in vm_group.get_children():
		c.queue_free()
	var dark := _vm_mat(Color8(0x22, 0x2a, 0x33), 0.55, 0.25)
	var accent := _vm_mat(Color8(0x5a, 0x6a, 0x75), 0.4, 0.35)
	var grey := _vm_mat(Color8(0x39, 0x42, 0x4c), 0.5, 0.35)
	var g := Node3D.new()
	var cat: String = weapon["def"]["cat"]
	if cast_mode != "":
		# 手持技能：发光法球 + 握持手（复刻网页版装备式施法）
		var col: Color = Ab.AGENTS[agent_id]["color"]
		var orb := MeshInstance3D.new()
		var om := SphereMesh.new()
		om.radius = 0.055
		om.height = 0.11
		om.material = _vm_mat(col, 0.35, 0.0, col, 1.4)
		orb.mesh = om
		orb.position = Vector3(0, -0.01, -0.18)
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(orb)
		var hand := _vm_box(Vector3(0.055, 0.05, 0.11), _vm_mat(Color8(0x22, 0x2a, 0x33), 0.55, 0.25), Vector3(0, -0.075, -0.1), 0.35)
		g.add_child(hand)
	elif arrow_ult > 0:
		var acol := Color(0.4, 1.0, 0.6)
		var shaft := _vm_box(Vector3(0.012, 0.012, 0.5), _vm_mat(acol, 0.4, 0.3, acol, 1.2), Vector3(0, 0, -0.3))
		g.add_child(shaft)
		var tip := _vm_box(Vector3(0.025, 0.025, 0.06), _vm_mat(acol, 0.3, 0.5, acol, 2.0), Vector3(0, 0, -0.56))
		g.add_child(tip)
		g.add_child(_vm_box(Vector3(0.03, 0.05, 0.1), dark, Vector3(0, -0.05, -0.08), 0.3))
	elif rocket_ult > 0:
		g.add_child(_vm_cyl(0.058, 0.62, dark, Vector3(0, 0, -0.3)))
		g.add_child(_vm_cyl(0.073, 0.1, accent, Vector3(0, 0, -0.62)))
		g.add_child(_vm_box(Vector3(0.035, 0.1, 0.045), dark, Vector3(0, -0.09, -0.12), 0.3))
	elif knife_ult > 0 or cat == "melee":
		var bcol := Color8(0x7f, 0xd0, 0xd4) if knife_ult > 0 else Color8(0xb8, 0xc4, 0xcc)
		var blade := _vm_box(Vector3(0.015, 0.05, 0.26), _vm_mat(bcol, 0.4, 0.55, bcol, 0.8 if knife_ult > 0 else 0.0), Vector3(0, 0, -0.16))
		g.add_child(blade)
		g.add_child(_vm_box(Vector3(0.03, 0.04, 0.1), dark, Vector3.ZERO))
	else:
		var len_map := { "pistol": 0.28, "smg": 0.42, "rifle": 0.55, "sniper": 0.68, "heavy": 0.55, "shotgun": 0.5 }
		var L: float = len_map.get(cat, 0.4)
		g.add_child(_vm_box(Vector3(0.045, 0.075, L * 0.55), dark, Vector3(0, 0, -L * 0.32)))
		g.add_child(_vm_box(Vector3(0.04, 0.06, L * 0.4), grey, Vector3(0, -0.005, -L * 0.75)))
		g.add_child(_vm_cyl(0.012, L * 0.35, dark, Vector3(0, 0.012, -L - 0.05)))
		g.add_child(_vm_cyl(0.018, 0.06, accent, Vector3(0, 0.012, -L - 0.2)))
		g.add_child(_vm_box(Vector3(0.006, 0.03, 0.01), dark, Vector3(0, 0.055, -L - 0.02)))
		g.add_child(_vm_box(Vector3(0.03, 0.022, 0.012), dark, Vector3(0, 0.052, -L * 0.12)))
		g.add_child(_vm_box(Vector3(0.034, 0.1, 0.045), dark, Vector3(0, -0.075, -0.06), 0.32))
		g.add_child(_vm_box(Vector3(0.008, 0.012, 0.07), grey, Vector3(0, -0.045, -0.12)))
		g.add_child(_vm_box(Vector3(0.004, 0.014, L * 0.42), accent, Vector3(0.026, 0.012, -L * 0.4)))
		if cat != "pistol":
			g.add_child(_vm_box(Vector3(0.032, 0.07, 0.05), grey, Vector3(0, -0.075, -L * 0.5), -0.12))
			g.add_child(_vm_box(Vector3(0.03, 0.05, 0.046), dark, Vector3(0, -0.125, -L * 0.48), -0.3))
			g.add_child(_vm_box(Vector3(0.036, 0.06, 0.14), grey, Vector3(0, -0.012, 0.1)))
			g.add_child(_vm_box(Vector3(0.04, 0.08, 0.02), dark, Vector3(0, -0.015, 0.18)))
		else:
			g.add_child(_vm_box(Vector3(0.042, 0.03, L * 0.7), grey, Vector3(0, 0.038, -L * 0.35)))
			g.add_child(_vm_box(Vector3(0.014, 0.02, 0.02), dark, Vector3(0, 0.04, 0.02)))
		if cat == "smg":
			g.add_child(_vm_box(Vector3(0.026, 0.07, 0.03), dark, Vector3(0, -0.055, -L * 0.8)))
		if cat == "shotgun":
			g.add_child(_vm_box(Vector3(0.05, 0.05, 0.12), accent, Vector3(0, -0.03, -L * 0.7)))
		if cat == "heavy":
			var drum := _vm_cyl(0.05, 0.045, grey, Vector3(0, -0.06, -L * 0.42))
			drum.rotation = Vector3(0, 0, PI / 2)
			g.add_child(drum)
			g.add_child(_vm_box(Vector3(0.012, 0.03, 0.16), dark, Vector3(0, 0.075, -L * 0.3)))
		if weapon["def"].get("scope", false):
			g.add_child(_vm_cyl(0.022, 0.16, dark, Vector3(0, 0.078, -L * 0.42)))
	vm_group.add_child(g)
	vm_group.position = Vector3(0.18, -0.16, -0.35)
	vm_group.rotation = Vector3(0, 0, 0.06)

func eye_pos() -> Vector3:
	return cam.global_position

func aim_dir() -> Vector3:
	return -cam.global_transform.basis.z

func yaw_angle() -> float:
	return yaw

func _unhandled_input(event: InputEvent) -> void:
	if not alive:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			spectate_idx += 1
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# 指针锁刚恢复/浏览器合成的大位移事件 → 丢弃，防止视角瞬间乱跳
		if main.now() < mouse_ignore_until or event.relative.length() > 250.0:
			return
		var s := SENS * sens_mult * (0.35 if _scoped() else 1.0)
		yaw -= event.relative.x * s
		pitch = clampf(pitch - event.relative.y * s, -1.55, 1.55)
		rotation.y = yaw
		cam.rotation.x = pitch
	if event.is_action_pressed("ads"):
		ads = true
	if event.is_action_released("ads"):
		ads = false
	if event.is_action_pressed("slot1"):
		cast_mode = ""
		if primary.size() > 0:
			weapon = primary
			slot = "primary"
		else:
			main.sfx.play("deny")
	if event.is_action_pressed("slot2"):
		cast_mode = ""
		weapon = secondary
		slot = "secondary"
	if event.is_action_pressed("slot3"):
		cast_mode = ""
		weapon = knife_w
		slot = "knife"
	if event.is_action_pressed("reload"):
		cast_mode = ""
		_start_reload()
	if event.is_action_pressed("ability_c"):
		_equip_ability("c")
	if event.is_action_pressed("ability_q"):
		_equip_ability("q")
	if event.is_action_pressed("ability_e"):
		_equip_ability("e")
	if event.is_action_pressed("ability_x"):
		_equip_ability("x")
	if event.is_action_pressed("buy_menu"):
		main.hud.toggle_buy()
	if event.is_action_pressed("scoreboard"):
		main.hud.show_board(true)
	if event.is_action_released("scoreboard"):
		main.hud.show_board(false)
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		main.hud.toggle_pause()

func _equip_ability(k: String) -> void:
	# 无畏契约式装备施法：按键拿到手上，左键释放，再按同键收回
	if cast_mode == k:
		cast_mode = ""
		return
	var sl: Dictionary = ability_slots[k]
	if k == "x":
		if ult_points < Ab.AGENTS[agent_id]["ult_cost"]:
			main.sfx.play("deny")
			return
		# 切换型大招直接激活（锋刃/火箭/猎杀）
		var xt: String = Ab.AGENTS[agent_id]["x"]["type"]
		if xt in ["knife_ult", "rocket_ult", "hunter_ult", "phoenix_ult", "null_pulse", "shadow_ult"]:
			if Ab.cast(main, self, "x"):
				main.sfx.play("ability")
			return
	elif sl["n"] <= 0 or (k == "e" and main.now() < sl["cd_until"]):
		main.sfx.play("deny")
		return
	cast_mode = k

func _ads_active() -> bool:
	# 近战/手持技能/大招武器不能瞄准
	if weapon["def"]["cat"] == "melee" or cast_mode != "" or knife_ult > 0 or rocket_ult > 0 or arrow_ult > 0:
		return false
	return ads

func _scoped() -> bool:
	return weapon["def"].get("scope", false) and _ads_active()

func _physics_process(dt: float) -> void:
	if not alive:
		_spectate(dt)
		return
	spectating = null
	if cam.top_level:
		cam.top_level = false
		cam.position = Vector3(0, 1.55, 0)
		cam.rotation = Vector3(pitch, 0, 0)
	var now: float = main.now()
	var cap := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if cap and not _was_captured:
		mouse_ignore_until = now + 0.15
	_was_captured = cap
	# 视模刷新（换枪/大招武器切换时）
	var vm_id: String = weapon["def"]["name"] + ("K" if knife_ult > 0 else "") + ("R" if rocket_ult > 0 else "") + ("A" if arrow_ult > 0 else "") + cast_mode
	if vm_id != _vm_weapon_id:
		_vm_weapon_id = vm_id
		_rebuild_viewmodel()
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
	var spd: float = SPEED * CAT_SPEED.get(weapon["def"]["cat"], 1.0) * (0.52 if walk else 1.0) * (0.55 if crouching else 1.0) * (0.75 if _ads_active() else 1.0)
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
	_step_assist()
	step_acc += Vector2(velocity.x, velocity.z).length() * dt
	if step_acc > 2.8:
		step_acc = 0.0
		if not walk and not crouching:
			main.sfx.play("step")

	cam.position.y = 1.15 if crouching else 1.55
	cam.fov = lerpf(cam.fov, (30.0 if _scoped() else (fov_base * 0.82 if _ads_active() else fov_base)), dt * 14.0)
	# 视模摆动/后座/换弹动画
	bob_t += Vector2(velocity.x, velocity.z).length() * dt * 1.8
	vm_kick = move_toward(vm_kick, 0.0, dt * 0.6)
	var ads_on := _ads_active()
	var tx := 0.0 if ads_on else 0.18
	var ty := (-0.12 if ads_on else -0.16) + sin(bob_t) * 0.004
	vm_group.position = vm_group.position.lerp(Vector3(tx, ty, -0.35 + vm_kick), minf(1.0, dt * 18.0))
	vm_group.visible = not (ads and weapon["def"].get("scope", false))
	var rl: bool = weapon["reload_end"] > 0
	vm_group.rotation.x = lerpf(vm_group.rotation.x, (0.5 if rl else 0.0) + vm_kick * 1.4, dt * 10.0)

	# 换弹结算
	if weapon["reload_end"] > 0 and now >= weapon["reload_end"]:
		var need: int = weapon["def"]["mag"] - weapon["ammo"]
		var take: int = mini(need, weapon["reserve"])
		weapon["ammo"] += take
		weapon["reserve"] -= take
		weapon["reload_end"] = 0.0
	# 射击（含大招武器）
	if cast_mode != "" and Input.is_action_just_pressed("fire"):
		var ck := cast_mode
		cast_mode = ""
		if Ab.cast(main, self, ck):
			main.sfx.play("ability")
		return
	var fire_held := Input.is_action_pressed("fire")
	var fire_tap := Input.is_action_just_pressed("fire")
	var wants_fire: bool = fire_held if weapon["def"].get("auto", true) else fire_tap
	if rocket_ult > 0 or knife_ult > 0: wants_fire = fire_held
	if arrow_ult > 0: wants_fire = fire_tap
	if wants_fire and main.can_fight() and now >= weapon["next_fire"] and weapon["reload_end"] == 0.0:
		if rocket_ult > 0:
			rocket_ult -= 1
			weapon["next_fire"] = now + 0.9
			main.sfx.shot("rifle")
			main.throw_grenade(self, "nade_throw", eye_pos(), aim_dir())
		elif arrow_ult > 0:
			arrow_ult -= 1
			weapon["next_fire"] = now + 0.9
			main.pierce_shot(self, eye_pos(), aim_dir())
		elif knife_ult > 0:
			knife_ult -= 1
			weapon["next_fire"] = now + 0.33
			main.sfx.shot("melee")
			main.hitscan(self, eye_pos(), aim_dir(), {"range": 60, "dmg": {"h": 150, "b": 50, "l": 50}})
		elif weapon["def"]["cat"] == "melee":
			weapon["next_fire"] = now + weapon["def"]["fi"]
			vm_kick += 0.05
			main.sfx.shot("melee")
			main.hitscan(self, eye_pos(), aim_dir(), weapon["def"])
		elif weapon["ammo"] > 0:
			_shoot(now)
		else:
			main.sfx.play("dry")
			_start_reload()
	bloom = move_toward(bloom, 0, 4.4 * dt)
	recoil = move_toward(recoil, 0, 8.0 * dt)

	channel = ""
	if Input.is_action_pressed("interact"):
		main.match_mgr.player_interact(self, dt)
		_try_pickup()

# ---------------- 观战（阵亡后跟随存活队友，左键切换） ----------------
func _spectate(dt: float) -> void:
	vm_group.visible = false
	if not cam.top_level:
		cam.top_level = true
	var allies: Array = []
	for e in main.bots:
		if e.alive and (observer or e.team == "ally"):
			allies.append(e)
	if allies.size() > 0:
		var t: Node = allies[spectate_idx % allies.size()]
		spectating = t
		if t.rig != null:
			t.rig.visible = false
		for e in allies:
			if e != t and e.rig != null:
				e.rig.visible = true
		var eye: Vector3 = t.global_position + Vector3(0, 1.55, 0)
		cam.global_position = cam.global_position.lerp(eye, minf(1.0, dt * 20.0))
		var want := Basis.from_euler(Vector3(0, t.yaw, 0))
		if t.target != null and is_instance_valid(t.target):
			var d: Vector3 = t.aim_dir()
			want = Basis.looking_at(d, Vector3.UP)
		cam.global_transform.basis = cam.global_transform.basis.slerp(want, minf(1.0, dt * 12.0))
	else:
		spectating = null
		cam.global_position = cam.global_position.lerp(Vector3(0, 42, 12), minf(1.0, dt * 3.0))
		cam.global_transform.basis = cam.global_transform.basis.slerp(Basis.from_euler(Vector3(-1.25, 0, 0)), minf(1.0, dt * 3.0))

func _step_assist() -> void:
	# 楼梯/矮台阶直接走（≤0.5m），跳跃留给箱子
	if not is_on_wall() or not is_on_floor():
		return
	var hv := Vector3(velocity.x, 0, velocity.z)
	if hv.length() < 1.0:
		return
	var dir := hv.normalized()
	var ahead := global_position + dir * 0.55
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(ahead + Vector3(0, 1.4, 0), ahead + Vector3(0, 0.02, 0))
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var rise: float = hit["position"].y - global_position.y
	if rise > 0.08 and rise <= 0.5:
		global_position.y = hit["position"].y + 0.02

func _try_pickup() -> void:
	if main.now() < next_pickup_t:
		return
	var d: Dictionary = main.nearest_drop(global_position, 1.8)
	if d.is_empty():
		return
	next_pickup_t = main.now() + 0.6
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
	if _ads_active() and not _scoped(): spread *= 0.55
	var pellets: int = weapon["def"].get("pellets", 1)
	for i in range(pellets):
		var d := aim_dir()
		d += Vector3(randfn(0, spread), randfn(0, spread) + recoil * 0.012, randfn(0, spread))
		main.hitscan(self, eye_pos(), d.normalized(), weapon["def"])
	bloom += 0.5
	recoil += 1.4
	vm_kick += 0.02
	pitch = clampf(pitch + 0.006 * (0.5 if _ads_active() else 1.0), -1.55, 1.55)
	cam.rotation.x = pitch
	main.sfx.shot(weapon["def"]["cat"])
	main.spawn_particles(eye_pos() + aim_dir() * 0.9, Color(1.0, 0.85, 0.5), 3, 1.5, 0.1)

func _start_reload() -> void:
	if weapon["reload_end"] > 0 or weapon["reserve"] <= 0 or weapon["ammo"] >= weapon["def"]["mag"]:
		return
	weapon["reload_end"] = main.now() + weapon["def"]["rl"]
	main.sfx.play("reload")

func take_damage(dmg: float, killer: Node = null, _hs: bool = false) -> void:
	if not alive:
		return
	if main.now() < resist_until:
		dmg *= 0.55
	var absorb: float = minf(armor, dmg * 0.66)
	armor -= int(absorb)
	hp -= dmg - absorb
	main.hud.damaged()
	main.sfx.play("hurt")
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
	cast_mode = ""
	ads = false
	knife_ult = 0
	rocket_ult = 0
	arrow_ult = 0
	spectate_idx = 0
	spectating = null
	flash_until = 0.0
	daze_until = 0.0
	slow_until = 0.0
	suppressed_until = 0.0
	# 双枪弹药全部补满（存活继承武器，弹药每回合重置）
	for w in [primary, secondary]:
		if w.size() > 0:
			w["ammo"] = w["def"]["mag"]
			w["reserve"] = w["def"]["res"]
			w["reload_end"] = 0.0
			w["next_fire"] = 0.0
	# 固有技能（免费 E 等）每回合回复
	for k in ["c", "q", "e"]:
		var sl: Dictionary = ability_slots[k]
		if sl["def"]["cost"] == 0 and sl["n"] < sl["def"].get("max", 1):
			sl["n"] = sl["def"].get("max", 1)
		sl["cd_until"] = 0.0

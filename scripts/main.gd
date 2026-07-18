# main.gd — 启动器：选图菜单 → 建图 → 生成玩家/AI → 战斗系统（射线/投掷物/特效）
extends Node3D

const MapBuilderScript := preload("res://scripts/map_builder.gd")
const PlayerScript := preload("res://scripts/player.gd")
const BotScript := preload("res://scripts/bot_ai.gd")
const MatchScript := preload("res://scripts/match_mgr.gd")
const HudScript := preload("res://scripts/hud.gd")

var map: Node3D
var player: CharacterBody3D
var bots: Array = []
var match_mgr: Node
var hud: CanvasLayer
var primary_weapon: Dictionary = {}
var difficulty := 1.0
var _t := 0.0
var menu: CanvasLayer
var started := false
var projectiles: Array = []

const AGENT_COLORS := [Color(0.56, 0.83, 1.0), Color(1.0, 0.48, 0.19), Color(0.96, 0.77, 0.42), Color(0.54, 0.44, 0.85), Color(0.41, 0.78, 0.49)]

func now() -> float:
	return _t

func _ready() -> void:
	_t = 0.0
	_build_menu()
	# CI/无头测试：TP_AUTOSTART=<map_id> 自动开局
	var auto := OS.get_environment("TP_AUTOSTART")
	if auto != "":
		call_deferred("_start_game", auto)

func _build_menu() -> void:
	menu = CanvasLayer.new()
	menu.layer = 10
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.09, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.position = Vector2(-200, -280)
	menu.add_child(v)
	var title := Label.new()
	title.text = "TACTICAL PROTOCOL — Godot 版\n选择地图开始（5v5 炸弹模式）"
	title.add_theme_font_size_override("font_size", 26)
	v.add_child(title)
	var data: Dictionary = MapBuilderScript.load_all()
	for m in data["maps"]:
		var btn := Button.new()
		btn.text = "%s — %s" % [m["name"], m["desc"]]
		btn.pressed.connect(_start_game.bind(m["id"]))
		v.add_child(btn)

func _start_game(map_id: String) -> void:
	menu.queue_free()
	started = true
	var data: Dictionary = MapBuilderScript.load_all()
	var md: Dictionary = {}
	for m in data["maps"]:
		if m["id"] == map_id:
			md = m
			break

	# 环境
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skm := ProceduralSkyMaterial.new()
	skm.sky_top_color = Color(md["skyTop"])
	skm.ground_bottom_color = Color(md["skyBot"])
	sky.sky_material = skm
	e.sky = sky
	e.fog_enabled = true
	e.fog_light_color = Color(md["fog"])
	e.fog_density = 0.004
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 30, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	add_child(sun)

	# 地图
	map = MapBuilderScript.new()
	add_child(map)
	map.build(md, float(data["world"]))

	# HUD
	hud = HudScript.new()
	add_child(hud)
	hud.setup(self)

	# 玩家
	player = PlayerScript.new()
	player.main = self
	add_child(player)

	# AI（我方 4 + 敌方 5）
	var names_a := ["风影", "烈焰", "圣愈", "猎鹰"]
	var names_e := ["天穹", "暗幕", "蛛影", "岚切", "零式"]
	for i in range(4):
		bots.append(_mk_bot("ally", names_a[i], AGENT_COLORS[i % AGENT_COLORS.size()]))
	for i in range(5):
		bots.append(_mk_bot("enemy", names_e[i], Color(0.85, 0.32, 0.36)))

	# 比赛
	match_mgr = MatchScript.new()
	add_child(match_mgr)
	match_mgr.setup(self)

func _mk_bot(t: String, nm: String, col: Color) -> CharacterBody3D:
	var b := BotScript.new()
	add_child(b)
	b.setup(self, t, nm, col)
	return b

func combatants() -> Array:
	var arr := bots.duplicate()
	arr.append(player)
	return arr

func can_fight() -> bool:
	var ph: String = match_mgr.phase
	return ph == "live" or ph == "planted"

func difficulty_get() -> float:
	return difficulty

# ---------- 战斗 ----------
func has_los(from: Vector3, to: Vector3, exclude: Array) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var rids: Array[RID] = []
	for e in exclude:
		if is_instance_valid(e):
			rids.append(e.get_rid())
	q.exclude = rids
	var hit := space.intersect_ray(q)
	return hit.is_empty()

func hitscan(shooter: Node, origin: Vector3, dir: Vector3, def: Dictionary) -> void:
	var space := get_world_3d().direct_space_state
	var to: Vector3 = origin + dir * float(def["range"]) * 2.0
	var q := PhysicsRayQueryParameters3D.create(origin, to)
	q.exclude = [shooter.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	_tracer(origin + dir * 0.8, hit["position"])
	if col is CharacterBody3D and "team" in col and col.team != shooter.team:
		var rel_y: float = hit["position"].y - col.global_position.y
		var part := "l"
		if rel_y > 1.45: part = "h"
		elif rel_y > 0.85: part = "b"
		var dmg: float = def["dmg"][part]
		var dist: float = origin.distance_to(hit["position"])
		if dist > def["range"]:
			dmg *= 0.75
		col.take_damage(dmg)

func throw_projectile(shooter: Node, kind: String, origin: Vector3, dir: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.11
	sm.height = 0.22
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission = Color(0.75, 0.79, 0.85) if kind == "smoke" else Color(1.0, 0.91, 0.63)
	mat.albedo_color = mat.emission
	sm.material = mat
	mesh.mesh = sm
	add_child(mesh)
	mesh.global_position = origin + dir * 0.6
	projectiles.append({ "mesh": mesh, "vel": dir * 21.0 + Vector3.UP * 3.0, "kind": kind, "shooter": shooter, "born": now() })

var _dbg_next := 0.0
func _physics_process(dt: float) -> void:
	_t += dt
	if not started:
		return
	if OS.get_environment("TP_AUTOSTART") != "" and _t >= _dbg_next:
		_dbg_next = _t + 4.0
		var alive_a := 0
		var alive_e := 0
		for e in combatants():
			if e.alive:
				if e.team == "ally": alive_a += 1
				else: alive_e += 1
		var b0: CharacterBody3D = bots[0]
		print("[TP] t=%.0f phase=%s score=%s alive=%d/%d bot0=%s (%.0f,%.0f) spike=%s" % [_t, match_mgr.phase, str(match_mgr.score), alive_a, alive_e, b0.state, b0.global_position.x, b0.global_position.z, match_mgr.spike_state])
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		p["vel"] += Vector3.DOWN * 11.0 * dt
		var mesh: MeshInstance3D = p["mesh"]
		var next: Vector3 = mesh.global_position + p["vel"] * dt
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(mesh.global_position, next)
		var hit := space.intersect_ray(q)
		var landed := false
		if not hit.is_empty():
			mesh.global_position = hit["position"]
			landed = true
		else:
			mesh.global_position = next
			if next.y <= 0.15:
				landed = true
		if landed:
			_pop_projectile(p)
			mesh.queue_free()
			projectiles.remove_at(i)

func _pop_projectile(p: Dictionary) -> void:
	var pos: Vector3 = p["mesh"].global_position
	if p["kind"] == "smoke":
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 4.0
		sm.height = 8.0
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.88, 0.92, 0.96)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		sm.material = mat
		s.mesh = sm
		add_child(s)
		s.global_position = Vector3(pos.x, 2.0, pos.z)
		var timer := get_tree().create_timer(15.0)
		timer.timeout.connect(func(): if is_instance_valid(s): s.queue_free())
	else:
		# 闪光：距离+朝向影响（简化：致盲附近敌 AI）
		for e in combatants():
			if e == p["shooter"] or not e.alive:
				continue
			if e.global_position.distance_to(pos) < 12.0 and e != player:
				e.next_think = now() + 2.2
				e.target = null

func spawn_spike_mesh(pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.24, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.2, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.3)
	bm.material = mat
	m.mesh = bm
	add_child(m)
	m.global_position = pos + Vector3(0, 0.12, 0)
	var t := get_tree().create_timer(50.0)
	t.timeout.connect(func(): if is_instance_valid(m): m.queue_free())

func explosion_at(pos: Vector3) -> void:
	for e in combatants():
		if e.alive and e.global_position.distance_to(pos) < 12.0:
			e.take_damage(500.0)

func map_rebuild_barriers() -> void:
	pass  # 光幕当前回合制简化：首回合已建；后续回合不重建（AI 出生即在阵地）

func _tracer(from: Vector3, to: Vector3) -> void:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.91, 0.63)
	mi.material_override = mat
	add_child(mi)
	var t := get_tree().create_timer(0.07)
	t.timeout.connect(func(): if is_instance_valid(mi): mi.queue_free())

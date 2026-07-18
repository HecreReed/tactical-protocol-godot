# main.gd — 战场核心：环境/物理投掷物/区域/烟雾(视觉遮断)/装置/粒子/爆炸冲量/掉落武器/布娃娃
extends Node3D

const MapBuilderScript := preload("res://scripts/map_builder.gd")
const PlayerScript := preload("res://scripts/player.gd")
const BotScript := preload("res://scripts/bot_ai.gd")
const MatchScript := preload("res://scripts/match_mgr.gd")
const HudScript := preload("res://scripts/hud.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const Weapons := preload("res://scripts/weapons.gd")
const Ab := preload("res://scripts/abilities.gd")

var map: Node3D
var player: CharacterBody3D
var bots: Array = []
var match_mgr: Node
var hud: CanvasLayer
var difficulty := 1.0
var _t := 0.0
var menu: CanvasLayer
var started := false
var zones: Array = []       # {pos,r,until,dps,slow,heal_owner,owner,mesh}
var smokes: Array = []      # {pos,r,until,mesh,body}
var devices: Array = []     # {kind,pos,owner,team,node,until,arm_at,hp,next_fire}
var drops: Array = []       # {body, weapon}
var sel_map_id := ""
var observer := false
var sfx: Node
var _fx_live := 0

func now() -> float:
	return _t

func _ready() -> void:
	print("[BOOT] main._ready")
	_t = 0.0
	_build_menu()
	print("[BOOT] menu built")
	var auto := OS.get_environment("TP_AUTOSTART")
	if auto != "":
		call_deferred("_start_game", auto, "astra", false)

# ---------------- 菜单（复刻网页版：地图卡片+难度 → 特工卡片 / 观战模式） ----------------
const MC_BG := Color8(0x0f, 0x19, 0x23)
const MC_PANEL := Color8(0x13, 0x1e, 0x29)
const MC_BORDER := Color8(0x24, 0x33, 0x3f)
const MC_RED := Color8(0xff, 0x46, 0x55)
const MC_TEAL := Color8(0x39, 0xd0, 0xc9)
const MC_GOLD := Color8(0xf5, 0xc5, 0x6b)
const MC_DIM := Color8(0x8b, 0x97, 0x8f)
const MC_WHITE := Color8(0xec, 0xe8, 0xe1)

var _menu_maps: Array = []
var _map_cards: Array = []
var _diff_btns: Array = []
var _sub_label: Label
var _step1: VBoxContainer
var _step2: VBoxContainer

static func _card_sb(bg: Color, border: Color, bw: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

func _mlbl(parent: Node, size: int, col: Color, text: String, center := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func _build_menu() -> void:
	menu = CanvasLayer.new()
	menu.layer = 10
	add_child(menu)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(root)
	var bg := ColorRect.new()
	bg.color = MC_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	center.add_child(v)

	# 标题：TACTICAL PROTOCOL（PROTOCOL 红色）
	var th := HBoxContainer.new()
	th.alignment = BoxContainer.ALIGNMENT_CENTER
	th.add_theme_constant_override("separation", 14)
	v.add_child(th)
	_mlbl(th, 34, MC_WHITE, "TACTICAL")
	_mlbl(th, 34, MC_RED, "PROTOCOL")
	_sub_label = _mlbl(v, 13, MC_DIM, "第 1 步 · 选择地图与难度")

	var data: Dictionary = MapBuilderScript.load_all()
	if data.is_empty():
		_sub_label.text = "错误：地图数据加载失败（data/maps.json 未打包）"
		push_error("maps.json load failed")
		return
	_menu_maps = data["maps"]
	print("[BOOT] maps loaded: %d" % [_menu_maps.size()])

	# ---- 第 1 步：地图卡片 + 难度 ----
	_step1 = VBoxContainer.new()
	_step1.add_theme_constant_override("separation", 12)
	v.add_child(_step1)
	var cards := HFlowContainer.new()
	cards.alignment = FlowContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("h_separation", 10)
	cards.add_theme_constant_override("v_separation", 10)
	cards.custom_minimum_size = Vector2(880, 0)
	_step1.add_child(cards)
	sel_map_id = _menu_maps[0]["id"]
	for m in _menu_maps:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(150, 0)
		card.add_theme_stylebox_override("panel", _card_sb(MC_PANEL, MC_BORDER))
		var cv := VBoxContainer.new()
		card.add_child(cv)
		_mlbl(cv, 18, MC_WHITE, m["name"])
		var dl := _mlbl(cv, 11, MC_DIM, m["desc"])
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(126, 0)
		card.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				sel_map_id = m["id"]
				_refresh_map_cards())
		cards.add_child(card)
		_map_cards.append({ "node": card, "id": m["id"] })
	_refresh_map_cards()

	var diffs := HBoxContainer.new()
	diffs.alignment = BoxContainer.ALIGNMENT_CENTER
	diffs.add_theme_constant_override("separation", 8)
	_step1.add_child(diffs)
	for d in [["新手", 0.55], ["常规", 0.8], ["困难", 1.0], ["天梯", 1.25]]:
		var b := Button.new()
		b.text = d[0]
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_stylebox_override("normal", _card_sb(MC_PANEL, MC_BORDER))
		b.add_theme_stylebox_override("hover", _card_sb(MC_PANEL, MC_TEAL))
		b.add_theme_stylebox_override("pressed", _card_sb(Color8(0x2a, 0x1a, 0x20), MC_RED))
		b.pressed.connect(func():
			difficulty = d[1]
			_refresh_diff_btns())
		diffs.add_child(b)
		_diff_btns.append({ "node": b, "diff": d[1] })
	_refresh_diff_btns()

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	_step1.add_child(btn_row)
	var next_btn := Button.new()
	next_btn.text = "下一步 · 选择特工 →"
	next_btn.add_theme_font_size_override("font_size", 15)
	next_btn.add_theme_color_override("font_color", Color.WHITE)
	var red_sb := _card_sb(MC_RED, MC_RED)
	red_sb.content_margin_left = 34
	red_sb.content_margin_right = 34
	next_btn.add_theme_stylebox_override("normal", red_sb)
	next_btn.add_theme_stylebox_override("hover", _card_sb(Color8(0xff, 0x5c, 0x69), MC_RED))
	next_btn.pressed.connect(func(): _to_step(2))
	btn_row.add_child(next_btn)
	var obs_btn := Button.new()
	obs_btn.text = "观战模式（只看 AI 对战）"
	obs_btn.add_theme_font_size_override("font_size", 14)
	obs_btn.add_theme_color_override("font_color", MC_TEAL)
	obs_btn.add_theme_stylebox_override("normal", _card_sb(Color8(0x1a, 0x2a, 0x36), MC_TEAL))
	obs_btn.add_theme_stylebox_override("hover", _card_sb(Color8(0x22, 0x36, 0x44), MC_TEAL))
	obs_btn.pressed.connect(func(): _start_game(sel_map_id, "", true))
	btn_row.add_child(obs_btn)

	# ---- 第 2 步：特工卡片 ----
	_step2 = VBoxContainer.new()
	_step2.add_theme_constant_override("separation", 12)
	_step2.visible = false
	v.add_child(_step2)
	var acards := HFlowContainer.new()
	acards.alignment = FlowContainer.ALIGNMENT_CENTER
	acards.add_theme_constant_override("h_separation", 12)
	acards.add_theme_constant_override("v_separation", 12)
	acards.custom_minimum_size = Vector2(1020, 0)
	_step2.add_child(acards)
	for aid in Ab.AGENTS.keys():
		acards.add_child(_agent_card(aid))
	var back := Button.new()
	back.text = "← 返回选图"
	back.add_theme_font_size_override("font_size", 14)
	back.add_theme_color_override("font_color", MC_DIM)
	back.add_theme_stylebox_override("normal", _card_sb(MC_PANEL, MC_BORDER))
	back.add_theme_stylebox_override("hover", _card_sb(MC_PANEL, MC_TEAL))
	back.pressed.connect(func(): _to_step(1))
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back)
	_step2.add_child(back_row)

	var help := _mlbl(v, 12, MC_DIM, "WASD 移动 · Shift 静步 · Ctrl 蹲 · 左键开火 · 右键瞄准 · R 换弹 · B 购买 · C/Q/E 技能 · X 大招 · F 安放/拆除/拾取 · Tab 计分板")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _agent_card(aid: String) -> PanelContainer:
	var a: Dictionary = Ab.AGENTS[aid]
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(158, 0)
	card.add_theme_stylebox_override("panel", _card_sb(MC_PANEL, MC_BORDER))
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	card.add_child(cv)
	var swatch := ColorRect.new()
	swatch.color = a["color"]
	swatch.custom_minimum_size = Vector2(0, 6)
	cv.add_child(swatch)
	_mlbl(cv, 18, MC_WHITE, a["name"])
	var role := _mlbl(cv, 11, MC_GOLD, "%s · %s" % [a.get("role", ""), a.get("desc", "")])
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role.custom_minimum_size = Vector2(134, 0)
	for k in ["c", "q", "e", "x"]:
		var ab: Dictionary = a[k]
		var suffix := ""
		if k == "e": suffix = "  免费"
		elif k == "x": suffix = "  %d点" % a["ult_cost"]
		var li := _mlbl(cv, 11, MC_DIM, "%s  %s%s" % [k.to_upper(), ab["name"], suffix], false)
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_start_game(sel_map_id, aid, false))
	card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", _card_sb(MC_PANEL, MC_RED)))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", _card_sb(MC_PANEL, MC_BORDER)))
	return card

func _to_step(n: int) -> void:
	_step1.visible = n == 1
	_step2.visible = n == 2
	_sub_label.text = "第 1 步 · 选择地图与难度" if n == 1 else "第 2 步 · 选择你的特工"

func _refresh_map_cards() -> void:
	for mc in _map_cards:
		var selected: bool = mc["id"] == sel_map_id
		(mc["node"] as PanelContainer).add_theme_stylebox_override("panel",
			_card_sb(Color8(0x15, 0x30, 0x3a) if selected else MC_PANEL, MC_TEAL if selected else MC_BORDER, 2 if selected else 1))

func _refresh_diff_btns() -> void:
	for db in _diff_btns:
		var selected: bool = absf(db["diff"] - difficulty) < 0.01
		(db["node"] as Button).add_theme_stylebox_override("normal",
			_card_sb(Color8(0x2a, 0x1a, 0x20) if selected else MC_PANEL, MC_RED if selected else MC_BORDER))
		(db["node"] as Button).add_theme_color_override("font_color", MC_WHITE if selected else MC_DIM)

func _start_game(map_id: String, agent_id: String, obs: bool = false) -> void:
	if started:
		return
	started = true
	observer = obs
	if is_instance_valid(menu):
		menu.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var data: Dictionary = MapBuilderScript.load_all()
	var md: Dictionary = {}
	for m in data["maps"]:
		if m["id"] == map_id:
			md = m
			break

	# ---- 环境：程序化天空 + 距离雾 + 泛光 + ACES ----
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var skm := ProceduralSkyMaterial.new()
	skm.sky_top_color = Color(md["skyTop"])
	skm.sky_horizon_color = Color(md["fog"])
	skm.ground_bottom_color = Color(md["skyBot"])
	skm.ground_horizon_color = Color(md["fog"])
	sky.sky_material = skm
	e.sky = sky
	e.fog_enabled = true
	e.fog_light_color = Color(md["fog"])
	e.fog_density = 0.0035
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.1
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, 28, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.25
	sun.directional_shadow_max_distance = 110
	add_child(sun)

	map = MapBuilderScript.new()
	add_child(map)
	map.build(md, float(data["world"]))

	sfx = SfxScript.new()
	add_child(sfx)
	hud = HudScript.new()
	add_child(hud)

	player = PlayerScript.new()
	player.main = self
	player.agent_id = agent_id if agent_id != "" else "astra"
	player.observer = observer
	add_child(player)
	hud.setup(self)

	var pool: Array = Ab.AGENTS.keys()
	pool.shuffle()
	var ai_agents: Array = []
	for aid in pool:
		if aid != agent_id:
			ai_agents.append(aid)
	var n_ally := 5 if observer else 4
	for i in range(n_ally):
		bots.append(_mk_bot("ally", ai_agents[i]))
	for i in range(5):
		bots.append(_mk_bot("enemy", ai_agents[(i + n_ally) % ai_agents.size()]))

	match_mgr = MatchScript.new()
	add_child(match_mgr)
	match_mgr.setup(self)

func _mk_bot(t: String, aid: String) -> CharacterBody3D:
	var b := BotScript.new()
	add_child(b)
	b.setup(self, t, aid)
	return b

func combatants() -> Array:
	var arr := bots.duplicate()
	if not observer:
		arr.append(player)
	return arr

func can_fight() -> bool:
	var ph: String = match_mgr.phase
	return ph == "live" or ph == "planted"

# ---------------- 视线 / 射击 ----------------
func has_los(from: Vector3, to: Vector3, exclude: Array) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 | 2      # 世界 + 烟雾视觉遮断层
	var rids: Array[RID] = []
	for ex in exclude:
		if is_instance_valid(ex):
			rids.append(ex.get_rid())
	q.exclude = rids
	return space.intersect_ray(q).is_empty()

func pierce_shot(shooter: Node, origin: Vector3, dir: Vector3) -> void:
	# 猎杀之矢：无视墙体，命中射线附近最近的敌人
	var best: Node = null
	var bd := 1e9
	for e in combatants():
		if not e.alive or e.team == shooter.team:
			continue
		var to: Vector3 = e.global_position + Vector3(0, 1.2, 0) - origin
		var t := to.dot(dir)
		if t < 1.0 or t > 70.0:
			continue
		var off: float = (to - dir * t).length()
		if off < 1.1 and t < bd:
			bd = t
			best = e
	_tracer(origin + dir * 0.6, origin + dir * (bd if best != null else 60.0))
	sfx.shot("sniper", 0.0)
	if best != null:
		spawn_particles(best.global_position + Vector3(0, 1.2, 0), Color(0.4, 1.0, 0.6), 12, 3.0, 0.4)
		if shooter == player:
			sfx.play("hit")
		best.take_damage(90.0, shooter, false)
		best.revealed_until = now() + 2.0

func hitscan(shooter: Node, origin: Vector3, dir: Vector3, def: Dictionary) -> void:
	var space := get_world_3d().direct_space_state
	var to: Vector3 = origin + dir * float(def["range"]) * 2.0
	var q := PhysicsRayQueryParameters3D.create(origin, to)
	q.collision_mask = 1 | 4 | 16          # 世界 + 部署物 + 角色（子弹穿烟）
	q.exclude = [shooter.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	_tracer(origin + dir * 0.8, hit["position"])
	# 枪声情报：28m 内的敌方 bot 获知射手方位
	if "team" in shooter:
		for b in bots:
			if b.alive and b.team != shooter.team and b.target == null \
					and b.global_position.distance_to(origin) < 28.0:
				b.last_seen = shooter.global_position
	if col is Node and col.has_meta("device"):
		damage_device(col, def["dmg"]["b"])
		spawn_particles(hit["position"], Color(0.9, 0.7, 0.3), 6, 2.5, 0.25)
		if shooter == player:
			sfx.play("hit")
		return
	if col is CharacterBody3D and "team" in col and col.team != shooter.team:
		var rel_y: float = hit["position"].y - col.global_position.y
		var crouched: bool = ("crouching" in col) and col.crouching
		var part := "l"
		if crouched:
			if rel_y > 1.02: part = "h"
			elif rel_y > 0.6: part = "b"
		elif rel_y > 1.45: part = "h"
		elif rel_y > 0.85: part = "b"
		var dmg: float = def["dmg"][part]
		var dist := origin.distance_to(hit["position"])
		for tier in def.get("tiers", []):
			if dist > float(tier[0]):
				dmg = tier[1][part]
		if dist > float(def["range"]):
			dmg *= 0.85
		spawn_particles(hit["position"], Color(0.8, 0.15, 0.15), 10, 3.0, 0.35)
		if shooter == player:
			sfx.play("headshot" if part == "h" else "hit")
		col.take_damage(dmg, shooter, part == "h")
	else:
		spawn_particles(hit["position"], Color(0.9, 0.85, 0.6), 6, 2.5, 0.25)

# ---------------- 真实物理投掷物（RigidBody 弹跳） ----------------
func throw_grenade(shooter: Node, kind: String, origin: Vector3, dir: Vector3) -> void:
	var body := RigidBody3D.new()
	body.mass = 0.4
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.45
	pm.friction = 0.6
	body.physics_material_override = pm
	body.collision_layer = 4
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.1
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	var col := _kind_color(kind)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.6
	sm.material = mat
	mi.mesh = sm
	body.add_child(mi)
	add_child(body)
	body.global_position = origin + dir * 0.7
	body.linear_velocity = dir * 21.0 + Vector3.UP * 3.0
	body.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), 0)
	var fuse := 1.15 if kind != "flash_throw" else 0.55
	var wr: WeakRef = weakref(body)
	get_tree().create_timer(fuse).timeout.connect(func():
		var b: Node = wr.get_ref()
		if b != null:
			_grenade_pop(b, kind, shooter))

func _kind_color(kind: String) -> Color:
	match kind:
		"smoke_throw", "toxic_smoke": return Color(0.8, 0.85, 0.9)
		"flash_throw": return Color(1.0, 0.92, 0.6)
		"molly_throw", "hot_hands": return Color(1.0, 0.5, 0.2)
		"acid_throw": return Color(0.35, 0.85, 0.5)
		"slow_throw": return Color(0.5, 0.8, 1.0)
		"suppress_throw": return Color(0.7, 0.5, 1.0)
		"recon_throw": return Color(0.25, 0.85, 0.8)
		"shock_throw": return Color(0.55, 0.85, 1.0)
		"nano_throw": return Color(0.75, 0.8, 0.85)
	return Color(1, 0.6, 0.25)

func _grenade_pop(body: RigidBody3D, kind: String, shooter: Node) -> void:
	if not is_instance_valid(body):
		return
	var pos := body.global_position
	body.queue_free()
	match kind:
		"smoke_throw":
			spawn_smoke(pos, 4.0, 15.0)
		"toxic_smoke":
			spawn_smoke(pos, 3.8, 11.0)
			spawn_zone(shooter, pos, 3.4, 11.0, 8.0)
		"flash_throw":
			flash_burst(pos, shooter)
		"molly_throw":
			spawn_zone(shooter, pos, 4.0, 7.0, 55.0)
		"hot_hands":
			var z := spawn_zone(shooter, pos, 3.6, 8.0, 26.0)
			z["heal_owner"] = true
		"acid_throw":
			spawn_zone(shooter, pos, 3.6, 8.0, 12.0)
		"slow_throw":
			var z2 := spawn_zone(shooter, pos, 4.5, 6.5, 0.0)
			z2["slow"] = true
		"shock_throw":
			spawn_zone(shooter, pos, 3.2, 4.0, 70.0)
		"nade_throw":
			explode(shooter, pos, 4.0, 75.0, 30.0)
		"suppress_throw":
			suppress_burst(pos, 5.5, 5.0, shooter)
		"recon_throw":
			reveal_area(pos, 16.0, shooter)
		"nano_throw":
			spawn_device(shooter, "nano", pos)

# ---------------- 烟雾（AI 视线遮断 + 玩家进烟遮罩） ----------------
func spawn_smoke(pos: Vector3, r: float, dur: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.88, 0.92, 0.97)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	sm.material = mat
	mi.mesh = sm
	add_child(mi)
	mi.global_position = Vector3(pos.x, r * 0.5, pos.z)
	# 视觉遮断体（layer 2：AI 视线射线被挡，子弹不挡）
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = r * 0.92
	cs.shape = sh
	body.add_child(cs)
	add_child(body)
	body.global_position = mi.global_position
	spawn_particles(mi.global_position, Color(0.9, 0.92, 0.95), 24, 4.0, 0.8)
	sfx.play("smoke_pop", player.global_position.distance_to(pos))
	smokes.append({ "pos": mi.global_position, "r": r, "until": now() + dur, "mesh": mi, "body": body })

func in_smoke(pos: Vector3) -> bool:
	for s in smokes:
		if pos.distance_to(s["pos"]) < s["r"] * 0.92:
			return true
	return false

# ---------------- 区域（燃烧/减速/毒/治疗） ----------------
func spawn_zone(owner: Node, pos: Vector3, r: float, dur: float, dps: float) -> Dictionary:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = 0.1
	var mat := StandardMaterial3D.new()
	var col := Color(1.0, 0.48, 0.19, 0.4) if dps > 20 else (Color(0.35, 0.85, 0.5, 0.4) if dps > 0 else Color(0.5, 0.8, 1.0, 0.35))
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(col.r, col.g, col.b)
	cm.material = mat
	mi.mesh = cm
	add_child(mi)
	mi.global_position = Vector3(pos.x, 0.06, pos.z)
	var z := { "pos": mi.global_position, "r": r, "until": now() + dur, "dps": dps, "slow": false, "heal_owner": false, "owner": owner, "mesh": mi }
	zones.append(z)
	return z

func explode(owner: Node, pos: Vector3, r: float, dmg_near: float, dmg_far: float) -> void:
	explosion_fx(pos, r, Color(1.0, 0.6, 0.25))
	sfx.play("explosion", player.global_position.distance_to(pos) * 0.4)
	for ent in combatants():
		if not ent.alive:
			continue
		if owner != null and "team" in owner and ent.team == owner.team:
			continue
		var d: float = ent.global_position.distance_to(pos)
		if d < r:
			ent.take_damage(lerpf(dmg_near, dmg_far, d / r), owner, false)
			# 爆炸冲量（物理推动）
			var push: Vector3 = (ent.global_position - pos).normalized() * (r - d) * 3.0
			ent.velocity += push + Vector3.UP * 2.0
	# 推动场上刚体（手雷/掉落武器）
	for d2 in drops:
		if is_instance_valid(d2["body"]) and d2["body"].global_position.distance_to(pos) < r:
			d2["body"].apply_impulse((d2["body"].global_position - pos).normalized() * 4.0 + Vector3.UP * 2.0)

func flash_burst(pos: Vector3, shooter: Node) -> void:
	explosion_fx(pos, 1.2, Color(1.0, 0.95, 0.7))
	sfx.play("flash_pop", player.global_position.distance_to(pos))
	for ent in combatants():
		if not ent.alive or ent == shooter:
			continue
		var d: float = ent.eye_pos().distance_to(pos)
		if d > 22.0:
			continue
		if not has_los(pos, ent.eye_pos(), [shooter, ent]):
			continue
		var dur := clampf(1.9 - d * 0.05, 0.4, 1.9)
		ent.flash_until = maxf(ent.flash_until, now() + dur)
		if ent == player:
			hud.flashed(dur)

func suppress_burst(pos: Vector3, r: float, dur: float, owner: Node) -> void:
	explosion_fx(pos, r * 0.3, Color(0.7, 0.5, 1.0))
	for ent in combatants():
		if not ent.alive:
			continue
		if owner != null and ent.team == owner.team:
			continue
		if ent.global_position.distance_to(pos) < r:
			ent.suppressed_until = maxf(ent.suppressed_until, now() + dur)

func cone_blind(ent: Node, dist: float, dot_min: float, dur: float) -> void:
	var f: Vector3 = ent.aim_dir()
	for e in combatants():
		if not e.alive or e.team == ent.team:
			continue
		var to: Vector3 = e.global_position - ent.global_position
		var d: float = to.length()
		if d > dist:
			continue
		if d > 3.0 and f.dot(to.normalized()) < dot_min:
			continue
		e.flash_until = maxf(e.flash_until, now() + dur)
		if e == player:
			hud.flashed(dur)

func cone_daze(ent: Node, dist: float, dot_min: float, dur: float) -> void:
	var f: Vector3 = ent.aim_dir()
	for e in combatants():
		if not e.alive or e.team == ent.team:
			continue
		var to: Vector3 = e.global_position - ent.global_position
		var d: float = to.length()
		if d > dist:
			continue
		if d > 3.0 and f.dot(to.normalized()) < dot_min:
			continue
		e.daze_until = maxf(e.daze_until, now() + dur)
		if e == player:
			hud.dazed(dur)

func delayed_quake(ent: Node, p: Vector3) -> void:
	spawn_zone(ent, p, 3.4, 0.65, 0.0)
	get_tree().create_timer(0.65).timeout.connect(func():
		if can_fight():
			explode(ent, Vector3(p.x, 0.5, p.z), 3.4, 60.0, 40.0))

func teleport_forward(ent: Node, dist: float) -> void:
	var f: Vector3 = ent.aim_dir()
	var d2 := Vector3(f.x, 0, f.z).normalized()
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(ent.eye_pos(), ent.eye_pos() + d2 * dist)
	q.collision_mask = 1
	q.exclude = [ent.get_rid()]
	var hit := space.intersect_ray(q)
	var t := dist
	if not hit.is_empty():
		t = ent.eye_pos().distance_to(hit["position"]) - 0.8
	spawn_particles(ent.global_position, Color(0.54, 0.44, 0.85), 20, 4.0, 0.5)
	ent.global_position += d2 * maxf(1.0, t)
	spawn_particles(ent.global_position, Color(0.54, 0.44, 0.85), 20, 4.0, 0.5)

func teleport_site(ent: Node) -> void:
	var plant: Vector3 = map.sites[match_mgr.plan_site]["plant"]
	spawn_particles(ent.global_position, Color(0.54, 0.44, 0.85), 26, 5.0, 0.6)
	ent.global_position = plant + Vector3(randf_range(-2, 2), 0.2, randf_range(-2, 2))
	spawn_particles(ent.global_position, Color(0.54, 0.44, 0.85), 26, 5.0, 0.6)

func smoke_site_chokes(ent: Node) -> void:
	# 玩家：烟落在准星指向的落点（单发单点，对齐无畏契约天穹）；AI：轮流封锁计划点烟位
	if ent == player:
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(ent.eye_pos(), ent.eye_pos() + ent.aim_dir() * 60.0)
		q.collision_mask = 1
		q.exclude = [ent.get_rid()]
		var hit := space.intersect_ray(q)
		var p: Vector3 = hit["position"] if not hit.is_empty() else ent.eye_pos() + ent.aim_dir() * 40.0
		spawn_smoke(Vector3(p.x, 0, p.z), 4.2, 18.0)
		return
	var site: String = match_mgr.plan_site
	var pts: Array = map.md["smokePoints"].get(site, [])
	if pts.is_empty():
		spawn_smoke(ent.global_position + ent.aim_dir() * 12.0, 4.2, 18.0)
		return
	var idx: int = ent.get_instance_id() % pts.size()
	if "smoke_idx" in ent:
		idx = ent.smoke_idx % pts.size()
		ent.smoke_idx += 1
	var pt: Array = pts[idx]
	spawn_smoke(Vector3(pt[0], 0, pt[1]), 4.2, 18.0)

func orbital_strike(ent: Node, origin: Vector3, dir: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 80.0)
	q.collision_mask = 1
	q.exclude = [ent.get_rid()]
	var hit := space.intersect_ray(q)
	var p: Vector3 = hit["position"] if not hit.is_empty() else origin + dir * 40.0
	p.y = 0
	var z := spawn_zone(ent, p, 5.5, 2.6, 0.0)
	get_tree().create_timer(2.6).timeout.connect(func():
		if can_fight():
			var zz := spawn_zone(ent, p, 5.5, 2.2, 150.0)
			explosion_fx(Vector3(p.x, 1, p.z), 5.5, Color(1.0, 0.85, 0.3)))

func toxic_wall(ent: Node, dir: Vector3) -> void:
	var d2 := Vector3(dir.x, 0, dir.z).normalized()
	for i in range(7):
		var p: Vector3 = ent.global_position + d2 * (4.0 + i * 3.0)
		spawn_smoke(p, 2.4, 12.0)

func toxic_dome(ent: Node, origin: Vector3, dir: Vector3) -> void:
	var p: Vector3 = origin + dir * 30.0
	p.y = 0
	spawn_smoke(p, 9.0, 26.0)
	spawn_zone(ent, p, 8.5, 26.0, 6.0)

func reveal_enemies(ent: Node) -> void:
	for e in combatants():
		if e.alive and e.team != ent.team:
			e.revealed_until = now() + 5.0

func reveal_area(pos: Vector3, r: float, owner: Node) -> void:
	for e in combatants():
		if e.alive and e.team != owner.team and e.global_position.distance_to(pos) < r:
			e.revealed_until = now() + 4.0

func try_revive(ent: Node) -> bool:
	for e in combatants():
		if e == ent or e.team != ent.team or e.alive:
			continue
		if e.global_position.distance_to(ent.global_position) < 9.0:
			e.revive_at(e.global_position)
			return true
	return false

func spawn_wall(pos: Vector3, yaw: float, dur: float) -> void:
	var d := Vector3(-sin(yaw), 0, -cos(yaw))
	var center := pos + d * 4.0
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(5.0, 2.2, 0.5)
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sh.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.9, 0.95, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.8, 0.85)
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)
	body.global_position = Vector3(center.x, 1.1, center.z)
	body.rotation.y = yaw
	var wrw: WeakRef = weakref(body)
	get_tree().create_timer(dur).timeout.connect(func():
		var b: Node = wrw.get_ref()
		if b != null: b.queue_free())

func spawn_firewall(ent: Node, pos: Vector3, dir: Vector3) -> void:
	var d2 := Vector3(dir.x, 0, dir.z).normalized()
	for i in range(5):
		var p: Vector3 = pos + d2 * (2.0 + i * 2.6)
		spawn_zone(ent, p, 1.5, 6.0, 30.0)

# ---------------- 装置（炮塔/信标/警报/蜂群/封锁） ----------------
func spawn_slow_zone(owner: Node, pos: Vector3, r: float, dur: float) -> void:
	var z := spawn_zone(owner, pos, r, dur, 0.0)
	if z is Dictionary:
		z["slow"] = true

func send_seeker(owner: Node, target: Node) -> void:
	# 追猎之灵：2.4 秒后命中目标——显形+眩晕+减速（对齐网页版 seekers）
	spawn_particles(target.global_position + Vector3(0, 0.5, 0), Color(0.62, 0.88, 0.54), 10, 2.0, 0.8)
	var wrt: WeakRef = weakref(target)
	get_tree().create_timer(2.4).timeout.connect(func():
		var f: Node = wrt.get_ref()
		if f == null or not f.alive or not can_fight():
			return
		f.revealed_until = maxf(f.revealed_until, now() + 4.0)
		f.daze_until = maxf(f.daze_until, now() + 2.2)
		f.slow_until = maxf(f.slow_until, now() + 2.2)
		spawn_particles(f.global_position + Vector3(0, 1.2, 0), Color(0.62, 0.88, 0.54), 16, 3.0, 0.5)
		if f == player:
			hud.dazed(1.5))

func damage_device(node: Node, dmg: float) -> void:
	for i in range(devices.size() - 1, -1, -1):
		var d: Dictionary = devices[i]
		if d["node"] == node:
			d["hp"] = d.get("hp", 40.0) - dmg
			if d["hp"] <= 0:
				explosion_fx(node.global_position, 0.9, Color(1.0, 0.7, 0.3))
				sfx.play("hit", player.global_position.distance_to(node.global_position))
				node.queue_free()
				devices.remove_at(i)
			return

func spawn_device(owner: Node, kind: String, pos: Vector3) -> void:
	var node := StaticBody3D.new()
	node.collision_layer = 4
	node.collision_mask = 0
	node.set_meta("device", true)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, 0.9, 0.6)
	cs.shape = bs
	cs.position = Vector3(0, 0.45, 0)
	node.add_child(cs)
	var mi_dev := MeshInstance3D.new()
	node.add_child(mi_dev)
	var node_mesh := mi_dev
	var col: Color = Color(0.25, 0.85, 0.8) if owner.team == "ally" else Color(1.0, 0.3, 0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.66, 0.7)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 1.2
	var mesh: Mesh
	match kind:
		"turret":
			var bm := BoxMesh.new(); bm.size = Vector3(0.5, 0.7, 0.5); mesh = bm
		"beacon":
			var cm := CylinderMesh.new(); cm.top_radius = 0.1; cm.bottom_radius = 0.14; cm.height = 0.9; mesh = cm
		"lockdown":
			var cm2 := CylinderMesh.new(); cm2.top_radius = 0.55; cm2.bottom_radius = 0.7; cm2.height = 1.1; mesh = cm2
		"trap":
			var tm := BoxMesh.new(); tm.size = Vector3(1.6, 0.08, 0.08); mesh = tm
		_:
			var sm := SphereMesh.new(); sm.radius = 0.22; sm.height = 0.44; mesh = sm
	mesh.surface_set_material(0, mat) if mesh.get_surface_count() > 0 else null
	mi_dev.mesh = mesh
	mi_dev.position = Vector3(0, 0.35, 0)
	add_child(node)
	node.global_position = pos
	devices.append({ "kind": kind, "pos": pos, "owner": owner, "team": owner.team, "node": node,
		"until": now() + (45.0 if kind == "turret" else (10.0 if kind == "beacon" else 90.0)),
		"arm_at": now() + 8.0 if kind == "lockdown" else 0.0, "hp": 125.0, "next_fire": 0.0 })

func spawn_boom_bot(ent: Node, dir: Vector3) -> void:
	var d2 := Vector3(dir.x, 0, dir.z).normalized()
	var node := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.4, 0.35, 0.5)
	node.mesh = bm
	add_child(node)
	node.global_position = ent.global_position + d2 * 0.8 + Vector3(0, 0.25, 0)
	devices.append({ "kind": "boombot", "pos": node.global_position, "owner": ent, "team": ent.team,
		"node": node, "until": now() + 5.0, "arm_at": 0.0, "hp": 60.0, "next_fire": 0.0, "vel": d2 * 6.5 })

func spawn_drone(ent: Node, dir: Vector3) -> void:
	var node := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.15, 0.5)
	node.mesh = bm
	add_child(node)
	node.global_position = ent.eye_pos() + dir * 1.0
	devices.append({ "kind": "drone", "pos": node.global_position, "owner": ent, "team": ent.team,
		"node": node, "until": now() + 3.6, "arm_at": 0.0, "hp": 40.0, "next_fire": 0.0, "vel": dir * 8.0 })

func _tick_devices(dt: float) -> void:
	for i in range(devices.size() - 1, -1, -1):
		var d: Dictionary = devices[i]
		if now() > d["until"] or d["hp"] <= 0:
			if d["kind"] == "boombot":
				explode(d["owner"], d["pos"], 3.4, 70.0, 30.0)
			if is_instance_valid(d["node"]):
				d["node"].queue_free()
			devices.remove_at(i)
			continue
		match d["kind"]:
			"drone", "boombot":
				d["pos"] += d["vel"] * dt
				if is_instance_valid(d["node"]):
					d["node"].global_position = d["pos"]
				if d["kind"] == "drone":
					if fmod(now(), 0.45) < dt:
						reveal_area(d["pos"], 9.0, d["owner"])
				else:
					for e in combatants():
						if e.alive and e.team != d["team"] and e.global_position.distance_to(d["pos"]) < 2.4:
							d["until"] = 0.0
							break
			"turret":
				if not can_fight():
					continue
				if now() < d["next_fire"]:
					continue
				for e in combatants():
					if not e.alive or e.team == d["team"]:
						continue
					var dist: float = e.global_position.distance_to(d["pos"])
					if dist < 26.0 and has_los(d["pos"] + Vector3(0, 0.8, 0), e.eye_pos(), [e, d.get("owner")]):
						d["next_fire"] = now() + 0.55
						_tracer(d["pos"] + Vector3(0, 0.8, 0), e.eye_pos())
						if randf() < 0.78:
							e.take_damage(7.0, d["owner"], false)
						break
			"trap":
				for e in combatants():
					if e.alive and e.team != d["team"] and e.global_position.distance_to(d["pos"]) < 2.2:
						e.revealed_until = maxf(e.revealed_until, now() + 4.0)
						e.daze_until = maxf(e.daze_until, now() + 2.2)
						e.slow_until = maxf(e.slow_until, now() + 2.2)
						explosion_fx(d["pos"] + Vector3(0, 0.5, 0), 1.2, Color(0.85, 0.82, 0.6))
						sfx.play("flash_pop", player.global_position.distance_to(d["pos"]))
						if e == player:
							hud.dazed(1.5)
						e.take_damage(12.0, d["owner"], false)
						d["until"] = 0.0
						break
			"beacon":
				for e in combatants():
					if e.alive and e.team == d["team"] and e.global_position.distance_to(d["pos"]) < 5.5:
						e.stim_until = maxf(e.stim_until, now() + 0.6)
			"lockdown":
				if d["arm_at"] > 0 and now() >= d["arm_at"]:
					d["until"] = 0.0
					for e in combatants():
						if e.alive and e.team != d["team"] and e.global_position.distance_to(d["pos"]) < 26.0:
							e.suppressed_until = now() + 7.0
							e.daze_until = now() + 7.0
			"nano", "alarm":
				for e in combatants():
					if e.alive and e.team != d["team"] and e.global_position.distance_to(d["pos"]) < 3.2:
						d["until"] = 0.0
						if d["kind"] == "nano":
							spawn_zone(d["owner"], d["pos"], 3.0, 4.0, 40.0)
						else:
							e.daze_until = now() + 2.2
							e.revealed_until = now() + 4.0
						break

# ---------------- 掉落武器（刚体物理） ----------------
func drop_weapon(ent: Node, weapon: Dictionary) -> void:
	var body := RigidBody3D.new()
	body.mass = 2.0
	body.collision_layer = 4
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.12, 0.12, 0.7)
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sh.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.22, 0.26)
	mat.emission_enabled = true
	mat.emission = Color(0.96, 0.77, 0.42)
	mat.emission_energy_multiplier = 0.4
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)
	body.global_position = ent.global_position + Vector3(0, 1.0, 0)
	body.linear_velocity = Vector3(randf_range(-2, 2), 3.0, randf_range(-2, 2))
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	var wrd: WeakRef = weakref(body)
	get_tree().create_timer(20.0).timeout.connect(func():
		var b: Node = wrd.get_ref()
		if b != null:
			for i in range(drops.size() - 1, -1, -1):
				if drops[i]["body"] == b:
					drops.remove_at(i)
			b.queue_free())
	drops.append({ "body": body, "weapon": weapon })

func nearest_drop(pos: Vector3, max_d: float) -> Dictionary:
	var best: Dictionary = {}
	var bd := max_d
	for d in drops:
		if not is_instance_valid(d["body"]):
			continue
		var dist: float = d["body"].global_position.distance_to(pos)
		if dist < bd:
			bd = dist
			best = d
	return best

func take_drop(d: Dictionary) -> Dictionary:
	drops.erase(d)
	if is_instance_valid(d["body"]):
		d["body"].queue_free()
	return d["weapon"]

# ---------------- 死亡布娃娃 ----------------
func spawn_ragdoll(ent: Node, from_dir: Vector3) -> void:
	var body := RigidBody3D.new()
	body.mass = 60.0
	body.collision_layer = 4
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.5
	cs.shape = cap
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.28, 0.32)
	cm.material = mat
	mi.mesh = cm
	body.add_child(mi)
	add_child(body)
	body.global_position = ent.global_position + Vector3(0, 0.9, 0)
	body.apply_impulse(from_dir * 180.0 + Vector3.UP * 100.0)
	var wrr: WeakRef = weakref(body)
	get_tree().create_timer(6.0).timeout.connect(func():
		var b: Node = wrr.get_ref()
		if b != null: b.queue_free())
	body.apply_torque_impulse(Vector3(randf_range(-40, 40), 0, randf_range(-40, 40)))
	var wr8: WeakRef = weakref(body)
	get_tree().create_timer(8.0).timeout.connect(func():
		var b: Node = wr8.get_ref()
		if b != null: b.queue_free())

# ---------------- 粒子 / 特效 ----------------
func spawn_particles(pos: Vector3, color: Color, amount: int, speed: float, life: float) -> void:
	if _fx_live > 36:
		return
	_fx_live += 1
	var p := GPUParticles3D.new()
	p.amount = amount
	p.one_shot = true
	p.lifetime = life
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	pm.color = color
	p.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.09
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = mat
	p.draw_pass_1 = sm
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.4).timeout.connect(func():
		_fx_live -= 1
		if is_instance_valid(p): p.queue_free())

func explosion_fx(pos: Vector3, r: float, color: Color) -> void:
	spawn_particles(pos, color, 36, r * 4.0, 0.6)
	spawn_particles(pos, Color(0.3, 0.3, 0.3), 16, r * 2.0, 1.0)

func explosion_at(pos: Vector3) -> void:
	explosion_fx(pos, 10.0, Color(1.0, 0.5, 0.2))
	for e in combatants():
		if e.alive and e.global_position.distance_to(pos) < 14.0:
			e.take_damage(500.0, null, false)

func spawn_spike_mesh(pos: Vector3) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 0.24, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.2, 0.25)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.3)
	mat.emission_energy_multiplier = 2.0
	bm.material = mat
	m.mesh = bm
	add_child(m)
	m.global_position = pos + Vector3(0, 0.12, 0)
	get_tree().create_timer(50.0).timeout.connect(func(): if is_instance_valid(m): m.queue_free())

func _tracer(from: Vector3, to: Vector3) -> void:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	mi.mesh = im
	mi.material_override = _tracer_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	get_tree().create_timer(0.06).timeout.connect(func(): if is_instance_valid(mi): mi.queue_free())

func clear_round_fx() -> void:
	# 烟雾/伤害区/部署物/掉落武器/投掷物全部清理（对齐网页版 clearRoundFX）
	for sm in smokes:
		if is_instance_valid(sm.get("mesh")): sm["mesh"].queue_free()
		if sm.has("body") and is_instance_valid(sm.get("body")): sm["body"].queue_free()
	smokes.clear()
	for z in zones:
		if is_instance_valid(z.get("mesh")): z["mesh"].queue_free()
	zones.clear()
	for d in devices:
		if is_instance_valid(d.get("node")): d["node"].queue_free()
	devices.clear()
	for d in drops:
		if is_instance_valid(d.get("body")): d["body"].queue_free()
	drops.clear()
	for c in get_children():
		if c is RigidBody3D:
			c.queue_free()

var _trm: StandardMaterial3D = null
func _tracer_mat() -> StandardMaterial3D:
	if _trm == null:
		_trm = StandardMaterial3D.new()
		_trm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trm.albedo_color = Color(1.0, 0.91, 0.63)
	return _trm

func map_rebuild_barriers() -> void:
	map.build_barriers()

# ---------------- 主循环 ----------------
var _dbg_next := 0.0
func _physics_process(dt: float) -> void:
	_t += dt
	if not started:
		return
	# 区域效果
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		if now() > z["until"]:
			if is_instance_valid(z["mesh"]):
				z["mesh"].queue_free()
			zones.remove_at(i)
			continue
		for e in combatants():
			if not e.alive:
				continue
			var d2 := Vector2(e.global_position.x - z["pos"].x, e.global_position.z - z["pos"].z).length()
			if d2 > z["r"] or e.global_position.y > 3.0:
				continue
			var owner = z["owner"]
			if owner != null and is_instance_valid(owner) and "team" in owner and owner.team == e.team:
				if z["heal_owner"] and owner == e:
					e.hp = minf(100.0, e.hp + 13.0 * dt)
				continue
			if z["slow"]:
				e.slow_until = now() + 0.3
			elif z["dps"] > 0:
				e.take_damage(z["dps"] * dt, owner, false)
	# 烟雾过期
	for i in range(smokes.size() - 1, -1, -1):
		var s: Dictionary = smokes[i]
		if now() > s["until"]:
			if is_instance_valid(s["mesh"]):
				s["mesh"].queue_free()
			if is_instance_valid(s["body"]):
				s["body"].queue_free()
			smokes.remove_at(i)
	_tick_devices(dt)
	if OS.get_environment("TP_AUTOSTART") != "" and _t >= _dbg_next:
		_dbg_next = _t + 4.0
		var alive_a := 0
		var alive_e := 0
		for e in combatants():
			if e.alive:
				if e.team == "ally": alive_a += 1
				else: alive_e += 1
		var b0: CharacterBody3D = bots[0]
		var b5: CharacterBody3D = bots[5]
		print("[TP] t=%.0f ph=%s sc=%s al=%d/%d spk=%s | b0=%s(%.0f,%.0f)fin=%s | b5=%s(%.0f,%.0f)fin=%s" % [_t, match_mgr.phase, str(match_mgr.score.values()), alive_a, alive_e, match_mgr.spike_state, b0.state, b0.global_position.x, b0.global_position.z, str(b0.nav_finished()), b5.state, b5.global_position.x, b5.global_position.z, str(b5.nav_finished())])

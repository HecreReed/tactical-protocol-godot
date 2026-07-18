# hud.gd — HUD：血条/弹药/技能/金钱/计时/比分/小地图/击杀条/记分板/战斗报告/买卖菜单/闪光遮罩
extends CanvasLayer

const Weapons := preload("res://scripts/weapons.gd")
const Ab := preload("res://scripts/abilities.gd")

var main: Node3D
var hp_label: Label
var ammo_label: Label
var money_label: Label
var clock_label: Label
var score_label: Label
var banner_label: Label
var util_label: Label
var crosshair: Control
var buy_panel: PanelContainer
var buy_open := false
var banner_until := 0.0
var vignette: ColorRect
var flash_rect: ColorRect
var smoke_rect: ColorRect
var minimap: Control
var killfeed: VBoxContainer
var board: PanelContainer
var report_label: Label
var bought_this_round: Array = []

func setup(m: Node3D) -> void:
	main = m
	layer = 5
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair.bind(crosshair))
	add_child(crosshair)

	hp_label = _mk_label(Vector2(24, -70), 30, Control.PRESET_BOTTOM_LEFT)
	money_label = _mk_label(Vector2(24, -120), 22, Control.PRESET_BOTTOM_LEFT)
	money_label.add_theme_color_override("font_color", Color(0.96, 0.77, 0.42))
	ammo_label = _mk_label(Vector2(-280, -70), 30, Control.PRESET_BOTTOM_RIGHT)
	clock_label = _mk_label(Vector2(-60, 14), 26, Control.PRESET_CENTER_TOP)
	score_label = _mk_label(Vector2(-160, 52), 18, Control.PRESET_CENTER_TOP)
	banner_label = _mk_label(Vector2(-320, 190), 40, Control.PRESET_CENTER_TOP)
	util_label = _mk_label(Vector2(-220, -56), 17, Control.PRESET_CENTER_BOTTOM)

	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash_rect)
	smoke_rect = ColorRect.new()
	smoke_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	smoke_rect.color = Color(0.85, 0.88, 0.92, 0)
	smoke_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(smoke_rect)
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(1, 0.1, 0.15, 0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	minimap = Control.new()
	minimap.position = Vector2(12, 12)
	minimap.custom_minimum_size = Vector2(210, 210)
	minimap.size = Vector2(210, 210)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap.bind(minimap))
	add_child(minimap)

	killfeed = VBoxContainer.new()
	killfeed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	killfeed.position = Vector2(-360, 14)
	add_child(killfeed)

	report_label = _mk_label(Vector2(-330, 120), 15, Control.PRESET_TOP_RIGHT)

	board = PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_CENTER)
	board.visible = false
	var bl := Label.new()
	bl.name = "body"
	board.add_child(bl)
	add_child(board)

	_build_buy()

func _mk_label(pos: Vector2, size: int, preset: int) -> Label:
	var l := Label.new()
	l.set_anchors_preset(preset)
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	return l

# ---------------- 买卖菜单（右键出售，同回合全额退款） ----------------
func _build_buy() -> void:
	buy_panel = PanelContainer.new()
	buy_panel.position = Vector2(60, 60)
	buy_panel.visible = false
	var v := VBoxContainer.new()
	buy_panel.add_child(v)
	var title := Label.new()
	title.text = "购买（左键买 · 右键卖回 · B 关闭）"
	v.add_child(title)
	for id in Weapons.BUY_ORDER:
		var def: Dictionary = Weapons.LIST[id]
		var btn := Button.new()
		btn.text = "%s — $%d" % [def["name"], def["cost"]]
		btn.gui_input.connect(_buy_input.bind(id))
		v.add_child(btn)
	var armor_l := Button.new()
	armor_l.text = "轻甲 +25 — $400"
	armor_l.gui_input.connect(_armor_input.bind(false))
	v.add_child(armor_l)
	var armor_h := Button.new()
	armor_h.text = "重甲 +50 — $1000"
	armor_h.gui_input.connect(_armor_input.bind(true))
	v.add_child(armor_h)
	for k in ["c", "q"]:
		var btn2 := Button.new()
		btn2.name = "ab_" + k
		btn2.gui_input.connect(_ability_input.bind(k))
		v.add_child(btn2)
	add_child(buy_panel)

func _buy_input(ev: InputEvent, id: String) -> void:
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	var p = main.player
	var def: Dictionary = Weapons.LIST[id]
	if ev.button_index == MOUSE_BUTTON_LEFT:
		var refund := 0
		if p.primary.size() > 0 and def["cat"] != "pistol" and bought_this_round.has(p.primary["id"]):
			refund = p.primary["def"]["cost"]
		if p.money + refund < def["cost"]:
			return
		p.money += refund - def["cost"]
		bought_this_round.append(id)
		if def["cat"] == "pistol":
			p.secondary = Weapons.make(id)
			if p.slot == "secondary": p.weapon = p.secondary
		else:
			p.primary = Weapons.make(id)
			p.weapon = p.primary
			p.slot = "primary"
	elif ev.button_index == MOUSE_BUTTON_RIGHT:
		# 卖回本回合购买的武器
		if not bought_this_round.has(id):
			return
		if p.primary.size() > 0 and p.primary["id"] == id:
			p.money = mini(9000, p.money + def["cost"])
			p.primary = {}
			bought_this_round.erase(id)
			p.weapon = p.secondary
			p.slot = "secondary"
		elif p.secondary["id"] == id:
			p.money = mini(9000, p.money + def["cost"])
			p.secondary = Weapons.make("classic")
			bought_this_round.erase(id)
			if p.slot == "secondary": p.weapon = p.secondary

func _armor_input(ev: InputEvent, heavy: bool) -> void:
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	var p = main.player
	var cost := 1000 if heavy else 400
	var val := 50 if heavy else 25
	if ev.button_index == MOUSE_BUTTON_LEFT:
		if p.money < cost or p.armor >= val:
			return
		p.money -= cost
		p.armor = val
		p.armor_bought_round = main.match_mgr.round_no
	elif ev.button_index == MOUSE_BUTTON_RIGHT and p.armor_bought_round == main.match_mgr.round_no:
		p.money = mini(9000, p.money + (1000 if p.armor == 50 else 400))
		p.armor = 0
		p.armor_bought_round = -1

func _ability_input(ev: InputEvent, k: String) -> void:
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	var p = main.player
	var sl: Dictionary = p.ability_slots[k]
	var def: Dictionary = sl["def"]
	if ev.button_index == MOUSE_BUTTON_LEFT:
		if sl["n"] >= def.get("max", 1) or p.money < def["cost"]:
			return
		p.money -= def["cost"]
		sl["n"] += 1
	elif ev.button_index == MOUSE_BUTTON_RIGHT and sl["n"] > 0 and def["cost"] > 0:
		sl["n"] -= 1
		p.money = mini(9000, p.money + def["cost"])

func toggle_buy() -> void:
	if main.match_mgr.phase != "buy":
		buy_panel.visible = false
		return
	buy_open = not buy_open
	buy_panel.visible = buy_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if buy_open else Input.MOUSE_MODE_CAPTURED

func on_round_start() -> void:
	bought_this_round.clear()

# ---------------- 反馈 ----------------
func _draw_crosshair(c: Control) -> void:
	var ctr := c.size / 2.0
	var col := Color(0.25, 0.88, 0.85)
	for off: Vector2 in [Vector2(0, -10), Vector2(0, 4), Vector2(-10, 0), Vector2(4, 0)]:
		var a: Vector2 = ctr + off
		var b: Vector2 = a + (Vector2(0, 6) if off.x == 0 else Vector2(6, 0))
		c.draw_line(a, b, col, 2.0)

func damaged() -> void:
	vignette.color.a = 0.35

func flashed(dur: float) -> void:
	flash_rect.color.a = 0.96

func dazed(dur: float) -> void:
	flash_rect.color.a = 0.35

func kill_msg(txt: String) -> void:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	killfeed.add_child(l)
	get_tree().create_timer(4.5).timeout.connect(func(): if is_instance_valid(l): l.queue_free())

func banner(text: String) -> void:
	banner_label.text = text
	banner_until = main.now() + 2.5

func match_over(won: bool) -> void:
	banner_label.text = "胜 利" if won else "失 败"
	banner_until = main.now() + 9999.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_board(show: bool) -> void:
	board.visible = show
	if not show:
		return
	var txt := "特工        K / D\n--------------------\n"
	for e in main.combatants():
		var nm: String = e.agent_name if "agent_name" in e else Ab.AGENTS[e.agent_id]["name"] + "（你）"
		txt += "%s  [%s]   %d / %d\n" % [nm, "我方" if e.team == "ally" else "敌方", e.kills, e.deaths]
	(board.get_node("body") as Label).text = txt

# ---------------- 小地图 ----------------
func _draw_minimap(c: Control) -> void:
	var w: float = c.size.x
	var world: float = main.map.world_size
	var k := w / world
	c.draw_rect(Rect2(0, 0, w, w), Color(0.03, 0.06, 0.09, 0.85))
	for r in main.map.md["open"]:
		c.draw_rect(Rect2((r[0] + world / 2) * k, (r[1] + world / 2) * k, (r[2] - r[0]) * k, (r[3] - r[1]) * k), Color(0.16, 0.22, 0.27))
	for key in main.map.sites.keys():
		var pl: Vector3 = main.map.sites[key]["plant"]
		c.draw_circle(Vector2((pl.x + world / 2) * k, (pl.z + world / 2) * k), 4, Color(0.5, 0.82, 0.83, 0.6))
	for e in main.combatants():
		if not e.alive:
			continue
		var pos := Vector2((e.global_position.x + world / 2) * k, (e.global_position.z + world / 2) * k)
		if e == main.player:
			c.draw_circle(pos, 4, Color.WHITE)
		elif e.team == main.player.team:
			c.draw_circle(pos, 3, Color(0.25, 0.85, 0.8))
		elif main.now() < e.revealed_until or main.has_los(main.player.eye_pos(), e.eye_pos(), [main.player, e]):
			c.draw_circle(pos, 3, Color(1.0, 0.3, 0.35))
	if main.match_mgr.spike_state != "carried":
		var sp: Vector3 = main.match_mgr.spike_pos
		c.draw_circle(Vector2((sp.x + world / 2) * k, (sp.z + world / 2) * k), 4, Color(1, 0.25, 0.3))

# ---------------- 每帧 ----------------
func _process(dt: float) -> void:
	if main == null or main.player == null:
		return
	var p = main.player
	var mm = main.match_mgr
	hp_label.text = "HP %d  |  甲 %d" % [maxi(0, int(p.hp)), p.armor]
	var w: Dictionary = p.weapon
	var extra := ""
	if p.knife_ult > 0: extra = "  锋刃×%d" % p.knife_ult
	if p.rocket_ult > 0: extra = "  火箭×%d" % p.rocket_ult
	ammo_label.text = "%s  %d/%d%s%s" % [w["def"]["name"], w["ammo"], w["reserve"], "  换弹…" if w["reload_end"] > 0 else "", extra]
	money_label.text = "$ %d" % p.money
	var sl: Dictionary = p.ability_slots
	var a: Dictionary = Ab.AGENTS[p.agent_id]
	util_label.text = "C %s×%d  Q %s×%d  E %s×%d  X %s %d/%d" % [
		sl["c"]["def"]["name"], sl["c"]["n"], sl["q"]["def"]["name"], sl["q"]["n"],
		sl["e"]["def"]["name"], sl["e"]["n"], a["x"]["name"], p.ult_points, a["ult_cost"]]
	var t: float = 0.0
	match mm.phase:
		"buy": t = mm.t_phase - main.now()
		"live": t = mm.t_phase - main.now()
		"planted": t = mm.explode_at - main.now()
	clock_label.text = "%s %d:%02d" % [{"buy": "购买", "live": "", "planted": "⚠", "end": "—", "over": ""}.get(mm.phase, ""), int(maxf(0, t)) / 60, int(maxf(0, t)) % 60]
	score_label.text = "我方 %d : %d 敌方   回合 %d   [%s]" % [mm.score["ally"], mm.score["enemy"], mm.round_no, "进攻" if mm.ally_side == "atk" else "防守"]
	banner_label.visible = main.now() < banner_until
	vignette.color.a = move_toward(vignette.color.a, 0, dt * 1.4)
	flash_rect.color.a = move_toward(flash_rect.color.a, 0, dt * 0.9)
	smoke_rect.color.a = 0.97 if main.in_smoke(p.eye_pos()) else 0.0
	report_label.text = mm.report_text if mm.phase == "buy" else ""
	crosshair.queue_redraw()
	minimap.queue_redraw()

# hud.gd — HUD：血量/弹药/金钱/计时/比分/横幅/准星/买枪菜单
extends CanvasLayer

const Weapons := preload("res://scripts/weapons.gd")

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

func setup(m: Node3D) -> void:
	main = m
	layer = 5
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.draw.connect(_draw_crosshair.bind(crosshair))
	add_child(crosshair)

	hp_label = _mk_label(Vector2(24, -60), 30)
	hp_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ammo_label = _mk_label(Vector2(-220, -60), 30)
	ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	money_label = _mk_label(Vector2(24, -110), 22)
	money_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	money_label.add_theme_color_override("font_color", Color(0.96, 0.77, 0.42))
	clock_label = _mk_label(Vector2(-60, 16), 26)
	clock_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	score_label = _mk_label(Vector2(-120, 50), 18)
	score_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_label = _mk_label(Vector2(-300, 200), 40)
	banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	util_label = _mk_label(Vector2(-140, -60), 18)
	util_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(1, 0.1, 0.15, 0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)

	buy_panel = PanelContainer.new()
	buy_panel.position = Vector2(80, 80)
	buy_panel.visible = false
	var v := VBoxContainer.new()
	buy_panel.add_child(v)
	var title := Label.new()
	title.text = "购买（点击 / B 关闭）"
	v.add_child(title)
	for id in Weapons.BUY_ORDER:
		var btn := Button.new()
		var def: Dictionary = Weapons.LIST[id]
		btn.text = "%s — $%d" % [def["name"], def["cost"]]
		btn.pressed.connect(_buy.bind(id))
		v.add_child(btn)
	add_child(buy_panel)

func _mk_label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	add_child(l)
	return l

func _draw_crosshair(c: Control) -> void:
	var ctr := c.size / 2.0
	var col := Color(0.25, 0.88, 0.85)
	for off: Vector2 in [Vector2(0, -10), Vector2(0, 4), Vector2(-10, 0), Vector2(4, 0)]:
		var a: Vector2 = ctr + off
		var b: Vector2 = a + (Vector2(0, 6) if off.x == 0 else Vector2(6, 0))
		c.draw_line(a, b, col, 2.0)

func flash_crosshair() -> void:
	pass

func damaged() -> void:
	vignette.color.a = 0.35

func toggle_buy() -> void:
	if main.match_mgr.phase != "buy":
		buy_panel.visible = false
		return
	buy_open = not buy_open
	buy_panel.visible = buy_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if buy_open else Input.MOUSE_MODE_CAPTURED

func _buy(id: String) -> void:
	var def: Dictionary = Weapons.LIST[id]
	var p = main.player
	if p.money < def["cost"]:
		return
	p.money -= def["cost"]
	if def["cat"] == "pistol":
		p.secondary = Weapons.make(id)
		if p.slot == "secondary":
			p.weapon = p.secondary
	else:
		main.primary_weapon = Weapons.make(id)
		p.weapon = main.primary_weapon
		p.slot = "primary"

func banner(text: String) -> void:
	banner_label.text = text
	banner_until = main.now() + 2.5

func match_over(won: bool) -> void:
	banner_label.text = "胜 利" if won else "失 败"
	banner_until = main.now() + 9999.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(dt: float) -> void:
	if main == null or main.player == null:
		return
	var p = main.player
	var mm = main.match_mgr
	hp_label.text = "HP %d  |  甲 %d" % [maxi(0, int(p.hp)), p.armor]
	var w: Dictionary = p.weapon
	var rl := "  换弹中…" if w["reload_end"] > 0 else ""
	ammo_label.text = "%s  %d / %d%s" % [w["def"]["name"], w["ammo"], w["reserve"], rl]
	money_label.text = "$ %d" % p.money
	util_label.text = "C 烟雾 ×%d   Q 闪光 ×%d" % [p.smoke_charges, p.flash_charges]
	var t: float = 0.0
	match mm.phase:
		"buy": t = mm.t_phase - main.now()
		"live": t = mm.t_phase - main.now()
		"planted": t = mm.explode_at - main.now()
	clock_label.text = "%s %d:%02d" % [{"buy":"购买","live":"","planted":"⚠","end":"—","over":""}.get(mm.phase, ""), int(maxf(0, t)) / 60, int(maxf(0, t)) % 60]
	score_label.text = "我方 %d : %d 敌方   回合 %d   [%s]" % [mm.score["ally"], mm.score["enemy"], mm.round_no, "进攻" if mm.ally_side == "atk" else "防守"]
	banner_label.visible = main.now() < banner_until
	vignette.color.a = move_toward(vignette.color.a, 0, dt * 1.4)
	crosshair.queue_redraw()

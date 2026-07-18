# hud.gd — HUD（1:1 复刻网页版 Valorant 风格）：
# 顶部比分/时钟/存活点 · 左下血甲面板 · 右下弹药面板 · 底部技能格 · 小地图 · 击杀条 · 记分板 · 战斗报告 · 购买菜单 · 观战提示
extends CanvasLayer

const Weapons := preload("res://scripts/weapons.gd")
const Ab := preload("res://scripts/abilities.gd")
const Icons := preload("res://scripts/icons.gd")

const C_RED := Color8(0xff, 0x46, 0x55)
const C_TEAL := Color8(0x39, 0xd0, 0xc9)
const C_BG := Color8(0x0f, 0x19, 0x23)
const C_PANEL := Color(0.059, 0.098, 0.137, 0.86)
const C_WHITE := Color8(0xec, 0xe8, 0xe1)
const C_GOLD := Color8(0xf5, 0xc5, 0x6b)
const C_DIM := Color8(0x8b, 0x97, 0x8f)
const C_BORDER := Color8(0x24, 0x33, 0x3f)
const C_ITEM_BG := Color8(0x14, 0x1f, 0x2a)

var main: Node3D
var buy_open := false
var banner_until := 0.0
var bought_this_round: Array = []

var score_ally_l: Label
var score_enemy_l: Label
var round_l: Label
var clock_l: Label
var side_l: Label
var dots_ally: HBoxContainer
var dots_enemy: HBoxContainer
var spike_tag: PanelContainer
var hp_num: Label
var armor_num: Label
var hp_bar: ColorRect
var armor_bar: ColorRect
var money_l: Label
var ult_l: Label
var ammo_num: Label
var weap_name: Label
var slot_ls: Array = []
var ability_box: HBoxContainer
var banner_big: Label
var banner_sub: Label
var spec_l: Label
var crosshair: Control
var vignette: ColorRect
var flash_rect: ColorRect
var smoke_rect: ColorRect
var minimap: Control
var killfeed: VBoxContainer
var board: PanelContainer
var board_body: Label
var report_panel: PanelContainer
var report_l: Label
var buy_panel: Control
var player_panels: Array = []
var pause_panel: PanelContainer
var pause_open := false
var lock_hint: Control
var buy_money_l: Label
var buy_grid_holder: VBoxContainer

# ---------------- 样式工具 ----------------
static func _sb(bg: Color, border: Color = Color.TRANSPARENT, bw: int = 0, side: String = "all") -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	if bw > 0:
		s.border_color = border
		match side:
			"left": s.border_width_left = bw
			"right": s.border_width_right = bw
			"bottom": s.border_width_bottom = bw
			_: s.set_border_width_all(bw)
	return s

func _lbl(parent: Node, size: int, col: Color = C_WHITE, text: String = "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)
	return l

func setup(m: Node3D) -> void:
	main = m
	layer = 5

	# ---- 准星 / 遮罩 ----
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair.bind(crosshair))
	add_child(crosshair)
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

	# ---- 顶栏：比分 + 时钟 + 存活点 ----
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.position = Vector2(-160, 8)
	top.add_theme_constant_override("separation", 14)
	add_child(top)
	var av := VBoxContainer.new()
	top.add_child(av)
	var ap := PanelContainer.new()
	ap.add_theme_stylebox_override("panel", _sb(C_PANEL, C_TEAL, 3, "bottom"))
	av.add_child(ap)
	score_ally_l = Label.new()
	score_ally_l.text = "0"
	score_ally_l.add_theme_font_size_override("font_size", 30)
	score_ally_l.add_theme_color_override("font_color", C_TEAL)
	score_ally_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_ally_l.custom_minimum_size = Vector2(64, 0)
	ap.add_child(score_ally_l)
	dots_ally = HBoxContainer.new()
	dots_ally.add_theme_constant_override("separation", 4)
	dots_ally.alignment = BoxContainer.ALIGNMENT_CENTER
	av.add_child(dots_ally)
	var cv := VBoxContainer.new()
	top.add_child(cv)
	var cp := PanelContainer.new()
	cp.add_theme_stylebox_override("panel", _sb(C_PANEL, Color8(0x3a, 0x4a, 0x55), 3, "bottom"))
	cv.add_child(cp)
	var cvv := VBoxContainer.new()
	cp.add_child(cvv)
	round_l = _lbl(cvv, 11, C_DIM, "回合 1")
	round_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_l = _lbl(cvv, 26, C_WHITE, "1:40")
	clock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_l.custom_minimum_size = Vector2(104, 0)
	side_l = _lbl(cv, 11, C_GOLD, "进攻方")
	side_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ev := VBoxContainer.new()
	top.add_child(ev)
	var ep := PanelContainer.new()
	ep.add_theme_stylebox_override("panel", _sb(C_PANEL, C_RED, 3, "bottom"))
	ev.add_child(ep)
	score_enemy_l = Label.new()
	score_enemy_l.text = "0"
	score_enemy_l.add_theme_font_size_override("font_size", 30)
	score_enemy_l.add_theme_color_override("font_color", C_RED)
	score_enemy_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_enemy_l.custom_minimum_size = Vector2(64, 0)
	ep.add_child(score_enemy_l)
	dots_enemy = HBoxContainer.new()
	dots_enemy.add_theme_constant_override("separation", 4)
	dots_enemy.alignment = BoxContainer.ALIGNMENT_CENTER
	ev.add_child(dots_enemy)
	for i in range(5):
		dots_ally.add_child(_mk_dot(C_TEAL))
		dots_enemy.add_child(_mk_dot(C_RED))

	spike_tag = PanelContainer.new()
	spike_tag.set_anchors_preset(Control.PRESET_CENTER_TOP)
	spike_tag.position = Vector2(-80, 76)
	spike_tag.add_theme_stylebox_override("panel", _sb(C_PANEL, C_RED, 1))
	spike_tag.visible = false
	var stl := _lbl(spike_tag, 13, C_RED, "SPIKE 已安放")
	add_child(spike_tag)

	# ---- 左下：血量 / 护甲 ----
	var hp_panel := PanelContainer.new()
	hp_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hp_panel.position = Vector2(26, -108)
	hp_panel.add_theme_stylebox_override("panel", _sb(C_PANEL, C_TEAL, 3, "left"))
	add_child(hp_panel)
	var hv := VBoxContainer.new()
	hv.custom_minimum_size = Vector2(210, 0)
	hp_panel.add_child(hv)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 10)
	hv.add_child(hr)
	hp_num = _lbl(hr, 38, C_WHITE, "100")
	armor_num = _lbl(hr, 20, Color8(0x9f, 0xb6, 0xc6), "甲 0")
	var hb_bg := ColorRect.new()
	hb_bg.color = C_BORDER
	hb_bg.custom_minimum_size = Vector2(0, 5)
	hv.add_child(hb_bg)
	hp_bar = ColorRect.new()
	hp_bar.color = C_WHITE
	hb_bg.add_child(hp_bar)
	hp_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	var ab_bg := ColorRect.new()
	ab_bg.color = C_BORDER
	ab_bg.custom_minimum_size = Vector2(0, 5)
	hv.add_child(ab_bg)
	armor_bar = ColorRect.new()
	armor_bar.color = Color8(0x9f, 0xb6, 0xc6)
	ab_bg.add_child(armor_bar)
	armor_bar.set_anchors_preset(Control.PRESET_FULL_RECT)

	var money_p := PanelContainer.new()
	money_p.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	money_p.position = Vector2(26, -156)
	money_p.add_theme_stylebox_override("panel", _sb(C_PANEL))
	add_child(money_p)
	money_l = _lbl(money_p, 22, C_GOLD, "¥ 800")
	var ult_p := PanelContainer.new()
	ult_p.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ult_p.position = Vector2(26, -196)
	ult_p.add_theme_stylebox_override("panel", _sb(C_PANEL))
	add_child(ult_p)
	ult_l = _lbl(ult_p, 13, C_DIM, "大招点数 0/7")

	# ---- 右下：弹药 ----
	var ammo_p := PanelContainer.new()
	ammo_p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_p.position = Vector2(-236, -128)
	ammo_p.add_theme_stylebox_override("panel", _sb(C_PANEL, C_RED, 3, "right"))
	add_child(ammo_p)
	var av2 := VBoxContainer.new()
	av2.custom_minimum_size = Vector2(190, 0)
	ammo_p.add_child(av2)
	ammo_num = _lbl(av2, 38, C_WHITE, "12 / 36")
	ammo_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weap_name = _lbl(av2, 13, C_DIM, "CLASSIC")
	weap_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	player_panels.append(hp_panel)
	player_panels.append(money_p)
	player_panels.append(ult_p)
	player_panels.append(ammo_p)
	var slots_h := HBoxContainer.new()
	slots_h.alignment = BoxContainer.ALIGNMENT_END
	slots_h.add_theme_constant_override("separation", 8)
	av2.add_child(slots_h)
	for txt in ["1 主武器", "2 副武器", "3 近战"]:
		var sp := PanelContainer.new()
		sp.add_theme_stylebox_override("panel", _sb(Color8(0x18, 0x24, 0x2e), C_BORDER, 1))
		var sl := _lbl(sp, 11, C_DIM, txt)
		slots_h.add_child(sp)
		slot_ls.append(sl)

	# ---- 底部中央：技能格 ----
	ability_box = HBoxContainer.new()
	ability_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ability_box.position = Vector2(-130, -80)
	ability_box.add_theme_constant_override("separation", 10)
	add_child(ability_box)

	# ---- 横幅 / 观战提示 ----
	var bv := VBoxContainer.new()
	bv.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bv.position = Vector2(-320, 190)
	bv.custom_minimum_size = Vector2(640, 0)
	add_child(bv)
	banner_big = _lbl(bv, 46, C_WHITE)
	banner_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_big.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	banner_big.add_theme_constant_override("outline_size", 10)
	banner_sub = _lbl(bv, 15, C_DIM)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spec_l = _lbl(self, 15, C_WHITE)
	spec_l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	spec_l.position = Vector2(-160, -140)
	spec_l.custom_minimum_size = Vector2(320, 0)
	spec_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spec_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	spec_l.add_theme_constant_override("outline_size", 6)

	# ---- 小地图 ----
	var mm_p := PanelContainer.new()
	mm_p.position = Vector2(10, 10)
	mm_p.add_theme_stylebox_override("panel", _sb(C_PANEL, C_BORDER, 1))
	add_child(mm_p)
	minimap = Control.new()
	minimap.custom_minimum_size = Vector2(210, 210)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap.bind(minimap))
	mm_p.add_child(minimap)

	# ---- 击杀条 ----
	killfeed = VBoxContainer.new()
	killfeed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	killfeed.position = Vector2(-320, 12)
	killfeed.add_theme_constant_override("separation", 4)
	killfeed.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(killfeed)

	# ---- 战斗报告 ----
	report_panel = PanelContainer.new()
	report_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	report_panel.position = Vector2(-274, 170)
	report_panel.add_theme_stylebox_override("panel", _sb(C_PANEL, C_GOLD, 3, "right"))
	report_panel.visible = false
	add_child(report_panel)
	report_l = _lbl(report_panel, 12, C_WHITE)
	report_l.custom_minimum_size = Vector2(250, 0)

	# ---- 记分板 ----
	board = PanelContainer.new()
	board.set_anchors_preset(Control.PRESET_CENTER_TOP)
	board.position = Vector2(-320, 100)
	board.add_theme_stylebox_override("panel", _sb(Color(0.039, 0.067, 0.094, 0.95), C_BORDER, 1))
	board.visible = false
	add_child(board)
	board_body = _lbl(board, 14, C_WHITE)
	board_body.custom_minimum_size = Vector2(640, 0)

	_build_buy()
	_build_pause()
	_build_lock_hint()

func _mk_dot(col: Color) -> ColorRect:
	var d := ColorRect.new()
	d.color = col
	d.custom_minimum_size = Vector2(9, 14)
	return d

# ---------------- 购买菜单（复刻网页版：分类网格 + 拥有/买不起态 + 右栏护甲技能说明） ----------------
func _build_buy() -> void:
	buy_panel = PanelContainer.new()
	buy_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	(buy_panel as PanelContainer).add_theme_stylebox_override("panel", _sb(Color(0.039, 0.067, 0.094, 0.96), C_BORDER, 1))
	buy_panel.set_offsets_preset(Control.PRESET_FULL_RECT)
	buy_panel.offset_left = 100
	buy_panel.offset_right = -100
	buy_panel.offset_top = 50
	buy_panel.offset_bottom = -50
	buy_panel.visible = false
	add_child(buy_panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	buy_panel.add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := _lbl(head, 22, C_WHITE, "购买阶段")
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	buy_money_l = _lbl(head, 24, C_GOLD, "¥ 800")
	var close_l := _lbl(head, 13, C_DIM, "   关闭 [B]")
	buy_grid_holder = VBoxContainer.new()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	buy_grid_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(buy_grid_holder)

func _refresh_buy() -> void:
	for c in buy_grid_holder.get_children():
		c.queue_free()
	var p = main.player
	buy_money_l.text = "¥ %d" % p.money
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buy_grid_holder.add_child(cols)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.5
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var cats := [["pistol", "副武器"], ["smg", "冲锋枪"], ["shotgun", "霰弹枪"], ["rifle", "步枪"], ["sniper", "狙击枪"], ["heavy", "重机枪"]]
	for cd in cats:
		var h := _lbl(left, 12, C_DIM, cd[1])
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		left.add_child(grid)
		for id in Weapons.BUY_ORDER:
			var def: Dictionary = Weapons.LIST[id]
			if def["cat"] != cd[0]:
				continue
			var owned: bool = (def["cat"] == "pistol" and p.secondary.size() > 0 and p.secondary["id"] == id) \
				or (def["cat"] != "pistol" and p.primary.size() > 0 and p.primary["id"] == id)
			grid.add_child(_buy_item(def["name"], "¥ %d" % def["cost"], owned, p.money < def["cost"], _buy_input, id))
	_lbl(right, 12, C_DIM, "护甲")
	var agrid := GridContainer.new()
	agrid.columns = 2
	agrid.add_theme_constant_override("h_separation", 6)
	right.add_child(agrid)
	agrid.add_child(_buy_item("轻型护甲 +25", "¥ 400", p.armor >= 25, p.money < 400, _armor_input, false))
	agrid.add_child(_buy_item("重型护甲 +50", "¥ 1000", p.armor >= 50, p.money < 1000, _armor_input, true))
	var a: Dictionary = Ab.AGENTS[p.agent_id]
	_lbl(right, 12, C_DIM, "技能 — %s" % a["name"])
	var abgrid := GridContainer.new()
	abgrid.columns = 1
	abgrid.add_theme_constant_override("v_separation", 6)
	right.add_child(abgrid)
	for k in ["c", "q"]:
		var sl: Dictionary = p.ability_slots[k]
		var d: Dictionary = sl["def"]
		var full: bool = sl["n"] >= d.get("max", 1)
		abgrid.add_child(_buy_item("[%s] %s (%d/%d)" % [k.to_upper(), d["name"], sl["n"], d.get("max", 1)], "¥ %d" % d["cost"], full, p.money < d["cost"], _ability_input, k))
	_lbl(right, 12, C_DIM, "说明")
	var info := _lbl(right, 12, C_DIM, "左键购买 · 右键出售本回合购买（全额退款）\n经济：击杀 +200 · 胜利 +3000\n连败补偿 · 存活保留装备\n购买阶段结束自动开局")
	info.add_theme_color_override("font_color", C_DIM)

func _buy_item(nm: String, price: String, owned: bool, noafford: bool, handler: Callable, arg) -> PanelContainer:
	var item := PanelContainer.new()
	var sb := _sb(Color8(0x14, 0x1f, 0x2a) if not owned else Color8(0x18, 0x28, 0x35), C_TEAL if owned else C_BORDER, 1)
	item.add_theme_stylebox_override("panel", sb)
	item.custom_minimum_size = Vector2(150, 0)
	var v := VBoxContainer.new()
	item.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var nl := _lbl(top, 14, C_WHITE if not noafford or owned else Color(C_WHITE.r, C_WHITE.g, C_WHITE.b, 0.4), nm)
	if owned:
		var og := Control.new()
		og.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(og)
		_lbl(top, 10, C_TEAL, "已装备")
	var pl := _lbl(v, 12, C_GOLD if not noafford or owned else Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, 0.4), price)
	item.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			handler.call(ev, arg))
	item.mouse_filter = Control.MOUSE_FILTER_STOP
	return item

func _buy_input(ev: InputEvent, id: String) -> void:
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
	_refresh_buy()

func _armor_input(ev: InputEvent, heavy: bool) -> void:
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
	_refresh_buy()

func _ability_input(ev: InputEvent, k: String) -> void:
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
	_refresh_buy()

func toggle_buy() -> void:
	if main.match_mgr.phase != "buy":
		buy_panel.visible = false
		return
	buy_open = not buy_open
	buy_panel.visible = buy_open
	if buy_open:
		_refresh_buy()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if buy_open else Input.MOUSE_MODE_CAPTURED

func on_round_start() -> void:
	bought_this_round.clear()
	if buy_open:
		_refresh_buy()

# ---------------- 暂停 / 设置（复刻网页版设置面板） ----------------
func _build_pause() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-260, -220)
	pause_panel.add_theme_stylebox_override("panel", _sb(Color(0.039, 0.067, 0.094, 0.97), C_BORDER, 1))
	pause_panel.visible = false
	add_child(pause_panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(520, 0)
	v.add_theme_constant_override("separation", 14)
	pause_panel.add_child(v)
	var title := _lbl(v, 20, C_WHITE, "设 置")
	_mk_slider(v, "灵敏度", 0.2, 3.0, 1.0, func(val): main.player.sens_mult = val)
	_mk_slider(v, "视野 FOV", 60.0, 100.0, 71.0, func(val): main.player.fov_base = val)
	_mk_slider(v, "音量", 0.0, 1.0, 0.8, func(val): main.sfx.volume = val)
	var dr := HBoxContainer.new()
	dr.add_theme_constant_override("separation", 6)
	v.add_child(dr)
	var dl := _lbl(dr, 13, C_DIM, "AI 难度  ")
	for d in [["新手", 0.55], ["常规", 0.8], ["困难", 1.0], ["天梯", 1.25]]:
		var b := Button.new()
		b.text = d[0]
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_stylebox_override("normal", _sb(C_ITEM_BG, C_BORDER, 1))
		b.add_theme_stylebox_override("hover", _sb(C_ITEM_BG, C_TEAL, 1))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): main.difficulty = d[1])
		dr.add_child(b)
	var closeb := Button.new()
	closeb.text = "保 存 并 关 闭"
	closeb.add_theme_font_size_override("font_size", 14)
	closeb.add_theme_color_override("font_color", Color8(0x06, 0x22, 0x2a))
	closeb.add_theme_stylebox_override("normal", _sb(C_TEAL, C_TEAL, 1))
	closeb.pressed.connect(func(): toggle_pause())
	v.add_child(closeb)

func _mk_slider(parent: Node, name_txt: String, mn: float, mx: float, val: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var l := _lbl(row, 13, C_DIM, name_txt)
	l.custom_minimum_size = Vector2(90, 0)
	var sl := HSlider.new()
	sl.min_value = mn
	sl.max_value = mx
	sl.step = 0.05 if mx <= 3.0 else 1.0
	sl.value = val
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(0, 24)
	row.add_child(sl)
	var vl := _lbl(row, 13, C_GOLD, str(val))
	vl.custom_minimum_size = Vector2(52, 0)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sl.value_changed.connect(func(nv):
		vl.text = ("%.2f" % nv) if mx <= 3.0 else str(int(nv))
		on_change.call(nv))

func toggle_pause() -> void:
	if buy_open:
		toggle_buy()
		return
	pause_open = not pause_open
	pause_panel.visible = pause_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if pause_open else Input.MOUSE_MODE_CAPTURED
	if not pause_open:
		lock_hint.visible = false

# ---------------- 点击回场（web 指针锁丢失兜底） ----------------
func _build_lock_hint() -> void:
	lock_hint = Control.new()
	lock_hint.set_anchors_preset(Control.PRESET_FULL_RECT)
	lock_hint.visible = false
	add_child(lock_hint)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.06, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	lock_hint.add_child(dim)
	var btn := Button.new()
	btn.text = "点 击 进 入 战 场"
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_stylebox_override("normal", _sb(C_PANEL, C_TEAL, 1))
	btn.add_theme_stylebox_override("hover", _sb(Color8(0x18, 0x28, 0x35), C_TEAL, 1))
	btn.set_anchors_preset(Control.PRESET_CENTER)
	btn.position = Vector2(-140, -30)
	btn.pressed.connect(func():
		lock_hint.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	lock_hint.add_child(btn)
func _draw_crosshair(c: Control) -> void:
	if main != null and main.player != null and not main.player.alive:
		return
	var ctr := c.size / 2.0
	var col := Color8(0x3f, 0xe0, 0xd8)
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
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(C_PANEL, C_RED, 3, "right"))
	var l := _lbl(p, 13, C_WHITE, txt)
	killfeed.add_child(p)
	get_tree().create_timer(4.5).timeout.connect(func(): if is_instance_valid(p): p.queue_free())

func banner(text: String) -> void:
	banner_big.text = text
	banner_until = main.now() + 2.5

func match_over(won: bool) -> void:
	banner_big.text = "胜 利" if won else "失 败"
	banner_big.add_theme_color_override("font_color", C_TEAL if won else C_RED)
	banner_until = main.now() + 9999.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_board(show: bool) -> void:
	board.visible = show
	if not show:
		return
	var mm = main.match_mgr
	var txt := "计分板 — 我方 %d : %d 敌方\n\n特工          定位      K    D\n————————————————————————\n" % [mm.score["ally"], mm.score["enemy"]]
	for e in main.combatants():
		var aid: String = e.agent_id
		var a: Dictionary = Ab.AGENTS[aid]
		var nm: String = a["name"] + ("（你）" if e == main.player else "")
		txt += "%-10s %-8s %2d   %2d   [%s]\n" % [nm, a.get("role", ""), e.kills, e.deaths, "我方" if e.team == "ally" else "敌方"]
	board_body.text = txt

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
			c.draw_circle(pos, 3, C_TEAL)
		elif main.now() < e.revealed_until or main.has_los(main.player.eye_pos(), e.eye_pos(), [main.player, e]):
			c.draw_circle(pos, 3, C_RED)
	if main.match_mgr.spike_state != "carried":
		var sp: Vector3 = main.match_mgr.spike_pos
		c.draw_circle(Vector2((sp.x + world / 2) * k, (sp.z + world / 2) * k), 4, Color(1, 0.25, 0.3))

# ---------------- 技能格 ----------------
var _ab_cache := ""
func _refresh_abilities(p) -> void:
	var a: Dictionary = Ab.AGENTS[p.agent_id]
	var sig := ""
	for k in ["c", "q", "e"]:
		sig += "%s%d" % [k, p.ability_slots[k]["n"]]
	sig += "x%d" % p.ult_points
	if sig == _ab_cache:
		return
	_ab_cache = sig
	for c in ability_box.get_children():
		c.queue_free()
	for k in ["c", "q", "e"]:
		var sl: Dictionary = p.ability_slots[k]
		ability_box.add_child(_ab_square(k.to_upper(), sl["def"]["type"], str(sl["n"]), sl["n"] <= 0, false))
	var ult_ready: bool = p.ult_points >= a["ult_cost"]
	ability_box.add_child(_ab_square("X", a["x"]["type"], "%d/%d" % [p.ult_points, a["ult_cost"]], false, true, ult_ready))

func _ab_square(key: String, ab_type: String, n: String, empty: bool, is_ult: bool, ready: bool = false) -> PanelContainer:
	var sq := PanelContainer.new()
	var border := C_GOLD if is_ult else (C_TEAL if ready else Color8(0x2b, 0x3b, 0x47))
	sq.add_theme_stylebox_override("panel", _sb(C_PANEL, border, 1))
	sq.custom_minimum_size = Vector2(58, 58)
	if empty:
		sq.modulate.a = 0.35
	var overlay := Control.new()
	sq.add_child(overlay)
	var icon := TextureRect.new()
	icon.texture = Icons.tex(ab_type, C_GOLD if is_ult else (C_TEAL if ready else C_WHITE), 54)
	icon.custom_minimum_size = Vector2(27, 27)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.position = Vector2(-14, -14)
	icon.size = Vector2(28, 28)
	overlay.add_child(icon)
	var kl := Label.new()
	kl.text = key
	kl.add_theme_font_size_override("font_size", 10)
	kl.add_theme_color_override("font_color", C_DIM)
	kl.position = Vector2(3, 1)
	overlay.add_child(kl)
	var cnt := Label.new()
	cnt.text = n
	cnt.add_theme_font_size_override("font_size", 12)
	cnt.add_theme_color_override("font_color", C_GOLD)
	cnt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	cnt.position = Vector2(-30, -18)
	cnt.custom_minimum_size = Vector2(26, 0)
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	overlay.add_child(cnt)
	return sq

# ---------------- 每帧 ----------------
func _process(dt: float) -> void:
	if main == null or main.player == null:
		return
	var p = main.player
	var mm = main.match_mgr
	if p.observer:
		for pp in player_panels:
			pp.visible = false
		ability_box.visible = false
	# 顶栏
	score_ally_l.text = str(mm.score["ally"])
	score_enemy_l.text = str(mm.score["enemy"])
	round_l.text = "回合 %d" % mm.round_no
	side_l.text = "进攻方" if mm.ally_side == "atk" else "防守方"
	var t: float = 0.0
	match mm.phase:
		"buy": t = mm.t_phase - main.now()
		"live": t = mm.t_phase - main.now()
		"planted": t = mm.explode_at - main.now()
	var ts := "%d:%02d" % [int(maxf(0, t)) / 60, int(maxf(0, t)) % 60]
	clock_l.text = ("购买 " + ts) if mm.phase == "buy" else ("—" if mm.phase == "end" else ts)
	clock_l.add_theme_color_override("font_color", C_RED if (mm.phase == "planted" or (mm.phase == "live" and t < 20)) else C_WHITE)
	spike_tag.visible = mm.phase == "planted"
	# 存活点
	var ai := 0
	var ei := 0
	for e in main.combatants():
		var arr := dots_ally if e.team == "ally" else dots_enemy
		var idx := ai if e.team == "ally" else ei
		if idx < arr.get_child_count():
			(arr.get_child(idx) as ColorRect).color = (C_TEAL if e.team == "ally" else C_RED) if e.alive else Color8(0x33, 0x3d, 0x46)
		if e.team == "ally": ai += 1
		else: ei += 1
	# 血甲
	hp_num.text = str(maxi(0, int(ceil(p.hp))))
	armor_num.text = "甲 %d" % p.armor
	hp_bar.anchor_right = clampf(p.hp / 100.0, 0, 1)
	armor_bar.anchor_right = clampf(p.armor / 50.0, 0, 1)
	money_l.text = "¥ %d" % p.money
	var a: Dictionary = Ab.AGENTS[p.agent_id]
	ult_l.text = "大招点数 %d/%d" % [p.ult_points, a["ult_cost"]]
	# 弹药
	var w: Dictionary = p.weapon
	if p.knife_ult > 0:
		ammo_num.text = "%d 飞刃" % p.knife_ult
		weap_name.text = "锋刃风暴"
	elif p.rocket_ult > 0:
		ammo_num.text = "%d 火箭弹" % p.rocket_ult
		weap_name.text = "毁灭者火箭"
	else:
		ammo_num.text = "%d / %d" % [w["ammo"], w["reserve"]]
		weap_name.text = w["def"]["name"].to_upper() + ("  换弹中…" if w["reload_end"] > 0 else "")
	for i in range(slot_ls.size()):
		var on: bool = (i == 0 and p.slot == "primary") or (i == 1 and p.slot == "secondary")
		(slot_ls[i] as Label).add_theme_color_override("font_color", C_WHITE if on else C_DIM)
	(slot_ls[0] as Label).modulate.a = 1.0 if p.primary.size() > 0 else 0.35
	_refresh_abilities(p)
	# 观战提示
	if not p.alive and p.spectating != null and is_instance_valid(p.spectating):
		spec_l.text = "观战中 · %s（左键切换）" % p.spectating.agent_name
	elif not p.alive:
		spec_l.text = "阵亡 — 等待回合结束"
	else:
		spec_l.text = ""
	# 指针锁丢失兜底：无菜单打开但鼠标未捕获 → 显示"点击进入战场"
	if not pause_open and not buy_open and main.match_mgr.phase != "over" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		lock_hint.visible = true
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		lock_hint.visible = false
	# 横幅 / 遮罩
	banner_big.visible = main.now() < banner_until
	vignette.color.a = move_toward(vignette.color.a, 0, dt * 1.4)
	flash_rect.color.a = move_toward(flash_rect.color.a, 0, dt * 0.9)
	smoke_rect.color.a = 0.97 if (p.alive and main.in_smoke(p.eye_pos())) else 0.0
	report_panel.visible = mm.phase == "buy" and mm.report_text != ""
	report_l.text = mm.report_text
	crosshair.queue_redraw()
	minimap.queue_redraw()

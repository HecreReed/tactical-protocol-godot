# map_builder.gd — 从 data/maps.json 构建战场（几何/碰撞/导航/点位/光幕）
# 与网页版共用同一份地图数据：10 张图 1:1 复刻
class_name MapBuilder
extends Node3D

const TexGen := preload("res://scripts/tex_gen.gd")

var md: Dictionary = {}
var world_size: float = 140.0
var barriers: Array = []          # StaticBody3D 列表（购买阶段光幕）
var sites: Dictionary = {}        # key -> {rect, plant:Vector3}
var spawns_atk: Array = []
var spawns_def: Array = []
var def_posts: Array = []         # [{p:Vector3, look:Vector3}]
var atk_holds: Dictionary = {}    # site -> [{p,look}]
var stages: Dictionary = {}
var nav_region: Node3D
var astar: AStar3D
var _nav_cells: Dictionary = {}
var _boxes: Array = []            # 碰撞盒 [{min:Vector3,max:Vector3}] 用于导航格judge

static func load_all() -> Dictionary:
	var f := FileAccess.open("res://data/maps.json", FileAccess.READ)
	if f == null:
		push_error("cannot open res://data/maps.json")
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("maps.json parse failed")
		return {}
	return parsed

const FLOOR_THEME := {
	"chongqing": "terrace", "liexia": "terrace", "xuefeng": "snow", "gumiao": "tile",
	"yiji": "stone", "santa": "tile", "huanjie": "asphalt", "rongcheng": "asphalt",
	"sixiang": "tile", "tiangang": "deck"
}

static func _mat_tex(tex: ImageTexture, tint: Color, tile_m: float, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * (1.0 / tile_m)
	m.roughness = rough
	m.metallic = metal
	return m

func build(map_dict: Dictionary, world: float) -> void:
	md = map_dict
	world_size = world
	var wall_tone := Color(md["wallTone"])
	var accent := Color(md["accent"])
	var ground := Color(md["ground"])

	nav_region = Node3D.new()
	add_child(nav_region)

	# ---- 地面（每图主题程序化纹理：等高线/雪原/石板/沥青/甲板） ----
	var theme: String = FLOOR_THEME.get(md.get("id", ""), "stone")
	var floor_mat := _mat_tex(TexGen.floor_theme(theme), ground.lerp(Color.WHITE, 0.55), 10.0 if theme == "terrace" else 6.0, 0.95)
	_box(nav_region, Vector3(0, -0.5, 0), Vector3(world, 1, world), floor_mat, true)

	# ---- 外墙（由开放区反推：与网页版同算法生成行条） ----
	var half := int(world / 2.0)
	var open: Array = md["open"]
	var wall_mat := _mat_tex(TexGen.wall(), wall_tone.lerp(Color.WHITE, 0.35), 4.0, 0.85)
	for z in range(-half, half):
		var run_start := -9999
		for x in range(-half, half + 1):
			var solid := x < half and not _in_open(open, x + 0.5, z + 0.5)
			if solid and run_start == -9999:
				run_start = x
			if (not solid or x == half) and run_start != -9999:
				var x2 := x
				var h := 4.0 + fmod(absf(sin(run_start * 127.1 + z * 311.7) * 43758.5), 1.0) * 1.8
				_box(nav_region, Vector3((run_start + x2) / 2.0, h / 2.0, z + 0.5), Vector3(x2 - run_start, h, 1), wall_mat, true)
				run_start = -9999

	# ---- 内墙 ----
	for w in md["innerWalls"]:
		_box(nav_region, Vector3((w[0] + w[2]) / 2.0, w[4] / 2.0, (w[1] + w[3]) / 2.0), Vector3(w[2] - w[0], w[4], w[3] - w[1]), wall_mat, true)

	# ---- 平台 / 楼梯 / 桥 ----
	var plat_mat := _mat_tex(TexGen.metal(), Color(0.78, 0.86, 0.92), 3.0, 0.72, 0.3)
	for p in md["platforms"]:
		_box(nav_region, Vector3((p[0] + p[2]) / 2.0, p[4] / 2.0, (p[1] + p[3]) / 2.0), Vector3(p[2] - p[0], p[4], p[3] - p[1]), plat_mat, true)
	for st in md["stairs"]:
		_stairs(st, plat_mat)
	for b in md["bridges"]:
		_box(nav_region, Vector3((b[0] + b[2]) / 2.0, b[4] - 0.175, (b[1] + b[3]) / 2.0), Vector3(b[2] - b[0], 0.35, b[3] - b[1]), plat_mat, true)

	# ---- 箱子 ----
	var crate_mat := _mat_tex(TexGen.crate(), Color(1, 1, 1), 2.0, 0.9)
	var metal_mat := _mat_tex(TexGen.metal(), Color(0.72, 0.80, 0.86), 2.0, 0.55, 0.35)
	for c in md["crates"]:
		var y0: float = c[5] if c.size() > 5 else 0.0
		var mat: StandardMaterial3D = metal_mat if (c.size() > 4 and int(c[4]) == 1) else crate_mat
		_box(nav_region, Vector3(c[0], y0 + c[3] / 2.0, c[1]), Vector3(c[2], c[3], c[2]), mat, true)

	# ---- 屋顶（不可站立：碰撞体加高，与网页版一致） ----
	var roof_mat := _mat_tex(TexGen.wall(), wall_tone.darkened(0.25), 4.0, 0.9)
	for r in md["roofs"]:
		_box(nav_region, Vector3((r[0] + r[2]) / 2.0, r[4] + 0.12, (r[1] + r[3]) / 2.0), Vector3(r[2] - r[0], 0.25, r[3] - r[1]), roof_mat, false)
		_collider_only(nav_region, Vector3((r[0] + r[2]) / 2.0, r[4] + 1.3, (r[1] + r[3]) / 2.0), Vector3(r[2] - r[0], 2.6, r[3] - r[1]))

	# ---- 点位标记：区域着色框 + 发光描边 + 大字母 ----
	for key in md["sites"].keys():
		var s: Dictionary = md["sites"][key]
		var plant: Array = s["plant"]
		var rect: Array = s["rect"]
		sites[key] = { "rect": rect, "plant": Vector3(plant[0], 0, plant[1]) }
		# 区域地面着色
		var tint := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(rect[2] - rect[0], 0.06, rect[3] - rect[1])
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = Color(0.16, 0.29, 0.31, 0.45)
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tmat.emission_enabled = true
		tmat.emission = Color(0.1, 0.23, 0.25)
		tmat.emission_energy_multiplier = 0.35
		tb.material = tmat
		tint.mesh = tb
		tint.position = Vector3((rect[0] + rect[2]) / 2.0, 0.035, (rect[1] + rect[3]) / 2.0)
		add_child(tint)
		# 发光描边（四边）
		var emat := StandardMaterial3D.new()
		emat.albedo_color = accent
		emat.emission_enabled = true
		emat.emission = accent
		emat.emission_energy_multiplier = 1.6
		var edges := [
			[Vector3((rect[0] + rect[2]) / 2.0, 0.06, rect[1]), Vector3(rect[2] - rect[0], 0.08, 0.18)],
			[Vector3((rect[0] + rect[2]) / 2.0, 0.06, rect[3]), Vector3(rect[2] - rect[0], 0.08, 0.18)],
			[Vector3(rect[0], 0.06, (rect[1] + rect[3]) / 2.0), Vector3(0.18, 0.08, rect[3] - rect[1])],
			[Vector3(rect[2], 0.06, (rect[1] + rect[3]) / 2.0), Vector3(0.18, 0.08, rect[3] - rect[1])],
		]
		for eg in edges:
			var em := MeshInstance3D.new()
			var eb := BoxMesh.new()
			eb.size = eg[1]
			eb.material = emat
			em.mesh = eb
			em.position = eg[0]
			add_child(em)
		# 地面大字母（复刻网页版 letterTexture 7m 平铺字）
		var letter := Label3D.new()
		letter.text = key
		letter.font_size = 320
		letter.pixel_size = 0.02
		letter.modulate = Color(0.5, 0.82, 0.83, 0.85)
		letter.rotation_degrees = Vector3(-90, 0, 0)
		letter.position = Vector3(plant[0], 0.09, plant[1])
		add_child(letter)
		# 下包环
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 1.45
		tor.outer_radius = 1.7
		var em2 := StandardMaterial3D.new()
		em2.albedo_color = accent
		em2.emission_enabled = true
		em2.emission = accent
		tor.material = em2
		ring.mesh = tor
		ring.position = Vector3(plant[0], 0.08, plant[1])
		add_child(ring)

	# ---- 出生点 / 驻点 / 集结 ----
	for sp in md["spawns"]["atk"]:
		spawns_atk.append(Vector3(sp[0], 0.1, sp[1]))
	for sp in md["spawns"]["def"]:
		spawns_def.append(Vector3(sp[0], 0.1, sp[1]))
	for p in md["defPostList"]:
		def_posts.append({ "p": Vector3(p["p"][0], 0, p["p"][1]), "look": Vector3(p["look"][0], 1.5, p["look"][1]) })
	for k in md["atkHolds"].keys():
		var arr: Array = []
		for h in md["atkHolds"][k]:
			arr.append({ "p": Vector3(h["p"][0], 0, h["p"][1]), "look": Vector3(h["look"][0], 1.5, h["look"][1]) })
		atk_holds[k] = arr
	for k in md["stages"].keys():
		stages[k] = Vector3(md["stages"][k][0], 0, md["stages"][k][1])

	# ---- 光幕（购买阶段） ----
	build_barriers()

	# ---- 多层网格导航（对齐网页版：每格采样可站高度——地面/楼梯/高台/桥面，按高度差连边） ----
	_bake_nav(open, world)

func build_barriers() -> void:
	remove_barriers()
	for b in md["barriers"]:
		var rect: Array = b["rect"]
		var body := _box(self, Vector3((rect[0] + rect[2]) / 2.0, 2, (rect[1] + rect[3]) / 2.0), Vector3(rect[2] - rect[0], 4, rect[3] - rect[1]), _barrier_mat(b["side"] == "atk"), true, true)
		body.collision_layer = 8      # 光幕专用层：挡人不进导航烘焙
		barriers.append(body)

func remove_barriers() -> void:
	for b in barriers:
		if is_instance_valid(b):
			b.queue_free()
	barriers.clear()

func _cell_blocked(x: float, z: float) -> bool:
	for b in _boxes:
		var bmin: Vector3 = b["min"]
		var bmax: Vector3 = b["max"]
		if bmax.y < 0.45 or bmin.y > 1.4:
			continue
		if x > bmin.x - 0.45 and x < bmax.x + 0.45 and z > bmin.z - 0.45 and z < bmax.z + 0.45:
			return true
	return false

func nav_path(from: Vector3, to: Vector3) -> PackedVector2Array:
	var a := _nearest_nav_id(from)
	var b := _nearest_nav_id(to)
	var out := PackedVector2Array()
	if a < 0 or b < 0:
		return out
	var pts := astar.get_point_path(a, b, true)
	for p in pts:
		out.append(Vector2(p.x, p.z))
	return out

func _nearest_nav_id(pos: Vector3) -> int:
	var half := int(world_size / 2.0)
	var gx := clampi(int(floor(pos.x)), -half, half - 1)
	var gz := clampi(int(floor(pos.z)), -half, half - 1)
	for radius in range(0, 9):
		var best := -1
		var bd := 1e9
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				if maxi(abs(dx), abs(dz)) != radius:
					continue
				var key: int = (gx + dx + 2048) * 4096 + (gz + dz + 2048)
				if _nav_cells.has(key):
					for id in _nav_cells[key]:
						var p: Vector3 = astar.get_point_position(id)
						var d: float = Vector2(p.x - pos.x, p.z - pos.z).length() + absf(p.y - pos.y) * 1.5
						if d < bd:
							bd = d
							best = id
		if best >= 0:
			return best
	return -1

func _cell_heights(cx: float, cz: float) -> Array:
	# 该格所有可站高度：地面 0 + 覆盖此格的实体顶面（≤3.2m），要求 1.8m 头顶净空
	var cands: Array = [0.0]
	for b in _boxes:
		var bmin: Vector3 = b["min"]
		var bmax: Vector3 = b["max"]
		if cx > bmin.x - 0.35 and cx < bmax.x + 0.35 and cz > bmin.z - 0.35 and cz < bmax.z + 0.35:
			if bmax.y <= 3.2 and bmax.y > 0.12:
				cands.append(bmax.y)
	var out: Array = []
	for h in cands:
		var ok := true
		for b in _boxes:
			var bmin: Vector3 = b["min"]
			var bmax: Vector3 = b["max"]
			if cx > bmin.x - 0.3 and cx < bmax.x + 0.3 and cz > bmin.z - 0.3 and cz < bmax.z + 0.3:
				if bmin.y < h + 1.75 and bmax.y > h + 0.25:
					ok = false
					break
		if ok:
			var dup := false
			for h2 in out:
				if absf(h2 - h) < 0.3:
					dup = true
					break
			if not dup:
				out.append(h)
	return out

func _bake_nav(open: Array, world: float) -> void:
	var half := int(world / 2.0)
	astar = AStar3D.new()
	_nav_cells = {}
	var next_id := 0
	for gx in range(-half, half):
		for gz in range(-half, half):
			var cx := gx + 0.5
			var cz := gz + 0.5
			if not _in_open(open, cx, cz):
				continue
			var hs := _cell_heights(cx, cz)
			if hs.is_empty():
				continue
			var ids: Array = []
			for h in hs:
				astar.add_point(next_id, Vector3(cx, h, cz))
				ids.append(next_id)
				next_id += 1
			_nav_cells[(gx + 2048) * 4096 + (gz + 2048)] = ids
	# 连边：四邻 + 对角，高度差 ≤1.05（台阶/楼梯可走，高台需经楼梯）
	for gx in range(-half, half):
		for gz in range(-half, half):
			var key: int = (gx + 2048) * 4096 + (gz + 2048)
			if not _nav_cells.has(key):
				continue
			for off in [[1, 0], [0, 1], [1, 1], [1, -1]]:
				var nkey: int = (gx + int(off[0]) + 2048) * 4096 + (gz + int(off[1]) + 2048)
				if not _nav_cells.has(nkey) or nkey == key:
					continue
				# 对角连边要求两侧正交格都可走（防穿角，对齐网页版）
				if off[0] != 0 and off[1] != 0:
					var k1: int = (gx + int(off[0]) + 2048) * 4096 + (gz + 2048)
					var k2: int = (gx + 2048) * 4096 + (gz + int(off[1]) + 2048)
					if not _nav_cells.has(k1) or not _nav_cells.has(k2):
						continue
				for id_a in _nav_cells[key]:
					var pa: Vector3 = astar.get_point_position(id_a)
					for id_b in _nav_cells[nkey]:
						var pb: Vector3 = astar.get_point_position(id_b)
						if absf(pa.y - pb.y) <= 0.62:
							astar.connect_points(id_a, id_b)

func in_site(pos: Vector3) -> String:
	for key in sites.keys():
		var r: Array = sites[key]["rect"]
		if pos.x >= r[0] and pos.x <= r[2] and pos.z >= r[1] and pos.z <= r[3]:
			return key
	return ""

func _barrier_mat(atk: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.22, 0.8, 0.78, 0.28) if atk else Color(1.0, 0.3, 0.35, 0.28)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = m.albedo_color
	return m

func _in_open(open: Array, x: float, z: float) -> bool:
	for r in open:
		if x >= r[0] and x <= r[2] and z >= r[1] and z <= r[3]:
			return true
	return false

func _stairs(st: Dictionary, mat: StandardMaterial3D) -> void:
	var steps := maxi(2, ceili(st["h"] / 0.28))
	for i in range(steps):
		var h: float = st["h"] * (i + 1) / steps
		var x1: float = st["x1"]
		var x2: float = st["x2"]
		var z1: float = st["z1"]
		var z2: float = st["z2"]
		var dir: String = st["dir"]
		if dir == "+x":
			var w := (x2 - x1) / steps
			x1 = st["x1"] + i * w
			x2 = x1 + w
		elif dir == "-x":
			var w := (x2 - x1) / steps
			x2 = st["x2"] - i * w
			x1 = x2 - w
		elif dir == "+z":
			var w := (z2 - z1) / steps
			z1 = st["z1"] + i * w
			z2 = z1 + w
		elif dir == "-z":
			var w := (z2 - z1) / steps
			z2 = st["z2"] - i * w
			z1 = z2 - w
		_box(nav_region, Vector3((x1 + x2) / 2.0, h / 2.0, (z1 + z2) / 2.0), Vector3(x2 - x1, h, z2 - z1), mat, true)

func _box(parent: Node, pos: Vector3, size: Vector3, mat: StandardMaterial3D, collide: bool, transparent: bool = false) -> StaticBody3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.position = pos
		body.add_child(cs)
		body.add_child(mi)
		parent.add_child(body)
		if not transparent:
			_boxes.append({ "min": pos - size / 2.0, "max": pos + size / 2.0 })
		return body
	mi.position = pos
	parent.add_child(mi)
	return null

func _collider_only(parent: Node, pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.position = pos
	body.add_child(cs)
	parent.add_child(body)

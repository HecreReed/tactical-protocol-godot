# map_builder.gd — 从 data/maps.json 构建战场（几何/碰撞/导航/点位/光幕）
# 与网页版共用同一份地图数据：10 张图 1:1 复刻
class_name MapBuilder
extends Node3D

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
var astar: AStarGrid2D
var _boxes: Array = []            # 碰撞盒 [{min:Vector3,max:Vector3}] 用于导航格judge

static func load_all() -> Dictionary:
	var f := FileAccess.open("res://data/maps.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

func build(map_dict: Dictionary, world: float) -> void:
	md = map_dict
	world_size = world
	var wall_tone := Color(md["wallTone"])
	var accent := Color(md["accent"])
	var ground := Color(md["ground"])

	nav_region = Node3D.new()
	add_child(nav_region)

	# ---- 地面 ----
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = ground
	floor_mat.roughness = 0.95
	_box(nav_region, Vector3(0, -0.5, 0), Vector3(world, 1, world), floor_mat, true)

	# ---- 外墙（由开放区反推：与网页版同算法生成行条） ----
	var half := int(world / 2.0)
	var open: Array = md["open"]
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = wall_tone
	wall_mat.roughness = 0.85
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
	var plat_mat := StandardMaterial3D.new()
	plat_mat.albedo_color = Color(0.62, 0.68, 0.72)
	plat_mat.roughness = 0.75
	for p in md["platforms"]:
		_box(nav_region, Vector3((p[0] + p[2]) / 2.0, p[4] / 2.0, (p[1] + p[3]) / 2.0), Vector3(p[2] - p[0], p[4], p[3] - p[1]), plat_mat, true)
	for st in md["stairs"]:
		_stairs(st, plat_mat)
	for b in md["bridges"]:
		_box(nav_region, Vector3((b[0] + b[2]) / 2.0, b[4] - 0.175, (b[1] + b[3]) / 2.0), Vector3(b[2] - b[0], 0.35, b[3] - b[1]), plat_mat, true)

	# ---- 箱子 ----
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color(0.55, 0.45, 0.34)
	crate_mat.roughness = 0.9
	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.5, 0.56, 0.6)
	metal_mat.metallic = 0.3
	for c in md["crates"]:
		var y0: float = c[5] if c.size() > 5 else 0.0
		var mat: StandardMaterial3D = metal_mat if (c.size() > 4 and int(c[4]) == 1) else crate_mat
		_box(nav_region, Vector3(c[0], y0 + c[3] / 2.0, c[1]), Vector3(c[2], c[3], c[2]), mat, true)

	# ---- 屋顶（不可站立：碰撞体加高，与网页版一致） ----
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = wall_tone.darkened(0.25)
	for r in md["roofs"]:
		_box(nav_region, Vector3((r[0] + r[2]) / 2.0, r[4] + 0.12, (r[1] + r[3]) / 2.0), Vector3(r[2] - r[0], 0.25, r[3] - r[1]), roof_mat, false)
		_collider_only(nav_region, Vector3((r[0] + r[2]) / 2.0, r[4] + 1.3, (r[1] + r[3]) / 2.0), Vector3(r[2] - r[0], 2.6, r[3] - r[1]))

	# ---- 点位标记 ----
	for key in md["sites"].keys():
		var s: Dictionary = md["sites"][key]
		var plant: Array = s["plant"]
		sites[key] = { "rect": s["rect"], "plant": Vector3(plant[0], 0, plant[1]) }
		var ring := MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 1.45
		tor.outer_radius = 1.7
		var em := StandardMaterial3D.new()
		em.albedo_color = accent
		em.emission_enabled = true
		em.emission = accent
		tor.material = em
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
	for b in md["barriers"]:
		var rect: Array = b["rect"]
		var body := _box(self, Vector3((rect[0] + rect[2]) / 2.0, 2, (rect[1] + rect[3]) / 2.0), Vector3(rect[2] - rect[0], 4, rect[3] - rect[1]), _barrier_mat(b["side"] == "atk"), true, true)
		body.collision_layer = 8      # 光幕专用层：挡人不进导航烘焙
		barriers.append(body)

	# ---- 网格导航（移植网页版：1m 格 + 对角连通，AStarGrid2D C++ 高速） ----
	var nhalf := int(world / 2.0)
	astar = AStarGrid2D.new()
	astar.region = Rect2i(-nhalf, -nhalf, int(world), int(world))
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for gx in range(-nhalf, nhalf):
		for gz in range(-nhalf, nhalf):
			var cx := gx + 0.5
			var cz := gz + 0.5
			var walkable := _in_open(open, cx, cz) and not _cell_blocked(cx, cz)
			if not walkable:
				astar.set_point_solid(Vector2i(gx, gz), true)

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
	var a := _nearest_cell(from)
	var b := _nearest_cell(to)
	return astar.get_point_path(a, b)

func _nearest_cell(p: Vector3) -> Vector2i:
	var c := Vector2i(floori(p.x), floori(p.z))
	var half := int(world_size / 2.0)
	c.x = clampi(c.x, -half, half - 1)
	c.y = clampi(c.y, -half, half - 1)
	if not astar.is_point_solid(c):
		return c
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var q := Vector2i(clampi(c.x + dx, -half, half - 1), clampi(c.y + dz, -half, half - 1))
				if not astar.is_point_solid(q):
					return q
	return c

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

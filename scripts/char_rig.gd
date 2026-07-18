# char_rig.gd — 人形角色模型（1:1 移植网页版 buildBody）：
# 双腿(髋铰点)+靴子/髋部/躯干/胸甲/背包/肩甲/腰带/双臂/头+头盔+发光面甲/手持枪 + 走路摆动动画 + 队友名牌
extends Node3D

const TEAM_COLORS := {
	"ally": { "head": Color8(0x3f, 0xb3, 0xad), "trim": Color8(0x2f, 0x8f, 0x8a) },
	"enemy": { "head": Color8(0xd0, 0x45, 0x55), "trim": Color8(0xb0, 0x30, 0x40) },
}

var leg_l: MeshInstance3D
var leg_r: MeshInstance3D
var arm_l: MeshInstance3D
var arm_r: MeshInstance3D
var upper: Node3D
var _phase := randf() * TAU

static func _mat(c: Color, rough: float, emis: Color = Color.BLACK, ei: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if ei > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = ei
	return m

static func _boxm(size: Vector3, mat: StandardMaterial3D, pos: Vector3, offset: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	if offset != Vector3.ZERO:
		var am := ArrayMesh.new()
		var arrs := bm.get_mesh_arrays()
		var verts: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		for i in range(verts.size()):
			verts[i] += offset
		arrs[Mesh.ARRAY_VERTEX] = verts
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
		mi.mesh = am
		mi.material_override = mat
	else:
		bm.material = mat
		mi.mesh = bm
	mi.position = pos
	return mi

func build(team: String, agent_color: Color, agent_name: String, show_tag: bool) -> void:
	var tc: Dictionary = TEAM_COLORS[team]
	var torso_mat := _mat(agent_color, 0.7, agent_color, 0.35)
	var dark_mat := _mat(Color8(0x2a, 0x33, 0x3c), 0.9)
	var grey_mat := _mat(Color8(0x3c, 0x46, 0x50), 0.75)
	var h_mat := _mat(tc["head"], 0.6)
	var trim_mat := _mat(tc["trim"], 0.55, tc["trim"], 0.6)

	# 双腿（髋部铰点：几何体下移，让 rotation 绕髋摆动）
	leg_l = _boxm(Vector3(0.17, 0.78, 0.22), dark_mat, Vector3(-0.13, 0.82, 0), Vector3(0, -0.39, 0))
	leg_r = _boxm(Vector3(0.17, 0.78, 0.22), dark_mat, Vector3(0.13, 0.82, 0), Vector3(0, -0.39, 0))
	add_child(leg_l)
	add_child(leg_r)
	# 靴子
	leg_l.add_child(_boxm(Vector3(0.19, 0.12, 0.3), grey_mat, Vector3(0, -0.72, -0.03)))
	leg_r.add_child(_boxm(Vector3(0.19, 0.12, 0.3), grey_mat, Vector3(0, -0.72, -0.03)))
	# 髋部
	add_child(_boxm(Vector3(0.46, 0.18, 0.3), grey_mat, Vector3(0, 0.9, 0)))
	# 躯干组（蹲下时整体下沉）
	upper = Node3D.new()
	add_child(upper)
	upper.add_child(_boxm(Vector3(0.54, 0.56, 0.32), torso_mat, Vector3(0, 1.24, 0)))
	upper.add_child(_boxm(Vector3(0.42, 0.3, 0.08), trim_mat, Vector3(0, 1.3, -0.19)))
	upper.add_child(_boxm(Vector3(0.36, 0.4, 0.15), grey_mat, Vector3(0, 1.22, 0.23)))
	upper.add_child(_boxm(Vector3(0.16, 0.12, 0.3), trim_mat, Vector3(-0.35, 1.48, 0)))
	upper.add_child(_boxm(Vector3(0.16, 0.12, 0.3), trim_mat, Vector3(0.35, 1.48, 0)))
	upper.add_child(_boxm(Vector3(0.56, 0.08, 0.34), trim_mat, Vector3(0, 1.0, 0)))
	# 双臂（肩部铰点）：右臂托枪前伸，左臂扶护木
	arm_l = _boxm(Vector3(0.12, 0.56, 0.14), torso_mat, Vector3(-0.33, 1.45, 0), Vector3(0, -0.28, 0))
	arm_l.rotation.x = -0.9
	arm_l.rotation.z = 0.35
	arm_r = _boxm(Vector3(0.12, 0.56, 0.14), torso_mat, Vector3(0.33, 1.45, 0), Vector3(0, -0.28, 0))
	arm_r.rotation.x = -1.05
	arm_r.rotation.z = -0.15
	upper.add_child(arm_l)
	upper.add_child(arm_r)
	# 头 + 头盔 + 发光面甲
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.17
	hm.height = 0.34
	hm.material = h_mat
	head.mesh = hm
	head.position = Vector3(0, 1.66, 0)
	upper.add_child(head)
	var helmet := MeshInstance3D.new()
	var hem := SphereMesh.new()
	hem.radius = 0.19
	hem.height = 0.38
	hem.material = grey_mat
	helmet.mesh = hem
	helmet.position = Vector3(0, 1.71, 0)
	helmet.scale = Vector3(1, 0.62, 1)
	upper.add_child(helmet)
	var visor := _boxm(Vector3(0.24, 0.07, 0.05), _mat(Color8(0x0c, 0x14, 0x1c), 0.5, tc["trim"], 1.6), Vector3(0, 1.67, -0.16))
	upper.add_child(visor)
	# 手中武器（机匣+弹匣+枪管）
	var gun := Node3D.new()
	var g_body := _boxm(Vector3(0.07, 0.09, 0.5), _mat(Color8(0x23, 0x2b, 0x33), 0.5), Vector3.ZERO)
	var g_mag := _boxm(Vector3(0.05, 0.12, 0.06), grey_mat, Vector3(0, -0.09, -0.05))
	var g_barrel := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.016
	cm.bottom_radius = 0.016
	cm.height = 0.2
	cm.material = dark_mat
	g_barrel.mesh = cm
	g_barrel.rotation.x = PI / 2
	g_barrel.position = Vector3(0, 0.015, -0.33)
	gun.add_child(g_body)
	gun.add_child(g_mag)
	gun.add_child(g_barrel)
	gun.position = Vector3(0.2, 1.32, -0.36)
	gun.rotation.x = 0.06
	upper.add_child(gun)
	# 队友名牌
	if show_tag:
		var tag := Label3D.new()
		tag.text = agent_name
		tag.font_size = 64
		tag.pixel_size = 0.004
		tag.modulate = agent_color
		tag.outline_size = 12
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.position = Vector3(0, 2.1, 0)
		add_child(tag)

func animate(speed_h: float, crouching: bool, t: float) -> void:
	var amp := minf(0.55, speed_h * 0.1)
	var swing := sin(t * 9.5 + _phase) * amp
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	arm_l.rotation.x = -0.9 - swing * 0.5
	arm_r.rotation.x = -1.05 + swing * 0.35
	upper.position.y = -0.3 if crouching else 0.0
	var ls := 0.72 if crouching else 1.0
	leg_l.scale.y = ls
	leg_r.scale.y = ls

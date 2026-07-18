# abilities.gd — 11 特工完整技能组（与网页版对位）+ 技能执行器
class_name Abilities

const AGENTS := {
	"fengying": { "name":"风影", "color":Color(0.56,0.83,1.0), "ult_cost":7,
		"c":{"name":"云雾烟弹","cost":250,"max":1,"type":"smoke_throw"},
		"q":{"name":"上升气流","cost":150,"max":2,"type":"updraft"},
		"e":{"name":"疾风突进","cost":0,"max":1,"cd":22.0,"type":"dash"},
		"x":{"name":"锋刃风暴","type":"knife_ult"} },
	"lieyan": { "name":"烈焰", "color":Color(1.0,0.48,0.19), "ult_cost":7,
		"c":{"name":"烈焰之墙","cost":200,"max":1,"type":"firewall"},
		"q":{"name":"曲光弹","cost":250,"max":2,"type":"flash_throw"},
		"e":{"name":"火热双手","cost":0,"max":1,"cd":0.0,"type":"hot_hands"},
		"x":{"name":"涅槃重生","type":"phoenix_ult"} },
	"tianqiong": { "name":"天穹", "color":Color(0.96,0.77,0.42), "ult_cost":8,
		"c":{"name":"燃烧榴弹","cost":250,"max":1,"type":"molly_throw"},
		"q":{"name":"兴奋信标","cost":100,"max":2,"type":"stim_beacon"},
		"e":{"name":"空降烟幕","cost":0,"max":2,"cd":20.0,"type":"smoke_sky"},
		"x":{"name":"轨道打击","type":"orbital"} },
	"anmu": { "name":"暗幕", "color":Color(0.54,0.44,0.85), "ult_cost":7,
		"c":{"name":"暗影潜行","cost":100,"max":1,"type":"shadow_step"},
		"q":{"name":"弥影闪","cost":250,"max":1,"type":"paranoia"},
		"e":{"name":"迷影烟幕","cost":0,"max":2,"cd":25.0,"type":"smoke_sky"},
		"x":{"name":"从影而袭","type":"shadow_ult"} },
	"lieying": { "name":"猎鹰", "color":Color(0.41,0.78,0.49), "ult_cost":8,
		"c":{"name":"猫头鹰侦察机","cost":300,"max":1,"type":"drone_scan"},
		"q":{"name":"震爆箭","cost":150,"max":2,"type":"shock_throw"},
		"e":{"name":"侦察之箭","cost":0,"max":1,"cd":35.0,"type":"recon_throw"},
		"x":{"name":"猎手之怒","type":"hunter_ult"} },
	"shengyu": { "name":"圣愈", "color":Color(0.91,0.9,0.85), "ult_cost":8,
		"c":{"name":"屏障之墙","cost":400,"max":1,"type":"wall"},
		"q":{"name":"缓速球","cost":200,"max":2,"type":"slow_throw"},
		"e":{"name":"治愈之光","cost":0,"max":1,"cd":45.0,"type":"heal"},
		"x":{"name":"复生","type":"rez"} },
	"leiyi": { "name":"雷奕", "color":Color(1.0,0.6,0.24), "ult_cost":8,
		"c":{"name":"轰轰机器人","cost":300,"max":1,"type":"boom_bot"},
		"q":{"name":"爆破背包","cost":200,"max":2,"type":"blast_jump"},
		"e":{"name":"彩弹集束雷","cost":0,"max":1,"cd":0.0,"type":"nade_throw"},
		"x":{"name":"毁灭者火箭","type":"rocket_ult"} },
	"zhuying": { "name":"蛛影", "color":Color(0.75,0.8,0.85), "ult_cost":8,
		"c":{"name":"纳米蜂群","cost":200,"max":2,"type":"nano_throw"},
		"q":{"name":"警报机器人","cost":200,"max":1,"type":"alarm_bot"},
		"e":{"name":"哨戒炮塔","cost":0,"max":1,"cd":0.0,"type":"turret"},
		"x":{"name":"全域封锁","type":"lockdown"} },
	"lanqie": { "name":"岚切", "color":Color(0.85,0.65,0.35), "ult_cost":8,
		"c":{"name":"震荡爆破","cost":200,"max":2,"type":"quake"},
		"q":{"name":"穿墙闪光","cost":250,"max":2,"type":"wall_flash"},
		"e":{"name":"裂地震波","cost":0,"max":1,"cd":35.0,"type":"stun_wave"},
		"x":{"name":"雷动九天","type":"big_stun"} },
	"qingzhen": { "name":"青鸩", "color":Color(0.35,0.85,0.5), "ult_cost":8,
		"c":{"name":"蛇噬毒液","cost":200,"max":2,"type":"acid_throw"},
		"q":{"name":"剧毒云雾","cost":200,"max":1,"type":"toxic_smoke"},
		"e":{"name":"蔓延毒幕","cost":0,"max":1,"cd":32.0,"type":"toxic_wall"},
		"x":{"name":"万毒领域","type":"toxic_dome"} },
	"lingshi": { "name":"零式", "color":Color(0.62,0.71,1.0), "ult_cost":7,
		"c":{"name":"破片雷","cost":200,"max":1,"type":"nade_throw"},
		"q":{"name":"电光闪雷","cost":250,"max":2,"type":"flash_throw"},
		"e":{"name":"零点压制刃","cost":0,"max":1,"cd":0.0,"type":"suppress_throw"},
		"x":{"name":"湮灭脉冲","type":"null_pulse"} },
}

# 投掷类：由 RigidBody3D 真实物理弹跳后触发
const THROWN := ["smoke_throw","flash_throw","molly_throw","slow_throw","nade_throw",
	"suppress_throw","acid_throw","shock_throw","recon_throw","nano_throw","hot_hands","toxic_smoke"]

static func make_slots(agent_id: String) -> Dictionary:
	var a: Dictionary = AGENTS[agent_id]
	var slots := {}
	for k in ["c", "q", "e"]:
		var d: Dictionary = a[k]
		slots[k] = { "def": d, "n": 1 if (d["cost"] == 0 or k != "q") else 1, "cd_until": 0.0 }
	slots["x"] = { "def": a["x"], "n": 0, "cd_until": 0.0 }
	return slots

# 执行技能：ent 为玩家或 AI；main 提供战场服务
static func cast(main: Node3D, ent: Node, key: String) -> bool:
	var slots: Dictionary = ent.ability_slots
	var slot: Dictionary = slots[key]
	var def: Dictionary = slot["def"]
	var now: float = main.now()
	if not main.can_fight():
		return false
	if now < ent.suppressed_until:
		return false
	if key == "x":
		var cost: int = AGENTS[ent.agent_id]["ult_cost"]
		if ent.ult_points < cost:
			return false
	else:
		if slot["n"] <= 0:
			return false
		if key == "e" and now < slot["cd_until"]:
			return false
	var t: String = def["type"]
	var origin: Vector3 = ent.eye_pos()
	var dir: Vector3 = ent.aim_dir()
	var used := true
	if t in THROWN:
		main.throw_grenade(ent, t, origin, dir)
	else:
		match t:
			"dash":
				var d2: Vector3 = Vector3(dir.x, 0, dir.z).normalized()
				ent.velocity = d2 * 16.0 + Vector3.UP * 0.5
				if key == "e": slot["cd_until"] = now + def.get("cd", 22.0)
			"updraft":
				ent.velocity.y = 11.0
			"blast_jump":
				var d2: Vector3 = Vector3(dir.x, 0, dir.z).normalized()
				ent.velocity = d2 * 8.0 + Vector3.UP * 7.2
				main.explosion_fx(ent.global_position, 1.5, Color(1.0,0.7,0.3))
			"heal":
				ent.hp = minf(100.0, ent.hp + 60.0)
				slot["cd_until"] = now + def.get("cd", 45.0)
			"phoenix_ult":
				ent.hp = 100.0
				ent.resist_until = now + 8.0
			"rez":
				used = main.try_revive(ent)
			"wall":
				main.spawn_wall(ent.global_position, ent.yaw_angle(), 30.0)
			"firewall":
				main.spawn_firewall(ent, ent.global_position, dir)
			"paranoia", "wall_flash":
				main.cone_blind(ent, 20.0, 0.65, 1.6)
			"stun_wave":
				main.cone_daze(ent, 18.0, 0.72, 2.4)
				slot["cd_until"] = now + def.get("cd", 35.0)
			"big_stun":
				main.cone_daze(ent, 26.0, 0.55, 3.2)
			"quake":
				var p: Vector3 = ent.global_position + Vector3(dir.x,0,dir.z).normalized() * 7.5
				main.delayed_quake(ent, p)
			"shadow_step":
				main.teleport_forward(ent, 9.0)
			"shadow_ult":
				main.teleport_site(ent)
			"smoke_sky":
				main.smoke_site_chokes(ent)
				slot["cd_until"] = now + def.get("cd", 20.0)
			"orbital":
				main.orbital_strike(ent, origin, dir)
			"stim_beacon":
				main.spawn_device(ent, "beacon", ent.global_position)
			"turret":
				main.spawn_device(ent, "turret", ent.global_position + Vector3(dir.x,0,dir.z).normalized() * 1.4)
			"alarm_bot":
				main.spawn_device(ent, "alarm", ent.global_position + Vector3(dir.x,0,dir.z).normalized() * 3.0)
			"lockdown":
				main.spawn_device(ent, "lockdown", ent.global_position)
			"boom_bot":
				main.spawn_boom_bot(ent, dir)
			"drone_scan":
				main.spawn_drone(ent, dir)
			"toxic_wall":
				main.toxic_wall(ent, dir)
				slot["cd_until"] = now + def.get("cd", 32.0)
			"toxic_dome":
				main.toxic_dome(ent, origin, dir)
			"reveal_all", "hunter_ult":
				main.reveal_enemies(ent)
				if t == "hunter_ult":
					ent.arrow_ult = 3
			"null_pulse":
				main.suppress_burst(ent.global_position, 16.0, 6.0, ent)
				ent.stim_until = now + 8.0
			"knife_ult":
				ent.knife_ult = 5
			"rocket_ult":
				ent.rocket_ult = 1
			_:
				used = false
	if used:
		if key == "x":
			ent.ult_points = 0
		else:
			slot["n"] -= 1
	return used

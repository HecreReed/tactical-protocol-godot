# match_mgr.gd — 回合循环：购买/交战/下包/拆包/结算/换边/经济
extends Node

const Weapons := preload("res://scripts/weapons.gd")

const ROUND_TIME := 100.0
const BUY_TIME := 20.0
const PLANT_TIME := 4.0
const DEFUSE_TIME := 7.0
const SPIKE_TIME := 45.0
const WIN_ROUNDS := 13

var main: Node3D
var phase := "buy"
var round_no := 1
var t_phase := 0.0
var score := { "ally": 0, "enemy": 0 }
var ally_side := "atk"
var spike_state := "carried"     # carried / planted / dropped
var spike_carrier: Node = null
var spike_claimer: Node = null
var spike_pos := Vector3.ZERO
var spike_prog := 0.0
var defuse_prog := 0.0
var explode_at := 0.0
var plan_site := "A"
var execute_called := false
var live_start := 0.0
var loss_streak := { "ally": 0, "enemy": 0 }
var _next_beep := 0.0
var spike_vis: MeshInstance3D

func setup(m: Node3D) -> void:
	main = m
	spike_vis = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.28, 0.34, 0.16)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.1, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.3)
	mat.emission_energy_multiplier = 1.8
	bm.material = mat
	spike_vis.mesh = bm
	main.add_child(spike_vis)
	spike_vis.visible = false
	start_round()

func _update_spike_vis() -> void:
	if spike_state == "carried" and spike_carrier != null and is_instance_valid(spike_carrier) and spike_carrier.alive:
		if spike_carrier == main.player:
			spike_vis.visible = false
			return
		spike_vis.visible = true
		var p: Vector3 = spike_carrier.global_position
		var yw: float = spike_carrier.yaw if "yaw" in spike_carrier else 0.0
		# 背在背后（模型背面 +Z 方向）
		spike_vis.global_position = p + Vector3(sin(yw), 0, cos(yw)) * 0.42 + Vector3(0, 1.28, 0)
		spike_vis.rotation.y = yw
	elif spike_state == "dropped":
		spike_vis.visible = true
		spike_vis.global_position = Vector3(spike_pos.x, 0.25, spike_pos.z)
		spike_vis.rotation.y += 0.03
	else:
		spike_vis.visible = false

func now() -> float:
	return main.now()

func side_of(ent: Node) -> String:
	if ent.team == "ally":
		return ally_side
	return "def" if ally_side == "atk" else "atk"

func start_round() -> void:
	# 战斗报告快照
	report_text = ""
	if not _report_dealt.is_empty():
		report_text = "上回合战斗报告\n"
		for nm in _report_dealt.keys():
			report_text += "%s — 给予 %d 伤害\n" % [nm, int(_report_dealt[nm])]
		_report_dealt.clear()
	main.hud.on_round_start()
	phase = "buy"
	t_phase = now() + BUY_TIME
	spike_state = "carried"
	spike_prog = 0.0
	defuse_prog = 0.0
	execute_called = false
	spike_claimer = null
	main.clear_round_fx()
	var site_keys: Array = main.map.sites.keys()
	plan_site = site_keys.pick_random()
	main.map_rebuild_barriers()
	# 复活 & 出生位
	var atk_spawns: Array = main.map.spawns_atk if ally_side == "atk" else main.map.spawns_def
	var def_spawns: Array = main.map.spawns_def if ally_side == "atk" else main.map.spawns_atk
	var ai := 0
	var di := 0
	for e in main.combatants():
		if e.team == "ally":
			if e == main.player:
				_reset_player(atk_spawns[ai % atk_spawns.size()])
			else:
				e.revive_reset(atk_spawns[ai % atk_spawns.size()])
			ai += 1
		else:
			e.revive_reset(def_spawns[di % def_spawns.size()])
			di += 1
	# 携弹者 = 进攻方随机 bot
	spike_carrier = null
	var roles := ["entry", "entry", "scout", "flank", "support"]
	var ri := 0
	for e in main.combatants():
		if side_of(e) == "atk" and e != main.player and e.alive:
			if spike_carrier == null:
				spike_carrier = e
			if "assault_role" in e:
				e.assault_role = roles[ri % roles.size()]
				ri += 1
	main.hud.banner("第 %d 回合 · %s" % [round_no, "进攻方" if ally_side == "atk" else "防守方"])

func _reset_player(pos: Vector3) -> void:
	var p = main.player
	if p.observer:
		return
	p.alive = true
	p.hp = 100
	p.visible = true
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.weapon["ammo"] = p.weapon["def"]["mag"]

func _process(_dt: float) -> void:
	var n := now()
	_update_spike_vis()
	_channel_watch()
	# 玩家走近掉落的 SPIKE 自动拾取
	if spike_state == "dropped" and not main.player.observer and main.player.alive and side_of(main.player) == "atk" \
			and main.player.global_position.distance_to(spike_pos) < 1.6:
		spike_carrier = main.player
		spike_state = "carried"
		spike_claimer = null
		main.hud.banner("你拾取了 SPIKE")
		main.sfx.play("buy")
	match phase:
		"buy":
			if n >= t_phase:
				phase = "live"
				live_start = n
				t_phase = n + ROUND_TIME
				main.map.remove_barriers()
				main.hud.banner("行动开始")
				main.hud.close_buy()
				main.sfx.play("round_start")
		"live":
			if n >= t_phase:
				end_round("def", "时间耗尽")
			elif n >= live_start + 20.0 and not execute_called:
				execute_called = true
			_check_elim()
		"planted":
			if n >= _next_beep:
				var remain := explode_at - n
				main.sfx.play("beep_fast" if remain < 12.0 else "beep", main.player.global_position.distance_to(spike_pos) * 0.5)
				_next_beep = n + (0.4 if remain < 12.0 else 1.0)
			if n >= explode_at:
				main.explosion_at(spike_pos)
				end_round("atk", "炸弹引爆")
			_check_elim_planted()
		"end":
			if n >= t_phase:
				if score["ally"] >= WIN_ROUNDS or score["enemy"] >= WIN_ROUNDS:
					main.hud.match_over(score["ally"] > score["enemy"])
					phase = "over"
				else:
					round_no += 1
					if round_no == 13:
						ally_side = "def" if ally_side == "atk" else "atk"
						_halftime_reset()
						main.hud.banner("攻防互换")
					start_round()

func _check_elim() -> void:
	var atk_alive := 0
	var def_alive := 0
	for e in main.combatants():
		if not e.alive:
			continue
		if side_of(e) == "atk": atk_alive += 1
		else: def_alive += 1
	if atk_alive == 0:
		end_round("def", "歼灭")
	elif def_alive == 0:
		end_round("atk", "歼灭")

func _check_elim_planted() -> void:
	var def_alive := 0
	for e in main.combatants():
		if e.alive and side_of(e) == "def":
			def_alive += 1
	if def_alive == 0:
		end_round("atk", "歼灭")

func end_round(winner_side: String, reason: String) -> void:
	if phase == "end" or phase == "over":
		return
	phase = "end"
	t_phase = now() + 5.0
	var winner_team := "ally" if side_of_team("ally") == winner_side else "enemy"
	score[winner_team] += 1
	# 经济：全队发放（含 bot）
	for e in main.combatants():
		if e == main.player and main.player.observer:
			continue
		var won: bool = (e.team == winner_team)
		var bonus: int = 3000 if won else 1900 + mini(loss_streak[e.team], 2) * 500
		e.money = mini(9000, e.money + bonus)
	loss_streak[winner_team] = 0
	var loser := "enemy" if winner_team == "ally" else "ally"
	loss_streak[loser] += 1
	main.hud.banner("%s 获胜 — %s" % ["我方" if winner_team == "ally" else "敌方", reason])
	main.sfx.play("round_win" if winner_team == "ally" else "round_lose")

func _halftime_reset() -> void:
	for e in main.combatants():
		e.money = 800
		e.ult_points = 0
		if e == main.player:
			e.primary = {}
			e.secondary = Weapons.make("classic")
			e.weapon = e.secondary
			e.slot = "secondary"
			e.armor = 0
		else:
			e.weapon = Weapons.make("classic")
	main.hud.banner("换边 — 经济重置")

var _plant_ent: Node = null
var _last_plant_t := -9.0
var _defuse_ent: Node = null
var _last_defuse_t := -9.0

func _channel_watch() -> void:
	var n := now()
	# 下包松手：进度清零（对齐无畏契约）
	if _plant_ent != null and n - _last_plant_t > 0.3:
		if is_instance_valid(_plant_ent):
			_plant_ent.channel = ""
		_plant_ent = null
		spike_prog = 0.0
	# 拆包松手：保留半拆检查点（3.5s）
	if _defuse_ent != null and n - _last_defuse_t > 0.3:
		if is_instance_valid(_defuse_ent):
			_defuse_ent.channel = ""
		_defuse_ent = null
		defuse_prog = 3.5 if defuse_prog >= 3.5 else 0.0

func side_of_team(t: String) -> String:
	return ally_side if t == "ally" else ("def" if ally_side == "atk" else "atk")

var report_text := ""
var _report_dealt := {}

func record_damage(attacker: Node, victim: Node, dmg: float) -> void:
	if attacker == main.player and victim != main.player:
		var nm: String = victim.agent_name
		_report_dealt[nm] = _report_dealt.get(nm, 0.0) + dmg

func on_death(ent: Node, killer: Node) -> void:
	if killer != null and is_instance_valid(killer) and killer != ent:
		killer.kills += 1
		killer.ult_points = mini(9, killer.ult_points + 1)
		if "money" in killer:
			killer.money = mini(9000, killer.money + 200)
		var kn: String = killer.agent_name if "agent_name" in killer else "你"
		var vn: String = ent.agent_name if "agent_name" in ent else "你"
		main.hud.kill_msg("%s ✖ %s" % [kn, vn])
		if killer == main.player:
			main.sfx.play("kill")
	if ent == spike_carrier:
		spike_carrier = null
		spike_state = "dropped"
		spike_pos = ent.global_position
	if phase == "live":
		_check_elim()
	elif phase == "planted":
		_check_elim_planted()

func plant_tick(ent: Node, dt: float) -> void:
	if phase != "live" or spike_carrier != ent:
		return
	if main.map.in_site(ent.global_position) == "":
		ent.channel = ""
		return
	ent.channel = "plant"
	_plant_ent = ent
	_last_plant_t = now()
	spike_prog += dt
	if spike_prog >= PLANT_TIME:
		ent.channel = ""
		spike_state = "planted"
		spike_pos = ent.global_position
		spike_carrier = null
		explode_at = now() + SPIKE_TIME
		phase = "planted"
		t_phase = explode_at
		main.spawn_spike_mesh(spike_pos)
		main.hud.banner("SPIKE 已安放 — 45 秒")
		main.sfx.play("planted")
		# 下包全队奖励：+300 金钱 +1 大招点
		for e in main.combatants():
			if side_of(e) == "atk":
				e.money = mini(9000, e.money + 300)
				e.ult_points = mini(9, e.ult_points + 1)

func defuse_tick(ent: Node, dt: float) -> void:
	if phase != "planted":
		return
	if ent.global_position.distance_to(spike_pos) > 2.2:
		ent.channel = ""
		return
	ent.channel = "defuse"
	_defuse_ent = ent
	_last_defuse_t = now()
	defuse_prog += dt
	if defuse_prog >= DEFUSE_TIME:
		ent.channel = ""
		main.sfx.play("defused")
		end_round("def", "拆除成功")

func player_interact(p: Node, dt: float) -> void:
	if side_of(p) == "atk" and phase == "live" and spike_carrier == p:
		plant_tick(p, dt)
	elif side_of(p) == "def" and phase == "planted":
		defuse_tick(p, dt)
	# 玩家拾取掉落炸弹
	if side_of(p) == "atk" and spike_state == "dropped" and p.global_position.distance_to(spike_pos) < 1.6:
		spike_carrier = p
		spike_state = "carried"

func bot_think(bot: Node, n: float) -> void:
	var side := side_of(bot)
	if phase == "buy":
		if side == "def":
			_assign_def_post(bot)
		return
	if phase == "planted":
		if side == "def":
			# 第一位活着的防守 bot 负责拆包，其余人在附近掩护架枪
			var defuser: Node = null
			for e in main.combatants():
				if e.alive and side_of(e) == "def" and e != main.player:
					defuser = e
					break
			if bot == defuser:
				if bot.state != "defuse":
					bot.state = "defuse"
					bot.set_goal(spike_pos)
				var safe: bool = bot.target == null and n - bot.last_hurt_at > 1.5
				if bot.global_position.distance_to(spike_pos) < 2.0 and safe:
					defuse_tick(bot, 0.15)
			else:
				if bot.state != "cover":
					bot.state = "cover"
					var ang := randf() * TAU
					bot.set_goal(spike_pos + Vector3(cos(ang) * 7.0, 0, sin(ang) * 7.0))
					bot.hold_look = spike_pos
		else:
			_assign_post_plant_hold(bot)
		return
	if phase != "live":
		return
	# 拾取掉落炸弹：单人认领（web 版 sp.claimer），其他人继续任务
	if side == "atk" and spike_state == "dropped":
		if spike_claimer == null or not is_instance_valid(spike_claimer) or not spike_claimer.alive:
			spike_claimer = bot
		if spike_claimer == bot:
			if bot.state != "fetch":
				bot.state = "fetch"
				bot.set_goal(spike_pos)
			if bot.global_position.distance_to(spike_pos) < 1.6:
				spike_carrier = bot
				spike_state = "carried"
				spike_claimer = null
				bot.state = "wait"
			return
	if side == "atk":
		# 残血刚受伤且非携弹者：回撤找队友（更像人）
		if bot.hp < 32 and n - bot.last_hurt_at < 2.5 and not bot.fell_back and spike_carrier != bot and bot.state != "fallback":
			bot.fell_back = true
			bot.state = "fallback"
			bot.fallback_until = n + randf_range(3.5, 5.5)
			var dest := Vector3(bot.global_position.x * 0.5, 0, clampf(bot.global_position.z + 16.0, -36.0, 36.0))
			for e in main.combatants():
				if e != bot and e.alive and e.team == bot.team and e.global_position.distance_to(bot.global_position) > 6.0:
					dest = e.global_position
					break
			bot.set_goal(dest)
			return
		if bot.state == "fallback":
			if n > bot.fallback_until or bot.hp > 55:
				bot.state = "wait"
			else:
				return
		if spike_carrier == bot:
			var plant: Vector3 = main.map.sites[plan_site]["plant"]
			if main.map.in_site(bot.global_position) == plan_site and bot.global_position.distance_to(plant) < 4.5:
				bot.state = "plant"
				bot.velocity = Vector3.ZERO
				plant_tick(bot, 0.15)
			else:
				if bot.state != "execute":
					bot.state = "execute"
					bot.set_goal(plant)
		else:
			if execute_called:
				var holds: Array = main.map.atk_holds.get(plan_site, [])
				if holds.size() > 0 and bot.state != "execute" and bot.state != "hold":
					bot.state = "execute"
					var h: Dictionary = holds[bot.get_instance_id() % holds.size()]
					bot.set_goal(h["p"])
					bot.hold_look = h["look"]
				elif bot.state == "execute" and bot.nav_finished():
					bot.state = "hold"
			elif bot.state == "wait":
				bot.state = "advance"
				var st: Vector3 = main.map.stages.get(plan_site, main.map.sites[plan_site]["plant"])
				var dest: Vector3 = st
				if bot.assault_role == "flank" and spike_carrier != bot and main.map.sites.size() > 1:
					# 绕后手：先去另一个点方向牵制，执行时再转点
					for k in main.map.sites.keys():
						if k != plan_site:
							dest = main.map.stages.get(k, main.map.sites[k]["plant"])
							break
				elif bot.assault_role == "scout":
					dest = st + Vector3(randf_range(-5.0, 5.0), 0, randf_range(-5.0, 5.0))
				bot.set_goal(dest + Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0)))
			elif bot.state == "advance" and bot.nav_finished():
				bot.state = "stage"
				bot.stage_at = n
			elif bot.state == "stage":
				# 集结：足够队友到场或超时 → 全队执行（web 版 executeT 逻辑）
				var stage_pos: Vector3 = main.map.stages.get(plan_site, main.map.sites[plan_site]["plant"])
				var mates := 0
				var near := 0
				for e in main.combatants():
					if e.alive and side_of(e) == "atk" and e != main.player and e.assault_role != "flank":
						mates += 1
						if e.global_position.distance_to(stage_pos) < 13.0:
							near += 1
				if near >= maxi(1, int(ceil(mates * 0.6))) or n - bot.stage_at > 5.0:
					execute_called = true
				elif n >= bot.next_regroup:
					# 集结等待时小范围游走警戒
					bot.next_regroup = n + randf_range(2.0, 3.5)
					bot.set_goal(stage_pos + Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0)))
	else:
		_assign_def_post(bot)
		# 长时间无事：小概率轮换驻点，保持地图控制
		if bot.state == "post" and bot.nav_finished() and n >= bot.next_regroup:
			bot.next_regroup = n + randf_range(8.0, 14.0)
			if randf() < 0.35:
				var posts: Array = main.map.def_posts
				if posts.size() > 1:
					var p: Dictionary = posts[randi() % posts.size()]
					bot.set_goal(p["p"])
					bot.hold_look = p["look"]

func _assign_def_post(bot: Node) -> void:
	if bot.state == "post":
		return
	var posts: Array = main.map.def_posts
	if posts.is_empty():
		return
	var p: Dictionary = posts[bot.get_instance_id() % posts.size()]
	bot.state = "post"
	bot.set_goal(p["p"])
	bot.hold_look = p["look"]

func _assign_post_plant_hold(bot: Node) -> void:
	var n := now()
	# 敌人正在拆包且被察觉（看得见或离得近）→ 全力回防
	if defuse_prog > 0.4:
		var defusing: Node = null
		for e in main.combatants():
			if e.alive and side_of(e) == "def" and e.channel == "defuse":
				defusing = e
				break
		if defusing != null:
			var seen: bool = main.has_los(bot.eye_pos(), defusing.eye_pos(), [bot, defusing])
			var close: bool = bot.global_position.distance_to(spike_pos) < 20.0
			if seen or close:
				if bot.state != "retake":
					bot.state = "retake"
					bot.set_goal(spike_pos)
					bot.hold_look = Vector3.ZERO
				return
	if bot.state == "retake" and bot.nav_finished():
		bot.state = "wait"
	if bot.state == "hold_pp":
		# 守包不发呆：周期换守位（架点之间轮换 / 绕包环形位）
		if bot.nav_finished() and n >= bot.next_regroup:
			bot.next_regroup = n + randf_range(7.0, 12.0)
			var site_key: String = main.map.in_site(spike_pos)
			var holds2: Array = main.map.atk_holds.get(site_key if site_key != "" else plan_site, [])
			if holds2.size() > 0 and randf() < 0.6:
				var h2: Dictionary = holds2[randi() % holds2.size()]
				bot.set_goal(h2["p"])
				bot.hold_look = h2["look"]
			else:
				var ang := randf() * TAU
				bot.set_goal(spike_pos + Vector3(cos(ang) * 8.0, 0, sin(ang) * 8.0))
				bot.hold_look = spike_pos
		return
	bot.state = "hold_pp"
	bot.next_regroup = n + randf_range(7.0, 12.0)
	var site_key0: String = main.map.in_site(spike_pos)
	var holds: Array = main.map.atk_holds.get(site_key0 if site_key0 != "" else plan_site, [])
	if holds.size() > 0:
		var h: Dictionary = holds[bot.get_instance_id() % holds.size()]
		bot.set_goal(h["p"])
		bot.hold_look = h["look"]
	else:
		var ang0 := randf() * TAU
		bot.set_goal(spike_pos + Vector3(cos(ang0) * 7.0, 0, sin(ang0) * 7.0))
		bot.hold_look = spike_pos

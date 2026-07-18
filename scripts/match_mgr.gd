# match_mgr.gd — 回合循环：购买/交战/下包/拆包/结算/换边/经济
extends Node

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
var spike_pos := Vector3.ZERO
var spike_prog := 0.0
var defuse_prog := 0.0
var explode_at := 0.0
var plan_site := "A"
var execute_called := false
var live_start := 0.0
var loss_streak := { "ally": 0, "enemy": 0 }
var _next_beep := 0.0

func setup(m: Node3D) -> void:
	main = m
	start_round()

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
	for e in main.combatants():
		if side_of(e) == "atk" and e != main.player and e.alive:
			spike_carrier = e
			break
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
	match phase:
		"buy":
			if n >= t_phase:
				phase = "live"
				live_start = n
				t_phase = n + ROUND_TIME
				main.map.remove_barriers()
				main.hud.banner("行动开始")
				main.sfx.play("round_start")
		"live":
			if n >= t_phase:
				end_round("def", "时间耗尽")
			elif n >= live_start + 12.0 and not execute_called:
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
	# 经济
	if not main.player.observer:
		var won_player: bool = (main.player.team == winner_team)
		var bonus: int = 3000 if won_player else 1900 + mini(loss_streak[main.player.team], 2) * 500
		main.player.money = mini(9000, main.player.money + bonus)
	loss_streak[winner_team] = 0
	var loser := "enemy" if winner_team == "ally" else "ally"
	loss_streak[loser] += 1
	main.hud.banner("%s 获胜 — %s" % ["我方" if winner_team == "ally" else "敌方", reason])
	main.sfx.play("round_win" if winner_team == "ally" else "round_lose")

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

func defuse_tick(ent: Node, dt: float) -> void:
	if phase != "planted":
		return
	if ent.global_position.distance_to(spike_pos) > 2.2:
		ent.channel = ""
		return
	ent.channel = "defuse"
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
			bot.state = "defuse"
			bot.set_goal(spike_pos)
			if bot.global_position.distance_to(spike_pos) < 2.0:
				defuse_tick(bot, 0.15)
		else:
			_assign_post_plant_hold(bot)
		return
	if phase != "live":
		return
	# 拾取掉落炸弹
	if side == "atk" and spike_state == "dropped":
		bot.state = "fetch"
		bot.set_goal(spike_pos)
		if bot.global_position.distance_to(spike_pos) < 1.6:
			spike_carrier = bot
			spike_state = "carried"
		return
	if side == "atk":
		if spike_carrier == bot:
			var plant: Vector3 = main.map.sites[plan_site]["plant"]
			if main.map.in_site(bot.global_position) == plan_site and bot.global_position.distance_to(plant) < 4.5:
				bot.state = "plant"
				bot.velocity = Vector3.ZERO
				plant_tick(bot, 0.15)
			else:
				bot.state = "execute"
				bot.set_goal(plant)
		else:
			if execute_called:
				var holds: Array = main.map.atk_holds.get(plan_site, [])
				if holds.size() > 0 and bot.state != "execute":
					bot.state = "execute"
					var h: Dictionary = holds[bot.get_instance_id() % holds.size()]
					bot.set_goal(h["p"])
					bot.hold_look = h["look"]
			elif bot.state == "wait":
				bot.state = "advance"
				var st: Vector3 = main.map.stages.get(plan_site, main.map.sites[plan_site]["plant"])
				bot.set_goal(st)
			elif bot.state == "advance" and bot.nav_finished() and n >= bot.next_regroup:
				# 到位后不再原地发呆：护送炸弹手 / 绕集结点游走
				bot.next_regroup = n + randf_range(2.0, 3.5)
				var anchor: Vector3 = main.map.stages.get(plan_site, main.map.sites[plan_site]["plant"])
				if spike_carrier != null and is_instance_valid(spike_carrier) and spike_carrier.alive:
					anchor = spike_carrier.global_position
				bot.set_goal(anchor + Vector3(randf_range(-4.0, 4.0), 0, randf_range(-4.0, 4.0)))
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
	if bot.state == "hold_pp":
		return
	bot.state = "hold_pp"
	var holds: Array = main.map.atk_holds.get(plan_site, [])
	if holds.size() > 0:
		var h: Dictionary = holds[bot.get_instance_id() % holds.size()]
		bot.set_goal(h["p"])
		bot.hold_look = h["look"]

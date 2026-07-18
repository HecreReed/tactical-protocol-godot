# sfx.gd — 程序化音效合成（1:1 移植网页版 audio.js：噪声层+振荡器层，指数衰减+滤波）
extends Node

const SR := 22050

var volume := 0.8
var _streams: Dictionary = {}
var _players: Array = []
var _pi := 0

func _ready() -> void:
	for i in range(14):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_gen_all()

# ---------------- 合成器 ----------------
static func _mk(dur: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(SR * dur))
	return buf

static func _tone(buf: PackedFloat32Array, f: float, f2: float, wave: String, vol: float, dur: float, delay: float = 0.0) -> void:
	var n := mini(buf.size(), int(SR * (dur + delay)))
	var start := int(SR * delay)
	var phase := 0.0
	for i in range(start, n):
		var t := float(i - start) / SR
		var k := t / dur
		var freq := f * pow(maxf(1.0, f2) / f, k) if f2 > 0 else f
		phase += freq / SR
		var s: float
		var ph := fmod(phase, 1.0)
		match wave:
			"square": s = 1.0 if ph < 0.5 else -1.0
			"sawtooth": s = ph * 2.0 - 1.0
			"triangle": s = 4.0 * absf(ph - 0.5) - 1.0
			_: s = sin(phase * TAU)
		var env := vol * pow(0.001 / vol, k) if vol > 0.001 else 0.0
		buf[i] += s * env

static func _noise(buf: PackedFloat32Array, vol: float, lp: float, hp: float, decay: float, dur: float, delay: float = 0.0) -> void:
	var n := mini(buf.size(), int(SR * (dur + delay)))
	var start := int(SR * delay)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var lp_a := 1.0 - exp(-TAU * lp / SR) if lp < 11000 else 1.0
	var hp_a := exp(-TAU * hp / SR) if hp > 0 else 0.0
	var y := 0.0
	var hx := 0.0
	var hy := 0.0
	for i in range(start, n):
		var t := float(i - start) / SR
		var x := rng.randf_range(-1.0, 1.0)
		y += lp_a * (x - y)
		var s := y
		if hp > 0:
			hy = hp_a * (hy + s - hx)
			hx = s
			s = hy
		var env := vol * pow(0.001 / maxf(vol, 0.002), t / decay)
		buf[i] += s * env

static func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var pcm := PackedByteArray()
	pcm.resize(buf.size() * 2)
	for i in range(buf.size()):
		var v := int(clampf(buf[i], -1.0, 1.0) * 32000.0)
		pcm.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.data = pcm
	return w

func _gen_all() -> void:
	var b: PackedFloat32Array
	# 枪声（按类别）
	b = _mk(0.5); _noise(b, 0.32, 3800, 0, 0.09, 0.4); _tone(b, 190, 60, "triangle", 0.2, 0.07); _streams["shot_pistol"] = _wav(b)
	b = _mk(0.4); _noise(b, 0.26, 4200, 0, 0.06, 0.3); _tone(b, 220, 80, "square", 0.1, 0.05); _streams["shot_smg"] = _wav(b)
	b = _mk(0.55); _noise(b, 0.38, 3200, 0, 0.11, 0.45); _tone(b, 150, 48, "sawtooth", 0.22, 0.09); _streams["shot_rifle"] = _wav(b)
	b = _mk(1.1); _noise(b, 0.5, 2200, 0, 0.3, 1.0); _tone(b, 100, 30, "sawtooth", 0.3, 0.25); _streams["shot_sniper"] = _wav(b)
	b = _mk(0.45); _noise(b, 0.3, 2800, 0, 0.09, 0.35); _tone(b, 130, 55, "square", 0.16, 0.07); _streams["shot_heavy"] = _wav(b)
	b = _mk(0.8); _noise(b, 0.5, 2500, 0, 0.18, 0.7); _tone(b, 90, 35, "sawtooth", 0.28, 0.14); _streams["shot_shotgun"] = _wav(b)
	b = _mk(0.3); _noise(b, 0.12, 11000, 2000, 0.06, 0.25); _streams["shot_melee"] = _wav(b)
	# 换弹 / 干火 / 脚步
	b = _mk(0.5); _tone(b, 800, 500, "square", 0.06, 0.05); _tone(b, 500, 900, "square", 0.06, 0.05, 0.25); _streams["reload"] = _wav(b)
	b = _mk(0.08); _tone(b, 1200, 0, "square", 0.05, 0.03); _streams["dry"] = _wav(b)
	b = _mk(0.2); _noise(b, 0.045, 900, 300, 0.05, 0.15); _streams["step"] = _wav(b)
	# 命中 / 爆头 / 击杀 / 受伤
	b = _mk(0.12); _tone(b, 1300, 0, "square", 0.09, 0.04); _streams["hit"] = _wav(b)
	b = _mk(0.15); _tone(b, 1900, 2400, "square", 0.11, 0.07); _streams["headshot"] = _wav(b)
	b = _mk(0.45); _tone(b, 520, 780, "sine", 0.12, 0.12); _tone(b, 780, 1040, "sine", 0.1, 0.12, 0.08); _streams["kill"] = _wav(b)
	b = _mk(0.4); _noise(b, 0.18, 900, 0, 0.12, 0.3); _tone(b, 180, 90, "sawtooth", 0.1, 0.1); _streams["hurt"] = _wav(b)
	# 爆炸 / 烟雾 / 闪光
	b = _mk(1.6); _noise(b, 0.7, 1200, 0, 0.9, 1.2); _tone(b, 60, 24, "sine", 0.5, 1.0); _streams["explosion"] = _wav(b)
	b = _mk(0.7); _noise(b, 0.2, 800, 0, 0.3, 0.6); _streams["smoke_pop"] = _wav(b)
	b = _mk(0.7); _tone(b, 2400, 3200, "sine", 0.22, 0.35); _noise(b, 0.18, 11000, 3000, 0.12, 0.4); _streams["flash_pop"] = _wav(b)
	# 下包 / 拆包 / 回合
	b = _mk(0.7); _tone(b, 600, 900, "sine", 0.14, 0.2); _tone(b, 900, 1200, "sine", 0.12, 0.25, 0.15); _streams["planted"] = _wav(b)
	b = _mk(0.5); _tone(b, 900, 1400, "sine", 0.14, 0.3); _streams["defused"] = _wav(b)
	b = _mk(0.12); _tone(b, 980, 0, "square", 0.09, 0.07); _streams["beep"] = _wav(b)
	b = _mk(0.12); _tone(b, 1120, 0, "square", 0.09, 0.07); _streams["beep_fast"] = _wav(b)
	b = _mk(0.5); _tone(b, 520, 0, "sine", 0.1, 0.1); _tone(b, 660, 0, "sine", 0.1, 0.14, 0.12); _streams["round_start"] = _wav(b)
	b = _mk(1.0); var i := 0
	for f in [523.0, 659.0, 784.0, 1046.0]:
		_tone(b, f, 0, "sine", 0.12, 0.18, i * 0.11); i += 1
	_streams["round_win"] = _wav(b)
	b = _mk(1.0); i = 0
	for f in [392.0, 330.0, 262.0]:
		_tone(b, f, 0, "triangle", 0.12, 0.22, i * 0.13); i += 1
	_streams["round_lose"] = _wav(b)
	# 购买 / 拒绝 / 技能
	b = _mk(0.2); _tone(b, 1000, 1400, "sine", 0.08, 0.08); _streams["buy"] = _wav(b)
	b = _mk(0.15); _tone(b, 220, 0, "square", 0.07, 0.09); _streams["deny"] = _wav(b)
	b = _mk(0.3); _tone(b, 700, 1100, "sine", 0.1, 0.15); _streams["ability"] = _wav(b)

# ---------------- 播放 ----------------
func play(id: String, dist: float = 0.0) -> void:
	if not _streams.has(id):
		return
	var v: float = clampf(1.0 / (1.0 + dist * 0.09), 0.03, 1.0) * volume
	if v < 0.035:
		return
	var p: AudioStreamPlayer = _players[_pi % _players.size()]
	_pi += 1
	p.stream = _streams[id]
	p.volume_db = linear_to_db(v)
	p.play()

func shot(cat: String, dist: float = 0.0) -> void:
	play("shot_" + cat, dist)

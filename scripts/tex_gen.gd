# tex_gen.gd — 程序化纹理生成（1:1 移植网页版 Canvas 纹理：墙面/地面主题/木箱/金属）

static var _cache: Dictionary = {}

static func _img(size: int = 256) -> Image:
	return Image.create(size, size, false, Image.FORMAT_RGB8)

static func _fill(img: Image, c: Color) -> void:
	img.fill(c)

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= 1.0:
		img.set_pixel(x, y, c)
	else:
		img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(c.r, c.g, c.b), c.a))

static func _rect(img: Image, x: float, y: float, w: float, h: float, c: Color) -> void:
	for yy in range(int(y), int(y + h) + 1):
		for xx in range(int(x), int(x + w) + 1):
			_px(img, xx, yy, c)

static func _hline(img: Image, y: float, c: Color, lw: int = 1) -> void:
	for dy in range(lw):
		for x in range(img.get_width()):
			_px(img, x, int(y) + dy, c)

static func _vline(img: Image, x: float, c: Color, lw: int = 1) -> void:
	for dx in range(lw):
		for y in range(img.get_height()):
			_px(img, int(x) + dx, y, c)

static func _line(img: Image, x0: float, y0: float, x1: float, y1: float, c: Color, lw: float = 1.0) -> void:
	var d := Vector2(x1 - x0, y1 - y0)
	var n := int(maxf(absf(d.x), absf(d.y))) + 1
	var r := int(ceilf(lw * 0.5))
	for i in range(n + 1):
		var t := float(i) / float(n)
		var cx := int(x0 + d.x * t)
		var cy := int(y0 + d.y * t)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy <= r * r:
					_px(img, cx + dx, cy + dy, c)

static func _dot(img: Image, x: float, y: float, r: float, c: Color) -> void:
	var ri := int(ceilf(r))
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy <= r * r:
				_px(img, int(x) + dx, int(y) + dy, c)

static func _speckle(img: Image, n: int, sz_min: float, sz_max: float, a_min: float, a_max: float, rng: RandomNumberGenerator) -> void:
	for i in range(n):
		var v := 1.0 if rng.randf() < 0.5 else 0.1
		var c := Color(v, v, v, rng.randf_range(a_min, a_max))
		var s := rng.randf_range(sz_min, sz_max)
		_rect(img, rng.randf() * 256.0, rng.randf() * 256.0, s, s, c)

static func _vstreak(img: Image, x: float, y0: float, w: float, h: float, c: Color) -> void:
	for yy in range(int(y0), int(y0 + h)):
		var t := 1.0 - float(yy - int(y0)) / h
		for xx in range(int(x), int(x + w)):
			_px(img, xx, yy, Color(c.r, c.g, c.b, c.a * t))

static func _tex(img: Image) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

# ---------------- 混凝土墙板 ----------------
static func wall() -> ImageTexture:
	if _cache.has("wall"):
		return _cache["wall"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var img := _img()
	_fill(img, Color8(143, 152, 158))
	_speckle(img, 700, 2, 5, 0.02, 0.07, rng)
	for y in range(0, 257, 64):
		_hline(img, y, Color(0.08, 0.10, 0.13, 0.5), 3)
		_hline(img, y + 3, Color(1, 1, 1, 0.10), 1)
	for x in range(0, 257, 128):
		_vline(img, x, Color(0.08, 0.10, 0.13, 0.5), 3)
	for i in range(14):
		var x := rng.randf() * 256.0
		var h := 30.0 + rng.randf() * 90.0
		var y0 := 64.0 * (1 + floorf(rng.randf() * 3.0))
		_vstreak(img, x, y0, 3.0 + rng.randf() * 5.0, h, Color(0.12, 0.14, 0.16, 0.22))
	for y in range(8, 256, 64):
		for x in range(8, 256, 32):
			_dot(img, x, y, 2.2, Color(0.09, 0.12, 0.14, 0.7))
	for yy in range(200, 256):
		var t := float(yy - 200) / 56.0
		_hline(img, yy, Color(0.10, 0.12, 0.10, 0.35 * t), 1)
	_cache["wall"] = _tex(img)
	return _cache["wall"]

# ---------------- 地面（六主题） ----------------
static func floor_theme(theme: String) -> ImageTexture:
	var key := "floor_" + theme
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var img := _img()
	match theme:
		"terrace":
			_fill(img, Color8(168, 154, 134))
			_speckle(img, 700, 2, 2, 0.03, 0.08, rng)
			for ring in range(9):
				var cx := 128.0 + sin(ring * 2.3) * 40.0
				var cy := 128.0 + cos(ring * 1.7) * 40.0
				var base_r := 22.0 + ring * 16.0
				var prev := Vector2.ZERO
				var a := 0.0
				while a <= TAU + 0.01:
					var rr := base_r + sin(a * 3.0 + ring) * 8.0 + cos(a * 5.0 - ring * 2.0) * 5.0
					var p := Vector2(cx + cos(a) * rr, cy + sin(a) * rr)
					if a > 0.0:
						_line(img, prev.x, prev.y, p.x, p.y, Color(0.27, 0.23, 0.18, 0.34 - ring * 0.02), 2.4)
					prev = p
					a += 0.22
		"snow":
			_fill(img, Color8(222, 230, 236))
			for i in range(26):
				var x := rng.randf() * 256.0
				var y := rng.randf() * 256.0
				var r := 14.0 + rng.randf() * 36.0
				var ri := int(r)
				for dy in range(-ri, ri + 1):
					for dx in range(-ri, ri + 1):
						var dd := sqrt(float(dx * dx + dy * dy))
						if dd <= r:
							_px(img, int(x) + dx, int(y) + dy, Color(1, 1, 1, 0.5 * (1.0 - dd / r)))
			for i in range(8):
				var x := rng.randf() * 256.0
				var y := rng.randf() * 256.0
				for j in range(4):
					var x2 := x + rng.randf_range(-35, 35)
					var y2 := y + rng.randf_range(-35, 35)
					_line(img, x, y, x2, y2, Color(0.47, 0.55, 0.63, 0.24), 1.6)
					x = x2; y = y2
		"tile":
			_fill(img, Color8(194, 181, 152))
			_speckle(img, 550, 2.5, 2.5, 0.04, 0.09, rng)
			for v in range(0, 257, 64):
				_vline(img, v, Color(0.28, 0.24, 0.17, 0.5), 3)
				_hline(img, v, Color(0.28, 0.24, 0.17, 0.5), 3)
			for v in range(32, 256, 64):
				_vline(img, v, Color(0.28, 0.24, 0.17, 0.25), 1)
				_hline(img, v, Color(0.28, 0.24, 0.17, 0.25), 1)
		"asphalt":
			_fill(img, Color8(117, 121, 127))
			_speckle(img, 1100, 1.6, 1.6, 0.04, 0.09, rng)
			var y := 0
			while y < 256:
				_rect(img, 126, y, 5, 26, Color(0.89, 0.84, 0.59, 0.55))
				y += 46
			for i in range(6):
				var x := rng.randf() * 256.0
				var yy := rng.randf() * 256.0
				for j in range(5):
					var x2 := x + rng.randf_range(-25, 25)
					var y2 := yy + rng.randf_range(-25, 25)
					_line(img, x, yy, x2, y2, Color(0.14, 0.16, 0.18, 0.5), 1.6)
					x = x2; yy = y2
		"deck":
			_fill(img, Color8(149, 162, 172))
			for v in range(0, 257, 85):
				_vline(img, v, Color(0.16, 0.20, 0.23, 0.5), 3)
				_hline(img, v, Color(0.16, 0.20, 0.23, 0.5), 3)
			for y2 in range(12, 256, 28):
				for x2 in range(12, 256, 28):
					_rect(img, x2, y2, 7, 3, Color(0.20, 0.24, 0.27, 0.6))
		_:
			_fill(img, Color8(168, 176, 181))
			_speckle(img, 900, 1.5, 4, 0.03, 0.09, rng)
			_vline(img, 128, Color(0.16, 0.19, 0.21, 0.5), 3)
			_hline(img, 128, Color(0.16, 0.19, 0.21, 0.5), 3)
			_vline(img, 0, Color(0.16, 0.19, 0.21, 0.5), 3)
			_hline(img, 0, Color(0.16, 0.19, 0.21, 0.5), 3)
			for i in range(7):
				var x := rng.randf() * 256.0
				var y := rng.randf() * 256.0
				for j in range(5):
					var x2 := x + rng.randf_range(-22, 22)
					var y2 := y + rng.randf_range(-22, 22)
					_line(img, x, y, x2, y2, Color(0.20, 0.22, 0.24, 0.45), 1.4)
					x = x2; y = y2
			_rect(img, 196, 196, 40, 40, Color(0.14, 0.16, 0.19, 0.8))
			for i in range(5):
				_line(img, 200, 200 + i * 8, 232, 200 + i * 8, Color(0.35, 0.39, 0.42, 0.9), 2)
	_cache[key] = _tex(img)
	return _cache[key]

# ---------------- 木箱 ----------------
static func crate() -> ImageTexture:
	if _cache.has("crate"):
		return _cache["crate"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var img := _img()
	_fill(img, Color8(125, 104, 80))
	for i in range(40):
		var y := rng.randf() * 256.0
		var c := Color(rng.randf_range(0.16, 0.28), rng.randf_range(0.11, 0.20), rng.randf_range(0.06, 0.12), rng.randf_range(0.14, 0.32))
		var lw := 1.0 + rng.randf() * 2.0
		var px := 0.0
		var py := y
		for seg in range(4):
			var nx := px + 64.0
			var ny := y + rng.randf_range(-5, 5)
			_line(img, px, py, nx, ny, c, lw)
			px = nx; py = ny
	for y in range(0, 257, 42):
		_hline(img, y, Color(0.12, 0.09, 0.05, 0.6), 5)
	for y in range(20, 257, 42):
		_hline(img, y, Color(1.0, 0.92, 0.78, 0.14), 2)
	var corner := Color(0.20, 0.23, 0.25, 0.95)
	_rect(img, 0, 0, 34, 10, corner); _rect(img, 0, 0, 10, 34, corner)
	_rect(img, 222, 0, 34, 10, corner); _rect(img, 246, 0, 10, 34, corner)
	_rect(img, 0, 246, 34, 10, corner); _rect(img, 0, 222, 10, 34, corner)
	_rect(img, 222, 246, 34, 10, corner); _rect(img, 246, 222, 10, 34, corner)
	var rivet := Color(0.71, 0.75, 0.78, 0.85)
	for p in [[6, 6], [28, 6], [6, 28], [250, 6], [228, 6], [250, 28], [6, 250], [28, 250], [6, 228], [250, 250], [228, 250], [250, 228]]:
		_dot(img, p[0], p[1], 2.4, rivet)
	var stamp := Color(0.12, 0.09, 0.06, 0.5)
	_line(img, 88, 112, 168, 112, stamp, 2); _line(img, 88, 152, 168, 152, stamp, 2)
	_line(img, 88, 112, 88, 152, stamp, 2); _line(img, 168, 112, 168, 152, stamp, 2)
	_line(img, 100, 140, 100, 124, stamp, 3); _line(img, 96, 124, 104, 124, stamp, 3)
	_line(img, 112, 124, 112, 140, stamp, 3); _line(img, 112, 124, 120, 124, stamp, 3)
	_line(img, 120, 124, 120, 132, stamp, 3); _line(img, 112, 132, 120, 132, stamp, 3)
	_cache["crate"] = _tex(img)
	return _cache["crate"]

# ---------------- 金属拉丝板 ----------------
static func metal() -> ImageTexture:
	if _cache.has("metal"):
		return _cache["metal"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var img := _img()
	_fill(img, Color8(126, 138, 146))
	for i in range(160):
		var v := 0.92 if rng.randf() < 0.5 else 0.26
		_hline(img, rng.randf() * 256.0, Color(v, v, v, rng.randf_range(0.03, 0.08)), 1)
	var seam := Color(0.12, 0.15, 0.17, 0.6)
	_hline(img, 14, seam, 3); _hline(img, 239, seam, 3)
	_vline(img, 14, seam, 3); _vline(img, 239, seam, 3)
	var screw := Color(0.12, 0.15, 0.17, 0.8)
	for p in [[22, 22], [234, 22], [22, 234], [234, 234], [128, 22], [128, 234], [22, 128], [234, 128]]:
		_dot(img, p[0], p[1], 3, screw)
	for x in range(-40, 300, 28):
		var warn := Color(0.86, 0.71, 0.16, 0.5) if (x / 28) % 2 != 0 else Color(0.12, 0.13, 0.15, 0.5)
		for yy in range(108, 148):
			var shift := int((148 - yy) * 0.35)
			for xx in range(x + shift, x + shift + 14):
				_px(img, xx, yy, warn)
	_cache["metal"] = _tex(img)
	return _cache["metal"]

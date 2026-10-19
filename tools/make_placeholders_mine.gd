extends SceneTree
## 잠긴 채굴장(확장판) 임시 그림 생성기. 진짜 그림(ChatGPT)이 오기 전까지 '스킨 자리'를 채운다.
## EXPANSION.md 11장의 파일 이름 **그대로** 만든다 → 진짜 그림을 같은 이름으로 덮어쓰기만 하면 끝.
## 사용: /path/to/Godot --headless --path . --script tools/make_placeholders_mine.gd [-- --force]
## **이미 있는 파일은 건너뛴다** — 기획자가 진짜 그림을 같은 이름으로 넣어 두었으면 그대로 둔다. 임시 그림을 다시 만들려면 --force.
## 만드는 것:
##   art/bosses/boss_iron_pump_now.png (1536×1024 투명, 왼쪽을 보는 녹슨 펌프: 몸통·피스톤·관·심장(핵))
##   art/enemies/enemy_small_pump.png (1536×1024 투명, 왼쪽을 보는 작은 펌프 — art_faces_right=false)
##   art/objects/object_cracked_wall.png (512×1024 투명, 세로로 금 간 나무 벽 조각 — 벽의 크기에 맞춰 늘려 그린다)
##   art/objects/object_dew_cup.png / object_scripture_page.png (512×512 투명 아이콘)
##   art/backgrounds/bg_flooded_mine.png / bg_flooded_mine_boss.png (1536×1024, 붉은 녹과 수액빛)
##   (art/memories/memory_pump_1~3.png · boss_iron_pump_past.png 는 진짜 그림이 들어와 더 만들지 않는다)
##   (art/memories/ending_third_way.png 는 더 만들지 않는다 — ENDINGS.md 의 진엔딩 그림 ending_true_1~5.png 로 바뀜)
## 그림은 절반 크기로 계산한 뒤 두 배로 키운다 (부드럽고 4배 빠르다).

var _rng := RandomNumberGenerator.new()
var _force := false
var _made := 0


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	_force = "--force" in OS.get_cmdline_user_args() or "--force" in OS.get_cmdline_args()
	_make("res://art/bosses/boss_iron_pump_now.png", 1536, 1024, true, func(u: float, v: float) -> Color: return _pump(u, v, true))
	# boss_iron_pump_past.png · memory_pump_1~3.png 는 기획자의 진짜 그림이 들어왔고, ending_third_way.png 는 ENDINGS.md 의 진엔딩 그림 5장
	# (ending_true_1~5.png)으로 바뀌어 없어졌다 (2026-10-20) — 만들지 않는다 (--force 로도 덮어쓰지 않게)
	_make("res://art/enemies/enemy_small_pump.png", 1536, 1024, true, _small_pump)
	_make("res://art/objects/object_cracked_wall.png", 512, 1024, true, _cracked_wall)
	_make("res://art/objects/object_dew_cup.png", 512, 512, true, _dew_cup)
	_make("res://art/objects/object_scripture_page.png", 512, 512, true, _scripture_page)
	_make("res://art/backgrounds/bg_flooded_mine.png", 1536, 1024, false, _bg_flooded)
	_make("res://art/backgrounds/bg_flooded_mine_boss.png", 1536, 1024, false, _bg_flooded_boss)
	print("임시 그림 %d장 생성 (7장 중, 나머지는 이미 있어 건너뜀) (%.1f초)" % [_made, (Time.get_ticks_msec() - t0) / 1000.0])
	quit()


## 픽셀마다 shade(u, v) 를 불러 그림을 만든다 (u, v 는 0~1). 절반 크기로 계산해 키운다.
func _make(path: String, out_w: int, out_h: int, alpha: bool, shade: Callable) -> void:
	if not _force and FileAccess.file_exists(path):
		print("  ", path, "  이미 있음 — 건너뜀 (덮어쓰려면 --force)")
		return
	_made += 1
	_rng.seed = hash(path)
	var w := out_w / 2
	var h := out_h / 2
	var fmt := Image.FORMAT_RGBA8 if alpha else Image.FORMAT_RGB8
	var img := Image.create(w, h, false, fmt)
	for y in h:
		var v := (y + 0.5) / h
		for x in w:
			var c: Color = shade.call((x + 0.5) / w, v)
			img.set_pixel(x, y, c)
	img.resize(out_w, out_h, Image.INTERPOLATE_CUBIC)
	img.save_png(ProjectSettings.globalize_path(path))
	print("  ", path, "  ", out_w, "x", out_h)


# ---------- 도형 보조 ----------
## 타원 안쪽 거리 (0 중심 → 1 가장자리). aspect = 그림의 가로/세로 비 (원이 원으로 보이게).
static func _ell(u: float, v: float, cx: float, cy: float, rx: float, ry: float, rot := 0.0, aspect := 1.5) -> float:
	var dx := u - cx
	var dy := (v - cy) / aspect
	var c := cos(rot)
	var s := sin(rot)
	var ex := dx * c + dy * s
	var ey := -dx * s + dy * c
	return sqrt((ex * ex) / (rx * rx) + (ey * ey) / (ry * ry))


## 사각형 안이면 0 미만, 밖이면 거리 (u·v 단위, aspect 보정 없음).
static func _box(u: float, v: float, x0: float, y0: float, x1: float, y1: float) -> float:
	var dx := maxf(x0 - u, u - x1)
	var dy := maxf(y0 - v, v - y1)
	return maxf(dx, dy)


static func _hash2(x: float, y: float) -> float:
	var h := sin(x * 127.1 + y * 311.7) * 43758.5453
	return h - floor(h)


static func _noise(x: float, y: float) -> float:
	var ix := floorf(x)
	var iy := floorf(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash2(ix, iy)
	var b := _hash2(ix + 1.0, iy)
	var c := _hash2(ix, iy + 1.0)
	var d := _hash2(ix + 1.0, iy + 1.0)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _vein(u: float, v: float, scale: float) -> float:
	var n := _noise(u * scale, v * scale * 0.67)
	return clampf(1.0 - absf(n - 0.5) * 18.0, 0.0, 1.0)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2, aspect := 1.5) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	var q := a + ab * t
	return Vector2((p.x - q.x), (p.y - q.y) / aspect).length()


## 녹슨 금속 색: 바탕 붉은 녹 + 결 + 밝은 긁힘
func _rust(u: float, v: float, base: Color, shine := 0.0) -> Color:
	var n := _noise(u * 26.0, v * 18.0)
	var n2 := _noise(u * 90.0 + 3.0, v * 60.0)
	var c := base.lerp(Color(0.16, 0.08, 0.06, 1.0), n * 0.55)
	c = c.lerp(Color(0.62, 0.3, 0.16, 1.0), clampf((n2 - 0.7) * 4.0, 0.0, 1.0) * 0.5)
	if shine > 0.0:
		c = c.lerp(Color(0.85, 0.82, 0.7, 1.0), shine * clampf((n2 - 0.55) * 3.0, 0.0, 1.0))
	return c


# ---------- 무쇠 펌프 (지금) ----------
## 왼쪽을 보는 펌프 (왼쪽 = 앞). 몸통 상자 + 위의 실린더 + 배기관 + 가운데 심장. (피스톤 팔·관은 코드가 그린다)
## 발(바닥)은 v=0.96 쯤. 몸통은 u 0.33~0.72.
func _pump(u: float, v: float, sick: bool) -> Color:
	var col := Color(0, 0, 0, 0)
	var rust := Color(0.42, 0.17, 0.1, 1.0) if sick else Color(0.55, 0.5, 0.46, 1.0)
	var dark := Color(0.2, 0.09, 0.07, 1.0) if sick else Color(0.3, 0.28, 0.27, 1.0)
	# 뿌리(발): 아래 양쪽으로 뻗은 두꺼운 뿌리 덩어리
	for i in 4:
		var rx := 0.36 + i * 0.1
		var d := _ell(u, v, rx, 0.93, 0.07, 0.035)
		if d < 1.0:
			col = Color(0.22, 0.15, 0.1, 1.0).lerp(Color(0.12, 0.08, 0.06, 1.0), d)
	# 몸통 (큰 상자)
	if _box(u, v, 0.34, 0.3, 0.72, 0.9) < 0.0:
		col = _rust(u, v, rust, 0.0 if sick else 0.6)
		# 리벳 줄
		for i in 7:
			var ry := 0.33 + i * 0.09
			for j in 2:
				var rxx := 0.37 + j * 0.32
				if _ell(u, v, rxx, ry, 0.012, 0.012) < 1.0:
					col = dark
		# 가로 띠(이음새)
		if absf(v - 0.5) < 0.006 or absf(v - 0.72) < 0.006:
			col = dark
	# 위의 실린더 (가로로 누운 통) 와 앞으로 나온 피스톤 팔
	if _box(u, v, 0.3, 0.18, 0.74, 0.3) < 0.0:
		col = _rust(u, v, rust.lightened(0.08), 0.0 if sick else 0.5)
		var band := 0.5 + 0.5 * sin(v * 160.0)
		col = col.lerp(dark, band * 0.25)
	# (피스톤 팔과 관(노즐)은 코드 iron_pump_visual.gd 가 그려 움직인다 — 진짜 그림에 그려져 있으면 draw_parts 를 끈다)
	# 뒤쪽의 배기관 두 개 (위로)
	for i in 2:
		var px := 0.62 + i * 0.07
		if _box(u, v, px - 0.015, 0.06, px + 0.015, 0.2) < 0.0:
			col = _rust(u, v, rust.darkened(0.15))
	# 몸통 뿌리 감김 (어두운 띠가 비스듬히)
	if col.a > 0.0 and _box(u, v, 0.34, 0.3, 0.72, 0.9) < 0.0:
		var vine := clampf(1.0 - absf(_noise(u * 9.0, v * 5.0) - 0.5) * 14.0, 0.0, 1.0)
		col = col.lerp(Color(0.14, 0.12, 0.08, 1.0), vine * 0.75)
	# 심장(핵): 몸통 가운데의 빛나는 수액 (덮개 두 짝 사이로 보인다)
	var heart := _ell(u, v, 0.53, 0.58, 0.07, 0.07)
	if heart < 1.0:
		var hc := Color(0.35, 0.9, 0.95, 1.0) if sick else Color(0.6, 0.95, 1.0, 1.0)
		col = hc.lerp(Color(0.1, 0.4, 0.5, 1.0), heart * heart)
		if heart < 0.35:
			col = col.lerp(Color(1, 1, 1, 1), 0.6 - heart)
	# 이음새에서 새는 수액 (아플 때만)
	if sick and col.a > 0.0:
		for i in 6:
			var dx := 0.37 + i * 0.065
			var top := 0.5 + _hash2(i, 2.0) * 0.02
			var length := 0.06 + _hash2(i, 9.0) * 0.16
			if absf(u - dx) < 0.006 and v > top and v < top + length:
				col = col.lerp(Color(0.35, 0.8, 0.85, 1.0), 0.85)
			var tip := _ell(u, v, dx, top + length, 0.012, 0.012)
			if tip < 1.0:
				col = col.lerp(Color(0.5, 0.9, 0.95, 1.0), 1.0 - tip * 0.5)
	return col


func _pump_past(u: float, v: float) -> Color:
	var c := _pump(u, v, false)
	# 바탕: 등불이 걸린 따뜻한 공방
	var bg := Color(0.16, 0.11, 0.07).lerp(Color(0.3, 0.2, 0.12), v)
	var grain := _noise(u * 30.0, v * 6.0)
	bg = bg.lerp(Color(0.22, 0.15, 0.09), grain * 0.4)
	for i in 4:
		var lx := 0.1 + i * 0.26
		var d := _ell(u, v, lx, 0.12 + _hash2(i, 1.0) * 0.05, 0.018, 0.026)
		if d < 1.0:
			bg = bg.lerp(Color(1.0, 0.85, 0.5), 1.0 - d * 0.5)
		var glow := _ell(u, v, lx, 0.14, 0.12, 0.14)
		if glow < 1.0:
			bg = bg.lerp(Color(1.0, 0.8, 0.5), (1.0 - glow) * 0.3)
	# 장인들 (작은 실루엣 둘, 펌프 앞)
	for s in [0.2, 0.84]:
		var head := _ell(u, v, s, 0.68, 0.025, 0.025)
		var body := _ell(u, v, s, 0.82, 0.04, 0.1)
		if head < 1.0 or body < 1.0:
			bg = Color(0.25, 0.18, 0.12)
	var out := bg.lerp(Color(c.r, c.g, c.b), c.a)
	return _faded(Color(out.r, out.g, out.b, 1.0))


# ---------- 작은 펌프 ----------
## 왼쪽을 보는 작은 보조 펌프: 둥근 통 + 앞의 짧은 관 + 뿌리 발. 키는 그림의 60% 정도.
func _small_pump(u: float, v: float) -> Color:
	var col := Color(0, 0, 0, 0)
	var rust := Color(0.4, 0.17, 0.1, 1.0)
	var dark := Color(0.18, 0.09, 0.07, 1.0)
	for i in 3:
		var d := _ell(u, v, 0.42 + i * 0.1, 0.9, 0.06, 0.03)
		if d < 1.0:
			col = Color(0.2, 0.14, 0.1, 1.0).lerp(Color(0.12, 0.08, 0.06, 1.0), d)
	var body := _ell(u, v, 0.53, 0.6, 0.14, 0.2)
	if body < 1.0:
		col = _rust(u, v, rust)
		if absf(v - 0.55) < 0.006 or absf(v - 0.7) < 0.006:
			col = dark
		for i in 3:
			if _ell(u, v, 0.5 + (i - 1) * 0.06, 0.48, 0.01, 0.01) < 1.0:
				col = dark
	if _box(u, v, 0.26, 0.58, 0.42, 0.66) < 0.0:
		col = _rust(u, v, rust.lightened(0.05))
	var mouth := _ell(u, v, 0.26, 0.62, 0.025, 0.05)
	if mouth < 1.0:
		col = dark.lerp(Color(0.25, 0.6, 0.65, 1.0), (1.0 - mouth) * 0.8)
	if _box(u, v, 0.57, 0.3, 0.6, 0.42) < 0.0:
		col = _rust(u, v, rust.darkened(0.1))
	var eye := _ell(u, v, 0.49, 0.6, 0.035, 0.035)
	if eye < 1.0:
		col = Color(0.35, 0.85, 0.9, 1.0).lerp(Color(0.1, 0.35, 0.45, 1.0), eye * eye)
	if col.a > 0.0 and body < 1.0:
		var vine := clampf(1.0 - absf(_noise(u * 12.0, v * 7.0) - 0.5) * 14.0, 0.0, 1.0)
		col = col.lerp(Color(0.14, 0.12, 0.08, 1.0), vine * 0.7)
	return col


# ---------- 오브젝트 ----------
## 금 간 벽: 세로로 긴 나무 벽 조각. 가운데를 지나는 큰 금에서 희미한 빛이 샌다. (512×1024, aspect 0.5)
func _cracked_wall(u: float, v: float) -> Color:
	var bark := Color(0.17, 0.13, 0.09, 1.0)
	var grain := _noise(u * 8.0, v * 40.0)
	var col := bark.lerp(Color(0.25, 0.19, 0.13, 1.0), grain * 0.6)
	# 가장자리 부드럽게
	var edge := minf(minf(u, 1.0 - u) / 0.06, 1.0)
	col.a = clampf(edge, 0.0, 1.0)
	# 큰 금: 위에서 아래로 지그재그
	var cx := 0.5 + sin(v * 9.0) * 0.08 + sin(v * 23.0) * 0.03
	var d := absf(u - cx)
	var crack := clampf(1.0 - d / 0.035, 0.0, 1.0)
	col = col.lerp(Color(0.05, 0.03, 0.02, 1.0), crack * 0.9)
	var glow := clampf(1.0 - d / 0.11, 0.0, 1.0)
	col = col.lerp(Color(1.0, 0.75, 0.4, 1.0), glow * glow * 0.45)
	# 곁가지 금
	for i in 5:
		var y0 := 0.12 + i * 0.18
		var x0 := 0.5 + sin(y0 * 9.0) * 0.08
		var dirn := 1.0 if i % 2 == 0 else -1.0
		var s := _seg_dist(Vector2(u, v), Vector2(x0, y0), Vector2(x0 + dirn * 0.25, y0 + 0.05), 0.5)
		if s < 0.012:
			col = col.lerp(Color(0.06, 0.04, 0.03, 1.0), 0.8)
	return col


## 이슬잔: 우산 모양 풀잎 잔에 담긴 빛나는 이슬 (정사각형 아이콘)
func _dew_cup(u: float, v: float) -> Color:
	var col := Color(0, 0, 0, 0)
	var cup := _ell(u, v, 0.5, 0.62, 0.3, 0.2, 0.0, 1.0)
	if cup < 1.0 and v > 0.5:
		col = Color(0.3, 0.6, 0.45, 1.0).lerp(Color(0.12, 0.3, 0.25, 1.0), cup)
		var vein := clampf(1.0 - absf(fmod(absf(u - 0.5) * 9.0, 1.0) - 0.5) * 6.0, 0.0, 1.0)
		col = col.lerp(Color(0.55, 0.85, 0.6, 1.0), vein * 0.4)
	var dew := _ell(u, v, 0.5, 0.5, 0.22, 0.14, 0.0, 1.0)
	if dew < 1.0:
		col = Color(0.56, 0.83, 1.0, 1.0).lerp(Color(0.85, 0.97, 1.0, 1.0), 1.0 - dew)
	var hl := _ell(u, v, 0.42, 0.46, 0.05, 0.03, 0.4, 1.0)
	if hl < 1.0:
		col = Color(1, 1, 1, 1)
	if _box(u, v, 0.47, 0.78, 0.53, 0.92) < 0.0:
		col = Color(0.2, 0.42, 0.3, 1.0)
	var halo := _ell(u, v, 0.5, 0.5, 0.42, 0.42, 0.0, 1.0)
	if halo < 1.0 and col.a == 0.0:
		col = Color(0.56, 0.83, 1.0, (1.0 - halo) * 0.35)
	return col


## 경전 조각: 가장자리가 그을린 찢긴 종이, 나뭇잎 무늬, 읽을 수 없는 글줄
func _scripture_page(u: float, v: float) -> Color:
	var col := Color(0, 0, 0, 0)
	var tear := _noise(u * 7.0, v * 7.0) * 0.08
	if _box(u, v, 0.18 + tear, 0.14 + tear * 0.5, 0.82 - tear, 0.88 - tear) < 0.0:
		col = Color(0.86, 0.78, 0.6, 1.0).lerp(Color(0.6, 0.5, 0.36, 1.0), _noise(u * 20.0, v * 20.0) * 0.4)
		var e := _box(u, v, 0.18 + tear, 0.14 + tear * 0.5, 0.82 - tear, 0.88 - tear)
		if e > -0.05:
			col = col.lerp(Color(0.25, 0.15, 0.08, 1.0), (e + 0.05) / 0.05 * 0.8)
		for i in 7:
			var ly := 0.28 + i * 0.08
			if absf(v - ly) < 0.008 and u > 0.26 and u < 0.74 - _hash2(i, 4.0) * 0.2:
				col = Color(0.3, 0.22, 0.14, 1.0)
		var leaf := _ell(u, v, 0.5, 0.52, 0.2, 0.1, 0.6, 1.0)
		if leaf < 1.0:
			col = col.lerp(Color(0.5, 0.6, 0.35, 1.0), (1.0 - leaf) * 0.35)
	var halo := _ell(u, v, 0.5, 0.5, 0.45, 0.45, 0.0, 1.0)
	if halo < 1.0 and col.a == 0.0:
		col = Color(1.0, 0.9, 0.6, (1.0 - halo) * 0.3)
	return col


# ---------- 배경 ----------
## 잠긴 채굴장: 수액에 반쯤 잠긴 펌프실. 녹슨 붉은 금속 관, 아래 수면에 비치는 붉은 빛.
func _bg_flooded(u: float, v: float) -> Color:
	var col := Color(0.1, 0.05, 0.04).lerp(Color(0.16, 0.08, 0.06), v)
	var grain := _noise(u * 24.0, v * 8.0)
	col = col.lerp(Color(0.22, 0.1, 0.07), grain * 0.4)
	# 관들 (세로·가로 어두운 띠)
	for i in 6:
		var px := 0.08 + i * 0.17 + _hash2(i, 3.0) * 0.04
		if absf(u - px) < 0.018:
			col = Color(0.26, 0.12, 0.08).lerp(Color(0.1, 0.05, 0.04), absf(u - px) / 0.018)
	for i in 3:
		var py := 0.22 + i * 0.16
		if absf(v - py) < 0.012:
			col = Color(0.24, 0.11, 0.08)
	# 붉은 빛 (가운데 위)
	var glow := _ell(u, v, 0.5, 0.3, 0.3, 0.25)
	if glow < 1.0:
		col = col.lerp(Color(0.6, 0.2, 0.1), (1.0 - glow) * 0.35)
	# 수면: 아래 30%, 붉은 빛이 비친다
	if v > 0.7:
		var depth := (v - 0.7) / 0.3
		var shimmer := 0.5 + 0.5 * sin(u * 80.0 + depth * 25.0) * sin(u * 19.0)
		col = col.lerp(Color(0.25, 0.5, 0.55), 0.4 + shimmer * 0.2 - depth * 0.15)
		col = col.lerp(Color(0.5, 0.2, 0.12), shimmer * 0.2 * (1.0 - depth))
	return _brighten(col, 2.1)


## 무쇠 펌프 싸움터: 거대한 설비가 둘러싼 넓은 방, 얕은 수액 바닥.
func _bg_flooded_boss(u: float, v: float) -> Color:
	var col := Color(0.09, 0.05, 0.04).lerp(Color(0.14, 0.08, 0.06), v)
	var grain := _noise(u * 20.0, v * 7.0)
	col = col.lerp(Color(0.2, 0.1, 0.07), grain * 0.35)
	# 양옆의 거대한 설비 (둥근 통들)
	for i in 3:
		for side in [0.12, 0.88]:
			var d := _ell(u, v, side, 0.25 + i * 0.22, 0.1, 0.1)
			if d < 1.0:
				col = Color(0.3, 0.13, 0.09).lerp(Color(0.12, 0.06, 0.05), d * d)
	# 가운데 위의 큰 톱니 실루엣
	var gear := _ell(u, v, 0.5, 0.22, 0.17, 0.17)
	if gear < 1.0 and gear > 0.72:
		var teeth := 0.5 + 0.5 * sin(atan2((v - 0.22) / 1.5, u - 0.5) * 14.0)
		if gear < 0.85 or teeth > 0.5:
			col = Color(0.22, 0.1, 0.08)
	var glow := _ell(u, v, 0.5, 0.45, 0.35, 0.3)
	if glow < 1.0:
		col = col.lerp(Color(0.55, 0.18, 0.1), (1.0 - glow) * 0.3)
	if v > 0.72:
		var depth := (v - 0.72) / 0.28
		var shimmer := 0.5 + 0.5 * sin(u * 70.0 + depth * 20.0) * sin(u * 31.0)
		col = col.lerp(Color(0.22, 0.5, 0.56), 0.45 + shimmer * 0.2 - depth * 0.15)
	return _brighten(col, 2.0)


## 어두운 바탕을 화면에서 보이게 밝힌다 (잿빛 재질이 또 한 번 바래게 하므로 넉넉히)
static func _brighten(c: Color, k: float) -> Color:
	return Color(minf(c.r * k, 1.0), minf(c.g * k, 1.0), minf(c.b * k, 1.0), 1.0)


# ---------- 회상 ----------
func _faded(c: Color) -> Color:
	var g := c.get_luminance()
	return Color(c.lerp(Color(g, g, g), 0.3).lerp(Color(0.95, 0.85, 0.7), 0.18), 1.0)


## ① 등불이 걸린 공방에서 장인들이 웃으며 펌프를 만드는 모습
func _memory_1(u: float, v: float) -> Color:
	return _pump_past(u, v)


## ② 끝없이 돌아가는 펌프, 관 속에서 고통스럽게 빛나는 마력, 지친 광부들
func _memory_2(u: float, v: float) -> Color:
	var col := Color(0.1, 0.06, 0.05).lerp(Color(0.2, 0.1, 0.07), v)
	var p := _pump(u * 1.3 - 0.1, v, true)
	col = col.lerp(Color(p.r, p.g, p.b), p.a * 0.9)
	# 관 속의 마력 (밝은 띠가 오른쪽으로)
	for i in 3:
		var py := 0.3 + i * 0.12
		var band := clampf(1.0 - absf(v - py) / 0.01, 0.0, 1.0) * clampf((u - 0.55) / 0.1, 0.0, 1.0)
		col = col.lerp(Color(0.5, 0.95, 1.0), band * 0.8)
	# 광부들 (오른쪽 아래 작은 실루엣들)
	for i in 3:
		var sx := 0.68 + i * 0.1
		var head := _ell(u, v, sx, 0.72, 0.02, 0.02)
		var body := _ell(u, v, sx, 0.84, 0.035, 0.09)
		if head < 1.0 or body < 1.0:
			col = Color(0.18, 0.13, 0.1)
	return _faded(col)


## ③ 펌프 옆 벽에 새겨진 오래된 설계도, 톱니가 거꾸로 도는 화살표
func _memory_3(u: float, v: float) -> Color:
	var col := Color(0.26, 0.2, 0.14).lerp(Color(0.34, 0.27, 0.19), v)
	col = col.lerp(Color(0.2, 0.15, 0.1), _noise(u * 14.0, v * 10.0) * 0.4)
	# 설계도 선 (밝은 선들)
	var line := Color(0.85, 0.8, 0.65)
	var gear := _ell(u, v, 0.5, 0.5, 0.22, 0.22)
	if absf(gear - 1.0) < 0.03 or absf(gear - 0.6) < 0.03:
		col = line
	var ang := atan2((v - 0.5) / 1.5, u - 0.5)
	if gear < 1.12 and gear > 1.0 and sin(ang * 12.0) > 0.3:
		col = line
	# 거꾸로 도는 화살표 (바깥 호 + 화살머리)
	if absf(gear - 1.3) < 0.03 and ang > -2.4 and ang < 1.2:
		col = Color(0.95, 0.8, 0.5)
	var head := Vector2(0.5 + cos(-2.4) * 0.22 * 1.3, 0.5 + sin(-2.4) * 0.22 * 1.3 * 1.5)
	if _ell(u, v, head.x, head.y, 0.035, 0.035) < 1.0:
		col = Color(0.95, 0.8, 0.5)
	for i in 6:
		var ly := 0.15 + i * 0.05
		if absf(v - ly) < 0.004 and u > 0.08 and u < 0.3 - _hash2(i, 2.0) * 0.1:
			col = line
	return _faded(col)


## 제3의 길 엔딩: 달빛풀 아래 작은 등불을 든 티아와 셀레니아, 뒤로 초록이 돌아오는 나무, 멀리 작은 등불들의 마을 (16:9)
func _ending(u: float, v: float) -> Color:
	var col := Color(0.06, 0.08, 0.12).lerp(Color(0.12, 0.16, 0.14), v)
	# 거대한 나무 줄기 (왼쪽)
	if u < 0.22 + sin(v * 6.0) * 0.02:
		col = Color(0.12, 0.09, 0.07).lerp(Color(0.2, 0.15, 0.1), _noise(u * 20.0, v * 8.0))
	# 잎: 잿빛에서 초록으로 (위쪽)
	var canopy := _noise(u * 12.0, v * 12.0)
	if v < 0.45 and canopy > 0.45:
		var green := clampf((0.45 - v) / 0.45, 0.0, 1.0)
		col = Color(0.4, 0.4, 0.42).lerp(Color(0.25, 0.55, 0.3), green)
	# 멀리 작은 등불들의 마을 (오른쪽 가운데)
	for i in 9:
		var lx := 0.6 + _hash2(i, 1.0) * 0.36
		var ly := 0.5 + _hash2(i, 2.0) * 0.12
		var d := _ell(u, v, lx, ly, 0.008, 0.008, 0.0, 1.78)
		if d < 1.0:
			col = col.lerp(Color(1.0, 0.85, 0.5), 1.0 - d * 0.4)
		var g := _ell(u, v, lx, ly, 0.03, 0.03, 0.0, 1.78)
		if g < 1.0:
			col = col.lerp(Color(1.0, 0.8, 0.5), (1.0 - g) * 0.25)
	# 땅
	if v > 0.78:
		col = Color(0.1, 0.12, 0.08).lerp(Color(0.16, 0.2, 0.12), _noise(u * 30.0, v * 10.0))
	# 달빛풀 (가운데 아래, 은청색 우산)
	var umb := _ell(u, v, 0.42, 0.52, 0.16, 0.07, 0.0, 1.78)
	if umb < 1.0 and v < 0.52:
		col = Color(0.56, 0.83, 1.0).lerp(Color(0.3, 0.5, 0.7), umb)
	if _box(u, v, 0.415, 0.52, 0.425, 0.8) < 0.0:
		col = Color(0.4, 0.6, 0.7)
	var halo := _ell(u, v, 0.42, 0.55, 0.3, 0.25, 0.0, 1.78)
	if halo < 1.0:
		col = col.lerp(Color(0.56, 0.83, 1.0), (1.0 - halo) * 0.2)
	# 두 소녀 (실루엣: 큰 쪽 셀레니아, 작은 쪽 티아) 와 작은 등불
	var sel_h := _ell(u, v, 0.37, 0.66, 0.02, 0.02, 0.0, 1.78)
	var sel_b := _ell(u, v, 0.37, 0.74, 0.035, 0.06, 0.0, 1.78)
	var tia_h := _ell(u, v, 0.45, 0.69, 0.016, 0.016, 0.0, 1.78)
	var tia_b := _ell(u, v, 0.45, 0.75, 0.028, 0.045, 0.0, 1.78)
	if sel_h < 1.0 or sel_b < 1.0:
		col = Color(0.25, 0.3, 0.3)
	if tia_h < 1.0 or tia_b < 1.0:
		col = Color(0.3, 0.25, 0.2)
	var lamp := _ell(u, v, 0.485, 0.74, 0.012, 0.016, 0.0, 1.78)
	if lamp < 1.0:
		col = Color(1.0, 0.85, 0.5)
	var lg := _ell(u, v, 0.485, 0.74, 0.08, 0.1, 0.0, 1.78)
	if lg < 1.0:
		col = col.lerp(Color(1.0, 0.8, 0.5), (1.0 - lg) * 0.35)
	return Color(col.lerp(Color(0.95, 0.85, 0.7), 0.1), 1.0)

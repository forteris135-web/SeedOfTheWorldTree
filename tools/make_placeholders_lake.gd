extends SceneTree
## 수액의 호수(확장판) 임시 그림 생성기. 진짜 그림(ChatGPT)이 오기 전까지 '스킨 자리'를 채운다.
## EXPANSION.md 11장의 파일 이름 **그대로** 만든다 → 진짜 그림을 같은 이름으로 덮어쓰기만 하면 끝.
## 사용: /path/to/Godot --headless --path . --script tools/make_placeholders_lake.gd
## 만드는 것 (모두 1536×1024, 진짜 그림과 같은 크기라 배율·자리가 그대로 맞는다):
##   art/bosses/boss_sap_queen_now.png (투명, 나비 실루엣 + 갈라진 날개)
##   art/enemies/enemy_sap_fisher.png (투명, 오른쪽을 보는 사람 실루엣 + 낚싯대, 줄은 코드가 그림) / enemy_sap_fisher_savable.png (가슴 온기)
##   art/backgrounds/bg_hidden_descent.png / bg_sap_lake_1.png / bg_sap_lake_boss.png (3:2 그라데이션 + 층층 수면 자국)
##   (boss_sap_queen_past.png · art/memories/memory_queen_1~3.png 는 진짜 그림이 들어와 더 만들지 않는다)
## 그림은 절반 크기(768×512)로 계산한 뒤 두 배로 키운다 (수채화처럼 부드럽고, 계산이 4배 빠르다).

const W := 768
const H := 512
const OUT_W := 1536
const OUT_H := 1024

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	_make("res://art/bosses/boss_sap_queen_now.png", true, _queen_now)
	# boss_sap_queen_past.png · memory_queen_1~3.png 는 기획자의 진짜 그림이 들어왔다 (2026-10-20) — 만들지 않는다 (덮어쓰기 방지)
	_make("res://art/enemies/enemy_sap_fisher.png", true, func(u: float, v: float) -> Color: return _fisher(u, v, false))
	_make("res://art/enemies/enemy_sap_fisher_savable.png", true, func(u: float, v: float) -> Color: return _fisher(u, v, true))
	_make("res://art/backgrounds/bg_hidden_descent.png", false, _bg_descent)
	_make("res://art/backgrounds/bg_sap_lake_1.png", false, _bg_lake)
	_make("res://art/backgrounds/bg_sap_lake_boss.png", false, _bg_lake_boss)
	print("임시 그림 6장 생성 완료 (%.1f초)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()


## 픽셀마다 shade(u, v) 를 불러 그림을 만든다 (u, v 는 0~1; 가로 3:2 라 u 는 1.5 배로 늘어난 축이 아니라 그냥 비율).
func _make(path: String, alpha: bool, shade: Callable) -> void:
	_rng.seed = hash(path)
	var fmt := Image.FORMAT_RGBA8 if alpha else Image.FORMAT_RGB8
	var img := Image.create(W, H, false, fmt)
	for y in H:
		var v := (y + 0.5) / H
		for x in W:
			var c: Color = shade.call((x + 0.5) / W, v)
			img.set_pixel(x, y, c)
	img.resize(OUT_W, OUT_H, Image.INTERPOLATE_CUBIC)
	img.save_png(ProjectSettings.globalize_path(path))
	print("  ", path, "  ", OUT_W, "x", OUT_H)


# ---------- 도형 보조 ----------
## 타원 안쪽 거리 (0 중심 → 1 가장자리). rot 는 라디안.
static func _ell(u: float, v: float, cx: float, cy: float, rx: float, ry: float, rot := 0.0) -> float:
	var dx := u - cx
	var dy := (v - cy) * 1.5   # 3:2 그림에서 세로를 가로 단위로 (원이 원으로 보이게)
	var c := cos(rot)
	var s := sin(rot)
	var ex := dx * c + dy * s
	var ey := -dx * s + dy * c
	return sqrt((ex * ex) / (rx * rx) + (ey * ey) / (ry * ry))


static func _hash2(x: float, y: float) -> float:
	var h := sin(x * 127.1 + y * 311.7) * 43758.5453
	return h - floor(h)


## 부드러운 잡음 (0~1)
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
	## 가늘고 긴 금(갈라짐): 잡음 등고선의 좁은 띠
	var n := _noise(u * scale, v * scale * 0.67)
	return clampf(1.0 - absf(n - 0.5) * 18.0, 0.0, 1.0)


# ---------- 수액의 여왕 ----------
## 날개 네 장 + 몸통 + 수액 방울. 날개는 몸에서 밝고 가장자리는 어둡게 굳은 껍질, 갈라진 금.
func _queen_now(u: float, v: float) -> Color:
	return _queen(u, v, true)


func _queen_past(u: float, v: float) -> Color:
	var c := _queen(u, v, false)
	if c.a < 0.98:
		# 바탕: 가득 찬 호수 (아래 밝은 푸른 수면, 위 어둠)
		var sky := Color(0.07, 0.1, 0.16).lerp(Color(0.12, 0.3, 0.42), clampf((v - 0.35) / 0.4, 0.0, 1.0))
		var shimmer := 0.5 + 0.5 * sin(u * 60.0 + v * 9.0) * sin(v * 40.0)
		if v > 0.62:
			sky = sky.lerp(Color(0.35, 0.75, 0.85), 0.25 + 0.25 * shimmer * (v - 0.62))
		var out := sky.lerp(Color(c.r, c.g, c.b), c.a)
		return Color(out.r, out.g, out.b, 1.0)
	return Color(c.r, c.g, c.b, 1.0)


func _queen(u: float, v: float, sick: bool) -> Color:
	var cx := 0.5
	var cy := 0.52
	# 날개: 위쪽 큰 날개 두 장(바깥·위로), 아래쪽 작은 날개 두 장
	var best := 9.0
	var which := 0
	var wings := [
		[cx + 0.19, cy - 0.11, 0.21, 0.135, 0.35],
		[cx - 0.19, cy - 0.11, 0.21, 0.135, -0.35],
		[cx + 0.13, cy + 0.14, 0.14, 0.1, -0.5],
		[cx - 0.13, cy + 0.14, 0.14, 0.1, 0.5],
	]
	for i in wings.size():
		var w: Array = wings[i]
		var d := _ell(u, v, w[0], w[1], w[2], w[3], w[4])
		if d < best:
			best = d
			which = i
	# 가장자리의 울퉁불퉁함 (껍질처럼 굳은 자리)
	var edge_noise := _noise(u * 40.0, v * 30.0) * 0.07
	var rim := 1.0 - edge_noise
	var col := Color(0, 0, 0, 0)
	if best < rim:
		var t := best / rim   # 0 몸 쪽 → 1 가장자리
		var inner := Color(0.62, 0.9, 0.95, 0.72) if sick else Color(0.55, 0.9, 1.0, 0.82)
		var outer := Color(0.22, 0.42, 0.5, 0.92) if sick else Color(0.2, 0.55, 0.85, 0.9)
		col = inner.lerp(outer, pow(t, 1.4))
		# 날개 무늬: 동심 띠
		var band := 0.5 + 0.5 * sin(t * 26.0)
		col = col.lerp(Color(0.9, 1.0, 1.0, col.a), band * 0.12 * (1.0 - t))
		if sick:
			# 가장자리가 나무껍질처럼 굳는다
			if t > 0.72:
				var k := (t - 0.72) / 0.28
				col = col.lerp(Color(0.26, 0.18, 0.12, 1.0), k * 0.9)
			# 갈라진 금
			var crack := _vein(u + which * 0.3, v, 14.0) * clampf((t - 0.3) / 0.5, 0.0, 1.0)
			col = col.lerp(Color(0.12, 0.08, 0.06, 1.0), crack * 0.85)
		else:
			# 맑은 날개의 빛 점
			var sp := _noise(u * 90.0, v * 60.0)
			if sp > 0.82:
				col = col.lerp(Color(1.0, 1.0, 1.0, 1.0), (sp - 0.82) * 3.0)
	# 몸통 (세로 길쭉한 타원) + 머리
	var body := _ell(u, v, cx, cy + 0.02, 0.028, 0.17)
	var head := _ell(u, v, cx, cy - 0.17, 0.036, 0.036)
	if body < 1.0 or head < 1.0:
		var bt := minf(body, head)
		var bc := Color(0.18, 0.12, 0.1, 1.0).lerp(Color(0.5, 0.75, 0.7, 1.0), 1.0 - bt)
		if sick:
			bc = bc.lerp(Color(0.3, 0.2, 0.14, 1.0), 0.4)
		col = bc
		# 가슴의 빛 (심장)
		var heart := _ell(u, v, cx, cy - 0.05, 0.02, 0.025)
		if heart < 1.0:
			col = col.lerp(Color(0.9, 1.0, 1.0, 1.0), 1.0 - heart)
	# 더듬이
	for s: float in [-1.0, 1.0]:
		var ax := cx + s * 0.06
		var ay := cy - 0.26
		var d := _ell(u, v, ax, ay, 0.055, 0.02, s * 0.9)
		if absf(d - 0.9) < 0.1:
			col = Color(0.2, 0.15, 0.12, 1.0)
	# 수액 방울 (아프면 많이, 맑으면 몇 개)
	var drops := 7 if sick else 2
	for i in drops:
		var dx := cx + (float(i) - drops / 2.0) * 0.045 + sin(i * 2.3) * 0.02
		var top := cy + 0.12 + _hash2(i, 3.0) * 0.08
		var length := 0.08 + _hash2(i, 7.0) * 0.14
		if sick:
			length *= 1.4
		var ddist := _ell(u, v, dx, top + length * 0.5, 0.009, length * 0.5)
		if ddist < 1.0:
			var dc := Color(0.45, 0.8, 0.85, 0.85) if sick else Color(0.5, 0.9, 1.0, 0.7)
			col = col.lerp(dc, (1.0 - ddist) * 0.9 + 0.1)
		var tip := _ell(u, v, dx, top + length, 0.014, 0.014)
		if tip < 1.0:
			col = col.lerp(Color(0.6, 0.9, 0.95, 0.95), 1.0 - tip * 0.5)
	return col


# ---------- 수액 어부 ----------
## 오른쪽을 보는 사람 실루엣 (art_faces_right = true). 나무껍질 피부 + 수액 줄기 + 앞으로 내민 낚싯대 (줄은 없음).
func _fisher(u: float, v: float, savable: bool) -> Color:
	var col := Color(0, 0, 0, 0)
	var cx := 0.46
	var skin := Color(0.3, 0.22, 0.16, 1.0)
	var bark := Color(0.2, 0.14, 0.1, 1.0)
	# 머리
	var head := _ell(u, v, cx + 0.01, 0.31, 0.052, 0.052)
	# 목 (머리와 몸통을 잇는다)
	var neck := _ell(u, v, cx + 0.005, 0.36, 0.028, 0.035)
	# 몸통 (앞으로 살짝 숙인 사다리꼴 느낌의 타원)
	var torso := _ell(u, v, cx, 0.48, 0.085, 0.17, 0.12)
	# 다리 두 개
	var leg1 := _ell(u, v, cx - 0.03, 0.78, 0.035, 0.15, 0.1)
	var leg2 := _ell(u, v, cx + 0.05, 0.78, 0.035, 0.15, -0.15)
	# 앞으로 내민 팔
	var arm := _ell(u, v, cx + 0.11, 0.42, 0.11, 0.028, -0.35)
	var dmin := minf(minf(minf(head, neck), torso), minf(minf(leg1, leg2), arm))
	if dmin < 1.0:
		col = skin.lerp(bark, pow(dmin, 2.0))
		# 나무 결
		var grain := _noise(u * 70.0, v * 14.0)
		col = col.lerp(bark, grain * 0.5)
		# 혈관처럼 빛나는 수액 줄기
		var vein := _vein(u, v, 22.0)
		col = col.lerp(Color(0.35, 0.8, 0.9, 1.0), vein * 0.8 * (1.0 - dmin * 0.4))
		# 몸을 뚫고 자란 잎 (어깨)
		var leaf := _ell(u, v, cx - 0.06, 0.33, 0.05, 0.02, 0.8)
		if leaf < 1.0:
			col = col.lerp(Color(0.3, 0.45, 0.2, 1.0), 1.0 - leaf)
		if savable:
			var face := _ell(u, v, cx + 0.03, 0.32, 0.035, 0.04)
			if face < 1.0:
				col = col.lerp(Color(0.7, 0.55, 0.42, 1.0), (1.0 - face) * 0.8)
			var warm := _ell(u, v, cx + 0.01, 0.42, 0.04, 0.05)
			if warm < 1.0:
				col = col.lerp(Color(1.0, 0.75, 0.35, 1.0), (1.0 - warm))
	# 낚싯대: 손에서 앞 위로 뻗는 가는 막대
	var hand := Vector2(cx + 0.2, 0.39)
	var tip := Vector2(cx + 0.42, 0.14)
	var seg := _seg_dist(Vector2(u, v), hand, tip)
	if seg < 0.006:
		col = Color(0.36, 0.26, 0.16, 1.0)
	# 낚싯줄은 그리지 않는다 — 대 끝(uv 0.88, 0.14)에서 코드(sap_fisher_visual.gd)가 그린다 (두 가닥으로 보이지 않게)
	return col


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var q := a + ab * t
	return Vector2((p.x - q.x), (p.y - q.y) * 1.5).length()


# ---------- 배경 ----------
## 숨은 내리막: 좁고 어두운 줄기 속 통로. 아래에서 푸른 수액빛이 올라온다.
func _bg_descent(u: float, v: float) -> Color:
	var col := Color(0.09, 0.07, 0.06).lerp(Color(0.05, 0.05, 0.07), v)
	# 세로 결 (줄기 속 벽)
	var grain := _noise(u * 40.0, v * 6.0)
	col = col.lerp(Color(0.14, 0.11, 0.08), grain * 0.5)
	# 가운데 통로가 조금 밝다
	var tunnel := 1.0 - clampf(absf(u - 0.5) / 0.22, 0.0, 1.0)
	col = col.lerp(Color(0.13, 0.13, 0.15), tunnel * 0.5)
	# 아래에서 올라오는 푸른 빛
	var glow := clampf((v - 0.55) / 0.45, 0.0, 1.0) * tunnel
	col = col.lerp(Color(0.2, 0.55, 0.7), glow * glow * 0.7)
	return col


## 수액의 호수 1: 벽에 층층이 남은 옛 수면 자국, 은은한 푸른 빛.
func _bg_lake(u: float, v: float) -> Color:
	var col := Color(0.08, 0.1, 0.12).lerp(Color(0.1, 0.17, 0.2), v)
	var wall := clampf((absf(u - 0.5) - 0.2) / 0.3, 0.0, 1.0)   # 양옆이 벽
	var grain := _noise(u * 30.0, v * 10.0)
	col = col.lerp(Color(0.16, 0.12, 0.09), wall * (0.5 + grain * 0.4))
	# 수면 자국 (가로 줄, 위로 갈수록 흐릿)
	for i in 7:
		var ly := 0.3 + i * 0.075
		var band := clampf(1.0 - absf(v - ly) / 0.008, 0.0, 1.0)
		col = col.lerp(Color(0.35, 0.6, 0.65), band * wall * (0.25 + i * 0.08))
	# 가운데 아래의 수액빛
	var glow := clampf((v - 0.5) / 0.5, 0.0, 1.0) * (1.0 - wall)
	var shimmer := 0.5 + 0.5 * sin(u * 70.0 + sin(v * 30.0) * 2.0)
	col = col.lerp(Color(0.2, 0.5, 0.62), glow * (0.5 + shimmer * 0.2))
	return col


## 수액의 호수 보스 싸움터: 넓게 트인 공간, 위에서 빛줄기, 수면 위 뿌리·바위 실루엣.
func _bg_lake_boss(u: float, v: float) -> Color:
	var col := Color(0.06, 0.09, 0.12).lerp(Color(0.1, 0.22, 0.28), v)
	# 빛줄기 (위에서 내려오는 밝은 세로 띠 몇 개)
	for i in 4:
		var sx := 0.22 + i * 0.19 + sin(i * 1.7) * 0.03
		var x := u - (sx + (v - 0.2) * 0.08 * (i - 1.5))
		var shaft := clampf(1.0 - absf(x) / 0.035, 0.0, 1.0) * (1.0 - v * 0.7)
		col = col.lerp(Color(0.45, 0.7, 0.75), shaft * 0.35)
	# 수면: 아래 35%
	if v > 0.65:
		var depth := (v - 0.65) / 0.35
		var shimmer := 0.5 + 0.5 * sin(u * 90.0 + depth * 20.0) * sin(u * 23.0)
		col = col.lerp(Color(0.25, 0.6, 0.72), 0.45 + shimmer * 0.2 - depth * 0.2)
	# 뿌리·바위 실루엣 (수면 위로 솟은 둥근 덩어리들)
	for i in 5:
		var rx := 0.1 + i * 0.2 + _hash2(i, 1.0) * 0.05
		var d := _ell(u, v, rx, 0.68, 0.06 + _hash2(i, 2.0) * 0.03, 0.05)
		if d < 1.0:
			col = Color(0.09, 0.08, 0.07).lerp(col, d * d * 0.3)
	return col


# ---------- 회상 ----------
func _faded(c: Color) -> Color:
	# 바랜 색 + 따뜻한 빛
	var g := c.get_luminance()
	return c.lerp(Color(g, g, g), 0.3).lerp(Color(0.95, 0.85, 0.7), 0.18)


## ① 가득 찬 호수 위를 춤추는 여왕
func _memory_1(u: float, v: float) -> Color:
	var col := Color(0.2, 0.3, 0.42).lerp(Color(0.3, 0.65, 0.78), clampf((v - 0.4) / 0.5, 0.0, 1.0))
	var shimmer := 0.5 + 0.5 * sin(u * 50.0 + v * 12.0) * sin(v * 60.0)
	if v > 0.55:
		col = col.lerp(Color(0.8, 0.95, 1.0), shimmer * 0.2)
	# 작은 나비 (밝은 빛)
	var b := _ell(u, v, 0.55, 0.38, 0.09, 0.05)
	var body := _ell(u, v, 0.55, 0.38, 0.012, 0.05)
	if b < 1.0:
		col = col.lerp(Color(0.85, 1.0, 1.0), (1.0 - b) * 0.9)
	if body < 1.0:
		col = col.lerp(Color(0.3, 0.3, 0.35), 0.8)
	var halo := _ell(u, v, 0.55, 0.38, 0.2, 0.14)
	if halo < 1.0:
		col = col.lerp(Color(1.0, 1.0, 0.95), (1.0 - halo) * 0.25)
	return _faded(col)


## ② 말라 가는 호수, 마지막 수액이 수로를 따라 위의 등불 마을로
func _memory_2(u: float, v: float) -> Color:
	var col := Color(0.16, 0.14, 0.13).lerp(Color(0.22, 0.3, 0.34), clampf((v - 0.55) / 0.45, 0.0, 1.0))
	# 수로: 왼쪽 아래에서 오른쪽 위로 가는 빛나는 줄
	var seg := _seg_dist(Vector2(u, v), Vector2(0.3, 0.8), Vector2(0.78, 0.18))
	var line := clampf(1.0 - seg / 0.02, 0.0, 1.0)
	col = col.lerp(Color(0.5, 0.9, 1.0), line * 0.9)
	var glow := clampf(1.0 - seg / 0.09, 0.0, 1.0)
	col = col.lerp(Color(0.35, 0.65, 0.8), glow * 0.35)
	# 위의 작은 등불들
	for i in 6:
		var lx := 0.62 + i * 0.055
		var ly := 0.12 + _hash2(i, 5.0) * 0.06
		var d := _ell(u, v, lx, ly, 0.012, 0.012)
		if d < 1.0:
			col = col.lerp(Color(1.0, 0.85, 0.5), 1.0 - d * 0.5)
	# 지켜보는 나비 (왼쪽, 어둡게)
	var b := _ell(u, v, 0.2, 0.55, 0.08, 0.045)
	if b < 1.0:
		col = col.lerp(Color(0.5, 0.75, 0.8), (1.0 - b) * 0.6)
	return _faded(col)


## ③ 텅 빈 호수 바닥에 메마른 날개로 홀로 앉은 여왕
func _memory_3(u: float, v: float) -> Color:
	var col := Color(0.14, 0.12, 0.1).lerp(Color(0.3, 0.24, 0.18), clampf((v - 0.5) / 0.5, 0.0, 1.0))
	# 갈라진 바닥
	var crack := _vein(u, v, 9.0) * clampf((v - 0.55) / 0.3, 0.0, 1.0)
	col = col.lerp(Color(0.08, 0.06, 0.05), crack * 0.8)
	# 벽의 수면 자국
	for i in 5:
		var ly := 0.2 + i * 0.07
		var band := clampf(1.0 - absf(v - ly) / 0.006, 0.0, 1.0)
		col = col.lerp(Color(0.3, 0.4, 0.42), band * 0.3)
	# 앉아 있는 나비 (가운데, 날개 접힘)
	var w1 := _ell(u, v, 0.47, 0.6, 0.07, 0.12, 0.3)
	var w2 := _ell(u, v, 0.55, 0.6, 0.07, 0.12, -0.3)
	var d := minf(w1, w2)
	if d < 1.0:
		var wc := Color(0.4, 0.55, 0.58).lerp(Color(0.25, 0.18, 0.12), pow(d, 1.3))
		var ck := _vein(u, v, 16.0)
		wc = wc.lerp(Color(0.1, 0.07, 0.05), ck * 0.8 * d)
		col = wc
	var body := _ell(u, v, 0.51, 0.63, 0.016, 0.1)
	if body < 1.0:
		col = Color(0.2, 0.14, 0.1)
	return _faded(col)

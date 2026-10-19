class_name SapWaterArt
extends Node2D
## 수액 웅덩이(SapPool)의 그림 겉모습 (그림 조각 지형 — TERRAIN.md). 방의 지형 그림 옷(TerrainSkin)에
## water 역할 조각이 있을 때만 붙는다 (지금은 수액의 호수: 기획자의 '물 지형' 시트). 없으면 null → 웅덩이는 옛 코드 그림 그대로.
## **판정(SapPool 의 Area2D)·수면 높이(surface_y)는 건드리지 않는다** — 겉모습만.
##
## 겹 (아래 → 위, 모두 SapPool 의 코드 그림(빛 띠·방울·잔물결 고리) 뒤에 그린다 — show_behind_parent):
##   몸통 (Body) : 긴 수면 조각의 가운데 토막들을 웅덩이 폭에 이어 붙인다 (이음매는 OVERLAP px 동안 서서히 겹침).
##                 위 끝 = 수면(y=0), 아래 끝 = 웅덩이 바닥 + 여유 (살아난 수액이 FILL_RISE 만큼 차올라도 바닥이 비지 않게).
##                 끝: 옆이 지형에 막혀 있으면 곧게(지형 속으로 TUCK px), 열려 있으면 조각의 비스듬한 물가 끝을 쓴다.
##   물결 (Waves): 물결 띠 조각을 수면에 얹고 천천히 흔든다 (위치만 바꾼다 — 다시 만들지 않음).
## 만들기는 방에 들어올 때 한 번 (TerrainArt.piece 로 삼각형 배열). 매 프레임은 tick() 이 색·물결 자리만 바꾼다.
## 세기 조절: data/terrain/<지역>.json 의 params.water (alpha, alpha_ash, wave_alpha) 와 아래 상수.

## 이어 붙이는 겹침 (px)
const OVERLAP := 110.0
## 막힌 끝을 지형 속으로 밀어 넣는 길이 (px)
const TUCK := 6.0
## 몸통 아래 여유 (웅덩이 바닥 + 차오름 + 이만큼)
const DEPTH_PAD := 14.0
## 끝이 열린 웅덩이(바닥 위에 고인 수액)는 몸통을 이만큼 더 깊게 — 바닥 띠를 덮어 '바닥이 움푹 팬 웅덩이'로 읽히게
const OPEN_PAD := 56.0
## 열린 끝(물가)이 서서히 사라지는 길이 (px)
const SHORE_FADE := 70.0
## 열린 끝 조각이 판정 끝 밖으로 나가는 비율 (끝 조각 폭 기준)
const SHORE_OUT := 0.55
## 물결 띠 높이 (px) 와 흔들림 (px)
const WAVE_H := 26.0
const WAVE_SWAY := 7.0
const WAVE_BOB := 1.6
## 정화 전 몸통 색 (곱하기 — 잿빛 표를 거치기 전 살짝 탁하게)
const ASH_MOD := Color(0.82, 0.86, 0.84)

var skin: TerrainSkin
var pool: Node2D
var _body: TerrainArt
var _waves: TerrainArt
var _alpha := 0.86
var _alpha_ash := 0.8
var _wave_alpha := 0.5
var _phase := 0.0
var _last_alive := -1.0
var _last_walk := false


## 웅덩이에 붙인다. 그림 옷에 water 조각이 없으면 아무것도 안 붙이고 null.
## rise: 살아난 수액이 차오르는 높이(그림만) — 몸통을 그만큼 더 깊게 만든다.
static func attach(p: Node2D, size: Vector2, rise: float) -> SapWaterArt:
	var s := TerrainSkin.for_node(p)
	if s == null or not s.has_role("water"):
		return null
	var w := SapWaterArt.new()
	w.skin = s
	w.pool = p
	w.name = "WaterArt"
	w.show_behind_parent = true
	w.material = preload("res://shaders/ash_purify.tres")   # 웅덩이 자체는 더하기 혼합이지만 물 그림은 보통 혼합
	w.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	p.add_child(w)
	w._build(size, rise)
	return w


func _build(size: Vector2, rise: float) -> void:
	_alpha = float(skin.param("water", "alpha", 0.86))
	_alpha_ash = float(skin.param("water", "alpha_ash", 0.8))
	_wave_alpha = float(skin.param("water", "wave_alpha", 0.5))
	_phase = fmod(pool.global_position.x * 0.0137, TAU)
	var t0 := Time.get_ticks_usec()
	_body = TerrainArt.new(skin, pool)
	_body.name = "Body"
	add_child(_body)
	_body._begin(int(size.x) * 7 + 3)
	_body._mod = Color(1, 1, 1, 1)
	var left_open := not _blocked(Vector2(-TUCK - 4.0, 12.0))
	var right_open := not _blocked(Vector2(size.x + TUCK + 4.0, 12.0))
	var depth := size.y + rise + DEPTH_PAD + (OPEN_PAD if left_open or right_open else 0.0)
	_lay_body(size.x, depth, left_open, right_open)
	_body._finish(t0)
	# 물결 띠
	if skin.has_role("wave"):
		var t1 := Time.get_ticks_usec()
		_waves = TerrainArt.new(skin, pool)
		_waves.name = "Waves"
		add_child(_waves)
		_waves._begin(int(size.x) * 5 + 11)
		_waves._mod = Color(1, 1, 1, 1)
		_lay_waves(size.x, left_open, right_open)
		_waves._finish(t1)


## 웅덩이 기준 자리 p 가 다른 지형(방의 Terrain 묶음) 안인가 — 막힌 끝이면 곧게, 아니면 물가 끝
func _blocked(p: Vector2) -> bool:
	var room := TerrainStyle.room_of(pool)
	if room == null:
		return false
	var terrain := room.get_node_or_null("Terrain")
	if terrain == null:
		return false
	var g := pool.global_position + p
	for c in terrain.get_children():
		if c is Platform:
			if Rect2((c as Node2D).global_position, c.size).has_point(g):
				return true
		elif c is TerrainPolygon:
			if Geometry2D.is_point_in_polygon(g - (c as Node2D).global_position, c.polygon):
				return true
	return false


## 몸통: 가운데 토막(조각의 비스듬한 끝은 피함)을 이어 깔고, 열린 끝에는 조각의 물가 끝을 쓴다.
func _lay_body(w: float, depth: float, left_open: bool, right_open: bool) -> void:
	var names := skin.list("water")
	var rng := _body._rng
	var top := func(_x: float) -> float: return 0.0
	var a := -TUCK
	var b := w + TUCK
	# 물가 끝 조각 (양 끝이 비스듬한 조각 — 첫 번째 water 조각): 끝 cap px
	var edge_name: String = names[0]
	var esz := skin.size_of(edge_name)
	var sy := depth / esz.y
	var k := maxf(sy, 0.9)
	var cap_u := minf(150.0, esz.x * 0.2)
	# 열린 끝(물가): 비스듬한 물가 끝이 웅덩이 판정 끝 밖으로 SHORE_OUT 만큼 나가게 (판정 안은 늘 물로 덮인다)
	if left_open:
		a = -cap_u * k * SHORE_OUT
	if right_open:
		b = w + cap_u * k * SHORE_OUT
	var x := a
	var segs: Array = []   # [name, u0, u1, x0, x1, flip]
	if left_open:
		segs.append([edge_name, 0.0, cap_u, x, x + cap_u * k, false])
		x += cap_u * k
	var end_x := b - (cap_u * k if right_open else 0.0)
	var guard := 0
	while x < end_x - 1.0 and guard < 64:
		guard += 1
		var n: String = names[rng.randi_range(0, names.size() - 1)]
		var sz := skin.size_of(n)
		var nk := maxf(depth / sz.y, 0.9)
		var lo := sz.x * 0.08
		var hi := sz.x * 0.9
		var start := x - (OVERLAP if not segs.is_empty() else 0.0)
		var need := end_x - start + (OVERLAP if right_open else 0.0)
		var lu := minf(rng.randf_range(0.6, 1.0) * (hi - lo), hi - lo)
		if need / nk - lu < (hi - lo) * 0.3:
			lu = minf(need / nk, hi - lo)
		var u0 := rng.randf_range(lo, maxf(lo, hi - lu))
		segs.append([n, u0, u0 + lu, start, start + lu * nk, rng.randf() < 0.5])
		x = start + lu * nk
	if right_open:
		segs.append([edge_name, esz.x - cap_u, esz.x, end_x, b, false])
	for i in segs.size():
		var sg: Array = segs[i]
		var n2: String = sg[0]
		var sz2 := skin.size_of(n2)
		var opts := {"y_off": 0.0, "mod": Color(1, 1, 1, 1)}
		if i > 0:
			opts["fade_l"] = OVERLAP
		# 막힌 끝은 지형 속에서 짧게 사라진다 (곧은 끝이 지형 앞에 보이지 않게)
		if i == 0 and not left_open:
			opts["fade_l"] = TUCK + 4.0
		if i == segs.size() - 1 and not right_open:
			opts["fade_r"] = TUCK + 4.0
		# 열린 끝(물가)은 비스듬한 끝을 서서히 사라지게 (유리 상자처럼 딱 끊기지 않게)
		if i == 0 and left_open:
			opts["fade_l"] = SHORE_FADE
		if i == segs.size() - 1 and right_open:
			opts["fade_r"] = SHORE_FADE
		var x1: float = minf(float(sg[4]), b)
		var u1: float = sg[2]
		if x1 < float(sg[4]):
			u1 = float(sg[1]) + (x1 - float(sg[3])) / (float(sg[4]) - float(sg[3])) * (float(sg[2]) - float(sg[1]))
		_body.piece(n2, sg[1], u1, sg[3], x1, top, depth / sz2.y, sg[5], opts)


## 물결 띠: 물결 조각을 낮게 눌러 수면을 따라 잇는다 (양 끝은 서서히 사라짐).
func _lay_waves(w: float, left_open: bool, right_open: bool) -> void:
	var names := skin.list("wave")
	var rng := _waves._rng
	var x := 10.0 if left_open else -4.0
	var end_x := w - (10.0 if right_open else -4.0)
	var first := true
	var guard := 0
	while x < end_x - 1.0 and guard < 64:
		guard += 1
		var n: String = names[rng.randi_range(0, names.size() - 1)]
		var sz := skin.size_of(n)
		var sy := WAVE_H / sz.y
		var k := sy * 1.6
		var start := x - (0.0 if first else OVERLAP)
		var lu := minf(rng.randf_range(300.0, 600.0), sz.x * 0.9)
		var lw := minf(lu * k, end_x - start)
		lu = lw / k
		var u0 := rng.randf_range(sz.x * 0.05, maxf(sz.x * 0.05, sz.x * 0.95 - lu))
		var y_top := -WAVE_H * 0.55
		var opts := {"y_off": 0.0, "mod": Color(1, 1, 1, 1), "fade_l": OVERLAP if not first else 40.0}
		if start + lw >= end_x - 1.0:
			opts["fade_r"] = 40.0
		_waves.piece(n, u0, u0 + lu, start, start + lw, func(_x: float) -> float: return y_top, sy, rng.randf() < 0.5, opts)
		x = start + lw
		first = false


## 매 프레임 (SapPool._process): 정화 정도(alive 0~1)·수액 위 걷기(walk)에 따라 색, 물결 흔들기
func tick(t: float, alive: float, walk: bool) -> void:
	if absf(alive - _last_alive) > 0.002 or walk != _last_walk:
		_last_alive = alive
		_last_walk = walk
		var c := ASH_MOD.lerp(Color(1, 1, 1), alive)
		var a := lerpf(_alpha_ash, _alpha, alive)
		if walk:
			c = c.lightened(0.08)
			a = minf(a + 0.05, 0.95)
		modulate = Color(c.r, c.g, c.b, a)
		if _waves:
			_waves.modulate = Color(1, 1, 1, _wave_alpha * (0.75 + 0.25 * alive) / maxf(a, 0.01))
	if _waves:
		_waves.position = Vector2(sin(t * 0.45 + _phase) * WAVE_SWAY, sin(t * 1.3 + _phase * 2.0) * WAVE_BOB)

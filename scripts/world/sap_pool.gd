extends Area2D
class_name SapPool
## 수액 웅덩이 (확장판 공용). 원점은 왼쪽 위, size 만큼의 수면.
## 수액 위 걷기(능력 "sap_walk")가 없으면: 안에서 느려지고 조금씩 체력이 깎인다 (즉사 아님). 구르기도 짧아진다(roll_slow).
## 능력이 있으면: 수면 위를 미끄러지듯 빠르게 지나고(slow_factor 1.35, 체력 안 깎임) 구르기 거리가 길어진다(roll_glide).
##   (EXPANSION.md 2장 "수액 위에서 구르기 거리가 길어진다" — player.roll_factor 를 이 웅덩이가 매 프레임 정한다)
## **판정(맞는 영역: 높이의 0.2 ~ 1)·surface_y()(여왕의 물결 기준)는 그림과 상관없이 그대로다.**
##
## 그림 (겉모습만 — 지역마다 같은 코드, 색·투명도는 그림 옷 데이터):
##  - 그림 수면은 맞는 영역의 윗변(높이의 SURFACE_FRAC) — 발이 수액에 닿기 시작하는 높이와 같다.
##    region 을 주면 그 지역이 정화된 뒤(Purity) '살아난 수액'으로 수면이 FILL_RISE 만큼 차오른 듯 그린다 (수액의 여왕 정화 연출).
##    방이 뜰 때의 상태로 시작하고, 그 뒤로는 Purity.region_changed 신호(색이 번져 돌아오는 연출·초기화)가 올 때만 바뀐다
##    → 회상에서 돌아와 잠깐 잿빛으로 돌렸다가 번지게 하는 BossRoom 연출과 맞물려 '살아남 → 잿빛 → 차오름'으로 깜빡이지 않는다.
##  - 방의 지형 그림 옷(TerrainSkin — 방마다 다르면 room_skins)에 water 조각(기획자의 '물 지형' 시트)이 있으면 몸통을 그림으로 그린다:
##      물빛(Deep): 지역 물 색(params.water.deep)의 비치는 그라데이션 — 위는 옅고 깊을수록 진하다(alpha [위, 아래]). 물의 색과 깊이를 맡는다.
##      결(Body): water 조각의 가운데 토막을 웅덩이 폭에 이어 붙여 그 위에 옅게(art_alpha, tint) — 물결무늬·수면 테두리를 맡는다.
##            조각 아랫부분(그려진 바위 바닥)은 쓰지 않는다(band).
##      두 겹 모두 아래끝은 웅덩이 밑 바닥 윗면 아래로 FLOOR_SINK px 동안 녹아들어 '바닥이 비치는 고인 물'로 읽힌다.
##      끝: 옆이 지형에 막혔으면 지형 속으로 TUCK px, 열려 있으면 판정 끝 밖 SHORE_OUT px 까지 서서히 사라지는 물가.
##      물결: wave 조각을 수면에 얹고 천천히 흔든다 (위치만 — 다시 만들지 않음).
##      정화 전에는 탁하다 (deep_ash·alpha_ash·tint_ash·art_alpha_ash — 잿빛 표를 거쳐 회색이 된다), 정화되면(방의 지역 Purity) 맑아지고, 수액 위 걷기가 있으면 조금 밝다.
##    water 조각이 없는 그림 옷이면 몸통을 코드로 그린다 (깊이 그라데이션 6줄).
##  - 그 위에 코드로: 흐르는 빛 띠, 떠오르는 방울, 일렁이는 수면선(밝은 테두리), 소녀 발 자리의 납작한 잔물결 고리.
## 세기 조절: 아래 상수들과 data/terrain/<그림 옷>.json 의 params.water (TERRAIN.md 6장).

@export var size := Vector2(600, 120):
	set(v):
		size = v
		_rebuild()
		queue_redraw()
@export var dps := 5.0
@export var slow := 0.5
@export var glide := 1.35
## 구르기 속도 배수: 능력 없을 때 / 있을 때
@export var roll_slow := 0.6
@export var roll_glide := 1.4
@export var color := Color(0.25, 0.55, 0.75, 0.55)
## 이 지역이 정화되면 살아난 수액으로 보인다 (비우면 늘 잿빛 수액)
@export var region := ""

## 살아난 수액의 색(코드로 그리는 몸통)과 차오르는 높이(px, 그림만)
const ALIVE_COLOR := Color(0.3, 0.75, 0.85, 0.7)
const FILL_RISE := 22.0
## 그림 수면 = 웅덩이 높이의 이 비율 (맞는 영역의 윗변)
const SURFACE_FRAC := 0.2
## 수면선 굵기·일렁임 간격(px)
const SURFACE_WIDTH := 3.0
const SURFACE_STEP := 16.0
## 빛 띠(흐르는 하이라이트) 개수와 방울 개수
const STREAK_COUNT := 5
const BUBBLE_COUNT := 14
## 물 그림: 토막 겹침, 막힌 끝을 지형 속으로 밀어 넣는 길이, 열린 끝(물가)이 판정 끝 밖으로 나가는 길이·사라지는 길이,
## 몸통 아래끝이 바닥 윗면 아래로 녹아드는 길이 (px)
const ART_OVERLAP := 110.0
const TUCK := 6.0
const SHORE_OUT := 90.0
const SHORE_FADE := 150.0
const FLOOR_SINK := 22.0
## 물결 띠 흔들림 (px)
const WAVE_SWAY := 7.0
const WAVE_BOB := 1.6

var _shape: CollisionShape2D
var _t := 0.0
var _tick := 0.0
var _alive := 0.0       # 0 잿빛 → 1 살아남 (차오름 — region 이 있을 때만, 감쇠 보간)
var _alive_target := 0.0
var _clear := 0.0       # 0 탁함 → 1 맑음 (방의 지역이 정화됐는가 — 물 그림의 색·투명도)
var _clear_target := 0.0
var _players_in: Array = []
var _seed := 0
var _rng := RandomNumberGenerator.new()   # 그릴 때마다 같은 씨앗으로 되감아 쓴다 (매 프레임 새로 만들지 않게)
## 물 그림 (그림 옷에 water 조각이 있을 때만): Water 노드 아래 몸통·물결 (TerrainArt — 방에 들어올 때 한 번 만든다)
var _art: Node2D
var _deep: TerrainArt
var _body: TerrainArt
var _waves: TerrainArt
var _wp := {}           # params.water 를 읽어 둔 값
var _last_look := Vector3(-1, -1, -1)
var _phase := 0.0
## 물 뒤 탁한 막 (params.water.murk 가 있는 그림 옷만): 지형 묶음 맨 아래(뒤 그림자보다 뒤)에 까는 RenderingServer 항목 —
## 물 아래로 먼 배경 그림이 밝게 비쳐 돌·호수 바닥 사이가 옅은 유리 상자처럼 보이지 않게 한다 (지형 뒤라 돌·바닥은 그대로 비친다).
var _murk_ci := RID()
var _murk_y := INF
const MURK_DRAW_INDEX := -300000
var _deep_top := PackedInt32Array()      # 물빛 겹의 수면 줄 꼭짓점 (위 진하기가 정화 전·후로 달라 _tick_art 가 바꾼다)
var _deep_top_a := PackedFloat32Array()  # 그 꼭짓점의 물가 알파


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	_rebuild()
	material = preload("res://shaders/ash_purify_add.tres")
	_seed = int(global_position.x * 3.0 + global_position.y * 7.0 + size.x)
	_sync_start()
	_build_art()
	Purity.region_changed.connect(_on_region_changed)
	# 방(BossRoom)의 _ready 가 이 뒤에 지역 상태를 바꿀 수 있다 (회상에서 막 돌아와 잠깐 잿빛으로 돌림) → 한 번 더 맞춘다
	_sync_start.call_deferred()


func _sync_start() -> void:
	_alive_target = 1.0 if _is_alive() else 0.0
	_alive = _alive_target
	_clear_target = 1.0 if Purity.is_purified(TerrainStyle.region_of(self)) else 0.0
	_clear = _clear_target


func _on_region_changed(r: String, purified: bool) -> void:
	if region != "" and r == region:
		_alive_target = 1.0 if purified else 0.0
	if r == TerrainStyle.region_of(self):
		_clear_target = 1.0 if purified else 0.0
	queue_redraw()


func _rebuild() -> void:
	if _shape == null:
		_shape = CollisionShape2D.new()
		add_child(_shape)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x, size.y * 0.8)
	_shape.shape = rect
	_shape.position = Vector2(size.x / 2.0, size.y * 0.6)


func can_walk() -> bool:
	return Progress.has_ability("sap_walk")


func _is_alive() -> bool:
	return region != "" and Purity.is_purified(region)


## 수면의 세계 y (여왕이 물결을 띄우는 기준 — 판정 쪽 값, 그림과 상관없다)
func surface_y() -> float:
	return global_position.y


## 그림 수면의 높이 (노드 기준 y): 맞는 영역 윗변, 살아난 수액은 차오른 만큼 위
func surface_top() -> float:
	return size.y * SURFACE_FRAC - FILL_RISE * _alive


func _process(delta: float) -> void:
	_t += delta
	_alive = lerpf(_alive, _alive_target, 1.0 - exp(-1.2 * delta))
	_clear = lerpf(_clear, _clear_target, 1.0 - exp(-1.2 * delta))
	if _art:
		_art.position.y = surface_top()
		_place_murk()
		_tick_art()
	queue_redraw()


func _physics_process(delta: float) -> void:
	_tick -= delta
	_players_in.clear()
	for b in get_overlapping_bodies():
		if b is Player:
			_players_in.append(b)
			if can_walk():
				b.slow_factor = glide
				b.roll_factor = roll_glide
			else:
				b.slow_factor = slow
				b.roll_factor = roll_slow
				if _tick <= 0.0:
					b.take_damage_over_time(dps * 0.5)
	if _tick <= 0.0:
		_tick = 0.5


func _surface_y(x: float, top: float) -> float:
	return top + 3.0 * sin(x * 0.03 + _t * 2.2) + 2.0 * sin(x * 0.011 - _t * 1.3)


func _draw() -> void:
	var walk := can_walk()
	var top := surface_top()
	if _art == null:
		# 물 그림이 없는 그림 옷: 몸통을 코드로 (수면 띠는 밝고 아래로 갈수록 어둡고 진하다 — 가로 띠 6줄)
		var base := color.lerp(ALIVE_COLOR, _alive)
		if walk:
			base = Color(base.r + 0.08, base.g + 0.12, base.b + 0.08, minf(base.a + 0.15, 0.85))
		var rows := 6
		var h := size.y - top
		for i in rows:
			var t0 := float(i) / rows
			var t1 := float(i + 1) / rows
			var c := base.lerp(Color(base.r * 0.35, base.g * 0.4, base.b * 0.5, base.a * 1.15), t0)
			var y0 := top + h * t0 + (6.0 if i > 0 else 0.0)
			draw_rect(Rect2(Vector2(0, y0), Vector2(size.x, h * (t1 - t0) + (0.0 if i == rows - 1 else 7.0))), Color(c, c.a * 0.9))
	var hl: Color = _wp.get("line", Color(0.75, 0.95, 1.0))
	# 흐르는 빛 띠 (수면 바로 아래를 천천히 지나간다)
	var rng := _rng
	rng.seed = _seed
	var lit := maxf(_alive, _clear)
	for i in STREAK_COUNT:
		var speed := rng.randf_range(18.0, 40.0)
		var len := rng.randf_range(80.0, 180.0)
		var phase := rng.randf() * size.x
		var x := fmod(phase + _t * speed, size.x + len) - len
		var y := top + 10.0 + rng.randf_range(4.0, 18.0)
		var a := (0.1 + 0.12 * lit) * (0.6 + 0.4 * sin(_t * 1.1 + i))
		draw_line(Vector2(maxf(x, 0.0), y), Vector2(minf(x + len, size.x), y), Color(hl.lightened(0.3), a), 2.0, true)
	# 떠오르는 방울
	for i in BUBBLE_COUNT:
		var bx := rng.randf() * size.x
		var period := rng.randf_range(2.5, 5.0)
		var k := fmod(_t / period + rng.randf(), 1.0)
		var by := size.y - k * (size.y - top - 8.0)
		var r := 1.5 + rng.randf() * 2.5
		draw_circle(Vector2(bx + sin(k * TAU + i) * 4.0, by), r, Color(hl.lightened(0.4), 0.25 * (1.0 - k) + 0.1 * lit))
	# 일렁이는 수면선 (앞 한 줄 밝게, 뒤 한 줄 흐리게 — 두 겹이면 물결이 두꺼워 보인다)
	var pts := PackedVector2Array()
	var pts2 := PackedVector2Array()
	var x2 := 0.0
	while x2 <= size.x:
		pts.append(Vector2(x2, _surface_y(x2, top)))
		pts2.append(Vector2(x2, _surface_y(x2 + 40.0, top) + 5.0))
		x2 += SURFACE_STEP
	var line_a := (0.85 if walk else 0.6) + 0.15 * lit
	if _art:
		line_a *= float(_wp.get("line_alpha", 0.55))   # 그림의 수면 테두리 위에 옅게
	draw_polyline(pts2, Color(hl.darkened(0.15), line_a * 0.35), SURFACE_WIDTH * 1.6, true)
	draw_polyline(pts, Color(hl, line_a), SURFACE_WIDTH, true)
	# 소녀가 빠져 있으면 발 자리의 잔물결 고리 (수면에 누운 납작한 고리)
	for p in _players_in:
		if not is_instance_valid(p):
			continue
		var lp: Vector2 = to_local(p.global_position + Vector2(0, 60.0))
		var ring := fmod(_t * 1.6, 1.0)
		var ring2 := fmod(ring + 0.5, 1.0)
		draw_set_transform(Vector2(lp.x, top + 3.0), 0.0, Vector2(1.0, 0.32))
		draw_arc(Vector2.ZERO, 18.0 + ring * 40.0, 0.0, TAU, 28, Color(hl.lightened(0.3), 0.45 * (1.0 - ring)), 3.0, true)
		draw_arc(Vector2.ZERO, 10.0 + ring2 * 40.0, 0.0, TAU, 28, Color(hl.lightened(0.3), 0.32 * (1.0 - ring2)), 3.0, true)
		draw_set_transform(Vector2.ZERO)


# ---------------------------------------------------------------- 물 그림
## 그림 옷에 water 조각이 있으면 몸통·물결을 만든다 (방에 들어올 때 한 번). 없으면 아무것도 안 함 (코드로 그린다).
func _build_art() -> void:
	var skin := TerrainSkin.for_node(self)
	if skin == null or not skin.has_role("water"):
		return
	var t0 := Time.get_ticks_usec()
	_wp = {
		"deep": _col(skin.param("water", "deep", "#1f5f80")),
		"deep_ash": _col(skin.param("water", "deep_ash", "#44504c")),
		"alpha": skin.param("water", "alpha", [0.2, 0.62]),
		"alpha_ash": skin.param("water", "alpha_ash", [0.32, 0.74]),
		"tint": _col(skin.param("water", "tint", [0.8, 0.95, 1.0])),
		"tint_ash": _col(skin.param("water", "tint_ash", [0.85, 0.88, 0.86])),
		"art_alpha": float(skin.param("water", "art_alpha", 0.42)),
		"art_alpha_ash": float(skin.param("water", "art_alpha_ash", 0.36)),
		"band": float(skin.param("water", "band", 0.62)),
		"wave_alpha": float(skin.param("water", "wave_alpha", 0.45)),
		"wave_h": float(skin.param("water", "wave_h", 24.0)),
		"line": _col(skin.param("water", "line", [0.75, 0.95, 1.0])),
		"line_alpha": float(skin.param("water", "line_alpha", 0.55)),
		"murk": skin.param("water", "murk", null),
	}
	_phase = fmod(global_position.x * 0.0137, TAU)
	_art = Node2D.new()
	_art.name = "Water"
	_art.show_behind_parent = true   # 코드로 그리는 빛 띠·방울·수면선이 그림 위에
	_art.material = preload("res://shaders/ash_purify.tres")   # 웅덩이 자체는 더하기 혼합이지만 물 그림은 보통 혼합
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.position.y = surface_top()
	add_child(_art)
	var surf0 := size.y * SURFACE_FRAC
	var left_open := not _blocked(Vector2(-TUCK - 4.0, surf0 + 12.0))
	var right_open := not _blocked(Vector2(size.x + TUCK + 4.0, surf0 + 12.0))
	# 물 깊이: 웅덩이 밑 바닥 윗면까지 (없으면 웅덩이 바닥까지). 차오름(살아난 수액)만큼 더 — 차올라도 아래가 비지 않게
	var floor_y := minf(_floor_below(), size.y)
	var water_d := maxf(floor_y - surf0, 20.0) + (FILL_RISE if region != "" else 0.0)
	_deep = _new_art("Deep", skin, int(size.x) * 3 + 1)
	_lay_deep(water_d, left_open, right_open)
	_make_murk(water_d, left_open, right_open)
	_deep._finish(t0)
	_body = _new_art("Body", skin, int(size.x) * 7 + 3)
	_lay_body(skin, water_d, left_open, right_open)
	_body._finish(Time.get_ticks_usec())
	if skin.has_role("wave"):
		_waves = _new_art("Waves", skin, int(size.x) * 5 + 11)
		_lay_waves(skin, left_open, right_open)
		_waves._finish(Time.get_ticks_usec())
	_last_look = Vector3(-1, -1, -1)
	_tick_art()


func _new_art(n: String, skin: TerrainSkin, seed_extra: int) -> TerrainArt:
	var a := TerrainArt.new(skin, self)
	a.name = n
	a.cast_shadow = false   # 물은 앞 지형 뒤 그림자를 드리우지 않는다
	_art.add_child(a)
	a._begin(seed_extra)
	a._mod = Color(1, 1, 1, 1)
	return a


static func _col(v) -> Color:
	if v is Array and v.size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	if v is String:
		return Color.html(v)
	return Color.WHITE


## 웅덩이 기준 자리 p 가 다른 지형(방의 Terrain 묶음) 안인가 — 막힌 끝이면 지형 속으로, 아니면 물가
func _blocked(p: Vector2) -> bool:
	var terrain := _terrain()
	if terrain == null:
		return false
	var g := global_position + p
	for c in terrain.get_children():
		if c is Platform:
			if Rect2((c as Node2D).global_position, c.size).has_point(g):
				return true
		elif c is TerrainPolygon:
			if Geometry2D.is_point_in_polygon(g - (c as Node2D).global_position, c.polygon):
				return true
	return false


func _terrain() -> Node:
	var room := TerrainStyle.room_of(self)
	return room.get_node_or_null("Terrain") if room else null


## 웅덩이 아래(가운데 절반 폭)에 있는 지형 바닥의 윗면 y (이 노드 기준, 그림 수면보다 아래인 것 중 가장 높은 것). 없으면 INF.
func _floor_below() -> float:
	var terrain := _terrain()
	if terrain == null:
		return INF
	var gx0 := global_position.x + size.x * 0.25
	var gx1 := global_position.x + size.x * 0.75
	var gs := global_position.y + size.y * SURFACE_FRAC
	var best := INF
	for c in terrain.get_children():
		if not (c is Platform):
			continue
		var r := Rect2((c as Node2D).global_position, c.size)
		if r.end.x < gx0 or r.position.x > gx1 or r.position.y < gs - 2.0:
			continue
		best = minf(best, r.position.y)
	return best - global_position.y if best < INF else INF


## 물빛: 수면(0)에서 water_d(바닥 윗면)까지 위가 옅고 깊을수록 진한 그라데이션, 그 아래 FLOOR_SINK px 동안 사라진다.
## 양 끝은 막혔으면 지형 속으로 짧게, 열렸으면(물가) SHORE_FADE px 동안 서서히. 흰색으로 만들고 색·진하기는 _tick_art 가 modulate 로 입힌다.
func _lay_deep(water_d: float, left_open: bool, right_open: bool) -> void:
	var top_a := _deep_top_ratio(0.0)
	var a := -SHORE_OUT if left_open else -TUCK
	var b := size.x + (SHORE_OUT if right_open else TUCK)
	var fl := SHORE_FADE if left_open else TUCK + 4.0
	var fr := SHORE_FADE if right_open else TUCK + 4.0
	var xs := PackedFloat32Array([a, minf(a + fl, (a + b) * 0.5), maxf(b - fr, (a + b) * 0.5), b])
	var xa := PackedFloat32Array([0.0, 1.0, 1.0, 0.0])
	var ys := PackedFloat32Array([0.0, water_d, water_d + FLOOR_SINK])
	var ya := PackedFloat32Array([top_a, 1.0, 0.0])
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	_deep_top = PackedInt32Array()
	_deep_top_a = PackedFloat32Array()
	for xi in 4:
		for yi in 3:
			if yi == 0:
				_deep_top.append(pts.size())
				_deep_top_a.append(xa[xi])
			pts.append(Vector2(xs[xi], ys[yi]))
			cols.append(Color(1, 1, 1, xa[xi] * ya[yi]))
	var idx := PackedInt32Array()
	for xi in 3:
		for yi in 2:
			var p := xi * 3 + yi
			idx.append_array(PackedInt32Array([p, p + 1, p + 3, p + 1, p + 4, p + 3]))
	_deep._tris(TerrainArt.BUF_PLAIN, pts, PackedVector2Array(), cols, idx)


## 물 뒤 탁한 막 (위 _murk_ci 설명). params.water.murk = {"color": 정화 후 색, "color_ash": 정화 전 색, "top": 수면 바로 아래 진하기, "full": 다 진해지는 깊이(px)}.
## 가로는 물빛 겹과 같은 물가 사라짐, 세로는 수면에서 top → full px 아래 1 → 바닥 윗면 아래 FLOOR_SINK 까지 (바닥 뒤라 거기서 끝나도 안 보인다).
func _make_murk(water_d: float, left_open: bool, right_open: bool) -> void:
	_free_murk()
	var mk = _wp.get("murk", null)
	var terrain := _terrain()
	if not (mk is Dictionary) or not (terrain is CanvasItem):
		return
	var top_a := clampf(float(mk.get("top", 0.4)), 0.0, 1.0)
	var full := clampf(float(mk.get("full", 30.0)), 1.0, maxf(water_d, 1.0))
	var a := -SHORE_OUT if left_open else -TUCK
	var b := size.x + (SHORE_OUT if right_open else TUCK)
	var fl := SHORE_FADE if left_open else TUCK + 4.0
	var fr := SHORE_FADE if right_open else TUCK + 4.0
	var xs := PackedFloat32Array([a, minf(a + fl, (a + b) * 0.5), maxf(b - fr, (a + b) * 0.5), b])
	var xa := PackedFloat32Array([0.0, 1.0, 1.0, 0.0])
	var ys := PackedFloat32Array([0.0, full, water_d + FLOOR_SINK])
	var ya := PackedFloat32Array([top_a, 1.0, 1.0])
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for xi in 4:
		for yi in 3:
			pts.append(Vector2(xs[xi], ys[yi]))
			cols.append(Color(1, 1, 1, xa[xi] * ya[yi]))
	var idx := PackedInt32Array()
	for xi in 3:
		for yi in 2:
			var p := xi * 3 + yi
			idx.append_array(PackedInt32Array([p, p + 1, p + 3, p + 1, p + 4, p + 3]))
	var rs := RenderingServer
	_murk_ci = rs.canvas_item_create()
	rs.canvas_item_set_parent(_murk_ci, (terrain as CanvasItem).get_canvas_item())
	rs.canvas_item_set_draw_index(_murk_ci, MURK_DRAW_INDEX)
	rs.canvas_item_set_material(_murk_ci, preload("res://shaders/ash_purify.tres").get_rid())
	rs.canvas_item_add_triangle_array(_murk_ci, idx, pts, cols)
	rs.canvas_item_set_visible(_murk_ci, is_visible_in_tree())
	_murk_y = INF
	_place_murk()


## 막의 자리 (그림 수면을 따라 — 차오르면 같이 올라간다). 바뀔 때만 보낸다.
func _place_murk() -> void:
	if not _murk_ci.is_valid() or _art == null:
		return
	var terrain := _terrain()
	if not (terrain is CanvasItem):
		return
	var y := _art.position.y
	if absf(y - _murk_y) < 0.05:
		return
	_murk_y = y
	var xf := (terrain as CanvasItem).get_global_transform().affine_inverse() * get_global_transform() * Transform2D(0.0, Vector2(0.0, y))
	RenderingServer.canvas_item_set_transform(_murk_ci, xf)


func _free_murk() -> void:
	if _murk_ci.is_valid():
		RenderingServer.free_rid(_murk_ci)
	_murk_ci = RID()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_EXIT_TREE, NOTIFICATION_PREDELETE:
			_free_murk()
		NOTIFICATION_VISIBILITY_CHANGED:
			if _murk_ci.is_valid():
				RenderingServer.canvas_item_set_visible(_murk_ci, is_visible_in_tree())


## 시험용: 물 뒤 탁한 막이 있는가
func has_murk() -> bool:
	return _murk_ci.is_valid()


## 물빛 겹의 위 진하기 ÷ 깊은 곳 진하기 (정화 정도 c 에서) — alpha / alpha_ash 의 [위, 아래] 를 그대로 따른다.
## 깊은 곳 진하기는 modulate.a 가, 위는 이 비율 × modulate.a 가 된다.
func _deep_top_ratio(c: float) -> float:
	var aa: Array = _wp["alpha_ash"]
	var al: Array = _wp["alpha"]
	var r_ash := clampf(float(aa[0]) / maxf(float(aa[1]), 0.01), 0.0, 1.0)
	var r_al := clampf(float(al[0]) / maxf(float(al[1]), 0.01), 0.0, 1.0)
	return lerpf(r_ash, r_al, c)


## 결: water 조각들의 가운데 토막(조각 양 끝의 비탈은 피함)을 이어 깐다. 조각의 위(수면 테두리)~band 까지만 쓰고
## water_d px 아래(바닥 윗면)부터 FLOOR_SINK px 동안 사라진다 (물빛 위에 옅게 — 진하기는 _tick_art 가 art_alpha 로).
func _lay_body(skin: TerrainSkin, water_d: float, left_open: bool, right_open: bool) -> void:
	var names := skin.list("water")
	var rng := _body._rng
	var top := func(_x: float) -> float: return 0.0
	var a := -SHORE_OUT if left_open else -TUCK
	var b := size.x + (SHORE_OUT if right_open else TUCK)
	var top_a := 0.75   # 수면 바로 아래 결은 조금 옅게 (테두리는 남는다)
	var x := a
	var first := true
	var guard := 0
	while x < b - 1.0 and guard < 64:
		guard += 1
		var n: String = names[rng.randi_range(0, names.size() - 1)]
		var sz := skin.size_of(n)
		# 크기: 조각의 쓰는 높이(band)가 물 깊이 + 녹아드는 길이를 덮게 (0.6~1.5 배)
		var k := clampf((water_d + FLOOR_SINK) / (sz.y * float(_wp["band"])), 0.6, 1.5)
		var lo := sz.x * 0.1
		var hi := sz.x * 0.9
		var start := x - (0.0 if first else ART_OVERLAP)
		var need := (b - start) / k
		var lu := minf(rng.randf_range(0.6, 1.0) * (hi - lo), hi - lo)
		if need - lu < (hi - lo) * 0.3:
			lu = minf(need, hi - lo)
		var u0 := rng.randf_range(lo, maxf(lo, hi - lu))
		var x1 := minf(start + lu * k, b)
		var last := x1 >= b - 1.0
		var opts := {"y_off": 0.0, "mod": Color(1, 1, 1, 1), "band": water_d / k, "band_fade": FLOOR_SINK / k, "top_alpha": top_a}
		if not first:
			opts["fade_l"] = ART_OVERLAP
		elif left_open:
			opts["fade_l"] = SHORE_FADE
		else:
			opts["fade_l"] = TUCK + 4.0
		if last:
			opts["fade_r"] = SHORE_FADE if right_open else TUCK + 4.0
		_body.piece(n, u0, u0 + (x1 - start) / k, start, x1, top, k, rng.randf() < 0.5, opts)
		x = x1
		first = false


## 물결 띠: wave 조각을 낮게 눌러 수면을 따라 잇는다 (양 끝은 서서히 사라짐).
func _lay_waves(skin: TerrainSkin, left_open: bool, right_open: bool) -> void:
	var names := skin.list("wave")
	var rng := _waves._rng
	var wh: float = _wp["wave_h"]
	var x := -SHORE_OUT * 0.5 if left_open else -4.0
	var end_x := size.x + (SHORE_OUT * 0.5 if right_open else 4.0)
	var first := true
	var guard := 0
	while x < end_x - 1.0 and guard < 64:
		guard += 1
		var n: String = names[rng.randi_range(0, names.size() - 1)]
		var sz := skin.size_of(n)
		var sy := wh / sz.y
		var k := sy * 1.6
		var start := x - (0.0 if first else ART_OVERLAP)
		var lu := minf(rng.randf_range(300.0, 600.0), sz.x * 0.9)
		var lw := minf(lu * k, end_x - start)
		lu = lw / k
		var u0 := rng.randf_range(sz.x * 0.05, maxf(sz.x * 0.05, sz.x * 0.95 - lu))
		var y_top := -wh * 0.55
		var opts := {"y_off": 0.0, "mod": Color(1, 1, 1, 1), "fade_l": (SHORE_FADE * 0.6 if left_open else 40.0) if first else ART_OVERLAP}
		if start + lw >= end_x - 1.0:
			opts["fade_r"] = SHORE_FADE * 0.6 if right_open else 40.0
		_waves.piece(n, u0, u0 + lu, start, start + lw, func(_x: float) -> float: return y_top, sy, rng.randf() < 0.5, opts)
		x = start + lw
		first = false


## 매 프레임: 맑음(정화)·수액 위 걷기에 따라 색·투명도를 바꾸고 (바뀔 때만), 물결을 흔든다.
func _tick_art() -> void:
	var walk := can_walk()
	var look := Vector3(snappedf(_clear, 0.004), 1.0 if walk else 0.0, 0.0)
	if look != _last_look:
		_last_look = look
		var aa: Array = _wp["alpha_ash"]
		var al: Array = _wp["alpha"]
		var d: Color = (_wp["deep_ash"] as Color).lerp(_wp["deep"], _clear)
		var c: Color = (_wp["tint_ash"] as Color).lerp(_wp["tint"], _clear)
		if walk:
			d = d.lightened(0.08)
			c = c.lightened(0.08)
		_deep.modulate = Color(d.r, d.g, d.b, lerpf(float(aa[1]), float(al[1]), _clear))
		# 위 진하기: 정화 전 alpha_ash[0] → 정화 후 alpha[0] (꼭짓점 몇 개만 바꿔 다시 그린다 — 바뀔 때만)
		var buf: Dictionary = _deep._bufs[TerrainArt.BUF_PLAIN]
		var cols: PackedColorArray = buf["cols"]
		var ta := _deep_top_ratio(_clear)
		for j in _deep_top.size():
			if _deep_top[j] < cols.size():
				cols[_deep_top[j]] = Color(1, 1, 1, _deep_top_a[j] * ta)
		buf["cols"] = cols
		_deep.queue_redraw()
		if _murk_ci.is_valid():
			var mk: Dictionary = _wp["murk"]
			var mc := _col(mk.get("color_ash", "#3c4644")).lerp(_col(mk.get("color", "#2c5266")), _clear)
			RenderingServer.canvas_item_set_modulate(_murk_ci, Color(mc.r, mc.g, mc.b, 1.0))
		_body.modulate = Color(c.r, c.g, c.b, lerpf(float(_wp["art_alpha_ash"]), float(_wp["art_alpha"]), _clear))
		if _waves:
			_waves.modulate = Color(1, 1, 1, float(_wp["wave_alpha"]) * (0.7 + 0.3 * _clear))
	if _waves:
		_waves.position = Vector2(sin(_t * 0.45 + _phase) * WAVE_SWAY, sin(_t * 1.3 + _phase * 2.0) * WAVE_BOB)

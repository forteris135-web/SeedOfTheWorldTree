class_name PoolArt
extends Node2D
## 수액 웅덩이(SapPool)의 그림 옷 — 기획자의 물 지형 그림(익스펜션/그림/지형/물 지형.png)으로 그린다.
## 방 파일에서 SapPool 의 자식으로 붙인다 (SapPool 코드는 건드리지 않는다 — 판정·느려짐·능력은 SapPool 그대로).
## 지역 그림 옷(TerrainSkin)에 water_body(웅덩이 몸통) / water_wave(수면 물결) 조각이 있을 때만 그리고,
## 없으면 스스로 사라져 SapPool 의 옛 코드 그림이 그대로 보인다.
##
## 그리는 것 (아래 → 위):
##  - 몸통: 물웅덩이 조각(양 끝이 바위로 비스듬한 그림)을 웅덩이 폭에 맞춰 왼끝 + 가운데 토막 + 오른끝으로 이어 붙인다.
##          수면은 판정(SapPool 의 맞는 영역 윗변 = 높이의 SURFACE_FRAC)에 맞춘다 — 발이 수액에 닿는 높이와 그림 수면이 같다.
##          조금 비치게(params.water.alpha) 그려 아래 바닥이 희미하게 보인다.
##  - 물결 두 겹: 수면에 가는 물결 띠. 노드를 좌우로 천천히 흔들어(다시 그리지 않고 위치만) 일렁이게 한다.
##  - 잔물결 고리: 소녀가 안에 있을 때만 발 자리에 (그때만 다시 그린다).
## 정화 전·후 색은 공용 잿빛 재질(팔레트 바꾸기)이 바꾼다. 수액 위 걷기를 얻으면 조금 밝아진다.
## 세기 조절: 아래 상수와 data/terrain/<지역>.json 의 params.water (cap 끝 비율, alpha, wave_alpha, wave_h).

## 그림 수면 = 웅덩이 높이의 이 비율 (SapPool 의 맞는 영역이 0.2h ~ h)
const SURFACE_FRAC := 0.2
## 물결 띠 흔들림 폭(px)·빠르기
const SWAY := 12.0
const SWAY_SPEED := 0.55
## 이어 붙이는 토막 겹침(px)
const OVERLAP := 40.0
## 수액 위 걷기가 있을 때 밝기
const WALK_BRIGHT := Color(1.12, 1.14, 1.12)

var _pool: Node2D
var _skin: TerrainSkin
var _body: TerrainArt
var _waves: Array = []
var _rings: Node2D
var _t := 0.0
var _surface := 0.0
var _size := Vector2.ZERO


func _ready() -> void:
	_pool = get_parent() as Node2D
	if _pool == null or not ("size" in _pool):
		queue_free()
		return
	_skin = TerrainSkin.for_node(_pool)
	if _skin == null or not _skin.has_role("water_body"):
		queue_free()   # 그림 옷이 없는 지역 — SapPool 의 옛 그림 그대로
		return
	material = preload("res://shaders/ash_purify.tres")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# SapPool 의 코드 그림은 감춘다 (자기 그림만 — 자식인 이 노드는 그대로 보인다). _process 는 그림용이라 멈춰도 판정과 상관없다.
	_pool.self_modulate.a = 0.0
	_pool.set_process(false)
	_t = fmod(_pool.global_position.x * 0.0137, TAU)
	_build()
	_apply_walk()
	if not Progress.ability_gained.is_connected(_on_ability):
		Progress.ability_gained.connect(_on_ability)


func _on_ability(_a: String) -> void:
	_apply_walk()


func _apply_walk() -> void:
	var walk: bool = _pool.has_method("can_walk") and _pool.can_walk()
	modulate = WALK_BRIGHT if walk else Color(1, 1, 1)


func _build() -> void:
	_size = _pool.size
	_surface = _size.y * SURFACE_FRAC
	var cap_f := float(_skin.param("water", "cap", 0.13))
	var alpha := float(_skin.param("water", "alpha", 0.8))
	# 몸통: 수면 조금 위(가장자리 빛 테두리)부터 바닥까지. 웅덩이 아래에 지형 바닥이 있으면 그 윗면 조금 아래까지만
	# (얕은 웅덩이가 바닥 위에 유리 덩어리처럼 서 보이지 않게 — 바위 테두리가 바닥 윗선을 덮는다)
	_body = _make_art("Body")
	var body_names: Array = _skin.list("water_body")
	var depth := _size.y - _surface + 16.0
	var floor_y := _floor_below()
	if floor_y < INF:
		depth = clampf(floor_y - _surface + 14.0, 30.0, depth)
	_lay(_body, _pick(body_names, _size.x, depth), 0.0, _size.x, _surface - 3.0, depth, cap_f, Color(1, 1, 1, alpha), 0.0)
	_body._finish(Time.get_ticks_usec())
	# 물결 두 겹 (앞 겹이 조금 크고 진하다)
	if _skin.has_role("water_wave"):
		var wave_names: Array = _skin.list("water_wave")
		var wh := float(_skin.param("water", "wave_h", 16.0))
		var wa := float(_skin.param("water", "wave_alpha", 0.75))
		for i in 2:
			var w := _make_art("Wave%d" % i)
			var h := wh * (0.75 if i == 0 else 1.0)
			var name: String = wave_names[(i + int(absf(_pool.global_position.x)) / 97) % wave_names.size()]
			_lay(w, name, 4.0, _size.x - 4.0, _surface - h * 0.7 + 2.0 * i, h, 0.0, Color(1.25, 1.3, 1.35, wa * (0.6 if i == 0 else 1.0)), 36.0)
			w._finish(Time.get_ticks_usec())
			_waves.append(w)
	_rings = Node2D.new()
	_rings.name = "Rings"
	_rings.use_parent_material = true
	_rings.draw.connect(_draw_rings)
	add_child(_rings)


## 웅덩이 아래(가운데 절반 폭)에 있는 지형 바닥의 윗면 y (이 노드 기준, 수면보다 아래인 것 중 가장 높은 것). 없으면 INF.
func _floor_below() -> float:
	var room := TerrainStyle.room_of(_pool)
	var terrain := room.get_node_or_null("Terrain") if room else null
	if terrain == null:
		return INF
	var gx0 := _pool.global_position.x + _size.x * 0.25
	var gx1 := _pool.global_position.x + _size.x * 0.75
	var gs := _pool.global_position.y + _surface
	var best := INF
	for c in terrain.get_children():
		if not (c is Platform):
			continue
		var r := Rect2((c as Node2D).global_position, c.size)
		if r.end.x < gx0 or r.position.x > gx1 or r.position.y < gs - 2.0:
			continue
		best = minf(best, r.position.y)
	return best - _pool.global_position.y if best < INF else INF


func _make_art(n: String) -> TerrainArt:
	var a := TerrainArt.new(_skin, _pool)
	a.name = n
	add_child(a)
	a._begin(n.hash() & 0xffff)
	return a


## 폭 w·깊이 d 에 맞는 몸통 조각 (가로세로 비율이 가까운 것)
func _pick(names: Array, w: float, d: float) -> String:
	var best := ""
	var best_cost := INF
	for n in names:
		var s := _skin.size_of(n)
		var k := d / s.y
		var cost := absf(log(maxf(w, 1.0) / (s.x * k)))
		if cost < best_cost:
			best_cost = cost
			best = n
	return best


## 조각 하나를 xa..xb 에 깐다: 맨 위가 y_top, 높이 h. 폭이 조각보다 많이 길면 왼끝 + 가운데 토막들 + 오른끝으로 잇는다.
## cap_f: 조각 양 끝(바위 비탈) 비율 (0 이면 끝 없이 가운데만 이어 붙인다). edge_fade: 양 끝을 이만큼 서서히.
func _lay(art: TerrainArt, name: String, xa: float, xb: float, y_top: float, h: float, cap_f: float, col: Color, edge_fade: float) -> void:
	if name == "" or xb - xa < 4.0:
		return
	var s := _skin.size_of(name)
	var sy := h / s.y
	var k := clampf(sy, 0.6, 1.4)
	var y_at := func(_x: float) -> float: return y_top
	var w := xb - xa
	if w <= s.x * k * 1.3:
		# 한 조각을 늘여 맞춘다
		art.piece(name, 0.0, s.x, xa, xb, y_at, sy, false, {"y_off": 0.0, "mod": col, "fade_l": edge_fade, "fade_r": edge_fade})
		return
	var cap_u := s.x * cap_f
	var segs: Array = art._plan(xa, xb, k, Vector2(0.0, s.x), s.x, cap_u, cap_u > 0.0, cap_u > 0.0, cap_u + 6.0, s.x - cap_u - 6.0, 220.0, 420.0, OVERLAP)
	for i in segs.size():
		var sg: Array = segs[i]
		var x0: float = sg[2]
		var x1: float = x0 + (sg[1] - sg[0]) * k
		var opts := {"y_off": 0.0, "mod": col}
		if i > 0:
			opts["fade_l"] = OVERLAP
		if i == 0 and edge_fade > 0.0:
			opts["fade_l"] = edge_fade
		if i == segs.size() - 1 and edge_fade > 0.0:
			opts["fade_r"] = edge_fade
		# 토막 높이는 몸통 그대로(sy), 가로는 k — 가운데 토막은 끝이 이웃과 겹쳐 서서히 섞인다
		art.piece(name, sg[0], sg[1], x0, minf(x1, xb + 2.0), y_at, sy, false, opts)


func _process(delta: float) -> void:
	_t += delta
	for i in _waves.size():
		var w: Node2D = _waves[i]
		var dir := 1.0 if i == 0 else -1.0
		w.position = Vector2(dir * SWAY * sin(_t * SWAY_SPEED * (1.0 + 0.3 * i)), 1.2 * sin(_t * 1.3 + i * 1.7))
	var inside: Array = _pool.get("_players_in") if "_players_in" in _pool else []
	if not inside.is_empty() or _rings.get_meta("had", false):
		_rings.set_meta("had", not inside.is_empty())
		_rings.queue_redraw()


## 소녀가 빠져 있으면 발 자리에 잔물결 고리 (SapPool 의 옛 연출과 같은 모양)
func _draw_rings() -> void:
	var inside: Array = _pool.get("_players_in") if "_players_in" in _pool else []
	for p in inside:
		if not is_instance_valid(p):
			continue
		var lp: Vector2 = to_local(p.global_position + Vector2(0, 60.0))
		var ring := fmod(_t * 1.6, 1.0)
		var ring2 := fmod(ring + 0.5, 1.0)
		var y := _surface + 2.0
		# 수면에 누운 고리 (납작한 타원)
		_rings.draw_set_transform(Vector2(lp.x, y), 0.0, Vector2(1.0, 0.3))
		_rings.draw_arc(Vector2.ZERO, 18.0 + ring * 40.0, 0.0, TAU, 28, Color(0.85, 1.0, 1.0, 0.45 * (1.0 - ring)), 3.0, true)
		_rings.draw_arc(Vector2.ZERO, 10.0 + ring2 * 40.0, 0.0, TAU, 28, Color(0.85, 1.0, 1.0, 0.32 * (1.0 - ring2)), 3.0, true)
	_rings.draw_set_transform(Vector2.ZERO)

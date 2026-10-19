extends StaticBody2D
class_name TerrainPolygon
## 지형 조각 (다각형). 경사나 울퉁불퉁한 가지 모양에 쓴다.
## 위를 향한 변에만 가는 빛 테두리를 그린다 (기획서 9장). 디테일은 발판(Platform)과 같은 표(TerrainStyle)를 쓴다:
## 위 변 안쪽으로 껍질 결·홈·옹이, 윗면 빛 띠, 이끼·잎·잔가지·지역 장식, 아래 변에는 이끼 수염·뿌리 가닥·돌.
## 아래 변이 '두꺼운지'(뿌리를 길게 늘어뜨릴지)는 그 변에서 위 변까지 실제 두께로 정한다.
## 그림은 발판처럼 세 겹(몸통 / 윗면 빛 / 장식)이다. 정화 연출 중에는 윗면 빛 겹만 다시 그린다.
## suspicious 를 켜면 발판(Platform)과 같은 '수상한' 단서: 창백한 이끼 + 위 변의 온기 빛 + 빛 가루.

@export var polygon := PackedVector2Array([Vector2(0, 0), Vector2(400, 0), Vector2(400, 100), Vector2(0, 100)])
@export var color := Color("070b14"):
	set(v):
		if v == color:
			return
		color = v
		queue_redraw()
		if _decor_layer:
			_decor_layer.queue_redraw()
@export var edge_color := Color("8fd3ff", 0.7):
	set(v):
		if v == edge_color:
			return
		edge_color = v
		if _edge_layer:
			_edge_layer.queue_redraw()
		else:
			queue_redraw()


## 기본값 그대로면 지역 팔레트(TerrainStyle)의 이끼 색을 쓴다.
@export var moss_color := Platform.DEFAULT_MOSS
@export var moss_light := Platform.DEFAULT_MOSS_LIGHT
## 지역 팔레트를 강제로 고른다 (비워 두면 조상 Room 의 region).
@export var style_region := ""
## 수상한 지형: 비밀로 이어지는 자리에 켠다. 글자 없이 빛과 창백한 이끼로만 알린다.
@export var suspicious := false:
	set(v):
		suspicious = v
		if is_inside_tree():
			_sync_suspicious()
		else:
			_redraw_all()

## 아래 변이 이보다 두꺼우면(그 변에서 위 변까지) 뿌리를 길게, 돌도 단다.
const THICK_MIN := 90.0

var _hint: Platform.SuspiciousHint
var _motes: CPUParticles2D
var _time := 0.0
var _style: Dictionary = {}
var _edge_layer: TerrainStyle.Layer
var _decor_layer: TerrainStyle.Layer
var _shapes: Array = []
var _covers := {}          # 변 번호 → 덮인 자리 표
var _cover_ready := false
var _glow_done := false


func _ready() -> void:
	var shape := CollisionPolygon2D.new()
	shape.polygon = polygon
	add_child(shape)
	material = preload("res://shaders/ash_purify.tres")
	_style = TerrainStyle.style_for(self, style_region)
	if moss_color == Platform.DEFAULT_MOSS:
		moss_color = _style["moss"]
	if moss_light == Platform.DEFAULT_MOSS_LIGHT:
		moss_light = _style["moss_light"]
	_edge_layer = TerrainStyle.Layer.new(self, TerrainStyle.LAYER_EDGE)
	_edge_layer.name = "EdgeLayer"
	add_child(_edge_layer)
	_decor_layer = TerrainStyle.Layer.new(self, TerrainStyle.LAYER_DECOR)
	_decor_layer.name = "DecorLayer"
	add_child(_decor_layer)
	_sync_suspicious()


func _redraw_all() -> void:
	queue_redraw()
	if _edge_layer:
		_edge_layer.queue_redraw()
	if _decor_layer:
		_decor_layer.queue_redraw()


## suspicious 값에 맞춰 단서 노드를 만들거나 지운다 (나중에 켜고 꺼도 바로 따라간다).
func _sync_suspicious() -> void:
	if suspicious:
		if _hint == null or _motes == null:
			_clear_suspicious()
			_make_suspicious_hint()
	else:
		_clear_suspicious()
	set_process(suspicious)
	_redraw_all()


func _clear_suspicious() -> void:
	if _hint:
		_hint.queue_free()
		_hint = null
	if _motes:
		_motes.queue_free()
		_motes = null


## 위를 향한 변: 시계 방향 다각형에서 왼쪽→오른쪽으로 가는 변.
func _top_edges() -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var edge := b - a
		if _is_top(edge):
			out.append(a)
			out.append(b)
	return out


static func _is_top(edge: Vector2) -> bool:
	return edge.x > 0.0 and absf(edge.y) < edge.x * 1.2


static func _is_bottom(edge: Vector2) -> bool:
	return edge.x < 0.0 and absf(edge.y) < -edge.x * 1.2


func _make_suspicious_hint() -> void:
	var tops := _top_edges()
	if tops.is_empty():
		return
	_hint = Platform.SuspiciousHint.new()
	_hint.setup(tops, Platform.HINT_HEIGHT, Platform.HINT_COLOR)
	add_child(_hint)
	# 빛 가루는 위 변들의 가운데에서, 가장 넓은 폭만큼
	var lo := INF
	var hi := -INF
	var ysum := 0.0
	for p in tops:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
		ysum += p.y
	var center := Vector2((lo + hi) * 0.5, ysum / tops.size() - 6.0)
	_motes = Platform._make_motes(center, Vector2((hi - lo) * 0.42, 3.0), Platform.HINT_COLOR)
	add_child(_motes)


func _process(delta: float) -> void:
	_time += delta
	if _hint:
		_hint.modulate.a = 0.775 + 0.225 * sin(_time * 1.4)


func _inside(p: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(p, polygon)


func _seed() -> int:
	return int(global_position.x * 7.0 + global_position.y * 13.0) + int(polygon[0].x * 3.0 + polygon[1].y * 5.0)


## 아래 변(a→b) 가운데에서 위로 올라가며 처음 만나는 다른 변까지의 거리 = 그 자리의 두께.
func _thickness_above(a: Vector2, b: Vector2) -> float:
	var mid := (a + b) * 0.5 + Vector2(0, -0.5)
	var far := mid + Vector2(0, -4000.0)
	var best := INF
	for i in polygon.size():
		var p := polygon[i]
		var q := polygon[(i + 1) % polygon.size()]
		var hit = Geometry2D.segment_intersects_segment(mid, far, p, q)
		if hit != null:
			var d: float = mid.y - (hit as Vector2).y
			if d > 0.5:
				best = minf(best, d)
	return best if best < INF else 0.0


## 옆 지형에 덮인 자리를 변마다 한 번 구한다 (위 변은 위쪽, 아래 변은 아래쪽).
func _ensure_cover() -> void:
	if _cover_ready:
		return
	_cover_ready = true
	var box := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		box = box.expand(p)
	_shapes = TerrainStyle.neighbor_shapes(self, box.grow_individual(20.0, 40.0, 20.0, 200.0))
	_covers.clear()
	if _shapes.is_empty():
		return
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var edge := b - a
		if _is_top(edge):
			var up := Vector2(edge.y, -edge.x).normalized()
			_covers[i] = TerrainStyle.cover_flags(_shapes, TerrainStyle.line_samples(a, b, up, 8.0))
		elif _is_bottom(edge):
			# 아래 변은 왼→오(b→a)로 장식하므로 같은 방향으로 표본을 만든다
			_covers[i] = TerrainStyle.cover_flags(_shapes, TerrainStyle.line_samples(b, a, Vector2(0, 1), 8.0))


## 몸통: 다각형 + 위 변 안쪽의 결·홈·옹이 + 채굴장 녹물·리벳 (양 끝이 다각형 안일 때만).
func _draw() -> void:
	if polygon.size() < 3:
		return
	var t0 := Time.get_ticks_usec()
	TerrainStyle.trace_node = self
	if _style.is_empty():
		_style = TerrainStyle.style_for(self, style_region)
	var st := _style
	var detailed := TerrainStyle.detail >= 1
	draw_colored_polygon(polygon, color)
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed() + 1
	var b := TerrainStyle.Batch.new()
	var lift: float = st["bark_lift"] if detailed else 0.12
	var streak := color.lightened(lift)
	if detailed:
		streak.a = float(st["bark_alpha"])
	for i in polygon.size():
		var a := polygon[i]
		var e := polygon[(i + 1) % polygon.size()]
		var edge := e - a
		var len := edge.length()
		if len < 2.0 or not _is_top(edge):
			continue
		var dir := edge / len
		var up := Vector2(dir.y, -dir.x)
		if not detailed:
			continue
		for k in TerrainStyle.n_of(len, 30.0, "streak"):
			var p := a.lerp(e, rng.randf()) - up * rng.randf_range(8.0, 46.0)
			var q := p + dir * rng.randf_range(20.0, 70.0) + up * rng.randf_range(-3, 3)
			if _inside(p) and _inside(q):
				TerrainStyle.draw_grain(self, p, q, streak, 2.4)
		for k in TerrainStyle.n_of(len, st["ridge_px"], "ridge"):
			var p := a.lerp(e, rng.randf()) - up * rng.randf_range(14.0, 50.0)
			var l := rng.randf_range(40.0, 100.0)
			var q := p + Vector2(l, 0)
			if _inside(p) and _inside(q + Vector2(0, 4)) and _inside(p.lerp(q, 0.5) + Vector2(0, 4)) and _inside(p.lerp(q, 0.5) + Vector2(0, -4)):
				TerrainStyle.draw_ridge(self, rng, p, l, color, st)
		for k in TerrainStyle.n_of(len, st["knot_px"], "knot"):
			var r := rng.randf_range(7.0, 11.0)
			var p := a.lerp(e, rng.randf_range(0.15, 0.85)) - up * rng.randf_range(26.0, 60.0)
			if _inside(p + Vector2(-r * 3.3, r * 0.3)) and _inside(p + Vector2(r * 3.3, r * 0.3)) and _inside(p + Vector2(0, r + 3.0)) and _inside(p + Vector2(0, -r - 5.0)) and _inside(p + Vector2(-r * 1.4, -r - 5.0)) and _inside(p + Vector2(r * 1.4, -r - 5.0)):
				TerrainStyle.draw_knot(b, self, rng, p, r, color, st)
		for k in TerrainStyle.n_of(len, st["rust_px"], "rust"):
			var p := a.lerp(e, rng.randf()) - up * rng.randf_range(3.0, 10.0)
			var l := rng.randf_range(14.0, 44.0)
			if _inside(p) and _inside(p + Vector2(0, l + 2.0)):
				TerrainStyle.draw_rust_line(self, rng, p, l, st)
		# 채굴장: 변을 따라 박힌 리벳 한 줄 (판 이음매처럼)
		for k in TerrainStyle.n_of(len, st["plate_px"], "plate"):
			var t := rng.randf_range(0.1, 0.7)
			var n := rng.randi_range(4, 7)
			for j in n:
				var p := a.lerp(e, t) + dir * (j * 15.0) - up * 9.0
				if _inside(p + Vector2(-3, -3)) and _inside(p + Vector2(3, 3)):
					TerrainStyle.draw_rivet(b, p, st)
		if st["sheen"]:
			TerrainStyle.draw_sheen(b, PackedVector2Array([a, a.lerp(e, 0.5), e]), st)
	b.flush(self)
	var dt := Time.get_ticks_usec() - t0
	Platform.draw_usec += dt
	Platform.body_usec += dt
	Platform.draw_calls += 1


## 겹 그리기 (TerrainStyle.Layer 가 부른다).
func _draw_layer(ci: CanvasItem, kind: int) -> void:
	if polygon.size() < 3:
		return
	var t0 := Time.get_ticks_usec()
	TerrainStyle.trace_node = self
	if kind == TerrainStyle.LAYER_EDGE:
		_draw_edge(ci)
		Platform.edge_calls += 1
	else:
		_draw_decor(ci)
	var dt := Time.get_ticks_usec() - t0
	Platform.draw_usec += dt
	if kind == TerrainStyle.LAYER_EDGE:
		Platform.edge_usec += dt
	else:
		Platform.decor_usec += dt
	Platform.layer_calls += 1


## 윗면 빛 겹: 위 변마다 빛 띠 + 테두리.
func _draw_edge(ci: CanvasItem) -> void:
	var b := TerrainStyle.Batch.new()
	var tops := _top_edges()
	if TerrainStyle.detail >= 1:
		var i := 0
		while i + 1 < tops.size():
			var a := tops[i]
			var e := tops[i + 1]
			var d := (e - a).normalized()
			TerrainStyle.draw_edge_glow(b, a, e, Vector2(d.y, -d.x), edge_color, float(_style["glow_depth"]))
			i += 2
	b.flush(ci)
	var j := 0
	while j + 1 < tops.size():
		ci.draw_line(tops[j] + Vector2(0, 1), tops[j + 1] + Vector2(0, 1), edge_color, 2.0, true)
		j += 2


## 장식 겹: 위 변의 이끼·잎·잔가지·지역 장식, 아래 변에 매달린 것 (두께에 따라 길이).
func _draw_decor(ci: CanvasItem) -> void:
	_ensure_cover()
	var st := _style
	var detailed := TerrainStyle.detail >= 1
	var mc := moss_color.lerp(Platform.PALE_MOSS, Platform.PALE_MIX) if suspicious else moss_color
	var ml := moss_light.lerp(Platform.PALE_MOSS_LIGHT, Platform.PALE_MIX) if suspicious else moss_light
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed() + 2
	var b := TerrainStyle.Batch.new()
	var spots: Array = []
	for i in polygon.size():
		var a := polygon[i]
		var e := polygon[(i + 1) % polygon.size()]
		var edge := e - a
		var len := edge.length()
		if len < 2.0:
			continue
		var cover: PackedByteArray = _covers.get(i, PackedByteArray())
		if _is_top(edge):
			TerrainStyle.draw_top_decor(b, ci, rng, st, a, e, mc, ml, detailed, cover, spots)
		elif detailed and _is_bottom(edge):
			var thick := _thickness_above(a, e) >= THICK_MIN
			TerrainStyle.draw_bottom_decor(b, ci, rng, st, PackedVector2Array([e, a]), len, thick, cover, mc)
	b.flush(ci)
	if not spots.is_empty() and not _glow_done:
		_glow_done = true
		call_deferred("_add_glow", spots, st)


func _add_glow(spots: Array, st: Dictionary) -> void:
	TerrainStyle.add_glow_light(self, spots, st)

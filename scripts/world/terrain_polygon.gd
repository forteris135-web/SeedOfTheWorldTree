extends StaticBody2D
class_name TerrainPolygon
## 임시 지형 조각 (다각형). 경사나 울퉁불퉁한 가지 모양에 쓴다.
## 위를 향한 변에만 가는 빛 테두리를 그린다 (기획서 9장).
## suspicious 를 켜면 발판(Platform)과 같은 '수상한' 단서: 창백한 이끼 + 위 변의 온기 빛 + 빛 가루.

@export var polygon := PackedVector2Array([Vector2(0, 0), Vector2(400, 0), Vector2(400, 100), Vector2(0, 100)])
@export var color := Color("070b14"):
	set(v):
		color = v
		queue_redraw()
@export var edge_color := Color("8fd3ff", 0.7):
	set(v):
		edge_color = v
		queue_redraw()


@export var moss_color := Color(0.42, 0.52, 0.24)
@export var moss_light := Color(0.72, 0.76, 0.36)
## 수상한 지형: 비밀로 이어지는 자리에 켠다. 글자 없이 빛과 창백한 이끼로만 알린다.
@export var suspicious := false:
	set(v):
		suspicious = v
		if is_inside_tree():
			_sync_suspicious()
		else:
			queue_redraw()

var _hint: Platform.SuspiciousHint
var _motes: CPUParticles2D
var _time := 0.0


func _ready() -> void:
	var shape := CollisionPolygon2D.new()
	shape.polygon = polygon
	add_child(shape)
	material = preload("res://shaders/ash_purify.tres")
	_sync_suspicious()


## suspicious 값에 맞춰 단서 노드를 만들거나 지운다 (나중에 켜고 꺼도 바로 따라간다).
func _sync_suspicious() -> void:
	if suspicious:
		if _hint == null or _motes == null:
			_clear_suspicious()
			_make_suspicious_hint()
	else:
		_clear_suspicious()
	set_process(suspicious)
	queue_redraw()


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
		if edge.x > 0.0 and absf(edge.y) < edge.x * 1.2:
			out.append(a)
			out.append(b)
	return out


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


func _draw() -> void:
	if polygon.size() < 3:
		return
	draw_colored_polygon(polygon, color)
	var mc := moss_color.lerp(Platform.PALE_MOSS, Platform.PALE_MIX) if suspicious else moss_color
	var ml := moss_light.lerp(Platform.PALE_MOSS_LIGHT, Platform.PALE_MIX) if suspicious else moss_light
	# 위를 향한 변: 시계 방향 다각형에서 왼쪽→오른쪽으로 가는 변
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var edge := b - a
		if edge.x > 0.0 and absf(edge.y) < edge.x * 1.2:
			draw_line(a + Vector2(0, 1), b + Vector2(0, 1), edge_color, 2.0, true)
			# 위를 향한 변에 이끼
			var rng := RandomNumberGenerator.new()
			rng.seed = int(a.x * 3.0 + b.y * 5.0)
			var len := edge.length()
			for k in int(len / 26.0):
				var t := rng.randf()
				var p := a.lerp(b, t)
				var r := rng.randf_range(4, 9)
				draw_circle(p + Vector2(0, -r * 0.3), r, mc.lerp(ml, rng.randf() * 0.5))

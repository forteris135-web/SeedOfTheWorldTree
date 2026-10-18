extends StaticBody2D
class_name Platform
## 지형 조각: 굽은 가지 모양의 어두운 실루엣 + 나무껍질 결 + 윗면 이끼·잎 + 늘어진 덩굴.
## (기획서 9장: 지형은 어두운 실루엣에 배경의 주된 색을 살짝 입히고, 윗면에 가는 빛 테두리)
## 원점은 왼쪽 위. 정화 전에는 공용 잿빛 재질로 바래 보인다.
## - label_text 는 개발용 메모다: 설정의 '개발 표시'(debug_hud)가 켜져 있을 때만 보인다.
## - suspicious 가 켜진 발판은 글자 없이 '수상한' 단서만 보인다(소울류처럼):
##   이끼가 조금 창백하고, 윗면에 희미한 온기 빛, 빛 가루가 천천히 떠오른다.

@export var size := Vector2(400, 40):
	set(v):
		size = v
		queue_redraw()
@export var color := Color("15150f"):
	set(v):
		color = v
		queue_redraw()
@export var edge_color := Color(1.0, 0.89, 0.62, 0.8):
	set(v):
		edge_color = v
		queue_redraw()
## 이끼·잎 색 (정화 후 기준. 정화 전엔 셰이더가 잿빛으로 만든다)
@export var moss_color := Color(0.42, 0.52, 0.24)
@export var moss_light := Color(0.72, 0.76, 0.36)
@export var vine_color := Color(0.13, 0.17, 0.1)
## 발판 위에 띄울 개발용 메모. 플레이 화면에는 안 보이고 '개발 표시'를 켜야 보인다.
@export var label_text := ""
## 장식을 그릴지 (벽·천장은 끈다)
@export var decorate := true
## 한쪽 방향 발판: 아래에서 뛰어오르면 통과해 위에 올라선다 (천장 틈의 비밀 발판처럼).
@export var one_way := false
## 수상한 발판: 비밀로 이어지는 자리에 켠다. 글자 대신 미묘한 빛과 창백한 이끼로만 알린다.
@export var suspicious := false:
	set(v):
		suspicious = v
		if is_inside_tree():
			_sync_suspicious()
		else:
			queue_redraw()
## 단서가 붙는 면. 비밀 발판은 '위', 비밀 천장(머리로 치는 곳)은 '아래', 비밀 벽은 '왼쪽'/'오른쪽'.
## 빛 띠와 빛 가루가 그 면의 바깥쪽으로 번진다. 창백한 이끼는 윗면에만 있다.
@export_enum("위", "아래", "왼쪽", "오른쪽") var suspicious_face := 0:
	set(v):
		suspicious_face = v
		if is_inside_tree() and suspicious:
			_clear_suspicious()
			_sync_suspicious()

## 수상한 단서의 색(따뜻한 온기)과 이끼가 창백해지는 정도.
const HINT_COLOR := Color(1.0, 0.84, 0.55)
const HINT_HEIGHT := 24.0
const PALE_MOSS := Color(0.78, 0.86, 0.72)
const PALE_MOSS_LIGHT := Color(0.96, 0.98, 0.86)
const PALE_MIX := 0.45

var _label: Label
var _hint: SuspiciousHint
var _motes: CPUParticles2D
var _time := 0.0


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size / 2.0
	if one_way:
		shape.one_way_collision = true
		shape.one_way_collision_margin = 24.0
	add_child(shape)
	if label_text != "":
		_label = Label.new()
		_label.text = label_text
		_label.add_theme_font_size_override("font_size", 22)
		_label.add_theme_color_override("font_color", Color("9aa3b8"))
		_label.position = Vector2(8, -34)
		_label.visible = false
		add_child(_label)
		# 개발 표시 설정을 따라간다 (메뉴에서 바꾸면 바로 반영)
		var settings := get_node_or_null("/root/Settings")
		if settings:
			settings.changed.connect(_apply_debug_label)
		_apply_debug_label()
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


## 개발 표시가 켜져 있을 때만 메모 글자를 보인다.
func _apply_debug_label() -> void:
	if _label == null:
		return
	var settings := get_node_or_null("/root/Settings")
	_label.visible = settings != null and bool(settings.get_value("debug_hud"))


## 고른 면의 변. 시계 방향(바깥 법선 = (dir.y, -dir.x))으로 만든다.
func _suspicious_edge() -> PackedVector2Array:
	var w := size.x
	var h := size.y
	match suspicious_face:
		1:   # 아래 (천장의 아랫면)
			return PackedVector2Array([Vector2(w, h), Vector2(0, h)])
		2:   # 왼쪽
			return PackedVector2Array([Vector2(0, h), Vector2(0, 0)])
		3:   # 오른쪽
			return PackedVector2Array([Vector2(w, 0), Vector2(w, h)])
		_:   # 위
			return PackedVector2Array([Vector2(0, 0), Vector2(w, 0)])


## 수상한 단서: 고른 면의 온기 빛(더하기 혼합) + 그 면 바깥으로 천천히 흐르는 빛 가루 몇 개.
func _make_suspicious_hint() -> void:
	var edge := _suspicious_edge()
	_hint = SuspiciousHint.new()
	_hint.setup(edge, HINT_HEIGHT, HINT_COLOR)
	add_child(_hint)
	var dir := edge[1] - edge[0]
	var normal := Vector2(dir.y, -dir.x).normalized()   # 면의 바깥쪽
	var len := dir.length()
	var mid := (edge[0] + edge[1]) * 0.5
	var extents := Vector2(len * 0.42, 3.0) if absf(dir.x) >= absf(dir.y) else Vector2(3.0, len * 0.42)
	_motes = _make_motes(mid + normal * 6.0, extents, HINT_COLOR, normal)
	add_child(_motes)


## 빛 가루 입자 (적게, 느리게). 다른 지형(경사)도 같은 모양을 쓴다.
## normal 은 가루가 흘러가는 방향(면의 바깥쪽). 기본은 위.
static func _make_motes(pos: Vector2, extents: Vector2, tint: Color, normal := Vector2(0, -1)) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 6
	p.lifetime = 4.5
	p.preprocess = 4.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = extents
	p.position = pos
	p.direction = normal
	p.spread = 18.0
	p.gravity = normal * 5.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 12.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.4
	p.color = Color(tint.r * 1.4, tint.g * 1.4, tint.b * 1.4, 0.6)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = add
	return p


## 수상한 빛은 아주 천천히 숨 쉬듯 밝아졌다 어두워진다 (0.55 ~ 1.0).
func _process(delta: float) -> void:
	_time += delta
	if _hint:
		_hint.modulate.a = 0.775 + 0.225 * sin(_time * 1.4)


## 이끼 색: 수상한 발판은 조금 창백하다.
func _moss() -> Color:
	return moss_color.lerp(PALE_MOSS, PALE_MIX) if suspicious else moss_color


func _moss_light() -> Color:
	return moss_light.lerp(PALE_MOSS_LIGHT, PALE_MIX) if suspicious else moss_light


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 7.0 + global_position.y * 13.0) + int(size.x)
	var w := size.x
	var h := size.y
	var thin := h <= 90.0 and w >= 120.0     # 가지 발판
	if thin:
		_draw_branch(rng, w, h)
	else:
		_draw_block(rng, w, h)


## 굽은 가지: 둥근 끝, 살짝 처진 아랫선, 껍질 결, 위에 이끼.
func _draw_branch(rng: RandomNumberGenerator, w: float, h: float) -> void:
	var mc := _moss()
	var ml := _moss_light()
	var pts := PackedVector2Array()
	var n := int(w / 40.0) + 2
	var sag := h * 0.9 + rng.randf_range(0, h * 0.6)
	# 윗선 (왼→오), 살짝 울퉁불퉁
	for i in n + 1:
		var t := float(i) / n
		var x := t * w
		var y := -absf(sin(t * PI * 3.1 + rng.randf() * 0.2)) * 2.0 + rng.randf_range(-1.5, 1.5)
		pts.append(Vector2(x, y))
	# 오른쪽 끝 둥글게
	for i in 4:
		var a := -PI / 2.0 + PI * float(i + 1) / 5.0
		pts.append(Vector2(w + cos(a) * h * 0.5, h * 0.5 + sin(a) * h * 0.5))
	# 아랫선 (오→왼), 가운데가 처진다
	for i in n + 1:
		var t := 1.0 - float(i) / n
		var x := t * w
		var y := h + sin(t * PI) * sag * 0.35 + rng.randf_range(-2.0, 2.0)
		pts.append(Vector2(x, y))
	for i in 4:
		var a := PI / 2.0 + PI * float(i + 1) / 5.0
		pts.append(Vector2(cos(a) * h * 0.5, h * 0.5 + sin(a) * h * 0.5))
	draw_colored_polygon(pts, color)
	# 껍질 결
	var streak := color.lightened(0.13)
	for i in int(w / 28.0):
		var x0 := rng.randf_range(0, w)
		var y0 := rng.randf_range(h * 0.25, h * 0.9)
		draw_line(Vector2(x0, y0), Vector2(x0 + rng.randf_range(16, 48), y0 + rng.randf_range(-3, 3)), streak, 1.5, true)
	# 윗면 빛 테두리
	draw_polyline(pts.slice(0, n + 1), edge_color, 2.0, true)
	# 이끼와 잎
	for i in int(w / 22.0):
		var x := rng.randf_range(6, w - 6)
		var r := rng.randf_range(4, 9)
		draw_circle(Vector2(x, -r * 0.3), r, mc.lerp(ml, rng.randf() * 0.5))
	for i in int(w / 60.0):
		var x := rng.randf_range(10, w - 10)
		var s := rng.randf_range(6, 11)
		var d := 1.0 if rng.randf() < 0.5 else -1.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, -2), Vector2(x + d * s, -s * 1.4), Vector2(x + d * s * 0.3, -s * 2.0)]), ml.darkened(rng.randf() * 0.3))
	# 늘어진 덩굴
	for i in int(w / 110.0) + 1:
		var x := rng.randf_range(20, w - 20)
		var len := rng.randf_range(30, 110)
		var sway := rng.randf_range(-10, 10)
		draw_line(Vector2(x, h), Vector2(x + sway, h + len), vine_color, 2.0, true)
		for j in 3:
			var tt := float(j + 1) / 4.0
			var p := Vector2(x + sway * tt, h + len * tt)
			draw_colored_polygon(PackedVector2Array([p, p + Vector2(-6, 8), p + Vector2(0, 16), p + Vector2(6, 8)]), vine_color.lightened(0.15))


## 큰 덩어리(바닥·벽): 채우고 윗선에 결과 이끼, 옆에 덩굴.
func _draw_block(rng: RandomNumberGenerator, w: float, h: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), color)
	if not decorate:
		return
	var mc := _moss()
	var ml := _moss_light()
	var streak := color.lightened(0.1)
	var band := minf(h, 140.0)
	for i in int(w * band / 2600.0) + 2:
		var x0 := rng.randf_range(0, w)
		var y0 := rng.randf_range(6, band)
		draw_line(Vector2(x0, y0), Vector2(x0 + rng.randf_range(30, 120), y0 + rng.randf_range(-4, 4)), streak, 1.5, true)
	draw_line(Vector2(0, 1), Vector2(w, 1), edge_color, 2.0, true)
	for i in int(w / 26.0):
		var x := rng.randf_range(4, w - 4)
		var r := rng.randf_range(4, 10)
		draw_circle(Vector2(x, -r * 0.3), r, mc.lerp(ml, rng.randf() * 0.5))
	for i in int(w / 70.0):
		var x := rng.randf_range(10, w - 10)
		var s := rng.randf_range(6, 12)
		var d := 1.0 if rng.randf() < 0.5 else -1.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, -2), Vector2(x + d * s, -s * 1.4), Vector2(x + d * s * 0.3, -s * 2.0)]), ml.darkened(rng.randf() * 0.3))
	# 옆면에 늘어진 덩굴 (벽 느낌)
	if h > 200.0:
		for side in [0.0, w]:
			for i in int(h / 160.0):
				var y := rng.randf_range(10, h - 60)
				var dir := 1.0 if side == 0.0 else -1.0
				var len := rng.randf_range(40, 120)
				draw_line(Vector2(side, y), Vector2(side + dir * rng.randf_range(4, 14), y + len), vine_color.lightened(0.1), 2.0, true)


## 수상한 자리의 온기 빛. 변(여러 개 가능)마다 변의 바깥쪽으로 서서히 사라지는 빛 띠를 그린다.
## 변은 시계 방향으로 준다: 바깥 법선 = (dir.y, -dir.x). (윗면은 왼→오, 아랫면은 오→왼.)
## 더하기 혼합이고 잿빛 셰이더를 거치지 않아, 잿빛 세상에서도 '살아 있는' 희미한 온기로 보인다.
## 자식 노드는 부모 그림 뒤에 그려지므로 이끼 위에 올라가되, 소녀(z 0)보다는 아래다.
class SuspiciousHint extends Node2D:
	var _edges: Array[PackedVector2Array] = []   # 각 변: [시작, 끝]
	var _height := 24.0
	var _tint := Color(1.0, 0.84, 0.55)

	## edges 는 (a, b, a, b, ...) 순서로 이어진 변 목록. 길이 2면 변 하나.
	func setup(points: PackedVector2Array, height: float, tint: Color) -> void:
		_edges.clear()
		var i := 0
		while i + 1 < points.size():
			_edges.append(PackedVector2Array([points[i], points[i + 1]]))
			i += 2
		_height = height
		_tint = tint
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = add
		queue_redraw()

	func _draw() -> void:
		for e in _edges:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var dir := b - a
			if dir.length() < 1.0:
				continue
			var up := Vector2(dir.y, -dir.x).normalized()   # 변의 바깥쪽 (시계 방향 기준)
			var mid := (a + b) * 0.5
			var lift := up * _height
			var strong := Color(_tint, 0.28)
			var faint := Color(_tint, 0.0)
			# 왼쪽 반: 끝은 투명, 가운데는 진하게. 바깥쪽 꼭짓점은 모두 투명 → 바깥으로 갈수록 사라진다.
			draw_polygon(PackedVector2Array([a + lift, mid + lift, mid + up * -2.0, a + up * -2.0]), PackedColorArray([faint, faint, strong, faint]))
			draw_polygon(PackedVector2Array([mid + lift, b + lift, b + up * -2.0, mid + up * -2.0]), PackedColorArray([faint, faint, faint, strong]))
			# 변을 따라 가는 빛줄: 가운데가 가장 밝다
			draw_line(a.lerp(b, 0.15) + up * 1.0, mid + up * 1.0, Color(_tint, 0.18), 1.5, true)
			draw_line(mid + up * 1.0, a.lerp(b, 0.85) + up * 1.0, Color(_tint, 0.18), 1.5, true)

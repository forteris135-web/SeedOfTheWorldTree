extends StaticBody2D
class_name Platform
## 지형 조각: 굽은 가지 모양의 어두운 실루엣 + 나무껍질 결 + 윗면 이끼·잎 + 늘어진 덩굴.
## (기획서 9장: 지형은 어두운 실루엣에 배경의 주된 색을 살짝 입히고, 윗면에 가는 빛 테두리)
## 원점은 왼쪽 위. 정화 전에는 공용 잿빛 재질로 바래 보인다.

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
## 발판 위에 띄울 설명 (연습장용).
@export var label_text := ""
## 장식을 그릴지 (벽·천장은 끈다)
@export var decorate := true
## 한쪽 방향 발판: 아래에서 뛰어오르면 통과해 위에 올라선다 (천장 틈의 비밀 발판처럼).
@export var one_way := false


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
		var label := Label.new()
		label.text = label_text
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color("9aa3b8"))
		label.position = Vector2(8, -34)
		add_child(label)
	material = preload("res://shaders/ash_purify.tres")
	queue_redraw()


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
		draw_circle(Vector2(x, -r * 0.3), r, moss_color.lerp(moss_light, rng.randf() * 0.5))
	for i in int(w / 60.0):
		var x := rng.randf_range(10, w - 10)
		var s := rng.randf_range(6, 11)
		var d := 1.0 if rng.randf() < 0.5 else -1.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, -2), Vector2(x + d * s, -s * 1.4), Vector2(x + d * s * 0.3, -s * 2.0)]), moss_light.darkened(rng.randf() * 0.3))
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
		draw_circle(Vector2(x, -r * 0.3), r, moss_color.lerp(moss_light, rng.randf() * 0.5))
	for i in int(w / 70.0):
		var x := rng.randf_range(10, w - 10)
		var s := rng.randf_range(6, 12)
		var d := 1.0 if rng.randf() < 0.5 else -1.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, -2), Vector2(x + d * s, -s * 1.4), Vector2(x + d * s * 0.3, -s * 2.0)]), moss_light.darkened(rng.randf() * 0.3))
	# 옆면에 늘어진 덩굴 (벽 느낌)
	if h > 200.0:
		for side in [0.0, w]:
			for i in int(h / 160.0):
				var y := rng.randf_range(10, h - 60)
				var dir := 1.0 if side == 0.0 else -1.0
				var len := rng.randf_range(40, 120)
				draw_line(Vector2(side, y), Vector2(side + dir * rng.randf_range(4, 14), y + len), vine_color.lightened(0.1), 2.0, true)

extends Node2D
## 시험 전용: 디테일 업그레이드 전(기준 커밋 3e7e6aa)의 지형 그리기 코드를 그대로 얼려 둔 사본.
## tools/probe_terrain 이 같은 방·같은 조건에서 '옛 그림'과 '새 그림'의 그리기 비용을 비교하는 데만 쓴다.
## 게임은 이 파일을 쓰지 않는다. (옛 platform.gd / terrain_polygon.gd / thorns.gd 의 _draw 를 옮긴 것)
## 쓰는 법: var s = preload("res://tools/terrain_legacy_draw.gd").new(); s.copy_from(진짜 지형 노드); 방에 add_child(s)

const ONE_WAY_DASH_LEN := 10.0
const ONE_WAY_DASH_GAP := 12.0
const ONE_WAY_DASH_ALPHA := 0.6
const ONE_WAY_DASH_WIDTH := 2.0

## 그린 시간(마이크로초)과 횟수 누적
static var draw_usec := 0
static var draw_calls := 0

var kind := 0          # 0 발판, 1 경사, 2 가시
var size := Vector2.ZERO
var polygon := PackedVector2Array()
var color := Color.BLACK
var edge_color := Color.WHITE
var moss_color := Color.GREEN
var moss_light := Color.GREEN
var vine_color := Color.DARK_GREEN
var tip_color := Color.WHITE
var decorate := true
var one_way := false
var seed_pos := Vector2.ZERO


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	match kind:
		0:
			draw_platform()
		1:
			draw_polygon_legacy()
		2:
			draw_thorns()
	draw_usec += Time.get_ticks_usec() - t0
	draw_calls += 1


## 진짜 지형 노드(Platform / TerrainPolygon / Thorns)를 흉내 낸다 (같은 자리·크기·색).
func copy_from(node: Node2D) -> void:
	seed_pos = node.global_position
	position = node.global_position
	if node is Platform:
		kind = 0
		size = node.size
		color = node.color
		edge_color = node.edge_color
		moss_color = node.moss_color
		moss_light = node.moss_light
		vine_color = node.vine_color
		decorate = node.decorate
		one_way = node.one_way
	elif node is TerrainPolygon:
		kind = 1
		polygon = node.polygon
		color = node.color
		edge_color = node.edge_color
		moss_color = node.moss_color
		moss_light = node.moss_light
	elif node is Thorns:
		kind = 2
		size = node.size
		color = node.color
		tip_color = node.tip_color


func draw_platform() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_pos.x * 7.0 + seed_pos.y * 13.0) + int(size.x)
	var w := size.x
	var h := size.y
	var thin := h <= 90.0 and w >= 120.0
	var sag := 0.0
	if thin:
		sag = _draw_branch(rng, w, h)
	else:
		_draw_block(rng, w, h)
	if one_way:
		var tint := Color(edge_color.r, edge_color.g, edge_color.b, ONE_WAY_DASH_ALPHA)
		var x := 6.0
		while x + ONE_WAY_DASH_LEN < w - 6.0:
			var t0 := x / w
			var t1 := (x + ONE_WAY_DASH_LEN) / w
			var y0 := h + 2.0 + sin(t0 * PI) * sag * 0.35
			var y1 := h + 2.0 + sin(t1 * PI) * sag * 0.35
			draw_line(Vector2(x, y0), Vector2(x + ONE_WAY_DASH_LEN, y1), tint, ONE_WAY_DASH_WIDTH, true)
			x += ONE_WAY_DASH_LEN + ONE_WAY_DASH_GAP


func _draw_branch(rng: RandomNumberGenerator, w: float, h: float) -> float:
	var mc := moss_color
	var ml := moss_light
	var pts := PackedVector2Array()
	var n := int(w / 40.0) + 2
	var sag := h * 0.9 + rng.randf_range(0, h * 0.6)
	for i in n + 1:
		var t := float(i) / n
		var x := t * w
		var y := -absf(sin(t * PI * 3.1 + rng.randf() * 0.2)) * 2.0 + rng.randf_range(-1.5, 1.5)
		pts.append(Vector2(x, y))
	for i in 4:
		var a := -PI / 2.0 + PI * float(i + 1) / 5.0
		pts.append(Vector2(w + cos(a) * h * 0.5, h * 0.5 + sin(a) * h * 0.5))
	for i in n + 1:
		var t := 1.0 - float(i) / n
		var x := t * w
		var y := h + sin(t * PI) * sag * 0.35 + rng.randf_range(-2.0, 2.0)
		pts.append(Vector2(x, y))
	for i in 4:
		var a := PI / 2.0 + PI * float(i + 1) / 5.0
		pts.append(Vector2(cos(a) * h * 0.5, h * 0.5 + sin(a) * h * 0.5))
	draw_colored_polygon(pts, color)
	var streak := color.lightened(0.13)
	for i in int(w / 28.0):
		var x0 := rng.randf_range(0, w)
		var y0 := rng.randf_range(h * 0.25, h * 0.9)
		draw_line(Vector2(x0, y0), Vector2(x0 + rng.randf_range(16, 48), y0 + rng.randf_range(-3, 3)), streak, 1.5, true)
	draw_polyline(pts.slice(0, n + 1), edge_color, 2.0, true)
	for i in int(w / 22.0):
		var x := rng.randf_range(6, w - 6)
		var r := rng.randf_range(4, 9)
		draw_circle(Vector2(x, -r * 0.3), r, mc.lerp(ml, rng.randf() * 0.5))
	for i in int(w / 60.0):
		var x := rng.randf_range(10, w - 10)
		var s := rng.randf_range(6, 11)
		var d := 1.0 if rng.randf() < 0.5 else -1.0
		draw_colored_polygon(PackedVector2Array([Vector2(x, -2), Vector2(x + d * s, -s * 1.4), Vector2(x + d * s * 0.3, -s * 2.0)]), ml.darkened(rng.randf() * 0.3))
	for i in int(w / 110.0) + 1:
		var x := rng.randf_range(20, w - 20)
		var len := rng.randf_range(30, 110)
		var sway := rng.randf_range(-10, 10)
		draw_line(Vector2(x, h), Vector2(x + sway, h + len), vine_color, 2.0, true)
		for j in 3:
			var tt := float(j + 1) / 4.0
			var p := Vector2(x + sway * tt, h + len * tt)
			draw_colored_polygon(PackedVector2Array([p, p + Vector2(-6, 8), p + Vector2(0, 16), p + Vector2(6, 8)]), vine_color.lightened(0.15))
	return sag


func _draw_block(rng: RandomNumberGenerator, w: float, h: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), color)
	if not decorate:
		return
	var mc := moss_color
	var ml := moss_light
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
	if h > 200.0:
		for side in [0.0, w]:
			for i in int(h / 160.0):
				var y := rng.randf_range(10, h - 60)
				var dir := 1.0 if side == 0.0 else -1.0
				var len := rng.randf_range(40, 120)
				draw_line(Vector2(side, y), Vector2(side + dir * rng.randf_range(4, 14), y + len), vine_color.lightened(0.1), 2.0, true)


func draw_polygon_legacy() -> void:
	if polygon.size() < 3:
		return
	draw_colored_polygon(polygon, color)
	var mc := moss_color
	var ml := moss_light
	for i in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		var edge := b - a
		if edge.x > 0.0 and absf(edge.y) < edge.x * 1.2:
			draw_line(a + Vector2(0, 1), b + Vector2(0, 1), edge_color, 2.0, true)
			var rng := RandomNumberGenerator.new()
			rng.seed = int(a.x * 3.0 + b.y * 5.0)
			var len := edge.length()
			for k in int(len / 26.0):
				var t := rng.randf()
				var p := a.lerp(b, t)
				var r := rng.randf_range(4, 9)
				draw_circle(p + Vector2(0, -r * 0.3), r, mc.lerp(ml, rng.randf() * 0.5))


func draw_thorns() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed_pos.x * 3.0 + seed_pos.y * 7.0)
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2(0, h * 0.55), Vector2(w, h * 0.45)), color)
	var x := 0.0
	while x < w - 10.0:
		var tw := rng.randf_range(14, 26)
		var th := rng.randf_range(h * 0.6, h * 1.05)
		var lean := rng.randf_range(-6, 6)
		var base_y := h * 0.6
		var tip := Vector2(x + tw / 2.0 + lean, base_y - th)
		draw_colored_polygon(PackedVector2Array([Vector2(x, base_y), tip, Vector2(x + tw, base_y)]), color)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-3, 10), tip + Vector2(3, 10)]), tip_color)
		x += tw * rng.randf_range(0.7, 1.1)

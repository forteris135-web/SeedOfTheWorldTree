extends StaticBody2D
class_name TerrainPolygon
## 임시 지형 조각 (다각형). 경사나 울퉁불퉁한 가지 모양에 쓴다.
## 위를 향한 변에만 가는 빛 테두리를 그린다 (기획서 9장).

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


func _ready() -> void:
	var shape := CollisionPolygon2D.new()
	shape.polygon = polygon
	add_child(shape)
	material = preload("res://shaders/ash_purify.tres")
	queue_redraw()


func _draw() -> void:
	if polygon.size() < 3:
		return
	draw_colored_polygon(polygon, color)
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
				draw_circle(p + Vector2(0, -r * 0.3), r, moss_color.lerp(moss_light, rng.randf() * 0.5))

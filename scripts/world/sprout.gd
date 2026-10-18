extends Node2D
## 정화되거나 쓰러진 적이 남기는 작은 묘목. 죽음이 아니라 나무로 돌아가 쉬는 것.

var _t := 0.0


func _process(delta: float) -> void:
	_t = minf(_t + delta * 0.8, 1.0)
	queue_redraw()


func _draw() -> void:
	var g := ease(_t, 0.4)
	draw_circle(Vector2(0, -10), 34.0 * g, Color("6fcf97", 0.08))
	draw_line(Vector2(0, 0), Vector2(0, -34 * g), Color("4fae7a"), 3.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -24 * g), Vector2(-18 * g, -36 * g), Vector2(-4 * g, -44 * g)]), Color("6fcf97"))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -30 * g), Vector2(16 * g, -44 * g), Vector2(4 * g, -48 * g)]), Color("6fcf97"))
	draw_circle(Vector2(0, -36 * g), 3.0 * g, Color("ffd46a"))

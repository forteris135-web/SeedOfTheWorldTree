extends StaticBody2D
class_name FogGate
## 보스 방의 안개 문. 싸움이 시작되면 닫혀 나갈 수 없고, 끝나면 걷힌다.

@export var size := Vector2(60, 700)
var closed := false
var _alpha := 0.0
var _t := 0.0
var _shape: CollisionShape2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_shape = CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	_shape.shape = r
	_shape.position = Vector2(0, -size.y / 2.0)
	_shape.disabled = true
	add_child(_shape)


func close() -> void:
	closed = true
	_shape.set_deferred("disabled", false)


func open() -> void:
	closed = false
	_shape.set_deferred("disabled", true)


func _process(delta: float) -> void:
	_t += delta
	_alpha = move_toward(_alpha, 1.0 if closed else 0.0, delta * 1.5)
	queue_redraw()


func _draw() -> void:
	if _alpha <= 0.01:
		return
	for i in 6:
		var w := size.x * (0.5 + i * 0.25)
		var sway := sin(_t * 1.3 + i) * 8.0
		draw_rect(Rect2(Vector2(-w / 2.0 + sway, -size.y), Vector2(w, size.y)), Color(0.75, 0.8, 0.9, 0.09 * _alpha))

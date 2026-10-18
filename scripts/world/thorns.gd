extends Area2D
class_name Thorns
## 나무 가시. 닿으면 피해를 입고 마지막 안전한 자리로 돌아온다. 원점은 왼쪽 위, 가시는 위를 향한다.

@export var size := Vector2(400, 60)
@export var damage := 15.0
@export var color := Color("1a1710")
@export var tip_color := Color(0.72, 0.66, 0.5)
## 가시가 향하는 방향 (0 위, 1 아래, 2 왼쪽, 3 오른쪽)
@export_enum("위", "아래", "왼쪽", "오른쪽") var facing_dir := 0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x - 8, size.y * 0.7)
	shape.shape = rect
	shape.position = Vector2(size.x / 2.0, size.y * 0.65)
	add_child(shape)
	body_entered.connect(_on_body_entered)
	material = preload("res://shaders/ash_purify.tres")
	queue_redraw()


func _physics_process(_delta: float) -> void:
	# 안에 머무는 동안도 (무적이 끝나면) 다시 찔린다
	for b in get_overlapping_bodies():
		if b is Player:
			b.take_hazard(damage)


func _on_body_entered(body: Node) -> void:
	if body is Player:
		body.take_hazard(damage)


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 3.0 + global_position.y * 7.0)
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

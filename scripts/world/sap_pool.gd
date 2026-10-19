extends Area2D
class_name SapPool
## 수액 웅덩이 (확장판 공용). 원점은 왼쪽 위, size 만큼의 수면.
## 수액 위 걷기(능력 "sap_walk")가 없으면: 안에서 느려지고 조금씩 체력이 깎인다 (즉사 아님).
## 능력이 있으면: 수면 위를 미끄러지듯 빠르게 지난다(slow_factor 1.35, 체력 안 깎임).
## 그림은 임시(파란 수액빛 사각형 + 일렁이는 윗선). 확장판 묶음이 다듬는다.

@export var size := Vector2(600, 120):
	set(v):
		size = v
		_rebuild()
		queue_redraw()
@export var dps := 5.0
@export var slow := 0.5
@export var glide := 1.35
@export var color := Color(0.25, 0.55, 0.75, 0.55)

var _shape: CollisionShape2D
var _t := 0.0
var _tick := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	_rebuild()
	material = preload("res://shaders/ash_purify_add.tres")


func _rebuild() -> void:
	if _shape == null:
		_shape = CollisionShape2D.new()
		add_child(_shape)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x, size.y * 0.8)
	_shape.shape = rect
	_shape.position = Vector2(size.x / 2.0, size.y * 0.6)


func can_walk() -> bool:
	return Progress.has_ability("sap_walk")


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _physics_process(delta: float) -> void:
	_tick -= delta
	for b in get_overlapping_bodies():
		if b is Player:
			if can_walk():
				b.slow_factor = glide
			else:
				b.slow_factor = slow
				if _tick <= 0.0:
					b.take_damage_over_time(dps * 0.5)
	if _tick <= 0.0:
		_tick = 0.5


func _draw() -> void:
	var walk := can_walk()
	var c := color if not walk else Color(color.r + 0.1, color.g + 0.15, color.b + 0.1, 0.75)
	draw_rect(Rect2(Vector2.ZERO, size), Color(c, c.a * 0.9))
	# 일렁이는 윗선
	var pts := PackedVector2Array()
	var x := 0.0
	while x <= size.x:
		pts.append(Vector2(x, 3.0 * sin(x * 0.03 + _t * 2.2) + 2.0 * sin(x * 0.011 - _t * 1.3)))
		x += 12.0
	draw_polyline(pts, Color(0.75, 0.95, 1.0, 0.85 if walk else 0.6), 3.0, true)

extends Area2D
class_name RootSpike
## 땅에서 솟는 뿌리 가시. 솟는 순간만 맞는다(가드 가능). 잠시 서 있다가 다시 들어간다.

var damage := 20.0
var _t := 0.0
var _h := 0.0
var _shape: CollisionShape2D
var _hit_done := false
var source: Node2D
const HEIGHT := 260.0


func _ready() -> void:
	add_to_group("projectile")
	collision_layer = 0
	collision_mask = 8
	_shape = CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(70, HEIGHT)
	_shape.shape = r
	_shape.position = Vector2(0, -HEIGHT / 2.0)
	add_child(_shape)
	material = preload("res://shaders/ash_purify.tres")


func launch(_dir: Vector2, src: Node2D, _player_owned: bool) -> void:
	source = src


func _physics_process(delta: float) -> void:
	_t += delta
	# 0~0.12초 솟음, 0.9초까지 서 있음, 1.3초까지 들어감
	if _t < 0.12:
		_h = ease(_t / 0.12, 0.4) * HEIGHT
	elif _t < 0.9:
		_h = HEIGHT
	else:
		_h = lerpf(HEIGHT, 0.0, (_t - 0.9) / 0.4)
	if _t > 1.3:
		queue_free()
		return
	if _t < 0.35 and not _hit_done:
		for area in get_overlapping_areas():
			if area is Hurtbox:
				var hit := HitData.make(damage, 0.0, source if source else self, Vector2(300, -420))
				hit.hitstop = 0.05
				var res: String = area.receive(hit)
				if res != "ignored":
					_hit_done = true
	queue_redraw()


func _draw() -> void:
	if _h <= 1.0:
		return
	var c := Color(0.42, 0.3, 0.5)
	var tip := Color(0.85, 0.75, 1.0)
	for i in 3:
		var ox := -24.0 + i * 24.0
		var hh := _h * (0.75 + 0.25 * (1 if i == 1 else 0))
		draw_colored_polygon(PackedVector2Array([Vector2(ox - 14, 0), Vector2(ox, -hh), Vector2(ox + 14, 0)]), c)
		draw_colored_polygon(PackedVector2Array([Vector2(ox - 4, -hh + 24), Vector2(ox, -hh), Vector2(ox + 4, -hh + 24)]), tip)
	draw_circle(Vector2(0, -_h * 0.5), 60.0, Color(0.7, 0.55, 1.0, 0.08))

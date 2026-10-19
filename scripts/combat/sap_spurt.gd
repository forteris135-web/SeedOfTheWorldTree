extends Area2D
class_name SapSpurt
## 바닥에서 솟는 뜨거운 수액 기둥 (무쇠 펌프 2페이즈: 사방에서 수액이 샌다). 뿌리 가시(root_spike.gd)와 같은 꼴.
## 예고(TELE 초: 바닥의 수액 고리가 부풀며 거품이 인다) → 솟음(UP) → 머무름(HOLD) → 가라앉음(DOWN). 솟는 순간만 맞는다(가드 가능).

var damage := 14.0
var source: Node2D
const TELE := 0.6
const UP := 0.12
const HOLD := 0.3
const DOWN := 0.35
const HEIGHT := 230.0
const HIT_WINDOW := 0.3

var _t := 0.0
var _h := 0.0
var _shape: CollisionShape2D
var _hit_done := false


func _ready() -> void:
	add_to_group("projectile")
	collision_layer = 0
	collision_mask = 8
	_shape = CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(80, HEIGHT)
	_shape.shape = r
	_shape.position = Vector2(0, -HEIGHT / 2.0)
	add_child(_shape)


func launch(_dir: Vector2, src: Node2D, _player_owned: bool) -> void:
	source = src


func is_telegraphing() -> bool:
	return _t < TELE


func _physics_process(delta: float) -> void:
	_t += delta
	var k := _t - TELE
	if k < 0.0:
		_h = 0.0
	elif k < UP:
		_h = ease(k / UP, 0.4) * HEIGHT
	elif k < UP + HOLD:
		_h = HEIGHT
	else:
		_h = lerpf(HEIGHT, 0.0, clampf((k - UP - HOLD) / DOWN, 0.0, 1.0))
	if k > UP + HOLD + DOWN:
		queue_free()
		return
	if k >= 0.0 and k < HIT_WINDOW and not _hit_done:
		for area in get_overlapping_areas():
			if area is Hurtbox:
				var hit := HitData.make(damage, 0.0, source if source else self, Vector2(260, -380))
				hit.hitstop = 0.04
				var res: String = area.receive(hit)
				if res != "ignored":
					_hit_done = true
	queue_redraw()


func _draw() -> void:
	var teal := Color(0.35, 0.8, 0.85)
	if _t < TELE:
		# 예고: 부풀어 오르는 수액 고리와 거품
		var p := _t / TELE
		var r := 20.0 + 40.0 * p
		draw_circle(Vector2(0, -4), r, Color(teal, 0.12 + 0.25 * p))
		draw_arc(Vector2(0, -4), r, 0.0, TAU, 24, Color(teal.lightened(0.3), 0.5 + 0.4 * p), 2.0 + 2.0 * p, true)
		for i in 5:
			var ang := float(i) * 1.26 + _t * 6.0
			var rr := r * 0.6
			var bubble := 3.0 + 4.0 * fmod(_t * 3.0 + i * 0.37, 1.0)
			draw_circle(Vector2(cos(ang) * rr, -4.0 - sin(ang) * rr * 0.3 - fmod(_t * 60.0 + i * 13.0, 30.0) * p), bubble, Color(0.75, 0.95, 1.0, 0.5))
		return
	if _h <= 1.0:
		return
	# 솟은 수액 기둥: 가운데 밝고 가장자리 어두운 띠 + 끝의 방울
	var w := 34.0 + 10.0 * sin(_t * 30.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-w, 0), Vector2(-w * 0.55, -_h), Vector2(w * 0.55, -_h), Vector2(w, 0)]), Color(0.2, 0.55, 0.62, 0.9))
	draw_colored_polygon(PackedVector2Array([Vector2(-w * 0.45, 0), Vector2(-w * 0.2, -_h * 0.95), Vector2(w * 0.2, -_h * 0.95), Vector2(w * 0.45, 0)]), Color(0.7, 0.95, 1.0, 0.85))
	for i in 4:
		var dy := -_h - 10.0 - i * 14.0 - fmod(_t * 160.0, 40.0)
		draw_circle(Vector2(-18.0 + i * 12.0, dy), 5.0 - i * 0.6, Color(0.75, 0.95, 1.0, 0.7))
	draw_circle(Vector2(0, -_h * 0.5), 70.0, Color(teal, 0.08))

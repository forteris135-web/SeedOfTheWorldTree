extends Area2D
class_name RootOrb
## 달빛 구슬 (뿌리지기 전용 투사체): 2배 크기(반지름 36)·꼬리·발광. 가드 가능.
## HOMING: 소녀를 천천히 쫓는다(지형에 막힘). ORBIT: 뿌리지기 둘레를 돌며 고리가 서서히 넓어진다('달빛 고리').
## 고리 구슬은 땅 아래로 내려간 동안 보이지 않고 맞지도 않는다 (타원 궤도의 아랫부분).

enum Mode { HOMING, ORBIT }

var mode := Mode.HOMING
var damage := 16.0
var speed := 380.0
var homing := 1.6
var lifetime := 4.5
var radius := 36.0
var source: Node2D
var direction := Vector2.LEFT
## ORBIT
var center: Node2D
var center_offset := Vector2(0, -200)
var orbit_r := 90.0
var orbit_grow := 280.0
var orbit_max := 760.0
var angle := 0.0
var angular_speed := 2.2
var ground_y := 0.0
var _t := 0.0
var _wobble := randf() * TAU
var _trail: Array[Vector2] = []
var _dead := false
var _below := false


func _ready() -> void:
	add_to_group("projectile")
	add_to_group("root_effect")
	collision_layer = 0
	collision_mask = 8
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius * 0.85
	shape.shape = c
	add_child(shape)


func launch(dir: Vector2, src: Node2D, _player_owned := false) -> void:
	direction = dir.normalized()
	source = src


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	match mode:
		Mode.HOMING:
			if homing > 0.0 and _t < lifetime * 0.7:
				var target := get_tree().get_first_node_in_group("player") as Node2D
				if target:
					var want := (target.global_position + Vector2(0, -50) - global_position).normalized()
					direction = direction.slerp(want, clampf(homing * delta, 0.0, 1.0)).normalized()
			var from := global_position
			var to := from + direction * speed * delta + Vector2(sin(_t * 3.0 + _wobble) * 50.0, 0) * delta
			var ray := PhysicsRayQueryParameters2D.create(from, to, 1)
			var hit_terrain := get_world_2d().direct_space_state.intersect_ray(ray)
			if not hit_terrain.is_empty():
				global_position = hit_terrain["position"]
				_vanish()
				return
			global_position = to
			if _t > lifetime:
				_vanish()
				return
		Mode.ORBIT:
			if center == null or not is_instance_valid(center):
				_vanish()
				return
			orbit_r = minf(orbit_r + orbit_grow * delta, orbit_max)
			angle += angular_speed * delta
			global_position = center.global_position + center_offset + Vector2(cos(angle) * orbit_r, sin(angle) * orbit_r * 0.5)
			_below = global_position.y > ground_y - 12.0
			visible = not _below
			if _t > lifetime or orbit_r >= orbit_max:
				_vanish()
				return
	_trail.push_front(global_position)
	if _trail.size() > 9:
		_trail.resize(9)
	if not _below:
		for area in get_overlapping_areas():
			if area is Hurtbox:
				var hit := HitData.make(damage, 0.0, source if source else self, Vector2(260, -100))
				hit.hitstop = 0.04
				var res: String = area.receive(hit)
				if res != "ignored":
					_vanish()
					return
	queue_redraw()


func _vanish() -> void:
	_dead = true
	set_deferred("monitoring", false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(queue_free)


func _draw() -> void:
	# 꼬리
	for i in _trail.size():
		var k := 1.0 - float(i) / _trail.size()
		draw_circle(to_local(_trail[i]), radius * (0.3 + 0.55 * k), Color(0.5, 0.75, 1.0, 0.22 * k))
	# 몸: 바깥 빛 → 속 → 흰 심 (HDR 밝기로 글로우)
	var pulse := 1.0 + 0.06 * sin(_t * 14.0 + _wobble)
	draw_circle(Vector2.ZERO, radius * 1.9 * pulse, Color(0.4, 0.6, 1.0, 0.14))
	draw_circle(Vector2.ZERO, radius * 1.25 * pulse, Color(0.55, 0.8, 1.0, 0.45))
	draw_circle(Vector2.ZERO, radius * 0.85, Color(1.3, 1.5, 1.9, 0.95))
	draw_circle(Vector2(-radius * 0.25, -radius * 0.25), radius * 0.3, Color(2.0, 2.0, 2.2, 0.9))

extends Area2D
class_name RootOrb
## 달빛 구슬 (뿌리지기 전용 투사체): 2배 크기(반지름 36)·꼬리·발광. 가드 가능.
## HOMING: 소녀를 천천히 쫓는다(지형에 막힘). ORBIT: 뿌리지기 둘레를 돌며 고리가 서서히 넓어진다('달빛 고리').
## 고리 구슬은 땅 아래로 내려간 동안 보이지 않고 맞지도 않는다 (타원 궤도의 아랫부분).
## 그림 (2026-10-19 이펙트 리뉴얼 F2): 기획자 이펙트 시트의 꼬리 달린 물방울(art/fx/bubble_trail)을 달빛 팔레트로 —
## 꼬리가 날아온 쪽을 향하게 움직이는 방향으로 돈다. 뒤에 옅은 달빛 발광. 판정 원(반지름 radius×0.85)은 그대로.

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
var _art: Sprite2D
var _last_pos := Vector2.INF
## 그림: 물방울 몸의 가운데(UV x)와 배율 (몸 지름 ≈ 판정 지름보다 조금 크게)
const ART := "bubble_trail"
const ART_HEAD_U := 0.79
const ART_SCALE_PER_R := 0.021


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
	_art = Sprite2D.new()
	_art.texture = Fx.texture(ART)
	_art.material = Fx.shared_material("moon", false, 0.4)
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _art.texture:
		_art.offset = Vector2(-(ART_HEAD_U - 0.5) * _art.texture.get_width(), 0.0)
	var k := radius * ART_SCALE_PER_R
	_art.scale = Vector2(k, k)
	_art.rotation = direction.angle()
	add_child(_art)


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
	# 그림은 실제로 움직인 방향을 향한다 (고리 구슬은 원을 따라 돈다)
	if _art and _last_pos != Vector2.INF:
		var mv := global_position - _last_pos
		if mv.length_squared() > 0.25:
			_art.rotation = lerp_angle(_art.rotation, mv.angle(), 0.5)
	_last_pos = global_position
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
	if _art and _art.texture:
		# 그림 뒤의 옅은 달빛 발광만 (몸·꼬리는 그림이 그린다)
		var pulse2 := 1.0 + 0.08 * sin(_t * 14.0 + _wobble)
		draw_circle(Vector2.ZERO, radius * 1.6 * pulse2, Color(0.45, 0.55, 1.0, 0.12))
		draw_circle(Vector2.ZERO, radius * 1.05 * pulse2, Color(0.6, 0.7, 1.0, 0.18))
		return
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

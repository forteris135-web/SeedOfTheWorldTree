extends Area2D
class_name SapWave
## 수액 물결 (수액의 여왕). 수면 위를 한 방향으로 밀려가는 물결. **점프로 넘긴다** (판정은 수면 위 HIT_H 만큼만).
## 가드는 된다 (소울류 원칙: 가드 불가는 붉은 예고뿐). 한 사람에게 한 번만 맞는다.
## 원점 = 수면 위 한 점 (y 가 수면). dir 로 launch 하면 그쪽으로 speed 로 간다. 방 끝(limit_x)에 닿으면 사라진다.
## 그림: 솟은 물마루(호) + 부서지는 거품 + 뒤로 끌리는 거품 자국 + 발광. 스킨 자리.

const HIT_H := 120.0     # 수면에서 이만큼 위까지 맞는다 (소녀 키 134 — 서 있으면 맞고, 점프하면 넘는다)
const HIT_W := 90.0
const CREST_H := 110.0   # 물마루 높이 (그림)

var speed := 540.0
var damage := 18.0
var lifetime := 5.0
var source: Node2D
var direction := 1.0
var limit_left := -INF
var limit_right := INF
var _t := 0.0
var _shape: CollisionShape2D
var _hit: Array = []
var _dead := false
var _spray: CPUParticles2D


func _ready() -> void:
	add_to_group("projectile")
	collision_layer = 0
	collision_mask = 8
	_shape = CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(HIT_W, HIT_H)
	_shape.shape = r
	_shape.position = Vector2(0, -HIT_H / 2.0)
	add_child(_shape)
	# 잿빛 재질은 붙이지 않는다: 점프로 넘겨야 하는 공격이라 잿빛 호수에서도 같은 싸움의 가루·나비처럼 청록으로 또렷해야 한다
	# (2026-10-19 검토: 잿빛 재질이면 옅은 회색 막으로만 보여 배경의 수면 줄무늬와 섞였다)
	_spray = CPUParticles2D.new()
	_spray.amount = 20
	_spray.lifetime = 0.5
	_spray.local_coords = false
	_spray.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_spray.emission_rect_extents = Vector2(30, 10)
	_spray.position = Vector2(0, -CREST_H * 0.8)
	_spray.direction = Vector2(0, -1)
	_spray.spread = 50.0
	_spray.gravity = Vector2(0, 700)
	_spray.initial_velocity_min = 120.0
	_spray.initial_velocity_max = 320.0
	_spray.scale_amount_min = 2.0
	_spray.scale_amount_max = 4.5
	_spray.color = Color(0.8, 1.0, 1.0, 0.8)
	add_child(_spray)
	Sfx.play("gust", -8.0, 0.1)


func launch(dir: Vector2, src: Node2D, _player_owned := false) -> void:
	direction = 1.0 if dir.x >= 0.0 else -1.0
	source = src


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	global_position.x += direction * speed * delta
	if _t > lifetime or global_position.x < limit_left or global_position.x > limit_right:
		_vanish()
		return
	for area in get_overlapping_areas():
		if area is Hurtbox and not _hit.has(area):
			_hit.append(area)
			var hit := HitData.make(damage, 0.0, source if source else self, Vector2(380, -300))
			hit.hitstop = 0.05
			area.receive(hit)
	queue_redraw()


func _vanish() -> void:
	_dead = true
	set_deferred("monitoring", false)
	_spray.emitting = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)


func _draw() -> void:
	var d := direction
	var wob := sin(_t * 18.0) * 6.0
	# 뒤로 끌리는 거품 자국
	for i in 6:
		var x := -d * (40.0 + i * 55.0)
		draw_circle(Vector2(x, -4.0 + sin(_t * 9.0 + i) * 3.0), 10.0 - i * 1.2, Color(0.8, 1.0, 1.0, 0.25 - i * 0.035))
	# 물마루: 앞으로 말리는 호 (여러 겹)
	var crest := PackedVector2Array()
	var n := 16
	for i in n + 1:
		var t := float(i) / n
		var ang := lerpf(PI, PI * 2.0, t)      # 뒤에서 앞으로 말린다 (수면선 y=0 아래로는 내려가지 않는다 — 다각형이 꼬이지 않게)
		var r := CREST_H * (0.55 + 0.45 * t)
		crest.append(Vector2(-d * 50.0 + d * cos(ang) * r * 0.9, minf(sin(ang) * r - 10.0 + wob * t, -4.0)))
	var poly := PackedVector2Array()
	poly.append(Vector2(-d * 150.0, 0))
	for p in crest:
		poly.append(p)
	poly.append(Vector2(d * 70.0, 0))
	draw_colored_polygon(poly, Color(0.3, 0.72, 0.88, 0.8))
	draw_polyline(crest, Color(0.2, 0.45, 0.55, 0.9), 8.0, true)     # 어두운 테두리 (밝은 배경에서도 윤곽이 보이게)
	draw_polyline(crest, Color(1.1, 1.3, 1.35, 1.0), 4.0, true)      # 밝은 물마루 (살짝 발광)
	# 안쪽 발광 띠
	var inner := PackedVector2Array()
	for p in crest:
		inner.append(p * 0.7 + Vector2(-d * 10.0, 0))
	draw_polyline(inner, Color(0.6, 0.95, 1.0, 0.5), 2.0, true)
	# 밑동 번짐
	draw_rect(Rect2(Vector2(-d * 160.0 if d > 0 else -80.0, -10), Vector2(240, 14)), Color(0.5, 0.9, 1.0, 0.3))

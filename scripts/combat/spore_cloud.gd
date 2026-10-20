extends Area2D
class_name SporeCloud
## 빛나는 포자 구름. 안의 소녀는 느려지고 조금씩 체력이 깎인다. 등불을 든 소녀가 들어오면 타서 걷힌다.
## 그림 (2026-10-19 이펙트 리뉴얼 F2): 기획자 이펙트 시트의 꽃잎 섞인 둥근 안개(art/fx/spore_ring)를 포자 팔레트(연두)로
## 네 겹 겹쳐 천천히 돌리고, 생길 때 빛나는 버섯 모양 포자가 피어오른다(Fx "spore_burst"). 등불에 타면 불꽃 고리(Fx "spore_burn").
## 판정(원 반지름 radius)은 그대로.

var radius := 150.0
var lifetime := 6.0
var dps := 6.0
var slow := 0.55
var _t := 0.0
var _alpha := 0.0
var _burning := false
var _particles: CPUParticles2D
var _shape: CollisionShape2D
var _tick := 0.0
var _puffs: Array[Sprite2D] = []
var _started := false
var _burn_fx := false
## 안개 겹: (자리 비율 x, y, 배율 비율, 도는 빠르기 rad/s, 투명도)
const PUFFS := [[0.0, 0.0, 1.0, 0.25, 0.5], [-0.35, 0.12, 0.7, -0.4, 0.42], [0.36, -0.1, 0.72, 0.35, 0.42], [0.05, -0.32, 0.6, -0.3, 0.38]]
const ART := "spore_ring"
## 안개 그림의 둥근 테 (fx 셰이더 round_on): 가운데에서 이 비율(UV)부터 지워 끝에서 0 — spore_ring 그림은 가장자리가 잘려 있어
## 크게 키워 돌리면 어두운 방에서 곧은 사선(마름모)이 보였다 (2026-10-20 검수)
const ROUND_R0 := 0.26
const ROUND_R1 := 0.5
## 둥근 테로 바깥이 지워진 만큼 안개 그림을 키운다 (보이는 구름 크기가 판정 원과 비슷하게)
const ROUND_GROW := 1.2
static var _round_mat: ShaderMaterial


func _ready() -> void:
	add_to_group("projectile")
	collision_layer = 0
	collision_mask = 2
	_shape = CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = radius
	_shape.shape = c
	add_child(_shape)
	_particles = CPUParticles2D.new()
	_particles.amount = 40
	_particles.lifetime = 2.5
	_particles.preprocess = 1.0
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = radius * 0.8
	_particles.gravity = Vector2(0, -8)
	_particles.initial_velocity_min = 5.0
	_particles.initial_velocity_max = 20.0
	_particles.scale_amount_min = 2.0
	_particles.scale_amount_max = 5.0
	_particles.color = Color(0.75, 1.0, 0.6, 0.6)
	add_child(_particles)
	var tex := Fx.texture(ART)
	if tex:
		if _round_mat == null:
			_round_mat = Fx.make_material("spore", false, 0.3)
			_round_mat.set_shader_parameter(&"round_on", true)
			_round_mat.set_shader_parameter(&"round_r0", ROUND_R0)
			_round_mat.set_shader_parameter(&"round_r1", ROUND_R1)
		var mat := _round_mat
		for pf in PUFFS:
			var sp := Sprite2D.new()
			sp.texture = tex
			sp.material = mat
			sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			sp.position = Vector2(pf[0], pf[1]) * radius
			var k: float = radius * 2.0 / tex.get_width() * float(pf[2]) * ROUND_GROW
			sp.scale = Vector2(k, k)
			sp.rotation = randf() * TAU
			sp.modulate = Color(1, 1, 1, 0.0)
			add_child(sp)
			_puffs.append(sp)
		# 입자는 포자 안개 앞에
		move_child(_particles, get_child_count() - 1)
	else:
		material = preload("res://shaders/ash_purify_add.tres")


func _process(delta: float) -> void:
	_t += delta
	if not _started:
		_started = true
		Fx.spawn("spore_burst", global_position + Vector2(0, radius * 0.4), {"scale": radius / 150.0})
	if _burning and not _burn_fx and _t <= lifetime:
		_burn_fx = true
		Fx.spawn("spore_burn", global_position, {"scale": radius / 150.0})
	var pulse := 0.92 + 0.08 * sin(_t * 2.0)
	for i in _puffs.size():
		var sp := _puffs[i]
		var pf: Array = PUFFS[i]
		sp.rotation += float(pf[3]) * delta
		sp.modulate = Color(1, 1, 1, float(pf[4]) * _alpha)
		var k: float = radius * 2.0 / sp.texture.get_width() * float(pf[2]) * pulse * ROUND_GROW
		sp.scale = Vector2(k, k)
	if _burning:
		_alpha = move_toward(_alpha, 0.0, delta * 2.5)
		_particles.emitting = false
		if _alpha <= 0.01:
			queue_free()
	else:
		_alpha = move_toward(_alpha, 1.0, delta * 2.0)
		if _t > lifetime:
			_burning = true
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _burning:
		return
	for b in get_overlapping_bodies():
		if b is Player:
			if Progress.has_ability("lantern"):
				_burning = true
				Juice.rumble(0.1, 0.2, 0.1)
				return
			b.slow_factor = slow
			_tick += delta
			if _tick >= 0.5:
				_tick = 0.0
				b.take_damage_over_time(dps * 0.5)


func _draw() -> void:
	if not _puffs.is_empty():
		return   # 안개 그림(Sprite2D)이 그린다
	var pulse := 0.85 + 0.15 * sin(_t * 2.0)
	draw_circle(Vector2.ZERO, radius * pulse, Color(0.6, 1.0, 0.5, 0.06 * _alpha))
	draw_circle(Vector2.ZERO, radius * 0.6 * pulse, Color(0.7, 1.0, 0.6, 0.08 * _alpha))
	if _burning:
		draw_circle(Vector2.ZERO, radius * (1.0 - _alpha) * 1.2, Color(1.0, 0.7, 0.4, 0.25 * _alpha))

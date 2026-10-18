extends Area2D
class_name SporeCloud
## 빛나는 포자 구름. 안의 소녀는 느려지고 조금씩 체력이 깎인다. 등불을 든 소녀가 들어오면 타서 걷힌다.

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
	material = preload("res://shaders/ash_purify_add.tres")


func _process(delta: float) -> void:
	_t += delta
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
	var pulse := 0.85 + 0.15 * sin(_t * 2.0)
	draw_circle(Vector2.ZERO, radius * pulse, Color(0.6, 1.0, 0.5, 0.06 * _alpha))
	draw_circle(Vector2.ZERO, radius * 0.6 * pulse, Color(0.7, 1.0, 0.6, 0.08 * _alpha))
	if _burning:
		draw_circle(Vector2.ZERO, radius * (1.0 - _alpha) * 1.2, Color(1.0, 0.7, 0.4, 0.25 * _alpha))

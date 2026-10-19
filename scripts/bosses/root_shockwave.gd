extends Area2D
class_name RootShockwave
## 지팡이 내려찍기 충격파 (뿌리지기 2페이즈): 바닥을 달리는 흙 두둑. 가드 불가(붉은 예고) — 점프로 넘는다(높이 90 < 점프 260).
## 아레나 끝(min_x~max_x)에 닿으면 흩어진다.
## 그림 (2026-10-19 이펙트 리뉴얼 F2): 기획자 이펙트 시트의 흙과 뿌리 가시 덩어리(art/fx/root_burst)를 붉게(가드 불가) 칠해
## 바닥을 따라 달리게 하고, 뒤로 흙먼지를 흘린다. 판정 사각형은 그대로.

var damage := 20.0
var speed := 760.0
var dir := 1
var min_x := -INF
var max_x := INF
var source: Node2D
var lifetime := 2.6
var _t := 0.0
var _dead := false
var _targets: Array = []
var _dirt: CPUParticles2D
var _art: Sprite2D
var _puff_t := 0.0
const H := 90.0
const W := 120.0
const ART := "root_burst"
const ART_SCALE := 0.72


func _ready() -> void:
	add_to_group("projectile")
	add_to_group("root_effect")
	collision_layer = 0
	collision_mask = 8
	var shape := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(70, H - 14)
	shape.shape = r
	shape.position = Vector2(0, -H / 2.0 + 6)
	add_child(shape)
	_dirt = CPUParticles2D.new()
	_dirt.amount = 24
	_dirt.lifetime = 0.5
	_dirt.direction = Vector2(-dir, -1)
	_dirt.spread = 40.0
	_dirt.gravity = Vector2(0, 900)
	_dirt.initial_velocity_min = 120.0
	_dirt.initial_velocity_max = 320.0
	_dirt.scale_amount_min = 2.0
	_dirt.scale_amount_max = 6.0
	_dirt.color = Color(0.36, 0.28, 0.3, 0.85)
	_dirt.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dirt.emission_rect_extents = Vector2(W * 0.4, 3)
	add_child(_dirt)
	_art = Sprite2D.new()
	_art.texture = Fx.texture(ART)
	_art.material = Fx.shared_material("danger", false, 0.5)
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.centered = false
	_art.visible = false
	add_child(_art)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_t += delta
	global_position.x += dir * speed * delta
	if global_position.x < min_x or global_position.x > max_x or _t > lifetime:
		_vanish()
		return
	_update_art(delta)
	for area in get_overlapping_areas():
		if area is Hurtbox and not _targets.has(area):
			_targets.append(area)
			var hit := HitData.make(damage, 0.0, source if source else self, Vector2(420, -380))
			hit.guardable = false
			hit.hitstop = 0.05
			area.receive(hit)
	queue_redraw()


## 그림: 처음 0.12초에 땅에서 솟고, 달리며 살짝 들썩인다. 뒤로 흙먼지.
func _update_art(delta: float) -> void:
	if _art == null or _art.texture == null:
		return
	var k := clampf(_t / 0.12, 0.0, 1.0)
	_art.visible = k > 0.02
	var ts := _art.texture.get_size()
	var bob := 1.0 + 0.08 * sin(_t * 26.0)
	_art.scale = Vector2(ART_SCALE * float(dir), ART_SCALE * k * bob)
	_art.position = Vector2(-ts.x * ART_SCALE * 0.5 * float(dir), -ts.y * ART_SCALE * k * bob + 10.0)
	_puff_t -= delta
	if _puff_t <= 0.0:
		_puff_t = 0.09
		Fx.spawn("dust_puff", global_position + Vector2(-dir * 50.0, -10.0), {"vel": Vector2(-dir * 120.0, -50.0)})


func _vanish() -> void:
	_dead = true
	set_deferred("monitoring", false)
	_dirt.emitting = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(queue_free)


func _draw() -> void:
	if _art and _art.texture:
		return   # 그림(Sprite2D)이 그린다
	var k := clampf(_t / 0.12, 0.0, 1.0)   # 처음 0.12초에 솟는다
	var h := H * k
	if h < 2.0:
		return
	# 두둑: 앞쪽이 가파르고 뒤가 완만한 흙더미
	var pts := PackedVector2Array()
	var n := 14
	for i in n + 1:
		var u := float(i) / n
		var x := lerpf(-W * 0.5, W * 0.5, u) * dir
		var profile := sin(u * PI)
		profile = pow(profile, 0.7 if u > 0.5 else 1.4)
		pts.append(Vector2(x, -h * profile))
	pts.append(Vector2(W * 0.5 * dir, 4))
	pts.append(Vector2(-W * 0.5 * dir, 4))
	draw_colored_polygon(pts, Color(0.3, 0.22, 0.26))
	# 갈라진 금 (붉은 빛 = 가드 불가)
	var red := Color(1.0, 0.25, 0.15, 0.55 + 0.3 * sin(_t * 30.0))
	draw_polyline(pts.slice(0, n + 1), Color(0.5, 0.36, 0.42), 2.5, true)
	for i in 4:
		var u := 0.3 + 0.13 * i
		var x := lerpf(-W * 0.5, W * 0.5, u) * dir
		draw_line(Vector2(x, 0), Vector2(x + 8 * dir, -h * sin(u * PI) * 0.8), red, 2.0)
	draw_circle(Vector2(W * 0.15 * dir, -h * 0.45), 34.0, Color(1.0, 0.2, 0.1, 0.12))
	# 흙덩이
	for i in 5:
		var x := (-W * 0.5 + W * (i + 0.5) / 5.0) * dir
		draw_circle(Vector2(x, -h * sin((i + 0.5) / 5.0 * PI) * 0.5), 8.0 + 3.0 * (i % 2), Color(0.42, 0.3, 0.32))

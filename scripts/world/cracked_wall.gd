extends Platform
class_name CrackedWall
## 금 간 벽 (확장판). 주변 지형과 같은 나무 벽이지만 큰 금이 가 있고 그 틈으로 빛이 샌다 (EXPANSION.md 2장).
## - 능력 '벽 부수기'(wall_break) 가 **없으면**: 때려도 금만 조금 더 갈라지고 붉은 빛이 번쩍이며 먼지가 떨어진다
##   ("아직 열 수 없다"는 느낌만, 글자 없음). 공격은 튕긴다("blocked" → 소녀가 살짝 밀린다).
## - 능력이 **있으면**: 무거운 공격(씨앗 베기·낙하 공격, 흐트러짐 45 이상) 한 대, 또는 약공격 3대로 부서진다.
## 부서진 것은 Progress.collected[secret_id] 에 남아 다시 와도 부서져 있다. 뒤에는 보통 숨겨진 방으로 가는 포탈이 있다.
## 그림: art/objects/object_cracked_wall.png 를 벽 크기에 맞춰 늘려 덮는다 (임시 그림; 진짜 그림으로 같은 이름 덮어쓰기).
## Platform 을 상속하므로 Terrain 아래에 두면 정화 색·잿빛 재질을 그대로 받는다. 적의 공격은 무시한다.

signal broken

## 고유 이름: cracked_<방>_<번호>
@export var secret_id := ""
## 부수는 데 필요한 '무거운 공격' 수. 약공격은 한 대가 LIGHT_WEIGHT 만큼만 센다.
@export var hits_to_break := 1.0

const TEX := preload("res://art/objects/object_cracked_wall.png")
## 이 흐트러짐 이상이면 무거운 공격 (씨앗 베기 60, 낙하 공격 45; 약공격 20/20/32, 바람 24, 빛 30)
const HEAVY_POISE := 45.0
const LIGHT_WEIGHT := 0.34
const LOCKED_GLOW := Color(1.0, 0.35, 0.2)
const OPEN_GLOW := Color(1.0, 0.82, 0.45)

var _damage := 0.0
var _broken := false
var _t := 0.0
var _shake := 0.0
var _deny := 0.0
var _redraw_t := 0.0
var _rng_seed := 0
var _sprite: Sprite2D
var _base: Polygon2D
var _dust: CPUParticles2D
var _hurtbox: Hurtbox
## 틈으로 새는 빛 (잿빛 재질을 받지 않는 더하기 혼합 층 — 정화 전 잿빛 지역에서도 빛은 색을 띤다)
var _glow: Node2D
var _leak: CPUParticles2D


func _ready() -> void:
	super()   # 충돌 모양 + 잿빛 재질
	set_process(true)   # Platform 은 '수상한 지형'이 아니면 _process 를 끈다 — 금 간 벽은 늘 숨 쉬고 흔들려야 한다
	add_to_group("cracked_wall")
	_rng_seed = int(global_position.x * 5.0 + global_position.y * 11.0) + int(size.x) + 31
	# 소녀 Hitbox(mask 16) 가 때릴 수 있는 '맞는 영역'. 직속 자식이어야 receive_hit 이 불린다.
	_hurtbox = Hurtbox.new()
	_hurtbox.collision_layer = 16
	_hurtbox.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size / 2.0
	_hurtbox.add_child(shape)
	add_child(_hurtbox)
	# 바탕 (그림 가장자리 밖도 벽으로 보이게) — 부모의 _draw(틈의 빛)보다 뒤에 그린다
	_base = Polygon2D.new()
	_base.polygon = PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
	_base.color = color
	_base.show_behind_parent = true
	_base.use_parent_material = true
	add_child(_base)
	# 금 간 벽 그림 (벽 크기에 맞춰 늘린다; 부모의 잿빛 재질을 따른다). 틈의 빛은 부모가 그 위에 그린다.
	_sprite = Sprite2D.new()
	_sprite.texture = TEX
	_sprite.centered = false
	_sprite.scale = size / TEX.get_size()
	_sprite.use_parent_material = true
	_sprite.show_behind_parent = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)
	# 가끔 떨어지는 먼지
	_dust = CPUParticles2D.new()
	_dust.amount = 3
	_dust.lifetime = 1.6
	_dust.preprocess = 1.0
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.emission_rect_extents = Vector2(size.x * 0.35, 3.0)
	_dust.position = Vector2(size.x / 2.0, 12.0)
	_dust.direction = Vector2(0, 1)
	_dust.spread = 12.0
	_dust.gravity = Vector2(0, 140)
	_dust.initial_velocity_min = 5.0
	_dust.initial_velocity_max = 20.0
	_dust.scale_amount_min = 1.2
	_dust.scale_amount_max = 2.6
	_dust.color = Color(color.lightened(0.45), 0.55)
	add_child(_dust)
	# 틈의 빛 층: 부모(잿빛 재질) 위에 더하기 혼합으로 그린다
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow = Node2D.new()
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	# 틈에서 새어 나오는 작은 빛 가루
	_leak = CPUParticles2D.new()
	_leak.amount = 5
	_leak.lifetime = 2.2
	_leak.preprocess = 2.0
	_leak.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_leak.emission_rect_extents = Vector2(6.0, size.y * 0.42)
	_leak.position = Vector2(size.x * 0.5, size.y * 0.5)
	_leak.direction = Vector2(0, -1)
	_leak.spread = 70.0
	_leak.gravity = Vector2(0, -10)
	_leak.initial_velocity_min = 6.0
	_leak.initial_velocity_max = 18.0
	_leak.scale_amount_min = 1.2
	_leak.scale_amount_max = 2.6
	_leak.material = add
	add_child(_leak)
	_update_glow_color()
	if secret_id != "" and Progress.is_collected(secret_id):
		_set_broken_quietly()


func is_broken() -> bool:
	return _broken


func can_break() -> bool:
	return Progress.has_ability("wall_break")


func _process(delta: float) -> void:
	if _broken:
		return
	_t += delta
	_shake = maxf(_shake - delta * 4.0, 0.0)
	_deny = maxf(_deny - delta * 2.2, 0.0)
	_redraw_t += delta
	if _sprite:
		_sprite.position = Vector2(sin(_t * 90.0) * 3.0 * _shake, cos(_t * 70.0) * 1.5 * _shake)
		# 능력이 없으면 붉게, 있으면 따뜻하게 숨 쉬는 틈의 빛. 맞아서 튕기면 붉게 번쩍.
		var glow := LOCKED_GLOW if not can_break() else OPEN_GLOW
		var pulse := 0.5 + 0.5 * sin(_t * 1.6 + float(_rng_seed % 7))
		var tint := Color(1, 1, 1, 1).lerp(glow, 0.12 + 0.1 * pulse + 0.3 * _damage)
		_sprite.modulate = tint.lerp(Color(2.2, 0.5, 0.35, 1.0), _deny)
	_glow.position = _sprite.position if _sprite else Vector2.ZERO
	_glow.queue_redraw()
	if _redraw_t >= 0.1 or _shake > 0.0 or _deny > 0.0:
		_redraw_t = 0.0
		_dust.color = Color(color.lightened(0.45), 0.55)
		_update_glow_color()
		if _base:
			_base.color = color   # Room 이 지형색을 입히는 건 _ready 뒤라 여기서 맞춘다
			_base.position = _sprite.position
		queue_redraw()


func _update_glow_color() -> void:
	if _leak:
		var g := LOCKED_GLOW if not can_break() else OPEN_GLOW
		_leak.color = Color(g.r * 1.4, g.g * 1.4, g.b * 1.4, 0.55 if can_break() else 0.35)


## 소녀의 공격이 닿았다 (Hurtbox 가 부른다). 적의 공격은 무시.
func receive_hit(hit: HitData, _hurtbox: Hurtbox) -> String:
	if _broken or not hit.from_player:
		return "ignored"
	_shake = 1.0
	_dust.restart()
	if not can_break():
		# 아직 열 수 없다: 붉은 번쩍임 + 먼지, 공격은 튕긴다
		_deny = 1.0
		_dust.amount = 8
		Sfx.play("guard", -8.0, 0.1)
		Juice.rumble(0.1, 0.25, 0.06)
		queue_redraw()
		return "blocked"
	var weight := 1.0 if hit.poise >= HEAVY_POISE else LIGHT_WEIGHT
	_damage = minf(_damage + weight / maxf(hits_to_break, 0.01), 1.0)
	_dust.amount = 3 + int(_damage * 10.0)
	Sfx.play("broke", -12.0, 0.12)
	queue_redraw()
	if _damage >= 0.999:
		_break()
	return "hit"


## 부서진다: 조각이 튀고, 충돌이 꺼지고, 그림이 사라진다.
func _break() -> void:
	if _broken:
		return
	_broken = true
	_disable_collision()
	_spawn_debris()
	Juice.shake(6.0)
	Juice.rumble(0.4, 0.7, 0.18)
	Juice.hitstop(0.06, 0.05)
	Sfx.play("broke", 0.0, 0.08)
	Sfx.play("heavy_hit", -4.0, 0.05)
	_dust.emitting = false
	_leak.emitting = false
	_glow.visible = false
	if _sprite:
		var tw := create_tween()
		tw.tween_property(_sprite, "modulate:a", 0.0, 0.25)
		tw.parallel().tween_property(_base, "modulate:a", 0.0, 0.25)
	queue_redraw()
	if secret_id != "":
		Progress.collect(secret_id)
	broken.emit()


## 다시 들어왔을 때: 이미 부서진 모습으로 시작 (연출 없음).
func _set_broken_quietly() -> void:
	_broken = true
	_disable_collision()
	_dust.emitting = false
	visible = false
	set_process(false)


func _disable_collision() -> void:
	set_deferred("collision_layer", 0)
	for c in get_children():
		if c is CollisionShape2D:
			c.set_deferred("disabled", true)
	if _hurtbox:
		_hurtbox.set_deferred("monitorable", false)
		for c in _hurtbox.get_children():
			if c is CollisionShape2D:
				c.set_deferred("disabled", true)


func _spawn_debris() -> void:
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 30
	burst.lifetime = 1.1
	burst.position = size / 2.0
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	burst.emission_rect_extents = size * 0.45
	burst.direction = Vector2(0, -1)
	burst.spread = 180.0
	burst.gravity = Vector2(0, 980)
	burst.initial_velocity_min = 140.0
	burst.initial_velocity_max = 460.0
	burst.angular_velocity_min = -360.0
	burst.angular_velocity_max = 360.0
	burst.scale_amount_min = 3.0
	burst.scale_amount_max = 9.0
	burst.color = color.lightened(0.28)
	burst.emitting = true
	add_child(burst)
	get_tree().create_timer(1.5).timeout.connect(burst.queue_free)
	var puff := CPUParticles2D.new()
	puff.one_shot = true
	puff.explosiveness = 0.9
	puff.amount = 20
	puff.lifetime = 0.9
	puff.position = size / 2.0
	puff.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	puff.emission_rect_extents = size * 0.5
	puff.spread = 180.0
	puff.gravity = Vector2(0, 60)
	puff.initial_velocity_min = 30.0
	puff.initial_velocity_max = 150.0
	puff.scale_amount_min = 4.0
	puff.scale_amount_max = 11.0
	puff.color = Color(OPEN_GLOW, 0.4)
	puff.emitting = true
	add_child(puff)
	get_tree().create_timer(1.3).timeout.connect(puff.queue_free)


## 부모(잿빛 재질): 금의 어두운 가장자리만 (빛은 _draw_glow 가 더하기 혼합으로 그 위에).
func _draw() -> void:
	if _broken:
		return
	if _shake > 0.0:
		draw_set_transform(Vector2(sin(_t * 90.0) * 3.0 * _shake, cos(_t * 70.0) * 1.5 * _shake))
	var pts := _crack_points()
	draw_polyline(pts, Color(0.05, 0.03, 0.02, 0.85), 5.0 + 6.0 * _damage, true)


## 금의 줄기: 벽 가운데를 지그재그로 내려간다 (방마다 같은 모양)
func _crack_points() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 9
	var ph := float(_rng_seed % 13) * 0.4
	for i in n + 1:
		var t := float(i) / n
		pts.append(Vector2(size.x * (0.5 + sin(t * 9.0 + ph) * 0.12 + sin(t * 23.0 + ph) * 0.04), t * size.y))
	return pts


## 틈으로 새는 빛 (더하기 혼합). 능력이 없으면 희미한 붉은빛, 있으면 따뜻한 금빛(밝은 값은 글로우로 번진다).
## 맞을수록 넓어지고 곁가지 금이 늘며, 능력 없이 때리면 붉게 크게 번쩍인다("아직 열 수 없다").
func _draw_glow() -> void:
	if _broken:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng_seed
	var open := can_break()
	var glow := LOCKED_GLOW if not open else OPEN_GLOW
	var pulse := 0.5 + 0.5 * sin(_t * 1.6 + float(_rng_seed % 7))
	var a := (0.32 + 0.18 * pulse) * (1.0 if open else 0.75) + 0.4 * _damage
	var core := Color(glow.r * (1.5 if open else 1.15), glow.g * (1.5 if open else 1.15), glow.b * (1.5 if open else 1.15), clampf(a, 0.0, 1.0))
	var pts := _crack_points()
	# 넓게 번지는 빛 → 가운데 밝은 줄
	_glow.draw_polyline(pts, Color(glow, a * 0.18), 26.0 + 18.0 * _damage, true)
	_glow.draw_polyline(pts, Color(glow, a * 0.45), 9.0 + 8.0 * _damage, true)
	_glow.draw_polyline(pts, core, 2.5 + 3.0 * _damage, true)
	# 곁가지 금 (맞을수록 늘어난다)
	var extra := 2 + int(_damage * 4.0 + _deny * 2.0)
	for k in extra:
		var p := pts[1 + (k * 2) % (pts.size() - 2)]
		var d := Vector2(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.6)).normalized() * rng.randf_range(14, 34)
		_glow.draw_line(p, p + d, Color(glow, a * 0.7), 1.5, true)
	# 능력 없이 맞았다: 붉은 번쩍임 (벽 전체가 잠깐 달아오른다)
	if _deny > 0.0:
		var red := Color(1.25, 0.2, 0.1, 0.75 * _deny)
		_glow.draw_rect(Rect2(Vector2(-4, -4), size + Vector2(8, 8)), Color(1.0, 0.18, 0.08, 0.12 * _deny))
		_glow.draw_polyline(pts, Color(red, 0.18 * _deny), 22.0 + 12.0 * _deny, true)
		_glow.draw_polyline(pts, red, 4.0 + 5.0 * _deny, true)

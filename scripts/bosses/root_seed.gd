extends Area2D
class_name RootSeed
## 씨앗 비 (뿌리지기 패턴): 하늘에서 떨어지는 가시 씨앗. 가드 가능.
## 떨어질 자리에 주황빛 점(가드 가능한 예고 색) + 하늘에서 내려오는 가는 선이 먼저 뜨고, 땅에 닿으면 가시가 터진다(짧은 판정).
## 생기면 바로 떨어지기 시작한다(delay 가 있으면 그동안 떠서 기다린다). 떨어지는 시간 ≈ FALL_HEIGHT / speed = 0.9초.
## 그림 (2026-10-19 이펙트 리뉴얼 F2): 기획자 이펙트 시트의 빛 꼬리를 단 가시 씨앗(art/fx/seed_fall)이 떨어지고,
## 땅에 닿으면 씨앗이 터지는 빛(Fx "seed_land")이 솟는다. 주황 바닥 예고는 코드 그림 그대로. 판정은 그대로.

var damage := 16.0
var speed := 1100.0
var ground_y := 0.0
var source: Node2D
var delay := 0.0
var _t := 0.0
var _landed := false
var _land_t := 0.0
var _hit_done := false
var _spin := 0.0
var _shape: CollisionShape2D
var _trail: Array[Vector2] = []
var _art: Sprite2D
const FALL_HEIGHT := 1000.0
## 그림: 씨앗 몸(UV y)이 판정 가운데에 오게, 배율
const ART := "seed_fall"
const ART_SEED_V := 0.8
const ART_SCALE := 0.62   # v1.1.0: 보이는 반경 ≈ 판정 SEED_R ×1.1 (예전 0.78 은 1.41배)
const BURST := 0.35
const BURST_RADIUS := 70.0
const SEED_R := 28.0
## 바닥 주황 점(예고)의 반폭: 터짐 판정(반지름 BURST_RADIUS)보다 조금 넓게 — 점 밖이면 안 맞는다
const MARK_RX := BURST_RADIUS + 10.0
const MARK_RY := 18.0


func _ready() -> void:
	add_to_group("projectile")
	add_to_group("root_effect")
	collision_layer = 0
	collision_mask = 8
	_shape = CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = SEED_R
	_shape.shape = c
	add_child(_shape)
	_art = Sprite2D.new()
	_art.texture = Fx.texture(ART)
	_art.material = Fx.shared_material("", false, 0.0)
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _art.texture:
		_art.offset = Vector2(0.0, -(ART_SEED_V - 0.5) * _art.texture.get_height())
	_art.scale = Vector2(ART_SCALE, ART_SCALE)
	add_child(_art)


## 땅 위 높이 (시험용)
func height() -> float:
	return ground_y - global_position.y


func landed() -> bool:
	return _landed


func _physics_process(delta: float) -> void:
	_t += delta
	_spin += delta * 9.0
	if _landed:
		_land_t += delta
		if _land_t > BURST:
			queue_free()
			return
		if _land_t < 0.2:
			_try_hit(Vector2(220, -360))
		queue_redraw()
		return
	if _t < delay:
		global_position.y += sin(_t * 6.0) * 10.0 * delta
		queue_redraw()
		return
	global_position.y += speed * delta
	_trail.push_front(global_position)
	if _trail.size() > 7:
		_trail.resize(7)
	if global_position.y >= ground_y - 26.0:
		global_position.y = ground_y - 26.0
		_landed = true
		_land_t = 0.0
		var c: CircleShape2D = _shape.shape
		c.radius = BURST_RADIUS
		_shape.position = Vector2(0, -20)
		Juice.shake(3.0)
		Sfx.play("seed_land", -6.0, 0.15)
		if _art:
			_art.visible = false
			Fx.spawn("seed_land", Vector2(global_position.x, ground_y + 4.0))
		queue_redraw()
		return
	_try_hit(Vector2(200, -320))
	queue_redraw()


func _try_hit(kb: Vector2) -> void:
	if _hit_done:
		return
	for area in get_overlapping_areas():
		if area is Hurtbox:
			var hit := HitData.make(damage, 0.0, source if source else self, kb)
			hit.hitstop = 0.04
			var res: String = area.receive(hit)
			if res != "ignored":
				_hit_done = true
				return


func _draw() -> void:
	var gy := ground_y - global_position.y   # 땅의 로컬 y
	if not _landed:
		# 예고: 땅의 주황 점 (가까워질수록 안이 찬다) + 하늘에서 내려오는 가는 선
		var prog := clampf(1.0 - (gy - 26.0) / FALL_HEIGHT, 0.0, 1.0)
		var pulse := 0.6 + 0.4 * sin(_t * 18.0)
		var tg := Color(1.0, 0.5, 0.15)
		draw_colored_polygon(RootSpike._ellipse(Vector2(0, gy), MARK_RX, MARK_RY), Color(tg, 0.22 + 0.25 * prog * pulse))
		draw_colored_polygon(RootSpike._ellipse(Vector2(0, gy), MARK_RX * prog, MARK_RY * prog), Color(tg, 0.55))
		draw_polyline(RootSpike._ellipse(Vector2(0, gy), MARK_RX, MARK_RY, 28) + PackedVector2Array([Vector2(MARK_RX, gy)]), Color(tg, 0.6 + 0.3 * pulse), 2.0, true)
		draw_line(Vector2(0, 0), Vector2(0, gy), Color(tg, 0.18 + 0.2 * prog), 2.0)
		if _art and _art.texture:
			return   # 씨앗 몸·꼬리는 그림이 그린다
		# 꼬리
		for i in _trail.size():
			var k := 1.0 - float(i) / _trail.size()
			draw_circle(to_local(_trail[i]) + Vector2(0, -SEED_R * (1.0 - k)), SEED_R * 0.7 * k, Color(0.55, 0.4, 0.7, 0.28 * k))
		# 씨앗 몸 (돌며 떨어진다) + 가시
		draw_set_transform(Vector2.ZERO, _spin, Vector2.ONE)
		draw_colored_polygon(RootSpike._ellipse(Vector2.ZERO, SEED_R, SEED_R * 0.8, 14), Color(0.33, 0.2, 0.36))
		for i in 8:
			var a := TAU * i / 8.0
			var d := Vector2(cos(a), sin(a))
			draw_colored_polygon(PackedVector2Array([d * SEED_R * 0.8 + d.orthogonal() * 6.0, d * (SEED_R + 16.0), d * SEED_R * 0.8 - d.orthogonal() * 6.0]), Color(0.78, 0.66, 0.9))
		draw_circle(Vector2(-6, -6), 8.0, Color(0.62, 0.48, 0.7))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		if _art and _art.texture:
			return   # 터짐은 Fx "seed_land" 가 그린다
		# 터짐: 땅에서 솟는 가시 다발 (짧게)
		var k := clampf(_land_t / 0.12, 0.0, 1.0)
		var fade := 1.0 - clampf((_land_t - 0.2) / 0.15, 0.0, 1.0)
		if k < 0.03:
			return
		for i in 7:
			var a := -PI / 2.0 + (i - 3) * 0.36
			var d := Vector2(cos(a), sin(a))
			var len := (70.0 + 20.0 * absf(i - 3)) * k
			draw_colored_polygon(PackedVector2Array([Vector2(0, 26) + d.orthogonal() * 9.0, Vector2(0, 26) + d * len, Vector2(0, 26) - d.orthogonal() * 9.0]), Color(0.42, 0.28, 0.5, fade))
			draw_circle(Vector2(0, 26) + d * len, 5.0, Color(0.9, 0.8, 1.0, fade))
		draw_circle(Vector2(0, 0), 60.0 * k, Color(0.7, 0.5, 1.0, 0.12 * fade))

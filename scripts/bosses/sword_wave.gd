extends Area2D
class_name SwordWave
## 등불 기사의 검기(劍氣): 창을 크게 베면 빛의 베기가 땅을 따라(또는 비스듬히 위로) 날아간다.
## 가드 가능. 저스트 가드로 되받으면 기사에게 돌아가 흐트러짐을 준다(reflect_poise = +40, 그 밖의 흐트러짐은 없다).
## 맞힐 때 HitData 출처는 검기 자신이다: 소녀의 가드 방향은 검기 자리 기준으로 재고, 저스트 가드해도 기사의
## on_just_guarded(창 튕김·흐트러짐 +45)는 불리지 않는다. source(기사)는 되받았을 때 돌아갈 곳·출처 표시로만 쓴다.
## 한쪽 발판(one_way 가지)은 아래에서 뚫고 지나간다 (소녀가 아래에서 뛰어오르며 지나가는 것과 같다).
## 구르기(무적)로 지나가면 사라지지 않고 계속 날아간다 — 한 번 판정한 상대는 다시 맞추지 않는다.
## Projectile 과 달리 판정이 세로로 긴 초승달이라 서서 가드하거나 점프로 넘기게 된다(땅 검기는 낮게 깔린다).
## 그림 (2026-10-19 이펙트 리뉴얼 F2): 기획자 이펙트 시트의 물 초승달(art/fx/water_crescent_big)을 불꽃 팔레트로 칠한 것 +
## 뒤따르는 옅은 그림자 한 겹 + 불씨 입자. 되받으면 금빛. 판정 상자 = size × HIT_BOX_K (v1.1.0 통합: 보이는 초승달에 맞춤).

signal reflected(wave: SwordWave)

@export var speed := 760.0
@export var damage := 18.0
@export var lifetime := 2.4
## 그림·판정 크기 (가로 = 초승달 두께 방향, 세로 = 날 길이)
@export var size := Vector2(150, 130)
@export var color := Color(1.0, 0.8, 0.42)
## 되받아 기사에게 돌아갔을 때 주는 흐트러짐
@export var reflect_poise := 40.0

var direction := Vector2.LEFT
var source: Node2D
var from_player := false
var _time := 0.0
var _dead := false
var _targets: Array = []
var _embers: CPUParticles2D
var _trail: Array[Vector2] = []
var _art: Sprite2D
var _echo: Sprite2D
## 그림: 물 초승달(볼록한 쪽이 앞) — 배율·자리 (2026-10-19 크기 그대로: 보이는 세로 반폭 ≈ 96, 볼록한 앞 끝 ≈ +50).
## v1.1.0 통합 (요청 4 '예고 = 판정', 명세 3.6 '보이는 그림 = 판정 ±20%'): 그림은 줄이지 않고 판정 상자를 그림에 맞춰 키웠다 —
## 예전 상자 75×110.5 (size × (0.5, 0.85)) → size × HIT_BOX_K ≈ 95×183 (세로 반폭 91.5, 앞 끝 47.6).
const ART := "water_crescent_big"
const ART_SCALE := Vector2(0.6, 0.72)
const ART_OFFSET := Vector2(-30.0, 0.0)
## 판정 상자 = size × 이 값 (그림 배율·자리를 바꾸면 함께 고친다 — probe_boss_melee 가 ±20% 를 확인)
const HIT_BOX_K := Vector2(0.635, 1.405)
## 뒤따르는 그림자의 자리 (그림 뒤로)
const ECHO_BACK := 40.0


## 판정 상자 크기 (가로 = 진행 방향)
func hit_box_size() -> Vector2:
	return size * HIT_BOX_K


func _ready() -> void:
	add_to_group("projectile")
	collision_layer = 0
	_update_mask()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = hit_box_size()
	shape.shape = rect
	add_child(shape)
	monitoring = true
	monitorable = false
	rotation = direction.angle()
	# 뒤로 흩어지는 불씨
	_embers = CPUParticles2D.new()
	_embers.amount = 18
	_embers.lifetime = 0.5
	_embers.local_coords = false
	_embers.direction = Vector2(-1, 0)
	_embers.spread = 35.0
	_embers.gravity = Vector2(0, -40)
	_embers.initial_velocity_min = 60.0
	_embers.initial_velocity_max = 180.0
	_embers.scale_amount_min = 2.0
	_embers.scale_amount_max = 4.5
	_embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_embers.emission_rect_extents = Vector2(6, size.y * 0.35)
	_embers.color = Color(1.0, 0.7, 0.3, 0.9)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_embers.material = add
	add_child(_embers)
	_echo = _make_art(Color(1, 1, 1, 0.3))
	_echo.position = ART_OFFSET + Vector2(-ECHO_BACK, 0.0)
	_echo.scale = ART_SCALE * 0.9
	_art = _make_art(Color(1.05, 1.02, 1.0, 1.0))


func _make_art(col: Color) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = Fx.texture(ART)
	sp.material = Fx.shared_material("fire", false, 0.15)
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sp.position = ART_OFFSET
	sp.scale = ART_SCALE
	sp.modulate = col
	add_child(sp)
	return sp


## 검기가 뚫고 지나가는 지형인가: 한쪽 발판(가지).
static func passes_through(col: Object) -> bool:
	return col is Platform and (col as Platform).one_way


func _update_mask() -> void:
	# 기사 검기는 소녀 맞는 영역(8), 되받은 검기는 적 맞는 영역(16). 지형(1)에는 막힌다.
	collision_mask = 1 | (16 if from_player else 8)


func launch(dir: Vector2, src: Node2D, player_owned := false) -> void:
	direction = dir.normalized()
	source = src
	from_player = player_owned
	_update_mask()
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	var from := global_position
	var to := from + direction * speed * delta
	# v1.1.0 (기획자 요청 4): 보스 투사체라 지형(벽·가지)에 막히지 않는다 — 수명이 다하면 사라진다.
	global_position = to
	rotation = direction.angle()
	if _art:
		# 살짝 일렁이고 그림자가 뒤에서 따라온다
		_art.scale = ART_SCALE * Vector2(1.0, 1.0 + 0.05 * sin(_time * 28.0))
		_echo.position = ART_OFFSET + Vector2(-ECHO_BACK - 12.0 * sin(_time * 16.0), 0.0)
	if _time > lifetime:
		_vanish()
		return
	for area in get_overlapping_areas():
		if area is Hurtbox:
			_hit(area)
			if _dead:
				return
	queue_redraw()


func _hit(area: Hurtbox) -> void:
	if _targets.has(area):
		return
	_targets.append(area)
	var hit := HitData.make(damage, reflect_poise if from_player else 0.0, self, Vector2(420, -160))
	hit.guardable = true
	hit.from_player = from_player
	hit.reflected = from_player   # 검기는 기사만 쏜다: 소녀 쪽이면 되받은 것
	hit.hitstop = 0.05
	var result: String = area.receive(hit)
	match result:
		"just_guard":
			if not from_player:
				_reflect(area.owner_node)
				return
		"ignored", "dodge":
			# 무적·구르기: 검기는 그대로 지나간다 (이 상대는 다시 맞추지 않음)
			return
	_vanish()


## 저스트 가드로 되받음: 기사에게 돌아간다. 빠르고 밝아지며, 맞히면 흐트러짐 reflect_poise.
func _reflect(_by: Node) -> void:
	from_player = true
	_update_mask()
	speed *= 1.25
	damage *= 1.5
	color = Color(1.0, 0.95, 0.72)
	_time = 0.0
	lifetime = 3.0
	_targets.clear()
	if _art:
		_art.material = Fx.shared_material("gold", false, 0.2)
		_echo.material = _art.material
	if is_instance_valid(source):
		direction = (source.global_position + Vector2(0, -150) - global_position).normalized()
	else:
		direction = -direction
	rotation = direction.angle()
	reflected.emit(self)


func _vanish() -> void:
	_dead = true
	set_deferred("monitoring", false)
	_embers.emitting = false
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.14)
	tw.tween_callback(queue_free)


func _draw() -> void:
	if _art:
		return   # 그림(Sprite2D)이 그린다
	# (그림을 못 읽었을 때만) 예전 코드 그림: 앞으로 볼록한 호 세 겹
	var r := size.y * 0.5
	var c := Vector2(-size.x * 0.35, 0)
	var span := 1.05
	draw_arc(c, r * 1.08, -span, span, 24, Color(color.r * 1.2, color.g * 1.1, color.b, 0.28), size.x * 0.42, true)
	draw_arc(c, r, -span * 0.95, span * 0.95, 24, Color(color.r * 1.6, color.g * 1.4, color.b * 1.1, 0.95), size.x * 0.2, true)
	draw_arc(c, r * 0.96, -span * 0.8, span * 0.8, 20, Color(2.2, 2.0, 1.6, 0.9), size.x * 0.07, true)

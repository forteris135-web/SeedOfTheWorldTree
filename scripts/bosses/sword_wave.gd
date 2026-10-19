extends Area2D
class_name SwordWave
## 등불 기사의 검기(劍氣): 창을 크게 베면 빛의 베기가 땅을 따라(또는 비스듬히 위로) 날아간다.
## 가드 가능. 저스트 가드로 되받으면 기사에게 돌아가 흐트러짐을 준다(reflect_poise = +40, 그 밖의 흐트러짐은 없다).
## 맞힐 때 HitData 출처는 검기 자신이다: 소녀의 가드 방향은 검기 자리 기준으로 재고, 저스트 가드해도 기사의
## on_just_guarded(창 튕김·흐트러짐 +45)는 불리지 않는다. source(기사)는 되받았을 때 돌아갈 곳·출처 표시로만 쓴다.
## 한쪽 발판(one_way 가지)은 아래에서 뚫고 지나간다 (소녀가 아래에서 뛰어오르며 지나가는 것과 같다).
## 구르기(무적)로 지나가면 사라지지 않고 계속 날아간다 — 한 번 판정한 상대는 다시 맞추지 않는다.
## Projectile 과 달리 판정이 세로로 긴 초승달이라 서서 가드하거나 점프로 넘기게 된다(땅 검기는 낮게 깔린다).

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


func _ready() -> void:
	add_to_group("projectile")
	collision_layer = 0
	_update_mask()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x * 0.5, size.y * 0.85)
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
	var ray := PhysicsRayQueryParameters2D.create(from, to, 1)
	var hit_terrain := get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit_terrain.is_empty() and not passes_through(hit_terrain.get("collider")):
		_vanish()
		return
	global_position = to
	rotation = direction.angle()
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
	# 초승달: 앞으로 볼록한 호 세 겹 (바깥 흐린 빛 → 가운데 진한 빛 → 안쪽 흰 심). HDR 글로우 문턱(1.0)을 넘는 밝기로 발광한다.
	var r := size.y * 0.5
	var c := Vector2(-size.x * 0.35, 0)
	var span := 1.05
	var glow := Color(color.r * 1.2, color.g * 1.1, color.b, 0.28)
	draw_arc(c, r * 1.08, -span, span, 24, glow, size.x * 0.42, true)
	draw_arc(c, r, -span * 0.95, span * 0.95, 24, Color(color.r * 1.6, color.g * 1.4, color.b * 1.1, 0.95), size.x * 0.2, true)
	draw_arc(c, r * 0.96, -span * 0.8, span * 0.8, 20, Color(2.2, 2.0, 1.6, 0.9), size.x * 0.07, true)
	# 뒤로 길게 끌리는 잔광
	for i in 3:
		var k := float(i + 1)
		draw_arc(c - Vector2(size.x * 0.22 * k, 0), r * (1.0 - 0.06 * k), -span * (0.9 - 0.15 * k), span * (0.9 - 0.15 * k), 16,
			Color(color.r, color.g, color.b, 0.35 - 0.1 * k), size.x * (0.14 - 0.03 * k), true)
	if from_player:
		draw_circle(c + Vector2(r * 0.4, 0), r * 0.5, Color(1.0, 0.95, 0.8, 0.15))

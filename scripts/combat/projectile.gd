extends Area2D
class_name Projectile
## 날아가는 공격 (깃털 화살, 잿빛 잎, 바람). 맞는 영역(Hurtbox)에 닿으면 receive_hit 를 부른다.
## 저스트 가드로 되받아칠 수 있는 것은 방향이 뒤집혀 쏜 쪽에게 돌아간다.

enum Kind { FEATHER, LEAF, GUST }

signal reflected(projectile: Projectile)

@export var kind: Kind = Kind.FEATHER
@export var speed := 900.0
@export var damage := 12.0
@export var poise := 10.0
@export var lifetime := 4.0
## 저스트 가드로 되받아칠 수 있는가 (깃털만).
@export var reflectable := false
@export var guardable := true
## 중력 (잎은 살짝 떨어진다).
@export var fall_gravity := 0.0
## 추적 세기 (0 = 직진). 소녀 쪽으로 천천히 휜다.
@export var homing := 0.0
## 그림 크기
@export var size := Vector2(70, 14)
@export var color := Color(0.75, 0.78, 0.8)

var direction := Vector2.RIGHT
var source: Node2D
## true 면 소녀 쪽 공격 (적을 맞춘다)
var from_player := false
var _time := 0.0
var _wobble := randf() * TAU
var _dead := false


func _ready() -> void:
	add_to_group("projectile")
	collision_layer = 0
	_update_mask()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = maxf(size.y * 0.6, 10.0)
	shape.shape = circle
	add_child(shape)
	monitoring = true
	monitorable = false
	rotation = direction.angle()


func _update_mask() -> void:
	# 소녀 공격이면 적 맞는 영역(16), 적 공격이면 소녀 맞는 영역(8). 지형(1)에는 항상 막힌다.
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
	if fall_gravity > 0.0:
		direction = (direction * speed + Vector2(0, fall_gravity * delta)).normalized()
	if homing > 0.0 and not from_player and _time < lifetime * 0.7:
		var target := get_tree().get_first_node_in_group("player") as Node2D
		if target:
			var want := (target.global_position + Vector2(0, -50) - global_position).normalized()
			direction = direction.slerp(want, clampf(homing * delta, 0.0, 1.0)).normalized()
	var wobble := Vector2.ZERO
	if kind == Kind.LEAF:
		wobble = Vector2(sin(_time * 3.0 + _wobble) * 60.0, 0) * delta
	var from := global_position
	var to := from + direction * speed * delta + wobble
	# 지형에 막힌다 (빠른 투사체가 얇은 발판을 건너뛰지 않게 선으로 검사)
	var ray := PhysicsRayQueryParameters2D.create(from, to, 1)
	var hit_terrain := get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit_terrain.is_empty():
		global_position = hit_terrain["position"]
		# 소녀의 바람·빛이 '때리면 부서지는 벽' 같은 지형에 닿으면 한 대로 친다
		var col = hit_terrain.get("collider")
		if from_player and col and col.has_method("receive_hit"):
			var h := HitData.make(damage, poise, source if source else self, Vector2(200, -60))
			h.from_player = true
			col.receive_hit(h, null)
		_vanish()
		return
	global_position = to
	rotation = direction.angle() + (sin(_time * 4.0 + _wobble) * 0.6 if kind == Kind.LEAF else 0.0)
	if _time > lifetime:
		_vanish()
		return
	for area in get_overlapping_areas():
		if area is Hurtbox:
			_hit(area)
			return
	queue_redraw()


func _hit(area: Hurtbox) -> void:
	var hit := HitData.make(damage, poise, source if source else self, Vector2(260, -100))
	hit.guardable = guardable
	hit.from_player = from_player
	hit.hitstop = 0.04
	var result: String = area.receive(hit)
	if result == "just_guard" and reflectable and not from_player:
		_reflect(area.owner_node)
		return
	if result == "ignored":
		return
	_vanish()


func _reflect(by: Node) -> void:
	from_player = true
	_update_mask()
	speed *= 1.5
	damage *= 1.6
	poise = 28.0
	_time = 0.0
	lifetime = 3.0
	color = Color(1.0, 0.85, 0.5)
	var target := source
	if is_instance_valid(target):
		direction = (target.global_position - global_position).normalized()
	else:
		direction = -direction
	rotation = direction.angle()
	reflected.emit(self)


func _vanish() -> void:
	_dead = true
	set_deferred("monitoring", false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(queue_free)


func _draw() -> void:
	match kind:
		Kind.FEATHER:
			# 깃털: 길쭉한 잎 모양 + 가운데 심
			var pts := PackedVector2Array()
			var n := 10
			for i in n + 1:
				var t := float(i) / n
				pts.append(Vector2(lerpf(-size.x / 2, size.x / 2, t), -sin(t * PI) * size.y / 2))
			for i in range(n, -1, -1):
				var t := float(i) / n
				pts.append(Vector2(lerpf(-size.x / 2, size.x / 2, t), sin(t * PI) * size.y / 2 * 0.8))
			draw_colored_polygon(pts, color)
			draw_line(Vector2(-size.x / 2, 0), Vector2(size.x / 2, 0), color.darkened(0.35), 1.5, true)
			if from_player:
				draw_circle(Vector2.ZERO, size.y * 0.9, Color(1.0, 0.85, 0.5, 0.25))
		Kind.LEAF:
			var s := size.x / 2
			draw_colored_polygon(PackedVector2Array([
				Vector2(-s, 0), Vector2(-s * 0.3, -s * 0.55), Vector2(s, 0), Vector2(-s * 0.3, s * 0.55)]), color)
			draw_line(Vector2(-s, 0), Vector2(s, 0), color.darkened(0.3), 1.5, true)
		Kind.GUST:
			for i in 3:
				var r := size.y * (0.6 + i * 0.35)
				draw_arc(Vector2(-i * 10.0, 0), r, -1.1, 1.1, 12, Color(color, 0.7 - i * 0.2), 3.0, true)

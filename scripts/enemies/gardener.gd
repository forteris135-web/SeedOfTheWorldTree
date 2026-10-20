extends EnemyBase
class_name Gardener
## 씨앗 적 (씨앗을 뿌리던 정원사). 멀리서 단단한 씨앗을 쏜다.
## 저스트 가드로 씨앗을 되받아치면 정원사가 맞는다. 가까이 오면 뒤로 물러난다.

@export var seed_speed := 760.0
@export var seed_damage := 11.0
@export var shoot_range := 760.0
@export var keep_distance := 260.0
@export var shots_per_volley := 2

const PROJECTILE := preload("res://scenes/combat/projectile.tscn")
var _shot := 0


func _physics_process(delta: float) -> void:
	# 바탕 상태 기계를 쓰되, 공격 판단만 바꾼다
	if state == State.CHASE and player and _sees_player(notice_range * 1.4):
		var dx := player.global_position.x - global_position.x
		facing = 1 if dx > 0.0 else -1
		if absf(dx) < keep_distance and _can_walk(-facing):
			# 뒤로 물러난다 (그림은 이동 방향·공중 여부를 보고 스스로 뒷걸음·폴짝 자세를 잡는다)
			_tick_common(delta)
			if is_on_floor() and _timer <= -0.4:
				velocity.y = -380.0   # 폴짝 물러난다
				_timer = 0.0
			velocity.x = move_toward(velocity.x, -facing * walk_speed * 1.1, 1800.0 * delta)
			if not is_on_floor():
				velocity.y += gravity * delta
			move_and_slide()
			return
		if absf(dx) <= shoot_range and _timer <= 0.0:
			_tick_common(delta)
			_begin_windup()
			_shot = 0
			if not is_on_floor():
				velocity.y += gravity * delta
			move_and_slide()
			return
	if anim_hint == "shoot" and state != State.STRIKE:
		anim_hint = ""
	super._physics_process(delta)


func _strike() -> void:
	_set_state(State.STRIKE)
	anim_hint = "shoot"   # 쏘는 자세 (휘두르기가 아니다)
	_timer = strike_time + 0.15 * shots_per_volley
	_shoot()


func _shoot() -> void:
	if player == null:
		return
	var p: Projectile = PROJECTILE.instantiate()
	p.kind = Projectile.Kind.FEATHER
	p.speed = seed_speed
	p.damage = seed_damage
	p.poise = 0.0
	p.reflectable = true
	p.size = Vector2(26, 18)
	p.color = Color(0.76, 0.62, 0.3)
	p.look = "gardener_seed"   # 이펙트 리뉴얼 F2: 금빛 씨앗 그림
	get_parent().add_child(p)
	var origin := shot_origin(global_position + Vector2(facing * 70.0, -hurt_height * 0.55))   # 뼈대 대롱 끝 (2026-10-20)
	p.global_position = origin
	var dir := (player.global_position + Vector2(0, -40) - origin).normalized()
	p.launch(dir, self, false)
	Fx.spawn("seed_muzzle", origin, {"rot": rad_to_deg(dir.angle())})
	_shot += 1
	# 반동은 실제로 쏘는 순간에 맞춰 그림에 직접 전한다
	_visual_call("recoil", [1.0])
	if _shot < shots_per_volley:
		get_tree().create_timer(0.18).timeout.connect(func() -> void:
			if state == State.STRIKE:
				_shoot())

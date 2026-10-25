extends EnemyBase
class_name Herbalist
## 포자 적 (약초를 캐던 약초꾼). 주변에 빛나는 **포자 구름**을 뿌린다. 안에서는 느려지고 체력이 깎인다.
## 등불(기사의 영혼)을 든 소녀가 들어가면 포자가 타서 걷힌다. 가까이 오면 뒤로 빠지며 포자를 더 뿌린다.

@export var cloud_radius := 150.0
@export var cloud_time := 6.0
@export var cloud_dps := 6.0
@export var cloud_slow := 0.55
@export var keep_distance := 300.0

const CLOUD := preload("res://scenes/combat/spore_cloud.tscn")


func _begin_windup() -> void:
	super._begin_windup()
	_timer = windup_time * 0.9


func _strike() -> void:
	_set_state(State.STRIKE)
	anim_hint = "scatter"   # 뿌리는 자세: 숙였다 펴며 포자를 흩뿌린다 (휘두르기가 아니다)
	_timer = strike_time + 0.2
	# 자기 주위와 소녀 쪽에 포자 구름
	_spawn_cloud(global_position + Vector2(facing * 140.0, -40.0))
	# 멀리 있는 소녀 자리에도 하나 — 바라보는 쪽(앞)에 있을 때만 (v1.1.0: 등 뒤로는 뿌리지 않는다)
	if player and absf(player.global_position.x - global_position.x) > 260.0 and _player_in_front():
		_spawn_cloud(player.global_position + Vector2(0, -40.0))


func _spawn_cloud(at: Vector2) -> void:
	var c := CLOUD.instantiate()
	c.radius = cloud_radius
	c.lifetime = cloud_time
	c.dps = cloud_dps
	c.slow = cloud_slow
	get_parent().add_child(c)
	c.global_position = at


func _physics_process(delta: float) -> void:
	if anim_hint == "scatter" and state != State.STRIKE:
		anim_hint = ""
	if state == State.CHASE and player and _sees_player(notice_range * 1.4):
		var dx := player.global_position.x - global_position.x
		# v1.1.0: 등 뒤로 간 소녀에게는 turn_delay(0.5초) 뒤에 돌아선다. 도는 동안은 멈칫
		if _turn_toward_player(delta) != facing:
			_tick_common(delta)
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			if not is_on_floor():
				velocity.y += gravity * delta
			move_and_slide()
			return
		if absf(dx) < keep_distance and _can_walk(-facing):
			# 뒤로 걷는다 (그림은 이동 방향을 보고 뒷걸음 자세를 잡는다)
			_tick_common(delta)
			velocity.x = move_toward(velocity.x, -facing * walk_speed, 1800.0 * delta)
			if not is_on_floor():
				velocity.y += gravity * delta
			move_and_slide()
			if _timer <= 0.0:
				_begin_windup()
			return
	super._physics_process(delta)

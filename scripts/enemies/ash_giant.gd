extends EnemyBase
class_name AshGiant
## 중간 보스 '잿가지 거인'. 수관의 숨겨진 둥지에 산다. 큰 나무꾼: 휘두르기와 **내려찍기**(뛰어올라 떨어지며 넓게 충격).
## 화면 아래에 보스식 체력 바가 뜬다 (MiniBossRoom 이 BossHUD 를 묶는다).

@export var slam_damage := 26.0
@export var slam_box := Rect2(-230, -90, 460, 130)

var _slamming := false
var _airborne := false


func _strike() -> void:
	if randf() < 0.45 and player and absf(player.global_position.x - global_position.x) > 120.0:
		# 내려찍기: 소녀 쪽으로 뛰어올라 떨어진다. 그림은 도약(leap) → 낙하(fall) → 착지(land) 세 박자.
		_set_state(State.STRIKE)
		_timer = 1.6
		_slamming = true
		_airborne = false
		anim_hint = "leap"
		var dx := clampf(player.global_position.x - global_position.x, -520.0, 520.0)
		velocity = Vector2(dx * 1.6, -980.0)
		Juice.shake(3.0)
		return
	super._strike()


func _physics_process(delta: float) -> void:
	if _slamming and state == State.STRIKE:
		_tick_common(delta)
		if not is_on_floor():
			velocity.y += gravity * delta
			_airborne = true
			velocity.x = move_toward(velocity.x, 0.0, 300.0 * delta)
			if velocity.y > 0.0:
				anim_hint = "fall"
		elif _airborne:
			# 착지: 충격파
			_airborne = false
			_slamming = false
			var hit := HitData.make(slam_damage, 0.0, self, Vector2(600, -300))
			hitbox.set_box(slam_box, facing)
			hitbox.activate(hit, 0.22)
			Juice.shake(12.0)
			Juice.hitstop(0.05, 0.1)
			Juice.rumble(0.6, 0.9, 0.25)
			velocity.x = 0.0
			anim_hint = "land"
			_visual_call("impact", [0, 1.8])
			Fx.spawn("ash_slam", global_position)   # 이펙트 리뉴얼 F2: 잿빛 잎 터짐 + 땅 고리 + 먼지
			_set_state(State.RECOVER)
			_timer = recover_time + 0.3
		if _timer <= 0.0:   # 어딘가 걸렸다
			_slamming = false
			anim_hint = ""
			_set_state(State.RECOVER)
			_timer = recover_time
		move_and_slide()
		return
	# 착지 웅크림은 회복의 앞부분(0.35초)까지만
	if anim_hint == "land" and (state != State.RECOVER or state_time > 0.35):
		anim_hint = ""
	if anim_hint in ["leap", "fall"] and state != State.STRIKE:
		anim_hint = ""
	super._physics_process(delta)

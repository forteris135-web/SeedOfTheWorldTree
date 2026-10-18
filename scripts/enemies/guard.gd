extends EnemyBase
class_name Guard
## 방패 돌진 적 (침식된 마을 경비병). 나무껍질 방패로 정면을 막는다(그냥 때리면 튕김).
## 붉은 예고 뒤 **가드 불가 돌진**. 피하면 방패가 박혀 잠시 무방비(흐트러짐 2배). 방패 치기도 한다.

@export var charge_speed := 980.0
@export var charge_time := 0.65
@export var charge_damage := 22.0
@export var stuck_time := 1.6
@export var charge_chance := 0.55

var _mode := ""          # "", "bash", "charge", "stuck"
var _charge_timer := 0.0


func _begin_windup() -> void:
	super._begin_windup()
	if randf() < charge_chance:
		_mode = "charge"
		anim_hint = "red"           # 붉은 예고 = 가드 불가
		_timer = windup_time * 1.3  # 예고 길이는 _tick_common 이 첫 틱에 잡아 windup_progress 가 0→1 이 된다
	else:
		_mode = "bash"
		anim_hint = ""


func _strike() -> void:
	if _mode == "charge":
		_set_state(State.STRIKE)
		anim_hint = "charge"
		_charge_timer = charge_time
		_timer = charge_time + 0.05
		var hit := HitData.make(charge_damage, 0.0, self, Vector2(620, -260))
		hit.guardable = false
		hitbox.set_box(Rect2(10, -110, 150, 140), facing)
		hitbox.activate(hit, charge_time)
		return
	anim_hint = ""
	super._strike()


func _physics_process(delta: float) -> void:
	if state == State.STRIKE and _mode == "charge":
		_tick_common(delta)
		_charge_timer -= delta
		velocity.x = facing * charge_speed
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		var blocked := is_on_wall() or not _can_walk(facing)
		if blocked or _charge_timer <= 0.0:
			# 방패가 박혔다: 무방비. 그림은 '꽝' 하고 박히는 충격 반동.
			hitbox.deactivate()
			_mode = "stuck"
			anim_hint = "stuck"
			velocity.x = 0.0
			_set_state(State.RECOVER)
			_timer = stuck_time
			Juice.shake(5.0)
			_visual_call("impact", [facing, 1.3 if blocked else 0.8])
		return
	if state == State.RECOVER and _mode == "stuck":
		_tick_common(delta)
		velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		if _timer <= 0.0:
			_mode = ""
			anim_hint = ""
			_set_state(State.CHASE)
			_timer = cooldown
		return
	if _mode != "" and state in [State.IDLE, State.PATROL, State.ALERT, State.CHASE, State.HIT, State.BROKEN, State.DEAD]:
		_mode = ""
		anim_hint = ""
	super._physics_process(delta)


## 정면 방패: 무방비·무너짐·피격이 아닐 때 앞에서 온 공격은 튕긴다.
func receive_hit(hit: HitData, hb: Hurtbox) -> String:
	var stuck := _mode == "stuck"
	if not stuck and state in [State.IDLE, State.PATROL, State.ALERT, State.CHASE, State.LUNGE, State.WINDUP, State.BACKSTEP] and hit.source:
		var from_front := (hit.source.global_position.x - global_position.x) * facing > 0.0
		if from_front:
			_flash = 0.6
			Juice.hitstop(0.03, 0.1)
			# 방패로 막는 자세: 몸이 뒤로 살짝 밀리며 번쩍
			_visual_call("block", [-facing, clampf(hit.poise / 40.0, 0.6, 1.5)])
			return "blocked"
	if stuck:
		hit.poise *= 2.0
	return super.receive_hit(hit, hb)

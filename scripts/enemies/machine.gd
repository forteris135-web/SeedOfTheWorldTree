extends EnemyBase
class_name Machine
## 침식된 채굴 기계. 뿌리에 감겨 짐승처럼 움직인다. 단단해서 약공격이 잘 안 먹힌다(강공격·흐트러짐으로).
## 패턴: 느리게 기어오다가 **돌진 들이받기**(긴 예고, 가드 가능) / 가까우면 짓누르기.

@export var light_damage_ratio := 0.35
@export var ram_speed := 820.0
@export var ram_time := 0.5

var _ramming := false
var _ram_timer := 0.0


func _begin_windup() -> void:
	super._begin_windup()
	_ramming = player != null and absf(player.global_position.x - global_position.x) > attack_range * 0.8
	anim_hint = "" if not _ramming else "red"
	if _ramming:
		anim_hint = ""   # 가드 가능하므로 붉은 예고는 아님. 떨림만.
		_timer = windup_time * 1.2


func _strike() -> void:
	if _ramming:
		_set_state(State.STRIKE)
		anim_hint = "charge"
		_ram_timer = ram_time
		_timer = ram_time + 0.05
		var hit := HitData.make(damage * 1.2, 0.0, self, Vector2(560, -240))
		hitbox.set_box(Rect2(0, -120, 170, 150), facing)
		hitbox.activate(hit, ram_time)
		return
	super._strike()


func _physics_process(delta: float) -> void:
	if state == State.STRIKE and _ramming:
		_flash = maxf(_flash - delta * 8.0, 0.0)
		_ram_timer -= delta
		velocity.x = facing * ram_speed
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		if is_on_wall() or not _can_walk(facing) or _ram_timer <= 0.0:
			hitbox.deactivate()
			_ramming = false
			anim_hint = ""
			velocity.x = 0.0
			_set_state(State.RECOVER)
			_timer = recover_time * 1.5
			Juice.shake(4.0)
		return
	if _ramming and state not in [State.WINDUP, State.STRIKE]:
		_ramming = false
		anim_hint = ""
	super._physics_process(delta)


func receive_hit(hit: HitData, hb: Hurtbox) -> String:
	# 단단함: 약한 공격(흐트러짐 30 미만)은 피해가 크게 준다. 무너졌을 땐 온전히.
	if hit.poise < 30.0 and state != State.BROKEN:
		hit.damage *= light_damage_ratio
		_flash = 0.5
	return super.receive_hit(hit, hb)

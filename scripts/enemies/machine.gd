extends EnemyBase
class_name Machine
## 침식된 채굴 기계. 뿌리에 감겨 짐승처럼 움직인다. 단단해서 약공격이 잘 안 먹힌다(씨앗 베기·낙하 공격·흐트러짐으로).
## 패턴: 느리게 기어오다가 **돌진 들이받기**(긴 예고, 가드 가능) / 가까우면 짓누르기.

@export var light_damage_ratio := 0.35
@export var ram_speed := 820.0
@export var ram_time := 0.5
## 확장판 · 벽 부수기(wall_break) 능력이 있으면 무거운 공격(씨앗 베기·낙하 공격)이 장갑을 깨서 이 시간 동안 약공격도 온전히 들어간다.
@export var armor_break_time := 4.0
const WALL_BREAK_POISE := 45.0

var _ramming := false
var _ram_timer := 0.0
var _armor_timer := 0.0
var _fx_t := 0.0   # 이펙트 리뉴얼 F2: 드릴 불똥 간격


func _begin_windup() -> void:
	super._begin_windup()
	_ramming = player != null and absf(player.global_position.x - global_position.x) > attack_range * 0.8
	anim_hint = ""   # 가드 가능하므로 붉은 예고는 아님. 떨림만.
	if _ramming:
		_timer = windup_time * 1.2   # 긴 예고. 길이는 _tick_common 이 첫 틱에 잡아 진행도가 0→1.


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
	_armor_timer = maxf(_armor_timer - delta, 0.0)
	if state == State.STRIKE and _ramming:
		_tick_common(delta)
		_ram_timer -= delta
		velocity.x = facing * ram_speed
		_fx_t -= delta
		if _fx_t <= 0.0:
			_fx_t = 0.05
			var tip := fx_point("drill_tip", global_position + Vector2(facing * 150.0, -hurt_height * 0.35))   # 뼈대 드릴 끝
			Fx.spawn("drill_spark", tip + Vector2(randf_range(-10.0, 10.0), randf_range(-20.0, 20.0)))   # 이펙트: 드릴 불똥
		if not is_on_floor():
			velocity.y += gravity * delta
		move_and_slide()
		var hit_wall := is_on_wall() or not _can_walk(facing)
		if hit_wall or _ram_timer <= 0.0:
			hitbox.deactivate()
			_ramming = false
			anim_hint = ""
			velocity.x = 0.0
			_set_state(State.RECOVER)
			_timer = recover_time * 1.5
			Juice.shake(4.0)
			# 들이받기 끝: '꽝' 충격 반동 (벽에 부딛혔으면 더 크게)
			_visual_call("impact", [facing, 1.4 if hit_wall else 0.9])
			Fx.spawn("slam_impact", fx_point("drill_tip", global_position + Vector2(facing * 150.0, -hurt_height * 0.4)), {"scale": 1.3 if hit_wall else 0.9})   # 이펙트: 들이받음 (드릴 끝)
		return
	if _ramming and state not in [State.WINDUP, State.STRIKE]:
		_ramming = false
		anim_hint = ""
	super._physics_process(delta)


func is_armor_broken() -> bool:
	return _armor_timer > 0.0


func receive_hit(hit: HitData, hb: Hurtbox) -> String:
	# 벽 부수기: 무거운 공격이 장갑을 깬다 (한동안 약공격도 온전히)
	if hit.from_player and hit.poise >= WALL_BREAK_POISE and Progress.has_ability("wall_break"):
		_armor_timer = armor_break_time
		_flash = 1.0
	# 단단함: 약한 공격(흐트러짐 30 미만)은 피해가 크게 준다. 무너졌을 땐·장갑이 깨졌을 땐 온전히.
	if hit.poise < 30.0 and state != State.BROKEN and _armor_timer <= 0.0:
		var weak := hit.copy()   # Hitbox 는 같은 HitData 를 여러 상대에게 넘기므로 원본을 고치지 않는다
		weak.damage *= light_damage_ratio
		_flash = 0.5
		return super.receive_hit(weak, hb)
	return super.receive_hit(hit, hb)

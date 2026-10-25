extends EnemyBase
class_name SmallPump
## 작은 펌프 (잠긴 채굴장의 보조 기계, EXPANSION.md 9장). 사람이 아니라 뿌리에 감긴 작은 펌프.
## 제자리(아주 느린 순찰)에서 **정해진 리듬(rhythm 초 주기)** 으로 수액 덩어리를 쏜다 — 무쇠 펌프의 리듬 읽기와 저스트 가드 예습.
## 수액 덩어리는 저스트 가드로 되받으면 펌프에게 돌아간다 (reflectable).
## 기계라 약공격(흐트러짐 30 미만)은 피해가 절반만. 되받은 자기 방울은 장갑과 상관없이 ×1.5 (저스트 가드 예습의 보상). 벽 부수기 능력이 있으면 무거운 공격(씨앗 베기·낙하 공격)이 장갑을
## 깨서 armor_break_time 동안 약공격도 온전히 들어간다 (침식된 기계와 같은 규칙).

signal shot

## 쏘는 주기(초). 예고 시작 → 다음 예고 시작까지.
@export var rhythm := 2.0
## 쏘는 거리. 방울은 중력(420)으로 떨어지므로 이보다 멀면 소녀 앞 바닥에 떨어진다 (2026-10-19 검토: 820 → 700).
@export var shoot_range := 700.0
@export var blob_speed := 640.0
@export var blob_damage := 12.0
@export var light_damage_ratio := 0.5
@export var armor_break_time := 4.0
## 되받은 자기 방울의 피해 배수 (무쇠 펌프와 같은 규칙)
@export var reflect_damage_multiplier := 1.5

const HEAVY_POISE := 45.0

var shots := 0
var _noticed := false
var _beat := 0.9
var _armor_timer := 0.0


func _in_range() -> bool:
	if player == null or not is_instance_valid(player) or player.state == Player.State.DEAD:
		return false
	if arrival_grace_active() and state in [State.IDLE, State.PATROL]:
		return false   # 방에 막 들어선 소녀는 아직 겨누지 않는다 (도착 매복 없애기, EnemyBase._sees_player 와 같은 규칙)
	var d := player.global_position - global_position
	return absf(d.x) <= shoot_range and absf(d.y) <= 520.0


func _physics_process(delta: float) -> void:
	_beat -= delta
	_armor_timer = maxf(_armor_timer - delta, 0.0)
	if state in [State.IDLE, State.PATROL, State.ALERT, State.CHASE] and _in_range():
		# 제자리에서 소녀를 겨누고 리듬에 맞춰 쏜다 (쫓지도, 펄쩍 뛰지도 않는다)
		_tick_common(delta)
		if not _noticed:
			# 처음 겨눌 때는 소녀 쪽으로 바로 돈다 (다른 몹의 '발견'과 같은 규칙)
			_noticed = true
			facing = 1 if player.global_position.x > global_position.x else -1
		# v1.1.0: 등 뒤로 간 소녀에게는 turn_delay(0.5초) 뒤에 돌아선다 (리듬의 박이 와도 돌아서는 중이면 그 박은 쉰다 — 박자는 그대로)
		var turning := _turn_toward_player(delta) != facing
		velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
		if not is_on_floor():
			velocity.y += gravity * delta
		if _beat <= 0.0 and is_on_floor():
			_beat = rhythm
			if not turning:
				_begin_windup()
		move_and_slide()
		return
	if anim_hint == "shoot" and state != State.STRIKE:
		anim_hint = ""
	super._physics_process(delta)


func _strike() -> void:
	_set_state(State.STRIKE)
	anim_hint = "shoot"   # 쏘는 자세 (휘두르기가 아니다)
	_timer = strike_time
	_shoot()


func _shoot() -> void:
	if player == null or not is_instance_valid(player):
		return
	var p := SapBlob.make(blob_speed, blob_damage, 34.0)   # 무쇠 펌프와 같은 수액 방울 (저스트 가드로 되받기)
	p.fall_gravity = 420.0
	p.lifetime = 2.6
	get_parent().add_child(p)
	var origin := shot_origin(global_position + Vector2(facing * 60.0, -hurt_height * 0.5))   # 뼈대 대롱 끝 (2026-10-20)
	p.global_position = origin
	# 소녀가 움직이는 쪽을 조금 앞질러 겨눈다 (리듬을 알면 구르기로 피하고, 가드로 되받는다)
	var aim := player.global_position + Vector2(player.velocity.x * 0.25, -50.0 - absf(player.global_position.x - origin.x) * 0.18)
	p.launch(_forward_aim((aim - origin).normalized()), self, false)   # 등 뒤로는 쏘지 않는다 (v1.1.0)
	shots += 1
	shot.emit()
	_visual_call("recoil", [1.0])


func receive_hit(hit: HitData, hb: Hurtbox) -> String:
	if state == State.DEAD:
		return "ignored"
	if hit.source == self:
		# 저스트 가드로 되받은 내 방울: 약공격 규칙(절반)에 걸리지 않고 ×1.5
		var back := hit.copy()
		back.damage *= reflect_damage_multiplier
		return super.receive_hit(back, hb)
	var heavy := hit.poise >= HEAVY_POISE
	if Balance.WALL_BREAK_COMBAT and heavy and hit.from_player and Progress.has_ability("wall_break"):   # v1.1.0: 전투 효과 꺼 둠 (D15)
		_armor_timer = armor_break_time   # 장갑이 깨졌다: 한동안 약공격도 온전히
	if hit.poise < 30.0 and state != State.BROKEN and _armor_timer <= 0.0:
		var weak := hit.copy()   # Hitbox 는 같은 HitData 를 여러 상대에게 넘기므로 원본을 고치지 않는다
		weak.damage *= light_damage_ratio
		_flash = 0.5
		return super.receive_hit(weak, hb)
	return super.receive_hit(hit, hb)


func is_armor_broken() -> bool:
	return _armor_timer > 0.0

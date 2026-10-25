extends EnemyBase
class_name Guard
## 방패 돌진 적 (침식된 마을 경비병). 나무껍질 방패로 정면을 막는다(그냥 때리면 튕김).
## 붉은 예고 뒤 **가드 불가 돌진**. 피하면 방패가 박혀 잠시 무방비(흐트러짐 2배). 방패 치기도 한다.
##
## 공략 길 (기획자 요청으로 너프):
## - 늦게 돌아선다(turn_delay 0.5초 — v1.1.0 부터 모든 몹 공통): 구르기로 등 뒤로 가면 그동안 방패가 없다.
## - 방패 판정은 **그림이 실제로 보는 방향** 기준이다 (그림이 저쪽을 보는데 튕기는 일 없음).
## - 정면에서 연속 block_limit(3)번 막으면 다음 한 대는 방패가 들려 맞고(흐트러짐 +block_break_poise), 잠깐 방패가 열린다.
## - 돌진이 박히면 stuck_time 동안 무방비, 풀린 뒤에도 charge_cooldown 동안 다음 공격을 못 한다.

@export_group("돌진")
@export var charge_speed := 700.0
@export var charge_time := 0.55
@export var charge_damage := 14.0
## 돌진이 벽·끝에 박혀 무방비로 있는 시간
@export var stuck_time := 2.4
## 공격할 때 돌진을 고를 확률 (나머지는 방패 치기)
@export var charge_chance := 0.35
## 박힘에서 풀린 뒤 다음 공격까지 쉬는 시간
@export var charge_cooldown := 1.2

@export_group("방패")
## 연속으로 막아 주는 횟수. 그다음 한 대는 방패가 들려 맞는다.
@export var block_limit := 3
## 마지막 막기 뒤 이 시간(초)이 지나면 막은 횟수가 0 으로 돌아간다.
@export var block_reset_time := 1.5
## 방패가 들려 맞을 때 더해지는 흐트러짐
@export var block_break_poise := 40.0
## 방패가 들린 뒤 막지 못하는 시간(초)
@export var block_open_time := 0.7

var _mode := ""          # "", "bash", "charge", "stuck"
var _charge_timer := 0.0
var _block_count := 0    # 연속으로 막은 횟수
var _block_reset := 0.0  # 막은 횟수가 돌아가기까지 남은 시간
var _block_open := 0.0   # 방패가 들려 있는 남은 시간
var _fx_t := 0.0         # 이펙트 리뉴얼 F2: 돌진 흙먼지 간격


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
	# 이펙트: 방패 치기 — 뼈대 방패 면 조금 앞 (그림이 모르면 예전 고정 자리)
	var bash_at := fx_point("weapon", global_position + Vector2(facing * 80.0, -hurt_height * 0.5)) + Vector2(facing * 20.0, 0.0)
	Fx.spawn("shield_bash", bash_at, {"facing": facing})


func _physics_process(delta: float) -> void:
	# 방패 횟수 시계
	_block_open = maxf(_block_open - delta, 0.0)
	if _block_reset > 0.0:
		_block_reset -= delta
		if _block_reset <= 0.0:
			_block_count = 0
	if state == State.STRIKE and _mode == "charge":
		_tick_common(delta)
		_charge_timer -= delta
		velocity.x = facing * charge_speed
		_fx_t -= delta
		if _fx_t <= 0.0:
			_fx_t = 0.06
			# 이펙트: 붉은 돌진 줄기 — 낮게 웅크린 몸통 높이 뒤로 끌린다
			var chest := fx_point("chest", global_position + Vector2(0.0, -hurt_height * 0.45))
			Fx.spawn("charge_dust", Vector2(global_position.x - facing * 30.0, chest.y), {"facing": facing})
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
			var stuck_at := fx_point("weapon", global_position + Vector2(facing * 90.0, -hurt_height * 0.45)) + Vector2(facing * 20.0, 0.0)
			Fx.spawn("slam_impact", stuck_at, {"scale": 1.2 if blocked else 0.8})   # 이펙트: 방패가 박힘 (뼈대 방패 면)
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
			_timer = charge_cooldown   # 박힘에서 빠져나온 뒤엔 한참 숨을 고른다
		return
	if _mode != "" and state in [State.IDLE, State.PATROL, State.ALERT, State.CHASE, State.HIT, State.BROKEN, State.DEAD]:
		_mode = ""
		anim_hint = ""
	super._physics_process(delta)


## 방패가 들려(막지 못하고) 열려 있는가 (그림이 읽는다 — 속 값 _block_open 을 직접 읽지 않게)
func is_block_open() -> bool:
	return _block_open > 0.0


## 방패를 들 수 있는 상태인가 (무방비·무너짐·피격·쓰러짐이 아님).
func _can_block() -> bool:
	return _mode != "stuck" and _block_open <= 0.0 and state in [State.IDLE, State.PATROL, State.ALERT, State.CHASE, State.LUNGE, State.WINDUP, State.BACKSTEP]


## 그림이 실제로 보는 방향 기준으로 공격이 앞에서 왔는가. 그림이 아직 돌아서는 중이면 앞이 없다(막지 못한다).
func _hit_from_front(hit: HitData) -> bool:
	if hit.source == null:
		return false
	var vis := get_node_or_null("Visual")
	var look := facing
	if vis and vis.has_method("is_facing_settled"):
		if not vis.is_facing_settled():
			return false
		look = vis.visible_facing()
	return (hit.source.global_position.x - global_position.x) * look > 0.0


## 확장판 · 벽 부수기(wall_break) 능력이 있으면 무거운 공격(씨앗 베기·낙하 공격, 흐트러짐 45 이상)은 방패를 깬다
## (막지 못하고 흐트러짐 +block_break_poise, 잠깐 방패가 열린다). EXPANSION.md 2장 "능력의 전투 활용".
## v1.1.0: 벽 부수기가 초반 능력이 되어 전투 효과는 끈다 — Balance.WALL_BREAK_COMBAT (false = 탐색 전용, D15).
const WALL_BREAK_POISE := 45.0


func _shield_breaker(hit: HitData) -> bool:
	return Balance.WALL_BREAK_COMBAT and hit.from_player and hit.poise >= WALL_BREAK_POISE and Progress.has_ability("wall_break")


## 정면 방패: 무방비·무너짐·피격이 아닐 때 앞에서 온 공격은 튕긴다. 연속 block_limit 번까지만.
func receive_hit(hit: HitData, hb: Hurtbox) -> String:
	var stuck := _mode == "stuck"
	if _can_block() and _hit_from_front(hit):
		if _block_count >= block_limit or _shield_breaker(hit):
			# 방패가 들렸다: 이번 한 대는 맞고 크게 흔들린다. 잠깐 방패가 열린다.
			_block_count = 0
			_block_reset = 0.0
			_block_open = block_open_time
			# Hitbox 는 한 휘두름에 닿은 모든 상대에게 같은 HitData 를 넘기므로 원본을 고치지 않고 복사해 쓴다
			var opened := hit.copy()
			opened.poise += block_break_poise
			Juice.hitstop(0.04, 0.1)
			return super.receive_hit(opened, hb)
		_block_count += 1
		_block_reset = block_reset_time
		_flash = 0.6
		Juice.hitstop(0.03, 0.1)
		# 방패로 막는 자세: 몸이 뒤로 살짝 밀리며 번쩍
		_visual_call("block", [-facing, clampf(hit.poise / 40.0, 0.6, 1.5)])
		return "blocked"
	if stuck:
		var doubled := hit.copy()
		doubled.poise *= 2.0
		return super.receive_hit(doubled, hb)
	return super.receive_hit(hit, hb)


## 박힌 동안은 맞아도 박힌 채로 남는다 (HIT 로 빠져나가면 stuck_time 무방비가 첫 타에 끝나 버린다).
## 흐트러짐이 가득 차면 EnemyBase 가 _break 로 무너뜨리므로 그 길은 그대로 열려 있다.
func _is_armored(hit: HitData) -> bool:
	if _mode == "stuck":
		return true
	return super._is_armored(hit)

extends CharacterBody2D
class_name EnemyBase
## 일반 적의 바탕. 순찰 → 발견 → 다가가기 → 예고 → 휘두르기 → 회복.
## 흐트러짐 게이지가 가득 차면 무너져(BROKEN) 정화의 손길을 받을 수 있다.
## 구원 불가능한 자는 정화되거나 쓰러지면 그 자리에 작은 묘목이 된다.

enum State { IDLE, PATROL, ALERT, CHASE, LUNGE, WINDUP, STRIKE, RECOVER, BACKSTEP, HIT, BROKEN, DEAD }

signal hp_changed(hp: float, max_hp: float)
signal poise_changed(poise: float, max_poise: float)
signal broke
signal recovered
signal died(purified: bool)
## 상태가 바뀔 때마다 (그림 쪽이 진입 1회 연출에 쓴다)
signal state_changed(old_state: State, new_state: State)

@export_group("능력치")
@export var max_hp := 70.0
@export var max_poise := 100.0
## 맞지 않을 때 초당 줄어드는 흐트러짐.
@export var poise_decay := 12.0
## 맞은 뒤 이 시간(초) 동안은 흐트러짐이 줄지 않는다.
@export var poise_hold := 2.0
@export var walk_speed := 220.0
@export var gravity := 2800.0
## 추격할 때 걷기 속도의 배수.
@export var chase_multiplier := 1.35
## 달려들기 거리(공격 거리보다 이만큼 멀면 달려든다)와 속도 배수.
@export var lunge_extra := 240.0
@export var lunge_multiplier := 2.4
## 공격 뒤 뒤로 빠질 확률.
@export var backstep_chance := 0.35
## 추격 중 소녀가 등 뒤로 갔을 때 돌아서기까지 걸리는 시간(초). 0 이면 바로 돈다.
## 방패를 든 경비병처럼 몸이 무거운 자는 늦게 돌아서서(0.45) 등 뒤가 빈틈이 된다. 도는 동안은 걷지 않고 멈칫한다.
@export var turn_delay := 0.0
## 쓰러질 때 떨어뜨리는 재화 '빛 가루' (±DUST_JITTER 흔들림, 2026-10-19 기획자 요청 9번). 정화의 손길로 쓰러지거나 구원되면
## DUST_PURIFY_BONUS 를 더 준다. 0 이면 안 떨어뜨린다 (중간 보스는 MiniBossRoom 이 0 으로 두고 따로 준다).
@export var dust_value := 10

const DUST_JITTER := 2
const DUST_PURIFY_BONUS := 20

@export_group("행동")
## 이 거리 안에 소녀가 오면 알아챈다.
@export var notice_range := 650.0
## 이 거리 안이면 공격한다.
@export var attack_range := 150.0
## 순찰 범위 (시작점 좌우).
@export var patrol_range := 300.0
@export var windup_time := 0.48
@export var strike_time := 0.12
@export var recover_time := 0.55
## 공격 뒤 다음 행동까지 쉬는 시간.
@export var cooldown := 0.25
@export var damage := 18.0
@export var hit_poise_to_player := 0.0
@export var knockback := Vector2(380, -150)
## 맞았을 때 멈칫하는 시간. 예고·휘두르기 중에는 흐트러짐이 작으면 멈칫하지 않는다.
@export var hit_stun := 0.18
## 무너진 채로 있는 시간. 그 안에 정화하지 않으면 일어난다.
@export var broken_time := 3.5
## 구원 가능한 자인가 (체력이 다하면 죽지 않고 무릎 꿇는다).
@export var savable := false
## 구원 가능한 자의 고유 이름 (data/dialogue/npcs.json 의 키). 구원하면 다시 나타나지 않는다.
@export var rescue_id := ""
## 이 깃발이 서 있으면 다시 나타나지 않는다 (중간 보스 등).
@export var defeat_flag := ""
## 공격 판정 영역 (바라보는 방향 기준).
@export var strike_box := Rect2(30, -90, 150, 110)
## 몸통 부딪힘 피해 (2026-10-19 기획자 요청 6번: 길목의 적을 그냥 뚫고 달려 지나가지 못하게).
## 소녀의 몸이 적의 몸통 가운데에 겹치면 이만큼 맞는다 (가드로 막을 수 있고, 구르기 무적이면 피한다). 0 이면 없음.
@export var contact_damage := 8.0
## 같은 적에게 다시 부딪혀 맞기까지의 간격(초)
@export var contact_interval := 1.0
@export var hurt_radius := 30.0
@export var hurt_height := 120.0

var state: State = State.IDLE
var hp := 70.0
var poise := 0.0
var facing := -1
var player: Player
var _timer := 0.0
var _poise_hold_timer := 0.0
var _origin := Vector2.ZERO
var _patrol_dir := 1
var _registered := false
var _flash := 0.0
## 돌아서려고 기다린 시간 (turn_delay 용)
var _turn_timer := 0.0
## 예고 진행도: WINDUP 중 0→1 (예고를 늘린 적도 실제 길이 기준으로 0에서 시작한다)
var windup_progress := 0.0
## 그림 쪽에 주는 힌트: "red"(가드 불가 예고) / "charge"(돌진) / "stuck"(박힘)
## 그 밖에 종류별: "shoot"(정원사 쏘기) / "scatter"(약초꾼 뿌리기) / "leap"·"fall"·"land"(거인 내려찍기) / "block"(경비병 막음)
var anim_hint := ""
## 지금 상태에 들어온 뒤 흐른 시간(초). 상태가 바뀌면 0.
var state_time := 0.0
## 지금 상태의 전체 길이(초). 상태에 들어선 첫 틱의 남은 시간으로 잡는다. 길이가 없는 상태(추격 등)는 0.
var phase_len := 0.0
## 지금 상태의 진행도 0→1 (길이가 있는 상태만; 없으면 0).
var phase_progress := 0.0
## 공격 단계 이름: "windup" / "strike" / "recover" / "" — 그림이 세 박자 곡선을 고를 때 쓴다.
var attack_phase := ""
## 쓰러지는 중인가 (DEAD 자세로 잠시 머문 뒤 사라진다)
var _dying := false
## 쓰러짐 연출이 끝나 묘목/사람을 만들고 사라졌는가 (한 번만)
var _fall_done := false
## 쓰러짐이 끝나면 구원(사람으로 돌아옴)인가, 묘목인가
var _fall_rescue := false
## 쓰러지기 전 발 위치 (묘목·구원 NPC 는 여기에 선다)
var _fall_at := Vector2.ZERO
var _fall_facing := 1
## 구원해 준 소녀 (감사 인사 대상)
var _fall_by: Player
## 마지막으로 맞은 방향(밀린 쪽, ±1). 쓰러질 때 이쪽으로 기울어진다.
var last_hit_dir := 1

@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox


signal rescued(id: String)


func _ready() -> void:
	add_to_group("enemy")
	if savable and rescue_id != "" and Progress.rescued.has(rescue_id):
		queue_free()   # 이미 구원했다
		return
	if defeat_flag != "" and Progress.has(defeat_flag):
		queue_free()
		return
	hp = max_hp
	_origin = global_position
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = hurt_radius
	capsule.height = hurt_height
	shape.shape = capsule
	hurtbox.add_child(shape)
	_timer = randf_range(0.3, 1.2)
	_make_contact_area()


## 몸통 부딪힘 판정: 맞는 영역보다 조금 작은 캡슐(가운데만). 소녀의 맞는 영역(층 4 = 8)과 겹치면 contact_damage.
var _contact: Area2D
var _contact_cd := 0.0


func _make_contact_area() -> void:
	if contact_damage <= 0.0:
		return
	_contact = Area2D.new()
	_contact.name = "ContactBox"
	_contact.collision_layer = 0
	_contact.collision_mask = 8
	_contact.monitorable = false
	var cs := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = hurt_radius * 0.7
	cap.height = maxf(hurt_height * 0.75, cap.radius * 2.0)
	cs.shape = cap
	_contact.position = hurtbox.position
	_contact.add_child(cs)
	add_child(_contact)


## 매 틱: 겹친 소녀에게 부딪힘 피해 (쓰러짐·무너짐·피격 경직·구원 중에는 없음)
func _tick_contact(delta: float) -> void:
	_contact_cd = maxf(_contact_cd - delta, 0.0)
	if _contact == null:
		return
	if state in [State.DEAD, State.BROKEN, State.HIT]:
		return
	for area in _contact.get_overlapping_areas():
		if area is Hurtbox and area.owner_node is Player:
			var pl := area.owner_node as Player
			# 낙하 공격으로 적을 맞히고 튕긴 직후(공중 + 착지 뒤 잠깐)는 부딪힘 없음: 튕겨 오른 소녀가 같은 적 몸으로 떨어져
			# '맞히고도 맞는' 일이 흔했다 (2026-10-19 검수). 그동안 몸 위에 내려선 소녀는 몸 바깥으로 살며시 밀어내
			# 유예가 끝났을 때 겹친 채로 남지 않게 한다 (손을 떼고 있어도). 스틱을 누르고 있으면 소녀 쪽 움직임이 이긴다.
			if pl.has_method("has_contact_grace") and pl.has_contact_grace():
				if pl.is_on_floor() and pl.state in Player.LOCOMOTION and absf(Input.get_axis("move_left", "move_right")) < 0.05:
					var dir := signf(pl.global_position.x - global_position.x)
					if dir == 0.0:
						dir = -float(facing)
					pl.velocity.x = dir * 320.0
				return
			if _contact_cd > 0.0:
				return
			var dmg := contact_damage * float(get("elite_damage_mult") if get("elite_damage_mult") != null else 1.0)
			# 밀림 520: 피격 감속(1600) 아래에서도 약 85px 밀려 겹침(약 46px)을 확실히 벗어난다 (340 은 36px 라 1초 뒤 또 맞았다)
			var hit := HitData.make(dmg, 0.0, self, Vector2(520, -180))
			hit.hitstop = 0.03
			hit.parryable = false
			var result: String = area.receive(hit)
			if result != "ignored":
				_contact_cd = contact_interval
			return


## 모든 상태가 공통으로 매 틱 하는 일: 번쩍임 감쇠, 흐트러짐 회복, 남은 시간 줄이기, 진행도 계산.
## 종류별 스크립트가 _physics_process 를 가로채는 분기에서도 반드시 이걸 부른다 (그림이 진행도를 읽는다).
func _tick_common(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player
	_tick_contact(delta)
	_flash = maxf(_flash - delta * 8.0, 0.0)
	_poise_hold_timer = maxf(_poise_hold_timer - delta, 0.0)
	if state != State.BROKEN and state != State.DEAD and _poise_hold_timer <= 0.0 and poise > 0.0:
		poise = maxf(poise - poise_decay * delta, 0.0)
		poise_changed.emit(poise, max_poise)
	# 상태 길이는 들어선 뒤 첫 틱의 남은 시간으로 잡는다 (하위 스크립트가 _timer 를 늘려도 그 값이 잡힌다)
	if _timer > phase_len and _timer != INF:
		phase_len = _timer
	_timer -= delta
	state_time += delta
	if phase_len > 0.0 and phase_len != INF:
		phase_progress = clampf(1.0 - _timer / phase_len, 0.0, 1.0)
	else:
		phase_progress = 0.0
	match state:
		State.WINDUP:
			attack_phase = "windup"
			windup_progress = phase_progress
		State.STRIKE:
			attack_phase = "strike"
		State.RECOVER:
			attack_phase = "recover"
		_:
			attack_phase = ""


func _physics_process(delta: float) -> void:
	_tick_common(delta)
	if not is_on_floor():
		velocity.y += gravity * delta

	match state:
		State.IDLE:
			velocity.x = move_toward(velocity.x, 0.0, 1200.0 * delta)
			if _sees_player():
				_alert()
			elif _timer <= 0.0:
				_patrol_dir = -_patrol_dir
				facing = _patrol_dir
				_set_state(State.PATROL)
				_timer = randf_range(1.2, 2.5)
		State.PATROL:
			if _sees_player():
				_alert()
			else:
				var dir := _patrol_dir
				if absf(global_position.x + dir * 20.0 - _origin.x) > patrol_range or not _can_walk(dir):
					_set_state(State.IDLE)
					_timer = randf_range(0.6, 1.5)
				else:
					facing = dir
					velocity.x = move_toward(velocity.x, dir * walk_speed * 0.7, 1400.0 * delta)
				if _timer <= 0.0:
					_set_state(State.IDLE)
					_timer = randf_range(0.6, 1.5)
		State.ALERT:
			velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
			if turn_delay > 0.0:
				_turn_toward_player(delta)   # 늦게 도는 자는 발견 순간에도 바로 돌지 않고 여기서부터 기다린다
			if _timer <= 0.0 and is_on_floor():
				_set_state(State.CHASE)
				_timer = 0.1
		State.CHASE:
			if player == null or not _sees_player(notice_range * 1.5):
				_set_state(State.IDLE)
				_timer = 0.8
			else:
				var dx := player.global_position.x - global_position.x
				var want := _turn_toward_player(delta)
				var close_y := absf(player.global_position.y - global_position.y) < 140.0
				if facing != want:
					# 아직 돌아서는 중(turn_delay): 등을 보인 채 멈칫한다 (걷지도 공격하지도 않는다)
					velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
				elif absf(dx) <= attack_range and close_y and _timer <= 0.0:
					_begin_windup()
				elif absf(dx) <= attack_range + lunge_extra and absf(dx) > attack_range * 0.9 and close_y and _timer <= 0.0 and _can_walk(facing) and randf() < 0.04:
					_set_state(State.LUNGE)
					_timer = 0.22
				elif absf(dx) > attack_range * 0.7 and _can_walk(facing):
					velocity.x = move_toward(velocity.x, facing * walk_speed * chase_multiplier, 2200.0 * delta)
				else:
					velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
		State.LUNGE:
			velocity.x = facing * walk_speed * lunge_multiplier
			if not _can_walk(facing) or _timer <= 0.0:
				velocity.x *= 0.3
				# 달려든 끝에 소녀가 아직 **앞**에 있을 때만 예고로 (달려드는 사이 등 뒤로 빠졌으면 등진 채 휘두르지 않고 다시 쫓는다)
				var ldx := player.global_position.x - global_position.x if player else 0.0
				if player and absf(ldx) <= attack_range * 1.2 and ldx * facing >= 0.0:
					_begin_windup()
				else:
					_set_state(State.CHASE)
					_timer = 0.15
		State.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, 2400.0 * delta)
			if _timer <= 0.0:
				_strike()
		State.STRIKE:
			velocity.x = move_toward(velocity.x, facing * 160.0, 3000.0 * delta)
			if _timer <= 0.0:
				_set_state(State.RECOVER)
				_timer = recover_time
		State.RECOVER:
			velocity.x = move_toward(velocity.x, 0.0, 1500.0 * delta)
			if _timer <= 0.0:
				if randf() < backstep_chance and _can_walk(-facing):
					_set_state(State.BACKSTEP)
					_timer = 0.28
				else:
					_set_state(State.CHASE)
					_timer = cooldown
		State.BACKSTEP:
			velocity.x = -facing * walk_speed * 1.4
			if _timer <= 0.0 or not _can_walk(-facing):
				_set_state(State.CHASE)
				_timer = cooldown * 0.5
		State.HIT:
			velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
			if turn_delay > 0.0 and player:
				_turn_toward_player(delta)   # 맞는 동안에도 '등 뒤에 있은 시간'은 계속 흐른다 (피격 뒤 더 빨리·더 늦게 돌지 않게)
			if _timer <= 0.0:
				_set_state(State.CHASE)
				_timer = 0.1
		State.BROKEN:
			velocity.x = move_toward(velocity.x, 0.0, 1400.0 * delta)
			_update_interactable()
			if not savable and _timer <= 0.0:
				_unregister()
				poise = 0.0
				poise_changed.emit(poise, max_poise)
				_set_state(State.RECOVER)
				_timer = 0.4
				recovered.emit()
		State.DEAD:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			# 쓰러짐 연출이 끝나면 (타이머가 아니라 상태 기계라 일시정지 중엔 멈추고, 방을 떠나면 그냥 함께 사라진다)
			if _dying and not _fall_done and _timer <= 0.0:
				_fall_done = true
				_finish_fall()
	move_and_slide()


## 방에 막 들어선 소녀를 알아채지 않는 시각 (Time.get_ticks_msec 초). Room 이 포탈·달빛풀로 들어설 때 정한다.
## 화면이 어둠에서 밝아지는 동안 길목 적이 먼저 달려와 때리던 '도착 매복'을 없앤다 (2026-10-19 검수).
static var arrival_grace_until := 0.0


static func arrival_grace_active() -> bool:
	return float(Engine.get_physics_frames()) < arrival_grace_until   # 단위: 물리 틱 번호 (Room 이 정한다)


func _sees_player(range_px := -1.0) -> bool:
	if player == null or player.state == Player.State.DEAD:
		return false
	if arrival_grace_active() and state in [State.IDLE, State.PATROL]:
		return false
	var r := notice_range if range_px < 0.0 else range_px
	var d := player.global_position - global_position
	return absf(d.x) <= r and absf(d.y) <= 260.0


## 앞에 바닥이 있고 벽이 없는가.
func _can_walk(dir: int) -> bool:
	var space := get_world_2d().direct_space_state
	var from := global_position + Vector2(dir * 48.0, 0)
	var ray := PhysicsRayQueryParameters2D.create(from, from + Vector2(0, hurt_height * 0.5 + 60.0), 1)
	if space.intersect_ray(ray).is_empty():
		return false
	var wall := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(dir * 60.0, 0), 1)
	return space.intersect_ray(wall).is_empty()


## 소녀 쪽으로 돌아선다 (매 틱 부른다). 돌려주는 값은 소녀가 있는 쪽(±1).
## turn_delay 가 0 이면 바로 돈다. 아니면 소녀가 등 뒤에 그 시간 동안 **이어서** 있어야 돈다:
##  - 이미 그쪽을 보고 있으면 기다린 시간은 0 으로 뚝 끊기지 않고 절반 속도로 식는다
##    (좌우를 turn_delay 보다 빠르게 번갈아 넘나들어도 결국 돌아선다 — 영영 굳는 일 없음).
##  - 소녀가 몸에 겹쳐 있으면(등 뒤라고 할 수 없음) 바로 돈다.
func _turn_toward_player(delta: float) -> int:
	if player == null:
		return facing
	var dx := player.global_position.x - global_position.x
	var want := 1 if dx > 0.0 else -1
	if want == facing:
		_turn_timer = maxf(_turn_timer - delta * 0.5, 0.0)
		return want
	if turn_delay <= 0.0 or absf(dx) < hurt_radius * 1.5:
		facing = want
		_turn_timer = 0.0
		return want
	_turn_timer = minf(_turn_timer + delta, turn_delay)
	if _turn_timer >= turn_delay:
		facing = want
		_turn_timer = 0.0
	return want


## 발견: 펄쩍 뛰며 경계한다. 늦게 도는 자(turn_delay > 0)는 여기서도 바로 돌지 않는다 (등 뒤에서 다가가면 그만큼 빈틈).
func _alert() -> void:
	_turn_timer = 0.0
	if player and turn_delay <= 0.0:
		facing = 1 if player.global_position.x > global_position.x else -1
	velocity.y = -420.0
	velocity.x = 0.0
	_set_state(State.ALERT)
	_timer = 0.3


func _begin_windup() -> void:
	_set_state(State.WINDUP)
	_timer = windup_time
	windup_progress = 0.0


func _strike() -> void:
	_set_state(State.STRIKE)
	_timer = strike_time
	var hit := HitData.make(damage, hit_poise_to_player, self, knockback)
	hitbox.set_box(strike_box, facing)
	hitbox.activate(hit, strike_time)


## 소녀의 공격이 닿았다.
func receive_hit(hit: HitData, _hurtbox: Hurtbox) -> String:
	if state == State.DEAD:
		return "ignored"
	_flash = 1.0
	hp = maxf(hp - hit.damage, 0.0)
	hp_changed.emit(hp, max_hp)
	_add_poise(hit.poise)
	var dir := 1
	if hit.source:
		dir = 1 if global_position.x >= hit.source.global_position.x else -1
	last_hit_dir = dir
	velocity.x = dir * absf(hit.knockback.x) * 0.5
	# 그림에 충격을 전한다 (맞은 프레임에 튕기고 스프링으로 되돌아온다)
	_visual_call("kick", [dir, clampf(hit.poise / 40.0, 0.5, 1.6)])
	if hp <= 0.0:
		if savable:
			_break(true)
		else:
			_die(false)
		return "hit"
	if state == State.BROKEN:
		return "hit"
	if poise >= max_poise:
		_break(false)
		return "hit"
	if not _is_armored(hit):
		hitbox.deactivate()
		_set_state(State.HIT)
		_timer = hit_stun
	return "hit"


## 이 공격에 멈칫(HIT)하지 않는가. 예고·휘두르기 중에는 작은 공격으로 멈칫하지 않는다 (단단함).
## 종류별 스크립트가 덧붙인다 (경비병: 박힌 동안은 맞아도 박힌 채로 남는다).
func _is_armored(hit: HitData) -> bool:
	return state in [State.WINDUP, State.STRIKE, State.LUNGE] and hit.poise < 30.0


## 소녀가 저스트 가드로 받아냈다.
func on_just_guarded(_by: Player, amount: float) -> void:
	_flash = 1.0
	_add_poise(amount)
	if poise >= max_poise:
		_break(false)
		return
	# 받아친 뒤 크게 휘청인다 (칼은 되튕겨 올라오고 몸은 뒤로)
	hitbox.deactivate()
	velocity.x = -facing * 220.0
	_visual_call("parried", [-facing, 1.4])
	_set_state(State.RECOVER)
	_timer = recover_time + 0.4


func _add_poise(amount: float) -> void:
	poise = minf(poise + amount, max_poise)
	_poise_hold_timer = poise_hold
	poise_changed.emit(poise, max_poise)


func _break(permanent: bool) -> void:
	hitbox.deactivate()
	Sfx.play("broke", -3.0)
	_set_state(State.BROKEN)
	_timer = INF if permanent else broken_time
	broke.emit()


func _update_interactable() -> void:
	if player == null:
		return
	var near := global_position.distance_to(player.global_position) < 170.0
	if near and not _registered:
		player.register_interactable(self)
		_registered = true
	elif not near and _registered:
		_unregister()


func _unregister() -> void:
	if _registered and player:
		player.unregister_interactable(self)
	_registered = false


## 소녀가 △를 눌렀다.
func interact(by: Player) -> void:
	if state == State.BROKEN:
		by.start_purify(self)


## 정화의 손길을 받았다.
func purified_by(by: Player) -> void:
	if savable:
		_rescue(by)
	else:
		_die(true)


## 구원: 사람으로 돌아온다. 감사의 말과 보상은 RescuedPerson 이 맡는다.
## 깃발·신호는 지금 바로 세우고, 그림은 빛으로 흩어지는 짧은 연출(0.5초) 뒤 사람으로 바뀐다.
func _rescue(by: Player) -> void:
	if _dying:
		return
	_fall_rescue = true
	_fall_by = by
	_begin_fall(true, 0.5)
	_drop_dust(true)
	if rescue_id != "":
		Progress.rescued[rescue_id] = true
		Progress.set_flag(rescue_id + "_rescued")
	rescued.emit(rescue_id)


## 쓰러짐: 신호는 지금 바로, 그림은 0.75초 동안 쓰러지는 자세로 가라앉은 뒤 묘목이 된다.
func _die(purified: bool) -> void:
	if _dying:
		return
	_fall_rescue = false
	_begin_fall(purified, 0.75)
	_drop_dust(purified)
	died.emit(purified)


## 떨어뜨릴 빛 가루 양 (정화·구원이면 보너스 포함). dust_value 가 0 이면 0.
func dust_amount(purified: bool) -> int:
	if dust_value <= 0:
		return 0
	var n := dust_value + randi_range(-DUST_JITTER, DUST_JITTER)
	if purified:
		n += DUST_PURIFY_BONUS
	return maxi(n, 1)


## 빛 가루를 몸에서 흩뿌린다 (Dust.burst). 소녀가 없는 시험 공간에서는 떨어뜨리지 않는다 (주울 이가 없다).
func _drop_dust(purified: bool) -> void:
	if player == null or not is_instance_valid(player):
		return
	var n := dust_amount(purified)
	if n <= 0:
		return
	Dust.burst(get_parent(), global_position + Vector2(0, -hurt_height * 0.25), n, player)


## 쓰러지기 시작: 판정을 끄고 DEAD 자세로 들어간다. 더는 맞지도, 소녀를 막지도 않는다 (땅에는 그대로 선다).
## 끝나는 시점은 _physics_process 의 DEAD 분기가 _timer 로 잰다 (일시정지 중엔 함께 멈춘다).
func _begin_fall(gentle: bool, duration: float) -> void:
	_dying = true
	_fall_done = false
	_fall_at = global_position + Vector2(0, hurt_height * 0.5)
	_fall_facing = facing
	_unregister()
	hitbox.deactivate()
	hurtbox.set_deferred("monitorable", false)
	collision_layer = 0
	remove_from_group("enemy")
	_set_state(State.DEAD)
	_timer = duration
	_visual_call("fall", [last_hit_dir, gentle])


## 쓰러짐 연출이 끝났다: 구원이면 사람(RescuedPerson)으로, 아니면 묘목으로 바뀌고 사라진다.
func _finish_fall() -> void:
	if _fall_rescue:
		var vis := get_node_or_null("Visual")
		var scene: PackedScene = load("res://scenes/npcs/rescued_person.tscn")
		if scene:
			var npc := scene.instantiate()
			npc.rescue_id = rescue_id
			if vis and vis.has_method("npc_look"):
				# 부위 뼈대 그림(EnemyRigVisual): 사람으로 돌아온 모습도 같은 뼈대로 (없으면 그림 한 장)
				var look: Dictionary = vis.npc_look()
				npc.texture = look.get("texture")
				npc.art_faces_right = bool(look.get("art_faces_right", true))
				npc.art_scale = float(look.get("art_scale", 0.17))
				npc.rig_id = str(look.get("rig", ""))
				npc.rig_scale = float(look.get("rig_scale", 1.0))
			else:
				npc.texture = vis.get("texture") if vis else null
				npc.art_faces_right = vis.get("art_faces_right") if vis else true
				npc.art_scale = vis.get("art_scale") if vis else 0.17
			npc.facing = -_fall_facing
			npc.global_position = _fall_at
			if vis and vis.has_method("npc_look"):
				# 뼈대 사람은 원점이 발바닥이다 → 몸 충돌(캡슐)의 바닥에 세운다 (hurt_height 절반은 캡슐 바닥보다 5px 아래라
				# 무릎 꿇은 몹이 사람으로 바뀌는 순간 땅속으로 툭 떨어졌다 — 2026-10-20 검수)
				npc.global_position.y = _fall_at.y - hurt_height * 0.5 + float(vis.npc_look().get("floor_y", hurt_height * 0.5))
			get_parent().add_child(npc)
			if is_instance_valid(_fall_by):
				npc.greet(_fall_by)
	else:
		_spawn_sprout(_fall_at)
	queue_free()


func _spawn_sprout(at: Vector2) -> void:
	var sprout_scene: PackedScene = load("res://scenes/world/sprout.tscn")
	if sprout_scene:
		var s := sprout_scene.instantiate()
		s.global_position = at
		get_parent().add_child(s)


## 그림(Visual)에 메서드가 있으면 부른다 (충격·반동 같은 1회 연출).
func _visual_call(method: String, args: Array = []) -> void:
	var vis := get_node_or_null("Visual")
	if vis and vis.has_method(method):
		vis.callv(method, args)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	state_time = 0.0
	phase_len = 0.0
	phase_progress = 0.0
	state_changed.emit(old, new_state)


func flash_amount() -> float:
	return _flash


## 지금 상태의 남은 시간 (읽기만 — 그림이 폴짝 웅크림 같은 때를 맞출 때. 속 값 _timer 를 직접 읽지 않게)
func state_timer() -> float:
	return _timer


func state_name() -> String:
	match state:
		State.IDLE: return "대기"
		State.PATROL: return "순찰"
		State.ALERT: return "발견"
		State.CHASE: return "추격"
		State.LUNGE: return "달려듦"
		State.BACKSTEP: return "뒤로 빠짐"
		State.WINDUP: return "예고"
		State.STRIKE: return "휘두름"
		State.RECOVER: return "회복"
		State.HIT: return "피격"
		State.BROKEN: return "무너짐"
		State.DEAD: return "쓰러짐"
	return "?"

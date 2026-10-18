extends CharacterBody2D
class_name Player
## 셀레니아. 이동·점프·구르기(3단계) + 전투(5단계).
## 손맛에 관한 숫자는 모두 아래 @export 에 모여 있다. 느낌 피드백이 오면 여기만 고친다.

enum State { IDLE, WALK, RUN, JUMP, FALL, ROLL, ATTACK, HEAVY_CHARGE, HEAVY_SWING, GUARD, HIT, HEAL, PURIFY, REST, DEAD }
const LOCOMOTION := [State.IDLE, State.WALK, State.RUN, State.JUMP, State.FALL]

signal state_changed(new_state: State)
signal jumped(air_jump: bool)
signal landed(fall_speed: float)
signal roll_started
signal hp_changed(hp: float, max_hp: float)
signal guard_changed(guard: float, max_guard: float)
signal dews_changed(dews: int)
signal attacked(step: int, heavy: bool)
signal just_guarded(source: Node)
signal guard_broken
signal hit_taken(damage: float)
signal healed
signal purify_started(target: Node)
signal purified(target: Node)
signal rest_started(grass: Node)
signal rest_ended
signal died
signal interactables_changed(can_interact: bool)
signal gust_cast
signal soul_changed(soul: String)
signal blocked

@export_group("걷기와 달리기")
## 걷는 속도 (픽셀/초). 화면 기준 1920×1080.
@export var walk_speed := 380.0
## 달리는 속도. 회피 버튼을 길게 누르고 있으면 달린다.
@export var run_speed := 640.0
## 땅에서 속도가 붙는 빠르기. 클수록 즉각 반응.
@export var ground_accel := 4200.0
## 땅에서 멈추는 빠르기.
@export var ground_decel := 5400.0
## 공중에서 방향을 바꾸는 빠르기 (땅보다 조금 둔하게).
@export var air_accel := 2800.0
## 회피 버튼을 이 시간(초) 넘게 누르고 있으면 구르기 대신 달리기.
@export var run_hold_time := 0.2

@export_group("점프")
## 점프 최고 높이 (픽셀). 소녀 키가 약 110.
@export var jump_height := 260.0
## 최고점까지 걸리는 시간 (초). 짧을수록 가볍고 빠른 점프.
@export var jump_time_to_apex := 0.4
## 떨어질 때 중력 배수. 1보다 크면 올라갈 때보다 빨리 떨어져 경쾌하다.
@export var fall_gravity_multiplier := 1.7
## 점프 버튼을 일찍 떼면 상승 속도를 이 비율로 줄인다 (짧은 점프).
@export var jump_cut_multiplier := 0.4
## 최대 낙하 속도.
@export var max_fall_speed := 1900.0
## 발판 끝에서 떨어진 뒤에도 이 시간(초) 안에는 점프할 수 있다 (코요테 타임).
@export var coyote_time := 0.1
## 땅에 닿기 직전에 누른 점프를 이 시간(초) 동안 기억한다.
@export var jump_buffer_time := 0.12
## 점프 횟수. 이단 점프를 얻으면 2.
@export var max_jumps := 1

@export_group("구르기")
## 구르는 속도.
@export var roll_speed := 980.0
## 구르는 시간 (초). 거리 = 속도 × 시간.
@export var roll_duration := 0.3
## 구르기 뒤 다시 구를 수 있기까지의 간격 (초).
@export var roll_cooldown := 0.1
## 구르기 시간 중 앞부분 이 비율 동안은 무적.
@export var roll_invuln_ratio := 0.7

@export_group("체력과 회복")
@export var max_hp := 100.0
## 이슬 방울 개수 (달빛풀에서 다시 채워진다).
@export var max_dews := 3
@export var heal_amount := 45.0
## 회복 동작에 걸리는 시간. 그동안 움직일 수 없고 맞으면 끊긴다.
@export var heal_time := 0.7

@export_group("약공격 (3연타)")
@export var light_damage := [12.0, 12.0, 18.0]
@export var light_poise := [20.0, 20.0, 32.0]
@export var light_startup := 0.07
@export var light_active := 0.1
@export var light_recovery := 0.2
## 공격하며 앞으로 살짝 나아가는 속도.
@export var light_lunge := 180.0

@export_group("강공격 (길게 차지)")
## 이 시간(초)까지 차지하면 최대.
@export var heavy_max_charge := 0.9
@export var heavy_damage := 26.0
@export var heavy_damage_charged := 52.0
@export var heavy_poise := 35.0
@export var heavy_poise_charged := 85.0
@export var heavy_startup := 0.14
@export var heavy_active := 0.14
@export var heavy_recovery := 0.45

@export_group("가드와 저스트 가드")
@export var max_guard := 100.0
## 가드 중 받는 피해 비율 (0.15 = 85% 줄임).
@export var guard_damage_ratio := 0.15
## 막은 피해 1당 깎이는 가드 게이지.
@export var guard_drain_ratio := 1.3
## 가드를 하지 않을 때 초당 회복되는 가드 게이지.
@export var guard_regen := 28.0
## 가드 버튼을 누른 뒤 이 시간(초) 안에 맞으면 저스트 가드.
## 저스트 가드 판정 (가드를 누른 뒤 이 시간 안에 맞으면). 0.15 → 0.24 로 후하게 (2026-10-18 기획자 요청).
@export var just_guard_window := 0.24
## 가드를 뗀 뒤 다시 가드할 수 있기까지 (연타 방지).
@export var guard_relock_time := 0.2
## 가드가 깨졌을 때 무방비 시간.
@export var guard_break_stun := 1.0
## 가드 중 걷는 속도 비율.
@export var guard_move_ratio := 0.4
## 저스트 가드가 적에게 주는 흐트러짐.
@export var just_guard_poise := 45.0

@export_group("바람 공격 (영혼 능력)")
@export var gust_damage := 14.0
@export var gust_poise := 24.0
@export var gust_speed := 760.0
@export var gust_range_time := 0.5
@export var gust_cooldown := 1.1

@export_group("빛 공격 (등불 기사의 영혼)")
@export var light_shot_damage := 22.0
@export var light_shot_poise := 30.0
@export var light_shot_speed := 1100.0
@export var light_shot_time := 0.7
@export var light_shot_cooldown := 0.9

@export_group("피격")
@export var hit_stun := 0.3
## 맞은 뒤 무적 시간.
@export var invuln_time := 0.7

var state: State = State.IDLE
## 바라보는 방향. 1 = 오른쪽, -1 = 왼쪽.
var facing := 1
var is_running := false
## 걷기 고정 (터치의 걷기 버튼, 컨트롤러 L3). 달리기가 기본이고, 켜면 이동이 걷기가 된다 (2026-10-18 기획자 결정).
## 걷는 중에도 회피 버튼을 길게 누르면 그동안은 달린다.
var walk_locked := false
var hp := 100.0
var guard := 100.0
var dews := 3
## 지금 상호작용(쉬기·정화)할 수 있는 대상들.
var interactables: Array = []
var can_interact: bool:
	get: return not interactables.is_empty()
## 자동 시험이나 터치 조작이 아닌, 실제 입력을 잠시 막을 때.
var input_enabled := true
## 공격 단계 (1~3), 공격 국면 ("startup" / "active" / "recovery")
var attack_step := 0
var attack_phase := ""
var charge := 0.0
var purify_target: Node2D

var _dodge_running := false
var _jump_gravity := 0.0
var _jump_velocity := 0.0
var _coyote_timer := 0.0
var _buffer_timer := 0.0
var _jumps_left := 0
var _roll_timer := 0.0
var _roll_cooldown_timer := 0.0
var _dodge_hold := 0.0
var _dodge_held := false
var _was_on_floor := false
var _last_fall_speed := 0.0
var _attack_timer := 0.0
var _attack_buffered := false
var _guard_pressed_at := -1000.0
var _guard_released_at := -1000.0
var _hit_timer := 0.0
var _invuln_timer := 0.0
var _heal_timer := 0.0
var _guard_regen_delay := 0.0
var _gust_cooldown := 0.0
var _interact_buffer := 0.0
var _light: PointLight2D
## 포자 구름 등으로 느려진 비율 (1 = 정상). 매 프레임 되돌아온다.
var slow_factor := 1.0
## 지금 고른 영혼: "wind" / "light"
var soul := ""
## 마지막으로 안전하게 서 있던 자리 (가시에 떨어지면 여기로 돌아온다).
var last_safe_position := Vector2.ZERO
var _safe_timer := 0.0
## 성장: 공격 배수 (구원한 사람의 보상 등)
var attack_multiplier := 1.0
var _wind := 0.0   # 이번 물리 프레임에 받는 바람 (픽셀/초²)

const PROJECTILE := preload("res://scenes/combat/projectile.tscn")

@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox


func _ready() -> void:
	_recalculate_jump()
	hp = max_hp
	guard = max_guard
	dews = max_dews
	hitbox.landed.connect(_on_hit_landed)
	add_to_group("player")
	_apply_abilities()
	Progress.ability_gained.connect(func(_a): _apply_abilities())
	_apply_settings()
	Settings.changed.connect(_apply_settings)
	# 효과음
	jumped.connect(func(_air): Sfx.play("jump"))
	landed.connect(func(v): if v > 300.0: Sfx.play("land", -6.0 + clampf(v / 400.0, 0.0, 6.0)))
	roll_started.connect(func(): Sfx.play("roll", -4.0))
	attacked.connect(func(_s, heavy): Sfx.play("swing", -2.0 if heavy else -6.0, 0.1))
	just_guarded.connect(func(_s): Sfx.play("just_guard", 2.0, 0.02))
	guard_broken.connect(func(): Sfx.play("guard_break"))
	hit_taken.connect(func(_d): Sfx.play("hurt", -2.0))
	healed.connect(func(): Sfx.play("heal", -4.0))
	purify_started.connect(func(_t): Sfx.play("purify", -2.0, 0.0))
	gust_cast.connect(func(): Sfx.play("gust", -6.0))
	soul_changed.connect(func(_s): Sfx.play("select", -4.0))
	rest_started.connect(func(_g): Sfx.play("bloom", -6.0, 0.0))
	died.connect(func(): Sfx.play("boss_fall", -4.0))


var _base_just_guard_window := -1.0
func _apply_settings() -> void:
	if _base_just_guard_window < 0.0:
		_base_just_guard_window = just_guard_window
	just_guard_window = _base_just_guard_window * (1.5 if Settings.get_value("lenient_guard") else 1.0)


func _apply_abilities() -> void:
	max_jumps = 2 if Progress.has_ability("double_jump") else 1
	var owned := owned_souls()
	if soul == "" or not owned.has(soul):
		soul = owned[-1] if not owned.is_empty() else ""
	if _light:
		_light.texture_scale = 3.6 if Progress.has_ability("lantern") else 1.0
		_light.energy = 2.4 if Progress.has_ability("lantern") else 0.9
	# 성장 보상 (Progress.upgrades)
	var old_max := max_hp
	max_hp = 100.0 + Progress.upgrades.get("max_hp", 0.0)
	if max_hp != old_max:
		hp = minf(hp + (max_hp - old_max), max_hp)
	attack_multiplier = 1.0 + Progress.upgrades.get("attack", 0.0)
	max_dews = 3 + int(Progress.upgrades.get("dews", 0))
	dews = mini(dews, max_dews)
	hp_changed.emit(hp, max_hp)
	dews_changed.emit(dews)


## 점프 높이와 시간으로 중력과 초기 속도를 계산한다.
func _recalculate_jump() -> void:
	_jump_gravity = 2.0 * jump_height / (jump_time_to_apex * jump_time_to_apex)
	_jump_velocity = _jump_gravity * jump_time_to_apex


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	_tick_timers(delta, on_floor)

	match state:
		State.DEAD, State.PURIFY, State.REST:
			_apply_gravity(delta, on_floor)
			velocity.x = move_toward(velocity.x, 0.0, ground_decel * delta)
			move_and_slide()
			if state == State.REST and input_enabled and _wants_to_leave_rest():
				_set_state(State.IDLE)
				rest_ended.emit()
			return
		State.HIT:
			_apply_gravity(delta, on_floor)
			velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
			move_and_slide()
			if _hit_timer <= 0.0:
				_set_state(State.IDLE)
			return
		State.HEAL:
			_apply_gravity(delta, on_floor)
			velocity.x = move_toward(velocity.x, 0.0, ground_decel * delta)
			move_and_slide()
			if _heal_timer <= 0.0:
				hp = minf(hp + heal_amount, max_hp)
				hp_changed.emit(hp, max_hp)
				healed.emit()
				_set_state(State.IDLE)
			return

	var move_input := Input.get_axis("move_left", "move_right") if input_enabled else 0.0

	_handle_dodge_and_run(delta, on_floor)
	_handle_guard(on_floor)
	_handle_attacks(delta, on_floor)
	_handle_heal(on_floor)
	_handle_interact()
	_handle_gust(on_floor)
	_apply_gravity(delta, on_floor)
	_handle_jump(on_floor)
	_handle_horizontal(delta, on_floor, move_input)
	# 날갯바람: 구르는 중에는 덜 밀린다
	if _wind != 0.0:
		velocity.x += _wind * (0.35 if state == State.ROLL else 1.0) * delta
		_wind = 0.0

	_last_fall_speed = velocity.y
	move_and_slide()
	slow_factor = 1.0

	if is_on_floor() and not _was_on_floor and state != State.ROLL:
		landed.emit(_last_fall_speed)
	_was_on_floor = is_on_floor()
	_resolve_locomotion_state()
	# 안전한 자리 기억 (땅에 서 있고, 조금 지난 뒤)
	if is_on_floor() and _invuln_timer <= 0.0:
		_safe_timer += delta
		if _safe_timer > 0.35:
			last_safe_position = global_position
	else:
		_safe_timer = 0.0


func _tick_timers(delta: float, on_floor: bool) -> void:
	if on_floor:
		_coyote_timer = coyote_time
		_jumps_left = max_jumps
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
	_buffer_timer = maxf(_buffer_timer - delta, 0.0)
	_roll_cooldown_timer = maxf(_roll_cooldown_timer - delta, 0.0)
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	_invuln_timer = maxf(_invuln_timer - delta, 0.0)
	_heal_timer = maxf(_heal_timer - delta, 0.0)
	_guard_regen_delay = maxf(_guard_regen_delay - delta, 0.0)
	_gust_cooldown = maxf(_gust_cooldown - delta, 0.0)
	_interact_buffer = maxf(_interact_buffer - delta, 0.0)
	if state != State.GUARD and _guard_regen_delay <= 0.0 and guard < max_guard:
		guard = minf(guard + guard_regen * delta, max_guard)
		guard_changed.emit(guard, max_guard)


func _apply_gravity(delta: float, on_floor: bool) -> void:
	var gravity := _jump_gravity
	if velocity.y > 0.0:
		gravity *= fall_gravity_multiplier
	elif velocity.y < 0.0 and state == State.JUMP and input_enabled and Input.is_action_just_released("jump"):
		# 버튼을 일찍 뗐다: 상승 속도를 한 번만 줄여 짧은 점프로
		velocity.y *= jump_cut_multiplier
	if not on_floor:
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _handle_dodge_and_run(delta: float, on_floor: bool) -> void:
	if input_enabled:
		if Input.is_action_just_pressed("dodge"):
			_dodge_held = true
			_dodge_hold = 0.0
		if _dodge_held and Input.is_action_pressed("dodge"):
			_dodge_hold += delta
			if _dodge_hold >= run_hold_time:
				_dodge_running = true
		if _dodge_held and not Input.is_action_pressed("dodge"):
			_dodge_held = false
			if _dodge_hold < run_hold_time:
				_try_roll(on_floor)
			_dodge_running = false
		if Input.is_action_just_pressed("run_toggle"):
			walk_locked = not walk_locked
		if Input.is_action_just_pressed("jump"):
			_buffer_timer = jump_buffer_time
	is_running = _dodge_running or not walk_locked

	if state == State.ROLL:
		_roll_timer -= delta
		if _roll_timer <= 0.0:
			_roll_cooldown_timer = roll_cooldown
			_set_state(State.IDLE)


func _handle_guard(on_floor: bool) -> void:
	if not input_enabled:
		return
	var pressed := Input.is_action_pressed("guard")
	var can_start := on_floor and (state in LOCOMOTION or (state == State.ATTACK and attack_phase == "recovery"))
	if Input.is_action_just_pressed("guard") and can_start and _now() - _guard_released_at >= guard_relock_time:
		_guard_pressed_at = _now()
		_set_state(State.GUARD)
	if state == State.GUARD and (not pressed or not on_floor):
		_guard_released_at = _now()
		_set_state(State.IDLE)


func _handle_attacks(delta: float, on_floor: bool) -> void:
	if state in LOCOMOTION or state == State.GUARD:
		if input_enabled and Input.is_action_just_pressed("attack_light"):
			_start_light(1)
		elif input_enabled and Input.is_action_just_pressed("attack_heavy"):
			charge = 0.0
			velocity.x = 0.0 if on_floor else velocity.x
			_set_state(State.HEAVY_CHARGE)
		return
	if state == State.ATTACK:
		if input_enabled and Input.is_action_just_pressed("attack_light"):
			_attack_buffered = true
		_attack_timer -= delta
		match attack_phase:
			"startup":
				if _attack_timer <= 0.0:
					attack_phase = "active"
					_attack_timer = light_active
					var hit := HitData.make(light_damage[attack_step - 1] * attack_multiplier, light_poise[attack_step - 1], self, Vector2(260, -80) if attack_step < 3 else Vector2(520, -180))
					hit.from_player = true
					# 범위: 앞으로 195 (기획자 요청으로 150 → 195, 2026-10-18)
					hitbox.set_box(Rect2(30, -90, 195, 112), facing)
					hitbox.activate(hit, light_active)
					if on_floor:
						velocity.x = facing * light_lunge
			"active":
				if _attack_timer <= 0.0:
					attack_phase = "recovery"
					_attack_timer = light_recovery
			"recovery":
				if _attack_buffered and attack_step < 3:
					_start_light(attack_step + 1)
				elif _attack_timer <= 0.0:
					_set_state(State.IDLE)
	elif state == State.HEAVY_CHARGE:
		charge = minf(charge + delta, heavy_max_charge)
		var still_held := Input.is_action_pressed("attack_heavy") if input_enabled else false
		if not still_held or charge >= heavy_max_charge:
			_start_heavy_swing()
	elif state == State.HEAVY_SWING:
		_attack_timer -= delta
		match attack_phase:
			"startup":
				if _attack_timer <= 0.0:
					attack_phase = "active"
					_attack_timer = heavy_active
					var t := charge / heavy_max_charge
					var hit := HitData.make(lerpf(heavy_damage, heavy_damage_charged, t) * attack_multiplier, lerpf(heavy_poise, heavy_poise_charged, t), self, Vector2(700, -260))
					hit.from_player = true
					hit.hitstop = 0.09
					hitbox.set_box(Rect2(20, -110, 265, 148), facing)
					hitbox.activate(hit, heavy_active)
					if on_floor:
						velocity.x = facing * light_lunge * 0.6
			"active":
				if _attack_timer <= 0.0:
					attack_phase = "recovery"
					_attack_timer = heavy_recovery
			"recovery":
				if _attack_timer <= 0.0:
					_set_state(State.IDLE)


func _start_light(step: int) -> void:
	attack_step = step
	attack_phase = "startup"
	_attack_timer = light_startup
	_attack_buffered = false
	if input_enabled:
		var axis := Input.get_axis("move_left", "move_right")
		if absf(axis) > 0.3:
			facing = 1 if axis > 0.0 else -1
	_set_state(State.ATTACK)
	attacked.emit(step, false)


func _start_heavy_swing() -> void:
	attack_phase = "startup"
	_attack_timer = heavy_startup
	_set_state(State.HEAVY_SWING)
	attacked.emit(0, true)


func _handle_heal(on_floor: bool) -> void:
	if not input_enabled:
		return
	if Input.is_action_just_pressed("heal") and dews > 0 and on_floor and state in LOCOMOTION:
		dews -= 1
		dews_changed.emit(dews)
		_heal_timer = heal_time
		_set_state(State.HEAL)


func _handle_interact() -> void:
	if not input_enabled:
		return
	if Input.is_action_just_pressed("interact"):
		_interact_buffer = 0.25   # 공격이 끝나기 직전에 눌러도 기억했다가 실행
	if _interact_buffer > 0.0 and can_interact and state in LOCOMOTION:
		_interact_buffer = 0.0
		var best: Node2D = null
		var best_d := INF
		for n in interactables:
			if is_instance_valid(n):
				var d: float = global_position.distance_to(n.global_position)
				if d < best_d:
					best_d = d
					best = n
		if best and best.has_method("interact"):
			best.interact(self)


## 보스의 날갯바람 등 바깥 힘. 매 물리 프레임 불러야 한다.
func apply_wind(force: float, _delta: float) -> void:
	if state == State.DEAD or state == State.REST or state == State.PURIFY:
		return
	_wind += force


func owned_souls() -> Array:
	var out := []
	if Progress.has_ability("wind"):
		out.append("wind")
	if Progress.has_ability("light"):
		out.append("light")
	return out


func soul_name() -> String:
	match soul:
		"wind": return "바람 (잿빛 잎새의 새)"
		"light": return "빛 (등불 기사)"
	return ""


## 영혼 능력. I / L2. 영혼 전환은 Q / 십자키 ← →.
func _handle_gust(_on_floor: bool) -> void:
	if not input_enabled:
		return
	var owned := owned_souls()
	if owned.size() > 1 and (Input.is_action_just_pressed("soul_next") or Input.is_action_just_pressed("soul_prev")):
		var i := owned.find(soul)
		var step := 1 if Input.is_action_just_pressed("soul_next") else -1
		soul = owned[(i + step + owned.size()) % owned.size()]
		soul_changed.emit(soul)
	if soul == "":
		return
	if Input.is_action_just_pressed("soul_ability") and _gust_cooldown <= 0.0 and (state in LOCOMOTION or state == State.GUARD):
		var p: Projectile = PROJECTILE.instantiate()
		if soul == "light":
			_gust_cooldown = light_shot_cooldown
			p.kind = Projectile.Kind.FEATHER
			p.speed = light_shot_speed
			p.damage = light_shot_damage * attack_multiplier
			p.poise = light_shot_poise
			p.lifetime = light_shot_time
			p.size = Vector2(70, 22)
			p.color = Color(1.0, 0.85, 0.5)
		else:
			_gust_cooldown = gust_cooldown
			p.kind = Projectile.Kind.GUST
			p.speed = gust_speed
			p.damage = gust_damage * attack_multiplier
			p.poise = gust_poise
			p.lifetime = gust_range_time
			p.size = Vector2(60, 34)
			p.color = Color(0.8, 1.0, 0.85)
		get_parent().add_child(p)
		p.global_position = global_position + Vector2(facing * 50.0, -20.0)
		p.launch(Vector2(facing, 0), self, true)
		gust_cast.emit()
		Juice.rumble(0.2, 0.3, 0.08)


## 어두운 방에서 소녀 주변을 밝힌다 (티아의 등불은 희미하게, 기사의 영혼이 깃들면 넓게).
func set_light(on: bool) -> void:
	if on and _light == null:
		_light = PointLight2D.new()
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 512
		gt.height = 512
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1, 0.5)
		_light.texture = gt
		_light.color = Color(1.0, 0.85, 0.6)
		_light.position = Vector2(0, -40)
		add_child(_light)
		_apply_abilities()
	elif _light:
		_light.enabled = on


func _handle_jump(on_floor: bool) -> void:
	if _buffer_timer > 0.0 and state in LOCOMOTION:
		if on_floor or _coyote_timer > 0.0:
			_do_jump(false)
		elif _jumps_left > 0:
			_do_jump(true)


func _handle_horizontal(delta: float, on_floor: bool, move_input: float) -> void:
	match state:
		State.ROLL:
			velocity.x = facing * roll_speed
		State.ATTACK, State.HEAVY_SWING:
			if on_floor:
				velocity.x = move_toward(velocity.x, 0.0, ground_decel * 0.8 * delta)
		State.HEAVY_CHARGE:
			if on_floor:
				velocity.x = move_toward(velocity.x, 0.0, ground_decel * delta)
			if absf(move_input) > 0.3:
				facing = 1 if move_input > 0.0 else -1
		State.GUARD:
			velocity.x = move_toward(velocity.x, move_input * walk_speed * guard_move_ratio, ground_accel * delta)
			# 가드 중에는 방향을 바꾸지 않는다 (정면만 막는다)
		_:
			var target_speed := move_input * (run_speed if (is_running and absf(move_input) > 0.5) else walk_speed) * slow_factor
			var accel := air_accel
			if on_floor:
				accel = ground_accel if absf(move_input) > 0.05 else ground_decel
			velocity.x = move_toward(velocity.x, target_speed, accel * delta)
			if absf(move_input) > 0.05:
				facing = 1 if move_input > 0.0 else -1


func _resolve_locomotion_state() -> void:
	if not (state in LOCOMOTION):
		return
	if not is_on_floor():
		_set_state(State.JUMP if velocity.y < 0.0 else State.FALL)
	elif absf(velocity.x) > 20.0:
		_set_state(State.RUN if (is_running and absf(velocity.x) > walk_speed + 10.0) else State.WALK)
	else:
		_set_state(State.IDLE)


func _do_jump(air_jump: bool) -> void:
	velocity.y = -_jump_velocity
	_buffer_timer = 0.0
	_coyote_timer = 0.0
	_jumps_left -= 1
	_set_state(State.JUMP)
	jumped.emit(air_jump)


func _try_roll(on_floor: bool) -> void:
	if _roll_cooldown_timer > 0.0:
		return
	var can := state in LOCOMOTION or state == State.GUARD or (state == State.ATTACK and attack_phase == "recovery")
	if not can or not (on_floor or _coyote_timer > 0.0):
		return
	hitbox.deactivate()
	_roll_timer = roll_duration
	velocity.y = 0.0
	_set_state(State.ROLL)
	roll_started.emit()


func _wants_to_leave_rest() -> bool:
	return Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("dodge") \
		or absf(Input.get_axis("move_left", "move_right")) > 0.5


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	if state == State.ATTACK or state == State.HEAVY_SWING:
		hitbox.deactivate()
	state = new_state
	if new_state == State.IDLE:
		attack_step = 0
		attack_phase = ""
	state_changed.emit(new_state)


# ---------- 맞기 ----------

## Hurtbox 가 부른다. 결과: "hit" / "guard" / "just_guard" / "guard_break" / "dodge" / "ignored"
func receive_hit(hit: HitData, _hurtbox: Hurtbox) -> String:
	if state == State.DEAD or state == State.PURIFY or state == State.REST:
		return "ignored"
	if _invuln_timer > 0.0:
		return "ignored"
	if state == State.ROLL and _roll_timer > roll_duration * (1.0 - roll_invuln_ratio):
		return "dodge"
	var from_dir := 1
	if hit.source:
		from_dir = 1 if hit.source.global_position.x >= global_position.x else -1
	var from_front := from_dir == facing

	if state == State.GUARD and hit.guardable and from_front:
		if _now() - _guard_pressed_at <= just_guard_window:
			_guard_pressed_at = -1000.0
			Juice.hitstop(0.1, 0.03)
			Juice.rumble(0.4, 1.0, 0.18)
			Juice.shake(7.0)
			just_guarded.emit(hit.source)
			if hit.source and hit.source.has_method("on_just_guarded"):
				hit.source.on_just_guarded(self, just_guard_poise)
			return "just_guard"
		Sfx.play("guard", -4.0)
		guard -= hit.damage * guard_drain_ratio
		hp = maxf(hp - hit.damage * guard_damage_ratio, 0.0)
		hp_changed.emit(hp, max_hp)
		velocity.x = -facing * 160.0
		Juice.hitstop(0.03, 0.1)
		Juice.rumble(0.2, 0.4, 0.08)
		_guard_regen_delay = 0.8
		if guard <= 0.0:
			guard = 0.0
			guard_changed.emit(guard, max_guard)
			_guard_regen_delay = 1.5
			_hit_timer = guard_break_stun
			_set_state(State.HIT)
			guard_broken.emit()
			Juice.shake(8.0)
			return "guard_break"
		guard_changed.emit(guard, max_guard)
		return "guard"

	hp = maxf(hp - hit.damage, 0.0)
	hp_changed.emit(hp, max_hp)
	hit_taken.emit(hit.damage)
	velocity = Vector2(-from_dir * absf(hit.knockback.x), hit.knockback.y)
	_hit_timer = hit_stun
	_invuln_timer = invuln_time
	hitbox.deactivate()
	Juice.hitstop(hit.hitstop, 0.05)
	Juice.rumble(0.5, 0.8, 0.15)
	Juice.shake(6.0)
	if hp <= 0.0:
		_die()
	else:
		_set_state(State.HIT)
	return "hit"


func _on_hit_landed(result: String, _target: Node) -> void:
	if result == "hit":
		Sfx.play("heavy_hit" if state == State.HEAVY_SWING else "hit", -3.0, 0.1)
		Juice.hitstop(0.05, 0.05)
		Juice.rumble(0.25, 0.5, 0.08)
		Juice.shake(3.0)
	elif result == "blocked":
		# 방패에 튕겼다: 살짝 밀려난다
		velocity.x = -facing * 260.0
		Juice.rumble(0.1, 0.2, 0.06)
		blocked.emit()


func _die() -> void:
	_set_state(State.DEAD)
	hitbox.deactivate()
	died.emit()


## 포자 등 조금씩 깎이는 피해 (경직 없음).
func take_damage_over_time(amount: float) -> void:
	if state == State.DEAD or state == State.REST:
		return
	hp = maxf(hp - amount, 0.0)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_die()


## 가시나 낭떠러지: 피해를 입고 마지막 안전한 자리로 돌아온다.
func take_hazard(damage: float) -> void:
	if state == State.DEAD or _invuln_timer > 0.0:
		return
	hp = maxf(hp - damage, 0.0)
	hp_changed.emit(hp, max_hp)
	hit_taken.emit(damage)
	Juice.hitstop(0.08, 0.05)
	Juice.rumble(0.5, 0.8, 0.2)
	Juice.shake(7.0)
	Sfx.play("thorn")
	hitbox.deactivate()
	if hp <= 0.0:
		_die()
		return
	_invuln_timer = 1.2
	_hit_timer = 0.5
	_set_state(State.HIT)
	velocity = Vector2.ZERO
	input_enabled = false
	await get_tree().create_timer(0.35).timeout
	if state == State.DEAD:
		return
	global_position = last_safe_position if last_safe_position != Vector2.ZERO else global_position
	velocity = Vector2.ZERO
	var cam := get_node_or_null("Camera2D")
	if cam:
		cam.reset_smoothing()
	input_enabled = true


## 방이 부른다: 마지막 달빛풀에서 다시 일어난다.
func revive(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	hp = max_hp
	guard = max_guard
	dews = max_dews
	_invuln_timer = 1.0
	last_safe_position = at
	_set_state(State.IDLE)
	hp_changed.emit(hp, max_hp)
	guard_changed.emit(guard, max_guard)
	dews_changed.emit(dews)


# ---------- 상호작용 ----------

func register_interactable(node: Node2D) -> void:
	if not interactables.has(node):
		interactables.append(node)
		interactables_changed.emit(can_interact)


func unregister_interactable(node: Node2D) -> void:
	if interactables.has(node):
		interactables.erase(node)
		interactables_changed.emit(can_interact)


## 정화의 손길: 무릎 꿇은 적에게 손을 얹는다.
func start_purify(target: Node2D) -> void:
	if state == State.PURIFY or state == State.DEAD:
		return
	purify_target = target
	facing = 1 if target.global_position.x >= global_position.x else -1
	velocity = Vector2.ZERO
	_set_state(State.PURIFY)
	purify_started.emit(target)
	await get_tree().create_timer(0.45).timeout
	if state != State.PURIFY:
		return
	Juice.hitstop(0.12, 0.02)
	Juice.rumble(0.3, 0.7, 0.3)
	Juice.shake(4.0)
	purified.emit(target)
	if is_instance_valid(target) and target.has_method("purified_by"):
		target.purified_by(self)
	await get_tree().create_timer(0.7).timeout
	if state == State.PURIFY:
		_set_state(State.IDLE)


## 달빛풀에서 쉰다.
func start_rest(grass: Node2D) -> void:
	if state == State.DEAD:
		return
	velocity = Vector2.ZERO
	facing = 1 if grass.global_position.x >= global_position.x else -1
	hp = max_hp
	guard = max_guard
	dews = max_dews
	hp_changed.emit(hp, max_hp)
	guard_changed.emit(guard, max_guard)
	dews_changed.emit(dews)
	_set_state(State.REST)
	rest_started.emit(grass)


func state_name() -> String:
	match state:
		State.IDLE: return "대기"
		State.WALK: return "걷기"
		State.RUN: return "달리기"
		State.JUMP: return "점프"
		State.FALL: return "낙하"
		State.ROLL: return "구르기"
		State.ATTACK: return "약공격 %d" % attack_step
		State.HEAVY_CHARGE: return "차지 %.0f%%" % (charge / heavy_max_charge * 100.0)
		State.HEAVY_SWING: return "강공격"
		State.GUARD: return "가드"
		State.HIT: return "피격"
		State.HEAL: return "회복"
		State.PURIFY: return "정화의 손길"
		State.REST: return "쉬는 중"
		State.DEAD: return "쓰러짐"
	return "?"


func jump_velocity() -> float:
	return _jump_velocity


func jump_gravity() -> float:
	return _jump_gravity


func is_invulnerable() -> bool:
	return _invuln_timer > 0.0

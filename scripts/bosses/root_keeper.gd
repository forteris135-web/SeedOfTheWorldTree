extends CharacterBody2D
class_name RootKeeper
## 최종 보스 '뿌리지기'. 세계수의 첫 수호자. 달빛 정원을 홀로 가꿔 왔다. 땅에서 싸운다.
## 2026-10-19 개편(기획자 요청: 단조로움·가시성): 모든 예고를 붉게·크게(가드 가능 = 주황빛, 가드 불가 = 진한 붉은색 깜빡임),
## 지팡이를 그림에서 분리해 실제로 휘두르고, 패턴을 늘리고 연계로 잇는다. 같은 패턴은 연속으로 두 번 쓰지 않는다.
## 1페이즈: 뿌리 가시 SPIKES(바닥 붉은 예고 → 솟음, 1.5배 커짐) / 지팡이 휘두르기 SWEEP(붉은 부채꼴 예고, 보랏빛 호 궤적; 가끔 되돌려 베기 SWEEP2 연계)
##          / 달빛 구슬 ORBS(지팡이 끝 붉은 고리 → 2배 크기 추적 구슬 2개) / 뿌리 손 HAND(붉은 타원 예고 → 거대한 손이 솟아 움켜쥠, 가드 불가, 잡히면 묶임)
##          / 씨앗 비 SEEDS(하늘에서 가시 씨앗 5개, 떨어질 자리에 주황 점) / 달빛 고리 RING(보스 둘레를 도는 구슬 고리가 넓어짐)
## 2페이즈(체력 절반 → 무너졌다 다시 일어서며 주제곡 RISE): 빨라지고(예비 0.7배), 가시 4개 또는 물결 6개, 구슬 4개, 손 2개, 씨앗 7개, 고리 8개,
##          + 뿌리 벽 돌진 WALL(지나갈 띠가 붉게, 가드 불가, 벽이 실제로 밀려옴) + 지팡이 내려찍기 STOMP(양쪽 바닥을 달리는 충격파 2줄 × 2번, 가드 불가, 점프로 넘김)
## 연계(_chain): 씨앗 비 → 뿌리 손, 휘두르기 → 되돌려 베기(앞에서 올려 베기) → (2페이즈) 내려찍기, 가시 → 구슬/고리, 구슬 → 가시, 손 → 휘두르기.
##   연계 직전에 소녀 쪽으로 돌아선다. 무너지면(BROKEN) 예약된 공격은 모두 거둔다. 2페이즈로 넘어갈 때 흐트러짐은 0 으로.
## 체력 0 → 쓰러짐 → 정화 → 마지막 회상 → 선택.
## BossRoom 과 맞추는 약속: start_fight / reset_fight / arena / ground_y / fallen / purified / hp_changed / poise_changed / phase_changed
##   / telegraph(kind) + telegraph_label(kind) / state_name() / debug_log / is_ground() / receive_hit / hp·poise·phase·facing

enum State { WAIT, INTRO, STANCE, SPIKES, SWEEP, ORBS, WALL, RISE, BROKEN, FALLEN, PURIFIED, HAND, SEEDS, RING, STOMP, SWEEP2 }
const ATTACK_STATES := [State.SPIKES, State.SWEEP, State.ORBS, State.WALL, State.HAND, State.SEEDS, State.RING, State.STOMP, State.SWEEP2]
## 가드 불가 패턴 (붉은 예고 빛 + 그림이 붉게 깜빡임)
const RED_STATES := [State.WALL, State.HAND, State.STOMP]
## 가드 불가 예고의 깜빡임 속도(초당 횟수). 그림·뿌리 손 예고가 함께 쓴다. 빛에 민감한 사람을 위해 3 이하로 둔다.
const TELEGRAPH_BLINK_HZ := 2.5
## 휘두르기 판정 사각형 (바라보는 방향 기준, Hitbox 노드 기준 — 노드는 발밑에서 y -60). 그림의 붉은 부채꼴도 이 값을 읽는다.
const SWEEP_BOX := Rect2(-60, -200, 380, 230)
const SWEEP2_BOX := Rect2(-80, -220, 400, 250)
## 휘두를 때 앞으로 미끄러지는 첫 속도 (부채꼴이 이만큼 더 앞을 덮는다)
const SWEEP_SLIDE := 300.0
const SWEEP2_SLIDE := 200.0

signal hp_changed(hp: float, max_hp: float)
signal poise_changed(poise: float, max_poise: float)
signal phase_changed(phase: int)
signal state_changed(state: State)
signal fallen
signal purified
signal telegraph(kind: String)

@export var max_hp := 1400.0
@export var max_poise := 200.0
@export var poise_decay := 7.0
@export var broken_time := 4.0
@export var broken_damage_multiplier := 1.6
@export var walk_speed := 140.0
@export var gravity := 2600.0
## 공격 피해 (기획서: 14~32)
@export var spike_damage := 20.0
@export var sweep_damage := 24.0
@export var sweep2_damage := 20.0
@export var orb_damage := 16.0
@export var ring_damage := 14.0
@export var wall_damage := 32.0
@export var hand_damage := 22.0
@export var seed_damage := 16.0
@export var stomp_wave_damage := 20.0
@export var stomp_slam_damage := 26.0
## 뿌리 손에 잡혀 묶이는 시간
@export var hand_hold := 0.7

var state: State = State.WAIT
var hp := 1400.0
var poise := 0.0
var phase := 1
var facing := -1
var player: Player
var arena: Rect2
var ground_y := 0.0
var attack_phase := ""   # startup / active / recovery (공격이 아니면 "")
var windup_progress := 0.0
## 지금 공격의 단계 길이(초). 그림이 진행도(남은 시간 / 길이)를 계산하는 데 쓴다.
var startup_len := 0.5
var active_len := 0.2
var recovery_len := 0.8
## 다시 일어서는 연출 길이 (RISE)
var rise_len := 3.0
## 그림에 주는 힌트: "" / "stagger"(저스트 가드로 지팡이가 튕김 — 그림만 휘청, 공격 흐름은 그대로)
var anim_hint := ""
var _hint_timer := 0.0
## 저스트 가드 휘청의 세기 (1 → 0 으로 stagger_len 동안 서서히 줄어든다). 그림은 이 값만큼 뒤로 젖힌다.
var stagger := 0.0
var stagger_len := 0.45
## 몸 돌리기 규칙: 소녀가 이만큼(px) 넘게 반대쪽에 있어야 돌고, 한 번 돌면 이 시간 동안은 다시 돌지 않는다.
@export var face_deadzone := 40.0
@export var face_hold := 0.25
var _face_hold := 0.0
## 예고 자리들 (그림이 붉은 예고를 그린다)
var spike_marks: Array = []     # 가시가 솟을 x
var spike_delays: Array = []    # 가시마다 솟기 전 기다리는 시간 (물결)
var hand_targets: Array = []    # 뿌리 손이 솟을 x (예비 60% 까지는 소녀를 따라간다)
var _spike_wave := false
## 패턴 고르기: 직전 패턴(연속 금지), 예약된 연계
var _last_attack := -1
var _chain := -1
## 예약된 일(초 뒤에 부르기). create_timer 대신 상태 기계 안에서 돌려 시험·리셋이 정확하다.
var _events: Array = []
var _clock := 0.0
var _timer := 0.0
var _poise_hold := 0.0
var _flash := 0.0
var _registered := false
var _home := Vector2.ZERO
var _red := false
var debug_log := false

@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
const SPIKE := preload("res://scenes/combat/root_spike.tscn")
const HAND := preload("res://scenes/bosses/root_hand.tscn")
const SEED := preload("res://scenes/bosses/root_seed.tscn")
const ORB := preload("res://scenes/bosses/root_orb.tscn")
const SHOCKWAVE := preload("res://scenes/bosses/root_shockwave.tscn")
const WALL_FX := preload("res://scenes/bosses/root_wall.tscn")


func _ready() -> void:
	add_to_group("boss")
	hp = max_hp
	_home = global_position
	visible = false


func start_fight(p: Player) -> void:
	player = p
	visible = true
	global_position = Vector2(arena.get_center().x + 450, ground_y)
	facing = -1
	_set_state(State.INTRO)
	_timer = 2.6


func reset_fight() -> void:
	_unregister()
	hp = max_hp
	poise = 0.0
	phase = 1
	visible = false
	velocity = Vector2.ZERO
	hitbox.deactivate()
	_clear_marks()
	_clear_effects()
	_events.clear()
	_last_attack = -1
	_chain = -1
	_red = false
	global_position = _home
	_set_state(State.WAIT)
	hp_changed.emit(hp, max_hp)
	poise_changed.emit(poise, max_poise)


func _physics_process(delta: float) -> void:
	if state == State.WAIT or state == State.PURIFIED:
		return
	_flash = maxf(_flash - delta * 6.0, 0.0)
	_poise_hold = maxf(_poise_hold - delta, 0.0)
	if _poise_hold <= 0.0 and poise > 0.0 and state not in [State.BROKEN, State.FALLEN, State.RISE]:
		poise = maxf(poise - poise_decay * delta, 0.0)
		poise_changed.emit(poise, max_poise)
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0
	_timer -= delta
	_clock += delta
	_tick_events()
	_face_hold = maxf(_face_hold - delta, 0.0)
	stagger = maxf(stagger - delta / stagger_len, 0.0)
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			anim_hint = ""
	var fast := 0.7 if phase == 2 else 1.0
	match state:
		State.INTRO:
			velocity.x = 0.0
			if _timer <= 0.0:
				_set_state(State.STANCE)
				_timer = 0.8
		State.STANCE:
			if player:
				var dx := player.global_position.x - global_position.x
				var want_face := 1 if dx > 0.0 else -1
				if want_face != facing and absf(dx) > face_deadzone and _face_hold <= 0.0:
					facing = want_face
					_face_hold = face_hold
				# 천천히 거리를 유지한다 (너무 가까우면 물러나고, 멀면 다가온다)
				var want := 0.0
				if absf(dx) < 260.0:
					want = -want_face * walk_speed
				elif absf(dx) > 700.0:
					want = want_face * walk_speed
				velocity.x = move_toward(velocity.x, want, 800.0 * delta)
				if _timer <= 0.0:
					_choose(absf(dx))
			else:
				velocity.x = 0.0
		State.SPIKES:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, startup_len, 0.3, 1.0 * fast, func() -> void: _raise_spikes())
		State.SWEEP:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, startup_len, 0.2, 0.8 * fast, func() -> void:
				var hit := HitData.make(sweep_damage, 0.0, self, Vector2(560, -220))
				hitbox.set_box(SWEEP_BOX, facing)
				hitbox.activate(hit, 0.2)
				velocity.x = facing * SWEEP_SLIDE
				Sfx.play("staff_swing", -2.0, 0.1))
		State.SWEEP2:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, startup_len, 0.2, 0.7 * fast, func() -> void:
				var hit := HitData.make(sweep2_damage, 0.0, self, Vector2(520, -260))
				hitbox.set_box(SWEEP2_BOX, facing)
				hitbox.activate(hit, 0.2)
				velocity.x = facing * SWEEP2_SLIDE
				Sfx.play("staff_swing", -1.0, 0.1))
		State.ORBS:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, startup_len, 0.2, 1.1 * fast, func() -> void:
				var n := 2 if phase == 1 else 4
				var gap := 0.3 if phase == 1 else 0.22
				for i in n:
					var off := i - (n - 1) / 2.0
					_queue(i * gap, func() -> void: _spawn_orb(off)))
		State.WALL:
			_phase_step(delta, startup_len, 0.6, 1.3, func() -> void:
				var hit := HitData.make(wall_damage, 0.0, self, Vector2(760, -340))
				hit.guardable = false
				hitbox.set_box(Rect2(0, -260, 200, 290), facing)
				hitbox.activate(hit, 0.6)
				velocity.x = facing * 1100.0
				Juice.shake(10.0)
				Sfx.play("root_wall", 0.0, 0.08)
				var wall: RootWall = WALL_FX.instantiate()
				wall.facing = facing
				wall.life = 0.75
				add_child(wall)
				_red = false)
			if attack_phase == "active":
				if is_on_wall():
					velocity.x = 0.0
			else:
				velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
		State.HAND:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			if attack_phase == "startup" and windup_progress < 0.6:
				_track_hands()
			_phase_step(delta, startup_len, 0.4, 0.9 * fast, func() -> void:
				_red = false
				for i in hand_targets.size():
					var h: RootHand = HAND.instantiate()
					h.damage = hand_damage
					h.hold_time = hand_hold
					h.delay = i * 0.25
					h.throw_dir = 1 if hand_targets[i] >= global_position.x else -1
					get_parent().add_child(h)
					h.global_position = Vector2(hand_targets[i], ground_y)
					h.source = self
				hand_targets.clear())
		State.SEEDS:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, startup_len, 1.3, 0.8 * fast, func() -> void:
				var n := 5 if phase == 1 else 7
				var offsets := [0.0, -260.0, 260.0, -130.0, 130.0, -390.0, 390.0]
				var px := player.global_position.x if player else global_position.x
				for i in n:
					var x: float = px + offsets[i]
					_queue(i * 0.18, func() -> void: _spawn_seed(x)))
		State.RING:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, startup_len, 2.4, 0.6 * fast, func() -> void:
				var n := 6 if phase == 1 else 8
				for i in n:
					var o: RootOrb = ORB.instantiate()
					o.mode = RootOrb.Mode.ORBIT
					o.damage = ring_damage
					o.center = self
					o.center_offset = Vector2(0, -200)
					o.orbit_r = 90.0
					o.orbit_grow = 280.0 if phase == 1 else 330.0
					o.orbit_max = 760.0
					o.angle = TAU * i / n
					o.angular_speed = 2.2 if phase == 1 else 2.7
					o.lifetime = 2.6
					o.ground_y = ground_y
					o.radius = 34.0
					get_parent().add_child(o)
					o.global_position = global_position + o.center_offset
					o.launch(Vector2.LEFT, self)
				Sfx.play("ring_hum", -4.0, 0.05))
		State.STOMP:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, startup_len, 0.3, 1.2, func() -> void:
				_red = false
				var hit := HitData.make(stomp_slam_damage, 0.0, self, Vector2(620, -380))
				hit.guardable = false
				hit.hitstop = 0.08
				hitbox.set_box(Rect2(-130, -130, 260, 150), 1)
				hitbox.activate(hit, 0.25)
				Juice.shake(14.0)
				Juice.rumble(0.7, 1.0, 0.3)
				Sfx.play("stomp", 0.0, 0.06)
				_spawn_shockwaves()
				_queue(0.55, func() -> void:
					Juice.shake(6.0)
					Sfx.play("stomp", -5.0, 0.06)
					_spawn_shockwaves()))
		State.RISE:
			velocity.x = 0.0
			if _timer <= 0.0:
				_set_state(State.STANCE)
				_timer = 0.6
		State.BROKEN:
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			if _timer <= 0.0:
				poise = 0.0
				poise_changed.emit(poise, max_poise)
				_set_state(State.STANCE)
				_timer = 0.5
		State.FALLEN:
			velocity.x = 0.0
			_update_interactable()
	move_and_slide()


func _phase_step(delta: float, startup: float, active: float, recovery: float, on_active: Callable) -> void:
	match attack_phase:
		"startup":
			windup_progress = 1.0 - _timer / startup
			if _timer <= 0.0:
				attack_phase = "active"
				_timer = active
				active_len = active
				on_active.call()
		"active":
			if _timer <= 0.0:
				attack_phase = "recovery"
				_timer = recovery
				recovery_len = recovery
		"recovery":
			if _timer <= 0.0:
				_end_attack()


## 공격이 끝났다: 예약된 연계가 있으면 바로 잇고, 없으면 자세로 돌아가 잠깐 쉰다.
func _end_attack() -> void:
	if _chain >= 0 and player:
		var c: State = _chain as State
		_chain = -1
		var dx := player.global_position.x - global_position.x
		# 휘두르기 연계는 소녀가 아직 가까울 때만 (그사이 멀어졌으면 쉬었다가 새로 고른다)
		if not (c == State.SWEEP and absf(dx) > 420.0):
			# 연계 직전에 소녀 쪽으로 돈다 (등진 채 허공을 치지 않게)
			var want_face := 1 if dx > 0.0 else -1
			if want_face != facing and absf(dx) > face_deadzone:
				facing = want_face
				_face_hold = face_hold
			_set_state(State.STANCE)
			_timer = 0.15
			_start_attack(c)
			# 되돌려 베기 뒤에는 (2페이즈) 가끔 내려찍기까지 잇는다
			if c == State.SWEEP2:
				_chain = _pick_chain(c, absf(dx))
			return
	_set_state(State.STANCE)
	_timer = (0.7 if phase == 1 else 0.4) + randf() * 0.3


## 지금 공격 단계의 진행도 (0→1). 그림이 세 박자 곡선(예비→타격→되돌림)을 그리는 기준.
func phase_progress() -> float:
	match attack_phase:
		"startup": return clampf(windup_progress, 0.0, 1.0)
		"active": return 1.0 - clampf(_timer / maxf(active_len, 0.001), 0.0, 1.0)
		"recovery": return 1.0 - clampf(_timer / maxf(recovery_len, 0.001), 0.0, 1.0)
	return 0.0


## 지금 상태의 진행도 (0→1; RISE 같은 단순 상태용).
func state_progress(length: float) -> float:
	return 1.0 - clampf(_timer / maxf(length, 0.001), 0.0, 1.0)


func _begin(st: State, startup: float) -> void:
	_set_state(st)
	attack_phase = "startup"
	windup_progress = 0.0
	_timer = startup
	startup_len = startup


# ---------- 예약된 일 ----------

func _queue(delay: float, cb: Callable) -> void:
	_events.append([_clock + delay, cb])


func _tick_events() -> void:
	if _events.is_empty():
		return
	var due: Array = []
	var rest: Array = []
	for e in _events:
		if e[0] <= _clock:
			due.append(e)
		else:
			rest.append(e)
	_events = rest
	for e in due:
		if state not in [State.FALLEN, State.PURIFIED, State.WAIT]:
			e[1].call()


# ---------- 패턴 고르기 ----------

## 거리별 후보에서 직전 패턴을 빼고 무게로 하나 고른 뒤, 확률로 연계를 예약한다.
func _choose(dist: float) -> void:
	var cands: Array = []   # [State, weight]
	if dist < 330.0:
		cands = [[State.SWEEP, 50], [State.HAND, 20], [State.RING, 15], [State.SPIKES, 10]]
		if phase == 2:
			cands.append([State.STOMP, 20])
	elif dist < 700.0:
		cands = [[State.SPIKES, 30], [State.ORBS, 20], [State.HAND, 20], [State.SEEDS, 20], [State.RING, 10]]
		if phase == 2:
			cands.append([State.STOMP, 12])
	else:
		cands = [[State.SPIKES, 25], [State.ORBS, 25], [State.SEEDS, 25], [State.HAND, 10]]
		if phase == 2:
			cands.append([State.WALL, 30])
	var pick := _weighted_pick(cands)
	_chain = _pick_chain(pick, dist)
	_start_attack(pick)


func _weighted_pick(cands: Array) -> State:
	var total := 0
	for c in cands:
		if c[0] != _last_attack:
			total += c[1]
	var r := randf() * total
	for c in cands:
		if c[0] == _last_attack:
			continue
		r -= c[1]
		if r <= 0.0:
			return c[0]
	return cands[0][0] if cands[0][0] != _last_attack else cands[1][0]


## 연계 표: (지금 패턴 → 다음 패턴, 확률). 2페이즈가 더 자주 잇는다.
func _pick_chain(st: State, dist: float) -> int:
	var p2 := phase == 2
	match st:
		State.SEEDS:
			return State.HAND if randf() < (0.6 if p2 else 0.35) else -1
		State.SWEEP:
			return State.SWEEP2 if randf() < (0.5 if p2 else 0.25) else -1
		State.SPIKES:
			if p2 and randf() < 0.25:
				return State.RING
			return State.ORBS if (not p2 and randf() < 0.2) else -1
		State.ORBS:
			return State.SPIKES if (p2 and randf() < 0.3) else -1
		State.HAND:
			return State.SWEEP if (p2 and dist < 420.0 and randf() < 0.3) else -1
		State.SWEEP2:
			return State.STOMP if (p2 and randf() < 0.3) else -1
	return -1


## 패턴 하나를 시작한다 (예고 자리·붉은 빛·예고 글자·예비 길이).
func _start_attack(st: State) -> void:
	var fast := 0.7 if phase == 2 else 1.0
	_last_attack = st
	_red = st in RED_STATES
	match st:
		State.SPIKES:
			_mark_spikes()
			_begin(st, 0.9 * fast)
		State.SWEEP:
			_begin(st, 0.5 * fast)
		State.SWEEP2:
			# 휘두르기 바로 뒤에 붙지만 예고는 기준(0.45초, 2페이즈 0.7배)을 지킨다
			_begin(st, 0.45 * fast)
		State.ORBS:
			_begin(st, 0.8 * fast)
		State.WALL:
			telegraph.emit("wall")
			_begin(st, 1.1)
		State.HAND:
			telegraph.emit("hand")
			hand_targets.clear()
			_track_hands()
			_begin(st, 0.8 * fast)
		State.SEEDS:
			telegraph.emit("seeds")
			_begin(st, 0.7 * fast)
		State.RING:
			telegraph.emit("ring")
			_begin(st, 0.7 * fast)
		State.STOMP:
			telegraph.emit("stomp")
			_begin(st, 1.0)
		_:
			_begin(State.SWEEP, 0.5 * fast)


## 시험·스크린샷용: 이름으로 패턴을 바로 건다 ("SPIKES", "HAND", ...).
func force_pattern(name: String) -> void:
	_chain = -1
	var idx := State.keys().find(name)
	if idx < 0 or idx not in ATTACK_STATES:
		return
	_start_attack(idx as State)


## BossRoom 이 예고 글자로 띄울 문구 (가드 불가는 붉은 빛으로 알리고 글자는 공격 이름만).
func telegraph_label(kind: String) -> String:
	match kind:
		"wall": return "뿌리 벽!"
		"hand": return "뿌리 손!"
		"seeds": return "씨앗 비!"
		"ring": return "달빛 고리!"
		"stomp": return "내려찍기!"
	return ""


# ---------- 패턴 실행 ----------

func _mark_spikes() -> void:
	_clear_marks()
	if player == null:
		return
	var px := player.global_position.x
	if phase == 1:
		spike_marks = [px, px + facing * 220.0]
		spike_delays = [0.0, 0.08]
	else:
		_spike_wave = not _spike_wave
		if _spike_wave:
			# 물결: 뿌리지기 앞에서 소녀 쪽으로 차례로 솟는 6개
			for i in 6:
				spike_marks.append(global_position.x + facing * (200.0 + 190.0 * i))
				spike_delays.append(i * 0.09)
		else:
			spike_marks = [px - 260.0, px, px + 260.0, px + player.velocity.x * 0.6]
			spike_delays = [0.0, 0.06, 0.12, 0.18]
	for i in spike_marks.size():
		spike_marks[i] = _clamp_x(spike_marks[i])


func _clamp_x(x: float) -> float:
	if arena.size.x <= 0.0:
		return x
	return clampf(x, arena.position.x + 60.0, arena.end.x - 60.0)


func _raise_spikes() -> void:
	for i in spike_marks.size():
		var sp: RootSpike = SPIKE.instantiate()
		sp.damage = spike_damage
		sp.delay = spike_delays[i] if i < spike_delays.size() else 0.0
		get_parent().add_child(sp)
		sp.global_position = Vector2(spike_marks[i], ground_y)
		sp.launch(Vector2.UP, self, false)
	Sfx.play("root_rise", 0.0, 0.08)
	_clear_marks()


func _clear_marks() -> void:
	spike_marks.clear()
	spike_delays.clear()


## 뿌리 손 자리: 예비 60% 까지 소녀를 따라간다 (2페이즈는 두 번째 손이 소녀가 달리는 쪽 앞에)
func _track_hands() -> void:
	if player == null:
		return
	var px := _clamp_x(player.global_position.x)
	if hand_targets.is_empty():
		hand_targets = [px]
	else:
		hand_targets[0] = px
	if phase == 2:
		var lead := signf(player.velocity.x) if absf(player.velocity.x) > 40.0 else float(-facing)
		var second := _clamp_x(px + lead * 240.0)
		if hand_targets.size() < 2:
			hand_targets.append(second)
		else:
			hand_targets[1] = second


func _spawn_orb(offset: float) -> void:
	var o: RootOrb = ORB.instantiate()
	o.mode = RootOrb.Mode.HOMING
	o.speed = 380.0 if phase == 1 else 460.0
	o.damage = orb_damage
	o.lifetime = 4.5
	o.homing = 1.6 if phase == 1 else 2.0
	o.radius = 36.0
	get_parent().add_child(o)
	o.global_position = orb_origin() + Vector2(0.0, offset * 30.0)   # 예고 고리(반지름 80) 안에서 생긴다
	var dir := Vector2(facing, -0.15 + offset * 0.22).normalized()
	o.launch(dir, self)


## 휘두르기(SWEEP/SWEEP2) 판정이 덮는 자리 (발밑 기준, 바라보는 쪽 = +x). 그림의 붉은 부채꼴은 이 사각형을 반드시 덮는다.
## 휘두르며 앞으로 미끄러지는 거리(첫 속도에서 감속 2000 으로 멈출 때까지) + 여유 30px 만큼 앞을 더 본다.
func sweep_reach(st: State) -> Rect2:
	var two := st == State.SWEEP2
	var box: Rect2 = SWEEP2_BOX if two else SWEEP_BOX
	var slide: float = SWEEP2_SLIDE if two else SWEEP_SLIDE
	var extra := slide * slide / (2.0 * 2000.0) + 30.0
	var hy: float = hitbox.position.y if hitbox else -60.0
	return Rect2(box.position.x, hy + box.position.y, box.size.x + extra, box.size.y)


## 구슬이 생기는 자리 = 그림의 지팡이 머리 (예고 고리가 뜨는 곳). 그림이 없으면 머리 위 앞쪽.
func orb_origin() -> Vector2:
	var vis := get_node_or_null("Sprite")
	if vis and vis.has_method("head_world"):
		return vis.head_world()
	return global_position + Vector2(facing * 120.0, -460.0)


func _spawn_seed(x: float) -> void:
	var s: RootSeed = SEED.instantiate()
	s.damage = seed_damage
	s.ground_y = ground_y
	s.source = self
	get_parent().add_child(s)
	s.global_position = Vector2(_clamp_x(x), ground_y - RootSeed.FALL_HEIGHT)
	Sfx.play("seed_fall", -8.0, 0.2)


func _spawn_shockwaves() -> void:
	for d in [-1, 1]:
		var w: RootShockwave = SHOCKWAVE.instantiate()
		w.damage = stomp_wave_damage
		w.dir = d
		w.source = self
		w.min_x = arena.position.x + 20.0 if arena.size.x > 0.0 else -INF
		w.max_x = arena.end.x - 20.0 if arena.size.x > 0.0 else INF
		get_parent().add_child(w)
		w.global_position = Vector2(global_position.x + d * 90.0, ground_y)


## 떠 있는 패턴 효과(손·구슬·씨앗·충격파·가시)를 모두 치운다 (쓰러짐·2페이즈 전환·리셋).
func _clear_effects() -> void:
	hand_targets.clear()
	_events.clear()
	for n in get_tree().get_nodes_in_group("root_effect"):
		if is_instance_valid(n):
			n.queue_free()


# ---------- 맞기 ----------

func receive_hit(hit: HitData, _hb: Hurtbox) -> String:
	if state in [State.WAIT, State.INTRO, State.FALLEN, State.PURIFIED, State.RISE]:
		return "ignored"
	_flash = 1.0
	var dmg := hit.damage * (broken_damage_multiplier if state == State.BROKEN else 1.0)
	hp = maxf(hp - dmg, 0.0)
	hp_changed.emit(hp, max_hp)
	_add_poise(hit.poise)
	if hp <= 0.0:
		_fall()
		return "hit"
	if phase == 1 and hp <= max_hp * 0.5:
		# 무너졌다 다시 일어선다 (여기서 주제곡이 터진다 — 13단계)
		phase = 2
		hitbox.deactivate()
		_clear_marks()
		_clear_effects()
		_chain = -1
		_red = false
		# 흐트러짐을 비운다: 무너진 채로 넘어와도 일어서자마자 한 대에 또 무너지지 않게 (RISE 동안은 줄지 않는다)
		poise = 0.0
		_poise_hold = 0.0
		poise_changed.emit(poise, max_poise)
		_set_state(State.RISE)
		_timer = rise_len
		phase_changed.emit(2)
		telegraph.emit("rise")
		Juice.hitstop(0.2, 0.02)
		Juice.shake(14.0)
		return "hit"
	if poise >= max_poise and state != State.BROKEN:
		_break()
		Juice.hitstop(0.1, 0.05)
		Juice.shake(8.0)
	return "hit"


func on_just_guarded(_by: Player, amount: float) -> void:
	_flash = 1.0
	_add_poise(amount)
	if poise >= max_poise and state != State.BROKEN:
		_break()
	elif state == State.SWEEP or state == State.SWEEP2:
		# 지팡이가 튕겼다: 그림만 짧게 휘청인다 (공격 길이·판정은 그대로)
		anim_hint = "stagger"
		_hint_timer = stagger_len
		stagger = 1.0


## 무너진다: 지금 공격과 예약해 둔 일(남은 씨앗·구슬·둘째 충격파)을 모두 거둔다 — 몰아칠 틈을 방해하지 않게.
## 이미 떠 있는 효과(떨어지는 씨앗 등)는 그대로 끝까지 간다.
func _break() -> void:
	hitbox.deactivate()
	_chain = -1
	_red = false
	_events.clear()
	hand_targets.clear()
	_clear_marks()
	_set_state(State.BROKEN)
	_timer = broken_time


func _add_poise(amount: float) -> void:
	if amount <= 0.0:
		return
	poise = minf(poise + amount, max_poise)
	_poise_hold = 2.5
	poise_changed.emit(poise, max_poise)


func _fall() -> void:
	hitbox.deactivate()
	_unregister()
	_clear_marks()
	_clear_effects()
	_chain = -1
	_red = false
	_set_state(State.FALLEN)
	Juice.hitstop(0.2, 0.02)
	Juice.shake(12.0)
	fallen.emit()


func _update_interactable() -> void:
	if player == null:
		return
	var near := absf(player.global_position.x - global_position.x) < 240.0 and absf(player.global_position.y - global_position.y) < 220.0
	if near and not _registered:
		player.register_interactable(self)
		_registered = true
	elif not near and _registered:
		_unregister()


func _unregister() -> void:
	if _registered and player:
		player.unregister_interactable(self)
	_registered = false


func interact(by: Player) -> void:
	if state == State.FALLEN:
		by.start_purify(self)


func purified_by(_by: Player) -> void:
	_unregister()
	_set_state(State.PURIFIED)
	purified.emit()


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	if debug_log:
		print("[뿌리지기] %s → %s" % [State.keys()[state], State.keys()[new_state]])
	state = new_state
	anim_hint = ""
	_hint_timer = 0.0
	if new_state not in ATTACK_STATES:
		attack_phase = ""
	state_changed.emit(new_state)


func flash_amount() -> float:
	return _flash


## 가드 불가 예고 중 (그림이 붉게 깜빡인다)
func is_red() -> bool:
	return _red and state in RED_STATES and attack_phase == "startup"


## 지금 패턴이 가드 가능한가 (그림이 예고 색을 고른다: 가드 가능 = 주황빛, 불가 = 진한 붉은색)
func is_guardable_pattern() -> bool:
	return state not in RED_STATES


func is_ground() -> bool:
	return true


func state_name() -> String:
	return State.keys()[state]

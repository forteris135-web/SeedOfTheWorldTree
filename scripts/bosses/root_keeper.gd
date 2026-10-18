extends CharacterBody2D
class_name RootKeeper
## 최종 보스 '뿌리지기'. 세계수의 첫 수호자. 달빛 정원을 홀로 가꿔 왔다. 땅에서 싸운다.
## 1페이즈: 뿌리 가시(바닥 예고 → 솟음) / 지팡이 휘두르기 / 달빛 구슬(느린 추적, 가드 가능)
## 2페이즈(체력 절반 → 무너졌다 다시 일어서며 주제곡): 뿌리 가시 3줄, 뿌리 벽 돌진(붉은 예고·가드 불가), 구슬 3개.
## 체력 0 → 쓰러짐 → 정화 → 마지막 회상 → 선택.

enum State { WAIT, INTRO, STANCE, SPIKES, SWEEP, ORBS, WALL, RISE, BROKEN, FALLEN, PURIFIED }
const ATTACK_STATES := [State.SPIKES, State.SWEEP, State.ORBS, State.WALL]

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
@export var spike_damage := 20.0
@export var sweep_damage := 24.0
@export var orb_damage := 16.0
@export var wall_damage := 32.0

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
## 힌트 시간이 끝날 때 보정이 한 번에 사라지지 않게 따로 감쇠시킨다.
var stagger := 0.0
var stagger_len := 0.45
## 몸 돌리기 규칙: 소녀가 이만큼(px) 넘게 반대쪽에 있어야 돌고, 한 번 돌면 이 시간 동안은 다시 돌지 않는다.
## (소녀가 구르기로 몸을 통과할 때 정면 그림이 찌그러졌다 펴지길 반복하지 않게)
@export var face_deadzone := 40.0
@export var face_hold := 0.25
var _face_hold := 0.0
var spike_marks: Array = []   # 예고 중인 가시 x 좌표들
var _timer := 0.0
var _poise_hold := 0.0
var _flash := 0.0
var _registered := false
var _home := Vector2.ZERO
var _red := false
var debug_log := false

@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
const PROJECTILE := preload("res://scenes/combat/projectile.tscn")
const SPIKE := preload("res://scenes/combat/root_spike.tscn")


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
	spike_marks.clear()
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
				# 거리 유지는 몸 방향이 아니라 소녀가 있는 쪽(dx) 기준 — 예전과 같은 움직임
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
			_phase_step(delta, 0.9 * fast, 0.3, 1.0 * fast, func() -> void: _raise_spikes())
		State.SWEEP:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, 0.5 * fast, 0.2, 0.8 * fast, func() -> void:
				var hit := HitData.make(sweep_damage, 0.0, self, Vector2(560, -220))
				hitbox.set_box(Rect2(-60, -200, 380, 230), facing)
				hitbox.activate(hit, 0.2)
				velocity.x = facing * 300.0)
		State.ORBS:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, 0.8 * fast, 0.2, 1.1 * fast, func() -> void:
				var n := 1 if phase == 1 else 3
				for i in n:
					get_tree().create_timer(i * 0.25).timeout.connect(func() -> void:
						if state not in [State.FALLEN, State.PURIFIED, State.WAIT]:
							_spawn_orb(i - (n - 1) / 2.0)))
		State.WALL:
			_phase_step(delta, 1.1, 0.6, 1.3, func() -> void:
				var hit := HitData.make(wall_damage, 0.0, self, Vector2(760, -340))
				hit.guardable = false
				hitbox.set_box(Rect2(0, -260, 200, 290), facing)
				hitbox.activate(hit, 0.6)
				velocity.x = facing * 1100.0
				Juice.shake(10.0)
				_red = false)
			if attack_phase == "active":
				if is_on_wall():
					velocity.x = 0.0
			else:
				velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
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


func _choose(dist: float) -> void:
	var fast := 0.7 if phase == 2 else 1.0
	if dist < 330.0:
		_begin(State.SWEEP, 0.5 * fast)
	elif phase == 2 and dist > 500.0 and randf() < 0.35:
		_red = true
		telegraph.emit("wall")
		_begin(State.WALL, 1.1)
	elif randf() < 0.55:
		_mark_spikes()
		_begin(State.SPIKES, 0.9 * fast)
	else:
		_begin(State.ORBS, 0.8 * fast)


func _mark_spikes() -> void:
	spike_marks.clear()
	if player == null:
		return
	var px := player.global_position.x
	if phase == 1:
		spike_marks = [px, px + facing * 220.0]
	else:
		spike_marks = [px - 260.0, px, px + 260.0, px + player.velocity.x * 0.6]


func _raise_spikes() -> void:
	for x in spike_marks:
		var sp := SPIKE.instantiate()
		sp.damage = spike_damage
		get_parent().add_child(sp)
		sp.global_position = Vector2(clampf(x, arena.position.x + 60.0, arena.end.x - 60.0), ground_y)
		sp.launch(Vector2.UP, self, false)
	spike_marks.clear()


func _spawn_orb(offset: float) -> void:
	var p: Projectile = PROJECTILE.instantiate()
	p.kind = Projectile.Kind.LEAF
	p.speed = 360.0 if phase == 1 else 440.0
	p.damage = orb_damage
	p.poise = 0.0
	p.lifetime = 4.0
	p.size = Vector2(40, 40)
	p.color = Color(0.6, 0.85, 1.0)
	p.homing = 1.6
	get_parent().add_child(p)
	p.global_position = global_position + Vector2(facing * 60.0, -220.0 + offset * 70.0)
	var dir := Vector2(facing, -0.2 + offset * 0.25).normalized()
	p.launch(dir, self, false)


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
		spike_marks.clear()
		_set_state(State.RISE)
		_timer = rise_len
		phase_changed.emit(2)
		telegraph.emit("rise")
		Juice.hitstop(0.2, 0.02)
		Juice.shake(14.0)
		return "hit"
	if poise >= max_poise and state != State.BROKEN:
		hitbox.deactivate()
		_set_state(State.BROKEN)
		_timer = broken_time
		Juice.hitstop(0.1, 0.05)
		Juice.shake(8.0)
	return "hit"


func on_just_guarded(_by: Player, amount: float) -> void:
	_flash = 1.0
	_add_poise(amount)
	if poise >= max_poise and state != State.BROKEN:
		hitbox.deactivate()
		_set_state(State.BROKEN)
		_timer = broken_time
	elif state == State.SWEEP:
		# 지팡이가 튕겼다: 그림만 짧게 휘청인다 (공격 길이·판정은 그대로)
		anim_hint = "stagger"
		_hint_timer = stagger_len
		stagger = 1.0


func _add_poise(amount: float) -> void:
	if amount <= 0.0:
		return
	poise = minf(poise + amount, max_poise)
	_poise_hold = 2.5
	poise_changed.emit(poise, max_poise)


func _fall() -> void:
	hitbox.deactivate()
	_unregister()
	spike_marks.clear()
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


func is_red() -> bool:
	return _red and state == State.WALL and attack_phase == "startup"


func is_ground() -> bool:
	return true


func state_name() -> String:
	return State.keys()[state]

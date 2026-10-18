extends CharacterBody2D
class_name LanternKnight
## 둘째 보스 '등불 기사'. 마을과 채굴장을 지키던 사람 기사. 마력 갑옷이 폭주해 괴물이 됨.
## 장중하고 무너져 가는 행진. 땅에서만 싸운다.
## 패턴: 창 찌르기(가드 가능, 긴 사거리) / 등불 휘두르기 → 땅을 달리는 불꽃 파도 / 내려찍기(붉은 예고, 가드 불가, 양쪽 충격)
## 2페이즈(체력 절반): 갑옷 폭주 — 빨라지고, 불꽃 파도 두 줄, 등불 던지기(포물선, 떨어진 자리에 불기둥).
## BossRoom 과 맞추는 약속: start_fight / reset_fight / arena / ground_y / fallen / purified / hp_changed / poise_changed / phase_changed / telegraph

## STAGGER: 2페이즈로 넘어가는 순간의 짧은 휘청(0.5초). 그 뒤 MARCH 로 이어진다.
enum State { WAIT, INTRO, MARCH, THRUST, FLAME, SLAM, THROW, BROKEN, FALLEN, PURIFIED, STAGGER }
const ATTACK_STATES := [State.THRUST, State.FLAME, State.SLAM, State.THROW]

signal hp_changed(hp: float, max_hp: float)
signal poise_changed(poise: float, max_poise: float)
signal phase_changed(phase: int)
signal state_changed(state: State)
signal fallen
signal purified
signal telegraph(kind: String)

@export var max_hp := 1100.0
@export var max_poise := 180.0
@export var poise_decay := 8.0
@export var broken_time := 4.5
@export var broken_damage_multiplier := 1.6
@export var march_speed := 170.0
@export var gravity := 2600.0
@export var thrust_damage := 22.0
@export var flame_damage := 18.0
@export var slam_damage := 30.0
@export var throw_damage := 24.0

var state: State = State.WAIT
var hp := 1100.0
var poise := 0.0
var phase := 1
var facing := -1
var player: Player
var arena: Rect2
var ground_y := 0.0
var attack_phase := ""   # startup / active / recovery (공격이 아니면 "")
var windup_progress := 0.0
## 지금 공격의 단계 길이(초). 그림이 진행도(남은 시간 / 길이)를 계산하는 데 쓴다. 2페이즈 배속이 있어도 모양이 같다.
var startup_len := 0.5
var active_len := 0.2
var recovery_len := 0.7
## 그림에 주는 힌트: "" / "stagger"(저스트 가드로 창이 튕김, 2페이즈 휘청)
var anim_hint := ""
## 2페이즈 전환 휘청 길이. 그 뒤 MARCH 0.7초 → 합쳐서 예전(1.2초)과 같다.
var stagger_len := 0.5
## 몸 돌리기 규칙: 소녀가 이만큼(px) 넘게 반대쪽에 있어야 돌고, 한 번 돌면 이 시간 동안은 다시 돌지 않는다.
## (행진 중 소녀 몸을 지나칠 때 매 프레임 뒤집혀 그림이 납작해졌다 펴지는 걸 막는다. 창 판정은 x 60부터라 영향 없음)
@export var face_deadzone := 40.0
@export var face_hold := 0.25
var _face_hold := 0.0
var _timer := 0.0
var _phase_timer := 0.0
var _poise_hold := 0.0
var _flash := 0.0
var _registered := false
var _home := Vector2.ZERO
var _combo := 0
var _red := false
var debug_log := false

@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
const PROJECTILE := preload("res://scenes/combat/projectile.tscn")


func _ready() -> void:
	add_to_group("boss")
	hp = max_hp
	_home = global_position
	visible = false


func start_fight(p: Player) -> void:
	player = p
	visible = true
	global_position = Vector2(arena.get_center().x + 500, ground_y)
	facing = -1
	_set_state(State.INTRO)
	_timer = 2.4


func reset_fight() -> void:
	_unregister()
	hp = max_hp
	poise = 0.0
	phase = 1
	visible = false
	velocity = Vector2.ZERO
	hitbox.deactivate()
	global_position = _home
	_set_state(State.WAIT)
	hp_changed.emit(hp, max_hp)
	poise_changed.emit(poise, max_poise)


func _physics_process(delta: float) -> void:
	if state == State.WAIT or state == State.PURIFIED:
		return
	_flash = maxf(_flash - delta * 6.0, 0.0)
	_poise_hold = maxf(_poise_hold - delta, 0.0)
	if _poise_hold <= 0.0 and poise > 0.0 and state != State.BROKEN and state != State.FALLEN:
		poise = maxf(poise - poise_decay * delta, 0.0)
		poise_changed.emit(poise, max_poise)
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0
	_timer -= delta
	_face_hold = maxf(_face_hold - delta, 0.0)
	var fast := 0.75 if phase == 2 else 1.0
	match state:
		State.INTRO:
			velocity.x = 0.0
			if _timer <= 0.0:
				_set_state(State.MARCH)
				_timer = 0.6
		State.MARCH:
			if player:
				var dx := player.global_position.x - global_position.x
				_update_facing(dx)
				velocity.x = move_toward(velocity.x, facing * march_speed * (1.3 if phase == 2 else 1.0), 900.0 * delta)
				if _timer <= 0.0:
					_choose_attack(absf(dx))
			else:
				velocity.x = 0.0
		State.THRUST:
			_phase_step(delta, 0.55 * fast, 0.18, 0.7 * fast, func() -> void:
				var hit := HitData.make(thrust_damage, 0.0, self, Vector2(520, -160))
				hitbox.set_box(Rect2(60, -150, 330, 110), facing)
				hitbox.activate(hit, 0.18)
				velocity.x = facing * 380.0)
			if attack_phase == "active":
				velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			else:
				velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
		State.FLAME:
			velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
			_phase_step(delta, 0.7 * fast, 0.2, 0.9 * fast, func() -> void:
				_spawn_flame_wave(facing)
				if phase == 2:
					get_tree().create_timer(0.35).timeout.connect(func() -> void:
						if state == State.FLAME or state == State.MARCH or state == State.STAGGER:
							_spawn_flame_wave(facing)))
		State.SLAM:
			velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
			_phase_step(delta, 1.0 * fast, 0.25, 1.2 * fast, func() -> void:
				var hit := HitData.make(slam_damage, 0.0, self, Vector2(700, -320))
				hit.guardable = false
				hit.hitstop = 0.08
				hitbox.set_box(Rect2(-300, -120, 600, 150), 1)
				hitbox.activate(hit, 0.25)
				Juice.shake(14.0)
				Juice.rumble(0.7, 1.0, 0.3)
				_red = false)
		State.THROW:
			velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
			_phase_step(delta, 0.6, 0.1, 1.0, func() -> void: _throw_lantern())
		State.STAGGER:
			# 갑옷이 폭주하며 잠깐 휘청인다 (뒤로 살짝 밀리며 멈춤)
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			if _timer <= 0.0:
				_set_state(State.MARCH)
				_timer = 1.2 - stagger_len
		State.BROKEN:
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			if _timer <= 0.0:
				poise = 0.0
				poise_changed.emit(poise, max_poise)
				_set_state(State.MARCH)
				_timer = 0.4
		State.FALLEN:
			velocity.x = 0.0
			_update_interactable()
	move_and_slide()


## 예고 → 실행 → 회복의 공통 흐름. on_active 는 실행 순간 한 번 불린다.
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
				_set_state(State.MARCH)
				_timer = (0.5 if phase == 1 else 0.3) + randf() * 0.3


## 소녀 쪽으로 몸을 돌린다 — 데드존 + 최소 유지 시간 (바로 옆을 지나쳐도 매 프레임 뒤집히지 않게).
func _update_facing(dx: float) -> void:
	var want := 1 if dx > 0.0 else -1
	if want != facing and absf(dx) > face_deadzone and _face_hold <= 0.0:
		facing = want
		_face_hold = face_hold


## 지금 공격 단계의 진행도 (0→1). 그림이 세 박자 곡선(예비→타격→되돌림)을 그리는 기준.
func phase_progress() -> float:
	match attack_phase:
		"startup": return clampf(windup_progress, 0.0, 1.0)
		"active": return 1.0 - clampf(_timer / maxf(active_len, 0.001), 0.0, 1.0)
		"recovery": return 1.0 - clampf(_timer / maxf(recovery_len, 0.001), 0.0, 1.0)
	return 0.0


## 지금 상태의 진행도 (0→1; STAGGER 같은 단순 상태용).
func state_progress(length: float) -> float:
	return 1.0 - clampf(_timer / maxf(length, 0.001), 0.0, 1.0)


func _begin(st: State, startup: float) -> void:
	_set_state(st)
	attack_phase = "startup"
	windup_progress = 0.0
	_timer = startup
	startup_len = startup


func _choose_attack(dist: float) -> void:
	var fast := 0.75 if phase == 2 else 1.0
	_combo += 1
	if dist < 420.0:
		if randf() < 0.3:
			_red = true
			telegraph.emit("slam")
			_begin(State.SLAM, 1.0 * fast)
		else:
			_begin(State.THRUST, 0.55 * fast)
	elif dist < 900.0:
		if phase == 2 and randf() < 0.35:
			_begin(State.THROW, 0.6)
		else:
			_begin(State.FLAME, 0.7 * fast)
	else:
		if phase == 2 and randf() < 0.5:
			_begin(State.THROW, 0.6)
		else:
			_begin(State.FLAME, 0.7 * fast)


func _spawn_flame_wave(dir: int) -> void:
	var p: Projectile = PROJECTILE.instantiate()
	p.kind = Projectile.Kind.GUST
	p.speed = 620.0
	p.damage = flame_damage
	p.poise = 0.0
	p.lifetime = 2.2
	p.size = Vector2(70, 48)
	p.color = Color(1.0, 0.6, 0.25)
	get_parent().add_child(p)
	p.global_position = global_position + Vector2(dir * 120.0, -30.0)
	p.launch(Vector2(dir, 0), self, false)


func _throw_lantern() -> void:
	if player == null:
		return
	var p: Projectile = PROJECTILE.instantiate()
	p.kind = Projectile.Kind.LEAF
	p.speed = 820.0
	p.damage = throw_damage
	p.poise = 0.0
	p.lifetime = 3.0
	p.fall_gravity = 1400.0
	p.size = Vector2(44, 44)
	p.color = Color(1.0, 0.7, 0.3)
	get_parent().add_child(p)
	p.global_position = global_position + Vector2(facing * 80.0, -170.0)
	var dx := player.global_position.x - global_position.x
	var dir := Vector2(dx, -600.0).normalized()
	p.launch(dir, self, false)
	p.tree_exited.connect(func() -> void: pass)
	# 떨어진 자리에 불기둥 (짧은 지연 뒤)
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if not is_instance_valid(p) or state == State.FALLEN or state == State.PURIFIED:
			return
		var pillar: Projectile = PROJECTILE.instantiate()
		pillar.kind = Projectile.Kind.GUST
		pillar.speed = 0.0
		pillar.damage = throw_damage
		pillar.poise = 0.0
		pillar.lifetime = 0.8
		pillar.size = Vector2(90, 160)
		pillar.color = Color(1.0, 0.55, 0.2)
		get_parent().add_child(pillar)
		pillar.global_position = Vector2(p.global_position.x, ground_y - 70.0)
		pillar.launch(Vector2.UP, self, false)
		p.queue_free())


func receive_hit(hit: HitData, _hb: Hurtbox) -> String:
	if state in [State.WAIT, State.INTRO, State.FALLEN, State.PURIFIED]:
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
		phase = 2
		phase_changed.emit(2)
		Juice.shake(10.0)
		hitbox.deactivate()
		# 공격 자세에서 곧바로 행진으로 '툭' 바뀌지 않게, 짧은 휘청을 거친다
		_set_state(State.STAGGER)
		anim_hint = "stagger"
		_timer = stagger_len
		velocity.x = -facing * 160.0
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
	elif state == State.THRUST:
		# 창이 튕겨 나간다: 긴 회복 + 뒤로 밀림. 그림은 "stagger" 힌트로 뒤로 젖히며 출렁인다.
		hitbox.deactivate()
		attack_phase = "recovery"
		_timer = 1.1
		recovery_len = 1.1
		anim_hint = "stagger"
		velocity.x = -facing * 240.0


func _add_poise(amount: float) -> void:
	if amount <= 0.0:
		return
	poise = minf(poise + amount, max_poise)
	_poise_hold = 2.5
	poise_changed.emit(poise, max_poise)


func _fall() -> void:
	hitbox.deactivate()
	_unregister()
	_set_state(State.FALLEN)
	Juice.hitstop(0.15, 0.03)
	Juice.shake(12.0)
	fallen.emit()


func _update_interactable() -> void:
	if player == null:
		return
	var near := absf(player.global_position.x - global_position.x) < 240.0 and absf(player.global_position.y - global_position.y) < 200.0
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
		print("[기사] %s → %s" % [State.keys()[state], State.keys()[new_state]])
	state = new_state
	anim_hint = ""
	if new_state not in ATTACK_STATES:
		attack_phase = ""
	state_changed.emit(new_state)


func flash_amount() -> float:
	return _flash


func is_red() -> bool:
	return _red and state == State.SLAM and attack_phase == "startup"


func is_ground() -> bool:
	return true


func state_name() -> String:
	return State.keys()[state]

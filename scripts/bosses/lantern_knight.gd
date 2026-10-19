extends CharacterBody2D
class_name LanternKnight
## 둘째 보스 '등불 기사'. 마을과 채굴장을 지키던 사람 기사. 마력 갑옷이 폭주해 괴물이 됨.
## 장중하고 무너져 가는 행진. 땅에서만 싸운다.
## 패턴 (1페이즈부터):
##  - 창 찌르기 THRUST (가드 가능, 긴 사거리; 저스트 가드로 창이 튕김)
##  - 등불 휘두르기 FLAME → 땅을 달리는 불꽃 파도
##  - 내려찍기 SLAM (붉은 예고, 가드 불가, 소녀 쪽으로 도약해 양쪽 충격)
##  - 검기 WAVE: 창을 크게 베어 빛의 베기(SwordWave)를 날린다. 가드 가능, 저스트 가드로 되받으면 기사에게 돌아가 흐트러짐 +40
##    (소녀가 높은 가지 위에 1초 넘게 머물면 검기를 소녀 쪽으로 비스듬히 올려 쏜다 — 가지 위가 안전지대가 되지 않게)
##  - 3연격 COMBO3: 찌르기 → 휘두르기 → 올려치기(붉은 예고 0.5초, 가드 불가). 앞 두 타 사이 0.25초
##  - 돌진 찌르기 CHARGE: 뒤로 물러났다 아레나를 가로지른다(가드 가능). 끝에 닿으면 창이 박혀 STUCK 2.0초 무방비(피해 1.3배).
##    박힌 동안 무너지면 무너짐은 남은 박힘 시간만큼만(최소 1초) — 돌진 한 번에 공짜 시간이 5초 넘게 되지 않게
## 2페이즈(체력 절반): 갑옷 폭주 — 예고 0.75배, 쉬는 시간 0.3초, 불꽃 파도 두 줄, 검기 3갈래, 등불 던지기 THROW(떨어진 자리 불기둥),
##  등불 회전 SPIN(불꽃 고리 3겹이 0.38초 간격으로 양쪽으로 퍼짐 — 차례로 점프해 넘긴다), 연계(찌르기→검기, 검기→돌진).
## 패턴 고르기: 거리·페이즈별 가중치, 같은 패턴 연속 2회 금지.
## BossRoom 과 맞추는 약속: start_fight / reset_fight / arena / ground_y / fallen / purified / hp_changed / poise_changed / phase_changed / telegraph / telegraph_label

## STAGGER: 2페이즈로 넘어가는 순간의 짧은 휘청(0.5초). STUCK: 돌진 창이 벽에 박힘(무방비).
enum State { WAIT, INTRO, MARCH, THRUST, FLAME, SLAM, THROW, BROKEN, FALLEN, PURIFIED, STAGGER, WAVE, COMBO3, CHARGE, STUCK, SPIN }
const ATTACK_STATES := [State.THRUST, State.FLAME, State.SLAM, State.THROW, State.WAVE, State.COMBO3, State.CHARGE, State.SPIN]

signal hp_changed(hp: float, max_hp: float)
signal poise_changed(poise: float, max_poise: float)
signal phase_changed(phase: int)
signal state_changed(state: State)
signal fallen
signal purified
signal telegraph(kind: String)

@export var max_hp := 1650.0
## 흐트러짐 한도·무너짐 길이 (2026-10-19 검수: 180 / 4.5초면 공격 버튼만 눌러도 싸움 시간 절반 넘게 무너져 있었다 — '샌드백')
@export var max_poise := 300.0
@export var poise_decay := 8.0
@export var broken_time := 3.0
@export var broken_damage_multiplier := 1.6
## 예비동작·타격 중에 받는 흐트러짐 배수 (슈퍼아머: 공격 도중에 두들겨 끊기 어렵게)
@export var attack_poise_multiplier := 0.5
## 무너졌다 일어선 뒤 이 시간(초) 동안은 흐트러짐이 쌓이지 않는다 (저스트 가드는 예외 — 기술의 보상은 그대로)
@export var poise_immune_after_broken := 2.5
@export var march_speed := 170.0
@export var gravity := 2600.0
@export var thrust_damage := 22.0
@export var flame_damage := 18.0
@export var slam_damage := 30.0
@export var throw_damage := 24.0
@export var wave_damage := 18.0
## 3연격 각 타의 피해 (찌르기 / 휘두르기 / 올려치기)
@export var combo_damages: Array[float] = [16.0, 18.0, 24.0]
@export var charge_damage := 22.0
@export var charge_speed := 1250.0
## 창이 박힌 뒤 무방비 시간
@export var stuck_len := 2.0
@export var stuck_damage_multiplier := 1.3
## 박힌 동안 흐트러짐 배수 (2.0 이면 박힘 → 무너짐 4.5초로 이어져 공짜 시간이 5.5초가 됐다 → 1.0)
@export var stuck_poise_multiplier := 1.0
## 박힌 동안 무너지면 무너짐 시간 = 남은 박힘 시간 (이 값보다 짧지는 않게)
@export var stuck_broken_min := 1.0
@export var spin_damage := 16.0
@export var ring_damage := 14.0
## 등불 회전의 불꽃 고리: 속도(모두 같게 — 뒤 고리가 앞 고리를 따라잡아 한 겹으로 겹치지 않게)와 내보내는 간격(초)
@export var ring_speed := 520.0
@export var ring_interval := 0.38
@export var spin_active := 0.8
## 높은 곳 견제: 소녀(몸 중심)가 바닥보다 이만큼 넘게 위에 이 시간 넘게 있으면 검기를 소녀 쪽으로 올려 쏜다
@export var high_height := 280.0
@export var high_time := 1.0

var state: State = State.WAIT
var hp := 1650.0
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
## 그림에 주는 힌트: "" / "stagger"(저스트 가드로 창이 튕김, 2페이즈 휘청) / "stuck"(창이 박힘)
var anim_hint := ""
## 2페이즈 전환 휘청 길이. 그 뒤 MARCH 0.7초 → 합쳐서 예전(1.2초)과 같다.
var stagger_len := 0.5
## 3연격의 지금 타 (0 찌르기, 1 휘두르기, 2 올려치기)
var combo_step := 0
## 등불 회전에서 지금까지 내보낸 고리 수 (0~3)
var rings_sent := 0
## 몸 돌리기 규칙: 소녀가 이만큼(px) 넘게 반대쪽에 있어야 돌고, 한 번 돌면 이 시간 동안은 다시 돌지 않는다.
## (행진 중 소녀 몸을 지나칠 때 매 프레임 뒤집혀 그림이 납작해졌다 펴지는 걸 막는다. 창 판정은 x 60부터라 영향 없음)
@export var face_deadzone := 40.0
@export var face_hold := 0.25
var _face_hold := 0.0
var _timer := 0.0
var _phase_timer := 0.0
var _poise_hold := 0.0
var _poise_immune := 0.0
var _flash := 0.0
var _registered := false
var _home := Vector2.ZERO
var _combo := 0
var _red := false
var _leapt := false
var _wave_sent := false
var _wave_aim_up := false
var _high_time := 0.0
var _last_attack: int = -1
var debug_log := false

@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
const PROJECTILE := preload("res://scenes/combat/projectile.tscn")
const SWORD_WAVE := preload("res://scenes/bosses/sword_wave.tscn")

## 3연격 각 타의 예비 / 타격 / 되돌림 길이 (마지막 타는 붉은 예고)
## (마지막 올려치기 예비 0.5초: 가드 불가 붉은 예고는 공통 기준 0.45초 이상. 2페이즈에도 줄이지 않는다)
const COMBO_STARTUP := [0.45, 0.25, 0.5]
const COMBO_ACTIVE := [0.16, 0.18, 0.2]
const COMBO_RECOVERY := [0.08, 0.08, 0.9]


func _ready() -> void:
	add_to_group("boss")
	hp = max_hp
	_home = global_position
	visible = false
	# 창(내 Hitbox)이 저스트 가드로 막혔을 때만 창이 튕긴다 (투사체 저스트 가드와 구분)
	hitbox.landed.connect(_on_spear_landed)


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
	_poise_immune = 0.0
	for m in get_tree().get_nodes_in_group("knight_pillar_mark"):
		m.queue_free()
	phase = 1
	visible = false
	velocity = Vector2.ZERO
	hitbox.deactivate()
	global_position = _home
	_last_attack = -1
	_high_time = 0.0
	_wave_aim_up = false
	_set_state(State.WAIT)
	hp_changed.emit(hp, max_hp)
	poise_changed.emit(poise, max_poise)


func _physics_process(delta: float) -> void:
	if state == State.WAIT or state == State.PURIFIED:
		return
	_flash = maxf(_flash - delta * 6.0, 0.0)
	_poise_hold = maxf(_poise_hold - delta, 0.0)
	_poise_immune = maxf(_poise_immune - delta, 0.0)
	if _poise_hold <= 0.0 and poise > 0.0 and state != State.BROKEN and state != State.FALLEN:
		poise = maxf(poise - poise_decay * delta, 0.0)
		poise_changed.emit(poise, max_poise)
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0
	_timer -= delta
	_face_hold = maxf(_face_hold - delta, 0.0)
	# 소녀가 높은 가지 위에 머문 시간 (점프 한 번은 1초가 안 돼 쌓이지 않는다)
	if player and ground_y - player.global_position.y > high_height:
		_high_time += delta
	else:
		_high_time = 0.0
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
				# 앞 450 은 그림의 창끝 자리. 뒤끝은 몸 안쪽(-20)까지 — 몸에 바짝 붙으면 안전하던 자리를 없앤다 (2026-10-19 검수)
				hitbox.set_box(Rect2(-20, -150, 470, 110), facing)
				hitbox.activate(hit, 0.18)
				velocity.x = facing * 380.0
				Sfx.play("spear_whoosh", -4.0, 0.08),
				func() -> void:
					# 2페이즈 연계: 찌르기 → 검기 (저스트 가드로 창이 튕겼으면 연계 없이 행진 — 튕김 보상이 줄지 않게)
					if anim_hint != "stagger" and phase == 2 and randf() < 0.45:
						_start_attack(State.WAVE)
					else:
						_to_march())
			if attack_phase == "active":
				velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			else:
				velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
		State.FLAME:
			velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
			_phase_step(delta, 0.7 * fast, 0.2, 0.9 * fast, func() -> void:
				_spawn_flame_wave(facing)
				Sfx.play("spear_whoosh", -3.0, 0.08)
				if phase == 2:
					get_tree().create_timer(0.35).timeout.connect(func() -> void:
						if state == State.FLAME or state == State.MARCH or state == State.STAGGER:
							_spawn_flame_wave(facing)),
				func() -> void:
					# 연계: 소녀가 가까이 붙어 있으면 바로 찌른다
					if player and absf(player.global_position.x - global_position.x) < 420.0 and randf() < 0.35:
						_start_attack(State.THRUST)
					else:
						_to_march())
		State.SLAM:
			# 예비 30% 지점에서 소녀 쪽으로 도약: 남은 예비 시간에 꼭 맞게 떨어지도록 속도를 계산한다
			if attack_phase == "startup" and not _leapt and windup_progress >= 0.3 and is_on_floor():
				_leapt = true
				var T := maxf(_timer, 0.2)
				var target_x := global_position.x
				if player:
					target_x = clampf(player.global_position.x, arena.position.x + 150.0, arena.end.x - 150.0)
				velocity = Vector2(clampf((target_x - global_position.x) / T, -720.0, 720.0), -gravity * T * 0.5)
				Sfx.play("jump", -6.0, 0.1)
			elif attack_phase == "startup" and _leapt and not is_on_floor():
				pass   # 공중: 가로 속도 유지
			else:
				velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
			_phase_step(delta, 1.0 * fast, 0.25, 1.2 * fast, func() -> void:
				var hit := HitData.make(slam_damage, 0.0, self, Vector2(700, -320))
				hit.guardable = false
				hit.hitstop = 0.08
				hitbox.set_box(Rect2(-300, -120, 600, 150), 1)
				hitbox.activate(hit, 0.25)
				if not is_on_floor():
					velocity.y = maxf(velocity.y, 900.0)
				velocity.x = 0.0
				Juice.shake(14.0)
				Juice.rumble(0.7, 1.0, 0.3)
				Sfx.play("heavy_hit", -2.0, 0.05)
				_red = false)
		State.THROW:
			velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
			_phase_step(delta, 0.6, 0.1, 1.0, func() -> void: _throw_lantern())
		State.WAVE:
			velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
			_phase_step(delta, 0.65 * fast, 0.22, 0.8 * fast, func() -> void:
				var hit := HitData.make(wave_damage, 0.0, self, Vector2(480, -200))
				hitbox.set_box(Rect2(0, -290, 360, 310), facing)
				hitbox.activate(hit, 0.2)
				_wave_sent = false
				Sfx.play("spear_whoosh", -4.0, 0.08),
				func() -> void:
					# 2페이즈 연계: 검기 → 돌진 (멀리 있을 때)
					if phase == 2 and player and absf(player.global_position.x - global_position.x) > 500.0 and randf() < 0.35:
						_start_attack(State.CHARGE)
					else:
						_to_march())
			# 검기는 창이 앞을 지나는 순간(타격 25%)에 날아간다 — 그림과 맞춘다
			if attack_phase == "active" and not _wave_sent and phase_progress() >= 0.25:
				_wave_sent = true
				_spawn_sword_waves()
				Juice.shake(5.0)
				Sfx.play("sword_wave", -2.0, 0.06)
		State.COMBO3:
			# 타마다 조금씩 앞으로 밀고 들어간다
			var push := 240.0 if attack_phase == "active" else 0.0
			velocity.x = move_toward(velocity.x, facing * push, 2600.0 * delta)
			var s := combo_step
			_phase_step(delta, COMBO_STARTUP[s] * (fast if s == 0 else 1.0), COMBO_ACTIVE[s], COMBO_RECOVERY[s] * (fast if s == 2 else 1.0),
				_combo_hit, _combo_next)
		State.CHARGE:
			match attack_phase:
				"startup":
					velocity.x = move_toward(velocity.x, -facing * 150.0, 1400.0 * delta)
				"active":
					velocity.x = facing * charge_speed
					var edge := (arena.end.x - 130.0) if facing > 0 else (arena.position.x + 130.0)
					if (facing > 0 and global_position.x >= edge) or (facing < 0 and global_position.x <= edge) or is_on_wall():
						_stick()
				_:
					velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
			if state == State.CHARGE:
				_phase_step(delta, 0.75 * fast, 2.6, 0.5, func() -> void:
					var hit := HitData.make(charge_damage, 0.0, self, Vector2(560, -220))
					hit.hitstop = 0.06
					hitbox.set_box(Rect2(40, -170, 380, 130), facing)
					hitbox.activate(hit, 2.6)
					Sfx.play("charge_dash", -2.0, 0.05))
		State.STUCK:
			velocity.x = 0.0
			if _timer <= 0.0:
				hitbox.deactivate()
				_set_state(State.MARCH)
				_timer = 0.5 if phase == 1 else 0.35
		State.SPIN:
			velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
			_phase_step(delta, 0.8 * fast, spin_active, 0.7 * fast, func() -> void:
				var hit := HitData.make(spin_damage, 0.0, self, Vector2(420, -200))
				hitbox.set_box(Rect2(-230, -330, 460, 350), 1)
				hitbox.activate(hit, spin_active)
				rings_sent = 0
				Sfx.play("spear_whoosh", -3.0, 0.1))
			# 타격 시작부터 ring_interval 초마다 불꽃 고리 한 겹씩 (타이머 없이 상태 기계로 — 시험에서도 돈다)
			if attack_phase == "active":
				var elapsed := active_len - _timer
				while rings_sent < 3 and elapsed >= rings_sent * ring_interval - 0.001:
					_spawn_ring(rings_sent)
					rings_sent += 1
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
				_poise_immune = poise_immune_after_broken
				_set_state(State.MARCH)
				_timer = 0.4
		State.FALLEN:
			velocity.x = 0.0
			_update_interactable()
	move_and_slide()


## 예고 → 실행 → 회복의 공통 흐름. on_active 는 실행 순간 한 번, on_done 은 회복이 끝날 때 한 번 불린다(없으면 행진으로).
func _phase_step(delta: float, startup: float, active: float, recovery: float, on_active: Callable, on_done := Callable()) -> void:
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
				if on_done.is_valid():
					on_done.call()
				else:
					_to_march()


func _to_march() -> void:
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


## 지금 상태의 진행도 (0→1; STAGGER·STUCK 같은 단순 상태용).
func state_progress(length: float) -> float:
	return 1.0 - clampf(_timer / maxf(length, 0.001), 0.0, 1.0)


func _begin(st: State, startup: float) -> void:
	_set_state(st)
	attack_phase = "startup"
	windup_progress = 0.0
	_timer = startup
	startup_len = startup
	_leapt = false


## 거리·페이즈별 가중치로 패턴을 고른다. 같은 패턴은 연속 2회 금지.
func _choose_attack(dist: float) -> void:
	_combo += 1
	var pool := {}
	_wave_aim_up = false
	# 공격을 고르는 순간에는 데드존 없이 소녀 쪽으로 돌아선다 (등 뒤·몸 안에 붙어 있으면 영영 돌지 않아 안전지대가 됐다)
	if player and absf(player.global_position.x - global_position.x) > 4.0:
		var want := 1 if player.global_position.x > global_position.x else -1
		if want != facing:
			facing = want
			_face_hold = face_hold
	if _high_time > high_time:
		# 소녀가 높은 가지 위에서 버틴다: 검기를 소녀 쪽으로 올려 쏜다 (2페이즈는 등불 던지기도)
		# (같은 패턴 연속 금지보다 우선 — 버티는 동안은 검기가 이어질 수 있다)
		pool[State.WAVE] = 4.0
		if phase == 2:
			pool[State.THROW] = 2.0
			pool.erase(_last_attack)
			if pool.is_empty():
				pool[State.WAVE] = 1.0
		var pick := _weighted_pick(pool)
		_wave_aim_up = pick == State.WAVE
		_start_attack(pick)
		return
	if dist < 420.0:
		pool[State.THRUST] = 3.0
		pool[State.COMBO3] = 3.0
		pool[State.SLAM] = 2.0
		if phase == 2:
			pool[State.SPIN] = 2.5
	elif dist < 900.0:
		pool[State.FLAME] = 3.0
		pool[State.WAVE] = 3.0
		pool[State.SLAM] = 1.5
		pool[State.COMBO3] = 1.0
		pool[State.CHARGE] = 2.0
		if phase == 2:
			pool[State.THROW] = 2.0
			pool[State.SPIN] = 1.0
	else:
		pool[State.FLAME] = 2.0
		pool[State.WAVE] = 3.0
		pool[State.CHARGE] = 3.5
		if phase == 2:
			pool[State.THROW] = 2.5
	if pool.size() > 1:
		pool.erase(_last_attack)
	_start_attack(_weighted_pick(pool))


func _weighted_pick(pool: Dictionary) -> State:
	var total := 0.0
	for k in pool:
		total += pool[k]
	var r := randf() * total
	for k in pool:
		r -= pool[k]
		if r <= 0.0:
			return k
	return pool.keys()[pool.size() - 1]


## 패턴 하나를 시작한다 (연계에서도 쓴다). 2페이즈는 예고 0.75배.
func _start_attack(st: State) -> void:
	var fast := 0.75 if phase == 2 else 1.0
	_last_attack = st
	match st:
		State.THRUST:
			_begin(State.THRUST, 0.55 * fast)
		State.SLAM:
			_red = true
			telegraph.emit("slam")
			_begin(State.SLAM, 1.0 * fast)
		State.FLAME:
			_begin(State.FLAME, 0.7 * fast)
		State.THROW:
			_begin(State.THROW, 0.6)
		State.WAVE:
			telegraph.emit("wave")
			_begin(State.WAVE, 0.65 * fast)
		State.COMBO3:
			combo_step = 0
			_begin(State.COMBO3, COMBO_STARTUP[0] * fast)
		State.CHARGE:
			telegraph.emit("charge")
			_begin(State.CHARGE, 0.75 * fast)
		State.SPIN:
			rings_sent = 0
			telegraph.emit("spin")
			_begin(State.SPIN, 0.8 * fast)
		_:
			_to_march()


## 시험·연출용: 다음 행진에서 고르지 않고 이 패턴을 바로 건다.
func force_attack(st: State) -> void:
	if state in [State.WAIT, State.INTRO, State.FALLEN, State.PURIFIED]:
		return
	hitbox.deactivate()
	_start_attack(st)


func _combo_hit() -> void:
	var dmg: float = combo_damages[combo_step]
	match combo_step:
		0:
			var hit := HitData.make(dmg, 0.0, self, Vector2(420, -140))
			hitbox.set_box(Rect2(-20, -150, 470, 110), facing)
			hitbox.activate(hit, COMBO_ACTIVE[0])
			velocity.x = facing * 320.0
			Sfx.play("spear_whoosh", -5.0, 0.1)
		1:
			var hit := HitData.make(dmg, 0.0, self, Vector2(460, -200))
			hitbox.set_box(Rect2(-40, -240, 380, 270), facing)
			hitbox.activate(hit, COMBO_ACTIVE[1])
			Sfx.play("spear_whoosh", -3.0, 0.1)
		2:
			var hit := HitData.make(dmg, 0.0, self, Vector2(380, -560))
			hit.guardable = false
			hit.hitstop = 0.07
			hitbox.set_box(Rect2(0, -330, 320, 350), facing)
			hitbox.activate(hit, COMBO_ACTIVE[2])
			velocity.x = facing * 200.0
			_red = false
			Juice.shake(9.0)
			Juice.rumble(0.5, 0.9, 0.2)
			Sfx.play("spear_whoosh", 0.0, 0.08)


## 3연격: 되돌림이 끝나면 다음 타로. 마지막 타(올려치기)는 붉은 예고.
func _combo_next() -> void:
	if combo_step >= 2:
		_to_march()
		return
	combo_step += 1
	attack_phase = "startup"
	windup_progress = 0.0
	_timer = COMBO_STARTUP[combo_step]
	startup_len = _timer
	if combo_step == 2:
		_red = true
		telegraph.emit("combo3")


## 돌진 창이 아레나 끝(벽)에 박힌다: STUCK 동안 무방비.
func _stick() -> void:
	hitbox.deactivate()
	velocity.x = 0.0
	_set_state(State.STUCK)
	anim_hint = "stuck"
	_timer = stuck_len
	Juice.shake(10.0)
	Juice.rumble(0.6, 1.0, 0.25)
	Sfx.play("spear_stuck", -1.0, 0.04)


func _spawn_flame_wave(dir: int) -> void:
	var p: Projectile = PROJECTILE.instantiate()
	p.kind = Projectile.Kind.GUST
	p.speed = 620.0
	p.damage = flame_damage
	p.poise = 0.0
	p.lifetime = 2.2
	p.size = Vector2(70, 48)
	p.color = Color(1.0, 0.6, 0.25)
	_flame_look(p, 1.6)
	get_parent().add_child(p)
	p.global_position = global_position + Vector2(dir * 120.0, -30.0)
	p.launch(Vector2(dir, 0), self, false)


## 검기: 1페이즈 한 갈래(땅을 따라), 2페이즈 세 갈래(땅 + 비스듬히 위 둘).
## 높은 곳 견제(_wave_aim_up)면 소녀 쪽으로 올려 쏜다 (2페이즈는 그 둘레로 세 갈래).
## 생기는 자리가 벽·안개 문 너머면(기사→생기는 자리 사이가 지형에 막히면) 막힌 자리 앞에서 만들고, 그럴 틈도 없으면 쏘지 않는다.
func _spawn_sword_waves() -> void:
	var dirs: Array[Vector2] = []
	var starts: Array[Vector2] = []
	if _wave_aim_up and player:
		var origin := Vector2(global_position.x + facing * 60.0, ground_y - 230.0)
		var to := player.global_position - origin
		var base := Vector2(facing, 0).angle_to(to) if to.length() > 1.0 else -1.2 * facing
		# 앞 위쪽(수평 ~ 거의 수직)으로만
		base = clampf(base * facing, -1.45, 0.0) * facing
		var spread := [0.0] if phase == 1 else [0.0, -0.2, 0.2]
		for a in spread:
			dirs.append(Vector2(facing, 0).rotated(base + float(a) * facing))
			starts.append(origin)
	else:
		var angles := [0.0] if phase == 1 else [0.0, -0.24, -0.48]
		for a in angles:
			dirs.append(Vector2(facing, 0).rotated(float(a) * facing))
			starts.append(Vector2(global_position.x + facing * 150.0, ground_y - 75.0 - (0.0 if a == 0.0 else 40.0)))
	var space := get_world_2d().direct_space_state
	for i in dirs.size():
		var pos := starts[i]
		# 기사 몸 → 생기는 자리 사이에 벽·문(한쪽 발판 말고)이 있으면 그 앞으로 당긴다
		var ray := PhysicsRayQueryParameters2D.create(Vector2(global_position.x, pos.y), pos, 1)
		ray.exclude = [get_rid()]
		var hit := space.intersect_ray(ray)
		if not hit.is_empty() and not SwordWave.passes_through(hit.get("collider")):
			pos = hit["position"] - Vector2(facing * 50.0, 0)
			if (pos.x - global_position.x) * facing < 10.0:
				continue
		var w: SwordWave = SWORD_WAVE.instantiate()
		w.damage = wave_damage
		w.speed = 760.0 if phase == 1 else 840.0
		get_parent().add_child(w)
		w.global_position = pos
		w.launch(dirs[i], self, false)


## 등불 회전의 불꽃 고리 한 겹: 양쪽으로 낮게 퍼진다 (모두 같은 속도 — 간격이 그대로 유지돼 차례로 넘는다). 점프로 넘긴다.
func _spawn_ring(i: int) -> void:
	for dir in [-1, 1]:
		var p: Projectile = PROJECTILE.instantiate()
		p.kind = Projectile.Kind.GUST
		p.speed = ring_speed
		p.damage = ring_damage
		p.poise = 0.0
		p.lifetime = 2.2
		p.size = Vector2(84, 42)
		p.color = Color(1.0, 0.55 + 0.1 * i, 0.2)
		_flame_look(p, 1.6)
		get_parent().add_child(p)
		p.global_position = Vector2(global_position.x + dir * 90.0, ground_y - 28.0)
		p.launch(Vector2(dir, 0), self, false)
	Juice.shake(4.0)


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
	p.pass_one_way = true   # 가운데 가지에 걸리지 않고 소녀 발밑 바닥까지 떨어진다
	get_parent().add_child(p)
	p.global_position = global_position + Vector2(facing * 80.0, -170.0)
	# 가까우면 느리게 던진다 (속력이 일정한 투사체라 820 으로는 꼭대기에서 수평으로 멀리 미끄러져 300px 넘게 지나쳤다)
	var aim := _aim_lantern(p.global_position, player.global_position.x, p.fall_gravity, p.lifetime)
	p.speed = aim[1]
	p.launch(aim[0], self, false)
	Sfx.play("spear_whoosh", -5.0, 0.1)
	# 등불이 땅·가지에 떨어진 바로 그 자리에 불기둥 (붉은 예고 PILLAR_WARN 초 뒤).
	# 예전엔 0.9초 고정 타이머가 '그 순간 공중의 등불 아래'에 세웠고, 그 전에 떨어지면 아예 안 생겼다 (2026-10-19 검수).
	p.landed.connect(_on_lantern_landed)


## 불꽃(파도·고리·불기둥) 그림: 기사 몸과 같은 주황이라 바닥을 달리는 작은 초승달이 몸에 섞여 안 보였다 (2026-10-19 검수)
## → 그림만 키우고(판정 그대로) 밝은 노란 테두리와 발광.
func _flame_look(p: Projectile, scale_k: float) -> void:
	p.draw_scale = scale_k
	p.outline_color = Color(1.0, 0.95, 0.6, 1.0)
	p.glow = 1.2


## 등불을 던질 방향: 투사체는 속력이 일정하고 방향만 아래로 휘므로(포물선이 아니다) 예전처럼 (dx, -600) 으로 던지면
## 가까운 소녀 너머 1000px 까지 날아갔다 → 몇 가지 각도로 날아가는 길을 미리 그려 보고 바닥(ground_y)에 떨어지는 자리가
## 소녀와 가장 가까운 각도를 고른다 (같으면 높은 포물선).
## 돌려주는 값: [방향, 속력]. 속력은 820 → 640 → 500 차례로 보고 충분히 가까우면(80px) 빠른 쪽을 쓴다.
func _aim_lantern(from: Vector2, target_x: float, grav: float, life: float) -> Array:
	var side := 1.0 if target_x >= from.x else -1.0
	var best := [Vector2(side * 0.38, -0.92), 820.0]
	var best_err := INF
	var dt := 1.0 / 30.0
	for speed in [820.0, 640.0, 500.0]:
		for i in 15:
			var up := deg_to_rad(84.0 - i * 4.5)   # 84° ~ 21° (수평에서 위로)
			var d := Vector2(cos(up) * side, -sin(up))
			var pos := from
			var dirv := d
			var t := 0.0
			while t < life and pos.y < ground_y:
				dirv = (dirv * speed + Vector2(0, grav * dt)).normalized()
				pos += dirv * speed * dt
				t += dt
			var err := absf(pos.x - target_x)
			if err < best_err - 1.0:
				best_err = err
				best = [d, speed]
		if best_err < 80.0:
			break
	return best


## 불기둥 붉은 예고 길이(초)
const PILLAR_WARN := 0.3


## 던진 등불이 지형에 닿았다: 바닥 같은 면이면 그 자리, 벽에 부딪혔으면 그 아래 바닥(싸움터 안)에 예고 → 불기둥.
func _on_lantern_landed(pos: Vector2, normal: Vector2) -> void:
	if state == State.FALLEN or state == State.PURIFIED or state == State.WAIT:
		return
	var at := pos
	if normal.y > -0.5:
		at = Vector2(clampf(pos.x, arena.position.x + 60.0, arena.end.x - 60.0), ground_y)
	var mark := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * 62.0, sin(a) * 14.0))
	mark.polygon = pts
	mark.color = Color(1.0, 0.25, 0.12, 0.0)
	mark.add_to_group("knight_pillar_mark")
	get_parent().add_child(mark)
	mark.global_position = at
	var tw := mark.create_tween()
	tw.tween_property(mark, "color:a", 0.75, PILLAR_WARN * 0.6)
	tw.parallel().tween_property(mark, "scale", Vector2(1.25, 1.25), PILLAR_WARN).from(Vector2(0.6, 0.6))
	get_tree().create_timer(PILLAR_WARN, false).timeout.connect(_spawn_pillar.bind(at, mark))


func _spawn_pillar(at: Vector2, mark: Node) -> void:
	if is_instance_valid(mark):
		mark.queue_free()
	if state == State.FALLEN or state == State.PURIFIED or state == State.WAIT:
		return
	var pillar: Projectile = PROJECTILE.instantiate()
	pillar.kind = Projectile.Kind.GUST
	pillar.speed = 0.0
	pillar.damage = throw_damage
	pillar.poise = 0.0
	pillar.lifetime = 0.8
	pillar.size = Vector2(90, 160)
	pillar.color = Color(1.0, 0.55, 0.2)
	_flame_look(pillar, 1.3)
	get_parent().add_child(pillar)
	pillar.global_position = at + Vector2(0, -70.0)
	pillar.launch(Vector2.UP, self, false)
	Juice.shake(4.0)


func receive_hit(hit: HitData, _hb: Hurtbox) -> String:
	if state in [State.WAIT, State.INTRO, State.FALLEN, State.PURIFIED]:
		return "ignored"
	_flash = 1.0
	var mult := 1.0
	var poise_mult := 1.0
	if state == State.BROKEN:
		mult = broken_damage_multiplier
	elif state == State.STUCK:
		mult = stuck_damage_multiplier
		poise_mult = stuck_poise_multiplier
	# 슈퍼아머·무너짐 뒤 면역은 보통 공격에만 (저스트 가드로 되받은 검기·불꽃은 기술의 보상이라 그대로 들어간다)
	if not hit.reflected and state in ATTACK_STATES and attack_phase in ["startup", "active"]:
		poise_mult *= attack_poise_multiplier
	hp = maxf(hp - hit.damage * mult, 0.0)
	hp_changed.emit(hp, max_hp)
	if _poise_immune <= 0.0 or hit.reflected:
		_add_poise(hit.poise * poise_mult)
	if hp <= 0.0:
		_fall()
		return "hit"
	if phase == 1 and hp <= max_hp * 0.5:
		phase = 2
		phase_changed.emit(2)
		Juice.shake(10.0)
		hitbox.deactivate()
		# 흐트러짐을 비운다: 무너진 채 절반을 넘기면 휘청 뒤 곧바로 무너짐 4.5초가 새로 시작돼 공짜 시간이 9초 가까이 됐다
		poise = 0.0
		_poise_hold = 0.0
		poise_changed.emit(poise, max_poise)
		# 공격 자세에서 곧바로 행진으로 '툭' 바뀌지 않게, 짧은 휘청을 거친다
		_set_state(State.STAGGER)
		anim_hint = "stagger"
		_timer = stagger_len
		velocity.x = -facing * 160.0
	if poise >= max_poise and state != State.BROKEN:
		hitbox.deactivate()
		_enter_broken()
		Juice.hitstop(0.1, 0.05)
		Juice.shake(8.0)
	return "hit"


## 소녀가 내 공격(창이든 불꽃 파도 같은 투사체든 — 출처가 나인 HitData)을 저스트 가드했다: 흐트러짐만 쌓는다.
## 창이 튕기는 건 창(내 Hitbox)이 막혔을 때만 — _on_spear_landed. (검기는 출처가 검기 자신이라 여기 오지 않는다:
##  멀리서 날아온 검기를 막았다고 돌진이 끊기거나, 되받기 흐트러짐이 +45 더 붙지 않게)
func on_just_guarded(_by: Player, amount: float) -> void:
	_flash = 1.0
	_add_poise(amount)
	if poise >= max_poise and state != State.BROKEN:
		hitbox.deactivate()
		_enter_broken()


## 내 Hitbox(창)가 상대를 맞힌 결과. 저스트 가드면 창이 튕긴다.
func _on_spear_landed(result: String, _target: Node) -> void:
	if result == "just_guard":
		_spear_parried()


## 창이 저스트 가드에 튕김: 찌르기·3연격 앞 두 타는 긴 회복(연격은 끊김), 돌진은 그 자리에서 끝나며 크게 휘청.
func _spear_parried() -> void:
	if state == State.THRUST or (state == State.COMBO3 and combo_step < 2):
		# 창이 튕겨 나간다: 긴 회복 + 뒤로 밀림 (3연격은 끊긴다). 그림은 "stagger" 힌트로 뒤로 젖히며 출렁인다.
		hitbox.deactivate()
		if state == State.COMBO3:
			combo_step = 2   # 되돌림이 끝나면 행진으로 (다음 타 없음)
			_red = false
		attack_phase = "recovery"
		_timer = 1.1
		recovery_len = 1.1
		anim_hint = "stagger"
		velocity.x = -facing * 240.0
	elif state == State.CHARGE and attack_phase == "active":
		# 돌진을 정면에서 되받았다: 창이 빗나가며 크게 휘청, 돌진은 끝난다
		hitbox.deactivate()
		attack_phase = "recovery"
		_timer = 1.2
		recovery_len = 1.2
		anim_hint = "stagger"
		velocity.x = -facing * 320.0


## 무너짐(BROKEN)으로. 창이 박힌 채(STUCK) 무너지면 남은 박힘 시간만큼만 무너진다 (최소 stuck_broken_min).
func _enter_broken() -> void:
	var t := broken_time
	if state == State.STUCK:
		t = clampf(_timer, stuck_broken_min, broken_time)
	_set_state(State.BROKEN)
	_timer = t


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
	# 날아가던 내 검기·불꽃은 거둔다 (쓰러뜨린 뒤 그 불꽃에 소녀가 쓰러지면 BossRoom 이 싸움을 처음으로 되돌려 승리가 날아간다)
	for p in get_tree().get_nodes_in_group("projectile"):
		if not is_instance_valid(p) or p.get("source") != self or p.get("from_player") or p.get("_dead"):
			continue
		if p.has_method("_vanish"):
			p._vanish()
	for m in get_tree().get_nodes_in_group("knight_pillar_mark"):
		m.queue_free()
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
		_red = false
	state_changed.emit(new_state)


func flash_amount() -> float:
	return _flash


## 붉은 예고(가드 불가): 내려찍기 예비, 3연격 마지막 타(올려치기) 예비.
func is_red() -> bool:
	if not _red or attack_phase != "startup":
		return false
	return state == State.SLAM or (state == State.COMBO3 and combo_step == 2)


## BossRoom 이 예고 글자를 띄울 때 쓴다 (공격 이름만 — 가드 불가 여부는 붉은 빛으로 안다).
func telegraph_label(kind: String) -> String:
	match kind:
		"slam": return "내려찍기!"
		"wave": return "검기!"
		"combo3": return "올려치기!"
		"charge": return "돌진!"
		"spin": return "등불 회전!"
	return ""


func is_ground() -> bool:
	return true


func state_name() -> String:
	return State.keys()[state]

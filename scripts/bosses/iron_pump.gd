extends CharacterBody2D
class_name IronPump
## 확장판 보스 '무쇠 펌프' (EXPANSION.md 4장). 마력을 뽑아내던 거대한 채굴 펌프. 장인들이 만들었고, 의지를 갖게 되었다.
## 땅에서 싸운다. 소녀 몇 배 크기. **기계적 반복 리듬**: 1페이즈 공격은 정해진 순서(피스톤 → 분사 → 빨아들이기 → …)로
## 돌고 예고는 보스곡 124.5bpm 의 2박(0.96초)이라, 규칙을 읽으면 쉽다.
## 패턴: 피스톤 내려찍기(붉은 예고·가드 불가·땅 충격파 양쪽) / 수액 분사(관에서 수액 덩어리 3연속, 저스트 가드로 되받기)
##       / 관 빨아들이기(2초 동안 소녀를 초당 suck_pull px 씩 끌어당김 → 끝에 물기(가드 가능); 반대로 달리거나 구르면 벗어난다)
## 장갑: 평소엔 약공격이 35% 만 먹힌다. 씨앗 베기·낙하 공격·되받은 분사가 장갑 게이지(=흐트러짐)를 채우면
##       장갑이 깨져 핵이 드러난다 (BROKEN 5초, 피해 ×2, 약공격도 온전히).
##       수액 방울 하나를 되받으면: 저스트 가드 자체가 +45(소녀 쪽 규칙) + 되받은 방울이 맞을 때 reflect_poise(15) = 60.
##       세 발을 모두 되받으면 180 ≥ 160 이라 장갑이 깨지고, 두 발이면 120 (2026-10-19 검토: 두 발로 깨지던 것을 조정).
## 2페이즈(체력 절반): 규칙이 무너진다 — 순서 무작위·예고 ±30%·피스톤 빨라짐, 공격 뒤마다 사방에서 수액이 솟는다(SapSpurt).
## 체력 0 → 쓰러짐 → 정화 → 회상 "memory_pump" → 벽 부수기(wall_break).
## BossRoom 과 맞추는 약속: start_fight / reset_fight / arena / ground_y / fallen / purified / hp_changed / poise_changed
##   / phase_changed / telegraph(kind) / telegraph_label(kind) / state_name / debug_log / is_ground / receive_hit / hp / poise / phase / facing

enum State { WAIT, INTRO, IDLE, PISTON, SPRAY, SUCK, STAGGER, BROKEN, FALLEN, PURIFIED }
const ATTACK_STATES := [State.PISTON, State.SPRAY, State.SUCK]
## 1페이즈의 고정 순서
const CYCLE := [State.PISTON, State.SPRAY, State.SUCK]
## 보스곡 한 박. 예고·쉼은 이 박의 배수 (재생 위치에 맞추지는 않고 길이만 곡의 박과 같게 — 여왕과 달리 박자 동기화는 없다).
## 기획서의 Suno 요청은 128bpm 이었지만 기획자의 정식 곡을 재 보니 124.5bpm (tools/measure_tempo.gd, 2026-10-19: 124.47~124.48bpm,
## 4/4, 첫 박 0.36초, 154.6초 동안 박 자리 어긋남 5ms 아래) → 곡에 맞춰 바꿈.
const BEAT := 60.0 / 124.5

signal hp_changed(hp: float, max_hp: float)
signal poise_changed(poise: float, max_poise: float)
signal phase_changed(phase: int)
signal state_changed(state: State)
signal fallen
signal purified
signal telegraph(kind: String)
## 분사 한 발을 쐈다 (그림의 반동)
signal shot
## 피스톤이 땅을 쳤다 (그림의 충격)
signal slammed

@export var max_hp := 1600.0
## 장갑 게이지 (= 흐트러짐). 가득 차면 장갑이 깨진다.
@export var max_poise := 160.0
@export var poise_decay := 6.0
@export var broken_time := 5.0
@export var broken_damage_multiplier := 2.0
## 약공격(흐트러짐 45 미만, 되받은 분사 아님)의 피해·장갑 비율
@export var light_damage_ratio := 0.35
@export var light_poise_ratio := 0.5
## 되받은 분사가 맞을 때 더하는 장갑 게이지(방울 자체의 흐트러짐 대신 이 값)와 피해 배수.
## 저스트 가드 순간에도 소녀 쪽 규칙으로 +45 가 들어가므로 방울 하나 = 45 + 이 값.
@export var reflect_poise := 15.0
@export var reflect_damage_multiplier := 1.5
@export var crawl_speed := 90.0
@export var gravity := 2600.0
@export var piston_damage := 28.0
@export var shock_damage := 16.0
@export var spray_damage := 14.0
@export var spray_speed := 700.0
## 빨아들이기: 소녀를 끌어당기는 빠르기(px/s, 위치를 직접 옮긴다)와 길이(초), 끝의 물기 피해.
## 가만히 서 있으면 2초에 약 440px 끌리고, 반대로 달리거나(640) 구르면(980) 벗어난다.
@export var suck_pull := 250.0
@export var suck_time := 2.0
@export var bite_damage := 22.0
@export var spurt_damage := 14.0
## 수액 방울이 소녀 몸 위에서 생기지 않게: 노즐(앞 250px)과 소녀 사이를 적어도 이만큼 둔다
@export var spray_min_gap := 170.0
## 몸 돌리기 규칙 (소녀가 몸을 지나칠 때 매 프레임 뒤집히지 않게)
@export var face_deadzone := 60.0
@export var face_hold := 0.3

const HEAVY_POISE := 45.0
const PROJECTILE := preload("res://scenes/combat/projectile.tscn")
## 빨아들이기의 끌림 기록 (시험용: 이번 빨아들이기에서 소녀를 끌어당긴 거리 px)
var pulled := 0.0
const SPURT := preload("res://scenes/combat/sap_spurt.tscn")

var state: State = State.WAIT
var hp := 1600.0
var poise := 0.0
var phase := 1
var facing := -1
var player: Player
var arena: Rect2
var ground_y := 0.0
var attack_phase := ""   # startup / active / recovery (공격이 아니면 "")
var windup_progress := 0.0
## 지금 공격의 단계 길이(초). 그림이 진행도를 계산하는 데 쓴다.
var startup_len := 0.5
var active_len := 0.2
var recovery_len := 0.7
## 그림에 주는 힌트: "" / "stagger"(빨아들이기가 저스트 가드로 끊김, 2페이즈 휘청)
var anim_hint := ""
var stagger_len := 0.6
## 시험·관찰용: 시작한 공격 이름의 기록 (피스톤/분사/빨아들이기)
var attack_log: Array = []
var debug_log := false

var _face_hold := 0.0
var _timer := 0.0
var _poise_hold := 0.0
var _flash := 0.0
var _registered := false
var _home := Vector2.ZERO
var _red := false
var _cycle := 0
var _last_attack: State = State.WAIT
var _shots_left := 0
var _shot_timer := 0.0
var _bit := false
var _spurts_pending := 0
var _idle_gap := 2.0 * BEAT

@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox


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
	_cycle = 0
	attack_log.clear()
	_set_state(State.INTRO)
	_timer = 2.2


func reset_fight() -> void:
	_unregister()
	hp = max_hp
	poise = 0.0
	phase = 1
	visible = false
	velocity = Vector2.ZERO
	hitbox.deactivate()
	global_position = _home
	_cycle = 0
	_spurts_pending = 0
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
	match state:
		State.INTRO:
			velocity.x = 0.0
			if _timer <= 0.0:
				_set_state(State.IDLE)
				_timer = 1.5 * BEAT
		State.IDLE:
			if player:
				var dx := player.global_position.x - global_position.x
				_update_facing(dx)
				# 무거운 기계: 소녀가 멀면 뿌리로 천천히 기어간다
				var want := facing * crawl_speed if absf(dx) > 560.0 else 0.0
				velocity.x = move_toward(velocity.x, want, 500.0 * delta)
				if _timer <= 0.0:
					_choose_attack()
			else:
				velocity.x = 0.0
		State.PISTON:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, 0.3, func() -> void: _slam())
		State.SPRAY:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, 0.75, func() -> void:
				_shots_left = 3
				_shot_timer = 0.0)
			if attack_phase == "active" and _shots_left > 0:
				_shot_timer -= delta
				if _shot_timer <= 0.0:
					_shot_timer = 0.25
					_shots_left -= 1
					_spray()
		State.SUCK:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, suck_time + 0.25, func() -> void:
				_bit = false
				pulled = 0.0)
			if attack_phase == "active" and player:
				if _timer > 0.25:
					# 관이 소녀를 끌어당긴다: 위치를 직접 옮긴다 (바람(apply_wind)은 소녀의 감속에 거의 지워져 끌리지 않았다).
					# 반대로 달리거나(640px/s) 구르면(980px/s) 끌어당김(suck_pull)보다 빨라 벗어난다.
					_pull_player(delta)
				elif not _bit:
					_bit = true
					_bite()
		State.STAGGER:
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * delta)
			if _timer <= 0.0:
				_set_state(State.IDLE)
				_timer = 1.5 * BEAT
		State.BROKEN:
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			if _timer <= 0.0:
				poise = 0.0
				poise_changed.emit(poise, max_poise)
				_set_state(State.IDLE)
				_timer = BEAT
		State.FALLEN:
			velocity.x = 0.0
			_update_interactable()
	move_and_slide()


## 빨아들이기: 소녀를 관 쪽으로 suck_pull px/s 만큼 옮긴다 (벽·지형에는 막힌다). 관 바로 앞(120px)까지만.
func _pull_player(delta: float) -> void:
	if player.state in [Player.State.DEAD, Player.State.REST, Player.State.PURIFY]:
		return
	var dx := global_position.x - player.global_position.x
	if absf(dx) <= 120.0:
		return
	var step := signf(dx) * minf(suck_pull * delta, absf(dx) - 120.0)
	var before := player.global_position.x
	player.move_and_collide(Vector2(step, 0.0))
	pulled += absf(player.global_position.x - before)


## 예고 → 실행 → 회복의 공통 흐름 (startup/recovery 길이는 _begin 이 정했다). on_active 는 실행 순간 한 번.
func _phase_step(delta: float, active: float, on_active: Callable) -> void:
	match attack_phase:
		"startup":
			windup_progress = 1.0 - _timer / maxf(startup_len, 0.001)
			if _timer <= 0.0:
				attack_phase = "active"
				_timer = active
				active_len = active
				on_active.call()
		"active":
			if _timer <= 0.0:
				attack_phase = "recovery"
				_timer = recovery_len
				_red = false
				if phase == 2:
					_leak()
		"recovery":
			if _timer <= 0.0:
				_set_state(State.IDLE)
				_timer = _idle_gap


func _update_facing(dx: float) -> void:
	var want := 1 if dx > 0.0 else -1
	if want != facing and absf(dx) > face_deadzone and _face_hold <= 0.0:
		facing = want
		_face_hold = face_hold


## 지금 공격 단계의 진행도 (0→1).
func phase_progress() -> float:
	match attack_phase:
		"startup": return clampf(windup_progress, 0.0, 1.0)
		"active": return 1.0 - clampf(_timer / maxf(active_len, 0.001), 0.0, 1.0)
		"recovery": return 1.0 - clampf(_timer / maxf(recovery_len, 0.001), 0.0, 1.0)
	return 0.0


func state_progress(length: float) -> float:
	return 1.0 - clampf(_timer / maxf(length, 0.001), 0.0, 1.0)


func _begin(st: State, startup: float, recovery: float) -> void:
	_set_state(st)
	attack_phase = "startup"
	windup_progress = 0.0
	_timer = startup
	startup_len = startup
	recovery_len = recovery
	_last_attack = st
	attack_log.append(State.keys()[st])


## 다음 공격을 고른다. 1페이즈: 정해진 순서와 정해진 박. 2페이즈: 순서 무작위(같은 것 연속 없음)·예고 ±30%·피스톤 빨라짐.
func _choose_attack() -> void:
	var st: State
	var jitter := 1.0
	if phase == 1:
		st = CYCLE[_cycle % CYCLE.size()]
		_cycle += 1
		_idle_gap = 2.0 * BEAT
	else:
		var pool: Array = CYCLE.duplicate()
		pool.erase(_last_attack)
		st = pool[randi() % pool.size()]
		jitter = randf_range(0.7, 1.3)
		_idle_gap = BEAT * randf_range(0.8, 2.0)
	match st:
		State.PISTON:
			_red = true
			telegraph.emit("piston")
			_begin(st, 2.0 * BEAT * (0.75 if phase == 2 else 1.0) * jitter, 2.0 * BEAT)
		State.SPRAY:
			telegraph.emit("spray")
			_begin(st, 2.0 * BEAT * jitter, 1.5 * BEAT)
		State.SUCK:
			telegraph.emit("suck")
			_begin(st, 1.5 * BEAT * jitter, 2.0 * BEAT)


## BossRoom 이 예고 글자로 쓴다 (가드 불가는 붉은 빛이 알리고 글자는 공격 이름만).
func telegraph_label(kind: String) -> String:
	return {"piston": "피스톤!", "spray": "수액 분사!", "suck": "빨아들이기!"}.get(kind, "")


## 피스톤이 땅을 친다: 앞쪽 판정(가드 불가) + 양쪽으로 달리는 땅 충격파.
func _slam() -> void:
	var hit := HitData.make(piston_damage, 0.0, self, Vector2(720, -340))
	hit.guardable = false
	hit.hitstop = 0.08
	# 판정은 보이는 망치 머리 자리(앞 약 220~340px)에 맞춘다. 그 너머는 양쪽으로 달리는 충격파(점프로 넘김)가 맡는다.
	hitbox.set_box(Rect2(150, -190, 220, 220), facing)
	hitbox.activate(hit, 0.3)
	Juice.shake(14.0)
	Juice.rumble(0.7, 1.0, 0.3)
	Sfx.play("heavy_hit", 2.0, 0.05)
	var at := global_position + Vector2(facing * 300.0, 0)
	for dir in [-1, 1]:
		var p: Projectile = PROJECTILE.instantiate()
		p.kind = Projectile.Kind.GUST
		p.speed = 720.0
		p.damage = shock_damage
		p.poise = 0.0
		p.lifetime = 1.5
		p.size = Vector2(84, 50)
		p.color = Color(0.95, 0.5, 0.25)
		get_parent().add_child(p)
		p.global_position = at + Vector2(dir * 40.0, -24.0)
		p.launch(Vector2(dir, 0), self, false)
	slammed.emit()


## 관에서 수액 덩어리 한 발 (소녀를 조금 앞질러 겨눈다). 저스트 가드로 되받으면 펌프에게 돌아온다.
func _spray() -> void:
	if player == null:
		return
	var p := SapBlob.make(spray_speed, spray_damage, 44.0)
	p.fall_gravity = 380.0
	p.lifetime = 2.8
	get_parent().add_child(p)
	# 노즐은 앞 250px. 소녀가 그보다 가까우면 방울이 소녀 몸 위에서 생겨 저스트 가드할 틈이 없으므로 몸 쪽으로 당겨 쏜다.
	var ahead := (player.global_position.x - global_position.x) * facing
	var reach := clampf(ahead - spray_min_gap, 60.0, 250.0)
	var origin := global_position + Vector2(facing * reach, -120.0)
	p.global_position = origin
	var aim := player.global_position + Vector2(player.velocity.x * 0.2, -50.0 - absf(player.global_position.x - origin.x) * 0.15)
	p.launch((aim - origin).normalized(), self, false)
	Sfx.play("gust", -4.0, 0.1)
	shot.emit()


## 빨아들이기의 끝: 관이 물어뜯는다 (가드 가능).
func _bite() -> void:
	var hit := HitData.make(bite_damage, 0.0, self, Vector2(520, -260))
	hit.hitstop = 0.06
	hitbox.set_box(Rect2(40, -230, 320, 250), facing)
	hitbox.activate(hit, 0.25)
	Juice.shake(6.0)
	Sfx.play("hit", -2.0, 0.1)


## 2페이즈: 공격 뒤마다 사방에서 수액이 솟는다 (바닥 예고 0.6초 → 기둥).
func _leak() -> void:
	if player == null:
		return
	var n := 2
	for i in n:
		var sp := SPURT.instantiate()
		sp.damage = spurt_damage
		get_parent().add_child(sp)
		var x: float
		if i == 0:
			x = player.global_position.x + player.velocity.x * 0.5
		else:
			x = randf_range(arena.position.x + 120.0, arena.end.x - 120.0)
		sp.global_position = Vector2(clampf(x, arena.position.x + 80.0, arena.end.x - 80.0), ground_y)
		sp.launch(Vector2.UP, self, false)


func receive_hit(hit: HitData, _hb: Hurtbox) -> String:
	if state in [State.WAIT, State.INTRO, State.FALLEN, State.PURIFIED]:
		return "ignored"
	_flash = 1.0
	# 되받은 분사(출처가 나 자신)는 피해 ×1.5 에 장갑 reflect_poise. 무거운 공격(씨앗 베기·낙하 공격)은 온전히, 약공격은 장갑에 막혀 조금만.
	var reflected := hit.source == self
	var heavy := reflected or hit.poise >= HEAVY_POISE
	var dmg := hit.damage
	var armor := hit.poise
	if state == State.BROKEN:
		dmg *= broken_damage_multiplier
	elif not heavy:
		dmg *= light_damage_ratio
		armor *= light_poise_ratio
	if reflected:
		# 저스트 가드 순간에 이미 +45 를 받았다 (on_just_guarded) → 방울 자체의 흐트러짐(28) 대신 reflect_poise 만
		armor = reflect_poise
		dmg *= reflect_damage_multiplier
	hp = maxf(hp - dmg, 0.0)
	hp_changed.emit(hp, max_hp)
	_add_poise(armor)
	if hp <= 0.0:
		_fall()
		return "hit"
	if phase == 1 and hp <= max_hp * 0.5:
		phase = 2
		phase_changed.emit(2)
		Juice.shake(10.0)
		if state != State.BROKEN:
			# 장갑이 깨진 채면 그 빈틈을 그대로 둔다 (휘청으로 끊지 않는다). 아니면 짧은 휘청을 거쳐 2페이즈로.
			hitbox.deactivate()
			_set_state(State.STAGGER)
			anim_hint = "stagger"
			_timer = stagger_len
			velocity.x = -facing * 120.0
			_red = false
	if poise >= max_poise and state != State.BROKEN:
		_break_armor()
	return "hit"


func _break_armor() -> void:
	hitbox.deactivate()
	_red = false
	_set_state(State.BROKEN)
	_timer = broken_time
	Juice.hitstop(0.12, 0.05)
	Juice.shake(9.0)
	Sfx.play("broke", 0.0, 0.05)


func on_just_guarded(_by: Player, amount: float) -> void:
	_flash = 1.0
	_add_poise(amount)
	if poise >= max_poise and state != State.BROKEN:
		_break_armor()
	elif state == State.SUCK and attack_phase == "active":
		# 물기를 되받았다: 관이 튕겨 빨아들이기가 끝난다
		hitbox.deactivate()
		attack_phase = "recovery"
		_timer = 1.2
		recovery_len = 1.2
		anim_hint = "stagger"
		velocity.x = -facing * 160.0


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
	var near := absf(player.global_position.x - global_position.x) < 300.0 and absf(player.global_position.y - global_position.y) < 240.0
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
		print("[펌프] %s → %s" % [State.keys()[state], State.keys()[new_state]])
	state = new_state
	anim_hint = ""
	if new_state not in ATTACK_STATES:
		attack_phase = ""
	state_changed.emit(new_state)


func flash_amount() -> float:
	return _flash


func is_red() -> bool:
	return _red and state == State.PISTON and attack_phase == "startup"


func is_ground() -> bool:
	return true


func state_name() -> String:
	return State.keys()[state]

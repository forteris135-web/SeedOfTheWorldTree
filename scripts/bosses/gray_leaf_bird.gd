extends CharacterBody2D
class_name GrayLeafBird
## 첫 보스 '잿빛 잎새의 새' (기획서 6장 보스 상세).
## 하늘: 잿빛 잎 흩날리기 / 깃털 화살(저스트 가드로 되받기) / 날갯바람(가드 불가).
## 지침: 땅으로 내려와 잿빛 잎을 삼키려 한다(끊으면 크게 흐트러짐). 날개 휘두르기·부리 찍기.
## 2페이즈(체력 절반): 잎 회오리, 더 많은 깃털, 짧아진 내려오기, 거세진 반격.
## 체력이 다하면 쓰러져 정화의 손길을 기다린다.

enum State { WAIT, INTRO, HOVER, LEAF_RAIN, FEATHERS, WIND, DESCEND, GROUND_IDLE, WALK_TO_PILE, EAT, SWEEP, PECK, TAKEOFF, BROKEN, FALLEN, PURIFIED }
const AIR_STATES := [State.HOVER, State.LEAF_RAIN, State.FEATHERS, State.WIND]
const GROUND_STATES := [State.GROUND_IDLE, State.WALK_TO_PILE, State.EAT, State.SWEEP, State.PECK]

signal hp_changed(hp: float, max_hp: float)
signal poise_changed(poise: float, max_poise: float)
signal phase_changed(phase: int)
signal state_changed(state: State)
signal fallen
signal purified
signal telegraph(kind: String)   # "wind" 등 붉은 예고

@export_group("능력치")
@export var max_hp := 900.0
@export var max_poise := 150.0
## 맞지 않을 때 초당 줄어드는 흐트러짐.
@export var poise_decay := 8.0
@export var broken_time := 5.0
## 무너진 동안 받는 피해 배수.
@export var broken_damage_multiplier := 1.6

@export_group("하늘")
@export var hover_speed := 5.0            # 목표 지점으로 다가가는 빠르기
@export var hover_rest := 1.2             # 패턴 사이 쉬는 시간 (2페이즈 0.8)
@export var air_time_max := 24.0          # 이 시간이 지나면 지쳐서 내려온다
@export var descend_fatigue := 4          # 깃털 반사·점프 공격이 이만큼 쌓이면 내려온다 (2페이즈 3)
@export var leaf_rain_time := 3.2
@export var leaf_interval := 0.2          # 2페이즈 0.13
@export var leaf_damage := 10.0
@export var feather_count := 3            # 2페이즈 5
@export var feather_damage := 14.0
@export var feather_speed := 1000.0
@export var wind_telegraph := 0.8
@export var wind_time := 1.5
@export var wind_force := 2600.0          # 소녀를 밀어내는 가속 (픽셀/초²)

@export_group("땅")
@export var ground_time := 9.0            # 2페이즈 7
@export var walk_speed := 240.0
@export var eat_time := 2.6
@export var eat_heal_ratio := 0.06
@export var eat_interrupt_poise := 50.0
@export var sweep_windup := 0.55          # 2페이즈 0.4
@export var sweep_damage := 20.0
@export var peck_windup := 0.45
@export var peck_damage := 16.0
@export var gravity := 2600.0

var state: State = State.WAIT
var hp := 900.0
var poise := 0.0
var phase := 1
var facing := -1
var player: Player
var arena: Rect2
var hover_points: Array = []
var ground_y := 0.0
var piles: Array = []

var _timer := 0.0
var _air_timer := 0.0
var _fatigue := 0
var _pattern_index := 0
var _hover_target := Vector2.ZERO
var _spawn_accum := 0.0
var _spawned := 0
var _poise_hold := 0.0
var _flash := 0.0
var _target_pile: Node2D
var _ground_timer := 0.0
var _ground_actions := 0
var _registered := false
var _hit_this_phase := false
var _home := Vector2.ZERO
var _bob_t := 0.0
var _wind_dir := 1

@onready var sprite: Sprite2D = $Sprite
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var body_shape: CollisionShape2D = $CollisionShape2D

const PROJECTILE := preload("res://scenes/combat/projectile.tscn")


func _ready() -> void:
	add_to_group("boss")
	hp = max_hp
	_home = global_position
	set_collision_mask_value(1, false)
	visible = false
	hitbox.landed.connect(_on_hit_landed)


## 방이 싸움을 시작시킨다.
func start_fight(p: Player) -> void:
	player = p
	visible = true
	global_position = Vector2(arena.get_center().x, arena.position.y - 300)
	_set_state(State.INTRO)
	_timer = 2.2
	_hover_target = hover_points[1] if hover_points.size() > 1 else arena.get_center()


## 소녀가 쓰러졌을 때: 처음 상태로.
func reset_fight() -> void:
	_unregister()
	hp = max_hp
	poise = 0.0
	phase = 1
	_fatigue = 0
	_air_timer = 0.0
	_pattern_index = 0
	visible = false
	velocity = Vector2.ZERO
	set_collision_mask_value(1, false)
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
	_timer -= delta
	_bob_t += delta
	if player and state in AIR_STATES + [State.INTRO, State.GROUND_IDLE, State.EAT]:
		facing = 1 if player.global_position.x > global_position.x else -1

	match state:
		State.INTRO:
			_fly_toward(_hover_target, delta, 2.5)
			if _timer <= 0.0:
				_set_state(State.HOVER)
				_timer = hover_rest
		State.HOVER:
			_air_timer += delta
			_fly_toward(_hover_target, delta, hover_speed)
			if _should_descend():
				_begin_descend()
			elif _timer <= 0.0:
				_next_pattern()
		State.LEAF_RAIN:
			_air_timer += delta
			_fly_toward(_hover_target, delta, hover_speed * 0.6)
			_spawn_accum += delta
			var interval := leaf_interval if phase == 1 else leaf_interval * 0.65
			while _spawn_accum >= interval:
				_spawn_accum -= interval
				_spawn_leaf()
			if _timer <= 0.0:
				_set_state(State.HOVER)
				_timer = _rest()
		State.FEATHERS:
			_air_timer += delta
			_fly_toward(_hover_target, delta, hover_speed * 0.3)
			var count := feather_count if phase == 1 else feather_count + 2
			# 예고 0.6초 뒤 0.15초 간격으로 쏜다
			var t_since := (0.6 + count * 0.15) - _timer
			var should_have := clampi(int(floor((t_since - 0.6) / 0.15)) + 1, 0, count)
			while _spawned < should_have:
				_spawn_feather(_spawned, count)
				_spawned += 1
			if _timer <= 0.0:
				_set_state(State.HOVER)
				_timer = _rest()
		State.WIND:
			_air_timer += delta
			_fly_toward(_hover_target, delta, hover_speed * 0.4)
			if _timer <= wind_time and player:
				player.apply_wind(_wind_dir * wind_force, delta)
			if _timer <= 0.0:
				_set_state(State.HOVER)
				_timer = _rest()
		State.DESCEND:
			var target := Vector2(global_position.x, ground_y)
			if _target_pile:
				target.x = _target_pile.global_position.x + facing * -120.0
			_fly_toward(target, delta, 3.5)
			if absf(global_position.y - ground_y) < 12.0:
				global_position.y = ground_y
				set_collision_mask_value(1, true)
				_set_state(State.GROUND_IDLE)
				_ground_timer = ground_time if phase == 1 else ground_time * 0.78
				_ground_actions = 0
				_timer = 0.5
				Juice.shake(6.0)
		State.GROUND_IDLE:
			_ground(delta)
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			if _timer <= 0.0:
				_pick_ground_action()
		State.WALK_TO_PILE:
			_ground(delta)
			if _target_pile == null or not is_instance_valid(_target_pile) or not _target_pile.available:
				_set_state(State.GROUND_IDLE)
				_timer = 0.3
			else:
				var dx := _target_pile.global_position.x - global_position.x
				facing = 1 if dx > 0.0 else -1
				if absf(dx) < 150.0:
					velocity.x = 0.0
					_set_state(State.EAT)
					_timer = eat_time
				else:
					velocity.x = move_toward(velocity.x, facing * walk_speed, 1200.0 * delta)
		State.EAT:
			_ground(delta)
			velocity.x = 0.0
			if _timer <= 0.0:
				hp = minf(hp + max_hp * eat_heal_ratio, max_hp)
				hp_changed.emit(hp, max_hp)
				if _target_pile and is_instance_valid(_target_pile):
					_target_pile.consume()
				_set_state(State.GROUND_IDLE)
				_timer = 0.6
		State.SWEEP:
			_ground(delta)
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			_melee_phase("sweep")
		State.PECK:
			_ground(delta)
			_melee_phase("peck")
		State.TAKEOFF:
			set_collision_mask_value(1, false)
			_fly_toward(_hover_target, delta, 2.5)
			if _timer <= 0.0:
				_set_state(State.HOVER)
				_timer = _rest()
				_air_timer = 0.0
				_fatigue = 0
		State.BROKEN:
			_settle_to_ground(delta)
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			if _timer <= 0.0:
				poise = 0.0
				poise_changed.emit(poise, max_poise)
				_begin_takeoff()
		State.FALLEN:
			_settle_to_ground(delta)
			velocity.x = 0.0
			_update_interactable()
	move_and_slide()


func _rest() -> float:
	return hover_rest if phase == 1 else hover_rest * 0.65


func _fly_toward(target: Vector2, delta: float, k: float) -> void:
	var bob := Vector2(0, sin(_bob_t * 2.2) * 18.0)
	var to := (target + bob) - global_position
	velocity = to * k


func _ground(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0


## 발판을 통과해 주 바닥까지 내려와 눕는다.
func _settle_to_ground(delta: float) -> void:
	if global_position.y < ground_y - 30.0 and not is_on_floor():
		set_collision_mask_value(1, false)
		velocity.y = minf(velocity.y + gravity * delta, 1400.0)
	else:
		set_collision_mask_value(1, true)
		_ground(delta)


func _should_descend() -> bool:
	var need := descend_fatigue if phase == 1 else maxi(descend_fatigue - 1, 2)
	return _fatigue >= need or _air_timer >= air_time_max


func _next_pattern() -> void:
	var order := [State.LEAF_RAIN, State.FEATHERS, State.WIND, State.FEATHERS] if phase == 1 else [State.LEAF_RAIN, State.FEATHERS, State.WIND, State.FEATHERS, State.LEAF_RAIN, State.WIND]
	var next: State = order[_pattern_index % order.size()]
	_pattern_index += 1
	# 다음 머무를 자리
	if hover_points.size() > 0:
		_hover_target = hover_points[randi() % hover_points.size()]
	match next:
		State.LEAF_RAIN:
			_set_state(State.LEAF_RAIN)
			_timer = leaf_rain_time
			_spawn_accum = 0.0
		State.FEATHERS:
			_set_state(State.FEATHERS)
			var count := feather_count if phase == 1 else feather_count + 2
			_timer = 0.6 + count * 0.15
			_spawned = 0
			_flash = 0.6
		State.WIND:
			_set_state(State.WIND)
			_timer = wind_telegraph + wind_time
			_wind_dir = 1 if (player and player.global_position.x > global_position.x) else -1
			telegraph.emit("wind")


func _spawn_leaf() -> void:
	var p: Projectile = PROJECTILE.instantiate()
	p.kind = Projectile.Kind.LEAF
	p.speed = randf_range(170.0, 260.0)
	p.damage = leaf_damage
	p.poise = 0.0
	p.lifetime = 7.0
	p.fall_gravity = 40.0
	p.size = Vector2(46, 20)
	p.color = Color(0.62, 0.64, 0.6)
	var dir := Vector2(randf_range(-0.25, 0.25), 1.0)
	var pos: Vector2
	if phase == 1:
		pos = Vector2(randf_range(arena.position.x + 80, arena.end.x - 80), arena.position.y + 40)
	else:
		# 회오리: 새 주위에서 바깥으로 돌며 흩어진다
		var a := _spawned * 0.9
		_spawned += 1
		pos = global_position + Vector2(cos(a), sin(a)) * 160.0
		dir = (Vector2(cos(a + 1.2), sin(a + 1.2)) + Vector2(0, 1.2)).normalized()
		p.speed = 300.0
	get_parent().add_child(p)
	p.global_position = pos
	p.launch(dir, self, false)


func _spawn_feather(index: int, count: int) -> void:
	if player == null:
		return
	var p: Projectile = PROJECTILE.instantiate()
	p.kind = Projectile.Kind.FEATHER
	p.speed = feather_speed
	p.damage = feather_damage
	p.poise = 0.0
	p.reflectable = true
	p.size = Vector2(76, 16)
	p.color = Color(0.78, 0.8, 0.78)
	get_parent().add_child(p)
	var origin := global_position + Vector2(facing * 120.0, 20.0)
	p.global_position = origin
	var spread := (index - (count - 1) / 2.0) * 0.12
	var dir := (player.global_position + Vector2(0, -40) - origin).normalized().rotated(spread)
	p.launch(dir, self, false)
	p.reflected.connect(func(_pr): _fatigue += 2)


func _begin_descend() -> void:
	_target_pile = _nearest_available_pile()
	set_collision_mask_value(1, false)
	_set_state(State.DESCEND)


func _nearest_available_pile() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for pile in piles:
		if is_instance_valid(pile) and pile.available:
			var d: float = absf(pile.global_position.x - global_position.x)
			if d < best_d:
				best_d = d
				best = pile
	return best


func _pick_ground_action() -> void:
	_ground_timer -= 0.0
	if _ground_actions == 0 and _target_pile and is_instance_valid(_target_pile) and _target_pile.available:
		_ground_actions += 1
		_set_state(State.WALK_TO_PILE)
		return
	if _ground_actions >= (4 if phase == 1 else 5):
		_begin_takeoff()
		return
	_ground_actions += 1
	if player:
		facing = 1 if player.global_position.x > global_position.x else -1
	var dist := absf(player.global_position.x - global_position.x) if player else 999.0
	if dist > 260.0 or randf() < 0.4:
		_set_state(State.PECK)
		_timer = peck_windup if phase == 1 else peck_windup * 0.8
	else:
		_set_state(State.SWEEP)
		_timer = sweep_windup if phase == 1 else sweep_windup * 0.75
	_melee_stage = 0


var _melee_stage := 0
func _melee_phase(kind: String) -> void:
	if _melee_stage == 0:
		# 예고 중
		if _timer <= 0.0:
			_melee_stage = 1
			if kind == "sweep":
				var hit := HitData.make(sweep_damage, 0.0, self, Vector2(520, -220))
				hitbox.set_box(Rect2(-40, -120, 330, 180), facing)
				hitbox.activate(hit, 0.22)
				_timer = 0.22
			else:
				var hit2 := HitData.make(peck_damage, 0.0, self, Vector2(420, -160))
				hitbox.set_box(Rect2(80, -90, 200, 110), facing)
				hitbox.activate(hit2, 0.3)
				velocity.x = facing * 520.0
				_timer = 0.3
			Juice.shake(3.0)
	elif _melee_stage == 1:
		if kind == "peck":
			velocity.x = move_toward(velocity.x, 0.0, 900.0 * get_physics_process_delta_time())
		if _timer <= 0.0:
			_melee_stage = 2
			_timer = 0.9 if phase == 1 else 0.65
	else:
		velocity.x = move_toward(velocity.x, 0.0, 1600.0 * get_physics_process_delta_time())
		if _timer <= 0.0:
			_set_state(State.GROUND_IDLE)
			_timer = 0.35


func _begin_takeoff() -> void:
	hitbox.deactivate()
	_hover_target = hover_points[randi() % hover_points.size()] if hover_points.size() > 0 else arena.get_center()
	_set_state(State.TAKEOFF)
	_timer = 1.1


# ---------- 맞기 ----------

func receive_hit(hit: HitData, _hurtbox: Hurtbox) -> String:
	if state in [State.WAIT, State.INTRO, State.FALLEN, State.PURIFIED]:
		return "ignored"
	_flash = 1.0
	var dmg := hit.damage
	if state == State.BROKEN:
		dmg *= broken_damage_multiplier
	hp = maxf(hp - dmg, 0.0)
	hp_changed.emit(hp, max_hp)
	var gained := hit.poise
	if state == State.EAT:
		gained += eat_interrupt_poise   # 잎 삼키기를 끊었다
		hitbox.deactivate()
		_set_state(State.GROUND_IDLE)
		_timer = 1.2
		Juice.shake(5.0)
	elif state in AIR_STATES:
		_fatigue += 1 if not hit.from_player or hit.poise < 25.0 else 2
	_add_poise(gained)
	if hp <= 0.0:
		_fall()
		return "hit"
	if phase == 1 and hp <= max_hp * 0.5:
		_enter_phase2()
	if poise >= max_poise and state != State.BROKEN:
		_break()
	return "hit"


func _add_poise(amount: float) -> void:
	if amount <= 0.0:
		return
	poise = minf(poise + amount, max_poise)
	_poise_hold = 2.5
	poise_changed.emit(poise, max_poise)


func _break() -> void:
	hitbox.deactivate()
	set_collision_mask_value(1, true)
	_set_state(State.BROKEN)
	_timer = broken_time
	Juice.hitstop(0.1, 0.05)
	Juice.shake(8.0)


func _enter_phase2() -> void:
	phase = 2
	phase_changed.emit(2)
	Juice.shake(10.0)
	_flash = 1.0


func _fall() -> void:
	hitbox.deactivate()
	set_collision_mask_value(1, true)
	velocity = Vector2(0, 600)
	_unregister()
	_set_state(State.FALLEN)
	Juice.hitstop(0.15, 0.03)
	Juice.shake(12.0)
	fallen.emit()


func _update_interactable() -> void:
	if player == null or not is_on_floor():
		return
	var near := absf(player.global_position.x - global_position.x) < 260.0 and absf(player.global_position.y - global_position.y) < 200.0
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


func _on_hit_landed(_result: String, _target: Node) -> void:
	pass


var debug_log := false
var _state_started_ms := 0


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	if debug_log:
		print("[새] %s %.2f초 → %s" % [State.keys()[state], (Time.get_ticks_msec() - _state_started_ms) / 1000.0, State.keys()[new_state]])
	_state_started_ms = Time.get_ticks_msec()
	state = new_state
	state_changed.emit(new_state)


func flash_amount() -> float:
	return _flash


func is_ground() -> bool:
	return state in GROUND_STATES or state in [State.BROKEN, State.FALLEN]


func state_name() -> String:
	return State.keys()[state]

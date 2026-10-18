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
var windup_progress := 0.0
## 그림 쪽에 주는 힌트: "red"(가드 불가 예고) / "charge"(돌진) / "stuck"(박힘)
var anim_hint := ""

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


func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Player
	_flash = maxf(_flash - delta * 8.0, 0.0)
	_poise_hold_timer = maxf(_poise_hold_timer - delta, 0.0)
	if state != State.BROKEN and _poise_hold_timer <= 0.0 and poise > 0.0:
		poise = maxf(poise - poise_decay * delta, 0.0)
		poise_changed.emit(poise, max_poise)

	if not is_on_floor():
		velocity.y += gravity * delta
	_timer -= delta

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
			if _timer <= 0.0 and is_on_floor():
				_set_state(State.CHASE)
				_timer = 0.1
		State.CHASE:
			if player == null or not _sees_player(notice_range * 1.5):
				_set_state(State.IDLE)
				_timer = 0.8
			else:
				var dx := player.global_position.x - global_position.x
				facing = 1 if dx > 0.0 else -1
				var close_y := absf(player.global_position.y - global_position.y) < 140.0
				if absf(dx) <= attack_range and close_y and _timer <= 0.0:
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
				if player and absf(player.global_position.x - global_position.x) <= attack_range * 1.2:
					_begin_windup()
				else:
					_set_state(State.CHASE)
					_timer = 0.15
		State.WINDUP:
			velocity.x = move_toward(velocity.x, 0.0, 2400.0 * delta)
			windup_progress = 1.0 - _timer / windup_time
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
			velocity.x = 0.0
	move_and_slide()


func _sees_player(range_px := -1.0) -> bool:
	if player == null or player.state == Player.State.DEAD:
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


## 발견: 펄쩍 뛰며 경계한다.
func _alert() -> void:
	if player:
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
	velocity.x = dir * absf(hit.knockback.x) * 0.5
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
	# 예고·휘두르기 중에는 작은 공격으로 멈칫하지 않는다 (단단함)
	var armored := state in [State.WINDUP, State.STRIKE, State.LUNGE] and hit.poise < 30.0
	if not armored:
		hitbox.deactivate()
		_set_state(State.HIT)
		_timer = hit_stun
	return "hit"


## 소녀가 저스트 가드로 받아냈다.
func on_just_guarded(_by: Player, amount: float) -> void:
	_flash = 1.0
	_add_poise(amount)
	if poise >= max_poise:
		_break(false)
		return
	# 받아친 뒤 크게 휘청인다
	hitbox.deactivate()
	velocity.x = -facing * 220.0
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
func _rescue(by: Player) -> void:
	_unregister()
	hitbox.deactivate()
	_set_state(State.DEAD)
	if rescue_id != "":
		Progress.rescued[rescue_id] = true
		Progress.set_flag(rescue_id + "_rescued")
	rescued.emit(rescue_id)
	var scene: PackedScene = load("res://scenes/npcs/rescued_person.tscn")
	if scene:
		var npc := scene.instantiate()
		npc.rescue_id = rescue_id
		npc.texture = ($Visual.texture if $Visual.get("texture") != null else null)
		npc.art_faces_right = $Visual.get("art_faces_right")
		npc.art_scale = $Visual.get("art_scale")
		npc.facing = -facing
		npc.global_position = global_position + Vector2(0, hurt_height * 0.5)
		get_parent().add_child(npc)
		npc.greet(by)
	queue_free()


func _die(purified: bool) -> void:
	_unregister()
	hitbox.deactivate()
	_set_state(State.DEAD)
	died.emit(purified)
	_spawn_sprout()
	queue_free()


func _spawn_sprout() -> void:
	var sprout_scene: PackedScene = load("res://scenes/world/sprout.tscn")
	if sprout_scene:
		var s := sprout_scene.instantiate()
		s.global_position = global_position + Vector2(0, hurt_height * 0.5)
		get_parent().add_child(s)


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state


func flash_amount() -> float:
	return _flash


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

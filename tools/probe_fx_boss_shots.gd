extends Node
## 보스·적 기술 이펙트 눈 확인용 스크린샷 (2026-10-19 이펙트 리뉴얼 F2). 화면이 있어야 찍힌다 (--headless 면 바로 끝난다).
## 실행: godot --path . res://tools/probe_fx_boss_shots.tscn -- --boss bird|knight|root|queen|pump|mobs|water [--only 기술,기술] [--out 폴더]
## 보스 방을 띄우고 HUD 를 숨긴 뒤 싸움을 시작시키고, 기술을 하나씩 걸어 정해 둔 때에 찍는다 (bfx_<보스>_<기술>_<때>.png).
## 시간은 느리게(SLOW) 흘리고 게임 시간으로 기다린다 (그리기가 느려도 찍는 순간이 맞게). 소녀는 무적.
## 마지막 줄 "[shots] 끝 N장".

const SLOW := 0.3
const ROOMS := {"bird": "canopy_boss", "knight": "mine_boss", "root": "abyss_boss", "queen": "sap_lake_boss", "pump": "flooded_mine_boss",
	"mobs": "canopy_01", "water": "sap_lake_01"}

var _out := "res://screenshots/"
var _only: Array = []
var _which := "bird"
var _room: Node
var _player: Player
var _boss: Node2D
var _count := 0
var _gt := 0.0


func _physics_process(delta: float) -> void:
	_gt += delta


func _process(_delta: float) -> void:
	if not Juice._stopping:
		Engine.time_scale = SLOW
	if _player:
		_player._invuln_timer = 9999.0
		_player.hp = _player.max_hp


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("[probe] 끝: 실패 0 (화면 없음 — 스크린샷 시험은 건너뜀)")
		get_tree().quit()
		return
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--out": _out = args[i + 1]
			"--only": _only = args[i + 1].split(",")
			"--boss": _which = args[i + 1]
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out)
	_room = load("res://scenes/rooms/%s.tscn" % ROOMS[_which]).instantiate()
	add_child(_room)
	await _frames(10)
	for n in _room.get_children():
		if n is CanvasLayer:
			n.visible = false
	_player = get_tree().get_first_node_in_group("player") as Player
	_player.input_enabled = false
	_boss = _room.get_node_or_null("Boss") as Node2D
	match _which:
		"bird": await _bird()
		"knight": await _knight()
		"root": await _root()
		"queen": await _queen()
		"pump": await _pump()
		"mobs": await _mobs()
		"water": await _water()
	print("[shots] 끝 %d장" % _count)
	get_tree().quit()


func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(sec: float) -> void:
	var t0 := _gt
	while _gt - t0 < sec:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _out + "bfx_%s_%s.png" % [_which, name]
	img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	_count += 1
	var names := {}
	for f in Fx._active:
		names[f.fx_name] = names.get(f.fx_name, 0) + 1
	print("[shots] %s: 이펙트 %d %s" % [name, Fx.active_count(), names])


## 기술을 건 뒤 정해 둔 때(초, 게임 시간)마다 찍는다
func _capture(name: String, times: Array) -> void:
	var t0 := _gt
	for t in times:
		while _gt - t0 < float(t) - 0.0001:
			await get_tree().process_frame
		await _shot("%s_%03d" % [name, int(round(float(t) * 100.0))])


## 싸움을 시작시킨다: 소녀를 싸움터 가운데 바닥에 세우면 방이 문을 닫고 보스를 깨운다
func _start_fight(dx := -300.0) -> void:
	var room := _room as BossRoom
	var c: Rect2 = _boss.arena
	_player.global_position = Vector2(c.get_center().x + dx, float(_boss.ground_y) - 4.0)
	_player.velocity = Vector2.ZERO
	await _frames(4)
	if not room.fight_started:
		room._on_trigger(_player)
	await _wait(2.6)


func _place_player(at: Vector2, face: int) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO
	_player.facing = face


# ---------------- 잿빛 잎새의 새 ----------------
func _bird() -> void:
	await _start_fight(-500.0)
	var b := _boss
	if _want("wind"):
		await _bird_hover()
		b._pattern_index = 2
		b._next_pattern()
		await _capture("wind", [0.3, 0.7, 1.0, 1.3, 1.8])
	if _want("feathers"):
		await _bird_hover()
		b._pattern_index = 1
		b._next_pattern()
		await _capture("feathers", [0.62, 0.7, 0.8, 0.95])
	if _want("leaves"):
		await _bird_hover()
		b._pattern_index = 0
		b._next_pattern()
		await _capture("leaves", [1.0, 2.2])
	if _want("tornado"):
		await _bird_hover()
		b.phase = 2
		b._pattern_index = 0
		b._next_pattern()
		await _capture("tornado", [0.4, 1.2, 2.4])
		b.phase = 1
	if _want("ground"):
		await _bird_hover()
		b._begin_descend()
		var t0 := _gt
		while b.state_name() != "GROUND_IDLE" and _gt - t0 < 4.0:
			await get_tree().process_frame
		await _capture("land", [0.03, 0.15, 0.3])
		await _wait(0.4)
		_place_player(b.global_position + Vector2(-b.facing * 260.0, -4.0), b.facing)
		for kind in ["SWEEP", "PECK"]:
			_bird_melee(kind)
			await _capture(kind.to_lower(), [0.5, 0.58, 0.7])
			await _wait(1.0)
		# 잎 삼키기
		var pile = b._nearest_available_pile()
		if pile:
			b._target_pile = pile
			b.global_position.x = pile.global_position.x - 140.0
			b.facing = 1
			b._set_state(b.State.EAT)
			b._timer = b.eat_time
			await _capture("eat", [0.4, 1.0])
			b.receive_hit(HitData.make(1.0, 0.0, _player), null)   # 끊기
			await _capture("eat_break", [0.05, 0.2])


func _bird_hover() -> void:
	var b := _boss
	b.phase = 1
	b._set_state(b.State.HOVER)
	b._timer = 99.0
	b.set_collision_mask_value(1, false)
	var c: Rect2 = b.arena
	_place_player(Vector2(c.get_center().x - 300.0, float(b.ground_y) - 4.0), 1)
	await _wait(1.6)


func _bird_melee(kind: String) -> void:
	var b := _boss
	b.facing = 1 if _player.global_position.x > b.global_position.x else -1
	b._set_state(b.State[kind])
	b._timer = b.sweep_windup if kind == "SWEEP" else b.peck_windup
	b._melee_stage = 0
	b.attack_phase = "startup"
	b.windup_progress = 0.0
	b.startup_len = b._timer


# ---------------- 등불 기사 ----------------
func _knight() -> void:
	await _start_fight(-400.0)
	var b := _boss
	var plan := [["THRUST", [0.5, 0.58, 0.66]], ["COMBO3", [0.47, 0.55, 0.95, 1.3, 1.82, 1.9]], ["FLAME", [0.72, 0.82, 1.05, 1.4]],
		["SLAM", [0.5, 0.9, 1.02, 1.1, 1.3]], ["WAVE", [0.72, 0.85, 1.1, 1.4]], ["CHARGE", [0.6, 0.85, 1.05, 1.3, 1.8]],
		["SPIN", [0.82, 0.95, 1.25, 1.6]], ["THROW", [0.62, 1.0, 1.4, 1.8, 2.05, 2.3]]]
	for item in plan:
		var nm: String = item[0]
		if not _want(nm.to_lower()):
			continue
		b.phase = 2 if nm in ["SPIN", "THROW"] else 1
		b._set_state(b.State.MARCH)
		b._timer = 99.0
		b.velocity = Vector2.ZERO
		var c: Rect2 = b.arena
		b.global_position.x = c.get_center().x + (200.0 if nm != "CHARGE" else 500.0)
		b.facing = -1
		var gap := 330.0 if nm in ["THRUST", "COMBO3", "SLAM", "SPIN"] else 700.0
		_place_player(Vector2(b.global_position.x - gap, float(b.ground_y) - 4.0), 1)
		await _wait(0.6)
		b.force_attack(b.State[nm])
		await _capture(nm.to_lower(), item[1])
		await _wait(0.8)


# ---------------- 뿌리지기 ----------------
func _root() -> void:
	await _start_fight(-400.0)
	var b := _boss
	var plan := [["SPIKES", [0.6, 0.95, 1.05, 1.3]], ["SWEEP", [0.45, 0.53, 0.62]], ["SWEEP2", [0.42, 0.5, 0.58]], ["ORBS", [0.85, 1.2, 1.7]],
		["WALL", [0.6, 1.15, 1.3, 1.6]], ["HAND", [0.5, 0.85, 1.0, 1.2]], ["SEEDS", [1.0, 1.5, 1.9, 2.3]], ["RING", [0.85, 1.4, 2.0]],
		["STOMP", [0.6, 1.03, 1.2, 1.65, 1.9]]]
	for item in plan:
		var nm: String = item[0]
		if not _want(nm.to_lower()):
			continue
		b._set_state(b.State.STANCE)
		b._timer = 99.0
		b.velocity = Vector2.ZERO
		var c: Rect2 = b.arena
		b.global_position.x = c.get_center().x + 300.0
		b.facing = -1
		var gap := 300.0 if nm in ["SWEEP", "SWEEP2", "STOMP", "RING"] else 650.0
		_place_player(Vector2(b.global_position.x - gap, float(b.ground_y) - 4.0), 1)
		await _wait(0.6)
		b.force_pattern(nm)
		await _capture(nm.to_lower(), item[1])
		await _wait(1.0)


# ---------------- 수액의 여왕 ----------------
func _queen() -> void:
	await _start_fight(-400.0)
	var b := _boss
	var beat: float = b.BEAT
	var plan := [["DUST", [0.9, 1.0, 1.3]], ["WAVE", [0.5, 0.9, 1.2, 1.7]], ["BUTTERFLIES", [0.9, 1.15, 1.6]], ["LAND", [0.8, 0.9, 1.0, 1.25]]]
	for item in plan:
		var nm: String = item[0]
		if not _want(nm.to_lower()):
			continue
		b._set_state(b.State.HOVER)
		b._next_at = b._clock + 999.0
		var c: Rect2 = b.arena
		b._hover_target = Vector2(c.get_center().x + 150.0, float(b.ground_y) - b.HOVER_HEIGHT)
		_place_player(Vector2(c.get_center().x - 350.0, float(b.ground_y) - 4.0), 1)
		await _wait(1.2)
		b._spawned = 0
		match nm:
			"DUST": b._begin(b.State.DUST, b._clock, beat * 2.0, beat, beat)
			"WAVE": b._begin(b.State.WAVE, b._clock, beat * 2.0, beat, beat * 2.0)
			"BUTTERFLIES": b._begin(b.State.BUTTERFLIES, b._clock, beat * 2.0, beat, beat)
			"LAND":
				b._land_stone = b._pick_stone()
				b._diving = false
				b.dive_amount = 0.0
				b._begin(b.State.LAND, b._clock, beat * 2.0, beat, 0.0)
		# 여왕의 박자 시계는 시간 배속(SLOW)과 상관없이 실제 시간(보스곡)으로 흐른다 → 찍는 때도 SLOW 배
		var times: Array = []
		for t in item[1]:
			times.append(float(t) * SLOW)
		await _capture(nm.to_lower(), times)
		await _wait(1.0)


# ---------------- 무쇠 펌프 ----------------
func _pump() -> void:
	await _start_fight(-500.0)
	var b := _boss
	var beat: float = b.BEAT
	var plan := [["PISTON", [0.5, 0.92, 0.98, 1.1, 1.35]], ["SPRAY", [0.95, 1.05, 1.25, 1.5]], ["SUCK", [0.8, 1.3, 2.2, 2.95, 3.05]],
		["SPURT", [0.3, 0.62, 0.7, 0.85]]]
	for item in plan:
		var nm: String = item[0]
		if not _want(nm.to_lower()):
			continue
		b._set_state(b.State.IDLE)
		b._timer = 99.0
		var c: Rect2 = b.arena
		b.global_position.x = c.get_center().x + 250.0
		b.facing = -1
		_place_player(Vector2(b.global_position.x - 520.0, float(b.ground_y) - 4.0), 1)
		await _wait(0.8)
		match nm:
			"PISTON":
				b._red = true
				b._begin(b.State.PISTON, 2.0 * beat, 2.0 * beat)
			"SPRAY": b._begin(b.State.SPRAY, 2.0 * beat, 1.5 * beat)
			"SUCK": b._begin(b.State.SUCK, 1.5 * beat, 2.0 * beat)
			"SPURT":
				b.phase = 2
				b._leak()
				b.phase = 1
		await _capture(nm.to_lower(), item[1])
		await _wait(1.0)


# ---------------- 몹 ----------------
func _mobs() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	await _frames(3)
	var base := _player.global_position
	var plan := [["gardener", "res://scenes/enemies/gardener.tscn", [0.05, 0.12, 0.3]], ["herbalist", "res://scenes/enemies/herbalist.tscn", [0.1, 0.5, 1.2]],
		["guard_bash", "res://scenes/enemies/guard.tscn", [0.03, 0.1, 0.2]], ["guard_charge", "res://scenes/enemies/guard.tscn", [0.1, 0.3, 0.5, 0.65]],
		["machine", "res://scenes/enemies/machine.tscn", [0.1, 0.25, 0.45, 0.6]], ["small_pump", "res://scenes/enemies/small_pump.tscn", [0.03, 0.1, 0.3]],
		["sap_fisher", "res://scenes/enemies/sap_fisher.tscn", [0.03, 0.08, 0.16, 0.3]]]
	for item in plan:
		var nm: String = item[0]
		if not _want(nm):
			continue
		_place_player(base, 1)
		var e: EnemyBase = load(item[1]).instantiate()
		e.position = base + Vector2(420.0, -2.0)
		_room.add_child(e)
		await _frames(3)
		e.facing = -1
		e.player = _player
		await _wait(0.3)
		match nm:
			"guard_charge":
				e._mode = "charge"
				e._strike()
			"guard_bash":
				e._mode = "bash"
				e._strike()
			"machine":
				e._ramming = true
				e._strike()
			"herbalist":
				_place_player(base + Vector2(-200.0, 0.0), 1)
				e._strike()
			_:
				e._strike()
		await _capture(nm, item[2])
		e.queue_free()
		for p in get_tree().get_nodes_in_group("projectile"):
			p.queue_free()
		await _wait(0.4)


# ---------------- 물 (수액 웅덩이) ----------------
func _water() -> void:
	var pool: SapPool = null
	for n in _room.find_children("*", "", true, false):
		if n is SapPool and (pool == null or n.size.x > pool.size.x):
			pool = n
	if pool == null:
		print("[shots] 수액 웅덩이가 없다")
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	var x := pool.global_position.x + pool.size.x * 0.3
	_place_player(Vector2(x, pool.global_position.y - 300.0), 1)
	_player._set_state(Player.State.FALL)
	await _capture("fall_in", [0.25, 0.32, 0.4, 0.5])
	_player.input_enabled = true
	Input.action_press("move_right")
	await _capture("walk", [0.3, 0.6, 0.9])
	Input.action_press("jump")
	await _frames(2)
	Input.action_release("jump")
	await _capture("jump", [0.02, 0.08, 0.2])
	Input.action_release("move_right")
	await _wait(1.0)
	await _capture("drip", [0.5, 1.0, 1.5, 2.0, 2.5])
	_player.input_enabled = false

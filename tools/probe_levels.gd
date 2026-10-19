extends Node
## Claude Code용 지형 주행 시험 (화면 없이 돈다). 방을 통째로 띄우고 소녀를 **입력만으로** 조종한다.
## 실행: godot --headless --path . res://tools/probe_levels.tscn
##  1) mine_01: 마을에서 들어온 자리(FromVillage)에서 선반 끝 가시(160px)를 뛰어넘어 디딤 가지(P1b) → (1800,600) 발판(P2)
##     → 왼쪽으로 내려서며 P7 → P9 → 바닥 → Exit2 포탈 앞까지. 가시에 닿으면 take_hazard 로 체력이 줄고 자리가 되돌아가므로
##     hit_taken 신호와 hp 로 판정한다.
##  2) mine_01: 바닥에서 이단 점프로 one_way 발판 P9 를 아래에서 통과해 올라서는지 (채굴장은 이단 점프 보유 지역).
##  3) canopy_02: 좁힌 가시 구덩이(1220~1400)를 달리기 점프로 오른쪽→왼쪽 양방향 건너기 (오른쪽 바닥이 막다른 곳이 아님).
##  4) canopy_02: 이단 점프 없이 바닥에서 one_way 발판 P4(250 위)를 통과해 올라서기.
##  5) canopy_03 두 구덩이(1500~1800, 3400~3700)를 위의 가지 다리로 건너기(양방향), mine_02 구덩이(1980~2300) 달리기 점프로 건너기.
##  6) 포탈 앞에서 ↑를 눌러도 들어가지 않고, 손길(interact)로만 들어간다 (next_spawn 으로 판정, 실제 장면 전환은 막는다).
## 마지막에 "[probe] 끝: 실패 N" 을 찍고 그 수로 종료한다.

var _fail := 0
var _hits := 0
var _room: Node = null
var _room_id := ""
var _player: Player = null


func _ready() -> void:
	print("[probe] 지형 주행 시험 시작")
	await _probe_mine01_descent()
	await _probe_mine01_oneway_up()
	await _probe_pit("canopy_02", "FromCanopy01", 2400.0, 900.0, 1140.0, 1500.0, "바람의 틈 구덩이(1220~1400) →")
	await _probe_pit("canopy_02", "FromCanopy01", 2400.0, 1700.0, 1480.0, 1100.0, "바람의 틈 구덩이 ←(오른쪽 바닥에서 되돌아오기)")
	await _probe_canopy02_oneway_up()
	await _probe_canopy03_bridges()
	await _probe_pit("mine_02", "FromMine01", 1200.0, 1600.0, 1920.0, 2400.0, "관의 복도 구덩이(1980~2300) →")
	await _probe_portal_interact_only()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


# ---------- 방 띄우기 / 치우기 ----------
func _open(room_id: String, spawn: String) -> void:
	_release_all()
	if _room != null and _room_id == room_id and is_instance_valid(_player):
		# 같은 방이면 다시 띄우지 않고(방 하나 띄우는 데 수십 초) 등장 자리로 옮기기만 한다
		var marker := _room.get_node_or_null("Markers/" + spawn)
		if marker:
			_player.global_position = marker.position
		_player.velocity = Vector2.ZERO
		_player.input_enabled = true
		_player.hp = _player.max_hp
		_hits = 0
		for i in 6:
			await get_tree().physics_frame
		return
	await _close()
	Progress.next_spawn = spawn
	_room_id = room_id
	_room = load("res://scenes/rooms/%s.tscn" % room_id).instantiate()
	add_child(_room)
	for i in 3:
		await get_tree().physics_frame
	_player = get_tree().get_first_node_in_group("player") as Player
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()   # 지형 시험: 적은 치운다
	_hits = 0
	_player.hit_taken.connect(func(_d): _hits += 1)
	for i in 6:
		await get_tree().physics_frame


func _close() -> void:
	_release_all()
	if _room:
		_room.queue_free()
		_room = null
		_room_id = ""
		_player = null
		for i in 3:
			await get_tree().process_frame


func _release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "interact", "dodge"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _feet() -> float:
	return _player.global_position.y + 67.0


## 조건이 참이 될 때까지 물리 틱을 기다린다 (시간 제한). 참이면 true.
func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if cond.call():
			return true
	return false


## 달리면서 x 가 jump_x 를 지나면 점프(0.35초 누름)하고, x_end 에 닿거나 시간이 다 될 때까지 계속 달린다.
## 돌아오는 값: 끝났을 때 소녀 위치.
func _run_and_jump(dir: int, jump_x: float, x_end: float, limit := 5.0) -> Vector2:
	var move := "move_right" if dir > 0 else "move_left"
	Input.action_press(move)
	var jumped := false
	var jump_t := 0.0
	var t := 0.0
	while t < limit:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var x := _player.global_position.x
		if not jumped and ((dir > 0 and x >= jump_x) or (dir < 0 and x <= jump_x)):
			jumped = true
			Input.action_press("jump")
		if jumped:
			jump_t += dt
			if jump_t > 0.35 and Input.is_action_pressed("jump"):
				Input.action_release("jump")
		if (dir > 0 and x >= x_end) or (dir < 0 and x <= x_end):
			if _player.is_on_floor():
				break
	_release_all()
	# 멈춰 서기
	await _until(func(): return _player.is_on_floor() and absf(_player.velocity.x) < 5.0, 1.0)
	return _player.global_position


## 방향을 누른 채 가다가 x 가 jump_x 를 지나면 한 번 점프(0.35초 누름). done() 이 참이 되면(바닥에 섰을 때만 검사) 멈춘다.
## walk 가 참이면 걷기 고정(380)으로 간다. 돌아오는 값: done 이 참이 됐는지.
func _go(dir: int, jump_x: float, done: Callable, walk := false, limit := 4.0) -> bool:
	var move := "move_right" if dir > 0 else "move_left"
	_player.walk_locked = walk
	Input.action_press(move)
	var jumped := false
	var jump_t := 0.0
	var t := 0.0
	var ok := false
	while t < limit:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var x := _player.global_position.x
		if not jumped and ((dir > 0 and x >= jump_x) or (dir < 0 and x <= jump_x)):
			jumped = true
			Input.action_press("jump")
		if jumped:
			jump_t += dt
			if jump_t > 0.35 and Input.is_action_pressed("jump"):
				Input.action_release("jump")
		if _player.is_on_floor() and done.call():
			ok = true
			break
	_release_all()
	_player.walk_locked = false
	await _until(func(): return _player.is_on_floor() and absf(_player.velocity.x) < 5.0, 1.0)
	return ok


## canopy_03: 구덩이 위의 가지 다리로 건너기 (가지가 턱 위 220~340 에 걸려 있어 바닥 점프는 머리를 박는다 — 설계상 다리로 건넌다)
func _probe_canopy03_bridges() -> void:
	await _open("canopy_03", "FromCanopy02")
	# 첫 구덩이(1500~1800): 바닥 → P6(1400~1620, 윗면 880) → P7(1700~1940, 윗면 760) → 오른쪽으로 달려 내려서 P3 바닥
	_player.global_position = Vector2(1000.0, 1100.0 - 67.0)
	_player.velocity = Vector2.ZERO
	await _until(func(): return _player.is_on_floor(), 1.0)
	var hp0 := _player.hp
	var a := await _go(1, 1250.0, func(): return absf(_feet() - 880.0) < 6.0 and _player.global_position.x >= 1400.0, true)
	# 달리기 점프는 240px 짜리 P7 을 넘어가 버리므로(그래도 구덩이 건너편 바닥에 떨어진다) 걷기 점프로 P7 에 올라선다
	var b := await _go(1, 1560.0, func(): return absf(_feet() - 760.0) < 6.0 and _player.global_position.x >= 1700.0, true, 2.5)
	var c := await _go(1, INF, func(): return absf(_feet() - 1100.0) < 6.0 and _player.global_position.x >= 1950.0, false, 2.5)
	print("[probe] canopy_03 첫 구덩이 다리: P6 %s → P7 %s → 건너편 바닥 %s, 자리 %s, 피격 %d, hp %.0f→%.0f" % [a, b, c, _player.global_position, _hits, hp0, _player.hp])
	_check(a and b and c and _hits == 0, "canopy_03 첫 구덩이(1500~1800)를 가지 다리 P6→P7 로 건넘 (피격 없음)")
	# 둘째 구덩이(3400~3700): 바닥 → P9(3200~3440, 윗면 860) → P10(3550~3810, 윗면 720) → 내려서 P5 바닥
	_player.global_position = Vector2(2850.0, 1100.0 - 67.0)
	_player.velocity = Vector2.ZERO
	await _until(func(): return _player.is_on_floor(), 1.0)
	_hits = 0
	a = await _go(1, 3060.0, func(): return absf(_feet() - 860.0) < 6.0 and _player.global_position.x >= 3200.0, true)
	b = await _go(1, 3400.0, func(): return absf(_feet() - 720.0) < 6.0 and _player.global_position.x >= 3550.0, false, 2.5)
	c = await _go(1, INF, func(): return absf(_feet() - 1100.0) < 6.0 and _player.global_position.x >= 3750.0, false, 2.5)
	print("[probe] canopy_03 둘째 구덩이 다리: P9 %s → P10 %s → 건너편 바닥 %s, 자리 %s, 피격 %d" % [a, b, c, _player.global_position, _hits])
	_check(a and b and c and _hits == 0, "canopy_03 둘째 구덩이(3400~3700)를 가지 다리 P9→P10 로 건넘 (피격 없음)")
	# 되돌아오기: P5 바닥 → P11(3900~4140, 860) → P10 → P9 → P3 바닥 (왼쪽)
	_player.global_position = Vector2(4300.0, 1100.0 - 67.0)
	_player.velocity = Vector2.ZERO
	await _until(func(): return _player.is_on_floor(), 1.0)
	_hits = 0
	a = await _go(-1, 4280.0, func(): return absf(_feet() - 860.0) < 6.0 and _player.global_position.x <= 4140.0, true)
	b = await _go(-1, 3960.0, func(): return absf(_feet() - 720.0) < 6.0 and _player.global_position.x <= 3810.0, true, 2.5)   # 걷기 점프 (달리면 P10 왼쪽 끝에 떨어져 미끄러진다)
	c = await _go(-1, 3600.0, func(): return absf(_feet() - 860.0) < 6.0 and _player.global_position.x <= 3440.0, true, 2.5)   # 걷기 점프 (달리면 P9 를 넘어 바닥에 떨어진다)
	var d := await _go(-1, INF, func(): return absf(_feet() - 1100.0) < 6.0 and _player.global_position.x <= 3300.0, false, 2.5)
	print("[probe] canopy_03 둘째 구덩이 되돌아오기: P11 %s → P10 %s → P9 %s → 바닥 %s, 자리 %s, 피격 %d" % [a, b, c, d, _player.global_position, _hits])
	_check(a and b and c and d and _hits == 0, "canopy_03 둘째 구덩이를 반대로(P11→P10→P9) 건너 돌아옴 (피격 없음)")


# ---------- 1) mine_01 내려가기 ----------
func _probe_mine01_descent() -> void:
	await _open("mine_01", "FromVillage")
	var p0 := _player.global_position
	_check(absf(p0.x - 120.0) < 5.0 and absf(_feet() - 300.0) < 6.0 and _player.is_on_floor(), "mine_01 FromVillage 선반(P1, 윗면 300)에 섰다: %s" % p0)
	var hp0 := _player.hp
	# 선반 끝 가시(1204~1356)를 달리기 점프로 넘어 디딤 가지 P1b(1450~1710, 윗면 480)에
	var p := await _run_and_jump(1, 1120.0, 1480.0, 3.0)
	var on_p1b := _player.is_on_floor() and absf(_feet() - 480.0) < 6.0 and p.x >= 1450.0 and p.x <= 1710.0
	print("[probe] 가시 넘은 뒤 자리 %s (발 y %.0f), 피격 %d, hp %.0f→%.0f" % [p, _feet(), _hits, hp0, _player.hp])
	_check(on_p1b and _hits == 0, "선반 끝 가시 160px 를 달리기 점프로 넘어 디딤 가지 P1b 에 착지 (피격 없음)")
	# P1b 에서 오른쪽으로 달려 내려서면 P2(1800~2600, 윗면 600)
	Input.action_press("move_right")
	var ok := await _until(func(): return _player.is_on_floor() and absf(_feet() - 600.0) < 6.0 and _player.global_position.x >= 1800.0, 3.0)
	_release_all()
	print("[probe] P2 도착 자리 %s (발 y %.0f), 피격 %d" % [_player.global_position, _feet(), _hits])
	_check(ok and _hits == 0, "P1b 에서 달려 내려서 (1800,600) 발판 P2 에 착지")
	# P2 에서 왼쪽으로 계속 달리면 one_way 디딤 가지들을 차례로 밟고 내려간다: P4b(900) → P4(1150) → P6(1700) → P8(2250) → 바닥(3000)
	await _until(func(): return _player.is_on_floor() and absf(_player.velocity.x) < 5.0, 1.0)
	var trace: Array[int] = [int(_feet())]
	Input.action_press("move_left")
	var t := 0.0
	while t < 8.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if _player.is_on_floor():
			var fy := int(roundf(_feet()))
			if absi(fy - trace[-1]) > 6:
				trace.append(fy)
			if absf(_feet() - 3000.0) < 6.0:
				break
	_release_all()
	print("[probe] P2 에서 왼쪽으로 계속 달려 내려간 발판 윗면 y 자취: %s, 지금 %s, 피격 %d" % [trace, _player.global_position, _hits])
	_check(absf(_feet() - 3000.0) < 6.0 and _hits == 0, "P2 → 왼쪽으로 달려 내려가 바닥(3000)에 닿음 (가시 없음)")
	_check(trace.has(900) and trace.has(1150) and trace.has(1700) and trace.has(2250), "내려오며 디딤 가지 P4b(900)·P4(1150)·P6(1700)·P8(2250)을 밟았다")
	# 바닥을 오른쪽으로 달려 Exit2(2410) 앞까지
	await _until(func(): return absf(_player.velocity.x) < 5.0, 1.0)
	Input.action_press("move_right")
	ok = await _until(func(): return _player.is_on_floor() and absf(_feet() - 3000.0) < 6.0 and _player.global_position.x >= 2380.0, 6.0)
	_release_all()
	await _until(func(): return absf(_player.velocity.x) < 5.0, 1.0)
	var near_exit := absf(_player.global_position.x - 2410.0) < 130.0 and absf(_feet() - 3000.0) < 6.0
	print("[probe] 바닥 Exit2 앞 %s (발 y %.0f), 피격 %d, hp %.0f, 상호작용 가능 %s" % [_player.global_position, _feet(), _hits, _player.hp, _player.can_interact])
	_check(ok and near_exit and _player.can_interact and _hits == 0 and is_equal_approx(_player.hp, hp0), "FromVillage → Exit2 포탈 앞까지 가시에 한 번도 닿지 않고 도착 (hp 그대로, 포탈 상호작용 가능)")
	# 가시 판정 자체는 살아 있다: 선반 끝 가시에 걸어 들어가면 15 피해 + 마지막 안전 자리로 복귀
	_player.global_position = Vector2(1000.0, 300.0 - 67.0)
	_player.velocity = Vector2.ZERO
	_player.walk_locked = true
	await _until(func(): return _player.is_on_floor(), 1.0)
	await get_tree().create_timer(0.5).timeout   # 안전 자리 기억(0.35초) 뒤
	var safe := _player.last_safe_position
	var hp_before := _player.hp
	Input.action_press("move_right")
	ok = await _until(func(): return _hits > 0, 4.0)
	_release_all()
	_player.walk_locked = false
	await get_tree().create_timer(0.6).timeout
	# 안전 자리는 걷는 동안 계속 갱신되므로(0.35초 뒤부터 매 프레임) 가시 바로 앞 선반 위로 돌아온다
	print("[probe] 선반 끝 가시에 걸어 들어감: 피격 %d, hp %.0f→%.0f, 되돌아온 자리 %s (출발 때 안전 자리 %s)" % [_hits, hp_before, _player.hp, _player.global_position, safe])
	_check(ok and _player.hp < hp_before and _player.is_on_floor() and absf(_feet() - 300.0) < 6.0 and _player.global_position.x < 1200.0 and _player.input_enabled,
		"선반 끝 가시(1200~1360)에 닿으면 15 피해 + 가시 앞 선반(P1) 위로 돌아오고 다시 움직일 수 있다")


# ---------- 2) mine_01 one_way 위로 통과 (이단 점프) ----------
func _probe_mine01_oneway_up() -> void:
	await _open("mine_01", "FromMine02")
	Progress.gain_ability("double_jump")
	_player._apply_abilities()
	_player.global_position = Vector2(1500.0, 3000.0 - 67.0)   # P9(1100~1800, 윗면 2540) 바로 아래 바닥
	_player.velocity = Vector2.ZERO
	await _until(func(): return _player.is_on_floor(), 1.0)
	var p9: Platform = _room.get_node("Terrain/P9")
	_check(p9.one_way, "mine_01 P9 는 one_way 발판")
	Input.action_press("jump")
	var t := 0.0
	var top := _feet()
	var second := false
	while t < 2.5:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		top = minf(top, _feet())
		if t >= 0.4 and not second:
			second = true
			Input.action_release("jump")
			await get_tree().physics_frame
			Input.action_press("jump")
		if t >= 0.9 and Input.is_action_pressed("jump"):
			Input.action_release("jump")
		if t > 1.2 and _player.is_on_floor():
			break
	_release_all()
	print("[probe] 바닥(3000)에서 이단 점프: 최고 발 y %.0f, 지금 발 y %.0f, 바닥 %s, x %.0f" % [top, _feet(), _player.is_on_floor(), _player.global_position.x])
	_check(_player.is_on_floor() and absf(_feet() - 2540.0) < 6.0, "이단 점프로 one_way 발판 P9(460 위)를 아래에서 통과해 위에 올라섰다")


# ---------- 3·5) 가시 구덩이 달리기 점프 ----------
func _probe_pit(room_id: String, spawn: String, floor_y: float, x_start: float, jump_x: float, x_end: float, label: String) -> void:
	await _open(room_id, spawn)
	_player.global_position = Vector2(x_start, floor_y - 67.0)
	_player.velocity = Vector2.ZERO
	await _until(func(): return _player.is_on_floor(), 1.0)
	var hp0 := _player.hp
	var dir := 1 if x_end > x_start else -1
	var p := await _run_and_jump(dir, jump_x, x_end, 4.0)
	var crossed := (p.x >= x_end if dir > 0 else p.x <= x_end) and _player.is_on_floor() and absf(_feet() - floor_y) < 6.0
	print("[probe] %s %s: 도착 %s (발 y %.0f), 피격 %d, hp %.0f→%.0f" % [room_id, label, p, _feet(), _hits, hp0, _player.hp])
	_check(crossed and _hits == 0, "%s %s 달리기 점프로 건넘 (피격 없음)" % [room_id, label])


# ---------- 4) canopy_02 one_way 위로 통과 (이단 점프 없이) ----------
func _probe_canopy02_oneway_up() -> void:
	await _open("canopy_02", "FromCanopy01")
	# 수관은 이단 점프 전: 앞 시험에서 얻은 능력을 잠시 끈다
	var had := Progress.has_ability("double_jump")
	if had:
		Progress.abilities.erase("double_jump")
	_player._apply_abilities()
	_player.global_position = Vector2(330.0, 2400.0 - 67.0)   # P4(200~460, 윗면 2150) 바로 아래 바닥
	_player.velocity = Vector2.ZERO
	await _until(func(): return _player.is_on_floor(), 1.0)
	var p4: Platform = _room.get_node("Terrain/P4")
	var p6: Platform = _room.get_node("Terrain/P6")
	_check(p4.one_way and not p6.one_way, "canopy_02: P4 는 one_way, 구덩이 위의 P6 는 one_way 아님 (최대 점프 수 %d)" % _player.max_jumps)
	Input.action_press("jump")
	var t := 0.0
	var top := _feet()
	while t < 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		top = minf(top, _feet())
		if t >= 0.45 and Input.is_action_pressed("jump"):
			Input.action_release("jump")
		if t > 0.9 and _player.is_on_floor():
			break
	_release_all()
	print("[probe] canopy_02 바닥(2400)에서 한 번 점프: 최고 발 y %.0f, 지금 발 y %.0f, 바닥 %s" % [top, _feet(), _player.is_on_floor()])
	_check(_player.is_on_floor() and absf(_feet() - 2150.0) < 6.0, "이단 점프 없이 one_way 발판 P4(250 위)를 아래에서 통과해 올라섰다")
	if had:
		Progress.gain_ability("double_jump")


# ---------- 6) 포탈: ↑는 무시, 손길로만 ----------
func _probe_portal_interact_only() -> void:
	await _open("canopy_hidden", "FromCanopy01")
	var portal: Portal = _room.get_node("Exits/Exit1")
	_player.global_position = portal.global_position + Vector2(-40, -70)
	_player.velocity = Vector2.ZERO
	await _until(func(): return _player.is_on_floor() and _player.can_interact, 1.5)
	_check(_player.can_interact, "포탈 앞: 상호작용 가능")
	var names: Array = portal.get_script().get_script_method_list().map(func(m): return m["name"])
	_check(not names.has("_physics_process"), "portal.gd 에 ↑ 진입 코드(_physics_process)가 없다")
	Game._busy = true   # 실제 장면 전환(Game.go_to)은 막는다 — _enter 가 next_spawn 을 쓰는 것까지만 본다
	Input.action_press("move_up")
	await get_tree().physics_frame
	await get_tree().process_frame
	Input.action_release("move_up")
	await get_tree().create_timer(0.3).timeout
	_check(Progress.next_spawn == "" and _player.input_enabled and not portal._used, "↑를 눌러도 포탈에 들어가지 않는다 (next_spawn '%s', 입력 가능 %s)" % [Progress.next_spawn, _player.input_enabled])
	Input.action_press("interact")
	await get_tree().physics_frame
	await get_tree().process_frame
	Input.action_release("interact")
	await get_tree().physics_frame
	print("[probe] 손길 뒤 next_spawn '%s', 입력 잠김 %s, 포탈 사용됨 %s, 안내 글 '%s'" % [Progress.next_spawn, not _player.input_enabled, portal._used, portal._prompt.text])
	_check(Progress.next_spawn == portal.spawn_name and portal._used and not _player.input_enabled, "손길(interact)로는 포탈에 들어간다 (next_spawn = '%s')" % portal.spawn_name)
	_check(not ("↑" in portal._prompt.text), "포탈 안내 글에 ↑가 없다: '%s'" % portal._prompt.text)
	Game._busy = false
	Progress.next_spawn = ""
	await _close()

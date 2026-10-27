extends Node
## v1.1.0 스태미너·3타 콤보 시험 (기획자 요청 10·11·12·15·17·18, 명세 §2). 화면 없이 돈다.
## 실행: godot --headless --path . res://tools/probe_stamina.tscn      마지막 줄 "[probe] 끝: 실패 N".
## 첫 방(canopy_01)을 띄우고 적을 치운 뒤 진짜 소녀를 Input.action_press 로 조종한다.
##  (a) 공격 비용 10/12/15: 100 → 1·2·3타 → 63, 바로 다시 1·2타 → 41
##  (b) 9 남으면 1타를 시작하지 않고 stamina_refused / 콤보 중 12 미만이면 2타 없이 콤보 끝
##  (c) 공격·씨앗 베기·낙하 공격·가드·3타 후딜레이 동안 회복 0, 벗어난 뒤 0.5초 0, 그 뒤 28/초 (맥동 30.8), 바람·빛 쏜 뒤 0.7초 0
##  (d) 3타 되돌림 0.35초, 그동안 공격·영혼 기술·낙하 공격 거절(기억도 안 함), 가드·구르기는 됨, 끝나면 1타부터
##  (e) 후딜레이 동안 Engine.time_scale 1.0 (게임 전체가 멈추지 않는다)
##  (f) 수액의 맥동: 3타가 적 둘을 맞혀도 +12 한 번, 1·2타·막힘은 0 / 낙하 공격 피해 ×1.3·판정 ×1.15
##  (g) 최대 스태미너 새순 0~3단계 → 100/103/106/109, _apply_abilities 뒤에도 그대로, HUD 막대 길이 1.09배
##  (h) 새순 단계 배율: 일반 공격·씨앗·바람·빛의 피해·범위·쿨다운 (바람·빛도 실제로 쏴서 과녁이 잃은 체력)
##  (i) 1·2·3타 휘두름 소리 음높이 1.0 / 1.08 / 0.92 — 소녀 자기 소리 플레이어(SFX 버스)로, Sfx 안쪽을 건드리지 않는다
##  (j) 구르기 스태미너 15 (v1.1.0 맞딜 검수): 100 → 85, 구르는 동안 회복 0 → 끝난 뒤 0.5초 0 → 찬다, 14 면 구르지 않고 stamina_refused,
##      딱 15 면 구르고 0, 터치 회피 버튼은 15 미만이면 꺼짐(어둡게)
##  (k) 영혼 기술 함께 잠김 — v1.1.0 맞딜 검수 2 부터 기본값 0(꺼짐: 씨앗 누름 뒤 바람·빛 바로 쓸 수 있음). 조절용으로 남긴 잠그는 길을 1.65초로 켜고 본다
##      (v1.1.0 맞딜 검수 — 영혼 돌려 쓰기 막기): 씨앗 누름 → 바람·빛도 잠김(제 쿨은 0), 바꾸기는 즉시,
##      바꾼 영혼의 HUD 원·터치 버튼에 꽉 찬 호와 남은 초·버튼 꺼짐, 씨앗 → 바람 → 빛 → 씨앗이 1.65초 간격, 씨앗만 쓰면 리듬 그대로(1.68초),
##      예비동작 중 끊긴 베기·모으는 중 끊긴 빛은 잠김도 돌려줌, 쏴도 스태미너는 그대로(비용 0)
##  (l) v1.1.1 수액의 숨결(여왕 보상, sap_breath): 회복이 다시 시작되기까지의 기다림 ×0.75 — 0.5/0.7/0.8/1.5 → 0.375/0.525/0.6/1.125,
##      실제로 1타가 끝난 뒤 0.33초 0 → 그 뒤 찬다(숨결 없으면 0.45초 0), 막기·가드 깨짐 기다림, 음수 안 됨, 최대치·비용·3타 후딜레이·맥동 그대로,
##      두 번 받아도 하나, 저장·불러오기 뒤 그대로, 여왕을 정화한 옛 저장(판 2, 숨결 없음)을 불러오면 저절로 생김

var _fail := 0
var _room: Node
var _player: Player
const FLOOR_Y := 2200.0    # 첫 방 시작 바닥(x 0~1600) 윗면
const STAND := Vector2(400, FLOOR_Y - 68.0)


func _ready() -> void:
	print("[probe] 시작")
	await _run()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)


## 게임 시간으로 기다린다 (물리 delta 를 더해서)
func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec - 0.0001:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _reset(pos := STAND, stamina := -1.0) -> void:
	_player.global_position = pos
	_player.velocity = Vector2.ZERO
	_player.facing = 1
	_player._set_state(Player.State.IDLE)
	_player._soul_cooldowns.clear()
	_player._combo_lock_timer = 0.0
	_player._plunge_lock = 0.0
	_player._plunge_buffered = false
	_player._plunge_btn_buffered = false
	_player._attack_buffered = false
	await _frames(4)
	_player.guard = _player.max_guard if stamina < 0.0 else stamina
	_player._guard_regen_delay = 0.0


## 게임 시계 (물리 delta 를 더한다 — 신호를 받은 순간의 시각을 적으려고)
var _clk := 0.0


func _physics_process(delta: float) -> void:
	_clk += delta


func _approx(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps


func _spawn_dummy(x: float) -> EnemyBase:
	var e: EnemyBase = load("res://scenes/enemies/woodcutter.tscn").instantiate()
	e.position = Vector2(x, FLOOR_Y - 66.0)
	_room.add_child(e)
	e.max_hp = 99999.0
	e.hp = 99999.0
	e.max_poise = 100000.0
	e.set_physics_process(false)   # 움직이지 않는 과녁
	return e


func _run() -> void:
	_room = load("res://scenes/rooms/canopy_01.tscn").instantiate()
	add_child(_room)
	await _frames(12)
	_player = get_tree().get_first_node_in_group("player") as Player
	_check(_player != null, "첫 방에 소녀가 있다")
	if _player == null:
		return
	_player._invuln_timer = 99999.0
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	Progress.abilities.erase("sap_pulse")
	for t in Progress.TOKEN_TRACKS:
		Progress.upgrades.erase("tok_" + t)
	Progress.ability_gained.emit("upgrade")
	await _frames(4)
	await _test_costs()
	await _test_refuse()
	await _test_regen()
	await _test_combo_lock()
	await _test_time_scale()
	await _test_sap_pulse()
	await _test_max_stamina()
	await _test_token_mults()
	await _test_swing_pitch()
	await _test_roll()
	await _test_soul_lock()
	await _test_sap_breath()


## 공격 버튼을 눌러 그 타가 시작되기를 기다린다. 시작되면 그 순간의 스태미너를 돌려준다 (-1 = 시작 안 됨)
func _press_until_step(step: int, max_frames := 40) -> float:
	for i in max_frames:
		if _player.state == Player.State.ATTACK and _player.attack_step == step:
			return _player.guard
		# 앞 타의 되돌림 중이거나 대기 중이면 누른다
		if _player.state != Player.State.ATTACK or _player.attack_phase == "recovery":
			await _tap("attack_light")
			await get_tree().physics_frame   # 누른 것은 다음 물리 프레임에 잡힌다 (매 프레임 다시 누르면 '방금 누름'이 계속 밀린다)
		else:
			await get_tree().physics_frame
	return -1.0


# ---------- (a) 공격 비용 ----------
func _test_costs() -> void:
	await _reset()
	_check(_approx(_player.stamina, 100.0) and _approx(_player.max_stamina, 100.0), "시작 스태미너 100 (stamina·max_stamina 별칭 = guard·max_guard)")
	var g1 := await _press_until_step(1)
	var g2 := await _press_until_step(2)
	var g3 := await _press_until_step(3)
	print("[probe] 100 에서 1·2·3타: %.2f → %.2f → %.2f" % [g1, g2, g3])
	_check(_approx(g1, 90.0) and _approx(g2, 78.0) and _approx(g3, 63.0), "1·2·3타 비용 10/12/15 → 63 (합 37)")
	# 3타 후딜레이가 끝나자마자 (회복 지연 0.5초 안에) 다시 1·2타
	while _player.state == Player.State.ATTACK or _player.combo_lock_left() > 0.0:
		await get_tree().physics_frame
	var g4 := await _press_until_step(1)
	var g5 := await _press_until_step(2)
	print("[probe] 바로 다시 1·2타: %.2f → %.2f" % [g4, g5])
	_check(_approx(g4, 53.0) and _approx(g5, 41.0), "다시 1·2타 → 53 → 41 (회복 지연 중이라 차지 않았다)")
	await _wait(1.2)


# ---------- (b) 모자라면 시작하지 않는다 ----------
func _test_refuse() -> void:
	var got := {"n": 0}
	var cb := func(): got["n"] += 1
	_player.stamina_refused.connect(cb)
	await _reset(STAND, 9.0)
	_player._guard_regen_delay = 5.0   # 시험 중 저절로 차지 않게
	await _tap("attack_light")
	await _frames(3)
	print("[probe] 9 남음 → 상태 %s, 스태미너 %.2f, 거절 신호 %d" % [_player.state_name(), _player.guard, got["n"]])
	_check(_player.state != Player.State.ATTACK and _approx(_player.guard, 9.0) and got["n"] == 1, "스태미너 9 이면 1타(10)를 시작하지 않고 stamina_refused 를 보낸다")
	# 콤보 중 12 미만: 21 → 1타(11 남음) → 2타 거절, 콤보 끝
	await _reset(STAND, 21.0)
	_player._guard_regen_delay = 5.0
	got["n"] = 0
	var g1 := await _press_until_step(1)
	var saw_step2 := false
	var presses := 0
	while _player.state == Player.State.ATTACK:
		if _player.attack_step >= 2:
			saw_step2 = true
		if _player.attack_phase == "recovery" and presses < 4:
			presses += 1
			await _tap("attack_light")   # 되돌림 중 여러 번 눌러도 잇지 않는다
		else:
			await get_tree().physics_frame
	print("[probe] 21 → 1타 뒤 %.2f, 2타 나옴 %s, 거절 신호 %d, 끝 상태 %s" % [g1 - 0.0, saw_step2, got["n"], _player.state_name()])
	_check(_approx(g1, 11.0) and not saw_step2 and got["n"] >= 1 and _player.state != Player.State.ATTACK, "콤보 중 다음 타 비용(12)이 모자라면 2타 없이 콤보가 끝나고 대기로")
	_check(got["n"] == 1, "되돌림 동안 다시 눌러도 거절은 한 번만 (콤보가 끝났다)")
	_player.stamina_refused.disconnect(cb)
	await _wait(0.6)


## 지금 상태에서 sec 초 동안 스태미너가 늘었는가 (늘어난 양)
func _gain_over(sec: float) -> float:
	var g0 := _player.guard
	await _wait(sec)
	return _player.guard - g0


# ---------- (c) 자연 회복 막기 ----------
func _test_regen() -> void:
	# 공격 중: 1타 동안 줄곧 그대로
	await _reset(STAND, 60.0)
	_player._guard_regen_delay = 0.2   # 누르는 동안 차지 않게 (공격이 끝나면 0.5 로 다시 걸린다)
	await _press_until_step(1)
	var paid := _player.guard
	var max_seen := paid
	while _player.state == Player.State.ATTACK:
		await get_tree().physics_frame
		max_seen = maxf(max_seen, _player.guard)
	var after := _player.guard
	var g_045 := await _gain_over(0.45)
	var g_more := await _gain_over(0.5)
	print("[probe] 1타: 낸 뒤 %.2f, 공격 중 최대 %.2f, 끝난 순간 %.2f, 0.45초 동안 +%.2f, 그다음 0.5초 +%.2f" % [paid, max_seen, after, g_045, g_more])
	_check(_approx(max_seen, paid) and _approx(after, paid), "약공격 중에는 스태미너가 차지 않는다")
	_check(_approx(g_045, 0.0) and g_more > 0.5 * 28.0 * 0.85 and g_more < 0.5 * 28.0 * 1.1, "공격이 끝난 뒤 0.5초는 0, 그 뒤 초당 28 (0.5초에 +%.1f)" % g_more)
	# 씨앗 베기 중
	await _reset(STAND, 50.0)
	_player.soul = "seed"
	await _tap("soul_ability")
	await get_tree().physics_frame
	var in_slash := _player.state == Player.State.SOUL_SLASH
	var g_slash := 0.0
	var g_start := _player.guard
	while _player.state == Player.State.SOUL_SLASH:
		await get_tree().physics_frame
		g_slash = maxf(g_slash, _player.guard - g_start)
	var g_slash_after := await _gain_over(0.45)
	_check(in_slash and _approx(g_slash, 0.0) and _approx(g_slash_after, 0.0), "씨앗 베기 중과 끝난 뒤 0.45초 동안 스태미너 0 (비용도 0: %.1f)" % _player.guard)
	await _wait(0.6)
	# 낙하 공격 중
	await _reset(STAND + Vector2(0, -400), 50.0)
	_player._set_state(Player.State.FALL)
	_player._guard_regen_delay = 5.0
	await get_tree().physics_frame
	_player._guard_regen_delay = 0.0
	_player._start_plunge()
	var g_pl0 := _player.guard
	var g_pl := 0.0
	var saw_plunge := false
	while _player.state == Player.State.PLUNGE or not saw_plunge:
		saw_plunge = saw_plunge or _player.state == Player.State.PLUNGE
		await get_tree().physics_frame
		g_pl = maxf(g_pl, _player.guard - g_pl0)
		if not saw_plunge and _player.state != Player.State.PLUNGE:
			break
	var g_pl_after := await _gain_over(0.45)
	print("[probe] 낙하 공격: 시작 %.2f, 낙하 공격 중 늘어난 최대 %.2f, 끝난 뒤 0.45초 +%.2f, 지금 %.2f" % [g_pl0, g_pl, g_pl_after, _player.guard])
	_check(saw_plunge and _approx(g_pl, 0.0) and _approx(g_pl_after, 0.0) and _approx(_player.guard, g_pl0), "낙하 공격 중과 끝난 뒤 0.45초 동안 스태미너 0 (비용 0)")
	await _wait(0.6)
	# 가드 유지 중
	await _reset(STAND, 50.0)
	Input.action_press("guard")
	await _frames(2)
	var in_guard := _player.state == Player.State.GUARD
	var g_guard := await _gain_over(1.0)
	Input.action_release("guard")
	await get_tree().physics_frame
	var g_guard_after := await _gain_over(0.45)
	var g_guard_more := await _gain_over(0.5)
	print("[probe] 가드 1초 +%.2f, 놓은 뒤 0.45초 +%.2f, 그다음 0.5초 +%.2f" % [g_guard, g_guard_after, g_guard_more])
	_check(in_guard and _approx(g_guard, 0.0), "가드를 들고 있는 동안 스태미너가 차지 않는다 (유지 비용도 0)")
	_check(_approx(g_guard_after, 0.0) and g_guard_more > 10.0, "가드를 놓은 뒤 0.5초 지나서부터 찬다")
	# 수액의 맥동: 회복 ×1.1 (28 → 30.8)
	Progress.abilities["sap_pulse"] = true
	await _reset(STAND, 20.0)
	var g_rate := await _gain_over(1.0)
	Progress.abilities.erase("sap_pulse")
	await _reset(STAND, 20.0)
	var g_rate0 := await _gain_over(1.0)
	print("[probe] 1초 회복: 기본 %.2f / 맥동 %.2f" % [g_rate0, g_rate])
	_check(absf(g_rate0 - 28.0) < 0.6 and absf(g_rate - 30.8) < 0.6, "자연 회복 초당 28, 수액의 맥동이면 30.8")
	# 바람·빛: 쏜 뒤 0.7초 동안 0
	Progress.gain_ability("wind")
	Progress.gain_ability("light")
	await get_tree().process_frame
	for s in ["wind", "light"]:
		await _reset(STAND, 50.0)
		_player.soul = s
		Progress.soul = s
		_player._guard_regen_delay = 0.1   # 누르는 두 프레임 동안 차지 않게 (쏘는 순간 0.7 로 늘어난다)
		var cast := {"n": 0}
		var on_cast := func(): cast["n"] += 1
		_player.gust_cast.connect(on_cast)
		_player.laser_charge_started.connect(on_cast)
		await _tap("soul_ability")
		while cast["n"] == 0:
			await get_tree().physics_frame
		_player.gust_cast.disconnect(on_cast)
		_player.laser_charge_started.disconnect(on_cast)
		var g_065 := await _gain_over(0.65)
		var g_next := await _gain_over(0.5)
		print("[probe] %s 쏜 뒤 0.65초 +%.2f, 그다음 0.5초 +%.2f" % [s, g_065, g_next])
		_check(_approx(g_065, 0.0) and g_next > 5.0, "%s: 쏜 뒤 0.7초 동안은 스태미너가 차지 않고 그 뒤 찬다" % s)
		await _wait(1.0)
	_player.soul = "seed"
	Progress.soul = "seed"


## 3타까지 이어 친 뒤 3타 되돌림(후딜레이)이 시작되는 순간까지
func _combo_to_lock() -> void:
	await _press_until_step(1)
	await _press_until_step(2)
	await _press_until_step(3)
	while not (_player.state == Player.State.ATTACK and _player.attack_phase == "recovery"):
		await get_tree().physics_frame


# ---------- (d) 3타 후딜레이 ----------
func _test_combo_lock() -> void:
	await _reset()
	await _combo_to_lock()
	var lock0 := _player.combo_lock_left()
	var t := 0.0
	var tried := {"attack": false, "soul": false}
	var regen := 0.0
	var g0 := _player.guard
	var recovery_len := 0.0
	while _player.state == Player.State.ATTACK:
		# 잠금 동안 공격·영혼 기술을 눌러 본다
		if t > 0.05 and not tried["attack"]:
			tried["attack"] = true
			await _tap("attack_light")
		elif t > 0.12 and not tried["soul"]:
			tried["soul"] = true
			await _tap("soul_ability")
		else:
			await get_tree().physics_frame
		t += get_physics_process_delta_time()
		recovery_len = t
		regen = maxf(regen, _player.guard - g0)
	var state_after := _player.state_name()
	await _frames(3)
	print("[probe] 3타 되돌림 %.3f초 (잠금 처음 %.2f), 잠금 중 누른 공격·영혼 → 끝난 뒤 상태 %s / %s, 회복 %.2f" % [recovery_len, lock0, state_after, _player.state_name(), regen])
	_check(_approx(lock0, 0.35, 0.001) and absf(recovery_len - 0.35) < 0.03, "3타 되돌림(후딜레이) 0.35초")
	_check(_player.state != Player.State.ATTACK and _player.state != Player.State.SOUL_SLASH, "후딜레이 중 누른 공격·영혼 기술은 나가지 않고 기억되지도 않는다 (끝난 뒤 %s)" % _player.state_name())
	_check(_approx(regen, 0.0), "후딜레이 동안 스태미너가 차지 않는다")
	# 잠금이 끝나면 1타부터
	await _reset()
	await _combo_to_lock()
	while _player.state == Player.State.ATTACK or _player.combo_lock_left() > 0.0:
		await get_tree().physics_frame
	await _tap("attack_light")
	await get_tree().physics_frame
	_check(_player.state == Player.State.ATTACK and _player.attack_step == 1, "후딜레이가 끝난 뒤 공격은 1타부터 (%s)" % _player.state_name())
	await _wait(1.0)
	# 가드로 끊기: 되지만 잠금은 계속 (가드를 풀고 바로 눌러도 공격이 안 나간다)
	await _reset()
	await _combo_to_lock()
	Input.action_press("guard")
	await _frames(2)
	var guarded := _player.state == Player.State.GUARD
	var lock_in_guard := _player.combo_lock_left()
	Input.action_release("guard")
	await _frames(2)
	await _tap("attack_light")
	await get_tree().physics_frame
	var blocked_attack := _player.state != Player.State.ATTACK
	print("[probe] 후딜레이 중 가드: 상태 가드 %s, 잠금 남음 %.2f, 가드 풀고 공격 → %s" % [guarded, lock_in_guard, _player.state_name()])
	_check(guarded and lock_in_guard > 0.2 and blocked_attack, "후딜레이 중 가드로 동작을 끊을 수 있지만 잠금 시간은 그대로 흘러 공격은 아직 안 나간다")
	await _wait(1.0)
	# 구르기로 끊기
	await _reset()
	await _combo_to_lock()
	await _tap("dodge")
	await _frames(2)
	var rolled := _player.state == Player.State.ROLL
	_check(rolled and _player.combo_lock_left() > 0.0, "후딜레이 중 구르기로 동작을 끊을 수 있다 (잠금은 계속 %.2f)" % _player.combo_lock_left())
	await _wait(1.0)
	# 낙하 공격도 거절: 3타 후딜레이가 시작된 순간 공중으로 띄워 낙하 버튼·↓+공격을 눌러 본다
	await _reset()
	await _combo_to_lock()
	_player.global_position += Vector2(0, -900)
	_player.velocity = Vector2.ZERO
	await get_tree().physics_frame
	var air := not _player.is_on_floor()
	await _tap("plunge")
	await _frames(2)
	var no_plunge := _player.state != Player.State.PLUNGE
	# 잠금 중 ↓+공격도
	Input.action_press("move_down")
	await _tap("attack_light")
	Input.action_release("move_down")
	await _frames(2)
	no_plunge = no_plunge and _player.state != Player.State.PLUNGE
	# 잠금이 끝난 뒤에도 기억해 둔 낙하 공격이 저절로 나가지 않는다
	var auto_plunge := false
	while _player.combo_lock_left() > 0.0 or _player.state == Player.State.ATTACK:
		await get_tree().physics_frame
	for i in 6:
		await get_tree().physics_frame
		auto_plunge = auto_plunge or _player.state == Player.State.PLUNGE
	print("[probe] 공중 3타 후딜레이: 공중 %s, 낙하 버튼·↓+공격 → %s, 잠금 뒤 저절로 낙하 공격 %s" % [air, "안 나감" if no_plunge else "나감", auto_plunge])
	_check(air and no_plunge and not auto_plunge, "후딜레이 중에는 낙하 공격도 나가지 않고, 누른 것을 기억하지도 않는다")
	await _wait(1.5)


# ---------- (e) 게임 전체는 멈추지 않는다 ----------
## (e1) 아무것도 안 맞힌 3타: 후딜레이 내내 Engine.time_scale 1.0.
## (e2) 과녁을 세워 1·2·3타가 실제로 맞게 한다: 맞힌 순간의 짧은 히트스톱(Juice.hitstop, 실제 시간 0.05초)은 타격 연출(hit_impact)
##      때만 걸리고, 후딜레이 자체는 time_scale 을 낮추지 않는다 — 후딜레이 동안 느려진 화면 프레임은 모두 바로 앞 타격 연출
##      0.12초(실제 시간) 안에 있어야 하고, 그 히트스톱이 풀린 뒤로는 1.0 이다. 화면 프레임(process_frame)마다 잰다
##      (히트스톱 중에는 물리 틱이 거의 돌지 않아 물리 프레임으로는 놓친다).
func _test_time_scale() -> void:
	await _reset()
	await _combo_to_lock()
	var min_ts := 10.0
	while _player.combo_lock_left() > 0.0:
		min_ts = minf(min_ts, Engine.time_scale)
		await get_tree().physics_frame
	_check(_approx(min_ts, 1.0, 0.0001), "후딜레이 동안 Engine.time_scale 은 1.0 그대로 (최소 %.3f)" % min_ts)
	await _wait(1.0)
	# (e2) 진짜로 맞히는 콤보
	var e := _spawn_dummy(STAND.x + 160.0)
	await _frames(3)
	await _reset()
	e.hp = e.max_hp
	var rec := {"hit3": 0, "impacts": [], "pre_min": 10.0, "lock_frames": 0, "lock_slow": 0, "unexplained": 0, "lock_min": 10.0, "after_lock": false}
	var on_land := func(res: String, t: Node) -> void:
		if t == e and res == "hit" and _player.attack_step == 3:
			rec["hit3"] += 1
	var on_impact := func(res: String, _t) -> void:
		if res == "hit":
			(rec["impacts"] as Array).append(Time.get_ticks_usec())
	var sampler := func() -> void:
		var ts := Engine.time_scale
		if _player.combo_lock_left() > 0.0:
			rec["after_lock"] = true
			rec["lock_frames"] += 1
			rec["lock_min"] = minf(float(rec["lock_min"]), ts)
			if ts < 1.0:
				rec["lock_slow"] += 1
				var now := Time.get_ticks_usec()
				var explained := false
				for u in rec["impacts"]:
					if now - int(u) <= 120000:
						explained = true
				if not explained:
					rec["unexplained"] += 1
		elif not bool(rec["after_lock"]):
			rec["pre_min"] = minf(float(rec["pre_min"]), ts)
	_player.hitbox.landed.connect(on_land)
	_player.hit_impact.connect(on_impact)
	get_tree().process_frame.connect(sampler)
	await _combo_to_lock()
	while _player.combo_lock_left() > 0.0:
		await get_tree().process_frame
	await get_tree().process_frame
	get_tree().process_frame.disconnect(sampler)
	_player.hitbox.landed.disconnect(on_land)
	_player.hit_impact.disconnect(on_impact)
	var lost := e.max_hp - e.hp
	print("[probe] 맞히는 콤보: 과녁 잃은 체력 %.0f, 3타 적중 %d, 타격 연출 %d번, 후딜레이 전 최소 time_scale %.3f, 후딜레이 화면 프레임 %d (느림 %d, 최소 %.3f, 타격 연출로 설명 안 되는 느림 %d), 끝난 뒤 %.3f" % [lost, rec["hit3"], (rec["impacts"] as Array).size(), rec["pre_min"], rec["lock_frames"], rec["lock_slow"], rec["lock_min"], rec["unexplained"], Engine.time_scale])
	_check(int(rec["hit3"]) == 1 and (rec["impacts"] as Array).size() >= 3 and minf(float(rec["pre_min"]), float(rec["lock_min"])) < 1.0, "과녁을 1·2·3타가 실제로 맞혔고 맞힌 순간 히트스톱이 걸렸다 (시험이 헛돌지 않는다)")
	_check(int(rec["lock_frames"]) > 0 and int(rec["unexplained"]) == 0, "3타를 맞혀도 후딜레이 자체는 time_scale 을 낮추지 않는다 (느린 프레임은 모두 타격 히트스톱 0.05초 안)")
	_check(_approx(Engine.time_scale, 1.0, 0.0001), "후딜레이가 끝나면 time_scale 1.0")
	e.queue_free()
	await _wait(1.0)


# ---------- (f) 수액의 맥동 ----------
func _test_sap_pulse() -> void:
	var a := _spawn_dummy(STAND.x + 150.0)
	var b := _spawn_dummy(STAND.x + 200.0)
	await _frames(3)
	var pulses := []
	var cb := func(v): pulses.append(v)
	_player.stamina_pulsed.connect(cb)
	# 맥동 없이: 3타가 맞아도 0
	await _reset()
	await _combo_to_lock()
	var g_no := _player.guard
	_check(pulses.is_empty() and _approx(g_no, 63.0), "수액의 맥동이 없으면 3타가 맞아도 스태미너가 차지 않는다 (%.2f)" % g_no)
	await _wait(1.2)
	# 맥동: 3타가 둘을 맞혀도 +12 한 번, 1·2타는 0
	Progress.abilities["sap_pulse"] = true
	await _reset()
	a.hp = a.max_hp
	b.hp = b.max_hp
	var g1 := await _press_until_step(1)
	var hp_a1 := 0.0
	while _player.attack_phase != "recovery":
		await get_tree().physics_frame
	var g1_end := _player.guard
	var hit1 := a.max_hp - a.hp
	var g2 := await _press_until_step(2)
	while _player.attack_phase != "recovery":
		await get_tree().physics_frame
	var g2_end := _player.guard
	var g3 := await _press_until_step(3)
	while _player.state == Player.State.ATTACK and _player.attack_phase != "recovery":
		await get_tree().physics_frame
	await _frames(2)
	var g3_end := _player.guard
	hp_a1 = a.max_hp - a.hp
	var hit_b := b.max_hp - b.hp
	print("[probe] 맥동 콤보: 1타 낸 뒤 %.2f → 1타 끝 %.2f (과녁 맞음 %.0f), 2타 낸 뒤 %.2f → 2타 끝 %.2f, 3타 낸 뒤 %.2f → 3타 판정 끝 %.2f, 맥동 신호 %s, 과녁 잃은 체력 %.0f / %.0f" % [g1, g1_end, hit1, g2, g2_end, g3, g3_end, pulses, hp_a1, hit_b])
	_check(hit1 > 0.0 and hp_a1 > hit1 and hit_b > 0.0, "1타부터 과녁을 맞혔고 3타 콤보가 과녁 둘을 모두 맞혔다")
	_check(_approx(g1, 90.0) and _approx(g1_end, 90.0) and _approx(g2, 78.0) and _approx(g2_end, 78.0), "1·2타가 맞아도 맥동 회복은 없다")
	_check(_approx(g3, 63.0) and _approx(g3_end, 75.0) and pulses.size() == 1 and _approx(float(pulses[0]), 12.0), "3타가 둘을 맞혀도 +12 한 번 (63 → 75)")
	# 최대치를 넘지 않는다
	await _wait(1.2)
	await _reset()
	await _press_until_step(1)
	await _press_until_step(2)
	await _press_until_step(3)
	_player.guard = _player.max_guard - 5.0
	while _player.state == Player.State.ATTACK and _player.attack_phase != "recovery":
		await get_tree().physics_frame
	await _frames(2)
	_check(_approx(_player.guard, _player.max_guard), "맥동 회복은 최대 스태미너를 넘지 않는다 (%.2f / %.0f)" % [_player.guard, _player.max_guard])
	await _wait(1.2)
	# 막힘(방패)은 0: 3타 중에 '막힘' 결과가 와도 차지 않는다
	await _reset()
	await _press_until_step(1)
	await _press_until_step(2)
	await _press_until_step(3)
	var gb := _player.guard
	pulses.clear()
	_player._on_hit_landed("blocked", a)
	_player._on_hit_landed("guard", a)
	_check(pulses.is_empty() and _approx(_player.guard, gb), "3타가 막히면(blocked·guard) 맥동 회복은 없다")
	# 적이 아닌 것(지형·벽)은 세지 않는다
	_player._on_hit_landed("hit", _room)
	_check(pulses.is_empty(), "3타가 적이 아닌 것을 맞혀도 맥동 회복은 없다")
	await _wait(1.2)
	_player.stamina_pulsed.disconnect(cb)
	# 낙하 공격: 피해 ×1.3 (26 → 33.8, 18 → 23.4), 판정 ×1.15 (가운데 그대로)
	var dmgs := []
	var cbd := func(res, t): if res == "hit" and t == a: dmgs.append(a.max_hp - a.hp)
	a.hp = a.max_hp
	b.queue_free()
	await _reset(Vector2(a.global_position.x, FLOOR_Y - 68.0 - 380.0))
	_player._jumps_left = 0
	_player._set_state(Player.State.FALL)
	await get_tree().physics_frame
	var hp0 := a.hp
	_player._start_plunge()
	var dive_box := Rect2()
	for i in 90:
		await get_tree().physics_frame
		if _player.state == Player.State.PLUNGE and _player.attack_phase == "dive" and dive_box.size == Vector2.ZERO:
			var sz: Vector2 = (_player.hitbox._shape.shape as RectangleShape2D).size
			dive_box = Rect2(_player.hitbox._shape.position - sz * 0.5, sz)
		if a.hp < hp0:
			break
	var lost := hp0 - a.hp
	var mult := _player.attack_multiplier
	print("[probe] 맥동 낙하 공격: 판정 %s, 과녁 잃은 체력 %.2f (기대 %.2f)" % [dive_box, lost, 26.0 * 1.3 * mult])
	_check(dive_box.position.is_equal_approx(Vector2(-126.5, -52)) and dive_box.size.is_equal_approx(Vector2(253, 184)), "맥동 내려꽂기 판정 Rect2(-126.5,-52,253,184)")
	_check(_approx(lost, 26.0 * 1.3 * mult, 0.05), "맥동 내려꽂기 피해 26 × 1.3 = 33.8")
	_check(_player.plunge_land_box_now().position.is_equal_approx(Vector2(-195.5, -67.5)) and _player.plunge_land_box_now().size.is_equal_approx(Vector2(391, 115)), "맥동 착지 판정 Rect2(-195.5,-67.5,391,115)")
	_check(_approx(_player.plunge_land_damage * _player.plunge_damage_mult(), 23.4), "맥동 착지 피해 18 × 1.3 = 23.4")
	Progress.abilities.erase("sap_pulse")
	_check(_player.plunge_dive_box() == _player.plunge_box and _player.plunge_land_box_now() == _player.plunge_land_box and _approx(_player.plunge_damage_mult(), 1.0), "맥동이 없으면 낙하 공격 판정·피해는 그대로")
	await _wait(1.5)
	a.queue_free()
	await _frames(2)


# ---------- (g) 최대 스태미너 ----------
func _test_max_stamina() -> void:
	await _reset()
	var hud := _room.get_node_or_null("CombatHUD")
	var got := []
	for lv in [0, 1, 2, 3]:
		Progress.upgrades["tok_stamina"] = float(lv)
		Progress.ability_gained.emit("upgrade")
		await get_tree().physics_frame
		_player._apply_abilities()   # 한 번 더 불러도 그대로
		got.append([_player.max_guard, _player.guard])
	print("[probe] 새순 0~3단계 최대 스태미너·현재: %s" % [got])
	_check(_approx(got[0][0], 100.0) and _approx(got[1][0], 103.0) and _approx(got[2][0], 106.0) and _approx(got[3][0], 109.0), "최대 스태미너 100 / 103 / 106 / 109")
	_check(_approx(got[3][1], 109.0), "최대치가 늘면 늘어난 만큼 채운다 (가득 → 109)")
	_check(_approx(Progress.max_stamina(), 109.0) and _approx(_player.max_stamina, 109.0), "Progress.max_stamina() 와 소녀 별칭이 같다")
	if hud and hud.has_method("guard_bar_scale"):
		_check(_approx(hud.guard_bar_scale(), 1.09), "HUD 스태미너 막대 길이 1.09배")
	Progress.upgrades.erase("tok_stamina")
	Progress.ability_gained.emit("upgrade")
	await get_tree().physics_frame
	_check(_approx(_player.max_guard, 100.0) and _player.guard <= 100.0, "단계를 지우면 다시 100")


# ---------- (h) 새순 단계 배율 ----------
func _test_token_mults() -> void:
	for t in ["normal", "seed", "wind", "light"]:
		Progress.upgrades["tok_" + t] = 3.0
	Progress.ability_gained.emit("upgrade")
	await get_tree().physics_frame
	var lb := _player.light_box()
	var sb := _player.seed_slash_box()
	_check(_approx(lb.end.x, 310.5) and _approx(lb.position.x, 30.0), "일반 공격 3단계: 판정 앞끝 270 × 1.15 = 310.5")
	_check(_approx(sb.end.x, 374.0 * 1.15) and _approx(sb.position.x, -60.0) and _approx(sb.size.y, 430.0), "씨앗 3단계: 판정 앞끝 374 × 1.15")
	_check(_approx(_player.soul_cooldown_total("wind"), 4.0) and _approx(_player.soul_cooldown_total("light"), 7.0 * 0.79), "바람 3단계 쿨 5 × 0.8 = 4, 빛 3단계 7 × 0.79")
	# 실제 피해: 과녁을 세워 일반 공격 1타·씨앗 베기
	var e := _spawn_dummy(STAND.x + 160.0)
	await _frames(3)
	await _reset()
	await _press_until_step(1)
	await _wait(0.5)
	var lost1 := e.max_hp - e.hp
	var mult := _player.attack_multiplier
	_check(_approx(lost1, 12.0 * 1.2 * mult, 0.05), "일반 공격 3단계 1타 피해 12 × 1.2 = %.1f (실제 %.2f)" % [12.0 * 1.2 * mult, lost1])
	e.hp = e.max_hp
	await _reset()
	_player.soul = "seed"
	Progress.soul = "seed"
	await _tap("soul_ability")
	await _wait(0.8)
	var lost_s := e.max_hp - e.hp
	_check(_approx(lost_s, 40.0 * 1.3 * mult, 0.05), "씨앗 3단계 피해 40 × 1.3 = %.1f (실제 %.2f)" % [40.0 * 1.3 * mult, lost_s])
	# 바람·빛도 실제로 쏴서: 바람 120 × 1.3 = 156, 빛 95.2 × 1.25 = 119 (_cast_wind/_cast_laser 의 새순 피해 배율)
	for s in [["wind", 120.0, 1.3], ["light", 95.2, 1.25]]:
		e.hp = e.max_hp
		await _reset()
		_player.soul = s[0]
		Progress.soul = s[0]
		await _tap("soul_ability")
		await _wait(1.0)
		var lost_k := e.max_hp - e.hp
		var want: float = float(s[1]) * float(s[2]) * mult
		_check(_approx(lost_k, want, 0.05), "%s 3단계 피해 %.1f × %.2f = %.1f, 한 번만 맞는다 (실제 %.2f)" % [s[0], s[1], s[2], want, lost_k])
	_player.soul = "seed"
	Progress.soul = "seed"
	e.queue_free()
	for t in ["normal", "seed", "wind", "light"]:
		Progress.upgrades.erase("tok_" + t)
	Progress.ability_gained.emit("upgrade")
	await get_tree().physics_frame
	_check(_approx(_player.light_box().end.x, 270.0) and _approx(_player.seed_slash_box().end.x, 374.0), "단계를 지우면 판정이 기본으로 (270 / 374)")


# ---------- (i) 휘두름 소리 음높이 ----------
func _test_swing_pitch() -> void:
	await _reset()
	var swing: AudioStream = load(Sfx.DIR + "swing.wav")
	var got := []
	var ok := true
	for step in [1, 2, 3]:
		await _press_until_step(step)
		var ap := _player.last_pitched_player()
		var want: float = Player.SWING_PITCH[step - 1]
		var p := ap.pitch_scale if ap else -1.0
		got.append("%.3f" % p)
		ok = ok and ap != null and ap.bus == Sfx.BUS and ap.stream == swing and absf(p - want) <= want * 0.031
		while _player.attack_phase != "recovery":
			await get_tree().physics_frame
	print("[probe] 휘두름 음높이 1·2·3타: %s (기대 1.0 / 1.08 / 0.92 ±3%%), 소녀 소리 플레이어 %d개" % [got, _player._pitched_players.size()])
	_check(ok and _player._pitched_players.size() == Player.PITCHED_PLAYERS, "1·2·3타 휘두름 소리가 SFX 버스의 소녀 플레이어에서 1.0 / 1.08 / 0.92 음높이로 난다 (플레이어는 둘만 만든다)")
	await _wait(1.2)


# ---------- (j) 구르기 스태미너 15 ----------
func _test_roll() -> void:
	var got := {"n": 0}
	var cb := func(): got["n"] += 1
	_player.stamina_refused.connect(cb)
	var touch := _room.get_node_or_null("TouchControls")
	# 100 → 구르기 → 85, 구르는 동안 회복 0
	await _reset()
	_check(_approx(_player.roll_stamina_cost, 15.0), "구르기 스태미너 비용 15 (Player.roll_stamina_cost)")
	await _tap("dodge")
	await _frames(2)
	var rolled := _player.state == Player.State.ROLL
	var paid := _player.guard
	var max_seen := paid
	while _player.state == Player.State.ROLL:
		await get_tree().physics_frame
		max_seen = maxf(max_seen, _player.guard)
	var g_045 := await _gain_over(0.45)
	var g_more := await _gain_over(0.5)
	print("[probe] 구르기: 굴렀나 %s, 낸 뒤 %.2f, 구르는 중 최대 %.2f, 끝난 뒤 0.45초 +%.2f, 그다음 0.5초 +%.2f, 거절 %d" % [rolled, paid, max_seen, g_045, g_more, got["n"]])
	_check(rolled and _approx(paid, 85.0) and got["n"] == 0, "100 에서 구르면 85 (비용 15)")
	_check(_approx(max_seen, paid), "구르는 동안 스태미너가 차지 않는다")
	_check(_approx(g_045, 0.0) and g_more > 0.5 * 28.0 * 0.85, "구르기가 끝난 뒤 0.5초는 0, 그 뒤 찬다 (+%.1f)" % g_more)
	await _wait(0.6)
	# 14 → 구르지 않는다 (stamina_refused, 막대 붉은 번쩍임), 터치 회피 버튼 꺼짐
	await _reset(STAND, 14.0)
	_player._guard_regen_delay = 5.0
	got["n"] = 0
	var touch_off: bool = touch == null or not touch.button_enabled("dodge_r")
	await _tap("dodge")
	await _frames(2)
	print("[probe] 14 남음 → 상태 %s, 스태미너 %.2f, 거절 %d, 터치 회피 꺼짐 %s" % [_player.state_name(), _player.guard, got["n"], touch_off])
	_check(_player.state != Player.State.ROLL and _approx(_player.guard, 14.0) and got["n"] == 1, "스태미너 14 면 구르지 않고 stamina_refused 를 보낸다")
	_check(touch_off, "스태미너 15 미만이면 터치 회피 버튼이 꺼진다(어둡게)")
	# 딱 15 → 구르고 0
	await _reset(STAND, 15.0)
	_player._guard_regen_delay = 5.0
	var touch_on: bool = touch == null or touch.button_enabled("dodge_r")
	await _tap("dodge")
	await _frames(2)
	_check(_player.state == Player.State.ROLL and _approx(_player.guard, 0.0) and touch_on, "스태미너가 딱 15 면 구르고 0 이 된다 (터치 회피 버튼 켜짐 %s)" % touch_on)
	_player.stamina_refused.disconnect(cb)
	await _wait(1.0)


# ---------- (k) 영혼 기술 함께 잠김 ----------

## 영혼 기술 버튼을 두 프레임에 한 번 누르며 ev[key] 횟수가 늘 때까지 (최대 max_sec 게임 초). 나갔으면 true.
func _press_soul_until(ev: Dictionary, key: String, max_sec: float) -> bool:
	var n0: int = ev[key]
	var t0 := _clk
	while _clk - t0 < max_sec:
		Input.action_press("soul_ability")
		await get_tree().physics_frame
		Input.action_release("soul_ability")
		if int(ev[key]) > n0:
			return true
		await get_tree().physics_frame
	return false


func _test_soul_lock() -> void:
	Progress.gain_ability("wind")
	Progress.gain_ability("light")
	await get_tree().process_frame
	var touch := _room.get_node_or_null("TouchControls")
	var ev := {"seed": 0, "wind": 0, "light": 0, "seed_t": -1.0, "wind_t": -1.0, "light_t": -1.0}
	var on_seed := func():
		ev["seed"] += 1
		ev["seed_t"] = _clk
	var on_wind := func():
		ev["wind"] += 1
		ev["wind_t"] = _clk
	var on_light := func():
		ev["light"] += 1
		ev["light_t"] = _clk
	_player.soul_slash_started.connect(on_seed)
	_player.gust_cast.connect(on_wind)
	_player.laser_charge_started.connect(on_light)
	# 0) v1.1.0 맞딜 검수 2: 기본값은 0 (꺼짐) — 영혼 돌려 쓰기 맞딜은 보스 쪽 응징으로 막는다 (잘하는 플레이가 느려지지 않게).
	#    씨앗 베기를 누른 바로 다음 틱에 바람으로 바꿔 쏠 수 있다 (바람의 제 쿨 0, 잠김 0).
	_check(_approx(_player.soul_shared_lockout, 0.0), "영혼 기술 함께 잠김 기본값 0 (꺼짐, %.2f)" % _player.soul_shared_lockout)
	await _reset()
	_player.soul = "seed"
	Progress.soul = "seed"
	var ok_off := await _press_soul_until(ev, "seed", 0.2)
	var lock_off := _player.soul_lock_left()
	var wind_off := _player.soul_cooldown_left("wind")
	var light_off := _player.soul_cooldown_left("light")
	print("[probe] 잠김 꺼짐: 씨앗 누름 → 잠김 %.3f, 바람 보이는 쿨 %.3f, 빛 %.3f" % [lock_off, wind_off, light_off])
	_check(ok_off and lock_off == 0.0 and wind_off == 0.0 and light_off == 0.0, "잠김이 꺼져 있으면 씨앗 베기를 눌러도 바람·빛은 잠기지 않는다")
	await _wait(1.0)
	# 아래는 잠그는 길(조절용으로 남긴 코드)이 여전히 맞게 도는지 — 예전 값 1.65초로 켜고 본다 (끝나면 0 으로 되돌린다)
	_player.soul_shared_lockout = 1.65
	var lock_len := _player.soul_shared_lockout
	_check(lock_len < _player.slash_startup + _player.slash_cooldown, "(켰을 때) 함께 잠김(%.2f)이 씨앗만 거듭 쓸 때의 누름 사이(예비 + 제 쿨 = %.2f)보다 짧다 — 씨앗 리듬은 그대로" % [lock_len, _player.slash_startup + _player.slash_cooldown])
	# 1) 씨앗 베기를 누르는 순간 바람·빛도 함께 잠긴다 (바람·빛의 제 쿨은 0 그대로, 쓴 스태미너도 0)
	await _reset()
	_player.soul = "seed"
	Progress.soul = "seed"
	var st0 := _player.guard
	var ok_s0 := await _press_soul_until(ev, "seed", 0.2)
	var lock0 := _player.soul_lock_left()
	var wind_own := _player.soul_own_cooldown_left("wind")
	var wind_left := _player.soul_cooldown_left("wind")
	var light_left := _player.soul_cooldown_left("light")
	print("[probe] 씨앗 누름 → 잠김 %.3f, 바람 제 쿨 %.2f / 보이는 쿨 %.3f, 빛 보이는 쿨 %.3f, 스태미너 %.1f → %.1f" % [lock0, wind_own, wind_left, light_left, st0, _player.guard])
	_check(ok_s0 and lock0 > lock_len - 0.05 and lock0 <= lock_len and wind_own == 0.0 and _approx(wind_left, lock0) and _approx(light_left, lock0),
		"씨앗 베기를 누르면 바람·빛도 함께 잠긴다 (제 쿨 0, 보이는 쿨 = 잠김 %.2f)" % lock0)
	_check(_approx(_player.guard, st0), "영혼 기술은 여전히 스태미너를 쓰지 않는다")
	# 2) 바꾸기는 즉시 — 바뀐 영혼의 HUD 원·터치 버튼이 잠김을 꽉 찬 호와 남은 초로 보이고 버튼은 꺼진다
	await _tap("soul_next")
	await get_tree().physics_frame   # 누른 것은 다음 물리 프레임에 잡힌다
	var switched := _player.soul == "wind"
	var r_full := _player.soul_cooldown_ratio()
	var txt := _player.soul_cooldown_text()
	var btn_off: bool = touch == null or not touch.button_enabled("soul")
	print("[probe] 잠김 중 바람으로 바꿈: 영혼 %s, 비율 %.3f, 남은 초 '%s', 터치 버튼 꺼짐 %s (터치 %s)" % [_player.soul, r_full, txt, btn_off, touch != null])
	_check(switched and r_full > 0.9 and txt == "2" and btn_off, "잠김 중에도 영혼 바꾸기는 즉시, 바람 원·버튼은 꽉 찬 호 · 남은 초 '2' · 터치 영혼 버튼 꺼짐")
	while _clk - float(ev["seed_t"]) < lock_len * 0.5:
		await get_tree().physics_frame
	var r_half := _player.soul_cooldown_ratio()
	_check(absf(r_half - 0.5) < 0.05 and _player.soul_cooldown_text() == "1", "잠김 절반이 지나면 호도 절반 (%.3f), 남은 초 '1'" % r_half)
	# 3) 잠김이 풀릴 때까지 바람은 안 나가고, 풀리면 바로 나간다 (씨앗을 누른 뒤 lock_len 초)
	var ok_w := await _press_soul_until(ev, "wind", 2.0)
	var dt_w: float = float(ev["wind_t"]) - float(ev["seed_t"])
	var seed_own := _player.soul_own_cooldown_left("seed")
	var seed_left := _player.soul_cooldown_left("seed")
	print("[probe] 바람: 씨앗 뒤 %.3f초에 나감, 그 순간 씨앗 제 쿨 %.3f / 보이는 쿨 %.3f" % [dt_w, seed_own, seed_left])
	_check(ok_w and absf(dt_w - lock_len) <= 0.05, "바람은 씨앗을 누른 뒤 %.2f초에야 나간다 (%.3f초)" % [lock_len, dt_w])
	_check(seed_own < 0.3 and seed_left > lock_len - 0.05, "바람을 쏘면 씨앗도 다시 잠긴다 (제 쿨 %.2f 는 거의 끝, 보이는 쿨 %.2f)" % [seed_own, seed_left])
	# 4) 바꿔 가며 써도 lock_len 초에 하나: 바람 → 빛 → 씨앗
	await _tap("soul_next")   # 바람 → 빛
	var ok_l := await _press_soul_until(ev, "light", 2.0)
	var dt_l: float = float(ev["light_t"]) - float(ev["wind_t"])
	await _tap("soul_next")   # 빛 → 씨앗
	var ok_s1 := await _press_soul_until(ev, "seed", 2.0)
	var dt_s: float = float(ev["seed_t"]) - float(ev["light_t"])
	print("[probe] 빛은 바람 뒤 %.3f초, 씨앗은 빛 뒤 %.3f초" % [dt_l, dt_s])
	_check(ok_l and absf(dt_l - lock_len) <= 0.05 and ok_s1 and absf(dt_s - lock_len) <= 0.05, "세 영혼을 바꿔 가며 써도 %.2f초에 하나 (빛 %.3f · 씨앗 %.3f)" % [lock_len, dt_l, dt_s])
	# 5) 씨앗만 거듭 쓰면 리듬은 그대로: 누름 사이 = 예비 0.28 + 제 쿨 1.4 (타격 순간부터) = 1.68 > 잠김 1.65
	var s1: float = ev["seed_t"]
	var ok_s2 := await _press_soul_until(ev, "seed", 2.5)
	var dt_ss: float = float(ev["seed_t"]) - s1
	var want_ss := _player.slash_startup + _player.slash_cooldown
	print("[probe] 씨앗만 거듭: 누름 사이 %.3f초 (예비 + 제 쿨 = %.2f)" % [dt_ss, want_ss])
	_check(ok_s2 and absf(dt_ss - want_ss) <= 0.05, "씨앗만 거듭 쓰면 리듬은 그대로 (%.3f초 ≈ %.2f)" % [dt_ss, want_ss])
	await _wait(1.0)
	# 6) 예비동작 중에 맞아 끊긴 씨앗 베기는 쿨다운처럼 잠김도 돌려준다 → 곧바로 바람을 쓴다
	await _reset()
	_player.soul = "seed"
	Progress.soul = "seed"
	await _press_soul_until(ev, "seed", 0.2)
	await _frames(3)
	var phase := _player.attack_phase
	_player._invuln_timer = 0.0
	var res: String = _player.receive_hit(HitData.make(5.0, 10.0, _player, Vector2(100, -50)), null)
	var lock_after := _player.soul_lock_left()
	_player._invuln_timer = 99999.0
	print("[probe] 베기 예비동작(%s) 중 맞음 → %s, 잠김 %.3f, 씨앗 제 쿨 %.2f" % [phase, res, lock_after, _player.soul_own_cooldown_left("seed")])
	_check(phase == "startup" and res == "hit" and lock_after == 0.0 and _player.soul_own_cooldown_left("seed") == 0.0, "예비동작 중 끊긴 씨앗 베기는 잠김도 쿨다운도 남기지 않는다")
	while _player.state == Player.State.HIT:
		await get_tree().physics_frame
	await _tap("soul_next")   # 씨앗 → 바람
	var ok_w2 := await _press_soul_until(ev, "wind", 0.1)
	_check(ok_w2, "끊긴 베기 뒤 바람은 곧바로 나간다")
	await _wait(1.5)
	# 7) 모으는 중에 맞아 끊긴 빛도 잠김을 돌려준다
	await _reset()
	_player.soul = "light"
	Progress.soul = "light"
	await _press_soul_until(ev, "light", 0.2)
	await _frames(2)
	var lock_charge := _player.soul_lock_left()
	_player._invuln_timer = 0.0
	_player._set_state(Player.State.HIT)
	_player._hit_timer = 0.3
	await _frames(15)
	_player._invuln_timer = 99999.0
	print("[probe] 빛 모으는 중 맞음: 잠김 %.3f → %.3f, 빛 제 쿨 %.2f" % [lock_charge, _player.soul_lock_left(), _player.soul_own_cooldown_left("light")])
	_check(lock_charge > 1.4 and _player.soul_lock_left() == 0.0 and _player.soul_own_cooldown_left("light") == 0.0, "모으는 중에 끊긴 빛은 쿨다운과 함께 잠김도 돌려준다")
	_player.soul_slash_started.disconnect(on_seed)
	_player.gust_cast.disconnect(on_wind)
	_player.laser_charge_started.disconnect(on_light)
	_player.soul_shared_lockout = 0.0
	_player._soul_cooldowns.clear()
	_player.soul = "seed"
	Progress.soul = "seed"
	await _wait(1.0)


# ---------- (l) v1.1.1 수액의 숨결 ----------
func _test_sap_breath() -> void:
	Progress.abilities.erase("sap_breath")
	Progress.abilities.erase("sap_pulse")
	await _reset()
	var base := [_player.regen_delay(_player.stamina_regen_delay_after_action), _player.regen_delay(_player.stamina_regen_delay_after_shot),
		_player.regen_delay(_player.stamina_regen_delay_after_block), _player.regen_delay(_player.stamina_regen_delay_after_break)]
	_check(_approx(base[0], 0.5, 0.0001) and _approx(base[1], 0.7, 0.0001) and _approx(base[2], 0.8, 0.0001) and _approx(base[3], 1.5, 0.0001),
		"숨결 없이: 회복 기다림 공격·구르기·가드 뒤 %.3f / 바람·빛 %.3f / 막은 뒤 %.3f / 깨짐 %.3f (v1.1.0 그대로)" % base)
	var cost0: Array = _player.light_stamina_cost.duplicate()
	var roll0 := _player.roll_stamina_cost
	var lock0 := _player.light_recovery_final
	var max0 := _player.max_guard
	var rate0 := _player.stamina_regen_rate()
	Progress.gain_ability("sap_breath")
	Progress.gain_ability("sap_breath")   # 다시 받아도(보스 재전투·불러오기) 하나 — 참/거짓
	await _frames(2)
	var br := [_player.regen_delay(_player.stamina_regen_delay_after_action), _player.regen_delay(_player.stamina_regen_delay_after_shot),
		_player.regen_delay(_player.stamina_regen_delay_after_block), _player.regen_delay(_player.stamina_regen_delay_after_break)]
	print("[probe] 수액의 숨결: 기다림 %s → %s" % [str(base), str(br)])
	_check(Progress.has_sap_breath() and _approx(br[0], 0.375, 0.0001) and _approx(br[1], 0.525, 0.0001) and _approx(br[2], 0.6, 0.0001) and _approx(br[3], 1.125, 0.0001),
		"숨결: 0.5 → 0.375, 0.7 → 0.525, 0.8 → 0.6, 1.5 → 1.125 (×0.75, 두 번 받아도 한 번만)")
	_check(_player.light_stamina_cost == cost0 and _approx(_player.roll_stamina_cost, roll0) and _approx(_player.light_recovery_final, lock0) and _approx(lock0, 0.35)
		and _approx(_player.max_guard, max0) and _approx(_player.stamina_regen_rate(), rate0) and not Progress.has_sap_pulse(),
		"숨결은 기다림만: 공격 비용 %s·구르기 %.0f·최대 %.0f·회복 빠르기 %.1f·3타 후딜레이 그대로, 맥동과 따로" % [str(_player.light_stamina_cost), _player.roll_stamina_cost, _player.max_guard, _player.stamina_regen_rate()])
	var mult0 := _player.sap_breath_delay_mult
	_player.sap_breath_delay_mult = -1.0
	var neg := _player.regen_delay(0.5)
	_player.sap_breath_delay_mult = mult0
	_check(_approx(neg, 0.0, 0.0001) and _approx(_player.regen_delay(-0.2), 0.0, 0.0001), "기다림은 음수가 되지 않는다 (%.3f)" % neg)
	# 실제로: 1타가 끝난 뒤 0.33초 동안 0, 그다음 0.5초는 (0.045초 기다림 남음 →) 약 0.455초 × 28
	await _reset(STAND, 60.0)
	_player._guard_regen_delay = 0.2
	await _press_until_step(1)
	while _player.state == Player.State.ATTACK:
		await get_tree().physics_frame
	var g_033 := await _gain_over(0.33)
	var g_next := await _gain_over(0.5)
	print("[probe] 숨결 1타 뒤: 0.33초 +%.2f, 그다음 0.5초 +%.2f (숨결 없으면 0.45초까지 0, 그다음 0.5초 약 +14 중 앞 0.12초 0)" % [g_033, g_next])
	_check(_approx(g_033, 0.0) and g_next > 0.45 * 28.0 * 0.9 and g_next < 0.5 * 28.0 * 1.05, "숨결: 공격이 끝난 뒤 0.375초 기다렸다가 찬다 (0.33초 0, 그다음 0.5초 +%.1f)" % g_next)
	# 구르기 뒤도 0.375
	await _reset(STAND, 60.0)
	await _tap("dodge")
	var rolled := false
	for i in 60:
		rolled = rolled or _player.state == Player.State.ROLL
		if rolled and _player.state != Player.State.ROLL:
			break
		await get_tree().physics_frame
	var roll_wait := _player._guard_regen_delay
	_check(rolled and _approx(roll_wait, 0.375, 0.02), "숨결: 구르기가 끝난 순간 기다림 %.3f (0.375)" % roll_wait)
	# 막은 뒤 0.6 / 가드 깨짐 1.125 (receive_hit 로 앞에서 맞힌다)
	await _reset(STAND, 60.0)
	var src := Node2D.new()
	_room.add_child(src)
	src.global_position = _player.global_position + Vector2(120, 0)
	var inv := _player._invuln_timer
	_player._invuln_timer = 0.0
	_player._set_state(Player.State.GUARD)
	_player._guard_pressed_at = -1000.0
	var r1: String = _player.receive_hit(HitData.make(5.0, 0.0, src), null)
	var w_block := _player._guard_regen_delay
	_player.guard = 1.0
	_player._invuln_timer = 0.0
	_player._set_state(Player.State.GUARD)
	_player._guard_pressed_at = -1000.0
	var r2: String = _player.receive_hit(HitData.make(5.0, 0.0, src), null)
	var w_break := _player._guard_regen_delay
	_player._invuln_timer = inv
	src.queue_free()
	print("[probe] 숨결 막기: %s → 기다림 %.3f, %s → 기다림 %.3f" % [r1, w_block, r2, w_break])
	_check(r1 == "guard" and _approx(w_block, 0.6, 0.0001) and r2 == "guard_break" and _approx(w_break, 1.125, 0.0001), "숨결: 막은 뒤 0.6초, 가드가 깨지면 1.125초")
	await _wait(1.6)
	_player.hp = _player.max_hp
	# 저장 → 초기화 → 불러오기 / 여왕을 정화한 옛 저장(숨결 없음)
	var had := FileAccess.file_exists(SaveGame.PATH)
	var backup := FileAccess.get_file_as_string(SaveGame.PATH) if had else ""
	var keep_ab := Progress.abilities.duplicate()
	var keep_diff := Progress.difficulty
	SaveGame.save("", "res://scenes/rooms/canopy_01.tscn")
	Progress.abilities.erase("sap_breath")
	_check(not Progress.has_sap_breath() and _approx(_player.regen_delay(0.5), 0.5, 0.0001), "지운 뒤에는 0.5 (시험 준비)")
	SaveGame.load_game()
	_check(Progress.has_sap_breath() and _approx(_player.regen_delay(0.5), 0.375, 0.0001), "저장·불러오기 뒤에도 숨결 (0.375)")
	var old := {"version": 2, "saved_at": "2026-10-26T10:00:00", "grass": "", "scene": "res://scenes/rooms/canopy_01.tscn",
		"flags": {"boss_queen_defeated": true, "tokens_boss_queen_defeated": true}, "abilities": {"double_jump": true, "sap_walk": true, "sap_pulse": true},
		"soul": "seed", "upgrades": {}, "grasses": {}, "rescued": {}, "visited_rooms": {}, "ending": "", "purity": {}, "collected": {}, "dust": 0}
	var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	SaveGame.load_game()
	var got_old := Progress.has_sap_breath() and Progress.has_sap_pulse() and _approx(_player.regen_delay(0.5), 0.375, 0.0001)
	SaveGame.load_game()
	_check(got_old and Progress.has_sap_breath() and Progress.abilities.keys().count("sap_breath") == 1, "여왕을 정화한 v1.1.0 저장(숨결 없음)을 불러오면 숨결이 생긴다 — 두 번 불러도 하나")
	old["flags"] = {}
	old["abilities"] = {"double_jump": true}
	f = FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	SaveGame.load_game()
	_check(not Progress.has_sap_breath() and _approx(_player.regen_delay(0.5), 0.5, 0.0001), "여왕을 정화하지 않은 저장은 숨결 없음 (0.5)")
	# 되돌림
	if had:
		f = FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	elif FileAccess.file_exists(SaveGame.PATH):
		DirAccess.remove_absolute(SaveGame.PATH)
	Progress.abilities = keep_ab
	Progress.abilities.erase("sap_breath")
	Progress.difficulty = keep_diff

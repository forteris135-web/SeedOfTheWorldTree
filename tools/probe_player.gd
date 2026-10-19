extends Node
## 플레이어 묶음 시험 (화면 없이 돈다). 2026-10-18 기획자 요청분: 씨앗 베기 / 낙하 공격 / 하단 점프 / 가드 보호막 신호 / 투사체 사거리 / 입력 맵.
## 검토 지적분(같은 날): 터치 스틱 세기 문턱 / 이단 점프 없을 때 튕김 / 튕김 뒤 잠금·기억 / 고른 영혼이 방·세이브를 건너 남음 /
##   착지 신호 한 번만 / 옛 키맵 파일 살리기 / 3연타 → 베기 연계 / 끊긴 베기는 쿨다운 없음 / 보호막·초승달 크기.
## 실행: godot --headless --path . res://tools/probe_player.tscn
## 첫 방(canopy_01)을 통째로 띄워 진짜 소녀를 Input.action_press 로 조종한다. 마지막 줄 "[probe] 끝: 실패 N".

var _fail := 0
var _room: Node
var _player: Player
var _dummy: Node2D


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


## 동작을 한 물리 프레임 동안 누른다 (is_action_just_pressed 가 잡힌다)
func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)


func _teleport(pos: Vector2, facing: int) -> void:
	_player.global_position = pos
	_player.velocity = Vector2.ZERO
	_player.facing = facing
	_player._end_drop_through()
	_player._plunge_lock = 0.0
	_player._plunge_buffered = false
	_player._plunge_hits = 0
	_player._set_state(Player.State.IDLE)


func _enemy(name: String) -> EnemyBase:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.name == name:
			return e
	return null


## 적을 시험용으로 되돌린다 (체력·흐트러짐·상태)
func _reset_enemy(e: EnemyBase) -> void:
	e.hp = e.max_hp
	e.poise = 0.0
	if e.state != EnemyBase.State.IDLE:
		e._set_state(EnemyBase.State.IDLE)
	e.velocity = Vector2.ZERO


func _run() -> void:
	_room = load("res://scenes/rooms/canopy_01.tscn").instantiate()
	add_child(_room)
	await _frames(12)
	_player = get_tree().get_first_node_in_group("player") as Player
	_check(_player != null, "첫 방에 소녀가 있다")
	if _player == null:
		return
	_player._invuln_timer = 9999.0   # 적의 공격에 끊기지 않게 (가드 시험 전에 푼다)
	_dummy = Node2D.new()
	_room.add_child(_dummy)
	var gardener := _enemy("Gardener1")
	if gardener:
		gardener.queue_free()   # 씨앗 투사체가 끼어들지 않게
	await _frames(2)

	await _test_input_map()
	await _test_souls()
	await _test_seed_slash()
	await _test_slash_after_combo()
	await _test_slash_cooldown_on_interrupt()
	await _test_plunge()
	await _test_bounce_without_double_jump()
	await _test_plunge_relock()
	await _test_landed_once()
	await _test_drop_through()
	await _test_touch_threshold()
	await _test_projectiles()
	await _test_soul_persist()
	await _test_keymap_old_file()
	await _test_shield_and_crescent_geometry()
	await _test_guard()


# ---------- (f) 입력 맵 ----------
func _test_input_map() -> void:
	_check(not InputMap.has_action("attack_heavy"), "입력 맵에 attack_heavy 가 없다")
	var has_k := false
	var has_rt := false
	var has_i := false
	var has_lt := false
	for e in InputMap.action_get_events("soul_ability"):
		if e is InputEventKey:
			has_k = has_k or e.physical_keycode == KEY_K
			has_i = has_i or e.physical_keycode == KEY_I
		elif e is InputEventJoypadMotion:
			has_rt = has_rt or (e.axis == JOY_AXIS_TRIGGER_RIGHT and e.axis_value > 0.0)
			has_lt = has_lt or (e.axis == JOY_AXIS_TRIGGER_LEFT and e.axis_value > 0.0)
	_check(has_k and has_rt, "soul_ability 에 K 키와 R2/RT 가 들어갔다 (K %s, RT %s)" % [has_k, has_rt])
	_check(has_i and has_lt, "soul_ability 의 기존 I 키와 L2/LT 도 남아 있다")
	_check(not Keymap.ACTIONS.has("attack_heavy") and Keymap.NAMES["soul_ability"] == "영혼 기술", "키맵 목록에서 강공격이 빠지고 영혼 기술 이름표")
	var font := ThemeDB.fallback_font
	var w := font.get_string_size("▸ " + Keymap.NAMES["attack_light"], HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
	_check(w < 360.0, "약공격 이름표가 키 바꾸기 화면의 동작 칸(360px) 안에 든다 (%.0fpx: '%s')" % [w, Keymap.NAMES["attack_light"]])


# ---------- (8) 영혼 목록 ----------
func _test_souls() -> void:
	_check(_player.owned_souls() == ["seed"], "능력 없이도 영혼 목록은 [seed] (%s)" % [_player.owned_souls()])
	_check(_player.soul == "seed" and Progress.soul == "seed", "기본 영혼은 seed (소녀 %s / Progress %s)" % [_player.soul, Progress.soul])
	_check(_player.soul_name() == "씨앗 (세계수의 씨앗)", "soul_name: %s" % _player.soul_name())


# ---------- (a) 씨앗 베기 ----------
func _test_seed_slash() -> void:
	var wc := _enemy("Woodcutter1")
	_check(wc != null, "나무꾼 1이 있다")
	if wc == null:
		return
	_teleport(wc.global_position + Vector2(-150, -10), 1)
	await _frames(8)
	_player.soul = "seed"
	_player._soul_cooldown = 0.0
	var hp0 := wc.hp
	var states := {}
	var active_time := 0.0   # 히트박스가 켜져 있던 게임 시간 (히트스톱 동안은 delta 가 줄어든다)
	var box_size := Vector2.ZERO
	var box_pos := Vector2.ZERO
	var got := {"started": false}   # (람다는 지역 변수를 값으로 잡으므로 사전에 담는다)
	_player.soul_slash_started.connect(func(): got["started"] = true)
	await _tap("soul_ability")
	await get_tree().physics_frame   # 누른 프레임의 처리가 끝난 뒤
	var cd_startup := _player._soul_cooldown
	var cd_active := -1.0
	for i in 70:
		await get_tree().physics_frame
		states[_player.state_name()] = true
		if _player.state == Player.State.SOUL_SLASH and _player.attack_phase == "active":
			active_time += get_physics_process_delta_time()
			box_size = (_player.hitbox._shape.shape as RectangleShape2D).size
			box_pos = _player.hitbox._shape.position
			cd_active = _player._soul_cooldown
	print("[probe] 씨앗 베기: 거친 상태 %s, 히트박스 켜진 시간 %.3f초 (설정 %.2f), 상자 크기 %s 중심 %s, 쿨다운 예비 중 %.2f / 타격 중 %.2f" % [states.keys(), active_time, _player.slash_active, box_size, box_pos, cd_startup, cd_active])
	_check(got["started"] and states.has("씨앗 베기"), "soul_ability(seed) → SOUL_SLASH 상태로 들어간다")
	_check(absf(active_time - _player.slash_active) < 0.04, "히트박스가 약 0.18초 켜진다")
	_check(box_size == Vector2(400, 430) and box_pos == Vector2(140, -35), "히트박스가 앞·위·아래를 넓게 덮는다 (400×430, 중심 (140,-35): 앞 340, 위 250, 아래 180)")
	_check(cd_startup == 0.0 and cd_active > 1.0, "쿨다운 1.4초는 실제로 베는 순간(active)에 걸린다")
	_check(wc.hp < hp0, "근처 나무꾼이 맞아 체력이 줄었다 (%.0f → %.0f, 기대 피해 %.0f)" % [hp0, wc.hp, _player.slash_damage * _player.attack_multiplier])
	_check(_player.state == Player.State.IDLE or _player.state in Player.LOCOMOTION, "베기가 끝나면 대기로 돌아온다 (%s)" % _player.state_name())
	# 앞 멀리 (+300) 에 선 적도 맞는다 (약공격은 255 까지)
	_reset_enemy(wc)
	var far_pos := wc.global_position
	_teleport(far_pos + Vector2(-300, -10), 1)
	await _frames(6)
	_player._soul_cooldown = 0.0
	hp0 = wc.hp
	await _tap("soul_ability")
	for i in 40:
		await get_tree().physics_frame
		wc.global_position = far_pos
		wc.velocity = Vector2.ZERO
	_check(wc.hp < hp0, "앞 300px 의 적도 씨앗 베기에 맞는다 (%.0f → %.0f)" % [hp0, wc.hp])
	await _frames(30)
	# 공중에서도 된다: 뛰어오른 채 누르면 상태가 들어간다
	_teleport(Vector2(300, 2000), 1)
	await _frames(3)
	_player._soul_cooldown = 0.0
	await _tap("soul_ability")
	await _frames(2)
	_check(_player.state == Player.State.SOUL_SLASH and not _player.is_on_floor(), "공중에서도 씨앗 베기가 나간다 (%s, 바닥 %s)" % [_player.state_name(), _player.is_on_floor()])
	await _frames(70)


# ---------- 약공격 되돌림 중 씨앗 베기 연계 ----------
func _test_slash_after_combo() -> void:
	_teleport(Vector2(400, 2132), 1)
	await _frames(3)
	_player._soul_cooldown = 0.0
	await _tap("attack_light")
	var saw_recovery := false
	for i in 40:
		await get_tree().physics_frame
		if _player.state == Player.State.ATTACK and _player.attack_phase == "recovery":
			saw_recovery = true
			break
	await _tap("soul_ability")
	await get_tree().physics_frame
	_check(saw_recovery and _player.state == Player.State.SOUL_SLASH, "약공격 되돌림 중에 영혼 기술을 누르면 바로 씨앗 베기로 이어진다 (%s)" % _player.state_name())
	await _frames(70)


# ---------- 예비동작 중 끊긴 베기는 쿨다운이 없다 ----------
func _test_slash_cooldown_on_interrupt() -> void:
	_player._invuln_timer = 0.0
	_player.hp = _player.max_hp
	_dummy.global_position = Vector2(300, 2132)
	_teleport(Vector2(400, 2132), 1)
	await _frames(3)
	_player._soul_cooldown = 0.0
	await _tap("soul_ability")
	await _frames(3)   # 예비동작(0.28초) 한가운데
	var phase := _player.attack_phase
	var h := HitData.make(5.0, 10.0, _dummy, Vector2(100, -50))
	var res: String = _player.receive_hit(h, null)
	await get_tree().physics_frame
	print("[probe] 베기 예비동작(%s) 중 피격 → %s, 상태 %s, 쿨다운 %.2f" % [phase, res, _player.state_name(), _player._soul_cooldown])
	_check(phase == "startup" and res == "hit" and _player.state == Player.State.HIT and _player._soul_cooldown == 0.0, "예비동작 중 맞아 끊기면 쿨다운을 잃지 않는다")
	_player._invuln_timer = 9999.0
	await _frames(40)


# ---------- (b) 낙하 공격 ----------
func _test_plunge() -> void:
	var wc := _enemy("Woodcutter1")
	if wc == null or not is_instance_valid(wc):
		_check(false, "낙하 공격 시험용 나무꾼이 없다")
		return
	_reset_enemy(wc)
	# 이단 점프가 있을 때: 튕기면 공중 점프 1회가 돌아온다
	Progress.gain_ability("double_jump")
	await get_tree().process_frame
	_check(_player.max_jumps == 2, "이단 점프 켬 (max_jumps=%d)" % _player.max_jumps)
	# 적 머리 위 320px 에서 ↓ + 약공격 (점프 두 번으로 올라온 것처럼 남은 점프 0)
	_teleport(wc.global_position + Vector2(0, -320), 1)
	_player._jumps_left = 0
	await _frames(3)
	_check(not _player.is_on_floor(), "적 위 공중에 떠 있다")
	var hp0 := wc.hp
	var bounced := false
	var min_vy_after_hit := 0.0
	var phases := []
	var hit_at_y := 0.0
	var jumps_after := -1
	Input.action_press("move_down")
	await _tap("attack_light")
	for i in 120:
		await get_tree().physics_frame
		if _player.state == Player.State.PLUNGE and (phases.is_empty() or phases[-1] != _player.attack_phase):
			phases.append(_player.attack_phase)
		if wc.hp < hp0 and not bounced:
			bounced = true
			hit_at_y = _player.global_position.y
			await get_tree().physics_frame
			min_vy_after_hit = _player.velocity.y
			jumps_after = _player._jumps_left
		if bounced and _player.is_on_floor() and i > 20:
			break
	Input.action_release("move_down")
	print("[probe] 낙하 공격(적 위, 이단 점프 있음): 국면 %s, 적 체력 %.0f → %.0f, 맞힌 높이 y=%.0f (적 y=%.0f), 맞힌 직후 세로 속도 %.0f, 남은 점프 %d, 지금 상태 %s" % [phases, hp0, wc.hp, hit_at_y, wc.global_position.y, min_vy_after_hit, jumps_after, _player.state_name()])
	_check(phases.has("pause") and phases.has("dive"), "↓+약공격 → PLUNGE (멈칫 → 급강하)")
	_check(wc.hp < hp0, "떨어지며 적을 맞혔다 (기대 피해 %.0f)" % (_player.plunge_damage * _player.attack_multiplier))
	_check(bounced and min_vy_after_hit < -400.0, "맞히면 튕겨 오른다 (세로 속도 %.0f)" % min_vy_after_hit)
	_check(jumps_after == 1, "이단 점프가 있으면 튕긴 뒤 공중 점프가 1회 돌아온다 (%d)" % jumps_after)
	await _frames(40)
	_check(_player.is_on_floor() and _player.state in [Player.State.IDLE, Player.State.WALK, Player.State.RUN], "그 뒤 바닥에 서서 대기 (%s)" % _player.state_name())

	# 빈 바닥에 착지: 착지 충격 판정과 흐름 pause→dive→land→recovery→IDLE
	_teleport(Vector2(400, 2200 - 67 - 360), 1)
	await _frames(3)
	var got := {"landed": false}
	_player.plunge_landed.connect(func(): got["landed"] = true)
	var phases2 := []
	var land_box := Vector2.ZERO
	var max_vy := 0.0
	Input.action_press("move_down")
	await _tap("attack_light")
	for i in 120:
		await get_tree().physics_frame
		if _player.state == Player.State.PLUNGE:
			if phases2.is_empty() or phases2[-1] != _player.attack_phase:
				phases2.append(_player.attack_phase)
			if _player.attack_phase == "land":
				land_box = (_player.hitbox._shape.shape as RectangleShape2D).size
			max_vy = maxf(max_vy, _player.velocity.y)
		elif not phases2.is_empty():
			break
	Input.action_release("move_down")
	print("[probe] 낙하 공격(빈 바닥): 국면 %s, 최고 낙하 속도 %.0f, 착지 판정 %s, 착지 신호 %s, 끝 상태 %s" % [phases2, max_vy, land_box, got["landed"], _player.state_name()])
	_check(phases2 == ["pause", "dive", "land", "recovery"], "국면이 pause → dive → land → recovery 순서")
	_check(got["landed"] and land_box == Vector2(340, 100), "착지 충격 판정 340×100 과 plunge_landed 신호")
	_check(absf(max_vy - _player.plunge_speed) < 1.0, "급강하 속도 %.0f" % _player.plunge_speed)
	_check(_player.state == Player.State.IDLE, "끝나면 IDLE 로 복귀 (%s)" % _player.state_name())

	# 착지·일어서는 중에 누른 약공격은 기억했다가 1타로 잇는다
	_teleport(Vector2(400, 2200 - 67 - 300), 1)
	await _frames(3)
	Input.action_press("move_down")
	await _tap("attack_light")
	for i in 60:
		await get_tree().physics_frame
		if _player.state == Player.State.PLUNGE and _player.attack_phase == "land":
			break
	Input.action_release("move_down")
	await _tap("attack_light")
	var chained := false
	for i in 30:
		await get_tree().physics_frame
		if _player.state == Player.State.ATTACK and _player.attack_step == 1:
			chained = true
			break
	_check(chained, "착지 중 누른 약공격이 일어서자마자 1타로 이어진다 (%s)" % _player.state_name())
	await _frames(40)

	# ↓ 없이 공중 약공격은 평소 ATTACK
	_teleport(Vector2(400, 2200 - 67 - 300), 1)
	await _frames(3)
	await _tap("attack_light")
	await get_tree().physics_frame
	_check(_player.state == Player.State.ATTACK, "↓ 없이 공중 약공격은 PLUNGE 가 아니라 ATTACK (%s)" % _player.state_name())
	await _frames(60)


# ---------- 이단 점프 없이 튕기면 공중 점프가 생기지 않는다 ----------
func _test_bounce_without_double_jump() -> void:
	Progress.abilities.erase("double_jump")
	_player._apply_abilities()
	_check(_player.max_jumps == 1, "이단 점프 끔 (max_jumps=%d)" % _player.max_jumps)
	var wc := _enemy("Woodcutter1")
	_reset_enemy(wc)
	var pin := wc.global_position
	_teleport(pin + Vector2(0, -320), 1)
	_player._jumps_left = 0   # 땅에서 뛰어올라 온 것처럼
	await _frames(3)
	var jumps := []
	var cb := func(a): jumps.append(a)
	_player.jumped.connect(cb)
	var hp0 := wc.hp
	var bounced := false
	var left_after := -1
	var y_bounce := 0.0
	var min_y := 99999.0
	Input.action_press("move_down")
	await _tap("attack_light")
	for i in 200:
		await get_tree().physics_frame
		if not bounced and wc.hp < hp0:
			bounced = true
			y_bounce = _player.global_position.y
			left_after = _player._jumps_left
			Input.action_release("move_down")
			await _frames(2)
			Input.action_press("jump")
		if bounced:
			min_y = minf(min_y, _player.global_position.y)
			if i > 40 and _player.is_on_floor():
				break
	Input.action_release("jump")
	Input.action_release("move_down")
	_player.jumped.disconnect(cb)
	print("[probe] 이단 점프 없이 튕김: 튕긴 직후 남은 점프 %d, 튕긴 자리 y=%.0f → 최고점 y=%.0f (%.0fpx 위), jumped 신호 %s" % [left_after, y_bounce, min_y, y_bounce - min_y, jumps])
	_check(bounced and left_after == 0 and not jumps.has(true), "이단 점프 능력이 없으면 튕긴 뒤 공중 점프가 생기지 않는다")
	_check(y_bounce - min_y < 120.0, "튕김만으로는 60px 쯤만 오른다 (적을 발판 삼아 능력 관문을 못 건너뛴다)")
	await _frames(30)
	# 발판에서 걸어 떨어진 뒤(코요테 0.1초가 지난 뒤)에는 이단 점프가 없으면 뛸 수 없다 (전엔 땅 점프가 남아 있어 공중에서 한 번 더 뛰었다)
	_teleport(Vector2(400, 1500), 1)
	await _frames(12)   # 0.2초: 코요테 지남
	var left_ledge := _player._jumps_left
	jumps.clear()
	_player.jumped.connect(cb)
	await _tap("jump")
	await _frames(3)
	_player.jumped.disconnect(cb)
	print("[probe] 걸어 떨어진 뒤 0.2초: 남은 점프 %d, 점프 신호 %s" % [left_ledge, jumps])
	_check(left_ledge == 0 and jumps.is_empty(), "이단 점프 없이 걸어 떨어지면 코요테 뒤엔 공중 점프가 없다")
	await _frames(60)


# ---------- 튕긴 뒤 잠금 + 기억, 두 번째부터 피해 감쇠 ----------
func _test_plunge_relock() -> void:
	var wc := _enemy("Woodcutter1")
	var saved := [wc.max_hp, wc.max_poise]
	wc.max_hp = 100000.0
	wc.max_poise = 100000.0   # 무너지지 않게
	_reset_enemy(wc)
	var pin := wc.global_position
	_teleport(pin + Vector2(0, -320), 1)
	await _frames(3)
	var starts := {"n": 0}
	var cb := func(): starts["n"] += 1
	_player.plunge_started.connect(cb)
	var dmgs := []
	var last_hp := wc.hp
	var lock_after_bounce := -1.0
	var state_after_retap := ""
	var buffered := false
	var second_dive_damage := -1.0
	var bounce_frame := -1
	var second_start_frame := -1
	Input.action_press("move_down")
	await _tap("attack_light")
	for i in 240:
		await get_tree().physics_frame
		wc.global_position = pin   # 적을 제자리에 고정 (넉백으로 비껴나지 않게)
		wc.velocity = Vector2.ZERO
		if wc.hp < last_hp:
			dmgs.append(last_hp - wc.hp)
			last_hp = wc.hp
			if dmgs.size() == 1:
				bounce_frame = i
				lock_after_bounce = _player._plunge_lock
				await _tap("attack_light")   # 튕긴 직후 바로 다시 ↓+약공격
				await get_tree().physics_frame
				state_after_retap = _player.state_name()
				buffered = _player._plunge_buffered
		if starts["n"] == 2 and second_start_frame < 0:
			second_start_frame = i
		if starts["n"] == 2 and _player.state == Player.State.PLUNGE and _player.attack_phase == "dive" and second_dive_damage < 0.0:
			second_dive_damage = _player.hitbox.hit.damage
		if dmgs.size() >= 2 and second_start_frame >= 0 and i > second_start_frame + 5:
			break
	Input.action_release("move_down")
	_player.plunge_started.disconnect(cb)
	var mult := _player.attack_multiplier
	print("[probe] 튕김 뒤: 잠금 %.2f초, 바로 다시 누른 뒤 상태 '%s' (기억 %s), 두 번째 낙하 공격 시작까지 %d 프레임, 두 번째 피해 설정 %.1f, 실제 맞힌 피해 %s" % [lock_after_bounce, state_after_retap, buffered, second_start_frame - bounce_frame, second_dive_damage, dmgs])
	_check(lock_after_bounce > 0.2, "튕기면 %.2f초 잠금이 걸린다" % _player.plunge_relock)
	_check(buffered and state_after_retap != "낙하 공격", "잠금 중 ↓+약공격은 바로 나가지 않고 기억된다")
	_check(starts["n"] >= 2 and second_start_frame - bounce_frame >= 13 and second_start_frame - bounce_frame <= 34, "잠금이 풀리면(약 0.25초) 기억한 낙하 공격이 저절로 나간다")
	_check(absf(second_dive_damage - _player.plunge_damage * _player.plunge_repeat_ratio * mult) < 0.01, "바닥에 닿기 전 두 번째 낙하 공격 피해 ×%.1f" % _player.plunge_repeat_ratio)
	_check(dmgs.size() >= 2 and absf(dmgs[0] - _player.plunge_damage * mult) < 0.01 and absf(dmgs[1] - _player.plunge_damage * _player.plunge_repeat_ratio * mult) < 0.01, "실제 피해도 26 → 15.6")
	wc.max_hp = saved[0]
	wc.max_poise = saved[1]
	_reset_enemy(wc)
	await _frames(40)


# ---------- 낙하 공격 착지에 landed 가 따로 나지 않는다 (착지음·찌그러짐 한 번만) ----------
func _test_landed_once() -> void:
	_teleport(Vector2(400, 2200 - 67 - 360), 1)
	await _frames(3)
	var got := {"landed": [], "plunge": 0}
	var c1 := func(v): got["landed"].append(v)
	var c2 := func(): got["plunge"] += 1
	_player.landed.connect(c1)
	_player.plunge_landed.connect(c2)
	Input.action_press("move_down")
	await _tap("attack_light")
	for i in 150:
		await get_tree().physics_frame
		if _player.state != Player.State.PLUNGE and i > 10:
			break
	Input.action_release("move_down")
	await _frames(5)
	_player.landed.disconnect(c1)
	_player.plunge_landed.disconnect(c2)
	print("[probe] 낙하 공격 착지: landed 신호 %s, plunge_landed %d" % [got["landed"], got["plunge"]])
	_check(got["landed"].is_empty() and got["plunge"] == 1, "낙하 공격 착지는 plunge_landed 한 번만 (landed 는 안 남)")
	# 평소 착지는 여전히 landed
	_teleport(Vector2(400, 2200 - 67 - 300), 1)
	_player.landed.connect(c1)
	await _frames(60)
	_player.landed.disconnect(c1)
	_check(got["landed"].size() == 1, "평소 떨어지면 landed 가 난다 (%s)" % [got["landed"]])


# ---------- (c) 하단 점프 (한쪽 방향 발판) ----------
func _test_drop_through() -> void:
	var secret: Platform = _room.get_node_or_null("Terrain/Secret")
	_check(secret != null and secret.one_way, "첫 방 비밀 발판 Secret 은 one_way")
	if secret == null:
		return
	var top_y := secret.global_position.y
	var stand := Vector2(secret.global_position.x + secret.size.x * 0.5, top_y - 67.0 - 1.0)
	_teleport(stand, 1)
	await _frames(6)
	_check(_player.is_on_floor(), "비밀 발판 위에 섰다 (y=%.0f, 바닥 %s)" % [_player.global_position.y, _player.is_on_floor()])
	var got := {"jumped": false, "dropped": false}
	_player.jumped.connect(func(_a): got["jumped"] = true)
	_player.dropped_through.connect(func(_p): got["dropped"] = true)
	var y0 := _player.global_position.y
	Input.action_press("move_down")
	await _tap("jump")
	var trace := []
	for i in 30:
		await get_tree().physics_frame
		if i % 5 == 0:
			trace.append("%.0f" % _player.global_position.y)
	Input.action_release("move_down")
	print("[probe] ↓+점프: y %.0f → %s (발판 윗면 %.0f), 점프 신호 %s, 통과 신호 %s, 상태 %s" % [y0, " ".join(trace), top_y, got["jumped"], got["dropped"], _player.state_name()])
	_check(got["dropped"] and not got["jumped"], "one_way 발판에서 ↓+점프는 점프하지 않고 통과해 내려간다")
	_check(_player.global_position.y > top_y + 20.0, "발판 아래로 떨어졌다 (y=%.0f > %.0f)" % [_player.global_position.y, top_y])
	await _frames(40)
	_check(_player._drop_body == null, "0.25초 뒤 충돌 예외가 풀렸다")
	_check(_player.is_on_floor() and _player.global_position.y > top_y + 100.0, "아래 가지에 내려섰다 (y=%.0f)" % _player.global_position.y)
	# ↓ 없이 점프는 평소 점프
	got["jumped"] = false
	got["dropped"] = false
	_teleport(stand, 1)
	await _frames(6)
	y0 = _player.global_position.y
	var min_y := y0
	Input.action_press("jump")   # 한 프레임만 누르면 '짧은 점프'가 되므로 잠깐 누르고 있는다
	for i in 20:
		await get_tree().physics_frame
		min_y = minf(min_y, _player.global_position.y)
		if i == 12:
			Input.action_release("jump")
	print("[probe] 점프만: y %.0f → 최고 %.0f, 점프 신호 %s, 통과 신호 %s" % [y0, min_y, got["jumped"], got["dropped"]])
	_check(got["jumped"] and not got["dropped"] and min_y < y0 - 60.0, "↓ 없이 점프하면 평소처럼 뛴다")
	# 보통 바닥에서 ↓+점프는 평소 점프
	_teleport(Vector2(400, 2200 - 67 - 1), 1)
	await _frames(6)
	got["jumped"] = false
	got["dropped"] = false
	Input.action_press("move_down")
	await _tap("jump")
	await _frames(3)
	Input.action_release("move_down")
	print("[probe] 보통 바닥에서 ↓+점프: 점프 신호 %s, 통과 신호 %s" % [got["jumped"], got["dropped"]])
	_check(got["jumped"] and not got["dropped"], "one_way 가 아닌 바닥에서는 ↓+점프도 평소 점프")
	await _frames(50)


# ---------- 터치 스틱 세기 문턱: 살짝 내린 ↓ 는 낙하 공격·하단 점프가 아니다 ----------
func _test_touch_threshold() -> void:
	# 터치 스틱은 데드존 0.12 를 넘으면 Input.action_press("move_down", 세기) 를 부른다 (touch_controls.gd _set_axis)
	_teleport(Vector2(400, 1700), 1)
	await _frames(2)
	Input.action_press("move_down", 0.15)
	await get_tree().physics_frame
	var pressed := Input.is_action_pressed("move_down")
	var raw := Input.get_action_raw_strength("move_down")
	var held := _player._down_held()
	await _tap("attack_light")
	await get_tree().physics_frame
	var st := _player.state_name()
	Input.action_release("move_down")
	print("[probe] 터치 스틱 15%% 아래: is_action_pressed=%s, raw 세기 %.2f, _down_held=%s → 공중 약공격 결과 '%s'" % [pressed, raw, held, st])
	_check(pressed and not held and st == "약공격 1", "스틱을 15% 만 내린 채 공중 약공격은 낙하 공격이 아니라 보통 공중 약공격")
	await _frames(60)
	# 70% 내리면 낙하 공격
	_teleport(Vector2(400, 1700), 1)
	await _frames(2)
	Input.action_press("move_down", 0.7)
	await _tap("attack_light")
	await get_tree().physics_frame
	var st2 := _player.state_name()
	Input.action_release("move_down")
	_check(st2 == "낙하 공격", "스틱을 70%% 내린 채 공중 약공격은 낙하 공격 (%s)" % st2)
	await _frames(70)
	# one_way 발판 위에서 15% + 점프는 점프
	var secret: Platform = _room.get_node("Terrain/Secret")
	_teleport(Vector2(secret.global_position.x + 200, secret.global_position.y - 68), 1)
	await _frames(6)
	var got := {"jumped": false, "dropped": false}
	var c1 := func(_a): got["jumped"] = true
	var c2 := func(_p): got["dropped"] = true
	_player.jumped.connect(c1)
	_player.dropped_through.connect(c2)
	Input.action_press("move_down", 0.15)
	await _tap("jump")
	await _frames(3)
	Input.action_release("move_down")
	_player.jumped.disconnect(c1)
	_player.dropped_through.disconnect(c2)
	_check(got["jumped"] and not got["dropped"], "스틱을 15%% 만 내린 채 점프는 점프 (발판 아래로 안 빠짐: 점프 %s, 통과 %s)" % [got["jumped"], got["dropped"]])
	await _frames(40)
	# 컨트롤러 스틱 (이벤트 입력): 0.3 은 아니고 0.6 은 ↓
	var notes := []
	for v in [0.3, 0.6]:
		var ev := InputEventJoypadMotion.new()
		ev.axis = JOY_AXIS_LEFT_Y
		ev.axis_value = v
		Input.parse_input_event(ev)
		await get_tree().physics_frame
		await get_tree().physics_frame
		notes.append("%.1f → 눌림 %s, raw %.2f, _down_held %s" % [v, Input.is_action_pressed("move_down"), Input.get_action_raw_strength("move_down"), _player._down_held()])
		if v == 0.3:
			_check(not _player._down_held(), "컨트롤러 스틱 30% 는 ↓ 로 치지 않는다")
		else:
			_check(_player._down_held(), "컨트롤러 스틱 60% 는 ↓ 로 친다")
	var ev0 := InputEventJoypadMotion.new()
	ev0.axis = JOY_AXIS_LEFT_Y
	ev0.axis_value = 0.0
	Input.parse_input_event(ev0)
	await _frames(2)
	print("[probe] 컨트롤러 L스틱 y: %s" % " | ".join(notes))


# ---------- (e) 바람·빛 투사체 사거리 ----------
func _test_projectiles() -> void:
	Progress.gain_ability("wind")
	Progress.gain_ability("light")
	await get_tree().process_frame
	_check(_player.owned_souls() == ["seed", "wind", "light"], "능력을 얻으면 영혼 목록 %s" % [_player.owned_souls()])
	_check(_player.soul == "seed", "능력을 얻어도 고른 영혼은 그대로 seed (%s)" % _player.soul)
	for soul in ["wind", "light"]:
		_teleport(Vector2(150, 2200 - 67 - 1), 1)
		await _frames(4)
		_player.soul = soul
		_player._soul_cooldown = 0.0
		var before := get_tree().get_nodes_in_group("projectile").size()
		await _tap("soul_ability")
		await get_tree().physics_frame
		var p: Projectile = null
		for n in get_tree().get_nodes_in_group("projectile"):
			p = n
		_check(p != null and get_tree().get_nodes_in_group("projectile").size() == before + 1, "%s: 투사체가 하나 나간다" % soul)
		if p == null:
			continue
		var start := p.global_position
		var shape_desc := ""
		var rect_size := Vector2.ZERO
		for c in p.get_children():
			if c is CollisionShape2D:
				shape_desc = "%s %s" % [c.shape.get_class(), (c.shape as RectangleShape2D).size if c.shape is RectangleShape2D else (c.shape as CircleShape2D).radius]
				if c.shape is RectangleShape2D:
					rect_size = (c.shape as RectangleShape2D).size
		if soul == "wind":
			# 그림(초승달 호 3겹)의 범위가 판정 사각형 안에 드는지 (projectile.gd _draw 의 식과 같은 계산)
			var x_min := INF
			var x_max := -INF
			var y_max := 0.0
			for i in 3:
				var r: float = p.size.y * (0.26 + i * 0.11)
				var cx: float = p.size.x * (0.26 - i * 0.3)
				x_min = minf(x_min, cx + r * cos(1.15))
				x_max = maxf(x_max, cx + r)
				y_max = maxf(y_max, r * sin(1.15))
			print("[probe] 바람 그림 범위 x %.0f ~ %.0f, y ±%.0f / 판정 ±%.1f × ±%.1f" % [x_min, x_max, y_max, rect_size.x * 0.5, rect_size.y * 0.5])
			_check(x_max <= rect_size.x * 0.5 + 1.0 and y_max <= rect_size.y * 0.5 + 1.0 and x_min >= -rect_size.x * 0.5, "바람 그림이 판정 사각형 안에 든다")
		var far := 0.0
		var frames := 0
		while is_instance_valid(p) and not p._dead and frames < 400:
			await get_tree().physics_frame
			frames += 1
			if is_instance_valid(p):
				far = maxf(far, p.global_position.distance_to(start))
		var expect: float = (_player.gust_speed * _player.gust_range_time) if soul == "wind" else (_player.light_shot_speed * _player.light_shot_time)
		print("[probe] %s 투사체: 그림 크기 %s, 판정 %s, 피해 %.0f, 사거리 %.0f px (%.2f초, 기대 %.0f)" % [soul, p.size if is_instance_valid(p) else "-", shape_desc, p.damage if is_instance_valid(p) else -1.0, far, frames / 60.0, expect])
		_check(far > expect * 0.9 and far < expect * 1.1, "%s 사거리가 속도×수명(%.0f)에 맞는다" % [soul, expect])
		if soul == "wind":
			_check(is_instance_valid(p) and p.size == Vector2(110, 60) and absf(p.damage - 24.0 * _player.attack_multiplier) < 0.01, "바람: 크기 110×60, 피해 24")
		else:
			_check(is_instance_valid(p) and p.size == Vector2(120, 40) and absf(p.damage - 34.0 * _player.attack_multiplier) < 0.01, "빛: 크기 120×40, 피해 34")
		await _frames(10)
	_player.soul = "seed"
	Progress.soul = "seed"


# ---------- 고른 영혼이 방(새 소녀)·세이브를 건너 남는다 ----------
func _test_soul_persist() -> void:
	_teleport(Vector2(400, 2132), 1)
	await _frames(3)
	await _tap("soul_next")
	await get_tree().physics_frame
	_check(_player.soul == "wind" and Progress.soul == "wind", "전환 키로 고른 영혼이 Progress.soul 에 기록된다 (소녀 %s / Progress %s)" % [_player.soul, Progress.soul])
	# 다음 방에서 생기는 것과 같은 새 소녀
	var p2: Player = load("res://scenes/player/player.tscn").instantiate()
	p2.position = Vector2(100, 2132)
	_room.add_child(p2)
	await get_tree().process_frame
	_check(p2.soul == "wind", "새로 만든 소녀(다음 방)의 영혼도 wind (%s)" % p2.soul)
	p2.queue_free()
	await get_tree().process_frame
	# 세이브 왕복 (있던 저장 파일은 잠깐 치워 두었다 되돌린다)
	var path: String = SaveGame.PATH
	var had := FileAccess.file_exists(path)
	var backup := FileAccess.get_file_as_string(path) if had else ""
	SaveGame.save("", "res://scenes/rooms/canopy_01.tscn")
	Progress.soul = "seed"
	var scene := SaveGame.load_game()
	_check(scene != "" and Progress.soul == "wind", "세이브에 고른 영혼이 들어가고 불러오면 돌아온다 (%s)" % Progress.soul)
	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(path)
	# 되돌리기
	_player.soul = "seed"
	Progress.soul = "seed"
	Progress.next_spawn = ""
	await _frames(3)


# ---------- 옛 keymap.json(판 1): 지우지 않고 살려 읽는다 ----------
func _test_keymap_old_file() -> void:
	var path: String = Keymap.PATH
	var had := FileAccess.file_exists(path)
	var backup := FileAccess.get_file_as_string(path) if had else ""
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"jump": ["key:65"], "attack_heavy": ["key:75"], "soul_ability": ["key:73", "axis:4:+"]}))
	f.close()
	Keymap._load()
	var jump_keys := []
	for e in InputMap.action_get_events("jump"):
		if e is InputEventKey:
			jump_keys.append(e.physical_keycode)
	var soul_keys := []
	for e in InputMap.action_get_events("soul_ability"):
		if e is InputEventKey:
			soul_keys.append(e.physical_keycode)
	var exists := FileAccess.file_exists(path)
	var ver := -1
	if exists:
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(data) == TYPE_DICTIONARY:
			ver = int(data.get("_version", 1))
	print("[probe] 옛 keymap.json 읽기: 점프 키 %s, 영혼 기술 키 %s, 파일 남음 %s (판 %d)" % [jump_keys, soul_keys, exists, ver])
	_check(jump_keys == [KEY_A], "옛 파일의 다른 동작 배치(점프 A)는 살아남는다")
	_check(soul_keys.has(KEY_K) and soul_keys.has(KEY_I), "옛 강공격 배치(K)가 영혼 기술에 합쳐진다")
	_check(exists and ver == Keymap.VERSION, "새 판으로 다시 저장된다")
	Keymap.reset_defaults()
	if had:
		f = FileAccess.open(path, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
		Keymap._load()


# ---------- 가드 보호막·씨앗 베기 초승달이 몸·판정과 맞는가 ----------
func _part_bounds(visual: Node2D, names: Array) -> Rect2:
	var r := Rect2()
	var first := true
	for name in names:
		var spr: Sprite2D = visual._sprites[name]
		var rect := spr.get_rect()
		for c in [rect.position, rect.position + Vector2(rect.size.x, 0), rect.position + rect.size, rect.position + Vector2(0, rect.size.y)]:
			var p: Vector2 = visual.to_local(spr.to_global(c))
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r


func _test_shield_and_crescent_geometry() -> void:
	_teleport(Vector2(400, 2132), 1)
	_player.input_enabled = false
	await _frames(20)
	var visual: Node2D = _player.get_node("Visual")
	_player._set_state(Player.State.GUARD)
	await _frames(40)   # 보호막 알파와 자세가 자리 잡을 시간
	var body := _part_bounds(visual, ["torso", "head", "leg_back", "leg_front"])
	var top_y: float = visual.GUARD_CENTER.y + visual.GUARD_RY * sin(-visual.GUARD_SPAN)
	var bot_y: float = visual.GUARD_CENTER.y + visual.GUARD_RY * sin(visual.GUARD_SPAN)
	var above: float = body.position.y - top_y
	var below: float = float(visual.FOOT_Y) - bot_y
	print("[probe] 가드 자세 몸 y %.0f ~ %.0f (발바닥 %.0f) / 보호막 y %.0f ~ %.0f → 머리 위 여유 %.0f, 발 아래 여유 %.0f, 알파 %.2f" % [body.position.y, body.end.y, visual.FOOT_Y, top_y, bot_y, above, -below, visual._guard_a])
	_check(visual._guard_a > 0.9, "가드 중 보호막 알파가 올라온다")
	_check(above >= 0.0 and above < 40.0 and below <= 0.0 and below > -40.0, "보호막이 머리 꼭대기부터 발바닥까지 '키만 하게' 덮는다")
	_player._set_state(Player.State.IDLE)
	_player.input_enabled = true
	# 초승달 범위 vs 판정 상자 (어깨 기준 타원)
	var o: Vector2 = visual._sword_origin()
	var top: float = o.y - visual.SLASH_RY_UP
	var bottom: float = o.y + visual.SLASH_RY_DOWN
	var front: float = o.x + visual.SLASH_RX
	var box: Rect2 = _player.slash_box
	print("[probe] 씨앗 베기 초승달: 위 %.0f, 아래 %.0f, 앞 %.0f / 판정 위 %.0f, 아래 %.0f, 앞 %.0f" % [top, bottom, front, box.position.y, box.end.y, box.end.x])
	_check(top >= box.position.y and bottom <= box.end.y and front <= box.end.x, "초승달이 판정 상자 밖으로 나가지 않는다")
	_check(front > box.end.x - 60.0 and bottom > box.end.y - 30.0, "초승달이 판정 상자에 거의 꽉 찬다")
	await _frames(10)


# ---------- (d) 가드: 일반 막기 신호 ----------
func _test_guard() -> void:
	var wc := _enemy("Woodcutter2")
	if wc == null:
		wc = _enemy("Woodcutter1")
	_check(wc != null, "가드 시험용 나무꾼이 있다")
	if wc == null:
		return
	wc.hp = wc.max_hp
	wc.poise = 0.0
	if wc.state == EnemyBase.State.BROKEN or wc.state == EnemyBase.State.HIT:
		wc._set_state(EnemyBase.State.IDLE)
	_teleport(wc.global_position + Vector2(-130, -10), 1)
	_player._invuln_timer = 0.0
	_player.hp = _player.max_hp
	_player.guard = _player.max_guard
	await _frames(6)
	var results := []
	wc.hitbox.landed.connect(func(res, _t): results.append(res))
	var guard_hits := []
	_player.guard_hit.connect(func(d): guard_hits.append(d))
	var hp0 := _player.hp
	Input.action_press("guard")
	var frames := 0
	while guard_hits.is_empty() and frames < 600:
		await get_tree().physics_frame
		frames += 1
		if _player.state != Player.State.GUARD and _player.state != Player.State.HIT:
			Input.action_press("guard")
	Input.action_release("guard")
	print("[probe] 가드: %.2f초 뒤 guard_hit %s (막은 피해), 적 히트박스 결과 %s, 소녀 체력 %.0f → %.0f, 가드 게이지 %.0f, 상태 %s" % [frames / 60.0, guard_hits, results, hp0, _player.hp, _player.guard, _player.state_name()])
	_check(not guard_hits.is_empty(), "가드 중 나무꾼의 공격을 받으면 guard_hit 신호가 온다")
	_check(results.has("guard"), "적 쪽 결과가 'guard'")
	_check(_player.hp > hp0 - 10.0 and _player.hp < hp0, "가드로 피해가 85%% 줄었다 (%.1f)" % (hp0 - _player.hp))
	await _frames(10)

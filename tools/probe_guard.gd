extends Node
## Claude Code용 경비병(방패 돌진 적) 시험 (화면 없이 돈다).
## 실행: godot --headless --path . res://tools/probe_guard.tscn
## 진짜 물리 틱(60Hz)으로 돌린다: 바닥(StaticBody2D)을 깔고 소녀(player.tscn, 물리 끔)를 세워 두고 경비병을 추격시킨다.
##  (a) 소녀가 등 뒤로 가면 facing 이 turn_delay(0.5초, v1.1.0 모든 몹 공통) 뒤에 바뀌는지, 바뀐 직후 그림이 아직 돌아서는 중일 때는 막지(blocked) 않는지
##  (b) 정면에서 연속 block_limit(3)번 막은 뒤 네 번째는 방패가 들려 맞고 흐트러짐 +block_break_poise 인지, 잠깐 열렸다가 다시 막는지
##  (c) 돌진 속도·피해·길이, 박힘 길이, 박힘 뒤 쉬는 시간, 박힘 중 흐트러짐 2배
##  (d) 두 씬의 그림 방향 플래그와 능력치가 그림 판단·너프 값과 같은지
##  (e) 부위 뼈대 그림(GuardRigVisual)이면: 방패(weapon 뼈)가 그림이 보는 쪽(visible_facing)에 그려지는지 — 좌우 모두, 세 씬 모두

const EXPECT_GUARD := {"max_hp": 100.0, "max_poise": 100.0, "damage": 12.0, "turn_delay": 0.5, "art_faces_right": true}
const EXPECT_SAVABLE := {"max_hp": 110.0, "max_poise": 100.0, "damage": 12.0, "turn_delay": 0.5, "art_faces_right": false}
const EXPECT_SCRIPT := {"charge_speed": 700.0, "charge_time": 0.55, "charge_damage": 14.0, "stuck_time": 2.4, "charge_chance": 0.35, "charge_cooldown": 1.2, "block_limit": 3, "block_reset_time": 1.5, "block_break_poise": 40.0}

var _fail := 0
var _player: Player
var _dt := 1.0 / 60.0


func _ready() -> void:
	await _run()


func _run() -> void:
	print("[probe] 경비병 시험 시작")
	_dt = 1.0 / float(Engine.physics_ticks_per_second)
	_make_floor()
	_make_player()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_probe_scene_values()
	await _probe_turn_delay()
	await _probe_block_limit()
	await _probe_charge()
	_probe_stuck_poise()
	await _probe_shield_side()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


## 바닥: 지형 레이어(1)의 긴 판. 경비병(발 y = +65)이 y=0 에 서도록 윗면을 65 에 둔다.
func _make_floor() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8000, 200)
	shape.shape = rect
	shape.position = Vector2(0, 65 + 100)
	body.add_child(shape)
	add_child(body)


## 소녀: 진짜 씬을 세우되 물리·입력은 끈다 (자리만 옮겨 가며 쓴다). 맞아도 죽지 않게 무적.
func _make_player() -> void:
	var scene: PackedScene = load("res://scenes/player/player.tscn")
	_player = scene.instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	_player._invuln_timer = 9999.0
	_player.global_position = Vector2(450, 0)


func _spawn_guard(path := "res://scenes/enemies/guard.tscn", at := Vector2.ZERO) -> Guard:
	var scene: PackedScene = load(path)
	var g: Guard = scene.instantiate()
	g.global_position = at
	add_child(g)
	return g


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		t += _dt


## 조건이 참이 될 때까지 기다린다 (최대 limit 초). 걸린 시간을 돌려준다 (시간 초과면 -1).
func _wait_until(cond: Callable, limit: float) -> float:
	var t := 0.0
	while t < limit:
		if cond.call():
			return t
		await get_tree().physics_frame
		t += _dt
	return -1.0


func _hit_from_player(poise := 10.0) -> HitData:
	var h := HitData.make(5.0, poise, _player, Vector2(300, -120))
	h.from_player = true
	return h


## (d) 씬 값: 그림 방향 플래그(그림을 직접 보고 정한 값)와 너프된 능력치
func _probe_scene_values() -> void:
	for pair in [["res://scenes/enemies/guard.tscn", EXPECT_GUARD], ["res://scenes/enemies/guard_savable.tscn", EXPECT_SAVABLE]]:
		var g := _spawn_guard(pair[0], Vector2(-3000, 0))
		var vis: Node2D = g.get_node("Visual")
		var exp: Dictionary = pair[1]
		var got := {"max_hp": g.max_hp, "max_poise": g.max_poise, "damage": g.damage, "turn_delay": g.turn_delay, "art_faces_right": vis.art_faces_right}
		print("[probe] %s: %s" % [pair[0].get_file(), got])
		if vis is EnemyRigVisual:
			# 부위 뼈대는 늘 오른쪽을 보는 그림으로 잘린다 (예전 한 장 그림의 방향 플래그는 뜻이 없다) — 방패 쪽은 (e) 가 직접 본다
			exp = exp.duplicate()
			exp["art_faces_right"] = true
		for k in exp.keys():
			_check(is_equal_approx(float(got[k]), float(exp[k])) if typeof(exp[k]) != TYPE_BOOL else got[k] == exp[k], "%s %s = %s (기대 %s)" % [pair[0].get_file(), k, got[k], exp[k]])
		for k in EXPECT_SCRIPT.keys():
			var v = g.get(k)
			_check(is_equal_approx(float(v), float(EXPECT_SCRIPT[k])), "%s %s = %s (기대 %s)" % [pair[0].get_file(), k, v, EXPECT_SCRIPT[k]])
		g.free()


## 추격 상태로 자리 잡을 때까지 (발견 펄쩍 → 착지 → 추격). walk_speed 0 이면 제자리에 선다.
func _settle_chase(g: Guard) -> bool:
	var t := await _wait_until(func(): return g.state == EnemyBase.State.CHASE and g.is_on_floor(), 4.0)
	return t >= 0.0


## (a) 돌아서기 지연과 '그림이 돌아서는 중엔 막지 않음'
func _probe_turn_delay() -> void:
	_player.global_position = Vector2(450, 0)
	var g := _spawn_guard()
	g.walk_speed = 0.0        # 제자리에서 바라보기만 (lunge 도 거리 밖: 450 > attack_range+lunge_extra 410)
	var vis: Node2D = g.get_node("Visual")
	var ok := await _settle_chase(g)
	_check(ok, "경비병이 소녀를 발견하고 추격 상태에 들어선다 (상태 %s)" % g.state_name())
	await _wait(0.5)
	_check(g.facing == 1 and vis.is_facing_settled() and vis.visible_facing() == 1, "오른쪽 소녀를 본다: facing %d, 그림 방향 %d, 자리 잡음 %s" % [g.facing, vis.visible_facing(), vis.is_facing_settled()])
	# 1) 시간 재기: 소녀가 등 뒤(왼쪽)로 → facing 이 바뀌기까지
	_player.global_position = Vector2(-450, 0)
	var mid_state := ""
	var mid_facing := 0
	var mid_speed := 0.0
	var t_turn := 0.0
	while t_turn < 1.5 and g.facing != -1:
		await get_tree().physics_frame
		t_turn += _dt
		if t_turn > 0.19 and t_turn < 0.21:
			mid_state = g.state_name()
			mid_facing = g.facing
			mid_speed = absf(g.velocity.x)
	print("[probe] 돌아서기: %.3f초 (기대 %.2f) — 0.2초 때 상태 %s, facing %d, 속도 %.0f" % [t_turn, g.turn_delay, mid_state, mid_facing, mid_speed])
	_check(t_turn >= g.turn_delay - 0.02 and t_turn <= g.turn_delay + 0.07, "소녀가 등 뒤로 가도 %.2f초 뒤에야 돌아선다 (%.3f초)" % [g.turn_delay, t_turn])
	_check(mid_facing == 1 and mid_state == "추격", "기다리는 동안엔 아직 저쪽(오른쪽)을 보고 추격 상태 그대로다")
	# 2) 막기: 논리 방향이 바뀐 바로 그 프레임엔 그림이 아직 안 돌아서 있어 막지 못한다
	var settled0: bool = vis.is_facing_settled()
	var look0: int = vis.visible_facing()
	var r0: String = g.receive_hit(_hit_from_player(), null)
	print("[probe] 돌아선 직후: 그림 자리 잡음 %s, 그림 방향 %d, 정면 공격 결과 '%s'" % [settled0, look0, r0])
	_check(not settled0 and r0 != "blocked", "돌아서는 중(그림은 아직 오른쪽)엔 앞(왼쪽)에서 온 공격도 튕기지 않는다")
	# 3) 그림이 다 돌아선 뒤엔 막는다
	var t_settle := await _wait_until(func(): return vis.is_facing_settled() and g.state == EnemyBase.State.CHASE, 1.5)
	await _wait(0.05)
	var r1: String = g.receive_hit(_hit_from_player(), null)
	print("[probe] 그림이 자리 잡기까지 %.3f초 → 정면 공격 결과 '%s' (그림 방향 %d)" % [t_settle, r1, vis.visible_facing()])
	_check(t_settle >= 0.0 and t_settle < 0.6 and r1 == "blocked", "그림이 왼쪽으로 다 돌아선 뒤엔 정면 공격을 막는다")
	# 4) 등 뒤(오른쪽)에서 온 공격은 그대로 맞는다
	_player.global_position = Vector2(450, 0)
	var hp0 := g.hp
	var r2: String = g.receive_hit(_hit_from_player(), null)
	_check(r2 == "hit" and g.hp < hp0, "등 뒤에서 온 공격은 맞는다 ('%s', 체력 %.0f → %.0f)" % [r2, hp0, g.hp])
	g.free()
	await get_tree().physics_frame


## (b) 정면 막기 한계
func _probe_block_limit() -> void:
	_player.global_position = Vector2(450, 0)
	var g := _spawn_guard()
	g.walk_speed = 0.0
	var vis: Node2D = g.get_node("Visual")
	var ok := await _settle_chase(g)
	await _wait(0.5)
	_check(ok and vis.is_facing_settled() and g.facing == 1, "정면 막기 시험 준비: 추격·오른쪽 보기 (%s, facing %d)" % [g.state_name(), g.facing])
	var results := []
	var poise_trail := []
	for i in g.block_limit + 1:
		results.append(g.receive_hit(_hit_from_player(10.0), null))
		poise_trail.append("%.0f" % g.poise)
		await _wait(0.1)
	print("[probe] 정면 연속 공격 결과: %s, 흐트러짐 %s" % [str(results), str(poise_trail)])
	var first_ok := true
	for i in g.block_limit:
		if results[i] != "blocked":
			first_ok = false
	_check(first_ok, "처음 %d번은 막는다" % g.block_limit)
	_check(results[g.block_limit] == "hit", "%d번째는 방패가 들려 맞는다" % (g.block_limit + 1))
	_check(is_equal_approx(g.poise, 10.0 + g.block_break_poise), "방패가 들린 한 대는 흐트러짐 +%.0f (지금 %.0f)" % [g.block_break_poise, g.poise])
	# 방패가 들린 직후(block_open_time 안)엔 한 대 더 들어간다 (피격 경직이 끝난 뒤)
	await _wait(0.25)
	var r_open: String = g.receive_hit(_hit_from_player(10.0), null)
	_check(r_open == "hit", "방패가 들린 %.1f초 안에는 더 맞는다 ('%s', 상태 %s)" % [g.block_open_time, r_open, g.state_name()])
	# 쉬고 나면 다시 막는다
	var t_back := await _wait_until(func(): return g.state == EnemyBase.State.CHASE and g._block_open <= 0.0, 2.0)
	await _wait(0.05)
	var r_again: String = g.receive_hit(_hit_from_player(10.0), null)
	_check(t_back >= 0.0 and r_again == "blocked", "방패가 다시 올라오면(%.2f초 뒤) 다시 막는다 ('%s')" % [t_back, r_again])
	g.free()
	await get_tree().physics_frame


## (c) 돌진: 속도·피해·길이 → 박힘 길이 → 쉬는 시간
func _probe_charge() -> void:
	_player.global_position = Vector2(450, 0)
	var g := _spawn_guard()
	g.charge_chance = 1.0
	var t0 := await _wait_until(func(): return g.state == EnemyBase.State.WINDUP and g._mode == "charge", 6.0)
	_check(t0 >= 0.0 and g.anim_hint == "red", "다가가서 돌진 예고(붉은 예고)에 들어간다 (%.2f초, 힌트 '%s')" % [t0, g.anim_hint])
	var t1 := await _wait_until(func(): return g.state == EnemyBase.State.STRIKE, 2.0)
	_check(t1 >= 0.0, "예고 뒤 돌진이 시작된다")
	var speeds := []
	var dmg := -1.0
	var guardable := true
	var charge_len := 0.0
	var x0 := g.global_position.x
	while g.state == EnemyBase.State.STRIKE and charge_len < 2.0:
		await get_tree().physics_frame
		if g.state == EnemyBase.State.STRIKE:
			charge_len += _dt
			speeds.append(absf(g.velocity.x))
			if g.hitbox.hit:
				dmg = g.hitbox.hit.damage
				guardable = g.hitbox.hit.guardable
	var vmax := 0.0
	for s in speeds:
		vmax = maxf(vmax, s)
	print("[probe] 돌진: 최고 속도 %.0f (기대 %.0f), 길이 %.3f초 (기대 %.2f), 거리 %.0f px, 피해 %.0f, 가드 가능 %s" % [vmax, g.charge_speed, charge_len, g.charge_time, g.global_position.x - x0, dmg, guardable])
	_check(absf(vmax - g.charge_speed) < 1.0, "돌진 속도가 charge_speed 와 같다")
	_check(absf(charge_len - g.charge_time) < 0.06, "돌진 길이가 charge_time 과 같다")
	_check(is_equal_approx(dmg, g.charge_damage) and not guardable, "돌진 피해 %.0f, 가드 불가" % g.charge_damage)
	_check(g.state == EnemyBase.State.RECOVER and g._mode == "stuck" and g.anim_hint == "stuck", "돌진이 끝나면 박힌다 (상태 %s, 힌트 '%s')" % [g.state_name(), g.anim_hint])
	var stuck_len := 0.0
	while g._mode == "stuck" and stuck_len < 4.0:
		await get_tree().physics_frame
		if g._mode == "stuck":
			stuck_len += _dt
	var timer_after: float = g._timer
	print("[probe] 박힘 %.3f초 (기대 %.2f) → 상태 %s, 남은 쉬는 시간 %.3f (기대 %.2f)" % [stuck_len, g.stuck_time, g.state_name(), timer_after, g.charge_cooldown])
	_check(absf(stuck_len - g.stuck_time) < 0.06, "박힘 길이가 stuck_time 과 같다")
	_check(g.state == EnemyBase.State.CHASE and timer_after > g.charge_cooldown - 0.05, "박힘에서 풀리면 charge_cooldown 동안 쉰다")
	g.free()
	await get_tree().physics_frame


## 박힘 중 흐트러짐 2배 (물리 없이 상태만 꾸며서 확인)
func _probe_stuck_poise() -> void:
	_player.global_position = Vector2(450, 0)
	var g := _spawn_guard("res://scenes/enemies/guard.tscn", Vector2(-3000, 0))
	g.player = _player
	g.facing = 1
	g._mode = "stuck"
	g._set_state(EnemyBase.State.RECOVER)
	g._timer = 2.0
	var r: String = g.receive_hit(_hit_from_player(10.0), null)
	_check(r == "hit" and is_equal_approx(g.poise, 20.0), "박힌 동안엔 정면이라도 맞고 흐트러짐 2배 ('%s', %.0f)" % [r, g.poise])
	g.free()


## (e) 방패가 그림이 보는 쪽에 그려지는가 (부위 뼈대 그림만). 소녀를 오른쪽·왼쪽에 두고 그림이 자리 잡은 뒤
## 방패 뼈(weapon)의 가운데가 몸 가운데보다 보는 쪽에 있어야 한다 — 방패 판정(그림이 보는 방향 기준)과 그림이 맞는지.
func _probe_shield_side() -> void:
	for path in ["res://scenes/enemies/guard.tscn", "res://scenes/enemies/guard_savable.tscn", "res://scenes/enemies/elite_guard.tscn"]:
		for side in [1, -1]:
			_player.global_position = Vector2(450.0 * side, 0)
			var g = load(path).instantiate()
			g.global_position = Vector2.ZERO
			add_child(g)
			var vis: Node2D = g.get_node("Visual")
			if not (vis is EnemyRigVisual):
				g.free()
				return
			g.walk_speed = 0.0
			g.attack_range = 0.0      # 제자리에서 바라보기만 (공격하러 오지 않게)
			g.lunge_extra = 0.0
			await _wait_until(func(): return g.facing == side and vis.is_facing_settled(), 3.0)
			await _wait(0.3)
			var rig: PartRig = vis.rig
			var shield_x: float = rig.to_global(rig.bone_point("weapon", Vector2(0, rig.bone_len[rig.bone_index("weapon")] * 0.5))).x - g.global_position.x
			_check(vis.visible_facing() == side and shield_x * side > 10.0,
				"%s 소녀가 %s: 그림 방향 %d, 방패 가운데가 몸 앞 %.0f px (보는 쪽에 그려짐)" % [path.get_file(), "오른쪽" if side > 0 else "왼쪽", vis.visible_facing(), shield_x * side])
			g.free()
			await get_tree().physics_frame

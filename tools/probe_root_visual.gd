extends Node
## 뿌리지기 새 패턴의 눈 확인용 스크린샷 (화면 있는 실행). 정원의 끝(abyss_boss)을 띄워 싸움을 걸고,
## 패턴을 하나씩 강제로 걸어 예고(붉은 전조)와 실행(효과) 순간을 screenshots/root_<패턴>_telegraph/active.png 로 남긴다.
## 실행: Godot --path <프로젝트> res://tools/probe_root_visual.tscn        (창이 잠깐 뜬다; --headless 면 스크린샷 없이 흐름만 찍는다)
## 마지막에 "[probe] 끝: 실패 N" 을 찍고 그 수로 종료한다.

var _fail := 0
var _room: Node
var _player: Player
var _boss: Node


func _ready() -> void:
	print("[probe] 뿌리지기 눈 확인 시작")
	Settings.set_value("screen_shake", false)
	_room = load("res://scenes/rooms/abyss_boss.tscn").instantiate()
	add_child(_room)
	for i in 5:
		await get_tree().physics_frame
	_player = get_tree().get_first_node_in_group("player") as Player
	_boss = _room.get_node("Boss")
	_player._invuln_timer = 9999.0
	_player.global_position = Vector2(1500, 1432)
	await get_tree().create_timer(0.5).timeout
	var started: bool = _room.fight_started
	print("[probe] 싸움 시작 %s" % started)
	if not started:
		_fail += 1
	# INTRO 가 끝나길 기다린다
	await _until(func() -> bool: return _boss.state_name() == "STANCE", 5.0)
	_boss._timer = 99.0
	var cases := [
		# [패턴, 페이즈, 소녀 x(보스 기준 거리), 예고 스샷 시각, 실행 스샷 시각]
		["SPIKES", 1, -500.0, 0.6, 1.08],
		["SWEEP", 1, -260.0, 0.35, 0.58],
		["ORBS", 1, -600.0, 0.6, 1.3],
		["HAND", 1, -450.0, 0.55, 1.15],
		["SEEDS", 1, -500.0, 0.5, 1.5],
		["RING", 1, -400.0, 0.5, 1.6],
		["WALL", 2, -900.0, 0.8, 1.35],
		["STOMP", 2, -450.0, 0.7, 1.12],
		["SWEEP2", 2, -260.0, 0.2, 0.45],
	]
	for c in cases:
		await _shoot(c[0], c[1], c[2], c[3], c[4])
	# 2026-10-20 부위 뼈대: 공격이 아닌 상태들도 실제 방에서 찍는다 (서 있기·걷기·무너짐·다시 일어섬·쓰러져 엎드림·정화)
	await _states()
	print("[probe] 끝: 실패 %d" % _fail)
	await get_tree().create_timer(0.3).timeout
	get_tree().quit(1 if _fail > 0 else 0)


func _shoot(pattern: String, phase: int, dx: float, t_tele: float, t_act: float) -> void:
	# 자세로 되돌리고 떠 있는 효과를 치운다
	for n in get_tree().get_nodes_in_group("root_effect"):
		n.queue_free()
	_boss.phase = phase
	_boss._chain = -1
	_boss._events.clear()
	_boss._set_state(_boss.State.STANCE)
	_boss._timer = 99.0
	_boss.velocity = Vector2.ZERO
	_boss.global_position = Vector2(2300, _boss.ground_y)
	_boss.facing = -1
	_player.global_position = Vector2(2300 + dx, 1432)
	_player.velocity = Vector2.ZERO
	_player.facing = 1
	await get_tree().create_timer(0.6).timeout
	_boss.force_pattern(pattern)
	var t0 := Time.get_ticks_msec()
	await get_tree().create_timer(t_tele).timeout
	var tele_phase: String = _boss.attack_phase
	_save("root_%s_telegraph.png" % pattern.to_lower())
	await get_tree().create_timer(maxf(t_act - t_tele, 0.05)).timeout
	var act_phase: String = _boss.attack_phase
	var fx := get_tree().get_nodes_in_group("root_effect").size()
	_save("root_%s_active.png" % pattern.to_lower())
	print("[probe] %s (%d페이즈): %.2f초 %s → %.2f초 %s, 효과 노드 %d, 예고 글자 '%s'" % [pattern, phase, t_tele, tele_phase, t_act, act_phase, fx, _boss.telegraph_label(pattern.to_lower())])
	var ok: bool = tele_phase == "startup" and act_phase in ["active", "recovery"]
	if pattern in ["SPIKES", "ORBS", "HAND", "SEEDS", "RING", "STOMP"] and fx == 0:
		ok = false
	if not ok:
		_fail += 1
	await _until(func() -> bool: return _boss.state_name() == "STANCE" and _boss.attack_phase == "", 6.0)
	_boss._timer = 99.0


## 상태 사진: screenshots/root_state_<이름>.png. 쓰러짐·정화는 싸움이 끝나는 것이라 맨 마지막에.
func _states() -> void:
	for n in get_tree().get_nodes_in_group("root_effect"):
		n.queue_free()
	_boss.phase = 1
	_boss.hp = _boss.max_hp
	_boss._chain = -1
	_boss._events.clear()
	_boss._set_state(_boss.State.STANCE)
	_boss.velocity = Vector2.ZERO
	_boss.global_position = Vector2(2300, _boss.ground_y)
	_boss.facing = -1
	_player.global_position = Vector2(2300 - 480, 1432)
	_player.velocity = Vector2.ZERO
	_player.facing = 1
	_boss._timer = 99.0
	await get_tree().create_timer(1.2).timeout
	_save("root_state_idle.png")
	# 걷기: 소녀가 멀어지면 다가온다 (보스 스스로)
	_player.global_position = Vector2(2300 - 1100, 1432)
	await get_tree().create_timer(0.9).timeout
	_boss._timer = 99.0
	_save("root_state_walk.png")
	_player.global_position = Vector2(_boss.global_position.x - 480, 1432)
	await get_tree().create_timer(0.6).timeout
	_boss._timer = 99.0
	# 무너짐
	_boss.poise = _boss.max_poise - 1.0
	_boss.receive_hit(HitData.make(1.0, 50.0, _player), null)
	await get_tree().create_timer(0.9).timeout
	_save("root_state_broken.png")
	await _until(func() -> bool: return _boss.state_name() == "STANCE", 5.0)
	_boss._timer = 99.0
	# 2페이즈: 무너졌다 다시 일어섬 (앞부분 무너짐 / 엎드려 숨 고름 / 일어서는 중)
	_boss.hp = _boss.max_hp * 0.51
	_boss._poise_immune = 0.0
	_boss.receive_hit(HitData.make(30.0, 0.0, _player), null)
	await get_tree().create_timer(0.85).timeout
	_save("root_state_rise_a.png")
	await get_tree().create_timer(0.9).timeout
	_save("root_state_rise_b.png")
	await get_tree().create_timer(0.8).timeout
	_save("root_state_rise_c.png")
	await _until(func() -> bool: return _boss.state_name() == "STANCE", 5.0)
	_boss._timer = 99.0
	await get_tree().create_timer(0.8).timeout
	_boss._timer = 99.0
	_save("root_state_idle_p2.png")
	# 쓰러짐 → 정화 기다림 → 정화
	_boss.hp = 1.0
	_boss.receive_hit(HitData.make(5.0, 0.0, _player), null)
	await get_tree().create_timer(0.5).timeout
	_save("root_state_fallen_a.png")
	await get_tree().create_timer(1.6).timeout
	_save("root_state_fallen_b.png")
	print("[probe] 상태 사진: 쓰러진 뒤 %s" % _boss.state_name())
	if _boss.state_name() != "FALLEN":
		_fail += 1
	_boss.purified_by(_player)
	await get_tree().create_timer(1.0).timeout
	_save("root_state_purified.png")


func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if cond.call():
			return true
	return false


func _save(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(ProjectSettings.globalize_path("res://screenshots/" + file_name))

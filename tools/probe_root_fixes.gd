extends Node
## 뿌리지기 검토 지적 수정 확인 (실제 방 abyss_boss, 엔진 물리로 판정).
## 실행: godot --headless --path <프로젝트> res://tools/probe_root_fixes.tscn
## 확인하는 것:
##  1) 휘두르기·되돌려 베기: 맞는 자리(가까이 선 소녀 포함)는 모두 붉은 부채꼴 안 / 판정 사각형이 부채꼴에 다 들어감
##  2) 되돌려 베기 예비 ≥ 0.45초(2페이즈 0.7배), 타격 중 지팡이 머리가 내내 보스 앞
##  3) 무너진 채 2페이즈로 넘어가면 흐트러짐 0
##  4) 무너지면 예약된 씨앗·둘째 충격파가 더 나오지 않음
##  5) 씨앗 주황 점 반폭 ≥ 터짐 판정, 점 밖이면 안 맞음
##  6) 늦게 솟는 가시·뿌리 손은 기다리는 동안 스스로 예고를 그림
##  7) 구슬은 예고 고리(지팡이 머리) 자리에서 생김
##  8) 연계 공격 직전 소녀 쪽으로 돈다
##  9) 뿌리 손: 묶인 동안 피격 상태 유지, 놓으면 실제로 던져짐
## 10) 가시 판정은 그려진 높이를 따라 자람
## 11) 예고 층은 소녀·보스보다 먼저(아래) 그려짐, 가드 불가 깜빡임 3Hz 이하
## 마지막에 "[probe] 끝: 실패 N" 을 찍고 그 수로 종료한다.

var _room: Node
var _player: Player
var _boss: RootKeeper
var _vis: Sprite2D
var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("[probe] 뿌리지기 수정 확인 시작")
	Settings.set_value("screen_shake", false)
	_room = load("res://scenes/rooms/abyss_boss.tscn").instantiate()
	add_child(_room)
	await _frames(10)
	_player = get_tree().get_first_node_in_group("player") as Player
	_boss = _room.get_node("Boss") as RootKeeper
	_vis = _boss.get_node("Sprite") as Sprite2D
	Progress.gain_ability("double_jump")
	_player._apply_abilities()
	_player.global_position = Vector2(1500, _boss.ground_y - 70)
	await _frames(10)
	await _until(func() -> bool: return _boss.state == RootKeeper.State.STANCE, 6.0)
	_check(_boss.state == RootKeeper.State.STANCE, "싸움 시작 → 보스 자세(STANCE)")
	_draw_order()
	_blink()
	_fan_geometry()
	await _fan_vs_hit("SWEEP", 1)
	await _fan_vs_hit("SWEEP2", 1)
	await _fan_vs_hit("SWEEP2", 2)
	await _sweep2_timing_and_side()
	await _phase2_poise()
	await _broken_events("STOMP", "RootShockwave", 0.8)
	await _broken_events("SEEDS", "RootSeed", 1.3)
	await _seed_mark()
	await _delayed_telegraphs()
	await _orb_origin()
	await _chain_turn()
	await _hand_throw()
	await _spike_shape()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(_fail)


# ---------- 도우미 ----------

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		_hold_boss()


func _until(cond: Callable, max_t: float) -> float:
	var t := 0.0
	while t < max_t and not cond.call():
		await get_tree().physics_frame
		t += 1.0 / 60.0
		_hold_boss()
	return t


## 보스가 스스로 다음 패턴을 고르지 않게 (자세 상태에서 타이머를 붙잡는다)
func _hold_boss() -> void:
	if _boss and _boss.state == RootKeeper.State.STANCE:
		_boss._timer = 99.0
		_boss.velocity.x = 0.0


func _check(ok: bool, msg: String) -> void:
	print("[probe] %s %s" % ["OK  " if ok else "실패", msg])
	if not ok:
		_fail += 1


func _clear_fx() -> void:
	for n in get_tree().get_nodes_in_group("root_effect"):
		n.queue_free()


func _prep_boss(bx: float, ph := 1) -> void:
	_clear_fx()
	_boss.phase = ph
	_boss._events.clear()
	_boss._chain = -1
	_boss._last_attack = -1
	_boss.poise = 0.0
	_boss._poise_immune = 0.0   # 앞 시험의 무너짐 뒤 흐트러짐 면역(2.5초)이 남지 않게
	_boss.hitbox.deactivate()
	_boss._set_state(RootKeeper.State.STANCE)
	_boss._timer = 99.0
	_boss.velocity = Vector2.ZERO
	_boss.facing = -1
	_boss.global_position = Vector2(bx, _boss.ground_y)


func _reset_player(x: float) -> void:
	for a in ["guard", "dodge", "jump", "move_left", "move_right", "attack_light"]:
		Input.action_release(a)
	_player.hp = _player.max_hp
	_player.guard = _player.max_guard
	_player._invuln_timer = 0.0
	_player.velocity = Vector2.ZERO
	_player.global_position = Vector2(x, _boss.ground_y - 67.0)
	if _player.state != Player.State.IDLE:
		_player._set_state(Player.State.IDLE)


func _count(cls: String) -> int:
	var n := 0
	for c in get_tree().get_nodes_in_group("root_effect"):
		if c.get_script() and c.get_script().get_global_name() == cls and not c.is_queued_for_deletion():
			n += 1
	return n


## 소녀 맞는 영역(캡슐)을 사각형 점들로 근사
func _body_points(p: Vector2) -> Array:
	var pts := []
	for yy in range(-66, 67, 11):
		for xx in [-25.0, 0.0, 25.0]:
			pts.append(p + Vector2(xx, yy))
	return pts


# ---------- 1) 부채꼴 ----------

func _draw_order() -> void:
	var marks: Node2D = _boss.get_node_or_null("Marks")
	var ok := marks != null and not marks.top_level and marks.get_index() < _vis.get_index() and _boss.get_index() < _player.get_index()
	_check(ok, "예고 층(Marks)이 top_level 아님, 보스 그림보다 먼저, 보스가 소녀보다 먼저 → 예고는 보스·소녀 아래에 그려짐")


func _blink() -> void:
	_check(RootKeeper.TELEGRAPH_BLINK_HZ <= 3.0, "가드 불가 깜빡임 %.1fHz (3 이하)" % RootKeeper.TELEGRAPH_BLINK_HZ)


func _fan_geometry() -> void:
	for st in [RootKeeper.State.SWEEP, RootKeeper.State.SWEEP2]:
		for f in [-1, 1]:
			_boss.facing = f
			var fan: PackedVector2Array = _vis.sweep_fan(st)
			var reach: Rect2 = _boss.sweep_reach(st)
			var bx := _boss.global_position.x
			var g := _boss.ground_y
			var outside := 0
			for xx in range(int(reach.position.x), int(reach.end.x) + 1, 10):
				for yy in range(int(reach.position.y), int(reach.end.y) + 1, 10):
					if not Geometry2D.is_point_in_polygon(Vector2(bx + f * xx, g + yy), fan):
						outside += 1
			_check(outside == 0, "%s(facing %d): 판정 사각형 %s 의 점이 부채꼴 밖 %d개 (0)" % [RootKeeper.State.keys()[st], f, reach, outside])
	_boss.facing = -1


func _fan_vs_hit(pattern: String, ph: int) -> void:
	var bad := []
	var hit_d := []
	for d in [40.0, 80.0, 120.0, 160.0, 200.0, 240.0, 280.0, 320.0, 360.0, 400.0]:
		_prep_boss(2500, ph)
		_reset_player(2500 - d)
		await _frames(12)
		_reset_player(2500 - d)
		_boss.velocity = Vector2.ZERO
		var hp0 := _player.hp
		_boss.force_pattern(pattern)
		_boss._chain = -1
		var fan: PackedVector2Array = _vis.sweep_fan(_boss.state)
		var shown := false
		for q in _body_points(_player.global_position):
			if Geometry2D.is_point_in_polygon(q, fan):
				shown = true
				break
		await _until(func() -> bool: return _boss.attack_phase == "recovery", 3.0)
		var hurt := hp0 - _player.hp > 0.5
		if hurt:
			hit_d.append(int(d))
			if not shown:
				bad.append(int(d))
		await _until(func() -> bool: return _boss.state == RootKeeper.State.STANCE, 3.0)
	_check(bad.is_empty() and hit_d.size() >= 3, "%s(%d페이즈): 맞은 거리 %s, 그중 부채꼴 밖 %s (비어야 함)" % [pattern, ph, hit_d, bad])


# ---------- 2) 되돌려 베기 ----------

func _sweep2_timing_and_side() -> void:
	for ph in [1, 2]:
		_prep_boss(2500, ph)
		_reset_player(1800)
		await _frames(5)
		_boss.force_pattern("SWEEP2")
		var want := 0.45 * (0.7 if ph == 2 else 1.0)
		var startup := _boss.startup_len
		var front := 0
		var behind := 0
		await _until(func() -> bool: return _boss.attack_phase == "active", 2.0)
		while _boss.attack_phase == "active":
			await get_tree().physics_frame
			var rel: float = (_vis.head_world().x - _boss.global_position.x) * float(_boss.facing)
			if rel >= 0.0:
				front += 1
			else:
				behind += 1
		_check(absf(startup - want) < 0.001 and behind == 0 and front > 0, "되돌려 베기 %d페이즈: 예비 %.3f초(%.3f), 타격 중 지팡이 머리 앞 %d / 뒤 %d 프레임 (뒤 0)" % [ph, startup, want, front, behind])
		await _until(func() -> bool: return _boss.state == RootKeeper.State.STANCE, 3.0)


# ---------- 3) 2페이즈 흐트러짐 ----------

func _phase2_poise() -> void:
	_prep_boss(2500, 1)
	_reset_player(1800)
	_boss.hp = _boss.max_hp * 0.6
	_boss.poise = _boss.max_poise - 1.0
	_boss.receive_hit(HitData.make(1.0, 50.0, _player), null)
	var broke := _boss.state == RootKeeper.State.BROKEN
	_boss.hp = _boss.max_hp * 0.51
	_boss.receive_hit(HitData.make(30.0, 0.0, _player), null)
	var rise := _boss.state == RootKeeper.State.RISE
	var p_after := _boss.poise
	await _until(func() -> bool: return _boss.state == RootKeeper.State.STANCE, 5.0)
	var p_stance := _boss.poise
	_boss.receive_hit(HitData.make(10.0, 20.0, _player), null)
	_check(broke and rise and p_after == 0.0 and _boss.state != RootKeeper.State.BROKEN, "무너진 채 2페이즈 전환: 무너짐 %s → RISE %s, 흐트러짐 %.0f → 일어선 뒤 %.0f, 한 대 맞고 %s (BROKEN 아님)" % [broke, rise, p_after, p_stance, _boss.state_name()])
	_boss.phase = 1
	_boss.hp = _boss.max_hp


# ---------- 4) 무너지면 예약 취소 ----------

func _broken_events(pattern: String, cls: String, wait: float) -> void:
	_prep_boss(2500, 2)
	_reset_player(1900)
	_player._invuln_timer = 9999.0
	await _frames(3)
	_boss.force_pattern(pattern)
	await _until(func() -> bool: return _boss.attack_phase == "active", 3.0)
	await _frames(1)
	var at_break := _count(cls)
	_boss.poise = _boss.max_poise - 1.0
	_boss.receive_hit(HitData.make(1.0, 50.0, _player), null)
	var st := _boss.state_name()
	var t := 0.0
	var most := at_break
	while t < wait:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		most = maxi(most, _count(cls))
	_check(st == "BROKEN" and most <= at_break and _boss._events.is_empty(), "%s 도중 무너짐: 무너진 순간 %s %d개 → %.1f초 동안 최대 %d개 (늘면 안 됨), 예약 남음 %d" % [pattern, cls, at_break, wait, most, _boss._events.size()])
	_boss._timer = 0.0
	await _until(func() -> bool: return _boss.state == RootKeeper.State.STANCE, 2.0)
	_player._invuln_timer = 0.0
	_clear_fx()


# ---------- 5) 씨앗 점 ----------

func _seed_mark() -> void:
	var res := []
	var ok := RootSeed.MARK_RX >= RootSeed.BURST_RADIUS
	for off in [60.0, 85.0, 115.0]:
		_prep_boss(2500, 1)
		_reset_player(1800)
		await _frames(20)
		var hp0 := _player.hp
		_boss._spawn_seed(_player.global_position.x + off)
		await _frames(80)
		var hurt := hp0 - _player.hp > 0.5
		# 몸 가장자리(중심 ± 25)가 점(반폭 MARK_RX) 안이면 '보인다'
		var shown: bool = off - 25.0 <= RootSeed.MARK_RX
		res.append("%.0f옆:피해%s/점안%s" % [off, hurt, shown])
		if hurt and not shown:
			ok = false
		await _frames(30)
	_check(ok, "씨앗: 주황 점 반폭 %.0f(터짐 %.0f 이상), %s — 맞았는데 점 밖인 경우 없음" % [RootSeed.MARK_RX, RootSeed.BURST_RADIUS, ", ".join(res)])


# ---------- 6) 늦게 솟는 것들의 예고 ----------

func _delayed_telegraphs() -> void:
	# 물결 가시
	_prep_boss(2500, 2)
	_reset_player(1900)
	_player._invuln_timer = 9999.0
	await _frames(3)
	_boss._spike_wave = false
	_boss.force_pattern("SPIKES")
	await _until(func() -> bool: return _boss.attack_phase == "active", 3.0)
	await _frames(1)
	var waiting := 0
	var marked := 0
	for n in get_tree().get_nodes_in_group("root_effect"):
		if n is RootSpike and n._t < n.delay:
			waiting += 1
			if n._mark.visible:
				marked += 1
	_check(waiting >= 3 and marked == waiting, "물결 가시: 보스 예고가 꺼진 뒤 기다리는 가시 %d개 중 스스로 예고를 그리는 것 %d개" % [waiting, marked])
	await _until(func() -> bool: return _boss.state == RootKeeper.State.STANCE, 3.0)
	_clear_fx()
	# 두 번째 뿌리 손
	_prep_boss(2500, 2)
	_reset_player(1900)
	await _frames(3)
	_boss.force_pattern("HAND")
	await _until(func() -> bool: return _boss.attack_phase == "active", 3.0)
	await _frames(1)
	var late: RootHand = null
	for n in get_tree().get_nodes_in_group("root_effect"):
		if n is RootHand and n.delay > 0.0:
			late = n
	_check(late != null and late.stage() == "wait" and _boss.hand_targets.is_empty(), "두 번째 뿌리 손: 보스 예고 자리 비움 %s, 손은 기다림(%s) 중 스스로 붉은 타원을 그림" % [_boss.hand_targets.is_empty(), late.stage() if late else "없음"])
	await _until(func() -> bool: return _boss.state == RootKeeper.State.STANCE, 3.0)
	await _frames(60)
	_player._invuln_timer = 0.0
	_clear_fx()


# ---------- 7) 구슬 자리 ----------

func _orb_origin() -> void:
	for ph in [1, 2]:
		_prep_boss(2500, ph)
		_reset_player(1700)
		_player._invuln_timer = 9999.0
		await _frames(3)
		_boss.force_pattern("ORBS")
		var ring := Vector2.ZERO
		while _boss.attack_phase == "startup":
			ring = _vis.head_world()
			await get_tree().physics_frame
		await get_tree().physics_frame
		var first: RootOrb = null
		for n in get_tree().get_nodes_in_group("root_effect"):
			if n is RootOrb:
				first = n
		var d := first.global_position.distance_to(ring) if first else 999.0
		_check(d < 80.0, "구슬 %d페이즈: 첫 구슬이 예고 고리(지팡이 머리)에서 %.0fpx (고리 반지름 80 미만)" % [ph, d])
		await _until(func() -> bool: return _boss.state == RootKeeper.State.STANCE, 3.0)
		_player._invuln_timer = 0.0
		_clear_fx()


# ---------- 8) 연계 몸 돌리기 ----------

func _chain_turn() -> void:
	_prep_boss(2500, 2)
	_reset_player(2500 + 300)   # 보스 뒤 (보스는 왼쪽을 본다)
	_player._invuln_timer = 9999.0
	await _frames(3)
	_boss._begin(RootKeeper.State.HAND, 0.1)
	_boss.attack_phase = "recovery"
	_boss._timer = 0.0
	_boss._chain = RootKeeper.State.SWEEP
	_boss._end_attack()
	var st := _boss.state_name()
	var f := _boss.facing
	_check(st == "SWEEP" and f == 1, "연계 HAND→SWEEP: 소녀가 뒤(+300)에 있으면 돌아선다 → %s, facing %d (1)" % [st, f])
	await _until(func() -> bool: return _boss.state == RootKeeper.State.STANCE, 3.0)
	# 멀어졌으면 휘두르기 연계는 거둔다
	_prep_boss(2500, 2)
	_reset_player(2500 - 700)
	await _frames(3)
	_boss._begin(RootKeeper.State.HAND, 0.1)
	_boss.attack_phase = "recovery"
	_boss._timer = 0.0
	_boss._chain = RootKeeper.State.SWEEP
	_boss._end_attack()
	_check(_boss.state == RootKeeper.State.STANCE, "연계 HAND→SWEEP: 소녀가 700 떨어져 있으면 휘두르지 않고 자세로 → %s" % _boss.state_name())
	_player._invuln_timer = 0.0


# ---------- 9) 뿌리 손 던지기 ----------

func _hand_throw() -> void:
	_prep_boss(2500, 1)
	_reset_player(2000)
	await _frames(20)
	_boss.force_pattern("HAND")
	await _until(func() -> bool:
		for n in get_tree().get_nodes_in_group("root_effect"):
			if n is RootHand:
				return true
		return false, 3.0)
	var hand: RootHand = null
	for n in get_tree().get_nodes_in_group("root_effect"):
		if n is RootHand:
			hand = n
	if hand == null:
		_check(false, "뿌리 손이 솟지 않음")
		return
	var held := 0
	var held_not_hit := 0
	var x_release := 0.0
	var released := false
	var t := 0.0
	while is_instance_valid(hand) and t < 3.0:
		await get_tree().physics_frame
		_hold_boss()
		t += 1.0 / 60.0
		if not is_instance_valid(hand):
			break
		if hand._held != null:
			held += 1
			if _player.state != Player.State.HIT:
				held_not_hit += 1
		elif held > 0 and not released:
			released = true
			x_release = _player.global_position.x
	await _frames(40)
	var moved := absf(_player.global_position.x - x_release)
	_check(held >= 38 and held_not_hit == 0 and released and moved >= 60.0, "뿌리 손: 묶인 프레임 %d(약 0.7초), 그중 피격 상태 아님 %d (0), 놓은 뒤 가로로 %.0fpx 날아감 (60 이상)" % [held, held_not_hit, moved])
	await _frames(60)


# ---------- 10) 가시 판정 높이 ----------

func _spike_shape() -> void:
	var sp: RootSpike = load("res://scenes/combat/root_spike.tscn").instantiate()
	sp.delay = 0.1
	_room.add_child(sp)
	sp.set_physics_process(false)
	sp.global_position = Vector2(1000, _boss.ground_y)
	var rows := []
	var ok := true
	for i in 20:
		sp._physics_process(1.0 / 60.0)
		var h: float = (sp._shape.shape as RectangleShape2D).size.y
		if sp._t >= sp.delay:
			if absf(h - maxf(sp.height(), 30.0)) > 1.5:
				ok = false
		if i in [3, 8, 10, 14, 19]:
			rows.append("%.2f초 그림 %.0f/판정 %.0f" % [sp._t, sp.height(), h])
	_check(ok, "가시 판정 높이가 그림을 따라 자람: %s" % ", ".join(rows))
	sp.queue_free()

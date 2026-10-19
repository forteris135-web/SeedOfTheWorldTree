extends Node
## 이펙트 시스템 시험 (2026-10-19 이펙트 리뉴얼 F1, 화면 없이 돈다).
## 실행: godot --headless --path . res://tools/probe_fx.tscn      마지막 줄 "[probe] 끝: 실패 N"
## 1) 표의 모든 이펙트가 뜨고(딸린 이펙트 포함) 수명이 끝나면 풀로 돌아온다. 끌려가는(driven) 이펙트는 놓아야 끝난다.
## 2) 상한: 한꺼번에 MAX_ACTIVE 개를 넘지 않고, 가득 차면 낮은 우선순위부터 비킨다. 풀은 상한보다 커지지 않는다.
## 3) 바쁜 싸움 부하: 매 프레임 이펙트를 쏟아부어도 Fx 갱신 한 번이 가볍다 (상한까지 찬 상태에서 잰다).
## 4) 레이저: 벽에서 멈추고, 빛줄기 안의 여러 적을 한 번씩, 벽 뒤·등 뒤 적은 안 맞히고, 한쪽 방향 가지는 지나가고,
##    맞는 영역이 둘인 상대도 한 번만. 모으는 중에 맞으면 쏘지 않고 쿨다운을 돌려준다.
## 5) 바람 초승달 검기: 지형(벽)에 막혀 사라지고, 벽 뒤 적은 안 맞힌다. 앞의 적은 한 번 맞힌다.

var _fail := 0
var _arena: Node2D
var _player: Player
const FLOOR_Y := 0.0


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


func _process_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await _test_every_effect()
	await _test_driven()
	await _test_cap_and_pool()
	await _test_stress()
	await _build_arena()
	await _test_laser()
	await _test_laser_cancel()
	await _test_wind()


# ---------- 1) 모든 이펙트 ----------
func _test_every_effect() -> void:
	Fx.clear()
	await _process_frames(2)
	var names: Array = Fx.effect_names()
	var missing := []
	var longest := 0.0
	for n in names:
		var def: Dictionary = Fx.Table.EFFECTS[n]
		var texs: Array = def["tex"] if def["tex"] is Array else [def["tex"]]
		for t in texs:
			if Fx.texture(t) == null:
				missing.append("%s(%s)" % [n, t])
		longest = maxf(longest, float(def.get("life", 0.3)))
		for ch in def.get("children", []):
			if not Fx.has_effect(ch[0]):
				missing.append("%s→%s" % [n, ch[0]])
	_check(missing.is_empty(), "표의 그림·딸린 이펙트가 모두 있다 %s" % [missing])
	var failed := []
	for n in names:
		# 이펙트가 많아(F2) 상한(72)을 넘지 않게 하나씩 비우고 띄운다
		Fx.clear()
		var before := Fx.active_count()
		var fx := Fx.spawn(n, Vector2(100, 100))
		if fx == null or Fx.active_count() <= before or fx.fx_name != n or not fx.visible:
			failed.append(n)
	_check(failed.is_empty(), "이펙트 %d개가 모두 뜬다 (못 뜬 것 %s)" % [names.size(), failed])
	var peak := Fx.active_count()
	await _process_frames(int((longest + 0.3) * 60.0) + 10)
	await get_tree().create_timer(longest + 0.3).timeout
	print("[probe] 한꺼번에 뜬 이펙트 %d (딸린 것 포함), 풀 %d, 가장 긴 수명 %.2f초 → 지금 떠 있는 것 %d" % [peak, Fx.pool_size(), longest, Fx.active_count()])
	_check(Fx.active_count() == 0, "수명이 끝나면 모두 풀로 돌아온다 (남은 %d)" % Fx.active_count())
	_check(Fx.total_nodes() <= Fx.MAX_ACTIVE, "만든 이펙트 노드가 상한(%d)보다 많지 않다 (%d)" % [Fx.MAX_ACTIVE, Fx.total_nodes()])
	# 따라다니는 이펙트: 따라가던 노드가 사라져도 오류 없이 제자리에서 끝난다
	var dummy := Node2D.new()
	add_child(dummy)
	dummy.global_position = Vector2(300, 300)
	var f2 := Fx.spawn("soul_switch", dummy.global_position, {"follow": dummy})
	await _process_frames(2)
	dummy.global_position = Vector2(400, 300)
	await _process_frames(2)
	var followed := f2 != null and absf(f2.global_position.x - 400.0) < 1.0
	dummy.queue_free()
	await _process_frames(3)
	_check(followed and (not Fx.alive(f2, f2.gen) or f2.global_position.x > 399.0), "follow: 따라가다가 대상이 사라져도 멀쩡하다")
	Fx.clear()


# ---------- 끌려가는 이펙트 ----------
func _test_driven() -> void:
	Fx.clear()
	var fx := Fx.spawn("slash1", Vector2(0, 0), {"driven": true})
	var gen := fx.gen
	for i in 40:
		Fx.set_reveal(fx, gen, float(i) / 39.0)
		await get_tree().process_frame
	var held := Fx.alive(fx, gen)
	var head: float = fx._head
	Fx.release(fx, gen)
	await get_tree().create_timer(0.6).timeout
	print("[probe] 끌려가는 칼질: 40프레임 뒤 살아 있음 %s (머리 %.2f), 놓은 뒤 0.6초 → 살아 있음 %s" % [held, head, Fx.alive(fx, gen)])
	_check(held and head > 0.99, "driven: 놓기 전에는 끝나지 않고 머리가 끝까지 간다")
	_check(not Fx.alive(fx, gen), "driven: 놓으면 남은 수명대로 끝난다")
	# 같은 노드가 다른 이펙트로 다시 쓰이면 옛 손잡이로는 못 만진다
	var a := Fx.spawn("mote", Vector2.ZERO)
	var ag := a.gen
	Fx.kill(a, ag)
	var b := Fx.spawn("mote", Vector2.ZERO)
	_check(not Fx.alive(a, ag) and (b != a or b.gen != ag), "다시 쓰인 이펙트는 옛 gen 으로 살아 있지 않다")
	Fx.clear()


# ---------- 2) 상한·우선순위·풀 ----------
func _test_cap_and_pool() -> void:
	Fx.clear()
	var drop0 := Fx.dropped_total
	for i in 200:
		Fx.spawn("mote", Vector2(i, 0))   # 우선순위 0
	var full := Fx.active_count()
	_check(full == Fx.MAX_ACTIVE, "200개를 띄워도 상한 %d 개까지만 (지금 %d)" % [Fx.MAX_ACTIVE, full])
	var imp := Fx.spawn("break_burst", Vector2.ZERO, {"children": false})   # 우선순위 2: 먼지를 밀어내고 뜬다
	_check(imp != null and Fx.active_count() == Fx.MAX_ACTIVE, "가득 차도 중요한 이펙트는 낮은 것을 밀어내고 뜬다")
	Fx.clear()
	for i in Fx.MAX_ACTIVE:
		Fx.spawn("slash1", Vector2.ZERO, {"driven": true})   # 우선순위 2 + 끌려가는 중 (밀려나지 않는다)
	var low := Fx.spawn("mote", Vector2.ZERO)
	_check(low == null and Fx.dropped_total > drop0, "중요한 것으로 가득 차면 먼지는 띄우지 않는다 (버림 %d)" % (Fx.dropped_total - drop0))
	Fx.clear()
	_check(Fx.active_count() == 0 and Fx.pool_size() == Fx.total_nodes(), "clear 뒤 0개, 모두 풀로 (%d)" % Fx.pool_size())


# ---------- 3) 바쁜 싸움 부하 ----------
func _test_stress() -> void:
	Fx.clear()
	var nodes0 := Fx.total_nodes()
	var heavy := ["hit_spark", "hit_spark_big", "slash3", "plunge_impact", "break_burst", "laser_hit", "wind_hit", "death_dust", "land_dust", "mote"]
	var t_us := 0
	var ticks := 0
	var max_active := 0
	for f in 120:
		for k in 6:
			Fx.spawn(heavy[(f + k) % heavy.size()], Vector2(randf_range(-600, 600), randf_range(-300, 300)), {"facing": 1 if k % 2 == 0 else -1})
		max_active = maxi(max_active, Fx.active_count())
		# Fx 갱신 한 번에 드는 시간 (엔진이 부르는 것과 같은 함수를 직접 재서 잰다 — 상한까지 찬 상태)
		var t0 := Time.get_ticks_usec()
		Fx._process(1.0 / 60.0)
		t_us += Time.get_ticks_usec() - t0
		ticks += 1
		await get_tree().process_frame
	var avg := float(t_us) / ticks
	print("[probe] 부하: 120프레임 동안 프레임마다 6개(+딸린 것) → 최대 동시 %d, 이펙트 노드 %d (처음 %d), Fx 갱신 평균 %.0f µs" % [max_active, Fx.total_nodes(), nodes0, avg])
	_check(max_active <= Fx.MAX_ACTIVE and Fx.total_nodes() <= Fx.MAX_ACTIVE, "부하 중에도 상한을 지키고 노드를 더 만들지 않는다")
	# 맥 기준 (아이폰 11 Pro 는 3~4배 느리다고 보고 넉넉히): 상한까지 찬 갱신이 1.5ms 안
	_check(avg < 1500.0, "Fx 갱신 한 번이 가볍다 (평균 %.0f µs < 1500)" % avg)
	Fx.clear()


# ---------- 시험장 (바닥 + 벽 + 한쪽 방향 가지) ----------
func _body(pos: Vector2, size: Vector2) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = size
	cs.shape = r
	b.add_child(cs)
	b.position = pos
	_arena.add_child(b)
	return b


func _build_arena() -> void:
	_arena = Node2D.new()
	add_child(_arena)
	_body(Vector2(0, FLOOR_Y + 50), Vector2(8000, 100))
	_player = load("res://scenes/player/player.tscn").instantiate()
	_player.position = Vector2(0, FLOOR_Y - 68)
	_arena.add_child(_player)
	_player.input_enabled = false
	_player._invuln_timer = 99999.0
	Progress.gain_ability("wind")
	Progress.gain_ability("light")
	await _frames(20)


func _dummy(x: float) -> EnemyBase:
	var e: EnemyBase = load("res://scenes/enemies/woodcutter.tscn").instantiate()
	e.position = Vector2(x, FLOOR_Y - 66.0)
	_arena.add_child(e)
	e.max_hp = 99999.0
	e.hp = 99999.0
	e.max_poise = 100000.0
	e.set_physics_process(false)
	return e


func _lost(e: EnemyBase) -> float:
	return e.max_hp - e.hp


func _laser_node() -> SoulLaser:
	for c in _arena.get_children():
		if c is SoulLaser and not c.is_queued_for_deletion():
			return c
	return null


## 맞는 영역이 둘인 시험용 상대 (맞은 횟수를 센다)
class TwoBox extends Node2D:
	var hits := 0
	func receive_hit(_hit: HitData, _hb: Hurtbox) -> String:
		hits += 1
		return "hit"


func _two_box(x: float) -> Node2D:
	var t := TwoBox.new()
	t.position = Vector2(x, FLOOR_Y - 60)
	for dy in [-30.0, 30.0]:
		var hb := Hurtbox.new()
		hb.collision_layer = 16
		hb.collision_mask = 0
		var cs := CollisionShape2D.new()
		var r := RectangleShape2D.new()
		r.size = Vector2(40, 40)
		cs.shape = r
		hb.add_child(cs)
		hb.position = Vector2(0, dy)
		t.add_child(hb)
	_arena.add_child(t)
	return t


# ---------- 4) 레이저 ----------
func _test_laser() -> void:
	var wall := _body(Vector2(820, FLOOR_Y - 200), Vector2(40, 400))   # 벽 왼쪽 면 x = 800
	# 빛줄기 높이(소녀 가운데 -20 → y -88)를 가로지르는 한쪽 방향 가지
	var branch := Platform.new()
	branch.size = Vector2(120, 20)
	branch.one_way = true
	branch.decorate = false
	branch.position = Vector2(360, FLOOR_Y - 98)
	_arena.add_child(branch)
	var e1 := _dummy(300.0)
	var e2 := _dummy(560.0)
	var behind_wall := _dummy(1000.0)
	var back := _dummy(-90.0)
	var two := _two_box(680.0)
	_player.global_position = Vector2(0, FLOOR_Y - 68)
	_player.facing = 1
	_player.soul = "light"
	_player._soul_cooldowns.clear()
	await _frames(4)
	_player.cast_soul_skill()
	await _frames(2)
	var l := _laser_node()
	_check(l != null and l.phase == "charge", "레이저: 먼저 손에 빛을 모은다")
	await _frames(12)
	var dmg := _player.light_shot_damage * _player.attack_multiplier
	var end_x: float = l.end_point.x if is_instance_valid(l) else -1.0
	var walled: bool = l.hit_wall if is_instance_valid(l) else false
	var hit_n: int = l.hit_count if is_instance_valid(l) else -1
	await _frames(20)   # 맞히는 구간(0.08초)이 지나도 더 맞지 않는다
	print("[probe] 레이저: 끝 x %.0f (벽 면 800), 벽 %s, 맞힌 수 %d / 앞 적 %.0f·%.0f, 벽 뒤 %.0f, 등 뒤 %.0f, 영역 둘인 상대 %d번 (피해 %.0f)" % [end_x, walled, hit_n, _lost(e1), _lost(e2), _lost(behind_wall), _lost(back), two.hits, dmg])
	_check(walled and absf(end_x - 800.0) < 2.0, "레이저가 벽 면에서 멈춘다 (한쪽 방향 가지는 지나간다)")
	_check(absf(_lost(e1) - dmg) < 0.5 and absf(_lost(e2) - dmg) < 0.5, "빛줄기 안의 적 둘이 모두 딱 한 번씩 맞는다")
	_check(_lost(behind_wall) == 0.0 and _lost(back) == 0.0, "벽 뒤·등 뒤 적은 맞지 않는다")
	_check(two.hits == 1, "맞는 영역이 둘인 상대도 한 번만 맞는다 (%d)" % two.hits)
	await _frames(30)
	_check(_laser_node() == null, "빛줄기는 잠깐 남았다가 사라진다")
	# 왼쪽으로 쏘기 (벽 없음): 사거리만큼
	_player.facing = -1
	_player._soul_cooldowns.clear()
	_player.cast_soul_skill()
	await _frames(12)
	var l2 := _laser_node()
	var len2: float = absf(l2.end_point.x - _player.global_position.x) if l2 else -1.0
	_check(l2 != null and not l2.hit_wall and absf(len2 - _player.light_beam_range()) < 2.0 and l2.end_point.x < _player.global_position.x, "왼쪽으로 쏘면 왼쪽으로 사거리 %.0f 만큼 (%.0f)" % [_player.light_beam_range(), len2])
	await _frames(30)
	for n in [wall, branch, e1, e2, behind_wall, back, two]:
		n.queue_free()
	_player.facing = 1
	await _frames(3)


func _test_laser_cancel() -> void:
	var e := _dummy(300.0)
	_player.global_position = Vector2(0, FLOOR_Y - 68)
	_player.soul = "light"
	_player._soul_cooldowns.clear()
	await _frames(3)
	_player.cast_soul_skill()
	var cd0 := _player.soul_cooldown_left("light")
	await _frames(2)
	_player._invuln_timer = 0.0
	_player._set_state(Player.State.HIT)
	_player._hit_timer = 0.3
	await _frames(15)
	print("[probe] 모으는 중 맞음: 쏜 직후 쿨 %.2f → %.2f, 레이저 노드 %s, 적 잃은 체력 %.0f" % [cd0, _player.soul_cooldown_left("light"), _laser_node(), _lost(e)])
	_check(cd0 > 6.9 and _player.soul_cooldown_left("light") == 0.0 and _laser_node() == null and _lost(e) == 0.0, "모으는 중에 맞으면 쏘지 않고 쿨다운을 돌려준다")
	_player._invuln_timer = 99999.0
	e.queue_free()
	await _frames(30)


# ---------- 5) 바람 초승달 검기 ----------
func _test_wind() -> void:
	var wall := _body(Vector2(720, FLOOR_Y - 200), Vector2(40, 400))   # 벽 왼쪽 면 x = 700
	var front := _dummy(380.0)
	var behind := _dummy(900.0)
	_player.global_position = Vector2(0, FLOOR_Y - 68)
	_player.facing = 1
	_player.soul = "wind"
	_player._soul_cooldowns.clear()
	_player._set_state(Player.State.IDLE)
	await _frames(4)
	_player.cast_soul_skill()
	await get_tree().physics_frame
	var p: WindCrescent = null
	for n in get_tree().get_nodes_in_group("projectile"):
		if n is WindCrescent:
			p = n
	_check(p != null, "바람: 초승달 검기가 나간다")
	await _frames(90)
	var dmg := _player.gust_damage * _player.attack_multiplier
	print("[probe] 바람: 앞 적 %.0f (피해 %.0f), 벽 뒤 적 %.0f, 검기 남아 있음 %s" % [_lost(front), dmg, _lost(behind), is_instance_valid(p) and not p._dead])
	_check(absf(_lost(front) - dmg) < 0.5, "바람: 앞의 적을 한 번 맞히고 사라진다")
	front.queue_free()
	await _frames(3)
	_player._soul_cooldowns.clear()
	_player.cast_soul_skill()
	await get_tree().physics_frame
	var q: WindCrescent = null
	for n in get_tree().get_nodes_in_group("projectile"):
		if n is WindCrescent:
			q = n
	var last_x := 0.0
	var landed := {"pos": Vector2.INF}
	if q:
		q.landed.connect(func(pos, _n): landed["pos"] = pos)
	for i in 120:
		await get_tree().physics_frame
		if is_instance_valid(q) and not q._dead:
			last_x = q.global_position.x
	print("[probe] 바람이 벽에: 마지막 x %.0f, 닿은 자리 %s (벽 면 700), 벽 뒤 적 %.0f" % [last_x, landed["pos"], _lost(behind)])
	_check(landed["pos"] != Vector2.INF and absf(landed["pos"].x - 700.0) < 2.0 and last_x <= 700.0, "바람: 벽(지형)에 닿으면 그 자리에서 사라진다")
	_check(_lost(behind) == 0.0, "바람: 벽 뒤 적은 맞지 않는다")
	wall.queue_free()
	behind.queue_free()
	await _frames(3)
	# 한쪽 방향 가지(one_way)는 지나간다 — 레이저·기사 검기와 같은 규칙 (2026-10-20 QA: 두께 40px 가지 옆면에 검기가 지워졌다).
	# 가지는 검기 높이(소녀 가운데 -20)를 가로지르고, 소녀 바로 앞(생기는 자리의 벽 검사 안)에도 하나 둔다.
	var branches := []
	for bx in [70.0, 300.0]:
		var br := Platform.new()
		br.size = Vector2(120, 40)
		br.one_way = true
		br.decorate = false
		br.position = Vector2(bx, FLOOR_Y - 68 - 20 - 20)
		_arena.add_child(br)
		branches.append(br)
	var past := _dummy(600.0)
	_player.global_position = Vector2(0, FLOOR_Y - 68)
	_player._soul_cooldowns.clear()
	_player._set_state(Player.State.IDLE)
	await _frames(4)
	_player.cast_soul_skill()
	await _frames(90)
	print("[probe] 바람이 한쪽 방향 가지 둘을 지나: 가지 너머 적 %.0f (피해 %.0f)" % [_lost(past), dmg])
	_check(absf(_lost(past) - dmg) < 0.5, "바람: 한쪽 방향 가지는 지나가 그 너머 적을 맞힌다")
	for n in branches + [past]:
		n.queue_free()
	await _frames(3)

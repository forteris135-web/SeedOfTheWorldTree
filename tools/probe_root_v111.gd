extends Node
## v1.1.1 뿌리지기 개편 확인 (실제 방 abyss_boss, 엔진 물리로 판정).
## 실행: godot --headless --path <프로젝트> res://tools/probe_root_v111.tscn
##       화면 있는 실행(창)이면 screenshots/root_v111_*.png 도 남긴다 (예고·촉수·씨앗 폭우·싸움 전 대화·싸움 중 자막).
## 확인하는 것:
##  1) 체력 = 2100 × Balance.hp_mult(심연) × 1.75, 공격 배율 1페이즈 ×1.25 · 2페이즈 ×1.375 (가시·촉수 실제 피해)
##  2) 뿌리 촉수(맵 패턴): 1페이즈 2줄 / 2페이즈 4줄, 예고 띠 = 다 솟은 판정 사각형(로컬·월드), 가드 불가,
##     땅 폭 안에 선 소녀는 맞고 땅 폭 밖(빈 틈)에 선 소녀는 안 맞음, 4줄 땅 폭 사이 빈 틈 ≥ 250px, 시계가 저절로 건다
##  3) 씨앗 폭우: 3물결, 물결마다 틈 하나(틈 안 씨앗 없음, 줄의 다른 곳은 간격 ≤ 170), 첫 틈은 소녀에게서 260px 넘게,
##     씨앗은 0.55초 떠서 예고 → 떨어짐, 2페이즈에도 예비·길이·씨앗 수·피해(×1.25) 그대로
##  4) 대사: 처음 마주칠 때만 싸움 전 대화(그동안 보스는 등장 자세로 기다림, 깃발), 두 번째는 없음,
##     싸움 중 자막 — 시작·체력 75%·다시 일어섬 문장이 데이터 파일 그대로 뜸, 보스 러시면 안 뜸
## 마지막에 "[probe] 끝: 실패 N" 을 찍고 그 수로 종료한다.

var _room: Node
var _player: Player
var _boss: RootKeeper
var _fail := 0
var _shots := false
var _data: Dictionary


func _ready() -> void:
	await get_tree().process_frame
	print("[probe] 뿌리지기 v1.1.1 확인 시작")
	_shots = DisplayServer.get_name() != "headless"
	Settings.set_value("screen_shake", false)
	Progress.set_flag(RootKeeper.INTRO_FLAG, false)
	_data = DialogueData.load_dialogue(RootKeeper.DIALOGUE_PATH)
	_room = load("res://scenes/rooms/abyss_boss.tscn").instantiate()
	add_child(_room)
	await _frames(10)
	_player = get_tree().get_first_node_in_group("player") as Player
	_boss = _room.get_node("Boss") as RootKeeper
	_boss.intro_talk_mode = 1   # 시험은 방을 자식으로 놓으므로 싸움 전 대화를 일부러 켠다
	_player._invuln_timer = 99999.0
	_player.global_position = Vector2(1500, _boss.ground_y - 67)
	await _frames(10)
	await _intro_talk()
	await _hp_and_atk()
	await _tentacles_phase1()
	await _map_clock()
	await _barrage(1)
	await _lines_phase1()
	await _to_phase2()
	await _tentacles_phase2()
	await _barrage(2)
	await _phase2_atk()
	await _second_encounter()
	await _rush_lines()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(_fail)


# ---------- 도우미 ----------

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _until(cond: Callable, max_t: float) -> float:
	var t := 0.0
	while t < max_t and not cond.call():
		await get_tree().physics_frame
		t += 1.0 / 60.0
	return t


func _check(ok: bool, msg: String) -> void:
	print("[probe] %s %s" % ["OK  " if ok else "실패", msg])
	if not ok:
		_fail += 1


func _shot(name: String) -> void:
	if not _shots:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(ProjectSettings.globalize_path("res://screenshots/root_v111_%s.png" % name))
		print("[probe] 스크린샷 root_v111_%s.png" % name)


## 보스를 자세로 붙잡고(스스로 고르지 않게) 떠 있는 효과를 치운다
func _hold() -> void:
	for n in get_tree().get_nodes_in_group("root_effect"):
		n.queue_free()
	_boss._chain = -1
	_boss._events.clear()
	_boss._set_state(RootKeeper.State.STANCE)
	_boss._timer = 99.0
	_boss.velocity = Vector2.ZERO
	_boss.manual_control = true


func _stand(x: float) -> void:
	_player.global_position = Vector2(x, _boss.ground_y - 67)
	_player.velocity = Vector2.ZERO


func _vulnerable() -> void:
	_player._invuln_timer = 0.0
	_player.hp = _player.max_hp
	_player.state = Player.State.IDLE
	_player._hit_timer = 0.0


func _tentacles() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("root_effect"):
		if n is RootTentacle and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _seeds() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("root_effect"):
		if n is RootSeed and not n.is_queued_for_deletion():
			out.append(n)
	return out


func _line(key: String, i := 0) -> String:
	var arr: Array = (_data.get("battle", {}) as Dictionary).get(key, [])
	return str(arr[mini(i, arr.size() - 1)].get("text", "")) if not arr.is_empty() else ""


# ---------- 4) 싸움 전 대화 (처음) ----------

func _intro_talk() -> void:
	await _until(func() -> bool: return Dialogue.is_active(), 2.0)
	_check(Dialogue.is_active(), "처음 마주침: 싸움 전 대화 상자가 뜬다")
	_check(Progress.has(RootKeeper.INTRO_FLAG), "처음 마주침 깃발 %s 이 선다" % RootKeeper.INTRO_FLAG)
	_check(Dialogue._lines.size() == (_data.get("intro", []) as Array).size() and str(Dialogue._lines[0].get("speaker", "")) == "뿌리지기",
		"대화 = 데이터 파일 intro %d줄, 말하는 이 '뿌리지기' (셀레니아 대사 없음)" % Dialogue._lines.size())
	var silent := true
	for l in Dialogue._lines:
		silent = silent and str(l.get("speaker", "")) != "셀레니아"
	_check(silent, "셀레니아는 말하지 않는다")
	await get_tree().create_timer(3.2).timeout
	_check(_boss.state == RootKeeper.State.INTRO, "대화 중에는 보스가 등장 자세로 기다린다 (지금 %s)" % _boss.state_name())
	await _shot("intro_dialogue")
	# 대화 넘기기 (화면 아래 대화 상자: 한 번 = 다 보이기, 한 번 더 = 다음 줄)
	var t := 0.0
	while Dialogue.is_active() and t < 20.0:
		Input.action_press("ui_accept")
		await get_tree().physics_frame
		Input.action_release("ui_accept")
		await get_tree().create_timer(0.25).timeout
		t += 0.27
	_check(not Dialogue.is_active(), "대화를 다 넘기면 닫힌다")
	var w := await _until(func() -> bool: return _boss.state == RootKeeper.State.STANCE, 3.0)
	_check(_boss.state == RootKeeper.State.STANCE and w < 1.5, "대화가 끝나고 %.2f초 뒤 싸움 시작 (STANCE)" % w)
	# 시작 대사 (등장 이름 카드가 걷힌 뒤)
	await _until(func() -> bool: return _boss._speech.showing(), 3.0)
	_check(_boss._speech.current_text() == _line("start"), "싸움 중 자막: 시작 '%s'" % _boss._speech.current_text())
	_boss._timer = 99.0
	_boss.manual_control = true
	await get_tree().create_timer(0.4).timeout
	await _shot("battle_line_start")
	var r: Rect2 = _boss._speech.box_rect()
	var hud = _room.get_node_or_null("CombatHUD")
	var hud_right := float(hud.hud_right_x(r.position.y, r.end.y)) if hud else 0.0
	var vp := get_viewport().get_visible_rect().size
	_check(r.position.x > hud_right and r.end.y < vp.y * 0.17 - 20.0 and r.end.x < vp.x - 100.0,
		"자막 자리 %s: 소녀 HUD(오른쪽 끝 %.0f)·영혼 알림(높이 0.17)·오른쪽 위 버튼과 안 겹침" % [r, hud_right])


# ---------- 1) 체력·공격 배율 ----------

func _hp_and_atk() -> void:
	var want := 2100.0 * Balance.hp_mult("abyss") * 1.75
	_check(absf(_boss.max_hp - want) < 0.5, "체력 %.1f = 2100 × 심연 %.4f × 1.75 (%.1f)" % [_boss.max_hp, Balance.hp_mult("abyss"), want])
	_check(is_equal_approx(RootKeeper.extra("hp"), 1.75) and is_equal_approx(RootKeeper.extra("atk"), 1.25) and is_equal_approx(RootKeeper.extra("atk_phase2"), 1.10),
		"추가 배율 표: 체력 1.75 · 공격 1.25 · 2페이즈 1.10")
	_check(is_equal_approx(_boss.atk_factor(), 1.25), "1페이즈 공격 배율 %.3f (1.25)" % _boss.atk_factor())
	_hold()
	_stand(_boss.global_position.x - 500.0)
	_boss.force_pattern("SPIKES")
	await _until(func() -> bool: return _boss.attack_phase == "active", 2.0)
	await _frames(2)
	var dmg := -1.0
	for n in get_tree().get_nodes_in_group("root_effect"):
		if n is RootSpike:
			dmg = (n as RootSpike).damage
	_check(is_equal_approx(dmg, _boss.spike_damage * 1.25), "1페이즈 뿌리 가시 피해 %.2f = 20 × 1.25" % dmg)


# ---------- 2) 뿌리 촉수 ----------

func _strike_and_check(n_want: int, label: String, shot := "") -> Array:
	_hold()
	_boss.force_map_pattern()
	await _frames(2)
	var ts := _tentacles()
	_check(ts.size() == n_want, "%s: 뿌리 촉수 %d줄 (기대 %d)" % [label, ts.size(), n_want])
	if shot != "":
		await get_tree().create_timer(0.7).timeout
		await _shot(shot + "_telegraph")
	# 예고 동안은 판정 없음, 붉은 예고(가드 불가)
	var tel_ok := true
	for t: RootTentacle in ts:
		tel_ok = tel_ok and t.is_telegraphing() and t.hit_rect() == Rect2()
	_check(tel_ok, "%s: 예고 동안 판정이 꺼져 있다" % label)
	# 다 솟을 때까지 (마지막 줄이 솟고 EXTEND 뒤)
	var last: RootTentacle = ts[ts.size() - 1] if not ts.is_empty() else null
	if last:
		await _until(func() -> bool: return not is_instance_valid(last) or (not last.is_telegraphing() and last._t - last.delay > RootTentacle.EXTEND + 0.03), 4.0)
	if shot != "":
		await _shot(shot + "_strike")
	var eq := true
	var info := ""
	for t: RootTentacle in ts:
		if not is_instance_valid(t):
			continue
		var u := t._t - t.delay
		if u >= RootTentacle.HIT_WINDOW:
			continue   # 앞 줄은 이미 판정 창이 지났다 (아래 월드 비교만)
		var hr := t.hit_rect()
		var br := t.band_rect()
		var ok := hr.position.distance_to(br.position) < 1.0 and hr.size.distance_to(br.size) < 1.0
		# 판정 모양의 월드 꼭짓점 = 예고 띠의 월드 꼭짓점
		var cs := t._shape
		var rs := cs.shape as RectangleShape2D
		var xf := cs.global_transform
		var poly := PackedVector2Array([xf * (-rs.size / 2.0), xf * Vector2(rs.size.x / 2.0, -rs.size.y / 2.0), xf * (rs.size / 2.0), xf * Vector2(-rs.size.x / 2.0, rs.size.y / 2.0)])
		var bp := t.band_polygon()
		for i in 4:
			ok = ok and poly[i].distance_to(bp[i]) < 1.5
		eq = eq and ok
		info += " [%.0f×%.0f / %.0f×%.0f]" % [hr.size.x, hr.size.y, br.size.x, br.size.y]
	_check(eq, "%s: 다 솟은 판정 사각형 = 예고 띠 (로컬·월드 꼭짓점)%s" % [label, info])
	var long_ok := true
	for t: RootTentacle in ts:
		if is_instance_valid(t):
			long_ok = long_ok and t.length >= 1200.0
	_check(long_ok, "%s: 촉수 길이 모두 1200px 이상 (아주 긴 사선)" % label)
	return ts


func _tentacles_phase1() -> void:
	_boss.phase = 1
	await _strike_and_check(2, "1페이즈", "tentacle_p1")
	await get_tree().create_timer(1.5).timeout
	# 땅 폭 안 / 밖: 레이아웃을 직접 받아 첫 줄의 땅 폭 가운데(맞음)와 빈 틈(안 맞음)에 서 본다
	for trial in 2:
		_hold()
		var px := _boss.arena.get_center().x - 300.0
		_stand(px)
		await _frames(2)
		_boss.force_map_pattern()
		await _frames(1)
		var ts := _tentacles()
		var lay: Array = []
		for t: RootTentacle in ts:
			lay.append({"x": t.global_position.x, "lean": 1 if t.rotation > 0.0 else -1, "angle": PI / 2.0 - absf(t.rotation)})
		var stand_x := px
		if trial == 1:
			# 빈 틈: 모든 줄의 땅 폭에서 40px 넘게 떨어진 싸움터 안 자리
			stand_x = _gap_spot(lay)
		_vulnerable()
		_stand(stand_x)
		var hp0 := _player.hp
		var t_end: float = ts[ts.size() - 1].delay + RootTentacle.HIT_WINDOW + 0.1 if not ts.is_empty() else 2.0
		var tt := 0.0
		while tt < t_end:
			_stand(stand_x)
			await get_tree().physics_frame
			tt += 1.0 / 60.0
		var hit := _player.hp < hp0
		if trial == 0:
			_check(hit, "땅 폭 가운데(x %.0f)에 선 소녀는 맞는다 (체력 %.0f → %.0f)" % [stand_x, hp0, _player.hp])
		else:
			_check(not hit and stand_x > 0.0, "빈 틈(x %.0f)에 선 소녀는 안 맞는다 (체력 %.0f → %.0f)" % [stand_x, hp0, _player.hp])
		_player._invuln_timer = 99999.0
		_player.hp = _player.max_hp
		await get_tree().create_timer(1.3).timeout


## 모든 줄의 땅 폭에서 40px 넘게 떨어진 싸움터 안 자리 (없으면 -1)
func _gap_spot(lay: Array) -> float:
	var a := _boss.arena
	var x := a.position.x + 80.0
	while x < a.end.x - 80.0:
		var free := true
		for e in lay:
			var fp := RootKeeper.map_footprint(e)
			if x > fp.x - 40.0 and x < fp.y + 40.0:
				free = false
				break
		if free:
			return x
		x += 10.0
	return -1.0


func _map_clock() -> void:
	# 시계가 저절로 건다: 손 조종을 끄고 자세 타이머를 짧게 두면 (공격은 막으려고 계속 붙잡는다) MAP_FIRST 안에 뜬다
	_hold()
	_boss.manual_control = false
	_boss._map_timer = 1.0
	_boss._timer = 5.0
	var t := await _until(func() -> bool:
		_boss._timer = 5.0
		return not _tentacles().is_empty(), 3.0)
	_check(not _tentacles().is_empty(), "맵 패턴 시계가 저절로 뿌리 촉수를 건다 (%.2f초)" % t)
	_check(_boss._map_timer >= RootKeeper.MAP_INTERVAL.x - 0.1 and _boss._map_timer <= RootKeeper.MAP_INTERVAL.y, "다음 맵 패턴까지 %.1f초 (10~14)" % _boss._map_timer)
	# 씨앗 폭우 중에는 미룬다
	_hold()
	_boss.manual_control = false
	_boss.force_pattern("BARRAGE")
	_boss.manual_control = false
	_boss._map_timer = 0.0
	await _frames(3)
	_check(_tentacles().is_empty(), "씨앗 폭우 중에는 맵 패턴을 미룬다")
	_boss.manual_control = true
	await get_tree().create_timer(4.5).timeout


func _tentacles_phase2() -> void:
	var ts := await _strike_and_check(4, "2페이즈", "tentacle_p2")
	# 4줄 땅 폭 사이 빈 틈
	var fps: Array = []
	for t: RootTentacle in ts:
		if is_instance_valid(t):
			fps.append(RootKeeper.map_footprint({"x": t.global_position.x, "lean": 1 if t.rotation > 0.0 else -1, "angle": PI / 2.0 - absf(t.rotation)}))
	fps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var min_gap := INF
	for i in range(1, fps.size()):
		min_gap = minf(min_gap, fps[i].x - fps[i - 1].y)
	_check(fps.size() == 4 and min_gap >= 250.0, "2페이즈 4줄 땅 폭 사이 가장 좁은 빈 틈 %.0fpx (≥ 250)" % min_gap)
	# 많은 자리에서 늘 피할 틈이 남는가 (무작위 각·기울기 200번)
	var worst := INF
	for k in 200:
		var lay := _boss.map_layout(4, randf_range(_boss.arena.position.x, _boss.arena.end.x))
		var f2: Array = []
		for e in lay:
			f2.append(RootKeeper.map_footprint(e))
		f2.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
		for i in range(1, f2.size()):
			worst = minf(worst, f2[i].x - f2[i - 1].y)
	_check(worst >= 230.0, "무작위 200번: 4줄 사이 가장 좁은 빈 틈 %.0fpx (≥ 230)" % worst)
	var dmg: float = ts[0].damage if not ts.is_empty() and is_instance_valid(ts[0]) else -1.0
	_check(is_equal_approx(dmg, _boss.tentacle_damage * 1.25 * 1.10), "2페이즈 촉수 피해 %.2f = 24 × 1.25 × 1.10" % dmg)
	await get_tree().create_timer(1.5).timeout


# ---------- 3) 씨앗 폭우 ----------

var _barrage_p1 := {}


func _barrage(ph: int) -> void:
	_hold()
	var px := _boss.arena.get_center().x - 200.0
	_stand(px)
	_player._invuln_timer = 99999.0
	await _frames(2)
	_boss.force_pattern("BARRAGE")
	var startup := _boss.startup_len
	_check(_boss.state == RootKeeper.State.BARRAGE, "%d페이즈: 씨앗 폭우 시작 (예비 %.2f초)" % [ph, startup])
	await _until(func() -> bool: return _boss.attack_phase == "active", 2.0)
	var active := _boss.active_len
	await _frames(2)
	var waves: Array = _boss.barrage_waves
	_check(waves.size() == RootKeeper.BARRAGE_WAVES, "%d페이즈: 물결 %d개" % [ph, waves.size()])
	var gap_ok := true
	var row_ok := true
	var counts: Array = []
	for w in waves:
		var g: float = w["gap"]
		var xs: Array = w["xs"]
		counts.append(xs.size())
		for x in xs:
			gap_ok = gap_ok and absf(float(x) - g) >= RootKeeper.BARRAGE_GAP_HALF - 0.01
		# 틈을 빼면 씨앗 사이 간격이 SPACING 을 넘지 않는다 (틈 하나뿐)
		var big := 0
		for i in range(1, xs.size()):
			if float(xs[i]) - float(xs[i - 1]) > RootKeeper.BARRAGE_SPACING + 0.5:
				big += 1
		row_ok = row_ok and big <= 1
	_check(gap_ok and row_ok, "%d페이즈: 물결마다 틈 하나 (틈 안 씨앗 없음, 다른 곳 간격 ≤ %.0f) — 씨앗 %s" % [ph, RootKeeper.BARRAGE_SPACING, counts])
	if not waves.is_empty():
		var g0: float = waves[0]["gap"]
		_check(absf(g0 - px) >= RootKeeper.BARRAGE_FIRST.x - 0.5, "%d페이즈: 첫 틈은 소녀에게서 %.0fpx (제자리면 맞는다)" % [ph, absf(g0 - px)])
	var first := _seeds()
	var hover_ok := not first.is_empty()
	for s: RootSeed in first:
		hover_ok = hover_ok and is_equal_approx(s.delay, RootKeeper.BARRAGE_HOVER) and s.height() > 900.0
	_check(hover_ok, "%d페이즈: 첫 물결 씨앗 %d개가 하늘(높이 > 900)에서 %.2f초 떠서 예고" % [ph, first.size(), RootKeeper.BARRAGE_HOVER])
	var sdmg := (first[0] as RootSeed).damage if not first.is_empty() else -1.0
	_check(is_equal_approx(sdmg, _boss.seed_damage * 1.25), "%d페이즈: 씨앗 폭우 피해 %.2f = 16 × 1.25 (2페이즈 배율 없음)" % [ph, sdmg])
	if ph == 1:
		await get_tree().create_timer(0.35).timeout
		await _shot("barrage_markers")
		await get_tree().create_timer(1.25).timeout
		await _shot("barrage_fall")
	await get_tree().create_timer(2.6).timeout
	var total := 0
	for c in counts:
		total += int(c)
	if ph == 1:
		_barrage_p1 = {"startup": startup, "active": active, "total": total}
	else:
		var same: bool = is_equal_approx(startup, _barrage_p1.get("startup", -1.0)) and is_equal_approx(active, _barrage_p1.get("active", -1.0)) \
			and absi(total - int(_barrage_p1.get("total", 0))) <= RootKeeper.BARRAGE_WAVES
		_check(same, "2페이즈 씨앗 폭우 = 1페이즈 그대로 (예비 %.2f/%.2f, 길이 %.2f/%.2f, 씨앗 %d/%d)" % [startup, _barrage_p1.get("startup", -1.0), active, _barrage_p1.get("active", -1.0), total, _barrage_p1.get("total", 0)])
	await get_tree().create_timer(1.0).timeout


# ---------- 4) 싸움 중 자막 ----------

func _lines_phase1() -> void:
	_hold()
	_boss._speech.clear()
	_boss._said.erase("hp75")
	_boss.hp = _boss.max_hp * 0.76
	_boss.receive_hit(HitData.make(_boss.max_hp * 0.02, 0.0, _player), null)
	await _frames(2)
	_check(_boss._speech.current_text() == _line("hp75"), "체력 75%% 아래: '%s'" % _boss._speech.current_text())
	# 소녀가 회복하면 (healed 신호)
	_boss._speech.clear()
	_player.healed.emit()
	await _frames(2)
	_check(_boss._speech.current_text() == _line("heal", 0), "소녀 회복: '%s'" % _boss._speech.current_text())


func _to_phase2() -> void:
	_hold()
	_boss._speech.clear()
	_boss.hp = _boss.max_hp * 0.5 + 1.0
	_boss.receive_hit(HitData.make(2.0, 0.0, _player), null)
	await _frames(2)
	_check(_boss.phase == 2 and _boss.state == RootKeeper.State.RISE, "체력 절반: 무너졌다 다시 일어섬 (RISE, 페이즈 %d)" % _boss.phase)
	_check(_boss._speech.current_text() == _line("rise"), "다시 일어섬 자막: '%s'" % _boss._speech.current_text())
	_check(absf(_boss._map_timer - RootKeeper.MAP_AFTER_RISE) < 0.05, "다시 일어선 뒤 %.1f초 만에 4줄 맵 패턴" % _boss._map_timer)
	await get_tree().create_timer(0.8).timeout
	await _shot("rise_line")
	await _until(func() -> bool: return _boss.state == RootKeeper.State.STANCE, 4.0)
	_check(is_equal_approx(_boss.atk_factor(), 1.25 * 1.10), "2페이즈 공격 배율 %.4f (1.375)" % _boss.atk_factor())


func _phase2_atk() -> void:
	_hold()
	_stand(_boss.global_position.x - 500.0)
	_boss.force_pattern("SPIKES")
	await _until(func() -> bool: return _boss.attack_phase == "active", 2.0)
	await _frames(2)
	var dmg := -1.0
	for n in get_tree().get_nodes_in_group("root_effect"):
		if n is RootSpike:
			dmg = (n as RootSpike).damage
	_check(is_equal_approx(dmg, _boss.spike_damage * 1.25 * 1.10), "2페이즈 뿌리 가시 피해 %.2f = 20 × 1.25 × 1.10" % dmg)
	# 2페이즈 연계 강화: 휘두르기 뒤 연계 표 (1000번)
	var sweep2 := 0
	var spikes := 0
	for i in 1000:
		var c := _boss._pick_chain(RootKeeper.State.SWEEP, 200.0)
		if c == RootKeeper.State.SWEEP2:
			sweep2 += 1
		elif c == RootKeeper.State.SPIKES:
			spikes += 1
	_check(sweep2 > 520 and sweep2 < 680 and spikes > 180 and spikes < 320, "2페이즈 휘두르기 연계: 되돌려 베기 %d/1000 (≈600), 뿌리 가시 %d/1000 (≈250)" % [sweep2, spikes])
	await get_tree().create_timer(1.5).timeout


func _second_encounter() -> void:
	# 같은 저장에서 다시 싸우면(죽고 돌아옴 등) 싸움 전 대화가 없다
	_boss.reset_fight()
	await _frames(2)
	_boss.start_fight(_player)
	await _frames(3)
	_check(not Dialogue.is_active() and not _boss._talking, "두 번째 마주침: 싸움 전 대화 없음 (깃발 %s)" % Progress.has(RootKeeper.INTRO_FLAG))
	var w := await _until(func() -> bool: return _boss.state == RootKeeper.State.STANCE, 4.0)
	_check(_boss.state == RootKeeper.State.STANCE, "두 번째 마주침: 등장 뒤 바로 싸움 (%.2f초)" % w)
	_hold()


func _rush_lines() -> void:
	BossRush.active = true
	_boss._speech.clear()
	_boss._said.clear()
	_boss._say("hp60")
	await _frames(1)
	_check(not _boss._speech.showing() and not _boss.lines_enabled(), "보스 러시: 싸움 중 자막 없음")
	_check(not _boss._intro_talk_due(), "보스 러시: 싸움 전 대화 없음")
	BossRush.active = false

extends Node
## v1.1.0 새순(토큰) · 기술 탭 · 저장 이주 시험 (기획자 요청 15·16·17·18). 화면 없이 돈다:
##   godot --headless --path . res://tools/probe_tokens.tscn
## 창을 띄우고 돌리면(--headless 없이) 달빛풀 메뉴 스크린샷을 남긴다:
##   screenshots/debug_grass_tab_stat.png (성장 탭), debug_grass_tab_skill.png (기술 탭: 처음, 바람·빛 잠김),
##   debug_grass_tab_skill_bought.png (몇 단계 산 뒤, 영혼을 얻어 바람·빛 열림)
##  1) 표: 출처 19 = 비용 19, 단계 최대 3, skill_*_mult 표, 최대 스태미너 100/103/106/109, skills.json 글자가 표 숫자와 같다
##  2) 출처 19 — 숨은 구슬 3(방 노드 종류 token·양 1, 모으면 +1, 다시 들어와도 안 생김) · 이슬잔 3(+2) · 구원 2(+1, 한 번만) ·
##     정원사 장로(+2, 깃발로 한 번) · 보스 첫 정화 5곳(새 1 · 펌프 2 · 기사 1 · 여왕 1 · 뿌리지기 1, 한 번만) → 합 19
##  3) 보스 러시 중에는 보스 새순 0 (깃발도 안 섬)
##  4) 구매: 비용 1·1·2 (스태미너 1·1·1), 단계 상한, 모자람 거절, 바람·빛은 그 영혼을 얻어야 (잠김 거절), 19개로 모두 최대 → 0 남음
##  5) 저장 → 초기화 → 불러오기: 새순·단계·최대 스태미너 그대로
##  6) 옛 세이브(v1) 이주 4경우 + 판 2 파일은 그대로
##  7) 여왕 보상: 회상에서 돌아오면 수액 위 걷기 + 수액의 맥동, 새순 +1, 안내 / 회상 글자
##  8) 달빛풀 메뉴: 탭 셋(이동·성장·기술), 기술 탭 결정·터치 두 번 구매 → 바로 저장, 모자람·잠김 안내, 탭 머리 터치
##  9) 보스 러시 '다 자란 몸': 이슬 5 · 넘침 0 · 수액의 맥동 · 기술 다섯 줄 3단계
## 10) 이슬 최대 5, 달빛풀에서 쉬면 이슬 5개로 가득
## 마지막에 "[probe] 끝: 실패 N" 을 찍고 그 수로 종료한다. 진짜 세이브 파일은 시작 때 백업하고 끝에 되돌린다.

var _fail := 0
var _room: Node
var _player: Player
var _had_save := false
var _save_backup := ""
var _shots := 0
var _fake_hud: Node


func _ready() -> void:
	print("[probe] 새순·기술 시험 시작")
	_backup_save()
	await _run()
	await _close()
	_restore_save()
	Progress.reset()
	Music.stop(0.0)
	await _frames(2)
	print("[probe] 스크린샷 %d장" % _shots)
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _until(cond: Callable, limit: float) -> float:
	var t := 0.0
	while t < limit:
		await get_tree().process_frame
		t += get_process_delta_time()
		if cond.call():
			return t
	return -1.0


func _sleep(seconds: float) -> void:
	await _until(func(): return false, seconds)


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SaveGame.PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(SaveGame.PATH)


func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
		if f:
			f.store_string(_save_backup)
			f.close()
	elif FileAccess.file_exists(SaveGame.PATH):
		DirAccess.remove_absolute(SaveGame.PATH)


func _save_screenshot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	# HDR 2D 화면은 선형 색이라 그대로 저장하면 어둡게 보인다 → sRGB 로 바꿔 저장
	var hdr := img.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]
	img.convert(Image.FORMAT_RGBA8)
	if hdr:
		img.linear_to_srgb()
	img.save_png(ProjectSettings.globalize_path("res://screenshots/" + file_name))
	_shots += 1


func _write_save(data: Dictionary) -> void:
	var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _read_save() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.PATH))
	return d if d is Dictionary else {}


# ---------- 방 ----------
func _open(room_id: String, spawn := "") -> void:
	await _close()
	Progress.next_spawn = spawn
	_room = load("res://scenes/rooms/%s.tscn" % room_id).instantiate()
	add_child(_room)
	await _frames(6)
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player:
		_player._invuln_timer = 9999.0
	await _frames(4)


func _close() -> void:
	if _room:
		_room.queue_free()
		_room = null
		_player = null
		for i in 3:
			await get_tree().process_frame


## 줍기 안내는 get_tree().current_scene(= 이 시험 노드)의 CombatHUD 에 뜬다 → 글자만 받아 적는 가짜 안내판
func _pickup_message() -> String:
	if _fake_hud == null:
		var gs := GDScript.new()
		gs.source_code = "extends Node\nvar _message := \"\"\nfunc show_message(text: String, _seconds := 2.0) -> void:\n\t_message = text\n"
		gs.reload()
		_fake_hud = Node.new()
		_fake_hud.set_script(gs)
		_fake_hud.name = "CombatHUD"
		add_child(_fake_hud)
	return str(_fake_hud.get("_message"))


func _drop_fake_hud() -> void:
	if _fake_hud:
		_fake_hud.queue_free()
		_fake_hud = null


func _find_pickup(id: String) -> Pickup:
	for n in get_tree().get_nodes_in_group("pickup"):
		if n is Pickup and n.pickup_id == id and not n.is_queued_for_deletion():
			return n
	return null


func _rest_grass() -> MoonlightGrass:
	for g in get_tree().get_nodes_in_group("moonlight_grass"):
		if not g.decor:
			return g
	return null


# ---------- 메뉴 입력 흉내 ----------
func _fake_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	ev = InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
	await get_tree().process_frame


func _fake_touch(pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = get_viewport().get_final_transform() * pos
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = ev.position
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


# ---------- 시험 ----------
func _run() -> void:
	Progress.reset()
	_probe_tables()
	await _probe_sources()
	_probe_rush_no_tokens()
	_probe_buying()
	await _probe_save_roundtrip()
	await _probe_migration()
	await _probe_queen_reward()
	await _probe_menu()
	_probe_rush_full_body()
	await _probe_dews_rest()


## 1) 표
func _probe_tables() -> void:
	print("[probe] -- 1) 표")
	var sources := 3 * 1 + 3 * 2 + 2 * 1 + 2
	for f in Progress.BOSS_TOKENS:
		sources += int(Progress.BOSS_TOKENS[f])
	var costs := 0
	for t in Progress.TOKEN_TRACKS:
		var c: Array = Progress.TOKEN_COST[t]
		_check(c.size() == Progress.TOKEN_MAX_LEVEL, "%s 비용 단계 %d개" % [t, c.size()])
		for v in c:
			costs += int(v)
	_check(sources == 19 and costs == 19, "새순 출처 %d = 쓰는 곳 %d = 19" % [sources, costs])
	_check(Progress.TOKEN_COST["normal"] == [1, 1, 2] and Progress.TOKEN_COST["seed"] == [1, 1, 2] and Progress.TOKEN_COST["wind"] == [1, 1, 2] and Progress.TOKEN_COST["light"] == [1, 1, 2] and Progress.TOKEN_COST["stamina"] == [1, 1, 1], "비용표 1·1·2 (스태미너 1·1·1)")
	_check(Progress.BOSS_TOKENS == {"boss_bird_defeated": 1, "boss_pump_defeated": 2, "boss_knight_defeated": 1, "boss_queen_defeated": 1, "boss_root_defeated": 1}, "보스 첫 정화 새순: 새 1 · 펌프 2 · 기사 1 · 여왕 1 · 뿌리지기 1")
	# 단계별 배율 (기본 Lv0)
	Progress.upgrades = {}
	_check(is_equal_approx(Progress.skill_damage_mult("normal"), 1.0) and is_equal_approx(Progress.skill_range_mult("seed"), 1.0) and is_equal_approx(Progress.skill_cooldown_mult("wind"), 1.0) and is_equal_approx(Progress.max_stamina(), 100.0), "Lv0: 배율 1.0, 최대 스태미너 100")
	var want := {
		"normal": [[1.06, 1.05, 1.0], [1.12, 1.10, 1.0], [1.20, 1.15, 1.0]],
		"seed": [[1.10, 1.05, 1.0], [1.20, 1.10, 1.0], [1.30, 1.15, 1.0]],
		"wind": [[1.10, 1.0, 0.95], [1.20, 1.0, 0.90], [1.30, 1.0, 0.80]],
		"light": [[1.08, 1.0, 0.93], [1.16, 1.0, 0.86], [1.25, 1.0, 0.79]],
	}
	for t in want:
		var ok := true
		var got := []
		for lv in 3:
			Progress.upgrades["tok_" + t] = float(lv + 1)
			var w: Array = want[t][lv]
			var g := [Progress.skill_damage_mult(t), Progress.skill_range_mult(t), Progress.skill_cooldown_mult(t)]
			got.append(g)
			ok = ok and is_equal_approx(g[0], w[0]) and is_equal_approx(g[1], w[1]) and is_equal_approx(g[2], w[2])
		_check(ok, "%s Lv1~3 (피해, 범위, 쿨다운) %s" % [t, str(got)])
	var stam := []
	for lv in 4:
		Progress.upgrades["tok_stamina"] = float(lv)
		stam.append(Progress.max_stamina())
	_check(stam == [100.0, 103.0, 106.0, 109.0], "최대 스태미너 단계 0~3: %s" % str(stam))
	Progress.upgrades["tok_stamina"] = 7.0
	_check(is_equal_approx(Progress.max_stamina(), 109.0), "단계가 3을 넘어도 109 에서 멈춘다")
	_check(is_equal_approx(Progress.skill_damage_mult("stamina"), 1.0) and is_equal_approx(Progress.skill_cooldown_mult("normal"), 1.0), "표에 없는 줄은 1.0")
	Progress.upgrades = {}
	# skills.json 글자가 표 숫자와 같다
	var items := SkillMenu.load_skill_items()
	var tracks := []
	for it in items:
		tracks.append(SkillMenu.track_of(it))
	_check(tracks == Progress.TOKEN_TRACKS, "skills.json 줄 순서 = Progress.TOKEN_TRACKS (%s)" % str(tracks))
	for it in items:
		var t := SkillMenu.track_of(it)
		var levels: Array = it.get("levels", [])
		var ok := levels.size() == 3
		for lv in range(1, 4):
			if not ok:
				break
			var text := str(levels[lv - 1])
			if t == "stamina":
				ok = text.contains("%d" % int(Progress.STAMINA_BASE + Progress.STAMINA_PER_LEVEL * lv))
				continue
			ok = text.contains("피해 +%d%%" % roundi((float(Progress.SKILL_DAMAGE[t][lv]) - 1.0) * 100.0))
			if Progress.SKILL_RANGE.has(t):
				ok = ok and text.contains("범위 +%d%%" % roundi((float(Progress.SKILL_RANGE[t][lv]) - 1.0) * 100.0))
			if Progress.SKILL_COOLDOWN.has(t):
				ok = ok and text.contains("쿨다운 -%d%%" % roundi((1.0 - float(Progress.SKILL_COOLDOWN[t][lv])) * 100.0))
		_check(ok, "skills.json %s 글자가 표와 같다 %s" % [t, str(levels)])
	var data := SkillMenu.load_skill_data()
	_check(str(data.get("title", "")) == "기술" and str(data.get("currency", "")) == "새순" and str(data.get("locked", "")) == "아직 깃들지 않은 영혼", "skills.json 제목·재화·잠김 글자")
	var req := {}
	for it in items:
		req[SkillMenu.track_of(it)] = str(it.get("requires", ""))
	_check(req == {"normal": "", "seed": "", "wind": "wind", "light": "light", "stamina": ""}, "바람·빛만 그 영혼이 필요하다 (%s)" % str(req))


## 2) 출처 19
func _probe_sources() -> void:
	print("[probe] -- 2) 새순 출처 19")
	Progress.reset()
	var total := 0
	_pickup_message()   # 가짜 안내판
	# 숨은 구슬 3 (+1), 이슬잔 3 (+2)
	var spots := [
		["canopy_01", "pick_canopy_01_1", 1, false], ["canopy_07", "pick_canopy_07_1", 1, false], ["mine_01", "pick_mine_01_1", 1, false],
		["canopy_hidden_1", "pick_canopy_hidden_1_1", 2, true], ["village_hidden_2", "pick_village_hidden_2_1", 2, true], ["flooded_mine_hidden_1", "pick_flooded_mine_hidden_1_1", 2, true],
	]
	for sp in spots:
		var room: String = sp[0]
		var id: String = sp[1]
		var n: int = sp[2]
		var cup: bool = sp[3]
		await _open(room)
		var pk := _find_pickup(id)
		_check(pk != null and pk.kind == "token" and is_equal_approx(pk.amount, float(n)) and (pk is DewCup) == cup, "%s: %s 는 새순 %d (%s, 종류 %s, 양 %.0f)" % [room, id, n, "이슬잔" if cup else "구슬", pk.kind if pk else "-", pk.amount if pk else 0.0])
		if pk == null or _player == null:
			continue
		var before := Progress.tokens
		var dews0 := _player.max_dews
		var ups0 := Progress.upgrades.duplicate()
		pk._collect(_player)
		await _frames(2)
		total += Progress.tokens - before
		var want_msg := "이슬잔 속에 새순 %d개가 돋아 있었다" % n if cup else "새순 +%d (지금 %d)" % [n, Progress.tokens]
		_check(Progress.tokens == before + n and Progress.is_collected(id) and _player.max_dews == dews0 and Progress.upgrades == ups0, "모으면 새순 %d → %d, 모은 것으로 남고 이슬·성장 그대로" % [before, Progress.tokens])
		_check(_pickup_message() == want_msg, "안내 '%s'" % _pickup_message())
		await _sleep(1.05)   # 빛이 다 꺼진 뒤 방을 닫는다 (Pickup._collect 의 1초)
		# 다시 들어오면: 숨어 있고 닿아도 안 준다
		await _open(room)
		var again := _find_pickup(id)
		var b2 := Progress.tokens
		if again:
			again._on_body_entered(_player)
			await _frames(2)
		_check(again != null and again.collected and not again.visible and Progress.tokens == b2, "다시 들어와도 다시 생기지 않는다 (모음 %s, 보임 %s, 새순 %d)" % [again.collected if again else "-", again.visible if again else "-", Progress.tokens])
	_drop_fake_hud()
	# 구원 2 (+1, 한 번만)
	for rid in ["gardener_canopy", "fisher_lake"]:
		var r := RescuedHomes.reward_of(rid)
		_check(str(r.get("type", "")) == "token" and int(r.get("amount", 0)) == 1, "%s 보상: 새순 1 (%s)" % [rid, str(r)])
		var before := Progress.tokens
		var ups0 := Progress.upgrades.duplicate()
		Progress.rescued[rid] = true
		RescuedHomes.mark_reward_due(rid)
		var text := RescuedHomes.settle_reward(rid)
		total += Progress.tokens - before
		_check(Progress.tokens == before + 1 and Progress.has(RescuedHomes.GIVEN + rid) and Progress.upgrades == ups0, "%s 구원: 새순 +1, 받음 깃발, 성장 그대로" % rid)
		_check(text == "새순이 1개 돋았다 (지금 %d)" % Progress.tokens, "구원 안내 '%s'" % text)
		RescuedHomes.mark_reward_due(rid)
		var again := RescuedHomes.settle_reward(rid)
		_check(again == "" and Progress.tokens == before + 1, "%s 보상은 두 번 받지 않는다" % rid)
	# 정원사 장로 (+2, 깃발로 한 번)
	await _open("canopy_mini_2")
	var boss: EnemyBase = _room.get("_boss") if _room else null
	_check(boss != null and is_instance_valid(boss) and _room.reward_type == "token" and is_equal_approx(_room.reward_amount, 2.0) and _room.reward_text == "정원사 장로가 남긴 새순 — 새순 +2", "정원사 장로 방: 보상 새순 2")
	if boss != null and is_instance_valid(boss):
		for e in get_tree().get_nodes_in_group("enemy"):
			if e != boss:
				e.queue_free()
		await _frames(2)
		_player.global_position = boss.global_position + Vector2(-300, 0)
		var before := Progress.tokens
		boss.hp = 1.0
		boss.receive_hit(HitData.make(5.0, 10.0, _player), null)
		await _frames(3)
		total += Progress.tokens - before
		var hud := _room.get_node_or_null("CombatHUD")
		_check(Progress.tokens == before + 2 and Progress.has(_room.defeat_flag), "장로를 쓰러뜨리면 새순 +2 (%d → %d), 깃발" % [before, Progress.tokens])
		_check(hud != null and str(hud.get("_message")) == "정원사 장로가 남긴 새순 — 새순 +2", "장로 안내 '%s'" % (hud.get("_message") if hud else "-"))
		await _sleep(2.5)   # 빛 가루가 다 흡수되게
		var b2 := Progress.tokens
		await _open("canopy_mini_2")
		var boss2 = _room.get("_boss") if _room else null
		await _frames(2)
		_check((boss2 == null or not is_instance_valid(boss2) or boss2.is_queued_for_deletion()) and Progress.tokens == b2, "다시 들어오면 장로는 없고 새순도 그대로 (%d)" % Progress.tokens)
	# 보스 첫 정화 (한 번만)
	for f in Progress.BOSS_TOKENS:
		Progress.set_flag(f)
		var n := Progress.grant_boss_tokens(f)
		total += n
		_check(n == int(Progress.BOSS_TOKENS[f]) and Progress.has("tokens_" + f), "%s 첫 정화: 새순 %d" % [f, n])
		_check(Progress.grant_boss_tokens(f) == 0, "%s 두 번째는 0" % f)
	_check(Progress.grant_boss_tokens("miniboss_canopy_defeated") == 0 and not Progress.has("tokens_miniboss_canopy_defeated"), "표에 없는 깃발은 0, 깃발도 안 섬")
	print("[probe] 새순 출처 합: %d (지금 %d)" % [total, Progress.tokens])
	_check(total == 19 and Progress.tokens == 19, "출처 19곳을 모두 거치면 새순 19 (%d, 지금 %d)" % [total, Progress.tokens])


## 3) 보스 러시 중에는 보스 새순 없음
func _probe_rush_no_tokens() -> void:
	print("[probe] -- 3) 보스 러시")
	Progress.reset()
	var was := BossRush.active
	BossRush.active = true
	Progress.set_flag("boss_pump_defeated")
	var n := Progress.grant_boss_tokens("boss_pump_defeated")
	BossRush.active = was
	_check(n == 0 and Progress.tokens == 0 and not Progress.has("tokens_boss_pump_defeated"), "러시 중 보스 정화: 새순 0, 깃발 안 섬")
	_check(Progress.grant_boss_tokens("boss_pump_defeated") == 2, "러시가 끝난 뒤(진짜 진행)에는 받는다")
	Progress.reset()


## 4) 구매
func _probe_buying() -> void:
	print("[probe] -- 4) 구매")
	Progress.reset()
	var by := {}
	for it in SkillMenu.load_skill_items():
		by[SkillMenu.track_of(it)] = it
	_check(SkillMenu.track_can_buy(by["normal"]) == "no_tokens" and SkillMenu.track_buy(by["normal"]) == "no_tokens" and Progress.token_level("normal") == 0, "새순 0: 'no_tokens'")
	_check(SkillMenu.is_locked(by["wind"]) and SkillMenu.is_locked(by["light"]) and not SkillMenu.is_locked(by["seed"]), "영혼이 없으면 바람·빛 잠김")
	Progress.add_tokens(5)
	_check(SkillMenu.track_buy(by["wind"]) == "locked" and SkillMenu.track_buy(by["light"]) == "locked" and Progress.tokens == 5 and Progress.token_level("wind") == 0, "잠긴 줄은 'locked', 새순 그대로")
	_check(not Progress.buy_token_level("nope") and Progress.token_next_cost("nope") == -1 and Progress.tokens == 5, "없는 줄은 살 수 없다")
	Progress.reset()
	Progress.add_tokens(19)
	Progress.gain_ability("wind")
	Progress.gain_ability("light")
	_check(not SkillMenu.is_locked(by["wind"]) and not SkillMenu.is_locked(by["light"]), "영혼을 얻으면 바람·빛 열림")
	var spent := {}
	for t in Progress.TOKEN_TRACKS:
		var seq := []
		for i in 3:
			var c := Progress.token_next_cost(t)
			var before := Progress.tokens
			var r := SkillMenu.track_buy(by[t])
			seq.append(before - Progress.tokens)
			if r != "" or before - Progress.tokens != c:
				_check(false, "%s %d단계 구매 실패 (%s)" % [t, i + 1, r])
		spent[t] = seq
		_check(Progress.token_level(t) == 3 and Progress.token_next_cost(t) == -1 and SkillMenu.track_can_buy(by[t]) == "maxed", "%s 3단계까지, 다음은 'maxed' (비용 %s)" % [t, str(seq)])
	_check(spent == {"normal": [1, 1, 2], "seed": [1, 1, 2], "wind": [1, 1, 2], "light": [1, 1, 2], "stamina": [1, 1, 1]}, "쓴 새순 %s" % str(spent))
	_check(Progress.tokens == 0, "19개로 모든 기술 최대, 남은 새순 0")
	_check(is_equal_approx(Progress.skill_damage_mult("normal"), 1.20) and is_equal_approx(Progress.skill_range_mult("normal"), 1.15) and is_equal_approx(Progress.skill_cooldown_mult("wind"), 0.80) and is_equal_approx(Progress.skill_cooldown_mult("light"), 0.79) and is_equal_approx(Progress.max_stamina(), 109.0), "최대 단계 효과: 일반 ×1.20·범위 ×1.15, 바람 쿨 ×0.80, 빛 쿨 ×0.79, 스태미너 109")
	# 단계는 성장 기록(upgrades)에 실수로 남는다 (저장·보스 러시 복사)
	_check(Progress.upgrades.get("tok_normal") is float and is_equal_approx(float(Progress.upgrades["tok_stamina"]), 3.0), "단계 기록 upgrades.tok_* (%s)" % str(Progress.upgrades))
	# 모자람: 2단계 비용이 남은 새순보다 크면
	Progress.reset()
	Progress.add_tokens(1)
	_check(SkillMenu.track_buy(by["seed"]) == "" and SkillMenu.track_buy(by["seed"]) == "no_tokens" and Progress.token_level("seed") == 1, "새순 1개: 1단계만 사고 2단계는 'no_tokens'")


## 5) 저장 왕복
func _probe_save_roundtrip() -> void:
	print("[probe] -- 5) 저장 왕복")
	Progress.reset()
	await _open("canopy_01")
	Progress.add_tokens(7)
	Progress.upgrades["tok_stamina"] = 2.0
	Progress.upgrades["tok_light"] = 1.0
	SaveGame.save("", _room.scene_file_path)
	var saved := _read_save()
	_check(int(saved.get("version", 0)) == 2 and int(saved.get("tokens", -1)) == 7, "저장 파일: 판 2, 새순 7 (%s, %s)" % [saved.get("version"), saved.get("tokens")])
	Progress.reset()
	_check(Progress.tokens == 0 and Progress.token_level("stamina") == 0, "초기화 뒤 새순 0, 단계 0")
	SaveGame.load_game()
	_check(Progress.tokens == 7 and Progress.token_level("stamina") == 2 and Progress.token_level("light") == 1 and is_equal_approx(Progress.max_stamina(), 106.0), "불러온 뒤 새순 %d, 스태미너 단계 %d (최대 %.0f), 빛 단계 %d" % [Progress.tokens, Progress.token_level("stamina"), Progress.max_stamina(), Progress.token_level("light")])
	# 판 2 파일은 고치지 않는다
	_check(is_equal_approx(float(Progress.upgrades.get("dews", 0.0)), 0.0) and Progress.tokens == 7, "판 2 파일은 이주하지 않는다")


## 6) 옛 세이브 이주
func _v1_save(extra: Dictionary) -> Dictionary:
	var d := {"version": 1, "saved_at": "2026-10-20T10:00:00", "grass": "", "scene": "res://scenes/rooms/canopy_01.tscn",
		"flags": {}, "abilities": {}, "soul": "seed", "upgrades": {}, "grasses": {}, "rescued": {}, "visited_rooms": {},
		"ending": "", "purity": {}, "collected": {}, "dust": 100}
	for k in extra:
		d[k] = extra[k]
	return d


func _probe_migration() -> void:
	print("[probe] -- 6) 옛 세이브 이주")
	await _close()
	# A) 다 모은 파일 (이슬 12: 구슬 3 · 이슬잔 3 · 구원 2 · 장로 1 · 성장 3) + 보스 다섯
	var all_ids := {}
	for id in SaveMigrate.ORB_IDS + SaveMigrate.CUP_IDS:
		all_ids[id] = true
	all_ids["secret_canopy_01_1"] = true
	var flags := {"rewarded_gardener_canopy": true, "rewarded_fisher_lake": true, "miniboss_elder_gardener_defeated": true}
	for f in Progress.BOSS_TOKENS:
		flags[f] = true
	_write_save(_v1_save({"flags": flags, "abilities": {"double_jump": true, "wind": true, "sap_walk": true},
		"upgrades": {"dews": 12.0, "stat_dews_level": 3, "max_hp": 30.0}, "collected": all_ids, "rescued": {"gardener_canopy": true, "fisher_lake": true}}))
	SaveGame.load_game()
	print("[probe] A) 새순 %d, 이슬 성장 %s, 단계 %s, 빛 가루 %d, 맥동 %s" % [Progress.tokens, Progress.upgrades.get("dews"), Progress.upgrades.get("stat_dews_level"), Progress.dust, Progress.has_sap_pulse()])
	_check(Progress.tokens == 19, "A) 새순 3 + 6 + 2 + 2 + 6 = 19 (%d)" % Progress.tokens)
	_check(is_equal_approx(float(Progress.upgrades.get("dews", -1)), 2.0) and int(Progress.upgrades.get("stat_dews_level", -1)) == 2 and Progress.dew_max() == 5 and Progress.dew_overflow() == 0, "A) 이슬 성장 2 · 단계 2 → 이슬 5, 넘침 0")
	_check(Progress.dust == 100 + 280, "A) 빛 가루 100 + 280 (없어진 3단계 값) = %d" % Progress.dust)
	_check(Progress.has_sap_pulse() and Progress.has_ability("sap_walk") and is_equal_approx(float(Progress.upgrades.get("max_hp", 0)), 30.0), "A) 여왕 정화 → 수액의 맥동 (수액 위 걷기·다른 성장은 그대로)")
	var all_tok := true
	for f in Progress.BOSS_TOKENS:
		all_tok = all_tok and Progress.has("tokens_" + f) and Progress.grant_boss_tokens(f) == 0
	_check(all_tok and Progress.tokens == 19, "A) 보스 새순 깃발이 서서 다시 받지 않는다")
	var kept := Progress.collected.size() == all_ids.size()
	for id in all_ids:
		kept = kept and Progress.is_collected(id)
	_check(kept and Progress.has("rewarded_gardener_canopy") and Progress.has(SaveMigrate.MINIBOSS_FLAG), "A) 모은 기록·받은 깃발은 그대로")
	# 이주한 뒤 진짜 방에 들어가도 구슬은 다시 생기지 않는다
	await _open("canopy_01")
	var pk := _find_pickup("pick_canopy_01_1")
	_check(pk != null and pk.collected and not pk.visible, "A) 이주 뒤 canopy_01 의 새순 구슬은 이미 모은 것")
	# 저장하면 판 2 → 다시 읽어도 더 주지 않는다
	SaveGame.save("", _room.scene_file_path)
	await _close()
	SaveGame.load_game()
	_check(Progress.tokens == 19 and Progress.dust == 380 and int(_read_save().get("version", 0)) == 2, "A) 다시 저장·불러오기: 새순 19, 빛 가루 380 그대로 (판 2)")
	# B) 이슬 0 (아무것도 모으지 않은 파일)
	_write_save(_v1_save({}))
	SaveGame.load_game()
	_check(Progress.tokens == 0 and is_equal_approx(float(Progress.upgrades.get("dews", -1)), 0.0) and Progress.dew_max() == 3 and Progress.dust == 100 and not Progress.has_sap_pulse(), "B) 이슬 0: 새순 0, 이슬 3, 빛 가루 그대로, 맥동 없음")
	# C) 구원은 했지만 보상을 아직 안 받음 (reward_due 만) → 세지 않고, 말을 걸면 새 보상(새순)
	_write_save(_v1_save({"flags": {"reward_due_gardener_canopy": true, "gardener_canopy_rescued": true}, "rescued": {"gardener_canopy": true}, "upgrades": {"dews": 0.0}}))
	SaveGame.load_game()
	_check(Progress.tokens == 0 and Progress.has("reward_due_gardener_canopy"), "C) 보상 미정산: 이주로는 새순 0, 받을 보상 깃발 그대로")
	var text := RescuedHomes.settle_reward("gardener_canopy")
	_check(Progress.tokens == 1 and Progress.has("rewarded_gardener_canopy") and text.contains("새순"), "C) 말을 걸면 새순 +1 ('%s')" % text)
	# D) 성장 이슬 1단계 + 구슬 1 + 이슬잔 1 (이슬 성장 3) + 새
	_write_save(_v1_save({"collected": {"pick_mine_01_1": true, "pick_village_hidden_2_1": true}, "flags": {"boss_bird_defeated": true},
		"upgrades": {"dews": 3.0, "stat_dews_level": 1}, "abilities": {"double_jump": true, "wind": true}}))
	SaveGame.load_game()
	_check(Progress.tokens == 1 + 2 + 1 and is_equal_approx(float(Progress.upgrades.get("dews", -1)), 1.0) and int(Progress.upgrades.get("stat_dews_level", -1)) == 1 and Progress.dew_max() == 4 and Progress.dust == 100, "D) 성장 이슬 1단계: 이슬 4, 새순 구슬 1 + 잔 2 + 새 1 = %d, 빛 가루 그대로 %d" % [Progress.tokens, Progress.dust])
	_check(not Progress.has_sap_pulse() and Progress.has("tokens_boss_bird_defeated"), "D) 여왕을 안 만났으면 맥동 없음, 새 새순 깃발")
	# E) 판 2 파일은 손대지 않는다 (이슬 상한은 dew_max 가 자른다)
	_write_save(_v1_save({"version": 2, "tokens": 4, "upgrades": {"dews": 9.0}, "collected": {"pick_canopy_01_1": true}, "flags": {"boss_queen_defeated": true}}))
	SaveGame.load_game()
	_check(Progress.tokens == 4 and is_equal_approx(float(Progress.upgrades.get("dews", 0)), 9.0) and Progress.dew_max() == 5 and not Progress.has_sap_pulse(), "E) 판 2: 그대로 (새순 4, 이슬 기록 9 → 이슬 5)")
	# 판 표시가 없는 아주 옛 파일 = 판 1
	var d := _v1_save({"collected": {"pick_canopy_07_1": true}})
	d.erase("version")
	_write_save(d)
	SaveGame.load_game()
	_check(Progress.tokens == 1, "판 표시 없는 파일도 판 1 로 보고 이주 (새순 %d)" % Progress.tokens)
	Progress.reset()


## 7) 여왕 보상
func _probe_queen_reward() -> void:
	print("[probe] -- 7) 여왕 보상")
	var scene: Node = load("res://scenes/rooms/sap_lake_boss.tscn").instantiate()
	var ab: Array = scene.get("abilities")
	var msg := str(scene.get("reward_message"))
	scene.free()
	_check(ab.has("sap_walk") and ab.has("sap_pulse"), "여왕 방 abilities %s (수액 위 걷기 + 수액의 맥동)" % str(ab))
	_check(msg.contains("수액의 맥동") and msg.contains("수액 위"), "여왕 보상 글자 '%s'" % msg)
	var mem: Dictionary = DialogueData.load_dialogue("res://data/dialogue/memories.json").get("memory_queen", {})
	_check(str(mem.get("reward_text", "")).contains("수액의 맥동"), "회상 끝 글자 '%s'" % mem.get("reward_text", ""))
	# 회상에서 돌아온 것처럼: 깃발만 서 있고 after_ 깃발 없음 → 방이 영혼을 깃들게 한다
	Progress.reset()
	Progress.set_flag("boss_queen_defeated")
	await _open("sap_lake_boss")
	var took := await _until(func(): return Progress.has_sap_pulse() and Progress.tokens > 0, 6.0)
	await _frames(2)
	var hud := _room.get_node_or_null("CombatHUD") if _room else null
	var text := str(hud.get("_message")) if hud else ""
	print("[probe] 여왕 보상 (%.2f초): 능력 %s, 새순 %d, 안내 '%s'" % [took, str(Progress.abilities.keys()), Progress.tokens, text])
	_check(took >= 0.0 and Progress.has_ability("sap_walk") and Progress.has_sap_pulse() and Progress.tokens == 1 and Progress.has("tokens_boss_queen_defeated"), "회상 뒤: 수액 위 걷기 + 수액의 맥동, 새순 +1")
	_check(text.contains("수액의 맥동") and text.ends_with("·  새순 +1"), "보상 안내에 맥동과 새순 +1 ('%s')" % text)
	await _sleep(3.8)   # 입력 잠금이 풀리게 (BossRoom._after_memory 끝)
	Progress.reset()


## 8) 달빛풀 메뉴 (탭 셋 · 기술 탭)
func _probe_menu() -> void:
	print("[probe] -- 8) 달빛풀 메뉴")
	Progress.reset()
	await _open("canopy_01")
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	var grass := _rest_grass()
	_check(grass != null and _player != null, "첫 방에 달빛풀·소녀")
	if grass == null or _player == null:
		return
	grass._register()
	Progress.grasses["probe_other"] = {"scene": "res://scenes/rooms/canopy_02.tscn", "name": "수관 · 시험용 다른 달빛풀"}
	Progress.dust = 300
	_player.global_position = grass.global_position + Vector2(50, -40)
	_player.velocity = Vector2.ZERO
	_player.start_rest(grass)
	await _frames(3)
	grass._open_menu()
	await get_tree().process_frame
	var menu: GrassMenu = grass.menu()
	_check(menu != null and menu.is_open() and menu.tab_count() == 3 and menu.tab() == 0, "탭 셋, 이동 탭으로 열림 (%d개)" % (menu.tab_count() if menu else 0))
	if menu == null:
		return
	_check(menu._labels == ["뿌리를 따라 이동", "성장", "기술"], "탭 이름 %s" % str(menu._labels))
	await _fake_action("move_right")
	_check(menu.tab() == 1 and menu.stat_panel().visible and not menu.skill_panel().visible, "오른쪽 → 성장 탭")
	await _save_screenshot("debug_grass_tab_stat.png")
	await _fake_action("move_right")
	var skill := menu.skill_panel()
	_check(menu.tab() == 2 and skill.visible and not menu.stat_panel().visible, "한 번 더 → 기술 탭")
	await _fake_action("move_right")
	_check(menu.tab() == 2, "끝에서 더 오른쪽 → 그대로 기술 탭")
	_check(skill.items.size() == 5, "기술 줄 5개 (%d)" % skill.items.size())
	# 새순 0: 일반 공격 결정 → 모자람
	skill.index = 0
	await _fake_action("jump")
	_check(Progress.token_level("normal") == 0 and skill._msg == "새순이 모자라다" and skill._shake > 0.0, "새순 0 → 거절 '%s'" % skill._msg)
	await _sleep(0.4)
	await _save_screenshot("debug_grass_tab_skill.png")
	# 새순 6: 일반 공격 결정 → 1단계, 바로 저장
	Progress.add_tokens(6)
	await _fake_action("interact")
	var saved := _read_save()
	_check(Progress.token_level("normal") == 1 and Progress.tokens == 5 and skill._flash > 0.0, "결정 → 일반 공격 1단계, 새순 6 → %d ('%s')" % [Progress.tokens, skill._msg])
	_check(skill._msg == "일반 공격 1단계 — 피해 +6% · 범위 +5%  (새순 1)", "구매 안내 '%s'" % skill._msg)
	_check(int(saved.get("tokens", -1)) == 5 and is_equal_approx(float(saved.get("upgrades", {}).get("tok_normal", 0)), 1.0), "사면 바로 저장된다 (저장 파일 새순 %s, 단계 %s)" % [saved.get("tokens"), saved.get("upgrades", {}).get("tok_normal")])
	# 바람 줄 (잠김)
	await _fake_action("move_down")
	await _fake_action("move_down")
	_check(skill.index == 2, "아래 둘 → 바람 줄 (%d)" % skill.index)
	await _fake_action("jump")
	_check(Progress.token_level("wind") == 0 and Progress.tokens == 5 and skill._msg == "아직 깃들지 않은 영혼", "바람 영혼이 없으면 '%s'" % skill._msg)
	# 터치: 스태미너 줄 첫 누르기 = 고르기, 두 번째 = 구매
	var rc := skill.row_rect(4)
	await _fake_touch(rc.get_center())
	_check(skill.index == 4 and Progress.token_level("stamina") == 0 and skill._msg == "한 번 더 누르면 다듬기", "터치 첫 누르기: 스태미너 줄 고르기만 ('%s')" % skill._msg)
	await _fake_touch(rc.get_center())
	_check(Progress.token_level("stamina") == 1 and is_equal_approx(Progress.max_stamina(), 103.0) and Progress.tokens == 4, "두 번째 누르기: 최대 스태미너 103, 새순 4")
	# 영혼을 얻으면 바람이 열린다 → 사고 스크린샷
	Progress.gain_ability("wind")
	Progress.gain_ability("light")
	skill.index = 2
	await _fake_action("jump")
	_check(Progress.token_level("wind") == 1 and Progress.tokens == 3, "바람 영혼을 얻으면 산다 (단계 %d)" % Progress.token_level("wind"))
	skill.index = 1
	await _fake_action("jump")
	await _fake_action("jump")
	_check(Progress.token_level("seed") == 2 and Progress.tokens == 1, "씨앗 2단계 (새순 %d)" % Progress.tokens)
	await _sleep(0.3)
	await _save_screenshot("debug_grass_tab_skill_bought.png")
	# 탭 머리 터치 → 성장 탭, 이슬 줄 '가득' 표시가 보이도록 이슬 2단계를 채워 둔다
	await _fake_touch(menu._tab_rect(1).get_center())
	_check(menu.tab() == 1 and menu.stat_panel().visible and not skill.visible, "탭 머리(성장) 터치 → 성장 탭")
	await _fake_touch(menu._tab_rect(2).get_center())
	_check(menu.tab() == 2 and skill.visible, "탭 머리(기술) 터치 → 기술 탭")
	await _fake_action("soul_prev")
	_check(menu.tab() == 1, "◁ (영혼 전환) → 성장 탭")
	await _fake_action("dodge")
	await _frames(4)
	_check(not menu.is_open() and not get_tree().paused and not skill.visible and _player.state == Player.State.REST, "회피 → 닫히고 쉬기 계속")
	Progress.grasses.erase("probe_other")
	_player._set_state(Player.State.IDLE)
	await _frames(2)
	Progress.reset()


## 9) 보스 러시 '다 자란 몸'
func _probe_rush_full_body() -> void:
	print("[probe] -- 9) 보스 러시 다 자란 몸")
	if FileAccess.file_exists(SaveGame.PATH):
		DirAccess.remove_absolute(SaveGame.PATH)
	var g := BossRush.growth_from_save()
	_check(g["source"] == "full", "저장 파일이 없으면 다 자란 몸")
	Progress.reset()
	Progress.upgrades = g["upgrades"]
	Progress.abilities = g["abilities"]
	var lv := []
	for t in Progress.TOKEN_TRACKS:
		lv.append(Progress.token_level(t))
	_check(Progress.dew_max() == 5 and Progress.dew_overflow() == 0 and is_equal_approx(Progress.heal_bonus(), 50.0), "이슬 5, 넘침 0, 회복량 성장 50 (%d, %d, %.0f)" % [Progress.dew_max(), Progress.dew_overflow(), Progress.heal_bonus()])
	_check(lv == [3, 3, 3, 3, 3] and is_equal_approx(Progress.max_stamina(), 109.0), "기술 다섯 줄 모두 3단계 %s, 스태미너 109" % str(lv))
	_check(Progress.has_sap_pulse() and Progress.has_ability("sap_walk") and Progress.has_ability("wind") and Progress.has_ability("light"), "수액의 맥동·수액 위 걷기·바람·빛")
	_check(is_equal_approx(float(Progress.upgrades.get("max_hp", 0)), 120.0) and is_equal_approx(float(Progress.upgrades.get("attack", 0)), 0.4), "체력 +120 · 공격 +40% 는 그대로")
	Progress.reset()


## 10) 이슬 최대 5 · 쉬면 가득
func _probe_dews_rest() -> void:
	print("[probe] -- 10) 이슬 5 · 달빛풀")
	Progress.reset()
	_check(Progress.MAX_DEWS == 5, "이슬 최대 5")
	Progress.upgrades = {"dews": 2.0}
	await _open("canopy_01")
	var grass := _rest_grass()
	if _player == null or grass == null:
		_check(false, "소녀·달빛풀")
		return
	_check(_player.max_dews == 5, "성장 2 → 이슬 5 (%d)" % _player.max_dews)
	_player.dews = 0
	_player.hp = 5.0
	_player.global_position = grass.global_position + Vector2(50, -40)
	_player.start_rest(grass)
	await _frames(3)
	_check(_player.dews == 5 and is_equal_approx(_player.hp, _player.max_hp), "달빛풀에서 쉬면 이슬 5/5, 체력 가득 (%d, %.0f)" % [_player.dews, _player.hp])
	Progress.upgrades = {"dews": 9.0}
	_player._apply_abilities()
	_check(_player.max_dews == 5, "성장 기록이 커도 이슬은 5 를 넘지 않는다 (%d)" % _player.max_dews)
	_player._set_state(Player.State.IDLE)
	Progress.reset()

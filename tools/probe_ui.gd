extends Node
## 플레이어·터치 UI 묶음 시험 (2026-10-19 기획자 요청 4·8·11·12번 + 빛 가루 표시). 화면 없이 돈다.
## 실행: godot --headless --path . res://tools/probe_ui.tscn
##       godot --path . res://tools/probe_ui.tscn   → 창이 잠깐 뜨고 screenshots/debug_touch_ui.png 를 남긴다 (터치 버튼·HUD 눈 확인용)
## 첫 방(canopy_01)을 띄우고 터치 장치로 친 뒤
##  - 터치 버튼 표에 '공격'·'낙하'가 있고 '약공격'이 없다, 영혼 버튼 글자 = 고른 영혼 이름(씨앗 → 바람)
##  - 쿨다운 글자 7 → 1, 쿨다운 중 영혼 버튼 꺼짐
##  - 버튼 겹침 없음: 1920×1080 / 2338×1080 / 1920×1440 × 버튼 크기 설정 3단계 (중심 거리 ≥ (r1+r2)×1.2)
##  - 노치: 세로 가운데 띠에 걸치는 버튼은 가장자리에서 86px 이상 (검토 지적 2026-10-19), 회피는 모서리에서 예전(389px)보다 멀지 않다
##  - 보스 등장 이름이 떠 있으면 전환 알림이 그 위로 / 장면 전환(불러오기) 중엔 빛 가루 '+N' 이 안 뜬다
##  - 낙하 버튼: 땅에서 꺼짐·무시, 공중에서 켜짐·누르면 낙하 공격
##  - 영혼 전환 알림(큰 글자·설명·투명도) / HUD 영혼 줄 '지금: …' / 빛 가루 숫자·"+N" 떠오름
##  - 터치 안내 글자 '공격'·'낙하', 입력 확인 화면 표, 키 바꾸기 화면 줄 수가 화면에 든다
## 마지막 줄 "[probe] 끝: 실패 N".

var _fail := 0
var _room: Node
var _player: Player
var _touch: CanvasLayer
var _hud: CanvasLayer


func _ready() -> void:
	print("[probe] 시작: 플레이어·터치 UI")
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


func _teleport(pos: Vector2) -> void:
	_player.global_position = pos
	_player.velocity = Vector2.ZERO
	_player._plunge_lock = 0.0
	_player._plunge_buffered = false
	_player._plunge_btn_buffered = false
	_player._set_state(Player.State.IDLE)


func _run() -> void:
	Progress.reset()
	_room = load("res://scenes/rooms/canopy_01.tscn").instantiate()
	add_child(_room)
	await _frames(12)
	_player = get_tree().get_first_node_in_group("player") as Player
	_touch = _room.get_node_or_null("TouchControls")
	_hud = _room.get_node_or_null("CombatHUD")
	_check(_player != null and _touch != null and _hud != null, "첫 방에 소녀·터치 조작·HUD 가 있다")
	if _player == null or _touch == null or _hud == null:
		return
	var n := 0
	while (_hud._player == null or _touch._player == null) and n < 60:
		await get_tree().process_frame
		n += 1
	_player._invuln_timer = 9999.0
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()   # 적이 끼어들지 않게
	await _frames(2)
	InputDevice._set_device(InputDevice.Kind.TOUCH, -1)
	await get_tree().process_frame
	_check(InputDevice.current == InputDevice.Kind.TOUCH and _touch._shown and _touch._canvas.visible, "터치 장치로 치면 터치 버튼이 보인다")

	await _test_button_names()
	await _test_soul_button_and_notice()
	await _test_overlap()
	await _test_plunge_button()
	await _test_dust()
	await _test_texts_and_screens()
	await _screenshot_if_window()


# ---------- (8) 버튼 이름 ----------
func _test_button_names() -> void:
	var b: Dictionary = _touch._buttons()
	var texts := []
	for k in b:
		texts.append(b[k]["text"])
	print("[probe] 터치 버튼: %s" % [texts])
	_check(b.has("attack_light") and b["attack_light"]["text"] == "공격" and b["attack_light"]["action"] == "attack_light", "공격 버튼 글자 '공격' (동작 attack_light 그대로)")
	_check(b.has("plunge") and b["plunge"]["text"] == "낙하" and b["plunge"]["action"] == "plunge" and is_equal_approx(b["plunge"]["r"], 60.0 * Settings.touch_scale_factor()), "낙하 버튼 '낙하' (동작 plunge, 반지름 60)")
	var has_old := false
	for t in texts:
		if "약공격" in str(t):
			has_old = true
	_check(not has_old, "'약공격' 글자는 어디에도 없다")
	_check(b["soul"]["text"] == "씨앗" and _touch.soul_button_text() == "씨앗", "영혼 버튼 글자 = 고른 영혼 이름 '씨앗' (%s)" % b["soul"]["text"])
	var jump: Vector2 = b["jump"]["pos"]
	var plunge: Vector2 = b["plunge"]["pos"]
	var dodge: Vector2 = b["dodge_r"]["pos"]
	var br: Vector2 = _touch._canvas.size
	var k := Settings.touch_scale_factor()
	var dodge_far := dodge.distance_to(br) / k
	_check(dodge.y < jump.y and absf(dodge.x - jump.x) < 60.0 and dodge_far <= 389.0, "회피는 점프 바로 위, 모서리에서 %.0fpx (예전 389px 보다 멀지 않다)" % dodge_far)
	_check(plunge.y < dodge.y and plunge.distance_to(jump) / k < 360.0, "낙하는 회피 위 바깥 호 (점프에서 %.0fpx; 점프 %s, 회피 %s, 낙하 %s)" % [plunge.distance_to(jump) / k, jump, dodge, plunge])
	_check(_touch.ALL_ACTIONS.has("plunge"), "숨길 때 떼는 동작 목록에 plunge")


# ---------- (12, 4) 영혼 버튼·전환 알림·쿨다운 ----------
func _test_soul_button_and_notice() -> void:
	Progress.gain_ability("wind")
	Progress.gain_ability("light")
	_player._apply_abilities()
	await _frames(2)
	_check(_player.next_soul() == "wind", "씨앗 다음 영혼은 바람 (%s)" % _player.next_soul())
	_teleport(Vector2(400, 2132))
	await _frames(3)
	await _tap("soul_next")
	await _frames(1)
	_check(_player.soul == "wind" and _touch._buttons()["soul"]["text"] == "바람", "전환하면 영혼 버튼 글자가 '바람' (%s)" % _touch._buttons()["soul"]["text"])
	_check(_player.next_soul() == "light" and _player.soul_color("light").is_equal_approx(Color(1.0, 0.9, 0.7)), "전환 버튼이 띨 다음 영혼은 빛(금빛)")
	_check(_hud._soul_notice_timer > 1.0 and _hud.soul_notice_title() == "바람의 영혼", "전환 순간 알림 1.2초 시작: '%s'" % _hud.soul_notice_title())
	_check("쿨 5초" in _hud.soul_notice_desc(), "알림 설명에 쿨다운: '%s'" % _hud.soul_notice_desc())
	var a0: float = _hud.soul_notice_alpha()
	await _frames(14)   # 0.23초
	var a1: float = _hud.soul_notice_alpha()
	print("[probe] 알림 투명도: 직후 %.2f → 0.23초 %.2f" % [a0, a1])
	_check(a0 < 0.3 and a1 > 0.9, "알림은 떠오르며 나타난다 (처음 흐리고 0.15초 뒤 또렷)")
	_check(_hud.soul_label() == "지금: 바람 (잿빛 잎새의 새)", "HUD 영혼 줄 '%s'" % _hud.soul_label())
	_check(not ("꿰뚫" in _player.soul_desc("light")), "빛 설명에 '꿰뚫는다' 가 없다: '%s'" % _player.soul_desc("light"))
	var y_normal: float = _hud.soul_notice_y_ratio()
	var fake_boss: Node = load("res://scenes/ui/boss_hud.tscn").instantiate()
	fake_boss.name = "BossHUD"
	_room.add_child(fake_boss)
	await get_tree().process_frame
	fake_boss.set("_title", 2.0)   # 보스 등장 이름이 떠 있는 동안
	var y_boss: float = _hud.soul_notice_y_ratio()
	fake_boss.set("_title", 0.0)
	var y_after: float = _hud.soul_notice_y_ratio()
	fake_boss.queue_free()
	print("[probe] 전환 알림 높이: 보통 %.3f / 보스 이름 떠 있음 %.3f / 사라진 뒤 %.3f" % [y_normal, y_boss, y_after])
	_check(is_equal_approx(y_normal, 0.17) and y_boss < 0.13 and is_equal_approx(y_after, 0.17), "보스 등장 이름(높이 0.22)이 떠 있으면 알림이 그 위로 올라간다")
	await get_tree().create_timer(1.2).timeout
	_check(_hud._soul_notice_timer <= 0.0 and _hud.soul_notice_title() == "" and _hud.soul_notice_alpha() == 0.0, "1.2초 뒤 알림이 사라진다")
	# 쿨다운 글자·버튼 꺼짐
	var texts := []
	var enabled := []
	for v in [7.0, 6.0, 5.0, 4.0, 3.0, 2.0, 1.0, 0.0]:
		_player._soul_cooldown = v
		texts.append(_player.soul_cooldown_text())
		enabled.append(_touch.button_enabled("soul"))
	print("[probe] 쿨다운 7→0 글자 %s, 영혼 버튼 켜짐 %s" % [texts, enabled])
	_check(texts == ["7", "6", "5", "4", "3", "2", "1", ""], "쿨다운 글자 7 → 1, 끝나면 빈 글자")
	_check(enabled == [false, false, false, false, false, false, false, true], "쿨다운 중엔 영혼 버튼이 꺼지고 0 이면 켜진다")
	_player._soul_cooldown = 2.5
	_check(is_equal_approx(_player.soul_cooldown_ratio(), 0.5) and _player.soul_cooldown_text() == "3", "바람(쿨 5초) 2.5초 남음 → 비율 0.5, 글자 3")
	_player._soul_cooldown = 0.0
	# 실제로 쏘면 쿨다운이 걸린다 (바람 5초)
	await _tap("soul_ability")
	await get_tree().physics_frame
	_check(_player.soul_cooldown_left() > 4.9 and _touch._buttons()["soul"]["text"] == "바람", "바람을 쏘면 5초 쿨다운, 버튼 글자는 그대로 '바람'")
	_player._soul_cooldown = 0.0
	await _frames(90)


# ---------- 겹침: 세 비율 × 버튼 크기 3단계 ----------
func _test_overlap() -> void:
	var saved = Settings.data.get("touch_scale", 1)
	var sizes := [Vector2(1920, 1080), Vector2(2338, 1080), Vector2(1920, 1440)]
	var all_ok := true
	var notch_ok := true
	for sc in [0, 1, 2]:
		Settings.data["touch_scale"] = sc   # (파일에 저장하지 않고 값만)
		for sz in sizes:
			var bad: Array = _touch.overlapping_pairs(sz, 1)
			var b: Dictionary = _touch._buttons(sz, 1)
			var min_gap := INF
			var min_pair := ""
			var names := b.keys()
			for i in names.size():
				for j in range(i + 1, names.size()):
					var d: float = b[names[i]]["pos"].distance_to(b[names[j]]["pos"])
					var need: float = (b[names[i]]["r"] + b[names[j]]["r"]) * _touch.GAP_RATIO
					if d / need < min_gap:
						min_gap = d / need
						min_pair = "%s-%s" % [names[i], names[j]]
			var inside := true
			for k in names:
				var p: Vector2 = b[k]["pos"]
				var r: float = b[k]["r"]
				if p.x - r < 0.0 or p.y - r < 0.0 or p.x + r > sz.x or p.y + r > sz.y:
					inside = false
			var notch: Array = _touch.notch_hits(sz, 1)
			print("[probe] %s 크기 %.2f: 버튼 %d개, 겹침 %s, 가장 빠듯한 쌍 %s (거리/필요 %.2f), 화면 안 %s, 노치에 걸림 %s" % [sz, Settings.touch_scale_factor(), b.size(), bad, min_pair, min_gap, inside, notch])
			if not bad.is_empty() or not inside:
				all_ok = false
			if not notch.is_empty():
				notch_ok = false
	Settings.data["touch_scale"] = saved
	_check(all_ok, "세 비율 × 세 크기에서 버튼이 겹치지 않고 화면 안에 든다 (상황 버튼 포함)")
	_check(notch_ok, "세 비율 × 세 크기에서 세로 가운데 띠의 버튼이 가장자리에서 %.0fpx 이상 (아이폰 노치)" % _touch.NOTCH_DEPTH)


# ---------- (11) 낙하 버튼 ----------
func _test_plunge_button() -> void:
	_teleport(Vector2(400, 2200 - 67 - 1))
	await _frames(4)
	_check(_player.is_on_floor() and not _touch.button_enabled("plunge"), "땅에서는 낙하 버튼이 꺼져 있다")
	var starts := {"n": 0}
	var cb := func(): starts["n"] += 1
	_player.plunge_started.connect(cb)
	var pos: Vector2 = _touch._buttons()["plunge"]["pos"]
	_touch._begin_touch(0, pos)
	await _frames(2)
	_touch._end_touch(0)
	await _frames(3)
	_check(starts["n"] == 0 and _player.state in Player.LOCOMOTION, "땅에서 낙하 버튼을 눌러도 아무 일 없다 (%s)" % _player.state_name())
	_teleport(Vector2(400, 2200 - 67 - 360))
	await _frames(3)
	_check(not _player.is_on_floor() and _touch.button_enabled("plunge"), "공중에서는 낙하 버튼이 켜진다")
	_touch._begin_touch(0, pos)
	await _frames(2)
	var st := _player.state_name()
	_touch._end_touch(0)
	_check(st == "낙하 공격" and starts["n"] == 1 and not Input.is_action_pressed("plunge"), "공중에서 낙하 버튼을 누르면 낙하 공격 (%s), 떼면 동작도 풀린다" % st)
	_player.plunge_started.disconnect(cb)
	await _frames(60)
	_check(_player.is_on_floor() and _player.state in Player.LOCOMOTION, "착지 뒤 대기 (%s)" % _player.state_name())


# ---------- 빛 가루 HUD ----------
func _test_dust() -> void:
	_check(_hud.dust_text() == str(Progress.dust) and Progress.dust == 0, "빛 가루 글자 = Progress.dust (%s)" % _hud.dust_text())
	var o: Vector2 = _hud.dust_origin()
	_check(o.x >= _hud.growth_end_x() + _hud.DUST_GAP and absf(o.y - _hud.growth_origin().y) < 0.5, "빛 가루 아이콘은 이슬 줄 오른쪽(성장 표시 뒤), 이슬 세로 가운데 (%s)" % o)
	Progress.add_dust(12)
	await get_tree().process_frame
	_check(_hud.dust_text() == "12" and _hud._dust_pops.size() == 1 and int(_hud._dust_pops[0]["amount"]) == 12 and _hud._dust_glow > 0.9, "+12 → 글자 '12', '+12' 떠오름 시작, 아이콘 밝아짐")
	Progress.add_dust(3)
	await get_tree().process_frame
	_check(_hud.dust_text() == "15" and _hud._dust_pops.size() == 2, "연달아 +3 → '15', 떠오르는 글자 둘")
	Progress.spend_dust(5)
	await get_tree().process_frame
	_check(_hud.dust_text() == "10" and _hud._dust_pops.size() == 2, "쓰면(−5) 글자만 줄고 떠오르는 글자는 안 생긴다")
	await get_tree().create_timer(1.3).timeout
	_check(_hud._dust_pops.is_empty(), "1.1초 뒤 떠오른 글자가 사라진다")
	Progress.add_upgrade("attack", 0.1)
	_player._apply_abilities()
	await get_tree().process_frame
	_check(_hud.dust_origin().x > o.x + 20.0, "성장 표시가 생기면 빛 가루가 그 오른쪽으로 밀린다 (%.1f → %.1f)" % [o.x, _hud.dust_origin().x])
	# 메뉴의 '불러오기': SaveGame 이 dust 를 넣고 dust_changed 를 낸 뒤 같은 호출에서 Game.go_to 로 전환을 시작한다 → '+N' 은 안 뜬다
	Game._busy = true   # (go_to 가 하는 것처럼; 진짜 전환은 이 시험 장면을 지우므로 깃발만)
	Progress.dust = 50
	Progress.dust_changed.emit(50)
	await get_tree().process_frame
	var pops_while_loading: int = _hud._dust_pops.size()
	Game._busy = false
	_check(pops_while_loading == 0 and _hud.dust_text() == "50", "장면 전환 중(불러오기) 빛 가루가 바뀌면 숫자만 바뀌고 '+N' 은 안 뜬다 (떠오름 %d)" % pops_while_loading)
	Progress.add_dust(5)
	await get_tree().process_frame
	_check(_hud._dust_pops.size() == 1, "전환이 끝난 뒤 번 빛 가루는 다시 '+N' 이 뜬다")
	await get_tree().create_timer(1.2).timeout


# ---------- 안내 글자·입력 확인 화면·키 바꾸기 화면 ----------
func _test_texts_and_screens() -> void:
	_check(InputDevice.prompt("attack_light") == "공격" and InputDevice.prompt("plunge") == "낙하", "터치 안내 글자: 공격 / 낙하 (%s / %s)" % [InputDevice.prompt("attack_light"), InputDevice.prompt("plunge")])
	var table: Array = load("res://scripts/debug/input_test.gd").ACTIONS
	var atk := ""
	var has_plunge := false
	var old := false
	for row in table:
		if row[0] == "attack_light":
			atk = row[1]
		if row[0] == "plunge":
			has_plunge = true
		if "약공격" in str(row[1]):
			old = true
	_check(atk.begins_with("공격") and has_plunge and not old, "입력 확인 화면 표: '%s', plunge 줄 %s, 약공격 없음" % [atk, has_plunge])
	var rs := RemapScreen.new()
	add_child(rs)
	await get_tree().process_frame
	var last: Rect2 = rs._row_rect(Keymap.ACTIONS.size() + 1)
	print("[probe] 키 바꾸기 화면 줄 %d, 마지막 줄 끝 y %.0f" % [Keymap.ACTIONS.size() + 2, last.end.y])
	_check(last.end.y <= 1060.0, "키 바꾸기 화면의 줄이 1080 안에 든다")
	_check(Keymap.label_for("plunge", "kb") == "-" and Keymap.label_for("plunge", "ds") == "-", "plunge 는 기본 배치가 없어 '-' 로 보인다")
	rs.queue_free()


# ---------- 창이 있으면 스크린샷 (기획자·Claude 눈 확인용) ----------
func _screenshot_if_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	# 보기 좋은 상태: 바람 영혼, 쿨다운 3.2초 남음, 빛 가루 37, 전환 알림, 공중(낙하 버튼 켜짐)
	Progress.add_dust(22)
	_player.soul = "wind"
	Progress.soul = "wind"
	_player._soul_cooldown = 3.2
	_player.soul_changed.emit("wind")
	_teleport(Vector2(700, 2200 - 67 - 330))
	_player.velocity.y = -200.0
	await get_tree().create_timer(0.3).timeout
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(ProjectSettings.globalize_path("res://screenshots/debug_touch_ui.png"))
		print("[probe] 스크린샷 screenshots/debug_touch_ui.png (소녀 상태 %s, 영혼 %s, 쿨 %.1f, 빛 가루 %d)" % [_player.state_name(), _player.soul, _player.soul_cooldown_left(), Progress.dust])

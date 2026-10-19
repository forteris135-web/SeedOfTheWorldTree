extends CanvasLayer
## 터치 조작 (기획서 8장 "터치 조작").
## - 왼쪽 화면 어디든 누르면 그 자리에 스틱.
## - 오른쪽 엄지: 싸움 버튼 여섯 개. 아래 모서리를 축으로 안쪽 호에 점프(가장 가까움)·공격(가장 큼)·회피(점프 바로 위, 예전 자리에서 30px 아래),
##   바깥 호에 **낙하**(회피 위, 공중에서만 켜짐)·가드(공격 왼쪽, 저스트 가드를 같은 엄지로)·영혼 기술(공격 위, 옛 강공격 자리).
##   (2026-10-19 검토: 처음엔 낙하를 점프 바로 위에 두고 회피를 바깥으로 밀었는데, 가장 급한 방어 버튼이 모서리에서 512px 로 멀어지고
##    낙하가 오른쪽 가장자리 65px 까지 붙어 아이폰 노치에 걸릴 수 있어서 둘을 맞바꿨다. 회피는 모서리에서 365px — 예전 389px 보다 가깝다.)
##   낙하 공격은 '낙하' 버튼(동작 plunge) 또는 스틱을 절반 넘게 아래로 내린 채 공격, 하단 점프는 스틱 절반 넘게 아래 + 점프
##   (살짝 처진 엄지로는 안 걸린다 — player.gd DOWN_HOLD_STRENGTH 0.5).
## - 영혼 버튼은 '영혼' 대신 **지금 고른 영혼 이름**(씨앗/바람/빛)과 그 영혼 색 테두리. 쿨다운 중엔 어두워지고 남은 초("7, 6, … 1")와
##   테두리를 시계 방향으로 차오르는 호(지난 비율; 남은 비율은 어두운 호)가 보인다. '전환' 버튼은 다음 영혼의 색을 띤다.
## - 왼쪽 가장자리 세로 줄: 회복 / 전환 (급하지 않은 버튼). 걷기 고정은 L3·키보드만 (터치 버튼은 없앴다).
## - 상황 버튼(손길): 상호작용이 가능할 때만 나타난다. 달빛풀에서 쉬는 중엔 '이동', 포탈 앞에선 '들어가기'.
## - 위 모서리: 왼쪽 '메뉴'(Esc), 오른쪽 '지도'. 이 둘은 방이 입력 이벤트로 받으므로 InputEventAction 을 함께 보낸다.
## - 밝은 배경에서도 보이게: 어두운 반투명 바탕 + 흰 테두리 + 테두리 있는 글자.
## - 컨트롤러나 키보드 입력이 들어오면 숨고, 화면을 만지면 다시 나타난다.
## - 멈춤(지도·메뉴) 중에도 손가락 떼기는 받아서 버튼이 눌린 채 남지 않게 한다.
## - 시험·스크린샷용: 실행 인수 `--touch` 가 있으면 처음부터 터치 장치로 쳐서 버튼을 보인다.
## 겹침 검사(tools/probe_ui.gd): 모든 버튼 쌍의 중심 거리 ≥ (r1 + r2) × 1.2, 1920×1080 / 2338×1080 / 1920×1440 세 비율.
## 노치 검사(같은 시험): 화면 세로 가운데 띠(1080 기준 y 239~841, 아이폰 가로 노치 자리)에 걸치는 버튼은 가장자리에서 NOTCH_DEPTH 이상 떨어진다.

@export var stick_radius := 110.0

## Input.action_press 는 상태만 바꾸고 이벤트를 보내지 않으므로, 이벤트로 듣는 동작들은 따로 보낸다.
const EVENT_ACTIONS := ["map", "pause"]
## 터치 버튼이 누르는 모든 동작 (숨길 때 전부 뗀다)
const ALL_ACTIONS := ["jump", "dodge", "run_toggle", "attack_light", "plunge", "guard", "heal", "interact", "soul_ability", "soul_next", "map", "pause", "move_left", "move_right", "move_up", "move_down"]
## 두 버튼이 겹치지 않는다고 볼 최소 간격 배수 (중심 거리 ≥ (r1+r2) × 이 값). _begin_touch 가 r×1.2 안을 누름으로 치므로 같은 값.
const GAP_RATIO := 1.2
## 가로로 쥔 아이폰의 노치 깊이 (1080 높이 화면 px, 애플 공개 치수로 계산 — 아이폰 11 Pro 약 86). 시험(probe_ui)이 이 값으로 검사한다.
const NOTCH_DEPTH := 86.0
## 노치가 차지하는 세로 띠 (화면 높이 비율): 1080 기준 y 239 ~ 841
const NOTCH_BAND := Vector2(0.221, 0.779)

var _touches := {}  # 손가락 번호 -> {"role": String, "origin": Vector2, "pos": Vector2}
var _canvas: Control
var _shown := true
var _player: Player


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	if "--touch" in OS.get_cmdline_user_args():
		InputDevice._set_device(InputDevice.Kind.TOUCH, -1)
	InputDevice.device_changed.connect(_on_device_changed)
	_on_device_changed(InputDevice.current)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if _shown:
		_canvas.queue_redraw()


func _on_device_changed(kind: InputDevice.Kind) -> void:
	var show := kind in [InputDevice.Kind.TOUCH, InputDevice.Kind.NONE]
	if show == _shown:
		return
	_shown = show
	_canvas.visible = show
	if not show:
		_release_all()


func _has_player() -> bool:
	return _player != null and is_instance_valid(_player)


## 상황 버튼의 글자: 쉬는 중 '이동·성장'(달빛풀 메뉴: 이동 / 성장 탭), 포탈 앞 '들어가기', 그 밖엔 '손길'.
func _interact_label() -> String:
	if _player.state == Player.State.REST:
		return "이동·성장"
	for n in _player.interactables:
		if n is Portal:
			# 아직 드러나지 않은 숨은 입구는 '손길' 그대로 (틈의 정체를 버튼 글자가 먼저 알려 주지 않게)
			if n is HiddenPortal and not n.is_revealed():
				return "손길"
			return "들어가기"
	return "손길"


## 영혼 버튼의 글자: 지금 고른 영혼의 짧은 이름 (씨앗 / 바람 / 빛). 소녀가 없으면 '영혼'.
func soul_button_text() -> String:
	if not _has_player() or _player.soul == "":
		return "영혼"
	return _player.soul_short_name()


## 버튼이 지금 눌러서 뜻이 있는가. 낙하 공격은 공중에서만 (땅에서는 어둡게 그리고, 눌러도 소녀가 무시한다).
func button_enabled(name: String) -> bool:
	if name == "plunge":
		# 공중 공격·공중 씨앗 베기 중에도 켜짐: 누르면 기억했다가 휘두름이 끝나는 순간 낙하 공격으로 잇는다 (player.gd)
		return _has_player() and not _player.is_on_floor() and (_player.state in Player.LOCOMOTION \
			or _player.state == Player.State.ATTACK or _player.state == Player.State.SOUL_SLASH)
	if name == "soul":
		return not _has_player() or _player.soul_cooldown_left() <= 0.0
	return true


## 버튼 배치: 이름 -> {pos, r, text, action}. 오른쪽은 오른쪽 아래 모서리, 왼쪽은 왼쪽 아래 모서리 기준.
## size 를 주면 그 화면 크기로 계산한다 (시험용: 세 비율의 겹침 검사). 비우면 지금 캔버스 크기.
func _buttons(size := Vector2.ZERO, with_interact := -1) -> Dictionary:
	var s := _canvas.size if size == Vector2.ZERO else size
	var br := Vector2(s.x, s.y)   # 오른쪽 아래 모서리 (오른손 엄지의 축)
	var b := {
		# 오른쪽 엄지 — 모서리에 가까운 안쪽 호: 점프(가장 가까움) → 공격(가장 큼) → 회피(점프 바로 위; 급한 방어라 엄지 가까이).
		# 바깥 호: 낙하(회피 위, 공중에서만 켜짐; 2026-10-19), 가드(공격 왼쪽, 저스트 가드를 같은 엄지로), 영혼 기술(공격 위 — 강공격이 있던 자리).
		"jump": {"pos": br + Vector2(-160, -140), "r": 80.0, "text": "점프", "action": "jump"},
		"attack_light": {"pos": br + Vector2(-360, -210), "r": 96.0, "text": "공격", "action": "attack_light"},
		"dodge_r": {"pos": br + Vector2(-175, -320), "r": 66.0, "text": "회피", "action": "dodge"},
		"plunge": {"pos": br + Vector2(-245, -460), "r": 60.0, "text": "낙하", "action": "plunge"},
		"guard": {"pos": br + Vector2(-560, -140), "r": 76.0, "text": "가드", "action": "guard"},
		"soul": {"pos": br + Vector2(-400, -440), "r": 66.0, "text": soul_button_text(), "action": "soul_ability"},
		# 왼쪽 엄지: 왼쪽 가장자리 세로 줄 (스틱은 그 오른쪽 빈 자리에서 시작한다). 회복·전환은 급하지 않은 버튼.
		# x=170: 가로로 쥔 아이폰의 노치(가장자리 가운데, 깊이 약 130px)를 피한다. 둘 다 아래쪽 절반에 두어
		# 버튼 크기 설정으로 키워도 같은(왼쪽 아래) 모서리 기준으로 함께 벌어진다.
		"heal": {"pos": Vector2(170, s.y - 480), "r": 50.0, "text": "회복", "action": "heal"},
		"soul_next": {"pos": Vector2(170, s.y - 340), "r": 42.0, "text": "전환", "action": "soul_next"},
		# 위 모서리
		"map": {"pos": Vector2(s.x - 76, 76), "r": 46.0, "text": "지도", "action": "map"},
		"menu": {"pos": Vector2(76, 76), "r": 46.0, "text": "메뉴", "action": "pause"},
	}
	var show_interact := (_has_player() and _player.can_interact) if with_interact < 0 else with_interact > 0
	if show_interact:
		b["interact"] = {"pos": br + Vector2(-740, -270), "r": 70.0, "text": _interact_label() if _has_player() else "손길", "action": "interact"}
	var k := Settings.touch_scale_factor()
	if k != 1.0:
		for name in b:
			var e: Dictionary = b[name]
			e["r"] = e["r"] * k
			# 모서리 기준으로 벌어지게
			var anchor := Vector2(s.x if e["pos"].x > s.x / 2.0 else 0.0, s.y if e["pos"].y > s.y / 2.0 else 0.0)
			e["pos"] = anchor + (e["pos"] - anchor) * k
	return b


## 노치에 걸리는 버튼 (시험용): [[이름, 가장자리까지 px], ...]. 세로 띠(NOTCH_BAND)에 걸치면서 왼쪽·오른쪽 가장자리에서
## NOTCH_DEPTH 보다 가까운 버튼. 아이폰은 가로로 어느 쪽을 들어도 되므로(sensor landscape) 양쪽을 다 본다. 위 모서리(지도·메뉴)는 띠 밖이다.
func notch_hits(size: Vector2, with_interact := 1) -> Array:
	var b := _buttons(size, with_interact)
	var out := []
	var y0 := size.y * NOTCH_BAND.x
	var y1 := size.y * NOTCH_BAND.y
	for name in b:
		var p: Vector2 = b[name]["pos"]
		var r: float = b[name]["r"]
		if p.y + r < y0 or p.y - r > y1:
			continue
		var edge := minf(p.x - r, size.x - (p.x + r))
		if edge < NOTCH_DEPTH:
			out.append([name, edge])
	return out


## 겹치는 버튼 쌍 (시험용): [[이름, 이름, 거리, 필요 거리], ...]. 비어 있으면 겹침 없음.
func overlapping_pairs(size: Vector2, with_interact := 1) -> Array:
	var b := _buttons(size, with_interact)
	var names := b.keys()
	var out := []
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Dictionary = b[names[i]]
			var c: Dictionary = b[names[j]]
			var d: float = a["pos"].distance_to(c["pos"])
			var need: float = (a["r"] + c["r"]) * GAP_RATIO
			if d < need:
				out.append([names[i], names[j], d, need])
	return out


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			# 멈춤 중(지도·메뉴·이동 목록)에는 그 화면이 터치를 받는다
			if not _shown or get_tree().paused:
				return
			_begin_touch(event.index, event.position)
		else:
			_end_touch(event.index)
	elif event is InputEventScreenDrag:
		if _touches.has(event.index):
			_touches[event.index]["pos"] = event.position
			_update_stick()


func _begin_touch(index: int, pos: Vector2) -> void:
	var buttons := _buttons()
	var role := ""
	var best := INF
	for name in buttons:
		var b: Dictionary = buttons[name]
		var d: float = pos.distance_to(b["pos"])
		if d <= b["r"] * GAP_RATIO and d < best:
			best = d
			role = name
	if role == "":
		if pos.x < _canvas.size.x * 0.45:
			role = "stick"
		else:
			return
	else:
		Input.action_press(buttons[role]["action"])
		_send_action_event(buttons[role]["action"], true)
	_touches[index] = {"role": role, "origin": pos, "pos": pos}


## 지도·메뉴처럼 _unhandled_input 으로 듣는 동작은 진짜 입력 이벤트로도 보낸다.
func _send_action_event(action: String, pressed: bool) -> void:
	if action not in EVENT_ACTIONS:
		return
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _end_touch(index: int) -> void:
	if not _touches.has(index):
		return
	var role: String = _touches[index]["role"]
	_touches.erase(index)
	if role == "stick":
		_update_stick()
		return
	var buttons := _buttons()
	var action: String = buttons[role]["action"] if buttons.has(role) else ""
	if action == "":
		return
	# 같은 동작을 다른 손가락이 아직 누르고 있으면 유지
	for t in _touches.values():
		if buttons.has(t["role"]) and buttons[t["role"]]["action"] == action:
			return
	Input.action_release(action)
	_send_action_event(action, false)


func _update_stick() -> void:
	var v := Vector2.ZERO
	for t in _touches.values():
		if t["role"] == "stick":
			v = (t["pos"] - t["origin"]) / stick_radius
			v = v.limit_length(1.0)
	if absf(v.x) < 0.12:
		v.x = 0.0
	if absf(v.y) < 0.12:
		v.y = 0.0
	_set_axis("move_left", "move_right", v.x)
	_set_axis("move_up", "move_down", v.y)


func _set_axis(neg: String, pos: String, value: float) -> void:
	if value < 0.0:
		Input.action_press(neg, -value)
		Input.action_release(pos)
	elif value > 0.0:
		Input.action_press(pos, value)
		Input.action_release(neg)
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _release_all() -> void:
	_touches.clear()
	for a in ALL_ACTIONS:
		Input.action_release(a)


## 테두리 있는 글자 (밝은 배경에서도 읽히게).
func _label(pos: Vector2, text: String, size: int, color: Color, width: float) -> void:
	var font := ThemeDB.fallback_font
	_canvas.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 5, Color(0, 0, 0, 0.75 * color.a))
	_canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


## 영혼 버튼: 영혼 색 테두리, 쿨다운 중엔 어둡고 남은 초 + 차오르는 호.
func _draw_soul_button(b: Dictionary, pressed: bool, idle: Color, active: Color) -> void:
	var c: Vector2 = b["pos"]
	var r: float = b["r"]
	var col := _player.soul_color() if _has_player() else Color.WHITE
	var ratio := _player.soul_cooldown_ratio() if _has_player() else 0.0
	var cooling := ratio > 0.0
	var fill := idle
	if pressed:
		fill = active
	elif cooling:
		fill = Color(0.02, 0.02, 0.04, 0.6)
	else:
		fill = Color(col.r * 0.25, col.g * 0.25, col.b * 0.22, 0.5)
	_canvas.draw_circle(c, r, fill)
	if cooling:
		# 어두운 호 = 아직 남은 비율 (시계 방향 끝쪽), 밝은 호 = 지난 비율 (위에서 시계 방향으로 차오른다)
		var done := TAU * (1.0 - ratio)
		_canvas.draw_arc(c, r, -PI / 2.0, -PI / 2.0 + TAU, 48, Color(col.r, col.g, col.b, 0.22), 3.0, true)
		if done > 0.02:
			_canvas.draw_arc(c, r, -PI / 2.0, -PI / 2.0 + done, 48, Color(col.r, col.g, col.b, 0.95), 5.0, true)
		var small := 15 if r < 60 else 18
		_label(c + Vector2(-r * 1.5, -r * 0.42 + small * 0.36), b["text"], small, Color(col.r, col.g, col.b, 0.75), r * 3.0)
		var num := 30 if r < 60 else 36
		_label(c + Vector2(-r * 1.5, r * 0.2 + num * 0.36), _player.soul_cooldown_text(), num, Color(1, 1, 1, 0.95), r * 3.0)
	else:
		_canvas.draw_arc(c, r, 0, TAU, 48, Color(col.r, col.g, col.b, 0.9), 3.5, true)
		var size := 22 if r < 60 else 28
		_label(c + Vector2(-r * 1.5, size * 0.36), b["text"], size, Color(1, 1, 1, 0.95), r * 3.0)


func _on_draw() -> void:
	var idle := Color(0.03, 0.04, 0.07, 0.42)
	var ring := Color(1, 1, 1, 0.55)
	var active := Color("8fd3ff", 0.6)
	for t in _touches.values():
		if t["role"] == "stick":
			var origin: Vector2 = t["origin"]
			var knob: Vector2 = origin + (t["pos"] - origin).limit_length(stick_radius)
			_canvas.draw_circle(origin, stick_radius, Color(0, 0, 0, 0.25))
			_canvas.draw_arc(origin, stick_radius, 0, TAU, 48, ring, 3.0, true)
			_canvas.draw_circle(knob, 40.0, active)
			_canvas.draw_arc(knob, 40.0, 0, TAU, 32, Color(1, 1, 1, 0.8), 2.0, true)
	var resting := _has_player() and _player.state == Player.State.REST
	var buttons := _buttons()
	for name in buttons:
		var b: Dictionary = buttons[name]
		var pressed := false
		for t in _touches.values():
			if t["role"] == name:
				pressed = true
		if name == "soul":
			_draw_soul_button(b, pressed, idle, active)
			continue
		var enabled := button_enabled(name)
		var fill := idle
		var ring_col := ring
		var text_col := Color(1, 1, 1, 0.95)
		if pressed:
			fill = active
		elif name == "interact":
			fill = Color("8fd3ff" if resting else "ffd46a", 0.35 + 0.1 * sin(Time.get_ticks_msec() / 150.0))
		elif not enabled:
			# 낙하: 땅에서는 꺼진 버튼 (어둡고 흐릿하게)
			fill = Color(0.02, 0.02, 0.04, 0.22)
			ring_col = Color(1, 1, 1, 0.18)
			text_col = Color(1, 1, 1, 0.35)
		elif name == "plunge":
			# 공중: 쓸 수 있다고 살짝 밝게
			fill = Color(0.35, 0.55, 0.8, 0.45)
		if name == "soul_next" and _has_player() and _player.next_soul() != "":
			var nc := _player.soul_color(_player.next_soul())
			ring_col = Color(nc.r, nc.g, nc.b, 0.9)
			if not pressed:
				fill = Color(nc.r * 0.3, nc.g * 0.3, nc.b * 0.28, 0.45)
		var r: float = b["r"]
		_canvas.draw_circle(b["pos"], r, fill)
		_canvas.draw_arc(b["pos"], r, 0, TAU, 48, ring_col, 3.0, true)
		var text: String = b["text"]
		var size := 22 if r < 60 else 28
		_label(b["pos"] + Vector2(-r * 1.5, size * 0.36), text, size, text_col, r * 3.0)
	# (화면 아래 조작 설명 줄은 없앴다. 버튼 이름만으로 충분하고, 설명 글자는 기획자 요청으로 모두 제거.)

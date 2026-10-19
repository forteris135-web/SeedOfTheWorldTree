extends CanvasLayer
## 터치 조작 (기획서 8장 "터치 조작").
## - 왼쪽 화면 어디든 누르면 그 자리에 스틱.
## - 오른쪽 엄지: 싸움 버튼 다섯 개만. 아래 모서리를 축으로 안쪽 호에 점프(가장 가까움)·약공격(가장 큼),
##   바깥 호에 회피(점프 위)·가드(약공격 왼쪽, 저스트 가드를 같은 엄지로)·영혼 기술(약공격 위, 옛 강공격 자리).
##   낙하 공격은 스틱을 절반 넘게 아래로 내린 채 약공격, 하단 점프는 스틱 절반 넘게 아래 + 점프
##   (살짝 처진 엄지로는 안 걸린다 — player.gd DOWN_HOLD_STRENGTH 0.5).
## - 왼쪽 가장자리 세로 줄: 회복 / 전환 (급하지 않은 버튼). 걷기 고정은 L3·키보드만 (터치 버튼은 없앴다).
## - 상황 버튼(손길): 상호작용이 가능할 때만 나타난다. 달빛풀에서 쉬는 중엔 '이동', 포탈 앞에선 '들어가기'.
## - 위 모서리: 왼쪽 '메뉴'(Esc), 오른쪽 '지도'. 이 둘은 방이 입력 이벤트로 받으므로 InputEventAction 을 함께 보낸다.
## - 밝은 배경에서도 보이게: 어두운 반투명 바탕 + 흰 테두리 + 테두리 있는 글자.
## - 컨트롤러나 키보드 입력이 들어오면 숨고, 화면을 만지면 다시 나타난다.
## - 멈춤(지도·메뉴) 중에도 손가락 떼기는 받아서 버튼이 눌린 채 남지 않게 한다.

@export var stick_radius := 110.0

## Input.action_press 는 상태만 바꾸고 이벤트를 보내지 않으므로, 이벤트로 듣는 동작들은 따로 보낸다.
const EVENT_ACTIONS := ["map", "pause"]

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


## 상황 버튼의 글자: 쉬는 중 '이동', 포탈 앞 '들어가기', 그 밖엔 '손길'.
func _interact_label() -> String:
	if _player.state == Player.State.REST:
		return "이동"
	for n in _player.interactables:
		if n is Portal:
			return "들어가기"
	return "손길"


## 버튼 배치: 이름 -> {pos, r, text, action}. 오른쪽은 오른쪽 아래 모서리, 왼쪽은 왼쪽 아래 모서리 기준.
func _buttons() -> Dictionary:
	var s := _canvas.size
	var br := Vector2(s.x, s.y)   # 오른쪽 아래 모서리 (오른손 엄지의 축)
	var b := {
		# 오른쪽 엄지 (2026-10-18 기획자 결정: 오른쪽은 싸움 버튼 다섯 개만) — 모서리에 가까운 안쪽 호:
		# 점프(가장 가까움) → 약공격(가장 큼). 바깥 호: 회피(점프 위), 가드(약공격 왼쪽, 저스트 가드를 같은 엄지로),
		# 영혼 기술(약공격 위 — 강공격이 있던 자리. 강공격은 없앴다).
		"jump": {"pos": br + Vector2(-160, -140), "r": 80.0, "text": "점프", "action": "jump"},
		"attack_light": {"pos": br + Vector2(-360, -210), "r": 96.0, "text": "약공격", "action": "attack_light"},
		"dodge_r": {"pos": br + Vector2(-170, -350), "r": 66.0, "text": "회피", "action": "dodge"},
		"guard": {"pos": br + Vector2(-560, -140), "r": 76.0, "text": "가드", "action": "guard"},
		"soul": {"pos": br + Vector2(-390, -430), "r": 66.0, "text": "영혼", "action": "soul_ability"},
		# 왼쪽 엄지: 왼쪽 가장자리 세로 줄 (스틱은 그 오른쪽 빈 자리에서 시작한다). 회복·전환은 급하지 않은 버튼.
		# x=170: 가로로 쥔 아이폰의 노치(가장자리 가운데, 깊이 약 130px)를 피한다. 둘 다 아래쪽 절반에 두어
		# 버튼 크기 설정으로 키워도 같은(왼쪽 아래) 모서리 기준으로 함께 벌어진다.
		"heal": {"pos": Vector2(170, s.y - 480), "r": 50.0, "text": "회복", "action": "heal"},
		"soul_next": {"pos": Vector2(170, s.y - 340), "r": 42.0, "text": "전환", "action": "soul_next"},
		# 위 모서리
		"map": {"pos": Vector2(s.x - 76, 76), "r": 46.0, "text": "지도", "action": "map"},
		"menu": {"pos": Vector2(76, 76), "r": 46.0, "text": "메뉴", "action": "pause"},
	}
	if _player and is_instance_valid(_player) and _player.can_interact:
		b["interact"] = {"pos": br + Vector2(-740, -270), "r": 70.0, "text": _interact_label(), "action": "interact"}
	var k := Settings.touch_scale_factor()
	if k != 1.0:
		for name in b:
			var e: Dictionary = b[name]
			e["r"] = e["r"] * k
			# 모서리 기준으로 벌어지게
			var anchor := Vector2(s.x if e["pos"].x > s.x / 2.0 else 0.0, s.y if e["pos"].y > s.y / 2.0 else 0.0)
			e["pos"] = anchor + (e["pos"] - anchor) * k
	return b


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
		if d <= b["r"] * 1.2 and d < best:
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
	for a in ["jump", "dodge", "run_toggle", "attack_light", "guard", "heal", "interact", "soul_ability", "soul_next", "map", "pause", "move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)


## 테두리 있는 글자 (밝은 배경에서도 읽히게).
func _label(pos: Vector2, text: String, size: int, color: Color, width: float) -> void:
	var font := ThemeDB.fallback_font
	_canvas.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 5, Color(0, 0, 0, 0.75))
	_canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, color)


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
	var resting := _player != null and is_instance_valid(_player) and _player.state == Player.State.REST
	var buttons := _buttons()
	for name in buttons:
		var b: Dictionary = buttons[name]
		var pressed := false
		for t in _touches.values():
			if t["role"] == name:
				pressed = true
		var fill := idle
		if pressed:
			fill = active
		elif name == "interact":
			fill = Color("8fd3ff" if resting else "ffd46a", 0.35 + 0.1 * sin(Time.get_ticks_msec() / 150.0))
		var r: float = b["r"]
		_canvas.draw_circle(b["pos"], r, fill)
		_canvas.draw_arc(b["pos"], r, 0, TAU, 48, ring, 3.0, true)
		var text: String = b["text"]
		var size := 22 if r < 60 else 28
		_label(b["pos"] + Vector2(-r * 1.5, size * 0.36), text, size, Color(1, 1, 1, 0.95), r * 3.0)
	# (화면 아래 조작 설명 줄은 없앴다. 버튼 이름만으로 충분하고, 설명 글자는 기획자 요청으로 모두 제거.)

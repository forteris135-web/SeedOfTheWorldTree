extends CanvasLayer
## 임시 터치 조작 (기획서 8장 "터치 조작" 배치를 따른 초안).
## - 왼쪽 화면 어디든 누르면 그 자리에 스틱.
## - 오른쪽: 약공격(가장 크게), 가드(바로 옆, 크게), 점프·회피(아래), 강공격(위, 길게 누르면 차지), 회복(작게 위), 달리기 고정.
## - 왼쪽 아래: 회피 / 달리기 고정 (양손 어느 쪽으로도).
## - 상황 버튼(손길): 쉬기·정화가 가능할 때만 나타난다. 달빛풀에서 쉬는 중에는 '이동'.
## - 위 모서리: 왼쪽 '메뉴', 오른쪽 '지도'. 이 둘은 방이 입력 이벤트로 받으므로 InputEventAction 을 함께 보낸다.
## - 컨트롤러나 키보드 입력이 들어오면 숨고, 화면을 만지면 다시 나타난다.
## - 멈춤(지도·메뉴) 중에도 손가락 떼기는 받아서 버튼이 눌린 채 남지 않게 한다.

## Input.action_press 는 상태만 바꾸고 이벤트를 보내지 않으므로, 이벤트로 듣는 동작들은 따로 보낸다.
const EVENT_ACTIONS := ["map", "pause"]

@export var stick_radius := 110.0

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


## 버튼 배치: 이름 -> {pos, r, text, action}
func _buttons() -> Dictionary:
	var s := _canvas.size
	var b := {
		"attack_light": {"pos": Vector2(s.x - 190, s.y - 290), "r": 86.0, "text": "약공격", "action": "attack_light"},
		"guard": {"pos": Vector2(s.x - 390, s.y - 250), "r": 78.0, "text": "가드", "action": "guard"},
		"jump": {"pos": Vector2(s.x - 170, s.y - 110), "r": 66.0, "text": "점프", "action": "jump"},
		"dodge_r": {"pos": Vector2(s.x - 330, s.y - 90), "r": 56.0, "text": "회피", "action": "dodge"},
		"attack_heavy": {"pos": Vector2(s.x - 190, s.y - 460), "r": 62.0, "text": "강공격", "action": "attack_heavy"},
		"run_r": {"pos": Vector2(s.x - 360, s.y - 420), "r": 46.0, "text": "달리기", "action": "run_toggle"},
		"heal": {"pos": Vector2(s.x - 90, s.y - 600), "r": 42.0, "text": "회복", "action": "heal"},
		"dodge_l": {"pos": Vector2(150, s.y - 110), "r": 60.0, "text": "회피", "action": "dodge"},
		"run_l": {"pos": Vector2(330, s.y - 150), "r": 46.0, "text": "달리기", "action": "run_toggle"},
		"map": {"pos": Vector2(s.x - 76, 76), "r": 46.0, "text": "지도", "action": "map"},
		"menu": {"pos": Vector2(76, 76), "r": 46.0, "text": "메뉴", "action": "pause"},
		"soul": {"pos": Vector2(s.x - 230, s.y - 600), "r": 42.0, "text": "영혼", "action": "soul_ability"},
		"soul_next": {"pos": Vector2(s.x - 330, s.y - 560), "r": 30.0, "text": "전환", "action": "soul_next"},
	}
	if _player and is_instance_valid(_player) and _player.can_interact:
		var resting := _player.state == Player.State.REST
		b["interact"] = {"pos": Vector2(s.x - 560, s.y - 110), "r": 70.0, "text": "이동" if resting else "손길", "action": "interact"}
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
	for a in ["jump", "dodge", "run_toggle", "attack_light", "attack_heavy", "guard", "heal", "interact", "soul_ability", "soul_next", "map", "pause", "move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)


func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var idle := Color(1, 1, 1, 0.12)
	var active := Color("8fd3ff", 0.35)
	var locked := Color("ffd46a", 0.35)
	for t in _touches.values():
		if t["role"] == "stick":
			var origin: Vector2 = t["origin"]
			var knob: Vector2 = origin + (t["pos"] - origin).limit_length(stick_radius)
			_canvas.draw_circle(origin, stick_radius, idle)
			_canvas.draw_arc(origin, stick_radius, 0, TAU, 48, Color(1, 1, 1, 0.3), 2.0, true)
			_canvas.draw_circle(knob, 40.0, active)
	var run_on := _player != null and is_instance_valid(_player) and _player.run_locked
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
		elif name.begins_with("run") and run_on:
			fill = locked
		elif name == "interact":
			fill = Color("8fd3ff" if resting else "ffd46a", 0.25 + 0.1 * sin(Time.get_ticks_msec() / 150.0))
		elif name == "map" or name == "menu":
			fill = Color(1, 1, 1, 0.16)
		var r: float = b["r"]
		_canvas.draw_circle(b["pos"], r, fill)
		_canvas.draw_arc(b["pos"], r, 0, TAU, 48, Color(1, 1, 1, 0.3), 2.0, true)
		var text: String = b["text"]
		if name.begins_with("run") and run_on:
			text = "달리기 ●"
		_canvas.draw_string(font, b["pos"] + Vector2(-r * 1.5, 9), text, HORIZONTAL_ALIGNMENT_CENTER, r * 3.0, 22 if r < 60 else 28, Color(1, 1, 1, 0.8))
	if _touches.is_empty():
		_canvas.draw_string(font, Vector2(_canvas.size.x * 0.5 - 700, _canvas.size.y - 36), "왼쪽 화면을 누른 채 움직이면 이동  ·  회피 짧게: 구르기, 길게: 달리기  ·  강공격 길게: 차지", HORIZONTAL_ALIGNMENT_CENTER, 1400, 20, Color(1, 1, 1, 0.45))

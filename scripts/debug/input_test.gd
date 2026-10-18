extends Control
## 1단계 입력 확인 화면.
## 조작표(GAME_DESIGN.md 8장)의 모든 동작이 듀얼센스 / 엑스박스 / 키보드 / 터치에서
## 제대로 들어오는지 눈으로 확인한다. 화면은 모두 코드로 만든다.

# (동작 이름, 표시 이름, 듀얼센스, 엑스박스, 키보드)
const ACTIONS := [
	["move_left", "이동 ←", "L스틱 ←", "L스틱 ←", "A, ←"],
	["move_right", "이동 →", "L스틱 →", "L스틱 →", "D, →"],
	["move_up", "위 (메뉴·사다리)", "L스틱 ↑", "L스틱 ↑", "W, ↑"],
	["move_down", "아래 (메뉴·사다리)", "L스틱 ↓", "L스틱 ↓", "S, ↓"],
	["jump", "점프", "×", "A", "Space"],
	["dodge", "회피 / 달리기", "○", "B", "Shift"],
	["attack_light", "약공격", "R1", "RB", "J"],
	["attack_heavy", "강공격 / 차지", "R2", "RT", "K"],
	["guard", "가드 / 저스트 가드", "L1", "LB", "L"],
	["soul_ability", "영혼 능력", "L2", "LT", "I"],
	["heal", "회복 (이슬 방울)", "□", "X", "R, H"],
	["interact", "상호작용 / 정화의 손길", "△", "Y", "E, U"],
	["soul_prev", "영혼 전환 ←", "십자키 ←", "십자키 ←", "-"],
	["soul_next", "영혼 전환 →", "십자키 →", "십자키 →", "Q"],
	["map", "지도", "만들기", "보기", "M, Tab"],
	["run_toggle", "달리기 고정", "L3", "LS 누르기", "- (터치 버튼)"],
	["pause", "메뉴 / 일시정지", "옵션", "메뉴", "Esc, P"],
]

const BG := Color("141a2a")
const PANEL_IDLE := Color("1f2840")
const PANEL_ON := Color("6fcf97")
const TEXT_DIM := Color("9aa3b8")
const TEXT_ON := Color("0e1420")
const ACCENT := Color("e9c46a")
const MOON := Color("8fd3ff")

const LOG_LINES := 8

var _device_label: Label
var _pads_label: Label
var _panels := {}  # 동작 이름 -> Panel
var _panel_labels := {}  # 동작 이름 -> Label
var _stick: StickView
var _trigger_left: ProgressBar
var _trigger_right: ProgressBar
var _log_label: Label
var _touch_label: Label
var _log: PackedStringArray = []
var _axis_active := {}  # 축 번호 -> bool (기록용)
var _touches := {}  # 손가락 번호 -> 위치


func _ready() -> void:
	Music.stop(0.5)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	InputDevice.device_changed.connect(_on_device_changed)
	InputDevice.joypads_changed.connect(_refresh_pads)
	_on_device_changed(InputDevice.current)
	_refresh_pads()
	# Claude Code가 화면을 확인할 때 쓰는 자동 스크린샷 모드.
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.0).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://screenshots/debug_input_test.png"))
		get_tree().quit()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 48)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	# 제목
	root.add_child(_make_label("세계수의 씨앗  ·  1단계 입력 확인", 40, ACCENT))
	_device_label = _make_label("", 30, Color.WHITE)
	root.add_child(_device_label)
	_pads_label = _make_label("", 22, TEXT_DIM)
	root.add_child(_pads_label)

	# 가운데: 왼쪽 스틱 / 오른쪽 동작 표
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 48)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.custom_minimum_size.x = 420
	body.add_child(left)
	left.add_child(_make_label("왼쪽 스틱 / 이동", 24, TEXT_DIM))
	_stick = StickView.new()
	_stick.custom_minimum_size = Vector2(300, 300)
	left.add_child(_stick)
	left.add_child(_make_label("L2 / LT (영혼 능력)", 20, TEXT_DIM))
	_trigger_left = _make_bar()
	left.add_child(_trigger_left)
	left.add_child(_make_label("R2 / RT (강공격)", 20, TEXT_DIM))
	_trigger_right = _make_bar()
	left.add_child(_trigger_right)
	_touch_label = _make_label("터치: 없음", 20, TEXT_DIM)
	left.add_child(_touch_label)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	right.add_child(_make_label("누르면 초록으로 켜진다  (동작  ·  듀얼센스 / 엑스박스 / 키보드)", 22, TEXT_DIM))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	right.add_child(grid)
	for a in ACTIONS:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(0, 58)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := StyleBoxFlat.new()
		style.bg_color = PANEL_IDLE
		style.set_corner_radius_all(10)
		style.content_margin_left = 16
		style.content_margin_right = 16
		panel.add_theme_stylebox_override("panel", style)
		var label := _make_label("%s   ·   %s / %s / %s" % [a[1], a[2], a[3], a[4]], 22, Color.WHITE)
		label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.offset_left = 16
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		panel.add_child(label)
		grid.add_child(panel)
		_panels[a[0]] = panel
		_panel_labels[a[0]] = label

	right.add_child(_make_label("가드(L1 / LB)를 누르면 컨트롤러가 짧게 떨린다.  마우스로 화면을 누르면 터치로 친다.  메뉴(옵션 / Esc·P)를 누르면 타이틀로.", 20, TEXT_DIM))

	# 아래: 최근 입력 기록
	root.add_child(_make_label("최근 입력 (원본 그대로)", 22, TEXT_DIM))
	_log_label = _make_label("", 18, MOON)
	_log_label.custom_minimum_size.y = 18 * 1.4 * LOG_LINES
	root.add_child(_log_label)


func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _make_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.01
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(300, 22)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = PANEL_IDLE
	back.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", back)
	return bar


func _process(_delta: float) -> void:
	# 동작 패널 켜고 끄기
	for a in ACTIONS:
		var action: String = a[0]
		var strength := Input.get_action_strength(action)
		var style: StyleBoxFlat = _panels[action].get_theme_stylebox("panel")
		style.bg_color = PANEL_IDLE.lerp(PANEL_ON, strength)
		_panel_labels[action].add_theme_color_override("font_color", Color.WHITE.lerp(TEXT_ON, strength))

	# 스틱과 트리거
	var pad := InputDevice.rumble_target()
	var stick := Vector2.ZERO
	if pad >= 0:
		stick = Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		_trigger_left.value = Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT)
		_trigger_right.value = Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT)
	else:
		# 키보드만 있을 때도 이동 방향을 스틱 그림으로 보여 준다.
		stick = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		_trigger_left.value = Input.get_action_strength("soul_ability")
		_trigger_right.value = Input.get_action_strength("attack_heavy")
	_stick.set_stick(stick)

	# 가드를 누른 순간 진동 (저스트 가드 손맛의 기초)
	if Input.is_action_just_pressed("guard") and pad >= 0:
		Input.start_joy_vibration(pad, 0.4, 0.7, 0.2)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Game.go_to(Game.TITLE_SCENE, 0.4, 0.6)
		return
	# 원본 입력 기록 (스틱은 크게 움직였을 때 한 번만)
	if event is InputEventKey and event.pressed and not event.echo:
		_push_log("키보드: %s" % OS.get_keycode_string(event.physical_keycode))
	elif event is InputEventJoypadButton and event.pressed:
		_push_log("%s: 버튼 %d" % [InputDevice.kind_name(InputDevice.joy_kind(event.device)), event.button_index])
	elif event is InputEventJoypadMotion:
		var active := absf(event.axis_value) > 0.6
		if active and not _axis_active.get(event.axis, false):
			_push_log("%s: 축 %d  %s" % [InputDevice.kind_name(InputDevice.joy_kind(event.device)), event.axis, "+" if event.axis_value > 0 else "-"])
		_axis_active[event.axis] = active
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			_push_log("터치: 손가락 %d  (%d, %d)" % [event.index, event.position.x, event.position.y])
		else:
			_touches.erase(event.index)
		_refresh_touch()
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		_refresh_touch()


func _push_log(line: String) -> void:
	_log.append(line)
	while _log.size() > LOG_LINES:
		_log.remove_at(0)
	_log_label.text = "\n".join(_log)


func _refresh_touch() -> void:
	if _touches.is_empty():
		_touch_label.text = "터치: 없음"
	else:
		var parts: PackedStringArray = []
		for i in _touches:
			parts.append("(%d, %d)" % [_touches[i].x, _touches[i].y])
		_touch_label.text = "터치 %d개: %s" % [_touches.size(), " ".join(parts)]


func _on_device_changed(kind: InputDevice.Kind) -> void:
	_device_label.text = "지금 쓰는 장치:  %s" % InputDevice.kind_name(kind)


func _refresh_pads() -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_pads_label.text = "연결된 컨트롤러 없음  (키보드와 터치만 확인할 수 있다)"
		return
	var names: PackedStringArray = []
	for id in pads:
		names.append("%d번 %s" % [id, Input.get_joy_name(id)])
	_pads_label.text = "연결된 컨트롤러: " + ",  ".join(names)


## 왼쪽 스틱을 동그라미와 점으로 그린다.
class StickView:
	extends Control
	var _value := Vector2.ZERO

	func set_stick(v: Vector2) -> void:
		if v != _value:
			_value = v
			queue_redraw()

	func _draw() -> void:
		var center := size / 2.0
		var radius := minf(size.x, size.y) / 2.0 - 8.0
		draw_circle(center, radius, Color("1f2840"))
		draw_arc(center, radius, 0.0, TAU, 64, Color("9aa3b8"), 2.0, true)
		draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color("2d3853"), 1.0)
		draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color("2d3853"), 1.0)
		var dot := center + _value.limit_length(1.0) * radius
		draw_line(center, dot, Color("8fd3ff", 0.5), 3.0, true)
		draw_circle(dot, 14.0, Color("8fd3ff"))

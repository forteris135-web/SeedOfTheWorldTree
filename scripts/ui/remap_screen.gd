extends CanvasLayer
class_name RemapScreen
## 키·버튼 바꾸기 화면. 동작을 고르고 결정하면, 다음에 누르는 키(또는 컨트롤러 버튼)로 바뀐다.

var _panel: Control
var _open := false
var _index := 0
var _waiting := false
var _t := 0.0
var _scroll := 0


func _ready() -> void:
	layer = 46
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	_panel.draw.connect(_on_draw)
	add_child(_panel)


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	_waiting = false
	_index = 0
	_panel.visible = true
	get_tree().paused = true


func close() -> void:
	_open = false
	_panel.visible = false
	get_tree().paused = false


func _process(delta: float) -> void:
	if _open:
		_t += delta
		_panel.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	get_viewport().set_input_as_handled()
	var rows := Keymap.ACTIONS.size() + 2   # + 기본값으로, 닫기
	if _waiting:
		# 다음 입력으로 바꾼다 (키 누름 / 버튼 누름 / 스틱·트리거 크게 움직임)
		var ok := false
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_ESCAPE:
				_waiting = false
				return
			ok = true
		elif event is InputEventJoypadButton and event.pressed:
			ok = true
		elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.75:
			ok = true
		if ok:
			Keymap.rebind(Keymap.ACTIONS[_index], event)
			Sfx.play("select")
			_waiting = false
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed("dodge"):
		close()
	elif event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
		_index = (_index + 1) % rows
		Sfx.play("blip")
	elif event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
		_index = (_index - 1 + rows) % rows
		Sfx.play("blip")
	elif event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_activate()
	elif event is InputEventScreenTouch and event.pressed:
		var hit := _row_at(event.position)
		if hit >= 0:
			_index = hit
			_activate()
		else:
			close()


func _activate() -> void:
	if _index == Keymap.ACTIONS.size():
		Keymap.reset_defaults()
		Sfx.play("select")
	elif _index == Keymap.ACTIONS.size() + 1:
		close()
	else:
		_waiting = true
		Sfx.play("select")


func _row_rect(i: int) -> Rect2:
	var size := _panel.size
	var w := 1100.0
	return Rect2((size.x - w) / 2.0, 150.0 + i * 46.0, w, 42.0)


func _row_at(pos: Vector2) -> int:
	for i in Keymap.ACTIONS.size() + 2:
		if _row_rect(i).has_point(pos):
			return i
	return -1


func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var size := _panel.size
	_panel.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.9))
	_panel.draw_string(font, Vector2(size.x / 2.0 - 500, 90), "키 · 버튼 바꾸기", HORIZONTAL_ALIGNMENT_CENTER, 1000, 38, Color(1.0, 0.9, 0.72))
	_panel.draw_string(font, Vector2(size.x / 2.0 - 500, 122), "동작을 고르고 결정한 뒤, 새로 쓸 키나 컨트롤러 버튼을 누른다  ·  Esc: 취소", HORIZONTAL_ALIGNMENT_CENTER, 1000, 18, Color(1, 1, 1, 0.5))
	var heads := _row_rect(0)
	_panel.draw_string(font, heads.position + Vector2(20, -8), "동작", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.4))
	_panel.draw_string(font, heads.position + Vector2(380, -8), "키보드", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.4))
	_panel.draw_string(font, heads.position + Vector2(640, -8), "듀얼센스", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.4))
	_panel.draw_string(font, heads.position + Vector2(880, -8), "엑스박스", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.4))
	for i in Keymap.ACTIONS.size() + 2:
		var r := _row_rect(i)
		var sel := i == _index
		_panel.draw_rect(r, Color(1.0, 0.86, 0.5, 0.16) if sel else Color(1, 1, 1, 0.04))
		var c := Color(1.0, 0.86, 0.5) if sel else Color(0.9, 0.9, 0.9)
		if i < Keymap.ACTIONS.size():
			var a: String = Keymap.ACTIONS[i]
			_panel.draw_string(font, r.position + Vector2(20, 29), ("▸ " if sel else "   ") + Keymap.NAMES[a], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, c)
			if sel and _waiting:
				var blink := 0.5 + 0.5 * sin(_t * 8.0)
				_panel.draw_string(font, r.position + Vector2(380, 29), "새 키나 버튼을 누르세요…", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.56, 0.83, 1.0, 0.5 + 0.5 * blink))
			else:
				_panel.draw_string(font, r.position + Vector2(380, 29), Keymap.label_for(a, "kb"), HORIZONTAL_ALIGNMENT_LEFT, 240, 20, c)
				_panel.draw_string(font, r.position + Vector2(640, 29), Keymap.label_for(a, "ds"), HORIZONTAL_ALIGNMENT_LEFT, 220, 20, c)
				_panel.draw_string(font, r.position + Vector2(880, 29), Keymap.label_for(a, "xb"), HORIZONTAL_ALIGNMENT_LEFT, 200, 20, c)
		elif i == Keymap.ACTIONS.size():
			_panel.draw_string(font, r.position + Vector2(20, 29), ("▸ " if sel else "   ") + "기본 배치로 되돌리기", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, c)
		else:
			_panel.draw_string(font, r.position + Vector2(20, 29), ("▸ " if sel else "   ") + "닫기", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, c)

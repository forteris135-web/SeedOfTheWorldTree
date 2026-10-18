extends CanvasLayer
## 대화 상자. 화면 아래에 말하는 이와 문장이 뜨고, 버튼(점프/손길/공격/터치)으로 다음 문장으로 넘어간다.
## 대사는 코드에 두지 않고 data/dialogue/*.json 에서 읽은 것을 넘겨받는다.
## 사용: Dialogue.start([{"speaker": "티아", "text": "..."}], func(): ...)

signal finished

var _lines: Array = []
var _index := -1
var _shown := 0.0        # 글자 수 (타자기 효과)
var _panel: Control
var _active := false
var _done_callback: Callable
var _player: Node
var _t := 0.0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_panel.draw.connect(_on_draw)
	add_child(_panel)


func is_active() -> bool:
	return _active


func start(lines: Array, on_done := Callable()) -> void:
	if lines.is_empty():
		return
	_lines = lines
	_index = -1
	_done_callback = on_done
	_active = true
	_panel.visible = true
	_player = get_tree().get_first_node_in_group("player")
	if _player:
		_player.input_enabled = false
	_since = 0.0
	_next()


func _next() -> void:
	_index += 1
	_shown = 0.0
	if _index >= _lines.size():
		_end()
		return
	_panel.queue_redraw()


func _end() -> void:
	_active = false
	_panel.visible = false
	if _player and is_instance_valid(_player):
		_player.input_enabled = true
	finished.emit()
	if _done_callback.is_valid():
		_done_callback.call()


func _process(delta: float) -> void:
	if not _active:
		return
	_t += delta
	_since += delta
	var before := int(_shown)
	_shown += delta * 38.0
	var text: String = _lines[_index].get("text", "") if _index >= 0 and _index < _lines.size() else ""
	if int(_shown) != before and int(_shown) <= text.length() and int(_shown) % 3 == 0:
		Sfx.play("blip", -14.0, 0.15)
	_panel.queue_redraw()


func _physics_process(_delta: float) -> void:
	if _active and _advance_pressed():
		_process_advance()


var _since := 0.0


func _advance_pressed() -> bool:
	return Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("interact") \
		or Input.is_action_just_pressed("attack_light") or Input.is_action_just_pressed("ui_accept")


func _process_advance() -> void:
	# 상자가 뜬 직후의 같은 버튼 입력은 무시한다 (말 걸기 버튼이 바로 다음 문장을 넘기지 않게)
	if _since < 0.2:
		return
	var text: String = _lines[_index].get("text", "")
	if _shown < text.length():
		_shown = text.length()   # 먼저 전부 보여 주고
	else:
		_next()
		_since = 0.0


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventScreenTouch and event.pressed:
		_process_advance()
		get_viewport().set_input_as_handled()


func _on_draw() -> void:
	if _index < 0 or _index >= _lines.size():
		return
	var font := ThemeDB.fallback_font
	var size := _panel.size
	var line: Dictionary = _lines[_index]
	var w := minf(1400.0, size.x - 120.0)
	var x := (size.x - w) / 2.0
	var h := 190.0
	var y := size.y - h - 60.0
	_panel.draw_rect(Rect2(x, y, w, h), Color(0.03, 0.04, 0.06, 0.82))
	_panel.draw_rect(Rect2(x, y, w, h), Color(1.0, 0.86, 0.5, 0.35), false, 2.0)
	var speaker: String = line.get("speaker", "")
	if speaker != "":
		_panel.draw_string(font, Vector2(x + 28, y + 40), speaker, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.86, 0.5))
	var text: String = line.get("text", "")
	var visible_text := text.substr(0, int(_shown))
	_panel.draw_multiline_string(font, Vector2(x + 28, y + 86), visible_text, HORIZONTAL_ALIGNMENT_LEFT, w - 56, 28, 3, Color(0.96, 0.95, 0.9))
	if _shown >= text.length():
		var a := 0.5 + 0.5 * sin(_t * 4.0)
		_panel.draw_string(font, Vector2(x + w - 60, y + h - 18), "▼", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, a))
	if _lines.size() > 1:
		_panel.draw_string(font, Vector2(x + w - 110, y + 40), "%d / %d" % [_index + 1, _lines.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.35))

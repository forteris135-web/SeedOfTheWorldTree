extends CanvasLayer
class_name PauseMenu
## 일시정지와 설정. 메뉴 버튼(Esc / P / 옵션)으로 연다.

var _items := []   # {key, label}
var _index := 0
var _panel: Control
var _open := false
var _t := 0.0


func _ready() -> void:
	layer = 45
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
	_items = [
		{"key": "resume", "label": "계속하기"},
		{"key": "lenient_guard", "label": "저스트 가드 넉넉하게"},
		{"key": "sfx_volume", "label": "효과음 음량"},
		{"key": "touch_scale", "label": "터치 버튼 크기"},
		{"key": "screen_shake", "label": "화면 흔들림"},
		{"key": "debug_hud", "label": "개발 표시"},
		{"key": "music_volume", "label": "음악 음량"},
		{"key": "remap", "label": "키 · 버튼 바꾸기"},
		{"key": "save", "label": "지금 저장하기"},
		{"key": "load", "label": "불러오기"},
		{"key": "title", "label": "타이틀로"},
	]
	_index = 0
	_open = true
	_panel.visible = true
	get_tree().paused = true
	for n in ["CombatHUD", "TouchControls", "BossHUD"]:
		var h := get_tree().current_scene.get_node_or_null(n)
		if h:
			h.visible = false
	Sfx.play("select")


func close() -> void:
	_open = false
	_panel.visible = false
	get_tree().paused = false
	for n in ["CombatHUD", "TouchControls", "BossHUD"]:
		var h := get_tree().current_scene.get_node_or_null(n)
		if h:
			h.visible = true


func _process(delta: float) -> void:
	if _open:
		_t += delta
		_panel.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("dodge"):
		close()
	elif event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
		_index = (_index + 1) % _items.size()
		Sfx.play("blip")
	elif event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
		_index = (_index - 1 + _items.size()) % _items.size()
		Sfx.play("blip")
	elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		_adjust(1)
	elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		_adjust(-1)
	elif event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_activate()
	elif event is InputEventScreenTouch and event.pressed:
		var hit := _row_at(event.position)
		if hit >= 0:
			if hit == _index:
				_activate()
			else:
				_index = hit
				Sfx.play("blip")
		else:
			close()
	get_viewport().set_input_as_handled()


func _activate() -> void:
	var key: String = _items[_index]["key"]
	match key:
		"resume":
			close()
		"title":
			close()
			Game.go_to(Game.TITLE_SCENE, 0.6, 0.8)
		"save":
			var where := SaveGame.save_now()
			Sfx.play("select")
			var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
			if hud:
				hud.show_message("저장되었다 — 다음에는 '%s'에서 이어진다" % where, 3.0)
		"load":
			if not SaveGame.has_save():
				Sfx.play("blip")
				return
			close()
			var scene := SaveGame.load_game()
			Game.go_to(scene if scene != "" else Game.FIRST_ROOM, 0.8, 1.0)
		"remap":
			_panel.visible = false
			_open = false
			var rs := RemapScreen.new()
			add_child(rs)
			rs.open()
			await get_tree().process_frame
			while rs.is_open():
				await get_tree().process_frame
			rs.queue_free()
			_open = true
			_panel.visible = true
			get_tree().paused = true
		"lenient_guard", "screen_shake", "debug_hud":
			Settings.set_value(key, not Settings.get_value(key))
			Sfx.play("select")
		_:
			_adjust(1)


func _adjust(dir: int) -> void:
	var key: String = _items[_index]["key"]
	match key:
		"sfx_volume", "music_volume":
			Settings.set_value(key, clampi(int(Settings.get_value(key)) + dir, 0, 10))
			Sfx.play("select")
		"touch_scale":
			Settings.set_value(key, (int(Settings.get_value(key)) + dir + 3) % 3)
			Sfx.play("select")
		"lenient_guard", "screen_shake", "debug_hud":
			Settings.set_value(key, not Settings.get_value(key))
			Sfx.play("select")


func _value_text(key: String) -> String:
	match key:
		"lenient_guard", "screen_shake", "debug_hud":
			return "켬" if Settings.get_value(key) else "끔"
		"sfx_volume", "music_volume":
			var v := int(Settings.get_value(key))
			return "◀ " + "■".repeat(v) + "□".repeat(10 - v) + " ▶"
		"touch_scale":
			return "◀ " + ["작게", "보통", "크게"][int(Settings.get_value(key))] + " ▶"
		"save":
			return "이어질 곳: " + str(Progress.last_grass.get("name", "지금 방의 처음"))
		"load":
			var at := SaveGame.saved_at_text()
			return ("저장: " + at) if at != "" else "저장 없음"
	return ""


func _row_rect(i: int) -> Rect2:
	var size := _panel.size
	var w := 820.0
	return Rect2((size.x - w) / 2.0, size.y * 0.26 + i * 58.0, w, 52.0)


func _row_at(pos: Vector2) -> int:
	for i in _items.size():
		if _row_rect(i).has_point(pos):
			return i
	return -1


func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var size := _panel.size
	_panel.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.78))
	_panel.draw_string(font, Vector2(size.x / 2.0 - 400, size.y * 0.18), "잠시 멈춤", HORIZONTAL_ALIGNMENT_CENTER, 800, 40, Color(1.0, 0.9, 0.72))
	for i in _items.size():
		var r := _row_rect(i)
		var sel := i == _index
		_panel.draw_rect(r, Color(1.0, 0.86, 0.5, 0.16) if sel else Color(1, 1, 1, 0.05))
		var it: Dictionary = _items[i]
		_panel.draw_string(font, r.position + Vector2(20, 35), ("▸  " if sel else "    ") + it["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.86, 0.5) if sel else Color(0.9, 0.9, 0.9))
		var vt := _value_text(it["key"])
		if vt != "":
			_panel.draw_string(font, r.position + Vector2(r.size.x - 300, 35), vt, HORIZONTAL_ALIGNMENT_RIGHT, 280, 24, Color(0.56, 0.83, 1.0) if sel else Color(0.75, 0.8, 0.85))
	_panel.draw_string(font, Vector2(size.x / 2.0 - 400, size.y * 0.26 + _items.size() * 58.0 + 40.0), "위·아래로 고르고 좌·우로 바꾼다  ·  메뉴 / 회피: 닫기", HORIZONTAL_ALIGNMENT_CENTER, 800, 20, Color(1, 1, 1, 0.45))

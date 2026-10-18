extends CanvasLayer
class_name TravelMenu
## 달빛풀 이동 메뉴. 피워 둔 달빛풀끼리 뿌리로 이어져 있다 (기획서 8장 "빠른 이동").

signal closed

var _items: Array = []     # [{id, name, scene}]
var _index := 0
var _panel: Control
var _labels: Array[Label] = []
var _current_id := ""
var _open := false


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	_panel.draw.connect(_on_draw)
	add_child(_panel)


func open(current_grass_id: String) -> void:
	_current_id = current_grass_id
	_items.clear()
	for id in Progress.grasses:
		var g: Dictionary = Progress.grasses[id]
		_items.append({"id": id, "name": g.get("name", id), "scene": g.get("scene", "")})
	_items.sort_custom(func(a, b): return a["name"] < b["name"])
	_index = 0
	for i in _items.size():
		if _items[i]["id"] == _current_id:
			_index = i
	_open = true
	_panel.visible = true
	get_tree().paused = true
	_panel.queue_redraw()


func close() -> void:
	_open = false
	_panel.visible = false
	get_tree().paused = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
		_index = (_index + 1) % max(_items.size(), 1)
		_panel.queue_redraw()
	elif event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
		_index = (_index - 1 + _items.size()) % max(_items.size(), 1)
		_panel.queue_redraw()
	elif event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_choose(_index)
	elif event.is_action_pressed("dodge") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close()
	elif event is InputEventScreenTouch and event.pressed:
		var hit := _item_at(event.position)
		if hit >= 0:
			_choose(hit)
		elif event.position.y > _panel.size.y * 0.8:
			close()
	get_viewport().set_input_as_handled()


func _row_rect(i: int) -> Rect2:
	var size := _panel.size
	var w := 620.0
	var x := (size.x - w) / 2.0
	var y0 := size.y * 0.3
	return Rect2(x, y0 + i * 56.0, w, 50.0)


func _item_at(pos: Vector2) -> int:
	for i in _items.size():
		if _row_rect(i).has_point(pos):
			return i
	return -1


func _choose(i: int) -> void:
	if i < 0 or i >= _items.size():
		return
	var it: Dictionary = _items[i]
	if it["id"] == _current_id:
		close()
		return
	close()
	Progress.next_spawn = "Grass:" + it["id"]
	Game.go_to(it["scene"], 0.8, 1.0)


func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var size := _panel.size
	_panel.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	_panel.draw_string(font, Vector2(size.x / 2.0 - 400, size.y * 0.22), "뿌리를 따라 이동", HORIZONTAL_ALIGNMENT_CENTER, 800, 36, Color(0.56, 0.83, 1.0))
	_panel.draw_string(font, Vector2(size.x / 2.0 - 400, size.y * 0.22 + 34), "피워 둔 달빛풀로 갈 수 있다", HORIZONTAL_ALIGNMENT_CENTER, 800, 20, Color(1, 1, 1, 0.5))
	for i in _items.size():
		var r := _row_rect(i)
		var sel := i == _index
		_panel.draw_rect(r, Color(0.56, 0.83, 1.0, 0.18) if sel else Color(1, 1, 1, 0.06))
		var it: Dictionary = _items[i]
		var text: String = it["name"] + ("   (여기)" if it["id"] == _current_id else "")
		_panel.draw_string(font, r.position + Vector2(20, 34), ("▸  " if sel else "    ") + text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.86, 0.5) if sel else Color(0.9, 0.9, 0.9))
	_panel.draw_string(font, Vector2(size.x / 2.0 - 400, size.y * 0.86), "위·아래로 고르고 결정  ·  회피 / 메뉴: 닫기", HORIZONTAL_ALIGNMENT_CENTER, 800, 20, Color(1, 1, 1, 0.45))

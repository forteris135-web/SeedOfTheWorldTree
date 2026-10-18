extends CanvasLayer
class_name MapScreen
## 지도. 방문한 방들을 이어진 자리에 그리고, 지금 있는 방과 소녀의 위치, 달빛풀, 보스 방을 표시한다.
## 방의 자리는 Room.map_offset (세계 좌표 기준 방의 왼쪽 위), 크기는 Room.bounds.

signal closed

var _panel: Control
var _open := false
var _room: Room
var _t := 0.0

const REGION_COLORS := {"canopy": Color(0.36, 0.48, 0.3), "village": Color(0.6, 0.45, 0.25), "mine": Color(0.5, 0.3, 0.25), "abyss": Color(0.35, 0.28, 0.5)}


func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	_panel.draw.connect(_on_draw)
	add_child(_panel)


func open(room: Room) -> void:
	_room = room
	_open = true
	_panel.visible = true
	get_tree().paused = true
	_panel.queue_redraw()


func close() -> void:
	_open = false
	_panel.visible = false
	get_tree().paused = false
	closed.emit()


func _process(delta: float) -> void:
	if _open:
		_t += delta
		_panel.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("map") or event.is_action_pressed("pause") or event.is_action_pressed("dodge") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("jump"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch and event.pressed:
		close()
		get_viewport().set_input_as_handled()


func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var size := _panel.size
	_panel.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.88))
	_panel.draw_string(font, Vector2(60, 70), "지도", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(0.95, 0.9, 0.8))
	_panel.draw_string(font, Vector2(60, 104), "가 본 곳만 그려진다  ·  지도 / 회피 / 메뉴: 닫기", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.45))
	var rooms: Dictionary = Progress.visited_rooms
	if rooms.is_empty():
		return
	# 전체 범위
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for id in rooms:
		var r: Dictionary = rooms[id]
		var off: Vector2 = r["offset"]
		var sz: Vector2 = r["size"]
		mn = mn.min(off)
		mx = mx.max(off + sz)
	var span := mx - mn
	var area := Rect2(Vector2(80, 140), size - Vector2(160, 220))
	var scale := minf(area.size.x / maxf(span.x, 1.0), area.size.y / maxf(span.y, 1.0))
	scale = minf(scale, 0.11)
	var origin := area.position + (area.size - span * scale) / 2.0
	for id in rooms:
		var r: Dictionary = rooms[id]
		var off: Vector2 = r["offset"]
		var sz: Vector2 = r["size"]
		var rect := Rect2(origin + (off - mn) * scale, sz * scale)
		var base: Color = REGION_COLORS.get(r.get("region", "canopy"), Color(0.4, 0.4, 0.4))
		var current: bool = _room != null and id == _room.room_id
		_panel.draw_rect(rect, Color(base, 0.55 if current else 0.3))
		_panel.draw_rect(rect, Color(1.0, 0.86, 0.5, 0.95) if current else Color(1, 1, 1, 0.35), false, 3.0 if current else 1.5)
		_panel.draw_string(font, rect.position + Vector2(10, 26), r.get("name", id), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12, 18, Color(1, 1, 1, 0.85))
		for g in r.get("grasses", []):
			var gp: Vector2 = origin + (off + g - mn) * scale
			_panel.draw_circle(gp, 7.0, Color(0.56, 0.83, 1.0))
			_panel.draw_circle(gp, 11.0, Color(0.56, 0.83, 1.0, 0.25 + 0.15 * sin(_t * 3.0)))
		if r.get("boss", false):
			var c := rect.get_center()
			_panel.draw_string(font, c + Vector2(-20, 12), "☠", HORIZONTAL_ALIGNMENT_CENTER, 40, 30, Color(1.0, 0.75, 0.6, 0.9))
	# 소녀의 위치
	if _room and _room.player:
		var cur: Dictionary = rooms.get(_room.room_id, {})
		if not cur.is_empty():
			var p: Vector2 = origin + (cur["offset"] + _room.player.global_position - mn) * scale
			var pulse := 0.7 + 0.3 * sin(_t * 5.0)
			_panel.draw_circle(p, 14.0 * pulse, Color(1.0, 0.83, 0.42, 0.25))
			_panel.draw_circle(p, 6.0, Color(1.0, 0.83, 0.42))
			_panel.draw_string(font, p + Vector2(-40, -18), "셀레니아", HORIZONTAL_ALIGNMENT_CENTER, 80, 16, Color(1.0, 0.9, 0.7))

extends CanvasLayer
class_name MapScreen
## 지도. 방문한 방들을 이어진 자리에 그리고, 지금 있는 방과 소녀의 위치, 달빛풀, 보스 방을 표시한다.
## 방의 자리는 Room.map_offset (세계 좌표 기준 방의 왼쪽 위), 크기는 Room.bounds.

signal closed

var _panel: Control
var _open := false
var _room: Room
var _t := 0.0

## 지역 구분색. 방 채움이 아니라 왼쪽 가는 띠와 테두리에만 쓴다. (travel_menu.gd 도 이 이름으로 참조한다)
const REGION_COLORS := {"canopy": Color(0.36, 0.48, 0.3), "village": Color(0.6, 0.45, 0.25), "mine": Color(0.5, 0.3, 0.25), "abyss": Color(0.35, 0.28, 0.5)}
## 탐사 상태 채움색: 아직 찾을 것이 남은 방 = 연초록, 모두 찾은 방 = 청명한 하늘색.
const FILL_REMAIN := Color(0.62, 0.92, 0.45)
const FILL_DONE := Color(0.45, 0.82, 1.0)
## 글자 테두리(밝은 채움 위에서도 읽히게)
const OUTLINE := Color(0.02, 0.04, 0.08, 0.9)
const REGION_BAND := 6.0


## 방의 탐사 수치를 읽는다 → [찾은 수, 전체 수].
## 1) "explore_ids"(문자열 배열)가 있으면 지도가 그릴 때 직접 센다 — 방을 다시 들어가지 않아도 바로 바뀐다.
##    항목 형식: "grass:<grass_id>" 는 Progress.grasses 에서, 그 밖("read_<id>", "<id>_rescued", "secret_<id>" 등)은 Progress 깃발에서 찾는다.
## 2) 없으면 "explore_total"/"explore_found" 정수를 쓴다(없으면 0).
static func explore_counts(r: Dictionary) -> Array[int]:
	if r.has("explore_ids"):
		var raw = r["explore_ids"]
		var found := 0
		var total := 0
		if raw is Dictionary:
			# Room._collect_explore_ids 형식: {"pickups": [...], "rescues": [...], "records": [...], "grasses": [...]}
			for id in raw.get("pickups", []):
				total += 1
				if Progress.is_collected(str(id)):
					found += 1
			for id in raw.get("rescues", []):
				total += 1
				if Progress.rescued.has(str(id)):
					found += 1
			for id in raw.get("records", []):
				total += 1
				if Progress.has("read_" + str(id)):
					found += 1
			for id in raw.get("grasses", []):
				total += 1
				if Progress.grasses.has(str(id)):
					found += 1
			return [found, total]
		elif raw is Array:
			for key in raw:
				var k := str(key)
				total += 1
				if k.begins_with("grass:"):
					if Progress.grasses.has(k.substr(6)):
						found += 1
				elif Progress.has(k):
					found += 1
			return [found, total]
	return [int(r.get("explore_found", 0)), int(r.get("explore_total", 0))]


## 채움색 규칙: 찾은 수 < 전체 수 → 연초록(FILL_REMAIN), 아니면 하늘색(FILL_DONE). 값이 없는 방(0/0)은 다 찾은 것으로 본다.
static func explore_fill(r: Dictionary) -> Color:
	var counts := explore_counts(r)
	return FILL_REMAIN if counts[0] < counts[1] else FILL_DONE


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
	_panel.draw_string(font, Vector2(60, 104), "가 본 곳만 그려진다  ·  ● 달빛풀  ◆ 포탈  ☠ 수호자  ·  지도 / 회피 / 메뉴 / 화면 누르기: 닫기", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.45))
	_draw_legend(font, Vector2(60, 132))
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
	var area := Rect2(Vector2(80, 164), size - Vector2(160, 244))
	var scale := minf(area.size.x / maxf(span.x, 1.0), area.size.y / maxf(span.y, 1.0))
	scale = minf(scale, 0.11)
	var origin := area.position + (area.size - span * scale) / 2.0
	for id in rooms:
		var r: Dictionary = rooms[id]
		var off: Vector2 = r["offset"]
		var sz: Vector2 = r["size"]
		var rect := Rect2(origin + (off - mn) * scale, sz * scale)
		var region_color: Color = REGION_COLORS.get(r.get("region", "canopy"), Color(0.4, 0.4, 0.4))
		var current: bool = _room != null and id == _room.room_id
		# 탐사 상태: 아직 찾을 것이 남았으면 연초록, 다 찾았으면 하늘색 (값이 없으면 0/0 → 다 찾은 것으로 본다)
		var counts := explore_counts(r)
		var found: int = counts[0]
		var total: int = counts[1]
		var fill := explore_fill(r)
		var done: bool = fill == FILL_DONE
		_panel.draw_rect(rect, Color(fill, 0.72 if current else 0.5))
		# 왼쪽 가는 띠로 지역 구분
		var band := Rect2(rect.position, Vector2(minf(REGION_BAND, rect.size.x), rect.size.y))
		_panel.draw_rect(band, Color(region_color.lightened(0.15), 0.95))
		# 테두리: 지금 있는 방은 금빛, 나머지는 지역색
		_panel.draw_rect(rect, Color(1.0, 0.86, 0.5, 0.95) if current else Color(region_color.lightened(0.35), 0.8), false, 3.0 if current else 1.5)
		var name_pos := rect.position + Vector2(10 + REGION_BAND, 26)
		var name_w := rect.size.x - 12 - REGION_BAND
		_panel.draw_string_outline(font, name_pos, r.get("name", id), HORIZONTAL_ALIGNMENT_LEFT, name_w, 18, 4, OUTLINE)
		_panel.draw_string(font, name_pos, r.get("name", id), HORIZONTAL_ALIGNMENT_LEFT, name_w, 18, Color(1, 1, 1, 0.92))
		var marks: Array[Vector2] = []  # 표식(달빛풀·포탈) 자리 — 숫자가 겹치지 않게 피하려고 모아 둔다
		for g in r.get("grasses", []):
			var gp: Vector2 = origin + (off + g - mn) * scale
			marks.append(gp)
			_panel.draw_circle(gp, 7.0, Color(0.56, 0.83, 1.0))
			_panel.draw_circle(gp, 11.0, Color(0.56, 0.83, 1.0, 0.25 + 0.15 * sin(_t * 3.0)))
		for pp in r.get("portals", []):
			var c: Vector2 = origin + (off + pp - mn) * scale
			marks.append(c)
			var d := 9.0
			var gold := Color(1.0, 0.86, 0.5)
			_panel.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), gold)
			_panel.draw_polyline(PackedVector2Array([c + Vector2(0, -d - 4), c + Vector2(d + 4, 0), c + Vector2(0, d + 4), c + Vector2(-d - 4, 0), c + Vector2(0, -d - 4)]), Color(gold, 0.3 + 0.2 * sin(_t * 3.0 + 1.0)), 2.0)
		if r.get("boss", false):
			var c := rect.get_center()
			_panel.draw_string_outline(font, c + Vector2(-20, 12), "☠", HORIZONTAL_ALIGNMENT_CENTER, 40, 30, 5, OUTLINE)
			_panel.draw_string(font, c + Vector2(-20, 12), "☠", HORIZONTAL_ALIGNMENT_CENTER, 40, 30, Color(1.0, 0.75, 0.6, 0.95))
		# 찾은 수 / 전체 수 (찾을 것이 있는 방만), 오른쪽 아래 작은 글씨. 표식 뒤에 그려 맨 위에 올리고,
		# 포탈·달빛풀 표식과 가까우면 20px 위로 올려 피한다. 글자 뒤에는 작은 어두운 바탕.
		if total > 0:
			var count_text := "%d/%d" % [found, total]
			var count_w := font.get_string_size(count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var count_pos := rect.end - Vector2(count_w + 8, 7)
			var count_box := Rect2(count_pos + Vector2(-3, -13), Vector2(count_w + 6, 17))
			for _try in 3:
				var hit := false
				for m in marks:
					if count_box.grow(16.0).has_point(m):
						hit = true
						break
				if not hit:
					break
				count_pos.y -= 20.0
				count_box.position.y -= 20.0
			_panel.draw_rect(count_box, Color(OUTLINE, 0.7))
			_panel.draw_string_outline(font, count_pos, count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, OUTLINE)
			_panel.draw_string(font, count_pos, count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.75, 0.95, 1.0) if done else Color(0.9, 1.0, 0.75))
	# 소녀의 위치
	if _room and _room.player:
		var cur: Dictionary = rooms.get(_room.room_id, {})
		if not cur.is_empty():
			var p: Vector2 = origin + (cur["offset"] + _room.player.global_position - mn) * scale
			var pulse := 0.7 + 0.3 * sin(_t * 5.0)
			_panel.draw_circle(p, 14.0 * pulse, Color(1.0, 0.83, 0.42, 0.25))
			_panel.draw_circle(p, 6.0, Color(1.0, 0.83, 0.42))
			_panel.draw_string_outline(font, p + Vector2(-40, -18), "셀레니아", HORIZONTAL_ALIGNMENT_CENTER, 80, 16, 4, OUTLINE)
			_panel.draw_string(font, p + Vector2(-40, -18), "셀레니아", HORIZONTAL_ALIGNMENT_CENTER, 80, 16, Color(1.0, 0.9, 0.7))


## 색 범례: 연초록 = 아직 찾을 것이 남음, 하늘색 = 모두 찾음. 작은 색 네모 뒤에 글을 쓴다.
func _draw_legend(font: Font, pos: Vector2) -> void:
	var x := pos.x
	var items := [[FILL_REMAIN, "아직 찾을 것이 남음"], [FILL_DONE, "모두 찾음"]]
	for item in items:
		var c: Color = item[0]
		var text: String = item[1]
		var box := Rect2(Vector2(x, pos.y - 15), Vector2(18, 18))
		_panel.draw_rect(box, Color(c, 0.4))
		_panel.draw_rect(box, Color(c, 0.9), false, 1.5)
		_panel.draw_string(font, Vector2(x + 26, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.55))
		x += 26 + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 34
	_panel.draw_string(font, Vector2(x, pos.y), "오른쪽 아래 숫자 = 찾은 수 / 전체", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.35))

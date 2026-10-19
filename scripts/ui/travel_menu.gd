extends CanvasLayer
class_name TravelMenu
## 이동 메뉴 (기획서 8장 "빠른 이동"): 피워 둔 달빛풀끼리 뿌리로 이어져 있다. 쉬는 중에 손길 버튼으로 연다.
## 지역 순(수관 → 마을 → 채굴장 → 심연)으로 늘어놓고, 위·아래 / 터치로 고른다.
## (옆 방으로 가는 포탈은 메뉴가 아니라 Portal 이 바로 건너간다.)

signal closed

const REGION_ORDER := {"canopy": 0, "village": 1, "sap_lake": 2, "mine": 3, "flooded_mine": 4, "abyss": 5}
const REGION_NAMES := {"canopy": "수관", "village": "마을", "sap_lake": "수액의 호수", "mine": "채굴장", "flooded_mine": "잠긴 채굴장", "abyss": "심연"}

var _kind := "grass"          # grass / portal
var _title := ""
var _subtitle := ""
var _empty_hint := ""
var _items: Array = []        # [{id, name, scene, region}]
var _index := 0
var _panel: Control
var _current_id := ""
var _open := false
## 스틱 위·아래: 한 번 밀기 = 한 칸 (StickLatch)
var _stick_v := StickLatch.new()


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	_panel.draw.connect(_on_draw)
	add_child(_panel)


func is_open() -> bool:
	return _open


## 달빛풀 목록 (쉬는 중).
func open(current_grass_id: String) -> void:
	var items: Array = []
	for id in Progress.grasses:
		var g: Dictionary = Progress.grasses[id]
		var scene: String = g.get("scene", "")
		items.append({"id": id, "name": g.get("name", id), "scene": scene, "region": g.get("region", region_of_scene(scene))})
	_open_list("grass", "뿌리를 따라 이동", "피워 둔 달빛풀로 갈 수 있다", "아직 다른 달빛풀을 피우지 않았다. 달빛풀에 손을 대어 두면 여기서 이어진다.", items, current_grass_id)


func _open_list(kind: String, title: String, subtitle: String, empty_hint: String, items: Array, current_id: String) -> void:
	_kind = kind
	_title = title
	_subtitle = subtitle
	_empty_hint = empty_hint
	_current_id = current_id
	_items = items
	_items.sort_custom(func(a, b):
		var ra: int = REGION_ORDER.get(a["region"], 9)
		var rb: int = REGION_ORDER.get(b["region"], 9)
		if ra != rb:
			return ra < rb
		return a["name"] < b["name"])
	_index = 0
	for i in _items.size():
		if _items[i]["id"] == _current_id:
			_index = i
	_open = true
	_stick_v.reset()
	_panel.visible = true
	get_tree().paused = true
	_panel.queue_redraw()


func close() -> void:
	_open = false
	_panel.visible = false
	get_tree().paused = false
	closed.emit()


## 방 경로에서 지역을 알아낸다 (옛 세이브에는 지역이 없다).
static func region_of_scene(scene: String) -> String:
	var file := scene.get_file().get_basename()
	if file.begins_with("moon_"):
		return "abyss"
	# 긴 이름(flooded_mine, sap_lake)을 먼저 본다 (mine 보다 앞에)
	for r in ["flooded_mine", "sap_lake", "canopy", "village", "mine", "abyss"]:
		if file.begins_with(r):
			return r
	return "canopy"


func _input(event: InputEvent) -> void:
	if not _open:
		return
	_handle_event(event)
	# 손가락 떼기는 터치 버튼(TouchControls)에도 흘려보낸다: 메뉴를 연 '이동' 버튼의 손가락을 메뉴가 삼키면
	# 손길(interact)이 눌린 채 남아, 패드·키로 닫은 뒤 다음 터치 한 번이 먹힌다. (떼기로 메뉴가 하는 일은 없다)
	if event is InputEventScreenTouch and not event.pressed:
		return
	get_viewport().set_input_as_handled()


## 입력 하나를 처리한다 (하위 메뉴 GrassMenu 가 가로채어 탭 바꾸기 등을 덧붙인다).
func _handle_event(event: InputEvent) -> void:
	if _stick_v.feed(event, ["move_up", "ui_up"], ["move_down", "ui_down"]):
		if _stick_v.step != 0:
			_move(_stick_v.step)
		return
	if event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
		_move(1)
	elif event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
		_move(-1)
	elif event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_choose(_index)
	elif event.is_action_pressed("dodge") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("map"):
		close()
	elif event is InputEventScreenTouch and event.pressed:
		var hit := _item_at(event.position)
		if hit >= 0:
			_choose(hit)
		else:
			close()


## 고른 줄을 dir(+1 아래 / -1 위)만큼 옮긴다 (끝에서 반대쪽으로 돈다).
func _move(dir: int) -> void:
	var n := maxi(_items.size(), 1)
	_index = (_index + dir + n) % n
	Sfx.play("blip")
	_panel.queue_redraw()


func _row_height() -> float:
	var n := maxi(_items.size(), 1)
	return clampf(floorf(_panel.size.y * 0.58 / n), 36.0, 56.0)


## 목록이 시작하는 높이 (하위 메뉴가 탭 머리 아래로 내릴 수 있다)
func _list_top() -> float:
	return _panel.size.y * 0.27


func _row_rect(i: int) -> Rect2:
	var size := _panel.size
	var w := 720.0
	var x := (size.x - w) / 2.0
	var y0 := _list_top()
	var rh := _row_height()
	return Rect2(x, y0 + i * rh, w, rh - 5.0)


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
	Sfx.play("select")
	Progress.next_spawn = ("Grass:" if _kind == "grass" else "Portal:") + it["id"]
	Game.go_to(it["scene"], 0.8, 1.0)


func _accent() -> Color:
	return Color(0.56, 0.83, 1.0) if _kind == "grass" else Color(1.0, 0.86, 0.5)


## 그리기는 네 조각으로 나눠 하위 메뉴가 조각마다 바꿔 끼울 수 있게 했다.
func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	_panel.draw_rect(Rect2(Vector2.ZERO, _panel.size), Color(0, 0, 0, 0.62))
	_draw_title(font)
	_draw_list(font)
	_draw_hint(font)


func _draw_title(font: Font) -> void:
	var size := _panel.size
	_panel.draw_string(font, Vector2(size.x / 2.0 - 400, size.y * 0.19), _title, HORIZONTAL_ALIGNMENT_CENTER, 800, 36, _accent())
	_panel.draw_string(font, Vector2(size.x / 2.0 - 400, size.y * 0.19 + 34), _subtitle, HORIZONTAL_ALIGNMENT_CENTER, 800, 20, Color(1, 1, 1, 0.5))


func _draw_list(font: Font) -> void:
	var size := _panel.size
	var accent := _accent()
	var rh := _row_height()
	var font_size := 26 if rh >= 50.0 else 22
	for i in _items.size():
		var r := _row_rect(i)
		var sel := i == _index
		var it: Dictionary = _items[i]
		_panel.draw_rect(r, Color(accent, 0.18) if sel else Color(1, 1, 1, 0.06))
		var region: String = it.get("region", "canopy")
		var rc: Color = MapScreen.REGION_COLORS.get(region, Color(0.4, 0.4, 0.4))
		_panel.draw_rect(Rect2(r.position + Vector2(12, 10), Vector2(8, r.size.y - 20)), rc.lightened(0.25))
		var baseline := r.position.y + r.size.y / 2.0 + font_size * 0.36
		_panel.draw_string(font, Vector2(r.position.x + 32, baseline), REGION_NAMES.get(region, ""), HORIZONTAL_ALIGNMENT_LEFT, 90, font_size - 6, Color(1, 1, 1, 0.5))
		var text: String = it["name"] + ("   (여기)" if it["id"] == _current_id else "")
		_panel.draw_string(font, Vector2(r.position.x + 120, baseline), ("▸  " if sel else "    ") + text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, accent if sel else Color(0.9, 0.9, 0.9))
	if _items.size() <= 1:
		_panel.draw_string(font, Vector2(size.x / 2.0 - 400, _list_top() + _items.size() * rh + 40), _empty_hint, HORIZONTAL_ALIGNMENT_CENTER, 800, 22, Color(1, 1, 1, 0.55))


## 아래 안내 줄의 글자 (안내는 메뉴 안에만 둔다)
func _hint_text() -> String:
	return "위·아래로 고르고 결정 (터치: 줄을 누르기)  ·  회피 / 메뉴 / 바깥 누르기: 닫기"


func _draw_hint(font: Font) -> void:
	var size := _panel.size
	_panel.draw_string(font, Vector2(size.x / 2.0 - 500, size.y - 70), _hint_text(), HORIZONTAL_ALIGNMENT_CENTER, 1000, 20, Color(1, 1, 1, 0.45))

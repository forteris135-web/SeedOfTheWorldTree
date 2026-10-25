extends CanvasLayer
class_name SlotPicker
## 저장 칸 고르기 (v1.1.0, 타이틀의 '이어하기'·'새로 시작'이 연다). 칸 세 개를 카드로 늘어놓는다.
## - "load"(이어하기): 찬 칸만 고를 수 있다 (빈 칸은 흐리게, 건너뛴다). 고르면 chosen(칸 번호).
## - "new"(새로 시작): 세 칸 모두. 찬 칸은 한 번 더 눌러야 고른다 ("한 번 더 누르면 이 칸의 저장이 지워집니다").
## - 칸 지우기 (두 모드 모두, 두 번 확인): 키보드 X / Delete, 패드 △ / Y, 터치 길게 누르기 (마우스는 오른쪽 단추도).
##   지우기 전에 그 칸의 클리어 기록은 메타(MetaSave)에 옮겨지므로 보스 러시·음악 감상은 남는다 (SaveGame.delete_slot).
## - 돌아가기: 맨 아래 줄, 또는 Esc·회피·메뉴·취소, 터치는 카드 바깥 누르기 → closed.
## 카드 한 장: 칸 번호 | 이어질 곳 (방 이름) / 난이도 · 저장한 때 | ✦ 클리어.
## 글자는 data/dialogue/slots.json (DifficultyPicker·PauseMenu 도 text() 로 같은 파일을 읽는다).

signal chosen(slot: int)
signal closed
signal deleted(slot: int)

const DATA_PATH := "res://data/dialogue/slots.json"
const CARD_W := 1120.0
const CARD_H := 148.0
const CARD_GAP := 24.0
const BACK_W := 360.0
const BACK_H := 58.0
## 이만큼 누르고 있으면 칸 지우기 (터치·마우스)
const LONG_PRESS := 0.6
## 지우기 확인을 건 뒤 이 시간 안의 두 번째 누름은 받지 않는다 (△ 를 결정 버튼처럼 연타해 저장을 지우는 일이 없게)
const DELETE_CONFIRM_DELAY := 0.45
## 칸 지우기 버튼(X·Delete·Backspace·△/Y)이 이 동작들에 묶여 있으면 지우기가 아니라 그 동작으로 받는다 (키·버튼 바꾸기)
const NAV_ACTIONS := ["jump", "dodge", "pause", "move_up", "move_down", "ui_accept", "ui_cancel", "ui_up", "ui_down"]
## 난이도별 글자 색 (카드의 난이도 이름)
const DIFF_COLOR := {"easy": Color(0.62, 0.9, 0.62), "normal": Color(0.82, 0.86, 0.92), "hard": Color(1.0, 0.72, 0.42), "nightmare": Color(1.0, 0.5, 0.6)}

## "load" / "new"
var mode := "load"
## 고른 줄: 0~2 = 칸 1~3, 3 = 돌아가기
var _index := 0
## 새로 시작: 한 번 눌러 덮어쓰기를 확인 중인 줄 (-1 없음)
var _confirm := -1
## 칸 지우기를 확인 중인 줄 (-1 없음)
var _delete_armed := -1
## 지우기 확인을 길게 누르기로 걸었는가 (안내 글자가 달라진다)
var _delete_by_touch := false
## 지우기 확인을 건 때 (_t)
var _delete_armed_at := 0.0
var _summaries: Array = []
var _open := false
var _t := 0.0
var _panel: Control
## 누르고 있는 손가락·마우스: {"row", "pos", "t0", "long"} (비었으면 누르고 있지 않음)
var _press := {}
var _notice := ""
var _notice_t := 0.0

static var _texts := {}


## 글자 하나 (data/dialogue/slots.json). {이름} 자리를 args 로 채운다.
static func text(key: String, args := {}) -> String:
	if _texts.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_texts = d if d is Dictionary else {}
	var s := str(_texts.get(key, key))
	return s.format(args) if not args.is_empty() else s


func _ready() -> void:
	layer = 44
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	_panel.draw.connect(_on_draw)
	add_child(_panel)


func is_open() -> bool:
	return _open


## 연다. how = "load" / "new", start = 처음 고를 칸 번호 (1~3, 0 이면 알아서: 이어하기 = 가장 늦게 저장한 칸, 새로 시작 = 첫 빈 칸)
func open(how: String, start := 0) -> void:
	mode = how
	refresh()
	_confirm = -1
	_delete_armed = -1
	_press = {}
	_notice = ""
	var i := start - 1
	if i < 0 or i > 2:
		i = _default_index()
	_index = i if selectable(i) else _next_selectable(i, 1)
	_open = true
	_panel.visible = true
	Sfx.play("select")


func close() -> void:
	if not _open and not _panel.visible:
		return
	_open = false
	_panel.visible = false
	_press = {}
	Sfx.play("blip")
	closed.emit()


## 고른 뒤 화면은 그대로 두고 입력만 멈춘다 (타이틀이 바로 장면을 바꾸거나 난이도 고르기를 위에 연다)
func hold() -> void:
	_open = false
	_press = {}


## 화면을 숨긴다 (난이도 고르기가 열려 있는 동안). 다시 보이려면 open().
func hide_panel() -> void:
	_open = false
	_panel.visible = false
	_press = {}


func refresh() -> void:
	_summaries.clear()
	for i in range(1, SaveGame.SLOT_COUNT + 1):
		_summaries.append(SaveGame.summary_of(i))


func summary(i: int) -> Dictionary:
	return _summaries[i] if i >= 0 and i < _summaries.size() else {}


## 시험용: 지금 고른 줄 (0~2 칸, 3 돌아가기)
func selected() -> int:
	return _index


func back_index() -> int:
	return SaveGame.SLOT_COUNT


## 덮어쓰기 확인 중인 줄 / 지우기 확인 중인 줄 (시험용)
func confirming() -> int:
	return _confirm


func delete_armed() -> int:
	return _delete_armed


func selectable(i: int) -> bool:
	if i == back_index():
		return true
	if i < 0 or i >= _summaries.size():
		return false
	return mode == "new" or bool(_summaries[i].get("exists", false))


func _default_index() -> int:
	if mode == "load":
		var l := SaveGame.latest_slot()
		return l - 1 if l > 0 else back_index()
	for i in _summaries.size():
		if not bool(_summaries[i].get("exists", false)):
			return i
	# 모두 차 있으면 가장 오래전에 저장한 칸 (지금 이어 하던 칸을 덮어쓰지 않게)
	var oldest := 0
	for i in _summaries.size():
		if str(_summaries[i].get("saved_at", "")) < str(_summaries[oldest].get("saved_at", "")):
			oldest = i
	return oldest


func _next_selectable(from: int, dir: int) -> int:
	var n := back_index() + 1
	var i := from
	for k in n:
		i = (i + dir + n) % n
		if selectable(i):
			return i
	return back_index()


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	_t += delta
	if _notice_t > 0.0:
		_notice_t -= delta
	# 길게 누르기 → 칸 지우기
	if _open and not _press.is_empty() and not _press["long"] and _t - float(_press["t0"]) >= LONG_PRESS:
		_press["long"] = true
		var row: int = _press["row"]
		if row >= 0 and row < back_index():
			_index = row
			delete_request(row, true)
	_panel.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	# 칸 지우기: 패드 △/Y 는 '손길'(결정)과 같은 버튼이라 먼저 본다.
	# 단, 키·버튼 바꾸기로 점프(결정)·회피(돌아가기)·위아래·메뉴에 옮겨 단 버튼이면 지우기가 아니라 그 동작 (_is_nav_action)
	if ((event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y) \
			or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_X, KEY_DELETE, KEY_BACKSPACE])) \
			and not _is_nav_action(event):
		delete_request(_index)
	elif event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("dodge"):
		cancel()
	elif event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
		_move(1)
	elif event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
		_move(-1)
	elif event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		activate(_index)
	elif event.device != InputEvent.DEVICE_ID_EMULATION:
		_pointer(event)
	get_viewport().set_input_as_handled()


## 칸 고르기의 결정·돌아가기·위아래 동작에 묶인 입력인가 ('손길'은 빼고 — 패드 △/Y 는 기본으로 손길이자 칸 지우기)
func _is_nav_action(event: InputEvent) -> bool:
	for a in NAV_ACTIONS:
		if event.is_action(a):
			return true
	return false


## 터치·마우스 (흉내 낸 사건은 건너뛴다 — 누름 한 번이 두 번 처리되지 않게, MusicRoom 과 같은 규칙)
func _pointer(event: InputEvent) -> void:
	var pressed := false
	var released := false
	var pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		if event.index != 0:
			return
		pressed = event.pressed
		released = not event.pressed
		pos = event.position
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var r := _hit_at(event.position)
			if r >= 0 and r < back_index():
				_index = r
				delete_request(r)
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		pressed = event.pressed
		released = not event.pressed
		pos = event.position
	else:
		return
	if pressed:
		var row := _hit_at(pos)
		_press = {"row": row, "pos": pos, "t0": _t, "long": false}
		if row >= 0 and selectable(row) and row != _index:
			_select(row)
	elif released and not _press.is_empty():
		var p := _press
		_press = {}
		if p["long"]:
			return
		var row := _hit_at(pos)
		if row != int(p["row"]):
			return   # 누른 곳과 뗀 곳이 다르면 아무것도 하지 않는다 (밀어서 취소)
		if row < 0:
			cancel()   # 카드 바깥 누르기 = 돌아가기 (확인 중이면 확인만 거둔다)
		else:
			activate(row)


func _select(i: int) -> void:
	if i == _index:
		return
	_index = i
	_confirm = -1
	_delete_armed = -1
	Sfx.play("blip", -6.0)


func _move(dir: int) -> void:
	_select(_next_selectable(_index, dir))


## 줄 i 를 결정 (시험도 부른다)
func activate(i: int) -> void:
	if not _open:
		return
	if i == back_index():
		close()
		return
	if not selectable(i):
		Sfx.play("blip")
		return
	if _delete_armed >= 0:
		# 지우기 확인 중에 결정을 누르면 확인만 거둔다 (실수로 불러오거나 덮어쓰지 않게)
		_delete_armed = -1
		_index = i
		Sfx.play("blip")
		return
	_index = i
	var filled := bool(_summaries[i].get("exists", false))
	if mode == "new" and filled and _confirm != i:
		_confirm = i
		Sfx.play("blip")
		return
	_confirm = -1
	hold()
	Sfx.play("select")
	chosen.emit(i + 1)


## 칸 지우기 요청 (두 번 확인). by_touch = 길게 누르기로 (안내 글자만 다르다). 시험도 부른다.
func delete_request(i: int, by_touch := false) -> void:
	if not _open:
		return
	if i < 0 or i >= back_index() or not bool(_summaries[i].get("exists", false)):
		Sfx.play("blip")
		return
	_confirm = -1
	if _delete_armed != i:
		_delete_armed = i
		_delete_by_touch = by_touch
		_delete_armed_at = _t
		_index = i
		Sfx.play("blip")
		return
	if _t - _delete_armed_at < DELETE_CONFIRM_DELAY:
		return   # 너무 빠른 두 번째 누름 (연타) — 확인 글자를 읽을 틈을 둔다
	_delete_armed = -1
	SaveGame.delete_slot(i + 1)
	refresh()
	_notice = text("deleted", {"n": i + 1})
	_notice_t = 2.2
	Sfx.play("select")
	deleted.emit(i + 1)
	if not selectable(_index):
		if mode == "load" and not SaveGame.any_save():
			close()
			return
		_index = _next_selectable(_index, 1)


## 돌아가기 (확인 중이면 확인만 거둔다)
func cancel() -> void:
	if _delete_armed >= 0 or _confirm >= 0:
		_delete_armed = -1
		_confirm = -1
		Sfx.play("blip")
		return
	close()


# ---------- 자리 ----------

func _block_h() -> float:
	return 130.0 + back_index() * (CARD_H + CARD_GAP) + 30.0 + BACK_H + 90.0


func _top() -> float:
	return maxf(30.0, (_panel.size.y - _block_h()) / 2.0)


func card_rect(i: int) -> Rect2:
	var w := minf(CARD_W, _panel.size.x - 64.0)
	return Rect2((_panel.size.x - w) / 2.0, _top() + 130.0 + i * (CARD_H + CARD_GAP), w, CARD_H)


func back_rect() -> Rect2:
	var y := _top() + 130.0 + back_index() * (CARD_H + CARD_GAP) + 30.0
	return Rect2((_panel.size.x - BACK_W) / 2.0, y, BACK_W, BACK_H)


func _hit_at(pos: Vector2) -> int:
	for i in back_index():
		if card_rect(i).has_point(pos):
			return i
	if back_rect().has_point(pos):
		return back_index()
	return -1


# ---------- 그리기 ----------

func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var size := _panel.size
	var gold := Color(1.0, 0.86, 0.5)
	# 완전히 가린다 (뒤의 타이틀 글자는 발광이라 조금만 비쳐도 눈에 띈다 — MusicRoom 과 같은 이유)
	_panel.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 1.0))
	var top := _top()
	_panel.draw_string(font, Vector2(0, top + 56), text("title_load" if mode == "load" else "title_new"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 46, Color(1.0, 0.9, 0.72))
	_panel.draw_string(font, Vector2(0, top + 100), text("sub_load" if mode == "load" else "sub_new"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(0.85, 0.85, 0.9, 0.7))
	for i in back_index():
		_draw_card(font, i, gold)
	# 돌아가기
	var br := back_rect()
	var bsel := _index == back_index()
	_panel.draw_rect(br, Color(1.0, 0.86, 0.5, 0.17) if bsel else Color(1, 1, 1, 0.05))
	_panel.draw_string(font, br.position + Vector2(0, 39), ("▸  " if bsel else "") + text("back"), HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 28, gold if bsel else Color(0.9, 0.9, 0.9))
	# 알림 (지웠다) · 안내
	if _notice_t > 0.0 and _notice != "":
		_panel.draw_string(font, Vector2(0, br.end.y + 44), _notice, HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(1.0, 0.8, 0.6, clampf(_notice_t, 0.0, 1.0)))
	_panel.draw_string(font, Vector2(0, br.end.y + 82), hint_text(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(1, 1, 1, 0.45))


func _draw_card(font: Font, i: int, gold: Color) -> void:
	var r := card_rect(i)
	var s: Dictionary = _summaries[i] if i < _summaries.size() else {}
	var exists := bool(s.get("exists", false))
	var sel := i == _index
	var dim := not selectable(i)
	var a := 0.35 if dim else 1.0
	var warn := _delete_armed == i or _confirm == i
	var bg := Color(1.0, 0.86, 0.5, 0.15) if sel else Color(1, 1, 1, 0.05)
	if warn:
		bg = Color(1.0, 0.45, 0.35, 0.16)
	_panel.draw_rect(r, bg)
	if sel:
		_panel.draw_rect(r, Color(1.0, 0.5, 0.4, 0.8) if warn else Color(gold, 0.7), false, 2.0)
	# 칸 번호
	var label_col := (gold if sel else Color(0.92, 0.92, 0.95)) * Color(1, 1, 1, a)
	_panel.draw_string(font, Vector2(r.position.x + 24, r.position.y + r.size.y / 2.0 + 15), ("▸ " if sel else "  ") + text("slot_label", {"n": i + 1}), HORIZONTAL_ALIGNMENT_LEFT, 190, 38, label_col)
	var x := r.position.x + 230.0
	_panel.draw_line(Vector2(x - 24, r.position.y + 22), Vector2(x - 24, r.end.y - 22), Color(1, 1, 1, 0.12 * a), 1.5)
	var w := r.end.x - x - 28.0
	if not exists:
		var ec := Color(0.95, 0.9, 0.8, 0.95) if sel else Color(0.7, 0.72, 0.76, 0.75 * a)
		_panel.draw_string(font, Vector2(x, r.position.y + r.size.y / 2.0 + 11), text("empty" if mode == "load" else "empty_new"), HORIZONTAL_ALIGNMENT_LEFT, w, 30, ec)
		return
	var place := str(s.get("place", ""))
	if place == "":
		place = text("place_start")
	elif place == "?":
		place = text("broken")
	var badge_w := 0.0
	if bool(s.get("cleared", false)):
		var badge := text("cleared")
		badge_w = font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 16.0
		_panel.draw_string(font, Vector2(r.end.x - 28 - badge_w + 16, r.position.y + 58), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.85, 0.45, a))
	_panel.draw_string(font, Vector2(x, r.position.y + 60), place, HORIZONTAL_ALIGNMENT_LEFT, w - badge_w, 34, Color(1, 1, 1, 0.96 * a))
	if warn:
		var wt := text("confirm_overwrite") if _confirm == i else text("confirm_delete_touch" if _delete_by_touch else "confirm_delete", {"n": i + 1})
		var pulse := 0.8 + 0.2 * sin(_t * 5.0)
		_panel.draw_string(font, Vector2(x, r.position.y + 110), wt, HORIZONTAL_ALIGNMENT_LEFT, w, 25, Color(1.0, 0.62, 0.5, pulse))
		return
	var diff := str(s.get("difficulty", "normal"))
	var dname := str(Balance.DIFF_NAME.get(diff, "Normal"))
	_panel.draw_string(font, Vector2(x, r.position.y + 110), dname, HORIZONTAL_ALIGNMENT_LEFT, -1, 25, DIFF_COLOR.get(diff, Color.WHITE) * Color(1, 1, 1, a))
	var dw := font.get_string_size(dname, HORIZONTAL_ALIGNMENT_LEFT, -1, 25).x
	var at := str(s.get("saved_at_text", ""))
	if at != "":
		_panel.draw_string(font, Vector2(x + dw, r.position.y + 110), "   ·   " + at, HORIZONTAL_ALIGNMENT_LEFT, w - dw, 25, Color(0.72, 0.8, 0.88, 0.9 * a))


func hint_text() -> String:
	match InputDevice.current:
		InputDevice.Kind.TOUCH:
			return text("hint_touch")
		InputDevice.Kind.DUALSENSE:
			return text("hint_ds", {"ok": InputDevice.prompt("jump"), "back": InputDevice.prompt("dodge")})
		InputDevice.Kind.XBOX, InputDevice.Kind.OTHER_PAD:
			return text("hint_xb", {"ok": InputDevice.prompt("jump"), "back": InputDevice.prompt("dodge")})
	return text("hint_kb", {"ok": InputDevice.prompt("jump")})

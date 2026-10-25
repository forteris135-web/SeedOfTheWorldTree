extends CanvasLayer
class_name DifficultyPicker
## 난이도 고르기 (v1.1.0, 타이틀의 '새로 시작' → 칸 고르기 다음). 네 줄: Easy · Normal · Hard · Nightmare (기본 Normal).
## 이름과 설명은 Balance.DIFF_NAME / DIFF_DESC (숫자의 단일 출처), 그 밖의 글자는 data/dialogue/slots.json.
## 고르면 chosen(난이도 id), 돌아가기(맨 아래 줄 · Esc · 회피 · 메뉴 · 취소 · 터치로 바깥 누르기)면 canceled → 타이틀이 칸 고르기로 되돌린다.
## 모든 난이도에서 탐험과 엔딩은 같다. 일시정지 메뉴에서 언제든 바꿀 수 있다 (명세 D8).

signal chosen(difficulty: String)
signal canceled

const ROW_W := 1000.0
const ROW_H := 104.0
const ROW_GAP := 18.0
const BACK_W := 360.0
const BACK_H := 58.0

## 칸 고르기에서 고른 칸 (안내 글자 "칸 N에서 새로 시작합니다")
var slot := 1
var _index := 1
var _open := false
var _t := 0.0
var _panel: Control
## 누른 줄 (뗄 때 같은 줄이면 결정; -2 = 누르고 있지 않음)
var _press_row := -2


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


## 연다. for_slot = 새로 시작할 칸, start = 처음 고를 난이도
func open(for_slot: int, start := "normal") -> void:
	slot = for_slot
	var i := Balance.DIFFICULTIES.find(start)
	_index = i if i >= 0 else 1
	_press_row = -2
	_open = true
	_panel.visible = true
	Sfx.play("select")


func close() -> void:
	_open = false
	_panel.visible = false
	_press_row = -2


## 시험용
func selected() -> int:
	return _index


func back_index() -> int:
	return Balance.DIFFICULTIES.size()


func _process(delta: float) -> void:
	if _panel.visible:
		_t += delta
		_panel.queue_redraw()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("dodge"):
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


func _pointer(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch and event.index == 0:
		pos = event.position
		pressed = event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		pressed = event.pressed
	else:
		return
	var row := _hit_at(pos)
	if pressed:
		_press_row = row
		if row >= 0 and row != _index:
			_index = row
			Sfx.play("blip", -6.0)
	elif _press_row != -2:
		var was := _press_row
		_press_row = -2
		if row != was:
			return
		if row < 0:
			cancel()
		else:
			activate(row)


func _move(dir: int) -> void:
	var n := back_index() + 1
	_index = (_index + dir + n) % n
	Sfx.play("blip", -6.0)


## 줄 i 를 결정 (시험도 부른다)
func activate(i: int) -> void:
	if not _open:
		return
	if i == back_index():
		cancel()
		return
	if i < 0 or i >= back_index():
		return
	_index = i
	_open = false   # 화면은 그대로 두고 (타이틀이 곧 장면을 바꾼다) 입력만 멈춘다
	Sfx.play("select")
	chosen.emit(str(Balance.DIFFICULTIES[i]))


func cancel() -> void:
	if not _open:
		return
	close()
	Sfx.play("blip")
	canceled.emit()


# ---------- 자리 ----------

func _block_h() -> float:
	return 130.0 + back_index() * (ROW_H + ROW_GAP) + 92.0 + BACK_H + 70.0


func _top() -> float:
	return maxf(30.0, (_panel.size.y - _block_h()) / 2.0)


func row_rect(i: int) -> Rect2:
	var w := minf(ROW_W, _panel.size.x - 64.0)
	return Rect2((_panel.size.x - w) / 2.0, _top() + 130.0 + i * (ROW_H + ROW_GAP), w, ROW_H)


func back_rect() -> Rect2:
	var y := _top() + 130.0 + back_index() * (ROW_H + ROW_GAP) + 92.0
	return Rect2((_panel.size.x - BACK_W) / 2.0, y, BACK_W, BACK_H)


func _hit_at(pos: Vector2) -> int:
	for i in back_index():
		if row_rect(i).has_point(pos):
			return i
	if back_rect().has_point(pos):
		return back_index()
	return -1


# ---------- 그리기 ----------

func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var size := _panel.size
	var gold := Color(1.0, 0.86, 0.5)
	_panel.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 1.0))
	var top := _top()
	_panel.draw_string(font, Vector2(0, top + 56), SlotPicker.text("diff_title"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 46, Color(1.0, 0.9, 0.72))
	_panel.draw_string(font, Vector2(0, top + 100), SlotPicker.text("diff_sub", {"n": slot}), HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(0.85, 0.85, 0.9, 0.7))
	for i in back_index():
		var r := row_rect(i)
		var id: String = Balance.DIFFICULTIES[i]
		var sel := i == _index
		_panel.draw_rect(r, Color(1.0, 0.86, 0.5, 0.15) if sel else Color(1, 1, 1, 0.05))
		if sel:
			_panel.draw_rect(r, Color(gold, 0.7), false, 2.0)
		var col: Color = SlotPicker.DIFF_COLOR.get(id, Color.WHITE)
		_panel.draw_string(font, Vector2(r.position.x + 28, r.position.y + 64), ("▸ " if sel else "  ") + str(Balance.DIFF_NAME[id]), HORIZONTAL_ALIGNMENT_LEFT, 330, 40, col if sel else col * Color(0.85, 0.85, 0.85, 0.9))
		_panel.draw_string(font, Vector2(r.position.x + 380, r.position.y + 62), str(Balance.DIFF_DESC[id]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 410, 28, Color(1, 1, 1, 0.92 if sel else 0.6))
	var ny := top + 130.0 + back_index() * (ROW_H + ROW_GAP)
	_panel.draw_string(font, Vector2(0, ny + 26), SlotPicker.text("diff_note"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 24, Color(0.75, 0.88, 0.8, 0.85))
	_panel.draw_string(font, Vector2(0, ny + 60), SlotPicker.text("diff_note2"), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(1, 1, 1, 0.5))
	var br := back_rect()
	var bsel := _index == back_index()
	_panel.draw_rect(br, Color(1.0, 0.86, 0.5, 0.17) if bsel else Color(1, 1, 1, 0.05))
	_panel.draw_string(font, br.position + Vector2(0, 39), ("▸  " if bsel else "") + SlotPicker.text("back"), HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 28, gold if bsel else Color(0.9, 0.9, 0.9))
	_panel.draw_string(font, Vector2(0, br.end.y + 48), hint_text(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20, Color(1, 1, 1, 0.45))


func hint_text() -> String:
	match InputDevice.current:
		InputDevice.Kind.TOUCH:
			return SlotPicker.text("diff_hint_touch")
		InputDevice.Kind.DUALSENSE, InputDevice.Kind.XBOX, InputDevice.Kind.OTHER_PAD:
			return SlotPicker.text("diff_hint_pad", {"ok": InputDevice.prompt("jump"), "back": InputDevice.prompt("dodge")})
	return SlotPicker.text("diff_hint_kb", {"ok": InputDevice.prompt("jump")})

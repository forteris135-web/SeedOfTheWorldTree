extends CanvasLayer
class_name MusicRoom
## 음악 감상 (엔딩을 본 뒤 타이틀에서 연다, 2026-10-20 기획자 요청). 정식 곡 18곡을 이야기 순서로 두 줄(9곡씩)에 늘어놓는다.
## 곡을 고르면 처음부터 흐르고 **반복**한다 (엔딩에서 한 번만 흐르는 셀레니아의 허밍도 여기선 반복). 흐르는 곡을 다시 고르면 멈춘다.
## 아래에 지금 흐르는 곡 이름 · 흐른 시간 / 길이 · 진행 막대. '돌아가기'(또는 회피·메뉴·취소)로 닫으면 closed 신호 →
## 타이틀이 타이틀 곡을 다시 튼다. 곡 이름은 data/dialogue/music_titles.json (곡 파일은 Music.DIR, 목록은 Music.TRACKS 와 같아야 한다).
## 조작: 컨트롤러·키보드 = 위·아래·좌·우로 고르고 결정 / 터치·마우스 = 곡을 누르면 흐르고 다시 누르면 멈춤
## (흉내 낸 사건은 건너뛰어 누름 한 번 = 한 번만 처리 — _is_tap).

signal closed

const DATA_PATH := "res://data/dialogue/music_titles.json"
const ROWS := 9
const COL_W := 760.0
const COL_GAP := 40.0
const ROW_H := 66.0
const FADE := 0.8

var _data := {}
## [{id, name, where}] — 이야기 순서
var tracks: Array = []
var _index := 0
var _last_col := 0
var _open := false
var _t := 0.0
var _panel: Control


func _ready() -> void:
	layer = 44
	_data = load_data()
	tracks = _data.get("tracks", [])
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	_panel.draw.connect(_on_draw)
	add_child(_panel)


static func load_data() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return d if d is Dictionary else {}


func is_open() -> bool:
	return _open


func open() -> void:
	_open = true
	_panel.visible = true
	# 지금 흐르는 곡(타이틀의 허밍)에 고름을 맞춘다
	var cur := playing_index()
	_index = cur if cur >= 0 else 0
	Sfx.play("select")


func close() -> void:
	if not _open:
		return
	_open = false
	_panel.visible = false
	Sfx.play("blip")
	closed.emit()


## 고른 자리: 0~17 곡, 18 = 돌아가기
func selected() -> int:
	return _index


func back_index() -> int:
	return tracks.size()


## 지금 흐르는 곡의 자리 (목록 밖이거나 멈춤이면 -1)
func playing_index() -> int:
	var cur := Music.current()
	for i in tracks.size():
		if str(tracks[i].get("id", "")) == cur:
			return i
	return -1


## i 번째 곡을 처음부터 반복으로 튼다. 이미 흐르는 곡이면 멈춘다. (시험도 부른다)
func toggle(i: int) -> void:
	if i < 0 or i >= tracks.size():
		return
	_index = i
	var id := str(tracks[i].get("id", ""))
	if Music.current() == id:
		Music.stop(FADE)
	else:
		Music.play(id, {"fade": FADE, "from": 0.0, "loop": true})
	Sfx.play("select", -8.0)


## 흐른 시간과 길이 (초). 멈춤이면 [0, 0]
func time_of_playing() -> Array:
	var i := playing_index()
	if i < 0:
		return [0.0, 0.0]
	var id := str(tracks[i].get("id", ""))
	return [maxf(Music.playback_time(id), 0.0), Music.current_length()]


func _process(delta: float) -> void:
	if _open:
		_t += delta
		_panel.queue_redraw()


func _move(dx: int, dy: int) -> void:
	var n := tracks.size()
	if _index >= n:
		# 돌아가기에서 위로 → 마지막에 있던 줄의 맨 아래
		if dy < 0:
			_index = mini(_last_col * ROWS + ROWS - 1, n - 1)
		return
	var col := _index / ROWS
	var row := _index % ROWS
	if dx != 0:
		var nc := clampi(col + dx, 0, (n - 1) / ROWS)
		var ni := mini(nc * ROWS + row, n - 1)
		_index = ni
	elif dy != 0:
		row += dy
		if row >= ROWS or col * ROWS + row >= n:
			_last_col = col
			_index = n   # 돌아가기
			return
		if row < 0:
			return
		_index = col * ROWS + row
	_last_col = _index / ROWS


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("dodge"):
		close()
	elif event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
		_move(0, 1)
		Sfx.play("blip", -6.0)
	elif event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
		_move(0, -1)
		Sfx.play("blip", -6.0)
	elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
		_move(1, 0)
		Sfx.play("blip", -6.0)
	elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
		_move(-1, 0)
		Sfx.play("blip", -6.0)
	elif event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_activate()
	elif _is_tap(event):
		var hit := _hit_at(event.position)
		if hit == back_index():
			_index = hit
			close()
		elif hit >= 0:
			toggle(hit)
	get_viewport().set_input_as_handled()


## 누름 한 번인가. 터치 한 번은 '터치 + 흉내 낸 마우스'(emulate_mouse_from_touch), 클릭 한 번은 '클릭 + 흉내 낸 터치'
## (project.godot 의 emulate_touch_from_mouse)로 사건이 둘씩 들어온다 → 흉내 낸 사건(device = DEVICE_ID_EMULATION)은 건너뛴다.
## 둘 다 받으면 곡이 틀어지자마자 다시 멈췄다 (2026-10-20 QA).
static func _is_tap(event: InputEvent) -> bool:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return false
	if event is InputEventScreenTouch:
		return event.pressed
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT


func _activate() -> void:
	if _index >= tracks.size():
		close()
	else:
		toggle(_index)


# ---------- 자리 ----------

func _top() -> float:
	return maxf(30.0, (_panel.size.y - 960.0) / 2.0)


func row_rect(i: int) -> Rect2:
	var size := _panel.size
	var x0 := (size.x - (COL_W * 2.0 + COL_GAP)) / 2.0
	var col := i / ROWS
	var row := i % ROWS
	return Rect2(x0 + col * (COL_W + COL_GAP), _top() + 130.0 + row * ROW_H, COL_W, ROW_H - 8.0)


func back_rect() -> Rect2:
	var size := _panel.size
	return Rect2(size.x / 2.0 - 180.0, _top() + 130.0 + ROWS * ROW_H + 150.0, 360.0, 56.0)


func _now_rect() -> Rect2:
	var size := _panel.size
	var w := COL_W * 2.0 + COL_GAP
	return Rect2((size.x - w) / 2.0, _top() + 130.0 + ROWS * ROW_H + 18.0, w, 112.0)


func _hit_at(pos: Vector2) -> int:
	for i in tracks.size():
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
	# 완전히 가린다: 뒤의 타이틀 제목·메뉴 글자는 발광(HDR)이라 조금만 비쳐도 눈에 띈다 (2026-10-20 QA)
	_panel.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 1.0))
	var top := _top()
	_panel.draw_string(font, Vector2(size.x / 2.0 - 400, top + 70), str(_data.get("title", "")), HORIZONTAL_ALIGNMENT_CENTER, 800, 44, Color(1.0, 0.9, 0.72))
	var playing := playing_index()
	for i in tracks.size():
		var r := row_rect(i)
		var sel := i == _index
		var on := i == playing
		_panel.draw_rect(r, Color(1.0, 0.86, 0.5, 0.17) if sel else Color(1, 1, 1, 0.045))
		if on:
			_panel.draw_rect(Rect2(r.position, Vector2(6, r.size.y)), Color(gold, 0.9))
		var t: Dictionary = tracks[i]
		var name_col := gold if on else (Color(1.0, 0.92, 0.75) if sel else Color(0.9, 0.9, 0.9))
		var mark := "▶ " if on else ("%2d  " % (i + 1))
		_panel.draw_string(font, r.position + Vector2(22, 40), mark + str(t.get("name", t.get("id", ""))), HORIZONTAL_ALIGNMENT_LEFT, COL_W - 260, 27, name_col)
		_panel.draw_string(font, r.position + Vector2(COL_W - 250, 39), str(t.get("where", "")), HORIZONTAL_ALIGNMENT_RIGHT, 230, 19, Color(0.7, 0.78, 0.86, 0.75 if sel or on else 0.5))
	# 지금 흐르는 곡
	var nr := _now_rect()
	_panel.draw_rect(nr, Color(1, 1, 1, 0.05))
	var label := str(_data.get("now_playing", ""))
	if playing >= 0:
		var tt := time_of_playing()
		var el: float = tt[0]
		var ln: float = tt[1]
		_panel.draw_string(font, nr.position + Vector2(30, 44), "♪  %s  ·  %s" % [label, str(tracks[playing].get("name", ""))], HORIZONTAL_ALIGNMENT_LEFT, nr.size.x - 420, 28, gold)
		_panel.draw_string(font, nr.position + Vector2(nr.size.x - 390, 44), "%s / %s   %s" % [_mmss(el), _mmss(ln), str(_data.get("loop", ""))], HORIZONTAL_ALIGNMENT_RIGHT, 360, 26, Color(0.85, 0.9, 0.95))
		var bar := Rect2(nr.position + Vector2(30, 70), Vector2(nr.size.x - 60, 8))
		_panel.draw_rect(bar, Color(1, 1, 1, 0.12))
		var f := clampf(el / ln, 0.0, 1.0) if ln > 0.0 else 0.0
		_panel.draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), Color(gold, 0.85))
	else:
		_panel.draw_string(font, nr.position + Vector2(30, 44), "♪  %s  ·  %s" % [label, str(_data.get("stopped", ""))], HORIZONTAL_ALIGNMENT_LEFT, nr.size.x - 60, 28, Color(0.75, 0.78, 0.82))
	# 돌아가기
	var br := back_rect()
	var bsel := _index == back_index()
	_panel.draw_rect(br, Color(1.0, 0.86, 0.5, 0.17) if bsel else Color(1, 1, 1, 0.05))
	_panel.draw_string(font, br.position + Vector2(0, 38), ("▸  " if bsel else "") + str(_data.get("back", "")), HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 28, gold if bsel else Color(0.9, 0.9, 0.9))
	var hint := str(_data.get("hint_touch" if InputDevice.current == InputDevice.Kind.TOUCH else "hint_pad", ""))
	_panel.draw_string(font, Vector2(size.x / 2.0 - 600, br.end.y + 44), hint, HORIZONTAL_ALIGNMENT_CENTER, 1200, 20, Color(1, 1, 1, 0.45))


static func _mmss(sec: float) -> String:
	var s := int(maxf(sec, 0.0))
	return "%d:%02d" % [s / 60, s % 60]

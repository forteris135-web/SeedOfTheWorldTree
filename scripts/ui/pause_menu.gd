extends CanvasLayer
class_name PauseMenu
## 일시정지와 설정. 메뉴 버튼(Esc / P / 옵션)으로 연다.
## 타이틀 화면의 '설정'도 이 화면을 쓴다: open(true) = 설정만 (계속하기·저장·불러오기·타이틀로 없이, 게임을 멈추지 않음).
## 음량 세 가지(음악·효과음·전체)는 각자 자기 소리 버스만 바꾼다 (Settings → AudioBuses). 0 은 끔.
## 보스 러시 중에는 저장·불러오기·타이틀로 대신 '포기하기' 하나 (BossRush.give_up → 결과 화면 → 타이틀).
## v1.1.0: '난이도' 줄(좌우로 Easy · Normal · Hard · Nightmare — Progress.difficulty, 다음 방부터 적용, 저장은 다음 저장 때;
## 보스 러시 중·타이틀 설정에선 없음). '지금 저장하기'·'불러오기'는 지금 저장 칸에 하고, 값 글자에 "칸 N" 을 보여 준다.

## 좌우로 값을 바꾸는 줄 (터치: 그려진 값 글자 '◀ … ▶' 의 왼쪽 반 = 줄이기, 오른쪽 반 = 키우기)
const SLIDER_KEYS := ["music_volume", "sfx_volume", "master_volume", "touch_scale", "difficulty"]
## 값 글자의 크기와, 줄 오른쪽 끝에서 글자 오른쪽 끝까지 비우는 거리 (그리기·누름 판정이 같은 값을 쓴다)
const VALUE_FONT := 24
const VALUE_RIGHT_PAD := 20.0
## 값 글자 바깥으로 이만큼까지는 누름을 값 바꾸기로 친다 (◀ ▶ 가장자리를 손가락으로 누르기 쉽게)
const VALUE_TOUCH_PAD := 24.0

var _items := []   # {key, label}
var _index := 0
var _panel: Control
var _open := false
var _t := 0.0
var _settings_only := false


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


## 연다. settings_only: 타이틀에서 여는 설정 화면 (게임을 멈추지 않고, 설정 줄과 '돌아가기'만).
func open(settings_only := false) -> void:
	_settings_only = settings_only
	var settings := [
		{"key": "music_volume", "label": "음악 음량"},
		{"key": "sfx_volume", "label": "효과음 음량"},
		{"key": "master_volume", "label": "전체 음량"},
		{"key": "lenient_guard", "label": "저스트 가드 넉넉하게"},
		{"key": "touch_scale", "label": "터치 버튼 크기"},
		{"key": "screen_shake", "label": "화면 흔들림"},
		{"key": "debug_hud", "label": "개발 표시"},
		{"key": "remap", "label": "키 · 버튼 바꾸기"},
	]
	if settings_only:
		_items = settings + [{"key": "resume", "label": "돌아가기"}]
	elif BossRush.active:
		_items = [{"key": "resume", "label": "계속하기"}] + settings + [{"key": "give_up", "label": BossRush.text("give_up")}]
	else:
		_items = [{"key": "resume", "label": "계속하기"}, {"key": "difficulty", "label": SlotPicker.text("pause_difficulty")}] + settings + [
			{"key": "save", "label": "지금 저장하기"},
			{"key": "load", "label": "불러오기"},
			{"key": "title", "label": "타이틀로"},
		]
	_index = 0
	_open = true
	_panel.visible = true
	if not settings_only:
		get_tree().paused = true
		_set_hud_visible(false)
	Sfx.play("select")


func close() -> void:
	_open = false
	_panel.visible = false
	if not _settings_only:
		get_tree().paused = false
		_set_hud_visible(true)


func _set_hud_visible(on: bool) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for n in ["CombatHUD", "TouchControls", "BossHUD", "BossRushHUD"]:
		var h := scene.get_node_or_null(n)
		if h:
			h.visible = on


## 줄 key 의 자리 (없으면 -1). 시험용.
func row_of(key: String) -> int:
	for i in _items.size():
		if _items[i]["key"] == key:
			return i
	return -1


## 줄을 고르고 값을 바꾼다 (시험용: 좌우 입력과 같다).
func adjust_row(key: String, dir: int) -> void:
	var i := row_of(key)
	if i >= 0:
		_index = i
		_adjust(dir)


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
			var key: String = _items[hit]["key"]
			var dir := slider_dir_at(hit, event.position)
			if key in SLIDER_KEYS and dir != 0:
				# 값 글자: ◀ 쪽(글자의 왼쪽 반)을 누르면 줄이고 ▶ 쪽(오른쪽 반)을 누르면 키운다 (터치로도 음량을 낮출 수 있게)
				_index = hit
				_adjust(dir)
			elif hit == _index:
				_activate()
			else:
				_index = hit
				Sfx.play("blip")
		else:
			close()
	# 손가락 떼기는 터치 버튼(TouchControls)에도 흘려보낸다: 메뉴를 연 손가락·스틱을 쥐고 있던 손가락을 메뉴가 삼키면
	# 그 동작(메뉴·이동)이 눌린 채 남아, 닫은 뒤 소녀가 혼자 걷는다 (2026-10-20 QA, travel_menu 와 같은 규칙). 떼기로 메뉴가 하는 일은 없다.
	if event is InputEventScreenTouch and not event.pressed:
		return
	get_viewport().set_input_as_handled()


func _activate() -> void:
	var key: String = _items[_index]["key"]
	match key:
		"resume":
			close()
		"title":
			close()
			Game.go_to(Game.TITLE_SCENE, 0.6, 0.8)
		"give_up":
			close()
			BossRush.give_up()
		"save":
			var where := SaveGame.save_now()
			Sfx.play("select")
			var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
			if hud:
				hud.show_message(SlotPicker.text("pause_saved", {"n": SaveGame.slot, "where": where}), 3.0)
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
			get_tree().paused = not _settings_only
		"lenient_guard", "screen_shake", "debug_hud":
			Settings.set_value(key, not Settings.get_value(key))
			Sfx.play("select")
		"difficulty":
			# 결정(또는 줄 누르기)은 한 단계씩 돌아간다: Nightmare 다음은 Easy (좌우는 끝에서 멈춘다)
			var i := (Balance.DIFFICULTIES.find(Balance.difficulty()) + 1) % Balance.DIFFICULTIES.size()
			Progress.difficulty = Balance.DIFFICULTIES[i]
			Sfx.play("select")
		_:
			_adjust(1)


func _adjust(dir: int) -> void:
	var key: String = _items[_index]["key"]
	match key:
		"sfx_volume", "music_volume", "master_volume":
			Settings.set_value(key, clampi(int(Settings.get_value(key)) + dir, 0, 10))
			Sfx.play("select")
		"touch_scale":
			Settings.set_value(key, (int(Settings.get_value(key)) + dir + 3) % 3)
			Sfx.play("select")
		"lenient_guard", "screen_shake", "debug_hud":
			Settings.set_value(key, not Settings.get_value(key))
			Sfx.play("select")
		"difficulty":
			# 끝에서 멈춘다 (Easy 에서 ◀, Nightmare 에서 ▶ 는 그대로) — 한 번에 가장 쉬움 ↔ 가장 어려움으로 넘어가지 않게
			var n := Balance.DIFFICULTIES.size()
			var i := clampi(Balance.DIFFICULTIES.find(Balance.difficulty()) + dir, 0, n - 1)
			if Balance.DIFFICULTIES[i] != Progress.difficulty:
				Progress.difficulty = Balance.DIFFICULTIES[i]
				Sfx.play("select")
			else:
				Sfx.play("blip")


func _value_text(key: String) -> String:
	match key:
		"lenient_guard", "screen_shake", "debug_hud":
			return "켬" if Settings.get_value(key) else "끔"
		"sfx_volume", "music_volume", "master_volume":
			var v := clampi(int(Settings.get_value(key)), 0, 10)
			return "◀ " + ("끔" if v == 0 else "■".repeat(v) + "□".repeat(10 - v)) + " ▶"
		"touch_scale":
			return "◀ " + ["작게", "보통", "크게"][int(Settings.get_value(key))] + " ▶"
		"save":
			# 이어질 곳 이름 = 그 달빛풀이 있는 방의 지도 이름 (옛 저장의 옛 달빛풀 이름도 바로 맞게)
			var where := "지금 방의 처음"
			if not Progress.last_grass.is_empty():
				where = RoomIndex.grass_room_name(str(Progress.last_grass.get("id", "")), str(Progress.last_grass.get("name", where)))
			return SlotPicker.text("pause_save_value", {"n": SaveGame.slot, "where": where})
		"load":
			var at := SaveGame.saved_at_text()
			return SlotPicker.text("pause_load_value", {"n": SaveGame.slot, "at": at}) if at != "" else SlotPicker.text("pause_load_none", {"n": SaveGame.slot})
		"difficulty":
			var d := Balance.difficulty()
			return ("◀ " if d != Balance.DIFFICULTIES[0] else "   ") + str(Balance.DIFF_NAME[d]) + (" ▶" if d != Balance.DIFFICULTIES[-1] else "   ")
		"give_up":
			return BossRush.text("give_up_value")
	return ""


## 줄의 세로 간격과 첫 줄 자리: 줄이 많아(일시정지 13줄) 화면 아래 안내 글자가 넘치면 위로 올리고, 그래도 넘치면 간격을 좁힌다.
func _layout() -> Vector2:
	var h := _panel.size.y
	var n := _items.size()
	var step := 58.0
	var top := h * 0.26
	var bottom := h - 24.0 - 52.0   # 안내 글자 한 줄 자리
	if top + n * step > bottom:
		top = maxf(h * 0.13, bottom - n * step)
	if top + n * step > bottom:
		step = maxf(44.0, (bottom - top) / maxf(n, 1))
	return Vector2(top, step)


func _row_rect(i: int) -> Rect2:
	var size := _panel.size
	var w := 820.0
	var l := _layout()
	return Rect2((size.x - w) / 2.0, l.x + i * l.y, w, minf(52.0, l.y - 6.0))


## 줄 i 의 값 글자가 실제로 그려지는 자리 (오른쪽 끝을 줄 끝 − VALUE_RIGHT_PAD 에 맞춘다). 글자가 없으면 빈 사각형.
## 글꼴에 따라 ■□ 폭이 달라도(아이폰 기기 글꼴 등) 그리기와 누름 판정이 늘 같은 자리를 쓴다.
func value_text_rect(i: int) -> Rect2:
	var vt := _value_text(_items[i]["key"])
	if vt == "":
		return Rect2()
	var r := _row_rect(i)
	var tw := ThemeDB.fallback_font.get_string_size(vt, HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_FONT).x
	return Rect2(r.end.x - VALUE_RIGHT_PAD - tw, r.position.y, tw, r.size.y)


## 값을 좌우로 바꾸는 줄에서 pos 를 누르면: -1 = 줄이기(◀ 쪽), +1 = 키우기(▶ 쪽), 0 = 값 글자 밖.
## 그려진 글자 '◀ … ▶' 의 가운데를 기준으로 가른다 (예전엔 고정 320px 칸의 가운데라, 짧은 값 '◀ 보통 ▶' 의 ◀ 가 오른쪽 반에 들어가 거꾸로 움직였다).
func slider_dir_at(i: int, pos: Vector2) -> int:
	if i < 0 or i >= _items.size() or not (_items[i]["key"] in SLIDER_KEYS):
		return 0
	var tr := value_text_rect(i)
	if tr.size.x <= 0.0 or pos.x < tr.position.x - VALUE_TOUCH_PAD or pos.x > _row_rect(i).end.x:
		return 0
	return -1 if pos.x < tr.get_center().x else 1


func _row_at(pos: Vector2) -> int:
	for i in _items.size():
		if _row_rect(i).has_point(pos):
			return i
	return -1


func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var size := _panel.size
	# 타이틀의 설정 화면은 뒤의 제목·메뉴 글자가 비치지 않게 더 짙게
	_panel.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.92 if _settings_only else 0.78))
	var l := _layout()
	_panel.draw_string(font, Vector2(size.x / 2.0 - 400, l.x - size.y * 0.08), "설정" if _settings_only else "잠시 멈춤", HORIZONTAL_ALIGNMENT_CENTER, 800, 40, Color(1.0, 0.9, 0.72))
	for i in _items.size():
		var r := _row_rect(i)
		var sel := i == _index
		_panel.draw_rect(r, Color(1.0, 0.86, 0.5, 0.16) if sel else Color(1, 1, 1, 0.05))
		var it: Dictionary = _items[i]
		var ty := r.position.y + r.size.y / 2.0 + 9.0   # 글자 바닥선 (줄 높이가 좁아져도 가운데)
		_panel.draw_string(font, Vector2(r.position.x + 20, ty), ("▸  " if sel else "    ") + it["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(1.0, 0.86, 0.5) if sel else Color(0.9, 0.9, 0.9))
		var vt := _value_text(it["key"])
		if vt != "":
			# 폭 제한 없이 왼쪽 정렬로, value_text_rect 가 잰 자리에 그린다 (누름 판정과 같은 자리)
			var tr := value_text_rect(i)
			_panel.draw_string(font, Vector2(tr.position.x, ty), vt, HORIZONTAL_ALIGNMENT_LEFT, -1, VALUE_FONT, Color(0.56, 0.83, 1.0) if sel else Color(0.75, 0.8, 0.85))
	var foot := "위·아래로 고르고 좌·우로 바꾼다  ·  메뉴 / 회피: 닫기" if InputDevice.current != InputDevice.Kind.TOUCH else "줄을 눌러 고르고, 값의 ◀ ▶ 쪽을 눌러 바꾼다  ·  바깥을 누르면 닫기"
	var foot_col := Color(1, 1, 1, 0.45)
	if _index < _items.size() and _items[_index]["key"] == "difficulty":
		# 난이도 줄을 고르면: 그 난이도의 뜻과 '다음 방부터 적용'
		foot = SlotPicker.text("pause_difficulty_note", {"desc": str(Balance.DIFF_DESC[Balance.difficulty()])})
		foot_col = Color(0.75, 0.88, 0.8, 0.8)
	_panel.draw_string(font, Vector2(size.x / 2.0 - 500, l.x + _items.size() * l.y + 34.0), foot, HORIZONTAL_ALIGNMENT_CENTER, 1000, 20, foot_col)

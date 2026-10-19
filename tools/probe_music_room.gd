extends Node
## 음악 감상 시험 (엔딩 뒤 타이틀의 '음악 감상', 2026-10-20). 화면 없이 돈다.
## 실행: godot --headless --path . res://tools/probe_music_room.tscn
##  1) 클리어 전 타이틀에는 '음악 감상'이 없다 (허밍은 엔딩 전에 들리지 않는다).
##  2) 곡 목록(data/dialogue/music_titles.json) 18곡 = Music.TRACKS, 곡 파일이 모두 있고 한국어 이름·쓰이는 곳이 있다.
##  3) 클리어 뒤 타이틀 메뉴로 연다 → 지금 흐르는 타이틀 곡(허밍)에 고름이 맞춰져 있다.
##  4) 컨트롤러·키보드: 위·아래·좌·우·결정 (두 줄 사이, 맨 아래 '돌아가기'), 고른 곡이 처음부터 반복으로 흐르고 흐른 시간·길이가 잡힌다,
##     허밍도 여기선 반복, 같은 곡을 다시 고르면 멈춤. 터치: 곡을 누르면 흐르고, '돌아가기'를 누르면 닫힘.
##  5) 회피로 닫으면 타이틀 곡(허밍, 반복)으로 돌아간다.
## 마지막 줄 "[probe] 끝: 실패 N".

var _fail := 0
## 화면 있게 돌릴 때 -- --shots --out=/절대/경로 를 주면 몇 장면을 찍는다 (그림 확인용)
var _shots := false
var _out := ""


func _ready() -> void:
	print("[probe] 시작: 음악 감상")
	await _run()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _shot(name: String) -> void:
	if not _shots or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img:
		DirAccess.make_dir_recursive_absolute(_out)
		img.save_png(_out.path_join(name + ".png"))
		print("[probe]   찍음: ", _out.path_join(name + ".png"))


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _open_title() -> TitleScreen:
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	var cur := get_tree().current_scene
	get_tree().current_scene = dummy
	if cur and cur != self:
		cur.queue_free()
	Game._busy = false
	get_tree().change_scene_to_file(Game.TITLE_SCENE)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs is TitleScreen and cs.is_node_ready():
			await _frames(4)
			return cs
	return null


## 동작 하나를 눌렀다 뗀다 (컨트롤러·키보드와 같은 길)
func _press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


## 화면 누르기: 진짜 입력 길(Input.parse_input_event)로 보낸다 — 터치 한 번에 '흉내 낸 마우스'가 함께 들어오는 것까지 그대로
## (2026-10-20 QA: 화면에 바로 넘기던 예전 시험은, 한 번 누르면 두 번 처리돼 곡이 바로 멈추는 것을 잡지 못했다).
## pos 는 화면(캔버스) 좌표 → 창 좌표로 바꿔 보낸다.
func _touch(mr: MusicRoom, pos: Vector2) -> void:
	var wpos: Vector2 = get_tree().root.get_final_transform() * pos
	var ev := InputEventScreenTouch.new()
	ev.position = wpos
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var up := InputEventScreenTouch.new()
	up.position = wpos
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


## 마우스 왼쪽 클릭 한 번 (진짜 입력 길 — '흉내 낸 터치'가 함께 들어온다)
func _click(pos: Vector2) -> void:
	var wpos: Vector2 = get_tree().root.get_final_transform() * pos
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = wpos
		ev.global_position = wpos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)


func _run() -> void:
	await get_tree().process_frame   # 시작 장면이 다 놓인 뒤에 장면을 바꾼다
	var args := OS.get_cmdline_user_args()
	_shots = "--shots" in args
	_out = ProjectSettings.globalize_path("res://screenshots")
	for a in args:
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_rm(SaveGame.PATH)
	Progress.reset()
	var title := await _open_title()
	_check(title != null and not title.has_item("MusicRoom"), "클리어 전 타이틀: '음악 감상'이 없다 (곡 %s)" % Music.current())
	# 2) 곡 목록
	var data := MusicRoom.load_data()
	var tracks: Array = data.get("tracks", [])
	var ids := []
	var bad := []
	for t in tracks:
		var id := str(t.get("id", ""))
		ids.append(id)
		if not ResourceLoader.exists(Music.DIR + id + ".wav"):
			bad.append(id + "(파일 없음)")
		var nm := str(t.get("name", ""))
		if nm == "" or nm == id or str(t.get("where", "")) == "":
			bad.append(id + "(이름)")
	var a := ids.duplicate()
	a.sort()
	var b: Array = Music.TRACKS.duplicate()
	b.sort()
	_check(tracks.size() == 18 and a == b and bad.is_empty(), "곡 목록 %d곡 = Music.TRACKS, 파일·이름 모두 있음 %s" % [tracks.size(), bad])
	_check(str(data.get("title", "")) != "" and str(data.get("back", "")) != "", "화면 글자도 데이터 파일에")
	# 3) 클리어 뒤
	Progress.flags["cleared"] = true
	title = await _open_title()
	_check(title != null and title.has_item("MusicRoom") and Music.current() == Music.title_track(true), "클리어 뒤 타이틀: '음악 감상' 있음, 곡 %s" % Music.current())
	if title == null:
		return
	title.activate_item("MusicRoom")
	await _frames(3)
	var mr: MusicRoom = title._music_room
	var hum := ids.find(Music.title_track(true))
	_check(mr != null and mr.is_open() and title.music_room_open() and mr.selected() == hum and mr.playing_index() == hum,
		"메뉴로 열림, 지금 흐르는 허밍에 고름 (%d)" % (mr.selected() if mr else -1))
	# 4) 컨트롤러·키보드
	await _press("move_down")
	_check(mr.selected() == mr.back_index(), "맨 아래 곡에서 ↓ → '돌아가기'")
	await _press("move_up")
	_check(mr.selected() == hum, "'돌아가기'에서 ↑ → 그 줄의 맨 아래 곡")
	await _press("move_left")
	_check(mr.selected() == hum - 9, "← → 왼쪽 줄 같은 자리 (%d)" % mr.selected())
	await _press("move_up")
	await _press("move_up")
	_check(mr.selected() == hum - 11, "↑ 두 번 (%d)" % mr.selected())
	await _press("move_right")
	_check(mr.selected() == hum - 2, "→ → 오른쪽 줄 (%d)" % mr.selected())
	# 결정 → 그 곡이 처음부터 반복으로
	var sel := mr.selected()
	await _press("jump")
	await _wait(1.2)
	var tt := mr.time_of_playing()
	_check(Music.current() == ids[sel] and Music.current_loops() and mr.playing_index() == sel and float(tt[0]) > 0.6 and float(tt[1]) > 60.0,
		"결정 → %s 이 흐름 (반복 %s, %.1f초 / %.1f초)" % [Music.current(), Music.current_loops(), float(tt[0]), float(tt[1])])
	# 허밍도 반복
	mr.toggle(hum)
	await _wait(0.3)
	_check(Music.current() == ids[hum] and Music.current_loops(), "허밍도 음악 감상에선 반복 (반복 %s)" % Music.current_loops())
	if _shots:
		await _wait(2.0)
		await _shot("music_room")
	# 같은 곡을 다시 고르면 멈춤
	mr.toggle(hum)
	await _wait(1.0)
	_check(Music.current() == "" and mr.playing_index() == -1 and float(mr.time_of_playing()[1]) == 0.0, "같은 곡을 다시 고르면 멈춤 (%s)" % Music.current())
	# 터치: 곡을 누르면 흐른다
	await _touch(mr, mr.row_rect(0).get_center())
	await _wait(0.3)
	_check(Music.current() == ids[0] and mr.selected() == 0, "터치: 첫 곡을 누르면 흐름 (%s)" % Music.current())
	await _touch(mr, mr.row_rect(0).get_center())
	await _wait(0.9)
	_check(Music.current() == "", "터치: 흐르는 곡을 다시 누르면 멈춤")
	await _touch(mr, mr.row_rect(13).get_center())
	await _wait(0.3)
	_check(Music.current() == ids[13], "터치: 오른쪽 줄 곡 (%s)" % Music.current())
	# 한 번 누르면 한 번만: 곡이 바뀐 뒤 한참 지나도 그대로 흐른다 (두 번 처리되면 틀자마자 멈춘다)
	await _wait(0.8)
	_check(Music.current() == ids[13] and mr.playing_index() == 13, "터치 한 번 = 한 번만 처리 (0.8초 뒤에도 %s 이 흐름)" % Music.current())
	# 마우스 클릭도 한 번만 (클릭 + 흉내 낸 터치)
	await _click(mr.row_rect(4).get_center())
	await _wait(0.8)
	_check(Music.current() == ids[4] and mr.selected() == 4, "클릭 한 번 = 한 번만 처리 (%s)" % Music.current())
	await _click(mr.row_rect(4).get_center())
	await _wait(0.9)
	_check(Music.current() == "", "클릭: 흐르는 곡을 다시 클릭하면 멈춤 (%s)" % Music.current())
	await _touch(mr, mr.row_rect(13).get_center())
	await _wait(0.3)
	# 5) 회피로 닫으면 타이틀 곡으로
	await _press("dodge")
	await _wait(0.3)
	_check(not mr.is_open() and not title.music_room_open() and Music.current() == Music.title_track(true) and Music.current_loops(),
		"회피로 닫힘 → 타이틀 곡 %s (반복 %s)" % [Music.current(), Music.current_loops()])
	# 터치로 '돌아가기'
	title.activate_item("MusicRoom")
	await _frames(3)
	await _touch(mr, mr.back_rect().get_center())
	_check(not mr.is_open(), "터치: '돌아가기'를 누르면 닫힘")
	# 닫힌 뒤 타이틀 메뉴가 다시 입력을 받는다
	var idx := title._index
	await _press("move_down")
	_check(title._index != idx, "닫힌 뒤 타이틀 메뉴가 다시 움직인다")
	Music.stop(0.0)
	Progress.reset()

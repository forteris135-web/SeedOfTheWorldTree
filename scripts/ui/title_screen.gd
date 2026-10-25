extends Control
class_name TitleScreen
## 타이틀 화면. 타이틀 일러스트 위로 천천히 움직이는 카메라, 떠다니는 빛, 제목과 메뉴.
## 음악: 클리어 전 title, 엔딩을 본 뒤 selenia_humming (Music.title_track). 클리어 후에는 그림·부제가 마지막으로 본 엔딩에 따라 바뀐다
## (ENDINGS.md 5장: 희생 → title_after_sacrifice, 되돌림 → title_after_return, 제3의 길 → title_after_true).
## 엔딩을 본 뒤에만 메뉴에 '보스 러시'(BossRush)와 '음악 감상'(MusicRoom)이 생긴다 (2026-10-20 기획자 요청).
## v1.1.0 저장 칸: '이어하기' → 칸 고르기(SlotPicker, 찬 칸만) → 불러오기. '새로 시작' → 칸 고르기(세 칸, 찬 칸은 두 번 눌러 덮어쓰기)
## → 난이도 고르기(DifficultyPicker) → 그 칸에 새로 시작. 엔딩을 본 기록은 칸과 상관없이 남는다(MetaSave) — 칸을 지우거나 덮어써도
## 보스 러시·음악 감상·클리어 뒤 타이틀 그림이 사라지지 않는다. 오른쪽 아래에 버전 글자.

## 클리어 전 타이틀 그림
const DEFAULT_ART := "res://art/characters/title_selenia.png"

@onready var art: TextureRect = $Art
@onready var menu: VBoxContainer = $Layout/Menu
@onready var title_label: Label = $Layout/Title
@onready var subtitle: Label = $Layout/Subtitle
@onready var hint: Label = $Hint

var _items: Array[Button] = []
var _index := 0
var _time := 0.0
var _started := false
## 설정 화면 (일시정지 메뉴의 설정 부분을 그대로 쓴다: 음량·터치 크기·키 바꾸기 등)
var _settings: PauseMenu
## 음악 감상 (엔딩을 본 뒤)
var _music_room: MusicRoom
var _cleared := false
## 저장 칸 고르기 · 난이도 고르기 (처음 열 때 만든다)
var _slots: SlotPicker
var _difficulty: DifficultyPicker
## '새로 시작'에서 고른 칸 (난이도를 고르는 동안)
var _new_slot := 0


func _ready() -> void:
	if BossRush.active:
		BossRush.restore()   # 혹시 러시가 끝나지 않은 채 왔으면 떼어 둔 진행부터 되돌린다
	var seen := cleared_state()
	_cleared = seen["cleared"]
	var gone := false
	if not SaveGame.any_save():
		menu.get_node("Continue").queue_free()
		gone = true
	if not _cleared:
		# 보스 러시·음악 감상은 엔딩을 본 뒤에만 (허밍은 엔딩 전에는 들리지 않는다)
		menu.get_node("BossRush").queue_free()
		menu.get_node("MusicRoom").queue_free()
		gone = true
	if gone:
		await get_tree().process_frame
	for c in menu.get_children():
		if c is Button:
			_items.append(c)
			c.pressed.connect(_on_item_pressed.bind(c))
			c.mouse_entered.connect(func() -> void: _select(_items.find(c)))
	_select(0)
	if seen["cleared"]:
		# 클리어 후: 마지막으로 본 엔딩의 타이틀 그림과 부제 (ENDINGS.md 5장 — 그림·부제는 endings*.json 의 title_image / title_subtitle)
		var look := title_look(seen)
		art.texture = load(look["image"])
		if look["subtitle"] != "":
			subtitle.text = look["subtitle"]
	# 타이틀 곡: 클리어 전 title, 엔딩을 본 뒤 셀레니아의 허밍(엔딩에선 한 번만 흐르는 곡을 여기선 반복) — ENDINGS.md 5장
	_play_title_music(2.0)
	InputDevice.device_changed.connect(func(_k): _refresh_hint())
	_refresh_hint()
	var ver := get_node_or_null("BuildVersion") as Label
	if ver:
		ver.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	# 느리게 다가가는 카메라
	art.pivot_offset = art.size / 2.0
	art.resized.connect(func() -> void: art.pivot_offset = art.size / 2.0)
	art.scale = Vector2(1.0, 1.0)
	var tw := create_tween().set_loops()
	tw.tween_property(art, "scale", Vector2(1.07, 1.07), 22.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(art, "scale", Vector2(1.0, 1.0), 22.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 제목이 천천히 떠오른다
	title_label.modulate.a = 0.0
	subtitle.modulate.a = 0.0
	menu.modulate.a = 0.0
	hint.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_interval(0.8)
	fade.tween_property(title_label, "modulate:a", 1.0, 1.6)
	fade.parallel().tween_property(subtitle, "modulate:a", 1.0, 1.6).set_delay(0.6)
	fade.tween_property(menu, "modulate:a", 1.0, 0.8)
	fade.parallel().tween_property(hint, "modulate:a", 1.0, 0.8)
	Game.fade_in(1.6)
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(4.5).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/debug_title.png"))
		get_tree().quit()


## 엔딩을 보았는가: 지금 진행(Progress) 또는 칸과 상관없는 해금 기록(MetaSave) 또는 아무 저장 칸의 깃발.
## 앱을 새로 켠 뒤에도 클리어한 타이틀이 보이게 파일을 **읽기만** 한다 (진행은 '이어하기'를 고를 때 SaveGame.load_game 이 되돌린다).
## {"cleared": 엔딩을 하나라도 봄, "third": 제3의 길을 봄, "ending": 마지막으로 본 엔딩 (sacrifice / return / third, 모르면 "")}
## 마지막으로 본 엔딩: 지금 진행에 엔딩을 본 기록이 있으면 그것, 없으면 메타의 마지막 엔딩, 그것도 없으면 가장 늦게 저장한 클리어 칸
## (깃발 last_ending_*, 옛 저장은 "ending" 값).
static func cleared_state() -> Dictionary:
	var out := {"cleared": Progress.has("cleared"), "third": Progress.has("cleared_third"), "ending": ""}
	if out["cleared"]:
		out["ending"] = PostEnding.last_ending()
		if out["ending"] == "" and Progress.ending in EndingScene.ENDINGS:
			out["ending"] = Progress.ending
	var meta := MetaSave.read()
	out["cleared"] = out["cleared"] or bool(meta["cleared"])
	out["third"] = out["third"] or bool(meta["cleared_third"])
	if out["ending"] == "" and str(meta["last_ending"]) in EndingScene.ENDINGS:
		out["ending"] = str(meta["last_ending"])
	var slot_end := ""
	var slot_end_at := ""
	for i in range(1, SaveGame.SLOT_COUNT + 1):
		var data := SaveGame.read_slot(i)
		if typeof(data.get("flags", null)) != TYPE_DICTIONARY:
			continue
		var f: Dictionary = data["flags"]
		if not bool(f.get("cleared", false)):
			continue
		out["cleared"] = true
		out["third"] = out["third"] or bool(f.get("cleared_third", false))
		var e := ""
		for n in EndingScene.ENDINGS:
			if bool(f.get("last_ending_" + n, false)):
				e = n
		if e == "" and str(data.get("ending", "")) in EndingScene.ENDINGS:
			e = str(data.get("ending", ""))
		var at := str(data.get("saved_at", ""))
		if e != "" and (slot_end == "" or at > slot_end_at):
			slot_end = e
			slot_end_at = at
	if out["ending"] == "":
		out["ending"] = slot_end
	return out


## 클리어 후 타이틀의 그림·부제: 마지막으로 본 엔딩에 따라 (ENDINGS.md 5장). 클리어 전에는 기본 그림.
## {"image": 그림 경로, "subtitle": 부제 (""이면 장면 파일의 기본 부제)}
static func title_look(seen: Dictionary) -> Dictionary:
	if not seen.get("cleared", false):
		return {"image": DEFAULT_ART, "subtitle": ""}
	var e: Dictionary = EndingScene.ending_data(str(seen.get("ending", "")))
	var img := str(e.get("title_image", ""))
	if img == "" or not ResourceLoader.exists(img):
		# 어느 엔딩인지 모르는 옛 저장: 예전처럼 밝은 일러스트
		return {"image": "res://art/characters/title_selenia_alt_b.png", "subtitle": "— 그리고 세계는 다시 숨을 쉰다."}
	return {"image": img, "subtitle": str(e.get("title_subtitle", ""))}


## 타이틀 곡을 튼다 (처음, 그리고 음악 감상에서 돌아올 때)
func _play_title_music(fade: float) -> void:
	Music.play(Music.title_track(_cleared), {"fade": fade, "loop": true})


func _process(delta: float) -> void:
	_time += delta
	# 선택된 항목이 은은하게 숨 쉰다
	for i in _items.size():
		var b := _items[i]
		if i == _index:
			var pulse := 0.85 + 0.15 * sin(_time * 3.0)
			b.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5) * Color(pulse, pulse, pulse, 1.0))
			b.text = "▸  " + b.text.trim_prefix("▸  ")
		else:
			b.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.75))
			b.text = b.text.trim_prefix("▸  ")


func _unhandled_input(event: InputEvent) -> void:
	if _started or settings_open() or music_room_open() or picker_open():
		return
	if event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
		_select((_index + 1) % _items.size())
		Sfx.play("blip", -6.0)
	elif event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
		_select((_index - 1 + _items.size()) % _items.size())
		Sfx.play("blip", -6.0)
	elif event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		_activate(_index)


func _select(i: int) -> void:
	_index = clampi(i, 0, max(_items.size() - 1, 0))


func _on_item_pressed(b: Button) -> void:
	# 누른 항목을 먼저 고른다 (터치는 마우스가 그 위로 '들어오지' 않고 바로 눌릴 수 있다)
	_select(_items.find(b))
	_activate(_items.find(b))


func _activate(i: int) -> void:
	if _started or i < 0 or i >= _items.size() or settings_open() or music_room_open() or picker_open():
		return
	var b := _items[i]
	Sfx.play("select")
	match b.name:
		"Settings":
			open_settings()
		"BossRush":
			_started = true
			BossRush.start()
		"MusicRoom":
			open_music_room()
		"Continue":
			open_slot_picker("load")
		"Start":
			# 찬 칸을 덮어쓸 때는 칸 고르기에서 한 번 더 확인한다 (2026-10-20 QA: 클리어한 저장이 확인 없이 지워졌다)
			open_slot_picker("new")
		"InputTest":
			_started = true
			Game.go_to("res://scenes/debug/input_test.tscn", 0.5, 0.6)


## 설정 화면을 연다 (시험도 부른다).
func open_settings() -> PauseMenu:
	if _settings == null or not is_instance_valid(_settings):
		_settings = PauseMenu.new()
		add_child(_settings)
	_settings.open(true)
	return _settings


func settings_open() -> bool:
	return _settings != null and is_instance_valid(_settings) and _settings.is_open()


## 음악 감상을 연다 (시험도 부른다). 닫으면 타이틀 곡으로 돌아간다.
func open_music_room() -> MusicRoom:
	if _music_room == null or not is_instance_valid(_music_room):
		_music_room = MusicRoom.new()
		add_child(_music_room)
		_music_room.closed.connect(_play_title_music.bind(1.5))
	_music_room.open()
	return _music_room


func music_room_open() -> bool:
	return _music_room != null and is_instance_valid(_music_room) and _music_room.is_open()


## 저장 칸 고르기를 연다: how = "load"(이어하기) / "new"(새로 시작). 시험도 부른다.
func open_slot_picker(how: String, start := 0) -> SlotPicker:
	if _slots == null or not is_instance_valid(_slots):
		_slots = SlotPicker.new()
		add_child(_slots)
		_slots.chosen.connect(_on_slot_chosen)
		_slots.closed.connect(_refresh_continue)
		_slots.deleted.connect(func(_i: int) -> void: _refresh_continue())
	_slots.open(how, start)
	return _slots


func slot_picker() -> SlotPicker:
	return _slots if _slots != null and is_instance_valid(_slots) else null


func difficulty_picker() -> DifficultyPicker:
	return _difficulty if _difficulty != null and is_instance_valid(_difficulty) else null


## 칸 고르기나 난이도 고르기가 열려 있는가
func picker_open() -> bool:
	return (slot_picker() != null and _slots.is_open()) or (difficulty_picker() != null and _difficulty.is_open())


func _on_slot_chosen(i: int) -> void:
	if _started:
		return
	if _slots.mode == "load":
		if SaveGame.read_slot(i).is_empty():
			# 읽을 수 없는 저장 (깨진 파일): 다시 고르게 한다 (지우기는 칸 고르기에서)
			Sfx.play("blip")
			_slots.open("load", i)
			return
		_started = true
		SaveGame.set_slot(i)
		var scene := SaveGame.load_game()
		Game.go_to(scene if scene != "" else Game.FIRST_ROOM, 1.2, 1.4)
		return
	# 새로 시작: 난이도를 고른다 (돌아가면 칸 고르기로)
	_new_slot = i
	_slots.hide_panel()
	if _difficulty == null or not is_instance_valid(_difficulty):
		_difficulty = DifficultyPicker.new()
		add_child(_difficulty)
		_difficulty.chosen.connect(_on_difficulty_chosen)
		_difficulty.canceled.connect(func() -> void: _slots.open("new", _new_slot))
	_difficulty.open(i, "normal")


func _on_difficulty_chosen(diff: String) -> void:
	if _started or _new_slot <= 0:
		return
	_started = true
	SaveGame.set_slot(_new_slot)
	SaveGame.new_game(diff)
	Game.go_to(Game.FIRST_ROOM, 1.2, 1.4)


## 칸을 지워 저장이 하나도 남지 않으면 '이어하기'를 치운다
func _refresh_continue() -> void:
	if SaveGame.any_save():
		return
	for k in _items.size():
		var b := _items[k]
		if is_instance_valid(b) and b.name == "Continue":
			_items.remove_at(k)
			b.queue_free()
			_select(maxi(_index - (1 if k < _index else 0), 0))
			return


## 메뉴에 그 항목이 있는가 (시험용: "BossRush", "MusicRoom" …)
func has_item(item_name: String) -> bool:
	for b in _items:
		if is_instance_valid(b) and b.name == item_name:
			return true
	return false


## 메뉴 항목을 이름으로 고른다 (시험용)
func activate_item(item_name: String) -> void:
	for i in _items.size():
		if _items[i].name == item_name:
			_activate(i)
			return


func _refresh_hint() -> void:
	match InputDevice.current:
		InputDevice.Kind.TOUCH:
			hint.text = "항목을 누르세요"
		InputDevice.Kind.DUALSENSE:
			hint.text = "스틱으로 고르고  ×  로 결정"
		InputDevice.Kind.XBOX, InputDevice.Kind.OTHER_PAD:
			hint.text = "스틱으로 고르고  A  로 결정"
		_:
			hint.text = "W / S 로 고르고  Space  로 결정"

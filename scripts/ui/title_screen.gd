extends Control
## 타이틀 화면. 타이틀 일러스트 위로 천천히 움직이는 카메라, 떠다니는 빛, 제목과 메뉴.
## 음악: 클리어 전 title, 엔딩을 본 뒤 selenia_humming (Music.title_track). 클리어 후에는 그림·부제도 바뀐다(기획서 2장).

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


func _ready() -> void:
	if not SaveGame.has_save():
		menu.get_node("Continue").queue_free()
		await get_tree().process_frame
	for c in menu.get_children():
		if c is Button:
			_items.append(c)
			c.pressed.connect(_on_item_pressed.bind(c))
			c.mouse_entered.connect(func() -> void: _select(_items.find(c)))
	_select(0)
	var seen := cleared_state()
	if seen["cleared"]:
		# 클리어 후: 밝은 일러스트, 바뀐 부제. 제3의 길(확장판)을 보았으면 부제가 또 바뀐다.
		art.texture = load("res://art/characters/title_selenia_alt_b.png")
		if seen["third"]:
			subtitle.text = "— 등불 하나면 충분해."
		else:
			subtitle.text = "— 그리고 세계는 다시 숨을 쉰다."
	# 타이틀 곡: 클리어 전 title, 엔딩을 본 뒤 셀레니아의 허밍(엔딩에선 한 번만 흐르는 곡을 여기선 반복) — ENDINGS.md 5장
	Music.play(Music.title_track(seen["cleared"]), {"fade": 2.0, "loop": true})
	InputDevice.device_changed.connect(func(_k): _refresh_hint())
	_refresh_hint()
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


## 엔딩을 보았는가: 지금 진행(Progress) 또는 저장 파일의 깃발. 앱을 새로 켠 뒤에도 클리어한 타이틀이 보이게
## 저장 파일을 **읽기만** 한다 (진행은 '이어하기'를 고를 때 SaveGame.load_game 이 되돌린다).
## {"cleared": 엔딩을 하나라도 봄, "third": 제3의 길을 봄}
static func cleared_state() -> Dictionary:
	var out := {"cleared": Progress.has("cleared"), "third": Progress.has("cleared_third")}
	if SaveGame.has_save():
		var data = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.PATH))
		if typeof(data) == TYPE_DICTIONARY and typeof(data.get("flags", null)) == TYPE_DICTIONARY:
			var f: Dictionary = data["flags"]
			out["cleared"] = out["cleared"] or bool(f.get("cleared", false))
			out["third"] = out["third"] or bool(f.get("cleared_third", false))
	return out


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
	if _started or settings_open():
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
	_activate(_items.find(b))


func _activate(i: int) -> void:
	if _started or i < 0 or settings_open():
		return
	var b := _items[i]
	Sfx.play("select")
	match b.name:
		"Settings":
			open_settings()
		"Continue":
			_started = true
			var scene := SaveGame.load_game()
			Game.go_to(scene if scene != "" else Game.FIRST_ROOM, 1.2, 1.4)
		"Start":
			_started = true
			SaveGame.new_game()
			Game.go_to(Game.FIRST_ROOM, 1.2, 1.4)
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

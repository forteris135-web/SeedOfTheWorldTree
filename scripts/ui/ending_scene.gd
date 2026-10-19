extends Control
## 엔딩. 선택에 따라 두 종류. 그림 위로 자막이 천천히 흐르고, 마지막에 주제 문장. 그 뒤 제작진과 타이틀로.
## 자막은 data/dialogue/endings.json. 음악(C장조로 끝나는 주제곡)은 13단계에서.

const DATA_PATH := "res://data/dialogue/endings.json"
const LINE_TIME := 6.0

@onready var art: TextureRect = $Art
@onready var subtitle: Label = $Subtitle
@onready var title: Label = $Title
@onready var credits: Label = $Credits

var _lines: Array = []
var _index := -1
var _timer := 0.0
var _done := false
var _can_skip := false


func _ready() -> void:
	var data: Dictionary = DialogueData.load_dialogue(DATA_PATH)
	var which := Progress.ending if Progress.ending != "" else "return"
	var e: Dictionary = data.get(which, {})
	_lines = e.get("lines", [])
	title.text = e.get("title", "")
	var tex := load(e.get("image", "")) as Texture2D
	art.texture = tex
	art.modulate = Color(1, 1, 1, 0)
	title.modulate.a = 0.0
	subtitle.modulate.a = 0.0
	credits.modulate.a = 0.0
	Progress.set_flag("cleared")
	Progress.set_flag("ending_" + which)
	Game.fade_in(1.5)
	Music.play("theme_ending", 3.0, true)
	var tw := create_tween()
	tw.tween_property(art, "modulate", Color(0.75, 0.72, 0.68, 1), 4.0)
	tw.parallel().tween_property(title, "modulate:a", 1.0, 2.0).set_delay(1.0)
	tw.tween_interval(1.5)
	tw.tween_property(title, "modulate:a", 0.0, 1.0)
	tw.tween_callback(_next)
	var ken := create_tween()
	art.pivot_offset = art.size / 2.0
	ken.tween_property(art, "scale", Vector2(1.12, 1.12), LINE_TIME * (_lines.size() + 2))
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(12.0).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/debug_ending.png"))
		get_tree().quit()


func _process(delta: float) -> void:
	if _index < 0 or _done:
		return
	_timer += delta
	_can_skip = _timer > 1.0
	if _timer >= LINE_TIME:
		_next()


func _unhandled_input(event: InputEvent) -> void:
	if _done or not _can_skip:
		return
	if event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") or (event is InputEventScreenTouch and event.pressed):
		_next()


func _next() -> void:
	_index += 1
	_timer = 0.0
	_can_skip = false
	if _index >= _lines.size():
		_finish()
		return
	var last := _index == _lines.size() - 1
	var tw := create_tween()
	tw.tween_property(subtitle, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		subtitle.text = _lines[_index]
		subtitle.add_theme_font_size_override("font_size", 40 if last else 32)
		subtitle.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75) if last else Color(0.96, 0.95, 0.9)))
	tw.tween_property(subtitle, "modulate:a", 1.0, 1.2)


func _finish() -> void:
	_done = true
	var tw := create_tween()
	tw.tween_property(subtitle, "modulate:a", 0.0, 1.5)
	tw.tween_property(art, "modulate", Color(0.2, 0.2, 0.2, 1), 2.0)
	tw.parallel().tween_property(credits, "modulate:a", 1.0, 2.0)
	tw.tween_interval(6.0)
	tw.tween_callback(func() -> void: Game.go_to(Game.TITLE_SCENE, 2.0, 2.0))

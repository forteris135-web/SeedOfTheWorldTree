extends Control
class_name MemoryScene
## 보스 회상 씬 (임시 연출). 회상 그림 위로 천천히 움직이는 카메라, 떠다니는 빛, 독백 자막.
## 대사는 data/dialogue/memories.json 에서 읽는다. 곡은 recollection (Music.RECOLLECTION).

const DATA_PATH := "res://data/dialogue/memories.json"
const LINE_TIME := 5.0
## 방으로 돌아간 뒤 회상 곡을 더 이어 갈 시간(초). 영혼 구슬이 내려와 깃드는 연출(약 7초)이 끝날 무렵 들판 곡으로 넘어간다.
const HOLD_AFTER := 8.0

@onready var art: TextureRect = $Art
@onready var art2: TextureRect = $Art2
@onready var subtitle: Label = $Subtitle
@onready var title: Label = $Title
@onready var hint: Label = $Hint

var _lines: Array = []
var _index := -1
var _timer := 0.0
var _can_skip := false
var _done := false
var _reward := ""
var _memory_id := ""


func _ready() -> void:
	_memory_id = Progress.pending_memory if Progress.pending_memory != "" else "memory_bird"
	var data: Dictionary = DialogueData.load_dialogue(DATA_PATH)
	var mem: Dictionary = data.get(_memory_id, {})
	_lines = mem.get("lines", [])
	_reward = mem.get("reward_text", "")
	title.text = mem.get("title", "")
	title.modulate.a = 0.0
	subtitle.modulate.a = 0.0
	art.modulate.a = 0.0
	art2.modulate.a = 0.0
	hint.modulate.a = 0.0
	Game.fade_in(1.0)
	# 회상 곡 (기획자의 recollection). 보스곡이 끊긴 정적 뒤에 조용히 시작해, 방으로 돌아간 뒤에도 영혼이 깃드는 동안
	# HOLD_AFTER 초 더 이어지고, 그다음 그 지역의 들판 곡(수관은 되살아난 수관 곡)이 스며든다 (Music.hold).
	# (옛 임시 주제곡의 '정화한 보스 수에 따라 길어지는 길이'는 정식 곡 한 곡으로 바뀌며 쓰지 않는다.)
	Music.play(Music.RECOLLECTION, {"fade": 2.5, "from": 0.0})
	Music.hold(Music.RECOLLECTION, HOLD_AFTER)
	var tw := create_tween()
	tw.tween_property(title, "modulate:a", 1.0, 1.2)
	tw.tween_interval(1.2)
	tw.tween_property(title, "modulate:a", 0.0, 0.8)
	tw.tween_callback(_next_line)
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(6.0).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/debug_memory.png"))
		get_tree().quit()


## 정화한 보스 수: 깃발 boss_<이름>_defeated 가 선 것을 센다 (중간 보스 miniboss_* 는 아님). 지금 정화한 보스도 포함된다
## (BossRoom 이 회상으로 오기 전에 깃발을 세운다).
static func purified_boss_count() -> int:
	var n := 0
	for f in Progress.flags:
		var k := str(f)
		if k.begins_with("boss_") and k.ends_with("_defeated") and Progress.flags[f]:
			n += 1
	return n


func _process(delta: float) -> void:
	if _index < 0 or _done:
		return
	_timer += delta
	if _timer > 0.8:
		_can_skip = true
		hint.modulate.a = move_toward(hint.modulate.a, 0.5, delta)
	if _timer >= LINE_TIME:
		_next_line()


func _unhandled_input(event: InputEvent) -> void:
	if _done or not _can_skip:
		return
	if event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("attack_light") or event.is_action_pressed("ui_accept") or (event is InputEventScreenTouch and event.pressed):
		_next_line()


func _next_line() -> void:
	_index += 1
	_timer = 0.0
	_can_skip = false
	if _index >= _lines.size():
		_finish()
		return
	var line: Dictionary = _lines[_index]
	var tex: Texture2D = load(line.get("image", "")) if line.get("image", "") != "" else null
	# 그림 교차 (art2 → art)
	var fade := create_tween()
	if tex and tex != art.texture:
		art2.texture = art.texture
		art2.modulate.a = art.modulate.a
		art2.scale = art.scale
		art.texture = tex
		art.modulate.a = 0.0
		art.pivot_offset = art.size / 2.0
		art.scale = Vector2(1.0, 1.0)
		fade.tween_property(art, "modulate:a", 1.0, 1.4)
		fade.parallel().tween_property(art2, "modulate:a", 0.0, 1.4)
		var ken := create_tween()
		ken.tween_property(art, "scale", Vector2(1.08, 1.08), LINE_TIME + 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		fade.tween_interval(0.01)
	var sub := create_tween()
	sub.tween_property(subtitle, "modulate:a", 0.0, 0.3)
	sub.tween_callback(func() -> void: subtitle.text = line.get("text", ""))
	sub.tween_property(subtitle, "modulate:a", 1.0, 0.8)


func _finish() -> void:
	_done = true
	var tw := create_tween()
	tw.tween_property(subtitle, "modulate:a", 0.0, 0.5)
	if _reward != "":
		tw.tween_callback(func() -> void: subtitle.text = _reward)
		tw.tween_property(subtitle, "modulate:a", 1.0, 0.8)
		tw.tween_interval(2.2)
	tw.tween_callback(func() -> void:
		Progress.pending_memory = ""
		# 곡은 끄지 않는다 — 방에 돌아간 뒤 Music.hold 가 HOLD_AFTER 초 뒤 들판 곡으로 넘긴다
		Game.go_to(Progress.memory_return_scene if Progress.memory_return_scene != "" else Game.FIRST_ROOM, 1.2, 1.4))

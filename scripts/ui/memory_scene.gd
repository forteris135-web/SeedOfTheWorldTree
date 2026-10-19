extends Control
class_name MemoryScene
## 보스 회상 씬 (임시 연출). 회상 그림 위로 천천히 움직이는 카메라, 떠다니는 빛, 독백 자막.
## 대사는 data/dialogue/memories.json 에서 읽는다. 주제곡은 13단계에서.

const DATA_PATH := "res://data/dialogue/memories.json"
const LINE_TIME := 5.0

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
	# 회상마다 주제곡이 조금씩 더 길게 들린다 (기획서 2장 "귀"). 확장판에서는 순서가 사람마다 다르므로
	# '지금까지 정화한 보스 수'로 정한다 (EXPANSION.md 5장): 1 A파트 / 2 A+B 앞 / 3 A+B 대부분 / 4 마지막 마디 전까지 / 뿌리지기 전체.
	var pick := theme_for(_memory_id, purified_boss_count())
	Music.play(pick[0], 2.5, true)
	# 정해진 길이(0 이면 곡 끝)까지 곡을 붙잡는다: 회상(27초 남짓)이 먼저 끝나도 곡은 방으로 돌아간 뒤에도 그 길이까지 이어지고,
	# 그다음 지역곡으로 넘어간다 (2026-10-19 검수: 전엔 회상 끝에 곡을 꺼서 다섯 단계 모두 '첫 27초'만 들렸다)
	Music.hold(pick[0], pick[1])
	var tw := create_tween()
	tw.tween_property(title, "modulate:a", 1.0, 1.2)
	tw.tween_interval(1.2)
	tw.tween_property(title, "modulate:a", 0.0, 0.8)
	tw.tween_callback(_next_line)
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(6.0).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/debug_memory.png"))
		get_tree().quit()


## 주제곡 전체(theme_full, 62bpm 80박)에서 마지막 마디(4박)를 뺀 길이(초).
const FULL_BEFORE_LAST_BAR := (80.0 - 4.0) * 60.0 / 62.0
## "A + B 앞": A(32박) 뒤 B 의 첫 세 마디(12박)까지 (theme_ab 54초 가운데 약 42.6초).
const AB_FRONT := (32.0 + 12.0) * 60.0 / 62.0


## 정화한 보스 수: 깃발 boss_<이름>_defeated 가 선 것을 센다 (중간 보스 miniboss_* 는 아님). 지금 정화한 보스도 포함된다
## (BossRoom 이 회상으로 오기 전에 깃발을 세운다).
static func purified_boss_count() -> int:
	var n := 0
	for f in Progress.flags:
		var k := str(f)
		if k.begins_with("boss_") and k.ends_with("_defeated") and Progress.flags[f]:
			n += 1
	return n


## [곡 이름, 길이 제한(초; 0 = 끝까지)]. 뿌리지기(마지막 회상)는 보스 수와 상관없이 처음으로 전체.
## 1편(새 → 기사 → 뿌리지기)은 전과 같다: theme_a → theme_ab → theme_full.
static func theme_for(memory_id: String, bosses: int) -> Array:
	if memory_id == "memory_root":
		return ["theme_full", 0.0]
	match bosses:
		0, 1: return ["theme_a", 0.0]
		2: return ["theme_ab", AB_FRONT]   # "A + B 앞"
		3: return ["theme_ab", 0.0]        # "A + B 대부분" — theme_ab 끝까지 (기획자 곡이 오면 theme_abx 를 둔다)
		_: return ["theme_full", FULL_BEFORE_LAST_BAR]


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
		# 곡은 끄지 않는다 — Music.hold 가 정해진 길이에서 지역곡으로 넘긴다
		Game.go_to(Progress.memory_return_scene if Progress.memory_return_scene != "" else Game.FIRST_ROOM, 1.2, 1.4))

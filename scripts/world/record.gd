extends Node2D
class_name Record
## 읽을 수 있는 기록물 (포스터, 경전, 명령서, 비석). △를 누르면 글이 대화 상자로 떠오른다.
## 글은 data/dialogue/records.json. 기획서: 하나당 4줄 이내, 1편 전체 6~10개.

const DATA_PATH := "res://data/dialogue/records.json"

@export var record_id := ""
## 모양: poster(벽보) / book(책) / stone(비석) / note(쪽지)
@export_enum("poster", "book", "stone", "note") var kind := "poster"

var _data := {}
var _prompt: Label
var _near: Player
var _t := 0.0


func _ready() -> void:
	var all: Dictionary = DialogueData.load_dialogue(DATA_PATH)
	_data = all.get(record_id, {})
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color("cfe9ff"))
	_prompt.position = Vector2(-60, -150)
	_prompt.visible = false
	add_child(_prompt)
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 120.0
	shape.shape = c
	shape.position = Vector2(0, -50)
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(func(b): if b is Player: _near = b; b.register_interactable(self))
	area.body_exited.connect(func(b): if b is Player: b.unregister_interactable(self); _near = null)
	material = preload("res://shaders/ash_purify.tres")


func _process(delta: float) -> void:
	_t += delta
	_prompt.visible = _near != null and not Dialogue.is_active()
	if _prompt.visible:
		_prompt.text = "%s  읽기" % InputDevice.prompt("interact")
	queue_redraw()


func interact(_by: Player) -> void:
	var title: String = _data.get("title", "")
	var lines: Array = []
	for l in _data.get("lines", []):
		lines.append({"speaker": title, "text": l})
	if _data.has("graffiti"):
		lines.append({"speaker": "삐뚤삐뚤한 낙서", "text": _data["graffiti"]})
	if lines.is_empty():
		return
	Dialogue.start(lines, func() -> void: Progress.set_flag("read_" + record_id))


func _draw() -> void:
	var glow := 0.6 + 0.4 * sin(_t * 2.0)
	match kind:
		"poster":
			draw_rect(Rect2(-34, -110, 68, 90), Color(0.86, 0.78, 0.6))
			draw_rect(Rect2(-34, -110, 68, 90), Color(0.4, 0.3, 0.2), false, 2.0)
			for i in 4:
				draw_line(Vector2(-24, -94 + i * 18), Vector2(24 - (i % 2) * 10, -94 + i * 18), Color(0.35, 0.28, 0.2, 0.8), 2.0)
		"book":
			draw_rect(Rect2(-40, -30, 80, 20), Color(0.45, 0.3, 0.2))
			draw_rect(Rect2(-38, -36, 76, 8), Color(0.92, 0.88, 0.78))
			draw_circle(Vector2(0, -32), 26.0 * glow, Color(1.0, 0.85, 0.5, 0.08))
		"stone":
			draw_colored_polygon(PackedVector2Array([Vector2(-50, 0), Vector2(-44, -140), Vector2(0, -170), Vector2(44, -140), Vector2(50, 0)]), Color(0.3, 0.3, 0.34))
			for i in 5:
				draw_line(Vector2(-26, -120 + i * 20), Vector2(26, -120 + i * 20), Color(0.6, 0.62, 0.7, 0.7), 2.0)
		"note":
			draw_rect(Rect2(-26, -50, 52, 40), Color(0.9, 0.86, 0.74))
			for i in 3:
				draw_line(Vector2(-18, -40 + i * 10), Vector2(18, -40 + i * 10), Color(0.3, 0.25, 0.2, 0.8), 1.5)
	draw_circle(Vector2(0, -60), 8.0 + glow * 4.0, Color(1.0, 0.9, 0.6, 0.12 * glow))

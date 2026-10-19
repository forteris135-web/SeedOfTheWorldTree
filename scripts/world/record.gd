extends Node2D
class_name Record
## 읽을 수 있는 기록물 (포스터, 경전, 명령서, 비석). △를 누르면 글이 대화 상자로 떠오른다.
## 글은 data/dialogue/records.json. 기획서: 하나당 4줄 이내, 1편 전체 6~10개.

const DATA_PATH := "res://data/dialogue/records.json"

@export var record_id := ""
## 모양: poster(벽보) / book(책) / stone(비석) / note(쪽지) / page(찢긴 경전 조각 — 확장판, 그림 object_scripture_page.png)
@export_enum("poster", "book", "stone", "note", "page") var kind := "poster"

const PAGE_TEX := preload("res://art/objects/object_scripture_page.png")

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
	# 확장판: 조건(깃발)이 맞을 때만 더해지는 줄 (예: 경전 조각을 다 읽으면 사당 경전에 완성 구절이 이어진다)
	for ex in _data.get("extra", []):
		if _condition_ok(str(ex.get("when", ""))):
			for l in ex.get("lines", []):
				lines.append({"speaker": title, "text": l})
	if lines.is_empty():
		return
	Dialogue.start(lines, func() -> void:
		Progress.set_flag("read_" + record_id)
		# 모으는 기록물(경전 조각): 읽은 수를 알려 준다
		var msg := str(_data.get("count_message", ""))
		if msg != "":
			var n := 0
			for id in _data.get("count_ids", []):
				if Progress.has("read_" + str(id)):
					n += 1
			var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
			if hud:
				hud.show_message(msg % n if "%d" in msg else msg, 3.0))


## when: 비어 있으면 항상. "flag" 는 깃발이 서 있을 때, "!flag" 는 안 서 있을 때. 여러 개는 쉼표 (npc.gd 와 같은 형식).
func _condition_ok(when: String) -> bool:
	if when.strip_edges() == "":
		return true
	for part in when.split(","):
		var f := part.strip_edges()
		if f.begins_with("!"):
			if Progress.has(f.substr(1)):
				return false
		elif not Progress.has(f):
			return false
	return true


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
		"page":
			# 찢긴 경전 조각: 임시 그림을 작게, 살짝 떠서 흔들린다
			var sway := sin(_t * 1.4) * 4.0
			draw_texture_rect(PAGE_TEX, Rect2(-44, -112 + sway, 88, 88), false, Color(1, 1, 1, 0.95))
			draw_circle(Vector2(0, -68 + sway), 36.0 * glow, Color(1.0, 0.9, 0.6, 0.08))
	draw_circle(Vector2(0, -60), 8.0 + glow * 4.0, Color(1.0, 0.9, 0.6, 0.12 * glow))

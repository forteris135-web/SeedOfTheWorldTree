extends Node2D
class_name Record
## 읽을 수 있는 기록물 (포스터, 경전, 명령서, 비석). △를 누르면 글이 대화 상자로 떠오른다.
## 글은 data/dialogue/records.json. 기획서: 하나당 4줄 이내, 1편 전체 6~10개.

const DATA_PATH := "res://data/dialogue/records.json"

@export var record_id := ""
## 모양: poster(벽보) / book(책) / stone(비석) / note(쪽지) / page(찢긴 경전 조각 — 확장판)
## 비석(stone)이 아니면 기획자가 준 양피지 그림(art/objects/record_parchment.png, tools/terrain_cut.gd _objects)을
## 모양마다 크기·기울기를 달리해 쓴다. 경전 조각(page)은 살짝 떠서 흔들린다.
@export_enum("poster", "book", "stone", "note", "page") var kind := "poster"

const PARCHMENT := preload("res://art/objects/record_parchment.png")
## 모양별 양피지: [가운데 자리, 높이 px, 기울기(도)]
const PARCHMENT_LOOK := {
	"poster": [Vector2(0, -78), 112.0, -4.0],
	"note": [Vector2(0, -44), 64.0, 9.0],
	"book": [Vector2(0, -30), 70.0, -78.0],
	"page": [Vector2(0, -72), 96.0, 6.0],
}

var _data := {}
var _prompt: Label
var _near: Player
var _t := 0.0
var _sheet: Sprite2D


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
	if PARCHMENT_LOOK.has(kind):
		var look: Array = PARCHMENT_LOOK[kind]
		_sheet = Sprite2D.new()
		_sheet.texture = PARCHMENT
		_sheet.use_parent_material = true
		_sheet.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_sheet.position = look[0]
		_sheet.scale = Vector2.ONE * (float(look[1]) / PARCHMENT.get_height())
		_sheet.rotation_degrees = float(look[2])
		add_child(_sheet)


func _process(delta: float) -> void:
	_t += delta
	_prompt.visible = _near != null and not Dialogue.is_active()
	if _prompt.visible:
		_prompt.text = "%s  읽기" % InputDevice.prompt("interact")
	if _sheet and kind == "page":
		_sheet.position = (PARCHMENT_LOOK["page"][0] as Vector2) + Vector2(0, sin(_t * 1.4) * 4.0)
		_sheet.rotation_degrees = 6.0 + sin(_t * 0.9) * 3.0
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
	if kind == "stone":
		draw_colored_polygon(PackedVector2Array([Vector2(-50, 0), Vector2(-44, -140), Vector2(0, -170), Vector2(44, -140), Vector2(50, 0)]), Color(0.3, 0.3, 0.34))
		for i in 5:
			draw_line(Vector2(-26, -120 + i * 20), Vector2(26, -120 + i * 20), Color(0.6, 0.62, 0.7, 0.7), 2.0)
	elif _sheet:
		# 양피지 뒤의 은은한 빛 (읽을 수 있다는 표시)
		draw_circle(_sheet.position, float(PARCHMENT_LOOK[kind][1]) * 0.55 * glow, Color(1.0, 0.88, 0.6, 0.07))
	draw_circle(Vector2(0, -60), 8.0 + glow * 4.0, Color(1.0, 0.9, 0.6, 0.12 * glow))

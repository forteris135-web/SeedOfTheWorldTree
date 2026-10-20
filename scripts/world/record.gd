extends Node2D
class_name Record
## 읽을 수 있는 기록물 (포스터, 경전, 명령서, 비석). △를 누르면 글이 대화 상자로 떠오른다.
## 글은 data/dialogue/records.json. 기획서: 하나당 4줄 이내, 1편 전체 6~10개.

const DATA_PATH := "res://data/dialogue/records.json"

@export var record_id := ""
## 모양: poster(벽보) / book(책) / stone(비석) / note(쪽지) / page(찢긴 경전 조각 — 확장판, 그림 object_scripture_page.png)
## 벽보·책·쪽지는 기획자가 준 양피지 그림(art/objects/record_parchment.png, tools/terrain_cut.gd _objects)을
## 모양마다 크기·기울기를 달리해 쓴다 (책 전용 그림이 오기 전까지 책은 바닥에 놓인 양피지).
## 경전 조각(page)은 확장판 자리 그림(EXPANSION.md 10번, object_scripture_page.png)을 그대로 쓰고 살짝 떠서 흔들린다.
@export_enum("poster", "book", "stone", "note", "page") var kind := "poster"

const PARCHMENT := preload("res://art/objects/record_parchment.png")
const PAGE_TEX := preload("res://art/objects/object_scripture_page.png")
## 모양별 그림: [가운데 자리, 높이 px, 기울기(도)] (page 만 PAGE_TEX, 나머지는 양피지)
const PARCHMENT_LOOK := {
	"poster": [Vector2(0, -78), 112.0, -4.0],
	"note": [Vector2(0, -44), 64.0, 9.0],
	"book": [Vector2(0, -34), 62.0, 4.0],
	"page": [Vector2(0, -68), 88.0, 0.0],
}

## 비석: 기획자 그림(art/objects/record_stone.png — ART_PROMPTS 2장)이 오면 그 그림을 세워 쓴다 (높이 STONE_H, 밑동이 원점).
## 그림이 오기 전에는 방의 지형 몸통 결(그림 옷의 fill — 뿌리·바위 결)을 입힌 아치형 비석에 새긴 글줄·이끼·그림자를 코드로 얹는다
## (2026-10-20 검수: 회색 다각형 + 흰 줄 다섯 개라 정화 뒤 밝은 호수에서 새까만 판처럼 보였다).
const STONE_ART := "res://art/objects/record_stone.png"
const STONE_H := 170.0
const STONE_TINT := Color(0.78, 0.8, 0.86)
var _stone_tex: Texture2D
var _stone_body := PackedVector2Array()
var _stone_uv := PackedVector2Array()
var _stone_panel := PackedVector2Array()
var _stone_runes: Array = []   # [시작, 끝] 짧은 새김 줄들
var _stone_moss: Array = []    # [자리, 반지름]

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
		_sheet.texture = PAGE_TEX if kind == "page" else PARCHMENT
		_sheet.use_parent_material = true
		_sheet.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_sheet.position = look[0]
		_sheet.scale = Vector2.ONE * (float(look[1]) / _sheet.texture.get_height())
		_sheet.rotation_degrees = float(look[2])
		add_child(_sheet)
	elif kind == "stone":
		_setup_stone()


func _setup_stone() -> void:
	if ResourceLoader.exists(STONE_ART):
		_sheet = Sprite2D.new()
		_sheet.texture = load(STONE_ART)
		_sheet.use_parent_material = true
		_sheet.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var k := STONE_H / _sheet.texture.get_height()
		_sheet.scale = Vector2(k, k)
		_sheet.position = Vector2(0, -STONE_H * 0.5 + 6.0)   # 밑동을 땅에 조금 묻는다
		add_child(_sheet)
		return
	var skin := TerrainSkin.for_node(self)
	if skin and skin.fill:
		_stone_tex = skin.fill
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(record_id) if record_id != "" else 7
	# 몸통: 아래가 조금 넓은 아치 (밑동은 땅에 6px 묻힘)
	var w0 := 54.0
	var w1 := 46.0
	var top := -128.0
	_stone_body = PackedVector2Array([Vector2(-w0, 6.0), Vector2(-w1 - rng.randf_range(0, 3), top)])
	for i in range(1, 12):
		var a := PI + PI * float(i) / 12.0
		_stone_body.append(Vector2(cos(a) * w1, top + sin(a) * 40.0 + rng.randf_range(-2.0, 2.0)))
	_stone_body.append(Vector2(w1 + rng.randf_range(0, 3), top))
	_stone_body.append(Vector2(w0, 6.0))
	_stone_uv = PackedVector2Array()
	var ofs := Vector2(rng.randf_range(0, 512), rng.randf_range(0, 512))
	for q in _stone_body:
		_stone_uv.append((q * 1.2 + ofs) / 512.0)
	# 새긴 판 (안쪽 아치)
	_stone_panel = PackedVector2Array([Vector2(-34, -18), Vector2(-34, top + 4.0)])
	for i in range(1, 10):
		var a := PI + PI * float(i) / 10.0
		_stone_panel.append(Vector2(cos(a) * 34.0, top + 4.0 + sin(a) * 26.0))
	_stone_panel.append(Vector2(34, top + 4.0))
	_stone_panel.append(Vector2(34, -18))
	# 새김 글줄: 다섯 줄, 줄마다 짧은 획 두세 개
	_stone_runes = []
	for row in 5:
		var y := top + 2.0 + row * 20.0
		var x := -26.0
		while x < 24.0:
			var len := rng.randf_range(7.0, 18.0)
			var x2 := minf(x + len, 26.0)
			_stone_runes.append([Vector2(x, y + rng.randf_range(-1.5, 1.5)), Vector2(x2, y + rng.randf_range(-1.5, 1.5))])
			x = x2 + rng.randf_range(4.0, 8.0)
	# 이끼: 아치 위와 밑동
	_stone_moss = []
	for i in 7:
		var a := PI + rng.randf_range(0.15, 0.85) * PI
		_stone_moss.append([Vector2(cos(a) * w1 * 0.95, top + sin(a) * 38.0 + 2.0), rng.randf_range(3.0, 6.5)])
	for i in 6:
		_stone_moss.append([Vector2(rng.randf_range(-w0, w0), rng.randf_range(-6.0, 2.0)), rng.randf_range(3.0, 7.0)])


func _process(delta: float) -> void:
	_t += delta
	_prompt.visible = _near != null and not Dialogue.is_active()
	if _prompt.visible:
		_prompt.text = "%s  읽기" % InputDevice.prompt("interact")
	if _sheet and kind == "page":
		_sheet.position = (PARCHMENT_LOOK["page"][0] as Vector2) + Vector2(0, sin(_t * 1.4) * 4.0)
		_sheet.rotation_degrees = sin(_t * 0.9) * 3.0
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


## 그림이 오기 전의 비석 (위 STONE_ART 설명): 그림자 → 결을 입힌 몸통 → 어두운 테·밝은 왼쪽 위 테 → 새긴 판 → 새김 글줄(희미한 빛) → 이끼
func _draw_stone(glow: float) -> void:
	if _stone_body.is_empty():
		return
	draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.22))
	draw_circle(Vector2.ZERO, 70.0, Color(0, 0, 0, 0.32))
	draw_set_transform(Vector2.ZERO)
	if _stone_tex:
		draw_colored_polygon(_stone_body, STONE_TINT, _stone_uv, _stone_tex)
	else:
		draw_colored_polygon(_stone_body, Color(0.42, 0.42, 0.46))
	var outline := _stone_body.duplicate()
	outline.append(_stone_body[0])
	draw_polyline(outline, Color(0.05, 0.05, 0.06, 0.55), 3.0, true)
	var lit := PackedVector2Array()
	for i in range(1, _stone_body.size() / 2 + 1):
		lit.append(_stone_body[i] + Vector2(3, 2))
	draw_polyline(lit, Color(1, 0.97, 0.9, 0.22), 2.0, true)
	draw_colored_polygon(_stone_panel, Color(0.0, 0.0, 0.02, 0.28))
	var rune_c := Color(0.62, 0.8, 1.0, 0.35 + 0.25 * glow)
	for r in _stone_runes:
		draw_line(r[0], r[1], Color(0.02, 0.02, 0.03, 0.75), 3.2, true)
		draw_line((r[0] as Vector2) + Vector2(0, 1.5), (r[1] as Vector2) + Vector2(0, 1.5), Color(1, 1, 1, 0.12), 1.2, true)
		draw_line(r[0], r[1], rune_c, 1.3, true)
	for m in _stone_moss:
		draw_circle(m[0], m[1], Color(0.28, 0.42, 0.2, 0.85))
		draw_circle((m[0] as Vector2) + Vector2(-1, -1.5), float(m[1]) * 0.55, Color(0.45, 0.6, 0.3, 0.8))


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
	if kind == "stone" and _sheet == null:
		_draw_stone(glow)
	elif _sheet:
		# 양피지 뒤의 은은한 빛 (읽을 수 있다는 표시)
		draw_circle(_sheet.position, float(PARCHMENT_LOOK[kind][1]) * 0.55 * glow, Color(1.0, 0.88, 0.6, 0.07))
	draw_circle(Vector2(0, -60), 8.0 + glow * 4.0, Color(1.0, 0.9, 0.6, 0.12 * glow))

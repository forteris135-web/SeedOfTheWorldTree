extends Node2D
class_name Npc
## 마을 사람. data/dialogue/npcs.json 의 항목을 읽어, 상황(깃발)에 맞는 대사 묶음을 고른다.
## 항목 형식: {"name": "...", "talks": [{"when": "깃발 조건", "lines": [...], "set": "세울 깃발", "once": true}, ...]}
## when: 비어 있으면 항상. "flag" 는 깃발이 서 있을 때, "!flag" 는 안 서 있을 때. 여러 개는 쉼표.

const DATA_PATH := "res://data/dialogue/npcs.json"

@export var npc_id := ""
@export var texture: Texture2D
@export var art_faces_right := true
@export var art_scale := 0.17
## 그림 아래 투명 여백 보정 (원본 px)
@export var foot_offset := 20.0
## 이 깃발이 서 있어야 나타난다 (비어 있으면 항상).
@export var require_flag := ""

var _data := {}
var _sprite: Sprite2D
var _prompt: Label
var _near: Player
var _t := 0.0
var _area: Area2D
var _talk_count := 0


func _ready() -> void:
	add_to_group("npc")
	if require_flag != "" and not Progress.has(require_flag):
		queue_free()
		return
	var all: Dictionary = DialogueData.load_dialogue(DATA_PATH)
	_data = all.get(npc_id, {})
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if texture:
		_sprite.position = Vector2(0, -texture.get_height() * art_scale / 2.0 + foot_offset * art_scale)
	_sprite.scale = Vector2(art_scale, art_scale)
	add_child(_sprite)
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color("cfe9ff"))
	_prompt.position = Vector2(-80, -(texture.get_height() * art_scale if texture else 200) - 40)
	_prompt.visible = false
	add_child(_prompt)
	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 150.0
	shape.shape = c
	shape.position = Vector2(0, -70)
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(func(b): if b is Player: _near = b; b.register_interactable(self))
	_area.body_exited.connect(func(b): if b is Player: b.unregister_interactable(self); _near = null)


func _process(delta: float) -> void:
	_t += delta
	_prompt.visible = _near != null and not Dialogue.is_active()
	if _prompt.visible:
		_prompt.text = "%s  %s" % [InputDevice.prompt("interact"), _data.get("name", "말 걸기")]
	# 숨쉬기, 소녀 쪽 바라보기
	_sprite.scale = Vector2(art_scale, art_scale * (1.0 + sin(_t * 1.8) * 0.012))
	if _near:
		var face_right := _near.global_position.x > global_position.x
		_sprite.scale.x = art_scale * (1.0 if face_right == art_faces_right else -1.0)


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


func interact(_by: Player) -> void:
	var talks: Array = _data.get("talks", [])
	var chosen := {}
	for t in talks:
		if t.get("once", false) and Progress.has("talked_" + npc_id + "_" + str(talks.find(t))):
			continue
		if _condition_ok(t.get("when", "")):
			chosen = t
			break
	if chosen.is_empty():
		return
	var name: String = _data.get("name", "")
	var lines: Array = []
	for l in chosen.get("lines", []):
		if l is String:
			lines.append({"speaker": name, "text": l})
		else:
			lines.append(l)
	var idx := talks.find(chosen)
	Dialogue.start(lines, func() -> void:
		if chosen.get("once", false):
			Progress.set_flag("talked_" + npc_id + "_" + str(idx))
		var flag: String = chosen.get("set", "")
		if flag != "":
			Progress.set_flag(flag)
		var give: String = chosen.get("message", "")
		if give != "":
			var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
			if hud:
				hud.show_message(give, 3.5))

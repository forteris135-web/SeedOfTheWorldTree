extends Node2D
class_name RescuedPerson
## 구원되어 사람으로 돌아온 이. 처음 한 번 감사의 말과 보상을 건네고, 그 뒤엔 말을 건다.
## 대사와 보상은 data/dialogue/npcs.json. (사람 모습 그림은 나중에 교체; 지금은 같은 그림에 따뜻한 빛)

const DATA_PATH := "res://data/dialogue/npcs.json"

var rescue_id := ""
var texture: Texture2D
var art_faces_right := true
var art_scale := 0.17
var facing := 1
var _sprite: Sprite2D
var _prompt: Label
var _near: Player
var _data := {}
var _said_first := false
var _bubble: Label
var _bubble_timer := 0.0
var _line_index := 0
var _area: Area2D


func _ready() -> void:
	add_to_group("npc")
	var all: Dictionary = DialogueData.load_dialogue(DATA_PATH)
	_data = all.get(rescue_id, {})
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.scale = Vector2(art_scale, art_scale)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if texture:
		_sprite.position = Vector2(0, -texture.get_height() * art_scale / 2.0 + 20.0 * art_scale)
	_sprite.flip_h = (facing > 0) != art_faces_right
	_sprite.modulate = Color(1.15, 1.1, 1.0)
	add_child(_sprite)
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color("cfe9ff"))
	_prompt.position = Vector2(-60, -250)
	_prompt.visible = false
	add_child(_prompt)
	_bubble = Label.new()
	_bubble.add_theme_font_size_override("font_size", 24)
	_bubble.add_theme_color_override("font_color", Color(0.97, 0.95, 0.9))
	_bubble.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_bubble.add_theme_constant_override("shadow_outline_size", 6)
	_bubble.position = Vector2(-260, -300)
	_bubble.size = Vector2(520, 60)
	_bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.visible = false
	add_child(_bubble)
	_area = Area2D.new()
	_area.collision_layer = 0
	_area.collision_mask = 2
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 140.0
	shape.shape = c
	shape.position = Vector2(0, -60)
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(func(b): if b is Player: _near = b; b.register_interactable(self))
	_area.body_exited.connect(func(b): if b is Player: b.unregister_interactable(self); _near = null)


func _process(delta: float) -> void:
	_prompt.visible = _near != null and not _bubble.visible
	if _prompt.visible:
		_prompt.text = "%s  말 걸기" % InputDevice.prompt("interact")
	if _bubble.visible:
		_bubble_timer -= delta
		if _bubble_timer <= 0.0:
			_bubble.visible = false
	if _near:
		_sprite.flip_h = ((_near.global_position.x > global_position.x) != art_faces_right)


## 구원 직후: 빛이 번지고 첫 말과 보상.
func greet(by: Player) -> void:
	_said_first = true
	var tw := create_tween()
	_sprite.modulate = Color(3, 3, 3)
	tw.tween_property(_sprite, "modulate", Color(1.15, 1.1, 1.0), 1.2)
	var name: String = _data.get("name", "구원된 사람")
	var lines: Array = _data.get("rescued_lines", ["…고마워요."])
	_say("%s: %s" % [name, lines[0]], 4.0)
	var reward: Dictionary = _data.get("reward", {})
	if not reward.is_empty():
		await get_tree().create_timer(4.2).timeout   # 감사의 말이 끝난 뒤
		_give_reward(reward)


func _give_reward(reward: Dictionary) -> void:
	var kind: String = reward.get("type", "")
	var amount: float = reward.get("amount", 0)
	var text := ""
	match kind:
		"max_hp":
			Progress.add_upgrade("max_hp", amount)
			text = "최대 체력이 %d 늘었다" % int(amount)
		"attack":
			Progress.add_upgrade("attack", amount)
			text = "공격력이 %d%% 올랐다" % int(round(amount * 100))
		"dews":
			Progress.add_upgrade("dews", amount)
			text = "이슬 방울을 %d개 더 담을 수 있다" % int(amount)
	var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
	if hud and text != "":
		hud.show_message(text, 3.0)
	Juice.rumble(0.2, 0.4, 0.2)


func interact(_by: Player) -> void:
	var name: String = _data.get("name", "구원된 사람")
	var lines: Array = _data.get("talk_lines", _data.get("rescued_lines", ["…"]))
	if lines.is_empty():
		return
	_say("%s: %s" % [name, lines[_line_index % lines.size()]], 3.5)
	_line_index += 1


func _say(text: String, seconds: float) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_timer = seconds

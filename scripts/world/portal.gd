extends Area2D
class_name Portal
## 포탈: 옆 방으로 이어지는 빛의 문 (메이플스토리처럼). 방의 양 끝에 서 있고, 앞에 서서 손길(상호작용) 버튼을
## 누르면 건너간다. (↑로 들어가던 것은 기획자 요청으로 뺐다 — 위 키는 이제 포탈과 무관하다.)
## 건너간 방에서는 그 방 포탈 앞(Markers/<spawn_name>)에 서므로 되돌아올 수도 있다.
## 그림: art/objects/portal.png (원본 1263×1246, 돌바닥 밑동은 약 1232줄, 문 가운데는 (630, 720)).

## 건너갈 방과 그 방에서 설 자리(Marker2D 이름).
@export_file("*.tscn") var target_scene := ""
@export var spawn_name := ""
## 이 능력이 있어야 지나갈 수 있다 (예: lantern). 없으면 안내가 뜬다.
@export var requires_ability := ""
@export var locked_message := "어둠이 너무 짙다. 길을 밝힐 빛이 필요하다."
## 그림 크기 비율 (원본 1246줄 → 약 311px, 소녀 키의 2.3배).
@export var art_scale := 0.25
## 밑동을 땅속에 이만큼(픽셀) 묻어서 떠 보이지 않게 한다.
@export var sink := 10.0

const TEX := preload("res://art/objects/portal.png")
const OPAQUE_BOTTOM := 1232.0
const DOOR_CENTER := Vector2(630.0, 720.0)
const GLOW := Color(1.0, 0.9, 0.68)

var _sprite: Sprite2D
var _glow: Sprite2D
var _motes: CPUParticles2D
var _prompt: Label
var _player_near: Player
var _time := 0.0
var _used := false
var _warned_at := -10.0


func _ready() -> void:
	add_to_group("portal")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	var tex_size := TEX.get_size()
	# 밑동이 원점보다 sink 만큼 아래에 오게
	var offset_y := sink / art_scale - (OPAQUE_BOTTOM - tex_size.y / 2.0)
	var door := (DOOR_CENTER - tex_size / 2.0 + Vector2(0, offset_y)) * art_scale

	# 문 안의 빛 (더하기 혼합, 발광)
	_glow = Sprite2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	grad.colors = PackedColorArray([Color(GLOW, 0.6), Color(GLOW, 0.2), Color(GLOW, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 256
	gt.height = 256
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	_glow.texture = gt
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.position = door
	_glow.scale = Vector2(0.8, 1.15)
	add_child(_glow)

	_sprite = Sprite2D.new()
	_sprite.texture = TEX
	_sprite.scale = Vector2(art_scale, art_scale)
	_sprite.offset = Vector2(0, offset_y)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)

	# 문에서 피어오르는 빛 가루
	_motes = CPUParticles2D.new()
	_motes.amount = 18
	_motes.lifetime = 4.0
	_motes.preprocess = 4.0
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(50, 90)
	_motes.position = door + Vector2(0, 25)
	_motes.direction = Vector2(0, -1)
	_motes.spread = 30.0
	_motes.gravity = Vector2(0, -10)
	_motes.initial_velocity_min = 8.0
	_motes.initial_velocity_max = 26.0
	_motes.scale_amount_min = 1.2
	_motes.scale_amount_max = 3.0
	_motes.color = Color(GLOW.r * 1.6, GLOW.g * 1.6, GLOW.b * 1.6, 0.7)
	add_child(_motes)

	# 어두운 방에서는 포탈이 주변을 밝힌다
	var room := _room()
	if room and room.get("dark"):
		var light := PointLight2D.new()
		var lg := Gradient.new()
		lg.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		lg.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
		var lt := GradientTexture2D.new()
		lt.gradient = lg
		lt.width = 512
		lt.height = 512
		lt.fill = GradientTexture2D.FILL_RADIAL
		lt.fill_from = Vector2(0.5, 0.5)
		lt.fill_to = Vector2(1, 0.5)
		light.texture = lt
		light.texture_scale = 2.0
		light.energy = 1.3
		light.color = GLOW
		light.position = door
		add_child(light)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color("ffe9c0"))
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.position = Vector2(-90, -360)
	_prompt.visible = false
	add_child(_prompt)


func _room() -> Node:
	var n := get_parent()
	while n and not (n is Room):
		n = n.get_parent()
	return n


func _process(delta: float) -> void:
	_time += delta
	# 손길이 다른 대상을 고를 때(정화 기다리는 적이 먼저 — Player.pick_interactable)는 '들어가기'를 띄우지 않는다 (두 안내가 겹치지 않게)
	if _player_near and not _used and _player_near.pick_interactable() == self:
		_prompt.visible = true
		var locked := requires_ability != "" and not Progress.has_ability(requires_ability)
		_prompt.text = "잠긴 길" if locked else "%s  들어가기" % InputDevice.prompt("interact")
	else:
		_prompt.visible = false
	var pulse := 0.85 + 0.15 * sin(_time * 1.7)
	_glow.modulate = Color(1.5, 1.5, 1.5, 1.0) * pulse
	_glow.scale = Vector2(0.8, 1.15) * (0.95 + 0.08 * sin(_time * 1.1))


func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player_near = body
		body.register_interactable(self)


func _on_body_exited(body: Node) -> void:
	if body is Player:
		body.unregister_interactable(self)
		_player_near = null


## 소녀가 손길 버튼을 눌렀다 (△).
func interact(by: Player) -> void:
	_enter(by)


func _enter(by: Player) -> void:
	if _used or target_scene == "":
		return
	if requires_ability != "" and not Progress.has_ability(requires_ability):
		var now := Time.get_ticks_msec() / 1000.0
		if now - _warned_at > 2.0:
			_warned_at = now
			var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
			if hud:
				hud.show_message(locked_message, 2.5)
			Sfx.play("blip")
		return
	_used = true
	Progress.next_spawn = spawn_name
	by.input_enabled = false
	by.velocity = Vector2.ZERO
	Sfx.play("soul", -6.0, 0.0)
	flash()
	Game.go_to(target_scene, 0.5, 0.9)


## 빛이 번쩍인다 (들어갈 때, 건너와 도착했을 때).
func flash() -> void:
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 36
	burst.lifetime = 1.0
	burst.position = _glow.position
	burst.direction = Vector2(1, 0)
	burst.spread = 180.0
	burst.gravity = Vector2(0, -20)
	burst.initial_velocity_min = 60.0
	burst.initial_velocity_max = 200.0
	burst.scale_amount_min = 1.5
	burst.scale_amount_max = 4.0
	burst.color = Color(GLOW.r * 1.8, GLOW.g * 1.8, GLOW.b * 1.8, 0.9)
	burst.emitting = true
	add_child(burst)
	get_tree().create_timer(1.4).timeout.connect(burst.queue_free)
	_glow.scale = Vector2(2.2, 2.6)
	var tw := create_tween()
	tw.tween_property(_glow, "scale", Vector2(0.8, 1.15), 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

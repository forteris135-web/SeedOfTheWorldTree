extends Area2D
class_name Portal
## 포탈: 방과 방을 잇는 빛의 문. 가 본 방의 포탈끼리 이어져 있어, 손을 대면 다른 방으로 건너간다 (기획서 8장 "포탈").
## 그림: art/objects/portal.png (원본 1263×1246, 돌바닥 밑동은 약 1232줄, 문 가운데는 (630, 720)).
## 보스 방의 포탈은 수호자를 정화하기 전에는 잠들어 있다 (requires_flag).

@export var portal_id := ""
@export var display_name := ""
## 이 깃발이 있어야 깨어난다. 비어 있으면 처음부터 깨어 있다.
@export var requires_flag := ""
## 그림 크기 비율 (원본 1246줄 → 약 374px, 소녀 키의 2.8배).
@export var art_scale := 0.3
## 밑동을 땅속에 이만큼(픽셀) 묻어서 떠 보이지 않게 한다.
@export var sink := 10.0

const TEX := preload("res://art/objects/portal.png")
const OPAQUE_BOTTOM := 1232.0
const DOOR_CENTER := Vector2(630.0, 720.0)
const GLOW := Color(1.0, 0.9, 0.68)

var awake := true
var _sprite: Sprite2D
var _glow: Sprite2D
var _motes: CPUParticles2D
var _prompt: Label
var _player_near: Player
var _time := 0.0
var _menu: TravelMenu


func _ready() -> void:
	awake = requires_flag == "" or Progress.has(requires_flag)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if awake:
		add_to_group("portal")
		_register()

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
	_glow.scale = Vector2(0.9, 1.3)
	add_child(_glow)

	_sprite = Sprite2D.new()
	_sprite.texture = TEX
	_sprite.scale = Vector2(art_scale, art_scale)
	_sprite.offset = Vector2(0, offset_y)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)

	# 문에서 피어오르는 빛 가루
	_motes = CPUParticles2D.new()
	_motes.amount = 22
	_motes.lifetime = 4.0
	_motes.preprocess = 4.0
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(60, 110)
	_motes.position = door + Vector2(0, 30)
	_motes.direction = Vector2(0, -1)
	_motes.spread = 30.0
	_motes.gravity = Vector2(0, -10)
	_motes.initial_velocity_min = 8.0
	_motes.initial_velocity_max = 26.0
	_motes.scale_amount_min = 1.2
	_motes.scale_amount_max = 3.0
	_motes.color = Color(GLOW.r * 1.6, GLOW.g * 1.6, GLOW.b * 1.6, 0.7)
	_motes.emitting = awake
	add_child(_motes)

	# 어두운 방에서는 포탈이 주변을 밝힌다
	var room := _room()
	if awake and room and room.get("dark"):
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
		light.texture_scale = 2.2
		light.energy = 1.4
		light.color = GLOW
		light.position = door
		add_child(light)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color("ffe9c0"))
	_prompt.position = Vector2(-70, -420)
	_prompt.visible = false
	add_child(_prompt)

	if not awake:
		_sprite.modulate = Color(0.45, 0.45, 0.52)
		_glow.visible = false


func _room() -> Node:
	var n := get_parent()
	while n and not (n is Room):
		n = n.get_parent()
	return n


## 가 본 방의 포탈로 등록한다 (이동 메뉴에 나온다).
func _register() -> void:
	if portal_id == "":
		return
	var room := _room()
	var scene_path := room.scene_file_path if room else get_tree().current_scene.scene_file_path
	Progress.portals[portal_id] = {
		"scene": scene_path,
		"name": display_name if display_name != "" else portal_id,
		"region": room.region if room else "canopy",
	}


func _process(delta: float) -> void:
	_time += delta
	if _player_near:
		_prompt.visible = true
		_prompt.text = "%s  포탈" % InputDevice.prompt("interact") if awake else "잠들어 있는 포탈"
	else:
		_prompt.visible = false
	if awake:
		var pulse := 0.85 + 0.15 * sin(_time * 1.7)
		_glow.modulate = Color(1.5, 1.5, 1.5, 1.0) * pulse
		_glow.scale = Vector2(0.9, 1.3) * (0.95 + 0.08 * sin(_time * 1.1))


func _on_body_entered(body: Node) -> void:
	if body is Player:
		_player_near = body
		body.register_interactable(self)


func _on_body_exited(body: Node) -> void:
	if body is Player:
		body.unregister_interactable(self)
		_player_near = null


## 소녀가 손을 댔다 (△).
func interact(by: Player) -> void:
	if not awake:
		var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
		if hud:
			hud.show_message("포탈이 아직 잠들어 있다. 이 땅의 수호자를 정화해야 깨어난다.", 2.5)
		return
	Sfx.play("select")
	if _menu == null or not is_instance_valid(_menu):
		_menu = TravelMenu.new()
		get_tree().current_scene.add_child(_menu)
	_menu.open_portals(portal_id)


## 다른 포탈에서 건너와 도착했다: 빛이 번쩍이고 잠깐 멈춘다.
func arrive(by: Player) -> void:
	by.facing = 1
	by.velocity = Vector2.ZERO
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 40
	burst.lifetime = 1.1
	burst.position = _glow.position
	burst.direction = Vector2(1, 0)
	burst.spread = 180.0
	burst.gravity = Vector2(0, -20)
	burst.initial_velocity_min = 60.0
	burst.initial_velocity_max = 220.0
	burst.scale_amount_min = 1.5
	burst.scale_amount_max = 4.0
	burst.color = Color(GLOW.r * 1.8, GLOW.g * 1.8, GLOW.b * 1.8, 0.9)
	burst.emitting = true
	add_child(burst)
	get_tree().create_timer(1.5).timeout.connect(burst.queue_free)
	var tw := create_tween()
	_glow.scale = Vector2(2.4, 2.8)
	tw.tween_property(_glow, "scale", Vector2(0.9, 1.3), 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	Sfx.play("soul", -4.0, 0.0)
	# Room 이 바로 뒤에 input_enabled 를 켜므로, 한 프레임 뒤에 잠깐 잠근다
	call_deferred("_hold_after_arrive", by)


func _hold_after_arrive(by: Player) -> void:
	if not is_instance_valid(by):
		return
	by.input_enabled = false
	await get_tree().create_timer(0.45).timeout
	if is_instance_valid(by) and by.state != Player.State.DEAD:
		by.input_enabled = true

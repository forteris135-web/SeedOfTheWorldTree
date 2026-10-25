extends Area2D
class_name MoonlightGrass
## 달빛풀: 세이브 포인트. 처음엔 오므라든 채 희미하게 빛나고, 손을 대면(△) 천천히 펼쳐진다.
## 쉬면 체력·이슬이 채워지고, 일반 적이 다시 나타난다. 그림: art/objects/moonlight_grass_*.png
## 쉬는 중에 손길 버튼을 한 번 더 누르면 달빛풀 메뉴(GrassMenu: 이동 탭 / 성장 탭)가 열린다 (2026-10-19 기획자 요청 9번).

signal bloomed
signal rested(player: Player)

@export var is_open := false
## 이동 메뉴에서 쓰는 고유 이름과 표시 이름 (비어 있으면 이동 목록에 안 나온다).
@export var grass_id := ""
@export var display_name := ""
## 장식용 (쉴 수 없고 이동 목록에도 없음)
@export var decor := false
## 그림 크기 비율 (원본 약 1000×1024 → 소녀보다 훨씬 크게).
@export var art_scale := 0.34

const CLOSED_TEX := preload("res://art/objects/moonlight_grass_closed.png")
const OPEN_TEX := preload("res://art/objects/moonlight_grass_open.png")
const GLOW := Color(0.56, 0.83, 1.0)

var _bloom := 0.0
var _time := 0.0
var _player_near: Player
var _prompt: Label
var _spores: CPUParticles2D
var _closed: Sprite2D
var _open: Sprite2D
var _glow: Sprite2D


const GRASS_MENU := preload("res://scenes/ui/grass_menu.tscn")

var _menu: GrassMenu
var _resting_player: Player
## 쉬기 시작한 그 손길 버튼이 떨어진 뒤에야 메뉴를 연다 (쉬자마자 열리지 않게).
var _travel_armed := false


func _ready() -> void:
	if not decor:
		add_to_group("moonlight_grass")
	# 이미 피워 둔 달빛풀이면 피어 있는 채로 시작
	if grass_id != "" and Progress.grasses.has(grass_id):
		is_open = true
	_bloom = 1.0 if is_open else 0.0
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# 바닥의 빛 (더하기 혼합, 발광)
	_glow = Sprite2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	grad.colors = PackedColorArray([Color(GLOW, 0.55), Color(GLOW, 0.18), Color(GLOW, 0.0)])
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
	_glow.position = Vector2(0, -150)
	add_child(_glow)

	# 밑동의 그림자 (땅에 붙어 보이게)
	var shadow := Sprite2D.new()
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	sg.colors = PackedColorArray([Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.2), Color(0, 0, 0, 0.0)])
	var st := GradientTexture2D.new()
	st.gradient = sg
	st.width = 256
	st.height = 64
	st.fill = GradientTexture2D.FILL_RADIAL
	st.fill_from = Vector2(0.5, 0.5)
	st.fill_to = Vector2(1.0, 0.5)
	shadow.texture = st
	shadow.position = Vector2(0, 2)
	shadow.scale = Vector2(0.8, 0.6)
	add_child(shadow)

	_closed = _make_sprite(CLOSED_TEX)
	_open = _make_sprite(OPEN_TEX)

	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_color", Color("cfe9ff"))
	_prompt.position = Vector2(-60, -400)
	_prompt.visible = false
	add_child(_prompt)

	_spores = CPUParticles2D.new()
	_spores.amount = 26
	_spores.lifetime = 5.0
	_spores.preprocess = 5.0
	_spores.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_spores.emission_rect_extents = Vector2(120, 10)
	_spores.position = Vector2(0, -80)
	_spores.direction = Vector2(0, -1)
	_spores.spread = 25.0
	_spores.gravity = Vector2(0, -12)
	_spores.initial_velocity_min = 10.0
	_spores.initial_velocity_max = 30.0
	_spores.scale_amount_min = 1.5
	_spores.scale_amount_max = 3.5
	_spores.color = Color(GLOW.r * 1.6, GLOW.g * 1.6, GLOW.b * 1.6, 0.7)
	_spores.emitting = is_open
	add_child(_spores)
	_apply_bloom()


## 그림 속 밑동(불투명한 마지막 줄)이 어디인지. 닫힘 994, 열림 1013 (1024 중).
const OPAQUE_BOTTOM := {"moonlight_grass_closed": 994.0, "moonlight_grass_open": 1013.0}
## 밑동을 땅속에 이만큼(픽셀) 묻어서 떠 보이지 않게 한다.
@export var sink := 26.0


func _make_sprite(tex: Texture2D) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2(art_scale, art_scale)
	var bottom: float = OPAQUE_BOTTOM.get(tex.resource_path.get_file().get_basename(), float(tex.get_height()))
	# 밑동이 원점보다 sink 만큼 아래에 오게
	s.offset = Vector2(0, sink / art_scale - (bottom - tex.get_height() / 2.0))
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(s)
	return s


func _process(delta: float) -> void:
	_time += delta
	if _player_near:
		var resting := _player_near.state == Player.State.REST
		_prompt.visible = true
		if resting:
			_prompt.text = "%s  이동 · 성장 · 기술" % InputDevice.prompt("interact")
		else:
			_prompt.text = "%s  %s" % [InputDevice.prompt("interact"), "쉬기" if is_open else "손을 대기"]
	else:
		_prompt.visible = false
	var pulse := 0.9 + 0.1 * sin(_time * 2.0)
	var strength := 0.5 + 0.7 * _bloom
	_glow.modulate = Color(1.4, 1.4, 1.4, 1.0) * pulse * strength
	_glow.scale = Vector2.ONE * (1.3 + 1.6 * _bloom) * pulse
	# 펼쳐진 잎은 살랑인다
	_open.rotation = sin(_time * 0.8) * 0.012 * _bloom


## 쉬는 중에 손길 버튼을 한 번 더 누르면 달빛풀 메뉴(이동 / 성장). (소녀와 같은 물리 틱에서 입력을 읽는다)
func _physics_process(_delta: float) -> void:
	if _player_near == null or _player_near.state != Player.State.REST:
		_travel_armed = false
		return
	if not _player_near.input_enabled or (_menu and is_instance_valid(_menu) and _menu.is_open()):
		return
	if not _travel_armed:
		# 쉬기 시작한 그 버튼이 떨어진 뒤부터
		if not Input.is_action_pressed("interact"):
			_travel_armed = true
	elif Input.is_action_just_pressed("interact"):
		_open_menu()


func _apply_bloom() -> void:
	_closed.modulate.a = 1.0 - _bloom
	_open.modulate.a = _bloom
	_open.scale = Vector2(art_scale, art_scale) * (0.85 + 0.15 * _bloom)
	_closed.scale = Vector2(art_scale, art_scale) * (1.0 - 0.1 * _bloom)


func _on_body_entered(body: Node) -> void:
	if body is Player and not decor:
		_player_near = body
		body.register_interactable(self)


func _on_body_exited(body: Node) -> void:
	if body is Player:
		body.unregister_interactable(self)
		_player_near = null


## 소녀가 △를 눌렀다.
func interact(by: Player) -> void:
	if not is_open:
		is_open = true
		by.input_enabled = false
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			_bloom = v
			_apply_bloom(), 0.0, 1.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		Sfx.play("bloom", -2.0, 0.0)
		await tw.finished
		_spores.emitting = true
		bloomed.emit()
		by.input_enabled = true
	_register()
	by.start_rest(self)
	rested.emit(by)
	if grass_id != "":
		SaveGame.save(grass_id, _room_scene())
		var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
		if hud:
			hud.flash("저장되었다")


func _register() -> void:
	if grass_id != "":
		var scene_path := _room_scene()
		# 이름은 지도와 같은 방 이름 (v1.1.0 기획자 요청 21 — RoomIndex). 방 목록에 없으면 이 달빛풀의 표시 이름.
		var shown := RoomIndex.grass_room_name(grass_id, display_name if display_name != "" else grass_id)
		Progress.grasses[grass_id] = {"scene": scene_path, "name": shown}
		Progress.last_grass = {"id": grass_id, "scene": scene_path, "name": shown}


## 이 달빛풀이 놓인 방의 파일 경로 (시험처럼 방이 '지금 장면'의 자식으로 놓여 있어도 방 파일을 가리키게).
func _room_scene() -> String:
	var n := get_parent()
	while n != null:
		if n is Room and (n as Room).scene_file_path != "":
			return (n as Room).scene_file_path
		n = n.get_parent()
	var cs := get_tree().current_scene
	return cs.scene_file_path if cs else ""


## 이동해서 도착했다: 바로 쉬는 자세로.
func arrive(by: Player) -> void:
	is_open = true
	_bloom = 1.0
	_apply_bloom()
	_spores.emitting = true
	_player_near = by
	by.register_interactable(self)
	_register()
	by.call_deferred("start_rest", self)


## 달빛풀 메뉴를 연다 (이동 탭으로 시작). 시험·다른 코드가 바로 부를 수 있다.
func _open_menu() -> void:
	if _menu == null or not is_instance_valid(_menu):
		_menu = GRASS_MENU.instantiate()
		get_tree().current_scene.add_child(_menu)
		_menu.closed.connect(_on_menu_closed)
	# 머리 위 안내 글자는 멈춤 동안 어두운 판 밑으로 비치므로 숨긴다 (닫히면 _process 가 다시 띄운다)
	_prompt.visible = false
	_menu.open_grass(grass_id)


## 메뉴가 닫혔다: 손길 버튼이 한 번 떨어진 뒤에야 다시 연다 ('(여기)'를 손길로 골라 닫은 그 누름으로 다시 열리지 않게).
func _on_menu_closed() -> void:
	_travel_armed = false


## 열려 있는 달빛풀 메뉴 (없으면 null)
func menu() -> GrassMenu:
	return _menu if _menu and is_instance_valid(_menu) else null

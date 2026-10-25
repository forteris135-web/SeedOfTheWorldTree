extends Node2D
class_name EndingChoice
## 마지막 선택지. 말 대신 행동으로: 심연의 뿌리에 손을 얹는가(희생), 마력의 관을 끊는가(되돌림).
## 둘 다 △. 가까이 가면 셀레니아가 허리의 등불을 내려다보는 짧은 연출(입력 잠깐 잠김) 뒤 선택할 수 있다 (어느 장치든 처음 한 번).
## 확장판(EXPANSION.md 7장) — 세 번째 행동 "심연의 거대한 펌프를 거꾸로 돌린다"(third).
## v1.1.0(기획자 요청 27, D16): 제3의 길 조건 = 뿌리지기 정화 + **경전의 잃어버린 조각 네 장(scripture_1~4)을 모두 읽음**.
##   (사당 경전·훼손된 경전은 조건이 아니다. 예전의 '다섯 영혼(네 능력)' 조건은 없앴다.)
##   조건이 모자라면 장치는 **보이되 꺼져 있다**: 잿빛, 빛·회전 멈춤, 손길 거절, 가까이 가면 "경전의 조각이 모자라다 (n/4)".
##   조건이 차면 깃발 five_souls(티아의 마지막 말이 열린다)를 세우고 평소처럼 고를 수 있다.
## 고르면 다섯 빛 구슬이 모여 물레방아를 거꾸로 돌리는 빛 소용돌이(3초) 뒤 엔딩 "third" 로 간다.
## v1.1.0 번외: 세 장치 모두 기획자 그림(ending/뿌리.png·관.png·진엔딩.png → tools/cut_ending_devices.gd → art/objects/object_choice_*.png).
##   노드 자리 = 밑동(바닥). 제3의 길은 받침 뒤에서 톱니 테·바퀴살·굴대가 진짜로 돈다. 빛(불꽃 심·밸브 핵·굴대 핵·기둥 등불)은 더하기 혼합.
##   일반 엔딩 둘은 v1.1.0 부터 새 방 '심연 · 두 갈래 길'(abyss_ending, scripts/world/ending_room.gd)에, 뿌리지기 방에는 제3의 길만.

@export_enum("sacrifice", "return", "third") var choice := "sacrifice"
@export var label := "뿌리에 손을 얹는다"

const ROOT_FLAG := "boss_root_defeated"
const SOUL_COLORS := [Color(0.75, 1.0, 0.85), Color(1.0, 0.85, 0.45), Color(0.45, 0.85, 0.95), Color(1.0, 0.55, 0.3), Color(0.8, 0.65, 1.0)]
## 제3의 길이 잠겼을 때 가까이 가면 뜨는 안내 (%d = 읽은 조각 수)
const LOCKED_HINT := "경전의 조각이 모자라다 (%d/4)"
## 잠긴 장치의 색
const LOCKED_TINT := Color(0.45, 0.45, 0.5, 1.0)
## 밑동을 땅에 묻는 깊이 (px)
const SINK := 6.0

## 그림 (tools/cut_ending_devices.gd 가 만든다 — 다시 자르면 아래 자리 값도 그 도구가 출력한 값으로 맞춘다)
const TEX_ROOT := preload("res://art/objects/object_choice_root.png")
const TEX_PIPE := preload("res://art/objects/object_choice_pipe.png")
const TEX_PUMP_BASE := preload("res://art/objects/object_choice_pump_base.png")
const TEX_PUMP_RING := preload("res://art/objects/object_choice_pump_ring.png")
const TEX_PUMP_SPOKES := preload("res://art/objects/object_choice_pump_spokes.png")
const TEX_PUMP_HUB := preload("res://art/objects/object_choice_pump_hub.png")
## 희생: 화면 높이 약 340 (배율), 밑동·불꽃 심 자리 (그림 px)
const ROOT_SCALE := 0.8
const ROOT_FOOT := Vector2(254.5, 419.3)
const ROOT_FLAME := Vector2(253.8, 175.2)
## 되돌림: 화면 높이 약 345, 밑동·밸브 핵 자리
const PIPE_SCALE := 0.468
const PIPE_FOOT := Vector2(148.0, 737.0)
const PIPE_VALVE := Vector2(136.1, 339.5)
## 제3의 길: 받침 폭 약 430·높이 약 370, 밑동·바퀴 중심·기둥 등불 자리 (받침 그림 px), 도는 조각 배율 (받침 배율에 곱함)
const PUMP_SCALE := 0.786
const PUMP_FOOT := Vector2(272.5, 473.0)
const PUMP_WHEEL := Vector2(313.25, 213.3)
const PUMP_LAMPS := [Vector2(205.0, 300.0), Vector2(423.0, 300.0)]
const PUMP_RING_K := 1.25
const PUMP_SPOKES_K := 1.1
const PUMP_HUB_K := 0.72
## 평소 도는 빠르기 (rad/s, '뽑는' 방향)
const PUMP_IDLE_SPIN := 0.15

var _near: Player
var _prompt: Label
var _t := 0.0
var _locked := false
var _ritual := -1.0   # 제3의 길 연출 진행(초). 음수면 아님
var _spin := 0.0      # 물레방아의 회전각 (거꾸로 돌면 줄어든다)
var _art: Node2D      # 그림 전부 (잠기면 잿빛)
var _wheel: Node2D    # 제3의 길: 도는 조각들 (바퀴 중심)
var _glows: Array[Sprite2D] = []
var _fx: Node2D       # 의식 연출을 그림 위에 그린다
var _top := -340.0    # 그림 윗끝 (안내 글자 자리)
var _center := Vector2(0, -190)   # 의식 연출의 중심 (제3의 길 = 바퀴 중심)

static var _glow_tex: GradientTexture2D
static var _add_mat: CanvasItemMaterial


## 제3의 길 조건: 뿌리지기 정화 + 경전의 잃어버린 조각 네 장(scripture_1~4)을 모두 읽음.
static func third_unlocked() -> bool:
	return Progress.has(ROOT_FLAG) and Progress.has_all_scriptures()


## 옛 이름 (호환): 제3의 길이 열렸는가
static func has_five_souls() -> bool:
	return third_unlocked()


func _ready() -> void:
	_build_art()
	_fx = Node2D.new()
	_fx.draw.connect(_draw_ritual)
	add_child(_fx)
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 24)
	var col := Color("ffe6b0")
	if choice == "return":
		col = Color("cfe9ff")
	elif choice == "third":
		col = Color("ffd0a0")
	_prompt.add_theme_color_override("font_color", col)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.size = Vector2(560, 40)
	_prompt.position = Vector2(-280, _top - 56.0)
	_prompt.visible = false
	add_child(_prompt)
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 170.0
	shape.shape = c
	shape.position = Vector2(0, -80)
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_enter)
	area.body_exited.connect(_on_exit)
	if choice == "third":
		_refresh_lock()
		Progress.flag_changed.connect(_on_flag_changed)


func is_locked() -> bool:
	return _locked


func _on_flag_changed(_flag: String, _value: bool) -> void:
	if _ritual < 0.0:
		_refresh_lock()


## 제3의 길: 조건에 따라 잠금·겉모습을 바꾼다 (경전을 다 읽으면 그 자리에서 깨어난다).
func _refresh_lock() -> void:
	var was := _locked
	_locked = not third_unlocked()
	visible = true
	_art.modulate = LOCKED_TINT if _locked else Color.WHITE
	for g in _glows:
		g.visible = not _locked
	if not _locked and not Progress.has("five_souls"):
		Progress.set_flag("five_souls")   # 티아의 마지막 말이 열린다
	# 잠금이 풀리는 순간 이미 곁에 서 있으면 바로 고를 수 있게
	if was and not _locked and _near and is_instance_valid(_near):
		_near.register_interactable(self)


func _on_enter(b: Node) -> void:
	if not (b is Player):
		return
	_near = b
	if not _locked:
		b.register_interactable(self)
	if not Progress.has("looked_at_lantern"):
		Progress.set_flag("looked_at_lantern")
		# 등불을 내려다본다
		b.input_enabled = false
		b.velocity = Vector2.ZERO
		var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
		if hud:
			hud.show_message("셀레니아는 허리의 작은 등불을 내려다보았다.", 3.0)
		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(b):
			b.input_enabled = true


func _on_exit(b: Node) -> void:
	if b is Player:
		b.unregister_interactable(self)
		_near = null


func _process(delta: float) -> void:
	_t += delta
	if _ritual >= 0.0:
		_ritual += delta
		# 거꾸로 도는 물레방아: 점점 빨리
		_spin -= delta * (0.4 + _ritual * 1.4)
		_fx.queue_redraw()
	elif not _locked:
		_spin += delta * PUMP_IDLE_SPIN   # 평소엔 아주 천천히 '뽑는' 방향으로 돈다
	if _wheel:
		_spin = wrapf(_spin, -TAU, TAU)
		_wheel.rotation = _spin
	if not _locked:
		var pulse := 0.6 + 0.4 * sin(_t * 1.8)
		if _ritual >= 0.0:
			pulse = clampf(1.0 + _ritual * 0.5, 1.0, 2.5)
		for g in _glows:
			g.modulate.a = pulse * float(g.get_meta("strength", 1.0))
	var show := _near != null and _ritual < 0.0 and (_locked or _near.input_enabled)
	_prompt.visible = show
	if show:
		_prompt.text = LOCKED_HINT % Progress.scripture_count() if _locked else "%s  %s" % [InputDevice.prompt("interact"), label]


func interact(by: Player) -> void:
	if _locked:
		return
	by.input_enabled = false
	by.velocity = Vector2.ZERO
	Progress.ending = choice
	var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
	if choice == "third":
		# 다섯 영혼이 함께 물레방아를 거꾸로 돌린다 (3초 연출)
		_ritual = 0.0
		if hud:
			hud.show_message("다섯 영혼이 함께 손을 얹었다.", 3.0)
		Sfx.play("soul", 0.0, 0.0)
		Juice.rumble(0.3, 0.6, 0.6)
		await get_tree().create_timer(1.6).timeout
		Sfx.play("purify", 0.0, 0.0)
		Juice.shake(8.0)
		await get_tree().create_timer(1.4).timeout
		Game.go_to("res://scenes/ui/ending_scene.tscn", 2.2, 1.5)
		return
	if hud:
		hud.show_message("…", 1.0)
	Juice.rumble(0.3, 0.6, 0.6)
	await get_tree().create_timer(1.2).timeout
	Game.go_to("res://scenes/ui/ending_scene.tscn", 2.2, 1.5)


# ---------- 그림 ----------

## 그림 노드를 만든다 (밑동이 노드 원점, SINK 만큼 땅에 묻힘).
func _build_art() -> void:
	_art = Node2D.new()
	add_child(_art)
	match choice:
		"sacrifice":
			_sprite(_art, TEX_ROOT, ROOT_SCALE, ROOT_FOOT)
			_top = -ROOT_FOOT.y * ROOT_SCALE
			_center = _at(ROOT_FLAME, ROOT_FOOT, ROOT_SCALE)
			_glow(_center, 96.0, Color(1.6, 1.15, 0.55), 0.32)
			_glow(_center, 40.0, Color(2.0, 1.6, 1.0), 0.6)
		"return":
			_sprite(_art, TEX_PIPE, PIPE_SCALE, PIPE_FOOT)
			_top = -PIPE_FOOT.y * PIPE_SCALE
			_center = _at(PIPE_VALVE, PIPE_FOOT, PIPE_SCALE)
			_glow(_center, 56.0, Color(0.7, 1.3, 2.0), 0.5)
			# 관 속 수액 빛 (세로로 긴 은은한 빛)
			var tube := _glow(Vector2(0, _top * 0.5), 150.0, Color(0.5, 0.9, 1.6), 0.25)
			tube.scale = Vector2(0.35, 1.6) * (150.0 / 64.0)
		"third":
			_center = _at(PUMP_WHEEL, PUMP_FOOT, PUMP_SCALE)
			_wheel = Node2D.new()
			_wheel.position = _center
			_art.add_child(_wheel)
			for pair in [[TEX_PUMP_SPOKES, PUMP_SPOKES_K], [TEX_PUMP_RING, PUMP_RING_K], [TEX_PUMP_HUB, PUMP_HUB_K]]:
				var s := Sprite2D.new()
				s.texture = pair[0]
				s.scale = Vector2.ONE * PUMP_SCALE * float(pair[1])
				s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
				_wheel.add_child(s)
			_sprite(_art, TEX_PUMP_BASE, PUMP_SCALE, PUMP_FOOT)
			_top = -PUMP_FOOT.y * PUMP_SCALE
			_glow(_center, 52.0, Color(0.7, 1.3, 2.0), 0.5)
			for lamp in PUMP_LAMPS:
				_glow(_at(lamp, PUMP_FOOT, PUMP_SCALE), 34.0, Color(1.8, 1.25, 0.6), 0.6)


## 그림 px 자리 → 노드 자리
func _at(p: Vector2, foot: Vector2, k: float) -> Vector2:
	return (p - foot) * k + Vector2(0, SINK)


func _sprite(parent: Node, tex: Texture2D, k: float, foot: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = -foot
	s.scale = Vector2(k, k)
	s.position = Vector2(0, SINK)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent.add_child(s)
	return s


## 더하기 혼합 빛 (반지름 r px, HDR 색 — 1 넘는 부분은 방의 글로우로 번진다). strength = 맥동의 최대 진하기.
func _glow(at: Vector2, r: float, col: Color, strength: float) -> Sprite2D:
	if _glow_tex == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = grad
		_glow_tex.width = 128
		_glow_tex.height = 128
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1, 0.5)
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var g := Sprite2D.new()
	g.texture = _glow_tex
	g.material = _add_mat
	g.position = at
	g.scale = Vector2.ONE * (r / 64.0)
	g.self_modulate = col
	g.modulate.a = strength
	g.set_meta("strength", strength)
	_art.add_child(g)
	_glows.append(g)
	return g


## 제3의 길 연출: 다섯 빛 구슬이 바퀴 둘레에서 가운데로 모여들며 돌고, 거꾸로 도는 화살·빛 소용돌이·흰 섬광 (그림 위에 그린다)
func _draw_ritual() -> void:
	if _ritual < 0.0:
		return
	var c := _center
	# 톱니 테 반지름 (그림 px 약 160 × 배율)
	var r := 160.0 * PUMP_SCALE * PUMP_RING_K if choice == "third" else 110.0
	var k := clampf(_ritual / 3.0, 0.0, 1.0)
	for i in 3:
		var a0 := -_spin * 0.5 + i * TAU / 3.0
		_fx.draw_arc(c, r + 50.0 + i * 8.0, a0, a0 + 1.6, 14, Color(1.0, 0.9, 0.7, 0.5 * k), 4.0, true)
	# 다섯 빛 구슬: 둘레에서 가운데로 모여들며 돈다
	for i in 5:
		var ang := -_t * 2.0 + i * TAU / 5.0
		var dist := lerpf(r + 140.0, 30.0, Motion.ease_in_out(k))
		var p := c + Vector2(cos(ang), sin(ang) * 0.8) * dist
		var col: Color = SOUL_COLORS[i]
		_fx.draw_circle(p, 34.0, Color(col, 0.18))
		_fx.draw_circle(p, 14.0, Color(col, 0.95))
		_fx.draw_circle(p + Vector2(-4, -4), 5.0, Color(1, 1, 1, 0.8))
	# 빛 소용돌이
	for i in 6:
		var a := -_t * 5.0 + i * 1.05
		var rr := 40.0 + i * 24.0 + k * 60.0
		_fx.draw_arc(c, rr, a, a + 1.2, 10, Color(0.85, 0.95, 1.0, 0.35 * k), 3.0, true)
	# 끝자락: 다섯 빛이 하나로 합쳐져 하얗게 터진다 (밝은 값은 글로우로 번지고, 곧 엔딩으로 어두워진다)
	var burst := clampf((_ritual - 2.1) / 0.9, 0.0, 1.0)
	if burst > 0.0:
		# 겹친 원 열둘로 가장자리가 부드러운 빛 무리 (가운데로 갈수록 진하다)
		var big := 60.0 + 560.0 * Motion.ease_in_out(burst)
		for i in 12:
			_fx.draw_circle(c, big * float(i + 1) / 12.0, Color(1.0, 0.97, 0.9, 0.035 * burst))
		for i in 4:
			_fx.draw_circle(c, (26.0 + 80.0 * burst) * float(i + 1) / 4.0, Color(1.5, 1.45, 1.3, 0.16 * burst))


## 시험용: 그림 노드들
func art_node() -> Node2D:
	return _art


func wheel_node() -> Node2D:
	return _wheel


func ritual_center() -> Vector2:
	return _center

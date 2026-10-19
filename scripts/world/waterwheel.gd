class_name Waterwheel
extends Node2D
## 물레방아 (잠긴 채굴장 장식 — 판정 없음). 기획자가 따로 그린 물레방아 조각을 조립해 천천히 돌린다.
##   익스펜션/그림/물레방아/11A4E5F6… : 바퀴 테두리 1/4 조각·바퀴살과 축·물 뿜는 관 탑·이끼 낀 바위
## 조각은 잠긴 채굴장 그림 옷 atlas 에 들어 있다 (data/terrain/flooded_mine.json 의 역할 wheel / prop).
##
## 조립 (노드 자리 = 바퀴 축):
##  - 바퀴: 축(wheel_hub, 바퀴살 6개) + 테두리 조각(wheel_ring)을 90°씩 돌려 네 번 → 동그란 바퀴. 이 묶음만 돈다.
##    (테두리 조각에 그려진 물방울은 돌리면 옆으로 흐르므로 자를 때 지웠다 — 물은 아래 입자로 늘 아래로 떨어진다)
##  - 관 탑(tower_a): 바퀴 왼쪽 뒤. 관 끝에서 물줄기가 바퀴 위로 쏟아진다 (입자, 아래로).
##  - 바위(rock_a·rock_b, 이끼 낀 바위와 뿌리): 바퀴 아래 양옆 — 바퀴 밑동을 가리고 물이 고인 자리를 만든다.
##  - 물보라: 바퀴 아래에서 작은 물방울이 튄다.
## 정화 전에는 공용 잿빛 재질로 잿빛, 정화 뒤에는 원래 색. 물방울은 잿빛 재질을 거치지 않아 늘 푸르게 빛난다.
## 매 프레임 하는 일은 바퀴 묶음의 rotation 바꾸기뿐이다 (다시 그리지 않음).

## 크기 (조각 1px → 월드 px). 0.7 이면 바퀴 지름 약 320px (소녀 키의 2.4배).
@export var art_scale := 0.7
## 도는 빠르기 (라디안/초). 음수면 반대로 (물이 왼쪽 위에서 쏟아지면 시계 반대 방향… 기본은 물 쪽이 내려가게 −)
@export var speed := -0.32
@export var with_tower := true
@export var with_rocks := true
@export var with_water := true
## 색 곱하기 (1 보다 작으면 어둡게 — 뒤 장식이 발판으로 오해받지 않게)
@export var shade := Color(1.0, 1.0, 1.0, 1.0)
## 지역 강제 (비우면 방의 지역)
@export var region := ""

## 테두리 조각 안에서 바퀴 축의 자리 (조각 px, tools 로 원을 맞춰 잰 값: 안쪽 반지름 약 141)
const RING_CENTER := Vector2(-36.0, 82.0)
## 축 조각 안에서 바퀴 축의 자리 (조각 px)
const HUB_CENTER := Vector2(124.0, 156.0)
## 바퀴 테두리 바깥 반지름 / 물받이 판 끝까지 (조각 px)
const R_RING := 182.0
const R_OUT := 280.0
## 관 탑 조각 안에서 관 끝(물 나오는 구멍)의 자리 (조각 px)
const TOWER_OUTLET := Vector2(168.0, 42.0)

var _wheel: Node2D
var _skin: TerrainSkin


func _ready() -> void:
	var r := region if region != "" else TerrainStyle.region_of(self)
	_skin = TerrainSkin.for_region(r)
	if _skin == null or not _skin.pieces.has("wheel_ring") or not _skin.pieces.has("wheel_hub"):
		return
	material = preload("res://shaders/ash_purify_far.tres")   # 배경 장식: 배경 그림과 같은 재질 (앞뒤 가르기 — 발판으로 오해받지 않게 아지랑이 뒤로)
	var k := art_scale
	# 뒤: 관 탑 (바퀴 왼쪽 뒤, 관 끝이 바퀴 왼쪽 위에 오게)
	var outlet := Vector2(-R_RING * 0.78, -R_RING * 1.02) * k
	if with_tower and _skin.pieces.has("tower_a"):
		var tk := k * 1.25
		var tsize := _skin.size_of("tower_a") * tk
		# 관 끝이 outlet 에 오도록 탑을 놓는다
		var top_left := outlet - TOWER_OUTLET * tk
		var p := _Piece.new(_skin, "tower_a", top_left, tk, shade)
		add_child(p)
	# 바퀴 (돈다)
	_wheel = Node2D.new()
	_wheel.name = "Wheel"
	_wheel.use_parent_material = true
	add_child(_wheel)
	var hub := _Piece.new(_skin, "wheel_hub", -HUB_CENTER * k, k, shade)
	_wheel.add_child(hub)
	for i in 4:
		var q := _Piece.new(_skin, "wheel_ring", -RING_CENTER * k, k, shade)
		q.rotation = i * PI * 0.5
		_wheel.add_child(q)
	# 앞: 바위 (바퀴 밑동을 가린다)
	if with_rocks:
		if _skin.pieces.has("rock_b"):
			_prop("rock_b", Vector2(-R_RING * 0.6, R_RING * 1.2) * k, k * 1.1, false)
		if _skin.pieces.has("rock_a"):
			_prop("rock_a", Vector2(R_RING * 0.55, R_RING * 1.15) * k, k * 1.15, true)
	if with_water:
		_add_water(k, outlet)
	set_process(absf(speed) > 0.0001)


func _process(delta: float) -> void:
	if _wheel:
		_wheel.rotation = wrapf(_wheel.rotation + speed * delta, -PI, PI)


## 조각 하나 (밑동 가운데가 at 에 오게)
func _prop(name: String, at: Vector2, k: float, flip: bool) -> void:
	var size := _skin.size_of(name) * k
	var p := _Piece.new(_skin, name, at - Vector2(size.x * 0.5, size.y), k, shade)
	p.flip = flip
	add_child(p)


## 물줄기 (관 끝 → 바퀴 위) + 바퀴 아래 물보라. 잿빛 재질을 거치지 않는다 (물빛은 늘 푸르게).
func _add_water(k: float, outlet: Vector2) -> void:
	var stream := CPUParticles2D.new()
	stream.name = "Stream"
	stream.position = outlet
	stream.amount = 40
	stream.lifetime = 1.1
	stream.preprocess = 1.1
	stream.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	stream.emission_rect_extents = Vector2(9.0 * k, 2.0)
	stream.direction = Vector2(0.15, 1.0)
	stream.spread = 4.0
	stream.gravity = Vector2(0, 520)
	stream.initial_velocity_min = 40.0
	stream.initial_velocity_max = 70.0
	stream.texture = _dot_tex()
	stream.scale_amount_min = 0.55
	stream.scale_amount_max = 1.0
	stream.color = Color(0.62, 0.9, 1.0, 0.55)
	stream.material = _add_mat()
	add_child(stream)
	var splash := CPUParticles2D.new()
	splash.name = "Splash"
	splash.position = Vector2(0, R_RING * 0.95) * k
	splash.amount = 18
	splash.lifetime = 0.9
	splash.preprocess = 0.9
	splash.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	splash.emission_rect_extents = Vector2(R_RING * 0.6 * k, 3.0)
	splash.direction = Vector2(0, -1)
	splash.spread = 35.0
	splash.gravity = Vector2(0, 380)
	splash.initial_velocity_min = 60.0
	splash.initial_velocity_max = 130.0
	splash.texture = _dot_tex()
	splash.scale_amount_min = 0.3
	splash.scale_amount_max = 0.6
	splash.color = Color(0.7, 0.95, 1.0, 0.45)
	splash.material = _add_mat()
	add_child(splash)


## 부드러운 물방울 점 (입자 그림 — 한 번 만들어 같이 쓴다)
static var _dot: GradientTexture2D
static func _dot_tex() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.width = 16
		_dot.height = 16
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
	return _dot


static func _add_mat() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


## atlas 조각 하나를 그리는 작은 노드 (offset 자리에 왼쪽 위, 배율 k)
class _Piece extends Node2D:
	var skin: TerrainSkin
	var piece := ""
	var offset := Vector2.ZERO
	var k := 1.0
	var col := Color(1, 1, 1, 1)
	var flip := false

	func _init(s: TerrainSkin, n: String, off: Vector2, scale_k: float, shade: Color) -> void:
		skin = s
		piece = n
		offset = off
		k = scale_k
		col = Color(s.tint.r * shade.r, s.tint.g * shade.g, s.tint.b * shade.b, shade.a)
		use_parent_material = true
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	func _draw() -> void:
		var size := skin.size_of(piece) * k
		var r := Rect2(offset, size)
		if flip:
			draw_set_transform(Vector2(offset.x * 2.0 + size.x, 0.0), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(skin.atlas, r, skin.rect_of(piece), col)

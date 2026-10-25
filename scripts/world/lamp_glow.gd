extends Node2D
## 등불 하나의 따뜻한 빛 (더하기 혼합, 잔잔한 깜빡임 — 판정 없음, 겉모습만).
## 배경 아지랑이(ash_purify_prop)에 묻히는 장식 등불(TerrainProp)의 등 자리에 붙여, 멀리서도 '불 켜진 등불'로 읽히게 한다.
## 예: 관의 복도(mine_02) 펌프실 입구의 등불 기둥 Props/PumpLamp (v1.1.0 검수 — 요청 19 '입구 찾기 쉽게': 등불 기둥이 안개에 묻혀
## 입구를 알려 주는 것이 포탈 빛뿐이었다). 잿빛 재질을 받지 않는다 (포탈 빛처럼 정화 전에도 따뜻한 색).
## energy 가 1 을 넘으면 화면 글로우(WorldEnvironment, 임계 1.0)가 살짝 번진다.

## 빛 무리 반지름 (월드 px)
@export var radius := 80.0
@export var color := Color(1.0, 0.70, 0.36)
## 밝기 곱 (무리 / 심)
@export var energy := 0.9
@export var core_energy := 1.25
## 깜빡임 세기 (0 = 없음)
@export var flicker := 0.10

static var _tex: GradientTexture2D
var _halo: Sprite2D
var _core: Sprite2D
var _t := 0.0
var _phase := 0.0


func _ready() -> void:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_phase = fposmod(global_position.x * 0.017 + global_position.y * 0.031, TAU)
	# 등 그림 뒤에 그린다: 등의 틀·창살이 빛 앞에 비쳐 '불 켜진 등'으로 읽히게 (앞에 그리면 떠다니는 불덩이처럼 보였다)
	show_behind_parent = true
	_halo = _make(mat, radius)
	_core = _make(mat, radius * 0.24)
	_apply(1.0)


func _make(mat: Material, r: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _texture()
	s.material = mat
	s.scale = Vector2.ONE * (r * 2.0 / float(_texture().width))
	add_child(s)
	return s


static func _texture() -> GradientTexture2D:
	if _tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0)])
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.width = 128
		_tex.height = 128
		_tex.fill = GradientTexture2D.FILL_RADIAL
		_tex.fill_from = Vector2(0.5, 0.5)
		_tex.fill_to = Vector2(1.0, 0.5)
	return _tex


func _process(delta: float) -> void:
	_t += delta
	var k := 1.0 + flicker * (0.6 * sin(_t * 2.3 + _phase) + 0.4 * sin(_t * 5.7 + _phase * 1.7))
	_apply(k)


func _apply(k: float) -> void:
	if _halo:
		_halo.modulate = Color(color.r * energy * k, color.g * energy * k, color.b * energy * k, 1.0)
	if _core:
		var c := color.lerp(Color(1.0, 0.92, 0.75), 0.5)
		_core.modulate = Color(c.r * core_energy * k, c.g * core_energy * k, c.b * core_energy * k, 1.0)

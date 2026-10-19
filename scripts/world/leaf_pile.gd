extends Node2D
class_name LeafPile
## 땅에 쌓인 잿빛 잎 더미. 새가 내려와 삼키려 한다. 삼키면 사라졌다가 한참 뒤 다시 쌓인다.
## 그림 (2026-10-19 이펙트 리뉴얼 F2): 기획자 이펙트 시트의 낱장 잎 두 가지(art/fx/leaf_b, leaf_c)를 잿빛 팔레트로 칠해 쌓는다
## (잎마다 자리·각도·크기는 씨앗으로 정해 매 프레임 같다). 먹히면 잎이 흩어진다(Fx "pile_burst").

@export var regrow_time := 25.0
var available := true
var _t := 0.0
var _alpha := 1.0
var _rng_seed := randi()
var _leaves: Array = []   # [텍스처, 변환, 색] — 처음 한 번 만든다
const LEAF_COUNT := 24


func _ready() -> void:
	material = Fx.shared_material("ash", false, 0.45)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng_seed
	var texs := [Fx.texture("leaf_c"), Fx.texture("leaf_b")]
	if texs[0] == null or texs[1] == null:
		return
	var by_tex := [[], []]
	for i in LEAF_COUNT:
		var x := rng.randf_range(-92.0, 92.0)
		var y := -rng.randf_range(2.0, 40.0) * (1.0 - absf(x) / 115.0) - 4.0
		var ti := 0 if rng.randf() < 0.65 else 1
		var sc := rng.randf_range(0.55, 0.85)
		var xf := Transform2D(rng.randf_range(-0.9, 0.9) + (PI if rng.randf() < 0.5 else 0.0), Vector2(sc, sc * rng.randf_range(0.8, 1.0)), 0.0, Vector2(x, y))
		var shade := rng.randf_range(0.8, 1.05)
		by_tex[ti].append([texs[ti], xf, Color(shade, shade, shade)])
	# 같은 그림끼리 이어 그려 묶어 그리기가 되게 (아래 줄부터 = 앞 잎이 위)
	_leaves = by_tex[0] + by_tex[1]


func _process(delta: float) -> void:
	_t += delta
	var a := move_toward(_alpha, 1.0 if available else 0.0, delta * 2.0)
	if a != _alpha or _leaves.is_empty():
		_alpha = a
		queue_redraw()


func consume() -> void:
	if not available:
		return
	available = false
	Fx.spawn("pile_burst", global_position)
	await get_tree().create_timer(regrow_time).timeout
	available = true


func _draw() -> void:
	if _alpha <= 0.01:
		return
	if not _leaves.is_empty():
		for lf in _leaves:
			var t: Texture2D = lf[0]
			draw_set_transform_matrix(lf[1])
			var c: Color = lf[2]
			draw_texture(t, -t.get_size() * 0.5, Color(c, _alpha))
		draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng_seed
	for i in 26:
		var x := rng.randf_range(-90, 90)
		var y := -rng.randf_range(0, 36) * (1.0 - absf(x) / 110.0)
		var r := rng.randf_range(10, 18)
		var c := Color(0.56, 0.58, 0.56).lerp(Color(0.42, 0.43, 0.44), rng.randf())
		c.a = _alpha
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - r, y), Vector2(x - r * 0.3, y - r * 0.5), Vector2(x + r, y), Vector2(x - r * 0.3, y + r * 0.3)]), c)

extends Node2D
class_name RootWall
## 뿌리 벽 (뿌리지기 2페이즈 돌진의 그림): 돌진하는 뿌리지기 앞에 실제로 솟아 함께 밀려오는 뿌리 벽.
## 판정은 보스의 Hitbox 가 한다 — 이 노드는 보스의 자식으로 붙어 보스를 따라 움직이는 그림 + 흙 입자.
## 그림 (2026-10-19 이펙트 리뉴얼 F2): 기획자 이펙트 시트의 앞으로 덮쳐 오는 뿌리 덩어리(art/fx/root_surge)를 붉게(가드 불가) 칠한 것.

var facing := -1
var life := 0.9
var _t := 0.0
var _dirt: CPUParticles2D
var _art: Sprite2D
const RISE := 0.14
const ART := "root_surge"
const ART_SCALE := Vector2(0.95, 1.3)
## 그림 왼쪽 끝 자리 (보스 발밑 기준, 앞 = +)
const ART_X := -30.0
const CRUMBLE := 0.3
const WALL_H := 310.0
## 뿌리 줄기: (앞쪽 x 오프셋, 밑동 반폭, 높이 비율, 휨)
const ROOTS := [[40.0, 22.0, 0.72, 10.0], [78.0, 26.0, 0.9, 18.0], [120.0, 30.0, 1.0, 26.0], [162.0, 28.0, 0.94, 22.0], [204.0, 24.0, 0.8, 14.0], [240.0, 18.0, 0.62, 8.0]]


func _ready() -> void:
	add_to_group("root_effect")
	_dirt = CPUParticles2D.new()
	_dirt.amount = 30
	_dirt.lifetime = 0.5
	_dirt.direction = Vector2(-facing, -1)
	_dirt.spread = 50.0
	_dirt.gravity = Vector2(0, 900)
	_dirt.initial_velocity_min = 150.0
	_dirt.initial_velocity_max = 380.0
	_dirt.scale_amount_min = 2.0
	_dirt.scale_amount_max = 7.0
	_dirt.color = Color(0.36, 0.28, 0.3, 0.85)
	_dirt.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dirt.emission_rect_extents = Vector2(110, 3)
	_dirt.position = Vector2(facing * 140.0, 0)
	add_child(_dirt)
	_art = Sprite2D.new()
	_art.texture = Fx.texture(ART)
	_art.material = Fx.shared_material("danger", false, 0.55)
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.centered = false
	_art.visible = false
	add_child(_art)


func _process(delta: float) -> void:
	_t += delta
	if _t > life + CRUMBLE:
		queue_free()
		return
	if _t > life:
		_dirt.emitting = false
	_update_art()
	queue_redraw()


## 그림: RISE 초에 땅에서 솟고, 끝나면 무너지며 옅어진다 (그리기 _draw 와 같은 곡선)
func _update_art() -> void:
	if _art == null or _art.texture == null:
		return
	var k := Motion.ease_out(clampf(_t / RISE, 0.0, 1.0), 2.0)
	var fade := 1.0
	if _t > life:
		var c := (_t - life) / CRUMBLE
		fade = 1.0 - c
		k *= 1.0 - Motion.ease_in(c, 1.5) * 0.6
	_art.visible = k > 0.02
	var ts := _art.texture.get_size()
	_art.scale = Vector2(ART_SCALE.x * float(facing), ART_SCALE.y * k)
	_art.position = Vector2(ART_X * float(facing), -ts.y * ART_SCALE.y * k + 12.0)
	_art.modulate = Color(1.1, 1.0, 1.0, clampf(fade, 0.0, 1.0))


func _draw() -> void:
	var k := Motion.ease_out(clampf(_t / RISE, 0.0, 1.0), 2.0)
	var fade := 1.0
	if _t > life:
		var c := (_t - life) / CRUMBLE
		fade = 1.0 - c
		k *= 1.0 - Motion.ease_in(c, 1.5) * 0.6
	var bark := Color(0.3, 0.2, 0.26, fade)
	var grain := Color(0.48, 0.34, 0.4, fade)
	var glow := Color(1.0, 0.3, 0.2, (0.5 + 0.3 * sin(_t * 28.0)) * fade)
	if WALL_H * k < 2.0:
		return
	if _art and _art.texture:
		return   # 그림(Sprite2D, 붉게 칠한 뿌리)이 그린다
	for r in ROOTS:
		var x: float = r[0] * facing
		var hw: float = r[1]
		var hh: float = WALL_H * r[2] * k
		var bend: float = r[3] * facing
		var pts := PackedVector2Array([Vector2(x - hw, 0), Vector2(x - hw * 0.7 + bend * 0.4, -hh * 0.5), Vector2(x + bend, -hh), Vector2(x + hw * 0.7 + bend * 0.4, -hh * 0.5), Vector2(x + hw, 0)])
		draw_colored_polygon(pts, bark)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), grain, 2.5, true)
		for m in 3:
			var yk := -hh * (0.22 + 0.24 * m)
			draw_line(Vector2(x - hw * 0.6 + bend * (0.22 + 0.24 * m), yk), Vector2(x + hw * 0.6 + bend * (0.22 + 0.24 * m), yk), Color(0.2, 0.13, 0.18, fade), 2.0)
		# 붉게 타는 금 (가드 불가)
		draw_line(Vector2(x - 4, -hh * 0.15), Vector2(x + bend * 0.5 + 3, -hh * 0.6), glow, 2.5)
	# 벽 앞의 붉은 기운
	draw_rect(Rect2(facing * 30.0 if facing > 0 else facing * 270.0, -WALL_H * k, 240.0, WALL_H * k), Color(1.0, 0.2, 0.1, 0.08 * fade))

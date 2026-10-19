extends Node2D
## 정화된 뒤 멈춰 선 무쇠 펌프와 그 위에 튼 싹 (EXPANSION.md 4장 "펌프가 멈춰 서고 그 위로 싹이 튼다").
## 보스 방에서 깃발 boss_pump_defeated 가 서 있을 때만 보인다 (IronPumpRoom 이 켠다). 원점은 발.
## 정화하는 순간에는 IronPumpRoom 이 sprout() 를 불러, 빛으로 흩어지는 펌프 자리에 멈춘 펌프가 식어 가며 싹이 자라난다 (회상 전).

const TEX := preload("res://art/bosses/boss_iron_pump_now.png")
const ART_SCALE := 0.5

var _t := 0.0
## 싹이 자란 정도 (0 → 1). sprout() 가 0 에서 키운다.
var grow := 1.0
var _sprite: Sprite2D
var _motes: CPUParticles2D


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = TEX
	_sprite.scale = Vector2(ART_SCALE, ART_SCALE)
	_sprite.position = Vector2(0, -234)
	_sprite.modulate = Color(0.55, 0.52, 0.5)   # 멈춘 기계: 식어서 잿빛
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_sprite.material = preload("res://shaders/ash_purify.tres")
	add_child(_sprite)
	_motes = CPUParticles2D.new()
	_motes.amount = 10
	_motes.lifetime = 3.0
	_motes.preprocess = 3.0
	_motes.position = Vector2(0, -480)
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_motes.emission_sphere_radius = 40.0
	_motes.direction = Vector2(0, -1)
	_motes.spread = 40.0
	_motes.gravity = Vector2(0, -12)
	_motes.initial_velocity_min = 8.0
	_motes.initial_velocity_max = 24.0
	_motes.scale_amount_min = 1.5
	_motes.scale_amount_max = 3.0
	_motes.color = Color(0.7, 1.0, 0.75, 0.7)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_motes.material = add
	add_child(_motes)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# 실린더 위에서 자라난 싹: 줄기와 잎 둘, 끝에 작은 빛
	var top := Vector2(0, -470)
	var sway := sin(_t * 1.1) * 0.06
	var g := clampf(grow, 0.0, 1.0)
	if g <= 0.01:
		return
	draw_circle(top + Vector2(0, -40), 70.0, Color(0.44, 0.81, 0.59, 0.1))
	draw_line(top, top + Vector2(sway * 60.0, -90.0 * g), Color(0.31, 0.68, 0.48), 7.0, true)
	var tip := top + Vector2(sway * 60.0, -90.0 * g)
	draw_colored_polygon(PackedVector2Array([tip + Vector2(0, 30), tip + Vector2(-46, -6), tip + Vector2(-10, -26)]), Color(0.44, 0.81, 0.59))
	draw_colored_polygon(PackedVector2Array([tip + Vector2(0, 16), tip + Vector2(44, -24), tip + Vector2(12, -34)]), Color(0.44, 0.81, 0.59))
	draw_circle(tip + Vector2(0, -8), 7.0, Color(1.0, 0.83, 0.42))
	# 식은 핵: 희미한 초록빛
	draw_circle(Vector2(24, -192), 40.0, Color(0.5, 0.9, 0.7, 0.12 + 0.05 * sin(_t * 1.6)))


## 정화하는 순간의 연출: 멈춘 펌프가 나타나 식어 가고(밝게 → 잿빛), 그 위로 싹이 자란다.
func sprout(duration := 1.6) -> void:
	visible = true
	grow = 0.0
	modulate = Color(1, 1, 1, 0)
	if _sprite:
		_sprite.modulate = Color(1.6, 1.6, 1.5)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, duration * 0.5)
	if _sprite:
		tw.tween_property(_sprite, "modulate", Color(0.55, 0.52, 0.5), duration).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "grow", 1.0, duration * 0.8).set_delay(duration * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

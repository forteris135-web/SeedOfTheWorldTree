extends Node2D
class_name LeafPile
## 땅에 쌓인 잿빛 잎 더미. 새가 내려와 삼키려 한다. 삼키면 사라졌다가 한참 뒤 다시 쌓인다.

@export var regrow_time := 25.0
var available := true
var _t := 0.0
var _alpha := 1.0
var _rng_seed := randi()


func _process(delta: float) -> void:
	_t += delta
	_alpha = move_toward(_alpha, 1.0 if available else 0.0, delta * 2.0)
	queue_redraw()


func consume() -> void:
	if not available:
		return
	available = false
	await get_tree().create_timer(regrow_time).timeout
	available = true


func _draw() -> void:
	if _alpha <= 0.01:
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

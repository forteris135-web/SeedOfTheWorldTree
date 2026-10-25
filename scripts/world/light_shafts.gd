extends Node2D
## 위에서 비쳐 드는 빛줄기. 천천히 숨 쉬듯 밝아졌다 어두워진다. 더하기 혼합으로 발광.

@export var count := 7
@export var shaft_color := Color(1.0, 0.86, 0.55, 0.07)
@export var seed := 11
## 정화된 지역에서는 빛줄기가 이만큼 더 밝다 (정화 연출 중에는 Purity.level 을 따라 서서히 — v1.1.0 기획자 요청 5)
const ENERGY_ALIVE := 1.35

var _time := 0.0
var _energy := 1.0
var _shafts: Array = []  # [x, width, drift, phase, speed]


func _ready() -> void:
	var room := BackdropUtil.room_bounds(self)
	var need := BackdropUtil.cover_size(self, room)
	position = BackdropUtil.center_of(self, room) - need / 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		_shafts.append([rng.randf_range(0, need.x), rng.randf_range(60, 190), rng.randf_range(-300, 300), rng.randf_range(0, TAU), rng.randf_range(0.15, 0.35), need.y])
	material = preload("res://shaders/ash_purify_add.tres")


func _process(delta: float) -> void:
	_time += delta
	_energy = lerpf(1.0, ENERGY_ALIVE, clampf(Purity.level, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	for s in _shafts:
		var pulse: float = 0.6 + 0.4 * sin(_time * s[4] * TAU + s[3])
		var c := Color(shaft_color.r, shaft_color.g, shaft_color.b, shaft_color.a * pulse * _energy)
		var x: float = s[0]
		var w: float = s[1]
		var drift: float = s[2]
		var h: float = s[5]
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, 0), Vector2(x + w, 0),
			Vector2(x + w * 2.4 + drift, h), Vector2(x + drift - w * 0.6, h)]), c)

extends Area2D
class_name Thorns
## 나무 가시. 닿으면 피해를 입고 마지막 안전한 자리로 돌아온다. 원점은 왼쪽 위, 가시는 위를 향한다.
## 모양(디테일): 옆선이 안으로 휜 날카로운 가시, 끝 1/3 은 뼈처럼 밝고 끝에 작은 빛점, 밑동은 얽힌 가지.
## 끝 색은 지역 팔레트(TerrainStyle.thorn_tip/thorn_glow)를 따른다. tip_color 를 방 파일에서 따로 정하면 그 색.

@export var size := Vector2(400, 60)
@export var damage := 15.0
@export var color := Color("1a1710")
const DEFAULT_TIP := Color(0.72, 0.66, 0.5)
@export var tip_color := DEFAULT_TIP
## 가시가 향하는 방향 (0 위, 1 아래, 2 왼쪽, 3 오른쪽)
@export_enum("위", "아래", "왼쪽", "오른쪽") var facing_dir := 0
## 지역 팔레트를 강제로 고른다 (비워 두면 조상 Room 의 region).
@export var style_region := ""

var _style: Dictionary = {}


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x - 8, size.y * 0.7)
	shape.shape = rect
	shape.position = Vector2(size.x / 2.0, size.y * 0.65)
	add_child(shape)
	body_entered.connect(_on_body_entered)
	material = preload("res://shaders/ash_purify.tres")
	_style = _pick_style()
	queue_redraw()


func _pick_style() -> Dictionary:
	var st := TerrainStyle.style_for(self, style_region)
	if tip_color != DEFAULT_TIP:
		st = st.duplicate()
		st["thorn_tip"] = tip_color
	return st


func _physics_process(_delta: float) -> void:
	# 안에 머무는 동안도 (무적이 끝나면) 다시 찔린다
	for b in get_overlapping_bodies():
		if b is Player:
			b.take_hazard(damage)


func _on_body_entered(body: Node) -> void:
	if body is Player:
		body.take_hazard(damage)


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	TerrainStyle.trace_node = self
	if _style.is_empty():
		_style = _pick_style()
	var st := _style
	var detailed := TerrainStyle.detail >= 1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 3.0 + global_position.y * 7.0)
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2(0, h * 0.55), Vector2(w, h * 0.45)), color)
	if detailed:
		# 밑동: 얽힌 어두운 가지 몇 줄 (선 두 토막씩)
		var tangle := color.lightened(0.16)
		for i in TerrainStyle.n_of(w, 55.0, "streak"):
			var x0 := rng.randf_range(0, w - 40.0)
			var y0 := rng.randf_range(h * 0.62, h * 0.94)
			var m := Vector2(x0 + rng.randf_range(10, 24), clampf(y0 + rng.randf_range(-6, 6), h * 0.58, h * 0.98))
			var q := Vector2(minf(x0 + rng.randf_range(28, 50), w), clampf(y0 + rng.randf_range(-4, 4), h * 0.58, h * 0.98))
			draw_line(Vector2(x0, y0), m, tangle, 1.4, true)
			draw_line(m, q, tangle, 1.4, true)
	var b := TerrainStyle.Batch.new()
	var x := 0.0
	while x < w - 10.0:
		var tw := rng.randf_range(10, 20) if detailed else rng.randf_range(14, 26)
		# 그림 끝이 맞는 영역(위쪽 0.3h)에서 너무 멀어지지 않게 옛 높이(최대 1.05h)를 지킨다
		var th := rng.randf_range(h * 0.7, h * 1.05) if detailed else rng.randf_range(h * 0.6, h * 1.05)
		var lean := rng.randf_range(-6, 6)
		var base_y := h * 0.6
		var tip := Vector2(x + tw / 2.0 + lean, base_y - th)
		TerrainStyle.draw_thorn(b, Vector2(x, base_y), Vector2(x + tw, base_y), tip, color, st, detailed)
		x += tw * rng.randf_range(0.75, 1.15) if detailed else tw * rng.randf_range(0.7, 1.1)
	b.flush(self)
	var dt := Time.get_ticks_usec() - t0
	Platform.draw_usec += dt
	Platform.body_usec += dt

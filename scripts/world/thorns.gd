extends Area2D
class_name Thorns
## 나무 가시. 닿으면 피해를 입고 마지막 안전한 자리로 돌아온다. 원점은 왼쪽 위, 가시는 위를 향한다.
## 모양(디테일): 옆선이 안으로 휜 날카로운 가시, 끝 1/3 은 뼈처럼 밝고 끝에 작은 빛점, 밑동은 얽힌 가지.
## 끝 색은 지역 팔레트(TerrainStyle.thorn_tip/thorn_glow)를 따른다. tip_color 를 방 파일에서 따로 정하면 그 색.
## 지역 그림 옷에 가시 조각(thorn)이 있으면 그림 조각으로 그린다 (뒤틀린 뿌리 가시를 폭을 따라 크기를 섞어 두 줄로 — TERRAIN.md).
## 방향(facing_dir): 그림·판정 모두 '위를 향한 틀'(길이 L × 높이 H, 밑동이 아래)로 만든 뒤 frame_of 로 돌려 상자에 맞춘다.
##   위·아래를 향하면 가시가 가로로(L = size.x, H = size.y), 왼쪽·오른쪽을 향하면 세로로(L = size.y, H = size.x) 늘어선다.
##   판정은 밑동 쪽 70% (hit_rect) — 위를 향한 가시는 옛날과 똑같다.

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
## 그림 조각 가시 (지역 그림 옷에 thorn 조각이 있으면). 있으면 옛 코드 그리기는 쓰지 않는다.
var _art: TerrainArt


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var hr := hit_rect(size, facing_dir)
	rect.size = hr.size
	shape.shape = rect
	shape.position = hr.get_center()
	add_child(shape)
	body_entered.connect(_on_body_entered)
	material = preload("res://shaders/ash_purify_thorn.tres")   # 가시 재질 = 앞 지형 재질 + 잿빛에서도 원래 색 조금 (depth 의 thorn_keep — TERRAIN.md 5장)
	var skin := TerrainSkin.for_node(self, style_region)
	if skin != null and skin.has_role("thorn"):
		_art = TerrainArt.new(skin, self)
		_art.name = "Art"
		add_child(_art)
		_art.build_thorns(self, size, facing_dir)
		return
	_style = _pick_style()
	queue_redraw()


## 가시가 늘어서는 길이와 높이 (위를 향한 틀의 크기): 옆을 향하면 가로세로가 바뀐다.
static func frame_size(sz: Vector2, facing: int) -> Vector2:
	return Vector2(sz.y, sz.x) if facing >= 2 else sz


## 위를 향한 틀(0,0 ~ L,H, 밑동 y=H) → 노드 좌표. 밑동이 위(1)·오른쪽 면(2)·왼쪽 면(3)에 붙게 돌린다.
static func frame_of(sz: Vector2, facing: int) -> Transform2D:
	match facing:
		1:
			return Transform2D(PI, sz)                   # 아래를 향함: 밑동이 윗면
		2:
			return Transform2D(-PI * 0.5, Vector2(0, sz.y))   # 왼쪽을 향함: 밑동이 오른쪽 면
		3:
			return Transform2D(PI * 0.5, Vector2(sz.x, 0))    # 오른쪽을 향함: 밑동이 왼쪽 면
	return Transform2D.IDENTITY


## 맞는 상자 (노드 좌표): 틀에서 양 끝 4px 씩 빼고, 밑동 쪽 70% (위를 향하면 옛날과 같은 (w−8)×0.7h).
static func hit_rect(sz: Vector2, facing: int) -> Rect2:
	var lh := frame_size(sz, facing)
	var local := Rect2(4.0, lh.y * 0.3, lh.x - 8.0, lh.y * 0.7)
	if facing == 0:
		return local
	var xf := frame_of(sz, facing)
	var a := xf * local.position
	var b := xf * local.end
	# 돌리기의 아주 작은 소수 오차는 0.01px 로 맞춘다
	var snap := Vector2(0.01, 0.01)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)).snapped(snap), (b - a).abs().snapped(snap))


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
	if _art:
		return
	var t0 := Time.get_ticks_usec()
	TerrainStyle.trace_node = self
	if _style.is_empty():
		_style = _pick_style()
	var st := _style
	var detailed := TerrainStyle.detail >= 1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 3.0 + global_position.y * 7.0)
	# 위를 향한 틀(L×H)로 그리고 방향대로 돌린다 (그림 조각 가시·판정과 같은 틀)
	var lh := frame_size(size, facing_dir)
	var w := lh.x
	var h := lh.y
	if facing_dir != 0:
		draw_set_transform_matrix(frame_of(size, facing_dir))
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
	if facing_dir != 0:
		draw_set_transform_matrix(Transform2D.IDENTITY)
	var dt := Time.get_ticks_usec() - t0
	Platform.draw_usec += dt
	Platform.body_usec += dt

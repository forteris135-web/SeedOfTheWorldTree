extends Area2D
class_name SapPool
## 수액 웅덩이 (확장판 공용). 원점은 왼쪽 위, size 만큼의 수면.
## 수액 위 걷기(능력 "sap_walk")가 없으면: 안에서 느려지고 조금씩 체력이 깎인다 (즉사 아님). 구르기도 짧아진다(roll_slow).
## 능력이 있으면: 수면 위를 미끄러지듯 빠르게 지나고(slow_factor 1.35, 체력 안 깎임) 구르기 거리가 길어진다(roll_glide).
##   (EXPANSION.md 2장 "수액 위에서 구르기 거리가 길어진다" — player.roll_factor 를 이 웅덩이가 매 프레임 정한다)
## 그림 (코드로 그린 임시 스킨, 수액의 호수 묶음이 다듬음):
##  - 깊이 그라데이션(수면 밝음 → 바닥 어두움) + 일렁이는 수면선 두 겹 + 흐르는 빛 띠 + 떠오르는 방울
##  - region 을 주면 그 지역이 정화된 뒤(Purity) '살아난 수액'으로 바뀐다: 더 맑고 밝은 청록, 수면이 FILL_RISE 만큼 차오른 듯 그린다
##    (수액의 여왕을 정화하면 호수에 수액이 차오르는 연출 — 그림만 바뀌고 판정은 그대로)
##    방이 뜰 때의 상태로 시작하고, 그 뒤로는 Purity.region_changed 신호(색이 번져 돌아오는 연출·초기화)가 올 때만 바뀐다
##    → 회상에서 돌아와 잠깐 잿빛으로 돌렸다가 번지게 하는 BossRoom 연출과 맞물려 '살아남 → 잿빛 → 차오름'으로 깜빡이지 않는다.
##  - 소녀가 안에 있으면 발 자리에 잔물결 고리
## 세기 조절: 아래 상수들.

@export var size := Vector2(600, 120):
	set(v):
		size = v
		_rebuild()
		queue_redraw()
@export var dps := 5.0
@export var slow := 0.5
@export var glide := 1.35
## 구르기 속도 배수: 능력 없을 때 / 있을 때
@export var roll_slow := 0.6
@export var roll_glide := 1.4
@export var color := Color(0.25, 0.55, 0.75, 0.55)
## 이 지역이 정화되면 살아난 수액으로 보인다 (비우면 늘 잿빛 수액)
@export var region := ""

## 살아난 수액의 색과 차오르는 높이(px, 그림만)
const ALIVE_COLOR := Color(0.3, 0.75, 0.85, 0.7)
const FILL_RISE := 22.0
## 수면선 굵기·일렁임 간격(px)
const SURFACE_WIDTH := 3.0
const SURFACE_STEP := 16.0
## 빛 띠(흐르는 하이라이트) 개수와 방울 개수
const STREAK_COUNT := 5
const BUBBLE_COUNT := 14

var _shape: CollisionShape2D
var _t := 0.0
var _tick := 0.0
var _alive := 0.0       # 0 잿빛 → 1 살아남 (감쇠 보간)
var _alive_target := 0.0
var _players_in: Array = []
var _seed := 0
var _rng := RandomNumberGenerator.new()   # 그릴 때마다 같은 씨앗으로 되감아 쓴다 (매 프레임 새로 만들지 않게)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	_rebuild()
	material = preload("res://shaders/ash_purify_add.tres")
	_seed = int(global_position.x * 3.0 + global_position.y * 7.0 + size.x)
	_alive_target = 1.0 if _is_alive() else 0.0
	_alive = _alive_target
	Purity.region_changed.connect(_on_region_changed)
	# 방(BossRoom)의 _ready 가 이 뒤에 지역 상태를 바꿀 수 있다 (회상에서 막 돌아와 잠깐 잿빛으로 돌림) → 한 번 더 맞춘다
	_sync_start.call_deferred()


func _sync_start() -> void:
	_alive_target = 1.0 if _is_alive() else 0.0
	_alive = _alive_target


func _on_region_changed(r: String, purified: bool) -> void:
	if region != "" and r == region:
		_alive_target = 1.0 if purified else 0.0
	queue_redraw()


func _rebuild() -> void:
	if _shape == null:
		_shape = CollisionShape2D.new()
		add_child(_shape)
	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x, size.y * 0.8)
	_shape.shape = rect
	_shape.position = Vector2(size.x / 2.0, size.y * 0.6)


func can_walk() -> bool:
	return Progress.has_ability("sap_walk")


func _is_alive() -> bool:
	return region != "" and Purity.is_purified(region)


## 수면의 세계 y (여왕이 물결을 띄우는 기준)
func surface_y() -> float:
	return global_position.y


func _process(delta: float) -> void:
	_t += delta
	_alive = lerpf(_alive, _alive_target, 1.0 - exp(-1.2 * delta))
	queue_redraw()


func _physics_process(delta: float) -> void:
	_tick -= delta
	_players_in.clear()
	for b in get_overlapping_bodies():
		if b is Player:
			_players_in.append(b)
			if can_walk():
				b.slow_factor = glide
				b.roll_factor = roll_glide
			else:
				b.slow_factor = slow
				b.roll_factor = roll_slow
				if _tick <= 0.0:
					b.take_damage_over_time(dps * 0.5)
	if _tick <= 0.0:
		_tick = 0.5


func _surface_y(x: float, rise: float) -> float:
	return -rise + 3.0 * sin(x * 0.03 + _t * 2.2) + 2.0 * sin(x * 0.011 - _t * 1.3)


func _draw() -> void:
	var walk := can_walk()
	var base := color.lerp(ALIVE_COLOR, _alive)
	if walk:
		base = Color(base.r + 0.08, base.g + 0.12, base.b + 0.08, minf(base.a + 0.15, 0.85))
	var rise := FILL_RISE * _alive
	# 깊이 그라데이션: 수면 띠는 밝고 아래로 갈수록 어둡고 진하다 (가로 띠 6줄)
	var rows := 6
	for i in rows:
		var t0 := float(i) / rows
		var t1 := float(i + 1) / rows
		var c := base.lerp(Color(base.r * 0.35, base.g * 0.4, base.b * 0.5, base.a * 1.15), t0)
		var y0 := -rise + size.y * t0 + (6.0 if i > 0 else 0.0)
		draw_rect(Rect2(Vector2(0, y0), Vector2(size.x, size.y * (t1 - t0) + (0.0 if i == rows - 1 else 7.0))), Color(c, c.a * 0.9))
	# 흐르는 빛 띠 (수면 바로 아래를 천천히 지나간다)
	var rng := _rng
	rng.seed = _seed
	for i in STREAK_COUNT:
		var speed := rng.randf_range(18.0, 40.0)
		var len := rng.randf_range(80.0, 180.0)
		var phase := rng.randf() * size.x
		var x := fmod(phase + _t * speed, size.x + len) - len
		var y := -rise + 10.0 + rng.randf_range(4.0, 18.0)
		var a := (0.1 + 0.12 * _alive) * (0.6 + 0.4 * sin(_t * 1.1 + i))
		draw_line(Vector2(maxf(x, 0.0), y), Vector2(minf(x + len, size.x), y), Color(0.8, 1.0, 1.0, a), 2.0, true)
	# 떠오르는 방울
	for i in BUBBLE_COUNT:
		var bx := rng.randf() * size.x
		var period := rng.randf_range(2.5, 5.0)
		var k := fmod(_t / period + rng.randf(), 1.0)
		var by := -rise + size.y - k * (size.y - 8.0)
		var r := 1.5 + rng.randf() * 2.5
		draw_circle(Vector2(bx + sin(k * TAU + i) * 4.0, by), r, Color(0.85, 1.0, 1.0, 0.25 * (1.0 - k) + 0.1 * _alive))
	# 일렁이는 수면선 (앞 한 줄 밝게, 뒤 한 줄 흐리게 — 두 겹이면 물결이 두꺼워 보인다)
	var pts := PackedVector2Array()
	var pts2 := PackedVector2Array()
	var x2 := 0.0
	while x2 <= size.x:
		pts.append(Vector2(x2, _surface_y(x2, rise)))
		pts2.append(Vector2(x2, _surface_y(x2 + 40.0, rise) + 5.0))
		x2 += SURFACE_STEP
	var line_a := (0.85 if walk else 0.6) + 0.15 * _alive
	draw_polyline(pts2, Color(0.6, 0.9, 1.0, line_a * 0.35), SURFACE_WIDTH * 1.6, true)
	draw_polyline(pts, Color(0.75, 0.95, 1.0, line_a), SURFACE_WIDTH, true)
	# 소녀가 빠져 있으면 발 자리의 잔물결 고리
	for p in _players_in:
		if not is_instance_valid(p):
			continue
		var lp: Vector2 = to_local(p.global_position + Vector2(0, 60.0))
		var ring := fmod(_t * 1.6, 1.0)
		var ring2 := fmod(ring + 0.5, 1.0)
		draw_arc(Vector2(lp.x, -rise + 4.0), 18.0 + ring * 36.0, 0.0, TAU, 24, Color(0.8, 1.0, 1.0, 0.35 * (1.0 - ring)), 2.0, true)
		draw_arc(Vector2(lp.x, -rise + 4.0), 10.0 + ring2 * 36.0, 0.0, TAU, 24, Color(0.8, 1.0, 1.0, 0.25 * (1.0 - ring2)), 2.0, true)

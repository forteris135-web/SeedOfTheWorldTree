extends Area2D
class_name Projectile
## 날아가는 공격 (깃털 화살, 잿빛 잎, 바람, 구슬). 맞는 영역(Hurtbox)에 닿으면 receive_hit 를 부른다.
## 저스트 가드로 되받아칠 수 있는 것은 방향이 뒤집혀 쏜 쪽에게 돌아간다.
##
## 가시성 (2026-10-19 기획자 "탄막의 가시성을 올린다"):
## - 몸통 + 밝은 테두리(outline_color, 2~3px) + 심(core_color: 깃털의 붉은 줄, 잎의 잎맥)
## - 더하기 혼합(additive) 발광 원 (자식 Sprite2D, glow 세기) — 어두운 배경에서도 또렷하다
## - 꼬리 잔상 (trail_count 개: 지나온 자리에 옅은 몸 윤곽을 남긴다. 뒤로 갈수록 흐리고 작다.
##   잔상 전부를 삼각형 배열 하나로 그려 그리기 호출이 1번이다 — 아이폰에서 탄막이 많아도 가볍게)
## - draw_scale 은 **그림만** 키운다. 판정(원 반지름 = size.y*0.6, 최소 10)은 size 기준 그대로라
##   그림을 키워도 억울한 피격이 늘지 않는다 (보스 탄막은 1.8배).
## 모든 그림은 size 에 비례해 그려지므로, 다른 묶음이 size 를 키우면 그림도 함께 커진다.
## 자기 그림(_draw)을 따로 그리는 하위 클래스(예: 확장판 SapProjectile)에는 바탕의 발광·꼬리를 붙이지 않는다
## (_uses_base_look). 모양은 크기·종류가 바뀔 때만 다시 만들어 매 프레임 배열을 새로 만들지 않는다 (_ensure_geo).

enum Kind { FEATHER, LEAF, GUST, ORB }

signal reflected(projectile: Projectile)

@export var kind: Kind = Kind.FEATHER
@export var speed := 900.0
@export var damage := 12.0
@export var poise := 10.0
@export var lifetime := 4.0
## 저스트 가드로 되받아칠 수 있는가 (깃털만).
@export var reflectable := false
@export var guardable := true
## 중력 (잎은 살짝 떨어진다).
@export var fall_gravity := 0.0
## 추적 세기 (0 = 직진). 소녀 쪽으로 천천히 휜다.
@export var homing := 0.0
## 그림·판정의 기준 크기 (가로, 세로). 판정 원 반지름 = size.y*0.6 (최소 10).
@export var size := Vector2(70, 14)
@export var color := Color(0.75, 0.78, 0.8)

@export_group("가시성")
## 그림 배율. 판정은 size 그대로. (보스 탄막 1.8)
@export var draw_scale := 1.0
## 테두리 색. 알파 0 이면 color 를 밝힌 색을 쓴다.
@export var outline_color := Color(0, 0, 0, 0)
## 심 색 (깃털 가운데 줄·붉은 점, 잎맥, 구슬 속). 알파 0 이면 color 를 어둡힌 색.
@export var core_color := Color(0, 0, 0, 0)
## 발광 세기 (0 = 발광 없음).
@export var glow := 1.0
## 꼬리 잔상 개수 (0~6).
@export var trail_count := 4
## 생길 때 이 시간(초) 동안 서서히 나타난다 (0 = 바로). 화면 안에서 툭 생겨나 보이지 않게.
@export var fade_in := 0.0

## 잔상 사이 거리 = clamp(speed * TRAIL_STEP_TIME, TRAIL_STEP_MIN, TRAIL_STEP_MAX) — 빠른 깃털은 긴 줄, 느린 잎은 짧은 떨림
const TRAIL_STEP_TIME := 0.03
const TRAIL_STEP_MIN := 6.0
const TRAIL_STEP_MAX := 60.0
const TRAIL_ALPHA := 0.42
const GLOW_TEX_HALF := 32.0
## 잎 그림의 세로 = 가로 × 이 값 (예전 마름모 잎과 같은 비율)
const LEAF_HEIGHT_RATIO := 0.55
## 잎몸이 시작하는 자리 (뒤끝 -s 에서 잎자루가 이어진다)
const LEAF_BACK := 0.8
## 바람 호의 반각 (라디안)과 테두리 덧굵기
const GUST_ANGLE := 1.15
const GUST_OUTLINE := 2.0
const BASE_SCRIPT_PATH := "res://scripts/combat/projectile.gd"

static var _glow_tex: GradientTexture2D
static var _glow_mat: CanvasItemMaterial

var direction := Vector2.RIGHT
var source: Node2D
## true 면 소녀 쪽 공격 (적을 맞춘다)
var from_player := false
var _time := 0.0
var _wobble := randf() * TAU
var _dead := false
var _trail: Array[Transform2D] = []   # 최근 것이 앞
var _trail_last := Vector2(INF, INF)
var _glow: Sprite2D

## 그림 모양 캐시 (_ensure_geo 가 크기·종류가 바뀔 때만 다시 만든다)
var _geo_key := Vector4(-1, -1, -1, -1)
var _body_pts := PackedVector2Array()      # 몸 윤곽
var _body_closed := PackedVector2Array()   # 테두리용 (첫 점을 끝에 한 번 더)
var _body_rect := Rect2()
var _detail := PackedVector2Array()        # 잔 선 (두 점씩: 깃가지·잎맥)
var _sil_pts := PackedVector2Array()       # 잔상 윤곽 (바람은 호 세 겹의 띠)
var _sil_tris := PackedInt32Array()        # 잔상 삼각형 (한 번만 나눠 둔다)
var _gust_k := 1.0                         # 소녀의 바람: 판정 사각형 안에 들게 줄이는 비율
var _tr_pts := PackedVector2Array()
var _tr_cols := PackedColorArray()
var _tr_idx := PackedInt32Array()


func _ready() -> void:
	add_to_group("projectile")
	collision_layer = 0
	_update_mask()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = hit_radius()
	shape.shape = circle
	add_child(shape)
	monitoring = true
	monitorable = false
	rotation = direction.angle()
	if not _uses_base_look():
		glow = 0.0
		trail_count = 0
	if fade_in > 0.0:
		modulate.a = 0.0
	_make_glow()
	queue_redraw()


## 바탕 그림 규칙(테두리·발광·꼬리)을 쓰는가. 자기 _draw 를 그리는 하위 클래스는 false —
## 바탕 규칙을 쓰고 싶은 하위 클래스는 이 함수를 덮어써 true 를 돌려준다.
func _uses_base_look() -> bool:
	var sc: Script = get_script()
	return sc == null or sc.resource_path == BASE_SCRIPT_PATH


## 판정 원 반지름 (size 기준; draw_scale 과 무관).
func hit_radius() -> float:
	return maxf(size.y * 0.6, 10.0)


## 몸통 그림의 범위 (자기 좌표; 테두리·발광·꼬리 제외). probe 가 예전 그림 크기와 비교한다.
func body_bounds() -> Rect2:
	_ensure_geo()
	if kind == Kind.GUST:
		return _gust_bounds(0.0)
	return _body_rect


## 테두리까지 넣은 그림 범위 (자기 좌표; 발광·꼬리 제외). 바람은 실제 호(선 굵기 포함)를 계산한다.
func draw_bounds() -> Rect2:
	_ensure_geo()
	if kind == Kind.GUST:
		return _gust_bounds(GUST_OUTLINE)
	return _body_rect.grow(_outline_width() * 0.5)


## 그림이 차지하는 반 크기 (가운데에서 가장 먼 곳까지; 테두리 포함, 발광·꼬리 제외).
func draw_half_extent() -> Vector2:
	var b := draw_bounds()
	return Vector2(maxf(absf(b.position.x), absf(b.end.x)), maxf(absf(b.position.y), absf(b.end.y)))


func _outline_width() -> float:
	return 2.0 + 0.6 * draw_scale


## 몸 그림의 세로 (draw_scale 포함). 잎은 예전 그림처럼 가로의 0.55 를 쓴다 —
## 정사각형 size 로 쓰는 다른 잎 모양 투사체(기사 등불, 뿌리지기 구슬 등)도 예전처럼 납작한 잎으로 보인다.
func _body_height() -> float:
	if kind == Kind.LEAF:
		return size.x * LEAF_HEIGHT_RATIO * draw_scale
	return size.y * draw_scale


func _outline() -> Color:
	if outline_color.a > 0.0:
		return outline_color
	return Color(color.lightened(0.6), 0.9)


func _core() -> Color:
	if core_color.a > 0.0:
		return core_color
	return color.darkened(0.35)


func _update_mask() -> void:
	# 소녀 공격이면 적 맞는 영역(16), 적 공격이면 소녀 맞는 영역(8). 지형(1)에는 항상 막힌다.
	collision_mask = 1 | (16 if from_player else 8)


func launch(dir: Vector2, src: Node2D, player_owned := false) -> void:
	direction = dir.normalized()
	source = src
	from_player = player_owned
	_update_mask()
	rotation = direction.angle()
	if from_player:
		# 소녀의 바람·빛은 그림 크기만큼 맞는다 (2026-10-18 영혼 기술 강화: 커진 크기가 판정에도 그대로)
		for c in get_children():
			if c is CollisionShape2D:
				var rect := RectangleShape2D.new()
				rect.size = size * 0.9
				c.shape = rect


func _physics_process(delta: float) -> void:
	if _dead:
		return
	_time += delta
	if fade_in > 0.0 and _time <= fade_in + delta:
		modulate.a = clampf(_time / fade_in, 0.0, 1.0)
	if fall_gravity > 0.0:
		direction = (direction * speed + Vector2(0, fall_gravity * delta)).normalized()
	if homing > 0.0 and not from_player and _time < lifetime * 0.7:
		var target := get_tree().get_first_node_in_group("player") as Node2D
		if target:
			var want := (target.global_position + Vector2(0, -50) - global_position).normalized()
			direction = direction.slerp(want, clampf(homing * delta, 0.0, 1.0)).normalized()
	var wobble := Vector2.ZERO
	if kind == Kind.LEAF:
		wobble = Vector2(sin(_time * 3.0 + _wobble) * 60.0, 0) * delta
	var from := global_position
	var to := from + direction * speed * delta + wobble
	# 지형에 막힌다 (빠른 투사체가 얇은 발판을 건너뛰지 않게 선으로 검사)
	var ray := PhysicsRayQueryParameters2D.create(from, to, 1)
	var hit_terrain := get_world_2d().direct_space_state.intersect_ray(ray)
	if not hit_terrain.is_empty():
		global_position = hit_terrain["position"]
		# 소녀의 바람·빛이 '때리면 부서지는 벽' 같은 지형에 닿으면 한 대로 친다
		var col = hit_terrain.get("collider")
		if from_player and col and col.has_method("receive_hit"):
			var h := HitData.make(damage, poise, source if source else self, Vector2(200, -60))
			h.from_player = true
			col.receive_hit(h, null)
		_vanish()
		return
	global_position = to
	rotation = direction.angle() + (sin(_time * 4.0 + _wobble) * 0.6 if kind == Kind.LEAF else 0.0)
	_record_trail()
	_update_glow()
	if _time > lifetime:
		_vanish()
		return
	for area in get_overlapping_areas():
		if area is Hurtbox:
			_hit(area)
			return
	queue_redraw()


## 지나온 자리를 적는다 (일정 거리마다). 제자리에 서 있는 것(불기둥)은 꼬리가 없다.
func _record_trail() -> void:
	if trail_count <= 0:
		return
	if _trail_last.x == INF:
		_trail_last = global_position   # 첫 자리는 기준점만 잡는다
		return
	var step := clampf(speed * TRAIL_STEP_TIME, TRAIL_STEP_MIN, TRAIL_STEP_MAX)
	if global_position.distance_squared_to(_trail_last) >= step * step:
		_trail_last = global_position
		_trail.push_front(global_transform)
		if _trail.size() > trail_count:
			_trail.resize(trail_count)


func trail_size() -> int:
	return _trail.size()


func _hit(area: Hurtbox) -> void:
	var hit := HitData.make(damage, poise, source if source else self, Vector2(260, -100))
	hit.guardable = guardable
	hit.from_player = from_player
	hit.hitstop = 0.04
	var result: String = area.receive(hit)
	if result == "just_guard" and reflectable and not from_player:
		_reflect(area.owner_node)
		return
	if result == "ignored":
		return
	_vanish()


func _reflect(by: Node) -> void:
	from_player = true
	_update_mask()
	speed *= 1.5
	damage *= 1.6
	poise = 28.0
	_time = 0.0
	lifetime = 3.0
	color = Color(1.0, 0.85, 0.5)
	outline_color = Color(1.0, 1.0, 0.9, 1.0)
	core_color = Color(1.0, 0.95, 0.7, 1.0)
	_trail.clear()
	var target := source
	if is_instance_valid(target):
		direction = (target.global_position - global_position).normalized()
	else:
		direction = -direction
	rotation = direction.angle()
	reflected.emit(self)


func _vanish() -> void:
	_dead = true
	set_deferred("monitoring", false)
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_callback(queue_free)


# ---------- 발광 ----------

func _make_glow() -> void:
	if glow <= 0.0:
		return
	if _glow_tex == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = grad
		_glow_tex.width = int(GLOW_TEX_HALF * 2)
		_glow_tex.height = int(GLOW_TEX_HALF * 2)
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1, 0.5)
		_glow_mat = CanvasItemMaterial.new()
		_glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow = Sprite2D.new()
	_glow.texture = _glow_tex
	_glow.material = _glow_mat
	_glow.show_behind_parent = true
	var r := glow_radii()
	_glow.scale = Vector2(r.x / GLOW_TEX_HALF, r.y / GLOW_TEX_HALF)
	_glow.position = glow_center()
	add_child(_glow)
	_update_glow()


## 발광 타원의 반지름 (가로, 세로).
func glow_radii() -> Vector2:
	var w := size.x * draw_scale
	var h := size.y * draw_scale
	match kind:
		Kind.FEATHER:
			return Vector2(w * 0.5, maxf(h * 1.2, 14.0))
		Kind.LEAF:
			return Vector2(w * 0.45, w * 0.45)
		Kind.GUST:
			# 판정 사각형 안
			return Vector2(size.x * 0.35, size.y * 0.42)
		Kind.ORB:
			return Vector2(h * 0.9, h * 0.9)
	return Vector2(w * 0.5, h)


func glow_center() -> Vector2:
	match kind:
		Kind.GUST:
			return Vector2(size.x * 0.05, 0)
		Kind.LEAF:
			return Vector2(size.x * draw_scale * 0.06, 0)
	return Vector2.ZERO


func _glow_color() -> Color:
	var c := color.lerp(Color(1, 1, 1), 0.35)
	return Color(c.r * 1.3, c.g * 1.3, c.b * 1.3, 1.0)


func _update_glow() -> void:
	if _glow == null:
		return
	var pulse := 0.85 + 0.15 * sin(_time * 18.0 + _wobble)
	var c := _glow_color()
	c.a = clampf(0.6 * glow * pulse, 0.0, 1.0)
	_glow.modulate = c


# ---------- 그림 ----------

## 모양 캐시를 만든다 (종류·크기·배율이 바뀔 때만). 몸 윤곽·테두리·잔 선·잔상 삼각형을 한 번에 준비한다.
func _ensure_geo() -> void:
	var key := Vector4(float(kind) + (10.0 if from_player else 0.0), size.x, size.y, draw_scale)
	if key == _geo_key:
		return
	_geo_key = key
	_body_pts = PackedVector2Array()
	_detail = PackedVector2Array()
	_sil_pts = PackedVector2Array()
	_sil_tris = PackedInt32Array()
	var w := size.x * draw_scale
	var h := _body_height()
	match kind:
		Kind.FEATHER:
			# 앞이 뾰족하고 뒤가 둥근 깃
			var n := 12
			for i in n + 1:
				var t := float(i) / n
				_body_pts.append(Vector2(lerpf(-w / 2, w / 2, t), -pow(sin(t * PI), 0.8) * h / 2))
			for i in range(n, -1, -1):
				var t := float(i) / n
				_body_pts.append(Vector2(lerpf(-w / 2, w / 2, t), pow(sin(t * PI), 1.2) * h / 2 * 0.78))
			# 깃가지: 심에서 뒤로 비스듬히
			for i in 4:
				var x := lerpf(-w * 0.3, w * 0.3, float(i) / 3)
				var yy := pow(sin((x / w + 0.5) * PI), 0.8) * h / 2
				_detail.append_array([Vector2(x, 0), Vector2(x - h * 0.5, -yy * 0.85), Vector2(x, 0), Vector2(x - h * 0.5, yy * 0.65)])
		Kind.LEAF:
			# 잎몸 (-LEAF_BACK·s ~ s) — 뒤끝 -s 까지는 잎자루
			var s := w / 2
			var n := 12
			for i in n + 1:
				var t := float(i) / n
				_body_pts.append(Vector2(lerpf(-s * LEAF_BACK, s, t), -pow(sin(t * PI), 0.9) * h / 2))
			for i in range(n, -1, -1):
				var t := float(i) / n
				_body_pts.append(Vector2(lerpf(-s * LEAF_BACK, s, t), pow(sin(t * PI), 0.9) * h / 2 * 0.92))
			# 곁맥 3쌍
			for i in 3:
				var x := lerpf(-s * 0.35, s * 0.45, float(i) / 2)
				var t := (x + s * LEAF_BACK) / (s * (1.0 + LEAF_BACK))
				var yy := pow(sin(t * PI), 0.9) * h / 2
				_detail.append_array([Vector2(x, 0), Vector2(x + s * 0.28, -yy * 0.8), Vector2(x, 0), Vector2(x + s * 0.28, yy * 0.72)])
		Kind.ORB:
			var r := h * 0.5
			for i in 24:
				_body_pts.append(Vector2.from_angle(i * TAU / 24.0) * r)
		Kind.GUST:
			# 소녀의 바람은 판정 사각형(0.9×size) 안에 들게 호 반지름을 살짝 줄인다 (테두리 굵기까지 넣어서)
			_gust_k = _fit_gust() if from_player else 1.0
			# 잔상 윤곽: 호 세 겹을 각각 띠 다각형으로 만들어 삼각형을 이어 붙인다
			for i in 3:
				var seg := PackedVector2Array()
				var c := _gust_center(i)
				var r := _gust_radius(i)
				var hw := _gust_width(i) * 0.5
				for j in 9:
					seg.append(c + Vector2.from_angle(lerpf(-GUST_ANGLE, GUST_ANGLE, j / 8.0)) * (r + hw))
				for j in range(8, -1, -1):
					seg.append(c + Vector2.from_angle(lerpf(-GUST_ANGLE, GUST_ANGLE, j / 8.0)) * maxf(r - hw, 0.5))
				var tris := Geometry2D.triangulate_polygon(seg)
				var base := _sil_pts.size()
				_sil_pts.append_array(seg)
				for t in tris:
					_sil_tris.append(base + t)
	_body_closed = _body_pts.duplicate()
	if not _body_pts.is_empty():
		_body_closed.append(_body_pts[0])
		var lo := _body_pts[0]
		var hi := _body_pts[0]
		for pt in _body_pts:
			lo = lo.min(pt)
			hi = hi.max(pt)
		_body_rect = Rect2(lo, hi - lo)
		_sil_pts = _body_pts
		_sil_tris = Geometry2D.triangulate_polygon(_body_pts)


func _draw() -> void:
	_ensure_geo()
	var ol := _outline()
	var co := _core()
	_draw_trail(ol)
	match kind:
		Kind.FEATHER:
			_draw_feather(ol, co)
		Kind.LEAF:
			_draw_leaf(ol, co)
		Kind.GUST:
			_draw_gust(ol)
		Kind.ORB:
			_draw_orb(ol, co)


## 꼬리 잔상: 지나온 자리마다 몸 윤곽을 옅게(테두리·잔 선 없이, 뒤로 갈수록 흐리고 작게).
## 잔상 전부를 삼각형 배열 하나로 보낸다 (그리기 호출 1번, 매 프레임 삼각분할 없음).
func _draw_trail(ol: Color) -> void:
	if _build_trail(ol):
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _tr_idx, _tr_pts, _tr_cols)


## 잔상 삼각형 배열(_tr_pts/_tr_cols/_tr_idx)을 채운다. 그릴 잔상이 없으면 false.
func _build_trail(ol: Color) -> bool:
	_ensure_geo()
	var n := _trail.size()
	if n == 0 or _sil_tris.is_empty():
		return false
	var m := _sil_pts.size()
	var tn := _sil_tris.size()
	_tr_pts.resize(n * m)
	_tr_cols.resize(n * m)
	_tr_idx.resize(n * tn)
	var inv := global_transform.affine_inverse()
	var tint := color.lerp(Color(ol.r, ol.g, ol.b), 0.3)
	var vi := 0
	var ii := 0
	for i in range(n - 1, -1, -1):   # 오래된 것부터 (최근 것이 위로)
		var k := 1.0 - float(i) / float(n)        # 0(가장 오래됨)…1(가장 최근)
		var c := Color(tint, color.a * TRAIL_ALPHA * (0.25 + 0.75 * k))
		var sc := 0.72 + 0.28 * k
		var xf := inv * _trail[i] * Transform2D(0.0, Vector2(sc, sc), 0.0, Vector2.ZERO)
		var base := vi
		for j in m:
			_tr_pts[vi] = xf * _sil_pts[j]
			_tr_cols[vi] = c
			vi += 1
		for j in tn:
			_tr_idx[ii] = base + _sil_tris[j]
			ii += 1
	return true


## 깃털: 은빛 몸 + 깃가지 + 붉은 심(가운데 줄과 점) + 흰 테두리 + 끝의 빛점.
func _draw_feather(ol: Color, co: Color) -> void:
	var w := size.x * draw_scale
	var h := _body_height()
	var lw := _outline_width()
	draw_colored_polygon(_body_pts, color)
	draw_multiline(_detail, Color(co.lerp(color, 0.55), color.a * 0.8), 1.0, true)
	draw_line(Vector2(-w * 0.46, 0), Vector2(w * 0.42, 0), co, maxf(lw * 0.8, 1.5), true)
	draw_circle(Vector2(-w * 0.06, 0), h * 0.24, Color(co, co.a * 0.95))
	draw_polyline(_body_closed, ol, lw, true)
	draw_circle(Vector2(w * 0.5 - h * 0.18, 0), maxf(h * 0.1, 1.5), ol)


## 잿빛 잎: 잎몸 + 잎자루 + 잎맥, 흰 테두리.
func _draw_leaf(ol: Color, co: Color) -> void:
	var s := size.x * draw_scale / 2
	var h := _body_height()
	var lw := _outline_width()
	draw_colored_polygon(_body_pts, color)
	draw_line(Vector2(-s * LEAF_BACK, 0), Vector2(-s, h * 0.1), co, maxf(lw * 0.8, 1.5), true)
	draw_line(Vector2(-s * (LEAF_BACK - 0.08), 0), Vector2(s * 0.88, 0), co, maxf(lw * 0.6, 1.2), true)
	draw_multiline(_detail, Color(co, co.a * 0.7), 1.0, true)
	draw_polyline(_body_closed, ol, lw, true)


## 바람: 겹친 초승달 호 세 겹, 앞쪽이 가장 작고 뒤로 갈수록 크다. 크기(size)를 따라 커진다.
## 테두리는 같은 호를 더 굵은 밝은 선으로 먼저 깔아 그린다. 소녀의 바람은 테두리까지 판정 사각형(0.9×size) 안.
func _draw_gust(ol: Color) -> void:
	for i in 3:
		draw_arc(_gust_center(i), _gust_radius(i), -GUST_ANGLE, GUST_ANGLE, 16, Color(ol, ol.a * (0.55 - i * 0.12)), _gust_width(i) + GUST_OUTLINE, true)
	for i in 3:
		draw_arc(_gust_center(i), _gust_radius(i), -GUST_ANGLE, GUST_ANGLE, 16, Color(color, color.a * (0.85 - i * 0.2)), _gust_width(i), true)
	if from_player:
		draw_circle(Vector2(size.x * 0.05, 0), size.y * 0.35 * _gust_k, Color(color, color.a * 0.12))


func _gust_center(i: int) -> Vector2:
	return Vector2(size.x * (0.28 - i * 0.3), 0)


func _gust_radius(i: int) -> float:
	return size.y * (0.26 + i * 0.11) * _gust_k


func _gust_width(i: int) -> float:
	return 2.5 + 1.5 * (2 - i)


## 호 세 겹(선 굵기 + extra 포함)의 실제 범위. 호 끝(±GUST_ANGLE)이 가장 위·아래, 각 0 이 가장 앞.
func _gust_bounds(extra: float) -> Rect2:
	var sn := sin(GUST_ANGLE)
	var cs := cos(GUST_ANGLE)
	var out := Rect2()
	for i in 3:
		var c := _gust_center(i)
		var r := _gust_radius(i)
		var hw := (_gust_width(i) + extra) * 0.5
		var y := (r + hw) * sn
		var x0 := c.x + maxf(r - hw, 0.0) * cs
		var x1 := c.x + r + hw
		var b := Rect2(x0, -y, x1 - x0, 2.0 * y)
		out = b if i == 0 else out.merge(b)
	return out


## 소녀의 바람: 테두리까지 판정 사각형 반(0.45×size) 안에 들게 하는 호 반지름 비율 (1 이하).
func _fit_gust() -> float:
	var k := 1.0
	var sn := sin(GUST_ANGLE)
	for i in 3:
		var r0 := size.y * (0.26 + i * 0.11)
		var hw := (_gust_width(i) + GUST_OUTLINE) * 0.5
		k = minf(k, (size.y * 0.45 / sn - hw) / r0)               # 위·아래
		k = minf(k, (size.x * 0.45 - _gust_center(i).x - hw) / r0)  # 앞
	return clampf(k, 0.3, 1.0)


## 구슬: 둥근 몸 + 밝은 속 + 테두리 고리.
func _draw_orb(ol: Color, co: Color) -> void:
	var r := _body_height() * 0.5
	var lw := _outline_width()
	draw_colored_polygon(_body_pts, color)
	draw_circle(Vector2(-r * 0.15, -r * 0.15), r * 0.45, Color(ol.lerp(Color(1, 1, 1), 0.5), color.a * 0.85))
	draw_arc(Vector2.ZERO, r * 0.68, 0.0, TAU, 20, Color(co, co.a * 0.5), 1.2, true)
	draw_polyline(_body_closed, ol, lw, true)

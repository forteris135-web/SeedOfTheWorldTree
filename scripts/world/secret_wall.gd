extends Platform
class_name SecretWall
## 비밀 벽. 겉은 주변 지형과 같은 나무껍질이지만, 가는 실금이 아주 희미하게 빛나고 가끔 먼지가 떨어진다.
## (소울류답게 글자 안내는 없다. 눈썰미 좋은 사람만 알아챈다.)
## 소녀의 공격을 hits_to_break 번 맞으면 금이 점점 커지다가 마지막 한 대에 부서진다.
## 부서진 것은 Progress.collected[secret_id] 에 남아 다시 와도 부서져 있고,
## 안에 숨은 아이템(Pickup.hidden_in == secret_id)은 부서질 때 나타난다. 적의 공격은 무시한다.
## Platform 을 상속하므로 Terrain 아래에 두면 정화 색(edge_color/color)과 잿빛 재질을 그대로 받는다.

signal broken

## 고유 이름: secret_<방>_<번호>
@export var secret_id := ""
## 몇 대 맞으면 부서지는가
@export var hits_to_break := 3
## 공격으로 부서지는가 (비밀 천장은 머리를 박아야 하므로 끈다)
var breaks_by_attack := true

var _hits := 0
var _broken := false
var _t := 0.0
var _redraw_t := 0.0
var _shake := 0.0
var _dust: CPUParticles2D
var _hurtbox: Hurtbox
var _rng_seed := 0
## 그림 조각 금 간 벽 (지역 그림 옷에 cracked 조각이 있으면). 있으면 옛 코드 그리기는 쓰지 않는다.
var _crack: CrackedArt

## 벽 뒤 작은 방의 '동굴 속' 바탕 (2026-10-20 검수): 단단한 지형 덩어리 한가운데 각진 구멍으로 먼 배경 그림이 비쳐
## 직사각형 창처럼 보였고, 비밀 자리도 미리 드러났다 → 작은 방 안쪽(+ 벽 자리)에 어두운 바탕을 지형 묶음 맨 뒤(뒤 그림자보다 뒤)에 깐다.
## 닫혀 있을 땐 불투명(지형 속처럼), 부서지면 NICHE_OPEN_ALPHA 로 옅어져 동굴 속이 된다. 위·아래·안쪽 끝은 지형 그림 밑으로 NICHE_TUCK 만큼,
## 입구(벽의 방 쪽 면)는 벽 두께만큼 서서히 사라진다. 벽 한쪽 위·아래가 지형으로 막혀 있을 때만 (그쪽이 작은 방).
const NICHE_DRAW_INDEX := -250000
const NICHE_TUCK := 28.0
const NICHE_SCAN := 900.0
const NICHE_OPEN_ALPHA := 0.86
## 색: 위·아래 가장자리(지형 밑으로 들어가는 곳) / 가운데 줄 입구 쪽(빛이 조금 드는 곳) / 가운데 줄 안쪽 끝 — 새까만 구멍이 아니라 그늘진 굴로 읽히게
const NICHE_COLOR := Color(0.16, 0.14, 0.125)
const NICHE_COLOR_LIT := Color(0.42, 0.38, 0.34)
const NICHE_COLOR_DEEP := Color(0.27, 0.24, 0.21)
var _niche_ci := RID()
var _niche_rect := Rect2()


func _ready() -> void:
	super()   # 충돌 모양 + 잿빛 재질
	_rng_seed = int(global_position.x * 7.0 + global_position.y * 13.0) + int(size.x) + 17
	if breaks_by_attack:
		# 소녀 Hitbox(mask 16) 가 때릴 수 있는 '맞는 영역'. 직속 자식이어야 receive_hit 이 불린다.
		_hurtbox = Hurtbox.new()
		_hurtbox.collision_layer = 16
		_hurtbox.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = size
		shape.shape = rect
		shape.position = size / 2.0
		_hurtbox.add_child(shape)
		add_child(_hurtbox)
	# 가끔 떨어지는 먼지 (수상한 단서)
	_dust = CPUParticles2D.new()
	_dust.amount = 3
	_dust.lifetime = 1.6
	_dust.preprocess = 1.0
	_dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dust.emission_rect_extents = Vector2(size.x * 0.35, 3.0)
	_dust.position = _dust_origin()
	_dust.direction = Vector2(0, 1)
	_dust.spread = 12.0
	_dust.gravity = Vector2(0, 140)
	_dust.initial_velocity_min = 5.0
	_dust.initial_velocity_max = 20.0
	_dust.scale_amount_min = 1.2
	_dust.scale_amount_max = 2.6
	_dust.color = Color(color.lightened(0.45), 0.55)
	add_child(_dust)
	if CrackedArt.can_build(_skin):
		set_process(true)   # Platform 은 '수상한 지형'이 아니면 _process 를 끈다 — 금 간 그림은 숨 쉬고 흔들려야 한다
		_crack = CrackedArt.new()
		add_child(_crack)
		move_child(_crack, 1)
		_crack.setup(_skin, self, _art_polygon(), _art_flip())
		_dust.color = Color(0.72, 0.62, 0.5, 0.55)
	if secret_id != "" and Progress.is_collected(secret_id):
		_set_broken_quietly()
	if breaks_by_attack:
		_build_niche.call_deferred()   # 형제 지형이 모두 자리 잡은 뒤


## 그림 조각 금 간 벽의 모양 (벽: 사각형). 천장은 덮어쓴다 (아래가 둥근 옹이).
func _art_polygon() -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])


## 그림을 위아래로 뒤집을지 (천장에 매달린 옹이는 넓은 밑동이 위)
func _art_flip() -> bool:
	return false


## 먼지가 생기는 자리 (벽: 윗부분, 천장: 아랫부분)
func _dust_origin() -> Vector2:
	return Vector2(size.x / 2.0, 12.0)


func _process(delta: float) -> void:
	if _broken:
		return
	_t += delta
	_shake = maxf(_shake - delta * 4.0, 0.0)
	if _crack:
		# 그림 조각: 흔들림·숨 쉬는 틈 빛·갈라진 정도만 바꾼다 (다시 그리지 않음)
		_crack.position = Vector2(sin(_t * 90.0) * 3.0 * _shake, cos(_t * 70.0) * 1.5 * _shake)
		var pulse := 0.5 + 0.5 * sin(_t * 1.6 + float(_rng_seed % 7))
		_crack.set_state(pulse, float(_hits) / maxf(float(hits_to_break), 1.0), Color(1.0, 0.86, 0.6), _shake * 0.35)
		return
	_redraw_t += delta
	if _redraw_t >= 0.1 or _shake > 0.0:
		_redraw_t = 0.0
		# 먼지 색은 지형색을 따라간다 (Room 이 지형색을 입히는 건 _ready 뒤라 여기서 맞춘다)
		_dust.color = Color(color.lightened(0.45), 0.55)
		queue_redraw()


## 소녀의 공격이 닿았다 (Hurtbox 가 부른다). 적의 공격은 무시.
func receive_hit(hit: HitData, _hurtbox: Hurtbox) -> String:
	if _broken or not breaks_by_attack or not hit.from_player:
		return "ignored"
	_hits += 1
	_shake = 1.0
	_dust.amount = 3 + _hits * 4
	_dust.restart()
	Sfx.play("broke", -16.0, 0.12)
	queue_redraw()
	if _hits >= hits_to_break:
		_break()
	return "hit"


## 부서진다: 조각이 튀고, 충돌이 꺼지고, 그림이 사라진다.
func _break() -> void:
	if _broken:
		return
	_broken = true
	_disable_collision()
	if _crack:
		_crack.burst(get_parent())
	_spawn_debris()
	Juice.shake(5.0)
	Juice.rumble(0.3, 0.6, 0.15)
	Sfx.play("broke", -2.0, 0.08)
	_dust.emitting = false
	queue_redraw()
	if _niche_ci.is_valid():
		create_tween().tween_method(_set_niche_alpha, 1.0, NICHE_OPEN_ALPHA, 0.6)
	if secret_id != "":
		Progress.collect(secret_id)   # 숨은 아이템이 이 신호를 듣고 나타난다
	broken.emit()


## 다시 들어왔을 때: 이미 부서진 모습으로 시작 (연출 없음).
func _set_broken_quietly() -> void:
	_broken = true
	_disable_collision()
	_dust.emitting = false
	visible = false
	set_process(false)


# ---------------------------------------------------------------- 동굴 속 바탕 (위 설명)
func _build_niche() -> void:
	_free_niche()
	if not is_inside_tree() or not (get_parent() is CanvasItem):
		return
	var r := Rect2(global_position, size)
	var cy := r.get_center().y
	var side := 0
	for sd in [1, -1]:
		var x: float = (r.end.x + 20.0) if sd > 0 else (r.position.x - 20.0)
		if _solid_at(Vector2(x, r.position.y - 8.0)) and _solid_at(Vector2(x, r.end.y + 8.0)) and not _solid_at(Vector2(x, cy)):
			side = sd
			break
	if side == 0:
		return
	var x0: float = r.end.x if side > 0 else r.position.x
	var d := 0.0
	while d < NICHE_SCAN and not _solid_at(Vector2(x0 + side * (d + 8.0), cy)):
		d += 8.0
	if d >= NICHE_SCAN:
		return
	var mid_x := x0 + side * d * 0.5
	var top := cy
	while cy - top < NICHE_SCAN and not _solid_at(Vector2(mid_x, top - 8.0)):
		top -= 8.0
	var bot := cy
	while bot - cy < NICHE_SCAN and not _solid_at(Vector2(mid_x, bot + 8.0)):
		bot += 8.0
	var mouth: float = r.position.x if side > 0 else r.end.x      # 벽의 방 쪽 면 (여기서 0)
	var full: float = mouth + side * size.x                         # 벽 두께만큼 들어가면 다 진함
	var inner := x0 + side * (d + NICHE_TUCK)                       # 안쪽 끝 (지형 밑으로)
	var xs := PackedFloat32Array([mouth, full, inner])
	var xa := PackedFloat32Array([0.0, 1.0, 1.0])
	if side < 0:
		xs.reverse()
		xa.reverse()
	var ys := PackedFloat32Array([top - NICHE_TUCK, (top + bot) * 0.5, bot + NICHE_TUCK])
	var mid_c := [NICHE_COLOR_LIT, NICHE_COLOR_LIT, NICHE_COLOR_DEEP]   # 가운데 줄: 입구 → 안쪽 끝
	if side < 0:
		mid_c.reverse()
	var parent := get_parent() as CanvasItem
	var inv := parent.get_global_transform().affine_inverse()
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for xi in 3:
		for yi in 3:
			pts.append(inv * Vector2(xs[xi], ys[yi]))
			var c: Color = mid_c[xi] if yi == 1 else NICHE_COLOR
			cols.append(Color(c, xa[xi]))
	var idx := PackedInt32Array()
	for xi in 2:
		for yi in 2:
			var p := xi * 3 + yi
			idx.append_array(PackedInt32Array([p, p + 1, p + 3, p + 1, p + 4, p + 3]))
	var rs := RenderingServer
	_niche_ci = rs.canvas_item_create()
	rs.canvas_item_set_parent(_niche_ci, parent.get_canvas_item())
	rs.canvas_item_set_draw_index(_niche_ci, NICHE_DRAW_INDEX)
	if material:
		rs.canvas_item_set_material(_niche_ci, material.get_rid())   # 지형과 같은 잿빛 재질 (정화 전엔 회색 굴)
	rs.canvas_item_add_triangle_array(_niche_ci, idx, pts, cols)
	rs.canvas_item_set_modulate(_niche_ci, Color(1, 1, 1, NICHE_OPEN_ALPHA if _broken else 1.0))
	_niche_rect = Rect2(Vector2(minf(xs[0], xs[2]), ys[0]), Vector2(absf(xs[2] - xs[0]), ys[2] - ys[0]))


func _set_niche_alpha(a: float) -> void:
	if _niche_ci.is_valid():
		RenderingServer.canvas_item_set_modulate(_niche_ci, Color(1, 1, 1, a))


## 세상 자리 g 가 형제 지형(비밀 벽은 빼고) 안이거나 방 경계 밖인가 (방 끝에 붙은 작은 방은 경계가 안쪽 끝)
func _solid_at(g: Vector2) -> bool:
	var room := TerrainStyle.room_of(self)
	if room and "bounds" in room and (room.bounds as Rect2).has_area() and not (room.bounds as Rect2).has_point(g):
		return true
	for c in get_parent().get_children():
		if c == self or c is SecretWall:
			continue
		if c is Platform:
			if Rect2((c as Node2D).global_position, c.size).has_point(g):
				return true
		elif c is TerrainPolygon:
			if Geometry2D.is_point_in_polygon(g - (c as Node2D).global_position, c.polygon):
				return true
	return false


func _free_niche() -> void:
	if _niche_ci.is_valid():
		RenderingServer.free_rid(_niche_ci)
	_niche_ci = RID()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		_free_niche()


## 시험용: 동굴 속 바탕이 깔린 자리 (세상 좌표, 없으면 빈 사각형)
func niche_rect() -> Rect2:
	return _niche_rect if _niche_ci.is_valid() else Rect2()


func _disable_collision() -> void:
	# 물리 단계 중에 불릴 수 있으니 미뤄서 바꾼다
	set_deferred("collision_layer", 0)
	for c in get_children():
		if c is CollisionShape2D:
			c.set_deferred("disabled", true)
	if _hurtbox:
		_hurtbox.set_deferred("monitorable", false)
		for c in _hurtbox.get_children():
			if c is CollisionShape2D:
				c.set_deferred("disabled", true)


func _spawn_debris() -> void:
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 26
	burst.lifetime = 1.1
	burst.position = size / 2.0
	burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	burst.emission_rect_extents = size * 0.45
	burst.direction = Vector2(0, -1)
	burst.spread = 180.0
	burst.gravity = Vector2(0, 980)
	burst.initial_velocity_min = 120.0
	burst.initial_velocity_max = 420.0
	burst.angular_velocity_min = -360.0
	burst.angular_velocity_max = 360.0
	burst.scale_amount_min = 3.0
	burst.scale_amount_max = 8.0
	burst.color = color.lightened(0.28)
	burst.emitting = true
	add_child(burst)
	get_tree().create_timer(1.5).timeout.connect(burst.queue_free)
	# 가루
	var puff := CPUParticles2D.new()
	puff.one_shot = true
	puff.explosiveness = 0.9
	puff.amount = 18
	puff.lifetime = 0.8
	puff.position = size / 2.0
	puff.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	puff.emission_rect_extents = size * 0.5
	puff.spread = 180.0
	puff.gravity = Vector2(0, 60)
	puff.initial_velocity_min = 30.0
	puff.initial_velocity_max = 140.0
	puff.scale_amount_min = 4.0
	puff.scale_amount_max = 10.0
	puff.color = Color(color.lightened(0.5), 0.35)
	puff.emitting = true
	add_child(puff)
	get_tree().create_timer(1.2).timeout.connect(puff.queue_free)


## 몸체 모양 (벽: 살짝 울퉁불퉁한 사각형). 천장은 덮어쓴다.
func _body_polygon(rng: RandomNumberGenerator) -> PackedVector2Array:
	var w := size.x
	var h := size.y
	return PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w + rng.randf_range(-2, 2), h * 0.5), Vector2(w, h),
		Vector2(0, h), Vector2(rng.randf_range(-2, 2), h * 0.5)])


## 실금이 지나는 길 (긴 축을 따라 지그재그).
func _crack_points(rng: RandomNumberGenerator) -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var pts := PackedVector2Array()
	var vertical := h >= w
	var n := 7
	for i in n + 1:
		var t := float(i) / n
		if vertical:
			pts.append(Vector2(w * 0.5 + rng.randf_range(-w * 0.28, w * 0.28), t * h))
		else:
			pts.append(Vector2(t * w, h * 0.55 + rng.randf_range(-h * 0.22, h * 0.22)))
	return pts


func _draw() -> void:
	if _broken or _crack:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng_seed
	var w := size.x
	var h := size.y
	if _shake > 0.0:
		draw_set_transform(Vector2(sin(_t * 90.0) * 3.0 * _shake, cos(_t * 70.0) * 1.5 * _shake))
	draw_colored_polygon(_body_polygon(rng), color)
	# 껍질 결 (주변 지형과 같은 화풍)
	var streak := color.lightened(0.1)
	for i in int(w * h / 2200.0) + 3:
		var x0 := rng.randf_range(4, w - 4)
		var y0 := rng.randf_range(6, h - 6)
		var len := rng.randf_range(14, minf(60, w))
		if h >= w:
			draw_line(Vector2(x0, y0), Vector2(x0 + rng.randf_range(-3, 3), y0 + len), streak, 1.5, true)
		else:
			draw_line(Vector2(x0, y0), Vector2(x0 + len, y0 + rng.randf_range(-3, 3)), streak, 1.5, true)
	# 실금: 희미하게 숨 쉬듯 빛난다. 맞을수록 굵고 밝아진다.
	var crack := _crack_points(rng)
	var stage := float(_hits) / maxf(float(hits_to_break), 1.0)
	var pulse := 0.5 + 0.5 * sin(_t * 1.6 + float(_rng_seed % 7))
	var glow_a := 0.08 + 0.07 * pulse + 0.5 * stage
	var glow_c := edge_color.lightened(0.25)
	draw_polyline(crack, Color(glow_c, glow_a * 0.45), 5.0 + 7.0 * stage, true)
	draw_polyline(crack, Color(glow_c, glow_a), 1.3 + 2.2 * stage, true)
	# 맞을 때마다 곁가지 금이 늘어난다
	for k in _hits:
		var i := 1 + (k * 2) % (crack.size() - 2)
		var p := crack[i]
		var d := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() * rng.randf_range(14, 34)
		draw_line(p, p + d, Color(glow_c, glow_a * 0.9), 1.5, true)
		draw_line(p + d, p + d + d.rotated(rng.randf_range(-0.9, 0.9)) * 0.6, Color(glow_c, glow_a * 0.7), 1.2, true)
	# 아주 작은 이끼 몇 점 (금 가장자리에 자라난 듯)
	for i in 3:
		var p := crack[rng.randi_range(0, crack.size() - 1)] + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		draw_circle(p, rng.randf_range(1.5, 3.0), moss_color.lerp(moss_light, rng.randf() * 0.4))

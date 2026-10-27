extends Area2D
class_name RootTentacle
## 뿌리 촉수 (뿌리지기 v1.1.1 '맵 패턴'): 땅에서 아주 긴 뿌리 촉수가 비스듬히 솟아 싸움터를 가로지른다. 가드 불가 — 피하거나 구른다.
## 흐름: delay 동안 붉은 예고 띠(가드 불가 = 진한 붉은빛, 2.5Hz 맥동) → 솟음(EXTEND, 땅에서 끝까지 뻗어 나감) → 판정(HIT_WINDOW 안 한 번)
##       → 잠시 서 있음(HOLD, 판정 없음) → 가라앉음(SINK).
## 노드의 원점 = 땅의 밑동, 노드의 회전 = 촉수 방향 (노드 로컬 -Y 가 촉수가 뻗는 쪽 — 뿌리 가시와 같은 틀).
## 예고 = 판정 = 그림: 셋 다 노드 로컬의 같은 띠 band_rect() = Rect2(-width/2, -length, width, length) 를 쓴다.
##   예고는 그 띠를 그대로 그리고(바닥에서 끝으로 차오름), 판정 사각형은 솟는 만큼 그 띠를 따라 자라 다 솟으면 띠와 똑같고,
##   그림(뿌리 가시 그림의 줄기 조각을 이어 붙임)은 띠 폭에 맞춰 띠 안에 그린다.
## 그림 재사용: art/fx/root_spike_art (뿌리 가시)의 줄기를 잘라 이어 붙이고 끝에 가시 끝 — 가드 불가라 붉게(danger 팔레트) 칠한다.
## 솟는 순간 밑동에서 흙 파편 + root_burst_fx. 판정이 지나간 뒤 서 있는 촉수는 닿아도 맞지 않는다 (뿌리 가시와 같은 규칙).

var damage := 24.0
var delay := 1.2
var length := 1800.0
var width := WIDTH
var source: Node2D
var _t := 0.0
var _len := 0.0
var _shape: CollisionShape2D
var _hit_done := false
var _rose := false
var _art: Node2D
var _dirt: CPUParticles2D
var _ember := 0.0
## 띠 폭 (px). 뿌리 가시 그림 줄기 폭(약 60px) × ART_SCALE 와 맞춘다.
const WIDTH := 130.0
const EXTEND := 0.16
const HIT_WINDOW := 0.32
const HOLD := 0.85
const SINK := 0.35
## 예고 색: 가드 불가 (RangeTelegraph 와 같은 붉은빛 + 안쪽 밝은 선)
const RED := Color(1.0, 0.15, 0.10)
const RED_INNER := Color(1.0, 0.86, 0.80)
const BLINK_HZ := 2.5
## 그림: 뿌리 가시 그림(187×270)의 줄기 조각과 끝 조각 (그림 px)
const ART := "root_spike_art"
const BODY_SRC := Rect2(50, 92, 76, 66)
const TIP_SRC := Rect2(50, 18, 76, 78)
## 그림 배율: 줄기 조각 폭 76px × 1.75 ≈ 133 ≈ 띠 폭
const ART_SCALE := 1.75


func _ready() -> void:
	add_to_group("projectile")
	add_to_group("root_effect")
	collision_layer = 0
	collision_mask = 8
	_shape = CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(width, 4.0)
	_shape.shape = r
	_shape.position = Vector2(0, -2.0)
	_shape.disabled = true
	add_child(_shape)
	_dirt = CPUParticles2D.new()
	_dirt.emitting = false
	_dirt.one_shot = true
	_dirt.explosiveness = 1.0
	_dirt.amount = 26
	_dirt.lifetime = 0.7
	_dirt.direction = Vector2(0, -1)
	_dirt.spread = 60.0
	_dirt.gravity = Vector2(0, 1100).rotated(-rotation)
	_dirt.initial_velocity_min = 300.0
	_dirt.initial_velocity_max = 640.0
	_dirt.scale_amount_min = 3.0
	_dirt.scale_amount_max = 8.0
	_dirt.color = Color(0.36, 0.28, 0.3, 0.9)
	_dirt.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dirt.emission_rect_extents = Vector2(width * 0.5, 4)
	add_child(_dirt)
	_art = Node2D.new()
	_art.material = Fx.shared_material("danger", false, 0.7)
	_art.draw.connect(_draw_art)
	add_child(_art)


func launch(_dir: Vector2, src: Node2D, _player_owned: bool) -> void:
	source = src


## 예고·판정·그림이 함께 쓰는 띠 (노드 로컬): 밑동(y=0)에서 촉수 끝(y=-length)까지, 폭 width
func band_rect() -> Rect2:
	return Rect2(-width / 2.0, -length, width, length)


## 띠의 월드 네 꼭짓점 (시험·예고 확인용)
func band_polygon() -> PackedVector2Array:
	var r := band_rect()
	var xf := global_transform
	return PackedVector2Array([xf * r.position, xf * Vector2(r.end.x, r.position.y), xf * r.end, xf * Vector2(r.position.x, r.end.y)])


## 지금 판정 사각형 (노드 로컬, 판정이 꺼져 있으면 빈 사각형)
func hit_rect() -> Rect2:
	if _shape == null or _shape.disabled:
		return Rect2()
	var s: Vector2 = (_shape.shape as RectangleShape2D).size
	return Rect2(_shape.position - s / 2.0, s)


## 솟은 길이 (시험용)
func extended() -> float:
	return _len


func is_telegraphing() -> bool:
	return _t < delay


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < delay:
		_ember -= delta
		if _ember <= 0.0:
			_ember = 0.16
			# 밑동 둘레에서 붉은 불티가 오른다 (가드 불가 예고)
			Fx.spawn("danger_ember", global_position + Vector2(randf_range(-width * 0.6, width * 0.6), -6.0))
		queue_redraw()
		return
	var u := _t - delay
	if u < EXTEND:
		_len = Motion.ease_out(u / EXTEND, 2.0) * length
		if not _rose:
			_rose = true
			_dirt.restart()
			_dirt.emitting = true
			Juice.shake(7.0)
			Fx.spawn("root_burst_fx", global_position, {"scale": 0.9, "palette": "danger", "keep": 0.4})
	elif u < HOLD:
		_len = length + sin(u * 30.0) * 6.0 * (1.0 - u / HOLD)
	else:
		_len = lerpf(length, 0.0, Motion.ease_in(clampf((u - HOLD) / SINK, 0.0, 1.0), 2.0))
	if u > HOLD + SINK:
		queue_free()
		return
	# 판정: 띠를 따라 솟은 만큼 자란다 (다 솟으면 band_rect 와 똑같다). 판정 창이 지나면 끈다.
	if u < HIT_WINDOW:
		var hgt := length if u >= EXTEND else maxf(minf(_len, length), 4.0)   # 다 솟은 뒤는 띠 그대로 (서 있을 때의 흔들림과 상관없이)
		var rs: RectangleShape2D = _shape.shape
		rs.size = Vector2(width, hgt)
		_shape.position = Vector2(0, -hgt / 2.0)
		_shape.disabled = false
		if not _hit_done:
			for area in get_overlapping_areas():
				if area is Hurtbox:
					var hit := HitData.make(damage, 0.0, self, Vector2(420, -380))
					hit.guardable = false
					hit.parryable = false
					hit.hitstop = 0.07
					var res: String = area.receive(hit)
					if res != "ignored":
						_hit_done = true
	elif not _shape.disabled:
		_shape.disabled = true
	queue_redraw()
	_art.queue_redraw()


func _draw() -> void:
	if _t >= delay:
		return
	var p := clampf(_t / maxf(delay, 0.001), 0.0, 1.0)
	var blink := 0.7 + 0.3 * sin(_t * TAU * BLINK_HZ)
	var fade := clampf(_t / 0.12, 0.0, 1.0)
	var r := band_rect()
	# 옅은 바탕(처음부터 띠 전체) + 밑동에서 끝으로 차오르는 채움
	draw_rect(r, Color(RED, 0.10 * fade))
	var fill_h := r.size.y * p
	draw_rect(Rect2(r.position.x, -fill_h, r.size.x, fill_h), Color(RED, (0.16 + 0.14 * p) * blink * fade))
	# 테두리 (붉은 굵은 선 + 안쪽 밝은 선 — 어두운 심연에서도 띠 끝이 읽히게)
	var c0 := Vector2(r.position.x, 0.0)
	var c1 := Vector2(r.end.x, 0.0)
	var c2 := Vector2(r.end.x, -r.size.y)
	var c3 := Vector2(r.position.x, -r.size.y)
	var edge := Color(RED, (0.6 + 0.35 * p) * blink * fade)
	draw_polyline(PackedVector2Array([c0, c3, c2, c1]), edge, 3.0, true)
	var inner := Color(RED_INNER, (0.25 + 0.35 * p) * blink * fade)
	draw_line(c0 + Vector2(5, 0), c3 + Vector2(5, 5), inner, 2.0, true)
	draw_line(c1 + Vector2(-5, 0), c2 + Vector2(-5, 5), inner, 2.0, true)
	# 뻗어 나갈 쪽을 가리키는 갈매기 표시 (밑동 → 끝, 천천히 흐른다)
	var step := 240.0
	var off := fmod(_t * 420.0, step)
	var y := -60.0 - off
	while y > -r.size.y + 40.0:
		var a := Color(RED_INNER, 0.55 * blink * fade * clampf(1.0 - (-y) / r.size.y * 0.4, 0.3, 1.0))
		draw_polyline(PackedVector2Array([Vector2(-width * 0.3, y + 26.0), Vector2(0, y), Vector2(width * 0.3, y + 26.0)]), a, 3.0, true)
		y -= step
	# 밑동: 땅이 갈라지는 자국 (땅과 나란히 — 회전을 되돌려 그린다)
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	draw_colored_polygon(RootSpike._ellipse(Vector2.ZERO, 95.0, 20.0, 24), Color(RED, (0.22 + 0.25 * p) * blink * fade))
	for i in 5:
		var ox := -60.0 + 30.0 * i
		draw_line(Vector2(ox, -2.0), Vector2(ox + (i - 2) * 8.0, -18.0 - 50.0 * p), Color(RED, 0.7 * p * fade), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 촉수 그림: 줄기 조각을 밑동부터 솟은 길이(_len)만큼 이어 붙이고 끝에 가시 끝. 띠(band_rect) 안에 맞춘다.
func _draw_art() -> void:
	if _len <= 4.0:
		return
	var tex := Fx.texture(ART)
	var w := width
	if tex == null:
		# 그림이 없으면 코드로 (나무껍질 띠)
		_art.draw_rect(Rect2(-w / 2.0, -_len, w, _len), Color(0.34, 0.22, 0.28))
		_art.draw_line(Vector2(0, 0), Vector2(0, -_len), Color(0.6, 0.45, 0.5), 3.0)
		return
	var tip_h := TIP_SRC.size.y * ART_SCALE
	var seg_h := BODY_SRC.size.y * ART_SCALE
	var dw := BODY_SRC.size.x * ART_SCALE
	var body_end := maxf(_len - tip_h, 0.0)
	var y := 0.0
	while y < body_end:
		var h := minf(seg_h, body_end - y)
		# 조각의 아래쪽부터 h 만큼 (밑동 쪽 조각이 땅에 붙게). 조각마다 그림의 같은 줄기를 이어 붙인다
		var src := Rect2(BODY_SRC.position + Vector2(0, BODY_SRC.size.y - h / ART_SCALE), Vector2(BODY_SRC.size.x, h / ART_SCALE))
		_art.draw_texture_rect_region(tex, Rect2(Vector2(-dw / 2.0, -y - h), Vector2(dw, h)), src)
		y += h
	var th := minf(tip_h, _len)
	var tsrc := Rect2(TIP_SRC.position + Vector2(0, TIP_SRC.size.y - th / ART_SCALE), Vector2(TIP_SRC.size.x, th / ART_SCALE))
	_art.draw_texture_rect_region(tex, Rect2(Vector2(-dw / 2.0, -_len), Vector2(dw, th)), tsrc)

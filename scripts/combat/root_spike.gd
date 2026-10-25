extends Area2D
class_name RootSpike
## 땅에서 솟는 뿌리 가시. 솟는 순간만 맞는다(가드 가능). 잠시 서 있다가 다시 들어간다.
## 2026-10-19 기획자 요청(가시성): 높이 1.5배(260→390)·폭 넓게(70→110), 솟을 때 흙 파편·화면 흔들림, 끝에 빛.
## delay 를 주면 그만큼 기다렸다 솟는다 (물결처럼 차례로 솟는 2페이즈 가시 줄). 기다리는 동안은 스스로 바닥 예고(주황)를 그린다
## — 보스의 예고는 타격 시작 순간 꺼지므로, 늦게 솟는 가시도 솟기 직전까지 자리가 보이게.
## 판정 사각형은 그려진 높이(_h)를 따라 자란다.
## 그림 (2026-10-19 이펙트 리뉴얼 F2): 기획자 이펙트 시트의 뒤틀린 뿌리 가시(art/fx/root_spike_art)가 땅에서 솟아오른다
## (그림의 위쪽부터 _h 만큼 드러난다 — 끝이 먼저 나오고 밑동이 땅에 붙는다). 빛을 받지 않는 재질이라 어두운 심연에서도 또렷하다.
## 기다리는 동안의 주황 바닥 예고(draw_telegraph)는 코드 그림 그대로 (보스 그림도 같은 함수를 쓴다).

var damage := 20.0
var delay := 0.0
var source: Node2D
var _t := 0.0
var _h := 0.0
var _shape: CollisionShape2D
var _hit_done := false
var _rose := false
var _dirt: CPUParticles2D
var _art: Sprite2D
var _mark: Node2D
const HEIGHT := 390.0
## 그림: 뿌리 가시 (위쪽 끝 ~ 아래 밑동). ART_TIP 는 그림 위에서 가시 끝까지의 비율, ART_BASE 는 밑동(땅) 자리의 비율.
const ART := "root_spike_art"
const ART_SCALE := 1.55
const ART_BASE := 0.93
## 예고 색 (그림 root_keeper_visual 의 GUARD_C 와 같은 주황: 가드 가능)
const TELEGRAPH_C := Color(1.0, 0.5, 0.15)
const WIDTH := 110.0
const RISE := 0.14
const HOLD := 0.95
const SINK := 0.4
## 다섯 갈래 (가운데가 가장 높다): x 오프셋, 높이 비율, 밑동 반폭
const PRONGS := [[-44.0, 0.66, 15.0], [-22.0, 0.84, 19.0], [0.0, 1.0, 24.0], [22.0, 0.84, 19.0], [44.0, 0.66, 15.0]]


func _ready() -> void:
	add_to_group("projectile")
	add_to_group("root_effect")
	collision_layer = 0
	collision_mask = 8
	_shape = CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(WIDTH, 30.0)
	_shape.shape = r
	_shape.position = Vector2(0, -15.0)
	add_child(_shape)
	# 흙 파편
	_dirt = CPUParticles2D.new()
	_dirt.emitting = false
	_dirt.one_shot = true
	_dirt.explosiveness = 1.0
	_dirt.amount = 22
	_dirt.lifetime = 0.7
	_dirt.direction = Vector2(0, -1)
	_dirt.spread = 55.0
	_dirt.gravity = Vector2(0, 1100)
	_dirt.initial_velocity_min = 320.0
	_dirt.initial_velocity_max = 680.0
	_dirt.scale_amount_min = 3.0
	_dirt.scale_amount_max = 8.0
	_dirt.color = Color(0.36, 0.28, 0.3, 0.9)
	_dirt.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dirt.emission_rect_extents = Vector2(WIDTH * 0.5, 4)
	add_child(_dirt)
	# 뿌리 가시 그림 (위쪽부터 드러난다)
	_art = Sprite2D.new()
	_art.texture = Fx.texture(ART)
	_art.material = Fx.shared_material("", false, 0.0)
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.centered = false
	_art.region_enabled = true
	_art.scale = Vector2(ART_SCALE, ART_SCALE)
	_art.visible = false
	add_child(_art)
	# 솟기 전 기다리는 동안의 바닥 예고 (주황 그대로)
	_mark = Node2D.new()
	_mark.draw.connect(_draw_mark)
	add_child(_mark)


func launch(_dir: Vector2, src: Node2D, _player_owned: bool) -> void:
	source = src


## 지금 가시 높이 (시험용)
func height() -> float:
	return _h


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < delay:
		_mark.queue_redraw()
		return
	if _mark.visible:
		_mark.visible = false
	var u := _t - delay
	# 0~0.14초 솟음, 0.95초까지 서 있음(살짝 떨림), 1.35초까지 들어감
	if u < RISE:
		_h = ease(u / RISE, 0.4) * HEIGHT
		if not _rose:
			_rose = true
			_dirt.restart()
			_dirt.emitting = true
			Juice.shake(5.0)
			Fx.spawn("root_burst_fx", global_position, {"scale": 0.7})
	elif u < HOLD:
		_h = HEIGHT + sin(u * 34.0) * 4.0 * (1.0 - u / HOLD)
	else:
		_h = lerpf(HEIGHT, 0.0, (u - HOLD) / SINK)
	if u > HOLD + SINK:
		queue_free()
		return
	# 판정은 그려진 높이를 따라 자란다 (솟기 시작한 첫 프레임부터 390 전체가 맞던 것을 고침)
	var hgt := maxf(_h, 30.0)
	var rs: RectangleShape2D = _shape.shape
	if absf(rs.size.y - hgt) > 1.0:
		rs.size = Vector2(WIDTH, hgt)
		_shape.position = Vector2(0, -hgt / 2.0)
	if u < 0.35 and not _hit_done:
		for area in get_overlapping_areas():
			if area is Hurtbox:
				var hit := HitData.make(damage, 0.0, source if source else self, Vector2(300, -420))
				hit.hitstop = 0.05
				var res: String = area.receive(hit)
				if res != "ignored":
					_hit_done = true
	_update_art()
	if _art == null or _art.texture == null:
		queue_redraw()


## 그림의 위쪽부터 _h 만큼 드러낸다: 드러난 부분의 아래 끝(밑동 자리)이 땅(y=0)에 붙는다.
func _update_art() -> void:
	if _art == null or _art.texture == null:
		return
	var ts := _art.texture.get_size()
	var k := clampf(_h / HEIGHT, 0.0, 1.0)
	_art.visible = k > 0.01
	if not _art.visible:
		return
	var vis_h := ts.y * ART_BASE * k + ts.y * (1.0 - ART_BASE)
	vis_h = minf(vis_h, ts.y)
	_art.region_rect = Rect2(0, 0, ts.x, vis_h)
	# 밑동(그림의 ART_BASE 자리, 드러난 부분에선 아래에서 (1-ART_BASE)*ts.y 위)이 땅에 오게
	_art.position = Vector2(-ts.x * ART_SCALE * 0.5, -(vis_h - ts.y * (1.0 - ART_BASE)) * ART_SCALE)


func _draw() -> void:
	if _art and _art.texture:
		return   # 그림(Sprite2D)이 그린다
	if _h <= 4.0:
		return
	var body := Color(0.4, 0.28, 0.46)
	var edge := Color(0.85, 0.72, 0.95)
	var tip := Color(0.9, 0.8, 1.0)
	# 밑동 흙더미
	draw_colored_polygon(_ellipse(Vector2(0, 0), 76.0, 14.0), Color(0.2, 0.15, 0.2))
	for pr in PRONGS:
		var ox: float = pr[0]
		var hh: float = _h * pr[1]
		var hw: float = pr[2]
		# 살짝 휜 가시: 왼쪽/오른쪽 가장자리를 점으로
		var bend := ox * 0.35 * (hh / HEIGHT)
		var pts := PackedVector2Array([Vector2(ox - hw, 0), Vector2(ox - hw * 0.55 + bend * 0.5, -hh * 0.55), Vector2(ox + bend, -hh), Vector2(ox + hw * 0.55 + bend * 0.5, -hh * 0.55), Vector2(ox + hw, 0)])
		draw_colored_polygon(pts, body)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2]]), edge, 2.5, true)
		# 마디 (옹이)
		for k in 3:
			var yk := -hh * (0.25 + 0.22 * k)
			var wk := hw * (1.0 - 0.25 * k) * 0.8
			draw_line(Vector2(ox - wk + bend * (0.25 + 0.22 * k), yk), Vector2(ox + wk + bend * (0.25 + 0.22 * k), yk), Color(0.25, 0.17, 0.3), 2.0)
		# 끝 (밝음)
		draw_colored_polygon(PackedVector2Array([Vector2(ox - 5 + bend, -hh + 34), Vector2(ox + bend, -hh), Vector2(ox + 5 + bend, -hh + 34)]), tip)


func _draw_mark() -> void:
	if _t >= delay:
		return
	var pulse := 0.5 + 0.5 * sin(_t * 40.0)
	RootSpike.draw_telegraph(_mark, Vector2.ZERO, 1.0, TELEGRAPH_C, 1.0, pulse)


## 가시 예고 (보스 그림과 기다리는 가시가 함께 쓴다): 바닥 띠(채움+맥동 테두리) + 위로 번지는 빛 + 금 가는 선
## + 가시가 닿는 높이(HEIGHT)까지 판정 폭(WIDTH)의 옅은 기둥과 윗선. col 의 알파는 깜빡임 등 곱할 세기.
static func draw_telegraph(ci: CanvasItem, pos: Vector2, p: float, col: Color, fade: float, pulse: float) -> void:
	var a := col.a * fade
	var c := Color(col.r, col.g, col.b)
	var w := WIDTH   # v1.1.0: 예고 바닥 폭 = 판정 폭 (예전엔 110 → 160 으로 커져 판정보다 넓었다)
	ci.draw_rect(Rect2(pos + Vector2(-w / 2.0, -14), Vector2(w, 18)), Color(c, (0.2 + 0.3 * p * (0.6 + 0.4 * pulse)) * a))
	for i in 5:
		var hh := 24.0 + 26.0 * i
		ci.draw_rect(Rect2(pos + Vector2(-w / 2.0 + i * 5.0, -14.0 - hh), Vector2(w - i * 10.0, hh)), Color(c, 0.09 * p * a))
	ci.draw_rect(Rect2(pos + Vector2(-w / 2.0, -14), Vector2(w, 18)), Color(c, (0.5 + 0.5 * pulse) * a), false, 2.0)
	# 금 가는 선 (위로 자란다)
	for i in 5:
		var ox := -w / 2.0 + w * (i + 0.5) / 5.0
		var hh := 20.0 + 70.0 * p * (1.0 if i == 2 else 0.7)
		ci.draw_line(pos + Vector2(ox, -2), pos + Vector2(ox + (i - 2) * 6.0, -hh), Color(c, 0.7 * p * a), 2.0)
	# 가시 높이까지 옅은 기둥 (예비 70% 에 다 자란다): 가지 위에 서 있어도 닿는다는 것이 보인다
	var colh := HEIGHT * clampf(p / 0.7, 0.0, 1.0)
	if colh > 20.0:
		ci.draw_rect(Rect2(pos + Vector2(-WIDTH / 2.0, -colh), Vector2(WIDTH, colh - 14.0)), Color(c, 0.07 * a))
		ci.draw_line(pos + Vector2(-WIDTH / 2.0, -colh), pos + Vector2(WIDTH / 2.0, -colh), Color(c, (0.35 + 0.25 * pulse) * a), 2.0)
		ci.draw_line(pos + Vector2(-WIDTH / 2.0, -14.0), pos + Vector2(-WIDTH / 2.0, -colh), Color(c, 0.2 * a), 1.5)
		ci.draw_line(pos + Vector2(WIDTH / 2.0, -14.0), pos + Vector2(WIDTH / 2.0, -colh), Color(c, 0.2 * a), 1.5)


static func _ellipse(c: Vector2, rx: float, ry: float, n := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

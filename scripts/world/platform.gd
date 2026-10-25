extends StaticBody2D
class_name Platform
## 지형 조각 (발판·바닥·벽·천장). 원점은 왼쪽 위, 충돌은 size 사각형 (one_way 면 아래에서 통과).
## 겉모습은 두 가지:
##  - 그림 조각 지형 (지역에 그림 옷이 있으면 — 지금은 41방 모두): TerrainArt 가 기획자 그림 조각을 이어 붙여 한 번 만든다.
##    설명서는 TERRAIN.md. 이때 아래 '코드로 그리기'(몸통·겹·색 setter)는 쓰지 않는다.
##  - 코드로 그리기 (그림이 아직 없는 지역): 굽은 가지 모양의 어두운 실루엣 + 나무껍질 결 + 윗면 이끼·잎 + 늘어진 덩굴.
##    (기획서 9장: 지형은 어두운 실루엣에 배경의 주된 색을 살짝 입히고, 윗면에 가는 빛 테두리)
## 정화 전에는 공용 잿빛 재질(팔레트 바꾸기)로 지역의 잿빛 색이 된다.
## - 디테일(2026-10-19 기획자 요청): 실루엣 가장자리에 읽히는 디테일(이끼 무더기·잘린 잔가지·늘어진 이끼 수염·
##   뿌리 가닥·잎 달린 덩굴·가지 끝 잎 묶음·덩어리 모서리 이끼), 안쪽은 윗면 빛 띠 + 껍질 결·홈·옹이,
##   지역별 장식(TerrainStyle 표). 지역은 조상 Room 의 region (style_region 으로 강제 가능).
## - 그림은 세 겹이다: 몸통(이 노드) → 윗면 빛 겹(테두리·빛 띠) → 장식 겹(이끼·잎·매달린 것).
##   정화 연출 중 Room 이 매 프레임 바꾸는 테두리 색은 윗면 빛 겹만 다시 그린다 (몸통·장식은 그대로).
##   비밀 벽(SecretWall)은 자기 그림을 쓰므로 겹을 만들지 않는다.
## - label_text 는 개발용 메모다: 설정의 '개발 표시'(debug_hud)가 켜져 있을 때만 보인다.
## - suspicious 가 켜진 발판은 글자 없이 '수상한' 단서만 보인다(소울류처럼):
##   이끼가 조금 창백하고, 윗면에 희미한 온기 빛, 빛 가루가 천천히 떠오른다.

@export var size := Vector2(400, 40):
	set(v):
		size = v
		_geo = {}
		_cover_ready = false
		_redraw_all()
@export var color := Color("15150f"):
	set(v):
		if v == color:
			return
		color = v
		if _art:
			return   # 그림 조각 지형은 몸통 색을 쓰지 않는다
		# 몸통 + 장식(잔가지가 몸통 색을 쓴다). 색은 방에 들어올 때 한 번만 바뀐다.
		queue_redraw()
		if _decor_layer:
			_decor_layer.queue_redraw()
@export var edge_color := Color(1.0, 0.89, 0.62, 0.8):
	set(v):
		if v == edge_color:
			return
		edge_color = v
		if _art:
			return   # 그림 조각 지형은 테두리 빛을 그림이 대신한다 (정화 연출 중 다시 그리지 않음)
		# 정화 연출 중에는 매 프레임 바뀐다 → 가벼운 윗면 빛 겹만 다시 그린다
		if _edge_layer:
			_edge_layer.queue_redraw()
		else:
			queue_redraw()
## 이끼·잎·덩굴 색 (정화 후 기준. 정화 전엔 셰이더가 잿빛으로 만든다).
## 기본값 그대로면 지역 팔레트(TerrainStyle)의 색을 쓴다. 방 파일에서 따로 정하면 그 색을 쓴다.
const DEFAULT_MOSS := Color(0.42, 0.52, 0.24)
const DEFAULT_MOSS_LIGHT := Color(0.72, 0.76, 0.36)
const DEFAULT_VINE := Color(0.13, 0.17, 0.1)
@export var moss_color := DEFAULT_MOSS
@export var moss_light := DEFAULT_MOSS_LIGHT
@export var vine_color := DEFAULT_VINE
## 지역 팔레트를 강제로 고른다 (비워 두면 조상 Room 의 region). 시험·특수 발판용.
@export var style_region := ""
## 발판 위에 띄울 개발용 메모. 플레이 화면에는 안 보이고 '개발 표시'를 켜야 보인다.
@export var label_text := ""
## 장식을 그릴지 (벽·천장은 끈다)
@export var decorate := true
## 한쪽 방향 발판: 아래에서 뛰어오르면 통과해 위에 올라선다 (아래+점프로 내려갈 수도 있다 — player.gd 가 one_way 를 읽는다).
## (옛 단서였던 아랫선의 빛 점선은 v1.1.0 기획자 요청으로 없앴다 — 그림 지형은 한쪽 방향 발판을 가는 가지로 그려 구분한다.)
@export var one_way := false:
	set(v):
		one_way = v
		_redraw_all()
## 수상한 발판: 비밀로 이어지는 자리에 켠다. 글자 대신 미묘한 빛과 창백한 이끼로만 알린다.
@export var suspicious := false:
	set(v):
		suspicious = v
		if is_inside_tree():
			_sync_suspicious()
		else:
			_redraw_all()
## 단서가 붙는 면. 비밀 발판은 '위', 비밀 천장(머리로 치는 곳)은 '아래', 비밀 벽은 '왼쪽'/'오른쪽'.
## 빛 띠와 빛 가루가 그 면의 바깥쪽으로 번진다. 창백한 이끼는 윗면에만 있다.
@export_enum("위", "아래", "왼쪽", "오른쪽") var suspicious_face := 0:
	set(v):
		suspicious_face = v
		if is_inside_tree() and suspicious:
			_clear_suspicious()
			_sync_suspicious()

## 수상한 단서의 색(따뜻한 온기)과 이끼가 창백해지는 정도.
const HINT_COLOR := Color(1.0, 0.84, 0.55)
const HINT_HEIGHT := 24.0
const PALE_MOSS := Color(0.78, 0.86, 0.72)
const PALE_MOSS_LIGHT := Color(0.96, 0.98, 0.86)
const PALE_MIX := 0.45
## one_way 단서: 아랫선 바로 안쪽의 빛 점선 (조각 길이 / 간격 / 투명도 / 굵기). 윗면 테두리(굵기 2.0, 투명도 0.8)보다 조금 약하게.
## 몸통 밖(배경 위)에 그리면 수관처럼 환한 방에서는 안 보여서, 아랫선 바로 안쪽(2.5px 위)에 그린다.
## v1.1.0: 점선은 더 그리지 않는다 (_draw_edge 가 _one_way_dashes 를 부르지 않음). 값·함수는 되살릴 때를 위해 남겨 둔다.
const ONE_WAY_DASH_LEN := 10.0
const ONE_WAY_DASH_GAP := 12.0
const ONE_WAY_DASH_ALPHA := 0.6
const ONE_WAY_DASH_WIDTH := 2.0
## 시험용(probe_terrain): 그리는 데 든 시간(마이크로초, 몸통·겹·경사·가시 모두)과 횟수 누적.
static var draw_usec := 0
## 몸통을 다시 그린 횟수 / 겹(윗면 빛·장식)을 다시 그린 횟수
static var draw_calls := 0
static var layer_calls := 0
static var edge_calls := 0
## 시험용: 몸통 / 윗면 빛 / 장식 각각에 든 시간(마이크로초)
static var body_usec := 0
static var edge_usec := 0
static var decor_usec := 0

var _label: Label
var _hint: SuspiciousHint
var _motes: CPUParticles2D
var _time := 0.0
var _style: Dictionary = {}
var _edge_layer: TerrainStyle.Layer
var _decor_layer: TerrainStyle.Layer
## 모양 (처음 그릴 때 한 번 만든다): thin(가지인가), body(몸통 다각형, 비면 사각형), top(윗선), bottom(아랫선, 왼→오), sag
var _geo := {}
## 옆 지형 (처음 장식을 그릴 때 한 번 모은다)
var _shapes: Array = []
var _top_cover := PackedByteArray()
var _bottom_cover := PackedByteArray()
var _cover_ready := false
var _glow_done := false
## 그림 조각 지형 (지역에 그림 옷이 있으면 — TerrainSkin). 있으면 옛 코드 그리기(몸통·겹)는 쓰지 않는다.
var _art: TerrainArt
var _skin: TerrainSkin
var _ready_done := false


func _ready() -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = size / 2.0
	if one_way:
		shape.one_way_collision = true
		shape.one_way_collision_margin = 24.0
	add_child(shape)
	material = preload("res://shaders/ash_purify_fore.tres")   # 앞 지형 재질 (앞뒤 가르기 — TERRAIN.md 5장)
	_apply_style()
	_skin = TerrainSkin.for_node(self, style_region)
	if _skin != null and _wants_layers():
		# 그림 조각 지형: 겉모습은 TerrainArt 가 한 번 만들어 둔다 (충돌은 위의 사각형 그대로)
		_build_art()
	elif _wants_layers():
		_edge_layer = TerrainStyle.Layer.new(self, TerrainStyle.LAYER_EDGE)
		_edge_layer.name = "EdgeLayer"
		add_child(_edge_layer)
		_decor_layer = TerrainStyle.Layer.new(self, TerrainStyle.LAYER_DECOR)
		_decor_layer.name = "DecorLayer"
		add_child(_decor_layer)
	if label_text != "":
		_label = Label.new()
		_label.text = label_text
		_label.add_theme_font_size_override("font_size", 22)
		_label.add_theme_color_override("font_color", Color("9aa3b8"))
		_label.position = Vector2(8, -34)
		_label.visible = false
		add_child(_label)
		# 개발 표시 설정을 따라간다 (메뉴에서 바꾸면 바로 반영)
		var settings := get_node_or_null("/root/Settings")
		if settings:
			settings.changed.connect(_apply_debug_label)
		_apply_debug_label()
	_sync_suspicious()
	_ready_done = true


## 그림 조각 겉모습을 (다시) 만든다.
func _build_art() -> void:
	if _art:
		remove_child(_art)
		_art.queue_free()
	_art = TerrainArt.new(_skin, self)
	_art.name = "Art"
	add_child(_art)
	move_child(_art, 1 if get_child_count() > 1 else 0)
	_art.build_platform(self, size, _is_thin(), one_way, decorate, suspicious)


## 그림 조각 지형인가 (시험용)
func is_art() -> bool:
	return _art != null


## 겹을 쓸지. 자기 _draw 로 다 그리는 하위 클래스(비밀 벽·천장)는 쓰지 않는다.
func _wants_layers() -> bool:
	return get_script() == Platform


## 지역 팔레트를 고르고, 방 파일에서 따로 정하지 않은 이끼·덩굴 색은 지역 색으로 바꾼다.
func _apply_style() -> void:
	_style = TerrainStyle.style_for(self, style_region)
	if moss_color == DEFAULT_MOSS:
		moss_color = _style["moss"]
	if moss_light == DEFAULT_MOSS_LIGHT:
		moss_light = _style["moss_light"]
	if vine_color == DEFAULT_VINE:
		vine_color = _style["vine"]


## 몸통과 두 겹을 모두 다시 그린다 (모양·장식 세기가 바뀌었을 때).
func _redraw_all() -> void:
	if _art:
		if _ready_done:
			_build_art()   # 나중에 모양·수상함이 바뀌면 겉모습을 다시 만든다 (방에 들어올 때는 한 번만)
		return
	queue_redraw()
	if _edge_layer:
		_edge_layer.queue_redraw()
	if _decor_layer:
		_decor_layer.queue_redraw()


## suspicious 값에 맞춰 단서 노드를 만들거나 지운다 (나중에 켜고 꺼도 바로 따라간다).
func _sync_suspicious() -> void:
	if suspicious:
		if _hint == null or _motes == null:
			_clear_suspicious()
			_make_suspicious_hint()
	else:
		_clear_suspicious()
	set_process(suspicious)
	_redraw_all()


func _clear_suspicious() -> void:
	if _hint:
		_hint.queue_free()
		_hint = null
	if _motes:
		_motes.queue_free()
		_motes = null


## 개발 표시가 켜져 있을 때만 메모 글자를 보인다.
func _apply_debug_label() -> void:
	if _label == null:
		return
	var settings := get_node_or_null("/root/Settings")
	_label.visible = settings != null and bool(settings.get_value("debug_hud"))


## 고른 면의 변. 시계 방향(바깥 법선 = (dir.y, -dir.x))으로 만든다.
func _suspicious_edge() -> PackedVector2Array:
	var w := size.x
	var h := size.y
	match suspicious_face:
		1:   # 아래 (천장의 아랫면) — 바로 밑에 붙은 부서지는 지형(비밀 천장 옹이)이 있으면 그 폭(+여유)만
			var span := _breakable_span_below()
			return PackedVector2Array([Vector2(span.y, h), Vector2(span.x, h)])
		2:   # 왼쪽
			return PackedVector2Array([Vector2(0, h), Vector2(0, 0)])
		3:   # 오른쪽
			return PackedVector2Array([Vector2(w, 0), Vector2(w, h)])
		_:   # 위
			return PackedVector2Array([Vector2(0, 0), Vector2(w, 0)])


## 아랫면 단서의 가로 구간 [x0, x1]: 바로 밑에 붙은 형제 부서지는 지형(secret_id — 비밀 천장 옹이)의 폭 + SPAN_PAD.
## 그림 가지는 충돌 아래로 늘어져, 발판 전체 길이의 빛 줄이면 늘어진 뿌리 한가운데를 가로질러 옹이를 가리키지 못한다. 없으면 전체 폭.
const SPAN_PAD := 24.0
func _breakable_span_below() -> Vector2:
	var lo := INF
	var hi := -INF
	var parent := get_parent()
	if parent != null and is_inside_tree():
		for s in parent.get_children():
			if s == self or not (s is Platform) or not ("secret_id" in s):
				continue
			var off: Vector2 = (s as Node2D).global_position - global_position
			if absf(off.y - size.y) > 6.0:
				continue
			var x0 := maxf(off.x, 0.0)
			var x1 := minf(off.x + (s as Platform).size.x, size.x)
			if x1 > x0:
				lo = minf(lo, x0)
				hi = maxf(hi, x1)
	if lo == INF:
		return Vector2(0.0, size.x)
	return Vector2(maxf(lo - SPAN_PAD, 0.0), minf(hi + SPAN_PAD, size.x))


## 수상한 단서: 고른 면의 온기 빛(더하기 혼합) + 그 면 바깥으로 천천히 흐르는 빛 가루 몇 개.
func _make_suspicious_hint() -> void:
	var edge := _suspicious_edge()
	_hint = SuspiciousHint.new()
	_hint.setup(edge, HINT_HEIGHT, HINT_COLOR)
	add_child(_hint)
	var dir := edge[1] - edge[0]
	var normal := Vector2(dir.y, -dir.x).normalized()   # 면의 바깥쪽
	var len := dir.length()
	var mid := (edge[0] + edge[1]) * 0.5
	var extents := Vector2(len * 0.42, 3.0) if absf(dir.x) >= absf(dir.y) else Vector2(3.0, len * 0.42)
	_motes = _make_motes(mid + normal * 6.0, extents, HINT_COLOR, normal)
	add_child(_motes)


## 빛 가루 입자 (적게, 느리게). 다른 지형(경사)도 같은 모양을 쓴다.
## normal 은 가루가 흘러가는 방향(면의 바깥쪽). 기본은 위.
static func _make_motes(pos: Vector2, extents: Vector2, tint: Color, normal := Vector2(0, -1)) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 6
	p.lifetime = 4.5
	p.preprocess = 4.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = extents
	p.position = pos
	p.direction = normal
	p.spread = 18.0
	p.gravity = normal * 5.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 12.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.4
	p.color = Color(tint.r * 1.4, tint.g * 1.4, tint.b * 1.4, 0.6)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = add
	return p


## 수상한 빛은 아주 천천히 숨 쉬듯 밝아졌다 어두워진다 (0.55 ~ 1.0).
func _process(delta: float) -> void:
	_time += delta
	if _hint:
		_hint.modulate.a = 0.775 + 0.225 * sin(_time * 1.4)


## 이끼 색: 수상한 발판은 조금 창백하다.
func _moss() -> Color:
	return moss_color.lerp(PALE_MOSS, PALE_MIX) if suspicious else moss_color


func _moss_light() -> Color:
	return moss_light.lerp(PALE_MOSS_LIGHT, PALE_MIX) if suspicious else moss_light


func _seed() -> int:
	return int(global_position.x * 7.0 + global_position.y * 13.0) + int(size.x)


func _is_thin() -> bool:
	return size.y <= 90.0 and size.x >= 120.0


## 가지 아랫선의 높이 (x 에서, 흔들림 빼고). 덩어리는 h.
func _bottom_y(x: float) -> float:
	var w := maxf(size.x, 1.0)
	return size.y + sin(clampf(x / w, 0.0, 1.0) * PI) * float(_geo.get("sag", 0.0)) * 0.35


## 모양을 한 번 만든다 (몸통·윗선·아랫선). 같은 씨앗이라 늘 같은 모양이다.
func _ensure_geo() -> void:
	if not _geo.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed()
	var w := size.x
	var h := size.y
	var thin := _is_thin()
	_geo["thin"] = thin
	if thin:
		var pts := PackedVector2Array()
		var n := int(w / 40.0) + 2
		var sag := h * 0.9 + rng.randf_range(0, h * 0.6)
		# 윗선 (왼→오), 살짝 울퉁불퉁
		for i in n + 1:
			var t := float(i) / n
			var y := -absf(sin(t * PI * 3.1 + rng.randf() * 0.2)) * 2.0 + rng.randf_range(-1.5, 1.5)
			pts.append(Vector2(t * w, y))
		# 오른쪽 끝 둥글게
		for i in 4:
			var a := -PI / 2.0 + PI * float(i + 1) / 5.0
			pts.append(Vector2(w + cos(a) * h * 0.5, h * 0.5 + sin(a) * h * 0.5))
		# 아랫선 (오→왼), 가운데가 처진다
		var bottom_start := pts.size()
		for i in n + 1:
			var t := 1.0 - float(i) / n
			pts.append(Vector2(t * w, h + sin(t * PI) * sag * 0.35 + rng.randf_range(-2.0, 2.0)))
		# 아랫선의 껍질 혹 몇 개 (실루엣이 밋밋하지 않게, 아래로만 불룩)
		var lumps := []
		for k in 1 + int(w / 300.0):
			lumps.append(Vector3(rng.randf_range(0.12, 0.88) * w, rng.randf_range(3.0, 6.5), rng.randf_range(40.0, 80.0)))
		for idx in range(bottom_start, bottom_start + n + 1):
			var add := 0.0
			for lp in lumps:
				var d: float = (pts[idx].x - lp.x) / lp.z
				add += lp.y * exp(-d * d)
			pts[idx] = pts[idx] + Vector2(0, add)
		var bottom := pts.slice(bottom_start, bottom_start + n + 1)
		bottom.reverse()
		for i in 4:
			var a := PI / 2.0 + PI * float(i + 1) / 5.0
			pts.append(Vector2(cos(a) * h * 0.5, h * 0.5 + sin(a) * h * 0.5))
		_geo["body"] = pts
		_geo["top"] = pts.slice(0, n + 1)
		_geo["bottom"] = bottom
		_geo["sag"] = sag
	else:
		var top := PackedVector2Array()
		if decorate:
			# 덩어리 윗선도 살짝 울퉁불퉁하게 (양 끝은 0 — 옆 지형과 이어지게)
			var n := maxi(int(w / 40.0), 1)
			for i in n + 1:
				var y := 0.0 if i == 0 or i == n else rng.randf_range(-2.2, 0.8)
				top.append(Vector2(w * i / n, y))
			var body := top.duplicate()
			body.append(Vector2(w, h))
			body.append(Vector2(0, h))
			_geo["body"] = body
		else:
			top = PackedVector2Array([Vector2(0, 0), Vector2(w, 0)])
			_geo["body"] = PackedVector2Array()
		_geo["top"] = top
		_geo["bottom"] = PackedVector2Array([Vector2(0, h), Vector2(w, h)])
		_geo["sag"] = 0.0


## 옆 지형에 덮인 자리를 한 번 구한다 (윗선 위쪽 / 아랫선 아래쪽).
func _ensure_cover() -> void:
	if _cover_ready:
		return
	_cover_ready = true
	var w := size.x
	var h := size.y
	_shapes = TerrainStyle.neighbor_shapes(self, Rect2(Vector2(-h, -40.0), Vector2(w + h * 2.0, h + 200.0)))
	if _shapes.is_empty():
		_top_cover = PackedByteArray()
		_bottom_cover = PackedByteArray()
		return
	var a := Vector2(6, 0) if _geo["thin"] else Vector2(4, 0)
	_top_cover = TerrainStyle.cover_flags(_shapes, TerrainStyle.line_samples(a, Vector2(w - a.x, 0), Vector2(0, -1), 8.0))
	var samples := PackedVector2Array()
	var bottom: PackedVector2Array = _geo["bottom"]
	var n := maxi(1, int(w / 12.0))
	for i in n:
		samples.append(TerrainStyle.point_on(bottom, (i + 0.5) / n) + Vector2(0, 8.0))
	_bottom_cover = TerrainStyle.cover_flags(_shapes, samples)


func _covered(p: Vector2) -> bool:
	return not _shapes.is_empty() and TerrainStyle.is_covered(_shapes, p)


# ---------------------------------------------------------------- 그리기
## 몸통 (이 노드): 실루엣 + 껍질 결·홈·옹이 + 지역 몸통 장식(채굴장 금속판·띠쇠·녹물, 수액 윤기).
func _draw() -> void:
	if _art:
		return
	var t0 := Time.get_ticks_usec()
	TerrainStyle.trace_node = self
	_ensure_geo()
	var body: PackedVector2Array = _geo["body"]
	if body.is_empty():
		draw_rect(Rect2(Vector2.ZERO, size), color)
	else:
		draw_colored_polygon(body, color)
	if _geo["thin"] or decorate:
		var rng := RandomNumberGenerator.new()
		rng.seed = _seed() + 1
		var b := TerrainStyle.Batch.new()
		if _geo["thin"]:
			_branch_body(b, rng)
		else:
			_block_body(b, rng)
		b.flush(self)
	if _edge_layer == null:
		# 겹을 만들기 전(또는 겹을 안 쓰는 경우)에는 이 노드에 다 그린다
		_draw_edge(self)
		_draw_decor(self)
	var dt := Time.get_ticks_usec() - t0
	draw_usec += dt
	body_usec += dt
	draw_calls += 1


## 겹 그리기 (TerrainStyle.Layer 가 부른다).
func _draw_layer(ci: CanvasItem, kind: int) -> void:
	var t0 := Time.get_ticks_usec()
	TerrainStyle.trace_node = self
	_ensure_geo()
	if kind == TerrainStyle.LAYER_EDGE:
		_draw_edge(ci)
		edge_calls += 1
	else:
		_draw_decor(ci)
	var dt := Time.get_ticks_usec() - t0
	draw_usec += dt
	if kind == TerrainStyle.LAYER_EDGE:
		edge_usec += dt
	else:
		decor_usec += dt
	layer_calls += 1


## 가지 몸통 안: 결 / 홈 / 옹이 / 채굴장 띠쇠·녹물 / 수액 윤기. 모든 것은 몸통 안에 머문다.
func _branch_body(b: TerrainStyle.Batch, rng: RandomNumberGenerator) -> void:
	var st := _style
	var w := size.x
	var h := size.y
	var detailed := TerrainStyle.detail >= 1
	var lift: float = st["bark_lift"] if detailed else 0.13
	var streak := color.lightened(lift)
	if detailed:
		streak.a = float(st["bark_alpha"])
	for i in TerrainStyle.n_of(w, 28.0, "streak"):
		var len := minf(rng.randf_range(16, 52), w - 8.0)
		var x0 := rng.randf_range(4.0, w - 4.0 - len)
		var y0 := rng.randf_range(h * 0.25, h * 0.85)
		var g0 := Vector2(x0, y0)
		var g1 := Vector2(x0 + len, clampf(y0 + rng.randf_range(-3, 3), h * 0.2, h * 0.88))
		if TerrainStyle.trace:
			TerrainStyle.draw_grain(self, g0, g1, streak, 2.4 if detailed else 1.5)
		else:
			draw_line(g0, g1, streak, 2.4 if detailed else 1.5, true)
	if not detailed:
		return
	for i in TerrainStyle.n_of(w, st["ridge_px"], "ridge"):
		var len := minf(rng.randf_range(40.0, 110.0), w - 16.0)
		var x0 := rng.randf_range(8.0, w - 8.0 - len)
		TerrainStyle.draw_ridge(self, rng, Vector2(x0, rng.randf_range(h * 0.38, h * 0.62)), len, color, st)
	if h >= 34.0 and w >= h * 3.0:
		# 옹이는 고르게 나눈 자리에 하나씩 (서로 붙으면 눈처럼 보인다)
		var nk := TerrainStyle.n_of(w, st["knot_px"], "knot")
		for i in nk:
			var r := clampf(h * rng.randf_range(0.18, 0.24), 5.0, 11.0)
			var slot := w / nk
			var x := clampf(slot * (i + 0.5) + rng.randf_range(-0.25, 0.25) * slot, r * 3.5, w - r * 3.5)
			TerrainStyle.draw_knot(b, self, rng, Vector2(x, h * rng.randf_range(0.5, 0.6)), r, color, st)
	_metal_body(b, rng, true)
	if st["sheen"]:
		TerrainStyle.draw_sheen(b, _geo["top"], st)


## 덩어리 몸통 안: 윗면 쪽 띠(최대 140px)에 결 / 홈 / 옹이, 깊어질수록 결이 흐려진다.
func _block_body(b: TerrainStyle.Batch, rng: RandomNumberGenerator) -> void:
	var st := _style
	var w := size.x
	var h := size.y
	var detailed := TerrainStyle.detail >= 1
	var band := minf(h, 140.0)
	var lift: float = st["bark_lift"] if detailed else 0.1
	var base_streak := color.lightened(lift)
	var alpha: float = st["bark_alpha"] if detailed else 1.0
	for i in mini(int(w * band / 2600.0) + 2, TerrainStyle.CAP["streak"]):
		var len := minf(rng.randf_range(30, 120), w - 8.0)
		var x0 := rng.randf_range(4.0, w - 4.0 - len)
		var y0 := rng.randf_range(6.0, band - 4.0)
		var col := base_streak
		col.a = alpha * (1.0 - 0.6 * y0 / band) if detailed else 1.0
		var g0 := Vector2(x0, y0)
		var g1 := Vector2(x0 + len, clampf(y0 + rng.randf_range(-4, 4), 4.0, band - 2.0))
		if TerrainStyle.trace:
			TerrainStyle.draw_grain(self, g0, g1, col, 2.4 if detailed else 1.5)
		else:
			draw_line(g0, g1, col, 2.4 if detailed else 1.5, true)
	if not detailed:
		return
	for i in mini(int(w * band / float(st["ridge_area"])) + 1, TerrainStyle.CAP["ridge"]):
		var len := minf(rng.randf_range(50.0, 160.0), w - 16.0)
		if len < 20.0:
			break
		var x0 := rng.randf_range(8.0, w - 8.0 - len)
		TerrainStyle.draw_ridge(self, rng, Vector2(x0, rng.randf_range(12.0, maxf(14.0, band - 12.0))), len, color, st)
	if h >= 50.0 and w >= 90.0:
		var nk := TerrainStyle.n_of(w, st["knot_px"], "knot")
		for i in nk:
			var r := rng.randf_range(8.0, 12.0)
			var slot := w / nk
			var x := clampf(slot * (i + 0.5) + rng.randf_range(-0.3, 0.3) * slot, r * 3.5, w - r * 3.5)
			TerrainStyle.draw_knot(b, self, rng, Vector2(x, rng.randf_range(26.0, maxf(28.0, minf(band, h - 22.0)))), r, color, st)
	_metal_body(b, rng, false)
	if st["sheen"]:
		TerrainStyle.draw_sheen(b, _geo["top"], st)
	# 드러난 옆면의 껍질 혹 (네모난 실루엣이 덜 딱딱해 보이게, 바깥으로 3~7px)
	if h >= 60.0:
		_ensure_cover()
		for side in [0.0, w]:
			var out := -1.0 if side == 0.0 else 1.0
			for i in clampi(int(h / 120.0), 1, 6):
				var l := rng.randf_range(30.0, 80.0)
				var y0 := rng.randf_range(10.0, maxf(12.0, h - l - 6.0))
				var d := rng.randf_range(3.0, 7.0) * out
				if _covered(Vector2(side + out * 8.0, y0 + l * 0.5)) or _covered(Vector2(side + out * 8.0, y0)) or _covered(Vector2(side + out * 8.0, y0 + l)):
					continue
				var s0 := Vector2(side - out * 2.0, y0)
				b.quad(s0, Vector2(side + d * 0.7, y0 + l * 0.22), Vector2(side + d, y0 + l * 0.5), Vector2(side - out * 2.0, y0 + l * 0.5), color)
				b.quad(Vector2(side - out * 2.0, y0 + l * 0.5), Vector2(side + d, y0 + l * 0.5), Vector2(side + d * 0.6, y0 + l * 0.8), Vector2(side - out * 2.0, y0 + l), color)
				TerrainStyle._tick("옆혹")


## 채굴장류: 윗선에 박힌 금속판(리벳 한 줄), 가지를 감은/모서리에 걸친 띠쇠, 위에서 흘러내린 녹물. 모두 몸통 안(띠쇠만 윗선 위로 2.5px).
func _metal_body(b: TerrainStyle.Batch, rng: RandomNumberGenerator, thin: bool) -> void:
	var st := _style
	var w := size.x
	var h := size.y
	var inner_max := h - 4.0 if thin else minf(h, 140.0) - 4.0
	for i in TerrainStyle.n_of(w, st["rust_px"], "rust"):
		var x := rng.randf_range(8.0, w - 8.0)
		var y0 := rng.randf_range(3.0, 8.0)
		var bottom := (_bottom_y(x) - 4.0) if thin else inner_max
		var len := minf(rng.randf_range(12.0, 40.0), bottom - y0)
		if len > 4.0:
			TerrainStyle.draw_rust_line(self, rng, Vector2(x, y0), len, st)
	if not thin and h >= 30.0:
		for i in TerrainStyle.n_of(w, st["plate_px"], "plate"):
			var pw := rng.randf_range(50.0, minf(120.0, w * 0.5))
			if pw < 30.0:
				break
			var ph := rng.randf_range(12.0, minf(16.0, h * 0.4))
			TerrainStyle.draw_plate(b, self, rng, rng.randf_range(8.0, w - pw - 8.0), pw, ph, inner_max, st)
	for i in TerrainStyle.n_of(w, st["strap_px"], "strap"):
		var x := rng.randf_range(16.0, w - 30.0)
		var y1 := (_bottom_y(x) - 1.0) if thin else minf(26.0, h - 6.0)
		TerrainStyle.draw_strap(b, self, rng, x, y1, thin, st)


## 윗면 빛 겹: 빛 띠 + 윗면 테두리. 정화 연출 중에는 이것만 다시 그린다.
func _draw_edge(ci: CanvasItem) -> void:
	var thin: bool = _geo["thin"]
	if not thin and not decorate:
		return
	var h := size.y
	var top: PackedVector2Array = _geo["top"]
	var b := TerrainStyle.Batch.new()
	if TerrainStyle.detail >= 1 and (thin or decorate):
		var depth := minf(18.0, h * 0.45) if thin else minf(float(_style["glow_depth"]), h * 0.3)
		TerrainStyle.draw_top_glow(b, top, edge_color, depth)
	b.flush(ci)
	if thin:
		ci.draw_polyline(top, edge_color, 2.0, true)
	elif decorate:
		ci.draw_polyline(Transform2D(0.0, Vector2(0, 1)) * top, edge_color, 2.0, true)


## one_way 단서: 아랫선을 따라 끊어진 빛 점선. 가지는 처진 아랫선(같은 sag)을 따라가고, 덩어리는 밑변을 따라 그린다. (v1.1.0 부터 쓰지 않는다)
func _one_way_dashes(b: TerrainStyle.Batch, w: float, h: float, sag: float) -> void:
	var tint := Color(edge_color.r, edge_color.g, edge_color.b, ONE_WAY_DASH_ALPHA)
	var half := Vector2(0, ONE_WAY_DASH_WIDTH * 0.5)
	var x := 6.0
	while x + ONE_WAY_DASH_LEN < w - 6.0:
		var y0 := h - 2.5 + sin(x / w * PI) * sag * 0.35
		var y1 := h - 2.5 + sin((x + ONE_WAY_DASH_LEN) / w * PI) * sag * 0.35
		var p := Vector2(x, y0)
		var q := Vector2(x + ONE_WAY_DASH_LEN, y1)
		b.quad(p - half, q - half, q + half, p + half, tint)
		x += ONE_WAY_DASH_LEN + ONE_WAY_DASH_GAP
		if TerrainStyle.trace:
			TerrainStyle._tick("점선")


## 장식 겹: 윗면 이끼·잎·꽃·잔가지, 가지 끝 잎 묶음, 덩굴, 아래 매달린 것, 모서리 이끼, 안쪽 구석 거미줄.
func _draw_decor(ci: CanvasItem) -> void:
	var thin: bool = _geo["thin"]
	if not thin and not decorate:
		return
	_ensure_cover()
	var st := _style
	var detailed := TerrainStyle.detail >= 1
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed() + 2
	var b := TerrainStyle.Batch.new()
	var spots: Array = []
	if thin:
		_branch_decor(ci, b, rng, st, detailed, spots)
	else:
		_block_decor(ci, b, rng, st, detailed, spots)
	b.flush(ci)
	if not spots.is_empty() and not _glow_done:
		_glow_done = true
		call_deferred("_add_glow", spots, st)


## 어두운 방이면 버섯 무리 하나가 실제로 빛난다 (그리는 중에는 노드를 더하지 않으려고 미뤄서 부른다).
func _add_glow(spots: Array, st: Dictionary) -> void:
	TerrainStyle.add_glow_light(self, spots, st)


func _branch_decor(ci: CanvasItem, b: TerrainStyle.Batch, rng: RandomNumberGenerator, st: Dictionary, detailed: bool, spots: Array) -> void:
	var w := size.x
	var h := size.y
	var sag: float = _geo["sag"]
	var mc := _moss()
	var ml := _moss_light()
	TerrainStyle.draw_top_decor(b, ci, rng, st, Vector2(6, 0), Vector2(w - 6, 0), mc, ml, detailed, _top_cover, spots)
	if detailed:
		# 가지 끝 잎 묶음 (끝이 다른 지형 속이면 빼기)
		var right_end := Vector2(w + h * 0.42, h * 0.3)
		var left_end := Vector2(-h * 0.42, h * 0.3)
		if not _covered(right_end + Vector2(8, 0)):
			TerrainStyle.draw_leaf_bundle(b, rng, right_end, 1.0, st)
		if not _covered(left_end - Vector2(8, 0)):
			TerrainStyle.draw_leaf_bundle(b, rng, left_end, -1.0, st)
	# 늘어진 덩굴 (잎 달린)
	var vst := _vine_style(st)
	var nb := _bottom_cover.size()
	for i in TerrainStyle.n_of(w, 110.0, "vine") + 1:
		var x := rng.randf_range(20, w - 20)
		var len := rng.randf_range(30, 110)
		var sway := rng.randf_range(-10, 10)
		if nb > 0 and _bottom_cover[clampi(int(x / w * nb), 0, nb - 1)] == 1:
			continue
		TerrainStyle.draw_vine(b, ci, rng, Vector2(x, h + sin(x / w * PI) * sag * 0.3), len, sway, vst, detailed)
	if detailed:
		TerrainStyle.draw_bottom_decor(b, ci, rng, st, _geo["bottom"], w, false, _bottom_cover, mc)


func _block_decor(ci: CanvasItem, b: TerrainStyle.Batch, rng: RandomNumberGenerator, st: Dictionary, detailed: bool, spots: Array) -> void:
	var w := size.x
	var h := size.y
	var mc := _moss()
	var ml := _moss_light()
	TerrainStyle.draw_top_decor(b, ci, rng, st, Vector2(4, 0), Vector2(w - 4, 0), mc, ml, detailed, _top_cover, spots)
	var vst := _vine_style(st)
	# 옆면에 늘어진 덩굴 (벽 느낌) — 옆이 다른 지형에 붙어 있으면 빼기
	if h > 200.0:
		for side in [0.0, w]:
			var dir := 1.0 if side == 0.0 else -1.0
			for i in mini(int(h / 160.0), TerrainStyle.CAP["vine"]):
				var y := rng.randf_range(10, h - 60)
				var len := rng.randf_range(40, 120)
				var sway := dir * rng.randf_range(4, 14)
				if _covered(Vector2(side - dir * 8.0, y + len * 0.5)):
					continue
				if detailed:
					TerrainStyle.draw_vine(b, ci, rng, Vector2(side, y), len, sway, vst, true)
				else:
					ci.draw_line(Vector2(side, y), Vector2(side + sway, y + len), vine_color.lightened(0.1), 2.0, true)
	if not detailed:
		return
	# 윗모서리: 옆면이 드러난 모서리에는 이끼가 걸쳐 늘어지고, 벽과 만나는 안쪽 모서리에는 가끔 거미줄
	if h >= 60.0:
		var beards := float(st["beard_px"]) > 0.0
		for c in [[Vector2(0, 0), -1.0], [Vector2(w, 0), 1.0]]:
			var corner: Vector2 = c[0]
			var out: float = c[1]
			var side_below := _covered(corner + Vector2(out * 8.0, 14.0))
			var side_above := _covered(corner + Vector2(out * 8.0, -14.0))
			if not side_below and not side_above:
				TerrainStyle.draw_corner_drape(b, ci, rng, corner, out, mc, ml, beards)
			elif side_above and not _covered(corner + Vector2(-out * 8.0, -8.0)) and rng.randf() < float(st["web_p"]):
				TerrainStyle.draw_web(ci, corner + Vector2(0, -1), -out, -1.0, rng.randf_range(18.0, 30.0), st)
	if h >= 90.0:
		# 아래로 늘어진 이끼 수염·뿌리 가닥·매달린 돌 (지역에 따라 사슬·방울). 다른 지형에 묻힌 아랫면은 건너뛴다.
		TerrainStyle.draw_bottom_decor(b, ci, rng, st, _geo["bottom"], w, true, _bottom_cover, mc)
		# 아랫모서리가 벽과 만나는 안쪽 구석의 거미줄 (가끔)
		for c in [[Vector2(0, h), -1.0], [Vector2(w, h), 1.0]]:
			var corner: Vector2 = c[0]
			var out: float = c[1]
			if _covered(corner + Vector2(out * 8.0, 16.0)) and not _covered(corner + Vector2(-out * 10.0, 10.0)) and rng.randf() < float(st["web_p"]):
				TerrainStyle.draw_web(ci, corner + Vector2(0, 1), -out, 1.0, rng.randf_range(18.0, 30.0), st)


## 덩굴 색은 방 파일에서 따로 정했으면 그 색을 쓴다 (팔레트 사전을 복사해 vine 만 바꿈).
func _vine_style(st: Dictionary) -> Dictionary:
	if vine_color == st["vine"]:
		return st
	var copy := st.duplicate()
	copy["vine"] = vine_color
	return copy


## 수상한 자리의 온기 빛. 변(여러 개 가능)마다 변의 바깥쪽으로 서서히 사라지는 빛 띠를 그린다.
## 변은 시계 방향으로 준다: 바깥 법선 = (dir.y, -dir.x). (윗면은 왼→오, 아랫면은 오→왼.)
## 더하기 혼합이고 잿빛 셰이더를 거치지 않아, 잿빛 세상에서도 '살아 있는' 희미한 온기로 보인다.
## 자식 노드는 부모 그림 뒤에 그려지므로 이끼 위에 올라가되, 소녀(z 0)보다는 아래다.
class SuspiciousHint extends Node2D:
	var _edges: Array[PackedVector2Array] = []   # 각 변: [시작, 끝]
	var _height := 24.0
	var _tint := Color(1.0, 0.84, 0.55)

	## edges 는 (a, b, a, b, ...) 순서로 이어진 변 목록. 길이 2면 변 하나.
	func setup(points: PackedVector2Array, height: float, tint: Color) -> void:
		_edges.clear()
		var i := 0
		while i + 1 < points.size():
			_edges.append(PackedVector2Array([points[i], points[i + 1]]))
			i += 2
		_height = height
		_tint = tint
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = add
		queue_redraw()

	func _draw() -> void:
		for e in _edges:
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var dir := b - a
			if dir.length() < 1.0:
				continue
			var up := Vector2(dir.y, -dir.x).normalized()   # 변의 바깥쪽 (시계 방향 기준)
			var mid := (a + b) * 0.5
			var lift := up * _height
			var strong := Color(_tint, 0.28)
			var faint := Color(_tint, 0.0)
			# 왼쪽 반: 끝은 투명, 가운데는 진하게. 바깥쪽 꼭짓점은 모두 투명 → 바깥으로 갈수록 사라진다.
			draw_polygon(PackedVector2Array([a + lift, mid + lift, mid + up * -2.0, a + up * -2.0]), PackedColorArray([faint, faint, strong, faint]))
			draw_polygon(PackedVector2Array([mid + lift, b + lift, b + up * -2.0, mid + up * -2.0]), PackedColorArray([faint, faint, faint, strong]))
			# 변을 따라 가는 빛줄: 가운데가 가장 밝다
			draw_line(a.lerp(b, 0.15) + up * 1.0, mid + up * 1.0, Color(_tint, 0.18), 1.5, true)
			draw_line(mid + up * 1.0, a.lerp(b, 0.85) + up * 1.0, Color(_tint, 0.18), 1.5, true)

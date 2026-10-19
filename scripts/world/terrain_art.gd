class_name TerrainArt
extends Node2D
## 그림 조각 지형의 겉모습 (설명서: TERRAIN.md). 발판(Platform)·경사(TerrainPolygon)·가시(Thorns)의 자식으로 붙어
## 지역 그림 옷(TerrainSkin)의 조각을 이어 붙여 그린다. **충돌은 건드리지 않는다** — 겉모습만.
##
## 만들기는 방에 들어올 때 한 번(build_*)이고, 그림은 RenderingServer 삼각형 배열 몇 개로 보낸다
## (몸통 결 / 세로 결 / 조각 atlas / 색만 — 노드 하나에 그리기 호출 최대 4번, 매 프레임 다시 그리지 않는다).
## 조각 선택은 자리(전역 좌표)로 씨앗을 정해 방마다 늘 같은 모양이다.
##
## 맞추기 약속:
##  - 걷는 조각(branch·slab·ground)은 tools/terrain_cut.gd 가 잰 '발 딛는 선'(top)을 펴서 충돌 윗면 y 에 놓는다
##    (skin.lift 만큼 위 — 잎 사이에 발이 살짝 묻힌다). 그래서 소녀는 늘 그림 위에 서 있고, 떠 보이지 않는다.
##  - 얇은 발판: 걷는 구간이 발판 폭에 맞게 한 조각을 고르고(크기 0.85~1.2배, 가로 늘이기 ±15% 안),
##    안 맞으면 같은 가지에서 왼끝 + 가운데 여러 토막 + 오른끝을 이어 붙인다(이음매는 40px 동안 서서히 겹침).
##  - 큰 덩어리: 몸통 결(이음매 없는 무늬, 전역 좌표 UV → 이웃 덩어리와 결이 이어짐)을 깔고 깊을수록 어둡게,
##    드러난 윗면에 ground 띠, 드러난 아랫면에 매단 장식, 드러난 옆면은 가장자리를 어둡게.
##  - '드러남'은 옆 지형(neighbors — 부서지는 벽은 뺀다)과 방 경계로 판단한다 (덮인 곳·방 밖에는 장식 없음).
##  - 드러난 충돌 끝(절벽 끝·가지 끝) 밖으로는 그림이 발 높이에 CLIP_START px 남짓만 남는다 (piece 의 clip_l/clip_r):
##    조각의 걷는 구간 밖(둥근 끝·늘어진 뿌리)은 비스듬한 선 위쪽을 지워, 서지 못하는 자리가 발판처럼 보이지 않게 한다.
##  - 그리는 순서: 뒤 그림자(조각 실루엣의 흐린 어두운 테 — 앞뒤 가르기)와 몸통 결(가로·세로)은 부모 묶음(보통 Terrain) 맨 아래 겹에 따로 그린다 (_make_group_items).
##    그래서 나중 형제의 몸통이 앞 형제의 끝 조각·뿌리를 덮어 세로로 잘린 자국이 생기지 않는다 (모든 몸통 → 모든 조각).

## 시험용 누적: 만드는 데 든 시간(µs)·만든 수·삼각형 수
static var build_usec := 0
static var build_count := 0
static var tri_count := 0

const BUF_FILL := 0
const BUF_FILL_V := 1
const BUF_ATLAS := 2
const BUF_PLAIN := 3
## 덩어리 몸통 결 격자 칸 (px)
const CELL := 96.0
## 드러남 표본 간격 / 바깥으로 떨어진 거리
const SAMPLE := 12.0
const OUT := 8.0
## 이어 붙이는 겹침 (월드 px)
const OVERLAP := 40.0
## 덮인 쪽으로 밀어 넣는 길이 (이웃 지형 속으로 숨김)
const TUCK := 28.0
## 얇은 발판 한 조각 맞추기 범위
const U_MIN := 0.85
const U_MAX := 1.2
const SX_MAX := 1.15
## 한쪽 방향 발판 단서 (밑변을 따라 끊어진 빛 점선) — 옛 Platform 과 같은 값
const DASH_LEN := 10.0
const DASH_GAP := 12.0
const DASH_ALPHA := 0.55
const DASH_W := 2.0
## 드러난 충돌 끝 밖 자르기: 끝에서 CLIP_START px 밖에서 발 높이를 지나는 비스듬한 선(바깥으로 갈수록 CLIP_SLOPE 배로
## 내려감) 위쪽 그림을 CLIP_SOFT px 동안 서서히 지운다 → 발 높이에는 끝 밖으로 20px 남짓만 남고, 처진 뿌리·덩굴만 보인다.
const CLIP_START := 22.0
const CLIP_SLOPE := 1.4
const CLIP_SOFT := 18.0
## 이웃 지형에 덮인 끝: 가지는 이만큼 이웃 속으로 서서히 사라지고, 벽에 닿은 바닥 띠는 이만큼만 들어간다
const WALL_TUCK := 8.0
## 몸통 결·뒤 그림자를 부모 묶음 맨 아래에 그릴 때의 그리기 순서 (노드 자식들은 0 이상 — 그보다 먼저; 그림자가 가장 먼저)
const FILL_DRAW_INDEX := -100000
const SHADOW_DRAW_INDEX := -200000
const SHADOW_MAT := preload("res://shaders/terrain_shadow.tres")

var skin: TerrainSkin
var host: Node2D
var _bufs: Array = []
var _rng := RandomNumberGenerator.new()
var _shapes: Array = []
var _own_poly := PackedVector2Array()
var _room_box := Rect2()      # 방 경계 + 40 (몸통 결은 여기까지 깐다 — 화면 끝에 빈틈이 안 보이게)
var _room_exact := Rect2()    # 방 경계 그대로 (장식은 이 안만)
var _has_room := false
var _mod := Color(1, 1, 1, 1)
## 몸통 결을 따로 그리는 캔버스 항목 (부모 묶음 맨 아래 겹). 비어 있으면 이 노드의 _draw 가 몸통 결도 그린다.
var _fill_ci := RID()
## 뒤 그림자 항목 (부모 묶음 가장 아래 겹 — 앞뒤 가르기). cast_shadow 를 끄면 안 만든다 (웅덩이 물 그림 등).
var _shadow_ci := RID()
var cast_shadow := true
var _clip_phase := 0.0
var _layer_fill := false
## 한 조각으로 맞춘 가지의 선택 (가까이 쌓인 같은 크기 발판이 똑같은 그림이 되지 않게 이웃이 본다)
var pick := ""
var pick_flip := false
var pick_w := 0.0
## 어두운 방의 작은 빛: 지역 설명에 params.glow 가 있고 어두운 방이면, 놓인 조각의 빛나는 자리(pieces.json 의 glow — 수정·버섯·등불)를 모은다.
## 다 만든 뒤 옛 코드 지형의 '버섯 빛'과 같은 규칙(TerrainStyle.add_glow_light: 노드 하나에 하나, 방 하나에 8개까지)으로 빛을 단다.
var _glow_on := false
var _glow_spots := PackedVector2Array()


func _init(s: TerrainSkin = null, h: Node2D = null) -> void:
	skin = s
	host = h
	name = "Art"
	use_parent_material = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for i in 4:
		_bufs.append({"pts": PackedVector2Array(), "uvs": PackedVector2Array(), "cols": PackedColorArray(), "idx": PackedInt32Array()})


func _draw() -> void:
	var ci := get_canvas_item()
	for i in 4:
		if (i == BUF_FILL or i == BUF_FILL_V) and _fill_ci.is_valid():
			continue   # 몸통 결은 부모 묶음 맨 아래 겹에서 그린다
		_add_buf(ci, i)


func _add_buf(ci: RID, i: int) -> void:
	var b: Dictionary = _bufs[i]
	var pts: PackedVector2Array = b["pts"]
	if pts.size() < 3:
		return
	var tex := RID()
	match i:
		BUF_FILL:
			if skin.fill: tex = skin.fill.get_rid()
		BUF_FILL_V:
			if skin.fill_v: tex = skin.fill_v.get_rid()
			elif skin.fill: tex = skin.fill.get_rid()
		BUF_ATLAS:
			tex = skin.atlas.get_rid()
	if i == BUF_PLAIN:
		RenderingServer.canvas_item_add_triangle_array(ci, b["idx"], pts, b["cols"])
	else:
		RenderingServer.canvas_item_add_triangle_array(ci, b["idx"], pts, b["cols"], b["uvs"], PackedInt32Array(), PackedFloat32Array(), tex)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			if _layer_fill and not _fill_ci.is_valid() and not _shadow_ci.is_valid():
				_make_group_items()
		NOTIFICATION_EXIT_TREE, NOTIFICATION_PREDELETE:
			_free_group_items()
		NOTIFICATION_VISIBILITY_CHANGED:
			for ci in [_fill_ci, _shadow_ci]:
				if ci.is_valid():
					RenderingServer.canvas_item_set_visible(ci, is_visible_in_tree())
		NOTIFICATION_TRANSFORM_CHANGED:
			_place_group_items()


## 부모 묶음(보통 Terrain) 맨 아래 겹에 그리는 두 항목 — 노드를 새로 붙이지 않고 RenderingServer 캔버스 항목을 둔다 (방 _ready 중에도 붙일 수 있고, 가볍다):
##  - 뒤 그림자 (SHADOW_DRAW_INDEX — 가장 먼저): 조각(atlas)을 그림자 재질(terrain_shadow)로 한 번 더 — 실루엣보다 조금 넓은 어두운 테 (앞뒤 가르기, TERRAIN.md 5장)
##  - 몸통 결 (FILL_DRAW_INDEX): 가로·세로 결 — 형제 지형의 끝 조각·뿌리를 나중 형제의 몸통이 덮어 세로로 잘린 자국이 생기지 않게 (모든 몸통 → 모든 조각 순서)
func _make_group_items() -> void:
	_free_group_items()
	if host == null or not is_inside_tree() or not (host.get_parent() is CanvasItem):
		return
	if (_bufs[BUF_FILL]["idx"] as PackedInt32Array).size() >= 3 or (_bufs[BUF_FILL_V]["idx"] as PackedInt32Array).size() >= 3:
		_fill_ci = _group_item(FILL_DRAW_INDEX, host.material)
		_add_buf(_fill_ci, BUF_FILL)
		_add_buf(_fill_ci, BUF_FILL_V)
	if cast_shadow and (_bufs[BUF_ATLAS]["idx"] as PackedInt32Array).size() >= 3:
		_shadow_ci = _group_item(SHADOW_DRAW_INDEX, SHADOW_MAT)
		_add_buf(_shadow_ci, BUF_ATLAS)
	if _fill_ci.is_valid() or _shadow_ci.is_valid():
		_place_group_items()
		set_notify_transform(true)


func _group_item(draw_index: int, mat: Material) -> RID:
	var rs := RenderingServer
	var ci := rs.canvas_item_create()
	rs.canvas_item_set_parent(ci, (host.get_parent() as CanvasItem).get_canvas_item())
	rs.canvas_item_set_draw_index(ci, draw_index + host.get_index())
	if mat:
		rs.canvas_item_set_material(ci, mat.get_rid())
	rs.canvas_item_set_default_texture_filter(ci, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	rs.canvas_item_set_default_texture_repeat(ci, RenderingServer.CANVAS_ITEM_TEXTURE_REPEAT_ENABLED)
	rs.canvas_item_set_visible(ci, is_visible_in_tree())
	return ci


func _place_group_items() -> void:
	if host == null or not is_inside_tree() or not (host.get_parent() is CanvasItem):
		return
	var xf := (host.get_parent() as CanvasItem).get_global_transform().affine_inverse() * get_global_transform()
	for ci in [_fill_ci, _shadow_ci]:
		if ci.is_valid():
			RenderingServer.canvas_item_set_transform(ci, xf)


func _free_group_items() -> void:
	for ci in [_fill_ci, _shadow_ci]:
		if ci.is_valid():
			RenderingServer.free_rid(ci)
	_fill_ci = RID()
	_shadow_ci = RID()


## 시험용: 뒤 그림자를 그리는가
func has_shadow() -> bool:
	return _shadow_ci.is_valid()


## 시험용: 몸통 결이 부모 묶음 맨 아래 겹에 그려지는가 (몸통 결이 없으면 true)
func fill_in_layer() -> bool:
	if (_bufs[BUF_FILL]["idx"] as PackedInt32Array).size() < 3 and (_bufs[BUF_FILL_V]["idx"] as PackedInt32Array).size() < 3:
		return true
	return _fill_ci.is_valid()


func triangle_count() -> int:
	var n := 0
	for b in _bufs:
		n += (b["idx"] as PackedInt32Array).size() / 3
	return n


# ---------------------------------------------------------------- 공통 준비
func _begin(seed_extra: int) -> void:
	_rng.seed = int(host.global_position.x * 7.0 + host.global_position.y * 13.0) + seed_extra
	_clip_phase = fmod(host.global_position.x * 0.013 + host.global_position.y * 0.007, TAU)
	_glow_on = (skin.data.get("params", {}) as Dictionary).has("glow") and TerrainStyle.is_dark(host)
	_glow_spots = PackedVector2Array()
	var room := TerrainStyle.room_of(host)
	_mod = skin.tint_for(room)
	_has_room = room != null and "bounds" in room
	if _has_room:
		var b: Rect2 = room.get("bounds")
		_room_exact = Rect2(b.position - host.global_position + (room as Node2D).global_position, b.size)
		_room_box = _room_exact.grow(40.0)


func _finish(t0: int) -> void:
	_layer_fill = true
	_make_group_items()
	if _glow_on and not _glow_spots.is_empty():
		var gc: Array = skin.param("glow", "color", [1.0, 0.8, 0.55])
		TerrainStyle.add_glow_light.call_deferred(host, Array(_glow_spots), {"mushroom_glow": Color(float(gc[0]), float(gc[1]), float(gc[2]))})
	build_usec += Time.get_ticks_usec() - t0
	build_count += 1
	tri_count += triangle_count()
	queue_redraw()


## 옆 지형 모양 (TerrainStyle.neighbor_shapes 와 같지만 부서지는 벽은 뺀다 — 부서진 뒤에도 그 뒤 땅의 띠·장식이 이어져 있게).
static func neighbors(node: Node2D, local_box: Rect2) -> Array:
	var out := []
	var parent := node.get_parent()
	if parent == null:
		return out
	var box := local_box.grow(24.0)
	for s in parent.get_children():
		if s == node or not (s is Node2D) or "secret_id" in s:   # 부서지는 벽(SecretWall·CrackedWall)은 뺀다
			continue
		var off: Vector2 = (s as Node2D).global_position - node.global_position
		if s is Platform:
			var r := Rect2(off, s.size)
			if r.intersects(box):
				out.append(r)
		elif s is TerrainPolygon:
			var poly: PackedVector2Array = Transform2D(0.0, off) * (s.polygon as PackedVector2Array)
			if poly.size() < 3:
				continue
			var pb := Rect2(poly[0], Vector2.ZERO)
			for p in poly:
				pb = pb.expand(p)
			if pb.intersects(box):
				out.append(poly)
	return out


## 그 자리가 다른 지형에 덮였거나 방 밖인가 (장식을 그리지 않을 곳)
func _covered(p: Vector2) -> bool:
	if _has_room and not _room_exact.has_point(p):
		return true
	if not _own_poly.is_empty() and Geometry2D.is_point_in_polygon(p, _own_poly):
		return true
	return TerrainStyle.is_covered(_shapes, p)


## 변 a→b(시계 방향, 바깥 = (dir.y, -dir.x))에서 바깥쪽이 드러난 구간들 [[t0, t1], …] (t 는 0~1)
func _exposed_runs(a: Vector2, b: Vector2) -> Array:
	var d := b - a
	var len := d.length()
	if len < 1.0:
		return []
	var nrm := Vector2(d.y, -d.x) / len
	var n := maxi(1, int(len / SAMPLE))
	var runs: Array = []
	var start := -1.0
	for i in n + 1:
		var t := (i + 0.5) / (n + 1)
		var free := not _covered(a.lerp(b, t) + nrm * OUT)
		if free and start < 0.0:
			start = float(i) / (n + 1)
		elif not free and start >= 0.0:
			runs.append([start, float(i) / (n + 1)])
			start = -1.0
	if start >= 0.0:
		runs.append([start, 1.0])
	# 아주 짧은 조각(표본 하나)은 버린다
	var out: Array = []
	for r in runs:
		if (r[1] - r[0]) * len >= SAMPLE * 1.5:
			out.append(r)
	return out


# ---------------------------------------------------------------- 메쉬 쌓기
## 버퍼 꺼내기: 사전에서 빼 두고(참조가 하나뿐이어야 append 가 통째 복사하지 않는다) 다 쓰면 _put 으로 돌려놓는다.
func _take(buf: int) -> Array:
	var b: Dictionary = _bufs[buf]
	var out := [b["pts"], b["uvs"], b["cols"], b["idx"]]
	b["pts"] = PackedVector2Array()
	b["uvs"] = PackedVector2Array()
	b["cols"] = PackedColorArray()
	b["idx"] = PackedInt32Array()
	return out


func _put(buf: int, arrs: Array) -> void:
	var b: Dictionary = _bufs[buf]
	b["pts"] = arrs[0]
	b["uvs"] = arrs[1]
	b["cols"] = arrs[2]
	b["idx"] = arrs[3]


func _tris(buf: int, pts_in: PackedVector2Array, uvs_in: PackedVector2Array, cols_in: PackedColorArray, idx_in: PackedInt32Array) -> void:
	var arrs := _take(buf)
	var pts: PackedVector2Array = arrs[0]
	var uvs: PackedVector2Array = arrs[1]
	var cols: PackedColorArray = arrs[2]
	var idx: PackedInt32Array = arrs[3]
	arrs.clear()
	var base := pts.size()
	pts.append_array(pts_in)
	uvs.append_array(uvs_in)
	cols.append_array(cols_in)
	for i in idx_in:
		idx.append(base + i)
	_put(buf, [pts, uvs, cols, idx])


## 조각 하나를 휘어서 놓는다.
##  name: 조각 / u0..u1: 조각 안 가로 구간(원래 px) / x0..x1: 놓을 가로 자리(노드 기준, x0 < x1)
##  y_at: 그 x 에서 발 딛는 선이 놓일 높이 (Callable(x) → y; 경사면은 기울어진 선)
##  sy: 세로 배율 / flip: 좌우 뒤집기
##  opts: fade_l, fade_r (놓인 px 동안 서서히 나타남/사라짐), band (발 선 아래 몇 원래 px 까지만), band_fade,
##        warp (기본 true: 윗선을 편다), mod (색), y_off (조각을 발 선 기준 대신 조각 맨 위 기준으로: 매단 장식용),
##        clip_l, clip_r (드러난 충돌 끝 x — 그 밖의 그림은 비스듬히 지운다: CLIP_START 참고),
##        top_alpha (맨 위 알파 배수 — 아래로 갈수록 1 까지(band 가 있으면 band 시작까지) 이어진다: 웅덩이 몸통처럼 깊을수록 진하게)
func piece(name: String, u0: float, u1: float, x0: float, x1: float, y_at: Callable, sy: float, flip := false, opts := {}) -> void:
	if not skin.pieces.has(name) or u1 - u0 < 1.0 or x1 - x0 < 1.0:
		return
	var r := skin.rect_of(name)
	var size := skin.size_of(name)
	var warp: bool = opts.get("warp", true)
	var hang: bool = opts.has("y_off")
	var walk_y := float(skin.pieces[name].get("walk_y", 0.0))
	var lift: float = opts.get("lift", skin.lift)
	var band: float = opts.get("band", -1.0)
	var band_fade: float = opts.get("band_fade", 40.0)
	var fade_l: float = opts.get("fade_l", 0.0)
	var fade_r: float = opts.get("fade_r", 0.0)
	var mod: Color = opts.get("mod", _mod)
	var clip_l: float = opts.get("clip_l", -INF)
	var clip_r: float = opts.get("clip_r", INF)
	var step := float(skin.step)
	# 세로 줄: 0, (band 가 있으면 band 시작, band 끝), 아래 끝
	var kx := (x1 - x0) / (u1 - u0)
	var us: Array = []
	var u := u0
	while u < u1:
		us.append(u)
		u = (floor(u / step) + 1.0) * step
	us.append(u1)
	var ncol := us.size()
	# 충돌 끝 밖 자르기가 이 조각에 닿는가 (가장 가까운 열에서도 자르는 선이 조각 맨 위보다 위면 자를 것 없음)
	var clip := false
	if not hang and (clip_l > -INF or clip_r < INF):
		var dmax := maxf(clip_l - x0, x1 - clip_r)
		clip = (dmax - CLIP_START) * CLIP_SLOPE + CLIP_SOFT + lift + 6.0 > -size.y * sy   # 6 = 물결 폭
	var has_band := band >= 0.0
	# 열마다 세로 줄 수: 위·아래 (+ band 끝) (+ 자르는 선 하나 — 자르는 선과 그 아래 CLIP_SOFT 가 위 끝을 대신한다)
	var nrow := (3 if has_band else 2) + (1 if clip else 0)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	pts.resize(ncol * nrow)
	uvs.resize(ncol * nrow)
	cols.resize(ncol * nrow)
	var vs := PackedFloat32Array()
	var al := PackedFloat32Array()
	vs.resize(nrow)
	al.resize(nrow)
	var soft_v := CLIP_SOFT / maxf(sy, 0.001)
	for ci in ncol:
		var su: float = us[ci]
		var x := x0 + (su - u0) * kx
		if flip:
			x = x1 - (su - u0) * kx
		var line := walk_y
		if warp and not hang:
			line = skin.top_at(name, su)
		var base_y: float = y_at.call(x)
		# fade_l / fade_r 은 놓인 자리(화면)의 왼쪽·오른쪽 끝 기준이다 (뒤집기와 상관없이)
		var a := 1.0
		var xl := x - x0
		var xr := x1 - x
		if fade_l > 0.0:
			a *= smoothstep(0.0, fade_l, xl)
		if fade_r > 0.0:
			a *= smoothstep(0.0, fade_r, xr)
		# 이 열의 세로 줄 (조각 안 v, 알파)
		var b1 := size.y
		var b2 := size.y
		if has_band:
			b1 = minf(line + band, size.y)
			b2 = minf(line + band + band_fade, size.y)
		if clip:
			# 자르는 선 vc (조각 안 v): 충돌 끝에서 CLIP_START px 밖에서 발 높이를 지나 바깥으로 갈수록 내려간다
			var d := maxf(clip_l - x, x - clip_r)
			# 자로 그은 듯한 곧은 선이 보이지 않게 조금 물결지게 (±6px)
			var wob := 4.0 * sin(x * 0.11 + _clip_phase) + 2.0 * sin(x * 0.29 + _clip_phase * 1.7)
			var vc := line + ((d - CLIP_START) * CLIP_SLOPE + wob) / maxf(sy, 0.001)
			var vend := b2
			var r0 := clampf(vc, 0.0, vend)
			var r1 := clampf(vc + soft_v, r0, vend)
			vs[0] = r0
			vs[1] = r1
			if has_band:
				vs[2] = maxf(b1, r1)
				vs[3] = maxf(b2, vs[2])
			else:
				vs[2] = maxf(size.y, r1)
			for ri in nrow:
				al[ri] = _band_alpha(vs[ri], b1, b2, has_band) * clampf((vs[ri] - vc) / soft_v, 0.0, 1.0)
		else:
			vs[0] = 0.0
			al[0] = 1.0
			if has_band:
				vs[1] = b1
				al[1] = 1.0
				vs[2] = b2
				al[2] = 0.0
			else:
				vs[1] = size.y
				al[1] = 1.0
		if opts.has("top_alpha"):
			var ta: float = opts["top_alpha"]
			for ri in nrow:
				al[ri] *= lerpf(ta, 1.0, clampf(vs[ri] / maxf(b1, 1.0), 0.0, 1.0))
		var uvx := (r.position.x + su) / skin.atlas_size.x
		for ri in nrow:
			var v: float = vs[ri]
			var y: float
			if hang:
				y = base_y + float(opts["y_off"]) + v * sy
			else:
				y = base_y - lift + (v - line) * sy
			var k := ci * nrow + ri
			pts[k] = Vector2(x, y)
			uvs[k] = Vector2(uvx, (r.position.y + v) / skin.atlas_size.y)
			cols[k] = Color(mod.r, mod.g, mod.b, mod.a * a * al[ri])
	if _glow_on and skin.pieces[name].has("glow"):
		_collect_glow(name, u0, u1, x0, x1, kx, y_at, sy, flip, warp, hang, opts, walk_y, lift, clip_l, clip_r, fade_l, fade_r)
	var idx := PackedInt32Array()
	idx.resize((ncol - 1) * (nrow - 1) * 6)
	var w := 0
	for ci in ncol - 1:
		for ri in nrow - 1:
			var p := ci * nrow + ri
			var q := p + nrow
			idx[w] = p; idx[w + 1] = p + 1; idx[w + 2] = q
			idx[w + 3] = p + 1; idx[w + 4] = q + 1; idx[w + 5] = q
			w += 6
	_tris(BUF_ATLAS, pts, uvs, cols, idx)


## 놓인 조각의 빛나는 자리(조각 px)를 노드 좌표로 옮겨 모은다 (어두운 방의 작은 빛). 잘리거나 사라지는 자리·band 아래는 뺀다.
func _collect_glow(name: String, u0: float, u1: float, x0: float, x1: float, kx: float, y_at: Callable, sy: float, flip: bool, warp: bool, hang: bool, opts: Dictionary, walk_y: float, lift: float, clip_l: float, clip_r: float, fade_l: float, fade_r: float) -> void:
	var band: float = opts.get("band", -1.0)
	for g in skin.pieces[name]["glow"]:
		var gu := float(g[0])
		var gv := float(g[1])
		if gu < u0 or gu > u1:
			continue
		var x := x0 + (gu - u0) * kx
		if flip:
			x = x1 - (gu - u0) * kx
		if x < clip_l - 4.0 or x > clip_r + 4.0 or (fade_l > 0.0 and x - x0 < fade_l) or (fade_r > 0.0 and x1 - x < fade_r):
			continue
		var line := walk_y
		if warp and not hang:
			line = skin.top_at(name, gu)
		if band >= 0.0 and gv > line + band:
			continue
		var by: float = y_at.call(x)
		var y := (by + float(opts["y_off"]) + gv * sy) if hang else (by - lift + (gv - line) * sy)
		_glow_spots.append(Vector2(x, y))


## band 아래로 서서히 사라지는 알파 (band 가 없으면 1)
static func _band_alpha(v: float, b1: float, b2: float, has_band: bool) -> float:
	if not has_band:
		return 1.0
	if b2 - b1 < 0.001:
		return 1.0 if v <= b1 + 0.001 else 0.0
	return 1.0 - clampf((v - b1) / (b2 - b1), 0.0, 1.0)


## 몸통 결로 다각형을 채운다 (격자 칸으로 잘라 삼각형). shade(p) → 밝기(0~1). vertical: 세로 결.
func fill_polygon(poly: PackedVector2Array, vertical: bool, shade: Callable) -> void:
	if poly.size() < 3 or (skin.fill == null and skin.fill_v == null):
		return
	var tex: Texture2D = skin.fill_v if vertical and skin.fill_v else skin.fill
	var ts := tex.get_size() * skin.scale
	var bb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	if _has_room:
		bb = bb.intersection(_room_box)
		if bb.size.x <= 0.0 or bb.size.y <= 0.0:
			return
	var gpos := host.global_position
	var is_rect := _is_axis_rect(poly)
	var y: float = floor(bb.position.y / CELL) * CELL
	while y < bb.end.y:
		var x: float = floor(bb.position.x / CELL) * CELL
		while x < bb.end.x:
			var cell := Rect2(x, y, CELL, CELL).intersection(bb)
			if cell.size.x > 0.5 and cell.size.y > 0.5:
				var pieces_: Array = []
				var cp := PackedVector2Array([cell.position, Vector2(cell.end.x, cell.position.y), cell.end, Vector2(cell.position.x, cell.end.y)])
				if is_rect:
					pieces_ = [cp]
				else:
					pieces_ = Geometry2D.intersect_polygons(cp, poly)
				for pc in pieces_:
					var pp: PackedVector2Array = pc
					if pp.size() < 3:
						continue
					var idx := Geometry2D.triangulate_polygon(pp)
					if idx.is_empty():
						continue
					var uvs := PackedVector2Array()
					var cols := PackedColorArray()
					for p in pp:
						var g := p + gpos
						uvs.append(g / ts)
						var s: float = shade.call(p)
						cols.append(Color(_mod.r * s, _mod.g * s, _mod.b * s, 1.0))
					_tris(BUF_FILL_V if vertical else BUF_FILL, pp, uvs, cols, idx)
			x += CELL
		y += CELL


static func _is_axis_rect(poly: PackedVector2Array) -> bool:
	if poly.size() != 4:
		return false
	for i in 4:
		var d := poly[(i + 1) % 4] - poly[i]
		if absf(d.x) > 0.01 and absf(d.y) > 0.01:
			return false
	return true


## 색만 있는 사각형 (빛 점선 등)
func plain_quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	_tris(BUF_PLAIN, PackedVector2Array([a, b, c, d]), PackedVector2Array(), PackedColorArray([col, col, col, col]), PackedInt32Array([0, 1, 2, 0, 2, 3]))


# ---------------------------------------------------------------- 발판 (Platform)
## 발판: 얇으면 가지·판, 아니면 덩어리.
func build_platform(p: Node2D, size: Vector2, thin: bool, one_way: bool, decorate: bool, suspicious := false) -> void:
	var t0 := Time.get_ticks_usec()
	_begin(int(size.x) * 3 + int(size.y))
	_shapes = neighbors(p, Rect2(Vector2(-400, -300), size + Vector2(800, 700)))
	if suspicious:
		_mod = _mod.lerp(Color(1.0, 0.98, 0.92), 0.22)
	if thin:
		var left_free := not _covered(Vector2(-OUT, size.y * 0.5)) and not _covered(Vector2(-OUT, 2.0))
		var right_free := not _covered(Vector2(size.x + OUT, size.y * 0.5)) and not _covered(Vector2(size.x + OUT, 2.0))
		var flat := func(_x: float) -> float: return 0.0
		branch_run(0.0, size.x, flat, left_free, right_free, one_way, size.y, not left_free, not right_free)
		if one_way:
			_dashes(size.x, size.y)
	else:
		var poly := PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)])
		_own_poly = PackedVector2Array()
		build_mass(poly, decorate, size.y > size.x * 1.6)
		if one_way:
			_dashes(size.x, size.y)
	_finish(t0)


## 한쪽 방향 단서: 밑변 바로 안쪽의 끊어진 빛 점선 (옛 발판과 같은 자리·간격; 그림 위에 얹힌다)
func _dashes(w: float, h: float) -> void:
	var col := Color(1.0, 0.92, 0.7, DASH_ALPHA)
	var half := Vector2(0, DASH_W * 0.5)
	var x := 6.0
	while x + DASH_LEN < w - 6.0:
		var p := Vector2(x, h - 2.5)
		var q := Vector2(x + DASH_LEN, h - 2.5)
		plain_quad(p - half, q - half, q + half, p + half, col)
		x += DASH_LEN + DASH_GAP


## 가지 한 줄 (얇은 발판·얇은 경사): xa..xb 에 발 딛는 선 y_at. 끝이 덮였으면(이웃 지형) 그쪽 끝을 이웃 속으로 밀어 넣는다.
## tuck_l/tuck_r: 그 끝이 이웃 지형에 덮였다 (가지가 이웃 속으로 TUCK px 동안 서서히 사라진다 — 같은 다각형의 꺾임은 false).
## 드러난 끝(left_free/right_free) 밖의 그림은 발 높이에서 잘라 낸다 (clip_l/clip_r).
func branch_run(xa: float, xb: float, y_at: Callable, left_free: bool, right_free: bool, one_way: bool, thick: float, tuck_l := false, tuck_r := false) -> void:
	var w := xb - xa
	if w < 4.0:
		return
	var use_slab: bool = one_way and left_free and right_free and skin.has_role("slab") and w <= float(skin.param("slab", "max_w", 360.0))
	var role := "slab" if use_slab else "branch"
	if not skin.has_role(role):
		role = "branch" if skin.has_role("branch") else "slab"
		if not skin.has_role(role):
			return
	# log 역할(덧붙인 역할 — 지역에 있을 때만): 한쪽 방향이 아닌 얇은 발판(벽장 바닥·넓은 단)은 굵은 통나무로 —
	# 한쪽 방향 발판은 가는 가지로 남아 '아래에서 뛰어 오를 수 있는 곳'과 구분된다. 없는 지역(수관 등)은 그대로.
	var solid_log: bool = not one_way and skin.has_role("log")
	if solid_log:
		role = "log"
	var avoid := _stacked_picks(w)
	var names := skin.list(role)
	# 방 파일에서 이 발판의 조각을 정해 둘 수 있다 (노드 metadata "terrain_piece" = 조각 이름 — 예: 마을의 흔들다리).
	# 한 조각으로 맞으면 그것, 아니면 그 조각으로 이어 붙인다. 충돌은 그대로 (그림만 고른다).
	var forced := str(host.get_meta("terrain_piece", "")) if host != null and host.has_meta("terrain_piece") else ""
	if forced != "" and skin.pieces.has(forced):
		names = [forced]
		avoid = []
	else:
		forced = ""
	# 끝이 이웃에 덮인 발판도 한 조각으로 맞출지 (params.<역할>.fit_tucked — 기본 false: 이어 붙이기).
	# 켜면 덮인 끝 밖의 그림(둥근 끝·기둥)은 이웃 속에서 서서히 사라진다 (흔들다리처럼 이어 붙이면 어색한 조각용).
	var fit_tucked: bool = forced == "" and (not left_free or not right_free) and bool(skin.param(role, "fit_tucked", false))
	if (left_free and right_free) or fit_tucked:
		var fit := _fit_single(names, w, thick, avoid)
		if not fit.is_empty():
			_place_single(fit, xa, xb, y_at, left_free, right_free)
			pick_w = w
			return
	# 이어 붙이기: 정한 조각 / 통나무 / (판이 안 맞으면) 가지
	if forced == "" and not solid_log and skin.has_role("branch"):
		names = skin.list("branch")
	_chain(names, xa, xb, y_at, left_free, right_free, thick, tuck_l, tuck_r, avoid)
	pick_w = w


## 한 조각으로 맞춘 가지를 놓는다 (fit = _fit_single 의 결과). 걷는 구간이 xa..xb 에 오고, 드러난 끝 밖은 발 높이에서 자르고,
## 이웃에 덮인 끝(fit_tucked)은 이웃 속에서 서서히 사라진다.
func _place_single(fit: Dictionary, xa: float, xb: float, y_at: Callable, left_free: bool, right_free: bool) -> void:
	var name: String = fit["name"]
	var k: float = fit["k"]
	var walk := skin.walk_of(name)
	var size := skin.size_of(name)
	var flip: bool = fit["flip"]
	var x0 := xa - walk.x * k
	var x1 := xa + (size.x - walk.x) * k
	if flip:
		x0 = xb - (size.x - walk.x) * k
		x1 = xb + walk.x * k
	var opts := {}
	if left_free:
		opts["clip_l"] = xa
	else:
		opts["fade_l"] = maxf(xa - x0, 0.0) + TUCK
	if right_free:
		opts["clip_r"] = xb
	else:
		opts["fade_r"] = maxf(x1 - xb, 0.0) + TUCK
	piece(name, 0.0, size.x, x0, x1, y_at, fit["u"] * skin.scale, flip, opts)
	pick = name
	pick_flip = flip


## 가까이 쌓인 같은 크기의 발판(먼저 만든 형제)이 고른 [조각, 뒤집기] — 같은 그림이 되풀이돼 보이지 않게 피한다.
func _stacked_picks(w: float) -> Array:
	var out := []
	var parent := host.get_parent() if host else null
	if parent == null:
		return out
	var gp := host.global_position
	for s in parent.get_children():
		if s == host:
			break   # 앞 순서(이미 만든 것)만
		if not (s is Node2D):
			continue
		var art = s.get("_art")
		if not (art is TerrainArt) or art.pick == "":
			continue
		var d: Vector2 = (s as Node2D).global_position - gp
		if absf(d.x) < 200.0 and absf(d.y) < 900.0 and absf(art.pick_w - w) < w * 0.25:
			out.append([art.pick, art.pick_flip])
	return out


## 한 조각으로 맞출 수 있으면 {name, k(가로 배율), u(크기 배율), flip}. 늘이기가 적은 것을 고르고, 비슷하면 무작위.
## avoid: 가까운 이웃이 고른 [조각, 뒤집기] — 다른 조각을 조금 더 좋게 보고, 같은 조각이면 반대로 뒤집는다.
func _fit_single(names: Array, w: float, thick: float, avoid := []) -> Dictionary:
	var best := {}
	var best_cost := INF
	var avoid_names := {}
	for av in avoid:
		avoid_names[av[0]] = av[1]
	for n in names:
		var walk := skin.walk_of(n)
		var span := (walk.y - walk.x) * skin.scale
		if span < 10.0:
			continue
		var depth := float(skin.pieces[n].get("depth", 0.0)) * skin.scale
		var umin := U_MIN
		if depth > 1.0:
			umin = clampf(thick * 0.9 / depth, U_MIN, U_MAX)
		var f := w / span
		var u := clampf(f, umin, U_MAX)
		var sx := f / u
		if sx > SX_MAX or sx < 1.0 / SX_MAX:
			continue
		var cost := absf(log(sx)) * 3.0 + absf(log(u)) + _rng.randf() * 0.25
		if avoid_names.has(n):
			cost += 0.6
		if cost < best_cost:
			best_cost = cost
			best = {"name": n, "k": f * skin.scale, "u": u, "flip": _rng.randf() < 0.5}
	if not best.is_empty() and avoid_names.has(best["name"]):
		best["flip"] = not bool(avoid_names[best["name"]])
	return best


## 같은 가지에서 왼끝 + 가운데 토막들 + 오른끝을 이어 붙인다 (긴 발판, 또는 끝이 이웃에 붙은 발판).
## avoid: 가까이 쌓인 같은 크기 이웃의 [조각, 뒤집기] (다른 조각을 고르고, 같은 조각뿐이면 반대로 뒤집는다)
func _chain(names: Array, xa: float, xb: float, y_at: Callable, left_free: bool, right_free: bool, thick: float, tuck_l := false, tuck_r := false, avoid := []) -> void:
	# 걷는 구간이 긴 가지들 중에서 고른다
	var cands: Array = []
	for n in names:
		var walk := skin.walk_of(n)
		if walk.y - walk.x >= 200.0:
			cands.append(n)
	if cands.is_empty():
		cands = names.duplicate()
	var avoid_names := {}
	for av in avoid:
		avoid_names[av[0]] = av[1]
	var fresh: Array = []
	for n in cands:
		if not avoid_names.has(n):
			fresh.append(n)
	if not fresh.is_empty():
		cands = fresh
	var name: String = cands[_rng.randi_range(0, cands.size() - 1)]
	var walk := skin.walk_of(name)
	var size := skin.size_of(name)
	var depth := float(skin.pieces[name].get("depth", 0.0))
	var u := 1.0
	if depth > 1.0:
		u = clampf(thick * 0.9 / (depth * skin.scale), 1.0, U_MAX)
	var k := u * skin.scale
	var cap := minf(160.0, (walk.y - walk.x) * 0.3)
	var a := xa - (0.0 if left_free else TUCK)
	var b := xb + (0.0 if right_free else TUCK)
	# 뒤집을 때는 끝 조각 자리를 바꿔 계획한 뒤 거울처럼 옮긴다 (덮인 쪽에 끝 조각이 가지 않게)
	var flip := _rng.randf() < 0.5
	if avoid_names.has(name):
		flip = not bool(avoid_names[name])
	pick = name
	pick_flip = flip
	var lcap := right_free if flip else left_free
	var rcap := left_free if flip else right_free
	var segs := _plan(a, b, k, walk, size.x, cap, lcap, rcap, walk.x + cap * 0.5, walk.y - cap * 0.5, 220.0, 420.0)
	for i in segs.size():
		var sg: Array = segs[i]
		var x0: float = sg[2]
		var x1: float = x0 + (sg[1] - sg[0]) * k
		var opts := {}
		if left_free:
			opts["clip_l"] = xa
		if right_free:
			opts["clip_r"] = xb
		var sx0 := a + b - x1 if flip else x0
		var sx1 := a + b - x0 if flip else x1
		if i > 0:
			opts["fade_r" if flip else "fade_l"] = OVERLAP
		# 이웃 지형에 덮인 끝: 이웃 속으로 밀어 넣은 TUCK 만큼 서서히 사라진다 (몸통은 맨 아래 겹이라 그대로면 이웃 위에 잘린 끝이 보인다)
		if tuck_l and sx0 <= a + 1.0:
			opts["fade_l"] = maxf(float(opts.get("fade_l", 0.0)), TUCK)
		if tuck_r and sx1 >= b - 1.0:
			opts["fade_r"] = maxf(float(opts.get("fade_r", 0.0)), TUCK)
		if flip:
			piece(name, sg[0], sg[1], sx0, sx1, y_at, k, true, opts)
		else:
			piece(name, sg[0], sg[1], x0, x1, y_at, k, false, opts)


## 이어 붙일 토막 계획: [[u0, u1, 놓일 x0], …]. 발 딛는 선이 a..b 를 빈틈없이 덮고, 토막끼리 OVERLAP 만큼 겹친다.
##  lcap: 왼끝 조각(조각의 0 ~ walk.x+cap, walk.x 가 a 에 옴) / rcap: 오른끝 조각(walk.y-cap ~ 끝, walk.y 가 b 에 옴)
##  가운데 토막은 lo..hi(조각 px) 안에서 길이 len_min~len_max 로 무작위로 고른다.
func _plan(a: float, b: float, k: float, walk: Vector2, full_w: float, cap: float, lcap: bool, rcap: bool, lo: float, hi: float, len_min: float, len_max: float, ov := OVERLAP) -> Array:
	var segs: Array = []
	var cur := a
	var first := true
	if lcap:
		segs.append([0.0, walk.x + cap, a - walk.x * k])
		cur = a + cap * k
		first = false
	var target := (b - cap * k + ov) if rcap else b
	var span := maxf(hi - lo, 20.0)
	var guard := 0
	while cur < target - 1.0 and guard < 256:
		guard += 1
		var start := cur - (0.0 if first else ov)
		var need := target - start
		var lw := minf(_rng.randf_range(len_min, len_max), span) * k
		if need - lw < len_min * k * 0.4:
			lw = need
		lw = minf(lw, span * k)
		if lw > need:
			lw = need
		var lu := lw / k
		var s0 := _rng.randf_range(lo, maxf(lo, lo + span - lu))
		segs.append([s0, s0 + lu, start])
		cur = start + lw
		first = false
	if rcap:
		segs.append([walk.y - cap, full_w, b - cap * k])
	return segs


# ---------------------------------------------------------------- 덩어리 (큰 바닥·벽·천장·경사)
## 다각형(시계 방향) 덩어리: 몸통 결 + 드러난 윗면 띠 + 아랫면 매단 장식 + 옆면 어둡게.
func build_mass(poly: PackedVector2Array, decorate: bool, vertical: bool) -> void:
	var n := poly.size()
	var tops: Array = []      # [a, b] 드러난 윗면 조각 (왼→오)
	var bottoms: Array = []   # [a, b] 드러난 아랫면 (왼→오로 바꿔 담음)
	var sides: Array = []     # [a, b, 바깥 법선]
	var top_edges: Array = [] # 모든 윗변 (드러남 상관없이)
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var e := b - a
		var len := e.length()
		if len < 1.0:
			continue
		var kind := _edge_kind(e)
		if kind == 0:
			top_edges.append([a, b])
		for run in _exposed_runs(a, b):
			var p0 := a.lerp(b, run[0])
			var p1 := a.lerp(b, run[1])
			match kind:
				0:
					var cap_l: bool = run[0] <= 0.001 and _side_exposed_at(poly, i, true)
					var cap_r: bool = run[1] >= 0.999 and _side_exposed_at(poly, i, false)
					var cont_l: bool = run[0] <= 0.001 and _prev_is_top(poly, i)
					var cont_r: bool = run[1] >= 0.999 and _next_is_top(poly, i)
					tops.append([p0, p1, cap_l, cap_r, cont_l, cont_r])
				1:
					bottoms.append([p1, p0])
				_:
					sides.append([p0, p1, Vector2(e.y, -e.x) / len])
	# 1) 몸통 결
	var deep_px := skin.fill_param("deep_px", 260.0)
	var top_b := skin.fill_param("top", 0.78)
	var deep_b := skin.fill_param("deep", 0.36)
	var rim_b := skin.fill_param("rim", 0.62)
	var rim_px := skin.fill_param("rim_px", 26.0)
	var wall_b := skin.fill_param("wall", 0.48)
	var shade := func(p: Vector2) -> float:
		var d := INF
		for t in tops:
			var a: Vector2 = t[0]
			var b: Vector2 = t[1]
			if p.x >= a.x - 1.0 and p.x <= b.x + 1.0 and b.x - a.x > 0.5:
				var ly := lerpf(a.y, b.y, clampf((p.x - a.x) / (b.x - a.x), 0.0, 1.0))
				if p.y >= ly - 1.0:
					d = minf(d, p.y - ly)
		var s := deep_b
		if vertical:
			s = wall_b
		if d < INF:
			s = lerpf(top_b, s, smoothstep(0.0, deep_px, d))
		for sd in sides:
			var dist := _seg_dist(p, sd[0], sd[1])
			if vertical:
				# 세로 기둥·벽: 가장자리 바로 안쪽이 살짝 밝다 (둥근 줄기처럼), 가장자리는 어둡게
				if dist < 90.0:
					s *= lerpf(rim_b, 1.0, smoothstep(0.0, 18.0, dist)) * (1.0 + 0.16 * sin(clampf(dist / 90.0, 0.0, 1.0) * PI))
			elif dist < rim_px:
				s *= lerpf(rim_b, 1.0, dist / rim_px)
		for bt in bottoms:
			var dist2 := _seg_dist(p, bt[0], bt[1])
			if dist2 < rim_px:
				s *= lerpf(rim_b, 1.0, dist2 / rim_px)
		return s
	# 몸통 결은 바닥 띠가 덮는 윗면에서 top_inset px 아래부터 깐다 (띠의 풀잎 사이로 몸통의 곧은 윗선이 비치지 않게)
	# 몸통은 1px 넓혀 깐다 (이웃 덩어리·방 가장자리 벽과 맞닿는 곳에 밝은 1px 틈이 보이지 않게)
	var body := _jag(poly)
	var grown := Geometry2D.offset_polygon(body, 1.0, Geometry2D.JOIN_MITER)
	if grown.size() == 1 and (grown[0] as PackedVector2Array).size() >= 3:
		body = grown[0]
	var polys: Array = [body]
	var inset := skin.fill_param("top_inset", 16.0)
	if decorate and skin.has_role("ground") and inset > 0.0:
		for t in tops:
			var ta: Vector2 = t[0]
			var tb: Vector2 = t[1]
			var strip := PackedVector2Array([ta + Vector2(-1, -60), tb + Vector2(1, -60), tb + Vector2(1, inset), ta + Vector2(-1, inset)])
			var next: Array = []
			for pp in polys:
				for q in Geometry2D.clip_polygons(pp, strip):
					if (q as PackedVector2Array).size() >= 3:
						next.append(q)
			polys = next
	for pp in polys:
		fill_polygon(pp, vertical, shade)
	# 1b) 벽·기둥·천장 (그 역할 조각이 있는 그림 옷만 — 아래 '벽·천장·기둥' 묶음). 바닥 띠·매단 장식이 그 위에 얹힌다.
	#     pillar: 세로로 긴 장식 덩어리 전체를 기둥 그림으로 감싼다 (감싼 덩어리에는 wall 을 따로 세우지 않는다)
	#     wall: 드러난 높은 옆면을 따라 세로로 / ceiling: 드러난 아랫면을 따라 가로로
	var wrapped := decorate and vertical and skin.has_role("pillar") and _pillar_run(poly, sides)
	if not wrapped and skin.has_role("wall"):
		var min_h := float(skin.param("wall", "min_h", 140.0))
		for sd in sides:
			var nv: Vector2 = sd[2]
			if absf(nv.x) >= 0.7 and absf((sd[1] as Vector2).y - (sd[0] as Vector2).y) >= min_h:
				_wall_run(sd[0], sd[1], nv, tops)
	if skin.has_role("ceiling"):
		var min_c := float(skin.param("ceiling", "min_len", 160.0))
		for bt in bottoms:
			if (bt[1] as Vector2).x - (bt[0] as Vector2).x >= min_c:
				_ceiling_run(bt[0], bt[1])
	# 2) 윗면 띠
	if decorate and skin.has_role("ground"):
		for t in tops:
			_ground_run(t[0], t[1], t[2], t[3], t[4], t[5])
	# 3) 아랫면 매단 장식 (덩어리가 충분히 두꺼울 때 — 천장도 포함)
	if skin.has_role("hang"):
		for bt in bottoms:
			_hang_run(bt[0], bt[1], 1.0 if decorate else 0.7)
	# 4) 드러난 옆면: 위쪽 모서리에 늘어진 덩굴, 높은 벽이면 아래로 내려가며 띄엄띄엄 (곧은 벽이 밋밋하지 않게)
	if skin.has_role("hang"):
		for sd in sides:
			var a: Vector2 = sd[0]
			var b: Vector2 = sd[1]
			var nrm: Vector2 = sd[2]
			if absf(nrm.x) < 0.7 or absf(b.y - a.y) < 140.0:
				continue
			var top_pt := a if a.y < b.y else b
			var bot_y := maxf(a.y, b.y)
			# 맨 위 덩굴도 발 높이보다 아래에서 시작한다 (절벽 끝 밖 발 높이에 잎이 서 있으면 발판처럼 보인다)
			var y := top_pt.y + 34.0
			var first := true
			while y < bot_y - 120.0:
				if (first and decorate and _rng.randf() < 0.8) or (not first and _rng.randf() < 0.6):
					_hang_at(Vector2(top_pt.x + nrm.x * 6.0, y), nrm.x, _rng.randf_range(0.6, 0.85))
				first = false
				y += _rng.randf_range(260.0, 480.0)


# ---------------------------------------------------------------- 벽·천장·기둥 (세로·가로로 이어 까는 조각)
## 세 역할 모두 그림 옷에 그 조각이 있을 때만 쓴다 (없으면 몸통 결 + 매단 장식만 — 수관·마을).
## 조각 고르기·이음은 변의 자리로 씨앗을 정한 따로 된 난수를 써서, 다른 장식을 만드는 순서와 상관없이 늘 같은 모양이다.
## 세로 토막 하나는 vstrip 으로 그린다 (세 역할 공용).

## 변 자리로 씨앗을 정한 난수 (벽·천장·기둥 전용)
func _edge_rng(p: Vector2) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	var g := p + (host.global_position if host else Vector2.ZERO)
	r.seed = int(g.x * 3.0 + g.y * 11.0) + 7919
	return r


## 벽 (역할 wall): 드러난 높은 옆면 a–b 를 따라 세로로 긴 조각(줄기 껍질·크레인 기둥·관 기둥)을 이어 세운다.
## params.wall:
##   width    : 그릴 폭 (px) — 없으면 조각 폭 × scale
##   out      : 충돌 옆면 밖으로 나오는 폭 (px) — 없으면 (1 − inset) × 폭 (inset: 폭 중 벽 속에 묻히는 비율, 기본 0.75)
##   min_h    : 이보다 짧은 옆면에는 안 세운다 (px)
##   top_inset: 옆면 위 끝이 드러난 윗면의 끝이면 이만큼 내려서 시작 (바닥 띠의 절벽 끝이 위를 덮는다)
##   inner_fade : 안쪽(몸통 쪽) 가장자리가 몸통 결로 녹아드는 비율 (0 이면 곧게)
##   tile     : "strip" (기본) — 조각 안 세로 구간 v_lo~v_hi(비율)에서 무작위 토막을 OVERLAP 만큼 서서히 겹쳐 잇는다 (줄기·뿌리처럼 결이 이어지는 그림)
##              "grid" — 조각의 세로 구간 repeat {조각: [v0, v1]}(조각 px, 없으면 전체)을 전역 y 격자에 맞춰 곧게 되풀이 (기둥·관처럼 마디가 있는 그림 — 이웃 벽과 마디가 맞는다)
##   end_fade : strip 의 위아래 끝이 서서히 사라지는 길이 (px, 기본 24)
##   art_faces: 그림의 바깥쪽이 보는 방향 (+1 오른쪽, −1 왼쪽, 0 이면 뒤집지 않음). 반대쪽 옆면에는 좌우로 뒤집는다.
##   flip_random : true 면 무작위로도 뒤집는다 (좌우가 거의 같은 그림)
func _wall_run(a: Vector2, b: Vector2, nrm: Vector2, tops: Array) -> void:
	var rng := _edge_rng(a)
	var names := skin.list("wall")
	var side := 1.0 if nrm.x > 0.0 else -1.0
	var name0: String = names[rng.randi_range(0, names.size() - 1)]
	var size0 := skin.size_of(name0)
	var w := float(skin.param("wall", "width", size0.x * float(skin.param("wall", "scale", 1.0)) * skin.scale))
	var out := float(skin.param("wall", "out", (1.0 - float(skin.param("wall", "inset", 0.75))) * w))
	var inner_fade := float(skin.param("wall", "inner_fade", 0.0))
	var y0 := minf(a.y, b.y)
	var y1 := maxf(a.y, b.y)
	var x := (a.x + b.x) * 0.5
	var top_inset := float(skin.param("wall", "top_inset", 0.0))
	if top_inset > 0.0:
		for t in tops:
			var ta: Vector2 = t[0]
			var tb: Vector2 = t[1]
			if (absf(ta.x - x) < 2.0 and absf(ta.y - y0) < 2.0) or (absf(tb.x - x) < 2.0 and absf(tb.y - y0) < 2.0):
				y0 += top_inset
				break
	if _has_room:
		y0 = maxf(y0, _room_box.position.y)
		y1 = minf(y1, _room_box.end.y)
	if y1 - y0 < 8.0:
		return
	var xo := x + side * out
	var xi := xo - side * w
	var xl := minf(xo, xi)
	var xr := maxf(xo, xi)
	var faces := float(skin.param("wall", "art_faces", 1.0))
	var flip_base := faces != 0.0 and side != faces
	var flip_rand: bool = bool(skin.param("wall", "flip_random", false))
	if str(skin.param("wall", "tile", "strip")) == "grid":
		# 마디 격자: 조각 하나의 세로 구간을 전역 y 에 맞춰 되풀이 (끝은 잘라 맞춘다)
		var k := w / size0.x
		var rep: Dictionary = skin.param("wall", "repeat", {})
		var v0 := 0.0
		var v1 := size0.y
		if rep.has(name0):
			v0 = float(rep[name0][0])
			v1 = float(rep[name0][1])
		var seg := (v1 - v0) * k
		if seg < 8.0:
			return
		var gy := host.global_position.y
		var y := floorf((y0 + gy) / seg) * seg - gy
		var guard := 0
		while y < y1 and guard < 400:
			guard += 1
			var ya := maxf(y, y0)
			var yb := minf(y + seg, y1)
			if yb - ya > 0.5:
				vstrip(name0, v0 + (ya - y) / k, v0 + (yb - y) / k, xl, xr, ya, yb, flip_base, 0.0, 0.0, side, inner_fade)
			y += seg
		return
	# 결 토막: 조각 안 v_lo~v_hi 에서 무작위 길이의 토막을 서서히 겹쳐 잇는다
	var v_lo := float(skin.param("wall", "v_lo", 0.0))
	var v_hi := float(skin.param("wall", "v_hi", 1.0))
	var end_fade := float(skin.param("wall", "end_fade", 24.0))
	var y2 := y0
	var first := true
	var guard2 := 0
	while y2 < y1 - 1.0 and guard2 < 64:
		guard2 += 1
		var n: String = names[rng.randi_range(0, names.size() - 1)]
		var sz := skin.size_of(n)
		var k2 := (xr - xl) / sz.x
		var lo := sz.y * v_lo
		var hi := sz.y * v_hi
		var start := y2 - (0.0 if first else OVERLAP)
		var lv := minf(rng.randf_range(0.55, 1.0) * (hi - lo), hi - lo)
		var need := (y1 - start) / k2
		if need - lv < (hi - lo) * 0.3:
			lv = minf(need, hi - lo)
		var vs := rng.randf_range(lo, maxf(lo, hi - lv))
		var seg_h := lv * k2
		var last := start + seg_h >= y1 - 1.0
		var flip := flip_base != (flip_rand and rng.randf() < 0.5)
		vstrip(n, vs, vs + lv, xl, xr, start, start + seg_h, flip, end_fade if first else OVERLAP, end_fade if last else 0.0, side, inner_fade)
		y2 = start + seg_h
		first = false


## 천장 (역할 ceiling): 드러난 아랫면 a→b(왼→오)를 따라 들보·관 조각을 가로로 잇는다 (전역 x 격자 — 이웃 천장과 마디가 맞는다).
## params.ceiling: scale, inset(조각 높이 중 천장 속에 묻히는 비율, 기본 0.35), repeat {조각: [u0, u1]}(이어 붙일 가로 구간), min_len.
func _ceiling_run(a: Vector2, b: Vector2) -> void:
	var rng := _edge_rng(a)
	var names := skin.list("ceiling")
	var name: String = names[rng.randi_range(0, names.size() - 1)]
	var size := skin.size_of(name)
	var k := float(skin.param("ceiling", "scale", 1.0)) * skin.scale
	var inset := float(skin.param("ceiling", "inset", 0.35))
	var rep: Dictionary = skin.param("ceiling", "repeat", {})
	var u0 := 0.0
	var u1 := size.x
	if rep.has(name):
		u0 = float(rep[name][0])
		u1 = float(rep[name][1])
	var seg := (u1 - u0) * k
	if seg < 8.0:
		return
	var xa := a.x
	var xb := b.x
	if _has_room:
		xa = maxf(xa, _room_box.position.x)
		xb = minf(xb, _room_box.end.x)
	var slope := (b.y - a.y) / maxf(b.x - a.x, 0.001)
	var y_at := func(x: float) -> float: return a.y + (x - a.x) * slope
	var gx := host.global_position.x
	var x := floorf((xa + gx) / seg) * seg - gx
	var guard := 0
	while x < xb and guard < 400:
		guard += 1
		var sa := maxf(x, xa)
		var sb := minf(x + seg, xb)
		if sb - sa > 1.0:
			piece(name, u0 + (sa - x) / k, u0 + (sb - x) / k, sa, sb, y_at, k, false, {"y_off": -inset * size.y * k, "warp": false})
		x += seg


## 기둥 (역할 pillar — 매달린 뿌리 기둥처럼 세로로 긴 그림): 세로로 긴 장식 덩어리를 드러난 옆면 높이만큼 위에서 아래로 감싼다.
## params.pillar: wide (폭 = 덩어리 폭 × wide, 가운데 맞춤 — 몸통 결의 곧은 옆선을 덮는다, 기본 1.25), overlap (토막 이음 비율, 기본 0.2),
##   tail (아래끝이 드러났으면 가늘어지는 끝이 늘어지는 비율, 기본 0.22). 위끝은 덮인 쪽(천장) 속으로 TUCK 만큼, 아래끝이 덮였으면(바닥에 선 기둥) 거기서 끝.
## 감쌌으면 true.
func _pillar_run(poly: PackedVector2Array, sides: Array) -> bool:
	if sides.is_empty():
		return false
	var bb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	var y0 := INF
	var y1 := -INF
	for sd in sides:
		y0 = minf(y0, minf((sd[0] as Vector2).y, (sd[1] as Vector2).y))
		y1 = maxf(y1, maxf((sd[0] as Vector2).y, (sd[1] as Vector2).y))
	if y1 - y0 < 60.0:
		return false
	var rng := _edge_rng(bb.position)
	var names := skin.list("pillar")
	var name: String = names[rng.randi_range(0, names.size() - 1)]
	var sz := skin.size_of(name)
	var w := bb.size.x * float(skin.param("pillar", "wide", 1.25))
	var th := sz.y * w / sz.x
	var top_cov := _covered(Vector2(bb.get_center().x, y0 - OUT))
	var bot_free := not _covered(Vector2(bb.get_center().x, y1 + OUT))
	var a := y0 - (TUCK if top_cov else 0.0)
	var b := y1 + (th * float(skin.param("pillar", "tail", 0.22)) if bot_free else 0.0)
	var ov := th * float(skin.param("pillar", "overlap", 0.2))
	var n := maxi(1, int(round((b - a - ov) / (th - ov))))
	# 토막 높이를 맞춰 a..b 를 꼭 채운다 (세로 늘이기 1.35 배를 넘으면 토막을 하나 더)
	var tile := (b - a + (n - 1) * ov) / n
	if tile > th * 1.35:
		n += 1
		tile = (b - a + (n - 1) * ov) / n
	var x0 := bb.get_center().x - w * 0.5
	var flip := rng.randf() < 0.5
	for i in n:
		var ty := a + i * (tile - ov)
		# 마지막 토막이 바닥에 선 기둥이면 끝 18px 동안 서서히 (가는 끝이 바닥 속으로 들어가지 않게)
		vstrip(name, 0.0, sz.y, x0, x0 + w, ty, ty + tile, flip, ov if i > 0 else 0.0, 18.0 if (i == n - 1 and not bot_free) else 0.0)
		flip = not flip
	return true


## 세로 토막 하나: 조각 name 의 세로 구간 v0..v1(조각 px)을 사각형 xl..xr × ya..yb 에 편다 (벽·기둥 공용).
## fade_top / fade_bot: 위·아래 끝이 서서히 나타나고 사라지는 길이(px). inner_side(±1, 바깥쪽 방향)·inner_fade(폭 비율):
## 안쪽(몸통 쪽) 가장자리가 서서히 사라진다 (inner_fade 0 이면 곧게).
func vstrip(name: String, v0: float, v1: float, xl: float, xr: float, ya: float, yb: float, flip: bool, fade_top := 0.0, fade_bot := 0.0, inner_side := 0.0, inner_fade := 0.0) -> void:
	if yb - ya < 0.5 or xr - xl < 0.5:
		return
	var r := skin.rect_of(name)
	var asz := skin.atlas_size
	var ys := PackedFloat32Array([ya, minf(ya + fade_top, yb), maxf(yb - fade_bot, ya), yb])
	var cols_n := 7 if inner_fade > 0.0 and inner_side != 0.0 else 2
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	pts.resize(cols_n * 4)
	uvs.resize(cols_n * 4)
	cols.resize(cols_n * 4)
	for ci in cols_n:
		var f := float(ci) / (cols_n - 1)
		var u := (1.0 - f) if flip else f
		var ca := 1.0
		if cols_n > 2:
			# 바깥쪽이 오른쪽(+1)이면 왼쪽(xl)이 안쪽
			ca = smoothstep(0.0, inner_fade, f if inner_side > 0.0 else 1.0 - f)
		for ri in 4:
			var yy := ys[ri]
			var ra := 1.0
			if (ri == 0 and fade_top > 0.0) or (ri == 3 and fade_bot > 0.0):
				ra = 0.0
			var v := lerpf(v0, v1, (yy - ya) / (yb - ya))
			var k := ci * 4 + ri
			pts[k] = Vector2(lerpf(xl, xr, f), yy)
			uvs[k] = Vector2((r.position.x + u * r.size.x) / asz.x, (r.position.y + v) / asz.y)
			cols[k] = Color(_mod.r, _mod.g, _mod.b, _mod.a * ca * ra)
	var idx := PackedInt32Array()
	idx.resize((cols_n - 1) * 3 * 6)
	var w := 0
	for ci in cols_n - 1:
		for ri in 3:
			var p := ci * 4 + ri
			var q := p + 4
			idx[w] = p; idx[w + 1] = p + 1; idx[w + 2] = q
			idx[w + 3] = p + 1; idx[w + 4] = q + 1; idx[w + 5] = q
			w += 6
	_tris(BUF_ATLAS, pts, uvs, cols, idx)


## 드러난 옆변·아랫변을 나무껍질 혹처럼 살짝 울퉁불퉁하게 (그림만 — 충돌은 곧은 그대로). 바깥 +9 ~ 안 -3 px.
## 윗변은 ground 띠가 덮으므로 그대로 둔다.
func _jag(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	var ph := _rng.randf() * TAU
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		out.append(a)
		var e := b - a
		var len := e.length()
		if len < 30.0 or _edge_kind(e) == 0:
			continue
		var nrm := Vector2(e.y, -e.x) / len
		var steps := int(len / 22.0)
		for k in range(1, steps):
			var t := float(k) / steps
			var p := a.lerp(b, t)
			if _covered(p + nrm * OUT):
				continue
			var d := 3.0 + 3.5 * sin(p.x * 0.031 + p.y * 0.027 + ph) + 2.5 * sin(p.x * 0.083 - p.y * 0.069 + ph * 2.0)
			# 모서리 가까이는 0 으로 (이웃 변과 어긋나지 않게)
			d *= smoothstep(0.0, 40.0, minf(t, 1.0 - t) * len)
			out.append(p + nrm * d)
	return out


## 변 종류: 0 윗변(왼→오, 완만), 1 아랫변(오→왼, 완만), 2 옆변
static func _edge_kind(e: Vector2) -> int:
	if e.x > 0.0 and absf(e.y) < e.x * 1.2:
		return 0
	if e.x < 0.0 and absf(e.y) < -e.x * 1.2:
		return 1
	return 2


func _prev_is_top(poly: PackedVector2Array, i: int) -> bool:
	var n := poly.size()
	return _edge_kind(poly[i] - poly[(i - 1 + n) % n]) == 0


func _next_is_top(poly: PackedVector2Array, i: int) -> bool:
	var n := poly.size()
	return _edge_kind(poly[(i + 2) % n] - poly[(i + 1) % n]) == 0


## 윗변 i 의 왼끝(start)·오른끝에 이어진 옆변이 드러나 있는가 (절벽 끝이면 끝 조각을 단다)
func _side_exposed_at(poly: PackedVector2Array, i: int, start: bool) -> bool:
	var n := poly.size()
	var a := poly[(i - 1 + n) % n] if start else poly[(i + 1) % n]
	var b := poly[i] if start else poly[(i + 2) % n]
	var e := b - a
	var len := e.length()
	if len < 1.0 or _edge_kind(e) == 0:
		return false
	var dir := e / len
	var nrm := Vector2(e.y, -e.x) / len
	var d := minf(10.0, len * 0.5)   # 모서리 바로 아래 (구덩이 바닥이 20px 아래 붙어 있어도 절벽 끝으로 본다)
	# 모서리에서 옆변을 따라 조금 들어간 자리의 바깥쪽
	var probe := (b - dir * d) if start else (a + dir * d)
	return not _covered(probe + nrm * OUT)


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))


## 윗면 끝 p 의 바깥(side: −1 왼쪽, +1 오른쪽)에 같은 높이로 이어지는 이웃 윗면이 있는가
## (발 높이 바로 아래는 덮였고, 24px 위는 비었다 — 위로 솟은 벽이면 false)
func _level_neighbor(p: Vector2, side: float) -> bool:
	return _covered(p + Vector2(side * OUT, 6.0)) and not _covered(p + Vector2(side * OUT, -24.0))


## 드러난 윗면 한 구간에 ground 띠를 깐다. cap_*: 절벽 끝(끝 조각), cont_*: 옆 윗변으로 이어짐(겹치게 늘림).
func _ground_run(a: Vector2, b: Vector2, cap_l: bool, cap_r: bool, cont_l: bool, cont_r: bool) -> void:
	var names := skin.list("ground")
	# 끝 조각(절벽 끝)은 끝이 자연스럽게 끝나는 조각만 (params.ground.caps). 목록에 같은 이름을 여러 번 쓰면 더 자주 나온다.
	var caps: Array = []
	for c in skin.param("ground", "caps", []):
		if skin.pieces.has(c):
			caps.append(c)
	if caps.is_empty():
		caps = names
	var name: String = caps[_rng.randi_range(0, caps.size() - 1)]
	var walk := skin.walk_of(name)
	var size := skin.size_of(name)
	var k := skin.scale
	var band := float(skin.param("ground", "band", 110.0))
	var band_fade := float(skin.param("ground", "fade", 50.0))
	var cap := minf(float(skin.param("ground", "cap", 150.0)), (walk.y - walk.x) * 0.3)
	var slope := (b.y - a.y) / maxf(b.x - a.x, 0.001)
	var y_at := func(x: float) -> float: return a.y + (x - a.x) * slope
	var ov := float(skin.param("ground", "overlap", 72.0))
	# 끝이 같은 높이의 윗면으로 이어지면(이웃 바닥·같은 다각형의 다음 윗변) ov 만큼 그쪽으로 늘이고 그만큼 서서히 사라지게
	# → 두 띠가 이음매 없이 겹친다. 벽처럼 위로 솟은 이웃에 닿은 끝은 WALL_TUCK 만큼만 (벽 면에 이끼가 번져 보이지 않게).
	var ov_l := 0.0 if cap_l else (ov if (cont_l or _level_neighbor(a, -1.0)) else WALL_TUCK)
	var ov_r := 0.0 if cap_r else (ov if (cont_r or _level_neighbor(b, 1.0)) else WALL_TUCK)
	var xa := a.x - ov_l
	var xb := b.x + ov_r
	var segs := _plan(xa, xb, k, walk, size.x, cap, cap_l, cap_r, walk.x + 10.0, walk.y - 10.0, 200.0, 380.0, ov)
	for i in segs.size():
		var sg: Array = segs[i]
		var x0: float = sg[2]
		var x1: float = x0 + (sg[1] - sg[0]) * k
		var opts := {"band": band, "band_fade": band_fade}
		# 절벽 끝(드러난 끝) 밖의 그림은 발 높이에서 잘라 낸다 (끝 조각의 늘어진 뿌리는 아래쪽만 남는다)
		if cap_l:
			opts["clip_l"] = a.x
		if cap_r:
			opts["clip_r"] = b.x
		if i > 0:
			opts["fade_l"] = ov
		if i == 0 and not cap_l:
			opts["fade_l"] = maxf(ov_l, 10.0)
		if i == segs.size() - 1 and not cap_r:
			opts["fade_r"] = maxf(ov_r, 10.0)
		var is_cap := (i == 0 and cap_l) or (i == segs.size() - 1 and cap_r)
		if is_cap:
			opts["band"] = band * 1.8   # 절벽 끝은 뿌리가 더 보이게
			if i == 0 and segs.size() > 1:
				opts["fade_r"] = ov   # 깊은 뿌리가 다음 토막 아래에서 딱 잘려 보이지 않게
			# params.ground.flip_right_cap: 오른쪽 절벽 끝에 조각의 왼끝을 뒤집어 쓴다 (오른끝이 비탈인 조각 — 숨은 내리막.
			# 비탈이 충돌 끝 밖으로 이어져 내려가는 길처럼 보이지 않게). 기본 꺼짐 → 수관은 그대로.
			if i > 0 and i == segs.size() - 1 and bool(skin.param("ground", "flip_right_cap", false)):
				piece(name, 0.0, walk.x + cap, xb - cap * k, xb + walk.x * k, y_at, k, true, opts)
				continue
			piece(name, sg[0], sg[1], x0, x1, y_at, k, false, opts)
			continue
		# 가운데 토막은 바닥 조각 여럿을 섞는다 (한 조각만 되풀이하면 무늬가 줄지어 보인다)
		var pn := name
		var u0: float = sg[0]
		var len_u: float = sg[1] - sg[0]
		if names.size() > 1:
			var cand: String = names[_rng.randi_range(0, names.size() - 1)]
			var cw := skin.walk_of(cand)
			if cw.y - cw.x - 20.0 >= len_u:
				pn = cand
				u0 = _rng.randf_range(cw.x + 10.0, cw.y - 10.0 - len_u)
		piece(pn, u0, u0 + len_u, x0, x1, y_at, k, _rng.randf() < 0.5, opts)
	# 세워 두는 장식(난간·등불 줄 기둥 — prop 역할이 있는 지역만): 띠 위에 세우고 밑동은 이끼 속으로 서서히 사라진다
	if skin.has_role("prop"):
		_props(a, b, y_at, cap_l, cap_r)
	# 가끔 작은 덤불
	if skin.has_role("bush"):
		var bushes := skin.list("bush")
		var bx := a.x + _rng.randf_range(120.0, 400.0)
		while bx < b.x - 80.0:
			if _rng.randf() < 0.35:
				var bn: String = bushes[_rng.randi_range(0, bushes.size() - 1)]
				var bsz := skin.size_of(bn)
				var bk := k * _rng.randf_range(0.6, 0.85)
				var y: float = y_at.call(bx) - bsz.y * bk * 0.62
				piece(bn, 0.0, bsz.x, bx - bsz.x * bk * 0.5, bx + bsz.x * bk * 0.5, func(_x): return y, bk, _rng.randf() < 0.5, {"y_off": 0.0})
			bx += _rng.randf_range(260.0, 620.0)


## 드러난 윗면 a→b 에 세워 두는 장식(prop 역할: 난간 토막·등불 줄 기둥 등)을 띄엄띄엄 세운다. 그림만 — 소녀 뒤에 그려진다.
## params.prop: gap_min / gap_max (장식 사이 빈 길이), edge (절벽 끝에서 떨어질 거리), sink (밑동을 발 선 아래로 묻는 px — 그 둘레에서 서서히 사라진다),
##              min_len (이보다 짧은 윗면에는 안 세움), clear (포탈·달빛풀·기록물·NPC 자리 둘레 비울 반폭), size ([최소, 최대] 배율)
## 방의 Exits·Interactables·Markers 자리 둘레는 비운다 (상호작용 물체가 장식에 묻히지 않게).
func _props(a: Vector2, b: Vector2, y_at: Callable, cap_l: bool, cap_r: bool) -> void:
	var names := skin.list("prop")
	if names.is_empty() or b.x - a.x < float(skin.param("prop", "min_len", 600.0)):
		return
	var gap_min := float(skin.param("prop", "gap_min", 520.0))
	var gap_max := float(skin.param("prop", "gap_max", 1000.0))
	var edge := float(skin.param("prop", "edge", 160.0))
	var sink := float(skin.param("prop", "sink", 12.0))
	var clear := float(skin.param("prop", "clear", 150.0))
	var sz: Array = skin.param("prop", "size", [0.9, 1.05])
	var busy := _busy_spots(a.y, clear)
	var lo := a.x + (edge if cap_l else 70.0)
	var hi := b.x - (edge if cap_r else 70.0)
	var x := lo + _rng.randf_range(0.0, gap_min * 0.7)
	var last := ""
	var guard := 0
	while x < hi and guard < 64:
		guard += 1
		var n: String = names[_rng.randi_range(0, names.size() - 1)]
		if n == last and names.size() > 1:
			n = names[(names.find(n) + 1) % names.size()]
		var ps := skin.size_of(n)
		var k := skin.scale * _rng.randf_range(float(sz[0]), float(sz[1]))
		var w := ps.x * k
		var x0 := x
		var x1 := x + w
		if x1 > hi:
			break
		var blocked := false
		for r in busy:
			if x1 > r.x and x0 < r.y:
				blocked = true
				x = r.y + 10.0
				break
		if blocked:
			continue
		var cx := (x0 + x1) * 0.5
		var y_top: float = y_at.call(cx) - ps.y * k + sink
		# 밑동(잘린 아랫선)은 발 선 둘레에서 서서히 사라져 이끼에 묻힌 것처럼 (band: 조각 px)
		var fade_px := sink * 1.6 / k
		piece(n, 0.0, ps.x, x0, x1, func(_x): return y_top, k, _rng.randf() < 0.5, {"y_off": 0.0, "band": maxf(ps.y - fade_px, 1.0), "band_fade": fade_px})
		last = n
		x = x1 + _rng.randf_range(gap_min, gap_max)


## 상호작용 물체 자리(노드 기준 가로 구간 [x0, x1] 배열): 방의 Exits·Interactables·Markers 자식 중 윗면 y 근처(위 260·아래 60)에 있는 것.
func _busy_spots(top_y: float, half: float) -> Array:
	var out := []
	var room := TerrainStyle.room_of(host)
	if room == null:
		return out
	for group in ["Exits", "Interactables", "Markers"]:
		var g := room.get_node_or_null(group)
		if g == null:
			continue
		for c in g.get_children():
			if not (c is Node2D):
				continue
			var lp: Vector2 = (c as Node2D).global_position - host.global_position
			if lp.y > top_y - 260.0 and lp.y < top_y + 60.0:
				out.append(Vector2(lp.x - half, lp.x + half))
	return out


## 드러난 아랫면(왼→오)에 매단 장식을 늘어놓는다.
func _hang_run(a: Vector2, b: Vector2, density: float) -> void:
	var len := b.x - a.x
	if len < 60.0:
		return
	var x := a.x + _rng.randf_range(10.0, 120.0)
	# 간격 배수 (data params.hang.gap, 기본 1 — 등불처럼 폭이 좁은 장식이 너무 촘촘해 보이지 않게)
	var gap := float(skin.param("hang", "gap", 1.0))
	while x < b.x - 30.0:
		var y := lerpf(a.y, b.y, clampf((x - a.x) / maxf(len, 1.0), 0.0, 1.0))
		var w := _hang_at(Vector2(x, y), 0.0, _rng.randf_range(0.65, 0.95), b.x - x)
		x += (maxf(w, 60.0) * _rng.randf_range(0.35, 0.7) + _rng.randf_range(0.0, 160.0) / density) * gap


## 매단 장식 하나를 p(장식 맨 위가 닿을 자리)에 단다. side: 옆면이면 바깥쪽(±1)으로 붙인다. 돌려주는 값 = 놓인 폭.
func _hang_at(p: Vector2, side: float, size_k: float, max_w := INF) -> float:
	if side != 0.0 and skin.has_role("hang_side"):
		return _side_hang_at(p, side, size_k)
	var names := skin.list("hang")
	var name: String = names[_rng.randi_range(0, names.size() - 1)]
	var size := skin.size_of(name)
	var k := skin.scale * size_k
	var w := size.x * k
	if w > max_w + 20.0:
		k *= (max_w + 20.0) / w
		w = size.x * k
	if w < 30.0:
		return 30.0
	var x0 := p.x
	# 옆면: 덩굴이 벽 면에 기대어 늘어지게 (70% 는 벽 위, 30% 는 바깥으로)
	if side < 0.0:
		x0 = p.x - w * 0.3
	elif side > 0.0:
		x0 = p.x - w * 0.7
	# 덩굴 뿌리(잎 달린 윗부분)가 가장자리를 덮어 곧은 아랫선이 안 보이게 조금 위에서 시작
	var y := p.y - (14.0 if side != 0.0 else 34.0) * k
	piece(name, 0.0, size.x, x0, x0 + w, func(_x): return y, k, _rng.randf() < 0.5, {"y_off": 0.0})
	return w


## 옆면 전용 매단 장식 (역할 hang_side — 벽에 박힌 등불 걸이 등). 그림은 벽이 오른쪽에 있게 그린 것으로 본다:
## 왼쪽을 향한 면(side −1)에는 그대로, 오른쪽을 향한 면(+1)에는 뒤집어 벽에 붙인다. 돌려주는 값 = 놓인 폭.
func _side_hang_at(p: Vector2, side: float, size_k: float) -> float:
	var names := skin.list("hang_side")
	var name: String = names[_rng.randi_range(0, names.size() - 1)]
	var size := skin.size_of(name)
	var k := skin.scale * size_k
	var w := size.x * k
	var x0 := p.x - w + 4.0 if side < 0.0 else p.x - 4.0
	var y := p.y
	piece(name, 0.0, size.x, x0, x0 + w, func(_x): return y, k, side > 0.0, {"y_off": 0.0})
	return w


# ---------------------------------------------------------------- 경사 (TerrainPolygon)
## 경사 다각형: 위 변 아래 두께가 얇으면(가지 경사) 위 변마다 가지를 기울여 놓고, 아니면 덩어리처럼 그린다.
func build_polygon(t: Node2D, poly: PackedVector2Array, suspicious := false) -> void:
	var t0 := Time.get_ticks_usec()
	_begin(int(poly[0].x * 3.0 + poly[1].y * 5.0))
	var bb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	_shapes = neighbors(t, bb.grow_individual(400, 300, 400, 400))
	_own_poly = poly
	if suspicious:
		_mod = _mod.lerp(Color(1.0, 0.98, 0.92), 0.22)
	var thin_max := float(skin.param("branch", "thin_poly", 110.0))
	var all_thin := true
	var n := poly.size()
	for i in n:
		var e := poly[(i + 1) % n] - poly[i]
		if _edge_kind(e) == 0 and _thickness_below(poly, poly[i].lerp(poly[(i + 1) % n], 0.5)) > thin_max:
			all_thin = false
	if all_thin and skin.has_role("branch"):
		for i in n:
			var a := poly[i]
			var b := poly[(i + 1) % n]
			if _edge_kind(b - a) != 0:
				continue
			var slope := (b.y - a.y) / maxf(b.x - a.x, 0.001)
			var y_at := func(x: float) -> float: return a.y + (x - a.x) * slope
			var l_cov := _covered(a + Vector2(-OUT, 6.0))
			var r_cov := _covered(b + Vector2(OUT, 6.0))
			var l_bend := _prev_is_top(poly, i)
			var r_bend := _next_is_top(poly, i)
			# 꺾임(같은 다각형의 윗변으로 이어짐)은 그대로 겹치고, 이웃 지형에 덮인 끝만 이웃 속으로 서서히 사라진다
			branch_run(a.x, b.x, y_at, not l_cov and not l_bend, not r_cov and not r_bend, false, _thickness_below(poly, a.lerp(b, 0.5)), l_cov and not l_bend, r_cov and not r_bend)
	else:
		build_mass(poly, true, false)
	_finish(t0)


## 다각형 안에서 점 p 아래로 내려가 처음 빠져나오는 곳까지의 두께
static func _thickness_below(poly: PackedVector2Array, p: Vector2) -> float:
	var a := p + Vector2(0, 0.5)
	var far := p + Vector2(0, 5000)
	var best := INF
	var n := poly.size()
	for i in n:
		var hit = Geometry2D.segment_intersects_segment(a, far, poly[i], poly[(i + 1) % n])
		if hit != null:
			var d: float = (hit as Vector2).y - p.y
			if d > 1.0:
				best = minf(best, d)
	return best if best < INF else 0.0


# ---------------------------------------------------------------- 가시 (Thorns)
## 가시: thorn 조각을 길이를 따라 크기를 섞어 겹쳐 세운다. 밑동은 밑면에 sink px 묻고, 끝은 판정 너머 조금까지.
## 위를 향한 틀(길이 L × 높이 H, 밑동 y=H, 끝은 위)로 만든 뒤 Thorns.frame_of 로 돌려 상자에 맞춘다:
## 위·아래를 향하면 가로로(L = size.x), 왼쪽·오른쪽을 향하면 세로로(L = size.y) 늘어선다. 판정(Thorns.hit_rect)도 같은 틀이다.
## 가시 끝 높이는 상자 높이 H 의 reach_min~reach_max 배 (밑면에서 잰 값; 1 이면 상자 끝, 판정 끝은 0.7).
func build_thorns(t: Node2D, size: Vector2, facing: int) -> void:
	var t0 := Time.get_ticks_usec()
	_begin(int(size.x) * 5 + int(size.y) * 3 + 11)
	var names := skin.list("thorn")
	if names.is_empty():
		return
	var lh := Thorns.frame_size(size, facing)
	var L := lh.x
	var H := lh.y
	var tint_t: Array = skin.param("thorn", "tint", [1.0, 1.0, 1.0])
	var base_mod := Color(float(tint_t[0]), float(tint_t[1]), float(tint_t[2]))
	var reach_min := float(skin.param("thorn", "reach_min", 0.85))
	var reach_max := float(skin.param("thorn", "reach_max", 1.2))
	var sink := float(skin.param("thorn", "sink", 10.0))
	# 뒤줄(작고 어둡게) → 앞줄(크게) 두 겹
	for layer in 2:
		var x := -12.0 + _rng.randf_range(0.0, 20.0) * layer
		var guard := 0
		while x < L + 4.0 and guard < 200:
			guard += 1
			var n: String = names[_rng.randi_range(0, names.size() - 1)]
			var ps := skin.size_of(n)
			var reach := H * _rng.randf_range(reach_min, reach_max) * (0.78 if layer == 0 else 1.0)
			var th := reach + sink
			var k := th / ps.y
			# 길이가 짧고 높이가 큰 상자(옆을 향한 짧은 가시 등)는 가시를 가로로 눌러 상자 길이 안에 담는다
			var w := minf(ps.x * k, L + 30.0)
			var cx := x + w * 0.5
			var m := base_mod * (0.72 if layer == 0 else 1.0)
			m.a = 1.0
			var y_top := H - reach
			var x0 := cx - w * 0.5
			var x1 := cx + w * 0.5
			# 양 끝 밖으로 크게 삐져나가지 않게
			if x1 > L + 18.0:
				var over := x1 - (L + 18.0)
				x0 -= over
				x1 -= over
			if x0 < -18.0:
				var over2 := -18.0 - x0
				x0 += over2
				x1 += over2
			piece(n, 0.0, ps.x, x0, x1, func(_x): return y_top, k, _rng.randf() < 0.5, {"y_off": 0.0, "mod": Color(_mod.r * m.r, _mod.g * m.g, _mod.b * m.b, 1.0)})
			x += w * _rng.randf_range(0.45, 0.7)
	# 아래·옆을 향한 가시: 틀을 돌려 밑동이 반대쪽 면에 붙게 한다
	transform = Thorns.frame_of(size, facing)
	_finish(t0)

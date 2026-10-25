class_name BloomDecor
extends Node2D
## 정화된 지역의 방에 돋아나는 풀포기·작은 꽃 (v1.1.0 기획자 요청 5 "정화 전후의 환경 변화가 분명하게").
## Purity 가 방에 붙인다 (Room 은 손대지 않는다 — Purity._attach_room_effects / play_purify):
##  - 정화된 지역의 방에 들어오면 다 핀 채로 있다.
##  - 정화 물결(Purity.play_purify) 중에는 물결 테두리가 그 자리를 지날 때 GROW_TIME 초에 걸쳐 살짝 튀어 오르며 돋는다.
##  - 잿빛 지역에는 만들지 않는다 (Purity 가 지운다).
## 자리: 방의 걷는 윗면(발판·경사의 윗선 — 한쪽 방향 발판 포함, 벽·천장·부서지는 벽 제외)을 따라 SPACING_MIN~MAX px 간격.
##   다른 지형에 덮인 곳, 방 경계 밖, 가시 둘레, 수액 웅덩이 둘레에는 두지 않는다. 방 하나에 MAX_TUFTS 포기까지.
## 그리기: 모양 5가지(풀 둘·꽃 핀 풀 둘·어린 나무)를 MultiMesh 로 그린다 (가장자리는 투명해지는 띠로 매끈하게) — 방 하나가 그리기 호출 5번이고, 다 핀 뒤에는 매 프레임 할 일이 없다.
##   바람에 살랑이는 것은 셰이더(정점)가 TIME 으로 한다 (CPU 계산 없음). 색은 지역마다 COLORS 표 (정화 후 색).
## 세기를 바꾸려면 아래 상수만 고친다.

## 포기 사이 간격 (px, 무작위)
const SPACING_MIN := 120.0
const SPACING_MAX := 180.0
## 방 하나의 최대 포기 수 (넘으면 고르게 솎는다)
const MAX_TUFTS := 160
## 물결이 지난 뒤 다 돋을 때까지 (초)
const GROW_TIME := 0.5
## 돋을 때 위로 튀어 오르는 정도: 뒤로 당기는 곡선(ease-out-back)의 세기. 2.43 이면 세로가 최고 약 1.18 배까지 솟았다 돌아온다 (0 = 튀지 않음)
const BACK := 2.43
## 윗면 끝에서 이만큼 안쪽부터 (가지의 둥근 끝에 풀이 떠 보이지 않게)
const END_MARGIN := 28.0
## 이보다 짧은 윗면에는 두지 않는다
const MIN_TOP := 56.0
## 풀 밑동을 윗면보다 이만큼 아래에 (잎 사이에 묻히게 — 지형 그림의 lift 와 비슷하게)
const SINK := 3.0
## 가시·수액 웅덩이 둘레로 비워 두는 너비
const HAZARD_PAD := 48.0
## 크기 (무작위 배율 — 모양 그림은 가장 큰 잎이 50~58px, 소녀 무릎 높이 안팎)
const SIZE_MIN := 0.8
const SIZE_MAX := 1.2
## 바람에 흔들리는 정도 (56px 높이의 끝이 움직이는 px) / 빠르기
const SWAY_PX := 3.0
const SWAY_SPEED := 1.25

## 모양 종류 (MultiMesh 하나씩): 풀 A(빽빽한 일곱 잎) / 풀 B(낮게 퍼진 다섯 잎) / 꽃 하나 / 꽃 셋 / 어린 나무. 고를 비율은 KIND_WEIGHTS.
const KIND_COUNT := 5
const KIND_WEIGHTS := [0.3, 0.25, 0.2, 0.1, 0.15]

## 지역별 색 (정화 후): 잎 밑동 / 잎 끝 / 꽃잎 / 꽃 가운데 / 새싹 잎. 표에 없는 지역은 canopy.
## 지형 장식 팔레트(TerrainStyle)보다 한결 푸르고 맑게 — 잿빛이던 땅이 되살아난 느낌이 들도록.
const COLORS := {
	"canopy": [Color(0.20, 0.36, 0.13), Color(0.64, 0.80, 0.36), Color(0.98, 0.97, 0.90), Color(1.0, 0.82, 0.35), Color(0.50, 0.76, 0.30)],
	"village": [Color(0.30, 0.46, 0.17), Color(0.66, 0.82, 0.36), Color(0.99, 0.92, 0.74), Color(1.0, 0.70, 0.35), Color(0.56, 0.78, 0.30)],
	"mine": [Color(0.30, 0.44, 0.16), Color(0.64, 0.80, 0.32), Color(1.0, 0.88, 0.58), Color(1.0, 0.56, 0.26), Color(0.56, 0.76, 0.28)],
	"flooded_mine": [Color(0.28, 0.44, 0.18), Color(0.60, 0.78, 0.34), Color(1.0, 0.84, 0.62), Color(1.0, 0.52, 0.28), Color(0.52, 0.76, 0.32)],
	"sap_lake": [Color(0.18, 0.42, 0.36), Color(0.48, 0.82, 0.64), Color(0.92, 1.0, 0.96), Color(0.52, 0.90, 0.96), Color(0.44, 0.80, 0.56)],
	"abyss": [Color(0.20, 0.38, 0.34), Color(0.48, 0.78, 0.62), Color(0.86, 0.84, 1.0), Color(0.72, 0.56, 1.0), Color(0.46, 0.76, 0.56)],
}

const SWAY_SHADER := """
shader_type canvas_item;
// 풀포기 살랑임 (BloomDecor): 밑동(y=0)은 그대로, 위로 갈수록 좌우로 흔들린다. 자리마다 박자가 다르다.
uniform float sway_px = 3.0;
uniform float sway_speed = 1.25;
void vertex() {
	float w = clamp(-VERTEX.y / 56.0, 0.0, 1.2);
	float ph = MODEL_MATRIX[3].x * 0.0123 + MODEL_MATRIX[3].y * 0.0071;
	VERTEX.x += (sin(TIME * sway_speed + ph) + 0.35 * sin(TIME * sway_speed * 2.3 + ph * 1.7)) * w * w * sway_px;
}
"""

static var _material: ShaderMaterial
## 지역별 모양 그림(ArrayMesh 5개) — 방마다 다시 만들지 않는다
static var _mesh_cache := {}

var region := "canopy"
var _mms: Array = []                       # MultiMesh (모양 종류마다)
var _pos := PackedVector2Array()           # 포기 자리 (이 노드 기준)
var _kind := PackedInt32Array()            # 모양 종류
var _slot := PackedInt32Array()            # 그 모양 MultiMesh 안의 번호
var _size := PackedFloat32Array()          # 배율
var _flip := PackedFloat32Array()          # ±1
var _tilt := PackedFloat32Array()          # 기울기 (라디안)
var _start := PackedFloat32Array()         # 돋기 시작한 시각 (-1 = 아직, -2 = 다 핌)
var _amount := PackedFloat32Array()        # 지금 돋은 정도 0~1 (시험용)
var _time := 0.0
var _waiting := 0                          # 아직 돋지 않은 수
var _growing := false
## 시험용: 만드는 데 든 시간 (마이크로초)
var build_usec := 0


## 방의 걷는 윗면을 따라 풀포기 자리를 정하고 그림을 만든다. bloomed: 다 핀 채로 시작할지 (false 면 모두 숨긴 채 물결을 기다린다)
func setup(room: Node2D, bloomed: bool) -> void:
	var t0 := Time.get_ticks_usec()
	region = str(room.get("region")) if "region" in room else "canopy"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(room.get("room_id")) if "room_id" in room else room.name)
	var spots := _spots(room, rng)
	var n := spots.size()
	_pos.resize(n)
	_kind.resize(n)
	_slot.resize(n)
	_size.resize(n)
	_flip.resize(n)
	_tilt.resize(n)
	_start.resize(n)
	_amount.resize(n)
	var counts := PackedInt32Array()
	counts.resize(KIND_COUNT)
	counts.fill(0)
	var inv := global_transform.affine_inverse()
	var tints := PackedColorArray()
	tints.resize(n)
	for i in n:
		_pos[i] = inv * (spots[i] as Vector2)
		var k := _pick_kind(rng)
		_kind[i] = k
		_slot[i] = counts[k]
		counts[k] += 1
		_size[i] = rng.randf_range(SIZE_MIN, SIZE_MAX)
		_flip[i] = -1.0 if rng.randf() < 0.5 else 1.0
		_tilt[i] = rng.randf_range(-0.09, 0.09)
		var v := rng.randf_range(0.86, 1.08)
		var hj := rng.randf_range(-0.05, 0.05)
		tints[i] = Color(v * (1.0 + hj), v, v * (1.0 - hj), 1.0)
	var meshes := _meshes(region)
	var bounds: Rect2 = room.get("bounds") if "bounds" in room else Rect2(-4000, -4000, 16000, 16000)
	var lb := Rect2(inv * bounds.position, bounds.size).grow(200.0)
	_mms.clear()
	for k in KIND_COUNT:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.mesh = meshes[k]
		mm.instance_count = counts[k]
		mm.custom_aabb = AABB(Vector3(lb.position.x, lb.position.y, -1.0), Vector3(lb.size.x, lb.size.y, 2.0))
		_mms.append(mm)
	for i in n:
		(_mms[_kind[i]] as MultiMesh).set_instance_color(_slot[i], tints[i])
	if bloomed:
		bloom_all()
	else:
		begin_wave()
	if material == null:
		material = shared_material()
	queue_redraw()
	build_usec = Time.get_ticks_usec() - t0


static func shared_material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SWAY_SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.set_shader_parameter("sway_px", SWAY_PX)
		_material.set_shader_parameter("sway_speed", SWAY_SPEED)
	return _material


func _draw() -> void:
	for mm in _mms:
		if (mm as MultiMesh).instance_count > 0:
			draw_multimesh(mm, null)


## 모두 다 핀 채로 (정화된 지역에 들어올 때, 물결이 끝날 때)
func bloom_all() -> void:
	for i in _pos.size():
		_start[i] = -2.0
		_amount[i] = 1.0
		_set_xf(i, 1.0, 1.0)
	_waiting = 0
	_growing = false
	set_process(false)


## 모두 숨기고 물결을 기다린다 (Purity.play_purify)
func begin_wave() -> void:
	for i in _pos.size():
		_start[i] = -1.0
		_amount[i] = 0.0
		_set_xf(i, 0.0, 0.0)
	_waiting = _pos.size()
	_growing = false
	_time = 0.0
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	if _waiting > 0:
		if Purity.wave_active:
			_catch_wave()
		elif Purity.level >= 0.999:
			# 물결이 끝났다 (화면 밖이라 테두리가 지나지 않은 포기도 이제 돋는다)
			for i in _pos.size():
				if _start[i] == -1.0:
					_start[i] = _time
					_waiting -= 1
					_growing = true
	if _growing:
		_grow()
	if _waiting == 0 and not _growing:
		set_process(false)


## 물결 테두리(화면 높이 단위 반지름)가 지난 포기를 돋기 시작하게 한다 — ash_purify 셰이더와 같은 화면 좌표 계산.
func _catch_wave() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var size := vp.get_visible_rect().size
	if size.y <= 0.0:
		return
	var xf := get_global_transform_with_canvas()
	var c := Purity.wave_center * size
	var r := Purity.wave_radius * size.y
	var r2 := r * r
	for i in _pos.size():
		if _start[i] != -1.0:
			continue
		var d := xf * _pos[i] - c
		if d.length_squared() <= r2:
			_start[i] = _time
			_waiting -= 1
			_growing = true


func _grow() -> void:
	var any := false
	for i in _pos.size():
		var s := _start[i]
		if s < 0.0:
			continue
		var t := (_time - s) / GROW_TIME
		if t >= 1.0:
			_start[i] = -2.0
			_amount[i] = 1.0
			_set_xf(i, 1.0, 1.0)
			continue
		any = true
		_amount[i] = t
		# 세로는 살짝 넘쳤다가 돌아오고(튀어 오름 — 뒤로 당기는 곡선, 최고점 약 1.18 배), 가로는 부드럽게 퍼진다
		var u := t - 1.0
		var gy := 1.0 + (BACK + 1.0) * u * u * u + BACK * u * u
		var gx := 1.0 - pow(1.0 - t, 3.0)
		_set_xf(i, gx, gy)
	_growing = any


func _set_xf(i: int, gx: float, gy: float) -> void:
	var s := _size[i]
	var mm: MultiMesh = _mms[_kind[i]]
	mm.set_instance_transform_2d(_slot[i], Transform2D(_tilt[i] * gy, Vector2(s * _flip[i] * gx, s * gy), 0.0, _pos[i]))


func _pick_kind(rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	var acc := 0.0
	for k in KIND_COUNT:
		acc += float(KIND_WEIGHTS[k])
		if r <= acc:
			return k
	return 0


# ---------------------------------------------------------------- 시험용
func count() -> int:
	return _pos.size()


## 다 돋은 포기 수
func bloomed_count() -> int:
	var n := 0
	for a in _amount:
		if a >= 1.0:
			n += 1
	return n


## 돋기 시작했거나 다 돋은 포기 수
func started_count() -> int:
	var n := 0
	for st in _start:
		if st != -1.0:
			n += 1
	return n


## 포기 자리 (전역 좌표)
func global_spots() -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(_pos.size())
	var xf := global_transform
	for i in _pos.size():
		out[i] = xf * _pos[i]
	return out


func draw_call_count() -> int:
	var n := 0
	for mm in _mms:
		if (mm as MultiMesh).instance_count > 0:
			n += 1
	return n


# ---------------------------------------------------------------- 자리 고르기
## 방의 걷는 윗면 [a, b] (전역 좌표, 왼→오). 발판(Platform)은 윗변 — 벽·천장(장식 끔이면서 얇지 않은 것)과 부서지는 벽은 뺀다.
## 경사(TerrainPolygon)는 위를 보는 변 (TerrainArt._edge_kind == 0).
static func walk_tops(room: Node) -> Array:
	var out := []
	var terrain := room.get_node_or_null("Terrain")
	if terrain == null:
		return out
	for t in terrain.get_children():
		out.append_array(walk_tops_of(t))
	return out


## 방의 지형 모양 (덮임 확인용): [노드, Rect2 또는 전역 다각형]. 부서지는 벽도 넣는다 (방에 들어올 때 그 자리에 있으므로).
static func _solids(room: Node) -> Array:
	var out := []
	var terrain := room.get_node_or_null("Terrain")
	if terrain == null:
		return out
	for t in terrain.get_children():
		if t is Platform:
			out.append([t, Rect2((t as Node2D).global_position, t.size)])
		elif t is TerrainPolygon:
			out.append([t, Transform2D(0.0, (t as Node2D).global_position) * ((t as TerrainPolygon).polygon as PackedVector2Array)])
	return out


static func _covered(solids: Array, me: Node, gp: Vector2) -> bool:
	for s in solids:
		if s[0] == me:
			continue
		if s[1] is Rect2:
			if (s[1] as Rect2).has_point(gp):
				return true
		elif Geometry2D.is_point_in_polygon(gp, s[1]):
			return true
	return false


## 비워 둘 곳: 가시·수액 웅덩이 둘레 (전역 Rect2)
static func _keep_out(room: Node) -> Array:
	var out := []
	for th in room.find_children("*", "Thorns", true, false):
		out.append(Rect2((th as Node2D).global_position, th.size).grow(HAZARD_PAD))
	for sp in room.find_children("*", "SapPool", true, false):
		out.append(Rect2((sp as Node2D).global_position, sp.size).grow(HAZARD_PAD))
	return out


## 포기 자리들 (전역 좌표, 밑동 = 윗면 + SINK)
func _spots(room: Node, rng: RandomNumberGenerator) -> Array:
	var solids := _solids(room)
	var keep_out := _keep_out(room)
	var bounds: Rect2 = room.get("bounds") if "bounds" in room else Rect2()
	var inner := bounds.grow(-16.0) if bounds.has_area() else Rect2()
	var terrain := room.get_node_or_null("Terrain")
	var tops := []
	if terrain:
		for t in terrain.get_children():
			for seg in walk_tops_of(t):
				tops.append([t, seg[0], seg[1]])
	var out := []
	for tp in tops:
		var me: Node = tp[0]
		var a: Vector2 = tp[1]
		var b: Vector2 = tp[2]
		var w := b.x - a.x
		if w < MIN_TOP:
			continue
		var xs := PackedFloat32Array()
		if w < END_MARGIN * 2.0 + SPACING_MIN * 0.5:
			xs.append(a.x + w * 0.5)
		else:
			var x := a.x + END_MARGIN + rng.randf_range(0.0, SPACING_MIN * 0.5)
			while x <= b.x - END_MARGIN:
				xs.append(x)
				x += rng.randf_range(SPACING_MIN, SPACING_MAX)
		for x in xs:
			var y := lerpf(a.y, b.y, (x - a.x) / maxf(w, 0.001))
			var gp := Vector2(x, y)
			if inner.has_area() and not inner.has_point(gp + Vector2(0, -8)):
				continue
			if _covered(solids, me, gp + Vector2(0, -10)) or _covered(solids, me, gp + Vector2(0, -34)):
				continue
			var bad := false
			for r in keep_out:
				if (r as Rect2).has_point(gp):
					bad = true
					break
			if bad:
				continue
			out.append(gp + Vector2(0, SINK))
	if out.size() > MAX_TUFTS:
		var thin := []
		var step := float(out.size()) / float(MAX_TUFTS)
		for i in MAX_TUFTS:
			thin.append(out[int(i * step)])
		out = thin
	return out


## 지형 노드 하나의 걷는 윗면들 (walk_tops 의 노드 하나 판)
static func walk_tops_of(t: Node) -> Array:
	var out := []
	if t is SecretWall or t is CrackedWall:
		return out
	if t is Platform:
		var p := t as Platform
		if not p.decorate and not p._is_thin():
			return out
		var o := p.global_position
		out.append([o, o + Vector2(p.size.x, 0.0)])
	elif t is TerrainPolygon:
		var poly: PackedVector2Array = (t as TerrainPolygon).polygon
		var o2 := (t as Node2D).global_position
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			if TerrainArt._edge_kind(b - a) == 0:
				out.append([o2 + a, o2 + b])
	return out


# ---------------------------------------------------------------- 모양 그림
## 모양 그림 하나 (묘목 sprout.gd 가 어린 나무 그림을 같이 쓴다)
static func kind_mesh(reg: String, kind: int) -> Mesh:
	return _meshes(reg)[clampi(kind, 0, KIND_COUNT - 1)]


## 지역의 모양 그림을 미리 만들어 둔다 (한 번만). Purity 가 방에 들어올 때 부른다 —
## 잿빛 방에서 처음 쓰러진 적의 묘목(sprout.gd)이 쓰러지는 순간(히트스톱 프레임)에 그림을 만드느라 끊기지 않게.
static func warm(reg: String) -> void:
	_meshes(reg)


## 그 지역의 모양 그림이 이미 있는가 (시험용)
static func is_warm(reg: String) -> bool:
	return _mesh_cache.has(reg)


## 나눠 쓰는 모양 그림·재질을 놓는다 (게임이 끝날 때 Purity 가 부른다 — 끝날 때 '남은 그림' 경고가 나지 않게)
static func release() -> void:
	_mesh_cache.clear()
	_material = null


## 지역의 모양 그림 5개 (한 번 만들고 나눠 쓴다). 크기는 소녀(키 약 132)의 무릎 높이 안팎.
static func _meshes(reg: String) -> Array:
	if _mesh_cache.has(reg):
		return _mesh_cache[reg]
	var pal: Array = COLORS.get(reg, COLORS["canopy"])
	var dark: Color = pal[0]
	var light: Color = pal[1]
	var petal: Color = pal[2]
	var core: Color = pal[3]
	var leaf: Color = pal[4]
	var back_d := dark.darkened(0.25)
	var back_l := light.darkened(0.22)
	var out := []
	# 풀 A: 빽빽한 일곱 잎 (뒤 잎은 어둡게, 가운데가 가장 길다)
	var g := _Geo.new()
	g.shadow(Vector2(0, 0), 26.0, 6.0)
	g.blade(Vector2(-7, 0), -0.62, 28.0, 4.8, -0.22, back_d, back_l)
	g.blade(Vector2(7, 0), 0.58, 26.0, 4.8, 0.24, back_d, back_l)
	g.blade(Vector2(-4, 0), -0.34, 42.0, 5.2, -0.2, dark, light.darkened(0.06))
	g.blade(Vector2(4, 0), 0.3, 40.0, 5.2, 0.22, dark, light.darkened(0.06))
	g.blade(Vector2(-2, 0), -0.12, 52.0, 5.6, -0.1, dark, light)
	g.blade(Vector2(2, 0), 0.1, 48.0, 5.6, 0.14, dark, light)
	g.blade(Vector2(0, 0), 0.0, 58.0, 5.2, 0.06, dark, light.lightened(0.1))
	out.append(g.mesh())
	# 풀 B: 낮고 넓게 퍼진 다섯 잎
	g = _Geo.new()
	g.shadow(Vector2(0, 0), 30.0, 6.0)
	g.blade(Vector2(-6, 0), -0.95, 24.0, 4.8, -0.35, back_d, back_l)
	g.blade(Vector2(6, 0), 0.92, 23.0, 4.8, 0.36, back_d, back_l)
	g.blade(Vector2(-3, 0), -0.5, 34.0, 5.2, -0.3, dark, light)
	g.blade(Vector2(3, 0), 0.46, 32.0, 5.2, 0.3, dark, light)
	g.blade(Vector2(0, 0), -0.06, 40.0, 5.2, -0.12, dark, light.lightened(0.06))
	out.append(g.mesh())
	# 꽃 하나: 잎 넷 + 줄기 위 큰 꽃 + 꽃봉오리
	g = _Geo.new()
	g.shadow(Vector2(0, 0), 24.0, 5.5)
	g.blade(Vector2(-5, 0), -0.6, 26.0, 4.8, -0.25, back_d, back_l)
	g.blade(Vector2(5, 0), 0.56, 24.0, 4.8, 0.25, back_d, back_l)
	g.blade(Vector2(-2, 0), -0.28, 32.0, 4.8, -0.15, dark, light)
	var bud := g.blade(Vector2(3, 0), 0.34, 34.0, 2.6, 0.12, dark.darkened(0.1), dark.lerp(light, 0.5))
	var tip := g.blade(Vector2(0, 0), -0.06, 54.0, 3.2, -0.05, dark.darkened(0.1), dark.lerp(light, 0.55))
	g.blade(Vector2(1, 0), 0.16, 30.0, 4.8, 0.18, dark, light)
	g.flower(tip, 9.5, petal, core)
	g.dot(bud, 3.2, petal.darkened(0.08))
	out.append(g.mesh())
	# 꽃 셋: 잎 셋 + 줄기 셋 (크고 작은 꽃)
	g = _Geo.new()
	g.shadow(Vector2(0, 0), 28.0, 6.0)
	g.blade(Vector2(-6, 0), -0.7, 24.0, 4.8, -0.3, back_d, back_l)
	g.blade(Vector2(6, 0), 0.66, 22.0, 4.8, 0.3, back_d, back_l)
	var t1 := g.blade(Vector2(-3, 0), -0.26, 46.0, 2.8, -0.08, dark.darkened(0.1), dark.lerp(light, 0.5))
	var t2 := g.blade(Vector2(3, 0), 0.3, 38.0, 2.6, 0.1, dark.darkened(0.1), dark.lerp(light, 0.5))
	var t3 := g.blade(Vector2(0, 0), 0.04, 30.0, 2.4, 0.04, dark.darkened(0.1), dark.lerp(light, 0.5))
	g.blade(Vector2(0, 0), -0.05, 30.0, 4.8, -0.08, dark, light)
	g.flower(t1, 8.0, petal, core)
	g.flower(t2, 4.8, petal.lerp(core, 0.12), core)
	g.flower(t3, 5.5, petal, core)
	out.append(g.mesh())
	# 어린 나무: 줄기 + 잎 넷 (쓰러진 적이 남기는 묘목과 같은 결)
	g = _Geo.new()
	g.shadow(Vector2(0, 0), 20.0, 5.0)
	var st := g.blade(Vector2(0, 0), 0.02, 44.0, 4.2, 0.04, dark.darkened(0.2), dark.lerp(leaf, 0.4))
	var mid := Vector2(st.x * 0.55, st.y * 0.55)
	g.leaf(mid, -1.15, 17.0, 8.0, leaf.darkened(0.18), leaf)
	g.leaf(mid + Vector2(1, -2), 1.1, 16.0, 5.6, leaf.darkened(0.18), leaf)
	g.leaf(st, -0.55, 18.0, 8.5, leaf.darkened(0.1), leaf.lightened(0.14))
	g.leaf(st, 0.6, 17.0, 8.0, leaf.darkened(0.1), leaf.lightened(0.14))
	out.append(g.mesh())
	_mesh_cache[reg] = out
	return out


## 삼각형 모으기 도우미 (밑동 = 원점, 위 = −y). 모든 도형 둘레에 FRINGE px 의 투명해지는 띠를 붙여 가장자리가 매끈하다
## (다각형은 계단이 지는데, 바깥 띠의 알파가 0 으로 이어져 그래픽 카드가 부드럽게 섞는다 — 안티에일리어싱 대신).
class _Geo:
	const FRINGE := 1.3
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()

	func _v(p: Vector2, c: Color) -> int:
		pts.append(p)
		cols.append(c)
		return pts.size() - 1

	func _tri(a: int, b: int, c: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(c)

	func _quad(a: int, b: int, c: int, d: int) -> void:
		_tri(a, b, c)
		_tri(a, c, d)

	## 잎 한 장 (밑동 base 에서 끝으로 가늘어지는 굽은 띠). lean: 기울기(라디안), bend: 끝으로 갈수록 휘는 정도. 끝 자리를 돌려준다.
	func blade(base: Vector2, lean: float, h: float, w: float, bend: float, c0: Color, c1: Color) -> Vector2:
		var n := 4
		var li := PackedInt32Array()
		var ri := PackedInt32Array()
		var lo := PackedInt32Array()
		var ro := PackedInt32Array()
		var tip := Vector2.ZERO
		var tip_dir := Vector2.UP
		for k in n + 1:
			var t := float(k) / float(n)
			var c := base + Vector2(sin(lean) * h * t + bend * h * t * t, -cos(lean) * h * t)
			var tn := Vector2(sin(lean) + 2.0 * bend * t, -cos(lean)).normalized()
			var nrm := Vector2(-tn.y, tn.x)
			var col := c0.lerp(c1, t)
			var clear := Color(col.r, col.g, col.b, 0.0)
			if k == n:
				tip = c
				tip_dir = tn
				break
			var hw := w * 0.5 * pow(1.0 - t, 0.7)
			li.append(_v(c - nrm * hw, col))
			ri.append(_v(c + nrm * hw, col))
			lo.append(_v(c - nrm * (hw + FRINGE), clear))
			ro.append(_v(c + nrm * (hw + FRINGE), clear))
		var c_tip := c1
		var ti := _v(tip, c_tip)
		var to := _v(tip + tip_dir * FRINGE * 1.6, Color(c_tip.r, c_tip.g, c_tip.b, 0.0))
		for k in n - 1:
			_quad(li[k], ri[k], ri[k + 1], li[k + 1])
			_quad(lo[k], li[k], li[k + 1], lo[k + 1])
			_quad(ri[k], ro[k], ro[k + 1], ri[k + 1])
		var e := n - 1
		_tri(li[e], ri[e], ti)
		_quad(lo[e], li[e], ti, to)
		_quad(ri[e], ro[e], to, ti)
		return tip

	## 볼록한 둘레(ring, 중심 center)를 채우고 바깥에 투명 띠를 붙인다. col_in: 가운데 색, ring_cols: 둘레 색
	func fan(center: Vector2, ring: PackedVector2Array, col_in: Color, ring_cols: PackedColorArray) -> void:
		var ci := _v(center, col_in)
		var m := ring.size()
		var inner := PackedInt32Array()
		var outer := PackedInt32Array()
		for i in m:
			var p := ring[i]
			var d := (p - center).normalized()
			var c := ring_cols[i]
			inner.append(_v(p, c))
			outer.append(_v(p + d * FRINGE, Color(c.r, c.g, c.b, 0.0)))
		for i in m:
			var j := (i + 1) % m
			_tri(ci, inner[i], inner[j])
			_quad(inner[i], outer[i], outer[j], inner[j])

	## 꽃 (다섯 꽃잎 + 가운데)
	func flower(at: Vector2, r: float, petal: Color, core: Color) -> void:
		for i in 5:
			var a := -PI * 0.5 + TAU * float(i) / 5.0 + 0.2
			var d := Vector2(cos(a), sin(a))
			var s := Vector2(-d.y, d.x)
			var ring := PackedVector2Array()
			var rc := PackedColorArray()
			var pc := at + d * r * 0.55
			for k in 8:
				var u := TAU * float(k) / 8.0
				ring.append(pc + d * cos(u) * r * 0.5 + s * sin(u) * r * 0.32)
				rc.append(petal.lerp(petal.lightened(0.12), maxf(cos(u), 0.0)))
			fan(pc, ring, petal.darkened(0.06), rc)
		dot(at, r * 0.3, core)

	## 동그란 점 (꽃 가운데·꽃봉오리)
	func dot(at: Vector2, r: float, col: Color) -> void:
		var ring := PackedVector2Array()
		var rc := PackedColorArray()
		for k in 8:
			var u := TAU * float(k) / 8.0
			ring.append(at + Vector2(cos(u), sin(u)) * r)
			rc.append(col.darkened(0.12))
		fan(at, ring, col.lightened(0.15), rc)

	## 잎 (줄기 위 at 에서 angle 쪽으로 길이 l, 폭 w — 끝이 뾰족한 볼록 둘레)
	func leaf(at: Vector2, angle: float, l: float, w: float, c0: Color, c1: Color) -> void:
		var d := Vector2(sin(angle), -cos(angle))
		var s := Vector2(-d.y, d.x)
		var ring := PackedVector2Array()
		var rc := PackedColorArray()
		var m := 10
		for i in m:
			var u := TAU * float(i) / float(m)
			var along := (1.0 - cos(u)) * 0.5   # 0 밑동 → 1 끝 → 0
			var side := sin(u) * w * 0.5 * pow(sin(along * PI * 0.5 + 0.0001), 0.6) * (1.0 - along * 0.35)
			ring.append(at + d * along * l + s * side)
			rc.append(c0.lerp(c1, along))
		fan(at + d * l * 0.45, ring, c0.lerp(c1, 0.5), rc)

	## 밑동 그림자 (땅에 붙어 보이게: 가운데만 살짝 어둡고 둘레는 투명)
	func shadow(at: Vector2, rx: float, ry: float) -> void:
		var ci := _v(at + Vector2(0, -1), Color(0.0, 0.0, 0.0, 0.26))
		var m := 12
		var ring := PackedInt32Array()
		for i in m:
			var u := TAU * float(i) / float(m)
			ring.append(_v(at + Vector2(cos(u) * rx, sin(u) * ry - 1.0), Color(0.0, 0.0, 0.0, 0.0)))
		for i in m:
			_tri(ci, ring[i], ring[(i + 1) % m])

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pts
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

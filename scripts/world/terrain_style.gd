class_name TerrainStyle
extends RefCounted
## 지역별 지형 팔레트와 장식 규칙 (2026-10-19 기획자 요청: 지형지물 디테일 업그레이드).
## ※ 코드로 그리는 옛 지형이다. 그림 옷(TerrainSkin, data/terrain/<지역>.json)이 생긴 지역은 그림 조각 지형(TerrainArt)으로 그린다 — TERRAIN.md.
## 발판(Platform)·경사(TerrainPolygon)·가시(Thorns)가 이 표 하나를 같이 쓴다. 방 파일은 손대지 않는다:
## 각 지형이 조상 Room 의 region 을 읽어 팔레트를 고른다 (Room 이 없으면 수관).
##
## 눈에 보이는 디테일은 '실루엣 가장자리'에 모았다 (지형 몸통은 거의 검은색이라 안쪽 무늬는 평소 배율에서 묻힌다):
##  - 윗선: 이끼 무더기(가끔 큰 무더기)·잎·꽃·잘린 잔가지, 덩어리 모서리에 걸쳐 늘어진 이끼.
##  - 아랫선: 가지 밑과 드러난 덩어리 밑에 늘어진 이끼 수염·뿌리 가닥·잎 달린 덩굴, 가지 끝 잎 묶음.
##  - 안쪽: 윗면이 빛을 받은 밝은 띠(깊이 glow_depth) + 대비를 올린 껍질 결·홈·옹이(나뭇결이 옹이를 돌아 흐른다).
##  - 지역 장식: 수관 흰 꽃 / 마을 등불빛 반사 / 채굴장 윗선에 박힌 금속판·가지를 감은 띠쇠(리벳 한 줄)·사슬 /
##    심연 발광 버섯(어두운 방에서는 몇 무리가 실제로 주변을 밝힌다) / 수액의 호수 수액 방울·구슬·윤기 /
##    잠긴 채굴장 붉은 녹물·수액 번짐.
##  - 아랫면이 다른 지형에 묻힌 곳(옆 지형에 덮인 곳)에는 매달린 것·이끼를 그리지 않는다. 거미줄은 안쪽 구석에만.
##
## 그리기 비용: 채운 도형(이끼·잎·꽃·돌·버섯…)은 노드마다 삼각형 배열 하나(Batch)로 모아 한 번에 보낸다.
##  옛 코드는 도형마다 draw_circle/draw_colored_polygon 을 불러, 실제 화면(맥)에서 도형 하나에 약 9µs 가 들었다.
##  모아 보내면 하나에 1µs 안팎이다. 선(결·뿌리·덩굴 줄기)은 원래도 싼 draw_line 을 그대로 쓴다.
##  정화 연출 중 바뀌는 윗면 빛 테두리는 따로 떼어 둔 '겹'(Layer)만 다시 그린다 (몸통·장식은 다시 안 그림).
##
## 기획자가 세기를 조절하려면:
##  - 지역별 색·밀도는 아래 REGIONS 표 (…_px 는 "몇 px 마다 하나", 0 이면 안 그림).
##  - 발판 하나당 최대 개수는 CAP 표 (아주 긴 바닥이 너무 무거워지지 않게 막는 상한).
##  - detail: 0 = 기본(옛 수준: 결·이끼·잎·덩굴만), 1 = 상세. tools/probe_terrain 이 옛 코드와 그리기 비용을 비교한다.

## 장식 세기 (0 기본 / 1 상세)
static var detail := 1
## 시험용: true 면 어떤 장식을 몇 개 그렸는지 trace_counts["꽃"] 처럼 세고, 일부는 자리도 남긴다(trace_points).
static var trace := false
static var trace_counts := {}
## 시험용 자리 기록: [종류, 노드, 노드 기준 좌표]. 종류 "안:*" = 몸통 안에 있어야 하는 것, "밑:*" = 매달린 것의 뿌리 자리.
static var trace_points: Array = []
static var trace_node: Node = null

const DEFAULT_REGION := "canopy"
## 겹 종류: 윗면 빛(테두리·빛 띠 — one_way 점선은 v1.1.0 에 없앰) / 장식(이끼·잎·매달린 것)
const LAYER_EDGE := 0
const LAYER_DECOR := 1
## 어두운 방에서 실제로 빛을 내는 버섯 무리 수 (방 하나에 이만큼까지)
const GLOW_LIGHTS_PER_ROOM := 8

## 모든 지역의 바탕값. 지역 표(REGIONS)가 덮어쓴다.
const BASE := {
	"name": "수관",
	# 이끼·잎·덩굴
	"moss": Color(0.42, 0.52, 0.24), "moss_light": Color(0.72, 0.76, 0.36),
	"vine": Color(0.13, 0.17, 0.10), "leaf": Color(0.40, 0.55, 0.22), "leaf_light": Color(0.66, 0.74, 0.34),
	"moss_density": 1.0,            # 이끼 덩어리 양 (1 = 옛 수준)
	"beard_px": 150.0,              # 가지 밑·덩어리 모서리에 늘어진 이끼 수염 (무리 하나당 px)
	"grass_px": 64.0,               # 윗선의 풀 포기 (가는 잎 2~3장, 실루엣에서 가장 잘 읽힌다)
	"sprig_px": 260.0,              # 윗선에 돋은 새싹 줄기 (잎 2~3장)
	# 지역 장식 (…_px: 몇 px 마다 하나. 0 = 없음)
	"flower": Color(0.97, 0.96, 0.88), "flower_core": Color(1.0, 0.86, 0.45), "flower_px": 0.0,
	"glint": Color(1.15, 0.95, 0.55), "glint_px": 0.0,                    # 등불빛 반사 (마을)
	"mushroom_cap": Color(1.25, 0.85, 1.5), "mushroom_glow": Color(0.9, 0.55, 1.2), "mushroom_stem": Color(0.82, 0.74, 0.9), "mushroom_px": 0.0,
	"metal": Color(0.36, 0.35, 0.33), "metal_light": Color(0.62, 0.60, 0.55), "rust": Color(0.52, 0.26, 0.13), "bolt": Color(0.58, 0.54, 0.48),
	"plate_px": 0.0, "strap_px": 0.0, "chain_px": 0.0, "rust_px": 0.0,
	"sap": Color(0.30, 0.62, 0.82, 0.8), "sap_light": Color(0.80, 1.0, 1.1), "drip_px": 0.0, "smear_px": 0.0, "bead_px": 0.0,
	"sheen": false,                   # 윗면의 젖은 윤기 띠
	# 껍질 (몸통 안): 결이 몸통색을 얼마나 밝히나 / 투명도, 홈·옹이 간격, 윗면 빛 띠 깊이
	"bark_lift": 0.26, "bark_alpha": 0.75,
	"ridge_px": 230.0, "ridge_area": 26000.0, "knot_px": 380.0,
	"glow_depth": 24.0,
	# 아래 매달린 것
	"root": Color(0.17, 0.14, 0.09), "root_px": 170.0,
	"stone": Color(0.30, 0.29, 0.26), "stone_light": Color(0.52, 0.51, 0.47), "stone_px": 420.0,
	"web": Color(0.95, 0.95, 0.9), "web_p": 0.5,      # 안쪽 구석(옆 지형과 만나는 곳)에 거미줄이 걸릴 확률
	# 가시
	"thorn_tip": Color(0.72, 0.66, 0.5), "thorn_glow": Color(1.15, 1.08, 0.9),
}

## 지역별 덮어쓰기. 키는 Room.region.
const REGIONS := {
	"canopy": {
		"name": "수관",
		"flower_px": 140.0,
	},
	"village": {
		"name": "가지 위의 마을",
		"moss": Color(0.50, 0.46, 0.22), "moss_light": Color(0.80, 0.70, 0.36), "leaf": Color(0.52, 0.48, 0.20), "leaf_light": Color(0.78, 0.66, 0.32),
		"flower": Color(0.98, 0.90, 0.72), "flower_core": Color(1.0, 0.70, 0.35), "flower_px": 170.0,
		"glint_px": 140.0, "beard_px": 220.0, "grass_px": 80.0, "sprig_px": 380.0, "web_p": 0.35,
		"thorn_tip": Color(0.76, 0.66, 0.46),
	},
	"mine": {
		"name": "채굴장",
		# 녹 낀 황토·올리브 이끼: 검은 몸통과 붉은 배경 모두에 대비되게 (옛 수관 이끼와 거의 같은 양)
		"moss": Color(0.54, 0.46, 0.22), "moss_light": Color(0.78, 0.64, 0.30), "leaf": Color(0.50, 0.42, 0.20), "leaf_light": Color(0.72, 0.58, 0.28),
		"moss_density": 0.9,
		"plate_px": 520.0, "strap_px": 420.0, "chain_px": 520.0, "rust_px": 230.0,
		"beard_px": 0.0, "grass_px": 170.0, "sprig_px": 0.0, "web_p": 0.6,
		"root_px": 260.0, "stone": Color(0.34, 0.30, 0.27), "stone_light": Color(0.56, 0.48, 0.40),
		"thorn_tip": Color(0.66, 0.50, 0.38), "thorn_glow": Color(1.15, 0.95, 0.8),
	},
	"abyss": {
		"name": "뿌리의 심연",
		"moss": Color(0.40, 0.28, 0.50), "moss_light": Color(0.66, 0.50, 0.80), "leaf": Color(0.42, 0.30, 0.52), "leaf_light": Color(0.62, 0.48, 0.76),
		"vine": Color(0.14, 0.10, 0.17),
		"mushroom_px": 170.0, "web_p": 0.6, "root_px": 130.0, "beard_px": 140.0, "grass_px": 95.0, "sprig_px": 420.0,
		"root": Color(0.16, 0.12, 0.18), "stone": Color(0.28, 0.24, 0.32), "stone_light": Color(0.50, 0.44, 0.58),
		"thorn_tip": Color(0.70, 0.56, 0.78), "thorn_glow": Color(1.1, 0.9, 1.3),
	},
	"sap_lake": {
		"name": "수액의 호수",
		"moss": Color(0.26, 0.48, 0.46), "moss_light": Color(0.50, 0.78, 0.72), "leaf": Color(0.28, 0.50, 0.46), "leaf_light": Color(0.52, 0.78, 0.70),
		"vine": Color(0.10, 0.16, 0.16),
		"drip_px": 110.0, "bead_px": 130.0, "smear_px": 400.0, "sheen": true, "web_p": 0.25,
		"beard_px": 260.0, "grass_px": 85.0, "sprig_px": 380.0,
		"root_px": 200.0, "stone": Color(0.24, 0.32, 0.36), "stone_light": Color(0.46, 0.60, 0.66),
		"thorn_tip": Color(0.56, 0.70, 0.78), "thorn_glow": Color(0.95, 1.15, 1.3),
	},
	"flooded_mine": {
		"name": "잠긴 채굴장",
		"moss": Color(0.50, 0.34, 0.22), "moss_light": Color(0.72, 0.48, 0.30), "leaf": Color(0.46, 0.32, 0.20), "leaf_light": Color(0.66, 0.46, 0.28),
		"moss_density": 0.8,
		"metal": Color(0.34, 0.24, 0.20), "metal_light": Color(0.58, 0.42, 0.34), "rust": Color(0.66, 0.28, 0.12), "bolt": Color(0.60, 0.48, 0.40),
		"plate_px": 560.0, "strap_px": 480.0, "chain_px": 700.0, "rust_px": 90.0,
		"sap": Color(0.28, 0.66, 0.72, 0.75), "sap_light": Color(0.78, 1.0, 1.05), "drip_px": 220.0, "smear_px": 350.0,
		"beard_px": 0.0, "grass_px": 200.0, "sprig_px": 0.0, "web_p": 0.5, "root_px": 300.0,
		"stone": Color(0.34, 0.26, 0.22), "stone_light": Color(0.56, 0.42, 0.34),
		"thorn_tip": Color(0.70, 0.40, 0.28), "thorn_glow": Color(1.25, 0.9, 0.7),
	},
}

## 발판 하나당 장식 최대 개수 (아주 긴 바닥도 이 이상은 안 그린다 → 그리기 비용 상한)
const CAP := {
	"moss": 220, "leaf": 90, "streak": 200, "ridge": 40, "knot": 10,
	"flower": 30, "glint": 30, "mushroom": 20, "plate": 6, "strap": 8, "chain": 8,
	"rust": 40, "drip": 40, "bead": 30, "smear": 12, "root": 26, "stone": 10,
	"beard": 30, "grass": 90, "sprig": 14, "vine": 14,
}

## 미리 만든 단위 도형 (삼각형 목록). Transform2D 로 자리·크기·회전만 바꿔 Batch 에 붙인다.
static var CIRCLE_T := PackedVector2Array()   # 10각형
static var STAR_T := PackedVector2Array()     # 다섯 잎 꽃
static var STONE_T := PackedVector2Array()    # 울퉁불퉁한 돌
static var CAP_T := PackedVector2Array()      # 버섯 갓 (반원, 위가 -y)
static var DROP_T := PackedVector2Array()     # 물방울 (뾰족한 쪽이 위)
static var SMEAR_T := PackedVector2Array()    # 번짐 얼룩

static var _cache := {}
static var _glow_tex: GradientTexture2D


static func _static_init() -> void:
	CIRCLE_T = _fan_first(_ngon(10))
	var star := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		var r := 1.0 if i % 2 == 0 else 0.45
		star.append(Vector2(cos(a), sin(a)) * r)
	STAR_T = _fan_center(star)
	STONE_T = _fan_first(PackedVector2Array([Vector2(1.0, 0.0), Vector2(0.55, 0.62), Vector2(-0.35, 0.72), Vector2(-1.0, 0.2), Vector2(-0.85, -0.5), Vector2(-0.1, -0.78), Vector2(0.7, -0.6)]))
	var cap := PackedVector2Array()
	for i in 7:
		var a := PI * i / 6.0
		cap.append(Vector2(cos(a), -sin(a) * 0.75))
	CAP_T = _fan_first(cap)
	DROP_T = _fan_first(PackedVector2Array([Vector2(0.0, -1.7), Vector2(0.707, -0.764), Vector2(1.0, 0.0), Vector2(0.707, 0.764), Vector2(0.0, 1.08), Vector2(-0.707, 0.764), Vector2(-1.0, 0.0), Vector2(-0.707, -0.764)]))
	SMEAR_T = _fan_first(PackedVector2Array([Vector2(1.1, 0.0), Vector2(0.75, 0.75), Vector2(0.0, 1.0), Vector2(-0.8, 0.7), Vector2(-1.0, -0.1), Vector2(-0.6, -0.85), Vector2(0.1, -1.0), Vector2(0.85, -0.65)]))


static func _ngon(n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(Vector2(cos(a), sin(a)))
	return out


## 볼록 다각형 → 첫 점 기준 부채꼴 삼각형 목록
static func _fan_first(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, poly.size() - 1):
		out.append(poly[0])
		out.append(poly[i])
		out.append(poly[i + 1])
	return out


## 원점 기준 별 모양 다각형 → 원점 부채꼴 삼각형 목록
static func _fan_center(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		out.append(Vector2.ZERO)
		out.append(poly[i])
		out.append(poly[(i + 1) % poly.size()])
	return out


## 채운 도형을 모아 두었다가 한 번에 보내는 삼각형 배열 (노드 하나의 겹 하나에 하나).
## 선은 여기 넣지 않고 draw_line 으로 바로 그린다 → flush 하면 모은 도형이 선 위에 올라간다.
class Batch extends RefCounted:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var _fill := PackedColorArray()

	## 단위 도형(삼각형 목록)을 xf 로 옮겨 붙인다.
	func shape(unit: PackedVector2Array, xf: Transform2D, col: Color) -> void:
		var t := xf * unit
		pts.append_array(t)
		if _fill.size() != t.size():
			_fill.resize(t.size())
		_fill.fill(col)
		cols.append_array(_fill)

	func circle(c: Vector2, r: float, col: Color) -> void:
		var t := Transform2D(0.0, Vector2(r, r), 0.0, c) * TerrainStyle.CIRCLE_T
		pts.append_array(t)
		if _fill.size() != t.size():
			_fill.resize(t.size())
		_fill.fill(col)
		cols.append_array(_fill)

	func ellipse(c: Vector2, rx: float, ry: float, rot: float, col: Color) -> void:
		var t := Transform2D(rot, Vector2(rx, ry), 0.0, c) * TerrainStyle.CIRCLE_T
		pts.append_array(t)
		if _fill.size() != t.size():
			_fill.resize(t.size())
		_fill.fill(col)
		cols.append_array(_fill)

	func tri(a: Vector2, b: Vector2, c: Vector2, col: Color) -> void:
		pts.append(a)
		pts.append(b)
		pts.append(c)
		cols.append(col)
		cols.append(col)
		cols.append(col)

	## a→b→c→d 순서의 볼록 사각형
	func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
		pts.append(a)
		pts.append(b)
		pts.append(c)
		pts.append(a)
		pts.append(c)
		pts.append(d)
		cols.append(col)
		cols.append(col)
		cols.append(col)
		cols.append(col)
		cols.append(col)
		cols.append(col)

	## 꼭짓점마다 색이 다른 사각형 (빛 띠처럼 서서히 사라지는 것)
	func quad_c(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
		pts.append(a)
		pts.append(b)
		pts.append(c)
		pts.append(a)
		pts.append(c)
		pts.append(d)
		cols.append(ca)
		cols.append(cb)
		cols.append(cc)
		cols.append(ca)
		cols.append(cc)
		cols.append(cd)

	func rect(p: Vector2, s: Vector2, col: Color) -> void:
		quad(p, p + Vector2(s.x, 0), p + s, p + Vector2(0, s.y), col)

	## 끝이 뾰족한 잎 하나. dir 은 잎이 기우는 방향(±1), up 은 잎이 뻗는 쪽(단위 벡터).
	func leaf(p: Vector2, s: float, dir: float, up: Vector2, col: Color) -> void:
		var side := Vector2(-up.y, up.x) * (dir * s)
		var u := up * s
		var b := p + side * 0.9 + u * 1.1
		var c := p + side * 0.45 + u * 2.0
		pts.append(p)
		pts.append(b)
		pts.append(c)
		pts.append(p)
		pts.append(c)
		pts.append(p - side * 0.1 + u * 1.1)
		cols.append(col)
		cols.append(col)
		cols.append(col)
		cols.append(col)
		cols.append(col)
		cols.append(col)

	## 모은 도형을 ci 에 한 번에 보낸다 (ci 의 _draw 안에서만 부른다).
	func flush(ci: CanvasItem) -> void:
		if pts.size() >= 3:
			RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), PackedInt32Array(), pts, cols)
		pts = PackedVector2Array()
		cols = PackedColorArray()


## 지형의 '겹': 윗면 빛(정화 연출 때 자주 바뀜)과 장식을 몸통과 따로 그린다.
## 그림은 host(Platform / TerrainPolygon)의 _draw_layer 가 그린다. 잿빛 재질은 부모 것을 쓴다.
class Layer extends Node2D:
	var host: Node
	var kind := 0

	func _init(h: Node = null, k := 0) -> void:
		host = h
		kind = k
		use_parent_material = true

	func _draw() -> void:
		if host and host.has_method("_draw_layer"):
			host._draw_layer(self, kind)


# ---------------------------------------------------------------- 표·지역
## 지역 이름 → 팔레트(바탕값 + 지역 덮어쓰기). 모르는 지역은 수관.
static func get_style(region: String) -> Dictionary:
	if _cache.has(region):
		return _cache[region]
	var st := BASE.duplicate()
	var over: Dictionary = REGIONS.get(region, REGIONS[DEFAULT_REGION])
	for k in over:
		st[k] = over[k]
	st["region"] = region if REGIONS.has(region) else DEFAULT_REGION
	_cache[region] = st
	return st


## 조상 중 Room(region 속성이 있는 것)
static func room_of(node: Node) -> Node:
	var n := node.get_parent()
	while n != null:
		if "region" in n:
			return n
		n = n.get_parent()
	return null


## 지형 노드의 조상 Room 의 지역. 없으면 수관.
static func region_of(node: Node) -> String:
	var n := node.get_parent()
	while n != null:
		if "region" in n:
			var r = n.get("region")
			if r is String and r != "":
				return r
		n = n.get_parent()
	return DEFAULT_REGION


## 어두운 방(Room.dark) 안인가
static func is_dark(node: Node) -> bool:
	var room := room_of(node)
	return room != null and "dark" in room and bool(room.get("dark"))


## 지형 노드가 쓸 팔레트. override 가 비어 있지 않으면 그 지역을 강제로 쓴다 (시험·특수 발판).
static func style_for(node: Node, override := "") -> Dictionary:
	return get_style(override if override != "" else region_of(node))


## "길이 len 에 px 마다 하나" 를 상한(cap 표의 key)까지. px 0 이면 없음.
static func n_of(len: float, px: float, key: String) -> int:
	if px <= 0.0:
		return 0
	return mini(int(len / px), int(CAP.get(key, 999)))


static func _tick(kind: String) -> void:
	if trace:
		trace_counts[kind] = int(trace_counts.get(kind, 0)) + 1


## 시험용 자리 기록 (trace 가 켜져 있을 때만)
static func _mark(kind: String, p: Vector2) -> void:
	if trace:
		trace_points.append([kind, trace_node, p])


## 꺾은선 위의 점 (t 0~1, 꼭짓점 번호 기준 — 장식 자리로는 충분하다)
static func point_on(poly: PackedVector2Array, t: float) -> Vector2:
	if poly.size() == 0:
		return Vector2.ZERO
	if poly.size() == 1:
		return poly[0]
	var f := clampf(t, 0.0, 0.9999) * (poly.size() - 1)
	var i := int(f)
	return poly[i].lerp(poly[i + 1], f - i)


# ---------------------------------------------------------------- 옆 지형 (덮인 자리)
## 같은 부모 아래 다른 지형(발판·경사)의 모양을 node 기준 좌표로 모은다. local_box 근처의 것만.
## 돌려주는 배열의 원소: Rect2(발판) 또는 PackedVector2Array(경사 다각형).
static func neighbor_shapes(node: Node2D, local_box: Rect2) -> Array:
	var out := []
	var parent := node.get_parent()
	if parent == null:
		return out
	var box := local_box.grow(24.0)
	for s in parent.get_children():
		if s == node or not (s is Node2D):
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


static func is_covered(shapes: Array, p: Vector2) -> bool:
	for s in shapes:
		if s is Rect2:
			if (s as Rect2).has_point(p):
				return true
		elif Geometry2D.is_point_in_polygon(p, s):
			return true
	return false


## 표본 점마다 옆 지형에 덮였는지 (1 = 덮임). 덮인 곳이 하나도 없으면 빈 배열(검사 생략).
static func cover_flags(shapes: Array, samples: PackedVector2Array) -> PackedByteArray:
	var out := PackedByteArray()
	if shapes.is_empty():
		return out
	out.resize(samples.size())
	var any := false
	for i in samples.size():
		var c := is_covered(shapes, samples[i])
		out[i] = 1 if c else 0
		any = any or c
	return out if any else PackedByteArray()


## a→b 위를 step px 마다, 바깥쪽(normal)으로 off 떨어진 표본
static func line_samples(a: Vector2, b: Vector2, normal: Vector2, off: float, step := 12.0) -> PackedVector2Array:
	var n := maxi(1, int(a.distance_to(b) / step))
	var out := PackedVector2Array()
	for i in n:
		out.append(a.lerp(b, (i + 0.5) / n) + normal * off)
	return out


static func covered(flags: PackedByteArray, t: float) -> bool:
	var n := flags.size()
	if n == 0:
		return false
	return flags[clampi(int(t * n), 0, n - 1)] == 1


# ---------------------------------------------------------------- 몸통 안 (껍질)
## 나뭇결: 밝은 가는 선. 몸통 안에서만 부른다 (끝점은 부르는 쪽이 몸통 안으로 맞춘다).
static func draw_grain(ci: CanvasItem, p: Vector2, q: Vector2, col: Color, width := 2.0) -> void:
	ci.draw_line(p, q, col, width, true)
	if trace:
		_tick("결")
		_mark("안:결", p)
		_mark("안:결", q)


## 껍질 홈: 어두운 갈라짐 + 바로 아래 빛 받은 입술 (지형이 어두워서 보이는 건 입술 쪽이다).
static func draw_ridge(ci: CanvasItem, rng: RandomNumberGenerator, p: Vector2, len: float, body: Color, st: Dictionary) -> void:
	var mid := p + Vector2(len * 0.5, rng.randf_range(-2.0, 2.0))
	var q := p + Vector2(len, rng.randf_range(-1.5, 1.5))
	var dark := body.darkened(0.55)
	ci.draw_line(p, mid, dark, 2.4, true)
	ci.draw_line(mid, q, dark, 2.4, true)
	var lip := body.lightened(float(st["bark_lift"]) + 0.12)
	lip.a = 0.6
	ci.draw_line(p + Vector2(2, 1.8), mid + Vector2(0, 1.8), lip, 1.5, true)
	ci.draw_line(mid + Vector2(0, 1.8), q + Vector2(-2, 1.8), lip, 1.5, true)
	if trace:
		_tick("홈")
		_mark("안:홈", p)
		_mark("안:홈", q + Vector2(0, 1.8))


## 옹이: 끝이 뾰족한 아몬드 모양의 어두운 속 + 위쪽에만 빛 받은 테(빛이 위에서 온다), 위로 나뭇결이 옹이를 돌아 흐른다.
## (둥근 고리 두 개가 나란히 있으면 눈처럼 보여서, 테는 위쪽 초승달로만 둔다)
static func draw_knot(b: Batch, ci: CanvasItem, rng: RandomNumberGenerator, p: Vector2, r: float, body: Color, st: Dictionary) -> void:
	var rx := r * rng.randf_range(1.2, 1.6)
	var ry := r * rng.randf_range(0.42, 0.58)
	var lift := float(st["bark_lift"])
	var flow := body.lightened(lift)
	flow.a = 0.6
	var top := p.y - ry - 4.0
	ci.draw_line(Vector2(p.x - rx * 2.0, p.y + ry * 0.3), Vector2(p.x - rx * 0.8, top), flow, 2.0, true)
	ci.draw_line(Vector2(p.x - rx * 0.8, top), Vector2(p.x + rx * 0.8, top), flow, 2.0, true)
	ci.draw_line(Vector2(p.x + rx * 0.8, top), Vector2(p.x + rx * 2.0, p.y + ry * 0.3), flow, 2.0, true)
	var rot := rng.randf_range(-0.1, 0.1)
	var xf := Transform2D(rot, Vector2(1, 1), 0.0, p)
	var rim := body.lightened(lift + 0.08)
	var a0 := xf * Vector2(-rx - 2.0, 0.0)
	var a1 := xf * Vector2(-rx * 0.45, -ry - 2.2)
	var a2 := xf * Vector2(rx * 0.45, -ry - 2.2)
	var a3 := xf * Vector2(rx + 2.0, 0.0)
	b.quad(a0, a1, a2, a3, rim)
	var dark := body.darkened(0.55)
	var k0 := xf * Vector2(-rx, 0.0)
	var k1 := xf * Vector2(-rx * 0.45, -ry)
	var k2 := xf * Vector2(rx * 0.45, -ry)
	var k3 := xf * Vector2(rx, 0.0)
	var k4 := xf * Vector2(rx * 0.45, ry)
	var k5 := xf * Vector2(-rx * 0.45, ry)
	b.quad(k0, k1, k2, k3, dark)
	b.quad(k0, k3, k4, k5, dark)
	if trace:
		_tick("옹이")
		_mark("안:옹이", p + Vector2(-rx * 2.0, ry * 0.3))
		_mark("안:옹이", p + Vector2(rx * 2.0, ry * 0.3))
		_mark("안:옹이", Vector2(p.x, top))
		_mark("안:옹이", p + Vector2(0, ry + 1.0))


## 리벳(볼트 머리): 둥근 머리 + 밝은 반짝임 점.
static func draw_rivet(b: Batch, p: Vector2, st: Dictionary) -> void:
	var c: Color = st["bolt"]
	b.circle(p, 2.6, c.darkened(0.35))
	b.circle(p + Vector2(-0.3, -0.3), 2.0, c)
	b.circle(p + Vector2(-0.8, -0.8), 0.9, c.lightened(0.55))
	if trace:
		_tick("볼트")
		_mark("안:볼트", p)


## 윗선에 박힌 금속판: 위 가장자리가 지형 윗면과 맞닿는다(떠 보이지 않게). 위·아래 가장자리에 리벳 한 줄, 아래로 녹물.
## max_bottom: 녹물이 내려갈 수 있는 가장 낮은 y (몸통 안).
static func draw_plate(b: Batch, ci: CanvasItem, rng: RandomNumberGenerator, x: float, pw: float, ph: float, max_bottom: float, st: Dictionary) -> void:
	var metal: Color = st["metal"]
	var rust: Color = st["rust"]
	var y0 := 1.0
	# 녹물 줄 (판 아래로) — 선이라 판보다 먼저 그려진다
	for k in rng.randi_range(1, 2):
		var rx := x + rng.randf_range(6.0, pw - 6.0)
		var top := y0 + ph - 2.0
		var bot := minf(top + rng.randf_range(10.0, 28.0), max_bottom)
		if bot > top + 3.0:
			draw_rust_line(ci, rng, Vector2(rx, top), bot - top, st)
	b.rect(Vector2(x, y0), Vector2(pw, ph), metal)
	b.rect(Vector2(x, y0), Vector2(pw, 2.0), st["metal_light"])
	var bx := x + rng.randf_range(pw * 0.2, pw * 0.6)
	b.quad(Vector2(bx, y0 + 2.0), Vector2(bx + rng.randf_range(8.0, pw * 0.35), y0 + 2.0), Vector2(bx + rng.randf_range(3.0, pw * 0.25), y0 + ph), Vector2(bx - 3.0, y0 + ph * 0.6), Color(rust.r, rust.g, rust.b, 0.7))
	var n := clampi(int((pw - 8.0) / 15.0), 2, 8)
	for i in n:
		var rxp := x + 5.0 + (pw - 10.0) * i / (n - 1)
		draw_rivet(b, Vector2(rxp, y0 + 4.5), st)
	if trace:
		_tick("금속판")
		_mark("안:금속판", Vector2(x, y0 + ph))
		_mark("안:금속판", Vector2(x + pw, y0 + ph))


## 띠쇠: 가지를 감거나(가지) 윗선 모서리에 걸친(덩어리) 금속 띠. 윗선 위로 2.5px 솟아 실루엣에서도 읽힌다.
## y1: 띠의 아래 끝 (가지는 아랫선, 덩어리는 윗면에서 조금 아래).
static func draw_strap(b: Batch, ci: CanvasItem, rng: RandomNumberGenerator, x: float, y1: float, wraps: bool, st: Dictionary) -> void:
	var sw := rng.randf_range(10.0, 14.0)
	var y0 := -2.5
	var bottom := y1 + (2.5 if wraps else 0.0)
	var col: Color = (st["metal_light"] as Color).darkened(0.3)
	if not wraps:
		draw_rust_line(ci, rng, Vector2(x + sw * 0.5, bottom - 2.0), rng.randf_range(8.0, 18.0), st)
	b.rect(Vector2(x, y0), Vector2(sw, bottom - y0), col)
	b.rect(Vector2(x, y0), Vector2(2.0, bottom - y0), st["metal_light"])
	b.rect(Vector2(x + sw - 2.0, y0), Vector2(2.0, bottom - y0), col.darkened(0.35))
	draw_rivet(b, Vector2(x + sw * 0.5, 4.5), st)
	if bottom - y0 > 22.0:
		draw_rivet(b, Vector2(x + sw * 0.5, bottom - 5.0), st)
	if trace:
		_tick("띠쇠")


## 녹물 자국: 위에서 아래로 흐른 붉은 줄 (len 은 부르는 쪽이 몸통 안으로 맞춘다).
static func draw_rust_line(ci: CanvasItem, rng: RandomNumberGenerator, p: Vector2, len: float, st: Dictionary) -> void:
	var rust: Color = st["rust"]
	var col := Color(rust.r, rust.g, rust.b, rng.randf_range(0.45, 0.7))
	var w := rng.randf_range(1.6, 2.8)
	var mid := p + Vector2(rng.randf_range(-1.5, 1.5), len * 0.5)
	var q := p + Vector2(rng.randf_range(-2.0, 2.0), len)
	ci.draw_line(p, mid, col, w, true)
	ci.draw_line(mid, q, col, w * 0.7, true)
	if trace:
		_tick("녹물")
		_mark("안:녹물", p)
		_mark("안:녹물", q)


## 젖은 윤기: 윗면을 따라 흐르는 밝은 띠 (수액의 호수). 몸통 안쪽.
static func draw_sheen(b: Batch, top: PackedVector2Array, st: Dictionary) -> void:
	if top.size() < 2:
		return
	var c: Color = st["sap_light"]
	c = Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0))   # 발광(HDR) 없이, 은은하게
	var clear := Color(c.r, c.g, c.b, 0.0)
	for i in top.size() - 1:
		var t0 := float(i) / (top.size() - 1)
		var t1 := float(i + 1) / (top.size() - 1)
		var c0 := Color(c.r, c.g, c.b, 0.06 + 0.16 * sin(t0 * PI))
		var c1 := Color(c.r, c.g, c.b, 0.06 + 0.16 * sin(t1 * PI))
		var p := top[i] + Vector2(0, 3.0)
		var q := top[i + 1] + Vector2(0, 3.0)
		b.quad_c(p, q, q + Vector2(0, 8.0), p + Vector2(0, 8.0), c0, c1, clear, clear)
	if trace:
		_tick("윤기")


# ---------------------------------------------------------------- 윗면 빛 (겹: LAYER_EDGE)
## 윗면 바로 아래의 빛 띠 (빛을 받은 윗면). top 은 왼→오 꺾은선. 띠는 윗선 2px 아래부터 depth 만큼.
static func draw_top_glow(b: Batch, top: PackedVector2Array, edge: Color, depth: float) -> void:
	if top.size() < 2 or depth < 2.0:
		return
	var hi := Color(edge.r, edge.g, edge.b, edge.a * 0.36)
	var lo := Color(edge.r, edge.g, edge.b, 0.0)
	var down := Vector2(0, depth)
	var off := Vector2(0, 2.4)
	var step := 2 if top.size() > 8 else 1
	var i := 0
	while i < top.size() - 1:
		var j := mini(i + step, top.size() - 1)
		var p := top[i] + off
		var q := top[j] + off
		b.quad_c(p, q, q + down, p + down, hi, hi, lo, lo)
		i = j
	if trace:
		_tick("윗면빛")


## 기운 변(a→b, 바깥 법선 up)의 빛 띠 — 경사용. 띠는 변의 안쪽(-up)으로 depth 만큼.
static func draw_edge_glow(b: Batch, a: Vector2, e: Vector2, up: Vector2, edge: Color, depth: float) -> void:
	var hi := Color(edge.r, edge.g, edge.b, edge.a * 0.36)
	var lo := Color(edge.r, edge.g, edge.b, 0.0)
	var p := a - up * 2.0
	var q := e - up * 2.0
	b.quad_c(p, q, q - up * depth, p - up * depth, hi, hi, lo, lo)
	if trace:
		_tick("윗면빛")


# ---------------------------------------------------------------- 윗면 장식 (겹: LAYER_DECOR)
## 윗면(a→e, 왼→오) 장식: 이끼 무더기 + 잎 + 풀 포기 + 새싹 + 지역 장식(꽃/반사빛/버섯/구슬/번짐).
## mc/ml 은 이끼 색(수상한 발판은 창백). detailed 가 false 면 옛 수준(이끼·잎만).
## cover: 옆 지형에 덮인 자리 표(cover_flags, a→e 기준) — 덮인 곳은 건너뛴다. spots: 버섯 자리를 모으는 배열(어두운 방 빛).
static func draw_top_decor(b: Batch, ci: CanvasItem, rng: RandomNumberGenerator, st: Dictionary, a: Vector2, e: Vector2, mc: Color, ml: Color, detailed: bool, cover: PackedByteArray, spots: Array) -> void:
	var dir := e - a
	var len := dir.length()
	if len < 12.0:
		return
	var tang := dir / len
	var up := Vector2(tang.y, -tang.x)
	var nc := cover.size()
	var density: float = st["moss_density"]
	var n_moss := mini(int(len / 24.0 * density), CAP["moss"])
	for i in n_moss:
		var t := rng.randf()
		var r := rng.randf_range(4.5, 10.5) if detailed else rng.randf_range(4.0, 9.5)
		var col := mc.lerp(ml, rng.randf() * 0.5)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		var p := a.lerp(e, t)
		b.circle(p + up * (r * 0.3), r, col)
		if detailed and i % 7 == 3:
			# 가끔 큰 이끼 무더기: 윗선 실루엣이 울퉁불퉁해 보인다
			var r2 := r * 0.7 + 4.0
			b.circle(p + tang * (r * 0.9) + up * (r2 * 0.3), r2, mc.lerp(ml, 0.12))
			b.circle(p - tang * (r * 0.9) + up * (r2 * 0.15), r2 * 0.75, mc.lerp(ml, 0.3))
			b.circle(p + up * (r2 * 0.75), r2 * 0.55, mc.lerp(ml, 0.55))
		if trace:
			_tick("이끼")
	var n_leaf := mini(int(len / 60.0 * maxf(density, 0.6)), CAP["leaf"])
	var leaf: Color = st["leaf"]
	var light: Color = st["leaf_light"]
	for i in n_leaf:
		var t := rng.randf_range(0.03, 0.97)
		var s := rng.randf_range(6.0, 10.5)
		var d := 1.0 if rng.randf() < 0.5 else -1.0
		var col := (leaf.lerp(light, rng.randf() * 0.7)).darkened(rng.randf() * 0.25)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		b.leaf(a.lerp(e, t) + up * 1.5, s, d, (up + tang * (d * 0.35)).normalized(), col)
		if trace:
			_tick("잎")
	if not detailed:
		return
	for i in n_of(len, st["grass_px"], "grass"):
		var t := rng.randf_range(0.03, 0.97)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		draw_grass(b, rng, a.lerp(e, t), up, tang, leaf, light)
	for i in n_of(len, st["sprig_px"], "sprig"):
		var t := rng.randf_range(0.08, 0.92)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		draw_sprig(b, rng, a.lerp(e, t), up, tang, st)
	for i in n_of(len, st["flower_px"], "flower"):
		var t := rng.randf_range(0.04, 0.96)
		var h := rng.randf_range(5.0, 11.0)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		draw_flower(b, rng, a.lerp(e, t) + up * h, st)
		if rng.randf() < 0.25:
			draw_flower(b, rng, a.lerp(e, t) + tang * rng.randf_range(7.0, 11.0) + up * (h * 0.6), st, 0.7)
	for i in n_of(len, st["glint_px"], "glint"):
		var t := rng.randf_range(0.05, 0.95)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		draw_glint(b, ci, rng, a.lerp(e, t) + up * 1.0, tang, st)
	for i in n_of(len, st["mushroom_px"], "mushroom"):
		var t := rng.randf_range(0.05, 0.95)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		var p := a.lerp(e, t) + up * 1.0
		draw_mushrooms(b, ci, rng, p, up, st)
		spots.append(p + up * 10.0)
	for i in n_of(len, st["bead_px"], "bead"):
		var t := rng.randf_range(0.04, 0.96)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		draw_bead(b, rng, a.lerp(e, t), up, st)
	for i in n_of(len, st["smear_px"], "smear"):
		var t := rng.randf_range(0.08, 0.92)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		draw_smear(b, rng, a.lerp(e, t) + up * 1.0, tang, st)


## 풀 포기: 가는 잎 2~4장이 살짝 휘어 솟는다 (윗선 실루엣의 대표 디테일).
static func draw_grass(b: Batch, rng: RandomNumberGenerator, p: Vector2, up: Vector2, tang: Vector2, leaf: Color, light: Color) -> void:
	var n := rng.randi_range(2, 3)
	for k in n:
		var off := (k - (n - 1) * 0.5)
		var base := p + tang * (off * rng.randf_range(2.5, 4.0)) - up * 1.5
		var hgt := rng.randf_range(9.0, 19.0)
		var tip := base + up * hgt + tang * ((rng.randf_range(-0.5, 0.5) + off * 0.3) * hgt * 0.7)
		var sw := tang * rng.randf_range(1.3, 1.9)
		b.tri(base - sw, base + sw, tip, leaf.lerp(light, rng.randf() * 0.55))
	if trace:
		_tick("풀")


## 새싹 줄기: 짧은 줄기에 잎 2~3장 (잘린 그루터기 대신 — 검은 뾰족한 모양은 가시처럼 보일 수 있다).
static func draw_sprig(b: Batch, rng: RandomNumberGenerator, p: Vector2, up: Vector2, tang: Vector2, st: Dictionary) -> void:
	var leaf: Color = st["leaf"]
	var light: Color = st["leaf_light"]
	var vine: Color = st["vine"]
	var lean := rng.randf_range(-0.35, 0.35)
	var dirv := (up + tang * lean).normalized()
	var l := rng.randf_range(12.0, 22.0)
	var side := Vector2(-dirv.y, dirv.x)
	var base := p - up * 2.0
	var tip := p + dirv * l
	b.quad(base - side * 1.4, base + side * 1.4, tip + side * 0.7, tip - side * 0.7, vine.lerp(leaf, 0.35))
	var n := rng.randi_range(2, 3)
	for k in n:
		var q := p + dirv * (l * (0.45 + 0.55 * k / maxf(n - 1, 1)))
		var d := 1.0 if k % 2 == 0 else -1.0
		b.leaf(q, rng.randf_range(4.5, 7.0), d, (dirv + side * (d * 0.9)).normalized(), leaf.lerp(light, rng.randf() * 0.7))
	if trace:
		_tick("새싹")


## 작은 꽃: 다섯 잎 별 모양 + 가운데 점.
static func draw_flower(b: Batch, rng: RandomNumberGenerator, p: Vector2, st: Dictionary, scale := 1.0) -> void:
	var r := rng.randf_range(6.0, 8.5) * scale
	var fc: Color = st["flower"]
	b.shape(STAR_T, Transform2D(rng.randf() * TAU, Vector2(r, r), 0.0, p), fc.darkened(rng.randf() * 0.12))
	b.circle(p, r * 0.32, st["flower_core"])
	if trace:
		_tick("꽃")


## 등불빛 반사: 짧은 가로 빛줄 + 빛점 (마을).
static func draw_glint(b: Batch, ci: CanvasItem, rng: RandomNumberGenerator, p: Vector2, tang: Vector2, st: Dictionary) -> void:
	var c: Color = st["glint"]
	var len := rng.randf_range(12.0, 26.0)
	ci.draw_line(p - tang * len, p + tang * len, Color(c.r, c.g, c.b, 0.28), 2.0, true)
	b.circle(p, rng.randf_range(2.0, 3.0), Color(c.r, c.g, c.b, 0.9))
	if trace:
		_tick("반사빛")


## 발광 버섯 한 무리 (1~3개): 빛 무리 + 대 + 갓.
static func draw_mushrooms(b: Batch, ci: CanvasItem, rng: RandomNumberGenerator, p: Vector2, up: Vector2, st: Dictionary) -> void:
	var n := rng.randi_range(1, 3)
	var glow: Color = st["mushroom_glow"]
	var side := Vector2(-up.y, up.x)
	var rot := up.angle() + PI * 0.5
	var stem: Color = st["mushroom_stem"]
	var cap_col: Color = st["mushroom_cap"]
	b.circle(p + up * 8.0, rng.randf_range(15.0, 21.0) + n * 2.5, Color(glow.r, glow.g, glow.b, 0.16))
	for i in n:
		var off := side * ((i - (n - 1) * 0.5) * rng.randf_range(7.0, 10.0))
		var hgt := rng.randf_range(9.0, 16.0) * (1.0 if i != 1 else 1.25)
		var cap := rng.randf_range(5.0, 8.5)
		var base := p + off
		var top := base + up * hgt
		ci.draw_line(base, top, stem, 2.6, true)
		b.shape(CAP_T, Transform2D(rot, Vector2(cap, cap), 0.0, top), cap_col)
		b.circle(top + up * (cap * 0.35) - side * (cap * 0.3), cap * 0.18, Color(1.6, 1.4, 1.7))
	if trace:
		_tick("버섯")


## 윗면 위에 맺힌 수액 구슬.
static func draw_bead(b: Batch, rng: RandomNumberGenerator, p: Vector2, up: Vector2, st: Dictionary) -> void:
	var r := rng.randf_range(3.0, 5.0)
	b.circle(p + up * (r * 0.6), r, st["sap"])
	b.circle(p + up * (r * 0.9) + Vector2(-r * 0.3, 0), r * 0.32, st["sap_light"])
	if trace:
		_tick("구슬")


## 수액 번짐: 반투명 얼룩.
static func draw_smear(b: Batch, rng: RandomNumberGenerator, p: Vector2, tang: Vector2, st: Dictionary) -> void:
	var sap: Color = st["sap"]
	b.shape(SMEAR_T, Transform2D(tang.angle() + rng.randf_range(-0.2, 0.2), Vector2(rng.randf_range(16.0, 36.0), rng.randf_range(3.5, 6.5)), 0.0, p), Color(sap.r, sap.g, sap.b, 0.42))
	if trace:
		_tick("번짐")


## 가지 끝의 잎 묶음 (4~5장 부채꼴). dir: 가지 끝이 향한 방향(±1).
static func draw_leaf_bundle(b: Batch, rng: RandomNumberGenerator, p: Vector2, dir: float, st: Dictionary) -> void:
	var n := rng.randi_range(4, 5)
	var leaf: Color = st["leaf"]
	var light: Color = st["leaf_light"]
	for i in n:
		var a := -PI * 0.5 + (PI * 0.95) * (float(i) / maxf(n - 1, 1) - 0.5) * dir + PI * 0.18 * dir
		var up := Vector2(cos(a), sin(a))
		b.leaf(p, rng.randf_range(7.5, 12.0), dir, up, leaf.lerp(light, rng.randf() * 0.6))
	if trace:
		_tick("잎묶음")


## 늘어진 덩굴: 줄 + 좌우로 번갈아 난 잎 (옛 마름모 잎과 비슷한 크기).
static func draw_vine(b: Batch, ci: CanvasItem, rng: RandomNumberGenerator, p: Vector2, len: float, sway: float, st: Dictionary, detailed: bool) -> void:
	var vine: Color = st["vine"]
	var leaf: Color = st["leaf"]
	ci.draw_line(p, p + Vector2(sway, len), vine, 2.0, true)
	if not detailed:
		for j in 3:
			var tt := float(j + 1) / 4.0
			var q := p + Vector2(sway * tt, len * tt)
			b.quad(q, q + Vector2(-6, 8), q + Vector2(0, 16), q + Vector2(6, 8), vine.lightened(0.15))
		if trace:
			_tick("덩굴")
		return
	var n := clampi(int(len / 22.0), 2, 5)
	for j in n:
		var tt := float(j + 1) / (n + 0.6)
		var q := p + Vector2(sway * tt, len * tt)
		var d := 1.0 if j % 2 == 0 else -1.0
		b.leaf(q, rng.randf_range(5.5, 8.0), d, Vector2(d * 0.7, 0.72).normalized(), vine.lerp(leaf, 0.5).lightened(rng.randf() * 0.15))
	# 끝의 작은 잎
	b.leaf(p + Vector2(sway, len), rng.randf_range(4.0, 5.5), 1.0 if sway < 0.0 else -1.0, Vector2(0, 1), vine.lerp(leaf, 0.4))
	if trace:
		_tick("덩굴")


## 늘어진 이끼 수염 한 무리: 가는 줄 3~5가닥 (실루엣 아래로 드러난다).
## b 가 있으면 매달린 자리에 작은 이끼 덩어리도 붙인다.
static func draw_beard(ci: CanvasItem, rng: RandomNumberGenerator, p: Vector2, mc: Color, max_len := 40.0, b: Batch = null) -> void:
	var col := mc.darkened(0.32)
	var n := rng.randi_range(4, 6)
	for k in n:
		var q := p + Vector2((k - (n - 1) * 0.5) * rng.randf_range(2.6, 4.2), -1.0)
		var l := rng.randf_range(12.0, max_len)
		var sway := rng.randf_range(-3.5, 3.5)
		ci.draw_line(q, q + Vector2(sway, l), col, 2.2, true)
	if b != null:
		b.circle(p + Vector2(0, 1.0), rng.randf_range(4.0, 6.5), mc.darkened(0.12))
		b.circle(p + Vector2(rng.randf_range(-6.0, 6.0), 2.5), rng.randf_range(3.0, 4.5), mc.darkened(0.22))
	if trace:
		_tick("수염")


## 늘어진 뿌리 가닥: 끝으로 갈수록 가늘어지는 꺾은선 + 잔뿌리 하나.
static func draw_root(ci: CanvasItem, rng: RandomNumberGenerator, p: Vector2, len: float, st: Dictionary, thick: bool) -> void:
	var col: Color = st["root"]
	var sway := rng.randf_range(-14.0, 14.0)
	var w0 := 3.6 if thick else 2.6
	var p1 := p + Vector2(sway * 0.4, len * 0.35)
	var p2 := p + Vector2(sway * 0.9, len * 0.7)
	var p3 := p + Vector2(sway, len)
	ci.draw_line(p, p1, col, w0, true)
	ci.draw_line(p1, p2, col, w0 * 0.65, true)
	ci.draw_line(p2, p3, col, w0 * 0.35, true)
	ci.draw_line(p1, p1 + Vector2(-sway * 0.7, 7.0 + absf(sway) * 0.5), col, w0 * 0.35, true)
	if trace:
		_tick("뿌리")


## 아래에 박혀 매달린 돌: 울퉁불퉁한 돌 + 위쪽 빛.
static func draw_stone(b: Batch, rng: RandomNumberGenerator, p: Vector2, r: float, st: Dictionary) -> void:
	var rot := rng.randf() * TAU
	var sy := r * rng.randf_range(0.65, 0.9)
	b.shape(STONE_T, Transform2D(rot, Vector2(r, sy), 0.0, p), st["stone"])
	b.ellipse(p + Vector2(-r * 0.25, -sy * 0.3), r * 0.42, sy * 0.3, 0.0, st["stone_light"])
	if trace:
		_tick("돌")


## 매달린 쇠사슬 조각: 고리 몇 개가 아래로 (밝은 고리 + 어두운 속).
static func draw_chain(b: Batch, rng: RandomNumberGenerator, p: Vector2, st: Dictionary) -> void:
	var links := rng.randi_range(4, 8)
	var col: Color = st["metal_light"]
	var inner: Color = (st["metal"] as Color).darkened(0.6)
	var sway := rng.randf_range(-0.25, 0.25)
	var q := p
	for i in links:
		q += Vector2(sway * 6.0, 6.5)
		if i % 2 == 0:
			b.ellipse(q, 2.8, 3.9, 0.0, col)
			b.ellipse(q, 1.2, 2.3, 0.0, inner)
		else:
			b.ellipse(q, 1.4, 3.6, 0.0, col.darkened(0.15))
	if trace:
		_tick("사슬")


## 매달린 수액 방울 (가는 줄 + 물방울 + 반짝임).
static func draw_drip(b: Batch, ci: CanvasItem, rng: RandomNumberGenerator, p: Vector2, st: Dictionary) -> void:
	var len := rng.randf_range(6.0, 22.0)
	var r := rng.randf_range(3.0, 4.8)
	var sap: Color = st["sap"]
	ci.draw_line(p, p + Vector2(0, len), Color(sap.r, sap.g, sap.b, sap.a * 0.6), 1.6, true)
	var c := p + Vector2(0, len + r)
	b.shape(DROP_T, Transform2D(0.0, Vector2(r, r), 0.0, c), sap)
	b.circle(c + Vector2(-r * 0.3, -r * 0.2), r * 0.3, st["sap_light"])
	if trace:
		_tick("방울")


## 거미줄: 안쪽 구석(corner)에서 dir_x·dir_y 쪽으로 펼쳐진 부채꼴 (실 4줄 + 가로줄 3줄).
static func draw_web(ci: CanvasItem, corner: Vector2, dir_x: float, dir_y: float, size: float, st: Dictionary) -> void:
	var c: Color = st["web"]
	var col := Color(c.r, c.g, c.b, 0.24)
	var spokes: Array[Vector2] = []
	for i in 4:
		var a := (PI * 0.5) * i / 3.0
		spokes.append(Vector2(cos(a) * dir_x, sin(a) * dir_y))
	for s in spokes:
		ci.draw_line(corner, corner + s * size, col, 1.0, true)
	for k in 3:
		var rr := size * (0.3 + 0.23 * k)
		for i in 3:
			ci.draw_line(corner + spokes[i] * rr, corner + spokes[i + 1] * rr * (1.0 - 0.06 * (k % 2)), col, 1.0, true)
	if trace:
		_tick("거미줄")


## 덩어리 윗모서리에 걸친 이끼: 모서리 이끼 덩어리 + 옆면 바깥으로 늘어진 수염.
## corner: 모서리 점, out: 옆면 바깥쪽(왼쪽 -1, 오른쪽 +1).
static func draw_corner_drape(b: Batch, ci: CanvasItem, rng: RandomNumberGenerator, corner: Vector2, out: float, mc: Color, ml: Color, beards: bool) -> void:
	if beards:
		for k in rng.randi_range(2, 3):
			draw_beard(ci, rng, corner + Vector2(out * rng.randf_range(1.0, 4.0), rng.randf_range(4.0, 16.0)), mc, 50.0)
	b.circle(corner + Vector2(-out * 4.0, -2.0), rng.randf_range(8.0, 11.0), mc.lerp(ml, 0.2))
	b.circle(corner + Vector2(out * 1.0, 5.0), rng.randf_range(6.0, 8.5), mc.lerp(ml, 0.05))
	b.circle(corner + Vector2(out * 2.0, 14.0), rng.randf_range(4.0, 6.0), mc.darkened(0.12))
	if trace:
		_tick("모서리이끼")


## 아랫선(bottom 꺾은선, 왼→오)에 매달린 것: 이끼 수염·뿌리 가닥·돌·사슬·방울.
## thick 가 false(얇은 가지)면 뿌리는 드물고 짧다, 돌은 없다. cover 로 덮인 자리(다른 지형 속)는 건너뛴다.
static func draw_bottom_decor(b: Batch, ci: CanvasItem, rng: RandomNumberGenerator, st: Dictionary, bottom: PackedVector2Array, len: float, thick: bool, cover: PackedByteArray, mc: Color) -> void:
	if bottom.size() < 2 or len < 40.0:
		return
	var nc := cover.size()
	for i in n_of(len, st["beard_px"] * (1.0 if not thick else 1.4), "beard"):
		var t := rng.randf_range(0.05, 0.95)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		var p := point_on(bottom, t)
		_mark("밑:수염", p)
		draw_beard(ci, rng, p, mc, 40.0, b)
	var root_px: float = st["root_px"] * (1.0 if thick else 2.6)
	for i in n_of(len, root_px, "root"):
		var t := rng.randf_range(0.03, 0.97)
		var l := rng.randf_range(30.0, 120.0) if thick else rng.randf_range(22.0, 64.0)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		var p := point_on(bottom, t) + Vector2(0, -1)
		_mark("밑:뿌리", p)
		if trace:
			trace_points.append(["뿌리길이", trace_node, Vector2(l, 1.0 if thick else 0.0)])
		draw_root(ci, rng, p, l, st, thick)
	if thick:
		for i in n_of(len, st["stone_px"], "stone"):
			var t := rng.randf_range(0.05, 0.95)
			var r := rng.randf_range(5.0, 11.0)
			if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
				continue
			var p := point_on(bottom, t) + Vector2(0, -2)
			_mark("밑:돌", p)
			draw_stone(b, rng, p, r, st)
	for i in n_of(len, st["chain_px"], "chain"):
		var t := rng.randf_range(0.05, 0.95)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		var p := point_on(bottom, t)
		_mark("밑:사슬", p)
		draw_chain(b, rng, p, st)
	for i in n_of(len, st["drip_px"], "drip"):
		var t := rng.randf_range(0.03, 0.97)
		if nc > 0 and cover[clampi(int(t * nc), 0, nc - 1)] == 1:
			continue
		var p := point_on(bottom, t)
		_mark("밑:방울", p)
		draw_drip(b, ci, rng, p, st)


# ---------------------------------------------------------------- 가시
## 가시 하나: 옆선이 안으로 휜 날카로운 모양 + 끝 1/3 뼈색 + 한쪽 옆선의 빛 + 끝의 빛점.
static func draw_thorn(b: Batch, base_l: Vector2, base_r: Vector2, tip: Vector2, body: Color, st: Dictionary, detailed: bool) -> void:
	var tipc: Color = st["thorn_tip"]
	if not detailed:
		b.tri(base_l, tip, base_r, body)
		b.tri(tip, tip + Vector2(-3, 10), tip + Vector2(3, 10), tipc)
		if trace:
			_tick("가시")
		return
	var ml := base_l.lerp(tip, 0.5)
	var mr := base_r.lerp(tip, 0.5)
	var inward := (base_r - base_l) * 0.16
	var c := (base_l + base_r) * 0.5
	var l2 := ml + inward
	var r2 := mr - inward
	b.tri(c, base_l, l2, body)
	b.tri(c, l2, tip, body)
	b.tri(c, tip, r2, body)
	b.tri(c, r2, base_r, body)
	# 끝 쪽 1/3 은 밝은 색 (뼈처럼 단단해 보이게) + 빛 받는 옆선(가는 조각)
	var t1 := base_l.lerp(tip, 0.66) + inward * 0.5
	var t2 := base_r.lerp(tip, 0.66) - inward * 0.5
	b.tri(t1, tip, t2, tipc)
	b.tri(t1, tip, t1.lerp(t2, 0.28), tipc.lightened(0.35))
	var glow: Color = st["thorn_glow"]
	b.circle(tip, 1.8, Color(glow.r, glow.g, glow.b, 0.95))
	if trace:
		_tick("가시")
		_mark("가시끝", tip)


# ---------------------------------------------------------------- 어두운 방의 버섯 빛
## 어두운 방이면 버섯 무리 하나에 작은 빛(PointLight2D)을 단다 (방 하나에 GLOW_LIGHTS_PER_ROOM 까지).
## host 의 _draw 에서 call_deferred 로 부른다 (그리는 중에는 노드를 더하지 않는다).
static func add_glow_light(host: Node2D, spots: Array, st: Dictionary) -> void:
	if spots.is_empty() or not host.is_inside_tree() or not is_dark(host):
		return
	# 방 전체에 고르게 퍼지도록 자리 값으로 절반쯤만 고른다 (먼저 그려진 지형에 몰리지 않게)
	var pick := int(absf(host.global_position.x) / 97.0) + int(absf(host.global_position.y) / 53.0)
	if pick % 2 == 1:
		return
	var room := room_of(host)
	var count := 0
	for n in host.get_tree().get_nodes_in_group("terrain_glow_light"):
		if room == null or room.is_ancestor_of(n):
			count += 1
	if count >= GLOW_LIGHTS_PER_ROOM:
		return
	var light := PointLight2D.new()
	light.name = "MushroomGlow"
	light.texture = _glow_texture()
	light.texture_scale = 1.25
	light.energy = 1.3
	var c: Color = st["mushroom_glow"]
	light.color = Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0))
	light.position = spots[spots.size() / 2]
	light.add_to_group("terrain_glow_light")
	host.add_child(light)


static func _glow_texture() -> GradientTexture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0)])
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.width = 256
		_glow_tex.height = 256
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
	return _glow_tex

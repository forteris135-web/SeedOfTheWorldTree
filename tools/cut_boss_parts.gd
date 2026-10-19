extends SceneTree
## 보스 그림을 몸통 / 무기 / 손 세 겹으로 나눈다 (등불 기사).
## - 창·등불(boss_knight_spear): 창대 띠 + 창날 + 등불·늘어진 덩굴·잎. 손아귀(grip)를 축으로 돌린다.
## - 몸통(boss_knight_body): 원본에서 창 자리를 지우고, 몸 위를 지나던 창대 자리는 띠 바깥 무늬를 거울 복사(안 되면 보간)로 메운다.
## - 손(boss_knight_hands): 두 주먹만(팔목·창대 없이) 잘라 맨 위에 얹는다 (창이 돌아도 손은 자루를 쥔 자리에 남는다).
##   주먹 속에 가려져 있던 창대는 창 조각에서 손 사이 창대 무늬를 축 방향으로 이어 붙여 만든다(창이 돌면 그 자리가 비지 않게).
## 결과: art/bosses/parts/boss_knight_{body,spear,hands}.png (원본 해상도) + parts.json (축·조각 위치·창끝·등불 자리).
## parts.json 값이 바뀌면 scenes/bosses/lantern_knight.tscn 의 Sprite(grip/spear_origin/hands_origin/spear_butt)도 맞춘다.
## 사용: Godot --headless --path . --script tools/cut_boss_parts.gd
## (2026-10-19 고침: 예전 띠는 밑동~창날을 잇는 직선이라 두 주먹 사이에서 진짜 창대와 약 44px 어긋나
##  몸통에 창대가 남고 거울 복사가 그걸 한 번 더 베꼈다 → 진짜 창대를 따라가는 꺾은선 띠로 바꿈)

const SRC := "res://art/bosses/boss_knight_now.png"
const OUT := "res://art/bosses/parts/"

## 창대 중심선(원본 px)과 그 자리의 두 반폭: (x, y, 몸에서 지우고 메우는 반폭, 창 조각에 넣는 반폭)
## 지우는 반폭은 창대 굵기(≈20px)에 감긴 덩굴을 더한 값, 창 조각 반폭은 창대 자체만(몸 무늬가 창에 묻어 돌지 않게).
## 밑동 매듭(x 430~580)은 두껍게 감겨 있어 넓다. 창날 쪽(x 1148~)은 어차피 HANGING 구역이 통째로 창이다.
const SHAFT := [
	Vector4(250, 1022, 12, 12),
	Vector4(340, 957, 22, 22),
	Vector4(430, 900, 30, 30),
	Vector4(470, 872, 42, 42),
	Vector4(530, 835, 42, 42),
	Vector4(580, 800, 24, 15),
	Vector4(912, 532, 20, 13),
	Vector4(1000, 467, 18, 13),
	Vector4(1090, 398, 18, 13),
	Vector4(1200, 290, 25, 25),
	Vector4(1300, 205, 25, 25),
	Vector4(1405, 100, 25, 25),
]
## 주먹 속 창대를 이어 붙일 때의 반폭
const SHAFT_CORE := 12.0
## 창날
const BLADE := [Vector2(1372, 105), Vector2(1392, 32), Vector2(1468, 0), Vector2(1536, 0), Vector2(1536, 195), Vector2(1452, 205), Vector2(1392, 150)]
## 등불과 창에서 늘어진 덩굴·잎 (몸과 겹치지 않는 오른쪽 구역 — 아래 735 밑은 앞발 끝이라 뺀다)
const HANGING := Rect2(1148, 0, 1536 - 1148, 735)
## 위 주먹 오른쪽 아래로 늘어진 사슬·잎 (몸 가장자리 바깥)
const HANG_LEFT := [Vector2(1038, 437), Vector2(1094, 426), Vector2(1112, 416), Vector2(1121, 397), Vector2(1125, 376), Vector2(1148, 362), Vector2(1148, 640), Vector2(1072, 640), Vector2(1064, 575), Vector2(1052, 520), Vector2(1040, 480)]
## 밑동 매듭 아래로 늘어진 잎
const BUTT_LEAVES := [Vector2(395, 905), Vector2(470, 890), Vector2(540, 858), Vector2(540, 1020), Vector2(400, 1020)]
## 손아귀 축 (두 주먹 사이, 진짜 창대 중심선 위)
const GRIP := Vector2(1000, 467)
## 두 주먹 (주먹만 — 팔목·창대는 넣지 않는다)
const HAND_UPPER := [Vector2(1070, 373), Vector2(1090, 362), Vector2(1104, 358), Vector2(1118, 363), Vector2(1123, 378), Vector2(1119, 396), Vector2(1110, 414), Vector2(1094, 424), Vector2(1076, 420), Vector2(1067, 404)]
const HAND_LOWER := [Vector2(888, 520), Vector2(900, 508), Vector2(916, 505), Vector2(930, 510), Vector2(938, 522), Vector2(937, 540), Vector2(930, 556), Vector2(918, 570), Vector2(904, 568), Vector2(892, 554), Vector2(887, 536)]
## 궤적·빛에 쓰는 자리
const TIP := Vector2(1526, 8)
const LANTERN := Vector2(1378, 370)
const BUTT := Vector2(250, 1022)
## 메우기: 지운 자리의 양옆(또는 위아래)에서 이만큼 안에 몸 픽셀이 있어야 메운다
const FILL_REACH := 60

## 마스크 값
const M_NONE := 0
const M_WEAPON := 1    # 창 조각으로 가고 몸에서 지운다
const M_ERASE := 2     # 창 조각엔 안 넣지만 몸에서 지우고 메운다 (창대 띠 가장자리)
const M_HAND := 3      # 주먹 (몸에 그대로 두고 손 조각에도 넣는다)

var _w := 0
var _h := 0


func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	_w = img.get_width()
	_h = img.get_height()
	var w := _w
	var h := _h
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var blade := PackedVector2Array(BLADE)
	var hang_left := PackedVector2Array(HANG_LEFT)
	var butt_leaves := PackedVector2Array(BUTT_LEAVES)
	var hand_u := PackedVector2Array(HAND_UPPER)
	var hand_l := PackedVector2Array(HAND_LOWER)
	# 마스크: 창(지우고 창에 넣음) / 띠 가장자리(지우기만) / 주먹
	var mask := PackedByteArray()
	mask.resize(w * h)
	var in_band := PackedByteArray()   # 창대 띠 안 (메우기 대상)
	in_band.resize(w * h)
	var minx := w; var maxx := -1; var miny := h; var maxy := -1
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var i := y * w + x
			if Geometry2D.is_point_in_polygon(p, hand_u) or Geometry2D.is_point_in_polygon(p, hand_l):
				mask[i] = M_HAND
				continue
			var info := _shaft_info(p)
			var d: float = absf(info[0])
			var m := M_NONE
			if d <= info[1]:
				in_band[i] = 1
				m = M_WEAPON if d <= info[2] else M_ERASE
			if HANGING.has_point(p) or Geometry2D.is_point_in_polygon(p, blade) \
					or Geometry2D.is_point_in_polygon(p, hang_left) or Geometry2D.is_point_in_polygon(p, butt_leaves):
				m = M_WEAPON
			mask[i] = m
			if m == M_WEAPON and img.get_pixel(x, y).a > 0.02:
				minx = mini(minx, x); maxx = maxi(maxx, x); miny = mini(miny, y); maxy = maxi(maxy, y)
	# 주먹 속 창대도 창 조각의 테두리에 들어가게 (이어 붙일 자리)
	var hb := _poly_bbox([hand_u, hand_l], w, h)
	minx = mini(minx, hb.position.x); miny = mini(miny, hb.position.y)
	maxx = maxi(maxx, hb.end.x - 1); maxy = maxi(maxy, hb.end.y - 1)
	var wb := Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)
	# 무기 조각
	var spear := Image.create(wb.size.x, wb.size.y, false, Image.FORMAT_RGBA8)
	var synth := 0
	for y in range(wb.position.y, wb.end.y):
		for x in range(wb.position.x, wb.end.x):
			var i := y * w + x
			if mask[i] == M_WEAPON:
				spear.set_pixel(x - wb.position.x, y - wb.position.y, img.get_pixel(x, y))
			elif mask[i] == M_HAND:
				# 주먹에 가려진 창대: 손아귀 쪽(손 사이) 창대 무늬를 축 방향으로 끌어온다
				var c := _shaft_under_hand(img, mask, Vector2(x + 0.5, y + 0.5))
				if c.a > 0.0:
					spear.set_pixel(x - wb.position.x, y - wb.position.y, c)
					synth += 1
	# 손 조각 (주먹만)
	var hands := Image.create(hb.size.x, hb.size.y, false, Image.FORMAT_RGBA8)
	for y in range(hb.position.y, hb.end.y):
		for x in range(hb.position.x, hb.end.x):
			if mask[y * w + x] == M_HAND:
				hands.set_pixel(x - hb.position.x, y - hb.position.y, img.get_pixel(x, y))
	# 몸통: 창 자리를 지우고, 창대가 몸 위를 지나던 자리를 메운다
	var body := img.duplicate()
	for y in h:
		for x in w:
			var m := mask[y * w + x]
			if m == M_WEAPON or m == M_ERASE:
				body.set_pixel(x, y, Color(0, 0, 0, 0))
	var filled := 0
	var holes := 0
	for y in h:
		for x in w:
			var i := y * w + x
			if in_band[i] != 1 or mask[i] == M_HAND:
				continue
			# 창대 띠만 메운다 (창날·늘어진 구역은 원래 몸 밖)
			if img.get_pixel(x, y).a < 0.25:
				continue
			var c := _fill_color(img, mask, x, y)
			if c.a > 0.0:
				body.set_pixel(x, y, c)
				filled += 1
			else:
				holes += 1
	body.save_png(ProjectSettings.globalize_path(OUT + "boss_knight_body.png"))
	spear.save_png(ProjectSettings.globalize_path(OUT + "boss_knight_spear.png"))
	hands.save_png(ProjectSettings.globalize_path(OUT + "boss_knight_hands.png"))
	var meta := {
		"boss_knight": {
			"size": [w, h],
			"grip": [GRIP.x, GRIP.y],
			"spear_origin": [wb.position.x, wb.position.y],
			"spear_size": [wb.size.x, wb.size.y],
			"hands_origin": [hb.position.x, hb.position.y],
			"hands_size": [hb.size.x, hb.size.y],
			"tip": [TIP.x, TIP.y],
			"lantern": [LANTERN.x, LANTERN.y],
			"shaft_butt": [BUTT.x, BUTT.y],
		}
	}
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT + "parts.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	print("기사: 몸통 %dx%d (메운 픽셀 %d, 못 메움 %d), 창 %dx%d (원본 %d,%d; 주먹 속 창대 %d), 손 %dx%d (원본 %d,%d), 손아귀 %s" % [
		body.get_width(), body.get_height(), filled, holes, spear.get_width(), spear.get_height(), wb.position.x, wb.position.y, synth,
		hands.get_width(), hands.get_height(), hb.position.x, hb.position.y, GRIP])
	quit()


## 점 p 에서 가장 가까운 창대 중심선 조각: [부호 있는 거리(법선 쪽 +), 지우는 반폭, 창 반폭, 조각 방향(밑동→창끝), 법선]
func _shaft_info(p: Vector2) -> Array:
	var best := INF
	var out := [INF, 0.0, 0.0, Vector2.RIGHT, Vector2.DOWN]
	for i in SHAFT.size() - 1:
		var a: Vector4 = SHAFT[i]
		var b: Vector4 = SHAFT[i + 1]
		var pa := Vector2(a.x, a.y)
		var pb := Vector2(b.x, b.y)
		var seg := pb - pa
		var t := clampf((p - pa).dot(seg) / seg.length_squared(), 0.0, 1.0)
		var q := pa + seg * t
		var dist := p.distance_to(q)
		if dist < best:
			best = dist
			var d := seg.normalized()
			var n := Vector2(-d.y, d.x)
			out = [(p - q).dot(n), lerpf(a.z, b.z, t), lerpf(a.w, b.w, t), d, n]
	return out


## 주먹 속 창대 픽셀: 창대 중심선에서 SHAFT_CORE 안이면, 손아귀 쪽(손 사이)으로 축을 따라 일정 거리 옮긴 자리의 색.
## 거리를 픽셀마다 같게 두어야 무늬(껍질 결)가 그대로 옮겨진다 (주먹 가장자리 한 점만 베끼면 납작한 줄무늬가 된다).
func _shaft_under_hand(img: Image, mask: PackedByteArray, p: Vector2) -> Color:
	var info := _shaft_info(p)
	if absf(info[0]) > SHAFT_CORE:
		return Color(0, 0, 0, 0)
	var d: Vector2 = info[3]
	var step := d if (GRIP - p).dot(d) > 0.0 else -d
	for L: float in [64.0, 78.0, 92.0, 106.0]:
		var q := p + step * L
		var x := int(q.x)
		var y := int(q.y)
		if x < 0 or y < 0 or x >= _w or y >= _h:
			return Color(0, 0, 0, 0)
		if mask[y * _w + x] == M_WEAPON:
			return img.get_pixel(x, y)
	return Color(0, 0, 0, 0)


func _poly_bbox(polys: Array, w: int, h: int) -> Rect2i:
	var minx := w; var maxx := 0; var miny := h; var maxy := 0
	for poly in polys:
		for p in poly:
			minx = mini(minx, int(p.x)); maxx = maxi(maxx, int(p.x) + 1); miny = mini(miny, int(p.y)); maxy = maxi(maxy, int(p.y) + 1)
	return Rect2i(minx, miny, maxx - minx, maxy - miny)


## 몸에서 쓸 수 있는 원본 픽셀인가 (지운 자리·주먹이 아니고 불투명)
func _usable(img: Image, mask: PackedByteArray, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return false
	var m := mask[y * _w + x]
	if m == M_WEAPON or m == M_ERASE or m == M_HAND:
		return false
	return img.get_pixel(x, y).a > 0.5


## 지운 자리를 메울 색.
## 1) 거울 복사: 띠 가장자리 바로 바깥의 진짜 무늬(덩굴·잎)를 띠 안쪽으로 접어 넣는다 (뭉개진 줄무늬 대신 결이 남는다).
##    같은 쪽 바깥이 몸이면 베낀다 — 반대쪽이 몸 밖(망토 구멍·팔 사이 틈)이어도 이쪽 절반은 몸으로 메워 구멍이 생기지 않게.
## 2) 보간: 창대에 직각 방향으로 양쪽에서 가장 가까운 몸 픽셀 둘을 거리로 섞는다.
##    (가로·세로 보간은 망토 구멍 자리에 네모난 줄무늬를 남겨서 뺐다 — 어느 쪽도 안 되면 구멍이 자연스럽게 이어지게 둔다)
func _fill_color(img: Image, mask: PackedByteArray, x: int, y: int) -> Color:
	var p := Vector2(x + 0.5, y + 0.5)
	var info := _shaft_info(p)
	var s: float = info[0]
	var half: float = info[1]
	var n: Vector2 = info[4]
	var side := 1.0 if s >= 0.0 else -1.0
	var src := p + n * side * (2.0 * (half - absf(s)) + 3.0)
	if _usable(img, mask, int(src.x), int(src.y)):
		return img.get_pixel(int(src.x), int(src.y))
	var a := _probe(img, mask, x, y, -n)
	var b := _probe(img, mask, x, y, n)
	if a[0] > 0 and b[0] > 0:
		var t := float(a[0]) / float(a[0] + b[0])
		return (a[1] as Color).lerp(b[1], t)
	return Color(0, 0, 0, 0)


func _probe(img: Image, mask: PackedByteArray, x: int, y: int, dir: Vector2) -> Array:
	for i in range(1, FILL_REACH + 1):
		var px := x + int(round(dir.x * i))
		var py := y + int(round(dir.y * i))
		if px < 0 or py < 0 or px >= _w or py >= _h:
			return [0, Color()]
		var m := mask[py * _w + px]
		if m == M_WEAPON or m == M_ERASE or m == M_HAND:
			continue
		var c := img.get_pixel(px, py)
		if c.a > 0.5:
			return [i, c]
		# 투명한 몸 밖에 닿았다 → 이쪽은 몸이 아니다
		if c.a < 0.1:
			return [0, Color()]
	return [0, Color()]

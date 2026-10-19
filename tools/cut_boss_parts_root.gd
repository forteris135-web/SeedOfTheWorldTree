extends SceneTree
## 뿌리지기 그림(boss_rootkeeper_now.png)을 '몸통'과 '지팡이' 두 겹으로 나눈다.
## 지팡이 영역은 아래 다각형들(원본 px, 1024×1536)로 정한다: 머리 장식(달 원반·덩굴 고리) / 등불 / 휘어진 자루 / 쥔 손.
## 몸통에서 지팡이가 빠진 구멍은 같은 줄의 좌우 이웃 픽셀을 선형으로 섞어 메운다(양쪽 모두 불투명할 때만 — 자루가
## 망토를 가로지르는 구간). 한쪽이라도 투명하면 투명하게 둔다(자루가 허공에 떠 있던 구간).
## 결과: art/bosses/parts/boss_rootkeeper_body.png (원본 크기), boss_rootkeeper_staff.png (잘라낸 상자), parts.json
##       (손잡이 축 pivot, 지팡이 조각의 원본 위치 staff_pos, 자루 위·아래 끝 top/bottom, 등불 고리 hook)
## 사용: Godot --headless --path . --script tools/cut_boss_parts_root.gd
## 값을 바꾸면 scripts/bosses/root_keeper_visual.gd 상단의 STAFF_* 상수도 같이 맞춘다.

const SRC := "res://art/bosses/boss_rootkeeper_now.png"
const OUT_DIR := "res://art/bosses/parts/"
## 지팡이 영역 (원본 px). 여러 다각형의 합집합.
const POLYS := [
	# 머리: 덩굴 고리 + 달 원반 + 고드름 + 작은 장식 (뿔은 x≤745 라 안 닿는다)
	[Vector2(770, 60), Vector2(1010, 60), Vector2(1010, 450), Vector2(930, 450), Vector2(930, 418), Vector2(770, 418)],
	# 등불 (쇠사슬 포함) + 그 아래 매달린 장식 잎
	[Vector2(848, 415), Vector2(925, 415), Vector2(925, 700), Vector2(868, 700), Vector2(868, 534), Vector2(848, 534)],
	# 휘어진 자루 (위 805~855 → 아래 715~775). 망토를 가로지르는 아래쪽은 색으로 덩굴만 골라낸다(COLOR_FROM_Y).
	[Vector2(797, 330), Vector2(866, 330), Vector2(866, 560), Vector2(848, 700), Vector2(818, 800), Vector2(808, 1000),
		Vector2(798, 1200), Vector2(788, 1450), Vector2(793, 1536), Vector2(697, 1536), Vector2(702, 1450), Vector2(722, 1200),
		Vector2(732, 1000), Vector2(742, 800), Vector2(772, 700), Vector2(797, 560), Vector2(780, 545), Vector2(780, 420), Vector2(797, 420)],
	# 쥔 손 (자루를 감싼 손가락; 소매 끝은 색으로 걸러진다)
	[Vector2(784, 548), Vector2(872, 548), Vector2(872, 634), Vector2(784, 634)],
]
## 이 줄(원본 y)부터는 다각형 안이라도 '덩굴 색'(어둡거나 채도가 높은 픽셀)만 지팡이로 본다. 옅은 크림색 망토는 몸통에 남긴다.
const COLOR_FROM_Y := 540
const COLOR_POLYS := [2, 3]   # 색 판정을 쓰는 다각형 번호 (자루, 손)
const PIVOT := Vector2(828, 590)      # 손잡이(쥔 손 가운데)
const TOP := Vector2(880, 100)        # 자루 위 끝 (고리 꼭대기)
const BOTTOM := Vector2(745, 1525)    # 자루 아래 끝
const HOOK := Vector2(872, 338)       # 등불이 걸린 고리


func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	var w := img.get_width()
	var h := img.get_height()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	# 1) 지팡이 마스크
	var mask := PackedByteArray()
	mask.resize(w * h)
	var minx := w; var maxx := 0; var miny := h; var maxy := 0
	for pi in POLYS.size():
		var poly: Array = POLYS[pi]
		var by_color: bool = pi in COLOR_POLYS
		var bb := Rect2i(Vector2i(w, h), Vector2i.ZERO)
		var px := w; var qx := 0; var py := h; var qy := 0
		for p in poly:
			px = mini(px, int(p.x)); qx = maxi(qx, int(p.x)); py = mini(py, int(p.y)); qy = maxi(qy, int(p.y))
		bb = Rect2i(px, py, qx - px + 1, qy - py + 1)
		var pv := PackedVector2Array(poly)
		for y in range(bb.position.y, mini(bb.end.y, h)):
			for x in range(bb.position.x, mini(bb.end.x, w)):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pv):
					if by_color and y >= COLOR_FROM_Y and not _is_vine(img.get_pixel(x, y)):
						continue
					mask[y * w + x] = 1
					minx = mini(minx, x); maxx = maxi(maxx, x); miny = mini(miny, y); maxy = maxi(maxy, y)
	# 2) 지팡이 조각 + 구멍 뚫린 몸통
	var staff := Image.create(maxx - minx + 1, maxy - miny + 1, false, Image.FORMAT_RGBA8)
	var body := img.duplicate()
	var cut := 0
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			if mask[y * w + x] == 1:
				var c := img.get_pixel(x, y)
				staff.set_pixel(x - minx, y - miny, c)
				body.set_pixel(x, y, Color(0, 0, 0, 0))
				if c.a > 0.5:
					cut += 1
	# 3) 구멍 메우기: 줄마다 구멍 구간의 왼쪽·오른쪽 이웃을 찾아 섞는다 (둘 다 불투명할 때만)
	var filled := 0
	for y in range(miny, maxy + 1):
		var x := minx
		while x <= maxx:
			if mask[y * w + x] == 1 and img.get_pixel(x, y).a > 0.5:
				var x0 := x
				while x <= maxx and mask[y * w + x] == 1:
					x += 1
				var x1 := x - 1
				var left := Color(0, 0, 0, 0)
				var right := Color(0, 0, 0, 0)
				if x0 - 1 >= 0:
					left = img.get_pixel(x0 - 1, y) if mask[y * w + x0 - 1] == 0 else Color(0, 0, 0, 0)
				if x1 + 1 < w:
					right = img.get_pixel(x1 + 1, y) if mask[y * w + x1 + 1] == 0 else Color(0, 0, 0, 0)
				if left.a > 0.5 and right.a > 0.5:
					# 양쪽 이웃을 거울처럼 안쪽으로 복사해 섞는다 (망토 결이 이어져 보이게; 단순 선형 섞기는 번진 띠가 됐다)
					var span := float(x1 - x0 + 2)
					for xx in range(x0, x1 + 1):
						var dl := xx - x0 + 1
						var dr := x1 - xx + 1
						var cl := _sample_mirror(img, mask, w, x0 - dl, y, left)
						var cr := _sample_mirror(img, mask, w, x1 + dr, y, right)
						var u := float(dl) / span
						var c := cl.lerp(cr, smoothstep(0.0, 1.0, u))
						c = c.darkened(0.08 * sin(u * PI))
						body.set_pixel(xx, y, c)
						filled += 1
			else:
				x += 1
	body.save_png(ProjectSettings.globalize_path(OUT_DIR + "boss_rootkeeper_body.png"))
	staff.save_png(ProjectSettings.globalize_path(OUT_DIR + "boss_rootkeeper_staff.png"))
	var meta := {
		"pivot": [PIVOT.x, PIVOT.y], "staff_pos": [minx, miny], "staff_size": [staff.get_width(), staff.get_height()],
		"size": [w, h], "top": [TOP.x, TOP.y], "bottom": [BOTTOM.x, BOTTOM.y], "hook": [HOOK.x, HOOK.y],
	}
	# parts.json 은 여러 보스가 같이 쓴다: 기존 내용을 읽어 내 키("boss_rootkeeper")만 바꿔 쓴다 (다른 보스 항목을 지우지 않게)
	var json_path := ProjectSettings.globalize_path(OUT_DIR + "parts.json")
	var all := {}
	if FileAccess.file_exists(json_path):
		var old = JSON.parse_string(FileAccess.get_file_as_string(json_path))
		if old is Dictionary:
			all = old
	all["boss_rootkeeper"] = meta
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(all, "  "))
	f.close()
	_check(body, staff, minx, miny)
	print("뿌리지기: 몸통 %dx%d, 지팡이 %dx%d (원본 %d,%d), 잘라낸 픽셀 %d, 메운 픽셀 %d, 손잡이 %s" % [
		body.get_width(), body.get_height(), staff.get_width(), staff.get_height(), minx, miny, cut, filled, PIVOT])
	quit()


## 덩굴 색인가: 어둡거나(명도 < 0.62) 채도가 높은(이끼·금빛 장식) 픽셀. 옅은 크림색 망토는 아니다.
func _is_vine(c: Color) -> bool:
	if c.a < 0.5:
		return false
	return c.v < 0.62 or (c.s > 0.4 and c.v < 0.85)


## 거울 복사 표본: 구멍이거나 투명하면 가장 가까운 이웃 색으로 대신한다.
func _sample_mirror(img: Image, mask: PackedByteArray, w: int, x: int, y: int, fallback: Color) -> Color:
	if x < 0 or x >= w or mask[y * w + x] == 1:
		return fallback
	var c := img.get_pixel(x, y)
	return c if c.a > 0.5 else fallback


## 결과 확인: 몸통+지팡이를 겹치면 원본과 같은지(불투명 픽셀 수), 지팡이 조각이 비어 있지 않은지.
func _check(body: Image, staff: Image, ox: int, oy: int) -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	var miss := 0
	var total := 0
	for y in range(0, src.get_height(), 3):
		for x in range(0, src.get_width(), 3):
			if src.get_pixel(x, y).a > 0.5:
				total += 1
				var covered := body.get_pixel(x, y).a > 0.5
				var sx := x - ox
				var sy := y - oy
				if not covered and sx >= 0 and sy >= 0 and sx < staff.get_width() and sy < staff.get_height():
					covered = staff.get_pixel(sx, sy).a > 0.5
				if not covered:
					miss += 1
	print("겹침 확인: 원본 불투명 표본 %d 중 두 겹이 못 덮는 픽셀 %d (0 이어야 함)" % [total, miss])

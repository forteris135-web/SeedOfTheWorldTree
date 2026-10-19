extends SceneTree
## 부위 뼈대(파트 리그) 자르기 도구.
## 부위가 따로 그려진 그림 시트(투명 PNG)에서 부위를 잘라 art/rigs/<id>/<부위>.png 와 실행용 art/rigs/<id>/rig.json 을 만든다.
## 설계도는 data/rigs/<id>.json (사람이 쓴다, 저장소에 둔다). 쓰는 법 전체는 RIGS.md.
##
## 사용 (프로젝트 폴더에서, 병렬 작업이면 /Users/wj/Projects/SeedWT/godot 래퍼로):
##   Godot --headless --path . --script tools/rig_cut.gd -- <id> --dump
##       조각 번호 미리보기: screenshots/rig_cut/<id>/labels_<시트>.png (+ .json). 번호를 보고 설계도의 comps 를 고른다.
##   Godot --headless --path . --script tools/rig_cut.gd -- <id> --crop <x> <y> <w> <h> [--grid 50] [--zoom 2] [--sheet <키>]
##       시트 한 구역을 격자·좌표와 함께 크게: screenshots/rig_cut/<id>/crop_<x>_<y>.png (관절 좌표 읽기용)
##   Godot --headless --path . --script tools/rig_cut.gd -- <id> [<id> ...]
##       자르기: art/rigs/<id>/*.png (+ 밉맵 켠 .import) + rig.json. 끝나면 "--import" 한 번(tools/cloud_bootstrap.sh).
##
## 조각 나누기 (segment): 불투명(alpha > segment.alpha) 픽셀을 erode 반지름만큼 깎아 서로 닿은 부위를 가늘게 이어진 곳에서 끊고,
## 깎인 덩어리(min_pixels 이상)를 씨앗으로 반투명 가장자리까지(alpha > soft_alpha) 가장 가까운 덩어리로 다시 채운다.
## 남은 작은 조각(min_small 이상)은 따로 번호를 받는다. 번호는 위→아래(120px 줄), 왼→오른 순서. 값을 바꾸면 번호가 바뀐다.
##
## 좌표 약속: 설계도의 모든 좌표(pivot·tip·attach·sole·다각형)는 **원본 시트 픽셀** 그대로 쓴다 (미리보기 그림의 격자 좌표).
## 시트 속 인물이 왼쪽을 보면 faces:"left" — 도구가 모든 부위를 뒤집어 실행용 뼈대는 늘 **오른쪽을 본다**.

const DIGITS := [
	"111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
	"111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111",
]
const PALETTE := [
	Color(1, 0.3, 0.3), Color(0.3, 1, 0.4), Color(0.35, 0.6, 1), Color(1, 0.9, 0.2), Color(1, 0.4, 1),
	Color(0.2, 1, 1), Color(1, 0.6, 0.2), Color(0.7, 0.5, 1), Color(0.6, 1, 0.6), Color(1, 0.7, 0.7),
]

var _sheets := {}     # 키 -> {img(Image, RGBA8), w, h, labels(PackedInt32Array), comps(Array), path}
var _spec := {}
var _id := ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ids: Array[String] = []
	var dump := false
	var crop := Rect2i()
	var grid := 50
	var zoom := 1.0
	var crop_sheet := "main"
	var i := 0
	while i < args.size():
		var a := args[i]
		match a:
			"--dump":
				dump = true
			"--crop":
				if i + 4 >= args.size():
					print("--crop 뒤에는 x y w h 네 숫자")
					quit(1)
					return
				crop = Rect2i(int(args[i + 1]), int(args[i + 2]), int(args[i + 3]), int(args[i + 4]))
				i += 4
			"--grid":
				grid = int(args[i + 1]); i += 1
			"--zoom":
				zoom = float(args[i + 1]); i += 1
			"--sheet":
				crop_sheet = args[i + 1]; i += 1
			_:
				ids.append(a)
		i += 1
	if ids.is_empty():
		print("사용: ... --script tools/rig_cut.gd -- <id> [--dump | --crop x y w h]")
		quit(1)
		return
	var fail := 0
	for id in ids:
		_sheets.clear()
		if not _load_spec(id):
			fail += 1
			continue
		if crop.size.x > 0:
			_crop_view(crop_sheet, crop, grid, zoom)
		elif dump:
			for key in _sheet_keys():
				_dump_labels(key)
		else:
			if not _cut():
				fail += 1
	quit(1 if fail > 0 else 0)


# ---------- 설계도 ----------

func _load_spec(id: String) -> bool:
	_id = id
	var path := "res://data/rigs/%s.json" % id
	if not FileAccess.file_exists(path):
		push_error("설계도가 없다: " + path)
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("설계도 JSON 을 읽지 못했다: " + path)
		return false
	_spec = parsed
	return true


func _sheet_keys() -> Array:
	var keys := ["main"]
	for k in _spec.get("extra_sheets", {}):
		keys.append(k)
	return keys


func _sheet_info(key: String) -> Dictionary:
	if key == "main":
		return {"path": _spec["sheet"], "segment": _spec.get("segment", {})}
	var ex: Dictionary = _spec.get("extra_sheets", {}).get(key, {})
	if ex.is_empty():
		push_error("모르는 시트 키: " + key)
	var seg: Dictionary = _spec.get("segment", {}).duplicate()
	seg.merge(ex.get("segment", {}), true)
	return {"path": ex.get("path", ""), "segment": seg}


## 시트를 읽고 조각 번호를 매긴다 (한 번만).
func _sheet(key: String) -> Dictionary:
	if _sheets.has(key):
		return _sheets[key]
	var info := _sheet_info(key)
	var p: String = info["path"]
	var img := Image.load_from_file(ProjectSettings.globalize_path(p) if p.begins_with("res://") else p)
	if img == null:
		push_error("시트를 읽지 못했다: " + p)
		return {}
	img.convert(Image.FORMAT_RGBA8)
	var s := {"img": img, "w": img.get_width(), "h": img.get_height(), "path": p}
	_segment(s, info["segment"])
	_sheets[key] = s
	return s


# ---------- 조각 나누기 ----------

func _segment(s: Dictionary, seg: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	var w: int = s["w"]
	var h: int = s["h"]
	var n := w * h
	var data: PackedByteArray = (s["img"] as Image).get_data()
	var athr := int(float(seg.get("alpha", 0.5)) * 255.0)
	var sthr := int(float(seg.get("soft_alpha", 0.03)) * 255.0)
	var erode := float(seg.get("erode", 0))
	var min_px := int(seg.get("min_pixels", 1500))
	var min_small := int(seg.get("min_small", 150))
	var solid := PackedByteArray(); solid.resize(n)
	var soft := PackedByteArray(); soft.resize(n)
	for p in n:
		var a := data[p * 4 + 3]
		solid[p] = 1 if a > athr else 0
		soft[p] = 1 if a > sthr else 0
	# 깎기: 투명까지의 거리(체스판 3-4 근사)가 erode 보다 큰 곳만 씨앗이 된다
	var seed := solid
	if erode > 0.0:
		var dist := PackedInt32Array(); dist.resize(n)
		var big := 1 << 28
		for p in n:
			dist[p] = big if solid[p] == 1 else 0
		for y in h:
			var row := y * w
			for x in w:
				var p := row + x
				if dist[p] == 0:
					continue
				var d := dist[p]
				if x > 0: d = mini(d, dist[p - 1] + 3)
				else: d = mini(d, 3)
				if y > 0:
					d = mini(d, dist[p - w] + 3)
					if x > 0: d = mini(d, dist[p - w - 1] + 4)
					if x < w - 1: d = mini(d, dist[p - w + 1] + 4)
				else:
					d = mini(d, 3)
				dist[p] = d
		for y in range(h - 1, -1, -1):
			var row := y * w
			for x in range(w - 1, -1, -1):
				var p := row + x
				if dist[p] == 0:
					continue
				var d := dist[p]
				if x < w - 1: d = mini(d, dist[p + 1] + 3)
				else: d = mini(d, 3)
				if y < h - 1:
					d = mini(d, dist[p + w] + 3)
					if x < w - 1: d = mini(d, dist[p + w + 1] + 4)
					if x > 0: d = mini(d, dist[p + w - 1] + 4)
				else:
					d = mini(d, 3)
				dist[p] = d
		seed = PackedByteArray(); seed.resize(n)
		var dthr := int(erode * 3.0)
		for p in n:
			seed[p] = 1 if dist[p] > dthr else 0
	# 씨앗 덩어리 (4방향)
	var label := PackedInt32Array(); label.resize(n)
	var comps: Array = []
	var stack := PackedInt32Array()
	var tmp_id := 0
	for start in n:
		if seed[start] == 0 or label[start] != 0:
			continue
		tmp_id += 1
		var cnt := 0
		stack.clear()
		stack.append(start)
		label[start] = tmp_id
		var members := PackedInt32Array()
		while stack.size() > 0:
			var q := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			members.append(q)
			cnt += 1
			var qx := q % w
			if qx > 0 and seed[q - 1] == 1 and label[q - 1] == 0: label[q - 1] = tmp_id; stack.append(q - 1)
			if qx < w - 1 and seed[q + 1] == 1 and label[q + 1] == 0: label[q + 1] = tmp_id; stack.append(q + 1)
			if q >= w and seed[q - w] == 1 and label[q - w] == 0: label[q - w] = tmp_id; stack.append(q - w)
			if q < n - w and seed[q + w] == 1 and label[q + w] == 0: label[q + w] = tmp_id; stack.append(q + w)
		if cnt < min_px:
			for q in members:
				label[q] = -1   # 너무 작은 씨앗: 아래 채우기에서 이웃 덩어리가 가져간다
	for p in n:
		if label[p] < 0:
			label[p] = 0
	# 채우기: 씨앗에서 반투명 가장자리까지 가장 가까운 덩어리로 (너비 우선)
	var queue := PackedInt32Array()
	for p in n:
		if label[p] > 0:
			queue.append(p)
	var head := 0
	while head < queue.size():
		var q := queue[head]
		head += 1
		var l := label[q]
		var qx := q % w
		if qx > 0 and soft[q - 1] == 1 and label[q - 1] == 0: label[q - 1] = l; queue.append(q - 1)
		if qx < w - 1 and soft[q + 1] == 1 and label[q + 1] == 0: label[q + 1] = l; queue.append(q + 1)
		if q >= w and soft[q - w] == 1 and label[q - w] == 0: label[q - w] = l; queue.append(q - w)
		if q < n - w and soft[q + w] == 1 and label[q + w] == 0: label[q + w] = l; queue.append(q + w)
	# 남은 작은 조각들 (씨앗이 없던 가는 덩굴·잎): 8방향으로 묶어 따로 번호
	for start in n:
		if soft[start] == 0 or label[start] != 0:
			continue
		tmp_id += 1
		stack.clear()
		stack.append(start)
		label[start] = tmp_id
		var members := PackedInt32Array()
		var solid_cnt := 0
		while stack.size() > 0:
			var q := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			members.append(q)
			if solid[q] == 1:
				solid_cnt += 1
			var qx := q % w
			for dy in [-w, 0, w]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					if (dx == -1 and qx == 0) or (dx == 1 and qx == w - 1):
						continue
					var r: int = q + dy + dx
					if r < 0 or r >= n:
						continue
					if soft[r] == 1 and label[r] == 0:
						label[r] = tmp_id
						stack.append(r)
		if solid_cnt < min_small:
			for q in members:
				label[q] = -1   # 먼지: 버린다
	# 덩어리별 상자·개수 → 위→아래, 왼→오른 순서로 번호 다시 매기기
	var stats := {}
	for p in n:
		var l := label[p]
		if l <= 0:
			continue
		var x := p % w
		var y := p / w
		if not stats.has(l):
			stats[l] = [x, y, x, y, 0, 0.0, 0.0]
		var st: Array = stats[l]
		if x < st[0]: st[0] = x
		if y < st[1]: st[1] = y
		if x > st[2]: st[2] = x
		if y > st[3]: st[3] = y
		if solid[p] == 1:
			st[4] += 1
			st[5] += x
			st[6] += y
	var keys := stats.keys()
	keys.sort_custom(func(a, b):
		var ra := int(stats[a][1] / 120); var rb := int(stats[b][1] / 120)
		if ra != rb: return ra < rb
		return stats[a][0] < stats[b][0])
	var remap := {}
	var out: Array = []
	for k in keys.size():
		var st: Array = stats[keys[k]]
		remap[keys[k]] = k
		var cx: float = st[5] / maxf(st[4], 1.0)
		var cy: float = st[6] / maxf(st[4], 1.0)
		out.append({"id": k, "rect": [st[0], st[1], st[2] - st[0] + 1, st[3] - st[1] + 1], "pixels": st[4], "center": [roundi(cx), roundi(cy)]})
	for p in n:
		var l := label[p]
		label[p] = remap[l] if l > 0 else -1
	s["labels"] = label
	s["comps"] = out
	print("[rig_cut] 조각 나누기 %s: %d개 (%.1f초)" % [str(s["path"]).get_file(), out.size(), (Time.get_ticks_msec() - t0) / 1000.0])


# ---------- 미리보기 그림 ----------

## 조각 번호 미리보기: 어두운 바탕 + 조각마다 색 + 경계선 + 가운데 번호 + 100px 격자(좌표 숫자).
func _dump_labels(key: String) -> void:
	var s := _sheet(key)
	if s.is_empty():
		return
	var w: int = s["w"]
	var h: int = s["h"]
	var labels: PackedInt32Array = s["labels"]
	var clean: Image = load("res://tools/sheet_catalog.gd").defringe(s["img"], 0.6)
	var src := clean.get_data()
	var out := PackedByteArray(); out.resize(w * h * 4)
	for p in w * h:
		var l := labels[p]
		var bg := Color(0.16, 0.17, 0.2)
		var gx := p % w
		var gy := p / w
		if gx % 100 == 0 or gy % 100 == 0:
			bg = Color(0.3, 0.32, 0.36)
		var a := src[p * 4 + 3] / 255.0
		var c := Color(src[p * 4] / 255.0, src[p * 4 + 1] / 255.0, src[p * 4 + 2] / 255.0)
		var col := bg.lerp(c, a)
		if l >= 0:
			var pc: Color = PALETTE[l % PALETTE.size()]
			col = col.lerp(pc, 0.28)
			# 경계: 이웃의 번호가 다르면 선
			var edge := false
			if gx > 0 and labels[p - 1] != l: edge = true
			elif gx < w - 1 and labels[p + 1] != l: edge = true
			elif gy > 0 and labels[p - w] != l: edge = true
			elif gy < h - 1 and labels[p + w] != l: edge = true
			if edge:
				col = pc
		out[p * 4] = int(clampf(col.r, 0, 1) * 255)
		out[p * 4 + 1] = int(clampf(col.g, 0, 1) * 255)
		out[p * 4 + 2] = int(clampf(col.b, 0, 1) * 255)
		out[p * 4 + 3] = 255
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)
	for c in s["comps"]:
		var ctr: Array = c["center"]
		_draw_number(img, int(c["id"]), int(ctr[0]), int(ctr[1]), 5, PALETTE[int(c["id"]) % PALETTE.size()])
	for x in range(100, w, 100):
		_draw_number(img, x, x + 3, 10, 2, Color(0.8, 0.9, 1.0))
	for y in range(100, h, 100):
		_draw_number(img, y, 14, y + 8, 2, Color(0.8, 0.9, 1.0))
	var dir := "res://screenshots/rig_cut/%s" % _id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var png := "%s/labels_%s.png" % [dir, key]
	img.save_png(ProjectSettings.globalize_path(png))
	var f := FileAccess.open(ProjectSettings.globalize_path("%s/labels_%s.json" % [dir, key]), FileAccess.WRITE)
	f.store_string(JSON.stringify({"sheet": s["path"], "size": [w, h], "segment": _sheet_info(key)["segment"], "comps": s["comps"]}, "  "))
	f.close()
	print("[rig_cut] 조각 번호 미리보기 → %s" % ProjectSettings.globalize_path(png))
	for c in s["comps"]:
		print("[rig_cut]   #%d 상자 %s 픽셀 %d" % [c["id"], str(c["rect"]), c["pixels"]])


## 시트 한 구역을 격자·좌표와 함께 크게 (관절 자리 읽기용). 조각 경계도 옅게 그린다.
func _crop_view(key: String, r: Rect2i, grid: int, zoom: float) -> void:
	var s := _sheet(key)
	if s.is_empty():
		return
	var w: int = s["w"]
	var labels: PackedInt32Array = s["labels"]
	r = r.intersection(Rect2i(0, 0, w, s["h"]))
	var clean: Image = load("res://tools/sheet_catalog.gd").defringe((s["img"] as Image).get_region(r), 0.6)
	var cw := r.size.x
	var ch := r.size.y
	var out := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
	for y in ch:
		for x in cw:
			var gx := x + r.position.x
			var gy := y + r.position.y
			var bg := Color(0.36, 0.39, 0.44)
			if gx % grid == 0 or gy % grid == 0:
				bg = Color(0.55, 0.6, 0.66) if (gx % (grid * 2) == 0 or gy % (grid * 2) == 0) else Color(0.45, 0.49, 0.55)
			var c := clean.get_pixel(x, y)
			var col := bg.lerp(Color(c.r, c.g, c.b), c.a)
			var l := labels[gy * w + gx]
			if l >= 0 and ((gx + 1 < w and labels[gy * w + gx + 1] != l) or (gy + 1 < s["h"] and labels[(gy + 1) * w + gx] != l)):
				col = col.lerp(PALETTE[l % PALETTE.size()], 0.7)
			out.set_pixel(x, y, col)
	if zoom != 1.0:
		out.resize(int(cw * zoom), int(ch * zoom), Image.INTERPOLATE_BILINEAR)
	var k := maxi(2, int(2 * zoom))
	var gx0 := int(ceil(r.position.x / float(grid * 2))) * grid * 2
	for gx in range(gx0, r.end.x, grid * 2):
		_draw_number(out, gx, int((gx - r.position.x) * zoom) + 3, 6, k, Color(1, 1, 0.6))
	var gy0 := int(ceil(r.position.y / float(grid * 2))) * grid * 2
	for gy in range(gy0, r.end.y, grid * 2):
		_draw_number(out, gy, 4, int((gy - r.position.y) * zoom) + 4, k, Color(1, 1, 0.6))
	var dir := "res://screenshots/rig_cut/%s" % _id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var png := "%s/crop_%s_%d_%d.png" % [dir, key, r.position.x, r.position.y]
	out.save_png(ProjectSettings.globalize_path(png))
	print("[rig_cut] 구역 → %s" % ProjectSettings.globalize_path(png))


## 작은 비트맵 숫자 (3×5, k배). 검은 테두리를 둘러 어떤 바탕에서도 읽힌다.
static func _draw_number(img: Image, value: int, x: int, y: int, k: int, col: Color) -> void:
	var text := str(value)
	var iw := img.get_width()
	var ih := img.get_height()
	for pass_i in 2:
		for ci in text.length():
			var ch := text.unicode_at(ci) - 48
			if ch < 0 or ch > 9:
				continue
			var bits: String = DIGITS[ch]
			for by in 5:
				for bx in 3:
					if bits[by * 3 + bx] != "1":
						continue
					var px := x + ci * 4 * k + bx * k
					var py := y + by * k
					var grow := 1 if pass_i == 0 else 0
					for yy in range(py - grow, py + k + grow):
						for xx in range(px - grow, px + k + grow):
							if xx >= 0 and yy >= 0 and xx < iw and yy < ih:
								img.set_pixel(xx, yy, Color.BLACK if pass_i == 0 else col)


# ---------- 자르기 ----------

func _flip() -> bool:
	return str(_spec.get("faces", "right")) == "left"


func _sheet_w(key: String) -> float:
	return float(_sheet(key)["w"])


## 설계도 좌표(원본 시트 px) → 뼈대 좌표(오른쪽을 보게 뒤집은 시트 px). 부위의 mirror 는 그 부위 pivot 을 축으로 한 번 더 뒤집는다.
func _to_rig(part_name: String, pt) -> Vector2:
	var part: Dictionary = _spec["parts"][part_name]
	var src_name := str(part.get("from", ""))
	var drawn: Dictionary = _spec["parts"][src_name] if src_name != "" else part
	var key := str(drawn.get("sheet", "main"))
	var v := Vector2(pt[0], pt[1])
	if _flip():
		v.x = _sheet_w(key) - v.x
	if bool(drawn.get("mirror", false)):
		var pv := Vector2(drawn["pivot"][0], drawn["pivot"][1])
		if _flip():
			pv.x = _sheet_w(key) - pv.x
		v.x = 2.0 * pv.x - v.x
	return v


## 다각형 덮임 비율(0~1)을 마스크에 곱하거나 더한다. mode: "clip"(곱: 안=1, 밖=0) / "add"(최대) / "cut"(1-덮임 곱)
## 가로는 정확한 겹침 길이, 세로는 4줄 표본 → 자른 가장자리가 계단지지 않는다.
static func _apply_polys(mask: PackedFloat32Array, soft: PackedFloat32Array, w: int, h: int, polys: Array, mode: String) -> void:
	var cover := PackedFloat32Array(); cover.resize(w * h)
	var any := false
	for poly_raw in polys:
		var poly := PackedVector2Array()
		for q in poly_raw:
			poly.append(Vector2(q[0], q[1]))
		if poly.size() < 3:
			continue
		any = true
		var y0 := maxi(0, int(floor(_min_y(poly))))
		var y1 := mini(h - 1, int(ceil(_max_y(poly))))
		for y in range(y0, y1 + 1):
			for sub in 4:
				var sy := y + (sub + 0.5) / 4.0
				var xs := PackedFloat32Array()
				for e in poly.size():
					var a := poly[e]
					var b := poly[(e + 1) % poly.size()]
					if (a.y <= sy and b.y > sy) or (b.y <= sy and a.y > sy):
						xs.append(a.x + (sy - a.y) / (b.y - a.y) * (b.x - a.x))
				xs.sort()
				var k := 0
				while k + 1 < xs.size():
					var x0 := clampf(xs[k], 0.0, w)
					var x1 := clampf(xs[k + 1], 0.0, w)
					var px := int(floor(x0))
					while px < x1 and px < w:
						var ov := minf(px + 1.0, x1) - maxf(px, x0)
						if ov > 0.0:
							var idx := y * w + px
							cover[idx] = minf(cover[idx] + ov * 0.25, 1.0)
						px += 1
					k += 2
	if not any:
		return
	for p in w * h:
		match mode:
			"clip":
				mask[p] *= cover[p]
			"add":
				mask[p] = maxf(mask[p], cover[p] * soft[p])
			"cut":
				mask[p] *= 1.0 - cover[p]


## 다각형들을 delta px 만큼 넓히거나(+) 좁힌다(−).
static func _offset_polys(polys: Array, delta: float) -> Array:
	if absf(delta) < 0.01:
		return polys
	var out: Array = []
	for poly_raw in polys:
		var poly := PackedVector2Array()
		for q in poly_raw:
			poly.append(Vector2(q[0], q[1]))
		if poly.size() < 3:
			continue
		var res := Geometry2D.offset_polygon(poly, delta, Geometry2D.JOIN_MITER)
		for r in res:
			if Geometry2D.is_polygon_clockwise(r) and delta > 0.0:
				continue   # 넓힐 때 생기는 구멍은 버린다
			var arr: Array = []
			for q in r:
				arr.append([q.x, q.y])
			out.append(arr)
	return out


static func _min_y(poly: PackedVector2Array) -> float:
	var m := INF
	for q in poly:
		m = minf(m, q.y)
	return m


static func _max_y(poly: PackedVector2Array) -> float:
	var m := -INF
	for q in poly:
		m = maxf(m, q.y)
	return m


## 부위(또는 변형) 하나의 그림을 원본 시트에서 잘라 낸다. 돌려주는 값: {img(뒤집기 전, 시트 해상도), origin(시트 px 왼쪽 위)}
func _extract(desc: Dictionary) -> Dictionary:
	var key := str(desc.get("sheet", "main"))
	var s := _sheet(key)
	if s.is_empty():
		return {}
	var w: int = s["w"]
	var h: int = s["h"]
	var n := w * h
	var labels: PackedInt32Array = s["labels"]
	var data: PackedByteArray = (s["img"] as Image).get_data()
	var mask := PackedFloat32Array(); mask.resize(n)
	var soft := PackedFloat32Array(); soft.resize(n)
	var sthr := int(float(_sheet_info(key)["segment"].get("soft_alpha", 0.03)) * 255.0)
	for p in n:
		soft[p] = 1.0 if data[p * 4 + 3] > sthr else 0.0
	var comps: Array = desc.get("comps", [])
	if comps.is_empty() and desc.has("clip"):
		mask = soft.duplicate()   # 번호 없이 다각형만: 다각형 안의 모든 픽셀
	else:
		var want := {}
		for c in comps:
			want[int(c)] = true
		for p in n:
			if want.has(labels[p]):
				mask[p] = 1.0
	# grow: 자른 경계를 이만큼(px) 바깥으로 넓힌다 → 이웃 부위와 조금 겹쳐 이음매에 배경이 비치지 않는다 (cut 은 그만큼 좁힌다)
	var grow := float(desc.get("grow", 3.0))
	if desc.has("clip"):
		_apply_polys(mask, soft, w, h, _offset_polys(desc["clip"], grow), "clip")
	if desc.has("add"):
		_apply_polys(mask, soft, w, h, _offset_polys(desc["add"], grow), "add")
	if desc.has("cut"):
		_apply_polys(mask, soft, w, h, _offset_polys(desc["cut"], -grow), "cut")
	# 상자
	var minx := w
	var miny := h
	var maxx := -1
	var maxy := -1
	for p in n:
		if mask[p] > 0.0 and data[p * 4 + 3] > 0:
			var x := p % w
			var y := p / w
			if x < minx: minx = x
			if x > maxx: maxx = x
			if y < miny: miny = y
			if y > maxy: maxy = y
	if maxx < 0:
		push_error("빈 부위 (조각 번호·다각형을 확인): %s" % str(desc))
		return {}
	var pad := 6
	minx = maxi(minx - pad, 0)
	miny = maxi(miny - pad, 0)
	maxx = mini(maxx + pad, w - 1)
	maxy = mini(maxy + pad, h - 1)
	var cw := maxx - minx + 1
	var ch := maxy - miny + 1
	var out := PackedByteArray(); out.resize(cw * ch * 4)
	for y in ch:
		for x in cw:
			var sp := (y + miny) * w + (x + minx)
			var m := mask[sp]
			if m <= 0.0:
				continue
			var dp := (y * cw + x) * 4
			out[dp] = data[sp * 4]
			out[dp + 1] = data[sp * 4 + 1]
			out[dp + 2] = data[sp * 4 + 2]
			out[dp + 3] = int(data[sp * 4 + 3] * m)
	var img := Image.create_from_data(cw, ch, false, Image.FORMAT_RGBA8, out)
	img = load("res://tools/sheet_catalog.gd").defringe(img, 0.6)
	return {"img": img, "origin": Vector2(minx, miny)}


## 그림을 뼈대 방향(뒤집기·mirror)으로 바꾸고 줄여 저장한다. 돌려주는 값: 뼈대 좌표의 왼쪽 위(origin_rig).
func _finish_texture(ex: Dictionary, desc: Dictionary, key: String, out_png: String, out_scale: float) -> Vector2:
	var img: Image = ex["img"]
	var o: Vector2 = ex["origin"]
	var cw := img.get_width()
	var ch := img.get_height()
	var sw := _sheet_w(key)
	# 뼈대 좌표의 왼쪽 위: 뒤집으면 [W - (o.x + cw), W - o.x)
	var orx := o.x
	var flip := _flip()
	if flip:
		img.flip_x()
		orx = sw - (o.x + cw)
	if bool(desc.get("mirror", false)):
		img.flip_x()
		var pv := Vector2(desc["pivot"][0], desc["pivot"][1])
		if flip:
			pv.x = sw - pv.x
		# pivot 축 거울: [orx, orx+cw) → [2pv - orx - cw, 2pv - orx)
		orx = 2.0 * pv.x - orx - cw
	if out_scale != 1.0:
		img.resize(maxi(1, roundi(cw * out_scale)), maxi(1, roundi(ch * out_scale)), Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path(out_png))
	_write_import(out_png)
	return Vector2(orx, o.y)


## 밉맵을 켠 .import 를 둔다 (이미 있으면 그대로: uid 와 설정이 유지된다). 줄여 그리는 부위가 반짝이지 않게.
static func _write_import(png: String) -> void:
	var ip := ProjectSettings.globalize_path(png + ".import")
	if FileAccess.file_exists(ip):
		return
	var f := FileAccess.open(ip, FileAccess.WRITE)
	f.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\ncompress/mode=0\nmipmaps/generate=true\nmipmaps/limit=-1\nprocess/fix_alpha_border=true\nprocess/premult_alpha=false\ndetect_3d/compress_to=0\n")
	f.close()


## 볼록 껍질 (텍스처 px, 알파 0.5 넘는 픽셀의 줄 양 끝으로) → 꼭짓점 12개 이하로 줄인다.
static func _hull(img: Image) -> PackedVector2Array:
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var pts := PackedVector2Array()
	for y in h:
		var l := -1
		var r := -1
		for x in w:
			if d[(y * w + x) * 4 + 3] > 127:
				if l < 0: l = x
				r = x
		if l >= 0:
			pts.append(Vector2(l, y + 0.5))
			pts.append(Vector2(r + 1, y + 0.5))
	if pts.size() < 3:
		return PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() > 1 and hull[0] == hull[hull.size() - 1]:
		hull.remove_at(hull.size() - 1)
	while hull.size() > 12:
		# 넓이를 가장 적게 잃는 꼭짓점을 뺀다
		var best := 0
		var best_area := INF
		for i in hull.size():
			var a := hull[(i - 1 + hull.size()) % hull.size()]
			var b := hull[i]
			var c := hull[(i + 1) % hull.size()]
			var area := absf((b - a).cross(c - a))
			if area < best_area:
				best_area = area
				best = i
		hull.remove_at(best)
	return hull


static func _arr(v: Vector2) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01)]


func _cut() -> bool:
	var t0 := Time.get_ticks_msec()
	var parts: Dictionary = _spec["parts"]
	var out_scale := float(_spec.get("out_scale", 0.5))
	var dir := "res://art/rigs/%s" % _id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	# 1) 부위별 그림 (from 은 원본 부위의 그림을 같이 쓴다)
	var info := {}   # 이름 -> {tex, pivot_tex, sr, hull(뼈대 틀), pivot_rig, tip_rig}
	var chains: Dictionary = _spec.get("chains", {})
	# 사슬의 다음 마디 관절을 tip 기본값으로 (팔다리 각도 0 = 똑바로 아래)
	var tip_default := {}
	for cname in chains:
		var ch: Array = chains[cname]
		for k in ch.size() - 1:
			if ch[k] != null and ch[k + 1] != null:
				var child: Dictionary = parts[ch[k + 1]]
				tip_default[ch[k]] = child.get("attach", child.get("pivot"))
	for name in parts:
		var part: Dictionary = parts[name]
		if part.has("from"):
			continue
		var key := str(part.get("sheet", "main"))
		var ex := _extract(part)
		if ex.is_empty():
			return false
		var scale_k := out_scale * float(part.get("scale", 1.0))
		var png := "%s/%s.png" % [dir, name]
		var orig := _finish_texture(ex, part, key, png, scale_k)
		var p := _to_rig(name, part["pivot"])
		var sr := 0.0
		var tip = part.get("tip", tip_default.get(name, null))
		var tipv := Vector2.ZERO
		if tip != null:
			tipv = _to_rig(name, tip)
			var ax := tipv - p
			sr = PI / 2.0 - atan2(ax.y, ax.x)
		sr += deg_to_rad(float(part.get("rot", 0.0)))
		var tex_img := Image.load_from_file(ProjectSettings.globalize_path(png))
		var hull_tex := _hull(tex_img)
		var hull_bone := PackedVector2Array()
		for q in hull_tex:
			hull_bone.append(((q / scale_k + orig) - p).rotated(sr))
		var variants := {}
		for vname in part.get("variants", {}):
			var vd: Dictionary = part["variants"][vname].duplicate()
			if not vd.has("pivot"):
				vd["pivot"] = part["pivot"]
			var vkey := str(vd.get("sheet", key))
			vd["sheet"] = vkey   # 시트를 안 적은 변형은 부위와 같은 시트
			var vex := _extract(vd)
			if vex.is_empty():
				return false
			var vpng := "%s/%s@%s.png" % [dir, name, vname]
			var vorig := _finish_texture(vex, vd, vkey, vpng, scale_k)
			# 변형의 pivot 은 그 변형 그림의 좌표 (시트가 다르면 그 시트 기준으로 뒤집는다)
			var vp := Vector2(vd["pivot"][0], vd["pivot"][1])
			if _flip():
				vp.x = _sheet_w(vkey) - vp.x
			variants[vname] = {
				"tex": vpng, "pivot": _arr((vp - vorig) * scale_k),
				"rot": rad_to_deg(sr + deg_to_rad(float(vd.get("rot", 0.0)))),
			}
		info[name] = {
			"tex": png, "pivot_tex": (p - orig) * scale_k, "sr": sr, "hull": hull_bone,
			"p": p, "scale_k": scale_k, "variants": variants, "has_tip": tip != null, "tip": tipv,
		}
	for name in parts:
		var part: Dictionary = parts[name]
		if part.has("from"):
			var src: String = part["from"]
			if not info.has(src):
				push_error("from 의 원본 부위가 없다: %s ← %s" % [name, src])
				return false
			info[name] = info[src].duplicate()
	# 2) 뼈대: 부모 먼저 (부모 → 자식 순서로 정렬)
	var order: Array = []
	var placed := {}
	var guard := 0
	while order.size() < parts.size() and guard < 100:
		guard += 1
		for name in parts:
			if placed.has(name):
				continue
			var par := str(parts[name].get("parent", ""))
			if par == "" or placed.has(par):
				order.append(name)
				placed[name] = true
	if order.size() < parts.size():
		push_error("부모를 찾지 못한 부위가 있다 (parent 이름 확인)")
		return false
	var bones: Array = []
	var world := {}   # 이름 -> Transform2D (쉬는 자세, 뼈대 좌표, 뿌리 = 원점)
	var world_rot := {}
	for name in order:
		var part: Dictionary = parts[name]
		var inf: Dictionary = info[name]
		var par := str(part.get("parent", ""))
		var pos := Vector2.ZERO
		var rest_local := 0.0
		var rest_world := 0.0
		if par == "":
			rest_world = deg_to_rad(float(part["rest"])) if part.has("rest") else -float(inf["sr"])
			rest_local = rest_world
			world[name] = Transform2D(rest_local, Vector2.ZERO)
		else:
			var pinf: Dictionary = info[par]
			var own_pivot = part.get("pivot", parts[str(part["from"])]["pivot"] if part.has("from") else null)
			if not part.has("attach") and own_pivot == null:
				push_error("부위에 attach 도 pivot 도 없다: " + str(name))
				return false
			var at := _to_rig(par, part.get("attach", own_pivot))
			pos = (at - pinf["p"]).rotated(pinf["sr"])
			if part.has("rest"):
				rest_world = deg_to_rad(float(part["rest"]))
			else:
				rest_world = float(world_rot[par]) + float(pinf["sr"]) - float(inf["sr"])
			rest_local = rest_world - float(world_rot[par])
			world[name] = (world[par] as Transform2D) * Transform2D(rest_local, pos)
		world_rot[name] = rest_world
		var b := {
			"name": name, "parent": par, "pos": _arr(pos), "rest": snappedf(rad_to_deg(rest_local), 0.01),
			"tex": inf["tex"], "pivot": _arr(inf["pivot_tex"]), "rot": snappedf(rad_to_deg(inf["sr"]), 0.01),
			"tex_scale": snappedf(1.0 / float(inf["scale_k"]), 0.0001), "z": int(part.get("z", 0)),
		}
		var hull_arr: Array = []
		for q in inf["hull"]:
			hull_arr.append(_arr(q))
		b["hull"] = hull_arr
		if inf["has_tip"]:
			b["len"] = snappedf(((inf["tip"] as Vector2) - (inf["p"] as Vector2)).length(), 0.01)
		if part.has("modulate"):
			b["modulate"] = part["modulate"]
		if part.has("sole"):
			b["sole"] = _arr((_to_rig(name, part["sole"]) - inf["p"]).rotated(inf["sr"]))
		if part.has("chain"):
			b["chain"] = part["chain"]
		if not (inf["variants"] as Dictionary).is_empty():
			b["variants"] = inf["variants"]
		if part.has("hidden"):
			b["hidden"] = bool(part["hidden"])
		bones.append(b)
	# 3) 땅: 쉬는 자세에서 가장 낮은 발바닥 (없으면 가장 낮은 껍질 점)
	var ground := -INF
	var min_y := INF
	var feet_x: Array = []
	for b in bones:
		var t: Transform2D = world[b["name"]]
		for q in b["hull"]:
			var wq := t * Vector2(q[0], q[1])
			min_y = minf(min_y, wq.y)
		if b.has("sole"):
			var ws := t * Vector2(b["sole"][0], b["sole"][1])
			ground = maxf(ground, ws.y)
			feet_x.append(ws.x)
	if ground == -INF:
		for b in bones:
			var t: Transform2D = world[b["name"]]
			for q in b["hull"]:
				ground = maxf(ground, (t * Vector2(q[0], q[1])).y)
	var mid_x := 0.0
	for fx in feet_x:
		mid_x += fx / feet_x.size()
	# 4) 다리 (IK) 정보
	var legs: Array = []
	for leg_spec in _spec.get("legs", []):
		# "leg_f" (사슬 이름) 또는 {"chain": "leg_f", "knee_back": true} (무릎이 뒤로 꺾이는 다리 — 새·짐승 뒷다리)
		var cname := str(leg_spec["chain"]) if leg_spec is Dictionary else str(leg_spec)
		var ch: Array = chains.get(cname, [])
		if ch.is_empty():
			push_error("legs 의 사슬이 없다: " + str(cname))
			return false
		var leg := {"name": cname, "up": ch[0]}
		var bmap := {}
		for b in bones:
			bmap[b["name"]] = b
		if ch.size() >= 3 and ch[1] != null:
			leg["lo"] = ch[1]
			leg["foot"] = ch[2]
			leg["a"] = snappedf(Vector2(bmap[ch[1]]["pos"][0], bmap[ch[1]]["pos"][1]).length(), 0.01)
			leg["b"] = snappedf(Vector2(bmap[ch[2]]["pos"][0], bmap[ch[2]]["pos"][1]).length(), 0.01)
		else:
			leg["foot"] = ch[ch.size() - 1]
		if not bmap[leg["foot"]].has("sole"):
			push_error("다리 끝 부위에 sole 이 없다: " + str(leg["foot"]))
			return false
		if leg_spec is Dictionary and bool(leg_spec.get("knee_back", false)):
			leg["knee_back"] = true
		legs.append(leg)
	var rig := {
		"_설명": "tools/rig_cut.gd 가 data/rigs/%s.json 에서 만든 실행용 뼈대. 손으로 고치지 말고 설계도를 고쳐 다시 자른다." % _id,
		"id": _id, "version": 1, "faces_right": true,
		"game_scale": float(_spec.get("game_scale", 0.15)),
		"archetype": str(_spec.get("archetype", "humanoid")),
		"root_offset": _arr(Vector2(-mid_x, -ground)),
		"height": snappedf(ground - min_y, 0.01),
		"bones": bones, "legs": legs, "chains": chains,
	}
	for k in ["weapon_chain", "ground_guard", "ghost", "sockets", "poses"]:
		if _spec.has(k):
			var v = _spec[k]
			if k == "sockets":
				var socks := {}
				for sname in v:
					var sd: Dictionary = v[sname]
					var bone := str(sd["bone"])
					var inf: Dictionary = info[bone]
					socks[sname] = {"bone": bone, "pos": _arr((_to_rig(bone, sd["at"]) - inf["p"]).rotated(inf["sr"]))}
				v = socks
			rig[k] = v
	var f := FileAccess.open(ProjectSettings.globalize_path(dir + "/rig.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(rig, "  ", false))
	f.close()
	print("[rig_cut] %s: 부위 %d개, 키 %.0f px(시트) → 게임 약 %.0f px, %.1f초 → %s/rig.json" % [
		_id, bones.size(), ground - min_y, (ground - min_y) * float(rig["game_scale"]), (Time.get_ticks_msec() - t0) / 1000.0, ProjectSettings.globalize_path(dir)])
	return true

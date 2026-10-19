extends SceneTree
## 그림 시트(부위·조각·이펙트를 한 장에 모아 둔 투명 PNG)를 조각으로 나눠 목록을 만든다.
## 사용: Godot --headless --path . --script tools/sheet_catalog.gd -- <시트 폴더 또는 PNG ...> --out <출력 폴더> [--alpha 0.6] [--gap 3] [--min 900] [--preview 320]
## 결과: <출력>/<시트 이름>/catalog.json  ( {sheet, size, parts:[{id, rect:[x,y,w,h], pixels}]} — id 는 위→아래, 왼→오른 순서)
##       <출력>/<시트 이름>/c<번호>.png  (조각 미리보기, 긴 변 preview px 이하, 가장자리 색 번짐을 정리한 그림)
##       <출력>/<시트 이름>/overview.png (전체를 줄여 조각 상자를 색칠해 그린 그림)
## 조각은 불투명(alpha > --alpha)한 픽셀이 이어진 덩어리다. --gap 만큼 부풀려 가까운 덩어리는 한 조각으로 본다.
## 가장자리 정리: 반투명 테두리의 붉은·노란 번짐(배경 지우기 흔적)은 가장 가까운 불투명 픽셀의 색으로 바꾼다.

var ALPHA := 0.6
var GAP := 3
var MIN_PIXELS := 900
var PREVIEW := 320


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var inputs: Array[String] = []
	var out := ""
	var i := 0
	while i < args.size():
		var a := args[i]
		if a == "--out":
			out = args[i + 1]; i += 2; continue
		if a == "--alpha":
			ALPHA = float(args[i + 1]); i += 2; continue
		if a == "--gap":
			GAP = int(args[i + 1]); i += 2; continue
		if a == "--min":
			MIN_PIXELS = int(args[i + 1]); i += 2; continue
		if a == "--preview":
			PREVIEW = int(args[i + 1]); i += 2; continue
		inputs.append(a)
		i += 1
	if out == "" or inputs.is_empty():
		print("사용: ... -- <폴더|PNG ...> --out <폴더>")
		quit(1)
		return
	var files: Array[String] = []
	for p in inputs:
		if DirAccess.dir_exists_absolute(p):
			var d := DirAccess.open(p)
			for f in d.get_files():
				if f.to_lower().ends_with(".png"):
					files.append(p.path_join(f))
		else:
			files.append(p)
	for f in files:
		_process_sheet(f, out)
	quit()


static func sheet_key(path: String) -> String:
	var folder := path.get_base_dir().get_file()
	var stem := path.get_file().get_basename().replace(" ", "_")
	return (folder + "__" + stem).substr(0, 80)


func _process_sheet(path: String, out_root: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		print("읽기 실패: ", path)
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var solid := PackedByteArray()
	solid.resize(w * h)
	var athr := int(ALPHA * 255.0)
	for p in w * h:
		solid[p] = 1 if data[p * 4 + 3] > athr else 0
	# 부풀리기 (가로·세로 따로 — 상자 모양 팽창)
	var tmp := PackedByteArray(); tmp.resize(w * h)
	for y in h:
		var row := y * w
		var run := -100000
		for x in w:
			if solid[row + x] == 1: run = x
			if x - run <= GAP: tmp[row + x] = 1
		run = 100000
		for x in range(w - 1, -1, -1):
			if solid[row + x] == 1: run = x
			if run - x <= GAP: tmp[row + x] = 1
	var grown := PackedByteArray(); grown.resize(w * h)
	for x in w:
		var run := -100000
		for y in h:
			if tmp[y * w + x] == 1: run = y
			if y - run <= GAP: grown[y * w + x] = 1
		run = 100000
		for y in range(h - 1, -1, -1):
			if tmp[y * w + x] == 1: run = y
			if run - y <= GAP: grown[y * w + x] = 1
	# 연결 성분 (4방향, 스택)
	var label := PackedInt32Array(); label.resize(w * h)
	var comps: Array = []
	var stack := PackedInt32Array()
	for start in w * h:
		if grown[start] == 0 or label[start] != 0:
			continue
		var cid := comps.size() + 1
		var minx := w; var miny := h; var maxx := 0; var maxy := 0; var cnt := 0
		stack.clear()
		stack.append(start)
		label[start] = cid
		while stack.size() > 0:
			var q := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var qx := q % w
			var qy := q / w
			if solid[q] == 1:
				cnt += 1
				minx = mini(minx, qx); maxx = maxi(maxx, qx); miny = mini(miny, qy); maxy = maxi(maxy, qy)
			if qx > 0 and grown[q - 1] == 1 and label[q - 1] == 0: label[q - 1] = cid; stack.append(q - 1)
			if qx < w - 1 and grown[q + 1] == 1 and label[q + 1] == 0: label[q + 1] = cid; stack.append(q + 1)
			if qy > 0 and grown[q - w] == 1 and label[q - w] == 0: label[q - w] = cid; stack.append(q - w)
			if qy < h - 1 and grown[q + w] == 1 and label[q + w] == 0: label[q + w] = cid; stack.append(q + w)
		comps.append({"cid": cid, "rect": [minx, miny, maxx - minx + 1, maxy - miny + 1], "pixels": cnt})
	var parts: Array = []
	for c in comps:
		if c["pixels"] >= MIN_PIXELS:
			parts.append(c)
	# 위→아래(행 묶음 120px), 왼→오른 순서
	parts.sort_custom(func(a, b):
		var ra := int(a["rect"][1] / 120); var rb := int(b["rect"][1] / 120)
		if ra != rb: return ra < rb
		return a["rect"][0] < b["rect"][0])
	var key := sheet_key(path)
	var dir := out_root.path_join(key)
	DirAccess.make_dir_recursive_absolute(dir)
	var clean := defringe(img, ALPHA)
	var list: Array = []
	for n in parts.size():
		var c: Dictionary = parts[n]
		var r: Array = c["rect"]
		var crop := clean.get_region(Rect2i(r[0], r[1], r[2], r[3]))
		var s := minf(1.0, float(PREVIEW) / float(maxi(r[2], r[3])))
		if s < 1.0:
			crop.resize(maxi(1, int(r[2] * s)), maxi(1, int(r[3] * s)), Image.INTERPOLATE_LANCZOS)
		crop.save_png(dir.path_join("c%02d.png" % n))
		list.append({"id": n, "rect": r, "pixels": c["pixels"]})
	# 미리보기 전체 그림: 줄이고 상자 테두리
	var ov: Image = clean.duplicate()
	var cols := [Color.RED, Color.LIME, Color.CYAN, Color.YELLOW, Color.MAGENTA, Color.ORANGE, Color.WHITE]
	for n in parts.size():
		var r: Array = parts[n]["rect"]
		var col: Color = cols[n % cols.size()]
		for t in 3:
			for x in range(r[0], r[0] + r[2]):
				ov.set_pixel(x, clampi(r[1] + t, 0, h - 1), col)
				ov.set_pixel(x, clampi(r[1] + r[3] - 1 - t, 0, h - 1), col)
			for y in range(r[1], r[1] + r[3]):
				ov.set_pixel(clampi(r[0] + t, 0, w - 1), y, col)
				ov.set_pixel(clampi(r[0] + r[2] - 1 - t, 0, w - 1), y, col)
	var os := minf(1.0, 1200.0 / float(maxi(w, h)))
	if os < 1.0:
		ov.resize(int(w * os), int(h * os), Image.INTERPOLATE_BILINEAR)
	ov.save_png(dir.path_join("overview.png"))
	var f := FileAccess.open(dir.path_join("catalog.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"sheet": path, "key": key, "size": [w, h], "alpha": ALPHA, "gap": GAP, "parts": list}, "  "))
	f.close()
	print("%s: 조각 %d개 → %s" % [path.get_file(), list.size(), dir])


## 반투명 가장자리의 번진 색(배경 지우기 흔적)을 가장 가까운 불투명 픽셀 색으로 바꾼다.
## 알파는 그대로 두되, 아주 옅은(alpha < 0.08) 픽셀은 지운다. (다른 도구에서도 쓴다: SheetCatalog 대신 이 스크립트를 load 해서 defringe 를 부른다)
static func defringe(src: Image, alpha_solid := 0.6) -> Image:
	var img: Image = src.duplicate()
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var athr := int(alpha_solid * 255.0)
	var near := PackedInt32Array(); near.resize(w * h)
	for p in w * h:
		near[p] = p if d[p * 4 + 3] > athr else -1
	# 두 번 훑기(왼위→오른아래, 오른아래→왼위)로 가까운 불투명 픽셀 번호를 퍼뜨린다 (근사)
	for pass_i in 2:
		var ys := range(h) if pass_i == 0 else range(h - 1, -1, -1)
		var xs := range(w) if pass_i == 0 else range(w - 1, -1, -1)
		var step := -1 if pass_i == 0 else 1
		for y in ys:
			for x in xs:
				var p: int = int(y) * w + int(x)
				if near[p] >= 0 and near[p] == p:
					continue
				var best := near[p]
				var bx: int = int(x) + step
				var by: int = int(y) + step
				if bx >= 0 and bx < w and near[int(y) * w + bx] >= 0:
					var c := near[int(y) * w + bx]
					if best < 0 or _dist2(c, p, w) < _dist2(best, p, w): best = c
				if by >= 0 and by < h and near[by * w + int(x)] >= 0:
					var c2 := near[by * w + int(x)]
					if best < 0 or _dist2(c2, p, w) < _dist2(best, p, w): best = c2
				near[p] = best
	for p in w * h:
		var a: int = d[p * 4 + 3]
		if a > athr:
			continue
		if a < 20:
			d[p * 4 + 3] = 0
			continue
		var q := near[p]
		if q >= 0 and _dist2(q, p, w) < 400:
			d[p * 4] = d[q * 4]; d[p * 4 + 1] = d[q * 4 + 1]; d[p * 4 + 2] = d[q * 4 + 2]
		else:
			d[p * 4 + 3] = 0
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, d)


static func _dist2(a: int, b: int, w: int) -> int:
	var dx := a % w - b % w
	var dy := a / w - b / w
	return dx * dx + dy * dy

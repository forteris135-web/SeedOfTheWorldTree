extends SceneTree
## 지형 그림 조각 자르기 (그림 조각 기반 지형 시스템 — 설명서는 TERRAIN.md).
## 기획자가 준 투명 배경 시트에서 조각을 잘라 한 장(atlas)에 모으고, 조각마다 '발 딛는 선'을 재서 적어 둔다.
##
## 실행 (맥):
##   /Users/wj/Projects/SeedWT/godot --headless --path . -s res://tools/terrain_cut.gd -- canopy
##   그 뒤 tools/cloud_bootstrap.sh (또는 godot --headless --import) 로 새 그림을 들여온다.
##
## 읽는 것: data/terrain/<지역>.json 의 "cut" 부분
##   sheet  : 시트 경로 (res:// — 익스펜션 폴더는 읽기만 한다)
##   alpha / gap : 조각 나누기 기준 (불투명 기준값, 이만큼 떨어진 덩어리까지 한 조각)
##   pieces : [{name, role, src:[x,y,w,h], sheet?, scale?, walk?:[x0,x1], run?, keep?:"largest"|"all", clip?:[x,y,w,h]}]
##            src 는 시트 위의 대략적인 상자. 그 상자에 가장 많이 들어 있는 덩어리(+ 상자 안에 절반 넘게 든 덩어리)를 조각으로 쓴다.
##            scale 을 주면 그만큼 줄여서 넣는다 (아주 큰 그림 — 금 간 벽·가시).
##            walk 를 주면 자동으로 잰 '걷는 구간' 대신 그 값(조각 안 x, 원래 크기 px)을 쓴다.
##            clip 을 주면 고른 덩어리의 상자를 그 사각형(시트 px) 안으로 줄인다 (붙은 옆 그림을 곧게 잘라 낼 때 — 다각형 자르기는 없다).
##            atlas: false 면 atlas 에 넣지 않는다 (몸통 결 재료로만 쓰는 큰 그림).
##            top_line 을 주면 자동으로 잰 '발 딛는 선' 대신 그 꺾은선을 쓴다: [[x, y], …] (시트 px — 격자 미리보기에서 읽은 값).
##              난간·기둥·매단 등불처럼 발판 위로 솟은 것이 빽빽한 윗면으로 잡히는 조각(다리·발코니)에 쓴다.
##              걷는 구간은 walk 를 주지 않으면 꺾은선의 처음~끝 x. (가운데가 처진 흔들다리도 이 선을 펴서 평평한 발판에 맞춘다)
##   fill   : 이음매 없는 몸통 결 만들기 {from:[조각 이름], size, patch, cover, min_ratio, hue:[도], sat:[], val:[], vertical, bright, contrast?}
##            from 조각들에서 나무껍질 색(hue·sat·val 범위)만 있는 작은 네모(patch)를 찾아 이어 붙여 size×size 무늬를 만든다.
##   exports: [{name, src, sheet?, out:"res://...png", max:긴 변 px}] — 지형 밖에서 쓰는 단독 그림 (기록물 양피지 등)
##   extras : 금 간 벽처럼 조각을 가공한 그림 (cracked: 틈 빛을 끈 그림 / 틈 빛만 / 원래 그림)
##
## 쓰는 것 (art/terrain/<지역>/):
##   atlas.png   조각 모음 (밉맵 켬)
##   fill.png    몸통 결 (가로 결) / fill_v.png 세로 결 (벽·기둥용) — 반복(repeat)해서 깐다
##   pieces.json 잰 값: {atlas:[w,h], pieces:{이름:{role, rect:[x,y,w,h], size:[w,h], top:[…], step, walk:[x0,x1], walk_y, …}}}
##   screenshots/terrain_<지역>_pieces.png  미리보기 (빨간 선 = 발 딛는 선, 초록 = 걷는 구간 끝)
##
## '발 딛는 선'(top): 열마다 위에서 내려오며 처음으로 불투명 픽셀이 run(기본 12)px 이어지는 높이(빽빽한 윗면)를 찾고,
##   STEP px 마다 ±WIN px 안의 중앙값으로 고른다 (잎 끝 몇 장은 무시). 게임은 이 선을 충돌 윗면에 맞춰 조각을 휜다.

const SheetCatalog := preload("res://tools/sheet_catalog.gd")
const STEP := 8          # 윗선 표본 간격 (조각 px)
const WIN := 56          # 윗선 백분위 창 반폭 (조각 설명의 win 으로 바꿀 수 있다)
const PAD := 4           # atlas 조각 사이 여백
const ATLAS_W := 2048

var _region := ""
var _spec := {}
var _sheets := {}        # 경로 → {img, lab, w, h}
var _pieces := {}        # 이름 → {img: Image, meta: Dictionary}
var _order: Array = []
var _last_origin := Vector2.ZERO   # 마지막으로 자른 조각의 왼쪽 위 (시트 px — top_line 을 조각 px 로 옮길 때)
var _last_scale := 1.0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("사용: ... -s res://tools/terrain_cut.gd -- <지역>")
		quit(1)
		return
	_region = args[0]
	var path := "res://data/terrain/%s.json" % _region
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if not (parsed is Dictionary) or not parsed.has("cut"):
		print("읽기 실패 또는 cut 없음: ", path)
		quit(1)
		return
	_spec = parsed
	var cut: Dictionary = _spec["cut"]
	var out_dir := "res://art/terrain/%s" % _region
	var t0 := Time.get_ticks_msec()
	for p in cut.get("pieces", []):
		var img := _cut(p, cut)
		if img == null:
			print("  ! 조각 실패: ", p.get("name"))
			continue
		var meta := _measure(img, p)
		_pieces[p["name"]] = {"img": img, "meta": meta}
		if bool(p.get("atlas", true)):
			_order.append(p["name"])   # atlas: false 인 조각은 몸통 결 재료로만 쓰고 atlas 에는 넣지 않는다
		print("  %-10s %-7s %4dx%-4d 걷는 구간 %s  발 선 %.0f  (흔들림 %.0f)" % [p["name"], p.get("role", ""), img.get_width(), img.get_height(), str(meta.get("walk", [])), float(meta.get("walk_y", -1)), float(meta.get("wobble", 0))])
	for e in cut.get("extras", []):
		_make_extra(e, cut)
	for e in cut.get("exports", []):
		_export(e, cut)
	if cut.has("fill"):
		var fill := _make_fill(cut["fill"])
		if fill:
			# 결 방향: vertical 이면 만든 무늬가 세로 결(나무 줄기) → fill_v 로 쓰고, 돌린 것을 가로 결(fill)로
			var other := fill.duplicate()
			other.rotate_90(CLOCKWISE)
			if bool(cut["fill"].get("vertical", false)):
				_save(fill, out_dir + "/fill_v.png")
				_save(other, out_dir + "/fill.png")
			else:
				_save(fill, out_dir + "/fill.png")
				_save(other, out_dir + "/fill_v.png")
	if not _pieces.is_empty():
		var atlas_info := _pack()
		var atlas: Image = atlas_info["img"]
		_save(atlas, out_dir + "/atlas.png", true)
		var meta_all := {"region": _region, "atlas": [atlas.get_width(), atlas.get_height()], "step": STEP, "pieces": {}}
		for n in _order:
			meta_all["pieces"][n] = _pieces[n]["meta"]
		var f := FileAccess.open(ProjectSettings.globalize_path(out_dir + "/pieces.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(meta_all, "  ", false))
		f.close()
		_preview()
	print("[terrain_cut] %s: 조각 %d개, %.1f초 → %s" % [_region, _pieces.size(), (Time.get_ticks_msec() - t0) / 1000.0, out_dir])
	quit(0)


# ---------------------------------------------------------------- 시트 읽기·덩어리 번호
func _sheet(path: String, cut: Dictionary) -> Dictionary:
	if _sheets.has(path):
		return _sheets[path]
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null:
		print("시트 읽기 실패: ", path)
		return {}
	img.convert(Image.FORMAT_RGBA8)
	var alpha := float(cut.get("alpha", 0.8))
	var clean: Image = SheetCatalog.defringe(img, 0.6)
	_normalize_alpha(clean, float(cut.get("alpha_full", 0.95)))
	var info := {"img": clean, "w": clean.get_width(), "h": clean.get_height(), "lab": _label(clean, alpha, int(cut.get("gap", 1)))}
	_sheets[path] = info
	return info


## 시트의 '불투명' 픽셀은 알파가 0.97 안팎이라 배경이 살짝 비친다 → alpha_full 이상은 완전 불투명으로 늘린다 (가장자리 비율은 유지).
static func _normalize_alpha(img: Image, full: float) -> void:
	var d := img.get_data()
	var k := 1.0 / maxf(full, 0.01)
	for q in d.size() / 4:
		d[q * 4 + 3] = mini(255, int(d[q * 4 + 3] * k))
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)


## 불투명 덩어리마다 번호를 붙인다 (gap 만큼 부풀려 이어 붙임). 반투명 가장자리는 가장 가까운 덩어리 번호를 받는다.
func _label(img: Image, alpha: float, gap: int) -> PackedInt32Array:
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var athr := int(alpha * 255.0)
	var solid := PackedByteArray(); solid.resize(w * h)
	for p in w * h:
		solid[p] = 1 if d[p * 4 + 3] > athr else 0
	var tmp := PackedByteArray(); tmp.resize(w * h)
	for y in h:
		var row := y * w
		var run := -100000
		for x in w:
			if solid[row + x] == 1: run = x
			if x - run <= gap: tmp[row + x] = 1
		run = 100000
		for x in range(w - 1, -1, -1):
			if solid[row + x] == 1: run = x
			if run - x <= gap: tmp[row + x] = 1
	var grown := PackedByteArray(); grown.resize(w * h)
	for x in w:
		var run := -100000
		for y in h:
			if tmp[y * w + x] == 1: run = y
			if y - run <= gap: grown[y * w + x] = 1
		run = 100000
		for y in range(h - 1, -1, -1):
			if tmp[y * w + x] == 1: run = y
			if run - y <= gap: grown[y * w + x] = 1
	var lab := PackedInt32Array(); lab.resize(w * h)
	var stack := PackedInt32Array()
	var next_id := 0
	for start in w * h:
		if grown[start] == 0 or lab[start] != 0:
			continue
		next_id += 1
		stack.clear()
		stack.append(start)
		lab[start] = next_id
		while stack.size() > 0:
			var q := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var qx := q % w
			if qx > 0 and grown[q - 1] == 1 and lab[q - 1] == 0: lab[q - 1] = next_id; stack.append(q - 1)
			if qx < w - 1 and grown[q + 1] == 1 and lab[q + 1] == 0: lab[q + 1] = next_id; stack.append(q + 1)
			if q >= w and grown[q - w] == 1 and lab[q - w] == 0: lab[q - w] = next_id; stack.append(q - w)
			if q < w * (h - 1) and grown[q + w] == 1 and lab[q + w] == 0: lab[q + w] = next_id; stack.append(q + w)
	# 반투명 가장자리: 번호 있는 픽셀에서 너비 우선으로 번진다 (알파가 있는 픽셀로만)
	var queue := PackedInt32Array()
	for p in w * h:
		if lab[p] != 0:
			queue.append(p)
	var head := 0
	while head < queue.size():
		var q := queue[head]
		head += 1
		var qx := q % w
		for n in [q - 1, q + 1, q - w, q + w]:
			if n < 0 or n >= w * h:
				continue
			if (n == q - 1 and qx == 0) or (n == q + 1 and qx == w - 1):
				continue
			if lab[n] == 0 and d[n * 4 + 3] > 0:
				lab[n] = lab[q]
				queue.append(n)
	return lab


## 조각 하나: src 상자에 가장 많이 든 덩어리 + 상자 안에 절반 넘게 든 덩어리만 남겨 잘라 낸다.
func _cut(p: Dictionary, cut: Dictionary) -> Image:
	var sheet_path: String = p.get("sheet", cut.get("sheet", ""))
	var info := _sheet(sheet_path, cut)
	if info.is_empty():
		return null
	var img: Image = info["img"]
	var lab: PackedInt32Array = info["lab"]
	var w: int = info["w"]
	var h: int = info["h"]
	var r: Array = p["src"]
	var rx := clampi(int(r[0]), 0, w - 1)
	var ry := clampi(int(r[1]), 0, h - 1)
	var rw := clampi(int(r[2]), 1, w - rx)
	var rh := clampi(int(r[3]), 1, h - ry)
	var inside := {}
	for y in range(ry, ry + rh):
		for x in range(rx, rx + rw):
			var l := lab[y * w + x]
			if l != 0:
				inside[l] = int(inside.get(l, 0)) + 1
	if inside.is_empty():
		return null
	var total := {}
	for l in inside:
		total[l] = 0
	for q in w * h:
		var l := lab[q]
		if l != 0 and total.has(l):
			total[l] += 1
	var best := -1
	for l in inside:
		if best < 0 or inside[l] > inside[best]:
			best = l
	var keep := {best: true}
	if str(p.get("keep", "")) != "largest":
		for l in inside:
			if float(inside[l]) >= 0.5 * float(total[l]):
				keep[l] = true
	# 남길 덩어리의 경계 상자
	var minx := w; var miny := h; var maxx := -1; var maxy := -1
	for q in w * h:
		if keep.has(lab[q]):
			var x := q % w
			var y := q / w
			minx = mini(minx, x); maxx = maxi(maxx, x); miny = mini(miny, y); maxy = maxi(maxy, y)
	if maxx < 0:
		return null
	if p.has("clip"):
		var c: Array = p["clip"]
		minx = maxi(minx, int(c[0])); miny = maxi(miny, int(c[1]))
		maxx = mini(maxx, int(c[0]) + int(c[2]) - 1); maxy = mini(maxy, int(c[1]) + int(c[3]) - 1)
	var cw := maxx - minx + 1
	var ch := maxy - miny + 1
	var src := img.get_data()
	var out := PackedByteArray(); out.resize(cw * ch * 4)
	for y in ch:
		for x in cw:
			var q := (miny + y) * w + (minx + x)
			if keep.has(lab[q]):
				var o := (y * cw + x) * 4
				out[o] = src[q * 4]; out[o + 1] = src[q * 4 + 1]; out[o + 2] = src[q * 4 + 2]; out[o + 3] = src[q * 4 + 3]
	var piece := Image.create_from_data(cw, ch, false, Image.FORMAT_RGBA8, out)
	var used := piece.get_used_rect()
	piece = _trim(piece)
	var s := float(p.get("scale", 1.0))
	_last_origin = Vector2(minx + maxi(used.position.x, 0), miny + maxi(used.position.y, 0))
	_last_scale = s
	if s < 0.999:
		piece = _resize(piece, maxi(1, roundi(piece.get_width() * s)), maxi(1, roundi(piece.get_height() * s)))
	return piece


## 투명한 가장자리를 잘라 낸다 (알파 8 이하는 투명으로 본다).
static func _trim(img: Image) -> Image:
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return img
	return img.get_region(used)


## 줄이기 전 투명 픽셀의 색을 옆 색으로 채워 (어두운 테두리 방지) 줄인다.
static func _resize(img: Image, nw: int, nh: int) -> Image:
	var out: Image = img.duplicate()
	_bleed(out, 6)
	out.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	return out


## 투명 픽셀(알파 0)의 RGB 를 이웃 불투명 픽셀 색으로 몇 겹 채운다 (알파는 그대로).
static func _bleed(img: Image, passes: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var filled := PackedByteArray(); filled.resize(w * h)
	for p in w * h:
		filled[p] = 1 if d[p * 4 + 3] > 0 else 0
	for it in passes:
		var nd := d.duplicate()
		var nf := filled.duplicate()
		for y in h:
			for x in w:
				var p := y * w + x
				if filled[p] == 1:
					continue
				var r := 0; var g := 0; var b := 0; var n := 0
				for o in [[-1, 0], [1, 0], [0, -1], [0, 1]]:
					var xx: int = x + o[0]
					var yy: int = y + o[1]
					if xx < 0 or yy < 0 or xx >= w or yy >= h:
						continue
					var q := yy * w + xx
					if filled[q] == 1:
						r += d[q * 4]; g += d[q * 4 + 1]; b += d[q * 4 + 2]; n += 1
				if n > 0:
					nd[p * 4] = r / n; nd[p * 4 + 1] = g / n; nd[p * 4 + 2] = b / n
					nf[p] = 1
		d = nd
		filled = nf
	img.set_data(w, h, false, Image.FORMAT_RGBA8, d)


# ---------------------------------------------------------------- 재기
## 윗선·걷는 구간을 잰다.
## 1) 열마다 '빽빽한 윗면'(불투명 픽셀이 run px 이어지기 시작하는 높이)을 찾는다.
## 2) STEP px 마다 ±WIN px 안 값들의 PCT 백분위(가운데보다 조금 아래)를 고르고, 이웃 표본과 한 번 더 고르게 한다
##    → 잎 덤불이 군데군데 솟은 것은 무시하고 가지의 큰 굽이만 따르는 선 (게임은 이 선을 펴서 충돌 윗면에 맞춘다).
## 3) 걷는 구간(walk): 선이 조각 가운데 높이에서 크게 벗어나지 않고(위 50·아래 40) 아래가 25px 넘게 차 있는 가장 긴 구간.
##    걷는 역할(branch·slab·ground·ledge)에만 잰다. 조각 설명에 walk 를 주면 그 값을 쓴다.
const WALK_ROLES := ["branch", "slab", "ground", "ledge"]
const PCT := 0.6


func _measure(img: Image, p: Dictionary) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	var run := int(p.get("run", 12))
	var dense := PackedInt32Array(); dense.resize(w)
	var thick := PackedInt32Array(); thick.resize(w)
	for x in w:
		dense[x] = -1
		var cnt := 0
		for y in h:
			if d[(y * w + x) * 4 + 3] > 127:
				cnt += 1
				if cnt >= run and dense[x] < 0:
					dense[x] = y - run + 1
			else:
				if dense[x] >= 0:
					break
				cnt = 0
		thick[x] = cnt
	var n := int(ceil(float(w - 1) / STEP)) + 1
	var win := int(p.get("win", WIN))
	var raw: Array = []
	for i in n:
		var cx := mini(i * STEP, w - 1)
		var vals: Array = []
		for x in range(maxi(0, cx - win), mini(w, cx + win + 1)):
			if dense[x] >= 0:
				vals.append(dense[x])
		if vals.size() < win / 2:
			raw.append(-1)
		else:
			vals.sort()
			raw.append(int(vals[mini(vals.size() - 1, int(vals.size() * PCT))]))
	var top: Array = []
	for i in n:
		if raw[i] < 0:
			top.append(-1)
			continue
		var s := 0.0
		var c := 0
		for k in range(maxi(0, i - 2), mini(n, i + 3)):
			if raw[k] >= 0:
				s += raw[k]
				c += 1
		top.append(roundi(s / c))
	var meta := {"role": p.get("role", ""), "size": [w, h], "top": top}
	if p.has("top_line"):
		return _measure_line(p, meta, d, w, h, n)
	if not (str(p.get("role", "")) in WALK_ROLES) and not p.has("walk"):
		return meta
	var mid: Array = []
	for i in range(n / 4, n - n / 4):
		if top[i] >= 0:
			mid.append(top[i])
	if mid.is_empty():
		return meta
	mid.sort()
	var mg: int = mid[mid.size() / 2]
	var good := PackedByteArray(); good.resize(n)
	for i in n:
		var cx := mini(i * STEP, w - 1)
		good[i] = 1 if top[i] >= 0 and top[i] >= mg - 50 and top[i] <= mg + 40 and thick[cx] >= 25 else 0
	# 한두 표본 빈 곳은 메워 준다
	for i in range(1, n - 1):
		if good[i] == 0 and good[i - 1] == 1 and (good[i + 1] == 1 or (i + 2 < n and good[i + 2] == 1)) and top[i] >= 0:
			good[i] = 1
	var best_a := -1
	var best_b := -2
	var a := -1
	for i in n + 1:
		if i < n and good[i] == 1:
			if a < 0:
				a = i
		elif a >= 0:
			if i - 1 - a > best_b - best_a:
				best_a = a
				best_b = i - 1
			a = -1
	if best_a < 0:
		return meta
	var walk := [best_a * STEP, mini(best_b * STEP, w - 1)]
	if p.has("walk"):
		walk = [int(p["walk"][0]), int(p["walk"][1])]
	# 걷는 구간 끝 다듬기: 끝 24px 안의 열 90% 이상이 발 선 아래 8px 까지 차 있을 때까지 안쪽으로 줄인다
	# (둥근 끝·잎 사이 틈 위에 충돌 끝이 오면 발밑이 비어 보인다)
	var solid_ok := func(x: int) -> bool:
		var i := clampi(int(round(float(x) / STEP)), 0, n - 1)
		return dense[x] >= 0 and top[i] >= 0 and dense[x] <= top[i] + 8 and thick[x] >= 16
	var end_ok := func(x0: int, x1: int) -> bool:
		var good_n := 0
		var all_n := 0
		for x in range(maxi(0, x0), mini(w, x1 + 1)):
			all_n += 1
			if solid_ok.call(x):
				good_n += 1
		return all_n > 0 and good_n >= all_n * 0.9
	var guard := 0
	while walk[1] - walk[0] > 80 and not end_ok.call(walk[0], walk[0] + 24) and guard < 40:
		walk[0] += STEP / 2
		guard += 1
	guard = 0
	while walk[1] - walk[0] > 80 and not end_ok.call(walk[1] - 24, walk[1]) and guard < 40:
		walk[1] -= STEP / 2
		guard += 1
	var span: Array = []
	for i in range(int(walk[0] / STEP), int(walk[1] / STEP) + 1):
		if i < n and top[i] >= 0:
			span.append(top[i])
	span.sort()
	meta["walk"] = walk
	meta["walk_y"] = span[span.size() / 2] if not span.is_empty() else mg
	meta["wobble"] = (span[-1] - span[0]) if not span.is_empty() else 0
	# 두께(depth): 걷는 구간에서 윗면부터 처음 빈 곳까지 이어진 불투명 높이의 중앙값 (얇은 발판 충돌 높이와 견줄 때 쓴다)
	var th: Array = []
	for x in range(int(walk[0]), int(walk[1]) + 1, 4):
		if dense[x] >= 0:
			th.append(thick[x])
	th.sort()
	meta["depth"] = th[th.size() / 2] if not th.is_empty() else 0
	return meta


## top_line(시트 px 꺾은선)으로 발 딛는 선을 정한다 — 난간·등불이 솟은 조각용. 조각 px 로 옮겨 STEP 마다 이어 칠하고,
## 걷는 구간(walk, 없으면 꺾은선 처음~끝)·발 선 높이(walk_y)·흔들림·두께(depth: 선 아래로 이어진 불투명 높이의 중앙값)를 적는다.
func _measure_line(p: Dictionary, meta: Dictionary, d: PackedByteArray, w: int, h: int, n: int) -> Dictionary:
	var pts: Array = []
	for q in p["top_line"]:
		pts.append(Vector2((float(q[0]) - _last_origin.x) * _last_scale, (float(q[1]) - _last_origin.y) * _last_scale))
	pts.sort_custom(func(a, b): return a.x < b.x)
	if pts.is_empty():
		return meta
	var top: Array = []
	for i in n:
		var cx := float(mini(i * STEP, w - 1))
		var y: float = pts[0].y
		if cx >= pts[-1].x:
			y = pts[-1].y
		else:
			for k in range(1, pts.size()):
				if cx <= pts[k].x:
					var a: Vector2 = pts[k - 1]
					var b: Vector2 = pts[k]
					y = lerpf(a.y, b.y, clampf((cx - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0))
					break
		top.append(clampi(roundi(y), 0, h - 1))
	meta["top"] = top
	var walk := [clampi(roundi(pts[0].x), 0, w - 1), clampi(roundi(pts[-1].x), 0, w - 1)]
	if p.has("walk"):
		walk = [int(p["walk"][0]), int(p["walk"][1])]
	var span: Array = []
	var th: Array = []
	for i in range(int(walk[0] / STEP), int(walk[1] / STEP) + 1):
		if i >= n:
			break
		span.append(top[i])
		var x := mini(i * STEP, w - 1)
		var cnt := 0
		for y in range(int(top[i]), h):
			if d[(y * w + x) * 4 + 3] > 127:
				cnt += 1
			elif cnt > 0:
				break
		th.append(cnt)
	span.sort()
	th.sort()
	meta["walk"] = walk
	meta["walk_y"] = span[span.size() / 2] if not span.is_empty() else 0
	meta["wobble"] = (span[-1] - span[0]) if not span.is_empty() else 0
	meta["depth"] = th[th.size() / 2] if not th.is_empty() else 0
	meta["line"] = true
	return meta


# ---------------------------------------------------------------- 가공 그림
## 금 간 벽: 원래 그림에서 아주 밝고 노란 '틈 빛' 픽셀을 찾아 세 장을 만든다.
##   <name>_closed : 틈 빛을 둘레 나무껍질 색으로 메운 그림 (아직 안 갈라진 벽)
##   <name>_glow   : 틈 빛만 (더하기 혼합으로 숨 쉬듯 빛나게)
##   <name>        : 원래 그림 (맞을수록 이 그림이 드러난다)
func _make_extra(e: Dictionary, cut: Dictionary) -> void:
	var img := _cut(e, cut)
	if img == null:
		print("  ! 가공 그림 실패: ", e.get("name"))
		return
	var kind := str(e.get("kind", ""))
	if kind == "cracked":
		# 먼저 줄인다 (틈 메우기가 픽셀마다 여러 번 돌기 때문)
		var s0 := float(e.get("out_scale", 1.0))
		if s0 < 0.999:
			img = _resize(img, roundi(img.get_width() * s0), roundi(img.get_height() * s0))
		var w := img.get_width()
		var h := img.get_height()
		var d := img.get_data()
		var glow := PackedByteArray(); glow.resize(w * h * 4)
		var mask := PackedFloat32Array(); mask.resize(w * h)
		for q in w * h:
			var r := d[q * 4] / 255.0
			var g := d[q * 4 + 1] / 255.0
			var b := d[q * 4 + 2] / 255.0
			var a := d[q * 4 + 3] / 255.0
			var lum := 0.299 * r + 0.587 * g + 0.114 * b
			var warm := (r + g) * 0.5 - b
			var k := clampf((lum - 0.55) / 0.3, 0.0, 1.0) * clampf((warm - 0.08) / 0.2, 0.0, 1.0) * a
			mask[q] = k
			glow[q * 4] = d[q * 4]; glow[q * 4 + 1] = d[q * 4 + 1]; glow[q * 4 + 2] = d[q * 4 + 2]
			glow[q * 4 + 3] = int(clampf(k * 255.0, 0.0, 255.0))
		# 틈 빛을 메운 그림: 빛 픽셀을 둘레의 어두운 껍질색(빛 아닌 이웃의 평균, 여러 번 번짐)으로 바꾼다
		var closed := d.duplicate()
		var known := PackedByteArray(); known.resize(w * h)
		for q in w * h:
			known[q] = 1 if mask[q] < 0.15 else 0
		for it in 40:
			var changed := false
			var nc := closed.duplicate()
			var nk := known.duplicate()
			for y in h:
				for x in w:
					var q := y * w + x
					if known[q] == 1:
						continue
					var rr := 0; var gg := 0; var bb := 0; var cnt := 0
					for o in [-1, 1, -w, w]:
						var nq: int = q + o
						if nq < 0 or nq >= w * h:
							continue
						if known[nq] == 1 and closed[nq * 4 + 3] > 0:
							rr += closed[nq * 4]; gg += closed[nq * 4 + 1]; bb += closed[nq * 4 + 2]; cnt += 1
					if cnt > 0:
						nc[q * 4] = int(rr / cnt * 0.92); nc[q * 4 + 1] = int(gg / cnt * 0.9); nc[q * 4 + 2] = int(bb / cnt * 0.9)
						nk[q] = 1
						changed = true
			closed = nc
			known = nk
			if not changed:
				break
		# 메운 자리에 어두운 금 한 줄을 남긴다 (빛 세기가 높던 곳일수록 어둡게)
		for q in w * h:
			var k := mask[q]
			if k > 0.15:
				var dark := 1.0 - 0.35 * k
				closed[q * 4] = int(closed[q * 4] * dark); closed[q * 4 + 1] = int(closed[q * 4 + 1] * dark); closed[q * 4 + 2] = int(closed[q * 4 + 2] * dark)
		var name := str(e["name"])
		# 밝기 맞추기 (bright): 나무 그림이 주변 지형보다 어두우면 굽기 전에 밝힌다 (틈 빛 그림은 그대로)
		var br := float(e.get("bright", 1.0))
		if absf(br - 1.0) > 0.001:
			for arr in [d, closed]:
				for q in w * h:
					for ch in 3:
						arr[q * 4 + ch] = mini(255, int(arr[q * 4 + ch] * br))
			img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, d)
		var ims := {name: img, name + "_closed": Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, closed), name + "_glow": Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, glow)}
		# 틈이 지나는 가로 자리(틈 빛 무게중심, 0~1) — 좁은 벽은 이 둘레를 잘라 쓴다
		var sx := 0.0
		var sw := 0.0
		for q in w * h:
			sx += mask[q] * float(q % w)
			sw += mask[q]
		var crack_x := (sx / sw / float(w)) if sw > 0.0 else 0.5
		for k2 in ims:
			var im: Image = ims[k2]
			_pieces[k2] = {"img": im, "meta": {"role": "cracked" if k2 == name else "cracked_layer", "size": [im.get_width(), im.get_height()], "top": [], "crack_x": snappedf(crack_x, 0.001)}}
			_order.append(k2)
		print("  %-10s 금 간 벽 세 장 (%dx%d, 틈 가로 %.2f)" % [name, w, h, crack_x])


## 단독 그림 (지형 밖에서 쓰는 것): 잘라서 긴 변 max px 로 줄여 out 에 저장한다.
func _export(e: Dictionary, cut: Dictionary) -> void:
	var img := _cut(e, cut)
	if img == null:
		print("  ! 단독 그림 실패: ", e.get("name"))
		return
	var mx := int(e.get("max", 0))
	if mx > 0 and maxi(img.get_width(), img.get_height()) > mx:
		var s := float(mx) / float(maxi(img.get_width(), img.get_height()))
		img = _resize(img, roundi(img.get_width() * s), roundi(img.get_height() * s))
	_save(img, str(e["out"]))
	print("  단독 그림 %s → %s (%dx%d)" % [e["name"], e["out"], img.get_width(), img.get_height()])


# ---------------------------------------------------------------- 몸통 결 (이음매 없는 무늬)
## 나무껍질 색만 있는 작은 네모를 여러 조각에서 찾아, 가장자리를 부드럽게 해 둥글게(가장자리가 이어지게) 겹쳐 붙인다.
func _make_fill(f: Dictionary) -> Image:
	var size := int(f.get("size", 512))
	var patch := int(f.get("patch", 64))
	var hue: Array = f.get("hue", [16, 50])
	var sat: Array = f.get("sat", [0.06, 0.6])
	var val: Array = f.get("val", [0.25, 0.97])
	var cands: Array = []   # [Image(patch)]
	for name in f.get("from", []):
		if not _pieces.has(name):
			continue
		var img: Image = _pieces[name]["img"]
		var w := img.get_width()
		var h := img.get_height()
		var d := img.get_data()
		var ok := PackedByteArray(); ok.resize(w * h)
		for q in w * h:
			var a := d[q * 4 + 3]
			if a < 250:
				continue
			var c := Color8(d[q * 4], d[q * 4 + 1], d[q * 4 + 2])
			var hd := c.h * 360.0
			if hd >= float(hue[0]) and hd <= float(hue[1]) and c.s >= float(sat[0]) and c.s <= float(sat[1]) and c.v >= float(val[0]) and c.v <= float(val[1]):
				ok[q] = 1
		# 적분 영상으로 네모 안의 '껍질' 비율을 빠르게 센다
		var integ := PackedInt32Array(); integ.resize((w + 1) * (h + 1))
		for y in h:
			var rs := 0
			for x in w:
				rs += ok[y * w + x]
				integ[(y + 1) * (w + 1) + x + 1] = integ[y * (w + 1) + x + 1] + rs
		var y0 := 0
		while y0 + patch <= h:
			var x0 := 0
			while x0 + patch <= w:
				var s := integ[(y0 + patch) * (w + 1) + x0 + patch] - integ[y0 * (w + 1) + x0 + patch] - integ[(y0 + patch) * (w + 1) + x0] + integ[y0 * (w + 1) + x0]
				if s >= patch * patch * float(f.get("min_ratio", 0.93)):
					cands.append(img.get_region(Rect2i(x0, y0, patch, patch)))
					x0 += patch / 2
				else:
					x0 += 6
			y0 += 10
	print("  몸통 결 후보 네모 %d개" % cands.size())
	if cands.is_empty():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261019
	# 1) 바탕: 격자로 빈틈 없이 깐다. 2) 그 위에 무작위 자리로 가장자리가 부드러운 네모를 덮어 붙여(평균이 아니라 덮기 — 결이 뭉개지지 않게)
	#    격자 자국을 지운다. 모든 자리는 둥글게(넘치면 반대편으로) 감아서 이음매가 없다.
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var od := out.get_data()
	for gy in range(0, size, patch):
		for gx in range(0, size, patch):
			_paste(od, size, _pick_patch(cands, rng), Vector2i(gx, gy), patch, null)
	var mask := PackedFloat32Array(); mask.resize(patch * patch)
	var edge := maxf(patch * 0.45, 4.0)
	for y in patch:
		for x in patch:
			var dx := minf(x + 0.5, patch - x - 0.5)
			var dy := minf(y + 0.5, patch - y - 0.5)
			mask[y * patch + x] = smoothstep(0.0, edge, minf(dx, dy))
	for i in int(float(size * size) / float(patch * patch) * float(f.get("cover", 6.0))):
		_paste(od, size, _pick_patch(cands, rng), Vector2i(rng.randi_range(0, size - 1), rng.randi_range(0, size - 1)), patch, mask)
	# 밝기 맞추기 (bright): 재료 그림이 어두우면 굽기 전에 밝힌다 (게임의 색 곱하기는 1 을 넘지 못한다)
	var br := float(f.get("bright", 1.0))
	if absf(br - 1.0) > 0.001:
		for q in size * size:
			for ch in 3:
				od[q * 4 + ch] = mini(255, int(od[q * 4 + ch] * br))
	out.set_data(size, size, false, Image.FORMAT_RGBA8, od)
	# 대비 (contrast): 덮어 붙이며 흐려진 결을 또렷하게 — 평균 밝기는 그대로 두고 밝기 차이를 그만큼 키운다 (없으면 그대로)
	if f.has("contrast"):
		_contrast(out, float(f["contrast"]))
	return out


## 평균 밝기 둘레로 밝기 차이를 k 배 (색 비율은 유지).
static func _contrast(img: Image, k: float) -> void:
	var m := _lum_stats([img]).x
	var d := img.get_data()
	for q in d.size() / 4:
		var r := d[q * 4] / 255.0
		var g := d[q * 4 + 1] / 255.0
		var b := d[q * 4 + 2] / 255.0
		var l := 0.299 * r + 0.587 * g + 0.114 * b
		var nl := clampf(m + (l - m) * k, 0.0, 1.0)
		var s := nl / maxf(l, 0.004)
		d[q * 4] = int(clampf(r * s, 0.0, 1.0) * 255.0)
		d[q * 4 + 1] = int(clampf(g * s, 0.0, 1.0) * 255.0)
		d[q * 4 + 2] = int(clampf(b * s, 0.0, 1.0) * 255.0)
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)


static func _pick_patch(cands: Array, rng: RandomNumberGenerator) -> PackedByteArray:
	var c: Image = cands[rng.randi_range(0, cands.size() - 1)]
	if rng.randf() < 0.5:
		c = c.duplicate()
		c.flip_x()
	return c.get_data()


## 네모 하나를 (감아 가며) 덮어 붙인다. mask 가 없으면 그대로 덮는다.
static func _paste(od: PackedByteArray, size: int, cd: PackedByteArray, at: Vector2i, patch: int, mask) -> void:
	for y in patch:
		for x in patch:
			var o := (posmod(at.y + y, size) * size + posmod(at.x + x, size)) * 4
			var s := (y * patch + x) * 4
			var m := 1.0 if mask == null else float(mask[y * patch + x])
			if m <= 0.0:
				continue
			for ch in 3:
				od[o + ch] = int(lerpf(od[o + ch], cd[s + ch], m))
			od[o + 3] = 255


## 평균 밝기는 그대로 두고 밝기 퍼짐(표준편차)을 후보 네모들과 같게 맞춘다.
static func _restore_contrast(img: Image, cands: Array) -> void:
	var target := _lum_stats(cands)
	var cur := _lum_stats([img])
	if cur.y < 0.001:
		return
	var k := clampf(target.y / cur.y, 1.0, 2.2)
	var d := img.get_data()
	for q in d.size() / 4:
		for ch in 3:
			var v := float(d[q * 4 + ch]) / 255.0
			d[q * 4 + ch] = int(clampf(cur.x + (v - cur.x) * k, 0.0, 1.0) * 255.0)
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)


static func _lum_stats(imgs: Array) -> Vector2:
	var s := 0.0
	var s2 := 0.0
	var n := 0
	for im in imgs:
		var d: PackedByteArray = (im as Image).get_data()
		for q in range(0, d.size() / 4, 3):
			var l := (0.299 * d[q * 4] + 0.587 * d[q * 4 + 1] + 0.114 * d[q * 4 + 2]) / 255.0
			s += l
			s2 += l * l
			n += 1
	if n == 0:
		return Vector2.ZERO
	var m := s / n
	return Vector2(m, sqrt(maxf(s2 / n - m * m, 0.0)))


# ---------------------------------------------------------------- 모으기·저장
## 높이 순으로 선반에 올려 한 장으로 모은다 (조각 사이 PAD px). 조각 자리를 meta.rect 에 적는다.
func _pack() -> Dictionary:
	var names := _order.duplicate()
	names.sort_custom(func(a, b): return (_pieces[a]["img"] as Image).get_height() > (_pieces[b]["img"] as Image).get_height())
	var x := PAD
	var y := PAD
	var row_h := 0
	var places := {}
	for n in names:
		var im: Image = _pieces[n]["img"]
		if x + im.get_width() + PAD > ATLAS_W:
			x = PAD
			y += row_h + PAD
			row_h = 0
		places[n] = Vector2i(x, y)
		x += im.get_width() + PAD
		row_h = maxi(row_h, im.get_height())
	var total_h := y + row_h + PAD
	total_h = int(ceil(total_h / 4.0)) * 4
	if total_h > 4096:
		print("  ! atlas 가 너무 크다: ", total_h)
	var atlas := Image.create(ATLAS_W, total_h, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for n in names:
		var im: Image = _pieces[n]["img"]
		var pos: Vector2i = places[n]
		atlas.blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), pos)
		_pieces[n]["meta"]["rect"] = [pos.x, pos.y, im.get_width(), im.get_height()]
	_bleed(atlas, 3)
	return {"img": atlas}


## PNG 로 저장하고, 처음 저장하는 그림이면 밉맵을 켠 .import 를 같이 만든다 (줄여 보이는 지형이 지글거리지 않게).
## vram: true 면 GPU 압축(VRAM 압축 — 모바일 ETC2; high_quality 를 켜면 ASTC)으로 들여온다 — 큰 atlas 의 메모리를 약 1/4 로 (그림 결이 커서 압축 티가 거의 안 난다).
func _save(img: Image, res_path: String, vram := false) -> void:
	var abs := ProjectSettings.globalize_path(res_path)
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	img.save_png(abs)
	var imp := abs + ".import"
	if not FileAccess.file_exists(imp):
		var f := FileAccess.open(imp, FileAccess.WRITE)
		f.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\ncompress/mode=%d\nmipmaps/generate=true\nprocess/fix_alpha_border=true\n" % (2 if vram else 0))
		f.close()


## 미리보기: atlas 를 어두운 바탕에 그리고, 발 딛는 선(빨강, 걷는 구간 밖은 옅게)·걷는 구간 끝(초록)을 겹쳐 그린다.
func _preview() -> void:
	var first: Image = _pieces[_order[0]]["img"]
	var aw := ATLAS_W
	var ah := 0
	for n in _order:
		var r: Array = _pieces[n]["meta"]["rect"]
		ah = maxi(ah, int(r[1]) + int(r[3]) + PAD)
	var img := Image.create(aw, ah, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.08, 0.09, 0.12))
	for n in _order:
		var im: Image = _pieces[n]["img"]
		var meta: Dictionary = _pieces[n]["meta"]
		var r: Array = meta["rect"]
		var ox := int(r[0])
		var oy := int(r[1])
		img.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(ox, oy))
		var top: Array = meta.get("top", [])
		if not meta.has("walk"):
			continue
		var walk: Array = meta["walk"]
		for k in top.size() - 1:
			if top[k] < 0 or top[k + 1] < 0:
				continue
			var inside: bool = k * STEP >= walk[0] and k * STEP <= walk[1]
			var c := Color(1, 0.15, 0.15) if inside else Color(1, 0.6, 0.6, 0.6)
			for dx in STEP:
				var px := ox + k * STEP + dx
				var py := oy + int(lerpf(top[k], top[k + 1], dx / float(STEP)))
				for t in 2:
					if px < aw and py + t >= 0 and py + t < ah:
						img.set_pixel(px, py + t, c)
		for wx in walk:
			for dy in range(-24, 24):
				var py := oy + int(float(meta["walk_y"])) + dy
				var px := ox + int(wx)
				if py >= 0 and py < ah and px < aw:
					img.set_pixel(px, py, Color(0.2, 1, 0.3))
	var path := ProjectSettings.globalize_path("res://screenshots/terrain_%s_pieces.png" % _region)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("  미리보기: ", path)

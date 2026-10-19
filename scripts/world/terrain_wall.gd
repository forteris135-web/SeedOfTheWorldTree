class_name TerrainWall
extends RefCounted
## 벽 조각 (그림 조각 지형 — TERRAIN.md). 지역 그림 옷에 wall 역할 조각(세로로 긴 줄기·기둥 그림)이 있을 때만,
## 덩어리(TerrainArt.build_mass)의 드러난 높은 옆면을 따라 그 조각을 세로로 이어 붙인다 (없으면 아무것도 안 함 — 수관은 그대로).
## 충돌은 건드리지 않는다. 그림의 바깥 가장자리는 충돌 옆면에서 out px 만 밖으로 나오고(울퉁불퉁한 줄기 가장자리),
## 안쪽 가장자리는 inner_fade 비율 동안 몸통 결로 서서히 녹아든다.
##
## data/terrain/<지역>.json 의 params.wall:
##   width      : 벽 조각을 그릴 폭 (px, 조각 가로를 이 폭에 맞춘다)
##   out        : 충돌 옆면 밖으로 나오는 폭 (px)
##   min_h      : 이보다 짧은 옆면에는 안 붙인다 (px)
##   inner_fade : 안쪽 가장자리가 녹아드는 비율 (0~1, 폭 기준)
##   v_lo, v_hi : 조각 안에서 쓰는 세로 구간 (0~1 — 위아래 잘린 끝은 피한다)
##   top_inset  : 윗면(바닥 띠)이 있는 옆면은 이만큼 아래에서 시작 (바닥 띠의 절벽 끝이 위를 덮는다)

## 세로로 이어 붙이는 겹침 (px)
const OVERLAP := 48.0
## 가로 칸 수 (안쪽으로 녹아드는 알파를 칸마다 준다)
const COLS := 6


## art: 그리는 TerrainArt / sides: build_mass 가 모은 드러난 옆면 [[a, b, 바깥 법선], …] (노드 기준)
## tops: 드러난 윗면 [[a, b, …], …] — 옆면 위 끝이 윗면에 닿으면 top_inset 만큼 내려서 시작한다
static func lay(art: TerrainArt, sides: Array, tops: Array) -> void:
	var skin := art.skin
	var names := skin.list("wall")
	if names.is_empty():
		return
	var width := float(skin.param("wall", "width", 120.0))
	var out := float(skin.param("wall", "out", 10.0))
	var min_h := float(skin.param("wall", "min_h", 160.0))
	var inner_fade := float(skin.param("wall", "inner_fade", 0.45))
	var v_lo := float(skin.param("wall", "v_lo", 0.06))
	var v_hi := float(skin.param("wall", "v_hi", 0.94))
	var top_inset := float(skin.param("wall", "top_inset", 40.0))
	for sd in sides:
		var a: Vector2 = sd[0]
		var b: Vector2 = sd[1]
		var nrm: Vector2 = sd[2]
		if absf(nrm.x) < 0.7:
			continue
		var y0 := minf(a.y, b.y)
		var y1 := maxf(a.y, b.y)
		var x := (a.x + b.x) * 0.5
		# 옆면 위 끝이 드러난 윗면의 끝이면 바닥 띠(절벽 끝 조각)가 위를 덮게 조금 내려서 시작
		for t in tops:
			var ta: Vector2 = t[0]
			var tb: Vector2 = t[1]
			if (absf(ta.x - x) < 2.0 and absf(ta.y - y0) < 2.0) or (absf(tb.x - x) < 2.0 and absf(tb.y - y0) < 2.0):
				y0 += top_inset
				break
		# 방 안만 (방 밖은 화면에 안 나온다)
		if art._has_room:
			y0 = maxf(y0, art._room_box.position.y)
			y1 = minf(y1, art._room_box.end.y)
		if y1 - y0 < min_h:
			continue
		var side := 1.0 if nrm.x > 0.0 else -1.0
		# 바깥 가장자리 x (충돌 옆면 + out), 안쪽 가장자리 x
		var xo := x + side * out
		var xi := xo - side * width
		_strip(art, names, minf(xo, xi), maxf(xo, xi), y0, y1, side, inner_fade, v_lo, v_hi)


## 한 옆면: y0..y1 을 조각의 세로 토막들로 채운다 (토막끼리 OVERLAP 동안 서서히 겹침, 위아래 끝도 서서히).
static func _strip(art: TerrainArt, names: Array, xl: float, xr: float, y0: float, y1: float, side: float, inner_fade: float, v_lo: float, v_hi: float) -> void:
	var rng := art._rng
	var y := y0
	var first := true
	var guard := 0
	while y < y1 - 1.0 and guard < 64:
		guard += 1
		var n: String = names[rng.randi_range(0, names.size() - 1)]
		var sz := art.skin.size_of(n)
		var k := (xr - xl) / sz.x
		var lo := sz.y * v_lo
		var hi := sz.y * v_hi
		var start := y - (0.0 if first else OVERLAP)
		var lv := minf(rng.randf_range(0.55, 1.0) * (hi - lo), hi - lo)
		var need := (y1 - start) / k
		if need - lv < (hi - lo) * 0.3:
			lv = minf(need, hi - lo)
		var v0 := rng.randf_range(lo, maxf(lo, hi - lv))
		var seg_h := lv * k
		var fade_top := 24.0 if first else OVERLAP
		var fade_bot := 24.0 if start + seg_h >= y1 - 1.0 else 0.0
		# 바깥쪽이 왼쪽이면 조각을 뒤집어 같은 쪽 가장자리가 바깥을 보게 (줄기 그림은 거의 좌우 같다 — 무작위로도 뒤집는다)
		var flip := (side < 0.0) != (rng.randf() < 0.5)
		_quad_grid(art, n, v0, v0 + lv, xl, xr, start, start + seg_h, flip, side, inner_fade, fade_top, fade_bot)
		y = start + seg_h
		first = false


## 조각 n 의 세로 구간 v0..v1(조각 px)을 사각형 xl..xr × ya..yb 에 그린다. 안쪽 가장자리·위아래 끝은 알파로 서서히.
static func _quad_grid(art: TerrainArt, n: String, v0: float, v1: float, xl: float, xr: float, ya: float, yb: float, flip: bool, side: float, inner_fade: float, fade_top: float, fade_bot: float) -> void:
	var skin := art.skin
	var r := skin.rect_of(n)
	var asz := skin.atlas_size
	var mod := art._mod
	# 세로 줄: 위 끝, 위 페이드 끝, 아래 페이드 시작, 아래 끝
	var ys := PackedFloat32Array([ya, minf(ya + fade_top, yb), maxf(yb - fade_bot, ya), yb])
	var rows := ys.size()
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	pts.resize((COLS + 1) * rows)
	uvs.resize((COLS + 1) * rows)
	cols.resize((COLS + 1) * rows)
	for ci in COLS + 1:
		var f := float(ci) / COLS
		var x := lerpf(xl, xr, f)
		var u := (1.0 - f) if flip else f
		# 안쪽(몸통 쪽) 가장자리: side>0 이면 왼쪽(xl)이 안쪽
		var inner_t := f if side > 0.0 else 1.0 - f
		var ca := smoothstep(0.0, maxf(inner_fade, 0.01), inner_t)
		for ri in rows:
			var yy := ys[ri]
			var ra := 1.0
			if ri == 0 and fade_top > 0.0:
				ra = 0.0
			if ri == rows - 1 and fade_bot > 0.0:
				ra = 0.0
			var v := lerpf(v0, v1, (yy - ya) / maxf(yb - ya, 0.001))
			var k := ci * rows + ri
			pts[k] = Vector2(x, yy)
			uvs[k] = Vector2((r.position.x + u * r.size.x) / asz.x, (r.position.y + v) / asz.y)
			cols[k] = Color(mod.r, mod.g, mod.b, mod.a * ca * ra)
	var idx := PackedInt32Array()
	idx.resize(COLS * (rows - 1) * 6)
	var w := 0
	for ci in COLS:
		for ri in rows - 1:
			var p := ci * rows + ri
			var q := p + rows
			idx[w] = p; idx[w + 1] = p + 1; idx[w + 2] = q
			idx[w + 3] = p + 1; idx[w + 4] = q + 1; idx[w + 5] = q
			w += 6
	art._tris(TerrainArt.BUF_ATLAS, pts, uvs, cols, idx)

extends Node
## 터치 버튼 그림 만들기 (2026-10-19 기획자 요청 "터치 버튼을 그림으로: 공격=칼, 방어=방패 …").
## 창으로 돌린다 (도형을 GPU 로 그려 찍어야 해서 --headless 로는 안 된다):
##   godot --path . res://tools/make_touch_icons.tscn
## 결과: art/ui/touch/*.png (192×192, 투명 배경) + screenshots/debug_touch_icons.png (밝은·어두운 바탕 위 모아 보기)
##
## 그림 규칙 (게임 HUD 와 같은 결): 상아→금빛 그라데이션으로 칠한 도형 + 짙은 갈색 테두리(밝은 장면 위에서도 읽히게)
## + 은은한 금빛 번짐(영혼 그림은 그 영혼 색으로 번짐). 100×100 칸에 도형으로 그리고, 4배(768px)로 찍어 192px 로 줄인다 (가장자리 매끈).
## 테두리는 도형을 둥글게 부풀린 것(Geometry2D.offset_polygon)을 먼저 깔고 그 위에 칠해서, 여러 도형이 겹친 그림도 바깥선만 남는다.
## 이슬(회복)은 기획자 그림 art/objects/icon_dew.png 를 다듬어 줄인다.
## 다시 만들 때 이 파일의 도형만 고치고 다시 돌리면 된다. (만든 그림은 .import 에서 밉맵을 켜 둔다)
## 몇 장만 다시 만들려면:  godot --path . res://tools/make_touch_icons.tscn -- --only=soul_light,soul_wind  (나머지 그림은 그대로 둔다)

const OUT := "res://art/ui/touch/"
const SIZE := 192
const SS := 4
const K := float(SIZE * SS) / 100.0   # 100 칸 → 찍는 px

const IVORY := Color(1.0, 0.97, 0.88)
const GOLD := Color(0.94, 0.75, 0.39)
const GOLD_DEEP := Color(0.62, 0.41, 0.17)
const INK := Color(0.14, 0.085, 0.04)
const OW := 3.3          # 테두리 두께 (100 칸 기준)
const GLOW := Color(1.0, 0.84, 0.5)

## 이름 → 번짐 색. 순서대로 만든다.
const ICONS := {
	"attack": GLOW, "guard": GLOW, "jump": GLOW, "dodge": GLOW, "plunge": GLOW,
	"soul_seed": Color(0.8, 1.0, 0.6), "soul_wind": Color(0.6, 1.0, 0.88), "soul_light": Color(1.0, 0.86, 0.45),
	"soul_next": GLOW, "hand": GLOW, "door": GLOW, "travel": GLOW, "grow": GLOW, "map": GLOW, "menu": GLOW, "dust": Color(1.0, 0.9, 0.55),
}

var _vp: SubViewport
var _painter: Node2D
var _icon := ""
var _premult := true


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE * SS, SIZE * SS)
	_vp.transparent_bg = true
	_vp.msaa_2d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_painter = Node2D.new()
	_painter.draw.connect(_paint)
	_vp.add_child(_painter)
	await _detect_premult()
	print("[아이콘] 찍은 그림의 알파: %s" % ("미리 곱해짐(가장자리 어두움) → 되돌린다" if _premult else "그대로"))
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=").split(",", false)
	var shots := {}
	for name in ICONS:
		if not only.is_empty() and not only.has(name):
			continue
		var img := await _render(name)
		img = _finish(img, ICONS[name])
		img.save_png(ProjectSettings.globalize_path(OUT + "touch_%s.png" % name))
		shots[name] = img
		print("[아이콘] %stouch_%s.png" % [OUT, name])
	if only.is_empty() or only.has("heal"):
		var dew := _make_dew()
		dew.save_png(ProjectSettings.globalize_path(OUT + "touch_heal.png"))
		shots["heal"] = dew
		print("[아이콘] %stouch_heal.png (art/objects/icon_dew.png 에서)" % OUT)
	_contact_sheet(shots)
	get_tree().quit()


## 찍은 그림이 '미리 곱한 알파'인지 알아본다: 흰 원의 가장자리 픽셀(반투명)의 밝기가 알파만큼 어두우면 미리 곱한 것.
func _detect_premult() -> void:
	_icon = "_probe"
	_painter.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBAF)
	var cx := int(50.0 * K)
	for x in range(cx, img.get_width()):
		var c := img.get_pixel(x, cx)
		if c.a > 0.2 and c.a < 0.8:
			_premult = c.r < 0.9
			return


func _render(name: String) -> Image:
	_icon = name
	_painter.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _vp.get_texture().get_image()


## 줄이기(미리 곱한 채로) → 알파 되돌리기 → 번짐 깔기
func _finish(src: Image, glow_col: Color) -> Image:
	var img: Image = src.duplicate()
	img.convert(Image.FORMAT_RGBAF)
	if not _premult:
		_premultiply(img)
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	_unpremultiply(img)
	return _add_glow(img, glow_col, 7, 0.55)


func _premultiply(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a))


func _unpremultiply(img: Image) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a <= 0.003:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				var a := clampf(c.a, 0.0, 1.0)
				img.set_pixel(x, y, Color(clampf(c.r / a, 0, 1), clampf(c.g / a, 0, 1), clampf(c.b / a, 0, 1), a))


## 그림의 알파를 흐리게 퍼뜨린 번짐(glow_col)을 그림 밑에 깐다. radius px, strength 0~1.
func _add_glow(img: Image, glow_col: Color, radius: int, strength: float) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var a := PackedFloat32Array(); a.resize(w * h)
	for y in h:
		for x in w:
			a[y * w + x] = img.get_pixel(x, y).a
	for _pass in 3:
		a = _box_blur(a, w, h, radius / 2 + 1)
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var ga := clampf(a[y * w + x] * strength * 1.6, 0.0, strength)
			# 그림(c) 을 번짐(glow_col, ga) 위에 얹는다 (곧은 알파 'over')
			var oa := c.a + ga * (1.0 - c.a)
			if oa <= 0.002:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var rgb := (Color(c.r, c.g, c.b) * c.a + Color(glow_col.r, glow_col.g, glow_col.b) * ga * (1.0 - c.a)) / oa
			out.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, oa))
	return out


func _box_blur(src: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array(); tmp.resize(w * h)
	var out := PackedFloat32Array(); out.resize(w * h)
	var n := float(r * 2 + 1)
	for y in h:
		var acc := 0.0
		for x in range(-r, r + 1):
			acc += src[y * w + clampi(x, 0, w - 1)]
		for x in w:
			tmp[y * w + x] = acc / n
			acc += src[y * w + clampi(x + r + 1, 0, w - 1)] - src[y * w + clampi(x - r, 0, w - 1)]
	for x in w:
		var acc := 0.0
		for y in range(-r, r + 1):
			acc += tmp[clampi(y, 0, h - 1) * w + x]
		for y in h:
			out[y * w + x] = acc / n
			acc += tmp[clampi(y + r + 1, 0, h - 1) * w + x] - tmp[clampi(y - r, 0, h - 1) * w + x]
	return out


## 이슬: 기획자 그림의 투명 여백을 잘라 정사각형으로 맞추고 192 로 줄인다 (붉은·노란 찌꺼기 픽셀은 defringe 로 정리)
func _make_dew() -> Image:
	var src := Image.load_from_file(ProjectSettings.globalize_path("res://art/objects/icon_dew.png"))
	src.convert(Image.FORMAT_RGBA8)
	var used := src.get_used_rect()
	var side := maxi(used.size.x, used.size.y)
	var sq := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	sq.blit_rect(src, used, Vector2i((side - used.size.x) / 2, (side - used.size.y) / 2))
	var sc = load("res://tools/sheet_catalog.gd")
	sq = sc.defringe(sq)
	sq.convert(Image.FORMAT_RGBAF)
	_premultiply(sq)
	# 테두리 두를 자리를 조금 남기고 (94%) 가운데에
	var inner := int(SIZE * 0.94)
	sq.resize(inner, inner, Image.INTERPOLATE_LANCZOS)
	_unpremultiply(sq)
	var out := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBAF)
	out.blit_rect(sq, Rect2i(0, 0, inner, inner), Vector2i((SIZE - inner) / 2, (SIZE - inner) / 2))
	out.convert(Image.FORMAT_RGBA8)
	return _add_outline(out, 3, INK)


## 짙은 테두리 (다른 그림들과 같게 — 밝은 장면 위에서도 읽히게). 또렷한 부분(알파 0.35~0.7 이상)만 r px 부풀려 밑에 깐다
## (이슬 그림의 옅은 물보라·번짐까지 부풀리면 검은 얼룩이 생긴다).
func _add_outline(img: Image, r: int, col: Color) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var m := PackedFloat32Array(); m.resize(w * h)
	for y in h:
		for x in w:
			m[y * w + x] = smoothstep(0.35, 0.7, img.get_pixel(x, y).a)
	var tmp := PackedFloat32Array(); tmp.resize(w * h)
	for y in h:
		for x in w:
			var v := 0.0
			for k in range(-r, r + 1):
				v = maxf(v, m[y * w + clampi(x + k, 0, w - 1)])
			tmp[y * w + x] = v
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var v := 0.0
			for k in range(-r, r + 1):
				v = maxf(v, tmp[clampi(y + k, 0, h - 1) * w + x])
			var c := img.get_pixel(x, y)
			var oa := v * col.a * 0.9
			var a := c.a + oa * (1.0 - c.a)
			if a <= 0.002:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var rgb := (Color(c.r, c.g, c.b) * c.a + Color(col.r, col.g, col.b) * oa * (1.0 - c.a)) / a
			out.set_pixel(x, y, Color(rgb.r, rgb.g, rgb.b, a))
	return out


## 모아 보기: 어두운 반투명 원(실제 버튼 바탕) 위에 밝은 바탕·어두운 바탕 두 줄
func _contact_sheet(shots: Dictionary) -> void:
	var cell := 150
	var names := shots.keys()
	var cols := names.size()
	var sheet := Image.create_empty(cell * cols, cell * 2, false, Image.FORMAT_RGBA8)
	for row in 2:
		var bg := Color(0.86, 0.9, 0.82) if row == 0 else Color(0.06, 0.07, 0.09)
		sheet.fill_rect(Rect2i(0, row * cell, cell * cols, cell), bg)
		for i in cols:
			var c := Vector2(i * cell + cell / 2.0, row * cell + cell / 2.0)
			var r := 62.0
			for y in range(int(c.y - r), int(c.y + r)):
				for x in range(int(c.x - r), int(c.x + r)):
					var d := Vector2(x, y).distance_to(c)
					if d <= r:
						var base := sheet.get_pixel(x, y)
						var ring := 1.0 if d > r - 3.0 else 0.0
						var col := base.lerp(Color(0.03, 0.04, 0.07), 0.42).lerp(Color(1.0, 0.9, 0.65), ring * 0.6)
						sheet.set_pixel(x, y, col)
			var icon: Image = shots[names[i]].duplicate()
			icon.convert(Image.FORMAT_RGBA8)
			icon.resize(int(r * 1.5), int(r * 1.5), Image.INTERPOLATE_LANCZOS)
			sheet.blend_rect(icon, Rect2i(0, 0, icon.get_width(), icon.get_height()), Vector2i(int(c.x - icon.get_width() / 2.0), int(c.y - icon.get_height() / 2.0)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	sheet.save_png(ProjectSettings.globalize_path("res://screenshots/debug_touch_icons.png"))
	print("[아이콘] 모아 보기 screenshots/debug_touch_icons.png (%s)" % ", ".join(names))


# ───────── 도형 도구 (100 칸 좌표) ─────────

func _arc(c: Vector2, r: float, a0: float, a1: float, n := 32) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


func _ellipse(c: Vector2, rx: float, ry: float, n := 40) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


func _bez2(p0: Vector2, p1: Vector2, p2: Vector2, n := 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		out.append(p0.lerp(p1, t).lerp(p1.lerp(p2, t), t))
	return out


func _bez3(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, n := 20) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		var a := p0.lerp(p1, t)
		var b := p1.lerp(p2, t)
		var c := p2.lerp(p3, t)
		out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return out


## 잎 모양 (a 에서 b 까지, 가운데 폭 w, bend 로 한쪽으로 휨)
func _leaf(a: Vector2, b: Vector2, w: float, bend := 0.0) -> PackedVector2Array:
	var d := b - a
	var n := Vector2(-d.y, d.x).normalized()
	var m := a.lerp(b, 0.45)
	var left := _bez2(a, m + n * (w + bend), b, 14)
	var right := _bez2(b, m - n * (w - bend), a, 14)
	var out := PackedVector2Array(left)
	for i in range(1, right.size() - 1):
		out.append(right[i])
	return out


## 굵기가 w0 → w1 로 변하는 획 (다각형)
func _taper(pts: PackedVector2Array, w0: float, w1: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var t := float(i) / (n - 1)
		var w := lerpf(w0, w1, t) * 0.5
		var dir: Vector2
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == n - 1:
			dir = pts[n - 1] - pts[n - 2]
		else:
			dir = pts[i + 1] - pts[i - 1]
		var nn := Vector2(-dir.y, dir.x).normalized()
		left.append(pts[i] + nn * w)
		right.append(pts[i] - nn * w)
	right.reverse()
	return left + right


## 굵기 일정한 획 (끝 둥글게) → 다각형들
func _stroke(pts: PackedVector2Array, width: float) -> Array:
	return Geometry2D.offset_polyline(pts, width * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)


func _round_rect(r: Rect2, rad: float) -> PackedVector2Array:
	var inner := r.grow(-rad)
	var polys := Geometry2D.offset_polygon(PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]), rad, Geometry2D.JOIN_ROUND)
	return polys[0] if not polys.is_empty() else PackedVector2Array()


func _xf(pts: PackedVector2Array, pos: Vector2, rot: float, s := 1.0) -> PackedVector2Array:
	var t := Transform2D(rot, Vector2(s, s), 0.0, pos)
	return t * pts


# ───────── 칠하기 ─────────

## 테두리: 도형을 둥글게 부풀려 짙은 색으로
func _ink(polys: Array, w := OW, col := INK) -> void:
	for p in polys:
		for o in Geometry2D.offset_polygon(p, w, Geometry2D.JOIN_ROUND):
			_painter.draw_colored_polygon(o, col)


## 세로 그라데이션 칠 (top → bottom, y 범위는 도형 자신의 범위)
func _fill(poly: PackedVector2Array, top: Color, bottom: Color, y0 := INF, y1 := INF) -> void:
	if poly.size() < 3:
		return
	if y0 == INF:
		y0 = INF
		y1 = -INF
		for p in poly:
			y0 = minf(y0, p.y)
			y1 = maxf(y1, p.y)
	var cols := PackedColorArray()
	for p in poly:
		cols.append(top.lerp(bottom, clampf((p.y - y0) / maxf(y1 - y0, 0.01), 0.0, 1.0)))
	_painter.draw_polygon(poly, cols)


func _fill_all(polys: Array, top: Color, bottom: Color) -> void:
	var y0 := INF
	var y1 := -INF
	for poly in polys:
		for p in poly:
			y0 = minf(y0, p.y)
			y1 = maxf(y1, p.y)
	for poly in polys:
		_fill(poly, top, bottom, y0, y1)


func _solid(polys: Array, col: Color) -> void:
	for p in polys:
		if p.size() >= 3:
			_painter.draw_colored_polygon(p, col)


func _line(pts: PackedVector2Array, width: float, col: Color) -> void:
	_solid(_stroke(pts, width), col)


func _paint() -> void:
	_painter.draw_set_transform(Vector2.ZERO, 0.0, Vector2(K, K))
	match _icon:
		"_probe": _painter.draw_circle(Vector2(50, 50), 30, Color.WHITE)
		"attack": _icon_attack()
		"guard": _icon_guard()
		"jump": _icon_jump()
		"dodge": _icon_dodge()
		"plunge": _icon_plunge()
		"soul_seed": _icon_soul_seed()
		"soul_wind": _icon_soul_wind()
		"soul_light": _icon_soul_light()
		"soul_next": _icon_soul_next()
		"hand": _icon_hand()
		"door": _icon_door()
		"travel": _icon_travel()
		"grow": _icon_grow()
		"map": _icon_map()
		"menu": _icon_menu()
		"dust": _icon_dust()


# ───────── 그림들 ─────────

## 칼 (가운데 c, 회전 rot — 0 이면 날이 위, s 크기)
func _sword(c: Vector2, rot: float, s := 1.0) -> void:
	var blade := _xf(PackedVector2Array([Vector2(0, -46), Vector2(7, -35), Vector2(6.2, 13), Vector2(-6.2, 13), Vector2(-7, -35)]), c, rot, s)
	var guard_pts := PackedVector2Array([Vector2(-17, 12), Vector2(-24, 9), Vector2(-27, 13.5), Vector2(-24, 19.5), Vector2(-17, 18.5), Vector2(17, 18.5), Vector2(24, 19.5), Vector2(27, 13.5), Vector2(24, 9), Vector2(17, 12)])
	var guard := _xf(guard_pts, c, rot, s)
	var grip := _xf(_round_rect(Rect2(-4.2, 18, 8.4, 17), 2.5), c, rot, s)
	var pommel := _xf(_ellipse(Vector2(0, 39), 5.6, 5.6, 24), c, rot, s)
	_ink([blade, guard, grip, pommel])
	_fill(grip, GOLD_DEEP.darkened(0.15), GOLD_DEEP.darkened(0.45))
	# 칼날: 상아 → 옅은 은빛, 가운데 홈과 한쪽 날 빛
	var blade_local := PackedVector2Array([Vector2(0, -46), Vector2(7, -35), Vector2(6.2, 13), Vector2(-6.2, 13), Vector2(-7, -35)])
	var cols := PackedColorArray()
	for p in blade_local:
		cols.append(Color(1.0, 0.99, 0.95).lerp(Color(0.86, 0.84, 0.8), clampf((p.y + 46.0) / 59.0, 0, 1)))
	_painter.draw_polygon(blade, cols)
	_line(_xf(PackedVector2Array([Vector2(0, -36), Vector2(0, 9)]), c, rot, s), 2.0 * s, Color(GOLD_DEEP, 0.85))
	_line(_xf(PackedVector2Array([Vector2(-4.6, -33), Vector2(-4.2, 10)]), c, rot, s), 1.3 * s, Color(1, 1, 1, 0.9))
	# 날밑·자루끝: 금빛
	var g_local := guard_pts
	var gcols := PackedColorArray()
	for p in g_local:
		gcols.append(IVORY.lerp(GOLD, clampf((p.y - 9.0) / 10.5, 0, 1)))
	_painter.draw_polygon(guard, gcols)
	_fill(pommel, IVORY, GOLD)
	_line(_xf(PackedVector2Array([Vector2(-20, 15.5), Vector2(20, 15.5)]), c, rot, s), 1.2 * s, Color(GOLD_DEEP, 0.7))
	# 자루 감은 끈
	for i in 3:
		var y := 21.5 + i * 4.6
		_line(_xf(PackedVector2Array([Vector2(-3.6, y), Vector2(3.6, y + 2.2)]), c, rot, s), 1.1 * s, Color(INK, 0.55))


func _icon_attack() -> void:
	_sword(Vector2(51, 50), deg_to_rad(42), 1.06)


func _icon_plunge() -> void:
	# 아래로 내리꽂는 칼 (비스듬히, 칼끝이 왼쪽 아래) + 칼을 따라 위로 남는 빛줄기 + 칼끝의 부딪힘 불꽃
	var rot := PI + deg_to_rad(22)
	var c := Vector2(52, 50)
	var dir := Vector2(sin(rot), -cos(rot))      # 칼끝 쪽 (아래)
	var side := Vector2(-dir.y, dir.x)
	var streaks := []
	for k in [-1.0, 1.0]:
		var base: Vector2 = c - dir * 6.0 + side * k * 15.0
		streaks.append(_taper(PackedVector2Array([base - dir * 30.0, base]), 1.0, 5.5))
	var tip := c + dir * 46.0 * 0.92
	var sparks := []
	for k in [-1.0, 1.0]:
		for a in [0.55, 1.15]:
			var d: Vector2 = (-dir).rotated(k * a)
			sparks += _stroke(PackedVector2Array([tip + d * 7.0, tip + d * 15.0]), 3.4)
	_ink(streaks + sparks, 2.6)
	_fill_all(streaks, Color(IVORY, 0.5), IVORY)
	_solid(sparks, GOLD)
	_sword(c, rot, 0.92)


func _icon_guard() -> void:
	var c := Vector2(50, 50)
	var top := _bez2(Vector2(-31, -33), Vector2(0, -43), Vector2(31, -33), 16)
	var right := _bez3(Vector2(31, -33), Vector2(32, 2), Vector2(22, 26), Vector2(0, 42), 18)
	var left := _bez3(Vector2(0, 42), Vector2(-22, 26), Vector2(-32, 2), Vector2(-31, -33), 18)
	var shield := PackedVector2Array()
	for p in top: shield.append(c + p)
	for i in range(1, right.size()): shield.append(c + right[i])
	for i in range(1, left.size() - 1): shield.append(c + left[i])
	_ink([shield])
	_fill(shield, IVORY, GOLD)
	# 안쪽 테 (금빛 짙은 선)
	var inset := Geometry2D.offset_polygon(shield, -5.5, Geometry2D.JOIN_ROUND)
	if not inset.is_empty():
		var rim: PackedVector2Array = inset[0]
		# 닫힌 선은 polyline 으로 (offset_polyline 은 닫힌 선에 구멍 다각형을 돌려줘 안까지 칠해진다)
		_painter.draw_polyline(rim + PackedVector2Array([rim[0], rim[1]]), Color(GOLD_DEEP, 0.9), 2.0)
		# 위쪽 빛
		_line(_bez2(c + Vector2(-20, -30), c + Vector2(0, -37), c + Vector2(20, -30), 12), 1.6, Color(1, 1, 1, 0.75))
	# 문장: 세계수 잎
	var leaf := _leaf(c + Vector2(0, 24), c + Vector2(0, -24), 11.0)
	_ink([leaf], 2.2, Color(INK, 0.85))
	_fill(leaf, GOLD, GOLD_DEEP)
	_line(PackedVector2Array([c + Vector2(0, 22), c + Vector2(0, -20)]), 1.6, Color(IVORY, 0.9))
	for i in 3:
		var y := -10.0 + i * 9.0
		_line(PackedVector2Array([c + Vector2(0, y + 4), c + Vector2(-6.5, y - 1)]), 1.1, Color(IVORY, 0.75))
		_line(PackedVector2Array([c + Vector2(0, y + 4), c + Vector2(6.5, y - 1)]), 1.1, Color(IVORY, 0.75))


func _icon_jump() -> void:
	# 위로 펼친 두 날개 + 가운데 위 화살 (점프)
	var feathers := []
	for side in [-1.0, 1.0]:
		var root := Vector2(50 + side * 5, 74)
		var tips := [Vector2(50 + side * 38, 26), Vector2(50 + side * 41, 46), Vector2(50 + side * 34, 63)]
		var widths := [9.5, 8.5, 7.0]
		for i in 3:
			feathers.append(_leaf(root, tips[i], widths[i], side * 2.0))
	var chev := _stroke(PackedVector2Array([Vector2(36, 34), Vector2(50, 19), Vector2(64, 34)]), 7.5)
	var shaft := _stroke(PackedVector2Array([Vector2(50, 24), Vector2(50, 60)]), 6.5)
	_ink(feathers + chev + shaft)
	# 아래 깃털부터 (바깥 → 안) 칠하기
	for i in [2, 1, 0, 5, 4, 3]:
		_fill(feathers[i], IVORY, GOLD.lerp(GOLD_DEEP, 0.15 * (2 - (i % 3))))
	for side in [-1.0, 1.0]:
		var root := Vector2(50 + side * 5, 74)
		for tip in [Vector2(50 + side * 38, 26), Vector2(50 + side * 41, 46), Vector2(50 + side * 34, 63)]:
			_line(PackedVector2Array([root, root.lerp(tip, 0.82)]), 1.1, Color(GOLD_DEEP, 0.8))
	_fill_all(chev + shaft, IVORY, GOLD)


func _icon_dodge() -> void:
	# 휘도는 소용돌이 + 뒤로 남는 빛줄기 (회피 = 재빠른 몸놀림)
	var c := Vector2(60, 50)
	var spiral := PackedVector2Array()
	for i in 41:
		var t := float(i) / 40.0
		var a := deg_to_rad(-200.0 + 470.0 * t)
		var r := lerpf(28.0, 7.0, t)
		spiral.append(c + Vector2(cos(a), sin(a)) * r)
	var sp := _taper(spiral, 10.0, 2.5)
	var streaks := []
	for s in [[Vector2(8, 32), Vector2(40, 26), 5.0], [Vector2(4, 52), Vector2(34, 50), 6.5], [Vector2(12, 70), Vector2(40, 72), 5.0]]:
		streaks.append(_taper(_bez2(s[0], (s[0] + s[1]) / 2.0 + Vector2(0, -2), s[1], 10), 0.8, s[2]))
	_ink([sp] + streaks)
	_fill_all(streaks, IVORY, GOLD)
	_fill(sp, IVORY, GOLD)
	var inner := PackedVector2Array()
	for i in range(4, 34):
		inner.append(spiral[i] + (c - spiral[i]).normalized() * 1.6)
	_line(inner, 1.2, Color(1, 1, 1, 0.7))


func _icon_soul_seed() -> void:
	# 세계수의 씨앗에서 돋은 잎 둘
	var leaf_top := Color(0.94, 1.0, 0.84)
	var leaf_bot := Color(0.52, 0.78, 0.36)
	var seed := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		var r := Vector2(13.0, 15.5)
		var p := Vector2(cos(a) * r.x, sin(a) * r.y)
		if p.y < 0:
			p.x *= 1.0 + p.y / 30.0   # 위가 조금 뾰족한 씨앗
		seed.append(Vector2(50, 70) + p)
	var stem := _stroke(_bez2(Vector2(50, 58), Vector2(49, 48), Vector2(51, 40), 10), 4.4)
	var l1 := _leaf(Vector2(50, 42), Vector2(20, 18), 11.5, -2.0)
	var l2 := _leaf(Vector2(51, 40), Vector2(80, 12), 12.5, 2.0)
	_ink([seed, l1, l2] + stem)
	_fill_all(stem, Color(0.8, 0.95, 0.6), Color(0.45, 0.66, 0.3))
	_fill(l1, leaf_top, leaf_bot)
	_fill(l2, leaf_top, leaf_bot)
	_line(PackedVector2Array([Vector2(48, 41), Vector2(25, 21)]), 1.5, Color(0.32, 0.52, 0.22, 0.9))
	_line(PackedVector2Array([Vector2(53, 39), Vector2(75, 16)]), 1.5, Color(0.32, 0.52, 0.22, 0.9))
	_fill(seed, IVORY, GOLD)
	_line(_bez2(Vector2(43, 62), Vector2(46, 58), Vector2(51, 57), 8), 1.6, Color(1, 1, 1, 0.8))
	_painter.draw_circle(Vector2(50, 71), 3.2, Color(1.0, 1.0, 0.85))


func _icon_soul_wind() -> void:
	# 초승달 검기 (바람의 영혼) + 볼록한 쪽 뒤로 남는 바람결 둘
	var outer := _ellipse(Vector2(50, 50), 37, 37, 64)
	var inner := _ellipse(Vector2(61, 41), 32, 32, 64)
	var cres := Geometry2D.clip_polygons(outer, inner)
	var top := Color(0.95, 1.0, 0.97)
	var bot := Color(0.45, 0.86, 0.74)
	var trails := [_taper(_arc(Vector2(50, 50), 43.5, deg_to_rad(95), deg_to_rad(165), 16), 1.0, 4.2),
		_taper(_arc(Vector2(50, 50), 43.5, deg_to_rad(185), deg_to_rad(235), 12), 3.6, 1.0)]
	_ink(cres + trails, OW)
	_fill_all(cres, top, bot)
	_fill_all(trails, top, bot)
	var hl := PackedVector2Array()
	for i in range(18, 46):
		var a := TAU * i / 64.0
		hl.append(Vector2(50, 50) + Vector2(cos(a), sin(a)) * 33.0)
	_line(hl, 1.5, Color(1, 1, 1, 0.75))


func _star(c: Vector2, r_out: float, r_in: float, points: int, rot := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points * 2:
		var a := rot - PI / 2.0 + PI * i / points
		var r := r_out if i % 2 == 0 else r_in
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


func _icon_soul_light() -> void:
	# 빛줄기 (빛의 영혼 = 레이저, 2026-10-20 통합: 이펙트 리뉴얼 F1 의 빛 레이저에 맞춤 — 예전엔 네 갈래 별):
	# 손에 모인 빛 구슬 → 곧게 뻗는 빛줄기(하얀 심) → 끝에서 터지는 번쩍임 + 빛 알갱이 둘.
	# 오른쪽 위로 조금 비스듬히(18°) 두어 '쏘는' 느낌을 준다 (게임에서는 수평으로 나간다).
	var c := Vector2(50, 52)
	var rot := deg_to_rad(-18)
	var orb_c := c + Vector2(-26, 0).rotated(rot)
	var tip_c := c + Vector2(31, 0).rotated(rot)
	var beam := _xf(PackedVector2Array([Vector2(-24, -8.5), Vector2(31, -6.0), Vector2(31, 6.0), Vector2(-24, 8.5)]), c, rot)
	var flare := _star(orb_c, 23, 3.0, 4, rot + PI / 4.0)   # 구슬 뒤 가는 네 갈래 빛살 (빛을 모으는 손), 빛줄기와 비껴서
	var orb := _ellipse(orb_c, 14.5, 14.5, 40)
	var burst := _star(tip_c, 13, 3.6, 4, PI / 4.0 + rot)   # 빛줄기 끝의 번쩍임 (벽에 닿은 자리)
	var burst2 := _star(tip_c, 9, 2.6, 4, rot)
	var sp1 := _star(c + Vector2(2, -18).rotated(rot), 6.0, 1.6, 4)
	var sp2 := _star(c + Vector2(14, 17).rotated(rot), 4.6, 1.3, 4)
	_ink([flare, beam, orb, burst, burst2, sp1, sp2])
	_fill(flare, Color(1.0, 0.96, 0.78), Color(0.96, 0.7, 0.32))
	_fill(beam, Color(1.0, 0.99, 0.9), Color(1.0, 0.76, 0.34))
	_fill(burst, Color(1.0, 0.97, 0.82), Color(1.0, 0.74, 0.32))
	_fill(burst2, Color(1.0, 1.0, 0.95), Color(1.0, 0.86, 0.5))
	# 빛줄기 심: 하얀 가는 줄 (구슬에서 끝까지)
	_line(_xf(PackedVector2Array([Vector2(-18, 0), Vector2(29, 0)]), c, rot), 3.4, Color(1, 1, 1, 0.95))
	_fill(orb, Color(1.0, 1.0, 0.94), Color(1.0, 0.8, 0.4))
	_painter.draw_circle(orb_c, 7.0, Color(1.0, 1.0, 0.92))
	_painter.draw_circle(orb_c, 3.8, Color(1, 1, 1))
	_painter.draw_circle(tip_c, 3.0, Color(1, 1, 1))
	_fill(sp1, Color(1.0, 1.0, 0.92), GOLD)
	_fill(sp2, Color(1.0, 1.0, 0.92), GOLD)


func _arrow_arc(c: Vector2, r: float, a0: float, a1: float, width: float) -> Array:
	var arc := _arc(c, r, a0, a1, 24)
	var polys := _stroke(arc, width)
	var end := arc[arc.size() - 1]
	var tangent := Vector2(-sin(a1), cos(a1)) * signf(a1 - a0)
	var nrm := Vector2(-tangent.y, tangent.x)
	var head := PackedVector2Array([end + tangent * 11.0, end + nrm * 10.0 - tangent * 2.0, end - nrm * 10.0 - tangent * 2.0])
	polys.append(head)
	return polys


func _icon_soul_next() -> void:
	# 두 화살이 서로를 쫓는 고리 (영혼 바꾸기)
	var c := Vector2(50, 50)
	var a := _arrow_arc(c, 27, deg_to_rad(-200), deg_to_rad(-30), 8.0)
	var b := _arrow_arc(c, 27, deg_to_rad(-20), deg_to_rad(150), 8.0)
	_ink(a + b)
	_fill_all(a, IVORY, GOLD)
	_fill_all(b, IVORY, GOLD)
	_painter.draw_circle(c, 5.0, Color(GOLD, 0.9))


func _icon_hand() -> void:
	# 펼친 손 (정화의 손길): 손바닥 + 손가락 넷 + 엄지, 손바닥에 빛
	var palm := _round_rect(Rect2(33, 46, 34, 34), 11)
	var fingers := []
	for f in [[Vector2(38.5, 50), Vector2(37, 22), 5.6], [Vector2(47.5, 48), Vector2(47.5, 15), 5.9], [Vector2(56.5, 49), Vector2(58, 19), 5.6], [Vector2(64.5, 53), Vector2(68, 29), 4.9]]:
		fingers += _stroke(PackedVector2Array([f[0], f[1]]), f[2] * 2.0)
	var thumb := _stroke(_bez2(Vector2(36, 70), Vector2(27, 62), Vector2(20, 49), 10), 11.5)
	var all: Array = [palm] + fingers + thumb
	_ink(all)
	_fill_all(all, IVORY, GOLD)
	# 손가락 사이 선 (손가락이 붙어 보이지 않게)
	for x in [43.0, 52.0, 61.0]:
		_line(PackedVector2Array([Vector2(x, 49), Vector2(x + 0.3, 40)]), 1.0, Color(GOLD_DEEP, 0.65))
	# 손바닥 빛
	_painter.draw_circle(Vector2(50, 64), 9.0, Color(1.0, 1.0, 0.85, 0.55))
	var spark := _star(Vector2(50, 64), 8.5, 2.2, 4)
	_solid([spark], Color(1, 1, 1, 0.95))


func _icon_door() -> void:
	# 둥근 문 (포탈로 들어가기): 금빛 문틀 + 살짝 열린 문 사이로 빛
	var c := Vector2(50, 50)
	var outer := PackedVector2Array([c + Vector2(-27, 41)])
	outer += _arc(c + Vector2(0, -6), 27, PI, TAU, 24)
	outer.append(c + Vector2(27, 41))
	var inner := PackedVector2Array([c + Vector2(-18, 41)])
	inner += _arc(c + Vector2(0, -6), 18, PI, TAU, 20)
	inner.append(c + Vector2(18, 41))
	var step := _round_rect(Rect2(c.x - 33, c.y + 38, 66, 8), 3)
	_ink([outer, step])
	_fill(outer, IVORY, GOLD)
	_fill(step, GOLD, GOLD_DEEP)
	# 문 안: 빛 (안쪽 테두리 짙게)
	_ink([inner], 1.6, Color(INK, 0.8))
	_fill(inner, Color(1.0, 0.98, 0.85), Color(1.0, 0.85, 0.5))
	# 열린 문짝 (왼쪽으로 반쯤)
	var leaf := PackedVector2Array([c + Vector2(-18, 41), c + Vector2(-18, -6), c + Vector2(-17, -13), c + Vector2(-6, -9), c + Vector2(-6, 37)])
	_ink([leaf], 1.6, Color(INK, 0.85))
	_fill(leaf, GOLD_DEEP.lightened(0.15), GOLD_DEEP.darkened(0.25))
	_line(PackedVector2Array([c + Vector2(-12, -6), c + Vector2(-12, 36)]), 1.0, Color(INK, 0.5))
	_painter.draw_circle(c + Vector2(-9, 16), 1.8, IVORY)
	# 돌 문틀 결
	_line(_arc(c + Vector2(0, -6), 22.5, PI + 0.15, TAU - 0.15, 18), 1.2, Color(GOLD_DEEP, 0.6))


func _icon_travel() -> void:
	# 굽이진 길 화살 (달빛풀 사이 이동)
	var path := _bez3(Vector2(16, 82), Vector2(14, 44), Vector2(56, 64), Vector2(70, 32), 30)
	var body := _stroke(path, 9.0)
	var end := path[path.size() - 1]
	var dir := (path[path.size() - 1] - path[path.size() - 4]).normalized()
	var nrm := Vector2(-dir.y, dir.x)
	var head := PackedVector2Array([end + dir * 16.0, end + nrm * 13.0 - dir * 3.0, end - nrm * 13.0 - dir * 3.0])
	var dots := []
	for p in [Vector2(80, 76), Vector2(88, 64)]:
		dots.append(_ellipse(p, 3.2, 3.2, 16))
	_ink(body + [head] + dots)
	_fill_all(body + [head], IVORY, GOLD)
	_fill_all(dots, IVORY, GOLD)
	var hl := PackedVector2Array()
	for i in range(2, 24):
		hl.append(path[i] + Vector2(-1.6, -1.0))
	_line(hl, 1.2, Color(1, 1, 1, 0.65))


func _icon_grow() -> void:
	# 성장: 둥근 고리 안에 위로 겹친 화살촉 둘 + 반짝임 (힘이 한 단계 오른다)
	var c := Vector2(50, 52)
	# 고리는 반쪽 둘로 (구멍 난 다각형은 칠하면 구멍까지 메워진다)
	var ring := []
	for half in 2:
		var a0 := PI * half
		ring.append(_arc(c, 34, a0, a0 + PI, 28) + _arc(c, 27, a0 + PI, a0, 28))
	var chev := []
	for y in [-4.0, 13.0]:
		chev += _stroke(PackedVector2Array([c + Vector2(-14, y + 8), c + Vector2(0, y - 7), c + Vector2(14, y + 8)]), 7.5)
	_ink(ring + chev)
	_fill_all(ring, IVORY, GOLD)
	_fill_all(chev, IVORY, GOLD)
	_solid([_star(Vector2(84, 18), 8, 2, 4)], Color(1, 1, 0.9))
	_solid([_star(Vector2(17, 20), 5.5, 1.5, 4)], Color(1, 1, 0.9))


func _icon_map() -> void:
	# 접힌 지도: 세 쪽 병풍 + 길(실선 — v1.1.0 기획자 요청으로 점선을 없앰) + 표시
	var p1 := PackedVector2Array([Vector2(12, 26), Vector2(37, 18), Vector2(37, 76), Vector2(12, 84)])
	var p2 := PackedVector2Array([Vector2(37, 18), Vector2(63, 26), Vector2(63, 84), Vector2(37, 76)])
	var p3 := PackedVector2Array([Vector2(63, 26), Vector2(88, 18), Vector2(88, 76), Vector2(63, 84)])
	_ink([p1, p2, p3])
	_fill(p1, IVORY, GOLD.lerp(IVORY, 0.3))
	_fill(p2, GOLD.lerp(IVORY, 0.25), GOLD)
	_fill(p3, IVORY, GOLD.lerp(IVORY, 0.3))
	_line(PackedVector2Array([Vector2(37, 18), Vector2(37, 76)]), 1.2, Color(GOLD_DEEP, 0.7))
	_line(PackedVector2Array([Vector2(63, 26), Vector2(63, 84)]), 1.2, Color(GOLD_DEEP, 0.7))
	var trail := _bez3(Vector2(20, 70), Vector2(30, 40), Vector2(52, 72), Vector2(72, 42), 40)
	_line(trail, 3.0, Color(GOLD_DEEP, 0.95))
	var x := Vector2(76, 37)
	_line(PackedVector2Array([x + Vector2(-5, -5), x + Vector2(5, 5)]), 3.0, Color(0.7, 0.2, 0.12))
	_line(PackedVector2Array([x + Vector2(5, -5), x + Vector2(-5, 5)]), 3.0, Color(0.7, 0.2, 0.12))


func _icon_menu() -> void:
	var lines := []
	for y in [30.0, 50.0, 70.0]:
		lines += _stroke(PackedVector2Array([Vector2(24, y), Vector2(76, y)]), 9.0)
	_ink(lines)
	_fill_all(lines, IVORY, GOLD)


func _icon_dust() -> void:
	# 빛 가루: 큰 네 갈래 반짝이 + 작은 반짝이 둘 + 가운데 빛
	var main := _star(Vector2(46, 54), 40, 8.5, 4)
	var s1 := _star(Vector2(80, 20), 14, 3.2, 4)
	var s2 := _star(Vector2(16, 18), 9, 2.4, 4)
	_ink([main, s1, s2], 3.0)
	_fill(main, Color(1.0, 0.99, 0.9), Color(1.0, 0.76, 0.32))
	_fill(s1, Color(1.0, 0.99, 0.9), Color(1.0, 0.8, 0.4))
	_fill(s2, Color(1.0, 0.99, 0.9), Color(1.0, 0.8, 0.4))
	_painter.draw_circle(Vector2(46, 54), 6.5, Color(1, 1, 0.95))

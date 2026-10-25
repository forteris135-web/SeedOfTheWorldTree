extends SceneTree
## 엔딩 장치 세 개의 새 그림 자르기 (v1.1.0 번외 — 기획자 그림 ending/뿌리.png · 관.png · 진엔딩.png, 각각 완성 그림 + 부위).
## 사용: godot --headless --path . -s tools/cut_ending_devices.gd
##
## 1) 원본 세 장을 art/_원본/ending/ 에 복사한다 (ending/ 폴더는 그대로 둔다. 둘 다 .gdignore 라 게임 빌드에는 안 들어간다).
## 2) 시트에서 조각을 찾는다: 알파 > 0.5 인 픽셀의 연결 성분을 모두 세고, 원하는 상자(PIECES 의 대략 자리)와 가장 많이 겹치는
##    성분을 고른다 → 그 성분을 3px 부풀린 자리의 원본 픽셀(반투명 가장자리까지)을 떼어 낸다.
## 3) art/objects/ 에 저장한다 (모두 STORE 배로 줄여서 — 게임에서는 화면 높이 약 320~370px 로 쓰므로 원본 크기는 필요 없다):
##    - object_choice_root.png  : 희생(심연의 뿌리). 완성 그림은 천장에 매달린 등나무 선반이라 바닥에 세우면 어색하다 →
##                                가운데 '불꽃 심장 뿌리'를 밑동이 땅에 닿게 세우고, 양옆 늘어진 뿌리 둘을 조금 안쪽으로 붙여 뒤에 둔다.
##    - object_choice_pipe.png  : 되돌림(마력의 관). 완성 그림(관 기둥) 그대로.
##    - object_choice_pump_base.png   : 제3의 길 받침. 진엔딩 완성 그림에서 물레방아(톱니 테·바퀴살) 자리를 비우고
##                                      앞의 두 기둥·관·돌 받침(+ 바퀴 아래쪽 앞에 늘어진 덩굴·뿌리)만 남긴다.
##    - object_choice_pump_ring.png   : 톱니 테 (돌리는 축 = 그림 한가운데가 되게 둘레를 채움)
##    - object_choice_pump_spokes.png : 바퀴살 (원본은 비스듬히 본 타원이라 가로로 늘려 정원으로 — 돌려도 모양이 출렁이지 않게)
##    - object_choice_pump_hub.png    : 바퀴 가운데 굴대 (빛나는 핵)
##    - object_choice_pump_wheel.png  : 위 셋을 장치와 같은 비율로 미리 겹친 한 장 — 뿌리지기 방 배경의 흐린 물레방아(BlurWheel)용
##                                      (반투명으로 그릴 때 테 뒤 바퀴살이 비치지 않고, 그림 한 장이라 가볍다)
## 4) EndingChoice(scripts/world/ending_choice.gd)가 쓰는 자리 값(불꽃·밸브 핵·바퀴 중심)을 출력한다 — 다시 자르면 그 파일의 상수를 맞춘다.
## 원본(ending/, art/_원본/)은 덮어쓰지 않는다. 결과 그림을 고친 뒤에는 godot --headless --path . --import 로 다시 들인다.

const SRC_DIR := "res://ending/"
const COPY_DIR := "res://art/_원본/ending/"
const OUT_DIR := "res://art/objects/"
const FILES := ["뿌리.png", "관.png", "진엔딩.png"]
## 저장 배율 (원본 px → 저장 px)
const STORE := 0.7
const ALPHA_T := 0.5
const GROW := 3

## 조각의 대략 자리 (원본 시트 px, 연결 성분을 고르는 데만 쓴다)
const ROOT_HEART := Rect2i(813, 274, 323, 597)
const ROOT_LEFT := Rect2i(574, 341, 222, 508)
const ROOT_RIGHT := Rect2i(1166, 357, 242, 504)
## 양옆 뿌리를 가운데 쪽으로 붙이는 거리 (원본 px) — 심장 뿌리 옆구리 뒤로 조금 겹쳐 '가지'처럼 읽히게
const ROOT_SIDE_IN := Vector2i(40, -45)
const PIPE_ASM := Rect2i(16, 8, 417, 1052)
const PUMP_ASM := Rect2i(9, 9, 773, 675)
const PUMP_RING := Rect2i(697, 8, 446, 462)
const PUMP_SPOKES := Rect2i(1143, 36, 296, 387)
const PUMP_HUB := Rect2i(1248, 452, 189, 194)

## 진엔딩 완성 그림의 물레방아: 바퀴 중심(빛나는 핵), 지울 원의 반지름, 그 아래로는 돌 받침이라 지우지 않는 줄
const WHEEL_C := Vector2(453.5, 310.7)
const WHEEL_ERASE_R := 372.0
const BASE_TOP := 545.0
## 지우지 않는 앞 물건 (원본 시트 px 다각형): 왼쪽 기둥(덩굴째)·오른쪽 기둥(늘어진 등나무째)·왼쪽 관·오른쪽 관
const KEEP_POLYS := [
	[Vector2(212, 316), Vector2(340, 316), Vector2(340, 560), Vector2(212, 560)],
	[Vector2(538, 316), Vector2(646, 316), Vector2(646, 362), Vector2(698, 362), Vector2(698, 560), Vector2(538, 560)],
	[Vector2(0, 452), Vector2(234, 452), Vector2(234, 700), Vector2(0, 700)],
	[Vector2(640, 448), Vector2(790, 448), Vector2(790, 700), Vector2(640, 700)],
]
## 바퀴 아래쪽(중심보다 이만큼 아래, 두 기둥 사이 VINE_X)에서는 앞에 늘어진 덩굴·뿌리·물빛 픽셀을 남긴다 (도는 바퀴 앞에 걸린 채 그대로).
## 기둥 바깥의 옛 톱니에 달렸던 등나무·물빛은 허공에 뜨므로 지운다.
const VINE_BELOW := 40.0
const VINE_X := Vector2(300, 612)
## 지운 자리 경계를 부드럽게 (px)
const FEATHER := 2

## 톱니 테의 축 (원본 시트 px): 가로 끝 700..1149 의 가운데. 세로는 톱니 끝 반지름이 위·아래로 고르게 되는 자리
## (각도별 톱니 끝 반지름을 재어 맞춤 — 축이 어긋나면 돌 때 테가 출렁인다)
const RING_C := Vector2(924.5, 235.0)
## 바퀴살 타원의 중심과 가로·세로 반지름 (원본 시트 px)
const SPOKES_C := Vector2(1290.5, 229.0)
## 굴대 축
const HUB_C := Vector2(1342.0, 548.5)
## 장치에서 톱니 테 지름을 1 로 볼 때 바퀴살·굴대 크기 (EndingChoice 의 PUMP_SPOKES_K / PUMP_HUB_K 와 같은 비율)
const WHEEL_SPOKES_K := 0.88
const WHEEL_HUB_K := 0.576


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(COPY_DIR))
	for f in FILES:
		var src := ProjectSettings.globalize_path(SRC_DIR + f)
		var dst := ProjectSettings.globalize_path(COPY_DIR + f)
		if not FileAccess.file_exists(src):
			push_error("원본이 없다: " + src)
			quit(1)
			return
		if not FileAccess.file_exists(dst):
			DirAccess.copy_absolute(src, dst)
			print("복사: ", f, " → art/_원본/ending/")
	_cut_root()
	_cut_pipe()
	_cut_pump()
	print("끝 — godot --headless --path . --import 로 다시 들이기")
	quit()


func _load(f: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(COPY_DIR + f))
	img.convert(Image.FORMAT_RGBA8)
	return img


# ---------- 연결 성분 ----------
## 모든 성분에 번호를 붙인다. {labels: PackedInt32Array, boxes: {id: Rect2i}, counts: {id: n}}
func _label(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var thr := int(ALPHA_T * 255.0)
	var labels := PackedInt32Array()
	labels.resize(w * h)
	var boxes := {}
	var counts := {}
	var next := 0
	var stack := PackedInt32Array()
	for i0 in w * h:
		if labels[i0] != 0 or data[i0 * 4 + 3] <= thr:
			continue
		next += 1
		labels[i0] = next
		stack.resize(0)
		stack.append(i0)
		var mnx := w
		var mny := h
		var mxx := 0
		var mxy := 0
		var n := 0
		while stack.size() > 0:
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var px := i % w
			var py := i / w
			n += 1
			mnx = mini(mnx, px)
			mny = mini(mny, py)
			mxx = maxi(mxx, px)
			mxy = maxi(mxy, py)
			if px > 0:
				_push(i - 1, labels, data, thr, next, stack)
			if px < w - 1:
				_push(i + 1, labels, data, thr, next, stack)
			if py > 0:
				_push(i - w, labels, data, thr, next, stack)
			if py < h - 1:
				_push(i + w, labels, data, thr, next, stack)
		boxes[next] = Rect2i(mnx, mny, mxx - mnx + 1, mxy - mny + 1)
		counts[next] = n
	return {"labels": labels, "boxes": boxes, "counts": counts, "w": w, "h": h}


func _push(j: int, labels: PackedInt32Array, data: PackedByteArray, thr: int, id: int, stack: PackedInt32Array) -> void:
	if labels[j] == 0 and data[j * 4 + 3] > thr:
		labels[j] = id
		stack.append(j)


## 원하는 상자와 가장 많이 겹치는 큰 성분 번호
func _pick(lab: Dictionary, want: Rect2i) -> int:
	var best := -1
	var best_score := 0.0
	for id in lab.boxes:
		var b: Rect2i = lab.boxes[id]
		var inter := b.intersection(want)
		if inter.size.x <= 0 or inter.size.y <= 0:
			continue
		var iou := float(inter.get_area()) / float(b.get_area() + want.get_area() - inter.get_area())
		if iou > best_score:
			best_score = iou
			best = id
	if best < 0 or best_score < 0.5:
		push_error("조각을 못 찾았다: %s (가장 비슷한 겹침 %.2f)" % [want, best_score])
	else:
		print("  조각 %s → 성분 %d %s (겹침 %.2f)" % [want, best, lab.boxes[best], best_score])
	return best


## 성분 하나를 GROW px 부풀린 자리의 원본 픽셀로 떼어 낸다. 돌려주는 이미지의 (0,0) = 시트의 origin.
func _extract(img: Image, lab: Dictionary, id: int) -> Dictionary:
	var b: Rect2i = lab.boxes[id]
	var r := b.grow(GROW).intersection(Rect2i(0, 0, lab.w, lab.h))
	var labels: PackedInt32Array = lab.labels
	var w: int = lab.w
	# 가로·세로로 나눠 부풀린다 (최댓값 거르기 두 번)
	var mask := PackedByteArray()
	mask.resize(r.size.x * r.size.y)
	for y in r.size.y:
		for x in r.size.x:
			if labels[(r.position.y + y) * w + r.position.x + x] == id:
				mask[y * r.size.x + x] = 1
	var tmp := PackedByteArray()
	tmp.resize(mask.size())
	for y in r.size.y:
		for x in r.size.x:
			var on := 0
			for d in range(-GROW, GROW + 1):
				var xx := x + d
				if xx >= 0 and xx < r.size.x and mask[y * r.size.x + xx] == 1:
					on = 1
					break
			tmp[y * r.size.x + x] = on
	for y in r.size.y:
		for x in r.size.x:
			var on := 0
			for d in range(-GROW, GROW + 1):
				var yy := y + d
				if yy >= 0 and yy < r.size.y and tmp[yy * r.size.x + x] == 1:
					on = 1
					break
			mask[y * r.size.x + x] = on
	var out := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
	var src := img.get_region(r)
	for y in r.size.y:
		for x in r.size.x:
			if mask[y * r.size.x + x] == 1:
				out.set_pixel(x, y, src.get_pixel(x, y))
	return {"image": out, "origin": r.position}


func _save(img: Image, name: String, scale := STORE) -> Image:
	var out := img.duplicate() as Image
	out.resize(maxi(1, roundi(img.get_width() * scale)), maxi(1, roundi(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	out.save_png(ProjectSettings.globalize_path(OUT_DIR + name))
	print("저장: art/objects/%s  %dx%d" % [name, out.get_width(), out.get_height()])
	return out


## 그림에서 가장 밝은 빛(불꽃·핵)의 무게중심 (조각 이미지 px)
func _glow_center(img: Image, warm: bool) -> Vector2:
	var s := Vector2.ZERO
	var n := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.8:
				continue
			var ok := (c.r > 0.95 and c.g > 0.85 and c.b > 0.55) if warm else (c.b > 0.9 and c.g > 0.8 and c.r > 0.6 and c.b >= c.r)
			if ok:
				s += Vector2(x, y)
				n += 1.0
	return s / maxf(n, 1.0)


# ---------- 희생: 심연의 뿌리 ----------
func _cut_root() -> void:
	print("뿌리.png")
	var img := _load("뿌리.png")
	var lab := _label(img)
	var heart := _extract(img, lab, _pick(lab, ROOT_HEART))
	var left := _extract(img, lab, _pick(lab, ROOT_LEFT))
	var right := _extract(img, lab, _pick(lab, ROOT_RIGHT))
	var lo: Vector2i = left.origin + Vector2i(ROOT_SIDE_IN.x, 0)
	var ro: Vector2i = right.origin + Vector2i(ROOT_SIDE_IN.y, 0)
	var ho: Vector2i = heart.origin
	var li: Image = left.image
	var ri: Image = right.image
	var hi: Image = heart.image
	var x0 := mini(lo.x, mini(ro.x, ho.x))
	var y0 := mini(lo.y, mini(ro.y, ho.y))
	var x1 := maxi(lo.x + li.get_width(), maxi(ro.x + ri.get_width(), ho.x + hi.get_width()))
	var y1 := maxi(lo.y + li.get_height(), maxi(ro.y + ri.get_height(), ho.y + hi.get_height()))
	var canvas := Image.create(x1 - x0, y1 - y0, false, Image.FORMAT_RGBA8)
	canvas.blend_rect(li, Rect2i(Vector2i.ZERO, li.get_size()), lo - Vector2i(x0, y0))
	canvas.blend_rect(ri, Rect2i(Vector2i.ZERO, ri.get_size()), ro - Vector2i(x0, y0))
	canvas.blend_rect(hi, Rect2i(Vector2i.ZERO, hi.get_size()), ho - Vector2i(x0, y0))
	var out := _save(canvas, "object_choice_root.png")
	# 밑동 = 심장 뿌리의 가장 아래 불투명 줄, 가운데 = 심장 뿌리 가운데
	var foot := Vector2((ho.x - x0) + hi.get_width() * 0.5, _bottom_row(canvas)) * STORE
	var flame := (_glow_center(hi, true) + Vector2(ho - Vector2i(x0, y0))) * STORE
	print("  ROOT: 크기 %s, 밑동 %s, 불꽃 %s" % [out.get_size(), foot, flame])


func _bottom_row(img: Image) -> float:
	for y in range(img.get_height() - 1, -1, -1):
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.6:
				return float(y)
	return float(img.get_height())


# ---------- 되돌림: 마력의 관 ----------
func _cut_pipe() -> void:
	print("관.png")
	var img := _load("관.png")
	var lab := _label(img)
	var asm := _extract(img, lab, _pick(lab, PIPE_ASM))
	var ai: Image = asm.image
	var out := _save(ai, "object_choice_pipe.png")
	var valve := _glow_center(ai.get_region(Rect2i(0, int(ai.get_height() * 0.38), ai.get_width(), int(ai.get_height() * 0.24))), false) + Vector2(0, int(ai.get_height() * 0.38))
	print("  PIPE: 크기 %s, 밑동 y %.0f, 밸브 핵 %s" % [out.get_size(), _bottom_row(ai) * STORE, valve * STORE])


# ---------- 제3의 길: 무쇠 펌프의 물레방아 ----------
func _cut_pump() -> void:
	print("진엔딩.png")
	var img := _load("진엔딩.png")
	var lab := _label(img)
	var asm := _extract(img, lab, _pick(lab, PUMP_ASM))
	var base: Image = asm.image
	var o: Vector2i = asm.origin
	_erase_wheel(base, o)
	var out := _save(base, "object_choice_pump_base.png")
	var wheel := (WHEEL_C - Vector2(o)) * STORE
	print("  PUMP BASE: 크기 %s, 밑동 y %.0f, 바퀴 중심 %s" % [out.get_size(), _bottom_row(base) * STORE, wheel])
	# 도는 조각들: 축이 그림 한가운데에 오게 둘레를 채운다
	var ring := _extract(img, lab, _pick(lab, PUMP_RING))
	var ri := _centered(ring.image, RING_C - Vector2(ring.origin))
	_save(ri, "object_choice_pump_ring.png")
	var spokes := _extract(img, lab, _pick(lab, PUMP_SPOKES))
	var si: Image = spokes.image
	var sc := SPOKES_C - Vector2(spokes.origin)
	# 비스듬히 본 타원 → 정원 (가로를 세로 지름에 맞춰 늘린다)
	var stretch := float(si.get_height()) / float(si.get_width())
	si.resize(roundi(si.get_width() * stretch), si.get_height(), Image.INTERPOLATE_LANCZOS)
	sc.x *= stretch
	_save(_centered(si, sc), "object_choice_pump_spokes.png")
	var hub := _extract(img, lab, _pick(lab, PUMP_HUB))
	var hi := _centered(hub.image, HUB_C - Vector2(hub.origin))
	_save(hi, "object_choice_pump_hub.png")
	# 배경용 한 장: 바퀴살 → 톱니 테 → 굴대 (테 크기 그대로, 가운데 맞춤)
	var whole := Image.create(ri.get_width(), ri.get_height(), false, Image.FORMAT_RGBA8)
	for pair in [[_centered(si, sc), WHEEL_SPOKES_K], [ri, 1.0], [hi, WHEEL_HUB_K]]:
		var part: Image = (pair[0] as Image).duplicate()
		var k: float = pair[1]
		part.resize(maxi(1, roundi(part.get_width() * k)), maxi(1, roundi(part.get_height() * k)), Image.INTERPOLATE_LANCZOS)
		var at := Vector2i((whole.get_size() - part.get_size()) / 2)
		whole.blend_rect(part, Rect2i(Vector2i.ZERO, part.get_size()), at)
	_save(whole, "object_choice_pump_wheel.png")
	print("  (톱니 테·바퀴살·굴대는 그림 한가운데가 도는 축 — 바퀴살은 가로 ×%.3f)" % stretch)


## 축 c 가 한가운데에 오도록 투명 둘레를 더한 새 이미지
func _centered(img: Image, c: Vector2) -> Image:
	var half := Vector2(maxf(c.x, img.get_width() - c.x), maxf(c.y, img.get_height() - c.y)).ceil()
	var size := Vector2i(int(half.x * 2.0), int(half.y * 2.0))
	var out := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	out.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(roundi(half.x - c.x), roundi(half.y - c.y)))
	return out


## 완성 그림에서 물레방아를 지운다: 바퀴 원 안이고 돌 받침(BASE_TOP)보다 위이고 앞 물건(KEEP_POLYS) 밖인 픽셀.
## 단 바퀴 아래쪽(VINE_BELOW)에서는 덩굴·뿌리·물빛 색 픽셀을 남긴다. 경계는 FEATHER px 부드럽게.
func _erase_wheel(img: Image, o: Vector2i) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var keep := PackedFloat32Array()
	keep.resize(w * h)
	for y in h:
		for x in w:
			var p := Vector2(x + o.x, y + o.y)
			var k := 1.0
			if p.y < BASE_TOP and p.distance_to(WHEEL_C) < WHEEL_ERASE_R and not _in_keep(p):
				k = 0.0
				if p.y > WHEEL_C.y + VINE_BELOW and p.x > VINE_X.x and p.x < VINE_X.y and _is_vine(img.get_pixel(x, y)):
					k = 1.0
			keep[y * w + x] = k
	# 남긴 덩굴의 작은 부스러기(흩어진 점)는 지운다
	_drop_specks(keep, w, h, 60)
	# 경계 부드럽게 (상자 거르기)
	var soft := keep.duplicate()
	if FEATHER > 0:
		for y in h:
			for x in w:
				if keep[y * w + x] == 1.0:
					var near_zero := false
					for dy in range(-FEATHER, FEATHER + 1):
						for dx in range(-FEATHER, FEATHER + 1):
							var xx := x + dx
							var yy := y + dy
							if xx >= 0 and yy >= 0 and xx < w and yy < h and keep[yy * w + xx] == 0.0:
								near_zero = true
					if near_zero:
						var s := 0.0
						var n := 0.0
						for dy in range(-FEATHER, FEATHER + 1):
							for dx in range(-FEATHER, FEATHER + 1):
								var xx := x + dx
								var yy := y + dy
								if xx >= 0 and yy >= 0 and xx < w and yy < h:
									s += keep[yy * w + xx]
									n += 1.0
						soft[y * w + x] = s / n
	for y in h:
		for x in w:
			var k: float = soft[y * w + x]
			if k < 1.0:
				var c := img.get_pixel(x, y)
				c.a *= k
				img.set_pixel(x, y, c)


func _in_keep(p: Vector2) -> bool:
	for poly in KEEP_POLYS:
		if Geometry2D.is_point_in_polygon(p, PackedVector2Array(poly)):
			return true
	return false


## 덩굴(등나무 꽃·잎)·뿌리 밧줄·물빛인가 (구리빛 금속이 아닌가)
func _is_vine(c: Color) -> bool:
	if c.a < 0.3:
		return false
	var hue := c.h * 360.0
	var s := c.s
	var v := c.v
	if c.b > c.r and c.b > 0.35:
		return true          # 등나무 꽃·물빛 (푸른·보랏빛)
	if v > 0.8 and s < 0.22:
		return true          # 흰 꽃잎
	if c.g > c.r * 0.98 and c.g > c.b and v > 0.25:
		return true          # 잎
	if hue >= 30.0 and hue <= 55.0 and s >= 0.15 and s <= 0.55 and v >= 0.38:
		return true          # 뿌리 밧줄 (옅은 황갈색)
	return false


## keep 이 1 인 덩어리 가운데 지울 자리(0) 사이에 섬처럼 남은 작은 덩어리를 0 으로
func _drop_specks(keep: PackedFloat32Array, w: int, h: int, min_px: int) -> void:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack := PackedInt32Array()
	var comp := PackedInt32Array()
	for i0 in w * h:
		if seen[i0] == 1 or keep[i0] != 1.0:
			continue
		stack.resize(0)
		comp.resize(0)
		stack.append(i0)
		seen[i0] = 1
		while stack.size() > 0:
			var i: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			comp.append(i)
			var x := i % w
			var y := i / w
			for j in [i - 1, i + 1, i - w, i + w]:
				if j < 0 or j >= w * h:
					continue
				if (j == i - 1 and x == 0) or (j == i + 1 and x == w - 1):
					continue
				if seen[j] == 0 and keep[j] == 1.0:
					seen[j] = 1
					stack.append(j)
		if comp.size() < min_px:
			for i in comp:
				keep[i] = 0.0

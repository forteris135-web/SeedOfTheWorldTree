extends RefCounted
## 투사체 그림의 '보이는 반경' 재기 — 시험 전용 도우미 (v1.1.0 기획자 요청 4, 명세 3.6 "보스 투사체의 보이는 그림 반경과 판정 원
## 반경 차이 ≤ 20%"). probe_boss_melee·probe_bosses·probe_fx_boss 가 preload 해서 쓴다. 게임 코드는 부르지 않는다.
##
## 재는 법: 그림 픽셀 가운데 알파 ≥ 0.25 인 것만, 투사체 자기 좌표(+x = 날아가는 쪽, 원점 = 판정 원 가운데)로 옮긴다.
##   "dir"   진행 방향으로 도는 그림: 앞쪽(x > 0)은 원점까지의 거리, 뒤쪽은 옆 거리 |y| — 가장 먼 값 (뒤로 끌리는 꼬리는 길어도 된다).
##           잎처럼 굴러가며 흔들리면(wobble) 그 각도 폭 안에서 가장 먼 값.
##   "circ"  스스로 도는 그림(spin)·똑바로 서는 그림(upright): 어느 쪽으로든 가장 먼 거리.
##   "still" 제자리에 서는 것(불기둥): 가로·세로 반폭 — 큰 쪽이 vis, 작은 쪽이 vis_min (둘 다 판정 반경 ±20%).

const ALPHA := 0.25

static var _images := {}


static func _image(tex: Texture2D) -> Image:
	if _images.has(tex):
		return _images[tex]
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	if img.has_mipmaps():
		img.clear_mipmaps()
	_images[tex] = img
	return img


## 그림의 보이는 픽셀(그림 가운데 기준 좌표)을 xf 로 옮긴 점들
static func points(tex: Texture2D, xf: Transform2D) -> PackedVector2Array:
	var out := PackedVector2Array()
	var img := _image(tex)
	if img == null:
		return out
	var w := img.get_width()
	var h := img.get_height()
	var half := Vector2(w, h) * 0.5
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a >= ALPHA:
				out.append(xf * (Vector2(x + 0.5, y + 0.5) - half))
	return out


## Sprite2D 그림(가운데 맞춤)의 보이는 픽셀을 부모 노드 좌표로 → frame_rot 만큼 돌려 진행 방향 좌표로
static func sprite_points(sp: Sprite2D, frame_rot := 0.0) -> PackedVector2Array:
	var xf := Transform2D(frame_rot, Vector2.ZERO) * sp.transform * Transform2D(0.0, sp.offset)
	return points(sp.texture, xf)


static func metric(pts: PackedVector2Array, mode: String, wobble := 0.0) -> Dictionary:
	var perp := 0.0
	var along := 0.0
	var front := 0.0
	var cap := 0.0
	var circ := 0.0
	var angs := [0.0] if wobble <= 0.0 else [-wobble, -wobble * 0.5, 0.0, wobble * 0.5, wobble]
	for a in angs:
		var r := Transform2D(float(a), Vector2.ZERO)
		for p0 in pts:
			var p: Vector2 = r * p0
			perp = maxf(perp, absf(p.y))
			along = maxf(along, absf(p.x))
			front = maxf(front, p.x)
			var d := p.length()
			circ = maxf(circ, d)
			cap = maxf(cap, d if p.x > 0.0 else absf(p.y))
	var vis := cap
	var vis_min := cap
	match mode:
		"circ":
			vis = circ
			vis_min = circ
		"still":
			vis = maxf(perp, along)
			vis_min = minf(perp, along)
	return {"mode": mode, "perp": perp, "along": along, "front": front, "cap": cap, "circ": circ, "vis": vis, "vis_min": vis_min, "n": pts.size()}


## 그림 묶음(look)을 쓰는 Projectile 하나를 잰다 (판정 반경 r = hit_radius). 그림이 없으면 빈 사전.
static func projectile(p: Projectile) -> Dictionary:
	if not p.has_art():
		return {}
	var mode := "dir"
	if p.speed <= 0.0:
		mode = "still"
	elif p.art_turns_freely():
		mode = "circ"
	var m := metric(points(p._art_tex, p.art_transform_static()), mode, p.rot_wobble() if mode == "dir" else 0.0)
	m["r"] = p.hit_radius()
	m["ratio"] = m["vis"] / maxf(p.hit_radius(), 0.001)
	m["ratio_min"] = m["vis_min"] / maxf(p.hit_radius(), 0.001)
	return m


## 판정 반경 ±tol 안인가 (still 은 가로·세로 둘 다)
static func fits(m: Dictionary, tol := 0.2) -> bool:
	if m.is_empty():
		return false
	return m["ratio"] <= 1.0 + tol and m["ratio_min"] >= 1.0 - tol


static func describe(m: Dictionary) -> String:
	if m.is_empty():
		return "(그림 없음)"
	return "%s: 보이는 반경 %.1f (옆 %.1f, 앞 %.1f%s) / 판정 %.1f = %.2f배" % [m["mode"], m["vis"], m["perp"], m["front"],
		(", 작은 쪽 %.2f배" % m["ratio_min"]) if m["mode"] == "still" else "", m["r"], m["ratio"]]

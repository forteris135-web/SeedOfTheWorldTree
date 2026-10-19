class_name CrackedArt
extends Node2D
## 금 간 나무 벽 그림 (그림 조각 지형 — TERRAIN.md). 비밀 벽(SecretWall)·비밀 천장(SecretCeiling)·금 간 벽(CrackedWall)이 함께 쓴다.
## 지역 그림 옷(TerrainSkin)에 cracked / cracked_closed / cracked_glow 세 조각이 있을 때만 쓴다 (tools/terrain_cut.gd 의 extras).
##
## 겹 (아래 → 위):
##   몸통 결(TerrainArt) : 그림의 빈틈 뒤를 메운다
##   닫힌 그림 (closed) : 틈 빛을 메운 나무껍질 — 아직 안 갈라진 벽
##   열린 그림 (open)   : 원래 그림 (틈이 환하다). 맞을수록(stage 0→1) 서서히 드러나 '점점 갈라지는' 느낌
##   틈 빛 (glow)       : 더하기 혼합. 평소엔 아주 희미하게 숨 쉬고(눈썰미 좋은 사람만 보는 단서), 맞을수록 밝아진다.
##                        잿빛 재질을 거치지 않아 잿빛 세상에서도 온기가 보인다.
## 어떤 크기에도: 다각형의 가로세로 비율에 맞춰 그림에서 틈(crack_x) 둘레를 잘라 낸다 (좁은 벽은 틈 둘레의 좁은 띠).
## 부서질 때 burst() 가 그림을 몇 조각으로 쪼개 튀기고 떨어뜨린다 (그림 조각 + 껍질 파편).

const GLOW_HINT := 0.16
## 그림에서 잘라 쓰는 상자의 최소 가로세로 비율 (이보다 좁은 벽은 그림을 가로로 눌러 담는다)
const MIN_ASPECT := 0.62
var skin: TerrainSkin
var poly := PackedVector2Array()
var flip_v := false
var _uv_local := PackedVector2Array()   # 조각 안 px (세 조각이 같은 크기라 같이 쓴다)
var _crop := Rect2()                     # 그림 안에서 잘라 쓰는 상자 (조각 안 px)
var _closed: Polygon2D
var _open: Polygon2D
var _glow: Polygon2D
var _fill: TerrainArt
var _host: Node2D


static func can_build(s: TerrainSkin) -> bool:
	return s != null and s.pieces.has("cracked") and s.pieces.has("cracked_closed") and s.pieces.has("cracked_glow")


func _init() -> void:
	name = "CrackedArt"
	use_parent_material = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## poly: 벽 모양(노드 기준). flip: 위아래 뒤집기(천장에 매달린 옹이 — 그림의 넓은 밑동이 천장에 붙는다).
func setup(s: TerrainSkin, host: Node2D, shape: PackedVector2Array, flip := false) -> void:
	skin = s
	_host = host
	poly = shape
	flip_v = flip
	var bb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	var size := skin.size_of("cracked")
	var crack_x := float(skin.pieces["cracked"].get("crack_x", 0.5))
	# 그림 안에서 자를 상자: 벽 비율, 틈 둘레, 그림의 가운데 아래쪽(위 끝은 들쭉날쭉해서 조금 피한다)
	# 좁은 벽(60×200 등)은 그림을 가로로 눌러 담는다 (자르기만 하면 어두운 틈 속만 보인다). 최소 비율 MIN_ASPECT.
	var aspect := maxf(bb.size.x / maxf(bb.size.y, 1.0), MIN_ASPECT)
	var ch := size.y * 0.86
	var cw := ch * aspect
	if cw > size.x * 0.9:
		cw = size.x * 0.9
		ch = cw / aspect
	var cx := clampf(size.x * crack_x - cw * 0.5, 0.0, size.x - cw)
	var cy := clampf(size.y * 0.1, 0.0, size.y - ch)
	_crop = Rect2(cx, cy, cw, ch)
	_uv_local = PackedVector2Array()
	for p in poly:
		var t := (p - bb.position) / bb.size
		if flip_v:
			t.y = 1.0 - t.y
		_uv_local.append(Vector2(cx + t.x * cw, cy + t.y * ch))
	# 빈틈 뒤 몸통 결
	_fill = TerrainArt.new(skin, host)
	_fill.name = "Fill"
	add_child(_fill)
	_fill._begin(7)
	_fill.fill_polygon(poly, true, func(_p): return 0.8)
	_fill.queue_redraw()
	_closed = _layer("cracked_closed")
	_open = _layer("cracked")
	_open.modulate.a = 0.0
	_glow = _layer("cracked_glow")
	_glow.use_parent_material = false
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	set_state(0.5, 0.0)


func _layer(piece_name: String) -> Polygon2D:
	var pg := Polygon2D.new()
	pg.name = piece_name
	pg.texture = skin.atlas
	pg.polygon = poly
	var o := skin.rect_of(piece_name).position
	var uv := PackedVector2Array()
	for u in _uv_local:
		uv.append(u + o)
	pg.uv = uv
	# 나무 그림의 밝기는 자르기 도구가 굽는다 (data 의 cut.extras[].bright)
	pg.color = Color(skin.tint.r, skin.tint.g, skin.tint.b) if piece_name != "cracked_glow" else Color(1, 1, 1)
	pg.use_parent_material = true
	pg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(pg)
	return pg


## pulse: 숨 쉬기(0~1), stage: 갈라진 정도(0~1), tint: 틈 빛 색 (금 간 벽은 잠김/열림에 따라 바꾼다), boost: 번쩍임(0~1)
func set_state(pulse: float, stage: float, tint := Color(1.0, 0.86, 0.6), boost := 0.0) -> void:
	if _open == null:
		return
	_open.modulate.a = clampf(stage, 0.0, 1.0)
	var a := GLOW_HINT * (0.6 + 0.4 * pulse) + 0.75 * stage + boost
	_glow.color = Color(tint.r * (1.0 + boost), tint.g * (1.0 + boost * 0.4), tint.b, clampf(a, 0.0, 1.0))


## 부서진다: 그림을 몇 조각으로 쪼개 튀기고 떨어뜨린다. 조각은 parent(보통 지형 노드) 아래 따로 산다.
func burst(parent: Node) -> void:
	if parent == null or _host == null:
		return
	var deb := CrackDebris.new()
	deb.material = _host.material
	parent.add_child(deb)
	deb.global_position = global_position
	var bb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		bb = bb.expand(p)
	var cols := clampi(int(bb.size.x / 38.0), 2, 5)
	var rows := clampi(int(bb.size.y / 44.0), 2, 7)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(global_position.x * 3.0 + global_position.y)
	# 격자 꼭짓점을 흔들어 조각이 들쭉날쭉하게
	var grid: Array = []
	for j in rows + 1:
		var row: Array = []
		for i in cols + 1:
			var p := bb.position + Vector2(bb.size.x * i / cols, bb.size.y * j / rows)
			if i > 0 and i < cols:
				p.x += rng.randf_range(-0.3, 0.3) * bb.size.x / cols
			if j > 0 and j < rows:
				p.y += rng.randf_range(-0.3, 0.3) * bb.size.y / rows
			row.append(p)
		grid.append(row)
	var o_open := skin.rect_of("cracked").position
	var center := bb.get_center()
	for j in rows:
		for i in cols:
			var cell := PackedVector2Array([grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]])
			for piece_poly in Geometry2D.intersect_polygons(cell, poly):
				var pp: PackedVector2Array = piece_poly
				if pp.size() < 3:
					continue
				var c := Vector2.ZERO
				for p in pp:
					c += p
				c /= pp.size()
				var local := PackedVector2Array()
				var uv := PackedVector2Array()
				for p in pp:
					local.append(p - c)
					uv.append(_uv_at(p, bb) + o_open)
				var away := (c - center)
				var vel := Vector2(away.x * rng.randf_range(2.0, 4.5) + rng.randf_range(-60, 60), -rng.randf_range(160, 380) + away.y * 1.5)
				deb.add_piece(local, uv, skin.atlas, c, vel, rng.randf_range(-6.0, 6.0), Color(skin.tint.r, skin.tint.g, skin.tint.b))
	# 껍질 파편 (shard 조각) 몇 개
	var shards := skin.list("shard")
	for k in mini(8, cols * rows):
		if shards.is_empty():
			break
		var sn: String = shards[rng.randi_range(0, shards.size() - 1)]
		var r := skin.rect_of(sn)
		var sz := r.size * rng.randf_range(0.5, 0.9)
		var local := PackedVector2Array([-sz * 0.5, Vector2(sz.x * 0.5, -sz.y * 0.5), sz * 0.5, Vector2(-sz.x * 0.5, sz.y * 0.5)])
		var uv := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		var at := bb.position + Vector2(rng.randf() * bb.size.x, rng.randf() * bb.size.y)
		deb.add_piece(local, uv, skin.atlas, at, Vector2(rng.randf_range(-260, 260), -rng.randf_range(200, 460)), rng.randf_range(-9.0, 9.0), Color(skin.tint.r, skin.tint.g, skin.tint.b))
	visible = false


func _uv_at(p: Vector2, bb: Rect2) -> Vector2:
	var t := (p - bb.position) / bb.size
	if flip_v:
		t.y = 1.0 - t.y
	return _crop.position + t * _crop.size


## 부서진 조각들: 중력으로 떨어지며 돌고, 1.4초 동안 흐려지다 사라진다.
class CrackDebris extends Node2D:
	var _pieces: Array = []   # [Polygon2D, 속도, 각속도]
	var _t := 0.0

	func add_piece(local: PackedVector2Array, uv: PackedVector2Array, tex: Texture2D, at: Vector2, vel: Vector2, spin: float, col: Color) -> void:
		var pg := Polygon2D.new()
		pg.polygon = local
		pg.uv = uv
		pg.texture = tex
		pg.color = col
		pg.position = at
		pg.use_parent_material = true
		pg.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(pg)
		_pieces.append([pg, vel, spin])

	func _process(delta: float) -> void:
		_t += delta
		for it in _pieces:
			var pg: Polygon2D = it[0]
			it[1] = (it[1] as Vector2) + Vector2(0, 1500.0) * delta
			pg.position += (it[1] as Vector2) * delta
			pg.rotation += float(it[2]) * delta
			pg.modulate.a = clampf(1.0 - (_t - 0.7) / 0.7, 0.0, 1.0)
		if _t > 1.45:
			queue_free()

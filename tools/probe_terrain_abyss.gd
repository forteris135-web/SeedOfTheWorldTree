extends "res://tools/probe_terrain.gd"
## 심연 그림 조각 지형 시험. 실행: godot --headless --path . res://tools/probe_terrain_abyss.tscn [-- --verbose]
## 심연 방 7곳 (abyss_01·02·boss·hidden_1·hidden_2·mini_1, moon_garden):
##  a) 그림 옷 두 벌이 읽힌다 — 심연(abyss: 금빛 뿌리 시트)과 달빛 정원(abyss_garden: 푸른 버섯 정원 시트).
##     abyss.json 의 room_skins 로 달빛 정원·정원의 끝(보스 방)만 정원 그림 옷을 쓰고, 나머지 심연 방은 심연 그림 옷.
##  b) 모든 지형·비밀 벽·금 간 벽이 그림 조각, 몸통 결은 지형 묶음 맨 아래 겹, 한쪽 방향 발판은 빛 점선 단서가 있다.
##  c) 발 딛는 자리: 드러난 윗면마다 충돌 윗면 8px 아래가 그림으로 90% 넘게 덮이고, 그림 윗선이 충돌 윗면 ±10px.
##     드러난 충돌 끝 밖 발 높이에 그림이 OVERHANG_MAX 넘게 남지 않는다 (서지 못하는 곳이 발판처럼 보이지 않게).
##  d) 충돌은 그대로: 그림 옷을 끈 채(옛 방식) 읽은 방과 켠 채 읽은 방의 충돌 모양·자리가 똑같다 (지형·가시 전부).
##  e) 어두운 방은 그대로 어둡고(CanvasModulate), 수정·버섯 자리에 작은 빛이 1~8개 (옛 코드 지형의 '버섯 빛'과 같은 몫).
##     밝은 방(달빛 정원·보스 방)에는 빛을 달지 않는다. 달빛 정원의 장식 달빛풀 6개는 그대로.
##  f) 잿빛 팔레트: 심연 표는 데이터 파일에서 읽고, 밝기 순서를 지키며, 너무 어둡지 않다 (가운데 밝기 0.42 이상).
##  g) 금 간 벽·비밀 천장도 그림 옷 그림, 만들기 비용 (방 하나 평균 60ms 미만).
## 마지막에 "[probe] 끝: 실패 N" 을 찍고 그 수로 종료한다.

const ABYSS_ROOMS := ["abyss_01", "abyss_02", "abyss_boss", "abyss_hidden_1", "abyss_hidden_2", "abyss_mini_1", "moon_garden"]
const GARDEN_ROOMS := ["moon_garden", "abyss_boss"]
const DARK_ROOMS := ["abyss_01", "abyss_02", "abyss_hidden_1", "abyss_hidden_2", "abyss_mini_1"]

var _atlases := {}


func _ready() -> void:
	print("[probe] 심연 그림 조각 지형 시험 시작 (%s)" % ("화면 없이" if DisplayServer.get_name() == "headless" else "실제 렌더러"))
	TerrainSkin.enabled = true
	TerrainSkin.clear_cache()
	_probe_skins()
	await _probe_abyss_rooms()
	await _probe_colliders()
	_probe_ash()
	await _probe_cracked_abyss()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _atlas_for(skin: TerrainSkin) -> Image:
	if not _atlases.has(skin.region):
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://art/terrain/%s/atlas.png" % skin.region))
		img.convert(Image.FORMAT_RGBA8)
		_atlases[skin.region] = img
	return _atlases[skin.region]


# ---------- a) 그림 옷 ----------
func _probe_skins() -> void:
	var a := TerrainSkin.for_region("abyss")
	var g := TerrainSkin.for_region("abyss_garden")
	_check(a != null and g != null, "심연·달빛 정원 그림 옷이 읽힌다")
	if a == null or g == null:
		return
	for s in [a, g]:
		var skin: TerrainSkin = s
		_check(skin.has_role("branch") and skin.has_role("ground") and skin.has_role("hang") and skin.has_role("thorn"), "%s 역할: 가지 %d·바닥 %d·매달림 %d·가시 %d·판 %d·통나무 %d" % [skin.region, skin.list("branch").size(), skin.list("ground").size(), skin.list("hang").size(), skin.list("thorn").size(), skin.list("slab").size(), skin.list("log").size()])
		_check(skin.atlas != null and skin.fill != null and skin.fill_v != null and CrackedArt.can_build(skin), "%s: atlas·몸통 결(가로/세로)·금 간 벽 그림 세 장" % skin.region)
		var bad_walk := []
		for n in skin.list("branch") + skin.list("slab") + skin.list("ground") + skin.list("log"):
			var w := skin.walk_of(n)
			if w.y - w.x < 60.0:
				bad_walk.append(n)
		_check(bad_walk.is_empty(), "%s: 걷는 조각마다 걷는 구간이 60px 넘게 있다 %s" % [skin.region, bad_walk])
		var sz := skin.atlas_size
		_check(sz.x <= 2048 and sz.y <= 2048, "%s atlas %dx%d (2048 이하 — 아이폰 메모리)" % [skin.region, sz.x, sz.y])
	_check(a.has_role("log") and not a.list("log").has(a.list("branch")[0]), "심연: 한쪽 방향이 아닌 얇은 발판은 굵은 통나무(log), 한쪽 방향 발판은 가는 덩굴(branch)")
	var rs: Dictionary = a.data.get("room_skins", {})
	_check(rs.get("moon_garden", "") == "abyss_garden" and rs.get("abyss_boss", "") == "abyss_garden" and rs.size() == 2, "room_skins: 달빛 정원·정원의 끝만 정원 그림 옷 (%s)" % [rs])
	_check(TerrainSkin.for_region("canopy") != null and not (TerrainSkin.for_region("canopy").data as Dictionary).has("room_skins"), "다른 지역(수관) 그림 옷은 room_skins 없이 그대로")


# ---------- b) c) e) 방마다 ----------
func _probe_abyss_rooms() -> void:
	var not_art := []
	var wrong_skin := []
	var fill_bad := []
	var dash_bad := []
	var feet_bad := []
	var top_bad := []
	var over_bad := []
	var over_all := []
	var tops_checked := 0
	var ends_checked := 0
	var worst_cov := 1.0
	var worst_name := ""
	var tops_all: Array = []
	var deco_max := 0.0
	var sum_ms := 0.0
	var worst_ms := 0.0
	var worst_ms_id := ""
	for id in ABYSS_ROOMS:
		var expect := "abyss_garden" if id in GARDEN_ROOMS else "abyss"
		TerrainArt.build_usec = 0
		var room := await _load_room(id)
		await _frames(2)
		var ms := TerrainArt.build_usec / 1000.0
		sum_ms += ms
		if ms > worst_ms:
			worst_ms = ms
			worst_ms_id = id
		var solids := _solids(room)
		var bounds: Rect2 = room.get("bounds")
		for t in room.get_node("Terrain").get_children():
			var nm := "%s/%s" % [id, t.name]
			if t is SecretWall or t is CrackedWall:
				var cr = t.get("_crack")
				if cr == null:
					not_art.append(nm)
				elif (cr as CrackedArt).skin.region != expect:
					wrong_skin.append("%s(%s)" % [nm, (cr as CrackedArt).skin.region])
				continue
			if not ((t is Platform or t is TerrainPolygon) and t.is_art()):
				if t is Platform or t is TerrainPolygon:
					not_art.append(nm)
				continue
			var art: TerrainArt = t.get("_art")
			if art.skin.region != expect:
				wrong_skin.append("%s(%s)" % [nm, art.skin.region])
			if not art.fill_in_layer():
				fill_bad.append(nm)
			if t is Platform and t.one_way and (art._bufs[TerrainArt.BUF_PLAIN]["idx"] as PackedInt32Array).size() < 6:
				dash_bad.append(nm)
			_atlas_img = _atlas_for(art.skin)
			for seg in _top_segments(t):
				for side in [-1.0, 1.0]:
					var far := _overhang(t, art, seg[0] if side < 0.0 else seg[1], side, solids, bounds)
					if far < 0.0:
						continue
					ends_checked += 1
					over_all.append([far, "%s %s" % [nm, "왼끝" if side < 0.0 else "오른끝"]])
					if far > OVERHANG_MAX:
						over_bad.append("%s %s %.0fpx" % [nm, "왼끝" if side < 0.0 else "오른끝", far])
				var r := _feet_check(t, seg[0], seg[1], solids, bounds)
				if r.is_empty():
					continue
				tops_checked += 1
				if float(r["cov"]) < worst_cov:
					worst_cov = r["cov"]
					worst_name = nm
				if float(r["cov"]) < 0.9:
					feet_bad.append("%s 덮임 %.0f%%" % [nm, float(r["cov"]) * 100.0])
				# 윗선: 발판 위에 선 장식(버섯·등불·난간·수정 — 윗선보다 18px 넘게 솟은 곳)은 빼고 잰다.
				# 장식이 윗면의 3/4 을 넘으면 실패 (그림 전체가 떠 있거나 묻힌 것과 구분 — 정원 바닥은 버섯이 60% 안팎)
				var dt := _top_diffs(t, seg[0], seg[1], solids, bounds)
				if dt.is_empty():
					continue
				var ground: Array = dt.filter(func(v): return v >= -18.0)
				var frac := float(ground.size()) / dt.size()
				var med: float = ground[ground.size() / 2] if not ground.is_empty() else -99.0
				deco_max = maxf(deco_max, 1.0 - frac)
				tops_all.append(med)
				if frac < 0.25 or ground.size() < 4 or absf(med) > 10.0:
					top_bad.append("%s 윗선 %+.0fpx (장식 %.0f%%)" % [nm, med, (1.0 - frac) * 100.0])
		var hz := room.get_node_or_null("Hazards")
		if hz:
			for th in hz.get_children():
				if th is Thorns and th.get("_art") == null:
					not_art.append("%s/%s" % [id, th.name])
		# e) 어두운 방·작은 빛·장식 달빛풀
		var dark := bool(room.get("dark"))
		var has_cm := false
		for c in room.get_children():
			if c is CanvasModulate:
				has_cm = true
		var glow := _count_glow(room)
		if id in DARK_ROOMS:
			_check(dark and has_cm and glow >= 1 and glow <= TerrainStyle.GLOW_LIGHTS_PER_ROOM, "%s: 어두운 방 그대로 (CanvasModulate %s), 수정 자리의 작은 빛 %d개 (1~%d)" % [id, has_cm, glow, TerrainStyle.GLOW_LIGHTS_PER_ROOM])
		else:
			_check(not dark and glow == 0, "%s: 밝은 방, 작은 빛 없음 (%d)" % [id, glow])
		if id == "moon_garden":
			var decor := _count_decor_grass(room)
			_check(decor == 6, "달빛 정원의 장식 달빛풀 %d개 그대로 (6)" % decor)
		print("[probe] %s 그림 지형 만들기 %.1fms" % [id, ms])
		await _free_room(room)
	_check(not_art.is_empty(), "심연 %d곳: 지형·가시·비밀 벽·금 간 벽이 모두 그림 조각 (아닌 것 %s)" % [ABYSS_ROOMS.size(), not_art.slice(0, 8)])
	_check(wrong_skin.is_empty(), "방마다 맞는 그림 옷 (정원 두 곳 = abyss_garden, 나머지 = abyss; 틀린 것 %s)" % [wrong_skin.slice(0, 8)])
	_check(fill_bad.is_empty(), "몸통 결은 지형 묶음 맨 아래 겹 (아닌 것 %s)" % [fill_bad.slice(0, 6)])
	_check(dash_bad.is_empty(), "한쪽 방향 발판에 빛 점선 단서 (없는 것 %s)" % [dash_bad.slice(0, 6)])
	_check(tops_checked >= 20 and feet_bad.is_empty(), "드러난 윗면 %d곳: 발밑(충돌 윗면 8px 아래)이 그림으로 90%% 넘게 덮임 (가장 낮은 %s %.0f%%) %s" % [tops_checked, worst_name, worst_cov * 100.0, feet_bad.slice(0, 6)])
	tops_all.sort()
	_check(top_bad.is_empty(), "드러난 윗면 %d곳: 그림 윗선(선 장식 뺌)이 충돌 윗면 ±10px 안 (범위 %+.0f~%+.0f, 장식이 가장 많은 윗면 %.0f%%) %s" % [tops_checked, tops_all[0] if not tops_all.is_empty() else 0.0, tops_all[-1] if not tops_all.is_empty() else 0.0, deco_max * 100.0, top_bad.slice(0, 6)])
	over_all.sort_custom(func(x, y): return x[0] > y[0])
	if "--verbose" in OS.get_cmdline_user_args():
		for r in over_all.slice(0, 12):
			print("[probe]   끝 밖 그림 %3.0fpx  %s" % [r[0], r[1]])
	_check(ends_checked >= 20 and over_bad.is_empty(), "드러난 충돌 끝 %d곳: 끝 밖 발 높이에 그림이 %.0fpx 넘게 남지 않는다 (가장 긴 %s) %s" % [ends_checked, OVERHANG_MAX, ("%.0fpx %s" % [over_all[0][0], over_all[0][1]]) if not over_all.is_empty() else "-", over_bad.slice(0, 6)])
	var avg := sum_ms / ABYSS_ROOMS.size()
	_check(avg < 60.0, "그림 지형 만들기: 방 하나 평균 %.1fms < 60ms (가장 긴 %s %.1fms)" % [avg, worst_ms_id, worst_ms])


# ---------- d) 충돌 그대로 ----------
## 지형·가시 아래 모든 충돌 모양의 (부모 이름, 종류, 전역 자리, 모양 값, 한쪽 방향) 목록
func _collider_sig(room: Node) -> Array:
	var out := []
	for group_name in ["Terrain", "Hazards"]:
		var grp := room.get_node_or_null(group_name)
		if grp:
			_collect_sig(grp, out)
	out.sort()
	return out


func _collect_sig(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is CollisionShape2D:
			var cs := c as CollisionShape2D
			var desc := ""
			if cs.shape is RectangleShape2D:
				desc = "rect %s" % [(cs.shape as RectangleShape2D).size]
			elif cs.shape is ConvexPolygonShape2D:
				desc = "convex %s" % [(cs.shape as ConvexPolygonShape2D).points]
			elif cs.shape != null:
				desc = cs.shape.get_class()
			out.append("%s|%s|%s|%s|ow=%s|dis=%s" % [_sig_name(n), "shape", cs.global_position.round(), desc, cs.one_way_collision, cs.disabled])
		elif c is CollisionPolygon2D:
			var cp := c as CollisionPolygon2D
			out.append("%s|%s|%s|%s|ow=%s" % [_sig_name(n), "poly", cp.global_position.round(), cp.polygon, cp.one_way_collision])
		_collect_sig(c, out)


## 부모 이름 (자동으로 붙은 '@Area2D@123' 같은 이름은 종류만)
static func _sig_name(n: Node) -> String:
	var s := str(n.name)
	return n.get_class() if s.begins_with("@") else s


func _probe_colliders() -> void:
	var bad := []
	var total := 0
	for id in ABYSS_ROOMS:
		TerrainSkin.enabled = false
		var r0 := await _load_room(id)
		var s0 := _collider_sig(r0)
		await _free_room(r0)
		TerrainSkin.enabled = true
		var r1 := await _load_room(id)
		var s1 := _collider_sig(r1)
		await _free_room(r1)
		total += s1.size()
		if s0 != s1:
			bad.append("%s (옛 %d개 / 그림 %d개)" % [id, s0.size(), s1.size()])
			if "--verbose" in OS.get_cmdline_user_args():
				for i in mini(s0.size(), s1.size()):
					if s0[i] != s1[i]:
						print("[probe]   옛  %s\n[probe]   그림 %s" % [s0[i], s1[i]])
	_check(total > 40 and bad.is_empty(), "심연 %d곳 충돌 모양 %d개: 그림 옷을 끈 방과 켠 방이 똑같다 (다른 방 %s)" % [ABYSS_ROOMS.size(), total, bad])


# ---------- f) 잿빛 팔레트 ----------
func _probe_ash() -> void:
	var spec := Purity.ash_spec("abyss")
	_check(spec.has("neutral") and spec.has("hues") and (spec["hues"] as Dictionary).size() >= 3, "심연 잿빛 팔레트는 data/terrain/abyss.json 에서 읽는다 (색상 띠 %d개)" % (spec.get("hues", {}) as Dictionary).size())
	var img := Purity.ash_lut("abyss").get_image()
	var mono := true
	for row in Purity.LUT_ROWS:
		var prev := -1.0
		for x in Purity.LUT_W:
			var l := img.get_pixel(x, row).get_luminance()
			if l < prev - 0.01:
				mono = false
			prev = l
	var mid := img.get_pixel(Purity.LUT_W / 2, 0)
	var quarter := img.get_pixel(Purity.LUT_W / 4, 0)
	_check(mono, "심연 잿빛 표: 모든 줄이 밝기 순서를 지킨다 (그림이 뭉개지지 않게)")
	_check(mid.get_luminance() >= 0.42 and quarter.get_luminance() >= 0.2, "심연 잿빛은 너무 어둡지 않다 (가운데 %.2f ≥ 0.42, 1/4 %.2f ≥ 0.2)" % [mid.get_luminance(), quarter.get_luminance()])
	_check(mid.b > mid.g and mid.s < 0.15, "심연 잿빛은 보랏빛이 살짝 도는 회색 (가운데 %s, 채도 %.2f)" % [mid.to_html(false), mid.s])
	var garden_spec_has_ash := (TerrainSkin.for_region("abyss_garden").data as Dictionary).has("ash")
	_check(not garden_spec_has_ash, "달빛 정원 그림 옷에는 따로 잿빛 표가 없다 (지역 표 하나를 함께 쓴다)")


# ---------- g) 금 간 벽·비밀 천장 ----------
func _probe_cracked_abyss() -> void:
	var r1 := await _load_room("abyss_01")
	var cw: CrackedWall = r1.get_node("Terrain/CrackedWall1")
	var c1 = cw.get("_crack")
	_check(c1 != null and not cw._sprite.visible and (c1 as CrackedArt).skin.region == "abyss", "abyss_01 금 간 벽: 심연 그림 옷의 금 간 나무 그림")
	await _free_room(r1)
	var r2 := await _load_room("abyss_02")
	var sc: SecretCeiling = r2.get_node("Terrain/SecretCeiling1")
	var c2 = sc.get("_crack")
	_check(c2 != null and (c2 as CrackedArt).flip_v, "abyss_02 비밀 천장: 금 간 나무 그림 (위아래 뒤집어 밑동이 천장에)")
	var cs := _first_shape(sc)
	_check(cs != null and cs.shape is ConvexPolygonShape2D, "비밀 천장 충돌은 옹이 모양 그대로")
	if c2:
		var crack: CrackedArt = c2
		var a0: float = crack._open.modulate.a
		sc.on_head_bump(null, 600.0)
		await _frames(2)
		_check(crack._open.modulate.a > a0 + 0.2 or sc._broken, "머리를 박으면 갈라진 그림이 드러난다 (열림 %.2f → %.2f)" % [a0, crack._open.modulate.a])
	await _free_room(r2)


## 장식 달빛풀(decor — 무리에 끼지 않는다) 수
func _count_decor_grass(n: Node) -> int:
	var k := 0
	for c in n.get_children():
		if "decor" in c and "grass_id" in c and bool(c.get("decor")) and (c as CanvasItem).visible:
			k += 1
		k += _count_decor_grass(c)
	return k


## 윗면 a→b 의 드러난 자리마다 그림 윗선과 충돌 윗면의 차이 (px, 위가 −) — 자르기 도구의 '빽빽한 윗면'과 같은 기준
func _top_diffs(t: Node2D, a: Vector2, b: Vector2, solids: Array, bounds: Rect2) -> Array:
	var art: TerrainArt = t.get("_art")
	var tris := _atlas_tris(art)
	var n := maxi(2, int((b.x - a.x) / 12.0))
	var out: Array = []
	for i in n:
		var x := lerpf(a.x, b.x, (i + 0.5) / n)
		if x - a.x < 14.0 or b.x - x < 14.0:
			continue
		var y := lerpf(a.y, b.y, (x - a.x) / maxf(b.x - a.x, 0.001))
		var gp := t.global_position + Vector2(x, y)
		if not bounds.has_point(gp + Vector2(0, -8)) or _inside_other(solids, t, gp + Vector2(0, -10)) != "":
			continue
		var col: Array = []
		for tr in tris:
			var bb: Rect2 = tr[3]
			if x >= bb.position.x and x <= bb.end.x and bb.end.y >= y - 140.0 and bb.position.y <= y + 60.0:
				col.append(tr)
		var run := 0
		var yy := y - 140.0
		while yy < y + 60.0:
			if _alpha_at(col, Vector2(x, yy)) > 0.5:
				run += 1
				if run >= 6:
					out.append(yy - 10.0 - y)
					break
			else:
				run = 0
			yy += 2.0
	out.sort()
	return out

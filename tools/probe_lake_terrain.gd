extends "res://tools/probe_terrain.gd"
## 수액의 호수 지형 그림 시험 (화면 없이 돈다). probe_terrain 의 재기 도우미(발밑 덮임·윗선·끝 밖 그림·가시 틀)를 그대로 쓰고,
## 방 목록·atlas 만 호수 것으로 바꾼다 (공용 시험 파일은 건드리지 않는다).
## 실행: godot --headless --path . res://tools/probe_lake_terrain.tscn   (끝줄 "[probe] 끝: 실패 N")
##  1) 그림 옷: sap_lake(호수 세 방)·sap_descent(숨은 내리막 — 방 메타 terrain_skin) 이 읽히고 역할별 조각이 있다, 잿빛 표는 데이터 파일에서
##  2) 방 4개: 지형·가시·비밀 벽이 모두 그림, 충돌 그대로, 드러난 윗면 발밑 90% 넘게 그림, 그림 윗선이 충돌 윗면 ±8px,
##     드러난 끝 밖 발 높이 그림 34px 이하, 몸통 결은 묶음 맨 아래 겹, 가시 그림이 판정을 덮고 너무 솟지 않음, 벽 조각이 높은 옆면에
##  3) 수액 웅덩이: 그림 겉모습(물 지형)이 있고 웅덩이 폭을 덮는다, 판정·수면 높이는 그대로, 다른 지역(잠긴 채굴장) 웅덩이는 옛 그림
##  4) 배경 세 장이 기획자 그림(1536×1024)이고 방이 그 그림을 쓴다
##  5) 만들기 비용 (방 하나 평균 < 60ms, 삼각형 < 40000, 노드 하나 그리기 호출 4번 이하)

const LAKE_ROOMS := ["hidden_descent", "sap_lake_01", "sap_lake_02", "sap_lake_boss"]
## 그림 윗선이 충돌 윗면에서 벗어나도 되는 거리 (px)
const TOP_TOL := 8.0

var _atlas_cache := {}


func _ready() -> void:
	print("[probe] 수액의 호수 지형 그림 시험 시작")
	TerrainSkin.clear_cache()
	_probe_skins()
	await _probe_lake_rooms()
	await _probe_pools()
	_probe_backgrounds()
	await _probe_lake_cost()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _atlas_of(skin: TerrainSkin) -> Image:
	if not _atlas_cache.has(skin.region):
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://art/terrain/%s/atlas.png" % skin.region))
		img.convert(Image.FORMAT_RGBA8)
		_atlas_cache[skin.region] = img
	return _atlas_cache[skin.region]


# ---------- 1) 그림 옷 ----------
func _probe_skins() -> void:
	var lake := TerrainSkin.for_region("sap_lake")
	var desc := TerrainSkin.for_region("sap_descent")
	_check(lake != null and desc != null, "수액의 호수 그림 옷 두 벌이 읽힌다 (sap_lake, sap_descent)")
	if lake == null or desc == null:
		return
	for s in [lake, desc]:
		var sk: TerrainSkin = s
		_check(sk.has_role("branch") and sk.has_role("ground") and sk.has_role("hang") and sk.has_role("thorn") and sk.has_role("wall"), "%s 역할별 조각: 가지 %d·바닥 %d·매달림 %d·가시 %d·벽 %d" % [sk.region, sk.list("branch").size(), sk.list("ground").size(), sk.list("hang").size(), sk.list("thorn").size(), sk.list("wall").size()])
		_check(sk.atlas != null and sk.fill != null and sk.fill_v != null, "%s atlas·몸통 결 그림이 있다" % sk.region)
		var bad := []
		for n in sk.list("branch") + sk.list("slab") + sk.list("ground"):
			var w := sk.walk_of(n)
			if w.y - w.x < 60.0:
				bad.append(n)
		_check(bad.is_empty(), "%s 걷는 조각마다 걷는 구간이 60px 넘게 있다 %s" % [sk.region, bad])
	_check(lake.has_role("water") and lake.has_role("wave"), "호수 그림 옷에 물 조각(수면 %d·물결 %d)이 있다" % [lake.list("water").size(), lake.list("wave").size()])
	_check(CrackedArt.can_build(lake), "호수 그림 옷에 금 간 벽 그림 세 장이 있다")
	var spec := Purity.ash_spec("sap_lake")
	_check(spec.has("hues") and (spec["hues"] as Dictionary).has("yellow") and (spec["hues"] as Dictionary).has("cyan"), "호수 잿빛 팔레트는 데이터 파일(data/terrain/sap_lake.json)에서 읽는다 (색상 띠 %d개)" % (spec.get("hues", {}) as Dictionary).size())
	# 잿빛 표: 무채색 줄 가운데 밝기가 너무 어둡지 않다 (오염됐지만 어둡지 않게)
	var img: Image = Purity.ash_lut("sap_lake").get_image()
	var mid := img.get_pixel(Purity.LUT_W / 2, 0).get_luminance()
	_check(mid > 0.42 and mid < 0.65, "호수 잿빛 표 가운데 밝기 %.2f (0.42~0.65 — 탁하지만 너무 어둡지 않게)" % mid)


# ---------- 2) 방 ----------
func _probe_lake_rooms() -> void:
	var not_art := []
	var collider_bad := []
	var feet_bad := []
	var top_bad := []
	var tops_all: Array = []
	var tops_checked := 0
	var worst_cov := 1.0
	var worst_name := ""
	var ends_checked := 0
	var over_bad := []
	var over_all := []
	var fill_bad := []
	var tip_bad := []
	var skin_bad := []
	var walls := 0
	for id in LAKE_ROOMS:
		var room := await _load_room(id)
		var want := "sap_descent" if id == "hidden_descent" else "sap_lake"
		if str(room.get("region")) != "sap_lake":
			skin_bad.append("%s 지역 %s" % [id, room.get("region")])
		var solids := _solids(room)
		var bounds: Rect2 = room.get("bounds")
		for t in room.get_node("Terrain").get_children():
			var art_n = t.get("_art")
			var sk: TerrainSkin = t.get("_skin")
			if sk != null and sk.region != want:
				skin_bad.append("%s/%s %s" % [id, t.name, sk.region])
			if sk != null:
				_atlas_img = _atlas_of(sk)
			if art_n is TerrainArt and not (art_n as TerrainArt).fill_in_layer():
				fill_bad.append("%s/%s" % [id, t.name])
			if art_n is TerrainArt:
				walls += _wall_strips(art_n)
			if art_n is TerrainArt and not (t is SecretWall or t is CrackedWall):
				for seg in _top_segments(t):
					for side in [-1.0, 1.0]:
						var far := _overhang(t, art_n, seg[0] if side < 0.0 else seg[1], side, solids, bounds)
						if far < 0.0:
							continue
						ends_checked += 1
						over_all.append([far, "%s/%s %s" % [id, t.name, "왼끝" if side < 0.0 else "오른끝"]])
						if far > OVERHANG_MAX:
							over_bad.append("%s/%s %s %.0fpx" % [id, t.name, "왼끝" if side < 0.0 else "오른끝", far])
			if t is SecretWall or t is CrackedWall:
				if t.get("_crack") == null and not (t.get("_broken") == true):
					not_art.append("%s/%s" % [id, t.name])
				continue
			if (t is Platform or t is TerrainPolygon) and not t.is_art():
				not_art.append("%s/%s" % [id, t.name])
				continue
			if t is Platform:
				var cs: CollisionShape2D = _first_shape(t)
				var ok: bool = cs != null and cs.shape is RectangleShape2D and (cs.shape as RectangleShape2D).size == t.size and cs.position == t.size / 2.0 and cs.one_way_collision == bool(t.one_way)
				if not ok:
					collider_bad.append("%s/%s" % [id, t.name])
			for seg in _top_segments(t):
				var r := _feet_check(t, seg[0], seg[1], solids, bounds)
				if r.is_empty():
					continue
				tops_checked += 1
				if float(r["cov"]) < worst_cov:
					worst_cov = r["cov"]
					worst_name = "%s/%s" % [id, t.name]
				if float(r["cov"]) < 0.9:
					feet_bad.append("%s/%s 덮임 %.0f%%" % [id, t.name, float(r["cov"]) * 100.0])
				tops_all.append(float(r["top"]))
				if "--verbose" in OS.get_cmdline_user_args():
					print("[probe]   %s/%s 윗선 %+.0fpx 덮임 %.0f%%" % [id, t.name, float(r["top"]), float(r["cov"]) * 100.0])
				if absf(float(r["top"])) > TOP_TOL:
					top_bad.append("%s/%s 윗선 %+.0fpx" % [id, t.name, float(r["top"])])
		var hz := room.get_node_or_null("Hazards")
		if hz:
			for th in hz.get_children():
				if th is Thorns:
					var tart = th.get("_art")
					if tart == null:
						not_art.append("%s/%s" % [id, th.name])
						continue
					var sk2: TerrainSkin = (tart as TerrainArt).skin
					if sk2.region != want:
						skin_bad.append("%s/%s(가시) %s" % [id, th.name, sk2.region])
					var cs2: CollisionShape2D = _first_shape(th)
					var hr := Thorns.hit_rect(th.size, th.facing_dir)
					if cs2 == null or (cs2.shape as RectangleShape2D).size != hr.size or cs2.position != hr.get_center():
						collider_bad.append("%s/%s(가시)" % [id, th.name])
					var ab := _art_bounds(tart)
					var allowed := _thorn_allowed(th.size, th.facing_dir, float(sk2.param("thorn", "sink", 10.0)))
					if not allowed.encloses(ab) or ab.intersection(hr).get_area() < hr.get_area() * 0.95:
						tip_bad.append("%s/%s 그림 %s 판정 %s" % [id, th.name, ab, hr])
		await _free_room(room)
	_check(skin_bad.is_empty(), "방 4곳: 지역은 sap_lake 그대로, 숨은 내리막만 sap_descent 그림 옷 (다른 것 %s)" % [skin_bad.slice(0, 6)])
	_check(not_art.is_empty(), "방 4곳: 지형·가시·비밀 벽이 모두 그림 조각 (아닌 것 %s)" % [not_art.slice(0, 8)])
	_check(collider_bad.is_empty(), "방 4곳: 충돌 모양이 그대로 (다른 것 %s)" % [collider_bad.slice(0, 8)])
	_check(tops_checked >= 20 and feet_bad.is_empty(), "드러난 윗면 %d곳: 발밑(충돌 윗면 8px 아래)이 그림으로 90%% 넘게 덮임 (가장 낮은 %s %.0f%%) %s" % [tops_checked, worst_name, worst_cov * 100.0, feet_bad.slice(0, 6)])
	tops_all.sort()
	var med: float = tops_all[tops_all.size() / 2] if not tops_all.is_empty() else 0.0
	_check(top_bad.is_empty(), "드러난 윗면 %d곳: 그림 윗선이 충돌 윗면 ±%.0fpx 안 (중앙값 %+.0fpx, 범위 %+.0f~%+.0f) %s" % [tops_checked, TOP_TOL, med, tops_all[0] if not tops_all.is_empty() else 0.0, tops_all[-1] if not tops_all.is_empty() else 0.0, top_bad.slice(0, 6)])
	over_all.sort_custom(func(x, y): return x[0] > y[0])
	_check(ends_checked >= 20 and over_bad.is_empty(), "드러난 충돌 끝 %d곳: 끝 밖 발 높이에 그림이 %.0fpx 넘게 남지 않는다 (가장 긴 %s) %s" % [ends_checked, OVERHANG_MAX, ("%.0fpx %s" % [over_all[0][0], over_all[0][1]]) if not over_all.is_empty() else "-", over_bad.slice(0, 6)])
	_check(fill_bad.is_empty(), "몸통 결은 지형 묶음 맨 아래 겹 (아닌 것 %s)" % [fill_bad.slice(0, 6)])
	_check(tip_bad.is_empty(), "방의 가시: 그림이 판정을 덮고 너무 솟지 않는다 %s" % [tip_bad.slice(0, 4)])
	_check(walls >= 6, "높은 옆면에 벽 조각(줄기·기둥 그림)이 붙는다 (%d 토막)" % walls)


## TerrainArt 의 atlas 삼각형 중 벽 조각(wall 역할) 토막 수 (uv 가 벽 조각 자리 안인 사각형 묶음을 센다)
func _wall_strips(art: TerrainArt) -> int:
	var skin := art.skin
	if not skin.has_role("wall"):
		return 0
	var rects := []
	for n in skin.list("wall"):
		var r := skin.rect_of(n)
		rects.append(Rect2(r.position / skin.atlas_size, r.size / skin.atlas_size))
	var b: Dictionary = art._bufs[TerrainArt.BUF_ATLAS]
	var uvs: PackedVector2Array = b["uvs"]
	var hits := 0
	for uv in uvs:
		for rr in rects:
			if (rr as Rect2).grow(0.0005).has_point(uv):
				hits += 1
				break
	# 토막 하나 = (COLS+1) × 4 꼭짓점
	return hits / ((TerrainWall.COLS + 1) * 4)


# ---------- 3) 수액 웅덩이 ----------
func _probe_pools() -> void:
	var bad := []
	var n := 0
	for id in ["sap_lake_01", "sap_lake_02", "sap_lake_boss"]:
		var room := await _load_room(id)
		for c in room.get_children():
			if not (c is SapPool):
				continue
			n += 1
			var pool: SapPool = c
			var w: SapWaterArt = pool.get("_water")
			if w == null:
				bad.append("%s/%s 그림 없음" % [id, pool.name])
				continue
			var cs: CollisionShape2D = pool._shape
			var rect := cs.shape as RectangleShape2D
			if rect.size != Vector2(pool.size.x, pool.size.y * 0.8) or cs.position != Vector2(pool.size.x / 2.0, pool.size.y * 0.6):
				bad.append("%s/%s 판정이 바뀜" % [id, pool.name])
			if pool.surface_y() != pool.global_position.y:
				bad.append("%s/%s 수면 높이가 바뀜" % [id, pool.name])
			var body: TerrainArt = w.get("_body")
			var ab := _art_bounds(body)
			if ab.position.x > 4.0 or ab.end.x < pool.size.x - 4.0 or ab.position.y > 2.0 or ab.end.y < pool.size.y:
				bad.append("%s/%s 그림 %s 이 웅덩이 %s 를 덮지 않음" % [id, pool.name, ab, pool.size])
		await _free_room(room)
	_check(n >= 4 and bad.is_empty(), "호수 웅덩이 %d곳: 물 지형 그림이 웅덩이를 덮고, 판정·수면 높이는 그대로 %s" % [n, bad.slice(0, 4)])
	# 다른 지역(잠긴 채굴장)의 웅덩이는 옛 코드 그림 그대로
	var fm := await _load_room("flooded_mine_01")
	var other := 0
	var other_art := 0
	for p in fm.find_children("*", "SapPool", true, false):
		other += 1
		if p.get("_water") != null:
			other_art += 1
	await _free_room(fm)
	_check(other_art == 0, "잠긴 채굴장 웅덩이 %d곳은 옛 그림 그대로 (그림 %d)" % [other, other_art])


# ---------- 4) 배경 ----------
func _probe_backgrounds() -> void:
	var bad := []
	for p in ["res://art/backgrounds/bg_sap_lake_1.png", "res://art/backgrounds/bg_sap_lake_boss.png", "res://art/backgrounds/bg_hidden_descent.png"]:
		var tex: Texture2D = load(p)
		if tex == null or tex.get_size() != Vector2(1536, 1024):
			bad.append(p)
	# 임시 그림(코드 그라데이션)이 아니라 기획자 그림: 원본 파일과 크기가 같다
	var pairs := {"res://art/backgrounds/bg_sap_lake_1.png": "res://익스펜션/그림/배경/4-1.PNG", "res://art/backgrounds/bg_sap_lake_boss.png": "res://익스펜션/그림/배경/4-2.PNG", "res://art/backgrounds/bg_hidden_descent.png": "res://익스펜션/그림/배경/5.PNG"}
	for k in pairs:
		var src := ProjectSettings.globalize_path(pairs[k])
		if FileAccess.file_exists(src) and FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(k)).size() != FileAccess.get_file_as_bytes(src).size():
			bad.append("%s ≠ %s" % [k, pairs[k]])
	_check(bad.is_empty(), "배경 세 장이 기획자 그림 (1536×1024) %s" % [bad])


# ---------- 5) 비용 ----------
func _probe_lake_cost() -> void:
	var sum := 0.0
	var worst := 0.0
	var worst_id := ""
	var tri_max := 0
	var calls_bad := []
	for id in LAKE_ROOMS:
		TerrainArt.build_usec = 0
		TerrainArt.tri_count = 0
		var room := await _load_room(id)
		var ms := TerrainArt.build_usec / 1000.0
		sum += ms
		if ms > worst:
			worst = ms
			worst_id = id
		tri_max = maxi(tri_max, TerrainArt.tri_count)
		for t in room.get_node("Terrain").get_children():
			var art: TerrainArt = t.get_node_or_null("Art")
			if art:
				var bufs := 0
				for bb in art._bufs:
					if (bb["idx"] as PackedInt32Array).size() >= 3:
						bufs += 1
				if bufs > 4:
					calls_bad.append("%s/%s" % [id, t.name])
		print("[probe] %s 그림 지형 만들기 %.1fms, 삼각형 %d" % [id, ms, TerrainArt.tri_count])
		await _free_room(room)
	var avg := sum / LAKE_ROOMS.size()
	_check(avg < 60.0, "그림 지형 만들기: 방 하나 평균 %.1fms < 60ms (가장 긴 %s %.1fms)" % [avg, worst_id, worst])
	_check(tri_max < 40000, "방 하나 삼각형 %d개 < 40000" % tri_max)
	_check(calls_bad.is_empty(), "노드 하나에 그리기 호출 4번 이하 %s" % [calls_bad])

extends Node
## 정화 전후 차이 시험 (v1.1.0 기획자 요청 5 + 번외 점선 — 화면 없이 돈다).
## 실행: godot --headless --path . res://tools/probe_purify.tscn
##  a) canopy_01 잿빛 → 풀포기(BloomDecor) 없음, 안개 진하기 그대로(×1), 빛줄기 ×1, 잎 색 그대로
##  b) canopy_01 정화 → 풀포기 20 넘게 다 핀 채, 모두 걷는 윗면 위(±6px — 시험이 따로 잰 윗면), 지형 바로 앞 순서,
##     그리기 호출 5 이하, 다 핀 뒤 매 프레임 일 없음, 안개 ×0.5, 빛줄기 ×1.35, 잎이 푸른색
##  c) play_purify: 중간(1.75초)엔 일부만 돋음 → 끝나면 모두, 안개가 서서히 걷힘, 물결 끝 상태
##  d) 어두운 방(abyss_02, mine_deep): 정화되면 CanvasModulate 가 dark_color 에서 하얀색 쪽으로 0.25 → 밝아짐
##  e) 정화 기둥 이펙트: 씨앗 팔레트(원래 색 0.6 남김), 크기 ×1.15, 잎 흩날림 6장
##  f) 정화 물결 테두리 색·세기 (두 셰이더), 잿빛 아지랑이·대비 한 단계 진하게 (data/terrain)
##  g) 정화되는 지역의 모든 방: 풀포기가 160 이하, 걷는 윗면 위, 가시·수액 웅덩이 둘레 밖, 만드는 데 10ms 안
##  h) 점선 없음: 모든 방의 발판 그림에 색만 있는 사각형(옛 한쪽 방향 점선)이 없다
##  i) 되돌리기(reset_region) → 풀포기 사라짐
##  j) 방 첫 프레임 시간: 정화된 방(풀포기 만들기 포함, 모양 그림을 처음 만드는 경우까지)이 잿빛 방보다 10ms 넘게 늘지 않는다
##  k) 잿빛 방에 들어오면 풀포기·묘목 모양 그림을 미리 만든다 → 처음 쓰러진 적의 묘목이 그림을 새로 만들지 않는다
##  (g 에는 시험이 따로 하는 확인도 있다: 물리 판정으로 포기 밑동 바로 아래는 지형, 바로 위는 빈 곳 — BloomDecor 의 규칙을 베끼지 않은 확인)

const FOG := preload("res://scripts/world/fog_layer.gd")
const SHAFTS := preload("res://scripts/world/light_shafts.gd")
const LEAVES := preload("res://scripts/world/falling_leaves.gd")
## 정화되는 지역 (마을은 정화 경로가 없다 — 기획서 D20)
const PURE_REGIONS := ["canopy", "mine", "abyss", "sap_lake", "flooded_mine"]

var _fail := 0


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _load_room(id: String, purified: bool) -> Node:
	var region := _region_of(id)
	Purity.regions[region] = purified
	var room: Node = load("res://scenes/rooms/%s.tscn" % id).instantiate()
	add_child(room)
	await _frames(3)
	return room


func _free_room(room: Node) -> void:
	room.queue_free()
	await _frames(2)


func _region_of(id: String) -> String:
	var txt := FileAccess.get_file_as_string("res://scenes/rooms/%s.tscn" % id)
	var i := txt.find("\nregion = \"")
	if i < 0:
		return "canopy"
	var j := txt.find("\"", i + 11)
	return txt.substr(i + 11, j - i - 11)


func _decor(room: Node) -> BloomDecor:
	var d := room.get_node_or_null(Purity.BLOOM_NAME) as BloomDecor
	return d if d and not d.is_queued_for_deletion() else null


func _nodes_with(room: Node, script: Script) -> Array:
	var out := []
	for n in room.find_children("*", "", true, false):
		if n.get_script() == script:
			out.append(n)
	return out


## 시험이 따로 재는 걷는 윗면 (발판 윗변 — 장식 있는 덩어리·얇은 가지, 경사의 위를 보는 변)
func _tops(room: Node) -> Array:
	var out := []
	for t in room.get_node("Terrain").get_children():
		if t is SecretWall or t is CrackedWall:
			continue
		if t is Platform:
			if not t.decorate and not (t.size.y <= 90.0 and t.size.x >= 120.0):
				continue
			var o: Vector2 = t.global_position
			out.append([o, o + Vector2(t.size.x, 0)])
		elif t is TerrainPolygon:
			var poly: PackedVector2Array = t.polygon
			var o2: Vector2 = t.global_position
			for i in poly.size():
				var a := poly[i]
				var b := poly[(i + 1) % poly.size()]
				if b.x > a.x and absf(b.y - a.y) < (b.x - a.x) * 1.2:
					out.append([o2 + a, o2 + b])
	return out


## 자리 p 가 어떤 걷는 윗면 위 ±tol px 인가
func _on_top(tops: Array, p: Vector2, tol: float) -> bool:
	for s in tops:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		if p.x < a.x - 0.5 or p.x > b.x + 0.5:
			continue
		var y := lerpf(a.y, b.y, (p.x - a.x) / maxf(b.x - a.x, 0.001))
		if absf(p.y - y) <= tol:
			return true
	return false


func _fog_ratio(room: Node) -> float:
	var worst := -1.0
	for f in _nodes_with(room, FOG):
		var r: float = (f as Sprite2D).modulate.a / maxf(f.fog_color.a, 0.0001)
		if worst < 0.0 or absf(r - 1.0) < absf(worst - 1.0):
			worst = r   # 가장 덜 걷힌 겹
	return worst


func _ready() -> void:
	print("[probe] 시작: 정화 전후 차이")
	await _frames(2)
	Progress.reset()
	var keep: Dictionary = Purity.regions.duplicate()
	await _probe_canopy()
	await _probe_wave()
	await _probe_dark()
	_probe_fx()
	_probe_shaders_and_depth()
	await _probe_all_rooms()
	await _probe_reset()
	await _probe_first_frame()
	await _probe_warm()
	for k in Purity.regions.keys():
		Purity.regions[k] = keep.get(k, false)
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(_fail)


# ---------- a) b) 잿빛 / 정화된 canopy_01 ----------
func _probe_canopy() -> void:
	var room := await _load_room("canopy_01", false)
	_check(_decor(room) == null, "a) 잿빛 canopy_01: 풀포기 없음")
	_check(absf(_fog_ratio(room) - 1.0) < 0.01, "a) 잿빛: 안개 진하기 그대로 (×%.2f)" % _fog_ratio(room))
	var sh: Array = _nodes_with(room, SHAFTS)
	_check(not sh.is_empty() and absf(float(sh[0]._energy) - 1.0) < 0.01, "a) 잿빛: 빛줄기 ×1")
	var lv: Array = _nodes_with(room, LEAVES)
	_check(not lv.is_empty() and (lv[0] as CPUParticles2D).color.is_equal_approx(lv[0].leaf_color), "a) 잿빛: 떨어지는 잎은 원래 색")
	await _free_room(room)

	var t0 := Time.get_ticks_usec()
	room = await _load_room("canopy_01", true)
	var d := _decor(room)
	_check(d != null, "b) 정화된 canopy_01: 풀포기가 붙었다")
	if d == null:
		await _free_room(room)
		return
	var n := d.count()
	_check(n > 20 and n <= BloomDecor.MAX_TUFTS, "b) 풀포기 %d개 (20 넘고 %d 이하)" % [n, BloomDecor.MAX_TUFTS])
	_check(d.bloomed_count() == n, "b) 모두 다 핀 채 (%d/%d)" % [d.bloomed_count(), n])
	var tops := _tops(room)
	var off := []
	for p in d.global_spots():
		if not _on_top(tops, p, 6.0):
			off.append(p)
	_check(off.is_empty(), "b) 모두 걷는 윗면 위 ±6px (벗어난 것 %s)" % [off.slice(0, 5)])
	var terrain := room.get_node("Terrain")
	_check(d.get_index() == terrain.get_index() + 1, "b) 지형 바로 앞에 그린다 (순서 %d, 지형 %d)" % [d.get_index(), terrain.get_index()])
	_check(d.draw_call_count() <= BloomDecor.KIND_COUNT, "b) 그리기 호출 %d번 (모양 %d가지 이하 — MultiMesh)" % [d.draw_call_count(), BloomDecor.KIND_COUNT])
	_check(not d.is_processing(), "b) 다 핀 뒤에는 매 프레임 할 일이 없다")
	_check(absf(_fog_ratio(room) - FOG.CLEAR_ALPHA) < 0.01, "b) 정화: 안개 진하기 ×%.2f (= %.2f)" % [_fog_ratio(room), FOG.CLEAR_ALPHA])
	await _frames(1)
	var sh2: Array = _nodes_with(room, SHAFTS)
	_check(absf(float(sh2[0]._energy) - SHAFTS.ENERGY_ALIVE) < 0.01, "b) 정화: 빛줄기 ×%.2f" % float(sh2[0]._energy))
	var lv2: Array = _nodes_with(room, LEAVES)
	_check((lv2[0] as CPUParticles2D).color.is_equal_approx(LEAVES.LEAF_ALIVE), "b) 정화: 떨어지는 잎이 푸른색 %s" % (lv2[0] as CPUParticles2D).color)
	print("[probe]   canopy_01 정화 방 띄우기 %.1fms (풀포기 만들기 %.2fms)" % [(Time.get_ticks_usec() - t0) / 1000.0, d.build_usec / 1000.0])
	await _free_room(room)


# ---------- c) 정화 물결 ----------
func _probe_wave() -> void:
	var room := await _load_room("canopy_01", false)
	_check(_decor(room) == null, "c) 시작: 잿빛이라 풀포기 없음")
	var player := get_tree().get_first_node_in_group("player") as Node2D
	room.call("purify_from", player.global_position if player else Vector2(800, 2000))
	await _frames(1)
	var d := _decor(room)
	_check(d != null and Purity.wave_active, "c) play_purify: 풀포기 노드가 생기고 물결이 돈다")
	if d == null:
		await _free_room(room)
		return
	_check(d.started_count() < d.count(), "c) 물결 시작 직후에는 거의 숨어 있다 (돋기 시작 %d/%d)" % [d.started_count(), d.count()])
	await _wait(1.75)
	var mid_started := d.started_count()
	var mid_bloomed := d.bloomed_count()
	var mid_fog := _fog_ratio(room)
	_check(mid_started > 0 and mid_started < d.count(), "c) 중간(1.75초): 일부만 돋았다 (돋기 시작 %d, 다 핌 %d / %d)" % [mid_started, mid_bloomed, d.count()])
	_check(mid_fog < 0.999 and mid_fog > FOG.CLEAR_ALPHA - 0.001, "c) 중간: 안개가 걷히는 중 (×%.2f)" % mid_fog)
	await _wait(2.5)
	_check(not Purity.wave_active and is_equal_approx(Purity.level, 1.0), "c) 물결 끝 (wave_active=%s, level=%.2f)" % [Purity.wave_active, Purity.level])
	_check(d.bloomed_count() == d.count(), "c) 끝나면 모두 돋음 (%d/%d)" % [d.bloomed_count(), d.count()])
	_check(not d.is_processing(), "c) 다 돋은 뒤에는 멈춘다")
	_check(absf(_fog_ratio(room) - FOG.CLEAR_ALPHA) < 0.01, "c) 끝: 안개 ×%.2f" % _fog_ratio(room))
	await _free_room(room)


# ---------- d) 어두운 방 ----------
func _probe_dark() -> void:
	for id in ["abyss_02", "mine_deep"]:
		var room := await _load_room(id, false)
		var base: Color = room.get("dark_color")
		var cm0 := _dark_cm(room)
		var has0 := cm0 != null
		var ash_col := cm0.color if cm0 else Color.BLACK
		await _free_room(room)
		room = await _load_room(id, true)
		var cm1 := _dark_cm(room)
		var want := base.lerp(Color.WHITE, Purity.DARK_LIFT)
		var got := cm1.color if cm1 else Color.BLACK
		_check(has0 and ash_col.is_equal_approx(base), "d) %s 잿빛: 어두운 방 색 그대로 %s" % [id, ash_col])
		_check(cm1 != null and got.is_equal_approx(want) and got.get_luminance() > ash_col.get_luminance() + 0.1,
			"d) %s 정화: CanvasModulate %s → %s (밝기 %.2f → %.2f)" % [id, ash_col, got, ash_col.get_luminance(), got.get_luminance()])
		await _free_room(room)


func _dark_cm(room: Node) -> CanvasModulate:
	for c in room.get_children():
		if c is CanvasModulate and not c.is_queued_for_deletion():
			return c
	return null


# ---------- e) 정화 기둥 ----------
func _probe_fx() -> void:
	var tbl := preload("res://scripts/fx/fx_table.gd")
	var def: Dictionary = tbl.EFFECTS["purify"]
	var sc: Array = def["scale"]
	_check(def["palette"] == "seed" and is_equal_approx(float(def["keep"]), 0.6), "e) 정화 기둥: 씨앗 팔레트, 원래 색 0.6 남김 (%s %.2f)" % [def["palette"], float(def["keep"])])
	_check(absf(float(sc[0]) - 0.5 * 1.15) < 0.001 and absf(float(sc[1]) - 0.56 * 1.15) < 0.001, "e) 크기 ×1.15 (%s)" % [sc])
	var leaves := 0
	var flash_gold := false
	for ch in def["children"]:
		if str(ch[0]).begins_with("purify_leaf"):
			leaves += int(ch[1])
			var cd: Dictionary = tbl.EFFECTS[ch[0]]
			_check(str(cd["tex"]).begins_with("leaf_") and cd["palette"] == "seed", "e) %s: 잎 그림(%s), 씨앗 팔레트" % [ch[0], cd["tex"]])
		if ch[0] == "purify_flash":
			flash_gold = tbl.EFFECTS["purify_flash"]["palette"] == "gold"
	_check(leaves == 6, "e) 잎 흩날림 %d장 (6)" % leaves)
	_check(flash_gold, "e) 번쩍임은 금빛 그대로")
	var fx := Fx.spawn("purify", Vector2(100, 100))
	var m := fx.material as ShaderMaterial if fx else null
	_check(m != null and m.get_shader_parameter("pal_mid") == tbl.PALETTES["seed"][1], "e) 띄운 기둥 재질의 팔레트가 씨앗색")
	Fx.clear()


# ---------- f) 셰이더 테두리 · 잿빛 아지랑이 ----------
func _probe_shaders_and_depth() -> void:
	for path in ["res://shaders/ash_purify.gdshader", "res://shaders/ash_purify_add.gdshader"]:
		var code := (load(path) as Shader).code
		_check(code.contains("vec3(0.75, 1.0, 0.55)") and code.contains("RING_STRENGTH = 0.7") and code.contains("col += RING_COLOR * edge * RING_STRENGTH"),
			"f) %s: 초록빛 금색 테두리 ×0.7" % path.get_file())
		var wi := code.find("const float RING_WIDTH = ")
		var ring_w := float(code.substr(wi + 25, code.find(";", wi) - wi - 25)) if wi >= 0 else -1.0
		_check(ring_w > 0.0 and ring_w < 0.3 and code.contains("smoothstep(0.0, RING_WIDTH, abs(d - radius))"),
			"f) %s: 고리 너비 %.2f — 색이 번지는 경계(softness 0.3)보다 좁아 넓은 빛 물결이 아니라 고리로 보인다" % [path.get_file(), ring_w])
	var cj = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain/canopy.json"))
	var ca: Dictionary = cj["depth"]["ash"]
	_check(is_equal_approx(float(ca["haze"]), 0.34) and is_equal_approx(float(ca["contrast"]), 0.60), "f) 수관 잿빛 아지랑이 0.34 · 대비 0.60 (%s / %s)" % [ca["haze"], ca["contrast"]])
	var weak := []
	for r in ["canopy", "mine", "abyss", "abyss_garden", "sap_lake", "sap_descent", "flooded_mine"]:
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain/%s.json" % r))
		var a: Dictionary = j["depth"]["ash"]
		var b: Dictionary = j["depth"]["alive"]
		if float(a["haze"]) - float(b["haze"]) < 0.14 or float(b["contrast"]) - float(a["contrast"]) < 0.14:
			weak.append("%s(흐림 %.2f/%.2f 대비 %.2f/%.2f)" % [r, a["haze"], b["haze"], a["contrast"], b["contrast"]])
	_check(weak.is_empty(), "f) 정화되는 지역 모두 잿빛이 정화 후보다 흐림 +0.14·대비 −0.14 넘게 %s" % [weak])


# ---------- g) h) 모든 방 ----------
func _probe_all_rooms() -> void:
	var files := DirAccess.get_files_at("res://scenes/rooms")
	var ids := []
	for f in files:
		if f.ends_with(".tscn"):
			ids.append(f.get_basename())
	ids.sort()
	var total := 0
	var rooms := 0
	var over := []
	var off := []
	var hazard := []
	var slow := []
	var worst_us := 0
	var worst_room := ""
	var dashes := []
	var floating := []
	var buried := []
	for id in ids:
		var region := _region_of(id)
		var pure := region in PURE_REGIONS
		var room := await _load_room(id, pure)
		# h) 점선 없음
		for t in room.get_node("Terrain").get_children():
			var art = t.get("_art")
			if t is Platform and art is TerrainArt and ((art as TerrainArt)._bufs[TerrainArt.BUF_PLAIN]["idx"] as PackedInt32Array).size() > 0:
				dashes.append("%s/%s" % [id, t.name])
		if not pure:
			_check(_decor(room) == null, "g) %s(%s): 정화되지 않는 지역이라 풀포기 없음" % [id, region])
			await _free_room(room)
			continue
		var d := _decor(room)
		rooms += 1
		if d == null:
			off.append("%s 풀포기 노드 없음" % id)
			await _free_room(room)
			continue
		total += d.count()
		if d.count() > BloomDecor.MAX_TUFTS:
			over.append("%s %d" % [id, d.count()])
		if d.build_usec > worst_us:
			worst_us = d.build_usec
			worst_room = id
		if d.build_usec > 10000:
			slow.append("%s %.1fms" % [id, d.build_usec / 1000.0])
		var tops := _tops(room)
		var keep_out := []
		for th in room.find_children("*", "Thorns", true, false):
			keep_out.append(Rect2(th.global_position, th.size))
		for sp in room.find_children("*", "SapPool", true, false):
			keep_out.append(Rect2(sp.global_position, sp.size))
		await get_tree().physics_frame
		for p in d.global_spots():
			if not _on_top(tops, p, 6.0):
				off.append("%s %s" % [id, p])
			# 시험이 따로 하는 확인 (BloomDecor 규칙과 무관): 밑동 바로 아래는 지형 충돌, 그 위(윗면 10px 위)는 비어 있다
			if not _solid_at(room, p + Vector2(0, 8)):
				floating.append("%s %s" % [id, p])
			if _solid_at(room, p + Vector2(0, -BloomDecor.SINK - 10.0)):
				buried.append("%s %s" % [id, p])
			for r in keep_out:
				if (r as Rect2).grow(20.0).has_point(p):
					hazard.append("%s %s" % [id, p])
					break
		await _free_room(room)
	_check(rooms >= 30 and off.is_empty(), "g) 정화되는 지역 방 %d곳 풀포기 %d개: 모두 걷는 윗면 위 ±6px %s" % [rooms, total, off.slice(0, 6)])
	_check(floating.is_empty(), "g) (물리 판정) 포기 밑동 바로 아래가 지형이다 — 공중에 뜬 것 %s" % [floating.slice(0, 6)])
	_check(buried.is_empty(), "g) (물리 판정) 포기 바로 위는 빈 곳이다 — 다른 지형에 묻힌 것 %s" % [buried.slice(0, 6)])
	_check(over.is_empty(), "g) 방마다 %d 이하 %s" % [BloomDecor.MAX_TUFTS, over])
	_check(hazard.is_empty(), "g) 가시·수액 웅덩이 둘레(20px)에는 없다 %s" % [hazard.slice(0, 6)])
	_check(slow.is_empty(), "g) 풀포기 만들기 방마다 10ms 안 (가장 오래 %s %.2fms) %s" % [worst_room, worst_us / 1000.0, slow])
	_check(dashes.is_empty(), "h) 방 %d곳: 발판 그림에 옛 한쪽 방향 점선(색만 있는 사각형)이 없다 %s" % [ids.size(), dashes.slice(0, 6)])


## 그 자리에 지형(발판·경사 — 부서지는 벽·비밀 벽 포함)의 충돌이 있는가 (물리 서버에 묻는다)
func _solid_at(room: Node, gp: Vector2) -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = gp
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var space := (room as Node2D).get_world_2d().direct_space_state
	for hit in space.intersect_point(q, 16):
		var c = hit.get("collider")
		if (c is Platform or c is TerrainPolygon) and room.is_ancestor_of(c):
			return true
	return false


# ---------- i) 되돌리기 ----------
func _probe_reset() -> void:
	var room := await _load_room("canopy_02", true)
	_check(_decor(room) != null, "i) 정화된 canopy_02: 풀포기 있음")
	Purity.reset_region("canopy")
	await _frames(2)
	_check(_decor(room) == null and absf(_fog_ratio(room) - 1.0) < 0.01, "i) reset_region → 풀포기 사라지고 안개 원래대로")
	await _free_room(room)


# ---------- j) 방 첫 프레임 ----------
## 방을 붙이고 첫 프레임이 지날 때까지 (Room._ready + 미뤄 둔 풀포기 붙이기). 세 번 재어 가운데 값.
func _first_frame_ms(id: String, purified: bool, cold: bool) -> float:
	var times := []
	for i in 3:
		Purity.regions[_region_of(id)] = purified
		if cold:
			BloomDecor._mesh_cache.clear()
		var ps: PackedScene = load("res://scenes/rooms/%s.tscn" % id)
		var t0 := Time.get_ticks_usec()
		var room: Node = ps.instantiate()
		add_child(room)
		await get_tree().process_frame
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		await _free_room(room)
	times.sort()
	return times[1]


func _probe_first_frame() -> void:
	for id in ["canopy_01", "mine_01", "abyss_02"]:
		var ash := await _first_frame_ms(id, false, false)
		var warm := await _first_frame_ms(id, true, false)
		var cold := await _first_frame_ms(id, true, true)
		_check(warm - ash < 10.0 and cold - ash < 10.0, "j) %s 첫 프레임: 잿빛 %.1fms / 정화 %.1fms / 정화(모양 그림 처음) %.1fms — 늘어난 것 10ms 안" % [id, ash, warm, cold])


# ---------- k) 모양 그림 미리 만들기 ----------
func _probe_warm() -> void:
	BloomDecor._mesh_cache.clear()
	var room := await _load_room("canopy_01", false)
	_check(_decor(room) == null and BloomDecor.is_warm("canopy"), "k) 잿빛 canopy_01: 풀포기는 없어도 모양 그림은 방에 들어올 때 미리 만든다")
	var before: Mesh = BloomDecor.kind_mesh("canopy", 4)
	var sp: Node2D = load("res://scenes/world/sprout.tscn").instantiate()
	room.add_child(sp)
	var mesh: Mesh = sp.get("_mesh")
	_check(mesh != null and mesh == before, "k) 쓰러진 적의 묘목은 미리 만든 어린 나무 그림을 그대로 쓴다 (새로 만들지 않음)")
	await _free_room(room)

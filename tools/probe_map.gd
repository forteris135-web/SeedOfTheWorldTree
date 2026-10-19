extends Node
## 지도 시험(headless). 실행: godot --headless --path . res://tools/probe_map_scene.tscn
##   창으로 돌리면(--headless 없이) screenshots/debug_map_open.png / debug_map_zoomed_out.png 도 남긴다 (눈 확인용).
## 1) 색칠: 가짜 방 데이터에 explore_total/explore_found(또는 explore_ids)를 넣어 지도를 몇 프레임 그려 보고
##    오류 없이 그려지는지(실제 draw 호출 수), 색 판정 규칙(남음=연초록, 다 찾음=하늘색)이 MapScreen 의 함수 기준으로 맞는지.
## 2) 확대·이동 (2026-10-19): scenes/rooms 의 모든 방(41개)을 가 본 것으로 치고 연다 →
##    열 때 지금 방이 가운데·배율 ZOOM_OPEN, 배율 막기(최대 ZOOM_MAX / 최소 = 전체가 한눈에), 가운데 막기(범위 밖으로 못 감),
##    커서 자리 고정 확대, 터치 한 손가락 끌기·두 손가락 벌리기·두 번 누르기(처음대로)·✕(닫기), 화면 가운데 한 번 누르기는 닫지 않음.
## 3) 중간 보스 집계: 중간 보스 깃발이 탐사 요소로 세어지고(쓰러뜨려야 '모두 찾음'), 옛 저장을 바로잡으며(fix_saved_minibosses, 두 번 해도 같음),
##    MINIBOSS_ROOMS 표가 scenes/rooms 의 MiniBossRoom 전부와 같고, 실제 방(canopy_mini_1·canopy_hidden)을 띄우면 Room 이 깃발을 모으는지.
## 자동 로드(Progress 등)가 필요해서 -s 가 아니라 씬으로 돌린다. 마지막 줄 "[지도시험] 결과: 통과/실패".

var _draws := 0
var _fail := 0


func _check(ok: bool, text: String) -> void:
	print("[지도시험] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


## [찾은 수, 전체 수] 비교 (Array[int] 와 글자 그대로의 배열을 == 로 견주지 않게)
func _pair(c: Array, a: int, b: int) -> bool:
	return c.size() == 2 and int(c[0]) == a and int(c[1]) == b


## 지도가 target 을 가운데로 하려 할 때 실제로 와야 할 자리 (보이는 폭보다 좁은 축은 범위 가운데, 아니면 범위 안으로 막음)
func _expect_center(map: MapScreen, target: Vector2) -> Vector2:
	var half: Vector2 = map.view_size() / (2.0 * map._zoom)
	var slack: float = MapScreen.EDGE_SLACK / map._zoom
	var b: Rect2 = map._bounds
	var out := target
	for a in 2:
		if b.size[a] <= half[a] * 2.0:
			out[a] = b.get_center()[a]
		else:
			out[a] = clampf(target[a], b.position[a] + half[a] - slack, b.end[a] - half[a] + slack)
	return out


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)   # 화면 없는 실행은 창이 정사각형이라 지도 칸이 세로로 길다 → 실제 비율로
	await _frames(2)
	await _test_colors()
	await _test_zoom_pan()
	await _test_miniboss()
	print("[지도시험] 결과: %s (실패 %d)" % ["통과" if _fail == 0 else "실패", _fail])
	get_tree().quit(0 if _fail == 0 else 1)


# ───────── 1) 색칠 ─────────
func _test_colors() -> void:
	Progress.reset()
	Progress.visited_rooms["a"] = {"offset": Vector2(0, 0), "size": Vector2(2000, 1000), "name": "남음", "region": "canopy", "grasses": [Vector2(100, 100)], "portals": [Vector2(1900, 900)], "boss": false, "explore_total": 3, "explore_found": 1}
	Progress.visited_rooms["b"] = {"offset": Vector2(2000, 0), "size": Vector2(2000, 1000), "name": "다찾음", "region": "village", "grasses": [], "portals": [], "boss": true, "explore_total": 2, "explore_found": 2}
	Progress.visited_rooms["c"] = {"offset": Vector2(0, 1000), "size": Vector2(2000, 1000), "name": "값없음", "region": "mine", "grasses": [], "boss": false}
	# id 목록 방식: 깃발 하나·달빛풀 하나 중 깃발만 찾은 상태 → 1/2 연초록, 달빛풀도 피우면 2/2 하늘색
	Progress.visited_rooms["d"] = {"offset": Vector2(2000, 1000), "size": Vector2(2000, 1000), "name": "목록", "region": "abyss", "grasses": [], "boss": false, "explore_ids": ["read_test_record", "grass:test_grass"]}
	Progress.set_flag("read_test_record")
	var map := MapScreen.new()
	add_child(map)
	await get_tree().process_frame
	map._view.draw.connect(func() -> void: _draws += 1)
	map.open(null)
	# 몇 프레임 그려서 _on_draw 가 오류 없이 도는지 (오류가 나면 SCRIPT ERROR 줄이 찍힌다)
	await _frames(5)
	map.close()
	_check(_draws >= 5, "draw 호출 수: %d" % _draws)
	for id in Progress.visited_rooms:
		var r: Dictionary = Progress.visited_rooms[id]
		var counts := MapScreen.explore_counts(r)
		var fill := MapScreen.explore_fill(r)
		var color := "하늘색" if fill == MapScreen.FILL_DONE else ("연초록" if fill == MapScreen.FILL_REMAIN else "???")
		print("[지도시험] %s: %d/%d → %s" % [id, counts[0], counts[1], color])
	_check(MapScreen.explore_fill(Progress.visited_rooms["a"]) == MapScreen.FILL_REMAIN, "a 1/3 → 연초록")
	_check(MapScreen.explore_fill(Progress.visited_rooms["b"]) == MapScreen.FILL_DONE, "b 2/2 → 하늘색")
	_check(MapScreen.explore_fill(Progress.visited_rooms["c"]) == MapScreen.FILL_DONE, "c 값 없음 → 하늘색")
	_check(MapScreen.explore_fill(Progress.visited_rooms["d"]) == MapScreen.FILL_REMAIN, "d 1/2 → 연초록")
	Progress.grasses["test_grass"] = {"scene": "x", "name": "시험"}
	var d_after := MapScreen.explore_counts(Progress.visited_rooms["d"])
	_check(MapScreen.explore_fill(Progress.visited_rooms["d"]) == MapScreen.FILL_DONE, "d 달빛풀 피운 뒤 %d/%d → 하늘색" % [d_after[0], d_after[1]])
	_check(MapScreen.FILL_REMAIN != MapScreen.FILL_DONE and MapScreen.REGION_COLORS.size() == 6, "색 상수")
	map.queue_free()


## scenes/rooms 의 모든 방을 '가 본 방'으로 넣는다 (지도 자리·크기·이름은 방 파일에서). 방 id 목록을 돌려준다.
func _visit_all_rooms() -> Array:
	var ids := []
	var dir := DirAccess.open("res://scenes/rooms")
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		var txt := FileAccess.get_file_as_string("res://scenes/rooms/" + f)
		var rid := _root_prop(txt, "room_id")
		if rid == "":
			continue
		var b := _rect(_root_prop(txt, "bounds"))
		if b.size == Vector2.ZERO:
			b = Rect2(0, 0, 4800, 2400)
		Progress.visited_rooms[rid] = {"offset": _vec2(_root_prop(txt, "map_offset")), "size": b.size, "name": _root_prop(txt, "display_name"),
			"region": _root_prop(txt, "region"), "grasses": [], "portals": [], "boss": _root_prop(txt, "is_boss_room") == "true", "explore_total": 1, "explore_found": 0}
		ids.append(rid)
	return ids


func _touch(map: MapScreen, index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	map._on_touch(ev)


func _drag(map: MapScreen, index: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	map._on_drag(ev)


# ───────── 2) 확대·이동 ─────────
func _test_zoom_pan() -> void:
	Progress.reset()
	var ids := _visit_all_rooms()
	_check(ids.size() >= 40, "모든 방을 가 본 것으로 넣음: %d개" % ids.size())
	var fake := Room.new()   # 트리에 넣지 않는 가짜 '지금 방' (id 만 쓴다)
	fake.room_id = "village_02" if Progress.visited_rooms.has("village_02") else str(ids[ids.size() / 2])
	var map := MapScreen.new()
	add_child(map)
	await get_tree().process_frame
	map.open(fake)
	await _frames(3)
	var vs: Vector2 = map.view_size()
	var cur: Dictionary = Progress.visited_rooms[fake.room_id]
	var room_c: Vector2 = cur["offset"] + cur["size"] / 2.0
	var b: Rect2 = map._bounds
	print("[지도시험] 지도 칸 %s, 전체 범위 %s, 최소 배율 %.4f, 연 배율 %.3f, 가운데 %s / 지금 방(%s) 가운데 %s" % [vs, b, map.zoom_min(), map._zoom, map._center, fake.room_id, room_c])
	_check(is_equal_approx(map._zoom, MapScreen.ZOOM_OPEN) and map.zoom_min() < MapScreen.ZOOM_OPEN * 0.5, "열면 읽기 좋은 배율 %.2f (전체 맞춤 %.4f 보다 크게)" % [MapScreen.ZOOM_OPEN, map.zoom_min()])
	var open_c := _expect_center(map, room_c)
	_check(map._center.distance_to(open_c) < 1.0, "열면 지금 방이 가운데 (%s; 지도 칸보다 좁은 축은 전체 가운데 %s)" % [map._center, open_c])
	var room_rect := Rect2(map.world_to_view(cur["offset"]), cur["size"] * map._zoom)
	_check(Rect2(Vector2.ZERO, vs).encloses(room_rect), "지금 방이 지도 칸 안에 통째로 보인다 (%s)" % room_rect)
	# 배율 막기
	map.zoom_at(map._view.position + vs / 2.0, 1000.0)
	_check(is_equal_approx(map._zoom, MapScreen.ZOOM_MAX), "아무리 키워도 최대 %.2f (%.3f)" % [MapScreen.ZOOM_MAX, map._zoom])
	map.zoom_at(map._view.position + vs / 2.0, 0.00001)
	var tl: Vector2 = map.world_to_view(b.position)
	var br: Vector2 = map.world_to_view(b.end)
	print("[지도시험] 가장 작게: 배율 %.4f, 전체 범위의 화면 자리 %s ~ %s" % [map._zoom, tl, br])
	_check(is_equal_approx(map._zoom, map.zoom_min()) and tl.x >= -1.0 and tl.y >= -1.0 and br.x <= vs.x + 1.0 and br.y <= vs.y + 1.0, "가장 작게 하면 %d개 방 전체가 지도 칸 안에 든다" % ids.size())
	# 커서 자리 고정 확대
	map.reset_view()
	var p := map._view.position + Vector2(vs.x * 0.3, vs.y * 0.6)
	var w0: Vector2 = map.view_to_world(p - map._view.position)
	map.zoom_at(p, 1.5)
	var w1: Vector2 = map.view_to_world(p - map._view.position)
	_check(w0.distance_to(w1) < 2.0 and is_equal_approx(map._zoom, MapScreen.ZOOM_OPEN * 1.5), "휠·손가락 확대는 그 자리를 고정한다 (어긋남 %.2f 세계 px)" % w0.distance_to(w1))
	# 가운데 막기: 끝없이 밀어도 범위 밖으로 못 간다 (두 축 모두 지도 칸보다 넓게 ×2 배율에서)
	map.reset_view()
	map.zoom_at(map._view.position + vs / 2.0, 2.0)
	map.pan_screen(Vector2(1e7, 1e7))
	var half: Vector2 = vs / (2.0 * map._zoom)
	var slack: float = MapScreen.EDGE_SLACK / map._zoom
	print("[지도시험] 왼쪽 위 끝까지 밀기: 가운데 %s (막는 값 %s)" % [map._center, b.position + half - Vector2(slack, slack)])
	_check(map._center.distance_to(b.position + half - Vector2(slack, slack)) < 1.0, "왼쪽 위 끝에서 멈춘다 (여유 %.0f 화면 px)" % MapScreen.EDGE_SLACK)
	map.pan_screen(Vector2(-1e7, -1e7))
	_check(map._center.distance_to(b.end - half + Vector2(slack, slack)) < 1.0, "오른쪽 아래 끝에서 멈춘다 (%s)" % map._center)
	var vis := Rect2(map.view_to_world(Vector2.ZERO), vs / map._zoom)
	_check(vis.intersects(b), "끝에 가도 방이 보인다")
	# 터치: 한 손가락 끌기 (×2 배율 — 두 축 모두 움직일 수 있게)
	map.reset_view()
	map.zoom_at(map._view.position + vs / 2.0, 2.0)
	var c0: Vector2 = map._center
	var mid := map._view.position + vs / 2.0
	_touch(map, 0, mid, true)
	_drag(map, 0, mid + Vector2(50, 0))
	_drag(map, 0, mid + Vector2(100, 40))
	_touch(map, 0, mid + Vector2(100, 40), false)
	var moved: Vector2 = (c0 - map._center) * map._zoom
	_check(moved.distance_to(Vector2(100, 40)) < 1.0 and map.is_open(), "한 손가락 끌기 (100, 40) → 지도가 그만큼 따라온다 (%s), 닫히지 않는다" % moved)
	# 두 손가락 벌리기
	map.reset_view()
	var c_before: Vector2 = map._center
	_touch(map, 0, mid - Vector2(100, 0), true)
	_touch(map, 1, mid + Vector2(100, 0), true)
	_drag(map, 0, mid - Vector2(150, 0))
	_drag(map, 1, mid + Vector2(150, 0))
	var z_pinch: float = map._zoom
	_touch(map, 0, mid - Vector2(150, 0), false)
	_touch(map, 1, mid + Vector2(150, 0), false)
	_check(absf(z_pinch - MapScreen.ZOOM_OPEN * 1.5) < 0.002 and map._center.distance_to(_expect_center(map, c_before)) < 2.0 / map._zoom, "두 손가락 200→300px 벌리기 → 배율 ×1.5 (%.3f), 가운데 그대로" % z_pinch)
	_check(map.is_open() and map._last_tap_ms < 0, "두 손가락 뗌은 '누르기'로 치지 않는다")
	# 화면 가운데 한 번 누르기: 닫히지 않는다 / 두 번 누르기: 처음대로
	map.pan_screen(Vector2(300, 0))
	_touch(map, 0, mid, true)
	_touch(map, 0, mid, false)
	_check(map.is_open(), "화면 가운데 한 번 누르기로는 닫히지 않는다")
	_touch(map, 0, mid + Vector2(10, 5), true)
	_touch(map, 0, mid + Vector2(10, 5), false)
	_check(is_equal_approx(map._zoom, MapScreen.ZOOM_OPEN) and map._center.distance_to(open_c) < 1.0, "두 번 누르기 → 처음대로 (배율 %.3f, 가운데 %s)" % [map._zoom, map._center])
	# 키보드 '지금 방' (손길 버튼)
	map.pan_screen(Vector2(-400, 200))
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	map._input(ev)
	_check(map._center.distance_to(open_c) < 1.0, "손길 버튼(E·U / △·Y) → 지금 방으로")
	# 누르고 있는 이동 키: 키보드·패드는 지도를 움직이고, 터치는 끌기로만 (화면 스틱을 누른 채 지도를 열어도 흘러가지 않게)
	var dev := InputDevice.current
	map.reset_view()
	InputDevice._set_device(InputDevice.Kind.TOUCH, -1)
	Input.action_press("move_right")
	var ct0: Vector2 = map._center
	map._held_input(0.25)
	var touch_moved: float = map._center.distance_to(ct0)
	InputDevice._set_device(InputDevice.Kind.KEYBOARD, -1)
	map._held_input(0.25)
	var key_moved: float = map._center.x - ct0.x
	Input.action_release("move_right")
	InputDevice._set_device(dev, -1)
	_check(touch_moved < 0.01 and key_moved > 100.0, "이동 키를 누르고 있으면: 터치 장치는 그대로(%.1f), 키보드는 오른쪽으로 (%.0f 세계 px)" % [touch_moved, key_moved])
	await _frames(3)
	_draws = 0
	map._view.draw.connect(func() -> void: _draws += 1)
	await _frames(3)
	_check(_draws >= 3, "%d개 방을 확대한 채 그려도 오류 없음 (draw %d)" % [ids.size(), _draws])
	if DisplayServer.get_name() != "headless":
		map.reset_view()
		await _frames(4)
		_shot("debug_map_open.png")
		map.zoom_at(mid, 0.001)
		await _frames(4)
		_shot("debug_map_zoomed_out.png")
	# ✕ 로 닫기
	var cb: Dictionary = map.close_button()
	_touch(map, 0, cb["pos"], true)
	_touch(map, 0, cb["pos"], false)
	_check(not map.is_open() and not get_tree().paused, "오른쪽 위 ✕ 누르기 → 닫히고 멈춤 풀림")
	map.queue_free()
	fake.free()


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(ProjectSettings.globalize_path("res://screenshots/" + name))
		print("[지도시험] 스크린샷 screenshots/%s" % name)


# ───────── 3) 중간 보스 집계 ─────────
func _test_miniboss() -> void:
	Progress.reset()
	# 함수 규칙
	var e := {"offset": Vector2.ZERO, "size": Vector2(100, 100), "explore_ids": {"pickups": [], "rescues": [], "records": [], "grasses": ["g1"], "minibosses": ["miniboss_test"]}}
	Progress.grasses["g1"] = {"scene": "x", "name": "x"}
	var c := MapScreen.explore_counts(e)
	_check(_pair(c, 1, 2) and MapScreen.explore_fill(e) == MapScreen.FILL_REMAIN and MapScreen.has_live_miniboss(e), "달빛풀은 찾았어도 중간 보스가 남으면 1/2 연초록 + 작은 ☠")
	Progress.set_flag("miniboss_test")
	c = MapScreen.explore_counts(e)
	_check(_pair(c, 2, 2) and MapScreen.explore_fill(e) == MapScreen.FILL_DONE and not MapScreen.has_live_miniboss(e), "중간 보스를 쓰러뜨리면 2/2 하늘색, ☠ 사라짐")
	# 옛 저장 바로잡기
	Progress.reset()
	Progress.grasses["g_old"] = {"scene": "x", "name": "x"}
	Progress.visited_rooms["canopy_mini_1"] = {"offset": Vector2.ZERO, "size": Vector2(100, 100), "explore_ids": {"grasses": ["g_old"]}, "explore_total": 1, "explore_found": 1}
	Progress.visited_rooms["canopy_hidden"] = {"offset": Vector2.ZERO, "size": Vector2(100, 100), "explore_ids": ["read_x"], "explore_total": 1, "explore_found": 0}
	Progress.visited_rooms["canopy_01"] = {"offset": Vector2.ZERO, "size": Vector2(100, 100), "explore_ids": {"grasses": ["g_old"]}, "explore_total": 1, "explore_found": 1}
	var before := MapScreen.explore_counts(Progress.visited_rooms["canopy_mini_1"])
	var n := MapScreen.fix_saved_minibosses(Progress.visited_rooms)
	var after := MapScreen.explore_counts(Progress.visited_rooms["canopy_mini_1"])
	var hidden := MapScreen.explore_counts(Progress.visited_rooms["canopy_hidden"])
	var n2 := MapScreen.fix_saved_minibosses(Progress.visited_rooms)
	print("[지도시험] 옛 저장: canopy_mini_1 %s → %s, canopy_hidden(배열 형식) %s, 고친 방 %d, 두 번째 %d" % [before, after, hidden, n, n2])
	_check(_pair(before, 1, 1) and _pair(after, 1, 2) and int(Progress.visited_rooms["canopy_mini_1"]["explore_total"]) == 2, "옛 저장의 중간 보스 방: 1/1(모두 찾음) → 1/2(아직 남음)")
	_check(_pair(hidden, 0, 2) and n == 2 and n2 == 0, "배열 형식도 고치고, 두 번 고쳐도 늘지 않는다")
	_check(_pair(MapScreen.explore_counts(Progress.visited_rooms["canopy_01"]), 1, 1), "중간 보스 없는 방은 그대로")
	# 표 = 모든 MiniBossRoom
	var found := {}
	var dir := DirAccess.open("res://scenes/rooms")
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		var txt := FileAccess.get_file_as_string("res://scenes/rooms/" + f)
		if not txt.contains("miniboss_room.gd"):
			continue
		var flag := _root_prop(txt, "defeat_flag")
		if flag == "":
			flag = _script_default("res://scripts/world/miniboss_room.gd", "defeat_flag")
		found[_root_prop(txt, "room_id")] = flag
	print("[지도시험] 방 파일의 중간 보스 방: %s" % found)
	_check(found.size() == 6 and found == MapScreen.MINIBOSS_ROOMS, "MINIBOSS_ROOMS 표 = scenes/rooms 의 중간 보스 방 %d개 전부 (깃발까지 같음)" % found.size())
	# 실제 방: 들어가면 Room 이 중간 보스 깃발을 모은다 → 쓰러뜨리면(깃발) 찾은 수가 1 늘고, 다시 들어가도 그대로 센다
	for rid in ["canopy_mini_1", "canopy_hidden"]:
		Progress.reset()
		var flag: String = MapScreen.MINIBOSS_ROOMS[rid]
		var room: Node = load("res://scenes/rooms/%s.tscn" % rid).instantiate()
		add_child(room)
		await _frames(4)
		var entry: Dictionary = Progress.visited_rooms.get(rid, {})
		var ids: Dictionary = entry.get("explore_ids", {})
		var f0 := int(entry.get("explore_found", -1))
		var t0 := int(entry.get("explore_total", -1))
		Progress.set_flag(flag)   # 쓰러뜨림 (MiniBossRoom._on_boss_died 와 같은 깃발) → flag_changed → refresh_explore
		await _frames(1)
		var f1 := int(entry.get("explore_found", -1))
		print("[지도시험] %s 들어감: 중간 보스 %s, 탐사 %d/%d → 깃발 뒤 %d/%d" % [rid, ids.get("minibosses", []), f0, t0, f1, int(entry.get("explore_total", -1))])
		_check(ids.get("minibosses", []) == [flag] and f1 == f0 + 1 and int(entry.get("explore_total", -1)) == t0 and f0 < t0, "%s: 중간 보스가 탐사 요소 (쓰러뜨리기 전 %d/%d → 뒤 %d/%d)" % [rid, f0, t0, f1, t0])
		room.queue_free()
		await _frames(2)
		# 다시 들어가기: 보스는 이미 쓰러져 노드가 사라지지만 깃발은 그대로 센다
		var room2: Node = load("res://scenes/rooms/%s.tscn" % rid).instantiate()
		add_child(room2)
		await _frames(4)
		entry = Progress.visited_rooms.get(rid, {})
		var c2 := MapScreen.explore_counts(entry)
		_check(c2[1] == t0 and c2[0] == f1 and (entry.get("explore_ids", {}) as Dictionary).get("minibosses", []) == [flag], "%s 다시 들어가도 중간 보스를 센다 (%d/%d)" % [rid, c2[0], c2[1]])
		room2.queue_free()
		await _frames(2)
	get_tree().paused = false


func _root_prop(txt: String, key: String) -> String:
	var head := txt.substr(0, txt.find('[node name="WorldEnvironment"'))
	var re := RegEx.create_from_string("(?m)^%s = (.+)$" % key)
	var m := re.search(head)
	return m.get_string(1).trim_prefix("\"").trim_suffix("\"") if m else ""


func _script_default(path: String, key: String) -> String:
	var re := RegEx.create_from_string('(?m)^@export var %s := "([^"]*)"' % key)
	var m := re.search(FileAccess.get_file_as_string(path))
	return m.get_string(1) if m else ""


func _vec2(s: String) -> Vector2:
	var re := RegEx.create_from_string("Vector2\\(([-\\d.]+), ([-\\d.]+)\\)")
	var m := re.search(s)
	return Vector2(float(m.get_string(1)), float(m.get_string(2))) if m else Vector2.ZERO


func _rect(s: String) -> Rect2:
	var re := RegEx.create_from_string("Rect2\\(([-\\d.]+), ([-\\d.]+), ([-\\d.]+), ([-\\d.]+)\\)")
	var m := re.search(s)
	return Rect2(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)), float(m.get_string(4))) if m else Rect2()

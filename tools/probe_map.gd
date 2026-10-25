extends Node
## 지도 시험(headless). 실행: godot --headless --path . res://tools/probe_map_scene.tscn
##   창으로 돌리면(--headless 없이) screenshots/debug_map_open.png / debug_map_zoomed_out.png 도 남긴다 (눈 확인용).
## 1) 색칠: 가짜 방 데이터에 explore_total/explore_found(또는 explore_ids)를 넣어 지도를 몇 프레임 그려 보고
##    오류 없이 그려지는지(실제 draw 호출 수), 색 판정 규칙(v1.1.0: 남음=하늘색, 다 찾음=초록)이 MapScreen 의 함수 기준으로 맞는지.
## 2) 확대·이동 (2026-10-19): scenes/rooms 의 모든 방(41개)을 가 본 것으로 치고 연다 →
##    열 때 지금 방이 가운데·배율 ZOOM_OPEN, 배율 막기(최대 ZOOM_MAX / 최소 = 전체가 한눈에), 가운데 막기(범위 밖으로 못 감),
##    커서 자리 고정 확대, 터치 한 손가락 끌기·두 손가락 벌리기·두 번 누르기(처음대로)·✕(닫기), 화면 가운데 한 번 누르기는 닫지 않음.
## 3) 중간 보스 집계: 중간 보스 깃발이 탐사 요소로 세어지고(쓰러뜨려야 '모두 찾음'), 옛 저장을 바로잡으며(fix_saved_minibosses, 두 번 해도 같음),
##    MINIBOSS_ROOMS 표가 scenes/rooms 의 MiniBossRoom 전부와 같고, 실제 방(canopy_mini_1·canopy_hidden)을 띄우면 Room 이 깃발을 모으는지.
## 4) v1.1.0 (기획자 요청 21~25): 방 목록(RoomIndex) = 방 파일, 색 맞바꿈, 0/0 초록, 보스 방(정화 전 하늘색·뒤 초록, 해골 옅게),
##    금 간 벽 집계(옛 저장도), 경전 번호(읽은 것만), 포탈 화살표(개수·방향·잠김·가 봄), 짝 실선, 숨은 포탈, 포탈 안내의 목적지 이름,
##    달빛풀 이동 목록 이름 = 지도 방 이름 (달빛풀 전부). 창으로 돌리면 debug_map_v110_*.png / debug_travel_menu.png 도 남긴다.
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
	await _test_v110()
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
		var color := "초록" if fill == MapScreen.FILL_DONE else ("하늘색" if fill == MapScreen.FILL_REMAIN else "???")
		print("[지도시험] %s: %d/%d → %s" % [id, counts[0], counts[1], color])
	_check(MapScreen.explore_fill(Progress.visited_rooms["a"]) == MapScreen.FILL_REMAIN, "a 1/3 → 하늘색 (남음)")
	_check(MapScreen.explore_fill(Progress.visited_rooms["b"]) == MapScreen.FILL_DONE, "b 2/2 → 초록 (모두 찾음)")
	_check(MapScreen.explore_fill(Progress.visited_rooms["c"]) == MapScreen.FILL_DONE, "c 값 없음(0/0) → 초록")
	_check(MapScreen.explore_fill(Progress.visited_rooms["d"]) == MapScreen.FILL_REMAIN, "d 1/2 → 하늘색 (남음)")
	Progress.grasses["test_grass"] = {"scene": "x", "name": "시험"}
	var d_after := MapScreen.explore_counts(Progress.visited_rooms["d"])
	_check(MapScreen.explore_fill(Progress.visited_rooms["d"]) == MapScreen.FILL_DONE, "d 달빛풀 피운 뒤 %d/%d → 초록" % [d_after[0], d_after[1]])
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
	_check(_pair(c, 1, 2) and MapScreen.explore_fill(e) == MapScreen.FILL_REMAIN and MapScreen.has_live_miniboss(e), "달빛풀은 찾았어도 중간 보스가 남으면 1/2 하늘색 + 작은 ☠")
	Progress.set_flag("miniboss_test")
	c = MapScreen.explore_counts(e)
	_check(_pair(c, 2, 2) and MapScreen.explore_fill(e) == MapScreen.FILL_DONE and not MapScreen.has_live_miniboss(e), "중간 보스를 쓰러뜨리면 2/2 초록, ☠ 사라짐")
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


# ───────── 4) v1.1.0: 방 목록·색·보스·금 간 벽·경전 번호·포탈 화살표·이동 이름 ─────────
func _test_v110() -> void:
	Progress.reset()
	RoomIndex.reload()
	await _v110_index()
	await _v110_colors()
	await _v110_rooms_explore()
	await _v110_scriptures()
	await _v110_arrows()
	await _v110_travel_names()
	await _v110_portal_prompt()
	await _v110_draw_all()
	Progress.reset()
	get_tree().paused = false


## 방 목록(data/map/rooms_index.json)이 방 파일과 맞는가
func _v110_index() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(RoomIndex.PATH))
	_check(data is Dictionary and data.get("region_labels", {}) == RoomIndex.REGION_LABEL, "방 목록의 지역 이름 = RoomIndex.REGION_LABEL")
	var files := 0
	var names_ok := true
	var bosses := {}
	var dir := DirAccess.open("res://scenes/rooms")
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		files += 1
		var txt := FileAccess.get_file_as_string("res://scenes/rooms/" + f)
		var rid := f.get_basename()
		var dn := _root_prop(txt, "display_name")
		if not RoomIndex.has_room(rid) or (dn != "" and RoomIndex.room_name(rid) != dn):
			names_ok = false
			print("[지도시험]   방 목록과 다름: %s ('%s' / '%s')" % [rid, dn, RoomIndex.room_name(rid)])
		if txt.contains("scripts/bosses/boss_room.gd") or txt.contains("scripts/bosses/iron_pump_room.gd"):
			var flag := _root_prop(txt, "defeat_flag")
			bosses[rid] = flag if flag != "" else _script_default("res://scripts/bosses/boss_room.gd", "defeat_flag")
	_check(RoomIndex.room_ids().size() == files and names_ok, "방 목록 = 방 파일 %d개 (이름까지)" % files)
	_check(bosses == MapScreen.BOSS_ROOMS, "BOSS_ROOMS 표 = scenes/rooms 의 보스 방 전부 (%s)" % bosses)
	var r01 := RoomIndex.room_rect("canopy_01")
	_check(r01 == Rect2(0, -420, 4800, 2750), "지도 칸 = map_offset + bounds.position (canopy_01 %s, 경계가 위로 420 넓다)" % r01)
	var want := {1: "canopy_hidden_2", 2: "village_hidden_1", 3: "mine_hidden_2", 4: "abyss_hidden_1"}
	var got := {}
	for n in want:
		got[n] = RoomIndex.scripture_room(n)
	_check(got == want, "경전 조각 방: %s" % got)


func _v110_colors() -> void:
	_check(MapScreen.FILL_DONE == Color(0.62, 0.92, 0.45) and MapScreen.FILL_REMAIN == Color(0.45, 0.82, 1.0), "색 맞바꿈: 모두 찾음 = 초록, 남음 = 하늘색")
	_check(MapScreen.GRASS_DOT == Color(1.0, 0.96, 0.78), "달빛풀 점 = 달빛 흰빛")
	# 0/0: 가 본 숨은 내리막 (탐사 요소 없음) → 초록
	var e := {"offset": Vector2.ZERO, "size": Vector2(100, 100), "explore_ids": {"pickups": [], "rescues": [], "records": [], "grasses": [], "minibosses": []}}
	var c := MapScreen.explore_counts(e, "hidden_descent")
	_check(_pair(c, 0, 0) and MapScreen.explore_fill(e, "hidden_descent") == MapScreen.FILL_DONE, "0/0 인 방은 가 보면 초록 (%s)" % [c])
	# 보스 방: 옛 저장(목록에 보스 없음)도 표로 센다 — 정화 전 하늘색, 뒤 초록
	Progress.grasses["canopy_boss_gate"] = {"scene": "x", "name": "x"}
	var b := {"offset": Vector2.ZERO, "size": Vector2(100, 100), "boss": true, "explore_ids": {"grasses": ["canopy_boss_gate"]}}
	var c0 := MapScreen.explore_counts(b, "canopy_boss")
	var fill0 := MapScreen.explore_fill(b, "canopy_boss")
	Progress.set_flag("boss_bird_defeated")
	var c1 := MapScreen.explore_counts(b, "canopy_boss")
	_check(_pair(c0, 1, 2) and fill0 == MapScreen.FILL_REMAIN and _pair(c1, 2, 2) and MapScreen.explore_fill(b, "canopy_boss") == MapScreen.FILL_DONE,
		"보스 방(옛 저장): 달빛풀만 찾음 %s 하늘색 → 보스 정화 뒤 %s 초록" % [c0, c1])
	# 금 간 벽: 옛 저장(목록에 벽 없음)도 방 목록으로 센다
	Progress.reset()
	Progress.grasses["canopy_wind"] = {"scene": "x", "name": "x"}
	var w := {"offset": Vector2.ZERO, "size": Vector2(100, 100), "explore_ids": {"grasses": ["canopy_wind"]}}
	var w0 := MapScreen.explore_counts(w, "canopy_02")
	Progress.collect("cracked_canopy_02_1")
	var w1 := MapScreen.explore_counts(w, "canopy_02")
	_check(_pair(w0, 1, 2) and _pair(w1, 2, 2), "금 간 벽(옛 저장): 부수기 전 %s → 부순 뒤 %s" % [w0, w1])
	# 정수만 있는 아주 옛 저장에도 보스를 더한다
	Progress.reset()
	var old := {"offset": Vector2.ZERO, "size": Vector2(100, 100), "explore_total": 1, "explore_found": 1}
	_check(_pair(MapScreen.explore_counts(old, "mine_boss"), 1, 2), "정수만 있는 옛 저장의 보스 방도 보스를 센다 (%s)" % [MapScreen.explore_counts(old, "mine_boss")])


## 실제 방에 들어가 Room 이 보스·금 간 벽을 탐사 요소로 모으는가
func _v110_rooms_explore() -> void:
	for rid in ["canopy_boss", "canopy_02"]:
		Progress.reset()
		var room: Node = load("res://scenes/rooms/%s.tscn" % rid).instantiate()
		add_child(room)
		await _frames(4)
		var entry: Dictionary = Progress.visited_rooms.get(rid, {})
		var ids: Dictionary = entry.get("explore_ids", {})
		var t0 := int(entry.get("explore_total", -1))
		var f0 := int(entry.get("explore_found", -1))
		if rid == "canopy_boss":
			Progress.set_flag("boss_bird_defeated")
		else:
			Progress.collect("cracked_canopy_02_1")
		await _frames(1)
		var f1 := int(entry.get("explore_found", -1))
		var map_c := MapScreen.explore_counts(entry, rid)
		var key := "bosses" if rid == "canopy_boss" else "walls"
		var want_id := "boss_bird_defeated" if rid == "canopy_boss" else "cracked_canopy_02_1"
		print("[지도시험] %s 들어감: %s %s, 탐사 %d/%d → %d/%d (지도 %s)" % [rid, key, ids.get(key, []), f0, t0, f1, t0, map_c])
		_check(ids.get(key, []) == [want_id] and f1 == f0 + 1 and map_c[1] == t0 and map_c[0] == f1, "%s: %s 가 탐사 요소 (%d/%d → %d/%d, 지도도 같은 수)" % [rid, want_id, f0, t0, f1, t0])
		room.queue_free()
		await _frames(2)


func _v110_scriptures() -> void:
	Progress.reset()
	var map := MapScreen.new()
	add_child(map)
	await get_tree().process_frame
	for rid in ["canopy_hidden_2", "village_hidden_1", "canopy_01"]:
		var rect := RoomIndex.room_rect(rid)
		Progress.visited_rooms[rid] = {"offset": RoomIndex.room_offset(rid), "size": rect.size, "name": "옛 이름", "region": "canopy", "grasses": [], "portals": [], "boss": false}
	map.open(null)
	await _frames(2)
	var none: bool = map.card_of("canopy_hidden_2")["scriptures"].is_empty() and map.card_of("village_hidden_1")["scriptures"].is_empty()
	map.close()
	Progress.set_flag("read_scripture_2")
	map.open(null)
	await _frames(2)
	var c1: Array = map.card_of("canopy_hidden_2")["scriptures"]
	var c2: Array = map.card_of("village_hidden_1")["scriptures"]
	var c3: Array = map.card_of("canopy_01")["scriptures"]
	var nm: String = map.card_of("canopy_hidden_2")["name"]
	map.close()
	_check(none and c1.is_empty() and c2 == [2] and c3.is_empty(), "경전 번호: 읽기 전 없음 → 2번만 읽으면 마을 다락에 ✦2 (수관 갈라진 가지 %s, 다락 %s)" % [c1, c2])
	_check(nm == RoomIndex.room_name("canopy_hidden_2") and nm != "옛 이름", "지도 방 이름은 방 목록 이름 ('%s' — 저장된 옛 이름이 아님)" % nm)
	map.queue_free()
	await _frames(1)


## 지금 화면에서 ray(시작 p, 방향 d)가 사각형 r 에 닿는가 (slab)
func _ray_hits(p: Vector2, d: Vector2, r: Rect2) -> bool:
	var tmin := 0.0
	var tmax := 1e9
	for a in 2:
		if absf(d[a]) < 1e-6:
			if p[a] < r.position[a] or p[a] > r.end[a]:
				return false
		else:
			var t1 := (r.position[a] - p[a]) / d[a]
			var t2 := (r.end[a] - p[a]) / d[a]
			tmin = maxf(tmin, minf(t1, t2))
			tmax = minf(tmax, maxf(t1, t2))
	return tmax >= tmin


func _v110_arrows() -> void:
	Progress.reset()
	var ids := _visit_all_rooms()
	var map := MapScreen.new()
	add_child(map)
	await get_tree().process_frame
	map.open(null)
	await _frames(2)
	var want := 0
	var hidden := 0
	for rid in ids:
		for p in RoomIndex.portals(rid):
			if bool(p.get("hidden", false)):
				hidden += 1
			else:
				want += 1
	var got := 0
	var bad_dir: Array = []
	var locked := 0
	var not_visited := 0
	for rid in ids:
		var card: Dictionary = map.card_of(rid)
		for pm in card.get("portals", []):
			got += 1
			var to: String = pm["to"]
			if pm["dir"] == Vector2.ZERO or not _ray_hits(pm["pos"], pm["dir"], RoomIndex.room_rect(to).grow(40.0)):
				bad_dir.append("%s→%s" % [rid, to])
			if pm["state"] == MapScreen.Link.LOCKED:
				locked += 1
			elif pm["state"] == MapScreen.Link.UNVISITED:
				not_visited += 1
	print("[지도시험] 화살표: 포탈 %d (숨은 %d 빼고 %d), 방향 어긋남 %s, 잠김 %d, 안 가 봄 %d, 짝 실선 %d" % [got, hidden, want, bad_dir, locked, not_visited, map.link_count()])
	_check(got == want and want > 60, "모든 방을 가 봤을 때 ◆ 마다 화살표 하나 (%d개, 드러나지 않은 숨은 포탈 %d 빼고)" % [got, hidden])
	_check(bad_dir.is_empty(), "화살표가 모두 목적지 방 쪽을 가리킨다 (어긋남 %s)" % [bad_dir])
	var req := 0
	for rid in ids:
		for p in RoomIndex.portals(rid):
			if str(p.get("requires", "")) != "" and not bool(p.get("hidden", false)):
				req += 1
	_check(locked == req and req > 0 and not_visited == 0, "능력이 없으면 잠긴 포탈 %d개는 회색, 나머지는 모두 '가 본 방' (안 가 봄 %d)" % [locked, not_visited])
	# 예: 잠긴 채굴장으로 가는 ◆ 는 잠긴 채굴장 쪽 (방 배치가 바뀌어도 '그쪽으로 가는 포탈'을 찾아 본다)
	var flooded: Array = []
	for rid in ids:
		for pm in map.card_of(rid).get("portals", []):
			if pm["to"] == "flooded_mine_01":
				var target: Vector2 = RoomIndex.room_rect("flooded_mine_01").get_center()
				flooded.append("%s %s" % [rid, "→" if pm["dir"].dot((target - pm["pos"]).normalized()) > 0.5 else "✗"])
	_check(not flooded.is_empty() and not str(flooded).contains("✗"), "잠긴 채굴장으로 가는 ◆ 의 화살표: %s" % [flooded])
	# 짝 실선: 숨은 포탈 짝을 뺀 나머지 모두 (포탈 두 개가 한 쌍)
	_check(map.link_count() * 2 >= want - hidden * 2 and map.link_count() > 30, "두 방을 다 가 봤으면 짝 ◆ 사이 실선 (%d개)" % map.link_count())
	# 붙어 있는 짝 ◆ (방 경계를 사이에 둔 짝): 마주 보는 두 화살표가 포개지지 않는다 — 열 때 배율(×100%)과 가장 크게(×300%)
	for z in [MapScreen.ZOOM_OPEN, MapScreen.ZOOM_MAX]:
		map._zoom = z
		var sep := _arrow_separation(map, ids)
		_check(sep["pairs"] > 30 and sep["bad"].is_empty() and (z != MapScreen.ZOOM_OPEN or sep["close"] > 0),
			"배율 %.2f: 짝 화살표 %d쌍(가까워 비킨 짝 %d) 모두 화면 거리 ≥ %.0fpx, 짝 ◆ 와도 떨어짐 (가장 가까운 화살표 사이 %.1fpx, 화살표↔짝 ◆ %.1fpx, 어긋남 %s)" % [z, sep["pairs"], sep["close"], MapScreen.ARROW_LEN, sep["min_sep"], sep["min_diamond"], sep["bad"]])
	map.reset_view()
	# 찾은 수 글자는 포탈·화살표 표식을 피한다 (예: 관의 복도 오른쪽 아래 ◆ 와 등불 잠긴 길 ◆ 가 세로로 붙어 있다)
	var overlap := _count_overlaps(map, ids)
	_check(overlap.is_empty(), "찾은 수 글자가 달빛풀·포탈·화살표를 덮지 않는다 (겹친 방 %s)" % [overlap])
	map.close()
	# 숨은 포탈: 스냅숏에 들어가야(드러나야) 보인다
	var hp: Dictionary = {}
	for p in RoomIndex.portals("village_02"):
		if bool(p.get("hidden", false)):
			hp = p
	var before: int = map.card_of("village_02")["portals"].size()
	Progress.visited_rooms["village_02"]["portals"] = [Vector2(float(hp["pos"][0]), float(hp["pos"][1]))]
	map.open(null)
	await _frames(1)
	var after_n: int = map.card_of("village_02")["portals"].size()
	map.close()
	_check(not hp.is_empty() and after_n == before + 1, "숨은 포탈(마을 틈)은 드러나 지도 기록에 들어간 뒤에만 ◆ (%d → %d)" % [before, after_n])
	# 두 방만 가 본 경우: 실선 1, 화살표 상태 (가 본 방 금빛 / 안 가 본 방 테두리)
	Progress.reset()
	for rid in ["canopy_01", "canopy_02"]:
		var rect := RoomIndex.room_rect(rid)
		Progress.visited_rooms[rid] = {"offset": RoomIndex.room_offset(rid), "size": rect.size, "name": rid, "region": "canopy", "grasses": [], "portals": [], "boss": false}
	map.open(null)
	await _frames(1)
	var st := {}
	for pm in map.card_of("canopy_01")["portals"]:
		st[pm["to"]] = pm["state"]
	var links := map.link_count()
	map.close()
	_check(links == 1 and st.get("canopy_02", -1) == MapScreen.Link.VISITED and st.get("canopy_hidden", -1) == MapScreen.Link.UNVISITED,
		"두 방만 가 봄: 실선 %d, 수관 시작의 가지 ◆→바람의 틈 금빛 %s, ◆→잿가지의 둥지 테두리 %s" % [links, st.get("canopy_02", -1) == MapScreen.Link.VISITED, st.get("canopy_hidden", -1) == MapScreen.Link.UNVISITED])
	map.queue_free()
	await _frames(1)


## 지금 배율에서 짝 ◆ 두 화살표의 화면 거리: {pairs, close(비킨 짝 수), bad:[...], min_sep, min_diamond}
func _arrow_separation(map: MapScreen, ids: Array) -> Dictionary:
	var mk := clampf(map._zoom / MapScreen.ZOOM_OPEN, 0.55, 1.2)
	var d := 9.0 * mk
	var marks := {}   # 세계 점(글자) -> 화살표 자료
	for rid in ids:
		for pm in map.card_of(rid).get("portals", []):
			marks[str(pm["pos"])] = pm
	var out := {"pairs": 0, "close": 0, "bad": [], "min_sep": INF, "min_diamond": INF}
	for key in marks:
		var a: Dictionary = marks[key]
		if not a.has("pair") or a["dir"] == Vector2.ZERO:
			continue
		var b = marks.get(str(a["pair"]))
		if b == null or b["dir"] == Vector2.ZERO or str(a["pos"]) > str(b["pos"]):
			continue   # 한 쌍은 한 번만
		out["pairs"] += 1
		var ca := map.world_to_view(a["pos"])
		var cb := map.world_to_view(b["pos"])
		var need := 2.0 * (d + MapScreen.ARROW_GAP + MapScreen.ARROW_LEN * 0.55) + 4.0
		if ca.distance_to(cb) < need:
			out["close"] += 1
		var aa := map.arrow_center(ca, d, a)
		var ab := map.arrow_center(cb, d, b)
		var sep := aa.distance_to(ab)
		var dia := minf(aa.distance_to(cb), ab.distance_to(ca))
		out["min_sep"] = minf(out["min_sep"], sep)
		out["min_diamond"] = minf(out["min_diamond"], dia)
		# 화살표 사이가 화살표 길이보다 가깝거나, 화살표 가운데가 짝 ◆(반지름 d, 빛 테 +4) 안이면 어긋남
		if sep < MapScreen.ARROW_LEN or dia < d + 4.0:
			out["bad"].append("%s (%.0fpx, ◆ %.0fpx)" % [key, sep, dia])
	return out


## 지금 배율에서 찾은 수 글자 네모가 그 방의 표식(달빛풀·포탈·화살표)과 겹치는 방 (그리기와 같은 자리 규칙: count_box_at)
func _count_overlaps(map: MapScreen, ids: Array) -> Array:
	var mk := clampf(map._zoom / MapScreen.ZOOM_OPEN, 0.55, 1.2)
	var d := 9.0 * mk
	var font := ThemeDB.fallback_font
	var out: Array = []
	for rid in ids:
		var card: Dictionary = map.card_of(rid)
		if card.is_empty() or int(card["total"]) <= 0:
			continue
		var rect := Rect2(map.world_to_view(card["rect"].position), card["rect"].size * map._zoom)
		var cw := font.get_string_size(card["count_text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		if rect.size.x < cw + 22.0 or rect.size.y < 24.0:
			continue
		map._marks.clear()
		for g in card["grasses"]:
			map._marks.append(map.world_to_view(g))
		for pm in card["portals"]:
			var c := map.world_to_view(pm["pos"])
			map._marks.append(c)
			if pm["dir"] != Vector2.ZERO:
				map._marks.append(map.arrow_center(c, d, pm))
		var box := map.count_box_at(rect, cw)
		for m in map._marks:
			if box.grow(10.0).has_point(m):
				out.append("%s %s" % [rid, card["count_text"]])
				break
	map._marks.clear()
	return out


## 달빛풀 이동 목록 이름 = 그 달빛풀이 있는 방의 지도 이름 (달빛풀 전부, 옛 저장 이름은 무시)
func _v110_travel_names() -> void:
	Progress.reset()
	var all := {}
	for rid in RoomIndex.room_ids():
		for g in RoomIndex.room(rid).get("grasses", []):
			if not bool(g.get("decor", false)) and str(g.get("id", "")) != "":
				all[str(g["id"])] = rid
				Progress.grasses[str(g["id"])] = {"scene": "res://scenes/rooms/%s.tscn" % rid, "name": "옛 이름 " + str(g["id"])}
	var menu := TravelMenu.new()
	add_child(menu)
	await get_tree().process_frame
	menu.open("canopy_start")
	await _frames(2)
	var bad: Array = []
	for it in menu._items:
		var rid: String = all.get(it["id"], "")
		if rid == "" or it["name"] != RoomIndex.room_name(rid) or it["region"] != RoomIndex.region_of(rid) or it["scene"] != "res://scenes/rooms/%s.tscn" % rid:
			bad.append("%s: '%s'" % [it["id"], it["name"]])
	_check(menu._items.size() == all.size() and all.size() >= 22 and bad.is_empty(), "이동 목록 %d줄 = 달빛풀 %d개, 이름 = 지도 방 이름 (어긋남 %s)" % [menu._items.size(), all.size(), bad])
	var regions := {}
	for it in menu._items:
		regions[RoomIndex.region_label(it["region"])] = true
	_check(regions.has("수액의 호수") and regions.has("잠긴 채굴장") and regions.has("심연"), "지역 칸 = 지도 지역 이름 (%s)" % [regions.keys()])
	if DisplayServer.get_name() != "headless":
		await _frames(3)
		_shot("debug_travel_menu.png")
	menu.close()
	menu.queue_free()
	await _frames(1)
	get_tree().paused = false


## 포탈 안내: '들어가기 → 목적지 이름' (가 본 방이면 지도 이름, 아니면 ???)
func _v110_portal_prompt() -> void:
	Progress.reset()
	var room: Room = load("res://scenes/rooms/canopy_01.tscn").instantiate()
	add_child(room)
	await _frames(4)
	var portal: Portal = null
	for p in get_tree().get_nodes_in_group("portal"):
		if room.is_ancestor_of(p) and p.destination_id() == "canopy_02":
			portal = p
	if portal == null:
		_check(false, "canopy_01 → canopy_02 포탈이 없다")
		room.queue_free()
		return
	room.player._invuln_timer = 9999.0
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	room.player.global_position = portal.global_position + Vector2(-30, -70)
	await _physics_frames(8)
	var t0: String = portal._prompt.text
	room.player.global_position = portal.global_position + Vector2(-900, -70)
	await _physics_frames(4)
	Progress.visited_rooms["canopy_02"] = {"offset": Vector2.ZERO, "size": Vector2(10, 10), "name": "옛 이름"}
	room.player.global_position = portal.global_position + Vector2(-30, -70)
	await _physics_frames(8)
	var t1: String = portal._prompt.text
	if DisplayServer.get_name() != "headless":
		await _frames(30)
		_shot("debug_portal_prompt.png")
	_check(t0.ends_with("들어가기 → ???") and t1.ends_with("들어가기 → " + RoomIndex.room_name("canopy_02")), "포탈 안내: 안 가 본 방 '%s' → 가 본 방 '%s'" % [t0, t1])
	room.queue_free()
	await _frames(2)


func _physics_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 모든 방을 가 보고 경전·보스·벽을 섞은 지도를 그려 본다 (오류 없이). 창으로 돌리면 스크린샷.
func _v110_draw_all() -> void:
	Progress.reset()
	var ids := _visit_all_rooms()
	Progress.set_flag("read_scripture_1")
	Progress.set_flag("read_scripture_3")
	Progress.set_flag("boss_bird_defeated")
	Progress.collect("cracked_canopy_02_1")
	Progress.gain_ability("lantern")
	var fake := Room.new()
	fake.room_id = "mine_02"
	var map := MapScreen.new()
	add_child(map)
	await get_tree().process_frame
	map.open(fake)
	_draws = 0
	map._view.draw.connect(func() -> void: _draws += 1)
	await _frames(4)
	_check(_draws >= 3, "모든 방 + 경전·보스·벽·화살표를 그려도 오류 없음 (draw %d)" % _draws)
	_check(map.card_of("canopy_boss")["boss_down"] and map.card_of("mine_hidden_2")["scriptures"] == [3], "정화한 보스 방은 해골 옅게(+✓), 막힌 관에 ✦3")
	if DisplayServer.get_name() != "headless":
		map.zoom_at(map._view.position + map.view_size() / 2.0, 2.2)
		await _frames(4)
		_shot("debug_map_v110_mine_zoomed.png")
		map.reset_view()
		map._center = RoomIndex.room_rect("canopy_02").get_center()
		map._clamp_view()
		await _frames(4)
		_shot("debug_map_v110_canopy.png")
		map.zoom_at(map._view.position + map.view_size() / 2.0, 0.001)
		await _frames(4)
		_shot("debug_map_v110_all.png")
	map.close()
	map.queue_free()
	fake.free()
	await _frames(1)


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

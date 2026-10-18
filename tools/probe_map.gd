extends Node
## 지도 색칠 시험(headless). 가짜 방 데이터에 explore_total/explore_found(또는 explore_ids)를 넣어 지도를 몇 프레임 그려 보고
## 오류 없이 그려지는지(실제 draw 호출 수), 색 판정 규칙(남음=연초록, 다 찾음=하늘색)이 MapScreen 의 함수 기준으로 맞는지 확인한다.
## 자동 로드(Progress 등)가 필요해서 -s 가 아니라 씬으로 돌린다:
##   godot --headless --path . res://tools/probe_map_scene.tscn

var _draws := 0


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ok := true
	Progress.visited_rooms.clear()
	Progress.flags.clear()
	Progress.grasses.clear()
	Progress.visited_rooms["a"] = {"offset": Vector2(0, 0), "size": Vector2(2000, 1000), "name": "남음", "region": "canopy", "grasses": [Vector2(100, 100)], "portals": [Vector2(1900, 900)], "boss": false, "explore_total": 3, "explore_found": 1}
	Progress.visited_rooms["b"] = {"offset": Vector2(2000, 0), "size": Vector2(2000, 1000), "name": "다찾음", "region": "village", "grasses": [], "portals": [], "boss": true, "explore_total": 2, "explore_found": 2}
	Progress.visited_rooms["c"] = {"offset": Vector2(0, 1000), "size": Vector2(2000, 1000), "name": "값없음", "region": "mine", "grasses": [], "boss": false}
	# id 목록 방식: 깃발 하나·달빛풀 하나 중 깃발만 찾은 상태 → 1/2 연초록, 달빛풀도 피우면 2/2 하늘색
	Progress.visited_rooms["d"] = {"offset": Vector2(2000, 1000), "size": Vector2(2000, 1000), "name": "목록", "region": "abyss", "grasses": [], "boss": false, "explore_ids": ["read_test_record", "grass:test_grass"]}
	Progress.set_flag("read_test_record")
	var map := MapScreen.new()
	add_child(map)
	await get_tree().process_frame
	map._panel.draw.connect(func() -> void: _draws += 1)
	map.open(null)
	# 몇 프레임 그려서 _on_draw 가 오류 없이 도는지 (오류가 나면 SCRIPT ERROR 줄이 찍힌다)
	for i in 5:
		await get_tree().process_frame
	map.close()
	print("[지도시험] draw 호출 수: %d" % _draws)
	if _draws < 5:
		ok = false
	# 색 판정 규칙: MapScreen 의 함수로 확인
	for id in Progress.visited_rooms:
		var r: Dictionary = Progress.visited_rooms[id]
		var counts := MapScreen.explore_counts(r)
		var fill := MapScreen.explore_fill(r)
		var color := "하늘색" if fill == MapScreen.FILL_DONE else ("연초록" if fill == MapScreen.FILL_REMAIN else "???")
		print("[지도시험] %s: %d/%d → %s" % [id, counts[0], counts[1], color])
	if MapScreen.explore_fill(Progress.visited_rooms["a"]) != MapScreen.FILL_REMAIN: ok = false
	if MapScreen.explore_fill(Progress.visited_rooms["b"]) != MapScreen.FILL_DONE: ok = false
	if MapScreen.explore_fill(Progress.visited_rooms["c"]) != MapScreen.FILL_DONE: ok = false
	if MapScreen.explore_fill(Progress.visited_rooms["d"]) != MapScreen.FILL_REMAIN: ok = false
	Progress.grasses["test_grass"] = {"scene": "x", "name": "시험"}
	var d_after := MapScreen.explore_counts(Progress.visited_rooms["d"])
	print("[지도시험] d (달빛풀 피운 뒤): %d/%d → %s" % [d_after[0], d_after[1], "하늘색" if MapScreen.explore_fill(Progress.visited_rooms["d"]) == MapScreen.FILL_DONE else "연초록"])
	if MapScreen.explore_fill(Progress.visited_rooms["d"]) != MapScreen.FILL_DONE: ok = false
	if MapScreen.FILL_REMAIN == MapScreen.FILL_DONE: ok = false
	if MapScreen.REGION_COLORS.size() != 4: ok = false
	print("[지도시험] 결과: %s" % ("통과" if ok else "실패"))
	get_tree().quit(0 if ok else 1)

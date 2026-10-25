extends Node
## v1.1.0 W2 레벨·엔딩 시험 (화면 없이 돈다). 방을 통째로 띄우고 소녀·포탈·장치를 손으로 돌린다.
## 실행: godot --headless --path . res://tools/probe_world_v110.tscn          (끝줄 "[probe] 끝: 실패 N")
##       godot --path . res://tools/probe_world_v110.tscn -- --shots [--out=/절대/경로]   (창이 뜨고 눈 확인용 스크린샷을 찍는다)
##  1) 무쇠 펌프 던전을 초반으로 (요청 20): 관의 복도(mine_02) ToFlooded ↔ 잠긴 채굴장(flooded_mine_01) FromMine02 왕복,
##     잠긴 채굴장 → 책임자의 방 지름길(ToMineDeep)은 등불이 있어야 열림, 책임자의 방 쪽 문은 조건 없음
##  2) 새만 잡은 상태(이단 점프·바람)로 mine_02 → 펌프 방까지: 문 조건 없음, 얕은 수액에서 피해 0·느려짐 0.85 (깊은 수액은 그대로 깎임)
##  3) 엔딩 장치 방 (요청 28): abyss_boss ↔ abyss_ending 왕복, 정화 전 장치 숨김·뒤 깨어남, 뿌리지기 방에는 진엔딩 장치(third) 하나
##  4) 진엔딩 조건 (요청 27): 경전 조각이 모자라면 보이되 꺼짐(잿빛·회전 멈춤·손길 거절·안내 n/4), 네 장 읽으면 그 자리에서 깨어남
##  5) 정원 끝의 비석 (요청 26): 달빛 정원 x 2180, 글·네 조각을 다 읽으면 더해지는 줄, 탐사 수에 들어감
##  6) 입구 찾기 (요청 19): 마을 틈이 크고 진하다, 등불 없이도 700 안 청록 맥동·400 안 '본 것'(깃발·지도 ◆·잠긴 포탈), 들어가기는 등불,
##     관의 복도 펌프실 표지·등불 기둥, 티아·오웬의 힌트 대사
##  7) 그림: 장치 세 개의 새 그림 조각, 제3의 길 물레방아가 진짜로 돈다, 뿌리지기 방 배경의 흐린 물레방아(Far 와 Shafts 사이, 돈다, 밉맵 흐림)
## 진짜 장면 바꾸기는 막아 둔다(Game._busy) — 포탈은 '어디로 가려 하는지'(Progress.next_spawn)만 보고, 그 방을 그 등장 자리로 다시 띄운다.

var _fail := 0
var _room: Node = null
var _player: Player = null
var _shots := false
var _out := ""
var _busy_was := false


func _ready() -> void:
	_shots = "--shots" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	_out = ProjectSettings.globalize_path("res://screenshots")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	print("[probe] v1.1.0 W2 레벨·엔딩 시험 시작 (스크린샷 %s)" % _shots)
	_busy_was = Game._busy
	Game._busy = true   # 포탈이 진짜로 장면을 바꾸지 않게
	if _shots:
		await _take_shots()
	else:
		await _probe_static_links()
		await _probe_flooded_route()
		await _probe_shallow_sap()
		await _probe_ending_rooms()
		await _probe_third_lock()
		await _probe_stone()
		await _probe_hidden_portal()
		await _probe_hints()
		await _probe_art()
	await _close()
	Game._busy = _busy_was
	Progress.reset()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


# ---------- 방 띄우기 / 치우기 ----------
func _open(room_id: String, spawn: String) -> void:
	await _close()
	Progress.next_spawn = spawn
	_room = load("res://scenes/rooms/%s.tscn" % room_id).instantiate()
	add_child(_room)
	for i in 3:
		await get_tree().physics_frame
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player:
		_player._invuln_timer = 9999.0
	for i in 6:
		await get_tree().physics_frame


func _close() -> void:
	if _room:
		_room.queue_free()
		_room = null
		_player = null
		for i in 3:
			await get_tree().process_frame


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


func _place(at: Vector2) -> void:
	_player.global_position = at
	_player.velocity = Vector2.ZERO
	var cam := _player.get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.reset_smoothing()


func _kill_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()


## 방 장면 파일에서 노드 하나의 속성들 (장면을 띄우지 않고 SceneState 로 본다). 없으면 {"_missing": true}
func _props(room_id: String, node_path: String) -> Dictionary:
	var ps: PackedScene = load("res://scenes/rooms/%s.tscn" % room_id)
	var st := ps.get_state()
	for i in st.get_node_count():
		var p := str(st.get_node_path(i)).trim_prefix("./")
		if p == ".":
			p = ""
		if p == node_path:
			var out := {}
			for j in st.get_node_property_count(i):
				out[st.get_node_property_name(i, j)] = st.get_node_property_value(i, j)
			return out
	return {"_missing": true}


func _children_of(room_id: String, parent: String) -> Array:
	var ps: PackedScene = load("res://scenes/rooms/%s.tscn" % room_id)
	var st := ps.get_state()
	var out: Array = []
	for i in st.get_node_count():
		if str(st.get_node_path(i, true)).trim_prefix("./") == parent:
			out.append(str(st.get_node_name(i)))
	return out


func _portal_ok(room_id: String, name: String, target: String, spawn: String, requires: String) -> bool:
	var p := _props(room_id, "Exits/" + name)
	return not p.has("_missing") and str(p.get("target_scene", "")).ends_with("/%s.tscn" % target) and str(p.get("spawn_name", "")) == spawn \
		and str(p.get("requires_ability", "")) == requires


# ---------- 1) 정적 연결 ----------
func _probe_static_links() -> void:
	_check(_portal_ok("mine_02", "ToFlooded", "flooded_mine_01", "FromMine02", ""), "관의 복도 ToFlooded → 잠긴 채굴장@FromMine02 (조건 없음) %s" % [_props("mine_02", "Exits/ToFlooded")])
	_check(_props("mine_02", "Exits/ToFlooded").get("position") == Vector2(3950, 1200) and _props("mine_02", "Markers/FromFlooded").get("position") == Vector2(3820, 1132),
		"관의 복도: 입구 (3950,1200) · 돌아오는 자리 FromFlooded (3820,1132)")
	_check(_portal_ok("flooded_mine_01", "Exit1", "mine_02", "FromFlooded", ""), "잠긴 채굴장 Exit1 → 관의 복도@FromFlooded")
	_check(_portal_ok("flooded_mine_01", "ToMineDeep", "mine_deep", "FromFlooded", "lantern") and _props("flooded_mine_01", "Exits/ToMineDeep").get("position") == Vector2(720, 1100),
		"잠긴 채굴장 ToMineDeep (720,1100) → 책임자의 방@FromFlooded, 등불 필요 ('%s')" % _props("flooded_mine_01", "Exits/ToMineDeep").get("locked_message", ""))
	_check(_props("flooded_mine_01", "Markers/FromMine02").get("position") == Vector2(120, 1032) and _props("flooded_mine_01", "Markers/FromMineDeep").get("position") == Vector2(800, 1032),
		"잠긴 채굴장 표식: FromMine02 (120,1032) · FromMineDeep (800,1032)")
	_check(_portal_ok("mine_deep", "ToFlooded", "flooded_mine_01", "FromMineDeep", ""), "책임자의 방 ToFlooded: 조건 없음 (그 방에 있다는 것이 곧 등불)")
	_check(_portal_ok("abyss_boss", "ToEnding", "abyss_ending", "FromBoss", "") and _props("abyss_boss", "Exits/ToEnding").get("position") == Vector2(3610, 1500)
		and _props("abyss_boss", "Markers/FromEnding").get("position") == Vector2(3460, 1432) and _props("abyss_boss", "Markers/FromVillage").has("_missing"),
		"정원의 끝 ToEnding (3610,1500) → 두 갈래 길@FromBoss, FromEnding 표식 (옛 FromVillage 이름 바꿈)")
	_check(_portal_ok("abyss_ending", "ToBoss", "abyss_boss", "FromEnding", "") and _props("abyss_ending", "Markers/FromBoss").get("position") == Vector2(340, 1432),
		"두 갈래 길 ToBoss → 정원의 끝@FromEnding, FromBoss (340,1432)")
	var root := _props("abyss_ending", "")
	_check(root.get("room_id") == "abyss_ending" and root.get("display_name") == "심연 · 두 갈래 길" and root.get("region") == "abyss" and root.get("bounds") == Rect2(0, 0, 2400, 1800) and root.get("map_offset") == Vector2(55600, -200),
		"두 갈래 길 방: %s / %s / %s / %s" % [root.get("display_name"), root.get("region"), root.get("bounds"), root.get("map_offset")])
	_check(_props("abyss_boss", "").get("display_name") == "심연 · 정원의 끝" and _props("moon_garden", "").get("display_name") == "심연 · 달빛 정원",
		"이름 통일: '%s', '%s'" % [_props("abyss_boss", "").get("display_name"), _props("moon_garden", "").get("display_name")])
	var boss_choices := _children_of("abyss_boss", "Choices")
	_check(boss_choices == ["Pump"] and _props("abyss_boss", "Choices/Pump").get("choice") == "third" and _props("abyss_boss", "Choices/Pump").get("position") == Vector2(2400, 1500),
		"정원의 끝 장치: %s (진엔딩 하나, x 2400)" % [boss_choices])
	var end_choices := _children_of("abyss_ending", "Choices")
	_check(end_choices == ["Roots", "Pipe"] and _props("abyss_ending", "Choices/Roots").get("choice") == "sacrifice" and _props("abyss_ending", "Choices/Pipe").get("choice") == "return"
		and _props("abyss_ending", "Choices/Roots").get("position") == Vector2(800, 1500) and _props("abyss_ending", "Choices/Pipe").get("position") == Vector2(1600, 1500),
		"두 갈래 길 장치: %s (희생 x800 · 되돌림 x1600)" % [end_choices])
	# 지도 사각형이 다른 방과 겹치지 않는다
	var mine := Rect2(Vector2(55600, -200), Vector2(2400, 1800))
	var overlap := ""
	for f in DirAccess.get_files_at("res://scenes/rooms"):
		if not f.ends_with(".tscn") or f == "abyss_ending.tscn":
			continue
		var r := _props(f.get_basename(), "")
		if r.has("map_offset") and r.has("bounds"):
			var b: Rect2 = r["bounds"]
			var other := Rect2(r["map_offset"], b.size)
			if other.intersects(mine) and not (other.end.x <= mine.position.x or mine.end.x <= other.position.x):
				overlap += f + " "
	_check(overlap == "", "두 갈래 길 지도 자리가 다른 방과 겹치지 않는다 %s" % overlap)


# ---------- 1') 왕복: 관의 복도 ↔ 잠긴 채굴장, 잠긴 채굴장 → 책임자의 방 (등불) ----------
func _probe_flooded_route() -> void:
	Progress.reset()
	await _open("mine_02", "FromFlooded")
	_check(_player.global_position.distance_to(Vector2(3820, 1132)) < 40.0, "관의 복도에 FromFlooded 로 도착 (%s)" % _player.global_position.round())
	var to_flooded: Portal = _room.get_node("Exits/ToFlooded")
	to_flooded._enter(_player)
	_check(to_flooded._used and Progress.next_spawn == "FromMine02", "ToFlooded 손길: 잠긴 채굴장으로 (등장 '%s')" % Progress.next_spawn)
	await _open("flooded_mine_01", Progress.next_spawn)
	_check(_player.global_position.distance_to(Vector2(120, 1032)) < 40.0, "잠긴 채굴장에 FromMine02 로 도착 (%s)" % _player.global_position.round())
	var back: Portal = _room.get_node("Exits/Exit1")
	back._enter(_player)
	_check(back._used and Progress.next_spawn == "FromFlooded", "Exit1 손길: 관의 복도로 (등장 '%s')" % Progress.next_spawn)
	await _open("mine_02", Progress.next_spawn)
	_check(_player.global_position.distance_to(Vector2(3820, 1132)) < 40.0, "관의 복도로 되돌아옴 (%s)" % _player.global_position.round())
	# 책임자의 방 지름길: 등불이 없으면 잠김
	Progress.reset()
	await _open("flooded_mine_01", "FromMineDeep")
	_check(_player.global_position.distance_to(Vector2(800, 1032)) < 40.0, "잠긴 채굴장에 FromMineDeep 로 도착 (%s)" % _player.global_position.round())
	var deep: Portal = _room.get_node("Exits/ToMineDeep")
	Progress.next_spawn = ""
	deep._enter(_player)
	_check(not deep._used and Progress.next_spawn == "" and _player.input_enabled, "ToMineDeep: 등불 없으면 잠긴 길 (건너가지 않음)")
	Progress.gain_ability("lantern")
	deep._enter(_player)
	_check(deep._used and Progress.next_spawn == "FromFlooded", "ToMineDeep: 등불이 있으면 책임자의 방으로 (등장 '%s')" % Progress.next_spawn)
	await _open("mine_deep", Progress.next_spawn)
	_check(_player.global_position.distance_to(Vector2(4700, 1032)) < 40.0, "책임자의 방에 FromFlooded 로 도착 (%s)" % _player.global_position.round())
	var to_f: Portal = _room.get_node("Exits/ToFlooded")
	to_f._enter(_player)
	_check(to_f._used and Progress.next_spawn == "FromMineDeep", "책임자의 방 → 잠긴 채굴장 (조건 없이, 등장 '%s')" % Progress.next_spawn)
	Progress.reset()


# ---------- 2) 새만 잡은 상태로 펌프 방까지: 얕은 수액 ----------
func _probe_shallow_sap() -> void:
	Progress.reset()
	Progress.gain_ability("double_jump")
	Progress.gain_ability("wind")
	var route := [["mine_02", "ToFlooded"], ["flooded_mine_01", "Exit2"], ["flooded_mine_02", "Exit2"]]
	var free := true
	for r in route:
		var p := _props(r[0], "Exits/" + r[1])
		if str(p.get("requires_ability", "")) != "":
			free = false
	_check(free, "새만 잡은 상태: 관의 복도 → 잠긴 채굴장 → 배관 위 → 펌프실 문에 능력 조건 없음")
	var spawns := {"flooded_mine_01": "FromMine02", "flooded_mine_02": "FromFlooded01", "flooded_mine_boss": "FromFlooded02"}
	for rid in spawns:
		await _open(rid, spawns[rid])
		_kill_enemies()
		var boss = _room.get("boss")
		if boss and is_instance_valid(boss):
			boss.set_physics_process(false)
			boss.set_process(false)
		for pool in _all_of(_room, SapPool):
			var sp: SapPool = pool
			_check(sp.shallow, "%s/%s: 얕은 수액" % [rid, sp.name])
			var hp0 := _player.hp
			_place(sp.global_position + Vector2(sp.size.x * 0.5, sp.size.y - 70.0))
			var inside := 0
			for i in 90:
				await get_tree().physics_frame
				if sp.get_overlapping_bodies().has(_player):
					inside += 1
			# 느려짐은 소녀가 그 틱에 움직인 뒤 1 로 되돌리므로, 웅덩이의 한 틱을 직접 돌려 바로 읽는다
			sp._physics_process(0.0)
			var sf := _player.slow_factor
			var rf := _player.roll_factor
			_check(inside > 30 and absf(sf - SapPool.SHALLOW_SLOW) < 0.01 and absf(rf - SapPool.SHALLOW_ROLL) < 0.01 and _player.hp == hp0,
				"%s/%s: 수액 위 걷기 없이 1.5초 — 피해 0 (체력 %.0f → %.0f), 느려짐 %.2f·구르기 %.2f, 웅덩이 안 %d틱" % [rid, sp.name, hp0, _player.hp, sf, rf, inside])
	# 깊은 수액(책임자의 방·호수)은 그대로
	await _open("mine_deep", "FromFlooded")
	_kill_enemies()
	var deep_pool: SapPool = _all_of(_room, SapPool)[0]
	var hp1 := _player.hp
	_place(deep_pool.global_position + Vector2(deep_pool.size.x * 0.5, deep_pool.size.y - 70.0))
	await _wait(1.6)
	_check(not deep_pool.shallow and _player.hp < hp1, "책임자의 방 웅덩이는 깊은 수액 그대로 (체력 %.0f → %.0f)" % [hp1, _player.hp])
	var lake_ok := true
	for rid in ["sap_lake_01", "sap_lake_02", "sap_lake_boss"]:
		var ps: PackedScene = load("res://scenes/rooms/%s.tscn" % rid)
		var st := ps.get_state()
		for i in st.get_node_count():
			for j in st.get_node_property_count(i):
				if st.get_node_property_name(i, j) == "shallow" and st.get_node_property_value(i, j) == true:
					lake_ok = false
	_check(lake_ok, "수액의 호수 웅덩이는 얕지 않다 (수액 위 걷기 체감 그대로)")
	Progress.reset()


func _all_of(node: Node, type) -> Array:
	var out: Array = []
	for c in node.get_children():
		if is_instance_of(c, type):
			out.append(c)
		out.append_array(_all_of(c, type))
	return out


# ---------- 3) 엔딩 장치 방 ----------
func _probe_ending_rooms() -> void:
	Progress.reset()
	await _open("abyss_ending", "FromBoss")
	var choices: Node2D = _room.get_node("Choices")
	_check(_player.global_position.distance_to(Vector2(340, 1432)) < 40.0, "두 갈래 길에 FromBoss 로 도착 (%s)" % _player.global_position.round())
	_check(not choices.visible and choices.get_child(0).process_mode == Node.PROCESS_MODE_DISABLED, "정화 전: 두 갈래 길 장치는 잠들어 있다 (숨김·멈춤)")
	Progress.set_flag("boss_root_defeated")
	Progress.set_flag("after_boss_root_defeated")
	await get_tree().physics_frame
	_check(choices.visible and choices.get_child(0).process_mode == Node.PROCESS_MODE_INHERIT, "깃발 after_boss_root_defeated 가 서면 그 자리에서 깨어난다")
	var entry: Dictionary = Progress.visited_rooms.get("abyss_ending", {})
	_check(entry.get("explore_total", -1) == 0 and entry.get("region", "") == "abyss" and entry.get("name", "") == "심연 · 두 갈래 길", "지도: %s, 탐사 %d/%d (0/0 → 가 보면 완료)" % [entry.get("name", ""), entry.get("explore_found", -1), entry.get("explore_total", -1)])
	var back: Portal = _room.get_node("Exits/ToBoss")
	back._enter(_player)
	_check(back._used and Progress.next_spawn == "FromEnding", "두 갈래 길 → 정원의 끝 (등장 '%s')" % Progress.next_spawn)
	await _open("abyss_boss", Progress.next_spawn)
	_check(_player.global_position.distance_to(Vector2(3460, 1432)) < 40.0, "정원의 끝에 FromEnding 으로 도착 (%s)" % _player.global_position.round())
	var bc: Node2D = _room.get_node("Choices")
	_check(bc.visible and bc.get_child_count() == 1 and (bc.get_child(0) as EndingChoice).choice == "third", "정원의 끝: 정화 뒤 진엔딩 장치 하나만 깨어 있다")
	var gate_open: bool = not _room.gate_out.closed
	var to_end: Portal = _room.get_node("Exits/ToEnding")
	to_end._enter(_player)
	_check(gate_open and to_end._used and Progress.next_spawn == "FromBoss", "정원의 끝 → 두 갈래 길 (오른쪽 문 열림 %s, 등장 '%s')" % [gate_open, Progress.next_spawn])
	await _open("abyss_ending", Progress.next_spawn)
	var ch: Node2D = _room.get_node("Choices")
	_check(ch.visible and (ch.get_node("Roots") as EndingChoice).choice == "sacrifice" and (ch.get_node("Pipe") as EndingChoice).choice == "return"
		and not (ch.get_node("Roots") as EndingChoice).is_locked() and not (ch.get_node("Pipe") as EndingChoice).is_locked(),
		"정화 뒤 다시 와도 일반 엔딩 둘이 깨어 있다 (경전과 상관없이 잠기지 않음)")
	# 일반 엔딩 고르기: 희생 장치에 다가가 손길
	Progress.set_flag("looked_at_lantern")
	var roots: EndingChoice = ch.get_node("Roots")
	_place(roots.global_position + Vector2(-90, -68))
	await _wait(0.4)
	_check(_player.interactables.has(roots), "희생 장치 곁: 손길 대상")
	Progress.ending = ""
	roots.interact(_player)
	_check(Progress.ending == "sacrifice" and not _player.input_enabled, "희생 장치 손길 → Progress.ending '%s'" % Progress.ending)
	Progress.reset()


# ---------- 4) 진엔딩 조건 ----------
func _probe_third_lock() -> void:
	Progress.reset()
	_check(not EndingChoice.third_unlocked(), "조건: 아무것도 없으면 잠김")
	for a in ["wind", "light", "sap_walk", "wall_break"]:
		Progress.gain_ability(a)
	Progress.set_flag("boss_root_defeated")
	_check(not EndingChoice.third_unlocked() and not EndingChoice.has_five_souls(), "조건: 네 영혼 능력 + 뿌리지기 정화만으로는 잠김 (예전 조건 없앰)")
	Progress.reset()
	for n in 4:
		Progress.set_flag("read_scripture_%d" % (n + 1))
	_check(not EndingChoice.third_unlocked(), "조건: 경전 네 장만으로는 잠김 (뿌리지기 정화 필요)")
	Progress.set_flag("boss_root_defeated")
	_check(EndingChoice.third_unlocked() and EndingChoice.has_five_souls(), "조건: 뿌리지기 정화 + 경전 네 장 = 열림 (능력과 상관없음)")
	Progress.reset()
	Progress.set_flag("read_scripture_village")
	Progress.set_flag("read_scripture_mine")
	Progress.set_flag("boss_root_defeated")
	_check(not EndingChoice.third_unlocked(), "조건: 사당 경전·훼손된 경전은 조각이 아니다")
	# 화면 글은 데이터 파일에서 (코드의 대비 문장이 아니라)
	var t_hint := EndingChoice.text("locked_hint", "-")
	var t_look := EndingChoice.text("lantern_look", "-")
	var t_rite := EndingChoice.text("third_ritual", "-")
	_check(t_hint.contains("{n}") and t_hint.contains("{total}") and t_look != "-" and t_rite != "-" and EndingChoice.text("chosen", "-") != "-",
		"장치 글은 data/dialogue/ending_devices.json 에서 ('%s' / '%s' / '%s')" % [t_hint, t_look, t_rite])
	# 방에서: 잠긴 장치는 보이되 꺼져 있다
	Progress.reset()
	for f in ["boss_root_defeated", "after_boss_root_defeated", "looked_at_lantern", "read_scripture_1", "read_scripture_2"]:
		Progress.set_flag(f)
	await _open("abyss_boss", "AfterBoss")
	var pump: EndingChoice = _room.get_node("Choices/Pump")
	var wheel := pump.wheel_node()
	var a0 := wheel.rotation
	await _wait(1.0)
	_check(pump.is_locked() and pump.visible and pump.art_node().modulate.is_equal_approx(EndingChoice.LOCKED_TINT) and is_equal_approx(wheel.rotation, a0) and not Progress.has("five_souls"),
		"경전 2/4: 진엔딩 장치가 보이되 꺼짐 (잿빛, 바퀴 멈춤 %.3f → %.3f, five_souls 없음)" % [a0, wheel.rotation])
	_place(pump.global_position + Vector2(-110, -68))
	await _wait(0.5)
	_check(pump._prompt.visible and pump._prompt.text == "경전의 조각이 모자라다 (2/4)" and not _player.interactables.has(pump), "가까이 가면 안내 '%s', 손길 대상 아님" % pump._prompt.text)
	Progress.ending = ""
	pump.interact(_player)
	_check(Progress.ending == "" and _player.input_enabled, "잠긴 장치 손길: 거절 (엔딩 '%s')" % Progress.ending)
	Progress.set_flag("read_scripture_3")
	await get_tree().process_frame
	await get_tree().physics_frame
	_check(pump.is_locked() and pump._prompt.text == "경전의 조각이 모자라다 (3/4)", "경전 3/4: 아직 잠김 (%s)" % pump._prompt.text)
	Progress.set_flag("read_scripture_4")
	await _wait(0.6)
	_check(not pump.is_locked() and pump.art_node().modulate.is_equal_approx(Color.WHITE) and Progress.has("five_souls") and _player.interactables.has(pump),
		"경전 4/4: 그 자리에서 깨어난다 (색 돌아옴, five_souls, 곁에 있으면 손길 대상)")
	var a1 := wheel.rotation
	await _wait(1.0)
	_check(absf(wrapf(wheel.rotation - a1, -PI, PI)) > 0.1, "깨어난 물레방아가 돈다 (%.3f → %.3f)" % [a1, wheel.rotation])
	pump.interact(_player)
	await _wait(1.0)
	_check(Progress.ending == "third" and not _player.input_enabled and wheel.rotation < a1, "진엔딩 장치 손길 → ending 'third', 물레방아가 거꾸로 돈다")
	await _wait(2.5)   # 연출이 끝까지 (Game._busy 라 장면은 그대로)
	Progress.reset()


# ---------- 5) 정원 끝의 비석 ----------
func _probe_stone() -> void:
	Progress.reset()
	await _open("moon_garden", "FromAbyss02")
	var stone: Record = null
	for r in _all_of(_room, Record):
		if r.record_id == "root_gate_stone":
			stone = r
	_check(stone != null and stone.kind == "stone" and absf(stone.global_position.x - 2180.0) < 1.0 and absf(stone.global_position.y - 1100.0) < 1.0,
		"달빛 정원 x 2180 에 비석 root_gate_stone (뿌리지기 방 포탈 2810 앞)")
	if stone == null:
		return
	var data: Dictionary = stone._data
	var ex: Array = data.get("extra", [])
	_check(data.get("title", "") == "정원 끝의 비석" and data.get("lines", []).size() == 2 and ex.size() == 1, "비석 글: '%s' %d줄 + 조건 줄 %d" % [data.get("title", ""), data.get("lines", []).size(), ex.size()])
	var when: String = ex[0].get("when", "") if ex.size() > 0 else ""
	var before := stone._condition_ok(when)
	for n in 4:
		Progress.set_flag("read_scripture_%d" % (n + 1))
	var after := stone._condition_ok(when)
	_check(not before and after, "네 조각을 다 읽어야 비석에 줄이 더해진다 (전 %s / 뒤 %s)" % [before, after])
	var ids: Dictionary = Progress.visited_rooms.get("moon_garden", {}).get("explore_ids", {})
	_check(ids.get("records", []).has("root_gate_stone"), "달빛 정원 탐사 요소에 비석 (%s)" % [ids.get("records", [])])
	Progress.reset()


# ---------- 6) 입구 찾기 ----------
func _probe_hidden_portal() -> void:
	_check(HiddenPortal.CRACK_ALPHA == 0.92 and HiddenPortal.CRACK_W == 72.0 and HiddenPortal.CRACK_H == 250.0 and HiddenPortal.REVEAL_RANGE == 400.0 and HiddenPortal.HINT_RANGE == 700.0,
		"마을 틈: 진하기 %.2f, 크기 %.0f×%.0f, 드러남 %.0f, 단서 %.0f" % [HiddenPortal.CRACK_ALPHA, HiddenPortal.CRACK_W, HiddenPortal.CRACK_H, HiddenPortal.REVEAL_RANGE, HiddenPortal.HINT_RANGE])
	Progress.reset()
	await _open("village_02", "FromVillage01")
	_kill_enemies()
	var hp: HiddenPortal = _room.get_node("Exits/ToHiddenDescent")
	var mid := hp.global_position + Vector2(0, -HiddenPortal.CRACK_H * 0.5)
	_place(hp.global_position + Vector2(1200, -68))
	await _wait(0.5)
	_check(not hp.is_revealed() and hp.hint_level() < 0.01 and not hp.is_in_group("portal"), "멀리서는 어두운 틈만 (단서 빛 %.2f)" % hp.hint_level())
	# 700 안 · 400 밖: 등불이 없어도 청록 맥동
	_place(Vector2(mid.x + 560.0, hp.global_position.y - 68.0))
	await _wait(0.8)
	var d := _player.global_position.distance_to(mid)
	_check(not hp.is_revealed() and hp.hint_level() > 0.05, "등불 없이 %.0fpx: 청록 단서 빛 %.2f, 아직 안 드러남" % [d, hp.hint_level()])
	_place(hp.global_position + Vector2(240, -68))
	await _wait(1.6)
	var map_portals: Array = Progress.visited_rooms.get("village_02", {}).get("portals", [])
	_check(hp.is_revealed() and Progress.has(hp.seen_flag) and hp.is_in_group("portal") and map_portals.has(hp.position) and not Progress.has_ability("lantern"),
		"등불 없이 가까이: '본 것' (깃발 %s, 지도 ◆ %s)" % [Progress.has(hp.seen_flag), map_portals.has(hp.position)])
	_place(hp.global_position + Vector2(-60, -68))
	await _wait(0.4)
	Progress.next_spawn = ""
	hp._enter(_player)
	_check(not hp._used and Progress.next_spawn == "" and hp._prompt.text == "잠긴 길", "드러났어도 등불 없이는 들어가지 못한다 (머리 위 '%s')" % hp._prompt.text)
	_check(hp.locked_message == "깊은 틈 아래에서 수액 냄새가 올라온다… 등불 없이는 내려갈 수 없다", "잠김 안내: %s" % hp.locked_message)
	# 다시 들어와도 처음부터 (잠긴) 포탈
	await _open("village_02", "FromVillage01")
	var hp2: HiddenPortal = _room.get_node("Exits/ToHiddenDescent")
	_check(hp2.is_revealed() and hp2.is_in_group("portal"), "다시 들어오면 처음부터 드러나 있다 (깃발 기억, 등불 없어도)")
	Progress.gain_ability("lantern")
	_kill_enemies()
	_place(hp2.global_position + Vector2(-60, -68))
	await _wait(0.4)
	hp2._enter(_player)
	_check(hp2._used and Progress.next_spawn == "FromVillage", "등불이 있으면 숨은 내리막으로 (등장 '%s')" % Progress.next_spawn)
	# 관의 복도 펌프실 표지·등불 기둥
	Progress.reset()
	await _open("mine_02", "FromMine01")
	var sign: Record = null
	for r in _all_of(_room, Record):
		if r.record_id == "pump_way_sign":
			sign = r
	var to_f: Node2D = _room.get_node("Exits/ToFlooded")
	var lamp: Node2D = _room.get_node_or_null("Props/PumpLamp")
	_check(sign != null and sign.kind == "note" and sign.global_position.distance_to(to_f.global_position) < 300.0 and sign._data.get("title", "") == "배수 갱도 표지" and sign._data.get("lines", []).size() == 2,
		"관의 복도: 펌프실 입구 옆 표지 '%s'" % (sign._data.get("title", "") if sign else "-"))
	_check(lamp != null and lamp.piece == "gallows_a" and absf(lamp.global_position.x - to_f.global_position.x) < 400.0, "관의 복도: 입구 옆 등불 기둥 (Prop gallows_a)")
	Progress.reset()


func _probe_hints() -> void:
	Progress.reset()
	var tia: Npc = load("res://scenes/npcs/npc.tscn").instantiate()
	tia.npc_id = "tia"
	add_child(tia)
	var owen: Npc = load("res://scenes/npcs/npc.tscn").instantiate()
	owen.npc_id = "owen"
	add_child(owen)
	await get_tree().process_frame
	Progress.set_flag("has_tia_lantern")
	var t0 := str(tia.pick_talk().get("when", ""))
	# 기사를 쓰러뜨렸어도 회상에서 돌아와 등불을 받기 전(after 깃발 전)에는 힌트를 하지 않는다
	Progress.set_flag("boss_knight_defeated")
	var t_before := str(tia.pick_talk().get("set", ""))
	Progress.set_flag("after_boss_knight_defeated")
	var t1: Dictionary = tia.pick_talk()
	var hint_line := str(t1.get("lines", [""])[0])
	Progress.set_flag(str(t1.get("set", "")))
	var t2 := str(tia.pick_talk().get("when", ""))
	_check(t0 == "has_tia_lantern,!owen_rescued" and t_before != "tia_told_sap_crack" and hint_line.begins_with("골목 끝 틈에서 수액 냄새가 났어") and t1.get("set", "") == "tia_told_sap_crack" and t2 == "has_tia_lantern,!owen_rescued",
		"티아: 기사 정화 뒤 등불을 받기 전엔 힌트 없음, 받은 뒤(after 깃발) 한 번 '%s' → 다시 원래 대사" % hint_line)
	Progress.reset()
	Progress.set_flag("has_tia_lantern")
	Progress.set_flag("boss_knight_defeated")
	Progress.set_flag("after_boss_knight_defeated")
	Progress.set_flag("owen_rescued")
	_check(str(tia.pick_talk().get("when", "")) == "owen_rescued,!reunion_done", "티아: 오웬과의 재회가 남았으면 재회가 먼저")
	Progress.set_flag("reunion_done")
	_check(str(tia.pick_talk().get("set", "")) == "tia_told_sap_crack", "티아: 재회 뒤에도 (아직 못 들었으면) 수액 냄새 힌트")
	Progress.set_flag("boss_queen_defeated")
	_check(str(tia.pick_talk().get("set", "")) != "tia_told_sap_crack", "티아: 여왕을 정화했으면 힌트 안 함")
	Progress.reset()
	Progress.set_flag("owen_rescued")
	var o1: Dictionary = owen.pick_talk()
	_check(str(o1.get("lines", [""])[0]).begins_with("관의 복도 끝에 펌프실로 내려가는 배수 갱도가 있지"), "오웬(사람): '%s'" % str(o1.get("lines", [""])[0]))
	Progress.set_flag("boss_pump_defeated")
	_check(str(owen.pick_talk().get("when", "")) == "boss_pump_defeated", "오웬: 펌프를 멈춘 뒤엔 펌프 대사")
	tia.queue_free()
	owen.queue_free()
	Progress.reset()


# ---------- 7) 그림 ----------
func _probe_art() -> void:
	Progress.reset()
	for f in ["boss_root_defeated", "after_boss_root_defeated", "looked_at_lantern"]:
		Progress.set_flag(f)
	for n in 4:
		Progress.set_flag("read_scripture_%d" % (n + 1))
	await _open("abyss_ending", "FromBoss")
	var tex_ok := true
	for pair in [["Roots", "object_choice_root.png"], ["Pipe", "object_choice_pipe.png"]]:
		var c: EndingChoice = _room.get_node("Choices/" + pair[0])
		var found := false
		for s in _all_of(c.art_node(), Sprite2D):
			if (s as Sprite2D).texture and (s as Sprite2D).texture.resource_path.ends_with(pair[1]):
				found = true
		tex_ok = tex_ok and found
	_check(tex_ok, "일반 엔딩 장치 두 개가 새 그림 (뿌리·관)")
	await _open("abyss_boss", "AfterBoss")
	var pump: EndingChoice = _room.get_node("Choices/Pump")
	var names: Array = []
	for s in pump.wheel_node().get_children():
		names.append((s as Sprite2D).texture.resource_path.get_file())
	var base_ok := false
	for s in _all_of(pump.art_node(), Sprite2D):
		if (s as Sprite2D).texture and (s as Sprite2D).texture.resource_path.ends_with("object_choice_pump_base.png"):
			base_ok = true
	_check(base_ok and names == ["object_choice_pump_spokes.png", "object_choice_pump_ring.png", "object_choice_pump_hub.png"], "진엔딩 장치: 받침 + 도는 조각 %s" % [names])
	var c0: Vector2 = pump.ritual_center()
	_check(c0.y < -150.0 and c0.y > -260.0, "의식 연출 중심 = 바퀴 중심 %s" % c0)
	# 흐린 물레방아
	var backdrop: Node = _room.get_node("Backdrop")
	var order: Array = []
	for c in backdrop.get_children():
		order.append(str(c.name))
	var wheel_layer := backdrop.get_node_or_null("Wheel") as Parallax2D
	var bw := _room.get_node_or_null("Backdrop/Wheel/BlurWheel") as BlurWheel
	_check(wheel_layer != null and wheel_layer.scroll_scale == Vector2(0.25, 0.25) and order.find("Wheel") == order.find("Far") + 1 and order.find("Shafts") == order.find("Wheel") + 1,
		"배경 물레방아 겹: Far 와 Shafts 사이, 비율 0.25 (%s)" % [order])
	if bw:
		var r0 := bw.angle()
		await _wait(1.0)
		var turned := wrapf(bw.angle() - r0, -PI, PI)
		var sp: Sprite2D = bw.get_child(0)
		var mat := sp.material as ShaderMaterial
		var img := sp.texture.get_image()
		_check(absf(turned - 0.10) < 0.03 and mat != null and is_equal_approx(float(mat.get_shader_parameter("blur")), 2.5) and img.has_mipmaps() and bw.modulate.is_equal_approx(Color(0.55, 0.62, 0.70, 0.55)),
			"흐린 물레방아: 1초에 %.3f rad 돈다, 흐림 %.1f, 밉맵 %s, 색 %s" % [turned, float(mat.get_shader_parameter("blur")) if mat else -1.0, img.has_mipmaps(), bw.modulate])
		# v1.1.0 검수: 잿빛 방에서는 무채색(ash 1), 정화되면 원래 색(ash 0) — Purity.level 을 따라간다
		if mat:
			var lv0 := Purity.level
			var ash0 := float(mat.get_shader_parameter("ash"))
			Purity.level = 1.0
			await _wait(0.1)
			var ash1 := float(mat.get_shader_parameter("ash"))
			var br1 := float(mat.get_shader_parameter("bright"))
			Purity.level = lv0
			await _wait(0.1)
			_check(absf(ash0 - (1.0 - lv0)) < 0.01 and ash1 < 0.01 and br1 > 1.5 and absf(float(mat.get_shader_parameter("ash")) - (1.0 - lv0)) < 0.01,
				"흐린 물레방아가 정화 정도를 따른다: 지금(정화 %.2f) 잿빛 %.2f, 정화 1 → 잿빛 %.2f·밝기 %.2f" % [lv0, ash0, ash1, br1])
	else:
		_check(false, "배경 물레방아(BlurWheel)가 없다")
	Progress.reset()


# ---------- 눈 확인용 스크린샷 (창 모드) ----------
func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		var path := _out.path_join("w2_%s.png" % name)
		img.save_png(path)
		print("[probe] 스크린샷 ", path)


func _view(at: Vector2, settle := 1.4, face := 0) -> void:
	_place(at)
	if face != 0:
		_player.facing = face
	var touch := _room.get_node_or_null("TouchControls")
	if touch:
		touch.set("visible", false)   # 눈 확인용: 터치 버튼이 그림을 가리지 않게
	await _wait(settle)


func _take_shots() -> void:
	# 뿌리지기 방: 진엔딩 장치(잠김 / 깨어남)와 배경 물레방아
	Progress.reset()
	for f in ["boss_root_defeated", "after_boss_root_defeated", "looked_at_lantern", "read_scripture_1", "read_scripture_2"]:
		Progress.set_flag(f)
	await _open("abyss_boss", "AfterBoss")
	await _view(Vector2(2150, 1432), 2.0)
	await _shot("abyss_boss_locked")
	for n in 4:
		Progress.set_flag("read_scripture_%d" % (n + 1))
	await _wait(1.0)
	await _shot("abyss_boss_unlocked")
	await _view(Vector2(3300, 1432), 1.6)
	await _shot("abyss_boss_right_door")
	await _view(Vector2(1300, 1432), 1.6)
	await _shot("abyss_boss_wheel_left")
	var pump: EndingChoice = _room.get_node("Choices/Pump")
	await _view(pump.global_position + Vector2(-140, -68), 1.0)
	pump.interact(_player)
	await _wait(1.6)
	await _shot("abyss_boss_ritual_1")
	await _wait(0.9)
	await _shot("abyss_boss_ritual_2")
	await _wait(1.0)
	# 정화된 뒤의 색 (뿌리지기를 정화하면 심연에 색이 돌아온다)
	Progress.reset()
	for f in ["boss_root_defeated", "after_boss_root_defeated", "looked_at_lantern"]:
		Progress.set_flag(f)
	Purity.regions["abyss"] = true
	await _open("abyss_boss", "AfterBoss")
	Purity.apply_region("abyss")
	await _view(Vector2(2150, 1432), 2.0)
	await _shot("abyss_boss_purified")
	# 두 갈래 길
	await _open("abyss_ending", "FromBoss")
	Purity.apply_region("abyss")
	await _view(Vector2(1200, 1432), 2.0)
	await _shot("abyss_ending_purified")
	Purity.reset_region("abyss")
	await _open("abyss_ending", "FromBoss")
	await _view(Vector2(1200, 1432), 2.0)
	await _shot("abyss_ending")
	await _view(Vector2(700, 1432), 1.2)
	await _shot("abyss_ending_roots")
	await _view(Vector2(1700, 1432), 1.2)
	await _shot("abyss_ending_pipe")
	# 달빛 정원 비석
	Progress.reset()
	await _open("moon_garden", "FromAbyss02")
	await _view(Vector2(2050, 1032), 1.6)
	await _shot("moon_garden_stone")
	# 관의 복도 펌프실 입구
	Progress.reset()
	await _open("mine_02", "FromFlooded")
	_kill_enemies()
	await _view(Vector2(3700, 1132), 1.6)
	await _shot("mine_02_entrance")
	await _view(Vector2(3450, 1132), 1.6, 1)
	await _shot("mine_02_entrance_far")
	# 잠긴 채굴장 왼쪽 (관의 복도 문 + 책임자의 방 지름길)
	await _open("flooded_mine_01", "FromMine02")
	_kill_enemies()
	await _view(Vector2(500, 1032), 1.6)
	await _shot("flooded_mine_01_left")
	# 마을 틈: 멀리 / 청록 단서 / 드러남(등불 없음)
	Progress.reset()
	await _open("village_02", "FromVillage01")
	_kill_enemies()
	var hp: HiddenPortal = _room.get_node("Exits/ToHiddenDescent")
	await _view(hp.global_position + Vector2(460, -68), 2.0)
	await _shot("village_02_crack_hint")
	await _view(hp.global_position + Vector2(240, -68), 2.0)
	await _shot("village_02_crack_seen")

extends Node
## Claude Code용 확장판 · 잠긴 채굴장 묶음 시험 (화면 없이 돈다).
## 실행: godot --headless --path . res://tools/probe_mine.tscn
##  1) 새 방 12개(잠긴 채굴장 3 + 숨겨진 방 9)가 뜨고 포탈·달빛풀·기록물·보상이 자리에 있는지
##  2) 금 간 벽: 능력 없이는 튕기고(blocked) 안 부서진다 / 있으면 약공격 3대 또는 무거운 공격 1대에 부서지고 Progress.collected 에 남는다
##  3) 잠긴 채굴장 포탈: sap_walk 없이는 잠긴 길 (책임자의 방에 link 가 적용돼 있으면 그 포탈도 확인)
##  4) 작은 펌프: 2초 리듬으로 쏜다, 약공격은 절반
##  5) 무쇠 펌프: 1페이즈 순서 고정(피스톤→분사→빨아들이기), 장갑(약공격 35%·되받은 분사·BROKEN ×2), 빨아들이기(바람), 2페이즈 무작위·엇박·수액 기둥, 쓰러짐→정화
##  6) 경비병 방패·기계 장갑이 벽 부수기 + 무거운 공격에 깨진다
##  7) 회상 곡: 모든 회상이 정식 곡 recollection (옛 '보스 수에 따라 길어지는 임시 주제곡'은 없앰) + 정화한 보스 수 세기
##  8) 대사 데이터: 오웬·티아 추가 대사(priority 로 먼저 골라짐), 광부, 경전 조각·완성 구절, 회상·엔딩
##  9) 세 번째 선택지: 네 능력 없으면 숨고(능력만 있고 뿌리지기 깃발이 없어도 숨김) 있으면 보이며 five_souls 깃발 → 엔딩 씬 "제3의 길" 로드 → interact 로 ending "third"
## 10) 회상에서 돌아온 무쇠 펌프 방: 영혼이 깃들어 벽 부수기(wall_break)를 얻고, 멈춘 펌프 위의 싹(PumpRemains)이 보인다
## 11) 엔딩 뒤 이어서 탐험: 엔딩 씬이 저장 → 타이틀이 저장 파일로 클리어(제3의 길)를 알아봄 → 이어하기가 마지막 달빛풀로
##     (기기의 진짜 저장 파일 user://save.json 은 시험 전에 떠 두었다가 끝나고 되돌린다)
## 12) 수액 방울 실제 비행: 무쇠 펌프·작은 펌프가 쏜 방울을 여러 거리에서 저스트 가드 → 되받은 방울이 쏜 쪽 몸통에 맞는다
##     (바닥에 떨어지지 않음), 작은 펌프는 사거리 끝에서도 방울이 소녀에게 닿는다
## 13) 피스톤 판정이 보이는 망치 자리(앞 150~370)에만: 300 에 서면 피스톤 28, 450 이면 피스톤 없음(충격파만)
## 14) 빨아들이기 실제 물리(펌프 방): 가만히 서 있으면 300px 넘게 끌리고, 반대로 달리면 벗어난다
## 15) 정화하는 순간 멈춘 펌프+싹이 펌프 자리에 나타나고 회상 뒤에도 같은 자리, 2페이즈 음악(곡은 그대로, 한 번 휘청 — Music.falter), 옛 저장 지도 바로잡기(MapOffsetFix)
## -- --linked : 통합 뒤(link_flooded_mine.py 를 돌린 뒤) 엄격 모드 — 기존 방에 잠긴 채굴장 입구·벽장·등장 자리가 없으면 실패.
##    (이 묶음의 브랜치에는 기존 방을 기준판 그대로 두었으므로 기본 모드에서는 '연결 전' 으로 적고 넘어간다)
## 마지막 줄 "[probe] 끝: 실패 N".

const DT := 1.0 / 60.0
var _fail := 0
var _player: Player
var _floor: StaticBody2D
var _linked := false
var _bad_links: Array = []


func _ready() -> void:
	_linked = "--linked" in OS.get_cmdline_user_args()
	print("[probe] 잠긴 채굴장 묶음 시험 시작%s" % (" (--linked 엄격 모드)" if _linked else ""))
	await _run()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _hit(dmg: float, poise: float, src: Node2D = null) -> HitData:
	var h := HitData.make(dmg, poise, src if src else _player)
	h.from_player = true
	return h


func _make_floor(y: float, w := 8000.0) -> void:
	_floor = StaticBody2D.new()
	_floor.collision_layer = 1
	_floor.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(w, 200)
	shape.shape = rect
	shape.position = Vector2(w / 2.0, y + 100.0)
	_floor.add_child(shape)
	add_child(_floor)


func _make_player(pos: Vector2) -> void:
	_player = load("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.global_position = pos
	_player.set_physics_process(false)
	_player.set_process(false)
	_player._invuln_timer = 9999.0


func _run() -> void:
	Progress.reset()
	await _probe_rooms()
	await _probe_after_memory()
	await _probe_cracked_wall()
	await _probe_portal_lock()
	await _probe_data()
	_probe_memory_theme()
	_make_floor(1000.0)
	_make_player(Vector2(600, 1000))
	await _frames(3)
	await _probe_small_pump()
	await _probe_dew_cup()
	await _probe_guard_machine()
	await _probe_iron_pump()
	await _probe_third_way()
	await _probe_ending_continue()
	await _probe_reflect_flight()
	await _probe_piston_reach()
	_player.queue_free()
	_floor.queue_free()
	await _frames(2)
	await _probe_suck_real()
	await _probe_remains_and_music()
	_probe_map_fix()
	await _probe_third_interact()


# ---------- 1) 방 ----------
func _probe_rooms() -> void:
	var rooms := {
		"flooded_mine_01": {"portals": 2, "grass": 1, "pumps": 3},
		"flooded_mine_02": {"portals": 3, "records": 1, "pumps": 3, "cracked": 1},
		"flooded_mine_boss": {"portals": 1, "grass": 1, "boss": true},
		"canopy_hidden_1": {"portals": 1, "pickups": 1},
		"canopy_hidden_2": {"portals": 1, "records": 1},
		"village_hidden_1": {"portals": 1, "records": 1},
		"village_hidden_2": {"portals": 1, "pickups": 1},
		"mine_hidden_1": {"portals": 1, "rescues": 1},
		"mine_hidden_2": {"portals": 1, "records": 1},
		"abyss_hidden_1": {"portals": 1, "records": 1},
		"abyss_hidden_2": {"portals": 1, "grass": 1},
		"flooded_mine_hidden_1": {"portals": 1, "pickups": 1},
	}
	for rid in rooms:
		var scene: PackedScene = load("res://scenes/rooms/%s.tscn" % rid)
		if scene == null:
			_check(false, "방 %s 를 읽지 못했다" % rid)
			continue
		var room = scene.instantiate()
		add_child(room)
		await _frames(4)
		var want: Dictionary = rooms[rid]
		var portals := get_tree().get_nodes_in_group("portal").size()
		var grasses := get_tree().get_nodes_in_group("moonlight_grass").size()
		var pickups := get_tree().get_nodes_in_group("pickup").size()
		var records := 0
		var rescues := 0
		var pumps := 0
		var cracked := get_tree().get_nodes_in_group("cracked_wall").size()
		for n in _all(room):
			if n is Record:
				records += 1
			elif n is EnemyBase and n.savable:
				rescues += 1
			elif n is SmallPump:
				pumps += 1
		var ok: bool = room.room_id == rid and portals == want.get("portals", 0) and grasses == want.get("grass", 0) and pickups == want.get("pickups", 0) \
			and records == want.get("records", 0) and rescues == want.get("rescues", 0) and pumps == want.get("pumps", 0) and cracked == want.get("cracked", 0)
		if want.get("boss", false):
			ok = ok and room is BossRoom and is_instance_valid(room.boss) and room.boss is IronPump and room.boss_name == "무쇠 펌프" and room.defeat_flag == "boss_pump_defeated" and room.abilities == ["wall_break"] and room.boss_track == "boss_iron_pump"
		for pt in get_tree().get_nodes_in_group("portal"):
			if pt.spawn_name != "" and not _scene_has_marker(pt.target_scene, pt.spawn_name):
				_bad_links.append("%s → %s 의 %s" % [rid, pt.target_scene.get_file(), pt.spawn_name])
		var vis: Dictionary = Progress.visited_rooms.get(rid, {})
		_check(ok and vis.get("region", "") == room.region, "방 %s (%s): 포탈 %d, 달빛풀 %d, 아이템 %d, 기록물 %d, 구원 %d, 작은 펌프 %d, 금 간 벽 %d, 지도 지역 %s, 탐사 %d/%d" % [
			rid, room.display_name, portals, grasses, pickups, records, rescues, pumps, cracked, vis.get("region", "?"), int(vis.get("explore_found", -1)), int(vis.get("explore_total", -1))])
		room.queue_free()
		await _frames(2)
	if _linked:
		_check(_bad_links.is_empty(), "연결(--linked): 새 방 포탈의 등장 자리가 모두 있다 (없는 것 %d: %s)" % [_bad_links.size(), _bad_links])
	else:
		print("[probe] (연결 전: 등장 자리가 아직 없는 포탈 %d개 — 통합 때 tools/link_flooded_mine.py 가 기존 방에 끼운다. 통합 뒤에는 -- --linked 로 돌린다)" % _bad_links.size())
	Progress.reset()


## 방 장면 파일에 Markers/<marker> 가 있는가 (장면을 띄우지 않고 SceneState 로 본다).
func _scene_has_marker(path: String, marker: String) -> bool:
	if marker.begins_with("Grass:"):
		return true
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if ps == null:
		return false
	var st := ps.get_state()
	for i in st.get_node_count():
		if st.get_node_name(i) == marker and str(st.get_node_path(i, true)).ends_with("Markers"):
			return true
	return false


func _all(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		out.append(c)
		out.append_array(_all(c))
	return out


# ---------- 2) 금 간 벽 ----------
func _probe_cracked_wall() -> void:
	Progress.reset()
	var holder := Node2D.new()
	add_child(holder)
	var src := Node2D.new()
	src.position = Vector2(500, 1000)
	holder.add_child(src)
	var wall: CrackedWall = load("res://scenes/world/cracked_wall.tscn").instantiate()
	wall.position = Vector2(600, 700)
	wall.secret_id = "cracked_probe_1"
	holder.add_child(wall)
	await _frames(2)
	var r1: String = wall.receive_hit(_hit(32.0, 60.0, src), null)
	var r2: String = wall.receive_hit(_hit(12.0, 20.0, src), null)
	_check(r1 == "blocked" and r2 == "blocked" and not wall.is_broken() and not Progress.is_collected("cracked_probe_1"), "능력 없음: 무거운 공격·약공격 모두 튕김(%s/%s), 안 부서짐" % [r1, r2])
	Progress.gain_ability("wall_break")
	var ra: String = wall.receive_hit(_hit(12.0, 20.0, src), null)
	var rb: String = wall.receive_hit(_hit(12.0, 20.0, src), null)
	var broke_after_two := wall.is_broken()
	var rc: String = wall.receive_hit(_hit(18.0, 32.0, src), null)
	_check(ra == "hit" and rb == "hit" and not broke_after_two and rc == "hit" and wall.is_broken() and Progress.is_collected("cracked_probe_1"), "능력 있음: 약공격 3대에 부서짐 (2대 뒤 %s, 3대 뒤 %s), collected 저장 %s" % [broke_after_two, wall.is_broken(), Progress.is_collected("cracked_probe_1")])
	var rd: String = wall.receive_hit(_hit(12.0, 20.0, src), null)
	_check(rd == "ignored", "부서진 뒤 공격은 무시(%s)" % rd)
	# 무거운 공격 한 대
	var wall2: CrackedWall = load("res://scenes/world/cracked_wall.tscn").instantiate()
	wall2.position = Vector2(900, 700)
	wall2.secret_id = "cracked_probe_2"
	holder.add_child(wall2)
	await _frames(2)
	var re: String = wall2.receive_hit(_hit(32.0, 60.0, src), null)
	_check(re == "hit" and wall2.is_broken(), "씨앗 베기(흐트러짐 60) 한 대에 부서짐 (%s)" % re)
	# 저장 복원: 같은 id 로 다시 만들면 부서진 채
	var wall3: CrackedWall = load("res://scenes/world/cracked_wall.tscn").instantiate()
	wall3.position = Vector2(1200, 700)
	wall3.secret_id = "cracked_probe_2"
	holder.add_child(wall3)
	await _frames(2)
	_check(wall3.is_broken() and not wall3.visible, "다시 만들면(세이브 복원) 부서진 채로 시작")
	holder.queue_free()
	await _frames(2)
	Progress.reset()


# ---------- 3) 잠긴 채굴장 포탈 ----------
func _probe_portal_lock() -> void:
	Progress.reset()
	var holder := Node2D.new()
	add_child(holder)
	var portal: Portal = load("res://scenes/world/portal.tscn").instantiate()
	portal.target_scene = "res://scenes/rooms/flooded_mine_01.tscn"
	portal.spawn_name = "FromMineDeep"
	portal.requires_ability = "sap_walk"
	holder.add_child(portal)
	var p: Player = load("res://scenes/player/player.tscn").instantiate()
	holder.add_child(p)
	p.set_physics_process(false)
	await _frames(2)
	Progress.next_spawn = ""
	portal._enter(p)
	await _frames(2)
	_check(not portal._used and Progress.next_spawn == "" and p.input_enabled, "sap_walk 없음: 잠긴 길 (건너가지 않음, 입력 안 잠김)")
	# 책임자의 방에 link 가 적용돼 있으면 그 포탈·자리·웅덩이도 본다
	var deep = load("res://scenes/rooms/mine_deep.tscn").instantiate()
	add_child(deep)
	await _frames(3)
	var to_flooded: Node = deep.get_node_or_null("Exits/ToFlooded")
	if to_flooded:
		var pools := 0
		for n in _all(deep):
			if n is SapPool:
				pools += 1
		_check(to_flooded.requires_ability == "sap_walk" and deep.get_node_or_null("Markers/FromFlooded") != null and pools == 3 and deep.bounds.size.x == 4800,
			"책임자의 방: 잠긴 채굴장 포탈(sap_walk) %s, FromFlooded 자리, 수액 웅덩이 %d, 너비 %d" % [to_flooded.target_scene.get_file(), pools, int(deep.bounds.size.x)])
		var fix: Node = deep.get_node_or_null("MapFix")
		_check(fix != null and fix.moves.has("abyss_01"), "책임자의 방: 옛 저장 지도 바로잡기 노드 MapFix (심연 방 %s)" % [fix.moves.keys() if fix else []])
	elif _linked:
		_check(false, "연결(--linked): 책임자의 방에 잠긴 채굴장 포탈(ToFlooded)이 없다 — tools/link_flooded_mine.py 를 돌려야 한다")
	else:
		print("[probe] (책임자의 방에 link_flooded_mine.py 가 아직 적용되지 않았다 — 잠긴 채굴장 포탈 확인 생략)")
	deep.queue_free()
	holder.queue_free()
	await _frames(2)
	Progress.reset()


# ---------- 8) 대사 데이터 ----------
func _probe_data() -> void:
	var npcs: Dictionary = DialogueData.load_dialogue("res://data/dialogue/npcs.json")
	var owen_ok := false
	for t in npcs.get("owen", {}).get("talks", []):
		if t.get("when", "") == "boss_pump_defeated":
			owen_ok = true
	var tia_ok := false
	for t in npcs.get("tia", {}).get("talks", []):
		if str(t.get("when", "")).begins_with("five_souls"):
			tia_ok = true
	_check(owen_ok and tia_ok and npcs.has("miner_hidden") and npcs["miner_hidden"].get("reward", {}).get("type", "") == "max_hp", "npcs_mine: 오웬(펌프 뒤) %s, 티아(five_souls) %s, 광부 하론 %s" % [owen_ok, tia_ok, npcs.has("miner_hidden")])
	# 티아: five_souls 대사는 1편의 한 번뿐인 대화(등불 건네기·재회)를 가리지 않고, 한 번 말하면 원래 대사로 돌아간다
	Progress.reset()
	var npc: Npc = load("res://scenes/npcs/npc.tscn").instantiate()
	npc.npc_id = "tia"
	add_child(npc)
	await _frames(1)
	var seq: Array = []
	Progress.set_flag("five_souls")
	seq.append(str(npc.pick_talk().get("when", "")))         # 등불을 아직 안 받음 → 등불 건네기
	Progress.set_flag("has_tia_lantern")
	seq.append(str(npc.pick_talk().get("when", "")))         # 오웬을 아직 못 구함 → five_souls (한 번)
	Progress.set_flag("owen_rescued")
	seq.append(str(npc.pick_talk().get("when", "")))         # 재회가 남음 → 재회 먼저
	Progress.set_flag("reunion_done")
	var t_five: Dictionary = npc.pick_talk()
	seq.append(str(t_five.get("when", "")))                  # 재회 뒤 → five_souls
	Progress.set_flag(str(t_five.get("set", "")))           # 말하고 나면 깃발이 선다
	seq.append(str(npc.pick_talk().get("when", "")))         # → 원래 마지막 대사
	var ok_seq: bool = seq[0] == "!has_tia_lantern" and seq[1].begins_with("five_souls") and seq[2] == "owen_rescued,!reunion_done" \
		and seq[3].begins_with("five_souls") and seq[4] == "reunion_done" and t_five.get("set", "") == "tia_told_five_souls"
	_check(ok_seq, "티아 대사 고르기 (five_souls 가 선 뒤): %s" % [seq])
	npc.queue_free()
	var recs: Dictionary = DialogueData.load_dialogue("res://data/dialogue/records.json")
	var pieces := recs.has("scripture_1") and recs.has("scripture_2") and recs.has("scripture_3") and recs.has("scripture_4") and recs.has("blueprint_piece")
	var extra: Array = recs.get("scripture_village", {}).get("extra", [])
	_check(pieces and extra.size() == 1 and extra[0].get("when", "").contains("read_scripture_4") and recs["scripture_village"].has("lines"), "records_mine: 경전 조각 4 + 설계도, 사당 경전에 완성 구절(extra, 조건 %s) 이어짐" % [extra[0].get("when", "") if extra.size() > 0 else "-"])
	var mems: Dictionary = DialogueData.load_dialogue("res://data/dialogue/memories.json")
	var ends: Dictionary = DialogueData.load_dialogue("res://data/dialogue/endings.json")
	# 제3의 길: ENDINGS.md 3-1장 — 장면 9개, 진엔딩 그림 5장(ending_true_1~5, 옛 ending_third_way 한 장을 대신함). 자세한 시험은 probe_endings.
	var third_scenes: Array = ends.get("third", {}).get("scenes", [])
	var third_imgs := {}
	for sc in third_scenes:
		third_imgs[str(sc.get("image", "")).get_file()] = true
	var five_imgs := third_imgs.has("ending_true_1.png") and third_imgs.has("ending_true_2.png") and third_imgs.has("ending_true_3.png") and third_imgs.has("ending_true_4.png") and third_imgs.has("ending_true_5.png")
	_check(mems.get("memory_pump", {}).get("lines", []).size() == 4 and third_scenes.size() == 9 and five_imgs,
		"memories_mine(펌프 회상 %d줄), endings_mine(제3의 길 장면 %d개, 진엔딩 그림 5장 %s)" % [mems.get("memory_pump", {}).get("lines", []).size(), third_scenes.size(), five_imgs])
	Progress.reset()


# ---------- 7) 회상 곡 ----------
func _probe_memory_theme() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/ui/memory_scene.gd")
	_check(Music.RECOLLECTION == "recollection" and ResourceLoader.exists(Music.DIR + "recollection.wav") and src.contains("Music.play(Music.RECOLLECTION") and not src.contains("theme_for"),
		"회상 곡: 모든 회상이 %s (정식 곡 한 곡, 보스 수에 따라 길어지는 임시 주제곡 없음)" % Music.RECOLLECTION)
	Progress.reset()
	Progress.set_flag("boss_bird_defeated")
	Progress.set_flag("boss_knight_defeated")
	Progress.set_flag("miniboss_canopy_defeated")
	Progress.set_flag("boss_pump_defeated")
	var n: int = MemoryScene.purified_boss_count()
	_check(n == 3, "정화한 보스 수 세기: 새·기사·펌프(+중간 보스는 안 셈) = %d" % n)
	Progress.reset()


# ---------- 4) 작은 펌프 ----------
func _probe_small_pump() -> void:
	Progress.reset()
	var pump: SmallPump = load("res://scenes/enemies/small_pump.tscn").instantiate()
	pump.position = Vector2(1200, 930)
	add_child(pump)
	_player.global_position = Vector2(600, 1000)
	var times: Array = []
	var t := [0.0]
	pump.shot.connect(func() -> void: times.append(t[0]))
	for i in 440:
		await get_tree().physics_frame
		t[0] += DT
	var gaps: Array = []
	for i in range(1, times.size()):
		gaps.append(snappedf(times[i] - times[i - 1], 0.01))
	var ok := times.size() >= 3
	for g in gaps:
		if absf(g - pump.rhythm) > 0.12:
			ok = false
	_check(ok, "작은 펌프 리듬: 7.3초 동안 %d발, 간격 %s (기준 %.1f초 ±0.12)" % [times.size(), gaps, pump.rhythm])
	var hp0 := pump.hp
	pump.receive_hit(_hit(12.0, 20.0), null)
	var light_drop := hp0 - pump.hp
	hp0 = pump.hp
	pump.receive_hit(_hit(32.0, 60.0), null)
	var heavy_drop := hp0 - pump.hp
	_check(is_equal_approx(light_drop, 6.0) and is_equal_approx(heavy_drop, 32.0), "작은 펌프 장갑: 약공격 12 → %.1f (절반), 씨앗 베기 32 → %.1f" % [light_drop, heavy_drop])
	for p in get_tree().get_nodes_in_group("projectile"):
		p.queue_free()
	pump.queue_free()
	await _frames(2)


# ---------- 이슬잔 ----------
func _probe_dew_cup() -> void:
	Progress.reset()
	_player._apply_abilities()
	var cup: DewCup = load("res://scenes/world/dew_cup.tscn").instantiate()
	cup.position = Vector2(700, 940)
	cup.pickup_id = "pick_probe_cup"
	add_child(cup)
	await _frames(2)
	var before := _player.max_dews
	cup._collect(_player)
	await _frames(3)
	_check(_player.max_dews == before + 1 and Progress.is_collected("pick_probe_cup") and is_equal_approx(float(Progress.upgrades.get("dews", 0)), 1.0), "이슬잔: 모으면 이슬 최대 %d → %d, collected %s" % [before, _player.max_dews, Progress.is_collected("pick_probe_cup")])
	cup.queue_free()
	await _frames(2)
	Progress.reset()


# ---------- 6) 경비병 방패 · 기계 장갑 ----------
func _probe_guard_machine() -> void:
	Progress.reset()
	var guard: Guard = load("res://scenes/enemies/guard.tscn").instantiate()
	guard.position = Vector2(1400, 930)
	add_child(guard)
	_player.global_position = Vector2(1200, 1000)   # 경비병(왼쪽을 봄)의 정면
	await _frames(40)
	guard._set_state(EnemyBase.State.IDLE)
	guard.facing = -1
	await _frames(20)
	var r_no: String = guard.receive_hit(_hit(32.0, 60.0), null)
	Progress.gain_ability("wall_break")
	var p0 := guard.poise
	var r_yes: String = guard.receive_hit(_hit(32.0, 60.0), null)
	_check(r_no == "blocked" and r_yes == "hit" and guard.poise - p0 >= 40.0, "경비병 방패: 벽 부수기 없음 %s / 있음+씨앗 베기 %s (흐트러짐 +%.0f, 방패 열림 %s)" % [r_no, r_yes, guard.poise - p0, guard._block_open > 0.0])
	guard.queue_free()
	Progress.reset()
	var m: Machine = load("res://scenes/enemies/machine.tscn").instantiate()
	m.position = Vector2(1400, 930)
	add_child(m)
	await _frames(10)
	var hp0 := m.hp
	m.receive_hit(_hit(12.0, 20.0), null)
	var light1 := hp0 - m.hp
	Progress.gain_ability("wall_break")
	hp0 = m.hp
	m.receive_hit(_hit(32.0, 60.0), null)
	var heavy := hp0 - m.hp
	hp0 = m.hp
	m.receive_hit(_hit(12.0, 20.0), null)
	var light2 := hp0 - m.hp
	_check(is_equal_approx(light1, 12.0 * 0.35) and is_equal_approx(heavy, 32.0) and m.is_armor_broken() and is_equal_approx(light2, 12.0), "기계 장갑: 약공격 %.1f(35%%) → 벽 부수기+씨앗 베기 %.0f 로 장갑 깨짐(%s) → 약공격 %.1f(온전히)" % [light1, heavy, m.is_armor_broken(), light2])
	m.queue_free()
	await _frames(2)
	Progress.reset()


# ---------- 5) 무쇠 펌프 ----------
func _probe_iron_pump() -> void:
	Progress.reset()
	var boss: IronPump = load("res://scenes/bosses/iron_pump.tscn").instantiate()
	boss.position = Vector2(2600, 1000)
	add_child(boss)
	boss.arena = Rect2(760, 200, 2680, 800)
	boss.ground_y = 1000.0
	_player.global_position = Vector2(1600, 932)   # 발이 바닥(1000) 위 (빨아들이기가 소녀를 실제로 옮긴다)
	await _frames(2)
	boss.start_fight(_player)
	# 1페이즈 순서: 피스톤 → 분사 → 빨아들이기 → 피스톤 (약 2.2 + 4×(예고+실행+회복+쉼) ≈ 18초)
	var labels := [boss.telegraph_label("piston"), boss.telegraph_label("spray"), boss.telegraph_label("suck"), boss.telegraph_label("x")]
	_check(labels == ["피스톤!", "수액 분사!", "빨아들이기!", ""], "예고 글자: %s" % [labels])
	var pulled_max := 0.0
	var x_before_suck := 0.0
	var x_after_suck := 0.0
	var suck_len := 0.0
	var startup_seen := {}
	var t := 0.0
	while t < 22.0 and boss.attack_log.size() < 4:
		await get_tree().physics_frame
		t += DT
		if boss.state == IronPump.State.SUCK and boss.attack_phase == "active":
			if suck_len == 0.0:
				x_before_suck = _player.global_position.x
			suck_len += DT
			pulled_max = maxf(pulled_max, boss.pulled)
			x_after_suck = _player.global_position.x
		if boss.attack_phase == "startup" and not startup_seen.has(boss.state_name()):
			startup_seen[boss.state_name()] = snappedf(boss.startup_len, 0.001)
	var order: Array = boss.attack_log.slice(0, 4)
	_check(order == ["PISTON", "SPRAY", "SUCK", "PISTON"], "1페이즈 순서 (%.1f초): %s" % [t, order])
	var beat := IronPump.BEAT
	_check(is_equal_approx(startup_seen.get("PISTON", 0.0), snappedf(2.0 * beat, 0.001)) and is_equal_approx(startup_seen.get("SPRAY", 0.0), snappedf(2.0 * beat, 0.001)) and is_equal_approx(startup_seen.get("SUCK", 0.0), snappedf(1.5 * beat, 0.001)),
		"1페이즈 예고 길이 (박 %.4f초): %s" % [beat, startup_seen])
	var moved := x_after_suck - x_before_suck
	_check(suck_len > 1.5 and pulled_max > 300.0 and moved > 300.0, "빨아들이기: %.1f초 동안 소녀를 펌프 쪽으로 %.0fpx 옮김 (기록 %.0f)" % [suck_len, moved, pulled_max])
	# 장갑: 약공격 35%·장갑 절반, 무거운 공격 온전히, 되받은 분사 ×1.5 + 장갑 +40
	await _wait_state(boss, IronPump.State.IDLE, 6.0)
	boss.poise = 0.0
	var hp0 := boss.hp
	boss.receive_hit(_hit(12.0, 20.0), null)
	var light := hp0 - boss.hp
	var armor_light := boss.poise
	hp0 = boss.hp
	boss.receive_hit(_hit(32.0, 60.0), null)
	var heavy := hp0 - boss.hp
	hp0 = boss.hp
	var p_before := boss.poise
	var refl := HitData.make(14.0 * 1.6, 28.0, boss)   # Projectile._reflect 뒤의 값 (출처 = 펌프 자신)
	refl.from_player = true
	boss.receive_hit(refl, null)
	var reflected := hp0 - boss.hp
	_check(is_equal_approx(light, 12.0 * 0.35) and is_equal_approx(armor_light, 10.0) and is_equal_approx(heavy, 32.0) and is_equal_approx(reflected, 14.0 * 1.6 * 1.5) and is_equal_approx(boss.poise - p_before, boss.reflect_poise),
		"장갑: 약공격 12 → %.1f(장갑 +%.0f), 씨앗 베기 32 → %.0f, 되받은 분사 22.4 → %.1f(장갑 +%.0f)" % [light, armor_light, heavy, reflected, boss.poise - p_before])
	boss.poise = boss.max_poise - 1.0
	boss.receive_hit(_hit(1.0, 60.0), null)
	var broken := boss.state == IronPump.State.BROKEN
	hp0 = boss.hp
	boss.receive_hit(_hit(12.0, 20.0), null)
	var broken_light := hp0 - boss.hp
	_check(broken and is_equal_approx(broken_light, 24.0) and boss.hitbox.monitoring == false, "장갑이 가득 차면 BROKEN(%s): 약공격 12 → %.0f (×2)" % [broken, broken_light])
	# 2페이즈: 순서 무작위·예고 ±30%·수액 기둥
	boss.hp = boss.max_hp * 0.45
	boss.receive_hit(_hit(1.0, 0.0), null)
	_check(boss.phase == 2 and boss.state == IronPump.State.BROKEN, "체력 절반 → 2페이즈 (장갑이 깨진 채면 휘청 없이 빈틈 유지): 페이즈 %d, 상태 %s" % [boss.phase, boss.state_name()])
	# 장갑이 멀쩡할 때 절반이 되면 휘청(STAGGER)을 거친다
	var boss2: IronPump = load("res://scenes/bosses/iron_pump.tscn").instantiate()
	boss2.position = Vector2(3000, 1000)
	add_child(boss2)
	boss2.arena = boss.arena
	boss2.ground_y = 1000.0
	await _frames(2)
	boss2.start_fight(_player)
	await _wait_state(boss2, IronPump.State.IDLE, 4.0)
	boss2.hp = boss2.max_hp * 0.45
	boss2.receive_hit(_hit(1.0, 0.0), null)
	_check(boss2.phase == 2 and boss2.state == IronPump.State.STAGGER, "장갑 멀쩡할 때 절반 → 휘청(STAGGER): 페이즈 %d, 상태 %s" % [boss2.phase, boss2.state_name()])
	boss2.queue_free()
	var log_start := boss.attack_log.size()
	var startups: Array = []
	var last_logged := log_start
	var spurts := 0
	t = 0.0
	while t < 26.0 and boss.attack_log.size() < log_start + 5:
		await get_tree().physics_frame
		t += DT
		if boss.attack_log.size() > last_logged:
			last_logged = boss.attack_log.size()
			startups.append(snappedf(boss.startup_len, 0.01))
		for n in get_tree().get_nodes_in_group("projectile"):
			if n is SapSpurt and not n.has_meta("counted"):
				n.set_meta("counted", true)
				spurts += 1
	var p2: Array = boss.attack_log.slice(log_start, log_start + 5)
	var fixed := [2.0 * beat, 2.0 * beat, 1.5 * beat]
	var jittered := false
	for s in startups:
		var hit_fixed := false
		for f in fixed:
			if absf(s - f) < 0.02 or absf(s - f * 0.75) < 0.02:
				hit_fixed = true
		if not hit_fixed:
			jittered = true
	var no_repeat := true
	for i in range(1, p2.size()):
		if p2[i] == p2[i - 1]:
			no_repeat = false
	_check(p2.size() == 5 and no_repeat and jittered and spurts >= 2, "2페이즈 (%.1f초): 공격 %s (같은 것 연속 없음 %s), 예고 %s (엇박 %s), 수액 기둥 %d" % [t, p2, no_repeat, startups, jittered, spurts])
	# 쓰러짐 → 정화
	boss.hp = 1.0
	boss.receive_hit(_hit(5.0, 0.0), null)
	await _frames(5)
	var fallen := boss.state == IronPump.State.FALLEN
	boss.purified_by(_player)
	_check(fallen and boss.state == IronPump.State.PURIFIED, "체력 0 → FALLEN(%s) → 정화 → PURIFIED(%s)" % [fallen, boss.state_name()])
	for n in get_tree().get_nodes_in_group("projectile"):
		n.queue_free()
	boss.queue_free()
	await _frames(2)


func _wait_state(boss: IronPump, st: IronPump.State, limit: float) -> void:
	var t := 0.0
	while boss.state != st and t < limit:
		await get_tree().physics_frame
		t += DT


# ---------- 9) 제3의 길 ----------
func _probe_third_way() -> void:
	Progress.reset()
	var c1: EndingChoice = load("res://scenes/world/ending_choice.tscn").instantiate()
	c1.choice = "third"
	c1.label = "심연의 거대한 펌프를 거꾸로 돌린다"
	add_child(c1)
	await _frames(1)
	_check(c1.is_locked() and not c1.visible and not Progress.has("five_souls"), "세 번째 선택지: 네 능력 없음 → 숨김(%s), five_souls 깃발 없음" % (not c1.visible))
	c1.queue_free()
	for a in ["wind", "light", "sap_walk", "wall_break"]:
		Progress.gain_ability(a)
	var c1b: EndingChoice = load("res://scenes/world/ending_choice.tscn").instantiate()
	c1b.choice = "third"
	add_child(c1b)
	await _frames(1)
	_check(c1b.is_locked() and not c1b.visible and not Progress.has("five_souls"), "세 번째 선택지: 네 능력은 있지만 뿌리지기 정화 깃발 없음 → 숨김(%s)" % (not c1b.visible))
	c1b.queue_free()
	# 1편 두 선택지는 영혼 수와 상관없이 늘 열려 있다
	var c_sac: EndingChoice = load("res://scenes/world/ending_choice.tscn").instantiate()
	c_sac.choice = "sacrifice"
	add_child(c_sac)
	await _frames(1)
	_check(not c_sac.is_locked() and c_sac.visible, "1편 선택지(희생)는 잠기지 않는다")
	c_sac.queue_free()
	Progress.set_flag("boss_root_defeated")
	var c2: EndingChoice = load("res://scenes/world/ending_choice.tscn").instantiate()
	c2.choice = "third"
	add_child(c2)
	await _frames(1)
	_check(not c2.is_locked() and c2.visible and Progress.has("five_souls"), "세 번째 선택지: 네 능력 있음 → 보임(%s), five_souls 깃발 %s" % [c2.visible, Progress.has("five_souls")])
	# 엔딩 씬: "third" 로 뜨는지 (음악·깃발·저장)
	Progress.ending = "third"
	Progress.last_grass = {}
	var ending = load("res://scenes/ui/ending_scene.tscn").instantiate()
	add_child(ending)
	await _frames(2)
	var title: String = ending.get_node("Title").text
	var tex: Texture2D = ending.front_texture()
	_check(title == "제3의 길" and tex != null and tex.resource_path.ends_with("ending_true_1.png") and ending._scenes.size() == 9 and Progress.has("cleared") and Progress.has("cleared_third") and Progress.has("ending_third"),
		"엔딩 씬: 제목 '%s', 첫 그림 %s, 장면 %d개, 깃발 cleared/cleared_third/ending_third %s/%s/%s" % [title, tex.resource_path.get_file() if tex else "없음", ending._scenes.size(), Progress.has("cleared"), Progress.has("cleared_third"), Progress.has("ending_third")])
	ending.queue_free()
	c2.queue_free()
	Progress.reset()


## 선택 → ending "third". 3초 뒤 장면이 엔딩으로 바뀌므로 **시험의 맨 마지막**에 부른다 (그 전에 끝내고 quit).
func _probe_third_interact() -> void:
	Progress.reset()
	for a in ["wind", "light", "sap_walk", "wall_break"]:
		Progress.gain_ability(a)
	Progress.set_flag("boss_root_defeated")
	var c2: EndingChoice = load("res://scenes/world/ending_choice.tscn").instantiate()
	c2.choice = "third"
	add_child(c2)
	var p: Player = load("res://scenes/player/player.tscn").instantiate()
	add_child(p)
	p.set_physics_process(false)
	await _frames(1)
	Progress.ending = ""
	c2.interact(p)
	await _frames(1)
	_check(Progress.ending == "third" and not p.input_enabled, "선택지 interact → Progress.ending '%s', 연출 중 입력 잠김" % Progress.ending)


# ---------- 10) 회상에서 돌아온 무쇠 펌프 방 ----------
func _probe_after_memory() -> void:
	Progress.reset()
	# BossRoom 이 회상 전에 세우는 깃발만 있고 after_ 깃발은 없다 = 회상에서 막 돌아온 상태
	Progress.set_flag("boss_pump_defeated")
	Progress.next_spawn = "AfterBoss"
	var room = load("res://scenes/rooms/flooded_mine_boss.tscn").instantiate()
	add_child(room)
	await _frames(2)
	var remains: Node2D = room.get_node_or_null("PumpRemains")
	var t := 0.0
	while t < 9.0 and not Progress.has_ability("wall_break"):
		await get_tree().physics_frame
		t += DT
	var boss_gone: bool = not is_instance_valid(room.boss) or room.boss.is_queued_for_deletion()
	_check(Progress.has_ability("wall_break") and Progress.has("after_boss_pump_defeated") and remains != null and remains.visible and boss_gone and Purity.regions.get("flooded_mine", false),
		"회상 뒤 펌프 방: %.1f초 만에 벽 부수기 %s, after 깃발 %s, 멈춘 펌프+싹 보임 %s, 보스 사라짐 %s, 지역 정화 %s" % [
		t, Progress.has_ability("wall_break"), Progress.has("after_boss_pump_defeated"), remains != null and remains.visible, boss_gone, Purity.regions.get("flooded_mine", false)])
	await _frames(240)   # 보상 연출(입력 잠금 3.6초)이 끝나게
	room.queue_free()
	await _frames(2)
	Purity.reset_region("flooded_mine")
	Progress.reset()


# ---------- 11) 엔딩 뒤 이어서 탐험 ----------
func _probe_ending_continue() -> void:
	var had := SaveGame.has_save()
	var backup := FileAccess.get_file_as_string(SaveGame.PATH) if had else ""
	Progress.reset()
	for a in ["double_jump", "wind", "light", "lantern", "sap_walk", "wall_break"]:
		Progress.gain_ability(a)
	for f in ["boss_bird_defeated", "boss_knight_defeated", "boss_pump_defeated", "boss_root_defeated", "after_boss_root_defeated"]:
		Progress.set_flag(f)
	Progress.grasses["moon_garden"] = {"scene": "res://scenes/rooms/moon_garden.tscn", "name": "달빛 정원"}
	Progress.last_grass = {"id": "moon_garden", "scene": "res://scenes/rooms/moon_garden.tscn", "name": "달빛 정원"}
	Progress.collect("cracked_mine_02_1")
	Progress.ending = "third"
	var ending = load("res://scenes/ui/ending_scene.tscn").instantiate()
	add_child(ending)
	await _frames(2)
	var saved := SaveGame.has_save()
	ending.queue_free()
	await _frames(1)
	var st: Dictionary = load("res://scripts/ui/title_screen.gd").cleared_state()
	Progress.reset()
	var st_fresh: Dictionary = load("res://scripts/ui/title_screen.gd").cleared_state()   # 앱을 새로 켠 것처럼 (진행이 비었을 때)
	var scene := SaveGame.load_game()
	_check(saved and st["cleared"] and st["third"] and st_fresh["cleared"] and st_fresh["third"],
		"엔딩 씬이 저장 %s → 타이틀 클리어 표시 (진행 있음 %s/%s, 새로 켬 %s/%s)" % [saved, st["cleared"], st["third"], st_fresh["cleared"], st_fresh["third"]])
	_check(scene == "res://scenes/rooms/moon_garden.tscn" and Progress.next_spawn == "Grass:moon_garden" and Progress.has("cleared_third") and Progress.ending == "third" \
		and Progress.has_ability("wall_break") and Progress.is_collected("cracked_mine_02_1"),
		"이어하기: 방 %s, 등장 %s, 깃발 cleared_third %s, 엔딩 '%s', 벽 부수기 %s, 부순 벽 기억 %s" % [scene.get_file(), Progress.next_spawn, Progress.has("cleared_third"), Progress.ending, Progress.has_ability("wall_break"), Progress.is_collected("cracked_mine_02_1")])
	# 기기의 저장 파일을 시험 전으로 되돌린다
	if had:
		var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
		f.store_string(backup)
		f.close()
	else:
		DirAccess.remove_absolute(SaveGame.PATH)
	Progress.reset()


# ---------- 12) 수액 방울 실제 비행 ----------
## 쏘고(fire) → 소녀가 가드한 채로 저스트 가드 시각을 계속 새로 해 두면 방울이 닿는 순간 되받는다. 결과: 되받음·쏜 쪽 피해·사라진 자리·소녀와 가장 가까웠던 거리.
func _blob_once(shooter: Node2D, fire: Callable, at: Vector2, guard := true) -> Dictionary:
	_player.global_position = at
	_player.velocity = Vector2.ZERO
	_player.facing = 1 if shooter.global_position.x > at.x else -1
	_player.state = Player.State.GUARD if guard else Player.State.IDLE
	_player._invuln_timer = 0.0 if guard else 9999.0
	var hp0: float = shooter.hp
	var before := get_tree().get_nodes_in_group("projectile")
	fire.call()
	var blob: SapBlob = null
	for n in get_tree().get_nodes_in_group("projectile"):
		if n is SapBlob and not before.has(n):
			blob = n
	var out := {"reflected": false, "dmg": 0.0, "end": Vector2.ZERO, "min_d": INF, "blob": blob != null}
	if blob == null:
		return out
	blob.reflected.connect(func(_pr: Projectile) -> void: out["reflected"] = true)
	var t := 0.0
	while t < 3.2 and is_instance_valid(blob) and not blob._dead:
		if guard:
			_player._guard_pressed_at = _player._now()
		out["min_d"] = minf(out["min_d"], blob.global_position.distance_to(_player.global_position))
		out["end"] = blob.global_position
		await get_tree().physics_frame
		t += DT
	out["dmg"] = hp0 - shooter.hp
	_player.state = Player.State.IDLE
	_player._invuln_timer = 9999.0
	await _frames(8)
	return out


func _probe_reflect_flight() -> void:
	Progress.reset()
	var boss: IronPump = load("res://scenes/bosses/iron_pump.tscn").instantiate()
	boss.position = Vector2(2600, 1000)
	add_child(boss)
	boss.arena = Rect2(760, 200, 2680, 800)
	boss.ground_y = 1000.0
	await _frames(3)
	boss.set_physics_process(false)
	boss.visible = true
	boss.player = _player
	boss._set_state(IronPump.State.IDLE)
	boss.facing = -1
	var lines: Array = []
	var ok := true
	for d in [300.0, 420.0, 600.0, 800.0]:
		boss.hp = boss.max_hp
		boss.poise = 0.0
		var r: Dictionary = await _blob_once(boss, func() -> void: boss._spray(), Vector2(2600.0 - d, 932.0))
		var good: bool = r["blob"] and r["reflected"] and is_equal_approx(r["dmg"], 14.0 * 1.6 * 1.5)
		ok = ok and good
		lines.append("%d: 되받음 %s 피해 %.1f 장갑 %.0f" % [d, r["reflected"], r["dmg"], boss.poise])
	_check(ok, "무쇠 펌프 방울 되받기 (거리별, 저스트 가드 45 + 되받은 방울 15): %s" % [lines])
	boss.queue_free()
	await _frames(2)
	var pump: SmallPump = load("res://scenes/enemies/small_pump.tscn").instantiate()
	pump.position = Vector2(2600, 940)
	add_child(pump)
	await _frames(3)
	pump.set_physics_process(false)
	pump.player = _player
	pump.facing = -1
	lines.clear()
	ok = true
	for d in [300.0, 450.0, 600.0, 690.0]:
		pump.hp = pump.max_hp
		var r: Dictionary = await _blob_once(pump, func() -> void: pump._shoot(), Vector2(2600.0 - d, 932.0))
		var good: bool = r["blob"] and r["reflected"] and is_equal_approx(r["dmg"], 12.0 * 1.6 * pump.reflect_damage_multiplier)
		ok = ok and good
		lines.append("%d: 되받음 %s 피해 %.1f" % [d, r["reflected"], r["dmg"]])
	_check(ok, "작은 펌프 방울 되받기 (거리별, ×1.5 온전히): %s" % [lines])
	var far: Dictionary = await _blob_once(pump, func() -> void: pump._shoot(), Vector2(2600.0 - pump.shoot_range + 10.0, 932.0), false)
	_check(far["blob"] and far["min_d"] < 60.0, "작은 펌프 사거리 끝(%.0f)에서도 방울이 소녀에게 닿는다 (가장 가까이 %.0fpx)" % [pump.shoot_range - 10.0, far["min_d"]])
	pump.queue_free()
	for n in get_tree().get_nodes_in_group("projectile"):
		n.queue_free()
	await _frames(2)


# ---------- 13) 피스톤 판정 ----------
func _probe_piston_reach() -> void:
	var boss: IronPump = load("res://scenes/bosses/iron_pump.tscn").instantiate()
	boss.position = Vector2(2600, 1000)
	add_child(boss)
	boss.arena = Rect2(760, 200, 2680, 800)
	boss.ground_y = 1000.0
	await _frames(3)
	boss.set_physics_process(false)
	boss.visible = true
	boss.player = _player
	boss._set_state(IronPump.State.IDLE)
	boss.facing = -1
	var got := {}
	for d in [300.0, 450.0]:
		_player.global_position = Vector2(2600.0 - d, 932.0)
		_player.state = Player.State.IDLE
		_player.hp = _player.max_hp
		var log: Array = []
		var cb := func(dmg: float) -> void: log.append(int(round(dmg)))
		_player.hit_taken.connect(cb)
		boss._slam()
		for i in 30:
			_player._invuln_timer = 0.0
			_player.state = Player.State.IDLE
			await get_tree().physics_frame
		_player.hit_taken.disconnect(cb)
		boss.hitbox.deactivate()
		for n in get_tree().get_nodes_in_group("projectile"):
			n.queue_free()
		got[d] = log
		await _frames(3)
	_player._invuln_timer = 9999.0
	_player.hp = _player.max_hp
	_check(got[300.0].has(28) and not got[450.0].has(28) and got[450.0].has(16), "피스톤 판정: 300 에 서면 %s (피스톤 28 포함), 450 이면 %s (피스톤 없음, 충격파 16)" % [got[300.0], got[450.0]])
	boss.queue_free()
	await _frames(2)


# ---------- 14) 빨아들이기 실제 물리 ----------
func _probe_suck_real() -> void:
	Progress.reset()
	Progress.gain_ability("sap_walk")
	Progress.next_spawn = "FromFlooded02"
	var room = load("res://scenes/rooms/flooded_mine_boss.tscn").instantiate()
	add_child(room)
	await _frames(3)
	var player: Player = room.player
	var boss: IronPump = room.boss
	player._invuln_timer = 9999.0
	player.global_position = Vector2(1500, 1430)
	var res: Array = []
	for mode in ["stand", "run_away"]:
		# 다음 빨아들이기 예고가 시작될 때 소녀를 펌프 앞 520 에 세운다
		var t := 0.0
		while t < 20.0 and not (boss.state == IronPump.State.SUCK and boss.attack_phase == "startup"):
			player._invuln_timer = 9999.0
			await get_tree().physics_frame
			t += DT
		player.global_position.x = boss.global_position.x + boss.facing * 520.0
		player.velocity = Vector2.ZERO
		while boss.state == IronPump.State.SUCK and boss.attack_phase == "startup":
			await get_tree().physics_frame
		var x0 := player.global_position.x
		var away := "move_left" if boss.facing < 0 else "move_right"
		if mode == "run_away":
			Input.action_press(away)
		while boss.state == IronPump.State.SUCK and boss.attack_phase == "active" and boss._timer > 0.25:
			player._invuln_timer = 9999.0
			await get_tree().physics_frame
		Input.action_release(away)
		var toward := (player.global_position.x - x0) * -boss.facing   # + 면 펌프 쪽으로 끌림
		res.append(toward)
		await _frames(2)
	_check(res.size() == 2 and res[0] > 300.0 and res[1] < -150.0, "빨아들이기 실제 물리: 가만히 서면 펌프 쪽으로 %.0fpx 끌림, 반대로 달리면 %.0fpx (벗어남)" % [res[0] if res.size() > 0 else 0.0, res[1] if res.size() > 1 else 0.0])
	room.queue_free()
	await _frames(3)
	for p in get_tree().get_nodes_in_group("projectile"):
		p.queue_free()
	Music.stop(0.0)
	Progress.reset()


# ---------- 15) 정화 순간의 멈춘 펌프 · 2페이즈 음악 · 옛 저장 지도 ----------
func _probe_remains_and_music() -> void:
	Progress.reset()
	Progress.gain_ability("sap_walk")
	if Progress.has_meta(IronPumpRoom.REMAINS_META):
		Progress.remove_meta(IronPumpRoom.REMAINS_META)
	var room = load("res://scenes/rooms/flooded_mine_boss.tscn").instantiate()
	add_child(room)
	await _frames(3)
	var remains: Node2D = room.get_node("PumpRemains")
	var hidden_before := not remains.visible
	room.boss.global_position.x = 2100.0
	room.boss.facing = 1
	room._on_pump_stopped()   # 정화의 손길 순간 (BossRoom 의 회상 이동은 부르지 않는다)
	await _frames(20)
	var shown: bool = remains.visible and absf(remains.global_position.x - 2100.0) < 1.0 and remains.scale.x < 0.0 and remains.modulate.a > 0.2
	for i in 110:
		await get_tree().physics_frame
	var grown: float = remains.grow
	# 2페이즈 음악: 곡은 그대로 두고 한 번 휘청인다
	Music.play(room.boss_track, 0.0, true)
	room.fight_started = true
	room._on_pump_phase(2)
	var track := Music.current()
	var faltered := Music.is_faltering()
	room.fight_started = false
	room.queue_free()
	await _frames(3)
	Music.stop(0.0)
	# 회상에서 돌아온 뒤 (깃발이 서 있음): 같은 자리·같은 방향
	Progress.set_flag("boss_pump_defeated")
	Progress.set_flag("after_boss_pump_defeated")
	Progress.next_spawn = "AfterBoss"   # 회상에서 돌아오는 자리 (1800 — 2100 의 멈춘 펌프 그림과 겹친다)
	var room2 = load("res://scenes/rooms/flooded_mine_boss.tscn").instantiate()
	add_child(room2)
	await _frames(3)
	var r2: Node2D = room2.get_node("PumpRemains")
	var kept: bool = r2.visible and absf(r2.position.x - 2100.0) < 1.0 and r2.scale.x < 0.0
	_check(hidden_before and shown and grown > 0.95 and kept, "정화 순간 멈춘 펌프+싹: 처음 숨김 %s → 펌프 자리(2100, 오른쪽을 봄)에 나타남 %s, 싹 자람 %.2f, 회상 뒤 같은 자리 %s" % [hidden_before, shown, grown, kept])
	# 회상에서 돌아온 소녀는 멈춘 펌프 그림 밖에 선다 (2026-10-20 검수: 대포 입구에 겹쳐 서 있었다)
	var span: Vector2 = r2.world_span()
	var px: float = room2.player.global_position.x if room2.player else INF
	_check(px < span.x or px > span.y, "회상 뒤 소녀 자리 x %.0f 가 멈춘 펌프 그림(%.0f ~ %.0f) 밖" % [px, span.x, span.y])
	_check(track == "boss_iron_pump" and faltered, "2페이즈 음악: 곡 그대로 %s, 휘청 %s" % [track, faltered])
	room2.queue_free()
	await _frames(3)
	Progress.remove_meta(IronPumpRoom.REMAINS_META)
	Music.stop(0.0)
	Progress.reset()


func _probe_map_fix() -> void:
	var fix := MapOffsetFix.new()
	fix.moves = {"abyss_01": [Vector2(39300, 500), Vector2(41100, 500)], "abyss_02": [Vector2(43500, 100), Vector2(45300, 100)], "moon_garden": [Vector2(47100, 300), Vector2(48900, 300)]}
	var rooms := {"abyss_01": {"offset": Vector2(39300, 500)}, "abyss_02": {"offset": Vector2(45300, 100)}, "mine_deep": {"offset": Vector2(35600, 500)}}
	var n := fix.fix(rooms)
	_check(n == 1 and rooms["abyss_01"]["offset"] == Vector2(41100, 500) and rooms["abyss_02"]["offset"] == Vector2(45300, 100) and rooms["mine_deep"]["offset"] == Vector2(35600, 500),
		"옛 저장 지도 바로잡기: 옛 자리만 새 자리로 (%d방 고침, abyss_01 %s, 이미 새 자리인 abyss_02 %s)" % [n, rooms["abyss_01"]["offset"], rooms["abyss_02"]["offset"]])
	fix.free()

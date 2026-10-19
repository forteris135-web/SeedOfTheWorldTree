extends Node
## Claude Code용 구원자 재배치 시험 (화면 없이 돈다).
## 실행: godot --headless --path . res://tools/probe_npcs.tscn
##       화면 있이 `-- --shots` 를 붙이면 screenshots/probe_npcs_*.png 도 남긴다 (들판 대화·사라짐·집·대화 상자).
##  0) 자료: 다섯 구원자 모두 relocations.json 항목(scene/position/texture 파일 있음)과 npcs.json 의 leave_line·home_lines 가 있고,
##     집 자리가 그 방의 바닥(Platform 윗면, one_way 아님) 위인지. **집 자리가 안전한지**: 그 방 적의 순찰 범위 + 발견 거리 안에
##     대화 자리(집 ±200)가 들어가지 않는지 (대화 상자 동안 소녀는 움직일 수 없다), 같은 바닥의 다른 말 걸기 대상과 250px 넘게 떨어졌는지.
##  1) 구원 전: 사당(village_shrine)에 나무꾼·경비병 집 NPC 가 없다 (등불지기·약초꾼 자리만).
##  2) canopy_01: 나무꾼을 정화 → 감사의 말 → 보상(최대 체력 +15, 화면 가운데 안내) → 말 걸기 ×2(talk_lines, 1초 넘게 띄운 뒤) →
##     한 번 더 → leave_line(글자 수만큼 떠 있음) → 빛 가루와 함께 사라짐 → 깃발 home_woodcutter_canopy.
##  3) 사당: 집 자리(1720, 1000)에 집 NPC, 말 걸면 대화 상자에 home_lines 첫 줄, boss_knight_defeated 뒤엔 조건 묶음.
##     손길로만 대화를 넘겨도 끝난 뒤 다시 열리지 않는다 (Dialogue 가 입력을 다음 틱에 돌려줌). 사람은 1.0 넘게 빛나지 않는다.
##  4) 세이브 왕복 뒤에도 사당에 있다. (기획자의 세이브 파일은 살려 둔다)
##  5) 같은 방이 집(시험용 덮어쓰기로 경비병 집을 village_01 로): 손길 연타(0.15초마다)에도 말풍선마다 1초 넘게 보이고,
##     감사의 말이 끝나고 마지막 대사가 2.5초 넘게 보인 뒤에야 떠난다. 떠나는 중 일시정지하면 사라짐 연출(빛 가루)이 멈춘다.
##     같은 방 집 자리에 빛에서 나타난다. 덮어쓰기를 지우면 경비병의 진짜 집은 사당.
##  6) 말 안 걸고 떠나기: canopy_03 의 정원사를 정화만 하고 방을 닫으면 깃발 home_gardener_canopy, 보상(이슬 +1)도 받는다.
##  7) village_02: 오웬 구원 상태로 띄우면 기존 Npc_owen 하나뿐(집 NPC 중복 없음), 정원사 집 NPC(2560, 1400) 가 owen_rescued 묶음을 말한다.
##  8) 보상은 꼭 한 번: (a) 감사의 말 중 '불러오기'(구원 전 세이브) → 보상이 새지 않고, 다시 구원하면 15 한 번만
##     (b) 쓰러짐 연출(0.5초) 안에 방을 떠나도 다음 방에서 받음 (b2) 다시 깨어난(respawn) 적도 같음
##     (c) 감사의 말 중 저장한 세이브를 읽으면 받음
##     (d) 1편 세이브(구원됐지만 보상 기록 없음)는 다시 받지 않음.
##  9) 집 항목이 없는 구원자(확장판 대비): 떠나지 않고 대사를 돌아가며 말하고, 집 깃발도 서지 않는다.
## 마지막에 "[probe] 끝: 실패 N" 을 찍고 그 수로 종료한다.

const IDS := ["woodcutter_canopy", "gardener_canopy", "guard_village", "owen", "herbalist_abyss", "fisher_lake", "miner_hidden"]
const SAVE_PATH := "user://save.json"
const TALK_BAND := 200.0     # 집 NPC 와 말하는 소녀가 설 수 있는 가로 범위 (± px)
const SPACING := 250.0       # 같은 바닥의 다른 말 걸기 대상과 떨어져야 하는 거리
const CAM_HALF_VIEW := 1920.0 / 1.15 / 2.0   # 카메라 기본 배율 1.15 (game_camera.gd base_zoom) 일 때 화면 가로 절반 (월드 px)
const CAM_LOOK_AHEAD := 150.0                 # game_camera.gd look_ahead

var _fail := 0
var _room: Node = null
var _player: Player = null
var _shots := false
var _save_backup := ""
var _had_save := false
var _room_cache := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # 일시정지 시험 중에도 시험은 돈다
	_shots = "--shots" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	print("[probe] 구원자 재배치 시험 시작")
	_backup_save()
	Progress.reset()
	RescuedHomes.test_override = {}
	_probe_data()
	await _probe_before_rescue()
	await _probe_field_flow()
	await _probe_home()
	await _probe_save_roundtrip()
	await _probe_same_room_home()
	await _probe_leave_without_talking()
	await _probe_village02()
	await _probe_reward_once()
	await _probe_no_home()
	await _close()
	RescuedHomes.test_override = {}
	_restore_save()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


# ---------- 0) 자료 ----------
func _probe_data() -> void:
	var table := RescuedHomes.table()
	var npcs: Dictionary = DialogueData.load_dialogue("res://data/dialogue/npcs.json")
	for id in IDS:
		var entry: Dictionary = table.get(id, {})
		_check(not entry.is_empty(), "relocations 항목 있음: %s" % id)
		if entry.is_empty():
			continue
		var scene := str(entry.get("scene", ""))
		var scene_path := "res://scenes/rooms/%s.tscn" % scene
		_check(ResourceLoader.exists(scene_path), "%s 집 방 파일 있음: %s" % [id, scene_path])
		var pos := RescuedHomes.home_position(entry)
		_check(pos != Vector2.ZERO, "%s 자리 %s" % [id, pos])
		var tex := str(entry.get("texture", ""))
		_check(tex != "" and ResourceLoader.exists(tex), "%s 그림 있음: %s" % [id, tex])
		var d: Dictionary = npcs.get(id, {})
		_check(str(d.get("leave_line", "")) != "", "%s leave_line 있음" % id)
		var hl: Array = d.get("home_lines", [])
		_check(not hl.is_empty(), "%s home_lines %d개" % [id, hl.size()])
		_check(not RescuedHomes.reward_of(id).is_empty(), "%s 보상 있음 %s" % [id, RescuedHomes.reward_of(id)])
		if not ResourceLoader.exists(scene_path):
			continue
		var info := _room_info(scene_path)
		# 바닥 위인가
		var on_floor := false
		for span in info["floors"]:
			if pos.x >= span[0] + 40.0 and pos.x <= span[1] - 40.0 and absf(pos.y - span[2]) < 0.5:
				on_floor = true
		_check(on_floor, "%s 자리 %s 는 %s 의 바닥 윗면 위" % [id, pos, scene])
		# 안전한가: 적의 순찰 범위 + 발견 거리 안에 대화 자리가 들어가지 않는다
		var threats: Array = []
		for e in info["enemies"]:
			if str(e["rescue_id"]) == id:
				continue
			if absf(float(e["y"]) - (pos.y - 57.0)) > 320.0:
				continue   # 다른 층 (발견은 위아래 260px 안에서만)
			var lo := float(e["x"]) - float(e["patrol"])
			var hi := float(e["x"]) + float(e["patrol"])
			var gap := maxf(0.0, maxf(lo - (pos.x + TALK_BAND), (pos.x - TALK_BAND) - hi))
			if gap <= float(e["notice"]):
				threats.append("%s(x %.0f, 순찰 ±%.0f, 발견 %.0f, 틈 %.0f)" % [e["name"], e["x"], e["patrol"], e["notice"], gap])
		_check(threats.is_empty(), "%s 집 자리는 적이 닿지 않는 곳 %s" % [id, "" if threats.is_empty() else str(threats)])
		# 왼쪽에서 다가가 말 걸 때(소녀 = 집 -100, 오른쪽 보기, 카메라 앞보기 150) 화면 가운데보다 왼쪽에 오는가
		# (방 오른쪽 끝에 카메라가 붙으면 오른쪽 아래 터치 버튼 무리 — 손길·약공격 — 밑에 가린다)
		var room_rect: Rect2 = info["bounds"]
		if room_rect.size.x > 0.0:
			var c := clampf(pos.x - 100.0 + CAM_LOOK_AHEAD, room_rect.position.x + CAM_HALF_VIEW, room_rect.end.x - CAM_HALF_VIEW)
			var frac := 0.5 + (pos.x - c) / (CAM_HALF_VIEW * 2.0)
			_check(frac <= 0.53, "%s 말 걸 때 화면 가로 %.0f%% 자리 (오른쪽 터치 버튼 밑이 아님)" % [id, frac * 100.0])
		# 같은 바닥의 다른 말 걸기 대상과 떨어져 있나 (오웬은 기존 NPC 가 그 자리 주인이라 뺀다)
		if str(entry.get("npc_id", "")) != "":
			continue
		var crowd: Array = []
		for it in info["interactables"]:
			if absf(float(it["y"]) - pos.y) < 40.0 and absf(float(it["x"]) - pos.x) < SPACING:
				crowd.append("%s(x %.0f)" % [it["name"], it["x"]])
		for other in IDS:
			if other == id:
				continue
			var oe: Dictionary = table.get(other, {})
			if str(oe.get("scene", "")) == scene and str(oe.get("npc_id", "")) == "":
				var op := RescuedHomes.home_position(oe)
				if absf(op.y - pos.y) < 40.0 and absf(op.x - pos.x) < SPACING:
					crowd.append("집:%s(x %.0f)" % [other, op.x])
		_check(crowd.is_empty(), "%s 집 자리 둘레 %.0fpx 안에 다른 말 걸기 대상 없음 %s" % [id, SPACING, "" if crowd.is_empty() else str(crowd)])
	# 오웬은 기존 마을 NPC 가 맡는다
	_check(str(table.get("owen", {}).get("npc_id", "")) == "owen", "오웬 항목은 npc_id=owen (기존 NPC 유지)")
	# 마지막 한 마디가 떠 있는 시간은 글자 수에 맞춘다
	for id in IDS:
		var line := str(npcs.get(id, {}).get("leave_line", ""))
		var t := clampf(line.length() / RescuedPerson.READ_CPS, RescuedPerson.LEAVE_SAY_MIN, RescuedPerson.LEAVE_SAY_MAX)
		print("[probe] %s 마지막 한 마디 %d자 → %.1f초 + 사라짐 %.1f초 (초당 %.1f자)" % [id, line.length(), t, RescuedPerson.VANISH_TIME, line.length() / (t + RescuedPerson.VANISH_TIME)])


## 방 파일을 트리에 넣지 않고 읽는다: one_way 아닌 Platform 들의 [x0, x1, 윗면 y], 적(자리·발견 거리·순찰 범위), 말 걸기 대상(자리).
func _room_info(scene_path: String) -> Dictionary:
	if _room_cache.has(scene_path):
		return _room_cache[scene_path]
	var out := {"floors": [], "enemies": [], "interactables": [], "bounds": Rect2()}
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return out
	var inst := packed.instantiate()
	if inst.get("bounds") is Rect2:
		out["bounds"] = inst.get("bounds")
	var terrain := inst.get_node_or_null("Terrain")
	if terrain:
		for c in terrain.get_children():
			if c is Node2D and c.get("size") != null and c.get("one_way") != null and not c.get("one_way"):
				var p: Vector2 = c.position
				var s: Vector2 = c.get("size")
				out["floors"].append([p.x, p.x + s.x, p.y])
	var enemies := inst.get_node_or_null("Enemies")
	if enemies:
		for e in enemies.get_children():
			if e is Node2D and e.get("notice_range") != null:
				out["enemies"].append({"name": e.name, "x": e.position.x, "y": e.position.y,
					"notice": float(e.get("notice_range")), "patrol": float(e.get("patrol_range")) if e.get("patrol_range") != null else 0.0,
					"rescue_id": str(e.get("rescue_id")) if e.get("rescue_id") != null else ""})
	for group in ["Interactables", "Exits"]:
		var g := inst.get_node_or_null(group)
		if g:
			for it in g.get_children():
				if it is Node2D:
					out["interactables"].append({"name": it.name, "x": it.position.x, "y": it.position.y})
	inst.free()
	_room_cache[scene_path] = out
	return out


# ---------- 1) 구원 전 ----------
func _probe_before_rescue() -> void:
	await _open("village_shrine", "FromVillage02")
	_check(_find_home("woodcutter_canopy") == null, "구원 전 사당에 나무꾼 집 NPC 없음")
	_check(_find_home("guard_village") == null, "구원 전 사당에 경비병 집 NPC 없음")
	_check(get_tree().get_nodes_in_group("enemy").is_empty(), "사당에는 적이 없다 (대화 중 맞지 않음)")


# ---------- 2) 들판 흐름 ----------
func _probe_field_flow() -> void:
	await _open("canopy_01", "")
	var enemy := _find_savable("woodcutter_canopy")
	_check(enemy != null, "canopy_01 에 구원 가능한 나무꾼 있음")
	if enemy == null:
		return
	var hp_before := _player.max_hp
	var npc := await _rescue(enemy, "woodcutter_canopy")
	if npc == null:
		return
	_check(npc.is_greeting(), "구원 직후 감사의 말 중")
	_check(npc.has_home(), "나무꾼은 집 항목이 있다")
	_check(Progress.has(RescuedHomes.DUE + "woodcutter_canopy") and _player.max_hp == hp_before, "감사의 말 중엔 '받을 보상'으로 적혀 있고 아직 안 받음")
	var done := await _until(func(): return not npc.is_greeting(), 8.0)
	_check(done and _player.max_hp >= hp_before + 15.0, "보상 뒤 최대 체력 %.0f → %.0f" % [hp_before, _player.max_hp])
	_check(Progress.has(RescuedHomes.GIVEN + "woodcutter_canopy") and not Progress.has(RescuedHomes.DUE + "woodcutter_canopy"), "보상 받음 깃발 rewarded_woodcutter_canopy")
	var hud := _room.get_node_or_null("CombatHUD")
	_check(hud != null and str(hud.get("_message")).find("최대 체력") >= 0, "화면 가운데 보상 안내 '%s'" % (hud.get("_message") if hud else ""))
	var data: Dictionary = DialogueData.load_dialogue("res://data/dialogue/npcs.json").get("woodcutter_canopy", {})
	var talk: Array = data.get("talk_lines", [])
	await _stand_by(npc)
	for i in talk.size():
		await _press("interact")
		await _wait(0.3)
		var b := npc.bubble_text()
		_check(b.find(talk[i]) >= 0, "말 걸기 %d: '%s'" % [i + 1, b])
		if i == 0:
			await _shot("field_talk")
			await _press("interact")   # 1초 안의 손길은 무시된다
			await _wait(0.1)
			_check(npc.bubble_text().find(talk[0]) >= 0, "말풍선이 뜬 지 1초 안의 손길은 무시 (아직 첫 줄)")
		await _wait(RescuedPerson.READ_MIN)
	_check(is_instance_valid(npc) and not npc.is_leaving(), "talk_lines 를 다 말한 뒤에도 아직 서 있다")
	await _press("interact")
	await _wait(0.2)
	_check(not npc.is_leaving(), "마지막 대사가 %.1f초 안 됐으면 떠나지 않는다" % RescuedPerson.LEAVE_GATE)
	await _wait(RescuedPerson.LEAVE_GATE)
	await _press("interact")
	await _wait(0.3)
	var leave := str(data.get("leave_line", ""))
	_check(npc.is_leaving() and npc.bubble_text().find(leave) >= 0, "마지막 한 마디: '%s'" % npc.bubble_text())
	_check(not _player.interactables.has(npc), "떠나는 중엔 말 걸기 대상에서 빠진다")
	await _shot("field_leave_line")
	var say := npc.leave_say_time()
	_check(say >= RescuedPerson.LEAVE_SAY_MIN and absf(say - clampf(leave.length() / RescuedPerson.READ_CPS, RescuedPerson.LEAVE_SAY_MIN, RescuedPerson.LEAVE_SAY_MAX)) < 0.01, "마지막 한 마디 %.1f초 (%d자)" % [say, leave.length()])
	await _wait(say - 0.4)
	_check(is_instance_valid(npc) and npc.bubble_text().find(leave) >= 0 and not npc._gone, "사라지기 직전까지 마지막 한 마디가 떠 있다")
	var motes_before := _count_particles()
	await _wait(0.4 + RescuedPerson.VANISH_TIME * 0.5)
	_check(_count_particles() > motes_before, "사라질 때 빛 가루 (입자 %d → %d)" % [motes_before, _count_particles()])
	await _shot("field_vanish")
	var gone := await _until_gone(npc, 3.0)
	_check(gone, "빛이 되어 사라짐 (노드 없음)")
	_check(Progress.has("home_woodcutter_canopy"), "깃발 home_woodcutter_canopy")
	_check(Progress.rescued.has("woodcutter_canopy"), "Progress.rescued 에 나무꾼")
	_check(_find_field("woodcutter_canopy") == null and _find_home("woodcutter_canopy") == null, "canopy_01 에는 아무 모습도 남지 않음 (집은 다른 방)")


# ---------- 3) 집 ----------
func _probe_home() -> void:
	await _open("village_shrine", "FromVillage02")
	var h := _find_home("woodcutter_canopy")
	_check(h != null, "사당에 나무꾼 집 NPC 있음")
	_check(_find_home("guard_village") == null, "경비병은 아직 구원 전이라 없음")
	if h == null:
		return
	var want := RescuedHomes.home_position(RescuedHomes.home_of("woodcutter_canopy"))
	_check(h.global_position.distance_to(want) < 2.0, "집 자리 %s (표: %s)" % [h.global_position, want])
	_check(h.get_parent().name == "Interactables", "Interactables 아래에 선다")
	_check(h.npc_id == "woodcutter_canopy", "npc_id 로도 읽힌다")
	var m: Color = h._sprite.modulate
	_check(m.r <= 1.0 and m.g <= 1.0 and m.b <= 1.0, "집 NPC 는 빛나지 않는다 (색 %s)" % m)
	var grp := h.current_home_group()
	_check(not grp.has("when"), "깃발 없을 땐 '늘 하는 말' 묶음")
	var expect := str(grp.get("lines", [""])[0])
	await _stand_by(h)
	await _shot("home_prompt")
	await _press("interact")
	await _wait(0.35)
	_check(Dialogue.is_active(), "말 걸면 대화 상자 열림")
	var first := str(Dialogue._lines[0].get("text", "")) if Dialogue.is_active() and Dialogue._lines.size() > 0 else ""
	_check(first == expect and first != "", "첫 줄 '%s'" % first)
	_check(str(Dialogue._lines[0].get("speaker", "")) == "나무꾼 베릴", "말하는 이 '나무꾼 베릴'")
	await _shot("home_dialogue")
	# 손길로만 넘긴다: 끝난 뒤 그 누름으로 대화가 다시 열리면 안 된다
	var ended := [0]
	var on_end := func(): ended[0] += 1
	Dialogue.finished.connect(on_end)
	var presses := 0
	var reopened := false
	while presses < 30 and ended[0] == 0:
		await _wait(0.3)
		await _press("interact")
		await get_tree().physics_frame   # 누른 그 틱의 처리(대화 넘김·소녀)가 끝난 뒤에 본다
		presses += 1
	for i in 4:
		if Dialogue.is_active():
			reopened = true
		await get_tree().physics_frame
	Dialogue.finished.disconnect(on_end)
	_check(ended[0] == 1 and not reopened and not Dialogue.is_active(), "손길로만 넘겨도 끝난 뒤 다시 열리지 않음 (누름 %d, 끝남 %d, 다시 열림 %s)" % [presses, ended[0], reopened])
	_check(_player.input_enabled, "대화가 끝나면 입력이 돌아온다")
	await _wait(0.3)
	await _press("interact")
	await _wait(0.35)
	_check(Dialogue.is_active(), "새로 누르면 다시 말을 건다")
	await _advance_dialogue()
	_check(not Dialogue.is_active(), "대화 끝")
	Progress.set_flag("boss_knight_defeated")
	var grp2 := h.current_home_group()
	_check(str(grp2.get("when", "")) == "boss_knight_defeated", "깃발 boss_knight_defeated 뒤엔 조건 묶음")
	Progress.flags.erase("boss_knight_defeated")


# ---------- 4) 세이브 왕복 ----------
func _probe_save_roundtrip() -> void:
	SaveGame.save("village_gate", "res://scenes/rooms/village_01.tscn")
	Progress.reset()
	_check(not Progress.rescued.has("woodcutter_canopy"), "초기화 뒤 구원 목록 비움")
	var scene := SaveGame.load_game()
	_check(scene.ends_with("village_01.tscn"), "읽은 방 %s" % scene.get_file())
	_check(Progress.rescued.has("woodcutter_canopy") and Progress.has("home_woodcutter_canopy"), "읽은 뒤 구원·집 깃발 복원")
	_check(Progress.has(RescuedHomes.GIVEN + "woodcutter_canopy"), "읽은 뒤 보상 받음 깃발도 복원")
	Progress.next_spawn = ""
	await _open("village_shrine", "FromVillage02")
	var h := _find_home("woodcutter_canopy")
	_check(h != null, "세이브 왕복 뒤에도 사당에 나무꾼 집 NPC 있음")
	_check(float(Progress.upgrades.get("max_hp", 0.0)) == 15.0, "세이브 왕복 뒤 보상은 그대로 한 번 (최대 체력 성장 %.0f)" % Progress.upgrades.get("max_hp", 0.0))


# ---------- 5) 같은 방이 집 (시험용 덮어쓰기) + 연타 + 일시정지 ----------
func _probe_same_room_home() -> void:
	var real: Dictionary = RescuedHomes.home_of("guard_village")
	var fake := real.duplicate()
	fake["scene"] = "village_01"
	fake["position"] = [3300, 1400]
	RescuedHomes.test_override = {"guard_village": fake}
	await _open("village_01", "FromCanopy")   # 달빛풀 도착(쉬는 중)이 아니라 걷는 상태로 연다
	var enemy := _find_savable("guard_village")
	_check(enemy != null, "village_01 에 구원 가능한 경비병 있음")
	if enemy == null:
		RescuedHomes.test_override = {}
		return
	var atk_before: float = Progress.upgrades.get("attack", 0.0)
	var npc := await _rescue(enemy, "guard_village")
	if npc == null:
		RescuedHomes.test_override = {}
		return
	# 손길 연타 (0.15초마다) — 정화 직후부터
	var talk: Array = DialogueData.load_dialogue("res://data/dialogue/npcs.json").get("guard_village", {}).get("talk_lines", [])
	var r := await _spam_until_leaving(npc, 14.0)
	var changes: Array = r["changes"]
	print("[probe] 연타 중 말풍선: %s" % str(changes.map(func(c): return "%.2f:%s" % [c[0], str(c[1]).left(12)])))
	var shortest := 99.0
	for i in range(1, changes.size()):
		if str(changes[i - 1][1]) != "" and str(changes[i][1]) != "":
			shortest = minf(shortest, float(changes[i][0]) - float(changes[i - 1][0]))
	_check(shortest >= RescuedPerson.READ_MIN - 0.04, "연타해도 말풍선마다 %.1f초 넘게 보인다 (가장 짧게 %.2f초)" % [RescuedPerson.READ_MIN, shortest])
	_check(r["leave_t"] > 0.0 and r["leave_t"] >= r["greet_end"], "감사의 말이 끝난 뒤에야 떠난다 (끝 %.2f, 떠남 %.2f)" % [r["greet_end"], r["leave_t"]])
	var last_talk_t := -1.0
	for c in changes:
		if talk.size() > 0 and str(c[1]).find(str(talk[talk.size() - 1])) >= 0:
			last_talk_t = float(c[0])
	_check(last_talk_t > 0.0 and r["leave_t"] - last_talk_t >= RescuedPerson.LEAVE_GATE - 0.04, "마지막 대사가 %.1f초 넘게 보인 뒤에 떠난다 (%.2f초)" % [RescuedPerson.LEAVE_GATE, r["leave_t"] - last_talk_t])
	_check(Progress.upgrades.get("attack", 0.0) > atk_before, "경비병 보상: 공격 %.2f → %.2f" % [atk_before, Progress.upgrades.get("attack", 0.0)])
	_check(is_instance_valid(npc) and npc.is_leaving(), "경비병 마지막 한 마디 뒤 떠나는 중")
	# 떠나는 중 일시정지: 사라짐 연출이 멈춘다
	var parts := _count_particles()
	get_tree().paused = true
	await _wait(npc.leave_say_time() + 1.0)   # 이 타이머는 멈춤 중에도 흐른다 (시험 쪽)
	var alive := is_instance_valid(npc) and npc.is_inside_tree()
	_check(alive and not npc._gone and _count_particles() == parts, "멈춘 동안엔 사라지지 않고 빛 가루도 안 나온다 (입자 %d → %d)" % [parts, _count_particles()])
	get_tree().paused = false
	var gone := await _until_gone(npc, npc.leave_say_time() + RescuedPerson.VANISH_TIME + 3.0) if alive else true
	_check(gone, "멈춤을 풀면 경비병 사라짐")
	await _wait(0.1)
	var h := _find_home("guard_village")
	_check(h != null, "같은 방이 집이면 그 자리에 바로 나타남")
	if h:
		_check(h.global_position.distance_to(Vector2(3300, 1400)) < 2.0, "경비병 (시험) 집 자리 %s" % h.global_position)
		_player.global_position = h.global_position + Vector2(-160, -10)
		_player.velocity = Vector2.ZERO
		await _wait(RescuedPerson.APPEAR_TIME * 0.4)
		await _shot("home_guard_appear")
	# 다시 열어도 하나만
	await _open("village_01", "FromCanopy")
	var n_guard := 0
	for n in get_tree().get_nodes_in_group("npc"):
		if n is RescuedPerson and n.home and n.rescue_id == "guard_village" and not n.is_queued_for_deletion():
			n_guard += 1
	_check(n_guard == 1, "다시 열면 경비병 %d (중복 없음)" % n_guard)
	# 덮어쓰기를 지우면 진짜 집(사당)
	RescuedHomes.test_override = {}
	await _open("village_01", "FromCanopy")
	_check(_find_home("guard_village") == null, "진짜 표로는 입구의 거리에 경비병 없음")
	await _open("village_shrine", "FromVillage02")
	var hg := _find_home("guard_village")
	_check(hg != null and hg.global_position.distance_to(RescuedHomes.home_position(real)) < 2.0, "경비병의 집은 사당 문가 %s" % (hg.global_position if hg else Vector2.ZERO))
	_check(_find_home("woodcutter_canopy") != null and _find_home("guard_village") != null, "사당에 집 NPC 둘 (나무꾼·경비병)")
	if hg:
		await _stand_by(hg)
		await _wait(1.4)   # 검은 페이드가 걷힌 뒤
		await _shot("home_shrine")


# ---------- 6) 말 안 걸고 떠나기 (정원사) ----------
func _probe_leave_without_talking() -> void:
	await _open("canopy_03", "FromCanopy02")
	var enemy := _find_savable("gardener_canopy")
	_check(enemy != null, "canopy_03 에 구원 가능한 정원사 있음")
	if enemy == null:
		return
	var dews_before: float = Progress.upgrades.get("dews", 0.0)
	var npc := await _rescue(enemy, "gardener_canopy")
	if npc == null:
		return
	_check(npc.is_greeting(), "정원사 감사의 말 중 (아직 보상 전)")
	await _close()   # 말 안 걸고 방을 떠난다
	_check(Progress.has("home_gardener_canopy"), "방을 떠나자 깃발 home_gardener_canopy")
	_check(float(Progress.upgrades.get("dews", 0.0)) == dews_before + 1.0, "감사의 말 중에 떠나도 보상(이슬 +1)은 한 번 받음: %.0f → %.0f" % [dews_before, Progress.upgrades.get("dews", 0.0)])


# ---------- 7) 등불 골목: 오웬 중복 없음 + 정원사 집 ----------
func _probe_village02() -> void:
	Progress.rescued["owen"] = true
	Progress.set_flag("owen_rescued")
	await _open("village_02", "FromVillage01")
	var n_owen_npc := 0
	var n_owen_home := 0
	for n in get_tree().get_nodes_in_group("npc"):
		if not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		if n is Npc and n.npc_id == "owen":
			n_owen_npc += 1
		elif n is RescuedPerson and n.rescue_id == "owen":
			n_owen_home += 1
	_check(n_owen_npc == 1 and n_owen_home == 0, "오웬: 기존 NPC %d, 집 NPC %d (중복 없음)" % [n_owen_npc, n_owen_home])
	_check(Progress.has("home_owen"), "오웬도 깃발 home_owen (옛 세이브 보정)")
	var g := _find_home("gardener_canopy")
	_check(g != null, "village_02 에 정원사 집 NPC 있음")
	if g == null:
		return
	var want := RescuedHomes.home_position(RescuedHomes.home_of("gardener_canopy"))
	_check(g.global_position.distance_to(want) < 2.0, "정원사 집 자리 %s" % g.global_position)
	var grp := g.current_home_group()
	_check(str(grp.get("when", "")) == "owen_rescued", "owen_rescued 깃발로 조건 묶음이 골라짐")
	await _stand_by(g)
	await _wait(1.0)   # 검은 페이드가 걷힌 뒤
	await _press("interact")
	await _wait(0.35)
	var first := str(Dialogue._lines[0].get("text", "")) if Dialogue.is_active() and Dialogue._lines.size() > 0 else ""
	_check(first == str(grp.get("lines", [""])[0]) and first != "", "정원사 첫 줄 '%s'" % first)
	await _shot("home_gardener_dialogue")
	await _advance_dialogue()


# ---------- 8) 보상은 꼭 한 번 ----------
func _probe_reward_once() -> void:
	# (a) 감사의 말 중 '불러오기' — 구원 전 세이브로 되돌아간다
	Progress.reset()
	SaveGame.save("", "res://scenes/rooms/canopy_01.tscn")
	await _open("canopy_01", "")
	var npc := await _rescue(_find_savable("woodcutter_canopy"), "woodcutter_canopy")
	if npc:
		_check(npc.is_greeting(), "(a) 감사의 말 중 (보상 전)")
		SaveGame.load_game()   # 메뉴 '불러오기': Progress 를 먼저 세이브로 바꾼 뒤 방을 닫는다
		await _wait(0.4)       # 페이드 동안 옛 방은 조금 더 돈다
		await _close()
		_check(float(Progress.upgrades.get("max_hp", 0.0)) == 0.0 and not Progress.rescued.has("woodcutter_canopy"), "(a) 읽어 온 구원 전 세이브에 보상이 새지 않음 (성장 %.0f)" % Progress.upgrades.get("max_hp", 0.0))
		_check(not Progress.has("home_woodcutter_canopy"), "(a) 구원 안 된 세이브엔 집 깃발 없음")
		Progress.next_spawn = ""
		await _open("canopy_01", "")
		var again := _find_savable("woodcutter_canopy")
		_check(again != null, "(a) 읽어 온 세이브에선 나무꾼이 다시 적")
		if again:
			var n2 := await _rescue(again, "woodcutter_canopy")
			if n2:
				await _until(func(): return not n2.is_greeting(), 8.0)
			_check(float(Progress.upgrades.get("max_hp", 0.0)) == 15.0, "(a) 다시 구원하면 보상은 한 번만 (성장 %.0f)" % Progress.upgrades.get("max_hp", 0.0))
	# (b) 쓰러짐 연출(0.5초) 안에 방을 떠난다
	Progress.reset()
	await _open("canopy_01", "")
	var ok := await _break_and_purify(_find_savable("woodcutter_canopy"), "woodcutter_canopy")
	if ok:
		await _until(func(): return Progress.rescued.has("woodcutter_canopy"), 2.0)
		_check(_find_field("woodcutter_canopy") == null, "(b) 구원 순간 (아직 사람 모습 전)")
		_check(Progress.has(RescuedHomes.DUE + "woodcutter_canopy"), "(b) 구원 순간에 받을 보상이 적힘")
		await _close()
		await _open("village_01", "FromCanopy")
		_check(float(Progress.upgrades.get("max_hp", 0.0)) == 15.0 and Progress.has(RescuedHomes.GIVEN + "woodcutter_canopy"), "(b) 다음 방에서 보상을 받음 (성장 %.0f)" % Progress.upgrades.get("max_hp", 0.0))
		var hud := _room.get_node_or_null("CombatHUD")
		_check(hud != null and str(hud.get("_message")).find("최대 체력") >= 0, "(b) 다음 방에서 보상 안내 '%s'" % (hud.get("_message") if hud else ""))
	# (b2) 달빛풀에서 쉬거나 쓰러진 뒤 다시 깨어난 적도 구원 순간이 잡힌다 (트리에 새로 들어온 적)
	Progress.reset()
	await _open("canopy_01", "")
	_room.respawn_enemies()
	for i in 4:
		await get_tree().physics_frame
	var ok2 := await _break_and_purify(_find_savable("woodcutter_canopy"), "woodcutter_canopy")
	if ok2:
		await _until(func(): return Progress.rescued.has("woodcutter_canopy"), 2.0)
		_check(_find_field("woodcutter_canopy") == null and Progress.has(RescuedHomes.DUE + "woodcutter_canopy"), "(b2) 다시 깨어난 적도 구원 순간에 받을 보상이 적힘")
		await _close()
	# (c) 감사의 말 중에 저장한 세이브
	Progress.reset()
	await _open("canopy_01", "")
	var n3 := await _rescue(_find_savable("woodcutter_canopy"), "woodcutter_canopy")
	if n3:
		SaveGame.save("", "res://scenes/rooms/canopy_01.tscn")   # 메뉴 '지금 저장하기' (보상 전)
		await _close()
		Progress.reset()
		SaveGame.load_game()
		_check(Progress.has(RescuedHomes.DUE + "woodcutter_canopy") and float(Progress.upgrades.get("max_hp", 0.0)) == 0.0, "(c) 세이브에는 받을 보상이 적혀 있고 아직 안 받음")
		Progress.next_spawn = ""
		await _open("village_01", "FromCanopy")
		_check(float(Progress.upgrades.get("max_hp", 0.0)) == 15.0, "(c) 그 세이브를 읽으면 보상을 받음 (성장 %.0f)" % Progress.upgrades.get("max_hp", 0.0))
	# (d) 1편 세이브: 구원됐지만 보상 기록 깃발이 없다 → 다시 주지 않는다
	Progress.reset()
	Progress.rescued["herbalist_abyss"] = true
	Progress.flags["herbalist_abyss_rescued"] = true
	await _open("village_shrine", "FromVillage02")
	_check(Progress.upgrades.is_empty(), "(d) 옛 세이브엔 보상을 다시 주지 않음 (성장 %s)" % Progress.upgrades)
	_check(_find_home("herbalist_abyss") != null, "(d) 옛 세이브여도 사당에 약초꾼이 선다")
	if _shots:
		# 사당에 다섯 명 중 셋(경비병·약초꾼·나무꾼)과 등불지기
		for id in IDS:
			Progress.rescued[id] = true
		await _open("village_shrine", "FromVillage02")
		var w := _find_home("woodcutter_canopy")
		if w:
			await _stand_by(w)
			await _wait(1.4)
			await _shot("home_shrine_all")


# ---------- 9) 집 항목이 없는 구원자 ----------
func _probe_no_home() -> void:
	Progress.reset()
	RescuedHomes.test_override = {"woodcutter_canopy": {}}
	await _open("canopy_01", "")
	var npc := await _rescue(_find_savable("woodcutter_canopy"), "woodcutter_canopy")
	if npc == null:
		RescuedHomes.test_override = {}
		return
	_check(not npc.has_home(), "표에 없으면 집 없음")
	await _until(func(): return not npc.is_greeting(), 8.0)
	await _stand_by(npc)
	var talk: Array = DialogueData.load_dialogue("res://data/dialogue/npcs.json").get("woodcutter_canopy", {}).get("talk_lines", [])
	var seen: Array = []
	for i in talk.size() + 3:
		await _press("interact")
		await _wait(0.2)
		seen.append(npc.bubble_text())
		await _wait(RescuedPerson.LEAVE_GATE + 0.2)
	_check(is_instance_valid(npc) and not npc.is_leaving(), "여러 번 말 걸어도 떠나지 않는다")
	_check(seen.size() > talk.size() and str(seen[talk.size()]).find(str(talk[0])) >= 0, "대사를 돌아가며 말한다 ('%s')" % (seen[talk.size()] if seen.size() > talk.size() else ""))
	await _close()
	_check(not Progress.has("home_woodcutter_canopy"), "집 항목이 없으면 집 깃발도 안 섬")
	RescuedHomes.test_override = {}


# ---------- 공용 ----------
func _open(room_id: String, spawn: String) -> void:
	await _close()
	if spawn != "":
		Progress.next_spawn = spawn
	_room = load("res://scenes/rooms/%s.tscn" % room_id).instantiate()
	add_child(_room)
	for i in 3:
		await get_tree().physics_frame
	_player = get_tree().get_first_node_in_group("player") as Player
	_player._invuln_timer = 9999.0
	for i in 6:
		await get_tree().physics_frame


func _close() -> void:
	_release_all()
	if _room:
		_room.queue_free()
		_room = null
		_player = null
		for i in 3:
			await get_tree().process_frame


func _release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "interact", "attack_light"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _press(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)


## 조건이 참이 될 때까지 물리 틱을 기다린다 (시간 제한). 참이면 true.
func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if cond.call():
			return true
	return false


## 노드가 지워질 때까지 기다린다 (약한 참조로 — 지워진 뒤 람다 포획 오류가 나지 않게).
func _until_gone(node: Node, limit: float) -> bool:
	var w: WeakRef = weakref(node)
	return await _until(func(): return w.get_ref() == null, limit)


## 0.15초마다 손길을 누르며 말풍선이 바뀌는 때를 적는다. 떠나기 시작하면 멈춘다.
func _spam_until_leaving(npc: RescuedPerson, limit: float) -> Dictionary:
	var w: WeakRef = weakref(npc)
	var t := 0.0
	var next_press := 0.0
	var last := npc.bubble_text()
	var changes: Array = [[0.0, last]]
	var greet_end := -1.0
	var leave_t := -1.0
	while t < limit:
		var pressed := false
		if t >= next_press:
			_player.global_position = npc.global_position + Vector2(-100, -10)
			Input.action_press("interact")
			pressed = true
			next_press += 0.15
		await get_tree().physics_frame
		if pressed:
			Input.action_release("interact")
		t += get_physics_process_delta_time()
		var n: RescuedPerson = w.get_ref()
		if n == null:
			break
		var b := n.bubble_text()
		if b != last:
			changes.append([t, b])
			last = b
		if greet_end < 0.0 and not n.is_greeting():
			greet_end = t
		if n.is_leaving():
			leave_t = t
			break
	return {"changes": changes, "greet_end": greet_end, "leave_t": leave_t}


func _count_particles() -> int:
	var n := 0
	if _room == null:
		return 0
	for c in _room.find_children("*", "CPUParticles2D", true, false):
		if c.one_shot:
			n += 1
	return n


func _find_savable(id: String) -> EnemyBase:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is EnemyBase and e.savable and e.rescue_id == id and not e.is_queued_for_deletion():
			return e
	return null


func _find_home(id: String) -> RescuedPerson:
	for n in get_tree().get_nodes_in_group("npc"):
		if n is RescuedPerson and n.home and n.rescue_id == id and is_instance_valid(n) and not n.is_queued_for_deletion():
			return n
	return null


func _find_field(id: String) -> RescuedPerson:
	for n in get_tree().get_nodes_in_group("npc"):
		if n is RescuedPerson and not n.home and n.rescue_id == id and is_instance_valid(n) and not n.is_queued_for_deletion():
			return n
	return null


## 기존 --rescuetest 흐름: 체력 5 → 공격으로 무릎 → 손길. 손길까지 눌렀으면 true.
func _break_and_purify(enemy: EnemyBase, id: String) -> bool:
	if enemy == null:
		_check(false, "%s 적이 없음" % id)
		return false
	_player._invuln_timer = 9999.0
	_player.global_position = enemy.global_position + Vector2(-140, 0)
	_player.velocity = Vector2.ZERO
	_player.facing = 1
	await _wait(0.4)
	enemy.hp = 5.0
	var tries := 0
	while is_instance_valid(enemy) and enemy.state != EnemyBase.State.BROKEN and tries < 12:
		_player.global_position = enemy.global_position + Vector2(-140, 0)
		_player.velocity = Vector2.ZERO
		_player.facing = 1
		await _press("attack_light")
		await _wait(0.35)
		tries += 1
	_check(is_instance_valid(enemy) and enemy.state == EnemyBase.State.BROKEN, "%s 무릎 꿇음 (%d번 공격)" % [id, tries])
	if not is_instance_valid(enemy) or enemy.state != EnemyBase.State.BROKEN:
		return false
	await _wait(0.3)
	_player.global_position = enemy.global_position + Vector2(-140, 0)
	_player.velocity = Vector2.ZERO
	await _until(func(): return _player.interactables.has(enemy), 1.0)
	await _press("interact")
	return true


## 정화해서 사람(RescuedPerson)이 나타나면 돌려준다.
func _rescue(enemy: EnemyBase, id: String) -> RescuedPerson:
	if not await _break_and_purify(enemy, id):
		return null
	var appeared := await _until(func(): return _find_field(id) != null, 4.0)
	_check(appeared, "%s 정화 → 사람으로" % id)
	return _find_field(id)


## 소녀를 NPC 곁에 세우고 말 걸기 대상이 될 때까지 기다린다.
func _stand_by(npc: Node2D) -> void:
	_release_all()
	_player.global_position = npc.global_position + Vector2(-100, -10)
	_player.velocity = Vector2.ZERO
	_player.facing = 1
	var ok := await _until(func(): return _player.interactables.has(npc) and _player.state in Player.LOCOMOTION, 2.0)
	_check(ok, "%s 곁에서 말 걸기 가능" % npc.name)


## 대화 상자를 끝까지 넘긴다 (점프 버튼: 먼저 글자를 다 보이고, 다음에 넘긴다).
func _advance_dialogue() -> void:
	var guard := 0
	while Dialogue.is_active() and guard < 16:
		await _wait(0.3)
		await _press("jump")
		guard += 1
	await _wait(0.3)


func _shot(name: String) -> void:
	if not _shots:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(ProjectSettings.globalize_path("res://screenshots/probe_npcs_%s.png" % name))


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(SAVE_PATH)


func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_string(_save_backup)
			f.close()
	elif FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

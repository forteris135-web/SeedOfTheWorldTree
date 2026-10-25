extends Node
## 보스 러시 시험 (엔딩 뒤 타이틀의 '보스 러시', 2026-10-20). 화면 없이 돈다 — 진짜 장면 바꾸기(Game.go_to)로 끝까지.
## 실행: godot --headless --path . res://tools/probe_bossrush.tscn
##  1) 클리어 전 타이틀에는 '보스 러시'·'음악 감상'이 없고, 클리어한 세이브가 있으면 생긴다.
##  2) 타이틀 메뉴로 러시 시작 → 보스 방 다섯이 이야기 순서(새 → 기사 → 여왕 → 펌프 → 뿌리지기)로 열린다. 방마다:
##     러시 모드 · 싸움터 안에서 곧바로 싸움 · 자기 보스곡 · 러시 시계(HUD) · 저장 파일의 성장(체력·공격·이슬·영혼) · 수액 위 걷기 ·
##     깃발 없음. 시험 훅(BossRoom.debug_force_defeat)으로 쓰러뜨리면 기록이 남고 다음 방으로 저절로 넘어간다.
##     러시 중: SaveGame.save/save_now 가 아무것도 쓰지 않음, 일시정지 메뉴에 '포기하기'(저장·불러오기·타이틀로 없음),
##     지도가 열리지 않음, 일시정지 동안 시계가 멈춤, 정화의 손길을 얹어도 깃발·회상 없음, 등장 연출이 짧아짐(새).
##  3) 완주 → 결과 화면: 다섯 기록, 전체 = 합, 최고 기록 파일(user://boss_rush.json), 진행·정화 상태가 러시 전과 똑같이 되돌아옴,
##     save.json 이 한 바이트도 바뀌지 않음 → 타이틀로.
##  4) 둘째 보스에서 쓰러짐 → 결과(쓰러짐, 2번째, 시간) → 최고 기록은 그대로. 5) 들어서자마자 포기 → 결과(포기).
##  6) 저장 파일이 없으면 다 자란 몸 (이슬 8개 등), 그래도 save.json 을 만들지 않는다.
## 마지막 줄 "[probe] 끝: 실패 N".

const EXPECT := ["canopy_boss", "mine_boss", "sap_lake_boss", "flooded_mine_boss", "abyss_boss"]
const EXPECT_TRACK := ["boss_bird", "boss_knight", "boss_sap_queen", "boss_iron_pump", "boss_rootkeeper_p1"]

var _fail := 0
## 화면 있게 돌릴 때 -- --shots --out=/절대/경로 를 주면 몇 장면을 찍는다 (그림 확인용)
var _shots := false
var _out := ""


func _ready() -> void:
	print("[probe] 시작: 보스 러시")
	await _run()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _shot(name: String) -> void:
	if not _shots or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img:
		DirAccess.make_dir_recursive_absolute(_out)
		img.save_png(_out.path_join(name + ".png"))
		print("[probe]   찍음: ", _out.path_join(name + ".png"))


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 지금 장면의 파일 이름에 name 이 들어갈 때까지 기다린다 (없으면 null).
func _wait_scene(name: String, limit: float) -> Node:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < limit * 1000.0:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and cs != self and cs.scene_file_path.get_file().get_basename() == name and cs.is_node_ready():
			return cs
	print("[probe]   장면을 기다리다 시간 초과: ", name, " (지금 ", get_tree().current_scene.scene_file_path if get_tree().current_scene else "없음", ")")
	return null


## 이 시험 노드가 장면 바꾸기에 지워지지 않게, 빈 노드를 '지금 장면'으로 세우고 그 자리를 바꾼다.
func _goto(path: String) -> void:
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	var cur := get_tree().current_scene
	get_tree().current_scene = dummy
	if cur and cur != self:
		cur.queue_free()
	Game._busy = false
	get_tree().change_scene_to_file(path)


func _open_title() -> TitleScreen:
	_goto(Game.TITLE_SCENE)
	var t: Node = await _wait_scene("title_screen", 10.0)
	await _frames(4)
	return t as TitleScreen


## 진행 전체를 글자로 (러시 전후 비교)
func _progress_json() -> String:
	var d := {}
	for k in BossRush.PROGRESS_FIELDS:
		d[k] = Progress.get(k)
	var metas := {}
	for m in Progress.get_meta_list():
		metas[m] = Progress.get_meta(m)
	d["_meta"] = metas
	d["_purity"] = Purity.regions
	return JSON.stringify(d, "", true)


## 엔딩까지 본 세이브 (성장: 체력 +30, 공격 +15%, 이슬 +2, 회복 +10, 영혼 바람)
func _make_cleared_save() -> void:
	Progress.reset()
	for f in ["cleared", "last_ending_return", "boss_bird_defeated", "after_boss_bird_defeated", "boss_knight_defeated",
			"after_boss_knight_defeated", "boss_queen_defeated", "boss_pump_defeated", "boss_root_defeated", "after_boss_root_defeated", "met_tia"]:
		Progress.flags[f] = true
	for a in ["double_jump", "wind", "light", "lantern", "sap_walk", "wall_break"]:
		Progress.abilities[a] = true
	Progress.soul = "wind"
	Progress.upgrades = {"max_hp": 30.0, "attack": 0.15, "dews": 2.0, "heal": 10.0}
	Progress.grasses = {"abyss_boss_gate": {"scene": "res://scenes/rooms/abyss_boss.tscn", "name": "심연 · 정원의 끝"}}
	Progress.last_grass = {"id": "abyss_boss_gate", "scene": "res://scenes/rooms/abyss_boss.tscn", "name": "심연 · 정원의 끝"}
	Progress.rescued = {"woodcutter_canopy": true}
	Progress.ending = "return"
	Progress.collected = {"pick_canopy_01_1": true}
	Progress.dust = 321
	for k in Purity.regions:
		Purity.regions[k] = true
	SaveGame.save("abyss_boss_gate", "res://scenes/rooms/abyss_boss.tscn")
	# 기억 속 진행은 저장과 조금 다르게 (러시가 '지금 진행'을 그대로 되돌리는지 보려고)
	Progress.dust = 777
	Progress.visited_rooms = {"canopy_01": {"offset": Vector2(0, 0), "size": Vector2(4800, 2330), "name": "수관 · 시작의 가지", "region": "canopy", "grasses": [], "portals": [], "boss": false}}
	Progress.soul_cooldowns = {"wind": 2.5}
	Progress.set_meta("iron_pump_remains", Vector2(2500, -1))


func _run() -> void:
	await get_tree().process_frame   # 시작 장면이 다 놓인 뒤에 장면을 바꾼다
	var args := OS.get_cmdline_user_args()
	_shots = "--shots" in args
	_out = ProjectSettings.globalize_path("res://screenshots")
	for a in args:
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_rm(SaveGame.PATH)
	_rm(BossRush.BEST_PATH)
	Progress.reset()
	_probe_format()
	# 1) 클리어 전
	var title := await _open_title()
	_check(title != null and not title.has_item("BossRush") and not title.has_item("MusicRoom"), "클리어 전 타이틀: '보스 러시'·'음악 감상'이 없다")
	_make_cleared_save()
	var save_bytes := FileAccess.get_file_as_bytes(SaveGame.PATH)
	var before := _progress_json()
	title = await _open_title()
	_check(title != null and title.has_item("BossRush") and title.has_item("MusicRoom"), "엔딩을 본 세이브: 타이틀에 '보스 러시'·'음악 감상'이 생긴다")
	if title == null:
		return
	# '새로 시작'은 저장이 있으면 한 번 더 눌러야 한다 (2026-10-20 QA: 클리어한 저장·엔딩 기록이 확인 없이 지워졌다)
	title.activate_item("Start")
	await _frames(2)
	var confirming: bool = title.confirming_new_game()
	var kept := FileAccess.get_file_as_bytes(SaveGame.PATH) == save_bytes and not title._started
	title._select((title._index + 1) % title._items.size())
	await _frames(2)
	_check(confirming and kept and not title.confirming_new_game() and FileAccess.get_file_as_bytes(SaveGame.PATH) == save_bytes,
		"저장이 있을 때 '새로 시작' 한 번 → 확인만 (저장 그대로), 다른 항목으로 옮기면 확인 취소")
	if _shots:
		await _wait(3.5)
		await _shot("rush_title_menu")
	# 2) 완주
	title.activate_item("BossRush")
	_check(BossRush.active and BossRush.growth_source == "save", "타이틀 메뉴로 러시 시작 (몸 = 저장 파일의 성장: %s)" % BossRush.growth_source)
	var order := []
	for i in EXPECT.size():
		var room := await _wait_scene(EXPECT[i], 20.0) as BossRoom
		if room == null:
			_check(false, "%d번째 보스 방 %s 이 열리지 않았다" % [i + 1, EXPECT[i]])
			break
		order.append(room.scene_file_path.get_file().get_basename())
		await _boss_room_checks(room, i, save_bytes)
		if _shots and i in [0, 2]:
			await _wait(1.5)
			await _shot("rush_fight_%d" % i)
		await room.debug_force_defeat()
		if _shots and i == 0:
			await _wait(1.2)
			await _shot("rush_fallen_0")
		var boss: Node = room.boss
		_check(is_instance_valid(boss) and boss.state_name() == "FALLEN" and BossRush.splits.size() == i + 1 and BossRush.advancing,
			"%s: 쓰러뜨림 → 기록 %s (%d개째), 다음으로 넘어가는 중" % [EXPECT[i], BossRush.format_time(BossRush.splits[i]) if BossRush.splits.size() > i else "-", BossRush.splits.size()])
		if i == 0:
			# 정화의 손길을 얹어도 깃발·회상 없이 그대로
			boss.purified_by(room.player)
			await _frames(3)
			_check(not Progress.has(room.defeat_flag) and Progress.pending_memory == "" and Progress.dust == 0 and not Progress.has("dust_" + room.defeat_flag),
				"러시에서 정화의 손길: 깃발·회상·빛 가루 없음")
		_check(not Progress.has(room.defeat_flag) and Progress.flags.is_empty(), "%s: 러시 중 깃발이 하나도 생기지 않았다 %s" % [EXPECT[i], Progress.flags.keys()])
		if i == 0:
			await _check_fx_cleared_on_advance(room)
	_check(order == EXPECT, "보스 방 순서: %s" % [order])
	var res := await _wait_scene("boss_rush_result", 20.0) as BossRushResult
	_check(res != null and res.outcome() == "clear", "다섯을 모두 쓰러뜨리면 결과 화면 (완주)")
	if res == null:
		return
	var r := res.result()
	var sum := 0.0
	for s in r["splits"]:
		sum += float(s)
	_check((r["splits"] as Array).size() == 5 and absf(float(r["total"]) - sum) < 0.001 and sum > 0.0, "보스별 기록 5개, 전체 시간 = 합 (%s)" % BossRush.format_time(sum))
	_check(not BossRush.active, "결과 화면에서 러시가 끝났다 (진행 되돌림)")
	_check(FileAccess.get_file_as_bytes(SaveGame.PATH) == save_bytes, "save.json 이 한 바이트도 바뀌지 않았다")
	var after := _progress_json()
	_check(after == before, "진행(깃발·능력·성장·달빛풀·지도·빛 가루·메타)과 정화 상태가 러시 전과 똑같다")
	if after != before:
		print("[probe]   전: ", before.left(400))
		print("[probe]   뒤: ", after.left(400))
	var best := BossRush.load_best()
	_check(FileAccess.file_exists(BossRush.BEST_PATH) and absf(float(best["best_total"]) - sum) < 0.001 and int(best["clears"]) == 1 and int(best["attempts"]) == 1
		and r.get("new_best", false) and (best["split_bests"] as Dictionary).size() == 5,
		"최고 기록 파일: %s (완주 %d, 도전 %d, 새 기록 %s)" % [BossRush.format_time(float(best["best_total"])), int(best["clears"]), int(best["attempts"]), r.get("new_best", false)])
	_check(Music.current() == Music.REST, "결과 화면 곡: %s" % Music.current())
	if _shots:
		await _wait(1.6)
		await _shot("rush_result_clear")
	var t0 := Time.get_ticks_msec()
	while not res.can_leave() and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	res.leave()
	title = await _wait_scene("title_screen", 10.0) as TitleScreen
	await _frames(4)
	_check(title != null and title.has_item("BossRush") and Music.current() == Music.title_track(true), "결과 화면 → 타이틀 (보스 러시 메뉴 그대로, 곡 %s)" % Music.current())
	if title == null:
		return
	# 4) 둘째 보스에서 쓰러짐
	title.activate_item("BossRush")
	var room1 := await _wait_scene(EXPECT[0], 20.0) as BossRoom
	await _frames(20)
	await room1.debug_force_defeat()
	var room2 := await _wait_scene(EXPECT[1], 20.0) as BossRoom
	await _wait(1.6)
	var p2: Player = get_tree().get_first_node_in_group("player")
	var e_before := BossRush.elapsed
	p2.take_damage_over_time(99999.0)
	res = await _wait_scene("boss_rush_result", 20.0) as BossRushResult
	r = res.result() if res else {}
	_check(res != null and res.outcome() == "dead" and int(r.get("reached", -1)) == 1 and (r["splits"] as Array).size() == 1
		and float(r.get("current", 0.0)) >= e_before and float(r.get("current", 0.0)) > 0.5,
		"둘째 보스에서 쓰러짐 → 결과 (쓰러짐, %d번째, 그 싸움 %s, 전체 %s)" % [int(r.get("reached", -1)) + 1, BossRush.format_time(float(r.get("current", 0.0))), BossRush.format_time(float(r.get("total", 0.0)))])
	if _shots:
		await _wait(1.6)
		await _shot("rush_result_dead")
	best = BossRush.load_best()
	_check(absf(float(best["best_total"]) - sum) < 0.001 and int(best["attempts"]) == 2 and int(best["clears"]) == 1 and not r.get("new_best", true),
		"쓰러지면 최고 기록은 그대로 (도전 %d)" % int(best["attempts"]))
	_check(FileAccess.get_file_as_bytes(SaveGame.PATH) == save_bytes and _progress_json() == before and not BossRush.active, "쓰러진 뒤에도 save.json·진행 그대로")
	# 5) 들어서자마자 포기 (방이 밝아지는 중에도 결과 화면으로 가야 한다)
	_goto(Game.TITLE_SCENE)
	title = await _wait_scene("title_screen", 10.0) as TitleScreen
	await _frames(4)
	title.activate_item("BossRush")
	var room3 := await _wait_scene(EXPECT[0], 20.0) as BossRoom
	# 장면 전환(밝아짐)이 아직 끝나지 않은 때를 흉내 낸다: Game.go_to 는 그동안 부르면 아무것도 하지 않는다
	Game._busy = true
	var pm := PauseMenu.new()
	room3.add_child(pm)
	pm.open()
	pm._index = pm.row_of("give_up")
	await _shot("rush_pause_menu")
	pm._activate()
	await _wait(0.5)
	_check(get_tree().current_scene == room3 and not BossRush.result.is_empty(), "전환 중에 포기: 전환이 끝나기를 기다린다")
	Game._busy = false
	res = await _wait_scene("boss_rush_result", 20.0) as BossRushResult
	_check(res != null and res.outcome() == "quit" and int(res.result().get("reached", -1)) == 0 and not get_tree().paused, "들어서자마자 '포기하기' → 결과 (포기, 1번째)")
	_check(FileAccess.get_file_as_bytes(SaveGame.PATH) == save_bytes and _progress_json() == before, "포기한 뒤에도 save.json·진행 그대로")
	# 5b) 보스를 쓰러뜨린 직후(다음 방으로 넘어가기 전 약 3.6초 사이)에 포기 (2026-10-20 QA: 그 싸움 시간이 전체에 두 번 들어가고,
	#     포기한 곳에 방금 이긴 보스 이름이 나왔다) → 그 싸움 시간은 한 번만, 지금 싸움 0, 다다른 곳 = 다음 보스
	_goto(Game.TITLE_SCENE)
	title = await _wait_scene("title_screen", 10.0) as TitleScreen
	await _frames(4)
	title.activate_item("BossRush")
	var room5 := await _wait_scene(EXPECT[0], 20.0) as BossRoom
	await _frames(20)
	await room5.debug_force_defeat()
	await _wait(0.3)
	var split5: float = float(BossRush.splits[0]) if BossRush.splits.size() > 0 else -1.0
	var adv5 := BossRush.advancing
	BossRush.give_up()
	res = await _wait_scene("boss_rush_result", 20.0) as BossRushResult
	r = res.result() if res else {}
	_check(res != null and adv5 and str(r.get("outcome", "")) == "quit" and int(r.get("reached", -1)) == 1 and (r.get("splits", []) as Array).size() == 1
		and is_zero_approx(float(r.get("current", -1.0))) and split5 > 0.0 and absf(float(r.get("total", 0.0)) - split5) < 0.001,
		"쓰러뜨린 직후 포기 → 포기, 다다른 곳 %d번째(다음 보스), 지금 싸움 %s, 전체 %s = 첫 싸움 %s (두 번 더하지 않음)" % [int(r.get("reached", -1)) + 1,
		BossRush.format_time(float(r.get("current", -1.0))), BossRush.format_time(float(r.get("total", 0.0))), BossRush.format_time(split5)])
	_check(FileAccess.get_file_as_bytes(SaveGame.PATH) == save_bytes and _progress_json() == before, "쓰러뜨린 직후 포기한 뒤에도 save.json·진행 그대로")
	# 6) 저장 파일이 없을 때: 다 자란 몸, save.json 을 만들지 않는다
	_rm(SaveGame.PATH)
	Progress.reset()
	Progress.flags["cleared"] = true
	var before2 := _progress_json()
	_goto(Game.TITLE_SCENE)
	title = await _wait_scene("title_screen", 10.0) as TitleScreen
	await _frames(4)
	_check(title.has_item("BossRush"), "저장 없이 클리어(이번 실행): 메뉴에 보스 러시")
	title.activate_item("BossRush")
	var room4 := await _wait_scene(EXPECT[0], 20.0) as BossRoom
	await _frames(10)
	var p4: Player = get_tree().get_first_node_in_group("player")
	var full: Dictionary = BossRush.data()["full_power"]
	_check(BossRush.growth_source == "full" and p4.max_dews == 5 and is_equal_approx(p4.max_hp, 100.0 + float(full["upgrades"]["max_hp"]))
		and p4.max_jumps == 2 and Progress.has_ability("light") and Progress.has_ability("wind"),
		"저장 파일이 없으면 다 자란 몸: 체력 %.0f, 이슬 %d, 점프 %d" % [p4.max_hp, p4.max_dews, p4.max_jumps])
	# 다섯째(마지막) 보스를 쓰러뜨린 직후에 포기해도 완주로 남는다 (QA: 'quit' 로 남아 최고 기록·완주 수에 들지 않았다).
	# 다섯 방을 다 돌지 않고, 첫 보스를 쓰러뜨린 뒤 기록 수만 다섯으로 채워 끝 처리를 본다.
	await room4.debug_force_defeat()
	await _wait(0.3)
	var clears_before := int(BossRush.load_best()["clears"])
	BossRush.splits = [float(BossRush.splits[0]) if BossRush.splits.size() > 0 else 1.0, 900.0, 900.0, 900.0, 900.0]
	var sum6 := 0.0
	for v in BossRush.splits:
		sum6 += float(v)
	BossRush.give_up()
	res = await _wait_scene("boss_rush_result", 20.0) as BossRushResult
	r = res.result() if res else {}
	_check(res != null and res.outcome() == "clear" and is_zero_approx(float(r.get("current", -1.0))) and absf(float(r.get("total", 0.0)) - sum6) < 0.001
		and int(BossRush.load_best()["clears"]) == clears_before + 1,
		"다섯째를 쓰러뜨린 직후 포기 → 완주로 기록 (결과 %s, 전체 %s, 완주 수 %d → %d)" % [res.outcome() if res else "-", BossRush.format_time(float(r.get("total", 0.0))), clears_before, int(BossRush.load_best()["clears"])])
	_check(res != null and not SaveGame.has_save() and _progress_json() == before2, "다 자란 몸으로 끝냄 → save.json 을 만들지 않고 진행 그대로")
	# 정리
	_goto(Game.TITLE_SCENE)
	await _frames(10)
	Music.stop(0.0)
	_rm(SaveGame.PATH)
	_rm(BossRush.BEST_PATH)


## 2026-10-20 통합(빛 가루 칸 U1 · 러시 시계 M3 · 영혼 알림): 러시에서는 빛 가루 칸을 숨기고(러시엔 빛 가루가 없다),
## 영혼 전환 알림은 러시 시계·보스 등장 이름과 겹치지 않으며, 열리지 않는 지도의 터치 버튼은 치운다.
func _check_rush_hud_layout(room: Node, ch: Node, hud: Node, player: Player) -> void:
	_check(not ch.dust_box_shown(), "러시 중 빛 가루 칸은 숨는다 (러시용 빈 진행이라 늘 0)")
	var bh: Node = room.get_node_or_null("BossHUD")
	var title_on: bool = bh != null and float(bh.get("_title")) > 0.0
	ch._on_soul_changed(player.soul if player else "wind")
	await _frames(2)
	# 화면 없는 실행의 캔버스 크기는 진짜 화면과 달라서, 세 화면 비율(아이폰·16:9·아이패드)의 캔버스 크기를 잠깐 넣어 재 본다
	var canvases: Array = [ch._canvas, hud._canvas, bh._canvas if bh else null]
	var keep: Array = []
	for c in canvases:
		keep.append(c.size if c else Vector2.ZERO)
	for sz in [Vector2(2338, 1080), Vector2(1920, 1080), Vector2(1920, 1440)]:
		for c in canvases:
			if c:
				c.size = sz
		hud._place()
		var nr: Rect2 = ch.soul_notice_rect()
		var pr: Rect2 = hud.panel_rect()
		var tb: float = ch._boss_title_bottom()
		var tt: float = float(bh.title_y()) - 62.0 if bh else 0.0
		_check(not nr.intersects(pr) and (not title_on or nr.position.y >= tb or nr.end.y <= tt) and nr.end.y < sz.y * 0.6,
			"러시 %s: 영혼 전환 알림 %s 이 러시 시계 %s · 보스 등장 이름(%s, %.0f~%.0f)과 겹치지 않는다" % [sz, nr, pr, "떠 있음" if title_on else "없음", tt, tb])
	for k in canvases.size():
		if canvases[k]:
			canvases[k].size = keep[k]
	hud._place()
	ch._soul_notice_timer = 0.0
	var touch: Node = room.get_node_or_null("TouchControls")
	if touch:
		_check(not touch._buttons().has("map") and touch._buttons().has("menu"), "러시 중 터치 '지도' 버튼은 치우고 '메뉴'는 남긴다")


## 2026-10-20 통합(이펙트 Fx F1 · 보스 러시 M3): 러시가 다음 방으로 저절로 넘어가면 옛 방의 이펙트가 하나도 남지 않는다.
func _check_fx_cleared_on_advance(room: Node) -> void:
	var probe_fx: FxSprite = Fx.spawn("pickup_big", room.player.global_position, {"life": 60.0, "children": false})
	var last_old := Time.get_ticks_msec()
	var t0 := last_old
	while is_instance_valid(room) and get_tree().current_scene == room and Time.get_ticks_msec() - t0 < 20000:
		last_old = Time.get_ticks_msec()
		await get_tree().process_frame
	await _frames(3)
	var stale := 0
	for a in Fx._active:
		if a.born_ms <= last_old:
			stale += 1
	_check(probe_fx != null and stale == 0, "러시: 다음 보스 방으로 넘어가면 옛 방 이펙트를 모두 거둔다 (남은 것 %d, 지금 %d개)" % [stale, Fx.active_count()])


## 방마다 확인하는 것
func _boss_room_checks(room: BossRoom, i: int, save_bytes: PackedByteArray) -> void:
	var t0 := Time.get_ticks_msec()
	while not room.fight_started and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	var player: Player = room.player
	var intro := BossRush.intro_time(i)
	if is_instance_valid(room.boss) and room.boss.state_name() == "INTRO":
		var left := float(room.boss.get("_timer"))
		if intro > 0.0:
			_check(left <= intro + 0.02, "%s: 등장 연출이 짧아졌다 (남은 %.2f초 ≤ %.1f초)" % [EXPECT[i], left, intro])
		else:
			_check(left > 1.0, "%s: 등장 연출은 그대로 (곡 박자, 남은 %.2f초)" % [EXPECT[i], left])
	_check(room._rush and room.fight_started and room.gate_in.closed and is_instance_valid(room.boss) and room.get_node_or_null("BossRushHUD") != null,
		"%s: 러시 모드, 들어서자마자 싸움 (문 닫힘), 보스 있음, 러시 시계" % EXPECT[i])
	_check(player != null and player.global_position.x > room.trigger.position.x and absf(player.global_position.x - BossRush.start_x(i)) < 200.0,
		"%s: 소녀가 싸움터 안 (x %.0f)" % [EXPECT[i], player.global_position.x if player else -1.0])
	await _wait(0.9)
	_check(Music.current() == EXPECT_TRACK[i], "%s: 보스곡 %s (기대 %s)" % [EXPECT[i], Music.current(), EXPECT_TRACK[i]])
	_check(BossRush.running and BossRush.elapsed > 0.3 and BossRush.index == i, "%s: 시계가 간다 (%s)" % [EXPECT[i], BossRush.format_time(BossRush.elapsed)])
	var hud = room.get_node("BossRushHUD")
	var lines: Array = hud.lines()
	_check(str(lines[0]).contains("%d / 5" % (i + 1)) and str(lines[1]).contains(":"), "%s: 러시 시계 글자 %s" % [EXPECT[i], lines])
	var ch = room.get_node_or_null("CombatHUD")
	if i == 0 and ch and ch.has_method("hud_right_x"):
		var pr: Rect2 = hud.panel_rect()
		var right: float = ch.hud_right_x(pr.position.y, pr.end.y)
		_check(pr.position.x >= right, "러시 시계가 체력 막대·이슬 줄과 겹치지 않는다 (시계 왼쪽 %.0f ≥ HUD 오른쪽 %.0f)" % [pr.position.x, right])
		await _check_rush_hud_layout(room, ch, hud, player)
	if player:
		_check(is_equal_approx(player.max_hp, 130.0) and is_equal_approx(player.hp, player.max_hp) and player.max_dews == 5 and player.dews == 5
			and is_equal_approx(player.attack_multiplier, 1.15) and Progress.soul == "wind" and player.soul == "wind" and Progress.has_ability("sap_walk"),
			"%s: 저장된 성장 그대로, 가득 찬 채 시작 (체력 %.0f/%.0f, 이슬 %d/%d, 공격 ×%.2f, 영혼 %s)" % [EXPECT[i], player.hp, player.max_hp, player.dews, player.max_dews, player.attack_multiplier, player.soul])
	if i == 0:
		# 러시 중 저장은 아무것도 쓰지 않는다
		SaveGame.save("x", "res://scenes/rooms/canopy_01.tscn")
		var where := SaveGame.save_now()
		SaveGame.new_game()
		_check(FileAccess.get_file_as_bytes(SaveGame.PATH) == save_bytes and where == "" and BossRush.active, "러시 중 SaveGame.save / save_now / new_game 은 저장 파일을 건드리지 않는다")
		# 일시정지 동안 시계가 멈춘다
		get_tree().paused = true
		var e0 := BossRush.elapsed
		await _wait(0.5)
		var e1 := BossRush.elapsed
		get_tree().paused = false
		_check(is_equal_approx(e0, e1), "일시정지 동안 시계가 멈춘다 (%.3f → %.3f)" % [e0, e1])
	if i == 1:
		var pm := PauseMenu.new()
		room.add_child(pm)
		pm.open()
		_check(pm.row_of("give_up") >= 0 and pm.row_of("save") < 0 and pm.row_of("load") < 0 and pm.row_of("title") < 0 and pm.row_of("music_volume") >= 0,
			"러시 중 일시정지 메뉴: '포기하기' 있음, 저장·불러오기·타이틀로 없음")
		pm.close()
		pm.queue_free()
		await _frames(2)
		# 지도 버튼을 눌러도 열리지 않는다
		var ev := InputEventAction.new()
		ev.action = "map"
		ev.pressed = true
		room._unhandled_input(ev)
		await _frames(2)
		_check(room._map == null, "러시 중 지도가 열리지 않는다")


func _probe_format() -> void:
	_check(BossRush.format_time(83.456) == "01:23.46" and BossRush.format_time(0.0) == "00:00.00" and BossRush.format_time(3725.5) == "1:02:05.50",
		"시간 글자: %s / %s / %s" % [BossRush.format_time(83.456), BossRush.format_time(0.0), BossRush.format_time(3725.5)])
	var names := []
	for i in BossRush.BOSSES.size():
		names.append(BossRush.boss_name(i))
		_check(ResourceLoader.exists(BossRush.scene_of(i)), "러시 보스 방 있음: %s" % BossRush.scene_of(i))
	_check(names == ["잿빛 잎새의 새", "등불 기사", "수액의 여왕", "무쇠 펌프", "뿌리지기"], "러시 순서 (이야기 순서): %s" % [names])

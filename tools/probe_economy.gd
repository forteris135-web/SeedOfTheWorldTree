extends Node
## 재화·성장 묶음 시험 (2026-10-19 기획자 요청 9번). 화면 없이 돈다:
##   godot --headless --path . res://tools/probe_economy.tscn
## 창을 띄우고 돌리면(--headless 없이) screenshots/debug_dust_*.png, debug_stat_menu.png 도 남긴다.
##  1) 적이 쓰러지면 빛 가루 알갱이(Dust)가 생기고 튀어 오른 뒤 소녀에게 흡수돼 Progress.dust 가 그만큼 오른다 (8~12)
##  2) 정화의 손길로 쓰러뜨리면 +20 보너스 (28~32), 구원도 +20 (28~32, 깃발·NPC)
##  3) dust_value 0 이면 안 떨어진다; 소녀 없이 사라지는 알갱이도 값을 잃지 않는다(_exit_tree); 소녀가 없으면 4초 뒤 저절로 흡수
##  4) 중간 보스(canopy_hidden): 보스 몫 0, 방이 60 을 준다
##  5) 보스 방(canopy_boss): 정화 때 200, 깃발로 두 번은 안 준다
##  6) 성장 메뉴 계산: 비용표, 구매 → 성장·dust 감소, 모자라면 거절, 최대 단계 거절; 소녀 수치가 바뀐다
##  7) 세이브 왕복(dust·단계), 옛 세이브(dust 없음) → 0
##  8) 달빛풀 메뉴(GrassMenu): 이동 탭으로 열림 → 좌·우로 성장 탭 → 위·아래·결정으로 구매/거절 → 터치 두 번 구매 → 탭 머리 터치 → 닫기, 바깥 터치 닫기
##  9) 검토 지적 수정: 회피·점프로 닫아도 쉬기 계속(입력 잠금) / '(여기)'를 손길로 골라도 다시 안 열림 / 스틱 한 번 = 한 칸 /
##     이미 골라진 줄도 터치 첫 누르기는 고르기만 / 사면 바로 저장 / HUD 가운데 글자 지움·머리 위 안내 숨김 / 갈 곳 없으면 성장 탭 /
##     메뉴가 손가락 떼기를 삼키지 않음 / 흡수 자리는 가슴 씨앗 / 불러오기 뒤 날던 가루는 더하지 않음 / 중간 보스에게 쓰러졌다 일어나도 다시 묶임
## 마지막에 "[probe] 끝: 실패 N" 을 찍고 그 수로 종료한다. 진짜 세이브 파일은 시작 때 백업하고 끝에 되돌린다.

var _fail := 0
var _room: Node
var _player: Player
var _had_save := false
var _save_backup := ""
var _shots := 0


func _ready() -> void:
	print("[probe] 재화·성장 시험 시작")
	_backup_save()
	await _run()
	_restore_save()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 조건이 참이 될 때까지 기다린다 (시간 제한, 초). 참이면 걸린 시간, 아니면 -1.
func _until(cond: Callable, limit: float) -> float:
	var t := 0.0
	while t < limit:
		await get_tree().process_frame
		t += get_process_delta_time()
		if cond.call():
			return t
	return -1.0


func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SaveGame.PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_string(SaveGame.PATH)


func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
		if f:
			f.store_string(_save_backup)
			f.close()
	elif FileAccess.file_exists(SaveGame.PATH):
		DirAccess.remove_absolute(SaveGame.PATH)


func _save_screenshot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	img.save_png(ProjectSettings.globalize_path("res://screenshots/" + file_name))
	_shots += 1


# ---------- 방 ----------
func _open(room_id: String) -> void:
	await _close()
	Progress.next_spawn = ""
	_room = load("res://scenes/rooms/%s.tscn" % room_id).instantiate()
	add_child(_room)
	await _frames(6)
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player:
		_player._invuln_timer = 9999.0
	await _frames(6)


func _close() -> void:
	if _room:
		_room.queue_free()
		_room = null
		_player = null
		for i in 3:
			await get_tree().process_frame


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	await _frames(2)


func _spawn_enemy(path: String, offset := Vector2(220, 0)) -> EnemyBase:
	var e: EnemyBase = load(path).instantiate()
	var parent: Node = _room.get_node_or_null("Enemies")
	if parent == null:
		parent = _room
	e.position = _player.global_position + offset
	parent.add_child(e)
	await _frames(3)   # _tick_common 이 player 를 잡는다
	return e


func _dust_nodes() -> Array:
	return get_tree().get_nodes_in_group("dust")


func _dust_sum(nodes: Array) -> int:
	var s := 0
	for d in nodes:
		if is_instance_valid(d) and not d._absorbed:
			s += d.value
	return s


## 알갱이가 다 흡수될 때까지 기다린다. 돌려주는 값: 걸린 시간(초), 못 끝나면 -1
func _wait_absorbed(limit := 5.0) -> float:
	return await _until(func(): return _dust_nodes().is_empty(), limit)


## 노드가 사라질 때까지 기다린다 (weakref — 람다가 지워진 객체를 붙들지 않게)
func _wait_gone(node: Variant, limit := 2.0) -> void:
	if not is_instance_valid(node):
		return   # 이미 사라졌다
	var wr: WeakRef = weakref(node)
	await _until(func(): return wr.get_ref() == null, limit)


## 그냥 시간을 기다린다 (초)
func _sleep(seconds: float) -> void:
	await _until(func(): return false, seconds)


# ---------- 시험 ----------
func _run() -> void:
	await _open("canopy_01")
	_check(_player != null, "첫 방에 소녀가 있다")
	if _player == null:
		return
	await _clear_enemies()
	Progress.reset()
	Progress.dust = 0

	await _probe_kill_drop()
	await _probe_purify_bonus()
	await _probe_rescue_bonus()
	await _probe_zero_and_fallbacks()
	await _probe_miniboss()
	await _probe_boss()
	await _probe_stat_logic()
	await _probe_save_roundtrip()
	await _probe_grass_menu()
	await _probe_menu_fixes()
	await _probe_dust_fixes()
	await _probe_miniboss_respawn()
	await _close()


## 1) 쓰러뜨리면 떨어지고, 튀어 오른 뒤 소녀에게 흡수된다
func _probe_kill_drop() -> void:
	var e := await _spawn_enemy("res://scenes/enemies/woodcutter.tscn")
	_check(e.player == _player, "적이 소녀를 알고 있다 (player 잡힘)")
	_check(e.dust_value == 10, "나무꾼 dust_value 기본 10 (%d)" % e.dust_value)
	var before := Progress.dust
	var at := e.global_position
	e.hp = 1.0
	e.receive_hit(HitData.make(5.0, 10.0, _player), null)
	var grains := _dust_nodes()
	var total := _dust_sum(grains)
	print("[probe] 쓰러뜨림: 알갱이 %d개, 값 합 %d, 값들 %s" % [grains.size(), total, grains.map(func(d): return d.value)])
	_check(grains.size() >= Dust.GRAINS_MIN and total >= 8 and total <= 12, "알갱이가 생기고 값 합이 8~12 (합 %d, %d개)" % [total, grains.size()])
	_check(Progress.dust == before, "아직 흡수 전엔 dust 가 안 오른다 (%d)" % Progress.dust)
	# 튀어 오름: 0.12초 뒤 알갱이들이 처음 자리보다 위에 있다
	await _sleep(0.12)
	var risen := 0
	for d in grains:
		if is_instance_valid(d) and d.global_position.y < at.y - 10.0:
			risen += 1
	_check(risen >= grains.size() / 2, "0.12초 뒤 알갱이 절반 이상이 튀어 올라 있다 (%d / %d)" % [risen, grains.size()])
	_save_screenshot("debug_dust_hop.png")
	var took := await _wait_absorbed(4.5)
	print("[probe] 흡수까지 %.2f초, dust %d → %d" % [took, before, Progress.dust])
	_check(took >= 0.0 and took < Dust.MAX_LIFE, "알갱이가 모두 소녀에게 흡수됐다 (%.2f초, 시간 초과 아님)" % took)
	_check(Progress.dust == before + total, "dust 가 값 합만큼 올랐다 (%d → %d, 합 %d)" % [before, Progress.dust, total])
	await _wait_gone(e)   # 묘목이 되고 사라진다


## 2) 정화의 손길(무너진 적) → +20
func _probe_purify_bonus() -> void:
	var e := await _spawn_enemy("res://scenes/enemies/woodcutter.tscn")
	_check(e.dust_amount(true) >= 28 and e.dust_amount(true) <= 32, "정화 양 계산 28~32 (%d)" % e.dust_amount(true))
	_check(e.dust_amount(false) >= 8 and e.dust_amount(false) <= 12, "쓰러뜨림 양 계산 8~12 (%d)" % e.dust_amount(false))
	var before := Progress.dust
	e.purified_by(_player)   # 구원 불가능한 자: 정화 → 쓰러짐(purified=true)
	var grains := _dust_nodes()
	var total := _dust_sum(grains)
	_check(total >= 28 and total <= 32, "정화로 쓰러뜨리면 보너스 +20 (합 %d)" % total)
	var took := await _wait_absorbed(4.5)
	_check(took >= 0.0 and Progress.dust == before + total, "정화 빛 가루 흡수 (%d → %d)" % [before, Progress.dust])
	await _wait_gone(e)


## 2b) 구원 → +20, 깃발, NPC
func _probe_rescue_bonus() -> void:
	Progress.rescued.clear()
	var e := await _spawn_enemy("res://scenes/enemies/woodcutter_savable.tscn")
	_check(e != null and e.savable and e.rescue_id != "", "구원 가능한 나무꾼 (%s)" % (e.rescue_id if e else "-"))
	var before := Progress.dust
	e.purified_by(_player)
	var grains := _dust_nodes()
	var total := _dust_sum(grains)
	_check(total >= 28 and total <= 32, "구원하면 보너스 +20 (합 %d)" % total)
	_check(Progress.rescued.has(e.rescue_id) and Progress.has(e.rescue_id + "_rescued"), "구원 기록·깃발은 그대로 선다")
	var took := await _wait_absorbed(4.5)
	_check(took >= 0.0 and Progress.dust == before + total, "구원 빛 가루 흡수 (%d → %d)" % [before, Progress.dust])
	await _wait_gone(e)
	var npcs := get_tree().get_nodes_in_group("npc")
	_check(npcs.size() >= 1, "구원된 사람(NPC)이 생겼다 (%d)" % npcs.size())
	for n in npcs:
		n.queue_free()
	Progress.rescued.clear()
	Progress.flags.clear()
	await _frames(2)


## 3) dust_value 0 → 없음; 흡수 전에 사라져도 값은 남는다; 소녀가 없으면 4초 뒤 저절로
func _probe_zero_and_fallbacks() -> void:
	var e := await _spawn_enemy("res://scenes/enemies/woodcutter.tscn")
	e.dust_value = 0
	_check(e.dust_amount(true) == 0, "dust_value 0 이면 정화해도 0")
	e.hp = 1.0
	e.receive_hit(HitData.make(5.0, 10.0, _player), null)
	_check(_dust_nodes().is_empty(), "dust_value 0 인 적은 알갱이를 안 떨어뜨린다")
	await _wait_gone(e)
	# 흡수 전에 사라지는 알갱이 (방을 떠날 때처럼)
	var before := Progress.dust
	var grains := Dust.burst(_room, _player.global_position + Vector2(0, -600), 7, null)
	_check(grains.size() >= 2 and _dust_sum(grains) == 7, "Dust.burst(7) → 알갱이 %d개, 합 %d" % [grains.size(), _dust_sum(grains)])
	for g in grains:
		g.queue_free()
	await _frames(2)
	_check(Progress.dust == before + 7, "흡수 전에 사라진 알갱이도 값을 잃지 않는다 (%d → %d)" % [before, Progress.dust])
	# 소녀 없음: 그룸에서 잠시 빼면 알갱이는 떠 있다가 MAX_LIFE 뒤 저절로 흡수
	before = Progress.dust
	_player.remove_from_group("player")
	var g2 := Dust.burst(_room, _player.global_position + Vector2(0, -400), 5, null)
	await _sleep(1.2)
	var alive := 0
	for g in g2:
		if is_instance_valid(g) and not g._absorbed:
			alive += 1
	_check(alive == g2.size() and Progress.dust == before, "소녀가 없으면 1.2초가 지나도 흡수되지 않고 떠 있다 (%d / %d)" % [alive, g2.size()])
	var took := await _wait_absorbed(Dust.MAX_LIFE + 1.5)
	_player.add_to_group("player")
	_check(took >= 0.0 and Progress.dust == before + 5, "소녀가 없어도 %.0f초 뒤엔 저절로 흡수된다 (%d → %d)" % [Dust.MAX_LIFE, before, Progress.dust])
	# Dust.burst 잘못된 입력
	_check(Dust.burst(_room, Vector2.ZERO, 0, null).is_empty() and Dust.burst(null, Vector2.ZERO, 5, null).is_empty(), "총량 0·부모 없음이면 아무것도 안 만든다")
	# 큰 양은 알갱이 수가 GRAINS_MAX 로 묶이고 합은 그대로
	var g3 := Dust.burst(_room, _player.global_position + Vector2(260, -40), 200, _player)
	_check(g3.size() == Dust.GRAINS_MAX and _dust_sum(g3) == 200, "200 → 알갱이 %d개(최대 %d), 합 %d" % [g3.size(), Dust.GRAINS_MAX, _dust_sum(g3)])
	before = Progress.dust
	await _sleep(0.3)
	_save_screenshot("debug_dust_flight.png")
	took = await _wait_absorbed(4.5)
	_check(took >= 0.0 and Progress.dust == before + 200, "200 이 모두 흡수됐다 (%d → %d)" % [before, Progress.dust])


## 4) 중간 보스: 방이 60 을 준다
func _probe_miniboss() -> void:
	Progress.reset()
	await _open("canopy_hidden")
	var boss: EnemyBase = _room.get("_boss")
	_check(boss != null and is_instance_valid(boss), "숨겨진 방에 중간 보스가 있다")
	if boss == null:
		return
	_check(boss.dust_value == 0, "중간 보스 자신의 dust_value 는 0 (방이 준다)")
	_check(_room.dust_reward == 60, "MiniBossRoom.dust_reward 60 (%d)" % _room.dust_reward)
	for e in get_tree().get_nodes_in_group("enemy"):
		if e != boss:
			e.queue_free()
	await _frames(3)
	_player.global_position = boss.global_position + Vector2(-300, 0)
	Progress.dust = 0
	boss.hp = 1.0
	boss.receive_hit(HitData.make(5.0, 10.0, _player), null)
	var grains := _dust_nodes()
	var total := _dust_sum(grains)
	_check(total == 60, "중간 보스가 쓰러지면 알갱이 합 60 (%d, %d개)" % [total, grains.size()])
	_check(Progress.has(_room.defeat_flag), "중간 보스 깃발이 섰다")
	var took := await _wait_absorbed(5.0)
	_check(took >= 0.0 and Progress.dust == 60, "60 이 흡수됐다 (dust %d)" % Progress.dust)


## 5) 보스: 정화 때 200, 한 번만
func _probe_boss() -> void:
	Progress.reset()
	await _open("canopy_boss")
	_check(_room is BossRoom, "canopy_boss 는 BossRoom")
	var room: BossRoom = _room
	_check(room.dust_reward == 200, "BossRoom.dust_reward 200 (%d)" % room.dust_reward)
	_check(not room.fight_started, "소녀는 아직 싸움을 시작하지 않았다 (등장 자리)")
	Progress.dust = 0
	var given := room._drop_boss_dust()
	var grains := _dust_nodes()
	_check(given == 200 and _dust_sum(grains) == 200, "보스 정화 빛 가루 200 (%d, 알갱이 %d개)" % [_dust_sum(grains), grains.size()])
	_check(Progress.has("dust_" + room.defeat_flag), "보스 빛 가루 깃발 dust_%s 가 섰다" % room.defeat_flag)
	var again := room._drop_boss_dust()
	_check(again == 0 and _dust_sum(_dust_nodes()) == 200, "다시 불러도 두 번은 안 준다 (%d)" % again)
	var took := await _wait_absorbed(5.0)
	_check(took >= 0.0 and Progress.dust == 200, "200 이 흡수됐다 (dust %d)" % Progress.dust)
	# 깃발이 세이브에 들어가는지
	SaveGame.save("", room.scene_file_path)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.PATH))
	_check(saved.get("flags", {}).get("dust_" + room.defeat_flag, false) == true and int(saved.get("dust", -1)) == 200, "세이브에 보스 빛 가루 깃발과 dust 200 이 있다")


## 6) 성장 메뉴 계산
func _probe_stat_logic() -> void:
	Progress.reset()
	_player._apply_abilities()
	var items := StatMenu.load_items()
	_check(items.size() == 4, "stats.json 항목 4개 (%d)" % items.size())
	var by := {}
	for it in items:
		by[it["kind"]] = it
	_check(by.has("max_hp") and by.has("attack") and by.has("heal") and by.has("dews"), "항목: 최대 체력·공격력·회복량·이슬")
	if by.size() < 4:
		return
	_check(StatMenu.cost_of(by["max_hp"], 0) == 40 and StatMenu.cost_of(by["max_hp"], 1) == 55 and StatMenu.max_level_of(by["max_hp"]) == 8, "최대 체력: 40, +15/단계, 최대 8")
	_check(StatMenu.cost_of(by["attack"], 0) == 60 and StatMenu.cost_of(by["attack"], 1) == 80 and StatMenu.max_level_of(by["attack"]) == 6, "공격력: 60, +20/단계, 최대 6")
	_check(StatMenu.cost_of(by["heal"], 0) == 50 and StatMenu.cost_of(by["heal"], 1) == 65 and StatMenu.max_level_of(by["heal"]) == 5, "회복량: 50, +15/단계, 최대 5")
	_check(StatMenu.cost_of(by["dews"], 0) == 120 and StatMenu.cost_of(by["dews"], 2) == 280 and StatMenu.max_level_of(by["dews"]) == 3, "이슬: 120, +80/단계, 최대 3")
	Progress.dust = 100
	var hp0 := _player.max_hp
	var r := StatMenu.buy(by["max_hp"], _player)
	_check(r == "" and Progress.dust == 60 and StatMenu.level_of("max_hp") == 1 and is_equal_approx(float(Progress.upgrades.get("max_hp", 0.0)), 10.0), "최대 체력 1단계 구매: dust 100 → %d, 단계 %d, 성장 %s" % [Progress.dust, StatMenu.level_of("max_hp"), Progress.upgrades])
	_check(is_equal_approx(_player.max_hp, hp0 + 10.0), "소녀 최대 체력 %.0f → %.0f" % [hp0, _player.max_hp])
	r = StatMenu.buy(by["attack"], _player)
	_check(r == "" and Progress.dust == 0 and is_equal_approx(_player.attack_multiplier, 1.05), "공격력 1단계 구매: dust 0, 배수 %.2f" % _player.attack_multiplier)
	r = StatMenu.buy(by["heal"], _player)
	_check(r == "no_dust" and Progress.dust == 0 and StatMenu.level_of("heal") == 0, "모자라면 거절 'no_dust' (%s)" % r)
	_check(StatMenu.can_buy(by["heal"]) == "no_dust", "can_buy 도 'no_dust'")
	Progress.add_dust(10000)
	var dews0 := _player.max_dews
	var spent := 0
	for i in 3:
		spent += StatMenu.cost_of(by["dews"], i)
		r = StatMenu.buy(by["dews"], _player)
		_check(r == "", "이슬 %d단계 구매" % (i + 1))
	_check(spent == 600 and Progress.dust == 10000 - 600, "이슬 3단계 비용 합 600 (쓴 %d, 남은 %d)" % [spent, Progress.dust])
	_check(_player.max_dews == dews0 + 3, "소녀 이슬 최대 %d → %d (지금 %d — 쉬는 중이 아니라 채우지 않는다, 상태 %s)" % [dews0, _player.max_dews, _player.dews, _player.state_name()])
	r = StatMenu.buy(by["dews"], _player)
	_check(r == "maxed" and StatMenu.level_of("dews") == 3, "최대 단계면 거절 'maxed' (%s)" % r)
	var before := Progress.dust
	for i in 7:
		r = StatMenu.buy(by["max_hp"], _player)
	_check(r == "" and StatMenu.level_of("max_hp") == 8 and before - Progress.dust == 700, "최대 체력 2~8단계: 비용 합 700 (%d), 단계 %d" % [before - Progress.dust, StatMenu.level_of("max_hp")])
	_check(StatMenu.buy(by["max_hp"], _player) == "maxed" and is_equal_approx(_player.max_hp, 180.0), "9단계는 거절, 소녀 최대 체력 180 (%.0f)" % _player.max_hp)
	_check(StatMenu.current_value_text("max_hp", _player) == "180" and StatMenu.current_value_text("attack", _player) == "+5%" and StatMenu.current_value_text("dews", _player) == "6개", "지금 값 글자: %s / %s / %s / %s" % [StatMenu.current_value_text("max_hp", _player), StatMenu.current_value_text("attack", _player), StatMenu.current_value_text("heal", _player), StatMenu.current_value_text("dews", _player)])


## 7) 세이브 왕복
func _probe_save_roundtrip() -> void:
	var dust0 := Progress.dust
	var ups := Progress.upgrades.duplicate()
	SaveGame.save("", _room.scene_file_path)
	Progress.reset()
	_check(Progress.dust == 0 and Progress.upgrades.is_empty(), "초기화 뒤 dust 0, 성장 없음")
	SaveGame.load_game()
	_check(Progress.dust == dust0, "불러온 뒤 dust %d (저장 %d)" % [Progress.dust, dust0])
	_check(StatMenu.level_of("max_hp") == 8 and StatMenu.level_of("dews") == 3 and StatMenu.level_of("attack") == 1 and StatMenu.level_of("heal") == 0, "단계가 돌아왔다: 체력 %d 공격 %d 회복 %d 이슬 %d" % [StatMenu.level_of("max_hp"), StatMenu.level_of("attack"), StatMenu.level_of("heal"), StatMenu.level_of("dews")])
	_check(is_equal_approx(float(Progress.upgrades.get("max_hp", 0.0)), float(ups.get("max_hp", 0.0))) and is_equal_approx(float(Progress.upgrades.get("attack", 0.0)), 0.05), "성장 값도 그대로 (%s)" % Progress.upgrades)
	_player._apply_abilities()
	_check(is_equal_approx(_player.max_hp, 180.0) and _player.max_dews == 6, "불러온 뒤 소녀 수치 (체력 %.0f, 이슬 %d)" % [_player.max_hp, _player.max_dews])
	# 옛 세이브(dust 없음)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.PATH))
	data.erase("dust")
	var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	SaveGame.load_game()
	_check(Progress.dust == 0, "dust 가 없는 옛 세이브는 0 으로 읽힌다 (%d)" % Progress.dust)
	Progress.dust = dust0
	Progress.dust_changed.emit(Progress.dust)


# ---------- 메뉴 입력 흉내 ----------
func _fake_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	ev = InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
	await get_tree().process_frame


func _fake_touch(pos: Vector2) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = get_viewport().get_final_transform() * pos
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = ev.position
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


## 8) 달빛풀 메뉴
func _probe_grass_menu() -> void:
	var grass: MoonlightGrass = null
	for g in get_tree().get_nodes_in_group("moonlight_grass"):
		if not g.decor:
			grass = g
			break
	_check(grass != null, "이 방에 달빛풀이 있다")
	if grass == null:
		return
	Progress.next_spawn = ""
	grass._register()
	Progress.grasses["probe_other"] = {"scene": "res://scenes/rooms/canopy_02.tscn", "name": "수관 · 시험용 다른 달빛풀"}
	grass._open_menu()
	await get_tree().process_frame
	var menu := grass.menu()
	_check(menu != null and menu is TravelMenu and menu.is_open() and get_tree().paused, "손길 → 달빛풀 메뉴가 열리고(TravelMenu 상속) 멈춤")
	if menu == null:
		return
	_check(menu.tab() == 0 and menu._items.size() == 2 and not menu.stat_panel().visible, "처음엔 이동 탭 (항목 %d, 성장 패널 숨김)" % menu._items.size())
	var touch := _room.get_node_or_null("TouchControls")
	_check(touch != null and not touch.visible, "메뉴가 열린 동안 터치 버튼은 숨는다")
	var idx0: int = menu._index
	await _fake_action("move_down")
	_check(menu._index == (idx0 + 1) % menu._items.size(), "이동 탭에서 아래 → 다음 달빛풀 (%d → %d)" % [idx0, menu._index])
	await _fake_action("move_right")
	_check(menu.tab() == 1 and menu.stat_panel().visible, "오른쪽 → 성장 탭, 패널 보임")
	var stat: StatMenu = menu.stat_panel()
	var si0: int = stat.index
	await _fake_action("move_down")
	_check(stat.index == (si0 + 1) % stat.items.size(), "성장 탭에서 아래 → 다음 항목 (%d → %d)" % [si0, stat.index])
	# 모자람
	var kind: String = stat.items[stat.index]["kind"]
	var lvl0 := StatMenu.level_of(kind)
	var cost := StatMenu.cost_of(stat.items[stat.index], lvl0)
	Progress.dust = 0
	Progress.dust_changed.emit(0)
	await _fake_action("jump")
	var not_enough: String = StatMenu.load_data().get("not_enough", "")
	_check(StatMenu.level_of(kind) == lvl0 and stat._msg == not_enough and stat._shake > 0.0, "모자라면 거절: 글자 '%s', 흔들림 %.2f" % [stat._msg, stat._shake])
	# 충분: 결정으로 구매 (최대 단계인 항목이면 maxed)
	Progress.add_dust(5000)
	await _fake_action("interact")
	if lvl0 < StatMenu.max_level_of(stat.items[stat.index]):
		_check(StatMenu.level_of(kind) == lvl0 + 1 and Progress.dust == 5000 - cost and stat._flash > 0.0, "결정 → %s 한 단계 (%d → %d), dust 5000 → %d, 번쩍 %.2f" % [kind, lvl0, StatMenu.level_of(kind), Progress.dust, stat._flash])
	else:
		_check(StatMenu.level_of(kind) == lvl0 and Progress.dust == 5000, "결정 → %s 는 최대 단계라 거절 (%s)" % [kind, stat._msg])
	_save_screenshot("debug_stat_menu.png")
	# 터치: 다른 줄은 첫 누르기 = 고르기, 두 번째 = 구매 (회복량 줄)
	var heal_i := -1
	for i in stat.items.size():
		if stat.items[i]["kind"] == "heal":
			heal_i = i
	var heal_lvl := StatMenu.level_of("heal")
	var rc := stat.row_rect(heal_i)
	await _fake_touch(rc.get_center())
	_check(stat.index == heal_i and StatMenu.level_of("heal") == heal_lvl, "터치 첫 누르기: 회복량 줄이 골라지고 아직 안 산다")
	await _fake_touch(rc.get_center())
	_check(StatMenu.level_of("heal") == heal_lvl + 1, "같은 줄 두 번째 누르기: 회복량 %d → %d" % [heal_lvl, StatMenu.level_of("heal")])
	# 탭 머리 터치 → 이동 탭
	await _fake_touch(menu._tab_rect(0).get_center())
	_check(menu.tab() == 0 and not stat.visible, "탭 머리(이동) 터치 → 이동 탭")
	await _fake_action("soul_next")
	_check(menu.tab() == 1, "◁▷(영혼 전환) 로도 탭 전환")
	await _fake_action("dodge")
	_check(not menu.is_open() and not get_tree().paused and not stat.visible, "회피 → 닫히고 멈춤 풀림")
	_check(touch != null and touch.visible, "닫히면 터치 버튼이 돌아온다")
	# 다시 열면 이동 탭부터, 바깥 터치로 닫힘
	grass._open_menu()
	await get_tree().process_frame
	_check(menu.is_open() and menu.tab() == 0, "다시 열면 이동 탭")
	await _fake_action("move_right")
	await _fake_touch(Vector2(30, 30))
	_check(not menu.is_open() and not get_tree().paused, "성장 탭에서 바깥 터치 → 닫힘 (이동으로 넘어가지 않음, next_spawn '%s')" % Progress.next_spawn)
	_check(Progress.next_spawn == "", "메뉴만 닫혔고 이동은 일어나지 않았다")
	Progress.grasses.erase("probe_other")
	# 쉬는 중에 사면 체력·이슬이 바로 채워진다
	_player.start_rest(grass)
	await _frames(2)
	Progress.add_dust(500)
	var heal_item := {}
	for it in StatMenu.load_items():
		if it["kind"] == "heal":
			heal_item = it
	_player.dews = 0
	_player.hp = 10.0
	var r := StatMenu.buy(heal_item, _player)
	_check(r == "" and _player.state == Player.State.REST and is_equal_approx(_player.hp, _player.max_hp) and _player.dews == _player.max_dews, "쉬는 중 구매(%s, 상태 %s) → 체력 %.0f/%.0f, 이슬 %d/%d 가득" % [r, _player.state_name(), _player.hp, _player.max_hp, _player.dews, _player.max_dews])


# ---------- 9) 검토 지적 수정 확인 ----------

func _rest_grass() -> MoonlightGrass:
	for g in get_tree().get_nodes_in_group("moonlight_grass"):
		if not g.decor:
			return g
	return null


## 쉬는 자세로 달빛풀 앞에 세우고 메뉴를 연다
func _open_menu_resting(grass: MoonlightGrass) -> GrassMenu:
	_player.global_position = grass.global_position + Vector2(50, -40)
	_player.velocity = Vector2.ZERO
	_player.start_rest(grass)
	await _frames(3)
	grass._open_menu()
	await get_tree().process_frame
	return grass.menu()


## 스틱(왼쪽 스틱 축)을 값들 차례로 한 프레임씩 넣는다
func _stick(axis: int, values: Array) -> void:
	for v in values:
		var ev := InputEventJoypadMotion.new()
		ev.device = 0
		ev.axis = axis
		ev.axis_value = v
		Input.parse_input_event(ev)
		await get_tree().process_frame


func _probe_menu_fixes() -> void:
	var grass := _rest_grass()
	if grass == null:
		_check(false, "달빛풀이 있다")
		return
	grass._register()
	Progress.grasses["probe_other"] = {"scene": "res://scenes/rooms/canopy_02.tscn", "name": "수관 · 시험용 다른 달빛풀"}
	# a) 회피로 닫아도 쉬기 계속 (이동 탭 / 성장 탭), 점프로 '(여기)'를 골라도 쉬기 계속
	for how in ["dodge_travel", "dodge_stat", "jump_here"]:
		var menu := await _open_menu_resting(grass)
		if how == "dodge_stat":
			await _fake_action("move_right")
		if how == "jump_here":
			menu._index = 0
			for i in menu._items.size():
				if menu._items[i]["id"] == grass.grass_id:
					menu._index = i
		await _fake_action("jump" if how == "jump_here" else "dodge")
		await _frames(4)
		_check(not menu.is_open() and _player.state == Player.State.REST, "[%s] 닫힌 뒤에도 쉬기 계속 (메뉴 열림 %s, 상태 %s)" % [how, menu.is_open(), _player.state_name()])
		_check(_player.input_enabled and not menu.is_input_locked(), "[%s] 버튼을 뗀 뒤 입력 잠금이 풀렸다" % how)
	# b) '(여기)'를 손길로 고르면 닫히고, 누르고 있는 동안 다시 열리지 않으며, 뗐다가 다시 누르면 열린다
	var menu := await _open_menu_resting(grass)
	for i in menu._items.size():
		if menu._items[i]["id"] == grass.grass_id:
			menu._index = i
	var ev := InputEventAction.new()
	ev.action = "interact"
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(8)
	_check(not menu.is_open() and _player.state == Player.State.REST and not get_tree().paused, "'(여기)'를 손길로 고름 → 닫힘, 누르고 있는 동안 다시 안 열림 (열림 %s, 상태 %s)" % [menu.is_open(), _player.state_name()])
	await _sleep(GrassMenu.LOCK_MAX + 0.2)
	_check(not menu.is_open() and _player.input_enabled, "계속 누르고 있어도 %.1f초 뒤 잠금은 풀리고, 메뉴는 그대로 닫혀 있다" % GrassMenu.LOCK_MAX)
	ev = InputEventAction.new()
	ev.action = "interact"
	ev.pressed = false
	Input.parse_input_event(ev)
	await _frames(3)
	Input.action_press("interact")
	await _frames(2)
	Input.action_release("interact")
	await get_tree().process_frame
	_check(menu.is_open() and _player.state == Player.State.REST, "손길을 뗐다가 다시 누르면 메뉴가 열린다 (%s)" % menu.is_open())
	# c) 스틱: 한 번 밀기 = 한 칸 (떨림 포함), 가운데로 돌아왔다가 다시 밀면 한 칸 더, 위로 밀면 한 칸 위
	var n: int = menu._items.size()
	var t0: int = menu._index
	await _stick(JOY_AXIS_LEFT_Y, [0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0, 0.97, 1.0, 0.98, 1.0])
	_check(menu._index == (t0 + 1) % n, "이동 탭: 스틱 아래로 한 번 → 한 칸 (%d → %d)" % [t0, menu._index])
	await _stick(JOY_AXIS_LEFT_Y, [0.4, 0.1, 0.0])
	await _stick(JOY_AXIS_LEFT_X, [0.3, 0.7, 1.0, 0.96, 1.0])
	_check(menu.tab() == 1, "스틱 오른쪽 → 성장 탭")
	await _stick(JOY_AXIS_LEFT_X, [1.0, 0.95, 1.0, 0.0])
	_check(menu.tab() == 1, "스틱을 오른쪽에 둔 채 떨려도 탭은 그대로, 가운데로 돌아옴")
	var stat: StatMenu = menu.stat_panel()
	var m := stat.items.size()
	stat.index = 0
	await _stick(JOY_AXIS_LEFT_Y, [0.15, 0.3, 0.45, 0.6, 0.75, 0.9, 1.0, 0.97, 1.0, 0.98, 1.0, 0.99, 1.0])
	_check(stat.index == 1, "성장 탭: 스틱 아래로 한 번 → 한 칸 (0 → %d, 줄 %d)" % [stat.index, m])
	await _stick(JOY_AXIS_LEFT_Y, [0.5, 0.1, 0.0, 0.7, 1.0, 0.0])
	_check(stat.index == 2, "가운데로 돌아왔다가 다시 밀면 한 칸 더 (%d)" % stat.index)
	await _stick(JOY_AXIS_LEFT_Y, [-0.7, -1.0, -0.96, 0.0])
	_check(stat.index == 1, "위로 한 번 → 한 칸 위 (%d)" % stat.index)
	# d) 이미 골라진 줄(키보드로 고른 줄)도 터치 첫 누르기는 고르기만
	Progress.dust = 5000
	Progress.dust_changed.emit(Progress.dust)
	var kind: String = stat.items[stat.index]["kind"]
	var lvl0 := StatMenu.level_of(kind)
	var rc := stat.row_rect(stat.index)
	await _fake_touch(rc.get_center())
	var touch_again: String = StatMenu.load_data().get("touch_again", "")
	_check(StatMenu.level_of(kind) == lvl0 and stat._msg == touch_again, "이미 골라진 줄도 터치 첫 누르기는 고르기만 (%s 단계 %d, 글자 '%s')" % [kind, StatMenu.level_of(kind), stat._msg])
	# e) 두 번째 누르기 → 구매 → 바로 저장
	await _fake_touch(rc.get_center())
	_check(StatMenu.level_of(kind) == lvl0 + 1, "같은 줄 두 번째 누르기 → %s %d → %d" % [kind, lvl0, StatMenu.level_of(kind)])
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.PATH))
	var saved_lvl := int(saved.get("upgrades", {}).get(StatMenu.level_key(kind), 0))
	_check(saved_lvl == lvl0 + 1 and int(saved.get("dust", -1)) == Progress.dust and str(saved.get("grass", "")) == grass.grass_id, "사면 바로 저장된다 (저장 파일: 단계 %d, dust %d / 지금 %d, 달빛풀 '%s')" % [saved_lvl, int(saved.get("dust", -1)), Progress.dust, saved.get("grass", "")])
	await _fake_action("move_down")
	var kind2: String = stat.items[stat.index]["kind"]
	var lvl2 := StatMenu.level_of(kind2)
	await _fake_touch(stat.row_rect(stat.index).get_center())
	_check(StatMenu.level_of(kind2) == lvl2, "키보드로 옮긴 줄도 터치 첫 누르기는 고르기만 (%s)" % kind2)
	await _fake_action("pause")
	await _frames(3)
	_check(not menu.is_open() and _player.state == Player.State.REST, "메뉴 키로 닫음 → 쉬기 계속")
	# f) 쉬자마자 연 메뉴: HUD 가운데 글자·'저장되었다'를 지우고, 머리 위 안내는 숨긴다
	var hud := _room.get_node_or_null("CombatHUD")
	if hud:
		hud.show_message("달빛풀에서 쉰다. 적들이 다시 깨어난다.", 2.5)
		hud.flash("저장되었다")
	await _frames(2)
	grass._open_menu()
	await get_tree().process_frame
	_check(hud == null or (hud._message_timer <= 0.0 and hud._flash_text == ""), "메뉴를 열면 HUD 가운데 글자를 지운다 (남은 %.2f초, 반짝 글자 '%s')" % [hud._message_timer if hud else 0.0, hud._flash_text if hud else ""])
	_check(not grass._prompt.visible, "메뉴가 열린 동안 달빛풀 머리 위 안내 글자는 숨는다")
	# g) 메뉴가 손가락 떼기를 삼키지 않는다 (터치 '이동' 버튼의 손가락을 메뉴가 열린 채 뗌)
	var touch := _room.get_node_or_null("TouchControls")
	if touch and _player.can_interact:
		touch._touches[0] = {"role": "interact", "origin": Vector2.ZERO, "pos": Vector2.ZERO}
		Input.action_press("interact")
		var up := InputEventScreenTouch.new()
		up.index = 0
		up.pressed = false
		up.position = Vector2(5, 5)
		Input.parse_input_event(up)
		await get_tree().process_frame
		_check(menu.is_open() and not Input.is_action_pressed("interact") and not touch._touches.has(0), "메뉴가 열린 채 손가락을 떼면 터치 버튼도 떼어진다 (interact 눌림 %s)" % Input.is_action_pressed("interact"))
	else:
		_check(false, "터치 조작·손길 가능 상태가 있다")
	await _fake_action("dodge")
	await _frames(3)
	# h) 갈 곳이 없으면(피운 달빛풀이 여기 하나뿐) 성장 탭으로 연다
	Progress.grasses.erase("probe_other")
	menu = await _open_menu_resting(grass)
	_check(menu.is_open() and menu.tab() == 1 and menu._items.size() == 1, "다른 달빛풀이 없으면 성장 탭으로 열린다 (탭 %d, 항목 %d)" % [menu.tab(), menu._items.size()])
	await _fake_action("dodge")
	await _frames(3)
	_check(_player.state == Player.State.REST and _player.input_enabled, "닫고 쉬기 계속, 잠금 풀림")
	_player._set_state(Player.State.IDLE)
	await _frames(2)


func _probe_dust_fixes() -> void:
	# i) 흡수 자리: 소녀 가슴 씨앗 (원점 + CHEST_OFFSET, 원점보다 조금 아래)
	var grains := Dust.burst(_room, _player.global_position + Vector2(300, -200), 3, _player)
	var at := []
	for g in grains:
		g.absorbed.connect(func(_v): at.append(g.global_position))
	await _wait_absorbed(4.0)
	var want := _player.global_position + Dust.CHEST_OFFSET
	var ok := at.size() == grains.size()
	for p in at:
		ok = ok and p.distance_to(want) < 4.0
	_check(ok and Dust.CHEST_OFFSET.y > 0.0 and Dust.CHEST_OFFSET.y < 30.0, "알갱이는 가슴 씨앗 자리(원점 아래 %.0fpx)로 빨려 든다 (%s)" % [Dust.CHEST_OFFSET.y, at])
	# j) 세이브를 불러오면 그 전에 날던 알갱이는 값을 더하지 않는다 (일시정지 '불러오기')
	Progress.dust = 100
	SaveGame.save("", _room.scene_file_path)
	var flying := Dust.burst(_room, _player.global_position + Vector2(1400, -300), 30, _player)
	await _sleep(0.1)
	SaveGame.load_game()
	var took := await _wait_absorbed(5.0)
	_check(took >= 0.0 and Progress.dust == 100, "불러오기 뒤 날던 알갱이(합 30)는 불러온 값에 얹히지 않는다 (dust %d)" % Progress.dust)
	var gone := Dust.burst(_room, _player.global_position + Vector2(0, -900), 6, null)
	await _sleep(0.05)
	SaveGame.load_game()
	for g in gone:
		g.queue_free()
	await _frames(2)
	_check(Progress.dust == 100 and flying.size() > 0, "불러온 뒤 흡수 전에 사라진 알갱이도 더하지 않는다 (dust %d)" % Progress.dust)
	var normal := Dust.burst(_room, _player.global_position + Vector2(200, -100), 9, _player)
	await _wait_absorbed(4.0)
	_check(normal.size() > 0 and Progress.dust == 109, "불러온 뒤 새로 떨어진 알갱이는 평소처럼 들어온다 (dust %d)" % Progress.dust)


## k) 중간 보스 방에서 쓰러졌다 일어나면 새 보스를 다시 묶는다 (빛 가루 60·깃발·보상)
func _probe_miniboss_respawn() -> void:
	Progress.reset()
	await _open("canopy_hidden")
	var boss0: EnemyBase = _room.get("_boss")
	_check(boss0 != null and boss0.dust_value == 0, "처음 보스 dust_value 0")
	if boss0 == null:
		return
	_player._invuln_timer = 0.0
	_player._die()
	await _sleep(3.2)
	_player._invuln_timer = 9999.0
	_check(_player.state != Player.State.DEAD, "소녀가 되살아났다 (%s)" % _player.state_name())
	var boss1: EnemyBase = _room.get("_boss")
	var ok := boss1 != null and is_instance_valid(boss1) and boss1 != boss0 and not boss1.is_queued_for_deletion()
	_check(ok, "되살아난 뒤 방의 _boss 는 새로 나타난 보스다 (%s)" % (boss1.name if ok else "-"))
	if not ok:
		return
	_check(boss1.dust_value == 0 and boss1.died.is_connected(_room._on_boss_died), "새 보스도 dust_value 0, 쓰러짐을 듣는다")
	# 싸움이 다시 시작된다 (문 닫힘)
	_player.global_position = Vector2(_room.get_node("BossTrigger").position.x + 60, boss1.global_position.y - 40)
	await _frames(4)
	_check(_room.get("_started") == true and _room.get_node("GateIn").closed, "다시 들어서면 싸움이 시작된다 (문 닫힘)")
	for e in get_tree().get_nodes_in_group("enemy"):
		if e != boss1:
			e.queue_free()
	await _frames(2)
	_player.global_position = boss1.global_position + Vector2(-300, 0)
	Progress.dust = 0
	boss1.hp = 1.0
	boss1.receive_hit(HitData.make(5.0, 10.0, _player), null)
	var total := _dust_sum(_dust_nodes())
	_check(total == 60 and Progress.has(_room.defeat_flag) and is_equal_approx(float(Progress.upgrades.get(_room.reward_type, 0.0)), _room.reward_amount), "되살아난 뒤 쓰러뜨려도 빛 가루 60, 깃발, 보상 (합 %d, 성장 %s)" % [total, Progress.upgrades])
	await _wait_absorbed(5.0)

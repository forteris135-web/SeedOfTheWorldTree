extends Node
## Claude Code용 레벨 확장 묶음 **눈 확인** 스크린샷 (화면 있는 실행에서만 찍힌다. 창이 잠깐 뜬다).
## 실행: godot --path . res://tools/probe_levels2_shots.tscn [-- <저장 폴더>]   (기본 res://screenshots/)
##  - debug_levels2_rage_<방>.png : 중간 보스 분노(몸 뒤 붉은 빛) + 경비대장은 붉은 돌진 예고와 함께
##  - debug_levels2_stagger.png   : 절반 위 흐트러짐 가득 → 크게 휘청(무너짐 아님, '정화의 손길' 글자 없음)
##  - debug_levels2_beast_feet.png / debug_levels2_beast_sprout.png : 채굴 괴수 발이 땅 위에, 쓰러진 뒤 묘목이 땅 위에
##  - debug_levels2_spore.png     : 포자 어미 포자 덩이·후려치기
##  - debug_levels2_map.png       : 수관 새 방 사슬이 지도에서 이어져 보이는지
## 마지막에 "[probe] 끝: 실패 0" 을 찍는다 (그림 판단은 사람이/Claude 가 PNG 를 보고 한다).

var _out := "res://screenshots/"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0].trim_suffix("/") + "/"
	if DisplayServer.get_name() == "headless":
		print("[probe] 화면 없는 실행이라 찍지 않는다")
		print("[probe] 끝: 실패 0")
		get_tree().quit(0)
		return
	await _rage("village_mini_1", true)
	await _rage("canopy_mini_1", false)
	await _stagger()
	await _beast()
	await _spore()
	await _map()
	print("[probe] 끝: 실패 0")
	get_tree().quit(0)


func _save(file_name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(_out + file_name) if _out.begins_with("res://") else _out + file_name
	img.save_png(path)
	print("[probe] 찍음 %s" % path)


func _load(rid: String, spawn := "") -> Node:
	Progress.next_spawn = spawn
	var room: Node = load("res://scenes/rooms/%s.tscn" % rid).instantiate()
	add_child(room)
	for i in 5:
		await get_tree().physics_frame
	return room


func _free(room: Node) -> void:
	room.queue_free()
	for i in 4:
		await get_tree().process_frame


func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _rage(rid: String, red_charge: bool) -> void:
	var room := await _load(rid)
	var pl := _player()
	pl._invuln_timer = 9999.0
	var boss: EnemyBase = room.get("_boss")
	pl.global_position = boss.global_position + Vector2(-460, 60)
	await get_tree().create_timer(0.6).timeout
	boss.hp = boss.max_hp * 0.45
	EliteTraits.check_rage(boss)
	await get_tree().create_timer(1.0).timeout
	if red_charge and boss is Guard:
		# 붉은 돌진 예고를 억지로 세운다 (분노 몸빛과 붉은 예고가 구별되는지)
		boss.facing = -1
		boss.set("charge_chance", 1.0)
		boss._set_state(EnemyBase.State.CHASE)
		boss._timer = 0.0
		var t := 0.0
		while t < 3.0 and boss.anim_hint != "red":
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		await get_tree().create_timer(0.25).timeout
	print("[probe] %s 분노 %s 상태 %s 힌트 '%s'" % [rid, boss.get("rage"), boss.state_name(), boss.anim_hint])
	_save("debug_levels2_rage_%s.png" % rid)
	await _free(room)


func _stagger() -> void:
	var room := await _load("canopy_mini_1")
	var pl := _player()
	pl._invuln_timer = 9999.0
	var boss: EnemyBase = room.get("_boss")
	pl.global_position = boss.global_position + Vector2(-300, 60)
	await get_tree().create_timer(0.8).timeout
	boss.receive_hit(HitData.make(1.0, boss.max_poise + 10.0, pl), null)
	await get_tree().create_timer(0.35).timeout
	print("[probe] 휘청: 상태 %s, 체력 %.0f/%.0f" % [boss.state_name(), boss.hp, boss.max_hp])
	_save("debug_levels2_stagger.png")
	await _free(room)


func _beast() -> void:
	var room := await _load("mine_mini_1")
	var pl := _player()
	pl._invuln_timer = 9999.0
	var boss: EnemyBase = room.get("_boss")
	pl.global_position = boss.global_position + Vector2(-520, 60)
	await get_tree().create_timer(1.6).timeout
	_save("debug_levels2_beast_feet.png")
	boss.hp = 1.0
	boss.receive_hit(HitData.make(5.0, 0.0, pl), null)
	await get_tree().create_timer(1.4).timeout
	_save("debug_levels2_beast_sprout.png")
	await _free(room)


func _spore() -> void:
	Progress.gain_ability("lantern")
	var room := await _load("abyss_mini_1")
	var pl := _player()
	pl._apply_abilities()
	pl._invuln_timer = 9999.0
	var boss: EnemyBase = room.get("_boss")
	pl.global_position = Vector2(1150, 1232)
	var t := 0.0
	var shot := false
	while t < 6.0 and not shot:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var bolts := 0
		for p in get_tree().get_nodes_in_group("projectile"):
			if p is Projectile:
				bolts += 1
		if bolts >= 2:
			await get_tree().create_timer(0.15).timeout
			shot = true
	print("[probe] 포자 어미 상태 %s" % boss.state_name())
	_save("debug_levels2_spore.png")
	Progress.abilities.erase("lantern")
	await _free(room)


func _map() -> void:
	for rid in ["canopy_01", "canopy_02", "canopy_03", "canopy_04", "canopy_05", "canopy_06", "canopy_mini_1", "canopy_mini_2", "canopy_boss", "village_01"]:
		var r := await _load(rid)
		await _free(r)
	var room := await _load("canopy_07")
	room.open_map()
	await get_tree().create_timer(0.8).timeout
	_save("debug_levels2_map.png")
	await _free(room)

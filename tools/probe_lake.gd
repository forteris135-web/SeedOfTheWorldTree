extends Node
## 확장판 · 수액의 호수 묶음 시험 (화면 없이 돈다). 방을 통째로 띄우고 소녀·적·보스를 손으로 돌린다.
## 실행: godot --headless --path . res://tools/probe_lake.tscn   (끝줄 "[probe] 끝: 실패 N")
##       godot --path . res://tools/probe_lake.tscn -- --shots   (창이 뜨고 screenshots/debug_lake_*.png 를 찍는다)
##  1) 방 4개 로드 + 포탈 체인: hidden_descent ↔ sap_lake_01 ↔ sap_lake_02 ↔ sap_lake_boss (대상 방·등장 표식이 있는지), 지역·음악·어둠·지도 등록
##  2) 수액 웅덩이: 능력 없으면 느려지고(거리 절반쯤) 체력이 깎인다 / 있으면 빠르고(1.2배 이상) 체력 그대로.
##     구르기: 능력 없으면 수액에서 짧아지고, 있으면 땅보다 길어진다 (EXPANSION 2장)
##  3) 수액 어부: 예고 길이 2박(0.87초 ±0.06), 채찍 판정 사거리 300, 가까우면 물러남, 줄 그림이 뒤로 흔들렸다 앞으로 뻗는지,
##     판정이 켜지는 첫 프레임에 줄이 이미 소녀 쪽을 가리키고 끝이 판정 끝(≈330)에 닿는지
##  4) 구원 흐름: 구원 가능한 어부 → 무릎 → 손길 → 구원 깃발·사람(이름)·보상(새순 +1)
##  5) 수액의 여왕: 패턴이 마디 첫 박에서 시작, 예고 2박(0.87 ±0.05), 공격·내려앉기가 셋째 박(시계 기준), 가루·나비·물결 생성,
##     내려앉기 반격 창(≥2.5초, 땅 피해 온전·공중 절반), 싸움 내내 여왕 시계 ≈ 보스곡 재생 위치, 디딤돌·바위 5개 이상,
##     2페이즈(디딤돌 가라앉음·예고 길이 흔들림), 쓰러짐 → 섬으로 → 정화 → 깃발·회상 id·능력(sap_walk)·회상 데이터
##  6) 여왕 박자: 히트스톱 10번·일시정지 1초 뒤에도 보스곡과 맞고, 일시정지를 풀자마자 공격이 들어오지 않는다(예정이 마디 단위로 밀림)
##  7) 여왕 나비 되받기(실제 경로: 가드 → 저스트 가드 → 되받은 나비가 여왕에게 맞음): 한 마리 = 45 + 28 + REFLECT_POISE, 두 마리로는 안 무너짐
##  8) 무너진 채 2페이즈로 넘어가면 흐트러짐이 0 으로 돌아간다 (갈라짐 뒤 한 대에 또 무너지지 않음)
##  9) 회상에서 돌아온 보스 방: 호수 수액이 처음엔 잿빛이었다가(깜빡이지 않고) 정화 번짐과 함께 차오른다
## 10) (`-- --hidden` 또는 village_02 에 숨은 입구가 있을 때) 숨은 입구: 멀리선 틈(지도에 없음) → v1.1.0: 등불이 없어도 가까이(400) 가면
##     '본 것'(깃발·지도 ◆·잠긴 포탈 — 들어가지는 못함) → 등불을 얻으면 들어간다.
##     `-- --hidden` 을 주면 village_02 에 입구가 없을 때 실패로 센다 (통합 뒤 link_sap_lake.py 를 빼먹지 않게)
## scripts/world/room.gd 의 시험 함수는 건드리지 않는다.

var _fail := 0
var _room: Node = null
var _room_id := ""
var _player: Player = null
var _shots := false

const ROOMS := ["hidden_descent", "sap_lake_01", "sap_lake_02", "sap_lake_boss"]
const SPAWNS := {"hidden_descent": "FromVillage", "sap_lake_01": "FromDescent", "sap_lake_02": "FromLake01", "sap_lake_boss": "FromLake02"}


func _ready() -> void:
	_shots = "--shots" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	print("[probe] 수액의 호수 시험 시작 (스크린샷 %s)" % _shots)
	await _probe_rooms_and_portals()
	await _probe_sap_pool()
	await _probe_fisher()
	await _probe_rescue()
	await _probe_queen()
	await _probe_queen_sync()
	await _probe_queen_reflect()
	await _probe_queen_phase2_from_broken()
	await _probe_lake_after_memory()
	await _probe_hidden_portal_shots()
	await _close()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


# ---------- 방 띄우기 / 치우기 ----------
func _open(room_id: String, spawn: String) -> void:
	_release_all()
	await _close()
	Progress.next_spawn = spawn
	_room_id = room_id
	_room = load("res://scenes/rooms/%s.tscn" % room_id).instantiate()
	add_child(_room)
	for i in 3:
		await get_tree().physics_frame
	_player = get_tree().get_first_node_in_group("player") as Player
	for i in 6:
		await get_tree().physics_frame


func _close() -> void:
	_release_all()
	if _room:
		_room.queue_free()
		_room = null
		_room_id = ""
		_player = null
		for i in 3:
			await get_tree().process_frame


func _release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "interact", "dodge", "attack_light", "guard"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _wait(sec: float) -> void:
	var t := 0.0
	while t < sec:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()


## 조건이 참이 될 때까지 물리 틱을 기다린다 (시간 제한). 참이면 true.
func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if cond.call():
			return true
	return false


func _shot(name: String) -> void:
	if not _shots:
		return
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(ProjectSettings.globalize_path("res://screenshots/debug_lake_%s.png" % name))
		print("[probe] 스크린샷 screenshots/debug_lake_%s.png" % name)


func _press(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().process_frame
	Input.action_release(action)


# ---------- 1) 방·포탈 ----------
func _probe_rooms_and_portals() -> void:
	for rid in ROOMS:
		await _open(rid, SPAWNS[rid])
		_check(_player != null, "%s: 소녀가 있다" % rid)
		if _player == null:
			continue
		var on := await _until(func(): return _player.is_on_floor(), 2.0)
		_check(on, "%s: 등장 자리 %s 에서 바닥에 선다 (%s)" % [rid, SPAWNS[rid], _player.global_position.round()])
		_check(_room.region == "sap_lake", "%s: 지역 sap_lake" % rid)
		var entry: Dictionary = Progress.visited_rooms.get(rid, {})
		_check(entry.get("region", "") == "sap_lake" and entry.get("name", "") != "", "%s: 지도 등록 (%s, 탐사 %d/%d, 포탈 %d)" % [rid, entry.get("name", ""), entry.get("explore_found", -1), entry.get("explore_total", -1), entry.get("portals", []).size()])
		if rid != "sap_lake_boss":
			_check(Music.current() == "field_sap_lake", "%s: 지역곡 field_sap_lake (지금 '%s')" % [rid, Music.current()])
		if rid == "hidden_descent":
			var cm := false
			for c in _room.get_children():
				if c is CanvasModulate:
					cm = true
			_check(_room.dark and cm, "hidden_descent: 어두운 방 (CanvasModulate)")
		# 포탈 체인
		for p in get_tree().get_nodes_in_group("portal"):
			var target: String = p.target_scene
			var ok_scene := ResourceLoader.exists(target)
			var has_marker := false
			if ok_scene:
				var txt := FileAccess.get_file_as_string(target)
				has_marker = txt.find('[node name="%s" type="Marker2D" parent="Markers"]' % p.spawn_name) >= 0
			if target.ends_with("village_02.tscn") and not has_marker:
				# 마을 쪽 표식은 tools/link_sap_lake.py 가 끼워 넣는다 (통합자가 돌림). `-- --hidden` 이면 꼭 있어야 한다.
				if "--hidden" in OS.get_cmdline_user_args():
					print("[probe]   village_02 에 %s 가 없다 — python3 tools/link_sap_lake.py 를 돌려야 한다" % p.spawn_name)
				else:
					var link := FileAccess.get_file_as_string("res://tools/link_sap_lake.py")
					has_marker = link.find('name="%s"' % p.spawn_name) >= 0
					print("[probe]   (주의) village_02 에 아직 숨은 입구가 없다 — 통합 뒤 python3 tools/link_sap_lake.py 필요 (지금은 도구 안의 표식으로 셈)")
			_check(ok_scene and has_marker, "%s: 포탈 %s → %s (%s)%s" % [rid, p.name, target.get_file(), p.spawn_name, "" if p.requires_ability == "" else " [%s 필요]" % p.requires_ability])
		if _shots:
			_player.get_node("Camera2D").reset_smoothing()
			await _wait(1.0)
			await _shot(rid)
	# 대사 데이터 (깊은 합치기)
	var npcs: Dictionary = DialogueData.load_dialogue("res://data/dialogue/npcs.json")
	_check(npcs.has("fisher_lake") and npcs.has("owen") and npcs["fisher_lake"].get("reward", {}).get("type", "") == "token", "npcs_lake.json 이 합쳐 읽힌다 (fisher_lake: %s)" % npcs.get("fisher_lake", {}).get("name", "-"))
	var mems: Dictionary = DialogueData.load_dialogue("res://data/dialogue/memories.json")
	var mq: Dictionary = mems.get("memory_queen", {})
	var imgs_ok := true
	for l in mq.get("lines", []):
		if not ResourceLoader.exists(l.get("image", "")):
			imgs_ok = false
	_check(mq.get("lines", []).size() == 4 and imgs_ok and mems.has("memory_bird"), "memories_lake.json: memory_queen 4줄 + 그림 있음, 기존 회상 유지")
	var recs: Dictionary = DialogueData.load_dialogue("res://data/dialogue/records.json")
	_check(recs.has("dry_channel_mark") and recs.has("fisher_tally") and recs.has("old_promise"), "records_lake.json: 마른 수로의 표식·어부의 눈금 + 기존 기록물 유지")
	_check(ResourceLoader.exists("res://audio/music/boss_sap_queen.wav") and ResourceLoader.exists("res://audio/music/field_sap_lake.wav"), "정식 곡 2곡(boss_sap_queen, field_sap_lake)이 있다")
	var st: AudioStream = load("res://audio/music/boss_sap_queen.wav")
	_check(st is AudioStreamWAV and (st as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "boss_sap_queen.wav 는 가져올 때 반복(loop forward)으로 읽힌다")


# ---------- 2) 수액 웅덩이 ----------
func _probe_sap_pool() -> void:
	# 수면 자국 벽(sap_lake_02)의 바닥 웅덩이: 900~2400 에 디딤돌이 없어 길게 달릴 수 있다
	await _open("sap_lake_02", "FromLake01")
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	await get_tree().physics_frame
	_player._invuln_timer = 9999.0
	# 땅에서 0.5초 달리기 (웅덩이 왼쪽 바닥 300~900)
	_player.global_position = Vector2(360, 2833)
	_player.velocity = Vector2.ZERO
	await _wait(0.3)
	var x0 := _player.global_position.x
	Input.action_press("move_right")
	await _wait(0.5)
	Input.action_release("move_right")
	var land_d := _player.global_position.x - x0
	# 수액 안에서 0.5초 (능력 없음)
	Progress.abilities.erase("sap_walk")
	_player.global_position = Vector2(960, 2833)   # Lake1 안 (바닥 2900)
	_player.velocity = Vector2.ZERO
	await _wait(0.4)
	var hp0 := _player.hp
	var in_pool := _player.is_on_floor()
	x0 = _player.global_position.x
	Input.action_press("move_right")
	await _wait(0.5)
	Input.action_release("move_right")
	var sap_d := _player.global_position.x - x0
	await _wait(0.8)
	var hp1 := _player.hp
	_check(in_pool and sap_d < land_d * 0.65 and sap_d > 10.0, "수액 안(능력 없음): 0.5초 이동 %.0f px (땅 %.0f px) — 느려진다" % [sap_d, land_d])
	_check(hp1 < hp0, "수액 안(능력 없음): 체력 %.1f → %.1f 조금씩 깎인다" % [hp0, hp1])
	# 능력 있음
	Progress.gain_ability("sap_walk")
	_player.hp = _player.max_hp
	_player.global_position = Vector2(960, 2833)
	_player.velocity = Vector2.ZERO
	await _wait(0.4)
	hp0 = _player.hp
	x0 = _player.global_position.x
	Input.action_press("move_right")
	await _wait(0.5)
	Input.action_release("move_right")
	var glide_d := _player.global_position.x - x0
	await _wait(0.8)
	_check(glide_d > land_d * 1.15, "수액 위 걷기(능력): 0.5초 이동 %.0f px (땅 %.0f px) — 미끄러지듯 빠르다" % [glide_d, land_d])
	_check(_player.hp == hp0, "수액 위 걷기(능력): 체력 그대로 (%.0f)" % _player.hp)
	var pool: SapPool = _room.get_node("Lake1")
	_check(pool.region == "sap_lake" and pool.surface_y() == 2840.0, "웅덩이 region sap_lake, 수면 y=%.0f" % pool.surface_y())
	# 앞 물 (2026-10-20 검수): 수면 아래 몸이 물에 잠겨 보이게 캐릭터(z 0)보다 앞, 이펙트(z 6)보다 뒤에 물빛 겹이 있다
	var front: Node2D = pool.front_layer() if pool.has_method("front_layer") else null
	var fz := front.z_index if front else -99
	_check(front != null and front.is_visible_in_tree() and fz > _player.z_index and fz < 6, "웅덩이 앞 물 겹: z %d (소녀 z %d 보다 앞, 이펙트 6 보다 뒤)" % [fz, _player.z_index])
	# 구르기 거리: 땅 / 수액(능력 없음) / 수액(능력 있음)
	Progress.abilities.erase("sap_walk")
	var roll_land := await _roll_distance(Vector2(340, 2833))
	var roll_sap := await _roll_distance(Vector2(1000, 2833))
	Progress.gain_ability("sap_walk")
	var roll_glide := await _roll_distance(Vector2(1000, 2833))
	_check(roll_sap < roll_land * 0.8 and roll_glide > roll_land * 1.2, "구르기 거리: 땅 %.0f px / 수액(능력 없음) %.0f px / 수액 위 걷기 %.0f px — 능력이 있으면 수액 위에서 더 멀리" % [roll_land, roll_sap, roll_glide])
	Progress.abilities.erase("sap_walk")
	await _shot("sap_pool")


## 그 자리에 세우고 오른쪽으로 한 번 구른 거리
func _roll_distance(at: Vector2) -> float:
	_player.global_position = at
	_player.velocity = Vector2.ZERO
	_player.facing = 1
	await _wait(0.4)
	var x0 := _player.global_position.x
	await _press("dodge")
	await _wait(0.5)
	return _player.global_position.x - x0


# ---------- 3) 수액 어부 ----------
func _probe_fisher() -> void:
	await _open("sap_lake_01", "FromDescent")
	var fisher: SapFisher = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is SapFisher and fisher == null:
			fisher = e
		else:
			e.queue_free()
	await get_tree().physics_frame
	_check(fisher != null, "수액 어부가 있다")
	if fisher == null:
		return
	_player._invuln_timer = 9999.0
	_player.global_position = fisher.global_position + Vector2(-260, 0)
	_player.velocity = Vector2.ZERO
	_player.facing = 1
	var vis = fisher.get_node("Visual")
	# 예고 길이: WINDUP 들어선 뒤 STRIKE 까지의 시간
	var marks := {"windup": -1.0, "strike": -1.0, "swing_min": 9.0, "swing_max": -9.0, "box_w": 0.0, "monitoring": false}
	var t := 0.0
	while t < 8.0 and marks.strike < 0.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		_player.global_position = Vector2(fisher.global_position.x - 260.0, _player.global_position.y)
		_player.velocity = Vector2.ZERO
		if fisher.state == EnemyBase.State.WINDUP:
			if marks.windup < 0.0:
				marks.windup = t
			marks.swing_min = minf(marks.swing_min, vis._swing)
		elif fisher.state == EnemyBase.State.STRIKE and marks.windup >= 0.0:
			marks.strike = t
			var r: RectangleShape2D = fisher.hitbox._shape.shape
			marks.box_w = r.size.x
			marks.monitoring = fisher.hitbox.monitoring
			# 판정이 켜진 이 순간 그림의 줄은 어디를 가리키나 (그림은 _process 에서 갱신 → 그림 한 프레임 뒤에 본다)
			await get_tree().process_frame
			var o: Vector2 = vis.line_origin()
			var aim: Vector2 = vis._aim(o, vis._strike_target())
			var tip: Vector2 = o + Vector2(sin(vis._swing) * fisher.facing, cos(vis._swing)) * aim.y
			var to_player := signf(_player.global_position.x - fisher.global_position.x)
			marks["first_dir"] = signf(sin(vis._swing) * fisher.facing) == to_player
			marks["first_tip"] = tip.x * to_player
			if _shots:
				get_tree().paused = true
				await _shot("fisher_strike")
				get_tree().paused = false
	var windup_len: float = marks.strike - marks.windup
	_check(marks.windup >= 0.0 and marks.strike >= 0.0 and absf(windup_len - SapFisher.BEAT * 2.0) < 0.06, "어부 예고 길이 %.2f초 (2박 = %.2f)" % [windup_len, SapFisher.BEAT * 2.0])
	_check(marks.box_w >= 300.0 and marks.monitoring, "어부 채찍 판정 켜짐, 사거리 %.0f (≥300)" % marks.box_w)
	_check(marks.swing_min < -0.8, "어부 예고 동안 줄이 뒤로 흔들린다 (최소 각 %.2f)" % marks.swing_min)
	_check(marks.get("first_dir", false) and marks.get("first_tip", 0.0) > 250.0, "어부 휘두름 첫 프레임: 줄이 이미 소녀 쪽을 가리키고 끝이 판정 끝 가까이 (끝 %.0f px, 판정 끝 330)" % marks.get("first_tip", 0.0))
	# 휘두름 동안 앞으로 뻗는다
	var t2 := 0.0
	while t2 < 0.5 and fisher.state in [EnemyBase.State.STRIKE, EnemyBase.State.RECOVER]:
		await get_tree().physics_frame
		t2 += get_physics_process_delta_time()
		marks.swing_max = maxf(marks.swing_max, vis._swing)
	_check(marks.swing_max > 0.9, "어부 휘두름에 줄이 앞으로 뻗는다 (최대 각 %.2f)" % marks.swing_max)
	# 가까이 가면 물러난다
	await _until(func(): return fisher.state == EnemyBase.State.CHASE, 3.0)
	_player.global_position = fisher.global_position + Vector2(-90, 0)
	_player.velocity = Vector2.ZERO
	var moved_away := await _until(func(): return fisher.velocity.x > 60.0 or fisher.global_position.x - _player.global_position.x > 150.0, 1.5)
	_check(moved_away, "어부는 가까우면 뒤로 물러난다 (거리 %.0f, 속도 %.0f)" % [fisher.global_position.x - _player.global_position.x, fisher.velocity.x])
	await _shot("fisher")


# ---------- 4) 구원 ----------
func _probe_rescue() -> void:
	Progress.reset()
	Progress.gain_ability("double_jump")
	await _open("sap_lake_02", "FromLake01")
	var savable: EnemyBase = null
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.savable and savable == null:
			savable = e
		else:
			e.queue_free()
	await get_tree().physics_frame
	_check(savable != null and savable.rescue_id == "fisher_lake", "구원 가능한 어부(rescue_id fisher_lake)가 있다")
	if savable == null:
		return
	_player._invuln_timer = 9999.0
	_player.global_position = savable.global_position + Vector2(-140, 0)
	_player.facing = 1
	_player.velocity = Vector2.ZERO
	await _wait(0.4)
	savable.hp = 5.0
	var tries := 0
	while is_instance_valid(savable) and savable.state != EnemyBase.State.BROKEN and tries < 8:
		_player.global_position = savable.global_position + Vector2(-140, 0)
		_player.velocity = Vector2.ZERO
		_player.facing = 1
		await _press("attack_light")
		await _wait(0.35)
		tries += 1
	_check(savable.state == EnemyBase.State.BROKEN and savable.hp <= 0.0, "체력이 다하면 쓰러지지 않고 무릎 꿇는다 (상태 %s)" % savable.state_name())
	# 맞으며 밀려난 어부 곁으로 다시 가 선다 (손길은 170px 안에서만)
	_player.global_position = savable.global_position + Vector2(-120, 0)
	_player.velocity = Vector2.ZERO
	_player.facing = 1
	await _wait(0.4)
	_check(_player.can_interact, "무릎 꿇은 어부 곁: 손길 가능 (거리 %.0f)" % _player.global_position.distance_to(savable.global_position))
	var tokens0 := Progress.tokens   # v1.1.0: 어부 보상은 이슬 대신 새순 1
	await _press("interact")
	await _wait(0.2)
	_check(_player.state == Player.State.PURIFY, "손길 → 소녀 정화 자세 (%s)" % _player.state_name())
	await _wait(1.6)
	var npc: RescuedPerson = null
	for n in get_tree().get_nodes_in_group("npc"):
		if n is RescuedPerson:
			npc = n
	_check(Progress.rescued.has("fisher_lake") and Progress.has("fisher_lake_rescued"), "구원 깃발 fisher_lake")
	_check(npc != null and npc._data.get("name", "") == "어부 할란", "사람으로 돌아온 어부 (이름 '%s')" % (npc._data.get("name", "-") if npc else "-"))
	await _wait(4.4)
	_check(Progress.tokens == tokens0 + 1, "보상: 새순 %d → %d" % [tokens0, Progress.tokens])
	await _shot("rescue")
	Progress.reset()


# ---------- 5) 수액의 여왕 ----------
func _probe_queen() -> void:
	Progress.reset()
	Progress.gain_ability("double_jump")
	Game._busy = true   # 회상 장면 전환은 막는다 (next_spawn·pending_memory 까지만 본다)
	await _open("sap_lake_boss", "FromLake02")
	var boss: SapQueen = _room.get_node("Boss")
	# v1.1.0: 체력은 던전 단계 배율(수액의 호수 단계 3 → ×1.331 × 난이도)을 받는다 (Balance.hp_mult)
	var queen_hp := 1300.0 * Balance.hp_mult("sap_lake")
	_check(boss != null and is_equal_approx(boss.max_hp, queen_hp) and boss.max_poise == 170.0, "여왕 체력 1300 × 단계 배율 = %.1f (지금 %.1f), 흐트러짐 170" % [queen_hp, boss.max_hp if boss else 0.0])
	_player._invuln_timer = 9999.0
	_player.global_position = Vector2(1850, 1433)   # 섬 위
	_player.velocity = Vector2.ZERO
	var started := await _until(func(): return _room.fight_started, 2.0)
	_check(started and boss.state == SapQueen.State.INTRO, "섬에 서면 싸움 시작 (문 닫힘 %s, 보스곡 '%s')" % [_room.gate_in.closed, Music.current()])
	_check(Music.current() == "boss_sap_queen", "보스곡 boss_sap_queen")
	# 패턴 기록: 상태 진입 시각(시계)·예고 길이·마디 정렬
	var rec := []   # [{state, clock_start, startup}]
	var cur := {}
	var prev_state: int = boss.state
	var prev_phase := ""
	var shots_done := {}
	var dust_n := 0
	var fly_n := 0
	var wave_ok := false
	var landed_len := 0.0
	var landed_max := 0.0
	var landed_ground := false
	var air_ok := false
	var ground_ok := false
	var t := 0.0
	var phase2_at := -1.0
	var sync_max := 0.0        # |여왕 시계 - 보스곡 위치| 의 최대
	var third_err := 0.0       # 1페이즈 공격·내려앉기가 셋째 박에서 얼마나 벗어났나 (시계 기준)
	var third_n := 0
	var land_deadline := -1.0
	var land_touch_err := -1.0
	while t < 75.0 and boss.state != SapQueen.State.FALLEN:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if _player.global_position.y > 1480.0 or absf(_player.global_position.x - 1850.0) > 300.0:
			_player.global_position = Vector2(1850, 1433)
			_player.velocity = Vector2.ZERO
		var st: int = boss.state
		var mt := Music.playback_time(SapQueen.TRACK)
		if mt >= 0.0 and boss.state != SapQueen.State.WAIT and boss._clock < 40.0:
			sync_max = maxf(sync_max, absf(boss._clock - _qclock(mt)))
		if st != prev_state:
			if st in SapQueen.ATTACK_STATES:
				cur = {"state": SapQueen.State.keys()[st], "clock": boss._clock, "startup": boss.startup_len, "phase": boss.phase}
				rec.append(cur)
				if st == SapQueen.State.LAND:
					land_deadline = boss._phase_end
			if st == SapQueen.State.LANDED:
				landed_len = 0.0
				landed_ground = boss.is_ground()
				if land_deadline >= 0.0 and boss.phase == 1:
					land_touch_err = boss._clock - land_deadline
					var off := fmod(boss._clock, SapQueen.BAR) - SapQueen.BEAT * 2.0
					third_err = maxf(third_err, absf(off))
					third_n += 1
				land_deadline = -1.0
			prev_state = st
		if st == SapQueen.State.LANDED:
			landed_len += dt
			landed_max = maxf(landed_max, landed_len)
			if not ground_ok and landed_len > 0.3:
				var hp_a := boss.hp
				boss.receive_hit(HitData.make(10.0, 0.0, _player), null)
				ground_ok = absf((hp_a - boss.hp) - 10.0) < 0.01
				_check(ground_ok, "내려앉았을 때 피해 온전 (10 → %.1f)" % (hp_a - boss.hp))
			if _shots and not shots_done.has("landed") and landed_len > 0.6:
				shots_done["landed"] = true
				await _shot("queen_landed")
		if st == SapQueen.State.HOVER and not air_ok and boss.phase == 1 and t > 4.0:
			var hp_b := boss.hp
			boss.receive_hit(HitData.make(10.0, 0.0, _player), null)
			air_ok = absf((hp_b - boss.hp) - 5.0) < 0.01
			_check(air_ok, "공중에선 피해 절반 (10 → %.1f)" % (hp_b - boss.hp))
			# 되받은 나비(소녀 쪽 공격인데 출처가 여왕): 피해 온전 + 흐트러짐 +REFLECT_POISE (실제 경로는 _probe_queen_reflect)
			var poise0: float = boss.poise
			var hp_c := boss.hp
			var rh := HitData.make(14.0, 0.0, boss)
			rh.from_player = true
			boss.receive_hit(rh, null)
			_check(boss.poise - poise0 >= SapQueen.REFLECT_POISE - 0.01 and absf((hp_c - boss.hp) - 14.0) < 0.01 and boss.reflected_count == 1, "되받은 나비: 피해 온전(14 → %.1f), 흐트러짐 +%.0f (%.0f → %.0f)" % [hp_c - boss.hp, SapQueen.REFLECT_POISE, poise0, boss.poise])
		var ph: String = boss.attack_phase
		if ph != prev_phase:
			if ph == "active" and boss.phase == 1:
				var off2 := fmod(boss._clock, SapQueen.BAR) - SapQueen.BEAT * 2.0
				third_err = maxf(third_err, absf(off2))
				third_n += 1
			if ph == "active":
				match st:
					SapQueen.State.DUST:
						await get_tree().physics_frame
						dust_n = maxi(dust_n, _count_proj("dust"))
						if _shots and not shots_done.has("dust"):
							shots_done["dust"] = true
							await _wait(0.3)
							await _shot("queen_dust")
					SapQueen.State.BUTTERFLIES:
						await _wait(0.5)
						fly_n = maxi(fly_n, _count_proj("butterfly"))
						if _shots and not shots_done.has("fly"):
							shots_done["fly"] = true
							await _shot("queen_butterflies")
					SapQueen.State.WAVE:
						await get_tree().physics_frame
						for w in get_tree().get_nodes_in_group("projectile"):
							if w is SapWave:
								var x0: float = w.global_position.x
								await _wait(0.2)
								if is_instance_valid(w):
									wave_ok = absf(w.global_position.y - 1560.0) < 2.0 and absf(w.global_position.x - x0) > 60.0
									if not wave_ok:
										print("[probe]   물결 y %.0f (수면 1560), 이동 %.0f" % [w.global_position.y, w.global_position.x - x0])
								break
						if _shots and not shots_done.has("wave"):
							shots_done["wave"] = true
							await _shot("queen_wave")
			prev_phase = ph
		if boss.phase == 2 and phase2_at < 0.0:
			phase2_at = t
			if _shots:
				await _wait(0.6)
				await _shot("queen_crack")
		# 18초가 지나고 1페이즈면 체력을 절반 아래로 (2페이즈)
		if t > 22.0 and boss.phase == 1 and boss.state not in [SapQueen.State.CRACK]:
			boss.hp = boss.max_hp * 0.45
			boss.receive_hit(HitData.make(1.0, 0.0, _player), null)
		if t > 40.0 and boss.state not in [SapQueen.State.FALLEN, SapQueen.State.CRACK]:
			boss.hp = 1.0
			boss.receive_hit(HitData.make(5.0, 0.0, _player), null)
	# ---- 기록 평가 ----
	var p1 := rec.filter(func(e): return e["phase"] == 1)
	var names := p1.map(func(e): return e["state"])
	print("[probe] 1페이즈 패턴 순서: %s" % [names])
	_check(names.size() >= 4 and names.has("DUST") and names.has("WAVE") and names.has("BUTTERFLIES") and names.has("LAND"), "1페이즈에 가루·물결·나비 떼·내려앉기가 모두 나온다")
	var bar_ok := true
	var startup_ok := true
	for e in p1:
		var off: float = fmod(e["clock"], SapQueen.BAR)
		if minf(off, SapQueen.BAR - off) > 0.05:
			bar_ok = false
			print("[probe]   %s 시작 시계 %.3f (마디 %.3f 의 배수 아님, 어긋남 %.3f)" % [e["state"], e["clock"], SapQueen.BAR, off])
		if absf(e["startup"] - SapQueen.BEAT * 2.0) > 0.05:
			startup_ok = false
			print("[probe]   %s 예고 %.3f (2박 %.3f 아님)" % [e["state"], e["startup"], SapQueen.BEAT * 2.0])
	_check(bar_ok, "1페이즈 패턴은 마디 첫 박에서 시작한다 (138bpm, 한 마디 %.3f초)" % SapQueen.BAR)
	_check(startup_ok, "1페이즈 예고는 2박 = %.2f초" % (SapQueen.BEAT * 2.0))
	_check(third_n >= 4 and third_err < 0.04, "1페이즈 공격·내려앉기 %d번이 셋째 박에 (가장 큰 어긋남 %.3f초)" % [third_n, third_err])
	_check(land_touch_err >= -0.001 and land_touch_err < 0.04, "내려앉기: 셋째 박에 딱 앉는다 (예정 시각과 차이 %.3f초 — 예전엔 0.33초 늦었다)" % land_touch_err)
	_check(sync_max < SapQueen.BEAT * 0.25, "싸움 내내 여왕 시계가 보스곡 위치와 맞는다 (가장 큰 차이 %.3f초, 한 박 %.3f)" % [sync_max, SapQueen.BEAT])
	_check(dust_n >= boss.dust_count, "날개가루 %d개 (≥%d)" % [dust_n, boss.dust_count])
	_check(fly_n >= boss.butterfly_count, "나비 %d마리 (≥%d), 되받기 가능" % [fly_n, boss.butterfly_count])
	_check(wave_ok, "수액 물결이 수면 위를 밀려간다")
	_check(landed_max >= 2.5 and landed_ground, "내려앉기 반격 창 %.2f초 (≥2.5), is_ground %s" % [landed_max, landed_ground])
	# 2페이즈
	_check(phase2_at > 0.0 and boss.phase == 2, "2페이즈 전환 (%.1f초)" % phase2_at)
	var s1: Node2D = _room.get_node("Terrain/SinkStone1")
	_check(s1.collision_layer == 0 and s1.position.y >= 1600.0, "2페이즈: 디딤돌이 가라앉고 충돌이 꺼진다 (y %.0f, 레이어 %d)" % [s1.position.y, s1.collision_layer])
	var stones := 0
	var left_p2 := 0
	for c in _room.get_node("Terrain").get_children():
		var nm := String(c.name)
		if nm.begins_with("Sink") or nm.begins_with("Rock") or nm == "Island":
			stones += 1
			if c.collision_layer != 0:
				left_p2 += 1
	_check(stones >= 5 and left_p2 >= 3 and left_p2 < stones, "디딤돌·바위 %d개, 2페이즈에 남는 것 %d개 (줄어든다)" % [stones, left_p2])
	var p2 := rec.filter(func(e): return e["phase"] == 2)
	var jitter := false
	var in_range := true
	for e in p2:
		var s: float = e["startup"]
		if absf(s - SapQueen.BEAT * 2.0) > 0.02:
			jitter = true
		if s < SapQueen.BEAT * 1.4 or s > SapQueen.BEAT * 2.5:
			in_range = false
	print("[probe] 2페이즈 예고 길이: %s" % [p2.map(func(e): return "%.2f" % e["startup"])])
	_check(p2.size() >= 3 and in_range, "2페이즈 패턴 %d개, 예고 길이가 1.4~2.5박 안" % p2.size())
	_check(jitter or p2.size() < 3, "2페이즈 박자가 엇나간다 (예고 길이 흔들림)")
	# 쓰러짐 → 섬으로 → 정화
	_check(boss.state == SapQueen.State.FALLEN, "체력 0 → FALLEN")
	var down := await _until(func(): return boss.is_on_floor(), 6.0)
	_check(down and absf(boss.global_position.x - 1850.0) < 220.0 and absf(boss.global_position.y - 1500.0) < 30.0, "쓰러진 여왕이 섬으로 내려앉는다 (%s)" % boss.global_position.round())
	await _shot("queen_fallen")
	_player.global_position = boss.global_position + Vector2(-150, -67)
	_player.velocity = Vector2.ZERO
	await _wait(0.5)
	_check(_player.can_interact, "쓰러진 여왕 곁: 손길 가능")
	await _press("interact")
	await _wait(1.6)
	_check(boss.state == SapQueen.State.PURIFIED and Progress.has("boss_queen_defeated"), "정화 → PURIFIED, 깃발 boss_queen_defeated")
	_check(Progress.pending_memory == "memory_queen" and Progress.next_spawn == "AfterBoss", "회상 id memory_queen, 복귀 자리 AfterBoss")
	_check(Purity.is_purified("sap_lake"), "수액의 호수 지역이 정화됨 (수액이 살아난다)")
	# 회상 뒤 능력: BossRoom._after_memory 를 직접 (장면 전환은 막아 두었으므로)
	Progress.set_flag("after_boss_queen_defeated")
	_room._after_memory()
	await _wait(3.4)
	_check(Progress.has_ability("sap_walk"), "회상에서 돌아오면 수액 위 걷기(sap_walk) 획득: %s" % Progress.abilities)
	await _shot("queen_after")
	Game._busy = false
	Progress.reset()


func _count_proj(kind: String) -> int:
	var n := 0
	for p in get_tree().get_nodes_in_group("projectile"):
		if p is SapProjectile and p.sap_kind == kind:
			n += 1
	return n


# ---------- 6) 여왕 박자: 히트스톱·일시정지 ----------
## 여왕을 띄워 싸움을 건다 (공통). 싸움이 시작되고 HOVER 가 될 때까지.
func _start_queen_fight() -> SapQueen:
	Progress.reset()
	Progress.gain_ability("double_jump")
	Game._busy = true
	await _open("sap_lake_boss", "FromLake02")
	var boss: SapQueen = _room.get_node("Boss")
	_player._invuln_timer = 9999.0
	_player.global_position = Vector2(1850, 1433)
	_player.velocity = Vector2.ZERO
	await _until(func(): return _room.fight_started, 2.0)
	await _until(func(): return boss.state == SapQueen.State.HOVER, 4.0)
	return boss


## 보스곡 재생 위치(첫 바퀴) → 여왕의 박자 시계 (첫 강박 DOWNBEAT 가 0; 그 전에는 시계가 0 에서 기다린다)
func _qclock(mt: float) -> float:
	return maxf(SapQueen.clock_from_music(mt), 0.0)


func _real_wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _probe_queen_sync() -> void:
	var boss := await _start_queen_fight()
	_check(boss.state == SapQueen.State.HOVER, "박자 시험: 싸움 시작 → HOVER")
	await _wait(0.5)
	var d0 := absf(boss._clock - _qclock(Music.playback_time(SapQueen.TRACK)))
	# 소녀 타격 10대만큼의 히트스톱 (Juice.hitstop(0.05, 0.05))
	for i in 10:
		Juice.hitstop(0.05, 0.05)
		await _real_wait(0.15)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var d1 := absf(boss._clock - _qclock(Music.playback_time(SapQueen.TRACK)))
	_check(d0 < SapQueen.BEAT * 0.25 and d1 < SapQueen.BEAT * 0.25, "히트스톱 10번 뒤에도 여왕 시계 = 보스곡 위치 (차이 %.3f → %.3f초, 한 박 %.3f)" % [d0, d1, SapQueen.BEAT])
	# 일시정지 1초 (메뉴·지도): 음악은 계속 흐른다 → 여왕 시계는 음악을 따라 건너뛰고, 남은 예정은 마디 단위로 밀린다
	await _until(func(): return boss.state == SapQueen.State.HOVER or boss.attack_phase == "startup", 4.0)
	var rem0: float = boss._left() if boss.attack_phase == "startup" else boss._next_at - boss._clock
	var st0 := boss.state_name()
	get_tree().paused = true
	await _real_wait(1.0)
	get_tree().paused = false
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var d2 := absf(boss._clock - _qclock(Music.playback_time(SapQueen.TRACK)))
	var rem1: float = boss._left() if boss.attack_phase == "startup" else boss._next_at - boss._clock
	var aligned := minf(fmod(boss._next_at, SapQueen.BAR), SapQueen.BAR - fmod(boss._next_at, SapQueen.BAR)) < 0.01
	_check(d2 < SapQueen.BEAT * 0.25, "일시정지 1초 뒤에도 여왕 시계 = 보스곡 위치 (차이 %.3f초)" % d2)
	_check(rem1 >= rem0 - 0.1 and aligned and boss.state_name() == st0, "일시정지를 풀자마자 공격이 들어오지 않는다 (%s, 남은 시간 %.2f → %.2f초, 다음 패턴은 마디 첫 박 %s)" % [st0, rem0, rem1, aligned])
	Game._busy = false
	Progress.reset()


# ---------- 7) 나비 되받기: 실제 경로 ----------
func _probe_queen_reflect() -> void:
	var boss := await _start_queen_fight()
	# 이 시험은 물리 틱으로 기다린다. 그런데 저스트 가드 창(Player._now, 0.24초)과 여왕의 박자 시계(보스곡 재생 위치)는 벽시계로 흘러서,
	# 기계가 바쁘면(전체 회귀 중) 가드를 누르고 나비가 닿기까지 벽시계로 0.24초가 넘어 보통 가드가 되고 되받지 못했다
	# ('흐트러짐 +0' 으로 흔들림, 2026-10-20 검수). 그래서 누른 시각을 나비가 닿기 직전에 다시 맞추고(창 길이는 그대로),
	# 여왕 시계도 물리 틱으로 센다 (곡에 맞춘 박자는 _probe_queen_sync 가 따로 본다). 되받기 흐트러짐 계산은 그대로 본다.
	boss._music_lost = true
	var totals := []
	var states := []
	for k in 2:
		await _until(func(): return boss.state in [SapQueen.State.HOVER, SapQueen.State.DUST, SapQueen.State.BUTTERFLIES, SapQueen.State.WAVE], 8.0)
		if Input.is_action_pressed("guard"):
			Input.action_release("guard")
		# 재는 동안 여왕의 진짜 공격(가루·물결·나비 떼)이 끼어들면 소녀가 맞거나 그 공격을 저스트 가드해서 셈이 흔들린다 →
		# 지금 하던 패턴이 끝나 HOVER 가 되면 다음 패턴을 미루고, 날아다니던 여왕 투사체를 거둔다 (되받는 길은 진짜 그대로).
		await _until(func(): return boss.state == SapQueen.State.HOVER, 8.0)
		boss._next_at = boss._clock + 60.0
		for q in get_tree().get_nodes_in_group("projectile"):
			if is_instance_valid(q) and q.get("from_player") != true:
				q.queue_free()
		await _wait(0.4)
		if k == 0:
			boss.poise = 0.0
		_player._invuln_timer = 0.0
		_player.hp = _player.max_hp
		var px := clampf(boss.global_position.x - 260.0, 1520.0, 2180.0)
		_player.global_position = Vector2(px, 1433)
		_player.velocity = Vector2.ZERO
		await _until(func(): return _player.is_on_floor(), 1.0)
		var f := 1 if boss.global_position.x >= _player.global_position.x else -1
		_player.facing = f
		var poise_before: float = boss.poise
		var jg := [false]
		var cb := func(_src): jg[0] = true
		_player.just_guarded.connect(cb)
		Input.action_press("guard")
		await get_tree().physics_frame
		await get_tree().physics_frame
		var p: SapProjectile = preload("res://scenes/combat/sap_projectile.tscn").instantiate()
		p.sap_kind = "butterfly"
		p.kind = Projectile.Kind.FEATHER
		p.speed = boss.butterfly_speed
		p.damage = boss.butterfly_damage
		p.poise = 0.0
		p.reflectable = true
		p.homing = 1.3
		p.lifetime = 5.0
		p.size = Vector2(34, 26)
		_room.add_child(p)
		p.global_position = _player.global_position + Vector2(f * 80.0, -60.0)
		p.launch(Vector2(-f, 0), boss, false)
		var rc0: int = boss.reflected_count
		var waited := 0.0
		while waited < 0.6 and not jg[0]:
			if is_instance_valid(p) and p.global_position.distance_to(_player.global_position) < 160.0:
				_player._guard_pressed_at = _player._now()   # 벽시계 창을 나비가 닿기 직전에 다시 맞춘다
			await get_tree().physics_frame
			waited += get_physics_process_delta_time()
		await _until(func(): return boss.reflected_count > rc0 or boss.state == SapQueen.State.BROKEN, 3.0)
		_player.just_guarded.disconnect(cb)
		Input.action_release("guard")
		totals.append(boss.poise - poise_before)
		states.append(boss.state_name())
		_player._invuln_timer = 9999.0
	var want := _player.just_guard_poise + 28.0 + SapQueen.REFLECT_POISE
	_check(totals.size() == 2 and absf(totals[0] - want) < 1.0, "나비 한 마리 되받기 흐트러짐 +%.0f (저스트 가드 %.0f + 되받은 나비 28 + 덧붙임 %.0f = %.0f)" % [totals[0] if totals.size() > 0 else -1.0, _player.just_guard_poise, SapQueen.REFLECT_POISE, want])
	_check(states.size() == 2 and states[1] != "BROKEN", "나비 두 마리 되받기로는 아직 무너지지 않는다 (상태 %s, 흐트러짐 %.0f / %.0f)" % [states[1] if states.size() > 1 else "-", boss.poise, boss.max_poise])
	Game._busy = false
	Progress.reset()


# ---------- 8) 무너진 채 2페이즈 ----------
func _probe_queen_phase2_from_broken() -> void:
	var boss := await _start_queen_fight()
	boss.receive_hit(HitData.make(1.0, 400.0, _player), null)
	_check(boss.state == SapQueen.State.BROKEN, "흐트러짐 가득 → BROKEN (%s)" % boss.state_name())
	await _until(func(): return boss.is_ground(), 4.0)
	boss.hp = boss.max_hp * 0.5 + 5.0
	boss.receive_hit(HitData.make(10.0, 0.0, _player), null)
	var poise_at_crack: float = boss.poise
	_check(boss.state == SapQueen.State.CRACK and poise_at_crack == 0.0, "무너진 채 2페이즈 → CRACK, 흐트러짐 %.0f (0 이어야)" % poise_at_crack)
	await _until(func(): return boss.state == SapQueen.State.HOVER, 3.0)
	await _wait(0.3)
	boss.receive_hit(HitData.make(12.0, 20.0, _player), null)
	_check(boss.state != SapQueen.State.BROKEN, "갈라짐 뒤 약공격 한 대로 다시 무너지지 않는다 (%s, 흐트러짐 %.0f)" % [boss.state_name(), boss.poise])
	Game._busy = false
	Progress.reset()


# ---------- 9) 회상에서 돌아온 보스 방의 호수 ----------
func _probe_lake_after_memory() -> void:
	Progress.reset()
	Progress.gain_ability("double_jump")
	Progress.set_flag("boss_queen_defeated")
	Purity.regions["sap_lake"] = true      # 정화 순간 BossRoom 이 해 둔 상태 그대로 회상에서 돌아온다
	await _open("sap_lake_boss", "AfterBoss")
	var pool: SapPool = _room.get_node("Lake")
	var samples := {}
	var t := 0.0
	for want in [0.1, 1.0, 2.0, 2.9, 6.5]:
		await _wait(want - t)
		t = want
		samples[want] = pool._alive
	print("[probe]   회상 뒤 호수 수액 살아남 정도: %s" % [samples])
	var early_max := maxf(maxf(samples[0.1], samples[1.0]), maxf(samples[2.0], samples[2.9]))
	_check(early_max < 0.15 and samples[6.5] > 0.85, "회상 뒤 호수: 잿빛에서 시작해(최대 %.2f) 번짐과 함께 차오른다(%.2f) — 깜빡이지 않음" % [early_max, samples[6.5]])
	_check(Progress.has_ability("sap_walk"), "회상 뒤 수액 위 걷기 획득")
	Progress.reset()
	Purity.regions["sap_lake"] = false


# ---------- 10) 마을의 숨은 입구 ----------
## village_02 에 ToHiddenDescent 가 있어야 돈다 (tools/link_sap_lake.py 를 돌린 뒤). 없으면 건너뛰되, `-- --hidden` 이면 실패로 센다.
## 화면이 있으면(-- --shots) 스크린샷도 찍는다.
func _probe_hidden_portal_shots() -> void:
	var strict := "--hidden" in OS.get_cmdline_user_args()
	var txt := FileAccess.get_file_as_string("res://scenes/rooms/village_02.tscn")
	if txt.find('name="ToHiddenDescent"') < 0:
		if strict:
			_check(false, "village_02 에 숨은 입구(ToHiddenDescent)가 있다 — python3 tools/link_sap_lake.py 를 돌려야 한다")
		else:
			print("[probe] (village_02 에 숨은 입구가 아직 없다 — 통합 뒤 link_sap_lake.py 를 돌리고 -- --hidden 으로 확인)")
		return
	Progress.reset()
	await _open("village_02", "FromVillage01")
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	var hp: HiddenPortal = _room.get_node("Exits/ToHiddenDescent")
	var map_portals: Array = Progress.visited_rooms.get("village_02", {}).get("portals", [])
	_check(not hp._revealed and not hp._glow.visible and not hp.is_in_group("portal") and not map_portals.has(hp.position), "숨은 입구: 처음엔 어두운 틈만 (문 빛 꺼짐, 지도에도 없음)")
	await _shot("hidden_portal_far")
	# v1.1.0: 등불이 없어도 가까이 가면 '본 것' — 깃발·지도 ◆·잠긴 포탈, 손길로는 들어가지 못한다
	_player.global_position = hp.global_position + Vector2(-60, -68)
	_player.velocity = Vector2.ZERO
	_player.facing = 1
	_player.get_node("Camera2D").reset_smoothing()
	await _wait(1.5)
	map_portals = Progress.visited_rooms.get("village_02", {}).get("portals", [])
	_check(hp._revealed and hp.is_in_group("portal") and Progress.has(hp.seen_flag) and map_portals.has(hp.position) and not Progress.has_ability("lantern"),
		"숨은 입구: 등불 없이 다가가도 드러난다 ('본 것' — 깃발 %s, 지도 ◆ %s)" % [Progress.has(hp.seen_flag), map_portals.has(hp.position)])
	await _press("interact")
	await _wait(0.3)
	_check(is_instance_valid(_room) and _room.scene_file_path.ends_with("village_02.tscn") and not hp._used, "등불 없이 손길: 들어가지 않는다 (잠긴 길)")
	await _shot("hidden_portal_locked")
	# 다음에 들어오면 처음부터 (잠긴) 포탈, 등불을 얻으면 들어간다
	await _open("village_02", "FromVillage01")
	var hp2: HiddenPortal = _room.get_node("Exits/ToHiddenDescent")
	_check(hp2._revealed and hp2.is_in_group("portal"), "다시 들어오면 처음부터 드러나 있다 (깃발 기억)")
	Progress.gain_ability("lantern")
	await _shot("hidden_portal_revealed")
	Progress.reset()

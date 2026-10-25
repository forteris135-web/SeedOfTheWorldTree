extends Node
## v1.1.0 방 이동·휴식·부활 시험 (기획자 요청 13, 명세 §4.1–4.3, D10). headless:
##   godot --headless --path . res://tools/probe_respawn.tscn
## 진짜 장면 바꾸기(Game.go_to)로 방을 오간다. 이 시험 노드는 빈 노드를 '지금 장면'으로 세워 장면 바꾸기에 지워지지 않는다.
## (a) 맞은 뒤 포탈로 옮기면 체력·이슬이 그대로 / 달빛풀로 이동해 도착하면 가득
## (b) 쓰러뜨린 일반 적은 방을 나갔다 와도 없다 → 다른 방 달빛풀에서 쉬면 돌아온다. 구원할 수 있는 자·중간 보스는 기억하지 않는다.
## (c) 다른 방에서 쓰러지면 마지막으로 쉰 달빛풀의 방에서 쉬는 자세로, 가득, 쓰러뜨린 기록 비움
## (d) 보스 방(그 방 달빛풀이 마지막)에서 쓰러지면 방을 다시 읽어 보스·잎 더미·투사체가 처음 상태 / 보스를 쓰러뜨린 뒤 쓰러지면 승리 유지
## (e) 보스 러시: 방마다 가득 (앞 보스 방의 체력을 이어 받지 않는다)
## 저장 파일·보스 러시 기록은 시험 전 상태로 되돌린다. 마지막 줄 "[probe] 끝: 실패 N".

var _fail := 0
var _backup := {}


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK  " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	await _frames(2)
	_save_files()
	await _test_carry()
	await _test_kills()
	await _test_death_other_room()
	await _test_boss_room()
	await _test_rush()
	_restore_files()
	Progress.reset()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)


# ---------- 도우미 ----------

## 시험이 쓰는 user:// 파일을 시험 전 상태로 되돌리려고 적어 둔다
func _save_files() -> void:
	for path in [SaveGame.PATH, BossRush.BEST_PATH]:
		_backup[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null


func _restore_files() -> void:
	for path in _backup:
		var data = _backup[path]
		if data == null:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_buffer(data)
				f.close()


## 빈 노드를 '지금 장면'으로 세우고 그 자리를 방으로 바꾼다 (이 시험 노드는 남는다).
func _goto(room_id: String, spawn: String) -> Room:
	var prev := get_tree().current_scene
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	if prev and prev != self:
		prev.queue_free()
	Game._busy = false
	Progress.next_spawn = spawn
	get_tree().change_scene_to_file("res://scenes/rooms/%s.tscn" % room_id)
	return await _wait_room(room_id, null)


## 지금 장면이 room_id 방(앞 방 prev 와 다른 새 것)이 되고, 장면 전환이 끝날 때까지 기다린다. 시간이 넘으면 null.
func _wait_room(room_id: String, prev: Node, limit := 12.0) -> Room:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < limit * 1000.0:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs is Room and cs != prev and is_instance_valid(cs) and cs.scene_file_path.get_file().get_basename() == room_id and cs.is_node_ready():
			while Game.is_busy() and Time.get_ticks_msec() - t0 < limit * 1000.0:
				await get_tree().process_frame
			await _physics(4)
			var room := cs as Room
			if room.player:
				room.player._invuln_timer = 9999.0
			return room
	print("[probe]   방을 기다리다 시간 초과: %s (지금 %s)" % [room_id, get_tree().current_scene.scene_file_path if get_tree().current_scene else "없음"])
	return null


## 방의 포탈 가운데 목적지가 to 인 것
func _portal_to(room: Room, to: String) -> Portal:
	for p in get_tree().get_nodes_in_group("portal"):
		if room.is_ancestor_of(p) and (p as Portal).destination_id() == to:
			return p
	return null


## 포탈로 건너가 새 방을 기다린다
func _through(room: Room, to: String) -> Room:
	var p := _portal_to(room, to)
	if p == null:
		_check(false, "%s 에서 %s 로 가는 포탈이 없다" % [room.room_id, to])
		return null
	p.interact(room.player)
	return await _wait_room(to, room)


## 자리 번호(spawn_key)가 key 인 적 (트리에 살아 있는 것)
func _enemy_with_key(room: Room, key: String) -> EnemyBase:
	for e in get_tree().get_nodes_in_group("enemy"):
		if room.is_ancestor_of(e) and not e.is_queued_for_deletion() and str(e.get_meta("spawn_key", "")) == key:
			return e
	return null


func _grass(room: Room) -> MoonlightGrass:
	for g in get_tree().get_nodes_in_group("moonlight_grass"):
		if room.is_ancestor_of(g):
			return g
	return null


## 달빛풀에 손을 대어 쉰다 (처음이면 피어나는 1.6초 뒤 쉬기). 끝나면 소녀는 쉬는 중.
func _rest_at(room: Room) -> MoonlightGrass:
	var g := _grass(room)
	if g == null:
		return null
	room.player.global_position = g.global_position + Vector2(60, -40)
	room.player.velocity = Vector2.ZERO
	await _physics(4)
	g.interact(room.player)
	var t0 := Time.get_ticks_msec()
	while room.player.state != Player.State.REST and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().physics_frame
	await _physics(2)
	return g


func _full(p: Player) -> bool:
	return is_equal_approx(p.hp, p.max_hp) and p.dews == p.max_dews


# ---------- (a) 방을 옮겨도 체력·이슬이 이어진다 ----------
func _test_carry() -> void:
	Progress.reset()
	var r1 := await _goto("canopy_01", "")
	if r1 == null:
		return
	var p1 := r1.player
	_check(_full(p1), "(a) 새로 시작한 방: 가득 (체력 %.0f/%.0f, 이슬 %d/%d)" % [p1.hp, p1.max_hp, p1.dews, p1.max_dews])
	p1.set_vitals(61.0, 1)
	p1.guard = 10.0
	var r2 := await _through(r1, "canopy_02")
	if r2 == null:
		return
	var p2 := r2.player
	_check(is_equal_approx(p2.hp, 61.0) and p2.dews == 1, "(a) 포탈로 옆 방: 체력·이슬 그대로 (체력 %.0f, 이슬 %d)" % [p2.hp, p2.dews])
	_check(is_equal_approx(p2.guard, p2.max_guard), "(a) 기력(가드 게이지)은 이어 가지 않는다 — 가득 (%.0f/%.0f)" % [p2.guard, p2.max_guard])
	_check(Progress.carry_hp < 0.0 and Progress.carry_dews < 0, "(a) 이어 받은 값은 지운다 (carry %.0f / %d)" % [Progress.carry_hp, Progress.carry_dews])
	p2.set_vitals(48.0, 0)
	var r3 := await _through(r2, "canopy_01")
	if r3 == null:
		return
	_check(is_equal_approx(r3.player.hp, 48.0) and r3.player.dews == 0, "(a) 되돌아와도 그대로 (체력 %.0f, 이슬 %d)" % [r3.player.hp, r3.player.dews])
	# 달빛풀로 이동해 도착 = 쉬기 = 가득
	Progress.grasses["canopy_wind"] = {"scene": "res://scenes/rooms/canopy_02.tscn", "name": "옛 이름"}
	r3.player.set_vitals(30.0, 0)
	Progress.next_spawn = "Grass:canopy_wind"
	Game.go_to("res://scenes/rooms/canopy_02.tscn", 0.2, 0.2)
	var r4 := await _wait_room("canopy_02", r3)
	if r4 == null:
		return
	await _physics(3)
	_check(_full(r4.player) and r4.player.state == Player.State.REST, "(a) 달빛풀로 이동해 도착: 쉬는 자세로 가득 (%s, 체력 %.0f, 이슬 %d)" % [r4.player.state_name(), r4.player.hp, r4.player.dews])
	_check(str(Progress.last_grass.get("name", "")) == RoomIndex.room_name("canopy_02"), "(a) 도착한 달빛풀 이름 = 지도 방 이름 ('%s')" % Progress.last_grass.get("name", ""))


# ---------- (b) 쓰러뜨린 적은 쉬기 전까지 다시 나타나지 않는다 ----------
func _test_kills() -> void:
	Progress.reset()
	var r1 := await _goto("canopy_01", "")
	if r1 == null:
		return
	var key := ""
	var savable_key := ""
	var tracked := 0
	for info in r1._enemy_spawns:
		var e := _enemy_with_key(r1, str(info["key"]))
		if e == null:
			continue
		if e.savable:
			savable_key = str(info["key"])
			_check(not bool(info["track"]), "(b) 구원할 수 있는 자(%s)는 쓰러뜨린 기록을 쓰지 않는다" % e.rescue_id)
		elif bool(info["track"]):
			tracked += 1
			if key == "":
				key = str(info["key"])
	_check(key != "" and savable_key != "" and tracked >= 2, "(b) canopy_01: 기억하는 일반 적 %d, 구원할 수 있는 자 있음 %s" % [tracked, savable_key != ""])
	if key == "":
		return
	var target := _enemy_with_key(r1, key)
	target._die(false)
	await _physics(2)
	_check(Progress.is_killed("canopy_01", key), "(b) 쓰러뜨리면 기록: killed %s" % Progress.killed)
	var r2 := await _through(r1, "canopy_02")
	var r3 := await _through(r2, "canopy_01") if r2 else null
	if r3 == null:
		return
	var other := 0
	for info in r3._enemy_spawns:
		if bool(info["track"]) and str(info["key"]) != key and _enemy_with_key(r3, str(info["key"])) != null:
			other += 1
	_check(_enemy_with_key(r3, key) == null and other == tracked - 1, "(b) 나갔다 와도 쓰러뜨린 적은 없다 (남은 일반 적 %d/%d)" % [other, tracked])
	_check(_enemy_with_key(r3, savable_key) != null, "(b) 구원할 수 있는 자는 그대로 있다")
	# 방 안에서 적이 다시 깨어나도(respawn_enemies) 기록이 남은 자리는 비어 있다
	r3.respawn_enemies()
	await _physics(3)
	_check(_enemy_with_key(r3, key) == null, "(b) respawn_enemies 도 쓰러뜨린 자리는 비워 둔다")
	# 다른 방 달빛풀에서 쉬면 돌아온다
	var r4 := await _through(r3, "canopy_02")
	if r4 == null:
		return
	await _rest_at(r4)
	_check(Progress.killed.is_empty() and r4.player.state == Player.State.REST, "(b) canopy_02 달빛풀에서 쉬면 기록이 비워진다 (%s)" % Progress.killed)
	var r5 := await _through(r4, "canopy_01")
	if r5 == null:
		return
	_check(_enemy_with_key(r5, key) != null, "(b) 쉬고 돌아오면 쓰러뜨렸던 적이 다시 있다")
	# 구원된 자는 쉬어도 돌아오지 않는다 (구원 기록이 맡는다)
	var sv := _enemy_with_key(r5, savable_key)
	if sv:
		Progress.rescued[sv.rescue_id] = true
	var r6 := await _through(r5, "canopy_02")
	if r6:
		Progress.clear_killed()
		var r7 := await _through(r6, "canopy_01")
		if r7:
			_check(_enemy_with_key(r7, savable_key) == null and Progress.killed.get("canopy_01", {}).is_empty(), "(b) 구원된 자는 쉬어도 다시 나타나지 않는다 (구원 기록)")
	# 중간 보스: 깃발이 맡는다 (쓰러뜨린 기록 없음, 쉬어도 다시 나오지 않음)
	Progress.reset()
	var m1 := await _goto("canopy_mini_1", "")
	if m1 == null:
		return
	var boss_info: Dictionary = {}
	for info in m1._enemy_spawns:
		var e := _enemy_with_key(m1, str(info["key"]))
		if e and m1.is_ancestor_of(e) and e == m1.get("_boss"):
			boss_info = info
	_check(not boss_info.is_empty() and not bool(boss_info["track"]), "(b) 중간 보스 방의 보스는 쓰러뜨린 기록을 쓰지 않는다")
	var boss: EnemyBase = m1.get("_boss")
	if boss:
		boss._die(false)
		await _physics(3)
	_check(Progress.has(m1.defeat_flag) and Progress.killed.get("canopy_mini_1", {}).is_empty(), "(b) 중간 보스: 깃발 %s, 기록 %s" % [Progress.has(m1.defeat_flag), Progress.killed])
	Progress.clear_killed()
	var m2 := await _goto("canopy_mini_1", "")
	if m2:
		var live := 0
		for e in get_tree().get_nodes_in_group("enemy"):
			if m2.is_ancestor_of(e) and not e.is_queued_for_deletion():
				live += 1
		_check(live == 0, "(b) 쉬고 다시 와도 중간 보스는 없다 (적 %d)" % live)


# ---------- (c) 다른 방에서 쓰러지면 마지막으로 쉰 달빛풀에서 ----------
func _test_death_other_room() -> void:
	Progress.reset()
	var r1 := await _goto("canopy_02", "")
	if r1 == null:
		return
	var g := await _rest_at(r1)
	_check(g != null and str(Progress.last_grass.get("id", "")) == g.grass_id, "(c) canopy_02 달빛풀에서 쉼 → 마지막 달빛풀 %s" % Progress.last_grass.get("id", ""))
	r1.player._set_state(Player.State.IDLE)
	var r2 := await _through(r1, "canopy_01")
	if r2 == null:
		return
	for info in r2._enemy_spawns:
		if bool(info["track"]):
			var e := _enemy_with_key(r2, str(info["key"]))
			if e:
				e._die(false)
				break
	await _physics(2)
	_check(not Progress.killed.is_empty(), "(c) canopy_01 에서 적 하나 쓰러뜨림 (%s)" % Progress.killed)
	r2.player.set_vitals(25.0, 0)
	r2.player._invuln_timer = 0.0
	r2.player._die()
	var r3 := await _wait_room("canopy_02", r2, 10.0)
	if r3 == null:
		_check(false, "(c) 쓰러진 뒤 마지막 달빛풀의 방(canopy_02)으로 가지 않았다")
		return
	await _physics(4)
	var gd := r3.player.global_position.distance_to(_grass(r3).global_position)
	_check(r3.player.state == Player.State.REST and _full(r3.player) and Progress.killed.is_empty(),
		"(c) canopy_02 달빛풀 곁에서 쉬는 자세 (%s, 거리 %.0f), 가득 (체력 %.0f/%.0f, 이슬 %d), 기록 비움 %s" % [r3.player.state_name(), gd, r3.player.hp, r3.player.max_hp, r3.player.dews, Progress.killed])


# ---------- (d) 보스 방에서 쓰러지면 방을 다시 읽는다 / 보스를 쓰러뜨린 뒤면 승리 유지 ----------
func _test_boss_room() -> void:
	Progress.reset()
	var r1 := await _goto("canopy_boss", "")
	if r1 == null:
		return
	await _rest_at(r1)
	_check(str(Progress.last_grass.get("id", "")) == "canopy_boss_gate", "(d) 보스 방 입구 달빛풀에서 쉼 (%s)" % Progress.last_grass.get("id", ""))
	var br := r1 as BossRoom
	var p := br.player
	p._set_state(Player.State.IDLE)
	p.global_position = Vector2(br.trigger.position.x + 240.0, br.get_node("Markers/GroundLine").position.y - 70.0)
	await _physics(6)
	_check(br.fight_started, "(d) 싸움 시작")
	await _wait(2.5)
	# 싸움을 어지럽힌다: 보스 체력·잎 더미 하나·투사체
	var boss = br.boss
	boss.hp = boss.max_hp - 250.0
	var piles: Array = boss.get("piles") if "piles" in boss else []
	if not piles.is_empty():
		piles[0].consume()
	# 날아가는 보스 투사체 하나 (천천히, 오래) — 다시 읽은 방에는 남지 않아야 한다
	var shot: Node2D = load("res://scenes/combat/projectile.tscn").instantiate()
	shot.speed = 40.0
	shot.lifetime = 30.0
	shot.source = boss
	shot.global_position = p.global_position + Vector2(600, -300)
	br.add_child(shot)
	await _physics(2)
	var proj_before := get_tree().get_nodes_in_group("projectile").size()
	print("[probe]   쓰러지기 전: 보스 체력 %.0f/%.0f, 상태 %s, 잎 더미 %s, 투사체 %d" % [boss.hp, boss.max_hp, boss.state_name(), piles.map(func(x): return x.available), proj_before])
	_check(proj_before >= 1 and not piles.is_empty() and not piles[0].available, "(d) 쓰러지기 전: 투사체 %d, 먹힌 잎 더미 있음" % proj_before)
	p._invuln_timer = 0.0
	p._die()
	var r2 := await _wait_room("canopy_boss", r1, 10.0)
	if r2 == null:
		_check(false, "(d) 보스 방이 다시 읽히지 않았다")
		return
	await _physics(4)
	var b2 := r2 as BossRoom
	var piles2: Array = b2.boss.get("piles") if "piles" in b2.boss else []
	var all_avail := piles2.all(func(x): return x.available)
	var projs := 0
	for n in get_tree().get_nodes_in_group("projectile"):
		if not n.is_queued_for_deletion():
			projs += 1
	_check(r2 != r1 and is_equal_approx(b2.boss.hp, b2.boss.max_hp) and not b2.fight_started and b2.boss.state_name() == "WAIT",
		"(d) 방을 다시 읽음: 보스 체력 %.0f/%.0f, 싸움 %s, 보스 상태 %s" % [b2.boss.hp, b2.boss.max_hp, b2.fight_started, b2.boss.state_name()])
	_check(piles2.size() >= 3 and all_avail and projs == 0, "(d) 잎 더미 %d개 모두 있음 %s, 투사체 %d" % [piles2.size(), all_avail, projs])
	_check(b2.player.state == Player.State.REST and _full(b2.player) and not b2.gate_in.closed, "(d) 입구 달빛풀에서 쉬는 자세로 가득 (%s), 문 열림" % b2.player.state_name())
	# 보스를 쓰러뜨린 뒤(정화 전)에 쓰러지면: 승리는 그대로
	var p2 := b2.player
	p2._set_state(Player.State.IDLE)
	p2._invuln_timer = 9999.0
	p2.global_position = Vector2(b2.trigger.position.x + 240.0, b2.get_node("Markers/GroundLine").position.y - 70.0)
	await _physics(6)
	await b2.debug_force_defeat()
	await _physics(4)
	_check(b2.boss.state_name() == "FALLEN", "(d) 보스를 쓰러뜨림 (%s)" % b2.boss.state_name())
	p2._invuln_timer = 0.0
	p2._die()
	await _wait(3.6)
	var same := get_tree().current_scene == b2
	_check(same and is_instance_valid(b2.boss) and b2.boss.state_name() == "FALLEN" and p2.state != Player.State.DEAD and not b2.gate_in.closed and not Progress.has(b2.defeat_flag),
		"(d) 쓰러뜨린 뒤 쓰러지면 승리 유지: 같은 방 %s, 보스 %s, 소녀 %s, 문 열림 %s" % [same, b2.boss.state_name() if is_instance_valid(b2.boss) else "-", p2.state_name(), not b2.gate_in.closed])


# ---------- (e) 보스 러시: 방마다 가득 ----------
func _test_rush() -> void:
	Progress.reset()
	var prev := get_tree().current_scene
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	if prev and prev != self:
		prev.queue_free()
	Game._busy = false
	BossRush.start()
	var r1 := await _wait_room("canopy_boss", null, 15.0)
	if r1 == null:
		BossRush.restore()
		return
	_check(_full(r1.player), "(e) 러시 첫 방 가득")
	r1.player.set_vitals(20.0, 0)
	await (r1 as BossRoom).debug_force_defeat()
	var r2 := await _wait_room("mine_boss", r1, 15.0)
	if r2:
		_check(_full(r2.player) and Progress.carry_hp < 0.0, "(e) 러시 다음 방도 가득 (체력 %.0f/%.0f, 이슬 %d) — 앞 방 체력을 이어 받지 않는다" % [r2.player.hp, r2.player.max_hp, r2.player.dews])
	BossRush.finish("quit")
	var t0 := Time.get_ticks_msec()
	while BossRush.active and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and cs.scene_file_path == BossRush.RESULT_SCENE:
			break
	await _frames(4)
	if BossRush.active:
		BossRush.restore()
	_check(not BossRush.active, "(e) 러시를 끝내고 진행을 되돌림")

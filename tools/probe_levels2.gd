extends Node
## Claude Code용 레벨 확장 묶음 시험 (화면 없이 돈다).
## 실행: godot --headless --path . res://tools/probe_levels2.tscn
##  1) 정적 점검: scenes/rooms/*.tscn 의 모든 포탈이 가리키는 방 파일이 있고, 그 방에 spawn_name 표식(Markers/<이름>)이 있는지.
##     중간 보스 방(miniboss_room.gd)마다 Enemies/MiniBoss·GateIn·BossTrigger·BossHUD 가 있고, 방의 defeat_flag 가 보스 씬의 깃발과 같은지.
##  2) 중간 보스(일반 몹 거대화) 수치: 기본 적 대비 체력 ×4(기계 ×3)·피해 ×1.5·흐트러짐 ×2.5·걷기 ×0.9·그림/맞는 영역 ×1.8·공격 판정 ×1.6,
##     체력 절반 아래로 맞으면 분노(예고 ×0.8, 붉은 빛 켜짐).
##  3) 새 방 사슬 주행 (입력만으로): canopy_04 포탈 → canopy_05 이끼 계단을 바닥에서 꼭대기까지(옆 가지의 중간 보스 포탈 확인 포함)
##     → canopy_06 바람의 다리 두 틈 → canopy_07 잿빛 둥지 내려가기(장로 포탈 확인) → 보스 방 포탈. 포탈은 손길로 next_spawn 까지만 본다(장면 전환은 막는다).
##  4) 길목 간격(정적): 같은 높이에서 등장 표식·달빛풀 500px 안에 새로 둔 적이 없다, 마을 NPC(대화 자리) 1050px 안에 적이 없다.
##  5) 중간 보스 방: 싸움 전엔 보스가 잠들어 있다(입구에서 기다려도 안 온다) / 소녀가 쓰러져 다시 일어나면 새 보스가 다시 묶여
##     문·체력 바·깃발·보상이 그대로 돈다 / 지역 보스곡 / 포자 어미는 등불이 있어도(심연의 실제 조건) 소녀를 다치게 한다.
## 마지막에 "[probe] 끝: 실패 N" 을 찍고 그 수로 종료한다.

var _fail := 0
var _room: Node = null
var _room_id := ""
var _player: Player = null
var _hits := 0


func _ready() -> void:
	print("[probe] 레벨 확장 시험 시작")
	_static_checks()
	_spacing_checks()
	await _perch_checks()
	await _elite_checks()
	await _mini_room_checks()
	await _chain()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


# ---------- 1) 정적 점검 ----------
func _static_checks() -> void:
	var rooms := {}
	var dir := DirAccess.open("res://scenes/rooms")
	for f in dir.get_files():
		if f.ends_with(".tscn"):
			rooms[f.get_basename()] = FileAccess.get_file_as_string("res://scenes/rooms/" + f)
	var portals := 0
	var bad := 0
	var minis := 0
	for rid in rooms:
		var txt: String = rooms[rid]
		var exts := _ext_paths(txt)
		var nodes := _nodes(txt)
		for n in nodes:
			if n["parent"] == "Exits" and exts.get(n["inst"], "").ends_with("portal.tscn"):
				portals += 1
				var target: String = n["props"].get("target_scene", "").trim_prefix("\"").trim_suffix("\"")
				var spawn: String = n["props"].get("spawn_name", "").trim_prefix("\"").trim_suffix("\"")
				var tid := target.get_file().get_basename()
				var ok_file := rooms.has(tid)
				var ok_marker := ok_file and (rooms[tid] as String).contains('[node name="%s" type="Marker2D" parent="Markers"]' % spawn)
				if not (ok_file and ok_marker):
					bad += 1
					_check(false, "%s/%s → %s 표식 '%s' (방 있음 %s, 표식 있음 %s)" % [rid, n["name"], tid, spawn, ok_file, ok_marker])
		if txt.contains("miniboss_room.gd"):
			minis += 1
			var have := {"MiniBoss": false, "GateIn": false, "BossTrigger": false, "BossHUD": false}
			var boss_scene := ""
			for n in nodes:
				if n["name"] == "MiniBoss" and n["parent"] == "Enemies":
					have["MiniBoss"] = true
					boss_scene = exts.get(n["inst"], "")
				elif n["name"] in have:
					have[n["name"]] = true
			var room_flag: String = _root_prop(txt, "defeat_flag")
			if room_flag == "":
				room_flag = _script_default("res://scripts/world/miniboss_room.gd", "defeat_flag")   # 잿가지의 둥지는 스크립트 기본값을 쓴다
			var scene_flag := ""
			if boss_scene != "" and FileAccess.file_exists(boss_scene):
				scene_flag = _root_prop(FileAccess.get_file_as_string(boss_scene), "defeat_flag")
			var all_have := true
			for k in have:
				all_have = all_have and have[k]
			_check(all_have and room_flag != "" and room_flag == scene_flag, "중간 보스 방 %s: 노드 %s, 방 깃발 '%s' = 보스 씬 깃발 '%s' (%s)" % [rid, have, room_flag, scene_flag, boss_scene.get_file()])
	_check(bad == 0 and portals >= 40, "방 %d개의 포탈 %d개가 모두 있는 방의 있는 표식을 가리킨다 (잘못 %d)" % [rooms.size(), portals, bad])
	_check(minis == 6, "중간 보스 방 6개 (잿가지 거인 + 새 5개): %d" % minis)
	_check(rooms.has("canopy_05") and rooms.has("canopy_06") and rooms.has("canopy_07"), "새 수관 방 canopy_05/06/07 이 있다")
	# 사슬: canopy_04 → 05 → 06 → 07 → boss
	var chain := [["canopy_04", "canopy_05"], ["canopy_05", "canopy_06"], ["canopy_06", "canopy_07"], ["canopy_07", "canopy_boss"]]
	for c in chain:
		_check((rooms[c[0]] as String).contains('target_scene = "res://scenes/rooms/%s.tscn"' % c[1]), "%s 에 %s 로 가는 포탈이 있다" % [c[0], c[1]])
	for c in [["canopy_05", "canopy_mini_1"], ["canopy_07", "canopy_mini_2"], ["village_02", "village_mini_1"], ["mine_02", "mine_mini_1"], ["abyss_02", "abyss_mini_1"]]:
		_check((rooms[c[0]] as String).contains('target_scene = "res://scenes/rooms/%s.tscn"' % c[1]), "%s 에 %s 로 가는 옆 갈래 포탈이 있다" % [c[0], c[1]])
	# 지도 자리가 겹치지 않는가 (모든 방 짝)
	var rects := {}
	for rid in rooms:
		var txt: String = rooms[rid]
		var off := _vec2(_root_prop(txt, "map_offset"))
		var b := _rect(_root_prop(txt, "bounds"))
		if b.size != Vector2.ZERO:
			rects[rid] = Rect2(off, b.size)
	var overlaps := []
	var ids := rects.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Rect2 = rects[ids[i]]
			var bb: Rect2 = rects[ids[j]]
			if a.intersects(bb, false):
				var inter: Rect2 = a.intersection(bb)
				if inter.size.x > 1.0 and inter.size.y > 1.0:
					overlaps.append("%s×%s" % [ids[i], ids[j]])
	_check(overlaps.is_empty(), "지도에서 방 자리가 겹치지 않는다: %s" % [overlaps])


func _ext_paths(txt: String) -> Dictionary:
	var out := {}
	var re := RegEx.create_from_string('\\[ext_resource type="PackedScene"(?: uid="[^"]*")? path="([^"]+)" id="([^"]+)"\\]')
	for m in re.search_all(txt):
		out[m.get_string(2)] = m.get_string(1)
	return out


## 노드 머리글과 그 아래 속성 줄을 모은다: [{name, parent, inst, props}]
func _nodes(txt: String) -> Array:
	var out := []
	var re := RegEx.create_from_string('^\\[node name="([^"]+)"(?: type="[^"]+")?(?: parent="([^"]+)")?(?: instance=ExtResource\\("([^"]+)"\\))?\\]$')
	var cur: Dictionary = {}
	for line in txt.split("\n"):
		var m := re.search(line)
		if m:
			cur = {"name": m.get_string(1), "parent": m.get_string(2), "inst": m.get_string(3), "props": {}}
			out.append(cur)
		elif line.begins_with("["):
			cur = {}
		elif not cur.is_empty() and line.contains(" = "):
			var kv := line.split(" = ", true, 1)
			cur["props"][kv[0].strip_edges()] = kv[1].strip_edges()
	return out


func _root_prop(txt: String, key: String) -> String:
	var head := txt.substr(0, txt.find('[node name="WorldEnvironment"'))
	var re := RegEx.create_from_string("(?m)^%s = (.+)$" % key)
	var m := re.search(head)
	return m.get_string(1).trim_prefix("\"").trim_suffix("\"") if m else ""


## 스크립트의 `@export var <key> := "..."` 기본값
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


# ---------- 2) 중간 보스 수치 ----------
func _elite_checks() -> void:
	# [기본 적, 중간 보스, 체력 배수, 피해 배수(지역 보스보다 세지 않게: 수관 1.1 / 마을 1.3 / 채굴장 1.25 / 심연 1.35)]
	var pairs := [["woodcutter", "elite_woodcutter", 4.0, 1.1], ["gardener", "elite_gardener", 4.0, 1.1], ["guard", "elite_guard", 4.0, 1.3], ["machine", "elite_machine", 3.0, 1.25], ["herbalist", "elite_herbalist", 4.0, 1.35]]
	for p in pairs:
		var base: EnemyBase = load("res://scenes/enemies/%s.tscn" % p[0]).instantiate()
		var el: EnemyBase = load("res://scenes/enemies/%s.tscn" % p[1]).instantiate()
		for e in [base, el]:
			e.gravity = 0.0
			add_child(e)
			e.set_physics_process(false)
			e.get_node("Visual").set_process(false)
			e.player = null
		await get_tree().process_frame
		var hp_mult: float = p[2]
		var ok := is_equal_approx(el.max_hp, base.max_hp * hp_mult) and is_equal_approx(el.hp, el.max_hp)
		var dmg_mult: float = p[3]
		ok = ok and is_equal_approx(el.damage, base.damage * dmg_mult) and is_equal_approx(float(el.get("elite_damage_mult")), dmg_mult) and is_equal_approx(el.max_poise, base.max_poise * 2.5)
		ok = ok and is_equal_approx(el.walk_speed, base.walk_speed * 0.9)
		ok = ok and is_equal_approx(el.hurt_height, base.hurt_height * 1.8) and is_equal_approx(el.hurt_radius, base.hurt_radius * 1.8)
		ok = ok and el.strike_box.size.is_equal_approx(base.strike_box.size * 1.6)
		var vis_ratio: float = el.get_node("Visual").art_scale / base.get_node("Visual").art_scale
		ok = ok and is_equal_approx(vis_ratio, 1.8)
		# 맞는 영역 캡슐과 몸 캡슐도 커졌는가
		var hurt_shape: CapsuleShape2D = null
		for c in el.get_node("Hurtbox").get_children():
			if c is CollisionShape2D:
				hurt_shape = c.shape
		var body_el: CapsuleShape2D = el.get_node("CollisionShape2D").shape
		var body_base: CapsuleShape2D = base.get_node("CollisionShape2D").shape
		ok = ok and hurt_shape != null and is_equal_approx(hurt_shape.radius, el.hurt_radius) and is_equal_approx(hurt_shape.height, el.hurt_height)
		ok = ok and is_equal_approx(body_el.height, body_base.height * 1.8) and is_equal_approx(body_el.radius, body_base.radius * 1.8)
		ok = ok and body_base.height != body_el.height   # 기본 씬의 자원을 건드리지 않았다
		# 몸 바닥이 그림의 발(hurt_height 절반 아래)과 같은가 (눕힌 캡슐 = 기계는 반지름 기준) — 그림이 땅에 묻히지 않게
		var body_node: CollisionShape2D = el.get_node("CollisionShape2D")
		var lying := absf(absf(body_node.rotation) - PI * 0.5) < 0.1
		var body_bottom: float = body_node.position.y + (body_el.radius if lying else body_el.height * 0.5)
		var feet_ok := absf(body_bottom - el.hurt_height * 0.5) < 1.0
		var vis: Node = el.get_node("Visual")
		var vis_ok: bool = vis.get("show_overhead_bar") == false and is_equal_approx(float(vis.get("stride_scale")), 1.8)
		_check(ok and feet_ok and vis_ok, "%s: 체력 %.0f(×%.0f) 피해 %.1f(×%.2f) 흐트러짐 %.0f 걷기 %.0f 키 %.0f 판정 %s 그림 ×%.2f 몸 캡슐 %.0f/%.0f, 몸 바닥 %.0f = 발 %.0f, 머리 위 막대 %s 보폭 ×%s, 깃발 '%s', 이름 '%s'" % [p[1], el.max_hp, hp_mult, el.damage, dmg_mult, el.max_poise, el.walk_speed, el.hurt_height, el.strike_box.size, vis_ratio, body_el.radius, body_el.height, body_bottom, el.hurt_height * 0.5, vis.get("show_overhead_bar"), vis.get("stride_scale"), el.defeat_flag, el.get("elite_name")])
		# 휘청: 체력이 절반 위면 흐트러짐이 차도 무너지지 않고(정화 불가) 크게 휘청인다. 그동안 받는 피해 ×1.5, 휘청임은 맞아도 안 끊긴다.
		el.receive_hit(HitData.make(1.0, el.max_poise + 10.0, null), null)
		var st_ok: bool = el.state == EnemyBase.State.HIT and float(el.get("stagger_left")) > 1.0 and el.poise == 0.0 and el._timer > 1.0
		var hp_a: float = el.hp
		el.receive_hit(HitData.make(10.0, 0.0, null), null)
		var exposed_dmg: float = hp_a - el.hp
		var still_st: bool = el.state == EnemyBase.State.HIT and el._timer > 1.0
		_check(st_ok and is_equal_approx(exposed_dmg, 15.0) and still_st, "%s 절반 위 흐트러짐 가득: 상태 %s(무너짐 아님), 휘청 %.1f초, 휘청 중 10 피해 → %.1f (×1.5), 맞아도 휘청 유지 %s" % [p[1], el.state_name(), float(el.get("stagger_left")), exposed_dmg, still_st])
		el.set("stagger_left", 0.0)
		el.set("exposed_left", 0.0)
		el._set_state(EnemyBase.State.IDLE)
		el.hp = el.max_hp
		el.hp_changed.emit(el.hp, el.max_hp)
		# 분노: 절반 위에서는 안 들어가고, 절반 아래로 맞으면 들어간다
		var w0: float = el.windup_time
		var s0: float = el.walk_speed
		el.hp = el.max_hp * 0.5 + 6.0
		el.receive_hit(HitData.make(5.0, 35.0, null), null)   # 흐트러짐 35: 기계의 약공격 35% 규칙에 걸리지 않는 타격
		var early: bool = el.get("rage")
		el.receive_hit(HitData.make(5.0, 35.0, null), null)
		el._physics_process(1.0 / 60.0)
		var aura: Sprite2D = el.get_node_or_null("RageAura")
		var raged: bool = el.get("rage")
		_check(not early and raged and is_equal_approx(el.windup_time, w0 * 0.8) and is_equal_approx(el.walk_speed, s0 * 1.25) and aura != null and aura.visible and el.state != EnemyBase.State.DEAD,
			"%s 분노: 절반 위 %s → 절반 아래 %s (체력 %.1f/%.0f), 예고 %.2f→%.2f, 걷기 %.0f→%.0f, 붉은 빛 %s" % [p[1], early, raged, el.hp, el.max_hp, w0, el.windup_time, s0, el.walk_speed, aura != null and aura.visible])
		# 절반 아래(분노 중)에서 흐트러짐이 차면 그때는 무너진다 → 정화의 손길
		el._set_state(EnemyBase.State.IDLE)
		el.receive_hit(HitData.make(1.0, el.max_poise + 10.0, null), null)
		_check(el.state == EnemyBase.State.BROKEN, "%s 절반 아래 흐트러짐 가득: 상태 %s (무너짐 → 정화 가능)" % [p[1], el.state_name()])
		base.queue_free()
		el.queue_free()
	await get_tree().process_frame



# ---------- 4) 길목 간격 (정적) ----------
## 예전부터 있던 자리(이번 묶음이 둔 적이 아님)는 기준값으로 둔다: [방, 적, 표식/달빛풀]
const SPACING_BASELINE := [["canopy_03", "Woodcutter5", "FromCanopy04"], ["mine_deep", "Machine1", "Grass1"]]


func _spacing_checks() -> void:
	var dir := DirAccess.open("res://scenes/rooms")
	var bad := []
	var npc_bad := []
	var counted := 0
	for f in dir.get_files():
		if not f.ends_with(".tscn"):
			continue
		var rid := f.get_basename()
		var txt := FileAccess.get_file_as_string("res://scenes/rooms/" + f)
		if txt.contains("miniboss_room.gd") or txt.contains("boss_room.gd"):
			continue
		var exts := _ext_paths(txt)
		var nodes := _nodes(txt)
		var enemies := []
		var spots := []
		var npcs := []
		for n in nodes:
			var pos := _vec2(n["props"].get("position", ""))
			var src: String = exts.get(n["inst"], "")
			if n["parent"] == "Enemies":
				enemies.append([n["name"], pos])
			elif n["parent"] == "Markers":
				spots.append([n["name"], pos])
			elif src.ends_with("moonlight_grass.tscn") and n["props"].get("decor", "false") != "true":
				spots.append([n["name"], pos + Vector2(0, -60)])
			elif src.ends_with("npc.tscn"):
				npcs.append([n["name"], pos + Vector2(0, -60)])
		for e in enemies:
			for sp in spots:
				counted += 1
				var d: Vector2 = (e[1] - sp[1]).abs()
				if d.x < 500.0 and d.y < 120.0 and not [rid, e[0], sp[0]] in SPACING_BASELINE:
					bad.append("%s %s↔%s %.0fpx" % [rid, e[0], sp[0], d.x])
			for npc in npcs:
				var d2: Vector2 = (e[1] - npc[1]).abs()
				if d2.x < 1050.0 and d2.y < 260.0:
					npc_bad.append("%s %s↔%s %.0fpx" % [rid, e[0], npc[0], d2.x])
	_check(bad.is_empty() and counted > 50, "같은 높이에서 등장 표식·달빛풀 500px 안에 적이 없다 (기준값 %d곳 제외, 살핀 짝 %d): %s" % [SPACING_BASELINE.size(), counted, bad])
	_check(npc_bad.is_empty(), "마을 NPC(대화 자리) 1050px 안에 같은 높이의 적이 없다 (발견 750 + 순찰 300): %s" % [npc_bad])



## 가지 위로 옮긴 적이 그 가지에 그대로 서 있는가 (one_way 가지를 뚫고 떨어지지 않는가). 소녀는 멀리 둔다.
func _perch_checks() -> void:
	var cases := [["canopy_02", "Woodcutter4"], ["canopy_05", "Woodcutter4"], ["village_02", "Guard3"], ["mine_02", "Gardener5"], ["abyss_02", "Machine5"], ["canopy_06", "Gardener4"]]
	for c in cases:
		_release_all()
		await _close()
		Progress.next_spawn = ""
		_room = load("res://scenes/rooms/%s.tscn" % c[0]).instantiate()
		var e: EnemyBase = _room.get_node("Enemies/" + c[1])
		var y0: float = e.position.y
		add_child(_room)
		_player = get_tree().get_first_node_in_group("player") as Player
		_player.global_position = Vector2(-5000, -5000)   # 멀리 (알아채지 않게)
		_player.set_physics_process(false)
		await get_tree().create_timer(2.0).timeout
		var ok := is_instance_valid(e) and e.is_on_floor() and absf(e.position.y - y0) < 40.0
		_check(ok, "%s/%s: 2초 뒤 가지 위에 서 있다 (처음 y %.0f → %.0f, 바닥 %s)" % [c[0], c[1], y0, e.position.y if is_instance_valid(e) else -1.0, e.is_on_floor() if is_instance_valid(e) else false])
	await _close()


# ---------- 5) 중간 보스 방 ----------
func _mini_room_checks() -> void:
	# 지역 보스곡
	var music := {}
	for rid in ["canopy_hidden", "canopy_mini_1", "canopy_mini_2", "village_mini_1", "mine_mini_1", "abyss_mini_1"]:
		var r: Node = load("res://scenes/rooms/%s.tscn" % rid).instantiate()
		music[rid] = r.get("boss_music")
		r.free()
	_check(music["village_mini_1"] == "boss_knight" and music["mine_mini_1"] == "boss_knight" and music["abyss_mini_1"] == "boss_rootkeeper_p1" and music["canopy_mini_1"] == "boss_bird",
		"중간 보스 방 곡: %s" % [music])

	# (가) 잠든 보스: 정원사 장로(발견 거리가 가장 멀다)의 방 입구(문과 시작 선 사이)에서 4초 기다려도 싸움이 시작되지 않고 맞지도 않는다
	var room := await _open_mini("canopy_mini_2")
	var boss: EnemyBase = room.get("_boss")
	_player.global_position = Vector2(640, 1232)
	var hits := [0]
	_player.hit_taken.connect(func(_d): hits[0] += 1)
	var closest := INF
	var t := 0.0
	while t < 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		closest = minf(closest, absf(boss.global_position.x - _player.global_position.x))
	var notice0: float = boss.notice_range
	_check(not room.get("_started") and not room.get_node("GateIn").closed and hits[0] == 0 and notice0 == 0.0,
		"canopy_mini_2 입구(x 640)에서 4초: 싸움 시작 %s, 문 닫힘 %s, 피격 %d, 보스 발견 거리 %.0f (잠듦), 보스와 가장 가까웠던 거리 %.0f" % [room.get("_started"), room.get_node("GateIn").closed, hits[0], notice0, closest])
	_player.global_position = Vector2(900, 1232)
	for i in 6:
		await get_tree().physics_frame
	_check(room.get("_started") and room.get_node("GateIn").closed and boss.notice_range > 1000.0, "시작 선을 넘으면 싸움 시작·문 닫힘, 보스가 깨어남 (발견 거리 %.0f)" % boss.notice_range)
	await _close()

	# (나) 쓰러졌다 일어나면: 새 보스가 다시 묶이고(잠든 채), 다시 들어서면 싸움이 시작되고, 이기면 깃발·보상·문 열림
	room = await _open_mini("canopy_mini_1")
	var flag: String = room.defeat_flag
	Progress.flags.erase(flag)
	var hp_before: float = float(Progress.upgrades.get("max_hp", 0.0))
	_player.global_position = Vector2(900, 1232)
	for i in 6:
		await get_tree().physics_frame
	var started0: bool = room.get("_started")
	_player._invuln_timer = 0.0
	_player.take_damage_over_time(99999.0)
	await get_tree().create_timer(3.4).timeout
	var nb: EnemyBase = room.get("_boss")
	var live := is_instance_valid(nb) and not nb.is_queued_for_deletion()
	_check(started0 and live and nb.died.is_connected(room._on_boss_died) and not room.get("_started") and not room.get_node("GateIn").closed and nb.notice_range == 0.0,
		"canopy_mini_1 쓰러진 뒤: 새 보스 %s 가 방에 묶임 %s, 싸움 풀림 %s, 문 열림 %s, 새 보스 잠듦 %s" % [nb.name if live else "-", live and nb.died.is_connected(room._on_boss_died), not room.get("_started"), not room.get_node("GateIn").closed, live and nb.notice_range == 0.0])
	_player._invuln_timer = 9999.0
	_player.global_position = Vector2(900, 1232)
	for i in 6:
		await get_tree().physics_frame
	var restarted: bool = room.get("_started") and room.get_node("GateIn").closed
	if live:
		nb.hp = 1.0
		nb.receive_hit(HitData.make(5.0, 0.0, _player), null)
	await get_tree().create_timer(1.2).timeout
	var got: float = float(Progress.upgrades.get("max_hp", 0.0)) - hp_before
	_check(restarted and Progress.has(flag) and not room.get_node("GateIn").closed and is_equal_approx(got, 10.0),
		"다시 들어서면 싸움 시작 %s, 이기면 깃발 %s, 문 열림 %s, 보상 최대 체력 +%.0f" % [restarted, Progress.has(flag), not room.get_node("GateIn").closed, got])
	Progress.flags.erase(flag)
	Progress.upgrades["max_hp"] = hp_before
	await _close()

	# (다) 포자 어미: 등불이 있어도(심연엔 등불이 있어야 온다) 후려치기·포자 덩이로 소녀를 다치게 한다
	Progress.gain_ability("lantern")
	room = await _open_mini("abyss_mini_1")
	_player._apply_abilities()
	_player._invuln_timer = 0.0
	_player.global_position = Vector2(1300, 1232)
	var hp0: float = _player.hp
	var first := -1.0
	t = 0.0
	while t < 12.0 and _player.state != Player.State.DEAD:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if first < 0.0 and _player.hp < hp0:
			first = t
	_check(_player.hp < hp0, "포자 어미 곁 12초 (등불 있음): 소녀 체력 %.0f → %.0f, 첫 피해 %.1f초" % [hp0, _player.hp, first])
	Progress.abilities.erase("lantern")
	await _close()


## 중간 보스 방을 띄운다 (적을 치우지 않는다).
func _open_mini(room_id: String) -> Node:
	_release_all()
	await _close()
	Progress.next_spawn = ""
	_room_id = room_id
	_room = load("res://scenes/rooms/%s.tscn" % room_id).instantiate()
	add_child(_room)
	for i in 4:
		await get_tree().physics_frame
	_player = get_tree().get_first_node_in_group("player") as Player
	return _room


# ---------- 3) 새 방 사슬 주행 ----------
func _chain() -> void:
	# canopy_04 갈림길: 오른챬 포탈이 이끼 계단으로
	await _open("canopy_04", "FromCanopy03")
	var ok := await _go(1, INF, func(): return _player.global_position.x >= 2960.0, false, 8.0)
	await _use_portal(ok, "canopy_05", "FromCanopy04", "canopy_04 바닥을 달려 오른쪽 포탈(3010) 앞")

	# canopy_05 이끼 계단: 바닥 → 가지 아홉 개 → 꼭대기
	await _open("canopy_05", "FromCanopy04")
	_check(absf(_feet() - 2800.0) < 6.0 and _player.is_on_floor(), "canopy_05 등장 자리(바닥 2800)에 섰다: %s" % _player.global_position)
	await _hop(1, 1560.0, 2560.0, 1700.0, 2000.0, "바닥 → B1")
	await _hop(-1, 1720.0, 2340.0, 1150.0, 1470.0, "B1 → B2")
	await _hop(-1, 1170.0, 2120.0, 650.0, 950.0, "B2 → B3")
	await _jump_up(1900.0, "B3 → B4 (제자리 점프로 one_way 통과)")
	await _hop(-1, 780.0, 1680.0, 0.0, 560.0, "B4 → 옆 가지 L1")
	ok = await _go(-1, INF, func(): return _player.global_position.x <= 240.0, true, 3.0)
	await get_tree().create_timer(0.3).timeout
	var p3: Portal = _room.get_node("Exits/Exit3")
	_check(ok and _player.can_interact and p3.target_scene.ends_with("canopy_mini_1.tscn"), "L1 왼쪽 끝: 늙은 벌목꾼 가지 포탈 앞에서 상호작용 가능 %s (→ %s)" % [_player.can_interact, p3.target_scene.get_file()])
	await _hop(1, 500.0, 1460.0, 800.0, 1120.0, "L1 → B5")
	await _hop(1, 1050.0, 1240.0, 1350.0, 1670.0, "B5 → B6")
	await _hop(1, 1560.0, 1020.0, 1650.0, 1970.0, "B6 → B7")
	await _hop(-1, 1900.0, 795.0, 1450.0, 1750.0, "B7 → B8")
	await _jump_up(570.0, "B8 → B9 (제자리 점프)")
	await _go(-1, INF, func(): return _player.global_position.x <= 1500.0, true, 3.0)
	await _hop(1, 1600.0, 360.0, 1800.0, 2600.0, "B9 → 꼭대기 T1")
	ok = await _go(1, INF, func(): return _player.global_position.x >= 2370.0, false, 5.0)
	_check(_hits == 0, "이끼 계단을 오르는 동안 가시에 닿지 않았다 (피격 %d)" % _hits)
	await _use_portal(ok, "canopy_06", "FromCanopy05", "꼭대기 T1 을 달려 바람의 다리 포탈(2410) 앞")

	# canopy_06 바람의 다리: 두 틈을 달리기 점프로
	await _open("canopy_06", "FromCanopy05")
	_check(absf(_feet() - 780.0) < 6.0, "canopy_06 등장 자리(다리 780)에 섰다: %s" % _player.global_position)
	await _hop(1, 1440.0, 780.0, 1800.0, 3000.0, "다리 첫 틈(1500~1800) 건너 Br2", 6.0)
	await _hop(1, 2940.0, 780.0, 3350.0, 5400.0, "다리 둘째 틈(3000~3350) 건너 Br3", 6.0)
	ok = await _go(1, INF, func(): return _player.global_position.x >= 5170.0, false, 6.0)
	_check(_hits == 0, "다리를 건너는 동안 피격 없음 (%d)" % _hits)
	await _use_portal(ok, "canopy_07", "FromCanopy06", "다리 끝 잿빛 둥지 포탈(5210) 앞")

	# canopy_07 잿빛 둥지: 오른쪽으로 달려 내려서면 D2 → D3 → R1(장로 포탈), 왼쪽으로 달려 내려서면 바닥
	await _open("canopy_07", "FromCanopy06")
	_check(absf(_feet() - 600.0) < 6.0, "canopy_07 등장 자리(둥지 위 600)에 섰다: %s" % _player.global_position)
	var trace: Array[int] = []
	ok = await _go(1, INF, func():
		var fy := int(roundf(_feet()))
		if trace.is_empty() or absi(fy - trace[-1]) > 6:
			trace.append(fy)
		return absf(_feet() - 1300.0) < 6.0 and _player.global_position.x >= 2450.0, false, 8.0)
	print("[probe] 둥지 내려가기(→) 발판 윗면 자취: %s" % [trace])
	_check(ok and trace.has(1060) and trace.has(1280), "둥지 위에서 오른쪽으로 달려 D2(1060)·D3(1280)을 밟고 가지 R1(1300)에 내려섰다")
	ok = await _go(1, INF, func(): return _player.global_position.x >= 3370.0 and absf(_feet() - 1300.0) < 6.0, false, 5.0)
	await get_tree().create_timer(0.3).timeout
	var p_mini: Portal = _room.get_node("Exits/Exit3")
	_check(ok and _player.can_interact and p_mini.target_scene.ends_with("canopy_mini_2.tscn"), "R1 오른쪽 끝: 장로의 온실 포탈 앞에서 상호작용 가능 %s" % _player.can_interact)
	trace.clear()
	ok = await _go(-1, INF, func():
		var fy := int(roundf(_feet()))
		if trace.is_empty() or absi(fy - trace[-1]) > 6:
			trace.append(fy)
		return absf(_feet() - 2200.0) < 6.0, false, 9.0)
	print("[probe] 둥지 내려가기(←) 발판 윗면 자취: %s" % [trace])
	_check(ok and trace.has(1520) and trace.has(1740) and trace.has(1960), "R1 에서 왼쪽으로 달려 D4(1520)·D5(1740)·D6(1960)을 밟고 바닥(2200)에 내려섰다")
	ok = await _go(1, INF, func(): return _player.global_position.x >= 3370.0 and absf(_feet() - 2200.0) < 6.0, false, 9.0)
	_check(_hits == 0, "둥지를 내려오는 동안 피격 없음 (%d)" % _hits)
	await _use_portal(ok, "canopy_boss", "FromCanopy04", "둥지 바닥을 달려 보스 방 포탈(3410) 앞")
	await _close()


## 포탈 앞에서 손길: 장면 전환은 막고 next_spawn 과 target 만 본다.
func _use_portal(arrived: bool, target_room: String, spawn: String, label: String) -> void:
	await get_tree().create_timer(0.4).timeout
	var portal: Portal = null
	for p in get_tree().get_nodes_in_group("portal"):
		if p.global_position.distance_to(_player.global_position) < 200.0:
			portal = p
	var ok := arrived and portal != null and _player.can_interact
	print("[probe] %s: 자리 %s, 포탈 %s, 상호작용 가능 %s" % [label, _player.global_position.round(), portal.name if portal else "-", _player.can_interact])
	if ok:
		Game._busy = true
		Input.action_press("interact")
		await get_tree().physics_frame
		await get_tree().process_frame
		Input.action_release("interact")
		await get_tree().physics_frame
		ok = Progress.next_spawn == spawn and portal.target_scene.ends_with(target_room + ".tscn") and portal._used
		Game._busy = false
		Progress.next_spawn = ""
	_check(ok, "%s → 손길로 %s(%s) 에 들어간다" % [label, target_room, spawn])


# ---------- 방 띄우기 / 조종 (probe_levels.gd 와 같은 방식) ----------
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
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()   # 지형 시험: 적은 치운다
	_hits = 0
	_player.hit_taken.connect(func(_d): _hits += 1)
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
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "interact", "dodge"]:
		if Input.is_action_pressed(a):
			Input.action_release(a)


func _feet() -> float:
	return _player.global_position.y + 67.0


func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while t < limit:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if cond.call():
			return true
	return false


## 방향을 누른 채 가다가 x 가 jump_x 를 지나면 한 번 점프(0.35초 누름). done() 이 참이 되면(바닥에 섰을 때만 검사) 멈춘다.
## jump_x 가 INF 면 점프하지 않는다. walk 가 참이면 걷기 고정(380). 돌아오는 값: done 이 참이 됐는지.
func _go(dir: int, jump_x: float, done: Callable, walk := false, limit := 4.0) -> bool:
	var move := "move_right" if dir > 0 else "move_left"
	_player.walk_locked = walk
	Input.action_press(move)
	var jumped := jump_x == INF
	var jump_t := 0.0
	var t := 0.0
	var ok := false
	while t < limit:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var x := _player.global_position.x
		if not jumped and ((dir > 0 and x >= jump_x) or (dir < 0 and x <= jump_x)):
			jumped = true
			Input.action_press("jump")
		if jumped and jump_x != INF:
			jump_t += dt
			if jump_t > 0.42 and Input.is_action_pressed("jump"):
				Input.action_release("jump")
		if _player.is_on_floor() and done.call():
			ok = true
			break
	_release_all()
	_player.walk_locked = false
	await _until(func(): return _player.is_on_floor() and absf(_player.velocity.x) < 5.0, 1.0)
	return ok


## 한 발판에서 다음 발판으로: dir 로 달리다 jump_x 에서 뛰어 윗면 land_y 의 [x0, x1] 에 내려선다.
func _hop(dir: int, jump_x: float, land_y: float, x0: float, x1: float, label: String, limit := 4.0) -> void:
	var ok := await _go(dir, jump_x, func():
		return absf(_feet() - land_y) < 6.0 and _player.global_position.x >= x0 and _player.global_position.x <= x1, false, limit)
	_check(ok, "%s: 도착 %s (발 y %.0f, 목표 %.0f, x %.0f~%.0f)" % [label, _player.global_position.round(), _feet(), land_y, x0, x1])


## 제자리에서 점프해 바로 위 one_way 가지(윗면 land_y)에 올라선다.
func _jump_up(land_y: float, label: String) -> void:
	Input.action_press("jump")
	var t := 0.0
	var ok := false
	while t < 2.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if t >= 0.42 and Input.is_action_pressed("jump"):
			Input.action_release("jump")
		if t > 0.3 and _player.is_on_floor() and absf(_feet() - land_y) < 6.0:
			ok = true
			break
	_release_all()
	await _until(func(): return _player.is_on_floor() and absf(_player.velocity.x) < 5.0, 1.0)
	_check(ok, "%s: 발 y %.0f (목표 %.0f), 자리 %s" % [label, _feet(), land_y, _player.global_position.round()])

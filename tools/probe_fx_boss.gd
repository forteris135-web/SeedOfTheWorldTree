extends Node
## 보스·적 기술 이펙트 시험 (2026-10-19 이펙트 리뉴얼 F2, 화면 없이 돈다).
## 실행: godot --headless --path . res://tools/probe_fx_boss.tscn      마지막 줄 "[probe] 끝: 실패 N"
## 1) 투사체 그림 묶음(look): 그림이 모두 있고, 판정(반지름·모양)은 look 이 없을 때와 같고, 그림이 판정보다 크고,
##    저스트 가드로 되받으면 금빛 재질로 바뀐다.
## 2) 보스 다섯 마리 모두 기술 이펙트 관찰자가 붙어 있고, 기술을 걸면 그 기술의 이펙트가 뜬다 (가드 불가 예고는 붉은 불티).
## 3) 공격 노드 그림: 뿌리 가시가 솟으며 그림이 드러나고(판정 높이는 그대로 자란다), 뿌리 손은 움켜쥐면 쥔 손 그림,
##    수액 기둥·충격파·검기·포자 구름·잎 더미가 그림을 가진다.
## 4) 몹: 정원사 씨앗·경비병 돌진·기계 드릴·작은 펌프 물줄기·수액 어부 채찍·약초꾼 포자 구름 이펙트가 뜬다.
## 5) 물: 소녀가 수액 웅덩이에 떨어지면 물보라, 걸으면 잔물결.
## 6) 바쁜 보스전에서도 이펙트는 상한(72)을 넘지 않는다.

var _fail := 0


func _ready() -> void:
	print("[probe] 시작")
	Fx.log_spawns = true
	await _test_looks()
	await _test_bosses()
	await _test_nodes()
	await _test_mobs()
	await _test_water()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _spawned(names: Array) -> Dictionary:
	var got := {}
	for n in names:
		got[n] = Fx.spawn_log.has(n)
	return got


func _all(d: Dictionary) -> bool:
	for k in d:
		if not d[k]:
			return false
	return true


# ---------- 1) 그림 묶음 ----------
func _test_looks() -> void:
	var table: Dictionary = load("res://scripts/fx/fx_art.gd").LOOKS
	var missing := []
	for k in table:
		if Fx.texture(String(table[k]["tex"])) == null:
			missing.append(k)
	_check(missing.is_empty(), "그림 묶음 %d개의 그림이 모두 있다 %s" % [table.size(), missing])
	var scene: PackedScene = load("res://scenes/combat/projectile.tscn")
	var bad := []
	for k in table:
		var a: Projectile = scene.instantiate()
		var b: Projectile = scene.instantiate()
		a.size = Vector2(60, 20)
		b.size = Vector2(60, 20)
		b.look = k
		add_child(a)
		add_child(b)
		var ra := _shape_r(a)
		var rb := _shape_r(b)
		var bb := b.body_bounds()
		var big := maxf(bb.size.x, bb.size.y) >= b.hit_radius() * 2.0
		if absf(ra - rb) > 0.01 or not b.has_art() or not big:
			bad.append("%s(판정 %.1f/%.1f, 그림 %s)" % [k, ra, rb, bb.size])
		a.free()
		b.free()
	_check(bad.is_empty(), "그림 묶음마다 판정은 그대로, 그림은 판정보다 크다 %s" % [bad])
	# 되받기: 금빛 재질로
	var f: Projectile = scene.instantiate()
	f.look = "bird_feather"
	f.reflectable = true
	add_child(f)
	var m0 := f.material
	f._reflect(null)
	_check(f.material != m0 and f.material != null, "되받은 깃털은 금빛 재질로 바뀐다")
	f.free()


func _shape_r(p: Projectile) -> float:
	for c in p.get_children():
		if c is CollisionShape2D and c.shape is CircleShape2D:
			return (c.shape as CircleShape2D).radius
	return -1.0


# ---------- 2) 보스 ----------
func _load_room(name: String) -> Dictionary:
	var room: Node = load("res://scenes/rooms/%s.tscn" % name).instantiate()
	add_child(room)
	await _frames(8)
	var player := get_tree().get_first_node_in_group("player") as Player
	var boss := room.get_node("Boss") as Node2D
	player._invuln_timer = 99999.0
	player.input_enabled = false
	var c: Rect2 = boss.arena
	player.global_position = Vector2(c.get_center().x - 400.0, float(boss.ground_y) - 4.0)
	await _frames(3)
	if not room.fight_started:
		room._on_trigger(player)
	await _frames(150)
	return {"room": room, "boss": boss, "player": player}


func _watcher(boss: Node) -> Node:
	for c in boss.get_children():
		var sc: Script = c.get_script()
		if sc and String(sc.resource_path).begins_with("res://scripts/fx/") and String(sc.resource_path).ends_with("_fx.gd"):
			return c
	return null


func _unload(r: Dictionary) -> void:
	r["room"].queue_free()
	await _frames(3)
	Fx.clear()


func _try(r: Dictionary, label: String, start: Callable, frames: int, want: Array) -> void:
	Fx.spawn_log.clear()
	r["player"]._invuln_timer = 99999.0
	r["player"].hp = r["player"].max_hp
	start.call()
	var peak := 0
	for i in frames:
		await get_tree().physics_frame
		r["player"]._invuln_timer = 99999.0
		peak = maxi(peak, Fx.active_count())
	var got := _spawned(want)
	_check(_all(got), "%s: %s (이펙트 최대 %d)" % [label, got, peak])
	_check(peak <= Fx.MAX_ACTIVE, "%s: 이펙트 상한 지킴 (%d ≤ %d)" % [label, peak, Fx.MAX_ACTIVE])


func _test_bosses() -> void:
	# --- 잿빛 잎새의 새 ---
	var r := await _load_room("canopy_boss")
	var b: Node2D = r["boss"]
	_check(_watcher(b) != null, "새: 기술 이펙트 관찰자가 붙어 있다")
	var hover := func() -> void:
		b.phase = 1
		b._set_state(b.State.HOVER)
		b._timer = 99.0
	await _try(r, "새 날갯바람(붉은 예고 → 바람)", func() -> void:
		hover.call()
		b._pattern_index = 2
		b._next_pattern(), 150, ["gust_gather", "danger_ember", "gust_crescent_fly", "gust_streak", "gust_leaf"])
	await _try(r, "새 깃털 화살", func() -> void:
		hover.call()
		b._pattern_index = 1
		b._next_pattern(), 70, ["feather_flash"])
	var feathers := 0
	for p in get_tree().get_nodes_in_group("projectile"):
		if p is Projectile and p.look == "bird_feather":
			feathers += 1
	_check(feathers >= 1, "새 깃털은 금빛 깃털 그림 (%d발)" % feathers)
	await _try(r, "새 2페이즈 잎 회오리", func() -> void:
		hover.call()
		b.phase = 2
		b._pattern_index = 0
		b._next_pattern(), 30, ["leaf_tornado"])
	b.phase = 1
	await _try(r, "새 내려앉기·날개 휘두르기", func() -> void:
		hover.call()
		b._begin_descend(), 200, ["bird_land"])
	await _unload(r)
	# --- 등불 기사 ---
	r = await _load_room("mine_boss")
	b = r["boss"]
	_check(_watcher(b) != null, "기사: 기술 이펙트 관찰자가 붙어 있다")
	var plan := [["THRUST", 60, ["spear_thrust"]], ["SLAM", 90, ["danger_ember", "knight_slam"]], ["COMBO3", 140, ["spear_thrust", "spear_swing", "spear_upper"]],
		["FLAME", 80, ["lantern_arc"]], ["WAVE", 80, ["wave_flash"]], ["CHARGE", 110, ["charge_streak"]]]
	for item in plan:
		var nm: String = item[0]
		b.phase = 1
		b._set_state(b.State.MARCH)
		b._timer = 99.0
		await _try(r, "기사 " + nm, func() -> void: b.force_attack(b.State[nm]), item[1], item[2])
	b.phase = 2
	b._set_state(b.State.MARCH)
	b._timer = 99.0
	await _try(r, "기사 등불 회전 (2페이즈)", func() -> void: b.force_attack(b.State.SPIN), 120, ["fire_ring"])
	b._set_state(b.State.MARCH)
	b._timer = 99.0
	await _try(r, "기사 등불 던지기 → 붉은 고리 → 불기둥", func() -> void: b.force_attack(b.State.THROW), 200, ["danger_ring", "fire_pillar_burst"])
	await _unload(r)
	# --- 뿌리지기 ---
	r = await _load_room("abyss_boss")
	b = r["boss"]
	_check(_watcher(b) != null, "뿌리지기: 기술 이펙트 관찰자가 붙어 있다")
	var plan2 := [["SWEEP", 50, ["staff_arc"]], ["STOMP", 110, ["danger_ember", "root_stomp"]], ["HAND", 90, ["danger_ember", "root_burst_fx"]],
		["SPIKES", 90, ["root_burst_fx"]], ["SEEDS", 200, ["seed_land"]], ["ORBS", 70, ["orb_charge"]], ["RING", 60, ["ring_flash"]]]
	for item in plan2:
		var nm: String = item[0]
		b._set_state(b.State.STANCE)
		b._timer = 99.0
		await _try(r, "뿌리지기 " + nm, func() -> void: b.force_pattern(nm), item[1], item[2])
	await _unload(r)
	# --- 수액의 여왕 --- (박자 시계는 실제 시간을 따른다: 물리 프레임을 넉넉히)
	r = await _load_room("sap_lake_boss")
	b = r["boss"]
	_check(_watcher(b) != null, "여왕: 기술 이펙트 관찰자가 붙어 있다")
	var beat: float = b.BEAT
	await _try(r, "여왕 날개가루", func() -> void:
		b._set_state(b.State.HOVER)
		b._next_at = b._clock + 999.0
		b._begin(b.State.DUST, b._clock, beat * 2.0, beat, beat), 90, ["wing_dust_burst"])
	await _try(r, "여왕 수액 물결", func() -> void:
		b._set_state(b.State.HOVER)
		b._next_at = b._clock + 999.0
		b._begin(b.State.WAVE, b._clock, beat * 2.0, beat, beat * 2.0), 90, ["sap_drip", "sap_splash"])
	await _try(r, "여왕 내려앉기", func() -> void:
		b._set_state(b.State.HOVER)
		b._next_at = b._clock + 999.0
		b._land_stone = b._pick_stone()
		b._diving = false
		b._begin(b.State.LAND, b._clock, beat * 2.0, beat, 0.0), 120, ["queen_land"])
	await _unload(r)
	# --- 무쇠 펌프 ---
	r = await _load_room("flooded_mine_boss")
	b = r["boss"]
	_check(_watcher(b) != null, "펌프: 기술 이펙트 관찰자가 붙어 있다")
	var pb: float = b.BEAT
	await _try(r, "펌프 피스톤 (붉은 김 → 물보라)", func() -> void:
		b._set_state(b.State.IDLE)
		b._red = true
		b._begin(b.State.PISTON, 2.0 * pb, 2.0 * pb), 90, ["danger_vent", "danger_ember", "pump_slam"])
	await _try(r, "펌프 수액 분사", func() -> void:
		b._set_state(b.State.IDLE)
		b._begin(b.State.SPRAY, 2.0 * pb, 1.5 * pb), 110, ["sap_jet"])
	await _try(r, "펌프 빨아들이기 → 물기", func() -> void:
		b._set_state(b.State.IDLE)
		b._begin(b.State.SUCK, 1.5 * pb, 2.0 * pb), 220, ["suck_strip", "pump_bite"])
	await _try(r, "펌프 2페이즈 수액 기둥", func() -> void:
		b.phase = 2
		b._leak()
		b.phase = 1, 60, ["sap_bubble", "sap_splash"])
	await _unload(r)


# ---------- 3) 공격 노드 그림 ----------
func _test_nodes() -> void:
	var holder := Node2D.new()
	add_child(holder)
	# 뿌리 가시: 솟으며 그림이 드러나고 판정 높이도 자란다
	var sp: Node2D = load("res://scenes/combat/root_spike.tscn").instantiate()
	holder.add_child(sp)
	sp.global_position = Vector2(500, 500)
	var art: Sprite2D = sp._art
	var h0 := -1.0
	var h1 := -1.0
	for i in 30:
		await get_tree().physics_frame
		if i == 3:
			h0 = art.region_rect.size.y if art.visible else 0.0
		if i == 20:
			h1 = art.region_rect.size.y
	var rs: RectangleShape2D = sp._shape.shape
	_check(art.texture != null and h1 > h0 and h1 > 200.0 and rs.size.y > 300.0, "뿌리 가시: 그림이 위부터 드러난다 (%.0f → %.0f), 판정 높이 %.0f" % [h0, h1, rs.size.y])
	sp.queue_free()
	# 뿌리 손: 움켜쥐면 쥔 손 그림
	var hand: Node2D = load("res://scenes/bosses/root_hand.tscn").instantiate()
	holder.add_child(hand)
	hand.global_position = Vector2(800, 500)
	var opened: Texture2D = null
	for i in 40:
		await get_tree().physics_frame
		if i == 6:
			opened = hand._art.texture
	_check(opened == Fx.texture("root_hand_open") and hand._art.texture == Fx.texture("root_hand_grip"), "뿌리 손: 벌린 손 → 쥔 손 그림")
	hand.queue_free()
	# 수액 기둥: 예고 뒤 물기둥 그림
	var spurt: Node2D = load("res://scenes/combat/sap_spurt.tscn").instantiate()
	holder.add_child(spurt)
	spurt.global_position = Vector2(1100, 500)
	for i in 45:
		await get_tree().physics_frame
	_check(spurt._art.visible and spurt._art.texture != null, "수액 기둥: 예고 뒤 물기둥 그림이 솟는다")
	spurt.queue_free()
	# 검기·포자 구름·잎 더미·충격파
	var w: Node2D = load("res://scenes/bosses/sword_wave.tscn").instantiate()
	holder.add_child(w)
	var cloud: Node2D = load("res://scenes/combat/spore_cloud.tscn").instantiate()
	holder.add_child(cloud)
	var pile := LeafPile.new()
	holder.add_child(pile)
	var shock: Node2D = load("res://scenes/bosses/root_shockwave.tscn").instantiate()
	holder.add_child(shock)
	shock.global_position = Vector2(300, 800)
	await _frames(12)
	_check(w._art != null and w._art.texture != null, "검기: 불꽃 초승달 그림")
	_check(cloud._puffs.size() == 4, "포자 구름: 포자 안개 그림 4겹")
	_check(pile._leaves.size() == 24, "잎 더미: 낱장 잎 그림 24장")
	_check(shock._art.visible, "뿌리 충격파: 붉은 뿌리 덩어리 그림")
	holder.queue_free()
	await _frames(2)


# ---------- 4) 몹 ----------
func _test_mobs() -> void:
	var room: Node = load("res://scenes/rooms/canopy_01.tscn").instantiate()
	add_child(room)
	await _frames(8)
	var player := get_tree().get_first_node_in_group("player") as Player
	player._invuln_timer = 99999.0
	player.input_enabled = false
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	await _frames(2)
	var plan := [["정원사 씨앗", "res://scenes/enemies/gardener.tscn", "", ["seed_muzzle"]],
		["약초꾼 포자 구름", "res://scenes/enemies/herbalist.tscn", "", ["spore_burst"]],
		["경비병 방패 치기", "res://scenes/enemies/guard.tscn", "bash", ["shield_bash"]],
		["경비병 돌진(가드 불가)", "res://scenes/enemies/guard.tscn", "charge", ["charge_dust"]],
		["기계 들이받기", "res://scenes/enemies/machine.tscn", "ram", ["drill_spark"]],
		["작은 펌프 물줄기", "res://scenes/enemies/small_pump.tscn", "", ["sap_jet"]],
		["수액 어부 채찍", "res://scenes/enemies/sap_fisher.tscn", "", ["whip_splash"]]]
	for item in plan:
		Fx.spawn_log.clear()
		var e: EnemyBase = load(item[1]).instantiate()
		e.position = player.global_position + Vector2(400.0, -2.0)
		room.add_child(e)
		await _frames(3)
		e.facing = -1
		e.player = player
		match String(item[2]):
			"bash":
				e._mode = "bash"
			"charge":
				e._mode = "charge"
			"ram":
				e._ramming = true
		e._strike()
		await _frames(20)
		var got := _spawned(item[3])
		_check(_all(got), "%s: %s" % [item[0], got])
		e.queue_free()
		for p in get_tree().get_nodes_in_group("projectile"):
			p.queue_free()
		await _frames(2)
	room.queue_free()
	await _frames(3)


# ---------- 5) 물 ----------
func _test_water() -> void:
	var room: Node = load("res://scenes/rooms/sap_lake_01.tscn").instantiate()
	add_child(room)
	await _frames(8)
	var player := get_tree().get_first_node_in_group("player") as Player
	player._invuln_timer = 99999.0
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	var pool: SapPool = null
	for n in room.find_children("*", "", true, false):
		if n is SapPool and (pool == null or n.size.x > pool.size.x):
			pool = n
	_check(pool != null, "수액 웅덩이가 있다")
	if pool == null:
		return
	var has_fx := false
	for c in pool.get_children():
		if c.get_script() and String(c.get_script().resource_path).ends_with("water_fx.gd"):
			has_fx = true
	_check(has_fx, "수액 웅덩이에 물 이펙트가 붙어 있다")
	Fx.spawn_log.clear()
	player.input_enabled = false
	player.global_position = Vector2(pool.global_position.x + pool.size.x * 0.5, pool.global_position.y - 260.0)
	player.velocity = Vector2.ZERO
	await _frames(70)
	var entered := Fx.spawn_log.has("water_splash_in")
	player.input_enabled = true
	Input.action_press("move_left")
	await _frames(50)
	Input.action_release("move_left")
	player.input_enabled = false
	_check(entered, "웅덩이에 떨어지면 물보라")
	_check(Fx.spawn_log.has("water_ripple"), "웅덩이에서 걸으면 잔물결")
	room.queue_free()
	await _frames(3)

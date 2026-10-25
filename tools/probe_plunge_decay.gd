extends Node
## 낙하 공격 감쇠(보스·중간 보스 4초 창) + 무쇠 펌프 몸 위 응징 시험 (v1.1.0 최종 검수 — 맞딜 방지, 화면 없이).
## 실행: godot --headless --path . res://tools/probe_plunge_decay.tscn
##  (a) PlungeDecay 계산: 4초 안에 거듭 맞으면 피해 ×0.6^n·흐트러짐 ×0.5^n, 4초 쉬면 처음으로, 낙하가 아니면 그대로,
##      소녀 쪽 공중 연속 감쇠와 곱하지 않고 센 쪽 하나만, 앞에서 곱한 배수(중간 보스 ×1.5)는 남는다.
##  (b) 소녀의 내려꽂기·착지 충격 HitData 에 plunge 표시와 공중 연속 비율이 실린다.
##  (c) 실제 무쇠 펌프: 점프 → 낙하 한 번 → **착지** → 다시 낙하 (4초 안) = 두 번째 피해 ×0.6, 4초 쉬고 나면 다시 온전히.
##  (d) 누가 시계를 가졌나: 다섯 보스·중간 보스(거대화 다섯·잿가지 거인)는 있고 일반 몹은 없다 (일반 몹은 지금 규칙 그대로).
##  (e) 무쇠 펌프 몸 위: 계량기가 몸 위 공중의 소녀도 세고, 김 분출 판정·예고가 발밑 위 760 까지 덮어 몸 위에 떠 있는 소녀를 맞힌다
##      (가드 가능·저스트 가드 불가·예고 2박 그대로).

var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	Settings.data["screen_shake"] = false
	_unit()
	await _player_hitdata_and_pump()
	await _owners()
	await _pump_anti_air()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


static func _near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps


func _plunge_hit(dmg: float, poise: float, chain_d := 1.0, chain_p := 1.0) -> HitData:
	var h := HitData.make(dmg, poise, null)
	h.from_player = true
	h.plunge = true
	h.plunge_chain_damage = chain_d
	h.plunge_chain_poise = chain_p
	return h


# ---------- (a) 계산 ----------
func _unit() -> void:
	var d := PlungeDecay.new()
	var got: Array = []
	for i in 4:
		var h := d.apply(_plunge_hit(26.0, 45.0))
		got.append([snappedf(h.damage, 0.01), snappedf(h.poise, 0.01)])
		d.tick(1.0)   # 1초 간격 (착지와 상관없이 시간으로 센다)
	print("[probe] 1초 간격 낙하 네 번: %s" % [got])
	_check(_near(got[0][0], 26.0) and _near(got[0][1], 45.0), "첫 번째는 온전히 (26 / 45)")
	_check(_near(got[1][0], 15.6) and _near(got[1][1], 22.5), "4초 안 두 번째: 피해 ×0.6 · 흐트러짐 ×0.5 (15.6 / 22.5)")
	_check(_near(got[2][0], 9.36) and _near(got[2][1], 11.25), "세 번째: ×0.36 · ×0.25 (9.36 / 11.25)")
	_check(_near(got[3][0], 5.62) and _near(got[3][1], 5.63, 0.02), "네 번째: ×0.216 · ×0.125")
	d.tick(3.0)   # 마지막 맞은 뒤 1 + 3 = 4초
	var fresh := d.apply(_plunge_hit(26.0, 45.0))
	_check(_near(fresh.damage, 26.0) and _near(fresh.poise, 45.0), "4초 동안 낙하가 안 맞으면 처음으로 (%.1f / %.1f)" % [fresh.damage, fresh.poise])
	# 3.9초 간격이면 이어진다
	d.tick(3.9)
	var cont := d.apply(_plunge_hit(26.0, 45.0))
	_check(_near(cont.damage, 15.6), "3.9초 간격은 같은 창 (%.2f)" % cont.damage)
	# 낙하가 아닌 공격은 그대로 (같은 객체) · 세지도 않는다
	var other := HitData.make(40.0, 60.0, null)
	var before := d.count
	_check(d.apply(other) == other and d.count == before, "낙하가 아닌 공격은 손대지 않고 세지도 않는다")
	# 공유 HitData 를 고치지 않는다
	var shared := _plunge_hit(26.0, 45.0)
	var dd := PlungeDecay.new()
	dd.apply(shared)
	var second := dd.apply(shared)
	_check(_near(shared.damage, 26.0) and second != shared and _near(second.damage, 15.6), "원본 HitData 는 그대로 두고 복사본을 고친다")
	# 소녀 쪽 공중 연속 감쇠와 곱하지 않는다: 센 쪽 하나만
	var e := PlungeDecay.new()
	e.apply(_plunge_hit(26.0, 45.0))                     # n=0
	var c1 := e.apply(_plunge_hit(15.6, 0.0, 0.6, 0.0))    # n=1, 공중 두 번째 (이미 ×0.6, 흐트러짐 0)
	var c2 := e.apply(_plunge_hit(9.36, 0.0, 0.36, 0.0))   # n=2, 공중 세 번째 (이미 ×0.36)
	var c3 := e.apply(_plunge_hit(26.0, 35.0))             # n=3, 착지 충격 (공중 감쇠 없음)
	print("[probe] 공중 연속과 함께: %.2f/%.2f, %.2f/%.2f, 착지 %.2f/%.2f" % [c1.damage, c1.poise, c2.damage, c2.poise, c3.damage, c3.poise])
	_check(_near(c1.damage, 15.6) and _near(c1.poise, 0.0), "공중 두 번째: 0.6 과 0.6 → 곱하지 않고 0.6 하나 (15.6, 흐트러짐 0 그대로)")
	_check(_near(c2.damage, 9.36), "공중 세 번째: 0.36 하나 (9.36 — 0.13 이 아니다)")
	_check(_near(c3.damage, 26.0 * 0.216) and _near(c3.poise, 35.0 * 0.125), "같은 창의 착지 충격도 센다 (×0.216 · ×0.125)")
	var f := PlungeDecay.new()
	f.apply(_plunge_hit(26.0, 45.0))
	f.tick(0.5)
	var c4 := f.apply(_plunge_hit(9.36, 0.0, 0.36, 0.0))   # 다른 적을 밟고 와서 공중 비율이 더 센 경우 (n=1 → 0.6 < 0.36? 아니다)
	_check(_near(c4.damage, 9.36), "공중 비율이 더 세면 그쪽 그대로 (9.36)")
	# 앞에서 곱한 배수는 남는다 (중간 보스 크게 휘청 뒤 ×1.5)
	var g := PlungeDecay.new()
	g.apply(_plunge_hit(39.0, 45.0))
	var ex := g.apply(_plunge_hit(39.0, 45.0))
	_check(_near(ex.damage, 23.4), "앞서 곱한 ×1.5 는 남는다 (39 → 23.4)")
	# 시험 스위치
	PlungeDecay.enabled = false
	var off := PlungeDecay.new()
	off.apply(_plunge_hit(26.0, 45.0))
	var off2 := off.apply(_plunge_hit(26.0, 45.0))
	PlungeDecay.enabled = true
	_check(_near(off2.damage, 26.0), "시험 스위치 enabled=false 면 줄이지 않는다")


# ---------- (b)(c) 소녀의 HitData + 실제 무쇠 펌프 ----------
func _player_hitdata_and_pump() -> void:
	Progress.reset()
	Progress.difficulty = "normal"
	Progress.abilities["double_jump"] = true
	var room: Node = load("res://scenes/rooms/flooded_mine_boss.tscn").instantiate()
	add_child(room)
	await _frames(6)
	var player := get_tree().get_first_node_in_group("player") as Player
	var boss: IronPump = room.get_node("Boss")
	var gy: float = boss.ground_y
	player.global_position = Vector2(boss.arena.get_center().x - 300.0, gy - 80.0)
	await _frames(3)
	if not room.fight_started:
		room._on_trigger(player)
	Music.stop(0.0)
	# 등장이 끝날 때까지
	var n := 0
	while boss.state_name() in ["WAIT", "INTRO"] and n < 400:
		player._invuln_timer = 1.0
		await get_tree().physics_frame
		n += 1
	_check(not boss.state_name() in ["WAIT", "INTRO"], "펌프 싸움이 시작됐다 (%s)" % boss.state_name())
	# (b) 내려꽂기 HitData
	var res := await _dive_on(player, boss, gy)
	var hd: HitData = res["hit"]
	_check(hd != null and hd.plunge and _near(hd.plunge_chain_damage, 1.0) and _near(hd.plunge_chain_poise, 1.0), "내려꽂기 HitData: plunge 표시, 공중 연속 비율 1/1")
	var d1: float = res["dmg"]
	var mult := player.plunge_damage_mult() * player.attack_multiplier
	_check(_near(d1, player.plunge_damage * mult, 0.05), "첫 낙하: 펌프 피해 %.1f (온전히 %.1f)" % [d1, player.plunge_damage * mult])
	# 착지할 때까지 (소녀 쪽 공중 연속 감쇠는 여기서 처음으로 돌아간다)
	n = 0
	while not (player.is_on_floor() and player.state in Player.LOCOMOTION) and n < 240:
		player._invuln_timer = 1.0
		await get_tree().physics_frame
		n += 1
	player._invuln_timer = 1.0
	await _frames(2)   # 바닥에 선 다음 틱에 소녀가 공중 연속 횟수를 지운다
	_check(player._plunge_hits == 0 and player.is_on_floor(), "착지했다 (소녀 쪽 공중 연속 횟수 0)")
	var since: float = boss.plunge_decay.since
	var res2 := await _dive_on(player, boss, gy)
	var d2: float = res2["dmg"]
	print("[probe] 착지 뒤 %.2f초 만에 두 번째 낙하: 피해 %.2f (첫 %.2f, 비율 %.3f)" % [since, d2, d1, d2 / maxf(d1, 0.001)])
	_check(_near(d2, d1 * 0.6, 0.05), "착지했어도 4초 안 두 번째 낙하는 ×0.6 (예전엔 착지하면 온전히 받던 길)")
	# 4초 쉰다 (펌프 공격은 무적으로 흘린다)
	n = 0
	while boss.plunge_decay.since < PlungeDecay.WINDOW + 0.1 and n < 600:
		player._invuln_timer = 1.0
		await get_tree().physics_frame
		n += 1
	while not (player.is_on_floor() and player.state in Player.LOCOMOTION) and n < 900:
		player._invuln_timer = 1.0
		await get_tree().physics_frame
		n += 1
	var res3 := await _dive_on(player, boss, gy)
	var d3: float = res3["dmg"]
	var broken := boss.state_name() == "BROKEN"
	_check(_near(d3, d1 * (boss.broken_damage_multiplier if broken else 1.0), 0.05), "4초 쉰 뒤 낙하는 다시 온전히 (%.1f)" % d3)
	# (b) 착지 충격 HitData
	player.global_position = Vector2(boss.global_position.x - 900.0, gy - 300.0)
	player.velocity = Vector2.ZERO
	await _frames(2)
	await _tap("plunge")
	var land_hit: HitData = null
	n = 0
	while n < 120:
		player._invuln_timer = 1.0
		await get_tree().physics_frame
		n += 1
		if player.state == Player.State.PLUNGE and player.attack_phase == "land":
			land_hit = player.hitbox.hit
			break
	_check(land_hit != null and land_hit.plunge, "착지 충격 HitData 에도 plunge 표시")
	room.queue_free()
	await _frames(3)
	Fx.clear()
	Engine.time_scale = 1.0


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	Input.action_release(action)


## 펌프 바로 위 공중으로 옮겨 낙하 공격을 걸고, 맞은 순간의 피해와 내려꽂기 HitData 를 돌려준다
func _dive_on(player: Player, boss: IronPump, gy: float) -> Dictionary:
	player.global_position = Vector2(boss.global_position.x + 20.0, gy - 640.0)
	player.velocity = Vector2.ZERO
	player._invuln_timer = 1.0
	await get_tree().physics_frame
	var hp0 := boss.hp
	await _tap("plunge")
	var hd: HitData = null
	var n := 0
	while n < 90:
		player._invuln_timer = 1.0
		await get_tree().physics_frame
		n += 1
		if player.state == Player.State.PLUNGE and player.attack_phase == "dive" and hd == null:
			hd = player.hitbox.hit
		if boss.hp < hp0:
			break
	return {"hit": hd, "dmg": hp0 - boss.hp}


# ---------- (d) 누가 시계를 가졌나 ----------
func _owners() -> void:
	var holder := Node2D.new()
	add_child(holder)
	for path in ["res://scenes/bosses/gray_leaf_bird.tscn", "res://scenes/bosses/lantern_knight.tscn", "res://scenes/bosses/root_keeper.tscn",
			"res://scenes/bosses/sap_queen.tscn", "res://scenes/bosses/iron_pump.tscn"]:
		var b: Node = load(path).instantiate()
		_check(b.get("plunge_decay") is PlungeDecay, "보스 %s: 낙하 감쇠 시계가 있다" % path.get_file())
		b.free()
	var elites := ["ash_giant", "elite_woodcutter", "elite_guard", "elite_machine", "elite_gardener", "elite_herbalist"]
	var mobs := ["woodcutter", "guard", "machine", "gardener", "herbalist", "small_pump", "sap_fisher", "woodcutter_savable"]
	for id in elites + mobs:
		var e: Node2D = load("res://scenes/enemies/%s.tscn" % id).instantiate()
		e.position = Vector2(-5000, -5000)
		holder.add_child(e)   # _ready (EliteTraits.apply) 가 돈다
		await get_tree().physics_frame
		var has: bool = e.get("plunge_decay") is PlungeDecay
		if id in elites:
			_check(has, "중간 보스 %s: 낙하 감쇠 시계가 있다" % id)
		else:
			_check(not has, "일반 몹 %s: 시계 없음 (지금 규칙 그대로)" % id)
		e.queue_free()
	await _frames(2)
	holder.queue_free()


# ---------- (e) 무쇠 펌프 몸 위 ----------
func _pump_anti_air() -> void:
	# 계량기 계산: 기본 meter 는 위로 300 까지만, 펌프는 640 까지
	var m := CrowdMeter.new(320.0)
	m.tick(1.0, Vector2.ZERO, Vector2(0, -450), true, -1)
	_check(_near(m.t, 0.0), "기본 계량기는 발밑 위 450 의 소녀를 세지 않는다 (%.2f)" % m.t)
	m.max_up = IronPump.CROWD_MAX_UP
	m.tick(1.0, Vector2.ZERO, Vector2(0, -450), true, -1)
	_check(_near(m.t, 1.0), "위쪽 한도 %.0f 이면 몸 위 공중의 소녀를 센다 (%.2f)" % [IronPump.CROWD_MAX_UP, m.t])
	m.consume()
	m.tick(1.0, Vector2.ZERO, Vector2(0, 280), true, -1)
	_check(_near(m.t, 1.0), "아래쪽 한도(300)는 그대로")

	Progress.reset()
	Progress.difficulty = "normal"
	var room: Node = load("res://scenes/rooms/flooded_mine_boss.tscn").instantiate()
	add_child(room)
	await _frames(6)
	var player := get_tree().get_first_node_in_group("player") as Player
	var boss: IronPump = room.get_node("Boss")
	var gy: float = boss.ground_y
	player.global_position = Vector2(boss.arena.get_center().x - 300.0, gy - 80.0)
	await _frames(3)
	if not room.fight_started:
		room._on_trigger(player)
	Music.stop(0.0)
	var n := 0
	while boss.state_name() in ["WAIT", "INTRO"] and n < 400:
		player._invuln_timer = 1.0
		await get_tree().physics_frame
		n += 1
	_check(boss.crowd.max_up == IronPump.CROWD_MAX_UP, "펌프 계량기 위쪽 한도 %.0f" % boss.crowd.max_up)
	# 몸 위 공중에 붙들어 두면 계량기가 찬다 → 김 분출
	var hover := Vector2(boss.global_position.x + 10.0, gy - 470.0)   # 소녀 가운데 = 발밑 위 470 (발은 약 400)
	var vented := false
	var vent_rect := Rect2()
	var tel_rect := Rect2()
	var startup := 0.0
	var hit_info := {}
	var taken := [0.0]
	var cb := func(d: float) -> void: taken[0] += d
	player.hit_taken.connect(cb)
	boss.crowd.consume()
	n = 0
	var max_t := 0.0
	while n < 60 * 12:
		player.global_position = hover
		player.velocity = Vector2.ZERO
		await get_tree().physics_frame
		n += 1
		max_t = maxf(max_t, boss.crowd.t)
		if boss.state_name() == "VENT":
			if not vented:
				vented = true
				startup = boss.startup_len
				vent_rect = boss.melee_reach()
				var tel: RangeTelegraph = boss.get_node_or_null("RangeTelegraph") as RangeTelegraph
				if tel and tel.is_showing():
					tel_rect = tel.rect
			if boss.hitbox._active and hit_info.is_empty() and boss.hitbox.hit:
				hit_info = {"guardable": boss.hitbox.hit.guardable, "parryable": boss.hitbox.hit.parryable}
		if taken[0] > 0.0:
			break
	player.hit_taken.disconnect(cb)
	print("[probe] 몸 위 공중(발밑 위 %.0f): 계량기 최고 %.2f초, 김 분출 %s, 판정 %s, 예고 %s, 예비 %.3f초, 받은 피해 %.1f" % [gy - hover.y, max_t, vented, vent_rect, tel_rect, startup, taken[0]])
	_check(vented, "몸 위 공중에 떠 있어도 계량기가 차서 김 분출을 고른다")
	_check(vent_rect.position.y <= gy - 755.0 and vent_rect.end.y >= gy - 5.0 and _near(vent_rect.size.x, 660.0, 1.0), "김 분출 판정이 발밑 위 760 까지 (몸 둘레 ±330 — 계량기 범위 320 을 덮는다)")
	_check(tel_rect.size != Vector2.ZERO and tel_rect.position.distance_to(vent_rect.position) < 2.0 and tel_rect.size.distance_to(vent_rect.size) < 2.0, "예고 사각형 = 판정 사각형")
	_check(_near(startup, 2.0 * IronPump.BEAT, 0.02), "예고는 그대로 2박 (%.3f초)" % startup)
	_check(hit_info.get("guardable", false) and not hit_info.get("parryable", true), "김 분출은 가드 가능 · 저스트 가드 불가 그대로")
	_check(taken[0] > 0.0, "몸 위에 떠 있는 소녀를 김 분출이 맞힌다 (피해 %.1f)" % taken[0])
	room.queue_free()
	await _frames(3)
	Fx.clear()
	Engine.time_scale = 1.0

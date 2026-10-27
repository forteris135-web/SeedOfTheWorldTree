extends Node
## v1.1.0 맞딜 마무리 검수: 높은 자리 계량기(PerchMeter)와 그 응징, 새 내려앉기 날개바람, 펌프 장갑. 화면 없이 돈다.
## 실행: godot --headless --path . res://tools/probe_perch.tscn      마지막 줄 "[probe] 끝: 실패 N".
##  (a) PerchMeter: 높은 자리(발밑이 바닥선 위 200 넘게)면 쌓이고, 그보다 낮은 공중이면 그대로, 땅에 서면·보스가 쉬면 절반 빠르기로 식는다
##  (b) 수액의 여왕: 가지(발밑 위 350) 위 소녀 → 계량기가 차면 '가지 나비 떼' — 나비 3+2 마리, 여왕은 소녀 머리 위(소녀 가운데보다 250 넘게 위)에서 풀고,
##      응징 중엔 흐트러짐이 쌓이지 않음(되받은 나비는 그대로), 디딤돌 위 소녀에게는 계량기가 차지 않는다
##  (c) 뿌리지기: 가지(발밑 위 380) 위 소녀 → 계량기가 차면 큰 뿌리 가시 — 공격 범위 예고 = 소녀 발밑 가시 판정 기둥(±2px), 가시 끝이 소녀 발보다 140 넘게 위,
##      가시 판정이 소녀 맞는 영역과 겹친다(가지를 뚫고 닿는다), 2페이즈는 가시 둘, 땅의 소녀에게는 계량기가 차지 않는다, 보통 가시는 그대로 390
##  (c2) 뿌리지기 맞딜 응징 (맞딜 검수 2): 멀리(300) 선 소녀 → 뿌리 창(큰 가시 둘 높이 600, 예비 동안 발밑을 따라감, 0.55초 뒤 하나 더, 주황),
##      가까이(100) 선 소녀 → 두 번 내려찍기(높은 사각형, 붉은 예고)
##  (d) 새: 내려앉는 동안 앉을 자리에 날개바람 예고, 앉는 순간 판정 = 예고 = landing_reach (가드 가능, 피해 16, 몸 높이 180..460 — 땅에 선 소녀는 안 맞음)
##      / 하늘의 새 + 높은 자리 소녀 → 계량기가 차면 깃털 세례 (깃털 3+2 발, 새는 소녀 머리 위에서 쏜다), 땅의 소녀에게는 안 찬다
##  (e) 무쇠 펌프 장갑: 240, 되받은 방울 셋(저스트 가드 45 + 35 씩) = 240 → 깨짐, 둘이면 안 깨짐, 씨앗 베기는 ×0.4, 깨진 시간 10박

var _fail := 0


func _ready() -> void:
	print("[probe] 시작")
	Settings.data["screen_shake"] = false
	_test_meter()
	await _test_queen()
	await _test_root()
	await _test_bird()
	await _test_pump()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _load_room(name: String) -> Dictionary:
	Progress.reset()
	var room: Node = load("res://scenes/rooms/%s.tscn" % name).instantiate()
	add_child(room)
	await _frames(8)
	var player := get_tree().get_first_node_in_group("player") as Player
	var boss := room.get_node("Boss") as Node2D
	player._invuln_timer = 99999.0
	player.input_enabled = false
	var c: Rect2 = boss.arena
	player.global_position = Vector2(c.get_center().x - 400.0, float(boss.ground_y) - 70.0)
	await _frames(3)
	if not room.fight_started:
		room._on_trigger(player)
	Music.stop(0.0)
	return {"room": room, "player": player, "boss": boss}


func _unload(r: Dictionary) -> void:
	r["room"].queue_free()
	await _frames(3)
	Fx.clear()


## 소녀를 발판 윗면(y) x 자리에 세운다
func _stand(p: Player, x: float, top: float) -> void:
	p.global_position = Vector2(x, top - BossRush.FOOT_OFFSET)
	p.velocity = Vector2.ZERO


# ---------- (a) 계량기 ----------
class FakeGirl extends CharacterBody2D:
	pass


func _test_meter() -> void:
	var m := PerchMeter.new(2.0)
	var g := FakeGirl.new()
	add_child(g)
	g.global_position = Vector2(0, 1000.0 - 300.0 - BossRush.FOOT_OFFSET)   # 발밑이 바닥선(1000) 위 300 (공중 — 바닥에 닿지 않음)
	for i in 60:
		m.tick(1.0 / 60.0, 1000.0, g, true)
	var high := m.t
	g.global_position = Vector2(0, 1000.0 - 120.0 - BossRush.FOOT_OFFSET)   # 위 120 공중 (낮은 공중: 그대로)
	for i in 60:
		m.tick(1.0 / 60.0, 1000.0, g, true)
	var low_air := m.t
	for i in 60:
		m.tick(1.0 / 60.0, 1000.0, g, false)   # 보스가 쉬는 중: 식는다
	var resting := m.t
	print("[probe] 계량기: 높은 자리 1초 %.2f → 낮은 공중 1초 %.2f → 보스 쉼 1초 %.2f" % [high, low_air, resting])
	_check(absf(high - 1.0) < 0.02 and absf(low_air - high) < 0.001 and absf(resting - (high - 0.5)) < 0.02,
		"높은 자리면 초당 1 쌓이고, 낮은 공중이면 그대로, 보스가 쉬면 초당 0.5 식는다")
	_check(absf(PerchMeter.height_of(g, 1000.0) - 120.0) < 0.01, "height_of = 바닥선 - 소녀 발밑 (%.1f)" % PerchMeter.height_of(g, 1000.0))
	g.queue_free()


# ---------- (b) 수액의 여왕 ----------
func _test_queen() -> void:
	var r := await _load_room("sap_lake_boss")
	var b: SapQueen = r["boss"]
	var p: Player = r["player"]
	# 디딤돌(바닥선 높이) 위 소녀: 계량기가 차지 않는다
	var island := r["room"].get_node("Terrain/Island") as Node2D
	_stand(p, island.global_position.x + 200.0, island.global_position.y)
	b._set_state(SapQueen.State.HOVER)
	b._next_at = b._clock + 999.0
	b.perch.reset()
	await _frames(150)
	var t_ground := b.perch.t
	# 가지(Branch2, 바닥선 위 350) 위 소녀: 쌓인다
	var br := r["room"].get_node("Terrain/Branch2") as Node2D
	_stand(p, br.global_position.x + 150.0, br.global_position.y)
	await _frames(160)
	var t_branch := b.perch.t
	print("[probe] 여왕 계량기: 섬 위 2.5초 %.2f / 가지 위 2.5초 %.2f (한도 %.1f)" % [t_ground, t_branch, b.perch.trigger])
	_check(t_ground < 0.01 and t_branch >= b.perch.trigger, "디딤돌 위에선 안 차고, 가지 위에선 2.5초 안에 찬다")
	# 다음 패턴 = 가지 나비 떼
	var before: Array = get_tree().get_nodes_in_group("projectile").duplicate()
	b._next_at = b._clock
	var started := false
	var count := 0
	var y_release := INF
	var poise_ok := true
	for i in 240:
		await get_tree().physics_frame
		_stand(p, br.global_position.x + 150.0, br.global_position.y)
		if b.state == SapQueen.State.BUTTERFLIES:
			if not started:
				started = true
				var p0: float = b.poise
				var h := HitData.make(10.0, 60.0, p)
				h.from_player = true
				b.receive_hit(h, null)
				poise_ok = b.punishing and is_equal_approx(b.poise, p0)
			if b.attack_phase == "active" and y_release == INF:
				y_release = b.global_position.y
	for n in get_tree().get_nodes_in_group("projectile"):
		if not (n in before) and n is SapProjectile and (n as SapProjectile).sap_kind == "butterfly":
			count += 1
	var above := p.global_position.y - y_release
	print("[probe] 여왕 가지 나비 떼: 시작 %s, 나비 %d 마리, 풀 때 여왕이 소녀 가운데보다 %.0f 위, 응징 중 흐트러짐 안 쌓임 %s" % [started, count, above, poise_ok])
	_check(started and count == b.butterfly_count + SapQueen.PERCH_EXTRA, "계량기가 차면 다음 패턴은 가지 나비 떼 (나비 %d 마리 = 3 + %d)" % [count, SapQueen.PERCH_EXTRA])
	_check(above > 250.0, "가지 나비 떼는 소녀 머리 위에서 푼다 (소녀의 수평 원거리 줄 밖 — %.0f px 위)" % above)
	_check(poise_ok, "가지 나비 떼 동안은 흐트러짐이 쌓이지 않는다 (응징)")
	await _unload(r)


# ---------- (c) 뿌리지기 ----------
func _test_root() -> void:
	var r := await _load_room("abyss_boss")
	var b: RootKeeper = r["boss"]
	var p: Player = r["player"]
	var gy: float = b.ground_y
	b.global_position = Vector2(b.arena.get_center().x - 200.0, gy)
	b._set_state(RootKeeper.State.STANCE)
	b._timer = 999.0
	_stand(p, b.global_position.x + 500.0, gy)
	b.perch.reset()
	await _frames(150)
	var t_ground := b.perch.t
	var br := r["room"].get_node("Terrain/Branch3") as Platform
	var bx := br.global_position.x + br.size.x * 0.5
	for i in 160:
		_stand(p, bx, br.global_position.y)
		await get_tree().physics_frame
	var t_branch := b.perch.t
	print("[probe] 뿌리지기 계량기: 땅 2.5초 %.2f / 가지(위 %.0f) 2.5초 %.2f" % [t_ground, gy - br.global_position.y, t_branch])
	_check(t_ground < 0.01 and t_branch >= b.perch.trigger, "땅에선 안 차고, 가지 위에선 2.5초 안에 찬다")
	# 공격을 고르게 한다 → 큰 가시 (맞딜 계량기는 비운다 — 가지 위 소녀도 뿌리지기 400 안이면 붙어 있는 것으로 세어 뿌리 창이 먼저 나간다)
	b.crowd.reset()
	b._timer = 0.0
	var tel_last := Rect2()
	var spike: RootSpike = null
	var spike_rect := Rect2()
	var overlap := false
	for i in 200:
		_stand(p, bx, br.global_position.y)
		b.crowd.reset()   # 이 시험은 높은 자리 응징만 본다 (가지 위 소녀도 400 안이면 맞딜 계량기가 차 뿌리 창이 끼어든다 — (c2) 에서 따로)
		var tel: RangeTelegraph = b.get_node_or_null("RangeTelegraph")
		if tel and tel.is_showing():
			tel_last = tel.rect
		await get_tree().physics_frame
		if spike == null:
			for n in get_tree().get_nodes_in_group("root_effect"):
				if n is RootSpike:
					spike = n
					break
		if spike and is_instance_valid(spike) and spike._t > spike.delay + RootSpike.RISE + 0.02 and spike_rect.size == Vector2.ZERO:
			var cs: CollisionShape2D = spike._shape
			var sz: Vector2 = (cs.shape as RectangleShape2D).size
			spike_rect = Rect2(cs.global_position - sz * 0.5, sz)
			var hb := p.get_node("Hurtbox") as Area2D
			for c in hb.get_children():
				if c is CollisionShape2D and c.shape is RectangleShape2D:
					var hs: Vector2 = (c.shape as RectangleShape2D).size
					overlap = overlap or Rect2(c.global_position - hs * 0.5, hs).intersects(spike_rect)
				elif c is CollisionShape2D and c.shape is CapsuleShape2D:
					var cap := c.shape as CapsuleShape2D
					overlap = overlap or Rect2(c.global_position - Vector2(cap.radius, cap.height * 0.5), Vector2(cap.radius * 2.0, cap.height)).intersects(spike_rect)
	var feet := br.global_position.y
	print("[probe] 큰 가시: 예고 %s / 판정 %s, 가시 끝이 소녀 발보다 %.0f 위, 소녀와 겹침 %s" % [tel_last, spike_rect, feet - spike_rect.position.y, overlap])
	var close := absf(tel_last.position.x - spike_rect.position.x) <= 2.0 and absf(tel_last.end.x - spike_rect.end.x) <= 2.0 \
		and absf(tel_last.position.y - spike_rect.position.y) <= 6.0 and absf(tel_last.end.y - spike_rect.end.y) <= 2.0
	_check(spike_rect.size != Vector2.ZERO and close, "큰 가시: 공격 범위 예고 = 소녀 발밑 가시 판정 기둥 (가로 ±2, 세로 ±6 — 서 있는 동안 4px 떨림)")
	_check(feet - spike_rect.position.y > 140.0 and overlap, "큰 가시가 가지를 뚫고 소녀에게 닿는다")
	_check(not b._tel.unguardable, "큰 가시 예고는 주황 (가드 가능)")
	await _frames(90)
	# 2페이즈: 가시 둘
	b.phase = 2
	b._perch_spikes = true
	b._chain = -1
	b._start_attack(RootKeeper.State.SPIKES)
	var n2 := b.spike_marks.size()
	var hs2: Array = b.spike_heights.duplicate()
	_check(n2 == 2 and hs2.size() == 2 and float(hs2[0]) > RootSpike.HEIGHT, "2페이즈 큰 가시는 둘 (%d, 높이 %s)" % [n2, hs2])
	await _frames(120)
	# 보통 가시는 그대로 390
	b.phase = 1
	b._set_state(RootKeeper.State.STANCE)
	b._timer = 999.0
	b.force_pattern("SPIKES")
	_check(b.spike_heights.is_empty(), "보통 가시는 높이 기록 없음 (390 그대로)")
	await _frames(120)
	# (c2) 맞딜 검수 2: 계량기(400 안)가 찼을 때 — 땅에 선 소녀가 몸 가까이(175 안)면 두 번 내려찍기(높은 사각형), 멀거나 떠 있으면 뿌리 창
	b._set_state(RootKeeper.State.STANCE)
	b._timer = 999.0
	b.perch.reset()
	_stand(p, b.global_position.x - 300.0, gy)
	await _frames(6)
	b.crowd.t = b.crowd.trigger
	b._choose(300.0)
	var lance_ok: bool = b.state == RootKeeper.State.SPIKES and b._lance and b.punishing and b.spike_marks.size() == 2 \
		and is_equal_approx(float(b.spike_heights[0]), RootKeeper.LANCE_HEIGHT)
	_check(lance_ok, "멀리(300) 선 소녀: 뿌리 창 — 큰 가시 둘(높이 %.0f), 응징 (%s, 표시 %s, 높이 %s)" % [RootKeeper.LANCE_HEIGHT, b.state_name(), b.spike_marks, b.spike_heights])
	_check(not b._tel.unguardable and b._tel.is_showing(), "뿌리 창 예고는 주황 기둥 (가드 가능)")
	# 예비 60% 까지 소녀 발밑을 따라간다
	_stand(p, b.global_position.x - 420.0, gy)
	await _frames(12)
	var follow := absf(float(b.spike_marks[0]) - p.global_position.x)
	var spikes_before: Array = []
	for n in get_tree().get_nodes_in_group("root_effect"):
		if n is RootSpike:
			spikes_before.append(n)
	var waited := 0
	while b.attack_phase == "startup" and waited < 120:
		await get_tree().physics_frame
		waited += 1
	await _frames(2)
	var new_spikes: Array = []
	for n in get_tree().get_nodes_in_group("root_effect"):
		if n is RootSpike and not (n in spikes_before):
			new_spikes.append(n)
	var delays: Array = []
	var has_follow := false
	for sp in new_spikes:
		delays.append(snappedf(sp.delay, 0.01))
		has_follow = has_follow or absf(sp.delay - RootKeeper.LANCE_FOLLOW) < 0.005
	print("[probe] 뿌리 창: 따라감 오차 %.0f px, 새로 생긴 가시 %d, 기다림 %s" % [follow, new_spikes.size(), delays])
	_check(follow < 30.0, "뿌리 창은 예비 동안 소녀 발밑을 따라간다 (오차 %.0f)" % follow)
	_check(new_spikes.size() == 3 and has_follow, "뿌리 창: 큰 가시 둘 + %.2f초 뒤 소녀 자리에 하나 더 (스스로 기둥 예고)" % RootKeeper.LANCE_FOLLOW)
	await _frames(150)
	b._set_state(RootKeeper.State.STANCE)
	b._timer = 999.0
	_stand(p, b.global_position.x - 100.0, gy)
	await _frames(6)
	b.crowd.t = b.crowd.trigger
	b._choose(100.0)
	var stomp_rect: Rect2 = b.melee_reach()
	_check(b.state == RootKeeper.State.STOMP and b.punishing and b._stomps_left == 1 and stomp_rect.size.y > 400.0 and b._tel.unguardable,
		"가까이(100) 선 소녀: 두 번 내려찍기 — 응징, 둘째 하나 남음, 판정·예고 높이 %.0f (땅에서 위로 400 + 발밑 아래 20), 붉은 예고" % stomp_rect.size.y)
	await _frames(200)
	await _unload(r)


# ---------- (d) 새 ----------
func _test_bird() -> void:
	var r := await _load_room("canopy_boss")
	var b: GrayLeafBird = r["boss"]
	var p: Player = r["player"]
	b.global_position = Vector2(b.arena.get_center().x, b.ground_y - 420.0)
	b.velocity = Vector2.ZERO
	b._set_state(GrayLeafBird.State.HOVER)
	b._timer = 99.0
	_stand(p, b.arena.get_center().x - 900.0, b.ground_y)
	await _frames(4)
	b._begin_descend()
	var tel_last := Rect2()
	var hb_rect := Rect2()
	var dmg := 0.0
	var guardable := false
	var tel_seen := false
	for i in 200:
		var tel: RangeTelegraph = b.get_node_or_null("RangeTelegraph")
		if tel and tel.is_showing():
			tel_last = tel.rect
			tel_seen = true
		await get_tree().physics_frame
		if b.hitbox._active and hb_rect.size == Vector2.ZERO:
			var cs: CollisionShape2D = b.hitbox._shape
			var sz: Vector2 = (cs.shape as RectangleShape2D).size
			hb_rect = Rect2(cs.global_position - sz * 0.5, sz)
			var hd: HitData = b.hitbox.hit
			if hd:
				dmg = hd.damage
				guardable = hd.guardable
	print("[probe] 새 날개바람: 예고 %s / 판정 %s (피해 %.0f, 가드 %s)" % [tel_last, hb_rect, dmg, guardable])
	var close := absf(tel_last.position.x - hb_rect.position.x) <= 2.0 and absf(tel_last.end.x - hb_rect.end.x) <= 2.0 \
		and absf(tel_last.position.y - hb_rect.position.y) <= 2.0 and absf(tel_last.end.y - hb_rect.end.y) <= 2.0
	_check(tel_seen and hb_rect.size != Vector2.ZERO and close, "새가 내려앉는 순간의 날개바람: 공격 범위 예고 = 판정 (±2px)")
	# v1.1.1: 새 추가 공격 배율(Balance.BOSS_EXTRA bird atk 1.05)을 한 번 받은 값
	_check(is_equal_approx(dmg, GrayLeafBird.LANDING_DAMAGE * Balance.boss_extra("bird", "atk")) and guardable, "날개바람 피해 %.1f·가드 가능" % dmg)
	var st_top := b.ground_y - 134.0   # 땅에 선 소녀 맞는 영역 윗끝
	_check(hb_rect.end.y < st_top - 30.0 and b.ground_y - hb_rect.position.y >= 450.0, "날개바람은 몸 높이(바닥 위 %.0f..%.0f) — 땅에 선 소녀는 안 맞고 떠 있는 소녀만" % [b.ground_y - hb_rect.end.y, b.ground_y - hb_rect.position.y])
	# 깃털 세례: 하늘의 새, 땅의 소녀 → 안 참 / 가지(Branch4) 위 소녀 → 참 → 다음 패턴 깃털 +2
	for i in 240:
		await get_tree().physics_frame
		if b.state == GrayLeafBird.State.GROUND_IDLE or b.state == GrayLeafBird.State.WALK_TO_PILE:
			break
	b.global_position = Vector2(b.arena.get_center().x, b.ground_y - 420.0)
	b.set_collision_mask_value(1, false)
	b._set_state(GrayLeafBird.State.HOVER)
	b._timer = 99.0
	b._air_timer = 0.0
	b._fatigue = 0
	b.perch.reset()
	_stand(p, b.arena.get_center().x - 600.0, b.ground_y)
	await _frames(150)
	var t_ground := b.perch.t
	var br := r["room"].get_node("Terrain/Branch4") as Platform
	var bx := br.global_position.x + br.size.x * 0.5
	for i in 160:
		_stand(p, bx, br.global_position.y)
		b._timer = 99.0
		await get_tree().physics_frame
	var t_branch := b.perch.t
	_check(t_ground < 0.01 and t_branch >= b.perch.trigger, "새 계량기: 땅의 소녀 %.2f / 가지 위 소녀 %.2f (한도 %.1f)" % [t_ground, t_branch, b.perch.trigger])
	var before: Array = get_tree().get_nodes_in_group("projectile").duplicate()
	b._timer = 0.0
	var started := false
	var y_shot := INF
	var seen := {}
	for i in 120:
		_stand(p, bx, br.global_position.y)
		await get_tree().physics_frame
		if b.state == GrayLeafBird.State.FEATHERS:
			started = started or b._perch_volley
			if b.muzzle_flash > 0.9:
				y_shot = minf(y_shot, b.body_center().y)
		for n in get_tree().get_nodes_in_group("projectile"):
			if not (n in before) and n is Projectile and (n as Projectile).look == "bird_feather":
				seen[n.get_instance_id()] = true
	var feathers := seen.size()
	print("[probe] 새 깃털 세례: 시작 %s, 깃털 %d 발, 쏠 때 새 몸 가운데가 소녀 가운데보다 %.0f 위" % [started, feathers, p.global_position.y - y_shot])
	_check(started and feathers == b.feather_count + GrayLeafBird.PERCH_EXTRA, "계량기가 차면 다음 하늘 패턴은 깃털 세례 (깃털 %d 발 = 3 + %d)" % [feathers, GrayLeafBird.PERCH_EXTRA])
	_check(p.global_position.y - y_shot > 140.0, "깃털 세례는 소녀보다 높은 자리에서 쏜다 (몸 가운데 140 넘게 위)")
	await _unload(r)


# ---------- (e) 무쇠 펌프 장갑 ----------
func _test_pump() -> void:
	var r := await _load_room("flooded_mine_boss")
	var b: IronPump = r["boss"]
	var p: Player = r["player"]
	for i in 200:
		await get_tree().physics_frame
		if b.state == IronPump.State.IDLE:
			break
	b.set_physics_process(false)
	b._set_state(IronPump.State.IDLE)
	_check(is_equal_approx(b.max_poise, 240.0) and is_equal_approx(b.reflect_poise, 35.0), "펌프 장갑 240, 되받은 방울 +35")
	_check(absf(b.broken_time - 10.0 * IronPump.BEAT) < 0.001, "장갑이 깨진 시간 10박 (%.3f초)" % b.broken_time)
	# 되받은 방울 둘 = 160 → 안 깨짐, 셋 = 240 → 깨짐
	b.poise = 0.0
	for k in 3:
		b.on_just_guarded(p, p.just_guard_poise)
		var refl := HitData.make(14.0 * 1.6, 28.0, b)
		refl.from_player = true
		b.receive_hit(refl, null)
		if k == 1:
			_check(b.state != IronPump.State.BROKEN and is_equal_approx(b.poise, 160.0), "되받은 방울 둘: 장갑 %.0f, 안 깨짐" % b.poise)
	_check(b.state == IronPump.State.BROKEN, "되받은 방울 셋: 장갑 가득 → 깨짐 (%s)" % b.state_name())
	# 씨앗 베기는 ×0.4 (쉬는 중), 공격 도중엔 그 절반
	b._set_state(IronPump.State.IDLE)
	b.poise = 0.0
	b._poise_immune = 0.0
	b.receive_hit(HitData.make(40.0, 60.0, p), null)
	var idle_gain := b.poise
	b.poise = 0.0
	b._set_state(IronPump.State.PISTON)
	b.attack_phase = "startup"
	b.receive_hit(HitData.make(40.0, 60.0, p), null)
	var atk_gain := b.poise
	print("[probe] 펌프 장갑: 씨앗 베기(흐트러짐 60) 쉬는 중 +%.1f / 공격 도중 +%.1f" % [idle_gain, atk_gain])
	_check(is_equal_approx(idle_gain, 60.0 * b.hit_poise_ratio) and is_equal_approx(atk_gain, 60.0 * b.hit_poise_ratio * b.attack_poise_multiplier),
		"씨앗 베기는 장갑을 ×%.1f (공격 도중엔 ×%.2f) 만 채운다" % [b.hit_poise_ratio, b.hit_poise_ratio * b.attack_poise_multiplier])
	b.set_physics_process(true)
	await _unload(r)

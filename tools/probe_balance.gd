extends Node
## Claude Code용 시험: v1.1.0 적·보스 능력치와 난이도 (기획자 요청 8·9, 명세 3.1·3.2).
## v1.1.1: v1.1.0 Hard = 새 Normal (모든 적 체력·공격 ×1.15 한 번), 보스별 추가 배율(Balance.BOSS_EXTRA), 영혼 기술의 보스 배율.
## 실행: godot --headless --path . res://tools/probe_balance.tscn
##  (a) 배율표: 지역 6곳 × 난이도 4개의 체력·공격 배율 (Balance.hp_mult / atk_mult)
##  (b) 몹·거대화·보스의 최대 체력 (Normal, 지역마다 — Balance.region_override 로 지역을 정하고 씬을 실제로 만든다)
##  (c) 소녀가 받는 피해 예시 (Normal): 보스 공격·몹 공격이 Player.receive_hit 에서 배율을 받는다 (HitData 원본은 그대로)
##  (d) 몸통 부딪힘 8 은 모든 지역·난이도에서 8, 환경 피해(가시 take_hazard·수액 웅덩이 take_damage_over_time)는 배율 없음
##  (e) 포자 구름: 0.5초마다 dps×0.5×공격 배율
##  (f) 난이도 4개: 같은 공격·같은 체력이 0.7 / 1.0 / 1.15 / 1.3 배
##  (g) v1.1.1 보스별 추가 공격: 새·펌프·여왕의 공격 값이 한 번만 커지고(다시 만들어도 겹치지 않음) 기사는 그대로
##  (h) v1.1.1 영혼 기술 → 보스: 바람·빛 ×0.8, 씨앗 베기 ×1.1 (복사본; 원본·중간 보스·영혼이 아닌 공격은 그대로), Hurtbox 를 거쳐서도

var _fail := 0
var _player: Player


func _ready() -> void:
	print("[probe] 능력치·난이도 시험 시작")
	_make_floor()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.global_position = Vector2(0, -68)
	await _frames(3)
	_probe_table()
	await _probe_hp()
	_probe_damage()
	_probe_unscaled()
	await _probe_spore()
	_probe_difficulty()
	await _probe_boss_atk()
	await _probe_soul_vs_boss()
	Balance.region_override = ""
	Progress.difficulty = "normal"
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _near(a: float, b: float, eps := 0.06) -> bool:
	return absf(a - b) <= eps


func _make_floor() -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(8000, 200)
	cs.shape = r
	cs.position = Vector2(0, 100)
	body.add_child(cs)
	add_child(body)


# ---------- (a) 배율표 ----------
func _probe_table() -> void:
	var tiers := {"canopy": 0, "village": 1, "mine": 2, "flooded_mine": 2, "sap_lake": 3, "abyss": 4}
	for reg in tiers:
		_check(Balance.tier_of(reg) == tiers[reg], "던전 단계 %s = %d" % [reg, Balance.tier_of(reg)])
	var diffs := {"easy": 0.7, "normal": 1.0, "hard": 1.15, "nightmare": 1.3}
	for d in diffs:
		Progress.difficulty = d
		for reg in tiers:
			var hp_want: float = 1.15 * pow(1.1, tiers[reg]) * diffs[d]
			var atk_want: float = 1.45 * 1.15 * pow(1.1, tiers[reg]) * diffs[d]
			if not (_near(Balance.hp_mult(reg), hp_want, 0.0005) and _near(Balance.atk_mult(reg), atk_want, 0.0005)):
				_check(false, "배율 %s/%s: 체력 %.4f (기대 %.4f), 공격 %.4f (기대 %.4f)" % [d, reg, Balance.hp_mult(reg), hp_want, Balance.atk_mult(reg), atk_want])
	_check(true, "배율표 6지역 × 4난이도 = 체력 1.15 × 1.1^단계 × 난이도, 공격 1.45 × 1.15 × 1.1^단계 × 난이도 (v1.1.1 새 Normal)")
	# 새 Normal = 옛 v1.1.0 Hard (같은 지역·같은 공격): 난이도 배율이 겹쳐 곱해지지 않는다
	Progress.difficulty = "normal"
	var new_normal := Balance.hp_mult("mine")
	Progress.difficulty = "hard"
	var new_hard := Balance.hp_mult("mine")
	Progress.difficulty = "normal"
	_check(_near(new_normal, 1.15 * 1.21, 0.0005) and _near(new_hard, 1.15 * 1.15 * 1.21, 0.0005),
		"새 Normal 체력 배율(채굴장) %.4f = 옛 Hard 1.15 × 1.21, 새 Hard %.4f = 그 1.15배" % [new_normal, new_hard])
	Progress.difficulty = "bogus"
	_check(Balance.difficulty() == "normal" and _near(Balance.diff_mult(), 1.0), "모르는 난이도 이름은 Normal 로 (%s)" % Balance.difficulty())
	Progress.difficulty = "normal"


# ---------- (b) 최대 체력 ----------
func _spawn_hp(path: String, region: String) -> float:
	Balance.region_override = region
	var n: Node2D = (load(path) as PackedScene).instantiate()
	n.position = Vector2(-3000, -100)
	add_child(n)
	await _frames(1)
	var v: float = float(n.get("max_hp"))
	var hp_now: float = float(n.get("hp"))
	n.queue_free()
	await _frames(1)
	Balance.region_override = ""
	if not _near(v, hp_now, 0.01):
		_check(false, "%s: 체력이 최대 체력으로 시작하지 않는다 (%.1f / %.1f)" % [path.get_file(), hp_now, v])
	return v


func _probe_hp() -> void:
	Progress.difficulty = "normal"
	# 세 번째 값 = v1.1.0 Normal 체력, 네 번째 = v1.1.1 보스별 추가 체력 (새 1.10 · 펌프 1.15 · 기사 1 · 여왕 1.15 · 뿌리지기 1.75).
	# 기대값 = v1.1.0 Normal × 1.15(새 Normal) × 보스 추가 — 한 번씩만.
	var cases := [
		["res://scenes/bosses/gray_leaf_bird.tscn", "canopy", 1800.0, 1.10],
		["res://scenes/bosses/iron_pump.tscn", "flooded_mine", 1936.0, 1.15],
		["res://scenes/bosses/lantern_knight.tscn", "mine", 1996.5, 1.0],
		["res://scenes/bosses/sap_queen.tscn", "sap_lake", 1730.3, 1.15],
		["res://scenes/bosses/root_keeper.tscn", "abyss", 3074.61, 1.75],
		["res://scenes/enemies/woodcutter.tscn", "canopy", 95.0, 1.0],
		["res://scenes/enemies/gardener.tscn", "canopy", 70.0, 1.0],
		["res://scenes/enemies/guard.tscn", "village", 110.0, 1.0],
		["res://scenes/enemies/machine.tscn", "mine", 205.7, 1.0],
		["res://scenes/enemies/machine.tscn", "abyss", 248.9, 1.0],
		["res://scenes/enemies/gardener.tscn", "mine", 84.7, 1.0],
		["res://scenes/enemies/small_pump.tscn", "flooded_mine", 108.9, 1.0],
		["res://scenes/enemies/sap_fisher.tscn", "sap_lake", 113.1, 1.0],
		["res://scenes/enemies/herbalist.tscn", "abyss", 102.5, 1.0],
		["res://scenes/enemies/elite_woodcutter.tscn", "canopy", 380.0, 1.0],
		["res://scenes/enemies/elite_gardener.tscn", "canopy", 280.0, 1.0],
		["res://scenes/enemies/ash_giant.tscn", "canopy", 360.0, 1.0],
		["res://scenes/enemies/elite_guard.tscn", "village", 440.0, 1.0],
	]
	for c in cases:
		var got := await _spawn_hp(c[0], c[1])
		var want: float = float(c[2]) * 1.15 * float(c[3])
		_check(_near(got, want, 0.2), "체력 %s (%s, Normal) = %.1f (기대 %.1f = v1.1.0 %.1f × 1.15 × %.2f)" % [String(c[0]).get_file().get_basename(), c[1], got, want, c[2], c[3]])
	# 같은 씬을 두 번 만들어도 겹쳐 곱해지지 않는다 (다시 나타나는 몹)
	var a := await _spawn_hp("res://scenes/enemies/guard.tscn", "village")
	var b := await _spawn_hp("res://scenes/enemies/guard.tscn", "village")
	_check(_near(a, b, 0.001) and _near(a, 126.5, 0.01), "다시 만든 경비병도 126.5 (겹쳐 곱해지지 않음: %.1f, %.1f)" % [a, b])
	# 보스도 다시 만들어도(재도전·보스 러시) 겹치지 않는다
	var q1 := await _spawn_hp("res://scenes/bosses/sap_queen.tscn", "sap_lake")
	var q2 := await _spawn_hp("res://scenes/bosses/sap_queen.tscn", "sap_lake")
	_check(_near(q1, q2, 0.001) and _near(q1, 1730.3 * 1.15 * 1.15, 0.2), "다시 만든 여왕도 %.1f (겹쳐 곱해지지 않음: %.1f)" % [q1, q2])


# ---------- (c) 받는 피해 ----------
func _incoming(base: float, region: String) -> float:
	Balance.region_override = region
	var h := HitData.make(base, 0.0, null)
	var v := Balance.incoming_damage(h, _player)
	Balance.region_override = ""
	return v


func _probe_damage() -> void:
	Progress.difficulty = "normal"
	# 네 번째 값 = v1.1.0 Normal 에서 받던 피해. v1.1.1 새 Normal 은 그 1.15배 (보스별 추가 공격은 보스 쪽 값에 — (g))
	var cases := [
		["새 날개 휘두르기", 20.0, "canopy", 29.0], ["새 깃털", 14.0, "canopy", 20.3],
		["기사 내려찍기", 30.0, "mine", 52.6], ["기사 3연격 1", 16.0, "mine", 28.1], ["기사 3연격 2", 18.0, "mine", 31.6], ["기사 3연격 3", 24.0, "mine", 42.1],
		["뿌리지기 뿌리 벽", 32.0, "abyss", 67.9], ["뿌리지기 휘두르기", 24.0, "abyss", 50.9],
		["여왕 물결", 18.0, "sap_lake", 34.7], ["펌프 피스톤", 28.0, "flooded_mine", 49.1],
		["나무꾼", 18.0, "canopy", 26.1], ["경비병 방패 치기", 12.0, "village", 19.1], ["기계(채굴장)", 20.0, "mine", 35.1],
	]
	for c in cases:
		var got := _incoming(c[1], c[2])
		var want: float = float(c[3]) * 1.15
		_check(_near(got, want, 0.08), "받는 피해 %s %.0f → %.1f (기대 %.1f = v1.1.0 %.1f × 1.15, %s)" % [c[0], c[1], got, want, c[3], c[2]])
	# 실제 receive_hit 로: 체력이 배율만큼 줄고 HitData 원본은 그대로
	Balance.region_override = "abyss"
	_player.hp = _player.max_hp
	_player._invuln_timer = 0.0
	_player.state = Player.State.IDLE
	var h := HitData.make(10.0, 0.0, null)
	var hp0 := _player.hp
	_player.receive_hit(h, null)
	var lost := hp0 - _player.hp
	Balance.region_override = ""
	_check(_near(lost, 10.0 * 1.45 * 1.15 * pow(1.1, 4), 0.02) and _near(h.damage, 10.0, 0.0001), "receive_hit: 심연 10 → %.2f 깎임 (HitData 원본 %.1f 그대로)" % [lost, h.damage])
	_player.hp = _player.max_hp
	_player._invuln_timer = 0.0
	_player.state = Player.State.IDLE


# ---------- (d) 배율 없는 피해 ----------
func _probe_unscaled() -> void:
	for d in ["easy", "normal", "hard", "nightmare"]:
		Progress.difficulty = d
		for reg in ["canopy", "abyss"]:
			Balance.region_override = reg
			var h := HitData.make(8.0, 0.0, null)
			h.scaled = Balance.SCALE_CONTACT
			var v := Balance.incoming_damage(h, _player)
			if not _near(v, 8.0, 0.0001):
				_check(false, "몸통 부딪힘 %s/%s = %.2f (기대 8)" % [d, reg, v])
	Balance.region_override = ""
	Progress.difficulty = "normal"
	_check(true, "몸통 부딪힘 8 은 4난이도 × 수관·심연 모두 8 (scaled = false)")
	# 몹의 실제 몸통 부딪힘 HitData 도 scaled = false 인가 (enemy_base 의 _tick_contact) — 코드 계약 확인
	var src := FileAccess.get_file_as_string("res://scripts/enemies/enemy_base.gd")
	_check(src.contains("hit.scaled = Balance.SCALE_CONTACT"), "EnemyBase 몸통 부딪힘이 Balance.SCALE_CONTACT 를 쓴다")
	# 환경: 가시(take_hazard)·수액 웅덩이(take_damage_over_time)는 배율 없이 그대로
	Progress.difficulty = "nightmare"
	Balance.region_override = "abyss"
	_player.hp = _player.max_hp
	_player._invuln_timer = 0.0
	_player.state = Player.State.IDLE
	var hp0 := _player.hp
	_player.take_hazard(15.0)
	var lost1 := hp0 - _player.hp
	_player.hp = _player.max_hp
	_player._invuln_timer = 0.0
	_player.state = Player.State.IDLE
	hp0 = _player.hp
	_player.take_damage_over_time(2.5)
	var lost2 := hp0 - _player.hp
	Balance.region_override = ""
	Progress.difficulty = "normal"
	_player.hp = _player.max_hp
	_player._invuln_timer = 0.0
	_player.state = Player.State.IDLE
	_check(_near(lost1, 15.0, 0.001) and _near(lost2, 2.5, 0.001), "환경 피해는 배율 없음 (심연·Nightmare 에서도 가시 15 → %.1f, 수액 웅덩이 2.5 → %.1f)" % [lost1, lost2])


# ---------- (e) 포자 구름 ----------
func _probe_spore() -> void:
	Progress.difficulty = "normal"
	Progress.abilities.erase("lantern")
	Balance.region_override = "abyss"
	var c: Node2D = (load("res://scenes/combat/spore_cloud.tscn") as PackedScene).instantiate()
	c.set("radius", 200.0)
	c.set("lifetime", 30.0)
	c.set("dps", 6.0)
	add_child(c)
	c.global_position = _player.global_position + Vector2(0, -40)
	_player.hp = _player.max_hp
	await _frames(4)
	var hp0 := _player.hp
	var frames := int(2.0 * Engine.physics_ticks_per_second) + 2
	await _frames(frames)
	var lost := hp0 - _player.hp
	c.queue_free()
	Balance.region_override = ""
	var per_tick := 6.0 * 0.5 * 1.45 * 1.15 * pow(1.1, 4)
	var ticks := roundf(lost / per_tick)
	_check(ticks >= 3.0 and _near(lost, ticks * per_tick, 0.05), "포자 구름(심연, dps 6): 0.5초마다 %.2f (6×0.5×1.45×1.15×1.1⁴) — 2초 동안 %.2f 깎임 (%d번)" % [per_tick, lost, int(ticks)])
	_player.hp = _player.max_hp


# ---------- (f) 난이도 ----------
func _probe_difficulty() -> void:
	var want := {"easy": 0.7, "normal": 1.0, "hard": 1.15, "nightmare": 1.3}
	for d in want:
		Progress.difficulty = d
		var dmg := _incoming(30.0, "mine")       # 기사 내려찍기
		var hp := 1650.0 * Balance.hp_mult("mine")
		_check(_near(dmg, 52.635 * 1.15 * want[d], 0.03) and _near(hp, 1996.5 * 1.15 * want[d], 0.06),
			"난이도 %s: 기사 내려찍기 30 → %.1f, 기사 체력 %.1f (새 Normal 의 %.0f%%)" % [d, dmg, hp, want[d] * 100.0])
	Progress.difficulty = "normal"


# ---------- (g) v1.1.1 보스별 추가 공격 ----------
func _spawn_boss(path: String, region: String) -> Node2D:
	Balance.region_override = region
	var n: Node2D = (load(path) as PackedScene).instantiate()
	n.position = Vector2(-3000, -100)
	add_child(n)
	await _frames(1)
	Balance.region_override = ""
	return n


func _probe_boss_atk() -> void:
	Progress.difficulty = "normal"
	# [씬, 지역, [[값 이름, v1.1.0 값], ...], 추가 공격 배율]
	var cases := [
		["res://scenes/bosses/gray_leaf_bird.tscn", "canopy", [["sweep_damage", 20.0], ["feather_damage", 14.0], ["leaf_damage", 10.0], ["peck_damage", 16.0], ["_landing_damage", 16.0]], 1.05],
		["res://scenes/bosses/iron_pump.tscn", "flooded_mine", [["piston_damage", 28.0], ["shock_damage", 16.0], ["spray_damage", 14.0], ["bite_damage", 22.0], ["spurt_damage", 14.0], ["_vent_damage", 20.0]], 1.10],
		["res://scenes/bosses/sap_queen.tscn", "sap_lake", [["wave_damage", 18.0], ["dust_damage", 14.0], ["butterfly_damage", 14.0], ["land_damage", 14.0]], 1.05],
		["res://scenes/bosses/lantern_knight.tscn", "mine", [["slam_damage", 30.0], ["thrust_damage", 22.0], ["flame_damage", 18.0], ["ring_damage", 14.0]], 1.0],
	]
	for c in cases:
		for rep_i in 2:   # 두 번 만들어도 겹치지 않는다
			var b := await _spawn_boss(c[0], c[1])
			var bad := []
			for pair in c[2]:
				var got := float(b.get(pair[0]))
				if not _near(got, float(pair[1]) * float(c[3]), 0.001):
					bad.append("%s %.2f (기대 %.2f)" % [pair[0], got, float(pair[1]) * float(c[3])])
			b.queue_free()
			await _frames(1)
			_check(bad.is_empty(), "%s 추가 공격 ×%.2f (%d번째로 만든 것)%s" % [String(c[0]).get_file().get_basename(), c[3], rep_i + 1, ("" if bad.is_empty() else ": " + ", ".join(bad))])
	var k := await _spawn_boss("res://scenes/bosses/lantern_knight.tscn", "mine")
	var combo: Array = k.get("combo_damages")
	k.queue_free()
	await _frames(1)
	_check(combo.size() == 3 and _near(combo[0], 16.0, 0.001) and _near(combo[1], 18.0, 0.001) and _near(combo[2], 24.0, 0.001), "등불 기사 3연격 %s 그대로 (기사는 고유 변경 없음)" % str(combo))
	# 소녀가 받는 최종 피해 예 (새 Normal): 새 날개 휘두르기 20 × 1.05 × 1.45 × 1.15 = 35.0, 펌프 피스톤 28 × 1.1 × 1.45 × 1.15 × 1.21 = 62.2
	var bird_sweep := _incoming(20.0 * 1.05, "canopy")
	var pump_piston := _incoming(28.0 * 1.10, "flooded_mine")
	_check(_near(bird_sweep, 35.02, 0.02) and _near(pump_piston, 62.15, 0.03), "최종 받는 피해 (Normal): 새 날개 휘두르기 %.2f, 펌프 피스톤 %.2f" % [bird_sweep, pump_piston])
	# 표 자체 (뿌리지기는 root_keeper.gd 가 읽는다)
	_check(_near(Balance.boss_extra("root", "hp"), 1.75, 0.0001) and _near(Balance.boss_extra("root", "atk"), 1.25, 0.0001) and _near(Balance.boss_extra("root", "atk_phase2"), 1.10, 0.0001)
		and _near(Balance.boss_extra("knight", "hp"), 1.0, 0.0001) and _near(Balance.boss_extra("nobody", "hp"), 1.0, 0.0001), "BOSS_EXTRA 표: 뿌리지기 체력 1.75·공격 1.25·2페이즈 1.10, 기사 1, 모르는 이름 1")


# ---------- (h) v1.1.1 영혼 기술 → 보스 ----------
class _Dummy extends Node2D:
	var got := -1.0
	func receive_hit(hit: HitData, _hb: Hurtbox) -> String:
		got = hit.damage
		return "hit"


func _dummy(is_boss: bool) -> _Dummy:
	var d := _Dummy.new()
	if is_boss:
		d.add_to_group("boss")
	var hb := Hurtbox.new()
	d.add_child(hb)
	add_child(d)
	return d


func _soul_hit(soul: String, dmg: float) -> HitData:
	var h := HitData.make(dmg, 10.0, _player)
	h.from_player = true
	h.soul = soul
	return h


func _probe_soul_vs_boss() -> void:
	var boss := _dummy(true)
	var mob := _dummy(false)
	await _frames(1)
	var hb_boss: Hurtbox = boss.get_child(0)
	var hb_mob: Hurtbox = mob.get_child(0)
	# [영혼, 피해(새순 없는 기본: 씨앗 40·바람 120·빛 95.2), 보스 배율]
	for c in [["seed", 40.0, 1.1], ["wind", 120.0, 0.8], ["light", 95.2, 0.8]]:
		var h := _soul_hit(c[0], c[1])
		hb_boss.receive(h)
		var to_boss := boss.got
		hb_mob.receive(h)
		var to_mob := mob.got
		_check(_near(to_boss, float(c[1]) * float(c[2]), 0.001) and _near(to_mob, float(c[1]), 0.001) and _near(h.damage, float(c[1]), 0.0001),
			"영혼 %s %.1f: 보스에게 %.2f (×%.1f), 몹·중간 보스에게 %.1f, 원본 %.1f 그대로" % [c[0], c[1], to_boss, c[2], to_mob, h.damage])
	# 영혼 기술이 아닌 소녀 공격·되받은 투사체·적의 공격은 그대로 (같은 객체)
	var plain := HitData.make(30.0, 10.0, _player)
	plain.from_player = true
	var enemy_soul := HitData.make(30.0, 10.0, null)
	enemy_soul.soul = "wind"
	_check(plain.for_target(boss) == plain and enemy_soul.for_target(boss) == enemy_soul and _soul_hit("seed", 40.0).for_target(mob) != null,
		"영혼이 아닌 공격·소녀 것이 아닌 공격은 배율 없음 (같은 HitData)")
	# 실제 보스: 다섯 보스는 모두 group "boss" (중간 보스 잿가지 거인은 아님)
	var in_group := []
	for path in ["res://scenes/bosses/gray_leaf_bird.tscn", "res://scenes/bosses/lantern_knight.tscn", "res://scenes/bosses/iron_pump.tscn", "res://scenes/bosses/sap_queen.tscn", "res://scenes/bosses/root_keeper.tscn", "res://scenes/enemies/ash_giant.tscn"]:
		var n := await _spawn_boss(path, "canopy")
		in_group.append(n.is_in_group("boss"))
		n.queue_free()
		await _frames(1)
	_check(in_group == [true, true, true, true, true, false], "다섯 보스는 group \"boss\", 잿가지 거인(중간 보스)은 아님 %s" % str(in_group))
	boss.queue_free()
	mob.queue_free()
	await _frames(1)

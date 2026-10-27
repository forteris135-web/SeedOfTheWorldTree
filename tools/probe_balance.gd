extends Node
## Claude Code용 시험: v1.1.0 적·보스 능력치와 난이도 (기획자 요청 8·9, 명세 3.1·3.2).
## 실행: godot --headless --path . res://tools/probe_balance.tscn
##  (a) 배율표: 지역 6곳 × 난이도 4개의 체력·공격 배율 (Balance.hp_mult / atk_mult)
##  (b) 몹·거대화·보스의 최대 체력 (Normal, 지역마다 — Balance.region_override 로 지역을 정하고 씬을 실제로 만든다)
##  (c) 소녀가 받는 피해 예시 (Normal): 보스 공격·몹 공격이 Player.receive_hit 에서 배율을 받는다 (HitData 원본은 그대로)
##  (d) 몸통 부딪힘 8 은 모든 지역·난이도에서 8, 환경 피해(가시 take_hazard·수액 웅덩이 take_damage_over_time)는 배율 없음
##  (e) 포자 구름: 0.5초마다 dps×0.5×공격 배율
##  (f) 난이도 4개: 같은 공격·같은 체력이 0.7 / 1.0 / 1.15 / 1.3 배

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
			var hp_want: float = pow(1.1, tiers[reg]) * diffs[d]
			var atk_want: float = 1.45 * pow(1.1, tiers[reg]) * diffs[d]
			if not (_near(Balance.hp_mult(reg), hp_want, 0.0005) and _near(Balance.atk_mult(reg), atk_want, 0.0005)):
				_check(false, "배율 %s/%s: 체력 %.4f (기대 %.4f), 공격 %.4f (기대 %.4f)" % [d, reg, Balance.hp_mult(reg), hp_want, Balance.atk_mult(reg), atk_want])
	_check(true, "배율표 6지역 × 4난이도 = 체력 1.1^단계 × 난이도, 공격 1.45 × 1.1^단계 × 난이도")
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
	var cases := [
		["res://scenes/bosses/gray_leaf_bird.tscn", "canopy", 1800.0],
		["res://scenes/bosses/iron_pump.tscn", "flooded_mine", 1936.0],
		["res://scenes/bosses/lantern_knight.tscn", "mine", 1996.5],
		["res://scenes/bosses/sap_queen.tscn", "sap_lake", 1730.3],
		["res://scenes/bosses/root_keeper.tscn", "abyss", 3074.61 * 1.75],   # v1.1.1 뿌리지기 추가 체력 ×1.75 (root_keeper.gd extra("hp"))
		["res://scenes/enemies/woodcutter.tscn", "canopy", 95.0],
		["res://scenes/enemies/gardener.tscn", "canopy", 70.0],
		["res://scenes/enemies/guard.tscn", "village", 110.0],
		["res://scenes/enemies/machine.tscn", "mine", 205.7],
		["res://scenes/enemies/machine.tscn", "abyss", 248.9],
		["res://scenes/enemies/gardener.tscn", "mine", 84.7],
		["res://scenes/enemies/small_pump.tscn", "flooded_mine", 108.9],
		["res://scenes/enemies/sap_fisher.tscn", "sap_lake", 113.1],
		["res://scenes/enemies/herbalist.tscn", "abyss", 102.5],
		["res://scenes/enemies/elite_woodcutter.tscn", "canopy", 380.0],
		["res://scenes/enemies/elite_gardener.tscn", "canopy", 280.0],
		["res://scenes/enemies/ash_giant.tscn", "canopy", 360.0],
		["res://scenes/enemies/elite_guard.tscn", "village", 440.0],
	]
	for c in cases:
		var got := await _spawn_hp(c[0], c[1])
		_check(_near(got, c[2], 0.11), "체력 %s (%s, Normal) = %.1f (기대 %.1f)" % [String(c[0]).get_file().get_basename(), c[1], got, c[2]])
	# 같은 씬을 두 번 만들어도 겹쳐 곱해지지 않는다 (다시 나타나는 몹)
	var a := await _spawn_hp("res://scenes/enemies/guard.tscn", "village")
	var b := await _spawn_hp("res://scenes/enemies/guard.tscn", "village")
	_check(_near(a, b, 0.001) and _near(a, 110.0, 0.01), "다시 만든 경비병도 110 (겹쳐 곱해지지 않음: %.1f, %.1f)" % [a, b])


# ---------- (c) 받는 피해 ----------
func _incoming(base: float, region: String) -> float:
	Balance.region_override = region
	var h := HitData.make(base, 0.0, null)
	var v := Balance.incoming_damage(h, _player)
	Balance.region_override = ""
	return v


func _probe_damage() -> void:
	Progress.difficulty = "normal"
	var cases := [
		["새 날개 휘두르기", 20.0, "canopy", 29.0], ["새 깃털", 14.0, "canopy", 20.3],
		["기사 내려찍기", 30.0, "mine", 52.6], ["기사 3연격 1", 16.0, "mine", 28.1], ["기사 3연격 2", 18.0, "mine", 31.6], ["기사 3연격 3", 24.0, "mine", 42.1],
		["뿌리지기 뿌리 벽", 32.0, "abyss", 67.9], ["뿌리지기 휘두르기", 24.0, "abyss", 50.9],
		["여왕 물결", 18.0, "sap_lake", 34.7], ["펌프 피스톤", 28.0, "flooded_mine", 49.1],
		["나무꾼", 18.0, "canopy", 26.1], ["경비병 방패 치기", 12.0, "village", 19.1], ["기계(채굴장)", 20.0, "mine", 35.1],
	]
	for c in cases:
		var got := _incoming(c[1], c[2])
		_check(_near(got, c[3], 0.06), "받는 피해 %s %.0f → %.1f (기대 %.1f, %s)" % [c[0], c[1], got, c[3], c[2]])
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
	_check(_near(lost, 10.0 * 1.45 * pow(1.1, 4), 0.02) and _near(h.damage, 10.0, 0.0001), "receive_hit: 심연 10 → %.2f 깎임 (HitData 원본 %.1f 그대로)" % [lost, h.damage])
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
	var per_tick := 6.0 * 0.5 * 1.45 * pow(1.1, 4)
	var ticks := roundf(lost / per_tick)
	_check(ticks >= 3.0 and _near(lost, ticks * per_tick, 0.05), "포자 구름(심연, dps 6): 0.5초마다 %.2f (6×0.5×1.45×1.1⁴) — 2초 동안 %.2f 깎임 (%d번)" % [per_tick, lost, int(ticks)])
	_player.hp = _player.max_hp


# ---------- (f) 난이도 ----------
func _probe_difficulty() -> void:
	var want := {"easy": 0.7, "normal": 1.0, "hard": 1.15, "nightmare": 1.3}
	for d in want:
		Progress.difficulty = d
		var dmg := _incoming(30.0, "mine")       # 기사 내려찍기
		var hp := 1650.0 * Balance.hp_mult("mine")
		_check(_near(dmg, 52.635 * want[d], 0.02) and _near(hp, 1996.5 * want[d], 0.05),
			"난이도 %s: 기사 내려찍기 30 → %.1f, 기사 체력 %.1f (Normal 의 %.0f%%)" % [d, dmg, hp, want[d] * 100.0])
	Progress.difficulty = "normal"

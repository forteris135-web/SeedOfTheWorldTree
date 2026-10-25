extends Node
## 맞딜 승인 시험 (v1.1.0 기획자 요청 8 마지막 문장: "보스의 공격 패턴을 무시하고 맞으면서 공격하는 방식으로 쉽게 승리할 수 없도록").
## 실행: godot --headless --fixed-fps 60 --path . res://tools/probe_facetank.tscn -- [--quick] [--diff normal] [--only knight]
## 봇: 가드·구르기·점프를 하지 않는다. 매 물리 틱:
##   체력 40% 미만 + 이슬 있음 + 바닥 → 회복 / 아니면 영혼 기술(씨앗 베기) 쿨이 끝났으면 사용 / 아니면 공격 버튼(누름·뗌 반복).
##   0.25초마다 목표 자리에서 (가로) 60px 넘게 떨어졌으면 목표 자리 바닥으로 옮기고 보스 쪽을 본다.
##   목표 자리: front(보스 앞 140) / back(보스 뒤 140) / inside(보스 x). 공중 보스면 그 x 의 바닥.
## 성장: 그 보스를 만날 즈음의 예상치 (명세 3.8 표 — Progress.upgrades 를 직접 정한다, 영혼 '씨앗').
## 통과: Normal 에서 5보스 × 3자리 × 씨드 2개 = 30판 모두 봇이 쓰러진다 (300초 안에). 이기거나 300초를 버티면 FAIL.
##   --quick (전체 회귀용): front·inside × 씨드 1 = 10판. --diff easy 등: 결과만 출력 (합격 판정은 Normal 만).
##   스태미너 흉내 (P 묶음 병합 전): 소녀에게 스태미너 규칙이 아직 없으면(Player.light_stamina_cost 없음) **저절로** 켜진다.
##   봇이 명세 2.1·2.2 의 규칙(1·2·3타 10/12/15, 공격 중 회복 없음, 벗어난 뒤 0.5초 지연, 28/초, 3타 뒤 0.35초 잠금)을 스스로 지키며
##   누르고, 소녀의 피해도 P 묶음 값으로 맞춘다(씨앗 베기 32 → 40, 일반·씨앗 새순 배율 Progress.skill_damage_mult) — 맞딜 승인 기준은
##   합친 게임(명세 9.5)이므로. 소녀 쪽에 스태미너가 들어오면 저절로 꺼진다 (두 번 빠지지 않게).
##   --sim-stamina: 늘 켠다 / --no-sim: 늘 끈다 (스태미너 없는 지금 소녀 그대로 — 참고용 '날것' 결과).

const TIME_LIMIT := 300.0
const SPOT_DIST := 140.0
const MOVE_TOL := 60.0
const MOVE_EVERY := 0.25
const HEAL_BELOW := 0.4

## 보스별 성장 프로필 (명세 3.8). tok = [normal, seed, wind, light, stamina]
const PROFILES := [
	{"id": "bird", "room": "canopy_boss", "max_hp": 25.0, "attack": 0.05, "heal": 10.0, "dews": 0.0, "tok": [1, 0, 0, 0, 0], "ab": []},
	{"id": "pump", "room": "flooded_mine_boss", "max_hp": 35.0, "attack": 0.10, "heal": 10.0, "dews": 1.0, "tok": [1, 1, 0, 0, 1], "ab": ["double_jump", "wind"]},
	{"id": "knight", "room": "mine_boss", "max_hp": 55.0, "attack": 0.15, "heal": 20.0, "dews": 1.0, "tok": [1, 1, 1, 0, 1], "ab": ["double_jump", "wind", "wall_break"]},
	{"id": "queen", "room": "sap_lake_boss", "max_hp": 85.0, "attack": 0.25, "heal": 30.0, "dews": 2.0, "tok": [2, 1, 1, 1, 2], "ab": ["double_jump", "wind", "wall_break", "light", "lantern"]},
	{"id": "root", "room": "abyss_boss", "max_hp": 110.0, "attack": 0.35, "heal": 40.0, "dews": 2.0, "tok": [2, 2, 1, 1, 2], "ab": ["double_jump", "wind", "wall_break", "light", "lantern", "sap_walk", "sap_pulse"]},
]
const TRACKS := ["normal", "seed", "wind", "light", "stamina"]
## --sim-stamina 의 숫자 (명세 2.1·2.2)
const SIM_COST := [10.0, 12.0, 15.0]
const SIM_REGEN := 28.0
const SIM_DELAY := 0.5
const SIM_LOCK := 0.35
## --fixed-fps 없이(실시간으로) 돌 때: 물리 틱을 ACCEL 배로 늘리고 시간 배수도 ACCEL 배 → 한 틱은 그대로 1/60초, 게임은 ACCEL 배 빠르게.
## (전체 회귀 래퍼가 인자 없이 부를 때 900초 안에 끝나게. 판정 방식·숫자는 같다 — 히트스톱만 짧아진다)
const ACCEL := 6

var _fail := 0
var _sim := false
var _sim_mode := "auto"
var _accel := 1
var _diff := "normal"
var _results: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var quick := "--quick" in args
	_sim_mode = "on" if "--sim-stamina" in args else ("off" if "--no-sim" in args else "auto")
	# --fixed-fps 로 도는가: 물리 30틱이 실제 시간 0.25초보다 빨리 지나가면 그렇다 (엔진 인자는 get_cmdline_args 에 남지 않는다)
	var t_us := Time.get_ticks_usec()
	await _frames(30)
	var fast := (Time.get_ticks_usec() - t_us) < 250000
	if not fast:
		# 실시간 실행: 빠른 판으로 줄이고 물리를 ACCEL 배로 돌린다
		quick = quick or not ("--full" in args)
		_accel = ACCEL
		Engine.physics_ticks_per_second = 60 * ACCEL
		Engine.max_physics_steps_per_frame = 8 * ACCEL
	var di := args.find("--diff")
	if di >= 0 and di + 1 < args.size():
		_diff = args[di + 1]
	var only := ""
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1]
	var spots := ["front", "inside"] if quick else ["front", "back", "inside"]
	var seeds := [1] if quick else [1, 2]
	var si := args.find("--spots")
	if si >= 0 and si + 1 < args.size():
		spots = Array(args[si + 1].split(","))
	Settings.data["screen_shake"] = false
	print("[probe] 맞딜 시험 시작 (난이도 %s, %s, 물리 %d틱/초 × 시간 %d배, 스태미너 흉내 %s)" % [_diff, "빠른 판" if quick else "전체", Engine.physics_ticks_per_second, _accel, {"auto": "자동", "on": "켬", "off": "끔"}[_sim_mode]])
	if _accel > 1:
		print("[probe] (실시간 실행이라 빠른 판·%d배속 — 전체 30판은 --fixed-fps 60 으로)" % _accel)
	var t_wall := Time.get_ticks_msec()
	for prof in PROFILES:
		if only != "" and prof["id"] != only:
			continue
		for spot in spots:
			for sd in seeds:
				await _run(prof, spot, sd)
	_summary()
	print("[probe] 걸린 시간 %.0f초 (벽시계)" % ((Time.get_ticks_msec() - t_wall) / 1000.0))
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _setup_progress(prof: Dictionary) -> void:
	Progress.reset()
	Progress.difficulty = _diff
	Progress.upgrades = {"max_hp": prof["max_hp"], "attack": prof["attack"], "heal": prof["heal"], "dews": prof["dews"]}
	for i in TRACKS.size():
		if int(prof["tok"][i]) > 0:
			Progress.upgrades["tok_" + TRACKS[i]] = float(prof["tok"][i])
	for a in prof["ab"]:
		Progress.abilities[a] = true
	Progress.soul = "seed"
	Progress.soul_cooldowns.clear()


func _release_all() -> void:
	for a in ["attack_light", "soul_ability", "heal", "guard", "dodge", "jump", "move_left", "move_right", "move_down", "move_up", "interact"]:
		if InputMap.has_action(a):
			Input.action_release(a)


## 한 판: 방을 읽고 싸움을 걸고, 봇이 쓰러지거나(통과) 보스가 쓰러지거나(실패) 300초가 지날 때(실패)까지.
func _run(prof: Dictionary, spot: String, sd: int) -> void:
	seed(9100 + sd * 7 + PROFILES.find(prof) * 31 + ["front", "back", "inside"].find(spot) * 3)
	_setup_progress(prof)
	_release_all()
	Engine.time_scale = float(_accel)
	var room: Node = load("res://scenes/rooms/%s.tscn" % prof["room"]).instantiate()
	add_child(room)
	await _frames(6)
	var player := get_tree().get_first_node_in_group("player") as Player
	var boss := room.get_node("Boss") as Node2D
	var gy: float = boss.ground_y
	var has_stamina := "light_stamina_cost" in player
	_sim = _sim_mode == "on" or (_sim_mode == "auto" and not has_stamina)
	if _results.is_empty():
		print("[probe] 소녀 스태미너 규칙: %s → 스태미너 흉내 %s" % ["있음 (P 묶음)" if has_stamina else "없음", "켬 (P 묶음 수치로 피해도 맞춤)" if _sim else "끔"])
	if _sim and not has_stamina:
		# P 묶음 수치 (명세 2.4·0.3): 씨앗 베기 40 × 씨앗 새순 배율, 일반 공격 × 일반 새순 배율 (공통 강화 attack_multiplier 는 소녀가 곱한다)
		player.slash_damage = 40.0 * Progress.skill_damage_mult("seed")
		var mn := Progress.skill_damage_mult("normal")
		player.light_damage = [12.0 * mn, 12.0 * mn, 18.0 * mn]
	var arena: Rect2 = boss.arena
	if "--log" in OS.get_cmdline_user_args():
		boss.debug_log = true
	player.global_position = Vector2(arena.get_center().x - 300.0, gy - 80.0)
	player.velocity = Vector2.ZERO
	await _frames(3)
	if not room.fight_started:
		room._on_trigger(player)
	Music.stop(0.0)   # 여왕 박자 시계는 실제 시간으로 (빠르게 돌리는 시험에서 음악 재생 위치에 묶이지 않게)
	var dmg_taken := [0.0]
	var hits := [0]
	player.hit_taken.connect(func(d: float) -> void:
		dmg_taken[0] += d
		hits[0] += 1)
	var heals := [0]
	player.healed.connect(func() -> void: heals[0] += 1)
	var tries := [0]
	var dews_prev := [player.dews]
	player.dews_changed.connect(func(n: int) -> void:
		if n < dews_prev[0]:
			tries[0] += 1
		dews_prev[0] = n)
	# --sim-stamina: [스태미너, 회복 지연, 3타 잠금, 직전 틱에 공격 중이었나]
	var max_st := 100.0 + 3.0 * float(prof["tok"][4])
	var sim := [max_st, 0.0, 0.0, false]
	if _sim:
		player.attacked.connect(func(step: int) -> void:
			sim[0] -= SIM_COST[clampi(step - 1, 0, 2)]
			if step == 3:
				sim[2] = 0.09 + 0.12 + SIM_LOCK)
	var dt := float(_accel) / float(Engine.physics_ticks_per_second)   # 한 틱의 기준 게임 시간 1/60초 (히트스톱 없을 때; 여왕 박자 시계 보정용)
	var t := 0.0
	var move_t := 0.0
	var tick := 0
	var result := "draw"
	var hp_min := player.hp
	while t < TIME_LIMIT:
		await get_tree().physics_frame
		# 이 틱에 흐른 게임 시간: 히트스톱(시간 배수 0.05) 동안은 거의 흐르지 않는다 → 싸움 시간·300초 상한·0.25초 움직임 주기가
		# 히트스톱 틱 수만큼 늘어나지 않게 (예전엔 틱마다 1/60초를 그대로 더했다)
		var gdt := Engine.time_scale / float(Engine.physics_ticks_per_second)
		if _accel > 1 and Engine.time_scale != float(_accel):
			Engine.time_scale = float(_accel)   # 히트스톱이 1 로 되돌린 시간 배수를 다시 (한 틱 = 1/60초 유지)
		if _accel > 1 and boss is SapQueen:
			# 여왕의 박자 시계는 '시간 배수를 뺀 실제 시간'으로 센다 (히트스톱에 느려지지 않게) → 배속 실행에서는 게임 시간만큼 보탠다
			boss._clock += dt * (1.0 - 1.0 / float(_accel))
		t += gdt
		tick += 1
		if not is_instance_valid(player) or not is_instance_valid(boss):
			result = "gone"
			break
		hp_min = minf(hp_min, player.hp)
		if player.state == Player.State.DEAD:
			result = "died"
			break
		if boss.has_method("state_name") and boss.state_name() in ["FALLEN", "PURIFIED"]:
			result = "won"
			break
		# --- 움직임: 0.25초마다 목표 자리로 ---
		move_t += gdt
		if move_t >= MOVE_EVERY:
			move_t = 0.0
			var tx := _target_x(boss, spot, arena)
			if absf(player.global_position.x - tx) > MOVE_TOL:
				_teleport(player, tx, gy)
			_face(player, boss, spot)
		if tick % 30 == 0 and "--trace" in OS.get_cmdline_user_args():
			print("[dbg] t=%.1f hp=%.0f dews=%d st=%s ph=%s boss=%s bhp=%.0f dx=%.0f face=%d" % [t, player.hp, player.dews, Player.State.keys()[player.state], player.attack_phase, boss.state_name(), boss.hp, boss.global_position.x - player.global_position.x, player.facing])
		if _sim:
			var busy := player.state in [Player.State.ATTACK, Player.State.SOUL_SLASH, Player.State.PLUNGE, Player.State.GUARD]
			if sim[3] and not busy:
				sim[1] = maxf(sim[1], SIM_DELAY)
			sim[3] = busy
			sim[1] = maxf(sim[1] - gdt, 0.0)
			sim[2] = maxf(sim[2] - gdt, 0.0)
			if not busy and sim[1] <= 0.0 and sim[2] <= 0.0:
				sim[0] = minf(sim[0] + SIM_REGEN * gdt, max_st)
		# --- 행동: 짝수 틱에 누르고 홀수 틱에 모두 뗀다 (누를 때마다 '막 눌림'이 되게) ---
		_release_all()
		if tick % 2 == 1:
			continue
		if _sim and sim[2] > 0.0:
			continue   # 3타 뒤 잠금: 공격·영혼 기술 거절 (명세 2.2)
		var on_floor := player.is_on_floor()
		if player.hp < player.max_hp * HEAL_BELOW and player.dews > 0 and on_floor:
			# 회복: 공격을 멈추고(지금 동작이 끝나 서면 받아 준다) 회복 버튼
			Input.action_press("heal")
		elif player.soul_cooldown_left() <= 0.0 and (player.state in Player.LOCOMOTION or (player.state == Player.State.ATTACK and player.attack_phase == "recovery")):
			Input.action_press("soul_ability")
		else:
			var next_step := (player.attack_step % 3) + 1 if player.state == Player.State.ATTACK else 1
			if not _sim or sim[0] >= SIM_COST[next_step - 1]:
				Input.action_press("attack_light")
	_release_all()
	var boss_pct := 100.0 * float(boss.hp) / maxf(float(boss.max_hp), 1.0) if is_instance_valid(boss) else -1.0
	var row := {"boss": prof["id"], "spot": spot, "seed": sd, "result": result, "t": t, "boss_pct": boss_pct, "dmg": dmg_taken[0], "hits": hits[0], "heals": heals[0], "tries": tries[0]}
	_results.append(row)
	var line := "facetank %s %s seed %d: %s %.1f초 — 보스 체력 %.0f%% (%.0f/%.0f), 받은 피해 %.0f (%d대), 회복 %d번(시도 %d), 소녀 최대 체력 %.0f" % [
		prof["id"], spot, sd, {"died": "봇이 쓰러짐", "won": "봇이 이김", "draw": "300초 무승부", "gone": "사라짐"}[result], t, boss_pct,
		float(boss.hp) if is_instance_valid(boss) else 0.0, float(boss.max_hp) if is_instance_valid(boss) else 0.0, dmg_taken[0], hits[0], heals[0], tries[0],
		player.max_hp if is_instance_valid(player) else 0.0]
	if _diff == "normal":
		if result == "won":
			_check(false, "facetank %s %s seed %d won %.1f초 hp %.0f" % [prof["id"], spot, sd, t, player.hp if is_instance_valid(player) else 0.0])
			print("[probe]   " + line)
		elif result != "died":
			_check(false, line)
		else:
			_check(true, line)
	else:
		print("[probe] (참고) " + line)
	room.queue_free()
	await _frames(3)
	Fx.clear()
	Engine.time_scale = 1.0


func _target_x(boss: Node2D, spot: String, arena: Rect2) -> float:
	var f := float(boss.get("facing")) if boss.get("facing") != null else 1.0
	var x := boss.global_position.x
	match spot:
		"front":
			x += f * SPOT_DIST
		"back":
			x -= f * SPOT_DIST
	return clampf(x, arena.position.x + 40.0, arena.end.x - 40.0)


## 목표 x 의 바닥으로 옮긴다 (아래로 선을 쏘아 지형 윗면을 찾는다; 못 찾으면 보스 바닥선)
func _teleport(player: Player, x: float, gy: float) -> void:
	var space := player.get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(Vector2(x, gy - 420.0), Vector2(x, gy + 600.0), 1)
	ray.exclude = [player.get_rid()]
	var y := gy
	var hit := space.intersect_ray(ray)
	# 한쪽 방향 가지(공중 발판)는 건너뛰고 아래 바닥을 찾는다
	var guard_n := 0
	while not hit.is_empty() and guard_n < 6:
		var c = hit.get("collider")
		if c is Platform and (c as Platform).one_way:
			ray.exclude = ray.exclude + [hit["rid"]]
			hit = space.intersect_ray(ray)
			guard_n += 1
		else:
			break
	if not hit.is_empty():
		y = float(hit["position"].y)
	player.global_position = Vector2(x, y - BossRush.FOOT_OFFSET)
	player.velocity = Vector2.ZERO


func _face(player: Player, boss: Node2D, spot: String) -> void:
	var dx := boss.global_position.x - player.global_position.x
	if absf(dx) > 4.0:
		player.facing = 1 if dx > 0.0 else -1
	else:
		var f := int(boss.get("facing")) if boss.get("facing") != null else 1
		player.facing = -f   # 몸 한가운데: 보스가 보는 쪽을 마주 본다


func _summary() -> void:
	var by := {}
	for r in _results:
		var k: String = r["boss"]
		if not by.has(k):
			by[k] = {"n": 0, "died": 0, "t": 0.0, "dmg": 0.0, "boss_pct": 0.0}
		by[k]["n"] += 1
		by[k]["died"] += 1 if r["result"] == "died" else 0
		by[k]["t"] += r["t"]
		by[k]["dmg"] += r["dmg"]
		by[k]["boss_pct"] += r["boss_pct"]
	for k in by:
		var b: Dictionary = by[k]
		print("[probe] 요약 %s (%s): 봇 쓰러짐 %d/%d, 평균 버틴 시간 %.1f초, 평균 받은 피해 %.0f, 끝날 때 보스 체력 평균 %.0f%%" % [
			k, _diff, b["died"], b["n"], b["t"] / b["n"], b["dmg"] / b["n"], b["boss_pct"] / b["n"]])

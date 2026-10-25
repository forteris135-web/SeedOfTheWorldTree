extends Node
## 맞딜 승인 시험 (v1.1.0 기획자 요청 8 마지막 문장: "보스의 공격 패턴을 무시하고 맞으면서 공격하는 방식으로 쉽게 승리할 수 없도록").
## 실행: godot --headless --fixed-fps 60 --path . res://tools/probe_facetank.tscn -- [--quick] [--diff normal] [--only knight] [--mode stand,plunge_land]
##       [--spots front,back] [--seeds 1,2,3] [--trace (틱·맞은 공격·보스 상태·준 피해를 찍는다)]
## 봇 방식 (--mode, 쉼표로 여럿 또는 all; 기본 = 여섯 다. 스태미너를 안 쓰는 길(낙하·바람·빛)도 지킨다):
##   stand (땅 맞딜; 옛 이름 ground): 가드·구르기·점프를 하지 않는다. 매 물리 틱:
##     체력 40% 미만 + 이슬 있음 + 바닥 → 회복 / 아니면 영혼 기술(씨앗 베기) 쿨이 끝났으면 사용 / 아니면 공격 버튼(누름·뗌 반복).
##     0.25초마다 목표 자리에서 (가로) 60px 넘게 떨어졌으면 목표 자리 바닥으로 옮기고 보스 쪽을 본다.
##   plunge_air (공중 연속 낙하; 옛 이름 plunge): 가드·구르기·땅 공격 없이 바닥에 서면 점프 → 공중에서 낙하 공격 버튼만 거듭한다
##     (보스를 맞히면 튕겨 올라 다시 낙하 공격). 회복 규칙은 같고, 자리 옮기기는 바닥에 서 있을 때만 (낙하 방식 셋 모두).
##   plunge_land (착지 낙하, 최종 검수가 찾은 길): 점프 → 공중에서 낙하 공격 **한 번** → 튕겨도 다시 누르지 않고 착지 → 다시 점프 …
##     (예전 소녀의 '바닥을 디디면 감쇠가 처음으로' 규칙 때문에 낙하마다 피해·흐트러짐을 온전히 받던 길).
##   plunge_mix (낙하 + 씨앗 베기): 바닥에서 씨앗 베기 쿨이 끝났으면 베기, 아니면 점프 → 낙하 공격 한 번 → 착지.
##   wind / light: stand 와 같은데 영혼이 바람 / 빛 (그 능력이 있는 보스만 — 바람은 펌프부터, 빛은 여왕부터: 전체 24 / 12판).
##   목표 자리: front(보스 앞 140) / back(보스 뒤 140) / inside(보스 x). 공중 보스면 그 x 의 바닥.
## 성장: 그 보스를 만날 즈음의 예상치 (명세 3.8 표 — Progress.upgrades 를 직접 정한다, 영혼 '씨앗').
## 통과: Normal 에서 방식마다 5보스 × 3자리 × 씨드 2개 = 30판(바람 24·빛 12) 모두 봇이 쓰러진다 (300초 안에). 이기거나 300초를 버티면 FAIL.
##   --quick (전체 회귀용): 자리 front·inside × 씨드 1. --mode 를 주지 않으면 stand·plunge_air·wind·light 는 다섯 보스 모두,
##   plunge_land·plunge_mix 는 무쇠 펌프·뿌리지기만 (최종 검수에서 봇이 이기던 두 보스) — 모두 40판.
##   --diff easy 등: 결과만 출력 (합격 판정은 Normal 만).
##   --good: '잘하는 사람' 비교 (합격 판정 없음, 참고 출력): 무적 봇이 땅에서 3타·씨앗 베기를 하고 낙하 공격은 N초마다 한 번만
##   (기본 6초 — --good-every 2.5 처럼 바꾼다) 섞어 보스를 쓰러뜨리는 시간을 잰다 (낙하 감쇠가 가끔 쓰는 사람을 깎지 않는지 보는 용도).
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
const MODES := ["stand", "plunge_air", "plunge_land", "plunge_mix", "wind", "light"]
const MODE_NAMES := {"stand": "땅 맞딜", "plunge_air": "공중 연속 낙하", "plunge_land": "착지 낙하", "plunge_mix": "낙하+씨앗 베기", "wind": "바람 영혼", "light": "빛 영혼"}
## 옛 이름 (fixA 때의 --mode ground,plunge 도 그대로 받는다)
const MODE_ALIASES := {"ground": "stand", "plunge": "plunge_air"}
const PLUNGE_MODES := ["plunge_air", "plunge_land", "plunge_mix"]
## --quick 이고 --mode 를 주지 않았을 때 착지 낙하·낙하+베기를 돌릴 보스 (최종 검수에서 봇이 이기던 두 보스)
const QUICK_LAND_BOSSES := ["pump", "root"]
const QUICK_LAND_MODES := ["plunge_land", "plunge_mix"]
var _jump_hold := 0
## 착지 낙하·낙하+베기 봇: 이번에 뜬 동안 이미 낙하 공격을 했는가 (바닥에 서면 지운다)
var _plunged_air := false
var _trace_phase := ""


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
	var sdi := args.find("--seeds")
	if sdi >= 0 and sdi + 1 < args.size():
		seeds = []
		for v in args[sdi + 1].split(","):
			seeds.append(int(v))
	var si := args.find("--spots")
	if si >= 0 and si + 1 < args.size():
		spots = Array(args[si + 1].split(","))
	var modes := MODES.duplicate()
	var mi := args.find("--mode")
	var mode_given := mi >= 0 and mi + 1 < args.size() and args[mi + 1] != "all"
	if mode_given:
		modes = []
		for m in args[mi + 1].split(","):
			modes.append(MODE_ALIASES.get(m, m))
	for m in modes:
		if not m in MODES:
			_check(false, "모르는 방식 %s (%s)" % [m, MODES])
			get_tree().quit(1)
			return
	if "--good" in args:
		await _good_compare(args, only)
		get_tree().quit(0)
		return
	Settings.data["screen_shake"] = false
	print("[probe] 맞딜 시험 시작 (난이도 %s, %s, 방식 %s, 물리 %d틱/초 × 시간 %d배, 스태미너 흉내 %s)" % [_diff, "빠른 판" if quick else "전체", ",".join(modes), Engine.physics_ticks_per_second, _accel, {"auto": "자동", "on": "켬", "off": "끔"}[_sim_mode]])
	if _accel > 1:
		print("[probe] (실시간 실행이라 빠른 판·%d배속 — 전체 30판은 --fixed-fps 60 으로)" % _accel)
	var t_wall := Time.get_ticks_msec()
	for mode in modes:
		for prof in PROFILES:
			if only != "" and prof["id"] != only:
				continue
			if (mode == "wind" or mode == "light") and not mode in prof["ab"]:
				continue   # 그 영혼을 아직 못 얻은 보스
			if quick and not mode_given and mode in QUICK_LAND_MODES and not prof["id"] in QUICK_LAND_BOSSES:
				continue   # 빠른 판: 착지 낙하·낙하+베기는 펌프·뿌리지기만
			for spot in spots:
				for sd in seeds:
					await _run(prof, spot, sd, mode)
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


func _setup_progress(prof: Dictionary, mode: String) -> void:
	Progress.reset()
	Progress.difficulty = _diff
	Progress.upgrades = {"max_hp": prof["max_hp"], "attack": prof["attack"], "heal": prof["heal"], "dews": prof["dews"]}
	for i in TRACKS.size():
		if int(prof["tok"][i]) > 0:
			Progress.upgrades["tok_" + TRACKS[i]] = float(prof["tok"][i])
	for a in prof["ab"]:
		Progress.abilities[a] = true
	Progress.soul = mode if mode == "wind" or mode == "light" else "seed"
	Progress.soul_cooldowns.clear()


func _release_all() -> void:
	for a in ["attack_light", "soul_ability", "heal", "guard", "dodge", "jump", "move_left", "move_right", "move_down", "move_up", "interact", "plunge"]:
		if InputMap.has_action(a):
			Input.action_release(a)


## 한 판: 방을 읽고 싸움을 걸고, 봇이 쓰러지거나(통과) 보스가 쓰러지거나(실패) 300초가 지날 때(실패)까지.
func _run(prof: Dictionary, spot: String, sd: int, mode := "stand") -> void:
	seed(9100 + sd * 7 + PROFILES.find(prof) * 31 + ["front", "back", "inside"].find(spot) * 3)
	_setup_progress(prof, mode)
	_release_all()
	_jump_hold = 0
	_plunged_air = false
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
	var trace := "--trace" in OS.get_cmdline_user_args()
	var t_now := [0.0]
	# 보스에게 준 피해를 소녀 상태별로 (낙하 / 씨앗 베기 / 그 밖) — 어느 길이 이기는지 보려고
	var dealt := {"plunge": 0.0, "slash": 0.0, "other": 0.0}
	var bhp_prev := [float(boss.hp)]
	boss.hp_changed.connect(func(h: float, _m: float) -> void:
		if h < bhp_prev[0] and is_instance_valid(player):
			var k := "plunge" if player.state == Player.State.PLUNGE else ("slash" if player.state == Player.State.SOUL_SLASH else "other")
			dealt[k] += bhp_prev[0] - h
			if trace and k != "other":
				var pd = boss.get("plunge_decay")
				print("[dmg] t=%.1f %s %.1f (보스 %s, 낙하 창 n=%s) 흐트러짐 %.0f" % [t_now[0], k, bhp_prev[0] - h, boss.state_name(), str(pd.count) if pd else "-", float(boss.get("poise"))])
		bhp_prev[0] = h)
	player.hit_taken.connect(func(d: float) -> void:
		dmg_taken[0] += d
		hits[0] += 1
		if trace:
			print("[hit] t=%.1f 피해 %.0f ← %s/%s, 소녀 dx %.0f 높이 %.0f" % [t_now[0], d, boss.state_name(), str(boss.get("attack_phase")), player.global_position.x - boss.global_position.x, float(boss.ground_y) - player.global_position.y]))
	if trace and boss.has_signal("state_changed"):
		boss.state_changed.connect(func(_s) -> void: print("[boss] t=%.1f → %s (체력 %.0f)" % [t_now[0], boss.state_name(), float(boss.hp)]))
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
		t_now[0] = t
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
			# 낙하 공격 봇은 바닥에 서 있을 때만 옮긴다 (튕겨 오르는 중에 끌어내리지 않게)
			var can_move := not mode in PLUNGE_MODES or (player.is_on_floor() and player.state in Player.LOCOMOTION)
			if absf(player.global_position.x - tx) > MOVE_TOL and can_move:
				_teleport(player, tx, gy)
			_face(player, boss, spot)
		if trace:
			var ph := str(boss.get("attack_phase"))
			if ph == "active" and ph != _trace_phase:
				print("[act] t=%.1f %s 타격 시작 — 소녀 %s dx %.0f 높이 %.0f 무적 %.2f" % [t, boss.state_name(), Player.State.keys()[player.state], player.global_position.x - boss.global_position.x, float(boss.ground_y) - player.global_position.y, player._invuln_timer])
			_trace_phase = ph
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
		elif mode in PLUNGE_MODES:
			# plunge_air: 바닥에 서면 점프(올라가는 동안 점프 버튼을 다시 눌러 높이) → 떨어지기 시작하면 낙하 공격 버튼
			#   (보스를 맞혀 튕겨 오르면 잠금 동안 누른 것은 기억됐다가 풀리는 순간 다시 내려꽂는다)
			# plunge_land / plunge_mix: 뜬 동안 낙하 공격은 한 번만 — 튕겨도 다시 누르지 않고 착지한 뒤 다시 점프
			#   (plunge_mix 는 바닥에서 씨앗 베기 쿨이 끝났으면 먼저 벤다)
			if on_floor:
				_plunged_air = false
			if player.state == Player.State.PLUNGE:
				_plunged_air = true
			if on_floor and player.state in Player.LOCOMOTION:
				if mode == "plunge_mix" and player.soul_cooldown_left() <= 0.0:
					Input.action_press("soul_ability")
				else:
					Input.action_press("jump")
					_jump_hold = 30
			elif not on_floor and player.state in Player.LOCOMOTION and player.velocity.y > -150.0 and (mode == "plunge_air" or not _plunged_air):
				Input.action_press("plunge")
			if _jump_hold > 0 and not on_floor and player.velocity.y < 0.0:
				Input.action_press("jump")
				_jump_hold -= 1
		elif player.soul_cooldown_left() <= 0.0 and (player.state in Player.LOCOMOTION or (player.state == Player.State.ATTACK and player.attack_phase == "recovery")):
			Input.action_press("soul_ability")
		else:
			var next_step := (player.attack_step % 3) + 1 if player.state == Player.State.ATTACK else 1
			if not _sim or sim[0] >= SIM_COST[next_step - 1]:
				Input.action_press("attack_light")
	_release_all()
	var boss_pct := 100.0 * float(boss.hp) / maxf(float(boss.max_hp), 1.0) if is_instance_valid(boss) else -1.0
	var row := {"mode": mode, "boss": prof["id"], "spot": spot, "seed": sd, "result": result, "t": t, "boss_pct": boss_pct, "dmg": dmg_taken[0], "hits": hits[0], "heals": heals[0], "tries": tries[0]}
	_results.append(row)
	var dsum := maxf(dealt["plunge"] + dealt["slash"] + dealt["other"], 1.0)
	var line := "facetank %s%s %s seed %d: %s %.1f초 — 보스 체력 %.0f%% (%.0f/%.0f), 받은 피해 %.0f (%d대), 회복 %d번(시도 %d), 소녀 최대 체력 %.0f, 준 피해 낙하 %.0f%%·베기 %.0f%%" % [
		"" if mode == "stand" else mode + " ", prof["id"], spot, sd, {"died": "봇이 쓰러짐", "won": "봇이 이김", "draw": "300초 무승부", "gone": "사라짐"}[result], t, boss_pct,
		float(boss.hp) if is_instance_valid(boss) else 0.0, float(boss.max_hp) if is_instance_valid(boss) else 0.0, dmg_taken[0], hits[0], heals[0], tries[0],
		player.max_hp if is_instance_valid(player) else 0.0, 100.0 * dealt["plunge"] / dsum, 100.0 * dealt["slash"] / dsum]
	if _diff == "normal":
		if result == "won":
			_check(false, "facetank %s%s %s seed %d won %.1f초 hp %.0f" % ["" if mode == "stand" else mode + " ", prof["id"], spot, sd, t, player.hp if is_instance_valid(player) else 0.0])
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
		var k: String = "%s|%s" % [r["mode"], r["boss"]]
		if not by.has(k):
			by[k] = {"n": 0, "died": 0, "t": 0.0, "dmg": 0.0, "boss_pct": 0.0}
		by[k]["n"] += 1
		by[k]["died"] += 1 if r["result"] == "died" else 0
		by[k]["t"] += r["t"]
		by[k]["dmg"] += r["dmg"]
		by[k]["boss_pct"] += r["boss_pct"]
	for k in by:
		var b: Dictionary = by[k]
		var mk: Array = k.split("|")
		print("[probe] 요약 [%s] %s (%s): 봇 쓰러짐 %d/%d, 평균 버틴 시간 %.1f초, 평균 받은 피해 %.0f, 끝날 때 보스 체력 평균 %.0f%%" % [
			MODE_NAMES.get(mk[0], mk[0]), mk[1], _diff, b["died"], b["n"], b["t"] / b["n"], b["dmg"] / b["n"], b["boss_pct"] / b["n"]])


## --good: '잘하는 사람' 비교 (참고 출력, 합격 판정 없음). 무적 봇이 보스 앞(front)에서 땅 3타·씨앗 베기를 하고, 낙하 공격은
## every 초마다 한 번만 (점프 → 낙하 한 번 → 착지) 섞는다. 같은 봇을 낙하 감쇠(PlungeDecay) 끔/켬으로 돌려 보스를 쓰러뜨리는 시간을 견준다.
## 패턴을 피하는 사람은 맞지 않으니 무적으로 둔다 (피하는 동안 못 때리는 시간은 빠지므로 '가장 빨리 잡을 때'의 비교).
func _good_compare(args: PackedStringArray, only: String) -> void:
	var every_list: Array = [6.0, 2.5]
	var gi := args.find("--good-every")
	if gi >= 0 and gi + 1 < args.size():
		every_list = []
		for v in args[gi + 1].split(","):
			every_list.append(float(v))
	print("[probe] 잘하는 봇 비교 (난이도 %s, 무적, 보스 앞, 낙하 %s초마다 한 번) — 낙하 감쇠 끔 → 켬" % [_diff, every_list])
	for prof in PROFILES:
		if only != "" and prof["id"] != only:
			continue
		for every in every_list:
			var res := {}
			for on in [false, true]:
				PlungeDecay.enabled = on
				res[on] = await _good_run(prof, float(every))
			PlungeDecay.enabled = true
			var a: Dictionary = res[false]
			var b: Dictionary = res[true]
			print("[probe] (참고) 잘하는 봇 %s 낙하 %.1f초마다: 감쇠 끔 %.1f초(낙하 %d번, 낙하 피해 %.0f%%) → 켬 %.1f초(낙하 %d번, 낙하 피해 %.0f%%), 잡는 시간 %+.1f%%" % [
				prof["id"], every, a["t"], a["n"], a["share"], b["t"], b["n"], b["share"], 100.0 * (b["t"] - a["t"]) / maxf(a["t"], 0.01)])


func _good_run(prof: Dictionary, every: float) -> Dictionary:
	seed(9100 + PROFILES.find(prof) * 31)
	_setup_progress(prof, "stand")
	_release_all()
	Engine.time_scale = float(_accel)
	var room: Node = load("res://scenes/rooms/%s.tscn" % prof["room"]).instantiate()
	add_child(room)
	await _frames(6)
	var player := get_tree().get_first_node_in_group("player") as Player
	var boss := room.get_node("Boss") as Node2D
	var gy: float = boss.ground_y
	var arena: Rect2 = boss.arena
	player.global_position = Vector2(arena.get_center().x - 300.0, gy - 80.0)
	player.velocity = Vector2.ZERO
	await _frames(3)
	if not room.fight_started:
		room._on_trigger(player)
	Music.stop(0.0)
	var plunge_dmg := [0.0]
	var all_dmg := [0.0]
	var prev := [float(boss.hp)]
	boss.hp_changed.connect(func(h: float, _m: float) -> void:
		if h < prev[0]:
			all_dmg[0] += prev[0] - h
			if is_instance_valid(player) and player.state == Player.State.PLUNGE:
				plunge_dmg[0] += prev[0] - h
		prev[0] = h)
	var t := 0.0
	var move_t := 0.0
	var tick := 0
	var last_plunge := -every   # 시작하자마자 한 번
	var plunging := false
	var plunged := false
	var n_plunge := [0]
	player.plunge_started.connect(func() -> void: n_plunge[0] += 1)
	var won := false
	_jump_hold = 0
	while t < TIME_LIMIT:
		await get_tree().physics_frame
		var gdt := Engine.time_scale / float(Engine.physics_ticks_per_second)
		if _accel > 1 and Engine.time_scale != float(_accel):
			Engine.time_scale = float(_accel)
		t += gdt
		tick += 1
		if not is_instance_valid(player) or not is_instance_valid(boss):
			break
		player._invuln_timer = 1.0   # 패턴을 피하는 사람: 맞지 않는다
		player.hp = player.max_hp
		if boss.state_name() in ["FALLEN", "PURIFIED"]:
			won = true
			break
		var on_floor := player.is_on_floor()
		move_t += gdt
		if move_t >= MOVE_EVERY:
			move_t = 0.0
			var tx := _target_x(boss, "front", arena)
			if absf(player.global_position.x - tx) > MOVE_TOL and on_floor and player.state in Player.LOCOMOTION and not plunging:
				_teleport(player, tx, gy)
			_face(player, boss, "front")
		_release_all()
		if tick % 2 == 1:
			continue
		if plunging:
			if player.state == Player.State.PLUNGE:
				plunged = true
			if on_floor and plunged and player.state in Player.LOCOMOTION:
				plunging = false
				last_plunge = t
			elif on_floor and player.state in Player.LOCOMOTION:
				Input.action_press("jump")
				_jump_hold = 30
			elif not on_floor and not plunged and player.state in Player.LOCOMOTION and player.velocity.y > -150.0:
				Input.action_press("plunge")
			if _jump_hold > 0 and not on_floor and player.velocity.y < 0.0:
				Input.action_press("jump")
				_jump_hold -= 1
			continue
		if t - last_plunge >= every and on_floor and player.state in Player.LOCOMOTION:
			plunging = true
			plunged = false
			Input.action_press("jump")
			_jump_hold = 30
		elif player.soul_cooldown_left() <= 0.0 and (player.state in Player.LOCOMOTION or (player.state == Player.State.ATTACK and player.attack_phase == "recovery")):
			Input.action_press("soul_ability")
		else:
			Input.action_press("attack_light")
	_release_all()
	var out := {"t": t if won else TIME_LIMIT, "n": n_plunge[0], "share": 100.0 * plunge_dmg[0] / maxf(all_dmg[0], 1.0)}
	room.queue_free()
	await _frames(3)
	Fx.clear()
	Engine.time_scale = 1.0
	return out

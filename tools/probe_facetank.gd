extends Node
## 맞딜 승인 시험 (v1.1.0 기획자 요청 8 마지막 문장: "보스의 공격 패턴을 무시하고 맞으면서 공격하는 방식으로 쉽게 승리할 수 없도록").
## 실행: godot --headless --fixed-fps 60 --path . res://tools/probe_facetank.tscn -- [--quick] [--mode stand,platform|all] [--only pump,queen]
##       [--spots front,back] [--seeds 6 (= 1..6) | 1,3 | 2-4] [--diff normal] [--trace] [--no-strict-face] [--roll-cost 15]
##       [--soul-lock 1.5 (영혼 기술 함께 잠김을 바꿔 본다)] [--boss-set 이름=값,이름=값 / --player-set 이름=값 (보스·소녀 노드의 값을 바꿔 본다)] [--good [--good-seeds 4] [--good-roll-cost 0]] [--list (계획만 출력)]
## 마지막 줄 "[probe] 끝: 실패 N". 판마다 한 줄, 끝에 보스 × 방식 표.
##
## 봇 방식 (--mode, 쉼표로 여럿 또는 all; 기본 = 전부). 모든 봇은 가드·저스트 가드를 하지 않고(구르기는 rolltank·hitrun·punish_roll 만),
## **돌아서기는 사람처럼**: 공격·영혼 기술·낙하·구르기·맞음 도중에는 방향을 바꾸지 않는다 (이동 상태에서만; --no-strict-face 로 끔).
## 회복은 공통: 체력 40% 미만 + 이슬 있음 + 바닥 → 회복 버튼.
##   stand       땅 맞딜 (요청 8 그대로): 목표 자리(front 보스 앞 140 / back 등 뒤 140 / inside 보스 x)에 서서 씨앗 베기(쿨마다)·약공격만 누른다.
##   plunge_air  공중 연속 낙하: 점프 → 낙하 공격만 거듭한다 (튕기면 다시 내려꽂기).
##   plunge_land 착지 낙하: 점프 → 낙하 공격 한 번 → 착지 → 다시 (바닥을 디디며 낙하 감쇠를 풀던 길).
##   plunge_mix  낙하 + 씨앗 베기: 바닥에서 베기가 준비됐으면 베고, 아니면 점프 → 낙하 한 번 → 착지.
##   wind/light  stand 와 같은데 영혼이 바람/빛 (그 능력이 있는 보스만 — 바람은 펌프부터, 빛은 여왕부터).
##   platform    가지 위 진치기: 싸움터의 가장 높은 한쪽 방향 가지 위에서 보스 쪽으로 걷고, 쿨이 끝난 원거리 영혼(빛·바람, 바꾸기는 공짜)을
##               쏘고, 닿으면 씨앗 베기, 보스가 바로 아래면 내려가며 낙하 공격 (4.1초마다). 떨어지면 0.6초 뒤 다시 올라간다 (점프+이단 점프 대신 순간이동).
##   rolltank    맞딜 + 구르기 끊기: 공격·베기 되돌림마다 보스 몸을 뚫고 굴러 끊고 돌아선다 (목표 자리에서 450 넘게 멀어지면 순간이동).
##   airmix      공중 맞딜: 제자리에서 점프·이단 점프로 떠 있으며 베기(준비되면)·낙하(앞 낙하가 맞은 지 4.1초 넘으면 — 감쇠를 피함)·공중 약공격.
##   airslash    airmix 에서 낙하만 뺀 것.
##   plunge4     땅 약공격·씨앗 베기 + 4.1초마다 한 번 낙하 공격 (낙하 감쇠 창을 비켜 가는 박자).
##   range       보스에게서 520 떨어져 원거리 영혼을 돌려 쏜다 (330 안이면 베기, 300 안이면 약공격; 구석에 몰리면 반대편으로 순간이동).
##   range_air   range 와 같은데 뛰어오른 꼭대기에서 쏜다.
##   hitrun      박자 없이 드나들기: 목표 자리로 들어가 1.3초 몰아치기(베기 > 4.1초 낙하 > 약공격 둘) → 굴러 빠져 520 에서 2초 원거리 → 반복.
##   punish_roll 380 앞에서 기다리다 보스가 되돌림·무너짐·쉼이면 굴러 들어가 때리고, 새 예비동작이면 굴러 나온다.
##   soulcycle   영혼 돌려 쓰기 (마지막 검수의 새 봇): stand 처럼 목표 자리에 서서 맞으며, 쿨이 끝난 영혼 기술을 모두 준비되는 대로 쓴다
##               (씨앗 베기 > 바람·빛 — 바꾸기는 공짜·즉시, 영혼마다 쿨다운이 따로) + 그 사이 약공격.
##   soulrun     soulcycle 을 순간이동 없이: 목표 자리에서 250 넘게 멀면 달려가고(막히면 뛴다), 달리는 동안에도 보스 쪽을 보고 있으면
##               원거리 영혼(빛·바람)을 쿨마다 쏜다. 250 안이면 soulcycle 과 같다.
## 목표 자리가 있는 방식: stand·plunge_*·wind·light·rolltank·airmix·airslash·plunge4·hitrun·soulcycle·soulrun (front/back/inside). 없는 방식: platform·range·range_air·punish_roll.
## 성장: 그 보스를 만날 즈음의 예상치 (명세 3.8 표 — Progress.upgrades 를 직접 정한다).
##
## 합격 (오케스트레이터 결정, Normal 만, 기본 씨드 1–6 × 자리):
##   stand·soulcycle: 어느 보스도 봇이 한 판도 못 이긴다 (300초를 버텨도 FAIL — 보스 화력 부족).
##   그 밖의 방식: 보스·방식마다 봇이 이긴 판이 1판 이하, 이긴 판도 봇 체력이 50% 넘게 남으면 안 된다 (300초 무승부는 이긴 것이 아님).
## --quick (전체 회귀용, 8분 아래 — 지금 약 1분 30초): stand 다섯 보스(front·inside × 씨드 1) + 위험했던 보스의 방식 몇 가지 (QUICK_PLAN, 36판 —
##   영혼 돌려 쓰기 여왕·뿌리지기 포함).
##   합격 규칙은 같다 (칸마다 2판 — 공중 맞딜 새 안쪽 씨드 1 은 전체 시험의 단 하나 봇 승(봇 체력 5%)이라 1/2 로 나온다).
## --diff easy 등: 결과만 출력 (합격 판정은 Normal 만).
## --good: '잘하는 사람' 봇 (전체 회귀에는 없음 — 보스를 고친 뒤 돌린다): 죽지 않게(매 틱 체력을 채움) 두고 패턴을 피한다 — 보스의 공격 범위 예고(RangeTelegraph)
##   안에 있으면 빠져나오고(달려 나갈 시간이 모자라면 가드 가능한 것은 저스트 가드, 가드 불가는 구르기), 다가오는 투사체는 저스트 가드(되받을 수 있는 것은 되받음),
##   그 밖엔 다가가 약공격 3타·씨앗 베기·원거리 영혼(맞을 만할 때만 — _ranged_can_hit)·6초마다 낙하 공격, 하늘의 보스가 닿을 만하면 뛰어올라(이단 점프) 벤다.
##   보스를 쓰러뜨리는 시간(초)을 씨드마다 재고 1985add 기준값(GOOD_BASELINE)과 견준다 (합격 기준: 어느 보스도 +20% 안).
##   --good-roll-cost 0 처럼 구르기 비용을 바꿔 볼 수 있다.

const TIME_LIMIT := 300.0
const SPOT_DIST := 140.0
const MOVE_TOL := 60.0
const MOVE_EVERY := 0.25
const HEAL_BELOW := 0.4
## 낙하 감쇠 창(PlungeDecay.WINDOW 4초)을 비켜 가는 봇의 낙하 간격
const PLUNGE_GAP := 4.1
const RANGE_DIST := 520.0

## 보스별 성장 프로필 (명세 3.8). tok = [normal, seed, wind, light, stamina]
const PROFILES := [
	{"id": "bird", "room": "canopy_boss", "max_hp": 25.0, "attack": 0.05, "heal": 10.0, "dews": 0.0, "tok": [1, 0, 0, 0, 0], "ab": []},
	{"id": "pump", "room": "flooded_mine_boss", "max_hp": 35.0, "attack": 0.10, "heal": 10.0, "dews": 1.0, "tok": [1, 1, 0, 0, 1], "ab": ["double_jump", "wind"]},
	{"id": "knight", "room": "mine_boss", "max_hp": 55.0, "attack": 0.15, "heal": 20.0, "dews": 1.0, "tok": [1, 1, 1, 0, 1], "ab": ["double_jump", "wind", "wall_break"]},
	{"id": "queen", "room": "sap_lake_boss", "max_hp": 85.0, "attack": 0.25, "heal": 30.0, "dews": 2.0, "tok": [2, 1, 1, 1, 2], "ab": ["double_jump", "wind", "wall_break", "light", "lantern"]},
	{"id": "root", "room": "abyss_boss", "max_hp": 110.0, "attack": 0.35, "heal": 40.0, "dews": 2.0, "tok": [2, 2, 1, 1, 2], "ab": ["double_jump", "wind", "wall_break", "light", "lantern", "sap_walk", "sap_pulse"]},
]
const TRACKS := ["normal", "seed", "wind", "light", "stamina"]
const MODES := ["stand", "plunge_air", "plunge_land", "plunge_mix", "wind", "light", "platform", "rolltank", "airmix", "airslash",
	"plunge4", "range", "range_air", "hitrun", "punish_roll", "soulcycle", "soulrun"]
const MODE_NAMES := {"stand": "땅 맞딜", "plunge_air": "공중 연속 낙하", "plunge_land": "착지 낙하", "plunge_mix": "낙하+씨앗 베기",
	"wind": "바람 영혼", "light": "빛 영혼", "platform": "가지 진치기", "rolltank": "맞딜+구르기 끊기", "airmix": "공중 맞딜",
	"airslash": "공중 베기", "plunge4": "4.1초 낙하", "range": "원거리", "range_air": "공중 원거리", "hitrun": "드나들기", "punish_roll": "빈틈 구르기",
	"soulcycle": "영혼 돌려 쓰기", "soulrun": "달리며 영혼"}
## 옛 이름 (--mode ground,plunge 도 그대로 받는다)
const MODE_ALIASES := {"ground": "stand", "plunge": "plunge_air", "rolltank2": "rolltank"}
const PLUNGE_MODES := ["plunge_air", "plunge_land", "plunge_mix"]
## 땅 맞딜 줄: 한 판도 이기면 안 되는 방식 (무승부도 FAIL)
const ZERO_WIN_MODES := ["stand", "soulcycle"]
## 목표 자리가 없는 방식
const SPOTLESS := ["platform", "range", "range_air", "punish_roll"]
const ALL_SPOTS := ["front", "back", "inside"]
## --quick 계획: [방식, 보스들, 자리들, 씨드들]. stand 는 다섯 보스, 나머지는 최종 검수들이 봇 승을 찾았던 보스.
const QUICK_PLAN := [
	["stand", ["bird", "pump", "knight", "queen", "root"], ["front", "inside"], [1]],
	["plunge_land", ["pump", "root"], ["front", "inside"], [1]],
	["plunge_mix", ["pump", "root"], ["front", "inside"], [1]],
	["rolltank", ["pump"], ["front", "inside"], [1]],
	["airmix", ["pump", "bird", "queen"], ["front", "inside"], [1]],
	["plunge4", ["pump"], ["front", "inside"], [1]],
	["platform", ["queen", "root"], ["-"], [1, 2]],
	["soulcycle", ["queen", "root"], ["front", "inside"], [1]],
]
## '잘하는 봇'의 1985add(맞딜 마무리 검수 앞) 기준 잡는 시간 (초, 씨드 1–4 평균, Normal; --good 이 % 차이를 출력한다).
## 잘하는 봇 코드를 바꾸면 1985add 에서 다시 재야 한다 (이 파일을 그 판에 넣고 --good).
## 영혼 함께 잠김 검수(2026-10-26): 원거리 영혼을 맞을 만할 때만 쏘게 바꾼 뒤 1985add 사본에서 다시 쟀다 — 새·펌프·기사·뿌리지기는 그대로,
## 여왕만 75.8 → 82.0 (하늘에 뜬 여왕에게 가로로 쏘던 바람·빛을 안 쏜다).
const GOOD_BASELINE := {"bird": 61.5, "pump": 45.8, "knight": 37.9, "queen": 82.0, "root": 51.0}

var _fail := 0
var _diff := "normal"
var _accel := 1
var _strict_face := true
var _trace := false
var _roll_cost := -1.0
var _soul_lock := -1.0
var _boss_set := {}
var _player_set := {}
var _results: Array = []
## 판마다의 봇 상태
var _b := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var quick := "--quick" in args
	_trace = "--trace" in args
	_strict_face = not ("--no-strict-face" in args)
	# --fixed-fps 로 도는가: 물리 30틱이 실제 시간 0.25초보다 빨리 지나가면 그렇다 (엔진 인자는 get_cmdline_args 에 남지 않는다)
	var t_us := Time.get_ticks_usec()
	await _frames(30)
	var fast := (Time.get_ticks_usec() - t_us) < 250000
	if not fast:
		# 실시간 실행: 빠른 판으로 줄이고 물리를 ACCEL 배로 돌린다 (한 틱은 그대로 1/60초)
		quick = quick or not ("--full" in args)
		_accel = 6
		Engine.physics_ticks_per_second = 60 * _accel
		Engine.max_physics_steps_per_frame = 8 * _accel
	_diff = _arg(args, "--diff", "normal")
	var rc := _arg(args, "--roll-cost", "")
	if rc != "":
		_roll_cost = float(rc)
	var sl := _arg(args, "--soul-lock", "")
	if sl != "":
		_soul_lock = float(sl)
	for kv in _arg(args, "--boss-set", "").split(",", false):
		var p := kv.split("=")
		if p.size() == 2:
			_boss_set[p[0]] = float(p[1])
	for kv in _arg(args, "--player-set", "").split(",", false):
		var p := kv.split("=")
		if p.size() == 2:
			_player_set[p[0]] = float(p[1])
	var only: Array = []
	if _arg(args, "--only", "") != "":
		only = Array(_arg(args, "--only", "").split(","))
	Settings.data["screen_shake"] = false
	if "--good" in args:
		await _good_all(args, only)
		print("[probe] 끝: 실패 %d" % _fail)
		get_tree().quit(1 if _fail > 0 else 0)
		return
	var modes: Array = MODES.duplicate()
	var mode_arg := _arg(args, "--mode", "all")
	if mode_arg != "all":
		modes = []
		for m in mode_arg.split(","):
			modes.append(MODE_ALIASES.get(m, m))
	for m in modes:
		if not m in MODES:
			_check(false, "모르는 방식 %s (%s)" % [m, MODES])
			get_tree().quit(1)
			return
	var seeds: Array = [1] if quick else [1, 2, 3, 4, 5, 6]
	if _arg(args, "--seeds", "") != "":
		seeds = _parse_seeds(_arg(args, "--seeds", ""))
	var spots_arg := _arg(args, "--spots", "")
	# 계획: [방식, 보스 프로필, 자리, 씨드]
	var plan: Array = []
	if quick and mode_arg == "all":
		for q in QUICK_PLAN:
			for prof in PROFILES:
				if not prof["id"] in q[1] or (not only.is_empty() and not prof["id"] in only):
					continue
				for spot in q[2]:
					for sd in (seeds if _arg(args, "--seeds", "") != "" else q[3]):
						plan.append([q[0], prof, spot, sd])
	else:
		for mode in modes:
			for prof in PROFILES:
				if not only.is_empty() and not prof["id"] in only:
					continue
				if (mode == "wind" or mode == "light") and not mode in prof["ab"]:
					continue   # 그 영혼을 아직 못 얻은 보스
				var spots: Array = ["-"] if mode in SPOTLESS else (["front", "inside"] if quick else ALL_SPOTS)
				if spots_arg != "" and not mode in SPOTLESS:
					spots = Array(spots_arg.split(","))
				for spot in spots:
					for sd in seeds:
						plan.append([mode, prof, spot, sd])
	print("[probe] 맞딜 시험 시작 (난이도 %s, %s, %d판, 물리 %d틱/초 × 시간 %d배, 돌아서기 %s, 구르기 비용 %s, 영혼 함께 잠김 %s)" % [_diff, "빠른 판" if quick else "전체",
		plan.size(), Engine.physics_ticks_per_second, _accel, "사람처럼" if _strict_face else "자유", "기본" if _roll_cost < 0.0 else str(_roll_cost),
		"기본" if _soul_lock < 0.0 else str(_soul_lock)])
	if not _boss_set.is_empty() or not _player_set.is_empty():
		print("[probe] 값 바꿈: 보스 %s, 소녀 %s" % [_boss_set, _player_set])
	if "--list" in args:
		for p in plan:
			print("[probe]   %s %s %s %d" % [p[0], p[1]["id"], p[2], p[3]])
		get_tree().quit(0)
		return
	var t_wall := Time.get_ticks_msec()
	for p in plan:
		await _run(p[1], p[2], p[3], p[0])
	_summary()
	print("[probe] 걸린 시간 %.0f초 (벽시계)" % ((Time.get_ticks_msec() - t_wall) / 1000.0))
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _arg(args: PackedStringArray, key: String, def: String) -> String:
	var i := args.find(key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def


## "6" → 1..6, "1,3" → [1, 3], "2-4" → [2, 3, 4], "5," → [5]
func _parse_seeds(s: String) -> Array:
	var out: Array = []
	if s.contains(","):
		for v in s.split(",", false):
			out.append(int(v))
	elif s.contains("-"):
		var ab := s.split("-")
		for v in range(int(ab[0]), int(ab[1]) + 1):
			out.append(v)
	else:
		for v in range(1, int(s) + 1):
			out.append(v)
	return out


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


const ACTIONS := ["attack_light", "soul_ability", "heal", "guard", "dodge", "jump", "move_left", "move_right", "move_down", "move_up",
	"interact", "plunge", "soul_next", "soul_prev"]


func _release_all(keep: Array = []) -> void:
	for a in ACTIONS:
		if InputMap.has_action(a) and not a in keep:
			Input.action_release(a)


## 방을 읽고 싸움을 건다. [room, player, boss] (실패하면 빈 배열)
func _open_room(prof: Dictionary, mode: String) -> Array:
	_setup_progress(prof, mode)
	_release_all()
	Engine.time_scale = float(_accel)
	var room: Node = load("res://scenes/rooms/%s.tscn" % prof["room"]).instantiate()
	add_child(room)
	await _frames(6)
	var player := get_tree().get_first_node_in_group("player") as Player
	var boss := room.get_node("Boss") as Node2D
	if _roll_cost >= 0.0:
		player.roll_stamina_cost = _roll_cost
	if _soul_lock >= 0.0:
		player.soul_shared_lockout = _soul_lock
	for k in _boss_set:
		if k in boss:
			boss.set(k, _boss_set[k])
	for k in _player_set:
		if k in player:
			player.set(k, _player_set[k])
	var arena: Rect2 = boss.arena
	player.global_position = Vector2(arena.get_center().x - 300.0, float(boss.ground_y) - 80.0)
	player.velocity = Vector2.ZERO
	await _frames(3)
	if not room.fight_started:
		room._on_trigger(player)
	Music.stop(0.0)   # 여왕 박자 시계는 실제 시간으로 (빠르게 돌리는 시험에서 음악 재생 위치에 묶이지 않게)
	return [room, player, boss]


func _close_room(room: Node) -> void:
	_release_all()
	room.queue_free()
	await _frames(3)
	Fx.clear()
	Engine.time_scale = 1.0


## 한 판: 봇이 쓰러지거나(통과) 보스가 쓰러지거나(봇 승) 300초가 지날 때(무승부)까지.
func _run(prof: Dictionary, spot: String, sd: int, mode: String) -> void:
	seed(9100 + sd * 7 + PROFILES.find(prof) * 31 + (ALL_SPOTS + ["-"]).find(spot) * 3 + MODES.find(mode) * 101)
	_b = {"jump_hold": 0, "phase": "in", "phase_t": 0.0, "last_plunge_hit": -99.0, "plunged_air": false, "off_t": 0.0,
		"burst_hits": 0, "dropping": false, "roll_side": 1, "teleports": 0, "now": 0.0, "stuck_t": 0.0}
	var opened: Array = await _open_room(prof, mode)
	var room: Node = opened[0]
	var player: Player = opened[1]
	var boss: Node2D = opened[2]
	var gy: float = boss.ground_y
	var arena: Rect2 = boss.arena
	_b["plat"] = _highest_branch(room, arena)
	var dmg_taken := [0.0]
	var hits := [0]
	player.hit_taken.connect(func(d: float) -> void:
		dmg_taken[0] += d
		hits[0] += 1
		if _trace:
			print("[hit] t=%.1f 피해 %.0f ← %s/%s, 소녀 dx %.0f 높이 %.0f 상태 %s" % [_b["now"], d, boss.state_name(), str(boss.get("attack_phase")),
				player.global_position.x - boss.global_position.x, gy - player.global_position.y, Player.State.keys()[player.state]]))
	var breaks := [0]
	if boss.has_signal("state_changed"):
		boss.state_changed.connect(func(_a = null) -> void:
			if boss.state_name() == "BROKEN":
				breaks[0] += 1
			if _trace:
				print("[boss] t=%.1f → %s (체력 %.0f)" % [_b["now"], boss.state_name(), float(boss.hp)]))
	# 보스에게 준 피해를 소녀 상태별로 (낙하 / 씨앗 베기 / 원거리 / 약공격) — 어느 길이 이기는지 보려고
	var dealt := {"plunge": 0.0, "slash": 0.0, "ranged": 0.0, "light": 0.0}
	var bhp_prev := [float(boss.hp)]
	boss.hp_changed.connect(func(h: float, _m: float) -> void:
		if h < bhp_prev[0] and is_instance_valid(player):
			var k := "ranged"
			if player.state == Player.State.PLUNGE:
				k = "plunge"
			elif player.state == Player.State.SOUL_SLASH:
				k = "slash"
			elif player.state == Player.State.ATTACK:
				k = "light"
			dealt[k] += bhp_prev[0] - h
		bhp_prev[0] = h)
	player.plunge_landed.connect(func() -> void: _b["last_plunge_hit"] = _b["now"])
	var heals := [0]
	player.healed.connect(func() -> void: heals[0] += 1)
	var dt := float(_accel) / float(Engine.physics_ticks_per_second)
	var t := 0.0
	var move_t := 0.0
	var tick := 0
	var result := "draw"
	while t < TIME_LIMIT:
		await get_tree().physics_frame
		# 이 틱에 흐른 게임 시간 (히트스톱 동안은 거의 흐르지 않는다)
		var gdt := Engine.time_scale / float(Engine.physics_ticks_per_second)
		if _accel > 1 and Engine.time_scale != float(_accel):
			Engine.time_scale = float(_accel)
		if _accel > 1 and boss is SapQueen:
			boss._clock += dt * (1.0 - 1.0 / float(_accel))
		t += gdt
		_b["now"] = t
		tick += 1
		if not is_instance_valid(player) or not is_instance_valid(boss):
			result = "gone"
			break
		if player.state == Player.State.DEAD:
			result = "died"
			break
		if boss.state_name() in ["FALLEN", "PURIFIED"]:
			result = "won"
			break
		_b["phase_t"] += gdt
		move_t += gdt
		var do_move := false
		if move_t >= MOVE_EVERY:
			move_t = 0.0
			do_move = true
		_release_all()
		_bot(mode, spot, player, boss, arena, gy, do_move, tick, gdt)
		if _trace and tick % 60 == 0:
			var pm = boss.get("perch")
			var cm = boss.get("crowd")
			print("[dbg] t=%.1f hp=%.0f st=%.0f dews=%d %s boss=%s bhp=%.0f dx=%.0f 높이 %.0f 계량기 붙음 %s 높음 %s" % [t, player.hp, player.guard, player.dews,
				Player.State.keys()[player.state], boss.state_name(), boss.hp, player.global_position.x - boss.global_position.x, gy - player.global_position.y,
				("%.1f" % cm.t) if cm else "-", ("%.1f" % pm.t) if pm else "-"])
	var boss_pct := 100.0 * float(boss.hp) / maxf(float(boss.max_hp), 1.0) if is_instance_valid(boss) else -1.0
	var bot_pct := 100.0 * player.hp / maxf(player.max_hp, 1.0) if is_instance_valid(player) else 0.0
	var dsum := maxf(dealt["plunge"] + dealt["slash"] + dealt["ranged"] + dealt["light"], 1.0)
	var row := {"mode": mode, "boss": prof["id"], "spot": spot, "seed": sd, "result": result, "t": t, "boss_pct": boss_pct, "bot_pct": bot_pct,
		"dmg": dmg_taken[0], "hits": hits[0], "breaks": breaks[0]}
	_results.append(row)
	var line := "%s %s %s seed %d: %s %.1f초 — 보스 체력 %.0f%%, 봇 체력 %.0f%% (받은 피해 %.0f, %d대, 회복 %d), 보스 무너짐 %d번, 준 피해 낙하 %.0f%%·베기 %.0f%%·원거리 %.0f%%·약공격 %.0f%%, 순간이동 %d" % [
		mode, prof["id"], spot, sd, {"died": "봇이 쓰러짐", "won": "봇이 이김", "draw": "300초 무승부", "gone": "사라짐"}[result], t, boss_pct, bot_pct,
		dmg_taken[0], hits[0], heals[0], breaks[0], 100.0 * dealt["plunge"] / dsum, 100.0 * dealt["slash"] / dsum, 100.0 * dealt["ranged"] / dsum,
		100.0 * dealt["light"] / dsum, _b["teleports"]]
	print("[probe] %s %s" % ["봇승" if result == "won" else ("무승부" if result != "died" else "  ok"), line])
	await _close_room(room)


## 싸움터 안에서 가장 높은 한쪽 방향 가지 (platform 봇의 진지)
func _highest_branch(room: Node, arena: Rect2) -> Platform:
	var plat: Platform = null
	var stack: Array = [room]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		stack.append_array(cur.get_children())
		if cur is Platform and (cur as Platform).one_way:
			var p := cur as Platform
			var c := p.global_position + p.size * 0.5
			if c.x > arena.position.x and c.x < arena.end.x and (plat == null or p.global_position.y < plat.global_position.y):
				plat = p
	return plat


# ---------------- 도우미 ----------------

## 목표 x 의 바닥으로 옮긴다 (아래로 선을 쏘아 지형 윗면을 찾는다; 한쪽 방향 가지는 건너뛴다; 못 찾으면 보스 바닥선)
func _teleport(player: Player, x: float, gy: float) -> void:
	var space := player.get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(Vector2(x, gy - 420.0), Vector2(x, gy + 600.0), 1)
	ray.exclude = [player.get_rid()]
	var y := gy
	var hit := space.intersect_ray(ray)
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
	_b["teleports"] += 1


func _teleport_onto_plat(player: Player, plat: Platform, x: float) -> void:
	var lx := clampf(x, plat.global_position.x + 30.0, plat.global_position.x + plat.size.x - 30.0)
	player.global_position = Vector2(lx, plat.global_position.y - BossRush.FOOT_OFFSET)
	player.velocity = Vector2.ZERO
	_b["teleports"] += 1


## 보스 쪽을 본다. 사람처럼: 이동 상태(서기·걷기·달리기·점프·낙하)에서만 돌아선다.
func _face_boss(player: Player, boss: Node2D) -> void:
	if _strict_face and not (player.state in Player.LOCOMOTION):
		return
	var dx := boss.global_position.x - player.global_position.x
	if absf(dx) > 4.0:
		player.facing = 1 if dx > 0.0 else -1
	else:
		player.facing = -int(boss.get("facing"))   # 몸 한가운데: 보스가 보는 쪽을 마주 본다


func _spot_x(boss: Node2D, spot: String, arena: Rect2) -> float:
	var f := float(boss.get("facing")) if boss.get("facing") != null else 1.0
	var x := boss.global_position.x
	match spot:
		"front":
			x += f * SPOT_DIST
		"back":
			x -= f * SPOT_DIST
	return clampf(x, arena.position.x + 40.0, arena.end.x - 40.0)


func _owned_ranged(player: Player) -> Array:
	var out := []
	for s in ["light", "wind"]:
		if s in player.owned_souls():
			out.append(s)
	return out


func _can_act(player: Player) -> bool:
	return player.state in Player.LOCOMOTION or (player.state == Player.State.ATTACK and player.attack_phase == "recovery")


## 쿨이 끝난 원거리 영혼을 쏜다 (먼저 그 영혼으로 바꾼다 — 바꾸기는 공짜). 눌렀으면 true.
## aim_at 을 주면 맞을 만할 때만 쏜다 (_ranged_can_hit — 잘하는 봇).
func _try_ranged(player: Player, aim_at: Node2D = null) -> bool:
	if not _can_act(player):
		return false
	for s in _owned_ranged(player):
		if aim_at != null and not _ranged_can_hit(player, aim_at, s):
			continue
		if player.soul_cooldown_left(s) <= 0.0:
			if player.soul != s:
				player.soul = s
				Progress.soul = s
			Input.action_press("soul_ability")
			return true
	return false


## 원거리 영혼이 맞을 만한가: 보고 있는 쪽이고, 보스 맞는 영역(사각형)이 쏘는 줄(소녀 가슴 높이 ± 판정 높이의 절반)과 겹치며 사거리 안이다.
## 잘하는 사람은 하늘 높이 뜬 보스에게 가로로 나가는 빛줄기·초승달을 쏘지 않는다 (v1.1.0 맞딜 검수: 영혼 기술 함께 잠김이 생긴 뒤로는
## 헛쏜 한 발이 1.5초 동안 씨앗 베기를 막는다 — 예전 잘하는 봇은 하늘의 여왕에게 쏜 바람·빛 40여 발이 거의 다 빗나갔다).
func _ranged_can_hit(player: Player, boss: Node2D, s: String) -> bool:
	var r := _hurt_rect(boss)
	if r.size == Vector2.ZERO:
		return true
	var me := player.global_position
	var cx := r.get_center().x
	if absf(cx - me.x) > 30.0 and signf(cx - me.x) != float(player.facing):
		return false
	var y := me.y - 20.0
	var half := (player.gust_size.y if s == "wind" else player.light_shot_size.y) * 0.9 * 0.5
	if r.end.y < y - half or r.position.y > y + half:
		return false
	var reach := player.gust_speed * player.gust_range_time + 100.0 if s == "wind" else player.light_beam_range()
	var near := r.position.x - me.x if player.facing > 0 else me.x - r.end.x
	return near <= reach


## 보스 맞는 영역(Hurtbox 의 모양들)을 세상 좌표 사각형 하나로 (없으면 빈 사각형)
func _hurt_rect(boss: Node2D) -> Rect2:
	var out := Rect2()
	var first := true
	var stack: Array = [boss]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is CollisionShape2D and n.get_parent() is Hurtbox and n.shape != null and not n.disabled:
			var gr: Rect2 = n.global_transform * (n.shape as Shape2D).get_rect()
			out = gr if first else out.merge(gr)
			first = false
	return out


func _try_slash(player: Player) -> bool:
	if not _can_act(player):
		return false
	if player.soul_cooldown_left("seed") <= 0.0:
		if player.soul != "seed":
			player.soul = "seed"
			Progress.soul = "seed"
		Input.action_press("soul_ability")
		return true
	return false


func _need_heal(player: Player) -> bool:
	return player.hp < player.max_hp * HEAL_BELOW and player.dews > 0 and player.is_on_floor()


func _boss_recovering(boss: Node2D) -> bool:
	var sn: String = boss.state_name()
	if sn in ["BROKEN", "STAGGER", "STUCK", "EAT", "GROUND_IDLE", "CRACK"]:
		return true
	return str(boss.get("attack_phase")) == "recovery"


func _jump_logic(player: Player, on_floor: bool) -> void:
	if _b["jump_hold"] > 0 and not on_floor and player.velocity.y < 0.0:
		Input.action_press("jump")
		_b["jump_hold"] -= 1


func _press_light(player: Player) -> void:
	var next_step := (player.attack_step % 3) + 1 if player.state == Player.State.ATTACK else 1
	if player.guard >= player.light_cost_of(next_step):
		Input.action_press("attack_light")


# ---------------- 봇 ----------------

func _bot(mode: String, spot: String, player: Player, boss: Node2D, arena: Rect2, gy: float, do_move: bool, tick: int, gdt: float) -> void:
	var on_floor := player.is_on_floor()
	var dx := player.global_position.x - boss.global_position.x
	if on_floor and player.state != Player.State.PLUNGE:
		_b["plunged_air"] = false
	if player.state == Player.State.PLUNGE:
		_b["plunged_air"] = true
	match mode:
		"stand", "wind", "light", "plunge_air", "plunge_land", "plunge_mix":
			_bot_classic(mode, spot, player, boss, arena, gy, do_move, tick, on_floor)
		"range", "range_air":
			if do_move:
				var side := signf(dx)
				if side == 0.0:
					side = -float(boss.get("facing"))
				var tx := clampf(boss.global_position.x + side * RANGE_DIST, arena.position.x + 40.0, arena.end.x - 40.0)
				if absf(tx - boss.global_position.x) < 330.0:
					side = -side
					tx = clampf(boss.global_position.x + side * RANGE_DIST, arena.position.x + 40.0, arena.end.x - 40.0)
				if absf(player.global_position.x - tx) > MOVE_TOL and (on_floor or mode == "range"):
					_teleport(player, tx, gy)
				_face_boss(player, boss)
			if tick % 2 == 1:
				return
			if _need_heal(player):
				Input.action_press("heal")
				return
			if mode == "range_air":
				if on_floor and player.state in Player.LOCOMOTION:
					Input.action_press("jump")
					_b["jump_hold"] = 30
					return
				_jump_logic(player, on_floor)
				if not on_floor and player.velocity.y > -120.0:
					_face_boss(player, boss)
					_try_ranged(player)
				return
			if absf(dx) <= 330.0 and _try_slash(player):
				return
			_face_boss(player, boss)
			if _try_ranged(player):
				return
			if absf(dx) <= 300.0 and player.state in Player.LOCOMOTION:
				Input.action_press("attack_light")
		"platform":
			var plat: Platform = _b["plat"]
			if plat == null:
				return
			var top := plat.global_position.y
			var on_plat := on_floor and absf(player.global_position.y + BossRush.FOOT_OFFSET - top) < 12.0 \
				and player.global_position.x > plat.global_position.x and player.global_position.x < plat.global_position.x + plat.size.x
			if on_floor and not on_plat and player.state in Player.LOCOMOTION:
				_b["off_t"] += gdt
				if _b["off_t"] >= 0.6:
					_b["off_t"] = 0.0
					_b["dropping"] = false
					_teleport_onto_plat(player, plat, boss.global_position.x)
			else:
				_b["off_t"] = 0.0
			if do_move and on_plat:
				# 가지 위에서 보스 쪽으로 걷는다 (가지를 벗어나지 않게)
				var want := clampf(boss.global_position.x, plat.global_position.x + 30.0, plat.global_position.x + plat.size.x - 30.0)
				if absf(player.global_position.x - want) > 40.0 and player.state in Player.LOCOMOTION:
					_teleport_onto_plat(player, plat, want)
				_face_boss(player, boss)
			if tick % 2 == 1:
				return
			if _need_heal(player):
				Input.action_press("heal")
				return
			if on_plat and absf(dx) < 170.0 and boss.global_position.y > player.global_position.y + 150.0 and player.state in Player.LOCOMOTION \
					and _b["now"] - _b["last_plunge_hit"] >= PLUNGE_GAP:
				Input.action_press("move_down")
				Input.action_press("jump")
				_b["dropping"] = true
				return
			if _b["dropping"] and not on_floor and player.state in Player.LOCOMOTION:
				Input.action_press("plunge")
				_b["dropping"] = false
				return
			if absf(dx) <= 330.0 and absf(player.global_position.y - boss.global_position.y) < 260.0 and _try_slash(player):
				return
			_face_boss(player, boss)
			_try_ranged(player)
		"hitrun":
			# 들어가 1.3초 몰아치기 → 굴러 빠져 520 에서 2초 원거리 → 반복
			if _b["phase"] == "in":
				if do_move and on_floor and player.state in Player.LOCOMOTION and absf(player.global_position.x - _spot_x(boss, spot, arena)) > MOVE_TOL:
					_teleport(player, _spot_x(boss, spot, arena), gy)
				if do_move:
					_face_boss(player, boss)
				if tick % 2 == 1:
					return
				if _need_heal(player):
					Input.action_press("heal")
					return
				var timeout: bool = _b["phase_t"] > 1.3
				var acted := false
				if not timeout:
					if _try_slash(player):
						acted = true
					elif _b["now"] - _b["last_plunge_hit"] >= PLUNGE_GAP and not _b["plunged_air"]:
						if on_floor and player.state in Player.LOCOMOTION:
							Input.action_press("jump")
							_b["jump_hold"] = 30
						elif not on_floor and player.state in Player.LOCOMOTION and player.velocity.y > -150.0:
							Input.action_press("plunge")
						_jump_logic(player, on_floor)
						acted = true
					elif on_floor and player.state in Player.LOCOMOTION and _b["burst_hits"] < 2:
						Input.action_press("attack_light")
						_b["burst_hits"] += 1
						acted = true
					elif player.state == Player.State.ATTACK and player.attack_phase != "recovery":
						acted = true
				if (timeout or not acted) and on_floor and (player.state in Player.LOCOMOTION or (player.state in [Player.State.ATTACK, Player.State.SOUL_SLASH] and player.attack_phase == "recovery")):
					if player.state in Player.LOCOMOTION or not _strict_face:
						player.facing = 1 if dx >= 0.0 else -1
						if absf(dx) < 4.0:
							player.facing = 1
					Input.action_press("dodge")
					_b["phase"] = "out"
					_b["phase_t"] = 0.0
			else:
				if do_move and player.state != Player.State.ROLL and _b["phase_t"] > 0.35:
					var side := signf(dx)
					if side == 0.0:
						side = 1.0
					var tx := clampf(boss.global_position.x + side * RANGE_DIST, arena.position.x + 40.0, arena.end.x - 40.0)
					if absf(tx - boss.global_position.x) < 330.0:
						side = -side
						tx = clampf(boss.global_position.x + side * RANGE_DIST, arena.position.x + 40.0, arena.end.x - 40.0)
					if absf(player.global_position.x - tx) > MOVE_TOL and on_floor:
						_teleport(player, tx, gy)
					_face_boss(player, boss)
				if tick % 2 == 1:
					return
				if _need_heal(player):
					Input.action_press("heal")
					return
				if _b["phase_t"] > 0.35:
					_try_ranged(player)
				if _b["phase_t"] >= 2.0 and player.state in Player.LOCOMOTION:
					_b["phase"] = "in"
					_b["phase_t"] = 0.0
					_b["burst_hits"] = 0
		"rolltank":
			if do_move and player.state != Player.State.ROLL:
				var tx := _spot_x(boss, spot, arena)
				if absf(player.global_position.x - tx) > 450.0:
					_teleport(player, tx, gy)
				_face_boss(player, boss)
			if tick % 2 == 1:
				return
			if _need_heal(player):
				Input.action_press("heal")
				return
			var recov := player.state in [Player.State.ATTACK, Player.State.SOUL_SLASH] and player.attack_phase == "recovery"
			if recov:
				# 되돌림을 구르기로 끊는다 (보고 있는 쪽 = 보스 쪽으로 굴러 몸을 뚫고 지나간다)
				if not _strict_face:
					var sx := _spot_x(boss, spot, arena)
					var off := sx - player.global_position.x
					if absf(off) > 60.0:
						player.facing = 1 if off > 0.0 else -1
					else:
						_b["roll_side"] = -_b["roll_side"]
						player.facing = _b["roll_side"]
				Input.action_press("dodge")
				return
			if player.state == Player.State.ROLL:
				return
			_face_boss(player, boss)
			if _try_slash(player):
				return
			if player.state in Player.LOCOMOTION:
				if player.guard >= player.light_cost_of(1):
					Input.action_press("attack_light")
				elif on_floor:
					player.facing = -1 if dx > 0.0 else 1
					Input.action_press("dodge")
		"airmix", "airslash":
			if do_move and on_floor and player.state in Player.LOCOMOTION:
				var tx := _spot_x(boss, spot, arena)
				if absf(player.global_position.x - tx) > MOVE_TOL:
					_teleport(player, tx, gy)
			if do_move:
				_face_boss(player, boss)
			if tick % 2 == 1:
				return
			if _need_heal(player):
				Input.action_press("heal")
				return
			if on_floor and player.state in Player.LOCOMOTION:
				Input.action_press("jump")
				_b["jump_hold"] = 30
				return
			_jump_logic(player, on_floor)
			if not on_floor:
				if player.soul_cooldown_left("seed") <= 0.0 and _try_slash(player):
					return
				if mode == "airmix" and _b["now"] - _b["last_plunge_hit"] >= PLUNGE_GAP and player.state in Player.LOCOMOTION \
						and player.velocity.y > -150.0 and not _b["plunged_air"]:
					Input.action_press("plunge")
					return
				# 꼭대기에서 이단 점프로 떠 있는다
				if player.velocity.y > 0.0 and player._jumps_left > 0 and player.state in Player.LOCOMOTION:
					Input.action_press("jump")
					return
				if _can_act(player):
					_press_light(player)
		"plunge4":
			if do_move and on_floor and player.state in Player.LOCOMOTION:
				var tx := _spot_x(boss, spot, arena)
				if absf(player.global_position.x - tx) > MOVE_TOL:
					_teleport(player, tx, gy)
				_face_boss(player, boss)
			if tick % 2 == 1:
				return
			if _need_heal(player):
				Input.action_press("heal")
				return
			var plunge_ok: bool = _b["now"] - _b["last_plunge_hit"] >= PLUNGE_GAP
			if not on_floor:
				_jump_logic(player, on_floor)
				if plunge_ok and not _b["plunged_air"] and player.state in Player.LOCOMOTION and player.velocity.y > -150.0:
					Input.action_press("plunge")
				return
			if _try_slash(player):
				return
			if plunge_ok and player.state in Player.LOCOMOTION:
				Input.action_press("jump")
				_b["jump_hold"] = 30
				return
			_press_light(player)
		"punish_roll":
			# 380 앞에서 기다리다 보스가 되돌림·무너짐이면 굴러 들어가 때리고, 새 예비동작이면 굴러 나온다
			var rec := _boss_recovering(boss)
			var wait_d := 380.0
			if do_move and player.state != Player.State.ROLL and absf(dx) > 700.0 and on_floor:
				_teleport(player, boss.global_position.x + signf(dx) * wait_d, gy)
			if tick % 2 == 1:
				return
			if _need_heal(player):
				Input.action_press("heal")
				return
			if player.state == Player.State.ROLL:
				return
			if rec:
				if absf(dx) > 200.0 and on_floor and (player.state in Player.LOCOMOTION or player.attack_phase == "recovery"):
					if player.state in Player.LOCOMOTION or not _strict_face:
						player.facing = -1 if dx > 0.0 else 1
					Input.action_press("dodge")
					return
				_face_boss(player, boss)
				if _try_slash(player):
					return
				if player.state in Player.LOCOMOTION or player.state == Player.State.ATTACK:
					_press_light(player)
			else:
				if absf(dx) < wait_d - 60.0 and on_floor and (player.state in Player.LOCOMOTION or player.attack_phase == "recovery"):
					if player.state in Player.LOCOMOTION or not _strict_face:
						player.facing = 1 if dx >= 0.0 else -1
					Input.action_press("dodge")
					return
				if player.state in Player.LOCOMOTION:
					var want := boss.global_position.x + (signf(dx) if dx != 0.0 else 1.0) * wait_d
					want = clampf(want, arena.position.x + 40.0, arena.end.x - 40.0)
					if absf(want - player.global_position.x) > 40.0:
						Input.action_press("move_right" if want > player.global_position.x else "move_left")
					else:
						_face_boss(player, boss)
						_try_ranged(player)
		"soulcycle", "soulrun":
			_bot_soul(mode, spot, player, boss, arena, gy, do_move, tick, gdt, on_floor)


## 영혼 돌려 쓰기 (soulcycle·soulrun; 마지막 검수 봇을 옮김): 패턴을 보지 않는 땅 맞딜인데 쿨이 끝난 영혼 기술을 모두 준비되는 대로 쓴다
## (씨앗 베기 > 바람·빛 > 약공격). 쿨·잠김은 소녀가 보여 주는 값(soul_cooldown_left — HUD·터치 버튼과 같은 값)만 본다.
func _bot_soul(mode: String, spot: String, player: Player, boss: Node2D, arena: Rect2, gy: float, do_move: bool, tick: int, gdt: float, on_floor: bool) -> void:
	if mode == "soulrun":
		# 사람처럼 달려 다닌다: 자리에서 250 넘게 멀면 달려가되(막혀 있으면 뛴다), 달리는 중에도 원거리 영혼은 쿨마다 쏜다
		var off := _spot_x(boss, spot, arena) - player.global_position.x
		_jump_logic(player, on_floor)
		if absf(off) > 250.0 and player.state in Player.LOCOMOTION:
			if absf(player.velocity.x) < 60.0:
				_b["stuck_t"] += gdt
			else:
				_b["stuck_t"] = 0.0
			Input.action_press("move_right" if off > 0.0 else "move_left")
			if on_floor and _b["stuck_t"] > 0.25 and tick % 2 == 0:
				Input.action_press("jump")
				_b["jump_hold"] = 30
				_b["stuck_t"] = 0.0
			# 달리며 원거리 영혼 (보스 쪽을 보고 있을 때만 — 돌아서지 않는다)
			var bdx := boss.global_position.x - player.global_position.x
			if signf(bdx) == float(player.facing) and tick % 2 == 0:
				for s in _owned_ranged(player):
					if player.soul_cooldown_left(s) <= 0.0:
						player.soul = s
						Progress.soul = s
						Input.action_press("soul_ability")
						break
			return
	elif do_move:
		var tx := _spot_x(boss, spot, arena)
		if absf(player.global_position.x - tx) > MOVE_TOL:
			_teleport(player, tx, gy)
	_face_boss(player, boss)
	if tick % 2 == 1:
		return
	if _need_heal(player):
		Input.action_press("heal")
		return
	if _try_slash(player):
		return
	if _try_ranged(player):
		return
	Input.action_press("attack_light")


## 처음 여섯 방식 (stand·wind·light·plunge_air·plunge_land·plunge_mix): 0.25초마다 목표 자리로 순간이동, 짝수 틱에 누르고 홀수 틱에 뗀다.
func _bot_classic(mode: String, spot: String, player: Player, boss: Node2D, arena: Rect2, gy: float, do_move: bool, tick: int, on_floor: bool) -> void:
	if do_move:
		var tx := _spot_x(boss, spot, arena)
		# 낙하 공격 봇은 바닥에 서 있을 때만 옮긴다 (튕겨 오르는 중에 끌어내리지 않게)
		var can_move := not mode in PLUNGE_MODES or (on_floor and player.state in Player.LOCOMOTION)
		if absf(player.global_position.x - tx) > MOVE_TOL and can_move:
			_teleport(player, tx, gy)
	_face_boss(player, boss)
	if tick % 2 == 1:
		return
	if _need_heal(player):
		Input.action_press("heal")
	elif mode in PLUNGE_MODES:
		if on_floor and player.state in Player.LOCOMOTION:
			if mode == "plunge_mix" and player.soul_cooldown_left() <= 0.0:
				Input.action_press("soul_ability")
			else:
				Input.action_press("jump")
				_b["jump_hold"] = 30
		elif not on_floor and player.state in Player.LOCOMOTION and player.velocity.y > -150.0 and (mode == "plunge_air" or not _b["plunged_air"]):
			Input.action_press("plunge")
		_jump_logic(player, on_floor)
	elif player.soul_cooldown_left() <= 0.0 and _can_act(player):
		Input.action_press("soul_ability")
	else:
		Input.action_press("attack_light")


# ---------------- 표와 합격 ----------------

func _summary() -> void:
	var by := {}
	var order: Array = []
	for r in _results:
		var k: String = "%s|%s" % [r["mode"], r["boss"]]
		if not by.has(k):
			by[k] = {"n": 0, "won": 0, "draw": 0, "worst_bot": 0.0, "min_boss": 999.0, "t": 0.0, "breaks": 0, "bt": 0.0}
			order.append(k)
		var b: Dictionary = by[k]
		b["n"] += 1
		b["t"] += r["t"]
		b["breaks"] += r["breaks"]
		if r["result"] == "won":
			b["won"] += 1
			b["worst_bot"] = maxf(b["worst_bot"], r["bot_pct"])
		elif r["result"] == "died":
			b["min_boss"] = minf(b["min_boss"], r["boss_pct"])
		else:
			b["draw"] += 1
	# 표: 줄 = 방식, 칸 = 보스 ("이긴/판 가장 아슬한 보스 체력%")
	var bosses: Array = []
	for p in PROFILES:
		bosses.append(p["id"])
	print("[probe] ── 표 (난이도 %s): 칸 = 봇 승/판 · 봇이 진 판 중 보스 체력 최저%% · (이긴 판의 봇 체력 최고%%) · 무너짐/40초" % _diff)
	var head := "[probe] %-12s" % "방식"
	for bi in bosses:
		head += " | %-24s" % bi
	print(head)
	var modes_seen: Array = []
	for k in order:
		var m: String = k.split("|")[0]
		if not m in modes_seen:
			modes_seen.append(m)
	for m in modes_seen:
		var line := "[probe] %-12s" % m
		for bi in bosses:
			var k: String = "%s|%s" % [m, bi]
			if not by.has(k):
				line += " | %-24s" % "-"
				continue
			var b: Dictionary = by[k]
			var cell := "%d/%d %s" % [b["won"], b["n"], ("%.0f%%" % b["min_boss"]) if b["min_boss"] < 999.0 else "-"]
			if b["won"] > 0:
				cell += " (봇%.0f%%)" % b["worst_bot"]
			if b["draw"] > 0:
				cell += " 무%d" % b["draw"]
			cell += " 무너짐%.1f" % (40.0 * b["breaks"] / maxf(b["t"], 1.0))
			line += " | %-24s" % cell
		print(line)
	if _diff != "normal":
		print("[probe] (참고: 합격 판정은 Normal 만)")
		return
	for k in order:
		var b: Dictionary = by[k]
		var mk: Array = k.split("|")
		var mode: String = mk[0]
		if mode in ZERO_WIN_MODES:
			_check(b["won"] == 0 and b["draw"] == 0, "[%s] %s: 땅 맞딜 봇 승 %d/%d, 무승부 %d (0 이어야 함)" % [MODE_NAMES.get(mode, mode), mk[1], b["won"], b["n"], b["draw"]])
		else:
			_check(b["won"] <= 1 and b["worst_bot"] <= 50.0, "[%s] %s: 봇 승 %d/%d (1 이하), 이긴 판 봇 체력 최고 %.0f%% (50%% 이하), 무승부 %d" % [
				MODE_NAMES.get(mode, mode), mk[1], b["won"], b["n"], b["worst_bot"], b["draw"]])


# ---------------- '잘하는 사람' 봇 (--good) ----------------

func _good_all(args: PackedStringArray, only: Array) -> void:
	var seeds := _parse_seeds(_arg(args, "--good-seeds", "4"))
	var grc := _arg(args, "--good-roll-cost", "")
	if grc != "":
		_roll_cost = float(grc)
	print("[probe] 잘하는 봇 (난이도 %s, 죽지 않음, 패턴 피하기·저스트 가드·모든 기술, 씨드 %s, 구르기 비용 %s, 영혼 함께 잠김 %s)" % [_diff, seeds,
		"기본" if _roll_cost < 0.0 else str(_roll_cost), "기본" if _soul_lock < 0.0 else str(_soul_lock)])
	if not _boss_set.is_empty():
		print("[probe] 보스 값 바꿈: %s" % _boss_set)
	for prof in PROFILES:
		if not only.is_empty() and not prof["id"] in only:
			continue
		var ts: Array = []
		var hits := 0
		var breaks := 0
		var jg := 0
		var rolls := 0
		for sd in seeds:
			var r: Dictionary = await _good_run(prof, sd)
			ts.append(r["t"])
			hits += r["hits"]
			breaks += r["breaks"]
			jg += r["jg"]
			rolls += r["rolls"]
			var dl: Dictionary = r["dealt"]
			print("[probe] (참고) 잘하는 봇 %s 씨드 %d: %s %.1f초, 맞음 %d, 저스트 가드 %d, 구르기 %d, 보스 무너짐 %d, 영혼 기술 씨앗 %d·바람 %d·빛 %d, 준 피해 베기 %.0f·원거리 %.0f·약공격 %.0f·낙하 %.0f" % [prof["id"], sd,
				"잡음" if r["won"] else "못 잡음", r["t"], r["hits"], r["jg"], r["rolls"], r["breaks"], r["casts"]["seed"], r["casts"]["wind"], r["casts"]["light"],
				dl["slash"], dl["ranged"], dl["light"], dl["plunge"]])
		var avg := 0.0
		for v in ts:
			avg += v
		avg /= maxf(ts.size(), 1)
		var cmp := ""
		if GOOD_BASELINE.has(prof["id"]):
			var base: float = GOOD_BASELINE[prof["id"]]
			cmp = " (1985add %.1f초 대비 %+.1f%%)" % [base, 100.0 * (avg - base) / base]
		print("[probe] 잘하는 봇 요약 %s: 평균 %.1f초%s, 판당 맞음 %.1f·저스트 가드 %.1f·구르기 %.1f·무너짐 %.1f" % [prof["id"], avg, cmp,
			float(hits) / seeds.size(), float(jg) / seeds.size(), float(rolls) / seeds.size(), float(breaks) / seeds.size()])
		if GOOD_BASELINE.has(prof["id"]) and _diff == "normal":
			_check(avg <= float(GOOD_BASELINE[prof["id"]]) * 1.2, "잘하는 봇 %s: 1985add 보다 20%% 넘게 느려지지 않는다 (%.1f / %.1f초)" % [prof["id"], avg, GOOD_BASELINE[prof["id"]]])


func _good_run(prof: Dictionary, sd: int) -> Dictionary:
	seed(9100 + sd * 7 + PROFILES.find(prof) * 31 + 5000)
	_b = {"teleports": 0, "now": 0.0, "guard_hold": 0.0, "last_plunge": -99.0, "plunging": false, "plunged": false, "jump_hold": 0,
		"proj_prev": {}, "rolls": 0, "air": false}
	var opened: Array = await _open_room(prof, "stand")
	var room: Node = opened[0]
	var player: Player = opened[1]
	var boss: Node2D = opened[2]
	var gy: float = boss.ground_y
	var arena: Rect2 = boss.arena
	var hits := [0]
	player.hit_taken.connect(func(_d: float) -> void:
		hits[0] += 1
		if _trace:
			print("[hit] t=%.1f ← %s/%s 소녀 %s dx %.0f 높이 %.0f" % [_b["now"], boss.state_name(), str(boss.get("attack_phase")), Player.State.keys()[player.state],
				player.global_position.x - boss.global_position.x, float(boss.ground_y) - player.global_position.y]))
	if _trace and boss.has_signal("state_changed"):
		boss.state_changed.connect(func(_a = null) -> void: print("[boss] t=%.1f → %s (체력 %.0f)" % [_b["now"], boss.state_name(), float(boss.hp)]))
	var jg := [0]
	player.just_guarded.connect(func(_s) -> void: jg[0] += 1)
	player.roll_started.connect(func() -> void: _b["rolls"] += 1)
	# 영혼 기술을 몇 번 썼나 (씨앗 베기 / 바람 / 빛) — 함께 잠김이 얼마나 막는지 보려고
	var casts := {"seed": 0, "wind": 0, "light": 0}
	player.soul_slash_started.connect(func() -> void: casts["seed"] += 1)
	player.gust_cast.connect(func() -> void: casts["wind"] += 1)
	player.laser_charge_started.connect(func() -> void: casts["light"] += 1)
	# 보스에게 준 피해를 길별로 (씨앗 베기 / 낙하 / 약공격 / 원거리 = 그 밖 — 바람·빛)
	var dealt := {"slash": 0.0, "plunge": 0.0, "light": 0.0, "ranged": 0.0}
	var bhp_prev := [float(boss.hp)]
	boss.hp_changed.connect(func(h: float, _m: float) -> void:
		if h < bhp_prev[0] and is_instance_valid(player):
			var k := "ranged"
			if player.state == Player.State.PLUNGE:
				k = "plunge"
			elif player.state == Player.State.SOUL_SLASH:
				k = "slash"
			elif player.state == Player.State.ATTACK:
				k = "light"
			dealt[k] += bhp_prev[0] - h
		bhp_prev[0] = h)
	var breaks := [0]
	if boss.has_signal("state_changed"):
		boss.state_changed.connect(func(_a = null) -> void:
			if boss.state_name() == "BROKEN":
				breaks[0] += 1)
	var dt := float(_accel) / float(Engine.physics_ticks_per_second)
	var t := 0.0
	var tick := 0
	var won := false
	while t < TIME_LIMIT:
		await get_tree().physics_frame
		var gdt := Engine.time_scale / float(Engine.physics_ticks_per_second)
		if _accel > 1 and Engine.time_scale != float(_accel):
			Engine.time_scale = float(_accel)
		if _accel > 1 and boss is SapQueen:
			boss._clock += dt * (1.0 - 1.0 / float(_accel))
		t += gdt
		_b["now"] = t
		tick += 1
		if not is_instance_valid(player) or not is_instance_valid(boss):
			break
		if boss.state_name() in ["FALLEN", "PURIFIED"]:
			won = true
			break
		if player.state == Player.State.DEAD:
			break
		_good_bot(player, boss, arena, gy, tick, gdt)
	var out := {"t": t if won else TIME_LIMIT, "won": won, "hits": hits[0], "jg": jg[0], "rolls": _b["rolls"], "breaks": breaks[0], "casts": casts, "dealt": dealt}
	await _close_room(room)
	return out


## 다가오는 적 투사체 가운데 가장 먼저 닿을 것까지의 시간 (초, 없으면 INF)
func _proj_threat(player: Player, gdt: float) -> float:
	var me := player.global_position + Vector2(0, -10)
	var best := INF
	var prev: Dictionary = _b["proj_prev"]
	var now_pos := {}
	for n in get_tree().get_nodes_in_group("projectile"):
		if not (n is Node2D) or not is_instance_valid(n):
			continue
		if n.get("from_player") == true or n.get("_dead") == true:
			continue
		var id := n.get_instance_id()
		var p: Vector2 = (n as Node2D).global_position
		now_pos[id] = p
		if not prev.has(id) or gdt <= 0.0:
			continue
		var v: Vector2 = (p - prev[id]) / gdt
		var to := me - p
		var dist := to.length()
		if dist > 420.0:
			continue
		var closing := v.dot(to.normalized()) if dist > 0.01 else 0.0
		if closing < 60.0:
			continue
		var r := 30.0
		if n.has_method("hit_radius"):
			r = float(n.hit_radius())
		best = minf(best, maxf(dist - r - 40.0, 0.0) / closing)
	_b["proj_prev"] = now_pos
	return best


func _good_bot(player: Player, boss: Node2D, arena: Rect2, gy: float, tick: int, gdt: float) -> void:
	player.hp = player.max_hp   # 죽지 않는다 (잡는 시간만 잰다; 맞으면 경직·밀려남은 그대로 받는다)
	var on_floor := player.is_on_floor()
	var me := player.global_position
	var dx := me.x - boss.global_position.x
	var body := Rect2(me + Vector2(-25.0, -66.0), Vector2(50.0, 132.0))
	var keep: Array = []
	# 저스트 가드 판정을 게임 시간으로: 소녀는 가드를 누른 때를 실제 시계(Time.get_ticks_msec)로 재는데, --fixed-fps 시험은 실제보다
	# 몇 십 배 빨리 돌아 0.24초 창이 게임 시간으로 몇 초가 되고 컴퓨터 빠르기에 따라 판마다 달라진다 → 누른 뒤 흐른 게임 시간으로 맞춰 둔다
	# (소녀가 저스트 가드 뒤 -1000 으로 지운 값은 건드리지 않는다)
	# 가드를 뗀 뒤 다시 누를 수 있기까지(guard_relock_time 0.2초)도 실제 시계라 같은 식으로 맞춘다
	if player.state == Player.State.GUARD and player._guard_pressed_at > -999.0 and _b.has("guard_press_t"):
		player._guard_pressed_at = player._now() - (_b["now"] - float(_b["guard_press_t"]))
	if _b.has("guard_release_t") and player.state != Player.State.GUARD:
		player._guard_released_at = player._now() - (_b["now"] - float(_b["guard_release_t"]))
	# 가드를 들고 있는 중 (저스트 가드 뒤 잠깐)
	if _b["guard_hold"] > 0.0:
		_b["guard_hold"] -= gdt
		keep.append("guard")
		_release_all(keep)
		Input.action_press("guard")
		if _b["guard_hold"] <= 0.0:
			_b["guard_release_t"] = _b["now"] + gdt   # 다음 틱에 뗀다
		return
	var threat := _proj_threat(player, gdt)
	var can_guard := on_floor and _can_act(player)
	if threat <= 0.12 and can_guard:
		_face_boss(player, boss)
		_release_all()
		Input.action_press("guard")
		_b["guard_hold"] = 0.3
		_b["guard_press_t"] = _b["now"]
		return
	# 보스 근접 공격 범위 예고 안이면 빠져나온다
	var tel = boss.get("_tel")
	if tel != null and tel.is_showing() and tel.rect.grow(10.0).intersects(body):
		var r: Rect2 = tel.rect
		var left: float = (1.0 - tel.progress()) * tel.duration
		var ex_l := r.position.x - 60.0
		var ex_r := r.end.x + 60.0
		var cand: Array = []
		if ex_l > arena.position.x + 30.0:
			cand.append(ex_l)
		if ex_r < arena.end.x - 30.0:
			cand.append(ex_r)
		if cand.is_empty():
			cand = [ex_l if absf(ex_l - me.x) < absf(ex_r - me.x) else ex_r]
		var ex: float = cand[0]
		for c in cand:
			if absf(c - me.x) < absf(ex - me.x):
				ex = c
		var dist := absf(ex - me.x)
		var dir := 1 if ex > me.x else -1
		_release_all()
		var run_time := dist / 640.0
		if run_time < left - 0.05 or not on_floor:
			if player.state in Player.LOCOMOTION:
				Input.action_press("move_right" if dir > 0 else "move_left")
		elif not tel.unguardable and can_guard:
			# 가드 가능: 달려 나갈 시간이 없으면 구르지 않고(스태미너 아낌) 그 자리에서 기다렸다가 맞기 직전에 저스트 가드
			if left <= 0.14:
				_face_boss(player, boss)
				Input.action_press("guard")
				_b["guard_hold"] = 0.35
				_b["guard_press_t"] = _b["now"]
		elif player.guard >= player.roll_stamina_cost and on_floor and (player.state in Player.LOCOMOTION or _can_act(player) or player.state == Player.State.GUARD):
			if player.state in Player.LOCOMOTION:
				player.facing = dir
			if tick % 2 == 0:
				Input.action_press("dodge")
		elif player.state in Player.LOCOMOTION:
			Input.action_press("move_right" if dir > 0 else "move_left")
		return
	_release_all()
	# 낙하 공격 (6초마다, 보스가 땅에 있을 때)
	if _b["plunging"]:
		if player.state == Player.State.PLUNGE:
			_b["plunged"] = true
		if on_floor and _b["plunged"] and player.state in Player.LOCOMOTION:
			_b["plunging"] = false
			_b["last_plunge"] = _b["now"]
		elif on_floor and player.state in Player.LOCOMOTION and tick % 2 == 0:
			Input.action_press("jump")
			_b["jump_hold"] = 30
		elif not on_floor and not _b["plunged"] and player.state in Player.LOCOMOTION and player.velocity.y > -150.0 and tick % 2 == 0:
			Input.action_press("plunge")
		_jump_logic(player, on_floor)
		if _b["now"] - _b["last_plunge"] > 12.0:
			_b["plunging"] = false
			_b["last_plunge"] = _b["now"]
		return
	var grounded: bool = boss.is_ground()
	var reach_y := absf((boss.global_position.y - 120.0) - me.y) < 260.0 or grounded
	# 하늘의 보스: 몸이 닿을 만한 높이·거리면 뛰어올라(이단 점프) 베기·약공격 (사람이 새·여왕을 칠 때처럼)
	var bc := boss.global_position + Vector2(0.0, -130.0)
	if _b["air"]:
		if on_floor and player.state in Player.LOCOMOTION and player.velocity.y >= 0.0:
			_b["air"] = false
		else:
			_jump_logic(player, on_floor)
			if not on_floor and player.state in Player.LOCOMOTION and player.velocity.y > -160.0 and player._jumps_left > 0 and bc.y < me.y - 220.0 and tick % 2 == 0:
				Input.action_press("jump")
			elif absf(bc.y - me.y) < 240.0 and tick % 2 == 0:
				_face_boss(player, boss)
				if not _try_slash(player) and _can_act(player):
					_press_light(player)
			return
	if not grounded and absf(bc.x - me.x) < 260.0 and bc.y < me.y - 150.0 and bc.y > me.y - 700.0 and on_floor and player.state in Player.LOCOMOTION \
			and (player.soul_cooldown_left("seed") <= 0.0 or player.guard >= player.light_cost_of(1)) and tick % 2 == 0:
		_b["air"] = true
		_face_boss(player, boss)
		Input.action_press("jump")
		_b["jump_hold"] = 30
		return
	# 자리: 보스 옆 (지금 있는 쪽) 170
	var side := signf(dx) if absf(dx) > 4.0 else -float(boss.get("facing"))
	var want := clampf(boss.global_position.x + side * 170.0, arena.position.x + 40.0, arena.end.x - 40.0)
	if not grounded:
		want = clampf(boss.global_position.x + side * 120.0, arena.position.x + 40.0, arena.end.x - 40.0)
	var far := absf(want - me.x) > 50.0
	if far and player.state in Player.LOCOMOTION:
		Input.action_press("move_right" if want > me.x else "move_left")
	else:
		_face_boss(player, boss)
	if tick % 2 == 1:
		return
	var adx := absf(dx)
	# 원거리 영혼: 멀거나 보스가 하늘에 있을 때
	if (adx > 300.0 or not grounded) and adx < 1100.0 and not _owned_ranged(player).is_empty():
		_face_boss(player, boss)
		if _try_ranged(player, boss):
			return
	if adx < 380.0 and reach_y and _try_slash(player):
		return
	if grounded and adx < 260.0 and _b["now"] - _b["last_plunge"] >= 6.0 and on_floor and player.state in Player.LOCOMOTION:
		_b["plunging"] = true
		_b["plunged"] = false
		Input.action_press("jump")
		_b["jump_hold"] = 30
		return
	if adx < 290.0 and reach_y and _can_act(player):
		_press_light(player)

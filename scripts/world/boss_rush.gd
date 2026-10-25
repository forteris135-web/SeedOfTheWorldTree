class_name BossRush
extends RefCounted
## 보스 러시 (엔딩을 본 뒤 타이틀에서 연다, 2026-10-20 기획자 요청). 다섯 수호자를 이야기 순서대로 잇달아 싸운다:
## 잿빛 잎새의 새 → 등불 기사 → 수액의 여왕 → 무쇠 펌프 → 뿌리지기. 싸움은 각자의 보스 방에서, 보스곡도 각자 자기 곡.
##
## 규칙 (GAME_DESIGN.md 7장 '엔딩 뒤 타이틀: 보스 러시 · 음악 감상'):
## - 몸은 저장 파일의 성장 그대로 (최대 체력·공격력·회복량·이슬·영혼·능력·새순 기술 단계). 저장 파일에 성장 기록이 없으면 '다 자란 몸'
##   (data/dialogue/boss_rush.json 의 full_power). 바닥이 수액인 펌프 방 때문에 '수액 위 걷기'는 늘 준다.
##   v1.1.0 저장 칸: 저장 파일 = 엔딩을 본 칸 가운데 가장 늦게 저장한 칸 (SaveGame.latest_slot(true)). 러시 난이도 = 그 칸의 난이도,
##   다 자란 몸이면 Normal (명세 D25). 엔딩을 본 칸이 없으면(메타로만 열림) 다 자란 몸 — '새로 시작'은 곧바로 첫 저장을 하므로,
##   그냥 '가장 늦은 칸'이면 다른 칸에서 막 새로 시작한 빈 몸(능력 없음)으로 러시가 열린다. RUSH_CLEARED_SLOT_ONLY 로 바꿀 수 있다.
## - 보스마다 체력·이슬이 가득 찬 채로 시작한다 (소녀는 방마다 새로 만들어진다).
## - 러시 동안에는 회상·보상·깃발·빛 가루가 없고, **저장 파일에 아무것도 쓰지 않는다**: 시작할 때 진행(Progress)과 정화 상태(Purity)를
##   통째로 떼어 두고 러시용 빈 진행으로 바꿨다가, 끝나면(결과 화면) 그대로 되돌린다. SaveGame 은 러시 중 쓰기를 거절한다.
## - 시간: 보스마다 싸움이 시작된 때부터 쓰러질 때까지 (방을 옮기는 시간·일시정지는 세지 않는다). 전체 시간 = 다섯 싸움의 합.
## - 쓰러지면 결과 화면 (어디까지 왔는지, 시간) → 타이틀. 다 이기면 전체 시간과 보스별 기록. 최고 기록은 user://boss_rush.json 따로,
##   v1.1.0 부터 난이도별로 ({"normal": {...}, "hard": {...}}; 옛 한 덩어리 기록은 Normal 로 읽는다).
## - 일시정지 메뉴에 '포기하기' (저장·불러오기·타이틀로 대신).
## - 보스가 쓰러지면 짧게 숨을 고른 뒤 다음 보스 방으로 저절로 넘어간다.
## 정적 함수·정적 변수만 있다 (자동 로드를 늘리지 않으려고). BossRoom 이 active 를 보고 러시 모드로 돈다.

const DATA_PATH := "res://data/dialogue/boss_rush.json"
const BEST_PATH := "user://boss_rush.json"
const RESULT_SCENE := "res://scenes/ui/boss_rush_result.tscn"
## 이야기 순서의 다섯 보스. start_x = 러시에서 소녀가 서는 자리(싸움터 문 안쪽, 바닥 위), intro = 등장 연출을 이 초로 줄임
## (-1 = 그대로: 여왕과 펌프는 보스곡의 박자에 맞춰 움직이므로 등장 길이를 바꾸지 않는다).
const BOSSES := [
	{"id": "bird", "scene": "res://scenes/rooms/canopy_boss.tscn", "start_x": 1200.0, "intro": 1.4},
	{"id": "knight", "scene": "res://scenes/rooms/mine_boss.tscn", "start_x": 1200.0, "intro": 1.2},
	{"id": "queen", "scene": "res://scenes/rooms/sap_lake_boss.tscn", "start_x": 1000.0, "intro": -1.0},
	{"id": "pump", "scene": "res://scenes/rooms/flooded_mine_boss.tscn", "start_x": 1200.0, "intro": -1.0},
	{"id": "root", "scene": "res://scenes/rooms/abyss_boss.tscn", "start_x": 1200.0, "intro": 1.4},
]
## 러시 동안 떼어 두는 Progress 의 값들 (끝나면 그대로 되돌린다)
const PROGRESS_FIELDS := ["flags", "abilities", "soul", "next_spawn", "pending_memory", "memory_return_scene", "upgrades",
	"grasses", "last_grass", "rescued", "visited_rooms", "ending", "collected", "dust", "soul_cooldowns",
	"tokens", "difficulty", "killed", "carry_hp", "carry_dews"]
## 보스가 쓰러진 뒤 다음 방으로 넘어가기까지 (초): 숨 고르기 + 보스가 빛으로 흩어짐
const ADVANCE_BEAT := 2.6
const ADVANCE_FADE := 1.0
## 소녀의 발끝이 바닥선(GroundLine)보다 위인 거리 (보스 방의 AfterBoss 표식과 같다)
const FOOT_OFFSET := 68.0

## 러시 중인가 (SaveGame·BossRoom·Room·일시정지 메뉴가 본다)
static var active := false
## 지금 싸우는(또는 다음에 싸울) 보스 번호 (0부터)
static var index := 0
## 쓰러뜨린 보스별 싸움 시간 (초)
static var splits: Array = []
## 지금 보스와 싸운 시간 (초)
static var elapsed := 0.0
## 지금 싸움 시간을 세는 중인가 (싸움 시작 → 쓰러짐/소녀 쓰러짐)
static var running := false
## 다음 방으로 넘어가는 중 (보스가 쓰러진 뒤)
static var advancing := false
## 몸의 출처: "save" (저장 파일의 성장) / "full" (다 자란 몸)
static var growth_source := ""
## 이번 러시의 난이도 (Balance.DIFFICULTIES). 최고 기록도 이 난이도 칸에 남는다.
static var difficulty := "normal"
## 러시의 몸을 엔딩을 본 칸에서만 가져온다 (false = 명세 D25 글자 그대로 '가장 늦게 저장한 칸')
const RUSH_CLEARED_SLOT_ONLY := true
## 끝난 러시의 결과 (결과 화면이 읽는다): {outcome, reached, splits, current, total, best_total, new_best, split_bests, growth}
static var result := {}
static var _snapshot := {}
static var _data_cache := {}


# ---------- 시작 · 끝 ----------

## 러시를 시작한다 (타이틀의 '보스 러시'). 진행을 떼어 두고 러시용 몸을 만든 뒤 첫 보스 방으로.
static func start() -> void:
	if active:
		return
	var growth := growth_from_save()
	_snapshot = _take_snapshot()
	active = true
	index = 0
	splits = []
	elapsed = 0.0
	running = false
	advancing = false
	result = {}
	growth_source = str(growth["source"])
	difficulty = str(growth.get("difficulty", "normal"))
	_setup_progress(growth)
	Music.stop(1.0)
	_go(scene_of(0), 1.0, 1.0)


## 보스 방이 싸움을 걸었다: 이 보스의 시간을 0부터 센다.
static func fight_started() -> void:
	if not active:
		return
	elapsed = 0.0
	running = true


## 보스 방이 매 프레임 부른다 (실제 시간; 히트스톱으로 느려진 시간도 실제 시간으로 되돌려 센다, 일시정지 중엔 불리지 않는다).
static func tick(delta: float) -> void:
	if not active or not running:
		return
	elapsed += minf(delta / maxf(Engine.time_scale, 0.01), 0.25)


## 보스가 쓰러졌다: 이 싸움의 기록을 남긴다. 돌려주는 값 = 이 싸움 시간.
static func boss_down() -> float:
	if not active or not running:
		return 0.0
	running = false
	advancing = true
	splits.append(elapsed)
	return elapsed


## 마지막 보스였는가 (쓰러뜨린 뒤 확인)
static func is_last() -> bool:
	return index >= BOSSES.size() - 1


## 다음 보스 방으로 (마지막이었으면 결과 화면으로).
static func advance() -> void:
	if not active or not result.is_empty():
		return
	if splits.size() >= BOSSES.size():
		finish("clear")
		return
	index = splits.size()
	advancing = false
	elapsed = 0.0
	_go(scene_of(index), 0.8, 0.9)


## 러시를 끝낸다: outcome = "clear"(완주) / "dead"(쓰러짐) / "quit"(포기). 기록을 남기고 결과 화면으로.
## (진행은 결과 화면이 열릴 때 되돌린다 — 보스 방이 아직 화면에 있는 동안 깃발이 바뀌지 않게)
## 보스를 쓰러뜨린 뒤 다음 방으로 넘어가는 사이(advancing)에 끝나면: 그 싸움 시간은 이미 splits 에 들어 있으므로 '지금 싸움'은 0,
## 다다른 곳은 다음 보스, 다섯을 다 쓰러뜨린 뒤였으면 완주로 친다 (2026-10-20 QA: 시간이 두 번 더해지고 다 이긴 기록이 '포기'로 남았다).
static func finish(outcome: String) -> void:
	if not active or not result.is_empty():
		return
	var between := advancing
	running = false
	advancing = false
	var total := 0.0
	for s in splits:
		total += float(s)
	var reached := index
	var current := elapsed
	if outcome == "clear":
		current = 0.0
	elif between:
		current = 0.0
		reached = mini(splits.size(), BOSSES.size() - 1)
		if splits.size() >= BOSSES.size():
			outcome = "clear"
	result = {"outcome": outcome, "reached": reached, "splits": splits.duplicate(), "current": current,
		"total": total + current, "growth": growth_source, "difficulty": difficulty}
	_record_best(result)
	_go(RESULT_SCENE, 0.8, 0.8)


## 일시정지 메뉴의 '포기하기'.
static func give_up() -> void:
	finish("quit")


## 떼어 둔 진행을 되돌리고 러시를 끝낸다 (결과 화면이 부른다; 타이틀도 혹시 남아 있으면 부른다).
static func restore() -> void:
	if not active:
		return
	for k in PROGRESS_FIELDS:
		Progress.set(k, _snapshot[k])
	for m in Progress.get_meta_list():
		Progress.remove_meta(m)
	var metas: Dictionary = _snapshot.get("_meta", {})
	for m in metas:
		Progress.set_meta(m, metas[m])
	Purity.regions = _snapshot["_purity"]
	_snapshot = {}
	active = false
	running = false
	advancing = false


## 장면 바꾸기. 다른 장면 전환(방에 들어선 직후의 밝아짐 등)이 아직 끝나지 않았으면 끝난 뒤에 바꾼다
## (Game.go_to 는 전환 중에 부르면 아무것도 하지 않아서, 들어서자마자 '포기하기'를 누르면 결과 화면으로 가지 못했다).
static func _go(path: String, fade_out: float, fade_in: float) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var waited := 0
	while Game._busy and waited < 600 and tree != null:
		await tree.process_frame
		waited += 1
	Game.go_to(path, fade_out, fade_in)


# ---------- 몸 (성장) ----------

## 러시에서 쓸 몸: 엔딩을 본 칸 가운데 가장 늦게 저장한 칸의 성장 (읽기만 한다). 그런 칸이 없거나 능력·성장 기록이 없으면 다 자란 몸.
## {"source": "save"/"full", "abilities": {이름: true}, "upgrades": {종류: 값 — 새순 기술 단계 tok_* 도 함께}, "soul": 고른 영혼,
##  "difficulty": 그 칸의 난이도 (다 자란 몸은 normal), "tokens": 그 칸의 새순 (쓰지 않는다), "slot": 칸 번호 (다 자란 몸은 0)}
static func growth_from_save() -> Dictionary:
	var slot := SaveGame.latest_slot(RUSH_CLEARED_SLOT_ONLY)
	if slot > 0:
		var d := SaveGame.read_slot(slot)
		# 능력이 하나도 없는 칸(막 새로 시작한 칸)은 쓰지 않고 다 자란 몸으로
		if d.get("abilities") is Dictionary and not (d["abilities"] as Dictionary).is_empty() and d.get("upgrades") is Dictionary:
			var diff := str(d.get("difficulty", "normal"))
			return {"source": "save", "abilities": (d["abilities"] as Dictionary).duplicate(true),
				"upgrades": (d["upgrades"] as Dictionary).duplicate(true), "soul": str(d.get("soul", "seed")),
				"difficulty": diff if Balance.DIFF_MULT.has(diff) else "normal", "tokens": int(d.get("tokens", 0)), "slot": slot}
	var full: Dictionary = data().get("full_power", {})
	var ab := {}
	for a in full.get("abilities", []):
		ab[str(a)] = true
	var up := {}
	var fu: Dictionary = full.get("upgrades", {})
	for k in fu:
		up[k] = float(fu[k])
	return {"source": "full", "abilities": ab, "upgrades": up, "soul": str(full.get("soul", "seed")), "difficulty": "normal", "tokens": 0, "slot": 0}


static func _setup_progress(growth: Dictionary) -> void:
	# 원래 사전들은 건드리지 않고(떼어 둔 것 그대로) 새 빈 것으로 바꾼다
	Progress.flags = {}
	Progress.abilities = growth["abilities"]
	Progress.abilities["sap_walk"] = true   # 펌프 방 바닥이 수액이다
	Progress.soul = str(growth["soul"])
	Progress.next_spawn = ""
	Progress.pending_memory = ""
	Progress.memory_return_scene = ""
	Progress.upgrades = growth["upgrades"]
	Progress.grasses = {}
	Progress.last_grass = {}
	Progress.rescued = {}
	Progress.visited_rooms = {}
	Progress.ending = ""
	Progress.collected = {}
	Progress.dust = 0
	Progress.soul_cooldowns = {}
	# v1.1.0: 난이도 = 몸을 가져온 칸의 난이도 (다 자란 몸은 Normal), 새순은 그 칸의 값 그대로 (러시에선 쓰지 않는다),
	# 러시용 새 사전 (떼어 둔 '쓰러뜨린 적' 사전에 러시가 쓰지 않게), 방 사이 체력·이슬 이어가기 없음
	var diff := str(growth.get("difficulty", "normal"))
	Progress.difficulty = diff if Balance.DIFF_MULT.has(diff) else "normal"
	Progress.tokens = int(growth.get("tokens", 0))
	Progress.killed = {}
	Progress.carry_hp = -1.0
	Progress.carry_dews = -1
	for m in Progress.get_meta_list():
		Progress.remove_meta(m)
	# 싸움터는 정화 전의 잿빛
	var pur := {}
	for k in Purity.regions:
		pur[k] = false
	Purity.regions = pur


static func _take_snapshot() -> Dictionary:
	var s := {}
	for k in PROGRESS_FIELDS:
		s[k] = Progress.get(k)   # 사전·배열은 그 객체 자체 (러시 동안 Progress 는 새 객체를 쓰므로 그대로 남는다)
	var metas := {}
	for m in Progress.get_meta_list():
		metas[m] = Progress.get_meta(m)
	s["_meta"] = metas
	s["_purity"] = Purity.regions
	return s


# ---------- 표 · 글자 ----------

static func scene_of(i: int) -> String:
	return str(BOSSES[clampi(i, 0, BOSSES.size() - 1)]["scene"])


static func boss_id(i: int) -> String:
	return str(BOSSES[clampi(i, 0, BOSSES.size() - 1)]["id"])


static func boss_name(i: int) -> String:
	return str(data().get("bosses", {}).get(boss_id(i), boss_id(i)))


## 보스 방 경로 → 러시 번호 (러시 보스 방이 아니면 -1)
static func index_of_scene(path: String) -> int:
	for i in BOSSES.size():
		if BOSSES[i]["scene"] == path:
			return i
	return -1


static func start_x(i: int) -> float:
	return float(BOSSES[clampi(i, 0, BOSSES.size() - 1)]["start_x"])


static func intro_time(i: int) -> float:
	return float(BOSSES[clampi(i, 0, BOSSES.size() - 1)]["intro"])


## 지금까지의 전체 시간 (쓰러뜨린 싸움의 합 + 지금 싸움)
static func current_total() -> float:
	var t := 0.0
	for s in splits:
		t += float(s)
	if running:
		t += elapsed
	return t


static func data() -> Dictionary:
	if _data_cache.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		_data_cache = d if d is Dictionary else {}
	return _data_cache


## 글자 하나 (data/dialogue/boss_rush.json). {이름} 자리를 args 로 채운다.
static func text(key: String, args := {}) -> String:
	var s := str(data().get(key, key))
	return s.format(args) if not args.is_empty() else s


## 01:23.45 꼴 (60분이 넘으면 1:01:23.45)
static func format_time(sec: float) -> String:
	var cs := int(round(maxf(sec, 0.0) * 100.0))
	var h := cs / 360000
	var m := (cs / 6000) % 60
	var s := (cs / 100) % 60
	var c := cs % 100
	if h > 0:
		return "%d:%02d:%02d.%02d" % [h, m, s, c]
	return "%02d:%02d.%02d" % [m, s, c]


# ---------- 최고 기록 (user://boss_rush.json) ----------

## 한 난이도의 기록: {"best_total": 초 또는 -1, "best_splits": [...], "best_at": 때, "split_bests": {보스 id: 초}, "clears": 완주 수, "attempts": 도전 수}
## diff 가 ""이면 이번(또는 마지막) 러시의 난이도.
static func load_best(diff := "") -> Dictionary:
	if diff == "":
		diff = difficulty
	return _parse_record(_load_all().get(diff, {}))


## 파일 전체: {난이도: 기록}. v1.1.0 전의 한 덩어리 기록(맨 위에 best_total 이 있는 꼴)은 Normal 의 기록으로 읽는다.
static func _load_all() -> Dictionary:
	if not FileAccess.file_exists(BEST_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(BEST_PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	if d.has("best_total") or d.has("attempts"):
		return {"normal": d}
	var out := {}
	for k in d:
		if Balance.DIFF_MULT.has(str(k)) and d[k] is Dictionary:
			out[str(k)] = d[k]
	return out


static func _parse_record(d) -> Dictionary:
	var out := {"best_total": -1.0, "best_splits": [], "best_at": "", "split_bests": {}, "clears": 0, "attempts": 0}
	if typeof(d) != TYPE_DICTIONARY:
		return out
	out["best_total"] = float(d.get("best_total", -1.0))
	out["best_splits"] = d.get("best_splits", []) if d.get("best_splits") is Array else []
	out["best_at"] = str(d.get("best_at", ""))
	out["split_bests"] = d.get("split_bests", {}) if d.get("split_bests") is Dictionary else {}
	out["clears"] = int(d.get("clears", 0))
	out["attempts"] = int(d.get("attempts", 0))
	return out


static func _record_best(r: Dictionary) -> void:
	var diff := str(r.get("difficulty", difficulty))
	var all := _load_all()
	var b := _parse_record(all.get(diff, {}))
	b["attempts"] = int(b["attempts"]) + 1
	var sb: Dictionary = b["split_bests"]
	var sp: Array = r["splits"]
	for i in sp.size():
		var id := boss_id(i)
		if not sb.has(id) or float(sp[i]) < float(sb[id]):
			sb[id] = float(sp[i])
	var new_best := false
	if r["outcome"] == "clear":
		b["clears"] = int(b["clears"]) + 1
		if float(b["best_total"]) < 0.0 or float(r["total"]) < float(b["best_total"]):
			new_best = true
			b["best_total"] = float(r["total"])
			b["best_splits"] = sp.duplicate()
			b["best_at"] = Time.get_datetime_string_from_system()
	r["new_best"] = new_best
	r["best_total"] = float(b["best_total"])
	r["best_splits"] = b["best_splits"]
	r["split_bests"] = sb
	all[diff] = b
	var f := FileAccess.open(BEST_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all, "  "))
		f.close()

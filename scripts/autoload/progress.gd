extends Node
## 이야기 진행과 능력. (세이브는 14단계에서 이 내용을 저장한다)

signal flag_changed(flag: String, value: bool)
signal ability_gained(ability: String)

## 진행 깃발: boss_bird_defeated, met_tia ...
var flags := {}
## 얻은 능력: double_jump, wind, lantern ...
var abilities := {}
## 고른 영혼 기술: "seed"(처음부터) / "wind" / "light". 소녀는 방마다 새로 만들어지므로 선택은 여기 둔다 (세이브에도 들어간다).
var soul := "seed"
## 다음 방에서 소녀가 설 자리 (RoomExit 가 정한다). 비어 있으면 방의 기본 자리.
var next_spawn := ""
## 지금 보여 줄 회상 (memories.json 의 키)과 끝난 뒤 돌아갈 방.
var pending_memory := ""
var memory_return_scene := ""
## 성장 보상 누적: max_hp(+체력), attack(+배수, 0.1 = 10%), dews(+개수), heal(+회복량)
## dews 는 상한 없이 받은 만큼 다 센다. 실제 이슬 개수는 dew_max() — 아래 '이슬 상한'.
## 단계 기록도 여기에 둔다: stat_<kind>_level (성장 메뉴, 빛 가루), tok_<줄> (기술 메뉴, 새순 — 아래 '새순').
var upgrades := {}
## 피워 둔 달빛풀: id -> {"scene": 경로, "name": 표시 이름}
var grasses := {}
## 마지막으로 쉰 달빛풀 {"id", "scene", "name"}. 메뉴에서 '지금 저장하기'를 누르면 여기서 이어진다.
var last_grass := {}
## 구원한 사람들 (id)
var rescued := {}
## 지도: 가 본 방 (room_id -> offset, size, name, region, grasses, boss)
var visited_rooms := {}
## 고른 엔딩: sacrifice / return
var ending := ""
## 모은 것·부순 것 (id -> true): 아이템(pick_<방>_<번호>), 비밀 벽·천장(secret_<방>_<번호>).
## 한 번 모으거나 부순 것은 다시 와도 그대로다.
var collected := {}
## 재화 '빛 가루': 적을 쓰러뜨리거나 정화하면 떨어지고, 달빛풀에서 성장에 쓴다 (2026-10-19 기획자 요청).
var dust := 0
## 영혼별 남은 쿨다운(초). 소녀가 방마다 새로 만들어져도 이어진다 (저장하지 않음).
var soul_cooldowns := {}
signal dust_changed(amount: int)
signal tokens_changed(n: int)
## 새 업그레이드 재화 '새순'(토큰). 이슬 최대치 보상 자리·보스 첫 정화에서 나온다. (저장됨)
var tokens := 0
## 난이도 (저장 칸마다, 저장됨): Balance.DIFFICULTIES
var difficulty := "normal"
## 쓰러뜨린 일반 적: room_id -> {spawn_key(String): true}. 달빛풀에서 쉬면 비운다. 저장하지 않음.
var killed := {}
## 방을 옮길 때 이어지는 체력·이슬 (-1 = 가득 채움). 저장하지 않음.
var carry_hp := -1.0
var carry_dews := -1


func add_dust(n: int) -> void:
	if n == 0:
		return
	dust = maxi(dust + n, 0)
	dust_changed.emit(dust)


func spend_dust(n: int) -> bool:
	if n > dust:
		return false
	dust -= n
	dust_changed.emit(dust)
	return true

signal upgraded(kind: String, amount: float)
## 무언가를 모으거나 부쉈다 (숨은 아이템이 나타나고, 지도의 탐사 수가 바뀐다).
signal collected_changed(id: String)


func is_collected(id: String) -> bool:
	return collected.get(id, false)


func collect(id: String) -> void:
	if id == "" or is_collected(id):
		return
	collected[id] = true
	collected_changed.emit(id)


func add_upgrade(kind: String, amount: float) -> void:
	upgrades[kind] = upgrades.get(kind, 0.0) + amount
	upgraded.emit(kind, amount)
	ability_gained.emit("upgrade")


# ---------- 이슬 상한 (v1.1.0 기획자 요청 16: 이슬 최대 8 → 5) ----------
# 이슬 방울은 기본 BASE_DEWS 개 + 성장(upgrades["dews"])이지만 MAX_DEWS 개를 넘지 않는다.
# v1.1.0 부터 이슬을 늘리는 길은 달빛풀 성장 메뉴의 이슬 2단계뿐이다 (기본 3 + 2 = 5). 예전의 이슬 최대치 보상 9곳
# (숨은 구슬 3 · 이슬잔 3 · 구원 보상 2 · 중간 보스 1)은 모두 새순(토큰)을 준다 — 아래 '새순'.
# 옛 저장 파일(v1, 예: dews 12)은 SaveMigrate.after_load 가 이슬 성장을 성장 메뉴 단계(최대 2)로 맞추고 나머지를 새순으로 돌려준다.
# 넘침 규칙(넘친 이슬 하나 = 회복량 +DEW_OVERFLOW_HEAL)은 안전망으로 남긴다 — 정상 진행에서는 넘칠 일이 없다.
# 성장 메뉴(StatMenu)는 이슬이 가득하면 이슬 줄에 '가득'을 보이고 팔지 않는다.
const BASE_DEWS := 3
const MAX_DEWS := 5
const DEW_OVERFLOW_HEAL := 10.0


## 받은 이슬을 상한 없이 모두 센 수 (기본 포함)
func dew_total() -> int:
	return BASE_DEWS + roundi(float(upgrades.get("dews", 0.0)))


## 실제 이슬 방울 최대 개수 (MAX_DEWS 를 넘지 않음)
func dew_max() -> int:
	return mini(dew_total(), MAX_DEWS)


## 상한을 넘어 회복량으로 바뀐 이슬 수
func dew_overflow() -> int:
	return maxi(dew_total() - MAX_DEWS, 0)


## 이슬이 가득 찼다 (이제 받는 이슬은 회복량으로 바뀐다)
func dews_full() -> bool:
	return dew_total() >= MAX_DEWS


## 방금 받은 이슬 성장 amount 개 가운데 넘쳐서 회복량으로 바뀐 개수. add_upgrade("dews", amount) 뒤에 부른다.
func dew_overflow_of(amount: float) -> int:
	var before := dew_total() - roundi(amount)
	return clampi(dew_overflow() - maxi(before - MAX_DEWS, 0), 0, maxi(roundi(amount), 0))


## 회복량 성장 합: 회복량 보상(upgrades["heal"]) + 넘친 이슬. 소녀의 회복량 = 45 + 이것.
func heal_bonus() -> float:
	return float(upgrades.get("heal", 0.0)) + dew_overflow() * DEW_OVERFLOW_HEAL


func has(flag: String) -> bool:
	return flags.get(flag, false)


func set_flag(flag: String, value := true) -> void:
	flags[flag] = value
	flag_changed.emit(flag, value)


func has_ability(ability: String) -> bool:
	return abilities.get(ability, false)


func gain_ability(ability: String) -> void:
	if has_ability(ability):
		return
	abilities[ability] = true
	ability_gained.emit(ability)


# ---------- v1.1.0 새순(토큰) · 기술 단계 · 최대 스태미너 (기획자 요청 15·16·18) ----------
# 새순은 일반 공격·영혼 기술(씨앗·바람·빛)·최대 스태미너를 한 단계씩 다듬는 데 쓴다. 단계는 upgrades["tok_<줄>"] 에 둔다
# (upgrades 는 통째로 저장되고 보스 러시의 몸에도 그대로 복사되므로 따로 저장할 것이 없다).
const TOKEN_TRACKS := ["normal", "seed", "wind", "light", "stamina"]
const TOKEN_MAX_LEVEL := 3
## 다음 단계 비용 (Lv1, Lv2, Lv3). 합계 19 = 얻을 수 있는 새순 19 — 모두 모으면 모든 기술이 최대.
## 새순이 나오는 곳 (19): 숨은 구슬 3 × 1 (canopy_01 · canopy_07 · mine_01), 이슬잔 3 × 2 (숨겨진 방 셋),
## 구원 보상 2 × 1 (정원사 루나 · 수액 어부), 정원사 장로(중간 보스) 2, 보스 첫 정화 6 (새 1 · 펌프 2 · 기사 1 · 여왕 1 · 뿌리지기 1).
const TOKEN_COST := {"normal": [1, 1, 2], "seed": [1, 1, 2], "wind": [1, 1, 2], "light": [1, 1, 2], "stamina": [1, 1, 1]}
## 단계별 배율 [Lv0, Lv1, Lv2, Lv3]
const SKILL_DAMAGE := {"normal": [1.0, 1.06, 1.12, 1.20], "seed": [1.0, 1.10, 1.20, 1.30], "wind": [1.0, 1.10, 1.20, 1.30], "light": [1.0, 1.08, 1.16, 1.25]}
const SKILL_RANGE := {"normal": [1.0, 1.05, 1.10, 1.15], "seed": [1.0, 1.05, 1.10, 1.15]}
const SKILL_COOLDOWN := {"wind": [1.0, 0.95, 0.90, 0.80], "light": [1.0, 0.93, 0.86, 0.79]}
const STAMINA_BASE := 100.0
const STAMINA_PER_LEVEL := 3.0
## 보스 첫 정화 때 주는 새순 (깃발 "tokens_<defeat_flag>" 로 한 번만; 보스 러시 제외)
const BOSS_TOKENS := {"boss_bird_defeated": 1, "boss_pump_defeated": 2, "boss_knight_defeated": 1, "boss_queen_defeated": 1, "boss_root_defeated": 1}
const SCRIPTURES := ["scripture_1", "scripture_2", "scripture_3", "scripture_4"]


func add_tokens(n: int) -> void:
	tokens = maxi(tokens + n, 0)
	tokens_changed.emit(tokens)


func spend_tokens(n: int) -> bool:
	if n < 0 or n > tokens:
		return false
	tokens -= n
	tokens_changed.emit(tokens)
	return true


## 그 줄을 몇 단계 다듬었나 (0~3)
func token_level(track: String) -> int:
	return int(upgrades.get("tok_" + track, 0))


## 다음 단계 비용. 이미 최대거나 없는 줄이면 -1
func token_next_cost(track: String) -> int:
	var costs: Array = TOKEN_COST.get(track, [])
	var lv := token_level(track)
	if lv < 0 or lv >= TOKEN_MAX_LEVEL or lv >= costs.size():
		return -1
	return int(costs[lv])


## 한 단계 다듬기: 새순을 내고 단계를 올린다. 모자라거나 최대면 false (아무것도 바뀌지 않음)
func buy_token_level(track: String) -> bool:
	var cost := token_next_cost(track)
	if cost < 0 or not spend_tokens(cost):
		return false
	var key := "tok_" + track
	upgrades[key] = float(token_level(track) + 1)   # 저장 파일(JSON)에서 읽으면 어차피 실수 — 처음부터 실수로 둔다
	upgraded.emit(key, 1.0)
	ability_gained.emit("upgrade")
	return true


## 단계 표에서 지금 단계의 값 (표에 없는 줄이면 1.0)
func _token_table_value(table: Dictionary, track: String) -> float:
	var t: Array = table.get(track, [])
	if t.is_empty():
		return 1.0
	return float(t[clampi(token_level(track), 0, t.size() - 1)])


func skill_damage_mult(track: String) -> float:
	return _token_table_value(SKILL_DAMAGE, track)


func skill_range_mult(track: String) -> float:
	return _token_table_value(SKILL_RANGE, track)


func skill_cooldown_mult(track: String) -> float:
	return _token_table_value(SKILL_COOLDOWN, track)


## 최대 스태미너: 100 + 3 × 단계 → 100 / 103 / 106 / 109
func max_stamina() -> float:
	return STAMINA_BASE + STAMINA_PER_LEVEL * clampi(token_level("stamina"), 0, TOKEN_MAX_LEVEL)


## 보스를 처음 정화했을 때의 새순. 보스 러시 중이거나 이미 받았으면 0. 아니면 깃발을 세우고 준 수를 돌려준다.
func grant_boss_tokens(defeat_flag: String) -> int:
	if BossRush.active:
		return 0
	var n := int(BOSS_TOKENS.get(defeat_flag, 0))
	if n <= 0:
		return 0
	var f := "tokens_" + defeat_flag
	if has(f):
		return 0
	set_flag(f)
	add_tokens(n)
	return n


# ---------- v1.1.0 쓰러뜨린 일반 적 (달빛풀에서 쉬기 전까지 다시 나타나지 않음, 기획자 요청 13) ----------

func is_killed(room_id: String, key: String) -> bool:
	var room: Dictionary = killed.get(room_id, {})
	return room.get(key, false)


func mark_killed(room_id: String, key: String) -> void:
	if not killed.has(room_id):
		killed[room_id] = {}
	killed[room_id][key] = true


func clear_killed() -> void:
	killed.clear()


# ---------- v1.1.0 경전 조각 (진엔딩 조건, 기획자 요청 25·27) ----------

## 경전 조각 n(1부터)을 읽었나
func scripture_read(n: int) -> bool:
	return has("read_scripture_%d" % n)


func scripture_count() -> int:
	var c := 0
	for i in SCRIPTURES.size():
		if scripture_read(i + 1):
			c += 1
	return c


func has_all_scriptures() -> bool:
	return scripture_count() >= SCRIPTURES.size()


## 수액의 여왕을 정화하고 얻는 영구 패시브 '수액의 맥동' (기획자 요청 17)
func has_sap_pulse() -> bool:
	return has_ability("sap_pulse")


## v1.1.1: 수액의 여왕을 정화하고 얻는 또 하나의 영구 패시브 '수액의 숨결' — 끊긴 스태미너 회복이 다시 시작되기까지 ×0.75
## (Player.regen_delay). 능력 하나(참/거짓)라 여러 번 받아도 겹치지 않는다. 옛 저장은 SaveMigrate.grant_boss_passives 가 채운다.
func has_sap_breath() -> bool:
	return has_ability("sap_breath")


## 테스트용 초기화.
func reset() -> void:
	flags.clear()
	abilities.clear()
	soul = "seed"
	upgrades.clear()
	grasses.clear()
	last_grass = {}
	rescued.clear()
	visited_rooms.clear()
	collected.clear()
	dust = 0
	soul_cooldowns.clear()
	next_spawn = ""
	# v1.1.0: 새 필드와, 전에는 남던 값들 (저장 칸을 바꾸거나 새로 시작할 때 앞 진행이 새지 않게)
	tokens = 0
	difficulty = "normal"
	killed.clear()
	carry_hp = -1.0
	carry_dews = -1
	ending = ""
	pending_memory = ""
	memory_return_scene = ""
	if has_meta("iron_pump_remains"):
		remove_meta("iron_pump_remains")

class_name SaveMigrate
extends RefCounted
## 저장 파일 판 올림. SaveGame.load_game 이 Progress 를 다 채운 뒤 부른다.
##
## v1 → v2 (v1.1.0 기획자 요청 16·17): 이슬 최대치가 8 → 5 로 줄고, 이슬 최대치 보상 9곳(숨은 구슬 3·이슬잔 3·
## 구원 보상 2·중간 보스 1)이 모두 새 재화 '새순'으로 바뀌었다. 옛 파일은 그 보상을 이미 이슬로 받아 upgrades.dews 에 합쳐
## 세어 두었으므로, 무엇을 모았는지(collected·깃발)를 보고 새순으로 돌려준다. 모은 기록·깃발은 그대로 둔다 → 다시 줍거나
## 다시 받을 수 없다(중복 없음).
##   1) 모은 숨은 구슬 ×1 + 모은 이슬잔 ×2 + 받은 구원 보상 ×1 + 정원사 장로 ×2 → 새순
##      (구원했지만 아직 말을 걸지 않아 보상을 안 받은 사람(reward_due 만 있음)은 세지 않는다 — 말을 걸면 새 보상(새순)을 받는다)
##   2) 성장 메뉴 이슬 단계가 3 이면 2 로 낮추고 3단계 값(빛 가루 280)을 돌려준다. 이슬 성장 = 성장 메뉴 단계(최대 2)
##   3) 이미 정화한 보스의 첫 정화 새순 (Progress.BOSS_TOKENS, 깃발 tokens_<보스 깃발> 로 한 번만)
##   4) 수액의 여왕을 정화했으면 영구 패시브 '수액의 맥동'
##   5) 옛 조건(네 능력)으로 선 five_souls 깃발은 새 진엔딩 조건이 아니면 내린다 (통합 때 추가)
## v2 이상 파일은 아무것도 하지 않는다. 이슬 상한은 Progress.dew_max() 가 늘 5 로 자른다.
## 진행을 불러오지 않고 저장 파일만 읽는 곳(보스 러시의 '저장된 성장', 저장 칸 요약 등)은 migrate_data(읽은 사전)로 같은 규칙을 쓸 수 있다.

## 옛 이슬 보상 자리 (pickup_id) — 지금은 새순을 준다
const ORB_IDS := ["pick_canopy_01_1", "pick_canopy_07_1", "pick_mine_01_1"]
const CUP_IDS := ["pick_canopy_hidden_1_1", "pick_village_hidden_2_1", "pick_flooded_mine_hidden_1_1"]
## 구원 보상을 받았다는 깃발 (RescuedHomes.GIVEN + id)
const RESCUE_FLAGS := ["rewarded_gardener_canopy", "rewarded_fisher_lake"]
const MINIBOSS_FLAG := "miniboss_elder_gardener_defeated"
## 하나당 새순 (지금 보상과 같은 값: 구슬 1 · 이슬잔 2 · 구원 1 · 정원사 장로 2)
const TOKENS_ORB := 1
const TOKENS_CUP := 2
const TOKENS_RESCUE := 1
const TOKENS_MINIBOSS := 2
## 성장 메뉴 이슬 줄: v1.1.0 최대 단계와, 없어진 v1.0 3단계의 값 (120 + 80×2) — 돌려주는 빛 가루
const DEW_STAT_MAX := 2
const DEW_STAT_REFUND := 280


## 불러온 진행(Progress) 위에서 판을 올린다 (SaveGame.load_game 이 맨 끝에 부른다).
static func after_load(from_version: int) -> void:
	if from_version >= 2:
		return
	var out := _v1_to_v2(Progress.flags, Progress.abilities, Progress.upgrades, Progress.collected)
	if int(out["dust"]) > 0:
		Progress.add_dust(int(out["dust"]))
	if int(out["tokens"]) > 0:
		Progress.add_tokens(int(out["tokens"]))


## 읽기만 한 저장 파일 사전(JSON)을 그 자리에서 판 2 로 고친다. Progress 는 건드리지 않는다. 이미 판 2 면 그대로.
static func migrate_data(data: Dictionary) -> void:
	if int(data.get("version", 1)) >= 2:
		return
	for k in ["flags", "abilities", "upgrades", "collected"]:
		if not data.get(k) is Dictionary:
			data[k] = {}
	var out := _v1_to_v2(data["flags"], data["abilities"], data["upgrades"], data["collected"])
	data["dust"] = int(data.get("dust", 0)) + int(out["dust"])
	data["tokens"] = int(data.get("tokens", 0)) + int(out["tokens"])
	data["version"] = 2


## v1 → v2 규칙 (위 1~4). 사전들을 그 자리에서 고치고, 더할 값 {"tokens": 새순, "dust": 빛 가루} 를 돌려준다.
static func _v1_to_v2(flags: Dictionary, abilities: Dictionary, upgrades: Dictionary, collected: Dictionary) -> Dictionary:
	var tokens := 0
	var dust := 0
	# 1) 이슬 최대치 보상 → 새순
	tokens += _count(collected, ORB_IDS) * TOKENS_ORB + _count(collected, CUP_IDS) * TOKENS_CUP
	tokens += _count(flags, RESCUE_FLAGS) * TOKENS_RESCUE
	if flags.get(MINIBOSS_FLAG, false):
		tokens += TOKENS_MINIBOSS
	# 2) 성장 메뉴 이슬 단계 (최대 2) — 이슬 성장은 이제 이것뿐
	var lv := int(upgrades.get("stat_dews_level", 0))
	if lv > DEW_STAT_MAX:
		upgrades["stat_dews_level"] = DEW_STAT_MAX
		dust += DEW_STAT_REFUND * (lv - DEW_STAT_MAX)
	upgrades["dews"] = float(clampi(lv, 0, DEW_STAT_MAX))
	# 3) 이미 정화한 보스의 첫 정화 새순 (불러오기 중이라 보스 러시 검사 없이 직접)
	for flag in Progress.BOSS_TOKENS:
		var tf := "tokens_" + str(flag)
		if flags.get(flag, false) and not flags.get(tf, false):
			flags[tf] = true
			tokens += int(Progress.BOSS_TOKENS[flag])
	# 4) 수액의 여왕 → 수액의 맥동
	if flags.get("boss_queen_defeated", false):
		abilities["sap_pulse"] = true
	# 5) 옛 '다섯 영혼'(네 능력) 조건으로 선 five_souls 는 새 진엔딩 조건(뿌리지기 정화 + 경전 조각 네 장)이 아니면 내린다
	#    (티아의 진엔딩 대사가 잠긴 장치와 어긋나지 않게; 조건이 차면 EndingChoice 가 다시 세운다)
	if flags.get("five_souls", false) and not _third_unlocked_in(flags):
		flags.erase("five_souls")
	return {"tokens": tokens, "dust": dust}


## EndingChoice.third_unlocked() 와 같은 조건을 깃발 사전으로 (뿌리지기 정화 + read_scripture_1~4)
static func _third_unlocked_in(flags: Dictionary) -> bool:
	if not flags.get("boss_root_defeated", false):
		return false
	for id in Progress.SCRIPTURES:
		if not flags.get("read_" + str(id), false):
			return false
	return true


## ids 가운데 사전에 참으로 들어 있는 수
static func _count(d: Dictionary, ids: Array) -> int:
	var n := 0
	for id in ids:
		if d.get(id, false):
			n += 1
	return n

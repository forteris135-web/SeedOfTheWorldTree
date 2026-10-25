class_name SaveMigrate
extends RefCounted
## 저장 파일 판 올림. SaveGame.load_game 이 Progress 를 다 채운 뒤 부른다.
##
## v1 → v2 (v1.1.0 기획자 요청 16·17, 명세 §5.5): 이슬 최대치가 8 → 5 로 줄고, 이슬 최대치 보상 9곳(숨은 구슬 3·이슬잔 3·
## 구원 보상 2·중간 보스 1)이 모두 새 재화 '새순'으로 바뀌었다. 옛 파일은 그 보상을 이미 이슬로 받아 upgrades.dews 에 합쳐
## 세어 두었으므로, 무엇을 모았는지(collected·깃발)를 보고 새순으로 돌려준다. 모은 기록·깃발은 그대로 둔다 → 다시 줍거나
## 다시 받을 수 없다(중복 없음).
##   1) 모은 숨은 구슬 ×1 + 모은 이슬잔 ×2 + 받은 구원 보상 ×1 + 정원사 장로 ×2 → 새순
##      (구원했지만 아직 말을 걸지 않아 보상을 안 받은 사람(reward_due 만 있음)은 세지 않는다 — 말을 걸면 새 보상(새순)을 받는다)
##   2) 성장 메뉴 이슬 단계가 3 이면 2 로 낮추고 3단계 값(빛 가루 280)을 돌려준다. 이슬 성장 = 성장 메뉴 단계(최대 2)
##   3) 이미 정화한 보스의 첫 정화 새순 (Progress.BOSS_TOKENS, 깃발 tokens_<보스 깃발> 로 한 번만)
##   4) 수액의 여왕을 정화했으면 영구 패시브 '수액의 맥동'
## v2 이상 파일은 아무것도 하지 않는다. 이슬 상한은 Progress.dew_max() 가 늘 5 로 자른다.

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


static func after_load(from_version: int) -> void:
	if from_version < 2:
		_v1_to_v2()


## v1 → v2. 돌려주는 값: 이번에 준 새순 수 (시험용).
static func _v1_to_v2() -> int:
	var given := 0
	# 1) 이슬 최대치 보상 → 새순
	var n_orb := _count_collected(ORB_IDS)
	var n_cup := _count_collected(CUP_IDS)
	var n_res := 0
	for f in RESCUE_FLAGS:
		if Progress.has(f):
			n_res += 1
	var n_mini := 1 if Progress.has(MINIBOSS_FLAG) else 0
	given += n_orb * TOKENS_ORB + n_cup * TOKENS_CUP + n_res * TOKENS_RESCUE + n_mini * TOKENS_MINIBOSS
	# 2) 성장 메뉴 이슬 단계 (최대 2) — 이슬 성장은 이제 이것뿐
	var lv := int(Progress.upgrades.get("stat_dews_level", 0))
	if lv > DEW_STAT_MAX:
		Progress.upgrades["stat_dews_level"] = DEW_STAT_MAX
		Progress.add_dust(DEW_STAT_REFUND * (lv - DEW_STAT_MAX))
	Progress.upgrades["dews"] = float(clampi(lv, 0, DEW_STAT_MAX))
	# 3) 이미 정화한 보스의 첫 정화 새순 (불러오기 중이라 보스 러시 검사 없이 직접)
	for flag in Progress.BOSS_TOKENS:
		var tf := "tokens_" + str(flag)
		if Progress.has(flag) and not Progress.has(tf):
			Progress.flags[tf] = true
			given += int(Progress.BOSS_TOKENS[flag])
	if given > 0:
		Progress.add_tokens(given)
	# 4) 수액의 여왕 → 수액의 맥동
	if Progress.has("boss_queen_defeated"):
		Progress.abilities["sap_pulse"] = true
	return given


static func _count_collected(ids: Array) -> int:
	var n := 0
	for id in ids:
		if Progress.is_collected(id):
			n += 1
	return n

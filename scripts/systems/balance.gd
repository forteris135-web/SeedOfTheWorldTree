class_name Balance
extends RefCounted
## v1.1.0 적·보스 능력치와 난이도 (기획자 요청 8·9). 숫자는 이 파일 한 곳.
## v1.1.1: v1.1.0 의 Hard 가 새 Normal — 모든 적 체력·공격력에 BASE_MULT 1.15 를 한 번 곱한다 (난이도 배율은 새 Normal 기준 그대로).
const ATK_BASE := 1.45                 # 모든 일반 몹·보스 기본 공격력 +45%
const BASE_MULT := 1.15                # v1.1.1 새 Normal 기준 (= v1.1.0 Hard). 체력·공격 모두, 난이도와 따로 한 번만
const TIER_STEP := 1.10                # 던전 단계마다 체력·공격력 ×1.1 누적
## 지역 → 던전 단계 (펌프 재배치 뒤; 잠긴 채굴장 입구가 채굴장 안이므로 채굴장과 같은 2)
const REGION_TIER := {"canopy": 0, "village": 1, "mine": 2, "flooded_mine": 2, "sap_lake": 3, "abyss": 4}
const DIFFICULTIES := ["easy", "normal", "hard", "nightmare"]
const DIFF_MULT := {"easy": 0.7, "normal": 1.0, "hard": 1.15, "nightmare": 1.3}
const DIFF_NAME := {"easy": "Easy", "normal": "Normal", "hard": "Hard", "nightmare": "Nightmare"}
const DIFF_DESC := {"easy": "적 체력·공격력 70%", "normal": "기본 능력치", "hard": "적 체력·공격력 115%", "nightmare": "적 체력·공격력 130%"}
## 몸통 부딪힘(8)은 배율을 받지 않는다 (2026-10-19 기획자 고정값 유지, D6)
const SCALE_CONTACT := false
## 벽 부수기의 전투 효과(방패·장갑 깨기) 끔 — 초반 능력이 되므로 탐색 전용 (D15)
const WALL_BREAK_COMBAT := false
## v1.1.1 보스별 추가 배율 (난이도·던전 단계 배율 뒤에 한 번 더 곱한다). hp = 최대 체력(_ready 에서 한 번),
## atk = 그 보스 자신의 공격(근접·투사체·가시 …; 방의 몹은 아님). 뿌리지기 atk_phase2 = 2페이즈(체력 50% 이하) 공격에 더하는 몫(합연산: 1 + 0.15 + 0.10 = ×1.25).
## 등불 기사는 기준점이라 그대로(×1). 뿌리지기 값은 root_keeper.gd 가 읽는다.
const BOSS_EXTRA := {"bird": {"hp": 1.10, "atk": 1.05}, "knight": {"hp": 1.0, "atk": 1.0}, "pump": {"hp": 1.15, "atk": 1.10}, "queen": {"hp": 1.15, "atk": 1.05}, "root": {"hp": 1.35, "atk": 1.15, "atk_phase2": 0.10}}
## v1.1.1 영혼 기술이 보스(group "boss" 다섯)에게 닿을 때만의 피해 배율: 바람·빛(던지는 영혼) −20%, 씨앗 베기 +10%.
## 중간 보스·몹, 기본 피해와 쿨다운은 그대로. HitData.for_target 이 복사본에 곱한다.
const SOUL_VS_BOSS := {"seed": 1.10, "wind": 0.8, "light": 0.8}
## 시험용: 비어 있지 않으면 지역 대신 이 값
static var region_override := ""


static func difficulty() -> String:
	return Progress.difficulty if DIFF_MULT.has(Progress.difficulty) else "normal"


static func diff_mult() -> float:
	return DIFF_MULT[difficulty()]


static func tier_of(region: String) -> int:
	return int(REGION_TIER.get(region, 0))


## node 가 속한 방의 지역 (조상 중 Room → current_scene 이 Room → "canopy")
static func region_of(node: Node = null) -> String:
	if region_override != "":
		return region_override
	var n := node
	while n != null:
		if n is Room:
			return (n as Room).region
		n = n.get_parent()
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.current_scene is Room:
		return (tree.current_scene as Room).region
	return "canopy"


## 체력 배율 (일반 몹·중간 보스·보스 공통) = 1.15(새 Normal 기준) × 1.1^단계 × 난이도. 첫 던전(단계 0) Normal 은 ×1.15
static func hp_mult(region: String) -> float:
	return BASE_MULT * pow(TIER_STEP, tier_of(region)) * diff_mult()


## 적이 주는 피해 배율 = 1.45 × 1.15(새 Normal 기준) × 1.1^단계 × 난이도
static func atk_mult(region: String) -> float:
	return ATK_BASE * BASE_MULT * pow(TIER_STEP, tier_of(region)) * diff_mult()


## 보스별 추가 배율 (BOSS_EXTRA[boss][key], 없으면 1.0). key = "hp" / "atk" / "atk_phase2"
static func boss_extra(boss: String, key: String) -> float:
	var row = BOSS_EXTRA.get(boss, {})
	return float(row.get(key, 1.0)) if row is Dictionary else 1.0


## 보스 자신의 공격 피해 값(이름들)에 추가 공격 배율 k 를 한 번 곱한다. 보스 _ready 에서 부른다 —
## 씬을 새로 만들 때마다 씬의 원래 값에서 시작하므로 다시 들어와도(재도전·보스 러시) 겹쳐 곱해지지 않는다.
## 배열(기사 3연격 같은)은 칸마다 곱한다.
static func scale_boss_damage(boss: Object, names: Array, k: float) -> void:
	if is_equal_approx(k, 1.0):
		return
	for n in names:
		var v = boss.get(n)
		if v is float or v is int:
			boss.set(n, float(v) * k)
		elif v is Array:
			var arr: Array = (v as Array).duplicate()   # 씬이 나눠 쓰는 배열을 고치지 않게 복사본에 (타입 배열은 타입 그대로)
			for i in arr.size():
				arr[i] = float(arr[i]) * k
			boss.set(n, arr)


## 영혼 기술이 보스에게 닿을 때의 피해 배율 (soul = HitData.soul; 영혼 기술이 아니면 1.0)
static func soul_vs_boss(soul: String) -> float:
	return float(SOUL_VS_BOSS.get(soul, 1.0))


## 소녀가 받는 피해 (Player.receive_hit 이 부른다). hit.scaled == false 면 원래 값.
static func incoming_damage(hit: HitData, victim: Node) -> float:
	if not hit.scaled:
		return hit.damage
	return hit.damage * atk_mult(region_of(victim))

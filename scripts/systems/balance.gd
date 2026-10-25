class_name Balance
extends RefCounted
## v1.1.0 적·보스 능력치와 난이도 (기획자 요청 8·9). 숫자는 이 파일 한 곳.
const ATK_BASE := 1.45                 # 모든 일반 몹·보스 기본 공격력 +45%
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


## 체력 배율 (일반 몹·중간 보스·보스 공통). 첫 던전(단계 0)·새는 ×1.0 × 난이도
static func hp_mult(region: String) -> float:
	return pow(TIER_STEP, tier_of(region)) * diff_mult()


## 적이 주는 피해 배율 = 1.45 × 1.1^단계 × 난이도
static func atk_mult(region: String) -> float:
	return ATK_BASE * pow(TIER_STEP, tier_of(region)) * diff_mult()


## 소녀가 받는 피해 (Player.receive_hit 이 부른다). hit.scaled == false 면 원래 값.
static func incoming_damage(hit: HitData, victim: Node) -> float:
	if not hit.scaled:
		return hit.damage
	return hit.damage * atk_mult(region_of(victim))

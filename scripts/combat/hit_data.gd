class_name HitData
extends RefCounted
## 한 번의 공격이 담고 있는 정보.

## 체력 피해
var damage := 10.0
## 흐트러짐 피해
var poise := 10.0
## 밀려나는 힘. x는 "공격자에게서 멀어지는 쪽"이 양수.
var knockback := Vector2(300, -120)
## 공격한 쪽 (방향 계산용)
var source: Node2D
## 가드로 막을 수 있는가 (붉은 예고 공격은 false)
var guardable := true
## 저스트 가드로 받아칠 수 있는가. 몸통 부딪힘은 false — 몸이 닿은 것을 '받아친' 것으로 치면
## 적 몸에 겹친 채 박자 맞춰 가드만 눌러도 적이 무너졌다 (2026-10-19 검수). false 면 일반 가드로 막는다.
var parryable := true
## 소녀의 공격인가
var from_player := false
## 저스트 가드로 되받은 투사체인가 (보스의 슈퍼아머·무너짐 뒤 흐트러짐 면역을 지나간다 — 기술의 보상은 그대로)
var reflected := false
## 맞았을 때 히트스톱 길이 (초)
var hitstop := 0.05
## 적·보스 능력치 배율(Balance: 기본 +45% × 던전 단계 × 난이도)을 받는가. false = Balance 배율 제외 — 몸통 부딪힘·환경.
## (copy() 는 스크립트 변수를 모두 복사하므로 이 값도 함께 복사된다)
var scaled := true
## 소녀의 낙하 공격(내려꽂기·착지 충격)인가. 보스·중간 보스는 PlungeDecay 로 4초 창 안의 거듭된 낙하 공격을 줄인다.
var plunge := false
## 소녀 쪽 공중 연속 감쇠가 이미 곱한 비율 (피해 0.6^k, 흐트러짐 0 또는 1). PlungeDecay 가 두 규칙을 곱하지 않고 센 쪽 하나만 쓰려고 읽는다.
var plunge_chain_damage := 1.0
var plunge_chain_poise := 1.0
## 소녀의 영혼 기술이면 그 영혼 ("seed" 씨앗 베기 / "wind" 바람 / "light" 빛), 아니면 "". v1.1.0 맞딜 검수 2: 보스가 영혼 기술을
## 따로 셀 때 읽는다 (잿빛 잎새의 새: 공중에서 맞은 씨앗 베기는 지침을 덜 쌓는다).
var soul := ""


static func make(p_damage: float, p_poise: float, p_source: Node2D, p_knockback := Vector2(300, -120)) -> HitData:
	var h := HitData.new()
	h.damage = p_damage
	h.poise = p_poise
	h.source = p_source
	h.knockback = p_knockback
	return h


## 같은 내용의 새 HitData. Hitbox 는 한 번의 휘두름에 닿은 모든 상대에게 **같은 객체**를 넘기므로,
## 상대마다 값을 바꿔 쓰고 싶으면(경비병 박힘 중 흐트러짐 2배 등) 원본을 고치지 말고 이것으로 복사해 쓴다.
## (필드를 하나하나 적지 않고 스크립트 변수 전부를 복사한다 — 나중에 필드가 늘어도 빠지지 않는다.)
func copy() -> HitData:
	var h := HitData.new()
	for p in get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			h.set(p.name, get(p.name))
	return h


## v1.1.1: 이 공격이 target 에게 닿을 때 쓸 HitData (Hurtbox.receive 가 부른다). 소녀의 영혼 기술이 보스(group "boss" 다섯)에
## 닿으면 복사본에 Balance.soul_vs_boss 배율(바람·빛 ×0.8, 씨앗 베기 ×1.1)을 곱해 돌려준다. 그 밖(중간 보스·몹·영혼 기술이
## 아닌 공격)은 자기 자신 그대로 — 원본(여럿이 함께 받는 객체)과 기본 피해 수치는 고치지 않는다.
func for_target(target: Node) -> HitData:
	if soul == "" or not from_player or target == null or not target.is_in_group("boss"):
		return self
	var k := Balance.soul_vs_boss(soul)
	if is_equal_approx(k, 1.0):
		return self
	var h := copy()
	h.damage = damage * k
	return h

class_name PlungeDecay
extends RefCounted
## 보스·중간 보스의 '낙하 공격 감쇠' 시계 (v1.1.0 최종 검수 — 맞딜 방지, 기획자 요청 8 마지막 문장).
## 낙하 공격은 스태미너를 쓰지 않는다(명세 2.1). 소녀 쪽의 공중 연속 감쇠(Player.plunge_repeat_*)는 바닥을 디디면 처음으로 돌아가서,
## '점프 → 낙하 한 번 → 착지'만 거듭하는 봇이 낙하마다 피해·흐트러짐을 온전히 받아 무쇠 펌프를 6판 중 5판 이겼다.
## 그래서 보스(와 중간 보스)는 자기 몸에 맞은 낙하 공격을 **시간으로** 센다 (착지와 상관없이):
##   - 앞 낙하 공격이 맞은 뒤 WINDOW(4초) 안에 또 맞으면 n 이 하나씩 오른다 (n = 이 창 안에서 앞서 맞은 낙하 공격 수).
##   - 그 한 대의 피해 × DAMAGE_RATIO^n (1 → 0.6 → 0.36 …), 흐트러짐 × POISE_RATIO^n (1 → 0.5 → 0.25 …).
##   - WINDOW 초 동안 낙하 공격이 한 번도 안 맞으면 처음(n = 0)으로. 내려꽂기와 착지 충격 모두 센다.
##   - 소녀 쪽 공중 연속 감쇠와는 **곱하지 않는다**: 둘 중 더 많이 줄이는 쪽 하나만 (공중에서 튕기며 거듭 맞힌 것은 이 창에서도 세어지므로).
##     일반 몹은 이 시계가 없어서 지금 규칙(공중 연속 감쇠만) 그대로다.
## 가끔 쓰는 낙하 공격(4초에 한 번 이하)은 늘 온전히 들어간다 — 거듭 쓰는 것만 줄어든다.
## 쓰는 법: 보스마다 하나(var plunge := PlungeDecay.new()), 매 물리 틱 tick(delta), receive_hit 맨 앞에서 hit = plunge.apply(hit),
## 싸움을 처음으로 돌릴 때 reset().

## 낙하 공격 사이 이 시간(초)이 지나면 처음으로
const WINDOW := 4.0
const DAMAGE_RATIO := 0.6
const POISE_RATIO := 0.5

## 시험용 스위치 (tools/probe_facetank --good 이 끈 것과 켠 것을 견준다). 게임에서는 늘 true.
static var enabled := true

## 이 창에서 맞은 낙하 공격 수
var count := 0
## 마지막 낙하 공격이 맞은 뒤 흐른 게임 시간 (초)
var since := INF


func tick(delta: float) -> void:
	since += delta
	if since >= WINDOW:
		count = 0


func reset() -> void:
	count = 0
	since = INF


## 다음 낙하 공격에 곱할 피해 비율 (시험·설명용; 공중 연속 감쇠는 빼고)
func next_damage_ratio() -> float:
	return pow(DAMAGE_RATIO, count) if since < WINDOW else 1.0


## 맞은 공격을 고쳐 돌려준다. 낙하 공격이 아니면 그대로. 고칠 때는 복사본 (Hitbox 는 같은 HitData 를 여러 상대에게 넘긴다).
## 보스가 이 앞에서 곱한 배수(중간 보스 휘청 뒤 ×1.5 등)는 그대로 남는다 — 이미 들어간 소녀 쪽 비율만 견주어 바꾼다.
func apply(hit: HitData) -> HitData:
	if not hit.plunge or not enabled:
		return hit
	if since >= WINDOW:
		count = 0
	var n := count
	count += 1
	since = 0.0
	if n == 0:
		return hit
	var wd := pow(DAMAGE_RATIO, n)
	var wp := pow(POISE_RATIO, n)
	var h := hit.copy()
	var cd := maxf(hit.plunge_chain_damage, 0.0001)
	if wd < cd:
		h.damage = hit.damage * wd / cd
	var cp := hit.plunge_chain_poise
	if cp > 0.0 and wp < cp:
		h.poise = hit.poise * wp / cp
	return h

class_name CrowdMeter
extends RefCounted
## 근접 압박 계량기 (v1.1.0 기획자 요청 8 마지막 문장: "보스의 공격 패턴을 무시하고 맞으면서 공격하는 방식으로 쉽게 승리할 수 없게").
## 보스마다 하나. 소녀가 보스 몸 가까이(|dx| ≤ range, |dy| < 300)에 붙어 있는 동안 시간이 쌓이고,
## 떨어지면 절반 빠르기로 식는다. trigger 초가 쌓이면(ready) 보스는 다음 공격으로 '응징 공격'(몸 둘레를 치는 공격)을 고르고 비운다(consume).
## 응징 공격: 새 날개 털기(땅에서) · 기사 SLAM · 뿌리지기 STOMP/뿌리 창 · 여왕 수액 터뜨리기(내려앉은 동안) · 펌프 VENT
## (맞딜 검수 2: 기사·뿌리지기·펌프는 첫 타격 뒤에도 소녀가 이 자리 안에 남아 있으면 둘째 — covers()).
## 패턴을 읽고 빠졌다 들어오는 소녀(붙어 있는 시간 < trigger)는 응징을 받지 않는다.

## 기본 쌓임 한도(초). 맞딜 승인 시험(tools/probe_facetank)이 통과하지 못하면 1.8 로 (명세 3.7 사다리 2단계).
const TRIGGER := 1.8
## 세로 거리 한도 (px)
const MAX_DY := 300.0

## 이 거리(px, 가로) 안이면 '붙어 있다'
var range_px := 280.0
## 소녀가 보스 발밑보다 **위**에 있을 때의 세로 한도 (px). 기본은 MAX_DY 와 같다.
## 무쇠 펌프는 몸 위(공중)에서 뛰며 낙하 공격만 거듭하는 소녀도 '붙어 있다'로 센다 (v1.1.0 최종 검수 — 몸 위가 안전지대였다).
var max_up := MAX_DY
## 소녀가 이만큼(px, 보스 발밑에서 소녀 가운데까지) 넘게 위에 있으면 above_mult 배로 쌓인다. 기본 above_mult 1 = 꺼짐.
## 무쇠 펌프: 피스톤·물기가 닿지 않는 몸 위(가지 위·공중)에 머무는 소녀에게 김 분출을 더 빨리 (v1.1.0 최종 검수).
var above_px := INF
var above_mult := 1.0
var trigger := TRIGGER
## 쌓인 시간 (초)
var t := 0.0


func _init(r := 280.0, trig := TRIGGER) -> void:
	range_px = r
	trigger = trig


## 등 뒤에 붙어 있으면 이만큼 빨리 쌓인다 (보스 등 뒤에 달라붙어 패턴을 피하며 때리는 것이 가장 쉬운 맞딜이다)
const BEHIND_MULT := 1.5

## 매 물리 틱. grounded_boss: 보스가 지금 공격할 수 있는 상태(무너짐·쓰러짐·등장이 아님)이고, 나는 보스라면 땅에 있을 때만 true.
## facing: 보스가 보는 쪽(±1, 0 이면 앞뒤를 가리지 않는다) — 소녀가 등 뒤면 BEHIND_MULT 배로 쌓인다.
func tick(delta: float, boss_pos: Vector2, player_pos: Vector2, grounded_boss: bool, facing := 0) -> void:
	var dx := player_pos.x - boss_pos.x
	var dy := player_pos.y - boss_pos.y
	if grounded_boss and absf(dx) <= range_px and dy < MAX_DY and -dy < max_up:
		var mult := BEHIND_MULT if facing != 0 and dx * float(facing) < -20.0 else 1.0
		if -dy > above_px:
			mult = maxf(mult, above_mult)
		t += delta * mult
	else:
		t = maxf(t - 0.5 * delta, 0.0)


## 소녀가 지금 '붙어 있다'의 자리 안인가 (가로 range_px, 세로 위 max_up·아래 MAX_DY — tick 과 같은 자리, 보스 상태는 보지 않는다).
## v1.1.0 맞딜 검수 2: 응징 공격의 둘째 타격(뿌리지기 두 번 내려찍기·기사 두 번 내려찍기·펌프 두 번 김 분출)은 첫 타격 뒤에도
## 소녀가 이 자리 안에 남아 있을 때만 — 예고를 보고 빠진 소녀에게는 오지 않는다.
func covers(boss_pos: Vector2, player_pos: Vector2) -> bool:
	var dx := player_pos.x - boss_pos.x
	var dy := player_pos.y - boss_pos.y
	return absf(dx) <= range_px and dy < MAX_DY and -dy < max_up


func ready() -> bool:
	return t >= trigger


func consume() -> void:
	t = 0.0


func reset() -> void:
	t = 0.0

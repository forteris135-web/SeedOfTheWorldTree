class_name PerchMeter
extends RefCounted
## 높은 자리 계량기 (v1.1.0 맞딜 검수 — 가지 위 진치기 막기). 보스마다 하나 (수액의 여왕·뿌리지기).
## 소녀가 보스의 바닥선보다 height_px 넘게 높은 곳(가지 위, 또는 그 높이의 공중)에 머무는 동안 시간이 쌓이고,
## 내려오면 절반 빠르기로 식는다. trigger 초가 쌓이면(ready) 보스는 다음 공격으로 '높은 자리 응징'을 고르고 비운다(consume):
##   여왕: 소녀가 선 가지로 내려앉기(가지 내려앉기 — 착지 충격 예고 = 판정, 주황, 가드 가능, 한 박 앉았다 곧 날아오름)
##   뿌리지기: 소녀 발밑에서 가지 높이까지 솟는 큰 뿌리 가시(예고 기둥 = 판정, 주황, 가드 가능)
## 근접 압박 계량기(CrowdMeter)는 보스 몸 둘레(|dy| < 300)만 보므로, 가지 위에서 원거리 영혼만 쏘는 소녀에게는 차지 않았다
## (최종 검수: 가지 위 봇이 여왕 6판 중 6판, 뿌리지기 6판 중 3판을 이김).

## 소녀 발밑이 보스 바닥선보다 이만큼(px) 넘게 높으면 '높은 자리' (가지는 260~380, 땅에서 한 번 뛴 점프 꼭대기는 약 260)
const HEIGHT_PX := 200.0
## 쌓임 한도 (초)
const TRIGGER := 2.5

var height_px := HEIGHT_PX
var trigger := TRIGGER
## 쌓인 시간 (초)
var t := 0.0


func _init(trig := TRIGGER, h := HEIGHT_PX) -> void:
	trigger = trig
	height_px = h


## 소녀 발밑이 바닥선 ground_y 보다 몇 px 위인가
static func height_of(player: Node2D, ground_y: float) -> float:
	return ground_y - (player.global_position.y + BossRush.FOOT_OFFSET)


## 매 물리 틱. active: 보스가 지금 공격할 수 있는 상태(무너짐·쓰러짐·등장·응징 중이 아님).
## 높은 자리면 쌓이고, 그보다 낮은 공중(뛰어오르고 내려오는 중)이면 그대로 두고, 땅에 서 있으면(또는 보스가 쉬는 중이면) 절반 빠르기로 식는다
## — 제자리에서 점프·이단 점프로 떠 있으며 싸우는 소녀(꼭대기만 높은 자리)도 쌓이고, 물결을 넘으려 가끔 뛰는 소녀는 땅에서 식는다.
func tick(delta: float, ground_y: float, player: Node2D, active: bool) -> void:
	if active and player and height_of(player, ground_y) > height_px:
		t += delta
	elif active and player is CharacterBody2D and not (player as CharacterBody2D).is_on_floor():
		pass
	else:
		t = maxf(t - 0.5 * delta, 0.0)


func ready() -> bool:
	return t >= trigger


func consume() -> void:
	t = 0.0


func reset() -> void:
	t = 0.0

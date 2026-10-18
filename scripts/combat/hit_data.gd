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
## 소녀의 공격인가
var from_player := false
## 맞았을 때 히트스톱 길이 (초)
var hitstop := 0.05


static func make(p_damage: float, p_poise: float, p_source: Node2D, p_knockback := Vector2(300, -120)) -> HitData:
	var h := HitData.new()
	h.damage = p_damage
	h.poise = p_poise
	h.source = p_source
	h.knockback = p_knockback
	return h

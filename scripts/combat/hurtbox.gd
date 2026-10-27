class_name Hurtbox
extends Area2D
## 맞는 영역. 주인(부모)의 receive_hit(hit, hurtbox) 를 불러 결과를 돌려준다.

var owner_node: Node


func _ready() -> void:
	owner_node = get_parent()
	monitoring = false
	monitorable = true


## v1.1.1: 영혼 기술이 보스에게 닿으면 보스 전용 배율을 곱한 복사본으로 (HitData.for_target — 그 밖에는 hit 그대로)
func receive(hit: HitData) -> String:
	if owner_node and owner_node.has_method("receive_hit"):
		return owner_node.receive_hit(hit.for_target(owner_node), self)
	return "ignored"

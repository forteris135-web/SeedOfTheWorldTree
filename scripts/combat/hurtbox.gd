class_name Hurtbox
extends Area2D
## 맞는 영역. 주인(부모)의 receive_hit(hit, hurtbox) 를 불러 결과를 돌려준다.

var owner_node: Node


func _ready() -> void:
	owner_node = get_parent()
	monitoring = false
	monitorable = true


func receive(hit: HitData) -> String:
	if owner_node and owner_node.has_method("receive_hit"):
		return owner_node.receive_hit(hit, self)
	return "ignored"

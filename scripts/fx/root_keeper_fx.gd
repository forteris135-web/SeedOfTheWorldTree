extends "res://scripts/fx/skill_fx.gd"
## '뿌리지기' 기술 이펙트 (이펙트 리뉴얼 F2). root_keeper.gd 의 _ready 가 붙인다. 판정·움직임은 건드리지 않는다.
## 뿌리 가시·뿌리 손·씨앗·달빛 구슬·충격파·뿌리 벽은 각자의 노드(root_*.gd)가 기획자 그림으로 그린다. 여기는 그 밖의 순간들:
##  - 지팡이 휘두르기: 꽃잎 섞인 보랏빛 초승달 (되돌려 베기는 위아래 뒤집어 올려 벤다)
##  - 달빛 구슬: 지팡이 머리의 번쩍임 / 달빛 고리: 퍼지는 달빛 고리
##  - 내려찍기(가드 불가): 붉은 뿌리 덩어리 터짐 + 붉은 고리 / 가드 불가 예고 동안 몸·손 자리에서 붉은 불티
##  - 2페이즈 다시 일어서기: 감아 오르는 달빛 기둥

func _on_state(_old: int, _new: int) -> void:
	if state_name() == "RISE":
		Fx.spawn("rise_pillar", boss.global_position)


func _on_phase(_st: int, _old: String, new: String) -> void:
	if new != "active":
		return
	var f := facing()
	match state_name():
		"SWEEP":
			Fx.spawn("staff_arc", ahead(150.0, -160.0), {"facing": f, "rot": 20.0})
		"SWEEP2":
			Fx.spawn("staff_arc", ahead(150.0, -180.0), {"facing": f, "rot": -25.0, "flip_v": true})
		"ORBS":
			Fx.spawn("orb_charge", boss.orb_origin())
		"STOMP":
			Fx.spawn("root_stomp", boss.global_position)
		"RING":
			Fx.spawn("ring_flash", boss.global_position + Vector2(0, -200))
		"WALL":
			Fx.spawn("root_burst_fx", ahead(120.0, 0.0), {"facing": f, "palette": "danger", "keep": 0.5})


func _tick(delta: float) -> void:
	if not boss.is_red():
		return
	if every("red", 0.09, delta):
		Fx.spawn("danger_ember", body_point(randf_range(0.1, 0.9), 400.0) + Vector2(randf_range(-80.0, 80.0), 0.0))
	# 뿌리 손 예고: 손이 솟을 자리에서 붉은 불티가 오른다 (예고 고리는 보스 그림·늦게 솟는 손이 그린다)
	if state_name() == "HAND" and every("hand", 0.07, delta):
		for x in boss.hand_targets:
			Fx.spawn("danger_ember", Vector2(float(x) + randf_range(-90.0, 90.0), float(boss.ground_y) - 6.0))

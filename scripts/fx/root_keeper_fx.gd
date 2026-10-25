extends "res://scripts/fx/skill_fx.gd"
## '뿌리지기' 기술 이펙트 (이펙트 리뉴얼 F2). root_keeper.gd 의 _ready 가 붙인다. 판정·움직임은 건드리지 않는다.
## 뿌리 가시·뿌리 손·씨앗·달빛 구슬·충격파·뿌리 벽은 각자의 노드(root_*.gd)가 기획자 그림으로 그린다. 여기는 그 밖의 순간들:
##  - 지팡이 휘두르기: 꽃잎 섞인 보랏빛 초승달 (되돌려 베기는 위아래 뒤집어 올려 벤다)
##  - 달빛 구슬: 지팡이 머리의 번쩍임 / 달빛 고리: 퍼지는 달빛 고리
##  - 내려찍기(가드 불가): 붉은 뿌리 덩어리 터짐 + 붉은 고리 / 가드 불가 예고 동안 몸·손 자리에서 붉은 불티
##  - 2페이즈 다시 일어서기: 감아 오르는 달빛 기둥
## 2026-10-20 통합: 지팡이에서 나는 이펙트는 뼈대 그림의 지팡이 머리·손 자리(vis_point — root_keeper_visual.fx_point)를 따른다.
## 휘두르기 초승달은 지팡이 머리가 그리는 호의 가운데(가슴 앞)에 크게 뜨고, 코드로 그린 보랏빛 띠는 껐다.

func _on_state(_old: int, _new: int) -> void:
	if state_name() == "RISE":
		Fx.spawn("rise_pillar", boss.global_position)


func _on_phase(_st: int, _old: String, new: String) -> void:
	if new != "active":
		return
	var f := facing()
	match state_name():
		"SWEEP", "SWEEP2":
			# v1.1.0 (기획자 요청 1): 지팡이 초승달 = 판정 사각형(미끄러짐 포함 — 공격 범위 예고와 같은 값) 그대로.
			# (예전엔 가슴 앞 250 에 1.3배로 떠 판정보다 약 200px 높았다.) 되돌려 베기는 위아래를 뒤집어 올려 벤다.
			var reach: Rect2 = boss.call("melee_reach") if boss.has_method("melee_reach") else Rect2()
			if reach.size != Vector2.ZERO:
				fit_fx("staff_arc", reach, f, 0.0, {"flip_v": state_name() == "SWEEP2"})
			else:
				_staff_arc(ahead(150.0, -160.0), 20.0, state_name() == "SWEEP2")
		"ORBS":
			Fx.spawn("orb_charge", vis_point("staff_head", boss.call("orb_origin") if boss.has_method("orb_origin") else body_point(1.0, 460.0)))
		"STOMP":
			var sr: Rect2 = boss.call("melee_reach") if boss.has_method("melee_reach") else Rect2()
			if sr.size != Vector2.ZERO:
				fit_fx("root_stomp", sr, 1, 0.0, {"ground_y": float(val("ground_y", boss.global_position.y))})   # 판정 ±130 그대로 (예전 ±80), 바닥 고리·먼지는 발밑 높이
			else:
				Fx.spawn("root_stomp", boss.global_position)
		"RING":
			Fx.spawn("ring_flash", boss.global_position + Vector2(0, -200))
		"WALL":
			Fx.spawn("root_burst_fx", ahead(120.0, 0.0), {"facing": f, "palette": "danger", "keep": 0.5})


func _tick(delta: float) -> void:
	if not red():
		return
	if every("red", 0.09, delta):
		Fx.spawn("danger_ember", body_point(randf_range(0.1, 0.9), 400.0) + Vector2(randf_range(-80.0, 80.0), 0.0))
	# 뿌리 손 예고: 손이 솟을 자리에서 붉은 불티가 오른다 (예고 고리는 보스 그림·늦게 솟는 손이 그린다)
	if state_name() == "HAND" and every("hand", 0.07, delta):
		for x in val("hand_targets", []):
			Fx.spawn("danger_ember", Vector2(float(x) + randf_range(-90.0, 90.0), float(val("ground_y", boss.global_position.y)) - 6.0))


## 지팡이 휘두르기 초승달: 지팡이 머리가 그리는 호의 가운데에 띄운다. 뼈대를 재 보면(2026-10-20) 휘두르기·되돌려 베기 모두
## 지팡이 머리가 앞 280~370px 를 지나며 머리 위 ↔ 앞 땅 사이를 도는데, 손이 자루를 따라 미끄러지는 축이 가슴 앞쪽이라
## 호의 가운데는 '가슴에서 앞으로 ARC_AHEAD, 가슴 높이'다 (타격이 시작될 때 손은 아직 머리 위라 손 기준이면 너무 높이 떴다).
## 가슴은 뼈대(몸 기울기·디딤)를 따라간다. 뼈대를 못 읽으면 예전 고정 자리 (fallback).
const ARC_AHEAD := 250.0
const ARC_SCALE := 1.3
func _staff_arc(fallback: Vector2, rot: float, flip: bool) -> void:
	var chest := vis_point("chest", Vector2.INF)
	var at := fallback
	var k := 1.0
	if chest.is_finite():
		at = Vector2(chest.x + float(facing()) * ARC_AHEAD, chest.y - 20.0)
		k = ARC_SCALE
	Fx.spawn("staff_arc", at, {"facing": facing(), "rot": rot, "flip_v": flip, "scale": k})

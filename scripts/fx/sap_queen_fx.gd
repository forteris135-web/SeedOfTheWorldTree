extends "res://scripts/fx/skill_fx.gd"
## '수액의 여왕' 기술 이펙트 (이펙트 리뉴얼 F2). sap_queen.gd 의 _ready 가 붙인다. 판정·움직임은 건드리지 않는다.
## 가루·나비 그림은 SapProjectile(look "queen_dust"/"queen_butterfly"), 물결 그림은 SapWave 노드가 그린다. 여기는 그 밖의 순간들:
##  - 날개가루: 날개에서 터지는 수액빛 별 + 반짝이 (2페이즈 반 박 뒤 한 번 더)
##  - 수액 물결: 내려오는 동안 몸에서 수액이 떨어지고, 셋째 박에 수면을 치는 물보라
##  - 나비 떼: 풀어 놓는 자리의 고리 / 춤추듯 내려앉기: 착지 물보라 / 날개 갈라짐(2페이즈): 흘러내리는 수액
##  - 하늘에 떠 있는 동안 가끔 날개에서 수액 방울이 떨어진다

const BODY := Vector2(0, -120)

var _prev_spawned := 0


func _on_state(old: int, _new: int) -> void:
	match state_name():
		"LANDED":
			Fx.spawn("queen_land", boss.global_position)
		"TAKEOFF":
			if state_is(old) == "LANDED" or state_is(old) == "BROKEN":
				Fx.spawn("sap_splash", boss.global_position, {"scale": 0.7})


func _on_phase(_st: int, _old: String, new: String) -> void:
	if new != "active":
		return
	match state_name():
		"DUST":
			Fx.spawn("wing_dust_burst", boss.global_position + BODY)
		"WAVE":
			Fx.spawn("sap_splash", Vector2(boss.global_position.x, float(val("surface_y", boss.global_position.y))), {"scale": 1.25})
		"BUTTERFLIES":
			Fx.spawn("butterfly_burst", ahead(90.0, -140.0))


func _tick(delta: float) -> void:
	var st := state_name()
	var body := boss.global_position + BODY
	match st:
		"DUST":
			# 2페이즈: 반 박 뒤 한 번 더 흩뿌린다 (_spawned 1 → 2)
			var sp := int(val("_spawned", 0))
			if sp == 2 and _prev_spawned == 1:
				Fx.spawn("wing_dust_burst", body, {"scale": 0.8})
			_prev_spawned = sp
		"WAVE":
			if String(val("attack_phase", "")) == "startup" and every("drip", 0.1, delta):
				Fx.spawn("sap_drip", body + Vector2(randf_range(-70.0, 70.0), randf_range(0.0, 50.0)))
		"CRACK":
			if every("crack", 0.06, delta):
				Fx.spawn("sap_drip", body + Vector2(randf_range(-110.0, 110.0), randf_range(-60.0, 40.0)))
				Fx.spawn("sap_glint", body + Vector2(randf_range(-120.0, 120.0), randf_range(-80.0, 40.0)))
		"HOVER":
			if every("idle_drip", 0.7, delta):
				Fx.spawn("sap_drip", body + Vector2(randf_range(-90.0, 90.0), randf_range(-20.0, 40.0)))
	if st != "DUST":
		_prev_spawned = 0

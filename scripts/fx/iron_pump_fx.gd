extends "res://scripts/fx/skill_fx.gd"
## '무쇠 펌프' 기술 이펙트 (이펙트 리뉴얼 F2). iron_pump.gd 의 _ready 가 붙인다. 판정·움직임은 건드리지 않는다.
## 수액 방울(SapBlob look "sap_blob" + 쏘는 순간 물줄기), 땅 충격파(Projectile look "pump_shock"), 수액 기둥(SapSpurt)은 각자 그린다.
##  - 피스톤(가드 불가): 예고 동안 김 구멍에서 붉은 김과 불티, 땅을 치면 물보라·왕관 물보라·김·고리
##  - 빨아들이기: 관으로 빨려 드는 물줄기 조각, 끝의 물기에 방울
##  - 장갑이 깨짐: 김이 터지고 불똥 / 휘청: 김
##  - 쉬는 동안 가끔 김을 뿜는다
## 2026-10-20 통합: 김 구멍·관 입·핵·피스톤 머리는 뼈대 그림의 자리(vis_point — iron_pump_visual.fx_point: vent·mouth·core)를 따른다.
## 아래 VENT·MOUTH 는 그림을 못 읽을 때의 예전 고정 자리.

## 김 구멍 자리 (발밑 기준, 앞 = +x)
const VENT := Vector2(-70.0, -330.0)
## 관 입 자리 (빨아들이기·물기)
const MOUTH := Vector2(250.0, -120.0)

var _prev_bit := false


func _ready() -> void:
	super._ready()
	if boss and boss.has_signal("slammed"):
		boss.slammed.connect(_on_slammed)


func _on_slammed() -> void:
	# v1.1.0 (기획자 요청 1): 피스톤 물보라 = 피스톤 판정 사각형 그대로 (예전엔 망치 머리 x≈391 에 떠 판정 가운데보다 130px 앞이었다)
	var reach: Rect2 = boss.call("melee_reach") if boss.has_method("melee_reach") else Rect2()
	if reach.size != Vector2.ZERO:
		fit_fx("pump_slam", reach, facing())
	else:
		var head := vis_point("piston", ahead(300.0, 0.0))
		Fx.spawn("pump_slam", Vector2(head.x, boss.global_position.y))


func _on_state(_old: int, _new: int) -> void:
	match state_name():
		"BROKEN":
			Fx.spawn("pump_break", vis_point("core", body_point(0.55, 420.0)))
		"STAGGER":
			for i in 4:
				Fx.spawn("steam_puff", _vent() + Vector2(randf_range(-40.0, 40.0), 0.0), {"scale": 1.3})


func _on_phase(_st: int, _old: String, new: String) -> void:
	if state_name() == "VENT" and new == "active":
		# 김 분출: 판정 사각형(몸 둘레 ±260, 높이 300) 그대로 김이 터진다
		var reach: Rect2 = boss.call("melee_reach") if boss.has_method("melee_reach") else Rect2()
		if reach.size != Vector2.ZERO:
			fit_fx("pump_vent", reach, facing())


func _tick(delta: float) -> void:
	var st := state_name()
	if st == "VENT" and String(val("attack_phase", "")) == "startup" and every("vent_warn", 0.08, delta):
		# 김 분출 예고: 김 구멍과 몸 둘레에서 주황 김이 새어 나온다 (막을 수 있는 공격 → 주황, 붉은빛은 가드 불가만)
		var v := _vent()
		Fx.spawn("vent_warn", v + Vector2(randf_range(-30.0, 30.0), 0.0))
		Fx.spawn("vent_leak", boss.global_position + Vector2(randf_range(-230.0, 230.0), randf_range(-260.0, -40.0)))
	if red():
		if every("red", 0.1, delta):
			var v := _vent()
			Fx.spawn("danger_vent", v + Vector2(randf_range(-20.0, 20.0), 0.0))
			Fx.spawn("danger_steam", v + Vector2(randf_range(-30.0, 30.0), -60.0))
			Fx.spawn("danger_ember", body_point(randf_range(0.2, 0.8), 420.0) + Vector2(randf_range(-120.0, 120.0), 0.0))
	match st:
		"SUCK":
			if String(val("attack_phase", "")) == "active" and not bool(val("_bit", false)) and every("suck", 0.06, delta):
				var mouth := _mouth()
				var from := mouth + Vector2(facing() * randf_range(160.0, 560.0), randf_range(-70.0, 90.0))
				var to := mouth - from
				Fx.spawn("suck_strip", from, {"vel": to / 0.42, "rot": rad_to_deg(to.angle()) + 180.0})
			var bit := bool(val("_bit", false))
			if bit and not _prev_bit:
				# v1.1.0: 물기 별빛 = 물기 판정 사각형 그대로 (예전엔 관 입 (417,-152) 에 떠 판정 앞끝에 겨우 걸쳤다)
				var reach: Rect2 = boss.call("melee_reach") if boss.has_method("melee_reach") else Rect2()
				if reach.size != Vector2.ZERO:
					fit_fx("pump_bite", reach, facing())
				else:
					Fx.spawn("pump_bite", _mouth())
			_prev_bit = bit
		"IDLE":
			if every("idle_steam", 1.1, delta):
				var v2 := _vent()
				Fx.spawn("vent_steam", v2)
				Fx.spawn("steam_puff", v2 + Vector2(0.0, -80.0))
	if st != "SUCK":
		_prev_bit = false


## 김 구멍 (뼈대의 탱크 꼭대기) / 관 입 (흡입 팔 끝) — 그림을 못 읽으면 예전 고정 자리
func _vent() -> Vector2:
	return vis_point("vent", ahead(VENT.x, VENT.y))


func _mouth() -> Vector2:
	return vis_point("mouth", ahead(MOUTH.x, MOUTH.y))

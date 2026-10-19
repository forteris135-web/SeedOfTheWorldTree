extends "res://scripts/fx/skill_fx.gd"
## '무쇠 펌프' 기술 이펙트 (이펙트 리뉴얼 F2). iron_pump.gd 의 _ready 가 붙인다. 판정·움직임은 건드리지 않는다.
## 수액 방울(SapBlob look "sap_blob" + 쏘는 순간 물줄기), 땅 충격파(Projectile look "pump_shock"), 수액 기둥(SapSpurt)은 각자 그린다.
##  - 피스톤(가드 불가): 예고 동안 김 구멍에서 붉은 김과 불티, 땅을 치면 물보라·왕관 물보라·김·고리
##  - 빨아들이기: 관으로 빨려 드는 물줄기 조각, 끝의 물기에 방울
##  - 장갑이 깨짐: 김이 터지고 불똥 / 휘청: 김
##  - 쉬는 동안 가끔 김을 뿜는다

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
	Fx.spawn("pump_slam", ahead(300.0, 0.0))


func _on_state(_old: int, _new: int) -> void:
	match state_name():
		"BROKEN":
			Fx.spawn("pump_break", body_point(0.55, 420.0))
		"STAGGER":
			for i in 4:
				Fx.spawn("steam_puff", ahead(VENT.x, VENT.y) + Vector2(randf_range(-40.0, 40.0), 0.0), {"scale": 1.3})


func _tick(delta: float) -> void:
	var st := state_name()
	if boss.is_red():
		if every("red", 0.1, delta):
			Fx.spawn("danger_vent", ahead(VENT.x, VENT.y) + Vector2(randf_range(-20.0, 20.0), 0.0))
			Fx.spawn("danger_steam", ahead(VENT.x, VENT.y - 60.0) + Vector2(randf_range(-30.0, 30.0), 0.0))
			Fx.spawn("danger_ember", body_point(randf_range(0.2, 0.8), 420.0) + Vector2(randf_range(-120.0, 120.0), 0.0))
	match st:
		"SUCK":
			if String(boss.attack_phase) == "active" and not bool(boss.get("_bit")) and every("suck", 0.06, delta):
				var mouth := ahead(MOUTH.x, MOUTH.y)
				var from := mouth + Vector2(facing() * randf_range(160.0, 560.0), randf_range(-70.0, 90.0))
				var to := mouth - from
				Fx.spawn("suck_strip", from, {"vel": to / 0.42, "rot": rad_to_deg(to.angle()) + 180.0})
			var bit := bool(boss.get("_bit"))
			if bit and not _prev_bit:
				Fx.spawn("pump_bite", ahead(MOUTH.x - 40.0, MOUTH.y))
			_prev_bit = bit
		"IDLE":
			if every("idle_steam", 1.1, delta):
				Fx.spawn("vent_steam", ahead(VENT.x, VENT.y))
				Fx.spawn("steam_puff", ahead(VENT.x, VENT.y - 80.0))
	if st != "SUCK":
		_prev_bit = false

extends "res://scripts/fx/skill_fx.gd"
## '등불 기사' 기술 이펙트 (이펙트 리뉴얼 F2). lantern_knight.gd 의 _ready 가 붙인다. 판정·움직임은 건드리지 않는다.
## 불꽃 그림은 기획자 이펙트 시트의 금빛·물 그림을 불꽃 팔레트("fire")로 바꿔 칠한 것 (시트에 불 그림이 없어 기획자 허락대로 응용).
##  - 창 찌르기: 창끝을 따라 앞으로 뻗는 불빛 줄기 (판정 상자 앞 470px 를 덮는다)
##  - 3연격: 찌르기 줄기 → 휘두르기 불꽃 초승달 → 올려치기(가드 불가) 진한 붉은 초승달
##  - 등불 휘두르기: 큰 불꽃 호 (불꽃 파도 그림은 Projectile look "knight_flame")
##  - 내려찍기(가드 불가): 예고 동안 몸에서 붉은 불티, 착지에 불꽃 터짐 + 붉은 고리 + 먼지
##  - 돌진: 뒤로 끌리는 불빛 줄기·먼지, 창이 박히면 불똥 / 등불 회전: 고리 한 겹마다 퍼지는 불꽃 고리
##  - 등불 던지기: 손의 불씨 (등불·불기둥 그림은 Projectile look "knight_lantern"/"knight_pillar", 붉은 예고 고리는 기사 논리가 띄운다)

var _prev_rings := 0
var _prev_wave_sent := false


func _on_state(_old: int, _new: int) -> void:
	match state_name():
		"STUCK":
			Fx.spawn("spear_stuck", ahead(380.0, -155.0), {"facing": facing()})
		"STAGGER":
			Fx.spawn("fire_ring", body_point(0.45, 330.0), {"scale": 0.8})
		"SPIN":
			_prev_rings = 0


func _on_phase(_st: int, _old: String, new: String) -> void:
	if new != "active":
		return
	var f := facing()
	match state_name():
		"THRUST":
			Fx.spawn("spear_thrust", ahead(-10.0, -155.0), {"facing": f})
		"COMBO3":
			match int(val("combo_step", 0)):
				0:
					Fx.spawn("spear_thrust", ahead(-10.0, -155.0), {"facing": f})
				1:
					Fx.spawn("spear_swing", ahead(150.0, -170.0), {"facing": f, "rot": 20.0})
				2:
					Fx.spawn("spear_upper", ahead(150.0, -220.0), {"facing": f})
		"FLAME":
			Fx.spawn("lantern_arc", ahead(130.0, -130.0), {"facing": f, "rot": 15.0})
		"SLAM":
			Fx.spawn("knight_slam", boss.global_position)
		"THROW":
			for i in 5:
				Fx.spawn("ember", ahead(80.0, -170.0) + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0)))


func _tick(delta: float) -> void:
	var st := state_name()
	# 가드 불가 예고 (내려찍기·올려치기): 몸에서 붉은 불티가 피어오른다
	if red() and every("red", 0.08, delta):
		Fx.spawn("danger_ember", body_point(randf_range(0.1, 0.9), 330.0) + Vector2(randf_range(-90.0, 90.0), 0.0))
	match st:
		"MARCH", "INTRO":
			# 폭주한 갑옷에서 불씨가 피어오른다
			if every("amb", 0.32, delta):
				Fx.spawn("ember", body_point(randf_range(0.35, 0.85), 330.0) + Vector2(randf_range(-70.0, 70.0), 0.0))
		"CHARGE":
			if String(val("attack_phase", "")) == "active":
				if every("streak", 0.05, delta):
					Fx.spawn("charge_streak", ahead(-20.0, -160.0), {"facing": facing()})
				if every("dust", 0.08, delta):
					Fx.spawn("dust_puff", ahead(-40.0, -10.0), {"vel": Vector2(-facing() * 160.0, -40.0)})
		"SPIN":
			var r := int(val("rings_sent", 0))
			while _prev_rings < r:
				_prev_rings += 1
				Fx.spawn("fire_ring", Vector2(boss.global_position.x, float(val("ground_y", boss.global_position.y)) - 30.0), {"scale": 1.0 + 0.15 * _prev_rings})
		"WAVE":
			var sent := bool(val("_wave_sent", false))
			if sent and not _prev_wave_sent and String(val("attack_phase", "")) == "active":
				Fx.spawn("wave_flash", ahead(150.0, -120.0), {"facing": facing()})
				Fx.spawn("spear_swing", ahead(140.0, -150.0), {"facing": facing(), "rot": 10.0, "scale": 1.1})
			_prev_wave_sent = sent
	if st != "WAVE":
		_prev_wave_sent = false

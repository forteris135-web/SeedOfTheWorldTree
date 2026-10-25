extends "res://scripts/fx/skill_fx.gd"
## '등불 기사' 기술 이펙트 (이펙트 리뉴얼 F2). lantern_knight.gd 의 _ready 가 붙인다. 판정·움직임은 건드리지 않는다.
## 불꽃 그림은 기획자 이펙트 시트의 금빛·물 그림을 불꽃 팔레트("fire")로 바꿔 칠한 것 (시트에 불 그림이 없어 기획자 허락대로 응용).
##  - 창 찌르기: 창끝을 따라 앞으로 뻗는 불빛 줄기 (판정 상자 앞 470px 를 덮는다)
##  - 3연격: 찌르기 줄기 → 휘두르기 불꽃 초승달 → 올려치기(가드 불가) 진한 붉은 초승달
##  - 등불 휘두르기: 큰 불꽃 호 (불꽃 파도 그림은 Projectile look "knight_flame")
##  - 내려찍기(가드 불가): 예고 동안 몸에서 붉은 불티, 착지에 불꽃 터짐 + 붉은 고리 + 먼지
##  - 돌진: 뒤로 끌리는 불빛 줄기·먼지, 창이 박히면 불똥 / 등불 회전: 고리 한 겹마다 퍼지는 불꽃 고리
##  - 등불 던지기: 손의 불씨 (등불·불기둥 그림은 Projectile look "knight_lantern"/"knight_pillar", 붉은 예고 고리는 기사 논리가 띄운다)
## 2026-10-20 통합: 창끝·등불·가슴에서 나는 이펙트는 뼈대 그림의 자리(vis_point — lantern_knight_visual.fx_point)를 따른다.
## 찌르기 줄기는 판정 앞 470px 를 덮도록 뒤끝 x 는 그대로 두고 높이만 창끝을 따른다. 휘두르기 초승달은 판정 상자 기준 그대로.
## 코드로 그린 창끝 띠(그림 쪽)는 껐다 — 기사의 공격은 이 그림 이펙트 한 겹으로 보인다 (등불 회전의 주황 등불 띠만 남김).

var _prev_rings := 0
var _prev_wave_sent := false
## 돌진 동안 기사를 따라다니는 창끝 불빛 [FxSprite, gen] (돌진이 끝나면 거둔다)
var _lance: Array = []


func _on_state(_old: int, _new: int) -> void:
	_end_lance()
	match state_name():
		"STUCK":
			Fx.spawn("spear_stuck", vis_point("spear_tip", ahead(380.0, -155.0)), {"facing": facing()})
		"STAGGER":
			Fx.spawn("fire_ring", vis_point("chest", body_point(0.45, 330.0)), {"scale": 0.8})
		"SPIN":
			_prev_rings = 0


## v1.1.0 (기획자 요청 1): 근접 공격 이펙트는 판정이 덮는 사각형(보스의 melee_reach — 공격 범위 예고와 같은 값)에 맞춰 띄운다.
func _on_phase(_st: int, _old: String, new: String) -> void:
	if new != "active":
		_end_lance()
		return
	var f := facing()
	var reach := _reach()
	match state_name():
		"THRUST":
			fit_fx("spear_thrust", reach, f)
		"COMBO3":
			match int(val("combo_step", 0)):
				0:
					fit_fx("spear_thrust", reach, f)
				1:
					fit_fx("spear_swing", reach, f)
				2:
					fit_fx("spear_upper", reach, f, -70.0)
		"WAVE":
			fit_fx("spear_swing", reach, f)
		"FLAME":
			# 근접 판정이 없다 → 근접 호 이펙트 없이 등불의 불씨만 (불꽃 파도 그림은 투사체가 그린다)
			var lan0 := vis_point("lantern", ahead(80.0, -170.0))
			for i in 4:
				Fx.spawn("ember", lan0 + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0)))
		"SLAM":
			fit_fx("knight_slam", reach, 1)
		"SPIN":
			fit_fx("knight_spin", reach, f)
		"CHARGE":
			# 돌진 판정(기사 앞 40~420)을 덮는 창끝 불빛이 기사를 따라간다
			var box: Rect2 = boss.call("charge_box") if boss.has_method("charge_box") else Rect2(40, -170, 380, 130)
			var hb: Node2D = val("hitbox")
			if hb:
				var fx := fit_fx("charge_lance", RangeTelegraph.box_world(hb, box, f), f, 0.0, {"follow": boss})
				if fx:
					_lance = [fx, fx.gen]
		"THROW":
			var lan := vis_point("lantern", ahead(80.0, -170.0))
			for i in 5:
				Fx.spawn("ember", lan + Vector2(randf_range(-20.0, 20.0), randf_range(-20.0, 20.0)))


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
			# 불꽃 고리 투사체가 나갈 때마다 고리가 나가는 두 자리(양쪽 바닥)에서 작은 불꽃 (고리 그림은 투사체가 그린다;
			# 예전의 넓은 바닥 불꽃 고리는 근접 판정(±230)보다 넓어 v1.1.0 에서 뺐다)
			var r := int(val("rings_sent", 0))
			while _prev_rings < r:
				_prev_rings += 1
				var gy := float(val("ground_y", boss.global_position.y))
				for d in [-1.0, 1.0]:
					Fx.spawn("fire_pillar_burst", Vector2(boss.global_position.x + d * 90.0, gy), {"scale": 0.6})
		"WAVE":
			var sent := bool(val("_wave_sent", false))
			if sent and not _prev_wave_sent and String(val("attack_phase", "")) == "active":
				# 검기가 생기는 자리(땅 가까이 앞 150) — 창끝은 이때 머리 위 높이라 따라가지 않는다 (검기와 번쩍임이 떨어져 보였다)
				Fx.spawn("wave_flash", ahead(150.0, -120.0), {"facing": facing()})
			_prev_wave_sent = sent
	if st != "WAVE":
		_prev_wave_sent = false


## 지금 근접 공격의 판정 구간 (보스의 melee_reach). 못 읽으면 앞쪽 기본 자리.
func _reach() -> Rect2:
	if boss.has_method("melee_reach"):
		var r: Rect2 = boss.call("melee_reach")
		if r.size != Vector2.ZERO:
			return r
	var c := ahead(200.0, -155.0)
	return Rect2(c - Vector2(230.0, 60.0), Vector2(460.0, 120.0))


func _end_lance() -> void:
	if _lance.size() == 2:
		Fx.end_soon(_lance[0], _lance[1])
	_lance = []

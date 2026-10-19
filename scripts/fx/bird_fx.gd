extends "res://scripts/fx/skill_fx.gd"
## '잿빛 잎새의 새' 기술 이펙트 (이펙트 리뉴얼 F2). gray_leaf_bird.gd 의 _ready 가 붙인다. 판정·움직임은 건드리지 않는다.
##  - 날갯바람(가드 불가): 예고 동안 새 몸에 붉은 바람 소용돌이가 모이고 붉은 불티가 피어오른다 → 바람이 부는 동안
##    화면을 가로지르는 붉은 금빛 바람 줄기·초승달과 굴러가는 잎
##  - 2페이즈 잎 회오리: 새 몸을 감싸 도는 잎 소용돌이
##  - 깃털 화살: 쏠 때마다 부리 앞 금빛 번쩍임 (깃털 그림은 Projectile 의 look "bird_feather")
##  - 내려앉기·날아오르기: 발밑 잎 무더기 / 날개 휘두르기: 잿빛 바람 초승달 / 부리 찍기: 부리 끝 별빛
##  - 잎 삼키기: 잎 더미에서 부리로 빨려 드는 잎, 끊기면 잎이 흩어진다

## 바람 줄기 간격 (초) — 아이폰 부담을 생각해 줄기는 성기게, 잎은 조금 촘촘히
const STREAK_GAP := 0.16
const CRESCENT_GAP := 0.09
const LEAF_GAP := 0.05
## 바람 줄기 빠르기 (px/초)
const STREAK_SPEED := 1700.0

var _prev_flash := 0.0
var _prev_stagger := 0.0
var _prev_crouch := false


func _on_state(old: int, _new: int) -> void:
	match state_name():
		"WIND":
			Fx.spawn("gust_gather", boss.body_center(), {"follow": boss, "offset": Vector2(0, -150), "life": float(boss.wind_telegraph)})
		"LEAF_RAIN":
			if int(boss.phase) == 2:
				var life := float(boss.leaf_rain_time)
				Fx.spawn("leaf_tornado", boss.body_center(), {"follow": boss, "offset": Vector2(0, -150), "life": life})
				Fx.spawn("leaf_tornado", boss.body_center(), {"follow": boss, "offset": Vector2(0, -150), "life": life, "flip_v": true, "scale": 0.72, "rot": 90.0})
		"GROUND_IDLE":
			if state_is(old) == "DESCEND":
				Fx.spawn("bird_land", boss.global_position)


func _on_phase(_st: int, _old: String, new: String) -> void:
	if new != "active":
		return
	match state_name():
		"SWEEP":
			Fx.spawn("wing_sweep", ahead(150.0, -110.0), {"facing": facing(), "rot": 30.0})
		"PECK":
			Fx.spawn("peck_burst", ahead(230.0, -60.0), {"facing": facing()})


func _tick(delta: float) -> void:
	var st := state_name()
	if st == "WIND":
		if boss.is_red():
			if every("ember", 0.1, delta):
				Fx.spawn("danger_ember", boss.body_center() + Vector2(randf_range(-140.0, 140.0), randf_range(-60.0, 80.0)))
		else:
			_blow(delta)
	# 깃털: 한 발 쏠 때마다 muzzle_flash 가 1 로 튄다
	var fl := float(boss.muzzle_flash)
	if fl > _prev_flash + 0.5:
		Fx.spawn("feather_flash", boss.muzzle_point())
	_prev_flash = fl
	# 잎 삼키기: 잎 더미에서 부리로 잎이 빨려 든다
	if st == "EAT" and every("suck", 0.12, delta):
		var pile = boss.get("_target_pile")
		if pile != null and is_instance_valid(pile):
			var from: Vector2 = pile.global_position + Vector2(randf_range(-80.0, 80.0), randf_range(-40.0, -8.0))
			var beak := ahead(170.0, -70.0)
			Fx.spawn("leaf_suck", from, {"vel": (beak - from) / 0.45})
	# 잎 삼키기를 끊었다 (움찔이 1 로 튄다): 부리 앞 잎이 흩어진다
	var sg := float(boss.stagger)
	if sg > _prev_stagger + 0.5:
		Fx.spawn("pile_burst", ahead(160.0, 0.0), {"scale": 0.8})
	_prev_stagger = sg
	# 날아오르기: 웅크렸다 박차는 순간 발밑에 잎이 터진다
	var cr := bool(boss.crouching)
	if _prev_crouch and not cr and st == "TAKEOFF":
		Fx.spawn("bird_land", boss.global_position, {"scale": 0.8})
	_prev_crouch = cr


## 날갯바람이 부는 동안: 바람 방향(_wind_dir)으로 화면을 가로지르는 줄기·초승달·잎
func _blow(delta: float) -> void:
	var dir := float(boss.get("_wind_dir"))
	if dir == 0.0:
		dir = 1.0
	var p: Node2D = boss.get("player")
	var center: Vector2 = p.global_position if p else boss.global_position
	var vel := Vector2(dir * STREAK_SPEED, 0.0)
	if every("streak", STREAK_GAP, delta):
		var at := Vector2(center.x - dir * randf_range(700.0, 1000.0), center.y - randf_range(-40.0, 620.0))
		Fx.spawn("gust_streak", at, {"facing": dir, "vel": Vector2(STREAK_SPEED, randf_range(-40.0, 40.0)), "rot": randf_range(-6.0, 6.0)})
	if every("crescent", CRESCENT_GAP, delta):
		var at2 := Vector2(center.x - dir * randf_range(500.0, 900.0), center.y - randf_range(0.0, 520.0))
		Fx.spawn("gust_crescent_fly", at2, {"facing": dir, "vel": Vector2(STREAK_SPEED * 1.1, 0.0)})
	if every("leaf", LEAF_GAP, delta):
		var at3 := Vector2(center.x - dir * randf_range(400.0, 1000.0), center.y - randf_range(-20.0, 600.0))
		Fx.spawn("gust_leaf", at3, {"vel": vel * randf_range(0.7, 1.0) + Vector2(0, randf_range(-80.0, 80.0))})

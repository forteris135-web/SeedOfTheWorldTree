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
## 기술이 끊기면(무너짐 등) 거둘 따라다니는 이펙트: [[FxSprite, gen], ...]
var _held: Array = []


func _on_state(old: int, _new: int) -> void:
	# 날갯바람·잎 회오리가 끝나거나 끊기면 따라다니던 소용돌이를 부드럽게 거둔다
	for h in _held:
		Fx.end_soon(h[0], h[1])
	_held.clear()
	match state_name():
		"WIND":
			_hold(Fx.spawn("gust_gather", body_point(0.5), {"follow": boss, "offset": Vector2(0, -150), "life": float(val("wind_telegraph", 0.8))}))
		"LEAF_RAIN":
			if int(val("phase", 1)) == 2:
				var life := float(val("leaf_rain_time", 3.5))
				_hold(Fx.spawn("leaf_tornado", body_point(0.5), {"follow": boss, "offset": Vector2(0, -150), "life": life}))
				_hold(Fx.spawn("leaf_tornado", body_point(0.5), {"follow": boss, "offset": Vector2(0, -150), "life": life, "flip_v": true, "scale": 0.72, "rot": 90.0}))
		"GROUND_IDLE":
			if state_is(old) == "DESCEND":
				Fx.spawn("bird_land", boss.global_position)


func _hold(fx: FxSprite) -> void:
	if fx:
		_held.append([fx, fx.gen])


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
		if red():
			if every("ember", 0.1, delta):
				Fx.spawn("danger_ember", body_point(0.5) + Vector2(randf_range(-140.0, 140.0), randf_range(-60.0, 80.0)))
		else:
			_blow(delta)
	# 깃털: 한 발 쏠 때마다 muzzle_flash 가 1 로 튄다
	var fl := float(val("muzzle_flash", 0.0))
	if fl > _prev_flash + 0.5 and boss.has_method("muzzle_point"):
		Fx.spawn("feather_flash", boss.call("muzzle_point"))
	_prev_flash = fl
	# 잎 삼키기: 잎 더미에서 부리로 잎이 빨려 든다
	if st == "EAT" and every("suck", 0.12, delta):
		var pile = val("_target_pile")
		if pile != null and is_instance_valid(pile):
			var from: Vector2 = pile.global_position + Vector2(randf_range(-80.0, 80.0), randf_range(-40.0, -8.0))
			var beak := ahead(170.0, -70.0)
			Fx.spawn("leaf_suck", from, {"vel": (beak - from) / 0.45})
	# 잎 삼키기를 끊었다 (움찔이 1 로 튄다): 부리 앞 잎이 흩어진다
	var sg := float(val("stagger", 0.0))
	if sg > _prev_stagger + 0.5:
		Fx.spawn("pile_burst", ahead(160.0, 0.0), {"scale": 0.8})
	_prev_stagger = sg
	# 날아오르기: 웅크렸다 박차는 순간 발밑에 잎이 터진다
	var cr := bool(val("crouching", false))
	if _prev_crouch and not cr and st == "TAKEOFF":
		Fx.spawn("bird_land", boss.global_position, {"scale": 0.8})
	_prev_crouch = cr


## 날갯바람이 부는 동안: 바람 방향(_wind_dir)으로 화면을 가로지르는 줄기·초승달·잎
func _blow(delta: float) -> void:
	var dir := float(val("_wind_dir", 1.0))
	if dir == 0.0:
		dir = 1.0
	var p: Node2D = val("player")
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

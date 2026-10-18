extends Sprite2D
## 새의 그림(boss_bird_now.png)을 상태에 맞춰 움직인다: 날갯짓, 기울기, 피격 번쩍임, 무너짐, 쓰러짐.

var _boss: GrayLeafBird
var _t := 0.0
var _base_scale := Vector2.ONE


func _ready() -> void:
	_boss = get_parent() as GrayLeafBird
	_base_scale = scale


func _process(delta: float) -> void:
	_t += delta
	if _boss == null:
		return
	flip_h = _boss.facing > 0
	var st := _boss.state
	var flap := 1.0
	var tilt := 0.0
	var offset_y := 0.0
	match st:
		GrayLeafBird.State.HOVER, GrayLeafBird.State.LEAF_RAIN, GrayLeafBird.State.INTRO, GrayLeafBird.State.TAKEOFF, GrayLeafBird.State.DESCEND:
			flap = 1.0 + sin(_t * 7.0) * 0.045
			tilt = clampf(_boss.velocity.x / 2500.0, -0.12, 0.12)
		GrayLeafBird.State.FEATHERS:
			flap = 1.0 + sin(_t * 18.0) * 0.03
			tilt = -0.08 * _boss.facing
		GrayLeafBird.State.WIND:
			flap = 1.0 + sin(_t * 22.0) * 0.08
			tilt = 0.18 * _boss.facing
		GrayLeafBird.State.EAT:
			tilt = 0.35 * _boss.facing
			offset_y = 40.0
		GrayLeafBird.State.SWEEP:
			tilt = -0.2 * _boss.facing
		GrayLeafBird.State.PECK:
			tilt = 0.3 * _boss.facing
		GrayLeafBird.State.BROKEN:
			tilt = 0.45 * _boss.facing
			offset_y = 60.0
		GrayLeafBird.State.FALLEN, GrayLeafBird.State.PURIFIED:
			tilt = 0.7 * _boss.facing
			offset_y = 90.0
	rotation = lerpf(rotation, tilt, 0.15)
	scale = Vector2(_base_scale.x, _base_scale.y * flap)
	offset.y = lerpf(offset.y, offset_y, 0.1)
	var f := _boss.flash_amount()
	var ash := Color(0.78, 0.8, 0.82) if _boss.phase == 1 else Color(0.7, 0.68, 0.7)
	modulate = ash.lerp(Color(2.0, 2.0, 2.0), f * 0.8)
	if st == GrayLeafBird.State.WIND and _boss._timer > _boss.wind_time:
		# 붉은 예고 (가드 불가)
		modulate = modulate.lerp(Color(2.2, 0.6, 0.5), 0.5 + 0.5 * sin(_t * 30.0))

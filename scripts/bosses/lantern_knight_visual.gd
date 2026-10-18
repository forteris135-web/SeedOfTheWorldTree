extends Sprite2D
## 등불 기사의 그림(boss_knight_now.png)을 상태에 맞춰 움직인다.

var _boss: LanternKnight
var _t := 0.0
var _base_scale := Vector2.ONE
var _base_pos := Vector2.ZERO
var _glow: PointLight2D


func _ready() -> void:
	_boss = get_parent() as LanternKnight
	_base_scale = scale
	_base_pos = position


func _process(delta: float) -> void:
	_t += delta
	if _boss == null:
		return
	var f := float(_boss.facing)
	var st := _boss.state
	var tilt := 0.0
	var sq := Vector2(1.0, 1.0 + sin(_t * 1.5) * 0.01)
	var dy := 0.0
	match st:
		LanternKnight.State.MARCH:
			var step := _t * 5.0
			dy = -absf(sin(step)) * 8.0
			tilt = 0.05 * f + sin(step) * 0.03
		LanternKnight.State.THRUST:
			match _boss.attack_phase:
				"startup": tilt = -0.18 * f * _boss.windup_progress; sq = Vector2(0.95, 1.04)
				"active": tilt = 0.25 * f; sq = Vector2(1.15, 0.92)
				_: tilt = 0.1 * f
		LanternKnight.State.FLAME:
			match _boss.attack_phase:
				"startup": tilt = -0.3 * f * _boss.windup_progress; dy = -12.0 * _boss.windup_progress
				"active": tilt = 0.35 * f; sq = Vector2(1.1, 0.94)
				_: tilt = 0.12 * f
		LanternKnight.State.SLAM:
			match _boss.attack_phase:
				"startup": dy = -70.0 * _boss.windup_progress; sq = Vector2(0.94, 1.1); tilt = sin(_t * 40.0) * 0.02 * _boss.windup_progress
				"active": dy = 24.0; sq = Vector2(1.2, 0.82)
				_: dy = 10.0; sq = Vector2(1.08, 0.94)
		LanternKnight.State.THROW:
			tilt = (-0.25 if _boss.attack_phase == "startup" else 0.2) * f
		LanternKnight.State.BROKEN:
			tilt = 0.4 * f
			dy = 40.0
			sq = Vector2(1.06, 0.9)
		LanternKnight.State.FALLEN, LanternKnight.State.PURIFIED:
			tilt = 0.85 * f
			dy = 110.0
	flip_h = _boss.facing > 0
	rotation = lerpf(rotation, tilt, 0.2)
	scale = Vector2(_base_scale.x * sq.x, _base_scale.y * sq.y)
	position = _base_pos + Vector2(0, dy)
	var fl := _boss.flash_amount()
	var base := Color(0.95, 0.9, 0.9) if _boss.phase == 1 else Color(1.1, 0.85, 0.75)
	if _boss.is_red():
		base = base.lerp(Color(2.4, 0.5, 0.4), 0.5 + 0.5 * sin(_t * 32.0))
	modulate = base.lerp(Color(2.5, 2.5, 2.5), fl * 0.8)

extends Sprite2D
## 뿌리지기의 그림(boss_rootkeeper_now.png)을 상태에 맞춰 움직인다. 가시 예고 자국도 그린다.

var _boss: RootKeeper
var _t := 0.0
var _base_scale := Vector2.ONE
var _base_pos := Vector2.ZERO
var _marks: Node2D


func _ready() -> void:
	_boss = get_parent() as RootKeeper
	_base_scale = scale
	_base_pos = position
	_marks = Node2D.new()
	_marks.top_level = true
	_marks.z_index = -1
	add_child(_marks)
	_marks.draw.connect(_draw_marks)


func _process(delta: float) -> void:
	_t += delta
	if _boss == null:
		return
	var f := float(_boss.facing)
	var st := _boss.state
	var tilt := 0.0
	var sq := Vector2(1.0, 1.0 + sin(_t * 1.2) * 0.012)
	var dy := 0.0
	match st:
		RootKeeper.State.STANCE:
			dy = sin(_t * 2.0) * 4.0
			tilt = 0.02 * f
		RootKeeper.State.SPIKES:
			match _boss.attack_phase:
				"startup": dy = -20.0 * _boss.windup_progress; tilt = -0.08 * f * _boss.windup_progress
				"active": dy = 14.0; sq = Vector2(1.08, 0.94)
				_: dy = 4.0
		RootKeeper.State.SWEEP:
			match _boss.attack_phase:
				"startup": tilt = -0.3 * f * _boss.windup_progress
				"active": tilt = 0.35 * f; sq = Vector2(1.12, 0.94)
				_: tilt = 0.1 * f
		RootKeeper.State.ORBS:
			tilt = -0.1 * f * (_boss.windup_progress if _boss.attack_phase == "startup" else 0.5)
			dy = -10.0
		RootKeeper.State.WALL:
			match _boss.attack_phase:
				"startup": tilt = -0.2 * f * _boss.windup_progress + sin(_t * 40.0) * 0.015
				"active": tilt = 0.4 * f; sq = Vector2(1.2, 0.9)
				_: tilt = 0.1 * f
		RootKeeper.State.RISE:
			var k := clampf(1.0 - _boss._timer / 3.0, 0.0, 1.0)
			dy = lerpf(120.0, -10.0, ease(k, 0.3))
			tilt = lerpf(0.6, 0.0, k) * f
			sq = Vector2(1.0, lerpf(0.8, 1.05, k))
		RootKeeper.State.BROKEN:
			tilt = 0.4 * f
			dy = 50.0
			sq = Vector2(1.06, 0.88)
		RootKeeper.State.FALLEN, RootKeeper.State.PURIFIED:
			tilt = 0.75 * f
			dy = 130.0
	flip_h = _boss.facing > 0
	rotation = lerpf(rotation, tilt, 0.2)
	scale = Vector2(_base_scale.x * sq.x, _base_scale.y * sq.y)
	position = _base_pos + Vector2(0, dy)
	var fl := _boss.flash_amount()
	var base := Color(0.9, 0.92, 1.0) if _boss.phase == 1 else Color(1.05, 0.95, 1.15)
	if _boss.is_red():
		base = base.lerp(Color(2.4, 0.5, 0.4), 0.5 + 0.5 * sin(_t * 32.0))
	modulate = base.lerp(Color(2.5, 2.5, 2.5), fl * 0.8)
	_marks.queue_redraw()


func _draw_marks() -> void:
	if _boss == null or _boss.state != RootKeeper.State.SPIKES or _boss.attack_phase != "startup":
		return
	var p := _boss.windup_progress
	for x in _boss.spike_marks:
		var pos := Vector2(x, _boss.ground_y)
		var w := 60.0 + 30.0 * p
		var pulse := 0.5 + 0.5 * sin(_t * (10.0 + p * 30.0))
		_marks.draw_rect(Rect2(pos + Vector2(-w / 2.0, -6), Vector2(w, 10)), Color(0.9, 0.7, 1.0, 0.25 + 0.45 * p * pulse))
		for i in 4:
			var ox := -w / 2.0 + w * (i + 0.5) / 4.0
			_marks.draw_line(pos + Vector2(ox, -2), pos + Vector2(ox, -14.0 - 30.0 * p), Color(0.85, 0.7, 1.0, 0.6 * p), 2.0)

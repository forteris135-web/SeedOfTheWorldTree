extends Sprite2D
## 새의 그림(boss_bird_now.png)을 상태에 맞춰 움직인다: 날갯짓, 기울기, 날개 휘두르기·부리 찍기, 착지·이륙, 무너짐, 쓰러짐.
## 원칙: 자세 값은 절대 '툭' 바뀌지 않는다. 매 프레임 '목표 자세'를 정하고 Motion.damp(프레임 독립)로 쫓는다.
## 날갯짓은 위상 누적기(_flap_phase += rate*delta)로 돌리고 rate/amp 만 목표로 수렴시켜 상태가 바뀌어도 이어진다.
## 그림 원본은 오른쪽을 본다 → 왼쪽을 볼 때 뒤집는다(scale.x 음수). 방향 전환은 몸을 틀며 1→0→−1 을 지난다.

## 자세 묶음: (기울기, 가로 찌그러짐, 세로 찌그러짐, 세로 오프셋)
const NEUTRAL := Vector4(0.0, 1.0, 1.0, 0.0)
const STRIDE := 110.0

var _boss: GrayLeafBird
var _t := 0.0
var _base_scale := Vector2.ONE
var _base_pos := Vector2.ZERO

var _pose := NEUTRAL
var _imp := 0.0
var _imp_v := 0.0
var _kick := 0.0
var _kick_v := 0.0
var _face := -1.0
var _red := 0.0
var _flap_phase := 0.0
var _flap_rate := 7.0
var _flap_amp := 0.0
var _dist := 0.0
var _last_step := 0
var _prev_state := -1
var _prev_phase := ""
var _prev_flash := 0.0
var _prev_stagger := 0.0
var _prev_crouch := false
var _was_on_floor := false
var _dust: CPUParticles2D
var _ghosts: Array[Sprite2D] = []
var _ghost_timer := 0.0


func _ready() -> void:
	_boss = get_parent() as GrayLeafBird
	_base_scale = scale
	_base_pos = position
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _boss:
		_face = float(_boss.facing)
		_boss.state_changed.connect(_on_state_changed)
	_dust = CPUParticles2D.new()
	_dust.top_level = true
	_dust.emitting = false
	_dust.one_shot = true
	_dust.explosiveness = 1.0
	_dust.amount = 10
	_dust.lifetime = 0.6
	_dust.direction = Vector2(0, -1)
	_dust.spread = 80.0
	_dust.gravity = Vector2(0, 200)
	_dust.initial_velocity_min = 80.0
	_dust.initial_velocity_max = 240.0
	_dust.scale_amount_min = 4.0
	_dust.scale_amount_max = 9.0
	_dust.color = Color(0.72, 0.7, 0.62, 0.5)
	add_child(_dust)
	for i in 3:
		var g := Sprite2D.new()
		g.texture = texture
		g.top_level = true
		g.visible = false
		g.show_behind_parent = true
		g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(g)
		_ghosts.append(g)


func _on_state_changed(st: GrayLeafBird.State) -> void:
	match st:
		GrayLeafBird.State.GROUND_IDLE:
			if _prev_state == GrayLeafBird.State.DESCEND:
				# 착지: 눌림 + 먼지
				_jolt(2.6, 0.8)
				_puff(18, 0.0)
		GrayLeafBird.State.BROKEN:
			_jolt(1.6, 3.0)
			_puff(12, 0.0)
		GrayLeafBird.State.FALLEN:
			_jolt(2.4, 2.0)
	_prev_state = st


## 충격: squash 양수 = 눌림, kick = 기울기 충격(바라보는 방향 기준, 양수 = 앞으로)
func _jolt(squash: float, kick: float) -> void:
	_imp_v += squash
	_kick_v += (kick * float(_boss.facing)) if _boss else kick


func _process(delta: float) -> void:
	_t += delta
	if _boss == null:
		return
	var f := float(_boss.facing)
	var st := _boss.state
	var ph := _boss.attack_phase
	var speed := absf(_boss.velocity.x)

	# ---- 일회성 사건 ----
	if ph != _prev_phase:
		if ph == "active":
			match st:
				GrayLeafBird.State.SWEEP:
					_puff(6, -f * 40.0)
				GrayLeafBird.State.PECK:
					_jolt(0.5, 1.5)
					_puff(6, -f * 50.0)
		_prev_phase = ph
	if _boss.stagger > 0.9 and _prev_stagger <= 0.9:
		_jolt(-1.0, -5.0)   # 잎 삼키기를 끊겼다: 뒤로 움찔
	_prev_stagger = _boss.stagger
	if _prev_crouch and not _boss.crouching:
		_jolt(-1.2, 0.0)    # 웅크림에서 튀어 오른다
		_puff(10, 0.0)
	_prev_crouch = _boss.crouching
	var fl := _boss.flash_amount()
	if fl > _prev_flash + 0.4 and st not in [GrayLeafBird.State.BROKEN, GrayLeafBird.State.FALLEN]:
		_jolt(0.3, -0.9)
	_prev_flash = fl
	# 쓰러지거나 무너져 떨어지다 바닥에 닿는 순간: 눌림 + 먼지
	var on_floor := _boss.is_on_floor()
	if on_floor and not _was_on_floor and st in [GrayLeafBird.State.FALLEN, GrayLeafBird.State.BROKEN]:
		_jolt(2.0, 1.0)
		_puff(16, 0.0)
	_was_on_floor = on_floor

	# ---- 목표 자세 + 날갯짓 목표 ----
	var target := NEUTRAL
	var follow := 9.0
	var rate := 0.0     # 날갯짓 빠르기 (rad/s)
	var amp := 0.0      # 날갯짓 크기
	var ghost := false
	var air_tilt := clampf(_boss.velocity.x / 2500.0, -0.12, 0.12)   # 실제 이동 방향으로 기운다
	match st:
		GrayLeafBird.State.HOVER, GrayLeafBird.State.LEAF_RAIN, GrayLeafBird.State.INTRO, GrayLeafBird.State.DESCEND:
			rate = 7.0; amp = 0.045
			target.x = air_tilt
			if st == GrayLeafBird.State.DESCEND:
				target.z = 1.04   # 날개를 펴고 내려온다
				target.x += 0.06 * f
		GrayLeafBird.State.TAKEOFF:
			if _boss.crouching:
				target = Vector4(-0.05 * f, 1.08, 0.9, 16.0)
				follow = 16.0
				rate = 4.0; amp = 0.02
			else:
				rate = 9.0; amp = 0.06
				target.x = air_tilt
				target.w = -6.0
		GrayLeafBird.State.FEATHERS:
			rate = 18.0; amp = 0.03
			target.x = -0.08 * f
			# 예고: 몸을 움츠린다 (색은 아래에서 날개 끝이 밝아지듯)
			var tg := _boss.telegraph_amount
			target.y = 1.0 - 0.06 * tg
			target.z = 1.0 + 0.05 * tg
			target.w = -8.0 * tg
		GrayLeafBird.State.WIND:
			rate = 22.0; amp = 0.08
			target.x = 0.18 * f
			target.w = 6.0
		GrayLeafBird.State.GROUND_IDLE:
			target.z = 1.0 + Motion.breathe(_t, 0.5, 0.015)
			target.w = Motion.breathe(_t, 0.5, 2.0)
		GrayLeafBird.State.WALK_TO_PILE:
			# 걸음은 이동 거리 기준, 기울기는 실제 이동 방향
			_dist += speed * delta
			var amount := clampf(speed / _boss.walk_speed, 0.0, 1.3)
			var bob := Motion.step_bob(_dist, STRIDE)
			target.w = -bob * 8.0 * amount
			target.x = 0.1 * amount * signf(_boss.velocity.x)
			target.z = 1.0 + bob * 0.03 * amount
			var step := int(floor(_dist / STRIDE))
			if step != _last_step:
				_last_step = step
				if amount > 0.3:
					_puff(3, 0.0)
					_imp_v += 0.4 * amount
		GrayLeafBird.State.EAT:
			# 고개를 숙이고 쪼아 먹는다
			target = Vector4(0.35 * f, 1.0, 1.0, 40.0)
			target.w += absf(sin(_t * 6.0)) * 6.0
			target.x += absf(sin(_t * 6.0)) * 0.04 * f
			follow = 8.0
		GrayLeafBird.State.SWEEP:
			# 날개를 뒤로 젖히고(예비) → 앞으로 쓸기(타격, 날갯짓 한 번 크게) → 되돌림
			target = _three_beat(Vector4(-0.22 * f, 0.94, 1.06, -10.0), Vector4(0.3 * f, 1.14, 0.9, 8.0), 0.6)
			follow = _beat_follow()
			if ph == "active":
				rate = 20.0; amp = 0.12
				ghost = true
			elif ph == "startup":
				rate = 3.0; amp = 0.03
		GrayLeafBird.State.PECK:
			# 몸을 뒤로 세웠다가(예비) → 돌진 속도를 따라 앞으로 기울며 찍기 → 되돌림
			target = _three_beat(Vector4(-0.16 * f, 0.96, 1.05, -14.0), Vector4(0.42 * f, 1.12, 0.9, 18.0), 0.5)
			if ph == "active":
				target.x += clampf(_boss.velocity.x * f / 2200.0, 0.0, 0.15)
				ghost = true
			follow = _beat_follow()
		GrayLeafBird.State.BROKEN:
			target = Vector4(0.45 * f, 1.06, 0.92, 60.0)
			target.z += Motion.breathe(_t, 0.7, 0.025)
			follow = 6.0
		GrayLeafBird.State.FALLEN, GrayLeafBird.State.PURIFIED:
			target = Vector4(0.7 * f, 1.0, 1.0, 90.0)
			follow = 5.0
	# 움찔: 뒤로 젖힌다
	target.x += -0.3 * f * _boss.stagger

	# ---- 보간 ----
	_pose = Vector4(
		Motion.damp(_pose.x, target.x, follow, delta),
		Motion.damp(_pose.y, target.y, follow, delta),
		Motion.damp(_pose.z, target.z, follow, delta),
		Motion.damp(_pose.w, target.w, follow, delta))
	var s := Motion.spring(_imp, 0.0, _imp_v, 380.0, 13.0, delta)
	_imp = s[0]; _imp_v = s[1]
	s = Motion.spring(_kick, 0.0, _kick_v, 210.0, 9.0, delta)
	_kick = s[0]; _kick_v = s[1]
	# 날갯짓: 위상은 끊기지 않고 rate/amp 만 수렴
	_flap_rate = Motion.damp(_flap_rate, rate, 6.0, delta)
	_flap_amp = Motion.damp(_flap_amp, amp, 8.0, delta)
	_flap_phase += _flap_rate * delta
	var flap := 1.0 + sin(_flap_phase) * _flap_amp
	# 방향 전환: 몸 틀기
	_face = Motion.damp(_face, f, 11.0, delta)
	var fx := _face   # 그림이 오른쪽을 보므로 오른쪽을 볼 때 그대로, 왼쪽을 볼 때 음수
	if absf(fx) < 0.03:
		fx = 0.03 * (1.0 if fx >= 0.0 else -1.0)

	var tilt := _pose.x + _kick
	var sq := Vector2(_pose.y + _imp * 0.7, (_pose.z - _imp) * flap)
	var dy := _pose.w + _imp * 40.0
	rotation = tilt
	scale = Vector2(_base_scale.x * sq.x * fx, _base_scale.y * maxf(sq.y, 0.05))
	position = _base_pos + Vector2(0, dy)
	_update_ghosts(delta, ghost)

	# ---- 색: 잿빛 바탕, 깃털 예고(차가운 밝아짐), 붉은 예고(서서히), 피격 번쩍임 ----
	_red = Motion.damp(_red, 1.0 if _boss.is_red() else 0.0, 14.0, delta)
	var ash := Color(0.78, 0.8, 0.82) if _boss.phase == 1 else Color(0.7, 0.68, 0.7)
	ash = ash.lerp(Color(1.25, 1.35, 1.45), _boss.telegraph_amount * (0.7 + 0.3 * sin(_t * 24.0)))
	ash = ash.lerp(Color(2.2, 0.6, 0.5), _red * (0.5 + 0.5 * sin(_t * 30.0)))
	modulate = ash.lerp(Color(2.0, 2.0, 2.0), fl * 0.8)


## 세 박자 자세 (경계에서 값이 이어진다: 예비 끝 = back, 타격 시작 = back, 되돌림 시작 = fwd).
func _three_beat(back: Vector4, fwd: Vector4, strike_span := 0.6) -> Vector4:
	var p := _boss.phase_progress()
	match _boss.attack_phase:
		"startup":
			return NEUTRAL.lerp(back, Motion.anticipation(p))
		"active":
			return back.lerp(fwd, Motion.strike(clampf(p / strike_span, 0.0, 1.0)))
		"recovery":
			return fwd.lerp(NEUTRAL, Motion.settle(p))
	return NEUTRAL


func _beat_follow() -> float:
	match _boss.attack_phase:
		"startup": return 11.0
		"active": return 40.0
		"recovery": return 12.0
	return 9.0


func _puff(n: int, ox: float) -> void:
	_dust.amount = n
	_dust.global_position = _boss.global_position + Vector2(ox, 0)
	_dust.restart()
	_dust.emitting = true


func _update_ghosts(delta: float, active: bool) -> void:
	if active:
		_ghost_timer += delta
		if _ghost_timer >= 0.04:
			_ghost_timer = 0.0
			var g: Sprite2D = _ghosts.pop_front()
			g.visible = true
			g.global_transform = global_transform
			g.modulate = Color(0.85, 0.9, 0.9, 0.3)
			_ghosts.append(g)
	else:
		_ghost_timer = 0.0
	for g in _ghosts:
		if g.visible:
			g.modulate.a -= delta * 2.4
			if g.modulate.a <= 0.0:
				g.visible = false

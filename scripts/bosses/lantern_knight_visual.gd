extends Sprite2D
## 등불 기사의 그림(boss_knight_now.png)을 상태에 맞춰 움직인다.
## 원칙: 자세 값(기울기·찌그러짐·세로 오프셋·색)은 절대 '툭' 바뀌지 않는다.
## 매 프레임 '목표 자세'를 정하고, 실제 값은 Motion.damp(프레임 독립)로 그 목표를 쫓는다.
## 그 위에 '충격 스프링'(내려찍기·디딤·휘청·피격)이 한 겹 더 얹힌다.
## 휘두르기는 세 박자: 예비(뒤로 당기며 멈칫) → 타격(아주 빠르게, 살짝 지나침) → 되돌림(출렁이며 제자리).
## 진행도는 보스가 공개한 단계 길이(startup_len/active_len/recovery_len)로 계산해 2페이즈 배속에도 모양이 같다.
## 그림 원본은 왼쪽을 본다 → 오른쪽을 볼 때 뒤집는다(scale.x 음수). 방향 전환은 몸을 틀며 1→0→−1 을 지난다.

## 자세 묶음: (기울기, 가로 찌그러짐, 세로 찌그러짐, 세로 오프셋)
const NEUTRAL := Vector4(0.0, 1.0, 1.0, 0.0)
const STRIDE := 150.0    # 한 걸음 거리(px). 들썩임과 디딤 먼지의 기준

var _boss: LanternKnight
var _t := 0.0
var _base_scale := Vector2.ONE
var _base_pos := Vector2.ZERO

# 현재 자세 (목표를 따라감)
var _pose := NEUTRAL
# 충격 스프링: _imp 양수 = 눌림(세로 줄고 가로 늘고 살짝 내려감), 음수 = 늘어남
var _imp := 0.0
var _imp_v := 0.0
# 기울기 충격 스프링 (휘청·피격)
var _kick := 0.0
var _kick_v := 0.0
# 바라보는 방향 (−1 왼쪽 … +1 오른쪽; 사이 값은 몸 틀기)
var _face := -1.0
var _red := 0.0
var _dist := 0.0         # 걸은 거리 누적 (걸음 들썩임 기준)
var _last_step := 0
var _prev_phase := ""
var _prev_hint := ""
var _prev_flash := 0.0
var _dust: CPUParticles2D
var _embers: CPUParticles2D
var _ghosts: Array[Sprite2D] = []
var _ghost_timer := 0.0
# 등불 빛: 몸보다 한 박자 늦게 진자처럼 흔들린다
var _light: PointLight2D
var _light_base := Vector2.ZERO
var _lamp := 0.0
var _lamp_v := 0.0


func _ready() -> void:
	_boss = get_parent() as LanternKnight
	_base_scale = scale
	_base_pos = position
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _boss:
		_face = float(_boss.facing)
		_boss.state_changed.connect(_on_state_changed)
		_light = _boss.get_node_or_null("Light") as PointLight2D
		if _light:
			_light_base = _light.position
	# 발 먼지 (몸의 배율·회전을 따르지 않게 top_level)
	_dust = CPUParticles2D.new()
	_dust.top_level = true
	_dust.emitting = false
	_dust.one_shot = true
	_dust.explosiveness = 1.0
	_dust.amount = 10
	_dust.lifetime = 0.55
	_dust.direction = Vector2(0, -1)
	_dust.spread = 75.0
	_dust.gravity = Vector2(0, 220)
	_dust.initial_velocity_min = 70.0
	_dust.initial_velocity_max = 200.0
	_dust.scale_amount_min = 4.0
	_dust.scale_amount_max = 9.0
	_dust.color = Color(0.7, 0.66, 0.58, 0.5)
	add_child(_dust)
	# 내려찍기 불씨
	_embers = CPUParticles2D.new()
	_embers.top_level = true
	_embers.emitting = false
	_embers.one_shot = true
	_embers.explosiveness = 1.0
	_embers.amount = 16
	_embers.lifetime = 0.8
	_embers.direction = Vector2(0, -1)
	_embers.spread = 60.0
	_embers.gravity = Vector2(0, -60)
	_embers.initial_velocity_min = 120.0
	_embers.initial_velocity_max = 320.0
	_embers.scale_amount_min = 2.0
	_embers.scale_amount_max = 4.0
	_embers.color = Color(1.0, 0.62, 0.25, 0.9)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_embers.material = add
	add_child(_embers)
	# 빠른 동작 잔상
	for i in 3:
		var g := Sprite2D.new()
		g.texture = texture
		g.top_level = true
		g.visible = false
		g.show_behind_parent = true
		g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(g)
		_ghosts.append(g)


func _on_state_changed(st: LanternKnight.State) -> void:
	match st:
		LanternKnight.State.STAGGER:
			_jolt(-1.0, -4.0)
		LanternKnight.State.BROKEN:
			_jolt(1.4, 3.0)
			_puff(10, 0.0)
		LanternKnight.State.FALLEN:
			_jolt(2.2, 2.0)
			_puff(16, 0.0)


## 충격을 준다: squash = 눌림 스프링 속도(양수 눌림), kick = 기울기 스프링 속도(바라보는 방향 기준, 양수 = 앞으로)
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

	# ---- 일회성 사건 감지 (단계 바뀜, 힌트, 피격) ----
	if ph != _prev_phase:
		if ph == "active":
			match st:
				LanternKnight.State.SLAM:
					_jolt(2.4, 0.0)
					_puff(22, 0.0)
					_spark()
				LanternKnight.State.THRUST:
					_puff(6, -f * 40.0)
				LanternKnight.State.FLAME:
					_jolt(0.6, 0.0)
		_prev_phase = ph
	if _boss.anim_hint == "stagger" and _prev_hint != "stagger" and st == LanternKnight.State.THRUST:
		_jolt(-1.0, -4.5)   # 창이 튕김 (STAGGER 상태 진입은 위 state_changed 에서 한 번만)
	_prev_hint = _boss.anim_hint
	var fl := _boss.flash_amount()
	if fl > _prev_flash + 0.4 and st not in [LanternKnight.State.BROKEN, LanternKnight.State.FALLEN, LanternKnight.State.STAGGER]:
		_jolt(0.35, -1.2)
	_prev_flash = fl

	# ---- 목표 자세 ----
	var target := NEUTRAL
	var follow := 9.0        # 목표를 쫓는 빠르기 (단계마다 다름)
	var ghost := false
	# 숨쉬기 (서 있을 때 더 크게)
	target.z += Motion.breathe(_t, 0.22, 0.012)
	match st:
		LanternKnight.State.MARCH, LanternKnight.State.INTRO:
			# 걸음은 시간이 아니라 이동 거리 기준: 속도가 0이면 멈춘다
			_dist += speed * delta
			var amount := clampf(speed / _boss.march_speed, 0.0, 1.3)
			var bob := Motion.step_bob(_dist, STRIDE)
			target.w = -bob * 9.0 * amount
			target.x = (0.05 * amount) * signf(_boss.velocity.x) + sin(_dist / STRIDE * PI) * 0.03 * amount
			target.y = 1.0 - bob * 0.02 * amount
			target.z += bob * 0.03 * amount
			var step := int(floor(_dist / STRIDE))
			if step != _last_step:
				_last_step = step
				if amount > 0.25:
					_puff(4, -signf(_boss.velocity.x) * 30.0)
					_imp_v += 0.45 * amount
		LanternKnight.State.THRUST:
			# 예비: 몸과 창을 뒤로, 무게는 뒷발 → 찌르기: 앞으로 쏠리며 살짝 지나침 → 되돌림
			target = _three_beat(Vector4(-0.2 * f, 0.95, 1.05, -6.0), Vector4(0.28 * f, 1.17, 0.9, 6.0), 0.6)
			follow = _beat_follow()
			ghost = ph == "active"
		LanternKnight.State.FLAME:
			# 등불을 뒤로 크게 들어 올렸다가 앞으로 휘두른다
			target = _three_beat(Vector4(-0.32 * f, 0.96, 1.06, -16.0), Vector4(0.36 * f, 1.12, 0.93, 6.0), 0.65)
			follow = _beat_follow()
			ghost = ph == "active"
		LanternKnight.State.SLAM:
			# 웅크림(앞 30%: 내려앉음) → 솟구침(위로) → 내려찍기(아래로 꽝) → 되돌림
			var up := Vector4(0.0, 0.93, 1.1, -70.0)
			target = _three_beat(up, Vector4(0.0, 1.22, 0.8, 24.0), 0.5)
			if ph == "startup":
				var p := _boss.phase_progress()
				var crouch := Vector4(0.0, 1.06, 0.94, 14.0)
				if p < 0.3:
					target = NEUTRAL.lerp(crouch, Motion.ease_out(p / 0.3))
				else:
					# 웅크린 자세에서 도약 (끝값 up 이 타격 시작 자세와 같아 이어진다)
					target = crouch.lerp(up, Motion.anticipation((p - 0.3) / 0.7))
				target.x += sin(_t * 40.0) * 0.02 * clampf((p - 0.6) / 0.4, 0.0, 1.0)
			follow = _beat_follow()
			ghost = ph == "active"
		LanternKnight.State.THROW:
			target = _three_beat(Vector4(-0.26 * f, 0.96, 1.04, -10.0), Vector4(0.22 * f, 1.08, 0.96, 2.0), 0.7)
			follow = _beat_follow()
		LanternKnight.State.STAGGER:
			# 뒤로 젖혀 휘청이다가 되돌아온다
			var k := _boss.state_progress(_boss.stagger_len)
			var back := Vector4(-0.3 * f, 0.94, 1.05, 4.0)
			target = back.lerp(NEUTRAL, Motion.settle(k, 1.5, 3.0))
			follow = 12.0
		LanternKnight.State.BROKEN:
			target = Vector4(0.4 * f, 1.06, 0.9, 40.0)
			target.z += Motion.breathe(_t, 0.6, 0.02)   # 거친 숨
			follow = 6.0
		LanternKnight.State.FALLEN, LanternKnight.State.PURIFIED:
			target = Vector4(0.85 * f, 1.0, 1.0, 110.0)
			follow = 5.0
	if _boss.anim_hint == "stagger" and st == LanternKnight.State.THRUST:
		# 창이 튕겼다: 되돌림 동안 뒤로 젖힌 자세에서 출렁이며 돌아온다
		var k := _boss.phase_progress()
		target = Vector4(-0.34 * f, 0.93, 1.06, 6.0).lerp(NEUTRAL, Motion.settle(k, 2.0, 3.5))
		follow = 10.0

	# ---- 보간 (프레임 독립) ----
	_pose = Vector4(
		Motion.damp(_pose.x, target.x, follow, delta),
		Motion.damp(_pose.y, target.y, follow, delta),
		Motion.damp(_pose.z, target.z, follow, delta),
		Motion.damp(_pose.w, target.w, follow, delta))
	var s := Motion.spring(_imp, 0.0, _imp_v, 380.0, 13.0, delta)
	_imp = s[0]; _imp_v = s[1]
	s = Motion.spring(_kick, 0.0, _kick_v, 210.0, 9.0, delta)
	_kick = s[0]; _kick_v = s[1]
	# 방향 전환: 몸 틀기 (scale.x 가 0 을 지나며 뒤집힌다)
	_face = Motion.damp(_face, f, 11.0, delta)
	var fx := -_face   # 그림이 왼쪽을 보므로 오른쪽을 볼 때 음수
	if absf(fx) < 0.03:
		fx = 0.03 * (1.0 if fx >= 0.0 else -1.0)

	var tilt := _pose.x + _kick
	var sq := Vector2(_pose.y + _imp * 0.7, _pose.z - _imp)
	var dy := _pose.w + _imp * 40.0
	rotation = tilt
	scale = Vector2(_base_scale.x * sq.x * fx, _base_scale.y * maxf(sq.y, 0.05))
	position = _base_pos + Vector2(0, dy)
	_update_ghosts(delta, ghost)
	_update_light(delta, tilt, dy)

	# ---- 색: 붉은 예고는 서서히 켜지고 꺼진다, 피격 번쩍임 ----
	_red = Motion.damp(_red, 1.0 if _boss.is_red() else 0.0, 14.0, delta)
	var base := Color(0.95, 0.9, 0.9) if _boss.phase == 1 else Color(1.1, 0.85, 0.75)
	base = base.lerp(Color(2.4, 0.5, 0.4), _red * (0.5 + 0.5 * sin(_t * 32.0)))
	modulate = base.lerp(Color(2.5, 2.5, 2.5), fl * 0.8)


## 세 박자 자세. back = 예비 끝 자세, fwd = 타격 자세. strike_span = 타격 구간 중 곡선이 끝나는 비율(정점이 그 안에 온다).
## 경계에서 곡선 값이 이어지므로(예비 끝 = back, 타격 시작 = back, 되돌림 시작 = fwd) 목표가 점프하지 않는다.
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


## 단계별 따라가는 빠르기: 예비는 천천히, 타격은 아주 빠르게, 되돌림은 보통.
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


func _spark() -> void:
	_embers.global_position = _boss.global_position + Vector2(0, -20)
	_embers.restart()
	_embers.emitting = true


## 잔상: 빠르게 움직일 때 뒤에 희미한 그림을 남긴다.
func _update_ghosts(delta: float, active: bool) -> void:
	if active:
		_ghost_timer += delta
		if _ghost_timer >= 0.04:
			_ghost_timer = 0.0
			var g: Sprite2D = _ghosts.pop_front()
			g.visible = true
			g.global_transform = global_transform
			g.modulate = Color(1.0, 0.85, 0.6, 0.32)
			_ghosts.append(g)
	else:
		_ghost_timer = 0.0
	for g in _ghosts:
		if g.visible:
			g.modulate.a -= delta * 2.4
			if g.modulate.a <= 0.0:
				g.visible = false


## 등불 빛: 몸의 기울기·속도에 끌려 진자처럼 한 박자 늦게 흔들린다.
func _update_light(delta: float, tilt: float, dy: float) -> void:
	if _light == null:
		return
	var drive := -tilt * 0.9 - clampf(_boss.velocity.x / 1400.0, -0.5, 0.5)
	var s := Motion.spring(_lamp, drive, _lamp_v, 48.0, 3.6, delta)
	_lamp = s[0]; _lamp_v = s[1]
	_light.position = _light_base + Vector2(sin(_lamp) * 70.0, dy * 0.8 + (1.0 - cos(_lamp)) * 40.0)
	var flicker := 1.0 + Motion.breathe(_t, 3.1, 0.06) + Motion.breathe(_t, 7.3, 0.03)
	_light.energy = (1.2 if _boss.phase == 1 else 1.5) * flicker

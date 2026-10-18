extends Sprite2D
## 뿌리지기의 그림(boss_rootkeeper_now.png)을 상태에 맞춰 움직인다. 가시 예고 자국도 그린다.
## 원칙: 자세 값은 절대 '툭' 바뀌지 않는다. 매 프레임 '목표 자세'를 정하고 Motion.damp(프레임 독립)로 쫓는다.
## 그 위에 '충격 스프링'(지팡이 내리꽂기·벽 돌진 멈춤·휘청·피격)이 한 겹 더 얹힌다.
## 공격은 세 박자(예비 → 타격 → 되돌림)로, 진행도는 보스가 공개한 단계 길이로 계산한다.
## 그림은 정면이라 뒤집기는 의미가 적다. 지팡이가 오른손이므로 기울기 부호만 바라보는 쪽으로 자연스럽게 둔다.

## 자세 묶음: (기울기, 가로 찌그러짐, 세로 찌그러짐, 세로 오프셋)
const NEUTRAL := Vector4(0.0, 1.0, 1.0, 0.0)
const STRIDE := 120.0

var _boss: RootKeeper
var _t := 0.0
var _base_scale := Vector2.ONE
var _base_pos := Vector2.ZERO
var _marks: Node2D

var _pose := NEUTRAL
var _imp := 0.0
var _imp_v := 0.0
var _kick := 0.0
var _kick_v := 0.0
var _face := -1.0
var _red := 0.0
var _dist := 0.0
var _last_step := 0
var _prev_phase := ""
var _prev_hint := ""
var _prev_flash := 0.0
var _prev_vx := 0.0
var _rise_from := NEUTRAL   # RISE 에 들어선 순간의 자세 (거기서 이어서 쓰러진다)
var _dust: CPUParticles2D
var _ghosts: Array[Sprite2D] = []
var _ghost_timer := 0.0
# 지팡이 등불 빛: 한 박자 늦게 흔들린다
var _light: PointLight2D
var _light_base := Vector2.ZERO
var _lamp := 0.0
var _lamp_v := 0.0


func _ready() -> void:
	_boss = get_parent() as RootKeeper
	_base_scale = scale
	_base_pos = position
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_marks = Node2D.new()
	_marks.top_level = true
	_marks.z_index = -1
	add_child(_marks)
	_marks.draw.connect(_draw_marks)
	if _boss:
		_face = float(_boss.facing)
		_boss.state_changed.connect(_on_state_changed)
		_light = _boss.get_node_or_null("Light") as PointLight2D
		if _light:
			_light_base = _light.position
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
	_dust.initial_velocity_min = 60.0
	_dust.initial_velocity_max = 180.0
	_dust.scale_amount_min = 3.0
	_dust.scale_amount_max = 7.0
	_dust.color = Color(0.55, 0.5, 0.6, 0.5)
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


func _on_state_changed(st: RootKeeper.State) -> void:
	match st:
		RootKeeper.State.RISE:
			_rise_from = _pose
			_jolt(1.2, -1.5)
			_puff(14, 0.0)
		RootKeeper.State.BROKEN:
			_jolt(1.4, 3.0)
			_puff(10, 0.0)
		RootKeeper.State.FALLEN:
			_jolt(2.2, 2.0)
			_puff(16, 0.0)


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
				RootKeeper.State.SPIKES:
					_jolt(1.6, 0.6)
					_puff(12, 0.0)
				RootKeeper.State.SWEEP:
					_puff(5, -f * 30.0)
				RootKeeper.State.WALL:
					_jolt(-0.6, 0.0)
		_prev_phase = ph
	if _boss.anim_hint == "stagger" and _prev_hint != "stagger":
		_jolt(-0.9, -4.5)
	_prev_hint = _boss.anim_hint
	var fl := _boss.flash_amount()
	if fl > _prev_flash + 0.4 and st not in [RootKeeper.State.BROKEN, RootKeeper.State.FALLEN, RootKeeper.State.RISE]:
		_jolt(0.3, -1.0)
	_prev_flash = fl
	# 벽 돌진이 벽에 막혀 멈출 때: 앞으로 쏠린 몸이 튕긴다
	if st == RootKeeper.State.WALL and absf(_prev_vx) > 600.0 and speed < 50.0:
		_jolt(1.2, 2.5)
		_puff(14, f * 60.0)
	_prev_vx = _boss.velocity.x

	# ---- 목표 자세 ----
	var target := NEUTRAL
	var follow := 9.0
	var ghost := false
	target.z += Motion.breathe(_t, 0.2, 0.012)
	target.w += Motion.breathe(_t, 0.2, 3.0)
	match st:
		RootKeeper.State.STANCE, RootKeeper.State.INTRO:
			# 느린 걸음: 거리 기준 들썩임, 기울기는 실제 이동 방향
			_dist += speed * delta
			var amount := clampf(speed / _boss.walk_speed, 0.0, 1.2)
			var bob := Motion.step_bob(_dist, STRIDE)
			target.w += -bob * 5.0 * amount
			target.x = 0.02 * f + 0.04 * amount * signf(_boss.velocity.x)
			var step := int(floor(_dist / STRIDE))
			if step != _last_step:
				_last_step = step
				if amount > 0.3:
					_puff(3, 0.0)
					_imp_v += 0.25 * amount
		RootKeeper.State.SPIKES:
			# 지팡이를 높이 들어 올리고(몸이 늘어남) → 내리꽂기(눌림) → 되돌림
			target = _three_beat(Vector4(-0.1 * f, 0.96, 1.06, -28.0), Vector4(0.08 * f, 1.1, 0.93, 14.0), 0.55)
			follow = _beat_follow()
		RootKeeper.State.SWEEP:
			target = _three_beat(Vector4(-0.26 * f, 0.96, 1.05, -8.0), Vector4(0.34 * f, 1.13, 0.93, 6.0), 0.75)
			follow = _beat_follow()
			ghost = ph == "active"
		RootKeeper.State.ORBS:
			# 지팡이를 들어 구슬을 빚는다: 살짝 뒤로 기울고 떠 있는 듯 올라간다
			target = _three_beat(Vector4(-0.1 * f, 0.98, 1.03, -12.0), Vector4(-0.06 * f, 1.0, 1.02, -10.0), 0.8)
			follow = _beat_follow()
		RootKeeper.State.WALL:
			# 뒤로 물러 몸을 모았다가 앞으로 쏠리며 돌진 (잔상)
			target = _three_beat(Vector4(-0.2 * f, 0.95, 1.06, -6.0), Vector4(0.38 * f, 1.2, 0.9, 8.0), 0.45)
			if ph == "startup":
				target.x += sin(_t * 40.0) * 0.015 * clampf((_boss.phase_progress() - 0.5) / 0.5, 0.0, 1.0)
			elif ph == "active":
				target.x += clampf(_boss.velocity.x / 4000.0, -0.2, 0.2)
			follow = _beat_follow()
			ghost = ph == "active" and speed > 300.0
		RootKeeper.State.RISE:
			# 지금 자세에서 이어서 쓰러지고(앞 30%) → 떨며 천천히 일어선다
			var k := _boss.state_progress(_boss.rise_len)
			var collapsed := Vector4(0.6 * f, 1.02, 0.8, 120.0)
			if k < 0.3:
				# 들어선 순간의 자세에서 점점 빨라지며 무너진다 (dy 가 한 번에 뛰지 않음)
				target = _rise_from.lerp(collapsed, Motion.ease_in(k / 0.3, 1.8))
				follow = 14.0
			else:
				var u := Motion.ease_in_out((k - 0.3) / 0.7)
				target = collapsed.lerp(Vector4(0.0, 1.0, 1.05, -10.0), u)
				target.x += sin(_t * 26.0) * 0.02 * (1.0 - u)
				follow = 8.0
		RootKeeper.State.BROKEN:
			target = Vector4(0.4 * f, 1.06, 0.88, 50.0)
			target.z += Motion.breathe(_t, 0.6, 0.02)
			follow = 6.0
		RootKeeper.State.FALLEN, RootKeeper.State.PURIFIED:
			target = Vector4(0.75 * f, 1.0, 1.0, 130.0)
			follow = 5.0
	# 지팡이가 튕겼다(저스트 가드): 뒤로 젖혔다가 stagger 가 1→0 으로 줄면서 서서히 돌아온다 (끝에서 툭 사라지지 않음)
	target.x += -0.2 * f * _boss.stagger

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
	# 정면 그림이라 틀기가 '찌그러짐'으로 읽히므로 기사·새보다 빠르게(약 0.15초) 돈다
	_face = Motion.damp(_face, f, 20.0, delta)
	var fx := -_face   # 예전 flip_h = facing > 0 과 같은 뜻 (오른쪽을 볼 때 뒤집음)
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

	# ---- 색 ----
	_red = Motion.damp(_red, 1.0 if _boss.is_red() else 0.0, 14.0, delta)
	var base := Color(0.9, 0.92, 1.0) if _boss.phase == 1 else Color(1.05, 0.95, 1.15)
	base = base.lerp(Color(2.4, 0.5, 0.4), _red * (0.5 + 0.5 * sin(_t * 32.0)))
	modulate = base.lerp(Color(2.5, 2.5, 2.5), fl * 0.8)
	_marks.queue_redraw()


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
			g.modulate = Color(0.7, 0.85, 1.0, 0.3)
			_ghosts.append(g)
	else:
		_ghost_timer = 0.0
	for g in _ghosts:
		if g.visible:
			g.modulate.a -= delta * 2.4
			if g.modulate.a <= 0.0:
				g.visible = false


## 지팡이 등불 빛: 몸의 기울기·속도에 끌려 한 박자 늦게 흔들린다.
func _update_light(delta: float, tilt: float, dy: float) -> void:
	if _light == null:
		return
	var drive := -tilt * 0.8 - clampf(_boss.velocity.x / 1600.0, -0.5, 0.5)
	var s := Motion.spring(_lamp, drive, _lamp_v, 44.0, 3.4, delta)
	_lamp = s[0]; _lamp_v = s[1]
	_light.position = _light_base + Vector2(sin(_lamp) * 60.0, dy * 0.8 + (1.0 - cos(_lamp)) * 30.0)
	_light.energy = (1.0 if _boss.phase == 1 else 1.25) * (1.0 + Motion.breathe(_t, 0.9, 0.08))


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

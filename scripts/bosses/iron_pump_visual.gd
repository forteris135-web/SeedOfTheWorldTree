extends Sprite2D
## 무쇠 펌프의 그림(boss_iron_pump_now.png)을 상태에 맞춰 움직인다. 등불 기사 visual 과 같은 원칙:
## 자세 값(기울기·찌그러짐·세로 오프셋)은 '툭' 바뀌지 않고 목표를 Motion.damp 로 쫓으며, 충격은 스프링 한 겹.
## 그림 한 장(임시)에는 몸통만 있고, **피스톤 팔·관(노즐)·장갑 덮개·핵**은 이 스크립트가 _draw 로 그려 움직인다
## (draw_parts). 진짜 그림에 피스톤·관이 그려져 오면 draw_parts 를 끄고 몸의 기울기·찌그러짐만 쓴다.
## 리듬: 기계라 매 박(128bpm)마다 '쿵' 하고 작게 들썩인다. 피스톤은 예고에 치켜들었다(멈칫) → 아주 빠르게 내려찍고 → 출렁이며 돌아온다.
## 그림 원본은 왼쪽을 본다 → 오른쪽을 볼 때 뒤집는다(scale.x 음수). 방향 전환은 몸을 틀며 1→0→−1 을 지난다.
## 좌표: 그림 픽셀(1536×1024, 가운데 원점). 몸통 x −248~332, y −212~408. 발 y 468. 핵 (47, 83).

const NEUTRAL := Vector4(0.0, 1.0, 1.0, 0.0)
const STRIDE := 220.0
const BEAT := 60.0 / 128.0
## 그림에 없는 부품을 코드로 그릴지 (임시 그림: 켬)
@export var draw_parts := true

const RUST := Color(0.42, 0.17, 0.1)
const RUST_DARK := Color(0.2, 0.09, 0.07)
const STEEL := Color(0.36, 0.33, 0.3)
const TEAL := Color(0.35, 0.85, 0.9)
const CORE_POS := Vector2(47, 83)
const NOZ_PIVOT := Vector2(-248, 250)
const NOZ_LEN := 300.0
const HEAD_REST := 60.0
const HEAD_SLAM := 368.0

var _boss: IronPump
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
var _dist := 0.0
var _last_step := 0
var _prev_phase := ""
var _prev_hint := ""
var _prev_flash := 0.0
var _prev_bit := false
# 부품 채널
var _ext := 0.1          # 피스톤 (−0.4 치켜듦 … 0 쉼 … 1 내려찍음)
var _ext_v := 0.0
var _noz := 0.0          # 관 각도 (0 = 정면, + = 아래)
var _open := 0.15        # 관 입 벌림 (0~1)
var _plates := 0.0       # 장갑 덮개 벌어짐 (0 닫힘 … 1 열림)
var _core := 0.3         # 핵 빛 세기
var _recoil := 0.0       # 관 반동 (스프링)
var _recoil_v := 0.0
var _tremble := 0.0
var _dust: CPUParticles2D
var _sparks: CPUParticles2D
var _steam: CPUParticles2D
var _inhale: CPUParticles2D
var _drips: CPUParticles2D
var _ghosts: Array[Sprite2D] = []
var _ghost_timer := 0.0
var _light: PointLight2D
var _light_base := Vector2.ZERO


func _ready() -> void:
	_boss = get_parent() as IronPump
	_base_scale = scale
	_base_pos = position
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _boss:
		_face = float(_boss.facing)
		_boss.state_changed.connect(_on_state_changed)
		_boss.shot.connect(func() -> void: _recoil_v += 9.0)
		_boss.slammed.connect(func() -> void:
			_jolt(2.6, 0.0)
			_puff(26, float(_boss.facing) * 300.0)
			_spark_burst(12))
		_light = _boss.get_node_or_null("Light") as PointLight2D
		if _light:
			_light_base = _light.position
	_dust = _make_particles(12, 0.6, Vector2(0, -1), 75.0, Vector2(0, 220), 70.0, 220.0, 4.0, 10.0, Color(0.6, 0.5, 0.42, 0.55), false)
	_dust.top_level = true
	_sparks = _make_particles(14, 0.7, Vector2(0, -1), 80.0, Vector2(0, 500), 160.0, 420.0, 2.0, 4.0, Color(1.0, 0.75, 0.3, 0.95), true)
	_sparks.top_level = true
	_steam = _make_particles(10, 1.4, Vector2(0, -1), 30.0, Vector2(0, -60), 40.0, 110.0, 8.0, 18.0, Color(0.8, 0.85, 0.85, 0.35), false)
	_steam.one_shot = false
	_steam.explosiveness = 0.0
	_steam.emitting = false
	_steam.top_level = true
	# 빨아들이기: 입 앞 넓은 자리에서 입 쪽(+x, 그림 기준 뒤쪽)으로 흘러드는 빛 가루 (그림 좌표라 뒤집힘을 따른다)
	_inhale = CPUParticles2D.new()
	_inhale.emitting = false
	_inhale.amount = 60
	_inhale.lifetime = 0.6
	_inhale.local_coords = true
	_inhale.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_inhale.emission_rect_extents = Vector2(60, 220)
	_inhale.position = NOZ_PIVOT + Vector2(-NOZ_LEN - 520.0, 0)
	_inhale.direction = Vector2(1, 0)
	_inhale.spread = 10.0
	_inhale.gravity = Vector2(600, 0)
	_inhale.initial_velocity_min = 500.0
	_inhale.initial_velocity_max = 900.0
	_inhale.scale_amount_min = 10.0
	_inhale.scale_amount_max = 18.0
	_inhale.color = Color(TEAL, 0.8)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_inhale.material = add
	add_child(_inhale)
	# 2페이즈: 이음새마다 새는 수액 (그림 좌표)
	_drips = CPUParticles2D.new()
	_drips.emitting = false
	_drips.amount = 10
	_drips.lifetime = 1.2
	_drips.local_coords = true
	_drips.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_drips.emission_rect_extents = Vector2(260, 6)
	_drips.position = Vector2(40, 120)
	_drips.direction = Vector2(0, 1)
	_drips.spread = 8.0
	_drips.gravity = Vector2(0, 900)
	_drips.initial_velocity_min = 10.0
	_drips.initial_velocity_max = 40.0
	_drips.scale_amount_min = 4.0
	_drips.scale_amount_max = 7.0
	_drips.color = Color(TEAL, 0.8)
	add_child(_drips)
	for i in 3:
		var g := Sprite2D.new()
		g.texture = texture
		g.top_level = true
		g.visible = false
		g.show_behind_parent = true
		g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(g)
		_ghosts.append(g)


func _make_particles(n: int, life: float, dir: Vector2, spread: float, grav: Vector2, v0: float, v1: float, s0: float, s1: float, col: Color, additive: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = n
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.gravity = grav
	p.initial_velocity_min = v0
	p.initial_velocity_max = v1
	p.scale_amount_min = s0
	p.scale_amount_max = s1
	p.color = col
	if additive:
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = add
	add_child(p)
	return p


func _on_state_changed(st: IronPump.State) -> void:
	match st:
		IronPump.State.STAGGER:
			_jolt(-1.0, -4.0)
			_spark_burst(14)
		IronPump.State.BROKEN:
			_jolt(1.6, 2.0)
			_puff(12, 0.0)
			_spark_burst(14)
			Sfx.play("guard_break", -2.0, 0.05)
		IronPump.State.FALLEN:
			_jolt(2.4, 1.5)
			_puff(18, 0.0)
			_steam.emitting = true
		IronPump.State.INTRO:
			_jolt(1.2, 0.0)


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
				IronPump.State.SPRAY:
					_jolt(0.3, 0.0)
				IronPump.State.SUCK:
					_inhale.emitting = true
		if _prev_phase == "active" and st == IronPump.State.SUCK:
			_inhale.emitting = false
		_prev_phase = ph
	if st != IronPump.State.SUCK:
		_inhale.emitting = false
	if _boss.anim_hint == "stagger" and _prev_hint != "stagger" and st == IronPump.State.SUCK:
		_jolt(-0.8, -4.0)
		_inhale.emitting = false
	_prev_hint = _boss.anim_hint
	if _boss._bit and not _prev_bit:
		_recoil_v -= 14.0   # 물기: 관이 앞으로 덥석
		_jolt(0.5, 2.0)
	_prev_bit = _boss._bit
	var fl := _boss.flash_amount()
	if fl > _prev_flash + 0.4 and st not in [IronPump.State.BROKEN, IronPump.State.FALLEN, IronPump.State.STAGGER]:
		_jolt(0.25, -0.6)
	_prev_flash = fl
	_drips.emitting = _boss.phase == 2 and st not in [IronPump.State.FALLEN, IronPump.State.PURIFIED, IronPump.State.WAIT]

	# ---- 목표 자세 ----
	var target := NEUTRAL
	var follow := 9.0
	var ghost := false
	var ext_target := 0.1 + 0.1 * sin(_t * TAU / (2.0 * BEAT))
	var ext_follow := 8.0
	var noz_target := _aim_angle()
	var open_target := 0.15
	var plates_target := 0.0
	var core_target := 0.3 + 0.1 * sin(_t * 2.0)
	var tremble := 0.0
	# 기계의 숨: 매 박 '쿵'
	var thump := exp(-7.0 * fmod(_t, BEAT) / BEAT)
	target.z += 0.014 * thump
	target.w += -5.0 * thump
	match st:
		IronPump.State.IDLE, IronPump.State.INTRO:
			_dist += speed * delta
			var amount := clampf(speed / _boss.crawl_speed, 0.0, 1.2)
			var bob := Motion.step_bob(_dist, STRIDE)
			target.w += -bob * 10.0 * amount
			target.x = 0.04 * amount * signf(_boss.velocity.x)
			var step := int(floor(_dist / STRIDE))
			if step != _last_step:
				_last_step = step
				if amount > 0.3:
					_puff(6, -signf(_boss.velocity.x) * 120.0)
					_imp_v += 0.5
		IronPump.State.PISTON:
			var p := _boss.phase_progress()
			match ph:
				"startup":
					target = NEUTRAL.lerp(Vector4(-0.1 * f, 0.98, 1.05, -10.0), Motion.anticipation(p))
					ext_target = lerpf(0.1, -0.4, Motion.anticipation(p))
					ext_follow = 7.0
					tremble = clampf((p - 0.55) / 0.45, 0.0, 1.0)
					core_target = 0.5
				"active":
					target = Vector4(-0.1 * f, 0.98, 1.05, -10.0).lerp(Vector4(0.14 * f, 1.1, 0.86, 26.0), Motion.strike(clampf(p / 0.5, 0.0, 1.0)))
					ext_target = 1.0
					ext_follow = 60.0
					ghost = true
				"recovery":
					target = Vector4(0.14 * f, 1.1, 0.86, 26.0).lerp(NEUTRAL, Motion.settle(p))
					ext_target = lerpf(1.0, 0.1, Motion.settle(p, 1.5, 3.0))
					ext_follow = 10.0
			follow = _beat_follow()
		IronPump.State.SPRAY:
			var p := _boss.phase_progress()
			open_target = 0.6
			core_target = 0.6
			match ph:
				"startup":
					target = NEUTRAL.lerp(Vector4(0.05 * f, 0.97, 1.03, -4.0), Motion.anticipation(p))
					tremble = clampf((p - 0.6) / 0.4, 0.0, 1.0) * 0.5
				"active":
					target = Vector4(0.05 * f, 0.97, 1.03, -4.0)
				"recovery":
					target = Vector4(0.05 * f, 0.97, 1.03, -4.0).lerp(NEUTRAL, Motion.settle(p))
					open_target = 0.25
			follow = _beat_follow()
		IronPump.State.SUCK:
			var p := _boss.phase_progress()
			open_target = 1.0
			core_target = 0.7
			match ph:
				"startup":
					target = NEUTRAL.lerp(Vector4(0.1 * f, 0.96, 1.04, -6.0), Motion.anticipation(p))
				"active":
					# 들이마시며 몸이 조금씩 부푼다
					target = Vector4(0.1 * f, 0.96 + 0.1 * p, 1.04 + 0.03 * p, -6.0)
					tremble = 0.4
				"recovery":
					target = Vector4(0.1 * f, 1.06, 1.07, -6.0).lerp(NEUTRAL, Motion.settle(p))
					open_target = 0.3
			follow = _beat_follow()
		IronPump.State.STAGGER:
			var k := _boss.state_progress(_boss.stagger_len)
			target = Vector4(-0.25 * f, 0.94, 1.05, 6.0).lerp(NEUTRAL, Motion.settle(k, 1.5, 3.0))
			follow = 12.0
			tremble = 1.0 - k
		IronPump.State.BROKEN:
			target = Vector4(0.08 * f, 1.04, 0.94, 40.0)
			target.z += Motion.breathe(_t, 0.5, 0.02)
			plates_target = 1.0
			core_target = 1.0 + 0.3 * sin(_t * 6.0)
			ext_target = 0.6
			open_target = 0.5
			follow = 6.0
		IronPump.State.FALLEN, IronPump.State.PURIFIED:
			target = Vector4(0.22 * f, 1.0, 0.96, 80.0)
			plates_target = 1.0
			core_target = 0.15 if st == IronPump.State.FALLEN else 0.0
			ext_target = 1.0
			noz_target = 0.6
			open_target = 0.2
			follow = 5.0
	if _boss.anim_hint == "stagger" and st == IronPump.State.SUCK:
		var k := _boss.phase_progress()
		target = Vector4(-0.3 * f, 0.93, 1.06, 6.0).lerp(NEUTRAL, Motion.settle(k, 2.0, 3.5))
		follow = 10.0

	# ---- 보간 ----
	_pose = Vector4(
		Motion.damp(_pose.x, target.x, follow, delta),
		Motion.damp(_pose.y, target.y, follow, delta),
		Motion.damp(_pose.z, target.z, follow, delta),
		Motion.damp(_pose.w, target.w, follow, delta))
	var s := Motion.spring(_imp, 0.0, _imp_v, 360.0, 13.0, delta)
	_imp = s[0]; _imp_v = s[1]
	s = Motion.spring(_kick, 0.0, _kick_v, 200.0, 9.0, delta)
	_kick = s[0]; _kick_v = s[1]
	s = Motion.spring(_recoil, 0.0, _recoil_v, 300.0, 10.0, delta)
	_recoil = s[0]; _recoil_v = s[1]
	_ext = Motion.damp(_ext, ext_target, ext_follow, delta)
	_noz = Motion.damp(_noz, noz_target, 6.0, delta)
	_open = Motion.damp(_open, open_target, 7.0, delta)
	_plates = Motion.damp(_plates, plates_target, 5.0, delta)
	_core = Motion.damp(_core, core_target, 6.0, delta)
	_tremble = Motion.damp(_tremble, tremble, 10.0, delta)
	_face = Motion.damp(_face, f, 9.0, delta)
	var fx := -_face
	if absf(fx) < 0.03:
		fx = 0.03 * (1.0 if fx >= 0.0 else -1.0)
	var tilt := _pose.x + _kick + sin(_t * 46.0) * 0.012 * _tremble
	var sq := Vector2(_pose.y + _imp * 0.6, _pose.z - _imp * 0.9)
	var dy := _pose.w + _imp * 36.0
	rotation = tilt
	scale = Vector2(_base_scale.x * sq.x * fx, _base_scale.y * maxf(sq.y, 0.05))
	position = _base_pos + Vector2(sin(_t * 60.0) * 4.0 * _tremble, dy)
	_update_ghosts(delta, ghost)
	if _light:
		_light.position = _light_base + Vector2(0, dy * 0.8)
		_light.energy = 0.6 + 1.6 * _core
		_light.color = TEAL.lerp(Color(1.0, 0.45, 0.3), _red)
	_steam.global_position = global_position + Vector2(0, -80)

	# ---- 색 ----
	_red = Motion.damp(_red, 1.0 if _boss.is_red() else 0.0, 14.0, delta)
	var base := Color(1.0, 0.97, 0.95) if _boss.phase == 1 else Color(1.08, 0.9, 0.84)
	base = base.lerp(Color(2.4, 0.5, 0.4), _red * (0.5 + 0.5 * sin(_t * 32.0)))
	modulate = base.lerp(Color(2.5, 2.5, 2.5), fl * 0.8)
	if draw_parts:
		queue_redraw()


## 관이 소녀를 겨누는 각도 (그림 좌표: 앞 = −x, + = 아래). 멀거나 없으면 정면.
func _aim_angle() -> float:
	if _boss.player == null or not is_instance_valid(_boss.player):
		return 0.0
	var pivot := to_global(NOZ_PIVOT)   # 지금의 배율·뒤집힘을 그대로 거친 관의 축
	var d := _boss.player.global_position + Vector2(0, -60) - pivot
	return clampf(atan2(d.y, maxf(absf(d.x), 1.0)), -0.45, 0.6)


func _beat_follow() -> float:
	match _boss.attack_phase:
		"startup": return 10.0
		"active": return 36.0
		"recovery": return 11.0
	return 9.0


func _puff(n: int, ox: float) -> void:
	_dust.amount = n
	_dust.global_position = _boss.global_position + Vector2(ox, 0)
	_dust.restart()
	_dust.emitting = true


func _spark_burst(n: int) -> void:
	_sparks.amount = n
	_sparks.global_position = _boss.global_position + Vector2(0, -180)
	_sparks.restart()
	_sparks.emitting = true


func _update_ghosts(delta: float, active: bool) -> void:
	if active:
		_ghost_timer += delta
		if _ghost_timer >= 0.04:
			_ghost_timer = 0.0
			var g: Sprite2D = _ghosts.pop_front()
			g.visible = true
			g.global_transform = global_transform
			g.modulate = Color(1.0, 0.7, 0.5, 0.3)
			_ghosts.append(g)
	else:
		_ghost_timer = 0.0
	for g in _ghosts:
		if g.visible:
			g.modulate.a -= delta * 2.4
			if g.modulate.a <= 0.0:
				g.visible = false


## 그림에 없는 부품: 피스톤 팔(실린더 캡·막대·망치 머리), 관(노즐), 장갑 덮개, 핵. 그림 픽셀 좌표(가운데 원점)로 그린다.
func _draw() -> void:
	if not draw_parts:
		return
	var open := clampf(_plates, 0.0, 1.0)
	# 핵 (덮개가 열리면 드러난다): 빛 → 수액 구슬
	var core_a := clampf(0.25 + 0.75 * open, 0.0, 1.0)
	draw_circle(CORE_POS, 150.0 * (0.8 + 0.2 * _core), Color(TEAL, 0.12 * _core * core_a))
	draw_circle(CORE_POS, 95.0, Color(0.12, 0.45, 0.55, core_a))
	draw_circle(CORE_POS, 80.0 * (0.9 + 0.1 * sin(_t * 9.0)), Color(TEAL.lightened(0.2 * _core), core_a))
	draw_circle(CORE_POS + Vector2(-22, -24), 26.0, Color(1, 1, 1, 0.7 * core_a))
	# 장갑 덮개 두 짝 (닫히면 핵을 덮고, 열리면 양옆으로 벌어진다)
	var slide := open * 120.0
	var lp := Rect2(Vector2(-78.0 - slide, -42.0), Vector2(125.0, 250.0))
	var rp := Rect2(Vector2(47.0 + slide, -42.0), Vector2(125.0, 250.0))
	for r in [lp, rp]:
		draw_rect(r, RUST)
		draw_rect(r, RUST_DARK, false, 6.0)
		draw_rect(Rect2(r.position + Vector2(18, 18), Vector2(r.size.x - 36.0, 6.0)), RUST_DARK)
		draw_circle(r.position + Vector2(24, 48), 9.0, RUST_DARK)
		draw_circle(r.position + Vector2(r.size.x - 24.0, 48), 9.0, RUST_DARK)
	# 피스톤: 실린더 캡(위의 가로 막대) → 막대 → 망치 머리
	# 망치 머리가 땅(보스 발 높이)을 뚫고 들어가 보이지 않게, 몸의 기울기·찌그러짐을 거친 바닥선 위에서 멈춘다
	var head_y := minf(lerpf(HEAD_REST, HEAD_SLAM, _ext), _floor_local_y([-680.0, -460.0]) - 100.0 + 4.0)
	draw_rect(Rect2(Vector2(-620, -300), Vector2(312, 50)), RUST.darkened(0.05))
	draw_rect(Rect2(Vector2(-620, -300), Vector2(312, 50)), RUST_DARK, false, 5.0)
	draw_rect(Rect2(Vector2(-596, -250), Vector2(56, maxf(head_y + 250.0, 10.0))), STEEL)
	draw_line(Vector2(-586, -250), Vector2(-586, head_y), STEEL.lightened(0.25), 8.0)
	var head := Rect2(Vector2(-680, head_y), Vector2(220, 100))
	draw_rect(head, RUST)
	draw_rect(head, RUST_DARK, false, 6.0)
	for i in 3:
		draw_circle(head.position + Vector2(36.0 + i * 74.0, 50), 9.0, RUST_DARK)
	if _ext > 0.9:
		# 땅을 친 순간: 머리 아래 먼지 띠
		draw_rect(Rect2(Vector2(-720, head_y + 92), Vector2(300, 14)), Color(0.6, 0.5, 0.42, (_ext - 0.9) * 4.0))
	# 관(노즐): 몸 앞 아래에서 소녀 쪽으로 뻗는다. 반동이면 뒤로 밀린다.
	var dir := Vector2(-cos(_noz), sin(_noz))
	var back := dir * _recoil * -6.0
	var p0 := NOZ_PIVOT + back
	var p1 := p0 + dir * NOZ_LEN
	draw_line(p0, p1, RUST_DARK, 96.0)
	draw_line(p0, p1, RUST, 80.0)
	draw_line(p0 + dir * 60.0, p1 - dir * 30.0, RUST.lightened(0.12), 20.0)
	for i in 3:
		var q := p0 + dir * (70.0 + i * 80.0)
		draw_line(q + dir.orthogonal() * 46.0, q - dir.orthogonal() * 46.0, RUST_DARK, 8.0)
	# 입: 벌어질수록 크고 어두워지며 안쪽에 수액빛
	var mouth_r := 46.0 + 30.0 * _open
	draw_circle(p1, mouth_r + 8.0, RUST_DARK)
	draw_circle(p1, mouth_r, Color(0.05, 0.1, 0.12))
	draw_circle(p1, mouth_r * 0.6, Color(TEAL, 0.25 + 0.6 * _open))
	if _boss.state == IronPump.State.SUCK and _boss.attack_phase == "active" and _boss.player and is_instance_valid(_boss.player):
		_draw_suck_stream(p1, mouth_r)
	if _open > 0.5:
		# 들이마시는 소용돌이
		for i in 3:
			var a := _t * 10.0 + i * 2.1
			draw_arc(p1, mouth_r * (0.35 + 0.2 * i), a, a + 2.2, 10, Color(TEAL.lightened(0.3), (_open - 0.5) * 1.2), 4.0, true)


## 그림 좌표에서 보스 발 높이(부모 y = 0)가 되는 y. xs 의 여러 x 가운데 가장 위(작은 값) — 기울면 앞 모서리가 먼저 닿는다.
func _floor_local_y(xs: Array) -> float:
	var t := transform
	var best := INF
	for x in xs:
		if absf(t.y.y) < 0.0001:
			continue
		best = minf(best, -(t.origin.y + t.x.y * float(x)) / t.y.y)
	return best if best < INF else HEAD_SLAM + 100.0


## 빨아들이기: 소녀와 관 입 사이에 빨려 드는 수액빛 띠 (흐르는 줄 여러 가닥 + 빛 알갱이). 그림 좌표.
func _draw_suck_stream(mouth: Vector2, mouth_r: float) -> void:
	var from := to_local(_boss.player.global_position + Vector2(0, -60))
	var span := mouth - from
	var len := span.length()
	if len < 10.0:
		return
	var along := span / len
	var side := along.orthogonal()
	var p := _boss.phase_progress()
	var a := clampf(p * 4.0, 0.0, 1.0)
	# 띠의 바탕: 소녀 쪽은 넓고 흐리게, 입 쪽은 좁고 진하게
	var band := PackedVector2Array([from + side * 130.0, mouth + side * mouth_r * 0.7, mouth - side * mouth_r * 0.7, from - side * 130.0])
	draw_colored_polygon(band, Color(TEAL, 0.07 * a))
	# 흐르는 줄: 소녀 쪽에서 입 쪽으로 빠르게 미끄러진다
	for i in 9:
		var k := fposmod(_t * 1.8 + i / 9.0, 1.0)
		var off := sin(i * 2.3) * 110.0 * (1.0 - k)
		var q0 := from + span * k + side * off
		var q1 := from + span * minf(k + 0.14, 1.0) + side * off * 0.8
		draw_line(q0, q1, Color(TEAL.lightened(0.35), 0.55 * a * (0.4 + 0.6 * k)), 10.0 + 8.0 * k, true)
	# 빛 알갱이
	for i in 7:
		var k := fposmod(_t * 1.25 + i / 7.0, 1.0)
		var q := from + span * k + side * sin(_t * 5.0 + i) * 70.0 * (1.0 - k)
		draw_circle(q, 9.0 + 6.0 * k, Color(1.0, 1.0, 1.0, 0.5 * a))

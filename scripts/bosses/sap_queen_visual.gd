extends Sprite2D
## 수액의 여왕 그림(boss_sap_queen_now.png — 지금은 임시 그림)을 상태에 맞춰 움직인다.
## 원칙: 자세 값은 '툭' 바뀌지 않는다 — 매 프레임 목표 자세를 정하고 Motion.damp/스프링으로 쫓는다 (새·기사·뿌리지기와 같은 약속).
## 날갯짓: 가로 찌그러짐(scale.x)이 위상 누적기로 접혔다 펴진다(나비를 위에서 본 그림이라 가로가 접힌다).
## 3박자 보이기: 예고 동안 '하나·둘'마다 몸 둘레에 고리가 한 겹씩 번지고(1개, 2개), '셋'에 터진다 — 소리 없이도 박자가 보인다.
## 2페이즈: 날개에 검은 금(crack_amount)과 흘러내리는 수액 방울(입자)이 는다.
## 세기 조절: 아래 상수.
## 스킨 자리: 진짜 그림이 오면 art_faces_right 만 맞춘다 (그림이 오른쪽을 보면 true, 왼쪽이면 false, 정면이면 상관없음).

## 그림이 오른쪽을 보는가 (새와 같은 규칙: 오른쪽을 보는 그림은 소녀가 왼쪽에 있으면 뒤집는다)
@export var art_faces_right := true

const NEUTRAL := Vector4(0.0, 1.0, 1.0, 0.0)
## 날갯짓 빠르기(rad/s)·크기: 떠 있을 때 / 예고 / 내려앉았을 때
const FLAP_HOVER := 6.5
const FLAP_AMP_HOVER := 0.1
const FLAP_TELEGRAPH := 13.0
const FLAP_LANDED := 2.2
## 박자 고리 반지름(px)과 두께
const RING_R := 150.0
const RING_W := 3.0

var _boss: SapQueen
var _t := 0.0
var _base_scale := Vector2.ONE
var _base_pos := Vector2.ZERO
var _pose := NEUTRAL
var _imp := 0.0
var _imp_v := 0.0
var _kick := 0.0
var _kick_v := 0.0
var _face := -1.0
var _flap_phase := 0.0
var _flap_rate := FLAP_HOVER
var _flap_amp := FLAP_AMP_HOVER
var _prev_state := -1
var _prev_phase := ""
var _prev_flash := 0.0
var _was_floor := false
var _beat_pulse := 0.0       # 박이 바뀐 순간 1 → 0
var _beat_at := 0
var _burst := 0.0            # '셋' 터짐 1 → 0
var _drips: CPUParticles2D
var _shimmer: CPUParticles2D
var _dust: CPUParticles2D
var _ghosts: Array[Sprite2D] = []
var _ghost_timer := 0.0
var _marks: Node2D
var _crack_seed := 7
var _crack_lines: Array = []   # 2페이즈 금: [시작점, [방향·길이]...] — _ready 에서 한 번만 만든다 (매 프레임 난수 안 씀)


func _ready() -> void:
	_boss = get_parent() as SapQueen
	_base_scale = scale
	_base_pos = position
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _boss:
		_face = float(_boss.facing)
		_boss.state_changed.connect(_on_state_changed)
		_boss.beat.connect(_on_beat)
	# 박자 고리·착지 충격은 세계 좌표에 그린다 (그림의 찌그러짐·회전과 무관하게)
	_marks = Node2D.new()
	_marks.top_level = true
	# 여왕 그림 바로 뒤, 배경·지형·수면보다는 앞 (z -1 이면 불투명한 배경 뒤에 숨어 안 보였다 — 2026-10-19 검토)
	_marks.z_index = 0
	_marks.show_behind_parent = true
	add_child(_marks)
	_marks.draw.connect(_draw_marks)
	# 흘러내리는 수액 방울
	_drips = CPUParticles2D.new()
	_drips.amount = 10
	_drips.lifetime = 1.4
	_drips.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_drips.emission_rect_extents = Vector2(220, 30)
	_drips.position = Vector2(0, 120)
	_drips.direction = Vector2(0, 1)
	_drips.spread = 8.0
	_drips.gravity = Vector2(0, 420)
	_drips.initial_velocity_min = 10.0
	_drips.initial_velocity_max = 40.0
	_drips.scale_amount_min = 3.0
	_drips.scale_amount_max = 6.0
	_drips.color = Color(0.5, 0.9, 1.0, 0.8)
	_drips.local_coords = false
	add_child(_drips)
	# 예고의 반짝이는 날개가루
	_shimmer = CPUParticles2D.new()
	_shimmer.amount = 26
	_shimmer.lifetime = 0.8
	_shimmer.emitting = false
	_shimmer.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_shimmer.emission_rect_extents = Vector2(520, 160)
	_shimmer.direction = Vector2(0, -1)
	_shimmer.spread = 180.0
	_shimmer.gravity = Vector2(0, -40)
	_shimmer.initial_velocity_min = 10.0
	_shimmer.initial_velocity_max = 50.0
	_shimmer.scale_amount_min = 2.0
	_shimmer.scale_amount_max = 5.0
	_shimmer.color = Color(1.2, 1.4, 1.5, 0.9)
	_shimmer.local_coords = false
	add_child(_shimmer)
	# 착지 먼지·물보라
	_dust = CPUParticles2D.new()
	_dust.top_level = true
	_dust.emitting = false
	_dust.one_shot = true
	_dust.explosiveness = 1.0
	_dust.amount = 16
	_dust.lifetime = 0.6
	_dust.direction = Vector2(0, -1)
	_dust.spread = 85.0
	_dust.gravity = Vector2(0, 300)
	_dust.initial_velocity_min = 100.0
	_dust.initial_velocity_max = 320.0
	_dust.scale_amount_min = 3.0
	_dust.scale_amount_max = 8.0
	_dust.color = Color(0.7, 0.95, 1.0, 0.7)
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
	_build_cracks()


## 2페이즈 날개의 금 모양을 미리 만든다 (그림 좌표). 그릴 때는 crack_amount 만큼 늘인다.
func _build_cracks() -> void:
	_crack_lines.clear()
	if texture == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _crack_seed
	var sz := texture.get_size()
	for i in 10:
		var start := Vector2(rng.randf_range(-sz.x * 0.42, sz.x * 0.42), rng.randf_range(-sz.y * 0.25, sz.y * 0.2))
		var steps: Array = []
		var segs := 4 + rng.randi() % 4
		var dir := Vector2(signf(start.x), rng.randf_range(-0.6, 0.6)).normalized()
		for j in segs:
			dir = dir.rotated(rng.randf_range(-0.7, 0.7))
			steps.append(Vector2(dir.x * rng.randf_range(30.0, 90.0), dir.y * rng.randf_range(30.0, 90.0)))
		_crack_lines.append([start, steps])


func _on_state_changed(st: SapQueen.State) -> void:
	match st:
		SapQueen.State.LANDED:
			_jolt(2.4, 0.6)
			_puff(0.0)
			_burst = 1.0   # 셋째 박에 앉는 순간 터지는 고리
		SapQueen.State.CRACK:
			_jolt(1.0, -2.0)
		SapQueen.State.BROKEN:
			_jolt(1.6, 2.5)
		SapQueen.State.FALLEN:
			_jolt(2.0, 1.5)
	_prev_state = st


func _on_beat(i: int) -> void:
	_beat_pulse = 1.0
	_beat_at = i
	if _boss and _boss.attack_phase == "active" and i == 2:
		_burst = 1.0


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
	# ---- 일회성 사건 ----
	if ph != _prev_phase:
		if ph == "active":
			_burst = 1.0
			match st:
				SapQueen.State.DUST:
					_jolt(0.8, -0.6)
				SapQueen.State.WAVE:
					_jolt(1.4, 0.8)
					_puff(0.0)
				SapQueen.State.BUTTERFLIES:
					_jolt(0.5, -0.8)
		_prev_phase = ph
	var fl := _boss.flash_amount()
	if fl > _prev_flash + 0.4 and st not in [SapQueen.State.BROKEN, SapQueen.State.FALLEN]:
		_jolt(0.3, -0.7)
	_prev_flash = fl
	var on_floor := _boss.is_on_floor()
	if on_floor and not _was_floor and st in [SapQueen.State.BROKEN, SapQueen.State.FALLEN]:
		_jolt(1.8, 1.0)
		_puff(0.0)
	_was_floor = on_floor
	_beat_pulse = maxf(_beat_pulse - delta * 3.0, 0.0)
	_burst = maxf(_burst - delta * 2.6, 0.0)

	# ---- 목표 자세 ----
	var target := NEUTRAL
	var follow := 9.0
	var rate := FLAP_HOVER
	var amp := FLAP_AMP_HOVER
	var ghost := false
	var air_tilt := clampf(_boss.velocity.x / 2200.0, -0.14, 0.14)
	var tg := _boss.telegraph_amount
	match st:
		SapQueen.State.HOVER, SapQueen.State.INTRO, SapQueen.State.TAKEOFF:
			target.x = air_tilt
			target.w = Motion.breathe(_t, 0.45, 6.0)
			if st == SapQueen.State.TAKEOFF:
				rate = 10.0; amp = 0.14
				target.z = 1.05
		SapQueen.State.DUST:
			# 예고: 날개를 활짝 펴고 떨며(반짝) → 셋에 털어 낸다
			rate = FLAP_HOVER + tg * (FLAP_TELEGRAPH - FLAP_HOVER); amp = 0.06 + 0.1 * tg
			target = Vector4(air_tilt, 1.0 + 0.1 * tg, 1.0 - 0.04 * tg, -14.0 * tg)
			if ph == "active":
				target.z = 1.08
				target.w = 10.0
				follow = 20.0
				ghost = true
		SapQueen.State.WAVE:
			# 아래로 몸을 숙이며 내려오고(예고) → 셋에 수면을 친다(눌림) → 떠오른다
			rate = 8.0 + tg * 5.0; amp = 0.08
			target = Vector4(0.08 * f * tg, 1.0, 1.0 + 0.06 * tg, 10.0 * tg)
			if ph == "active":
				target = Vector4(0.1 * f, 1.14, 0.84, 26.0)
				follow = 24.0
			elif ph == "recovery":
				target = Vector4(-0.05 * f, 0.98, 1.04, -8.0)
		SapQueen.State.BUTTERFLIES:
			# 날개를 모으며 나비를 빚는다 → 셋에 펼치며 날려 보낸다
			rate = 5.0; amp = 0.04 + 0.12 * tg
			target = Vector4(-0.06 * f * tg, 1.0 - 0.14 * tg, 1.0 + 0.08 * tg, -10.0 * tg)
			if ph == "active":
				target = Vector4(0.08 * f, 1.12, 0.96, 6.0)
				follow = 22.0
				rate = 16.0; amp = 0.14
				ghost = true
		SapQueen.State.LAND:
			rate = 9.0 + tg * 4.0; amp = 0.12
			target = Vector4(air_tilt, 1.0 + 0.05 * tg, 1.0 + 0.06 * tg, 0.0)
			var dv := _boss.dive_amount
			if dv > 0.0:
				# 내려꽂기: 날개를 접고 세로로 길게 (셋째 박에 앉는다)
				target = target.lerp(Vector4(0.0, 0.9, 1.14, 0.0), clampf(dv * 1.5, 0.0, 1.0))
				rate = 4.0; amp = 0.04
				follow = 22.0
				ghost = true
		SapQueen.State.LANDED:
			# 춤추듯 쉰다: 왈츠 박에 맞춰 좌우로 흔들며 숨쉬기. 날개는 천천히
			rate = FLAP_LANDED; amp = 0.05
			var bp := _boss.beat_phase()
			var bi := _boss.beat_index()
			var sway := sin((bi + bp) / 3.0 * TAU) * 0.08
			target = Vector4(sway, 1.0 + 0.02 * sin(bp * PI), 0.98 + 0.03 * sin(bp * PI), 12.0 + 4.0 * sin(bp * PI))
			follow = 7.0
		SapQueen.State.CRACK:
			rate = 24.0; amp = 0.05
			target = Vector4(sin(_t * 28.0) * 0.06, 0.94, 1.08, -6.0)
			follow = 18.0
		SapQueen.State.BROKEN:
			rate = 1.5; amp = 0.03
			target = Vector4(0.35 * f, 1.04, 0.9, 40.0)
			target.z += Motion.breathe(_t, 0.7, 0.025)
			follow = 6.0
		SapQueen.State.FALLEN, SapQueen.State.PURIFIED:
			rate = 0.6; amp = 0.02
			target = Vector4(0.55 * f, 1.0, 0.9, 70.0)
			follow = 5.0
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
	_flap_rate = Motion.damp(_flap_rate, rate, 6.0, delta)
	_flap_amp = Motion.damp(_flap_amp, amp, 8.0, delta)
	_flap_phase += _flap_rate * delta
	var flap := 1.0 - absf(sin(_flap_phase)) * _flap_amp   # 접혔다 펴짐 (가로)
	_face = Motion.damp(_face, f, 11.0, delta)
	# 오른쪽을 보는 그림은 왼쪽을 볼 때 뒤집는다 (새와 같은 규칙). 왼쪽을 보는 그림이면 반대.
	var fx := _face if art_faces_right else -_face
	if absf(fx) < 0.03:
		fx = 0.03 * (1.0 if fx >= 0.0 else -1.0)
	var tilt := _pose.x + _kick
	var sq := Vector2((_pose.y + _imp * 0.5) * flap, _pose.z - _imp)
	var dy := _pose.w + _imp * 40.0
	rotation = tilt
	scale = Vector2(_base_scale.x * sq.x * fx, _base_scale.y * maxf(sq.y, 0.05))
	position = _base_pos + Vector2(0, dy)
	_update_ghosts(delta, ghost)
	# 입자
	_shimmer.emitting = tg > 0.05 and st in [SapQueen.State.DUST, SapQueen.State.BUTTERFLIES]
	_shimmer.global_position = global_position
	# 2페이즈일수록 수액이 많이 흘러내린다 (CPUParticles2D 는 amount_ratio 가 없어 진하기·속도로)
	_drips.modulate = Color(1, 1, 1, 0.45 + 0.55 * _boss.crack_amount)
	_drips.speed_scale = 0.8 + 0.7 * _boss.crack_amount
	_drips.global_position = _boss.global_position + Vector2(0, -60)
	# ---- 색: 수액빛 바탕, 예고 반짝임, 피격 번쩍, 2페이즈 조금 어둡고 누렇게 ----
	var base := Color(0.95, 1.0, 1.05) if _boss.phase == 1 else Color(0.9, 0.92, 0.9)
	base = base.lerp(Color(1.35, 1.5, 1.6), tg * (0.6 + 0.4 * sin(_t * 26.0)))
	base = base.lerp(Color(1.6, 1.7, 1.8), _burst * 0.5)
	if st in [SapQueen.State.FALLEN, SapQueen.State.PURIFIED]:
		base = base.lerp(Color(0.6, 0.62, 0.66), 0.6)
	modulate = base.lerp(Color(2.2, 2.2, 2.2), fl * 0.8)
	queue_redraw()
	_marks.queue_redraw()


func _puff(ox: float) -> void:
	_dust.global_position = _boss.global_position + Vector2(ox, 0)
	_dust.restart()
	_dust.emitting = true


func _update_ghosts(delta: float, active: bool) -> void:
	if active:
		_ghost_timer += delta
		if _ghost_timer >= 0.05:
			_ghost_timer = 0.0
			var g: Sprite2D = _ghosts.pop_front()
			g.visible = true
			g.global_transform = global_transform
			g.modulate = Color(0.7, 0.95, 1.0, 0.3)
			_ghosts.append(g)
	else:
		_ghost_timer = 0.0
	for g in _ghosts:
		if g.visible:
			g.modulate.a -= delta * 2.4
			if g.modulate.a <= 0.0:
				g.visible = false


## 그림 위에 그리는 것: 2페이즈 날개의 검은 금 (그림 좌표라 찌그러짐·회전을 같이 탄다)
func _draw() -> void:
	if _boss == null or _boss.crack_amount <= 0.01 or _crack_lines.is_empty():
		return
	var k := _boss.crack_amount
	for line in _crack_lines:
		var p: Vector2 = line[0]
		var pts := PackedVector2Array([p])
		for step in line[1]:
			p += step * k
			pts.append(p)
		# 그림 좌표라 화면에선 배율(0.36)만큼 가늘어진다 → 넉넉히 굵게
		draw_polyline(pts, Color(0.05, 0.03, 0.03, 0.85 * k), 20.0, true)
		draw_polyline(pts, Color(0.35, 0.8, 0.9, 0.55 * k), 7.0, true)


## 세계 좌표에 그리는 것: 박자 고리 (하나 1겹, 둘 2겹, 셋 터짐), 내려앉을 디딤돌의 자국
func _draw_marks() -> void:
	if _boss == null or not _boss.visible:
		return
	var c := _boss.global_position + Vector2(0, -120)
	var st := _boss.state
	if _boss.attack_phase == "startup":
		var rings := 1 + _boss.beat_index() % 3
		rings = mini(rings, 2)
		for i in rings:
			var r := RING_R + i * 34.0 + (1.0 - _beat_pulse) * 12.0
			_marks.draw_arc(c, r, 0.0, TAU, 48, Color(0.75, 0.98, 1.0, 0.25 + 0.45 * _beat_pulse), RING_W + 2.0 * _beat_pulse, true)
	if _burst > 0.0:
		var r := RING_R + (1.0 - _burst) * 220.0
		_marks.draw_arc(c, r, 0.0, TAU, 56, Color(0.9, 1.0, 1.0, 0.6 * _burst), RING_W * 2.0 * _burst + 1.0, true)
	# 내려앉기 예고: 디딤돌 위에 빛 자국
	if st == SapQueen.State.LAND and _boss._land_stone and is_instance_valid(_boss._land_stone):
		var s: Node2D = _boss._land_stone
		var top := Vector2(s.global_position.x, s.global_position.y)
		var w: float = s.size.x
		var p := _boss.windup_progress
		var pulse := 0.5 + 0.5 * sin(_t * (8.0 + 20.0 * p))
		_marks.draw_rect(Rect2(top + Vector2(0, -8), Vector2(w, 10)), Color(0.8, 1.0, 1.0, 0.2 + 0.4 * p * pulse))

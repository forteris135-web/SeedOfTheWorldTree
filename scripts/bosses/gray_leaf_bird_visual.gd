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
var _muzzle: MuzzleDot
var _band: RainBand
var _band_front: RainBand


## 깃털 발사 예고: 부리 앞 붉은 점 + 조여드는 고리, 한 발마다 번쩍 (보스의 feather_warn / muzzle_flash 를 읽는다).
## 날갯바람의 '몸 전체 붉은 빛'(가드 불가)과는 다르게 작은 점이다 — 깃털은 가드·저스트 가드가 된다.
class MuzzleDot extends Node2D:
	var amount := 0.0
	var flash := 0.0
	var t := 0.0
	const RED := Color(2.2, 0.45, 0.35)
	func _draw() -> void:
		if amount <= 0.01 and flash <= 0.01:
			return
		var a := clampf(amount, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(t * 22.0)
		# 조여드는 고리 (멀리서 점으로 모인다 = '지금 온다')
		var ring_r := lerpf(56.0, 18.0, a)
		draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 32, Color(RED, a * (0.55 + 0.35 * pulse)), 3.0, true)
		# 붉은 점
		var dot_r := (9.0 + 3.0 * pulse) * (0.6 + 0.4 * a)
		draw_circle(Vector2.ZERO, dot_r * 1.9, Color(RED, a * 0.22))
		draw_circle(Vector2.ZERO, dot_r, Color(RED, a * 0.95))
		draw_circle(Vector2.ZERO, dot_r * 0.45, Color(2.6, 1.6, 1.4, a))
		# 발사 번쩍임: 터지는 원 + 짧은 빛살 6개
		if flash > 0.01:
			var f := clampf(flash, 0.0, 1.0)
			var burst := lerpf(44.0, 14.0, f)
			draw_circle(Vector2.ZERO, burst, Color(2.4, 1.2, 0.9, f * 0.5))
			for i in 6:
				var ang := i * TAU / 6.0 + t * 3.0
				var d := Vector2(cos(ang), sin(ang))
				draw_line(d * burst * 0.6, d * burst * 1.5, Color(2.4, 1.3, 1.0, f * 0.8), 2.0, true)


## 잎 흩날리기 예고: 떨어질 구간 위쪽의 옅은 흰 띠 (1페이즈 = 싸움터 가로 전체, 2페이즈 = 새 몸 주위 고리).
## amount 는 보스의 rain_warn (예고 때 1, 떨어지는 동안 0.45).
## 새 그림의 **뒤**에 그린다: top_level 이 아닌 자식 + show_behind_parent (top_level 은 맨 위로 올라가 새·잎·소녀를 덮었다).
## 방 나무에서 보스 자리에 그려지므로 지형 위, 새·소녀·잎(나중에 붙는 투사체) 아래. 색은 HDR 이 아닌 흰색(글로우로 번지지 않음).
## 2페이즈 고리는 새를 감싸 도는 모양: 윗반은 뒤 노드(새 뒤), 아랫반은 앞 노드(front, 새 앞)가 그린다 —
## 고리 전부를 뒤에 두면 큰 날개에 가려 거의 안 보였다(스크린샷 확인). 앞 노드는 1페이즈 띠를 그리지 않는다.
class RainBand extends Node2D:
	var front := false
	var amount := 0.0
	var arena := Rect2()
	var phase := 1
	var center := Vector2.ZERO   # 2페이즈 고리 중심 (새 몸 가운데)
	var t := 0.0
	## 싸움터 위 경계에서 이만큼 아래. 소녀가 바닥에 서면 화면 위 끝이 싸움터 위 경계보다 ~35px 아래라(레터박스 띠 때문에
	## 카메라가 올라감) 110 으로는 HUD 뒤 화면 맨 위에 걸렸다(스크린샷 확인) → 160 으로 내려 HUD 아래 가운데가 보이게.
	const BAND_TOP := 160.0
	const BAND_H := 80.0
	## 띠 맨 위 채움의 불투명도 (예고 때). 아래로 갈수록 0 (그라디언트 한 장 — 단 사이 이음선 없음).
	const FILL_ALPHA := 0.22
	const LINE_ALPHA := 0.6
	const ARROW_ALPHA := 0.5
	const WHITE := Color(1.0, 1.0, 1.0)
	static var _grad_tex: GradientTexture2D
	func _ready() -> void:
		if _grad_tex == null:
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
			_grad_tex = GradientTexture2D.new()
			_grad_tex.gradient = g
			_grad_tex.width = 4
			_grad_tex.height = 64
			_grad_tex.fill_from = Vector2(0, 0)
			_grad_tex.fill_to = Vector2(0, 1)
	func _draw() -> void:
		if amount <= 0.01:
			return
		var a := clampf(amount, 0.0, 1.0)
		if phase == 1:
			if front:
				return
			var x0 := arena.position.x + 40.0
			var x1 := arena.end.x - 40.0
			var y0 := arena.position.y + BAND_TOP
			# 위가 밝고 아래로 옅어지는 띠 (그라디언트 한 장)
			if _grad_tex:
				draw_texture_rect(_grad_tex, Rect2(x0, y0, x1 - x0, BAND_H), false, Color(WHITE, a * FILL_ALPHA))
			draw_line(Vector2(x0, y0), Vector2(x1, y0), Color(WHITE, a * LINE_ALPHA), 2.0, true)
			# 아래로 흐르는 화살표(v) — 떨어진다는 뜻
			var slide := fmod(t * 1.3, 1.0) * BAND_H
			var x := x0 + 60.0
			while x < x1 - 40.0:
				var y := y0 + slide
				var c := Color(WHITE, a * ARROW_ALPHA * (1.0 - slide / BAND_H))
				draw_polyline(PackedVector2Array([Vector2(x - 12, y - 8), Vector2(x, y + 4), Vector2(x + 12, y - 8)]), c, 2.0, true)
				x += 180.0
		else:
			# 회오리: 새 몸 주위 고리 (잎이 이 고리에서 바깥으로 흩어진다). 뒤 = 윗반(PI~TAU), 앞 = 아랫반(0~PI).
			var a0 := 0.0 if front else PI
			var fill := 0.06 if front else 0.1   # 새 앞에 오는 아랫반은 채움을 더 옅게 (몸을 가리지 않게)
			draw_arc(center, 185.0, a0, a0 + PI, 28, Color(WHITE, a * fill), 44.0, true)
			draw_arc(center, 162.0, a0, a0 + PI, 28, Color(WHITE, a * 0.55), 2.0, true)
			draw_arc(center, 208.0, a0, a0 + PI, 28, Color(WHITE, a * 0.35), 2.0, true)
			for i in 8:
				var ang := i * TAU / 8.0 + t * 2.2
				var d := Vector2(cos(ang), sin(ang))
				if (d.y >= 0.0) != front:
					continue
				var p := center + d * 185.0
				var tang := Vector2(-d.y, d.x)
				draw_polyline(PackedVector2Array([p - d * 10.0 - tang * 10.0, p + d * 6.0, p - d * 10.0 + tang * 10.0]), Color(WHITE, a * ARROW_ALPHA), 2.0, true)


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
	_muzzle = MuzzleDot.new()
	_muzzle.top_level = true
	_muzzle.visible = false
	add_child(_muzzle)
	_band = RainBand.new()
	_band.visible = false
	_band.show_behind_parent = true   # 새 그림 뒤 (top_level 이 아니어야 듣는다)
	_band.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # 부모의 밉맵 필터를 물려받지 않게 (그라디언트엔 밉맵이 없다)
	add_child(_band)
	_band_front = RainBand.new()   # 2페이즈 고리의 아랫반 (새 앞)
	_band_front.front = true
	_band_front.visible = false
	add_child(_band_front)


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
	_update_telegraphs()

	# ---- 색: 잿빛 바탕, 깃털 예고(차가운 밝아짐), 붉은 예고(서서히), 피격 번쩍임 ----
	_red = Motion.damp(_red, 1.0 if _boss.is_red() else 0.0, 14.0, delta)
	var ash := Color(0.78, 0.8, 0.82) if _boss.phase == 1 else Color(0.7, 0.68, 0.7)
	ash = ash.lerp(Color(1.25, 1.35, 1.45), _boss.telegraph_amount * (0.7 + 0.3 * sin(_t * 24.0)))
	ash = ash.lerp(Color(2.2, 0.6, 0.5), _red * (0.5 + 0.5 * sin(_t * 30.0)))
	# self_modulate: 새 그림에만 색을 입힌다 (뒤에 그리는 예고 띠 자식은 물들지 않게)
	self_modulate = ash.lerp(Color(2.0, 2.0, 2.0), fl * 0.8)


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


## 깃털 붉은 점·잎 띠 예고를 보스 값에 맞춘다 (자리는 보스 기준이라 그림의 기울기·뒤집기와 무관).
func _update_telegraphs() -> void:
	if _muzzle:
		_muzzle.amount = _boss.feather_warn
		_muzzle.flash = _boss.muzzle_flash
		_muzzle.t = _t
		_muzzle.global_position = _boss.muzzle_point()
		_muzzle.global_rotation = 0.0
		_muzzle.global_scale = Vector2.ONE
		_muzzle.visible = _muzzle.amount > 0.01 or _muzzle.flash > 0.01
		if _muzzle.visible:
			_muzzle.queue_redraw()
	for b: RainBand in [_band, _band_front]:
		if b == null:
			continue
		b.amount = _boss.rain_warn
		b.arena = _boss.arena
		b.phase = _boss.phase
		b.center = _boss.body_center()
		b.t = _t
		# 부모(새 그림)는 기울고 뒤집히므로 세계 좌표 그대로가 되게 매 프레임 되돌린다 (top_level 이 아니라서)
		b.global_transform = Transform2D.IDENTITY
		b.visible = b.amount > 0.01 and (not b.front or b.phase != 1)
		if b.visible:
			b.queue_redraw()


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

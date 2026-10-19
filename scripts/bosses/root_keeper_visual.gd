extends Sprite2D
## 뿌리지기의 그림. 몸통(art/bosses/parts/boss_rootkeeper_body.png)과 지팡이(…_staff.png) 두 겹 — tools/cut_boss_parts_root.gd 로 잘랐다.
## 원칙: 자세 값은 절대 '툭' 바뀌지 않는다. 매 프레임 '목표 자세'를 정하고 Motion.damp(프레임 독립)로 쫓는다.
## 그 위에 '충격 스프링'(지팡이 내리꽂기·벽 돌진 멈춤·휘청·피격)이 한 겹 더 얹힌다.
## 공격은 세 박자(예비 → 타격 → 되돌림)로, 진행도는 보스가 공개한 단계 길이로 계산한다.
## 지팡이는 몸통 스프라이트의 자식: 손잡이(쥔 손)를 축으로 돌고(ang), 축이 자루를 따라 미끄러지며(pivot: 휘두를 때 자루 아래쪽을 고쳐 쥠),
## 손이 앞뒤·위아래로 내밀어진다(reach). 휘두를 때 보랏빛 호 궤적(_trail)과 잔상(몸통+지팡이)을 남긴다. 등불 빛은 지팡이 고리에 매달려 흔들린다.
## 붉은 예고(_draw_marks): 가시 바닥 사각형(+가시 높이만큼 옅은 기둥)·휘두르기 부채꼴(판정 사각형 sweep_reach 를 덮음)·구슬 고리·뿌리 벽 띠·뿌리 손 타원·달빛 고리 원·내려찍기 띠.
##   가드 가능 = 주황빛(GUARD_C), 가드 불가 = 진한 붉은색 깜빡임(RED_C, 초당 RootKeeper.TELEGRAPH_BLINK_HZ 번). 세기 조절 상수는 아래 TG_* 참고.
##   예고 층은 보스 씬의 Marks 노드(보스 그림보다 먼저 = 보스 뒤, 소녀보다 먼저 = 소녀 뒤, 지형·배경보다는 위)에 그린다.
## 그림은 정면이라 뒤집기는 의미가 적다. 지팡이가 오른손이므로 기울기 부호만 바라보는 쪽으로 자연스럽게 둔다.

## 자세 묶음: (기울기, 가로 찌그러짐, 세로 찌그러짐, 세로 오프셋)
const NEUTRAL := Vector4(0.0, 1.0, 1.0, 0.0)
const STRIDE := 120.0
## 지팡이 자세 묶음: (앞으로 기운 각도 rad, 축 위치 0~1(위 끝→아래 끝), 손 앞으로 내밀기 px, 손 위로 올리기 px) — 원본 px 기준
const STAFF_NEUTRAL := Vector4(0.0, 0.344, 0.0, 0.0)
## 지팡이 조각 (tools/cut_boss_parts_root.gd 의 값)
const STAFF_TEX := preload("res://art/bosses/parts/boss_rootkeeper_staff.png")
const TEX_SIZE := Vector2(1024, 1536)
const STAFF_POS := Vector2(698, 60)
const GRIP := Vector2(828, 590)
const STAFF_TOP := Vector2(880, 100)
const STAFF_BOTTOM := Vector2(745, 1525)
const HOOK := Vector2(872, 338)
## 예고 색과 세기
const GUARD_C := Color(1.0, 0.5, 0.15)
const RED_C := Color(1.0, 0.1, 0.08)
const RED_BODY := Color(1.6, 0.45, 0.4)   # 가드 불가 예고 때 몸이 물드는 색 (너무 밝으면 글로우로 번진다)
const TRAIL_LIFE := 0.28   # 지팡이 호 궤적이 남는 시간
const TRAIL_C := Color(0.7, 0.45, 1.0)

var _boss: RootKeeper
var _t := 0.0
var _base_scale := Vector2.ONE
var _base_pos := Vector2.ZERO
var _marks: Node2D
var _staff: Sprite2D
var _trail: Node2D
var _trail_pts: Array = []   # [tip(world), mid(world), 시각]

var _pose := NEUTRAL
var _staff_pose := STAFF_NEUTRAL
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
var _staff_rise_from := STAFF_NEUTRAL
var _dust: CPUParticles2D
var _ghosts: Array = []   # [몸통 Sprite2D, 지팡이 Sprite2D]
var _ghost_timer := 0.0
# 지팡이 등불 빛: 고리에 매달려 한 박자 늦게 흔들린다
var _light: PointLight2D
var _lamp := 0.0
var _lamp_v := 0.0
var _hook_prev := Vector2.ZERO


func _ready() -> void:
	_boss = get_parent() as RootKeeper
	_base_scale = scale
	_base_pos = position
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# 예고 자국 (월드 좌표). 보스 씬의 Marks 노드: 트리 순서상 지형 뒤·보스 그림 앞·소녀 앞이라
	# 배경·지형 위, 보스와 소녀 아래에 그려진다 (몸 그림의 붉은 깜빡임 modulate 도 물려받지 않는다).
	_marks = get_parent().get_node_or_null("Marks") as Node2D if get_parent() else null
	if _marks == null:
		_marks = Node2D.new()
		_marks.top_level = true
		add_child(_marks)
	_marks.draw.connect(_draw_marks)
	# 지팡이
	_staff = Sprite2D.new()
	_staff.texture = STAFF_TEX
	_staff.centered = false
	_staff.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_staff)
	_apply_staff(STAFF_NEUTRAL, 0.0)
	# 호 궤적 (월드 좌표, 더하기 혼합)
	_trail = Node2D.new()
	_trail.top_level = true
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail.material = add
	_trail.draw.connect(_draw_trail)
	add_child(_trail)
	if _boss:
		_face = float(_boss.facing)
		_boss.state_changed.connect(_on_state_changed)
		_light = _boss.get_node_or_null("Light") as PointLight2D
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
	for i in 4:
		var g := Sprite2D.new()
		g.texture = texture
		g.top_level = true
		g.visible = false
		g.show_behind_parent = true
		g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(g)
		var gs := Sprite2D.new()
		gs.texture = STAFF_TEX
		gs.centered = false
		gs.top_level = true
		gs.visible = false
		gs.show_behind_parent = true
		gs.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(gs)
		_ghosts.append([g, gs])


func _on_state_changed(st: RootKeeper.State) -> void:
	match st:
		RootKeeper.State.RISE:
			_rise_from = _pose
			_staff_rise_from = _staff_pose
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
				RootKeeper.State.SWEEP2:
					_puff(5, f * 30.0)
				RootKeeper.State.WALL:
					_jolt(-0.6, 0.0)
				RootKeeper.State.HAND:
					_jolt(1.4, 0.8)
					_puff(10, 0.0)
				RootKeeper.State.SEEDS:
					_jolt(-0.5, -0.3)
				RootKeeper.State.STOMP:
					_jolt(2.4, 0.4)
					_puff(24, 0.0)
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

	# ---- 목표 자세 (몸통·지팡이) ----
	var target := NEUTRAL
	var staff := STAFF_NEUTRAL
	var follow := 9.0
	var sfollow := 8.0
	var ghost := false
	var trail := false
	target.z += Motion.breathe(_t, 0.2, 0.012)
	target.w += Motion.breathe(_t, 0.2, 3.0)
	staff.x += Motion.breathe(_t + 0.4, 0.2, 0.025)
	match st:
		RootKeeper.State.STANCE, RootKeeper.State.INTRO:
			# 느린 걸음: 거리 기준 들썩임, 기울기는 실제 이동 방향
			_dist += speed * delta
			var amount := clampf(speed / _boss.walk_speed, 0.0, 1.2)
			var bob := Motion.step_bob(_dist, STRIDE)
			target.w += -bob * 5.0 * amount
			target.x = 0.02 * f + 0.04 * amount * signf(_boss.velocity.x)
			staff.x += -0.06 * amount * signf(_boss.velocity.x) * f
			staff.w += bob * 10.0 * amount
			var step := int(floor(_dist / STRIDE))
			if step != _last_step:
				_last_step = step
				if amount > 0.3:
					_puff(3, 0.0)
					_imp_v += 0.25 * amount
		RootKeeper.State.SPIKES:
			# 지팡이를 높이 들어 올리고(몸이 늘어남) → 땅에 내리꽂기(눌림) → 되돌림
			target = _three_beat(Vector4(-0.1 * f, 0.96, 1.06, -28.0), Vector4(0.08 * f, 1.1, 0.93, 14.0), 0.55)
			staff = _staff_beat(Vector4(-0.4, 0.344, -40.0, 300.0), Vector4(0.14, 0.3, 80.0, -150.0), 0.55)
			if ph == "active":
				staff.x += sin(_t * 50.0) * 0.03
			follow = _beat_follow()
			sfollow = _staff_follow()
		RootKeeper.State.SWEEP:
			# 자루 아래쪽을 고쳐 쥐고(pivot 0.72) 머리 쪽을 뒤로 들어 올렸다가 앞으로 크게 쓸어 내린다
			target = _three_beat(Vector4(-0.26 * f, 0.96, 1.05, -8.0), Vector4(0.34 * f, 1.13, 0.93, 6.0), 0.75)
			staff = _staff_beat(Vector4(-0.95, 0.72, -80.0, 140.0), Vector4(2.05, 0.72, 260.0, -60.0), 0.75)
			follow = _beat_follow()
			sfollow = _staff_follow()
			ghost = ph == "active"
			trail = ph == "active" or (ph == "recovery" and _boss.phase_progress() < 0.25)
		RootKeeper.State.SWEEP2:
			# 되돌려 베기 = 앞에서 올려 베기: 쓸어 내린 지팡이 머리를 땅 가까이 더 낮췄다가(몸 숙임) 앞쪽 아래 → 앞쪽 위로 쳐올린다.
			# 지팡이 머리가 타격 내내 보스 앞에 있어 판정(앞쪽)과 그림 방향이 같다.
			target = _three_beat(Vector4(0.32 * f, 1.1, 0.94, 10.0), Vector4(-0.14 * f, 0.97, 1.06, -12.0), 0.75)
			staff = _staff_beat(Vector4(2.45, 0.72, 270.0, -40.0), Vector4(0.75, 0.72, 300.0, 200.0), 0.75)
			follow = _beat_follow()
			sfollow = _staff_follow()
			ghost = ph == "active"
			trail = ph == "active" or (ph == "recovery" and _boss.phase_progress() < 0.25)
		RootKeeper.State.ORBS:
			# 지팡이 끝을 앞으로 내밀어 구슬을 빚는다
			target = _three_beat(Vector4(-0.1 * f, 0.98, 1.03, -12.0), Vector4(-0.06 * f, 1.0, 1.02, -10.0), 0.8)
			staff = _staff_beat(Vector4(0.6, 0.5, 110.0, 210.0), Vector4(1.05, 0.5, 190.0, 240.0), 0.8)
			follow = _beat_follow()
			sfollow = _staff_follow()
		RootKeeper.State.WALL:
			# 뒤로 물러 몸을 모았다가 지팡이를 창처럼 눕히고 앞으로 쏠리며 돌진 (잔상)
			target = _three_beat(Vector4(-0.2 * f, 0.95, 1.06, -6.0), Vector4(0.38 * f, 1.2, 0.9, 8.0), 0.45)
			staff = _staff_beat(Vector4(-0.3, 0.6, -50.0, 60.0), Vector4(1.45, 0.6, 220.0, 120.0), 0.45)
			if ph == "startup":
				target.x += sin(_t * 40.0) * 0.015 * clampf((_boss.phase_progress() - 0.5) / 0.5, 0.0, 1.0)
			elif ph == "active":
				target.x += clampf(_boss.velocity.x / 4000.0, -0.2, 0.2)
			follow = _beat_follow()
			sfollow = _staff_follow()
			ghost = ph == "active" and speed > 300.0
		RootKeeper.State.HAND:
			# 지팡이를 땅에 깊이 꽂고 몸을 앞으로 숙인다 → 저 앞에서 뿌리 손이 솟는다
			target = _three_beat(Vector4(-0.14 * f, 0.97, 1.05, -20.0), Vector4(0.3 * f, 1.12, 0.9, 20.0), 0.6)
			staff = _staff_beat(Vector4(-0.45, 0.344, -30.0, 240.0), Vector4(0.3, 0.28, 60.0, -170.0), 0.6)
			if ph == "startup":
				staff.x += sin(_t * 30.0) * 0.02 * _boss.phase_progress()
			follow = _beat_follow()
			sfollow = _staff_follow()
		RootKeeper.State.SEEDS:
			# 지팡이를 머리 위로 높이 들고 흔든다 → 하늘에서 씨앗이 떨어진다
			target = _three_beat(Vector4(-0.08 * f, 0.96, 1.08, -30.0), Vector4(0.02 * f, 0.98, 1.06, -26.0), 0.8)
			staff = _staff_beat(Vector4(-0.25, 0.5, 0.0, 340.0), Vector4(0.1, 0.5, 30.0, 380.0), 0.8)
			if ph == "active":
				staff.x += sin(_t * 18.0) * 0.12
				target.x += sin(_t * 18.0) * 0.01 * f
			follow = _beat_follow()
			sfollow = _staff_follow()
		RootKeeper.State.RING:
			# 지팡이를 앞에 가로로 들고 천천히 돌리며 고리를 만든다 (몸이 살짝 떠오른다)
			target = _three_beat(Vector4(0.04 * f, 1.0, 1.02, -8.0), Vector4(0.0, 1.02, 1.0, -16.0), 0.8)
			staff = _staff_beat(Vector4(1.1, 0.5, 120.0, 220.0), Vector4(1.55, 0.5, 150.0, 250.0), 0.8)
			if ph == "active":
				staff.x += sin(_t * 2.6) * 0.18
				target.w += sin(_t * 2.6) * 6.0
			follow = _beat_follow()
			sfollow = _staff_follow()
		RootKeeper.State.STOMP:
			# 지팡이를 머리 위로 치켜들며 몸이 늘어났다가(예비) 땅에 내리찍으며 눌린다(타격)
			target = _three_beat(Vector4(-0.18 * f, 0.94, 1.12, -50.0), Vector4(0.12 * f, 1.16, 0.86, 22.0), 0.5)
			staff = _staff_beat(Vector4(-0.55, 0.55, -50.0, 420.0), Vector4(0.4, 0.3, 90.0, -180.0), 0.5)
			if ph == "startup":
				var k := clampf((_boss.phase_progress() - 0.6) / 0.4, 0.0, 1.0)
				staff.x += sin(_t * 44.0) * 0.03 * k
				target.x += sin(_t * 44.0) * 0.01 * k
			follow = _beat_follow()
			sfollow = _staff_follow()
			ghost = ph == "active"
			trail = ph == "active"
		RootKeeper.State.RISE:
			# 지금 자세에서 이어서 쓰러지고(앞 30%) → 떨며 천천히 일어선다
			var k := _boss.state_progress(_boss.rise_len)
			var collapsed := Vector4(0.6 * f, 1.02, 0.8, 120.0)
			var staff_collapsed := Vector4(1.3, 0.344, 120.0, -200.0)
			if k < 0.3:
				target = _rise_from.lerp(collapsed, Motion.ease_in(k / 0.3, 1.8))
				staff = _staff_rise_from.lerp(staff_collapsed, Motion.ease_in(k / 0.3, 1.8))
				follow = 14.0
				sfollow = 12.0
			else:
				var u := Motion.ease_in_out((k - 0.3) / 0.7)
				target = collapsed.lerp(Vector4(0.0, 1.0, 1.05, -10.0), u)
				staff = staff_collapsed.lerp(Vector4(-0.1, 0.344, 0.0, 30.0), u)
				target.x += sin(_t * 26.0) * 0.02 * (1.0 - u)
				staff.x += sin(_t * 26.0) * 0.04 * (1.0 - u)
				follow = 8.0
				sfollow = 7.0
		RootKeeper.State.BROKEN:
			target = Vector4(0.4 * f, 1.06, 0.88, 50.0)
			target.z += Motion.breathe(_t, 0.6, 0.02)
			staff = Vector4(0.7, 0.3, 80.0, -120.0)
			follow = 6.0
			sfollow = 5.0
		RootKeeper.State.FALLEN, RootKeeper.State.PURIFIED:
			target = Vector4(0.75 * f, 1.0, 1.0, 130.0)
			staff = Vector4(1.5, 0.344, 140.0, -260.0)
			follow = 5.0
			sfollow = 4.0
	# 지팡이가 튕겼다(저스트 가드): 뒤로 젖혔다가 stagger 가 1→0 으로 줄면서 서서히 돌아온다
	target.x += -0.2 * f * _boss.stagger
	staff.x += -0.6 * _boss.stagger

	# ---- 보간 ----
	_pose = Vector4(
		Motion.damp(_pose.x, target.x, follow, delta),
		Motion.damp(_pose.y, target.y, follow, delta),
		Motion.damp(_pose.z, target.z, follow, delta),
		Motion.damp(_pose.w, target.w, follow, delta))
	_staff_pose = Vector4(
		Motion.damp(_staff_pose.x, staff.x, sfollow, delta),
		Motion.damp(_staff_pose.y, staff.y, sfollow * 0.8, delta),
		Motion.damp(_staff_pose.z, staff.z, sfollow, delta),
		Motion.damp(_staff_pose.w, staff.w, sfollow, delta))
	var s := _spring_steps(_imp, _imp_v, 380.0, 13.0, delta)
	_imp = s[0]; _imp_v = s[1]
	s = _spring_steps(_kick, _kick_v, 210.0, 9.0, delta)
	_kick = s[0]; _kick_v = s[1]
	_face = Motion.damp(_face, f, 20.0, delta)
	var fx := -_face
	if absf(fx) < 0.03:
		fx = 0.03 * (1.0 if fx >= 0.0 else -1.0)

	var tilt := _pose.x + _kick
	var sq := Vector2(_pose.y + _imp * 0.7, _pose.z - _imp)
	var dy := _pose.w + _imp * 40.0
	rotation = tilt
	scale = Vector2(_base_scale.x * sq.x * fx, _base_scale.y * maxf(sq.y, 0.05))
	position = _base_pos + Vector2(0, dy)
	# 지팡이: 기울기 충격(_kick 은 바라보는 방향 부호가 곱해져 있다 → 로컬 앞 방향으로 되돌린다)
	_apply_staff(_staff_pose, _kick * f * 1.3)
	_update_trail(delta, trail)
	_update_ghosts(delta, ghost)
	_update_light(delta)

	# ---- 색 ----
	_red = Motion.damp(_red, 1.0 if _boss.is_red() else 0.0, 14.0, delta)
	var base := Color(0.9, 0.92, 1.0) if _boss.phase == 1 else Color(1.05, 0.95, 1.15)
	base = base.lerp(RED_BODY, _red * (0.45 + 0.35 * sin(_t * TAU * RootKeeper.TELEGRAPH_BLINK_HZ)))
	modulate = base.lerp(Color(2.5, 2.5, 2.5), fl * 0.8)
	if not _marks.top_level:
		_marks.global_position = Vector2.ZERO   # 보스가 움직여도 예고는 월드 좌표로 그린다
	_marks.queue_redraw()
	_trail.queue_redraw()


## 충격 스프링을 짧은 조각으로 나눠 돌린다: 한 프레임이 길어지면(스크린샷 저장·끊김) 한 번에 적분한 스프링이 터져 몸이 납작해졌다.
static func _spring_steps(value: float, vel: float, k: float, d: float, delta: float) -> Array:
	var n := maxi(1, int(ceil(delta / (1.0 / 50.0))))
	var dt := delta / n
	var v := value
	var w := vel
	for i in n:
		var r := Motion.spring(v, 0.0, w, k, d, dt)
		v = r[0]; w = r[1]
	return [v, w]


# ---------- 지팡이 ----------

## 자루 위의 점 (원본 px): t = 0 위 끝, 1 아래 끝
static func _staff_point(t: float) -> Vector2:
	return STAFF_TOP + (STAFF_BOTTOM - STAFF_TOP) * t


## 지팡이 자세를 스프라이트에 적용한다. 손(노드 자리)은 손잡이 + 내밀기, 축은 자루 위 pivot 점, 각도는 앞으로 양수.
func _apply_staff(p: Vector4, extra_ang: float) -> void:
	var pivot := _staff_point(clampf(p.y, 0.0, 1.0))
	_staff.offset = -(pivot - STAFF_POS)
	# 로컬 좌표에서 앞 = -x (그림이 왼쪽을 볼 때; 뒤집히면 자동으로 거울), 위 = -y
	_staff.position = (GRIP - TEX_SIZE / 2.0) + Vector2(-p.z, -p.w)
	_staff.rotation = -(p.x + extra_ang)


## 자루 위 점의 월드 좌표
func _staff_world(t: float) -> Vector2:
	var pivot := _staff_point(clampf(_staff_pose.y, 0.0, 1.0))
	return _staff.to_global(_staff_point(t) - pivot)


## 지팡이 머리(달 원반)의 월드 좌표 — 구슬·씨앗 예고 고리가 여기 뜬다
func head_world() -> Vector2:
	return _staff_world(0.08)


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


func _staff_beat(back: Vector4, fwd: Vector4, strike_span := 0.6) -> Vector4:
	var p := _boss.phase_progress()
	match _boss.attack_phase:
		"startup":
			return STAFF_NEUTRAL.lerp(back, Motion.anticipation(p))
		"active":
			return back.lerp(fwd, Motion.strike(clampf(p / strike_span, 0.0, 1.0)))
		"recovery":
			return fwd.lerp(STAFF_NEUTRAL, Motion.settle(p, 2.0, 3.5))
	return STAFF_NEUTRAL


func _beat_follow() -> float:
	match _boss.attack_phase:
		"startup": return 11.0
		"active": return 40.0
		"recovery": return 12.0
	return 9.0


func _staff_follow() -> float:
	match _boss.attack_phase:
		"startup": return 9.0
		"active": return 34.0
		"recovery": return 9.0
	return 8.0


func _puff(n: int, ox: float) -> void:
	_dust.amount = n
	_dust.global_position = _boss.global_position + Vector2(ox, 0)
	_dust.restart()
	_dust.emitting = true


# ---------- 호 궤적 · 잔상 · 빛 ----------

func _update_trail(delta: float, active: bool) -> void:
	if active:
		_trail_pts.append([_staff_world(0.0), _staff_world(0.2), _t])
	var keep: Array = []
	for e in _trail_pts:
		if _t - e[2] < TRAIL_LIFE:
			keep.append(e)
	_trail_pts = keep


func _draw_trail() -> void:
	if _trail_pts.size() < 2:
		return
	for i in range(1, _trail_pts.size()):
		var a: Array = _trail_pts[i - 1]
		var b: Array = _trail_pts[i]
		# 머리가 거의 안 움직인 조각(겹친 점)은 건너뛴다 — 삼각분할이 깨진다
		if (a[0] as Vector2).distance_to(b[0]) < 1.5:
			continue
		var age := clampf((_t - b[2]) / TRAIL_LIFE, 0.0, 1.0)
		var alpha := (1.0 - age) * 0.32
		var ma: Vector2 = (a[0] + a[1]) * 0.5
		var mb: Vector2 = (b[0] + b[1]) * 0.5
		# 바깥(머리 쪽)은 진하고 안쪽은 옅게: 초승달 베기 자국.
		# 삼각형 둘로 나눠 그린다: 손이 움직이며 돌면 조각이 꼬여(나비 모양) 다각형 삼각분할이 실패하던 것을 피함
		_trail_quad(a[0], b[0], mb, ma, Color(TRAIL_C, alpha))
		_trail_quad(ma, mb, b[1], a[1], Color(TRAIL_C, alpha * 0.3))
		_trail.draw_line(a[0], b[0], Color(1.0, 0.9, 1.0, alpha * 1.4), 4.0, true)


## 궤적 조각 하나 = 삼각형 둘. 감기는 방향(휘두르는 방향)과 상관없이 보이도록 삼각형마다 꼭짓점 순서를 맞추고, 넓이 없는 조각은 건너뛴다.
func _trail_quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, c: Color) -> void:
	_trail_tri(p0, p1, p2, c)
	_trail_tri(p0, p2, p3, c)


func _trail_tri(p0: Vector2, p1: Vector2, p2: Vector2, c: Color) -> void:
	var area := (p1 - p0).cross(p2 - p0)
	if absf(area) < 1.0:
		return
	if area > 0.0:   # 화면에서 보이는 감김(휘두르기 SWEEP 궤적과 같은 쪽)으로 맞춘다
		var t := p1
		p1 = p2
		p2 = t
	_trail.draw_primitive(PackedVector2Array([p0, p1, p2]), PackedColorArray([c, c, c]), PackedVector2Array())


func _update_ghosts(delta: float, active: bool) -> void:
	if active:
		_ghost_timer += delta
		if _ghost_timer >= 0.035:
			_ghost_timer = 0.0
			var pair: Array = _ghosts.pop_front()
			var g: Sprite2D = pair[0]
			var gs: Sprite2D = pair[1]
			g.visible = true
			g.global_transform = global_transform
			g.modulate = Color(0.7, 0.85, 1.0, 0.3)
			gs.visible = true
			gs.offset = _staff.offset
			gs.global_transform = _staff.global_transform
			gs.modulate = Color(0.85, 0.7, 1.0, 0.4)
			_ghosts.append(pair)
	else:
		_ghost_timer = 0.0
	for pair in _ghosts:
		for g in pair:
			if g.visible:
				g.modulate.a -= delta * 2.4
				if g.modulate.a <= 0.0:
					g.visible = false


## 지팡이 등불 빛: 고리(HOOK)에 매달려 고리의 움직임에 끌려 한 박자 늦게 진자처럼 흔들린다.
func _update_light(delta: float) -> void:
	if _light == null:
		return
	var pivot := _staff_point(clampf(_staff_pose.y, 0.0, 1.0))
	var hook := _staff.to_global(HOOK - pivot)
	var vx := (hook.x - _hook_prev.x) / maxf(delta, 0.001) if _hook_prev != Vector2.ZERO else 0.0
	_hook_prev = hook
	var drive := clampf(-vx / 2200.0, -0.7, 0.7)
	var s := Motion.spring(_lamp, drive, _lamp_v, 44.0, 3.4, delta)
	_lamp = s[0]; _lamp_v = s[1]
	_light.global_position = hook + Vector2(sin(_lamp) * 40.0, cos(_lamp) * 40.0)
	_light.energy = (1.0 if _boss.phase == 1 else 1.25) * (1.0 + Motion.breathe(_t, 0.9, 0.08))


# ---------- 붉은 예고 ----------

## 예고 색: 가드 가능 = 주황빛, 불가 = 진한 붉은색 깜빡임. a 는 기본 투명도.
func _tg(a: float, guardable: bool) -> Color:
	if guardable:
		return Color(GUARD_C, a)
	var blink := 0.7 + 0.3 * sin(_t * TAU * RootKeeper.TELEGRAPH_BLINK_HZ)   # 꺼지지 않고 맥동 (최저 0.4)
	return Color(RED_C, a * blink)


func _draw_marks() -> void:
	if _boss == null or _boss.attack_phase != "startup":
		return
	var p := clampf(_boss.windup_progress, 0.0, 1.0)
	var g := _boss.ground_y
	var f := float(_boss.facing)
	var bx := _boss.global_position.x
	var guard := _boss.is_guardable_pattern()
	var fade := clampf(p / 0.12, 0.0, 1.0)   # 처음 0.1초에 살며시 떠오른다
	match _boss.state:
		RootKeeper.State.SPIKES:
			# 바닥 사각형 + 맥동 테두리 + 금 가는 선 + 가시 높이(390)만큼 옅은 기둥 (가지 위에 서 있어도 닿는다는 것이 보이게)
			var pulse := 0.5 + 0.5 * sin(_t * (10.0 + p * 30.0))
			for x: float in _boss.spike_marks:
				RootSpike.draw_telegraph(_marks, Vector2(x, g), p, _tg(1.0, guard), fade, pulse)
		RootKeeper.State.SWEEP, RootKeeper.State.SWEEP2:
			# 휘두를 호 모양의 부채꼴. 판정 사각형(sweep_reach)을 그대로 덮도록 땅까지 내려온다 — 보스 바로 앞도 붉다.
			var pts := sweep_fan(_boss.state)
			_marks.draw_colored_polygon(pts, _tg((0.12 + 0.18 * p) * fade, guard))
			_marks.draw_polyline(pts + PackedVector2Array([pts[0]]), _tg((0.5 + 0.4 * p) * fade, guard), 3.0, true)
		RootKeeper.State.ORBS, RootKeeper.State.SEEDS:
			# 지팡이 머리에 모이는 빛의 고리
			var h := head_world()
			var r := 34.0 + 46.0 * p
			_marks.draw_circle(h, r, _tg(0.18 * fade, guard))
			_marks.draw_arc(h, r, 0.0, TAU, 32, _tg((0.5 + 0.4 * p) * fade, guard), 3.0, true)
			_marks.draw_arc(h, r * 0.55, _t * 4.0, _t * 4.0 + PI, 16, _tg(0.8 * p * fade, guard), 2.0, true)
			if _boss.state == RootKeeper.State.SEEDS and _boss.player:
				# 씨앗이 떨어질 너비를 희미하게 (가드 가능 → 주황빛)
				var px: float = _boss.player.global_position.x
				var half := 420.0 if _boss.phase == 2 else 300.0
				_marks.draw_rect(Rect2(px - half, g - 6, half * 2.0, 8), _tg(0.1 + 0.12 * p, true))
		RootKeeper.State.WALL:
			# 지나갈 띠 전체가 붉게 (가드 불가)
			var x0 := bx
			var x1 := (_boss.arena.end.x if f > 0.0 else _boss.arena.position.x) if _boss.arena.size.x > 0.0 else bx + f * 1600.0
			var lane := Rect2(minf(x0, x1), g - 330.0, absf(x1 - x0), 330.0)   # 판정 윗끝(발밑 기준 320)보다 조금 높게
			_marks.draw_rect(lane, _tg((0.1 + 0.14 * p) * fade, false))
			_marks.draw_rect(Rect2(lane.position.x, g - 8, lane.size.x, 10), _tg((0.4 + 0.4 * p) * fade, false))
			# 벽 실루엣
			var wx := bx + f * 40.0
			_marks.draw_rect(Rect2(minf(wx, wx + f * 220.0), g - 310.0, 220.0, 310.0), _tg(0.6 * p * fade, false), false, 3.0)
		RootKeeper.State.HAND:
			for x: float in _boss.hand_targets:
				# 땅의 붉은 타원 + 위로 뻗는 기둥 + 손가락 자국 (가드 불가)
				_marks.draw_colored_polygon(RootSpike._ellipse(Vector2(x, g), 125.0, 32.0, 28), _tg((0.25 + 0.25 * p) * fade, false))
				_marks.draw_polyline(RootSpike._ellipse(Vector2(x, g), 125.0, 32.0, 28) + PackedVector2Array([Vector2(x + 125.0, g)]), _tg((0.6 + 0.4 * p) * fade, false), 3.0, true)
				_marks.draw_rect(Rect2(x - 110.0, g - 240.0 * p, 220.0, 240.0 * p), _tg(0.09 * fade, false))
				for i in 5:
					var a := -1.0 + 0.5 * i
					var base := Vector2(x + sin(a) * 90.0, g - 10.0)
					_marks.draw_line(base, base + Vector2(sin(a) * 40.0, -60.0 * p), _tg(0.7 * p * fade, false), 3.0)
		RootKeeper.State.RING:
			# 보스 둘레의 고리 (가드 가능 → 주황빛), 구슬이 생길 자리의 점
			var c := _boss.global_position + Vector2(0, -200.0)
			var r := 100.0 + 90.0 * p
			var ell := RootSpike._ellipse(c, r, r * 0.5, 40)
			_marks.draw_colored_polygon(ell, _tg(0.1 * fade, true))
			_marks.draw_polyline(ell + PackedVector2Array([ell[0]]), _tg((0.5 + 0.4 * p) * fade, true), 3.0, true)
			var n := 6 if _boss.phase == 1 else 8
			for i in n:
				var a := TAU * i / n
				_marks.draw_circle(c + Vector2(cos(a) * r, sin(a) * r * 0.5), 10.0 + 8.0 * p, _tg(0.8 * p * fade, true))
		RootKeeper.State.STOMP:
			# 양쪽 바닥을 달릴 띠 2줄 + 발밑 원 (가드 불가)
			var ax := _boss.arena.position.x if _boss.arena.size.x > 0.0 else bx - 1600.0
			var ex := _boss.arena.end.x if _boss.arena.size.x > 0.0 else bx + 1600.0
			_marks.draw_rect(Rect2(ax, g - 90.0, ex - ax, 90.0), _tg((0.1 + 0.16 * p) * fade, false))
			_marks.draw_rect(Rect2(ax, g - 8, ex - ax, 10), _tg((0.4 + 0.4 * p) * fade, false))
			# 발밑 반원 (땅 위쪽만 — 원 전체를 그리면 아래 반이 바닥 위에 비쳐 보였다)
			var half := PackedVector2Array()
			for i in 25:
				var a := PI + PI * i / 24.0
				half.append(Vector2(bx + cos(a) * 150.0, g + sin(a) * 150.0))
			_marks.draw_colored_polygon(half, _tg((0.12 + 0.2 * p) * fade, false))
			_marks.draw_arc(Vector2(bx, g), 150.0, PI, TAU, 24, _tg((0.5 + 0.4 * p) * fade, false), 3.0, true)
			# 내려찍기 판정 기둥 (발밑 기준 좌우 130, 높이 190 — 반원만으로는 판정 위쪽 모서리가 예고 밖이었다)
			var col := Rect2(bx - 150.0, g - 205.0, 300.0, 205.0)
			_marks.draw_rect(col, _tg((0.08 + 0.12 * p) * fade, false))
			_marks.draw_rect(col, _tg((0.45 + 0.4 * p) * fade, false), false, 2.5)
			# 충격파가 달릴 방향 화살
			for d: float in [-1.0, 1.0]:
				var x: float = bx + d * (200.0 + 300.0 * p)
				_marks.draw_line(Vector2(x, g - 45), Vector2(x + d * 40.0, g - 45), _tg(0.8 * p * fade, false), 3.0)
				_marks.draw_line(Vector2(x + d * 40.0, g - 45), Vector2(x + d * 20.0, g - 65), _tg(0.8 * p * fade, false), 3.0)
				_marks.draw_line(Vector2(x + d * 40.0, g - 45), Vector2(x + d * 20.0, g - 25), _tg(0.8 * p * fade, false), 3.0)


## 휘두르기 부채꼴 (월드 좌표 다각형): 손잡이 높이쯤(땅 위 FAN_CENTER_H)을 중심으로 뒤-위(지팡이를 치켜든 자리)에서
## 앞으로 돌아 땅에 닿는 호 + 땅을 따라 판정 뒤끝까지 + 판정 위끝까지. 판정 사각형(보스 sweep_reach)을 반드시 덮는다.
## 되돌려 베기(SWEEP2)는 앞에서 올려 베므로 호가 앞-위에서 시작한다.
const FAN_CENTER_H := 150.0
func sweep_fan(st: int) -> PackedVector2Array:
	var reach: Rect2 = _boss.sweep_reach(st)
	var g := _boss.ground_y
	var f := float(_boss.facing)
	var bx := _boss.global_position.x
	var front := reach.end.x               # 판정 앞끝 (+미끄러짐)
	var back := reach.position.x            # 판정 뒤끝 (음수 = 뒤)
	var top := reach.position.y - 20.0      # 판정 위끝 (발밑 기준, 음수)
	var cx := 20.0
	var r := Vector2(front - cx, FAN_CENTER_H).length()
	var th_ground := atan2(front - cx, -FAN_CENTER_H)   # 호가 땅(앞끝)에 닿는 각도
	var th0 := -0.55 if st == RootKeeper.State.SWEEP else 0.15
	var pts := PackedVector2Array()
	var n := 24
	for i in n + 1:
		var th := lerpf(th0, th_ground, float(i) / n)
		var lp := Vector2(cx + sin(th) * r, -FAN_CENTER_H - cos(th) * r)
		pts.append(Vector2(bx + f * lp.x, g + lp.y))
	pts.append(Vector2(bx + f * back, g))
	var start_fwd := cx + sin(th0) * r
	if start_fwd > back:
		pts.append(Vector2(bx + f * back, g + top))
	return pts

extends Sprite2D
## 등불 기사의 그림을 상태에 맞춰 움직인다. 세 겹:
##  - 몸통(이 Sprite2D, art/bosses/parts/boss_knight_body.png — 창 자리를 지우고 메운 원본)
##  - 창·등불(boss_knight_spear.png): 손아귀(grip)를 축으로 돈다. 모든 공격에서 크게 휘둘러지고 궤적(빛의 띠)을 남긴다.
##  - 손(boss_knight_hands.png): 맨 위에 고정 — 창이 돌아도 두 주먹은 자루를 쥔 자리에 남는다.
## 원칙: 자세 값(기울기·찌그러짐·세로 오프셋·창 각도·밀기·색)은 절대 '툭' 바뀌지 않는다.
## 매 프레임 '목표 자세'를 정하고, 실제 값은 Motion.damp(프레임 독립)로 그 목표를 쫓는다.
## 그 위에 '충격 스프링'(내려찍기·디딤·휘청·피격·창 튕김)이 한 겹 더 얹힌다.
## 휘두르기는 세 박자: 예비(뒤로 당기며 멈칫) → 타격(아주 빠르게, 살짝 지나침) → 되돌림(출렁이며 제자리).
## 진행도는 보스가 공개한 단계 길이(startup_len/active_len/recovery_len)로 계산해 2페이즈 배속에도 모양이 같다.
## 그림 원본은 **오른쪽**을 본다(발끝·창끝이 오른쪽, 망토가 왼쪽으로 흘러감) → 왼쪽을 볼 때 뒤집는다(scale.x 음수).
## (2026-10-19 수정: 전엔 왼쪽을 본다고 잘못 알아 소녀에게 등을 보였다.) 방향 전환은 몸을 틀며 1→0→−1 을 지난다.
## 창 각도: 0 = 그림 그대로(창끝이 앞 위 39°). 양수 = 창끝이 앞으로 내려옴(+0.68 ≈ 앞으로 수평), 음수 = 머리 위를 지나 등 뒤로.
## 밀기: 그림 픽셀 단위, 앞 = +x.

## 자세 묶음: (기울기, 가로 찌그러짐, 세로 찌그러짐, 세로 오프셋)
const NEUTRAL := Vector4(0.0, 1.0, 1.0, 0.0)
const STRIDE := 150.0    # 한 걸음 거리(px). 들썩임과 디딤 먼지의 기준
## 창 자세 묶음: (각도 rad, 밀기 x, 밀기 y) — 밀기는 그림 픽셀(원본 px) 단위, 앞 = +x
const W_REST := Vector3.ZERO
const A_UP := -0.89          # 창끝이 똑바로 위
const A_BACK_HIGH := -1.67   # 등 뒤 위 45° (큰 휘두르기 예비: 머리 위로 넘겨 뒤로)
const A_BACK := -2.46        # 등 뒤 수평
const A_LEVEL := 0.68        # 앞으로 수평 (찌르기)
const A_FRONT_DOWN := 1.47   # 앞 아래 45° (등불이 땅을 친다)
const A_DOWN := 2.26         # 똑바로 아래
## 궤적: 이 속도(px/s)보다 빨리 움직일 때만 띠가 보이고, 이만큼 넘으면 가장 진하다
const TRAIL_MIN_SPEED := 900.0
const TRAIL_FULL_SPEED := 3200.0
const TRAIL_LIFE := 0.16

@export var spear_texture: Texture2D
@export var hands_texture: Texture2D
## 손아귀 축·조각 위치·창끝·등불 자리 (원본 px; tools/cut_boss_parts.gd 가 적은 parts.json 값)
@export var grip := Vector2(1000, 467)
@export var spear_origin := Vector2(246, 0)
@export var hands_origin := Vector2(887, 358)
@export var spear_tip := Vector2(1526, 8)
@export var spear_lantern := Vector2(1378, 370)
@export var spear_butt := Vector2(250, 1022)

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
# 창: 현재 자세, 충격 스프링(각도), 등불 회전 누적
var _wpose := W_REST
var _wkick := 0.0
var _wkick_v := 0.0
var _spin := 0.0
var _combo_from := W_REST          # 3연격: 앞 타가 끝난 창 자세 (거기서 이어서 다음 타로)
var _combo_body_from := NEUTRAL
var _prev_combo_step := -1
# 바라보는 방향 (−1 왼쪽 … +1 오른쪽; 사이 값은 몸 틀기)
var _face := -1.0
var _red := 0.0
var _dist := 0.0         # 걸은 거리 누적 (걸음 들썩임 기준)
var _last_step := 0
var _prev_phase := ""
var _prev_hint := ""
var _prev_flash := 0.0
var _prev_state := -1
var _dust: CPUParticles2D
var _embers: CPUParticles2D
var _weapon_bone: Node2D
var _weapon: Sprite2D
var _hands: Sprite2D
var _ghosts: Array[Node2D] = []
var _ghost_timer := 0.0
# 궤적: [창끝, 창날 뒤, 등불, 등불 뒤, 시각]
var _trail: Node2D
var _trail_pts: Array = []
var _prev_tip := Vector2.ZERO
var _prev_lantern := Vector2.ZERO
var _tip_speed := 0.0
var _lantern_speed := 0.0
var _trail_dirty := false
# 창 수평 맞춤 (0~1): 찌르기·돌진·박힘처럼 창을 앞으로 겨누는 자세에서 몸이 앞으로 기운 만큼 창 각도를 되돌려
# 창끝이 땅에 파묻히거나 판정보다 훨씬 아래·멀리 그려지지 않게 한다.
var _level := 0.0
# 등불 빛: 등불 자리를 한 박자 늦게 따라간다
var _light: PointLight2D
var _light_pos := Vector2.ZERO


func _ready() -> void:
	_boss = get_parent() as LanternKnight
	_base_scale = scale
	_base_pos = position
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _boss:
		_face = float(_boss.facing)
		_boss.state_changed.connect(_on_state_changed)
		_light = _boss.get_node_or_null("Light") as PointLight2D
	# 창(손아귀 축) 과 손
	var half := Vector2(texture.get_width(), texture.get_height()) / 2.0 if texture else Vector2(768, 512)
	_weapon_bone = Node2D.new()
	_weapon_bone.position = grip - half
	add_child(_weapon_bone)
	_weapon = Sprite2D.new()
	_weapon.texture = spear_texture
	_weapon.centered = false
	_weapon.position = spear_origin - grip
	_weapon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_weapon_bone.add_child(_weapon)
	_hands = Sprite2D.new()
	_hands.texture = hands_texture
	_hands.centered = false
	_hands.position = hands_origin - half
	_hands.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_hands)
	# 궤적 (몸의 배율·회전을 따르지 않게 top_level, 몸 위에 그린다)
	_trail = Node2D.new()
	_trail.top_level = true
	_trail.z_index = 2
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail.material = add
	_trail.draw.connect(_draw_trail)
	add_child(_trail)
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
	# 내려찍기·등불 불씨
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
	var add2 := CanvasItemMaterial.new()
	add2.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_embers.material = add2
	add_child(_embers)
	# 빠른 동작 잔상 (몸통 + 창 + 손 한 묶음)
	for i in 4:
		var g := Node2D.new()
		g.top_level = true
		g.visible = false
		g.z_index = -1
		var gb := Sprite2D.new()
		gb.texture = texture
		gb.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		g.add_child(gb)
		var gw := Sprite2D.new()
		gw.texture = spear_texture
		gw.centered = false
		gw.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		g.add_child(gw)
		var gh := Sprite2D.new()
		gh.texture = hands_texture
		gh.centered = false
		gh.position = _hands.position
		gh.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		g.add_child(gh)
		add_child(g)
		_ghosts.append(g)


func _on_state_changed(st: LanternKnight.State) -> void:
	match st:
		LanternKnight.State.STAGGER:
			_jolt(-1.0, -4.0)
			_wkick_v += 7.0
		LanternKnight.State.BROKEN:
			_jolt(1.4, 3.0)
			_puff(10, 0.0)
		LanternKnight.State.FALLEN:
			_jolt(2.2, 2.0)
			_puff(16, 0.0)
		LanternKnight.State.STUCK:
			# 창이 벽에 박혀 몸이 앞으로 쏠리며 튕긴다
			_jolt(1.4, 3.2)
			_puff(14, (float(_boss.facing) if _boss else 1.0) * 70.0)
			_spark_at(_tip_global())
	# 등불 회전이 끝나면 누적 각도를 접는다 (2π 의 배수라 그림은 그대로)
	if _prev_state == LanternKnight.State.SPIN and st != LanternKnight.State.SPIN:
		_wpose.x = wrapf(_wpose.x, -PI, PI)
		_spin = 0.0
	_prev_state = st


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
					_spark_at(_boss.global_position + Vector2(0, -20))
					_wkick_v += 3.0
				LanternKnight.State.THRUST:
					_puff(6, -f * 40.0)
				LanternKnight.State.FLAME:
					_jolt(0.6, 0.0)
					_spark_at(_lantern_global())
				LanternKnight.State.WAVE:
					_jolt(0.8, 0.0)
					_puff(10, -f * 30.0)
				LanternKnight.State.CHARGE:
					_jolt(0.5, 0.0)
					_puff(12, f * 50.0)
				LanternKnight.State.SPIN:
					_spark_at(_lantern_global())
				LanternKnight.State.COMBO3:
					if _boss.combo_step == 2:
						_jolt(-0.8, 0.0)   # 올려치기: 몸이 위로 늘어난다
						_puff(10, 0.0)
					else:
						_puff(5, -f * 30.0)
		_prev_phase = ph
	if st == LanternKnight.State.COMBO3 and _boss.combo_step != _prev_combo_step:
		# 다음 타의 시작 자세 = 지금 자세 (끊기지 않고 이어진다)
		_combo_from = _wpose
		_combo_body_from = _pose
		_prev_combo_step = _boss.combo_step
	elif st != LanternKnight.State.COMBO3:
		_prev_combo_step = -1
	if _boss.anim_hint == "stagger" and _prev_hint != "stagger" and st in [LanternKnight.State.THRUST, LanternKnight.State.COMBO3, LanternKnight.State.CHARGE]:
		_jolt(-1.0, -4.5)   # 창이 튕김 (STAGGER 상태 진입은 위 state_changed 에서 한 번만)
		_wkick_v += 9.0
	_prev_hint = _boss.anim_hint
	var fl := _boss.flash_amount()
	if fl > _prev_flash + 0.4 and st not in [LanternKnight.State.BROKEN, LanternKnight.State.FALLEN, LanternKnight.State.STAGGER]:
		_jolt(0.35, -1.2)
		_wkick_v += 1.0
	_prev_flash = fl

	# ---- 목표 자세 (몸 + 창) ----
	var target := NEUTRAL
	var wtarget := W_REST
	var follow := 9.0        # 목표를 쫓는 빠르기 (단계마다 다름)
	var wfollow := 9.0
	var ghost := false
	# 숨쉬기 (서 있을 때 더 크게)
	target.z += Motion.breathe(_t, 0.22, 0.012)
	wtarget.y += Motion.breathe(_t, 0.22, 4.0)
	match st:
		LanternKnight.State.MARCH, LanternKnight.State.INTRO:
			# 걸음은 시간이 아니라 이동 거리 기준: 속도가 0이면 멈춘다
			_dist += speed * delta
			var amount := clampf(speed / _boss.march_speed, 0.0, 1.3)
			var bob := Motion.step_bob(_dist, STRIDE)
			var sway := sin(_dist / STRIDE * PI)
			target.w = -bob * 9.0 * amount
			target.x = (0.05 * amount) * signf(_boss.velocity.x) + sway * 0.03 * amount
			target.y = 1.0 - bob * 0.02 * amount
			target.z += bob * 0.03 * amount
			# 창은 걸음에 맞춰 흔들리고 등불이 출렁인다
			wtarget.x += sway * 0.07 * amount - 0.04 * amount
			wtarget.y += -bob * 10.0 * amount
			wtarget.z += -bob * 14.0 * amount
			var step := int(floor(_dist / STRIDE))
			if step != _last_step:
				_last_step = step
				if amount > 0.25:
					_puff(4, -signf(_boss.velocity.x) * 30.0)
					_imp_v += 0.45 * amount
					_wkick_v += 0.6 * amount
		LanternKnight.State.THRUST:
			# 예비: 몸과 창을 뒤로, 창끝이 머리 위를 넘어 앞을 겨눈다 → 찌르기: 몸을 앞으로 던지며 창을 내지른다 → 되돌림
			target = _three_beat(Vector4(-0.2 * f, 0.95, 1.05, -6.0), Vector4(0.28 * f, 1.1, 0.93, 6.0), 0.6)
			wtarget = _wbeat(W_REST, Vector3(-0.45, -110.0, -20.0), Vector3(A_LEVEL, 170.0, 15.0), W_REST, 0.6)
			follow = _beat_follow()
			wfollow = _wbeat_follow()
			ghost = ph == "active"
		LanternKnight.State.FLAME:
			# 등불을 등 뒤 아래로 크게 당겼다가 머리 위로 넘겨 앞 땅에 내리친다 (불꽃 파도)
			target = _three_beat(Vector4(-0.32 * f, 0.96, 1.06, -16.0), Vector4(0.36 * f, 1.12, 0.93, 6.0), 0.65)
			wtarget = _wbeat(W_REST, Vector3(A_BACK_HIGH + 0.25, -40.0, -10.0), Vector3(A_FRONT_DOWN + 0.15, 110.0, 30.0), W_REST, 0.9)
			follow = _beat_follow()
			wfollow = _wbeat_follow()
			ghost = ph == "active"
		LanternKnight.State.SLAM:
			# 웅크림(앞 30%: 내려앉음) → 도약(몸이 진짜 뛴다; 창을 머리 위로 세움) → 창 밑동을 땅에 꽝 → 되돌림
			var up := Vector4(0.0, 0.93, 1.1, -22.0)
			target = _three_beat(up, Vector4(0.0, 1.22, 0.8, 24.0), 0.5)
			wtarget = _wbeat(W_REST, Vector3(A_UP - 0.25, 0.0, -70.0), Vector3(A_UP, 0.0, 70.0), W_REST, 0.5)
			if ph == "startup":
				var p := _boss.phase_progress()
				var crouch := Vector4(0.0, 1.06, 0.94, 14.0)
				if p < 0.3:
					target = NEUTRAL.lerp(crouch, Motion.ease_out(p / 0.3))
					wtarget = W_REST.lerp(Vector3(-0.35, 0.0, 20.0), Motion.ease_out(p / 0.3))
				else:
					# 웅크린 자세에서 도약 (끝값 up 이 타격 시작 자세와 같아 이어진다)
					target = crouch.lerp(up, Motion.anticipation((p - 0.3) / 0.7))
					wtarget = Vector3(-0.35, 0.0, 20.0).lerp(Vector3(A_UP - 0.25, 0.0, -70.0), Motion.anticipation((p - 0.3) / 0.7))
				target.x += sin(_t * 40.0) * 0.02 * clampf((p - 0.6) / 0.4, 0.0, 1.0)
			follow = _beat_follow()
			wfollow = _wbeat_follow()
			ghost = ph == "active" or (ph == "startup" and not _boss.is_on_floor())
		LanternKnight.State.THROW:
			target = _three_beat(Vector4(-0.26 * f, 0.96, 1.04, -10.0), Vector4(0.22 * f, 1.08, 0.96, 2.0), 0.7)
			wtarget = _wbeat(W_REST, Vector3(A_BACK_HIGH + 0.3, -50.0, -30.0), Vector3(A_LEVEL - 0.5, 120.0, -40.0), W_REST, 0.7)
			follow = _beat_follow()
			wfollow = _wbeat_follow()
		LanternKnight.State.WAVE:
			# 검기: 창을 등 뒤 아래로 깊이 당겼다가 머리 위를 지나 앞으로 크게 벤다
			target = _three_beat(Vector4(-0.3 * f, 0.95, 1.06, -10.0), Vector4(0.32 * f, 1.15, 0.92, 8.0), 0.72)
			wtarget = _wbeat(W_REST, Vector3(A_BACK + 0.55, -70.0, 30.0), Vector3(A_LEVEL + 0.3, 170.0, 0.0), W_REST, 0.92)
			if ph == "startup":
				target.x += sin(_t * 36.0) * 0.015 * clampf((_boss.phase_progress() - 0.6) / 0.4, 0.0, 1.0)
			follow = _beat_follow()
			wfollow = _wbeat_follow()
			ghost = ph == "active"
		LanternKnight.State.COMBO3:
			# 찌르기 → 휘두르기(머리 위에서 앞 땅으로) → 올려치기(앞 아래에서 앞 위로, 붉은 예고). 타 사이에 자세가 이어진다.
			var s := _boss.combo_step
			var wb: Vector3
			var wf: Vector3
			var bb: Vector4
			var bf: Vector4
			match s:
				0:
					wb = Vector3(A_LEVEL - 0.3, -90.0, 0.0); wf = Vector3(A_LEVEL, 170.0, 10.0)
					bb = Vector4(-0.18 * f, 0.96, 1.04, -4.0); bf = Vector4(0.26 * f, 1.1, 0.94, 6.0)
				1:
					# 머리 위에서 앞 아래로 내려벤다 (창끝은 땅에 닿을 듯 말 듯 — 파묻히지 않게)
					wb = Vector3(A_UP + 0.35, 40.0, -70.0); wf = Vector3(A_LEVEL + 0.3, 60.0, 0.0)
					bb = Vector4(-0.25 * f, 0.96, 1.05, -12.0); bf = Vector4(0.2 * f, 1.1, 0.95, 4.0)
				_:
					# 올려치기 예비: 창을 앞 아래로 낮게 겨눴다가(창끝은 땅 위) 앞 위로 크게 올려친다
					wb = Vector3(A_LEVEL + 0.45, 30.0, 0.0); wf = Vector3(A_UP + 0.1, 140.0, -230.0)
					bb = Vector4(0.08 * f, 1.05, 0.93, 10.0); bf = Vector4(-0.2 * f, 0.94, 1.14, -30.0)
			var last := s == 2
			wtarget = _wbeat(_combo_from, wb, wf, W_REST if last else wf, 0.85)
			target = _beat4(_combo_body_from, bb, bf, NEUTRAL if last else bf, 0.7)
			if last and ph == "startup":
				target.x += sin(_t * 40.0) * 0.02 * clampf((_boss.phase_progress() - 0.5) / 0.5, 0.0, 1.0)
			follow = _beat_follow()
			wfollow = _wbeat_follow()
			ghost = ph == "active"
		LanternKnight.State.CHARGE:
			# 뒤로 물러나며 창을 수평으로 겨눈다(떨림) → 몸을 앞으로 던지며 돌진 → 되돌림
			target = _three_beat(Vector4(-0.28 * f, 0.95, 1.06, 2.0), Vector4(0.42 * f, 1.22, 0.9, 10.0), 0.4)
			wtarget = _wbeat(W_REST, Vector3(A_LEVEL, -100.0, 0.0), Vector3(A_LEVEL, 220.0, 0.0), W_REST, 0.4)
			if ph == "startup":
				var k := clampf((_boss.phase_progress() - 0.5) / 0.5, 0.0, 1.0)
				target.x += sin(_t * 44.0) * 0.02 * k
				wtarget.y += sin(_t * 44.0) * 6.0 * k
			elif ph == "active":
				target.x += clampf(_boss.velocity.x / 4000.0, -0.2, 0.2) * f * f
			follow = _beat_follow()
			wfollow = _wbeat_follow()
			ghost = ph == "active" and speed > 300.0
		LanternKnight.State.STUCK:
			# 창이 벽에 박혔다: 앞으로 쏠린 채 창을 뽑으려 당긴다 (들썩임)
			var k := _boss.state_progress(_boss.stuck_len)
			var tug := absf(sin(_t * 9.0))
			target = Vector4(0.34 * f - tug * 0.08 * f, 1.1 - tug * 0.05, 0.95 + tug * 0.04, 8.0)
			wtarget = Vector3(A_LEVEL, 270.0 - tug * 18.0, 0.0)
			if k > 0.85:
				# 마지막엔 뽑히며 뒤로 휘청
				target = target.lerp(Vector4(-0.2 * f, 0.96, 1.05, 0.0), (k - 0.85) / 0.15)
				wtarget = wtarget.lerp(Vector3(A_LEVEL - 0.4, -60.0, -20.0), (k - 0.85) / 0.15)
			follow = 12.0
			wfollow = 14.0
		LanternKnight.State.SPIN:
			# 제자리에서 창을 빙글 돌린다 (등불이 불꽃 고리를 그린다): 예비 1바퀴 → 타격 2바퀴 → 멈춤
			var p := _boss.phase_progress()
			match ph:
				"startup":
					_spin = TAU * Motion.ease_in(p, 2.0)
					target = Vector4(0.0, 0.98, 1.03, -6.0)
				"active":
					_spin = TAU + 2.0 * TAU * p
					target = Vector4(sin(_t * 30.0) * 0.03, 1.04, 0.98, 2.0)
				_:
					_spin = 3.0 * TAU
					target = Vector4(0.0, 1.0, 1.0, 0.0).lerp(NEUTRAL, Motion.settle(p))
			wtarget = Vector3(_spin, 0.0, -40.0 * (1.0 if ph != "recovery" else 1.0 - p))
			follow = 12.0
			wfollow = 40.0
			ghost = ph == "active"
		LanternKnight.State.STAGGER:
			# 뒤로 젖혀 휘청이다가 되돌아온다
			var k := _boss.state_progress(_boss.stagger_len)
			var back := Vector4(-0.3 * f, 0.94, 1.05, 4.0)
			target = back.lerp(NEUTRAL, Motion.settle(k, 1.5, 3.0))
			wtarget = Vector3(-0.5, -30.0, -20.0).lerp(W_REST, Motion.settle(k, 1.5, 3.0))
			follow = 12.0
			wfollow = 12.0
		LanternKnight.State.BROKEN:
			target = Vector4(0.4 * f, 1.06, 0.9, 40.0)
			target.z += Motion.breathe(_t, 0.6, 0.02)   # 거친 숨
			wtarget = Vector3(0.9, -20.0, 60.0)
			follow = 6.0
			wfollow = 6.0
		LanternKnight.State.FALLEN, LanternKnight.State.PURIFIED:
			target = Vector4(0.85 * f, 1.0, 1.0, 110.0)
			wtarget = Vector3(1.35, 0.0, 100.0)
			follow = 5.0
			wfollow = 5.0
	# 창 수평 맞춤: 앞으로 겨누는 자세(찌르기·3연격 첫 타·돌진·박힘)에서만
	# (찌르기·3연격 첫 타는 내지르는 순간부터 — 예비에선 창끝을 머리 위로 치켜든 큰 호가 그대로 보이게. 돌진은 예비부터 수평으로 겨눈다)
	var level_want := 0.0
	if st == LanternKnight.State.CHARGE or st == LanternKnight.State.STUCK:
		level_want = 1.0
	elif (st == LanternKnight.State.THRUST or (st == LanternKnight.State.COMBO3 and _boss.combo_step == 0)) and ph != "startup":
		level_want = 1.0
	if _boss.anim_hint == "stagger":
		level_want = 0.0
	_level = Motion.damp(_level, level_want, 10.0, delta)
	if _boss.anim_hint == "stagger" and st in [LanternKnight.State.THRUST, LanternKnight.State.COMBO3, LanternKnight.State.CHARGE]:
		# 창이 튕겼다: 되돌림 동안 뒤로 젖힌 자세에서 출렁이며 돌아온다
		var k := _boss.phase_progress()
		target = Vector4(-0.34 * f, 0.93, 1.06, 6.0).lerp(NEUTRAL, Motion.settle(k, 2.0, 3.5))
		wtarget = Vector3(A_LEVEL - 0.9, -60.0, -60.0).lerp(W_REST, Motion.settle(k, 2.0, 3.5))
		follow = 10.0
		wfollow = 10.0

	# ---- 보간 (프레임 독립) ----
	_pose = Vector4(
		Motion.damp(_pose.x, target.x, follow, delta),
		Motion.damp(_pose.y, target.y, follow, delta),
		Motion.damp(_pose.z, target.z, follow, delta),
		Motion.damp(_pose.w, target.w, follow, delta))
	_wpose = Vector3(
		Motion.damp(_wpose.x, wtarget.x, wfollow, delta),
		Motion.damp(_wpose.y, wtarget.y, wfollow, delta),
		Motion.damp(_wpose.z, wtarget.z, wfollow, delta))
	var s := Motion.spring(_imp, 0.0, _imp_v, 380.0, 13.0, delta)
	_imp = s[0]; _imp_v = s[1]
	s = Motion.spring(_kick, 0.0, _kick_v, 210.0, 9.0, delta)
	_kick = s[0]; _kick_v = s[1]
	s = Motion.spring(_wkick, 0.0, _wkick_v, 160.0, 7.0, delta)
	_wkick = s[0]; _wkick_v = s[1]
	# 방향 전환: 몸 틀기 (scale.x 가 0 을 지나며 뒤집힌다)
	_face = Motion.damp(_face, f, 11.0, delta)
	var fx := _face   # 그림이 오른쪽을 보므로 왼쪽을 볼 때 음수
	if absf(fx) < 0.03:
		fx = 0.03 * (1.0 if fx >= 0.0 else -1.0)

	var tilt := _pose.x + _kick
	var sq := Vector2(_pose.y + _imp * 0.7, _pose.z - _imp)
	var dy := _pose.w + _imp * 40.0
	rotation = tilt
	scale = Vector2(_base_scale.x * sq.x * fx, _base_scale.y * maxf(sq.y, 0.05))
	position = _base_pos + Vector2(0, dy)
	# 창: 손아귀 축 회전 + 밀기 (창을 쥔 방향으로 미끄러진다)
	# (수평 맞춤: 몸이 앞으로 기운 만큼(기울기 × 바라보는 쪽) 창을 되돌린다 — 그림 좌표에서 양수 각도 = 창끝이 앞으로 내려옴)
	# 밀기도 같은 만큼 되돌려 화면에서 수평으로 민다 (몸이 크게 앞으로 기운 돌진에서 창이 아래로 밀려 땅에 박히지 않게)
	var lean := tilt * (1.0 if fx >= 0.0 else -1.0)
	_weapon_bone.rotation = _wpose.x + _wkick * 0.12 - lean * _level
	_weapon_bone.position = (grip - _half()) + Vector2(_wpose.y, _wpose.z).rotated(-lean * _level)
	_update_trail(delta)
	_update_ghosts(delta, ghost)
	_update_light(delta)

	# ---- 색: 붉은 예고는 서서히 켜지고 꺼진다, 피격 번쩍임 ----
	_red = Motion.damp(_red, 1.0 if _boss.is_red() else 0.0, 14.0, delta)
	var base := Color(0.95, 0.9, 0.9) if _boss.phase == 1 else Color(1.1, 0.85, 0.75)
	base = base.lerp(Color(2.4, 0.5, 0.4), _red * (0.5 + 0.5 * sin(_t * 32.0)))
	modulate = base.lerp(Color(2.5, 2.5, 2.5), fl * 0.8)


func _half() -> Vector2:
	return Vector2(texture.get_width(), texture.get_height()) / 2.0 if texture else Vector2(768, 512)


## 세 박자 자세. back = 예비 끝 자세, fwd = 타격 자세. strike_span = 타격 구간 중 곡선이 끝나는 비율(정점이 그 안에 온다).
## 경계에서 곡선 값이 이어지므로(예비 끝 = back, 타격 시작 = back, 되돌림 시작 = fwd) 목표가 점프하지 않는다.
func _three_beat(back: Vector4, fwd: Vector4, strike_span := 0.6) -> Vector4:
	return _beat4(NEUTRAL, back, fwd, NEUTRAL, strike_span)


## 세 박자 (몸): from 에서 예비로, 타격 뒤 to 로 되돌아온다 (3연격처럼 앞 타에서 이어질 때 from/to 가 NEUTRAL 이 아니다).
func _beat4(from: Vector4, back: Vector4, fwd: Vector4, to: Vector4, strike_span := 0.6) -> Vector4:
	var p := _boss.phase_progress()
	match _boss.attack_phase:
		"startup":
			return from.lerp(back, Motion.anticipation(p))
		"active":
			return back.lerp(fwd, Motion.strike(clampf(p / strike_span, 0.0, 1.0)))
		"recovery":
			return fwd.lerp(to, Motion.settle(p))
	return to


## 세 박자 (창: 각도·밀기).
func _wbeat(from: Vector3, back: Vector3, fwd: Vector3, to: Vector3, strike_span := 0.6) -> Vector3:
	var p := _boss.phase_progress()
	match _boss.attack_phase:
		"startup":
			return from.lerp(back, Motion.anticipation(p))
		"active":
			return back.lerp(fwd, Motion.strike(clampf(p / strike_span, 0.0, 1.0)))
		"recovery":
			return fwd.lerp(to, Motion.settle(p))
	return to


## 단계별 따라가는 빠르기: 예비는 천천히, 타격은 아주 빠르게, 되돌림은 보통.
func _beat_follow() -> float:
	match _boss.attack_phase:
		"startup": return 11.0
		"active": return 40.0
		"recovery": return 12.0
	return 9.0


## 창은 몸보다 조금 더 빠르게 따라간다 (무거운 창이 휙 지나가는 느낌).
func _wbeat_follow() -> float:
	match _boss.attack_phase:
		"startup": return 13.0
		"active": return 38.0
		"recovery": return 11.0
	return 9.0


func _puff(n: int, ox: float) -> void:
	_dust.amount = n
	_dust.global_position = _boss.global_position + Vector2(ox, 0)
	_dust.restart()
	_dust.emitting = true


func _spark_at(pos: Vector2) -> void:
	_embers.global_position = pos
	_embers.restart()
	_embers.emitting = true


func _tip_global() -> Vector2:
	return _weapon_bone.to_global(spear_tip - grip)


func _lantern_global() -> Vector2:
	return _weapon_bone.to_global(spear_lantern - grip)


## 궤적: 창끝과 등불이 빠르게 지나간 자리를 빛의 띠로 남긴다 (느릴 땐 보이지 않는다).
func _update_trail(delta: float) -> void:
	var tip := _tip_global()
	var lantern := _lantern_global()
	var blade_back := _weapon_bone.to_global((spear_tip - grip) * 0.82)
	var lantern_back := _weapon_bone.to_global((spear_lantern - grip) * 0.86)
	if delta > 0.0 and _prev_tip != Vector2.ZERO:
		_tip_speed = (tip - _prev_tip).length() / delta
		_lantern_speed = (lantern - _prev_lantern).length() / delta
	_prev_tip = tip
	_prev_lantern = lantern
	# 공격 중에만 점을 남긴다 — 몸 틀기(scale.x 가 1→0→−1)만으로도 창끝이 5000px/s 넘게 넘어가 빛줄기가 생겼다.
	# 공격 직전에 몸을 튼 경우도 있어 몸이 다 돌았을 때(|_face| > 0.9)만.
	if _boss.attack_phase != "" and absf(_face) > 0.9:
		_trail_pts.append([tip, blade_back, lantern, lantern_back, _t, _tip_speed, _lantern_speed])
	while _trail_pts.size() > 0 and _t - _trail_pts[0][4] > TRAIL_LIFE:
		_trail_pts.pop_front()
	while _trail_pts.size() > 24:
		_trail_pts.pop_front()
	# 그릴 게 있을 때만 (마지막 한 번은 지우려고 다시 그린다)
	if _trail_pts.size() > 0 or _trail_dirty:
		_trail.queue_redraw()
	_trail_dirty = _trail_pts.size() > 0


func _draw_trail() -> void:
	if _trail_pts.size() < 2:
		return
	for i in range(_trail_pts.size() - 1):
		var a: Array = _trail_pts[i]
		var b: Array = _trail_pts[i + 1]
		var age := clampf((_t - b[4]) / TRAIL_LIFE, 0.0, 1.0)
		var fade := 1.0 - age
		# 창날: 흰 금빛 얇은 띠
		var k := clampf((maxf(a[5], b[5]) - TRAIL_MIN_SPEED) / (TRAIL_FULL_SPEED - TRAIL_MIN_SPEED), 0.0, 1.0)
		if k > 0.0:
			var al := k * fade * 0.1
			_ribbon(a[0], b[0], b[1], a[1], Color(1.0, 0.95, 0.75, al))
			_trail.draw_line(a[0], b[0], Color(1.4, 1.3, 1.0, al * 5.0), 4.0, true)
		# 등불: 불꽃빛 두꺼운 띠
		var kl := clampf((maxf(a[6], b[6]) - TRAIL_MIN_SPEED) / (TRAIL_FULL_SPEED - TRAIL_MIN_SPEED), 0.0, 1.0)
		if kl > 0.0:
			var al := kl * fade * 0.16
			_ribbon(a[2], b[2], b[3], a[3], Color(1.0, 0.55, 0.2, al))
			_trail.draw_line(a[2], b[2], Color(1.5, 1.0, 0.5, al * 3.4), 9.0, true)


## 띠 한 조각: 네 점이 겹치거나 꼬여도(삼각 분할 실패) 그려지게 다각형 대신 기본 도형(두 삼각형)으로 그린다.
func _ribbon(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, c: Color) -> void:
	var cols := PackedColorArray([c, c, c, c])
	var uvs := PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	_trail.draw_primitive(PackedVector2Array([p0, p1, p2, p3]), cols, uvs)


## 잔상: 빠르게 움직일 때 뒤에 희미한 그림(몸통+창+손)을 남긴다.
func _update_ghosts(delta: float, active: bool) -> void:
	if active:
		_ghost_timer += delta
		if _ghost_timer >= 0.035:
			_ghost_timer = 0.0
			var g: Node2D = _ghosts.pop_front()
			g.visible = true
			g.global_transform = global_transform
			(g.get_child(1) as Sprite2D).transform = _weapon_bone.transform * _weapon.transform
			g.modulate = Color(1.0, 0.85, 0.6, 0.32)
			_ghosts.append(g)
	else:
		_ghost_timer = 0.0
	for g in _ghosts:
		if g.visible:
			g.modulate.a -= delta * 2.4
			if g.modulate.a <= 0.0:
				g.visible = false


## 등불 빛: 창에 매달린 등불 자리를 한 박자 늦게 따라가고, 빠르게 휘둘릴수록 밝아진다.
func _update_light(delta: float) -> void:
	if _light == null:
		return
	var want := _lantern_global()
	if _light_pos == Vector2.ZERO:
		_light_pos = want
	_light_pos = Motion.damp_vec(_light_pos, want, 26.0, delta)
	_light.global_position = _light_pos
	var flicker := 1.0 + Motion.breathe(_t, 3.1, 0.06) + Motion.breathe(_t, 7.3, 0.03)
	var swing := clampf(_lantern_speed / 3000.0, 0.0, 0.7)
	_light.energy = (1.2 if _boss.phase == 1 else 1.5) * flicker * (1.0 + swing)

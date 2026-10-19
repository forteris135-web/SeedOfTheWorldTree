extends Node2D
## 일반 적의 그림(art/enemies/*.png)을 상태에 맞춰 움직인다: 걸음 들썩임, 예고 젖힘, 휘두름, 피격 번쩍임, 무너짐, 쓰러짐.
## 그림은 한 장(또는 몸통+무기 팔 두 겹)이라 기울기·찌그러짐·위치·팔 각도·색으로 표현한다.
##
## 움직임 원칙 (기획자: "휘두르기가 저렴하고 단절돼 보인다 → 자연스럽게"):
## - 자세 값은 절대 '툭' 바뀌지 않는다. 모든 값은 '목표값 + 속도를 이어 가는 보간(스프링/감쇠)'으로만 움직인다.
##   상태가 바뀌어도 지금 값과 속도에서 이어진다. 프레임당 고정 비율 lerp 는 쓰지 않는다 (FPS 에 따라 달라지므로).
## - 휘두르기는 세 박자: 예비동작(뒤로 당기며 무게가 뒷발로, 끝에서 멈칫) → 타격(아주 빠르게, 살짝 지나침, 몸통이 같이 비틀림)
##   → 되돌림(출렁이며 제자리). 진행도는 EnemyBase 의 windup_progress / phase_progress (남은 시간 기준) 로 읽는다.
## - 몸 전체가 따라간다: 걷기는 이동 거리 기준, 기울기는 실제 이동 방향, 공중이면 점프 자세.
## - 피격·충돌은 '충격 스프링': 맞은 프레임에 속도를 주고 되돌아온다. 방향 전환은 몸을 틀며 지나간다.

@export var texture: Texture2D
## 그림 속 인물이 오른쪽을 보고 있는가 (왼쪽을 보면 false)
@export var art_faces_right := true
## 그림 크기 배율 (원본 1536×1024 기준, 키 약 150이 되게)
@export var art_scale := 0.17
## 그림의 발 위치 (그림 아래쪽 투명 여백만큼 보정, 원본 px)
@export var foot_offset := 20.0
## 구원 가능한 자: 눈빛의 따뜻한 빛
@export var warm_eye := false
## 머리 위 작은 체력·흐트러짐 막대를 그리는가 (중간 보스는 화면 아래 보스 막대가 있어 끈다)
@export var show_overhead_bar := true
## 걸음 보폭 배율 (큰 몸은 보폭도 크다: 중간 보스 1.8)
@export var stride_scale := 1.0

@export_group("무기 팔 (따로 움직이는 겹)")
## 팔 조각 그림 (없으면 한 장짜리로 그린다)
@export var arm_texture: Texture2D
## 그림이 원본의 몇 배로 줄여진 것인가 (parts 폴더는 0.5)
@export var art_pixel_scale := 1.0
## 어깨 축 (원본 px)
@export var arm_pivot := Vector2.ZERO
## 팔 조각의 왼쪽 위가 원본에서 있던 자리 (원본 px)
@export var arm_origin := Vector2.ZERO
## 원본 그림 크기 (원본 px)
@export var art_size := Vector2(1536, 1024)
## 팔의 종류: 검(들었다 내려침) / 대롱(겨눔·반동)
@export_enum("sword", "gun") var arm_kind := "sword"

## 잔상 장 수 (몸통+팔 한 쌍이 한 장). 미리 만들어 돌려 쓴다 (모바일: 매 프레임 노드를 만들지 않는다).
const GHOST_COUNT := 8
## 타격·돌진 중 잔상 간격(초)
const GHOST_INTERVAL := 0.02
## 걸음 보폭(px). 이 거리마다 한 번 디딘다.
const STRIDE := 95.0

## 예비동작 끝 팔 각도(그림 기준, 뒤로 당김)와 타격 끝 각도(앞으로). 예고의 끝 = 타격의 시작이라 이음새가 없다.
const ARM_BACK := -1.5
const ARM_FRONT := 1.1
## 예비동작 끝 몸 기울기(뒤) / 타격 끝 기울기(앞)
const ROT_BACK := -0.3
const ROT_FRONT := 0.42


## 보간 채널: 값 + 속도. 스프링(출렁임)과 감쇠(따라가기) 둘 다 속도를 이어 가므로 어떤 전환에서도 끊기지 않는다.
class Chan:
	var v := 0.0
	var vel := 0.0

	func _init(start := 0.0) -> void:
		v = start

	## 스프링. stiffness 가 클수록 빠르고 damping 이 작을수록 더 출렁인다. 큰 delta(끊김)에서도 터지지 않게 잘게 나눈다.
	func spring(target: float, stiffness: float, damping: float, delta: float) -> void:
		var steps := maxi(1, ceili(delta * sqrt(stiffness) / 0.7))
		var h := delta / steps
		for i in steps:
			vel += ((target - v) * stiffness - vel * damping) * h
			v += vel * h

	## 지수 감쇠 따라가기 (속도도 기록해 둔다 → 다음에 스프링으로 넘어가도 이어진다)
	func damp(target: float, speed: float, delta: float) -> void:
		var nv := lerpf(v, target, 1.0 - exp(-speed * delta))
		vel = (nv - v) / maxf(delta, 0.0001)
		v = nv

	func kick(impulse: float) -> void:
		vel += impulse


## 보간 방식: 상태마다 고른다
enum Drive { SOFT, FAST, SETTLE, NORMAL, HEAVY, QUICK }

var _enemy: EnemyBase
var _sprite: Sprite2D
var _glow: Sprite2D
var _label: Label
var _t := 0.0
# 자세 채널 (값+속도)
var _rot := Chan.new(0.0)
var _sx := Chan.new(1.0)
var _sy := Chan.new(1.0)
var _dy := Chan.new(0.0)
var _arm := Chan.new(0.0)
var _mir := Chan.new(1.0)        # 보이는 좌우 방향 (+1/-1 사이를 지나며 몸을 튼다)
var _pivot := Chan.new(0.0)      # 회전축 섞임: 0 = 그림 가운데, 1 = 발끝 (무너짐·쓰러짐은 발을 땅에 두고 넘어진다)
var _col := Color(1, 1, 1, 1)
var _tint_strength := 0.0        # 예고 빛 세기 (감쇠 보간)
var _tremor := 0.0               # 떨림 세기 (감쇠 보간)
var _strike_flash := 0.0         # 타격 첫 순간의 번쩍임
var _block_flash := 0.0          # 방패로 막은 번쩍임
var _recoil := 0.0               # 쏘기 반동
var _travel := 0.0               # 걸은 거리 (걸음 들썩임 기준)
var _last_bob := 0.0
var _face_target := 0            # 받아들인 바라보는 방향
var _face_hold := 0.0            # 방향 전환 뒤 지난 시간 (너무 잦은 뒤집힘 방지)
var _ghosts: Array[Sprite2D] = []
var _arm_ghosts: Array[Sprite2D] = []
var _ghost_timer := 0.0
var _dust: CPUParticles2D        # 타격·착지·도약 먼지 (한 번에 피어오름)
var _step_dust: CPUParticles2D   # 디딤 먼지 (작고 잦아서 따로 둔다: 큰 먼지를 끊지 않게)
var _drag: CPUParticles2D
var _was_airborne := false
var _alert_t := -1.0
var _arm_bone: Node2D
var _arm_sprite: Sprite2D
var _hit_dir := 1
var _fall_dir := 1
var _fall_gentle := false
var _scatter_popped := false
var _entered := -1               # 이번 프레임에 새로 들어선 상태 (없으면 -1)
var _last_rising := false        # 걸음 들썩임이 올라가는 중이었나 (디딤 순간 감지)


func _ready() -> void:
	_enemy = get_parent() as EnemyBase
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.scale = Vector2(art_scale, art_scale) / art_pixel_scale
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)
	if arm_texture:
		# 어깨 축은 몸통 그림 좌표(그림 픽셀 단위, 가운데가 원점)에 둔다
		_arm_bone = Node2D.new()
		_arm_bone.position = (arm_pivot - art_size / 2.0) * art_pixel_scale
		_sprite.add_child(_arm_bone)
		_arm_sprite = Sprite2D.new()
		_arm_sprite.texture = arm_texture
		_arm_sprite.centered = false
		_arm_sprite.position = (arm_origin - arm_pivot) * art_pixel_scale
		_arm_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_arm_bone.add_child(_arm_sprite)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color("ffd46a"))
	_label.position = Vector2(-80, -230)
	_label.visible = false
	add_child(_label)
	# 잔상: 몸통과 팔을 한 쌍으로 미리 만들어 둔다
	for i in GHOST_COUNT:
		var g := Sprite2D.new()
		g.texture = texture
		g.scale = Vector2(art_scale, art_scale) / art_pixel_scale
		g.visible = false
		g.show_behind_parent = true
		g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(g)
		_ghosts.append(g)
		if arm_texture:
			var ga := Sprite2D.new()
			ga.texture = arm_texture
			ga.centered = false
			ga.visible = false
			ga.show_behind_parent = true
			ga.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			add_child(ga)
			_arm_ghosts.append(ga)
	# 입자 개수(amount)는 바꾸면 배열을 다시 잡으므로 고정해 두고, 세기는 속도·크기로만 바꾼다
	_dust = _make_dust(12)
	_step_dust = _make_dust(3)
	_step_dust.lifetime = 0.35
	_step_dust.initial_velocity_min = 30.0
	_step_dust.initial_velocity_max = 70.0
	_step_dust.scale_amount_min = 2.0
	_step_dust.scale_amount_max = 3.5
	# 발 끌림 먼지: 돌진하는 동안 계속 뒤로 흩날린다
	_drag = CPUParticles2D.new()
	_drag.emitting = false
	_drag.local_coords = false
	_drag.amount = 14
	_drag.lifetime = 0.45
	_drag.direction = Vector2(0, -1)
	_drag.spread = 40.0
	_drag.gravity = Vector2(0, 120)
	_drag.initial_velocity_min = 40.0
	_drag.initial_velocity_max = 120.0
	_drag.scale_amount_min = 2.5
	_drag.scale_amount_max = 5.0
	_drag.color = Color(0.75, 0.72, 0.6, 0.45)
	add_child(_drag)
	if warm_eye:
		_glow = Sprite2D.new()
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		grad.colors = PackedColorArray([Color(1, 0.85, 0.5, 0.8), Color(1, 0.8, 0.45, 0.25), Color(1, 0.8, 0.45, 0.0)])
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 64
		gt.height = 64
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1, 0.5)
		_glow.texture = gt
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow.material = add
		add_child(_glow)
	if _enemy:
		_face_target = _enemy.facing
		_mir.v = -1.0 if ((_enemy.facing > 0) != art_faces_right) else 1.0
		if _enemy.has_signal("state_changed"):
			_enemy.state_changed.connect(_on_state_changed)


## 상태가 바뀌었다고 표시만 해 둔다. 진입 연출은 다음 _process 에서 한다 (하위 스크립트가 anim_hint 를 그 뒤에 세우므로).
func _on_state_changed(_old: int, new_state: int) -> void:
	_entered = new_state


## 지금 그림이 실제로 보고 있는 방향(±1). 뒤집는 도중이면 아직 지나온 쪽이다.
func visible_facing() -> int:
	var right := (_mir.v >= 0.0) == art_faces_right
	return 1 if right else -1


## 보이는 방향이 논리 방향(facing)에 자리 잡았는가. 아직 돌아서는 중(0.1초 유지 대기, 또는 뒤집는 보간이 60% 미만)이면 false.
## 경비병의 방패 판정이 이것을 본다: 그림이 저쪽을 보고 있는데 공격이 튕기는 일을 막는다.
func is_facing_settled() -> bool:
	if _enemy == null:
		return true
	if _face_target != _enemy.facing:
		return false
	var want := -1.0 if ((_enemy.facing > 0) != art_faces_right) else 1.0
	return signf(_mir.v) == signf(want) and absf(_mir.v) >= 0.6


## 상태 진입 1회 연출 (먼지·번쩍임). 자세는 여기서 바꾸지 않는다 — 자세는 늘 보간으로만 움직인다.
func _on_entered(st: int, hint: String) -> void:
	match st:
		EnemyBase.State.STRIKE:
			if hint in ["", "charge"]:
				_strike_flash = 1.0
				_puff(6)
			elif hint == "leap":
				_puff(10)   # 뛰어오르며 발밑 먼지
			_scatter_popped = false
		EnemyBase.State.LUNGE:
			_puff(4)


## 소녀의 공격이 닿았다: 밀린 방향(dir, ±1)으로 튕기고 스프링으로 되돌아온다. strength 는 공격의 무게(0.5~1.6).
func kick(dir: int, strength := 1.0) -> void:
	_hit_dir = dir
	_rot.kick(4.5 * dir * strength)
	_sx.kick(1.6 * strength)
	_sy.kick(-1.6 * strength)
	_dy.kick(40.0 * strength)


## 꽝 하고 부딛힘(방패 박힘·들이받기 끝·착지): 눌렸다 튕긴다. dir 은 나아가던 방향(0이면 수직 착지).
func impact(dir: int, strength := 1.0) -> void:
	_sx.kick(2.2 * strength)
	_sy.kick(-2.4 * strength)
	_dy.kick(90.0 * strength)
	_rot.kick(2.0 * dir * strength)
	_arm.kick(5.0 * strength)
	_puff(int(6 + 6 * strength))


## 소녀가 저스트 가드로 받아쳤다: 휘두르던 칼은 작게 되튕겨 올라오고(지나가던 속도를 뒤집음) 몸은 kick 처럼 뒤로 밀린다.
## (그냥 kick 만 주면 타격 곡선이 팔에 남긴 속도가 그대로 이어져 '막혔는데 칼이 더 깊이 들어가는' 모양이 된다.)
func parried(dir: int, strength := 1.0) -> void:
	_arm.vel = -_arm.vel * 0.35
	_rot.vel *= 0.3
	kick(dir, strength)


## 방패로 막았다: 몸(윗몸)이 뒤로 살짝 밀리며 번쩍. dir 은 밀리는 방향 (kick 과 같은 부호: 윗몸이 dir 쪽으로 기운다).
func block(dir: int, strength := 1.0) -> void:
	_block_flash = 1.0
	_rot.kick(1.6 * dir * strength)
	_dy.kick(14.0 * strength)
	_sx.kick(0.5 * strength)


## 쏘았다: 대롱이 뒤로 튀고 몸이 살짝 밀린다.
func recoil(strength := 1.0) -> void:
	_recoil = maxf(_recoil, strength)
	_rot.kick(-1.2 * float(_enemy.facing if _enemy else 1) * strength)


## 쓰러진다 (EnemyBase._begin_fall 이 부른다). dir 은 기울어질 방향, gentle 이면 빛으로 흩어지고 아니면 어두워진다.
func fall(dir: int, gentle: bool) -> void:
	_fall_dir = dir if dir != 0 else 1
	_fall_gentle = gentle
	_rot.kick(1.5 * _fall_dir)
	_dy.kick(20.0)


func _process(delta: float) -> void:
	_t += delta
	if _enemy == null or texture == null:
		return
	var st := _enemy.state
	var f := float(_enemy.facing)
	var forward := 1.0 if art_faces_right else -1.0   # 그림에서 "앞"이 +x 인가
	var hint: String = _enemy.anim_hint
	var h := art_size.y * art_scale
	var base_y := -h / 2.0 + foot_offset * art_scale + _enemy.hurt_height * 0.5
	var vx := _enemy.velocity.x
	var speed := absf(vx)
	var move_dir := signf(vx) if speed > 25.0 else 0.0
	var on_floor := _enemy.is_on_floor()
	# 공중: 바닥에서 떨어져 떨어지거나 솟는 중 (서 있을 때 한 틱 삐끗한 것은 공중으로 치지 않는다)
	var airborne := not on_floor and absf(_enemy.velocity.y) > 60.0

	# 방향 전환: 너무 잦은 뒤집힘은 0.1초에 한 번만 받아들이고, 보이는 방향은 +1→0→-1 을 지나며 몸을 튼다
	_face_hold += delta
	if _enemy.facing != _face_target and _face_hold >= 0.1:
		_face_target = _enemy.facing
		_face_hold = 0.0
	var mirror := -1.0 if ((_face_target > 0) != art_faces_right) else 1.0
	_mir.damp(mirror, 22.0, delta)

	# 착지: 먼지 + 짧은 눌림 (경사에서 바닥 판정이 깜빡이는 것은 착지로 치지 않는다)
	if not airborne and _was_airborne and on_floor:
		_puff(8)
		_sy.kick(-1.2)
		_sx.kick(1.0)
	_was_airborne = airborne
	if st == EnemyBase.State.ALERT and _alert_t < 0.0:
		_alert_t = 0.0
	elif st != EnemyBase.State.ALERT:
		_alert_t = -1.0
	if _alert_t >= 0.0:
		_alert_t += delta
	if _entered >= 0:
		_on_entered(_entered, hint)
		_entered = -1

	# 걸은 거리 (바닥에서만 쌓인다) → 걸음 들썩임의 기준
	if on_floor:
		_travel += speed * delta

	# ---- 목표 자세 ----
	var rot := 0.0
	var sx := 1.0
	var sy := 1.0 + sin(_t * 2.2) * 0.015   # 숨쉬기
	var dy := 0.0
	var arm := 0.0            # 팔 목표 (그림 기준 각도, forward 를 곱한 뒤)
	var arm_set := false
	var ghost := false
	var drive := Drive.NORMAL
	var tremor := 0.0
	var tint := Color(1, 1, 1)
	var tint_strength := 0.0
	var drag := false
	var pivot := 0.0          # 1이면 발끝을 축으로 돈다 (무너짐·쓰러짐)

	if airborne and st in [EnemyBase.State.IDLE, EnemyBase.State.PATROL, EnemyBase.State.CHASE, EnemyBase.State.BACKSTEP, EnemyBase.State.ALERT, EnemyBase.State.LUNGE, EnemyBase.State.HIT]:
		# 점프·폴짝: 몸을 늘리고 가는 방향으로 살짝 기울인다 (정원사가 물러나며 뛸 때도)
		rot = move_dir * 0.1 + clampf(_enemy.velocity.y / 4000.0, -0.08, 0.08) * -move_dir
		sx = 0.92
		sy = 1.1
		arm = -0.25 * forward
		arm_set = true
	else:
		match st:
			EnemyBase.State.IDLE:
				rot = 0.0
			EnemyBase.State.PATROL, EnemyBase.State.CHASE, EnemyBase.State.BACKSTEP:
				# 걷기: 이동 거리 기준 들썩임. 속도가 0이면 멈춘다. 기울기는 실제 이동 방향.
				var amp := clampf(speed / 140.0, 0.0, 1.0)
				var bob := Motion.step_bob(_travel, STRIDE * stride_scale)
				dy = -bob * amp * (4.0 + speed / 60.0)
				rot = move_dir * (0.04 + speed / 4000.0) + (bob - 0.5) * 0.05 * amp
				sx = 1.0 - bob * 0.03 * amp
				sy = 1.0 + bob * 0.04 * amp
				arm = sin(_travel / (STRIDE * stride_scale) * PI) * 0.08 * amp
				arm_set = true
				# 디딤 순간(들썩임이 바닥을 치고 다시 오르기 시작하는 순간) 작은 먼지
				var rising := bob > _last_bob
				if rising and not _last_rising and speed > 80.0 and on_floor:
					_step_puff()
				_last_rising = rising
				_last_bob = bob
			EnemyBase.State.ALERT:
				rot = -0.1 * f
				sx = 0.9
				sy = 1.12
			EnemyBase.State.LUNGE:
				rot = 0.28 * f
				sx = 1.12
				sy = 0.92
				arm = -0.6 * forward
				arm_set = true
				ghost = true
				drive = Drive.QUICK
			EnemyBase.State.WINDUP:
				# 예비동작: 뒤로 당기며 무게가 뒷발로, 끝에서 멈칫. 묵직하게.
				var p := Motion.anticipation(_enemy.windup_progress)
				rot = ROT_BACK * f * p
				dy = -10.0 * p
				sx = 0.95
				sy = 1.04 + p * 0.04
				arm = ARM_BACK * forward * p
				arm_set = true
				drive = Drive.SOFT
				tremor = clampf((_enemy.windup_progress - 0.6) / 0.4, 0.0, 1.0)
				tint = Color(1.6, 1.3, 0.9)
				tint_strength = 0.3 + 0.5 * _enemy.windup_progress
				if hint == "red":
					tint = Color(2.4, 0.5, 0.4)
					tint_strength = 0.75
			EnemyBase.State.STRIKE:
				match hint:
					"shoot":
						# 쏘는 자세: 살짝 앞으로 몸을 기울여 겨눈다 (반동은 recoil() 이 준다)
						rot = 0.12 * f
						sx = 1.04
						sy = 0.98
					"scatter":
						# 뿌리는 자세: 숙였다가 펴며 포자를 흩뿌린다
						var q := _enemy.phase_progress
						if q < 0.35:
							rot = 0.06 * f
							sx = 1.08
							sy = 0.9
							dy = 10.0
						else:
							rot = -0.1 * f
							sx = 0.96
							sy = 1.08
							dy = -6.0
							if not _scatter_popped:
								_scatter_popped = true
								_puff(8)
								_sy.kick(2.0)
						drive = Drive.SETTLE
					"leap":
						rot = -0.1 * f
						sx = 0.9
						sy = 1.14
						arm = -1.4 * forward
						arm_set = true
					"fall":
						rot = 0.05 * f
						sx = 0.95
						sy = 1.08
						arm = -1.6 * forward
						arm_set = true
					"charge":
						rot = 0.42 * f
						sx = 1.18
						sy = 0.88
						ghost = true
						drag = on_floor
						drive = Drive.QUICK
					_:
						# 타격: 예비동작 끝 자세에서 아주 빠르게 앞으로, 끝에서 살짝 지나친다. 몸통·허리가 같이 비틀리고 무게가 앞발로.
						var s := _strike_curve(_enemy.phase_progress)
						rot = lerpf(ROT_BACK, ROT_FRONT, s) * f
						sx = lerpf(0.95, 1.14, s)
						sy = lerpf(1.08, 0.92, s)
						dy = lerpf(-10.0, 5.0, s)
						arm = lerpf(ARM_BACK, ARM_FRONT, s) * forward
						arm_set = true
						ghost = true
						drive = Drive.FAST
			EnemyBase.State.RECOVER:
				match hint:
					"stuck":
						rot = 0.5 * f
						dy = 10.0
						sx = 1.05
						sy = 0.95
						arm = 0.8 * forward
						arm_set = true
						tremor = 0.8
					"land":
						rot = 0.15 * f
						sx = 1.2
						sy = 0.82
						dy = 12.0
						arm = 1.0 * forward
						arm_set = true
					_:
						rot = 0.1 * f
						sx = 1.03
						sy = 0.98
						arm = 0.55 * forward
						arm_set = true
				drive = Drive.SETTLE
			EnemyBase.State.HIT:
				rot = 0.15 * _hit_dir
				sx = 1.08
				sy = 0.92
				arm = 0.4 * forward
				arm_set = true
			EnemyBase.State.BROKEN:
				# 무너짐(무릎): 발을 땅에 둔 채 앞으로 숙인다 (발끝 축이라 발이 미끄러지지 않는다)
				rot = 0.45 * f
				dy = 4.0 + sin(_t * 1.5) * 2.0
				sx = 1.05
				sy = 0.85
				arm = 0.7 * forward
				arm_set = true
				drive = Drive.SOFT
				pivot = 1.0
			EnemyBase.State.DEAD:
				# 쓰러짐: 발끝을 축으로 맞은 쪽으로 넘어가 머리가 땅 가까이 닿고, 살짝 가라앉는다.
				# 빛으로 흩어지거나(정화·구원) 어두워진다.
				rot = 1.4 * _fall_dir
				dy = 5.0
				sx = 1.1
				sy = 0.8
				arm = 0.9 * forward
				arm_set = true
				drive = Drive.HEAVY
				pivot = 1.0
				if _fall_gentle:
					tint = Color(1.9, 1.75, 1.35)
					tint_strength = 1.0
				else:
					tint = Color(0.35, 0.33, 0.36)
					tint_strength = 1.0

	# 대롱(gun): 소녀를 겨눈다. 검이 아닌 팔은 상태 자세 대신 겨눔이 우선.
	if _arm_bone and arm_kind == "gun" and st in [EnemyBase.State.CHASE, EnemyBase.State.WINDUP, EnemyBase.State.STRIKE, EnemyBase.State.RECOVER, EnemyBase.State.BACKSTEP]:
		var aim := 0.0
		if _enemy.player:
			var to := _enemy.player.global_position + Vector2(0, -40) - global_position - Vector2(0, -_enemy.hurt_height * 0.55)
			var ang := atan2(to.y, absf(to.x))    # 앞쪽 기준 위아래 각
			aim = clampf(ang, -0.7, 0.6) * forward
		arm = aim
		if st == EnemyBase.State.WINDUP:
			arm = aim - 0.25 * forward
		arm_set = true

	# ---- 보간: 상태별 방식으로 목표를 쫓는다 (값과 속도가 이어진다) ----
	_drive(_rot, rot, drive, delta)
	_drive(_sx, sx, drive, delta)
	_drive(_sy, sy, drive, delta)
	_drive(_dy, dy, drive, delta)
	if _arm_bone:
		if not arm_set:
			arm = sin(_t * 1.8) * 0.05
		_drive(_arm, arm, drive, delta)
	# 떨림·반동·번쩍임은 보간 위에 얹는 덧(overlay)이고, 세기는 감쇠로 이어진다
	_tremor = Motion.damp(_tremor, tremor, 30.0, delta)
	_recoil = maxf(_recoil - delta * 6.0, 0.0)
	_strike_flash = maxf(_strike_flash - delta * 12.0, 0.0)
	_block_flash = maxf(_block_flash - delta * 9.0, 0.0)
	var rot_show := _rot.v + sin(_t * 45.0) * 0.02 * _tremor - 0.05 * f * _recoil
	var sx_show := _sx.v + sin(_t * 45.0) * 0.012 * _tremor
	var arm_show := _arm.v + sin(_t * 40.0) * 0.03 * _tremor - 0.35 * forward * _recoil

	# 회전축: 보통은 그림 가운데, 무너짐·쓰러짐은 발끝. 섞임(_pivot)도 보간이라 전환에서 발이 '툭' 옮겨 가지 않는다.
	# 그림은 가운데를 축으로 도니까, 발끝(가운데에서 foot_d 아래)이 제자리에 남도록 그만큼 위치를 되돌린다.
	# 세로 찌그러짐(sy)도 발을 기준으로: 가운데 기준이면 눌릴 때 발이 땅에서 떠오르므로 그만큼 내려 둔다 (늘 적용, 연속).
	_pivot.damp(pivot, 30.0 if pivot > _pivot.v else 12.0, delta)   # 넘어질 땐 바로 발이 축, 일어날 땐 천천히 발을 고쳐 디딘다
	var foot_d0 := (art_size.y * 0.5 - foot_offset) * art_scale
	var foot_d := foot_d0 * _sy.v
	var pivot_fix := Vector2(foot_d * sin(rot_show), foot_d * (1.0 - cos(rot_show))) * _pivot.v + Vector2(0, foot_d0 * (1.0 - _sy.v))
	_sprite.rotation = rot_show
	_sprite.scale = Vector2(art_scale * sx_show * _mir.v, art_scale * _sy.v) / art_pixel_scale
	_sprite.position = Vector2(0, base_y + _dy.v + 2.0 * _recoil) + pivot_fix
	if _arm_bone:
		_arm_bone.rotation = arm_show
	_update_ghosts(delta, ghost)
	if _drag.emitting != drag:
		_drag.emitting = drag
	if drag:
		_drag.global_position = _enemy.global_position + Vector2(-f * 20.0, _enemy.hurt_height * 0.5)

	# ---- 색: 예고 빛(맥동)·붉은 예고·타격 번쩍·피격 번쩍·쓰러짐 — 모두 감쇠로 이어진다 ----
	var tint_speed := 6.0 if st == EnemyBase.State.DEAD else 18.0
	_tint_strength = Motion.damp(_tint_strength, tint_strength, tint_speed, delta)
	var pulse := 1.0
	if st == EnemyBase.State.WINDUP:
		pulse = 0.5 + 0.5 * sin(_t * (32.0 if hint == "red" else 30.0))
	var target_col := Color(1, 1, 1).lerp(tint, _tint_strength * pulse)
	_col = _col.lerp(target_col, 1.0 - exp(-24.0 * delta))
	var fl := _enemy.flash_amount()
	var shown := _col.lerp(Color(2.5, 2.5, 2.5), fl * 0.8)
	shown = shown.lerp(Color(2.6, 2.4, 2.0), _strike_flash * 0.7)
	shown = shown.lerp(Color(1.8, 2.2, 2.6), _block_flash * 0.8)
	var alpha := 1.0
	if st == EnemyBase.State.DEAD:
		# 뒤 60% 동안 서서히 사라진다
		alpha = 1.0 - Motion.ease_in(clampf((_enemy.phase_progress - 0.4) / 0.6, 0.0, 1.0), 1.6)
	shown.a = alpha
	_sprite.modulate = shown
	_label.visible = st == EnemyBase.State.BROKEN
	if _label.visible:
		_label.text = "%s  %s" % [InputDevice.prompt("interact"), "구원의 손길" if _enemy.savable else "정화의 손길"]
	if _glow:
		var gp := 0.7 + 0.3 * sin(_t * 2.5)
		# 눈빛은 그림과 함께 돈다 (쓰러져 누워도 얼굴 자리에 남게): 그림 가운데에서의 머리 오프셋을 회전시켜 더한다
		var head_off := Vector2(14 * f, -h * 0.72 - base_y)
		_glow.position = _sprite.position + head_off.rotated(rot_show)
		_glow.modulate = Color(1.6, 1.4, 1.0, alpha) * gp
		_glow.scale = Vector2(1.2, 1.2) * gp
	queue_redraw()


## 타격 곡선 0→1: 가속해서 중간보다 조금 앞(약 38%)에서 가장 빠르고, 끝에서 살짝 지나쳤다 돌아온다.
## 보간(damp)의 지연을 감안해 조금 앞당겨 두어, 보이는 정점이 판정 구간의 가운데쯤(50% 안팎)에 온다.
static func _strike_curve(q: float) -> float:
	var c := clampf(q, 0.0, 1.0)
	var w := pow(c, 0.7)
	var base := w * w * (3.0 - 2.0 * w)
	var over := 0.14 * sin(PI * clampf((c - 0.45) / 0.55, 0.0, 1.0))
	return base + over


## 채널 하나를 상태별 방식으로 목표에 보낸다.
func _drive(ch: Chan, target: float, drive: Drive, delta: float) -> void:
	match drive:
		Drive.SOFT:      # 예비동작·무너짐: 느리고 묵직하게
			ch.spring(target, 90.0, 17.0, delta)
		Drive.FAST:      # 타격: 곡선이 시간 기반이므로 아주 바짝 따라간다
			ch.damp(target, 90.0, delta)
		Drive.SETTLE:    # 되돌림: 출렁이며 제자리
			ch.spring(target, 150.0, 12.0, delta)
		Drive.HEAVY:     # 쓰러짐: 무겁게 가라앉는다
			ch.spring(target, 60.0, 9.0, delta)
		Drive.QUICK:     # 달려듦·돌진: 빠르게 자세를 잡는다
			ch.spring(target, 320.0, 30.0, delta)
		_:               # 보통
			ch.spring(target, 220.0, 24.0, delta)


## 먼지 방출기 하나를 만든다 (개수는 만들 때 정하고 바꾸지 않는다).
func _make_dust(n: int) -> CPUParticles2D:
	var d := CPUParticles2D.new()
	d.emitting = false
	d.one_shot = true
	d.explosiveness = 1.0
	d.amount = n
	d.lifetime = 0.5
	d.direction = Vector2(0, -1)
	d.spread = 70.0
	d.gravity = Vector2(0, 200)
	d.initial_velocity_min = 60.0
	d.initial_velocity_max = 160.0
	d.scale_amount_min = 3.0
	d.scale_amount_max = 6.0
	d.color = Color(0.75, 0.72, 0.6, 0.5)
	add_child(d)
	return d


## 발밑 먼지가 한 번 피어오른다. n 은 세기(4~16): 개수는 고정이고 퍼지는 속도·크기만 커진다.
func _puff(n: int) -> void:
	var k := clampf(float(n) / 12.0, 0.4, 1.4)
	_dust.initial_velocity_min = 50.0 * k
	_dust.initial_velocity_max = 150.0 * k
	_dust.scale_amount_min = 2.5 * k
	_dust.scale_amount_max = 5.5 * k
	_dust.position = Vector2(0, _enemy.hurt_height * 0.5)
	_dust.restart()
	_dust.emitting = true


## 디딤 먼지 (작은 방출기 따로: 큰 먼지가 피어오르는 중이어도 끊지 않는다)
func _step_puff() -> void:
	_step_dust.position = Vector2(0, _enemy.hurt_height * 0.5)
	_step_dust.restart()
	_step_dust.emitting = true


## 잔상: 타격·돌진 중 뒤에 희미한 그림(몸통+팔)을 촘촘히 남긴다. 미리 만든 장을 돌려 쓴다.
func _update_ghosts(delta: float, active: bool) -> void:
	if active:
		_ghost_timer += delta
		if _ghost_timer >= GHOST_INTERVAL:
			_ghost_timer = 0.0
			var g: Sprite2D = _ghosts.pop_front()
			g.visible = true
			g.position = _sprite.position
			g.rotation = _sprite.rotation
			g.scale = _sprite.scale
			g.modulate = Color(1.0, 0.9, 0.7, 0.35)
			_ghosts.append(g)
			if not _arm_ghosts.is_empty():
				var ga: Sprite2D = _arm_ghosts.pop_front()
				ga.visible = true
				ga.global_transform = _arm_sprite.global_transform
				ga.modulate = g.modulate
				_arm_ghosts.append(ga)
	else:
		_ghost_timer = 0.0
	for i in _ghosts.size():
		var g := _ghosts[i]
		if g.visible:
			g.modulate.a -= delta * 3.5
			if g.modulate.a <= 0.0:
				g.visible = false
	for ga in _arm_ghosts:
		if ga.visible:
			ga.modulate.a -= delta * 3.5
			if ga.modulate.a <= 0.0:
				ga.visible = false


func _draw() -> void:
	if _enemy == null:
		return
	var st := _enemy.state
	if st == EnemyBase.State.DEAD:
		return
	if _alert_t >= 0.0 and _alert_t < 0.6:
		var font := ThemeDB.fallback_font
		var a := 1.0 - _alert_t / 0.6
		draw_string(font, Vector2(-8, -_enemy.hurt_height - 60.0 - _alert_t * 30.0), "!", HORIZONTAL_ALIGNMENT_CENTER, 16, 44, Color(1.0, 0.85, 0.5, a))
	if show_overhead_bar and (_enemy.hp < _enemy.max_hp or _enemy.poise > 0.0 or st == EnemyBase.State.BROKEN):
		var w := 90.0
		var top := Vector2(-w / 2.0, -_enemy.hurt_height - 40.0)
		draw_rect(Rect2(top, Vector2(w, 7)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(top, Vector2(w * _enemy.hp / _enemy.max_hp, 7)), Color("9bd48a"))
		draw_rect(Rect2(top + Vector2(0, 10), Vector2(w, 5)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(top + Vector2(0, 10), Vector2(w * _enemy.poise / _enemy.max_poise, 5)), Color("8fd3ff"))
	if st == EnemyBase.State.BROKEN:
		var pulse := 0.6 + 0.4 * sin(_t * 5.0)
		draw_circle(Vector2(0, -_enemy.hurt_height * 0.4), 60.0, Color("8fd3ff", 0.08 * pulse))

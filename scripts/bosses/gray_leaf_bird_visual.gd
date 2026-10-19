extends Sprite2D
## 첫 보스 '잿빛 잎새의 새'의 그림. 2026-10-20: 한 장 그림을 통째로 기울이던 방식을 버리고 **부위 뼈대**(PartRig,
## art/rigs/gray_leaf_bird — 설계도 data/rigs/gray_leaf_bird.json, 자세 data/rigs/_archetypes/bird.json)로 바꿨다.
## 이 노드(Sprite2D, 그림 없음)는 자리만 지키고, 자식 Rig 가 몸통·머리·날개 두 쌍(안쪽·바깥쪽)·접은 날개·꼬리 두 갈래·새 다리 두 개를 관절로 움직인다.
##  - 날갯짓: 위상 누적기(_flap_phase += 빠르기 × delta)로 어깨가 먼저, 바깥 날개(손끝 깃)는 한 박자 늦게 따라온다.
##    날개가 내려칠 때 몸이 떠오르고, 들어 올릴 때 가라앉는다 (몸 들썩임은 날개와 반대). 꼬리는 흔들림(chain)이 따라온다.
##  - 땅에서는 다리 IK 로 발톱이 바닥선(BossRoom 의 GroundLine = 보스의 ground_y)을 딛는다 (걸을 때 딛은 발은 미끄러지지 않는다).
##    날 때는 다리를 접어 매단다. 내려앉으면 날개를 접는다 (펼친 날개 그림 ↔ 접은 날개 그림을 겹쳐 바꾼다: 둘 다 보이는 동안 비침 없음).
##  - 날개 휘두르기·부리 찍기는 세 박자 (예비에서 멈칫 → 빠른 타격 끝에서 지나침 → 출렁이며 되돌림), 보스의 phase_progress 를 그대로 쓴다.
##  - 쓰러짐: 공중에서 날개가 힘없이 들린 채 떨어지고 → 땅에 부딪혀 주저앉고 → 날개가 무너지며 몸이 옆으로 누워 땅에 붙는다
##    (RigMotion 내려놓기 ground_settle + 땅 닿기 ground_lock). 정화를 기다리는 동안 그대로 누워 옅게 숨쉰다.
## 판정·시간은 전혀 건드리지 않는다 (그림이 논리를 따라간다). 공개 값·노드 이름은 예전과 같다:
##   _muzzle(깃털 붉은 점) / _band·_band_front(잎 흩날리기 띠) / 새 색은 Rig 에만 (이 노드의 modulate 는 늘 흰색).
## 좌우: 뼈대는 늘 오른쪽을 보는 그림이다. 왼쪽을 볼 때 Rig 의 scale.x 를 뒤집고, 방향 전환은 폭이 1 → 0 → −1 을 지나며 몸을 튼다.

const RIG_ID := "gray_leaf_bird"
## 부위별 크기 배율 — 시트에 따로 그려진 부위들의 크기가 서로 맞지 않아서 그림 쪽에서 맞춘다 (뼈 배율, 자식도 함께 커진다).
## 다리·몸통(뿌리)은 1 이어야 한다 (다리 IK 가 시트 길이로 푼다).
const BONE_SCALE := {"head": 0.82, "wing_b_in": 1.25, "wing_f_in": 1.25, "wing_b_fold": 1.15, "wing_f_fold": 1.15, "tail_a": 1.05, "tail_c": 1.1}
## 잔상 간격(초)
const GHOST_INTERVAL := 0.03
## 누운 몸이 바닥에 묻히는 깊이 (게임 px)
const LIE_SINK := 12.0
## 날 때 몸을 발 자리보다 이만큼(게임 px) 내려 그린다 — 몸 가운데가 몸 충돌·맞는 영역(보스 원점 위 150px)에 오게.
## 바닥 가까이(이 값의 두 배 안)에서는 부드럽게 0 으로 (내려앉는 순간 발톱이 바닥에 닿는다).
const AIR_DROP := 95.0
## 펼친 날개 ↔ 접은 날개 그림이 바뀌는 빠르기 (초당 몫 — 6 이면 0.17초에 다 바뀐다)
const FOLD_SPEED := 6.0

## 뼈대 전체 배율 (1 = 설계도 game_scale 그대로)
@export var art_scale := 1.0

var rig: PartRig
var motion: RigMotion
var _boss: GrayLeafBird
var _t := 0.0
var _face := RigMotion.Chan.new(-1.0)
var _last_face_sign := -1.0
var _flap_phase := 0.0
var _flap_rate := 7.0
var _flap_amp := 0.0
var _floor_off := 0.0    # 바닥선의 이 노드 기준 높이 (게임 px) = Rig 의 자리 (Rig 의 y 0 은 늘 바닥선)
var _base_root_y := 0.0  # 서 있을 때의 뿌리 높이 (RigMotion.stand_root_y 처음 값)
var _air_h := 0.0        # 바닥 위로 떠 있는 높이 (뼈대 단위)
var _wing_chains: Array = []   # 땅 막기할 날개 사슬 [[어깨, 손목], [접은 날개] …] (뼈 번호)
var _wing_dir: Array = []      # 사슬마다 들어 올리는 회전 방향 (+1 / −1)
var _wing_lift := {}           # 뼈 번호 → 지금 들어 올린 각도 (라디안)
var _wing_side := {}           # 뼈 번호 → 들어 올리는 쪽 (+1 / −1, 다 풀릴 때까지 지킨다)
var _prev_state := -1
var _state_t := 0.0
var _from := {}          # 상태에 들어설 때 보이던 자세 (예비·쓰러짐이 여기서 출발)
var _prev_phase := ""
var _phase_from := {}    # 공격 국면이 바뀔 때 보이던 자세 (되돌림이 여기서 출발)
var _prev_flash := 0.0
var _prev_stagger := 0.0
var _prev_crouch := false
var _prev_shots := 0.0
var _was_grounded := false
var _crash_t := -1.0     # 쓰러짐: 땅에 닿은 뒤 지난 시간 (-1 = 아직 공중)
var _lie := 0.0          # 누운 몫 (0~1)
var _red := 0.0
var _tint := Color(1, 1, 1)
var _alive := 0.0        # 정화되어 색이 돌아오는 몫 (0 잿빛 → 1 살아난 빛)
var _ghost_timer := 0.0
var _head_variant := ""
var _look := 0.0         # 머리가 소녀 쪽을 보는 각도 (도)
var _fold := {"f": 0.0, "b": 0.0}   # 접은 날개 몫 (자세의 fold_* 를 빠르게 따라간다 — 반투명한 순간을 짧게)
var _idx := {}           # 뼈 이름 → 번호
var _spr := {}           # 뼈 이름 → 부위 그림 (투명도 바꾸기)
var _dust: CPUParticles2D
var _leaves: CPUParticles2D
var _leaf_burst: CPUParticles2D
var _glow: Node2D
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
	texture = null   # 예전 한 장 그림은 쓰지 않는다 (이 노드는 자리만)
	# 쓰러져 정화를 기다리는 동안 몸 뒤의 옅은 빛 (새 뒤에 그린다)
	_glow = Node2D.new()
	_glow.name = "Glow"
	_glow.show_behind_parent = true
	_glow.visible = false
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	rig = PartRig.new()
	rig.name = "Rig"
	add_child(rig)
	if not rig.build(RIG_ID):
		push_error("새 뼈대를 읽지 못했다: " + RIG_ID)
		rig = null
		return
	motion = RigMotion.new(rig)
	for i in rig.names.size():
		_idx[rig.names[i]] = i
		var s := rig.sprite_of(rig.names[i])
		if s:
			_spr[rig.names[i]] = s
	for bn in BONE_SCALE:
		if _idx.has(bn):
			var k: float = BONE_SCALE[bn]
			rig.scl[_idx[bn]] = Vector2(k, k)
	rig.setup_ghosts(rig.data.get("ghost", ["wing_f_in", "wing_f_out", "head"]), 6)
	_base_root_y = motion.stand_root_y
	# 몸·발 채널의 단위 L: 새 발은 발톱까지 높아(발목이 땅에서 높다) RigMotion 이 잰 L(다리 + 발 높이)로는 보폭이 다리가 닿는 거리보다 길어
	# 뒷발이 닿지 못하는 순간 엉덩이가 툭 튀었다 → 두 마디(허벅지·정강이) 길이의 0.95 배로 줄인다. 자세 파일(bird.json)의 몸·발 값은 이 단위.
	var reach := 0.0
	for leg in motion.legs:
		reach += (leg.a + leg.b) / maxf(motion.legs.size(), 1)
	if reach > 1.0:
		motion.L = reach * 0.95
	motion.snap_feet()
	for entry in [[["wing_f_in", "wing_f_out"], -1.0], [["wing_b_in", "wing_b_out"], 1.0], [["wing_f_fold"], 1.0], [["wing_b_fold"], 1.0]]:
		var ids := PackedInt32Array()
		for bn in entry[0]:
			if _idx.has(bn):
				ids.append(_idx[bn])
		if ids.size() > 0:
			_wing_chains.append(ids)
			_wing_dir.append(entry[1])
	if _boss:
		_face.v = float(_boss.facing)
		_last_face_sign = signf(_face.v)
	_from = motion.pose("hover")
	_phase_from = _from
	_dust = _make_dust()
	_leaves = _make_leaves(false)
	_leaf_burst = _make_leaves(true)
	_muzzle = MuzzleDot.new()
	_muzzle.top_level = true
	_muzzle.visible = false
	add_child(_muzzle)
	_band = RainBand.new()
	_band.visible = false
	_band.show_behind_parent = true   # 새 그림 뒤 (top_level 이 아니어야 듣는다)
	_band.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # 그라디언트엔 밉맵이 없다
	add_child(_band)
	_band_front = RainBand.new()   # 2페이즈 고리의 아랫반 (새 앞)
	_band_front.front = true
	_band_front.visible = false
	add_child(_band_front)


func _make_dust() -> CPUParticles2D:
	var d := CPUParticles2D.new()
	d.top_level = true
	d.emitting = false
	d.one_shot = true
	d.explosiveness = 1.0
	d.amount = 16
	d.lifetime = 0.6
	d.direction = Vector2(0, -1)
	d.spread = 80.0
	d.gravity = Vector2(0, 200)
	d.initial_velocity_min = 80.0
	d.initial_velocity_max = 240.0
	d.scale_amount_min = 4.0
	d.scale_amount_max = 9.0
	d.color = Color(0.72, 0.7, 0.62, 0.5)
	add_child(d)
	return d


## 흩날리는 잿빛 잎 (부위 시트의 낱잎 그림). burst = 한 번에 터지는 것 (부딪힘·쓰러짐), 아니면 날갯짓 동안 조금씩 떨어진다.
func _make_leaves(burst: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.top_level = true
	p.local_coords = false
	p.emitting = false
	p.texture = load("res://art/rigs/%s/%s.png" % [RIG_ID, "leaf_b" if burst else "leaf_a"])
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	p.amount = 18 if burst else 10
	p.lifetime = 1.1 if burst else 2.0
	p.one_shot = burst
	p.explosiveness = 0.9 if burst else 0.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 70.0 if burst else 110.0
	p.direction = Vector2(0, -1) if burst else Vector2(-0.3, 1)
	p.spread = 70.0 if burst else 50.0
	p.gravity = Vector2(0, 120 if burst else 60)
	p.initial_velocity_min = 40.0 if burst else 20.0
	p.initial_velocity_max = 140.0 if burst else 60.0
	p.angular_velocity_min = -160.0
	p.angular_velocity_max = 160.0
	p.angle_min = -180.0
	p.angle_max = 180.0
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.2
	p.damping_min = 20.0
	p.damping_max = 40.0
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.1, 0.75, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	p.color_ramp = fade
	p.color = Color(0.82, 0.84, 0.82)
	add_child(p)
	return p


# ---------- 매 프레임 ----------

func _process(delta: float) -> void:
	_t += delta
	if _boss == null or rig == null:
		return
	var st := _boss.state
	if st != _prev_state:
		_on_enter(st)
	_state_t += delta
	var k := rig.game_scale * art_scale

	# ---- 방향: 폭이 +1 → 0 → −1 을 지나며 몸을 튼다 (0 을 지나는 순간 딛은 발을 세상에 남긴다) ----
	var want_face := float(_boss.facing)
	if st == GrayLeafBird.State.EAT and _boss._target_pile and is_instance_valid(_boss._target_pile):
		# 잎을 삼키는 동안은 잎 더미 쪽으로 고개를 숙인다 (논리는 소녀 쪽을 보고 있어도 — 이때는 공격이 없다)
		var dxp: float = _boss._target_pile.global_position.x - _boss.global_position.x
		if absf(dxp) > 10.0:
			want_face = signf(dxp)
	_face.damp(want_face, 11.0, delta)
	var fs := signf(_face.v) if _face.v != 0.0 else _last_face_sign
	if fs != _last_face_sign:
		motion.flip_feet()
		_last_face_sign = fs
	var vis_f := _last_face_sign

	# ---- 땅인가: 땅 상태는 늘 바닥선 위, 무너짐·쓰러짐은 바닥에 닿았을 때, 이륙 전 웅크림도 땅 ----
	var near_floor := _boss.global_position.y >= _boss.ground_y - 8.0
	var grounded: bool = st in GrayLeafBird.GROUND_STATES \
		or (st in [GrayLeafBird.State.BROKEN, GrayLeafBird.State.FALLEN, GrayLeafBird.State.PURIFIED] and near_floor) \
		or (st == GrayLeafBird.State.TAKEOFF and _boss.crouching)
	# Rig 의 y 0 = 늘 바닥선 (땅 닿기·내려놓기·날개·꼬리의 땅 막기가 진짜 바닥을 본다). 날고 있으면 그 높이만큼 뿌리를 들어 올린다
	# (보스 원점 = 발 자리라 몸은 예전과 같은 자리). 땅 상태에선 보스 원점이 바닥보다 30px 아래라(몸 충돌 캡슐) 높이는 0.
	_floor_off = _boss.ground_y - _boss.global_position.y
	var h_px := maxf(_floor_off, 0.0)
	h_px -= AIR_DROP * smoothstep(0.0, AIR_DROP * 2.0, h_px)
	var h_rig := h_px / maxf(k, 0.0001)
	if grounded and not _was_grounded and _t > 0.05:
		_on_touchdown(st)
	_was_grounded = grounded

	# ---- 일회성 사건 ----
	var ph := _boss.attack_phase
	if ph != _prev_phase:
		_phase_from = motion.capture()
		if ph == "active":
			_ghost_timer = GHOST_INTERVAL
			match st:
				GrayLeafBird.State.SWEEP:
					_puff(8, vis_f * 80.0, 0.8)
					_leaf_pop(10)
				GrayLeafBird.State.PECK:
					_puff(6, vis_f * 150.0, 0.6)
		_prev_phase = ph
	if _boss.stagger > 0.9 and _prev_stagger <= 0.9:
		# 잎 삼키기를 끊겼다: 뒤로 움찔, 잎이 흩날린다
		motion.kick("impact", 120.0)
		_leaf_pop(12)
	_prev_stagger = _boss.stagger
	if _prev_crouch and not _boss.crouching and st == GrayLeafBird.State.TAKEOFF:
		# 웅크림에서 땅을 박차고 날아오른다
		motion.kick("crouch", -1.2)
		_puff(14, 0.0, 1.2)
		_leaf_pop(8)
	_prev_crouch = _boss.crouching
	var fl := _boss.flash_amount()
	if fl > _prev_flash + 0.4 and st not in [GrayLeafBird.State.FALLEN, GrayLeafBird.State.PURIFIED]:
		motion.kick("impact", 70.0)
		_leaf_pop(4)
	_prev_flash = fl
	if _boss.muzzle_flash > _prev_shots + 0.5:
		motion.kick("recoil", 120.0)   # 깃털 한 발: 고개가 살짝 튄다
		_ghost_timer = GHOST_INTERVAL
	_prev_shots = _boss.muzzle_flash

	# ---- 자세 고르기 ----
	var p := _pose_for(st, ph, delta)
	var drive: int = p.get("_drive", RigMotion.Drive.NORMAL)
	var feet: int = RigMotion.Feet.POSE if grounded else RigMotion.Feet.AIR
	if p.has("_feet"):
		feet = p["_feet"]
	motion.breath = float(p.get("_breath", 1.0))
	motion.ground_lock = float(p.get("_lock", 0.0))
	motion.ground_settle = float(p.get("_settle", 0.0))

	# ---- 날갯짓 (위상은 끊기지 않고 빠르기·크기만 따라간다) ----
	var rate: float = p.get("_rate", 0.0)
	var amp: float = p.get("_amp", 0.0)
	_flap_rate = Motion.damp(_flap_rate, maxf(rate, 2.0), 5.0, delta)
	_flap_amp = Motion.damp(_flap_amp, amp, 6.0, delta)
	_flap_phase = fmod(_flap_phase + _flap_rate * delta, TAU * 64.0)
	if _flap_amp > 0.05:
		var s := sin(_flap_phase)
		var lag := sin(_flap_phase - 1.05)          # 바깥 날개(손끝 깃)는 한 박자 늦게
		var down := maxf(-cos(_flap_phase), 0.0)     # 내려치는 반 주기의 세기 (몸이 떠오른다)
		p["wing_b_in"] = float(p["wing_b_in"]) + _flap_amp * s
		p["wing_f_in"] = float(p["wing_f_in"]) - _flap_amp * s
		p["wing_b_out"] = float(p["wing_b_out"]) + _flap_amp * 0.75 * lag
		p["wing_f_out"] = float(p["wing_f_out"]) - _flap_amp * 0.75 * lag
		# 몸 들썩임: 날개가 위에 있을 때 가라앉고, 내려칠 때 떠오른다. 고개는 몸과 반대로 조금 버틴다.
		var bob := _flap_amp / 40.0
		p["hip_y"] = float(p["hip_y"]) + 0.08 * bob * s - 0.032 * bob * down
		p["lean"] = float(p["lean"]) + 3.0 * bob * cos(_flap_phase)
		p["head"] = float(p["head"]) - 4.0 * bob * cos(_flap_phase)
	var ghost: bool = p.get("_ghost", false)
	var shed: bool = p.get("_shed", false)
	for side in ["f", "b"]:
		var tf := clampf(float(p.get("fold_" + side, 0.0)), 0.0, 1.0)
		_fold[side] = move_toward(float(_fold[side]), tf, FOLD_SPEED * delta) if delta > 0.0 else tf
	_clean(p)
	motion.set_target(p, drive, feet)
	# 떠 있는 높이: 뿌리를 그만큼 올리고, 매달린 발도 같이 올린다 (발이 높이 변화에 끌려 늦지 않게 — 늦음은 자세 바뀜에만)
	if feet == RigMotion.Feet.AIR or not grounded:
		for leg in motion.legs:
			leg.h += h_rig - _air_h
	_air_h = h_rig
	motion.stand_root_y = _base_root_y - h_rig

	# ---- 움직이기 ----
	var vx := _boss.velocity.x
	var speed_rig := vx / maxf(k, 0.0001) * vis_f
	motion.update(delta, {"speed": speed_rig if grounded else 0.0, "dx": speed_rig * delta if grounded else 0.0,
		"vy": _boss.velocity.y / maxf(k, 0.0001), "grounded": grounded})
	_apply_folds()
	_clamp_wings(delta)
	var sq := clampf(motion.spring_value("squash"), -0.25, 0.3) * 0.08
	# 누운 몸은 바닥에 조금 묻힌다 (잎 끝이 바닥 풀에 묻혀 무게가 실려 보이게 — 껍질 점은 삐죽한 잎 끝까지라 그대로면 떠 보인다)
	rig.position = Vector2(0.0, _floor_off + LIE_SINK * _lie)
	rig.scale = Vector2(_face.v * art_scale * (1.0 + sq), art_scale * (1.0 - sq))

	# ---- 잔상·잎 ----
	if ghost:
		_ghost_timer += delta
		if _ghost_timer >= GHOST_INTERVAL:
			_ghost_timer = 0.0
			rig.snapshot_ghost(Color(0.85, 0.9, 0.9, 0.32))
	else:
		_ghost_timer = 0.0
	rig.fade_ghosts(delta)
	if _leaves.emitting != shed:
		_leaves.emitting = shed
	if shed:
		_leaves.global_position = _boss.body_center() + Vector2(-vis_f * 40.0, 0.0)

	_update_telegraphs()
	_update_color(st, fl, delta)
	_glow.visible = st == GrayLeafBird.State.FALLEN and _crash_t > 0.6
	if _glow.visible:
		_glow.queue_redraw()


## 상태에 들어설 때 한 번: 그때 보이던 자세를 기억하고, 섞는 길이를 정한다.
func _on_enter(st: int) -> void:
	_from = motion.capture()
	_state_t = 0.0
	var fade := 0.12
	match st:
		GrayLeafBird.State.SWEEP, GrayLeafBird.State.PECK:
			fade = 0.0   # 세 박자 곡선이 지금 자세에서 출발한다
		GrayLeafBird.State.FALLEN:
			fade = 0.08
			motion.kick("impact", 140.0)
			_leaf_pop(16)
			# 무너져 땅에 있던 채로 쓰러지면 공중 단계 없이 바로 무너져 눕는다 (땅에 닿는 순간이 따로 오지 않는다)
			_crash_t = 0.0 if _boss.global_position.y >= _boss.ground_y - 8.0 else -1.0
		GrayLeafBird.State.BROKEN:
			fade = 0.15
			motion.kick("impact", 90.0)
			_leaf_pop(10)
		GrayLeafBird.State.PURIFIED:
			fade = 0.3
			_leaf_pop(16)   # 잎이 흩날리며 (곧 초록으로 물든다)
		GrayLeafBird.State.WAIT:
			_alive = 0.0
			_crash_t = -1.0
	if _prev_state == GrayLeafBird.State.BROKEN:
		fade = maxf(fade, 0.3)
	motion.transition(fade)
	_prev_state = st


## 발이 땅에 닿은 순간 (착지·무너져 떨어짐·쓰러져 떨어짐)
func _on_touchdown(st: int) -> void:
	match st:
		GrayLeafBird.State.FALLEN:
			_crash_t = 0.0
			_from = motion.capture()
			motion.kick("crouch", 2.2)
			motion.kick("thud", 10.0)
			motion.kick("squash", 2.4)
			_puff(20, 0.0, 1.5)
			_leaf_pop(18)
		GrayLeafBird.State.BROKEN:
			motion.kick("crouch", 1.8)
			motion.kick("squash", 1.6)
			_puff(16, 0.0, 1.2)
			_leaf_pop(8)
		_:
			motion.kick("crouch", 1.4)
			motion.kick("squash", 1.2)
			_puff(18, 0.0, 1.1)


## 이번 프레임의 목표 자세 (base 까지 합친 사전 + '_' 로 시작하는 연출 값: _drive/_feet/_rate/_amp/_ghost/_shed/_breath/_lock/_settle).
func _pose_for(st: int, ph: String, delta: float) -> Dictionary:
	var S := GrayLeafBird.State
	var p := {}
	var air_lean := clampf(_boss.velocity.x * float(_last_face_sign) / 60.0, -12.0, 14.0)   # 날아가는 쪽으로 기운다
	_look = Motion.damp(_look, _look_angle(), 4.0, delta)
	var head := ""
	match st:
		S.WAIT, S.INTRO, S.HOVER:
			p = motion.pose("hover").duplicate()
			p["lean"] = float(p["lean"]) + air_lean
			p["head"] = float(p["head"]) + _look
			p["_rate"] = 7.2
			p["_amp"] = 30.0
		S.LEAF_RAIN:
			# 넓게 펼친 날개를 크게 털며 잎을 떨군다
			p = motion.pose("hover_wide").duplicate()
			p["lean"] = float(p["lean"]) + air_lean
			p["_rate"] = 9.0
			p["_amp"] = 40.0
			p["_shed"] = true
		S.FEATHERS:
			# 깃털 던지기: 예고 0.6초 동안 가까운 날개를 뒤로 당겨 세우고 고개를 젖힌다(멈칫) → 한 발마다 날개를 앞으로 채찍처럼 휘둘러
			# 날개 앞깃 끝(붉은 점 자리)에서 깃털이 떠나고, 다음 발 전에 반쯤 다시 당긴다. 쏘는 때는 보스와 같은 셈 (0.6 + 0.15 × n).
			var count := _boss.feather_count if _boss.phase == 1 else _boss.feather_count + 2
			var ts := _state_t + 0.04   # 채널이 따라오는 늦음만큼 미리
			if ts < 0.6:
				p = motion.mix(motion.pose("hover"), motion.pose("feather_cock"), Motion.anticipation(clampf(ts / 0.6, 0.0, 1.0)))
				p["_drive"] = RigMotion.Drive.QUICK
			else:
				var n := floori((ts - 0.6) / 0.15)
				var u := fmod(ts - 0.6, 0.15) / 0.15
				var back := 0.0
				if n < count - 1:
					back = smoothstep(0.3, 1.0, u) * 0.6   # 다음 발을 위해 반쯤 다시 당긴다
				p = motion.mix(motion.pose("feather_release"), motion.pose("feather_cock"), back)
				p["_drive"] = RigMotion.Drive.FAST
			p["_rate"] = 6.0
			p["_amp"] = 8.0
			p["_breath"] = 0.0
			head = "scream" if ts > 0.45 else ""
		S.WIND:
			if _boss.is_red():
				# 붉은 예고: 두 날개를 머리 위 뒤로 크게 치켜들고 몸을 젖힌다 (곧 거대한 날갯짓)
				var u := clampf(_state_t / maxf(_boss.wind_telegraph, 0.01), 0.0, 1.0)
				p = motion.mix(motion.pose("hover"), motion.pose("gust_windup"), Motion.anticipation(u))
				p["_rate"] = 3.0
				p["_amp"] = 4.0
				p["_drive"] = RigMotion.Drive.SOFT
				head = "scream" if u > 0.5 else ""
			else:
				p = motion.pose("gust").duplicate()
				p["_rate"] = 12.5
				p["_amp"] = 50.0
				p["_shed"] = true
				p["_drive"] = RigMotion.Drive.QUICK
				head = "scream"
		S.DESCEND:
			# 날개를 V 로 세워 미끄러져 내려오며 다리를 뻗는다 (바닥 가까이 오면 날개를 크게 저어 속도를 죽인다)
			var h := _boss.ground_y - _boss.global_position.y
			var near := 1.0 - clampf((h - 40.0) / 260.0, 0.0, 1.0)
			p = motion.mix(motion.pose("glide"), motion.pose("brake"), near)
			p["_rate"] = lerpf(5.0, 10.0, near)
			p["_amp"] = lerpf(8.0, 34.0, near)
		S.GROUND_IDLE:
			p = motion.pose("idle").duplicate()
			p["head"] = float(p["head"]) + _look * 0.7 + sin(_t * 0.9) * 3.0
			# 잎 삼키기를 끊겨 움찔: 몸을 젖히고 날개를 펄럭 연다
			if _boss.stagger > 0.0:
				p = motion.mix(p, motion.pose("flinch"), Motion.ease_out(_boss.stagger, 2.0))
		S.WALK_TO_PILE:
			var amt := clampf(absf(_boss.velocity.x) / maxf(_boss.walk_speed, 1.0), 0.0, 1.0)
			p = motion.mix(motion.pose("idle"), motion.pose("walk"), amt)
			# 걸을 때 고개를 앞뒤로 끄덕인다 (딛는 발에 맞춰)
			var bob := 0.0
			if motion.legs.size() >= 2:
				bob = clampf((motion.legs[0].x - motion.legs[1].x) / maxf(motion.L * 0.5, 1.0), -1.0, 1.0)
			p["head"] = float(p["head"]) + 7.0 * absf(bob) * amt
			p["_feet"] = RigMotion.Feet.GAIT
			p["_breath"] = 0.4
		S.EAT:
			# 고개를 숙여 잎 더미를 쪼고, 삼킬 때마다 고개를 들썩인다 (목을 타고 넘기는 꿀꺽)
			p = motion.pose("eat").duplicate()
			var peck := absf(sin(_state_t * 5.2))
			p["head"] = float(p["head"]) - 16.0 * (1.0 - peck)
			p["lean"] = float(p["lean"]) - 4.0 * (1.0 - peck)
			var gulp_ph := fmod(_state_t, 0.86) / 0.86
			if gulp_ph > 0.7:
				p["head"] = float(p["head"]) - 22.0 * sin((gulp_ph - 0.7) / 0.3 * PI)
			p["_drive"] = RigMotion.Drive.QUICK
			p["_breath"] = 0.3
			head = "down" if peck > 0.35 else ""
		S.SWEEP:
			p = _three_beat("sweep_windup", "sweep", "sweep_ready", ph)
			p["_ghost"] = ph == "active"
			p["_breath"] = 0.0
		S.PECK:
			p = _three_beat("peck_windup", "peck", "peck_ready", ph)
			p["_ghost"] = ph == "active"
			p["_breath"] = 0.0
			if ph == "active":
				p["_feet"] = RigMotion.Feet.AIR   # 돌진 찍기는 두 발을 띄워 폴짝 뛰어든다 (딛은 발이 뒤에 끌려 남지 않게)
			if ph == "active" or (ph == "recovery" and _boss.phase_progress() < 0.3):
				head = "scream"
		S.TAKEOFF:
			if _boss.crouching:
				p = motion.pose("crouch").duplicate()
				p["_rate"] = 3.0
				p["_amp"] = 6.0
				p["_drive"] = RigMotion.Drive.QUICK
			else:
				p = motion.pose("takeoff").duplicate()
				p["lean"] = float(p["lean"]) + air_lean
				p["_rate"] = 10.5
				p["_amp"] = 46.0
		S.BROKEN:
			if _boss.global_position.y < _boss.ground_y - 8.0:
				p = motion.pose("fall_air").duplicate()   # 떨어지는 중: 날개를 허우적
				p["_rate"] = 11.0
				p["_amp"] = 14.0
			else:
				p = motion.pose("broken").duplicate()
				var sway := sin(_t * 1.4)
				p["lean"] = float(p["lean"]) + sway * 2.0
				p["head"] = float(p["head"]) + sin(_t * 1.4 + 0.8) * 4.0
				p["_drive"] = RigMotion.Drive.SOFT
		S.FALLEN, S.PURIFIED:
			p = _fallen_pose(st, delta)
	if st != S.FALLEN and st != S.PURIFIED:
		_lie = 0.0
	if p.is_empty():
		p = motion.pose("hover").duplicate()
	_set_head(head)
	return p


## 쓰러짐: 공중 → 땅에 부딪혀 주저앉음 → 날개가 무너지며 옆으로 눕는다 → 누운 채 옅게 숨쉰다. 정화되면 색이 돌아오고 고개를 든다.
func _fallen_pose(st: int, delta: float) -> Dictionary:
	var p: Dictionary
	if _crash_t < 0.0:
		# 아직 공중: 날개가 힘없이 위로 들리고 몸이 앞으로 고꾸라진다
		p = motion.pose("fall_air").duplicate()
		p["_rate"] = 6.0
		p["_amp"] = 8.0
		p["_drive"] = RigMotion.Drive.SOFT
		p["_breath"] = 0.0
		p["_lock"] = 1.0
		return p
	_crash_t += delta
	# 부딪힌 뒤: 0~0.2초 다리가 꺾이며 주저앉고 → 0.1~0.6초 옆으로 눕는다 (무게에 끌리듯 점점 빨리) → 눕는 순간 한 번 털썩
	var sit := Motion.ease_out(clampf(_crash_t / 0.14, 0.0, 1.0), 2.0)
	var lie := Motion.ease_in(clampf((_crash_t - 0.06) / 0.42, 0.0, 1.0), 1.5)
	if lie >= 1.0 and _lie < 1.0:
		motion.kick("thud", 6.0)
		motion.kick("impact", -50.0)
		_puff(12, -_last_face_sign * 60.0, 0.8)
		_leaf_pop(8)
	_lie = lie
	p = motion.mix(motion.mix(_from, motion.pose("crash"), sit), motion.pose("dead"), lie)
	p["_drive"] = RigMotion.Drive.QUICK if lie < 1.0 else RigMotion.Drive.SOFT
	p["_breath"] = 0.25 if lie >= 1.0 else 0.0
	p["_lock"] = 1.0
	p["_settle"] = lie
	p["_feet"] = RigMotion.Feet.AIR if lie > 0.3 else RigMotion.Feet.POSE
	if st == GrayLeafBird.State.PURIFIED:
		# 정화: 고개를 들고 날개를 조금 펴며 빛이 된다 (BossRoom 이 몸 전체를 하얗게 흐린다)
		var u := Motion.ease_in_out(clampf(_state_t / 1.2, 0.0, 1.0))
		p = motion.mix(p, motion.pose("purified"), u)
		p["_lock"] = 1.0
		p["_settle"] = 1.0
		p["_feet"] = RigMotion.Feet.AIR
		p["_breath"] = 0.6
		p["_drive"] = RigMotion.Drive.SLOW
	return p


## 세 박자: 예비(지금 자세 → 예비 자세, 끝에서 멈칫) → 타격(채찍처럼, 지나침) → 되돌림(출렁이며 준비 자세).
func _three_beat(windup: String, strike: String, ready: String, ph: String) -> Dictionary:
	var q := _boss.phase_progress()
	var p: Dictionary
	match ph:
		"startup":
			p = motion.three_beat(_from, motion.pose(windup), motion.pose(strike), motion.pose(ready), "windup", q)
			p["_drive"] = RigMotion.Drive.SOFT
		"active":
			p = motion.three_beat(_from, motion.pose(windup), motion.pose(strike), motion.pose(ready), "strike", q, 0.2)
			p["_drive"] = RigMotion.Drive.FAST
		"recovery":
			p = motion.three_beat(_phase_from, {}, {}, motion.pose(ready), "recover", q)
			p["_drive"] = RigMotion.Drive.SETTLE
		_:
			p = motion.pose(ready).duplicate()
	return p


## 뼈대 설계도 sockets 의 자리 (세계 좌표): "beak"(부리 끝) / "wing_tip"(가까운 날개 끝). 시험·연출이 읽는다.
func socket_global(sock: String) -> Vector2:
	if rig == null:
		return global_position
	var sd: Dictionary = rig.data.get("sockets", {}).get(sock, {})
	if sd.is_empty():
		return global_position
	return rig.to_global(rig.bone_point(str(sd["bone"]), PartRig._v(sd["pos"])))


## 머리가 소녀 쪽을 보는 각도 (도, + = 아래). 몸 기울기와 상관없이 머리만 조금 돌린다.
func _look_angle() -> float:
	var pl := _boss.player
	if pl == null or not is_instance_valid(pl):
		return 0.0
	var to := pl.global_position + Vector2(0, -60) - (_boss.global_position + Vector2(0, -240))
	return clampf(rad_to_deg(atan2(to.y, maxf(absf(to.x), 1.0))) * 0.35, -14.0, 18.0)


## 머리 그림 바꾸기 (부르짖는 머리 / 숙인 머리). 같은 값이면 아무것도 안 한다.
func _set_head(v: String) -> void:
	if v == _head_variant:
		return
	_head_variant = v
	rig.set_variant("head", v)


## '_' 로 시작하는 연출 값은 RigMotion 에 넘기지 않는다 (채널이 아니다).
func _clean(p: Dictionary) -> void:
	for key in p.keys():
		if str(key).begins_with("_"):
			p.erase(key)


## 펼친 날개 ↔ 접은 날개 그림: fold_* 채널(0~1)로 겹쳐 바꾼다. 접은 그림이 먼저 다 나타난 뒤 펼친 그림이 사라진다
## (둘이 함께 반투명해지는 순간이 없어 몸이 비치지 않는다). 접히는 동안 펼친 날개는 조금 줄어든다 (몸 쪽으로 접혀 들어가는 것처럼).
func _apply_folds() -> void:
	for side in ["f", "b"]:
		var f: float = _fold[side]
		var spread_a := clampf(2.0 - f * 2.0, 0.0, 1.0)
		var fold_a := clampf(f * 2.0, 0.0, 1.0)
		for part in ["wing_%s_in" % side, "wing_%s_out" % side]:
			var s: Sprite2D = _spr.get(part)
			if s:
				s.self_modulate.a = spread_a
				s.visible = spread_a > 0.01
		var fsp: Sprite2D = _spr.get("wing_%s_fold" % side)
		if fsp:
			fsp.self_modulate.a = fold_a
			fsp.visible = fold_a > 0.01
		var wi: int = _idx.get("wing_%s_in" % side, -1)
		if wi >= 0:
			var k0: float = BONE_SCALE.get("wing_%s_in" % side, 1.0)
			var kk := k0 * lerpf(1.0, 0.72, f)
			rig.scl[wi] = Vector2(kk, kk)


## 날개 땅 막기: 펼친 날개·접은 날개가 바닥선 아래로 들어가면 어깨(그다음 손목)를 '들어 올리는 쪽'으로 돌려 날개 끝을 바닥 위에 눕힌다
## (축 없는 뼈라 RigMotion 의 무기 땅 막기를 못 쓴다 — 같은 방법을 여기서). 날개는 설계도에서 '부드러운 부위'라 몸을 받쳐 띄우지 않는다.
## 돌리는 쪽: 가장 깊은 점이 관절보다 앞이면 −, 뒤면 + (빨리 들리는 쪽). 한 번 들기 시작하면 다 풀릴 때까지 그 쪽을 지킨다 —
## 두 해 사이를 오가며 날개가 한 프레임에 뒤집히지 않게. 든 각도는 필요하면 바로 늘리고, 필요 없어지면 천천히(WING_RELEASE) 푼다.
const WING_MARGIN := 2.0
const WING_RELEASE := 5.0

func _clamp_wings(delta: float) -> void:
	var bx := rig.body_xf
	var changed := false
	for ci in _wing_chains.size():
		var chain: PackedInt32Array = _wing_chains[ci]
		var spr: Sprite2D = _spr.get(rig.names[chain[0]])
		if spr and not spr.visible:
			for jb in chain:
				_wing_lift[jb] = 0.0   # 안 보이는 날개(접은 그림이 대신 보일 때)는 막지 않는다 — 다시 보이는 순간 바로 막힌다
			continue
		for c in chain.size():
			var jb := chain[c]
			var held: float = _wing_lift.get(jb, 0.0)
			var dir: float = _wing_side.get(jb, float(_wing_dir[ci]))
			var total := 0.0
			for iter in 3:
				var deepest := -INF
				var q := Vector2.ZERO
				for j in range(c, chain.size()):
					var t := bx * rig.xf[chain[j]]
					for hp in rig.hulls[chain[j]]:
						var w := t * hp
						if w.y > deepest:
							deepest = w.y
							q = w
				var pj := bx * rig.xf[jb].origin
				if deepest <= -WING_MARGIN or pj.y >= -WING_MARGIN:
					break
				if held < 0.01 and iter == 0 and total == 0.0:
					dir = -1.0 if q.x > pj.x else 1.0
					_wing_side[jb] = dir
				var rr := (q - pj).length()
				if rr <= 1.0:
					break
				var want := clampf((-WING_MARGIN - pj.y) / rr, -1.0, 1.0)
				var cur := (q - pj).angle()
				var s1 := asin(want)
				var best := INF
				for sol in [s1, PI - s1]:
					var d := wrapf(sol - cur, -PI, PI)
					if d * dir >= -0.001 and absf(d) < best:
						best = absf(d)
				if best == INF or total + best > 2.2:
					break
				total += best + 0.01
				rig.rot[jb] += dir * (best + 0.01)
				rig.compute_from(jb)
				changed = true
			# 풀릴 때는 천천히: 이번에 필요한 것보다 더 들려 있던 몫을 조금씩 내린다
			var lift := maxf(total, held - WING_RELEASE * delta) if delta > 0.0 else total
			if lift > total + 0.0001:
				rig.rot[jb] += dir * (lift - total)
				rig.compute_from(jb)
				changed = true
			_wing_lift[jb] = lift
		for jb in chain:
			if rig.squash_y[jb] < 1.0:
				rig.squash_y[jb] = 1.0
				changed = true
	if changed:
		rig.apply()


func _update_color(st: int, fl: float, delta: float) -> void:
	_red = Motion.damp(_red, 1.0 if _boss.is_red() else 0.0, 14.0, delta)
	if st == GrayLeafBird.State.PURIFIED:
		_alive = minf(_alive + delta / 1.2, 1.0)
	var ash := Color(0.8, 0.82, 0.84) if _boss.phase == 1 else Color(0.72, 0.7, 0.72)
	ash = ash.lerp(Color(1.25, 1.35, 1.45), _boss.telegraph_amount * (0.7 + 0.3 * sin(_t * 24.0)))
	ash = ash.lerp(Color(2.2, 0.6, 0.5), _red * (0.5 + 0.5 * sin(_t * 30.0)))
	# 정화: 잿빛이 걷히고 잎의 초록·금빛이 돌아온다
	ash = ash.lerp(Color(1.1, 1.35, 1.0), _alive)
	_tint = _tint.lerp(ash, 1.0 - exp(-20.0 * delta)) if delta > 0.0 else ash
	rig.modulate = _tint
	rig.set_flash(fl * 0.8, Color(1.5, 1.5, 1.5))
	var lc := Color(0.82, 0.84, 0.82).lerp(Color(0.95, 1.2, 0.85), _alive)
	_leaves.color = lc
	_leaf_burst.color = lc


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
		# 부모가 움직여도 세계 좌표 그대로가 되게 매 프레임 되돌린다 (top_level 이 아니라서)
		b.global_transform = Transform2D.IDENTITY
		b.visible = b.amount > 0.01 and (not b.front or b.phase != 1)
		if b.visible:
			b.queue_redraw()


## 쓰러져 정화를 기다리는 동안 몸 뒤의 옅은 빛 (손을 얹을 수 있다는 표시)
func _draw_glow() -> void:
	if _boss == null:
		return
	var pulse := 0.6 + 0.4 * sin(_t * 3.0)
	var c := Vector2(0, _floor_off - 120.0)
	_glow.draw_circle(c, 120.0, Color(0.75, 0.95, 0.85, 0.05 * pulse))
	_glow.draw_circle(c, 75.0, Color(0.8, 1.0, 0.9, 0.07 * pulse))


func _puff(n: int, ox: float, strength := 1.0) -> void:
	_dust.amount = n
	_dust.initial_velocity_min = 80.0 * strength
	_dust.initial_velocity_max = 240.0 * strength
	_dust.global_position = Vector2(_boss.global_position.x + ox, minf(_boss.ground_y, _boss.global_position.y + 400.0))
	_dust.restart()
	_dust.emitting = true


func _leaf_pop(n: int) -> void:
	if _leaf_burst == null or _boss == null:
		return
	_leaf_burst.amount = maxi(n, 1)
	_leaf_burst.global_position = _boss.body_center()
	_leaf_burst.restart()
	_leaf_burst.emitting = true

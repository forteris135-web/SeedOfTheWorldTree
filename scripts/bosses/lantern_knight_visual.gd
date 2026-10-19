extends Node2D
## 등불 기사의 그림 (2026-10-20 리뉴얼). 기획자의 부위 시트를 잘라 만든 부위 뼈대(PartRig — art/rigs/lantern_knight,
## 설계도 data/rigs/lantern_knight.json)를 움직임 층(RigMotion)으로 움직인다. 자세 값은 data/rigs/_archetypes/knight.json.
## 예전에는 한 장 그림(몸통+창+손 세 겹)을 통째로 기울이고 눌러서 '판때기'처럼 보였다 — 이제 관절로 선다:
##  - 무거운 행진: 디딘 발은 땅에 고정, 두 뼈 다리 IK, 걸음마다 무게가 실리고(엉덩이 들썩·몸 흔들림) 망토가 한 박자 늦게 따라온다.
##  - 공격은 세 박자: 예비(당기며 멈칫) → 타격(허리 → 팔 → 창 순서로 채찍처럼, 끝에서 살짝 지나침) → 되돌림(출렁이며 제자리).
##    진행도는 보스가 공개한 단계 길이(phase_progress)라 2페이즈 배속에도 모양이 같다.
##  - 창은 두 손으로 쥔다: 앞손(뼈대의 무기 팔)이 창의 뒤 손잡이, 뒷손은 IK 로 창의 앞 손잡이를 따라간다 (닿지 않으면 놓는다).
##  - 창에 매단 등불은 진자: 매달린 자리의 가속도로 흔들린다 (휘두르면 크게 돌고, 멈추면 출렁인다).
##  - 쓰러짐: 한 무릎을 꿇고 창에 기댄다 → 떨다가 → 창을 놓치며 앞으로 엎어져 땅에 눕는다 (몸이 땅에 박히거나 뜨지 않는다).
##  - 정화: 무릎 꿇은 채 몸을 일으켜 고개를 든다 — 투구 등불이 하얗게 밝아진다.
## 보스 논리(lantern_knight.gd)는 그대로다 — 그림이 상태·단계·진행도를 읽어 따라간다 (판정·시간은 건드리지 않는다).
##
## 매 프레임 순서:
##  1) 상태 → 목표 자세 (_pose_now)          2) RigMotion.update (섞기·스프링·걸음·다리 IK·망토·땅 닿기)
##  3) _post_solve: 앞손 IK → 창(세상 각도·미끄럼·땅 짚기·땅에 안 박히게) → 뒷손 IK → 등불 진자 → 그림에 반영
##  4) 빛·궤적·잔상·먼지·색
## 좌우: 뼈대는 늘 오른쪽을 본다. 이 노드의 scale.x 가 1 → 0 → −1 을 지나며 몸을 튼다 (뒤집는 순간 딛은 발을 세상에 남긴다).
## 이 노드의 원점 = 보스 발밑 땅 (CharacterBody2D 원점 = 몸 충돌 캡슐의 바닥).

const RIG_ID := "lantern_knight"
## 창 크기: 시트 그림보다 길게 (기사 키의 약 1.5배 — 기획 시트의 조립 그림·예전 그림과 같은 비율). 뼈 배율로 키운다.
const SPEAR_SIZE := 1.6
## 등불 크기 (창 배율을 물려받으므로 등불 뼈 배율 = LANTERN_SIZE / SPEAR_SIZE)
const LANTERN_SIZE := 1.2
## 창 그림 치수 (창 그림 px, 배율 전): 손잡이(뼈 관절) → 창끝 / → 밑동
const SPEAR_TIP := 391.0
const SPEAR_BUTT := 242.0
## 뒷손이 쥐는 자리: 앞손에서 창끝 쪽으로 (창 그림 px)
const GRIP_B := 125.0
## 주먹이 땅 위로 떠 있어야 하는 높이 (뼈대 단위 — 주먹 그림 반지름쯤)
const HAND_GROUND := 34.0
## 등불 뼈 틀에서 등불 몸통 가운데 (빛·궤적 자리)
const LANTERN_CENTER := Vector2(0, 123)
## 투구 등불 창 가운데 (머리 뼈 틀, 시트 px)
const HEAD_LAMP := Vector2(16, -66)
## 등불 진자: 중력(px/s²), 감쇠(1/s), 매달린 자리 가속도 상한·반영 몫 (짧은 사슬이 충격을 조금 먹는다),
## 크게 흔들릴 때 더하는 감쇠(사슬 마찰), 흔들림 한계(라디안 — 보통 동작에서 등불이 창 위로 빙글 돌아 넘어가지 않게; 등불 회전 중엔 없음)
const LANTERN_G := 1900.0
const LANTERN_DAMP := 3.0
const LANTERN_ACC_MAX := 15000.0
const LANTERN_ACC_GAIN := 0.55
const LANTERN_FRICTION := 5.0
const LANTERN_SWING_MAX := 2.3
## 창이 돌 수 있는 가장 빠른 빠르기 (라디안/초): 큰 휘두르기도 한 프레임에 창이 '순간이동'하지 않게 (60fps 에 한 프레임 0.57rad)
const SPEAR_MAX_SPEED := 34.0
## 몸 틀기 빠르기 (1/s)
const TURN_SPEED := 11.0
## 궤적: 이 속도(px/s)보다 빨리 움직일 때만 띠가 보이고, 이만큼 넘으면 가장 진하다
const TRAIL_MIN_SPEED := 900.0
const TRAIL_FULL_SPEED := 3200.0
const TRAIL_LIFE := 0.16
## 쓰러짐 순서 (FALLEN 이 된 뒤 초): 무릎 꿇기 → 창에 기대어 떨기 → 엎어짐 시작 → 다 누움
const FALL_KNEE := 0.45
const FALL_LEAN := 1.5
const FALL_DOWN := 2.15

var boss: LanternKnight
var rig: PartRig
var motion: RigMotion
## 그림 배율 (1 = 설계도 game_scale)
@export var art_scale := 1.0

var _i_torso := -1
var _i_head := -1
var _i_af_up := -1
var _i_af_lo := -1
var _i_ab_up := -1
var _i_ab_lo := -1
var _i_weapon := -1
var _i_lantern := -1
var _k := 0.6              # 뼈대 단위 → 게임 px

var _t := 0.0
var _state_t := 0.0
var _phase_t := 0.0
var _prev_state := -1
var _prev_phase := ""
var _prev_hint := ""
var _prev_combo := -1
var _prev_flash := 0.0
var _from := {}            # 지금 동작이 시작될 때 보이던 자세 (세 박자의 출발)
var _face := -1.0
var _sign := -1.0
var _prev_x := 0.0
var _spin := 0.0           # 등불 회전 누적 각도 (라디안)
var _spin_base := 0.0
var _spear_w := 0.0        # 이번 프레임 창의 세상 각도 (라디안, 뼈대 틀)
var _spear_shown := 0.0    # 빠르기를 제한한 창 각도 (자세 채널을 쫓는다, 값은 이어진다 — 감싸지 않는다)
var _walking := false      # 걸음이 막 시작됐는지 (걸음 위상 맞추기)
var _head_front := false   # 투구 앞모습 그림을 끼웠는가
var _grip_eff := 1.0       # 뒷손이 실제로 쥔 정도 (닿지 않으면 놓는다)
## 창이 손을 떠남 (쓰러짐·정화): 밑동 자리(뼈대 틀)와 기울기·각속도
var _spear_free := false
var _free_butt := Vector2.ZERO
var _free_vy := 0.0
var _free_phi := 0.0       # 0 = 똑바로 섬, +PI/2 = 누움
var _free_w := 0.0
var _free_dir := 1.0
## 박힌 창: 창 손잡이 자리·각도를 세상(뼈대 틀)에 고정하고 손이 따라간다
var _anchor := 0.0
var _anchor_pos := Vector2.ZERO
var _anchor_w := 0.0
## 등불 진자 (화면 기준: 0 = 똑바로 아래, + = 화면 오른쪽으로)
var _lan_th := 0.0
var _lan_w := 0.0
var _lan_prev := Vector2.INF
var _lan_vel := Vector2.ZERO
var _lan_alpha := 1.0      # 던진 뒤 다시 켜지는 등불 (0 = 없음)
var _lan_flash := 0.0
var _red := 0.0
var _glow := 1.0           # 투구 등불 밝기
var _settle := 0.0
var _lock := 0.0
## 망토(늘어진 천 사슬)의 원래 중력·흔들림 한계 — 엎어져 누우면 망토가 등 위로 솟지 않고 땅 쪽으로 늘어지게 바꾼다
var _cape_chain: Array = []
var _cape_gravity := 0.15
var _cape_max := 0.5
## 호환: 예전 시험(probe_bosses / probe_knight_fix)이 읽는 값 — 창 손잡이 자리·각도를 따라가는 노드, 수평 맞춤(이제 늘 0)
var _weapon_bone: Node2D
var _level := 0.0

var _dust: CPUParticles2D
var _embers: CPUParticles2D
var _head_glow: Sprite2D
var _lan_glow: Sprite2D
var _light: PointLight2D
var _light_pos := Vector2.ZERO
var _trail: Node2D
var _trail_pts: Array = []
var _prev_tip := Vector2.ZERO
var _prev_lantern := Vector2.ZERO
var _tip_speed := 0.0
var _lantern_speed := 0.0
var _trail_dirty := false
var _ghost_timer := 0.0

static var _glow_tex: Texture2D


func _ready() -> void:
	boss = get_parent() as LanternKnight
	rig = PartRig.new()
	rig.name = "Rig"
	add_child(rig)
	if not rig.build(RIG_ID):
		push_error("등불 기사 뼈대를 만들지 못했다")
		set_process(false)
		return
	_k = rig.game_scale * art_scale
	rig.scale = Vector2(art_scale, art_scale)
	_i_torso = rig.bone_index("torso")
	_i_head = rig.bone_index("head")
	_i_af_up = rig.bone_index("arm_f_up")
	_i_af_lo = rig.bone_index("arm_f_lo")
	_i_ab_up = rig.bone_index("arm_b_up")
	_i_ab_lo = rig.bone_index("arm_b_lo")
	_i_weapon = rig.bone_index("weapon")
	_i_lantern = rig.bone_index("lantern")
	rig.scl[_i_weapon] = Vector2(SPEAR_SIZE, SPEAR_SIZE)
	rig.scl[_i_lantern] = Vector2.ONE * (LANTERN_SIZE / SPEAR_SIZE)
	motion = RigMotion.new(rig)
	for c in motion._chains:
		if rig.names[int(c[0])] == "cape":
			_cape_chain = c
			_cape_gravity = float(c[4])
			_cape_max = float(c[5])
	rig.setup_ghosts(["torso", "arm_f_up", "arm_f_lo", "weapon", "lantern"], 6)
	if boss:
		_face = float(boss.facing)
		_sign = signf(_face)
		_prev_x = boss.global_position.x
		_light = boss.get_node_or_null("Light") as PointLight2D
	scale = Vector2(_face, 1.0)
	_weapon_bone = Node2D.new()
	_weapon_bone.name = "WeaponBone"
	add_child(_weapon_bone)
	_make_effects()
	_spear_w = deg_to_rad(float(motion.fin.get("spear", -128.0)))
	_spear_shown = _spear_w


func _make_effects() -> void:
	if _glow_tex == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.08), Color(1, 1, 1, 0)])
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 64
		gt.height = 64
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		_glow_tex = gt
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	# 투구 등불·창 등불의 은은한 빛 (HDR 1 넘김 → 글로우가 번진다)
	_head_glow = Sprite2D.new()
	_head_glow.texture = _glow_tex
	_head_glow.material = add
	_head_glow.scale = Vector2(1.5, 1.5)
	rig.attach("head", _head_glow, HEAD_LAMP)
	_lan_glow = Sprite2D.new()
	_lan_glow.texture = _glow_tex
	_lan_glow.material = add
	_lan_glow.scale = Vector2(1.7, 1.7)
	rig.attach("lantern", _lan_glow, LANTERN_CENTER)
	# 궤적 (몸의 배율·좌우를 따르지 않게 top_level, 몸 위에 그린다)
	_trail = Node2D.new()
	_trail.top_level = true
	_trail.z_index = 2
	var add2 := CanvasItemMaterial.new()
	add2.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail.material = add2
	_trail.draw.connect(_draw_trail)
	add_child(_trail)
	# 발 먼지·내려찍기 먼지 (top_level)
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
	_dust.color = Color(0.7, 0.66, 0.58, 0.5)
	_dust.texture = _glow_tex   # 둥글고 부드러운 먼지 (텍스처가 없으면 네모 점으로 찍힌다)
	_dust.scale_amount_min = 0.25
	_dust.scale_amount_max = 0.55
	add_child(_dust)
	# 불씨 (등불이 땅을 칠 때·던질 때·박힐 때)
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
	_embers.color = Color(1.0, 0.62, 0.25, 0.9)
	_embers.texture = _glow_tex
	_embers.scale_amount_min = 0.1
	_embers.scale_amount_max = 0.22
	var add3 := CanvasItemMaterial.new()
	add3.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_embers.material = add3
	add_child(_embers)


# ---------- 매 프레임 ----------

func _process(delta: float) -> void:
	if boss == null or motion == null:
		return
	delta = minf(delta, 0.05)
	_t += delta
	_state_t += delta
	_phase_t += delta
	var st := boss.state
	_events(st)
	# 몸 틀기: 1 → 0 → −1 (뒤집는 순간 딛은 발·등불을 세상에 남긴다)
	_face = Motion.damp(_face, float(boss.facing), TURN_SPEED, delta)
	var fx := _face
	if absf(fx) < 0.03:
		fx = 0.03 * (1.0 if fx >= 0.0 else -1.0)
	var s := signf(fx)
	if s != _sign:
		_sign = s
		motion.flip_feet()
		_lan_th = -_lan_th
		_lan_w = -_lan_w
		_lan_prev = Vector2.INF
	scale = Vector2(fx, 1.0)
	# 몸을 트는 한가운데(옆모습이 납작해질 때)엔 투구를 앞모습 그림으로 바꿔 끼운다 (시트의 정면 투구) — 판때기가 뒤집히는 대신 돌아서는 것처럼
	var front := absf(fx) < 0.45
	if front != _head_front:
		_head_front = front
		rig.set_variant("head", "front" if front else "")
	# 목표 자세
	var info := {"drive": RigMotion.Drive.NORMAL, "feet": RigMotion.Feet.POSE, "breath": 1.0}
	var pose := _pose_now(st, delta, info)
	motion.breath = float(info["breath"])
	motion.set_target(pose, info["drive"], info["feet"])
	# 몸이 간 거리 (뼈대 단위, 보는 쪽 + 앞)
	var dxw := boss.global_position.x - _prev_x
	_prev_x = boss.global_position.x
	# 돌진(초속 1250px)은 다리가 따라갈 수 없는 빠르기라 걸음에는 줄여서 준다 (발이 조금 미끄러지는 대신 다리가 닿지 않아
	# 엉덩이가 툭툭 떨어지지 않게 — 빠른 돌진이라 미끄러짐은 거의 안 보인다)
	var gait_k := 0.5 if st == LanternKnight.State.CHARGE and boss.attack_phase == "active" else 1.0
	var ctx := {
		"speed": boss.velocity.x * _sign / _k * gait_k,
		"dx": dxw * _sign / _k * gait_k,
		"vy": boss.velocity.y / _k,
		"grounded": boss.is_on_floor() or st == LanternKnight.State.WAIT,
	}
	# 땅 닿기: 눕거나 무너진 상태 (몸이 땅에 묻히지 않게 받친다). 서서 한 무릎을 꿇은 자세(깨어남)는 디딘 발이 들리지 않게 빼 둔다
	var kneeling := st in [LanternKnight.State.FALLEN, LanternKnight.State.PURIFIED, LanternKnight.State.BROKEN]
	_lock = Motion.damp(_lock, 1.0 if kneeling else 0.0, 6.0, delta)
	var settle_want := 0.0
	if st == LanternKnight.State.FALLEN:
		settle_want = clampf((_state_t - FALL_LEAN) / (FALL_DOWN - FALL_LEAN), 0.0, 1.0)
	_settle = Motion.damp(_settle, settle_want, 5.0, delta)
	motion.ground_lock = _lock
	motion.ground_settle = _settle
	if not _cape_chain.is_empty():
		_cape_chain[4] = lerpf(_cape_gravity, 0.9, _settle)
		_cape_chain[5] = lerpf(_cape_max, 2.6, _settle)
	_sync_gait(st, absf(float(ctx["speed"])))
	motion.update(delta, ctx)
	_post_solve(delta)
	_after(delta, st)


## 걸음이 막 시작될 때 걸음 위상을 맞춘다: 가는 쪽 기준 가장 뒤에 있는 발부터 내딛게.
## (위상이 아무 데서나 시작하면 뒤에 디딘 발이 한참 끌려가다 다리가 닿지 않아 엉덩이가 '툭' 내려앉았다 — 돌진·행진 시작)
func _sync_gait(st: LanternKnight.State, speed: float) -> void:
	var walk := speed > RigMotion.GAIT_MIN_SPEED * motion.L * 1.2 and (st == LanternKnight.State.MARCH or (st == LanternKnight.State.CHARGE and boss.attack_phase == "active"))
	if walk and not _walking and motion.legs.size() >= 2:
		# 가는 쪽: 돌진은 늘 앞 (단계가 바뀌는 그 프레임엔 아직 뒤로 물러나던 속도가 남아 있다), 행진은 속도 쪽
		var dir := 1.0 if st == LanternKnight.State.CHARGE else (1.0 if boss.velocity.x * _sign >= 0.0 else -1.0)
		var back := 0 if motion.legs[0].x * dir < motion.legs[1].x * dir else 1
		# 다리 k 의 위상 = _phase + (홀수면 0.5): 뒤 발의 위상을 0(내딛기 시작)에
		motion._phase = 0.5 if back == 1 else 0.0
		for leg in motion.legs:
			leg.swing = false
	_walking = walk


## 일회성 사건: 상태·단계·힌트·피격이 바뀐 순간
func _events(st: LanternKnight.State) -> void:
	var ph := boss.attack_phase
	if int(st) != _prev_state:
		_on_state(st)
		_prev_state = st
		_state_t = 0.0
	if ph != _prev_phase:
		_on_phase(st, ph)
		_prev_phase = ph
		_phase_t = 0.0
	if st == LanternKnight.State.COMBO3 and boss.combo_step != _prev_combo:
		if _prev_combo >= 0:
			_from = motion.capture()   # 다음 타의 예비는 지금 자세에서 이어진다
		_prev_combo = boss.combo_step
	elif st != LanternKnight.State.COMBO3:
		_prev_combo = -1
	if boss.anim_hint == "stagger" and _prev_hint != "stagger" and st in [LanternKnight.State.THRUST, LanternKnight.State.COMBO3, LanternKnight.State.CHARGE]:
		# 저스트 가드로 창이 튕김: 지나가던 창·손을 되튕기고 몸이 젖혀진다
		motion.scale_velocity(motion.parry_bounce, -0.5)
		motion.kick("parry", 260.0)
		motion.kick("impact", 140.0)
		_from = motion.capture()
		_spark_at(_tip_global())
	_prev_hint = boss.anim_hint
	var fl := boss.flash_amount()
	if fl > _prev_flash + 0.4 and st not in [LanternKnight.State.BROKEN, LanternKnight.State.FALLEN, LanternKnight.State.STAGGER, LanternKnight.State.PURIFIED]:
		motion.kick("impact", 70.0)
	_prev_flash = fl


func _on_state(st: LanternKnight.State) -> void:
	var was := _prev_state
	_from = motion.capture()
	match st:
		LanternKnight.State.MARCH:
			motion.transition(0.12)
		LanternKnight.State.STAGGER:
			motion.kick("impact", 160.0)
			motion.transition(0.06)
		LanternKnight.State.BROKEN:
			motion.kick("crouch", 1.2)
			motion.transition(0.1)
			_puff(10, 0.0)
		LanternKnight.State.FALLEN:
			motion.transition(0.08)
			motion.kick("crouch", 1.4)
			_puff(16, 0.0)
		LanternKnight.State.PURIFIED:
			motion.transition(0.2)
			_release_spear()
		LanternKnight.State.STUCK:
			# 창이 벽에 박혔다: 창 손잡이를 지금 자리에 고정하고 몸이 앞으로 쏠리며 튕긴다
			_anchor = 1.0
			_anchor_pos = rig.xf[_i_weapon].origin
			_anchor_w = _spear_w
			motion.kick("impact", -120.0)
			motion.kick("crouch", 0.8)
			_puff(14, float(boss.facing) * 70.0)
			_spark_at(_tip_global())
		LanternKnight.State.INTRO:
			_spear_free = false
			_lan_alpha = 1.0
			_glow = 0.0
	if st != LanternKnight.State.STUCK:
		_anchor = 0.0
	if st == LanternKnight.State.SPIN:
		_spin = 0.0
		_spin_base = _spear_w
	elif was == LanternKnight.State.SPIN:
		# 세 바퀴를 돈 각도를 접는다 (2π 의 배수라 그림은 그대로 — 빠르기 제한이 거꾸로 세 바퀴를 되감지 않게)
		_spear_shown -= TAU * roundf((_spear_shown - _spin_base) / TAU)
		_spin = 0.0
	if st in [LanternKnight.State.WAIT, LanternKnight.State.INTRO, LanternKnight.State.MARCH]:
		_spear_free = false


func _on_phase(st: LanternKnight.State, ph: String) -> void:
	if ph == "recovery":
		_from = motion.capture()
	if ph == "startup" and st != LanternKnight.State.COMBO3:
		_from = motion.capture()
	if ph != "active":
		return
	var f := float(boss.facing)
	match st:
		LanternKnight.State.SLAM:
			motion.kick("crouch", 2.0)
			motion.kick("thud", 40.0)
			_puff(22, f * 120.0)
			_spark_at(_tip_global())
		LanternKnight.State.THRUST:
			_puff(6, -f * 40.0)
		LanternKnight.State.FLAME:
			motion.kick("crouch", 0.6)
		LanternKnight.State.WAVE:
			_puff(10, -f * 30.0)
		LanternKnight.State.CHARGE:
			_puff(12, f * 50.0)
		LanternKnight.State.THROW:
			# 등불을 던졌다: 창에 매달린 등불이 사라지고(던진 투사체가 된다) 되돌림 동안 새 불이 켜진다
			_spark_at(_lantern_global())
			_lan_alpha = 0.0
		LanternKnight.State.SPIN:
			_spark_at(_lantern_global())
		LanternKnight.State.COMBO3:
			if boss.combo_step == 2:
				motion.kick("crouch", -0.8)
				_puff(10, 0.0)
			else:
				_puff(5, -f * 30.0)


# ---------- 자세 고르기 ----------

## 지금 상태의 목표 자세. info 에 보간 방식·발 방식·숨쉬기를 적는다.
func _pose_now(st: LanternKnight.State, delta: float, info: Dictionary) -> Dictionary:
	var ph := boss.attack_phase
	var p := boss.phase_progress()
	var beat := "windup" if ph == "startup" else ("strike" if ph == "active" else "recover")
	match ph:
		"startup": info["drive"] = RigMotion.Drive.NORMAL
		"active": info["drive"] = RigMotion.Drive.FAST
		"recovery": info["drive"] = RigMotion.Drive.SETTLE
	info["breath"] = 0.3
	var stance := _stance(false)
	match st:
		LanternKnight.State.WAIT:
			info["breath"] = 0.0
			return motion.pose("intro_kneel")
		LanternKnight.State.INTRO:
			# 깨어남: 창에 기대 꿇은 채 → 투구 등불이 켜지며 일어선다 → 자리 잡기
			info["drive"] = RigMotion.Drive.SOFT
			info["breath"] = 0.6
			_glow = Motion.damp(_glow, 1.0 if _state_t > 0.8 else 0.0, 5.0, delta)
			return motion.sample_clip([[0.0, "intro_kneel"], [0.75, "intro_kneel", "hold"], [1.0, "intro_crouch", "out"], [1.8, stance], [2.4, stance]], _state_t)
		LanternKnight.State.MARCH:
			info["feet"] = RigMotion.Feet.GAIT
			info["breath"] = 0.7
			return _stance(true)
		LanternKnight.State.THRUST:
			if boss.anim_hint == "stagger":
				return _parried(p, stance, info)
			if ph == "recovery":
				# 찌른 뒤엔 곧장 거둬들인다 (무거운 허리가 관성으로 되돌림까지 더 숙여 들어가지 않게 — 타격 정점이 판정 구간 안에)
				info["drive"] = RigMotion.Drive.QUICK
				return motion.mix(motion.pose("thrust_h"), stance, Motion.settle(p, 1.5, 3.0))
			if ph == "active":
				# 찌르기는 타격 구간 앞 50% 안에 다 뻗는다 (판정이 켜진 동안 창이 다 나가 있게) — 나머지는 뻗은 채 버틴다
				# 뒤 50% 는 팔을 뻗은 채 몸만 조금 되받쳐 세운다 (허리 정점이 판정 구간 가운데에 온다)
				if p > 0.5:
					return motion.mix(motion.pose("thrust_s"), motion.pose("thrust_h"), Motion.ease_in_out((p - 0.5) / 0.5))
				return motion.three_beat(_from, motion.pose("thrust_w"), motion.pose("thrust_s"), stance, beat, p / 0.5, 0.2)
			return motion.three_beat(_from, motion.pose("thrust_w"), motion.pose("thrust_s"), stance, beat, p, 0.2)
		LanternKnight.State.FLAME:
			return motion.three_beat(_from, motion.pose("flame_w"), motion.pose("flame_s"), stance, beat, p, 0.05)
		LanternKnight.State.SLAM:
			return _slam_pose(ph, p, stance, info)
		LanternKnight.State.THROW:
			return motion.three_beat(_from, motion.pose("throw_w"), motion.pose("throw_s"), stance, beat, p, 0.16)
		LanternKnight.State.WAVE:
			return motion.three_beat(_from, motion.pose("wave_w"), motion.pose("wave_s"), stance, beat, p, 0.12)
		LanternKnight.State.COMBO3:
			if boss.anim_hint == "stagger":
				return _parried(p, stance, info)
			var s := boss.combo_step
			var names: Array = [["thrust_w", "thrust_s"], ["cut_w", "cut_s"], ["upper_w", "upper_s"]][s]
			var w := motion.pose(names[0])
			var k := motion.pose(names[1])
			# 앞 두 타의 되돌림은 아주 짧고 곧 다음 타의 예비가 이어진다 — 타격 자세에 머문다
			var to := stance if s == 2 else k
			return motion.three_beat(_from, w, k, to, beat, p, 0.18)
		LanternKnight.State.CHARGE:
			if boss.anim_hint == "stagger":
				return _parried(p, stance, info)
			match ph:
				"startup":
					var cw := motion.three_beat(_from, motion.pose("charge_w"), motion.pose("charge_s"), stance, "windup", p)
					# 끝자락에 떨림 (힘을 모은다)
					var tr := clampf((p - 0.5) / 0.5, 0.0, 1.0)
					cw["torso"] = float(cw["torso"]) + sin(_t * 44.0) * 1.6 * tr
					cw["hand_x"] = float(cw["hand_x"]) + sin(_t * 44.0) * 4.0 * tr
					return cw
				"active":
					info["drive"] = RigMotion.Drive.QUICK
					info["feet"] = RigMotion.Feet.GAIT
					return motion.pose("charge_s")
			return motion.three_beat(_from, motion.pose("charge_w"), motion.pose("charge_s"), stance, "recover", p)
		LanternKnight.State.STUCK:
			# 박힌 창을 뽑으려 당긴다 (몸이 들썩인다). 마지막엔 뽑히며 뒤로 휘청
			var kk := boss.state_progress(boss.stuck_len)
			var tug := absf(sin(_t * 9.0))
			var sp := motion.pose("stuck").duplicate()
			sp["torso"] = float(sp["torso"]) - tug * 9.0
			sp["hip_x"] = float(sp["hip_x"]) - tug * 0.05
			sp["lean"] = float(sp["lean"]) - tug * 3.0
			info["drive"] = RigMotion.Drive.QUICK
			if kk > 0.85:
				var out := (kk - 0.85) / 0.15
				_anchor = 1.0 - Motion.ease_in_out(out)
				return motion.mix(sp, motion.pose("stagger"), Motion.ease_out(out))
			return sp
		LanternKnight.State.SPIN:
			return _spin_pose(ph, p, stance, info)
		LanternKnight.State.STAGGER:
			# 갑옷이 폭주하며 휘청 (2페이즈 전환): 뒤로 젖혔다 출렁이며 돌아온다
			var k2 := boss.state_progress(boss.stagger_len)
			info["drive"] = RigMotion.Drive.QUICK
			_glow = 1.6
			return motion.mix(motion.pose("stagger"), _stance(false), Motion.settle(k2, 1.5, 3.0))
		LanternKnight.State.BROKEN:
			info["drive"] = RigMotion.Drive.HEAVY
			info["breath"] = 2.6
			_glow = Motion.damp(_glow, 0.45 + 0.25 * absf(sin(_t * 7.0)), 8.0, delta)
			var bp := motion.pose("broken").duplicate()
			bp["torso"] = float(bp["torso"]) + sin(_t * 23.0) * 0.8
			return bp
		LanternKnight.State.FALLEN:
			return _fallen_pose(delta, info)
		LanternKnight.State.PURIFIED:
			info["drive"] = RigMotion.Drive.SLOW
			info["breath"] = 0.5
			_glow = Motion.damp(_glow, 1.5, 3.0, delta)
			return motion.pose("purified")
	return stance


## 행진·대기 자세 (2페이즈는 더 낮고 앞으로 숙여 창을 앞으로 겨눈다). walking = 걸음 흔들림·무게 실림을 더한다
func _stance(walking: bool) -> Dictionary:
	var p2 := boss.phase == 2
	var idle := motion.pose("idle_p2" if p2 else "idle")
	if not walking:
		return idle
	var spd := clampf(absf(boss.velocity.x) / maxf(boss.march_speed, 1.0), 0.0, 1.0)
	var out := motion.mix(idle, motion.pose("walk_p2" if p2 else "walk"), spd)
	# 걸음마다 무게가 실린다: 몸이 앞뒤로 조금 흔들리고 머리는 반대로 (걸음 위상은 걸은 거리 기준이라 멈추면 멈춘다)
	var ph := motion._phase * TAU * 2.0
	out["torso"] = float(out["torso"]) + sin(ph) * 2.2 * spd
	out["head"] = float(out["head"]) - sin(ph) * 1.6 * spd
	out["spear"] = float(out["spear"]) + sin(ph + 0.6) * 3.0 * spd
	out["hand_y"] = float(out["hand_y"]) + cos(ph) * 4.0 * spd
	return out


func _parried(p: float, stance: Dictionary, info: Dictionary) -> Dictionary:
	info["drive"] = RigMotion.Drive.QUICK
	if boss.attack_phase != "recovery":
		return motion.pose("parried")
	return motion.mix(motion.pose("parried"), stance, Motion.settle(p, 2.0, 3.5))


## 내려찍기: 웅크림(예비 앞 30%) → 도약(몸이 실제로 뛴다 — 창을 머리 위 뒤로 두 손으로 치켜든다) →
## 착지와 함께 머리 위로 넘겨 앞 땅을 내리친다(무릎이 깊이 꺾인다) → 되돌림
func _slam_pose(ph: String, p: float, stance: Dictionary, info: Dictionary) -> Dictionary:
	var crouch := motion.pose("slam_crouch")
	var air := motion.pose("slam_air")
	match ph:
		"startup":
			if p < 0.3:
				return motion.mix(_from, crouch, Motion.ease_out(p / 0.3))
			if not boss.is_on_floor():
				info["feet"] = RigMotion.Feet.AIR
			# 발끝으로 솟으며 창을 머리 위 뒤로 (끝자락에 떨림 — 붉은 예고)
			var up := motion.mix(crouch, air, Motion.anticipation((p - 0.3) / 0.7))
			var tr := clampf((p - 0.7) / 0.3, 0.0, 1.0)
			up["spear"] = float(up["spear"]) + sin(_t * 40.0) * 2.0 * tr
			return up
		"active":
			return motion.three_beat(_from, air, motion.pose("slam_s"), stance, "strike", p, 0.1)
	return motion.three_beat(_from, air, motion.pose("slam_s"), motion.mix(motion.pose("slam_r"), stance, p), "recover", p)


## 등불 회전: 창을 머리 위로 들고 손을 자루 가운데로 미끄러뜨려 빙글 돌린다 (예비 1바퀴 → 타격 2바퀴 → 멈춤).
## 회전 각도는 자세 채널이 아니라 누적기(_spin)로 — 세 바퀴를 정확히 돈다.
func _spin_pose(ph: String, p: float, stance: Dictionary, info: Dictionary) -> Dictionary:
	var up := motion.pose("spin_up")
	match ph:
		"startup":
			# 먼저 창을 머리 위로 들고(앞 40%) 손을 자루 가운데로 미끄러뜨린 뒤 돌리기 시작한다 (낮을 때 돌리면 창끝이 땅을 긁는다)
			_spin = TAU * Motion.ease_in(clampf((p - 0.3) / 0.7, 0.0, 1.0), 2.0)
			return motion.mix(_from, up, Motion.ease_out(minf(p / 0.4, 1.0)))
		"active":
			_spin = TAU + 2.0 * TAU * p
			info["drive"] = RigMotion.Drive.NORMAL
			var a := up.duplicate()
			a["torso"] = float(a["torso"]) + sin(_t * 30.0) * 1.5
			return a
	_spin = 3.0 * TAU
	return motion.mix(up, stance, Motion.settle(p))


## 쓰러짐: 무릎이 꺾여 한 무릎을 꿇고 창을 땅에 짚어 기댄다 → 떨며 고개가 처진다 → 창을 놓치고 앞으로 엎어져 눕는다.
## 다 누운 뒤에는 정화할 때까지 그대로 (숨도 멎는다). 몸은 땅 닿기(ground_lock)·내려놓기(ground_settle)로 땅 위에.
func _fallen_pose(delta: float, info: Dictionary) -> Dictionary:
	var t := _state_t
	info["breath"] = 0.0 if t > FALL_LEAN else 1.4
	_glow = Motion.damp(_glow, 0.12 if t > FALL_LEAN else 0.5, 2.5, delta)
	if t < FALL_KNEE:
		info["drive"] = RigMotion.Drive.HEAVY
		return motion.mix(_from, motion.pose("fall_knee"), Motion.ease_out(t / FALL_KNEE, 2.0))
	if t < FALL_LEAN:
		info["drive"] = RigMotion.Drive.SOFT
		var lp := motion.mix(motion.pose("fall_knee"), motion.pose("fall_lean"), Motion.ease_in_out((t - FALL_KNEE) / (FALL_LEAN - FALL_KNEE)))
		lp["torso"] = float(lp["torso"]) + sin(_t * 26.0) * 0.9   # 떨림
		return lp
	if not _spear_free:
		_release_spear()
	# 엎어짐은 넘치지 않는 스프링으로 (무릎 꿇기 채널이 넘쳐 앞·뒤 다리 중 축이 되는 무릎이 바뀌면 몸이 한 프레임에 튄다)
	info["drive"] = RigMotion.Drive.SOFT
	return motion.mix(motion.pose("fall_lean"), motion.pose("fall_lie"), Motion.ease_in(clampf((t - FALL_LEAN) / (FALL_DOWN - FALL_LEAN), 0.0, 1.0), 1.6))


# ---------- 손·창·등불 ----------

## RigMotion 이 몸·다리를 푼 뒤: 앞손 IK → 창 → 땅 막기 → 뒷손 IK → 등불 진자 → 그림에 반영
func _post_solve(delta: float) -> void:
	var f := motion.fin
	var tor := rig.xf[_i_torso]
	var slide := float(f.get("slide", 0.0))
	# 창의 세상 각도 (등불 회전은 누적기를 더한다)
	var sw := deg_to_rad(float(f.get("spear", -128.0)))
	if boss.state == LanternKnight.State.SPIN:
		sw = _spin_base + _spin
	if delta > 0.0:
		_spear_shown = move_toward(_spear_shown, sw, SPEAR_MAX_SPEED * delta)
	else:
		_spear_shown = sw
	sw = _spear_shown
	_spear_w = sw
	var dir := Vector2(0, 1).rotated(sw)
	# 1) 앞손: 몸통 틀의 손 자리 (+ 맞았을 때 손이 뒤로 흔들림) / 땅 짚기 / 박힌 창
	var imp := motion.spring_value("impact")
	var hand := tor * Vector2(float(f.get("hand_x", 60.0)) - imp * 0.8, float(f.get("hand_y", 18.0)) - imp * 0.4)
	var plant := clampf(float(f.get("plant", 0.0)), 0.0, 1.0)
	if plant > 0.001:
		var butt := Vector2(float(f.get("plant_x", 160.0)), -3.0)
		hand = hand.lerp(butt + dir * (SPEAR_BUTT - slide) * SPEAR_SIZE, plant)
	if _anchor > 0.001:
		sw = lerp_angle(sw, _anchor_w, _anchor)
		_spear_w = sw
		dir = Vector2(0, 1).rotated(sw)
		hand = hand.lerp(_anchor_pos - dir * slide * SPEAR_SIZE, _anchor)
	if _spear_free:
		_update_free_spear(delta)
	hand.y = minf(hand.y, -HAND_GROUND)   # 주먹이 땅 아래로 가지 않게 (엎어져 팔을 뻗을 때)
	_solve_arm(_i_af_up, _i_af_lo, hand, 1.0)
	if _lock > 0.5:
		_lift_bone(_i_af_lo, 3.0, 1.2)
	# 2) 창: 앞손(아래팔 축 끝)에 붙어 세상 각도로 선다. 손을 떠났으면 세상 자리 그대로.
	if _spear_free:
		_place_free_spear()
	else:
		var rl := sw - rig.world_rot(_i_af_lo)
		rig.rot[_i_weapon] = rl
		rig.off[_i_weapon] = Vector2(0, 1).rotated(rl) * slide * SPEAR_SIZE
		rig.compute_from(_i_weapon)
		# 3) 땅에 박히지 않게 (회전 중·박힘·짚기는 뺀다 — 짚기는 밑동이 땅에 닿는 것이 맞다)
		if boss.state != LanternKnight.State.SPIN and _anchor < 0.5 and plant < 0.5:
			# 들어 올린 만큼 '보이는 각도'에도 넣는다 → 다음 프레임은 땅에 닿은 자리에서 이어서 움직인다 (튀지 않고 땅을 따라 미끄러진다)
			var lifted := _lift_bone(_i_weapon, 4.0, 0.12)
			_spear_w += lifted
			_spear_shown += lifted
	# 4) 뒷손: 창의 앞 손잡이로 (닿지 않으면 놓는다) — 놓으면 자세의 뒷손 자리
	var grip := 0.0 if _spear_free else clampf(float(f.get("grip_b", 1.0)), 0.0, 1.0)
	var free_b := tor * Vector2(float(f.get("hand_bx", 40.0)), float(f.get("hand_by", -30.0)))
	var gp := rig.xf[_i_weapon] * Vector2(0, GRIP_B)
	var reach := rig.base_pos[_i_ab_lo].length() + rig.bone_len[_i_ab_lo]
	var dist := (gp - rig.xf[_i_ab_up].origin).length()
	var can := clampf((reach * 1.06 - dist) / (reach * 0.1), 0.0, 1.0)
	_grip_eff = Motion.damp(_grip_eff, grip * can, 16.0, delta)
	var tb := free_b.lerp(gp, _grip_eff)
	tb.y = minf(tb.y, -HAND_GROUND)
	_solve_arm(_i_ab_up, _i_ab_lo, tb, 1.0)
	if _lock > 0.5:
		_lift_bone(_i_ab_lo, 3.0, 1.2)
	# 5) 등불 진자
	_update_lantern(delta)
	# 6) 무릎 꿇은 다리의 발끝이 땅에 묻히지 않게 발목 둘레로 세운다 (뼈대 층의 발끝 각도 찾기가 0.05rad 간격이라 긴 장화 끝이
	#    몇 프레임마다 5px 쯤 묻혔다 깜빡였다)
	for leg in motion.legs:
		if float(motion.fin.get(leg.k_kneel, 0.0)) > 0.5:
			_lift_bone(leg.foot, 0.5, 0.6)
	rig.apply()


## 두 뼈 팔 IK: 위팔 관절에서 target(뼈대 틀)으로 아래팔 축 끝(주먹)을 보낸다. 팔꿈치는 늘 같은 쪽(뒤·아래)으로 굽는다.
## (닿지 않으면 팔을 쭉 뻗어 그쪽을 가리킨다.) w = 원래 회전과 섞는 정도.
func _solve_arm(up: int, lo: int, target: Vector2, w: float) -> void:
	var s := rig.xf[up].origin
	var a := rig.base_pos[lo].length()
	var b := rig.bone_len[lo]
	var d := target - s
	var dist := clampf(d.length(), absf(a - b) + 1.0, a + b - 0.5)
	var cos_al := (a * a + dist * dist - b * b) / (2.0 * a * dist)
	var al := acos(clampf(cos_al, -1.0, 1.0))
	var base := d.angle()
	var th1 := base + al
	var elbow := s + Vector2.from_angle(th1) * a
	var hand := s + Vector2.from_angle(base) * dist
	var th2 := (hand - elbow).angle()
	var pw := rig.world_rot(rig.parent[up])
	var r_up := th1 - PI * 0.5 - pw
	var r_lo := th2 - th1
	rig.rot[up] = lerp_angle(rig.rot[up], r_up, w)
	rig.rot[lo] = lerp_angle(rig.rot[lo], r_lo, w)
	rig.compute_from(up)


## 뼈를 관절 둘레로 돌려 껍질의 가장 낮은 점을 땅 위(−margin)로 올린다. 돌린 각도(라디안)를 돌려준다 (안 돌렸으면 0).
func _lift_bone(i: int, margin: float, max_rot: float) -> float:
	var bx := rig.body_xf
	var moved := 0.0
	for iter in 2:
		var t := bx * rig.xf[i]
		var low := -INF
		var q := Vector2.ZERO
		for h in rig.hulls[i]:
			var pt := t * h
			if pt.y > low:
				low = pt.y
				q = pt
		if low <= -margin:
			return moved
		var o := t.origin
		var rr := (q - o).length()
		if rr < 1.0 or o.y > -margin:
			return moved
		var want := clampf((-margin - o.y) / rr, -1.0, 1.0)
		var cur := (q - o).angle()
		var s1 := asin(want)
		var d1 := wrapf(s1 - cur, -PI, PI)
		var d2 := wrapf(PI - s1 - cur, -PI, PI)
		var dd := clampf(d1 if absf(d1) <= absf(d2) else d2, -max_rot, max_rot)
		rig.rot[i] += dd
		rig.compute_from(i)
		moved += dd
	return moved


## 창이 손을 떠난다 (쓰러짐에서 놓침, 정화): 지금 밑동 자리에서 앞으로 쓰러지는 막대가 된다.
func _release_spear() -> void:
	if _spear_free:
		return
	_spear_free = true
	var t := rig.xf[_i_weapon]
	_free_butt = t * Vector2(0, -SPEAR_BUTT)
	_free_vy = 0.0
	# 기울기: 창끝이 앞(+x)으로 기운 만큼 (똑바로 섰으면 앞으로 살짝 밀어 넘어지게)
	var up := (t * Vector2(0, SPEAR_TIP) - _free_butt).normalized()
	var tilt := atan2(up.x, -up.y)
	_free_dir = 1.0 if tilt >= -0.05 else -1.0
	_free_phi = absf(tilt)
	_free_w = 0.6


## 손을 떠난 창: 밑동이 땅에 닿을 때까지 떨어지고, 밑동을 축으로 쓰러져(뒤집힌 진자) 땅에 눕는다 — 작게 튕긴 뒤 멈춘다.
func _update_free_spear(delta: float) -> void:
	if delta <= 0.0:
		return
	var len := (SPEAR_TIP + SPEAR_BUTT) * SPEAR_SIZE * _k
	if _free_butt.y < -2.0:
		_free_vy += 2600.0 * delta
		_free_butt.y = minf(_free_butt.y + _free_vy * delta / _k, -2.0)
	var lie := PI * 0.5
	if _free_phi < lie or absf(_free_w) > 0.0:
		_free_w += 1.5 * 2600.0 / len * sin(maxf(_free_phi, 0.02)) * delta
		_free_phi += _free_w * delta
		if _free_phi >= lie:
			_free_phi = lie
			_free_w = -_free_w * 0.22
			if absf(_free_w) < 0.4:
				_free_w = 0.0
			else:
				_puff(8, float(boss.facing) * _free_dir * (len * 0.6))
	# 세상 각도: φ 0 = 창끝 위(−180°), 앞으로 누우면 −90°
	_spear_w = -PI + _free_phi * _free_dir


func _place_free_spear() -> void:
	var dir := Vector2(0, 1).rotated(_spear_w)
	var origin := _free_butt + dir * SPEAR_BUTT * SPEAR_SIZE
	var par := rig.xf[_i_af_lo]
	var local := par.affine_inverse() * origin
	rig.rot[_i_weapon] = _spear_w - rig.world_rot(_i_af_lo)
	rig.off[_i_weapon] = local - rig.base_pos[_i_weapon]
	rig.compute_from(_i_weapon)
	# 누운 만큼 껍질의 가장 낮은 점을 땅에 (창 그림은 축 둘레로 두께가 있다 — 축만 땅에 대면 한쪽이 떠 보인다)
	if _free_phi > 0.6:
		var low := rig.lowest_y(PackedInt32Array([_i_weapon]))
		var k := clampf((_free_phi - 0.6) / 0.6, 0.0, 1.0)
		rig.off[_i_weapon] += par.basis_xform_inv(Vector2(0, -(low + 1.0) * k))
		rig.compute_from(_i_weapon)


## 등불 진자: 매달린 자리(창 위)의 세상 가속도로 흔들린다. θ'' = −(g + a_y)/l·sinθ − a_x/l·cosθ − c·θ'
## 땅에 닿으면 땅 위에 눕는다 (창이 쓰러져 누웠을 때).
func _update_lantern(delta: float) -> void:
	rig.off[_i_lantern] = Vector2.ZERO
	var hang := rig.xf[_i_weapon] * rig.base_pos[_i_lantern]
	# 세상 자리 (좌우는 지금 보는 쪽으로만 — 몸 틀기의 납작해짐은 가속도에 넣지 않는다)
	var p := boss.global_position + Vector2(hang.x * _sign, hang.y + rig.body_xf.origin.y) * _k
	var acc := Vector2.ZERO
	if delta > 0.0:
		if _lan_prev != Vector2.INF:
			var v := (p - _lan_prev) / delta
			acc = ((v - _lan_vel) / delta).limit_length(LANTERN_ACC_MAX) * LANTERN_ACC_GAIN
			_lan_vel = v
		else:
			_lan_vel = Vector2.ZERO
		_lan_prev = p
		var l := LANTERN_CENTER.length() * LANTERN_SIZE * _k
		var n := 6
		var h := delta / n
		var spinning := boss.state == LanternKnight.State.SPIN
		for k in n:
			# 매달린 자리의 틀에서 본 중력 = g − a (y 아래 +): θ'' = −((g − a_y)·sinθ + a_x·cosθ)/l − 감쇠
			# 사슬 마찰: 바깥으로 크게 흔들려 나갈 때만 (돌아올 때는 붙잡지 않는다 — 붙잡으면 등불이 옆에 떠 있는 것처럼 머문다)
			var outward := _lan_th * _lan_w > 0.0
			var c := LANTERN_DAMP + (LANTERN_FRICTION * maxf(absf(_lan_th) - 1.0, 0.0) if outward and not spinning else 0.0)
			var a := -((LANTERN_G - acc.y) * sin(_lan_th) + acc.x * cos(_lan_th)) / l - c * _lan_w
			_lan_w = clampf(_lan_w + a * h, -30.0, 30.0)
			_lan_th += _lan_w * h
		_lan_th = wrapf(_lan_th, -PI, PI)
		if not spinning and absf(_lan_th) > LANTERN_SWING_MAX:
			_lan_th = signf(_lan_th) * LANTERN_SWING_MAX
			_lan_w *= -0.2
	var world := -_lan_th * _sign
	rig.rot[_i_lantern] = world - rig.world_rot(_i_weapon)
	rig.compute_from(_i_lantern)
	var hang_y := (rig.body_xf * rig.xf[_i_lantern]).origin.y
	if hang_y > -90.0:
		# 매단 자리가 땅에 닿았다 (창이 쓰러져 누움): 등불도 땅 위에 옆으로 눕는다 (가까운 쪽으로)
		var lie := PI * 0.5 if wrapf(world, -PI, PI) >= 0.0 else -PI * 0.5
		var cur := rig.world_rot(_i_lantern)
		var k := clampf((hang_y + 90.0) / 50.0, 0.0, 1.0)
		rig.rot[_i_lantern] += angle_difference(cur, lie) * k
		rig.compute_from(_i_lantern)
		# 옆으로 누운 등불은 몸통 두께만큼 들어 올려 땅 위에 얹는다
		var low := rig.lowest_y(PackedInt32Array([_i_lantern]))
		if low > -1.0:
			rig.off[_i_lantern] = rig.xf[_i_weapon].affine_inverse().basis_xform(Vector2(0, -(low + 1.0)))
			rig.compute_from(_i_lantern)
		_lan_th = -rig.world_rot(_i_lantern) * _sign
		_lan_w *= 0.5
	elif _lift_bone(_i_lantern, 2.0, PI) != 0.0:
		_lan_th = -rig.world_rot(_i_lantern) * _sign
		_lan_w *= -0.15


# ---------- 빛·색·궤적·잔상 ----------

func _after(delta: float, st: LanternKnight.State) -> void:
	# 호환 노드: 창 손잡이 자리·각도 (등불 회전 중엔 누적 각도 — 시험이 바퀴 수를 센다)
	_weapon_bone.position = rig.position + rig.bone_point("weapon") * rig.scale.x
	_weapon_bone.rotation = _spin_base + _spin if st == LanternKnight.State.SPIN else _spear_w
	# 던진 등불이 다시 켜진다 (되돌림 뒤 절반에 걸쳐, 켜지는 순간 번쩍)
	if st == LanternKnight.State.THROW and boss.attack_phase == "recovery" and _lan_alpha < 1.0:
		var want := clampf((boss.phase_progress() - 0.35) / 0.45, 0.0, 1.0)
		if want > _lan_alpha:
			if _lan_alpha <= 0.0:
				_lan_flash = 1.0
			_lan_alpha = want
	elif st != LanternKnight.State.THROW:
		if _lan_alpha < 1.0:
			_lan_flash = 1.0
		_lan_alpha = 1.0
	_lan_flash = maxf(_lan_flash - delta * 2.5, 0.0)
	var lspr := rig.sprite_of("lantern")
	if lspr:
		lspr.modulate = Color(1.0 + _lan_flash * 1.5, 1.0 + _lan_flash * 1.2, 1.0 + _lan_flash, _lan_alpha)
	# 색: 붉은 예고는 서서히 켜지고 꺼진다, 피격 번쩍임은 셰이더로
	_red = Motion.damp(_red, 1.0 if boss.is_red() else 0.0, 14.0, delta)
	var base := Color(0.95, 0.9, 0.9) if boss.phase == 1 else Color(1.08, 0.86, 0.78)
	if st == LanternKnight.State.FALLEN:
		base = base.lerp(Color(0.72, 0.7, 0.7), clampf(_state_t / FALL_DOWN, 0.0, 1.0))
	elif st == LanternKnight.State.PURIFIED:
		base = Color(1.25, 1.22, 1.12)
	rig.modulate = base.lerp(Color(2.4, 0.5, 0.4), _red * (0.5 + 0.5 * sin(_t * 32.0)))
	rig.set_flash(boss.flash_amount() * 0.8)
	# 투구 등불·창 등불 빛
	var flick := 1.0 + Motion.breathe(_t, 3.1, 0.07) + Motion.breathe(_t, 7.3, 0.04)
	if st not in [LanternKnight.State.INTRO, LanternKnight.State.BROKEN, LanternKnight.State.FALLEN, LanternKnight.State.PURIFIED, LanternKnight.State.STAGGER, LanternKnight.State.WAIT]:
		_glow = Motion.damp(_glow, 1.0, 4.0, delta)
	var hot := Color(1.6, 1.0, 0.45) if st != LanternKnight.State.PURIFIED else Color(1.8, 1.7, 1.4)
	_head_glow.modulate = Color(hot.r, hot.g, hot.b, clampf(0.38 * _glow * flick, 0.0, 0.6))
	_head_glow.scale = Vector2.ONE * (1.3 + 0.25 * minf(_glow, 1.6))
	var lg := clampf(_lan_alpha * (0.42 if st != LanternKnight.State.FALLEN else 0.18) * flick + _lan_flash * 0.5, 0.0, 1.0)
	_lan_glow.modulate = Color(1.7, 1.05, 0.45, lg)
	_update_trail(delta)
	_update_ghosts(delta, st)
	_update_light(delta, st)
	_foot_dust(st)


func _foot_dust(st: LanternKnight.State) -> void:
	if st not in [LanternKnight.State.MARCH, LanternKnight.State.CHARGE, LanternKnight.State.INTRO, LanternKnight.State.THRUST, LanternKnight.State.WAVE, LanternKnight.State.FLAME]:
		return
	for leg in motion.legs:
		if leg.planted_now:
			var sole := rig.to_global(rig.to_rig_local(rig.xf[leg.foot] * leg.sole))
			_dust.amount = 5
			_dust.global_position = Vector2(sole.x, boss.global_position.y)
			_dust.restart()
			_dust.emitting = true
			if st == LanternKnight.State.MARCH:
				motion.kick("thud", 18.0)   # 무거운 디딤: 엉덩이가 살짝 내려앉는다


func _puff(n: int, ox: float) -> void:
	_dust.amount = n
	_dust.global_position = boss.global_position + Vector2(ox, 0)
	_dust.restart()
	_dust.emitting = true


func _spark_at(pos: Vector2) -> void:
	_embers.global_position = pos
	_embers.restart()
	_embers.emitting = true


## 창끝 / 등불의 세상 자리 (시험·불씨·궤적이 쓴다)
func _tip_global() -> Vector2:
	return rig.to_global(rig.to_rig_local(rig.xf[_i_weapon] * Vector2(0, SPEAR_TIP)))


func _lantern_global() -> Vector2:
	return rig.to_global(rig.to_rig_local(rig.xf[_i_lantern] * LANTERN_CENTER))


## 궤적: 창끝과 등불이 빠르게 지나간 자리를 빛의 띠로 남긴다 (느릴 땐 보이지 않는다).
## 점마다 '창 손잡이 자리 + 창의 방향·길이'(등불은 손잡이에서 본 방향·거리)를 적고, 그릴 때 두 점 사이를 각도로 잘게 나눠
## 호를 따라 그린다 — 빠른 휘두르기는 한 프레임에 창끝이 수백 px 를 가서 곧은 선으로 이으면 각진 띠가 됐다.
func _update_trail(delta: float) -> void:
	var tip := _tip_global()
	var lantern := _lantern_global()
	var pivot := rig.to_global(rig.to_rig_local(rig.xf[_i_weapon].origin))
	if delta > 0.0 and _prev_tip != Vector2.ZERO:
		_tip_speed = (tip - _prev_tip).length() / delta
		_lantern_speed = (lantern - _prev_lantern).length() / delta
	_prev_tip = tip
	_prev_lantern = lantern
	# 휘두르는 순간(타격)과 되돌림 첫머리에만 점을 남긴다 — 예비동작에서 창을 머리 위로 넘길 때나 몸 틀기에 띠가 생기지 않게.
	# 몸이 다 돌았을 때(|scale.x| > 0.9)만.
	var ph := boss.attack_phase
	var on := ph == "active" or (ph == "recovery" and boss.phase_progress() < 0.3)
	if boss.state == LanternKnight.State.CHARGE or boss.state == LanternKnight.State.SPIN:
		on = on or (ph == "startup" and boss.state == LanternKnight.State.SPIN and boss.phase_progress() > 0.5)
	if on and absf(_face) > 0.9:
		var to_tip := tip - pivot
		var to_lan := lantern - pivot
		_trail_pts.append([pivot, to_tip.angle(), to_tip.length(), to_lan.angle(), to_lan.length(), _t, _tip_speed, _lantern_speed * _lan_alpha])
	while _trail_pts.size() > 0 and _t - float(_trail_pts[0][5]) > TRAIL_LIFE:
		_trail_pts.pop_front()
	while _trail_pts.size() > 20:
		_trail_pts.pop_front()
	if _trail_pts.size() > 0 or _trail_dirty:
		_trail.queue_redraw()
	_trail_dirty = _trail_pts.size() > 0


func _draw_trail() -> void:
	if _trail_pts.size() < 2:
		return
	for i in range(_trail_pts.size() - 1):
		var a: Array = _trail_pts[i]
		var b: Array = _trail_pts[i + 1]
		var fade := 1.0 - clampf((_t - float(b[5])) / TRAIL_LIFE, 0.0, 1.0)
		var k := clampf((maxf(a[6], b[6]) - TRAIL_MIN_SPEED) / (TRAIL_FULL_SPEED - TRAIL_MIN_SPEED), 0.0, 1.0)
		var kl := clampf((maxf(a[7], b[7]) - TRAIL_MIN_SPEED) / (TRAIL_FULL_SPEED - TRAIL_MIN_SPEED), 0.0, 1.0)
		if k <= 0.0 and kl <= 0.0:
			continue
		var turn := maxf(absf(angle_difference(float(a[1]), float(b[1]))), absf(angle_difference(float(a[3]), float(b[3]))))
		var n := clampi(int(turn / 0.1) + 1, 1, 10)
		var p_prev := a[0] as Vector2
		var at_prev := float(a[1])
		var lt_prev := float(a[2])
		var al_prev := float(a[3])
		var ll_prev := float(a[4])
		for j in range(1, n + 1):
			var u := float(j) / n
			var p := (a[0] as Vector2).lerp(b[0], u)
			var at := lerp_angle(float(a[1]), float(b[1]), u)
			var lt := lerpf(float(a[2]), float(b[2]), u)
			var al := lerp_angle(float(a[3]), float(b[3]), u)
			var ll := lerpf(float(a[4]), float(b[4]), u)
			if k > 0.0:
				var c0 := p_prev + Vector2.from_angle(at_prev) * lt_prev
				var c1 := p + Vector2.from_angle(at) * lt
				var c2 := p + Vector2.from_angle(at) * lt * 0.82
				var c3 := p_prev + Vector2.from_angle(at_prev) * lt_prev * 0.82
				var w := k * fade * 0.1
				_ribbon(c0, c1, c2, c3, Color(1.0, 0.95, 0.75, w))
				_trail.draw_line(c0, c1, Color(1.4, 1.3, 1.0, w * 5.0), 4.0, true)
			if kl > 0.0:
				var d0 := p_prev + Vector2.from_angle(al_prev) * ll_prev
				var d1 := p + Vector2.from_angle(al) * ll
				var d2 := p + Vector2.from_angle(al) * ll * 0.88
				var d3 := p_prev + Vector2.from_angle(al_prev) * ll_prev * 0.88
				var w2 := kl * fade * 0.16
				_ribbon(d0, d1, d2, d3, Color(1.0, 0.55, 0.2, w2))
				_trail.draw_line(d0, d1, Color(1.5, 1.0, 0.5, w2 * 3.4), 9.0, true)
			p_prev = p
			at_prev = at
			lt_prev = lt
			al_prev = al
			ll_prev = ll


## 띠 한 조각: 네 점이 겹치거나 꼬여도 그려지게 기본 도형(두 삼각형)으로.
func _ribbon(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, c: Color) -> void:
	var cols := PackedColorArray([c, c, c, c])
	var uvs := PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	_trail.draw_primitive(PackedVector2Array([p0, p1, p2, p3]), cols, uvs)


## 잔상: 빠르게 휘두를 때 몸통·팔·창·등불의 희미한 그림을 남긴다 (PartRig 의 돌려 쓰는 묶음).
func _update_ghosts(delta: float, st: LanternKnight.State) -> void:
	var active := boss.attack_phase == "active" or (st == LanternKnight.State.SLAM and boss.attack_phase == "startup" and not boss.is_on_floor())
	if st == LanternKnight.State.CHARGE and boss.attack_phase == "active":
		active = false   # 돌진은 몸이 통째로 달려서 몸에 붙은 잔상이 의미 없다 (먼지·궤적으로)
	if active:
		_ghost_timer += delta
		if _ghost_timer >= 0.035:
			_ghost_timer = 0.0
			rig.snapshot_ghost(Color(1.0, 0.82, 0.55, 0.32))
	else:
		_ghost_timer = 0.0
	rig.fade_ghosts(delta, 2.6)


## 등불 빛 (보스의 PointLight2D): 창에 매단 등불을 한 박자 늦게 따라가고, 빠르게 휘둘릴수록 밝다.
## 등불을 던져 없을 땐 투구 등불로.
func _update_light(delta: float, st: LanternKnight.State) -> void:
	if _light == null:
		return
	var want := _lantern_global() if _lan_alpha > 0.3 else _head_glow.global_position
	if _light_pos == Vector2.ZERO:
		_light_pos = want
	_light_pos = Motion.damp_vec(_light_pos, want, 26.0, delta)
	_light.global_position = _light_pos
	var flicker := 1.0 + Motion.breathe(_t, 3.1, 0.06) + Motion.breathe(_t, 7.3, 0.03)
	var swing := clampf(_lantern_speed / 3000.0, 0.0, 0.7)
	var e := (1.2 if boss.phase == 1 else 1.5) * flicker * (1.0 + swing)
	if st == LanternKnight.State.FALLEN:
		e *= 0.45
	_light.energy = e


# ---------- 시험용 ----------

## 시험(probe_bosses)이 읽는 몸 자세: [기울기(화면 기준 라디안, × facing 이 + 면 앞으로 숙임), 배율(x 는 몸 틀기), 몸 세로 자리(게임 px, + 아래)]
## 노드 변환은 늘 그대로라(뼈대가 안에서 움직인다) 예전 그림의 rotation/scale/position 대신 이것을 본다.
## 기울기는 숨쉬기·덧붙임 스프링을 뺀 채널 값에서 대기 자세를 뺀 것 (멈추면 0 으로 가라앉는다).
func probe_pose() -> Array:
	var idle := motion.pose("idle_p2" if boss and boss.phase == 2 else "idle")
	var lean := ((motion.ch["lean"] as RigMotion.Chan).v + (motion.ch["torso"] as RigMotion.Chan).v) - (float(idle["lean"]) + float(idle["torso"]))
	var y := (rig.root_pos.y - motion.stand_root_y + rig.body_xf.origin.y) * _k
	return [deg_to_rad(lean) * _sign, Vector2(scale.x, 1.0), y]

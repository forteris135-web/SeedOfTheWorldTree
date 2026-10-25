extends Sprite2D
## 뿌리지기의 그림 — 부위 뼈대(PartRig: art/rigs/root_keeper, 설계도 data/rigs/root_keeper.json) + 움직임 층(RigMotion,
## 원형 자세 data/rigs/_archetypes/root_keeper.json). 2026-10-20 개편: 예전엔 몸통 한 장 + 지팡이 한 장을 통째로 기울이고 늘여서
## 땅에서 떠 보이거나 판자처럼 넘어졌다. 이제 치마·몸통·머리·두 팔(위팔·아래팔·손)·지팡이·소매·뿌리 발이 관절로 움직인다.
##  - 뿌리 발 두 개(foot_f·foot_b)가 땅을 딛는다: 걸으면 번갈아 뿌리를 떼어 옮기고(디딘 뿌리는 미끄러지지 않음), 서 있을 땐 움켜쥔다.
##    다리(허벅지·정강이)는 치마 속에 숨은 뼈라 보이지 않고, 치마 자락(부드러운 부위)은 땅에 닿으면 눌려 접혀 늘 땅에 붙어 있다.
##  - 공격은 세 박자(예비 멈칫 → 빠른 타격과 지나침 → 출렁이며 돌아옴). 진행도는 보스가 공개한 단계(attack_phase·phase_progress)라
##    단계 길이가 바뀌어도(2페이즈 0.7배) 모양이 같다. 판정·시간은 보스 스크립트 그대로 — 그림이 따라간다.
##  - 휘두르기는 손이 자루 아래쪽을 고쳐 쥐어(slide 채널, 지팡이가 손 안에서 미끄러짐) 지팡이 머리가 크게 호를 그린다.
##  - 무너짐(RISE)·쓰러짐(FALLEN): 치마가 구겨지며 몸이 내려앉고(무릎이 꺾이듯) 윗몸이 앞으로 접혀 땅에 엎드린다. 뿌리는 땅에 남는다.
##    쓰러짐은 그 자세로 정화를 기다리고, 정화되면 윗몸을 들고 고요해진다(빛이 된다).
## 공개 함수(보스·시험이 부른다): head_world()(지팡이 머리 = 구슬·씨앗 예고 자리), sweep_fan(st)(휘두르기 붉은 부채꼴).
## 붉은 예고(_draw_marks)는 예전 그대로 보스 씬의 Marks 노드(보스·소녀 뒤)에 그린다:
##   가드 가능 = 주황빛(GUARD_C), 가드 불가 = 진한 붉은색 깜빡임(RED_C, 초당 RootKeeper.TELEGRAPH_BLINK_HZ 번).
## 이 노드는 시험이 Sprite2D 로 읽어서 Sprite2D 로 두되 그림(texture)은 없다 — 부위 그림은 자식 PartRig 가 그린다.

## 뿌리 가시: 예비의 이 몫부터 지팡이를 내리꽂는다 (타격 시작 = 가시가 솟는 순간에 땅을 치게)
const SPIKE_STRIKE_AT := 0.8
const RIG_ID := "root_keeper"
## 예고 색과 세기
const GUARD_C := Color(1.0, 0.5, 0.15)
const RED_C := Color(1.0, 0.1, 0.08)
const RED_BODY := Color(1.6, 0.45, 0.4)   # 가드 불가 예고 때 몸이 물드는 색 (너무 밝으면 글로우로 번진다)
const TRAIL_LIFE := 0.28   # 지팡이 호 궤적이 남는 시간
const TRAIL_C := Color(0.7, 0.45, 1.0)
## 코드 궤적을 그리는가 (false: 이펙트 그림만 — 아래 _process 의 설명)
const TRAIL_ON := false
## 손이 자루를 따라 미끄러지는 길이 (시트 px, slide 채널 1 일 때): 휘두를 때 자루 아래쪽을 쥔다
const SLIDE_PX := 330.0
## 지팡이 위 자리 (시트 px → 지팡이 뼈 틀). 설계도 sockets 에 있다: staff_head(달 원반), lantern(등불), staff_mid(자루 가운데)
const GHOST_INTERVAL := 0.03
## 방향 전환: 보이는 폭이 +1 → 0 → −1 로 지나가는 빠르기
const TURN_SPEED := 16.0
## 쓰러짐(FALLEN): 주저앉는 시간 / 엎드려 눕는 시간 (초)
const FALL_KNEES := 0.55
const FALL_LIE := 0.75
## 다시 일어섬(RISE, 3초)의 앞부분(무너짐) 몫
const RISE_COLLAPSE := 0.3

var rig: PartRig
var motion: RigMotion
## 확인 도구용: 이름을 넣으면 상태와 상관없이 그 자세로 선다 (tools/root_keeper_film.gd 의 --poses)
var debug_pose := ""
var _boss: RootKeeper
var _t := 0.0
var _marks: Node2D
var _trail: Node2D
var _trail_pts: Array = []   # [tip(world), mid(world), 시각]
var _mir := RigMotion.Chan.new(-1.0)
var _last_mir_sign := -1.0
var _entered := -1
var _state_from := {}       # 상태(또는 공격 단계)에 들어설 때 보이던 자세
var _prev_phase := ""
var _prev_hint := ""
var _prev_flash := 0.0
var _prev_vx := 0.0
var _last_x := 0.0
var _state_t := 0.0         # 지금 상태에 머문 시간 (FALLEN·PURIFIED·INTRO 연출)
var _staff_i := -1
var _staff_axis := Vector2.DOWN   # 지팡이 축 방향 (손 뼈 틀)
var _staff_bones := PackedInt32Array()   # 지팡이 땅 막기로 지키는 부위 (staff·staff_lo)
var _sock := {}             # 이름 → [뼈 번호, 뼈 틀 자리]
var _ghost_timer := 0.0
var _dust: CPUParticles2D
var _red := 0.0
var _thud_done := false
var _rise_steps := 0
var _surge_t := 0.0
var _ready_ok := false
# 지팡이 등불 빛 (등불 부위를 따라간다)
var _light: PointLight2D


func _ready() -> void:
	texture = null
	_boss = get_parent() as RootKeeper
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rig = PartRig.new()
	rig.name = "Rig"
	add_child(rig)
	if not rig.build(RIG_ID):
		return
	motion = RigMotion.new(rig)
	rig.setup_ghosts(rig.data.get("ghost", []), 6)
	_staff_i = rig.bone_index("staff")
	if _staff_i >= 0:
		# 지팡이 축(뼈 틀 아래쪽)을 손(부모) 틀로: 손 안에서 자루를 따라 미끄러지는 방향
		_staff_axis = Vector2.DOWN.rotated(rig.rest[_staff_i])
		for nm in ["staff", "staff_lo"]:
			if rig.has_bone(nm):
				_staff_bones.append(rig.bone_index(nm))
	for sname in rig.data.get("sockets", {}):
		var sd: Dictionary = rig.data["sockets"][sname]
		_sock[sname] = [rig.bone_index(str(sd["bone"])), PartRig._v(sd["pos"])]
	# 예고 자국 (월드 좌표). 보스 씬의 Marks 노드: 트리 순서상 지형 뒤·보스 그림 앞·소녀 앞이라
	# 배경·지형 위, 보스와 소녀 아래에 그려진다 (몸 그림의 붉은 깜빡임 modulate 도 물려받지 않는다).
	_marks = get_parent().get_node_or_null("Marks") as Node2D if get_parent() else null
	if _marks == null:
		_marks = Node2D.new()
		_marks.top_level = true
		add_child(_marks)
	_marks.draw.connect(_draw_marks)
	# 호 궤적 (월드 좌표, 더하기 혼합)
	_trail = Node2D.new()
	_trail.top_level = true
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail.material = add
	_trail.draw.connect(_draw_trail)
	add_child(_trail)
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
	_dust.texture = _soft_dot()
	_dust.scale_amount_min = 0.25
	_dust.scale_amount_max = 0.6
	add_child(_dust)
	if _boss:
		_mir.v = float(_boss.facing)
		_last_mir_sign = signf(_mir.v)
		_last_x = _boss.global_position.x
		_boss.state_changed.connect(_on_state_changed)
		_light = _boss.get_node_or_null("Light") as PointLight2D
	_state_from = motion.pose("idle")
	motion.snap_feet()
	_ready_ok = true


## 먼지 알갱이 그림: 둥글고 가장자리가 부드러운 점 (기본 네모 알갱이는 가까이서 네모로 보였다). 한 번 만들어 둔다.
static var _dot: Texture2D
static func _soft_dot() -> Texture2D:
	if _dot == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 24
		gt.height = 24
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		_dot = gt
	return _dot


func _on_state_changed(st: RootKeeper.State) -> void:
	_entered = st


# ---------- 공개 ----------

## 지팡이 머리(달 원반)의 월드 좌표 — 구슬·씨앗 예고 고리가 여기 뜬다 (보스의 orb_origin 이 읽는다)
func head_world() -> Vector2:
	return socket_world("staff_head")


## 지팡이 머리(달 원반)의 세상 자리 — 이펙트가 지팡이를 따라가게 (head_world 와 같다)
func weapon_tip_global() -> Vector2:
	return socket_world("staff_head") if rig else Vector2.INF


## 뼈 틀의 점 → 세상 자리 (뼈가 없으면 Vector2.INF)
func bone_global(bone_name: String, local := Vector2.ZERO) -> Vector2:
	return rig.bone_global(bone_name, local) if rig else Vector2.INF


## 이름으로 고르는 이펙트 자리 (scripts/fx/root_keeper_fx.gd 가 읽는다): staff_head(달 원반) / staff_mid(자루 가운데)
## / lantern(지팡이 등불) / hand(지팡이를 쥔 손) / chest(가슴). 모르는 이름이면 Vector2.INF.
func fx_point(kind: String) -> Vector2:
	if rig == null:
		return Vector2.INF
	match kind:
		"staff_head", "staff_mid", "lantern":
			return socket_world(kind) if _sock.has(kind) else Vector2.INF
		"hand":
			return rig.bone_center_global("hand_f")
		"chest":
			return rig.bone_center_global("torso")
	return Vector2.INF


## 설계도 sockets 의 자리를 월드 좌표로 (없으면 보스 머리 위)
func socket_world(sname: String) -> Vector2:
	if rig == null or not _sock.has(sname):
		return global_position + Vector2(0, -300)
	var s: Array = _sock[sname]
	return rig.to_global(rig.to_rig_local(rig.xf[s[0]] * (s[1] as Vector2)))


# ---------- 매 프레임 ----------

func _process(delta: float) -> void:
	if not _ready_ok or _boss == null:
		return
	_t += delta
	_state_t += delta
	var st := _boss.state
	var ph := _boss.attack_phase
	var gs := rig.game_scale

	# 방향 전환: 보이는 폭이 +1 → 0 → −1 을 지나며 돈다 (0 인 순간 딛은 발을 뒤집는다)
	_mir.damp(float(_boss.facing), TURN_SPEED, delta)
	var ms := signf(_mir.v) if _mir.v != 0.0 else _last_mir_sign
	if ms != _last_mir_sign:
		motion.flip_feet()
		_last_mir_sign = ms
	var fvis := _last_mir_sign

	# 상태·단계 진입 (그 순간 보이던 자세에서 출발한다)
	if _entered >= 0:
		_on_entered(_entered)
		_entered = -1
	if ph != _prev_phase:
		_on_phase(st, ph)
		_prev_phase = ph
	if _boss.anim_hint == "stagger" and _prev_hint != "stagger":
		# 저스트 가드로 지팡이가 튕겼다: 휘두르던 속도를 뒤집고 팔이 뒤로 튄다
		motion.scale_velocity(motion.parry_bounce, -0.35)
		motion.kick("parry", 240.0)
		motion.kick("impact", 90.0)
	_prev_hint = _boss.anim_hint
	var fl := _boss.flash_amount()
	if fl > _prev_flash + 0.4 and st not in [RootKeeper.State.BROKEN, RootKeeper.State.FALLEN, RootKeeper.State.RISE, RootKeeper.State.PURIFIED]:
		motion.kick("impact", 70.0)
		motion.kick("crouch", 0.12)
	_prev_flash = fl
	# 벽 돌진이 벽에 막혀 멈출 때: 앞으로 쏠린 몸이 튕긴다
	var speed := absf(_boss.velocity.x)
	if st == RootKeeper.State.WALL and absf(_prev_vx) > 600.0 and speed < 50.0:
		motion.kick("impact", 140.0)
		motion.kick("crouch", 0.5)
		_puff(14, float(_boss.facing) * 60.0)
	_prev_vx = _boss.velocity.x

	# 몸이 간 거리 (뼈대 단위, 보이는 방향 기준 + = 앞)
	var dxw := _boss.global_position.x - _last_x
	_last_x = _boss.global_position.x
	if absf(dxw) > 200.0:
		dxw = 0.0   # 순간 이동 (싸움 시작·되돌리기)
		motion.snap_feet()
	var dx_rig := dxw / gs * fvis
	var speed_rig := _boss.velocity.x / gs * fvis

	# ---- 자세 ----
	var p := {}
	var drive := RigMotion.Drive.NORMAL
	var feet := RigMotion.Feet.POSE
	var ghost := false
	var trail := false
	var breath := 1.0
	var lock := 0.0
	var settle := 0.0
	var tremor := 0.0
	var surge := false
	var plant := 0.0   # 지팡이 끝을 땅에 짚는가 (서 있을 때 — 몸이 흔들려도 지팡이 끝은 땅에 남고 손이 자루를 따라 미끄러진다)
	match st:
		RootKeeper.State.WAIT:
			p = motion.pose("idle")
			plant = 1.0
		RootKeeper.State.INTRO:
			# 고개 숙여 웅크린 채 → 천천히 일어서고 → 지팡이를 땅에 짚는다 (2.6초)
			var k := _state_t / 2.6
			p = motion.mix(motion.pose("intro_bow"), motion.pose("idle"), Motion.ease_in_out(clampf((k - 0.15) / 0.6, 0.0, 1.0)))
			drive = RigMotion.Drive.SOFT
			breath = 0.4
			plant = 1.0
		RootKeeper.State.STANCE:
			p = _stance_pose(speed_rig)
			feet = RigMotion.Feet.GAIT
			breath = 1.0 if speed < 20.0 else 0.4
			plant = 1.0 if speed < 30.0 else 0.0
		RootKeeper.State.SPIKES:
			# 가시는 타격 첫 프레임에 솟는다 (root_keeper.gd) → 지팡이 내리꽂기를 예비 끝자락(SPIKE_STRIKE_AT 부터)에 당겨
			# 타격이 시작될 때 지팡이 끝이 이미 땅을 친다 (예전엔 지팡이가 땅 위 60px 에서 멈추고 가시가 먼저 솟았다 — 2026-10-20 검수)
			var sq := _boss.phase_progress()
			if _boss.attack_phase == "startup" and sq >= SPIKE_STRIKE_AT:
				p = motion.three_beat(_state_from, motion.pose("spike_up"), motion.pose("spike_down"), motion.pose("idle"), "strike",
					(sq - SPIKE_STRIKE_AT) / (1.0 - SPIKE_STRIKE_AT))
				drive = RigMotion.Drive.FAST
			elif _boss.attack_phase == "startup":
				p = motion.three_beat(_state_from, motion.pose("spike_up"), motion.pose("spike_down"), motion.pose("idle"), "windup", sq / SPIKE_STRIKE_AT)
				drive = RigMotion.Drive.SOFT
			elif _boss.attack_phase == "active":
				p = motion.three_beat(_state_from, motion.pose("spike_up"), motion.pose("spike_down"), motion.pose("idle"), "strike", 1.0)
				drive = RigMotion.Drive.FAST
			else:
				p = _beat("spike_up", "spike_down", "idle", 0.5)
				drive = _beat_drive()
			breath = 0.0
		RootKeeper.State.SWEEP:
			p = _beat("sweep_up", "sweep_hit", "sweep_ready", 1.0)
			drive = _beat_drive()
			ghost = ph == "active"
			trail = ph == "active" or (ph == "recovery" and _boss.phase_progress() < 0.25)
			breath = 0.0
		RootKeeper.State.SWEEP2:
			p = _beat("sweep2_low", "sweep2_hit", "sweep_ready", 1.0)
			drive = _beat_drive()
			ghost = ph == "active"
			trail = ph == "active" or (ph == "recovery" and _boss.phase_progress() < 0.25)
			breath = 0.0
		RootKeeper.State.ORBS:
			p = _beat("orb_charge", "orb_cast", "idle", 0.6)
			drive = _beat_drive()
			if ph == "startup":
				tremor = clampf((_boss.phase_progress() - 0.5) / 0.5, 0.0, 1.0) * 0.6
			breath = 0.0
		RootKeeper.State.WALL:
			p = _beat("wall_gather", "wall_charge", "idle", 0.25)
			drive = _beat_drive()
			if ph == "startup":
				tremor = clampf((_boss.phase_progress() - 0.5) / 0.5, 0.0, 1.0)
			elif speed > 300.0:
				# 돌진: 뿌리를 땅에 댄 채 미끄러지듯 밀려간다 (발을 떼어 걷지 않는다 — 뿌리가 땅을 긁으며 흙을 튀긴다)
				surge = true
			breath = 0.0
		RootKeeper.State.HAND:
			p = _beat("hand_up", "hand_down", "idle", 0.5)
			drive = _beat_drive()
			if ph == "startup":
				tremor = clampf(_boss.phase_progress(), 0.0, 1.0) * 0.5
			breath = 0.0
		RootKeeper.State.SEEDS:
			p = _beat("seed_up", "seed_up", "idle", 0.3)
			drive = _beat_drive()
			if ph == "active":
				# 지팡이를 머리 위에서 흔든다 (씨앗이 떨어진다)
				p = p.duplicate()
				var w := sin(_t * 17.0)
				p["hand_f"] = float(p["hand_f"]) + w * 16.0
				p["arm_f_lo"] = float(p["arm_f_lo"]) + w * 8.0
				p["torso"] = float(p["torso"]) + w * 1.5
			breath = 0.0
		RootKeeper.State.RING:
			p = _beat("ring", "ring", "idle", 0.3)
			drive = _beat_drive()
			if ph == "active":
				# 지팡이를 앞에 가로로 든 채 천천히 돌린다 (몸이 살짝 떠오른다)
				p = p.duplicate()
				var w := sin(_t * 2.6)
				p["hand_f"] = float(p["hand_f"]) + w * 24.0
				p["arm_f_up"] = float(p["arm_f_up"]) + w * 8.0
				p["hip_y"] = float(p["hip_y"]) - 0.03 * (0.5 + 0.5 * sin(_t * 2.6 + 1.0))
			breath = 0.3
		RootKeeper.State.STOMP:
			p = _beat("stomp_up", "stomp_down", "idle", 0.4)
			drive = _beat_drive()
			ghost = ph == "active"
			trail = ph == "active"
			if ph == "startup":
				tremor = clampf((_boss.phase_progress() - 0.6) / 0.4, 0.0, 1.0)
			breath = 0.0
		RootKeeper.State.BROKEN:
			p = motion.pose("broken").duplicate()
			var sway := sin(_t * 1.6)
			p["torso"] = float(p["torso"]) + sway * 3.0
			p["head"] = float(p["head"]) + sin(_t * 1.6 + 0.8) * 4.0
			p["hip_y"] = float(p["hip_y"]) + (sway * 0.5 + 0.5) * 0.02
			drive = RigMotion.Drive.SOFT
			breath = 0.5
			lock = 1.0
		RootKeeper.State.RISE:
			var r := _rise_pose()
			p = r[0]
			drive = r[1]
			tremor = r[2]
			lock = 1.0
			breath = 0.0
		RootKeeper.State.FALLEN:
			var r := _fall_pose()
			p = r[0]
			drive = r[1]
			settle = r[2]
			lock = 1.0
			breath = 0.25 if _state_t > FALL_KNEES + FALL_LIE else 0.0
		RootKeeper.State.PURIFIED:
			var k := Motion.ease_in_out(clampf(_state_t / 1.2, 0.0, 1.0))
			p = motion.mix(_state_from, motion.pose("purified"), k)
			drive = RigMotion.Drive.SLOW
			lock = 1.0
			settle = 1.0 - k
			breath = 0.6
	if debug_pose != "":
		p = motion.pose(debug_pose)
		drive = RigMotion.Drive.NORMAL
		feet = RigMotion.Feet.POSE
		breath = 0.0
		lock = 1.0 if debug_pose in ["crumple", "dead_lie", "purified", "broken"] else 0.0
		settle = 1.0 if debug_pose.begins_with("dead_lie") else 0.0
	if p.is_empty():
		p = motion.pose("idle")
	# 지팡이가 튕겼다(저스트 가드): stagger 1 → 0 동안 지팡이가 치켜든 자리 쪽으로 되튕기고 팔·몸통이 뒤로 젖혀졌다 돌아온다
	# (판정·시간은 그대로 — 그림만 휘청)
	if _boss.stagger > 0.0:
		if st == RootKeeper.State.SWEEP or st == RootKeeper.State.SWEEP2:
			var back := "sweep_up" if st == RootKeeper.State.SWEEP else "sweep2_hit"
			p = motion.mix(p, motion.pose(back), _boss.stagger * 0.6)
		p = p.duplicate()
		p["arm_f_up"] = float(p.get("arm_f_up", 0.0)) + 46.0 * _boss.stagger
		p["torso"] = float(p.get("torso", 0.0)) - 10.0 * _boss.stagger
		p["head"] = float(p.get("head", 0.0)) - 8.0 * _boss.stagger
	# 떨림 (예비 끝·가드 불가 예고): 몸통·지팡이 손이 잘게 떤다
	if tremor > 0.0:
		p = p.duplicate()
		var tw := sin(_t * 46.0) * tremor
		p["torso"] = float(p.get("torso", 0.0)) + tw * 1.2
		p["hand_f"] = float(p.get("hand_f", 0.0)) + tw * 3.0
	motion.ground_lock = lock
	motion.ground_settle = settle
	motion.breath = breath
	motion.set_target(p, drive, feet)
	_apply_slide()
	if surge:
		dx_rig = 0.0   # 딛은 뿌리를 세상에 고정하지 않는다 = 몸과 함께 땅 위를 미끄러진다
		_surge_t += delta
		if _surge_t >= 0.06:
			_surge_t = 0.0
			_puff(4, -float(_boss.facing) * 40.0)
	motion.update(delta, {"speed": speed_rig, "dx": dx_rig, "vy": _boss.velocity.y / gs, "grounded": true})
	_staff_plant(delta, plant)
	_staff_ground(delta)
	rig.position = Vector2.ZERO
	rig.scale = Vector2(_mir.v, 1.0)
	# 디딤 먼지 (걷는 중 뿌리를 디딜 때)
	if speed > 60.0:
		for leg in motion.legs:
			if leg.planted_now:
				_puff(3, leg.x * gs * fvis)
	# 잔상 (지팡이 팔)
	if ghost:
		_ghost_timer += delta
		if _ghost_timer >= GHOST_INTERVAL:
			_ghost_timer = 0.0
			rig.snapshot_ghost(Color(0.85, 0.75, 1.0, 0.35))
	else:
		_ghost_timer = 0.0
	rig.fade_ghosts(delta)
	# 지팡이 호 궤적(코드로 그린 보랏빛 띠)은 끈다 (2026-10-20 통합): 휘두르기·되돌려 베기는 기획자 이펙트 그림 '보랏빛 초승달'
	# (scripts/fx/root_keeper_fx.gd — 지팡이 머리가 지나가는 호에 맞춰 뜬다)이 맡는다. 둘 다 그리면 각진 보랏빛 띠가
	# 초승달 그림 위에 따로 떠서 두 겹으로 보였다. 내려찍기(가드 불가)는 붉은 이펙트만 (보랏빛 띠가 붉은 예고를 흐렸다).
	_update_trail(trail and TRAIL_ON)
	_update_light(delta)

	# ---- 색 ----
	_red = Motion.damp(_red, 1.0 if _boss.is_red() else 0.0, 14.0, delta)
	var base := Color(0.94, 0.95, 1.0) if _boss.phase == 1 else Color(1.04, 0.97, 1.06)
	if st == RootKeeper.State.FALLEN:
		base = base.lerp(Color(0.6, 0.6, 0.66), clampf(_state_t / 1.5, 0.0, 1.0) * 0.6)
	elif st == RootKeeper.State.PURIFIED:
		base = Color(1.25, 1.2, 1.05)
	base = base.lerp(RED_BODY, _red * (0.45 + 0.35 * sin(_t * TAU * RootKeeper.TELEGRAPH_BLINK_HZ)))
	rig.modulate = base
	rig.set_flash(fl * 0.8, Color(1.6, 1.6, 1.6))
	if not _marks.top_level:
		_marks.global_position = Vector2.ZERO   # 보스가 움직여도 예고는 월드 좌표로 그린다
	_marks.queue_redraw()
	_trail.queue_redraw()


## 서 있기·걷기: 소녀와 거리를 두며 천천히 다가오거나(앞으로) 물러난다(뒤로 걷기)
func _stance_pose(speed_rig: float) -> Dictionary:
	var amt := clampf(absf(speed_rig) / maxf(motion.L * 1.0, 1.0), 0.0, 1.0)
	var idle := motion.pose("idle").duplicate()
	# 대기: 위엄 있게 천천히 흔들린다 (몸통·머리, 뿌리는 땅을 움켜쥔다)
	var sway := sin(_t * 0.9)
	idle["torso"] = float(idle["torso"]) + sway * 1.6
	idle["head"] = float(idle["head"]) + sin(_t * 0.9 + 0.9) * 2.2
	idle["toe_f"] = (0.5 + 0.5 * sin(_t * 0.7)) * 3.0
	idle["toe_b"] = (0.5 + 0.5 * sin(_t * 0.7 + 2.0)) * 3.0
	# 골반째 아주 조금 흔들린다 → 치마 자락(늘어진 천)이 한 박자 늦게 따라 흔들린다
	idle["lean"] = float(idle.get("lean", 0.0)) + sin(_t * 0.9 - 0.6) * 1.2
	var walk := motion.pose("walk_back" if speed_rig < 0.0 else "walk")
	return motion.mix(idle, walk, amt)


## 공격 세 박자: 예비(startup) → 타격(active, 앞 span 몫에 끝나고 머문다) → 되돌림(recovery).
func _beat(windup: String, strike: String, ready: String, span: float) -> Dictionary:
	var p := _boss.phase_progress()
	match _boss.attack_phase:
		"startup":
			return motion.three_beat(_state_from, motion.pose(windup), motion.pose(strike), motion.pose(ready), "windup", p)
		"active":
			return motion.three_beat(_state_from, motion.pose(windup), motion.pose(strike), motion.pose(ready), "strike", clampf(p / maxf(span, 0.01), 0.0, 1.0))
		"recovery":
			return motion.three_beat(_state_from, {}, {}, motion.pose(ready), "recover", p)
	return motion.pose("idle")


func _beat_drive() -> RigMotion.Drive:
	match _boss.attack_phase:
		"startup": return RigMotion.Drive.SOFT
		"active": return RigMotion.Drive.FAST
		"recovery": return RigMotion.Drive.SETTLE
	return RigMotion.Drive.NORMAL


## 다시 일어섬 (RISE, rise_len 초): 앞 30% 에 지금 자세에서 무너져 치마가 구겨지며 땅에 주저앉고 윗몸이 앞으로 접힌다.
## 그다음 떨며 지팡이를 땅에 짚고, 뿌리를 다시 움켜쥐며(한 걸음씩 다시 디딤) 천천히 일어선다. [자세, 보간, 떨림]
func _rise_pose() -> Array:
	var k := _boss.state_progress(_boss.rise_len)
	if k < RISE_COLLAPSE:
		var u := Motion.ease_in(k / RISE_COLLAPSE, 1.8)
		return [motion.mix(_state_from, motion.pose("crumple"), u), RigMotion.Drive.QUICK, 0.0]
	var v := (k - RISE_COLLAPSE) / (1.0 - RISE_COLLAPSE)
	# 잠깐 엎드린 채 숨을 고르고(앞 15%), 지팡이를 짚어 밀어 올린다
	var up := Motion.ease_in_out(clampf((v - 0.15) / 0.85, 0.0, 1.0))
	var p := motion.mix(motion.pose("crumple"), motion.pose("rise_stand"), up)
	# 뿌리를 다시 움켜쥐며 발을 차례로 고쳐 디딘다 (발 자리를 조금씩 옮겨 한 걸음씩)
	var steps := int(floor(v * 4.0))
	if steps != _rise_steps and steps <= 3:
		_rise_steps = steps
		if steps > 0:
			motion.kick("crouch", 0.25)
			_puff(6, 0.0)
	p = p.duplicate()
	p["foot_f"] = float(p.get("foot_f", 0.3)) + (0.06 if _rise_steps % 2 == 1 else 0.0)
	p["foot_b"] = float(p.get("foot_b", -0.3)) - (0.06 if _rise_steps % 2 == 0 and _rise_steps > 0 else 0.0)
	p["step_thr"] = 0.04
	p["step_dur"] = 0.22
	p["step_lift"] = 0.05
	var tremor := (1.0 - up) * 0.8 if v > 0.1 else 0.0
	return [p, RigMotion.Drive.SOFT, tremor]


## 쓰러짐 (FALLEN): 맞은 순간 몸이 젖혀졌다가 → 치마가 구겨지며 주저앉고(FALL_KNEES) → 윗몸이 앞으로 넘어가 땅에 엎드린다(FALL_LIE).
## 엎드린 몸은 내려놓기(ground_settle)가 땅에 붙인다. 닿는 순간 작게 튄다. 그 자세로 정화를 기다린다. [자세, 보간, 내려놓기]
func _fall_pose() -> Array:
	var e := _state_t
	var knees := Motion.ease_in(clampf(e / FALL_KNEES, 0.0, 1.0), 1.6)
	var lie := Motion.ease_in(clampf((e - FALL_KNEES * 0.7) / FALL_LIE, 0.0, 1.0), 2.0)
	var p := motion.mix(motion.mix(_state_from, motion.pose("crumple"), knees), motion.pose("dead_lie"), lie)
	if lie >= 1.0 and not _thud_done:
		_thud_done = true
		motion.kick("thud", 8.0)
		motion.kick("impact", -60.0)
		_puff(16, float(_boss.facing) * 120.0)
	return [p, RigMotion.Drive.QUICK if lie < 1.0 else RigMotion.Drive.SOFT, lie]


## 지팡이 짚기: 서 있을 때 지팡이 끝이 땅에 닿도록 지팡이를 자루 방향으로 밀고 당긴다 (손이 자루를 따라 미끄러진다).
## 숨쉬기·흔들림으로 손이 오르내려도 지팡이 끝은 땅에 남는다. 지팡이가 곧게 서 있을 때만 (기울면 하지 않는다). _plant 는 부드럽게 오간다.
const PLANT_MAX := 120.0   # 자루를 따라 밀고 당기는 한계 (뼈대 단위 = 시트 px)
var _plant := 0.0
func _staff_plant(delta: float, target: float) -> void:
	_plant = Motion.damp(_plant, target, 6.0, delta) if delta > 0.0 else target
	if _plant < 0.01 or _staff_i < 0:
		return
	var axis := (rig.body_xf * rig.xf[_staff_i]).basis_xform(Vector2.DOWN).normalized()
	if axis.y < 0.6:
		return
	var depth := _staff_depth()
	var want := -STAFF_MARGIN - 1.0
	var k := clampf((depth - want) / axis.y, -PLANT_MAX, PLANT_MAX) * _plant
	if absf(k) < 0.05:
		return
	var par := rig.parent[_staff_i]
	rig.set_bone_offset(_staff_i, rig.bone_offset(_staff_i) + (rig.body_xf * rig.xf[par]).basis_xform_inv(-axis * k))
	rig.apply()


## 지팡이 땅 막기 (RigMotion 의 무기 땅 막기는 관절마다 한계가 있어, 엎드리는 동안 지팡이가 땅속으로 들어갈 때가 있다):
## 지팡이(staff·staff_lo) 껍질의 가장 낮은 점이 땅 아래면 손 안에서 지팡이를 돌려 땅 위에 얹는다. 돌리는 각도(_staff_fix)는
## 5도씩 양쪽으로 견줘 '지난 프레임의 각도에 가장 가까운' 해를 고르고(처음이면 지팡이 머리가 몸 앞쪽에 남는 쪽) 부드럽게 쫓는다
## → 프레임마다 다른 해로 튀지 않는다. 쫓는 동안 모자라거나 손이 땅에 닿아 돌려도 남는 만큼은 지팡이를 들어 올린다.
const STAFF_MARGIN := 3.0
const STAFF_STEP := 0.087
var _staff_fix := 0.0
func _staff_ground(delta: float) -> void:
	if _staff_i < 0:
		return
	var base := rig.bone_rot(_staff_i)
	var want := 0.0
	var need := _staff_depth() > -STAFF_MARGIN
	if need and absf(_staff_fix) > 0.0005:
		# 지난 프레임의 각도로 아직 땅 위면 그대로 (매 프레임 다시 찾지 않는다 — 지팡이를 짚고 선 대기 자세에서 늘 이 경우)
		rig.set_bone_rot(_staff_i, base + _staff_fix)
		if _staff_depth() <= -STAFF_MARGIN:
			want = _staff_fix
			need = false
	if need:
		var best := INF
		var best_cost := INF
		var least := INF
		var least_fix := 0.0
		for k in range(1, 28):
			for sgn in [-1.0, 1.0]:
				var fix: float = sgn * k * STAFF_STEP
				rig.set_bone_rot(_staff_i, base + fix)
				var d := _staff_depth()
				if d <= -STAFF_MARGIN:
					var cost := absf(fix - _staff_fix)
					if absf(_staff_fix) < 0.01 and _sock.has("staff_head"):
						cost -= (rig.body_xf * (rig.xf[_staff_i] * (_sock["staff_head"][1] as Vector2))).x * 0.0001   # 처음이면 머리가 앞쪽인 해
					if cost < best_cost:
						best_cost = cost
						best = fix
				elif d < least:
					least = d
					least_fix = fix
		want = best if best < INF else least_fix
	_staff_fix = Motion.damp(_staff_fix, want, 10.0, delta) if delta > 0.0 else want
	if absf(_staff_fix) < 0.0005 and want == 0.0:
		_staff_fix = 0.0
		rig.set_bone_rot(_staff_i, base)
		return
	rig.set_bone_rot(_staff_i, base + _staff_fix)
	var rest_d := _staff_depth() + STAFF_MARGIN
	if rest_d > 0.0:
		# 모자란 만큼 지팡이를 위로 (세상 위쪽을 부모 틀로 바꿔 자리에 더한다 — 다음 프레임에 _apply_slide 가 다시 정한다)
		var up := (rig.body_xf * rig.xf[rig.parent[_staff_i]]).basis_xform_inv(Vector2(0.0, -rest_d))
		rig.set_bone_offset(_staff_i, rig.bone_offset(_staff_i) + up)
	rig.apply()


func _staff_depth() -> float:
	var deepest := -INF
	for b in _staff_bones:
		var t := rig.body_xf * rig.xf[b]
		for hp in rig.hulls[b]:
			deepest = maxf(deepest, (t * hp).y)
	return deepest


## 지팡이를 손 안에서 자루를 따라 미끄러뜨린다 (slide 채널: 0 = 등불 아래 손잡이, 1 = 자루 아래쪽을 쥠)
func _apply_slide() -> void:
	if _staff_i < 0 or not motion.ch.has("slide"):
		return
	var s := clampf(motion.channel("slide"), -0.2, 1.2)
	rig.set_bone_offset(_staff_i, -_staff_axis * s * SLIDE_PX, false)


func _on_entered(st: int) -> void:
	_state_from = motion.capture()
	_state_t = 0.0
	var fade := 0.12
	match st:
		RootKeeper.State.FALLEN:
			_thud_done = false
			fade = 0.0
			motion.kick("impact", 120.0)
			_puff(16, 0.0)
		RootKeeper.State.RISE:
			_rise_steps = 0
			fade = 0.0
			motion.kick("impact", 100.0)
			_puff(14, 0.0)
		RootKeeper.State.BROKEN:
			fade = 0.1
			motion.kick("impact", 110.0)
			motion.kick("crouch", 0.6)
			_puff(10, 0.0)
		RootKeeper.State.PURIFIED:
			fade = 0.0
		RootKeeper.State.STANCE:
			fade = 0.25
		RootKeeper.State.INTRO:
			# 나타나는 순간부터 고개 숙여 웅크린 자세 (서 있다가 숙이지 않게: 채널을 바로 그 자세로)
			motion.transition(0.0)
			motion.set_target(motion.pose("intro_bow"), RigMotion.Drive.SOFT, RigMotion.Feet.POSE)
			motion.update(0.0, {})
			motion.snap_feet()
			_state_from = motion.capture()
			fade = 0.0
	if st in RootKeeper.ATTACK_STATES:
		fade = 0.0     # 세 박자 곡선이 지금 자세에서 출발한다
	motion.transition(fade)


## 공격 단계가 바뀌는 순간: 출발 자세를 다시 잡고(되돌림은 타격 끝 자세에서), 타격 순간의 먼지·눌림.
func _on_phase(st: int, ph: String) -> void:
	if ph == "recovery":
		_state_from = motion.capture()
	if ph != "active":
		return
	var f := float(_boss.facing)
	match st:
		RootKeeper.State.SPIKES, RootKeeper.State.HAND:
			motion.kick("crouch", 0.6)
			motion.kick("squash", 1.2)
			_puff(12, _staff_tip_x())
		RootKeeper.State.STOMP:
			motion.kick("crouch", 1.0)
			motion.kick("squash", 2.0)
			_puff(24, _staff_tip_x())
		RootKeeper.State.SWEEP:
			_puff(5, -f * 30.0)
		RootKeeper.State.SWEEP2:
			_puff(5, f * 30.0)
		RootKeeper.State.WALL:
			_puff(10, -f * 60.0)
		RootKeeper.State.SEEDS:
			motion.kick("crouch", -0.3)


## 지팡이 아래 끝의 x (보스 기준, 월드 px) — 내리꽂은 자리에서 먼지가 인다
func _staff_tip_x() -> float:
	var lo := rig.bone_index("staff_lo")
	if lo < 0:
		return 0.0
	return rig.to_global(rig.bone_point("staff_lo", Vector2(0, 200))).x - _boss.global_position.x


func _puff(n: int, ox: float) -> void:
	_dust.amount = n
	_dust.global_position = _boss.global_position + Vector2(ox, 0)
	_dust.restart()
	_dust.emitting = true


# ---------- 호 궤적 · 빛 ----------

func _update_trail(active: bool) -> void:
	if active:
		_trail_pts.append([socket_world("staff_head"), socket_world("staff_mid"), _t])
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
		# 바깥(머리 쪽)은 진하고 안쪽은 옅게: 초승달 베기 자국. 삼각형 둘로 나눠 그린다 (조각이 꼬여도 삼각분할이 실패하지 않게)
		_trail_quad(a[0], b[0], mb, ma, Color(TRAIL_C, alpha))
		_trail_quad(ma, mb, b[1], a[1], Color(TRAIL_C, alpha * 0.3))
		_trail.draw_line(a[0], b[0], Color(1.0, 0.9, 1.0, alpha * 1.4), 4.0, true)


func _trail_quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, c: Color) -> void:
	_trail_tri(p0, p1, p2, c)
	_trail_tri(p0, p2, p3, c)


func _trail_tri(p0: Vector2, p1: Vector2, p2: Vector2, c: Color) -> void:
	var area := (p1 - p0).cross(p2 - p0)
	if absf(area) < 1.0:
		return
	if area > 0.0:
		var t := p1
		p1 = p2
		p2 = t
	_trail.draw_primitive(PackedVector2Array([p0, p1, p2]), PackedColorArray([c, c, c]), PackedVector2Array())


## 지팡이 등불 빛: 등불 부위(lantern — 뼈대의 늘어진 천처럼 진자로 흔들린다)의 가운데를 따라간다.
func _update_light(_delta: float) -> void:
	if _light == null:
		return
	_light.global_position = socket_world("lantern")
	var e := (1.0 if _boss.phase == 1 else 1.25) * (1.0 + Motion.breathe(_t, 0.9, 0.08))
	if _boss.state == RootKeeper.State.FALLEN:
		e *= 0.45
	_light.energy = e


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
			# v1.1.0: 휘두르기의 공격 범위 예고는 보스의 RangeTelegraph 가 판정과 같은 사각형으로 그린다 (예전 붉은 부채꼴은 판정보다 훨씬 컸다)
			pass
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
			# v1.1.0: 뿌리 벽이 쓸고 갈 구간은 보스의 RangeTelegraph 가 판정과 같은 사각형으로 그린다 (예전엔 아레나 끝까지·판정보다 높게)
			pass
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
			# (내려찍기 판정 기둥은 v1.1.0 부터 보스의 RangeTelegraph 가 판정과 같은 사각형 ±130 으로 그린다 — 예전 기둥 폭 300·반원은 뺐다)
			# 충격파가 달릴 방향 화살
			for d: float in [-1.0, 1.0]:
				var x: float = bx + d * (200.0 + 300.0 * p)
				_marks.draw_line(Vector2(x, g - 45), Vector2(x + d * 40.0, g - 45), _tg(0.8 * p * fade, false), 3.0)
				_marks.draw_line(Vector2(x + d * 40.0, g - 45), Vector2(x + d * 20.0, g - 65), _tg(0.8 * p * fade, false), 3.0)
				_marks.draw_line(Vector2(x + d * 40.0, g - 45), Vector2(x + d * 20.0, g - 25), _tg(0.8 * p * fade, false), 3.0)


## 휘두르기 예고 영역 (월드 좌표 다각형). v1.1.0 (기획자 요청 1): 판정과 같은 사각형 — 보스 sweep_reach(미끄러짐 포함)의
## 네 모서리 (경계 위의 점도 안에 들도록 1px 넓힌다). 그려지는 예고는 보스의 RangeTelegraph 이고, 이 함수는 시험이 그 자리를 읽는 통로.
func sweep_fan(st: int) -> PackedVector2Array:
	var reach: Rect2 = _boss.sweep_reach(st)
	var g := _boss.ground_y
	var f := float(_boss.facing)
	var bx := _boss.global_position.x
	var x0 := bx + f * (reach.position.x - 1.0)
	var x1 := bx + f * (reach.end.x + 1.0)
	var y0 := g + reach.position.y - 1.0
	var y1 := g + reach.end.y + 1.0
	return PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)])

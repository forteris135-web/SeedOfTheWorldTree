extends Node2D
class_name EnemyRigVisual
## 일반 몹의 '부위 뼈대' 그림 (EnemySpriteVisual 을 갈아 끼우는 자리). 씬의 Visual 노드에 이 스크립트를 붙이고 rig_id 만 정한다.
## 부위 그림은 art/rigs/<rig_id>/ (tools/rig_cut.gd 가 data/rigs/<rig_id>.json 에서 자른다). 쓰는 법: RIGS.md.
##
## EnemyBase 의 상태(state·windup_progress·phase_progress·attack_phase·anim_hint·velocity·facing)를 읽어 자세를 고르고,
## RigMotion 이 관절을 움직인다 (예비 → 타격 → 되돌림 세 박자, 발 디딤, 다리 IK, 무기 땅 막기, 천 흔들림, 쓰러짐).
## 판정·시간은 전혀 건드리지 않는다 (그림이 논리를 따라간다). EnemySpriteVisual 과 같은 공개 함수·값을 그대로 둔다:
##   kick / impact / parried / block / recoil / fall, visible_facing / is_facing_settled, art_faces_right, show_overhead_bar,
##   warm_eye, stride_scale, arm_front / arm_front_limit / tilt_scale, arm_kind(대롱이면 소녀를 겨눔 — aim_bone), art_scale(배율),
##   _label, texture(구원 NPC 그림).
## 원형(archetype)별 자세는 RigPoses, 뼈대마다 고칠 값은 설계도의 "poses".

## art/rigs/<rig_id>/rig.json
@export var rig_id := "woodcutter"
## 크기 배율 (1 = 뼈대 설계도의 game_scale 그대로). 거대화 중간 보스는 EliteTraits 가 1.8 배로 키운다.
@export var art_scale := 1.0
## 구원 가능한 자: 눈빛의 따뜻한 빛 (뼈대 설계도 sockets 의 eye 자리)
@export var warm_eye := false
## 머리 위 작은 체력·흐트러짐 막대 (중간 보스는 화면 아래 보스 막대가 있어 끈다)
@export var show_overhead_bar := true
## 구원되어 사람으로 돌아온 모습 (RescuedPerson). npc_rig 이 있으면 그 뼈대로, 없으면 texture 한 장(npc_art_scale 배율)으로.
@export var npc_rig := ""
@export var texture: Texture2D
@export var npc_art_scale := 0.17
@export var npc_faces_right := false
## 무기 팔의 종류 (EliteTraits 가 읽는다): 검(들었다 내려침) / 대롱(겨눔 — 쫓기·예고·쏘기·회복·물러남 동안 aim_bone 이 소녀를 겨눈다)
@export_enum("sword", "gun") var arm_kind := "sword"
## 대롱: 소녀를 겨누는 부위 (그 뼈의 축 = 대롱 방향). 위팔(arm_f_up)을 돌려 겨눈다.
@export var aim_bone := "weapon"

## 예전 그림(EnemySpriteVisual)과 같은 이름의 값들 — EliteTraits·시험이 읽고 쓴다. 뼈대는 늘 오른쪽을 보는 그림으로 잘린다.
var art_faces_right := true
## 걸음 보폭 배율 — 뼈대는 크기와 함께 보폭도 커지므로 쓰지 않는다 (예전 값 호환용).
var stride_scale := 1.0
## 타격 끝 무기 각도 / 앞으로 내리는 무기 각도 상한 (예전 값 호환용 — EliteTraits 가 쓴다). 뼈대는 이 값을 쓰지 않고
## '무기 땅 막기'(RigMotion, 설계도 ground_guard)가 어떤 크기에서도 칼끝을 땅 위에 둔다.
var arm_front := 1.1
var arm_front_limit := INF
const ARM_FRONT := 1.1
## 몸 기울기 배수 (거대화 몹은 앞머리가 땅에 박히지 않게 줄인다)
var tilt_scale := 1.0
## 돌아설 때 줄이는 폭의 한계 (0 = 폭이 0 을 지나며 몸을 튼다 — 사람 모양). 몸이 긴 기계는 0.5: 절반까지 줄이고 '쿵' 뒤집는다
## (기계·작은 펌프가 4~5프레임 동안 세로 실선처럼 보였다 — 2026-10-20 검수). EnemyMechVisual 이 정한다.
var turn_min_width := 0.0

## 공중이면 '공중 자세'로 바꾸는 상태들 (공격·무너짐·쓰러짐은 공중에서도 제 자세)
const LOCO_STATES := [EnemyBase.State.IDLE, EnemyBase.State.PATROL, EnemyBase.State.CHASE, EnemyBase.State.BACKSTEP, EnemyBase.State.ALERT, EnemyBase.State.LUNGE, EnemyBase.State.HIT]
## 잔상 간격(초)·장 수
const GHOST_INTERVAL := 0.025
const GHOST_COUNT := 6
## 대롱이 겨누는 상태와 위아래 한계 (앞쪽 수평 기준, 라디안: − 위 / + 아래) — 예전 그림(EnemySpriteVisual)과 같은 값
const AIM_STATES := [EnemyBase.State.CHASE, EnemyBase.State.WINDUP, EnemyBase.State.STRIKE, EnemyBase.State.RECOVER, EnemyBase.State.BACKSTEP]
const AIM_UP := -0.7
const AIM_DOWN := 0.6
## 예고 동안 대롱을 조금 치켜든다 (쏘기 직전 겨눔이 읽히게)
const AIM_WINDUP_RAISE := 0.25

var rig: PartRig
var motion: RigMotion
var _enemy: EnemyBase
var _label: Label
var _overlay: Node2D
var _underlay: Node2D
var _glow: Sprite2D
var _t := 0.0
var _mir := RigMotion.Chan.new(1.0)
var _face_target := 0
var _face_hold := 0.0
var _last_mir_sign := 1.0
var _entered := -1
var _state_from := {}     # 상태에 들어설 때 보이던 자세 (예비·되돌림·무너짐이 여기서 시작)
var _from_state := -1
var _floor_y := 0.0
var _floor_known := false
var _last_x := 0.0
var _was_airborne := false
var _alert_t := -1.0
var _col := Color(1, 1, 1, 1)
var _tint_strength := 0.0
var _tremor := 0.0
var _strike_flash := 0.0
var _block_flash := 0.0
var _recoil := 0.0
var _ghost_timer := 0.0
var _dust: CPUParticles2D
var _step_dust: CPUParticles2D
var _drag: CPUParticles2D
var _hit_dir := 1
var _fall_dir := 1
var _fall_gentle := false
var _fall_sign := 1.0
var _scatter_popped := false
var _thud_done := false
var _ready_ok := false
var _underlay_on := false
var _aim_i := -1      # 대롱 뼈 번호
var _overlay_sig := Vector3(-2, -2, -2)   # 머리 위 표시를 마지막으로 그린 값 (바뀔 때만 다시 그린다)
var _aim_arm := -1    # 겨눌 때 돌리는 위팔 뼈 번호
var _notifier: VisibleOnScreenNotifier2D   # 화면 밖 가만히 있는 몹은 뼈대를 쉬게 한다 (_cull_quiet)
var _culled := false
var _notifier_scale := -1.0


func _ready() -> void:
	_enemy = get_parent() as EnemyBase
	_underlay = Node2D.new()
	_underlay.name = "Underlay"
	_underlay.draw.connect(_draw_underlay)
	add_child(_underlay)
	rig = PartRig.new()
	rig.name = "Rig"
	add_child(rig)
	if not rig.build(rig_id):
		return
	motion = _make_motion()
	rig.setup_ghosts(rig.data.get("ghost", ["torso", "arm_f_up", "arm_f_lo", "weapon"]), GHOST_COUNT)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color("ffd46a"))
	# '정화의 손길' 글자: 머리 위 (거대화 중간 보스는 EliteTraits.fit_visual 이 다시 맞춘다)
	_label.position = Vector2(-80, -float(rig.data.get("height", 1000.0)) * rig.game_scale * art_scale - 70.0)
	_label.visible = false
	add_child(_label)
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_dust = _make_dust(12)
	_step_dust = _make_dust(3)
	_step_dust.lifetime = 0.35
	_step_dust.initial_velocity_min = 30.0
	_step_dust.initial_velocity_max = 70.0
	_step_dust.scale_amount_min = 2.0
	_step_dust.scale_amount_max = 3.5
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
	if warm_eye and rig.data.get("sockets", {}).has("eye"):
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
		var sock: Dictionary = rig.data["sockets"]["eye"]
		rig.attach(str(sock["bone"]), _glow, PartRig._v(sock["pos"]))
	if _enemy:
		_face_target = _enemy.facing
		_mir.v = 1.0 if _enemy.facing > 0 else -1.0
		_last_mir_sign = signf(_mir.v)
		_last_x = _enemy.global_position.x
		if _enemy.has_signal("state_changed"):
			_enemy.state_changed.connect(_on_state_changed)
		_from_state = _enemy.state
	_state_from = motion.pose("idle")
	if arm_kind == "gun":
		_aim_i = rig.bone_index(aim_bone)
		_aim_arm = rig.bone_index("arm_f_up")
		if _aim_i < 0 or _aim_arm < 0 or not motion.ch.has("arm_f_up"):
			push_warning("대롱 겨눔: 뼈대 %s 에 %s 또는 arm_f_up 이 없어 겨누지 않는다" % [rig_id, aim_bone])
			_aim_i = -1
	if DisplayServer.get_name() != "headless":
		# 뼈대를 덮는 넉넉한 사각형 (키 기준: 무기·천이 앞뒤로 키만큼, 위로 키의 1.5배 — 크기는 _cull_quiet 가 맞춘다)
		_notifier = VisibleOnScreenNotifier2D.new()
		add_child(_notifier)
	_ready_ok = true


## 움직임 층을 만든다 (몹마다 갈고리 달린 HookedRigMotion 으로 바꿔 쓰려면 이것을 덮어쓴다 — 두 번 만들지 않게)
func _make_motion() -> RigMotion:
	return RigMotion.new(rig)


## 상태가 바뀌었다고 표시만 해 둔다. 진입 연출은 다음 _process 에서 (하위 스크립트가 anim_hint 를 그 뒤에 세우므로).
func _on_state_changed(_old: int, new_state: int) -> void:
	_entered = new_state


## 지금 그림이 실제로 보고 있는 방향(±1). 뒤집는 도중이면 아직 지나온 쪽이다.
func visible_facing() -> int:
	return 1 if _mir.v >= 0.0 else -1


## 보이는 방향이 논리 방향(facing)에 자리 잡았는가 (경비병의 방패 판정이 본다).
func is_facing_settled() -> bool:
	if _enemy == null:
		return true
	if _face_target != _enemy.facing:
		return false
	var want := 1.0 if _enemy.facing > 0 else -1.0
	return signf(_mir.v) == signf(want) and absf(_mir.v) >= 0.6


## 구원되어 사람으로 돌아올 때의 모습 (EnemyBase._finish_fall 이 읽는다).
## floor_y: 발이 닿는 땅 = 몸 충돌 캡슐의 바닥 (적 원점 기준) — 뼈대 사람을 여기에 세운다.
func npc_look() -> Dictionary:
	var fy := _floor_y if _floor_known else (_find_floor_y() if _enemy else 0.0)
	return {"rig": npc_rig, "rig_scale": art_scale, "texture": texture, "art_faces_right": npc_faces_right, "art_scale": npc_art_scale, "floor_y": fy}


# ---------- 1회 연출 (EnemyBase 가 부른다) ----------

## 소녀의 공격이 닿았다: 밀린 방향(dir, ±1, 세상 기준)으로 젖혀지고 스프링으로 돌아온다. strength 0.5~1.6.
func kick(dir: int, strength := 1.0) -> void:
	if motion == null:
		return
	_hit_dir = dir
	var rel := float(dir) * signf(_mir.v)    # + = 앞으로 밀림(등 뒤에서 맞음), − = 뒤로
	motion.kick("impact", -rel * 160.0 * strength)
	motion.kick("shove", rel * 0.8 * strength)
	motion.kick("crouch", 0.35 * strength)


## 꽝 하고 부딪힘(방패 박힘·착지·분노): 눌렸다 튕긴다.
func impact(dir: int, strength := 1.0) -> void:
	if motion == null:
		return
	motion.kick("crouch", 1.2 * strength)
	motion.kick("squash", 2.0 * strength)
	motion.kick("impact", float(dir) * signf(_mir.v) * -60.0 * strength)
	_puff(int(6 + 6 * strength))


## 저스트 가드로 받아쳤다: 휘두르던 무기는 지나가던 속도를 뒤집어 되튕기고, 몸은 뒤로 밀린다.
func parried(dir: int, strength := 1.0) -> void:
	if motion == null:
		return
	motion.scale_velocity(motion.parry_bounce, -0.35)   # 원형의 움직임 지도 (사람 모양: 무기 팔 + 몸통)
	motion.kick("parry", 260.0 * strength)
	kick(dir, strength)


## 방패로 막았다: 윗몸이 뒤로 살짝 밀리며 번쩍.
func block(dir: int, strength := 1.0) -> void:
	if motion == null:
		return
	_block_flash = 1.0
	motion.kick("impact", -float(dir) * signf(_mir.v) * 70.0 * strength)
	motion.kick("crouch", 0.2 * strength)


## 쏘았다: 무기가 뒤로 튀고 몸이 살짝 밀린다.
func recoil(strength := 1.0) -> void:
	if motion == null:
		return
	_recoil = maxf(_recoil, strength)
	motion.kick("recoil", 220.0 * strength)
	motion.kick("shove", -0.4 * strength)


## 쓰러진다 (EnemyBase._begin_fall 이 부른다). dir: 밀린 방향(세상), gentle: 빛으로 흩어짐(정화·구원) / 어두워짐.
func fall(dir: int, gentle: bool) -> void:
	_fall_dir = dir if dir != 0 else 1
	_fall_gentle = gentle
	# 넘어가는 쪽 (뼈대 기준 + = 앞으로): 뒤로 밀렸으면 뒤로, 정화(빛)는 앞으로 고개 숙이며 엎드린다
	var rel := float(_fall_dir) * signf(_mir.v)
	_fall_sign = 1.0 if (gentle or rel > 0.0) else -1.0
	_thud_done = false
	if motion:
		motion.kick("impact", -rel * 90.0)


# ---------- 매 프레임 ----------

func _process(delta: float) -> void:
	if not _ready_ok or _enemy == null:
		return
	_t += delta
	if _cull_quiet():
		return
	if not _floor_known:
		_floor_y = _find_floor_y()
		_floor_known = true
	var st := _enemy.state
	var hint: String = _enemy.anim_hint
	var gscale := rig.game_scale * art_scale
	var vx := _enemy.velocity.x
	var on_floor := _enemy.is_on_floor()
	# 한 번 공중이 되면 땅에 닿을 때까지 공중 (폴짝 뛴 꼭대기에서 세로 속도가 잠깐 작아질 때 다리가 땅 걸음을 시작하지 않게)
	var airborne := not on_floor and (absf(_enemy.velocity.y) > 60.0 or _was_airborne)

	# 방향 전환: 0.1초에 한 번만 받아들이고, 보이는 폭이 +1 → 0 → −1 을 지나며 몸을 튼다
	_face_hold += delta
	if _enemy.facing != _face_target and _face_hold >= 0.1:
		_face_target = _enemy.facing
		_face_hold = 0.0
	_mir.damp(1.0 if _face_target > 0 else -1.0, 22.0, delta)
	var ms := signf(_mir.v) if _mir.v != 0.0 else _last_mir_sign
	if ms != _last_mir_sign:
		motion.flip_feet()      # 폭이 0 인 순간이라 안 보인다
		_last_mir_sign = ms
	var facing_vis := _last_mir_sign

	# 착지
	if not airborne and _was_airborne and on_floor:
		_puff(8)
		motion.kick("crouch", 1.4)
		motion.kick("squash", 1.0)
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

	# 몸이 간 거리 (뼈대 단위, 보이는 방향 기준 + = 앞)
	var dxw := _enemy.global_position.x - _last_x
	_last_x = _enemy.global_position.x
	if absf(dxw) > 200.0:
		dxw = 0.0   # 순간 이동 (방 이동·되살아남)
		motion.snap_feet()
	var dx_rig := dxw / maxf(gscale, 0.0001) * facing_vis
	var speed_rig := vx / maxf(gscale, 0.0001) * facing_vis

	# ---- 자세 고르기 ----
	var p := {}
	var drive := RigMotion.Drive.NORMAL
	var feet := RigMotion.Feet.POSE
	var ghost := false
	var drag := false
	var tremor := 0.0
	var tint := Color(1, 1, 1)
	var tint_strength := 0.0
	var breath := 1.0
	var lock := 0.0
	var settle := 0.0
	motion.tilt_scale = tilt_scale
	if airborne and st in LOCO_STATES:
		p = motion.pose("air")
		feet = RigMotion.Feet.AIR
		breath = 0.0
	else:
		match st:
			EnemyBase.State.IDLE:
				p = motion.pose("idle")
			EnemyBase.State.PATROL, EnemyBase.State.CHASE:
				p = motion.mix(motion.pose("idle"), motion.pose("walk"), clampf(absf(speed_rig) / maxf(motion.L * 0.8, 1.0), 0.0, 1.0))
				feet = RigMotion.Feet.GAIT
				breath = 0.4
			EnemyBase.State.BACKSTEP:
				p = motion.pose("backstep")
				feet = RigMotion.Feet.GAIT
				drive = RigMotion.Drive.QUICK
				breath = 0.0
			EnemyBase.State.ALERT:
				p = motion.pose("alert")
				drive = RigMotion.Drive.QUICK
			EnemyBase.State.LUNGE:
				p = motion.pose("lunge")
				feet = RigMotion.Feet.GAIT
				drive = RigMotion.Drive.QUICK
				ghost = true
				breath = 0.0
			EnemyBase.State.WINDUP:
				var wp := motion.pose("windup")
				if hint == "red" and motion.has_pose("charge"):
					wp = motion.mix(motion.pose("windup"), motion.pose("charge"), 0.5)
				p = motion.three_beat(_state_from, wp, motion.pose("strike"), motion.pose("ready"), "windup", _enemy.windup_progress)
				drive = RigMotion.Drive.SOFT
				tremor = clampf((_enemy.windup_progress - 0.6) / 0.4, 0.0, 1.0)
				tint = Color(1.6, 1.3, 0.9)
				tint_strength = 0.3 + 0.5 * _enemy.windup_progress
				breath = 0.0
				if hint == "red":
					tint = Color(2.4, 0.5, 0.4)
					tint_strength = 0.75
			EnemyBase.State.STRIKE:
				breath = 0.0
				match hint:
					"shoot":
						p = motion.pose("shoot")
					"scatter":
						var q := _enemy.phase_progress
						p = motion.pose("scatter_a") if q < 0.35 else motion.pose("scatter_b")
						if q >= 0.35 and not _scatter_popped:
							_scatter_popped = true
							_puff(8)
							motion.kick("squash", -1.5)
						drive = RigMotion.Drive.SETTLE
					"leap":
						p = motion.pose("leap")
						feet = RigMotion.Feet.AIR if airborne else RigMotion.Feet.POSE
						drive = RigMotion.Drive.QUICK
					"fall":
						p = motion.pose("slam_fall")
						feet = RigMotion.Feet.AIR if airborne else RigMotion.Feet.POSE
						drive = RigMotion.Drive.QUICK
					"charge":
						p = motion.pose("charge")
						feet = RigMotion.Feet.GAIT
						ghost = true
						drag = on_floor
						drive = RigMotion.Drive.QUICK
					_:
						# 타격: 예비 끝 자세에서 어깨가 먼저, 팔꿈치·무기가 늦게 채찍처럼 따라와 끝에서 지나친다. 앞발을 내딛는다.
						p = motion.three_beat(_state_from, motion.pose("windup"), motion.pose("strike"), motion.pose("ready"), "strike", _enemy.phase_progress)
						ghost = true
						drive = RigMotion.Drive.FAST
			EnemyBase.State.RECOVER:
				breath = 0.0
				match hint:
					"stuck":
						p = motion.pose("stuck")
						tremor = 0.8
					"land":
						p = motion.pose("land")
					_:
						p = motion.three_beat(_state_from, {}, {}, motion.pose("ready"), "recover", _enemy.phase_progress)
				drive = RigMotion.Drive.SETTLE
			EnemyBase.State.HIT:
				p = motion.pose("hit")
				drive = RigMotion.Drive.QUICK
				breath = 0.0
			EnemyBase.State.BROKEN:
				# 무너짐: 구원 가능한 자는 무릎을 꿇고 기다린다 (일어나지 않는다 — EnemyBase 도 구원 가능한 자는 무너진 채 둔다).
				# 아니면 두 무릎이 꺾여 처졌다가(흐트러짐 시간 뒤) 일어난다.
				if _enemy.savable:
					p = motion.pose("kneel")
				else:
					p = motion.pose("broken").duplicate()
					var sway := sin(_t * 1.5)
					p["torso"] = float(p["torso"]) + sway * 3.0
					p["head"] = float(p["head"]) + sin(_t * 1.5 + 0.8) * 4.0
					p["hip_y"] = float(p["hip_y"]) + (sway * 0.5 + 0.5) * 0.02
				drive = RigMotion.Drive.SOFT
				breath = 0.5
			EnemyBase.State.DEAD:
				breath = 0.0
				drive = RigMotion.Drive.HEAVY
				var e := _enemy.state_time
				var total := maxf(_enemy.phase_len, 0.3)
				if _enemy.savable and _fall_gentle:
					# 구원: 무릎 꿇은 채 몸을 일으키며 빛이 된다 (넘어지지 않는다)
					p = motion.pose("rescued")
					drive = RigMotion.Drive.SOFT
				else:
					# 쓰러짐. 앞으로(등 뒤에서 맞음·정화): 무릎이 꺾여 꿇고 → 꿇은 무릎을 축으로 허벅지째 엎어져 땅에 눕는다 (관절 자세만으로).
					# 뒤로(앞에서 맞아 밀림 — 흔한 경우): 무릎이 꺾여 엉덩방아를 찧고(발은 땅에 딛은 채) → 골반째 뒤로 굴러 등이 땅에 눕는다.
					# 뒤로는 내려놓기(ground_settle)가 몸의 가장 낮은 점을 땅에 붙이고 다리는 IK 로 딛은 발에 맞춘다 (무릎이 서고 발이 앞으로 차 나감).
					# 두 경우 모두 무게에 끌리듯 점점 빨리 떨어지고, 몸이 땅 아래로 들어가면 들어 올린다(ground_lock — 올리기만).
					# 쓰러짐 길이(0.75초)의 뒤 38% 동안 흩어져 사라진다.
					var u := e / total
					# 뒤로는 조금 일찍 눕는다 (엉덩방아는 무릎 꿇기보다 짧고, 흩어지기 전에 누운 모습이 보이게)
					var back := _fall_sign < 0.0
					var knees := Motion.ease_out(clampf(u / (0.26 if back else 0.32), 0.0, 1.0), 2.0)
					var slump := Motion.ease_in(clampf((u - (0.16 if back else 0.22)) / (0.32 if back else 0.38), 0.0, 1.0), 2.0)
					lock = 1.0
					# 거대화 몹의 '몸 기울기 줄이기'(tilt_scale)는 서 있는 동안만: 쓰러질 땐 끝까지 눕는다
					# (줄인 채면 엎어지는 기울기 78도가 35도가 되어 몸이 반쯤 선 채 칼끝이 하늘을 가리켰다 — 2026-10-20 검수)
					motion.tilt_scale = lerpf(tilt_scale, 1.0, knees)
					if _fall_sign > 0.0:
						p = motion.mix(motion.mix(_state_from, motion.pose("dead_knees"), knees), motion.pose("dead_lie"), slump)
						# 엎어지는 동안 내려놓기: 몸(가슴·머리·팔)이 땅에 닿을 때까지 엉덩이가 꿇은 무릎을 축으로 내려오거나 올라간다
						# (RigMotion: 무릎은 땅에 남는다 — 몸이 얇으면 허벅지가 눕고, 두꺼우면 허벅지가 서서 엉덩이가 들린다)
						settle = slump
					else:
						p = motion.mix(motion.mix(_state_from, motion.pose("dead_back"), knees), motion.pose("dead_back_lie"), slump)
						settle = knees
					if slump >= 1.0 and not _thud_done:
						_thud_done = true
						motion.kick("thud", 8.0)
						motion.kick("impact", -_fall_sign * 40.0)
						_puff(10)
					drive = RigMotion.Drive.QUICK
				if _fall_gentle:
					tint = Color(1.9, 1.75, 1.35)
				else:
					tint = Color(0.35, 0.33, 0.36)
				tint_strength = 1.0
	motion.fall_angle = 0.0
	motion.ground_lock = lock
	motion.ground_settle = settle
	motion.breath = breath
	motion.set_target(p, drive, feet)
	if _aim_i >= 0 and st in AIM_STATES:
		_aim_gun(st)   # 폴짝 물러나는 공중에서도 겨눈다 (예전 그림과 같게)
	motion.update(delta, {"speed": speed_rig, "dx": dx_rig, "vy": _enemy.velocity.y / maxf(gscale, 0.0001), "grounded": on_floor or not airborne})

	# 떨림·반동·번쩍임 (덧붙임)
	_tremor = Motion.damp(_tremor, tremor, 30.0, delta)
	_recoil = maxf(_recoil - delta * 6.0, 0.0)
	_strike_flash = maxf(_strike_flash - delta * 12.0, 0.0)
	_block_flash = maxf(_block_flash - delta * 9.0, 0.0)
	var sq := clampf(motion.spring_value("squash"), -0.25, 0.3) * 0.1
	var shake := sin(_t * 45.0) * 1.2 * _tremor
	rig.position = Vector2(shake, _floor_y)
	var mir_w := _last_mir_sign * lerpf(turn_min_width, 1.0, absf(_mir.v))
	rig.scale = Vector2(mir_w * art_scale * (1.0 + sq), art_scale * (1.0 - sq))
	# 디딤 먼지
	if absf(vx) > 80.0 and on_floor:
		for leg in motion.legs:
			if leg.planted_now:
				_step_puff(leg.x * gscale * facing_vis)
	# 잔상
	if ghost:
		_ghost_timer += delta
		if _ghost_timer >= GHOST_INTERVAL:
			_ghost_timer = 0.0
			rig.snapshot_ghost(Color(1.0, 0.9, 0.7, 0.35))
	else:
		_ghost_timer = 0.0
	rig.fade_ghosts(delta)
	if _drag.emitting != drag:
		_drag.emitting = drag
	if drag:
		_drag.global_position = _enemy.global_position + Vector2(-float(_enemy.facing) * 20.0, _floor_y)

	# ---- 색 ----
	var tint_speed := 6.0 if st == EnemyBase.State.DEAD else 18.0
	_tint_strength = Motion.damp(_tint_strength, tint_strength, tint_speed, delta)
	var pulse := 1.0
	if st == EnemyBase.State.WINDUP:
		pulse = 0.5 + 0.5 * sin(_t * (32.0 if hint == "red" else 30.0))
	var target_col := Color(1, 1, 1).lerp(tint, _tint_strength * pulse)
	_col = _col.lerp(target_col, 1.0 - exp(-24.0 * delta))
	var alpha := 1.0
	if st == EnemyBase.State.DEAD:
		# 땅에 누운 뒤(뒤 38%) 흩어져 사라진다: 쓰러짐은 잿빛 재, 정화·구원은 빛 (투명도로 흐리면 겹친 부위가 비친다)
		var dz := Motion.ease_in(clampf((_enemy.phase_progress - 0.62) / 0.38, 0.0, 1.0), 1.3)
		if _enemy.savable and _fall_gentle:
			dz = Motion.ease_in(clampf((_enemy.phase_progress - 0.3) / 0.7, 0.0, 1.0), 1.2)
		rig.set_dissolve(dz, Color(2.2, 1.9, 1.2) if _fall_gentle else Color(0.9, 0.55, 0.3))
		alpha = 1.0 - dz
	elif rig.dissolve_amount() > 0.0:
		rig.set_dissolve(0.0)
	var shown := _col
	rig.modulate = shown
	var fl := _enemy.flash_amount()
	# 피격은 하얗게, 타격 첫 순간은 옅은 금빛, 방패로 막음은 푸른빛 (가장 센 것 하나)
	var flash := fl * 0.75
	var fcol := Color(1.3, 1.27, 1.2)
	if _strike_flash * 0.45 > flash:
		flash = _strike_flash * 0.45
		fcol = Color(1.4, 1.25, 0.95)
	if _block_flash * 0.7 > flash:
		flash = _block_flash * 0.7
		fcol = Color(1.5, 1.9, 2.3)
	rig.set_flash(flash, fcol)
	_label.visible = st == EnemyBase.State.BROKEN
	if _label.visible:
		_label.text = "%s  %s" % [InputDevice.prompt("interact"), "구원의 손길" if _enemy.savable else "정화의 손길"]
	if _glow:
		var gp := 0.7 + 0.3 * sin(_t * 2.5)
		# 얼굴 그림이 있으니 예전(한 장 그림)보다 작고 옅게 — 얼굴을 가리지 않는 눈가의 온기
		_glow.modulate = Color(1.5, 1.3, 0.95, 0.55 * alpha) * gp
		_glow.scale = Vector2(0.5, 0.5) * gp
	# 머리 위 표시는 값이 바뀔 때만 다시 그린다 (몹마다 매 프레임 그리지 않게). "!" 가 떠 있는 동안만 매 프레임.
	var want_bar := show_overhead_bar and st != EnemyBase.State.DEAD and (_enemy.hp < _enemy.max_hp or _enemy.poise > 0.0 or st == EnemyBase.State.BROKEN)
	var alert_on := _alert_t >= 0.0 and _alert_t < 0.6 and st != EnemyBase.State.DEAD
	var sig := Vector3(_enemy.hp if want_bar else -1.0, _enemy.poise if want_bar else -1.0, 1.0 if alert_on else 0.0)
	if alert_on or sig != _overlay_sig:
		_overlay_sig = sig
		_overlay.queue_redraw()
	if st == EnemyBase.State.BROKEN or _underlay_on:
		_underlay.queue_redraw()
	_underlay_on = st == EnemyBase.State.BROKEN


## 화면 밖에서 가만히 서 있거나 거니는 몹은 뼈대를 움직이지 않는다 (모바일 비용 — 방 하나에 몹 그림만 매 프레임 약 1ms 를 썼다,
## 2026-10-20 검수). 싸움·쓰러짐 같은 상태는 화면 밖에서도 그대로 움직인다 (돌아왔을 때 자세가 튀지 않게).
## 보는 방향만은 맞춰 둔다 (경비병 방패 판정이 is_facing_settled 를 본다). 화면 없는 시험(headless)에서는 끈다.
func _cull_quiet() -> bool:
	if _notifier == null:
		return false
	if _notifier_scale != art_scale:
		# 크기가 바뀌면(거대화는 _ready 뒤에 키운다) 사각형도 다시
		_notifier_scale = art_scale
		var h := float(rig.data.get("height", 1000.0)) * rig.game_scale * art_scale
		_notifier.rect = Rect2(-h * 1.3, -h * 1.6, h * 2.6, h * 2.3)
	var quiet := _enemy.state == EnemyBase.State.IDLE or _enemy.state == EnemyBase.State.PATROL
	if quiet and not _notifier.is_on_screen():
		_culled = true
		_face_target = _enemy.facing
		_mir.v = 1.0 if _enemy.facing > 0 else -1.0
		_last_mir_sign = signf(_mir.v)
		_last_x = _enemy.global_position.x
		return true
	if _culled:
		_culled = false
		motion.snap_feet()
	return false


## 대롱(gun): 소녀를 겨눈다 (EnemySpriteVisual 의 겨눔과 같은 상태·한계). 상태 자세 대신 위팔 목표를 고쳐
## 대롱 뼈의 축이 소녀 가슴 쪽을 향하게 한다. 팔꿈치·손목은 자세 그대로라 '위팔을 이만큼 더 돌리면 대롱이 그만큼 돈다'로 바로 푼다
## (지난 프레임의 실제 각도로 풀어도 위팔 값이 서로 지워져 되먹임 떨림이 없다). 피격·반동 같은 덧붙임은 빼고 풀어 반동은 그대로 보인다.
func _aim_gun(st: int) -> void:
	var pl := _enemy.player
	if pl == null or not is_instance_valid(pl):
		return
	var hand := rig.to_global(rig.bone_point(aim_bone))
	var to: Vector2 = pl.global_position + Vector2(0, -40) - hand
	# 뼈대 틀(늘 오른쪽을 봄)의 겨눌 각도: 0 = 앞 수평, + = 아래. 뒤쪽이면 앞쪽으로 접어 생각한다 (곧 돌아선다).
	var want := clampf(atan2(to.y, maxf(absf(to.x), 1.0)), AIM_UP, AIM_DOWN)
	if st == EnemyBase.State.WINDUP:
		want -= AIM_WINDUP_RAISE
	var axis := (rig.body_xf * rig.xf[_aim_i]).basis_xform(Vector2.DOWN).angle()
	var chan := deg_to_rad(motion.channel("arm_f_up"))
	var extra := rig.bone_rot(_aim_arm) - chan    # 덧붙임(숨쉬기·피격·반동)
	var err := wrapf(want - (axis - extra), -PI, PI)
	motion.target["arm_f_up"] = rad_to_deg(chan + err)


## 상태 진입 1회: 그 순간 보이던 자세를 기억(예비·되돌림·무너짐이 여기서 출발)하고, 먼지·번쩍임·섞기 길이를 정한다.
func _on_entered(st: int, hint: String) -> void:
	_state_from = motion.capture()
	var fade := 0.1
	match st:
		EnemyBase.State.WINDUP, EnemyBase.State.STRIKE, EnemyBase.State.RECOVER:
			fade = 0.0     # 세 박자 곡선이 지금 자세에서 출발한다
		EnemyBase.State.HIT, EnemyBase.State.LUNGE, EnemyBase.State.ALERT:
			fade = 0.06
		EnemyBase.State.BROKEN, EnemyBase.State.DEAD:
			fade = 0.12
	if _from_state == EnemyBase.State.BROKEN:
		fade = maxf(fade, 0.3)     # 무너졌다 일어날 때는 천천히
	_from_state = st
	motion.transition(fade)
	match st:
		EnemyBase.State.STRIKE:
			if hint in ["", "charge"]:
				_strike_flash = 1.0
				_puff(6)
			elif hint == "leap":
				_puff(10)
			_scatter_popped = false
		EnemyBase.State.LUNGE:
			_puff(4)


## 몸 충돌(캡슐)의 바닥 = 발이 닿는 땅 (적 원점 기준). 없으면 hurt_height 의 절반.
func _find_floor_y() -> float:
	for c in _enemy.get_children():
		if c is CollisionShape2D and c.shape is CapsuleShape2D and absf(c.rotation) < 0.1:
			return c.position.y + (c.shape as CapsuleShape2D).height * 0.5
	return _enemy.hurt_height * 0.5


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


func _puff(n: int) -> void:
	var k := clampf(float(n) / 12.0, 0.4, 1.4) * sqrt(art_scale)
	_dust.initial_velocity_min = 50.0 * k
	_dust.initial_velocity_max = 150.0 * k
	_dust.scale_amount_min = 2.5 * k
	_dust.scale_amount_max = 5.5 * k
	_dust.position = Vector2(0, _floor_y)
	_dust.restart()
	_dust.emitting = true


func _step_puff(x := 0.0) -> void:
	_step_dust.position = Vector2(x, _floor_y)
	_step_dust.restart()
	_step_dust.emitting = true


## 머리 위 표시 (뼈대 위에 그린다): 발견 "!", 체력·흐트러짐 막대, 무너짐 빛
func _draw_overlay() -> void:
	if _enemy == null or rig == null:
		return
	var st := _enemy.state
	if st == EnemyBase.State.DEAD:
		return
	if _alert_t >= 0.0 and _alert_t < 0.6:
		var top := rig.highest_y() * rig.game_scale * art_scale + _floor_y
		var top_y := minf(top, -_enemy.hurt_height * 0.5) - 10.0
		var font := ThemeDB.fallback_font
		var a := 1.0 - _alert_t / 0.6
		_overlay.draw_string(font, Vector2(-8, top_y - 40.0 - _alert_t * 30.0), "!", HORIZONTAL_ALIGNMENT_CENTER, 16, 44, Color(1.0, 0.85, 0.5, a))
	if show_overhead_bar and (_enemy.hp < _enemy.max_hp or _enemy.poise > 0.0 or st == EnemyBase.State.BROKEN):
		var w := 90.0
		var bar := Vector2(-w / 2.0, -_enemy.hurt_height - 40.0)
		_overlay.draw_rect(Rect2(bar, Vector2(w, 7)), Color(0, 0, 0, 0.6))
		_overlay.draw_rect(Rect2(bar, Vector2(w * _enemy.hp / _enemy.max_hp, 7)), Color("9bd48a"))
		_overlay.draw_rect(Rect2(bar + Vector2(0, 10), Vector2(w, 5)), Color(0, 0, 0, 0.6))
		_overlay.draw_rect(Rect2(bar + Vector2(0, 10), Vector2(w * _enemy.poise / _enemy.max_poise, 5)), Color("8fd3ff"))


## 뼈대 뒤에 그리는 것: 무너짐(정화할 수 있음)의 옅은 빛
func _draw_underlay() -> void:
	if _enemy and _enemy.state == EnemyBase.State.BROKEN:
		var pulse := 0.6 + 0.4 * sin(_t * 5.0)
		_underlay.draw_circle(Vector2(0, _floor_y - _enemy.hurt_height * 0.45), 60.0 * art_scale, Color("8fd3ff", 0.08 * pulse))

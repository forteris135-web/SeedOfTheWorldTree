extends Node2D
## 무쇠 펌프의 그림 (2026-10-20 리뉴얼). 기획자의 부위 시트(익스펜션/그림/보스/02E4EA0A…)를 잘라 만든 부위 뼈대
## (PartRig — art/rigs/iron_pump, 설계도 data/rigs/iron_pump.json, 자세 data/rigs/_archetypes/iron_pump.json)를
## 움직임 층(RigMotion)으로 움직인다. 예전에는 임시 그림 한 장을 통째로 기울이고 눌러서 '판때기'처럼 보였다 — 이제 관절로 선다:
##  - 몸통(핵 창·탱크) 아래 **무릎이 뒤로 꺾이는 기계 다리 둘**: 디딘 발은 땅에 고정, 두 마디 IK. 걸음마다 쿵 — 몸이 내려앉고
##    앞뒤로 흔들리며 발밑에 먼지. 서 있어도 매 박(보스곡 128bpm)마다 '쿵' 하고 들썩이고, 등 위 관 팔이 펌프처럼 끄덕인다.
##  - 흡입 팔(위팔 → 아래팔, 끝에 쇠창살 입): **피스톤 내려찍기** = 팔을 하늘로 치켜들고 멈칫(붉게 떨림) → 앞 땅에 내리꽂고
##    몸이 앞으로 쏠림(먼지·불꽃) → 출렁이며 제자리. **빨아들이기** = 입을 소녀에게 겨누고 떨며 들이마심(수액빛 띠) → 끝에 덥석 문다.
##  - 수액 대포(몸 앞 아래): **수액 분사** = 흡입 팔을 땅에 짚어 버팀(받침대) → 대포가 소녀를 겨누고 한 발마다 크게 튀어 오르는 반동,
##    몸이 뒤로 밀리고 관 팔이 출렁임.
##  - 2페이즈: 규칙이 무너진다 — 박이 엇나가고(짧았다 길었다·두 번 쿵), 동작이 멈칫멈칫 끊겼다가 확 따라잡고, 경련하듯 튄다.
##    이음새마다 수액이 샌다.
##  - 장갑 깨짐(BROKEN): 무릎이 꺾여 주저앉고 팔·대포·관이 늘어지며, 핵 창이 터질 듯 밝게 맥동(빛살)하고 김이 샌다.
##  - 쓰러짐: 경련 → 다리가 꺾이며 발이 밖으로 미끄러지고 → 몸이 땅에 '쿵' 떨어져 살짝 튀었다가 → 엎드려 눕는다.
##    핵이 꺼져 가며 마지막 박동 몇 번. 정화를 기다리는 동안 그 자세 그대로(몸이 땅에 박히거나 뜨지 않는다).
##  - 정화: 핵이 맑은 초록빛으로 바뀌고 몸이 빛으로 흩어진다 (그 자리에 멈춘 펌프 PumpRemains 가 같은 자세로 남는다 — iron_pump_room).
## 보스 논리(iron_pump.gd)는 그대로다 — 그림이 상태·단계·진행도(phase_progress)를 읽어 따라간다 (판정·시간은 건드리지 않는다).
## 좌우: 뼈대는 늘 오른쪽을 본다. 이 노드의 scale.x 가 1 → 0 → −1 을 지나며 몸을 튼다 (뒤집는 순간 딛은 발을 세상에 남긴다).
## 이 노드의 원점 = 보스 발밑 땅 (CharacterBody2D 원점 = 몸 충돌 캡슐의 바닥).
## 세기 조절: 아래 상수들과 자세 파일.

const RIG_ID := "iron_pump"
const BEAT := 60.0 / 128.0
## 몸 틀기 빠르기 (1/s)
const TURN_SPEED := 7.0
## 피스톤 예고 중 '치켜들고 멈칫' 이 끝나고 내리치기 시작하는 진행도 (예고 끝 몫에서 팔이 떨어져 실행 순간에 땅에 닿는다)
const SLAM_DROP := 0.82
## 쓰러짐 순서 (FALLEN 이 된 뒤 초): 경련 → 다리가 꺾임 → 몸이 땅에 부딪힘 → 다 누움
const FALL_JOLT := 0.3
const FALL_BUCKLE := 0.95
const FALL_CRASH := 1.22
const FALL_REST := 2.2
## 등장: 잠든 자세 → 깨어남 → 포효(팔을 치켜듦) → 내려찍듯 자리 잡기 (INTRO 2.2초 안)
const INTRO_WAKE := 0.45
const INTRO_RISE := 1.05
const INTRO_ROAR := 1.5
const INTRO_LAND := 1.85
## 대포 겨눔 한계 (축 각도, 도: −90 = 앞 수평, 더 작으면 위로)
const CANNON_UP := -128.0
const CANNON_DOWN := -46.0
## 빨아들이기: 아래팔 겨눔 한계 (위팔 틀 기준, 도)
const SUCK_LO_MIN := -72.0
const SUCK_LO_MAX := 30.0
## 색
const CORE_AMBER := Color(1.0, 0.68, 0.34)
const CORE_GREEN := Color(0.62, 1.0, 0.72)
const SAP := Color(0.35, 0.82, 0.88)
const RED_HOT := Color(1.9, 0.62, 0.5)
## 일회성 효과 표시 (상태가 바뀌면 지운다)
const ONCE_ROAR := 1
const ONCE_LAND := 2

var boss: IronPump
var rig: PartRig
var motion: RigMotion
## 그림 배율 (1 = 설계도 game_scale)
@export var art_scale := 1.0

var _i_body := -1
var _i_arm_up := -1
var _i_arm_lo := -1
var _i_cannon := -1
var _cannon_only := PackedInt32Array()
var _k := 0.49             # 뼈대 단위 → 게임 px
var _sock := {}            # 소켓 이름 → [뼈 번호, 뼈 틀 자리]

var _t := 0.0
var _state_t := 0.0
var _prev_state := -1
var _prev_phase := ""
var _prev_flash := 0.0
var _from := {}            # 지금 동작이 시작될 때 보이던 자세 (예고·쓰러짐의 출발)
var _out := {}             # 이번 프레임 목표 (돌려 쓴다)
var _info := {}            # 이번 프레임 상태 정보 (돌려 쓴다)
var _ctx := {"speed": 0.0, "dx": 0.0, "vy": 0.0, "grounded": true}
var _stream_on := false
var _face := -1.0
var _sign := -1.0
var _prev_x := 0.0
var _visible_prev := false
var _once := 0
## 박: 다음 '쿵' 까지 흐른 시간과 그 길이. 2페이즈엔 길이가 들쭉날쭉하다.
var _beat_t := 0.0
var _beat_len := BEAT
var _beat_n := 0
var _beat_amp := 1.0
var _pump_ph := 0.0        # 관 팔 끄덕임 위상 (박마다 반 바퀴)
var _death_beats := 0      # 쓰러진 뒤 남은 마지막 박동 수
## 2페이즈 멈칫거림: 남은 멈춤 시간, 다음 멈춤까지, 멈춘 자세, 따라잡기(빠른 스프링) 남은 시간
var _stut_hold := 0.0
var _stut_next := 0.6
var _stut_pose := {}
var _snap_t := 0.0
## 땅을 디딘 발의 흔들림 (앞발 = 앞으로 쏠림, 뒷발 = 뒤로) — 값·속도 (lean 에 더한다, 도)
var _rock := 0.0
var _rock_v := 0.0
## 몸이 땅에 부딪혀 튀는 높이 (게임 px) — 값·속도
var _bounce := 0.0
var _bounce_v := 0.0
var _tremble := 0.0
var _core := 0.4
var _core_kick := 0.0
var _red := 0.0
var _purify := 0.0
var _ghost_timer := 0.0
var _crashed := false
var _bite_pose := false
var _steam_t := 0.0
## 관 팔이 홱 튀는 값 (2페이즈 수액이 샐 때) — 값·속도 (도)
var _pipe_jerk := 0.0
var _pipe_jerk_v := 0.0

var _dust: Array[CPUParticles2D] = []
var _dust_next := 0
var _sparks: CPUParticles2D
var _steam: CPUParticles2D      # 관 팔 끝 (박마다 한 줌)
var _vent: CPUParticles2D       # 몸통 위 김 (장갑 깨짐·쓰러짐)
var _drips: CPUParticles2D      # 2페이즈: 이음새마다 새는 수액
var _inhale: CPUParticles2D     # 빨아들이기
var _muzzle_smoke: CPUParticles2D
var _motes: CPUParticles2D      # 정화: 솟아오르는 빛 가루
var _spray: CPUParticles2D      # 2페이즈: 관 팔 끝에서 뿜는 수액
var _core_glow: Sprite2D
var _mouth_glow: Sprite2D
var _muzzle_glow: Sprite2D
var _muzzle_a := 0.0
var _rays: Node2D               # 장갑 깨짐: 핵 창에서 새어 나오는 빛살
var _stream: Node2D             # 빨아들이기 띠 (세상 좌표)
var _light: PointLight2D
var _red_sprites: Array[Sprite2D] = []

var _glow_tex: Texture2D


func _ready() -> void:
	boss = get_parent() as IronPump
	rig = PartRig.new()
	rig.name = "Rig"
	add_child(rig)
	if not rig.build(RIG_ID):
		push_error("무쇠 펌프 뼈대를 만들지 못했다")
		set_process(false)
		return
	rig.scale = Vector2(art_scale, art_scale)
	_k = rig.game_scale * art_scale
	_i_body = rig.bone_index("body")
	_i_arm_up = rig.bone_index("arm_up")
	_i_arm_lo = rig.bone_index("arm_lo")
	_i_cannon = rig.bone_index("cannon")
	_cannon_only = PackedInt32Array([_i_cannon])
	for bn in ["arm_up", "arm_lo"]:
		var spr := rig.sprite_of(bn)
		if spr:
			_red_sprites.append(spr)
	var socks: Dictionary = rig.data.get("sockets", {})
	for sname in socks:
		var sd: Dictionary = socks[sname]
		_sock[sname] = [rig.bone_index(str(sd["bone"])), PartRig._v(sd["pos"])]
	motion = RigMotion.new(rig)
	motion.breath = 0.0   # 숨 대신 박마다 '쿵' (아래 _beat)
	rig.setup_ghosts(["arm_up", "arm_lo"], 5)
	if boss:
		_face = float(boss.facing)
		_sign = signf(_face)
		_prev_x = boss.global_position.x
		_light = boss.get_node_or_null("Light") as PointLight2D
		boss.state_changed.connect(_on_state_changed)
		boss.shot.connect(_on_shot)
		boss.slammed.connect(_on_slammed)
		boss.phase_changed.connect(_on_phase_changed)
	scale = Vector2(_face, 1.0)
	_make_effects()
	_snap_to("dormant")


# ---------- 효과 만들기 ----------

func _make_effects() -> void:
	if _glow_tex == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.08), Color(1, 1, 1, 0)])
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
	# 핵 창의 빛 (HDR 1 넘김 → 글로우가 번진다). 뼈를 따라간다.
	_core_glow = _glow_sprite(add, 4.2)
	_attach_sock("core", _core_glow)
	_mouth_glow = _glow_sprite(add, 2.2)
	_attach_sock("mouth", _mouth_glow)
	_muzzle_glow = _glow_sprite(add, 1.8)
	_attach_sock("muzzle", _muzzle_glow)
	_rays = Node2D.new()
	_rays.name = "CoreRays"
	_rays.material = add
	_rays.visible = false
	_rays.z_index = 1
	_rays.draw.connect(_draw_rays)
	_attach_sock("core", _rays)
	_stream = Node2D.new()
	_stream.name = "SuckStream"
	_stream.top_level = true
	_stream.z_index = 2
	_stream.material = add
	_stream.draw.connect(_draw_suck_stream)
	add_child(_stream)
	for i in 3:
		var d := _particles(14, 0.75, Vector2(0, -1), 70.0, Vector2(0, 260), 60.0, 220.0, 5.0, 12.0, Color(0.58, 0.48, 0.4, 0.55), false)
		d.top_level = true
		d.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		d.emission_rect_extents = Vector2(40, 4)
		_dust.append(d)
	_sparks = _particles(16, 0.7, Vector2(0, -1), 80.0, Vector2(0, 520), 160.0, 440.0, 2.0, 4.5, Color(1.0, 0.75, 0.3, 0.95), true)
	_sparks.top_level = true
	_steam = _particles(10, 1.3, Vector2(0, 1), 22.0, Vector2(0, -60), 40.0, 110.0, 6.0, 15.0, Color(0.85, 0.88, 0.88, 0.32), false)
	_steam.one_shot = false
	_steam.explosiveness = 0.0
	_steam.local_coords = false
	_attach_sock("outlet", _steam)
	_vent = _particles(16, 1.6, Vector2(0, -1), 30.0, Vector2(8, -50), 30.0, 90.0, 9.0, 20.0, Color(0.85, 0.85, 0.85, 0.28), false)
	_vent.one_shot = false
	_vent.explosiveness = 0.0
	_vent.local_coords = false
	_vent.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_vent.emission_rect_extents = Vector2(60, 10)
	_attach_sock("core", _vent, Vector2(0, -70))
	_drips = _particles(12, 1.1, Vector2(0, 1), 6.0, Vector2(0, 900), 10.0, 40.0, 3.0, 6.0, Color(1.0, 0.72, 0.36, 0.85), true)
	_drips.one_shot = false
	_drips.explosiveness = 0.0
	_drips.local_coords = false
	_drips.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_drips.emission_rect_extents = Vector2(120, 8)
	_attach_sock("core", _drips, Vector2(0, 50))
	_muzzle_smoke = _particles(10, 0.7, Vector2(1, -0.3), 25.0, Vector2(0, -60), 120.0, 320.0, 6.0, 13.0, Color(0.8, 0.9, 0.9, 0.4), false)
	_muzzle_smoke.top_level = true
	_spray = _particles(22, 1.0, Vector2(0, -1), 28.0, Vector2(0, 980), 260.0, 520.0, 5.0, 10.0, Color(1.0, 0.72, 0.36, 0.95), true)
	_spray.top_level = true
	_motes = _particles(40, 1.8, Vector2(0, -1), 70.0, Vector2(0, -90), 60.0, 200.0, 5.0, 12.0, Color(0.75, 1.0, 0.8, 0.9), true)
	_motes.top_level = true
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(200, 60)
	_inhale = CPUParticles2D.new()
	_inhale.emitting = false
	_inhale.amount = 48
	_inhale.lifetime = 0.55
	_inhale.local_coords = false
	_inhale.top_level = true
	_inhale.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_inhale.emission_rect_extents = Vector2(40, 110)
	_inhale.direction = Vector2(1, 0)
	_inhale.spread = 8.0
	_inhale.gravity = Vector2.ZERO
	_inhale.initial_velocity_min = 520.0
	_inhale.initial_velocity_max = 860.0
	_inhale.texture = _glow_tex
	_inhale.scale_amount_min = 7.0 / 26.0
	_inhale.scale_amount_max = 14.0 / 26.0
	_inhale.color = Color(SAP, 0.8)
	_inhale.material = add
	add_child(_inhale)


func _glow_sprite(mat: Material, size: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _glow_tex
	s.material = mat
	s.scale = Vector2.ONE * size
	s.modulate = Color(1, 1, 1, 0)
	s.z_index = 1
	return s


## 소켓(설계도 sockets)에 노드를 붙인다: 뼈를 따라 자리만 옮긴다 (회전은 따라가지 않는다). extra = 소켓에서 게임 px 만큼 더.
func _attach_sock(sname: String, node: Node2D, extra := Vector2.ZERO) -> void:
	if not _sock.has(sname):
		add_child(node)
		return
	var sk: Array = _sock[sname]
	rig.attach(rig.names[int(sk[0])], node, (sk[1] as Vector2) + extra / _k)


func _particles(n: int, life: float, dir: Vector2, spread: float, grav: Vector2, v0: float, v1: float, s0: float, s1: float, col: Color, additive: bool) -> CPUParticles2D:
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
	# 부드러운 둥근 알갱이 (텍스처 64px 의 빛 방울 — 네모 알갱이가 싸 보이지 않게). s0·s1 은 보이는 지름(px)쯤.
	p.texture = _glow_tex
	p.scale_amount_min = s0 / 26.0
	p.scale_amount_max = s1 / 26.0
	p.color = col
	if additive:
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = add
	add_child(p)
	return p


# ---------- 사건 ----------

func _on_state_changed(st: IronPump.State) -> void:
	match st:
		IronPump.State.INTRO:
			_snap_to("dormant")
			_core = 0.0
			_beat_t = 0.0
			_beat_len = BEAT
			_purify = 0.0
			rig.set_dissolve(0.0)
			_crashed = false
		IronPump.State.STAGGER:
			motion.kick("impact", 90.0)
			_spark_burst(14, _sock_global("core"))
			_vent_burst()
		IronPump.State.BROKEN:
			motion.kick("impact", 70.0)
			motion.kick("crouch", 1.2)
			_spark_burst(16, _sock_global("core"))
			_puff(12, global_position)
			Sfx.play("guard_break", -2.0, 0.05)
		IronPump.State.FALLEN:
			motion.kick("impact", 120.0)
			_spark_burst(16, _sock_global("core"))
			_death_beats = 3
			_crashed = false
		IronPump.State.PURIFIED:
			# 정화: 핵에서 맑은 빛 가루가 솟아 흩어진다 (몸은 BossRoom 이 밝게 지우고, 그 자리에 멈춘 펌프가 남는다)
			_motes.global_position = _sock_global("core")
			_motes.restart()
			_motes.emitting = true


func _on_shot() -> void:
	# 대포 반동: 대포가 위로 튀고 몸이 뒤로 밀리며 관 팔이 출렁인다
	motion.kick("recoil", 300.0)
	motion.kick("shove", -1.1)
	motion.kick("crouch", 0.5)
	_rock_v -= 2.5
	_muzzle_a = 1.0
	_muzzle_smoke.global_position = _sock_global("muzzle")
	_muzzle_smoke.direction = Vector2(_sign, -0.25)
	_muzzle_smoke.restart()
	_muzzle_smoke.emitting = true
	Juice.shake(2.5)


func _on_slammed() -> void:
	# 피스톤이 땅을 쳤다: 입 자리에 먼지·불꽃, 몸이 쿵 내려앉고 팔이 살짝 튀어 오른다
	var at := _sock_global("mouth")
	at.y = global_position.y
	_puff(26, at)
	_spark_burst(14, at + Vector2(0, -20))
	motion.kick("crouch", 1.6)
	motion.kick("parry", 70.0)
	_rock_v += 4.0
	_core_kick = 0.8


func _on_phase_changed(ph: int) -> void:
	if ph == 2:
		_vent_burst()
		_spark_burst(16, _sock_global("core"))
		_stut_next = 0.05   # 곧바로 한 번 멈칫


## 자세를 바로 그 자리로 (보이기 시작할 때·처음)
func _snap_to(pose_name: String) -> void:
	if motion == null:
		return
	motion.transition(0.0)
	motion.set_target(motion.pose(pose_name), RigMotion.Drive.NORMAL, RigMotion.Feet.POSE)
	motion.snap_feet()
	motion.ground_lock = 0.0
	motion.ground_settle = 0.0
	motion.update(0.0, {})
	rig.hide_ghosts()
	_from = motion.capture()


# ---------- 매 프레임 ----------

func _process(delta: float) -> void:
	if boss == null or motion == null:
		return
	if not boss.visible:
		if _visible_prev:
			_stream.queue_redraw()   # 빨아들이던 띠가 다음 싸움에 남아 보이지 않게
			_inhale.emitting = false
		_visible_prev = false
		return
	delta = minf(delta, 0.05)
	_t += delta
	var st := boss.state
	if not _visible_prev:
		_visible_prev = true
		_prev_x = boss.global_position.x
	if st != _prev_state:
		_state_t = 0.0
		_prev_state = st
		_once = 0
		_from = motion.capture()
		motion.transition(0.16)
	else:
		_state_t += delta
	var ph := boss.attack_phase
	if ph != _prev_phase:
		if ph != "":
			_from = motion.capture()
		if _prev_phase == "active" and ph == "recovery" and boss.phase == 2:
			_leak_fx()
		_prev_phase = ph
	# 몸 틀기: 1 → 0 → −1 (뒤집는 순간 딛은 발을 세상에 남긴다)
	_face = Motion.damp(_face, float(boss.facing), TURN_SPEED, delta)
	var fx := _face
	if absf(fx) < 0.04:
		fx = 0.04 * (1.0 if fx >= 0.0 else -1.0)
	var s := signf(fx)
	if s != _sign:
		_sign = s
		motion.flip_feet()
	scale = Vector2(fx, 1.0)
	# 목표 자세
	var info := _info
	info["drive"] = RigMotion.Drive.NORMAL
	info["feet"] = RigMotion.Feet.POSE
	info["tremble"] = 0.0
	info["core"] = 0.45
	info["beat"] = 1.0
	info["ghost"] = false
	var pose := _pose_now(st, info)
	pose = _stutter(pose, delta, info)
	_beat(delta, st, float(info["beat"]))
	# 덧붙임: 박 끄덕임(관 팔), 발 디딤 흔들림 — 자세 사전은 원형의 것을 함께 쓰므로 돌려 쓰는 사전에 옮겨 더한다
	for key in pose:
		_out[key] = pose[key]
	var pj := Motion.spring(_pipe_jerk, 0.0, _pipe_jerk_v, 180.0, 9.0, delta)
	_pipe_jerk = pj[0]
	_pipe_jerk_v = pj[1]
	_out["pipe"] = float(pose.get("pipe", 0.0)) + sin(_pump_ph) * 7.0 * _beat_amp * float(info["beat"]) + _pipe_jerk
	_out["lean"] = float(pose.get("lean", 0.0)) + _rock
	var drive: int = info["drive"]
	if _snap_t > 0.0:
		_snap_t -= delta
		drive = RigMotion.Drive.QUICK
	motion.set_target(_out, drive, info["feet"])
	# 몸이 간 거리 (뼈대 단위, 보는 쪽 + 앞)
	var dxw := boss.global_position.x - _prev_x
	_prev_x = boss.global_position.x
	if absf(dxw) > 200.0:
		dxw = 0.0
		motion.snap_feet()   # 순간이동 (싸움 다시 시작)
	_ctx["speed"] = boss.velocity.x * _sign / _k
	_ctx["dx"] = dxw * _sign / _k
	motion.update(delta, _ctx)
	_guard_cannon()
	_after_update(delta, st, info)


## 대포 땅 막기: 늘어진 대포(장갑 깨짐·잠든 자세 등)의 끝이 땅에 파고들면 들어 올려 땅 위에 얹는다
## (RigMotion 의 땅 막기는 흡입 팔 사슬만 지킨다 — 대포는 여기서 따로).
func _guard_cannon() -> void:
	if _i_cannon < 0:
		return
	var fixed := false
	for it in 24:
		if rig.lowest_y(_cannon_only) < -3.0:
			break
		rig.rot[_i_cannon] -= 0.06   # 위로(앞쪽으로) 들어 올린다 (최대 약 80도)
		rig.compute_from(_i_cannon)
		fixed = true
	if fixed:
		rig.apply()


## 상태 → 목표 자세. info 에 보간 방식·발 방식·떨림·핵 밝기·박 세기를 적는다.
func _pose_now(st: IronPump.State, info: Dictionary) -> Dictionary:
	var phase2 := boss.phase == 2
	motion.ground_lock = 0.0
	motion.ground_settle = 0.0
	match st:
		IronPump.State.INTRO:
			return _intro_pose(info)
		IronPump.State.IDLE:
			var spd := absf(boss.velocity.x)
			var w := clampf(spd / maxf(boss.crawl_speed, 1.0), 0.0, 1.0)
			var p := motion.mix(motion.pose("idle"), motion.pose("walk"), w)
			if phase2:
				p["lean"] = float(p["lean"]) + 4.0
				p["hip_y"] = float(p["hip_y"]) + 0.03
				info["core"] = 0.6
			p["cannon"] = _cannon_aim(float(p["cannon"]), 0.35)
			info["feet"] = RigMotion.Feet.GAIT if spd > 12.0 else RigMotion.Feet.POSE
			info["drive"] = RigMotion.Drive.SOFT
			return p
		IronPump.State.PISTON:
			return _piston_pose(info)
		IronPump.State.SPRAY:
			return _spray_pose(info)
		IronPump.State.SUCK:
			return _suck_pose(info)
		IronPump.State.STAGGER:
			var k := boss.state_progress(boss.stagger_len)
			info["drive"] = RigMotion.Drive.SETTLE
			info["tremble"] = 1.0 - k
			info["beat"] = 0.3
			return motion.mix(motion.pose("stagger"), motion.pose("ready"), Motion.settle(k, 1.5, 3.0))
		IronPump.State.BROKEN:
			# 무릎이 꺾여 주저앉은 채 떨고, 핵이 터질 듯 맥동한다. 끝 0.5초에 몸을 일으킨다.
			var left: float = boss._timer
			var p := motion.pose("broken")
			if left < 0.5:
				p = motion.mix(p, motion.pose("idle"), Motion.ease_in_out(1.0 - left / 0.5))
			info["drive"] = RigMotion.Drive.HEAVY if left >= 0.5 else RigMotion.Drive.SOFT
			info["tremble"] = 0.35 + 0.25 * sin(_t * 9.0)
			info["core"] = 1.25 + 0.35 * sin(_t * 7.0)
			info["beat"] = 0.5
			return p
		IronPump.State.FALLEN:
			return _fall_pose(info)
		IronPump.State.PURIFIED:
			motion.ground_lock = 1.0
			motion.ground_settle = 1.0
			info["drive"] = RigMotion.Drive.SLOW
			info["core"] = 0.0
			info["beat"] = 0.0
			return motion.pose("dead")
	return motion.pose("idle")


## 등장: 잠든 채 웅크린 자세 → 핵이 깜빡이며 켜지고 몸을 일으킴 → 팔을 치켜들며 몸을 젖힘(김·불꽃) → 팔을 내리꽂으며 자리 잡기
func _intro_pose(info: Dictionary) -> Dictionary:
	var t := _state_t
	info["beat"] = 0.0
	if t < INTRO_WAKE:
		info["core"] = 0.05 + 0.3 * float(fmod(t * 7.0, 1.0) < 0.3)
		info["drive"] = RigMotion.Drive.SLOW
		return motion.pose("dormant")
	if t < INTRO_RISE:
		var u := (t - INTRO_WAKE) / (INTRO_RISE - INTRO_WAKE)
		info["core"] = lerpf(0.3, 0.9, u)
		info["tremble"] = 0.5 * (1.0 - u)
		info["drive"] = RigMotion.Drive.SOFT
		return motion.mix(motion.pose("dormant"), motion.pose("idle"), Motion.ease_in_out(u))
	if t < INTRO_ROAR:
		var u := (t - INTRO_RISE) / (INTRO_ROAR - INTRO_RISE)
		info["core"] = 1.2
		info["tremble"] = 0.6 * u
		info["drive"] = RigMotion.Drive.SOFT
		if u > 0.1 and not (_once & ONCE_ROAR):
			_once |= ONCE_ROAR
			_vent_burst()
			_spark_burst(10, _sock_global("core"))
		return motion.mix(motion.pose("idle"), motion.pose("roar"), Motion.anticipation(u))
	if t < INTRO_LAND:
		var u := (t - INTRO_ROAR) / (INTRO_LAND - INTRO_ROAR)
		info["core"] = 1.0
		info["drive"] = RigMotion.Drive.FAST
		info["ghost"] = true
		if u > 0.85 and not (_once & ONCE_LAND):
			_once |= ONCE_LAND
			var at := _sock_global("mouth")
			at.y = global_position.y
			_puff(20, at)
			motion.kick("crouch", 1.4)
			_rock_v += 3.0
			Juice.shake(6.0)
		return motion.mix(motion.pose("roar"), motion.pose("strike"), Motion.ease_in(u, 2.2))
	var u2 := clampf((t - INTRO_LAND) / 0.35, 0.0, 1.0)
	info["drive"] = RigMotion.Drive.SETTLE
	return motion.mix(motion.pose("strike"), motion.pose("idle"), Motion.settle(u2, 1.5, 3.0))


## 피스톤 내려찍기: 예고에 팔을 하늘로 치켜들고 멈칫(붉게 떨림) → 예고 끝 몫에 내리치기 시작해 실행 순간 앞 땅에 닿음
## → 실행 동안 팔이 땅에 박힌 채 몸이 쏠림 → 회복에 출렁이며 제자리.
func _piston_pose(info: Dictionary) -> Dictionary:
	var ph := boss.attack_phase
	var p := boss.phase_progress()
	info["beat"] = 0.25
	info["core"] = 0.7
	match ph:
		"startup":
			if boss.phase == 2:
				p = _stairs(p, 5)
			if p < SLAM_DROP:
				var u := p / SLAM_DROP
				info["drive"] = RigMotion.Drive.SOFT
				info["tremble"] = clampf((u - 0.55) / 0.45, 0.0, 1.0) * 0.9
				return motion.mix(_from, motion.pose("windup"), Motion.anticipation(u))
			var u2 := (p - SLAM_DROP) / (1.0 - SLAM_DROP)
			info["drive"] = RigMotion.Drive.FAST
			info["ghost"] = true
			return motion.mix(motion.pose("windup"), motion.pose("strike"), Motion.ease_in(u2, 2.4) * 0.92)
		"active":
			info["drive"] = RigMotion.Drive.FAST
			info["ghost"] = p < 0.35
			return motion.pose("strike")
		"recovery":
			info["drive"] = RigMotion.Drive.SETTLE
			return motion.mix(motion.pose("strike"), motion.pose("ready"), Motion.settle(Motion.ease_in(p, 2.0), 1.5, 2.5))
	return motion.pose("idle")


## 수액 분사: 흡입 팔을 땅에 짚어 버티고(받침대) 대포가 소녀를 겨눈다 → 한 발마다 반동(_on_shot) → 출렁이며 제자리
func _spray_pose(info: Dictionary) -> Dictionary:
	var ph := boss.attack_phase
	var p := boss.phase_progress()
	info["beat"] = 0.3
	info["core"] = 0.85
	var brace := motion.pose("brace").duplicate()
	brace["cannon"] = _cannon_aim(float(brace["cannon"]), 1.0)
	match ph:
		"startup":
			if boss.phase == 2:
				p = _stairs(p, 4)
			info["drive"] = RigMotion.Drive.SOFT
			info["tremble"] = clampf((p - 0.6) / 0.4, 0.0, 1.0) * 0.45
			return motion.mix(_from, brace, Motion.anticipation(p))
		"active":
			info["drive"] = RigMotion.Drive.NORMAL
			info["tremble"] = 0.2
			return brace
		"recovery":
			info["drive"] = RigMotion.Drive.SETTLE
			return motion.mix(brace, motion.pose("ready"), Motion.settle(Motion.ease_in(p, 2.0), 1.5, 2.5))
	return motion.pose("idle")


## 빨아들이기: 흡입 팔을 들어 입을 소녀에게 겨눈다 → 떨며 들이마심 → 끝에 덥석 물기 → 제자리.
## 물기를 저스트 가드로 되받으면(anim_hint "stagger") 팔이 튕겨 올라가고 몸이 휘청인다.
func _suck_pose(info: Dictionary) -> Dictionary:
	var ph := boss.attack_phase
	var p := boss.phase_progress()
	info["beat"] = 0.2
	info["core"] = 0.95
	if boss.anim_hint == "stagger" and ph == "recovery":
		info["drive"] = RigMotion.Drive.SETTLE
		info["tremble"] = 0.6 * (1.0 - p)
		return motion.mix(motion.pose("stagger"), motion.pose("ready"), Motion.settle(p, 1.5, 3.0))
	var aim := motion.pose("suck").duplicate()
	aim["arm_lo"] = _arm_aim(float(aim["arm_lo"]))
	match ph:
		"startup":
			if boss.phase == 2:
				p = _stairs(p, 4)
			info["drive"] = RigMotion.Drive.SOFT
			return motion.mix(_from, aim, Motion.anticipation(p))
		"active":
			if boss._bit:
				info["drive"] = RigMotion.Drive.QUICK
				_bite_pose = true
				return motion.pose("bite")
			_bite_pose = false
			info["drive"] = RigMotion.Drive.NORMAL
			info["tremble"] = 0.35
			# 들이마시며 몸이 조금씩 웅크렸다 펴진다 (펌프질)
			aim["hip_y"] = float(aim["hip_y"]) + 0.025 * sin(_t * 14.0)
			aim["pipe"] = float(aim["pipe"]) + 9.0 * sin(_t * 9.0)
			return aim
		"recovery":
			info["drive"] = RigMotion.Drive.SETTLE
			var src: Dictionary = motion.pose("bite") if _bite_pose else aim
			return motion.mix(src, motion.pose("ready"), Motion.settle(Motion.ease_in(p, 2.0), 1.5, 2.5))
	return motion.pose("idle")


## 쓰러짐: 경련 → 다리가 꺾이며 발이 밖으로 미끄러짐 → 몸이 땅에 부딪힘(튐·먼지) → 엎드려 누움 (정화를 기다리는 동안 그대로)
func _fall_pose(info: Dictionary) -> Dictionary:
	var t := _state_t
	info["beat"] = 0.0
	motion.ground_lock = 1.0
	if t < FALL_JOLT:
		info["drive"] = RigMotion.Drive.QUICK
		info["tremble"] = 1.0
		info["core"] = 0.9 * float(fmod(t * 11.0, 1.0) < 0.5)
		return motion.mix(_from, motion.pose("die_jolt"), Motion.ease_out(t / FALL_JOLT, 2.0))
	if t < FALL_BUCKLE:
		var u := (t - FALL_JOLT) / (FALL_BUCKLE - FALL_JOLT)
		info["drive"] = RigMotion.Drive.SOFT
		info["tremble"] = 0.6 * (1.0 - u)
		info["core"] = 0.5 + 0.3 * sin(t * 20.0)
		return motion.mix(motion.pose("die_jolt"), motion.pose("die_buckle"), Motion.ease_in(u, 1.6))
	if t < FALL_CRASH:
		var u := (t - FALL_BUCKLE) / (FALL_CRASH - FALL_BUCKLE)
		info["drive"] = RigMotion.Drive.FAST
		info["core"] = 0.4
		motion.ground_settle = Motion.ease_in(u, 2.0)
		return motion.mix(motion.pose("die_buckle"), motion.pose("dead"), Motion.ease_in(u, 2.4))
	if not _crashed:
		_crashed = true
		_crash()
	var u3 := clampf((t - FALL_CRASH) / (FALL_REST - FALL_CRASH), 0.0, 1.0)
	motion.ground_settle = 1.0
	info["drive"] = RigMotion.Drive.SETTLE if u3 < 0.5 else RigMotion.Drive.SLOW
	info["core"] = lerpf(0.35, 0.12, u3)
	return motion.pose("dead")


## 몸이 땅에 떨어진 순간: 넓은 먼지·흔들림·김·불꽃, 몸이 살짝 튀어 오른다
func _crash() -> void:
	var g := global_position
	_puff(28, g + Vector2(-60.0 * _sign, 0))
	_puff(22, g + Vector2(120.0 * _sign, 0))
	_spark_burst(14, _sock_global("core"))
	_vent_burst()
	_bounce_v = 260.0
	_rock_v += 6.0
	motion.kick("parry", 60.0)
	Juice.shake(9.0)
	Juice.rumble(0.5, 0.9, 0.3)
	Sfx.play("heavy_hit", -2.0, 0.05)


## 계단처럼 끊기는 진행도 (2페이즈 예고: 스르르 대신 멈칫멈칫)
static func _stairs(p: float, n: int) -> float:
	var x := clampf(p, 0.0, 1.0) * n
	var i := floorf(x)
	var f := x - i
	return (i + smoothstep(0.55, 1.0, f)) / n


## 2페이즈: 가끔 동작이 그 자리에 멈칫 굳었다가(0.06~0.18초) 빠른 스프링으로 확 따라잡는다 — 리듬이 무너진 기계.
## 타격 순간(실행 단계)과 쓰러진 뒤에는 멈추지 않는다 (보이는 동작이 판정과 어긋나지 않게).
func _stutter(pose: Dictionary, delta: float, info: Dictionary) -> Dictionary:
	var st := boss.state
	var allow := boss.phase == 2 and boss.attack_phase != "active" and st in [IronPump.State.IDLE, IronPump.State.PISTON, IronPump.State.SPRAY, IronPump.State.SUCK]
	if not allow:
		_stut_hold = 0.0
		return pose
	if _stut_hold > 0.0:
		_stut_hold -= delta
		info["drive"] = RigMotion.Drive.QUICK
		if _stut_hold <= 0.0:
			_snap_t = 0.12
		return _stut_pose
	_stut_next -= delta
	if _stut_next <= 0.0:
		_stut_next = randf_range(0.3, 0.85)
		_stut_hold = randf_range(0.06, 0.18)
		_stut_pose = motion.capture()
		motion.kick("impact", randf_range(-40.0, 40.0))
		info["drive"] = RigMotion.Drive.QUICK
		return _stut_pose
	return pose


## 박: 1페이즈는 정확히 128bpm 마다 '쿵'. 2페이즈는 길이가 들쭉날쭉(반 박·한 박 반)하고 가끔 두 번 연달아.
## 쓰러진 뒤에는 약해지는 마지막 박동 몇 번 뒤 멈춘다.
func _beat(delta: float, st: IronPump.State, amount: float) -> void:
	_beat_t += delta
	_pump_ph += delta * PI / _beat_len
	_beat_amp = Motion.damp(_beat_amp, 0.0 if st == IronPump.State.FALLEN or st == IronPump.State.PURIFIED else 1.0, 1.5, delta)
	_steam_t -= delta
	_steam.emitting = _steam_t > 0.0
	if _beat_t < _beat_len:
		return
	_beat_t = 0.0
	_beat_n += 1
	if st == IronPump.State.FALLEN or st == IronPump.State.PURIFIED:
		if _death_beats > 0 and st == IronPump.State.FALLEN and _state_t > FALL_REST:
			_death_beats -= 1
			_core_kick = 0.25 * (_death_beats + 1)
			motion.kick("crouch", 0.12 * (_death_beats + 1))
		_beat_len = BEAT * 1.6
		return
	if boss.phase == 1:
		_beat_len = BEAT
	else:
		var r := randf()
		_beat_len = BEAT * (0.3 if r < 0.18 else (0.5 if r < 0.35 else (1.5 if r < 0.6 else (0.75 if r < 0.75 else 1.0))))
	if amount <= 0.0:
		return
	motion.kick("crouch", 0.55 * amount)
	_core_kick = maxf(_core_kick, 0.35 * amount)
	if _beat_n % 2 == 0 or boss.phase == 2:
		_steam_t = 0.12


## 대포 겨눔 각도 (도). 소녀가 앞에 있으면 수액 방울이 날아갈 쪽(소녀 위로 조금, 거리만큼 더 높게)을 겨눈다. w = 겨눔 몫.
func _cannon_aim(rest: float, w: float) -> float:
	if _i_cannon < 0 or boss.player == null or not is_instance_valid(boss.player):
		return rest
	var pg := boss.player.global_position
	var target := pg + Vector2(0, -50.0 - absf(pg.x - boss.global_position.x) * 0.15)
	var d := _to_rig(target) - rig.xf[_i_cannon].origin
	if d.x < 40.0:
		return rest
	var r := rad_to_deg(atan2(-d.x, d.y) - rig.world_rot(_i_body))
	return lerpf(rest, clampf(r, CANNON_UP, CANNON_DOWN), w)


## 빨아들이기: 아래팔(입)이 소녀 가슴을 향하는 각도 (위팔 틀 기준, 도)
func _arm_aim(rest: float) -> float:
	if _i_arm_lo < 0 or boss.player == null or not is_instance_valid(boss.player):
		return rest
	var d := _to_rig(boss.player.global_position + Vector2(0, -60)) - rig.xf[_i_arm_lo].origin
	if d.x < 30.0:
		return rest
	var r := rad_to_deg(atan2(-d.x, d.y) - rig.world_rot(_i_arm_up))
	return clampf(r, SUCK_LO_MIN, SUCK_LO_MAX)


## 세상 점 → 뼈대 단위(뼈대 뿌리 틀)
func _to_rig(g: Vector2) -> Vector2:
	return rig.body_xf.affine_inverse() * (rig.to_local(g) / rig.game_scale)


func _sock_global(sname: String) -> Vector2:
	if not _sock.has(sname):
		return global_position
	var sk: Array = _sock[sname]
	return rig.to_global(rig.to_rig_local(rig.xf[int(sk[0])] * (sk[1] as Vector2)))


# ---------- 갱신 뒤: 효과·빛·색 ----------

func _after_update(delta: float, st: IronPump.State, info: Dictionary) -> void:
	var down := st == IronPump.State.FALLEN or st == IronPump.State.PURIFIED
	# 발 디딤: 먼지와 몸 흔들림 (앞발은 앞으로, 뒷발은 뒤로 쏠림)
	for k in motion.legs.size():
		var leg: RigMotion.Leg = motion.legs[k]
		if leg.planted_now and not down:
			var fp := rig.to_global(rig.to_rig_local(rig.xf[leg.foot] * leg.sole))
			fp.y = global_position.y
			_puff(8, fp)
			motion.kick("crouch", 0.7)
			_rock_v += 2.2 if k == 0 else -2.2
	# 흔들림·튐 스프링
	var r := Motion.spring(_rock, 0.0, _rock_v, 160.0, 11.0, delta)
	_rock = r[0]
	_rock_v = r[1]
	var b := Motion.spring(_bounce, 0.0, _bounce_v, 220.0, 9.0, delta)
	_bounce = b[0]
	_bounce_v = b[1]
	if _bounce < 0.0:
		_bounce = 0.0
		_bounce_v = 0.0
	_tremble = Motion.damp(_tremble, float(info["tremble"]), 12.0, delta)
	rig.position = Vector2(sin(_t * 57.0) * 3.5 * _tremble, -_bounce + cos(_t * 43.0) * 1.5 * _tremble)
	# 잔상 (피스톤 휘두름)
	if info["ghost"]:
		_ghost_timer += delta
		if _ghost_timer >= 0.03:
			_ghost_timer = 0.0
			rig.snapshot_ghost(Color(1.0, 0.62, 0.42, 0.32))
	else:
		_ghost_timer = 0.0
	rig.fade_ghosts(delta, 4.0)
	# 핵 빛
	_core_kick = maxf(_core_kick - delta * 2.2, 0.0)
	_core = Motion.damp(_core, float(info["core"]), 6.0, delta)
	var core := _core + _core_kick
	_red = Motion.damp(_red, 1.0 if boss.is_red() else 0.0, 14.0, delta)
	var purified := st == IronPump.State.PURIFIED
	if purified:
		_purify = minf(_purify + delta / 1.6, 1.0)
	var core_col := CORE_AMBER.lerp(Color(1.0, 0.35, 0.25), _red).lerp(CORE_GREEN, _purify)
	var glow := core if not purified else lerpf(1.4, 0.0, _purify)
	_core_glow.modulate = Color(core_col.r * 1.5, core_col.g * 1.5, core_col.b * 1.5, clampf(glow, 0.0, 1.5) * 0.5)
	_core_glow.scale = Vector2.ONE * (2.0 + 0.9 * clampf(glow, 0.0, 1.6))
	_rays.visible = st == IronPump.State.BROKEN
	if _rays.visible:
		_rays.queue_redraw()
	# 입 빛 (빨아들이기) / 대포 불빛 (분사)
	var suck_on := st == IronPump.State.SUCK and boss.attack_phase == "active" and not boss._bit
	var mouth_a := Motion.damp(_mouth_glow.modulate.a, 0.8 if suck_on else (0.25 if st == IronPump.State.SUCK else 0.0), 8.0, delta)
	_mouth_glow.modulate = Color(SAP.r * 1.8, SAP.g * 1.8, SAP.b * 1.8, mouth_a)
	_muzzle_a = maxf(_muzzle_a - delta * 6.0, 0.0)
	var aim_glow := 0.25 if st == IronPump.State.SPRAY and boss.attack_phase != "recovery" else 0.0
	_muzzle_glow.modulate = Color(1.8, 2.0, 1.9, maxf(_muzzle_a, aim_glow))
	_muzzle_glow.scale = Vector2.ONE * (0.9 + 1.1 * _muzzle_a)
	# 빨아들이기 띠·가루
	_inhale.emitting = suck_on and boss.player != null and is_instance_valid(boss.player)
	if _inhale.emitting:
		var mouth := _sock_global("mouth")
		var pc := boss.player.global_position + Vector2(0, -60)
		var span := mouth - pc
		_inhale.global_position = pc + span * 0.25
		_inhale.global_rotation = span.angle()
		_inhale.lifetime = clampf(span.length() * 0.75 / 690.0, 0.15, 0.9)
	if suck_on or _stream_on:
		_stream.queue_redraw()   # 켜져 있거나 막 꺼진 프레임만 다시 그린다
	_stream_on = suck_on
	# 김·수액
	_vent.emitting = st == IronPump.State.BROKEN or st == IronPump.State.STAGGER or (st == IronPump.State.FALLEN and _state_t > FALL_CRASH)
	_drips.emitting = boss.phase == 2 and not down
	# 점빛 (보스 장면의 Light): 핵 자리를 따라간다
	if _light:
		_light.position = boss.to_local(_core_glow.global_position)
		_light.energy = 0.5 + 1.4 * clampf(glow, 0.0, 1.6)
		_light.color = core_col
	# 몸 색: 2페이즈엔 조금 달아오르고, 피스톤 예고엔 붉게 깜빡인다. 맞으면 번쩍(약하게 움찔).
	var fl := boss.flash_amount()
	if fl > _prev_flash + 0.4 and st != IronPump.State.FALLEN and st != IronPump.State.STAGGER:
		motion.kick("impact", 60.0 if st == IronPump.State.BROKEN else 30.0)
	_prev_flash = fl
	var base := Color(1.0, 0.97, 0.95) if boss.phase == 1 else Color(1.06, 0.92, 0.86)
	if down:
		base = base.lerp(Color(0.82, 0.78, 0.76), clampf(_state_t / 2.0, 0.0, 1.0))
	# 붉은 예고: 치켜든 흡입 팔(피스톤)이 달아오르고 몸은 조금만 물든다
	var pulse := _red * (0.6 + 0.4 * sin(_t * 32.0))
	rig.modulate = base.lerp(RED_HOT, pulse * 0.15)
	for spr in _red_sprites:
		spr.self_modulate = Color.WHITE.lerp(RED_HOT, pulse * 0.7)
	rig.set_flash(fl * 0.75)



## 2페이즈: 공격이 끝날 때마다 사방에서 수액이 솟는다(SapSpurt, 보스 논리) — 그림은 관 팔이 홱 치켜들며 끝에서 수액을 뿜고 김이 샌다.
func _leak_fx() -> void:
	_pipe_jerk_v += 260.0
	_spray.global_position = _sock_global("outlet")
	_spray.direction = Vector2(-_sign * 0.6, -1.0)
	_spray.restart()
	_spray.emitting = true
	_vent_burst()


func _vent_burst() -> void:
	_vent.restart()
	_vent.emitting = true


func _puff(n: int, at: Vector2) -> void:
	var d := _dust[_dust_next]
	_dust_next = (_dust_next + 1) % _dust.size()
	d.amount = n
	d.global_position = at
	d.restart()
	d.emitting = true


func _spark_burst(n: int, at: Vector2) -> void:
	_sparks.amount = n
	_sparks.global_position = at
	_sparks.restart()
	_sparks.emitting = true


## 장갑 깨짐: 핵 창에서 사방으로 새어 나오는 빛살 (CoreRays 노드의 지역 좌표 = 핵 자리, 뒤집힘은 부모를 따른다)
func _draw_rays() -> void:
	var a := 0.22 + 0.16 * sin(_t * 7.0)
	for i in 6:
		var ang := -PI * 0.5 + (i - 2.5) * 0.5 + sin(_t * 2.0 + i) * 0.08
		var len := 70.0 + 35.0 * sin(_t * 5.0 + i * 1.7)
		var d := Vector2.from_angle(ang)
		var side := d.orthogonal() * 4.5
		_rays.draw_colored_polygon(PackedVector2Array([side, d * len, -side]), Color(1.6, 1.1, 0.55, a))


## 빨아들이기: 소녀와 흡입 팔의 입 사이에 빨려 드는 수액빛 띠 (흐르는 줄 여러 가닥 + 빛 알갱이). 세상 좌표.
func _draw_suck_stream() -> void:
	if boss == null or not boss.visible or boss.state != IronPump.State.SUCK or boss.attack_phase != "active" or boss._bit:
		return
	if boss.player == null or not is_instance_valid(boss.player):
		return
	var mouth := _sock_global("mouth")
	var from := boss.player.global_position + Vector2(0, -60)
	var span := mouth - from
	var len := span.length()
	if len < 10.0:
		return
	var side := (span / len).orthogonal()
	var a := clampf(boss.phase_progress() * 4.0, 0.0, 1.0)
	var mouth_r := 40.0
	var band := PackedVector2Array([from + side * 120.0, mouth + side * mouth_r * 0.7, mouth - side * mouth_r * 0.7, from - side * 120.0])
	_stream.draw_colored_polygon(band, Color(SAP, 0.07 * a))
	for i in 9:
		var k := fposmod(_t * 1.8 + i / 9.0, 1.0)
		var off := sin(i * 2.3) * 100.0 * (1.0 - k)
		var q0 := from + span * k + side * off
		var q1 := from + span * minf(k + 0.14, 1.0) + side * off * 0.8
		_stream.draw_line(q0, q1, Color(SAP.lightened(0.35), 0.55 * a * (0.4 + 0.6 * k)), 8.0 + 7.0 * k, true)
	for i in 7:
		var k := fposmod(_t * 1.25 + i / 7.0, 1.0)
		var q := from + span * k + side * sin(_t * 5.0 + i) * 64.0 * (1.0 - k)
		_stream.draw_circle(q, 8.0 + 5.0 * k, Color(1.0, 1.0, 1.0, 0.5 * a))


# ---------- 시험·도구용 ----------

## 지금 자세 값 (시험이 읽는다): 발바닥 높이(게임 px, 땅 0·아래 +), 몸(무기 팔·천 뺌)의 가장 낮은 점·가장 높은 점(게임 px, 땅 기준),
## 몸통 관절 높이, 흡입 팔 입·대포 끝 자리(세상), 기울기·팔·대포 각도, 몸 틀기 값
func probe_pose() -> Dictionary:
	var soles: Array = []
	for y in motion.sole_ys():
		soles.append(y * _k + rig.position.y)
	return {
		"soles": soles,
		"lowest": rig.lowest_y(motion._lock_bones) * _k + rig.position.y,
		"settle_low": rig.lowest_y(motion._settle_bones) * _k + rig.position.y,
		"top": rig.highest_y() * _k + rig.position.y,
		"body_y": rig.to_global(rig.to_rig_local(rig.xf[_i_body].origin)).y - global_position.y,
		"mouth": _sock_global("mouth"),
		"muzzle": _sock_global("muzzle"),
		"core": _sock_global("core"),
		"lean": float(motion.fin.get("lean", 0.0)),
		"arm_up": float(motion.fin.get("arm_up", 0.0)),
		"cannon": float(motion.fin.get("cannon", 0.0)),
		"face": _face,
		"low_bone": _lowest_bone(),
	}


func _lowest_bone() -> String:
	var best := -INF
	var name := ""
	for i in motion._lock_bones:
		var y := rig.lowest_y(PackedInt32Array([i]))
		if y > best:
			best = y
			name = rig.names[i]
	return name

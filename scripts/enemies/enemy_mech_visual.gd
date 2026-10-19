extends EnemyRigVisual
class_name EnemyMechVisual
## 기계 몹(침식된 채굴 기계·채굴 괴수·작은 펌프)의 부위 뼈대 그림. EnemyRigVisual(사람·짐승 공용) 위에 기계다운 것만 더한다.
## 판정·시간은 건드리지 않는다 — 그림이 몹 스크립트의 상태(예고·타격·회복·들이받기 등)를 따라간다.
##
##  - 몸 충돌이 누운 캡슐(기계)이어도 발이 닿는 땅을 바로 찾는다 (예전 그림의 foot_offset 대신).
##  - 도는 부위(spin_bone, 드릴): 대기 땐 천천히, 예고 동안 점점 빨라지고(시동), 들이받기 땐 가장 빠르다.
##    그림 한 장이라 드릴 그림을 한 장 더 겹쳐 '비스듬한 빛 줄(나선)이 끝으로 흘러가게'(shaders/drill_spin.gdshader) + 떨림으로 돈다.
##  - 빛나는 자리(glow_sockets: 등불·심장): 숨쉬듯 깜박이고, 예고 땐 밝게 끓고, 무너지면 꺼질 듯 깜박이고, 쓰러지면 꺼진다.
##    glow_parts 부위 그림도 함께 밝아져 HDR 글로우가 등불 유리·드릴 홈에만 번진다.
##  - 쓰러짐: 정화(빛)는 **멈춰 선 채로** 힘이 빠지고(기획서 '정화하면 멈춰 선 채 그 위로 싹이 튼다'),
##    부서짐은 다리가 꺾여 배가 땅에 닿는다 (밀린 쪽 다리부터 — 뒤에서 맞으면 앞다리, 앞에서 맞으면 뒷다리).
##  - 김(steam_socket): 쏠 때·걸을 때 칙칙. 불꽃(spark_socket): 드릴이 땅을 긁거나 들이받아 부딪힐 때.
##  - 대롱 겨눔(arm_kind = "gun"): aim_always 면 대기·순찰·발견 중에도 소녀가 가까우면 겨눈다 (작은 펌프는 제자리에서 늘 겨눈다).
## 자세는 원형 파일(data/rigs/_archetypes/drill_beast.json · pipe_walker.json), 뼈대는 data/rigs/<id>.json.

## 도는 부위 (드릴). 비우면 돌지 않는다.
@export var spin_bone := ""
## 빛나는 자리들 (설계도 sockets 이름)
@export var glow_sockets: PackedStringArray = []
## 빛과 함께 밝아지는 부위 그림 (뼈 이름)
@export var glow_parts: PackedStringArray = []
@export var glow_color := Color(1.0, 0.7, 0.35)
## 빛 크기 (게임 px 지름, 배율 1 기준)
@export var glow_size := 46.0
## 김이 나오는 자리 (sockets 이름, 비우면 없음)
@export var steam_socket := ""
## 불꽃이 튀는 자리 (sockets 이름, 비우면 없음)
@export var spark_socket := ""
## 대롱: 대기·순찰·발견 중에도 소녀가 이 거리(px) 안이면 겨눈다 (0 이면 EnemyRigVisual 과 같이 쫓기·공격 중에만)
@export var aim_always_range := 0.0

## 상태별 드릴 빠르기 (초당 띠가 지나가는 수)
const SPIN_IDLE := 1.2
const SPIN_MOVE := 3.0
const SPIN_WINDUP_MAX := 14.0
const SPIN_CHARGE := 17.0
const SPIN_SLAM := 12.0
const SPIN_SHADER := preload("res://shaders/drill_spin.gdshader")

var _spin := 0.0
var _spin_phase := 0.0
var _spin_i := -1
var _spin_sprite: Sprite2D      # 드릴 위에 겹친 빛 줄 그림
var _spin_src: Sprite2D         # 드릴 그림 (뼈대의 것)
var _spin_mat: ShaderMaterial
var _glows: Array[Sprite2D] = []
var _glow_part_sprites: Array[Sprite2D] = []
var _glow_level := 1.0
var _glow_flicker := 0.0
var _steam: CPUParticles2D
var _sparks: CPUParticles2D       # 들이받는 동안 계속 튀는 불꽃
var _spark_burst: CPUParticles2D  # 한 번에 터지는 불꽃 (내려찍기·부딪힘)
var _steam_timer := 1.0
var _slam_sparked := false
var _mt := 0.0


func _ready() -> void:
	super._ready()
	if not _ready_ok:
		return
	# 움직이기 직전 갈고리가 달린 움직임으로 바꾼다 (공용 RigMotion 은 그대로)
	motion = HookedRigMotion.new(rig, _pre_motion)
	_state_from = motion.pose("idle")
	_spin_i = rig.bone_index(spin_bone) if spin_bone != "" else -1
	if _spin_i >= 0:
		_spin_src = rig.sprite_of(spin_bone)
	if _spin_src:
		# 드릴 그림을 한 장 더 (같은 텍스처) 드릴 바로 위 순서에 겹친다. 축 = 설계도의 pivot → tip (텍스처 px).
		var bd: Dictionary = rig.data["bones"][_spin_i]
		var pv := PartRig._v(bd["pivot"])
		var ts := float(bd.get("tex_scale", 1.0))
		var tip := pv + Vector2(0.0, float(bd.get("len", 100.0))).rotated(-deg_to_rad(float(bd["rot"]))) / ts
		_spin_mat = ShaderMaterial.new()
		_spin_mat.shader = SPIN_SHADER
		_spin_mat.set_shader_parameter("tex_size", _spin_src.texture.get_size())
		_spin_mat.set_shader_parameter("axis_a", pv)
		_spin_mat.set_shader_parameter("axis_b", tip)
		_spin_mat.set_shader_parameter("band_color", glow_color)
		_spin_sprite = Sprite2D.new()
		_spin_sprite.name = "DrillSpin"
		_spin_sprite.texture = _spin_src.texture
		_spin_sprite.centered = false
		_spin_sprite.offset = _spin_src.offset
		_spin_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_spin_sprite.material = _spin_mat
		_spin_src.get_parent().add_child(_spin_sprite)
		_spin_src.get_parent().move_child(_spin_sprite, _spin_src.get_index() + 1)
	var socks: Dictionary = rig.data.get("sockets", {})
	var gt := _glow_texture()
	for sname in glow_sockets:
		if not socks.has(sname):
			continue
		var g := Sprite2D.new()
		g.texture = gt
		var add2 := CanvasItemMaterial.new()
		add2.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		g.material = add2
		var sd: Dictionary = socks[sname]
		rig.attach(str(sd["bone"]), g, PartRig._v(sd["pos"]))
		_glows.append(g)
	for pn in glow_parts:
		var s := rig.sprite_of(pn)
		if s:
			_glow_part_sprites.append(s)
	if steam_socket != "" and socks.has(steam_socket):
		_steam = _make_puffs(Color(0.92, 0.9, 0.86, 0.38), 10, 0.9)
		var sd2: Dictionary = socks[steam_socket]
		rig.attach(str(sd2["bone"]), _steam, PartRig._v(sd2["pos"]))
	if spark_socket != "" and socks.has(spark_socket):
		var sd3: Dictionary = socks[spark_socket]
		_sparks = _make_sparks(false)
		rig.attach(str(sd3["bone"]), _sparks, PartRig._v(sd3["pos"]))
		_spark_burst = _make_sparks(true)
		rig.attach(str(sd3["bone"]), _spark_burst, PartRig._v(sd3["pos"]))


## 몸 충돌(캡슐)의 바닥 = 발이 닿는 땅. 기계는 캡슐을 눕혀 두어서(가로로 긴 몸) 바닥이 '반지름' 아래다.
func _find_floor_y() -> float:
	for c in _enemy.get_children():
		if c is CollisionShape2D and c.shape is CapsuleShape2D:
			var cap := c.shape as CapsuleShape2D
			if absf(c.rotation) < 0.1:
				return c.position.y + cap.height * 0.5
			if absf(absf(c.rotation) - PI * 0.5) < 0.1:
				return c.position.y + cap.radius
	return super._find_floor_y()


## 쓰러진다: 정화(빛)는 멈춰 선 채 힘이 빠지고, 부서짐은 다리가 꺾여 배가 땅에 닿는다.
## (EnemyRigVisual 의 쓰러짐 흐름을 그대로 쓰되 자세만 기계 것으로 바꿔 끼운다.)
func fall(dir: int, gentle: bool) -> void:
	super.fall(dir, gentle)
	if motion == null:
		return
	var rel := float(_fall_dir) * signf(_mir.v)
	if gentle:
		_fall_sign = 1.0     # 앞쪽 흐름 = 땅 닿기(올리기만), 내려놓기 없음 → 선 채로
		_use_pose("dead_knees", "powerdown")
		_use_pose("dead_lie", "powerdown_lie")
	else:
		_fall_sign = -1.0    # 뒤쪽 흐름 = 내려놓기(몸의 가장 낮은 점을 땅에) → 배가 땅에 닿는다
		var side := "collapse_front" if rel > 0.0 else "collapse_back"
		_use_pose("dead_back", side)
		_use_pose("dead_back_lie", side + "_lie")
	_glow_flicker = 1.0


func _use_pose(dst: String, src: String) -> void:
	if motion.has_pose(src):
		motion.poses[dst] = motion.poses[src]


## 들이받기 끝·방패 박힘 같은 '꽝': 불꽃도 튄다.
func impact(dir: int, strength := 1.0) -> void:
	super.impact(dir, strength)
	_burst_sparks(int(10 * strength))


## 쏘았다: 김이 칙.
func recoil(strength := 1.0) -> void:
	super.recoil(strength)
	_puff_steam(8)


## 관절이 움직이기 직전 (HookedRigMotion 이 부른다): 상태 자세 위에 기계다운 떨림·겨눔을 얹는다.
func _pre_motion(delta: float) -> void:
	if _enemy == null:
		return
	_mt += delta
	var st := _enemy.state
	var s := clampf(_spin / SPIN_CHARGE, 0.0, 1.0)
	# 드릴이 빨리 돌면 드릴 축과 몸이 잘게 떨린다 (스프링이 쫓으며 고르게 누그러진다)
	if _spin_i >= 0 and s > 0.05:
		var k := spin_bone
		if motion.target.has(k):
			motion.target[k] = float(motion.target[k]) + (sin(_mt * 57.0) * 1.3 + sin(_mt * 91.0) * 0.6) * s
		motion.target["lean"] = float(motion.target["lean"]) + sin(_mt * 43.0) * 0.5 * s
	# 들이받기 예고: 몸을 낮추고 앞발로 땅을 긁듯 버틴다 (내려치기 예고는 원형 자세대로 몸을 뒤로 젖혀 치켜든다)
	if st == EnemyBase.State.WINDUP and bool(_enemy.get("_ramming")):
		var w := Motion.ease_out(clampf(_enemy.windup_progress * 1.4, 0.0, 1.0), 2.0)
		motion.target["hip_y"] = lerpf(float(motion.target["hip_y"]), 0.2, w)
		motion.target["lean"] = lerpf(float(motion.target["lean"]), 6.0, w) + sin(_mt * 30.0) * 1.2 * w
		motion.target["hip_x"] = lerpf(float(motion.target["hip_x"]), -0.18, w)
		if motion.target.has(spin_bone):
			motion.target[spin_bone] = lerpf(float(motion.target[spin_bone]), -82.0, w)
	# 부서져 쓰러질 때: 무게에 눌려 발이 바깥으로 미끄러지며 다리가 벌어지고 배가 땅에 닿는다
	# (한 걸음씩 들어 옮기지 않고 땅을 긁으며 — 걸음 방식이면 넷을 차례로 옮기느라 쓰러짐 0.75초 안에 끝나지 않는다)
	if st == EnemyBase.State.DEAD and not _fall_gentle:
		for leg in motion.legs:
			leg.swing = false
			leg.h = 0.0
			leg.x = Motion.damp(leg.x, float(motion.target.get(leg.k_foot, 0.0)) * motion.L, 9.0, delta)
	# 대롱: 제자리에서 늘 겨눈다 (EnemyRigVisual 은 쫓기·공격 중에만 겨눈다)
	if aim_always_range > 0.0 and _aim_i >= 0 and st in [EnemyBase.State.IDLE, EnemyBase.State.PATROL, EnemyBase.State.ALERT]:
		var pl := _enemy.player
		if pl and is_instance_valid(pl) and pl.global_position.distance_to(_enemy.global_position) < aim_always_range:
			_aim_gun(st)


func _process(delta: float) -> void:
	super._process(delta)
	if not _ready_ok or _enemy == null:
		return
	var st := _enemy.state
	var hint: String = _enemy.anim_hint
	# ---- 드릴 빠르기 ----
	var want := SPIN_IDLE
	match st:
		EnemyBase.State.PATROL, EnemyBase.State.CHASE, EnemyBase.State.ALERT, EnemyBase.State.BACKSTEP, EnemyBase.State.LUNGE:
			want = SPIN_MOVE
		EnemyBase.State.WINDUP:
			want = lerpf(SPIN_MOVE, SPIN_WINDUP_MAX, Motion.ease_in(_enemy.windup_progress, 1.6))
		EnemyBase.State.STRIKE:
			want = SPIN_CHARGE if hint == "charge" else SPIN_SLAM
		EnemyBase.State.RECOVER:
			want = SPIN_MOVE
		EnemyBase.State.HIT:
			want = SPIN_IDLE
		EnemyBase.State.BROKEN:
			want = 0.4 + 0.5 * maxf(sin(_t * 6.0) * sin(_t * 2.3), 0.0)   # 털털거리며 꺼질 듯
		EnemyBase.State.DEAD:
			want = 0.0
	_spin = Motion.damp(_spin, want, 5.0 if want > _spin else 2.2, delta)
	_spin_phase = fposmod(_spin_phase + _spin * delta, 1.0)
	if _spin_sprite:
		_spin_sprite.visible = st != EnemyBase.State.DEAD and _spin > 0.3
		if _spin_sprite.visible:
			_spin_sprite.transform = _spin_src.transform
			_spin_mat.set_shader_parameter("phase", _spin_phase)
			_spin_mat.set_shader_parameter("strength", 0.03 + 0.8 * clampf(_spin / SPIN_CHARGE, 0.0, 1.0))
	# ---- 불꽃: 내려찍은 드릴이 땅을 긁는 순간 ----
	if st == EnemyBase.State.STRIKE and hint != "charge":
		if not _slam_sparked and _enemy.phase_progress > 0.35:
			_slam_sparked = true
			_burst_sparks(12)
	else:
		_slam_sparked = false
	if _sparks:
		var grind := st == EnemyBase.State.STRIKE and hint == "charge" and _enemy.is_on_floor()
		if _sparks.emitting != grind:
			_sparks.emitting = grind
	# ---- 빛 ----
	var level := 0.85 + 0.15 * sin(_t * 2.2)
	match st:
		EnemyBase.State.WINDUP:
			level = 1.0 + 0.7 * _enemy.windup_progress + 0.15 * sin(_t * 31.0) * _enemy.windup_progress
		EnemyBase.State.STRIKE:
			level = 1.6
		EnemyBase.State.HIT:
			level = 0.7
		EnemyBase.State.BROKEN:
			level = 0.25 + 0.55 * maxf(sin(_t * 9.0) * sin(_t * 3.7 + 1.0), 0.0)
		EnemyBase.State.DEAD:
			if _fall_gentle:
				level = maxf(1.4 - _enemy.phase_progress * 2.0, 0.0)   # 따뜻하게 한 번 밝았다가 잦아든다
			else:
				# 털털 깜박이다 꺼진다
				var u := _enemy.phase_progress
				level = maxf(0.0, (1.0 - u * 2.2)) * (0.4 + 0.6 * absf(sin(_t * 23.0)))
	_glow_level = Motion.damp(_glow_level, level, 14.0, delta)
	var alpha := 1.0 - rig.dissolve_amount()
	var gs := glow_size / 64.0   # 빛은 뼈대(배율 art_scale)의 자식이라 크기는 뼈대가 키운다
	for g in _glows:
		g.modulate = Color(glow_color.r * 1.15, glow_color.g * 1.05, glow_color.b, 0.22 * _glow_level * alpha)
		g.scale = Vector2(gs, gs) * (0.85 + 0.2 * _glow_level)
	var pk := 1.0 + 0.28 * clampf(_glow_level - 0.6, -0.6, 1.2)
	for s in _glow_part_sprites:
		s.self_modulate = Color(pk, pk * 0.97, pk * 0.92, 1.0)
	# ---- 김 ----
	if _steam:
		_steam_timer -= delta
		if _steam_timer <= 0.0 and st != EnemyBase.State.DEAD:
			var moving := absf(_enemy.velocity.x) > 40.0
			_puff_steam(4 if moving else 3)
			_steam_timer = randf_range(0.7, 1.2) if moving else randf_range(1.6, 3.0)


func _glow_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 64
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	return gt


func _make_puffs(col: Color, n: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = n
	p.lifetime = life
	p.local_coords = false
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(0, -60)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 90.0
	p.damping_min = 30.0
	p.damping_max = 60.0
	p.scale_amount_min = 4.0
	p.scale_amount_max = 9.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.4, 1.0))
	curve.add_point(Vector2(1, 1.4))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	ramp.colors = PackedColorArray([Color(col, 0.0), col, Color(col, 0.0)])
	p.color_ramp = ramp
	return p


## 불꽃 입자: burst 면 한 번에 터지는 묶음, 아니면 계속 뿜는 묶음. 방향은 뼈대 틀(오른쪽을 봄)의 뒤 위 —
## 뼈대의 자식이라 왼쪽을 보면 저절로 뒤집힌다. 개수는 만들 때 한 번만 정한다 (바꾸면 입자 배열을 다시 만든다).
func _make_sparks(burst: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = burst
	p.explosiveness = 0.9 if burst else 0.0
	p.amount = 14 if burst else 10
	p.lifetime = 0.35
	p.local_coords = false
	p.direction = Vector2(-1, -0.6)
	p.spread = 50.0
	p.gravity = Vector2(0, 700)
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 320.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color(2.4, 1.9, 1.0, 1.0), Color(2.0, 1.1, 0.4, 0.9), Color(1.2, 0.4, 0.1, 0.0)])
	p.color_ramp = ramp
	return p


func _puff_steam(_n := 0) -> void:
	if _steam == null:
		return
	_steam.restart()
	_steam.emitting = true


func _burst_sparks(_n := 0) -> void:
	if _spark_burst == null:
		return
	_spark_burst.restart()
	_spark_burst.emitting = true

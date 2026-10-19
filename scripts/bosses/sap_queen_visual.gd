extends Sprite2D
## 수액의 여왕 그림. 부위 뼈대(PartRig — art/rigs/sap_queen, 설계도 data/rigs/sap_queen.json)를 움직임 층(RigMotion,
## 자세 모음 data/rigs/_archetypes/sap_queen.json)으로 상태에 맞춰 움직인다. 판정·시간은 전혀 건드리지 않는다 (그림이 논리를 따라간다).
## 이 노드는 보스 씬의 'Sprite'(Sprite2D)다 — 보스 스크립트가 $Sprite 로 찾으므로 이름·종류를 그대로 두고, 그림은 자식 뼈대가 그린다.
## (뼈대를 못 읽으면 texture(조립 그림 한 장, boss_sap_queen_now.png)를 대신 띄운다.)
##
## 움직임 원칙 (몹·다른 보스와 같은 약속): 자세 값은 '툭' 바뀌지 않는다 — 매 프레임 목표 자세만 정하고 RigMotion 의 스프링이 쫓는다.
##  - 정면을 보는 나비 정령: 날개 넷이 따로 퍼덕인다 (위 날개가 앞서고 아래 날개가 조금 늦게, 왼·오른도 살짝 어긋나게).
##    날갯짓 = 날개 뿌리에서 위아래로 도는 각도 + 가로로 접혔다 펴짐(날개가 앞뒤로 젖혀지며 짧아 보임). 위상 누적기라 빠르기가 바뀌어도 끊기지 않는다.
##  - 공격은 모두 왈츠 3박자 (하나·둘 = 예고, 셋 = 공격). 예고 동안 팔이 모으거나 치켜들고(둘째 박 끝에 멈칫·떨림),
##    셋째 박(히트 순간)에 팔이 어깨 → 팔꿈치 → 손목 순서로 채찍처럼 휘둘러 지나쳤다 돌아온다 (RigMotion.three_beat).
##    가루 = 두 팔을 머리 위로 → 바깥으로 흩뿌림 / 물결 = 몸 반대쪽 아래로 모았다 → 소녀 쪽 수면을 쓸어냄 /
##    나비 = 가슴 앞에 두 손을 모아 빚고 날개를 접었다 → 팔과 날개를 활짝 펴며 놓아줌 / 내려앉기 = 두 팔을 머리 위로 → 날개를 접고 곧게 내리꽂음 → 무릎을 굽혀 받음.
##    박마다 몸이 살짝 가라앉았다 떠오른다 (첫 박이 가장 크게 — 왈츠의 '쿵·짝·짝').
##  - 내려앉음·무너짐·쓰러짐·정화는 땅(보스 원점 = 디딤돌 윗면)에: 가장 낮은 점(발끝·무릎·몸)이 정확히 땅에 오게 RigMotion.ground_settle.
##  - 무너짐: 무릎이 풀려 주저앉고 → 다리를 옆으로 모아 앉아 한 손으로 땅을 짚는다 (날개는 축 늘어짐).
##  - 쓰러짐: 공중에서 힘없이 떨어지다 → 땅에 닿으면 무릎이 풀리고 → 옆으로 앉았다가 → 옆으로 쓰러져 눕는다 (작게 튕김),
##    날개는 몸을 따라 접혀 땅에 늘어진다. 정화를 기다리는 동안 그대로 숨만 쉰다.
##  - 정화: 고개를 들고 날개가 맑게 펴지며 빛으로 흩어진다 (방이 보스의 modulate 를 하얗게 지운다).
## 박자 보이기(그대로): 예고 동안 '하나·둘'마다 몸 둘레에 고리가 한 겹씩 번지고, '셋'에 터진다.
## 2페이즈: 날개에 검은 금(crack_amount)과 흘러내리는 수액 방울이 는다.
## 세기 조절: 아래 상수 / 자세 각도는 data/rigs/_archetypes/sap_queen.json.

## 예전 한 장 그림용 (뼈대를 못 읽어 texture 를 대신 띄울 때만): 그림이 오른쪽을 보면 true
@export var art_faces_right := true
## art/rigs/<rig_id>/rig.json
@export var rig_id := "sap_queen"

## 날개 크기 배율 (시트 비율보다 조금 크게 — 보스 날개가 몸통 판정 폭 340 에 맞게)
const WING_SCALE := 1.1
## 날갯짓 빠르기(rad/s)
const FLAP_HOVER := 6.5
const FLAP_TELEGRAPH := 12.0
const FLAP_LANDED := 2.0
## 날갯짓 세기: 뿌리에서 도는 각도(도)와 가로 접힘(0~1)
const FLAP_ROT := 10.0
const FLAP_FOLD := 0.24
## 날개 넷의 위상 (uf, ub, lf, lb): 위 날개가 앞서고 아래 날개가 늦게, 왼·오른도 조금 어긋난다
const WING_PHASE := [0.0, 0.16, -0.7, -0.52]
## 왈츠 박 강세 (몸이 가라앉는 세기, 첫 박 / 둘째·셋째 박)
const BEAT_DIP_DOWN := 0.9
const BEAT_DIP_UP := 0.45
## 휘두름: 셋째 박보다 먼저 출발하는 시간(초)과 공격 한 박 중 휘두름이 끝나는 몫 (히트 순간에 팔이 가장 빠르게)
const STRIKE_LEAD := 0.1
const STRIKE_PART := 0.5
## 쓰러짐: 땅에 닿은 뒤 무릎 풀림 → 옆으로 앉음 → (잠깐) → 짚은 팔 쪽으로 기울어 → 누움 시각 (초)
## (다리는 옆으로 모은 쪽에 그대로 두고 몸만 반대쪽으로 넘어간다 — 다리가 땅을 짚어 몸을 들어 올리지 않게)
const FALL_CLIP := [0.0, 0.2, 0.55, 0.8, 1.0, 1.25]
## 무너짐: 땅에 닿은 뒤 무릎 풀림 → 옆으로 앉음 (초)
const BROKEN_CLIP := [0.0, 0.2, 0.6]
## 돌아설 때 몸통이 가장 좁아지는 폭 (날개는 0 까지 접혔다 펴진다 — 몸은 둥근 몸이라 종이처럼 납작해지지 않게)
const TURN_BODY_MIN := 0.3
## 돌아서기 빠르기 (스프링 강성 — 클수록 빨리 돈다. 260 ≈ 0.3초)
const TURN_STIFF := 260.0
## 박자 고리 반지름(px)과 두께
const RING_R := 150.0
const RING_W := 3.0
## 잔상 간격(초)
const GHOST_INTERVAL := 0.03
## 손의 수액빛: 색(HDR — 1 을 넘으면 글로우가 번진다)과 크기
const GLOW_COLOR := Color(1.3, 1.9, 2.1)
const GLOW_SCALE := 0.72
## 뼈대를 못 읽었을 때 한 장 그림(boss_sap_queen_now.png — tools/queen_film.tscn -- --render 가 만든 조립 그림)의 배율·높이:
## 그림 1px = 게임 1/2.4px, 발끝이 그림 가운데에서 188px(게임) 아래
const FALLBACK_SCALE := 1.0 / 2.4
const FALLBACK_LIFT := 188.3

var rig: PartRig
var motion: RigMotion

var _boss: SapQueen
var _t := 0.0
var _mir := RigMotion.Chan.new(-1.0)
var _face_target := -1
var _face_hold := 0.0
var _flap_phase := 0.0
var _flap_rate := FLAP_HOVER
var _flap_rot := FLAP_ROT
var _flap_fold := FLAP_FOLD
var _fold := 0.0               # 날개 전체 접힘 (0 펼침 ~ 1 접힘)
var _tremble := 0.0
var _settle := 0.0
var _state_from := {}          # 상태(공격 예고)에 들어설 때 보이던 자세
var _rec_from := {}            # 되돌림을 시작할 때 보이던 자세
var _prev_phase := ""
var _prev_flash := 0.0
var _down_t := -1.0            # 무너짐·쓰러짐: 땅에 닿은 뒤 지난 시간 (-1 = 아직 공중)
var _land_t := -1.0            # 내려앉은 뒤 지난 시간
var _purify_t := -1.0
var _thud_done := false
var _vel := Vector2.ZERO       # 부드럽게 한 속도 (기울기·끌림용)
var _last_pos := Vector2.ZERO
var _beat_pulse := 0.0         # 박이 바뀐 순간 1 → 0
var _burst := 0.0              # '셋' 터짐 1 → 0
var _ghost_timer := 0.0
var _trail: PackedVector2Array = []   # 내리꽂기 꼬리 (세계 좌표)
var _wing_i := PackedInt32Array()     # uf, ub, lf, lb 뼈 번호
var _wing_sign := PackedFloat32Array([-1.0, 1.0, -1.0, 1.0])   # '위로'의 부호 (f 는 −, b 는 +)
var _crack_nodes: Array[Node2D] = []
var _crack_drawn := -1.0
var _drips: CPUParticles2D
var _shimmer: CPUParticles2D
var _dust: CPUParticles2D
var _marks: Node2D
var _glows: Array[Sprite2D] = []   # 두 손의 수액빛 (공격을 모으는 손이 보이게)
var _glow_amt := 0.0
var _striking := false        # 휘두르는 중 (세 박자의 타격 구간)
var _ok := false


func _ready() -> void:
	_boss = get_parent() as SapQueen
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if _boss:
		_face_target = _boss.facing
		_mir.v = 1.0 if _boss.facing > 0 else -1.0
		_last_pos = _boss.global_position
		_boss.state_changed.connect(_on_state_changed)
		_boss.beat.connect(_on_beat)
	rig = PartRig.new()
	rig.name = "Rig"
	add_child(rig)
	if rig.build(rig_id):
		texture = null   # 조립 그림 한 장은 뼈대를 못 읽을 때만
		motion = RigMotion.new(rig)
		motion.breath = 0.7
		rig.setup_ghosts(rig.data.get("ghost", ["arm_f_up", "arm_f_lo", "hand_f"]), 6)
		for nm in ["wing_uf", "wing_ub", "wing_lf", "wing_lb"]:
			_wing_i.append(rig.bone_index(nm))
		_state_from = motion.pose("hover")
		_rec_from = _state_from
		_build_cracks()
		_build_glows()
		_ok = true
	else:
		rig.queue_free()
		rig = null
		position = Vector2(0, -FALLBACK_LIFT)
		scale = Vector2.ONE * FALLBACK_SCALE
	# 박자 고리·착지 표시·내리꽂기 꼬리는 세계 좌표에 그린다 (그림의 기울기와 무관하게)
	_marks = Node2D.new()
	_marks.top_level = true
	# 여왕 그림 바로 뒤, 배경·지형·수면보다는 앞 (z -1 이면 불투명한 배경 뒤에 숨어 안 보였다 — 2026-10-19 검토)
	_marks.z_index = 0
	_marks.show_behind_parent = true
	add_child(_marks)
	_marks.draw.connect(_draw_marks)
	# 흘러내리는 수액 방울 (아래 날개·치마 끝에서)
	_drips = CPUParticles2D.new()
	_drips.amount = 10
	_drips.lifetime = 1.4
	_drips.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_drips.emission_rect_extents = Vector2(110, 26)
	_drips.direction = Vector2(0, 1)
	_drips.spread = 8.0
	_drips.gravity = Vector2(0, 420)
	_drips.initial_velocity_min = 10.0
	_drips.initial_velocity_max = 40.0
	_drips.texture = _dot_texture()
	_drips.scale_amount_min = 0.22
	_drips.scale_amount_max = 0.42
	_drips.color = Color(0.5, 0.9, 1.0, 0.8)
	_drips.local_coords = false
	add_child(_drips)
	# 예고의 반짝이는 날개가루
	_shimmer = CPUParticles2D.new()
	_shimmer.amount = 26
	_shimmer.lifetime = 0.8
	_shimmer.emitting = false
	_shimmer.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_shimmer.emission_rect_extents = Vector2(190, 70)
	_shimmer.direction = Vector2(0, -1)
	_shimmer.spread = 180.0
	_shimmer.gravity = Vector2(0, -40)
	_shimmer.initial_velocity_min = 10.0
	_shimmer.initial_velocity_max = 50.0
	_shimmer.texture = _dot_texture()
	_shimmer.scale_amount_min = 0.18
	_shimmer.scale_amount_max = 0.45
	_shimmer.color = Color(1.2, 1.4, 1.5, 0.9)
	_shimmer.local_coords = false
	add_child(_shimmer)
	# 착지 먼지·물보라
	_dust = CPUParticles2D.new()
	_dust.top_level = true
	_dust.emitting = false
	_dust.one_shot = true
	_dust.explosiveness = 1.0
	_dust.amount = 16
	_dust.lifetime = 0.6
	_dust.direction = Vector2(0, -1)
	_dust.spread = 85.0
	_dust.gravity = Vector2(0, 300)
	_dust.initial_velocity_min = 100.0
	_dust.initial_velocity_max = 320.0
	_dust.texture = _dot_texture()
	_dust.scale_amount_min = 0.3
	_dust.scale_amount_max = 0.8
	_dust.color = Color(0.7, 0.95, 1.0, 0.7)
	add_child(_dust)


## 입자용 둥근 점 (흰 가운데 → 투명 가장자리, 16px). 한 번만 만들어 함께 쓴다.
static var _dot: GradientTexture2D
static func _dot_texture() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.width = 16
		_dot.height = 16
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
	return _dot


## 두 손의 수액빛: 손바닥 자리에 붙인 더하기 혼합 빛. 공격을 모으는 동안 차오르고 셋째 박에 터진다.
func _build_glows() -> void:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.8, 0.95, 1.0, 0.45), Color(0.6, 0.9, 1.0, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for nm in ["hand_f", "hand_b"]:
		var i := rig.bone_index(nm)
		if i < 0:
			continue
		var s := Sprite2D.new()
		s.name = "Glow_" + nm
		s.texture = gt
		s.material = add
		s.scale = Vector2.ONE * GLOW_SCALE
		s.modulate = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, 0.0)
		rig.attach(nm, s, Vector2(0, rig.bone_len[i] * 0.55))
		_glows.append(s)


## 2페이즈 날개의 금: 날개 그림마다 자식 노드를 붙여 그림 px 좌표로 그린다 (날개의 회전·접힘·눌림을 그대로 탄다).
## 금 모양은 여기서 한 번만 만든다 (매 프레임 난수 안 씀). 그릴 때는 crack_amount 만큼 늘인다.
func _build_cracks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for nm in ["wing_uf", "wing_ub", "wing_lf", "wing_lb"]:
		var spr := rig.sprite_of(nm)
		if spr == null or spr.texture == null:
			continue
		var sz := spr.texture.get_size()
		var root := -spr.offset   # 날개 뿌리 (그림 px)
		# 금은 날개 막 안에서만 (그림의 투명한 곳으로 빠져나가면 거기서 멈춘다)
		var img := spr.texture.get_image()
		if img and img.is_compressed():
			img.decompress()
		var lines: Array = []
		for i in 6:
			# 날개 안쪽에서 바깥 가장자리로 지그재그로 갈라져 나가는 금
			var start := root.lerp(Vector2(rng.randf_range(sz.x * 0.15, sz.x * 0.85), rng.randf_range(sz.y * 0.15, sz.y * 0.85)), rng.randf_range(0.3, 0.6))
			if not _opaque(img, start):
				continue
			var dir := (start - root).normalized()
			var steps: Array = []
			var p := start
			for j in 5 + rng.randi() % 4:
				dir = dir.rotated(rng.randf_range(-0.8, 0.8))
				var step := dir * rng.randf_range(sz.x * 0.03, sz.x * 0.07)
				if not _opaque(img, p + step):
					break
				p += step
				steps.append(step)
			if steps.size() >= 2:
				lines.append([start + spr.offset, steps])
		var node := Node2D.new()
		node.name = "Cracks"
		node.visible = false
		spr.add_child(node)
		node.draw.connect(_draw_cracks.bind(node, lines))
		_crack_nodes.append(node)


static func _opaque(img: Image, p: Vector2) -> bool:
	if img == null:
		return true
	var x := int(p.x)
	var y := int(p.y)
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return false
	return img.get_pixel(x, y).a > 0.6


func _draw_cracks(node: Node2D, lines: Array) -> void:
	var k := _crack_drawn
	if k <= 0.01:
		return
	for line in lines:
		var p: Vector2 = line[0]
		var pts := PackedVector2Array([p])
		for step in line[1]:
			p += step * k
			pts.append(p)
		# 그림 px 라 화면에선 약 0.45배 — 넉넉히 굵게
		# 화면에선 약 0.45배로 줄어 보인다 — 매끈하게 하면(antialiased) 줄어든 선이 점선처럼 끊겨 보여서 끈다
		node.draw_polyline(pts, Color(0.06, 0.04, 0.03, 0.8 * k), 6.0)
		node.draw_polyline(pts, Color(0.5, 0.9, 1.0, 0.5 * k), 2.2)


func _on_state_changed(st: SapQueen.State) -> void:
	if not _ok:
		return
	# 새 상태는 지금 보이는 자세에서 시작한다 (예고·되돌림의 출발점)
	_state_from = motion.capture()
	_rec_from = _state_from
	motion.transition(0.12)
	match st:
		SapQueen.State.LANDED:
			_land_t = 0.0
			motion.kick("crouch", 2.6)
			motion.kick("squash", 2.0)
			_puff(0.0)
			_burst = 1.0   # 셋째 박에 앉는 순간 터지는 고리
		SapQueen.State.CRACK:
			motion.kick("impact", 120.0)
		SapQueen.State.BROKEN:
			motion.kick("impact", 160.0)
			_down_t = 0.0 if _boss.is_ground() else -1.0
			_land_t = -1.0
		SapQueen.State.FALLEN:
			motion.kick("impact", 200.0)
			_down_t = -1.0
			_land_t = -1.0
			_thud_done = false
		SapQueen.State.PURIFIED:
			_purify_t = 0.0
		SapQueen.State.INTRO, SapQueen.State.WAIT, SapQueen.State.TAKEOFF:
			_down_t = -1.0
			_land_t = -1.0
			if st != SapQueen.State.TAKEOFF:
				_purify_t = -1.0
				_settle = 0.0
				rig.set_dissolve(0.0)


func _on_beat(i: int) -> void:
	_beat_pulse = 1.0
	if _boss and _boss.attack_phase == "active" and i == 2:
		_burst = 1.0
	if not _ok or _boss == null:
		return
	# 왈츠 강세: 박마다 몸이 살짝 가라앉았다 떠오른다 (첫 박이 크게). 쓰러진 뒤엔 없음.
	if _boss.state in [SapQueen.State.BROKEN, SapQueen.State.FALLEN, SapQueen.State.PURIFIED, SapQueen.State.CRACK]:
		return
	motion.kick("crouch", BEAT_DIP_DOWN if i == 0 else BEAT_DIP_UP)


func _process(delta: float) -> void:
	_t += delta
	if _boss == null:
		return
	if not _ok:
		_fallback_process(delta)
		return
	if not _boss.visible:
		_last_pos = _boss.global_position
		return
	var st := _boss.state
	var ph := _boss.attack_phase
	var gs := rig.game_scale
	# ---- 속도 (세상 px/초, 부드럽게) ----
	var moved := _boss.global_position - _last_pos
	_last_pos = _boss.global_position
	if moved.length() > 300.0:
		moved = Vector2.ZERO   # 순간 이동 (싸움 시작·되돌림)
	var v_now := moved / maxf(delta, 0.0001)
	_vel = _vel.lerp(v_now, 1.0 - exp(-8.0 * delta))

	# ---- 방향: 0.1초에 한 번만 받아들이고, 보이는 폭이 +1 → 0 → −1 을 지나며 빙글 돈다 (왈츠의 회전) ----
	_face_hold += delta
	if _boss.facing != _face_target and _face_hold >= 0.1:
		_face_target = _boss.facing
		_face_hold = 0.0
	# 임계 감쇠 스프링: 천천히 출발해 가속하고 끝에서 부드럽게 선다 (지수 감쇠는 첫 프레임에 확 튄다)
	_mir.spring(1.0 if _face_target > 0 else -1.0, TURN_STIFF, 2.0 * sqrt(TURN_STIFF), delta)
	_mir.v = clampf(_mir.v, -1.0, 1.0)
	var fvis := 1.0 if _mir.v >= 0.0 else -1.0

	# ---- 일회성 사건 ----
	if ph != _prev_phase:
		if ph == "active":
			_burst = 1.0
			motion.kick("squash", -1.2)
			if st == SapQueen.State.WAVE:
				_puff(float(_boss.facing) * 60.0, _boss.surface_y)
		elif ph == "recovery":
			_rec_from = motion.capture()
		_prev_phase = ph
	var fl := _boss.flash_amount()
	if fl > _prev_flash + 0.4 and st not in [SapQueen.State.BROKEN, SapQueen.State.FALLEN]:
		motion.kick("impact", 90.0)
		_tremble = maxf(_tremble, 0.6)
	_prev_flash = fl
	var grounded := _boss.is_ground()
	if st in [SapQueen.State.BROKEN, SapQueen.State.FALLEN]:
		if grounded and _down_t < 0.0:
			# 땅에 닿은 순간: 무릎 풀림은 지금 보이는 (떨어지던) 자세에서 시작한다
			_down_t = 0.0
			_state_from = motion.capture()
			motion.kick("crouch", 2.2)
			_puff(0.0)
		elif _down_t >= 0.0:
			_down_t += delta
	if _land_t >= 0.0:
		_land_t += delta
	if _purify_t >= 0.0:
		_purify_t += delta
	_beat_pulse = maxf(_beat_pulse - delta * 3.0, 0.0)
	_burst = maxf(_burst - delta * 2.6, 0.0)

	# ---- 목표 자세 ----
	var p: Dictionary
	var drive := RigMotion.Drive.NORMAL
	var rate := FLAP_HOVER
	var frot := FLAP_ROT
	var ffold := FLAP_FOLD
	var fold := 0.0
	var tremble := 0.0
	var ghost := false
	var settle := 0.0
	var breath := 0.7
	var air_drag := 1.0
	var tg := _boss.telegraph_amount
	match st:
		SapQueen.State.HOVER, SapQueen.State.INTRO, SapQueen.State.WAIT:
			p = _hover_pose()
			if st == SapQueen.State.INTRO:
				rate = 8.0
				frot = 13.0
		SapQueen.State.DUST:
			p = _three("cast_up", "dust_strike", "dust_ready")
			drive = _three_drive()
			rate = lerpf(FLAP_HOVER, FLAP_TELEGRAPH, tg)
			frot = lerpf(FLAP_ROT, 5.0, tg)
			tremble = smoothstep(0.5, 1.0, tg) if ph == "startup" and not _striking else 0.0
			ghost = _striking
			if _striking or ph == "active":
				rate = 14.0
				frot = 16.0
		SapQueen.State.WAVE:
			p = _three("wave_windup", "wave_strike", "wave_ready")
			drive = _three_drive()
			rate = 8.0 + tg * 4.0
			tremble = smoothstep(0.6, 1.0, tg) * 0.6 if ph == "startup" and not _striking else 0.0
			ghost = _striking
			if _striking or ph == "active":
				rate = 12.0
				frot = 18.0
		SapQueen.State.BUTTERFLIES:
			p = _three("gather", "release", "release_ready")
			drive = _three_drive()
			if ph == "startup" and not _striking:
				fold = Motion.ease_out(tg, 2.0) * 0.75   # 날개를 모아 접는다 (나비를 빚는 동안)
				rate = 4.0
				frot = 4.0
				tremble = smoothstep(0.55, 1.0, tg) * 0.5
			elif _striking or ph == "active":
				rate = 16.0   # 펼치며 놓아준다
				frot = 15.0
			ghost = _striking
		SapQueen.State.LAND:
			var dv := _boss.dive_amount
			if dv > 0.0:
				# 내리꽂기: 날개를 위로 접고 두 팔을 머리 위로 곧게 — 셋째 박에 딱 앉는다
				var k := clampf(dv * 1.6, 0.0, 1.0)
				p = motion.mix(motion.pose("land_rise"), motion.pose("dive"), Motion.ease_out(k, 2.0))
				fold = 0.65 * k
				rate = 4.0
				frot = 3.0
				ghost = true
				drive = RigMotion.Drive.QUICK
				air_drag = 0.3
			else:
				p = motion.three_beat(_state_from, motion.pose("land_rise"), motion.pose("dive"), motion.pose("landed"), "windup", _boss.windup_progress)
				drive = RigMotion.Drive.SOFT
				rate = 9.0 + tg * 3.0
				frot = 12.0
		SapQueen.State.LANDED:
			# 받음(무릎을 굽혀 착지) → 춤추듯 쉰다: 왈츠 박에 맞춰 좌우로 흔들며 숨쉬기
			var lt := maxf(_land_t, 0.0)
			p = motion.sample_clip([[0.0, "dive"], [0.1, "land_impact", "out"], [0.65, "landed", "smooth"]], lt)
			if lt > 0.5:
				p = _waltz_rest(p, smoothstep(0.5, 1.2, lt))
				# 박마다 무릎을 살짝 굽혔다 편다 (땅에 서 있으면 몸 높이 강세가 발끝에 막히므로 무릎으로 — 첫 박이 깊게)
				var pl := clampf(motion.spring_value("crouch") * 260.0, -6.0, 14.0)
				p["leg_f_up"] = float(p["leg_f_up"]) - pl
				p["leg_f_lo"] = float(p["leg_f_lo"]) + pl * 1.8
				p["pointe_f"] = float(p["pointe_f"]) - pl * 0.6
				p["leg_b_up"] = float(p["leg_b_up"]) + pl
				p["leg_b_lo"] = float(p["leg_b_lo"]) - pl * 1.8
				p["pointe_b"] = float(p["pointe_b"]) + pl * 0.6
			drive = RigMotion.Drive.QUICK if lt < 0.15 else RigMotion.Drive.SOFT
			rate = FLAP_LANDED
			frot = 5.0
			ffold = 0.12
			settle = 1.0
			breath = 1.0
		SapQueen.State.TAKEOFF:
			p = motion.pose("takeoff")
			drive = RigMotion.Drive.SOFT
			rate = 11.0
			frot = 16.0
		SapQueen.State.CRACK:
			p = motion.pose("crack").duplicate()
			# 경련: 몸과 고개가 잘게 떨린다
			p["torso"] = float(p["torso"]) + sin(_t * 31.0) * 3.0
			p["head"] = float(p["head"]) + sin(_t * 27.0 + 1.0) * 4.0
			drive = RigMotion.Drive.QUICK
			rate = 22.0
			frot = 4.0
			tremble = 1.0
			breath = 0.0
		SapQueen.State.BROKEN:
			breath = 0.4
			if _down_t >= 0.0:
				var c: Array = BROKEN_CLIP
				p = motion.sample_clip([[c[0], _state_from], [c[1], "knees_give", "in"], [c[2], "sit", "out"]], _down_t)
				if _down_t > c[2]:
					p = _broken_breath(p)
				settle = 1.0
				drive = RigMotion.Drive.QUICK if _down_t < c[2] else RigMotion.Drive.SOFT
				rate = 1.2
				frot = 3.0
				ffold = 0.08
				fold = 0.25
			else:
				p = motion.pose("fall_air")
				drive = RigMotion.Drive.SOFT
				rate = 3.5
				frot = 8.0
				fold = 0.3
		SapQueen.State.FALLEN, SapQueen.State.PURIFIED:
			breath = 0.25
			settle = 1.0 if (_down_t >= 0.0 or st == SapQueen.State.PURIFIED) else 0.0
			if st == SapQueen.State.PURIFIED:
				# 정화: 고개를 들고 몸을 반쯤 일으키며 날개가 맑게 펴진다
				var u := Motion.ease_in_out(clampf(_purify_t / 1.2, 0.0, 1.0))
				p = motion.mix(motion.pose("lie"), motion.pose("purified"), u)
				drive = RigMotion.Drive.SLOW
				rate = 2.5
				frot = 6.0 * u
				fold = 0.6 * (1.0 - u)
			elif _down_t >= 0.0:
				var c: Array = FALL_CLIP
				p = motion.sample_clip([[c[0], _state_from], [c[1], "knees_give", "in"], [c[2], "sit", "out"], [c[3], "sit", "hold"], [c[4], "topple", "in"], [c[5], "lie", "smooth"]], _down_t)
				drive = RigMotion.Drive.QUICK if _down_t < c[5] else RigMotion.Drive.SOFT
				rate = 0.8
				frot = 2.0 if _down_t < c[5] else 0.6
				ffold = 0.05
				fold = clampf((_down_t - c[2]) / (c[5] - c[2]), 0.0, 1.0) * 0.75
				if _down_t >= c[5] and not _thud_done:
					# 옆으로 쓰러져 땅에 닿는 순간: 작게 튕긴다
					_thud_done = true
					motion.kick("thud", 9.0)
					motion.kick("impact", -60.0)
					_puff(0.0)
			else:
				p = motion.pose("fall_air")
				drive = RigMotion.Drive.SOFT
				rate = 3.0
				frot = 7.0
				fold = 0.35
	# 손의 수액빛: 공격을 모으는 동안 차오르고 셋째 박에 가득, 되돌림에 잦아든다
	var glow := 0.12
	match st:
		SapQueen.State.DUST, SapQueen.State.WAVE, SapQueen.State.BUTTERFLIES:
			match ph:
				"startup": glow = 0.15 + 0.75 * tg
				"active": glow = 1.0
				_: glow = 0.3
		SapQueen.State.LAND:
			glow = 0.8 if _boss.dive_amount > 0.0 else 0.2 + 0.5 * tg
		SapQueen.State.CRACK:
			glow = 0.35 + 0.3 * sin(_t * 23.0)
		SapQueen.State.BROKEN, SapQueen.State.FALLEN:
			glow = 0.0
		SapQueen.State.PURIFIED:
			glow = 0.45 * (1.0 - rig.dissolve_amount())
	_glow_amt = Motion.damp(_glow_amt, glow, 14.0 if glow > _glow_amt else 4.0, delta)
	var ga := clampf(_glow_amt + _burst * 0.4, 0.0, 1.2)
	for g in _glows:
		g.modulate = Color(GLOW_COLOR.r, GLOW_COLOR.g, GLOW_COLOR.b, ga * 0.75)
		g.scale = Vector2.ONE * GLOW_SCALE * (0.7 + 0.5 * ga + 0.06 * sin(_t * 9.0))
	# 맞은 순간: 잠깐 움찔 (자세 hit 를 조금 섞는다)
	if fl > 0.05 and st in [SapQueen.State.HOVER, SapQueen.State.LANDED]:
		p = motion.mix(p, motion.pose("hit"), fl * 0.5)

	# ---- 날기: 속도 쪽으로 기울고, 다리·팔이 뒤로 끌린다 (보이는 방향 기준 + = 앞) ----
	var sp_f := _vel.x * fvis
	if settle < 0.5 and st != SapQueen.State.PURIFIED:
		p = p.duplicate()
		var lean_add := clampf(sp_f * 0.012, -9.0, 9.0) * air_drag
		p["lean"] = float(p.get("lean", 0.0)) + lean_add
		var drag := clampf(sp_f * 0.02, -14.0, 14.0) * air_drag
		for k in ["leg_f_up", "leg_b_up"]:
			p[k] = float(p[k]) + drag
		for k in ["leg_f_lo", "leg_b_lo"]:
			p[k] = float(p[k]) + drag * 0.6
		# 위로 빨리 오르면 다리가 곧게 늘어지고, 내려가면 발끝이 조금 들린다
		var rise := clampf(-_vel.y * 0.01, -6.0, 6.0) * air_drag
		p["leg_b_lo"] = float(p["leg_b_lo"]) - rise
		p["leg_f_lo"] = float(p["leg_f_lo"]) + rise * 0.5

	# ---- 날개: 접힘·떨림 정도를 부드럽게 ----
	_flap_rate = Motion.damp(_flap_rate, rate, 5.0, delta)
	_flap_rot = Motion.damp(_flap_rot, frot, 6.0, delta)
	_flap_fold = Motion.damp(_flap_fold, ffold, 6.0, delta)
	_fold = Motion.damp(_fold, fold, 7.0, delta)
	_tremble = Motion.damp(_tremble, tremble, 10.0, delta)
	_flap_phase += _flap_rate * delta
	# 돌아서기: 몸 폭은 TURN_BODY_MIN 까지만 줄고(그 순간 좌우가 바뀐다), 날개는 나머지 몫만큼 더 접혀 0 을 지난다
	var turn_abs := absf(_mir.v)
	var body_w := maxf(turn_abs, TURN_BODY_MIN)
	var turn_w := turn_abs / body_w
	for w in 4:
		var wi := _wing_i[w]
		if wi < 0:
			continue
		var phw := _flap_phase + float(WING_PHASE[w])
		var sx := (1.0 - _flap_fold * pow(sin(phw), 2.0)) * (1.0 - 0.55 * _fold) * turn_w
		rig.scl[wi] = Vector2(WING_SCALE * maxf(sx, 0.02), WING_SCALE * (1.0 - 0.08 * _fold))

	_settle = Motion.damp(_settle, settle, 9.0 if settle > _settle else 5.0, delta)
	motion.ground_settle = _settle
	motion.ground_lock = _settle
	motion.breath = breath
	motion.set_target(p, drive, RigMotion.Feet.POSE)
	motion.update(delta, {"speed": sp_f / gs, "dx": moved.x * fvis / gs, "vy": _vel.y / gs, "grounded": _settle > 0.5})

	# 날갯짓 각도: 스프링 뒤에 더한다 (빠른 날갯짓이 스프링에 뭉개지지 않게). 접힌 만큼 위로 젖힌다.
	var shiver := _tremble * 2.2
	for w in 4:
		var wi := _wing_i[w]
		if wi < 0:
			continue
		var phw := _flap_phase + float(WING_PHASE[w])
		var up := sin(phw) * _flap_rot + _fold * 18.0 + sin(_t * 47.0 + w * 1.7) * shiver
		rig.rot[wi] += deg_to_rad(up * _wing_sign[w])
	rig.apply()

	# ---- 놓기: 원점 = 발이 닿는 땅 (날 때는 보스 원점 바로 위에 떠 있다) ----
	var sq := clampf(motion.spring_value("squash"), -0.3, 0.3) * 0.08
	var shake := sin(_t * 40.0) * 1.5 * _tremble if st == SapQueen.State.CRACK else 0.0
	rig.position = Vector2(shake, 0.0)
	rig.scale = Vector2(fvis * body_w * (1.0 + sq), 1.0 - sq)
	# 잔상
	if ghost:
		_ghost_timer += delta
		if _ghost_timer >= GHOST_INTERVAL:
			_ghost_timer = 0.0
			rig.snapshot_ghost(Color(0.7, 0.95, 1.0, 0.32))
	else:
		_ghost_timer = 0.0
	rig.fade_ghosts(delta, 4.0)
	# 내리꽂기 꼬리 (세계 좌표 — 잔상은 몸과 함께 움직여 꼬리가 안 남는다)
	if st == SapQueen.State.LAND and _boss.dive_amount > 0.0:
		_trail.append(_boss.global_position + Vector2(0, -150))
		if _trail.size() > 8:
			_trail.remove_at(0)
	elif _trail.size() > 0:
		_trail.remove_at(0)

	# ---- 입자 ----
	_shimmer.emitting = tg > 0.05 and st in [SapQueen.State.DUST, SapQueen.State.BUTTERFLIES]
	_shimmer.global_position = _boss.global_position + Vector2(0, -150)
	# 2페이즈일수록 수액이 많이 흘러내린다 (CPUParticles2D 는 amount_ratio 가 없어 진하기·속도로)
	_drips.emitting = st != SapQueen.State.PURIFIED
	_drips.modulate = Color(1, 1, 1, 0.45 + 0.55 * _boss.crack_amount)
	_drips.speed_scale = 0.8 + 0.7 * _boss.crack_amount
	_drips.global_position = _boss.global_position + Vector2(0, -80)

	# ---- 2페이즈 금 (값이 바뀔 때만 다시 그린다) ----
	var ck := _boss.crack_amount
	if _purify_t >= 0.0:
		ck *= clampf(1.0 - _purify_t / 1.0, 0.0, 1.0)   # 정화되며 금이 아문다
	if absf(ck - _crack_drawn) > 0.01:
		_crack_drawn = ck
		for n in _crack_nodes:
			n.visible = ck > 0.01
			n.queue_redraw()

	# ---- 색: 수액빛 바탕, 예고 반짝임, 셋 터짐, 2페이즈 조금 어둡게, 쓰러지면 잿빛, 정화되면 맑게 ----
	var base := Color(0.97, 1.0, 1.04) if _boss.phase == 1 else Color(0.9, 0.92, 0.9)
	base = base.lerp(Color(1.3, 1.45, 1.55), tg * (0.55 + 0.45 * sin(_t * 26.0)))
	base = base.lerp(Color(1.55, 1.65, 1.75), _burst * 0.45)
	if st == SapQueen.State.FALLEN:
		base = base.lerp(Color(0.62, 0.64, 0.68), clampf(_down_t, 0.0, 1.0) * 0.55 + 0.05)
	elif st == SapQueen.State.PURIFIED:
		base = Color(0.75, 0.78, 0.82).lerp(Color(1.5, 1.7, 1.8), clampf(_purify_t / 0.9, 0.0, 1.0))
		rig.set_dissolve(clampf((_purify_t - 0.6) / 1.2, 0.0, 1.0), Color(1.4, 1.8, 2.0))
	elif st == SapQueen.State.BROKEN:
		base = base.lerp(Color(0.8, 0.84, 0.86), 0.3)
	rig.modulate = base
	rig.set_flash(fl * 0.75, Color(1.8, 1.9, 2.0))
	_marks.queue_redraw()


## 떠 있을 때: 둥글게 내린 팔이 왈츠 박에 맞춰 천천히 흔들리고, 몸이 마디(3박)마다 좌우로 기운다.
func _hover_pose() -> Dictionary:
	var p: Dictionary = motion.pose("hover").duplicate()
	var bar := (_boss.beat_index() + _boss.beat_phase()) / 3.0 * TAU
	var s := sin(bar)
	p["torso"] = float(p["torso"]) + s * 3.0
	p["head"] = float(p["head"]) + sin(bar - 0.6) * 3.0
	p["arm_f_up"] = float(p["arm_f_up"]) - (s * 0.5 + 0.5) * 10.0
	p["arm_b_up"] = float(p["arm_b_up"]) + (-s * 0.5 + 0.5) * 10.0
	p["arm_f_lo"] = float(p["arm_f_lo"]) + s * 6.0
	p["arm_b_lo"] = float(p["arm_b_lo"]) + s * 6.0
	p["leg_b_lo"] = float(p["leg_b_lo"]) + sin(bar + 0.8) * 5.0
	p["leg_f_lo"] = float(p["leg_f_lo"]) + sin(bar + 2.0) * 3.0
	return p


## 내려앉아 쉬는 동안: 왈츠 박에 맞춰 윗몸·팔이 좌우로 흔들린다 (발끝은 땅에 둔 채 — 골반은 거의 그대로).
func _waltz_rest(p: Dictionary, w: float) -> Dictionary:
	var q: Dictionary = p.duplicate()
	var bar := (_boss.beat_index() + _boss.beat_phase()) / 3.0 * TAU
	var s := sin(bar)
	q["torso"] = float(q["torso"]) + s * 5.0 * w
	q["head"] = float(q["head"]) + sin(bar - 0.7) * 4.0 * w
	q["arm_f_up"] = float(q["arm_f_up"]) - (s * 0.5 + 0.5) * 34.0 * w
	q["arm_f_lo"] = float(q["arm_f_lo"]) - (s * 0.5 + 0.5) * 10.0 * w
	q["arm_b_up"] = float(q["arm_b_up"]) + (-s * 0.5 + 0.5) * 34.0 * w
	q["arm_b_lo"] = float(q["arm_b_lo"]) + (-s * 0.5 + 0.5) * 10.0 * w
	q["leg_f_lo"] = float(q["leg_f_lo"]) + (s * 0.5 + 0.5) * 6.0 * w
	q["leg_b_lo"] = float(q["leg_b_lo"]) - (-s * 0.5 + 0.5) * 6.0 * w
	return q


## 무너져 앉은 동안: 어깨가 들썩이고 고개가 처졌다 든다.
func _broken_breath(p: Dictionary) -> Dictionary:
	var q: Dictionary = p.duplicate()
	var s := sin(_t * 1.6)
	q["torso"] = float(q["torso"]) + s * 2.0
	q["head"] = float(q["head"]) + sin(_t * 1.6 + 0.9) * 4.0
	q["arm_f_up"] = float(q["arm_f_up"]) + s * 3.0
	return q


## 공격 세 박자: 하나·둘(예고) = windup 으로 당기며 끝에서 멈칫, 셋 = 채찍처럼 휘두름, 되돌림 = ready 로 출렁이며.
## 휘두름은 셋째 박(투사체가 나오는 순간)보다 STRIKE_LEAD 초 먼저 출발해 공격 한 박의 앞 STRIKE_PART 까지 — 나오는 순간에 팔이 가장 빠르다.
func _three(windup: String, strike: String, ready: String) -> Dictionary:
	var w := motion.pose(windup)
	var s := motion.pose(strike)
	var r := motion.pose(ready)
	var q := _boss.phase_progress()
	var strike_len := STRIKE_LEAD + STRIKE_PART * maxf(_boss.active_len, 0.05)
	_striking = false
	match _boss.attack_phase:
		"startup":
			var total := maxf(_boss.startup_len, 0.1)
			var rem := (1.0 - q) * total
			if rem > STRIKE_LEAD:
				return motion.three_beat(_state_from, w, s, r, "windup", q * total / maxf(total - STRIKE_LEAD, 0.05))
			_striking = true
			return motion.three_beat(_state_from, w, s, r, "strike", (STRIKE_LEAD - rem) / strike_len)
		"active":
			var u := (STRIKE_LEAD + q * _boss.active_len) / strike_len
			_striking = u < 1.0
			return motion.three_beat(_state_from, w, s, r, "strike", clampf(u, 0.0, 1.0))
		"recovery":
			return motion.three_beat(_rec_from, w, s, r, "recover", q)
	return r


func _three_drive() -> RigMotion.Drive:
	if _striking:
		return RigMotion.Drive.FAST
	match _boss.attack_phase:
		"startup": return RigMotion.Drive.SOFT
		"active": return RigMotion.Drive.SETTLE
		"recovery": return RigMotion.Drive.SETTLE
	return RigMotion.Drive.NORMAL


## 뼈대를 못 읽었을 때: 조립 그림 한 장을 띄우고 둥실거리기만 한다.
func _fallback_process(delta: float) -> void:
	_mir.damp(1.0 if _boss.facing > 0 else -1.0, 14.0, delta)
	var fx := _mir.v if art_faces_right else -_mir.v
	scale = Vector2(FALLBACK_SCALE * fx, FALLBACK_SCALE)
	position = Vector2(0, -FALLBACK_LIFT + sin(_t * 2.0) * 4.0)
	var fl := _boss.flash_amount()
	modulate = Color(1, 1, 1).lerp(Color(2.2, 2.2, 2.2), fl * 0.8)


func _puff(ox: float, y := INF) -> void:
	_dust.global_position = Vector2(_boss.global_position.x + ox, _boss.global_position.y if y == INF else y)
	_dust.restart()
	_dust.emitting = true


## 세계 좌표에 그리는 것: 박자 고리 (하나 1겹, 둘 2겹, 셋 터짐), 내려앉을 디딤돌의 자국, 내리꽂기 꼬리
func _draw_marks() -> void:
	if _boss == null or not _boss.visible:
		return
	var c := _boss.global_position + Vector2(0, -130)
	var st := _boss.state
	if _boss.attack_phase == "startup":
		var rings := 1 + _boss.beat_index() % 3
		rings = mini(rings, 2)
		for i in rings:
			var r := RING_R + i * 34.0 + (1.0 - _beat_pulse) * 12.0
			_marks.draw_arc(c, r, 0.0, TAU, 48, Color(0.75, 0.98, 1.0, 0.25 + 0.45 * _beat_pulse), RING_W + 2.0 * _beat_pulse, true)
	if _burst > 0.0:
		var r := RING_R + (1.0 - _burst) * 220.0
		_marks.draw_arc(c, r, 0.0, TAU, 56, Color(0.9, 1.0, 1.0, 0.6 * _burst), RING_W * 2.0 * _burst + 1.0, true)
	# 내려앉기 예고: 디딤돌 위에 빛 자국
	if st == SapQueen.State.LAND and _boss._land_stone and is_instance_valid(_boss._land_stone):
		var s: Node2D = _boss._land_stone
		var top := Vector2(s.global_position.x, s.global_position.y)
		var w: float = s.size.x
		var p := _boss.windup_progress
		var pulse := 0.5 + 0.5 * sin(_t * (8.0 + 20.0 * p))
		_marks.draw_rect(Rect2(top + Vector2(0, -8), Vector2(w, 10)), Color(0.8, 1.0, 1.0, 0.2 + 0.4 * p * pulse))
	# 내리꽂기 꼬리: 지나온 자리를 옅은 수액빛 띠로
	if _trail.size() >= 2:
		for i in range(1, _trail.size()):
			var a := float(i) / _trail.size()
			_marks.draw_line(_trail[i - 1], _trail[i], Color(0.75, 0.95, 1.0, 0.35 * a), 30.0 * a, true)

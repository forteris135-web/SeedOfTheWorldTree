extends EnemyRigVisual
## 수액 어부의 그림: 부위 뼈대(EnemyRigVisual) + **줄 물리로 움직이는 낚싯줄**.
## 줄은 뼈대 설계도(data/rigs/sap_fisher*.json)의 숨은 부위 whip_00(끝) ~ whip_NN(손 쪽) 덩굴 조각들이다.
## PartRig 는 숨은 부위를 그리지 않으므로 이 그림이 조각을 직접 뼈대 그림 노드(rig.skeleton_node()) 안, 손 그림 바로 아래 순서에 늘어놓는다
## (번쩍임·흩어짐 셰이더를 함께 쓴다). 구원되어 사람으로 돌아온 어부(RescuedPerson)는 줄 없이 선다.
##
## 줄 = 마디가 이어진 밧줄(베를레 적분: 중력·관성·땅에 닿으면 눕기). 손이 움직이면 줄이 한 박자 늦게 따라오고,
## 줄 길이는 상태마다 풀렸다 감긴다 (손 쪽에서 덩굴이 풀려 나오고 들어간다 — 끝 조각은 늘 끝에 있다).
##  - 대기·걷기: 주먹에서 늘어져 땅에 조금 눕는다. 걸으면 끌린다.
##  - 예고(하나·둘): 팔을 머리 위 뒤로 들며 두 번 펌프질 → 줄이 뒤 위로 두 번 휘날린다(박마다 끝의 수액 방울이 반짝).
##    끝자락에 머리 위로 치켜든다(예비 동작).
##  - 휘두름(셋): 판정이 켜지는 첫 프레임에 줄은 이미 머리 위를 넘어 앞 위에 와 있고, 손 쪽부터 끝 쪽으로 물결처럼 내리꽂혀
##    판정 상자의 먼 끝(사거리)까지 곧게 뻗는다. 끝은 지나쳐 출렁인다(채찍의 따라옴). 끝이 지나간 자리에 빛 자국 + 수액 방울이 튄다.
##  - 되돌림: 힘이 빠져 줄이 떨어지고 감겨 들어간다.
##  - 무너짐·쓰러짐: 줄이 힘없이 떨어져 땅에 눕는다.
## 판정·시간은 sap_fisher.gd 그대로. 옛 그림(코드로 그린 선)과 같은 박자·같은 기준점(판정 상자의 먼 끝)에 맞춘다.

## 낚싯줄 조각 이름 머리
const WHIP_PREFIX := "whip_"
## 상태별 풀린 줄 길이 (게임 px, 배율 1 기준). 휘두를 때는 판정 끝까지의 거리.
@export var idle_len := 165.0
@export var windup_len := 125.0
## 줄 끝 수액 방울 색
@export var bead_color := Color(0.55, 0.95, 1.0)

const GRAVITY := 1500.0
const DAMP := 0.985
const ITER := 8
const SUBSTEPS := 2
## 줄이 땅 위에 뜨는 높이 (px)
const FLOOR_PAD := 3.0
## 줄 끝 자국 (휘두를 때) 점 수
const TRAIL_N := 10

var _segs: Array[Sprite2D] = []           # 0 = 끝 조각
var _seg_local: Array[Transform2D] = []   # 조각 그림의 뼈 틀 변환 (PartRig 와 같은 rot·tex_scale)
var _seg_len := PackedFloat32Array()      # 뼈대 단위 길이
var _n := 0
var _pts := PackedVector2Array()          # 세상 좌표, 0 = 끝 … _m = 손
var _prev := PackedVector2Array()
var _tgt := PackedVector2Array()
var _k := PackedFloat32Array()            # 점마다 모양 잡기 세기 (1/초)
var _rest := PackedFloat32Array()         # 이번 프레임 마디 길이 (게임 px) — 제약 풀기에서 함수를 부르지 않게 미리
var _m := 0
var _len := 0.0
var _rope_ok := false
var _grip_bone := -1
var _grip := Vector2.ZERO
var _bead: Sprite2D
var _beat_flash := 0.0
var _crack := 0.0
var _prev_beat := -1
var _rope_state := -1
var _trail := PackedVector2Array()
var _trail_head := 0
var _trail_fx: Node2D
var _drops: CPUParticles2D
var _hand_prev := Vector2.ZERO
var _rope_fresh := true
## 줄 방향 (손 → 끝, 옛 그림과 같은 약속: 0 = 수직 아래, + = 바라보는 쪽(앞), −π/2 = 뒤 수평, ±π = 위). 시험(probe_lake)이 읽는다.
var _swing := 0.0


## 움직이기 직전 갈고리가 달린 움직임 (공용 RigMotion 은 그대로)
func _make_motion() -> RigMotion:
	return HookedRigMotion.new(rig, _pre_motion)


func _ready() -> void:
	super._ready()
	if not _ready_ok:
		return
	_setup_whip()


func _setup_whip() -> void:
	var bones: Array = rig.data["bones"]
	var names: Array = []
	for b in bones:
		if str(b["name"]).begins_with(WHIP_PREFIX):
			names.append(str(b["name"]))
	names.sort()
	_n = names.size()
	var socks: Dictionary = rig.data.get("sockets", {})
	if _n == 0 or not socks.has("grip"):
		return
	_grip_bone = rig.bone_index(str(socks["grip"]["bone"]))
	_grip = PartRig._v(socks["grip"]["pos"])
	var hand_spr := rig.sprite_of(str(socks["grip"]["bone"]))
	var skel: Node2D = rig.skeleton_node()
	var at := hand_spr.get_index() if hand_spr else skel.get_child_count()
	for nm in names:
		var b: Dictionary = bones[rig.bone_index(nm)]
		var s := Sprite2D.new()
		s.name = "Whip" + str(nm).substr(WHIP_PREFIX.length())
		s.texture = load(b["tex"])
		s.centered = false
		s.offset = -PartRig._v(b["pivot"])
		s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		s.use_parent_material = true
		s.visible = false
		skel.add_child(s)
		skel.move_child(s, at)   # 손 그림 바로 아래 (덩굴이 주먹 속으로 들어간다)
		at += 1
		_segs.append(s)
		var k := float(b.get("tex_scale", 2.0))
		_seg_local.append(Transform2D(deg_to_rad(float(b["rot"])), Vector2(k, k), 0.0, Vector2.ZERO))
		_seg_len.append(float(b.get("len", 100.0)))
	_pts.resize(_n + 1)
	_prev.resize(_n + 1)
	_tgt.resize(_n + 1)
	_k.resize(_n + 1)
	_rest.resize(_n + 1)
	_trail.resize(TRAIL_N)
	# 끝의 수액 방울 (더하기 빛)
	var gt := _dot_texture()
	_bead = Sprite2D.new()
	_bead.name = "SapBead"
	_bead.texture = gt
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_bead.material = add
	add_child(_bead)
	_trail_fx = Node2D.new()
	_trail_fx.name = "WhipTrail"
	var add2 := CanvasItemMaterial.new()
	add2.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_trail_fx.material = add2
	_trail_fx.draw.connect(_draw_trail)
	_trail_fx.visible = false
	add_child(_trail_fx)
	_drops = CPUParticles2D.new()
	_drops.name = "SapDrops"
	_drops.emitting = false
	_drops.one_shot = true
	_drops.explosiveness = 0.9
	_drops.amount = 10
	_drops.lifetime = 0.55
	_drops.local_coords = false
	_drops.direction = Vector2(0, -1)
	_drops.spread = 70.0
	_drops.gravity = Vector2(0, 900)
	_drops.initial_velocity_min = 80.0
	_drops.initial_velocity_max = 220.0
	_drops.scale_amount_min = 0.1
	_drops.scale_amount_max = 0.18
	_drops.texture = gt
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([Color(bead_color.r * 1.6, bead_color.g * 1.5, bead_color.b * 1.4, 1.0), Color(bead_color, 0.0)])
	_drops.color_ramp = ramp
	add_child(_drops)
	_rope_ok = true
	_rope_fresh = true   # 처음 놓기는 첫 프레임에 (땅 높이를 안 뒤에)


static var _dot: GradientTexture2D

static func _dot_texture() -> GradientTexture2D:
	if _dot == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
		_dot = GradientTexture2D.new()
		_dot.gradient = grad
		_dot.width = 32
		_dot.height = 32
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1, 0.5)
	return _dot


## 줄을 손에서 늘어뜨린다 (처음·순간 이동 뒤): 땅에 닿을 때까지 아래로, 남는 줄은 뒤쪽 땅에 눕힌다.
func _reset_rope() -> void:
	var hand := _hand_world()
	_len = idle_len * art_scale
	_m = _active_count(_len)
	var y := hand.y
	var floor_y := _floor_world() - FLOOR_PAD
	var x := hand.x
	var dirx := -signf(_mir.v) if _mir.v != 0.0 else -1.0
	_pts[_m] = hand
	_prev[_m] = hand
	for j in range(_m - 1, -1, -1):
		var l := _seg_rest(j)
		if y + l <= floor_y:
			y += l
		else:
			var down := maxf(floor_y - y, 0.0)
			y += down
			x += dirx * sqrt(maxf(l * l - down * down, 0.0))
		_pts[j] = Vector2(x, y)
		_prev[j] = _pts[j]
	_hand_prev = hand


## 풀린 길이(게임 px)에 필요한 조각 수
func _active_count(length: float) -> int:
	var acc := 0.0
	for j in _n:
		acc += _seg_world_len(j)
		if acc >= length - 0.01:
			return j + 1
	return _n


## 조각 j 의 게임 px 길이 (배율 포함)
func _seg_world_len(j: int) -> float:
	return _seg_len[j] * rig.game_scale * art_scale


## 손 쪽 마디(m-1)는 풀린 몫만큼만
func _seg_rest(j: int) -> float:
	var full := _seg_world_len(j)
	if j < _m - 1:
		return full
	var acc := 0.0
	for i in _m - 1:
		acc += _seg_world_len(i)
	return clampf(_len - acc, full * 0.05, full)


func _hand_world() -> Vector2:
	if _grip_bone < 0:
		return global_position
	return rig.to_global(rig.to_rig_local(rig.xf[_grip_bone] * _grip))


func _floor_world() -> float:
	return global_position.y + _floor_y


## 관절이 움직이기 직전 (HookedRigMotion 이 부른다): 예고 동안 줄을 쥔 팔을 박자에 맞춰 두 번 펌프질한다 (하나·둘).
func _pre_motion(_delta: float) -> void:
	if _enemy == null or _enemy.state != EnemyBase.State.WINDUP:
		return
	var p := _enemy.windup_progress
	var pump := sin(p * TAU * 2.0) * (1.0 - smoothstep(0.8, 1.0, p))
	if motion.target.has("arm_f_up"):
		motion.target["arm_f_up"] = float(motion.target["arm_f_up"]) + pump * 16.0
	if motion.target.has("arm_f_lo"):
		motion.target["arm_f_lo"] = float(motion.target["arm_f_lo"]) - absf(pump) * 14.0
	if motion.target.has("torso"):
		motion.target["torso"] = float(motion.target["torso"]) + pump * 3.0


func _process(delta: float) -> void:
	super._process(delta)
	if not _rope_ok or not _ready_ok or _enemy == null:
		return
	_update_rope(delta)
	_place_segments()


func _update_rope(delta: float) -> void:
	var st := _enemy.state
	var hand := _hand_world()
	if _rope_fresh or hand.distance_to(_hand_prev) > 220.0:
		_rope_fresh = false
		_reset_rope()   # 처음·순간 이동 (방 이동·되살아남)
	_hand_prev = hand
	var f := signf(_mir.v) if _mir.v != 0.0 else 1.0
	# ---- 상태별 목표: 풀린 길이, 모양 잡기 ----
	var want_len := idle_len * art_scale
	var reel := 260.0
	var shape := 0   # 0 없음, 1 예고(뒤 위로), 2 휘두름(앞으로 곧게)
	if st != _rope_state:
		_on_rope_state(st, hand, f)
		_rope_state = st
	match st:
		EnemyBase.State.WINDUP:
			want_len = windup_len * art_scale
			shape = 1
			var beat: int = _enemy.windup_beat() if _enemy.has_method("windup_beat") else 0
			if beat != _prev_beat:
				_beat_flash = 1.0
				_prev_beat = beat
		EnemyBase.State.STRIKE:
			shape = 2
			reel = 0.0
		EnemyBase.State.RECOVER:
			reel = 320.0
			_prev_beat = -1
		_:
			_prev_beat = -1
	if reel > 0.0:
		_len = move_toward(_len, want_len, reel * delta)
	var m_new := _active_count(_len)
	while _m < m_new:
		# 손 쪽에서 덩굴이 풀려 나온다: 손 자리에 새 마디
		_m += 1
		_pts[_m] = hand
		_prev[_m] = hand
	while _m > m_new and _m > 1:
		_m -= 1
		_pts[_m] = hand
		_prev[_m] = hand
	# ---- 마디 길이 (이번 프레임) ----
	for j in _m:
		_rest[j] = _seg_rest(j)
	# ---- 목표 모양 ----
	for j in _m + 1:
		_k[j] = 0.0
	if shape == 1:
		var p := _enemy.windup_progress
		var a0 := -2.45 + 0.45 * sin(p * TAU * 2.0)
		if p > 0.82:
			a0 = lerpf(a0, -1.8, smoothstep(0.82, 1.0, p))
		var acc := 0.0
		var pos := hand
		for i in range(_m - 1, -1, -1):   # 손 → 끝
			var t := acc / maxf(_len, 1.0)
			var a := a0 - 0.7 * t   # 끝은 뒤로 처진다
			pos += Vector2(cos(a) * f, sin(a)) * _rest[i]
			acc += _rest[i]
			_tgt[i] = pos
			_k[i] = lerpf(14.0, 5.0, t)
	elif shape == 2:
		var q := _enemy.phase_progress
		var target := _strike_target_world(f)
		var d := target - hand
		var dn := d.normalized() if d.length() > 1.0 else Vector2(f, 0)
		var acc2 := 0.0
		var i_from_hand := 0
		for i in range(_m - 1, -1, -1):
			acc2 += _rest[i]
			i_from_hand += 1
			_tgt[i] = hand + dn * acc2
			var th := float(i_from_hand) / float(_m) * 0.5
			_k[i] = 90.0 * clampf((q - th) / 0.22, 0.0, 1.0)
	# ---- 적분 ----
	var floor_y := _floor_world() - FLOOR_PAD
	var h := minf(delta, 1.0 / 30.0) / SUBSTEPS
	var vmax := 4000.0 * h
	for s in SUBSTEPS:
		for j in _m:
			var v := (_pts[j] - _prev[j]) * DAMP
			if v.length_squared() > vmax * vmax:
				v = v.normalized() * vmax
			_prev[j] = _pts[j]
			var np := _pts[j] + v + Vector2(0.0, GRAVITY * art_scale) * h * h
			if _k[j] > 0.0:
				np = np.lerp(_tgt[j], 1.0 - exp(-_k[j] * h))
			_pts[j] = np
		_pts[_m] = hand
		for it in ITER:
			for j in range(_m - 1, -1, -1):
				var a := _pts[j + 1]
				var b := _pts[j]
				var dd := b - a
				var dl := dd.length()
				if dl < 0.0001:
					continue
				var diff := (dl - _rest[j]) / dl
				if j + 1 == _m:
					_pts[j] = b - dd * diff
				else:
					_pts[j + 1] = a + dd * diff * 0.5
					_pts[j] = b - dd * diff * 0.5
			_pts[_m] = hand
		for j in _m:
			if _pts[j].y > floor_y:
				_pts[j].y = floor_y
				_prev[j].y = floor_y
				_prev[j].x = lerpf(_prev[j].x, _pts[j].x, 0.35)   # 땅에 닿은 덩굴은 끌린다 (마찰)
	# ---- 연출 값 ----
	var chord := _pts[0] - hand
	if chord.length() > 0.5:
		_swing = atan2(chord.x * f, chord.y)
	_beat_flash = maxf(_beat_flash - delta * 4.0, 0.0)
	_crack = maxf(_crack - delta * 4.5, 0.0)
	if _crack > 0.0:
		_trail[_trail_head] = _pts[0]
		_trail_head = (_trail_head + 1) % TRAIL_N
		_trail_fx.queue_redraw()
	if _trail_fx.visible != (_crack > 0.0):
		_trail_fx.visible = _crack > 0.0
	var alpha := 1.0 - rig.dissolve_amount()
	_bead.visible = alpha > 0.05
	_bead.position = to_local(_pts[0])
	_bead.modulate = Color(bead_color.r * 1.5, bead_color.g * 1.4, bead_color.b * 1.3, (0.5 + 0.5 * maxf(_beat_flash, _crack)) * alpha)
	_bead.scale = Vector2.ONE * (0.45 + 0.4 * _beat_flash + 0.6 * _crack) * sqrt(art_scale)


## 상태에 들어선 순간: 휘두름은 줄을 '이미 앞 위로 넘어온' 모양으로 놓고 판정 끝까지 풀어 둔다 (첫 프레임부터 앞을 가리키게)
func _on_rope_state(st: int, hand: Vector2, f: float) -> void:
	if st == EnemyBase.State.STRIKE:
		var target := _strike_target_world(f)
		var d := target - hand
		_len = clampf(d.length() * 1.03, idle_len * art_scale, _total_len())
		_m = _active_count(_len)
		var base := atan2(d.y, d.x * f)   # 앞 기준 각도 (+ 아래)
		var acc := 0.0
		_pts[_m] = hand
		_prev[_m] = hand
		var pos := hand
		for i in range(_m - 1, -1, -1):
			var t := acc / maxf(_len, 1.0)
			var a := base - 0.25 - 0.4 * t   # 손 쪽은 앞 조금 위, 끝은 더 위 (머리 위를 넘어와 내리꽂히는 중)
			pos += Vector2(cos(a) * f, sin(a)) * _seg_rest(i)
			_pts[i] = pos
			# 내리꽂히는 속도: 손을 축으로 앞·아래로 도는 속도 (끝일수록 빠르다)
			_prev[i] = hand + (pos - hand).rotated(-0.14 * f)
			acc += _seg_rest(i)
		_crack = 1.0
		for k in TRAIL_N:
			_trail[k] = _pts[0]
		_spray(_pts[0])
	elif st == EnemyBase.State.RECOVER and _rope_state == EnemyBase.State.STRIKE:
		_spray(_pts[0])   # 끝이 다 뻗으며 수액이 튄다


func _spray(at: Vector2) -> void:
	_drops.global_position = at
	_drops.restart()
	_drops.emitting = true


func _total_len() -> float:
	var acc := 0.0
	for j in _n:
		acc += _seg_world_len(j)
	return acc


## 휘두를 때 줄 끝이 닿을 자리 (판정 상자의 먼 끝, 높이 가운데) — 옛 그림과 같은 기준
func _strike_target_world(f: float) -> Vector2:
	var box: Rect2 = _enemy.strike_box
	return _enemy.global_position + Vector2((box.position.x + box.size.x) * f, box.position.y + box.size.y * 0.5)


## 줄 조각을 줄 마디에 놓는다: 조각 j 는 손 쪽 점(j+1)이 관절, 축(그림의 pivot → tip)이 끝 쪽 점(j)을 향한다.
## 뼈대 틀(skeleton_node() 안, body_xf 앞) 좌표로 바꿔 놓는다 → 쓰러짐·좌우 뒤집기·찌그러짐을 그대로 따른다.
func _place_segments() -> void:
	var inv := rig.body_xf.affine_inverse()
	var gs := rig.game_scale
	for j in _n:
		var s := _segs[j]
		if j >= _m:
			if s.visible:
				s.visible = false
			continue
		if not s.visible:
			s.visible = true
		var a := inv * (rig.to_local(_pts[j + 1]) / gs)
		var b := inv * (rig.to_local(_pts[j]) / gs)
		var d := b - a
		var dl := d.length()
		var sy := clampf(dl / maxf(_seg_len[j], 0.001), 0.05, 1.25)
		var rotv := d.angle() - PI * 0.5 if dl > 0.001 else 0.0
		s.transform = Transform2D(rotv, Vector2(1.0, sy), 0.0, a) * _seg_local[j]


## 휘두른 줄 끝이 지나간 자국 (더하기 빛, 점점 옅게)
func _draw_trail() -> void:
	if _crack <= 0.0:
		return
	var prev := _trail_fx.to_local(_trail[_trail_head % TRAIL_N])
	for k in range(1, TRAIL_N):
		var p := _trail_fx.to_local(_trail[(_trail_head + k) % TRAIL_N])
		var a := float(k) / TRAIL_N * _crack
		_trail_fx.draw_line(prev, p, Color(0.75, 1.0, 1.0, 0.45 * a), 2.0 + 4.0 * a * art_scale, true)
		prev = p


# ---------- 이펙트 자리 ----------

## EnemyRigVisual.fx_point 에 낚싯줄 자리를 더한다: whip_tip(줄 끝) / hand(줄을 쥔 주먹)
func fx_point(kind: String) -> Vector2:
	match kind:
		"whip_tip":
			return _pts[0] if _rope_ok and _pts.size() > 0 else Vector2.INF
		"hand":
			return _hand_world() if _grip_bone >= 0 else Vector2.INF
	return super.fx_point(kind)


# ---------- 옛 그림과 같은 이름 (시험 probe_lake 가 읽는다) ----------

## 줄이 나오는 자리 (이 노드 기준) = 주먹
func line_origin() -> Vector2:
	return to_local(_hand_world())


## 휘두를 때 줄 끝이 닿을 자리 (이 노드 기준) — 판정 상자의 먼 끝, 높이 가운데
func _strike_target() -> Vector2:
	var f := float(_enemy.facing) if _enemy else 1.0
	return to_local(_strike_target_world(f))


## 줄 끝을 target 으로 보내는 (각도, 길이) — 각도는 _swing 과 같은 약속
func _aim(origin: Vector2, target: Vector2) -> Vector2:
	var d := target - origin
	var f := float(_enemy.facing) if _enemy else 1.0
	return Vector2(atan2(d.x * f, d.y), d.length())

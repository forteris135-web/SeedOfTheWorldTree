extends Node2D
## 셀레니아의 뼈대 애니메이션 (8단계). 부위 그림(art/characters/selenia/)을 관절로 이어 코드로 움직인다.
## 좌표 단위는 원본 부위 시트의 픽셀(PART_SCALE 로 줄인 그림을 쓰므로 안에서 곱한다). 오른쪽을 보는 기준.
## 동작: 대기·걷기·달리기·점프·낙하·구르기·약공격(3)·강공격(차지/휘두름)·가드·피격·회복·정화의 손길·쉬기·사망.

const PART_SCALE := 0.25        # 그림을 1/4로 줄여 두었다
const RIG_SCALE := 0.135        # 원본 px → 게임 px (키 약 132)
const SEED := Color("ffd46a")
const SEED_HDR := Color(2.2, 1.8, 0.9)
const SKIN := Color("efe6d8")
const GUARD_BLUE := Color("8fd3ff")

## 부위 정의: 이름 -> {file, pivot(그림 안의 관절 px), parent(관절이 붙는 뼈), at(부모 기준 관절 위치 px), z}
## 뿌리(hip)는 두 다리 사이 엉덩이. 오른쪽을 본다.
const PARTS := {
	"cloak_far":  {"file": "cloak_far.png",  "pivot": Vector2(120, 40),  "parent": "hip", "at": Vector2(-40, -195), "z": 0},
	"cloak_near": {"file": "cloak_near.png", "pivot": Vector2(560, 40),  "parent": "hip", "at": Vector2(-20, -185), "z": 1},
	"arm_back":   {"file": "arm_back.png",   "pivot": Vector2(120, 40),  "parent": "hip", "at": Vector2(-15, -170), "z": 2},
	"leg_back":   {"file": "leg_back.png",   "pivot": Vector2(95, 25),   "parent": "hip", "at": Vector2(-22, -5),   "z": 3},
	"torso":      {"file": "torso.png",      "pivot": Vector2(190, 265), "parent": "hip", "at": Vector2(0, 0),      "z": 4},
	"leg_front":  {"file": "leg_front.png",  "pivot": Vector2(84, 25),   "parent": "hip", "at": Vector2(28, -5),    "z": 5},
	"cape":       {"file": "cape.png",       "pivot": Vector2(40, 20),   "parent": "hip", "at": Vector2(-40, -200), "z": 6},
	"head":       {"file": "head.png",       "pivot": Vector2(380, 330), "parent": "hip", "at": Vector2(12, -218),  "z": 7},
	"arm_sword":  {"file": "arm_sword.png",  "pivot": Vector2(62, 62),   "parent": "hip", "at": Vector2(8, -165),   "z": 8},
}
const ORDER := ["cloak_far", "cloak_near", "arm_back", "leg_back", "torso", "leg_front", "cape", "head", "arm_sword"]

var _player: Player
var _bones := {}          # 이름 -> Node2D (관절)
var _sprites := {}        # 이름 -> Sprite2D
var _hip: Node2D
var _time := 0.0
var _squash := Vector2.ONE
var _tween: Tween
var _flash := 0.0
var _hurt := 0.0
var _purify_ring := -1.0
var _air_ring := -1.0
var _gust_t := -1.0
var _death_t := 0.0
var _roll_angle := 0.0
var _cloak_vel := 0.0     # 망토의 흔들림 (단순 물리)
var _cloak_ang := 0.0
var _prev_x := 0.0
var _seed_glow: Sprite2D
var _cur := {}            # 현재 관절 각도 (부드럽게 따라감)
var _lantern: Sprite2D
var _lantern_glow: Sprite2D


func _ready() -> void:
	_player = get_parent() as Player
	_hip = Node2D.new()
	_hip.name = "Hip"
	_hip.position = Vector2(0, 22)
	_hip.scale = Vector2(RIG_SCALE, RIG_SCALE)
	add_child(_hip)
	for name in ORDER:
		var p: Dictionary = PARTS[name]
		var bone := Node2D.new()
		bone.name = name
		bone.position = p["at"]
		_hip.add_child(bone)
		var spr := Sprite2D.new()
		spr.texture = load("res://art/characters/selenia/" + p["file"])
		spr.centered = false
		spr.scale = Vector2(1.0 / PART_SCALE, 1.0 / PART_SCALE)
		spr.position = -p["pivot"]
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		bone.add_child(spr)
		_bones[name] = bone
		_sprites[name] = spr
		_cur[name] = 0.0
	# 가슴의 씨앗 빛 (발광)
	_seed_glow = Sprite2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(SEED, 0.9), Color(SEED, 0.25), Color(SEED, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 64
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	_seed_glow.texture = gt
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_seed_glow.material = add
	_bones["torso"].add_child(_seed_glow)
	_seed_glow.position = Vector2(85, -120)   # 몸통 그림 속 씨앗 자리 (원본 px, 관절 기준)
	_seed_glow.scale = Vector2(2.6, 2.6)

	# 티아의 작은 등불 (받으면 허리에 매달린다)
	_lantern = Sprite2D.new()
	_lantern.texture = preload("res://art/objects/tia_lantern.png")
	_lantern.scale = Vector2(0.9, 0.9)   # 원본 px 기준(뼈대 배율로 줄어든다): 약 70px 높이
	_lantern.position = Vector2(-70, 20)
	_lantern.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_lantern.visible = Progress.has("has_tia_lantern")
	_hip.add_child(_lantern)
	_hip.move_child(_lantern, _bones["torso"].get_index() + 1)
	_lantern_glow = Sprite2D.new()
	_lantern_glow.texture = _seed_glow.texture
	_lantern_glow.material = _seed_glow.material
	_lantern_glow.modulate = Color(2.0, 1.3, 0.6, 0.8)
	_lantern_glow.scale = Vector2(3.0, 3.0)
	_lantern_glow.position = Vector2(0, 40)
	_lantern.add_child(_lantern_glow)
	Progress.flag_changed.connect(func(f, v): if f == "has_tia_lantern": _lantern.visible = v)
	_player.jumped.connect(_on_jumped)
	_player.landed.connect(_on_landed)
	_player.roll_started.connect(func(): _play_squash(Vector2(1.1, 0.9)))
	_player.just_guarded.connect(func(_s): _flash = 1.0)
	_player.hit_taken.connect(func(_d): _hurt = 1.0; _play_squash(Vector2(1.12, 0.88)))
	_player.purified.connect(func(_t): _purify_ring = 0.0; _flash = 1.0)
	_player.gust_cast.connect(func(): _gust_t = 0.0)
	_player.state_changed.connect(func(st): if st == Player.State.HEAVY_SWING: _play_squash(Vector2(1.12, 0.92)))


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(_flash - delta * 6.0, 0.0)
	_hurt = maxf(_hurt - delta * 3.0, 0.0)
	for k in ["_purify_ring", "_air_ring", "_gust_t"]:
		var v: float = get(k)
		if v >= 0.0:
			v += delta * (1.6 if k == "_purify_ring" else 3.0)
			set(k, v if v <= 1.0 else -1.0)
	var st := _player.state
	if st == Player.State.ROLL:
		_roll_angle += delta / _player.roll_duration * TAU
	else:
		_roll_angle = 0.0
	_death_t = minf(_death_t + delta, 1.0) if st == Player.State.DEAD else 0.0

	# 전체: 방향, 찌그러짐, 구르기 회전, 쓰러짐
	var f := float(_player.facing)
	var rot := _roll_angle * f
	var shift := Vector2.ZERO
	if st == Player.State.DEAD:
		rot = -PI / 2.0 * f * ease(_death_t, 0.4)
		shift = Vector2(0, 30.0 * _death_t)
	elif st == Player.State.REST:
		shift = Vector2(0, 8)
	position = shift
	rotation = rot
	scale = Vector2(_squash.x * f, _squash.y)

	# 무적 깜빡임
	if _player.is_invulnerable() and st != Player.State.DEAD:
		modulate.a = 0.45 if fmod(_time, 0.12) < 0.06 else 1.0
	else:
		modulate.a = 1.0 - _death_t * 0.6
	# 피격 붉은 기운 / 저스트 가드 번쩍임
	var tint := Color.WHITE.lerp(Color(1.6, 0.6, 0.5), _hurt * 0.7).lerp(Color(2.5, 2.5, 2.5), _flash * 0.8)
	for name in ORDER:
		_sprites[name].modulate = tint

	_apply_pose(delta, st)
	queue_redraw()


## 상태별 목표 자세 (각도는 라디안, 음수 = 앞으로). 부드럽게 따라간다.
func _apply_pose(delta: float, st: Player.State) -> void:
	var t := _time
	var pose := {"torso": 0.0, "head": 0.0, "arm_back": 0.0, "arm_sword": 0.25, "leg_back": 0.0, "leg_front": 0.0, "cape": 0.0}
	var hip_y := 0.0
	var k := 14.0   # 따라가는 빠르기
	var speed_ratio := absf(_player.velocity.x) / _player.run_speed
	match st:
		Player.State.IDLE:
			pose["torso"] = sin(t * 1.6) * 0.012
			pose["head"] = sin(t * 1.6 + 0.5) * 0.02
			pose["arm_back"] = sin(t * 1.6) * 0.04 + 0.1
			pose["arm_sword"] = 0.3 + sin(t * 1.6) * 0.03
			hip_y = sin(t * 1.6) * 2.0
		Player.State.WALK, Player.State.RUN:
			var run := st == Player.State.RUN
			var w := (13.0 if run else 9.5)
			var amp := (0.75 if run else 0.45)
			var s := sin(t * w)
			pose["leg_front"] = -s * amp
			pose["leg_back"] = s * amp
			pose["arm_back"] = -s * amp * 0.7
			pose["arm_sword"] = 0.25 + s * amp * 0.5
			pose["torso"] = (0.18 if run else 0.07) + absf(cos(t * w)) * 0.02
			pose["head"] = (-0.06 if run else -0.02)
			hip_y = -absf(cos(t * w)) * (10.0 if run else 5.0)
		Player.State.JUMP:
			pose["leg_front"] = -0.7
			pose["leg_back"] = 0.5
			pose["arm_back"] = 0.6
			pose["arm_sword"] = -0.2
			pose["torso"] = 0.08
			pose["head"] = -0.05
		Player.State.FALL:
			pose["leg_front"] = -0.3
			pose["leg_back"] = 0.25
			pose["arm_back"] = 0.9 + sin(t * 8.0) * 0.1
			pose["arm_sword"] = -0.5
			pose["torso"] = -0.05
			pose["head"] = 0.08
		Player.State.ROLL:
			pose["leg_front"] = -1.5
			pose["leg_back"] = 1.3
			pose["arm_back"] = 1.2
			pose["arm_sword"] = -1.0
			pose["torso"] = 0.5
			pose["head"] = 0.5
			k = 30.0
		Player.State.ATTACK:
			k = 40.0
			var step := _player.attack_step
			var ph := _player.attack_phase
			var a := _swing(ph, step)
			pose["arm_sword"] = a
			pose["torso"] = 0.22 if ph != "startup" else -0.1
			pose["head"] = -0.1
			pose["arm_back"] = -a * 0.3
			pose["leg_front"] = -0.35
			pose["leg_back"] = 0.3
		Player.State.HEAVY_CHARGE:
			k = 18.0
			var c := _player.charge / _player.heavy_max_charge
			pose["arm_sword"] = 2.5 + sin(t * 40.0) * 0.06 * c
			pose["torso"] = -0.18
			pose["head"] = -0.05
			pose["arm_back"] = 0.5
			pose["leg_back"] = 0.35
			pose["leg_front"] = -0.25
		Player.State.HEAVY_SWING:
			k = 45.0
			match _player.attack_phase:
				"startup": pose["arm_sword"] = 2.5; pose["torso"] = -0.15
				"active": pose["arm_sword"] = -1.1; pose["torso"] = 0.35
				_: pose["arm_sword"] = -0.7; pose["torso"] = 0.25
			pose["leg_front"] = -0.45
			pose["leg_back"] = 0.4
			pose["head"] = -0.12
		Player.State.GUARD:
			pose["arm_sword"] = -1.45
			pose["arm_back"] = -0.8
			pose["torso"] = -0.1
			pose["head"] = 0.05
			pose["leg_front"] = -0.25
			pose["leg_back"] = 0.2
		Player.State.HIT:
			k = 25.0
			pose["torso"] = -0.3
			pose["head"] = -0.25
			pose["arm_back"] = 1.0
			pose["arm_sword"] = 1.2
			pose["leg_front"] = -0.2
			pose["leg_back"] = 0.4
		Player.State.HEAL:
			pose["arm_sword"] = -0.9
			pose["arm_back"] = -0.9
			pose["torso"] = 0.1
			pose["head"] = 0.18
		Player.State.PURIFY:
			pose["arm_back"] = -1.6
			pose["arm_sword"] = 0.6
			pose["torso"] = 0.12
			pose["head"] = 0.1
		Player.State.REST:
			pose["leg_front"] = -1.7
			pose["leg_back"] = 1.4
			pose["torso"] = 0.3
			pose["head"] = 0.3
			pose["arm_back"] = -1.1
			pose["arm_sword"] = -0.9
			hip_y = 95.0
		Player.State.DEAD:
			pose["arm_back"] = 1.2
			pose["arm_sword"] = 1.0
			pose["leg_front"] = -0.3
			pose["leg_back"] = 0.2
			pose["head"] = 0.3
	# 망토: 움직임에 뒤처지며 흔들린다
	var vx := _player.velocity.x * _player.facing
	var target_cloak := clampf(-vx / 900.0, -0.5, 0.35) + (0.25 if not _player.is_on_floor() else 0.0) * (1 if _player.velocity.y > 0 else -1)
	var accel := (target_cloak - _cloak_ang) * 60.0 - _cloak_vel * 7.0
	_cloak_vel += accel * delta
	_cloak_ang += _cloak_vel * delta
	var cloak_sway := sin(t * 2.3) * 0.02
	var cloak_ang := _cloak_ang + cloak_sway
	for name in pose:
		_cur[name] = lerpf(_cur[name], pose[name], 1.0 - exp(-k * delta))
		_bones[name].rotation = _cur[name]
	# 망토 두 자락은 뒤쪽(양수 = 뒤로 날림)
	_bones["cloak_near"].rotation = cloak_ang * 0.9 + _cur["torso"] * 0.5
	_bones["cloak_far"].rotation = cloak_ang * 0.7 + _cur["torso"] * 0.5 + 0.12
	_bones["cape"].rotation = cloak_ang * 0.5 + _cur["torso"]
	_hip.position.y = 22.0 + hip_y * RIG_SCALE
	# 씨앗 빛 맥동
	var pulse := 0.8 + 0.2 * sin(t * 3.0)
	if st in [Player.State.HEAL, Player.State.PURIFY, Player.State.REST]:
		pulse += 0.35 + 0.2 * sin(t * 9.0)
	_seed_glow.modulate = Color(1.3, 1.15, 0.8, 0.9) * pulse
	if _lantern and _lantern.visible:
		_lantern.rotation = cloak_ang * 0.6 + sin(t * 2.0) * 0.05
		_lantern_glow.modulate = Color(2.0, 1.3, 0.6, 0.7 + 0.2 * sin(t * 7.0))
	_seed_glow.scale = Vector2(2.6, 2.6) * (0.85 + pulse * 0.3)


func _swing(phase: String, step: int) -> float:
	var t := 0.0
	match phase:
		"startup": t = 0.0
		"active": t = 0.75
		"recovery": t = 1.0
	if step == 3:
		return lerpf(-1.8, 1.4, t)     # 아래에서 위로 크게
	return lerpf(2.2, -1.2, t)        # 위에서 아래로


func _draw() -> void:
	# 뼈대와 별개의 빛 효과들 (게임 px 단위, 바라보는 방향 기준)
	if _air_ring >= 0.0:
		draw_set_transform(Vector2(0, 50), 0.0, Vector2(1.0, 0.35))
		draw_arc(Vector2.ZERO, 20.0 + _air_ring * 70.0, 0, TAU, 32, Color(0.8, 1.0, 0.85, 1.0 - _air_ring), 3.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _gust_t >= 0.0:
		draw_arc(Vector2(44, -18), 14.0 + _gust_t * 20.0, -0.9, 0.9, 10, Color(0.8, 1.0, 0.85, 1.0 - _gust_t), 2.5, true)
	if _player.state == Player.State.GUARD:
		draw_arc(Vector2(38, -14), 48.0, -1.1, 1.1, 14, Color(GUARD_BLUE, 0.5 + _flash * 0.5), 3.0, true)
		if _flash > 0.0:
			draw_circle(Vector2(44, -12), 26.0 * _flash + 8.0, Color(1, 1, 1, _flash * 0.8))
	if (_player.state == Player.State.ATTACK or _player.state == Player.State.HEAVY_SWING) and _player.attack_phase == "active":
		var r := 92.0
		var a0 := -1.9 if _player.attack_step != 3 else 0.4
		var a1 := 0.4 if _player.attack_step != 3 else -1.9
		draw_arc(Vector2(8, -16), r, minf(a0, a1), maxf(a0, a1), 18, Color(SEED, 0.6), 4.0, true)
	if _purify_ring >= 0.0:
		var rr := 20.0 + _purify_ring * 160.0
		draw_arc(Vector2(50, -20), rr, 0, TAU, 40, Color(SEED, 1.0 - _purify_ring), 5.0 * (1.0 - _purify_ring) + 1.0, true)


func _on_jumped(air: bool) -> void:
	_play_squash(Vector2(0.86, 1.14))
	if air:
		_air_ring = 0.0


func _on_landed(fall_speed: float) -> void:
	var amount := clampf(fall_speed / 1600.0, 0.1, 0.3)
	_play_squash(Vector2(1.0 + amount, 1.0 - amount))


func _play_squash(to: Vector2) -> void:
	if _tween:
		_tween.kill()
	_squash = to
	_tween = create_tween()
	_tween.tween_method(func(v: Vector2) -> void: _squash = v, to, Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

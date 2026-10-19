extends Sprite2D
class_name FxSprite
## 이펙트 하나 (Fx 자동 로드가 미리 만들어 두고 돌려 쓴다 — 직접 만들지 말 것).
## Fx.spawn() 이 이 노드를 돌려준다. 이펙트가 끝나면 풀로 돌아가 다른 이펙트로 다시 쓰이므로,
## 들고 있다가 나중에 만지려면 함께 받은 gen 이 그대로인지 Fx.alive(fx, gen) 으로 확인한다.
## 매 프레임 할 일은 Fx 가 tick() 으로 몰아서 부른다 (노드마다 _process 를 돌리지 않는다). 프레임마다 새로 만드는 것 없음.

## 몇 번째로 쓰이는 중인가 (재사용될 때마다 1씩 늘어난다)
var gen := 0
var fx_name := ""
var active := false
## 0 낮음(먼지·빛 알갱이) / 1 보통 / 2 중요(놓치면 안 되는 것). 가득 찼을 때 낮은 것부터 비켜 준다.
var priority := 1
var born_ms := 0

var t := 0.0
var life := 0.3
var _s0 := 1.0
var _s1 := 1.0
var _ease := 2.0
var _base := Vector2.ONE        # 기본 가로·세로 배율 (보는 방향의 뒤집기 포함)
var _fade_in := 0.0             # 수명 비율
var _fade_out := 0.6            # 이 비율부터 사라지기 시작
var _spin := 0.0                # 라디안/초
var _vel := Vector2.ZERO
var _gravity := 0.0
var _drag := 0.0
var _color := Color.WHITE
var _follow: Node2D
var _offset := Vector2.ZERO
var _frames: Array = []
var _frame_i := -1
## 호 닦아 드러내기
var _wipe := false
var _wipe_time := 0.5           # 머리가 끝까지 가는 데 드는 수명 비율
var _wipe_tail_end := 4.0       # 머리가 끝난 뒤 꼬리가 줄어드는 목표 (4 = 꼬리 없음)
var _wipe_from := -0.15
var _wipe_to := 1.3
## 바깥(소녀 뼈대)이 머리 위치를 정해 준다. 놓아주면(release) 그 자리에서 수명이 이어진다.
var driven := false
var _hold := 0.5                # 끌려가는 동안 멈춰 있는 수명 비율
var _head := 0.0
var _flicker := 0.0
var _seed := 0.0

var _shader_mat: ShaderMaterial


## Fx 가 부른다: def(표의 한 줄)와 opts 로 상태를 채운다. 텍스처·재질은 Fx 가 이미 정해 두었다.
func setup(def: Dictionary, opts: Dictionary, facing: float) -> void:
	t = 0.0
	life = maxf(float(opts.get("life", def.get("life", 0.3))), 0.01)
	var sc: Array = def.get("scale", [1.0, 1.0])
	var k := float(opts.get("scale", 1.0))
	_s0 = float(sc[0]) * k
	_s1 = float(sc[1]) * k
	_ease = float(def.get("ease", 2.0))
	var sxy: Vector2 = def.get("scale_xy", Vector2.ONE)
	if opts.has("scale_xy"):
		sxy *= opts["scale_xy"] as Vector2
	var flip_v := bool(def.get("flip_v", false)) != bool(opts.get("flip_v", false))
	_base = Vector2(sxy.x * facing, sxy.y * (-1.0 if flip_v else 1.0))
	_fade_in = float(def.get("fade_in", 0.0))
	_fade_out = float(def.get("fade_out", 0.6))
	var rot := deg_to_rad(float(def.get("rot", 0.0)) + float(opts.get("rot", 0.0)))
	var rr := float(def.get("rot_rand", 0.0))
	if rr > 0.0:
		rot += deg_to_rad(randf_range(-rr, rr))
	rotation = rot * facing
	_spin = deg_to_rad(float(def.get("spin", 0.0))) * facing
	var v: Vector2 = opts.get("vel", def.get("vel", Vector2.ZERO))
	var vr: Vector2 = def.get("vel_rand", Vector2.ZERO)
	if vr != Vector2.ZERO:
		v += Vector2(randf_range(-vr.x, vr.x), randf_range(-vr.y, vr.y))
	_vel = Vector2(v.x * facing, v.y)
	_gravity = float(def.get("gravity", 0.0))
	_drag = float(def.get("drag", 0.0))
	var col: Color = opts.get("color", def.get("color", Color.WHITE))
	var energy := float(opts.get("energy", def.get("energy", 1.0)))
	_color = Color(col.r * energy, col.g * energy, col.b * energy, col.a)
	_flicker = float(def.get("flicker", 0.0))
	_seed = randf() * TAU
	_follow = opts.get("follow", null)
	var off: Vector2 = opts.get("offset", Vector2.ZERO)
	_offset = Vector2(off.x * facing, off.y)
	z_index = int(opts.get("z", def.get("z", 6)))
	priority = int(def.get("priority", 1))
	driven = bool(opts.get("driven", false))
	_hold = float(def.get("hold", 0.5))
	_head = 0.0
	var w: Dictionary = def.get("wipe", {})
	_wipe = not w.is_empty()
	if _wipe:
		_wipe_time = float(w.get("time", 0.5))
		_wipe_tail_end = float(w.get("tail_end", 4.0))
		_wipe_from = -float(w.get("soft", 0.12))
		_wipe_to = 1.0 + float(w.get("soft", 0.12)) * 2.0 + 0.15
		_head = _wipe_from
	scale = _base * _s0
	modulate = Color(_color, 0.0 if _fade_in > 0.0 else _color.a)
	if _follow and is_instance_valid(_follow):
		global_position = _follow.global_position + _offset
	visible = true
	active = true


## 프레임 묶음 (그림 여러 장을 수명 동안 고르게 넘긴다). Fx 가 setup 뒤에 준다.
func set_frames(textures: Array) -> void:
	_frames = textures
	_frame_i = -1
	if not _frames.is_empty():
		texture = _frames[0]
		_frame_i = 0


func shader_material() -> ShaderMaterial:
	if _shader_mat == null:
		_shader_mat = ShaderMaterial.new()
	return _shader_mat


## 끌려가는 동안: 머리 위치 (0 = 시작, 1 = 끝까지 그려짐)
func set_reveal(v: float) -> void:
	_head = lerpf(_wipe_from, 1.0 + 0.05, clampf(v, 0.0, 1.0))


## 끌어 주던 쪽이 놓았다: 지금 자리에서 수명이 이어진다 (머리는 끝까지 마저 간다).
func release() -> void:
	if not driven:
		return
	driven = false
	t = maxf(t, _hold * life)


## 한 프레임. 끝났으면 false.
func tick(delta: float) -> bool:
	if driven:
		t = minf(t + delta, _hold * life)   # 끌려가는 동안은 hold 자리까지만 (나타나기는 하고 사라지지는 않는다)
	else:
		t += delta
	var u := t / life
	if u >= 1.0:
		return false
	if _follow:
		if is_instance_valid(_follow):
			global_position = _follow.global_position + _offset
		else:
			_follow = null
	else:
		if _gravity != 0.0:
			_vel.y += _gravity * delta
		if _drag > 0.0:
			_vel *= exp(-_drag * delta)
		position += _vel * delta
	if _spin != 0.0:
		rotation += _spin * delta
	var e := 1.0 - pow(1.0 - u, _ease)
	scale = _base * lerpf(_s0, _s1, e)
	var a := 1.0
	if _fade_in > 0.0 and u < _fade_in:
		a = u / _fade_in
	if u > _fade_out:
		var f := (u - _fade_out) / maxf(1.0 - _fade_out, 0.001)
		a *= 1.0 - f * f * (3.0 - 2.0 * f)
	if _flicker > 0.0:
		a *= 1.0 - _flicker * (0.5 + 0.5 * sin(t * 47.0 + _seed)) * (0.5 + 0.5 * sin(t * 23.0 + _seed * 2.0))
	modulate = Color(_color, _color.a * a)
	if not _frames.is_empty():
		var fi := mini(int(u * _frames.size()), _frames.size() - 1)
		if fi != _frame_i:
			_frame_i = fi
			texture = _frames[fi]
	if _wipe and _shader_mat:
		if not driven:
			var wt := clampf(u / maxf(_wipe_time, 0.001), 0.0, 1.0)
			var target := lerpf(_wipe_from, _wipe_to, 1.0 - (1.0 - wt) * (1.0 - wt))
			_head = maxf(_head, target)
		_shader_mat.set_shader_parameter(&"wipe_head", _head)
		if _wipe_tail_end < 4.0 and u > _hold:
			var tu := (u - _hold) / maxf(1.0 - _hold, 0.001)
			_shader_mat.set_shader_parameter(&"wipe_tail", lerpf(1.6, _wipe_tail_end, tu))
	return true


## 풀로 돌아간다.
func finish() -> void:
	active = false
	visible = false
	driven = false
	_follow = null
	_frames = []

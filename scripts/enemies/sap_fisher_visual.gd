extends "res://scripts/enemies/enemy_sprite_visual.gd"
## 수액 어부의 그림: 공통 적 그림(EnemySpriteVisual) 위에 **낚싯줄**을 코드로 그린다.
## 줄은 그림 속 **낚싯대 끝**(rod_tip_uv)에서 시작한다. 그림에는 대만 있고 줄은 코드가 그린다 (그림에도 줄이 있으면 두 가닥으로 보인다).
## - 대기·걷기: 대 끝에서 줄이 아래로 늘어져 흔들린다 (끝에 수액 방울)
## - 예고(하나·둘): 줄을 뒤 위로 두 번 흔든다 — 흔들 때마다 끝의 방울이 반짝 (박자를 눈으로 읽게).
##   예고 끝자락에는 머리 위로 크게 치켜든다 (예비 동작)
## - 휘두름(셋): 줄이 **머리 위를 넘어 앞으로** 내리꽂힌다. 판정이 켜지는 첫 프레임에 이미 앞(소녀 쪽)을 가리키고,
##   끝은 판정 상자의 먼 끝(사거리 300)에 닿는다. 머리 위로 지나간 자리에 호 잔상 (늘 대 끝보다 위 → 바닥을 뚫지 않는다).
## - 되돌림: 줄이 처져 늘어졌다가 제자리로.
## 각도: 0 = 수직 아래, + = 바라보는 쪽(앞), -π/2 = 뒤 수평, ±π = 위.
## 스킨 자리: 진짜 그림이 오면 rod_tip_uv 를 그림 속 대 끝 자리(가로·세로 비율 0~1, 그림이 오른쪽을 볼 때 기준)로 맞춘다.
##   대가 없는 그림이면 use_rod_tip = false → 손 자리(HAND)에서 줄이 나온다.

## 그림 속 낚싯대 끝 (그림 크기에 대한 비율, 오른쪽을 보는 그림 기준). 임시 그림은 (0.88, 0.14).
@export var rod_tip_uv := Vector2(0.88, 0.14)
## false 면 대 끝 대신 손 자리(HAND)에서 줄이 나온다
@export var use_rod_tip := true

## 손끝 자리 (몸 가운데 기준, 바라보는 방향 +x) — use_rod_tip 이 false 일 때만
const HAND := Vector2(42.0, -95.0)
const LINE_COLOR := Color(0.6, 0.9, 0.95, 0.9)
const BEAD_COLOR := Color(0.55, 0.95, 1.0)
const SEGMENTS := 14
const IDLE_LEN := 120.0
## 예고 때 줄의 기본 각도(뒤 위)와 흔들림 크기, 끝자락에 치켜드는 각도
const BACK_REST := -1.9
const BACK_SHAKE := 0.4
const OVERHEAD := -2.6
## 예고 진행도가 이보다 크면 머리 위로 치켜든다
const OVERHEAD_FROM := 0.85

var _swing := 0.0        # 줄의 각도
var _swing_v := 0.0
var _crack := 0.0        # 휘두름 순간의 번쩍 (1→0)
var _prev_beat := -1
var _beat_flash := 0.0
var _prev_state := -1


## 줄이 나오는 자리 (이 노드 기준). 그림의 찌그러짐·기울기·좌우 뒤집기를 그대로 따른다.
func line_origin() -> Vector2:
	if use_rod_tip and _sprite and _sprite.texture:
		var sz := _sprite.texture.get_size()
		var uv := rod_tip_uv
		if not art_faces_right:
			uv.x = 1.0 - uv.x
		return _sprite.transform * (uv * sz - sz / 2.0)
	var f := float(_enemy.facing) if _enemy else 1.0
	return Vector2(HAND.x * f, HAND.y + (_enemy.hurt_height * 0.5 if _enemy else 0.0) + _dy.v * 0.5)


## 휘두를 때 줄 끝이 닿을 자리 (판정 상자의 먼 끝, 높이 가운데)
func _strike_target() -> Vector2:
	var f := float(_enemy.facing)
	var box: Rect2 = _enemy.strike_box
	return Vector2((box.position.x + box.size.x) * f, box.position.y + box.size.y * 0.5)


## 줄 끝을 target 으로 보내는 (각도, 길이)
func _aim(origin: Vector2, target: Vector2) -> Vector2:
	var d := target - origin
	var f := float(_enemy.facing)
	return Vector2(atan2(d.x * f, d.y), d.length())


func _process(delta: float) -> void:
	super(delta)
	if _enemy == null:
		return
	var st := _enemy.state
	var target := 0.0
	var stiff := 40.0
	var damp := 7.0
	if st == EnemyBase.State.WINDUP:
		# 하나·둘: 뒤 위로 두 번 흔든다 (진행도 0→1 에 두 주기) → 끝자락에 머리 위로 치켜든다
		var p: float = _enemy.windup_progress
		target = BACK_REST - BACK_SHAKE * sin(p * TAU * 2.0)
		if p > OVERHEAD_FROM:
			target = OVERHEAD
		stiff = 90.0
		damp = 10.0
		var beat: int = _enemy.windup_beat() if _enemy.has_method("windup_beat") else 0
		if beat != _prev_beat:
			_beat_flash = 1.0
		_prev_beat = beat
	elif st == EnemyBase.State.STRIKE:
		target = _aim(line_origin(), _strike_target()).x
		stiff = 600.0
		damp = 26.0
		if _prev_state != st:
			# 판정은 첫 프레임부터 켜진다 → 줄도 이미 머리 위를 넘어 앞에 와 있게 (앞 위에서 내리꽂힌다)
			_crack = 1.0
			_swing = target + 0.35
			_swing_v = -6.0
	elif st == EnemyBase.State.RECOVER:
		target = 0.9
		stiff = 40.0
		damp = 5.0
		_prev_beat = -1
	else:
		target = sin(_t * 1.3) * 0.12
		_prev_beat = -1
	if st != EnemyBase.State.WINDUP:
		_prev_beat = -1
	_prev_state = st
	var s := Motion.spring(_swing, target, _swing_v, stiff, damp, delta)
	_swing = s[0]
	_swing_v = s[1]
	_crack = maxf(_crack - delta * 5.0, 0.0)
	_beat_flash = maxf(_beat_flash - delta * 4.0, 0.0)


func _draw() -> void:
	super()
	if _enemy == null or _enemy.state == EnemyBase.State.DEAD:
		return
	var f := float(_enemy.facing)
	var st := _enemy.state
	var origin := line_origin()
	# 줄: 대 끝에서 _swing 각도로 뻗되, 중력으로 처진다. 휘두를 때는 판정 끝까지 곧다.
	var striking := st == EnemyBase.State.STRIKE
	var length := IDLE_LEN
	var sag := 60.0
	if st == EnemyBase.State.WINDUP:
		length = 150.0
		sag = 30.0
	elif striking:
		length = _aim(origin, _strike_target()).y * (1.0 + 0.06 * _crack)
		sag = 6.0
	elif st == EnemyBase.State.RECOVER:
		length = 200.0
		sag = 90.0
	var dir := Vector2(sin(_swing) * f, cos(_swing))
	var pts := PackedVector2Array()
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var p := origin + dir * length * t
		p.y += sag * sin(t * PI) * (1.0 - absf(sin(_swing)) * 0.5)
		# 잔잔한 흔들림
		p.x += sin(_t * 6.0 + t * 7.0) * 3.0 * t
		pts.append(p)
	var col := LINE_COLOR
	if striking:
		col = Color(1.0, 1.0, 1.0, 1.0)
	draw_polyline(pts, Color(col, 0.35), 5.0, true)
	draw_polyline(pts, col, 2.0, true)
	# 끝의 수액 방울 (박마다 반짝, 휘두를 때 터짐)
	var tip: Vector2 = pts[pts.size() - 1]
	var bead_r := 6.0 + 4.0 * _beat_flash
	draw_circle(tip, bead_r * 1.8, Color(BEAD_COLOR, 0.15 + 0.3 * _beat_flash))
	draw_circle(tip, bead_r, Color(BEAD_COLOR, 0.95))
	if _crack > 0.0:
		# 끝이 '딱' 터지는 번쩍 + 머리 위를 넘어온 호 잔상 (뒤 위 → 위 → 앞; 대 끝보다 위로만 지나가 바닥을 뚫지 않는다)
		draw_circle(tip, 26.0 * _crack, Color(1.0, 1.0, 1.0, 0.5 * _crack))
		var a_end := _swing - TAU          # 같은 방향을 '위로 넘어온' 쪽으로 펼친 값
		for k in 3:
			var r := length * (0.72 + k * 0.1)
			var a0 := lerpf(OVERHEAD + 0.3, a_end, 0.25 * k)
			draw_arc(origin, r, PI / 2.0 - a0 * f, PI / 2.0 - a_end * f, 14, Color(0.8, 1.0, 1.0, 0.35 * _crack), 2.0, true)

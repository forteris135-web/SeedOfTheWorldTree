extends Area2D
class_name RootHand
## 뿌리 손 (뿌리지기 패턴): 땅에서 거대한 뿌리 손이 솟아 소녀를 움켜쥔다. 가드 불가 — 구르기(무적)로 피한다.
## 흐름: delay 대기 → 솟음(RISE) → 움켜쥠(CLOSE 끝에 한 번 판정) → 쥔 채(HOLD; 잡혔으면 소녀가 묶인다) → 가라앉음(SINK)
## 잡히면: 피해 + hold_time 동안 손 안에 묶였다가(피격 상태 유지) 밖으로 던져진다(피격 상태로 날아가 가로 속도가 산다).
## 예고(붉은 타원)는 보스 그림(root_keeper_visual)이 예비 동안 그리고, delay 로 늦게 솟는 손(2페이즈 두 번째)은 기다리는 동안 스스로 그린다.

var damage := 22.0
var hold_time := 0.7
var delay := 0.0
var source: Node2D
## 던질 방향 (보스에게서 멀어지는 쪽). 0 이면 손 위치로 정한다.
var throw_dir := 0
var _t := 0.0
var _rise := 0.0      # 0~1 손이 올라온 정도
var _close := 0.0     # 0~1 손가락 오므림
var _held: Node = null
var _grabbed := false
var _closed := false
var _dirt: CPUParticles2D
var _rose := false
const RISE := 0.2
const CLOSE := 0.14
const SINK := 0.45
const GRAB_RADIUS := 115.0
const GRAB_CENTER_Y := -130.0
const HAND_H := 250.0
const FINGERS := [-0.95, -0.5, 0.0, 0.5, 0.95]   # 손가락 벌린 각도 (rad, 위 기준)
## 던지는 속도와 그동안의 피격 경직 (피격 상태에서는 가로 속도가 천천히 줄어 실제로 날아간다)
const THROW_VEL := Vector2(560.0, -600.0)
const THROW_STUN := 0.4
const RED_C := Color(1.0, 0.1, 0.08)


func _ready() -> void:
	add_to_group("projectile")
	add_to_group("root_effect")
	collision_layer = 0
	collision_mask = 8
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = GRAB_RADIUS
	shape.shape = c
	shape.position = Vector2(0, GRAB_CENTER_Y)
	add_child(shape)
	_dirt = CPUParticles2D.new()
	_dirt.emitting = false
	_dirt.one_shot = true
	_dirt.explosiveness = 1.0
	_dirt.amount = 26
	_dirt.lifetime = 0.8
	_dirt.direction = Vector2(0, -1)
	_dirt.spread = 70.0
	_dirt.gravity = Vector2(0, 1100)
	_dirt.initial_velocity_min = 260.0
	_dirt.initial_velocity_max = 640.0
	_dirt.scale_amount_min = 3.0
	_dirt.scale_amount_max = 9.0
	_dirt.color = Color(0.34, 0.26, 0.28, 0.9)
	_dirt.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_dirt.emission_rect_extents = Vector2(90, 4)
	add_child(_dirt)


## 흐름 단계 이름 (시험용): wait / rise / close / hold / sink / done
func stage() -> String:
	if _t < delay:
		return "wait"
	var u := _t - delay
	if u < RISE:
		return "rise"
	if u < RISE + CLOSE:
		return "close"
	if u < RISE + CLOSE + _hold_len():
		return "hold"
	if u < RISE + CLOSE + _hold_len() + SINK:
		return "sink"
	return "done"


func grabbed() -> bool:
	return _grabbed


func _hold_len() -> float:
	return hold_time if _grabbed else 0.25


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < delay:
		queue_redraw()   # 기다리는 동안 바닥 예고
		return
	var u := _t - delay
	if u < RISE:
		_rise = Motion.ease_out(u / RISE, 2.2)
		if not _rose:
			_rose = true
			_dirt.restart()
			_dirt.emitting = true
			Juice.shake(7.0)
			Sfx.play("root_rise", -2.0, 0.1)
	elif u < RISE + CLOSE:
		_rise = 1.0
		_close = Motion.ease_in(( u - RISE) / CLOSE, 1.6)
	elif u < RISE + CLOSE + _hold_len():
		_rise = 1.0
		_close = 1.0
		if not _closed:
			_closed = true
			_grab()
		_hold_player()
	elif u < RISE + CLOSE + _hold_len() + SINK:
		if _held != null:
			_release()
		_close = 1.0
		_rise = 1.0 - Motion.ease_in((u - RISE - CLOSE - _hold_len()) / SINK, 1.5)
	else:
		if _held != null:
			_release()
		queue_free()
		return
	queue_redraw()


## 손가락이 닫히는 순간 한 번: 손 안에 있는 소녀를 움켜쥔다 (가드 불가).
func _grab() -> void:
	for area in get_overlapping_areas():
		if area is Hurtbox:
			var hit := HitData.make(damage, 0.0, source if source else self, Vector2.ZERO)
			hit.guardable = false
			hit.hitstop = 0.08
			var res: String = area.receive(hit)
			if res == "hit" and area.owner_node is Player:
				_held = area.owner_node
				_grabbed = true
				Juice.shake(9.0)
				Juice.rumble(0.6, 1.0, 0.3)
				Sfx.play("root_grab", 0.0, 0.08)
				return
	Sfx.play("root_grab", -8.0, 0.1)


func _hold_player() -> void:
	if _held == null or not is_instance_valid(_held):
		_held = null
		return
	if _held.state == Player.State.DEAD:
		_held = null
		return
	_held.global_position = global_position + Vector2(0, GRAB_CENTER_Y + 20)
	_held.velocity = Vector2.ZERO
	_held.slow_factor = 0.0
	# 묶인 동안은 피격 상태를 유지한다 (경직 0.3초가 먼저 끝나 손 안에서 낙하 자세로 조작이 풀리던 것을 고침)
	_held._hit_timer = maxf(_held._hit_timer, 0.1)
	if _held.state != Player.State.HIT:
		_held._set_state(Player.State.HIT)


func _release() -> void:
	if _held and is_instance_valid(_held) and _held.state != Player.State.DEAD:
		var d := throw_dir
		if d == 0:
			d = 1 if (source == null or global_position.x >= source.global_position.x) else -1
		_held.velocity = Vector2(d * THROW_VEL.x, THROW_VEL.y)
		_held.global_position = global_position + Vector2(0, GRAB_CENTER_Y - 20)
		_held._hit_timer = THROW_STUN
		if _held.state != Player.State.HIT:
			_held._set_state(Player.State.HIT)
	_held = null


func _draw() -> void:
	if _t < delay:
		_draw_telegraph()
		return
	if _rise <= 0.01:
		return
	# 땅(y=0)에서 자라 나오게 세로 배율로 솟는다
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, _rise))
	var bark := Color(0.38, 0.27, 0.31)
	var dark := Color(0.22, 0.14, 0.18)
	var grain := Color(0.6, 0.46, 0.5)
	var crack := Color(0.85, 0.55, 1.0)
	# 손목 (굵은 뿌리, 결이 보이게)
	draw_colored_polygon(PackedVector2Array([Vector2(-50, 0), Vector2(-40, -120), Vector2(40, -120), Vector2(50, 0)]), bark)
	for k in 4:
		draw_line(Vector2(-34 + k * 22, -4), Vector2(-28 + k * 20, -112), dark, 3.0)
	draw_polyline(PackedVector2Array([Vector2(-50, 0), Vector2(-40, -120)]), grain, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(50, 0), Vector2(40, -120)]), grain, 2.0, true)
	# 손바닥 (손가락이 도드라지게 조금 작게)
	var palm_c := Vector2(0, -148)
	draw_colored_polygon(RootSpike._ellipse(palm_c, 70.0, 50.0), bark)
	draw_polyline(RootSpike._ellipse(palm_c, 70.0, 50.0, 24) + PackedVector2Array([Vector2(palm_c.x + 70.0, palm_c.y)]), dark, 2.5, true)
	draw_colored_polygon(RootSpike._ellipse(palm_c + Vector2(0, 6), 46.0, 30.0), dark)
	# 손가락: 벌렸다가(_close 0) 가운데로 오므린다(_close 1). 각 손가락은 어두운 테두리 + 밝은 결 선으로 따로 보인다.
	for i in FINGERS.size():
		var spread: float = FINGERS[i]
		var a := spread * (1.0 - 0.72 * _close)
		var base := palm_c + Vector2(sin(spread) * 58.0, -cos(spread) * 36.0)
		var len := 130.0 * (1.0 - 0.25 * _close)
		var dir := Vector2(sin(a), -cos(a))
		var side := Vector2(dir.y, -dir.x)
		var sg := signf(spread + 0.01)
		var mid := base + dir * len * 0.55 + side * (-16.0 * _close * sg)
		var tipp := base + dir * len + side * (-40.0 * _close * sg) + Vector2(0, 30.0 * _close)
		var w0 := 17.0
		var pts := PackedVector2Array([base - side * w0, mid - side * w0 * 0.8, tipp, mid + side * w0 * 0.8, base + side * w0])
		draw_colored_polygon(pts, bark)
		draw_polyline(pts + PackedVector2Array([pts[0]]), dark, 2.5, true)
		draw_polyline(PackedVector2Array([base - side * w0 * 0.35, mid - side * w0 * 0.3, tipp - dir * 8.0]), grain, 2.0, true)
		# 마디
		draw_line(mid - side * w0 * 0.8, mid + side * w0 * 0.8, dark, 2.0)
		# 손톱 (옅은 가시)
		draw_colored_polygon(PackedVector2Array([tipp - dir * 20.0 - side * 6.0, tipp + dir * 8.0, tipp - dir * 20.0 + side * 6.0]), Color(0.9, 0.82, 0.95))
	# 빛나는 금 (오므릴수록 밝음)
	var glow := Color(crack, 0.3 + 0.6 * _close)
	draw_line(palm_c + Vector2(-26, 18), palm_c + Vector2(8, -26), glow, 3.0)
	draw_line(palm_c + Vector2(8, -26), palm_c + Vector2(30, 8), glow, 2.5)
	draw_line(Vector2(-8, -20), Vector2(5, -100), glow, 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2(0, GRAB_CENTER_Y * _rise), 70.0, Color(0.7, 0.4, 1.0, 0.07 + 0.12 * _close))


## 늦게 솟는 손의 바닥 예고 (보스 그림의 뿌리 손 예고와 같은 모양: 붉은 타원 + 위로 뻗는 기둥 + 손가락 자국, 가드 불가 = 깜빡임)
func _draw_telegraph() -> void:
	var blink := 0.7 + 0.3 * sin(_t * TAU * RootKeeper.TELEGRAPH_BLINK_HZ)   # 꺼지지 않고 맥동 (최저 0.4)
	var ell := RootSpike._ellipse(Vector2.ZERO, 125.0, 32.0, 28)
	draw_colored_polygon(ell, Color(RED_C, 0.5 * blink))
	draw_polyline(ell + PackedVector2Array([ell[0]]), Color(RED_C, 1.0 * blink), 3.0, true)
	draw_rect(Rect2(-110.0, -240.0, 220.0, 240.0), Color(RED_C, 0.09 * blink))
	for i in 5:
		var a := -1.0 + 0.5 * i
		var base := Vector2(sin(a) * 90.0, -10.0)
		draw_line(base, base + Vector2(sin(a) * 40.0, -60.0), Color(RED_C, 0.7 * blink), 3.0)

extends Node
## 보스 그림 움직임 수치 검사 (화면 없이).
## 보스 씬을 띄우되 엔진의 자동 처리는 끄고, 내가 1/60초씩 _physics_process / _process 를 직접 불러
## 공격 한 사이클(예비 → 타격 → 되돌림 → 복귀) 동안 그림의 기울기·배율·세로 위치가 프레임 사이에 얼마나 뛰는지 찍는다.
## 또 타격 정점(가장 앞으로 기운 순간)이 히트박스가 켜지는 순간(on_active) 뒤 얼마에 오는지 적는다.
## 실행: godot --headless --path <프로젝트> res://tools/probe_bosses.tscn
## (-s 스크립트로는 자동 로드 Juice 등이 안 떠서 보스 스크립트가 컴파일되지 않는다 → 작은 씬으로 띄운다)
## 기준: 프레임 간 기울기 변화 < 0.2rad(11°), 배율 변화 < 0.1, 세로 위치 변화 < 32px 이면 "이어진다"고 본다.
## (예전 코드는 경계에서 세로 94px·배율 0.3 이 한 프레임에 뛰었다. 타격은 의도적으로 빠르므로 0.1~0.16rad/프레임은 정상.)

const DT := 1.0 / 60.0
var KNIGHT: PackedScene
var ROOT: PackedScene
var BIRD: PackedScene
var PLAYER: PackedScene

var _fail := 0


func _ready() -> void:
	await get_tree().process_frame
	print("[probe] 시작")
	KNIGHT = load("res://scenes/bosses/lantern_knight.tscn")
	ROOT = load("res://scenes/bosses/root_keeper.tscn")
	BIRD = load("res://scenes/bosses/gray_leaf_bird.tscn")
	PLAYER = load("res://scenes/player/player.tscn")
	_knight()
	_root_keeper()
	_bird()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _spawn(scene: PackedScene) -> Array:
	var boss := scene.instantiate()
	get_tree().root.add_child(boss)
	# 엔진의 자동 호출은 끄고 내가 직접 1/60초씩 부른다 (process_mode 를 끄면 물리 공간에서도 빠지므로 이렇게)
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.visible = true
	boss.arena = Rect2(0, 0, 2400, 1200)
	boss.ground_y = 1000.0
	boss.global_position = Vector2(1200, 1000)
	var vis: Sprite2D = boss.get_node("Sprite")
	vis.set_process(false)
	return [boss, vis]


## 한 사이클을 돌리며 그림 값을 기록한다. done 은 끝났는지 알려 주는 콜러블.
## 돌려주는 값: {max_rot, max_sx, max_sy, max_dy, peak_t, active_t, frames, states}
func _run(boss: Node, vis: Sprite2D, done: Callable, max_time := 6.0, each: Callable = Callable()) -> Dictionary:
	var prev_rot := vis.rotation
	var prev_scale := vis.scale
	var prev_y := vis.position.y
	var r := {"max_rot": 0.0, "max_sx": 0.0, "max_sy": 0.0, "max_dy": 0.0, "peak_t": -1.0, "active_t": -1.0, "frames": 0, "states": [], "at": {}}
	var t := 0.0
	var peak := -INF
	var last_state := -1
	var last_phase := ""
	while t < max_time:
		boss._physics_process(DT)
		vis._process(DT)
		if each.is_valid():
			each.call(t)
		t += DT
		r.frames += 1
		if boss.state != last_state:
			last_state = boss.state
			r.states.append("%.2f %s" % [t, boss.state_name()])
		if "attack_phase" in boss and boss.attack_phase != last_phase:
			last_phase = boss.attack_phase
			if last_phase == "active" and r.active_t < 0.0:
				r.active_t = t
		var d_rot := absf(vis.rotation - prev_rot)
		var d_sx := absf(absf(vis.scale.x) - absf(prev_scale.x))
		var d_sy := absf(vis.scale.y - prev_scale.y)
		var d_y := absf(vis.position.y - prev_y)
		if d_rot > r.max_rot: r.max_rot = d_rot; r.at["rot"] = "%.2f %s/%s" % [t, boss.state_name(), boss.attack_phase if "attack_phase" in boss else ""]
		if d_sx > r.max_sx: r.max_sx = d_sx; r.at["sx"] = "%.2f %s" % [t, boss.state_name()]
		if d_sy > r.max_sy: r.max_sy = d_sy; r.at["sy"] = "%.2f %s" % [t, boss.state_name()]
		if d_y > r.max_dy: r.max_dy = d_y; r.at["dy"] = "%.2f %s" % [t, boss.state_name()]
		# 앞으로 기운 정도 (바라보는 방향 기준)
		var fwd := vis.rotation * float(boss.facing)
		if fwd > peak:
			peak = fwd
			r.peak_t = t
		prev_rot = vis.rotation
		prev_scale = vis.scale
		prev_y = vis.position.y
		if done.call():
			break
	r["peak_rot"] = peak
	return r


func _report(label: String, r: Dictionary, rot_lim := 0.2, scale_lim := 0.1, dy_lim := 32.0) -> void:
	var ok: bool = r.max_rot < rot_lim and r.max_sx < scale_lim and r.max_sy < scale_lim and r.max_dy < dy_lim
	print("[probe] %s: 프레임 %d, 프레임 간 최대 변화 — 기울기 %.3f(%s)  배율x %.3f(%s)  배율y %.3f(%s)  세로 %.1fpx(%s)  → %s" % [
		label, r.frames, r.max_rot, r.at.get("rot", ""), r.max_sx, r.at.get("sx", ""), r.max_sy, r.at.get("sy", ""), r.max_dy, r.at.get("dy", ""), "이어짐" if ok else "끊김!"])
	if r.active_t >= 0.0 and r.peak_rot > 0.05:
		print("[probe]    히트박스 켜짐 %.3f초, 가장 앞으로 기운 순간 %.3f초 (정점 %.2frad, 켜진 뒤 %+.3f초)" % [r.active_t, r.peak_t, r.peak_rot, r.peak_t - r.active_t])
	print("[probe]    상태: %s" % ", ".join(r.states))
	if not ok:
		_fail += 1


func _knight() -> void:
	var pair := _spawn(KNIGHT)
	var boss = pair[0]
	var vis: Sprite2D = pair[1]
	boss.facing = -1
	boss._set_state(boss.State.MARCH)
	boss._timer = 99.0
	# 정지 자세로 안정시키기
	_run(boss, vis, func() -> bool: return false, 1.0)
	# THRUST 한 사이클 (startup 0.55 → active 0.18 → recovery 0.7 → MARCH)
	boss._begin(boss.State.THRUST, 0.55)
	var r := _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss._timer < 99.0 and boss.attack_phase == "" and _settled(vis), 6.0)
	_check_active_window(r, 0.18)
	_report("기사 THRUST", r)
	# SLAM (큰 세로 움직임이 있는 공격)
	boss._timer = 99.0
	boss._red = true
	boss._begin(boss.State.SLAM, 1.0)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 6.0)
	_report("기사 SLAM", r)
	# 2페이즈 전환: SLAM 예고 중간에 체력 절반 아래로 → STAGGER → MARCH
	boss._timer = 99.0
	boss._begin(boss.State.SLAM, 1.0)
	_run(boss, vis, func() -> bool: return false, 0.4)
	boss.hp = boss.max_hp * 0.45
	boss.receive_hit(HitData.make(1.0, 0.0, null), null)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss._timer < 0.1, 4.0)
	_report("기사 2페이즈 전환(SLAM→STAGGER→MARCH)", r)
	# 저스트 가드: THRUST 타격 중 창이 튕김
	boss._timer = 99.0
	boss._begin(boss.State.THRUST, 0.55 * 0.75)
	_run(boss, vis, func() -> bool: return boss.attack_phase == "active", 2.0)
	boss.on_just_guarded(null, 10.0)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 4.0)
	_report("기사 저스트 가드 휘청", r)
	# 방향 전환: 몸 틀기 (scale.x 가 한 프레임에 뒤집히지 않는다)
	boss._timer = 99.0
	boss.facing = 1
	var min_abs := INF
	var flipped_frames := 0
	var prev_sx := vis.scale.x
	for i in 60:
		boss._physics_process(DT)
		vis._process(DT)
		min_abs = minf(min_abs, absf(vis.scale.x))
		if absf(vis.scale.x - prev_sx) > 0.2:   # 전체 뒤집기(0.8)의 1/4 넘게 한 프레임에 뛰면 끊김
			flipped_frames += 1
		prev_sx = vis.scale.x
	print("[probe] 기사 방향 전환: 60프레임 동안 |scale.x| 최소 %.3f (0.4 기준), 한 프레임에 0.2 넘게 뛴 횟수 %d → %s" % [min_abs, flipped_frames, "몸 틀기 OK" if flipped_frames == 0 and min_abs < 0.2 else "끊김!"])
	if flipped_frames > 0 or min_abs >= 0.2:
		_fail += 1
	# SLAM 웅크림: 예비 앞 30% 동안 먼저 내려앉았다가(아래로) 그 뒤 솟구친다(위로)
	boss._timer = 99.0
	boss.facing = -1
	_run(boss, vis, func() -> bool: return false, 1.0)
	# (람다는 지역 실수를 값으로 잡으므로 사전(참조)에 기록한다)
	var y0 := vis.position.y
	var c := {"low": -INF, "high": INF, "t_low": 0.0, "t_high": 0.0}
	boss._begin(boss.State.SLAM, 1.0)
	_run(boss, vis, func() -> bool: return boss.attack_phase != "startup", 3.0, func(t: float) -> void:
		var dy: float = vis.position.y - y0
		if dy > c.low:
			c.low = dy; c.t_low = t
		if dy < c.high:
			c.high = dy; c.t_high = t)
	var crouch_ok: bool = c.low > 5.0 and c.t_low < 0.5 and c.high < -40.0 and c.t_high > c.t_low
	print("[probe] 기사 SLAM 웅크림: 예비 중 가장 내려앉음 %+.1fpx(%.2f초) → 가장 솟음 %+.1fpx(%.2f초) → %s" % [c.low, c.t_low, c.high, c.t_high, "웅크림→도약 OK" if crouch_ok else "웅크림 없음!"])
	if not crouch_ok:
		_fail += 1
	_run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 6.0)
	_facing_hold(boss, vis, "기사", boss.State.MARCH)
	boss.queue_free()


## 소녀가 보스 바로 옆(데드존 안)을 왔다 갔다 해도 몸이 매 프레임 뒤집히지 않는지,
## 멀리(데드존 밖) 넘어가도 최소 유지 시간 안에는 다시 돌지 않는지 센다.
func _facing_hold(boss: Node, vis: Sprite2D, label: String, idle_state: int) -> void:
	var player: Player = PLAYER.instantiate()
	get_tree().root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	boss.player = player
	boss._set_state(idle_state)
	boss._timer = 99.0
	boss.facing = -1
	var flips_near := 0
	var prev: int = boss.facing
	# 1) 데드존 안에서 4프레임마다 좌우 바꿈 (몸을 통과하는 상황) — 1초
	for i in 60:
		player.global_position = boss.global_position + Vector2(20.0 if (i / 4) % 2 == 0 else -20.0, 0)
		boss._physics_process(DT)
		vis._process(DT)
		if boss.facing != prev:
			flips_near += 1
		prev = boss.facing
	# 2) 데드존 밖으로 넘어감 → 한 번 돌고, 0.1초 뒤 반대쪽으로 다시 넘어가도 유지 시간 안에는 안 돈다
	var flips_far := 0
	var first_flip_t := -1.0
	var second_flip_t := -1.0
	for i in 60:
		var t := i * DT
		player.global_position = boss.global_position + Vector2(120.0 if t < 0.1 else -120.0, 0)
		boss._physics_process(DT)
		vis._process(DT)
		if boss.facing != prev:
			flips_far += 1
			if first_flip_t < 0.0:
				first_flip_t = t
			elif second_flip_t < 0.0:
				second_flip_t = t
		prev = boss.facing
	var gap := second_flip_t - first_flip_t if second_flip_t >= 0.0 else INF
	var ok: bool = flips_near == 0 and flips_far >= 1 and gap >= boss.face_hold - 0.02
	print("[probe] %s 방향 유지: 데드존 안 왕복 1초 동안 뒤집힘 %d회(0 기준), 데드존 밖 전환 %d회, 두 전환 간격 %.2f초(%.2f 이상) → %s" % [label, flips_near, flips_far, gap, boss.face_hold, "OK" if ok else "떨림!"])
	if not ok:
		_fail += 1
	boss.player = null
	player.queue_free()


func _settled(vis: Sprite2D) -> bool:
	return absf(vis.rotation) < 0.02


func _check_active_window(r: Dictionary, active_len: float) -> void:
	if r.active_t < 0.0:
		return
	var inside: bool = r.peak_t >= r.active_t - 0.001 and r.peak_t <= r.active_t + active_len + 0.001
	print("[probe]    타격 정점이 히트박스 구간(%.2f~%.2f) 안: %s" % [r.active_t, r.active_t + active_len, "예" if inside else "아니오!"])
	if not inside:
		_fail += 1


func _root_keeper() -> void:
	var pair := _spawn(ROOT)
	var boss = pair[0]
	var vis: Sprite2D = pair[1]
	boss.facing = -1
	boss._set_state(boss.State.STANCE)
	boss._timer = 99.0
	_run(boss, vis, func() -> bool: return false, 1.0)
	# SPIKES (지팡이 들어 올려 내리꽂기, 세로 움직임)
	boss.spike_marks = [1000.0, 800.0]
	boss._begin(boss.State.SPIKES, 0.9)
	var r := _run(boss, vis, func() -> bool: return boss.state == boss.State.STANCE and boss.attack_phase == "", 6.0)
	_report("뿌리지기 SPIKES", r)
	# SWEEP
	boss._timer = 99.0
	boss._begin(boss.State.SWEEP, 0.5)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.STANCE and boss.attack_phase == "", 6.0)
	_check_active_window(r, 0.2)
	_report("뿌리지기 SWEEP", r)
	# 저스트 가드 (SWEEP 타격 중)
	boss._timer = 99.0
	boss._begin(boss.State.SWEEP, 0.5)
	_run(boss, vis, func() -> bool: return boss.attack_phase == "active", 2.0)
	boss.on_just_guarded(null, 10.0)
	# 휘청 보정(stagger)이 힌트가 끝날 때 한 번에 사라지지 않는지: 힌트 끝 전후의 stagger 값 변화를 본다
	var sg := {"before": boss.stagger, "jump": 0.0, "start": boss.stagger}
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.STANCE and boss.attack_phase == "", 6.0, func(_t: float) -> void:
		sg.jump = maxf(sg.jump, absf(boss.stagger - sg.before))
		sg.before = boss.stagger)
	var stag_ok: bool = sg.start >= 0.99 and sg.jump < 0.06 and boss.stagger == 0.0
	print("[probe]    휘청 세기(stagger) 시작 %.2f → 프레임 간 최대 변화 %.3f(0.06 기준, 1→0 서서히) → 끝값 %.2f → %s" % [sg.start, sg.jump, boss.stagger, "서서히 OK" if stag_ok else "툭 사라짐!"])
	if not stag_ok:
		_fail += 1
	_report("뿌리지기 저스트 가드 휘청", r)
	# WALL
	boss._timer = 99.0
	boss._red = true
	boss._begin(boss.State.WALL, 1.1)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.STANCE and boss.attack_phase == "", 6.0)
	_report("뿌리지기 WALL", r)
	# 2페이즈: SPIKES 예고 도중 RISE 로 (쓰러졌다 일어섬; dy 점프 없어야 함)
	boss._timer = 99.0
	boss.spike_marks = [1000.0, 800.0]
	boss._begin(boss.State.SPIKES, 0.9)
	_run(boss, vis, func() -> bool: return false, 0.5)
	boss.hp = boss.max_hp * 0.45
	boss.receive_hit(HitData.make(1.0, 0.0, null), null)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.STANCE and boss._timer < 0.2, 6.0)
	_report("뿌리지기 2페이즈(SPIKES→RISE→STANCE)", r)
	_facing_hold(boss, vis, "뿌리지기", boss.State.STANCE)
	boss.queue_free()


func _bird() -> void:
	var pair := _spawn(BIRD)
	var boss = pair[0]
	var vis: Sprite2D = pair[1]
	boss.facing = -1
	boss.set_collision_mask_value(1, true)
	boss._set_state(boss.State.GROUND_IDLE)
	boss._timer = 99.0
	_run(boss, vis, func() -> bool: return false, 1.0)
	# SWEEP (날개 휘두르기)
	boss._set_state(boss.State.SWEEP)
	boss._timer = 0.55
	boss._melee_stage = 0
	boss.attack_phase = "startup"
	boss.windup_progress = 0.0
	boss.startup_len = 0.55
	var r := _run(boss, vis, func() -> bool: return boss.state == boss.State.GROUND_IDLE and boss._timer < 0.05, 6.0)
	_check_active_window(r, 0.22)
	_report("새 SWEEP", r)
	# PECK (부리 찍기, 돌진)
	boss._timer = 99.0
	boss._set_state(boss.State.PECK)
	boss._timer = 0.45
	boss._melee_stage = 0
	boss.attack_phase = "startup"
	boss.windup_progress = 0.0
	boss.startup_len = 0.45
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.GROUND_IDLE and boss._timer < 0.05, 6.0)
	_check_active_window(r, 0.3)
	_report("새 PECK", r)
	# 공중: HOVER 에서 WIND 로, 다시 HOVER (날갯짓 위상 연속)
	boss.hover_points = [Vector2(600, 500), Vector2(1200, 500), Vector2(1800, 500)]
	boss._hover_target = Vector2(1200, 500)
	boss.set_collision_mask_value(1, false)
	boss.global_position = Vector2(1200, 520)
	boss._set_state(boss.State.HOVER)
	boss._timer = 99.0
	_run(boss, vis, func() -> bool: return false, 1.0)
	boss._set_state(boss.State.WIND)
	boss._timer = boss.wind_telegraph + boss.wind_time
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.HOVER, 4.0)
	_report("새 HOVER→WIND→HOVER", r, 0.1, 0.06, 14.0)
	# 날갯바람 끝에서 붉은색이 한 프레임에 돌아오지 않는다
	boss.queue_free()

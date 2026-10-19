extends SceneTree
## 셀레니아 뼈대 애니메이션의 '연속성'을 숫자로 확인하는 독립 시험 (화면 없이 돈다).
## 실행: godot --headless --path <프로젝트> -s res://tools/probe_selenia.gd
## 하는 일: 진짜 소녀(player.tscn)를 바닥 위에 세우고 상태를 흐름대로 꽂으며 1/120초마다 뼈대를 한 번씩 돌린다.
##   흐름: 대기 → 약공격 3연타 → 대기 → 걷기 → 달리기 → 점프 → 낙하 → 착지 → 방향 전환 → 씨앗 베기 → 낙하 공격 → …
## 찍는 것: 관절마다 프레임 사이 최대 변화량(라디안), '툭' 하는 프레임(직전 변화의 3배 넘게 갑자기 뛴 곳),
##   약공격·씨앗 베기마다 칼팔이 가장 빠른 순간과 몸 앞을 지나는 순간이 히트박스 구간(active) 어디에 오는지.
##   (강공격은 2026-10-18 없앴다. 그 자리의 영혼 기술 '씨앗 베기'와 새 '낙하 공격'을 본다.)
## 마지막 줄 "[probe] 결과: 통과/실패" 로 판정한다.

const DT := 1.0 / 120.0
const JOINTS := ["torso", "head", "arm_back", "arm_sword", "leg_back", "leg_front", "cloak_near", "cape"]
const SNAP_LIMIT := 0.5      # 한 프레임(1/120초)에 이보다 크게 움직이면 끊김으로 본다 (60 rad/s)

var _player: Node   # Player (스크립트를 -s 로 돌릴 때는 Player 형을 컴파일 시점에 쓸 수 없어 동적으로 다룬다)
var S := {}          # Player.State 이름 → 값
var _visual: Node2D
var _prev := {}
var _prev_d := {}
var _fail := false
var _t := 0.0
var _seg := ""
var _seg_max := {}
var _log := []          # [시각, 관절, 변화량] 끊김 기록
var _arm_track := []    # [시각, 칼팔 각도] (정점 계산용)
var _landed := false
var _plunge_landed := false   # 낙하 공격 착지 신호 (람다는 지역 변수를 값으로 잡으므로 멤버로 둔다)
var _cur_dt := DT       # 마지막 틱의 길이 (정점 속도 계산용)
var _cross_pct := -1.0  # 마지막 _report_peaks 가 찾은 '앞 지남' 위치 (구간의 %)


func _initialize() -> void:
	_ensure_autoloads()
	Engine.physics_ticks_per_second = 120
	_run()


func _ensure_autoloads() -> void:
	# -s 로 돌릴 때 자동 로드가 없으면 project.godot 의 목록대로 직접 올린다
	if root.has_node("Progress"):
		return
	for key in ProjectSettings.get_property_list():
		var n: String = key["name"]
		if n.begins_with("autoload/"):
			var path: String = ProjectSettings.get_setting(n)
			path = path.trim_prefix("*")
			var res = load(path)
			var node: Node = res.instantiate() if res is PackedScene else Node.new()
			if not (res is PackedScene):
				node.set_script(res)
			node.name = n.trim_prefix("autoload/")
			root.add_child(node)


func _run() -> void:
	await process_frame
	# 바닥
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20000, 200)
	shape.shape = rect
	shape.position = Vector2(0, 100)
	floor_body.add_child(shape)
	root.add_child(floor_body)
	# 소녀
	_player = load("res://scenes/player/player.tscn").instantiate()
	_player.position = Vector2(0, -68)
	root.add_child(_player)
	_player.input_enabled = false
	_visual = _player.get_node("Visual")
	S = _player.get_script().get_script_constant_map()["State"]
	_visual.set_process(false)     # 엔진 대신 우리가 1/120초마다 돌린다
	for i in 20:
		await physics_frame
	print("[probe] 바닥 위: %s, 상태 %s" % [_player.is_on_floor(), _player.state_name()])

	_begin("대기")
	await _steps(60, func(): _player.velocity.x = 0.0)
	_end()

	_begin("약공격 3연타")
	_player._start_light(1)
	_arm_track.clear()
	var windows := []      # [타, active 시작 시각]
	var last_phase := ""
	var last_step := 0
	while _player.state == S["ATTACK"] and _t < 20.0:
		if _player.attack_step < 3:
			_player._attack_buffered = true
		await _step(Callable())
		if _player.attack_phase == "active" and (last_phase != "active" or last_step != _player.attack_step):
			windows.append([_player.attack_step, _hit_on_time(_player.light_active)])
		last_phase = _player.attack_phase
		last_step = _player.attack_step
	_end()
	_report_peaks(windows, _player.light_active, "약공격")

	_begin("공격 뒤 대기")
	await _steps(60, Callable())
	_end()

	_begin("걷기")
	await _steps(120, func(): _player.velocity.x = 380.0)
	print("[probe]   걷기 중 상태: %s (속도 %.0f)" % [_player.state_name(), _player.velocity.x])
	_end()

	_begin("달리기")
	await _steps(120, func(): _player.velocity.x = 700.0)
	print("[probe]   달리기 중 상태: %s (속도 %.0f)" % [_player.state_name(), _player.velocity.x])
	_end()

	_begin("점프→낙하→착지")
	_player._do_jump(false)
	_landed = false
	_player.landed.connect(func(_v): _landed = true)
	var n := 0
	while not _landed and n < 400:
		await _step(func(): _player.velocity.x = 700.0)
		n += 1
	print("[probe]   공중 %.2f초 뒤 착지, 상태 %s" % [n * DT, _player.state_name()])
	await _steps(60, func(): _player.velocity.x = 0.0)
	_end()

	_begin("방향 전환")
	var min_abs_sx := 10.0
	var max_sx_jump := 0.0
	var prev_sx: float = _visual.scale.x
	_player.facing = -1
	for i in 40:
		await _step(Callable())
		var sx: float = _visual.scale.x
		min_abs_sx = minf(min_abs_sx, absf(sx))
		max_sx_jump = maxf(max_sx_jump, absf(sx - prev_sx))
		prev_sx = sx
	print("[probe]   scale.x 가 지난 가장 얇은 값 %.2f, 한 프레임 최대 변화 %.2f (뒤집기면 2.0)" % [min_abs_sx, max_sx_jump])
	if max_sx_jump > 0.6:
		_fail = true
		print("[probe]   !! 방향 전환이 한 프레임에 뒤집혔다")
	_player.facing = 1
	await _steps(40, Callable())
	_end()

	_begin("씨앗 베기(넓은 호)")
	_player._start_soul_slash()
	_arm_track.clear()
	var swindows := []
	last_phase = ""
	var windup_min := 10.0
	while _player.state == S["SOUL_SLASH"] and _t < 40.0:
		await _step(Callable())
		if _player.attack_phase == "startup":
			windup_min = minf(windup_min, _visual._out["arm_sword"])
		if _player.attack_phase == "active" and last_phase != "active":
			swindows.append([0, _hit_on_time(_player.slash_active)])
		last_phase = _player.attack_phase
	_end()
	_report_peaks(swindows, _player.slash_active, "씨앗 베기")
	print("[probe]   씨앗 베기 예비동작 끝 칼팔 %.2f (설계 %.2f: 머리 위 뒤로 크게)" % [windup_min, _visual.WINDUP_S["arm_sword"]])
	if windup_min > _visual.WINDUP_S["arm_sword"] + 0.35:
		_fail = true
		print("[probe]   !! 씨앗 베기 예비동작이 칼을 충분히 들어 올리지 못한다")

	_begin("씨앗 베기 뒤 대기")
	await _steps(60, Callable())
	_end()

	_begin("낙하 공격(점프 → 공중에서 멈칫 → 급강하 → 착지)")
	_player._do_jump(false)
	await _steps(30, Callable())
	_player._start_plunge()
	var phases := []
	var max_vy := 0.0
	_plunge_landed = false
	_player.plunge_landed.connect(func(): _plunge_landed = true)
	n = 0
	while _player.state == S["PLUNGE"] and n < 600:
		await _step(Callable())
		n += 1
		if _player.state == S["PLUNGE"] and (phases.is_empty() or phases[-1] != _player.attack_phase):
			phases.append(_player.attack_phase)
		max_vy = maxf(max_vy, _player.velocity.y)
	print("[probe]   낙하 공격 국면 흐름: %s | 최고 낙하 속도 %.0f (설정 %.0f) | 착지 신호 %s | %.2f초 뒤 상태 %s" % [", ".join(phases), max_vy, _player.plunge_speed, _plunge_landed, n * DT, _player.state_name()])
	if not (phases.has("pause") and phases.has("dive") and phases.has("land") and phases.has("recovery")) or not _plunge_landed:
		_fail = true
		print("[probe]   !! 낙하 공격 국면(pause→dive→land→recovery)이 빠졌다")
	await _steps(60, Callable())
	_end()

	_begin("구르기")
	_player._roll_timer = _player.roll_duration
	_player._set_state(S["ROLL"])
	var min_rot := 0.0
	var max_rot := 0.0
	var max_rot_step := 0.0
	var prev_rot: float = _visual.rotation
	while _player.state == S["ROLL"] and _t < 60.0:
		await _step(Callable())
		max_rot_step = maxf(max_rot_step, absf(wrapf(_visual.rotation - prev_rot, -PI, PI)))   # 2π 차이는 같은 그림
		prev_rot = _visual.rotation
		min_rot = minf(min_rot, _visual.rotation)
		max_rot = maxf(max_rot, _visual.rotation)
	await _steps(30, Callable())
	max_rot_step = maxf(max_rot_step, absf(wrapf(_visual.rotation - prev_rot, -PI, PI)))
	print("[probe]   구르기 회전 %.2f~%.2f rad (한 바퀴 = %.2f), 한 프레임 최대 회전 %.3f, 끝난 뒤 %.3f" % [min_rot, max_rot, TAU, max_rot_step, _visual.rotation])
	if max_rot_step > 0.6:
		_fail = true
		print("[probe]   !! 구르기 회전이 한 프레임에 튀었다")
	_end()

	_begin("피격(앞에서 맞아 뒤로 밀림)")
	_player.velocity.x = -200.0
	_player._hit_timer = _player.hit_stun
	_player._set_state(S["HIT"])
	_player.hit_taken.emit(10.0)
	await _steps(60, Callable())
	_end()

	_begin("회복")
	_player._heal_timer = _player.heal_time
	_player._set_state(S["HEAL"])
	while _player.state == S["HEAL"] and _t < 80.0:
		await _step(Callable())
	await _steps(30, Callable())
	_end()

	_begin("가드 → 저스트 가드 → 해제")
	_player._set_state(S["GUARD"])
	await _steps(30, Callable())
	_player.just_guarded.emit(null)
	await _steps(30, Callable())
	_player._set_state(S["IDLE"])
	await _steps(30, Callable())
	_end()

	_begin("정화의 손길")
	_player._set_state(S["PURIFY"])
	await _steps(54, Callable())
	_player.purified.emit(null)
	await _steps(60, Callable())
	_player._set_state(S["IDLE"])
	await _steps(30, Callable())
	_end()

	_begin("쉬기 → 일어남")
	_player._set_state(S["REST"])
	await _steps(90, Callable())
	_player._set_state(S["IDLE"])
	await _steps(60, Callable())
	_end()

	_begin("쓰러짐 → 부활")
	_player._set_state(S["DEAD"])
	var rot_at := {}
	for i in 150:
		await _step(Callable())
		if i in [30, 60, 90, 120, 149]:
			rot_at[i] = [_visual.rotation, _visual.modulate.a]
	print("[probe]   쓰러짐: 0.25초 회전 %.2f/알파 %.2f, 0.5초 %.2f/%.2f, 0.75초 %.2f/%.2f, 1.0초 %.2f/%.2f, 1.25초 %.2f/%.2f" % [
		rot_at[30][0], rot_at[30][1], rot_at[60][0], rot_at[60][1], rot_at[90][0], rot_at[90][1], rot_at[120][0], rot_at[120][1], rot_at[149][0], rot_at[149][1]])
	_player.revive(Vector2(0, -68))
	_prev = {}   # 부활은 다른 자리에 다시 서는 것이라 자세가 바로 바뀌는 게 맞다 (끊김으로 세지 않는다)
	_prev_d = {}
	var revive_rows := []
	for i in 16:
		await _step(Callable())
		if i % 3 == 0:
			revive_rows.append("%.2f/%.0fpx" % [_visual.rotation, _visual.position.y])
	print("[probe]   부활 뒤 회전/position.y (3프레임마다): %s" % " ".join(revive_rows))
	if absf(_visual.rotation) > 0.05 or absf(_visual.position.y) > 2.0:
		_fail = true
		print("[probe]   !! 부활 뒤에도 쓰러진 기울기가 남아 있다")
	await _steps(44, Callable())
	_end()

	await _check_60fps()

	if _log.is_empty():
		print("[probe] 끊긴 프레임 없음 (한 프레임 변화 > %.2f rad 이면서 직전의 3배 넘는 곳)" % SNAP_LIMIT)
	else:
		for e in _log:
			print("[probe] !! 끊김 %.3f초 %s: %.3f rad (직전 %.3f)" % e)
		_fail = true
	print("[probe] 결과: %s" % ("실패" if _fail else "통과"))
	quit()


func _begin(name: String) -> void:
	_seg = name
	_seg_max = {}
	for j in JOINTS:
		_seg_max[j] = 0.0
	_seg_max["hip"] = 0.0
	_seg_max["scale"] = 0.0


func _end() -> void:
	var parts := []
	for j in JOINTS:
		parts.append("%s %.3f" % [j, _seg_max[j]])
	print("[probe] %s — 관절별 한 프레임 최대 변화(rad): %s | 엉덩이 %.2fpx 찌그러짐 %.3f" % [_seg, ", ".join(parts), _seg_max["hip"], _seg_max["scale"]])


func _steps(count: int, before: Callable) -> void:
	for i in count:
		await _step(before)


## 한 틱: (물리 전에) 속도 등을 꽂고 → 물리 한 번(1/120초) → 뼈대 한 번 → 변화량 기록.
## dt 를 1/60 으로 주면 물리는 두 번 돌고 뼈대는 한 번만 돈다 (60fps 화면 흉내).
func _step(before: Callable, dt: float = DT) -> void:
	if before.is_valid():
		before.call()
	var n := maxi(int(roundf(dt / DT)), 1)
	for i in n:
		await physics_frame
	_visual._process(dt)
	_t += dt
	_cur_dt = dt
	var cur := {}
	for j in JOINTS:
		cur[j] = (_visual._bones[j] as Node2D).rotation
	var hip: Vector2 = _visual._hip.position
	var sc: Vector2 = _visual.scale
	if not _prev.is_empty():
		for j in JOINTS:
			var d: float = absf(cur[j] - _prev[j])
			_seg_max[j] = maxf(_seg_max[j], d)
			var pd: float = _prev_d.get(j, 0.0)
			# 끊김 판정은 1/120초 기준. 60fps 재확인 구간은 '닿는지·언제 지나는지'만 본다 (한 프레임이 두 배 길어 같은 잣대를 못 쓴다)
			if dt == DT and d > SNAP_LIMIT and d > pd * 3.0:
				_log.append([_t, j, d, pd])
			_prev_d[j] = d
		_seg_max["hip"] = maxf(_seg_max["hip"], hip.distance_to(_prev["hip"]))
		_seg_max["scale"] = maxf(_seg_max["scale"], absf(sc.y - _prev["scale"].y))
	_prev = cur
	_prev["hip"] = hip
	_prev["scale"] = sc
	_arm_track.append([_t, cur["arm_sword"]])


## 타격 정점: 히트박스가 켜진 구간(active 시작 ~ +길이) 안에서 칼팔이 가장 빨리 도는 순간과,
## 당긴 각도와 휘두른 각도의 가운데를 지나는 순간을 찾는다. 둘 다 구간 안에 있어야 한다.
func _report_peaks(windows: Array, active_len: float, label: String) -> void:
	for w in windows:
		var step: int = w[0]
		var t0: float = w[1]
		var t1 := t0 + active_len
		# 구간 앞뒤로 조금 넓혀 살핀다 (정점이 밖으로 샜는지 보려고)
		var best_v := 0.0
		var best_t := -1.0
		var a_start := 0.0
		var a_end := 0.0
		var first := true
		for i in range(1, _arm_track.size()):
			var tt: float = _arm_track[i][0]
			if tt < t0 - 0.03 or tt > t1 + 0.08:
				continue
			if first:
				a_start = _arm_track[i - 1][1]
				first = false
			a_end = _arm_track[i][1]
			var v: float = absf(_arm_track[i][1] - _arm_track[i - 1][1]) / _cur_dt
			if v > best_v:
				best_v = v
				best_t = tt
		# 가운데 각도를 지나는 순간: '당긴 각(구간 직전)'과 '히트박스 구간 안에서 가장 멀리 휘두른 각'의 중간.
		# (구간 뒤 0.08초는 이미 되돌림이라 끝 각도로 쓰면 가운데가 틀어진다)
		var extreme := a_start
		for i in range(1, _arm_track.size()):
			var tt: float = _arm_track[i][0]
			if tt < t0 - 0.03 or tt > t1:
				continue
			if absf(_arm_track[i][1] - a_start) > absf(extreme - a_start):
				extreme = _arm_track[i][1]
		var mid := (a_start + extreme) * 0.5
		var cross_t := -1.0
		for i in range(1, _arm_track.size()):
			var tt: float = _arm_track[i][0]
			if tt < t0 - 0.03 or tt > t1 + 0.08:
				continue
			var a0: float = _arm_track[i - 1][1]
			var a1: float = _arm_track[i][1]
			if (a0 - mid) * (a1 - mid) <= 0.0 and a0 != a1:
				# 프레임 사이를 직선으로 보간해 지나는 시각을 어림한다 (60fps 에서는 한 프레임이 구간의 17%라 그냥 쓰면 거칠다)
				var tp: float = _arm_track[i - 1][0]
				cross_t = lerpf(tp, tt, clampf((mid - a0) / (a1 - a0), 0.0, 1.0))
				break
		var in_win := best_t >= t0 and best_t <= t1 and cross_t >= t0 and cross_t <= t1
		_cross_pct = (cross_t - t0) / active_len * 100.0
		print("[probe]   %s %d타: 히트박스 %.3f~%.3f초 | 칼팔 최고 속도 %.0f rad/s @%.3f (구간의 %.0f%%) | 앞 지남 @%.3f (구간의 %.0f%%) | 휘두른 각 %.2f rad → %s" % [
			label, step, t0, t1, best_v, best_t, (best_t - t0) / active_len * 100.0, cross_t, (cross_t - t0) / active_len * 100.0, a_end - a_start, "구간 안" if in_win else "!! 구간 밖"])
		if not in_win:
			_fail = true


## 60fps 재확인: 1/120초로는 잘 따라가도 실제 기기(60fps)에서는 '휘두른 자세'에 못 닿거나 전환이 한 프레임에 끝날 수 있다.
## 약공격 1타·강공격의 화면 칼팔 최소값, 방향 전환 프레임, 저스트 가드 튕김, 쉬기→일어남, 착지 웅크림을 60fps 로 찍는다.
func _check_60fps() -> void:
	const D60 := 1.0 / 60.0
	print("[probe] ---- 60fps 재확인 ----")
	_prev = {}      # 120Hz 와 60fps 사이의 변화량은 비교하지 않는다
	_prev_d = {}
	await _steps60(30)

	# 약공격 1타: 화면 칼팔이 설계 자세(-1.15)에 닿고 지나치는지
	_begin("60fps 약공격 1타")
	_player._start_light(1)
	_arm_track.clear()
	var windows := []
	var last_phase := ""
	var arm_min := 10.0     # 화면 각도 (팔 + 몸통 기울기)
	var out_min := 10.0     # 팔 자체의 각도 (설계 자세와 같은 단위)
	var tgt_min := 10.0
	while _player.state == S["ATTACK"] and _t < 200.0:
		await _step(Callable(), D60)
		arm_min = minf(arm_min, (_visual._bones["arm_sword"] as Node2D).rotation)
		out_min = minf(out_min, _visual._out["arm_sword"])
		tgt_min = minf(tgt_min, _visual._tgt["arm_sword"])
		if _player.attack_phase == "active" and last_phase != "active":
			windows.append([1, _hit_on_time(_player.light_active)])
		last_phase = _player.attack_phase
	_end()
	_report_peaks(windows, _player.light_active, "60fps 약공격")
	var design_1: float = _visual.STRIKE_1["arm_sword"]
	var design_1_world: float = design_1 + _visual.STRIKE_1["torso"]
	print("[probe]   60fps 1타 칼팔 최소: 팔 %.2f (목표 %.2f, 설계 %.2f) | 화면(팔+몸통) %.2f (설계 %.2f) | 앞 지남 구간의 %.0f%%" % [out_min, tgt_min, design_1, arm_min, design_1_world, _cross_pct])
	if out_min > -1.2 or arm_min > design_1_world:
		_fail = true
		print("[probe]   !! 60fps 에서 1타 칼팔이 휘두른 자세(-1.2)에 못 닿는다")
	if _cross_pct < 35.0 or _cross_pct > 55.0:
		_fail = true
		print("[probe]   !! 60fps 1타 앞 지남이 히트박스 구간 35~55%% 를 벗어났다")
	await _steps60(30)

	# 씨앗 베기: 머리 위 뒤(-3.5)에서 앞 아래(-0.35)까지 크게 돌아 지나친다. 되돌림(READY 0.15)은 빼고 휘두르는 동안(startup·active)만 잰다
	_begin("60fps 씨앗 베기")
	_player._start_soul_slash()
	_arm_track.clear()
	windows = []
	last_phase = ""
	var swing_min := 10.0     # 당긴 끝 (가장 작은 값)
	var swing_max := -10.0    # 휘두른 끝 (startup·active 동안 가장 큰 값, 지나침 포함)
	var world_max := -10.0
	while _player.state == S["SOUL_SLASH"] and _t < 200.0:
		await _step(Callable(), D60)
		if _player.state == S["SOUL_SLASH"] and _player.attack_phase in ["startup", "active"]:
			swing_min = minf(swing_min, _visual._out["arm_sword"])
			swing_max = maxf(swing_max, _visual._out["arm_sword"])
			world_max = maxf(world_max, (_visual._bones["arm_sword"] as Node2D).rotation)
		if _player.attack_phase == "active" and last_phase != "active":
			windows.append([0, _hit_on_time(_player.slash_active)])
		last_phase = _player.attack_phase
	_end()
	_report_peaks(windows, _player.slash_active, "60fps 씨앗 베기")
	var design_s: float = _visual.STRIKE_S["arm_sword"]
	var design_s_world: float = design_s + _visual.STRIKE_S["torso"]
	print("[probe]   60fps 씨앗 베기 칼팔: 당긴 끝 %.2f (설계 %.2f) → 휘두른 끝 %.2f (설계 %.2f, 지나침 포함 %.2f 위여야) | 화면(팔+몸통) %.2f (설계 %.2f) | 앞 지남 구간의 %.0f%%" % [swing_min, _visual.WINDUP_S["arm_sword"], swing_max, design_s, design_s - 0.05, world_max, design_s_world, _cross_pct])
	if swing_max < design_s - 0.05 or swing_min > _visual.WINDUP_S["arm_sword"] + 0.35:
		_fail = true
		print("[probe]   !! 60fps 에서 씨앗 베기 칼팔이 당긴 자세나 휘두른 자세에 닿지 못한다")
	if _cross_pct < 35.0 or _cross_pct > 55.0:
		_fail = true
		print("[probe]   !! 60fps 씨앗 베기 앞 지남이 히트박스 구간 35~55%% 를 벗어났다")
	await _steps60(30)

	# 낙하 공격 (60fps): 착지에서 깊게 웅크리는지
	_player._do_jump(false)
	await _steps60(15)
	_player._start_plunge()
	_plunge_landed = false
	var pn := 0
	var pl_crouch := 0.0
	while _player.state == S["PLUNGE"] and pn < 300:
		await _step(Callable(), D60)
		pn += 1
		if _plunge_landed:
			pl_crouch = maxf(pl_crouch, _visual._hip.position.y - 22.0)
	print("[probe]   60fps 낙하 공격: %.2f초, 착지 뒤 엉덩이 최대 %.1fpx 내려감 (착지 신호 %s)" % [pn * D60, pl_crouch, _plunge_landed])
	if not _plunge_landed or pl_crouch < 6.0:
		_fail = true
		print("[probe]   !! 60fps 낙하 공격 착지 웅크림이 작다")
	await _steps60(30)

	# 방향 전환: 프레임마다 고르게 돌아야 한다 (첫 프레임에 3/4 이 돌면 '툭')
	_player.facing = -1
	var sxs := []
	var max_jump := 0.0
	var prev_sx: float = _visual.scale.x
	for i in 8:
		await _step(Callable(), D60)
		sxs.append("%.2f" % _visual.scale.x)
		max_jump = maxf(max_jump, absf(_visual.scale.x - prev_sx))
		prev_sx = _visual.scale.x
	print("[probe]   60fps 방향 전환 scale.x: %s | 한 프레임 최대 %.2f" % [" ".join(sxs), max_jump])
	if max_jump > 0.5:
		_fail = true
		print("[probe]   !! 60fps 방향 전환이 한 프레임에 너무 많이 돈다")
	_player.facing = 1
	await _steps60(20)

	# 저스트 가드 튕김: 칼팔이 눈에 보일 만큼(0.25rad 이상) 튕겼다 돌아와야 한다
	_player._set_state(S["GUARD"])
	await _steps60(30)
	var base_arm: float = (_visual._bones["arm_sword"] as Node2D).rotation
	var base_hip: float = _visual._hip.position.x
	_player.just_guarded.emit(null)
	var peak := 0.0
	var hip_peak := 0.0
	var ds := []
	for i in 12:
		await _step(Callable(), D60)
		var d: float = (_visual._bones["arm_sword"] as Node2D).rotation - base_arm
		peak = maxf(peak, absf(d))
		hip_peak = maxf(hip_peak, absf(_visual._hip.position.x - base_hip))
		ds.append("%.2f" % d)
	print("[probe]   60fps 저스트 가드 칼팔 변화: %s | 최대 %.2f rad, 허리 %.1fpx" % [" ".join(ds), peak, hip_peak])
	if peak < 0.25:
		_fail = true
		print("[probe]   !! 저스트 가드 튕김이 눈에 안 보일 만큼 작다")
	_player._set_state(S["IDLE"])
	await _steps60(20)

	# 쉬기 → 일어남: 0.13초(8프레임) 뒤에도 아직 엉덩이가 내려가 있어야 벌떡 서지 않는 것
	_player._set_state(S["REST"])
	await _steps60(60)
	_player._set_state(S["IDLE"])
	var hs := []
	var hip8 := 0.0
	for i in 14:
		await _step(Callable(), D60)
		var hy: float = _visual._hip.position.y - 22.0
		hs.append("%.1f" % hy)
		if i == 7:
			hip8 = hy
	print("[probe]   60fps 쉬기→일어남 엉덩이(px): %s" % " ".join(hs))
	if hip8 < 4.0:
		_fail = true
		print("[probe]   !! 쉬기에서 너무 빨리 일어선다")
	await _steps60(30)

	# 착지: 찌그러짐과 함께 무릎이 굽는지 (엉덩이가 3px 넘게 내려가야 보인다)
	_player._do_jump(false)
	_landed = false
	var n := 0
	while not _landed and n < 200:
		await _step(Callable(), D60)
		n += 1
	var ys := []
	var crouch_max := 0.0
	for i in 12:
		await _step(Callable(), D60)
		var hy: float = _visual._hip.position.y - 22.0
		crouch_max = maxf(crouch_max, hy)
		ys.append("%.2f/%.1f" % [_visual.scale.y, hy])
	print("[probe]   60fps 착지 scale.y/엉덩이(px): %s | 웅크림 최대 %.1fpx" % [" ".join(ys), crouch_max])
	if crouch_max < 3.0:
		_fail = true
		print("[probe]   !! 착지 웅크림이 눈에 안 보인다")


## 히트박스가 실제로 켜진 시각: 'active 로 바뀐 것을 처음 본 프레임'은 켜진 뒤 조금 지난 때라, 남은 시간으로 되짚는다.
func _hit_on_time(active_len: float) -> float:
	return _t - (active_len - _player._attack_timer)


func _steps60(count: int, before: Callable = Callable()) -> void:
	for i in count:
		await _step(before, 1.0 / 60.0)

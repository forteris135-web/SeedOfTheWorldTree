extends Node
## Claude Code용 적 모션 수치 검증 (화면 없이 돈다).
## 실행: godot --headless --path . res://tools/probe_enemies.tscn
## (적 스크립트가 자동 로드 Progress·Sfx 등을 참조하므로 -s 스크립트 모드가 아니라 씬으로 돌린다 — 자동 로드가 함께 뜬다)
## 나무꾼(Visual 포함)을 만들어 예고→휘두름→회복→추격 한 사이클을 1/120초 단위로 손으로 돌리며
##  - 자세 채널(rot/sx/sy/dy/팔 각도)의 프레임 간 최대 변화량 (끊김이 없는지)
##  - 타격 정점(팔이 가장 빠른 순간 / 팔이 앞(각도 0)을 지나는 순간)이 strike_time 의 몇 %에 오는지
##  - windup_progress 가 0에서 시작해 1로 가는지 (경비병 돌진 예고처럼 길이를 늘린 경우 포함)
##  - 피격 충격 스프링이 되돌아오는지, 쓰러짐이 0.75초 동안 보이다 사라지는지
##  - 저스트 가드로 타격 도중 끊겼을 때 칼이 휘두름 끝각보다 더 깊이 들어가지 않는지 (parried)
##  - 쓰러짐·무너짐에서 발끝이 땅에 남고(발끝 축 회전) 머리가 땅 가까이 내려오는지, 일어날 때 발이 '툭' 옮겨 가지 않는지
##  - 쓰러짐의 끝(묘목 만들고 사라짐)이 물리 틱 기준 0.75초인지 (일시정지하면 함께 멈춘다)
## 를 찍는다. 자동 로드(Progress 등)는 없는 환경이므로 그것을 건드리는 경로(구원·무너짐)는 돌리지 않는다.
## (2026-10-20 부위 뼈대: 나무꾼은 EnemyRigVisual 이다. 자세 값은 뼈대에서 읽는다 — rot = 몸통 세상 각도, arm = 무기(칼날) 세상 각도,
##  dy = 엉덩이 높이(px). 칼날은 머리 위에서 앞 아래까지 예전 팔보다 크게(약 3.8 rad) 돌기 때문에 프레임 간 한계는 0.6 rad.
##  쓰러짐은 무릎이 꺾인 뒤 몸 전체가 앞발(또는 뒷발)을 축으로 넘어가 땅에 눕고 흩어져 사라진다(투명도 대신 dissolve).
##  경비병은 아직 예전 그림이라 예전 값을 그대로 읽는다.)

const STEP := 1.0 / 120.0

var _fail := 0


func _ready() -> void:
	print("[probe] 시작 (step %.4f초)" % STEP)
	_probe_woodcutter_cycle()
	_probe_hit_spring()
	_probe_death()
	_probe_guard_charge()
	_probe_turn()
	_probe_parry_mid_strike()
	_probe_fall_feet()
	_probe_broken_feet()
	_probe_fall_finish()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _spawn(path: String) -> EnemyBase:
	var scene: PackedScene = load(path)
	var e: EnemyBase = scene.instantiate()
	e.gravity = 0.0            # 바닥이 없는 시험 공간: 떨어지지 않게
	add_child(e)
	e.set_physics_process(false)
	var vis: Node2D = e.get_node("Visual")
	vis.set_process(false)
	e.player = null
	e.facing = 1
	e._timer = 999.0           # 순찰로 넘어가지 않게
	return e


func _step(e: EnemyBase, n: int, rec: Callable = Callable()) -> void:
	var vis: Node2D = e.get_node("Visual")
	for i in n:
		e._physics_process(STEP)
		vis._process(STEP)
		if rec.is_valid():
			rec.call()


static func _is_rig(vis: Node) -> bool:
	return vis is EnemyRigVisual


func _pose(vis: Node2D) -> Dictionary:
	if _is_rig(vis):
		var rig: PartRig = vis.rig
		var gs: float = rig.game_scale * float(vis.art_scale)
		var w := rig.bone_index("weapon")
		var t := rig.bone_index("torso")
		# 칼날 방향(세상, 오른쪽을 보는 기준): 뼈 축(+Y)의 각도. 앞 수평 = 0, 아래 = +π/2, 머리 위 = −π/2
		var blade := (rig.body_xf * rig.xf[w]).basis_xform(Vector2(0, 1)).angle()
		return {
			"rot": rig.world_rot(t) + rig.body_xf.get_rotation(),
			"sx": absf(rig.scale.x),
			"sy": rig.scale.y,
			"dy": rig.root_pos.y * gs,
			"arm": blade,
			"mir": vis._mir.v,
		}
	var arm := 0.0
	if vis._arm_bone:
		arm = vis._arm_bone.rotation
	return {
		"rot": vis._sprite.rotation,
		"sx": absf(vis._sprite.scale.x),
		"sy": vis._sprite.scale.y,
		"dy": vis._sprite.position.y,
		"arm": arm,
		"mir": vis._mir.v,
	}


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


## 나무꾼 한 사이클: 예고 → 휘두름 → 회복 → (추격/대기)
func _probe_woodcutter_cycle() -> void:
	var e := _spawn("res://scenes/enemies/woodcutter.tscn")
	var vis: Node2D = e.get_node("Visual")
	var rig_mode := _is_rig(vis)
	_step(e, 60)   # 0.5초 가만히 (자세 안정)
	var prev := _pose(vis)
	var max_d := {"rot": 0.0, "sx": 0.0, "sy": 0.0, "dy": 0.0, "arm": 0.0}
	var where := {}
	var t := 0.0
	var strike_t0 := -1.0
	var strike_len := 0.0
	var arm_speed_peak := 0.0
	var arm_speak_t := -1.0
	var arm_cross_t := -1.0
	var wp_first := -1.0
	var wp_last := 0.0
	var states := []
	var last_state := -1
	var rows := []
	e._begin_windup()
	var done := false
	while not done and t < 3.0:
		e._physics_process(STEP)
		vis._process(STEP)
		t += STEP
		var p := _pose(vis)
		if e.state != last_state:
			states.append(e.state_name())
			last_state = e.state
			if e.state == EnemyBase.State.STRIKE:
				strike_t0 = t
				strike_len = e.strike_time
		if e.state == EnemyBase.State.WINDUP:
			if wp_first < 0.0:
				wp_first = e.windup_progress
			wp_last = e.windup_progress
		for k in max_d.keys():
			var d: float = absf(wrapf(p[k] - prev[k], -PI, PI)) if k in ["rot", "arm"] else absf(p[k] - prev[k])
			if d > max_d[k]:
				max_d[k] = d
				where[k] = "%s %.3f초" % [e.state_name(), t]
		if strike_t0 >= 0.0 and e.state == EnemyBase.State.STRIKE:
			var w := absf(wrapf(p["arm"] - prev["arm"], -PI, PI)) / STEP
			if w > arm_speed_peak:
				arm_speed_peak = w
				arm_speak_t = t - strike_t0
			# 뼈대: 칼날이 '머리 위(−π/2)'를 넘어 앞으로 넘어가는 순간 / 예전 그림: 팔 각도 0
			var c_prev: float = prev["arm"] + PI * 0.5 if rig_mode else prev["arm"]
			var c_now: float = p["arm"] + PI * 0.5 if rig_mode else p["arm"]
			if arm_cross_t < 0.0 and signf(c_prev) != signf(c_now) and c_prev != 0.0 and absf(c_now - c_prev) < PI:
				arm_cross_t = t - strike_t0
		if int(t * 120.0) % 4 == 0:
			rows.append("%.3f %-6s wp=%.2f pp=%.2f rot=%+.3f sx=%.3f sy=%.3f dy=%+.1f arm=%+.3f" % [t, e.state_name(), e.windup_progress, e.phase_progress, p["rot"], p["sx"], p["sy"], p["dy"] - 0.0, p["arm"]])
		prev = p
		if e.state in [EnemyBase.State.CHASE, EnemyBase.State.IDLE, EnemyBase.State.BACKSTEP] and strike_t0 >= 0.0 and t > strike_t0 + 0.9:
			done = true
	print("[probe] 나무꾼 상태 흐름: %s" % ", ".join(states))
	for r in rows:
		print("[probe]   " + r)
	print("[probe] 프레임 간 최대 변화: rot %.4f (%s) / sx %.4f (%s) / sy %.4f (%s) / dy %.2f (%s) / arm %.4f (%s)" % [
		max_d["rot"], where.get("rot", "-"), max_d["sx"], where.get("sx", "-"), max_d["sy"], where.get("sy", "-"), max_d["dy"], where.get("dy", "-"), max_d["arm"], where.get("arm", "-")])
	_check(max_d["rot"] < 0.09 and max_d["sx"] < 0.04 and max_d["sy"] < 0.04 and max_d["dy"] < 4.0, "자세가 프레임 사이에 '툭' 뛰지 않는다 (rot<0.09, sx/sy<0.04, dy<4px)")
	var arm_lim := 0.6 if rig_mode else 0.4
	_check(max_d["arm"] < arm_lim, "팔(칼날) 각도도 프레임 사이에 뛰지 않는다 (<%.1f rad/프레임 = 1/120초)" % arm_lim)
	if rig_mode:
		print("[probe] (뼈대: rot = 몸통 세상 각도, arm = 칼날 세상 각도, dy = 엉덩이 높이 px, 앞을 지남 = 칼날이 머리 위를 넘어 앞으로)")
	_check(wp_first >= 0.0 and wp_first < 0.05 and wp_last > 0.95, "windup_progress 0→1 (처음 %.3f, 마지막 %.3f)" % [wp_first, wp_last])
	var peak_pct := arm_speak_t / strike_len * 100.0 if strike_len > 0.0 else -1.0
	var cross_pct := arm_cross_t / strike_len * 100.0 if (strike_len > 0.0 and arm_cross_t >= 0.0) else -1.0
	print("[probe] 타격: strike_time %.2f초, 팔 최고 속도 %.1f rad/s 시각 %.1f%%, 팔이 앞(0)을 지나는 시각 %.1f%%" % [strike_len, arm_speed_peak, peak_pct, cross_pct])
	_check(peak_pct > 20.0 and peak_pct < 80.0, "팔 정점이 판정 구간(0~100%%) 가운데쯤 (%.0f%%)" % peak_pct)
	_check(cross_pct > 15.0 and cross_pct < 85.0, "팔이 앞을 지나는 순간도 판정 구간 안 (%.0f%%)" % cross_pct)
	e.free()


## 피격: 충격 스프링이 튕기고 되돌아오는지
func _probe_hit_spring() -> void:
	var e := _spawn("res://scenes/enemies/woodcutter.tscn")
	var vis: Node2D = e.get_node("Visual")
	_step(e, 60)
	var before := _pose(vis)
	var hit := HitData.make(10.0, 20.0, null, Vector2(380, -150))
	e.receive_hit(hit, null)
	var peak := 0.0
	var trail := []
	for i in 72:   # 0.6초
		e._physics_process(STEP)
		vis._process(STEP)
		var p := _pose(vis)
		peak = maxf(peak, absf(p["rot"] - before["rot"]))
		if i % 6 == 0:
			trail.append("%.3f" % p["rot"])
	var after := _pose(vis)
	print("[probe] 피격 뒤 rot: %s" % ", ".join(trail))
	_check(peak > 0.08, "맞은 순간 몸이 눈에 띄게 튕긴다 (최대 기울기 변화 %.3f)" % peak)
	_check(absf(after["rot"] - before["rot"]) < 0.08 and e.state != EnemyBase.State.HIT, "0.6초 뒤엔 거의 제자리로 돌아온다 (차이 %.3f, 상태 %s)" % [absf(after["rot"] - before["rot"]), e.state_name()])
	e.free()


## 쓰러짐: 즉시 사라지지 않고 0.75초 동안 기울며 투명해진다
func _probe_death() -> void:
	var e := _spawn("res://scenes/enemies/woodcutter.tscn")
	var vis: Node2D = e.get_node("Visual")
	_step(e, 30)
	e.hp = 1.0
	var got := {"died": false}
	e.died.connect(func(_p): got["died"] = true)
	e.receive_hit(HitData.make(5.0, 10.0, null), null)
	_check(got["died"], "died 신호는 맞은 즉시 난다")
	_check(e.state == EnemyBase.State.DEAD and e.collision_layer == 0 and not e.is_in_group("enemy"), "쓰러지는 즉시 DEAD·충돌 꺼짐·enemy 그룹에서 빠짐")
	var rig_mode := _is_rig(vis)
	var r0: float = _pose(vis)["rot"]
	var samples := []
	for i in 90:   # 0.75초
		e._physics_process(STEP)
		vis._process(STEP)
		if i % 15 == 14:
			var p := _pose(vis)
			var a: float = (1.0 - vis.rig.dissolve_amount()) if rig_mode else vis._sprite.modulate.a
			samples.append("%.2f초 rot=%.2f dy=%.0f a=%.2f" % [(i + 1) * STEP, p["rot"], p["dy"], a])
	print("[probe] 쓰러짐: %s" % " | ".join(samples))
	var r1: float = _pose(vis)["rot"]
	_check(is_instance_valid(e) and absf(wrapf(r1 - r0, -PI, PI)) > 0.6, "0.75초 동안 눈에 띄게 기울어졋다 (%.2f → %.2f)" % [r0, r1])
	var left: float = (1.0 - vis.rig.dissolve_amount()) if rig_mode else vis._sprite.modulate.a
	_check(left < 0.2, "끝에는 거의 사라짐 (남은 %.2f — 뼈대는 흩어져 사라짐)" % left)
	e.free()


## 경비병 돌진 예고(길이 ×1.3): windup_progress 가 0에서 시작하는지, charge→stuck 전환이 부드러운지
func _probe_guard_charge() -> void:
	var e := _spawn("res://scenes/enemies/guard.tscn")
	var vis: Node2D = e.get_node("Visual")
	_step(e, 30)
	e._mode = "charge"
	e._set_state(EnemyBase.State.WINDUP)
	e._timer = e.windup_time * 1.3
	e.windup_progress = 0.0
	e.anim_hint = "red"
	var first := -1.0
	var last := 0.0
	var neg := false
	var prev := _pose(vis)
	var max_d := 0.0
	var max_sy := 0.0
	var hints := []
	var t := 0.0
	# 예고 ×1.3 + 돌진(바닥이 없어 첫 틱에 박힘) + 박힘 stuck_time 까지 한 바퀴를 다 본다
	var cycle: float = e.windup_time * 1.3 + e.charge_time + e.stuck_time + 0.5
	while t < cycle and e.state != EnemyBase.State.CHASE:
		e._physics_process(STEP)
		vis._process(STEP)
		t += STEP
		if e.state == EnemyBase.State.WINDUP:
			if first < 0.0:
				first = e.windup_progress
			last = e.windup_progress
			if e.windup_progress < 0.0:
				neg = true
		var p := _pose(vis)
		max_d = maxf(max_d, absf(p["rot"] - prev["rot"]))
		max_sy = maxf(max_sy, absf(p["sy"] - prev["sy"]))
		prev = p
		if hints.is_empty() or hints[-1] != e.anim_hint:
			hints.append(e.anim_hint)
	print("[probe] 경비병 힌트 흐름: %s (예고 길이 %.3f초)" % [str(hints), e.windup_time * 1.3])
	_check(first >= 0.0 and not neg and last > 0.95, "경비병 돌진 예고 windup_progress 0→1, 음수 없음 (처음 %.3f 마지막 %.3f)" % [first, last])
	_check(hints.has("red") and hints.has("charge") and hints.has("stuck"), "red → charge → stuck 힌트가 그대로 나온다")
	_check(max_d < 0.12 and max_sy < 0.05, "charge→stuck 전환에서도 자세가 뛰지 않는다 (rot %.3f, sy %.3f)" % [max_d, max_sy])
	_check(e.state == EnemyBase.State.CHASE and e._timer > e.charge_cooldown - 0.05, "박힘이 풀리면 추격으로 돌아오고 charge_cooldown(%.1f초) 동안 쉰다 (상태 %s, 남은 %.2f)" % [e.charge_cooldown, e.state_name(), e._timer])
	e.free()


## 방향 전환: 한 프레임 뒤집기가 아니라 0을 지나며 몸을 튼다
func _probe_turn() -> void:
	var e := _spawn("res://scenes/enemies/woodcutter.tscn")
	var vis: Node2D = e.get_node("Visual")
	_step(e, 30)
	var m0: float = _pose(vis)["mir"]
	e.facing = -e.facing
	var passed_mid := false
	var max_d := 0.0
	var prev := m0
	var frames := 0
	for i in 60:
		e._physics_process(STEP)
		vis._process(STEP)
		var m: float = _pose(vis)["mir"]
		if absf(m) < 0.5:
			passed_mid = true
		max_d = maxf(max_d, absf(m - prev))
		prev = m
		frames += 1
		if signf(m) != signf(m0) and absf(m) > 0.9:
			break
	print("[probe] 방향 전환: %d 프레임(%.3f초) 걸려 뒤집힘, 프레임 간 최대 변화 %.3f" % [frames, frames * STEP, max_d])
	_check(passed_mid and max_d < 0.5 and frames >= 6, "뒤집힘이 여러 프레임에 걸쳐 0을 지난다")
	e.free()


## 저스트 가드로 타격 도중 RECOVER 로 점프: 팔이 휘두르던 속도를 이어 받아 '더 깊이 들어갔다 올라오는' 모양이 되지 않는지
## (휘두름 끝각 ARM_FRONT 를 앞쪽으로 넘어가면 안 된다)
func _probe_parry_mid_strike() -> void:
	for q_target in [0.05, 0.3, 0.55]:
		var e := _spawn("res://scenes/enemies/woodcutter.tscn")
		var vis: Node2D = e.get_node("Visual")
		_step(e, 60)
		var forward := 1.0 if vis.art_faces_right else -1.0
		e._begin_windup()
		var t := 0.0
		while (e.state != EnemyBase.State.STRIKE or e.phase_progress < q_target) and t < 3.0:
			_step(e, 1)
			t += STEP
		if _is_rig(vis):
			# 뼈대: 칼날 세상 각도(앞 수평 0, 아래 +). 받아친 뒤 칼날이 '휘두름 끝'(막히지 않았을 때 가장 깊은 각도)보다 더 내려가면 안 된다.
			var at := _deep_angle(_pose(vis)["arm"])
			e.on_just_guarded(null, 20.0)
			var deepest_r := at
			var trail_r := []
			for i in 72:
				_step(e, 1)
				var a := _deep_angle(_pose(vis)["arm"])
				deepest_r = maxf(deepest_r, a)
				if i % 6 == 0:
					trail_r.append("%.2f" % a)
			var limit := _rig_strike_end()
			print("[probe] 저스트 가드 q=%.2f: 가드 순간 칼날 %.2f → 0.6초 동안 가장 깊이 %.2f (막히지 않은 휘두름 끝 %.2f) | %s" % [q_target, at, deepest_r, limit, ", ".join(trail_r)])
			_check(deepest_r <= limit + 0.05, "받아쳐진 칼이 휘두름 끝(%.2f)보다 더 깊이 들어가지 않는다 (q=%.2f, 최대 %.2f)" % [limit, q_target, deepest_r])
			e.free()
			continue
		var arm_at: float = vis._arm.v
		var vel_at: float = vis._arm.vel
		e.on_just_guarded(null, 20.0)
		var deepest := 0.0   # 앞쪽(forward)으로 가장 멀리 간 팔 각도
		var trail := []
		for i in 72:
			_step(e, 1)
			deepest = maxf(deepest, vis._arm.v * forward)
			if i % 6 == 0:
				trail.append("%.2f" % (vis._arm.v * forward))
		print("[probe] 저스트 가드 q=%.2f: 가드 순간 팔 %.2f(속도 %.1f rad/s) → 0.6초 동안 앞쪽 최대 %.2f (끝각 %.2f) | %s" % [q_target, arm_at * forward, vel_at * forward, deepest, vis.ARM_FRONT, ", ".join(trail)])
		_check(deepest <= vis.ARM_FRONT + 0.02, "받아쳐진 칼이 휘두름 끝각(%.2f)보다 더 깊이 들어가지 않는다 (q=%.2f, 최대 %.2f)" % [vis.ARM_FRONT, q_target, deepest])
		e.free()


## 뼈대 나무꾼이 막히지 않고 한 번 휘둘렀을 때 칼날이 가장 깊이 내려간 각도 (받아치기 비교 기준)
func _rig_strike_end() -> float:
	var e := _spawn("res://scenes/enemies/woodcutter.tscn")
	var vis: Node2D = e.get_node("Visual")
	_step(e, 60)
	e._begin_windup()
	var deepest := -INF
	var t := 0.0
	var struck := false
	while t < 2.5:
		_step(e, 1)
		t += STEP
		if e.state == EnemyBase.State.STRIKE:
			struck = true
		if struck:
			deepest = maxf(deepest, _deep_angle(_pose(vis)["arm"]))
		if struck and e.state in [EnemyBase.State.CHASE, EnemyBase.State.IDLE, EnemyBase.State.BACKSTEP]:
			break
	e.free()
	return deepest


## 칼날 세상 각도(앞 수평 0, 아래 +)를 '휘두름 깊이' 순서로 편다: 등 뒤 아래(약 150도)를 자르는 자리로 삼아
## 머리 위 뒤(−2.5) < 머리 위(−1.57) < 앞 수평(0) < 앞 아래(+) 가 되게 (−3.68, 2.6] 로 옮긴다.
## (예전엔 −π/2 아래에 2π 를 더한 뒤 π 로 잘라서 기준이 늘 3.14 가 되어 검사가 실패할 수 없었다 — 2026-10-20 검수)
static func _deep_angle(a: float) -> float:
	const CUT := 2.6
	return fposmod(a - CUT, TAU) + CUT - TAU


## 그림의 발끝·머리 위치 (Visual 로컬 좌표). 땅은 y = hurt_height*0.5.
## 뼈대: [앞발 발바닥, 머리 꼭대기] — 앞으로 넘어질 때 축이 되는 발.
func _feet_head(vis: Node2D) -> Array:
	if _is_rig(vis):
		var rig: PartRig = vis.rig
		var m: RigMotion = vis.motion
		var leg: RigMotion.Leg = m.legs[0]
		# 세상 자리로 (딛은 발은 세상에 고정 — 몸이 밀려 미끄러져도 발은 그 자리)
		var e: Node2D = vis.get_parent()
		var foot := e.global_position + rig.position + rig.scale * ((rig.body_xf * rig.xf[leg.foot] * leg.sole) * rig.game_scale)
		var hi := rig.bone_index("head")
		var top := INF
		var top_p := Vector2.ZERO
		for q in rig.hulls[hi]:
			var p := rig.body_xf * rig.xf[hi] * q
			if p.y < top:
				top = p.y
				top_p = p
		var head := e.global_position + rig.position + rig.scale * (top_p * rig.game_scale)
		return [foot, head]
	var spr: Sprite2D = vis._sprite
	var half_h := spr.texture.get_height() * 0.5
	# foot_offset 은 원본(1536×1024) px 이므로 그림 px 로는 × art_pixel_scale
	var foot_local := Vector2(0, half_h - vis.foot_offset * vis.art_pixel_scale)
	var head_local := Vector2(0, -half_h + 60.0 * vis.art_pixel_scale)
	return [spr.transform * foot_local, spr.transform * head_local]


## 쓰러질 때 발은 땅에 남고 머리가 땅 가까이 내려오는지 (가운데 축으로 돌아 공중에 뜨지 않는지)
func _probe_fall_feet() -> void:
	var e := _spawn("res://scenes/enemies/woodcutter.tscn")
	var vis: Node2D = e.get_node("Visual")
	_step(e, 30)
	if _is_rig(vis):
		_probe_fall_feet_rig(e, vis)
		return
	var ground: float = e.hurt_height * 0.5
	var f0: Vector2 = _feet_head(vis)[0]
	e.hp = 1.0
	e.receive_hit(HitData.make(5.0, 10.0, null), null)
	var rows := []
	var foot_dev := 0.0
	var head_end := 0.0
	for i in 90:
		_step(e, 1)
		var fh := _feet_head(vis)
		if i >= 6:   # 맞은 순간의 충격 튕김은 빼고 잰다
			foot_dev = maxf(foot_dev, (fh[0] - f0).length())
		head_end = fh[1].y - ground
		if i % 15 == 14:
			rows.append("%.2f초 rot %.2f 발 (%+.0f, %+.0f) 머리 땅에서 %+.0f" % [(i + 1) * STEP, _pose(vis)["rot"], fh[0].x - f0.x, fh[0].y - f0.y, fh[1].y - ground])
	print("[probe] 쓰러짐 발·머리 (처음 발 y %.0f, 땅 %.0f): %s" % [f0.y, ground, " | ".join(rows)])
	_check(foot_dev < 9.0, "쓰러지는 동안 발끝이 제자리에 남는다 (최대 벗어남 %.1f px)" % foot_dev)
	_check(head_end > -40.0, "끝에는 머리가 땅 가까이 내려온다 (땅에서 %+.0f px)" % head_end)
	e.free()


## 뼈대의 '땅 닿는 점': 다리마다 발바닥과 무릎 관절 (세상 좌표). 무릎을 꿇으면 무릎이, 아니면 발바닥이 땅에 닿는다.
## 걸음으로 옮기는 중인 발(swing)은 땅에 닿은 점이 아니므로 아주 멀리(y 9999) 둔다.
func _rig_contacts(e: Node2D, vis: Node2D) -> Array:
	var rig: PartRig = vis.rig
	var m: RigMotion = vis.motion
	var out: Array = []
	var base: Vector2 = e.global_position + rig.position
	for leg in m.legs:
		var sole := base + rig.scale * ((rig.body_xf * rig.xf[leg.foot] * leg.sole) * rig.game_scale)
		out.append(Vector2(sole.x, 9999.0) if leg.swing else sole)
		if leg.lo >= 0:
			var knee := base + rig.scale * ((rig.body_xf * rig.xf[leg.lo].origin) * rig.game_scale)
			out.append(knee)
	return out


## 땅에 닿아 있는 점이 미끄러진 거리: 앞뒤 두 프레임 모두 땅 ±3px 안에 있던 점의 가로 이동을 점마다 쌓는다.
## (발을 들어 옮기는 '걸음'과 무릎을 꿇는 순간의 바뀜은 미끄러짐이 아니다 — 땅에 붙은 채 옆으로 끌린 거리만 잰다)
static func _slide(prev: Array, now: Array, ground: float, acc: PackedFloat32Array) -> void:
	for k in mini(prev.size(), now.size()):
		var a: Vector2 = prev[k]
		var b: Vector2 = now[k]
		if absf(a.y - ground) < 3.0 and absf(b.y - ground) < 3.0:
			acc[k] += absf(b.x - a.x)


## 뼈대 쓰러짐: 땅에 닿은 발·무릎이 끌리지 않고, 끝에는 머리(가운데)가 땅 가까이 내려온다 (가라앉지도 않는다)
func _probe_fall_feet_rig(e: EnemyBase, vis: Node2D) -> void:
	var rig: PartRig = vis.rig
	var ground: float = e.global_position.y + vis._floor_y
	e.hp = 1.0
	e.receive_hit(HitData.make(5.0, 10.0, null), null)
	var acc := PackedFloat32Array()
	acc.resize(8)
	var prev := _rig_contacts(e, vis)
	var rows := []
	var head_c := 0.0
	var low_min := INF
	var hi := rig.bone_index("head")
	for i in 84:   # 0.7초 (0.75초에 묘목이 된다)
		_step(e, 1)
		var now := _rig_contacts(e, vis)
		if i >= 4:
			_slide(prev, now, ground, acc)
		prev = now
		var c := Vector2.ZERO
		for q in rig.hulls[hi]:
			c += q
		c /= maxf(rig.hulls[hi].size(), 1.0)
		head_c = e.global_position.y + rig.position.y + ((rig.body_xf * rig.xf[hi] * c) * rig.game_scale * absf(rig.scale.y)).y - ground
		if i >= 60:
			low_min = minf(low_min, -rig.lowest_y(vis.motion._lock_bones) * rig.game_scale * rig.scale.y)
		if i % 14 == 13:
			rows.append("%.2f초 몸통 %.2f 머리(가운데) 땅에서 %+.0f" % [(i + 1) * STEP, _pose(vis)["rot"], head_c])
	var worst := 0.0
	for v in acc:
		worst = maxf(worst, v)
	print("[probe] 쓰러짐(뼈대): %s | 땅에 닿은 발·무릎이 끌린 거리 최대 %.1f px" % [" | ".join(rows), worst])
	_check(worst < 9.0, "쓰러지는 동안 땅에 닿은 발·무릎이 끌리지 않는다 (최대 %.1f px)" % worst)
	_check(head_c > -45.0, "끝에는 머리가 땅 가까이 내려온다 (머리 가운데가 땅에서 %+.0f px)" % head_c)
	_check(absf(low_min) < 4.0, "누운 몸이 땅에 닿아 있다 — 가라앉거나 뜨지 않음 (가장 낮은 점 %+.1f px)" % low_min)
	e.free()


## 무너짐(무릎)도 발이 미끄러지지 않는지, 일어날 때 발이 '툭' 옮겨 가지 않는지
func _probe_broken_feet() -> void:
	var e := _spawn("res://scenes/enemies/woodcutter.tscn")
	var vis: Node2D = e.get_node("Visual")
	_step(e, 30)
	if _is_rig(vis):
		_probe_broken_feet_rig(e, vis)
		return
	var f0: Vector2 = _feet_head(vis)[0]
	e.poise = e.max_poise - 1.0
	e.receive_hit(HitData.make(1.0, 10.0, null), null)
	_check(e.state == EnemyBase.State.BROKEN, "흐트러짐이 차서 무너졌다")
	var foot_dev := 0.0
	for i in 120:
		_step(e, 1)
		if i >= 12:
			foot_dev = maxf(foot_dev, (_feet_head(vis)[0] - f0).length())
	var fb: Vector2 = _feet_head(vis)[0]
	# 일어난다
	e._timer = 0.0
	var prev: Vector2 = fb
	var max_jump := 0.0
	for i in 60:
		_step(e, 1)
		var fp: Vector2 = _feet_head(vis)[0]
		max_jump = maxf(max_jump, (fp - prev).length())
		prev = fp
	print("[probe] 무너짐 발: 1초 동안 최대 벗어남 %.1f px (rot %.2f), 일어나는 0.5초 동안 프레임 간 발 이동 최대 %.1f px, 상태 %s" % [foot_dev, _pose(vis)["rot"], max_jump, e.state_name()])
	_check(foot_dev < 12.0, "무너진 동안 발이 미끄러지지 않는다")
	_check(max_jump < 6.0, "일어날 때 발이 프레임 사이에 '툭' 옮겨 가지 않는다")
	e.free()


## 뼈대 무너짐: 땅에 닿은 발·무릎이 끌리지 않고, 일어날 때 땅 닿는 점이 프레임 사이에 '툭' 옮겨 가지 않는다
func _probe_broken_feet_rig(e: EnemyBase, vis: Node2D) -> void:
	var ground: float = e.global_position.y + vis._floor_y
	e.poise = e.max_poise - 1.0
	e.receive_hit(HitData.make(1.0, 10.0, null), null)
	_check(e.state == EnemyBase.State.BROKEN, "흐트러짐이 차서 무너졌다")
	var acc := PackedFloat32Array()
	acc.resize(8)
	var prev := _rig_contacts(e, vis)
	for i in 120:
		_step(e, 1)
		var now := _rig_contacts(e, vis)
		if i >= 6:
			_slide(prev, now, ground, acc)
		prev = now
	var worst := 0.0
	for v in acc:
		worst = maxf(worst, v)
	e._timer = 0.0   # 일어난다
	var max_jump := 0.0
	var acc2 := PackedFloat32Array()
	acc2.resize(8)
	for i in 60:
		_step(e, 1)
		var now := _rig_contacts(e, vis)
		_slide(prev, now, ground, acc2)
		for k in mini(prev.size(), now.size()):
			if absf((now[k] as Vector2).y - ground) < 3.0 and absf((prev[k] as Vector2).y - ground) < 3.0:
				max_jump = maxf(max_jump, absf((now[k] as Vector2).x - (prev[k] as Vector2).x))
		prev = now
	print("[probe] 무너짐 발(뼈대): 1초 동안 땅에 닿은 발·무릎이 끌린 거리 최대 %.1f px, 일어나는 0.5초 동안 땅 닿은 점의 프레임 간 이동 최대 %.1f px, 상태 %s" % [worst, max_jump, e.state_name()])
	_check(worst < 12.0, "무너진 동안 발이 미끄러지지 않는다")
	_check(max_jump < 6.0, "일어날 때 발이 프레임 사이에 '툭' 옮겨 가지 않는다")
	e.free()


## 쓰러짐의 끝(묘목 만들고 사라짐)은 물리 틱이 재므로, 물리가 멈추면(일시정지) 함께 멈추고 0.75초 뒤에 끝난다
func _probe_fall_finish() -> void:
	var e := _spawn("res://scenes/enemies/woodcutter.tscn")
	_step(e, 10)
	e.hp = 1.0
	e.receive_hit(HitData.make(5.0, 10.0, null), null)
	var sprouts_before := get_child_count()
	_step(e, 60)   # 0.5초
	_check(not e.is_queued_for_deletion() and get_child_count() == sprouts_before, "0.5초엔 아직 쓰러지는 중 (묘목 없음)")
	_step(e, 36)   # 0.8초
	_check(e.is_queued_for_deletion() and get_child_count() == sprouts_before + 1, "0.75초가 지나면 묘목이 생기고 사라진다 (자식 %d → %d)" % [sprouts_before, get_child_count()])
	# 쓰러지는 중에 방을 떠나는 경우: 기다리는 코루틴이 없으니 그냥 함께 사라진다
	var e2 := _spawn("res://scenes/enemies/woodcutter.tscn")
	_step(e2, 10)
	e2.hp = 1.0
	e2.receive_hit(HitData.make(5.0, 10.0, null), null)
	_step(e2, 24)
	e2.free()
	_check(true, "쓰러지는 중 free 해도 오류 없음 (await 없음)")
	for c in get_children():
		if c is Node2D and not (c is EnemyBase):
			c.free()

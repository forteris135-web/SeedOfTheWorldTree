extends Node2D
## 무쇠 펌프 부위 뼈대 검사 (화면 없이): godot --headless --path . res://tools/probe_pump_rig.tscn
## 실제 보스 장면(iron_pump.tscn)을 바닥 위에 세우고 보스 논리를 1/60초씩 직접 돌리며(판정·시간은 게임과 같다) 그림을 잰다:
##  1) 대기·걷기·피스톤·분사·빨아들이기(+물기 되받기)·휘청·장갑 깨짐·2페이즈 공격: 디딘 발(걸음 중이 아닌 발)의 발바닥이 땅 ±4px,
##     몸(흡입 팔·늘어진 천 뺌)이 땅 아래로 6px 넘게 들어가지 않음, 흡입 팔이 땅에 파고들지 않음, NaN 없음
##  2) 피스톤: 실행(판정이 켜지는) 순간 흡입 팔 끝이 앞 땅에 닿아 있다 (팔의 가장 낮은 점이 땅 위 24px 안)
##  3) 분사: 한 발마다 대포 끝이 수액 방울이 생기는 자리(보스 논리의 노즐 자리) 90px 안
##  4) 쓰러짐: 끝에 몸의 가장 낮은 점이 땅 ±6px, 핵 높이가 서 있을 때의 60% 아래, 꼭대기가 서 있을 때의 75% 아래 (정말 엎드렸다)
##  5) 멈춘 펌프(PumpRemains)가 쓰러진 자세를 그대로 이어받는다
##  6) 그림 한 프레임 비용
## 실패가 하나라도 있으면 종료 코드 1.

const STEP := 1.0 / 60.0
const FLOOR_Y := 1000.0
const FEET_TOL := 4.0
const SINK_TOL := 6.0

var _fail := 0
var _boss: IronPump
var _vis
var _player: Player


func _ready() -> void:
	print("[probe] 시작: 무쇠 펌프 부위 뼈대")
	var floor := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20000, 400)
	cs.shape = rect
	cs.position = Vector2(0, FLOOR_Y + 200)
	floor.add_child(cs)
	add_child(floor)
	await get_tree().process_frame
	var stand := await _seq_stand()
	for name in ["walk", "piston", "spray", "suck", "bite_parry", "stagger", "broken", "p2"]:
		await _seq(name)
	await _seq_dead(stand)
	await _seq_reset()
	await _cost()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _spawn() -> void:
	if is_instance_valid(_boss):
		_boss.free()
	if is_instance_valid(_player):
		_player.free()
	for n in get_tree().get_nodes_in_group("projectile"):
		n.free()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.set_process_unhandled_input(false)
	_boss = (load("res://scenes/bosses/iron_pump.tscn") as PackedScene).instantiate()
	_boss.position = Vector2(0, FLOOR_Y)
	add_child(_boss)
	_boss.arena = Rect2(-1800, FLOOR_Y - 900, 3600, 900)
	_boss.ground_y = FLOOR_Y
	_boss.set_physics_process(false)
	_vis = _boss.get_node("Sprite")
	_vis.set_process(false)
	await get_tree().process_frame
	_boss.start_fight(_player)
	_boss.global_position = Vector2(0, FLOOR_Y)
	_player.global_position = Vector2(-430, FLOOR_Y - 2)
	_step(int(2.4 / STEP))
	_boss._set_state(IronPump.State.IDLE)
	_boss._timer = 999.0
	_step(30)


func _step(n := 1) -> void:
	for i in n:
		_boss._physics_process(STEP)
		_vis._process(STEP)


## [디딘 발 최대 어긋남, 몸이 땅 아래로 들어간 깊이, 팔의 가장 낮은 점, NaN?] (게임 px, 땅 0·아래 +)
func _measure() -> Array:
	var rig: PartRig = _vis.rig
	var m: RigMotion = _vis.motion
	var k: float = _vis._k
	var oy: float = rig.position.y
	var ys := m.sole_ys()
	var feet := 0.0
	for i in ys.size():
		if not m.legs[i].swing:
			feet = maxf(feet, absf(ys[i] * k + oy))
	var nan := false
	for x in rig.xf:
		if is_nan(x.origin.x) or is_nan(x.origin.y):
			nan = true
	var sink := rig.lowest_y(m._lock_bones) * k + oy
	var arm := rig.lowest_y(PackedInt32Array([rig.bone_index("arm_lo"), rig.bone_index("arm_up")])) * k + oy
	return [feet, sink, arm, nan]


func _seq_stand() -> Dictionary:
	await _spawn()
	var r := _measure()
	var pp: Dictionary = _vis.probe_pose()
	var out := {"core": -(pp["core"] as Vector2).y + FLOOR_Y, "top": -float(pp["top"])}
	_check(float(r[0]) <= FEET_TOL and float(r[1]) <= SINK_TOL and not r[3], "대기: 발바닥 %.1fpx, 몸 깊이 %+.1fpx (핵 높이 %.0f, 키 %.0f)" % [r[0], r[1], out["core"], out["top"]])
	return out


func _seq(name: String) -> void:
	await _spawn()
	var length := 2.5
	match name:
		"walk":
			_player.global_position = Vector2(-1500, FLOOR_Y - 2)
			length = 3.0
		"piston", "spray", "suck", "bite_parry":
			_boss._cycle = {"piston": 0, "spray": 1, "suck": 2, "bite_parry": 2}[name]
			_boss._timer = 0.0
			length = 3.4
		"stagger":
			_boss.hp = _boss.max_hp * 0.45
			_boss.receive_hit(HitData.make(1.0, 0.0, _player), null)
			length = 1.2
		"broken":
			_boss.poise = _boss.max_poise - 1.0
			_boss.receive_hit(HitData.make(1.0, 60.0, _player), null)
			length = 5.6
		"p2":
			_boss.hp = _boss.max_hp * 0.45
			_boss.receive_hit(HitData.make(1.0, 0.0, _player), null)
			_boss._timer = 0.6
			length = 9.0
	var feet := 0.0
	var sink := -INF
	var arm := -INF
	var nan := false
	var slam_arm := INF
	var acc := {"err": 0.0, "shots": 0}   # 람다는 지역 값을 복사해 잡으므로 사전에 모은다
	var worst_bone := ""
	var parried := false
	var prev_phase := ""
	var cb := func() -> void:
		acc["shots"] = int(acc["shots"]) + 1
		# 보스 논리의 노즐 자리 (iron_pump.gd _spray 와 같은 식)
		var ahead := (_player.global_position.x - _boss.global_position.x) * _boss.facing
		var reach := clampf(ahead - _boss.spray_min_gap, 60.0, 250.0)
		var origin := _boss.global_position + Vector2(_boss.facing * reach, -120.0)
		acc["err"] = maxf(float(acc["err"]), ((_vis.probe_pose()["muzzle"] as Vector2) - origin).length())
	_boss.shot.connect(cb)
	var t := 0.0
	while t < length:
		if name == "bite_parry" and not parried and _boss.state == IronPump.State.SUCK and _boss._bit:
			parried = true
			_boss.on_just_guarded(_player, 45.0)
		if name in ["suck", "bite_parry"] and _boss.state == IronPump.State.SUCK:
			_player.global_position = Vector2(-430, FLOOR_Y - 2)   # 끌려가도 제자리 (그림 겨눔만 본다)
		_step()
		t += STEP
		var r := _measure()
		feet = maxf(feet, r[0])
		if float(r[1]) > sink:
			sink = r[1]
			worst_bone = "%s %.2f초 %s" % [_vis.probe_pose()["low_bone"], t, _boss.state_name()]
		arm = maxf(arm, r[2])
		nan = nan or r[3]
		if _boss.state == IronPump.State.PISTON and _boss.attack_phase == "active" and prev_phase == "startup":
			slam_arm = -float(r[2])   # 땅 위 높이
		prev_phase = _boss.attack_phase if _boss.state == IronPump.State.PISTON else prev_phase
	_boss.shot.disconnect(cb)
	_check(feet <= FEET_TOL and sink <= SINK_TOL and arm <= SINK_TOL and not nan,
		"%s: 디딘 발바닥 최대 %.1fpx, 몸 깊이 최대 %+.1fpx (%s), 흡입 팔 깊이 최대 %+.1fpx%s" % [name, feet, sink, worst_bone, arm, " NaN!" if nan else ""])
	if name == "piston":
		_check(slam_arm <= 24.0, "피스톤: 판정이 켜지는 순간 흡입 팔 끝이 땅에 닿아 있다 (팔의 가장 낮은 점 땅 위 %.1fpx)" % slam_arm)
	if name == "spray":
		_check(int(acc["shots"]) == 3 and float(acc["err"]) <= 90.0, "분사: %d발, 대포 끝과 수액 방울 생기는 자리 거리 최대 %.0fpx" % [acc["shots"], acc["err"]])
	if name == "bite_parry":
		_check(parried, "빨아들이기: 물기가 나왔고 되받을 수 있었다 (되받음 %s)" % parried)


func _seq_dead(stand: Dictionary) -> void:
	await _spawn()
	_boss.hp = 1.0
	_boss.receive_hit(HitData.make(5.0, 0.0, _player), null)
	var feet := 0.0
	var nan := false
	var t := 0.0
	while t < 3.0:
		_step()
		t += STEP
		if t > 2.4:
			var r := _measure()
			feet = maxf(feet, r[0])
			nan = nan or r[3]
	var r2 := _measure()
	var pp: Dictionary = _vis.probe_pose()
	var core := -(pp["core"] as Vector2).y + FLOOR_Y
	var top := -float(pp["top"])
	_check(absf(float(r2[1])) <= 6.0 and feet <= 8.0 and not nan, "쓰러짐: 누운 몸의 가장 낮은 점 %+.1fpx (땅 ±6), 발바닥 %.1fpx" % [r2[1], feet])
	_check(core <= float(stand["core"]) * 0.6 and top <= float(stand["top"]) * 0.75,
		"쓰러짐: 정말 엎드렸다 — 핵 높이 %.0f (서 있을 때 %.0f 의 %.0f%%), 꼭대기 %.0f (서 있을 때 %.0f 의 %.0f%%)" % [core, stand["core"], core / float(stand["core"]) * 100.0, top, stand["top"], top / float(stand["top"]) * 100.0])
	# 멈춘 펌프가 같은 자세를 이어받는다
	var remains: Node2D = Node2D.new()
	remains.set_script(load("res://scripts/bosses/iron_pump_remains.gd"))
	add_child(remains)
	await get_tree().process_frame
	remains.match_pose(_vis)
	var a: PartRig = _vis.rig
	var b: PartRig = remains.rig
	var same := a.rot.size() == b.rot.size()
	for i in mini(a.rot.size(), b.rot.size()):
		if absf(a.rot[i] - b.rot[i]) > 0.0001:
			same = false
	same = same and a.root_pos.is_equal_approx(b.root_pos)
	_check(same, "멈춘 펌프가 쓰러진 자세(관절 %d개)를 그대로 이어받는다" % a.rot.size())
	remains.free()


## 소녀가 쓰러져 싸움이 처음으로 돌아갔다가(reset_fight) 다시 시작해도 그림이 바로 제자리에 선다 (오른쪽을 보다 죽어도 왼쪽으로 등장)
func _seq_reset() -> void:
	await _spawn()
	_player.global_position = Vector2(600, FLOOR_Y - 2)
	_boss._timer = 0.3
	_step(int(2.0 / STEP))   # 소녀 쪽으로 돌아서 피스톤 하나
	var turned: bool = _boss.facing == 1
	_boss.reset_fight()
	_step(10)
	_boss.start_fight(_player)
	_step(2)
	var face: float = _vis.probe_pose()["face"]
	var start_facing := float(_boss.facing)
	_step(int(2.4 / STEP))
	var r := _measure()
	_check(turned and absf(face - start_facing) < 0.01 and float(r[0]) <= FEET_TOL and float(r[1]) <= SINK_TOL and not r[3],
		"다시 시작: 돌아섰던 펌프(%s)가 바로 보스 방향으로 등장 (보는 쪽 %.2f), 발바닥 %.1fpx, 몸 깊이 %+.1fpx" % [turned, face, r[0], r[1]])


func _cost() -> void:
	await _spawn()
	_boss._timer = 0.0
	var t0 := Time.get_ticks_usec()
	var n := 240
	for i in n:
		_vis._process(STEP)
	var us := float(Time.get_ticks_usec() - t0) / n
	print("[probe] 무쇠 펌프 그림 한 프레임 비용: %.0f µs (이 맥 기준 — 아이폰 11 Pro 는 약 2~3배)" % us)
	_check(us < 1500.0, "그림 한 프레임 비용이 1.5ms 미만 (%.0f µs)" % us)

extends Node
## 등불 기사 부위 뼈대 검사 (화면 없이): godot --headless --path . res://tools/probe_knight_rig.tscn
## 진짜 보스 씬을 바닥 위에 세우고 1/60초씩 직접 돌리며(판정·시간은 실제와 같다) 모든 상태에서 그림을 잰다:
##  1) 발: 땅에 서 있는 동안 디딘 발바닥이 땅 ±4px (걸음 중엔 가장 낮은 발, 무릎 꿇은 다리는 뺀다)
##  2) 몸이 땅 아래로 4px 넘게 들어가지 않는다 (다리·몸통·머리·팔). 창은 땅에 박히지 않는다 (짚기·손을 떠난 창은 땅에 닿는 게 맞다)
##  3) 몸 높이(엉덩이)가 한 프레임에 크게 뛰지 않는다 (12px 아래 — '툭' 내려앉음 없음), 창 각도가 한 프레임에 0.7rad 넘게 뛰지 않는다
##  4) 쓰러짐 끝: 정말 누웠다 (몸통 가운데 ≤ 키의 30%, 머리 가운데 ≤ 35%), 가장 낮은 몸 점이 땅 ±6px, 창·등불도 땅 위에 눕는다
##  5) 정화: 무릎 꿇은 채 몸을 일으킨다 (머리 가운데가 키의 45% 넘게), 투구 등불이 밝아진다
##  6) 2페이즈 자세는 1페이즈보다 낮고 앞으로 숙인다
##  7) NaN 없음, 한 프레임 비용
## 실패가 하나라도 있으면 종료 코드 1.

const DT := 1.0 / 60.0
const FEET_TOL := 4.0
const SINK_TOL := 4.0
const HIP_JUMP := 12.0
var _fail := 0
var _player: Player


func _ready() -> void:
	var fb := StaticBody2D.new()
	fb.collision_layer = 1
	var cs := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(20000, 200)
	cs.shape = r
	fb.add_child(cs)
	fb.position = Vector2(0, 1100)
	add_child(fb)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[probe] 시작: 등불 기사 부위 뼈대")
	for sc in ["idle", "march", "thrust", "flame", "slam", "throw", "wave", "combo3", "charge", "spin", "stagger", "parry", "broken", "intro", "march_p2", "thrust_p2", "spin_p2"]:
		_scenario(sc)
	_fallen(false)
	_fallen(true)
	_phase2_posture()
	_cost()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _spawn(p2: bool) -> LanternKnight:
	var b: LanternKnight = (load("res://scenes/bosses/lantern_knight.tscn") as PackedScene).instantiate()
	add_child(b)
	b.set_physics_process(false)
	b.get_node("Sprite").set_process(false)
	b.visible = true
	b.arena = Rect2(-1500, 0, 3000, 1000)
	b.ground_y = 1000.0
	b.global_position = Vector2(0, 1000)
	b.facing = 1
	b.player = null
	if p2:
		b.phase = 2
		b.hp = b.max_hp * 0.4
	b._set_state(LanternKnight.State.MARCH)
	b._timer = 999.0
	return b


func _step(b: LanternKnight) -> void:
	b._physics_process(DT)
	b.get_node("Sprite")._process(DT)


## 한 상태를 돌리며 잰다
func _scenario(name: String) -> void:
	var p2 := name.ends_with("_p2")
	var base := name.trim_suffix("_p2")
	var b := _spawn(p2)
	var vis = b.get_node("Sprite")
	for i in 40:
		_step(b)
	var frames := 90
	var attack := ""
	match base:
		"march":
			_player.global_position = Vector2(2500, 1000)
			b.player = _player
			frames = 150
		"thrust", "flame", "slam", "throw", "wave", "combo3", "charge", "spin":
			_player.global_position = Vector2(400 if base != "charge" else 1300, 940)
			b.player = _player
			attack = base
			b.force_attack(LanternKnight.State[base.to_upper()])
			frames = 420
		"stagger":
			b.hp = b.max_hp * 0.45
			b.receive_hit(HitData.make(1.0, 0.0, null), null)
			frames = 70
		"parry":
			b.force_attack(LanternKnight.State.THRUST)
			frames = 240
		"broken":
			b.receive_hit(HitData.make(1.0, b.max_poise, null), null)
			frames = 220
		"intro":
			b._set_state(LanternKnight.State.WAIT)
			for i in 60:
				_step(b)
			b._set_state(LanternKnight.State.INTRO)
			b._timer = 2.4
			frames = 170
	var k: float = vis._k
	var rig: PartRig = vis.rig
	var m: RigMotion = vis.motion
	var body := PackedInt32Array()
	for i in rig.names.size():
		var nm := rig.names[i]
		if nm.begins_with("leg_") or nm.begins_with("foot_") or nm.begins_with("arm_") or nm in ["torso", "head"]:
			body.append(i)
	var wi := rig.bone_index("weapon")
	var worst_feet := 0.0
	var feet_at := ""
	var worst_sink := -INF
	var sink_at := ""
	var worst_spear := -INF
	var spear_at := ""
	var worst_hip := 0.0
	var hip_at := ""
	var worst_wrot := 0.0
	var wrot_at := ""
	var nan := false
	var prev_y := float(vis.probe_pose()[2])
	var prev_w: float = vis._weapon_bone.rotation
	var done_at := -1
	for f in frames:
		_step(b)
		if base == "parry" and b.attack_phase == "active" and b.anim_hint != "stagger":
			b.on_just_guarded(null, 10.0)
			b.hitbox.landed.emit("just_guard", null)
		if attack != "" and b.state == LanternKnight.State.MARCH:
			b._timer = 999.0
			if done_at < 0:
				done_at = f
			if f > done_at + 40:
				break
		var tag := "%.2f %s/%s" % [f * DT, b.state_name(), b.attack_phase]
		# 발
		if b.is_on_floor():
			var ys := m.sole_ys()
			var dev := 0.0
			var lo := INF
			var any_swing := false
			for li in ys.size():
				var leg: RigMotion.Leg = m.legs[li]
				# 무릎 꿇은 다리와 꿇기에서 일어서는 중인 다리(채널이 0 으로 내려가는 중)는 뺀다 — 일어설 때 발이 잠깐 들린다
				if float(m.fin.get(leg.k_kneel, 0.0)) > 0.02:
					continue
				if leg.swing or leg.h > 1.0:
					any_swing = true
					continue
				dev = maxf(dev, absf(ys[li]) * k)
				lo = minf(lo, absf(ys[li]) * k)
			if any_swing:
				dev = 0.0 if lo == INF else lo
			if dev > worst_feet:
				worst_feet = dev
				feet_at = tag
			var sink := rig.lowest_y(body) * k
			if sink > worst_sink:
				worst_sink = sink
				sink_at = tag + " " + _lowest_bone(rig, body)
		if not vis._spear_free and float(m.fin.get("plant", 0.0)) < 0.5 and b.state != LanternKnight.State.STUCK:
			var sp := rig.lowest_y(PackedInt32Array([wi])) * k
			if sp > worst_spear:
				worst_spear = sp
				spear_at = tag
		var y := float(vis.probe_pose()[2])
		if absf(y - prev_y) > worst_hip:
			worst_hip = absf(y - prev_y)
			hip_at = tag
		prev_y = y
		var w: float = vis._weapon_bone.rotation
		if absf(angle_difference(prev_w, w)) > worst_wrot:
			worst_wrot = absf(angle_difference(prev_w, w))
			wrot_at = tag
		prev_w = w
		for x in rig.xf:
			if is_nan(x.origin.x) or is_nan(x.origin.y):
				nan = true
	print("[probe]   %-10s 발 %.1fpx(%s) · 몸 아래 %.1fpx(%s) · 창 아래 %.1fpx(%s) · 엉덩이 뜀 %.1fpx(%s) · 창 각 뜀 %.2frad(%s)" % [
		name, worst_feet, feet_at, worst_sink, sink_at, worst_spear, spear_at, worst_hip, hip_at, worst_wrot, wrot_at])
	_check(worst_feet <= FEET_TOL, "%s: 디딘 발바닥이 땅 ±%.0fpx (%.1f)" % [name, FEET_TOL, worst_feet])
	_check(worst_sink <= SINK_TOL, "%s: 몸이 땅 아래로 %.0fpx 넘게 들어가지 않는다 (%.1f)" % [name, SINK_TOL, worst_sink])
	_check(worst_spear <= SINK_TOL, "%s: 창이 땅에 박히지 않는다 (가장 낮은 창 점 %+.1fpx)" % [name, worst_spear])
	_check(worst_hip <= HIP_JUMP, "%s: 엉덩이 높이가 한 프레임에 %.0fpx 넘게 뛰지 않는다 (%.1f)" % [name, HIP_JUMP, worst_hip])
	_check(worst_wrot <= 0.7, "%s: 창 각도가 한 프레임에 0.7rad 넘게 뛰지 않는다 (%.2f)" % [name, worst_wrot])
	_check(not nan, "%s: NaN 없음" % name)
	b.free()


## 쓰러짐(→ 정화): 무릎 → 창에 기댐 → 엎어져 누움. 누운 끝을 재고, purify 면 정화해서 일어선 모습을 잰다.
func _fallen(purify: bool) -> void:
	var b := _spawn(false)
	var vis = b.get_node("Sprite")
	for i in 40:
		_step(b)
	var rig: PartRig = vis.rig
	var m: RigMotion = vis.motion
	var k: float = vis._k
	var stand_h := (float(rig.data.get("height", 680.0))) * k
	b.hp = 1.0
	b.receive_hit(HitData.make(5.0, 0.0, null), null)
	var worst_sink := -INF
	var worst_hip := 0.0
	var prev_y := float(vis.probe_pose()[2])
	var frames := 220 if not purify else 130
	for f in frames:
		_step(b)
		var sink := rig.lowest_y(m.lock_bones()) * k
		worst_sink = maxf(worst_sink, sink)
		var y := float(vis.probe_pose()[2])
		worst_hip = maxf(worst_hip, absf(y - prev_y))
		prev_y = y
	if not purify:
		var low := rig.lowest_y(m.lock_bones()) * k
		var torso := -_center_y(rig, "torso") * k
		var head := -_center_y(rig, "head") * k
		var spear_low := rig.lowest_y(PackedInt32Array([rig.bone_index("weapon")])) * k
		var spear_top := -_top_y(rig, "weapon") * k
		var lan_low := rig.lowest_y(PackedInt32Array([rig.bone_index("lantern")])) * k
		print("[probe]   쓰러짐 끝 (%.1f초): 몸통 가운데 %+.0fpx, 머리 가운데 %+.0fpx (키 %.0f), 가장 낮은 몸 점 %+.1f, 창 가장 낮은 점 %+.1f·꼭대기 %+.0f, 등불 가장 낮은 점 %+.1f, 쓰러지는 동안 몸 아래 최대 %.1f·엉덩이 뜀 %.1f" % [
			frames * DT, torso, head, stand_h, low, spear_low, spear_top, lan_low, worst_sink, worst_hip])
		_check(torso <= stand_h * 0.3 and head <= stand_h * 0.35, "쓰러짐: 정말 누웠다 — 몸통 %.0f%%(30 이하), 머리 %.0f%%(35 이하)" % [torso / stand_h * 100.0, head / stand_h * 100.0])
		_check(absf(low) <= 6.0, "쓰러짐: 누운 몸의 가장 낮은 점이 땅 ±6px (%+.1f)" % low)
		_check(worst_sink <= SINK_TOL, "쓰러지는 동안 몸이 땅에 박히지 않는다 (%.1f)" % worst_sink)
		_check(worst_hip <= HIP_JUMP * 1.5, "쓰러지는 동안 몸이 툭 떨어지지 않는다 (엉덩이 한 프레임 %.1fpx)" % worst_hip)
		_check(spear_low <= 3.0 and spear_low >= -24.0 and spear_top <= 60.0, "쓰러짐: 놓친 창이 땅 위에 눕는다 (가장 낮은 점 %+.1f, 꼭대기 %+.0f — 창날·잎 두께 60 아래)" % [spear_low, spear_top])
		_check(lan_low <= 4.0, "쓰러짐: 등불이 땅에 박히지 않는다 (%+.1f)" % lan_low)
	else:
		b.purified_by(null)
		for f in 100:
			_step(b)
		var head2 := -_center_y(rig, "head") * k
		var low2 := rig.lowest_y(m.lock_bones()) * k
		print("[probe]   정화 뒤: 머리 가운데 %+.0fpx (키 %.0f), 가장 낮은 몸 점 %+.1f, 투구 빛 %.2f" % [head2, stand_h, low2, vis._glow])
		_check(head2 >= stand_h * 0.45, "정화: 무릎 꿇은 채 몸을 일으킨다 — 머리 가운데 키의 %.0f%% (45 이상)" % (head2 / stand_h * 100.0))
		_check(absf(low2) <= 6.0, "정화: 몸이 땅 위에 (가장 낮은 점 %+.1f)" % low2)
		_check(vis._glow > 1.2, "정화: 투구 등불이 밝아진다 (%.2f)" % vis._glow)
	b.free()


func _phase2_posture() -> void:
	var out := []
	for p2 in [false, true]:
		var b := _spawn(p2)
		var vis = b.get_node("Sprite")
		for i in 90:
			_step(b)
		var pp: Array = vis.probe_pose()
		var rig: PartRig = vis.rig
		out.append([float(rig.root_pos.y), float(vis.motion.fin["torso"]) + float(vis.motion.fin["lean"])])
		b.free()
	print("[probe]   대기 자세 엉덩이 y 1페이즈 %.0f / 2페이즈 %.0f, 숙임 %.0f° / %.0f°" % [out[0][0], out[1][0], out[0][1], out[1][1]])
	_check(out[1][0] > out[0][0] + 10.0 and out[1][1] > out[0][1] + 5.0, "2페이즈 대기 자세가 더 낮고 앞으로 숙였다")


func _cost() -> void:
	var b := _spawn(false)
	var vis = b.get_node("Sprite")
	_player.global_position = Vector2(2500, 1000)
	b.player = _player
	for i in 30:
		_step(b)
	var t0 := Time.get_ticks_usec()
	for i in 240:
		vis._process(DT)
	var us := float(Time.get_ticks_usec() - t0) / 240.0
	print("[probe]   그림 한 프레임 비용 %.0f µs (이 맥 기준 — 아이폰 11 Pro 는 약 2~3배)" % us)
	_check(us < 2500.0, "등불 기사 그림 한 프레임 2.5ms 미만 (%.0f µs)" % us)
	b.free()


## 가장 낮은 껍질 점을 가진 뼈 이름 (어긋남 알림용)
func _lowest_bone(rig: PartRig, bones: PackedInt32Array) -> String:
	var best := ""
	var m := -INF
	for i in bones:
		var y := rig.lowest_y(PackedInt32Array([i]))
		if y > m:
			m = y
			best = rig.names[i]
	return best


func _center_y(rig: PartRig, bone: String) -> float:
	var i := rig.bone_index(bone)
	var t := rig.body_xf * rig.xf[i]
	var sum := 0.0
	for q in rig.hulls[i]:
		sum += (t * q).y
	return sum / maxf(rig.hulls[i].size(), 1)


func _top_y(rig: PartRig, bone: String) -> float:
	var i := rig.bone_index(bone)
	var t := rig.body_xf * rig.xf[i]
	var mn := INF
	for q in rig.hulls[i]:
		mn = minf(mn, (t * q).y)
	return mn

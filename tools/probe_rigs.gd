extends Node
## 부위 뼈대(파트 리그) 검사 — 화면 없이 돈다: godot --headless --path . res://tools/probe_rigs.tscn
## art/rigs/ 의 모든 뼈대에 대해
##  1) rig.json 을 읽고 부위 그림이 모두 있는가, 뼈 계층이 맞는가(부모가 먼저, 이름 겹침 없음), 다리·무기 사슬 이름이 실제 뼈인가
##  2) 대기 / 걷기 / 공격(예비→타격→되돌림) / 무너짐 / 피격 / 무릎 꿇기 에서 N 프레임 동안
##     - 발바닥이 땅 ±4px (게임 px): 서 있는 동안은 모든 발, 걷는 동안은 가장 낮은 발(한 발은 들려 있다)
##     - 땅 아래로 4px 넘게 들어간 부위 없음 (발·다리·몸·머리·무기 — 무기는 '땅 막기'가 지킨다)
##     - NaN 없음, 덮는 상자가 상식적 (키의 0.5~2.5배, 너비 < 키의 5배)
##  3) 쓰러짐(실제 몹 씬, 앞·뒤): 넘어진 뒤 가장 낮은 몸 점이 땅 ±6px (가라앉거나 뜨지 않음),
##     그리고 정말 누웠는가 — 몸통·머리 가운데가 낮고 무기가 하늘로 들리지 않음 (천·치마가 몸을 받쳐 떠 있지 않게)
##  4) 대롱 겨눔 (arm_kind = "gun"): 뼈대 몹을 대롱 몹처럼 바꿔 소녀를 위·앞·아래에 두면 대롱 뼈(aim_bone)의 축이 소녀를 향하는가
##  5) 뼈대 8개를 매 프레임 움직이는 비용
## 를 찍는다. 실패가 하나라도 있으면 종료 코드 1.

const STEP := 1.0 / 60.0
const FEET_TOL := 4.0
const SINK_TOL := 4.0
## 쓰러져 누운 끝: 몸통 가운데·머리 가운데·무기 꼭대기의 땅 위 높이 상한 (서 있는 키의 몫)
const LIE_TORSO := 0.3
const LIE_HEAD := 0.35
const LIE_WEAPON := 0.45

var _fail := 0


func _ready() -> void:
	print("[probe] 시작: 부위 뼈대 검사")
	var ids := _rig_ids()
	print("[probe] 뼈대 %d개: %s" % [ids.size(), ", ".join(ids)])
	_check(ids.size() > 0, "art/rigs 에 뼈대가 하나 이상 있다")
	for id in ids:
		_probe_rig(id)
	var scenes := _rig_enemy_scenes()
	for path in scenes:
		_probe_enemy_fall(path, false)
		_probe_enemy_fall(path, true)
	if scenes.size() > 0:
		await _probe_gun_aim(scenes[0])
	_probe_cost(ids)
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


## 부위 뼈대 그림(EnemyRigVisual)을 쓰는 몹 씬들 (scenes/enemies/ 에서 저절로 찾는다 — 새 몹을 바꾸면 따로 적지 않아도 검사된다)
func _rig_enemy_scenes() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://scenes/enemies")
	if d == null:
		return out
	for f in d.get_files():
		if not f.ends_with(".tscn"):
			continue
		var path := "res://scenes/enemies/" + f
		var ps: PackedScene = load(path)
		if ps == null:
			continue
		var st := ps.get_state()
		for i in st.get_node_count():
			if str(st.get_node_name(i)) != "Visual":
				continue
			for k in st.get_node_property_count(i):
				if st.get_node_property_name(i, k) == "script":
					var sc = st.get_node_property_value(i, k)
					if sc is Script and (sc as Script).resource_path.ends_with("enemy_rig_visual.gd"):
						out.append(path)
	out.sort()
	return out


func _rig_ids() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://art/rigs")
	if d == null:
		return out
	for sub in d.get_directories():
		if FileAccess.file_exists("res://art/rigs/%s/rig.json" % sub):
			out.append(sub)
	out.sort()
	return out


func _probe_rig(id: String) -> void:
	var data := PartRig.load_data(id)
	_check(not data.is_empty(), "%s: rig.json 을 읽었다" % id)
	if data.is_empty():
		return
	# 1) 구조
	var bones: Array = data["bones"]
	var seen := {}
	var order_ok := true
	var tex_ok := true
	for b in bones:
		var nm := str(b["name"])
		if seen.has(nm):
			order_ok = false
		var par := str(b["parent"])
		if par != "" and not seen.has(par):
			order_ok = false
		seen[nm] = true
		if b.has("tex") and not ResourceLoader.exists(str(b["tex"])):
			tex_ok = false
			print("[probe]   그림 없음: ", b["tex"])
		for vn in b.get("variants", {}):
			if not ResourceLoader.exists(str(b["variants"][vn]["tex"])):
				tex_ok = false
	_check(order_ok, "%s: 뼈 계층 (부모가 먼저, 이름 겹침 없음, 뿌리 1개)" % id)
	_check(tex_ok, "%s: 부위 그림이 모두 있다 (%d개)" % [id, bones.size()])
	var names_ok := true
	for leg in data.get("legs", []):
		for k in ["up", "lo", "foot"]:
			if leg.has(k) and not seen.has(str(leg[k])):
				names_ok = false
	for g in data.get("ground_guard", []):
		if not seen.has(str(g)):
			names_ok = false
	_check(names_ok, "%s: 다리·땅 막기 이름이 실제 뼈다" % id)
	var root_count := 0
	for b in bones:
		if str(b["parent"]) == "":
			root_count += 1
	_check(root_count == 1, "%s: 뿌리 뼈 하나 (%d)" % [id, root_count])
	# 변형 그림: 바꿔 끼우고 되돌릴 수 있는가
	for b in bones:
		for vn in b.get("variants", {}):
			var vr := PartRig.new()
			add_child(vr)
			vr.build(id)
			var spr := vr.sprite_of(str(b["name"]))
			var t0: Texture2D = spr.texture if spr else null
			vr.set_variant(str(b["name"]), str(vn))
			var t1: Texture2D = spr.texture if spr else null
			vr.set_variant(str(b["name"]), "")
			var t2: Texture2D = spr.texture if spr else null
			_check(spr != null and t1 != t0 and t2 == t0, "%s: 변형 그림 %s@%s 바꿔 끼우기·되돌리기" % [id, b["name"], vn])
			vr.queue_free()

	# 2) 자세들
	var rig := PartRig.new()
	add_child(rig)
	rig.build(id)
	var m := RigMotion.new(rig)
	var gs := rig.game_scale
	var h := float(data.get("height", 1000.0))
	var bad_feet := {}
	var worst_sink := {}
	var nan := false
	var bounds_bad := ""
	var weapon_low := -INF
	var guard_set := PackedInt32Array()
	for g in data.get("ground_guard", []):
		guard_set.append(rig.bone_index(str(g)))
	# 몸(천·장식을 뺀) 부위: 다리·몸통·머리·팔 — 치마 잎처럼 늘어진 천은 땅에 닿아 접혀도 된다 (hips 는 치마를 품고 있어 뺀다)
	var body := PackedInt32Array()
	for i in rig.names.size():
		var nm := rig.names[i]
		if nm.begins_with("leg_") or nm.begins_with("foot_") or nm in ["torso", "head"] or nm.begins_with("arm_"):
			body.append(i)
	if body.is_empty():
		# 사람 모양이 아닌 뼈대(새·기계): 무기 사슬과 늘어진 천을 뺀 모든 부위
		for i in m._lock_bones:
			if not (data["bones"][i] as Dictionary).has("chain"):
				body.append(i)
	var scen := [
		["idle", 90, false], ["walk", 150, true], ["attack", 0, false], ["broken", 120, false], ["hit", 40, false], ["kneel", 120, false],
	]
	for sc in scen:
		var name: String = sc[0]
		var frames: int = sc[1]
		var walking: bool = sc[2]
		var worst_feet := 0.0
		var sink := -INF
		m.snap_feet()
		if name == "attack":
			# 예비 0.5초 → 타격 0.12초 → 되돌림 0.55초 (나무꾼 값)
			m.set_target(m.pose("idle"))
			for i in 60:
				m.update(STEP, {})
			var from := m.capture()
			var seq := [["windup", 0.5, RigMotion.Drive.SOFT], ["strike", 0.12, RigMotion.Drive.FAST], ["recover", 0.55, RigMotion.Drive.SETTLE]]
			for ph in seq:
				var n := int(round(float(ph[1]) / STEP))
				if ph[0] == "recover":
					from = m.capture()
				for i in n:
					var p := float(i + 1) / n
					var pose := m.three_beat(from, m.pose("windup"), m.pose("strike"), m.pose("ready"), ph[0], p)
					m.set_target(pose, ph[2], RigMotion.Feet.POSE)
					m.update(STEP, {})
					var r := _measure(m, rig, body, guard_set, gs, false)
					worst_feet = maxf(worst_feet, r[0])
					sink = maxf(sink, r[1])
					weapon_low = maxf(weapon_low, r[2])
					nan = nan or r[3]
		else:
			var pose_name := "walk" if walking else name
			m.set_target(m.pose(pose_name), RigMotion.Drive.NORMAL, RigMotion.Feet.GAIT if walking else RigMotion.Feet.POSE)
			var speed := 300.0 / gs   # 게임 300px/초
			for i in frames:
				m.update(STEP, {"speed": speed if walking else 0.0, "dx": speed * STEP if walking else 0.0})
				if i < 30:
					continue   # 자세가 자리 잡는 동안은 빼고 잰다
				var r := _measure(m, rig, body, guard_set, gs, walking or name == "kneel" or name == "broken")
				worst_feet = maxf(worst_feet, r[0])
				sink = maxf(sink, r[1])
				weapon_low = maxf(weapon_low, r[2])
				nan = nan or r[3]
		var bb := rig.bounds()
		if bb.size.y < h * 0.4 or bb.size.y > h * 2.5 or bb.size.x > h * 5.0:
			bounds_bad += "%s(%.0fx%.0f) " % [name, bb.size.x, bb.size.y]
		bad_feet[name] = worst_feet
		worst_sink[name] = sink
		print("[probe]   %s %-7s 발바닥 최대 어긋남 %.1fpx, 몸이 땅 아래로 최대 %.1fpx" % [id, name, worst_feet, sink])
	var feet_ok := true
	var sink_ok := true
	for k in bad_feet:
		if bad_feet[k] > FEET_TOL:
			feet_ok = false
		if worst_sink[k] > SINK_TOL:
			sink_ok = false
	_check(feet_ok, "%s: 발바닥이 땅 ±%.0fpx (대기·걷기·공격·무너짐·피격·무릎)" % [id, FEET_TOL])
	_check(sink_ok, "%s: 몸(다리·몸통·머리·팔)이 땅 아래로 %.0fpx 넘게 들어가지 않는다" % [id, SINK_TOL])
	_check(weapon_low <= SINK_TOL or guard_set.is_empty(), "%s: 무기가 땅에 파고들지 않는다 (가장 낮은 무기 점 %+.1fpx)" % [id, weapon_low])
	_check(not nan, "%s: NaN 없음" % id)
	_check(bounds_bad == "", "%s: 덮는 상자가 상식적 %s" % [id, bounds_bad])
	rig.queue_free()


## [발바닥 어긋남(px), 몸이 땅 아래로 들어간 깊이(px), 무기 가장 낮은 점(px, + = 땅 아래), NaN?]
## lenient: 걷기·무릎처럼 한 발이 들려 있는 자세 — 가장 낮은 발만 땅 ±.
func _measure(m: RigMotion, rig: PartRig, body: PackedInt32Array, guard: PackedInt32Array, gs: float, lenient: bool) -> Array:
	var ys := m.sole_ys()
	var feet := 0.0
	var nan := false
	if ys.size() > 0:
		if lenient:
			var lo := INF
			for k in ys.size():
				var leg: RigMotion.Leg = m.legs[k]
				if float(m.fin.get(leg.k_kneel, 0.0)) > 0.3:
					continue
				lo = minf(lo, absf(ys[k]))
			feet = (0.0 if lo == INF else lo) * gs
		else:
			for y in ys:
				feet = maxf(feet, absf(y) * gs)
	for x in rig.xf:
		if is_nan(x.origin.x) or is_nan(x.origin.y) or is_nan(x.x.x):
			nan = true
	var sink := rig.lowest_y(body) * gs
	var wlow := rig.lowest_y(guard) * gs if guard.size() > 0 else -INF
	return [feet, sink, wlow, nan]


## 실제 몹 씬으로 쓰러짐: 넘어진 끝에 몸이 땅 위에 눕는가 (가라앉거나 뜨지 않음)
## from_front: 앞에서 맞아 뒤로 쓰러짐(엉덩방아 → 등), 아니면 뒤에서 맞아 앞으로(꿇고 엎어짐)
func _probe_enemy_fall(path: String, from_front: bool) -> void:
	var e: EnemyBase = (load(path) as PackedScene).instantiate()
	if e.savable:
		e.free()
		print("[probe]   %s: 구원 가능한 자는 쓰러지지 않는다 (무릎 꿇기는 자세 검사에서 본다)" % path.get_file())
		return
	e.gravity = 0.0
	add_child(e)
	if e.is_queued_for_deletion():
		print("[probe]   %s: 이미 물리친 중간 보스라 나오지 않는다 (건너뜀)" % path.get_file())
		e.free()
		return
	e.set_physics_process(false)
	var vis = e.get_node("Visual")
	vis.set_process(false)
	e.player = null
	e.facing = 1
	e._timer = 999.0
	for i in 30:
		e._physics_process(STEP)
		vis._process(STEP)
	e.hp = 1.0
	var src: Node2D = null
	if from_front:
		src = Node2D.new()
		add_child(src)
		src.global_position = e.global_position + Vector2(120, 0)   # 몹은 오른쪽(facing 1)을 본다
	e.receive_hit(HitData.make(5.0, 10.0, src), null)
	if src:
		src.free()
	var low_end := 0.0
	var feet_dev := 0.0
	var rig: PartRig = vis.rig
	var body := PackedInt32Array()
	for i in rig.names.size():
		var nm := rig.names[i]
		if nm.begins_with("leg_") or nm.begins_with("foot_") or nm in ["torso", "head"]:
			body.append(i)
	var gs: float = rig.game_scale * float(vis.art_scale)
	var stand_h := float(rig.data.get("height", 1000.0)) * gs
	var torso_h := 0.0
	var head_h := 0.0
	var weapon_hi := 0.0
	for i in 40:   # 0.67초 (쓰러짐 0.75초 안)
		e._physics_process(STEP)
		vis._process(STEP)
		if i == 36:
			low_end = rig.lowest_y(vis.motion._lock_bones) * gs
			torso_h = -_center_y(rig, "torso") * gs
			head_h = -_center_y(rig, "head") * gs
			weapon_hi = -_top_y(rig, "weapon") * gs
	var side := "뒤로" if from_front else "앞으로"
	print("[probe]   %s %s 쓰러짐 끝: 몸통 가운데 %+.0fpx, 머리 가운데 %+.0fpx, 무기 꼭대기 %+.0fpx (서 있는 키 %.0fpx, 땅 위 +)" % [path.get_file(), side, torso_h, head_h, weapon_hi, stand_h])
	_check(absf(low_end) <= 6.0, "%s: %s 쓰러져 누운 몸의 가장 낮은 점이 땅 ±6px (%+.1fpx)" % [path.get_file(), side, low_end])
	# 누웠는가: 가장 낮은 점만 보면 천·치마가 몸을 받쳐 떠 있어도 통과한다 → 몸통·머리 가운데가 낮아야 한다 (기울기 줄인 거대화 몹 포함)
	_check(torso_h <= stand_h * LIE_TORSO and head_h <= stand_h * LIE_HEAD,
		"%s: %s 쓰러져 누웠다 — 몸통 가운데 ≤ 키의 %d%%, 머리 가운데 ≤ 키의 %d%% (몸통 %.0f%%, 머리 %.0f%%)" % [path.get_file(), side,
		int(LIE_TORSO * 100.0), int(LIE_HEAD * 100.0), torso_h / stand_h * 100.0, head_h / stand_h * 100.0])
	if rig.has_bone("weapon"):
		_check(weapon_hi <= stand_h * LIE_WEAPON, "%s: %s 쓰러진 무기가 하늘로 들리지 않는다 — 무기 꼭대기 ≤ 키의 %d%% (%.0f%%)" % [path.get_file(), side,
			int(LIE_WEAPON * 100.0), weapon_hi / stand_h * 100.0])
	e.free()


## 부위 껍질 점들의 가운데 y (뼈대 단위, body_xf 포함, 땅 0·위 −). 그 뼈가 없으면 0.
func _center_y(rig: PartRig, bone: String) -> float:
	var i := rig.bone_index(bone)
	if i < 0 or rig.hulls[i].is_empty():
		return 0.0
	var t := rig.body_xf * rig.xf[i]
	var sum := 0.0
	for q in rig.hulls[i]:
		sum += (t * q).y
	return sum / rig.hulls[i].size()


## 부위 껍질의 가장 높은 y (뼈대 단위, 위 −)
func _top_y(rig: PartRig, bone: String) -> float:
	var i := rig.bone_index(bone)
	if i < 0:
		return 0.0
	var t := rig.body_xf * rig.xf[i]
	var m := INF
	for q in rig.hulls[i]:
		m = minf(m, (t * q).y)
	return m if m < INF else 0.0


## 대롱 겨눔: 첫 뼈대 몹 씬을 arm_kind = "gun" 으로 바꿔 (aim_bone 의 축 = 대롱) 쫓는 상태에서 소녀를 세 자리에 둔다.
## 대롱 축과 '손 → 소녀 가슴' 방향의 각도 차이가 작아야 한다 (겨눔 한계 안의 자리만). 예고 때는 조금 치켜든다.
func _probe_gun_aim(path: String) -> void:
	var e: EnemyBase = (load(path) as PackedScene).instantiate()
	e.gravity = 0.0
	var vis = e.get_node("Visual")
	vis.arm_kind = "gun"
	add_child(e)
	if e.is_queued_for_deletion():
		e.free()
		return
	e.set_physics_process(false)
	vis.set_process(false)
	var pl: Player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(pl)
	pl.set_physics_process(false)
	pl.set_process(false)
	await get_tree().process_frame
	e.facing = 1
	e.player = pl
	e._set_state(EnemyBase.State.CHASE)
	var rig: PartRig = vis.rig
	var ai := rig.bone_index(str(vis.aim_bone))
	var worst := 0.0
	var res := ""
	# 소녀 자리 (몹 기준): 앞 수평, 앞 위(한계 안), 앞 아래(한계 안)
	for off in [Vector2(520, 0), Vector2(600, -260), Vector2(600, 260)]:
		for i in 60:
			var hand0 := rig.to_global(rig.bone_point(str(vis.aim_bone)))
			pl.global_position = hand0 + off + Vector2(0, 40)
			vis._process(STEP)
		var hand := rig.to_global(rig.bone_point(str(vis.aim_bone)))
		var tip := rig.to_global(rig.to_rig_local(rig.xf[ai] * Vector2(0, 100)))
		var want: Vector2 = pl.global_position + Vector2(0, -40) - hand
		var err := absf(rad_to_deg(wrapf((tip - hand).angle() - want.angle(), -PI, PI)))
		worst = maxf(worst, err)
		res += "(%+.0f,%+.0f) %.1f도  " % [off.x, off.y, err]
	print("[probe]   대롱 겨눔 %s: %s" % [path.get_file(), res])
	_check(worst <= 6.0, "대롱 겨눔: 대롱 축이 소녀 가슴을 향한다 (가장 큰 차이 %.1f도, 기준 6도)" % worst)
	# 예고: 조금 치켜든다
	e._set_state(EnemyBase.State.WINDUP)
	for i in 40:
		vis._process(STEP)
	var hand2 := rig.to_global(rig.bone_point(str(vis.aim_bone)))
	var tip2 := rig.to_global(rig.to_rig_local(rig.xf[ai] * Vector2(0, 100)))
	var want2: Vector2 = pl.global_position + Vector2(0, -40) - hand2
	var raise := rad_to_deg(wrapf(want2.angle() - (tip2 - hand2).angle(), -PI, PI))
	_check(raise > 5.0 and raise < 25.0, "대롱 겨눔: 예고 때 대롱을 조금 치켜든다 (%.1f도)" % raise)
	e.free()
	pl.free()


func _probe_cost(ids: Array) -> void:
	if ids.is_empty():
		return
	var rigs: Array = []
	var motions: Array = []
	for k in 8:
		var r := PartRig.new()
		add_child(r)
		r.build(ids[k % ids.size()])
		var mm := RigMotion.new(r)
		mm.set_target(mm.pose("walk"), RigMotion.Drive.NORMAL, RigMotion.Feet.GAIT)
		rigs.append(r)
		motions.append(mm)
	var t0 := Time.get_ticks_usec()
	var n := 240
	for f in n:
		for mm in motions:
			mm.update(STEP, {"speed": 1500.0, "dx": 25.0})
	var us := float(Time.get_ticks_usec() - t0) / n
	print("[probe] 뼈대 8개 한 프레임 비용: %.2f ms (뼈대 하나 %.0f µs, 이 맥 기준 — 아이폰 11 Pro 는 약 2~3배)" % [us / 1000.0, us / 8.0])
	_check(us < 4000.0, "뼈대 8개를 움직이는 비용이 한 프레임 4ms 미만 (%.2f ms)" % (us / 1000.0))
	for r in rigs:
		r.queue_free()

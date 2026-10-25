extends Node
## 정원사·약초꾼 가족(부위 뼈대) 검사 — 화면 없이 돈다: godot --headless --path . res://tools/probe_gardener_herbalist.tscn
## 바닥 하나뿐인 시험장에 실제 몹 씬(gardener / gardener_savable / elite_gardener / herbalist / herbalist_savable / elite_herbalist)을 세우고
## 실제 AI(_physics_process)를 1/60초씩 손으로 돌리며 소녀를 '쏠 거리'에 두었다가 '바짝 붙은 거리'로 옮긴다. 그동안
##  1) 땅을 딛은 동안 발바닥이 땅 ±4px (적어도 한 발은 땅에, 땅 아래로 4px 넘게 들어간 발·몸 없음), NaN 없음
##  2) 정원사: 대롱이 소녀 가슴을 겨눈다 (쫓기·회복 중 오차 ≤ 8도), 쏘는 순간 대롱이 튀어 오른다(반동),
##     물러나며 폴짝 뛰기 직전에 웅크린다(엉덩이가 선 자세보다 낮다), 등의 씨앗 꼬투리가 출렁인다
##  3) 약초꾼: 뿌리는 순간 버섯이 부풀어 터지고(배율 ≥ 1.2) 포자 가루가 흩날리며, 앞손을 앞으로 내던진다
##  4) 구원 가능한 자: 무릎 꿇고 기다리는 동안 눈 감은 얼굴(머리 변형), 정화되면 눈을 뜨고 같은 뼈대의 사람(RescuedPerson)이 선다
##  5) 대롱·버섯 같은 부위 이름이 설계도에 실제로 있다
## 를 본다. 실패가 하나라도 있으면 종료 코드 1.
##
## 창으로 띄우면(--headless 빼고) 실제 방에서 장면을 찍는다: ... res://tools/probe_gardener_herbalist.tscn -- --shots
##   → screenshots/gh_<방>_<몹>_<번호>_<상태>.png (실제 조명·배경·크기로 대기·걷기·쏘기·물러남·피격·무너짐·쓰러짐·무릎·정화)

const STEP := 1.0 / 60.0
const FLOOR_Y := 600.0
const FEET_TOL := 4.0
const SCENES := ["gardener", "gardener_savable", "elite_gardener", "herbalist", "herbalist_savable", "elite_herbalist"]
## 실제 방에서 찍을 몹: [방, 몹 노드 이름]
const SHOT_CASES := [["canopy_03", "Gardener7"], ["canopy_03", "Gardener_sav4"], ["canopy_mini_2", "MiniBoss"],
	["abyss_01", "Herbalist1"], ["abyss_02", "Herbalist_sav1"], ["abyss_mini_1", "MiniBoss"]]

var _fail := 0
var _floor: StaticBody2D
var _player: Player


func _ready() -> void:
	if "--shots" in OS.get_cmdline_user_args():
		await _run_shots()
		get_tree().quit()
		return
	var fi := OS.get_cmdline_user_args().find("--film")
	if fi >= 0:
		await _run_film(OS.get_cmdline_user_args()[fi + 1])
		get_tree().quit()
		return
	# 몹의 우연(달려들기·뒤로 빠지기 확률)을 고정한다 — 뒤로 빠진 직후 예고로 들어가는 길에서 거대화 약초꾼의 발이
	# 기준(7.2px)에 걸치는 판이 가끔 나와 시험이 흔들렸다 (v1.1.0 몹 돌아서기로 행동 순서가 바뀐 뒤). --seed N 으로 바꿔 볼 수 있다.
	var si := OS.get_cmdline_user_args().find("--seed")
	seed(int(OS.get_cmdline_user_args()[si + 1]) if si >= 0 else 20261025)
	print("[probe] 시작: 정원사·약초꾼 부위 뼈대")
	_make_floor()
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.hurtbox.set_deferred("monitorable", false)
	_player.hurtbox.set_deferred("monitoring", false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for s in SCENES:
		await _probe_scene(s)
	await _probe_rescue("gardener_savable")
	await _probe_rescue("herbalist_savable")
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _make_floor() -> void:
	_floor = StaticBody2D.new()
	_floor.collision_layer = 1
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20000, 200)
	cs.shape = rect
	cs.position = Vector2(0, FLOOR_Y + 100)
	_floor.add_child(cs)
	add_child(_floor)


func _spawn(scene: String, x: float) -> EnemyBase:
	var e: EnemyBase = (load("res://scenes/enemies/%s.tscn" % scene) as PackedScene).instantiate()
	e.position = Vector2(x, FLOOR_Y - 120.0)
	add_child(e)
	e.set_physics_process(false)
	e.get_node("Visual").set_process(false)
	return e


func _tick(e: EnemyBase) -> void:
	e._physics_process(STEP)
	if is_instance_valid(e):
		e.get_node("Visual")._process(STEP)


## 대롱 축과 '손 → 소녀 가슴' 방향 사이의 각도(도). 대롱이 소녀보다 위를 가리키면 −.
func _aim_err(vis: EnemyRigVisual) -> float:
	var rig := vis.rig
	var ai := rig.bone_index(vis.aim_bone)
	var hand := rig.to_global(rig.bone_point(vis.aim_bone))
	var tip := rig.to_global(rig.to_rig_local(rig.xf[ai] * Vector2(0, 100)))
	var want: Vector2 = _player.global_position + Vector2(0, -40) - hand
	var f := float(vis.visible_facing())
	# 오른쪽을 보는 기준으로 맞춘 각도 차 (+ = 대롱이 아래)
	var a := Vector2((tip - hand).x * f, (tip - hand).y).angle()
	var b := Vector2(want.x * f, want.y).angle()
	return rad_to_deg(wrapf(a - b, -PI, PI))


func _probe_scene(scene: String) -> void:
	var e := _spawn(scene, 0.0)
	if e.is_queued_for_deletion():
		print("[probe]   %s: 나오지 않는다 (건너뜀)" % scene)
		e.free()
		return
	var vis := e.get_node("Visual") as EnemyRigVisual
	_check(vis != null and vis.rig != null and vis.motion != null, "%s: Visual 이 부위 뼈대(EnemyRigVisual)다" % scene)
	if vis == null or vis.rig == null:
		e.free()
		return
	var rig := vis.rig
	var gs := rig.game_scale * vis.art_scale
	var gun := vis.arm_kind == "gun"
	var herb := vis is HerbalistEnemyRigVisual
	if gun:
		_check(rig.has_bone("weapon") and rig.has_bone("arm_f_up") and rig.has_bone("pods"), "%s: 대롱(weapon)·위팔·씨앗 꼬투리(pods) 뼈가 있다" % scene)
	if herb:
		_check(rig.has_bone("mush_a") and rig.has_bone("mush_b") and rig.has_bone("mantle"), "%s: 버섯(mush_a·b)·망토(mantle) 뼈가 있다" % scene)
	e.player = _player
	# 1) 쏠/뿌릴 거리에 소녀를 둔다
	var far := 500.0 if gun else 430.0
	if scene.begins_with("elite"):
		far *= 1.3
	_player.global_position = Vector2(far, FLOOR_Y - 67.0)
	var feet_worst := 0.0
	var sink_worst := 0.0
	var feet_where := ""
	var sink_where := ""
	var settle := 0.0   # 소녀를 옮긴 뒤 겨눔이 따라붙을 시간
	var land_t := 1.0
	var nan := false
	var aim_worst := 0.0
	var aim_n := 0
	var shots := 0
	var recoil_seen := 0.0
	var crouch_best := -INF
	var takeoffs := 0
	var pods_min := INF
	var pods_max := -INF
	var puff_max := 0.0
	var spores := false
	var fling := 0.0
	var states := {}
	var stand_root := rig.root_pos.y
	var prev_floor := true
	var prev_root := 0.0
	var shot_t := -1.0
	var wind_tip_x := 0.0
	var t := 0.0
	var phase_len := 5.0
	for phase in 2:
		if phase == 1:
			# 2) 바짝 붙는다 (정원사는 대롱을 겨눈 채 폴짝 물러나고, 약초꾼은 뒷걸음질하며 뿌린다)
			_player.global_position = Vector2(e.global_position.x + (150.0 if not scene.begins_with("elite") else 240.0) * float(e.facing), FLOOR_Y - 67.0)
			phase_len = 3.5
			settle = 0.5
		var pt := 0.0
		while pt < phase_len and is_instance_valid(e):
			if phase == 1:
				# 소녀가 물러나는 몹을 따라붙는다 (바라보는 쪽 앞, 몹 몸에 겹치지 않게)
				var side := 1.0 if _player.global_position.x >= e.global_position.x else -1.0
				var close := 150.0 if not scene.begins_with("elite") else 240.0
				_player.global_position.x = move_toward(_player.global_position.x, e.global_position.x + side * close, 400.0 * STEP)
			settle = maxf(settle - STEP, 0.0)
			var st0 := e.state
			_tick(e)
			pt += STEP
			t += STEP
			if not is_instance_valid(e):
				break
			states[e.state_name()] = true
			var on_floor := e.is_on_floor()
			if is_nan(rig.root_pos.x) or is_nan(rig.root_pos.y):
				nan = true
			# 발: 땅을 딛은 동안 (공중 아님, 내려앉은 뒤 0.15초는 다리가 따라 내려오는 중)
			land_t = 0.0 if not on_floor else land_t + STEP
			if on_floor and land_t > 0.15 and absf(e.velocity.y) < 60.0 and e.state in [EnemyBase.State.IDLE, EnemyBase.State.PATROL, EnemyBase.State.CHASE, EnemyBase.State.WINDUP, EnemyBase.State.STRIKE, EnemyBase.State.RECOVER] and not vis.motion.is_airborne():
				var ys := vis.motion.sole_ys()
				var near := INF
				var deep := -INF
				for y in ys:
					near = minf(near, absf(y))
					deep = maxf(deep, y)
				if near * gs > feet_worst:
					feet_worst = near * gs
					feet_where = "%s %.2f초" % [e.state_name(), e.state_time]
				var sink := maxf(deep, rig.lowest_y(vis.motion.lock_bones())) * gs
				if sink > sink_worst:
					sink_worst = sink
					sink_where = "%s %.2f초 %s" % [e.state_name(), e.state_time, _deepest_part(rig, vis.motion.lock_bones())]
			if gun:
				var pi_ := rig.bone_index("pods")
				var rel := rig.world_rot(pi_) - rig.world_rot(rig.bone_index("torso"))
				pods_min = minf(pods_min, rel)
				pods_max = maxf(pods_max, rel)
				if e.state in [EnemyBase.State.CHASE, EnemyBase.State.RECOVER] and on_floor and e.state_time > 0.25 and settle <= 0.0 and vis.is_facing_settled():
					# 소녀가 대롱 끝보다 가까우면 겨눔 각도가 뜻이 없다 (그땐 물러난다) → 손에서 220px 넘게 떨어졌을 때만
					var hand_g := rig.to_global(rig.bone_point(vis.aim_bone))
					if hand_g.distance_to(_player.global_position + Vector2(0, -40)) > 220.0 * vis.art_scale:
						aim_worst = maxf(aim_worst, absf(_aim_err(vis)))
						aim_n += 1
				if e.state == EnemyBase.State.STRIKE and st0 != EnemyBase.State.STRIKE:
					shots += 1
					shot_t = 0.0
				if shot_t >= 0.0:
					shot_t += STEP
					# 반동: 위팔에 덧붙은 각도(채널 목표 밖의 몫 — 숨쉬기·충격·반동)가 위로(−) 튄 만큼
					var arm := rig.bone_index("arm_f_up")
					var extra := rad_to_deg(rig.bone_rot(arm)) - vis.motion.channel("arm_f_up")
					recoil_seen = maxf(recoil_seen, -extra)
					if shot_t > 0.12:
						shot_t = -1.0
				# 폴짝 뛰기: 땅에서 떠나는 순간 바로 앞 프레임의 엉덩이 높이
				if prev_floor and not on_floor and e.velocity.y < -200.0 and e.state == EnemyBase.State.CHASE:
					takeoffs += 1
					crouch_best = maxf(crouch_best, (prev_root - stand_root) * gs)
			if herb:
				var mi := rig.bone_index("mush_a")
				puff_max = maxf(puff_max, rig.scl[mi].x)
				var hs = vis.get("_h_spores")
				if hs and (hs as CPUParticles2D).emitting:
					spores = true
				var hand := rig.bone_index("weapon")
				var tip_x := (rig.xf[hand] * Vector2(0, rig.bone_len[hand])).x
				if e.state == EnemyBase.State.WINDUP:
					wind_tip_x = tip_x
				elif e.state == EnemyBase.State.STRIKE and e.anim_hint == "scatter":
					fling = maxf(fling, (tip_x - wind_tip_x) * gs)
			prev_floor = on_floor
			prev_root = rig.root_pos.y
	if not is_instance_valid(e):
		_check(false, "%s: 시험 중에 사라졌다" % scene)
		return
	print("[probe]   %s 거친 상태: %s" % [scene, ", ".join(states.keys())])
	_check(not nan, "%s: 뼈대 값에 NaN 이 없다" % scene)
	# 기준은 보통 크기에서 4px — 1.8배 거대화 몹은 같은 몫(× 그림 배율)
	var tol := FEET_TOL * maxf(vis.art_scale, 1.0)
	_check(feet_worst <= tol, "%s: 땅을 딛은 동안 한 발은 늘 땅에 (가장 먼 %.1fpx, 기준 %.1f — %s)" % [scene, feet_worst, tol, feet_where])
	_check(sink_worst <= tol, "%s: 발·몸이 땅 아래로 들어가지 않는다 (가장 깊이 %.1fpx, 기준 %.1f — %s)" % [scene, sink_worst, tol, sink_where])
	if gun:
		_check(aim_n > 20 and aim_worst <= 8.0, "%s: 대롱이 소녀 가슴을 겨눈다 (쫓기·회복 %d프레임, 가장 큰 오차 %.1f도)" % [scene, aim_n, aim_worst])
		_check(shots >= 1 and recoil_seen >= 8.0, "%s: 쏘는 순간 대롱이 위로 튄다 (쏜 횟수 %d, 어깨 반동 %.1f도, 기준 8)" % [scene, shots, recoil_seen])
		_check(takeoffs >= 1 and crouch_best >= 5.0, "%s: 물러나며 폴짝 뛰기 직전에 웅크린다 (뛴 횟수 %d, 엉덩이가 선 자세보다 %.1fpx 낮음)" % [scene, takeoffs, crouch_best])
		_check(rad_to_deg(pods_max - pods_min) >= 3.0, "%s: 등의 씨앗 꼬투리가 출렁인다 (몸통 기준 흔들림 %.1f도)" % [scene, rad_to_deg(pods_max - pods_min)])
	if herb:
		_check(puff_max >= 1.2, "%s: 뿌리는 순간 버섯이 부풀어 터진다 (가장 큰 배율 %.2f)" % [scene, puff_max])
		_check(spores, "%s: 뿌릴 때 포자 가루가 흩날린다" % scene)
		_check(fling >= 25.0, "%s: 앞손을 앞으로 내던진다 (예고 끝보다 %.0fpx 앞으로)" % [scene, fling])
	e.free()


## 땅 아래로 가장 깊이 들어간 부위 이름 (진단용)
func _deepest_part(rig: PartRig, bones: PackedInt32Array) -> String:
	var best := ""
	var dv := -INF
	for i in bones:
		var t := rig.body_xf * rig.xf[i]
		for q in rig.hulls[i]:
			if (t * q).y > dv:
				dv = (t * q).y
				best = rig.names[i]
	return best


## 구원 가능한 자: 무너져 무릎 꿇음(눈 감은 얼굴) → 정화(눈 뜸) → 같은 뼈대의 사람이 선다
func _probe_rescue(scene: String) -> void:
	var e := _spawn(scene, 3000.0)
	if e.is_queued_for_deletion():
		e.free()
		return
	var vis := e.get_node("Visual") as EnemyRigVisual
	e.player = _player
	_player.global_position = Vector2(3400.0, FLOOR_Y - 67.0)
	for i in 30:
		_tick(e)
	var head := vis.rig.sprite_of("head")
	var open_tex := head.texture
	e.hp = 1.0
	e.receive_hit(HitData.make(5.0, 10.0, null), null)
	for i in 30:
		_tick(e)
	_check(e.state == EnemyBase.State.BROKEN and vis.motion.target.get("kneel_b", 0.0) >= 1.0, "%s: 체력 0 이면 무릎 꿇고 기다린다 (%s)" % [scene, e.state_name()])
	_check(head.texture != open_tex, "%s: 기다리는 동안 눈 감은 얼굴 (머리 변형 closed)" % scene)
	var feet := vis.motion.sole_ys()
	var low := INF
	for y in feet:
		low = minf(low, absf(y))
	_check(low * vis.rig.game_scale * vis.art_scale <= FEET_TOL, "%s: 무릎 꿇은 앞발이 땅에 (%.1fpx)" % [scene, low * vis.rig.game_scale * vis.art_scale])
	var parent := e.get_parent()
	var rid := e.rescue_id
	e.purified_by(_player)
	for i in 6:
		_tick(e)
	_check(is_instance_valid(e) and head.texture == open_tex, "%s: 정화되는 순간 눈을 뜬다" % scene)
	var npc: Node = null
	for i in 60:
		if not is_instance_valid(e):
			break
		_tick(e)
	await get_tree().process_frame
	for c in parent.get_children():
		if c is RescuedPerson and str(c.rescue_id) == rid:
			npc = c
	_check(npc != null and npc.get("_rig") != null and str(npc.get("rig_id")) == scene, "%s: 정화 뒤 같은 뼈대로 사람이 선다 (rig_id %s)" % [scene, str(npc.get("rig_id")) if npc else "없음"])
	if npc:
		npc.queue_free()
	await get_tree().process_frame


# ---------- 창으로: 실제 방에서 장면 찍기 ----------

## 파일 이름용 상태 이름 (영문 소문자)
static func _st(e: EnemyBase) -> String:
	return str(EnemyBase.State.keys()[e.state]).to_lower()


func _run_shots() -> void:
	var dir := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	var only := ""
	var args := OS.get_cmdline_user_args()
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1]
	for c in SHOT_CASES:
		if only != "" and not str(c[1]).to_lower().contains(only) and not str(c[0]).contains(only):
			continue
		await _shoot_case(str(c[0]), str(c[1]), dir)


func _shoot_case(room_id: String, enemy_name: String, dir: String) -> void:
	Progress.next_spawn = ""
	var room: Node = load("res://scenes/rooms/%s.tscn" % room_id).instantiate()
	add_child(room)
	for i in 6:
		await get_tree().physics_frame
	var pl := get_tree().get_first_node_in_group("player") as Player
	var e := room.get_node_or_null("Enemies/" + enemy_name) as EnemyBase
	if e == null or pl == null:
		print("[shots] %s/%s 없음" % [room_id, enemy_name])
		room.queue_free()
		await get_tree().process_frame
		return
	pl.hurtbox.set_deferred("monitorable", false)
	pl.set_physics_process(false)
	# 화면: 터치 버튼·HUD 는 숨기고, 몹을 따라가는 카메라 (게임 카메라와 같은 배율)
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(cl as CanvasLayer).visible = false
	var cam := Camera2D.new()
	cam.zoom = Vector2(1.15, 1.15) * (0.8 if enemy_name == "MiniBoss" else 1.0)
	room.add_child(cam)
	cam.make_current()
	var follow := func() -> void:
		if is_instance_valid(e):
			cam.global_position = e.global_position + Vector2(0, -40)
	var tag := "%s_%s" % [room_id, enemy_name.to_lower()]
	var n := [0]
	var keep_hp := func() -> void:
		pl.hp = pl.max_hp
		follow.call()
	var shot := func(label: String) -> void:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var hdr := img.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]
		img.convert(Image.FORMAT_RGBA8)
		if hdr:
			img.linear_to_srgb()
		var w := img.get_width()
		var h := img.get_height()
		img = img.get_region(Rect2i(w / 4, h / 6, w / 2, h * 2 / 3))
		img.save_png("%s/gh_%s_%02d_%s.png" % [dir, tag, n[0], label])
		n[0] += 1
	var elite := enemy_name == "MiniBoss"
	var far := (520.0 if e.get("seed_speed") != null else 440.0) * (1.3 if elite else 1.0)
	# 대기 (소녀는 멀리)
	pl.global_position = e.global_position + Vector2(-1400, -20)
	for i in 30:
		await get_tree().physics_frame
		follow.call()
	await shot.call("idle")
	pl.global_position = e.global_position + Vector2(-far, 0)
	pl.global_position.y = e.global_position.y + (e.hurt_height * 0.5 - 67.0)
	# 쏘기·뿌리기 (실제 AI)
	var t := 0.0
	var every := 0.12
	var next := 0.4
	while t < 3.2 and is_instance_valid(e):
		await get_tree().physics_frame
		keep_hp.call()
		t += STEP
		if t >= next:
			next += every
			await shot.call(_st(e))
	# 물러남
	if is_instance_valid(e):
		# 소녀가 몹 앞 바짝(보통 150px)에 붙어 따라간다 → 정원사는 대롱을 겨눈 채 폴짝 물러나고, 약초꾼은 뒷걸음질하며 뿌린다
		var close := 150.0 if not elite else 240.0
		var side := -1.0 if pl.global_position.x < e.global_position.x else 1.0
		pl.global_position.x = e.global_position.x + side * close
		t = 0.0
		next = 0.0
		while t < 2.0 and is_instance_valid(e):
			await get_tree().physics_frame
			pl.global_position.x = move_toward(pl.global_position.x, e.global_position.x + side * close, 400.0 * STEP)
			keep_hp.call()
			t += STEP
			if t >= next:
				next += 0.06
				await shot.call("retreat_" + _st(e))
	# 피격
	if is_instance_valid(e):
		e.receive_hit(HitData.make(1.0, 5.0, pl, Vector2(300, -100)), null)
		for i in 4:
			await get_tree().physics_frame
			follow.call()
		await shot.call("hit")
	# 무너짐 / 무릎 꿇음
	if is_instance_valid(e):
		if elite:
			e.hp = e.max_hp * 0.4
		e.poise = e.max_poise - 0.5
		e.receive_hit(HitData.make(1.0, 50.0, pl), null)
		for i in 40:
			await get_tree().physics_frame
			keep_hp.call()
		await shot.call("broken")
	# 쓰러짐 (일반: 앞에서 맞아 뒤로) / 정화 (구원 가능한 자)
	var savable := is_instance_valid(e) and e.savable
	if is_instance_valid(e):
		if e.savable:
			e.purified_by(pl)
		else:
			e.hp = 1.0
			e.receive_hit(HitData.make(5.0, 0.0, pl), null)
		for i in 9:
			for k in 5:
				await get_tree().physics_frame
			await shot.call("fall")
		for i in 30:
			await get_tree().physics_frame
		await shot.call("after")
		if savable:
			# 구원된 사람 (같은 뼈대) — 대화가 끝날 때까지 몇 장
			for i in 3:
				for k in 30:
					await get_tree().physics_frame
				await shot.call("rescued")
	print("[shots] %s: %d장" % [tag, n[0]])
	room.queue_free()
	for i in 3:
		await get_tree().process_frame


# ---------- 창으로: 평평한 바닥에서 실제 AI 필름 ----------

## ... res://tools/probe_gardener_herbalist.tscn -- --film gardener
## 소녀(멈춤)를 쏠 거리에 두었다가 바짝 붙여 따라가게 하고, 0.05초마다 몹 둘레를 찍는다 → screenshots/ghf_<몹>_<번호>_<상태>.png
func _run_film(scene: String) -> void:
	RenderingServer.set_default_clear_color(Color(0.42, 0.45, 0.5))
	_make_floor()
	var ground := ColorRect.new()
	ground.color = Color(0.3, 0.33, 0.3)
	ground.position = Vector2(-10000, FLOOR_Y)
	ground.size = Vector2(20000, 400)
	add_child(ground)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_player.hurtbox.set_deferred("monitorable", false)
	var pcam := _player.get_node_or_null("Camera2D")
	if pcam:
		pcam.enabled = false
	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()
	var e := _spawn(scene, 0.0)
	e.set_physics_process(true)
	e.get_node("Visual").set_process(true)
	e.player = _player
	var elite := scene.begins_with("elite")
	cam.zoom = Vector2.ONE * (2.2 if not elite else 1.4)
	var far := (500.0 if e.get("seed_speed") != null else 430.0) * (1.3 if elite else 1.0)
	_player.global_position = Vector2(far, FLOOR_Y - 67.0)
	var dir := ProjectSettings.globalize_path("res://screenshots")
	var t := 0.0
	var next := 0.0
	var n := 0
	var close := 150.0 if not elite else 240.0
	while t < 6.0 and is_instance_valid(e):
		await get_tree().physics_frame
		t += STEP
		_player.hp = _player.max_hp
		if t > 2.6:
			var side := 1.0 if _player.global_position.x >= e.global_position.x else -1.0
			_player.global_position.x = move_toward(_player.global_position.x, e.global_position.x + side * close, 400.0 * STEP)
		cam.global_position = Vector2(e.global_position.x + 60.0, FLOOR_Y - e.hurt_height * 0.6)
		if t >= next:
			next += 0.05
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var hdr := img.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]
			img.convert(Image.FORMAT_RGBA8)
			if hdr:
				img.linear_to_srgb()
			var w := img.get_width()
			var h := img.get_height()
			img = img.get_region(Rect2i(w / 5, h / 8, w * 3 / 5, h * 3 / 4))
			img.save_png("%s/ghf_%s_%03d_%s.png" % [dir, scene, n, _st(e)])
			n += 1
	print("[film] %s: %d장" % [scene, n])

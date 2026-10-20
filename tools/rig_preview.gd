extends Node2D
## 부위 뼈대 확인 화면. **창으로** 띄워야 그림이 찍힌다 (--headless 를 빼고 실행; 병렬 작업이면 /Users/wj/Projects/SeedWT/godot 래퍼).
## 결과 그림은 screenshots/ 에 쓴다 (저장소에 올리지 않는다). 자세한 쓰는 법: RIGS.md
##
##   Godot --path . res://tools/rig_preview.tscn -- <id> [--poses idle,windup,strike] [--joints] [--hull]
##       자세마다 screenshots/rig_<id>_<자세>.png + 모아 보기 screenshots/rig_<id>_poses.png
##   Godot --path . res://tools/rig_preview.tscn -- <id> --parts [--cols 6]
##       부위마다 같은 크기 칸에 맞춰 그림 + 관절(빨강 pivot, 파랑 축 끝, 노랑 자식 관절, 초록 발바닥) + 이름·z·칸 배율:
##       screenshots/rig_<id>_parts.png
##   Godot --path . res://tools/rig_preview.tscn -- --enemy res://scenes/enemies/woodcutter.tscn [--seq idle,walk,attack,hit,broken,dead,kneel] [--joints]
##       동작: idle / walk / backstep / alert / attack / hit / broken / dead(뒤에서 맞아 앞으로) / dead_back(앞에서 맞아 뒤로) / kneel(구원형)
##             / slam (잿가지 거인 내려찍기) / aim (대롱 겨눔: arm_kind 를 gun 으로 바꾸고 소녀가 몹 앞을 위→아래로 돈다 — 정원사처럼 대롱 몹을 만들 때)
##       실제 몹 씬을 바닥 위에 세우고 동작을 차례로 돌려 0.05초(--every) 간격 필름 띠: screenshots/rig_<씬 이름>_<동작>.png
##       (상태는 EnemyBase 를 직접 바꿔 돌린다 — 판정·시간은 실제 게임과 같다)
##   공통: --zoom 2.5 (카메라 배율), --every 0.05 (필름 칸 간격, 초), --cols 5, --crop 0.5 (필름 칸에 남길 화면 몫)
##   자세 모드: --cam_y 0.5 / --cam_x 0 (카메라 자리, 키의 몇 배 — 발을 크게 보려면 --zoom 8 --cam_y 0.1),
##             --variant head@human (변형 그림 끼워 보기), --flash 0.7 (번쩍임 세기 보기), --nomat (셰이더 없이),
##             --lock (땅 닿기·내려놓기를 켜고 — 쓰러져 누운 자세 dead_lie·dead_back_lie 를 게임처럼 볼 때)

const FLOOR_Y := 600.0
## 동작마다 몹을 옮기는 간격 (게임 px) — 바닥은 동작 수에 맞춰 넓힌다
const SEQ_GAP := 1500.0

var _args := {}
## 바닥 너비의 절반 (게임 px). --enemy 는 동작 수 × SEQ_GAP 만큼 늘린다.
var _floor_half := 4000.0
var _cam: Camera2D
var _shots: Array = []
var _joints := false
var _hull := false


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var pos_args: Array[String] = []
	var i := 0
	while i < a.size():
		var s := a[i]
		if s.begins_with("--"):
			var key := s.substr(2)
			if i + 1 < a.size() and not a[i + 1].begins_with("--"):
				_args[key] = a[i + 1]
				i += 1
			else:
				_args[key] = "true"
		else:
			pos_args.append(s)
		i += 1
	_joints = _args.has("joints")
	_hull = _args.has("hull")
	RenderingServer.set_default_clear_color(Color(0.42, 0.45, 0.5))
	_cam = Camera2D.new()
	_cam.zoom = Vector2.ONE * float(_args.get("zoom", "2.5"))
	add_child(_cam)
	_cam.make_current()
	if _args.has("enemy"):
		_run_enemy.call_deferred(str(_args["enemy"]))
	elif not pos_args.is_empty():
		if _args.has("parts"):
			_run_parts.call_deferred(pos_args[0])
		else:
			_run_poses.call_deferred(pos_args[0])
	else:
		print("사용: ... res://tools/rig_preview.tscn -- <id> | --enemy <씬>")
		get_tree().quit(1)


func _out_dir() -> String:
	var d := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(d)
	return d


func _grab(crop := 1.0) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if crop < 1.0:
		var w := img.get_width()
		var h := img.get_height()
		var cw := int(w * crop)
		var ch := int(h * minf(crop * 1.3, 1.0))
		img = img.get_region(Rect2i((w - cw) / 2, (h - ch) / 2, cw, ch))
	# HDR 2D 화면은 선형 색 공간의 부동소수 그림을 돌려준다 → sRGB 8비트로 (안 그러면 어둡게 찍힌다)
	var hdr := img.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]
	img.convert(Image.FORMAT_RGBA8)
	if hdr:
		img.linear_to_srgb()
	return img


## 바닥 선 (게임 px)
func _draw() -> void:
	if _floor_half <= 0.0:
		return   # 부위 모드: 바닥 없음
	draw_line(Vector2(-_floor_half, FLOOR_Y), Vector2(_floor_half, FLOOR_Y), Color(0.2, 0.25, 0.2), 3.0)
	draw_rect(Rect2(-_floor_half, FLOOR_Y, _floor_half * 2.0, 400), Color(0.3, 0.33, 0.3))


# ---------- 자세 ----------

func _run_poses(id: String) -> void:
	var rig := PartRig.new()
	add_child(rig)
	if not rig.build(id):
		get_tree().quit(1)
		return
	rig.position = Vector2(0, FLOOR_Y)
	if _args.has("nomat"):
		rig.material = null   # 색 비교용: 셰이더 없이
	var motion := RigMotion.new(rig)
	var marks := _add_marks(rig, motion)
	var list: Array = []
	if _args.has("poses"):
		list = str(_args["poses"]).split(",")
	else:
		list = ["base", "idle", "walk", "alert", "windup", "strike", "ready", "hit", "broken", "kneel", "dead_knees", "lunge", "air"]
	var h := float(rig.data.get("height", 1000.0)) * rig.game_scale
	_cam.position = Vector2(float(_args.get("cam_x", "0")) * h, FLOOR_Y - h * float(_args.get("cam_y", "0.5")))
	var tiles: Array = []
	for pname in list:
		if not motion.has_pose(pname) and pname != "base":
			print("[rig_preview] 없는 자세: ", pname)
			continue
		motion.set_target(motion.pose(pname), RigMotion.Drive.NORMAL, RigMotion.Feet.AIR if pname == "air" else RigMotion.Feet.POSE)
		motion.ground_lock = 1.0 if _args.has("lock") else 0.0   # --lock: 쓰러진 자세처럼 땅 닿기(올리기)·내려놓기(붙이기)를 켜고 본다
		motion.ground_settle = 1.0 if _args.has("lock") else 0.0
		motion.snap_feet()
		for f in 150:
			motion.update(1.0 / 60.0, {"grounded": pname != "air"})
		marks.queue_redraw()
		if _args.has("flash"):
			rig.set_flash(float(_args["flash"]))
		if _args.has("variant"):
			var vv := str(_args["variant"]).split("@")   # --variant head@human
			rig.set_variant(vv[0], vv[1] if vv.size() > 1 else "")
		var img: Image = await _grab()
		var path := "%s/rig_%s_%s.png" % [_out_dir(), id, pname]
		img.save_png(path)
		tiles.append([pname, img])
		var feet := motion.sole_ys()
		print("[rig_preview] %s → %s (발바닥 y %s, 가장 낮은 점 %.1f)" % [pname, path, str(feet), rig.lowest_y()])
	_save_sheet(tiles, "%s/rig_%s_poses.png" % [_out_dir(), id])
	get_tree().quit()


func _save_sheet(tiles: Array, path: String) -> void:
	if tiles.is_empty():
		return
	var cols := int(_args.get("cols", "5"))
	var first: Image = tiles[0][1]
	var tw := first.get_width() / 2
	var th := first.get_height() / 2
	var rows := ceili(float(tiles.size()) / cols)
	var sheet := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.2, 0.2))
	for k in tiles.size():
		var img: Image = tiles[k][1].duplicate()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, tw, th), Vector2i((k % cols) * tw, (k / cols) * th))
	sheet.save_png(path)
	print("[rig_preview] 모아 보기 → ", path)


## 관절 표시 노드 (뼈대 위에 그린다)
func _add_marks(rig: PartRig, motion: RigMotion) -> Node2D:
	var m := Node2D.new()
	m.z_index = 50
	rig.add_child(m)
	m.draw.connect(func():
		if not _joints and not _hull:
			return
		for i in rig.xf.size():
			var t := rig.body_xf * rig.xf[i]
			var o := t.origin * rig.game_scale
			if _hull:
				var pts := PackedVector2Array()
				for q in rig.hulls[i]:
					pts.append((t * q) * rig.game_scale)
				if pts.size() > 2:
					pts.append(pts[0])
					m.draw_polyline(pts, Color(0, 1, 1, 0.6), 1.0)
			if _joints:
				var p := rig.parent[i]
				if p >= 0:
					m.draw_line((rig.body_xf * rig.xf[p]).origin * rig.game_scale, o, Color(1, 1, 0, 0.8), 1.5)
				m.draw_circle(o, 3.0, Color(1, 0.2, 0.2))
				if rig.has_axis[i] == 1:
					m.draw_line(o, (t * Vector2(0, rig.bone_len[i])) * rig.game_scale, Color(0.3, 0.6, 1.0, 0.7), 1.0)
		if _joints and motion:
			for leg in motion.legs:
				var t2 := rig.body_xf * rig.xf[leg.foot]
				m.draw_circle((t2 * leg.sole) * rig.game_scale, 3.5, Color(0.2, 1, 0.3))
		m.draw_line(Vector2(-300, 0), Vector2(300, 0), Color(1, 1, 1, 0.5), 1.0))
	return m


# ---------- 부위 ----------

func _run_parts(id: String) -> void:
	# 부위마다 같은 크기의 칸에 맞춰 키워(또는 줄여) 그린다 — 작은 부위(발·아래팔)의 관절 점도 읽히게. 칸 아래에 이름·z·배율.
	var data := PartRig.load_data(id)
	if data.is_empty():
		get_tree().quit(1)
		return
	var bones: Array = data["bones"]
	var font := ThemeDB.fallback_font
	_floor_half = 0.0
	queue_redraw()
	var holder := Node2D.new()
	add_child(holder)
	const CELL := 520.0
	const LABEL_H := 70.0
	var list: Array = []
	for b in bones:
		if b.has("tex"):
			list.append(b)
	var cols := mini(int(_args.get("cols", "6")), maxi(list.size(), 1))
	var rows := ceili(float(list.size()) / cols)
	for n in list.size():
		var b: Dictionary = list[n]
		var tex: Texture2D = load(b["tex"])
		if tex == null:
			continue
		var cell := Vector2((n % cols) * CELL, (n / cols) * (CELL + LABEL_H))
		var sz := tex.get_size()
		var k := minf((CELL - 40.0) / maxf(sz.x, 1.0), (CELL - 40.0) / maxf(sz.y, 1.0))
		var org := cell + (Vector2(CELL, CELL) - sz * k) * 0.5
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.scale = Vector2(k, k)
		spr.position = org
		holder.add_child(spr)
		var pv := PartRig._v(b["pivot"]) * k
		var info := {"pos": org, "cell": cell, "pv": pv, "name": str(b["name"]), "b": b, "k": k, "sz": sz * k}
		var mk := Node2D.new()
		mk.z_index = 10
		holder.add_child(mk)
		mk.draw.connect(func():
			var o: Vector2 = info["pos"] + info["pv"]
			mk.draw_rect(Rect2(info["cell"], Vector2(CELL, CELL)), Color(0, 0, 0, 0.18))
			mk.draw_rect(Rect2(info["pos"], info["sz"]), Color(1, 1, 1, 0.3), false, 2.0)
			var bb: Dictionary = info["b"]
			var rot := deg_to_rad(float(bb["rot"]))
			var ts := float(bb.get("tex_scale", 2.0))
			# 뼈 틀 → 텍스처 px: 회전을 되돌리고 tex_scale 로 나눈다 (칸 배율 k 를 곱한다)
			var to_tex := func(v: Vector2) -> Vector2: return o + v.rotated(-rot) / ts * float(info["k"])
			if bb.has("len"):
				mk.draw_line(o, to_tex.call(Vector2(0, float(bb["len"]))), Color(0.3, 0.6, 1), 4.0)
			if bb.has("sole"):
				mk.draw_circle(to_tex.call(PartRig._v(bb["sole"])), 10.0, Color(0.2, 1, 0.3))
			for c in bones:
				if c["parent"] == bb["name"]:
					mk.draw_circle(to_tex.call(PartRig._v(c["pos"])), 9.0, Color(1, 0.9, 0.2))
			mk.draw_circle(o, 11.0, Color(1, 0.2, 0.2))
			var label := "%s  z %d  ×%.2f" % [info["name"], int(bb.get("z", 0)), float(info["k"])]
			mk.draw_string_outline(font, info["cell"] + Vector2(10, CELL + 48), label, HORIZONTAL_ALIGNMENT_LEFT, CELL - 20, 40, 8, Color(0, 0, 0, 0.8))
			mk.draw_string(font, info["cell"] + Vector2(10, CELL + 48), label, HORIZONTAL_ALIGNMENT_LEFT, CELL - 20, 40, Color.WHITE))
	var total := Vector2(cols * CELL, rows * (CELL + LABEL_H))
	var vp := get_viewport().get_visible_rect().size
	_cam.zoom = Vector2.ONE * minf(vp.x / (total.x + 40.0), vp.y / (total.y + 40.0))
	_cam.position = total * 0.5
	var img: Image = await _grab()
	var path := "%s/rig_%s_parts.png" % [_out_dir(), id]
	img.save_png(path)
	print("[rig_preview] 부위 → ", path, "  (빨강 관절 · 파랑 축 · 노랑 자식 관절 · 초록 발바닥, 칸마다 배율이 다르다)")
	get_tree().quit()


# ---------- 실제 몹 ----------

func _run_enemy(scene_path: String) -> void:
	var seqs: Array = str(_args.get("seq", "idle,walk,attack,hit,broken,dead")).split(",")
	# 바닥: 동작마다 몹을 SEQ_GAP 씩 오른쪽으로 옮기므로 마지막 동작(걷기·밀림 포함)까지 덮게 넓힌다
	# (예전엔 ±4000 고정이라 넷째 동작부터 몹이 바닥 밖으로 떨어져 빈 필름이 찍혔다)
	_floor_half = seqs.size() * SEQ_GAP + 4000.0
	queue_redraw()
	var floor_body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(_floor_half * 2.0, 200)
	cs.shape = rect
	cs.position = Vector2(0, FLOOR_Y + 100)
	floor_body.add_child(cs)
	add_child(floor_body)
	var every := float(_args.get("every", "0.05"))
	var name := scene_path.get_file().get_basename()
	var seq_i := -1
	for seq in seqs:
		seq_i += 1
		var path := scene_path
		# 구원형 무릎 꿇기: <몹>_savable.tscn 이 있으면 그것으로 (오웬처럼 씬 자체가 구원형이면 그대로)
		if seq == "kneel" and not scene_path.contains("savable") and ResourceLoader.exists(scene_path.replace(".tscn", "_savable.tscn")):
			path = scene_path.replace(".tscn", "_savable.tscn")
		var e: EnemyBase = (load(path) as PackedScene).instantiate()
		if seq == "aim":
			e.get_node("Visual").set("arm_kind", "gun")   # _ready 전에 정해야 겨눌 뼈를 찾는다
		add_child(e)
		e.global_position = Vector2(seq_i * SEQ_GAP, FLOOR_Y - 80.0)   # 동작마다 자리를 옮긴다 (앞 동작의 묘목·사람이 안 겹치게)
		e.set_physics_process(false)
		e.facing = 1
		e.player = null
		e._timer = 999.0
		for f in 30:
			await get_tree().physics_frame
			_sim(e, 1.0 / 60.0, 0.0)
		var vis: Node = e.get_node("Visual")
		if _joints and vis.get("rig"):
			var mk := _add_marks(vis.rig, vis.motion)
			vis.set_meta("marks", mk)
		_cam.position = Vector2(e.global_position.x + 60.0, FLOOR_Y - 90.0 * float(vis.get("art_scale") if vis.get("art_scale") != null else 1.0))
		var cam_y0 := _cam.position.y
		var frames: Array = []
		var t := 0.0
		var next := 0.0
		var dur := 1.4
		var vx := 0.0
		var real_physics := false   # 몹 스크립트의 _physics_process 를 그대로 돌린다 (AI 를 쓰지 않는 동작만)
		var aim_target: Player = null
		match seq:
			"idle":
				dur = 1.2
			"walk":
				e._set_state(EnemyBase.State.CHASE)
				vx = e.walk_speed * e.chase_multiplier
				dur = 1.2
			"backstep":
				e._set_state(EnemyBase.State.BACKSTEP)
				vx = -e.walk_speed * 1.4
				dur = 0.6
			"attack":
				e._begin_windup()
				dur = e.windup_time + e.strike_time + e.recover_time + 0.4
			"hit":
				e.receive_hit(HitData.make(5.0, 20.0, null, Vector2(380, -150)), null)
				dur = 0.7
			"broken":
				e.poise = e.max_poise - 1.0
				e.receive_hit(HitData.make(1.0, 10.0, null), null)
				dur = 1.6
			"dead":
				e.hp = 1.0
				e.receive_hit(HitData.make(5.0, 10.0, null), null)
				dur = 0.8
			"dead_back":
				# 앞에서 맞아 뒤로 밀려 쓰러짐
				var src := Node2D.new()
				add_child(src)
				src.global_position = e.global_position + Vector2(120, 0)
				e.hp = 1.0
				if "_block_open" in e:
					e.set("_block_open", 99.0)   # 방패 몹(경비병): 방패를 든 채로 — 앞에서 친 공격을 막지 않게 (probe_rigs 와 같게)
				e.receive_hit(HitData.make(5.0, 10.0, src), null)
				src.queue_free()
				dur = 0.8
			"kneel":
				e.hp = 1.0
				e.receive_hit(HitData.make(5.0, 10.0, null), null)
				dur = 1.2
			"alert":
				e._alert()
				dur = 0.9
			"aim":
				# 소녀(처리 끔, 카메라 뺌)를 몹 앞 반원 위에서 위 → 아래로 옮긴다. 대롱 축이 따라오는지 본다.
				aim_target = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
				var pcam := aim_target.get_node_or_null("Camera2D")
				if pcam:
					aim_target.remove_child(pcam)
					pcam.free()
				add_child(aim_target)
				aim_target.set_physics_process(false)
				aim_target.set_process(false)
				_cam.make_current()
				e.player = aim_target
				e._set_state(EnemyBase.State.CHASE)
				dur = 1.6
			"slam":
				# 잿가지 거인의 뛰어올라 내려찍기 (그 몹 스크립트의 물리를 그대로 돌린다)
				if "_slamming" in e:
					e._set_state(EnemyBase.State.STRIKE)
					e._timer = 1.6
					e._slamming = true
					e._airborne = false
					e.anim_hint = "leap"
					e.velocity = Vector2(300.0, -980.0)
					real_physics = true
				dur = 1.9
		while t < dur and is_instance_valid(e):
			await get_tree().physics_frame
			if not is_instance_valid(e):
				break
			if real_physics:
				e._physics_process(1.0 / 60.0)
			else:
				_sim(e, 1.0 / 60.0, vx)
			if not is_instance_valid(e) or e.is_queued_for_deletion():
				break
			# 공격 흐름: 예고 → 타격 → 회복 → 대기
			if seq == "attack":
				if e.state == EnemyBase.State.WINDUP and e._timer <= 0.0:
					e._strike()
				elif e.state == EnemyBase.State.STRIKE and e._timer <= 0.0:
					e._set_state(EnemyBase.State.RECOVER)
					e._timer = e.recover_time
				elif e.state == EnemyBase.State.RECOVER and e._timer <= 0.0:
					e._set_state(EnemyBase.State.IDLE)
					e._timer = 999.0
			elif e.state == EnemyBase.State.HIT and e._timer <= 0.0:
				e._set_state(EnemyBase.State.IDLE)
				e._timer = 999.0
			if aim_target:
				var ang := lerpf(-0.75, 0.55, clampf(t / (dur - 0.2), 0.0, 1.0))
				aim_target.global_position = e.global_position + Vector2(cos(ang), sin(ang)) * 420.0 + Vector2(0, -40)
			if seq in ["walk", "backstep", "slam"]:
				_cam.position.x = e.global_position.x + 60.0
			if seq == "slam":
				_cam.position.y = minf(cam_y0, e.global_position.y - 40.0)   # 뛰어오르면 따라 올라간다
			t += 1.0 / 60.0
			if t >= next:
				next += every
				if vis.has_meta("marks"):
					(vis.get_meta("marks") as Node2D).queue_redraw()
				var img: Image = await _grab(float(_args.get("crop", "0.5")))
				frames.append(["%.2f %s" % [t, e.state_name()], img])
		var out := "%s/rig_%s_%s.png" % [_out_dir(), name, seq]
		_save_sheet(frames, out)
		if frames.size() > 0:
			(frames[frames.size() / 2][1] as Image).save_png(out.replace(".png", "_mid.png"))
		if is_instance_valid(e):
			e.queue_free()
		if aim_target:
			aim_target.queue_free()
		await get_tree().physics_frame
	get_tree().quit()


## 몹을 한 틱 돌린다: 타이머·진행도만 (AI 는 끄고), 중력, 정해 준 가로 속도.
func _sim(e, dt: float, vx: float) -> void:
	if not is_instance_valid(e):
		return
	e._tick_common(dt)
	if not e.is_on_floor():
		e.velocity.y += e.gravity * dt
	if e.state in [EnemyBase.State.CHASE, EnemyBase.State.BACKSTEP, EnemyBase.State.PATROL]:
		e.velocity.x = vx
	elif e.state == EnemyBase.State.STRIKE:
		e.velocity.x = move_toward(e.velocity.x, e.facing * 160.0, 3000.0 * dt)
	else:
		e.velocity.x = move_toward(e.velocity.x, 0.0, 1400.0 * dt)
	if e.state == EnemyBase.State.DEAD and e._dying and not e._fall_done and e._timer <= 0.0:
		e._fall_done = true
		e._finish_fall()
		return
	e.move_and_slide()

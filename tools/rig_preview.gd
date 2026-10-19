extends Node2D
## 부위 뼈대 확인 화면. **창으로** 띄워야 그림이 찍힌다 (--headless 를 빼고 실행; 병렬 작업이면 /Users/wj/Projects/SeedWT/godot 래퍼).
## 결과 그림은 screenshots/ 에 쓴다 (저장소에 올리지 않는다). 자세한 쓰는 법: RIGS.md
##
##   Godot --path . res://tools/rig_preview.tscn -- <id> [--poses idle,windup,strike] [--joints] [--hull]
##       자세마다 screenshots/rig_<id>_<자세>.png + 모아 보기 screenshots/rig_<id>_poses.png
##   Godot --path . res://tools/rig_preview.tscn -- <id> --parts
##       부위마다 그림 + 관절(빨강 pivot, 파랑 축 끝, 노랑 자식 관절, 초록 발바닥): screenshots/rig_<id>_parts.png
##   Godot --path . res://tools/rig_preview.tscn -- --enemy res://scenes/enemies/woodcutter.tscn [--seq idle,walk,attack,hit,broken,dead,kneel] [--joints]
##       실제 몹 씬을 바닥 위에 세우고 동작을 차례로 돌려 0.05초(--every) 간격 필름 띠: screenshots/rig_<씬 이름>_<동작>.png
##       (상태는 EnemyBase 를 직접 바꿔 돌린다 — 판정·시간은 실제 게임과 같다)
##   공통: --zoom 2.5 (카메라 배율), --every 0.05 (필름 칸 간격, 초), --cols 5, --crop 0.5 (필름 칸에 남길 화면 몫)
##   자세 모드: --cam_y 0.5 / --cam_x 0 (카메라 자리, 키의 몇 배 — 발을 크게 보려면 --zoom 8 --cam_y 0.1)

const FLOOR_Y := 600.0

var _args := {}
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
	draw_line(Vector2(-4000, FLOOR_Y), Vector2(4000, FLOOR_Y), Color(0.2, 0.25, 0.2), 3.0)
	draw_rect(Rect2(-4000, FLOOR_Y, 8000, 400), Color(0.3, 0.33, 0.3))


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
		motion.snap_feet()
		for f in 150:
			motion.update(1.0 / 60.0, {"grounded": pname != "air"})
		marks.queue_redraw()
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
	var data := PartRig.load_data(id)
	if data.is_empty():
		get_tree().quit(1)
		return
	var bones: Array = data["bones"]
	var x := -1300.0
	var y := 0.0
	var row_h := 0.0
	var font := ThemeDB.fallback_font
	var holder := Node2D.new()
	add_child(holder)
	for b in bones:
		var tex: Texture2D = load(b["tex"])
		if tex == null:
			continue
		var k := 1.0
		var sz := tex.get_size() * k
		if x + sz.x > 1300.0:
			x = -1300.0
			y += row_h + 50.0
			row_h = 0.0
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.centered = false
		spr.scale = Vector2(k, k)
		spr.position = Vector2(x, y)
		holder.add_child(spr)
		var pv := PartRig._v(b["pivot"]) * k
		var info := {"pos": Vector2(x, y), "pv": pv, "name": str(b["name"]), "b": b, "k": k, "sz": sz}
		var mk := Node2D.new()
		mk.z_index = 10
		holder.add_child(mk)
		mk.draw.connect(func():
			var o: Vector2 = info["pos"] + info["pv"]
			mk.draw_rect(Rect2(info["pos"], info["sz"]), Color(1, 1, 1, 0.25), false, 1.0)
			mk.draw_circle(o, 5.0, Color(1, 0.2, 0.2))
			var bb: Dictionary = info["b"]
			var rot := deg_to_rad(float(bb["rot"]))
			var ts := float(bb.get("tex_scale", 2.0))
			# 뼈 틀 → 텍스처 px: 회전을 되돌리고 tex_scale 로 나눈다
			var to_tex := func(v: Vector2) -> Vector2: return o + v.rotated(-rot) / ts * float(info["k"])
			if bb.has("len"):
				mk.draw_line(o, to_tex.call(Vector2(0, float(bb["len"]))), Color(0.3, 0.6, 1), 2.0)
			if bb.has("sole"):
				mk.draw_circle(to_tex.call(PartRig._v(bb["sole"])), 5.0, Color(0.2, 1, 0.3))
			for c in bones:
				if c["parent"] == bb["name"]:
					mk.draw_circle(to_tex.call(PartRig._v(c["pos"])), 4.0, Color(1, 0.9, 0.2))
			mk.draw_string(font, info["pos"] + Vector2(0, -6), "%s (z %d)" % [info["name"], int(bb.get("z", 0))], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE))
		x += sz.x + 30.0
		row_h = maxf(row_h, sz.y)
	var total_h := y + row_h + 40.0
	_cam.zoom = Vector2.ONE * minf(1920.0 / 2700.0, 1080.0 / total_h)
	_cam.position = Vector2(0, total_h * 0.5 - 20.0)
	var img: Image = await _grab()
	var path := "%s/rig_%s_parts.png" % [_out_dir(), id]
	img.save_png(path)
	print("[rig_preview] 부위 → ", path)
	get_tree().quit()


# ---------- 실제 몹 ----------

func _run_enemy(scene_path: String) -> void:
	var floor_body := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8000, 200)
	cs.shape = rect
	cs.position = Vector2(0, FLOOR_Y + 100)
	floor_body.add_child(cs)
	add_child(floor_body)
	var seqs: Array = str(_args.get("seq", "idle,walk,attack,hit,broken,dead")).split(",")
	var every := float(_args.get("every", "0.05"))
	var name := scene_path.get_file().get_basename()
	for seq in seqs:
		var path := scene_path
		if seq == "kneel" and not scene_path.contains("savable"):
			path = scene_path.replace(".tscn", "_savable.tscn")
		var e: EnemyBase = (load(path) as PackedScene).instantiate()
		add_child(e)
		e.global_position = Vector2(0, FLOOR_Y - 80.0)
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
		var frames: Array = []
		var t := 0.0
		var next := 0.0
		var dur := 1.4
		var vx := 0.0
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
			"kneel":
				e.hp = 1.0
				e.receive_hit(HitData.make(5.0, 10.0, null), null)
				dur = 1.2
			"alert":
				e._alert()
				dur = 0.9
		while t < dur and is_instance_valid(e):
			await get_tree().physics_frame
			if not is_instance_valid(e):
				break
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
			if seq == "walk" or seq == "backstep":
				_cam.position.x = e.global_position.x + 60.0
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

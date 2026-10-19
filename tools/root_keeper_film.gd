extends Node2D
## 뿌리지기 동작 필름 (창으로 띄운다 — 화면이 있어야 찍힌다; 병렬 작업이면 /Users/wj/Projects/SeedWT/godot 래퍼).
## 실제 보스 씬(scenes/bosses/root_keeper.tscn)을 바닥 위에 세우고 동작을 하나씩 걸어 일정 간격으로 찍어 띠 그림으로 모은다.
## 보스의 논리(_physics_process)는 그대로 돈다 — 판정·시간은 게임과 같다. 자세 상태에서 스스로 공격을 고르지 않게 타이머만 붙잡는다.
##
##   Godot --path . --resolution 1600x900 res://tools/root_keeper_film.tscn -- [--seq idle,walk,SWEEP,...] [--every 0.1] [--zoom 1.2] [--cols 6] [--phase 2]
##   동작: idle / walk / back / turn / hit / stagger / broken / rise / fallen / purified / intro / 공격 이름(SPIKES SWEEP SWEEP2 ORBS HAND SEEDS RING WALL STOMP)
##   결과: screenshots/rk_film_<동작>.png (+ 가운데 칸 _mid.png). 칸 위에 시각·상태·단계.
## 마지막에 보스 그림의 땅 닿기 수치(뿌리 발바닥·치마 끝·가장 낮은 몸 점, 게임 px)를 동작마다 찍는다.

const FLOOR_Y := 600.0
const GAP := 2600.0

var _args := {}
var _cam: Camera2D
var _boss: RootKeeper
var _player: Player
var _hold := true
var _font: Font


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var s := a[i]
		if s.begins_with("--"):
			if i + 1 < a.size() and not a[i + 1].begins_with("--"):
				_args[s.substr(2)] = a[i + 1]
				i += 1
			else:
				_args[s.substr(2)] = "true"
		i += 1
	_font = ThemeDB.fallback_font
	RenderingServer.set_default_clear_color(Color(0.42, 0.45, 0.5))
	Settings.set_value("screen_shake", false)
	_cam = Camera2D.new()
	_cam.zoom = Vector2.ONE * float(_args.get("zoom", "1.6"))
	add_child(_cam)
	_cam.make_current()
	_run.call_deferred()


func _draw() -> void:
	draw_rect(Rect2(-4000, FLOOR_Y, 200000, 600), Color(0.3, 0.33, 0.3))
	draw_line(Vector2(-4000, FLOOR_Y), Vector2(196000, FLOOR_Y), Color(0.15, 0.2, 0.15), 2.0)


func _physics_process(_d: float) -> void:
	if _hold and _boss and _boss.state == RootKeeper.State.STANCE:
		_boss._timer = 99.0


func _run() -> void:
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape2D.new()
	# 끝없는 바닥 (아주 긴 사각형은 정밀도 때문에 돌진하는 보스가 바닥을 '벽'으로 부딪혔다)
	var plane := WorldBoundaryShape2D.new()
	plane.normal = Vector2.UP
	cs.shape = plane
	cs.position = Vector2(0, FLOOR_Y)
	floor_body.add_child(cs)
	add_child(floor_body)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var pcam := _player.get_node_or_null("Camera2D")
	if pcam:
		_player.remove_child(pcam)
		pcam.free()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player._invuln_timer = 99999.0
	_cam.make_current()
	_boss = (load("res://scenes/bosses/root_keeper.tscn") as PackedScene).instantiate()
	add_child(_boss)
	_boss.ground_y = FLOOR_Y
	_boss.arena = Rect2(-3000, FLOOR_Y - 1200, 200000, 1200)
	await get_tree().physics_frame
	if _args.has("poses"):
		await _pose_sheet(str(_args["poses"]).split(","))
		get_tree().quit()
		return
	var seqs: Array = str(_args.get("seq", "idle,walk,back,SPIKES,SWEEP,SWEEP2,ORBS,HAND,SEEDS,RING,WALL,STOMP,stagger,hit,broken,rise,fallen,purified,intro")).split(",")
	var every := float(_args.get("every", "0.1"))
	var ph := int(_args.get("phase", "1"))
	var report: Array = []
	var k := 0
	for seq in seqs:
		var bx := float(k) * GAP
		k += 1
		_reset(bx, ph)
		var dur := 1.6
		var px := bx - 500.0
		var follow := false
		match seq:
			"idle":
				dur = 2.4
			"walk":
				px = bx - 1500.0
				follow = true
				dur = 2.4
			"back":
				px = bx - 160.0
				follow = true
				dur = 1.8
			"turn":
				px = bx + 500.0
				dur = 1.0
			"intro":
				_boss.reset_fight()
				_boss.global_position = Vector2(bx, FLOOR_Y)
				_boss.arena = Rect2(bx - 2000.0, FLOOR_Y - 1200, 4000, 1200)
				dur = 2.8
		_player.global_position = Vector2(px, FLOOR_Y - 67.0)
		_cam.position = Vector2(bx + float(_args.get("camx", "-60")), FLOOR_Y - float(_args.get("camy", "250")))
		await _settle_frames(30)
		match seq:
			"hit":
				_boss.receive_hit(HitData.make(5.0, 10.0, _player, Vector2(380, -150)), null)
				dur = 0.8
			"stagger":
				_boss.force_pattern("SWEEP")
				dur = 2.2
			"broken":
				_boss.poise = _boss.max_poise - 1.0
				_boss.receive_hit(HitData.make(1.0, 50.0, _player), null)
				dur = 3.4
			"rise":
				_boss.hp = _boss.max_hp * 0.51
				_boss.receive_hit(HitData.make(30.0, 0.0, _player), null)
				dur = 3.4
			"fallen", "purified":
				_boss.hp = 1.0
				_boss.receive_hit(HitData.make(5.0, 0.0, _player), null)
				dur = 3.0 if seq == "fallen" else 4.2
			"intro":
				_hold = true
				_boss.start_fight(_player)
				_boss.global_position = Vector2(bx, FLOOR_Y)
				_player.global_position = Vector2(bx - 700.0, FLOOR_Y - 67.0)
			_:
				if seq == seq.to_upper():
					_boss.force_pattern(seq)
					dur = _boss.startup_len + 3.0
		var frames: Array = []
		var t := 0.0
		var next := 0.0
		var lows := {"sole": 0.0, "hem": -INF, "body": -INF, "n": 0}
		var parried := false
		var purified := false
		while t < dur:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			if seq == "stagger" and not parried and _boss.attack_phase == "active":
				parried = true
				_boss.on_just_guarded(_player, 10.0)
			if seq == "purified" and not purified and t > 1.8:
				purified = true
				_boss.purified_by(_player)
			if seq == seq.to_upper() and _boss.state == RootKeeper.State.STANCE and t > _boss.startup_len + 0.2:
				dur = minf(dur, t + 0.35)
			if follow or seq == "WALL":
				_cam.position.x = _boss.global_position.x + float(_args.get("camx", "-60"))
			_measure(lows)
			if _args.has("trace"):
				print("[trace] %.2f %s %s x=%.0f vx=%.0f wall=%s floor=%s col=%s" % [t, _boss.state_name(), _boss.attack_phase, _boss.global_position.x, _boss.velocity.x, _boss.is_on_wall(), _boss.is_on_floor(), _boss.get_last_slide_collision().get_collider() if _boss.get_last_slide_collision() else null])
			if t >= next:
				next += every
				var img := await _grab(float(_args.get("crop", "0.6")))
				frames.append(["%.2f %s %s" % [t, _boss.state_name(), _boss.attack_phase], img])
		if _args.has("bones"):
			_print_bones(seq)
		var out := ProjectSettings.globalize_path("res://screenshots/rk_film_%s.png" % seq)
		_save_sheet(frames, out)
		if frames.size() > 0:
			(frames[frames.size() / 2][1] as Image).save_png(out.replace(".png", "_mid.png"))
		report.append("%s: 뿌리 발바닥 최대 어긋남 %.1fpx, 치마 끝 가장 낮음 %+.1fpx, 몸 가장 낮음 %+.1fpx, 지팡이 가장 낮음 %+.1fpx (땅 아래 +)" % [seq, lows["sole"], lows["hem"], lows["body"], lows.get("staff", 0.0)])
		print("[film] %s → %s (%d칸)" % [seq, out, frames.size()])
	for r in report:
		print("[film] ", r)
	get_tree().quit()


## 자세 모음: 보스를 자세 상태에 두고 그림만 그 자세로 세워(debug_pose) 1.5초 뒤 찍는다 → screenshots/rk_poses.png
func _pose_sheet(names: Array) -> void:
	var vis = _boss.get_node("Sprite")
	var tiles: Array = []
	var k := 0
	for nm in names:
		var bx := float(k) * GAP
		k += 1
		_reset(bx, int(_args.get("phase", "1")))
		_player.global_position = Vector2(bx - 500.0, FLOOR_Y - 67.0)
		_cam.position = Vector2(bx + float(_args.get("camx", "-60")), FLOOR_Y - float(_args.get("camy", "250")))
		vis.debug_pose = nm
		await _settle_frames(int(float(_args.get("hold", "1.5")) * 60.0))
		var img := await _grab(float(_args.get("crop", "0.6")))
		tiles.append([nm, img])
		img.save_png(ProjectSettings.globalize_path("res://screenshots/rk_pose_%s.png" % nm))
		print("[film] 자세 %s" % nm)
	vis.debug_pose = ""
	_save_sheet(tiles, ProjectSettings.globalize_path("res://screenshots/rk_poses.png"))


func _reset(bx: float, ph: int) -> void:
	for n in get_tree().get_nodes_in_group("root_effect"):
		n.queue_free()
	_hold = true
	_boss.visible = true
	_boss.player = _player
	_boss.phase = ph
	_boss.hp = _boss.max_hp * (0.4 if ph == 2 else 1.0)
	_boss.poise = 0.0
	_boss._poise_immune = 0.0
	_boss._events.clear()
	_boss._chain = -1
	_boss._last_attack = -1
	_boss.hitbox.deactivate()
	_boss._set_state(RootKeeper.State.STANCE)
	_boss._timer = 99.0
	_boss.velocity = Vector2.ZERO
	_boss.facing = -1
	_boss.global_position = Vector2(bx, FLOOR_Y)


func _settle_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## 그림의 땅 닿기: 뿌리 발바닥(딛은 발만), 치마(hips) 껍질의 가장 낮은 점, 몸(몸통·머리·팔)의 가장 낮은 점 — 게임 px, 땅 아래 +
func _measure(lows: Dictionary) -> void:
	var vis = _boss.get_node("Sprite")
	var rig: PartRig = vis.rig
	var m: RigMotion = vis.motion
	if rig == null or m == null:
		return
	var gs := rig.game_scale
	var ys := m.sole_ys()
	for k in ys.size():
		var leg: RigMotion.Leg = m.legs[k]
		if not leg.swing and m.feet_mode != RigMotion.Feet.AIR:
			lows["sole"] = maxf(lows["sole"], absf(ys[k]) * gs)
	lows["hem"] = maxf(lows["hem"], rig.lowest_y(PackedInt32Array([rig.bone_index("hips")])) * gs)
	var body := PackedInt32Array()
	for nm in ["torso", "head", "arm_b_up", "arm_b_lo", "arm_f_up", "arm_f_lo", "hand_f"]:
		body.append(rig.bone_index(nm))
	lows["body"] = maxf(lows["body"], rig.lowest_y(body) * gs)
	var staff := PackedInt32Array([rig.bone_index("staff"), rig.bone_index("staff_lo")])
	var sl := rig.lowest_y(staff) * gs
	lows["staff"] = maxf(float(lows.get("staff", -INF)), sl)
	if _args.has("trace") and sl > 2.0:
		var hand := rig.body_xf * rig.xf[rig.bone_index("staff")].origin
		print("[trace] 지팡이 땅 아래 %.1fpx (손잡이 y %.1f)" % [sl, hand.y * gs])


## 동작 끝에서 부위마다 가장 낮은 점 (게임 px, 땅 아래 +) — 땅에 박히거나 몸을 받쳐 띄우는 부위 찾기
func _print_bones(seq: String) -> void:
	var vis = _boss.get_node("Sprite")
	var rig: PartRig = vis.rig
	var m: RigMotion = vis.motion
	var parts := []
	for i in rig.names.size():
		var low := rig.lowest_y(PackedInt32Array([i])) * rig.game_scale
		if low > -12.0:
			parts.append("%s %+.1f" % [rig.names[i], low])
	print("[bones] %s: 발바닥 %s, 땅 닿기 들어 올림 %.1f, 지팡이 돌림 %.1f도, %s" % [seq, str(m.sole_ys()), rig.body_xf.origin.y * rig.game_scale, rad_to_deg(vis._staff_fix), ", ".join(parts)])


func _grab(crop := 1.0) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if crop < 1.0:
		var w := img.get_width()
		var h := img.get_height()
		var cw := int(w * crop)
		var ch := int(h * float(_args.get("croph", "0.95")))
		img = img.get_region(Rect2i((w - cw) / 2, (h - ch) / 2, cw, ch))
	var hdr := img.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]
	img.convert(Image.FORMAT_RGBA8)
	if hdr:
		img.linear_to_srgb()
	return img


func _save_sheet(tiles: Array, path: String) -> void:
	if tiles.is_empty():
		return
	var cols := int(_args.get("cols", "6"))
	var first: Image = tiles[0][1]
	var shrink := float(_args.get("shrink", "0.5"))
	var tw := int(first.get_width() * shrink)
	var th := int(first.get_height() * shrink)
	var rows := ceili(float(tiles.size()) / cols)
	var sheet := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.2, 0.2))
	for k in tiles.size():
		var img: Image = (tiles[k][1] as Image).duplicate()
		img.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, tw, th), Vector2i((k % cols) * tw, (k / cols) * th))
	sheet.save_png(path)

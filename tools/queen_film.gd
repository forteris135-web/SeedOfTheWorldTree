extends Node2D
## 수액의 여왕 그림 확인 도구 (창으로 띄운다 — --headless 를 빼고). 병렬 작업 폴더에서는 Godot 래퍼로.
##   Godot --path . --resolution 1600x900 res://tools/queen_film.tscn -- --film [--seq hover,dust,...] [--every 0.1] [--zoom 1.6]
##       실제 보스 씬(scenes/bosses/sap_queen.tscn)을 바닥 위에 띄우고, 보스의 상태·박자 값을 손으로 돌려(물리·음악 없이 — 판정은 안 씀)
##       그림이 상태마다 어떻게 움직이는지 필름 띠로 찍는다: screenshots/queen_<동작>.png (+ 가운데 칸 _mid.png)
##       동작: hover / turn / hit / dust / wave / butterflies / land (예고 → 내리꽂기 → 받음 → 쉼 → 날아오름) / crack /
##             broken (공중 → 섬에 앉음 → 날아오름) / fallen (공중 → 쓰러져 누움 → 정화)
##   Godot --path . --resolution 1920x1080 res://tools/queen_film.tscn -- --game
##       진짜 보스 방(sap_lake_boss)에서 실제 싸움(보스곡 박자 그대로)을 돌리며 장면마다 한 장씩: screenshots/queen_game_<장면>.png
##       (소녀는 무적, 1페이즈 패턴을 다 본 뒤 2페이즈 → 내려앉으면 무너뜨림 → 쓰러뜨림 → 정화. 회상으로 넘어가지 않게 막는다)
##   Godot --path . res://tools/queen_film.tscn -- --render
##       떠 있는 자세의 조립 그림 한 장을 투명 배경으로: art/bosses/boss_sap_queen_now.png (1536×1024, 발끝 = 아래 가운데에서 60px 위)
##       (뼈대를 못 읽을 때 보스가 대신 띄우는 그림이자 ART_PROMPTS·확장판 문서의 '여왕 지금' 자리)
## 결과 그림은 screenshots/ 에 쓴다 (저장소에 올리지 않는다). 바닥 선 = 보스 원점(발이 닿는 땅).

const FLOOR_Y := 600.0
const BEAT := 60.0 / 138.0
const RENDER_SIZE := Vector2i(1536, 1024)
const RENDER_ZOOM := 2.4
const RENDER_FOOT_MARGIN := 60

var _args := {}
var _cam: Camera2D
var _boss: SapQueen
var _vis: Node
var _clock := 0.0
var _last_beat := -1


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
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
		i += 1
	RenderingServer.set_default_clear_color(Color(0.36, 0.42, 0.46))
	if _args.has("render"):
		_render.call_deferred()
	elif _args.has("game"):
		_game.call_deferred()
	else:
		_film.call_deferred()


func _draw() -> void:
	if _args.has("render"):
		return
	draw_rect(Rect2(-20000, FLOOR_Y, 40000, 600), Color(0.22, 0.27, 0.27))
	draw_line(Vector2(-20000, FLOOR_Y), Vector2(20000, FLOOR_Y), Color(0.75, 0.95, 1.0, 0.6), 2.0)


func _out(name: String) -> String:
	var d := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(d)
	return d + "/" + name


func _grab(vp: Viewport, crop := 1.0) -> Image:
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if crop < 1.0:
		var w := img.get_width()
		var h := img.get_height()
		var cw := int(w * crop)
		var ch := int(h * minf(crop * 1.25, 1.0))
		img = img.get_region(Rect2i((w - cw) / 2, (h - ch) / 2, cw, ch))
	var hdr := img.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]
	img.convert(Image.FORMAT_RGBA8)
	if hdr:
		img.linear_to_srgb()
	return img


func _save_sheet(tiles: Array, path: String, cols: int, tile := 0.5) -> void:
	if tiles.is_empty():
		return
	var first: Image = tiles[0]
	var tw := int(first.get_width() * tile)
	var th := int(first.get_height() * tile)
	var rows := ceili(float(tiles.size()) / cols)
	var sheet := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.15, 0.15, 0.15))
	for k in tiles.size():
		var img: Image = (tiles[k] as Image).duplicate()
		img.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, tw, th), Vector2i((k % cols) * tw, (k / cols) * th))
	sheet.save_png(path)
	print("[queen_film] → ", path)


# ---------- 보스 손으로 돌리기 ----------

func _spawn(parent: Node, pos: Vector2) -> void:
	_boss = (load("res://scenes/bosses/sap_queen.tscn") as PackedScene).instantiate()
	if _args.has("fallback"):
		_boss.get_node("Sprite").set("rig_id", "__없는_뼈대__")   # 뼈대를 못 읽었을 때 한 장 그림이 제자리에 뜨는지
	parent.add_child(_boss)
	_boss.set_physics_process(false)
	_boss.visible = true
	_boss.arena = Rect2(-1500, -200, 3000, 1000)
	_boss.ground_y = FLOOR_Y
	_boss.surface_y = FLOOR_Y + 40.0
	_boss.global_position = pos
	_boss.facing = 1
	_boss.state = SapQueen.State.HOVER
	_vis = _boss.get_node("Sprite")
	_vis.set_process(false)
	# --nowings : 날개를 숨겨 팔·몸 자세만 본다 (자세 다듬기용)
	if _args.has("nowings") and _vis.get("rig"):
		for nm in ["wing_uf", "wing_ub", "wing_lf", "wing_lb"]:
			var spr: Sprite2D = _vis.rig.sprite_of(nm)
			if spr:
				spr.visible = false
	_clock = 0.0
	_last_beat = -1


## 한 틱: 메트로놈(박 신호)·피격 번쩍임·예고 값만 돌리고 그림을 한 프레임 움직인다.
func _tick(dt: float) -> void:
	_clock += dt
	_boss._clock = _clock
	var b := int(floorf(_clock / BEAT)) % 3
	if b != _last_beat:
		_last_beat = b
		_boss.beat.emit(b)
	_boss._flash = maxf(_boss._flash - dt * 6.0, 0.0)
	if _boss.attack_phase != "startup":
		_boss.telegraph_amount = maxf(_boss.telegraph_amount - dt * 4.0, 0.0)
	_vis._process(dt)


## 공격 국면 하나를 시작 (논리의 _begin/_phase_step 과 같은 값)
func _phase(ph: String, length: float) -> void:
	_boss.attack_phase = ph
	_boss._phase_end = _clock + length
	match ph:
		"startup": _boss.startup_len = length
		"active": _boss.active_len = length
		"recovery": _boss.recovery_len = length


func _film() -> void:
	_cam = Camera2D.new()
	_cam.zoom = Vector2.ONE * float(_args.get("zoom", "1.6"))
	add_child(_cam)
	_cam.make_current()
	queue_redraw()
	var seqs: Array = str(_args.get("seq", "hover,turn,hit,dust,wave,butterflies,land,crack,broken,fallen")).split(",")
	var every := float(_args.get("every", "0.1"))
	var cols := int(_args.get("cols", "8"))
	var crop := float(_args.get("crop", "0.55"))
	var tile := float(_args.get("tile", "0.5"))
	# --at 0.5,1.2 : 그 시각의 장면만 크게 (screenshots/queen_<동작>_at.png)
	var ats: Array = []
	if _args.has("at"):
		for x in str(_args["at"]).split(","):
			ats.append(float(x))
	for seq in seqs:
		_spawn(self, Vector2(0, FLOOR_Y - 260.0))
		_cam.position = Vector2(0, FLOOR_Y - 330.0)
		var frames: Array = []
		var t := 0.0
		var next := 0.0
		var dt := 1.0 / 60.0
		var plan := _plan(seq)
		var total: float = plan["dur"]
		var events: Array = plan["events"]
		var ev_i := 0
		var at_i := 0
		var at_frames: Array = []
		# 자리 잡기 (찍지 않음)
		for k in 40:
			_boss.global_position = Vector2(0, FLOOR_Y - 260.0 + sin(k * dt * 2.0) * 16.0)
			_tick(dt)
		while t < total:
			while ev_i < events.size() and t >= float(events[ev_i][0]):
				(events[ev_i][1] as Callable).call()
				ev_i += 1
			(plan["each"] as Callable).call(t, dt)
			_tick(dt)
			# 카메라: 보스를 따라가되 바닥 선이 늘 보이게
			_cam.position = Vector2(_boss.global_position.x, minf(_boss.global_position.y - 130.0, FLOOR_Y - 110.0))
			await get_tree().process_frame
			t += dt
			if at_i < ats.size() and t >= float(ats[at_i]):
				at_i += 1
				at_frames.append(await _grab(get_viewport(), crop))
			elif ats.is_empty() and t >= next:
				next += every
				var img: Image = await _grab(get_viewport(), crop)
				frames.append(img)
		var out := _out("queen_%s.png" % seq)
		if not at_frames.is_empty():
			_save_sheet(at_frames, out.replace(".png", "_at.png"), cols, tile)
		_save_sheet(frames, out, cols, tile)
		if frames.size() > 0:
			(frames[frames.size() / 2] as Image).save_png(out.replace(".png", "_mid.png"))
		_boss.queue_free()
		await get_tree().process_frame
	get_tree().quit()


## 동작마다: 길이, 시각별 사건 [[초, 콜러블]…], 매 틱 위치·값을 정하는 콜러블 each(t, dt)
func _plan(seq: String) -> Dictionary:
	var air := FLOOR_Y - 260.0
	var bob := func(t: float) -> float: return sin(t * 2.0) * 16.0
	match seq:
		"hover":
			return {"dur": 2.8, "events": [], "each": func(t, dt):
				_boss.global_position = Vector2(sin(t * 0.9) * 120.0, air + bob.call(t))}
		"turn":
			return {"dur": 2.0, "events": [[0.5, func(): _boss.facing = -1], [1.4, func(): _boss.facing = 1]], "each": func(t, dt):
				_boss.global_position = Vector2(0, air + bob.call(t))}
		"hit":
			return {"dur": 1.6, "events": [[0.2, func(): _boss._flash = 1.0], [0.8, func(): _boss._flash = 1.0], [1.0, func(): _boss._flash = 1.0]], "each": func(t, dt):
				_boss.global_position = Vector2(0, air + bob.call(t))}
		"dust", "butterflies":
			var st := SapQueen.State.DUST if seq == "dust" else SapQueen.State.BUTTERFLIES
			return {"dur": 3.2, "events": [
				[0.2, func(): _boss._set_state(st); _phase("startup", BEAT * 2.0)],
				[0.2 + BEAT * 2.0, func(): _phase("active", BEAT)],
				[0.2 + BEAT * 3.0, func(): _phase("recovery", BEAT)],
				[0.2 + BEAT * 4.0, func(): _boss.attack_phase = ""; _boss._set_state(SapQueen.State.HOVER)],
				], "each": func(t, dt):
				if _boss.attack_phase == "startup":
					_boss.windup_progress = 1.0 - clampf((_boss._phase_end - _clock) / _boss.startup_len, 0.0, 1.0)
					_boss.telegraph_amount = _boss.windup_progress
				_boss.global_position = Vector2(0, air + bob.call(t))}
		"wave":
			return {"dur": 3.6, "events": [
				[0.2, func(): _boss._set_state(SapQueen.State.WAVE); _phase("startup", BEAT * 2.0)],
				[0.2 + BEAT * 2.0, func(): _phase("active", BEAT)],
				[0.2 + BEAT * 3.0, func(): _phase("recovery", BEAT * 2.0)],
				[0.2 + BEAT * 5.0, func(): _boss.attack_phase = ""; _boss._set_state(SapQueen.State.HOVER)],
				], "each": func(t, dt):
				if _boss.attack_phase == "startup":
					_boss.windup_progress = 1.0 - clampf((_boss._phase_end - _clock) / _boss.startup_len, 0.0, 1.0)
					_boss.telegraph_amount = _boss.windup_progress
				# 예고 동안 수면 가까이 내려왔다가 되돌림에 다시 떠오른다
				var dip := 0.0
				if _boss.state == SapQueen.State.WAVE:
					match _boss.attack_phase:
						"startup": dip = _boss.windup_progress
						"active": dip = 1.0
						"recovery": dip = clampf((_boss._phase_end - _clock) / _boss.recovery_len, 0.0, 1.0)
				_boss.global_position = Vector2(0, air + bob.call(t) + dip * 130.0)}
		"land":
			var t0 := 0.2
			var t_dive := t0 + BEAT * 2.0 - 0.2
			var t_touch := t0 + BEAT * 2.0
			var t_off := t_touch + BEAT * 6.0
			var from := {"p": Vector2.ZERO}
			return {"dur": t_off + 1.0, "events": [
				[t0, func(): _boss._set_state(SapQueen.State.LAND); _phase("startup", BEAT * 2.0)],
				[t_dive, func(): from["p"] = _boss.global_position],
				[t_touch, func():
					_boss.dive_amount = 0.0
					_boss.attack_phase = ""
					_boss._landed_touch = true
					_boss.global_position = Vector2(0, FLOOR_Y)
					_boss._set_state(SapQueen.State.LANDED)],
				[t_off, func(): _boss._landed_touch = false; _boss._set_state(SapQueen.State.TAKEOFF)],
				], "each": func(t, dt):
				if _boss.state == SapQueen.State.LAND:
					_boss.windup_progress = clampf((t - t0) / (BEAT * 2.0), 0.0, 1.0)
					_boss.telegraph_amount = _boss.windup_progress
					if t >= t_dive:
						var k := clampf((t - t_dive) / 0.2, 0.0, 1.0)
						_boss.dive_amount = k
						_boss.global_position = (from["p"] as Vector2).lerp(Vector2(0, FLOOR_Y), k * k)
					else:
						_boss.global_position = _boss.global_position.lerp(Vector2(0, FLOOR_Y - 280.0 + bob.call(t)), 1.0 - exp(-5.0 * dt))
				elif _boss.state == SapQueen.State.TAKEOFF:
					_boss.global_position = _boss.global_position.lerp(Vector2(0, air), 1.0 - exp(-3.0 * dt))}
		"crack":
			return {"dur": 2.0, "events": [[0.2, func(): _boss.phase = 2; _boss._set_state(SapQueen.State.CRACK)], [0.2 + BEAT * 3.0, func(): _boss._set_state(SapQueen.State.HOVER)]], "each": func(t, dt):
				if _boss.state == SapQueen.State.CRACK:
					_boss.crack_amount = clampf((t - 0.2) / (BEAT * 3.0), 0.0, 1.0)
				_boss.global_position = Vector2(0, air + bob.call(t))}
		"broken", "fallen":
			var st2 := SapQueen.State.BROKEN if seq == "broken" else SapQueen.State.FALLEN
			var t_land := 0.9
			var dur := 3.6 if seq == "broken" else 5.2
			var evs: Array = [
				[0.2, func(): _boss._landed_touch = false; _boss._set_state(st2)],
				[t_land, func(): _boss._landed_touch = true; _boss.global_position = Vector2(0, FLOOR_Y)],
				]
			if seq == "broken":
				evs.append([3.0, func(): _boss._landed_touch = false; _boss._set_state(SapQueen.State.TAKEOFF)])
			else:
				evs.append([3.4, func(): _boss._set_state(SapQueen.State.PURIFIED)])
			return {"dur": dur, "events": evs, "each": func(t, dt):
				if t < t_land and t >= 0.2:
					var k := clampf((t - 0.2) / (t_land - 0.2), 0.0, 1.0)
					_boss.global_position = Vector2(k * 60.0, lerpf(air, FLOOR_Y, k * k))
				elif _boss.state == SapQueen.State.TAKEOFF:
					_boss.global_position = _boss.global_position.lerp(Vector2(0, air), 1.0 - exp(-3.0 * dt))}
	return {"dur": 1.0, "events": [], "each": func(t, dt): pass}


# ---------- 조립 그림 한 장 ----------

func _render() -> void:
	var vp := SubViewport.new()
	vp.size = RENDER_SIZE
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera2D.new()
	cam.zoom = Vector2.ONE * RENDER_ZOOM
	vp.add_child(cam)
	cam.make_current()
	_spawn(vp, Vector2.ZERO)
	# 원점(발끝 땅)이 그림 아래 가운데에서 RENDER_FOOT_MARGIN px 위에 오게
	cam.position = Vector2(0, -(RENDER_SIZE.y / 2.0 - RENDER_FOOT_MARGIN) / RENDER_ZOOM)
	for k in 90:
		_tick(1.0 / 60.0)
	# 날개를 활짝 편 순간 (날갯짓 위상 0 = 펼침, 접힘 없음), 숨쉬기·흔들림이 가운데에 오게
	_vis.set("_flap_phase", 0.0)
	_vis.set("_flap_rot", 0.0)
	_vis.set("_flap_fold", 0.0)
	_tick(1.0 / 60.0)
	_vis.get("rig").modulate = Color(1, 1, 1)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	# 투명 바탕에 섞어 그리면 색이 알파만큼 곱해져(미리 곱한 알파) 반투명 가장자리가 어두워진다 → 알파로 나눠 되돌린다
	var data := img.get_data()
	for i in range(0, data.size(), 4):
		var a := data[i + 3]
		if a > 0 and a < 255:
			var k := 255.0 / a
			data[i] = mini(int(data[i] * k), 255)
			data[i + 1] = mini(int(data[i + 1] * k), 255)
			data[i + 2] = mini(int(data[i + 2] * k), 255)
	img = Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, data)
	var path := "res://art/bosses/boss_sap_queen_now.png"
	img.save_png(ProjectSettings.globalize_path(path))
	print("[queen_film] 조립 그림 → %s (%dx%d, 게임 px 배율 %.4f, 발끝 = 가운데 아래 %.1f 게임 px)" % [path, img.get_width(), img.get_height(),
		1.0 / RENDER_ZOOM, (RENDER_SIZE.y / 2.0 - RENDER_FOOT_MARGIN) / RENDER_ZOOM])
	get_tree().quit()


# ---------- 진짜 방에서 싸움 ----------

func _game() -> void:
	var tree := get_tree()
	Progress.reset()
	Progress.gain_ability("double_jump")
	Progress.next_spawn = "FromLake02"
	Game._busy = true   # 정화 뒤 회상으로 넘어가지 않게
	var room: Node = load("res://scenes/rooms/sap_lake_boss.tscn").instantiate()
	add_child(room)
	for i in 6:
		await tree.physics_frame
	var player: Player = tree.get_first_node_in_group("player") as Player
	var boss: SapQueen = room.get_node("Boss")
	player._invuln_timer = 99999.0
	player.global_position = Vector2(1560, 1433)
	var shots := {}
	var t := 0.0
	var st_t := 0.0
	var last_state := -1
	var stage := 0      # 0 1페이즈 구경, 1 2페이즈, 2 무너뜨림, 3 쓰러뜨림, 4 정화
	var seen := {}
	var only: String = str(_args.get("only", ""))
	while t < 95.0:
		await tree.physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		player._invuln_timer = 99999.0
		if player.global_position.y > 1500.0 or player.global_position.x < 1300.0:
			player.global_position = Vector2(1560, 1433)
			player.velocity = Vector2.ZERO
		if boss.state != last_state:
			last_state = boss.state
			st_t = 0.0
			print("[queen_film] %.1f초 %s (페이즈 %d)" % [t, boss.state_name(), boss.phase])
		else:
			st_t += dt
		var sn := boss.state_name().to_lower()
		var want := ""
		match boss.state:
			SapQueen.State.INTRO:
				if st_t > 1.4: want = "intro"
			SapQueen.State.HOVER:
				if st_t > 0.4: want = "hover_p%d" % boss.phase
			SapQueen.State.DUST, SapQueen.State.WAVE, SapQueen.State.BUTTERFLIES:
				seen[sn] = true
				match boss.attack_phase:
					"startup":
						if boss.windup_progress > 0.86: want = "%s_windup_p%d" % [sn, boss.phase]
					"active":
						if boss.phase_progress() > 0.3: want = "%s_strike_p%d" % [sn, boss.phase]
					"recovery":
						if boss.phase_progress() > 0.5: want = "%s_recover_p%d" % [sn, boss.phase]
			SapQueen.State.LAND:
				seen["land"] = true
				if boss.dive_amount > 0.45: want = "land_dive_p%d" % boss.phase
				elif boss.windup_progress > 0.5 and boss.dive_amount <= 0.0: want = "land_rise_p%d" % boss.phase
			SapQueen.State.LANDED:
				if st_t > 0.12 and st_t < 0.4: want = "landed_impact_p%d" % boss.phase
				elif st_t > 1.6: want = "landed_rest_p%d" % boss.phase
			SapQueen.State.TAKEOFF:
				if st_t > 0.3: want = "takeoff"
			SapQueen.State.CRACK:
				if st_t > 0.9: want = "crack"
			SapQueen.State.BROKEN:
				if boss.is_ground() and st_t > 0.15 and st_t < 0.4: want = "broken_down"
				elif st_t > 2.0: want = "broken_sit"
			SapQueen.State.FALLEN:
				if not boss.is_ground() and st_t > 0.2: want = "fallen_air"
				elif boss.is_ground() and st_t > 0.5 and not shots.has("fallen_touch"): want = "fallen_touch"
				elif st_t > 3.0: want = "fallen_lie"
			SapQueen.State.PURIFIED:
				if st_t > 0.4 and st_t < 0.8: want = "purified_a"
				elif st_t > 1.2: want = "purified_b"
		if want != "" and not shots.has(want) and (only == "" or want.begins_with(only)):
			shots[want] = true
			var img: Image = await _grab(get_viewport())
			var path := _out("queen_game_%s.png" % want)
			img.save_png(path)
			print("[queen_film] 장면 → ", path)
		# 진행: 1페이즈 패턴을 다 보면 2페이즈로
		if stage == 0 and seen.has("dust") and seen.has("wave") and seen.has("butterflies") and shots.has("landed_rest_p1") and boss.state == SapQueen.State.HOVER:
			stage = 1
			boss.hp = boss.max_hp * 0.45
			boss.receive_hit(HitData.make(1.0, 0.0, player), null)
		elif stage == 1 and boss.state == SapQueen.State.LANDED and st_t > 2.2:
			stage = 2
			boss.poise = boss.max_poise
			boss._break()
		elif stage == 2 and boss.state == SapQueen.State.TAKEOFF and st_t > 0.6:
			stage = 3
			boss.hp = 1.0
			boss.receive_hit(HitData.make(5.0, 0.0, player), null)
		elif stage == 3 and boss.state == SapQueen.State.FALLEN and shots.has("fallen_lie"):
			stage = 4
			player.global_position = boss.global_position + Vector2(-140, -60)
			await tree.create_timer(0.3).timeout
			boss.interact(player)
		elif stage == 4 and shots.has("purified_b"):
			break
		elif t > 40.0 and stage == 0:
			stage = 0
			seen = {"dust": true, "wave": true, "butterflies": true}
			shots["landed_rest_p1"] = true
	print("[queen_film] 게임 장면 끝 (%.1f초, %d장)" % [t, shots.size()])
	tree.quit()

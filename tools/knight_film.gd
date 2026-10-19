extends Node2D
## 등불 기사 동작 필름 (그림·모션 눈 확인용 — **창으로** 띄워야 찍힌다; 병렬 작업이면 /Users/wj/Projects/SeedWT/godot 래퍼).
## 빈 바닥 위에 진짜 보스 씬을 세우고 상태를 차례로 걸어(판정·시간은 실제 게임과 같다) 0.05초(--every) 간격 필름 띠를 남긴다:
##   screenshots/knight_film_<동작>.png (+ 가운데 칸 하나 _mid.png)
## 실행: Godot --path . --resolution 1600x900 res://tools/knight_film.tscn -- [--seq idle,march,thrust,...] [--every 0.05] [--zoom 1.3] [--p2]
## 동작: idle march intro thrust flame slam throw wave combo3 charge spin stagger parry broken hit fallen purify turn
## (--p2 = 2페이즈로. --at 0.62 처럼 주면 그 시각 한 장만 크게: knight_film_<동작>_at.png)

const FLOOR_Y := 700.0
const DT := 1.0 / 60.0
const ALL := ["idle", "march", "intro", "thrust", "flame", "slam", "throw", "wave", "combo3", "charge", "spin", "stagger", "parry", "broken", "fallen", "purify", "turn"]

var _args := {}
var _cam: Camera2D
var _player: Player


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
	RenderingServer.set_default_clear_color(Color(0.42, 0.45, 0.5))
	_cam = Camera2D.new()
	_cam.zoom = Vector2.ONE * float(_args.get("zoom", "1.3"))
	add_child(_cam)
	_cam.make_current()
	var fb := StaticBody2D.new()
	fb.collision_layer = 1
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40000, 200)
	cs.shape = rect
	cs.position = Vector2(0, FLOOR_Y + 100)
	fb.add_child(cs)
	add_child(fb)
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var pcam := _player.get_node_or_null("Camera2D")
	if pcam:
		_player.remove_child(pcam)
		pcam.free()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.visible = false
	_player._invuln_timer = 9999.0
	_cam.make_current()
	queue_redraw()
	_run.call_deferred()


func _draw() -> void:
	draw_rect(Rect2(-20000, FLOOR_Y, 40000, 600), Color(0.3, 0.33, 0.3))
	draw_line(Vector2(-20000, FLOOR_Y), Vector2(20000, FLOOR_Y), Color(0.15, 0.2, 0.15), 3.0)


func _run() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var seqs: Array = str(_args.get("seq", ",".join(ALL))).split(",")
	var k := 0
	for seq in seqs:
		await _film(str(seq), k)
		k += 1
	get_tree().quit()


func _spawn(x: float) -> LanternKnight:
	var b: LanternKnight = (load("res://scenes/bosses/lantern_knight.tscn") as PackedScene).instantiate()
	add_child(b)
	b.set_physics_process(false)
	b.get_node("Sprite").set_process(false)
	b.visible = true
	b.arena = Rect2(x - 1500.0, FLOOR_Y - 900.0, 3000.0, 900.0)
	b.ground_y = FLOOR_Y
	b.global_position = Vector2(x, FLOOR_Y)
	b.facing = 1
	if _args.has("p2"):
		b.phase = 2
		b.hp = b.max_hp * 0.4
	return b


func _step(b: LanternKnight) -> void:
	b._physics_process(DT)
	b.get_node("Sprite")._process(DT)


func _film(seq: String, k: int) -> void:
	var x := k * 4000.0
	var b := _spawn(x)
	b.player = null
	b._set_state(LanternKnight.State.MARCH)
	b._timer = 999.0
	# 자리 잡기
	for f in 40:
		await get_tree().physics_frame
		_step(b)
	var dur := 1.6
	var every := float(_args.get("every", "0.05"))
	var on_tick := Callable()
	match seq:
		"idle":
			dur = 1.2
		"march":
			_player.global_position = Vector2(x + 3000.0, FLOOR_Y)
			b.player = _player
			dur = 2.4
		"intro":
			b._set_state(LanternKnight.State.INTRO)
			b._timer = 2.4
			dur = 2.6
		"turn":
			_player.global_position = Vector2(x - 600.0, FLOOR_Y)
			b.player = _player
			dur = 0.8
		"thrust", "flame", "slam", "throw", "wave", "combo3", "charge", "spin":
			var dist: float = {"thrust": 330.0, "flame": 620.0, "slam": 420.0, "throw": 800.0, "wave": 700.0, "combo3": 330.0, "charge": 1300.0, "spin": 420.0}[seq]
			_player.global_position = Vector2(x + dist, FLOOR_Y - 60.0)
			b.player = _player
			b.force_attack(LanternKnight.State[seq.to_upper()])
			b._timer = b.startup_len if b.attack_phase == "startup" else b._timer
			dur = 6.0
			on_tick = func() -> bool: return b.state == LanternKnight.State.MARCH and b.attack_phase == ""
		"stagger":
			b.hp = b.max_hp * 0.45
			b.receive_hit(HitData.make(1.0, 0.0, null), null)
			dur = 1.4
		"parry":
			b.force_attack(LanternKnight.State.THRUST)
			on_tick = func() -> bool:
				if b.attack_phase == "active" and b.anim_hint != "stagger":
					b.on_just_guarded(null, 10.0)
					b.hitbox.landed.emit("just_guard", null)
				return b.state == LanternKnight.State.MARCH and b.attack_phase == "" and b.anim_hint == ""
			dur = 4.0
		"hit":
			b.receive_hit(HitData.make(5.0, 5.0, null), null)
			dur = 0.6
		"broken":
			b.receive_hit(HitData.make(1.0, b.max_poise, null), null)
			dur = 3.4
		"fallen":
			b.hp = 1.0
			b.receive_hit(HitData.make(5.0, 0.0, null), null)
			dur = 3.6
		"purify":
			b.hp = 1.0
			b.receive_hit(HitData.make(5.0, 0.0, null), null)
			for f in int(2.6 / DT):
				await get_tree().physics_frame
				_step(b)
			b.purified_by(null)
			dur = 1.8
	var vis: Node2D = b.get_node("Sprite")
	var frames: Array = []
	var t := 0.0
	var next := 0.0
	# --at 0.4,0.9 : 그 시각들만 크게 한 장씩 (knight_film_<동작>_at<시각>.png)
	var ats: Array = []
	if _args.has("at"):
		for v in str(_args["at"]).split(","):
			ats.append(float(v))
	var at := 0.0 if ats.size() > 0 else -1.0
	var done_t := -1.0
	while t < dur:
		await get_tree().physics_frame
		_step(b)
		if b.state == LanternKnight.State.MARCH and b.player and seq in ["thrust", "flame", "slam", "throw", "wave", "combo3", "charge", "spin"]:
			b._timer = 999.0   # 공격이 끝나면 다음 공격을 고르지 않게
		_cam.position = Vector2(b.global_position.x + 140.0 * float(b.facing), FLOOR_Y - 230.0)
		if seq == "slam":
			_cam.position.y = minf(FLOOR_Y - 230.0, b.global_position.y - 230.0)
		t += DT
		if on_tick.is_valid() and done_t < 0.0 and on_tick.call():
			done_t = t
		if done_t > 0.0 and t > done_t + 0.6:
			break
		if at >= 0.0:
			if ats.size() > 0 and t >= float(ats[0]) - 0.001:
				var when: float = ats.pop_front()
				var big: Image = await _grab(float(_args.get("crop", "0.62")))
				big.save_png(ProjectSettings.globalize_path("res://screenshots/knight_film_%s_at%.2f.png" % [seq, when]))
				print("[film] %s @%.2f %s/%s" % [seq, t, b.state_name(), b.attack_phase])
			if ats.is_empty():
				break
			continue
		if t >= next:
			next += every
			var img: Image = await _grab(float(_args.get("crop", "0.62")))
			frames.append(["%.2f %s %s" % [t, b.state_name(), b.attack_phase], img])
	if at < 0.0:
		_save_sheet(frames, ProjectSettings.globalize_path("res://screenshots/knight_film_%s.png" % seq))
		if frames.size() > 0:
			(frames[frames.size() / 2][1] as Image).save_png(ProjectSettings.globalize_path("res://screenshots/knight_film_%s_mid.png" % seq))
	print("[film] %s: %d칸, 끝 상태 %s" % [seq, frames.size(), b.state_name()])
	b.queue_free()
	await get_tree().physics_frame


func _grab(crop: float) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
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


func _save_sheet(tiles: Array, path: String) -> void:
	if tiles.is_empty():
		return
	var cols := int(_args.get("cols", "6"))
	var first: Image = tiles[0][1]
	var sc := float(_args.get("tile", "0.5"))
	var tw := int(first.get_width() * sc)
	var th := int(first.get_height() * sc)
	var rows := ceili(float(tiles.size()) / cols)
	var sheet := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.2, 0.2))
	for n in tiles.size():
		var img: Image = tiles[n][1].duplicate()
		img.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, tw, th), Vector2i((n % cols) * tw, (n / cols) * th))
	sheet.save_png(path)
	print("[film] → ", path)

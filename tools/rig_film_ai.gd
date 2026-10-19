extends Node2D
## 몹 동작 필름 (AI 그대로). **창으로** 띄워야 그림이 찍힌다 (--headless 빼고, 병렬 작업이면 /Users/wj/Projects/SeedWT/godot 래퍼).
## rig_preview.tscn 의 --enemy 와 같지만, 소녀를 정한 거리에 세워 두고 **몹 스크립트의 _physics_process 를 그대로** 돌린다 →
## 들이받기(기계, 소녀가 공격 거리 바깥쪽)·내려찍기(가까이)·리듬 쏘기(작은 펌프)·채찍(수액 어부)처럼 AI 가 고르는 공격을 본다.
##
##   Godot --path . --resolution 1600x900 res://tools/rig_film_ai.tscn -- --enemy res://scenes/enemies/machine.tscn \
##         --seq idle,walk,ram,slam,hit,broken,dead,dead_back,purify [--every 0.08] [--zoom 2.5] [--crop 0.55] [--dist 190]
##   동작: idle / walk / ram(소녀 190px) / slam(90px) / shoot(420px) / whip(280px) / attack(소녀 dist px, 기본 150) /
##         hit / broken / dead(뒤에서 맞아 앞으로) / dead_back(앞에서 맞아 뒤로) / purify(무너진 뒤 정화 — 구원형이면 구원) / kneel(구원형 무릎)
##   --cam_dx 80: 카메라를 몹에서 이만큼 앞에 (기본: 소녀와의 가운데)
##   결과: screenshots/film_<씬>_<동작>.png (칸 위 글자 없음, 왼→오 시간 순서) + _mid.png (가운데 칸 크게)
##         --at 0.6 이면 그 시각 한 장을 screenshots/film_<씬>_<동작>_at.png 로도. --from 1.5 면 그 시각부터만 찍는다 (--dur 로 길이).

const FLOOR_Y := 600.0
const SEQ_GAP := 2600.0

var _args := {}
var _cam: Camera2D
var _floor_half := 4000.0


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
	RenderingServer.set_default_clear_color(Color(0.42, 0.45, 0.5))
	_cam = Camera2D.new()
	_cam.zoom = Vector2.ONE * float(_args.get("zoom", "2.5"))
	add_child(_cam)
	_cam.make_current()
	if not _args.has("enemy"):
		print("사용: ... res://tools/rig_film_ai.tscn -- --enemy <씬> --seq idle,ram")
		get_tree().quit(1)
		return
	_run.call_deferred(str(_args["enemy"]))


func _draw() -> void:
	draw_line(Vector2(-_floor_half, FLOOR_Y), Vector2(_floor_half, FLOOR_Y), Color(0.2, 0.25, 0.2), 3.0)
	draw_rect(Rect2(-_floor_half, FLOOR_Y, _floor_half * 2.0, 400), Color(0.3, 0.33, 0.3))


func _grab(crop := 1.0) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if crop < 1.0:
		var w := img.get_width()
		var h := img.get_height()
		var cw := int(w * crop)
		var ch := int(h * minf(crop * 1.3, 1.0))
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
	var first: Image = tiles[0]
	var tw := first.get_width() / 2
	var th := first.get_height() / 2
	var rows := ceili(float(tiles.size()) / cols)
	var sheet := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.2, 0.2, 0.2))
	for k in tiles.size():
		var img: Image = (tiles[k] as Image).duplicate()
		img.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, tw, th), Vector2i((k % cols) * tw, (k / cols) * th))
	sheet.save_png(path)
	print("[film] → ", path)


func _out(name: String) -> String:
	var d := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(d)
	return "%s/%s" % [d, name]


func _run(scene_path: String) -> void:
	var seqs: Array = str(_args.get("seq", "idle,walk,attack,hit,broken,dead")).split(",")
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
	var every := float(_args.get("every", "0.08"))
	var name := scene_path.get_file().get_basename()
	var seq_i := -1
	for seq in seqs:
		seq_i += 1
		var path := scene_path
		if seq == "kneel" and not scene_path.contains("savable"):
			path = scene_path.replace(".tscn", "_savable.tscn")
		var e: EnemyBase = (load(path) as PackedScene).instantiate()
		add_child(e)
		if e.is_queued_for_deletion():
			print("[film] %s: 이미 물리친 중간 보스 (건너뜀)" % name)
			continue
		var x0 := seq_i * SEQ_GAP
		e.global_position = Vector2(x0, FLOOR_Y - 90.0)
		e.facing = 1
		e.set_physics_process(false)
		# 소녀: 처리를 끈 채(움직이지 않는 과녁) 정한 거리에 세운다. 카메라는 빼서 필름 카메라를 쓴다.
		var pl: Player = null
		var dist := -1.0
		match seq:
			"ram": dist = 190.0
			"slam": dist = 90.0
			"shoot": dist = 420.0
			"whip": dist = 280.0
			"attack": dist = float(_args.get("dist", "150"))
		if dist > 0.0:
			pl = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
			var pcam := pl.get_node_or_null("Camera2D")
			if pcam:
				pl.remove_child(pcam)
				pcam.free()
			add_child(pl)
			pl.set_physics_process(false)
			pl.set_process(false)
			pl.global_position = Vector2(x0 + dist, FLOOR_Y - 70.0)
			_cam.make_current()
		e.player = pl
		e._timer = 999.0 if pl == null else 0.0
		for f in 30:
			await get_tree().physics_frame
			_sim(e, 1.0 / 60.0, 0.0)
		var vis: Node = e.get_node("Visual")
		var k := float(vis.get("art_scale") if vis.get("art_scale") != null else 1.0)
		var cam_dx := float(_args.get("cam_dx", str(dist * 0.5 if dist > 0.0 else 40.0)))
		_cam.position = Vector2(x0 + cam_dx, FLOOR_Y - 100.0 * k)
		var tiles: Array = []
		var t := 0.0
		var next := 0.0
		var dur := 1.4
		var vx := 0.0
		var real := false
		match seq:
			"idle":
				dur = 1.4
				real = true
			"walk":
				e._set_state(EnemyBase.State.CHASE)
				vx = e.walk_speed * e.chase_multiplier
				dur = 1.3
			"ram", "slam", "attack", "whip":
				e._set_state(EnemyBase.State.CHASE)
				e._timer = 0.0
				real = true
				dur = 2.4
			"shoot":
				e._set_state(EnemyBase.State.IDLE)
				real = true
				dur = 3.0
			"hit":
				e.receive_hit(HitData.make(5.0, 20.0, null, Vector2(380, -150)), null)
				dur = 0.8
			"broken":
				e.poise = e.max_poise - 1.0
				e.receive_hit(HitData.make(1.0, 30.0, null), null)
				dur = 1.6
			"dead":
				e.hp = 1.0
				e.receive_hit(HitData.make(5.0, 30.0, null), null)
				dur = 0.85
			"dead_back":
				var src := Node2D.new()
				add_child(src)
				src.global_position = e.global_position + Vector2(160, 0)
				e.hp = 1.0
				e.receive_hit(HitData.make(5.0, 30.0, src), null)
				src.queue_free()
				dur = 0.85
			"purify", "kneel":
				e.poise = e.max_poise - 1.0
				e.receive_hit(HitData.make(1.0, 30.0, null), null)
				dur = 1.9 if seq == "purify" else 1.2
		if _args.has("dur"):
			dur = float(_args["dur"])
		var purified := false
		while t < dur and is_instance_valid(e) and not e.is_queued_for_deletion():
			await get_tree().physics_frame
			if not is_instance_valid(e) or e.is_queued_for_deletion():
				break
			if real:
				e._physics_process(1.0 / 60.0)
			else:
				_sim(e, 1.0 / 60.0, vx)
			if not is_instance_valid(e) or e.is_queued_for_deletion():
				break
			if seq == "purify" and not purified and t > 0.7 and e.state == EnemyBase.State.BROKEN:
				purified = true
				e.purified_by(null)
			if not real and e.state == EnemyBase.State.HIT and e._timer <= 0.0:
				e._set_state(EnemyBase.State.IDLE)
				e._timer = 999.0
			if seq in ["walk", "ram", "slam", "attack", "whip"]:
				_cam.position.x = lerpf(_cam.position.x, e.global_position.x + (dist * 0.4 if dist > 0.0 else 40.0), 0.1)
			t += 1.0 / 60.0
			if t < float(_args.get("from", "0")):
				next = t
			elif t >= next:
				next += every
				var img: Image = await _grab(float(_args.get("crop", "0.55")))
				tiles.append(img)
				if _args.has("at") and absf(t - float(_args["at"])) < every * 0.5:
					img.save_png(_out("film_%s_%s_at.png" % [name, seq]))
		_save_sheet(tiles, _out("film_%s_%s.png" % [name, seq]))
		if tiles.size() > 0:
			(tiles[tiles.size() / 2] as Image).save_png(_out("film_%s_%s_mid.png" % [name, seq]))
		if is_instance_valid(e):
			e.queue_free()
		if pl and is_instance_valid(pl):
			pl.queue_free()
		await get_tree().physics_frame
	get_tree().quit()


## 몹을 한 틱: 타이머·진행도만 (AI 는 끄고), 중력, 정해 준 가로 속도.
func _sim(e, dt: float, vx: float) -> void:
	if not is_instance_valid(e):
		return
	e._tick_common(dt)
	if not e.is_on_floor():
		e.velocity.y += e.gravity * dt
	if e.state in [EnemyBase.State.CHASE, EnemyBase.State.BACKSTEP, EnemyBase.State.PATROL]:
		e.velocity.x = vx
	else:
		e.velocity.x = move_toward(e.velocity.x, 0.0, 1400.0 * dt)
	if e.state == EnemyBase.State.DEAD and e._dying and not e._fall_done and e._timer <= 0.0:
		e._fall_done = true
		e._finish_fall()
		return
	e.move_and_slide()

extends Node2D
## '잿빛 잎새의 새' 부위 뼈대 동작 필름 (확인용 — **창으로** 띄워야 그림이 찍힌다; 병렬 작업이면 /Users/wj/Projects/SeedWT/godot 래퍼).
##   Godot --path . --resolution 1600x900 res://tools/bird_film.tscn -- [--seq hover,feathers,wind,...] [--every 0.08] [--zoom 0.9] [--cols 5] [--crop 0.7] [--joints]
## 보스 씬을 바닥(y=1000) 위에 띄우고 보스 스크립트를 **그대로** 돌리며(판정·시간은 실제 게임과 같다) 상태를 차례로 건다.
## 결과: screenshots/bird_<동작>.png (필름 띠, 칸마다 왼쪽 위에 시각·상태), 가운데 칸은 screenshots/bird_<동작>_mid.png.
## 동작: intro hover leafrain feathers wind descend idle walk eat stagger sweep peck takeoff turn broken fallen fallen_ground purify
## (fallen 은 쓰러져 누운 뒤 정화 대기까지, purify 는 그 뒤 손길을 얹은 장면)

const FLOOR_Y := 1000.0
const BIRD := preload("res://scenes/bosses/gray_leaf_bird.tscn")

var _args := {}
var _cam: Camera2D
var _boss: GrayLeafBird
var _player: Player
var _pile: LeafPile
var _label: Label
var _joints := false


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
	_joints = _args.has("joints")
	RenderingServer.set_default_clear_color(Color(0.42, 0.45, 0.5))
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20000, 400)
	cs.shape = rect
	cs.position = Vector2(2000, FLOOR_Y + 200)
	floor_body.add_child(cs)
	add_child(floor_body)
	_cam = Camera2D.new()
	_cam.zoom = Vector2.ONE * float(_args.get("zoom", "0.9"))
	add_child(_cam)
	_cam.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20, 14)
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_label)
	_run.call_deferred()


func _draw() -> void:
	draw_rect(Rect2(-8000, FLOOR_Y, 20000, 600), Color(0.3, 0.33, 0.3))
	draw_line(Vector2(-8000, FLOOR_Y), Vector2(12000, FLOOR_Y), Color(0.15, 0.2, 0.15), 3.0)
	for x in range(-2000, 6000, 200):
		draw_line(Vector2(x, FLOOR_Y), Vector2(x, FLOOR_Y + 14), Color(0.15, 0.2, 0.15), 2.0)


func _spawn() -> void:
	if _boss and is_instance_valid(_boss):
		_boss.queue_free()
	if _player and is_instance_valid(_player):
		_player.queue_free()
	if _pile and is_instance_valid(_pile):
		_pile.queue_free()
	await get_tree().physics_frame
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	var pcam := _player.get_node_or_null("Camera2D")
	if pcam:
		_player.remove_child(pcam)
		pcam.free()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player._invuln_timer = 9999.0
	_player.global_position = Vector2(1400, FLOOR_Y)
	_cam.make_current()
	_pile = LeafPile.new()
	add_child(_pile)
	_pile.position = Vector2(2700, FLOOR_Y)
	_boss = BIRD.instantiate()
	add_child(_boss)
	_boss.arena = Rect2(600, 300, 2800, 700)
	_boss.ground_y = FLOOR_Y
	_boss.hover_points = [Vector2(2000, 640), Vector2(2000, 640), Vector2(2000, 640)]
	_boss.piles = [_pile]
	_boss.player = _player
	_boss.visible = true
	_boss.facing = -1
	if _joints:
		var vis = _boss.get_node("Sprite")
		var mk := Node2D.new()
		mk.z_index = 60
		vis.rig.add_child(mk)
		mk.draw.connect(func():
			var r: PartRig = vis.rig
			for k in r.xf.size():
				var o: Vector2 = (r.body_xf * r.xf[k]).origin * r.game_scale
				var p := r.parent[k]
				if p >= 0:
					mk.draw_line((r.body_xf * r.xf[p]).origin * r.game_scale, o, Color(1, 1, 0, 0.8), 2.0)
				mk.draw_circle(o, 4.0, Color(1, 0.2, 0.2)))
		_boss.set_meta("marks", mk)


## 땅에 서 있게 둔다 (바닥 충돌 켜고 GROUND_IDLE)
func _ground(x: float) -> void:
	_boss.global_position = Vector2(x, FLOOR_Y)
	_boss.set_collision_mask_value(1, true)
	_boss._set_state(GrayLeafBird.State.GROUND_IDLE)
	_boss._timer = 999.0
	_boss._ground_actions = 99


func _hover(x: float, y := 640.0) -> void:
	_boss.global_position = Vector2(x, y)
	_boss._hover_target = Vector2(x, y)
	_boss.hover_points = [Vector2(x, y)]
	_boss.set_collision_mask_value(1, false)
	_boss._set_state(GrayLeafBird.State.HOVER)
	_boss._timer = 999.0
	_boss._air_timer = 0.0


func _run() -> void:
	var seqs: Array = str(_args.get("seq", "hover,feathers,wind,descend,idle,walk,eat,sweep,peck,takeoff,broken,fallen")).split(",")
	var every := float(_args.get("every", "0.08"))
	var crop := float(_args.get("crop", "0.75"))
	var vp := get_viewport().get_visible_rect().size
	_label.position = Vector2(vp.x * (1.0 - crop) * 0.5 + 12.0, vp.y * (1.0 - minf(crop * 1.15, 1.0)) * 0.5 + 6.0)
	for seq in seqs:
		await _spawn()
		var dur := 1.6
		var settle := 0.6
		var follow := true
		match seq:
			"intro":
				_boss.global_position = Vector2(2000, 300)
				_boss.start_fight(_player)
				_boss.hover_points = [Vector2(2000, 640), Vector2(2000, 640)]
				_boss._hover_target = Vector2(2000, 640)
				settle = 0.0
				dur = 2.6
			"hover":
				_hover(2000)
				dur = 1.2
			"leafrain":
				_hover(2000)
			"feathers":
				_hover(2000)
			"wind":
				_hover(2000)
			"descend":
				_hover(2000, 560)
			"idle", "turn":
				_ground(2000)
			"walk":
				_ground(1900)
			"eat", "stagger":
				_ground(2560)
			"sweep", "peck":
				_ground(2000)
			"takeoff":
				_ground(2000)
			"broken":
				_hover(2000)
			"fallen", "purify":
				_hover(2000)
			"fallen_ground":
				_ground(2000)
		# 자리 잡기
		var t := 0.0
		while t < settle:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			_follow()
		# 동작 시작
		match seq:
			"leafrain":
				_boss._set_state(GrayLeafBird.State.LEAF_RAIN)
				_boss._timer = _boss.leaf_rain_time
				_boss._spawn_accum = 0.0
				dur = 2.0
			"feathers":
				_boss._pattern_index = 1
				_boss._next_pattern()
				dur = 1.6
			"wind":
				_boss._pattern_index = 2
				_boss._next_pattern()
				dur = 2.6
			"descend":
				_boss._begin_descend()
				dur = 2.2
			"idle":
				dur = 1.6
			"turn":
				_player.global_position = Vector2(2600, FLOOR_Y)
				_boss.facing = 1
				dur = 1.0
			"walk":
				_boss._target_pile = _pile
				_boss._set_state(GrayLeafBird.State.WALK_TO_PILE)
				dur = 2.4
			"eat":
				_boss._target_pile = _pile
				_boss.facing = 1
				_boss._set_state(GrayLeafBird.State.EAT)
				_boss._timer = _boss.eat_time
				dur = 2.0
			"stagger":
				_boss._target_pile = _pile
				_boss.facing = 1
				_boss._set_state(GrayLeafBird.State.EAT)
				_boss._timer = _boss.eat_time
				dur = 1.8
			"sweep", "peck":
				_player.global_position = Vector2(1780, FLOOR_Y)
				_boss.facing = -1
				var s: int = GrayLeafBird.State.SWEEP if seq == "sweep" else GrayLeafBird.State.PECK
				_boss._set_state(s)
				_boss._timer = _boss.sweep_windup if seq == "sweep" else _boss.peck_windup
				_boss._melee_stage = 0
				_boss.attack_phase = "startup"
				_boss.windup_progress = 0.0
				_boss.startup_len = _boss._timer
				dur = 1.8
			"takeoff":
				_boss._begin_takeoff()
				_boss._hover_target = Vector2(2000, 640)
				dur = 1.6
			"broken":
				_boss._break()
				dur = 2.6
			"fallen", "purify":
				_boss.hp = 1.0
				_boss.receive_hit(HitData.make(5.0, 0.0, _player), null)
				dur = 3.0
			"fallen_ground":
				# 무너져 땅에 있다가 쓰러짐 (공중 단계 없음)
				_boss._break()
				for i in 40:
					await get_tree().physics_frame
				_boss.hp = 1.0
				_boss.receive_hit(HitData.make(5.0, 0.0, _player), null)
				dur = 2.0
		var frames: Array = []
		var next := 0.0
		t = 0.0
		var interrupted := false
		var purified := false
		while t < dur and is_instance_valid(_boss):
			await get_tree().physics_frame
			t += 1.0 / 60.0
			if seq == "stagger" and not interrupted and t > 0.7:
				interrupted = true
				_boss.receive_hit(HitData.make(10.0, 10.0, _player), null)
			if seq == "purify" and not purified and t > 2.0:
				purified = true
				_boss.purified_by(_player)
			if follow:
				_follow()
			if _boss.has_meta("marks"):
				(_boss.get_meta("marks") as Node2D).queue_redraw()
			_label.text = "%s  %.2f  %s %s" % [seq, t, _boss.state_name(), _boss.attack_phase]
			if _args.has("debug") and _boss.muzzle_flash > 0.95:
				var v = _boss.get_node("Sprite")
				print("[bird_film] 깃털 한 발: 붉은 점 %s, 부리 %s, 날개 끝 %s (보스 %s)" % [_boss.muzzle_point() - _boss.global_position,
					v.socket_global("beak") - _boss.global_position, v.socket_global("wing_tip") - _boss.global_position, _boss.global_position])
			if t >= next:
				next += every
				var img: Image = await _grab(crop)
				frames.append(img)
		if _args.has("debug") and is_instance_valid(_boss):
			_dump_low()
		var out := "%s/bird_%s.png" % [_out_dir(), seq]
		_save_sheet(frames, out)
		if frames.size() > 0:
			(frames[frames.size() / 2] as Image).save_png(out.replace(".png", "_mid.png"))
			(frames[frames.size() - 1] as Image).save_png(out.replace(".png", "_end.png"))
	get_tree().quit()


## 부위마다 가장 낮은 점 (바닥 위 −, 게임 px) — 떠 있거나 파고드는 부위 찾기
func _dump_low() -> void:
	var vis = _boss.get_node("Sprite")
	var r: PartRig = vis.rig
	var line := ""
	for k in r.names.size():
		var low := r.lowest_y(PackedInt32Array([k])) * r.game_scale
		line += "%s %.0f  " % [r.names[k], low]
	print("[bird_film] 가장 낮은 점(게임 px, + = 바닥 아래): ", line, " | 바닥 자리 ", vis._floor_off)
	# 몸통·머리 가운데 (보스 원점 기준 게임 px) — 몸 충돌·맞는 영역(가운데 y −150, 위아래 ±110)과 견준다
	for bn in ["torso", "head"]:
		var i := r.bone_index(bn)
		var c := Vector2.ZERO
		for q in r.hulls[i]:
			c += r.body_xf * r.xf[i] * q
		c /= maxf(r.hulls[i].size(), 1)
		var g: Vector2 = r.to_global(c * r.game_scale) - _boss.global_position
		print("[bird_film]   %s 가운데 (보스 원점 기준) %s" % [bn, g])


func _follow() -> void:
	if _boss and is_instance_valid(_boss):
		var target := Vector2(_boss.global_position.x, minf(_boss.global_position.y - 210.0, FLOOR_Y - 270.0))
		_cam.position = target


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
		var ch := int(h * minf(crop * 1.15, 1.0))
		img = img.get_region(Rect2i((w - cw) / 2, (h - ch) / 2, cw, ch))
	var hdr := img.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]
	img.convert(Image.FORMAT_RGBA8)
	if hdr:
		img.linear_to_srgb()
	return img


func _save_sheet(tiles: Array, path: String) -> void:
	if tiles.is_empty():
		return
	var cols := int(_args.get("cols", "5"))
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
	print("[bird_film] ", path, " (", tiles.size(), "칸)")

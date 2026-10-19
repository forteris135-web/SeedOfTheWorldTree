extends Node2D
## 무쇠 펌프 동작 필름 (확인용, **창으로** 띄워야 그림이 찍힌다 — --headless 를 빼고 실행).
##   Godot --path . --resolution 1600x900 res://tools/pump_film.tscn [-- --seq intro,idle,walk,piston,spray,suck,bite_parry,stagger,broken,p2piston,dead,purify]
##        [--every 0.1] [--cols 6] [--zoom 0.9] [--joints] [--shot <동작>:<초>]
## 실제 보스 장면(scenes/bosses/iron_pump.tscn)을 바닥 위에 세우고 보스 논리를 1/60초씩 직접 돌려(판정·시간은 게임과 같다)
## 동작마다 --every 간격 칸을 모은 필름 띠 screenshots/pump_film_<동작>.png 를 만든다.
## --shot piston:0.95 처럼 주면 그 동작의 그 시각 한 장을 크게 screenshots/pump_shot_<동작>_<초>.png 로 (여러 번 줄 수 있다: 쉼표로).
## 콘솔에는 칸마다 발바닥 높이·몸의 가장 낮은 점(땅 0, 아래 +)·입/대포 자리를 찍는다.

const STEP := 1.0 / 60.0
const FLOOR_Y := 700.0

var _args := {}
var _cam: Camera2D
var _boss: IronPump
var _vis
var _player: Player
var _marks: Node2D
var _shots := {}


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
	for sh in str(_args.get("shot", "")).split(",", false):
		var kv := sh.split(":")
		if kv.size() == 2:
			if not _shots.has(kv[0]):
				_shots[kv[0]] = []
			_shots[kv[0]].append(float(kv[1]))
	RenderingServer.set_default_clear_color(Color(0.36, 0.38, 0.42))
	_cam = Camera2D.new()
	_cam.zoom = Vector2.ONE * float(_args.get("zoom", "1.25"))
	add_child(_cam)
	_cam.make_current()
	var floor := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20000, 400)
	cs.shape = rect
	cs.position = Vector2(0, FLOOR_Y + 200)
	floor.add_child(cs)
	add_child(floor)
	queue_redraw()
	_run.call_deferred()


func _draw() -> void:
	draw_rect(Rect2(-10000, FLOOR_Y, 20000, 500), Color(0.27, 0.29, 0.27))
	draw_line(Vector2(-10000, FLOOR_Y), Vector2(10000, FLOOR_Y), Color(0.15, 0.18, 0.15), 3.0)


func _spawn() -> void:
	if is_instance_valid(_boss):
		_boss.queue_free()
	if is_instance_valid(_player):
		_player.queue_free()
	for n in get_tree().get_nodes_in_group("projectile"):
		n.queue_free()
	await get_tree().process_frame
	_player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(_player)
	_player.set_physics_process(false)
	_player.set_process(false)
	_player.set_process_unhandled_input(false)
	_boss = (load("res://scenes/bosses/iron_pump.tscn") as PackedScene).instantiate()
	_boss.position = Vector2(0, FLOOR_Y)
	add_child(_boss)
	_boss.arena = Rect2(-1800, FLOOR_Y - 900, 3600, 900)
	_boss.ground_y = FLOOR_Y
	_boss.set_physics_process(false)
	_vis = _boss.get_node("Sprite")
	_vis.set_process(false)
	_player.global_position = Vector2(-1000, FLOOR_Y - 2)
	if _args.has("joints"):
		_marks = Node2D.new()
		_marks.z_index = 60
		_vis.rig.add_child(_marks)
		_marks.draw.connect(_draw_joints)
	await get_tree().process_frame


func _draw_joints() -> void:
	var rig: PartRig = _vis.rig
	for i in rig.xf.size():
		var t := rig.body_xf * rig.xf[i]
		var o := t.origin * rig.game_scale
		var p := rig.parent[i]
		if p >= 0:
			_marks.draw_line((rig.body_xf * rig.xf[p]).origin * rig.game_scale, o, Color(1, 1, 0, 0.8), 2.0)
		_marks.draw_circle(o, 4.0, Color(1, 0.2, 0.2))
	_marks.draw_line(Vector2(-400, 0), Vector2(400, 0), Color(1, 1, 1, 0.5), 1.0)


func _step(n := 1) -> void:
	for i in n:
		_boss._physics_process(STEP)
		_vis._process(STEP)


func _run() -> void:
	var seqs: Array = str(_args.get("seq", "intro,idle,walk,piston,spray,suck,bite_parry,stagger,broken,p2piston,p2idle,dead,purify")).split(",")
	for sq in seqs:
		await _sequence(str(sq))
	get_tree().quit()


## 한 동작: 보스를 새로 세우고, 그 동작의 상태로 만든 뒤 칸을 찍는다
func _sequence(name: String) -> void:
	await _spawn()
	_boss.start_fight(_player)
	_boss.global_position = Vector2(0, FLOOR_Y)
	_player.global_position = Vector2(-430, FLOOR_Y - 2)
	var length := 2.0
	match name:
		"intro":
			length = 2.6
		_:
			_step(int(2.4 / STEP))   # 등장 끝까지
			_boss._set_state(IronPump.State.IDLE)
			_boss._timer = 999.0
			_step(30)
	match name:
		"idle":
			length = 1.6
		"walk":
			_player.global_position = Vector2(-1500, FLOOR_Y - 2)
			length = 3.0
		"turn":
			_player.global_position = Vector2(600, FLOOR_Y - 2)
			length = 2.0
		"piston", "spray", "suck", "bite_parry":
			var idx := {"piston": 0, "spray": 1, "suck": 2, "bite_parry": 2}[name] as int
			_boss._cycle = idx
			_boss._timer = 0.0
			length = 3.4 if name != "piston" else 2.4
		"stagger":
			_boss.hp = _boss.max_hp * 0.45
			_boss.receive_hit(HitData.make(1.0, 0.0, _player), null)
			length = 1.2
		"broken":
			_boss.poise = _boss.max_poise - 1.0
			_boss.receive_hit(HitData.make(1.0, 60.0, _player), null)
			length = 5.6
		"p2piston", "p2idle":
			_boss.hp = _boss.max_hp * 0.45
			_boss.receive_hit(HitData.make(1.0, 0.0, _player), null)
			_step(int(0.7 / STEP))
			if name == "p2piston":
				_boss._cycle = 0
				_boss._last_attack = IronPump.State.SUCK
				_boss._set_state(IronPump.State.IDLE)
				_boss._timer = 0.0
				length = 2.2
			else:
				_boss._timer = 999.0
				length = 3.0
		"dead":
			_boss.hp = 1.0
			_boss.receive_hit(HitData.make(5.0, 0.0, _player), null)
			length = 3.4
		"purify":
			_boss.hp = 1.0
			_boss.receive_hit(HitData.make(5.0, 0.0, _player), null)
			_step(int(2.6 / STEP))
			_boss.purified_by(_player)
			length = 1.8
	var every := float(_args.get("every", "0.1"))
	var tiles: Array = []
	var t := 0.0
	var next_tile := 0.0
	var shots: Array = (_shots.get(name, []) as Array).duplicate()
	var parried := false
	while t <= length + 0.0001:
		if name == "bite_parry" and not parried and _boss.state == IronPump.State.SUCK and _boss._bit:
			parried = true
			_boss.on_just_guarded(_player, 45.0)
		var want_tile := t >= next_tile - 0.0001
		var want_shot := false
		for s in shots:
			if t >= float(s) - 0.0001:
				want_shot = true
		if want_tile or want_shot:
			_cam.position = Vector2(_boss.global_position.x - 60.0 * _boss.facing, FLOOR_Y - 0.26 * get_viewport().get_visible_rect().size.y / _cam.zoom.y)
			if _marks:
				_marks.queue_redraw()
			var img: Image = await _grab()
			var pp: Dictionary = _vis.probe_pose()
			print("[펌프필름] %-10s %4.2f초 %-8s %-9s 발바닥 %s 가장 낮은 몸 %+.1f 몸 내려놓기 %+.1f 꼭대기 %.0f 입 %s 대포 %.0f 대포끝 %s %s" % [name, t, _boss.state_name(), _boss.attack_phase,
				_fmt(pp["soles"]), pp["lowest"], pp["settle_low"], pp["top"], str(Vector2i(pp["mouth"] - _boss.global_position)), pp["cannon"], str(Vector2i(pp["muzzle"] - _boss.global_position)), pp["low_bone"]])
			if want_tile:
				tiles.append(img)
				next_tile += every
			if want_shot:
				for s in shots.duplicate():
					if t >= float(s) - 0.0001:
						shots.erase(s)
						img.save_png(ProjectSettings.globalize_path("res://screenshots/pump_shot_%s_%.2f.png" % [name, float(s)]))
		_step()
		t += STEP
	_save_strip(tiles, "res://screenshots/pump_film_%s.png" % name)


func _fmt(a: Array) -> String:
	var out := ""
	for v in a:
		out += "%+.1f " % float(v)
	return out


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var crop := float(_args.get("crop", "0.7"))
	if crop < 1.0:
		var w := img.get_width()
		var h := img.get_height()
		img = img.get_region(Rect2i(int(w * (1.0 - crop) * 0.5), int(h * (1.0 - crop) * 0.3), int(w * crop), int(h * crop)))
	var hdr := img.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]
	img.convert(Image.FORMAT_RGBA8)
	if hdr:
		img.linear_to_srgb()
	return img


func _save_strip(tiles: Array, path: String) -> void:
	if tiles.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots"))
	var cols := int(_args.get("cols", "5"))
	var first: Image = tiles[0]
	var div := float(_args.get("div", "2.2"))
	var tw := int(first.get_width() / div)
	var th := int(first.get_height() / div)
	var rows := ceili(float(tiles.size()) / cols)
	var sheet := Image.create(tw * cols, th * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.15, 0.15, 0.15))
	for k in tiles.size():
		var img: Image = (tiles[k] as Image).duplicate()
		img.resize(tw, th, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, tw, th), Vector2i((k % cols) * tw, (k / cols) * th))
	sheet.save_png(ProjectSettings.globalize_path(path))
	print("[펌프필름] → ", ProjectSettings.globalize_path(path))

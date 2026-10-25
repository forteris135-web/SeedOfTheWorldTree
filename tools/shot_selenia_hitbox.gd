extends Node
## 셀레니아 공격 이펙트 ↔ 판정 상자 눈 확인용 스크린샷 (v1.1.0 기획자 요청 2·3·17). 화면이 있어야 찍힌다 (--headless 로는 안 찍힌다).
## 실행: godot --path . res://tools/shot_selenia_hitbox.tscn -- [--out <폴더>] [--only slash,seed,plunge,hud] [--zoom 2.0] [--left]
## 첫 방을 띄우고 적을 치운 뒤, 일반 공격 1·2·3타(새순 0단계·3단계), 씨앗 베기, 낙하 공격(기본·수액의 맥동)을 하나씩 꽂아
## 칼자국이 가장 크게 드러난 순간에 소녀를 멈추고 찍는다. 빨간 테두리 = 실제 판정 상자, 노란 테두리 = 이펙트 그림이 보이는 범위(시험이 재는 값).
## 파일: hb_<동작>.png. 마지막 줄 "[shots] 끝 N장". (tools/probe_*.tscn 이 아니라서 전체 회귀에는 들지 않는다)

var _out := "res://screenshots/"
var _only: Array = []
var _zoom := 2.0
var _face := 1
var _room: Node
var _player: Player
var _rig: Node2D
var _cam: Camera2D
var _count := 0
var _floor := Vector2(1240, 2132)
var _overlay: Node2D
var _label: Label
## 그릴 사각형들: [{"rect": Rect2(소녀 기준, 오른쪽을 볼 때), "color": Color}]
var _boxes: Array = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("[shots] 화면 없음 — 건너뜀")
		get_tree().quit()
		return
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--out": _out = args[i + 1]
			"--only": _only = args[i + 1].split(",")
			"--zoom": _zoom = float(args[i + 1])
			"--left": _face = -1
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out)
	_room = load("res://scenes/rooms/canopy_01.tscn").instantiate()
	add_child(_room)
	await _frames(10)
	for n in _room.get_children():
		if n is CanvasLayer and n.name != "CombatHUD":
			n.visible = false
	_player = get_tree().get_first_node_in_group("player") as Player
	_rig = _player.get_node("Visual")
	_player.input_enabled = false
	_player._invuln_timer = 0.0   # 무적 깜빡임 없이 (적은 모두 치운다)
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	_cam = _player.get_node("Camera2D")
	_cam.zoom = Vector2(_zoom, _zoom)
	_cam.vertical_offset = -40.0
	_cam.look_ahead = 0.0
	_cam.position_smoothing_enabled = false
	_cam.limit_left = -100000
	_cam.limit_top = -100000
	_cam.limit_right = 100000
	_cam.limit_bottom = 100000
	_overlay = Node2D.new()
	_overlay.z_index = 100
	_overlay.draw.connect(_draw_overlay)
	_room.add_child(_overlay)
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(20, 900)
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	layer.add_child(_label)
	await _frames(5)
	await _run()
	print("[shots] 끝 %d장" % _count)
	get_tree().quit()


func _process(_d: float) -> void:
	if _overlay:
		_overlay.queue_redraw()


func _draw_overlay() -> void:
	if _player == null:
		return
	for b in _boxes:
		var r: Rect2 = b["rect"]
		var f := float(_player.facing)
		var x0 := r.position.x * f
		var x1 := r.end.x * f
		var wr := Rect2(Vector2(minf(x0, x1), r.position.y) + _player.global_position, Vector2(absf(x1 - x0), r.size.y))
		_overlay.draw_rect(wr, b["color"], false, 2.0 / _zoom * 1.5)
	# 소녀 가운데 표시
	_overlay.draw_circle(_player.global_position, 3.0, Color(1, 1, 1, 0.8))


func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _out + "hb_%s.png" % name
	img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	_count += 1
	print("[shots] %s" % path)


func _reset(pos := Vector2.ZERO) -> void:
	_player.set_physics_process(true)
	_player.global_position = _floor if pos == Vector2.ZERO else pos
	_player.velocity = Vector2.ZERO
	_player.facing = _face
	_player._set_state(Player.State.IDLE)
	_player._soul_cooldowns.clear()
	_player._combo_lock_timer = 0.0
	_player.guard = _player.max_guard
	_boxes.clear()
	_label.text = ""
	await _frames(50)


## 소녀(와 판정)를 멈춘다: 뼈대·이펙트는 계속 돌아 멈춘 자세에서 가라앉는다
func _freeze(on: bool) -> void:
	_player.set_physics_process(not on)
	_player.hitbox.set_physics_process(not on)


func _fmt(r: Rect2) -> String:
	return "x %.0f..%.0f  y %.0f..%.0f" % [r.position.x, r.end.x, r.position.y, r.end.y]


func _slash(step: int, lv: int) -> void:
	Progress.upgrades["tok_normal"] = float(lv)
	await _reset()
	# 앞 타들을 거쳐 이어지는 것처럼: 그 타를 바로 시작한다
	_player._start_light(step)
	for i in 60:
		await get_tree().physics_frame
		if _player.attack_phase == "active" and _player._attack_timer <= get_physics_process_delta_time() * 1.01:
			break
	_freeze(true)
	var box := _player.light_box()
	var art: Rect2 = _rig.light_slash_rect(step)
	_boxes = [{"rect": box, "color": Color(1, 0.15, 0.1)}, {"rect": art, "color": Color(1, 0.9, 0.2)}]
	_label.text = "%d타  새순 %d단계\n판정 %s\n그림 %s   (끝 차이 %+.0f)" % [step, lv, _fmt(box), _fmt(art), art.end.x - box.end.x]
	await _frames(6)
	await _shot("slash%d_lv%d" % [step, lv])
	_freeze(false)
	Progress.upgrades.erase("tok_normal")


func _run() -> void:
	if _want("slash"):
		for lv in [0, 3]:
			for step in [1, 2, 3]:
				await _slash(step, lv)
	if _want("seed"):
		await _reset()
		_player._start_soul_slash()
		for i in 80:
			await get_tree().physics_frame
			if _player.attack_phase == "active" and _player._attack_timer <= get_physics_process_delta_time() * 1.01:
				break
		_freeze(true)
		var sbox := _player.seed_slash_box()
		var sart: Rect2 = _rig.seed_slash_rect()
		_boxes = [{"rect": sbox, "color": Color(1, 0.15, 0.1)}, {"rect": sart, "color": Color(1, 0.9, 0.2)}]
		_label.text = "씨앗 베기\n판정 %s\n그림 %s" % [_fmt(sbox), _fmt(sart)]
		await _frames(6)
		await _shot("seed")
		_freeze(false)
	if _want("plunge"):
		for pulse in [false, true]:
			if pulse:
				Progress.abilities["sap_pulse"] = true
			else:
				Progress.abilities.erase("sap_pulse")
			var tag := "pulse" if pulse else "base"
			await _reset()
			_player.global_position = _floor + Vector2(0, -360)   # 기다리는 동안 떨어지지 않게 다 기다린 뒤 띄운다
			_player.velocity = Vector2.ZERO
			_player._set_state(Player.State.FALL)
			await get_tree().physics_frame
			_player._start_plunge()
			for i in 60:
				await get_tree().physics_frame
				if _player.attack_phase == "dive" and _player._attack_timer < -0.1:
					break
			_freeze(true)
			var dbox := _player.plunge_dive_box()
			var dart: Rect2 = _rig.plunge_dive_rect()
			_boxes = [{"rect": dbox, "color": Color(1, 0.15, 0.1)}, {"rect": dart, "color": Color(1, 0.9, 0.2)}]
			_label.text = "낙하 공격 내려꽂기 (%s)\n판정 %s\n그림 %s" % [tag, _fmt(dbox), _fmt(dart)]
			await _frames(6)
			await _shot("plunge_dive_%s" % tag)
			_freeze(false)
			for i in 90:
				await get_tree().physics_frame
				if _player.attack_phase == "land":
					break
			# 착지 터짐이 거의 다 커졌을 때 (수명 0.42 의 30% 쯤)
			var t0 := 0.0
			while t0 < 0.13:
				await get_tree().physics_frame
				t0 += get_physics_process_delta_time()
			_freeze(true)
			Engine.time_scale = 0.0001   # 이펙트도 멈춘다
			var lbox := _player.plunge_land_box_now()
			var lart: Rect2 = _rig.plunge_impact_rect()
			_boxes = [{"rect": lbox, "color": Color(1, 0.15, 0.1)}, {"rect": lart, "color": Color(1, 0.9, 0.2)}]
			_label.text = "낙하 공격 착지 (%s)\n판정 %s\n그림 %s (가장 커졌을 때)" % [tag, _fmt(lbox), _fmt(lart)]
			await RenderingServer.frame_post_draw
			await _shot("plunge_land_%s" % tag)
			Engine.time_scale = 1.0
			_freeze(false)
		Progress.abilities.erase("sap_pulse")
	if _want("hud"):
		_cam.zoom = Vector2(1, 1)
		await _reset()
		_player.guard = 40.0
		_player.stamina_refused.emit()
		await _frames(2)
		await _shot("hud_refused")
		Progress.upgrades["tok_stamina"] = 3.0
		Progress.ability_gained.emit("upgrade")
		await _frames(30)
		_player.guard = 70.0
		_label.text = "최대 스태미너 %.0f" % _player.max_guard
		await _shot("hud_max109")
		Progress.upgrades.erase("tok_stamina")
		Progress.ability_gained.emit("upgrade")

extends Node
## 셀레니아 이펙트 눈 확인용 스크린샷 (2026-10-19 이펙트 리뉴얼 F1). 화면이 있어야 찍힌다 (--headless 로는 안 찍힌다).
## 실행: godot --path . res://tools/probe_fx_shots.tscn -- [--out <폴더>] [--only 이름,이름] [--zoom 2.0] [--room canopy_01]
## 첫 방을 띄우고 HUD 를 숨긴 뒤, 소녀의 공격·기술을 하나씩 꽂으며 정해 둔 프레임에 찍는다 (fx_<동작>_<프레임>.png).
## 마지막 줄 "[shots] 끝 N장".

var _out := "res://screenshots/"
var _only: Array = []
var _zoom := 2.0
var _room_name := "canopy_01"
var _room: Node
var _player: Player
var _cam: Camera2D
var _count := 0
var _floor := Vector2(1240, 2132)
## 게임 시간 (물리 delta 를 더한 값). 찍는 순간을 '물리 프레임 수'가 아니라 게임 시간으로 맞춘다 —
## 화면 그리기가 느리면 그리는 동안 물리 프레임이 여러 번 지나가 버리므로, 시간을 느리게(SLOW) 흘리고 시간으로 기다린다.
var _gt := 0.0
const SLOW := 0.2


func _physics_process(delta: float) -> void:
	_gt += delta


func _process(_delta: float) -> void:
	# 히트스톱(Juice)이 끝나며 1.0 으로 되돌린 것을 다시 느리게
	if not Juice._stopping:
		Engine.time_scale = SLOW


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		match args[i]:
			"--out": _out = args[i + 1]
			"--only": _only = args[i + 1].split(",")
			"--zoom": _zoom = float(args[i + 1])
			"--room": _room_name = args[i + 1]
	if not _out.ends_with("/"):
		_out += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out) if _out.begins_with("res://") else _out)
	_room = load("res://scenes/rooms/%s.tscn" % _room_name).instantiate()
	add_child(_room)
	await _frames(10)
	for n in _room.get_children():
		if n is CanvasLayer:
			n.visible = false
	_player = get_tree().get_first_node_in_group("player") as Player
	_player.input_enabled = false
	_player._invuln_timer = 0.0
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
	await _frames(5)
	await _run()
	print("[shots] 끝 %d장" % _count)
	get_tree().quit()


func _want(name: String) -> bool:
	return _only.is_empty() or _only.has(name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		return
	var img := get_viewport().get_texture().get_image()
	var path := _out + "fx_%s.png" % name
	img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	_count += 1


## 동작을 시작하고 정해 둔 때(60fps 프레임 수로 센 게임 시간)마다 찍는다
func _capture(name: String, frames: Array) -> void:
	var t0 := _gt
	for target in frames:
		while _gt - t0 < float(target) / 60.0 - 0.0001:
			await get_tree().process_frame
		await _shot("%s_%02d" % [name, int(target)])


func _reset(pos := Vector2.ZERO, facing := 1) -> void:
	_player.global_position = _floor if pos == Vector2.ZERO else pos
	_player.velocity = Vector2.ZERO
	_player.facing = facing
	_player._set_state(Player.State.IDLE)
	_player._soul_cooldowns.clear()
	await _frames(20)


func _dummy(x_off: float, hp := 99999.0) -> EnemyBase:
	var e: EnemyBase = load("res://scenes/enemies/woodcutter.tscn").instantiate()
	e.position = _player.global_position + Vector2(x_off, -2.0)
	_room.add_child(e)
	e.max_hp = hp
	e.hp = hp
	e.max_poise = 100000.0
	await _frames(2)
	e.set_physics_process(false)
	return e


## 표의 모든 이펙트를 격자로 띄워 몇 순간 찍는다 (--only gallery)
func _gallery() -> void:
	_player.visible = false
	var names: Array = Fx.effect_names()
	names.sort()
	var cols := 6
	var cell := Vector2(260, 230)
	var base := _player.global_position + Vector2(-cell.x * 2.5, -300)
	for k in [0.06, 0.16, 0.3]:
		Fx.clear()
		var t0 := _gt
		for i in names.size():
			var p := base + Vector2((i % cols) * cell.x, (i / cols) * cell.y)
			Fx.spawn(names[i], p, {"children": false})
		while _gt - t0 < k:
			await get_tree().process_frame
		await _shot("gallery_%02d" % int(k * 100))
	print("[shots] 이펙트 순서: %s" % ", ".join(names))
	_player.visible = true


func _run() -> void:
	if _want("gallery") and not _only.is_empty():
		_cam.zoom = Vector2(0.75, 0.75)
		await _gallery()
		_cam.zoom = Vector2(_zoom, _zoom)
	if _want("attack"):
		await _reset()
		_player._start_light(1)
		var t0 := _gt
		var next := 1
		while next <= 52:
			if _player.state == Player.State.ATTACK and _player.attack_phase == "recovery" and _player.attack_step < 3:
				_player._attack_buffered = true
			await get_tree().process_frame
			if _gt - t0 >= next / 60.0 - 0.0001:
				await _shot("attack_%02d" % next)
				next += 2 if next < 44 else 4
	if _want("seed"):
		await _reset()
		_player._start_soul_slash()
		await _capture("seed", [12, 17, 20, 23, 27, 33, 42])
	if _want("plunge"):
		await _reset(_floor + Vector2(0, -330))
		_player._set_state(Player.State.FALL)
		_player._start_plunge()
		await _capture("plunge", [4, 8, 12, 16, 19, 22, 26, 32])
	if _want("roll"):
		await _reset()
		_player._try_roll(true)
		await _capture("roll", [3, 7, 11, 15, 20])
	if _want("land"):
		await _reset(_floor + Vector2(0, -420))
		_player._set_state(Player.State.FALL)
		var landed := false
		for i in 90:
			await _frames(1)
			if _player.is_on_floor():
				landed = true
				break
		await _capture("land", [1, 4, 8, 14])
	if _want("jump2"):
		await _reset()
		Progress.gain_ability("double_jump")
		_player._apply_abilities()
		_player._do_jump(false)
		await _frames(14)
		_player._do_jump(true)
		await _capture("jump2", [2, 6, 10])
	if _want("guard"):
		await _reset()
		_player._set_state(Player.State.GUARD)
		await _capture("guard", [20])
		_player.guard_hit.emit(10.0)
		await _capture("guardhit", [2, 5, 9])
		await _frames(20)
		_player.just_guarded.emit(null)
		await _capture("justguard", [2, 5, 9, 14])
		_player._set_state(Player.State.IDLE)
	if _want("heal"):
		await _reset()
		_player._heal_timer = _player.heal_time
		_player._set_state(Player.State.HEAL)
		await _capture("heal", [8, 22, 38, 50])
	if _want("hit"):
		await _reset()
		var e := await _dummy(150.0)
		_player._start_light(1)
		await _capture("hitspark", [8, 10, 13, 17])
		e.queue_free()
	if _want("break"):
		await _reset()
		var e2 := await _dummy(200.0)
		e2.max_poise = 10.0
		e2._break(false)
		await _capture("break", [3, 8, 15, 24])
		e2.set_physics_process(true)
		e2._die(false)
		await _capture("death", [6, 20, 40, 52])
	if _want("purify"):
		await _reset()
		var e3 := await _dummy(120.0)
		e3._break(false)
		await _frames(10)
		_player.start_purify(e3)
		await _capture("purify", [20, 30, 36, 44, 60])
	if _want("pickup"):
		await _reset()
		Dust.burst(_room, _player.global_position + Vector2(160, -60), 30, _player)
		await _capture("pickup", [20, 30, 40, 50])
	if _want("souls"):
		Progress.gain_ability("wind")
		Progress.gain_ability("light")
		_player._apply_abilities()
		await _reset()
		_player.soul = "wind"
		_player.soul_changed.emit("wind")
		await _capture("switch", [3, 8, 16])
		await _frames(20)
	if _want("wind"):
		Progress.gain_ability("wind")
		_player._apply_abilities()
		await _reset(_floor + Vector2(-200, 0))
		_player.soul = "wind"
		var e4 := await _dummy(700.0)
		_player.cast_soul_skill()
		await _capture("wind", [2, 6, 12, 20, 30, 40])
		e4.queue_free()
	if _want("laser"):
		Progress.gain_ability("light")
		_player._apply_abilities()
		await _reset(_floor + Vector2(-200, 0))
		_player.soul = "light"
		var e5 := await _dummy(400.0)
		var e6 := await _dummy(650.0)
		_player.cast_soul_skill()
		await _capture("laser", [3, 6, 9, 12, 16, 22, 30])
		e5.queue_free()
		e6.queue_free()

extends Node
## Claude Code용 **그림 확인** (화면 있는 실행 전용 — 창이 잠깐 떴다가 닫힌다). 잠긴 채굴장 묶음의 장면을 screenshots/debug_mine_*.png 로 찍는다.
## 실행: godot --path . res://tools/probe_mine_shots.tscn      (--headless 로 돌리면 아무것도 찍지 않고 끝난다)
##  - 금 간 벽 (기존 방에 link_flooded_mine.py 가 적용돼 있을 때만): 잠김 → 맞아서 붉게 번쩍 → 벽 부수기 뒤 따뜻한 빛 → 부서짐 → 열린 벽장
##  - 잠긴 채굴장 방 셋 + 숨겨진 방 몇 개, 지도(새 방 모두 가 본 것으로), 클리어(제3의 길) 타이틀, 제3의 길 엔딩 씬
##  - 마지막: 심연 '정원의 끝'의 세 선택지와 제3의 길 연출(다섯 빛 구슬) — 연출이 엔딩 씬으로 넘어가기 전에 끝낸다
## 진행·저장 파일은 건드리지 않는다 (엔딩 씬은 last_grass 를 비워 저장하지 않게 한다).

const DT := 1.0 / 60.0
var _room: Node


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("[샷] 화면 없는 실행이라 찍지 않는다")
		get_tree().quit(0)
		return
	await _wait(0.3)
	# -- --only cracked,rooms,map,title,ending,third 로 일부만 찍을 수 있다 (없으면 전부)
	var only := []
	var args := OS.get_cmdline_user_args()
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		only = args[oi + 1].split(",")
	var want := func(part: String) -> bool: return only.is_empty() or part in only
	Progress.reset()
	if want.call("cracked"):
		await _cracked_shots("mine_02", "debug_mine_cracked")
		await _cracked_shots("village_01", "debug_mine_cracked_village", true)
		await _cracked_shots("canopy_02", "debug_mine_cracked_canopy", true)
		await _cracked_shots("mine_deep", "debug_mine_cracked_minedeep", true)
		await _cracked_shots("abyss_01", "debug_mine_cracked_abyss", true)
	if want.call("rooms"):
		Progress.reset()
		Progress.gain_ability("sap_walk")
		await _room_shot("flooded_mine_01", Vector2(1300, 1180), "debug_mine_flooded_01.png", 2.4)
		await _room_shot("flooded_mine_02", Vector2(1200, 2100), "debug_mine_flooded_02.png", 2.4)
		await _room_shot("flooded_mine_02", Vector2(1560, 1050), "debug_mine_flooded_02_top.png", 1.8)
		Progress.gain_ability("wall_break")
		await _room_shot("canopy_hidden_1", Vector2(700, 700), "debug_mine_hidden_canopy1.png", 1.8)
		await _room_shot("mine_hidden_1", Vector2(700, 700), "debug_mine_hidden_mine1.png", 1.8)
		await _room_shot("abyss_hidden_2", Vector2(700, 700), "debug_mine_hidden_abyss2.png", 1.8)
	if want.call("map"):
		await _map_shot()
	if want.call("title"):
		await _title_shot()
	if want.call("ending"):
		await _ending_shot()
	if want.call("third"):
		await _third_way_shots()
	print("[샷] 끝")
	get_tree().quit(0)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://screenshots/" + file_name))
	print("[샷] %s" % file_name)


func _load(room_id: String) -> Node:
	if is_instance_valid(_room):
		_room.queue_free()
		await get_tree().process_frame
	_room = load("res://scenes/rooms/%s.tscn" % room_id).instantiate()
	add_child(_room)
	await get_tree().process_frame
	await get_tree().process_frame
	return _room


func _place(feet: Vector2) -> void:
	var p: Player = _room.player
	p.global_position = feet + Vector2(0, -68)
	p.velocity = Vector2.ZERO
	var cam := p.get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.reset_smoothing()


func _room_shot(room_id: String, feet: Vector2, file_name: String, wait: float) -> void:
	await _load(room_id)
	_place(feet)
	await _wait(wait)
	await _shot(file_name)


## 금 간 벽 앞에 서서: 잠김 → (능력 없이) 때림 → 능력 → 부서짐 → 열린 벽장. quick 이면 잠긴 모습 한 장만.
func _cracked_shots(room_id: String, prefix: String, quick := false) -> void:
	Progress.reset()
	await _load(room_id)
	var wall: CrackedWall = _room.get_node_or_null("Terrain/CrackedWall1")
	if wall == null:
		print("[샷] %s: 금 간 벽이 없다 (link_flooded_mine.py 가 적용되지 않았다) — 건너뜀" % room_id)
		return
	var room_w: float = (_room as Room).bounds.size.x
	var left: bool = wall.global_position.x < room_w * 0.5
	var feet_x: float = wall.global_position.x + wall.size.x + 90.0 if left else wall.global_position.x - 90.0
	_place(Vector2(feet_x, wall.global_position.y + wall.size.y))
	_room.player.facing = -1 if left else 1
	await _wait(1.8)
	await _shot(prefix + "_locked.png")
	if quick:
		return
	var hit := HitData.make(12.0, 20.0, _room.player)
	hit.from_player = true
	wall.receive_hit(hit, null)
	await _wait(0.07)
	await _shot(prefix + "_deny.png")
	Progress.gain_ability("wall_break")
	await _wait(1.2)
	await _shot(prefix + "_ready.png")
	var heavy := HitData.make(32.0, 60.0, _room.player)
	heavy.from_player = true
	wall.receive_hit(heavy, null)
	await _wait(0.12)
	await _shot(prefix + "_break.png")
	await _wait(1.4)
	await _shot(prefix + "_open.png")


## 지도: 모든 방(1편 + 새 방)을 한 번씩 띄워 '가 본 방'으로 만든 뒤 연다.
func _map_shot() -> void:
	Progress.reset()
	var ids := ["canopy_01", "canopy_02", "canopy_03", "canopy_04", "canopy_hidden", "canopy_boss",
		"village_01", "village_02", "village_shrine", "mine_01", "mine_02", "mine_deep", "mine_boss",
		"abyss_01", "abyss_02", "moon_garden", "abyss_boss",
		"flooded_mine_01", "flooded_mine_02", "flooded_mine_boss", "flooded_mine_hidden_1",
		"canopy_hidden_1", "canopy_hidden_2", "village_hidden_1", "village_hidden_2",
		"mine_hidden_1", "mine_hidden_2", "abyss_hidden_1", "abyss_hidden_2"]
	for id in ids:
		await _load(id)
	_room.queue_free()
	_room = null
	await get_tree().process_frame
	var map := MapScreen.new()
	add_child(map)
	await get_tree().process_frame
	map.open(null)
	await _wait(0.8)
	await _shot("debug_mine_map.png")
	map.close()
	map.queue_free()
	Progress.reset()


func _title_shot() -> void:
	Progress.reset()
	Progress.set_flag("cleared")
	Progress.set_flag("cleared_third")
	var title: Node = load("res://scenes/ui/title_screen.tscn").instantiate()
	add_child(title)
	await _wait(4.5)
	await _shot("debug_mine_title_third.png")
	title.queue_free()
	await get_tree().process_frame
	Progress.reset()


func _ending_shot() -> void:
	Progress.reset()
	Progress.ending = "third"
	Progress.last_grass = {}   # 저장하지 않게
	var ending: Node = load("res://scenes/ui/ending_scene.tscn").instantiate()
	add_child(ending)
	await _wait(6.0)
	await _shot("debug_mine_ending_third.png")
	ending.queue_free()
	await get_tree().process_frame
	Progress.reset()


## 심연 '정원의 끝': 뿌리지기를 정화한 뒤(after 깃발) 다섯 영혼이 있으면 세 선택지. 세 번째를 고르면 다섯 빛 구슬 연출.
func _third_way_shots() -> void:
	Progress.reset()
	for a in ["double_jump", "wind", "light", "lantern", "sap_walk", "wall_break"]:
		Progress.gain_ability(a)
	for f in ["boss_root_defeated", "after_boss_root_defeated", "looked_at_lantern"]:
		Progress.set_flag(f)
	await _load("abyss_boss")
	var pump: EndingChoice = _room.get_node("Choices/Pump")
	_place(Vector2(pump.global_position.x - 260.0, pump.global_position.y))
	await _wait(2.2)
	await _shot("debug_mine_third_choices.png")
	pump.interact(_room.player)
	await _wait(1.3)
	await _shot("debug_mine_third_ritual_1.png")
	await _wait(1.4)
	await _shot("debug_mine_third_ritual_2.png")

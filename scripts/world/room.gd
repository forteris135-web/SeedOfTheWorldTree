extends Node2D
class_name Room
## 방 하나의 바탕. 방의 경계를 카메라에 알려 주고, 떨어지면 시작 지점으로 되돌린다.
## 달빛풀에서 쉬면 적이 다시 나타나고, 쓰러지면 마지막 달빛풀에서 일어난다.
## 메뉴 버튼(Esc / P / 옵션)을 누르면 입력 확인 화면으로 간다 (임시).

const INPUT_TEST_SCENE := "res://scenes/debug/input_test.tscn"

## 방의 경계 (월드 좌표). 카메라가 이 밖을 보여 주지 않는다.
@export var bounds := Rect2(0, 0, 4800, 2400)
## 이 방이 속한 지역 (정화 상태를 함께 쓴다): canopy / village / mine / abyss
@export var region := "canopy"
## 지도용: 고유 이름, 표시 이름, 세계 지도에서 이 방의 왼쪽 위 자리, 보스 방 여부
@export var room_id := ""
@export var display_name := ""
@export var map_offset := Vector2.ZERO
@export var is_boss_room := false
## 어두운 방: 등불이 없으면 소녀 주변만 희미하게 보인다.
@export var dark := false
@export var dark_color := Color(0.3, 0.27, 0.34)
var _map: MapScreen
## 지형 색: 배경의 주된 색을 살짝 입힌 어두운 실루엣.
@export var terrain_color := Color("15150f")
## 지형 윗면의 빛 테두리 (정화 후 / 정화 전).
@export var edge_color_alive := Color(1.0, 0.89, 0.62, 0.8)
@export var edge_color_ash := Color(0.62, 0.70, 0.80, 0.55)

var player: Player
var rest_point := Vector2.ZERO
var _spawn := Vector2.ZERO
var _enemy_spawns: Array = []   # [{scene: String, position: Vector2, parent: Node}]


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Player
	if player:
		# 다른 방에서 넘어왔다면 그 출구에 맞는 자리에 선다
		if Progress.next_spawn != "":
			if Progress.next_spawn.begins_with("Grass:"):
				var gid := Progress.next_spawn.trim_prefix("Grass:")
				for g in get_tree().get_nodes_in_group("moonlight_grass"):
					if g.grass_id == gid:
						player.position = g.global_position + Vector2(60, -2)
						rest_point = g.global_position + Vector2(0, -2)
						g.arrive(player)
			elif Progress.next_spawn.begins_with("Portal:"):
				var pid := Progress.next_spawn.trim_prefix("Portal:")
				for p in get_tree().get_nodes_in_group("portal"):
					if p.portal_id == pid:
						player.position = p.global_position + Vector2(90, -2)
						p.arrive(player)
			else:
				var marker := get_node_or_null("Markers/" + Progress.next_spawn)
				if marker:
					player.position = marker.position
					player.facing = 1 if marker.position.x < bounds.get_center().x else -1
			Progress.next_spawn = ""
		player.input_enabled = true
		_spawn = player.position
		if rest_point == Vector2.ZERO:
			rest_point = _spawn
		player.last_safe_position = player.position
		var cam := player.get_node_or_null("Camera2D")
		if cam and cam.has_method("set_room_bounds"):
			cam.set_room_bounds(bounds)
		player.died.connect(_on_player_died)
		player.rest_started.connect(_on_player_rested)
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node2D and e.scene_file_path != "":
			_enemy_spawns.append({"scene": e.scene_file_path, "position": e.position, "parent": e.get_parent()})
	Purity.progress.connect(_on_purity_progress)
	Purity.apply_region(region)
	_register_on_map()
	_apply_room_settings()
	Settings.changed.connect(_apply_room_settings)
	if not (self is BossRoom) or Progress.has(get("defeat_flag") if "defeat_flag" in self else ""):
		Music.play_region(region)
	if dark:
		var cm := CanvasModulate.new()
		cm.color = dark_color
		add_child(cm)
		if player:
			player.set_light(true)
	Game.fade_in(1.2)
	var args := OS.get_cmdline_user_args()
	if "--lantern" in args:
		Progress.gain_ability("lantern")
		Progress.gain_ability("light")
		if player:
			player._apply_abilities()
	if "--ash" in args:
		Purity.reset_region(region)
	elif "--alive" in args:
		Purity.regions[region] = true
		Purity.apply_region(region)
	if "--screenshot" in args:
		await get_tree().create_timer(3.0).timeout
		print("[스크린샷] 3초 뒤 FPS: %d" % Engine.get_frames_per_second())
		if "--map" in args:
			# 지도 시험용: 몇 개 방을 가 본 것으로 치고 연다
			Progress.visited_rooms["canopy_02"] = {"offset": Vector2(4800, -1600), "size": Vector2(2400, 2600), "name": "수관 · 바람의 틈", "region": "canopy", "grasses": [Vector2(2050, 300)], "boss": false}
			Progress.visited_rooms["canopy_03"] = {"offset": Vector2(7200, -2400), "size": Vector2(5200, 1400), "name": "수관 · 잎의 회랑", "region": "canopy", "grasses": [], "boss": false}
			Progress.visited_rooms["canopy_boss"] = {"offset": Vector2(15600, -2623), "size": Vector2(3600, 1800), "name": "수관 · 꼭대기의 하늘", "region": "canopy", "grasses": [Vector2(330, 1380)], "boss": true}
			open_map()
			await get_tree().create_timer(0.5).timeout
		var sky := get_node_or_null("Backdrop/Far/Sky")
		var cam := get_viewport().get_camera_2d()
		if sky and cam:
			var far := sky.get_parent()
			print("[배경] Far.position=%s Sky.position=%s global=%s scale=%s tex=%s | 카메라 중심=%s 보이는 영역=%s" % [far.position, sky.position, sky.global_position, sky.scale, sky.texture.get_size(), cam.get_screen_center_position(), get_viewport().get_visible_rect().size])
		_save_screenshot("debug_room.png")
		get_tree().quit()
	elif "--autotest" in args:
		_autotest()
	elif "--rescuetest" in args:
		_rescuetest()
	elif "--villagetest" in args:
		_villagetest()
	elif "--savetest" in args:
		_savetest()
	elif "--remaptest" in args:
		_remaptest()
	elif "--portaltest" in args:
		if Progress.has("_test_travelled"):
			_arrivaltest("포탈", Progress.next_spawn)
		else:
			_portaltest()
	elif "--grasstest" in args:
		if Progress.has("_test_travelled"):
			_arrivaltest("달빛풀", Progress.next_spawn)
		else:
			_grasstest()


func _process(_delta: float) -> void:
	if player and player.position.y > bounds.end.y + 200.0 and player.state != Player.State.DEAD:
		# 방 밖으로 떨어졌다: 가시에 떨어진 것처럼 피해를 입고 마지막 안전한 자리로
		if player.last_safe_position == Vector2.ZERO:
			player.last_safe_position = rest_point
		player.take_hazard(15.0)


var _pause: PauseMenu


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if Dialogue.is_active():
			return
		if _pause == null:
			_pause = PauseMenu.new()
			add_child(_pause)
		if not _pause.is_open():
			_pause.open()
	elif event.is_action_pressed("map"):
		open_map()


func _apply_room_settings() -> void:
	var dbg := get_node_or_null("DebugHUD")
	if dbg:
		dbg.visible = bool(Settings.get_value("debug_hud"))


func open_map() -> void:
	if _map == null:
		_map = MapScreen.new()
		add_child(_map)
	if not _map._open:
		_map.open(self)


## 지도에 이 방을 기록한다 (방문한 방만 지도에 그려진다).
func _register_on_map() -> void:
	if room_id == "":
		return
	var grasses: Array = []
	for g in get_tree().get_nodes_in_group("moonlight_grass"):
		grasses.append(g.position)
	var portals: Array = []
	for p in get_tree().get_nodes_in_group("portal"):
		portals.append(p.position)
	Progress.visited_rooms[room_id] = {"offset": map_offset, "size": bounds.size, "name": display_name if display_name != "" else room_id, "region": region, "grasses": grasses, "portals": portals, "boss": is_boss_room}


## 월드의 한 점에서 색이 번져 돌아온다.
func purify_from(world_point: Vector2) -> void:
	var cam := get_viewport().get_camera_2d()
	var screen_uv := Vector2(0.5, 0.5)
	if cam:
		var vp_size := get_viewport().get_visible_rect().size
		var screen_pos := (world_point - cam.get_screen_center_position()) * cam.zoom + vp_size / 2.0
		screen_uv = screen_pos / vp_size
	Purity.play_purify(region, screen_uv)


func _on_purity_progress(value: float) -> void:
	var edge := edge_color_ash.lerp(edge_color_alive, value)
	var terrain := get_node_or_null("Terrain")
	if terrain:
		for t in terrain.get_children():
			if "edge_color" in t:
				t.edge_color = edge
				t.color = terrain_color


## 모든 일반 적을 처음 자리로 되돌린다 (불사의 저주).
func respawn_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	for info in _enemy_spawns:
		var scene: PackedScene = load(info["scene"])
		if scene == null:
			continue
		var e := scene.instantiate()
		e.position = info["position"]
		(info["parent"] as Node).add_child(e)


func _on_player_rested(grass: Node2D) -> void:
	rest_point = grass.global_position + Vector2(0, -2)
	respawn_enemies()


func _on_player_died() -> void:
	await get_tree().create_timer(2.6).timeout
	if player == null or not is_instance_valid(player):
		return
	respawn_enemies()
	player.revive(rest_point)
	var cam := player.get_node_or_null("Camera2D")
	if cam:
		cam.reset_smoothing()


func _save_screenshot(file_name: String) -> void:
	var tex := get_viewport().get_texture()
	if tex == null:
		return   # 화면 없는(headless) 시험에서는 찍지 않는다
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	img.save_png(ProjectSettings.globalize_path("res://screenshots/" + file_name))


## Claude Code용 자동 전투 시험. 적을 때리고, 가드하고, 맞고, 회복하고, 정화한다.
func _autotest() -> void:
	var tree := get_tree()
	await tree.create_timer(0.5).timeout
	var enemy: EnemyBase = null
	for e in tree.get_nodes_in_group("enemy"):
		enemy = e
		break
	if enemy == null:
		print("[자동시험] 적이 없다")
		tree.quit()
		return
	# 적 옆으로 순간이동 (왼쪽에서 오른쪽을 보게)
	player.position = enemy.position + Vector2(-110, -10)
	player.facing = 1
	player.velocity = Vector2.ZERO
	await tree.create_timer(0.3).timeout
	var hp0 := enemy.hp
	# 약공격 3연타
	for i in 3:
		Input.action_press("attack_light")
		await tree.physics_frame
		Input.action_release("attack_light")
		await tree.create_timer(0.3).timeout
	await tree.create_timer(0.4).timeout
	print("[자동시험] 약공격 3연타 뒤 적 체력: %.0f → %.0f (흐트러짐 %.0f)" % [hp0, enemy.hp, enemy.poise])
	_save_screenshot("debug_autotest_attack.png")
	# 강공격 차지
	var hp1 := enemy.hp
	player._invuln_timer = 2.5   # 시험용: 차지 중에 맞아 끊기지 않게
	Input.action_press("attack_heavy")
	await tree.create_timer(0.95).timeout
	Input.action_release("attack_heavy")
	await tree.create_timer(0.8).timeout
	if is_instance_valid(enemy):
		print("[자동시험] 강공격(최대 차지) 뒤 적 체력: %.0f → %.0f (흐트러짐 %.0f, 상태 %s)" % [hp1, enemy.hp, enemy.poise, enemy.state_name()])
	else:
		print("[자동시험] 강공격(최대 차지)으로 적이 쓰러졌다 (체력 %.0f 에서). 다음 적으로 옮긴다." % hp1)
		enemy = null
		for e in tree.get_nodes_in_group("enemy"):
			if is_instance_valid(e) and e.state != EnemyBase.State.DEAD:
				enemy = e
				break
		if enemy == null:
			print("[자동시험] 남은 적이 없다")
			tree.quit()
			return
		player.position = enemy.position + Vector2(-110, -10)
		player.facing = 1
		player.velocity = Vector2.ZERO
		await tree.create_timer(0.3).timeout
	# 가드 들고 적의 공격을 기다린다 (일반 가드)
	var php0 := player.hp
	Input.action_press("guard")
	var waited := 0.0
	while waited < 4.0 and player.hp == php0 and player.state != Player.State.HIT:
		await tree.physics_frame
		waited += get_physics_process_delta_time()
	await tree.create_timer(0.2).timeout
	print("[자동시험] 가드 중 피격: 소녀 체력 %.0f → %.0f, 가드 게이지 %.0f, 상태 %s" % [php0, player.hp, player.guard, player.state_name()])
	Input.action_release("guard")
	_save_screenshot("debug_autotest_guard.png")
	# 가드 없이 맞기
	var php1 := player.hp
	waited = 0.0
	while waited < 4.0 and player.hp == php1:
		await tree.physics_frame
		waited += get_physics_process_delta_time()
	await tree.create_timer(0.5).timeout
	print("[자동시험] 맨몸 피격: 소녀 체력 %.0f → %.0f" % [php1, player.hp])
	# 회복
	var php2 := player.hp
	Input.action_press("heal")
	await tree.physics_frame
	Input.action_release("heal")
	await tree.create_timer(1.0).timeout
	print("[자동시험] 회복: %.0f → %.0f, 남은 이슬 %d" % [php2, player.hp, player.dews])
	# 흐트러뜨려 정화
	player.position = enemy.position + Vector2(-110, -10)
	player.facing = 1
	player._invuln_timer = 5.0
	enemy.hp = enemy.max_hp   # 시험용: 온전한 적을 흐트러뜨린다
	var tries := 0
	while is_instance_valid(enemy) and enemy.state != EnemyBase.State.BROKEN and tries < 12:
		Input.action_press("attack_light")
		await tree.physics_frame
		Input.action_release("attack_light")
		await tree.create_timer(0.35).timeout
		tries += 1
	if is_instance_valid(enemy):
		print("[자동시험] %d번 때린 뒤 적 상태: %s (체력 %.0f, 흐트러짐 %.0f)" % [tries, enemy.state_name(), enemy.hp, enemy.poise])
		await tree.create_timer(0.2).timeout
		print("[자동시험] 상호작용 가능: %s" % player.can_interact)
		Input.action_press("interact")
		await tree.physics_frame
		Input.action_release("interact")
		await tree.create_timer(0.5).timeout
		_save_screenshot("debug_autotest_purify.png")
		await tree.create_timer(1.0).timeout
		print("[자동시험] 정화 뒤 적 살아있음: %s, 남은 적 수 %d" % [is_instance_valid(enemy), tree.get_nodes_in_group("enemy").size()])
	else:
		print("[자동시험] 적이 정화 전에 쓰러졌다 (체력 0)")
	# 달빛풀
	var grass := tree.get_first_node_in_group("moonlight_grass") as Node2D
	if grass:
		player.position = grass.global_position + Vector2(40, -2)
		await tree.create_timer(0.3).timeout
		print("[자동시험] 달빛풀 곁 상호작용 가능: %s" % player.can_interact)
		Input.action_press("interact")
		await tree.physics_frame
		Input.action_release("interact")
		await tree.create_timer(2.0).timeout
		print("[자동시험] 달빛풀: 소녀 상태 %s, 적 수 %d" % [player.state_name(), tree.get_nodes_in_group("enemy").size()])
		_save_screenshot("debug_autotest_rest.png")
	tree.quit()


## Claude Code용: 구원 가능한 자를 무릎 꿇리고 구원한다. 정원사 앞에서도 한 장 찍는다.
func _rescuetest() -> void:
	var tree := get_tree()
	await tree.create_timer(0.5).timeout
	player._invuln_timer = 9999.0
	var gardener: EnemyBase = null
	var savable: EnemyBase = null
	var grunt: EnemyBase = null
	for e in tree.get_nodes_in_group("enemy"):
		if e is Gardener: gardener = e
		elif e.savable: savable = e
		elif grunt == null: grunt = e
	if grunt:
		player.global_position = grunt.global_position + Vector2(-200, 0)
		player.facing = 1
		var waited := 0.0
		var got := {}
		while waited < 6.0 and got.size() < 2:
			await tree.physics_frame
			waited += get_physics_process_delta_time()
			if grunt.state == EnemyBase.State.WINDUP and grunt.windup_progress > 0.7 and not got.has("windup"):
				got["windup"] = true
				_save_screenshot("debug_enemy_windup.png")
			elif grunt.state == EnemyBase.State.STRIKE and not got.has("strike"):
				got["strike"] = true
				await tree.create_timer(0.05).timeout
				_save_screenshot("debug_enemy_strike.png")
		print("[구원시험] 나무꾼 장면: " + str(got.keys()))
	if gardener:
		player.global_position = gardener.global_position + Vector2(-420, 0)
		player.facing = 1
		await tree.create_timer(2.2).timeout
		_save_screenshot("debug_gardener.png")
		print("[구원시험] 정원사 상태: %s, 투사체 %d" % [gardener.state_name(), tree.get_nodes_in_group("projectile").size()])
	if savable == null:
		print("[구원시험] 구원 가능한 자가 없다")
		tree.quit()
		return
	player.global_position = savable.global_position + Vector2(-140, 0)
	player.facing = 1
	await tree.create_timer(0.4).timeout
	savable.hp = 5.0
	var tries := 0
	while is_instance_valid(savable) and savable.state != EnemyBase.State.BROKEN and tries < 6:
		Input.action_press("attack_light")
		await tree.physics_frame
		Input.action_release("attack_light")
		await tree.create_timer(0.35).timeout
		tries += 1
	print("[구원시험] 상태: %s (체력 %.0f) 상호작용 가능: %s" % [savable.state_name(), savable.hp, player.can_interact])
	_save_screenshot("debug_rescue_kneel.png")
	var hp_before := player.max_hp
	await tree.create_timer(0.3).timeout
	print("[구원시험] 누르기 전 소녀 상태: %s, 대상 수 %d" % [player.state_name(), player.interactables.size()])
	Input.action_press("interact")
	await tree.physics_frame
	Input.action_release("interact")
	await tree.create_timer(0.15).timeout
	print("[구원시험] 누른 뒤 소녀 상태: %s" % player.state_name())
	await tree.create_timer(5.2).timeout
	print("[구원시험] 구원됨: %s, 보상 뒤 최대 체력 %.0f → %.0f, NPC 수 %d" % [Progress.rescued, hp_before, player.max_hp, tree.get_nodes_in_group("npc").size()])
	_save_screenshot("debug_rescue_done.png")
	Input.action_press("interact")
	await tree.physics_frame
	Input.action_release("interact")
	await tree.create_timer(0.8).timeout
	_save_screenshot("debug_rescue_talk.png")
	tree.quit()


## Claude Code용: 이 방의 NPC·기록물에 말을 걸고, 경비병의 돌진을 찍는다.
func _villagetest() -> void:
	var tree := get_tree()
	await tree.create_timer(0.6).timeout
	player._invuln_timer = 9999.0
	for npc in tree.get_nodes_in_group("npc"):
		var id: String = npc.get("npc_id") if npc.get("npc_id") != null else "npc"
		player.global_position = npc.global_position + Vector2(-120, -60)
		player.velocity = Vector2.ZERO
		player.facing = 1
		await tree.create_timer(0.6).timeout
		print("[마을시험] %s 곁: 상호작용 가능 %s, 소녀 상태 %s" % [id, player.can_interact, player.state_name()])
		Input.action_press("interact")
		await tree.physics_frame
		Input.action_release("interact")
		await tree.create_timer(1.6).timeout
		print("[마을시험] 대화 열림: %s" % Dialogue.is_active())
		_save_screenshot("debug_dialogue_%s.png" % id)
		var guard := 0
		while Dialogue.is_active() and guard < 12:
			Input.action_press("jump")
			await tree.physics_frame
			Input.action_release("jump")
			await tree.create_timer(0.35).timeout
			Input.action_press("jump")
			await tree.physics_frame
			Input.action_release("jump")
			await tree.create_timer(0.35).timeout
			guard += 1
		await tree.create_timer(0.3).timeout
		print("[마을시험] %s 대화 끝. 깃발: %s" % [id, Progress.flags])
	for rec in tree.get_nodes_in_group("record") if tree.has_group("record") else []:
		pass
	for node in get_tree().current_scene.find_children("Record_*", "", true):
		player.global_position = node.global_position + Vector2(-80, -60)
		player.velocity = Vector2.ZERO
		await tree.create_timer(0.6).timeout
		Input.action_press("interact")
		await tree.physics_frame
		Input.action_release("interact")
		await tree.create_timer(1.2).timeout
		_save_screenshot("debug_record_%s.png" % node.record_id)
		var guard2 := 0
		while Dialogue.is_active() and guard2 < 8:
			Input.action_press("jump")
			await tree.physics_frame
			Input.action_release("jump")
			await tree.create_timer(0.4).timeout
			guard2 += 1
		print("[마을시험] 기록물 %s 읽음: %s" % [node.record_id, Progress.has("read_" + node.record_id)])
	for e in tree.get_nodes_in_group("enemy"):
		if e is Guard:
			player.global_position = e.global_position + Vector2(-520, 0)
			player.facing = 1
			var waited := 0.0
			var got := {}
			while waited < 10.0 and got.size() < 2:
				await tree.physics_frame
				waited += get_physics_process_delta_time()
				if e.anim_hint == "red" and not got.has("red"):
					got["red"] = true
					_save_screenshot("debug_guard_red.png")
				elif e.anim_hint == "stuck" and not got.has("stuck"):
					got["stuck"] = true
					_save_screenshot("debug_guard_stuck.png")
			print("[마을시험] 경비병 장면: " + str(got.keys()))
			# 정면 공격은 튕긴다
			player.global_position = e.global_position + Vector2(-e.facing * 120.0, 0)
			player.facing = e.facing
			var hp0: float = e.hp
			Input.action_press("attack_light")
			await tree.physics_frame
			Input.action_release("attack_light")
			await tree.create_timer(0.5).timeout
			print("[마을시험] 정면 공격 뒤 경비병 체력 %.0f → %.0f (상태 %s)" % [hp0, e.hp, e.state_name()])
			break
	_save_screenshot("debug_village_end.png")
	tree.quit()


## Claude Code용: 달빛풀에서 쉬어 저장하고, 다시 읽어 같은 내용인지 확인한다.
func _savetest() -> void:
	var tree := get_tree()
	await tree.create_timer(0.5).timeout
	Progress.set_flag("test_flag")
	Progress.gain_ability("double_jump")
	Progress.add_upgrade("max_hp", 15)
	var grass := tree.get_first_node_in_group("moonlight_grass") as Node2D
	player.global_position = grass.global_position + Vector2(50, -60)
	player.velocity = Vector2.ZERO
	await tree.create_timer(0.6).timeout
	Input.action_press("interact")
	await tree.physics_frame
	Input.action_release("interact")
	await tree.create_timer(2.5).timeout
	print("[저장시험] 저장 파일 있음: %s" % SaveGame.has_save())
	Progress.reset()
	print("[저장시험] 초기화 뒤 능력: %s" % Progress.abilities)
	var scene := SaveGame.load_game()
	print("[저장시험] 읽은 뒤: 방 %s, 깃발 %s, 능력 %s, 성장 %s, 달빛풀 %s, 등장 %s" % [scene.get_file(), Progress.has("test_flag"), Progress.abilities, Progress.upgrades, Progress.grasses.keys(), Progress.next_spawn])
	# 일시정지 메뉴 열어 찍기
	_pause = PauseMenu.new()
	add_child(_pause)
	_pause.open()
	await tree.create_timer(0.4).timeout
	_save_screenshot("debug_pause.png")
	_pause.close()
	SaveGame.new_game()
	print("[저장시험] 새로 시작 뒤 저장 파일 있음: %s" % SaveGame.has_save())
	tree.quit()


## 시험용: 열려 있는 이동 메뉴를 찾는다.
func _find_travel_menu() -> TravelMenu:
	for c in get_children():
		if c is TravelMenu and c.is_open():
			return c
	return null


## 시험용: 화면(캔버스 좌표)의 한 점을 손가락으로 누르거나 뗀다 (터치 조작 시험). 창 좌표로 바꿔서 보낸다.
func _fake_touch(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = get_viewport().get_final_transform() * pos
	ev.pressed = pressed
	Input.parse_input_event(ev)


## 시험용: 동작을 진짜 입력 이벤트로 눌렀다 뗀다 (메뉴처럼 이벤트로 듣는 화면용).
func _fake_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	ev = InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)


## Claude Code용: 터치 '지도' 버튼으로 지도가 열리는지, 포탈 메뉴를 열고 다른 방으로 건너가는지 확인한다.
func _portaltest() -> void:
	var tree := get_tree()
	await tree.create_timer(0.5).timeout
	# 1) 터치 지도 버튼
	var touch := get_node_or_null("TouchControls")
	if touch:
		var s: Vector2 = touch._canvas.size
		_fake_touch(Vector2(s.x - 76, 76), true)
		await tree.create_timer(0.3).timeout
		print("[포탈시험] 터치 '지도' 누름 → 지도 열림: %s (손가락 %s, 장치 %s)" % [_map != null and _map._open, touch._touches, InputDevice.current])
		_fake_touch(Vector2(s.x - 76, 76), false)
		await tree.create_timer(0.2).timeout
		_fake_touch(Vector2(s.x / 2.0, s.y / 2.0), true)
		await tree.create_timer(0.2).timeout
		_fake_touch(Vector2(s.x / 2.0, s.y / 2.0), false)
		await tree.create_timer(0.2).timeout
		print("[포탈시험] 화면 누름 → 지도 닫힘: %s, 멈춤 해제: %s" % [_map == null or not _map._open, not tree.paused])
		# 터치 '메뉴' 버튼
		_fake_touch(Vector2(76, 76), true)
		await tree.create_timer(0.3).timeout
		print("[포탈시험] 터치 '메뉴' 누름 → 메뉴 열림: %s" % (_pause != null and _pause.is_open()))
		_fake_touch(Vector2(76, 76), false)
		await tree.create_timer(0.2).timeout
		_fake_touch(Vector2(s.x / 2.0, s.y - 40), true)
		await tree.create_timer(0.2).timeout
		_fake_touch(Vector2(s.x / 2.0, s.y - 40), false)
		await tree.create_timer(0.2).timeout
		print("[포탈시험] 바깥 누름 → 메뉴 닫힘: %s (터치 영역 %s)" % [_pause == null or not _pause.is_open(), s])
	# 2) 포탈
	var portal: Portal = null
	for p in tree.get_nodes_in_group("portal"):
		portal = p
		break
	if portal == null:
		print("[포탈시험] 이 방에 깨어 있는 포탈이 없다")
		tree.quit()
		return
	# 다른 방에 가 본 것으로 친다
	Progress.portals["village_01"] = {"scene": "res://scenes/rooms/village_01.tscn", "name": "마을 · 입구의 거리", "region": "village"}
	Progress.portals["mine_02"] = {"scene": "res://scenes/rooms/mine_02.tscn", "name": "채굴장 · 관의 복도", "region": "mine"}
	player._invuln_timer = 9999.0
	player.global_position = portal.global_position + Vector2(-60, -40)
	player.velocity = Vector2.ZERO
	await tree.create_timer(0.6).timeout
	print("[포탈시험] 포탈 곁 상호작용 가능: %s, 알려진 포탈: %s, 지도에 포탈 자리: %s" % [player.can_interact, Progress.portals.keys(), Progress.visited_rooms[room_id]["portals"]])
	Input.action_press("interact")
	await tree.physics_frame
	Input.action_release("interact")
	await tree.create_timer(0.4).timeout
	var menu := _find_travel_menu()
	print("[포탈시험] 포탈 메뉴 열림: %s, 항목 %d, 멈춤: %s" % [menu != null, menu._items.size() if menu else 0, tree.paused])
	_save_screenshot("debug_portal_menu.png")
	if menu == null:
		tree.quit()
		return
	# 터치로 두 번째 줄을 고른다
	Progress.set_flag("_test_travelled")
	var target: String = menu._items[1]["id"]
	Progress.set_flag("_test_target_" + target)
	_fake_touch(menu._row_rect(1).get_center(), true)
	await tree.create_timer(0.1).timeout
	_fake_touch(menu._row_rect(1).get_center(), false)
	await tree.create_timer(0.2).timeout
	print("[포탈시험] 터치로 고른 포탈: %s → 다음 등장 자리 '%s'" % [target, Progress.next_spawn])
	if Progress.next_spawn == "":
		# 터치가 안 닿았으면 버튼으로 고른다
		await _fake_action("move_down")
		await _fake_action("jump")
		await tree.create_timer(0.2).timeout
		print("[포탈시험] 버튼으로 고른 뒤 다음 등장 자리 '%s'" % Progress.next_spawn)
	await tree.create_timer(6.0).timeout
	print("[포탈시험] 6초가 지나도 방이 바뀌지 않았다")
	tree.quit()


## Claude Code용: 달빛풀에서 쉬고 → 쉬자마자 메뉴가 열리지 않는지 → 손길을 한 번 더 눌러 메뉴 → 다른 달빛풀로 이동.
func _grasstest() -> void:
	var tree := get_tree()
	await tree.create_timer(0.5).timeout
	var grass := tree.get_first_node_in_group("moonlight_grass") as MoonlightGrass
	if grass == null:
		print("[달빛풀시험] 달빛풀이 없다")
		tree.quit()
		return
	Progress.grasses["canopy_wind"] = {"scene": "res://scenes/rooms/canopy_02.tscn", "name": "수관 · 바람의 틈 위"}
	player._invuln_timer = 9999.0
	player.global_position = grass.global_position + Vector2(50, -40)
	player.velocity = Vector2.ZERO
	await tree.create_timer(0.6).timeout
	Input.action_press("interact")
	await tree.physics_frame
	await tree.process_frame
	print("[달빛풀시험] 손길 직후: 소녀 상태 %s, 메뉴 열림 %s (처음 피우는 중이면 쉬기 전)" % [player.state_name(), _find_travel_menu() != null])
	Input.action_release("interact")
	await tree.create_timer(2.4).timeout
	print("[달빛풀시험] 2.4초 뒤: 소녀 상태 %s, 메뉴 저절로 열림 %s (false 여야 함), 등록된 달빛풀 %s" % [player.state_name(), _find_travel_menu() != null, Progress.grasses.keys()])
	Input.action_press("interact")
	await tree.physics_frame
	await tree.process_frame
	Input.action_release("interact")
	await tree.create_timer(0.4).timeout
	var menu := _find_travel_menu()
	print("[달빛풀시험] 손길 한 번 더: 메뉴 열림 %s, 항목 %d" % [menu != null, menu._items.size() if menu else 0])
	_save_screenshot("debug_grass_menu.png")
	if menu == null:
		tree.quit()
		return
	Progress.set_flag("_test_travelled")
	var next_i := (menu._index + 1) % menu._items.size()
	Progress.set_flag("_test_target_" + menu._items[next_i]["id"])
	await _fake_action("move_down")
	await _fake_action("jump")
	await tree.create_timer(0.2).timeout
	print("[달빛풀시험] 고른 뒤 다음 등장 자리: '%s'" % Progress.next_spawn)
	await tree.create_timer(6.0).timeout
	print("[달빛풀시험] 6초가 지나도 방이 바뀌지 않았다")
	tree.quit()


## 시험 2단계: 건너온 방에서 제대로 도착했는지 확인하고 끝낸다.
func _arrivaltest(label: String, _spawn: String) -> void:
	var tree := get_tree()
	await tree.create_timer(0.8).timeout
	var near := "?"
	var group := "portal" if label == "포탈" else "moonlight_grass"
	for n in tree.get_nodes_in_group(group):
		var want := false
		for f in Progress.flags:
			if str(f).begins_with("_test_target_") and str(f).trim_prefix("_test_target_") == (n.portal_id if group == "portal" else n.grass_id):
				want = true
		if want:
			near = "%.0f px" % player.global_position.distance_to(n.global_position)
	print("[%s시험·도착] 방 %s, 소녀 상태 %s, 입력 가능 %s, 목표까지 %s, 등장 자리 비움 %s, 멈춤 %s" % [label, scene_file_path.get_file(), player.state_name(), player.input_enabled, near, Progress.next_spawn == "", tree.paused])
	_save_screenshot("debug_%s_arrive.png" % ("portal" if group == "portal" else "grass"))
	tree.quit()


## Claude Code용: 키 바꾸기가 저장·복원되는지, 화면이 뜨는지 확인한다.
func _remaptest() -> void:
	var tree := get_tree()
	await tree.create_timer(0.4).timeout
	var k := InputEventKey.new()
	k.physical_keycode = KEY_O
	Keymap.rebind("attack_light", k)
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_X
	Keymap.rebind("attack_light", b)
	print("[키시험] 약공격 → 키보드 %s / 듀얼센스 %s / 엑스박스 %s, 파일 %s" % [Keymap.label_for("attack_light", "kb"), Keymap.label_for("attack_light", "ds"), Keymap.label_for("attack_light", "xb"), FileAccess.file_exists(Keymap.PATH)])
	print("[키시험] 회복(□가 빠졌는지) → %s, 안내 글자 %s" % [Keymap.label_for("heal", "ds"), InputDevice.prompt("attack_light")])
	var rs := RemapScreen.new()
	add_child(rs)
	rs.open()
	await tree.create_timer(0.4).timeout
	_save_screenshot("debug_remap.png")
	rs.close()
	Keymap.reset_defaults()
	print("[키시험] 되돌린 뒤 약공격 → %s / %s, 파일 %s, 음악 %s" % [Keymap.label_for("attack_light", "kb"), Keymap.label_for("attack_light", "ds"), FileAccess.file_exists(Keymap.PATH), Music.current()])
	tree.quit()

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
## 이 방에 들어온 자리 (Progress.next_spawn 값: 표식 이름 / "Grass:<id>" / "" = 새로 시작·이어하기·시험). _reload_here 가 같은 자리로 다시 읽는다.
var _arrival_spawn := ""
## 처음 놓인 적들: [{scene, position, parent, props, key: 순번 글자, track: 쓰러뜨림을 기억하는가}]
## key = 방에 놓인 순서(트리 순서)의 번호. 쓰러뜨린 일반 적은 Progress.killed[room_id][key] 에 남아 달빛풀에서 쉬기 전까지 다시 나타나지 않는다
## (v1.1.0 기획자 요청 13). 구원할 수 있는 자·깃발이 있는 적(중간 보스·거대화 적)·중간 보스 방의 보스는 기억하지 않는다 —
## 그들은 구원 기록·깃발이 맡는다 (구원할 수 있는 사람은 반드시 구원된다).
var _enemy_spawns: Array = []
## 포탈·달빛풀로 들어선 뒤 적이 소녀를 알아채지 않는 시간(초). 화면이 밝아지는 1.2초 + 둘러볼 틈.
const ARRIVAL_GRACE := 2.8
## 지도용 탐사 요소의 id 목록 (방에 들어올 때 한 번 모은다): pickups / rescues / records / grasses / minibosses / walls / bosses
## minibosses = 이 방 중간 보스의 깃발(defeat_flag). 쓰러뜨려야 '모두 찾음'이 된다 (2026-10-19 기획자 결정).
## walls = 금 간 벽(CrackedWall.secret_id, 부숴야), bosses = 지역 보스 깃발(정화해야) — v1.1.0 기획자 요청 23·24.
var _explore_ids := {}
var _explore_timer := 0.0


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player") as Player
	EnemyBase.arrival_grace_until = 0.0
	var arrived_resting := false   # 달빛풀로 이동해 와서 쉬는 자세로 도착 (음악: 쉼터 곡을 이어 간다)
	var arrived_spawn := Progress.next_spawn   # 다른 방에서 넘어왔는가 (비어 있으면 새로 시작·이어하기·시험)
	_arrival_spawn = arrived_spawn
	if player:
		# 다른 방에서 넘어왔다면 그 출구에 맞는 자리에 선다
		if Progress.next_spawn != "":
			# 게임 시간(물리 틱)으로 잰다: 방을 띄우며 기기가 1~2초 멈춰도 유예가 미리 지나가지 않게 (2026-10-19 검수)
			EnemyBase.arrival_grace_until = float(Engine.get_physics_frames()) + ARRIVAL_GRACE * Engine.physics_ticks_per_second
			if Progress.next_spawn.begins_with("Grass:"):
				var gid := Progress.next_spawn.trim_prefix("Grass:")
				for g in get_tree().get_nodes_in_group("moonlight_grass"):
					if g.grass_id == gid:
						player.position = g.global_position + Vector2(60, -2)
						rest_point = g.global_position + Vector2(0, -2)
						g.arrive(player)
						arrived_resting = true
			else:
				var marker := get_node_or_null("Markers/" + Progress.next_spawn)
				if marker:
					player.position = marker.position
					player.facing = 1 if marker.position.x < bounds.get_center().x else -1
					# 포탈로 건너왔다면 그 포탈이 번쩍인다
					for p in get_tree().get_nodes_in_group("portal"):
						if p.global_position.distance_to(marker.position) < 260.0:
							p.flash()
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
		player.state_changed.connect(_on_player_state_for_music)
		# 방을 옮겨도 체력·이슬은 이어진다 (v1.1.0 기획자 요청 13 — Game.go_to 가 앞 방에서 적어 둔 값).
		# 달빛풀로 도착하면 쉬기(가득)라서 이어 받지 않는다. 기력(가드 게이지)은 이어 가지 않는다 (가득).
		if not arrived_resting and arrived_spawn != "" and Progress.carry_hp >= 0.0:
			player.set_vitals(Progress.carry_hp, Progress.carry_dews if Progress.carry_dews >= 0 else player.dews)
	# 한 번 이어 받은 값은 지운다 (다음 방에서 다시 쓰이지 않게)
	Progress.carry_hp = -1.0
	Progress.carry_dews = -1
	var overrides := _scene_overrides()
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node2D and e.scene_file_path != "":
			var info := {"scene": e.scene_file_path, "position": e.position, "parent": e.get_parent(),
				"props": overrides.get(_rel_path(e), {}), "key": str(_enemy_spawns.size()), "track": _tracks_kill(e)}
			_enemy_spawns.append(info)
			_bind_enemy(e, info, true)
	Purity.progress.connect(_on_purity_progress)
	Purity.apply_region(region)
	Purity.apply_depth(TerrainSkin.depth_of(self))   # 앞뒤 가르기 (배경 아지랑이·앞 지형·뒤 그림자 — 방의 그림 옷 데이터)
	TerrainSkin.keep_region(region)   # 다른 지역 그림 옷은 기억에서 뺀다 (메모리)
	_register_on_map()
	Progress.collected_changed.connect(_on_explore_changed)
	Progress.flag_changed.connect(_on_explore_flag_changed)
	_apply_room_settings()
	Settings.changed.connect(_apply_room_settings)
	# 들판 곡 (지역·방에 따라, Music.region_track). 아직 정화하지 않은 보스 방은 앞 방의 곡이 이어지다 싸움이 시작되면 보스곡으로.
	var field_now: bool = not (self is BossRoom) or Progress.has(get("defeat_flag") if "defeat_flag" in self else "")
	Music.enter_room(region, room_id, field_now, arrived_resting)
	if dark:
		var cm := CanvasModulate.new()
		cm.color = dark_color
		add_child(cm)
		if player:
			player.set_light(true)
	PostEnding.apply(self)   # 엔딩 뒤: 마지막으로 본 엔딩에 따라 마을의 빛이 바뀐다 (endings*.json 의 post)
	Game.fade_in(1.2)
	RescuedHomes.spawn_into(self)   # 구원되어 '집'으로 돌아간 사람들을 세운다 (data/dialogue/relocations.json)
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
			Progress.visited_rooms["canopy_02"] = {"offset": Vector2(4800, -1600), "size": Vector2(2400, 2600), "name": "수관 · 바람의 틈", "region": "canopy", "grasses": [Vector2(2050, 300)], "boss": false, "explore_total": 1, "explore_found": 1}
			Progress.visited_rooms["canopy_03"] = {"offset": Vector2(7200, -2400), "size": Vector2(5200, 1400), "name": "수관 · 잎의 회랑", "region": "canopy", "grasses": [], "boss": false, "explore_total": 2, "explore_found": 0}
			Progress.visited_rooms["canopy_boss"] = {"offset": Vector2(15900, -2623), "size": Vector2(3600, 1800), "name": "수관 · 꼭대기의 하늘", "region": "canopy", "grasses": [Vector2(330, 1380)], "boss": true, "explore_total": 1, "explore_found": 0}
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
	elif "--nooktest" in args:
		_nooktest()
	elif "--camtest" in args:
		_camtest()
	elif "--secrettest" in args:
		_secrettest()


func _process(delta: float) -> void:
	if player and player.position.y > bounds.end.y + 200.0 and player.state != Player.State.DEAD:
		# 방 밖으로 떨어졌다: 가시에 떨어진 것처럼 피해를 입고 마지막 안전한 자리로
		if player.last_safe_position == Vector2.ZERO:
			player.last_safe_position = rest_point
		player.take_hazard(15.0)
	# 지도용 탐사 수를 0.5초마다 다시 센다 (구원·읽기·피우기는 신호로도 잡히지만, 안전하게)
	_explore_timer += delta
	if _explore_timer >= 0.5:
		_explore_timer = 0.0
		refresh_explore()


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
	elif event.is_action_pressed("map") and not BossRush.active:
		open_map()   # 보스 러시 중에는 지도를 열지 않는다


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
## 지도용 계약: visited_rooms[room_id] 에 "explore_total"(이 방의 탐사 요소 수) 와 "explore_found"(그중 찾은 수) 를 넣는다.
## 탐사 요소 = 아이템(Pickup, 비밀 안의 것 포함) + 구원 가능한 자 + 기록물 + 달빛풀(장식 아님) + 중간 보스(쓰러뜨림)
## + 금 간 벽(부숨) + 지역 보스(정화). 다 찾으면(0/0 포함) 지도에서 초록.
func _register_on_map() -> void:
	if room_id == "":
		return
	var grasses: Array = []
	for g in get_tree().get_nodes_in_group("moonlight_grass"):
		grasses.append(g.position)
	var portals: Array = []
	for p in get_tree().get_nodes_in_group("portal"):
		portals.append(p.position)
	_explore_ids = _collect_explore_ids()
	var prev: Dictionary = Progress.visited_rooms.get(room_id, {})
	# 이미 구원된 자는 노드가 사라져 있을 수 있으니, 전에 기록한 구원 id 가운데 실제로 구원된 것은 합쳐 둔다.
	# (아이템·기록물·달빛풀은 노드가 늘 남아 있으므로 지금 센 것만 쓴다 → 배치를 바꿔도 옛 값이 남지 않는다)
	var prev_ids = prev.get("explore_ids", {})
	if not (prev_ids is Dictionary):
		prev_ids = {}   # 아주 옛 형식(배열)은 버리고 지금 센 것만 쓴다
	for id in prev_ids.get("rescues", []):
		if Progress.rescued.has(id) and not _explore_ids["rescues"].has(id):
			_explore_ids["rescues"].append(id)
	# 중간 보스도 쓰러뜨리면 노드가 사라진다 → 전에 기록한 깃발 가운데 쓰러뜨린 것은 남겨 둔다
	for flag in prev_ids.get("minibosses", []):
		if Progress.has(str(flag)) and not _explore_ids["minibosses"].has(flag):
			_explore_ids["minibosses"].append(flag)
	var entry := {"offset": map_offset, "size": bounds.size, "name": display_name if display_name != "" else room_id, "region": region, "grasses": grasses, "portals": portals, "boss": is_boss_room}
	entry["explore_ids"] = _explore_ids
	entry["explore_total"] = _explore_total()
	entry["explore_found"] = _explore_found()
	Progress.visited_rooms[room_id] = entry


## 이 방의 탐사 요소 id 목록을 모은다 (Room._ready 는 자식들의 _ready 뒤에 돌므로 모두 자리에 있다).
## 중간 보스: 방의 깃발(MiniBossRoom.defeat_flag, _miniboss_flags) + 깃발을 가진 적(EnemyBase.defeat_flag — 거대화 중간 보스·잿가지 거인).
## 이미 쓰러뜨린 보스는 _ready 에서 queue_free 되지만 이 프레임 끝까지는 남아 있고, 방의 깃발로도 센다.
func _collect_explore_ids() -> Dictionary:
	var ids := {"pickups": [], "rescues": [], "records": [], "grasses": [], "minibosses": [], "walls": [], "bosses": []}
	for flag in _miniboss_flags():
		if flag != "" and not ids["minibosses"].has(flag):
			ids["minibosses"].append(flag)
	for flag in _boss_flags():
		if flag != "" and not ids["bosses"].has(flag):
			ids["bosses"].append(flag)
	var nodes: Array = []
	_walk(self, nodes)
	for n in nodes:
		if n is Pickup:
			if n.pickup_id != "" and not ids["pickups"].has(n.pickup_id):
				ids["pickups"].append(n.pickup_id)
		elif n is Record:
			if n.record_id != "" and not ids["records"].has(n.record_id):
				ids["records"].append(n.record_id)
		elif n is MoonlightGrass:
			if not n.decor and n.grass_id != "" and not ids["grasses"].has(n.grass_id):
				ids["grasses"].append(n.grass_id)
		elif n is CrackedWall:
			if n.secret_id != "" and not ids["walls"].has(n.secret_id):
				ids["walls"].append(n.secret_id)
		elif n is EnemyBase:
			if n.savable and n.rescue_id != "" and not ids["rescues"].has(n.rescue_id):
				ids["rescues"].append(n.rescue_id)
			if n.defeat_flag != "" and not ids["minibosses"].has(n.defeat_flag):
				ids["minibosses"].append(n.defeat_flag)
	return ids


## 이 방에 있는 중간 보스의 깃발들. 보통 방은 없음, MiniBossRoom 이 자기 defeat_flag 를 돌려준다.
func _miniboss_flags() -> Array:
	return []


## 이 방의 지역 보스 깃발들 (v1.1.0 기획자 요청 24: 보스 방은 보스를 정화해야 '모두 찾음'). 보통 방은 없음, BossRoom 이 돌려준다.
func _boss_flags() -> Array:
	return []


func _walk(node: Node, out: Array) -> void:
	for c in node.get_children():
		out.append(c)
		_walk(c, out)


func _explore_total() -> int:
	var n := 0
	for k in _explore_ids:
		n += (_explore_ids[k] as Array).size()
	return n


func _explore_found() -> int:
	var n := 0
	for id in _explore_ids.get("pickups", []):
		if Progress.is_collected(id):
			n += 1
	for id in _explore_ids.get("rescues", []):
		if Progress.rescued.has(id):
			n += 1
	for id in _explore_ids.get("records", []):
		if Progress.has("read_" + id):
			n += 1
	for id in _explore_ids.get("grasses", []):
		if Progress.grasses.has(id):
			n += 1
	for flag in _explore_ids.get("minibosses", []):
		if Progress.has(flag):
			n += 1
	for id in _explore_ids.get("walls", []):
		if Progress.is_collected(id):
			n += 1
	for flag in _explore_ids.get("bosses", []):
		if Progress.has(flag):
			n += 1
	return n


## 탐사 수를 다시 센다 (아이템을 줍거나 구원·읽기·피우기가 일어난 뒤).
func refresh_explore() -> void:
	if room_id == "" or not Progress.visited_rooms.has(room_id):
		return
	var entry: Dictionary = Progress.visited_rooms[room_id]
	entry["explore_total"] = _explore_total()
	entry["explore_found"] = _explore_found()


func _on_explore_changed(_id: String) -> void:
	refresh_explore()


func _on_explore_flag_changed(_flag: String, _value: bool) -> void:
	refresh_explore()


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


## 모든 일반 적을 처음 자리로 되돌린다 (불사의 저주). 단 쓰러뜨린 기록(Progress.killed)이 남은 적은 그대로 비워 둔다 —
## 달빛풀에서 쉬거나 쓰러져 다시 일어날 때는 기록을 먼저 지우고(clear_killed) 부르므로 모두 돌아온다.
func respawn_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	for info in _enemy_spawns:
		if _is_killed_spawn(info):
			continue
		var scene: PackedScene = load(info["scene"])
		if scene == null:
			continue
		var e := scene.instantiate()
		e.position = info["position"]
		# 방 파일이 이 적에게 덮어쓴 값(rescue_id, patrol_range …)을 다시 넣는다. 씬 기본값으로 깨어나면
		# 광부 하론이 '나무꾼 베릴'로 바뀌거나(구원 id 가 기본값으로) 사라졌다 (2026-10-19 검수)
		var props: Dictionary = info.get("props", {})
		for k in props:
			e.set(k, props[k])
		_bind_enemy(e, info, false)
		(info["parent"] as Node).add_child(e)


## 이 적의 쓰러뜨림을 기억하는가 (처음 놓인 적을 모을 때 한 번 묻는다).
## 구원할 수 있는 자(구원 기록이 맡음)·깃발이 있는 적(깃발이 맡음)은 빼고, MiniBossRoom 은 자기 보스도 뺀다.
func _tracks_kill(e: Node) -> bool:
	var eb := e as EnemyBase
	if room_id == "" or eb == null:
		return false
	return not eb.savable and eb.defeat_flag == ""


## 이 자리의 적은 쓰러뜨린 기록이 있는가
func _is_killed_spawn(info: Dictionary) -> bool:
	return bool(info.get("track", false)) and Progress.is_killed(room_id, str(info.get("key", "")))


## 적에게 자리 번호를 붙이고 쓰러짐을 듣는다. already_in_tree: 방 파일에 처음부터 있던 적 (기록이 있으면 지운다 — 묘목·빛 가루 없이).
func _bind_enemy(e: Node, info: Dictionary, already_in_tree: bool) -> void:
	var key := str(info.get("key", ""))
	e.set_meta("spawn_key", key)
	if not bool(info.get("track", false)):
		return
	if already_in_tree and Progress.is_killed(room_id, key):
		e.remove_from_group("enemy")
		e.queue_free()
		return
	var eb := e as EnemyBase
	if eb:
		eb.died.connect(_on_enemy_killed.bind(key))   # 적 하나에 한 번만 불린다 (처음 놓일 때 / 다시 만들 때)


## 일반 적을 쓰러뜨렸다 (정화했든 아니든): 달빛풀에서 쉬기 전까지 이 자리는 비어 있다.
func _on_enemy_killed(_purified: bool, key: String) -> void:
	if room_id != "":
		Progress.mark_killed(room_id, key)


## 방 파일(.tscn)이 인스턴스 노드에 덮어쓴 속성들: { "Enemies/MinerSavable": {"rescue_id": "miner_hidden", …} }.
## 자리(position)는 따로 적으므로 뺀다. 다시 깨울 때(respawn_enemies) 같은 값을 넣어 준다.
func _scene_overrides() -> Dictionary:
	var out := {}
	if scene_file_path == "":
		return out
	var ps := load(scene_file_path) as PackedScene
	if ps == null:
		return out
	var st := ps.get_state()
	for i in st.get_node_count():
		if st.get_node_instance(i) == null:
			continue
		var path := _clean_path(str(st.get_node_path(i)))
		var props := {}
		for j in st.get_node_property_count(i):
			var pname := st.get_node_property_name(i, j)
			if pname in ["position", "rotation", "scale", "transform"]:
				continue
			props[pname] = st.get_node_property_value(i, j)
		if not props.is_empty():
			out[path] = props
	return out


func _rel_path(n: Node) -> String:
	return _clean_path(str(get_path_to(n)))


static func _clean_path(p: String) -> String:
	return p.trim_prefix("./")


func _on_player_rested(grass: Node2D) -> void:
	rest_point = grass.global_position + Vector2(0, -2)
	Progress.clear_killed()   # 쉬면 쓰러뜨린 적이 모두 돌아온다 (모든 방)
	respawn_enemies()
	_rest_music = true
	Music.rest_begin()   # 쉬는 동안 쉼터 곡 (rest_moonlight_grass)


## 쉬는 자세에서 어떤 식으로든 벗어나면(일어서기 등) 들판 곡으로 돌아간다.
## (쉬기 전의 상태 변화는 보지 않는다: 달빛풀로 이동해 와서 쉬는 자세가 되기 직전에 쉼터 곡이 끊기지 않게)
var _rest_music := false
func _on_player_state_for_music(new_state: int) -> void:
	if _rest_music and new_state != Player.State.REST:
		_rest_music = false
		Music.rest_end()


## 쓰러졌다 (v1.1.0 기획자 요청 13, D10): 2.6초 뒤 마지막으로 쉰 달빛풀에서 '쉬기'와 같게 깨어난다 —
## 그 방을 다시 읽으므로(같은 방이어도) 체력·이슬·기력이 가득하고, 쓰러뜨린 적이 모두 돌아오고, 보스 방이면 보스도 새로 나온다.
## 아직 달빛풀에서 쉰 적이 없으면 이 방의 시작 자리에서 일어난다. (BossRoom·MiniBossRoom 도 같은 규칙: _respawn_at_last_grass)
func _on_player_died() -> void:
	await get_tree().create_timer(2.6).timeout
	if player == null or not is_instance_valid(player):
		return
	if _respawn_at_last_grass():
		return
	_revive_here()


## 마지막으로 쉰 달빛풀의 방으로 (그 달빛풀에서 쉬는 자세로 도착). 갈 수 없으면 false (보스 러시·쉰 적 없음·장면 전환 중·
## 이 방이 '지금 장면'이 아님 — 시험이 방을 자기 자식으로 놓았을 때 장면 바꾸기가 시험 자체를 지우지 않게, 그 자리에서 일어난다).
func _respawn_at_last_grass() -> bool:
	if BossRush.active or Game.is_busy() or not is_inside_tree() or get_tree().current_scene != self:
		return false
	var gid := str(Progress.last_grass.get("id", ""))
	# 달빛풀이 있는 방은 방 목록(RoomIndex)에서 찾는다 (없으면 저장된 경로). 방 파일이 아니면 가지 않는다.
	var scene := RoomIndex.scene_of(RoomIndex.room_of_grass(gid))
	if scene == "":
		scene = str(Progress.last_grass.get("scene", ""))
	if gid == "" or not scene.begins_with("res://scenes/rooms/") or not ResourceLoader.exists(scene):
		return false
	Progress.clear_killed()
	Progress.carry_hp = -1.0
	Progress.carry_dews = -1
	Progress.next_spawn = "Grass:" + gid
	Game.go_to(scene, 0.8, 1.0)
	return true


## 쉰 달빛풀이 없을 때 이 방을 다시 읽어 들어온 자리(_arrival_spawn)에서 일어난다 — 보스 방 재도전을 처음 상태로
## (v1.1.0 기획자 요청 13: 보스 잎 더미·연속 공격 단계까지 새로). 체력·이슬은 가득(쓰러진 소녀는 Game.go_to 가 적지 않는다).
## 갈 수 없으면 false (보스 러시·장면 전환 중·이 방이 '지금 장면'이 아님·방 파일 없음).
func _reload_here() -> bool:
	if BossRush.active or Game.is_busy() or not is_inside_tree() or get_tree().current_scene != self:
		return false
	if not scene_file_path.begins_with("res://scenes/rooms/"):
		return false
	Progress.clear_killed()
	Progress.carry_hp = -1.0
	Progress.carry_dews = -1
	Progress.next_spawn = _arrival_spawn if not _arrival_spawn.begins_with("Grass:") else ""
	Game.go_to(scene_file_path, 0.8, 1.0)
	return true


## 이 방에서 그대로 일어난다 (쉰 달빛풀이 없을 때): 쓰러뜨린 적이 돌아오고 체력·이슬이 가득.
func _revive_here() -> void:
	Progress.clear_killed()
	respawn_enemies()
	player.revive(rest_point)
	var cam := player.get_node_or_null("Camera2D")
	if cam:
		cam.reset_smoothing()


func _save_screenshot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return   # 화면 없는 시험에서는 찍지 않는다
	var tex := get_viewport().get_texture()
	if tex == null:
		return
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
	# 씨앗 베기 (처음부터 있는 영혼 기술, 옛 강공격 자리)
	var hp1 := enemy.hp
	player._invuln_timer = 2.5   # 시험용: 예비동작 중에 맞아 끊기지 않게
	player.soul = "seed"
	Input.action_press("soul_ability")
	await tree.physics_frame
	Input.action_release("soul_ability")
	await tree.create_timer(1.0).timeout
	if is_instance_valid(enemy):
		print("[자동시험] 씨앗 베기 뒤 적 체력: %.0f → %.0f (흐트러짐 %.0f, 상태 %s)" % [hp1, enemy.hp, enemy.poise, enemy.state_name()])
	else:
		print("[자동시험] 씨앗 베기로 적이 쓰러졌다 (체력 %.0f 에서). 다음 적으로 옮긴다." % hp1)
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
	# 씨앗 베기의 넉백(420)과 무너짐(3.5초) 때문에 적이 제때 못 와서 결과가 들쭉날쭉했다 (2026-10-18 검토):
	# 적을 싸울 수 있는 상태로 되돌리고 바로 옆에 서서, 실제로 막은 신호(guard_hit)가 올 때까지 기다린다.
	if enemy.state == EnemyBase.State.BROKEN or enemy.state == EnemyBase.State.HIT:
		enemy._set_state(EnemyBase.State.IDLE)
	enemy.poise = 0.0
	enemy.velocity = Vector2.ZERO
	player.position = enemy.position + Vector2(-130, -10)
	player.facing = 1
	player.velocity = Vector2.ZERO
	player._invuln_timer = 0.0
	await tree.create_timer(0.3).timeout
	var php0 := player.hp
	var guard_hits := []
	var on_guard_hit := func(d): guard_hits.append(d)
	player.guard_hit.connect(on_guard_hit)
	Input.action_press("guard")
	var waited := 0.0
	while waited < 6.0 and guard_hits.is_empty() and player.state != Player.State.HIT:
		await tree.physics_frame
		waited += get_physics_process_delta_time()
		if player.state != Player.State.GUARD and player.state != Player.State.HIT:
			Input.action_press("guard")
	await tree.create_timer(0.2).timeout
	player.guard_hit.disconnect(on_guard_hit)
	print("[자동시험] 가드 중 피격: 소녀 체력 %.0f → %.0f, 가드 게이지 %.0f, 상태 %s, 막은 피해 %s (%.1f초 기다림)" % [php0, player.hp, player.guard, player.state_name(), guard_hits, waited])
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
	# 회복 (시험용으로 잠깐 무적: 적의 공격에 끊기면 회복 자체를 못 본다)
	player._invuln_timer = 1.5
	if not (player.state in Player.LOCOMOTION):
		player._set_state(Player.State.IDLE)
	await tree.physics_frame
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
	while is_instance_valid(savable) and savable.state != EnemyBase.State.BROKEN and tries < 8:
		# 매번 곁에 다시 선다 (경비병이 돌진해 멀어지거나 정원사가 물러나도 칼이 닿게)
		player.global_position = savable.global_position + Vector2(-140, 0)
		player.velocity = Vector2.ZERO
		player.facing = 1
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
			e.charge_chance = 1.0   # 장면 찍기용: 첫 공격이 반드시 돌진이 되게 (무작위 제거)
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
			# 정면 공격은 튕긴다: 박힘이 풀려 추격으로 돌아올 때까지 기다렸다가(박힌 동안은 막지 못한다, 풀린 뒤 1.2초는 공격을 쉰다)
			# 경비병이 보는 쪽에 마주 선다 (경비병은 늦게 돌아서므로 등 뒤에 서면 그냥 맞는다)
			var w2 := 0.0
			while w2 < 4.0 and (e._mode == "stuck" or e.state != EnemyBase.State.CHASE):
				await tree.physics_frame
				w2 += get_physics_process_delta_time()
			player.global_position = e.global_position + Vector2(e.facing * 120.0, 0)
			player.velocity = Vector2.ZERO
			player.facing = -e.facing
			await tree.create_timer(0.15).timeout
			var hp0: float = e.hp
			Input.action_press("attack_light")
			await tree.physics_frame
			Input.action_release("attack_light")
			await tree.create_timer(0.5).timeout
			print("[마을시험] 정면 공격 뒤 경비병 체력 %.0f → %.0f (상태 %s, 그림 방향 %d)" % [hp0, e.hp, e.state_name(), e.get_node("Visual").visible_facing()])
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
	print("[저장시험] 읽은 뒤: 방 %s, 깃발 %s, 능력 %s, 성장 %s, 달빛풀 %s, 등장 %s, 마지막 달빛풀 %s" % [scene.get_file(), Progress.has("test_flag"), Progress.abilities, Progress.upgrades, Progress.grasses.keys(), Progress.next_spawn, Progress.last_grass])
	# 메뉴의 '지금 저장하기' / 표시 글자
	var where := SaveGame.save_now()
	print("[저장시험] 지금 저장하기 → 이어질 곳 '%s', 저장한 때 '%s'" % [where, SaveGame.saved_at_text()])
	# 일시정지 메뉴 열어 찍기
	_pause = PauseMenu.new()
	add_child(_pause)
	_pause.open()
	await tree.create_timer(0.4).timeout
	_save_screenshot("debug_pause.png")
	_pause.close()
	SaveGame.new_game()
	print("[저장시험] 새로 시작 뒤 저장 파일 있음: %s" % SaveGame.has_save())
	DirAccess.remove_absolute(SaveGame.PATH)   # 시험이 남긴 새 칸 파일을 치운다 (v1.1.0: new_game 이 곧바로 저장한다 — 뒤 시험이 '저장 없음'에서 시작하게)
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


## 시험용: 동작을 상태로 눌렀다가 물리 한 틱 뒤에 뗀다 (소녀처럼 Input.is_action_just_pressed 로 듣는 쪽용).
func _press_action(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().process_frame
	Input.action_release(action)


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


## Claude Code용: 터치 '지도'·'메뉴' 버튼이 열리는지, 포탈 앞에서 손길(interact)을 눌러 옆 방으로 건너가는지 확인한다.
## (↑로 들어가던 것은 뺐으므로 ↑를 눌러도 아무 일이 없어야 한다.)
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
		# 지도는 끌기·두 손가락으로 움직이므로 화면 가운데를 눌러도 닫히지 않는다 → 오른쪽 위 ✕ (지도 버튼과 같은 자리)
		_fake_touch(Vector2(s.x / 2.0, s.y / 2.0), true)
		await tree.create_timer(0.1).timeout
		_fake_touch(Vector2(s.x / 2.0, s.y / 2.0), false)
		await tree.create_timer(0.2).timeout
		print("[포탈시험] 화면 가운데 누름 → 지도 그대로: %s" % [_map != null and _map._open])
		_fake_touch(Vector2(s.x - 76, 76), true)
		await tree.create_timer(0.2).timeout
		_fake_touch(Vector2(s.x - 76, 76), false)
		await tree.create_timer(0.2).timeout
		print("[포탈시험] ✕ 누름 → 지도 닫힘: %s, 멈춤 해제: %s" % [_map == null or not _map._open, not tree.paused])
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
	# 2) 포탈: 잠긴 포탈이 있으면 먼저 막히는지, 그 다음 열린 포탈로 건너간다
	var portals: Array = tree.get_nodes_in_group("portal")
	if portals.is_empty():
		print("[포탈시험] 이 방에 포탈이 없다")
		tree.quit()
		return
	print("[포탈시험] 이 방의 포탈 %d개: %s, 지도에 포탈 자리: %s" % [portals.size(), portals.map(func(p): return "%s→%s" % [p.name, p.target_scene.get_file()]), Progress.visited_rooms[room_id]["portals"]])
	player._invuln_timer = 9999.0
	var target: Portal = null
	for p in portals:
		if p.requires_ability != "" and not Progress.has_ability(p.requires_ability):
			player.global_position = p.global_position + Vector2(-40, -70)
			player.velocity = Vector2.ZERO
			await tree.create_timer(0.6).timeout
			await _press_action("interact")
			await tree.create_timer(0.5).timeout
			print("[포탈시험] 잠긴 포탈(%s)에서 손길: 그대로 이 방 %s, 안내 '%s'" % [p.requires_ability, tree.current_scene == self, get_node("CombatHUD")._message])
		elif target == null:
			target = p
	player.global_position = target.global_position + Vector2(-40, -70)
	player.velocity = Vector2.ZERO
	await tree.create_timer(0.6).timeout
	print("[포탈시험] 포탈 앞: 상호작용 가능 %s, 바닥 %s, 터치 상황 버튼 글자 '%s'" % [player.can_interact, player.is_on_floor(), touch._interact_label() if touch else "-"])
	# ↑는 더 이상 포탈과 무관하다: 눌러도 방이 바뀌지 않아야 한다
	await _press_action("move_up")
	await tree.create_timer(0.3).timeout
	print("[포탈시험] ↑ 누름 → 다음 등장 자리 '%s' (비어 있어야 함), 입력 가능 %s, 그대로 이 방 %s" % [Progress.next_spawn, player.input_enabled, tree.current_scene == self])
	Progress.set_flag("_test_travelled")
	Progress.set_flag("_test_target_" + target.spawn_name)
	await _press_action("interact")
	await tree.create_timer(0.3).timeout
	print("[포탈시험] 손길 누름 → 다음 등장 자리 '%s', 입력 잠김 %s" % [Progress.next_spawn, not player.input_enabled])
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


## Claude Code용 (첫 방): 꼭대기 가지에서 이단 점프로 천장 틈의 비밀 발판(윗면 y=60)에 올라서는지 확인한다.
func _nooktest() -> void:
	var tree := get_tree()
	await tree.create_timer(0.5).timeout
	Progress.gain_ability("double_jump")
	player._apply_abilities()
	player._invuln_timer = 9999.0
	for e in tree.get_nodes_in_group("enemy"):
		e.queue_free()   # 꼭대기 가지의 나무꾼이 끼어들지 않게
	player.global_position = Vector2(1650, 332)   # 꼭대기 가지(윗면 400) 위, 틈 바로 아래
	player.velocity = Vector2.ZERO
	await tree.create_timer(0.5).timeout
	var top := player.global_position.y
	print("[틈시험] 누르기 전: 상태 %s, 바닥 %s, 입력 %s, 자리 %s" % [player.state_name(), player.is_on_floor(), player.input_enabled, player.global_position])
	# 점프는 최고점까지 누르고 있어야 짧은 점프가 되지 않는다
	Input.action_press("jump")
	var trace := []
	var t := 0.0
	var second_done := false
	while t < 2.4:
		await tree.physics_frame
		t += get_physics_process_delta_time()
		top = minf(top, player.global_position.y)
		if t >= 0.4 and not second_done:
			# 최고점에서 손을 뗐다가 다시 눌러 이단 점프
			second_done = true
			Input.action_release("jump")
			await tree.physics_frame
			Input.action_press("jump")
		if t >= 0.9 and Input.is_action_pressed("jump"):
			Input.action_release("jump")
		if int(t * 20.0) != int((t - get_physics_process_delta_time()) * 20.0):
			trace.append("%.2f:%d/v%d%s%s" % [t, player.global_position.y, player.velocity.y, "F" if player.is_on_floor() else "", "P" if Input.is_action_pressed("jump") else ""])
	print("[틈시험] 시간:높이  " + " ".join(trace))
	print("[틈시험] 이단 점프 최고점 y=%.0f (비밀 발판에 서면 y=-8), 지금 y=%.0f, 바닥 %s, 최대 점프 수 %d, 남은 점프 %d" % [top, player.global_position.y, player.is_on_floor(), player.max_jumps, player._jumps_left])
	tree.quit()


## Claude Code용: 바닥에 서 있을 때 소녀의 발이 화면 아래에서 몇 px 위에 있는지 (보스 체력 바는 아래 150px 띠).
func _camtest() -> void:
	var tree := get_tree()
	await tree.create_timer(0.5).timeout
	player._invuln_timer = 9999.0
	for e in tree.get_nodes_in_group("enemy"):
		e.queue_free()
	var band := 0.0
	if has_method("_set_battle_camera"):
		call("_set_battle_camera", true)   # 보스 방: 싸움 카메라(0.88배, 위쪽 더 보기)
	var bhud := get_node_or_null("BossHUD")
	if bhud:
		bhud.show_boss()   # 레터박스 띠가 올라온다
	await tree.create_timer(2.5).timeout
	if bhud:
		band = bhud.band_px()
	var cam := get_viewport().get_camera_2d()
	var vp := get_viewport().get_visible_rect().size
	var center := cam.get_screen_center_position()
	var bottom_world := center.y + vp.y / 2.0 / cam.zoom.y
	var feet := player.global_position.y + 67.0
	var feet_px := (bottom_world - feet) * cam.zoom.y
	print("[카메라시험] %s: 확대 %.2f, 화면 아래 끝 세계 y=%.0f (방 경계 아래 %.0f, 카메라 아래 한계 %d), 소녀 발 y=%.0f → 화면 아래에서 %.0f px 위, 레터박스 띠 %.0f px (발이 띠 위: %s), 바닥 %s" % [scene_file_path.get_file(), cam.zoom.y, bottom_world, bounds.end.y, cam.limit_bottom, feet, feet_px, band, feet_px > band, player.is_on_floor()])
	tree.quit()


## Claude Code용: 이 방의 비밀 벽(옆에 서서 약공격 4번)·비밀 천장(아래서 점프해 머리 박기)과 아이템, 탐사 수, 세이브 복원을 확인한다.
## 여섯 방 어디서든 돈다: tools/test.sh <방> --secrettest
func _secrettest() -> void:
	var tree := get_tree()
	await tree.create_timer(0.5).timeout
	player._invuln_timer = 9999.0
	for e in tree.get_nodes_in_group("enemy"):
		e.queue_free()
	await tree.physics_frame
	var pickup: Pickup = null
	for p in tree.get_nodes_in_group("pickup"):
		pickup = p
		break
	var wall: SecretWall = null
	var ceiling: SecretCeiling = null
	for t in get_node("Terrain").get_children():
		if t is SecretCeiling:
			ceiling = t
		elif t is SecretWall:
			wall = t
	var entry: Dictionary = Progress.visited_rooms.get(room_id, {})
	print("[비밀시험] %s 시작: 탐사 %d / %d, id 목록 %s" % [room_id, entry.get("explore_found", -1), entry.get("explore_total", -1), _explore_ids])
	if Progress.has("_test_reentered"):
		# 2단계: 부수고 모은 뒤 다시 들어왔다. 벽은 부서진 채, 아이템은 없어야 한다.
		var sec: SecretWall = wall if wall else ceiling
		print("[비밀시험·재입장] 비밀 %s: 부서짐 %s, 보임 %s, 충돌 레이어 %d | 아이템 모음 %s, 보임 %s, 감지 %s | 탐사 %d / %d" % [sec.secret_id if sec else "-", sec._broken if sec else "-", sec.visible if sec else "-", sec.collision_layer if sec else -1, pickup.collected if pickup else "-", pickup.visible if pickup else "-", pickup.monitoring if pickup else "-", entry.get("explore_found", -1), entry.get("explore_total", -1)])
		SaveGame.new_game()
		DirAccess.remove_absolute(SaveGame.PATH)   # 시험이 남긴 새 칸 파일을 치운다 (v1.1.0: new_game 이 곧바로 저장한다 — 뒤 시험이 '저장 없음'에서 시작하게)
		tree.quit()
		return
	if pickup == null or (wall == null and ceiling == null):
		print("[비밀시험] 비밀이나 아이템이 없다 (벽 %s, 천장 %s, 아이템 %s)" % [wall != null, ceiling != null, pickup != null])
		tree.quit()
		return
	var space := get_world_2d().direct_space_state
	var hp0 := player.max_hp
	var dews0 := player.max_dews
	var atk0 := player.attack_multiplier
	var heal0 := player.heal_amount
	if wall:
		# 벽의 열린 쪽(소녀가 설 수 있는 쪽)을 찾아 그 바닥에 선다
		var c := wall.global_position + wall.size / 2.0
		var side := 0
		for s in [-1, 1]:
			var q := PhysicsRayQueryParameters2D.create(c, c + Vector2(s * (wall.size.x / 2.0 + 180.0), 0))
			q.exclude = [wall.get_rid()]
			if space.intersect_ray(q).is_empty():
				side = s
				break
		var stand_x := c.x + side * (wall.size.x / 2.0 + 120.0)
		var fq := PhysicsRayQueryParameters2D.create(Vector2(stand_x, c.y), Vector2(stand_x, c.y + 800.0))
		var floor_hit := space.intersect_ray(fq)
		var floor_y: float = floor_hit["position"].y if not floor_hit.is_empty() else c.y + wall.size.y / 2.0
		player.global_position = Vector2(stand_x, floor_y - 67.0)
		player.facing = -side
		player.velocity = Vector2.ZERO
		await tree.create_timer(0.4).timeout
		print("[비밀시험] 벽 %s (%s 크기 %s): 열린 쪽 %s, 소녀 자리 %s (바닥 %s), 맞은 수 %d, 충돌 레이어 %d, 아이템 보임 %s / 감지 %s" % [wall.secret_id, wall.global_position, wall.size, "왼쪽" if side < 0 else "오른쪽", player.global_position.round(), player.is_on_floor(), wall._hits, wall.collision_layer, pickup.visible, pickup.monitoring])
		for i in 4:
			Input.action_press("attack_light")
			await tree.physics_frame
			Input.action_release("attack_light")
			await tree.create_timer(0.4).timeout
			print("[비밀시험] 약공격 %d번째 뒤: 맞은 수 %d, 부서짐 %s" % [i + 1, wall._hits, wall._broken])
		await tree.create_timer(0.3).timeout
		print("[비밀시험] 벽 충돌 레이어 %d, 보임 %s, 기록 %s, 아이템 보임 %s / 감지 %s" % [wall.collision_layer, wall.visible, Progress.is_collected(wall.secret_id), pickup.visible, pickup.monitoring])
	if ceiling:
		# 옹이 바로 아래 바닥에 서서 점프한다
		var bottom := ceiling.global_position + Vector2(ceiling.size.x / 2.0, ceiling.size.y)
		var fq := PhysicsRayQueryParameters2D.create(bottom + Vector2(0, 4), bottom + Vector2(0, 1400))
		var floor_hit := space.intersect_ray(fq)
		var floor_y: float = floor_hit["position"].y if not floor_hit.is_empty() else bottom.y + 300.0
		# 먼저 옹이의 왼쪽 끝 밑(그림상 둥글어 허공인 자리)에서 점프: 충돌 모양이 그림과 같으면 부서지지 않아야 한다
		for edge_dx in [2.0, 20.0]:
			player.global_position = Vector2(ceiling.global_position.x + edge_dx, floor_y - 67.0)
			player.velocity = Vector2.ZERO
			await tree.create_timer(0.3).timeout
			Input.action_press("jump")
			var et := 0.0
			var etop := player.global_position.y
			while et < 1.0:
				await tree.physics_frame
				et += get_physics_process_delta_time()
				etop = minf(etop, player.global_position.y)
				if et >= 0.4 and Input.is_action_pressed("jump"):
					Input.action_release("jump")
			# 소녀 몸통(폭 46)이 둥근 아랫선에 어깨를 부딪칠 수는 있지만, 그 자리는 사각형 아랫면(bottom.y)보다 분명히 위여야 한다
			var shape_ok: bool = (not ceiling._broken) or (etop - 67.0 < bottom.y - 15.0)
			print("[비밀시험] 옹이 왼쪽 끝 %.0fpx 안에서 점프: 머리 최고 y=%.0f (사각형이었다면 %.0f 에 박힘), 부서짐 %s → 충돌이 그림을 따름 %s" % [edge_dx, etop - 67.0, bottom.y, ceiling._broken, shape_ok])
			if ceiling._broken:
				break
		player.global_position = Vector2(bottom.x, floor_y - 67.0)
		player.velocity = Vector2.ZERO
		await tree.create_timer(0.4).timeout
		print("[비밀시험] 천장 %s (%s 크기 %s): 아랫면 y=%.0f, 바닥 y=%.0f (머리 공간 %.0f ≥ 144), 소녀 바닥 %s, 아이템 보임 %s, 자리 %s" % [ceiling.secret_id, ceiling.global_position, ceiling.size, bottom.y, floor_y, floor_y - bottom.y, player.is_on_floor(), pickup.visible, pickup.global_position])
		Input.action_press("jump")
		var top := player.global_position.y
		var t := 0.0
		var bumped_at := -1.0
		while t < 2.0:
			await tree.physics_frame
			t += get_physics_process_delta_time()
			top = minf(top, player.global_position.y)
			if ceiling._broken and bumped_at < 0.0:
				bumped_at = t
			if t >= 0.4 and Input.is_action_pressed("jump"):
				Input.action_release("jump")
		print("[비밀시험] 점프 최고점 y=%.0f (머리 %.0f, 천장 아랫면 %.0f), 천장 부서짐 %s (%.2f초), 충돌 레이어 %d" % [top, top - 67.0, bottom.y, ceiling._broken, bumped_at, ceiling.collision_layer])
		print("[비밀시험] 아이템 보임 %s, 자리 %s (바닥 자리 %s), 감지 %s, 이미 모음 %s" % [pickup.visible, pickup.global_position.round(), pickup.fall_to, pickup.monitoring, pickup.collected])
	# 아이템에 닿는다
	if not pickup.collected:
		var at := pickup.fall_to if pickup.fall_to != Vector2.ZERO else pickup.global_position
		player.global_position = at + Vector2(0, -30)
		player.velocity = Vector2.ZERO
		await tree.create_timer(0.6).timeout
	print("[비밀시험] 아이템 모음(%s %.2f): %s, 최대 체력 %.0f → %.0f, 최대 이슬 %d → %d (지금 %d), 공격 배수 %.2f → %.2f, 회복량 %.0f → %.0f, 안내 '%s'" % [pickup.kind, pickup.amount, Progress.collected, hp0, player.max_hp, dews0, player.max_dews, player.dews, atk0, player.attack_multiplier, heal0, player.heal_amount, get_node("CombatHUD")._message])
	refresh_explore()
	entry = Progress.visited_rooms.get(room_id, {})
	print("[비밀시험] 모은 뒤 탐사 %d / %d" % [entry.get("explore_found", -1), entry.get("explore_total", -1)])
	# 세이브 → 초기화 → 불러오기
	SaveGame.save("", scene_file_path)
	Progress.reset()
	print("[비밀시험] 초기화 뒤 collected %s, 방 기록 %d개" % [Progress.collected, Progress.visited_rooms.size()])
	SaveGame.load_game()
	entry = Progress.visited_rooms.get(room_id, {})
	print("[비밀시험] 불러온 뒤 collected %s, 성장 %s, 탐사 %d / %d" % [Progress.collected, Progress.upgrades, entry.get("explore_found", -1), entry.get("explore_total", -1)])
	# 같은 방에 다시 들어가 본다 (부서진 채로 남아 있는지)
	Progress.set_flag("_test_reentered")
	Progress.next_spawn = ""
	Game.go_to(scene_file_path, 0.2, 0.2)
	await tree.create_timer(6.0).timeout
	print("[비밀시험] 6초가 지나도 방이 다시 열리지 않았다")
	SaveGame.new_game()
	DirAccess.remove_absolute(SaveGame.PATH)   # 시험이 남긴 새 칸 파일을 치운다 (v1.1.0: new_game 이 곧바로 저장한다 — 뒤 시험이 '저장 없음'에서 시작하게)
	tree.quit()


## 시험 2단계: 건너온 방에서 제대로 도착했는지 확인하고 끝낸다.
func _arrivaltest(label: String, _spawn: String) -> void:
	var tree := get_tree()
	await tree.create_timer(0.8).timeout
	var near := "?"
	var group := "portal" if label == "포탈" else "moonlight_grass"
	if group == "portal":
		# 등장 자리(Markers/<이름>) 옆에 포탈이 있어야 되돌아갈 수 있다
		var best := INF
		for n in tree.get_nodes_in_group("portal"):
			best = minf(best, player.global_position.distance_to(n.global_position))
		near = "%.0f px (가장 가까운 포탈)" % best
	else:
		for n in tree.get_nodes_in_group(group):
			for f in Progress.flags:
				if str(f).begins_with("_test_target_") and str(f).trim_prefix("_test_target_") == n.grass_id:
					near = "%.0f px" % player.global_position.distance_to(n.global_position)
	print("[%s시험·도착] 방 %s, 소녀 상태 %s, 입력 가능 %s, 바닥 %s, 목표까지 %s, 등장 자리 비움 %s, 멈춤 %s" % [label, scene_file_path.get_file(), player.state_name(), player.input_enabled, player.is_on_floor(), near, Progress.next_spawn == "", tree.paused])
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

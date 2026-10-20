extends Node
## 터치 버튼 그림·빛 가루 칸 눈 확인용 스크린샷 (창으로 돌린다 — 화면 없이 돌면 그림이 안 찍힌다):
##   godot --path . res://tools/shot_touch_ui.tscn
## 밝은 방(수관 시작의 가지, 정화된 색)과 어두운 방(채굴장 책임자의 방, 어둠)을 1920×1080 과 아이패드 4:3(2048×1536 → 캔버스 1920×1440)
## 크기의 SubViewport 에 띄워, 터치 장치·바람 영혼(어두운 1080 은 빛 영혼 = 빛줄기 그림) 쿨다운 중·상황 버튼(손길 / 들어가기 / 쉬는 중 이동·성장)·공격 버튼 누름·빛 가루 +N 상태로 찍는다.
## 결과: screenshots/touch_<방>_<크기>.png

const CASES := [
	{"room": "canopy_01", "size": Vector2i(1920, 1080), "tag": "bright_1080", "alive": true, "spot": "grass"},
	{"room": "mine_deep", "size": Vector2i(1920, 1080), "tag": "dark_1080", "alive": false, "spot": "portal", "soul": "light"},
	{"room": "canopy_01", "size": Vector2i(1920, 1440), "tag": "bright_ipad", "alive": true, "spot": "rest"},
	{"room": "mine_deep", "size": Vector2i(1920, 1440), "tag": "dark_ipad", "alive": false, "spot": "portal"},
]


func _ready() -> void:
	for c in CASES:
		await _shot(c)
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(c: Dictionary) -> void:
	Progress.reset()
	Progress.gain_ability("wind")
	Progress.gain_ability("double_jump")
	var soul: String = c.get("soul", "wind")
	if soul != "wind":
		Progress.gain_ability(soul)
	Progress.soul = soul
	Progress.add_upgrade("dews", 1)
	if c["alive"]:
		Purity.regions["canopy"] = true
	var vp := SubViewport.new()
	vp.size = c["size"]
	vp.use_hdr_2d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	InputDevice._set_device(InputDevice.Kind.TOUCH, -1)
	var room: Node = load("res://scenes/rooms/%s.tscn" % c["room"]).instantiate()
	vp.add_child(room)
	await _frames(20)
	var player := get_tree().get_first_node_in_group("player") as Player
	var touch: Node = room.get_node_or_null("TouchControls")
	player._invuln_timer = 9999.0
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	match c["spot"]:
		"grass", "rest":
			var g: Node2D = get_tree().get_first_node_in_group("moonlight_grass")
			player.global_position = g.global_position + Vector2(70, -70)
		"portal":
			var p: Node2D = get_tree().get_first_node_in_group("portal")
			player.global_position = p.global_position + Vector2(-30, -70)
	player.velocity = Vector2.ZERO
	await _frames(30)
	if c["spot"] == "rest":
		var g: Node2D = get_tree().get_first_node_in_group("moonlight_grass")
		player.start_rest(g)
		await _frames(10)
	player._soul_cooldowns[soul] = 2.9
	Progress.add_dust(1234)
	await _frames(12)
	# 공격 버튼을 누르고 있는 모습 (가짜 손가락)
	if touch:
		touch._touches[99] = {"role": "attack_light", "origin": Vector2.ZERO, "pos": Vector2.ZERO}
		touch._dirty = true   # 터치 버튼은 상태가 바뀔 때만 다시 그린다
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	var path := "res://screenshots/touch_%s.png" % c["tag"]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[터치 스크린샷] %s (%s, 상황 버튼 %s, 영혼 %s 쿨 %.1f, 빛 가루 %d)" % [path, c["size"], touch.button_icon("interact") if touch and player.can_interact else "-", player.soul, player.soul_cooldown_left(), Progress.dust])
	if touch:
		touch._touches.erase(99)
	room.queue_free()
	await _frames(2)
	vp.queue_free()
	await _frames(2)
	Purity.regions["canopy"] = false

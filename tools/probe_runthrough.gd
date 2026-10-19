extends Node
## 길목 시험: 방을 띄워 소녀가 적을 그대로 둔 채 오른쪽(또는 왼쪽) 달리기만 눌러 지나갈 때 몇 번 맞는지 센다.
## (2026-10-19 기획자 요청 6번 — 몸통 부딪힘 피해가 있으면 그냥 뚫고 지나가기 어렵다.) 끝줄 "[probe] 끝: 실패 N".
## 실행: godot --headless --path . res://tools/probe_runthrough.tscn

const CASES := [
	# [방, 등장 자리, 방향, 달릴 시간(초)]
	["canopy_03", "FromCanopy02", 1, 9.0],
	["canopy_06", "", 1, 9.0],
	["village_01", "", 1, 8.0],
	["village_02", "", 1, 8.0],
	["mine_02", "", 1, 9.0],
	["abyss_01", "", 1, 8.0],
]

var _fail := 0


func _ready() -> void:
	var total_hits := 0
	for c in CASES:
		var hits: int = await _run(c[0], c[1], c[2], c[3])
		total_hits += hits
	print("[probe] 적에게 맞은 횟수(가시 제외) %d (방 %d곳)" % [total_hits, CASES.size()])
	if total_hits < CASES.size():
		print("[probe] FAIL 달려 지나가도 거의 안 맞는다 (방마다 평균 1번 이상이어야 길목 의미가 있다)")
		_fail += 1
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(_fail)


func _run(room_id: String, spawn: String, dir: int, secs: float) -> int:
	Progress.reset()
	Progress.next_spawn = spawn
	var room: Node = load("res://scenes/rooms/%s.tscn" % room_id).instantiate()
	add_child(room)
	for i in 6:
		await get_tree().physics_frame
	var player := get_tree().get_first_node_in_group("player") as Player
	var hits := [0]
	var contact := [0]
	var hazard := [0]
	# 가시(take_hazard)는 따로 센다: 가시는 맞은 뒤 입력을 잠깐 잠그므로 한 틱 뒤에 입력이 잠겨 있으면 가시다.
	# (2026-10-19 검수: 가시 구덩이에 거듭 빠진 것까지 세어 '길목' 통과가 부풀려졌다)
	player.hit_taken.connect(func(d):
		hits[0] += 1
		(func() -> void:
			if not player.input_enabled:
				hazard[0] += 1
			elif is_equal_approx(d, 8.0) or d < 12.5:
				contact[0] += 1).call_deferred())
	var x0 := player.global_position.x
	var a := "move_right" if dir > 0 else "move_left"
	Input.action_press(a)
	var t := 0.0
	while t < secs and player.state != Player.State.DEAD:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		# 점프로 턱을 넘는다 (막혀 있으면)
		if player.is_on_floor() and player.is_on_wall() and not Input.is_action_pressed("jump"):
			Input.action_press("jump")
		elif Input.is_action_pressed("jump") and not player.is_on_wall():
			Input.action_release("jump")
	Input.action_release(a)
	Input.action_release("jump")
	await get_tree().process_frame
	print("[probe] %s: %.1f초 동안 %d px 달림, 맞은 횟수 %d (가시 %d, 적 %d — 그중 몸통 부딪힘으로 보이는 것 %d), 체력 %.0f" % [room_id, t, int(absf(player.global_position.x - x0)), hits[0], hazard[0], hits[0] - hazard[0], contact[0], player.hp])
	room.queue_free()
	for i in 3:
		await get_tree().process_frame
	return hits[0] - hazard[0]

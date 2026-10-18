extends Node2D
## 3단계 연습장. 소녀의 이동·점프·구르기 손맛을 재 보는 방.
## 메뉴 버튼(Esc / P / 옵션)을 누르면 입력 확인 화면으로 간다.

const INPUT_TEST_SCENE := "res://scenes/debug/input_test.tscn"

@onready var player: Player = $Player
@onready var measure_label: Label = $DebugHUD/Measure
@onready var start_position: Vector2 = player.position

## 자동 시험 기록
var _max_height := 0.0
var _jump_start_y := 0.0
var _measuring := false


func _ready() -> void:
	Music.stop(0.5)
	player.get_node("Camera2D").set_room_bounds(Rect2(-700, -600, 5400, 1850))
	player.jumped.connect(func(_air: bool) -> void:
		_jump_start_y = player.position.y
		_max_height = 0.0
		_measuring = true)
	var args := OS.get_cmdline_user_args()
	if "--screenshot" in args:
		await get_tree().create_timer(1.0).timeout
		_save_screenshot("debug_playground.png")
		get_tree().quit()
	elif "--autotest" in args:
		_autotest()
	elif "--rigtest" in args:
		_rigtest()


func _process(_delta: float) -> void:
	if _measuring:
		_max_height = maxf(_max_height, _jump_start_y - player.position.y)
		if player.is_on_floor():
			_measuring = false
	if player.position.y > 2200.0:
		player.position = start_position
		player.velocity = Vector2.ZERO
	measure_label.text = "마지막 점프 높이 %d px" % _max_height


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().change_scene_to_file(INPUT_TEST_SCENE)


func _save_screenshot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return   # 화면 없는 시험에서는 찍지 않는다
	var tex := get_viewport().get_texture()
	var img := tex.get_image() if tex else null
	if img == null or img.is_empty():
		return
	img.save_png(ProjectSettings.globalize_path("res://screenshots/" + file_name))


## Claude Code가 손맛 숫자를 확인할 때 쓰는 자동 시험. 결과를 콘솔에 찍는다.
func _autotest() -> void:
	player.input_enabled = false
	await get_tree().create_timer(0.5).timeout
	var tree := get_tree()

	# 1) 제자리 점프 높이
	var y0 := player.position.y
	player.velocity.y = -player.jump_velocity()
	player._set_state(Player.State.JUMP)
	var peak := 0.0
	var t := 0.0
	while t < 1.5:
		await tree.physics_frame
		t += get_physics_process_delta_time()
		peak = maxf(peak, y0 - player.position.y)
		if t > 0.2 and player.is_on_floor():
			break
	print("[자동시험] 제자리 점프: 최고 높이 %.0f px (설정 %.0f), 공중 시간 %.2f초" % [peak, player.jump_height, t])

	# 2) 걷다가 점프한 거리 / 달리며 점프한 거리
	for running in [false, true]:
		player.position = start_position
		player.velocity = Vector2.ZERO
		await tree.physics_frame
		var speed := player.run_speed if running else player.walk_speed
		player.velocity.x = speed
		var x0 := player.position.x
		player.velocity.y = -player.jump_velocity()
		player._set_state(Player.State.JUMP)
		t = 0.0
		while t < 2.0:
			await tree.physics_frame
			t += get_physics_process_delta_time()
			player.velocity.x = speed
			if t > 0.2 and player.is_on_floor():
				break
		print("[자동시험] %s 점프 거리: %.0f px" % ["달리기" if running else "걷기", player.position.x - x0])
		await tree.create_timer(0.3).timeout
		_save_screenshot("debug_autotest_%s.png" % ("run" if running else "walk"))

	# 3) 구르기 거리
	player.position = start_position
	player.velocity = Vector2.ZERO
	await tree.physics_frame
	var rx0 := player.position.x
	player.facing = 1
	player._roll_timer = player.roll_duration
	player._set_state(Player.State.ROLL)
	t = 0.0
	while player.state == Player.State.ROLL and t < 1.0:
		await tree.physics_frame
		t += get_physics_process_delta_time()
		if t > 0.1 and t < 0.16:
			_save_screenshot("debug_autotest_roll.png")
	print("[자동시험] 구르기 거리: %.0f px (%.2f초)" % [player.position.x - rx0, t])
	await tree.create_timer(0.3).timeout
	_save_screenshot("debug_autotest_end.png")
	tree.quit()


## 뼈대 확인: 카메라를 당겨 자세별로 찍는다.
func _rigtest() -> void:
	var tree := get_tree()
	player.input_enabled = false
	var cam: Camera2D = player.get_node("Camera2D")
	cam.zoom = Vector2(4.5, 4.5)
	cam.vertical_offset = -30.0
	cam.position_smoothing_enabled = false
	$DebugHUD.visible = false
	$CombatHUD.visible = false
	$TouchControls.visible = false
	await tree.create_timer(0.6).timeout
	var shots := {
		"idle": Player.State.IDLE, "walk": Player.State.WALK, "run": Player.State.RUN, "jump": Player.State.JUMP,
		"guard": Player.State.GUARD, "attack2": Player.State.ATTACK, "attack3": Player.State.ATTACK,
		"heavy": Player.State.HEAVY_CHARGE, "hit": Player.State.HIT, "rest": Player.State.REST, "purify": Player.State.PURIFY,
	}
	for name in shots:
		player.state = shots[name]
		if name == "attack2":
			player.attack_step = 2; player.attack_phase = "active"
		elif name == "attack3":
			player.attack_step = 3; player.attack_phase = "active"
		if name in ["walk", "run"]:
			player.velocity.x = player.run_speed if name == "run" else player.walk_speed
		else:
			player.velocity.x = 0.0
		if name == "heavy":
			player.charge = player.heavy_max_charge
		await tree.create_timer(0.7).timeout
		_save_screenshot("rig_%s.png" % name)
		player.attack_step = 0
		player.attack_phase = ""
	tree.quit()

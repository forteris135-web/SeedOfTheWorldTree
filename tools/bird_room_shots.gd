extends Node
## '잿빛 잎새의 새'를 **실제 보스 방(canopy_boss)** 에서 상태별로 찍는다 (확인용 — 창으로 띄워야 찍힌다).
##   Godot --path . --resolution 1600x900 res://tools/bird_room_shots.tscn
## 결과: screenshots/bird_room_<장면>.png (싸움 카메라·레터박스 띠·HUD 그대로). 소녀는 무적으로 새 옆 바닥에 세워 둔다 (크기 비교용).
## 방 스크립트는 고치지 않는다: 이 노드를 루트에 남겨 두고 방으로 장면을 바꾼 뒤, 방의 보스·소녀를 직접 움직인다.

const ROOM := "res://scenes/rooms/canopy_boss.tscn"

var _room: Node
var _boss: GrayLeafBird
var _player: Player


func _ready() -> void:
	# 장면이 바뀌어도 살아남게 루트의 자식으로 옮긴다
	var root := get_tree().root
	get_parent().remove_child.call_deferred(self)
	root.add_child.call_deferred(self)
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	get_tree().change_scene_to_file(ROOM)
	for i in 30:
		await get_tree().process_frame
	_room = get_tree().current_scene
	_boss = _room.get_node("Boss") as GrayLeafBird
	_player = _room.player
	if _boss == null or _player == null:
		push_error("보스 방을 읽지 못했다")
		get_tree().quit(1)
		return
	_player._invuln_timer = 99999.0
	# 싸움 시작: 문 안쪽으로
	var gl: float = _room.get_node("Markers/GroundLine").position.y
	_player.global_position = Vector2(1500, gl - 4.0)
	await _wait(3.4)   # 등장(INTRO 2.2초) → HOVER
	_hold_player(-1)
	await _shot("hover")
	# 깃털 던지기: 예고(날개 당김) → 던짐
	_boss._pattern_index = 1
	_boss._next_pattern()
	await _wait(0.42)
	await _shot("feathers_cock")
	await _wait(0.33)
	await _shot("feathers_throw")
	await _wait(1.2)
	# 날갯바람: 붉은 예고 → 거대한 날갯짓
	_boss._pattern_index = 2
	_boss._next_pattern()
	await _wait(0.55)
	await _shot("wind_red")
	await _wait(0.8)
	await _shot("wind_gust")
	await _wait(1.4)
	# 잎 흩날리기
	_boss._pattern_index = 0
	_boss._next_pattern()
	await _wait(1.4)
	await _shot("leafrain")
	await _wait(2.4)
	# 내려앉기 → 땅
	_boss._fatigue = 99
	await _wait_state("DESCEND", 3.0)
	await _wait(0.9)
	await _shot("descend")
	await _wait_state("GROUND_IDLE", 3.0)
	await _wait(0.15)
	await _shot("landed")
	await _wait_state("EAT", 3.0)
	await _wait(0.8)
	await _shot("eat")
	# 날개 휘두르기
	await _melee(GrayLeafBird.State.SWEEP, "sweep")
	await _melee(GrayLeafBird.State.PECK, "peck")
	# 무너짐
	_boss.poise = _boss.max_poise - 1.0
	_boss.receive_hit(HitData.make(1.0, 10.0, _player), null)
	await _wait(1.2)
	await _shot("broken")
	# 쓰러짐 → 누워 기다림 → 정화
	_boss.hp = 1.0
	_boss.receive_hit(HitData.make(5.0, 0.0, _player), null)
	await _wait(0.25)
	await _shot("fallen_air")
	await _wait(1.6)
	_hold_player(-1, 230.0)
	await _shot("fallen")
	_boss.purified_by(_player)   # 방이 정화 연출(하얗게 흐려짐·띠 내려감)을 이어 한다 — 회상으로 넘어가기(1.8초) 전에 찍는다
	await _wait(0.7)
	await _shot("purified")
	get_tree().quit()


## 소녀를 새 옆 바닥에 세운다 (side: 새의 어느 쪽, 새를 바라보게)
func _hold_player(side: int, dist := 420.0) -> void:
	var gl: float = _room.get_node("Markers/GroundLine").position.y
	_player.global_position = Vector2(_boss.global_position.x + side * dist, gl - 4.0)
	_player.velocity = Vector2.ZERO
	_player.facing = -side
	_player.input_enabled = false


func _melee(st: int, name: String) -> void:
	_hold_player(-1, 330.0)
	_boss.facing = -1
	_boss._set_state(st)
	_boss._timer = _boss.sweep_windup if st == GrayLeafBird.State.SWEEP else _boss.peck_windup
	_boss._melee_stage = 0
	_boss.attack_phase = "startup"
	_boss.windup_progress = 0.0
	_boss.startup_len = _boss._timer
	_boss._ground_actions = 0
	await _wait(_boss.startup_len * 0.85)
	await _shot(name + "_windup")
	await _wait(_boss.startup_len * 0.15 + 0.1)
	await _shot(name + "_strike")
	await _wait(0.5)
	await _shot(name + "_recover")
	await _wait(0.6)


func _wait(t: float) -> void:
	var e := 0.0
	while e < t:
		await get_tree().physics_frame
		e += 1.0 / 60.0
		if is_instance_valid(_player) and not _player.input_enabled:
			_player.velocity = Vector2.ZERO


func _wait_state(sname: String, limit: float) -> void:
	var e := 0.0
	while e < limit and _boss.state_name() != sname:
		await get_tree().physics_frame
		e += 1.0 / 60.0


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var hdr := img.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]
	img.convert(Image.FORMAT_RGBA8)
	if hdr:
		img.linear_to_srgb()
	var d := ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(d)
	var path := "%s/bird_room_%s.png" % [d, name]
	img.save_png(path)
	print("[bird_room_shots] %s  (새 %s %s, 소녀 %s)" % [path, _boss.state_name(), _boss.attack_phase, _player.global_position])

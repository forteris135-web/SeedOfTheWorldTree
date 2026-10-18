extends CanvasLayer
## 개발용 표시. 소녀의 상태, 장치, FPS, 손맛 숫자.

@onready var info: Label = $Info
var _player: Player


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player == null:
			info.text = ""
			return
	info.text = "상태: %s   속도: (%d, %d)   %s\n장치: %s   FPS %d\n점프 높이 %d / 최고점 %.2f초 / 걷기 %d / 달리기 %d" % [
		_player.state_name(), _player.velocity.x, _player.velocity.y,
		("달리기 고정 ●" if _player.run_locked else ("달리는 중" if _player.is_running else "")),
		InputDevice.kind_name(InputDevice.current), Engine.get_frames_per_second(),
		_player.jump_height, _player.jump_time_to_apex, _player.walk_speed, _player.run_speed]

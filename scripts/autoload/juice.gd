extends Node
## 손맛 연출 도우미: 히트스톱, 화면 흔들림, 컨트롤러 진동.

var _stopping := false


## 아주 짧게 시간을 멈춘다. duration 은 실제 시간(초).
func hitstop(duration := 0.06, scale := 0.05) -> void:
	if _stopping:
		return
	_stopping = true
	Engine.time_scale = scale
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_stopping = false


func rumble(weak := 0.3, strong := 0.6, duration := 0.12) -> void:
	var id := InputDevice.rumble_target()
	if id >= 0:
		Input.start_joy_vibration(id, weak, strong, duration)


func shake(amount := 6.0) -> void:
	if not Settings.get_value("screen_shake"):
		return
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(amount)

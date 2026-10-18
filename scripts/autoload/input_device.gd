extends Node
## 마지막으로 입력이 들어온 장치를 기억한다.
## 나중에 화면의 버튼 안내("△ 정화" 등)를 듀얼센스 / 엑스박스 / 키보드 / 터치 표시로
## 자동 전환하는 데 쓴다. (GAME_DESIGN.md 8장 "버튼 안내 아이콘 자동 전환")

enum Kind { NONE, KEYBOARD, DUALSENSE, XBOX, OTHER_PAD, TOUCH }

## 장치가 바뀌었을 때 알린다.
signal device_changed(kind: Kind)
## 컨트롤러가 연결되거나 끊겼을 때 알린다.
signal joypads_changed

## 지금 쓰고 있는 장치.
var current: Kind = Kind.NONE
## 마지막으로 입력이 들어온 컨트롤러 번호. 컨트롤러가 아니면 -1.
var current_joy_id: int = -1

## 스틱을 살짝 건드린 것은 장치 전환으로 치지 않는다.
const STICK_THRESHOLD := 0.3


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# 이미 연결된 컨트롤러가 있으면 그것을 기본 장치로 삼는다.
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		_set_device(joy_kind(pads[0]), pads[0])


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		_set_device(Kind.KEYBOARD, -1)
	elif event is InputEventJoypadButton:
		_set_device(joy_kind(event.device), event.device)
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > STICK_THRESHOLD:
			_set_device(joy_kind(event.device), event.device)
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		_set_device(Kind.TOUCH, -1)


func _set_device(kind: Kind, joy_id: int) -> void:
	if kind == current and joy_id == current_joy_id:
		return
	current = kind
	current_joy_id = joy_id
	device_changed.emit(kind)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected and device == current_joy_id:
		current_joy_id = -1
		var pads := Input.get_connected_joypads()
		if pads.is_empty():
			_set_device(Kind.KEYBOARD, -1)
		else:
			_set_device(joy_kind(pads[0]), pads[0])
	joypads_changed.emit()


## 컨트롤러 이름으로 종류를 알아낸다.
func joy_kind(device: int) -> Kind:
	var joy_name := Input.get_joy_name(device).to_lower()
	for word in ["dualsense", "dualshock", "ps5", "ps4", "playstation", "sony", "wireless controller"]:
		if word in joy_name:
			return Kind.DUALSENSE
	for word in ["xbox", "x-box", "xinput", "microsoft"]:
		if word in joy_name:
			return Kind.XBOX
	return Kind.OTHER_PAD


## 화면에 보여 줄 장치 이름.
func kind_name(kind: Kind) -> String:
	match kind:
		Kind.KEYBOARD:
			return "키보드"
		Kind.DUALSENSE:
			return "듀얼센스"
		Kind.XBOX:
			return "엑스박스 컨트롤러"
		Kind.OTHER_PAD:
			return "컨트롤러"
		Kind.TOUCH:
			return "터치"
		_:
			return "아직 입력 없음"


## 지금 장치가 컨트롤러인가.
func is_using_joypad() -> bool:
	return current in [Kind.DUALSENSE, Kind.XBOX, Kind.OTHER_PAD]


## 진동을 쓸 컨트롤러 번호. 없으면 -1.
func rumble_target() -> int:
	if current_joy_id >= 0:
		return current_joy_id
	var pads := Input.get_connected_joypads()
	return pads[0] if not pads.is_empty() else -1


## 화면 안내용 버튼 이름. 바뀐 배치를 따라간다. 예: prompt("interact") → "E" / "△" / "Y"
func prompt(action: String) -> String:
	match current:
		Kind.DUALSENSE:
			return _first(Keymap.label_for(action, "ds"))
		Kind.XBOX, Kind.OTHER_PAD:
			return _first(Keymap.label_for(action, "xb"))
		Kind.TOUCH:
			return {"interact": "손길 버튼", "guard": "가드", "heal": "회복", "soul_ability": "영혼", "soul_next": "전환 버튼", "jump": "점프", "map": "지도", "pause": "메뉴"}.get(action, action)
		_:
			return _first(Keymap.label_for(action, "kb"))


func _first(label: String) -> String:
	return label.split(",")[0].strip_edges()

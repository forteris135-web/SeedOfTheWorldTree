extends Node
## 키·버튼 바꾸기. 바뀐 배치는 설정 파일(user://keymap.json)에 저장하고 시작할 때 되돌린다.
## 이벤트 표기: "key:<물리 키코드>", "btn:<버튼 번호>", "axis:<축>:<+|->"

const PATH := "user://keymap.json"
## 저장 파일의 배치 판. 기본 배치가 크게 바뀌면 올린다. 옛 판 파일은 _load 가 맞춰 읽고 새 판으로 다시 저장한다.
## 2: 강공격 삭제, 그 입력(K, R2/RT)이 영혼 기술로 (2026-10-18) — 옛 파일의 강공격 배치는 영혼 기술에 합친다
const VERSION := 2
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "dodge", "attack_light", "guard", "soul_ability", "heal", "interact", "soul_prev", "soul_next", "map", "pause", "run_toggle"]
const NAMES := {
	"move_left": "이동 ←", "move_right": "이동 →", "move_up": "위", "move_down": "아래", "jump": "점프", "dodge": "회피 / 달리기",
	"attack_light": "약공격 (공중 ↓ = 낙하 공격)", "guard": "가드 / 저스트 가드", "soul_ability": "영혼 기술", "heal": "회복 (이슬 방울)",
	"interact": "상호작용 / 정화의 손길", "soul_prev": "영혼 전환 ←", "soul_next": "영혼 전환 →", "map": "지도", "pause": "메뉴", "run_toggle": "걷기 고정",
}
## 듀얼센스 / 엑스박스 버튼 이름
const PAD_NAMES := {
	0: ["×", "A"], 1: ["○", "B"], 2: ["□", "X"], 3: ["△", "Y"], 4: ["만들기", "보기"], 6: ["옵션", "메뉴"], 7: ["L3", "LS"], 8: ["R3", "RS"],
	9: ["L1", "LB"], 10: ["R1", "RB"], 11: ["십자 ↑", "십자 ↑"], 12: ["십자 ↓", "십자 ↓"], 13: ["십자 ←", "십자 ←"], 14: ["십자 →", "십자 →"],
}
const AXIS_NAMES := {"0-": "L스틱 ←", "0+": "L스틱 →", "1-": "L스틱 ↑", "1+": "L스틱 ↓", "2-": "R스틱 ←", "2+": "R스틱 →", "3-": "R스틱 ↑", "3+": "R스틱 ↓", "4+": ["L2", "LT"], "5+": ["R2", "RT"]}

signal changed

var _defaults := {}   # action -> Array[InputEvent] (project.godot 의 원래 배치)


func _ready() -> void:
	for a in ACTIONS:
		_defaults[a] = InputMap.action_get_events(a).duplicate()
	_load()


## 한 동작의 한 장치 종류(키보드 / 컨트롤러) 배치를 새 이벤트로 바꾼다.
func rebind(action: String, event: InputEvent) -> void:
	var is_key := event is InputEventKey
	var kept: Array = []
	for e in InputMap.action_get_events(action):
		var e_key := e is InputEventKey
		if e_key != is_key:
			kept.append(e)   # 다른 장치 종류는 그대로
	InputMap.action_erase_events(action)
	for e in kept:
		InputMap.action_add_event(action, e)
	var ne := _normalize(event)
	# 같은 장치에서 다른 동작에 쓰이던 같은 입력은 떼어 낸다 (이동·메뉴는 예외)
	for other in ACTIONS:
		if other == action or other in ["pause"]:
			continue
		for e in InputMap.action_get_events(other):
			if _same(e, ne):
				InputMap.action_erase_event(other, e)
	InputMap.action_add_event(action, ne)
	_save()
	changed.emit()


func reset_defaults() -> void:
	for a in ACTIONS:
		InputMap.action_erase_events(a)
		for e in _defaults[a]:
			InputMap.action_add_event(a, e)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	changed.emit()


## 안내용 글자. kind: "kb" / "ds" / "xb"
func label_for(action: String, kind: String) -> String:
	var parts: Array[String] = []
	for e in InputMap.action_get_events(action):
		if kind == "kb" and e is InputEventKey:
			parts.append(OS.get_keycode_string(e.physical_keycode if e.physical_keycode != 0 else e.keycode))
		elif kind != "kb" and e is InputEventJoypadButton:
			var n = PAD_NAMES.get(e.button_index, ["버튼 %d" % e.button_index, "버튼 %d" % e.button_index])
			parts.append(n[0] if kind == "ds" else n[1])
		elif kind != "kb" and e is InputEventJoypadMotion:
			var k := "%d%s" % [e.axis, "+" if e.axis_value > 0 else "-"]
			var n = AXIS_NAMES.get(k, "축 %s" % k)
			parts.append((n[0] if kind == "ds" else n[1]) if n is Array else n)
	return ", ".join(parts) if not parts.is_empty() else "-"


func _normalize(event: InputEvent) -> InputEvent:
	if event is InputEventKey:
		var k := InputEventKey.new()
		k.physical_keycode = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return k
	if event is InputEventJoypadButton:
		var b := InputEventJoypadButton.new()
		b.button_index = event.button_index
		return b
	if event is InputEventJoypadMotion:
		var m := InputEventJoypadMotion.new()
		m.axis = event.axis
		m.axis_value = 1.0 if event.axis_value > 0 else -1.0
		return m
	return event


func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return (a.physical_keycode if a.physical_keycode != 0 else a.keycode) == b.physical_keycode
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return a.axis == b.axis and signf(a.axis_value) == signf(b.axis_value)
	return false


func _encode(e: InputEvent) -> String:
	if e is InputEventKey:
		return "key:%d" % (e.physical_keycode if e.physical_keycode != 0 else e.keycode)
	if e is InputEventJoypadButton:
		return "btn:%d" % e.button_index
	if e is InputEventJoypadMotion:
		return "axis:%d:%s" % [e.axis, "+" if e.axis_value > 0 else "-"]
	return ""


func _decode(s: String) -> InputEvent:
	var p := s.split(":")
	match p[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(p[1]) as Key
			return k
		"btn":
			var b := InputEventJoypadButton.new()
			b.button_index = int(p[1]) as JoyButton
			return b
		"axis":
			var m := InputEventJoypadMotion.new()
			m.axis = int(p[1]) as JoyAxis
			m.axis_value = 1.0 if p[2] == "+" else -1.0
			return m
	return null


func _save() -> void:
	var data := {"_version": VERSION}
	for a in ACTIONS:
		var arr := []
		for e in InputMap.action_get_events(a):
			var s := _encode(e)
			if s != "":
				arr.append(s)
		data[a] = arr
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()


func _load() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	var old_version := int(data.get("_version", 1)) < VERSION
	if old_version and data.has("attack_heavy"):
		# 판 1 (강공격이 있던 때): 강공격에 쓰던 입력을 영혼 기술에 합치고, 나머지 배치(점프·회피 등)는 그대로 살린다
		var merged: Array = (data.get("soul_ability", []) as Array).duplicate()
		for s in data["attack_heavy"]:
			if not merged.has(s):
				merged.append(s)
		data["soul_ability"] = merged
	for a in ACTIONS:
		if not data.has(a):
			continue
		InputMap.action_erase_events(a)
		for s in data[a]:
			var e := _decode(str(s))
			if e:
				InputMap.action_add_event(a, e)
	if old_version:
		_save()   # 새 판으로 다시 저장 (없는 동작 attack_heavy 는 빠진다)
	changed.emit()

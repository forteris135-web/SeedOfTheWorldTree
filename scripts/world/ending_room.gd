extends Room
class_name EndingRoom
## 심연 · 두 갈래 길 (v1.1.0 기획자 요청 28): 뿌리지기 방(정원의 끝) 오른쪽 문 너머의 작은 방.
## 일반 엔딩 장치 둘(희생 '심연의 뿌리' · 되돌림 '마력의 관')이 이 방으로 옮겨 왔다. 뿌리지기 방에는 진엔딩 장치만 남는다.
## 장치(Choices)는 뿌리지기를 정화하고 회상에서 돌아온 뒤(깃발 after_boss_root_defeated)에만 깨어난다.
## (그 전에는 이 방에 올 수도 없다 — 뿌리지기 방의 오른쪽 문은 정화해야 열린다.) 적·달빛풀이 없어 지도 탐사는 0/0.

## 장치를 깨우는 깃발 (BossRoom 이 회상 뒤에 세운다)
const AWAKE_FLAG := "after_boss_root_defeated"


func _ready() -> void:
	super._ready()
	_apply_choices()
	Progress.flag_changed.connect(_on_flag_for_choices)


func _apply_choices() -> void:
	var choices := get_node_or_null("Choices")
	if choices == null:
		return
	var awake := Progress.has(AWAKE_FLAG)
	choices.visible = awake
	for c in choices.get_children():
		c.process_mode = Node.PROCESS_MODE_INHERIT if awake else Node.PROCESS_MODE_DISABLED


func _on_flag_for_choices(flag: String, _value: bool) -> void:
	if flag == AWAKE_FLAG:
		_apply_choices()

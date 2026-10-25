extends Node
## 장면 전환 (검은 화면으로 부드럽게 바꾸기).

const TITLE_SCENE := "res://scenes/ui/title_screen.tscn"
const FIRST_ROOM := "res://scenes/rooms/canopy_01.tscn"
const MEMORY_SCENE := "res://scenes/ui/memory_scene.tscn"

var _layer: CanvasLayer
var _black: ColorRect
var _busy := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_black.modulate.a = 0.0
	_layer.add_child(_black)


## 검게 어두워졌다가 새 장면에서 밝아진다.
func go_to(scene_path: String, fade_out := 0.6, fade_in := 0.9) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_black, "modulate:a", 1.0, fade_out)
	await tw.finished
	_capture_vitals()
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	tw = create_tween()
	tw.tween_property(_black, "modulate:a", 0.0, fade_in)
	await tw.finished
	_busy = false


## 장면 전환 중인가 (검은 화면으로 바뀌는 중에는 go_to 가 아무것도 하지 않는다)
func is_busy() -> bool:
	return _busy


## 방을 옮겨도 체력·이슬은 그대로 이어진다 (v1.1.0 기획자 요청 13 — 방 이동으로는 회복하지 않는다).
## 지금 장면의 소녀 체력·이슬을 Progress.carry_* 에 적어 두면 다음 방(Room._ready)이 이어 받는다.
## 적지 않는 때: 보스 러시(보스마다 가득), 소녀가 없는 장면(회상·타이틀), 쓰러진 소녀(부활은 달빛풀에서 가득).
## 회상을 거쳐 보스 방으로 돌아올 때는 보스 방을 나갈 때 적은 값이 이어진다 (회상 장면에는 소녀가 없다).
func _capture_vitals() -> void:
	if BossRush.active:
		return
	var tree := get_tree()
	var cs := tree.current_scene
	var p := tree.get_first_node_in_group("player") as Player
	if cs == null or p == null or not is_instance_valid(p) or not cs.is_ancestor_of(p) or p.state == Player.State.DEAD:
		return
	Progress.carry_hp = p.hp
	Progress.carry_dews = p.dews


## 장면 시작 때 검은 화면에서 밝아지기만.
func fade_in(duration := 1.2) -> void:
	_black.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_black, "modulate:a", 0.0, duration)

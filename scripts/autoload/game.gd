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
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	tw = create_tween()
	tw.tween_property(_black, "modulate:a", 0.0, fade_in)
	await tw.finished
	_busy = false


## 장면 시작 때 검은 화면에서 밝아지기만.
func fade_in(duration := 1.2) -> void:
	_black.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_black, "modulate:a", 0.0, duration)

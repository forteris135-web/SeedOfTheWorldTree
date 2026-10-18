extends Area2D
class_name RoomExit
## 방과 방을 잇는 출구. 소녀가 들어오면 다음 방으로 넘어가고, 그 방의 spawn_name 자리에 선다.

@export_file("*.tscn") var target_scene := ""
## 다음 방에 있는 Marker2D 이름.
@export var spawn_name := ""
## 이 능력이 있어야 지나갈 수 있다 (예: lantern). 없으면 되밀리고 안내가 뜬다.
@export var requires_ability := ""
@export var locked_message := "어둠이 너무 짙다. 길을 밝힐 빛이 필요하다."
var _warned_at := -10.0

var _used := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _used or not (body is Player) or target_scene == "":
		return
	if requires_ability != "" and not Progress.has_ability(requires_ability):
		var p := body as Player
		p.velocity.x = -p.facing * 420.0
		p.global_position.x -= p.facing * 30.0
		var now := Time.get_ticks_msec() / 1000.0
		if now - _warned_at > 2.0:
			_warned_at = now
			var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
			if hud:
				hud.show_message(locked_message, 2.5)
		return
	_used = true
	Progress.next_spawn = spawn_name
	body.input_enabled = false
	Game.go_to(target_scene, 0.5, 0.9)

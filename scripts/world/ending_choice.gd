extends Node2D
class_name EndingChoice
## 마지막 선택지. 말 대신 행동으로: 심연의 뿌리에 손을 얹는가(희생), 마력의 관을 끊는가(되돌림).
## 둘 다 △. 가까이 가면 셀레니아가 허리의 등불을 내려다보는 짧은 연출(입력 잠깐 잠김) 뒤 선택할 수 있다.

@export_enum("sacrifice", "return") var choice := "sacrifice"
@export var label := "뿌리에 손을 얹는다"

var _near: Player
var _prompt: Label
var _t := 0.0
var _looked := false


func _ready() -> void:
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 24)
	_prompt.add_theme_color_override("font_color", Color("ffe6b0") if choice == "sacrifice" else Color("cfe9ff"))
	_prompt.position = Vector2(-140, -300)
	_prompt.visible = false
	add_child(_prompt)
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 170.0
	shape.shape = c
	shape.position = Vector2(0, -80)
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_enter)
	area.body_exited.connect(func(b): if b is Player: b.unregister_interactable(self); _near = null)


func _on_enter(b: Node) -> void:
	if not (b is Player):
		return
	_near = b
	b.register_interactable(self)
	if not Progress.has("looked_at_lantern"):
		Progress.set_flag("looked_at_lantern")
		# 등불을 내려다본다
		b.input_enabled = false
		b.velocity = Vector2.ZERO
		var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
		if hud:
			hud.show_message("셀레니아는 허리의 작은 등불을 내려다보았다.", 3.0)
		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(b):
			b.input_enabled = true


func _process(delta: float) -> void:
	_t += delta
	_prompt.visible = _near != null and _near.input_enabled
	if _prompt.visible:
		_prompt.text = "%s  %s" % [InputDevice.prompt("interact"), label]
	queue_redraw()


func interact(by: Player) -> void:
	by.input_enabled = false
	by.velocity = Vector2.ZERO
	Progress.ending = choice
	var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
	if hud:
		hud.show_message("…" if choice == "sacrifice" else "…", 1.0)
	Juice.rumble(0.3, 0.6, 0.6)
	await get_tree().create_timer(1.2).timeout
	Game.go_to("res://scenes/ui/ending_scene.tscn", 2.2, 1.5)


func _draw() -> void:
	var pulse := 0.6 + 0.4 * sin(_t * 1.8)
	if choice == "sacrifice":
		# 심연의 뿌리: 굵고 금빛이 도는 뿌리 덩어리
		for i in 5:
			var a := -1.2 + i * 0.6
			draw_line(Vector2.ZERO, Vector2(cos(a) * 140.0, -abs(sin(a)) * 220.0 - 40.0), Color(0.32, 0.26, 0.2), 22.0 - i * 2.0, true)
		draw_circle(Vector2(0, -120), 70.0 * pulse, Color(1.0, 0.85, 0.5, 0.1))
		draw_circle(Vector2(0, -120), 26.0, Color(1.0, 0.85, 0.5, 0.5 * pulse))
	else:
		# 마력의 관: 금속 관과 붉게 흐르는 빛
		draw_rect(Rect2(-40, -320, 80, 320), Color(0.3, 0.2, 0.18))
		draw_rect(Rect2(-40, -320, 80, 320), Color(0.5, 0.35, 0.3), false, 3.0)
		for i in 4:
			var y := -300.0 + fmod(_t * 120.0 + i * 80.0, 300.0)
			draw_rect(Rect2(-28, y, 56, 14), Color(1.0, 0.45, 0.3, 0.6))
		draw_circle(Vector2(0, -160), 60.0 * pulse, Color(1.0, 0.5, 0.35, 0.08))

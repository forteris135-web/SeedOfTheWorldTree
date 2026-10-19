extends Node2D
class_name EndingChoice
## 마지막 선택지. 말 대신 행동으로: 심연의 뿌리에 손을 얹는가(희생), 마력의 관을 끊는가(되돌림).
## 둘 다 △. 가까이 가면 셀레니아가 허리의 등불을 내려다보는 짧은 연출(입력 잠깐 잠김) 뒤 선택할 수 있다.
## 확장판(EXPANSION.md 7장) — 세 번째 행동 "심연의 거대한 펌프를 거꾸로 돌린다"(third): 다섯 수호자의 영혼
## (새 wind · 기사 light · 여왕 sap_walk · 펌프 wall_break 능력 + 뿌리지기 정화 깃발 boss_root_defeated)이 다 있을 때만 보인다.
## 고르면 다섯 빛 구슬이 모여 펌프 상징을 거꾸로 돌리는 빛 소용돌이(3초) 뒤 엔딩 "third" 로 간다.

@export_enum("sacrifice", "return", "third") var choice := "sacrifice"
@export var label := "뿌리에 손을 얹는다"

## 제3의 길에 필요한 네 영혼의 능력 (새 wind · 기사 light · 여왕 sap_walk · 펌프 wall_break) + 뿌리지기 정화 깃발
const FIVE_SOULS := ["wind", "light", "sap_walk", "wall_break"]
const ROOT_FLAG := "boss_root_defeated"
const SOUL_COLORS := [Color(0.75, 1.0, 0.85), Color(1.0, 0.85, 0.45), Color(0.45, 0.85, 0.95), Color(1.0, 0.55, 0.3), Color(0.8, 0.65, 1.0)]

var _near: Player
var _prompt: Label
var _t := 0.0
var _locked := false
var _ritual := -1.0   # 제3의 길 연출 진행(초). 음수면 아님
var _spin := 0.0      # 펌프 상징의 회전각 (거꾸로 돌면 줄어든다)


## 다섯 영혼이 다 있는가 (제3의 길 조건). 구원한 사람 수는 조건에 넣지 않는다 (EXPANSION.md 7장).
static func has_five_souls() -> bool:
	if not Progress.has(ROOT_FLAG):
		return false
	for a in FIVE_SOULS:
		if not Progress.has_ability(a):
			return false
	return true


func _ready() -> void:
	if choice == "third":
		_locked = not has_five_souls()
		if _locked:
			visible = false
		else:
			Progress.set_flag("five_souls")   # 티아의 마지막 말이 열린다
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 24)
	var col := Color("ffe6b0")
	if choice == "return":
		col = Color("cfe9ff")
	elif choice == "third":
		col = Color("ffd0a0")
	_prompt.add_theme_color_override("font_color", col)
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


func is_locked() -> bool:
	return _locked


func _on_enter(b: Node) -> void:
	if not (b is Player) or _locked:
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
	if _ritual >= 0.0:
		_ritual += delta
		# 거꾸로 도는 펌프: 점점 빨리
		_spin -= delta * (0.4 + _ritual * 1.4)
	else:
		_spin += delta * 0.15   # 평소엔 아주 천천히 '뽑는' 방향으로 돈다
	_prompt.visible = _near != null and _near.input_enabled and _ritual < 0.0
	if _prompt.visible:
		_prompt.text = "%s  %s" % [InputDevice.prompt("interact"), label]
	queue_redraw()


func interact(by: Player) -> void:
	if _locked:
		return
	by.input_enabled = false
	by.velocity = Vector2.ZERO
	Progress.ending = choice
	var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
	if choice == "third":
		# 다섯 영혼이 함께 펌프를 거꾸로 돌린다 (3초 연출)
		_ritual = 0.0
		if hud:
			hud.show_message("다섯 영혼이 함께 손을 얹었다.", 3.0)
		Sfx.play("soul", 0.0, 0.0)
		Juice.rumble(0.3, 0.6, 0.6)
		await get_tree().create_timer(1.6).timeout
		Sfx.play("purify", 0.0, 0.0)
		Juice.shake(8.0)
		await get_tree().create_timer(1.4).timeout
		Game.go_to("res://scenes/ui/ending_scene.tscn", 2.2, 1.5)
		return
	if hud:
		hud.show_message("…", 1.0)
	Juice.rumble(0.3, 0.6, 0.6)
	await get_tree().create_timer(1.2).timeout
	Game.go_to("res://scenes/ui/ending_scene.tscn", 2.2, 1.5)


func _draw() -> void:
	var pulse := 0.6 + 0.4 * sin(_t * 1.8)
	match choice:
		"sacrifice":
			# 심연의 뿌리: 굵고 금빛이 도는 뿌리 덩어리
			for i in 5:
				var a := -1.2 + i * 0.6
				draw_line(Vector2.ZERO, Vector2(cos(a) * 140.0, -abs(sin(a)) * 220.0 - 40.0), Color(0.32, 0.26, 0.2), 22.0 - i * 2.0, true)
			draw_circle(Vector2(0, -120), 70.0 * pulse, Color(1.0, 0.85, 0.5, 0.1))
			draw_circle(Vector2(0, -120), 26.0, Color(1.0, 0.85, 0.5, 0.5 * pulse))
		"return":
			# 마력의 관: 금속 관과 붉게 흐르는 빛
			draw_rect(Rect2(-40, -320, 80, 320), Color(0.3, 0.2, 0.18))
			draw_rect(Rect2(-40, -320, 80, 320), Color(0.5, 0.35, 0.3), false, 3.0)
			for i in 4:
				var y := -300.0 + fmod(_t * 120.0 + i * 80.0, 300.0)
				draw_rect(Rect2(-28, y, 56, 14), Color(1.0, 0.45, 0.3, 0.6))
			draw_circle(Vector2(0, -160), 60.0 * pulse, Color(1.0, 0.5, 0.35, 0.08))
		"third":
			_draw_pump(pulse)


## 심연의 거대한 펌프 상징: 받침 위의 큰 톱니바퀴와 양쪽 관. 연출 중에는 다섯 빛 구슬이 모여들며 거꾸로 돌고 빛 소용돌이가 인다.
func _draw_pump(pulse: float) -> void:
	var c := Vector2(0, -190)
	var rust := Color(0.4, 0.2, 0.14)
	var dark := Color(0.2, 0.1, 0.08)
	# 받침과 관
	draw_rect(Rect2(-70, -60, 140, 60), dark)
	draw_rect(Rect2(-230, -140, 160, 40), rust)
	draw_rect(Rect2(70, -140, 160, 40), rust)
	# 톱니바퀴 (spin 만큼 돈다)
	var r := 110.0
	draw_circle(c, r + 18.0, dark)
	for i in 12:
		var a := _spin + i * TAU / 12.0
		var p0 := c + Vector2(cos(a), sin(a)) * (r + 10.0)
		draw_line(p0, c + Vector2(cos(a), sin(a)) * (r + 32.0), dark, 22.0)
	draw_circle(c, r, rust)
	draw_arc(c, r * 0.7, 0.0, TAU, 32, dark, 6.0, true)
	for i in 4:
		var a := _spin + i * TAU / 4.0
		draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.7, dark, 10.0)
	# 핵: 다섯 영혼이 닿기 전엔 희미하게, 연출 중엔 밝게
	var glow := 0.25 + 0.15 * pulse
	if _ritual >= 0.0:
		glow = clampf(0.4 + _ritual * 0.4, 0.0, 1.4)
	draw_circle(c, 26.0, Color(0.45, 0.85, 0.95, glow))
	draw_circle(c, 70.0 * pulse, Color(0.45, 0.85, 0.95, 0.08 + 0.1 * glow))
	# 거꾸로 도는 화살표 (연출 중)
	if _ritual >= 0.0:
		var k := clampf(_ritual / 3.0, 0.0, 1.0)
		for i in 3:
			var a0 := -_spin * 0.5 + i * TAU / 3.0
			draw_arc(c, r + 50.0 + i * 8.0, a0, a0 + 1.6, 14, Color(1.0, 0.9, 0.7, 0.5 * k), 4.0, true)
		# 다섯 빛 구슬: 둘레에서 가운데로 모여들며 돈다
		for i in 5:
			var ang := -_t * 2.0 + i * TAU / 5.0
			var dist := lerpf(260.0, 30.0, Motion.ease_in_out(k))
			var p := c + Vector2(cos(ang), sin(ang) * 0.8) * dist
			var col: Color = SOUL_COLORS[i]
			draw_circle(p, 34.0, Color(col, 0.18))
			draw_circle(p, 14.0, Color(col, 0.95))
			draw_circle(p + Vector2(-4, -4), 5.0, Color(1, 1, 1, 0.8))
		# 빛 소용돌이
		for i in 6:
			var a := -_t * 5.0 + i * 1.05
			var rr := 40.0 + i * 24.0 + k * 60.0
			draw_arc(c, rr, a, a + 1.2, 10, Color(0.85, 0.95, 1.0, 0.35 * k), 3.0, true)
		# 끝자락: 다섯 빛이 하나로 합쳐져 하얗게 터진다 (밝은 값은 글로우로 번지고, 곧 엔딩으로 어두워진다)
		var burst := clampf((_ritual - 2.1) / 0.9, 0.0, 1.0)
		if burst > 0.0:
			# 겹친 원 열둘로 가장자리가 부드러운 빛 무리 (가운데로 갈수록 진하다)
			var big := 60.0 + 560.0 * Motion.ease_in_out(burst)
			for i in 12:
				draw_circle(c, big * float(i + 1) / 12.0, Color(1.0, 0.97, 0.9, 0.035 * burst))
			for i in 4:
				draw_circle(c, (26.0 + 80.0 * burst) * float(i + 1) / 4.0, Color(1.5, 1.45, 1.3, 0.16 * burst))

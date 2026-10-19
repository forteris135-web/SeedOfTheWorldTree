extends Control
class_name BossRushResult
## 보스 러시 결과 화면. 열리자마자 러시가 떼어 둔 진행을 되돌린다 (BossRush.restore) — 그 뒤로는 평소 게임 그대로.
## 완주: 전체 시간 + 보스별 기록 (+ 보스별 최고), 최고 기록·새 기록. 쓰러짐/포기: 어디까지 왔는지와 그때까지의 시간.
## 배경은 클리어 후 타이틀 그림을 어둡게. 아무 버튼(또는 화면 누르기)으로 타이틀로 — 1.2초 동안은 받지 않는다(연타로 넘어가지 않게).
## 글자는 data/dialogue/boss_rush.json.

const ACCEPT_AFTER := 1.2

var _r := {}
var _t := 0.0
var _leaving := false
var _art: TextureRect
var _canvas: Control


func _ready() -> void:
	_r = BossRush.result.duplicate(true)
	BossRush.restore()
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_art = TextureRect.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var look := TitleScreen.title_look(TitleScreen.cleared_state())
	if ResourceLoader.exists(look["image"]):
		_art.texture = load(look["image"])
	_art.modulate = Color(0.32, 0.32, 0.36, 1.0)
	add_child(_art)
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	_canvas.modulate.a = 0.0
	create_tween().tween_property(_canvas, "modulate:a", 1.0, 0.8).set_delay(0.3)
	Music.play(Music.REST, {"fade": 2.0})
	if outcome() == "clear":
		Sfx.play("soul", 0.0, 0.0)


func _process(delta: float) -> void:
	_t += delta
	_canvas.queue_redraw()   # 새 기록 글자·안내가 숨 쉰다


## 시험용
func outcome() -> String:
	return str(_r.get("outcome", ""))


func result() -> Dictionary:
	return _r


func can_leave() -> bool:
	return _t >= ACCEPT_AFTER and not _leaving


## 타이틀로 (시험도 부른다)
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.play("select")
	Game.go_to(Game.TITLE_SCENE, 0.8, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
		or event.is_action_pressed("pause") or event.is_action_pressed("attack_light") or event.is_action_pressed("dodge") \
		or (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if pressed and can_leave():
		leave()


func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var size := _canvas.size
	var cx := size.x / 2.0
	var w := 1100.0
	var x0 := cx - w / 2.0
	var ol := Color(0.01, 0.01, 0.02, 0.9)
	var gold := Color(1.0, 0.86, 0.55)
	var oc := outcome()
	var head := BossRush.text("result_clear" if oc == "clear" else ("result_dead" if oc == "dead" else "result_quit"))
	var y := size.y * 0.15
	_str(font, Vector2(x0, y), BossRush.text("title"), 28, Color(gold, 0.75), w, ol)
	_str(font, Vector2(x0, y + 74), head, 64, gold if oc == "clear" else Color(0.92, 0.9, 0.95), w, ol)
	var reached := int(_r.get("reached", 0))
	if oc != "clear":
		_str(font, Vector2(x0, y + 122), BossRush.text("reached", {"n": reached + 1, "name": BossRush.boss_name(reached)}), 26, Color(0.85, 0.85, 0.9, 0.9), w, ol)
	# 보스별 기록
	var splits: Array = _r.get("splits", [])
	var sb: Dictionary = _r.get("split_bests", {})
	var row_y := y + 190.0
	for i in BossRush.BOSSES.size():
		var ry := row_y + i * 54.0
		var bg := Color(1, 1, 1, 0.06) if i % 2 == 0 else Color(1, 1, 1, 0.03)
		_canvas.draw_rect(Rect2(x0 + 60, ry - 36, w - 120, 48), bg)
		var done := i < splits.size()
		var now := (not done) and oc != "clear" and i == reached
		var col := Color(0.95, 0.95, 0.95) if done else (Color(1.0, 0.7, 0.62) if now else Color(0.6, 0.62, 0.66))
		_canvas.draw_string(font, Vector2(x0 + 90, ry), "%d.  %s" % [i + 1, BossRush.boss_name(i)], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col)
		var tt := BossRush.text("not_reached")
		if done:
			tt = BossRush.format_time(float(splits[i]))
		elif now:
			tt = BossRush.text("fighting" if oc == "dead" else "quit_mark") + "  " + BossRush.format_time(float(_r.get("current", 0.0)))
		_canvas.draw_string(font, Vector2(x0 + w - 640, ry), tt, HORIZONTAL_ALIGNMENT_RIGHT, 360, 28, col)
		var id := BossRush.boss_id(i)
		if sb.has(id):
			_canvas.draw_string(font, Vector2(x0 + w - 270, ry), "%s %s" % [BossRush.text("best_split"), BossRush.format_time(float(sb[id]))], HORIZONTAL_ALIGNMENT_RIGHT, 190, 20, Color(0.7, 0.8, 0.9, 0.75))
	# 전체 시간 · 최고 기록
	var ty := row_y + BossRush.BOSSES.size() * 54.0 + 46.0
	_str(font, Vector2(x0, ty), "%s   %s" % [BossRush.text("total"), BossRush.format_time(float(_r.get("total", 0.0)))], 40, Color(1, 1, 1, 0.96), w, ol)
	var best := float(_r.get("best_total", -1.0))
	var best_text := "%s   %s" % [BossRush.text("best"), BossRush.format_time(best) if best >= 0.0 else BossRush.text("no_best")]
	_str(font, Vector2(x0, ty + 50), best_text, 26, Color(0.75, 0.85, 0.95, 0.85), w, ol)
	if _r.get("new_best", false):
		var pulse := 0.75 + 0.25 * sin(_t * 4.0)
		_str(font, Vector2(x0, ty + 96), BossRush.text("new_best"), 34, Color(1.0, 0.86, 0.45, pulse), w, ol)
	var g := BossRush.text("growth_full" if str(_r.get("growth", "")) == "full" else "growth_save")
	_str(font, Vector2(x0, size.y - 104), g, 18, Color(1, 1, 1, 0.4), w, ol)
	if can_leave():
		var hint := BossRush.text("back_hint_touch" if InputDevice.current == InputDevice.Kind.TOUCH else "back_hint_pad")
		_str(font, Vector2(x0, size.y - 64), hint, 22, Color(1, 1, 1, 0.55 + 0.2 * sin(_t * 2.5)), w, ol)


func _str(font: Font, at: Vector2, s: String, fs: int, col: Color, w: float, ol: Color) -> void:
	_canvas.draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 8, ol)
	_canvas.draw_string(font, at, s, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)

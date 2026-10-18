extends CanvasLayer
## 전투 표시: 체력, 가드 게이지, 이슬 방울, 가운데 메시지.
## 그림: art/ui/ (기획자의 HUD 시트에서 잘라낸 조각). 좌표 상수는 시트(1672×941) 기준이고
## 화면에는 SHEET_SCALE 로 줄여 그린다. 조각 자르기는 tools/cut_hud.gd.

const SHEET_SCALE := 0.36
const ORIGIN := Vector2(10, 4)

const EMBLEM := preload("res://art/ui/hud_emblem.png")
const BAR_HP := preload("res://art/ui/hud_bar_hp.png")
const BAR_GUARD := preload("res://art/ui/hud_bar_guard.png")
const DEWS := [preload("res://art/ui/hud_dew_1.png"), preload("res://art/ui/hud_dew_2.png"), preload("res://art/ui/hud_dew_3.png")]

const EMBLEM_POS := Vector2(0, 0)
const HP_TRACK_POS := Vector2(540, 60)
const HP_FILL := Rect2(560, 219, 1400, 86)        # 채워지는 구간 (시트 좌표)
const HP_RED_SLICE := Rect2(360, 159, 40, 86)     # 틀 그림 안에서 "찬 부분" 조각
const HP_DARK_SLICE := Rect2(1260, 159, 40, 86)   # "빈 부분" 조각
const GUARD_TRACK_POS := Vector2(540, 318)
const GUARD_FILL := Rect2(560, 331, 1100, 70)
const GUARD_GREEN_SLICE := Rect2(360, 13, 40, 70)
const GUARD_DARK_SLICE := Rect2(910, 13, 40, 70)
const DEW_POS := [Vector2(405, 445), Vector2(560, 445), Vector2(735, 445)]
const SEED_CENTER := Vector2(330, 320)

var _player: Player
var _canvas: Control
var _message := ""
var _message_timer := 0.0
var _flash_text := ""
var _flash_timer := 0.0
var _time := 0.0
var _hp_shown := 1.0       # 체력 막대가 천천히 따라오게
var _guard_flash := 0.0


func _ready() -> void:
	layer = 15
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)


func _process(delta: float) -> void:
	_time += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player:
			_hp_shown = _player.hp / _player.max_hp
			_player.just_guarded.connect(func(_s): flash("저스트 가드!"); _guard_flash = 1.0)
			_player.guard_broken.connect(func(): flash("가드가 깨졌다"); _guard_flash = 1.0)
			_player.purify_started.connect(func(_t): flash("정화의 손길"))
			_player.died.connect(func(): show_message("쓰러졌다…", 2.5))
			_player.rest_started.connect(func(_g): show_message("달빛풀에서 쉰다. 적들이 다시 깨어난다.", 2.5))
	else:
		var target := _player.hp / _player.max_hp
		_hp_shown = move_toward(_hp_shown, target, delta * (2.5 if target < _hp_shown else 4.0))
	_message_timer = maxf(_message_timer - delta, 0.0)
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	_guard_flash = maxf(_guard_flash - delta * 2.0, 0.0)
	_canvas.queue_redraw()


func show_message(text: String, seconds := 2.0) -> void:
	_message = text
	_message_timer = seconds


func flash(text: String) -> void:
	_flash_text = text
	_flash_timer = 0.8


func _s(p: Vector2) -> Vector2:
	return ORIGIN + p * SHEET_SCALE


func _draw_bar(tex: Texture2D, track_pos: Vector2, fill: Rect2, full_slice: Rect2, empty_slice: Rect2, ratio: float) -> void:
	_canvas.draw_texture_rect(tex, Rect2(_s(track_pos), tex.get_size() * SHEET_SCALE), false)
	var full_w := fill.size.x * clampf(ratio, 0.0, 1.0)
	if full_w > 1.0:
		_canvas.draw_texture_rect_region(tex, Rect2(_s(fill.position), Vector2(full_w, fill.size.y) * SHEET_SCALE), full_slice)
	if fill.size.x - full_w > 1.0:
		_canvas.draw_texture_rect_region(tex, Rect2(_s(fill.position + Vector2(full_w, 0)), Vector2(fill.size.x - full_w, fill.size.y) * SHEET_SCALE), empty_slice)


func _on_draw() -> void:
	if _player == null:
		return
	var font := ThemeDB.fallback_font
	var hp_ratio := _player.hp / _player.max_hp
	# 막대 (틀 → 찬 부분 → 빈 부분). 체력은 줄어든 자리를 잠깐 밝게 남긴다.
	_draw_bar(BAR_HP, HP_TRACK_POS, HP_FILL, HP_RED_SLICE, HP_DARK_SLICE, _hp_shown)
	if _hp_shown > hp_ratio + 0.002:
		var lost := Rect2(_s(HP_FILL.position + Vector2(HP_FILL.size.x * hp_ratio, 0)), Vector2(HP_FILL.size.x * (_hp_shown - hp_ratio), HP_FILL.size.y) * SHEET_SCALE)
		_canvas.draw_rect(lost, Color(1.0, 0.9, 0.7, 0.55))
	_draw_bar(BAR_GUARD, GUARD_TRACK_POS, GUARD_FILL, GUARD_GREEN_SLICE, GUARD_DARK_SLICE, _player.guard / _player.max_guard)
	if _guard_flash > 0.0:
		_canvas.draw_rect(Rect2(_s(GUARD_FILL.position), GUARD_FILL.size * SHEET_SCALE), Color(0.56, 0.83, 1.0, 0.6 * _guard_flash))
	# 엠블럼과 씨앗의 빛
	_canvas.draw_texture_rect(EMBLEM, Rect2(_s(EMBLEM_POS), EMBLEM.get_size() * SHEET_SCALE), false)
	var low := hp_ratio < 0.3
	var pulse := 0.75 + 0.25 * sin(_time * (7.0 if low else 2.2))
	var glow_color := Color(2.2, 0.9, 0.6, 0.16 * pulse) if low else Color(2.0, 1.7, 1.0, 0.1 * pulse)
	_canvas.draw_circle(_s(SEED_CENTER), 40.0 * SHEET_SCALE * (1.2 + 0.4 * pulse), glow_color)
	# 이슬 방울
	for i in _player.max_dews:
		var k := mini(i, DEW_POS.size() - 1)
		var tex: Texture2D = DEWS[k]
		var tint := Color(1.2, 1.2, 1.25, 1.0) if i < _player.dews else Color(0.45, 0.45, 0.5, 0.4)
		_canvas.draw_texture_rect(tex, Rect2(_s(DEW_POS[k]), tex.get_size() * SHEET_SCALE), false, tint)
	# 고른 영혼: 이름만 보인다. 키 안내는 설명 글자라서 '개발 표시'를 켰을 때만 덧붙인다.
	if _player.soul != "":
		var label := "영혼: %s" % _player.soul_name()
		if bool(Settings.get_value("debug_hud")):
			label += "   (%s)" % InputDevice.prompt("soul_ability")
			if _player.owned_souls().size() > 1:
				# 터치 사전에는 soul_next 가 없어서 터치는 버튼 이름을 직접 쓴다
				var nxt := "전환 버튼" if InputDevice.current == InputDevice.Kind.TOUCH else InputDevice.prompt("soul_next")
				label += "   전환 %s" % nxt
		_canvas.draw_string(font, _s(Vector2(60, 790)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 1.0, 0.9, 0.85) if _player.soul == "wind" else Color(1.0, 0.9, 0.7, 0.9))
	# 메시지
	var size := _canvas.size
	if _message_timer > 0.0:
		var a := clampf(_message_timer / 0.5, 0.0, 1.0)
		_canvas.draw_string(font, Vector2(size.x / 2.0 - 500, size.y * 0.3), _message, HORIZONTAL_ALIGNMENT_CENTER, 1000, 40, Color(1, 1, 1, a))
	if _flash_timer > 0.0:
		var a2 := clampf(_flash_timer / 0.3, 0.0, 1.0)
		_canvas.draw_string(font, Vector2(size.x / 2.0 - 300, size.y * 0.42), _flash_text, HORIZONTAL_ALIGNMENT_CENTER, 600, 34, Color("ffd46a", a2))

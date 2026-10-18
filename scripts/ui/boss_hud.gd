extends CanvasLayer
## 보스 표시: 화면 아래 이름, 체력, 흐트러짐. 셀레니아 HUD와 같은 그림(잎 테두리 막대)을 쓴다.
## 등장 때 큰 이름이 떠올랐다 사라진다.

const BAR_HP := preload("res://art/ui/hud_bar_hp.png")       # 1616×258 (시트 좌표 540,60 기준)
const BAR_GUARD := preload("res://art/ui/hud_bar_guard.png") # 1616×185 (시트 좌표 540,318 기준)
# 조각 안에서의 채움 구간과 "찬/빈" 색 조각 (조각 좌표 = 시트 좌표 - 조각 원점)
const HP_FILL := Rect2(20, 159, 1400, 86)
const HP_RED := Rect2(360, 159, 40, 86)
const HP_DARK := Rect2(1260, 159, 40, 86)
const GUARD_FILL := Rect2(20, 13, 1100, 70)
const GUARD_BLUE := Rect2(360, 13, 40, 70)
const GUARD_DARK := Rect2(910, 13, 40, 70)
const SCALE := 0.7

var _boss: Node
var _canvas: Control
var _shown := 0.0
var _target_shown := 0.0
var _title := 0.0
var _hp_trail := 1.0
var _name := ""
var _subtitle := ""
var _hp := 1.0
var _poise := 0.0
var _flash := 0.0
var _t := 0.0


func _ready() -> void:
	layer = 16
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)


func bind(boss: Node, boss_name: String, subtitle := "") -> void:
	_boss = boss
	_name = boss_name
	_subtitle = subtitle
	_hp = 1.0
	_hp_trail = 1.0
	_poise = 0.0
	boss.hp_changed.connect(func(hp, mx): _hp = hp / mx)
	boss.poise_changed.connect(func(p, mx): _poise = p / mx)
	if boss.has_signal("phase_changed"):
		boss.phase_changed.connect(func(_p): _flash = 1.0)


func show_boss() -> void:
	_title = 3.0
	_target_shown = 1.0


func hide_boss() -> void:
	_target_shown = 0.0


func _process(delta: float) -> void:
	_t += delta
	_shown = move_toward(_shown, _target_shown, delta * 1.5)
	_title = maxf(_title - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_hp_trail = move_toward(_hp_trail, _hp, delta * (0.35 if _hp < _hp_trail else 3.0))
	_canvas.queue_redraw()


func _bar(tex: Texture2D, origin: Vector2, fill: Rect2, full_slice: Rect2, empty_slice: Rect2, ratio: float, a: float, trail := -1.0) -> void:
	# 장식 없이 막대만: 채움 구간을 같은 그림 조각으로 늘려 그리고 가는 테두리를 두른다
	var tint := Color(1, 1, 1, a)
	var full_w := fill.size.x * clampf(ratio, 0.0, 1.0)
	var rect := Rect2(origin, fill.size * SCALE)
	_canvas.draw_rect(rect.grow(3.0), Color(0.05, 0.04, 0.03, 0.75 * a))
	if trail > ratio:
		var tw := fill.size.x * (trail - ratio)
		_canvas.draw_texture_rect_region(tex, Rect2(origin + Vector2(full_w, 0) * SCALE, Vector2(tw, fill.size.y) * SCALE), full_slice, Color(1.6, 1.4, 1.2, a))
		full_w += tw
	if fill.size.x * ratio > 1.0:
		_canvas.draw_texture_rect_region(tex, Rect2(origin, Vector2(fill.size.x * ratio, fill.size.y) * SCALE), full_slice, tint)
	if fill.size.x - full_w > 1.0:
		_canvas.draw_texture_rect_region(tex, Rect2(origin + Vector2(full_w, 0) * SCALE, Vector2(fill.size.x - full_w, fill.size.y) * SCALE), empty_slice, tint)
	_canvas.draw_rect(rect, Color(0.85, 0.72, 0.5, 0.8 * a), false, 2.0)


func _on_draw() -> void:
	if _shown <= 0.01:
		return
	var font := ThemeDB.fallback_font
	var size := _canvas.size
	var a := _shown
	var hp_w := HP_FILL.size.x * SCALE
	var x := (size.x - hp_w) / 2.0
	var y := size.y - 150.0
	_canvas.draw_string(font, Vector2(x, y - 12), _name, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(1.0, 0.9, 0.72, a))
	_bar(BAR_HP, Vector2(x, y), HP_FILL, HP_RED, HP_DARK, _hp, a, _hp_trail)
	if _flash > 0.0:
		_canvas.draw_rect(Rect2(Vector2(x, y), HP_FILL.size * SCALE), Color(1, 0.95, 0.8, 0.5 * _flash * a))
	# 흐트러짐 (은청색, 더 가늘게)
	var gy := y + HP_FILL.size.y * SCALE + 10.0
	var gscale := 0.45
	var grect := Rect2(Vector2(x, gy), Vector2(GUARD_FILL.size.x * SCALE * 0.7, GUARD_FILL.size.y * gscale))
	_canvas.draw_rect(grect.grow(2.0), Color(0.05, 0.04, 0.03, 0.75 * a))
	_canvas.draw_rect(grect, Color(0.08, 0.1, 0.14, 0.9 * a))
	_canvas.draw_rect(Rect2(grect.position, Vector2(grect.size.x * _poise, grect.size.y)), Color(0.56, 0.83, 1.0, a))
	if _poise >= 0.999:
		var pulse := 0.5 + 0.5 * sin(_t * 8.0)
		_canvas.draw_rect(grect, Color(1, 1, 1, 0.5 * pulse * a))
	if _title > 0.0:
		var t := clampf(_title / 0.6, 0.0, 1.0) if _title < 0.6 else clampf((3.0 - _title) / 0.6, 0.0, 1.0)
		_canvas.draw_string(font, Vector2(size.x / 2.0 - 600, size.y * 0.22), _name, HORIZONTAL_ALIGNMENT_CENTER, 1200, 72, Color(0.95, 0.9, 0.8, t))
		_canvas.draw_string(font, Vector2(size.x / 2.0 - 600, size.y * 0.22 + 44), _subtitle, HORIZONTAL_ALIGNMENT_CENTER, 1200, 24, Color(0.8, 0.8, 0.8, t * 0.8))

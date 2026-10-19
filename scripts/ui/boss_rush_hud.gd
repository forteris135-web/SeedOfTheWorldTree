extends CanvasLayer
class_name BossRushHUD
## 보스 러시의 작은 시계 (화면 위 가운데 — 체력 막대가 길면 그 오른쪽으로 비켜 선다). BossRoom 이 러시 모드일 때 붙인다.
## 윗줄: "보스 러시  2 / 5", 가운데: 전체 시간, 아랫줄: 이번 싸움 시간 (보스를 쓰러뜨린 뒤에는 "다음 수호자에게로…").
## 글자는 data/dialogue/boss_rush.json. 시간 글자는 1초에 20번만 새로 그린다 (매 프레임 글자를 만들지 않게).

const W := 380.0
const H := 118.0
const TOP := 14.0
const REDRAW_EVERY := 0.05
## 체력 막대 등 왼쪽 위 HUD 의 오른쪽 끝을 다시 재는 간격 (초)
const PLACE_EVERY := 0.5

var _canvas: Control
var _acc := 0.0
var _label := ""
var _total := ""
var _sub := ""
var _sb: StyleBoxFlat
var _cx := -1.0
var _place_acc := 0.0


func _ready() -> void:
	layer = 17
	_sb = StyleBoxFlat.new()
	_sb.bg_color = Color(0.03, 0.04, 0.06, 0.62)
	_sb.border_color = Color(1.0, 0.86, 0.55, 0.35)
	_sb.set_border_width_all(2)
	_sb.set_corner_radius_all(14)
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	_refresh()


func _process(delta: float) -> void:
	_acc += delta
	_place_acc += delta
	if _place_acc >= PLACE_EVERY or _cx < 0.0:
		_place_acc = 0.0
		_place()
	if _acc >= REDRAW_EVERY:
		_acc = 0.0
		_refresh()


func _refresh() -> void:
	var i := BossRush.index_of_scene(get_tree().current_scene.scene_file_path) if get_tree().current_scene else BossRush.index
	if i < 0:
		i = BossRush.index
	_label = BossRush.text("hud_label", {"n": i + 1, "total": BossRush.BOSSES.size()})
	_total = BossRush.format_time(BossRush.current_total())
	if BossRush.advancing:
		_sub = BossRush.text("all_clear" if BossRush.is_last() else "next")
	else:
		_sub = BossRush.text("hud_split", {"time": BossRush.format_time(BossRush.elapsed)})
	_canvas.queue_redraw()


## 가운데 x: 화면 가운데, 단 왼쪽 위 HUD(체력 막대·이슬·빛 가루·영혼 줄)의 오른쪽 끝보다 오른쪽, 오른쪽 위 '지도' 버튼 자리는 비운다
## (CombatHUD 의 영혼 전환 알림과 같은 방식)
func _place() -> void:
	var size := _canvas.size if _canvas else Vector2(1920, 1080)
	var cx := size.x / 2.0
	var scene := get_tree().current_scene
	var hud := scene.get_node_or_null("CombatHUD") if scene else null
	if hud and hud.has_method("hud_right_x"):
		cx = maxf(cx, float(hud.hud_right_x(TOP, TOP + H)) + 40.0 + W / 2.0)
	cx = minf(cx, size.x - 130.0 - W / 2.0)
	if not is_equal_approx(cx, _cx):
		_cx = cx
		_canvas.queue_redraw()


## 시계 판의 자리 (화면 좌표, 시험용)
func panel_rect() -> Rect2:
	var size := _canvas.size
	var cx := _cx if _cx >= 0.0 else size.x / 2.0
	return Rect2(cx - W / 2.0, TOP, W, H)


## 시험용: 지금 보이는 글자 세 줄
func lines() -> Array:
	return [_label, _total, _sub]


func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var r := panel_rect()
	_canvas.draw_style_box(_sb, r)
	var ol := Color(0.02, 0.02, 0.03, 0.85)
	_text(font, Vector2(r.position.x, r.position.y + 30), _label, 22, Color(1.0, 0.86, 0.55, 0.9), ol)
	_text(font, Vector2(r.position.x, r.position.y + 74), _total, 40, Color(1, 1, 1, 0.96), ol)
	_text(font, Vector2(r.position.x, r.position.y + 104), _sub, 20, Color(0.78, 0.86, 0.92, 0.85), ol)


func _text(font: Font, at: Vector2, s: String, fs: int, col: Color, ol: Color) -> void:
	_canvas.draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_CENTER, W, fs, 6, ol)
	_canvas.draw_string(font, at, s, HORIZONTAL_ALIGNMENT_CENTER, W, fs, col)

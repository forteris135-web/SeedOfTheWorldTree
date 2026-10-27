extends CanvasLayer
class_name RootKeeperSpeech
## 뿌리지기의 싸움 중 한 마디 (v1.1.1 기획자 지시서 2-E 추가 '스토리텔링'): 화면 위쪽 가운데의 자막. 입력을 막지 않는다
## (싸움 전 대화 상자 Dialogue 와 다르다). 말하는 이 이름(작게) + 한 줄(천천히 떠오름 — 타자기 효과는 가운데 맞춤 글자가 흔들려 뺐다) + 옅은 어두운 띠.
## 자리: 소녀 HUD(왼쪽 위)·보스 띠(아래)·대화 상자(아래)·가운데 안내(화면 높이 0.3)·공격 이름(0.42)·영혼 전환 알림(0.17)과
## 겹치지 않게 위쪽 띠(화면 높이 약 0.04~0.14)에 둔다. HUD 가 길어져 그 높이까지 오른쪽으로 뻗으면(CombatHUD.hud_right_x)
## 자막을 그 오른쪽으로 민다. 오른쪽 위 터치 '지도' 버튼 자리(RIGHT_MARGIN)는 비운다.
## root_keeper.gd 가 만들어 붙이고 say() 로 부른다. 대사 문장은 data/dialogue/root_keeper.json.

const NAME_Y := 0.058          # 이름 글자 기준선 (화면 높이 비율)
const LINE_Y := 0.112          # 대사 첫 줄 기준선
const NAME_SIZE := 22
const LINE_SIZE := 32
const LINE_GAP := 40.0         # 두 줄일 때 줄 간격 (px)
const MAX_W := 1000.0
const RIGHT_MARGIN := 150.0
const LEFT_MARGIN := 40.0
const FADE_IN := 0.25
const FADE_OUT := 0.45
const QUEUE_MAX_WAIT := 5.0    # 기다리던 대사가 이보다 오래 밀리면 버린다
const NAME_C := Color(0.8, 0.68, 0.98)
const LINE_C := Color(0.97, 0.95, 0.9)

var speaker := "뿌리지기"
## 소녀 HUD (CombatHUD) — 자막을 HUD 오른쪽으로 밀 때 읽는다. 없으면 가운데.
var hud: Node = null
var _text := ""
var _t := 0.0
var _len := 0.0
var _queue: Array = []   # [문장, 초, 넣은 시각]
var _clock := 0.0
var _canvas: Control


func _ready() -> void:
	layer = 16
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)


## 한 마디를 띄운다. 이미 떠 있으면 그것이 끝난 뒤 (하나만 기다린다 — 새 것이 옛 것을 밀어낸다). force 면 바로 바꾼다.
func say(text: String, seconds := 3.6, force := false) -> void:
	if text == "":
		return
	if force or _text == "":
		_queue.clear()
		_show(text, seconds)
	else:
		_queue = [[text, seconds, _clock]]


func clear() -> void:
	_text = ""
	_queue.clear()
	if _canvas:
		_canvas.queue_redraw()


## 지금 떠 있는 대사 ("" = 없음)
func current_text() -> String:
	return _text


func showing() -> bool:
	return _text != ""


func _show(text: String, seconds: float) -> void:
	_text = text
	_t = 0.0
	_len = maxf(seconds, FADE_IN + FADE_OUT + 0.5)


func _process(delta: float) -> void:
	_clock += delta
	if _text == "":
		if not _queue.is_empty():
			var q: Array = _queue.pop_front()
			if _clock - float(q[2]) < QUEUE_MAX_WAIT:
				_show(q[0], q[1])
		return
	_t += delta
	if _t >= _len:
		_text = ""
	_canvas.queue_redraw()


## 자막 띠가 놓일 화면 사각형 (시험이 HUD·다른 글자와 겹치지 않는지 읽는다)
func box_rect() -> Rect2:
	var size := _canvas.size if _canvas else Vector2(1920, 1080)
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, LINE_SIZE).x if _text != "" else 400.0
	var two := tw > MAX_W - 60.0
	var w := minf(tw + 80.0, MAX_W)
	var y0 := size.y * NAME_Y - 30.0
	var y1 := size.y * LINE_Y + (LINE_GAP if two else 0.0) + 16.0
	var left := LEFT_MARGIN
	if hud and is_instance_valid(hud) and hud.has_method("hud_right_x") and hud.get("_player") != null:
		left = maxf(left, float(hud.hud_right_x(y0, y1)) + 24.0)
	var right := size.x - RIGHT_MARGIN
	if right - left < w:
		w = maxf(right - left, 300.0)
	var cx := clampf(size.x / 2.0, left + w / 2.0, right - w / 2.0)
	return Rect2(cx - w / 2.0, y0, w, y1 - y0)


func _on_draw() -> void:
	if _text == "":
		return
	var a := clampf(_t / FADE_IN, 0.0, 1.0) * clampf((_len - _t) / FADE_OUT, 0.0, 1.0)
	if a <= 0.0:
		return
	var font := ThemeDB.fallback_font
	var r := box_rect()
	# 옅은 어두운 띠 (가장자리는 더 옅게 — 배경을 가리지 않게)
	_canvas.draw_rect(Rect2(r.position.x - 40.0, r.position.y, r.size.x + 80.0, r.size.y), Color(0.02, 0.01, 0.04, 0.22 * a))
	_canvas.draw_rect(r, Color(0.02, 0.01, 0.04, 0.38 * a))
	_canvas.draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.end.y), Color(NAME_C, 0.35 * a), 1.5)
	var size := _canvas.size
	_canvas.draw_string_outline(font, Vector2(r.position.x, size.y * NAME_Y), speaker, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, NAME_SIZE, 4, Color(0.02, 0.01, 0.04, 0.8 * a))
	_canvas.draw_string(font, Vector2(r.position.x, size.y * NAME_Y), speaker, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, NAME_SIZE, Color(NAME_C, a))
	var lw := r.size.x - 40.0
	_canvas.draw_multiline_string_outline(font, Vector2(r.position.x + 20.0, size.y * LINE_Y), _text, HORIZONTAL_ALIGNMENT_CENTER, lw, LINE_SIZE, 2, 6, Color(0.02, 0.01, 0.04, 0.85 * a))
	_canvas.draw_multiline_string(font, Vector2(r.position.x + 20.0, size.y * LINE_Y), _text, HORIZONTAL_ALIGNMENT_CENTER, lw, LINE_SIZE, 2, Color(LINE_C, a))

extends CanvasLayer
## 보스 표시 (2026-10-18 기획자 결정): 싸움이 시작되면 화면 **아래에만** 얇은 레터박스 띠가 올라온다.
## 띠는 순수한 검정이 아니라 아래로 갈수록 어두워지는 흙과 뿌리다. 보스 이름과 체력 바(단순한 막대)는 그 띠 안에 든다.
## 보스가 쓰러지면 막대만 사라지고 띠는 남아 있다가, 정화의 손길로 정화하면 띠가 천천히 내려가며 회상으로 이어진다.
## 중간 보스도 같은 띠와 막대를 쓴다. 아이패드(세로가 긴 화면)에서는 띠가 조금 더 두껍다(화면 높이의 12%).
## 등장 때 큰 이름이 떠올랐다 사라지는 것은 그대로.

## 띠 높이: 화면 높이의 이 비율 (1080 → 130px, 아이패드 1440 → 173px)
const BAND_RATIO := 0.12
## 막대 색 (기획자가 고른 예전 막대의 색)
const BAR_FILL := Color(0.48, 0.515, 0.40)
const BAR_TRAIL := Color(0.86, 0.80, 0.62)
const BAR_BACK := Color(0.06, 0.05, 0.04, 0.85)
const BAR_EDGE := Color(0.80, 0.76, 0.62, 0.75)
const POISE := Color(0.56, 0.83, 1.0)
## 터치 조작 중 막대 오른쪽 끝을 화면 오른쪽 가장자리에서 이만큼(버튼 크기 '보통' 기준 px) 안쪽에 둔다 — 가드 버튼과 그 누름 범위를 피한다
const TOUCH_CLEAR := 660.0
## 흙 색: 띠 위쪽 → 아래쪽
const SOIL_TOP := Color(0.21, 0.145, 0.095)
const SOIL_BOTTOM := Color(0.035, 0.022, 0.016)
const ROOT_DARK := Color(0.10, 0.065, 0.04)
const ROOT_LIGHT := Color(0.31, 0.22, 0.14)

var _boss: Node
var _canvas: Control
var _name := ""
var _subtitle := ""
var _hp := 1.0
var _hp_trail := 1.0
var _poise := 0.0
var _flash := 0.0
var _title := 0.0
var _t := 0.0
## 띠가 올라온 정도 0→1 과 목표, 그리고 오르내리는 빠르기(초당)
var _band := 0.0
var _band_target := 0.0
var _band_speed := 1.0 / 0.6
## 막대 보임 정도 0→1
var _bar := 0.0
var _bar_target := 0.0
## 뿌리·자갈 모양 (한 번 만들어 재사용; 띠 너비 기준 0~1 좌표)
var _roots: Array = []
var _pebbles: Array = []
var _rim: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	layer = 16
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	_make_soil_shapes()


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


## 싸움 시작: 띠가 0.6초에 올라오고 막대가 켜진다. 큰 이름이 떠오른다.
func show_boss() -> void:
	_title = 3.0
	_band_target = 1.0
	_band_speed = 1.0 / 0.6
	_bar_target = 1.0


## 싸움이 끝나거나 다시 시작할 때(쓰러져서 되돌릴 때, 중간 보스 처치): 막대와 띠가 함께 내려간다.
func hide_boss(duration := 0.5) -> void:
	_bar_target = 0.0
	_band_target = 0.0
	_band_speed = 1.0 / maxf(duration, 0.05)


## 보스가 쓰러졌다: 막대만 사라지고 띠는 남는다 (정화의 손길을 기다린다).
func hide_bar() -> void:
	_bar_target = 0.0


## 정화했다: 띠가 천천히 내려간다 (이어서 회상으로 넘어간다).
func lower_band(duration := 1.8) -> void:
	_bar_target = 0.0
	_band_target = 0.0
	_band_speed = 1.0 / maxf(duration, 0.05)


## 지금 띠가 가리는 화면 아래쪽 높이(px). 카메라가 바닥을 띠 위에 두는 데 쓴다.
func band_px() -> float:
	return _canvas.size.y * BAND_RATIO * _band


## 띠가 다 올라왔을 때의 높이(px).
func band_full_px() -> float:
	return _canvas.size.y * BAND_RATIO


func is_band_up() -> bool:
	return _band_target > 0.5


func _process(delta: float) -> void:
	_t += delta
	_band = move_toward(_band, _band_target, delta * _band_speed)
	_bar = move_toward(_bar, _bar_target, delta * 2.5)
	_title = maxf(_title - delta, 0.0)
	_flash = maxf(_flash - delta, 0.0)
	_hp_trail = move_toward(_hp_trail, _hp, delta * (0.35 if _hp < _hp_trail else 3.0))
	if _band > 0.0 or _bar > 0.0 or _title > 0.0:
		_canvas.queue_redraw()
	elif _canvas.is_visible_in_tree():
		_canvas.queue_redraw()   # 마지막 한 번 지우기


## 뿌리·자갈·윗선 모양을 만든다 (좌표는 띠 너비·높이 기준 0~1).
func _make_soil_shapes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261018
	_roots.clear()
	for i in 9:
		var pts := PackedVector2Array()
		var x := rng.randf_range(0.02, 0.98)
		var y := rng.randf_range(-0.02, 0.08)
		var drift := rng.randf_range(-0.06, 0.06)
		var n := rng.randi_range(7, 11)
		for k in n:
			pts.append(Vector2(x, y))
			x += drift * rng.randf_range(0.4, 1.4) + rng.randf_range(-0.025, 0.025)
			y += rng.randf_range(0.07, 0.16)
			drift = lerpf(drift, rng.randf_range(-0.08, 0.08), 0.5)
		_roots.append({"pts": pts, "w": rng.randf_range(4.0, 9.0), "shade": rng.randf_range(0.0, 1.0)})
	_pebbles.clear()
	for i in 40:
		_pebbles.append(Vector3(rng.randf(), rng.randf_range(0.15, 0.95), rng.randf_range(1.5, 4.0)))
	_rim = PackedFloat32Array()
	for i in 97:
		_rim.append(rng.randf_range(0.0, 1.0))


func _draw_band(rect: Rect2, a: float) -> void:
	var w := rect.size.x
	var h := rect.size.y
	# 흙: 위에서 아래로 어두워지는 띠 (가로 줄 여러 장)
	var strips := 14
	for i in strips:
		var t0 := float(i) / strips
		var t1 := float(i + 1) / strips
		var c := SOIL_TOP.lerp(SOIL_BOTTOM, pow(t0, 0.8))
		c.a = a * (0.55 + 0.45 * minf(t0 * 6.0, 1.0))   # 맨 위 줄은 살짝 비치게
		_canvas.draw_rect(Rect2(rect.position.x, rect.position.y + h * t0, w, h * (t1 - t0) + 1.0), c)
	# 윗선: 울퉁불퉁한 흙 가장자리 (위로 살짝 솟은 혹들)
	var rim := PackedVector2Array()
	var n := _rim.size()
	rim.append(Vector2(rect.position.x, rect.position.y + 2.0))
	for i in n:
		var x := rect.position.x + w * float(i) / (n - 1)
		var bump := (_rim[i] * 7.0 + 2.0 * sin(float(i) * 1.7)) * (0.6 + 0.4 * a)
		rim.append(Vector2(x, rect.position.y - bump))
	rim.append(Vector2(rect.end.x, rect.position.y + 2.0))
	rim.append(Vector2(rect.end.x, rect.position.y + 12.0))
	rim.append(Vector2(rect.position.x, rect.position.y + 12.0))
	_canvas.draw_colored_polygon(rim, Color(SOIL_TOP.lightened(0.08), 0.9 * a))
	# 뿌리: 위에서 아래로 가늘어지며 내려간다 (어두운 심 + 밝은 가장자리)
	for r in _roots:
		var pts: PackedVector2Array = r["pts"]
		var scaled := PackedVector2Array()
		for p in pts:
			scaled.append(Vector2(rect.position.x + p.x * w, rect.position.y + p.y * h))
		var wmax: float = r["w"]
		var shade: float = r["shade"]
		var light := ROOT_LIGHT.lerp(ROOT_DARK, shade * 0.5)
		for k in scaled.size() - 1:
			var tk := float(k) / maxf(scaled.size() - 2, 1)
			var wk := lerpf(wmax, 1.2, tk)
			var fade := a * (1.0 - 0.55 * tk)
			_canvas.draw_line(scaled[k], scaled[k + 1], Color(light, fade), wk, true)
			_canvas.draw_line(scaled[k], scaled[k + 1], Color(ROOT_DARK, fade), maxf(wk * 0.45, 0.8), true)
	# 자갈
	for p in _pebbles:
		var c := SOIL_TOP.lerp(SOIL_BOTTOM, p.y)
		_canvas.draw_circle(Vector2(rect.position.x + p.x * w, rect.position.y + p.y * h), p.z, Color(c.lightened(0.12), 0.8 * a))


func _draw_bar(band: Rect2, a: float) -> void:
	var font := ThemeDB.fallback_font
	var size := _canvas.size
	var bar_w := minf(900.0, size.x * 0.47)
	var bar_h := 18.0
	# 터치 조작 중에는 오른쪽 아래 버튼 무리(가드 버튼 왼쪽 끝 ≈ 오른쪽 가장자리 −636)와 겹치지 않게,
	# 막대 오른쪽 끝이 가장자리 −660 안에 들어올 만큼만 왼쪽으로 민다 (넓은 화면에선 안 밀어도 된다).
	# 버튼은 오른쪽 아래 모서리 기준으로 '터치 버튼 크기'만큼 벌어지므로 비우는 폭도 같이 키운다
	# (2026-10-20 QA: 아이패드 4:3 + 크게 에서 가드 버튼이 막대 오른쪽 끝을 덮었다)
	var x := (size.x - bar_w) / 2.0
	if InputDevice.current == InputDevice.Kind.TOUCH:
		x -= maxf(0.0, x + bar_w - (size.x - TOUCH_CLEAR * Settings.touch_scale_factor()))
	var y := band.position.y + band.size.y * 0.52
	# 이름 (막대 왼쪽 위, 사진처럼 작은 글씨)
	_canvas.draw_string_outline(font, Vector2(x, y - 10.0), _name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.7 * a))
	_canvas.draw_string(font, Vector2(x, y - 10.0), _name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.93, 0.90, 0.78, a))
	# 막대: 바탕 → 잔상 → 채움 → 테두리
	var rect := Rect2(x, y, bar_w, bar_h)
	_canvas.draw_rect(rect.grow(2.0), Color(BAR_BACK, BAR_BACK.a * a))
	if _hp_trail > _hp:
		_canvas.draw_rect(Rect2(x, y, bar_w * _hp_trail, bar_h), Color(BAR_TRAIL, 0.85 * a))
	if _hp > 0.001:
		_canvas.draw_rect(Rect2(x, y, bar_w * _hp, bar_h), Color(BAR_FILL, a))
	if _flash > 0.0:
		_canvas.draw_rect(rect, Color(1, 0.95, 0.8, 0.55 * _flash * a))
	_canvas.draw_rect(rect, Color(BAR_EDGE, BAR_EDGE.a * a), false, 1.5)
	# 흐트러짐: 막대 아래 가는 은청색 선
	var py := y + bar_h + 6.0
	_canvas.draw_rect(Rect2(x, py, bar_w * 0.7, 4.0), Color(0.08, 0.1, 0.14, 0.85 * a))
	_canvas.draw_rect(Rect2(x, py, bar_w * 0.7 * _poise, 4.0), Color(POISE, a))
	if _poise >= 0.999:
		_canvas.draw_rect(Rect2(x, py, bar_w * 0.7, 4.0), Color(1, 1, 1, (0.5 + 0.5 * sin(_t * 8.0)) * 0.6 * a))


func _on_draw() -> void:
	var size := _canvas.size
	if _band > 0.001:
		var bh := band_full_px() * smoothstep(0.0, 1.0, _band)
		var band := Rect2(0.0, size.y - bh, size.x, bh)
		_draw_band(band, 1.0)
		if _bar > 0.01:
			_draw_bar(band, _bar)
	if _title > 0.0:
		var font := ThemeDB.fallback_font
		var t := clampf(_title / 0.6, 0.0, 1.0) if _title < 0.6 else clampf((3.0 - _title) / 0.6, 0.0, 1.0)
		var ty := title_y()
		_canvas.draw_string_outline(font, Vector2(size.x / 2.0 - 600, ty), _name, HORIZONTAL_ALIGNMENT_CENTER, 1200, 72, 8, Color(0, 0, 0, 0.6 * t))
		_canvas.draw_string(font, Vector2(size.x / 2.0 - 600, ty), _name, HORIZONTAL_ALIGNMENT_CENTER, 1200, 72, Color(0.95, 0.9, 0.8, t))
		_canvas.draw_string(font, Vector2(size.x / 2.0 - 600, ty + 44), _subtitle, HORIZONTAL_ALIGNMENT_CENTER, 1200, 24, Color(0.8, 0.8, 0.8, t * 0.8))


## 등장 이름의 글자 기준선 높이 (화면 px). 보통은 화면 높이 0.22. 소녀 HUD(이슬·성장·빛 가루 줄)가 길어져
## 이름 자리까지 뻗으면 HUD 아래로 내린다 (2026-10-19 검수: 이슬 9개·성장 아이콘에서 이름이 빛 가루 숫자를 가렸다).
func title_y() -> float:
	var size := _canvas.size if _canvas else Vector2(1920, 1080)
	var y := size.y * 0.22
	var hud := get_parent().get_node_or_null("CombatHUD") if get_parent() else null
	if hud == null or not hud.has_method("hud_right_x") or hud.get("_player") == null:
		return y
	var font := ThemeDB.fallback_font
	var w := maxf(font.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 72).x, font.get_string_size(_subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x)
	var left := size.x / 2.0 - w / 2.0
	# 이름 글자(기준선 위 ~62px)부터 부제(기준선 아래 ~52px)까지의 높이에 걸친 HUD 만 본다
	if float(hud.hud_right_x(y - 62.0, y + 52.0)) + 24.0 > left:
		y = maxf(y, float(hud.hud_bottom_y()) + 72.0)
	return y

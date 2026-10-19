extends Control
class_name EndingScene
## 엔딩 (ENDINGS.md). 세 엔딩 모두 같은 틀: 장면들을 한 줄씩 보여 주고 → 정해진 장면에서 셀레니아의 허밍(selenia_humming)이
## 처음부터 한 번 흐르기 시작해 → 크레딧(엔딩·회상 그림 위로 제작진이 올라감)까지 끊기지 않고 이어지고 →
## 마지막 그림은 그 엔딩의 '클리어 후 타이틀 그림' + 엔딩 이름 + "끝" + 메뉴(이어서 탐험하기 / 타이틀로).
## 장면·대사·그림·연출은 모두 data/dialogue/endings.json (+ endings_mine.json — 제3의 길). 형식은 그 파일의 "_형식".
## 허밍 전 장면은 음악 없이 효과음만 (뿌리의 울림·잎 소리·등불 꺼지는 소리·펌프 소리 — tools/gen_sfx_endings.gd).
## 엔딩으로 가는 조건과 고르는 방식은 EndingChoice(심연의 끝)가 정한다 — 여기서는 Progress.ending 을 읽기만 한다.
## 엔딩 뒤: 깃발 cleared · ending_<이름> · last_ending_<이름>(마지막으로 본 엔딩 하나만)을 세우고 저장 → 타이틀 그림·곡,
## 마을 사람들의 엔딩 뒤 대사(npcs_endings.json), 마을의 밤빛(PostEnding)이 이 깃발을 따른다.

const DATA_PATH := "res://data/dialogue/endings.json"
## 엔딩 이름들 (깃발 last_ending_<이름> 은 이 가운데 하나만 선다)
const ENDINGS := ["sacrifice", "return", "third"]
const FADE := 1.3                # 그림이 바뀌는 시간
const READ_MIN := 0.8            # 한 줄이 뜬 뒤 이 시간 안의 누름은 무시한다 (연타로 못 읽고 넘어가지 않게)
const CREDITS_MIN := 40.0        # 크레딧 최소 길이 (초)
const CREDITS_MAX := 150.0       # 〃 최대
const END_TAIL := 7.0            # 크레딧이 끝난 뒤 '끝' 화면에서 허밍의 마지막 소리가 흐르는 시간 — 크레딧은 허밍이 이만큼 남았을 때 끝나게 맞춘다
## selenia_humming 의 박 (tools/measure_tempo.gd 로 잼: 124.5bpm, 첫 박 0.122초). 진엔딩의 펌프 소리를 이 박에 맞춘다.
const HUM_BEAT := 60.0 / 124.5
const HUM_DOWNBEAT := 0.122
## 마지막 달빛풀이 없을 때 '이어서 탐험하기'가 가는 곳
const EXPLORE_FALLBACK := {"id": "moon_garden", "scene": "res://scenes/rooms/moon_garden.tscn", "name": "달빛 정원"}

## 시험용 빠르기 (1 = 보통). probe_endings 가 크게 두어 엔딩을 몇 초 만에 돌린다.
var time_scale := 1.0
## 시험용 기록: [{"kind": "scene" | "beat" | "music" | "effect" | "credits" | "credit_image" | "end" | "choose", ...}]
var events: Array = []
## 지금 보이는 엔딩 이름 (sacrifice / return / third)
var which := ""
## 진행 단계: scenes → credits → end → leaving
var phase := "scenes"
## 허밍이 시작된 장면 번호 (0부터), 아직이면 -1
var humming_scene_index := -1

@onready var art: TextureRect = $Art
@onready var subtitle: Label = $Subtitle
@onready var title: Label = $Title
@onready var credits: Label = $Credits

var _data: Dictionary = {}
var _common: Dictionary = {}
var _scenes: Array = []
var _scene_i := -1
var _beat_i := -1
var _beat_t := 0.0            # 지금 줄이 뜬 뒤 흐른 시간 (빠르기 반영)
var _beat_real := 0.0         # 〃 실제 시간 (읽을 틈 판단용)
var _beat_len := 5.0
var _token := 0               # 장면이 바뀔 때마다 늘어난다 — 늦게 도착한 예약 동작이 다른 장면을 건드리지 않게
var _humming_from := -1       # 허밍을 시작할 장면 번호 (0부터)

# 그림 두 겹 (번갈아 겹쳐 부드럽게 바꾼다). 겹치기는 modulate.a, 밝기·색조는 self_modulate.
var _layers_art: Array = []   # [{rect, view_from, view_to, t, len, tint}]
var _front := 0
var _sprite_root: Control
var _sprites := {}            # id → {rect, glow, x, y, h}
var _fx_root: Control
var _fx_canvas: Control
var _overlay: TextureRect     # 왼쪽부터 번지는 어둠
var _flash: ColorRect
var _blur: ColorRect
var _place: Label
var _speaker: Label
var _echo: Label
var _roll: Label
var _end_box: VBoxContainer
var _end_items: Array[Button] = []
var _end_index := 0
var _radial: GradientTexture2D
var _add_mat: CanvasItemMaterial
var _ash_shader: Shader

# 연출 상태
var _glows: Array = []        # [{node, id, at, radius, color, alpha, alpha_to, t, time, pulse}]
var _seed := {}
var _spin := {}
var _ash := {}
var _pump := {}
var _scripture := {}
var _spin_drawn := false
var _time := 0.0
# 같은 대상을 건드리는 앞선 트윈은 새 트윈을 걸 때 멈춘다 (건너뛰기를 연타해도 옛 트윈이 새 화면을 덮어쓰지 않게)
var _line_tw: Tween
var _blur_tw: Tween
var _flash_tw: Tween
var _place_tw: Tween
var _overlay_tw: Tween

# 크레딧
var _credits_t := 0.0
var _credits_len := CREDITS_MIN
var _credit_images: Array = []
var _credit_next := 0


func _ready() -> void:
	_build()
	_data = DialogueData.load_dialogue(DATA_PATH)
	_common = _data.get("_공통", {})
	which = Progress.ending if Progress.ending in ENDINGS else "return"
	var e: Dictionary = _data.get(which, {})
	_scenes = e.get("scenes", [])
	_humming_from = clampi(int(e.get("humming_scene", 1)) - 1, 0, maxi(_scenes.size() - 1, 0))
	title.text = e.get("title", "")
	title.modulate.a = 0.0
	subtitle.modulate.a = 0.0
	credits.visible = false
	mark_seen(which)
	# 엔딩 뒤에도 이어서 탐험할 수 있게 진행을 저장한다 (타이틀 → 이어하기 → 마지막 달빛풀; EXPANSION.md 7장 "엔딩 후").
	# 아직 달빛풀에서 쉰 적이 없으면(이어질 곳이 없음) 저장하지 않는다.
	if str(Progress.last_grass.get("scene", "")) != "":
		SaveGame.save_now()
	Game.fade_in(1.5 / time_scale)
	# 허밍 전 장면은 음악 없이 (선택지 방의 들판 곡을 조용히 거둔다)
	Music.stop(2.0 / time_scale)
	_start_scene(0)
	if "--screenshot" in OS.get_cmdline_user_args():
		await get_tree().create_timer(12.0).timeout
		get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://screenshots/debug_ending.png"))
		get_tree().quit()


## 엔딩을 보았다는 표시 (깃발). 마지막으로 본 엔딩 깃발(last_ending_*)은 하나만 남긴다. 시험도 부른다.
static func mark_seen(name: String) -> void:
	Progress.set_flag("cleared")
	Progress.set_flag("ending_" + name)
	if name == "third":
		Progress.set_flag("cleared_third")   # 확장판 · 제3의 길
	for n in ENDINGS:
		if n != name and Progress.has("last_ending_" + n):
			Progress.set_flag("last_ending_" + n, false)
	Progress.set_flag("last_ending_" + name)


## 엔딩 곡: 세 엔딩 모두 셀레니아의 허밍 selenia_humming (ENDINGS.md 0장 — 주제곡 엔딩 버전·E♭장조 버전은 엔딩에 쓰지 않는다).
static func ending_track(_which: String) -> String:
	return Music.ENDING_TRACK


## 엔딩 데이터 한 개 (시험·타이틀이 읽는다)
static func ending_data(name: String) -> Dictionary:
	return DialogueData.load_dialogue(DATA_PATH).get(name, {})


# ---------- 화면 만들기 ----------

func _build() -> void:
	_radial = GradientTexture2D.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])
	_radial.gradient = g
	_radial.width = 128
	_radial.height = 128
	_radial.fill = GradientTexture2D.FILL_RADIAL
	_radial.fill_from = Vector2(0.5, 0.5)
	_radial.fill_to = Vector2(1.0, 0.5)
	_add_mat = CanvasItemMaterial.new()
	_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_ash_shader = load("res://shaders/ash_purify.gdshader")
	# 그림 두 겹: tscn 의 Art 를 첫 겹으로 쓰고, 한 겹을 더 만든다
	var art_b := TextureRect.new()
	art_b.name = "ArtB"
	add_child(art_b)
	move_child(art_b, art.get_index())
	for r: TextureRect in [art, art_b]:
		r.set_anchors_preset(Control.PRESET_TOP_LEFT)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.modulate = Color(1, 1, 1, 0)
		r.pivot_offset = Vector2.ZERO
		_layers_art.append({"rect": r, "view_from": Vector3(0.5, 0.5, 1.0), "view_to": Vector3(0.5, 0.5, 1.0), "t": 0.0, "len": 1.0, "tint": Color.WHITE})
	var vignette := get_node("Vignette")
	_sprite_root = _full_control("Sprites")
	move_child(_sprite_root, vignette.get_index())
	_fx_root = _full_control("Fx")
	move_child(_fx_root, vignette.get_index())
	var fc := FxCanvas.new()
	fc.name = "FxCanvas"
	fc.set_anchors_preset(Control.PRESET_FULL_RECT)
	fc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fc.draw_cb = _draw_fx
	_fx_canvas = fc
	add_child(fc)
	move_child(fc, vignette.get_index())
	# 화면 전체 덮개들 (비네트 위, 글자 아래)
	_overlay = TextureRect.new()
	_overlay.name = "Sweep"
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.0, 0.45, 0.55, 1.0])
	sg.colors = PackedColorArray([Color(0, 0, 0.02, 1), Color(0, 0, 0.02, 1), Color(0, 0, 0.02, 0), Color(0, 0, 0.02, 0)])
	var st := GradientTexture2D.new()
	st.gradient = sg
	st.width = 256
	st.height = 4
	_overlay.texture = st
	_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	add_child(_overlay)
	move_child(_overlay, vignette.get_index() + 1)
	_flash = ColorRect.new()
	_flash.name = "Flash"
	_flash.color = Color(1, 0.97, 0.9, 0)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	move_child(_flash, _overlay.get_index() + 1)
	_blur = ColorRect.new()
	_blur.name = "Blur"
	_blur.color = Color(0, 0, 0, 0)
	_blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_blur)
	move_child(_blur, _flash.get_index() + 1)
	# 글자들
	_place = _label("Place", 28, Color(0.92, 0.9, 0.84, 0.9))
	_place.position = Vector2(90, 70)
	_speaker = _label("Speaker", 26, Color(1.0, 0.86, 0.55))
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_speaker.offset_left = -600
	_speaker.offset_right = 600
	_speaker.offset_top = -300
	_speaker.offset_bottom = -262
	_echo = _label("Echo", 22, Color(1.0, 0.86, 0.55, 0.8))
	_echo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_echo.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_echo.offset_left = -600
	_echo.offset_right = 600
	_echo.offset_top = -96
	_echo.offset_bottom = -64
	_roll = _label("Roll", 30, Color(0.93, 0.9, 0.84))
	_roll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_roll.add_theme_constant_override("line_spacing", 10)
	_roll.visible = false
	for l: Label in [subtitle, _speaker, _echo, _place, _roll, title]:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 8)
	resized.connect(_on_resized)


func _full_control(n: String) -> Control:
	var c := Control.new()
	c.name = n
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _label(n: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.name = n
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.modulate.a = 0.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _vp() -> Vector2:
	return size if size.x > 0.0 else get_viewport_rect().size


func _on_resized() -> void:
	for s in _sprites.values():
		_place_sprite(s)


# ---------- 장면 · 줄 ----------

func _start_scene(i: int) -> void:
	_token += 1
	_scene_i = i
	if i >= _scenes.size():
		_start_credits()
		return
	var sc: Dictionary = _scenes[i]
	_clear_fx()
	_clear_sprites()
	# 앞 장면의 장소 글자(4.4초 연출)가 새 장면 그림 위에 남지 않게 빠르게 거둔다 (2026-10-20 QA: 마을 그림 위에 '수관'이 떴다)
	_kill(_place_tw)
	if _place.modulate.a > 0.0:
		_place_tw = create_tween()
		_place_tw.tween_property(_place, "modulate:a", 0.0, 0.25 / time_scale)
	events.append({"kind": "scene", "index": i, "id": sc.get("id", ""), "name": sc.get("name", ""), "image": sc.get("image", ""),
		"music": Music.current(), "music_pos": Music.playback_time(Music.ENDING_TRACK)})
	# 허밍: 정해진 장면이 시작되는 순간 처음부터, 한 번만 (반복 없이) — 크레딧이 끝날 때까지 다시 틀지 않는다
	if i == _humming_from and humming_scene_index < 0:
		humming_scene_index = i
		Music.play(Music.ENDING_TRACK, {"fade": 2.5 / time_scale, "from": 0.0, "loop": false})
		events.append({"kind": "music", "index": i, "track": Music.ENDING_TRACK})
	var view := _vec3(sc.get("view", [0.5, 0.5, 1.0]))
	_show_image(str(sc.get("image", "")), view, _vec3(sc.get("view_to", sc.get("view", [0.5, 0.5, 1.0]))),
		_scene_len(sc), float(sc.get("bright", 1.0)), _color3(sc.get("tint", [1, 1, 1])), i == 0)
	if sc.has("bright_to"):
		_tween_bright(float(sc["bright_to"]), _scene_len(sc))
	for l in sc.get("layers", []):
		_add_sprite(l)
	for f in sc.get("effects", []):
		_add_effect(f)
	_play_sfx(sc.get("sfx", []))
	_beat_i = -1
	_next_beat()


func _next_beat() -> void:
	if _scene_i < 0 or _scene_i >= _scenes.size():
		return
	var beats: Array = _scenes[_scene_i].get("beats", [])
	_beat_i += 1
	if _beat_i >= beats.size():
		_start_scene(_scene_i + 1)
		return
	var b: Dictionary = beats[_beat_i]
	_beat_t = 0.0
	_beat_real = 0.0
	_beat_len = beat_length(b)
	var text := str(b.get("text", ""))
	var echo_shown := str(b.get("echo", "")) if Npc.condition_ok(str(b.get("echo_when", ""))) else ""
	events.append({"kind": "beat", "scene": _scene_i, "index": _beat_i, "text": text, "speaker": str(b.get("speaker", "")),
		"theme": bool(b.get("theme", false)), "image": str(b.get("image", "")), "echo": echo_shown})
	# 그 줄에서 바뀌는 그림·연출
	if b.has("image"):
		_clear_glows()
		_show_image(str(b["image"]), _vec3(b.get("view", [0.5, 0.5, 1.04])), _vec3(b.get("view_to", b.get("view", [0.5, 0.5, 1.04]))),
			_beat_len + FADE, float(b.get("bright", 1.0)), _color3(b.get("tint", [1, 1, 1])), false)
	else:
		if b.has("view"):
			_retarget_view(_vec3(b["view"]), _beat_len)
		if b.has("bright"):
			_tween_bright(float(b["bright"]), 1.6)
	for l in b.get("layers", []):
		_add_sprite(l)
	for f in b.get("effects", []):
		_add_effect(f)
	if b.has("move"):
		_move_sprite(b["move"])
	if b.has("swap"):
		_swap_sprite(b["swap"])
	if b.has("place"):
		_show_place(str(b["place"]))
	_play_sfx(b.get("sfx", []))
	_show_line(b)


## 한 줄이 떠 있는 시간: 주어진 time, 없으면 글자 수로 (읽는 빠르기 약 8.5자/초 + 여유). 빈 줄은 3초.
static func beat_length(b: Dictionary) -> float:
	if b.has("time"):
		return float(b["time"])
	var n := str(b.get("text", "")).length()
	if n == 0:
		return 3.0
	return clampf(2.8 + n / 8.5, 4.0, 9.5)


func _scene_len(sc: Dictionary) -> float:
	var total := 0.0
	for b in sc.get("beats", []):
		total += beat_length(b)
	return maxf(total, 1.0)


func _show_line(b: Dictionary) -> void:
	var text := str(b.get("text", ""))
	var speaker := str(b.get("speaker", ""))
	var theme := bool(b.get("theme", false))
	var voice := speaker == "세계수의 목소리"
	var echo := str(b.get("echo", ""))
	if echo != "" and not Npc.condition_ok(str(b.get("echo_when", ""))):
		echo = ""
	_kill(_line_tw)
	var tw := create_tween()
	_line_tw = tw
	tw.tween_property(subtitle, "modulate:a", 0.0, 0.4 / time_scale)
	tw.parallel().tween_property(_speaker, "modulate:a", 0.0, 0.4 / time_scale)
	tw.parallel().tween_property(_echo, "modulate:a", 0.0, 0.4 / time_scale)
	var tok := _token
	var bi := _beat_i
	tw.tween_callback(func() -> void:
		if tok != _token or bi != _beat_i:
			return
		subtitle.text = text
		_speaker.text = speaker
		_echo.text = echo
		subtitle.add_theme_font_size_override("font_size", 40 if theme else 32)
		var col := Color(0.96, 0.95, 0.9)
		if theme:
			col = Color(1.0, 0.9, 0.7)
		elif voice:
			col = Color(1.0, 0.9, 0.68)
		subtitle.add_theme_color_override("font_color", col)
		_speaker.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55) if voice else Color(0.78, 0.88, 1.0)))
	if text != "":
		tw.tween_property(subtitle, "modulate:a", 1.0, 1.1 / time_scale)
		if speaker != "":
			tw.parallel().tween_property(_speaker, "modulate:a", 1.0, 1.1 / time_scale)
		if echo != "":
			tw.tween_property(_echo, "modulate:a", 1.0, 1.4 / time_scale).set_delay(0.6 / time_scale)


func _process(delta: float) -> void:
	_time += delta
	match phase:
		"scenes":
			_beat_t += delta * time_scale
			_beat_real += delta
			if _beat_t >= _beat_len:
				_next_beat()
		"credits":
			_credits_t += delta * time_scale
			_update_credits()
	_update_views(delta)
	_update_fx(delta)


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") \
		or (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	match phase:
		"scenes":
			if pressed and _beat_real >= READ_MIN:
				skip()
		"credits":
			if pressed and _credits_t >= 2.0:
				skip()
		"end":
			if _end_items.is_empty():
				return
			if event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
				_select_end((_end_index + 1) % _end_items.size())
				Sfx.play("blip", -6.0)
			elif event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
				_select_end((_end_index - 1 + _end_items.size()) % _end_items.size())
				Sfx.play("blip", -6.0)
			elif event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
				choose(str(_end_items[_end_index].get_meta("kind")))


## 다음 줄로 (크레딧 중이면 '끝' 화면으로). 시험도 부른다.
func skip() -> void:
	match phase:
		"scenes":
			_next_beat()
		"credits":
			_show_end()


# ---------- 그림 ----------

## 새 그림을 뒤 겹에 올려 앞 겹 위로 겹쳐 띄운다 (같은 그림이어도 겹쳐 바꿔서, 보는 자리가 부드럽게 넘어간다).
func _show_image(path: String, view: Vector3, view_to: Vector3, view_len: float, bright: float, tint: Color, from_black: bool) -> void:
	var tex: Texture2D = load(path) if path != "" and ResourceLoader.exists(path) else null
	var front_rect: TextureRect = _layers_art[_front]["rect"]
	var nxt := 1 - _front
	var L: Dictionary = _layers_art[nxt]
	var r: TextureRect = L["rect"]
	r.texture = tex
	r.material = null
	L["view_from"] = view
	L["view_to"] = view_to
	L["t"] = 0.0
	L["len"] = view_len
	L["tint"] = tint
	if r.get_index() < front_rect.get_index():
		move_child(r, front_rect.get_index())   # 새 겹을 앞 겹 바로 위로
	_apply_view(L)
	_kill(L.get("tw_a"))
	_kill(L.get("tw_b"))
	r.self_modulate = Color(bright * tint.r, bright * tint.g, bright * tint.b, 1.0)
	r.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(r, "modulate:a", 1.0, (2.5 if from_black else FADE) / time_scale)
	L["tw_a"] = tw
	if not from_black:
		var F: Dictionary = _layers_art[_front]
		_kill(F.get("tw_a"))
		var tw_out := create_tween()
		tw_out.tween_property(front_rect, "modulate:a", 0.0, FADE / time_scale)
		F["tw_a"] = tw_out
	_front = nxt


func _kill(t) -> void:
	if t is Tween and (t as Tween).is_valid():
		(t as Tween).kill()


## 앞 그림의 밝기를 바꾼다 (색조는 그대로).
func _tween_bright(b: float, time: float) -> void:
	var L: Dictionary = _layers_art[_front]
	var r: TextureRect = L["rect"]
	var t: Color = L["tint"]
	_kill(L.get("tw_b"))
	var tw := create_tween()
	tw.tween_property(r, "self_modulate", Color(b * t.r, b * t.g, b * t.b, 1.0), maxf(time, 0.05) / time_scale)
	L["tw_b"] = tw


func _retarget_view(v: Vector3, time: float) -> void:
	var L: Dictionary = _layers_art[_front]
	L["view_from"] = _current_view(L)
	L["view_to"] = v
	L["t"] = 0.0
	L["len"] = maxf(time, 0.5)


func _current_view(L: Dictionary) -> Vector3:
	var k := _ease(clampf(float(L["t"]) / maxf(float(L["len"]), 0.01), 0.0, 1.0))
	return (L["view_from"] as Vector3).lerp(L["view_to"], k)


static func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


func _update_views(delta: float) -> void:
	for L in _layers_art:
		L["t"] = float(L["t"]) + delta * time_scale
		_apply_view(L)


## 보기(그림의 가로·세로 비율 자리, 확대)를 그림 겹에 적용한다: 그 자리가 화면 가운데에 오도록, 그림이 화면을 늘 덮도록.
func _apply_view(L: Dictionary) -> void:
	var r: TextureRect = L["rect"]
	var vp := _vp()
	r.size = vp
	var v := _current_view(L)
	var z := maxf(v.z, 1.0)
	var p := _image_point(r.texture, vp, v.x, v.y)
	var pos := vp * 0.5 - p * z
	pos.x = clampf(pos.x, vp.x - vp.x * z, 0.0)
	pos.y = clampf(pos.y, vp.y - vp.y * z, 0.0)
	r.scale = Vector2(z, z)
	r.position = pos


## 그림의 (fx, fy) 비율 자리가 '덮기'로 늘인 TextureRect(크기 vp) 안에서 어디인가 (확대 전).
static func _image_point(tex: Texture2D, vp: Vector2, fx: float, fy: float) -> Vector2:
	if tex == null:
		return Vector2(fx * vp.x, fy * vp.y)
	var ts := tex.get_size()
	var s := maxf(vp.x / ts.x, vp.y / ts.y)
	var disp := ts * s
	var off := (vp - disp) * 0.5
	return off + Vector2(fx * disp.x, fy * disp.y)


## 지금 앞 그림의 (fx, fy) 자리가 화면 어디에 보이는가.
func art_point(fx: float, fy: float) -> Vector2:
	var r: TextureRect = _layers_art[_front]["rect"]
	return r.position + _image_point(r.texture, r.size, fx, fy) * r.scale


## 지금 앞 그림 (시험용)
func front_texture() -> Texture2D:
	return (_layers_art[_front]["rect"] as TextureRect).texture


func _front_scale() -> float:
	return (_layers_art[_front]["rect"] as TextureRect).scale.x


# ---------- 인물·물건 그림 (layers) ----------

func _add_sprite(l: Dictionary) -> void:
	var id := str(l.get("id", str(_sprites.size())))
	if _sprites.has(id):
		_remove_sprite(id)
	var path := str(l.get("tex", ""))
	if not ResourceLoader.exists(path):
		return
	var tex: Texture2D = load(path)
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.flip_h = bool(l.get("flip", false))
	r.self_modulate = _color3(l.get("mod", [1, 1, 1]))
	r.modulate.a = 0.0
	var s := {"rect": r, "x": float(l.get("x", 0.5)), "y": float(l.get("y", 0.95)), "h": float(l.get("h", 0.4)), "glow": null}
	if l.has("glow"):
		var g := _glow_rect(_color3(l["glow"]))
		g.modulate.a = 0.0
		_sprite_root.add_child(g)
		s["glow"] = g
		s["glow_alpha"] = float(l.get("glow_alpha", 0.55))
	_sprite_root.add_child(r)
	_sprites[id] = s
	_place_sprite(s)
	var tw := create_tween()
	tw.tween_property(r, "modulate:a", 1.0, 1.0 / time_scale)
	if s["glow"]:
		tw.parallel().tween_property(s["glow"], "modulate:a", float(s["glow_alpha"]), 1.4 / time_scale)


func _glow_rect(col: Color) -> TextureRect:
	var g := TextureRect.new()
	g.texture = _radial
	g.material = _add_mat
	g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	g.stretch_mode = TextureRect.STRETCH_SCALE
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.self_modulate = col
	return g


func _place_sprite(s: Dictionary) -> void:
	var r: TextureRect = s["rect"]
	if not is_instance_valid(r) or r.texture == null:
		return
	var vp := _vp()
	var tex := r.texture
	var hp: float = float(s["h"]) * vp.y
	var wp := hp * tex.get_width() / maxf(tex.get_height(), 1.0)
	r.size = Vector2(wp, hp)
	r.position = Vector2(float(s["x"]) * vp.x - wp * 0.5, float(s["y"]) * vp.y - hp)
	var g = s.get("glow")
	if g and is_instance_valid(g):
		var gr := maxf(wp, hp) * 1.25
		(g as TextureRect).size = Vector2(gr, gr)
		(g as TextureRect).position = r.position + r.size * 0.5 - Vector2(gr, gr) * 0.5


func _move_sprite(m: Dictionary) -> void:
	var s: Dictionary = _sprites.get(str(m.get("id", "")), {})
	if s.is_empty():
		return
	var to: Array = m.get("to", [s["x"], s["y"]])
	var from := Vector2(s["x"], s["y"])
	var dest := Vector2(float(to[0]), float(to[1]))
	var tw := create_tween()
	tw.tween_method(func(k: float) -> void:
		var p := from.lerp(dest, _ease(k))
		s["x"] = p.x
		s["y"] = p.y
		_place_sprite(s), 0.0, 1.0, float(m.get("time", 2.0)) / time_scale).set_delay(float(m.get("delay", 0.4)) / time_scale)


func _swap_sprite(m: Dictionary) -> void:
	var s: Dictionary = _sprites.get(str(m.get("id", "")), {})
	var path := str(m.get("tex", ""))
	if s.is_empty() or not ResourceLoader.exists(path):
		return
	var old: TextureRect = s["rect"]
	var r := old.duplicate() as TextureRect
	r.texture = load(path)
	r.modulate.a = 0.0
	_sprite_root.add_child(r)
	s["rect"] = r
	_place_sprite(s)
	var d := float(m.get("delay", 0.0)) / time_scale
	var t := float(m.get("time", 1.2)) / time_scale
	var tw := create_tween()
	tw.tween_property(r, "modulate:a", 1.0, t).set_delay(d)
	tw.parallel().tween_property(old, "modulate:a", 0.0, t).set_delay(d)
	if s.get("glow") and m.has("glow"):
		tw.parallel().tween_property(s["glow"], "modulate:a", float(m["glow"]), t).set_delay(d)
	tw.tween_callback(old.queue_free)


func _remove_sprite(id: String) -> void:
	var s: Dictionary = _sprites.get(id, {})
	for k in ["rect", "glow"]:
		var n = s.get(k)
		if n and is_instance_valid(n):
			n.queue_free()
	_sprites.erase(id)


func _clear_sprites() -> void:
	_sprites.clear()
	# 옛 장면의 그림(바뀌는 중이던 것 포함)은 천천히 걷는다
	for c in _sprite_root.get_children():
		if c is CanvasItem and not c.is_queued_for_deletion():
			var tw := create_tween()
			tw.tween_property(c, "modulate:a", 0.0, 0.8 / time_scale)
			tw.tween_callback(c.queue_free)


# ---------- 연출 ----------

func _add_effect(f: Dictionary) -> void:
	var tp := str(f.get("type", ""))
	match tp:
		"glow":
			_add_glow(f)
		"motes", "stars", "flow":
			_fx_root.add_child(_particles(tp, _color3(f.get("color", [1, 0.85, 0.5])), int(f.get("amount", 30))))
		"ash":
			_start_ash(f)
		"sweep":
			_start_sweep(f)
		"seed":
			_start_seed(f)
		"spin":
			_spin = {"at": _vec2(f.get("at", [0.5, 0.5])), "radius": float(f.get("radius", 0.2)), "t": 0.0}
		"flash":
			_kill(_flash_tw)
			_flash_tw = create_tween()
			_flash_tw.tween_property(_flash, "color:a", 0.85, 0.08 / time_scale).set_delay(float(f.get("delay", 0.0)) / time_scale)
			_flash_tw.tween_property(_flash, "color:a", 0.0, float(f.get("time", 0.8)) / time_scale)
		"blur":
			var a := _blur.color.a
			_blur.color = Color(1.0, 0.97, 0.9, a) if bool(f.get("white", false)) else Color(0, 0, 0, a)
			_kill(_blur_tw)
			_blur_tw = create_tween()
			_blur_tw.tween_property(_blur, "color:a", 1.0, float(f.get("time", 3.0)) / time_scale)
			_kill(_line_tw)
			_line_tw = create_tween()
			_line_tw.tween_property(subtitle, "modulate:a", 0.0, 1.0 / time_scale)
		"scripture":
			_start_scripture(f)
		"pump_beats":
			_pump = {"next": -1.0, "count": int(f.get("count", 8)), "every": int(f.get("every", 2)), "db": float(f.get("db", -18.0))}
	events.append({"kind": "effect", "scene": _scene_i, "type": tp})


func _add_glow(f: Dictionary) -> void:
	var id := str(f.get("id", ""))
	for g in _glows:
		if id != "" and g["id"] == id:
			# 같은 빛: 세기만 새로
			g["alpha"] = (g["node"] as TextureRect).modulate.a
			g["alpha_to"] = float(f.get("alpha_to", f.get("alpha", 0.4)))
			g["t"] = 0.0
			g["time"] = float(f.get("time", 1.5))
			if f.has("radius"):
				g["radius"] = float(f["radius"])
			return
	var col := _color3(f.get("color", [1, 0.85, 0.5]))
	var n := _glow_rect(col)
	var a0 := float(f.get("alpha", 0.4))
	n.modulate.a = a0
	_fx_root.add_child(n)
	_glows.append({"node": n, "id": id, "at": _vec2(f.get("at", [0.5, 0.5])), "radius": float(f.get("radius", 0.12)),
		"alpha": a0, "alpha_to": float(f.get("alpha_to", a0)), "t": 0.0, "time": float(f.get("time", 1.0)), "pulse": float(f.get("pulse", 0.0))})


func _particles(kind: String, col: Color, amount: int) -> CPUParticles2D:
	var vp := _vp()
	var p := CPUParticles2D.new()
	p.texture = _radial
	p.material = _add_mat
	p.amount = maxi(amount, 1)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color(col, 0.0), Color(col, 0.9), Color(col, 0.6), Color(col, 0.0)])
	p.color_ramp = ramp
	match kind:
		"motes":
			p.lifetime = 7.0
			p.preprocess = 4.0
			p.position = Vector2(vp.x * 0.5, vp.y + 30.0)
			p.emission_rect_extents = Vector2(vp.x * 0.55, 60.0)
			p.direction = Vector2(0, -1)
			p.spread = 18.0
			p.gravity = Vector2(0, -8)
			p.initial_velocity_min = 40.0
			p.initial_velocity_max = 110.0
			p.scale_amount_min = 0.06
			p.scale_amount_max = 0.2
		"stars":
			p.lifetime = 3.5
			p.preprocess = 3.0
			p.position = vp * 0.5
			p.emission_rect_extents = vp * 0.5
			p.gravity = Vector2.ZERO
			p.initial_velocity_min = 2.0
			p.initial_velocity_max = 10.0
			p.spread = 180.0
			p.scale_amount_min = 0.05
			p.scale_amount_max = 0.16
		"flow":
			p.lifetime = 2.6
			p.preprocess = 2.0
			p.position = Vector2(vp.x * 0.5, vp.y * 0.12)
			p.emission_rect_extents = Vector2(vp.x * 0.18, 30.0)
			p.direction = Vector2(0, 1)
			p.spread = 12.0
			p.gravity = Vector2(0, 260)
			p.initial_velocity_min = 120.0
			p.initial_velocity_max = 260.0
			p.scale_amount_min = 0.08
			p.scale_amount_max = 0.22
	p.speed_scale = clampf(time_scale, 1.0, 4.0)
	return p


func _start_ash(f: Dictionary) -> void:
	var L: Dictionary = _layers_art[_front]
	var mat := ShaderMaterial.new()
	mat.shader = _ash_shader
	mat.set_shader_parameter("ash_tint", Purity.ASH_TINTS.get(str(f.get("tint", "canopy")), Vector3(0.66, 0.70, 0.78)))
	mat.set_shader_parameter("purity", 0.0)
	mat.set_shader_parameter("radius", 0.0)
	mat.set_shader_parameter("center", _vec2(f.get("origin", [0.5, 1.1])))
	mat.set_shader_parameter("softness", 0.6 if bool(f.get("slow", false)) else 0.3)
	(L["rect"] as TextureRect).material = mat
	_ash = {"mat": mat, "t": 0.0, "time": float(f.get("time", 4.0)), "slow": bool(f.get("slow", false)), "hold": bool(f.get("hold", false))}


func _start_sweep(f: Dictionary) -> void:
	var vp := _vp()
	_overlay.visible = true
	_overlay.size = Vector2(vp.x * 2.0, vp.y)
	_overlay.position = Vector2(-vp.x * 1.1, 0)
	_overlay.modulate = Color(1, 1, 1, float(f.get("dark", 0.72)))
	var t := float(f.get("time", 6.0)) / time_scale
	_kill(_overlay_tw)
	_overlay_tw = create_tween()
	_overlay_tw.tween_property(_overlay, "position:x", vp.x * 0.15, t).set_trans(Tween.TRANS_SINE)
	# 등불이 하나씩 꺼지는 소리 (조금씩 불규칙하게)
	var clicks := int(f.get("clicks", 6))
	for i in clicks:
		var at := t * (0.08 + 0.84 * float(i) / maxf(clicks - 1, 1)) + randf_range(-0.12, 0.12) / time_scale
		get_tree().create_timer(maxf(at, 0.0)).timeout.connect(_sfx_later.bind(_token, "lamp_out", -9.0 - randf() * 5.0))


func _start_seed(f: Dictionary) -> void:
	var n := _glow_rect(Color(1.0, 0.85, 0.45))
	n.modulate.a = 0.0
	_fx_root.add_child(n)
	var core := _glow_rect(Color(1.0, 0.96, 0.78))
	core.modulate.a = 0.0
	_fx_root.add_child(core)
	_seed = {"node": n, "core": core, "from": _vec2(f.get("from", [0.5, 0.4])), "to": _vec2(f.get("to", [0.5, 0.9])), "t": 0.0, "time": float(f.get("time", 6.0))}
	Sfx.play("seed_fall", -16.0, 0.0)


func _start_scripture(f: Dictionary) -> void:
	# 낡은 종이 위의 한 줄: [앞 글][번영(그어 지울 글자)][생명(다시 적는 글자, 처음엔 안 보임)][뒷글]. 비네트 위에 올려 또렷하게.
	var vp := _vp()
	var panel := PanelContainer.new()
	panel.name = "Scripture"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.88, 0.76, 0.94)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(22)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 14
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var ink := Color(0.24, 0.17, 0.11)
	var parts := [str(f.get("before", "")), str(f.get("wrong", "")), str(f.get("right", "")), str(f.get("after", ""))]
	var labels: Array = []
	for i in 4:
		var l := Label.new()
		l.text = parts[i] if i != 2 else " " + parts[i]
		l.add_theme_font_size_override("font_size", 30)
		l.add_theme_color_override("font_color", ink if i != 2 else Color(0.62, 0.38, 0.05))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
		labels.append(l)
	(labels[2] as Label).visible = false   # '생명'은 다시 적을 때 나타난다
	# '번영' 위에 긋는 줄 (처음엔 길이 0)
	var strike := ColorRect.new()
	strike.color = Color(0.45, 0.12, 0.08, 0.9)
	strike.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strike.size = Vector2(0, 4)
	(labels[1] as Label).add_child(strike)
	panel.modulate.a = 0.0
	add_child(panel)
	move_child(panel, _blur.get_index())   # 비네트·어둠 덮개 위, 흐려짐 덮개 아래
	panel.reset_size()
	var at := _vec2(f.get("at", [0.72, 0.15]))
	var w := maxf(panel.size.x, 400.0)
	panel.position = Vector2(clampf(at.x * vp.x - w * 0.5, 40.0, vp.x - w - 40.0), at.y * vp.y)
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 1.0 / time_scale)
	_scripture = {"panel": panel, "labels": labels, "strike": strike, "parts": parts, "t": 0.0,
		"strike_at": float(f.get("strike_at", 2.5)), "write_at": float(f.get("write_at", 4.5)), "stage": 0}


## 경전 글자의 단계: 0 = 훼손된 글(번영), 1 = 번영에 줄을 그음, 2 = 그 곁에 생명을 다시 적음, -1 = 없음. 시험도 읽는다.
func scripture_stage() -> int:
	return int(_scripture.get("stage", -1))


## 경전 글자 그대로 — 보이는 글자만 (시험용)
func scripture_text() -> String:
	if _scripture.is_empty():
		return ""
	var out := ""
	for l in _scripture["labels"]:
		if (l as Label).visible:
			out += (l as Label).text
	return out


func _update_fx(delta: float) -> void:
	var dt := delta * time_scale
	var vp := _vp()
	var zs := _front_scale()
	for g in _glows:
		g["t"] = float(g["t"]) + dt
		var k := _ease(clampf(float(g["t"]) / maxf(float(g["time"]), 0.01), 0.0, 1.0))
		var a := lerpf(float(g["alpha"]), float(g["alpha_to"]), k)
		if float(g["pulse"]) > 0.0:
			a *= 1.0 + float(g["pulse"]) * sin(_time * 2.2 + float(g["radius"]) * 40.0)
		var n: TextureRect = g["node"]
		var rad: float = float(g["radius"]) * vp.y * 2.0 * zs
		n.size = Vector2(rad, rad)
		var at: Vector2 = g["at"]
		n.position = art_point(at.x, at.y) - n.size * 0.5
		n.modulate.a = clampf(a, 0.0, 1.0)
	if not _seed.is_empty():
		_seed["t"] = float(_seed["t"]) + dt
		var k2 := clampf(float(_seed["t"]) / maxf(float(_seed["time"]), 0.01), 0.0, 1.0)
		var fp: Vector2 = (_seed["from"] as Vector2).lerp(_seed["to"], k2 * k2 * 0.6 + k2 * 0.4)
		fp.x += sin(float(_seed["t"]) * 1.7) * 0.012 * (1.0 - k2 * 0.5)
		var sp := art_point(fp.x, fp.y)
		var alpha := clampf(float(_seed["t"]) / 0.8, 0.0, 1.0)
		var big := 120.0 * zs
		var node: TextureRect = _seed["node"]
		node.size = Vector2(big, big)
		node.position = sp - node.size * 0.5
		node.modulate.a = 0.55 * alpha * (0.85 + 0.15 * sin(_time * 5.0))
		var core: TextureRect = _seed["core"]
		core.size = Vector2(big, big) * 0.28
		core.position = sp - core.size * 0.5
		core.modulate.a = alpha
	if not _ash.is_empty() and not bool(_ash["hold"]):
		_ash["t"] = float(_ash["t"]) + dt
		var mat: ShaderMaterial = _ash["mat"]
		var k3 := clampf(float(_ash["t"]) / maxf(float(_ash["time"]), 0.01), 0.0, 1.0)
		if k3 >= 1.0:
			mat.set_shader_parameter("radius", 0.0)
			mat.set_shader_parameter("purity", 1.0)
		elif bool(_ash["slow"]):
			# 한 잎씩: 넓은 부드러운 경계로 천천히, 전체 정화 정도도 함께 오른다
			mat.set_shader_parameter("radius", lerpf(0.0, 1.6, k3))
			mat.set_shader_parameter("purity", clampf((k3 - 0.15) / 0.85, 0.0, 1.0) * 0.92)
		else:
			mat.set_shader_parameter("radius", lerpf(0.0, 2.4, _ease(k3)))
			mat.set_shader_parameter("purity", clampf((k3 - 0.7) / 0.3, 0.0, 1.0))
	if not _spin.is_empty():
		_spin["t"] = float(_spin["t"]) + dt
	if not _scripture.is_empty():
		_scripture["t"] = float(_scripture["t"]) + dt
		var stage := 0
		if float(_scripture["t"]) >= float(_scripture["write_at"]):
			stage = 2
		elif float(_scripture["t"]) >= float(_scripture["strike_at"]):
			stage = 1
		var labels: Array = _scripture["labels"]
		var wrong: Label = labels[1]
		var strike: ColorRect = _scripture["strike"]
		# 줄 긋기: strike_at 부터 0.8초 동안 왼쪽에서 오른쪽으로
		var sk := clampf((float(_scripture["t"]) - float(_scripture["strike_at"])) / 0.8, 0.0, 1.0)
		strike.size = Vector2(wrong.size.x * sk, 4)
		strike.position = Vector2(0, wrong.size.y * 0.52)
		if stage != int(_scripture["stage"]):
			_scripture["stage"] = stage
			if stage == 1:
				Sfx.play("swing", -20.0, 0.1)
				wrong.add_theme_color_override("font_color", Color(0.45, 0.38, 0.32))
			else:
				var right: Label = labels[2]
				right.visible = true
				right.modulate.a = 0.0
				var twr := create_tween()
				twr.tween_property(right, "modulate:a", 1.0, 1.2 / time_scale)
				Sfx.play("bloom", -16.0, 0.0)
	if not _pump.is_empty() and phase == "scenes" and int(_pump["count"]) > 0:
		var pt := Music.playback_time(Music.ENDING_TRACK)
		if pt >= 0.0:
			var step := HUM_BEAT * int(_pump["every"])
			if float(_pump["next"]) < 0.0:
				# 허밍이 들리기 시작한 뒤의 다음 박부터 (첫 박 0.122초에서 셈)
				_pump["next"] = HUM_DOWNBEAT + ceilf((maxf(pt, 1.0) - HUM_DOWNBEAT) / step) * step
			if pt >= float(_pump["next"]):
				# 고른 리듬 — 차츰 잦아든다 (허밍과 어긋나지 않게 낮게)
				Sfx.play("pump_clunk", float(_pump["db"]) - 0.8 * (8 - int(_pump["count"])), 0.0)
				_pump["count"] = int(_pump["count"]) - 1
				_pump["next"] = float(_pump["next"]) + step
	if not _spin.is_empty() or _spin_drawn:
		_fx_canvas.queue_redraw()
		_spin_drawn = not _spin.is_empty()


func _draw_fx(c: Control) -> void:
	if _spin.is_empty():
		return
	var t: float = _spin["t"]
	var k := clampf(t / 2.5, 0.0, 1.0)
	var at: Vector2 = _spin["at"]
	var center := art_point(at.x, at.y)
	var r: float = float(_spin["radius"]) * c.size.y * _front_scale()
	var ang := -t * (0.35 + 0.25 * k)   # 거꾸로 (시계 반대), 천천히
	for i in 3:
		var a0 := ang + i * TAU / 3.0
		c.draw_arc(center, r, a0, a0 + 1.3, 24, Color(1.0, 0.88, 0.6, 0.45 * k), 5.0, true)
		c.draw_arc(center, r * 1.12, a0 + 0.4, a0 + 1.1, 16, Color(1.0, 0.95, 0.8, 0.25 * k), 3.0, true)
		# 도는 쪽을 가리키는 화살촉 (호의 앞끝 = a0 쪽)
		var tip := center + Vector2(cos(a0), sin(a0)) * r
		var back := Vector2(-sin(a0), cos(a0))   # 호를 따라 각도가 커지는 쪽
		c.draw_line(tip, tip + back * 20.0 + Vector2(cos(a0), sin(a0)) * 9.0, Color(1.0, 0.9, 0.65, 0.5 * k), 4.0, true)
		c.draw_line(tip, tip + back * 20.0 - Vector2(cos(a0), sin(a0)) * 9.0, Color(1.0, 0.9, 0.65, 0.5 * k), 4.0, true)


func _clear_glows() -> void:
	for g in _glows:
		var n: TextureRect = g["node"]
		if is_instance_valid(n):
			var tw := create_tween()
			tw.tween_property(n, "modulate:a", 0.0, 0.8 / time_scale)
			tw.tween_callback(n.queue_free)
	_glows.clear()


func _clear_fx() -> void:
	_clear_glows()
	for c in _fx_root.get_children():
		if c.is_queued_for_deletion():
			continue
		if c is CPUParticles2D:
			(c as CPUParticles2D).emitting = false
			get_tree().create_timer(3.0 / time_scale).timeout.connect(c.queue_free)
		elif c is CanvasItem:
			var tw := create_tween()
			tw.tween_property(c, "modulate:a", 0.0, 0.6 / time_scale)
			tw.tween_callback(c.queue_free)
	if not _scripture.is_empty():
		var panel: Control = _scripture["panel"]
		if is_instance_valid(panel):
			var twp := create_tween()
			twp.tween_property(panel, "modulate:a", 0.0, 0.6 / time_scale)
			twp.tween_callback(panel.queue_free)
	_seed = {}
	_spin = {}
	_ash = {}
	_pump = {}
	_scripture = {}
	if _overlay.visible:
		_kill(_overlay_tw)
		_overlay_tw = create_tween()
		_overlay_tw.tween_property(_overlay, "modulate:a", 0.0, 1.0 / time_scale)
		_overlay_tw.tween_callback(func() -> void: _overlay.visible = false)
	_kill(_blur_tw)
	if _blur.color.a > 0.0:
		_blur_tw = create_tween()
		_blur_tw.tween_property(_blur, "color:a", 0.0, 1.5 / time_scale)


func _show_place(text: String) -> void:
	_place.text = text
	_kill(_place_tw)
	_place_tw = create_tween()
	_place_tw.tween_property(_place, "modulate:a", 1.0, 0.8 / time_scale)
	_place_tw.tween_interval(2.6 / time_scale)
	_place_tw.tween_property(_place, "modulate:a", 0.0, 1.0 / time_scale)


func _play_sfx(list: Array) -> void:
	var tok := _token
	for s in list:
		if not (s is Array) or s.is_empty():
			continue
		var name := str(s[0])
		var db := float(s[1]) if s.size() > 1 else 0.0
		var delay := float(s[2]) if s.size() > 2 else 0.0
		if delay <= 0.0:
			Sfx.play(name, db, 0.03)
		else:
			get_tree().create_timer(delay / time_scale).timeout.connect(_sfx_later.bind(tok, name, db))


## 예약한 효과음: 그사이 장면이 바뀌지 않았을 때만 (_token)
func _sfx_later(tok: int, name: String, db: float) -> void:
	if tok == _token and phase == "scenes":
		Sfx.play(name, db, 0.03)


# ---------- 크레딧 · 끝 ----------

func _start_credits() -> void:
	phase = "credits"
	_token += 1
	_clear_fx()
	_clear_sprites()
	var e: Dictionary = _data.get(which, {})
	_credit_images = e.get("credits_images", []).duplicate()
	_credit_next = 0
	# 허밍이 끝나기 END_TAIL 초 전에 크레딧이 끝나게 (허밍은 한 번만, 반복 없이 끝까지 흐른다)
	var remain := CREDITS_MIN
	var pt := Music.playback_time(Music.ENDING_TRACK)
	if pt >= 0.0:
		remain = Music.current_length() - pt - END_TAIL
	_credits_len = clampf(remain, CREDITS_MIN, CREDITS_MAX)
	_credits_t = 0.0
	events.append({"kind": "credits", "music": Music.current(), "music_pos": pt, "length": _credits_len})
	_kill(_line_tw)
	_kill(_place_tw)
	_line_tw = create_tween()
	_line_tw.tween_property(subtitle, "modulate:a", 0.0, 1.0 / time_scale)
	_line_tw.parallel().tween_property(_speaker, "modulate:a", 0.0, 1.0 / time_scale)
	_line_tw.parallel().tween_property(_echo, "modulate:a", 0.0, 1.0 / time_scale)
	_line_tw.parallel().tween_property(_place, "modulate:a", 0.0, 1.0 / time_scale)
	_line_tw.tween_callback(func() -> void:
		subtitle.text = ""
		_speaker.text = ""
		_echo.text = "")
	# 제작진 글
	var lines := PackedStringArray()
	for x in _common.get("credits", []):
		lines.append(str(x))
	_roll.text = "\n".join(lines)
	_roll.visible = true
	_roll.modulate.a = 1.0
	_update_credits()


func _update_credits() -> void:
	var vp := _vp()
	var k := clampf(_credits_t / maxf(_credits_len, 0.01), 0.0, 1.0)
	var h := _roll.get_minimum_size().y
	_roll.size = Vector2(1200, h)
	_roll.position = Vector2(vp.x * 0.5 - 600.0, lerpf(vp.y + 40.0, -h - 40.0, k))
	# 그림: 엔딩·회상 그림이 차례로 (어둡게, 천천히 다가감)
	var n := _credit_images.size()
	if n > 0 and _credit_next < n and int(k * n) >= _credit_next:
		var path := str(_credit_images[_credit_next])
		_credit_next += 1
		_show_image(path, Vector3(0.5, 0.5, 1.1), Vector3(0.5, 0.5, 1.0), _credits_len / n + FADE, 0.5, Color.WHITE, false)
		events.append({"kind": "credit_image", "path": path})
	if k >= 1.0:
		_show_end()


func _show_end() -> void:
	if phase == "end" or phase == "leaving":
		return
	phase = "end"
	_token += 1
	var e: Dictionary = _data.get(which, {})
	events.append({"kind": "end", "music": Music.current(), "music_pos": Music.playback_time(Music.ENDING_TRACK), "title_image": e.get("title_image", "")})
	var tw := create_tween()
	tw.tween_property(_roll, "modulate:a", 0.0, 1.2 / time_scale)
	_kill(_blur_tw)
	_blur_tw = create_tween()
	_blur_tw.tween_property(_blur, "color:a", 0.0, 1.2 / time_scale)
	# 그 엔딩의 클리어 후 타이틀 그림 (타이틀이 이렇게 바뀐다)
	_show_image(str(e.get("title_image", "")), Vector3(0.5, 0.5, 1.06), Vector3(0.5, 0.5, 1.0), 20.0, 1.0, Color.WHITE, false)
	# 엔딩 이름과 '끝' — 그림 오른쪽 제목 여백에
	var vp := _vp()
	var col_x := vp.x * 0.6
	var col_w := vp.x * 0.36
	title.set_anchors_preset(Control.PRESET_TOP_LEFT)
	title.size = Vector2(col_w, 70)
	title.position = Vector2(col_x, vp.y * 0.36)
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
	var end_label := Label.new()
	end_label.name = "EndLabel"
	end_label.text = str(_common.get("end_title", "— 끝 —"))
	end_label.add_theme_font_size_override("font_size", 28)
	end_label.add_theme_color_override("font_color", Color(0.92, 0.9, 0.84))
	end_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	end_label.add_theme_constant_override("outline_size", 8)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.size = Vector2(col_w, 44)
	end_label.position = Vector2(col_x, vp.y * 0.36 + 76)
	end_label.modulate.a = 0.0
	add_child(end_label)
	var tw2 := create_tween()
	tw2.tween_interval(1.4 / time_scale)
	tw2.tween_property(title, "modulate:a", 1.0, 1.6 / time_scale)
	tw2.tween_property(end_label, "modulate:a", 1.0, 1.2 / time_scale)
	tw2.tween_callback(_build_end_menu.bind(Vector2(col_x, vp.y * 0.36 + 150), col_w))


func _build_end_menu(at: Vector2, width: float) -> void:
	if phase != "end":
		return
	_end_box = VBoxContainer.new()
	_end_box.name = "EndMenu"
	_end_box.position = at
	_end_box.size = Vector2(width, 160)
	_end_box.add_theme_constant_override("separation", 14)
	_end_box.modulate.a = 0.0
	add_child(_end_box)
	_end_items.clear()
	var hint := str(_common.get("explore_hint", ""))
	for item in [["explore", str(_common.get("explore", "이어서 탐험하기"))], ["title", str(_common.get("to_title", "타이틀로"))]]:
		var b := Button.new()
		b.name = "End_" + str(item[0])
		b.flat = true
		b.text = str(item[1])
		b.set_meta("kind", item[0])
		b.add_theme_font_size_override("font_size", 30)
		b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		b.add_theme_constant_override("outline_size", 8)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: choose(str(b.get_meta("kind"))))
		b.mouse_entered.connect(func() -> void: _select_end(_end_items.find(b)))
		_end_box.add_child(b)
		_end_items.append(b)
		if item[0] == "explore" and hint != "":
			# 작은 안내: 마지막 달빛풀에서 다시 걷는다
			var hl := Label.new()
			hl.text = hint
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hl.add_theme_font_size_override("font_size", 20)
			hl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8, 0.7))
			hl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
			hl.add_theme_constant_override("outline_size", 6)
			hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_end_box.add_child(hl)
	_select_end(0)
	var tw := create_tween()
	tw.tween_property(_end_box, "modulate:a", 1.0, 0.8 / time_scale)


func _select_end(i: int) -> void:
	_end_index = clampi(i, 0, maxi(_end_items.size() - 1, 0))
	for j in _end_items.size():
		var b := _end_items[j]
		var on := j == _end_index
		b.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5) if on else Color(0.85, 0.85, 0.85, 0.75))
		b.add_theme_color_override("font_hover_color", Color(1.0, 0.86, 0.5))
		b.add_theme_color_override("font_pressed_color", Color(1.0, 0.86, 0.5))


## '끝' 화면의 메뉴가 떠 있는가 (시험용)
func end_menu_ready() -> bool:
	return phase == "end" and not _end_items.is_empty()


## '끝' 화면의 선택: "explore"(마지막 달빛풀에서 이어서 탐험) / "title"(타이틀로). 시험도 부른다.
## 허밍은 여기서 처음으로 거둔다 (크레딧까지는 끊지 않는다).
func choose(kind: String) -> void:
	if phase == "leaving":
		return
	phase = "leaving"
	Sfx.play("select")
	Music.stop(2.5 / time_scale)
	if kind == "explore":
		var target := explore_target()
		Progress.next_spawn = "Grass:" + str(target["id"])
		events.append({"kind": "choose", "what": kind, "scene": target["scene"], "spawn": Progress.next_spawn})
		Game.go_to(str(target["scene"]), 2.2 / time_scale, 1.4 / time_scale)
	else:
		events.append({"kind": "choose", "what": "title", "scene": Game.TITLE_SCENE})
		Game.go_to(Game.TITLE_SCENE, 2.2 / time_scale, 2.0 / time_scale)


## '이어서 탐험하기'가 가는 곳: 마지막으로 쉰 달빛풀 (없으면 달빛 정원). {"id", "scene", "name"}
static func explore_target() -> Dictionary:
	var g: Dictionary = Progress.last_grass
	var scene := str(g.get("scene", ""))
	var gid := str(g.get("id", ""))
	if scene == "" or gid == "" or not ResourceLoader.exists(scene):
		return EXPLORE_FALLBACK.duplicate()
	return {"id": gid, "scene": scene, "name": str(g.get("name", gid))}


# ---------- 작은 도우미 ----------

static func _vec3(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3(0.5, 0.5, 1.0)


static func _vec2(a) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2(0.5, 0.5)


static func _color3(a) -> Color:
	if a is Array and a.size() >= 3:
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return Color.WHITE


## 빛 고리처럼 코드로 그리는 연출을 맡는 판 (그리기는 EndingScene._draw_fx)
class FxCanvas extends Control:
	var draw_cb: Callable

	func _draw() -> void:
		if draw_cb.is_valid():
			draw_cb.call(self)

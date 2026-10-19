extends TravelMenu
class_name GrassMenu
## 달빛풀 메뉴 (2026-10-19 기획자 요청 9번): 쉬는 중에 손길 버튼을 한 번 더 누르면 열린다. 탭 두 개 —
##   [뿌리를 따라 이동]  이동 탭: TravelMenu 그대로 (피워 둔 달빛풀 목록)
##   [성장 ✦ N]          성장 탭: StatMenu 패널 (빛 가루로 최대 체력·공격력·회복량·이슬을 올린다)
## 좌·우(스틱·십자키·A/D), ◁ ▷(영혼 전환 버튼), 탭 머리 누르기로 탭을 바꾼다.
## 처음엔 이동 탭. 단, 갈 곳이 없으면(피운 달빛풀이 여기 하나뿐) 성장 탭으로 연다.
## 닫으면(회피 / 메뉴 / 바깥 누르기) 그대로 쉬기 계속: 닫은 버튼이 떨어질 때까지 소녀 입력을 잠가서
## 그 누름이 '쉬기 그만'(회피·점프)이나 '메뉴 다시 열기'(손길)로 읽히지 않게 한다.
## 성장을 사면 바로 저장한다 (앱이 꺼져도 산 성장이 남게). 안내 글자는 메뉴 안에만.
## TravelMenu 를 상속하므로 "is TravelMenu" 로 찾는 기존 시험(--grasstest)이 그대로 돈다.

const STAT_SCENE := preload("res://scenes/ui/stat_menu.tscn")
const GOLD := Color(1.0, 0.86, 0.5)
const TAB_W := 340.0
const TAB_H := 60.0
const TAB_GAP := 18.0
## 탭 머리를 손가락으로 누르는 자리는 그림보다 위아래로 이만큼 넓다 (아이폰에서 누르기 쉽게)
const TAB_TOUCH_PAD := 24.0
## 닫은 뒤 소녀 입력 잠금이 저절로 풀리는 시간(초) — 버튼을 계속 누르고 있어도 이 뒤엔 풀린다 (멈춰 버리지 않게)
const LOCK_MAX := 1.0
## 잠금이 풀리려면 모두 떨어져 있어야 하는 버튼 (쉬기를 끝내거나 메뉴를 다시 여는 버튼)
const LOCK_ACTIONS := ["jump", "dodge", "interact"]

var _tab := 0
var _stat: StatMenu
var _player: Player
var _stat_data := {}
## 스틱 좌·우(탭 바꾸기): 한 번 밀기 = 한 탭
var _stick_h := StickLatch.new()
## 닫은 뒤 입력을 잠가 둔 소녀 (null = 잠금 없음)
var _lock_player: Player
var _lock_time := 0.0


func _ready() -> void:
	super._ready()
	_stat = STAT_SCENE.instantiate()
	_stat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stat.top_ratio = 0.3
	_panel.add_child(_stat)
	_stat.purchased.connect(_on_purchased)
	Progress.dust_changed.connect(func(_n): if _open: _panel.queue_redraw())


## 달빛풀에서 연다 (쉬는 중). 이동 탭으로 시작한다 — 갈 다른 달빛풀이 없으면 성장 탭.
## 터치 버튼은 메뉴 위에 겹치지 않게 잠시 숨기고, 멈춘 채 남을 HUD 가운데 글자는 지운다.
func open_grass(grass_id: String) -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	_release_lock()
	_stat_data = StatMenu.load_data()
	_stick_h.reset()
	open(grass_id)
	_set_tab(1 if _items.size() <= 1 else 0)
	_show_touch(false)
	_clear_hud_text()


func close() -> void:
	_stat.close()
	super.close()
	_show_touch(true)
	_lock_input()


## 성장을 샀다: 다시 그리고 바로 저장한다 (쉬기 저장은 메뉴를 열기 전에 이미 끝났으므로).
func _on_purchased(_kind: String, _level: int, _cost: int) -> void:
	_panel.queue_redraw()
	if _current_id == "":
		return
	var scene_path := str(Progress.grasses.get(_current_id, {}).get("scene", ""))
	if scene_path == "" and get_tree().current_scene:
		scene_path = get_tree().current_scene.scene_file_path
	SaveGame.save(_current_id, scene_path)


# ---------- 닫은 뒤 입력 잠금 ----------

## 닫는 누름(회피·점프·손길)이 같은 틱에 소녀에게 '쉬기 그만'으로, 달빛풀에게 '메뉴 다시 열기'로 읽히지 않게
## 버튼이 떨어질 때까지 소녀 입력을 잠근다. (멈춤이 풀리는 바로 그 틱에 Input.is_action_just_pressed 가 참이라서)
func _lock_input() -> void:
	if _player == null or not is_instance_valid(_player) or not _player.input_enabled:
		return   # 다른 것이 이미 잠가 두었다 — 건드리지 않는다
	_lock_player = _player
	_lock_time = 0.0
	_player.input_enabled = false


func _release_lock() -> void:
	if _lock_player and is_instance_valid(_lock_player):
		_lock_player.input_enabled = true
	_lock_player = null


func is_input_locked() -> bool:
	return _lock_player != null and is_instance_valid(_lock_player)


func _lock_held() -> bool:
	for a in LOCK_ACTIONS:
		if Input.is_action_pressed(a):
			return true
	return absf(Input.get_axis("move_left", "move_right")) > 0.5


func _physics_process(delta: float) -> void:
	if _lock_player == null:
		return
	if not is_instance_valid(_lock_player):
		_lock_player = null
		return
	_lock_time += delta
	if _lock_time >= LOCK_MAX or not _lock_held():
		_release_lock()


func _exit_tree() -> void:
	_release_lock()


# ---------- 방의 다른 화면 ----------

## 방의 노드 하나 (TouchControls·CombatHUD). 방이 current_scene 이 아닌 시험 공간에서는 소녀의 부모(방)에서 찾는다.
func _room_node(node_name: String) -> Node:
	var n: Node = null
	var scene := get_tree().current_scene
	if scene:
		n = scene.get_node_or_null(node_name)
	if n == null and _player and is_instance_valid(_player) and _player.get_parent():
		n = _player.get_parent().get_node_or_null(node_name)
	return n


## 터치 버튼(방의 TouchControls)을 숨기거나 보인다.
func _show_touch(on: bool) -> void:
	var touch := _room_node("TouchControls")
	if touch:
		touch.visible = on


## 쉬기 시작 때 뜬 HUD 가운데 안내('달빛풀에서 쉰다…')와 '저장되었다'는 멈춤 동안 함께 멈춰서 메뉴 줄 위에 겹친다 → 지운다.
func _clear_hud_text() -> void:
	var hud := _room_node("CombatHUD")
	if hud == null:
		return
	if hud.has_method("show_message"):
		hud.show_message("", 0.0)
	if hud.has_method("flash"):
		hud.flash("")
	# HUD 는 멈춤 동안 스스로 다시 그리지 않으므로(_process 가 멈춤) 지운 글자가 화면에서도 사라지게 한 번 다시 그린다
	for c in hud.get_children():
		if c is CanvasItem:
			(c as CanvasItem).queue_redraw()


func tab() -> int:
	return _tab


func stat_panel() -> StatMenu:
	return _stat


func _set_tab(t: int) -> void:
	_tab = clampi(t, 0, 1)
	if _tab == 1:
		_stat.open(_player)
	else:
		_stat.close()
	_panel.queue_redraw()


func _switch_tab(dir: int) -> void:
	var t := clampi(_tab + dir, 0, 1)
	if t == _tab:
		return
	Sfx.play("select")
	_set_tab(t)


func _handle_event(event: InputEvent) -> void:
	# 탭 머리 누르기 (그림보다 위아래로 조금 넓게)
	if event is InputEventScreenTouch and event.pressed:
		for i in 2:
			if _tab_rect(i).grow_individual(0.0, TAB_TOUCH_PAD, 0.0, TAB_TOUCH_PAD * 0.5).has_point(event.position):
				if i != _tab:
					Sfx.play("select")
					_set_tab(i)
				return
	# 스틱 좌·우: 한 번 밀기 = 한 탭 (스틱 떨림으로 탭이 왔다 갔다 하지 않게)
	if _stick_h.feed(event, ["move_left", "ui_left"], ["move_right", "ui_right"]):
		if _stick_h.step != 0:
			_switch_tab(_stick_h.step)
		return
	if event.is_action_pressed("move_right") or event.is_action_pressed("ui_right") or event.is_action_pressed("soul_next"):
		_switch_tab(1)
		return
	if event.is_action_pressed("move_left") or event.is_action_pressed("ui_left") or event.is_action_pressed("soul_prev"):
		_switch_tab(-1)
		return
	if _tab == 1:
		if _stat.handle(event):
			return
		# 성장 탭에서 줄 밖을 누르면 닫기 (이동 목록의 줄 자리로 넘어가 이동이 되지 않게 기본 처리를 거치지 않는다)
		if event is InputEventScreenTouch and event.pressed:
			close()
			return
		if event.is_action_pressed("dodge") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("map"):
			close()
		return
	super._handle_event(event)


func _list_top() -> float:
	return _panel.size.y * 0.3


func _accent() -> Color:
	return GOLD if _tab == 1 else super._accent()


func _tab_rect(i: int) -> Rect2:
	var size := _panel.size
	var total := TAB_W * 2.0 + TAB_GAP
	var x0 := (size.x - total) / 2.0
	return Rect2(x0 + i * (TAB_W + TAB_GAP), size.y * 0.155, TAB_W, TAB_H)


func _draw_title(font: Font) -> void:
	var size := _panel.size
	_panel.draw_string(font, Vector2(size.x / 2.0 - 400, size.y * 0.115), "달빛풀", HORIZONTAL_ALIGNMENT_CENTER, 800, 36, Color(0.56, 0.83, 1.0))
	var labels := ["뿌리를 따라 이동", "성장"]
	var accents := [Color(0.56, 0.83, 1.0), GOLD]
	for i in 2:
		var r := _tab_rect(i)
		var sel := i == _tab
		var ac: Color = accents[i]
		_panel.draw_rect(r, Color(ac, 0.28) if sel else Color(1, 1, 1, 0.07))
		if sel:
			_panel.draw_rect(r, Color(ac, 0.8), false, 1.5)
		var text: String = labels[i]
		var fs := 26
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col := ac if sel else Color(0.85, 0.85, 0.85)
		if i == 1:
			# "성장   ✦ 128" — 빛 가루 보유량을 함께
			var have := "%d" % Progress.dust
			var hw := font.get_string_size(have, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			var total_w := tw + 30.0 + 20.0 + hw
			var x := r.position.x + (r.size.x - total_w) / 2.0
			var base := r.position.y + r.size.y / 2.0 + fs * 0.36
			_panel.draw_string(font, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			StatMenu.draw_spark(_panel, Vector2(x + tw + 30.0 + 8.0, r.position.y + r.size.y / 2.0), 8.0, StatMenu.DUST_COLOR if sel else Color(0.8, 0.78, 0.65))
			_panel.draw_string(font, Vector2(x + tw + 30.0 + 20.0, base - 1), have, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, StatMenu.DUST_COLOR if sel else Color(0.8, 0.78, 0.65))
		else:
			_panel.draw_string(font, Vector2(r.position.x + (r.size.x - tw) / 2.0, r.position.y + r.size.y / 2.0 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# 좌·우 화살표 (탭이 하나 더 있다는 표시)
	var left := _tab_rect(0)
	var right := _tab_rect(1)
	var cy := left.position.y + TAB_H / 2.0
	var arrow_col := Color(1, 1, 1, 0.35)
	_panel.draw_colored_polygon(PackedVector2Array([Vector2(left.position.x - 46, cy), Vector2(left.position.x - 28, cy - 11), Vector2(left.position.x - 28, cy + 11)]), arrow_col if _tab == 1 else Color(1, 1, 1, 0.12))
	_panel.draw_colored_polygon(PackedVector2Array([Vector2(right.end.x + 46, cy), Vector2(right.end.x + 28, cy - 11), Vector2(right.end.x + 28, cy + 11)]), arrow_col if _tab == 0 else Color(1, 1, 1, 0.12))
	var sub: String = _subtitle if _tab == 0 else str(_stat_data.get("subtitle", ""))
	_panel.draw_string(font, Vector2(size.x / 2.0 - 400, left.end.y + 34), sub, HORIZONTAL_ALIGNMENT_CENTER, 800, 20, Color(1, 1, 1, 0.5))


func _draw_list(font: Font) -> void:
	if _tab == 0:
		super._draw_list(font)
	# 성장 탭은 StatMenu(자식 Control)가 스스로 그린다


func _hint_text() -> String:
	if _tab == 1:
		return "위·아래로 고르고 결정: 한 단계 성장 (터치: 줄을 두 번)  ·  좌·우: 이동 탭  ·  회피 / 메뉴 / 바깥 누르기: 닫고 쉬기 계속"
	return "위·아래로 고르고 결정: 이동 (터치: 줄 누르기)  ·  좌·우: 성장 탭  ·  회피 / 메뉴 / 바깥 누르기: 닫고 쉬기 계속"

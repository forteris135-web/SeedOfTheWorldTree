extends Control
class_name StatMenu
## 성장 패널 (2026-10-19 기획자 요청 9번): 달빛풀에서 재화 '빛 가루'로 최대 체력·공격력·회복량·이슬을 한 단계씩 올린다.
## 항목·값·비용·글자는 data/dialogue/stats.json (stats_*.json 을 두면 DialogueData 가 합쳐 읽는다).
## 단계는 Progress.upgrades["stat_<kind>_level"] 에 남고(세이브 자동), 효과는 Progress.add_upgrade(kind, amount) 로 들어가
## 소녀가 _apply_abilities 로 다시 계산한다 — 아이템·구원 보상과 같은 길.
## 이 노드는 CanvasLayer 가 아니라 Control 이다: GrassMenu(달빛풀 메뉴)가 자기 판 안에 넣고 open()/handle()/close() 로 부린다.
## 안내 글자는 메뉴 안에만 둔다 (기획자 결정: 플레이 화면에 설명 글자 없음).
## 이슬은 최대 5개 (Progress.MAX_DEWS, v1.1.0 기획자 요청 16: 기본 3 + 이 메뉴의 이슬 2단계). 이슬이 가득하면 이슬 줄은
## 비용 대신 '가득'을 보이고 사지 않는다 (거절 이유 "full"; 단계를 다 채워 가득해도 '가득'). 다른 이슬 보상은 모두 새순이 되었다.
## v1.1.0 (기획자 요청 14): 빛 가루 비용은 v1.0 의 1.4배 (stats.json). 새순으로 사는 기술은 옆 탭 SkillMenu.

signal purchased(kind: String, level: int, cost: int)
## "no_dust"(모자람) / "maxed"(최대 단계) / "full"(이슬이 이미 가득 — 이슬 줄만)
signal rejected(kind: String, reason: String)

const DATA_PATH := "res://data/dialogue/stats.json"
const ACCENT := Color(1.0, 0.86, 0.5)
const DUST_COLOR := Color(1.0, 0.92, 0.62)
const BAD := Color(1.0, 0.45, 0.4)
const GOOD := Color(0.75, 0.95, 0.8)
## 이슬이 가득할 때 이슬 줄의 '가득' 글자 색 (달빛 이슬 구슬의 은청색)
const FULL_COLOR := Color(0.62, 0.85, 1.0)
## 터치: 첫 누르기는 고르기(+ "한 번 더 누르면 성장" 글자), 같은 줄을 한 번 더 누르면 산다 (잘못 눌러 쓰지 않게).
## 이미 골라진 줄(처음 연 첫 줄, 키보드로 고른 줄)도 터치 첫 누르기는 고르기만 한다. false 면 한 번에 산다.
const TOUCH_TWO_TAP := true
const ROW_H := 86.0
const ROW_W := 760.0
## 둘째 줄 설명 글의 x (단계 눈금 최대 8개 + "8 / 8" 오른쪽)
const DESC_X := 300.0
## 줄 목록이 시작하는 높이 (화면 높이 비율). GrassMenu 의 탭 머리 아래.
var top_ratio := 0.3

var items: Array = []
var index := 0
var player: Player
var _data := {}
var _msg := ""
var _msg_color := Color.WHITE
var _msg_timer := 0.0
var _shake := 0.0
var _flash := 0.0
var _flash_row := -1
var _t := 0.0
## 터치로 한 번 눌러 둔 줄 (-1 = 없음). 이 줄을 한 번 더 누를 때만 산다. 열 때·키보드로 옮길 때 지운다.
var _armed_row := -1
## 스틱 위·아래: 한 번 밀기 = 한 칸
var _stick := StickLatch.new()


# ---------- 계산 (정적: 시험·다른 화면에서도 쓴다) ----------

static func load_data() -> Dictionary:
	return DialogueData.load_dialogue(DATA_PATH)


static func load_items() -> Array:
	return load_data().get("items", [])


static func level_key(kind: String) -> String:
	return "stat_%s_level" % kind


static func level_of(kind: String) -> int:
	return int(Progress.upgrades.get(level_key(kind), 0))


static func max_level_of(item: Dictionary) -> int:
	return int(item.get("max_level", 1))


## level 단계에서 다음 단계로 가는 비용: 시작 비용 + 단계마다 더해지는 비용
static func cost_of(item: Dictionary, level: int) -> int:
	return int(item.get("base_cost", 0)) + int(item.get("cost_step", 0)) * level


## 지금 살 수 있는가: "" 이면 가능, 아니면 이유 "maxed" / "full" / "no_dust"
static func can_buy(item: Dictionary) -> String:
	var kind: String = item.get("kind", "")
	var lvl := level_of(kind)
	if lvl >= max_level_of(item):
		return "maxed"
	if is_full(kind):
		return "full"
	if Progress.dust < cost_of(item, lvl):
		return "no_dust"
	return ""


## 단계와 상관없이 더 받을 수 없는가: 이슬이 이미 최대(5개)다.
static func is_full(kind: String) -> bool:
	return kind == "dews" and Progress.dews_full()


## 한 단계 산다. 돌려주는 값: "" 이면 성공, 아니면 거절 이유. 성공하면 빛 가루가 줄고 성장이 들어간다.
## p 를 주면 쉬는 중인 소녀의 체력·이슬을 바로 채운다 (달빛풀에서 쉬면 가득 차는 것과 같게).
static func buy(item: Dictionary, p: Player = null) -> String:
	var why := can_buy(item)
	if why != "":
		return why
	var kind: String = item.get("kind", "")
	var lvl := level_of(kind)
	var cost := cost_of(item, lvl)
	if not Progress.spend_dust(cost):
		return "no_dust"
	Progress.upgrades[level_key(kind)] = lvl + 1   # add_upgrade 보다 먼저 (듣는 쪽이 단계를 읽을 수 있게)
	Progress.add_upgrade(kind, float(item.get("amount", 0)))
	if p != null and is_instance_valid(p) and p.state == Player.State.REST:
		p.hp = p.max_hp
		p.dews = p.max_dews
		p.hp_changed.emit(p.hp, p.max_hp)
		p.dews_changed.emit(p.dews)
	return ""


## 지금 값 글자 (성장 뒤 "이제 110" 같은 표시용). 소녀가 없으면 Progress.upgrades 로 셈한다.
static func current_value_text(kind: String, p: Player = null) -> String:
	var alive := p != null and is_instance_valid(p)
	match kind:
		"max_hp":
			return "%d" % int(p.max_hp if alive else 100.0 + float(Progress.upgrades.get("max_hp", 0.0)))
		"attack":
			var mult: float = p.attack_multiplier if alive else 1.0 + float(Progress.upgrades.get("attack", 0.0))
			return "+%d%%" % int(round((mult - 1.0) * 100.0))
		"heal":
			return "%d" % int(p.heal_amount if alive else 45.0 + Progress.heal_bonus())
		"dews":
			return "%d개" % int(p.max_dews if alive else Progress.dew_max())
	return ""


# ---------- 화면 ----------

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)


func open(p: Player) -> void:
	player = p
	_data = load_data()
	items = _data.get("items", [])
	index = clampi(index, 0, maxi(items.size() - 1, 0))
	_msg_timer = 0.0
	_shake = 0.0
	_flash = 0.0
	_armed_row = -1
	_stick.reset()
	visible = true
	set_process(true)
	queue_redraw()


func close() -> void:
	visible = false
	_armed_row = -1
	set_process(false)


func _process(delta: float) -> void:
	_t += delta
	_msg_timer = maxf(_msg_timer - delta, 0.0)
	_shake = maxf(_shake - delta * 3.0, 0.0)
	_flash = maxf(_flash - delta * 2.5, 0.0)
	queue_redraw()


## 입력 하나를 처리한다. 처리했으면 true. (닫기·탭 바꾸기·바깥 누르기는 부모 메뉴가 맡는다)
func handle(event: InputEvent) -> bool:
	if not visible:
		return false
	if _stick.feed(event, ["move_up", "ui_up"], ["move_down", "ui_down"]):
		if _stick.step != 0:
			move(_stick.step)
		return true
	if event.is_action_pressed("move_down") or event.is_action_pressed("ui_down"):
		move(1)
		return true
	if event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
		move(-1)
		return true
	if event.is_action_pressed("jump") or event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		try_buy(index)
		return true
	if event is InputEventScreenTouch and event.pressed:
		var hit := row_at(event.position)
		if hit < 0:
			return false
		if TOUCH_TWO_TAP and hit != _armed_row:
			# 첫 누르기: 고르기만 (산 뒤에도 같은 줄은 눌러 둔 채라, 이어서 누르면 한 단계씩 더 산다)
			index = hit
			_armed_row = hit
			Sfx.play("blip")
			_say(str(_data.get("touch_again", "한 번 더 누르면 성장")), Color(1, 1, 1, 0.85))
			queue_redraw()
		else:
			try_buy(hit)
		return true
	return false


## 고른 줄을 dir(+1 아래 / -1 위)만큼 옮긴다 (키보드·패드). 터치로 눌러 둔 줄은 잊는다.
func move(dir: int) -> void:
	var n := maxi(items.size(), 1)
	index = (index + dir + n) % n
	_armed_row = -1
	Sfx.play("blip")
	queue_redraw()


## i 번째 항목을 한 단계 산다 (소리·번쩍·흔들림·글자 포함). 돌려주는 값은 buy() 와 같다.
func try_buy(i: int) -> String:
	if i < 0 or i >= items.size():
		return "none"
	var item: Dictionary = items[i]
	var kind: String = item.get("kind", "")
	var why := buy(item, player)
	match why:
		"":
			_flash = 1.0
			_flash_row = i
			Sfx.play("soul", -4.0, 0.03)
			Juice.rumble(0.2, 0.4, 0.15)
			var lvl := level_of(kind)
			var tmpl: String = _data.get("bought", "{name} {amount}  (이제 {now})  — 빛 가루 {cost}")
			_say(tmpl.format({"name": item.get("name", kind), "amount": item.get("amount_text", ""), "now": current_value_text(kind, player), "cost": cost_of(item, lvl - 1)}), ACCENT)
			purchased.emit(kind, lvl, cost_of(item, lvl - 1))
		"no_dust":
			_shake = 1.0
			Sfx.play("blip", -4.0)
			_say(_data.get("not_enough", "빛 가루가 모자라다"), BAD)
			rejected.emit(kind, why)
		"maxed":
			_shake = 0.6
			Sfx.play("blip", -6.0)
			_say(_data.get("maxed", "더는 자랄 수 없다"), Color(0.8, 0.8, 0.8))
			rejected.emit(kind, why)
		"full":
			_shake = 0.6
			Sfx.play("blip", -6.0)
			_say(full_text(_data), FULL_COLOR)
			rejected.emit(kind, why)
	queue_redraw()
	return why


## 이슬이 가득해 못 살 때의 안내 (stats.json "dews_full", {max} = 최대 개수)
static func full_text(data: Dictionary) -> String:
	return str(data.get("dews_full", "이슬이 가득하다 (최대 {max}개)")).format({"max": Progress.MAX_DEWS})


func _say(text: String, color: Color) -> void:
	_msg = text
	_msg_color = color
	_msg_timer = 2.2


func row_rect(i: int) -> Rect2:
	var x := (size.x - ROW_W) / 2.0
	return Rect2(x, size.y * top_ratio + i * ROW_H, ROW_W, ROW_H - 8.0)


func row_at(pos: Vector2) -> int:
	for i in items.size():
		if row_rect(i).has_point(pos):
			return i
	return -1


## 목록 아래 끝 (부모가 안내 글자 자리를 잡을 때)
func list_bottom() -> float:
	return size.y * top_ratio + items.size() * ROW_H


## 작은 네 갈래 빛 (빛 가루 표시). 글꼴에 없는 글자 대신 모양으로 그린다.
static func draw_spark(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 8:
		var a := k * TAU / 8.0 - PI / 2.0
		var rr := r if k % 2 == 0 else r * 0.38
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	ci.draw_colored_polygon(pts, color)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var x := (size.x - ROW_W) / 2.0
	var y0 := size.y * top_ratio
	# 보유량 (목록 오른쇽 위)
	var have := "%d" % Progress.dust
	var have_w := font.get_string_size(have, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(font, Vector2(x + ROW_W - have_w, y0 - 16), have, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, DUST_COLOR)
	draw_spark(self, Vector2(x + ROW_W - have_w - 22, y0 - 25), 9.0, DUST_COLOR)
	draw_string(font, Vector2(x + ROW_W - have_w - 40 - 110, y0 - 16), str(_data.get("currency", "빛 가루")), HORIZONTAL_ALIGNMENT_RIGHT, 110, 22, Color(1, 1, 1, 0.6))
	for i in items.size():
		var item: Dictionary = items[i]
		var kind: String = item.get("kind", "")
		var r := row_rect(i)
		var sel := i == index
		if sel and _shake > 0.0:
			r.position.x += sin(_t * 70.0) * 10.0 * _shake
		draw_rect(r, Color(ACCENT, 0.18) if sel else Color(1, 1, 1, 0.06))
		if sel:
			draw_rect(r, Color(ACCENT, 0.6), false, 1.5)
		if _flash_row == i and _flash > 0.0:
			draw_rect(r, Color(1, 1, 1, 0.45 * _flash))
		var lvl := level_of(kind)
		var maxl := max_level_of(item)
		var name_col := ACCENT if sel else Color(0.92, 0.92, 0.92)
		draw_string(font, r.position + Vector2(22, 36), ("▸  " if sel else "    ") + str(item.get("name", kind)), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, name_col)
		draw_string(font, r.position + Vector2(236, 36), str(item.get("amount_text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, GOOD)
		# 단계 눈금
		for k in maxl:
			var pip := Rect2(r.position + Vector2(46 + k * 18.0, 54), Vector2(12, 12))
			draw_rect(pip, DUST_COLOR if k < lvl else Color(1, 1, 1, 0.15))
		draw_string(font, r.position + Vector2(46 + maxl * 18.0 + 10, 66), "%d / %d" % [lvl, maxl], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.55))
		var full := is_full(kind)
		var desc := str(item.get("desc", ""))
		if full:
			desc = str(_data.get("dews_full_desc", "이슬은 {max}개까지")).format({"max": Progress.MAX_DEWS})
		draw_string(font, r.position + Vector2(DESC_X, 66), desc, HORIZONTAL_ALIGNMENT_LEFT, 300, 18, Color(FULL_COLOR, 0.75) if full else Color(1, 1, 1, 0.5))
		# 비용 (오른쪽). 이슬 줄은 가득하면 단계와 상관없이 '가득' (최대 단계 = 이슬 5개)
		if full:
			draw_string(font, r.position + Vector2(r.size.x - 180, 44), str(_data.get("full_label", "가득")), HORIZONTAL_ALIGNMENT_RIGHT, 160, 26, FULL_COLOR)
		elif lvl >= maxl:
			draw_string(font, r.position + Vector2(r.size.x - 180, 44), "최대", HORIZONTAL_ALIGNMENT_RIGHT, 160, 26, Color(0.65, 0.65, 0.65))
		else:
			var cost := cost_of(item, lvl)
			var ok := Progress.dust >= cost
			var ctext := "%d" % cost
			var cw := font.get_string_size(ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			var col := DUST_COLOR if ok else BAD
			draw_string(font, r.position + Vector2(r.size.x - 22 - cw, 44), ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)
			draw_spark(self, r.position + Vector2(r.size.x - 22 - cw - 20, 35), 8.0, col)
	if _msg_timer > 0.0 and _msg != "":
		var a := minf(_msg_timer, 1.0)
		draw_string(font, Vector2(x, list_bottom() + 30), _msg, HORIZONTAL_ALIGNMENT_CENTER, ROW_W, 24, Color(_msg_color, a))

extends StatMenu
class_name SkillMenu
## 기술 패널 (v1.1.0 기획자 요청 15·18): 달빛풀 메뉴(GrassMenu)의 셋째 탭 '기술'.
## 새 재화 '새순'(토큰)으로 일반 공격 · 씨앗 · 바람 · 빛 영혼 기술 · 최대 스태미너를 한 단계씩(최대 3단계) 다듬는다.
## 화면과 조작은 성장 패널(StatMenu)과 같다: 위·아래로 고르고 결정으로 산다, 터치는 같은 줄을 한 번 더 눌러야 산다.
## 비용·효과 숫자는 Progress 표(TOKEN_COST · SKILL_DAMAGE · SKILL_RANGE · SKILL_COOLDOWN · STAMINA_PER_LEVEL),
## 글자는 data/dialogue/skills.json. 단계는 Progress.upgrades["tok_<줄>"] 에 남는다(세이브 자동, Progress.buy_token_level).
## 바람·빛 줄은 그 영혼을 얻은 뒤에만 살 수 있다 (skills.json 의 requires) — 그 전엔 줄이 흐리고 "아직 깃들지 않은 영혼".
## 소녀 쪽 효과(피해·범위·쿨다운·최대 스태미너)는 소녀가 시전·타격 순간 Progress 에서 읽는다 (사면 바로 반영).

const SKILL_DATA_PATH := "res://data/dialogue/skills.json"
## 새순 색 (Pickup.COLORS["token"] 과 같은 연둣빛)
const SPROUT := Color(0.55, 1.0, 0.55)
## 잠긴 줄(아직 얻지 못한 영혼)의 글자 색
const LOCKED_COL := Color(1, 1, 1, 0.32)
## 둘째 줄 설명 글의 x (단계 눈금 3개 + "3 / 3" 오른쪽)
const SKILL_DESC_X := 190.0


# ---------- 계산 (정적: 시험·다른 화면에서도 쓴다) ----------

static func load_skill_data() -> Dictionary:
	return DialogueData.load_dialogue(SKILL_DATA_PATH)


static func load_skill_items() -> Array:
	return load_skill_data().get("items", [])


## skills.json 글자 하나 (없으면 fallback). 줍기·구원 안내처럼 메뉴 밖에서도 쓴다.
static func text_of(key: String, fallback: String) -> String:
	return str(load_skill_data().get(key, fallback))


static func track_of(item: Dictionary) -> String:
	return str(item.get("track", ""))


## 아직 그 영혼을 얻지 못해 살 수 없는 줄인가 (requires 가 비면 늘 열림)
static func is_locked(item: Dictionary) -> bool:
	var req := str(item.get("requires", ""))
	return req != "" and not Progress.has_ability(req)


## 지금 살 수 있는가: "" 이면 가능, 아니면 이유 "locked" / "maxed" / "no_tokens"
static func track_can_buy(item: Dictionary) -> String:
	if is_locked(item):
		return "locked"
	var cost := Progress.token_next_cost(track_of(item))
	if cost < 0:
		return "maxed"
	if Progress.tokens < cost:
		return "no_tokens"
	return ""


## 한 단계 산다. 돌려주는 값: "" 이면 성공(새순이 줄고 단계가 오름), 아니면 거절 이유.
static func track_buy(item: Dictionary) -> String:
	var why := track_can_buy(item)
	if why != "":
		return why
	if not Progress.buy_token_level(track_of(item)):
		return "no_tokens"
	return ""


## level 단계(1~3)의 효과 글자. 0 이면 "".
static func effect_text(item: Dictionary, level: int) -> String:
	var lv: Array = item.get("levels", [])
	if level <= 0 or lv.is_empty():
		return ""
	return str(lv[clampi(level - 1, 0, lv.size() - 1)])


## 작은 새순 (줄기 + 잎 두 장). 글꼴에 없는 글자 대신 모양으로 그린다 — 기술 탭 머리·보유량·비용·새순 구슬.
## 잎 모양은 반지름 1 짜리로 한 번만 만들어 두고 크기·자리는 그리기 변환으로 바꾼다 (매 프레임 새 배열을 만들지 않게).
static var _sprout_leaves: Array[PackedVector2Array] = []


static func draw_sprout(ci: CanvasItem, c: Vector2, r: float, color: Color) -> void:
	if _sprout_leaves.is_empty():
		var top := Vector2(0, -0.05)
		for side in [-1.0, 1.0]:
			var axis := Vector2(side * 0.95, -0.7) - top
			var nrm := Vector2(-axis.y, axis.x).normalized() * 0.32
			var pts := PackedVector2Array()
			for k in 7:
				var u := k / 6.0
				pts.append(top + axis * u + nrm * sin(PI * u))
			for k in range(5, 0, -1):
				var u := k / 6.0
				pts.append(top + axis * u - nrm * sin(PI * u))
			_sprout_leaves.append(pts)
	ci.draw_set_transform(c, 0.0, Vector2(r, r))
	ci.draw_line(Vector2(0, 0.95), Vector2(0, -0.05), color, 0.2)
	for pts in _sprout_leaves:
		ci.draw_colored_polygon(pts, color)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------- 화면 ----------

func open(p: Player) -> void:
	player = p
	_data = load_skill_data()
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


## i 번째 줄을 한 단계 산다 (소리·번쩍·흔들림·글자 포함). 돌려주는 값은 track_buy() 와 같다.
func try_buy(i: int) -> String:
	if i < 0 or i >= items.size():
		return "none"
	var item: Dictionary = items[i]
	var track := track_of(item)
	var cost := Progress.token_next_cost(track)
	var why := track_buy(item)
	match why:
		"":
			_flash = 1.0
			_flash_row = i
			Sfx.play("soul", -4.0, 0.03)
			Juice.rumble(0.2, 0.4, 0.15)
			var lvl := Progress.token_level(track)
			var tmpl := str(_data.get("bought", "{name} {level}단계 — {effect}  (새순 {cost})"))
			_say(tmpl.format({"name": item.get("name", track), "level": lvl, "effect": effect_text(item, lvl), "cost": cost}), SPROUT)
			purchased.emit(track, lvl, cost)
		"no_tokens":
			_shake = 1.0
			Sfx.play("blip", -4.0)
			_say(str(_data.get("not_enough", "새순이 모자라다")), BAD)
			rejected.emit(track, why)
		"maxed":
			_shake = 0.6
			Sfx.play("blip", -6.0)
			_say(str(_data.get("maxed", "더는 다듬을 수 없다")), Color(0.8, 0.8, 0.8))
			rejected.emit(track, why)
		"locked":
			_shake = 0.6
			Sfx.play("blip", -6.0)
			_say(str(_data.get("locked", "아직 깃들지 않은 영혼")), Color(0.8, 0.8, 0.8))
			rejected.emit(track, why)
	queue_redraw()
	return why


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var x := (size.x - ROW_W) / 2.0
	var y0 := size.y * top_ratio
	# 보유량 (목록 오른쪽 위): "새순  (새순 그림) 3"
	var have := "%d" % Progress.tokens
	var have_w := font.get_string_size(have, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_string(font, Vector2(x + ROW_W - have_w, y0 - 16), have, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, SPROUT)
	draw_sprout(self, Vector2(x + ROW_W - have_w - 20, y0 - 27), 11.0, SPROUT)
	draw_string(font, Vector2(x + ROW_W - have_w - 40 - 110, y0 - 16), str(_data.get("currency", "새순")), HORIZONTAL_ALIGNMENT_RIGHT, 110, 22, Color(1, 1, 1, 0.6))
	var maxl := Progress.TOKEN_MAX_LEVEL
	for i in items.size():
		var item: Dictionary = items[i]
		var track := track_of(item)
		var locked := is_locked(item)
		var r := row_rect(i)
		var sel := i == index
		if sel and _shake > 0.0:
			r.position.x += sin(_t * 70.0) * 10.0 * _shake
		draw_rect(r, Color(SPROUT, 0.16) if sel else Color(1, 1, 1, 0.06 if not locked else 0.03))
		if sel:
			draw_rect(r, Color(SPROUT, 0.6), false, 1.5)
		if _flash_row == i and _flash > 0.0:
			draw_rect(r, Color(1, 1, 1, 0.45 * _flash))
		var lvl := Progress.token_level(track)
		var name_col := LOCKED_COL if locked else (SPROUT if sel else Color(0.92, 0.92, 0.92))
		draw_string(font, r.position + Vector2(22, 36), ("▸  " if sel else "    ") + str(item.get("name", track)), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, name_col)
		# 첫째 줄 효과: 사면 얻는 단계 (최대면 지금 단계)
		var eff := effect_text(item, mini(lvl + 1, maxl))
		draw_string(font, r.position + Vector2(236, 36), eff, HORIZONTAL_ALIGNMENT_LEFT, 300, 22, LOCKED_COL if locked else GOOD)
		# 단계 눈금
		for k in maxl:
			var pip := Rect2(r.position + Vector2(46 + k * 18.0, 54), Vector2(12, 12))
			draw_rect(pip, SPROUT if k < lvl else Color(1, 1, 1, 0.15))
		draw_string(font, r.position + Vector2(46 + maxl * 18.0 + 10, 66), "%d / %d" % [lvl, maxl], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.55 if not locked else 0.3))
		# 둘째 줄: 잠김 안내 / 지금 단계 / 설명
		var desc := str(item.get("desc", ""))
		var desc_col := Color(1, 1, 1, 0.5)
		if locked:
			desc = str(_data.get("locked", "아직 깃들지 않은 영혼"))
			desc_col = Color(1, 1, 1, 0.42)
		elif lvl > 0 and lvl < maxl:
			desc = str(_data.get("now", "지금: {effect}")).format({"effect": effect_text(item, lvl)})
		draw_string(font, r.position + Vector2(SKILL_DESC_X, 66), desc, HORIZONTAL_ALIGNMENT_LEFT, 360, 18, desc_col)
		# 비용 (오른쪽)
		if lvl >= maxl:
			draw_string(font, r.position + Vector2(r.size.x - 180, 44), str(_data.get("max_label", "최대")), HORIZONTAL_ALIGNMENT_RIGHT, 160, 26, Color(0.65, 0.65, 0.65))
		else:
			var cost := Progress.token_next_cost(track)
			var ok := Progress.tokens >= cost
			var ctext := "%d" % cost
			var cw := font.get_string_size(ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			var col := LOCKED_COL if locked else (SPROUT if ok else BAD)
			draw_string(font, r.position + Vector2(r.size.x - 22 - cw, 44), ctext, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)
			draw_sprout(self, r.position + Vector2(r.size.x - 22 - cw - 18, 34), 9.0, col)
	if _msg_timer > 0.0 and _msg != "":
		var a := minf(_msg_timer, 1.0)
		draw_string(font, Vector2(x, list_bottom() + 30), _msg, HORIZONTAL_ALIGNMENT_CENTER, ROW_W, 24, Color(_msg_color, a))

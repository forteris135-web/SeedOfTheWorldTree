extends CanvasLayer
## 전투 표시: 체력, 가드 게이지, 이슬 방울, 성장 표시(공격·회복), 영혼, 가운데 메시지.
## 그림: art/ui/ (기획자의 HUD 시트에서 잘라낸 조각). 좌표 상수는 시트(2156×729) 기준이고
## 화면에는 SHEET_SCALE 로 줄여 그린다. 조각 자르기는 tools/cut_hud.gd.
##
## 성장이 HUD 에 반영되는 규칙
## - 이슬: max_dews 만큼 겹치지 않게 늘어놓는다 (한 줄 7개, 넘으면 둘째 줄). 새로 늘어난 이슬은 0.6초 반짝이며 커졌다 작아진다.
## - 체력 막대: max_hp 에 비례해 길어진다 (100 기준 1.0, 최대 1.6배). 틀 그림은 세 조각(왼쪽 / 늘림 조각 / 오른쪽 끝)으로 그려
##   끝 장식이 깨지지 않는다. 늘어나는 순간 0.5초에 걸쳐 자라며 한 번 번쩍.
## - 공격 배수·회복량 성장: 이슬 오른쪽에 작은 검 / 물방울 아이콘 + "+10%" / "+15" (성장이 없으면 아무것도 없음).
## - 영혼: 가진 영혼마다 작은 원, 고른 것은 밝고 크게 + "지금: 바람 (잿빛 잎새의 새)" 이름. 전환 순간 0.3초 번쩍.
##   쿨다운 중엔 고른 원 둘레에 차오르는 호(지난 비율)와 남은 초 숫자("7, 6, … 1") — 키보드·패드로 놀 때도 터치 버튼과 같은 정보.
## - 영혼 전환 알림 (2026-10-19 기획자 요청 "지금 어느 영혼인지 모른다"): 전환 순간 화면 가운데 위에 1.2초 동안 큰 글자("바람의 영혼", 영혼 색)와
##   작은 설명 한 줄("커다란 돌풍 — … / 쿨 5초", SOUL_NOTICE_SHOW_DESC 로 끌 수 있음)이 떠올랐다 사라진다.
##   보스 등장 이름이 떠 있는 3초 동안은 그 위(높이 0.105)로 올라간다.
## - 빛 가루 (재화, Progress.dust): 이슬 줄 오른쪽(성장 아이콘 뒤)에 반짝이는 점 아이콘 + 개수. 늘어나면 "+N" 이 떠올라 사라진다
##   (장면 전환 중 — 메뉴의 '불러오기' 등 — 에는 띄우지 않는다).
## - 성장이 생긴 순간 가운데에 "이슬 +1" 같은 짧은 글자(flash). 아이템·구원 보상이 같은 때 가운데 안내(show_message)를 띄우면 그것 하나만 보인다.
## 시험: tools/probe_hud.tscn (그리기와 같은 계산 함수 dew_slots / hp_bar_width / hp_frame_pieces / growth_labels / soul_dots 를 검사),
##       tools/probe_ui.tscn (dust_text / soul_notice_title / soul_cooldown 표시)

const SHEET_SCALE := 0.36
const ORIGIN := Vector2(10, 4)

const EMBLEM := preload("res://art/ui/hud_emblem.png")
const BAR_HP := preload("res://art/ui/hud_bar_hp.png")
const BAR_GUARD := preload("res://art/ui/hud_bar_guard.png")
const DEWS := [preload("res://art/ui/hud_dew_1.png"), preload("res://art/ui/hud_dew_2.png"), preload("res://art/ui/hud_dew_3.png")]

const EMBLEM_POS := Vector2(0, 0)
const HP_TRACK_POS := Vector2(540, 60)
const HP_FILL := Rect2(560, 219, 1400, 86)        # 채워지는 구간 (시트 좌표, 기본 길이)
const HP_RED_SLICE := Rect2(360, 159, 40, 86)     # 틀 그림 안에서 "찬 부분" 조각 (그림 좌표)
const HP_DARK_SLICE := Rect2(1260, 159, 40, 86)   # "빈 부분" 조각 (그림 좌표)
## 체력 틀 그림(1616×258)을 가르는 자리 (그림 px). 왼쪽 조각 [0, 900) / 오른쪽 끝 조각 [900, 1616).
## 그림 x 780~1160 구간은 잎 장식 없이 막대만 있어서 여기를 가르고 늘려도 장식이 깨지지 않는다.
const HP_FRAME_SPLIT := 900.0
## 늘어난 길이만큼 사이에 끼워 넣는 민무늬 막대 조각 (그림 좌표)
const HP_FRAME_STRETCH := Rect2(880, 0, 40, 258)
const HP_BASE := 100.0          # 이 체력일 때 막대 길이 1.0
const HP_SCALE_MAX := 1.6       # 막대 길이 최대 배수
const HP_GROW_TIME := 0.5       # 최대 체력이 늘 때 막대가 자라는 시간
const GUARD_TRACK_POS := Vector2(540, 318)
const GUARD_FILL := Rect2(560, 331, 1100, 70)
const GUARD_GREEN_SLICE := Rect2(360, 13, 40, 70)
const GUARD_DARK_SLICE := Rect2(910, 13, 40, 70)
const DEW_POS := [Vector2(405, 445), Vector2(560, 445), Vector2(735, 445)]   # 시트에 그려진 세 자리 (첫 자리만 기준으로 쓴다)
const DEW_STEP := 155.0         # 이슬 사이 간격 (시트 px; 성장 표시 자리 계산용)
const DEW_STEP_EXTRA := 175.0   # 4번째부터의 간격 (시트의 둘째→셋째 간격과 같게; 처음 세 자리는 DEW_POS 그대로)
const DEW_PER_ROW := 7          # 한 줄에 이 개수까지, 넘으면 둘째 줄
const DEW_ROW_STEP := 200.0     # 줄 사이 간격 (시트 px)
const DEW_POP_TIME := 0.6       # 새 이슬 반짝임 시간
const SEED_CENTER := Vector2(330, 320)
## 성장 표시 줄: 이슬 줄 오른쪽, 이슬 세로 가운데
const GROWTH_GAP := 20.0        # 마지막 이슬과의 간격 (시트 px)
const GROWTH_FONT_SIZE := 17
const GROWTH_ICON := 11.0       # 아이콘 반 높이 (화면 px)
## 영혼 표시: 엠블럼 아래
const SOUL_POS := Vector2(60, 790)   # 글자 기준선 (시트 px). 이슬이 둘째 줄까지 있으면 한 줄만큼 내려간다
const SOUL_DOT_R := 7.0              # 지름 14
const SOUL_DOT_R_SEL := 9.0          # 고른 영혼은 조금 크게
const SOUL_DOT_GAP := 24.0           # 원 사이 간격 (화면 px)
const SOUL_FLASH_TIME := 0.3
const SOUL_FONT_SIZE := 18
## (영혼 색은 Player.SOUL_INFO 에 한 곳만 둔다: 씨앗 연둣빛 / 바람 민트 / 빛 금빛)
const SOUL_CD_FONT_SIZE := 26       # 영혼 이름 옆 남은 초 숫자 (아이폰에서도 읽히게 영혼 이름 18 보다 크게)
## 영혼 전환 알림
const SOUL_NOTICE_TIME := 1.2
const SOUL_NOTICE_FADE_IN := 0.15
const SOUL_NOTICE_FADE_OUT := 0.35
const SOUL_NOTICE_Y := 0.17         # 화면 높이 비율 (큰 글자 기준선)
const SOUL_NOTICE_Y_BOSS := 0.105   # 보스 등장 이름(높이 0.22, 72pt)이 떠 있는 3초 동안은 그 위로 올려 겹치지 않게
## 설명 줄("커다란 돌풍 — … / 쿨 5초")을 보일지. 기획자가 '큰 이름만' 을 고르면 false 로.
const SOUL_NOTICE_SHOW_DESC := true
const SOUL_NOTICE_TITLE_SIZE := 46
const SOUL_NOTICE_DESC_SIZE := 20
## 빛 가루 표시
const DUST_GAP := 18.0              # 성장 표시(또는 이슬) 와의 간격 (화면 px)
const DUST_ICON := 9.0              # 아이콘 반 크기 (화면 px)
const DUST_FONT_SIZE := 17
const DUST_POP_TIME := 1.1          # "+N" 이 떠올라 사라지는 시간
const DUST_POP_RISE := 26.0         # 떠오르는 거리 (화면 px)
const DUST_COLOR := Color(1.0, 0.95, 0.72)

var _player: Player
var _canvas: Control
var _message := ""
var _message_timer := 0.0
var _message_set_at := -100.0   # show_message 가 마지막으로 불린 때 (_time)
var _flash_text := ""
var _flash_timer := 0.0
var _time := 0.0
var _hp_shown := 1.0       # 체력 막대가 천천히 따라오게
var _guard_flash := 0.0
## 성장 연출
var _last_max_dews := -1
var _last_max_hp := -1.0
var _dew_pop := {}          # 이슬 번호 -> 남은 반짝임 시간
var _hp_scale_shown := 1.0  # 지금 그리는 막대 배수 (목표로 자란다)
var _hp_scale_from := 1.0
var _hp_scale_timer := 0.0
var _hp_grow_flash := 0.0
var _soul_flash := 0.0
var _pending_flash := ""    # Progress.upgraded 로 받은 짧은 글자. 같은 때 가운데 안내가 뜨면 버린다
var _pending_flash_frames := 0
## 영혼 전환 알림: 남은 시간과 어떤 영혼인지
var _soul_notice_timer := 0.0
var _soul_notice_soul := ""
## 빛 가루: 늘어난 양이 떠오르는 글자들 [{"amount": int, "t": 남은 시간}]
var _dust_pops: Array = []
var _dust_glow := 0.0       # 늘어난 순간 아이콘이 밝아졌다 가라앉음


func _ready() -> void:
	layer = 15
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)
	Progress.upgraded.connect(_on_upgraded)
	Progress.dust_changed.connect(_on_dust_changed)
	_last_dust = Progress.dust


func _process(delta: float) -> void:
	_time += delta
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
		if _player:
			_hp_shown = _player.hp / _player.max_hp
			_last_max_dews = _player.max_dews
			_last_max_hp = _player.max_hp
			_hp_scale_shown = hp_bar_scale()
			_player.just_guarded.connect(func(_s): flash("저스트 가드!"); _guard_flash = 1.0)
			_player.guard_broken.connect(func(): flash("가드가 깨졌다"); _guard_flash = 1.0)
			_player.purify_started.connect(func(_t): flash("정화의 손길"))
			_player.died.connect(func(): show_message("쓰러졌다…", 2.5))
			_player.rest_started.connect(func(_g): show_message("달빛풀에서 쉰다. 적들이 다시 깨어난다.", 2.5))
			_player.soul_changed.connect(_on_soul_changed)
	else:
		var target := _player.hp / _player.max_hp
		_hp_shown = move_toward(_hp_shown, target, delta * (2.5 if target < _hp_shown else 4.0))
		_track_growth(delta)
	_message_timer = maxf(_message_timer - delta, 0.0)
	_flash_timer = maxf(_flash_timer - delta, 0.0)
	_guard_flash = maxf(_guard_flash - delta * 2.0, 0.0)
	_soul_flash = maxf(_soul_flash - delta / SOUL_FLASH_TIME, 0.0)
	_hp_grow_flash = maxf(_hp_grow_flash - delta / HP_GROW_TIME, 0.0)
	_soul_notice_timer = maxf(_soul_notice_timer - delta, 0.0)
	_dust_glow = maxf(_dust_glow - delta / DUST_POP_TIME, 0.0)
	if _scene_changing() and not _dust_pops.is_empty():
		# 메뉴의 '불러오기'는 빛 가루를 넣고(dust_changed) 같은 호출에서 장면 전환을 시작한다 → 번 것이 아니니 떠오르는 글자를 지운다
		_dust_pops.clear()
		_dust_glow = 0.0
	for i in range(_dust_pops.size() - 1, -1, -1):
		_dust_pops[i]["t"] -= delta
		if _dust_pops[i]["t"] <= 0.0:
			_dust_pops.remove_at(i)
	if _pending_flash != "":
		_pending_flash_frames -= 1
		if _pending_flash_frames <= 0:
			# 아이템·구원 보상은 add_upgrade 직후 같은 프레임에 가운데 안내를 띄운다 → 그것 하나만 남긴다
			if _time - _message_set_at > 0.15:
				flash(_pending_flash)
			_pending_flash = ""
	_canvas.queue_redraw()


## 성장 감지: 이슬이 늘면 새 이슬이 반짝이고, 최대 체력이 늘면 막대가 자란다.
func _track_growth(delta: float) -> void:
	if _player.max_dews > _last_max_dews:
		for i in range(_last_max_dews, _player.max_dews):
			_dew_pop[i] = DEW_POP_TIME
	_last_max_dews = _player.max_dews
	var target_scale := hp_bar_scale()
	if _player.max_hp > _last_max_hp + 0.01:
		_hp_scale_from = _hp_scale_shown
		_hp_scale_timer = HP_GROW_TIME
		_hp_grow_flash = 1.0
	elif _player.max_hp < _last_max_hp - 0.01:
		_hp_scale_timer = 0.0   # 줄어드는 일(새로 시작)은 바로
	_last_max_hp = _player.max_hp
	if _hp_scale_timer > 0.0:
		_hp_scale_timer = maxf(_hp_scale_timer - delta, 0.0)
		var t := 1.0 - _hp_scale_timer / HP_GROW_TIME
		_hp_scale_shown = lerpf(_hp_scale_from, target_scale, 1.0 - (1.0 - t) * (1.0 - t))   # 빠르게 자라 천천히 멎음
	else:
		_hp_scale_shown = target_scale
	for k in _dew_pop.keys():
		_dew_pop[k] -= delta
		if _dew_pop[k] <= 0.0:
			_dew_pop.erase(k)


func _on_upgraded(kind: String, amount: float) -> void:
	var text := ""
	match kind:
		"dews": text = "이슬 +%d" % int(round(amount))
		"max_hp": text = "체력 +%d" % int(round(amount))
		"attack": text = "공격 +%d%%" % int(round(amount * 100.0))
		"heal": text = "회복 +%d" % int(round(amount))
	if text == "":
		return
	_pending_flash = text
	_pending_flash_frames = 2


## 영혼을 바꿨다: 번쩍 + 가운데 위 알림 1.2초
func _on_soul_changed(s: String) -> void:
	_soul_flash = 1.0
	_soul_notice_soul = s
	_soul_notice_timer = SOUL_NOTICE_TIME


var _last_dust := 0
## 장면 전환(Game.go_to 의 검은 화면) 중인가
func _scene_changing() -> bool:
	return bool(Game.get("_busy"))


## 빛 가루가 바뀌었다: 늘어난 만큼 "+N" 이 떠오른다 (줄어든 것은 조용히)
func _on_dust_changed(amount: int) -> void:
	var diff := amount - _last_dust
	_last_dust = amount
	if diff > 0:
		_dust_pops.append({"amount": diff, "t": DUST_POP_TIME})
		_dust_glow = 1.0


func show_message(text: String, seconds := 2.0) -> void:
	_message = text
	_message_timer = seconds
	_message_set_at = _time
	# 아이템·구원 보상은 add_upgrade 직후 같은 호출 안에서 가운데 안내를 띄운다 → 짧은 성장 글자는 버린다
	# (프레임이 끊겨도 둘 다 뜨지 않게, 시간이 아니라 여기서 바로 지운다)
	_pending_flash = ""


func flash(text: String) -> void:
	_flash_text = text
	_flash_timer = 0.8


func _s(p: Vector2) -> Vector2:
	return ORIGIN + p * SHEET_SCALE


# ───────── 계산 함수 (그리기와 시험이 같은 것을 쓴다) ─────────

## 체력 막대 길이 배수 (100 → 1.0, 최대 1.6)
func hp_bar_scale(max_hp := -1.0) -> float:
	if max_hp < 0.0:
		max_hp = _player.max_hp if _player else HP_BASE
	return clampf(max_hp / HP_BASE, 1.0, HP_SCALE_MAX)


## 채움 구간의 화면 px 길이
func hp_bar_width(scale := -1.0) -> float:
	if scale < 0.0:
		scale = hp_bar_scale()
	return HP_FILL.size.x * scale * SHEET_SCALE


## 채움 구간 (화면 좌표)
func hp_fill_rect(scale := -1.0) -> Rect2:
	if scale < 0.0:
		scale = hp_bar_scale()
	return Rect2(_s(HP_FILL.position), Vector2(hp_bar_width(scale), HP_FILL.size.y * SHEET_SCALE))


## 틀 그림 세 조각: [{"dst": 화면 Rect2, "src": 그림 Rect2}, ...] 왼쪽 → (늘어난 만큼 끼운 조각) → 오른쪽 끝.
## 기본 길이(배수 1.0)면 두 조각으로 원래 그림 그대로다.
func hp_frame_pieces(scale := -1.0) -> Array:
	if scale < 0.0:
		scale = hp_bar_scale()
	var tex_size := BAR_HP.get_size()
	var extra := HP_FILL.size.x * (scale - 1.0)
	var base := _s(HP_TRACK_POS)
	var out := []
	out.append({"dst": Rect2(base, Vector2(HP_FRAME_SPLIT, tex_size.y) * SHEET_SCALE), "src": Rect2(0, 0, HP_FRAME_SPLIT, tex_size.y)})
	if extra > 0.5:
		out.append({"dst": Rect2(base + Vector2(HP_FRAME_SPLIT, 0) * SHEET_SCALE, Vector2(extra, tex_size.y) * SHEET_SCALE), "src": HP_FRAME_STRETCH})
	out.append({"dst": Rect2(base + Vector2(HP_FRAME_SPLIT + extra, 0) * SHEET_SCALE, Vector2(tex_size.x - HP_FRAME_SPLIT, tex_size.y) * SHEET_SCALE), "src": Rect2(HP_FRAME_SPLIT, 0, tex_size.x - HP_FRAME_SPLIT, tex_size.y)})
	return out


## 이슬 줄 수 (7개까지 한 줄)
func dew_rows(count := -1) -> int:
	if count < 0:
		count = _player.max_dews if _player else 3
	return maxi(1, ceili(float(count) / DEW_PER_ROW))


## 이슬 자리 (화면 좌표, 그림 왼쪽 위). 첫 자리에서 오른쪽으로 DEW_STEP 간격, 7개 넘으면 둘째 줄.
func dew_slots(count := -1) -> Array[Vector2]:
	if count < 0:
		count = _player.max_dews if _player else 3
	var out: Array[Vector2] = []
	for i in count:
		var col := i % DEW_PER_ROW
		var row := floori(float(i) / DEW_PER_ROW)
		var base: Vector2 = DEW_POS[col] if col < DEW_POS.size() else DEW_POS[DEW_POS.size() - 1] + Vector2(DEW_STEP_EXTRA * (col - DEW_POS.size() + 1), 0)
		out.append(_s(base + Vector2(0, DEW_ROW_STEP * row)))
	return out


## i 번째 이슬의 그림 (세 장을 돌려 쓴다)과 화면 크기
func dew_texture(i: int) -> Texture2D:
	return DEWS[i % DEWS.size()]


func dew_size(i: int) -> Vector2:
	return dew_texture(i).get_size() * SHEET_SCALE


## 성장 표시 항목: [{"kind": "attack"/"heal", "text": "+10%"/"+15"}]. 성장이 없으면 빈 배열.
func growth_items() -> Array:
	var out := []
	var atk := int(round(float(Progress.upgrades.get("attack", 0.0)) * 100.0))
	if atk > 0:
		out.append({"kind": "attack", "text": "+%d%%" % atk})
	var heal := int(round(float(Progress.upgrades.get("heal", 0.0))))
	if heal > 0:
		out.append({"kind": "heal", "text": "+%d" % heal})
	return out


func growth_labels() -> Array[String]:
	var out: Array[String] = []
	for it in growth_items():
		out.append(it["text"])
	return out


## 성장 표시 줄의 시작점 (화면 좌표: 첫 아이콘 가운데 높이의 왼쪽 끝) — 이슬 첫 줄 오른쪽
func growth_origin() -> Vector2:
	var n := mini(_player.max_dews if _player else 3, DEW_PER_ROW)
	var slots := dew_slots(mini(n, DEW_PER_ROW))   # 첫 줄 마지막 이슬의 오른쪽
	return slots[slots.size() - 1] + Vector2(dew_size(mini(n, DEW_PER_ROW) - 1).x + GROWTH_GAP * SHEET_SCALE, DEWS[0].get_height() * 0.5 * SHEET_SCALE)


## 표시할 영혼 목록: 가진 영혼들, 고른 영혼이 그 안에 없으면(다른 묶음의 새 영혼 등) 맨 앞에 더한다
func soul_list() -> Array:
	if _player == null:
		return []
	var souls: Array = _player.owned_souls().duplicate()
	if _player.soul != "" and not souls.has(_player.soul):
		souls.push_front(_player.soul)
	return souls


func soul_color(s: String) -> Color:
	return Player.soul_color_of(s)


## 영혼 이름 줄의 글자: "지금: 바람 (잿빛 잎새의 새)". 영혼이 없으면 "".
func soul_label() -> String:
	if _player == null or _player.soul == "":
		return ""
	return "지금: %s" % _player.soul_name()


## 전환 알림의 큰 글자 ("바람의 영혼"). 알림이 꺼져 있으면 "".
func soul_notice_title() -> String:
	if _soul_notice_timer <= 0.0 or _player == null:
		return ""
	return _player.soul_title(_soul_notice_soul)


func soul_notice_desc() -> String:
	if _soul_notice_timer <= 0.0 or _player == null or not SOUL_NOTICE_SHOW_DESC:
		return ""
	return _player.soul_desc(_soul_notice_soul)


## 알림 큰 글자 기준선의 높이 비율. 보스 등장 이름이 떠 있으면 그 위로 올린다.
func soul_notice_y_ratio() -> float:
	return SOUL_NOTICE_Y_BOSS if _boss_title_showing() else SOUL_NOTICE_Y


## 보스 등장 이름(BossHUD, 3초)이 화면에 떠 있는가
func _boss_title_showing() -> bool:
	var room := get_parent()
	var bhud: Node = room.get_node_or_null("BossHUD") if room else null   # 보스 방에서 CombatHUD 와 BossHUD 는 형제
	if bhud == null:
		return false
	var t = bhud.get("_title")
	return t != null and float(t) > 0.0


## 알림 글자의 투명도 (0~1): 빠르게 떠올라 머물다 사라진다
func soul_notice_alpha() -> float:
	if _soul_notice_timer <= 0.0:
		return 0.0
	var elapsed := SOUL_NOTICE_TIME - _soul_notice_timer
	return clampf(minf(elapsed / SOUL_NOTICE_FADE_IN, _soul_notice_timer / SOUL_NOTICE_FADE_OUT), 0.0, 1.0)


## 빛 가루 개수 글자
func dust_text() -> String:
	return str(Progress.dust)


## 빛 가루 아이콘의 가운데 (화면 좌표): 성장 표시 줄 끝 (성장이 없으면 이슬 줄 바로 오른쪽)
func dust_origin() -> Vector2:
	var o := growth_origin()
	return Vector2(growth_end_x() + DUST_GAP + DUST_ICON, o.y)


## 성장 표시 줄이 끝나는 x (화면 좌표). 성장이 없으면 시작점 그대로.
func growth_end_x() -> float:
	var font := ThemeDB.fallback_font
	var origin := growth_origin()
	var x := origin.x
	for it in growth_items():
		var tx := x + GROWTH_ICON * 1.6 + 4.0
		x = tx + font.get_string_size(it["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, GROWTH_FONT_SIZE).x + 16.0
	return x


## 영혼 줄의 시작점 (화면 좌표, 글자 기준선). 이슬이 두 줄이면 한 줄만큼 아래
func soul_origin() -> Vector2:
	return _s(SOUL_POS + Vector2(0, DEW_ROW_STEP * (dew_rows() - 1)))


## 영혼 원들: [{"soul", "center", "radius", "color", "selected"}]
func soul_dots() -> Array:
	var out := []
	var souls := soul_list()
	var o := soul_origin()
	for i in souls.size():
		var s: String = souls[i]
		var sel := _player != null and s == _player.soul
		out.append({
			"soul": s,
			"center": o + Vector2(SOUL_DOT_R_SEL + SOUL_DOT_GAP * i, -6.0),
			"radius": SOUL_DOT_R_SEL if sel else SOUL_DOT_R,
			"color": soul_color(s),
			"selected": sel,
		})
	return out


# ───────── 그리기 ─────────

func _draw_bar(tex: Texture2D, track_pos: Vector2, fill: Rect2, full_slice: Rect2, empty_slice: Rect2, ratio: float) -> void:
	_canvas.draw_texture_rect(tex, Rect2(_s(track_pos), tex.get_size() * SHEET_SCALE), false)
	var full_w := fill.size.x * clampf(ratio, 0.0, 1.0)
	if full_w > 1.0:
		_canvas.draw_texture_rect_region(tex, Rect2(_s(fill.position), Vector2(full_w, fill.size.y) * SHEET_SCALE), full_slice)
	if fill.size.x - full_w > 1.0:
		_canvas.draw_texture_rect_region(tex, Rect2(_s(fill.position + Vector2(full_w, 0)), Vector2(fill.size.x - full_w, fill.size.y) * SHEET_SCALE), empty_slice)


## 체력 막대: 틀 세 조각 → 찬 부분 → 빈 부분 (길이 배수 scale)
func _draw_hp_bar(ratio: float, scale: float) -> void:
	for piece in hp_frame_pieces(scale):
		_canvas.draw_texture_rect_region(BAR_HP, piece["dst"], piece["src"])
	var fill := hp_fill_rect(scale)
	var full_w := fill.size.x * clampf(ratio, 0.0, 1.0)
	if full_w > 1.0:
		_canvas.draw_texture_rect_region(BAR_HP, Rect2(fill.position, Vector2(full_w, fill.size.y)), HP_RED_SLICE)
	if fill.size.x - full_w > 1.0:
		_canvas.draw_texture_rect_region(BAR_HP, Rect2(fill.position + Vector2(full_w, 0), Vector2(fill.size.x - full_w, fill.size.y)), HP_DARK_SLICE)


func _draw_outlined(font: Font, pos: Vector2, text: String, size: int, color: Color) -> void:
	_canvas.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0.05, 0.04, 0.03, 0.75 * color.a))
	_canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## 작은 검 (위를 향한 칼날, 십자 날밑, 손잡이). c = 가운데, h = 반 높이
func _draw_sword_icon(c: Vector2, h: float) -> void:
	var blade := PackedVector2Array([c + Vector2(0, -h), c + Vector2(h * 0.28, -h * 0.6), c + Vector2(h * 0.22, h * 0.3), c + Vector2(-h * 0.22, h * 0.3), c + Vector2(-h * 0.28, -h * 0.6)])
	var outline := Color(0.08, 0.06, 0.04, 0.8)
	_canvas.draw_colored_polygon(blade, Color(0.92, 0.95, 1.0))
	_canvas.draw_polyline(blade + PackedVector2Array([blade[0]]), outline, 1.2)
	_canvas.draw_line(c + Vector2(0, -h * 0.85), c + Vector2(0, h * 0.25), Color(0.75, 0.82, 0.92), 1.0)
	var guard := Rect2(c + Vector2(-h * 0.6, h * 0.3), Vector2(h * 1.2, h * 0.2))
	_canvas.draw_rect(guard, Color(0.95, 0.8, 0.45))
	_canvas.draw_rect(guard, outline, false, 1.0)
	var grip := Rect2(c + Vector2(-h * 0.13, h * 0.5), Vector2(h * 0.26, h * 0.42))
	_canvas.draw_rect(grip, Color(0.45, 0.3, 0.2))
	_canvas.draw_circle(c + Vector2(0, h), h * 0.17, Color(0.95, 0.8, 0.45))


## 작은 물방울. c = 가운데, h = 반 높이
func _draw_drop_icon(c: Vector2, h: float) -> void:
	var pts := PackedVector2Array()
	var r := h * 0.58
	var cy := h * 0.42   # 둥근 아랫부분 중심
	pts.append(c + Vector2(0, -h))
	for k in range(0, 13):
		var a := -PI * 0.25 + PI * 1.5 * k / 12.0
		pts.append(c + Vector2(cos(a) * r, cy + sin(a) * r))
	_canvas.draw_colored_polygon(pts, Color(0.6, 0.85, 1.0))
	_canvas.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.08, 0.1, 0.16, 0.8), 1.2)
	_canvas.draw_circle(c + Vector2(-r * 0.35, cy - r * 0.2), r * 0.25, Color(1, 1, 1, 0.8))


func _draw_growth(font: Font) -> void:
	var items := growth_items()
	if items.is_empty():
		return
	var origin := growth_origin()
	var x := origin.x
	var cy := origin.y
	for it in items:
		var icon_c := Vector2(x + GROWTH_ICON * 0.7, cy)
		if it["kind"] == "attack":
			_draw_sword_icon(icon_c, GROWTH_ICON)
		else:
			_draw_drop_icon(icon_c, GROWTH_ICON)
		var tx := x + GROWTH_ICON * 1.6 + 4.0
		var text: String = it["text"]
		_draw_outlined(font, Vector2(tx, cy + GROWTH_FONT_SIZE * 0.36), text, GROWTH_FONT_SIZE, Color(1.0, 0.96, 0.85, 0.95))
		x = tx + font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, GROWTH_FONT_SIZE).x + 16.0


func _draw_dews() -> void:
	var slots := dew_slots()
	for i in slots.size():
		var tex := dew_texture(i)
		var size := dew_size(i)
		var pos := slots[i]
		var tint := Color(1.2, 1.2, 1.25, 1.0) if i < _player.dews else Color(0.45, 0.45, 0.5, 0.4)
		var pop: float = _dew_pop.get(i, 0.0)
		if pop > 0.0:
			# 새로 늘어난 이슬: 커졌다 작아지며 빛난다
			var t := 1.0 - pop / DEW_POP_TIME
			var s := sin(PI * t)
			var grow := 1.0 + 0.35 * s
			var center := pos + size * 0.5
			_canvas.draw_circle(center, size.x * 0.8 * grow, Color(1.0, 1.0, 0.85, 0.4 * s))
			for k in 4:
				var a := k * PI * 0.5 + t * 1.2
				var ray := Vector2(cos(a), sin(a)) * size.x * (0.9 + 0.6 * s)
				_canvas.draw_line(center + ray * 0.3, center + ray, Color(1.0, 1.0, 0.9, 0.7 * s), 1.5)
			pos = center - size * grow * 0.5
			size *= grow
			tint = Color(1.2 + 0.9 * s, 1.2 + 0.9 * s, 1.25 + 0.7 * s, 1.0)
		_canvas.draw_texture_rect(tex, Rect2(pos, size), false, tint)


## 빛 가루: 네 갈래 반짝이 + 가운데 점, 그 오른쪽에 개수. 늘어난 순간 "+N" 이 위로 떠오르며 사라진다.
func _draw_dust(font: Font) -> void:
	var c := dust_origin()
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	var glow := 0.25 + 0.2 * pulse + 0.6 * _dust_glow
	_canvas.draw_circle(c, DUST_ICON * (1.3 + 0.6 * _dust_glow), Color(DUST_COLOR.r, DUST_COLOR.g, DUST_COLOR.b, 0.18 * glow))
	var long := DUST_ICON * (1.0 + 0.15 * pulse + 0.4 * _dust_glow)
	var short := DUST_ICON * 0.45
	var outline := Color(0.08, 0.06, 0.03, 0.7)
	for k in 4:
		var a := k * PI * 0.5
		var tip := c + Vector2(cos(a), sin(a)) * long
		var l := c + Vector2(cos(a + PI * 0.5), sin(a + PI * 0.5)) * short * 0.55
		var r := c + Vector2(cos(a - PI * 0.5), sin(a - PI * 0.5)) * short * 0.55
		var tri := PackedVector2Array([tip, l, r])
		_canvas.draw_colored_polygon(tri, Color(1.0, 0.98, 0.85, 0.95))
		_canvas.draw_polyline(tri + PackedVector2Array([tip]), outline, 1.0)
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		_canvas.draw_line(c, c + Vector2(cos(a), sin(a)) * short * (1.0 + 0.6 * _dust_glow), Color(1.0, 0.95, 0.75, 0.6), 1.2)
	_canvas.draw_circle(c, DUST_ICON * 0.32, Color(1, 1, 1, 0.95))
	var tx := c.x + DUST_ICON + 5.0
	_draw_outlined(font, Vector2(tx, c.y + DUST_FONT_SIZE * 0.36), dust_text(), DUST_FONT_SIZE, Color(DUST_COLOR.r, DUST_COLOR.g, DUST_COLOR.b, 0.95))
	for pop in _dust_pops:
		var t: float = 1.0 - pop["t"] / DUST_POP_TIME   # 0 → 1
		var a := clampf(minf(t / 0.12, (1.0 - t) / 0.4), 0.0, 1.0)
		var y := c.y - DUST_POP_RISE * (1.0 - (1.0 - t) * (1.0 - t))
		_draw_outlined(font, Vector2(tx, y + DUST_FONT_SIZE * 0.36 - 4.0), "+%d" % int(pop["amount"]), DUST_FONT_SIZE + 2, Color(1.0, 1.0, 0.85, a))


## 영혼 전환 알림: 화면 가운데 위, 큰 영혼 이름 + 작은 설명. 떠올랐다 사라진다.
func _draw_soul_notice(font: Font) -> void:
	var a := soul_notice_alpha()
	if a <= 0.0:
		return
	var size := _canvas.size
	var col := soul_color(_soul_notice_soul)
	var title := soul_notice_title()
	var desc := soul_notice_desc()
	var elapsed := SOUL_NOTICE_TIME - _soul_notice_timer
	var rise := 14.0 * (1.0 - clampf(elapsed / 0.25, 0.0, 1.0))   # 처음 0.25초 살짝 떠오른다
	var y := size.y * soul_notice_y_ratio() + rise
	var w := 1200.0
	var x := size.x / 2.0 - w / 2.0
	# 뒤에 영혼 색 빛 띠
	_canvas.draw_rect(Rect2(x + 200.0, y - SOUL_NOTICE_TITLE_SIZE * 0.95, w - 400.0, SOUL_NOTICE_TITLE_SIZE * 1.25), Color(col.r, col.g, col.b, 0.1 * a))
	_canvas.draw_string_outline(font, Vector2(x, y), title, HORIZONTAL_ALIGNMENT_CENTER, w, SOUL_NOTICE_TITLE_SIZE, 6, Color(0.05, 0.04, 0.03, 0.8 * a))
	_canvas.draw_string(font, Vector2(x, y), title, HORIZONTAL_ALIGNMENT_CENTER, w, SOUL_NOTICE_TITLE_SIZE, Color(col.r, col.g, col.b, a))
	if desc != "":
		var dy := y + SOUL_NOTICE_DESC_SIZE * 1.9
		_canvas.draw_string_outline(font, Vector2(x, dy), desc, HORIZONTAL_ALIGNMENT_CENTER, w, SOUL_NOTICE_DESC_SIZE, 4, Color(0.05, 0.04, 0.03, 0.75 * a))
		_canvas.draw_string(font, Vector2(x, dy), desc, HORIZONTAL_ALIGNMENT_CENTER, w, SOUL_NOTICE_DESC_SIZE, Color(1, 1, 1, 0.9 * a))


func _draw_souls(font: Font) -> void:
	var dots := soul_dots()
	if dots.is_empty():
		return
	var ratio := _player.soul_cooldown_ratio()
	for d in dots:
		var c: Vector2 = d["center"]
		var r: float = d["radius"]
		var col: Color = d["color"]
		if d["selected"]:
			_canvas.draw_circle(c, r * (1.9 + 0.8 * _soul_flash), Color(col.r, col.g, col.b, 0.18 + 0.45 * _soul_flash))
			_canvas.draw_circle(c, r + 1.5, Color(0.05, 0.04, 0.03, 0.7))
			var body := Color(col.r + 0.3 * _soul_flash, col.g + 0.3 * _soul_flash, col.b + 0.3 * _soul_flash, 1.0)
			if ratio > 0.0:
				body = body.darkened(0.45)   # 쿨다운 중엔 원이 어둡다
			_canvas.draw_circle(c, r, body)
			_canvas.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.3, Color(1, 1, 1, 0.7 if ratio <= 0.0 else 0.35))
			if ratio > 0.0:
				# 쿨다운 호: 위에서 시계 방향으로 차오른다 (밝은 호 = 지난 비율, 어두운 호 = 남은 비율)
				_canvas.draw_arc(c, r + 4.0, -PI / 2.0, -PI / 2.0 + TAU, 40, Color(col.r, col.g, col.b, 0.25), 2.5, true)
				var done := TAU * (1.0 - ratio)
				if done > 0.02:
					_canvas.draw_arc(c, r + 4.0, -PI / 2.0, -PI / 2.0 + done, 40, Color(col.r, col.g, col.b, 0.95), 3.0, true)
		else:
			_canvas.draw_circle(c, r + 1.5, Color(0.05, 0.04, 0.03, 0.5))
			_canvas.draw_circle(c, r, Color(col.r, col.g, col.b, 0.42))
	var o := soul_origin()
	var label := soul_label()
	if label == "":
		return
	if bool(Settings.get_value("debug_hud")):
		# 키 안내는 설명 글자라서 '개발 표시'를 켰을 때만 덧붙인다
		label += "   (%s)" % InputDevice.prompt("soul_ability")
		if _player.owned_souls().size() > 1:
			# 터치 사전에는 soul_next 가 없어서 터치는 버튼 이름을 직접 쓴다
			var nxt := "전환 버튼" if InputDevice.current == InputDevice.Kind.TOUCH else InputDevice.prompt("soul_next")
			label += "   전환 %s" % nxt
	var col := soul_color(_player.soul)
	col.a = 0.9
	col = col.lerp(Color(1, 1, 1, 1), 0.5 * _soul_flash)
	var lx := o.x + SOUL_DOT_R_SEL * 2.0 + SOUL_DOT_GAP * (dots.size() - 1) + 8.0
	_draw_outlined(font, Vector2(lx, o.y), label, SOUL_FONT_SIZE, col)
	# 쿨다운 남은 초: 이름 뒤에 큼직하게 ("7", "6", … "1")
	var cd := _player.soul_cooldown_text()
	if cd != "":
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, SOUL_FONT_SIZE).x
		_draw_outlined(font, Vector2(lx + w + 12.0, o.y + 1.0), cd, SOUL_CD_FONT_SIZE, Color(1, 1, 1, 0.9))


func _on_draw() -> void:
	if _player == null:
		return
	var font := ThemeDB.fallback_font
	var hp_ratio := _player.hp / _player.max_hp
	# 막대 (틀 → 찬 부분 → 빈 부분). 체력은 줄어든 자리를 잠깐 밝게 남긴다.
	_draw_hp_bar(_hp_shown, _hp_scale_shown)
	var fill := hp_fill_rect(_hp_scale_shown)
	if _hp_shown > hp_ratio + 0.002:
		var lost := Rect2(fill.position + Vector2(fill.size.x * hp_ratio, 0), Vector2(fill.size.x * (_hp_shown - hp_ratio), fill.size.y))
		_canvas.draw_rect(lost, Color(1.0, 0.9, 0.7, 0.55))
	if _hp_grow_flash > 0.0:
		_canvas.draw_rect(fill, Color(1.0, 0.95, 0.8, 0.55 * _hp_grow_flash))
	_draw_bar(BAR_GUARD, GUARD_TRACK_POS, GUARD_FILL, GUARD_GREEN_SLICE, GUARD_DARK_SLICE, _player.guard / _player.max_guard)
	if _guard_flash > 0.0:
		_canvas.draw_rect(Rect2(_s(GUARD_FILL.position), GUARD_FILL.size * SHEET_SCALE), Color(0.56, 0.83, 1.0, 0.6 * _guard_flash))
	# 엠블럼과 씨앗의 빛
	_canvas.draw_texture_rect(EMBLEM, Rect2(_s(EMBLEM_POS), EMBLEM.get_size() * SHEET_SCALE), false)
	var low := hp_ratio < 0.3
	var pulse := 0.75 + 0.25 * sin(_time * (7.0 if low else 2.2))
	var glow_color := Color(2.2, 0.9, 0.6, 0.16 * pulse) if low else Color(2.0, 1.7, 1.0, 0.1 * pulse)
	_canvas.draw_circle(_s(SEED_CENTER), 40.0 * SHEET_SCALE * (1.2 + 0.4 * pulse), glow_color)
	# 이슬 방울 · 성장 표시 · 빛 가루 · 영혼
	_draw_dews()
	_draw_growth(font)
	_draw_dust(font)
	_draw_souls(font)
	_draw_soul_notice(font)
	# 메시지
	var size := _canvas.size
	if _message_timer > 0.0:
		var a := clampf(_message_timer / 0.5, 0.0, 1.0)
		_canvas.draw_string(font, Vector2(size.x / 2.0 - 500, size.y * 0.3), _message, HORIZONTAL_ALIGNMENT_CENTER, 1000, 40, Color(1, 1, 1, a))
	if _flash_timer > 0.0:
		var a2 := clampf(_flash_timer / 0.3, 0.0, 1.0)
		_canvas.draw_string(font, Vector2(size.x / 2.0 - 300, size.y * 0.42), _flash_text, HORIZONTAL_ALIGNMENT_CENTER, 600, 34, Color("ffd46a", a2))

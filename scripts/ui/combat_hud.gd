extends CanvasLayer
## 전투 표시: 체력, 가드 게이지, 이슬 방울, 성장 표시(공격·회복), 영혼, 가운데 메시지.
## 그림: art/ui/ (기획자의 HUD 시트에서 잘라낸 조각). 좌표 상수는 시트(2156×729) 기준이고
## 화면에는 SHEET_SCALE 로 줄여 그린다. 조각 자르기는 tools/cut_hud.gd.
##
## 성장이 HUD 에 반영되는 규칙
## - 이슬: max_dews 만큼 겹치지 않게 늘어놓는다 (한 줄 7개, 넘으면 둘째 줄). 새로 늘어난 이슬은 0.6초 반짝이며 커졌다 작아진다.
##   최대 8개 (Progress.MAX_DEWS, 2026-10-20 기획자 결정) → 가득하면 첫 줄 7 + 둘째 줄 1. 넘친 이슬은 회복량 성장(물방울 "+N")에 더해 보인다.
## - 체력 막대: max_hp 에 비례해 길어진다 (100 기준 1.0, 최대 1.6배). 틀 그림은 세 조각(왼쪽 / 늘림 조각 / 오른쪽 끝)으로 그려
##   끝 장식이 깨지지 않는다. 늘어나는 순간 0.5초에 걸쳐 자라며 한 번 번쩍.
## - 공격 배수·회복량 성장: 이슬 오른쪽에 작은 검 / 물방울 아이콘 + "+10%" / "+15" (성장이 없으면 아무것도 없음).
## - 영혼: 가진 영혼마다 작은 원, 고른 것은 밝고 크게 + "지금: 바람 (잿빛 잎새의 새)" 이름. 전환 순간 0.3초 번쩍.
##   쿨다운 중엔 고른 원 둘레에 차오르는 호(지난 비율)와 남은 초 숫자("7, 6, … 1") — 키보드·패드로 놀 때도 터치 버튼과 같은 정보.
## - 영혼 전환 알림 (2026-10-19 기획자 요청 "지금 어느 영혼인지 모른다"): 전환 순간 화면 가운데 위에 1.2초 동안 큰 글자("바람의 영혼", 영혼 색)와
##   작은 설명 한 줄("커다란 돌풍 — … / 쿨 5초", SOUL_NOTICE_SHOW_DESC 로 끌 수 있음)이 떠올랐다 사라진다.
##   보스 등장 이름이 떠 있는 3초 동안은 그 위(높이 0.105)로 올라간다.
## - 빛 가루 (재화, Progress.dust) — **네모 칸 (2026-10-19 기획자 요청 "재화를 네모 칸으로")**: 영혼 줄 아래, 왼쪽 끝을 맞춘 금테 칸.
##   HUD 그림과 같은 결(짙은 바깥선 + 금빛 테 + 안쪽 옅은 빛 선 + 어두운 바탕)에 오른쪽 끝은 가드 막대 그림의 잎 장식을 그대로 붙였다.
##   안에 빛 가루 그림(art/ui/touch/touch_dust.png)과 숫자(천 단위 쉼표). 늘어나면 숫자가 0.6초에 걸쳐 차오르고(count-up) 칸이 한 번 빛나며 그림이 커졌다 돌아온다,
##   잎 장식 오른쪽에 "+N" 이 나타나 오른쪽으로 흘러가며 사라진다 (장면 전환 중 — 메뉴의 '불러오기' 등 — 에는 숫자만 바로 바뀐다). 줄어들면(성장에 씀) 바로 바뀐다.
##   자리: 이슬이 두 줄이면 영혼 줄과 함께 내려간다. 체력·이슬·영혼·위 모서리 터치 버튼(메뉴·지도)·왼쪽 터치 버튼(회복)·보스 띠·대화 상자·전환 알림과 겹치지 않는다
##   (시험: tools/probe_hud.tscn 이 1920×1080·2338×1080·4:3 아이패드 × 터치 버튼 크기 3단계에서 확인).
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
## v1.1.0: 가드 막대 = 스태미너 막대. 최대 스태미너(100/103/106/109)만큼 길이가 늘어난다 (체력 막대와 같은 방식, 숫자 없음).
## 틀 그림(1616×185)을 가르는 자리 (그림 px): 막대 테두리만 있고 잎 장식이 없는 곳. 늘어난 만큼 민무늬 조각을 끼운다.
const GUARD_BASE := 100.0
const GUARD_SCALE_MAX := 1.09
const GUARD_FRAME_SPLIT := 1000.0
const GUARD_FRAME_STRETCH := Rect2(990, 0, 20, 185)
## 스태미너가 모자라 공격을 못 했을 때 막대가 붉게 번쩍이는 시간 / 수액의 맥동으로 찼을 때 밝게 번쩍이는 시간 (초)
const STAMINA_REFUSE_TIME := 0.35
const STAMINA_PULSE_TIME := 0.4
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
## 빛 가루 칸 (화면 px)
const DUST_ICON_TEX := preload("res://art/ui/touch/touch_dust.png")
const DUST_BOX_GAP := 22.0          # 영혼 줄 글자 기준선 아래로 이만큼 띄워 칸 윗변 (영혼 원이 번쩍일 때 번짐이 닿지 않게)
const DUST_BOX_X := 26.0            # 칸 왼쪽 (영혼 원 줄과 맞춤)
## 화면 왼쪽이 가려지는 기기(노치 있는 아이폰을 가로로)에서 영혼 줄·빛 가루 칸을 안전 영역 안으로 민다 (2026-10-20 QA).
## 이 둘은 화면 세로 가운데(노치 자리, 1080 기준 y 239~841)에 있어서 노치를 왼쪽에 두고 쥐면 빛 가루 그림과 첫 숫자가 가려졌다.
## 가려지는 폭은 기기의 안전 영역(DisplayServer.get_display_safe_area)으로 잰다 — 모바일에서만, 맥·아이패드는 0.
## 시험은 safe_left_override(캔버스 px)로 흉내 낸다. 위쪽의 체력 막대·씨앗은 노치 띠 밖이라 그대로.
const SAFE_LEFT_GAP := 6.0          # 안전 영역 안쪽으로 더 띄우는 거리
const SAFE_LEFT_MAX := 160.0
var safe_left_override := -1.0
const DUST_BOX_H := 42.0
const DUST_BOX_MIN_W := 150.0
const DUST_BOX_PAD := 14.0          # 숫자 오른쪽 여백
const DUST_ICON_SIZE := 40.0        # 칸 안 빛 가루 그림 크기
const DUST_FONT_SIZE := 26
## 오른쪽 끝 잎 장식: 가드 막대 그림(hud_bar_guard.png) 끝의 잎 줄기 (그림 px)
const DUST_ORNAMENT_SRC := Rect2(1158, 16, 112, 84)
const DUST_ORNAMENT_SCALE := 0.5
const DUST_COUNT_TIME := 0.6        # 숫자가 차오르는 시간
const DUST_POP_TIME := 1.1          # "+N" 이 나타나 사라지는 시간 (칸이 빛나는 것도 같은 시간에 가라앉는다)
const DUST_POP_RISE := 26.0         # "+N" 이 오른쪽으로 흘러가는 거리 (화면 px; 위로 뜨면 영혼 줄 글자에 닿아서 옆으로)
const DUST_COLOR := Color(1.0, 0.95, 0.72)
## 칸 색 (가드 막대 그림에서 뽑은 색: 짙은 바깥선 / 금테 / 어두운 바탕)
const DUST_INK := Color(0.16, 0.1, 0.03, 0.9)
const DUST_GOLD := Color(0.88, 0.71, 0.46)
const DUST_BG := Color(0.12, 0.115, 0.09, 0.8)

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
var _stamina_refuse := 0.0   # 남은 붉은 번쩍임 (초)
var _stamina_pulse := 0.0    # 남은 맥동 번쩍임 (초)
var _guard_pieces: Array = []      # 가드 막대 틀 조각 (길이 배수가 바뀔 때만 다시 만든다 — 매 프레임 배열을 새로 만들지 않게)
var _guard_pieces_scale := -1.0
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
var _dust_glow := 0.0       # 늘어난 순간 칸이 빛나고 그림이 커졌다 가라앉음
var _dust_shown := 0.0      # 칸에 보이는 숫자 (차오르는 중엔 Progress.dust 보다 작다)
var _dust_rate := 0.0       # 차오르는 빠르기 (개 / 초)
var _box_outer: StyleBoxFlat
var _box_gold: StyleBoxFlat
var _box_inner: StyleBoxFlat


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
	_dust_shown = float(Progress.dust)
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # 빛 가루 그림(192px)을 작게 그려도 매끈하게
	_make_box_styles()


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
			_player.stamina_refused.connect(func(): _stamina_refuse = STAMINA_REFUSE_TIME)
			_player.stamina_pulsed.connect(func(_a): _stamina_pulse = STAMINA_PULSE_TIME)
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
	_stamina_refuse = maxf(_stamina_refuse - delta, 0.0)
	_stamina_pulse = maxf(_stamina_pulse - delta, 0.0)
	_soul_flash = maxf(_soul_flash - delta / SOUL_FLASH_TIME, 0.0)
	_hp_grow_flash = maxf(_hp_grow_flash - delta / HP_GROW_TIME, 0.0)
	_soul_notice_timer = maxf(_soul_notice_timer - delta, 0.0)
	_dust_glow = maxf(_dust_glow - delta / DUST_POP_TIME, 0.0)
	# 빛 가루 숫자 차오르기 (줄어드는 것은 _on_dust_changed 에서 바로)
	if _dust_shown < float(Progress.dust):
		_dust_shown = minf(_dust_shown + maxf(_dust_rate, 20.0) * delta, float(Progress.dust))
	elif _dust_shown > float(Progress.dust):
		_dust_shown = float(Progress.dust)
	if _scene_changing() and not _dust_pops.is_empty():
		# 메뉴의 '불러오기'는 빛 가루를 넣고(dust_changed) 같은 호출에서 장면 전환을 시작한다 → 번 것이 아니니 떠오르는 글자를 지운다
		_dust_pops.clear()
		_dust_glow = 0.0
		_dust_shown = float(Progress.dust)
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
		"dews":
			# 이슬이 가득(8개)해 회복량으로 바뀐 몫은 그렇게 보인다 (Progress.dew_overflow_of — add_upgrade 뒤라 이미 더해졌다)
			var over := Progress.dew_overflow_of(amount)
			var added := roundi(amount) - over
			if over <= 0:
				text = "이슬 +%d" % added
			elif added <= 0:
				text = "이슬 가득 · 회복 +%d" % int(round(over * Progress.DEW_OVERFLOW_HEAL))
			else:
				text = "이슬 +%d · 회복 +%d" % [added, int(round(over * Progress.DEW_OVERFLOW_HEAL))]
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
	if diff > 0 and not _scene_changing():
		_dust_pops.append({"amount": diff, "t": DUST_POP_TIME})
		_dust_glow = 1.0
		# 지금 보이는 숫자에서 새 값까지 DUST_COUNT_TIME 에 차오르게
		_dust_rate = (float(amount) - _dust_shown) / DUST_COUNT_TIME
	else:
		_dust_shown = float(amount)   # 썼거나(줄어듦) 불러오기 중: 바로


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


## 가드(스태미너) 막대 길이 배수 (100 → 1.0, 109 → 1.09)
func guard_bar_scale(max_guard := -1.0) -> float:
	if max_guard < 0.0:
		max_guard = _player.max_guard if _player else GUARD_BASE
	return clampf(max_guard / GUARD_BASE, 1.0, GUARD_SCALE_MAX)


## 가드 막대 채움 구간 (화면 좌표)
func guard_fill_rect(scale := -1.0) -> Rect2:
	if scale < 0.0:
		scale = guard_bar_scale()
	return Rect2(_s(GUARD_FILL.position), Vector2(GUARD_FILL.size.x * scale, GUARD_FILL.size.y) * SHEET_SCALE)


## 가드 막대 틀 조각 (체력 막대 hp_frame_pieces 와 같은 방식): 왼쪽 → (늘어난 만큼 끼운 조각) → 오른쪽 끝
func guard_frame_pieces(scale := -1.0) -> Array:
	if scale < 0.0:
		scale = guard_bar_scale()
	var tex_size := BAR_GUARD.get_size()
	var extra := GUARD_FILL.size.x * (scale - 1.0)
	var base := _s(GUARD_TRACK_POS)
	var out := []
	out.append({"dst": Rect2(base, Vector2(GUARD_FRAME_SPLIT, tex_size.y) * SHEET_SCALE), "src": Rect2(0, 0, GUARD_FRAME_SPLIT, tex_size.y)})
	if extra > 0.5:
		out.append({"dst": Rect2(base + Vector2(GUARD_FRAME_SPLIT, 0) * SHEET_SCALE, Vector2(extra, tex_size.y) * SHEET_SCALE), "src": GUARD_FRAME_STRETCH})
	out.append({"dst": Rect2(base + Vector2(GUARD_FRAME_SPLIT + extra, 0) * SHEET_SCALE, Vector2(tex_size.x - GUARD_FRAME_SPLIT, tex_size.y) * SHEET_SCALE), "src": Rect2(GUARD_FRAME_SPLIT, 0, tex_size.x - GUARD_FRAME_SPLIT, tex_size.y)})
	return out


## 가드(스태미너) 막대: 틀 → 찬 부분 → 빈 부분 (길이 배수 scale)
func _draw_guard_bar(ratio: float, scale: float) -> void:
	if not is_equal_approx(scale, _guard_pieces_scale):
		_guard_pieces = guard_frame_pieces(scale)
		_guard_pieces_scale = scale
	for piece in _guard_pieces:
		_canvas.draw_texture_rect_region(BAR_GUARD, piece["dst"], piece["src"])
	var fill := guard_fill_rect(scale)
	var full_w := fill.size.x * clampf(ratio, 0.0, 1.0)
	if full_w > 1.0:
		_canvas.draw_texture_rect_region(BAR_GUARD, Rect2(fill.position, Vector2(full_w, fill.size.y)), GUARD_GREEN_SLICE)
	if fill.size.x - full_w > 1.0:
		_canvas.draw_texture_rect_region(BAR_GUARD, Rect2(fill.position + Vector2(full_w, 0), Vector2(fill.size.x - full_w, fill.size.y)), GUARD_DARK_SLICE)


## 그릴 이슬 수: 소녀의 최대 이슬 (상한 Progress.MAX_DEWS 를 넘지 않게 한 번 더 막는다)
func dew_count() -> int:
	return mini(_player.max_dews if _player else Progress.BASE_DEWS, Progress.MAX_DEWS)


## 이슬 줄 수 (7개까지 한 줄)
func dew_rows(count := -1) -> int:
	if count < 0:
		count = dew_count()
	return maxi(1, ceili(float(count) / DEW_PER_ROW))


## 이슬 자리 (화면 좌표, 그림 왼쪽 위). 첫 자리에서 오른쪽으로 DEW_STEP 간격, 7개 넘으면 둘째 줄.
func dew_slots(count := -1) -> Array[Vector2]:
	if count < 0:
		count = dew_count()
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
	var heal := int(round(Progress.heal_bonus()))   # 회복량 성장 + 넘친 이슬(하나마다 +10)
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
	var n := mini(dew_count(), DEW_PER_ROW)
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
## 보스 러시 시계(BossRushHUD, 화면 위 가운데)와 겹치면 시계 아래로 내리고, 그때 보스 등장 이름도 떠 있으면 이름 아래로 (2026-10-20 통합).
func soul_notice_y_ratio() -> float:
	var r := SOUL_NOTICE_Y_BOSS if _boss_title_showing() else SOUL_NOTICE_Y
	var clock := rush_clock_rect()
	if clock.size.y <= 0.0:
		return r
	var h := _canvas.size.y if _canvas and _canvas.size.y > 0.0 else 1080.0
	var y := h * r
	var lift := SOUL_NOTICE_TITLE_SIZE * 0.95   # 기준선에서 띠 위 끝까지
	if y - lift < clock.end.y + 8.0:
		y = clock.end.y + 8.0 + lift
		var below := _boss_title_bottom()
		if below > 0.0:
			y = maxf(y, below + 16.0 + lift)
	return y / h


## 보스 러시 시계 판의 자리 (화면 좌표). 러시가 아니면 빈 사각형.
func rush_clock_rect() -> Rect2:
	var room := get_parent()
	var rh: Node = room.get_node_or_null("BossRushHUD") if room else null
	if rh == null or not rh.has_method("panel_rect") or rh.get("_canvas") == null:
		return Rect2()
	return rh.panel_rect()


## 보스 등장 이름(부제 포함)의 아래 끝 y (화면 px). 이름이 떠 있지 않으면 -1.
func _boss_title_bottom() -> float:
	if not _boss_title_showing():
		return -1.0
	var bhud: Node = get_parent().get_node_or_null("BossHUD")
	if bhud == null or not bhud.has_method("title_y"):
		return -1.0
	return float(bhud.title_y()) + 52.0   # 부제 기준선(+44) + 글자 아래 끝


## 보스 등장 이름(BossHUD, 3초)이 화면에 떠 있는가
func _boss_title_showing() -> bool:
	var room := get_parent()
	var bhud: Node = room.get_node_or_null("BossHUD") if room else null   # 보스 방에서 CombatHUD 와 BossHUD 는 형제
	if bhud == null:
		return false
	var t = bhud.get("_title")
	return t != null and float(t) > 0.0


## HUD 덩어리(체력·가드 막대, 이슬, 성장 표시, 빛 가루)의 오른쪽 끝 x (화면 px).
## 영혼 전환 알림·보스 등장 이름이 이 오른쪽에 서서 HUD 를 덮지 않게 한다 (2026-10-19 검수: 체력 180·이슬 9 에서 겹쳤다).
## y0~y1 을 주면 그 높이에 걸친 것만 센다 (예: 화면 위 끝의 체력 막대는 그 아래 높이의 글자와 겹치지 않는다).
func hud_right_x(y0 := -INF, y1 := INF) -> float:
	var font := ThemeDB.fallback_font
	var rects: Array[Rect2] = []
	for piece in hp_frame_pieces(maxf(_hp_scale_shown, hp_bar_scale())):
		rects.append(piece["dst"])
	# 가드 막대 그림(185px)의 아래쪽은 투명이라 보이는 높이(약 120px)만 센다 (최대 스태미너만큼 늘어난 길이 포함)
	rects.append(Rect2(_s(GUARD_TRACK_POS), Vector2(BAR_GUARD.get_width() + GUARD_FILL.size.x * (guard_bar_scale() - 1.0), 120.0) * SHEET_SCALE))
	var slots := dew_slots()
	for i in slots.size():
		rects.append(Rect2(slots[i], dew_size(i)))
	if dust_box_shown():
		rects.append(dust_box_full_rect())
	if _player:
		var o := soul_origin()
		var label := soul_label()
		var lx := o.x + SOUL_DOT_R_SEL * 2.0 + SOUL_DOT_GAP * maxi(soul_list().size() - 1, 0) + 8.0
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, SOUL_FONT_SIZE).x + 12.0 + font.get_string_size("7", HORIZONTAL_ALIGNMENT_LEFT, -1, SOUL_CD_FONT_SIZE).x
		rects.append(Rect2(o.x, o.y - SOUL_CD_FONT_SIZE, lx - o.x + lw, SOUL_CD_FONT_SIZE + 8.0))
	var right := 0.0
	for r in rects:
		if r.end.y >= y0 and r.position.y <= y1:
			right = maxf(right, r.end.x)
	return right


## HUD 덩어리의 아래 끝 y (화면 px): 빛 가루 칸 아래 (영혼 줄보다 아래에 있다). 칸이 숨었으면 영혼 줄 아래.
func hud_bottom_y() -> float:
	if not dust_box_shown():
		return soul_origin().y + 12.0
	return maxf(soul_origin().y + 12.0, dust_box_full_rect().end.y + 4.0)


## 빛 가루 칸을 보이는가. 보스 러시 동안은 숨긴다 (러시에는 빛 가루가 없고 러시용 빈 진행이라 늘 0 — 2026-10-20 통합).
func dust_box_shown() -> bool:
	return not BossRush.active


## 영혼 전환 알림의 띠 (화면 좌표). 글자 폭에 맞춘 띠를 HUD 오른쪽 끝보다 오른쪽에 둔다 (화면이 넓으면 가운데).
func soul_notice_rect() -> Rect2:
	var font := ThemeDB.fallback_font
	var size := _canvas.size if _canvas else Vector2(1920, 1080)
	var tw := font.get_string_size(soul_notice_title(), HORIZONTAL_ALIGNMENT_LEFT, -1, SOUL_NOTICE_TITLE_SIZE).x
	var dw := font.get_string_size(soul_notice_desc(), HORIZONTAL_ALIGNMENT_LEFT, -1, SOUL_NOTICE_DESC_SIZE).x
	var w := maxf(maxf(tw, dw) + 120.0, 420.0)
	var y := size.y * soul_notice_y_ratio()
	var top := y - SOUL_NOTICE_TITLE_SIZE * 0.95
	var h := SOUL_NOTICE_TITLE_SIZE * 1.25 + (SOUL_NOTICE_DESC_SIZE * 1.9 if soul_notice_desc() != "" else 0.0)
	var cx := maxf(size.x / 2.0, hud_right_x(top, top + h) + 40.0 + w / 2.0)
	cx = minf(cx, size.x - 130.0 - w / 2.0)   # 오른쪽 위 '지도' 터치 버튼 자리는 비운다
	return Rect2(cx - w / 2.0, top, w, h)


## 알림 글자의 투명도 (0~1): 빠르게 떠올라 머물다 사라진다
func soul_notice_alpha() -> float:
	if _soul_notice_timer <= 0.0:
		return 0.0
	var elapsed := SOUL_NOTICE_TIME - _soul_notice_timer
	return clampf(minf(elapsed / SOUL_NOTICE_FADE_IN, _soul_notice_timer / SOUL_NOTICE_FADE_OUT), 0.0, 1.0)


## 빛 가루 개수 글자 (Progress.dust 그대로 — 칸이 차오르는 중이어도 목표 값)
func dust_text() -> String:
	return str(Progress.dust)


## 칸에 지금 보이는 숫자 (차오르는 중의 값, 천 단위 쉼표: "1,234")
func dust_shown_text() -> String:
	return _thousands(int(round(_dust_shown)))


static func _thousands(n: int) -> String:
	var t := str(absi(n))
	var out := ""
	while t.length() > 3:
		out = "," + t.substr(t.length() - 3) + out
		t = t.substr(0, t.length() - 3)
	return ("-" if n < 0 else "") + t + out


## 빛 가루 칸 (화면 좌표, 부풀기 전). 영혼 줄 아래, 너비는 목표 숫자의 폭에 맞춘다 (차오르는 동안 칸이 들썩이지 않게).
func dust_box_rect() -> Rect2:
	var font := ThemeDB.fallback_font
	var tw := font.get_string_size(_thousands(Progress.dust), HORIZONTAL_ALIGNMENT_LEFT, -1, DUST_FONT_SIZE).x
	var w := maxf(DUST_BOX_MIN_W, 8.0 + DUST_ICON_SIZE + 6.0 + tw + DUST_BOX_PAD)
	var top := soul_origin().y + DUST_BOX_GAP
	return Rect2(DUST_BOX_X + notch_shift(), top, w, DUST_BOX_H)


## 칸 오른쪽 끝의 잎 장식 자리 (화면 좌표)
func dust_ornament_rect() -> Rect2:
	var box := dust_box_rect()
	var sz := DUST_ORNAMENT_SRC.size * DUST_ORNAMENT_SCALE
	return Rect2(Vector2(box.end.x - 10.0, box.get_center().y - sz.y * 0.52), sz)


## 칸 + 짙은 바깥선 + 잎 장식을 합친 자리 (겹침 검사용)
func dust_box_full_rect() -> Rect2:
	return dust_box_rect().grow(2.0).merge(dust_ornament_rect())


## "+N" 이 나타나 흘러가는 자리 (겹침 검사용)
func dust_pop_rect() -> Rect2:
	var orn := dust_ornament_rect()
	return Rect2(orn.end.x + 2.0, dust_box_rect().get_center().y - 20.0, 150.0 + DUST_POP_RISE, 34.0)


## 빛 가루 그림의 가운데 (화면 좌표): 칸 왼쪽 안
func dust_origin() -> Vector2:
	var box := dust_box_rect()
	return Vector2(box.position.x + 8.0 + DUST_ICON_SIZE * 0.5, box.get_center().y)


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
	return _s(SOUL_POS + Vector2(0, DEW_ROW_STEP * (dew_rows() - 1))) + Vector2(notch_shift(), 0.0)


## 기기 화면 왼쪽에서 가려지는 폭 (캔버스 px). 모바일 기기에서만 안전 영역으로 잰다.
func safe_left_inset() -> float:
	if safe_left_override >= 0.0:
		return safe_left_override
	if not OS.has_feature("mobile"):
		return 0.0
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return 0.0
	var safe := DisplayServer.get_display_safe_area()
	var canvas_w := _canvas.size.x if _canvas and _canvas.size.x > 0.0 else get_viewport().get_visible_rect().size.x
	return clampf(float(safe.position.x - DisplayServer.screen_get_position().x) / float(win.x) * canvas_w, 0.0, SAFE_LEFT_MAX)


## 영혼 줄·빛 가루 칸을 오른쪽으로 미는 거리 (가려지는 폭 + SAFE_LEFT_GAP 이 칸 왼쪽 DUST_BOX_X 보다 크면 그만큼)
func notch_shift() -> float:
	return maxf(0.0, safe_left_inset() + SAFE_LEFT_GAP - DUST_BOX_X)


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


## 칸 테두리 모양 (한 번만 만든다): 짙은 바깥선 / 금테 / 안쪽 옅은 빛 선
func _make_box_styles() -> void:
	_box_outer = StyleBoxFlat.new()
	_box_outer.bg_color = DUST_INK
	_box_outer.set_corner_radius_all(9)
	_box_outer.anti_aliasing = true
	_box_gold = StyleBoxFlat.new()
	_box_gold.bg_color = DUST_BG
	_box_gold.border_color = DUST_GOLD
	_box_gold.set_border_width_all(3)
	_box_gold.set_corner_radius_all(7)
	_box_gold.anti_aliasing = true
	_box_inner = StyleBoxFlat.new()
	_box_inner.draw_center = false
	_box_inner.border_color = Color(1.0, 0.93, 0.72, 0.38)
	_box_inner.set_border_width_all(1)
	_box_inner.set_corner_radius_all(4)
	_box_inner.anti_aliasing = true


## 빛 가루 칸: 금테 칸 + 오른쪽 잎 장식 + 빛 가루 그림 + 숫자. 늘어난 순간 칸 안이 빛나고 그림이 커졌다 돌아오며, 잎 장식 오른쪽에 "+N".
## (칸 자체는 커지지 않는다 — 바로 아래 왼쪽 터치 버튼(회복)과 몇 px 떨어져 있어서)
func _draw_dust(font: Font) -> void:
	var box := dust_box_rect()
	var s := sin(PI * clampf(1.0 - _dust_glow, 0.0, 1.0)) * minf(_dust_glow * 4.0, 1.0)   # 0 → 1 → 0 (처음 빠르게)
	# 잎 장식 (칸 뒤에 깔아 칸 테두리가 줄기 밑동을 덮는다)
	var orn := dust_ornament_rect()
	_canvas.draw_texture_rect_region(BAR_GUARD, orn, DUST_ORNAMENT_SRC)
	_canvas.draw_style_box(_box_outer, box.grow(2.0))
	_canvas.draw_style_box(_box_gold, box)
	if s > 0.01:
		_canvas.draw_rect(box.grow(-3.0), Color(1.0, 0.88, 0.55, 0.22 * s))
	_canvas.draw_style_box(_box_inner, box.grow(-4.5))
	# 빛 가루 그림 (천천히 숨쉬듯 밝기, 늘어난 순간 커짐)
	var c := dust_origin()
	var pulse := 0.5 + 0.5 * sin(_time * 3.0)
	var isz := DUST_ICON_SIZE * (1.0 + 0.18 * s)
	_canvas.draw_texture_rect(DUST_ICON_TEX, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(1, 1, 1, 0.88 + 0.12 * pulse))
	var tx := box.position.x + 8.0 + DUST_ICON_SIZE + 6.0
	var ty := box.get_center().y + DUST_FONT_SIZE * 0.36
	var num_col := DUST_COLOR.lerp(Color(1, 1, 1), 0.6 * s)
	_draw_outlined(font, Vector2(tx, ty), dust_shown_text(), DUST_FONT_SIZE, num_col)
	for pop in _dust_pops:
		var t: float = 1.0 - pop["t"] / DUST_POP_TIME   # 0 → 1
		var a := clampf(minf(t / 0.12, (1.0 - t) / 0.4), 0.0, 1.0)
		var x := orn.end.x + 4.0 + DUST_POP_RISE * (1.0 - (1.0 - t) * (1.0 - t))
		_draw_outlined(font, Vector2(x, box.get_center().y + 8.0), "+%s" % _thousands(int(pop["amount"])), 22, Color(1.0, 1.0, 0.85, a))


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
	var box := soul_notice_rect()
	var w := box.size.x
	var x := box.position.x
	# 뒤에 영혼 색 빛 띠
	_canvas.draw_rect(Rect2(x, y - SOUL_NOTICE_TITLE_SIZE * 0.95, w, SOUL_NOTICE_TITLE_SIZE * 1.25), Color(col.r, col.g, col.b, 0.1 * a))
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
	# 가드 막대 = 스태미너 막대 (v1.1.0): 최대 스태미너만큼 길어지고, 모자라 공격을 못 하면 붉게 / 수액의 맥동으로 차면 밝게 번쩍
	var gfill := guard_fill_rect()
	_draw_guard_bar(_player.guard / maxf(_player.max_guard, 1.0), guard_bar_scale())
	if _guard_flash > 0.0:
		_canvas.draw_rect(gfill, Color(0.56, 0.83, 1.0, 0.6 * _guard_flash))
	if _stamina_refuse > 0.0:
		# 남은 양은 보이게: 빈 부분은 진하게, 찬 부분은 옅게 붉힌다
		var ra := _stamina_refuse / STAMINA_REFUSE_TIME
		var cut := gfill.size.x * clampf(_player.guard / maxf(_player.max_guard, 1.0), 0.0, 1.0)
		_canvas.draw_rect(Rect2(gfill.position, Vector2(cut, gfill.size.y)), Color(1.0, 0.3, 0.2, 0.3 * ra))
		_canvas.draw_rect(Rect2(gfill.position + Vector2(cut, 0.0), Vector2(gfill.size.x - cut, gfill.size.y)), Color(1.0, 0.18, 0.12, 0.75 * ra))
	if _stamina_pulse > 0.0:
		_canvas.draw_rect(gfill, Color(0.75, 1.0, 0.85, 0.5 * _stamina_pulse / STAMINA_PULSE_TIME))
	# 엠블럼과 씨앗의 빛
	_canvas.draw_texture_rect(EMBLEM, Rect2(_s(EMBLEM_POS), EMBLEM.get_size() * SHEET_SCALE), false)
	var low := hp_ratio < 0.3
	var pulse := 0.75 + 0.25 * sin(_time * (7.0 if low else 2.2))
	var glow_color := Color(2.2, 0.9, 0.6, 0.16 * pulse) if low else Color(2.0, 1.7, 1.0, 0.1 * pulse)
	_canvas.draw_circle(_s(SEED_CENTER), 40.0 * SHEET_SCALE * (1.2 + 0.4 * pulse), glow_color)
	# 이슬 방울 · 성장 표시 · 빛 가루 · 영혼
	_draw_dews()
	_draw_growth(font)
	if dust_box_shown():
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
		# 어두운 테두리: 붉게 빛나는 보스 몸 위에 겹쳐도 읽히게 (2026-10-19 검수)
		_canvas.draw_string_outline(font, Vector2(size.x / 2.0 - 300, size.y * 0.42), _flash_text, HORIZONTAL_ALIGNMENT_CENTER, 600, 34, 6, Color(0.08, 0.04, 0.02, 0.85 * a2))
		_canvas.draw_string(font, Vector2(size.x / 2.0 - 300, size.y * 0.42), _flash_text, HORIZONTAL_ALIGNMENT_CENTER, 600, 34, Color("ffd46a", a2))

extends CanvasLayer
class_name MapScreen
## 지도. 방문한 방들을 이어진 자리에 그리고, 지금 있는 방과 소녀의 위치, 달빛풀, 보스 방을 표시한다.
## 방의 자리는 Room.map_offset (세계 좌표 기준 방의 왼쪽 위), 크기는 Room.bounds.
##
## 확대·이동 (2026-10-19 기획자 요청: 방이 41개가 되며 지도가 너무 작아졌다)
## - 열면 **지금 있는 방이 가운데**, 읽기 좋은 배율(ZOOM_OPEN)로 시작한다.
## - 터치: 두 손가락 벌리기·오므리기 = 확대·축소, 한 손가락 끌기 = 이동, 두 번 누르기 = 처음대로(지금 방 가운데).
##   (예전엔 화면 아무 데나 누르면 닫혔다 → 이제 닫기는 오른쪽 위 ✕ — 지도 버튼과 같은 자리라 한 번 더 누르면 닫힌다)
## - 마우스: 휠 = 커서 자리를 중심으로 확대·축소, 끌기 = 이동 (마우스 누름은 터치로도 들어온다: emulate_touch_from_mouse),
##   맥 트랙패드 오므리기·두 손가락 밀기도 받는다.
## - 키보드·컨트롤러: 이동 키(W A S D·방향키)·왼쪽 스틱·오른쪽 스틱·십자키 = 이동,
##   L1 R1 / L2 R2(LB RB / LT RT) 또는 − + = 축소·확대, 손길 버튼(E·U / △·Y)·Home·R3 = 지금 방으로.
## - 배율은 [전체가 한눈에 드는 배율, ZOOM_MAX] 사이, 가운데 자리는 가 본 방들의 범위 안으로 막는다.
## - 글자·표식은 배율과 상관없이 같은 크기로 그린다 (방이 작아 이름이 안 들어가면 이름을 숨기고, 지금 방만 위에 띄운다).
## 시험: tools/probe_map_scene.tscn (배율·이동 막기, 열 때 가운데, 중간 보스 집계, 색·보스·금 간 벽·경전 번호·포탈 화살표)
##
## v1.1.0 (기획자 요청 21~25):
## - 방 이름·자리·크기·달빛풀·포탈은 방 목록(RoomIndex, data/map/rooms_index.json)을 먼저 쓴다 (없으면 저장된 스냅숏).
##   방 칸 = map_offset + bounds.position, 크기 bounds.size (canopy_01 처럼 경계가 위로 넓은 방도 표식과 칸이 맞게).
## - 색: 모두 찾음 = 초록, 아직 남음 = 하늘색. 탐사 요소에 금 간 벽(부숴야)과 지역 보스(정화해야)도 센다. 0/0 인 방은 가 보면 초록.
## - 경전 조각을 읽은 방: 방 칸 오른쪽 위에 금빛 별 + 번호 (안 읽은 번호는 그리지 않는다).
## - 포탈 ◆ 옆에 이어지는 방 쪽을 가리키는 화살표 (가 본 방 = 금빛 채움, 안 가 본 방 = 테두리, 잠김 = 회색 + 자물쇠 점),
##   두 방을 다 가 봤으면 짝 ◆ 사이에 옅은 실선.

signal closed

var _panel: Control   # 화면 전체: 어두운 바탕, 제목·안내·범례, 닫기 버튼
var _view: Control    # 방들을 그리는 칸 (clip_contents: 머리글 위로 넘치지 않게)
var _open := false
var _room: Room
var _t := 0.0

## 지역 구분색. 방 채움이 아니라 왼쪽 가는 띠와 테두리에만 쓴다. (travel_menu.gd 도 이 이름으로 참조한다)
const REGION_COLORS := {"canopy": Color(0.36, 0.48, 0.3), "village": Color(0.6, 0.45, 0.25), "mine": Color(0.5, 0.3, 0.25), "abyss": Color(0.35, 0.28, 0.5), "sap_lake": Color(0.25, 0.45, 0.55), "flooded_mine": Color(0.55, 0.25, 0.2)}
## 탐사 상태 채움색 (v1.1.0 기획자 요청 23 — 뜻을 맞바꿈): 모두 찾은 방 = 초록, 아직 찾을 것이 남은 방 = 하늘색.
const FILL_DONE := Color(0.62, 0.92, 0.45)
const FILL_REMAIN := Color(0.45, 0.82, 1.0)
## 달빛풀 점: 달빛 흰빛 + 어두운 테두리 (하늘색 칸과 헷갈리지 않게)
const GRASS_DOT := Color(1.0, 0.96, 0.78)
## 포탈 짝 사이 실선 (점선 아님)
const LINK_COLOR := Color(1.0, 0.85, 0.4, 0.3)
const LINK_WIDTH := 2.0
## 포탈 화살표: 화면 크기(px, 확대와 무관)와 ◆ 에서 떨어진 거리
const ARROW_LEN := 14.0
const ARROW_GAP := 12.0
## 짝 ◆ 가 가까워 마주 보는 두 화살표가 겹칠 때(방 경계를 사이에 둔 짝 — 기본 배율에서 약 35px): 두 화살표를 짝을 잇는 선에
## 수직으로 이만큼(화면 px) 서로 반대쪽으로 비켜 '⇄' 처럼 갈라 그린다. RAMP = 겹치기 시작하는 거리에서 다 비킬 때까지의 폭(px).
const ARROW_SPLIT := 10.0
const ARROW_SPLIT_RAMP := 12.0
const ARROW_LOCKED := Color(0.62, 0.62, 0.66)
## 찾은 수 글자 자리 후보: 오른쪽 아래(0,0)에서 (x 칸, y 칸) 만큼. x 한 칸 = 글자 폭 + COUNT_STEP_X(왼쪽), y 한 칸 = COUNT_STEP_Y(위)
const COUNT_SLOTS: Array[Vector2] = [Vector2(0, 0), Vector2(0, -1), Vector2(0, -2), Vector2(-1, 0), Vector2(-1, -1), Vector2(-2, 0), Vector2(-2, -1)]
const COUNT_STEP_X := 34.0
const COUNT_STEP_Y := 20.0
## 경전 조각 별 (금빛)
const SCRIPTURE_COLOR := Color(1.0, 0.84, 0.36)
## 화살표 상태
enum Link { VISITED, UNVISITED, LOCKED }
## 글자 테두리(밝은 채움 위에서도 읽히게)
const OUTLINE := Color(0.02, 0.04, 0.08, 0.9)
const REGION_BAND := 6.0
const GOLD := Color(1.0, 0.86, 0.5)
## 해골 표식 크기(지도 확대 100% 기준 px)와 색: 보스 방 / 아직 쓰러뜨리지 않은 중간 보스 방
const SKULL_BOSS := 15.0
const SKULL_MINI := 10.5
const SKULL_BOSS_COLOR := Color(1.0, 0.8, 0.66)
const SKULL_MINI_COLOR := Color(1.0, 0.72, 0.58, 0.9)

## 배율 (화면 px / 세계 px). 0.1 이면 4800 너비의 방이 480px.
const ZOOM_OPEN := 0.1       # 열 때 (읽기 좋은 크기)
const ZOOM_MAX := 0.3        # 가장 크게
const ZOOM_MIN_FLOOR := 0.008  # 아무리 넓어도 이 밑으로는 줄이지 않는다
const PAN_SPEED := 1100.0    # 스틱·키로 이동하는 빠르기 (화면 px / 초)
const ZOOM_SPEED := 1.6      # 버튼을 누르고 있을 때 확대 빠르기 (초당 배율 e^이 값)
const WHEEL_STEP := 1.15     # 휠 한 칸
const EDGE_SLACK := 120.0    # 범위 끝에서 더 밀 수 있는 여유 (화면 px)
const DOUBLE_TAP_TIME := 0.35  # 두 번 누르기로 치는 간격 (초)
const DOUBLE_TAP_DIST := 70.0
const TAP_MOVE := 24.0       # 이만큼 넘게 움직이면 누르기가 아니라 끌기
const TAP_TIME := 0.3
## 머리글(제목·안내·범례) 높이와 지도 칸 여백
const HEADER_H := 156.0
const VIEW_MARGIN := 40.0
## 닫기 버튼: 터치 '지도' 버튼과 같은 자리·크기 (터치 버튼 크기 설정을 따른다)
const CLOSE_POS := Vector2(76, 76)   # 오른쪽 위 모서리에서
const CLOSE_R := 46.0

## 중간 보스가 있는 방 → 깃발. 옛 저장(중간 보스를 탐사 요소로 세기 전)에 빠진 항목을 지도가 열릴 때 채운다 (fix_saved_minibosses).
## tools/probe_map.gd 가 scenes/rooms 의 MiniBossRoom 전부와 이 표가 같은지 확인한다.
const MINIBOSS_ROOMS := {
	"canopy_hidden": "miniboss_canopy_defeated",
	"canopy_mini_1": "miniboss_old_woodcutter_defeated",
	"canopy_mini_2": "miniboss_elder_gardener_defeated",
	"village_mini_1": "miniboss_guard_captain_defeated",
	"mine_mini_1": "miniboss_mine_beast_defeated",
	"abyss_mini_1": "miniboss_spore_mother_defeated",
}

## 지역 보스 방 → 깃발 (v1.1.0 기획자 요청 24: 보스를 정화해야 '모두 찾음'). 옛 저장의 탐사 목록에 없어도 지도가 직접 센다.
## tools/probe_map.gd 가 scenes/rooms 의 BossRoom 전부와 이 표가 같은지 확인한다.
const BOSS_ROOMS := {
	"canopy_boss": "boss_bird_defeated",
	"mine_boss": "boss_knight_defeated",
	"sap_lake_boss": "boss_queen_defeated",
	"flooded_mine_boss": "boss_pump_defeated",
	"abyss_boss": "boss_root_defeated",
}

## 보기 상태
var _zoom := ZOOM_OPEN
var _center := Vector2.ZERO          # 지도 칸 가운데에 보이는 세계 좌표
var _bounds := Rect2()               # 가 본 방 전체의 범위 (세계 좌표)
## 손가락: 번호 -> {"pos", "start", "time", "multi"}
var _touches := {}
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO
var _last_tap_ms := -100000
var _last_tap_pos := Vector2.ZERO
## 글자 폭 캐시 (그릴 때마다 재지 않게): "글자|크기" -> 폭
var _text_w := {}
## 열 때 한 번 만드는 그리기 자료 (지도가 열린 동안 게임이 멈추므로 바뀌지 않는다) — 매 프레임 사전·배열을 새로 만들지 않게
## _cards: [{id, rect(세계), origin(세계, 방 원점), name, region, grasses:[세계 점], portals:[{pos, dir, state, to, pair?}], found, total, done,
##           boss(""/깃발), boss_down, mini_live, scriptures:[번호], count_text}]
## (포탈의 pair = 지도에 보이는 짝 ◆ 의 세계 점 — 가까우면 화살표를 비켜 그린다)
var _cards: Array = []
## 포탈 짝 실선: [[세계 점 a, 세계 점 b]]
var _links: Array = []
## 찾은 수 글자가 피할 표식 자리 (그릴 때마다 비워 다시 쓴다 — 새 배열을 만들지 않게)
var _marks: Array[Vector2] = []


## 방의 탐사 수치를 읽는다 → [찾은 수, 전체 수].
## 1) "explore_ids"(문자열 배열)가 있으면 지도가 그릴 때 직접 센다 — 방을 다시 들어가지 않아도 바로 바뀐다.
##    항목 형식: "grass:<grass_id>" 는 Progress.grasses 에서, 그 밖("read_<id>", "<id>_rescued", "secret_<id>" 등)은 Progress 깃발에서 찾는다.
## 2) 없으면 "explore_total"/"explore_found" 정수를 쓴다(없으면 0).
## room_id 를 주면 (v1.1.0) 지역 보스(BOSS_ROOMS, 정화 깃발)와 금 간 벽(방 목록의 secret_id, 부숨 = Progress.collected)을
## 탐사 목록에 없더라도 더해 센다 — 옛 저장도 바로 맞게. (목록에 "bosses"/"walls" 가 있으면 그것을 쓴다)
static func explore_counts(r: Dictionary, room_id := "") -> Array[int]:
	var extra := _extra_counts(r.get("explore_ids", null), room_id)
	if r.has("explore_ids"):
		var raw = r["explore_ids"]
		var found: int = extra[0]
		var total: int = extra[1]
		if raw is Dictionary:
			# Room._collect_explore_ids 형식: {"pickups": [...], "rescues": [...], "records": [...], "grasses": [...], "minibosses": [...]}
			for id in raw.get("pickups", []):
				total += 1
				if Progress.is_collected(str(id)):
					found += 1
			for id in raw.get("rescues", []):
				total += 1
				if Progress.rescued.has(str(id)):
					found += 1
			for id in raw.get("records", []):
				total += 1
				if Progress.has("read_" + str(id)):
					found += 1
			for id in raw.get("grasses", []):
				total += 1
				if Progress.grasses.has(str(id)):
					found += 1
			# 중간 보스: 쓰러뜨려야(깃발) 찾은 것으로 친다
			for flag in raw.get("minibosses", []):
				total += 1
				if Progress.has(str(flag)):
					found += 1
			return [found, total]
		elif raw is Array:
			for key in raw:
				var k := str(key)
				total += 1
				if k.begins_with("grass:"):
					if Progress.grasses.has(k.substr(6)):
						found += 1
				elif Progress.has(k):
					found += 1
			return [found, total]
	return [int(r.get("explore_found", 0)) + extra[0], int(r.get("explore_total", 0)) + extra[1]]


## 지역 보스·금 간 벽 → [찾은 수, 전체 수]. 탐사 목록(사전)에 "bosses"/"walls" 가 있으면 그 목록을, 없으면 표·방 목록을 쓴다.
static func _extra_counts(raw, room_id: String) -> Array[int]:
	var bosses: Array = []
	var walls: Array = []
	if raw is Dictionary:
		bosses = raw.get("bosses", [])
		walls = raw.get("walls", [])
	if bosses.is_empty() and BOSS_ROOMS.has(room_id):
		bosses = [BOSS_ROOMS[room_id]]
	if walls.is_empty() and room_id != "":
		walls = RoomIndex.cracked(room_id)
	var found := 0
	for flag in bosses:
		if Progress.has(str(flag)):
			found += 1
	for id in walls:
		if Progress.is_collected(str(id)):
			found += 1
	return [found, bosses.size() + walls.size()]


## 채움색 규칙: 찾은 수 < 전체 수 → 하늘색(FILL_REMAIN), 아니면 초록(FILL_DONE). 값이 없는 방(0/0)은 다 찾은 것으로 본다.
static func explore_fill(r: Dictionary, room_id := "") -> Color:
	var counts := explore_counts(r, room_id)
	return FILL_REMAIN if counts[0] < counts[1] else FILL_DONE


## 아직 쓰러뜨리지 않은 중간 보스가 있는 방인가 (지도에 작은 해골 표식).
static func has_live_miniboss(r: Dictionary) -> bool:
	var raw = r.get("explore_ids", null)
	if raw is Dictionary:
		for flag in raw.get("minibosses", []):
			if not Progress.has(str(flag)):
				return true
	return false


## 옛 저장 바로잡기: 중간 보스 방의 탐사 목록에 중간 보스 깃발이 없으면 넣고 수를 다시 센다. 고친 방 수를 돌려준다.
## (그 방에 다시 들어가면 Room 이 어차피 새로 세지만, 들어가기 전에도 지도가 맞게)
static func fix_saved_minibosses(rooms: Dictionary) -> int:
	var n := 0
	for id in MINIBOSS_ROOMS:
		var entry = rooms.get(id)
		if not (entry is Dictionary):
			continue
		var flag: String = MINIBOSS_ROOMS[id]
		var raw = entry.get("explore_ids", null)
		var changed := false
		if raw is Dictionary:
			var list = raw.get("minibosses", [])
			if not (list is Array):
				list = []
			if not list.has(flag):
				list.append(flag)
				raw["minibosses"] = list
				changed = true
		elif raw is Array:
			if not raw.has(flag):
				raw.append(flag)
				changed = true
		else:
			entry["explore_ids"] = {"minibosses": [flag]}
			changed = true
		if changed:
			var c := explore_counts(entry, id)
			entry["explore_found"] = c[0]
			entry["explore_total"] = c[1]
			n += 1
	return n


func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = Control.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	_panel.draw.connect(_on_draw)
	add_child(_panel)
	_view = Control.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.clip_contents = true
	_view.draw.connect(_on_draw_view)
	_panel.add_child(_view)
	_panel.resized.connect(_layout)
	_layout()


## 지도 칸 자리 (화면 크기에 맞춰)
func _layout() -> void:
	var size := _panel.size
	_view.position = Vector2(VIEW_MARGIN, HEADER_H)
	_view.size = Vector2(maxf(size.x - VIEW_MARGIN * 2.0, 10.0), maxf(size.y - HEADER_H - VIEW_MARGIN, 10.0))
	if _open:
		_clamp_view()


func open(room: Room) -> void:
	_room = room
	_open = true
	_panel.visible = true
	_touches.clear()
	_last_tap_ms = -100000
	fix_saved_minibosses(Progress.visited_rooms)   # 옛 저장의 중간 보스 방
	build_cards()
	_layout()
	reset_view()
	get_tree().paused = true
	_panel.queue_redraw()


func close() -> void:
	_open = false
	_panel.visible = false
	_touches.clear()
	get_tree().paused = false
	closed.emit()


func is_open() -> bool:
	return _open


# ───────── 보기 (배율·가운데) ─────────

## 방의 지도 칸 (세계 좌표): 방 목록(RoomIndex)이 있으면 map_offset + bounds.position / bounds.size, 없으면 저장된 스냅숏.
static func room_rect(id: String, r: Dictionary) -> Rect2:
	if RoomIndex.has_room(id):
		return RoomIndex.room_rect(id)
	return Rect2(r["offset"], r["size"])


## 방 원점의 세계 좌표 (달빛풀·포탈·소녀 자리를 더하는 기준)
static func room_origin(id: String, r: Dictionary) -> Vector2:
	if RoomIndex.has_room(id):
		return RoomIndex.room_offset(id)
	return r["offset"]


## 가 본 방 전체의 범위 (세계 좌표). 방이 없으면 빈 사각형.
func map_bounds() -> Rect2:
	var rooms: Dictionary = Progress.visited_rooms
	var first := true
	var out := Rect2()
	for id in rooms:
		var rect := room_rect(id, rooms[id])
		if first:
			out = rect
			first = false
		else:
			out = out.merge(rect)
	return out


## 그리기 자료를 만든다 (열 때). 시험이 Progress 를 바꾼 뒤 다시 부를 수 있다.
func build_cards() -> void:
	_cards.clear()
	_links.clear()
	var rooms: Dictionary = Progress.visited_rooms
	var shown := {}   # 방 id -> {포탈 노드 이름: 화살표 자료(pos = 세계 점)} (짝 실선·짝 화살표 비키기용)
	for id in rooms:
		var r: Dictionary = rooms[id]
		var origin := room_origin(id, r)
		var counts := explore_counts(r, id)
		var card := {"id": id, "rect": room_rect(id, r), "origin": origin, "name": RoomIndex.room_name(id, str(r.get("name", id))),
			"region": RoomIndex.region_of(id, str(r.get("region", "canopy"))), "found": counts[0], "total": counts[1],
			"done": counts[0] >= counts[1], "count_text": "%d/%d" % [counts[0], counts[1]],
			"boss": str(BOSS_ROOMS.get(id, "")) if (r.get("boss", false) or BOSS_ROOMS.has(id)) else "",
			"mini_live": has_live_miniboss(r), "grasses": [], "portals": [], "scriptures": []}
		card["boss_down"] = card["boss"] != "" and Progress.has(card["boss"])
		if r.get("boss", false) and card["boss"] == "":
			card["boss"] = "?"   # 표에 없는 보스 방 (시험용 가짜 방 등): 해골만
		# 달빛풀: 방 목록의 (장식 아닌) 달빛풀, 없으면 스냅숏
		if RoomIndex.has_room(id):
			for g in RoomIndex.room(id).get("grasses", []):
				if not bool(g.get("decor", false)):
					card["grasses"].append(origin + Vector2(float(g["pos"][0]), float(g["pos"][1])))
		else:
			for g in r.get("grasses", []):
				card["grasses"].append(origin + Vector2(g))
		# 경전 조각: 읽은 번호만
		for n in RoomIndex.scriptures_in(id):
			if Progress.scripture_read(n):
				card["scriptures"].append(n)
		# 포탈: 방 목록의 포탈 (숨은 포탈은 드러나 스냅숏에 들어간 뒤에만), 목록에 없는 방은 스냅숏 자리만
		var snap: Array = r.get("portals", [])
		shown[id] = {}
		if RoomIndex.has_room(id):
			for p in RoomIndex.portals(id):
				var local := Vector2(float(p["pos"][0]), float(p["pos"][1]))
				if bool(p.get("hidden", false)) and not _near_any(local, snap):
					continue
				var mark := _portal_mark(origin + local, p)
				shown[id][str(p.get("node", ""))] = mark
				card["portals"].append(mark)
		else:
			for pp in snap:
				card["portals"].append({"pos": origin + Vector2(pp), "dir": Vector2.ZERO, "state": Link.UNVISITED, "to": ""})
		_cards.append(card)
	# 짝 실선: 두 방을 다 가 봤고 두 ◆ 가 다 보이면 (한 번씩만)
	var done := {}
	for id in shown:
		for node in shown[id]:
			var p := _index_portal(id, node)
			var to := str(p.get("to", ""))
			if not shown.has(to):
				continue
			var pair := _pair_node(id, p)
			if pair == "" or not shown[to].has(pair):
				continue
			var key := "%s/%s|%s/%s" % ([id, node, to, pair] if id < to else [to, pair, id, node])
			if done.has(key):
				continue
			done[key] = true
			var ma: Dictionary = shown[id][node]
			var mb: Dictionary = shown[to][pair]
			ma["pair"] = mb["pos"]
			mb["pair"] = ma["pos"]
			_links.append([ma["pos"], mb["pos"]])


static func _near_any(p: Vector2, pts: Array, tol := 40.0) -> bool:
	for q in pts:
		if p.distance_to(Vector2(q)) <= tol:
			return true
	return false


static func _index_portal(room_id: String, node: String) -> Dictionary:
	for p in RoomIndex.portals(room_id):
		if str(p.get("node", "")) == node:
			return p
	return {}


## 포탈 p(방 room_id)의 짝: 목적지 방에서 이 방으로 돌아오는 포탈 가운데 도착 표식에 가장 가까운 것의 노드 이름 (없으면 "")
static func _pair_node(room_id: String, p: Dictionary) -> String:
	var to := str(p.get("to", ""))
	var spawn = RoomIndex.marker(to, str(p.get("spawn", "")))
	var best := ""
	var best_d := INF
	for q in RoomIndex.portals(to):
		if str(q.get("to", "")) != room_id:
			continue
		var d := 0.0
		if spawn != null:
			d = (spawn as Vector2).distance_to(Vector2(float(q["pos"][0]), float(q["pos"][1])))
		if d < best_d:
			best_d = d
			best = str(q.get("node", ""))
	return best


## ◆ 하나의 화살표: 방향 = 이 ◆ → 목적지 방의 도착 표식(없으면 목적지 방 가운데), 상태 = 잠김 / 가 봄 / 안 가 봄
static func _portal_mark(at: Vector2, p: Dictionary) -> Dictionary:
	var to := str(p.get("to", ""))
	var dir := Vector2.ZERO
	if RoomIndex.has_room(to):
		var target := RoomIndex.room_rect(to).get_center()
		var m = RoomIndex.marker(to, str(p.get("spawn", "")))
		if m != null:
			target = RoomIndex.room_offset(to) + (m as Vector2)
		if target.distance_to(at) > 1.0:
			dir = (target - at).normalized()
	var req := str(p.get("requires", ""))
	var state := Link.UNVISITED
	if req != "" and not Progress.has_ability(req):
		state = Link.LOCKED
	elif Progress.visited_rooms.has(to):
		state = Link.VISITED
	return {"pos": at, "dir": dir, "state": state, "to": to}


## 화살표 가운데 (지도 칸 좌표). c = ◆ 가운데, d = ◆ 반지름, pm = 화살표 자료(pair 가 있으면 짝 ◆ 의 세계 점).
## 보통은 ◆ 에서 목적지 쪽으로 d + ARROW_GAP. 짝 ◆ 가 가까워 마주 보는 두 화살표가 겹칠 거리면(방 경계를 사이에 둔 짝),
## 짝을 잇는 선에 수직으로 ARROW_SPLIT 만큼 비킨다 — 짝도 같은 규칙이라 반대쪽으로 갈라져 '⇄' 처럼 보인다 (v1.1.0 검토).
## 화살표가 가리키는 방향(pm.dir)은 그대로다. 그리기와 tools/probe_map.gd 가 같이 쓴다.
func arrow_center(c: Vector2, d: float, pm: Dictionary) -> Vector2:
	var dir: Vector2 = pm["dir"]
	var along := d + ARROW_GAP
	if pm.has("pair"):
		var pc := world_to_view(pm["pair"])
		var dist := c.distance_to(pc)
		var need := 2.0 * (d + ARROW_GAP + ARROW_LEN * 0.55) + 4.0   # 이보다 가까우면 두 화살표가 짝을 잇는 선 위에서 겹친다
		if dist < need and dist > 0.5:
			var axis := (pc - c) / dist
			var t := clampf((need - dist) / ARROW_SPLIT_RAMP, 0.0, 1.0)
			return c + axis * minf(along, dist * 0.5) + Vector2(axis.y, -axis.x) * (ARROW_SPLIT * t)
	return c + dir * along


## 찾은 수 글자의 바탕 네모 (지도 칸 좌표): 방 칸 rect 의 오른쪽 아래에서 시작해, 표식 자리(_marks)와 16px 안으로 가까우면
## COUNT_SLOTS 차례로 비킨다 (방 칸 안에서만). 겹치는 표식이 없는 첫 자리, 모두 겹치면 가장 적게 겹치는 자리.
## 글자 기준점 = 네모 위치 + (3, 13). 그리기와 tools/probe_map.gd 가 같이 쓴다.
func count_box_at(rect: Rect2, count_w: float) -> Rect2:
	var base := Rect2(rect.end - Vector2(count_w + 11, 20), Vector2(count_w + 6, 17))
	var best := base
	var best_hits := 9999
	for slot in COUNT_SLOTS:
		var box := base
		box.position += Vector2(slot.x * (count_w + COUNT_STEP_X), slot.y * COUNT_STEP_Y)
		if slot != Vector2.ZERO and not rect.encloses(box):
			continue
		var hits := 0
		var near := box.grow(16.0)
		for m in _marks:
			if near.has_point(m):
				hits += 1
		if hits < best_hits:
			best_hits = hits
			best = box
			if hits == 0:
				break
	return best


## 시험용: 그리기 자료에서 방 하나 (없으면 빈 사전)
func card_of(id: String) -> Dictionary:
	for c in _cards:
		if c["id"] == id:
			return c
	return {}


## 시험용: 포탈 짝 실선 수
func link_count() -> int:
	return _links.size()


## 지도 칸 크기 (화면 px)
func view_size() -> Vector2:
	return _view.size


## 전체가 한눈에 드는 배율 (조금 여백). 이보다(또는 ZOOM_OPEN 보다) 더 줄이지는 않는다.
func zoom_min() -> float:
	var span := _bounds.size
	if span.x <= 0.0 or span.y <= 0.0:
		return ZOOM_OPEN
	var vs := view_size()
	var fit := minf(vs.x / span.x, vs.y / span.y) * 0.92
	return clampf(minf(fit, ZOOM_OPEN), ZOOM_MIN_FLOOR, ZOOM_OPEN)


func zoom_max() -> float:
	return ZOOM_MAX


## 열 때·두 번 누를 때·'지금 방' 버튼: 읽기 좋은 배율로 지금 방(없으면 전체 가운데)을 가운데에.
func reset_view() -> void:
	_bounds = map_bounds()
	_zoom = clampf(ZOOM_OPEN, zoom_min(), zoom_max())
	_center = current_room_center()
	_clamp_view()


## 지금 방의 가운데 (세계 좌표). 지금 방이 지도에 없으면 전체의 가운데.
func current_room_center() -> Vector2:
	if _room != null and is_instance_valid(_room) and Progress.visited_rooms.has(_room.room_id):
		return room_rect(_room.room_id, Progress.visited_rooms[_room.room_id]).get_center()
	return _bounds.get_center()


## 배율과 가운데를 범위 안으로 막는다. 보이는 폭보다 범위가 좁은 축은 가운데에 고정.
func _clamp_view() -> void:
	_zoom = clampf(_zoom, zoom_min(), zoom_max())
	if _bounds.size == Vector2.ZERO:
		_center = Vector2.ZERO
		return
	var half := view_size() / (2.0 * _zoom)
	var slack := EDGE_SLACK / _zoom
	for axis in 2:
		var lo: float = _bounds.position[axis]
		var hi: float = _bounds.end[axis]
		if hi - lo <= half[axis] * 2.0:
			_center[axis] = (lo + hi) / 2.0
		else:
			_center[axis] = clampf(_center[axis], lo + half[axis] - slack, hi - half[axis] + slack)


## 세계 좌표 → 지도 칸 안 좌표
func world_to_view(p: Vector2) -> Vector2:
	return view_size() / 2.0 + (p - _center) * _zoom


func view_to_world(p: Vector2) -> Vector2:
	return _center + (p - view_size() / 2.0) / _zoom


## 지도 칸 안의 한 점(화면 좌표)을 고정한 채 배율을 factor 배로.
func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var p := screen_pos - _view.position
	var anchor := view_to_world(p)
	_zoom = clampf(_zoom * factor, zoom_min(), zoom_max())
	_center = anchor - (p - view_size() / 2.0) / _zoom
	_clamp_view()


## 화면 px 만큼 지도를 끈다 (손가락이 오른쪽으로 가면 지도도 오른쪽으로).
func pan_screen(delta_px: Vector2) -> void:
	_center -= delta_px / _zoom
	_clamp_view()


# ───────── 입력 ─────────

func _process(delta: float) -> void:
	if not _open:
		return
	_t += delta
	_held_input(delta)
	_panel.queue_redraw()
	_view.queue_redraw()


## 누르고 있는 키·스틱·어깨 버튼: 이동과 확대 (멈춘 동안에도 Input 은 읽힌다)
func _held_input(delta: float) -> void:
	var move := Vector2.ZERO
	# 터치로 놀 때는 끌기로만 움직인다: 지도를 열 때 왼손이 화면 스틱을 누르고 있으면 그 이동 동작이 계속 눌린 채라
	# 지도가 혼자 흘러가 버린다 (터치 스틱은 멈춘 동안에도 손가락 끌기를 받는다)
	if InputDevice.current != InputDevice.Kind.TOUCH:
		move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var zoom_dir := 0.0
	for dev in Input.get_connected_joypads():
		var rs := Vector2(Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X), Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y))
		if rs.length() > 0.2:
			move += rs
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT):
			move.x -= 1.0
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT):
			move.x += 1.0
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_RIGHT_SHOULDER) or Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT) > 0.35:
			zoom_dir += 1.0
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_LEFT_SHOULDER) or Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT) > 0.35:
			zoom_dir -= 1.0
	if Input.is_physical_key_pressed(KEY_EQUAL) or Input.is_physical_key_pressed(KEY_KP_ADD) or Input.is_physical_key_pressed(KEY_PAGEUP):
		zoom_dir += 1.0
	if Input.is_physical_key_pressed(KEY_MINUS) or Input.is_physical_key_pressed(KEY_KP_SUBTRACT) or Input.is_physical_key_pressed(KEY_PAGEDOWN):
		zoom_dir -= 1.0
	if move.length() > 0.05:
		# 끌기와 반대: 스틱을 오른쪽으로 밀면 오른쪽(동쪽)을 보러 간다
		pan_screen(-move.limit_length(1.0) * PAN_SPEED * delta)
	if zoom_dir != 0.0:
		zoom_at(_view.position + view_size() / 2.0, exp(clampf(zoom_dir, -1.0, 1.0) * ZOOM_SPEED * delta))


## 닫기 버튼 자리·반지름 (화면 좌표)
func close_button() -> Dictionary:
	var k := Settings.touch_scale_factor()
	return {"pos": Vector2(_panel.size.x - CLOSE_POS.x * k, CLOSE_POS.y * k), "r": CLOSE_R * k}


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("map") or event.is_action_pressed("pause") or event.is_action_pressed("dodge") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("jump"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_HOME) \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_RIGHT_STICK):
		reset_view()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		_on_touch(event)
		# 손가락 떼기는 터치 버튼(TouchControls)에도 흘려보낸다: 지도를 연 '지도' 손가락·걷던 스틱 손가락의 떼기를 지도가 삼키면
		# 그 동작이 눌린 채 남아, 닫은 뒤 소녀가 혼자 걷고 '지도' 버튼이 눌린 채 보인다 (2026-10-20 QA, travel_menu 와 같은 규칙).
		if event.pressed:
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var mine: bool = _touches.has(event.index)
		_on_drag(event)
		# 지도를 열기 전부터 눌려 있던 손가락(스틱 등)의 끌기도 터치 버튼이 받게 둔다 (지도는 그 손가락을 쓰지 않는다)
		if mine:
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var steps: float = event.factor if event.factor > 0.0 else 1.0
		var f := pow(WHEEL_STEP, steps)
		zoom_at(event.position, f if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / f)
		get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		zoom_at(event.position, event.factor)
		get_viewport().set_input_as_handled()
	elif event is InputEventPanGesture:
		pan_screen(-event.delta * 24.0)
		get_viewport().set_input_as_handled()


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		var cb := close_button()
		if _touches.is_empty() and event.position.distance_to(cb["pos"]) <= cb["r"] * 1.3:
			close()
			return
		_touches[event.index] = {"pos": event.position, "start": event.position, "time": Time.get_ticks_msec(), "multi": false}
		if _touches.size() >= 2:
			for t in _touches.values():
				t["multi"] = true
			_begin_pinch()
		return
	if not _touches.has(event.index):
		return   # 지도를 열기 전에 눌린 손가락 (예: '지도' 버튼을 누른 손가락)
	var t: Dictionary = _touches[event.index]
	_touches.erase(event.index)
	if _touches.size() >= 2:
		_begin_pinch()
	var moved: bool = event.position.distance_to(t["start"]) > TAP_MOVE
	var quick: bool = Time.get_ticks_msec() - int(t["time"]) <= int(TAP_TIME * 1000.0)
	if t["multi"] or moved or not quick:
		return
	# 짧게 한 번 누름: 앞선 누름과 가까우면 두 번 누르기 → 처음대로
	var now := Time.get_ticks_msec()
	if now - _last_tap_ms <= int(DOUBLE_TAP_TIME * 1000.0) and event.position.distance_to(_last_tap_pos) <= DOUBLE_TAP_DIST:
		reset_view()
		_last_tap_ms = -100000
	else:
		_last_tap_ms = now
		_last_tap_pos = event.position


func _on_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	var prev: Vector2 = _touches[event.index]["pos"]
	_touches[event.index]["pos"] = event.position
	if _touches.size() == 1:
		pan_screen(event.position - prev)
	elif _touches.size() >= 2:
		var pts := _pinch_points()
		var dist := pts[0].distance_to(pts[1])
		var mid := (pts[0] + pts[1]) / 2.0
		# 먼저 손가락 사이 가운데가 움직인 만큼 끌고, 그 자리를 고정한 채 확대 (처음 잡은 지도 위 한 점이 손가락 가운데를 따라온다)
		pan_screen(mid - _pinch_mid)
		if _pinch_dist > 1.0 and dist > 1.0:
			zoom_at(mid, dist / _pinch_dist)
		_pinch_dist = dist
		_pinch_mid = mid


func _pinch_points() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for t in _touches.values():
		out.append(t["pos"])
		if out.size() == 2:
			break
	return out


func _begin_pinch() -> void:
	var pts := _pinch_points()
	if pts.size() < 2:
		return
	_pinch_dist = pts[0].distance_to(pts[1])
	_pinch_mid = (pts[0] + pts[1]) / 2.0


# ───────── 그리기 ─────────

func _tw(font: Font, text: String, size: int) -> float:
	var key := "%s|%d" % [text, size]
	if not _text_w.has(key):
		_text_w[key] = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return _text_w[key]


func _outlined(ci: CanvasItem, font: Font, pos: Vector2, text: String, size: int, color: Color, outline := 4) -> void:
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(OUTLINE, OUTLINE.a * color.a))
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## 장치에 맞는 조작 안내 한 줄
func hint_text() -> String:
	match InputDevice.current:
		InputDevice.Kind.TOUCH, InputDevice.Kind.NONE:
			return "두 손가락: 확대·축소  ·  끌기: 이동  ·  두 번 누르기: 지금 방  ·  ✕: 닫기"
		InputDevice.Kind.DUALSENSE:
			return "스틱: 이동  ·  L1 R1: 축소·확대  ·  %s: 지금 방  ·  %s: 닫기" % [InputDevice.prompt("interact"), InputDevice.prompt("dodge")]
		InputDevice.Kind.XBOX, InputDevice.Kind.OTHER_PAD:
			return "스틱: 이동  ·  LB RB: 축소·확대  ·  %s: 지금 방  ·  %s: 닫기" % [InputDevice.prompt("interact"), InputDevice.prompt("dodge")]
	return "방향키: 이동  ·  − +, 휠: 축소·확대  ·  %s: 지금 방  ·  %s / Esc: 닫기" % [InputDevice.prompt("interact"), InputDevice.prompt("map")]


func _on_draw() -> void:
	var font := ThemeDB.fallback_font
	var size := _panel.size
	_panel.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.88))
	_panel.draw_string(font, Vector2(60, 70), "지도", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(0.95, 0.9, 0.8))
	# 머리글: '☠'·'✦' 글자는 기기 글꼴에 따라 작은 얼룩으로 보여서 지도와 같은 그린 해골·별·화살표를 쓴다
	var head := "가 본 곳만 그려진다  ·  ● 달빛풀  ◆ 포탈"
	var dim := Color(1, 1, 1, 0.45)
	_panel.draw_string(font, Vector2(150, 70), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, dim)
	var hx := 150.0 + _tw(font, head, 20) + 8.0
	draw_arrow(_panel, Vector2(hx + 6.0, 63.0), Vector2.RIGHT, Link.VISITED)
	_panel.draw_string(font, Vector2(hx + 18.0, 70), "이어지는 쪽", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, dim)
	hx += 18.0 + _tw(font, "이어지는 쪽", 20) + 22.0
	draw_star(_panel, Vector2(hx + 8.0, 63.0), 9.0, SCRIPTURE_COLOR)
	_panel.draw_string(font, Vector2(hx + 22.0, 70), "경전 조각", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, dim)
	hx += 22.0 + _tw(font, "경전 조각", 20) + 22.0
	draw_skull(_panel, Vector2(hx + 10.0, 63.0), 9.0, SKULL_BOSS_COLOR)
	_panel.draw_string(font, Vector2(hx + 26.0, 70), "수호자", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, dim)
	_panel.draw_string(font, Vector2(60, 106), hint_text(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 260.0, 20, Color(1, 1, 1, 0.45))
	_draw_legend(font, Vector2(60, 138))
	# 지도 칸 테두리
	_panel.draw_rect(Rect2(_view.position, _view.size), Color(GOLD, 0.18), false, 1.5)
	_draw_close_button()
	# 배율 표시 (오른쪽 아래, 작게)
	var zt := "×%.0f%%" % (_zoom / ZOOM_OPEN * 100.0)
	_panel.draw_string(font, Vector2(size.x - VIEW_MARGIN - 8.0 - _tw(font, zt, 16), size.y - VIEW_MARGIN - 10.0), zt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.35))


## 그린 해골 표식 (보스·중간 보스 방). 가운데 c, 크기 sz(머리 반지름쯤). 짙은 둥근 바탕 위에 그려 연초록·하늘색 칸에서도 또렷하다.
## (예전엔 '☠' 글자였는데 기기 글꼴로 약 10px 의 검붉은 얼룩이 되어 칸 위에서 거의 안 보였다 — 2026-10-20 QA)
## alpha: 정화한 보스 방은 옅게(0.35) 그린다.
static func draw_skull(ci: CanvasItem, c: Vector2, sz: float, col: Color, alpha := 1.0) -> void:
	var dark := Color(0.06, 0.03, 0.03, 0.92 * alpha)
	col = Color(col, col.a * alpha)
	ci.draw_circle(c, sz * 1.32, Color(OUTLINE, 0.85 * alpha))
	ci.draw_arc(c, sz * 1.32, 0, TAU, 32, Color(col, 0.75 * alpha), maxf(1.5, sz * 0.12), true)
	# 머리뼈 + 턱
	var head := c + Vector2(0, -sz * 0.16)
	ci.draw_circle(head, sz * 0.66, col)
	ci.draw_rect(Rect2(c + Vector2(-sz * 0.38, sz * 0.12), Vector2(sz * 0.76, sz * 0.5)), col)
	# 눈구멍·코
	for sx in [-1.0, 1.0]:
		ci.draw_circle(head + Vector2(sx * sz * 0.27, sz * 0.02), sz * 0.19, dark)
	var n := c + Vector2(0, sz * 0.16)
	ci.draw_colored_polygon(PackedVector2Array([n + Vector2(0, -sz * 0.14), n + Vector2(sz * 0.1, sz * 0.06), n + Vector2(-sz * 0.1, sz * 0.06)]), dark)
	# 이빨 사이 금
	for tx in [-0.13, 0.13]:
		ci.draw_line(c + Vector2(tx * sz, sz * 0.36), c + Vector2(tx * sz, sz * 0.62), dark, maxf(1.0, sz * 0.09))


## 작은 ✓ (정화한 보스 방의 해골 옆). 가운데 c, 크기 sz.
static func draw_check(ci: CanvasItem, c: Vector2, sz: float) -> void:
	var pts := PackedVector2Array([c + Vector2(-sz * 0.5, 0), c + Vector2(-sz * 0.12, sz * 0.4), c + Vector2(sz * 0.55, -sz * 0.45)])
	ci.draw_polyline(pts, Color(OUTLINE, 0.9), maxf(3.0, sz * 0.42), true)
	ci.draw_polyline(pts, FILL_DONE.lightened(0.25), maxf(1.6, sz * 0.22), true)


## 네 갈래 별 (경전 조각). 가운데 c, 반지름 r.
static func draw_star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI / 2.0 + i * PI / 4.0
		var rr := r if i % 2 == 0 else r * 0.38
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	var outline := pts.duplicate()
	outline.append(pts[0])
	ci.draw_polyline(outline, Color(OUTLINE, 0.9 * col.a), 3.0, true)
	ci.draw_colored_polygon(pts, col)


## 포탈 화살표 (삼각형, 화면 ARROW_LEN px — 확대와 무관). 가운데 c, 방향 dir(길이 1), 상태 Link.
static func draw_arrow(ci: CanvasItem, c: Vector2, dir: Vector2, state: int) -> void:
	var side := Vector2(-dir.y, dir.x)
	var tip := c + dir * (ARROW_LEN * 0.55)
	var back := c - dir * (ARROW_LEN * 0.45)
	var tri := PackedVector2Array([tip, back + side * (ARROW_LEN * 0.42), back - side * (ARROW_LEN * 0.42)])
	var ring := tri.duplicate()
	ring.append(tri[0])
	match state:
		Link.VISITED:
			ci.draw_polyline(ring, Color(OUTLINE, 0.9), 3.5, true)
			ci.draw_colored_polygon(tri, GOLD)
		Link.UNVISITED:
			ci.draw_polyline(ring, Color(OUTLINE, 0.9), 4.0, true)
			ci.draw_polyline(ring, GOLD, 1.8, true)
		_:
			ci.draw_polyline(ring, Color(OUTLINE, 0.9), 3.5, true)
			ci.draw_colored_polygon(tri, ARROW_LOCKED)
			# 자물쇠 점: 화살표 뒤쪽의 작은 어두운 점 + 회색 테
			var dot := back - dir * 5.0
			ci.draw_circle(dot, 4.2, Color(OUTLINE, 0.95))
			ci.draw_arc(dot, 4.2, 0, TAU, 12, ARROW_LOCKED, 1.4, true)


## 오른쪽 위 ✕ (터치 '지도' 버튼 자리)
func _draw_close_button() -> void:
	var cb := close_button()
	var c: Vector2 = cb["pos"]
	var r: float = cb["r"]
	_panel.draw_circle(c, r, Color(0.03, 0.04, 0.07, 0.6))
	_panel.draw_arc(c, r, 0, TAU, 48, Color(0.08, 0.05, 0.02, 0.8), 5.0, true)
	_panel.draw_arc(c, r - 1.0, 0, TAU, 48, Color(GOLD, 0.85), 2.5, true)
	var d := r * 0.36
	for s in [Vector2(1, 1), Vector2(1, -1)]:
		_panel.draw_line(c - d * s, c + d * s, Color(0.08, 0.05, 0.02, 0.9), 9.0, true)
		_panel.draw_line(c - d * s, c + d * s, Color(1.0, 0.95, 0.85), 4.5, true)


func _on_draw_view() -> void:
	var font := ThemeDB.fallback_font
	if _cards.is_empty():
		return
	var vs := view_size()
	var screen := Rect2(Vector2.ZERO, vs).grow(40.0)
	# 표식 크기: 많이 줄이면 조금 작게
	var mk := clampf(_zoom / ZOOM_OPEN, 0.55, 1.2)
	var current_id: String = _room.room_id if _room != null and is_instance_valid(_room) else ""
	var current_label := {}
	# 1) 방 칸: 채움(탐사 상태) · 지역 띠 · 테두리 · 이름
	for card in _cards:
		var rect := Rect2(world_to_view(card["rect"].position), card["rect"].size * _zoom)
		if not screen.intersects(rect):
			continue   # 화면 밖 방은 건너뛴다
		var region_color: Color = REGION_COLORS.get(card["region"], Color(0.4, 0.4, 0.4))
		var current: bool = card["id"] == current_id
		# 탐사 상태: 다 찾았으면 초록, 아직 남았으면 하늘색 (값이 없으면 0/0 → 다 찾은 것으로 본다)
		var fill := FILL_DONE if card["done"] else FILL_REMAIN
		_view.draw_rect(rect, Color(fill, 0.72 if current else 0.5))
		# 왼쪽 가는 띠로 지역 구분
		var band := Rect2(rect.position, Vector2(minf(REGION_BAND, rect.size.x), rect.size.y))
		_view.draw_rect(band, Color(region_color.lightened(0.15), 0.95))
		# 테두리: 지금 있는 방은 금빛, 나머지는 지역색
		_view.draw_rect(rect, Color(1.0, 0.86, 0.5, 0.95) if current else Color(region_color.lightened(0.35), 0.8), false, 3.0 if current else 1.5)
		# 이름: 방 안에 들어가면 18, 안 되면 14, 그래도 안 되면 숨긴다 (지금 방은 방 위에 띄운다). 경전 별 자리는 비운다.
		var name: String = card["name"]
		var name_w: float = rect.size.x - 14.0 - REGION_BAND - (38.0 * card["scriptures"].size())
		var fs := 18 if _tw(font, name, 18) <= name_w else (14 if _tw(font, name, 14) <= name_w else 0)
		if fs > 0 and rect.size.y >= fs + 10.0:
			_outlined(_view, font, rect.position + Vector2(10 + REGION_BAND, 6.0 + fs), name, fs, Color(1, 1, 1, 0.92))
		elif current:
			current_label = {"rect": rect, "name": name}
	# 2) 포탈 짝 사이 실선 (두 방을 다 가 봤을 때) — 방 칸 위, 표식 아래
	for link in _links:
		var a := world_to_view(link[0])
		var b := world_to_view(link[1])
		if screen.intersects(Rect2(a, Vector2.ZERO).expand(b)):
			_view.draw_line(a, b, LINK_COLOR, LINK_WIDTH, true)
	# 3) 표식: 달빛풀 · 포탈(+화살표) · 해골 · 경전 별 · 찾은 수
	for card in _cards:
		var rect := Rect2(world_to_view(card["rect"].position), card["rect"].size * _zoom)
		if not screen.intersects(rect):
			continue
		_marks.clear()  # 표식(달빛풀·포탈·화살표) 자리 — 숫자가 겹치지 않게 피하려고 모아 둔다
		for g in card["grasses"]:
			var gp: Vector2 = world_to_view(g)
			_marks.append(gp)
			_view.draw_circle(gp, 12.0 * mk, Color(GRASS_DOT, 0.22 + 0.14 * sin(_t * 3.0)))
			_view.draw_circle(gp, 8.6 * mk, Color(OUTLINE, 0.9))
			_view.draw_circle(gp, 6.6 * mk, GRASS_DOT)
		for pm in card["portals"]:
			var c: Vector2 = world_to_view(pm["pos"])
			_marks.append(c)
			var d := 9.0 * mk
			_view.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), GOLD)
			_view.draw_polyline(PackedVector2Array([c + Vector2(0, -d - 4), c + Vector2(d + 4, 0), c + Vector2(0, d + 4), c + Vector2(-d - 4, 0), c + Vector2(0, -d - 4)]), Color(GOLD, 0.3 + 0.2 * sin(_t * 3.0 + 1.0)), 2.0)
			var dir: Vector2 = pm["dir"]
			if dir != Vector2.ZERO:
				var ac := arrow_center(c, d, pm)
				_marks.append(ac)
				draw_arrow(_view, ac, dir, pm["state"])
		if card["boss"] != "":
			# 지역 보스: 정화하면 옅게 + 작은 ✓
			var sc := rect.get_center()
			draw_skull(_view, sc, SKULL_BOSS * mk, SKULL_BOSS_COLOR, 0.35 if card["boss_down"] else 1.0)
			if card["boss_down"]:
				draw_check(_view, sc + Vector2(SKULL_BOSS * mk * 1.15, SKULL_BOSS * mk * 0.75), 11.0 * mk)
		elif card["mini_live"]:
			# 아직 쓰러뜨리지 않은 중간 보스: 작은 해골 (쓰러뜨리면 사라진다)
			draw_skull(_view, rect.get_center(), SKULL_MINI * mk, SKULL_MINI_COLOR)
		# 경전 조각 (읽은 것만): 방 칸 오른쪽 위에 금빛 별 + 번호
		var sx := rect.end.x - 8.0
		var nums: Array = card["scriptures"]
		for i in range(nums.size() - 1, -1, -1):
			var t := str(nums[i])
			var tw := _tw(font, t, 18)
			sx -= tw
			_outlined(_view, font, Vector2(sx, rect.position.y + 24.0), t, 18, SCRIPTURE_COLOR)
			draw_star(_view, Vector2(sx - 12.0, rect.position.y + 17.0), 9.5, SCRIPTURE_COLOR)
			sx -= 30.0
		# 찾은 수 / 전체 수 (찾을 것이 있는 방만), 오른쪽 아래 작은 글씨. 표식 뒤에 그려 맨 위에 올리고,
		# 포탈·달빛풀·화살표 표식과 가까우면 비킨다: 위로 20·40px → 왼쪽으로 (방 칸 안에서, 겹치는 표식이 가장 적은 자리).
		# 글자 뒤에는 작은 어두운 바탕. 방이 너무 작으면 숨긴다.
		if card["total"] > 0:
			var count_text: String = card["count_text"]
			var count_w := _tw(font, count_text, 14)
			if rect.size.x >= count_w + 22.0 and rect.size.y >= 24.0:
				var count_box := count_box_at(rect, count_w)
				var count_pos := count_box.position + Vector2(3, 13)
				_view.draw_rect(count_box, Color(OUTLINE, 0.7))
				_outlined(_view, font, count_pos, count_text, 14, Color(0.82, 1.0, 0.72) if card["done"] else Color(0.78, 0.93, 1.0))
	# 이름이 방 안에 안 들어가는 지금 방: 방 위에 이름
	if not current_label.is_empty():
		var rect: Rect2 = current_label["rect"]
		var nm: String = current_label["name"]
		var w := _tw(font, nm, 18)
		_outlined(_view, font, Vector2(rect.get_center().x - w / 2.0, rect.position.y - 8.0), nm, 18, Color(1.0, 0.9, 0.7))
	# 소녀의 위치
	if _room and is_instance_valid(_room) and _room.player and is_instance_valid(_room.player):
		var cur: Dictionary = card_of(_room.room_id)
		if not cur.is_empty():
			var p: Vector2 = world_to_view(Vector2(cur["origin"]) + _room.player.global_position)
			var pulse := 0.7 + 0.3 * sin(_t * 5.0)
			_view.draw_circle(p, 14.0 * pulse, Color(1.0, 0.83, 0.42, 0.25))
			_view.draw_circle(p, 6.0, Color(1.0, 0.83, 0.42))
			_view.draw_string_outline(font, p + Vector2(-40, -18), "셀레니아", HORIZONTAL_ALIGNMENT_CENTER, 80, 16, 4, OUTLINE)
			_view.draw_string(font, p + Vector2(-40, -18), "셀레니아", HORIZONTAL_ALIGNMENT_CENTER, 80, 16, Color(1.0, 0.9, 0.7))


## 색 범례: 초록 = 모두 찾음, 하늘색 = 아직 찾을 것이 남음. 작은 색 네모 뒤에 글을 쓴다.
func _draw_legend(font: Font, pos: Vector2) -> void:
	var x := pos.x
	var items := [[FILL_DONE, "모두 찾음"], [FILL_REMAIN, "아직 찾을 것이 남음"]]
	for item in items:
		var c: Color = item[0]
		var text: String = item[1]
		var box := Rect2(Vector2(x, pos.y - 15), Vector2(18, 18))
		_panel.draw_rect(box, Color(c, 0.4))
		_panel.draw_rect(box, Color(c, 0.9), false, 1.5)
		_panel.draw_string(font, Vector2(x + 26, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.55))
		x += 26 + _tw(font, text, 20) + 34
	_panel.draw_string(font, Vector2(x, pos.y), "오른쪽 아래 숫자 = 찾은 수 / 전체 (보스는 정화·중간 보스는 쓰러뜨리기·금 간 벽은 부수기까지)", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.35))

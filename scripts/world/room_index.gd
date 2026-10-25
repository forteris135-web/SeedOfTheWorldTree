class_name RoomIndex
extends RefCounted
## 방 이름의 단일 출처 (v1.1.0 기획자 요청 21·22·25): 지도·달빛풀 이동 목록·저장 칸 요약·포탈 안내가 같은 이름을 쓴다.
## 데이터: data/map/rooms_index.json (tools/make_rooms_index.py 가 scenes/rooms/*.tscn 에서 만든다 — 방 파일을 고치면 다시 돌릴 것,
## tools/regress.sh 가 --check 로 어긋남을 잡는다).
## 저장 파일에 남은 옛 이름(달빛풀 이름·지도 방 이름 스냅숏)은 쓰지 않고 늘 여기서 찾는다 → 옛 저장도 바로 맞는 이름이 된다.
## 파일은 처음 물을 때 한 번 읽어 둔다.

const PATH := "res://data/map/rooms_index.json"
const REGION_LABEL := {"canopy": "수관", "village": "마을", "mine": "채굴장", "flooded_mine": "잠긴 채굴장", "sap_lake": "수액의 호수", "abyss": "심연"}

static var _loaded := false
static var _rooms := {}
static var _grass_room := {}       # 달빛풀 id -> 방 id (장식 달빛풀 제외)
static var _scripture_room := {}   # 경전 조각 번호 N -> 방 id (기록물 scripture_N 이 있는 방)


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	_rooms = {}
	_grass_room = {}
	_scripture_room = {}
	var txt := FileAccess.get_file_as_string(PATH)
	var data = JSON.parse_string(txt) if txt != "" else null
	if not (data is Dictionary):
		push_warning("RoomIndex: %s 를 읽지 못했다 (python3 -I tools/make_rooms_index.py)" % PATH)
		return
	var rooms = data.get("rooms", {})
	if rooms is Dictionary:
		_rooms = rooms
	for rid in _rooms:
		var r: Dictionary = _rooms[rid]
		for g in r.get("grasses", []):
			if not bool(g.get("decor", false)) and str(g.get("id", "")) != "":
				_grass_room[str(g["id"])] = rid
		for n in _scripture_numbers(r.get("records", [])):
			_scripture_room[n] = rid


## 기록물 id 목록에서 경전 조각 번호(scripture_N 의 N)만 (작은 수부터)
static func _scripture_numbers(recs: Array) -> Array[int]:
	var out: Array[int] = []
	for rec in recs:
		var s := str(rec)
		if s.begins_with("scripture_") and s.trim_prefix("scripture_").is_valid_int():
			out.append(int(s.trim_prefix("scripture_")))
	out.sort()
	return out


## 시험용: 파일을 다시 읽는다.
static func reload() -> void:
	_loaded = false
	_ensure()


static func has_room(room_id: String) -> bool:
	_ensure()
	return _rooms.has(room_id)


## 방 하나의 기록 (없으면 빈 사전). 돌려준 사전은 고치지 말 것 (모두가 같이 쓴다).
static func room(room_id: String) -> Dictionary:
	_ensure()
	return _rooms.get(room_id, {})


static func room_ids() -> Array:
	_ensure()
	return _rooms.keys()


static func region_label(region: String) -> String:
	return REGION_LABEL.get(region, region)


## 방의 지역 (모르는 방이면 fallback)
static func region_of(room_id: String, fallback := "") -> String:
	var r := room(room_id)
	return str(r.get("region", fallback)) if not r.is_empty() else fallback


## 지도에 쓰는 방 이름 (예 "수관 · 바람의 틈"). 모르는 방이면 fallback.
static func room_name(room_id: String, fallback := "") -> String:
	var r := room(room_id)
	return str(r.get("name", fallback)) if not r.is_empty() else fallback


## 달빛풀이 있는 방의 지도 이름 = 달빛풀 이동 목록의 이름. 모르는 달빛풀이면 fallback (저장된 옛 이름 등).
static func grass_room_name(grass_id: String, fallback := "") -> String:
	var rid := room_of_grass(grass_id)
	return room_name(rid, fallback) if rid != "" else fallback


## 달빛풀이 있는 방 id (모르면 "")
static func room_of_grass(grass_id: String) -> String:
	_ensure()
	return str(_grass_room.get(grass_id, ""))


## 방 파일 경로 (모르는 방이면 "")
static func scene_of(room_id: String) -> String:
	return "res://scenes/rooms/%s.tscn" % room_id if has_room(room_id) else ""


## 지도 칸 (세계 좌표): 자리 = map_offset + bounds.position, 크기 = bounds.size. 모르는 방이면 빈 사각형.
static func room_rect(room_id: String) -> Rect2:
	var r := room(room_id)
	if r.is_empty():
		return Rect2()
	var off: Array = r.get("offset", [0, 0])
	var b: Array = r.get("bounds", [0, 0, 0, 0])
	return Rect2(float(off[0]) + float(b[0]), float(off[1]) + float(b[1]), float(b[2]), float(b[3]))


## 방 원점의 세계 지도 자리 (Room.map_offset)
static func room_offset(room_id: String) -> Vector2:
	var off: Array = room(room_id).get("offset", [0, 0])
	return Vector2(float(off[0]), float(off[1]))


## 방의 포탈 목록 [{node, pos:[x,y], to, spawn, requires, hidden}]
static func portals(room_id: String) -> Array:
	return room(room_id).get("portals", [])


## 방의 등장 표식 자리 (방 원점 기준). 없으면 null.
static func marker(room_id: String, marker_name: String) -> Variant:
	var m = room(room_id).get("markers", {}).get(marker_name, null)
	return Vector2(float(m[0]), float(m[1])) if m is Array and m.size() >= 2 else null


## 방의 금 간 벽 secret_id 목록 (부숴야 탐사 완료)
static func cracked(room_id: String) -> Array:
	return room(room_id).get("cracked", [])


## 방의 기록물 id 목록
static func records(room_id: String) -> Array:
	return room(room_id).get("records", [])


## 경전 조각 N(1~4)이 있는 방 (모르면 "")
static func scripture_room(n: int) -> String:
	_ensure()
	return str(_scripture_room.get(n, ""))


## 방에 있는 경전 조각 번호들 (작은 수부터)
static func scriptures_in(room_id: String) -> Array[int]:
	return _scripture_numbers(records(room_id))

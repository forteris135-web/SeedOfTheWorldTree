extends Node
## 세이브. 달빛풀에서 쉴 때 기기 안에 저장한다. 타이틀의 "이어하기"가 읽는다.
## v1.1.0: 저장 칸 3개 (user://save_1.json … save_3.json). 지금 칸(slot)은 타이틀의 칸 고르기가 정한다 (set_slot).
## 저장·불러오기·'지금 저장하기'·'새로 시작'은 모두 지금 칸에만 한다. 처음 켤 때 옛 단일 파일 user://save.json 은 칸 1 로 옮긴다
## (원본은 save.json.bak 으로 이름만 바꿔 남긴다). 칸과 상관없는 해금(엔딩을 봄)은 MetaSave(user://meta.json).
## 보스 러시 중(BossRush.active)에는 저장 파일에 아무것도 쓰지도 지우지도 않는다 (러시는 떼어 둔 진행을 끝나고 되돌린다).

const SLOT_COUNT := 3
## v1.1.0 이전의 단일 저장 파일 (처음 켤 때 칸 1 로 옮긴다)
const OLD_PATH := "user://save.json"
## 지금 칸 (1 ~ SLOT_COUNT)
var slot := 1
## 지금 칸의 저장 파일 경로. set_slot 이 바꾼다 (시험들이 SaveGame.PATH 를 식으로 쓰므로 이름은 그대로).
var PATH := "user://save_1.json"


static func path_of(i: int) -> String:
	return "user://save_%d.json" % i


func _ready() -> void:
	migrate_old_file()
	# 메타 파일이 아직 없고 칸에 클리어 기록이 보이면 메타를 만든다 (옛 저장으로 클리어한 사람의 보스 러시·음악 감상이 칸을 지워도 남게)
	var datas := []
	for i in range(1, SLOT_COUNT + 1):
		datas.append(read_slot(i))
	MetaSave.sync_from_slots(datas)


## 옛 단일 파일(save.json)이 있고 칸 1 이 비어 있으면 칸 1 로 복사하고, 원본은 save.json.bak 으로 이름을 바꾼다 (지우지 않는다).
## 옮겼으면 true. (시험도 부른다)
func migrate_old_file() -> bool:
	if not FileAccess.file_exists(OLD_PATH) or FileAccess.file_exists(path_of(1)):
		return false
	var text := FileAccess.get_file_as_string(OLD_PATH)
	var f := FileAccess.open(path_of(1), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	var bak := OLD_PATH + ".bak"
	var n := 2
	while FileAccess.file_exists(bak):   # 앞선 이주의 .bak 이 있으면 지우지 않고 다른 이름으로 (save.json.bak2 …)
		bak = OLD_PATH + ".bak%d" % n
		n += 1
	if DirAccess.rename_absolute(OLD_PATH, bak) != OK:
		push_warning("save.json 을 save.json.bak 으로 바꾸지 못했다 (칸 1 에는 복사됨)")
	return true


## 지금 칸을 바꾼다 (1 ~ SLOT_COUNT)
func set_slot(i: int) -> void:
	slot = clampi(i, 1, SLOT_COUNT)
	PATH = path_of(slot)


## 지금 칸에 저장이 있는가
func has_save() -> bool:
	return FileAccess.file_exists(PATH)


func has_save_in(i: int) -> bool:
	return FileAccess.file_exists(path_of(i))


## 어느 칸이든 저장이 있는가 (타이틀의 '이어하기')
func any_save() -> bool:
	for i in range(1, SLOT_COUNT + 1):
		if has_save_in(i):
			return true
	return false


## 칸 i 의 저장 내용 (읽기만; 없거나 깨졌으면 빈 사전 — 깨진 파일도 오류 글을 쏟지 않는다)
func read_slot(i: int) -> Dictionary:
	if not has_save_in(i):
		return {}
	return parse_quiet(FileAccess.get_file_as_string(path_of(i)))


## JSON 글을 사전으로 (깨졌으면 빈 사전, 오류 글 없이)
static func parse_quiet(text: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	return j.data if j.data is Dictionary else {}


## 칸 고르기 화면에 보여 줄 칸 i 의 요약.
## {exists, saved_at, saved_at_text, place, difficulty, cleared, version}
## place = 이어질 곳의 이름 (달빛풀이 있는 방 이름 — RoomIndex; 아직 쉰 적이 없으면 저장한 방 이름, 그것도 모르면 "")
func summary_of(i: int) -> Dictionary:
	var out := {"exists": false, "saved_at": "", "saved_at_text": "", "place": "", "difficulty": "normal", "cleared": false, "version": 0}
	if not has_save_in(i):
		return out
	var d := read_slot(i)
	out["exists"] = true
	if d.is_empty():
		out["place"] = "?"   # 깨진 파일: 칸은 차 있다고 보여 주고(지울 수 있게) 이름만 모른다
		return out
	out["saved_at"] = str(d.get("saved_at", ""))
	out["saved_at_text"] = _short_time(out["saved_at"])
	out["difficulty"] = str(d.get("difficulty", "normal")) if Balance.DIFF_MULT.has(str(d.get("difficulty", "normal"))) else "normal"
	var f = d.get("flags", {})
	out["cleared"] = f is Dictionary and bool(f.get("cleared", false))
	out["version"] = int(d.get("version", 1))
	out["place"] = place_of(d)
	return out


## 저장 내용의 '이어질 곳' 이름
static func place_of(d: Dictionary) -> String:
	var gid := str(d.get("grass", ""))
	if gid != "":
		var gs = d.get("grasses", {})
		var gname := gid
		if gs is Dictionary and gs.get(gid) is Dictionary:
			gname = str(gs[gid].get("name", gid))
		return RoomIndex.grass_room_name(gid, gname)
	var scene := str(d.get("scene", ""))
	var room_id := scene.get_file().get_basename()
	var fallback := ""
	var vr = d.get("visited_rooms", {})
	if vr is Dictionary and vr.get(room_id) is Dictionary:
		fallback = str(vr[room_id].get("name", ""))
	return RoomIndex.room_name(room_id, fallback)   # 모르면 "" (칸 고르기가 '여정의 시작'으로 보여 준다)


## 칸 i 를 지운다 (보스 러시 중엔 거절). 그 칸에 클리어 기록이 있으면 먼저 메타에 옮겨 적는다.
func delete_slot(i: int) -> void:
	if BossRush.active or not has_save_in(i):
		return
	MetaSave.remember_slot(read_slot(i))
	DirAccess.remove_absolute(path_of(i))


## 가장 늦게 저장한 칸 (없으면 0). 같으면 지금 칸, 그다음 번호가 작은 칸.
func latest_slot() -> int:
	var best := 0
	var best_at := ""
	for i in range(1, SLOT_COUNT + 1):
		if not has_save_in(i):
			continue
		var at := str(read_slot(i).get("saved_at", ""))
		if best == 0 or at > best_at or (at == best_at and i == slot):
			best = i
			best_at = at
	return best


func save(grass_id: String, scene_path: String) -> void:
	if BossRush.active:
		return
	var data := {
		"version": 2,   # v1.1.0 (새순·난이도). 옛 판(1) 파일은 읽은 뒤 SaveMigrate.after_load 가 고친다
		"saved_at": Time.get_datetime_string_from_system(),
		"grass": grass_id,
		"scene": scene_path,
		"flags": Progress.flags,
		"abilities": Progress.abilities,
		"soul": Progress.soul,
		"upgrades": Progress.upgrades,
		"grasses": Progress.grasses,
		"rescued": Progress.rescued,
		"visited_rooms": _rooms_to_json(Progress.visited_rooms),
		"ending": Progress.ending,
		"purity": Purity.regions,
		"collected": Progress.collected,
		"dust": Progress.dust,
		"tokens": Progress.tokens,
		"difficulty": Progress.difficulty,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()


## 메뉴의 '지금 저장하기': 마지막으로 쉰 달빛풀에서 이어지도록 저장한다.
## 아직 달빛풀에서 쉰 적이 없으면 지금 방의 처음 자리에서 이어진다.
func save_now() -> String:
	if BossRush.active:
		return ""
	var g: Dictionary = Progress.last_grass
	var scene: String = g.get("scene", "")
	if scene == "":
		scene = get_tree().current_scene.scene_file_path
	save(str(g.get("id", "")), scene)
	return str(g.get("name", "지금 방의 처음"))


## 저장한 때 (메뉴 표시용, 지금 칸). 없으면 "".
func saved_at_text() -> String:
	if not has_save():
		return ""
	return _short_time(str(read_slot(slot).get("saved_at", "")))


## "2026-10-18T09:12:33" → "10/18 09:12"
static func _short_time(s: String) -> String:
	if s.length() >= 16:
		return s.substr(5, 5).replace("-", "/") + " " + s.substr(11, 5)
	return s


## 읽어서 진행을 되돌린 뒤, 마지막 달빛풀이 있는 방 경로를 돌려준다. 없으면 "".
func load_game() -> String:
	if not has_save():
		return ""
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	Progress.reset()
	Progress.flags = data.get("flags", {})
	Progress.abilities = data.get("abilities", {})
	Progress.soul = str(data.get("soul", "seed"))   # 옛 저장 파일에는 없다 → 씨앗
	Progress.upgrades = data.get("upgrades", {})
	Progress.grasses = data.get("grasses", {})
	Progress.rescued = data.get("rescued", {})
	Progress.visited_rooms = _rooms_from_json(data.get("visited_rooms", {}))
	MapOffsetFix.fix_saved(Progress.visited_rooms)   # 확장판이 옮긴 방들의 옛 지도 자리 바로잡기
	Progress.ending = data.get("ending", "")
	_fill_last_ending()   # 옛 저장 파일: 마지막 엔딩 깃발(last_ending_*)이 없으면 저장된 엔딩 값으로 채운다
	Progress.collected = data.get("collected", {})   # 옛 저장 파일에는 없다 → 빈 사전
	Progress.dust = int(data.get("dust", 0))
	Progress.dust_changed.emit(Progress.dust)
	Progress.tokens = int(data.get("tokens", 0))   # 옛 저장 파일에는 없다 → 0 (이주가 채운다)
	Progress.difficulty = str(data.get("difficulty", "normal"))   # 옛 저장 파일에는 없다 → Normal
	if not Balance.DIFF_MULT.has(Progress.difficulty):
		Progress.difficulty = "normal"   # 모르는 값 (손으로 고친 파일 등)
	var pur: Dictionary = data.get("purity", {})
	# 먼저 모두 잿빛으로 (저장 파일에 없는 지역 — 예: 나중에 정화한 확장 지역 — 의 정화가 남지 않게)
	for k in Purity.regions:
		Purity.regions[k] = false
	for k in pur:
		Purity.regions[k] = pur[k]
	var gid := str(data.get("grass", ""))
	var scene := str(data.get("scene", ""))
	if gid != "":
		Progress.last_grass = {"id": gid, "scene": scene, "name": Progress.grasses.get(gid, {}).get("name", gid)}
	# 모든 값을 채운 맨 끝에: 옛 판 저장 파일 고치기 (v1 → v2)
	SaveMigrate.after_load(int(data.get("version", 1)))
	Progress.next_spawn = "Grass:" + gid
	return scene


## 엔딩 뒤의 세계(PostEnding)와 마을 사람들의 엔딩 뒤 대사는 깃발 last_ending_<이름> 을 본다.
## 그 깃발이 생기기 전의 빌드로 클리어한 저장 파일에는 cleared + ending_<이름> + "ending" 값만 있다 →
## 엔딩을 본 기록이 있는데 last_ending_* 가 하나도 없으면, 저장된 "ending" 값(없으면 ending_<이름> 깃발)으로 채운다.
## (그 시절 엔딩 장면은 "ending" 값이 비어 있으면 되돌림을 보여 주었다.) 다음 저장 때 깃발이 함께 저장된다.
static func _fill_last_ending() -> void:
	if not Progress.has("cleared"):
		return
	for n in EndingScene.ENDINGS:
		if Progress.has("last_ending_" + n):
			return
	var which := str(Progress.ending)
	if not (which in EndingScene.ENDINGS):
		which = ""
		for n in EndingScene.ENDINGS:
			if Progress.has("ending_" + n):
				which = n   # 여럿이면 마지막 차례의 것 (어느 것을 마지막에 봤는지는 알 수 없다)
		if which == "":
			which = "return"
	Progress.flags["last_ending_" + which] = true


## 지금 칸에 새로 시작한다: 진행을 비우고(잿빛 세계), 고른 난이도를 정하고, 칸의 옛 저장을 지운 뒤 곧바로 첫 저장을 한다
## (칸 고르기에서 이 칸이 '차 있음'으로 보이게; 이어지는 곳은 첫 방의 처음 자리). 지우는 칸에 클리어 기록이 있으면 먼저 메타에 옮긴다.
func new_game(difficulty := "normal") -> void:
	if BossRush.active:
		return
	Progress.reset()
	for k in Purity.regions:
		Purity.regions[k] = false
	Progress.difficulty = difficulty if Balance.DIFF_MULT.has(difficulty) else "normal"
	if has_save():
		MetaSave.remember_slot(read_slot(slot))
		DirAccess.remove_absolute(PATH)
	save("", Game.FIRST_ROOM)


func _rooms_to_json(rooms: Dictionary) -> Dictionary:
	var out := {}
	for id in rooms:
		var r: Dictionary = rooms[id]
		var gs := []
		for g in r.get("grasses", []):
			gs.append([g.x, g.y])
		var ps := []
		for p in r.get("portals", []):
			ps.append([p.x, p.y])
		out[id] = {"offset": [r["offset"].x, r["offset"].y], "size": [r["size"].x, r["size"].y], "name": r.get("name", id), "region": r.get("region", ""), "grasses": gs, "portals": ps, "boss": r.get("boss", false),
			"explore_total": int(r.get("explore_total", 0)), "explore_found": int(r.get("explore_found", 0)),
			"explore_ids": r.get("explore_ids", {})}   # 탐사 요소 id 목록 (글자 배열들) — 구원된 자는 노드가 사라져도 세기 위해
	return out


func _rooms_from_json(rooms: Dictionary) -> Dictionary:
	var out := {}
	for id in rooms:
		var r: Dictionary = rooms[id]
		var gs := []
		for g in r.get("grasses", []):
			gs.append(Vector2(g[0], g[1]))
		var ps := []
		for p in r.get("portals", []):
			ps.append(Vector2(p[0], p[1]))
		out[id] = {"offset": Vector2(r["offset"][0], r["offset"][1]), "size": Vector2(r["size"][0], r["size"][1]), "name": r.get("name", id), "region": r.get("region", ""), "grasses": gs, "portals": ps, "boss": r.get("boss", false),
			"explore_total": int(r.get("explore_total", 0)), "explore_found": int(r.get("explore_found", 0)),
			"explore_ids": r.get("explore_ids", {})}
	return out

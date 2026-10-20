extends Node
## 세이브. 달빛풀에서 쉴 때 기기 안(user://save.json)에 저장한다. 타이틀의 "이어하기"가 읽는다.
## 보스 러시 중(BossRush.active)에는 저장 파일에 아무것도 쓰지도 지우지도 않는다 (러시는 떼어 둔 진행을 끝나고 되돌린다).

const PATH := "user://save.json"


func has_save() -> bool:
	return FileAccess.file_exists(PATH)


func save(grass_id: String, scene_path: String) -> void:
	if BossRush.active:
		return
	var data := {
		"version": 1,
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


## 저장한 때 (메뉴 표시용). 없으면 "".
func saved_at_text() -> String:
	if not has_save():
		return ""
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	var s := str(data.get("saved_at", ""))   # 2026-10-18T09:12:33
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


func new_game() -> void:
	if BossRush.active:
		return
	Progress.reset()
	for k in Purity.regions:
		Purity.regions[k] = false
	if has_save():
		DirAccess.remove_absolute(PATH)


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

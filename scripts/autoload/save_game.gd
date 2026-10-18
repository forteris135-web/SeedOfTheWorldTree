extends Node
## 세이브. 달빛풀에서 쉴 때 기기 안(user://save.json)에 저장한다. 타이틀의 "이어하기"가 읽는다.

const PATH := "user://save.json"


func has_save() -> bool:
	return FileAccess.file_exists(PATH)


func save(grass_id: String, scene_path: String) -> void:
	var data := {
		"version": 1,
		"saved_at": Time.get_datetime_string_from_system(),
		"grass": grass_id,
		"scene": scene_path,
		"flags": Progress.flags,
		"abilities": Progress.abilities,
		"upgrades": Progress.upgrades,
		"grasses": Progress.grasses,
		"rescued": Progress.rescued,
		"visited_rooms": _rooms_to_json(Progress.visited_rooms),
		"ending": Progress.ending,
		"purity": Purity.regions,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))
		f.close()


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
	Progress.upgrades = data.get("upgrades", {})
	Progress.grasses = data.get("grasses", {})
	Progress.rescued = data.get("rescued", {})
	Progress.visited_rooms = _rooms_from_json(data.get("visited_rooms", {}))
	Progress.ending = data.get("ending", "")
	var pur: Dictionary = data.get("purity", {})
	for k in pur:
		Purity.regions[k] = pur[k]
	Progress.next_spawn = "Grass:" + str(data.get("grass", ""))
	return str(data.get("scene", ""))


func new_game() -> void:
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
		out[id] = {"offset": [r["offset"].x, r["offset"].y], "size": [r["size"].x, r["size"].y], "name": r.get("name", id), "region": r.get("region", ""), "grasses": gs, "boss": r.get("boss", false)}
	return out


func _rooms_from_json(rooms: Dictionary) -> Dictionary:
	var out := {}
	for id in rooms:
		var r: Dictionary = rooms[id]
		var gs := []
		for g in r.get("grasses", []):
			gs.append(Vector2(g[0], g[1]))
		out[id] = {"offset": Vector2(r["offset"][0], r["offset"][1]), "size": Vector2(r["size"][0], r["size"][1]), "name": r.get("name", id), "region": r.get("region", ""), "grasses": gs, "boss": r.get("boss", false)}
	return out

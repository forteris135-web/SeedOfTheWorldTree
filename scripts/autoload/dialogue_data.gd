class_name DialogueData
extends RefCounted
## 대사 데이터: 기본 파일에 더해 같은 이름의 `_*.json`(예: npcs_lake.json)을 모두 합쳐 읽는다 (확장판·묶음별 파일 분리용).
static func load_dialogue(base_path: String) -> Dictionary:
	var out: Dictionary = {}
	var dir := base_path.get_base_dir()
	var stem := base_path.get_file().get_basename()
	var files: Array[String] = [base_path]
	var d := DirAccess.open(dir)
	if d:
		for f in d.get_files():
			if f.begins_with(stem + "_") and f.ends_with(".json"):
				files.append(dir + "/" + f)
	for path in files:
		if not FileAccess.file_exists(path):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_merge_into(out, parsed)
	return out


## 깊은 합치기: 같은 키의 사전은 안쪽까지 합치고, 같은 키의 배열(talks 등)은 뒤에 이어 붙인다. 그 밖은 덮어쓴다.
static func _merge_into(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		if dst.has(k) and dst[k] is Dictionary and src[k] is Dictionary:
			_merge_into(dst[k], src[k])
		elif dst.has(k) and dst[k] is Array and src[k] is Array:
			dst[k] = dst[k] + src[k]
		else:
			dst[k] = src[k]

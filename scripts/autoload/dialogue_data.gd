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
			for k in parsed:
				out[k] = parsed[k]
	return out

class_name SaveMigrate
extends RefCounted
## 저장 파일 판 올림. SaveGame.load_game 이 Progress 를 다 채운 뒤 부른다.
static func after_load(from_version: int) -> void:
	pass   # G 가 v1 → v2 를 채운다 (§5.5)

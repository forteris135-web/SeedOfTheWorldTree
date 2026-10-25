class_name MetaSave
extends RefCounted
## 칸과 상관없는 해금 기록 (v1.1.0 저장 칸). user://meta.json 한 파일:
##   {"version": 1, "cleared": 엔딩을 하나라도 봄, "cleared_third": 제3의 길을 봄, "last_ending": 마지막으로 본 엔딩, "endings": {이름: true}}
## 어느 칸에서든 엔딩을 한 번 보면 '보스 러시'·'음악 감상'·클리어 뒤 타이틀 그림이 계속 열려 있다 —
## '새로 시작'으로 칸을 덮어쓰거나 칸을 지워도 사라지지 않는다 (명세 D9).
## 쓰는 곳: 엔딩을 볼 때(EndingScene.mark_seen → mark_ending), 클리어한 칸을 지우기 직전(SaveGame.delete_slot / new_game → remember_slot),
## 앱을 처음 켰을 때 메타 파일이 없고 칸에 클리어 기록이 보이면(SaveGame._ready → sync_from_slots — 옛 저장 파일 이주용).
## 읽기는 매번 파일에서 (작은 파일, 타이틀·엔딩·러시에서만 읽는다). 정적 함수만 있다.

const VERSION := 1
## 시험이 다른 곳을 가리키게 할 수 있도록 var
static var PATH := "user://meta.json"


## 기록 전체 (없거나 깨졌으면 빈 기록). 빠진 열쇠는 기본값으로 채운다. (이름이 load 가 아닌 것은 GDScript 의 load() 와 겹치기 때문)
static func read() -> Dictionary:
	var out := {"version": VERSION, "cleared": false, "cleared_third": false, "last_ending": "", "endings": {}}
	if not FileAccess.file_exists(PATH):
		return out
	var d := SaveGame.parse_quiet(FileAccess.get_file_as_string(PATH))
	if d.is_empty():
		return out
	out["cleared"] = bool(d.get("cleared", false))
	out["cleared_third"] = bool(d.get("cleared_third", false))
	out["last_ending"] = str(d.get("last_ending", ""))
	if d.get("endings") is Dictionary:
		for k in d["endings"]:
			if bool(d["endings"][k]):
				out["endings"][str(k)] = true
	return out


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


## 엔딩 하나를 보았다 (EndingScene.mark_seen 이 부른다). 마지막으로 본 엔딩도 이것으로 바뀐다.
static func mark_ending(name: String) -> void:
	if name == "":
		return
	var m := read()
	m["cleared"] = true
	m["endings"][name] = true
	if name == "third":
		m["cleared_third"] = true
	m["last_ending"] = name
	_write(m)


## 엔딩을 하나라도 보았는가
static func is_cleared() -> bool:
	return bool(read()["cleared"])


## 마지막으로 본 엔딩 (없으면 "")
static func last_ending() -> String:
	return str(read()["last_ending"])


## 저장 칸 하나의 내용(읽은 사전)에 있는 클리어 기록을 메타에 옮겨 적는다 — 그 칸을 지우기 직전에 부른다.
## 메타에 이미 마지막 엔딩이 있으면 그것은 그대로 둔다 (메타가 더 새 기록). 옮길 것이 없으면 파일을 건드리지 않는다.
static func remember_slot(data: Dictionary) -> void:
	var f = data.get("flags", {})
	if not (f is Dictionary) or not bool(f.get("cleared", false)):
		return
	var m := read()
	var before := JSON.stringify(m)
	m["cleared"] = true
	if bool(f.get("cleared_third", false)):
		m["cleared_third"] = true
	var last := ""
	for n in EndingScene.ENDINGS:
		if bool(f.get("ending_" + n, false)):
			m["endings"][n] = true
		if bool(f.get("last_ending_" + n, false)):
			last = n
	if last == "" and str(data.get("ending", "")) in EndingScene.ENDINGS:
		last = str(data.get("ending", ""))
	if last != "":
		m["endings"][last] = true
		if str(m["last_ending"]) == "":
			m["last_ending"] = last
	if JSON.stringify(m) != before:
		_write(m)


## 앱을 켤 때 (SaveGame._ready): 메타 파일이 아직 없고 어느 칸에 클리어 기록이 있으면 메타를 만든다
## (v1.1.0 이전에 클리어한 저장 파일 → 칸 1 로 옮긴 뒤 처음 켤 때). 칸들은 저장한 때 순서로 옮겨, 가장 늦게 저장한 칸의 엔딩이 마지막 엔딩이 된다.
static func sync_from_slots(slot_datas: Array) -> void:
	if exists():
		return
	var cleared := []
	for d in slot_datas:
		if d is Dictionary and d.get("flags") is Dictionary and bool(d["flags"].get("cleared", false)):
			cleared.append(d)
	if cleared.is_empty():
		return
	# 늦게 저장한 칸이 먼저 옮겨져야 그 칸의 엔딩이 '마지막 엔딩'으로 남는다 (remember_slot 은 이미 있는 마지막 엔딩을 두므로)
	cleared.sort_custom(func(a, b): return str(a.get("saved_at", "")) > str(b.get("saved_at", "")))
	for d in cleared:
		remember_slot(d)


static func _write(m: Dictionary) -> void:
	m["version"] = VERSION
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(m, "  "))
		f.close()

extends Node
## 저장 칸·난이도·타이틀 시험 (v1.1.0 묶음 S). 화면 없이 돈다.
## 실행: godot --headless --path . res://tools/probe_slots.tscn
##       그림 확인용(화면 있게): godot --path . res://tools/probe_slots.tscn -- --shots --out=/절대/경로 [--size=1280x960] [--device=ds|xb|kb|touch]
##  1) 옛 단일 저장 save.json → 칸 1 로 옮김 (+ save.json.bak, 이미 있는 .bak 은 지우지 않음), 칸 1 이 차 있으면 옮기지 않음, 켤 때(SaveGame._ready) 옮김.
##  2) 칸 세 개가 따로 저장·불러오기 (깃발·빛 가루·새순·난이도·성장), 저장 판 2 와 새순·난이도 필드.
##  3) 새로 시작은 지금 칸만 지우고 곧바로 첫 저장 (다른 칸 한 바이트도 안 바뀜), 고른 난이도, 러시 중엔 거절.
##  4) 난이도 저장·불러오기, 옛 파일·모르는 값은 Normal.
##  5) 메타 해금: 칸을 지우거나 덮어써도 클리어 기록이 남는다, 엔딩을 보면 메타에 적힌다, 켤 때 칸에서 메타 만들기, 타이틀 판단(cleared_state).
##  6) 가장 늦게 저장한 칸 (latest_slot), 칸 요약(이어질 곳·난이도·저장한 때·클리어), 깨진 파일.
##  7) 보스 러시: 몸 = 엔딩을 본 칸 가운데 가장 늦게 저장한 칸 (새순 단계 포함; 막 새로 시작한 칸·능력 없는 칸은 건너뜀, 없으면 다 자란 몸),
##     러시 난이도 = 그 칸의 난이도 (다 자란 몸 Normal), 최고 기록 난이도별(옛 한 덩어리 = Normal), 결과 화면 난이도 이름.
##  8) 타이틀: 저장 없으면 '이어하기' 없음, 버전 글자, 이어하기 → 칸 고르기(찬 칸만) → 불러오기, 새로 시작 → 칸 고르기(덮어쓰기 두 번) → 난이도 고르기
##     (돌아가기 → 칸 고르기) → 그 칸에 새로 시작. 칸 지우기: 키보드 X · 패드 △/Y · 터치 길게 누르기 · 마우스 오른쪽, 두 번 확인. 터치 누르기, 바깥 누르기 = 돌아가기.
##  9) 일시정지 메뉴: '난이도' 줄 (좌우 4단계 · 결정은 돌아감 · 러시·타이틀 설정에선 없음), 저장·불러오기 값에 "칸 N", 줄이 많아도 화면 안.
## 기기의 user:// 파일(save*.json, meta.json, boss_rush.json)은 시험 전에 떠 두었다가 끝나고 되돌린다.
## 마지막 줄 "[probe] 끝: 실패 N".

const FIRST := "res://scenes/rooms/canopy_01.tscn"

var _fail := 0
var _shots := false
var _out := ""
var _backup := {}


func _ready() -> void:
	print("[probe] 시작: 저장 칸·난이도·타이틀")
	var args := OS.get_cmdline_user_args()
	_shots = "--shots" in args and DisplayServer.get_name() != "headless"
	_out = ProjectSettings.globalize_path("res://screenshots")
	for a in args:
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--size="):
			var p := a.trim_prefix("--size=").split("x")
			get_window().size = Vector2i(int(p[0]), int(p[1]))
	_backup_files()
	Game._busy = true   # 장면 바꾸기는 막는다 (타이틀이 고른 칸·난이도까지만 본다)
	await get_tree().process_frame
	if _shots:
		await _take_shots(args)
	else:
		await _run()
	Game._busy = false
	_restore_files()
	Progress.reset()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


# ---------- 파일 떠 두기 ----------

func _managed() -> Array:
	var out := [SaveGame.OLD_PATH, MetaSave.PATH, BossRush.BEST_PATH]
	for i in range(1, SaveGame.SLOT_COUNT + 1):
		out.append(SaveGame.path_of(i))
	out.append(SaveGame.OLD_PATH + ".bak")
	for n in range(2, 6):
		out.append(SaveGame.OLD_PATH + ".bak%d" % n)
	return out


func _backup_files() -> void:
	for p in _managed():
		_backup[p] = FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else null


func _restore_files() -> void:
	for p in _managed():
		var b = _backup.get(p, null)
		if b == null:
			_rm(p)
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_buffer(b)
			f.close()
	SaveGame.set_slot(1)


func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _clear_all() -> void:
	for p in _managed():
		_rm(p)
	SaveGame.set_slot(1)


func _write(path: String, d: Dictionary) -> String:
	var s := JSON.stringify(d, "  ")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(s)
	f.close()
	return s


func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


func _bytes(i: int) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(SaveGame.path_of(i)) if SaveGame.has_save_in(i) else PackedByteArray()


## 칸 i 에 저장 파일 한 개 (요약·타이틀 시험용)
func _slot_file(i: int, saved_at: String, extra := {}) -> void:
	var d := {"version": 2, "saved_at": saved_at, "grass": "", "scene": FIRST, "flags": {"slot%d_flag" % i: true}, "abilities": {}, "soul": "seed",
		"upgrades": {}, "grasses": {}, "rescued": {}, "visited_rooms": {}, "ending": "", "purity": {}, "collected": {}, "dust": 10 * i, "tokens": i, "difficulty": "normal"}
	d.merge(extra, true)
	_write(SaveGame.path_of(i), d)


func _run() -> void:
	_clear_all()
	Progress.reset()
	_probe_migration()
	_probe_slots_independent()
	_probe_new_game()
	_probe_difficulty_io()
	_probe_meta()
	_probe_latest_and_summary()
	await _probe_rush()
	await _probe_title_ui()
	await _probe_pause()
	_clear_all()


# ---------- 1) 옛 save.json → 칸 1 ----------
func _probe_migration() -> void:
	_clear_all()
	var old := _write(SaveGame.OLD_PATH, {"version": 1, "saved_at": "2026-10-01T10:00:00", "flags": {"met_tia": true}, "grass": "canopy_start", "scene": FIRST,
		"grasses": {"canopy_start": {"scene": FIRST, "name": "수관 · 시작의 가지"}}, "upgrades": {"max_hp": 10.0}, "dust": 55})
	var moved := SaveGame.migrate_old_file()
	_check(moved and FileAccess.get_file_as_string(SaveGame.path_of(1)) == old and not FileAccess.file_exists(SaveGame.OLD_PATH)
		and FileAccess.get_file_as_string(SaveGame.OLD_PATH + ".bak") == old,
		"옛 save.json → save_1.json 으로 복사, 원본은 save.json.bak 으로 (옮김 %s)" % moved)
	SaveGame.set_slot(1)
	Progress.reset()
	var scene := SaveGame.load_game()
	_check(scene == FIRST and Progress.dust == 55 and Progress.has("met_tia") and Progress.difficulty == "normal" and Progress.last_grass.get("id", "") == "canopy_start",
		"옮긴 칸 1 이어하기: 빛 가루 %d, 깃발 met_tia %s, 난이도 %s (옛 파일 → Normal)" % [Progress.dust, Progress.has("met_tia"), Progress.difficulty])
	# 칸 1 이 차 있으면 옮기지 않는다
	var old2 := _write(SaveGame.OLD_PATH, {"version": 1, "saved_at": "2026-10-02T10:00:00", "flags": {"second": true}, "dust": 7})
	var moved2 := SaveGame.migrate_old_file()
	_check(not moved2 and FileAccess.get_file_as_string(SaveGame.path_of(1)) == old and FileAccess.file_exists(SaveGame.OLD_PATH),
		"칸 1 이 차 있으면 save.json 을 옮기지 않는다 (칸 1 그대로)")
	# 칸 1 을 비운 뒤 다시: 앞선 .bak 은 지우지 않고 .bak2 로
	_rm(SaveGame.path_of(1))
	var moved3 := SaveGame.migrate_old_file()
	_check(moved3 and FileAccess.get_file_as_string(SaveGame.path_of(1)) == old2 and FileAccess.get_file_as_string(SaveGame.OLD_PATH + ".bak") == old
		and FileAccess.get_file_as_string(SaveGame.OLD_PATH + ".bak2") == old2,
		"다시 옮길 때 앞선 save.json.bak 은 남기고 save.json.bak2 로")
	# 켤 때 (SaveGame._ready): 옮기고, 그 파일이 클리어한 저장이면 메타도 만든다
	_clear_all()
	_write(SaveGame.OLD_PATH, {"version": 1, "saved_at": "2026-10-03T10:00:00", "flags": {"cleared": true, "ending_return": true, "last_ending_return": true}, "ending": "return", "scene": FIRST})
	SaveGame._ready()
	var m := MetaSave.read()
	_check(SaveGame.has_save_in(1) and not FileAccess.file_exists(SaveGame.OLD_PATH) and MetaSave.exists() and bool(m["cleared"]) and m["last_ending"] == "return",
		"켤 때: 옛 클리어 저장을 칸 1 로 옮기고 메타에 클리어·마지막 엔딩(%s) 기록" % m["last_ending"])
	_clear_all()


# ---------- 2) 칸 세 개 따로 ----------
func _probe_slots_independent() -> void:
	_clear_all()
	for i in [1, 2, 3]:
		SaveGame.set_slot(i)
		Progress.reset()
		Progress.flags = {"only_slot_%d" % i: true}
		Progress.dust = 100 * i
		Progress.tokens = i + 4
		Progress.difficulty = Balance.DIFFICULTIES[i]
		Progress.upgrades = {"tok_wind": float(i), "max_hp": 10.0 * i}
		SaveGame.save("", FIRST)
	var ok := true
	var info := []
	for i in [3, 1, 2]:
		SaveGame.set_slot(i)
		Progress.reset()
		SaveGame.load_game()
		var good: bool = SaveGame.PATH == SaveGame.path_of(i) and SaveGame.has_save() and Progress.flags.size() == 1 and Progress.has("only_slot_%d" % i) \
			and Progress.dust == 100 * i and Progress.tokens == i + 4 and Progress.difficulty == Balance.DIFFICULTIES[i] and int(Progress.upgrades.get("tok_wind", 0)) == i
		info.append("칸%d %s/%d/%d/%s" % [i, Progress.flags.keys(), Progress.dust, Progress.tokens, Progress.difficulty])
		ok = ok and good
	_check(ok, "칸 세 개가 따로 저장·불러오기 (깃발·빛 가루·새순·난이도·새순 단계) %s" % [info])
	var raw := _read(SaveGame.path_of(2))
	_check(int(raw.get("version", 0)) == 2 and int(raw.get("tokens", -1)) == 6 and str(raw.get("difficulty", "")) == "hard",
		"저장 파일: 판 2, tokens %s, difficulty %s" % [raw.get("tokens", "-"), raw.get("difficulty", "-")])
	# 새순 왕복
	SaveGame.set_slot(1)
	Progress.reset()
	Progress.tokens = 13
	SaveGame.save("", FIRST)
	Progress.reset()
	SaveGame.load_game()
	_check(Progress.tokens == 13, "새순 저장 → 불러오기 %d" % Progress.tokens)


# ---------- 3) 새로 시작 ----------
func _probe_new_game() -> void:
	var b1 := _bytes(1)
	var b2 := _bytes(2)
	SaveGame.set_slot(3)
	Progress.flags = {"left_over": true}
	Progress.ending = "return"
	Purity.regions["canopy"] = true
	SaveGame.new_game("hard")
	var d := _read(SaveGame.path_of(3))
	var ash := true
	for k in Purity.regions:
		ash = ash and not Purity.regions[k]
	_check(SaveGame.has_save_in(3) and int(d.get("version", 0)) == 2 and str(d.get("difficulty", "")) == "hard" and str(d.get("scene", "")) == Game.FIRST_ROOM
		and str(d.get("grass", "x")) == "" and (d.get("flags", {}) as Dictionary).is_empty() and Progress.difficulty == "hard" and Progress.flags.is_empty() and ash,
		"새로 시작(Hard): 칸 3 을 비우고 곧바로 첫 저장 (판 2, 첫 방, 난이도 hard, 깃발 없음, 잿빛)")
	_check(_bytes(1) == b1 and _bytes(2) == b2, "새로 시작은 다른 칸(1·2)을 한 바이트도 바꾸지 않는다")
	SaveGame.new_game("insane")
	_check(Progress.difficulty == "normal" and str(_read(SaveGame.path_of(3)).get("difficulty", "")) == "normal", "모르는 난이도로 새로 시작 → Normal")
	var b3 := _bytes(3)
	BossRush.active = true
	SaveGame.new_game("easy")
	SaveGame.delete_slot(3)
	BossRush.active = false
	_check(_bytes(3) == b3, "보스 러시 중엔 새로 시작·칸 지우기가 저장 파일을 건드리지 않는다")


# ---------- 4) 난이도 ----------
func _probe_difficulty_io() -> void:
	SaveGame.set_slot(1)
	Progress.reset()
	Progress.difficulty = "nightmare"
	SaveGame.save("", FIRST)
	Progress.reset()
	SaveGame.load_game()
	var a := Progress.difficulty
	_write(SaveGame.path_of(1), {"version": 1, "saved_at": "2026-10-01T10:00:00", "flags": {}, "scene": FIRST})
	Progress.difficulty = "hard"
	SaveGame.load_game()
	var b := Progress.difficulty
	_write(SaveGame.path_of(1), {"version": 2, "saved_at": "2026-10-01T10:00:00", "flags": {}, "scene": FIRST, "difficulty": "weird"})
	SaveGame.load_game()
	var c := Progress.difficulty
	_check(a == "nightmare" and b == "normal" and c == "normal", "난이도 저장·불러오기 %s, 옛 파일 → %s, 모르는 값 → %s" % [a, b, c])


# ---------- 5) 메타 해금 ----------
func _probe_meta() -> void:
	_clear_all()
	Progress.reset()
	_slot_file(2, "2026-10-05T10:00:00", {"flags": {"cleared": true, "ending_return": true, "last_ending_return": true}, "ending": "return"})
	var st0: Dictionary = TitleScreen.cleared_state()
	_check(not MetaSave.exists() and st0["cleared"] and st0["ending"] == "return", "메타가 없어도 클리어한 칸이 있으면 타이틀은 클리어 (%s)" % st0["ending"])
	SaveGame.delete_slot(2)
	var m := MetaSave.read()
	var st1: Dictionary = TitleScreen.cleared_state()
	_check(not SaveGame.has_save_in(2) and bool(m["cleared"]) and m["last_ending"] == "return" and m["endings"].has("return") and st1["cleared"] and st1["ending"] == "return" and not SaveGame.any_save(),
		"클리어한 칸 2 를 지워도 메타에 남는다 → 저장이 하나도 없어도 타이틀은 클리어 (마지막 엔딩 %s)" % st1["ending"])
	# 덮어쓰기(새로 시작)로 지워지는 칸의 기록도 옮긴다 — 메타의 마지막 엔딩(더 새 기록)은 그대로
	_slot_file(1, "2026-10-06T10:00:00", {"flags": {"cleared": true, "cleared_third": true, "ending_third": true, "last_ending_third": true}, "ending": "third"})
	SaveGame.set_slot(1)
	SaveGame.new_game()
	m = MetaSave.read()
	_check(bool(m["cleared_third"]) and m["endings"].has("third") and m["last_ending"] == "return" and TitleScreen.cleared_state()["third"],
		"제3의 길을 본 칸을 새로 시작으로 덮어써도 '제3의 길 봄'이 남는다 (마지막 엔딩은 메타의 %s 그대로)" % m["last_ending"])
	# 엔딩을 보면 메타에 적힌다
	EndingScene.mark_seen("sacrifice")
	m = MetaSave.read()
	_check(m["last_ending"] == "sacrifice" and m["endings"].has("sacrifice") and Progress.has("last_ending_sacrifice"), "엔딩을 보면(mark_seen) 메타의 마지막 엔딩 = sacrifice")
	# 지금 진행이 먼저: 진행에 엔딩 기록이 있으면 그것 (메타보다)
	Progress.reset()
	Progress.flags = {"cleared": true, "last_ending_third": true}
	_check(TitleScreen.cleared_state()["ending"] == "third", "타이틀의 마지막 엔딩은 지금 진행이 먼저 (third)")
	Progress.reset()
	_check(TitleScreen.cleared_state()["ending"] == "sacrifice", "진행이 비면 메타의 마지막 엔딩 (sacrifice)")
	# 켤 때 메타 만들기: 메타가 없고 클리어한 칸이 둘이면 늦게 저장한 칸의 엔딩이 마지막
	_clear_all()
	_slot_file(1, "2026-10-01T10:00:00", {"flags": {"cleared": true, "last_ending_return": true}})
	_slot_file(3, "2026-10-09T10:00:00", {"flags": {"cleared": true, "last_ending_sacrifice": true}})
	SaveGame._ready()
	m = MetaSave.read()
	_check(MetaSave.exists() and bool(m["cleared"]) and m["last_ending"] == "sacrifice", "켤 때 메타 만들기: 늦게 저장한 칸 3 의 엔딩이 마지막 (%s)" % m["last_ending"])
	var mb := FileAccess.get_file_as_bytes(MetaSave.PATH)
	_slot_file(2, "2026-10-12T10:00:00", {"flags": {"cleared": true, "last_ending_third": true}})
	SaveGame._ready()
	_check(FileAccess.get_file_as_bytes(MetaSave.PATH) == mb, "메타가 이미 있으면 켤 때 다시 만들지 않는다")
	_clear_all()
	_slot_file(1, "2026-10-01T10:00:00")
	SaveGame._ready()
	_check(not MetaSave.exists() and not TitleScreen.cleared_state()["cleared"], "클리어한 칸이 없으면 메타 파일을 만들지 않고, 타이틀은 클리어 전")
	_clear_all()
	Progress.reset()


# ---------- 6) 가장 늦은 칸 · 요약 ----------
func _probe_latest_and_summary() -> void:
	_clear_all()
	_check(SaveGame.latest_slot() == 0 and not SaveGame.any_save() and not SaveGame.summary_of(2)["exists"], "저장이 없으면 latest_slot 0, any_save 거짓")
	_slot_file(1, "2026-10-20T10:00:00")
	_slot_file(2, "2026-10-22T09:00:00")
	_slot_file(3, "2026-10-24T13:05:00", {"difficulty": "hard", "grass": "canopy_02_top", "flags": {"cleared": true},
		"grasses": {"canopy_02_top": {"scene": "res://scenes/rooms/canopy_02.tscn", "name": "수관 · 바람의 틈 위"}}})
	_check(SaveGame.latest_slot() == 3 and SaveGame.any_save(), "가장 늦게 저장한 칸 = 3 (%d)" % SaveGame.latest_slot())
	_slot_file(1, "2026-10-25T08:00:00")
	_check(SaveGame.latest_slot() == 1, "칸 1 을 더 늦게 저장하면 latest_slot = 1")
	var s3 := SaveGame.summary_of(3)
	var want_place := RoomIndex.grass_room_name("canopy_02_top", "수관 · 바람의 틈 위")
	_check(s3["exists"] and s3["saved_at_text"] == "10/24 13:05" and s3["difficulty"] == "hard" and s3["cleared"] and s3["place"] == want_place and s3["place"] != "" and int(s3["version"]) == 2,
		"칸 3 요약: '%s' · %s · %s · 클리어 %s" % [s3["place"], s3["difficulty"], s3["saved_at_text"], s3["cleared"]])
	var s1 := SaveGame.summary_of(1)
	_check(s1["exists"] and not s1["cleared"] and s1["place"] == RoomIndex.room_name("canopy_01", ""), "달빛풀 없이 저장한 칸 1: 이어질 곳 = 방 이름 ('%s', 모르면 칸 고르기가 '여정의 시작')" % s1["place"])
	var f := FileAccess.open(SaveGame.path_of(2), FileAccess.WRITE)
	f.store_string("{{{ 깨진 파일")
	f.close()
	var s2 := SaveGame.summary_of(2)
	_check(s2["exists"] and s2["place"] == "?" and SaveGame.read_slot(2).is_empty(), "깨진 칸 2: 차 있음(지울 수 있게), 이름은 '?'")
	_clear_all()


# ---------- 7) 보스 러시 ----------
func _probe_rush() -> void:
	_clear_all()
	var g0 := BossRush.growth_from_save()
	_check(g0["source"] == "full" and g0["difficulty"] == "normal" and int(g0["slot"]) == 0, "저장이 없으면 러시 몸 = 다 자란 몸, 난이도 Normal")
	_slot_file(1, "2026-10-20T10:00:00", {"difficulty": "hard", "upgrades": {"max_hp": 30.0, "tok_seed": 2.0}, "abilities": {"double_jump": true}})
	_slot_file(2, "2026-10-23T10:00:00", {"difficulty": "easy", "upgrades": {"max_hp": 50.0, "tok_wind": 3.0}, "abilities": {"wind": true}, "tokens": 4, "soul": "wind"})
	var gn := BossRush.growth_from_save()
	_check(gn["source"] == "full" and gn["difficulty"] == "normal", "엔딩을 본 칸이 없으면(메타로만 열림) 러시 몸 = 다 자란 몸, Normal (%s)" % gn["source"])
	_slot_file(1, "2026-10-20T10:00:00", {"difficulty": "hard", "upgrades": {"max_hp": 30.0, "tok_seed": 2.0}, "abilities": {"double_jump": true}, "flags": {"cleared": true}})
	_slot_file(2, "2026-10-23T10:00:00", {"difficulty": "easy", "upgrades": {"max_hp": 50.0, "tok_wind": 3.0}, "abilities": {"wind": true}, "tokens": 4, "soul": "wind", "flags": {"cleared": true}})
	SaveGame.set_slot(1)   # 지금 칸이 아니라 '엔딩을 본 칸 가운데 가장 늦게 저장한 칸'이 기준
	var g := BossRush.growth_from_save()
	_check(g["source"] == "save" and int(g["slot"]) == 2 and g["difficulty"] == "easy" and int(g["upgrades"].get("tok_wind", 0)) == 3 and int(g["tokens"]) == 4
		and g["abilities"].has("wind") and g["soul"] == "wind",
		"러시 몸 = 엔딩을 본 칸 중 가장 늦게 저장한 칸 2 (난이도 %s, 새순 단계 tok_wind %s, 새순 %s)" % [g["difficulty"], g["upgrades"].get("tok_wind", "-"), g["tokens"]])
	# 칸 3 에서 막 새로 시작(곧바로 첫 저장 → 가장 늦은 칸)해도 러시는 그 빈 몸을 쓰지 않는다
	SaveGame.set_slot(3)
	SaveGame.new_game("nightmare")
	var g3 := BossRush.growth_from_save()
	_check(SaveGame.latest_slot() == 3 and g3["source"] == "save" and int(g3["slot"]) == 2 and g3["difficulty"] == "easy" and g3["abilities"].has("wind"),
		"다른 칸에서 막 새로 시작해도(가장 늦은 칸 %d) 러시 몸 = 엔딩을 본 칸 %d, 난이도 %s" % [SaveGame.latest_slot(), int(g3["slot"]), g3["difficulty"]])
	_slot_file(3, "2026-10-25T10:00:00", {"difficulty": "hard", "flags": {"cleared": true}})
	var ge := BossRush.growth_from_save()
	_check(ge["source"] == "full" and ge["difficulty"] == "normal" and ge["abilities"].has("double_jump"), "엔딩을 본 칸이라도 능력 기록이 비어 있으면 다 자란 몸 (%s)" % ge["source"])
	DirAccess.remove_absolute(SaveGame.path_of(3))
	SaveGame.set_slot(1)
	Progress.reset()
	var snap := BossRush._take_snapshot()
	var keep_dust := Progress.dust
	BossRush._setup_progress(g)
	var set_ok := Progress.difficulty == "easy" and Progress.tokens == 4 and Progress.killed.is_empty() and Progress.carry_hp < 0.0 and Progress.carry_dews < 0 \
		and int(Progress.upgrades.get("tok_wind", 0)) == 3 and Balance.diff_mult() == 0.7
	BossRush._snapshot = snap
	BossRush.active = true
	BossRush.restore()
	_check(set_ok and not BossRush.active and Progress.dust == keep_dust and "difficulty" in BossRush.PROGRESS_FIELDS and "tokens" in BossRush.PROGRESS_FIELDS,
		"러시용 진행: 난이도 easy(×0.7)·새순 4·쓰러뜨린 적 비움, 끝나면 되돌림")
	# 최고 기록: 옛 한 덩어리 = Normal, 난이도별로 따로
	_write(BossRush.BEST_PATH, {"best_total": 100.0, "best_splits": [20, 20, 20, 20, 20], "best_at": "2026-10-20T10:00:00", "split_bests": {"bird": 20.0}, "clears": 1, "attempts": 2})
	var bn := BossRush.load_best("normal")
	var bh := BossRush.load_best("hard")
	_check(is_equal_approx(float(bn["best_total"]), 100.0) and int(bn["attempts"]) == 2 and float(bh["best_total"]) < 0.0 and int(bh["attempts"]) == 0,
		"옛 최고 기록 파일(한 덩어리)은 Normal 의 기록으로 읽는다, Hard 는 비어 있음")
	BossRush.difficulty = "hard"
	var r := {"outcome": "clear", "splits": [10.0, 10.0, 10.0, 10.0, 10.0], "total": 50.0, "difficulty": "hard"}
	BossRush._record_best(r)
	var all := _read(BossRush.BEST_PATH)
	_check(r["new_best"] and all.has("normal") and all.has("hard") and is_equal_approx(float(all["normal"]["best_total"]), 100.0)
		and is_equal_approx(float(all["hard"]["best_total"]), 50.0) and int(all["hard"]["clears"]) == 1 and is_equal_approx(float(BossRush.load_best()["best_total"]), 50.0),
		"Hard 완주 기록은 hard 칸에 (Normal 100초 그대로, Hard 50초 새 기록), 파일 열쇠 %s" % [all.keys()])
	var r2 := {"outcome": "dead", "splits": [5.0], "total": 9.0, "difficulty": "normal"}
	BossRush._record_best(r2)
	_check(int(BossRush.load_best("normal")["attempts"]) == 3 and is_equal_approx(float(BossRush.load_best("normal")["best_total"]), 100.0) and int(BossRush.load_best("hard")["attempts"]) == 1,
		"Normal 에서 쓰러짐: Normal 도전 수만 늘고 Hard 는 그대로")
	BossRush.difficulty = "normal"
	# 결과 화면의 난이도 이름
	BossRush.result = {"outcome": "clear", "reached": 4, "splits": [10.0, 10.0, 10.0, 10.0, 10.0], "current": 0.0, "total": 50.0, "growth": "save", "difficulty": "hard",
		"new_best": true, "best_total": 50.0, "split_bests": {}}
	var res: BossRushResult = load(BossRush.RESULT_SCENE).instantiate()
	add_child(res)
	await _frames(2)
	_check(res.difficulty_name() == "Hard", "결과 화면에 러시 난이도 이름 (%s)" % res.difficulty_name())
	res.queue_free()
	BossRush.result = {}
	await _frames(2)
	Music.stop(0.0)
	_clear_all()


# ---------- 8) 타이틀 ----------
func _title() -> TitleScreen:
	var t: TitleScreen = load(Game.TITLE_SCENE).instantiate()
	add_child(t)
	await _frames(5)
	return t


func _drop(t: Node) -> void:
	t.queue_free()
	await _frames(2)
	Music.stop(0.0)


func _act(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)


func _pad_y() -> void:
	for pressed in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = JOY_BUTTON_Y
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)


## 화면(캔버스) 좌표의 한 점을 손가락으로 누른다 (hold 초 동안). 진짜 입력 길이라 '흉내 낸 마우스'도 함께 들어온다.
func _touch(pos: Vector2, hold := 0.0) -> void:
	var wpos: Vector2 = get_tree().root.get_final_transform() * pos
	var ev := InputEventScreenTouch.new()
	ev.position = wpos
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	if hold > 0.0:
		await _wait(hold)
	var up := InputEventScreenTouch.new()
	up.position = wpos
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func _right_click(pos: Vector2) -> void:
	var wpos: Vector2 = get_tree().root.get_final_transform() * pos
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = wpos
		ev.global_position = wpos
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)


func _probe_title_ui() -> void:
	_clear_all()
	Progress.reset()
	# 저장이 없으면 '이어하기' 없음, 버전 글자
	var t := await _title()
	var ver: Label = t.get_node("BuildVersion")
	_check(not t.has_item("Continue") and t.has_item("Start") and not t.has_item("BossRush") and not t.has_item("MusicRoom"), "저장이 없는 타이틀: '이어하기'·'보스 러시'·'음악 감상' 없음")
	_check(ver.text == "v1.1.0" and ver.text == "v" + str(ProjectSettings.get_setting("application/config/version")) and ver.get_global_rect().position.x > t.size.x * 0.6,
		"오른쪽 아래 버전 글자 '%s'" % ver.text)
	await _drop(t)
	# 이어하기 → 칸 고르기 (찬 칸만) → 불러오기
	_slot_file(2, "2026-10-21T10:00:00", {"flags": {"slot2_flag": true}, "dust": 222})
	t = await _title()
	_check(t.has_item("Continue"), "칸 2 에만 저장이 있어도 '이어하기'가 생긴다")
	t.activate_item("Continue")
	await _frames(2)
	var sp: SlotPicker = t.slot_picker()
	_check(sp != null and sp.is_open() and t.picker_open() and sp.mode == "load" and sp.selected() == 1 and not sp.selectable(0) and not sp.selectable(2),
		"이어하기 → 칸 고르기(불러오기): 가장 늦은 칸 2 에 고름, 빈 칸 1·3 은 고를 수 없음")
	await _act("move_down")
	var a := sp.selected()
	await _act("move_down")
	var b := sp.selected()
	await _act("move_up")
	var c := sp.selected()
	_check(a == sp.back_index() and b == 1 and c == sp.back_index(), "↓ → 돌아가기, ↓ → 빈 칸을 건너 칸 2, ↑ → 돌아가기 (%d/%d/%d)" % [a, b, c])
	await _act("move_down")
	Progress.reset()
	await _act("jump")
	_check(t._started and SaveGame.slot == 2 and Progress.has("slot2_flag") and Progress.dust == 222, "칸 2 를 고르면 칸 2 를 불러온다 (지금 칸 %d, 빛 가루 %d)" % [SaveGame.slot, Progress.dust])
	await _drop(t)
	# 새로 시작 → 칸 고르기: 빈 칸에 고름, 찬 칸은 두 번 → 난이도 고르기 → 돌아가기 → 다시 → Nightmare
	t = await _title()
	t.activate_item("Start")
	await _frames(2)
	sp = t.slot_picker()
	_check(sp.is_open() and sp.mode == "new" and sp.selected() == 0 and sp.selectable(0) and sp.selectable(2), "새로 시작 → 칸 고르기(새로): 세 칸 모두, 첫 빈 칸 1 에 고름")
	var b2 := _bytes(2)
	await _act("move_down")
	await _act("jump")
	var dp: DifficultyPicker = t.difficulty_picker()
	_check(sp.confirming() == 1 and (dp == null or not dp.is_open()) and _bytes(2) == b2, "찬 칸 2 를 한 번 누르면 확인만 (덮어쓰기 경고, 저장 그대로)")
	await _act("move_up")
	_check(sp.confirming() == -1, "다른 칸으로 옮기면 확인을 거둔다")
	await _act("move_down")
	await _act("jump")
	await _act("jump")
	dp = t.difficulty_picker()
	_check(dp != null and dp.is_open() and not sp.is_open() and dp.selected() == 1 and dp.slot == 2 and _bytes(2) == b2,
		"두 번 누르면 난이도 고르기 (기본 Normal, 칸 2) — 아직 저장은 그대로")
	await _act("dodge")
	_check(not dp.is_open() and sp.is_open() and sp.mode == "new" and sp.selected() == 1, "난이도에서 돌아가기 → 칸 고르기 (칸 2)")
	await _act("jump")
	await _act("jump")
	await _act("move_down")
	await _act("move_down")
	_check(dp.selected() == 3, "↓↓ → Nightmare")
	await _act("jump")
	var d2 := _read(SaveGame.path_of(2))
	_check(t._started and SaveGame.slot == 2 and str(d2.get("difficulty", "")) == "nightmare" and not (d2.get("flags", {}) as Dictionary).has("slot2_flag") and Progress.difficulty == "nightmare"
		and not SaveGame.has_save_in(1) and not SaveGame.has_save_in(3),
		"Nightmare 로 칸 2 에 새로 시작 (옛 저장 지움, 첫 저장 nightmare), 칸 1·3 은 빈 채")
	await _drop(t)
	# 칸 지우기: 키보드 X 두 번
	t = await _title()
	t.activate_item("Start")
	await _frames(2)
	sp = t.slot_picker()
	await _act("move_down")
	await _key(KEY_X)
	var armed := sp.delete_armed()
	await _key(KEY_X)   # 곧바로 한 번 더 (연타) → 받지 않는다
	var still := SaveGame.has_save_in(2) and sp.delete_armed() == 1
	await _wait(0.5)
	await _key(KEY_X)
	_check(armed == 1 and still and not SaveGame.has_save_in(2) and sp.is_open() and sp.delete_armed() == -1,
		"키보드 X 한 번 → 지우기 확인, 곧바로 연타는 무시, 잠시 뒤 한 번 더 → 칸 2 지움")
	await _drop(t)
	# 패드 △/Y: 확인 중 결정은 확인만 거둔다, 마지막 칸을 지우면 칸 고르기가 닫히고 '이어하기'가 사라진다
	_slot_file(3, "2026-10-22T10:00:00")
	t = await _title()
	t.activate_item("Continue")
	await _frames(2)
	sp = t.slot_picker()
	await _pad_y()
	var armed_y := sp.delete_armed()
	await _act("jump")
	_check(armed_y == 2 and sp.delete_armed() == -1 and not t._started and SaveGame.has_save_in(3), "패드 Y → 지우기 확인, 그때 결정을 누르면 확인만 거둠 (불러오지 않음)")
	await _pad_y()
	await _wait(0.5)
	await _pad_y()
	await _frames(3)
	_check(not SaveGame.any_save() and not sp.is_open() and not t.has_item("Continue"), "패드 Y 두 번으로 마지막 칸을 지우면 칸 고르기가 닫히고 '이어하기'가 사라진다")
	await _drop(t)
	# 키·버튼 바꾸기: 점프(결정)를 패드 Y 에, 회피(돌아가기)를 키보드 X 에 달면 그 버튼은 칸 지우기가 아니라 결정·돌아가기
	_slot_file(3, "2026-10-22T10:00:00", {"flags": {"slot3_flag": true}})
	var ey := InputEventJoypadButton.new()
	ey.button_index = JOY_BUTTON_Y
	InputMap.action_add_event("jump", ey)
	var ex := InputEventKey.new()
	ex.physical_keycode = KEY_X
	InputMap.action_add_event("dodge", ex)
	t = await _title()
	t.activate_item("Continue")
	await _frames(2)
	sp = t.slot_picker()
	await _key(KEY_X)
	var x_closed := not sp.is_open() and sp.delete_armed() == -1 and SaveGame.has_save_in(3)
	t.activate_item("Continue")
	await _frames(2)
	Progress.reset()
	await _pad_y()
	_check(x_closed and sp.delete_armed() == -1 and t._started and SaveGame.slot == 3 and SaveGame.has_save_in(3) and Progress.has("slot3_flag"),
		"회피를 X 키로 바꾸면 X 는 돌아가기, 점프를 패드 Y 로 바꾸면 Y 는 결정 (칸 3 불러옴, 지우지 않음)")
	InputMap.action_erase_event("jump", ey)
	InputMap.action_erase_event("dodge", ex)
	await _drop(t)
	DirAccess.remove_absolute(SaveGame.path_of(3))
	# 터치: 카드 누르기 = 불러오기, 길게 누르기 = 지우기, 바깥 누르기 = 돌아가기, 마우스 오른쪽 = 지우기
	_slot_file(1, "2026-10-20T10:00:00", {"flags": {"slot1_flag": true}})
	_slot_file(3, "2026-10-22T10:00:00", {"flags": {"slot3_flag": true}})
	t = await _title()
	t.activate_item("Continue")
	await _frames(2)
	sp = t.slot_picker()
	await _touch(sp.card_rect(0).get_center(), 0.8)
	var armed_t := sp.delete_armed()
	_check(armed_t == 0 and not t._started and SaveGame.has_save_in(1), "터치로 칸 1 을 길게 누르면 지우기 확인 (불러오지 않음)")
	await _touch(sp.card_rect(0).get_center(), 0.8)
	_check(not SaveGame.has_save_in(1) and SaveGame.has_save_in(3) and sp.is_open(), "한 번 더 길게 누르면 칸 1 지움 (칸 3 그대로)")
	await _touch(Vector2(sp.card_rect(0).position.x, 12.0))
	_check(not sp.is_open() and t.has_item("Continue"), "카드 바깥을 누르면 돌아가기 (칸 고르기 닫힘)")
	t.activate_item("Continue")
	await _frames(2)
	await _right_click(sp.card_rect(2).get_center())
	var armed_m := sp.delete_armed()
	await _act("dodge")
	_check(armed_m == 2 and sp.delete_armed() == -1 and sp.is_open() and SaveGame.has_save_in(3), "마우스 오른쪽 → 지우기 확인, 회피 → 확인만 거둠")
	Progress.reset()
	await _touch(sp.card_rect(2).get_center())
	_check(t._started and SaveGame.slot == 3 and Progress.has("slot3_flag"), "터치로 칸 3 을 누르면 한 번에 불러온다 (흉내 낸 마우스로 두 번 처리되지 않음)")
	await _drop(t)
	# 클리어 기록은 칸이 없어도: 메타만으로 보스 러시·음악 감상
	_clear_all()
	Progress.reset()
	MetaSave.mark_ending("return")
	t = await _title()
	_check(t.has_item("BossRush") and t.has_item("MusicRoom") and not t.has_item("Continue"), "저장 칸이 하나도 없어도 메타에 클리어가 있으면 '보스 러시'·'음악 감상'")
	await _drop(t)
	_clear_all()
	Progress.reset()


# ---------- 9) 일시정지 메뉴 ----------
func _probe_pause() -> void:
	_clear_all()
	Progress.reset()
	SaveGame.set_slot(2)
	var pm := PauseMenu.new()
	add_child(pm)
	pm.open()
	var row := pm.row_of("difficulty")
	var seq := []
	for d in [1, 1, 1, -1, -1, -1, -1]:
		pm.adjust_row("difficulty", d)
		seq.append(Progress.difficulty)
	_check(row == 1 and seq == ["hard", "nightmare", "nightmare", "hard", "normal", "easy", "easy"], "일시정지 '난이도' 줄(둘째): 좌우로 %s" % [seq])
	pm._index = row
	pm._activate()
	var wrap := Progress.difficulty
	Progress.difficulty = "nightmare"
	pm._activate()
	_check(wrap == "normal" and Progress.difficulty == "easy", "결정은 한 단계씩 돌아간다 (Easy → %s, Nightmare → %s)" % [wrap, Progress.difficulty])
	_check(pm._value_text("difficulty").contains("Easy") and pm._value_text("save").begins_with("칸 2") and pm._value_text("load") == SlotPicker.text("pause_load_none", {"n": 2}),
		"값 글자: 난이도 '%s', 저장 '%s', 불러오기 '%s'" % [pm._value_text("difficulty"), pm._value_text("save"), pm._value_text("load")])
	# 지금 저장하기는 지금 칸에만
	Progress.last_grass = {"id": "canopy_start", "scene": FIRST, "name": "수관 · 시작의 가지"}
	pm._index = pm.row_of("save")
	pm._activate()
	_check(SaveGame.has_save_in(2) and not SaveGame.has_save_in(1) and not SaveGame.has_save_in(3) and str(_read(SaveGame.path_of(2)).get("difficulty", "")) == "easy"
		and pm._value_text("load").begins_with("칸 2 · 저장: "),
		"'지금 저장하기' → 칸 2 에만 (난이도 easy 도 저장), 불러오기 값 '%s'" % pm._value_text("load"))
	# 줄이 많아도 화면 안 (세 화면 비율)
	var fits := []
	var keep := pm._panel.size
	for sz in [Vector2(1920, 1080), Vector2(2338, 1080), Vector2(1920, 1440)]:
		pm._panel.size = sz
		var last := pm._row_rect(pm._items.size() - 1)
		var first := pm._row_rect(0)
		fits.append(last.end.y + 34.0 + 12.0 <= sz.y and first.position.y > sz.y * 0.1)
	pm._panel.size = keep
	_check(fits == [true, true, true], "일시정지 %d줄이 세 화면 비율 모두 안에 (안내 글자까지) %s" % [pm._items.size(), fits])
	pm.close()
	# 타이틀 설정·보스 러시에는 난이도 줄이 없다
	pm.open(true)
	var r_title := pm.row_of("difficulty")
	pm.close()
	BossRush.active = true
	pm.open()
	var r_rush := pm.row_of("difficulty")
	pm.close()
	BossRush.active = false
	_check(r_title < 0 and r_rush < 0, "타이틀 설정·보스 러시 일시정지에는 '난이도' 줄이 없다")
	pm.queue_free()
	get_tree().paused = false
	await _frames(2)
	_clear_all()
	Progress.reset()


# ---------- 그림 확인 (화면 있게) ----------
func _take_shots(args: PackedStringArray) -> void:
	DirAccess.make_dir_recursive_absolute(_out)
	var dev := "kb"
	for a in args:
		if a.begins_with("--device="):
			dev = a.trim_prefix("--device=")
	var kinds := {"kb": InputDevice.Kind.KEYBOARD, "ds": InputDevice.Kind.DUALSENSE, "xb": InputDevice.Kind.XBOX, "touch": InputDevice.Kind.TOUCH}
	_clear_all()
	Progress.reset()
	_slot_file(1, "2026-10-24T13:05:00", {"grass": "canopy_02_top", "grasses": {"canopy_02_top": {"scene": "res://scenes/rooms/canopy_02.tscn", "name": "수관 · 바람의 틈 위"}},
		"flags": {"cleared": true, "last_ending_return": true}, "difficulty": "normal"})
	_slot_file(3, "2026-10-22T21:40:00", {"grass": "mine_owen", "grasses": {"mine_owen": {"scene": "res://scenes/rooms/mine_02.tscn", "name": "채굴장 · 오웬의 등불"}}, "difficulty": "nightmare"})
	var t := await _title()
	InputDevice.current = kinds.get(dev, InputDevice.Kind.KEYBOARD)
	t._refresh_hint()
	await _wait(3.2)
	await _snap("slots_title_%s" % dev)
	t.activate_item("Continue")
	await _wait(0.3)
	await _snap("slots_load_%s" % dev)
	var sp := t.slot_picker()
	sp.delete_request(0)
	await _wait(0.2)
	await _snap("slots_load_delete_%s" % dev)
	sp.cancel()
	sp.close()
	t.activate_item("Start")
	await _wait(0.2)
	await _snap("slots_new_%s" % dev)
	sp.activate(0)
	await _wait(0.2)
	await _snap("slots_new_confirm_%s" % dev)
	sp.activate(0)
	await _wait(0.3)
	await _snap("slots_difficulty_%s" % dev)
	t.difficulty_picker().cancel()
	sp.close()
	await _drop(t)
	# 일시정지 메뉴 (난이도 줄 고름)
	SaveGame.set_slot(1)
	Progress.difficulty = "hard"
	Progress.last_grass = {"id": "canopy_02_top", "scene": "res://scenes/rooms/canopy_02.tscn", "name": "수관 · 바람의 틈 위"}
	var bg := ColorRect.new()
	bg.color = Color(0.2, 0.25, 0.2)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var pm := PauseMenu.new()
	add_child(pm)
	pm.open()
	pm._index = pm.row_of("difficulty")
	await _wait(0.3)
	await _snap("slots_pause_%s" % dev)
	pm.close()
	pm.queue_free()
	bg.queue_free()
	get_tree().paused = false
	_clear_all()


func _snap(name: String) -> void:
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(_out.path_join(name + ".png"))
		print("[probe]   찍음: ", _out.path_join(name + ".png"))

extends Node
## 엔딩 시험 (ENDINGS.md). 화면 없이 돈다. 엔딩 장면을 빠르게(time_scale) 끝까지 돌려 본다.
## 실행: godot --headless --path . res://tools/probe_endings.tscn
##       그림 확인용(화면 있게): godot --path . res://tools/probe_endings.tscn -- --shots --out=/절대/경로   (몇 장면을 찍는다)
##  1) 데이터: 세 엔딩의 장면 순서가 ENDINGS.md 와 같다, 허밍 시작 장면(희생 4 · 되돌림 6 · 제3의 길 3), 그림 파일(엔딩 그림 14장·타이틀 3장)이
##     있고 크기 1672×941 (엔딩 11장·타이틀 3장), ending_third_way 는 어디에도 없다, 회상·과거 그림이 진짜 그림(임시가 아님).
##  2) 주제 문장 "오직 생명만이…" 은 대사 파일 전체에서 단 한 번 (되돌림의 끝 장면 5, 늙은 등불지기).
##  3) selenia_humming 을 부르는 코드는 엔딩·타이틀(클리어 후)·음악 표뿐 (첫 소리 보존).
##  4) 세 엔딩을 끝까지: 장면 순서·그림, 허밍이 정해진 장면에서 처음 시작해 크레딧이 끝날 때까지 다시 시작하지 않고 끊기지 않음(반복 없음),
##     허밍 전에는 음악 없음, 주제 문장 횟수, 크레딧 그림, 끝 화면의 타이틀 그림, 깃발·저장(cleared·ending·last_ending), '이어서 탐험하기' → 마지막 달빛풀.
##  5) 타이틀: 마지막으로 본 엔딩의 그림·부제·곡(selenia_humming 반복), 앱을 새로 켠 것처럼(진행 비움) 저장 파일만으로도 같음.
##  6) 엔딩 뒤 세계: 마지막 달빛풀에 도착(쉬는 자세), 마을 빛(되돌림 · 제3의 길), 티아·등불지기·오웬의 엔딩 뒤 대사, 재회가 남았으면 재회가 먼저.
##  7) 건너뛰기를 연타해도 허밍은 정해진 장면에서 시작, 경전 고쳐 쓰기 글자 단계, 경전 구절 메아리(조각을 읽었을 때만).
##  8) 진짜 장면 바꾸기로 끝까지: 정원의 끝(abyss_boss)의 '마력의 관' 선택지 → 엔딩 장면 → 끝 화면 '이어서 탐험하기' → 달빛 정원에 쉬는 자세로 도착(쉼터 곡).
## 마지막 줄 "[probe] 끝: 실패 N".

const THEME := "오직 생명만이"
const EXPECT_NAMES := {
	"sacrifice": ["등불을 내려놓다", "뿌리에 손을 얹다", "나무가 되다", "세계수의 목소리", "빛이 위로 오른다", "마을", "달빛 정원", "마지막 한 컷"],
	"return": ["관을 끊다", "마력이 돌아가다", "등불이 꺼지다", "저주가 풀리다", "어둠 속에서", "달빛풀이 피어나다", "돌아온 셀레니아", "마지막 한 컷"],
	"third": ["등불을 내려다보다", "다섯 영혼이 함께하다", "펌프가 거꾸로 돌다", "세계수의 목소리", "작은 등불의 마을", "천천히 돌아오는 초록", "경전을 고쳐 쓰다", "달빛풀 아래", "마지막 한 컷"],
}
const EXPECT_HUM := {"sacrifice": 4, "return": 6, "third": 3}
const EXPECT_IMAGES := {
	"sacrifice": ["ending_sacrifice_1", "ending_sacrifice_2", "ending_sacrifice_3"],
	"return": ["ending_return_1", "ending_return_2", "ending_return_3"],
	"third": ["ending_true_1", "ending_true_2", "ending_true_3", "ending_true_4", "ending_true_5"],
}
const TITLE_IMAGES := {"sacrifice": "res://art/characters/title_after_sacrifice.png", "return": "res://art/characters/title_after_return.png", "third": "res://art/characters/title_after_true.png"}
const GARDEN := "res://scenes/rooms/moon_garden.tscn"
const SPEED := 30.0

var _fail := 0
var _had_save := false
var _save_backup := ""
var _shots := false
var _out := ""


func _ready() -> void:
	print("[probe] 시작: 엔딩")
	var args := OS.get_cmdline_user_args()
	_shots = "--shots" in args
	for a in args:
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	_had_save = SaveGame.has_save()
	_save_backup = FileAccess.get_file_as_string(SaveGame.PATH) if _had_save else ""
	Game._busy = true   # 장면 전환은 막는다 (choose 가 정한 다음 장면·등장 자리까지만 본다)
	if _shots:
		await _take_shots()
	else:
		await _run()
	_restore_save()
	Game._busy = false
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
		f.store_string(_save_backup)
		f.close()
	elif SaveGame.has_save():
		DirAccess.remove_absolute(SaveGame.PATH)


func _run() -> void:
	Progress.reset()
	_probe_data()
	_probe_theme_once()
	_probe_humming_refs()
	for w in ["sacrifice", "return", "third"]:
		await _probe_ending(w)
	await _probe_sequence()
	await _probe_skip_spam()
	await _probe_post_world()
	await _probe_full_flow()
	Music.stop(0.0)
	Progress.reset()


# ---------- 1) 데이터 ----------
func _probe_data() -> void:
	for w in ["sacrifice", "return", "third"]:
		var e := EndingScene.ending_data(w)
		var names: Array = []
		var images := {}
		for sc in e.get("scenes", []):
			names.append(str(sc.get("name", "")))
			images[str(sc.get("image", "")).get_file().get_basename()] = true
			for b in sc.get("beats", []):
				if b.has("image"):
					images[str(b["image"]).get_file().get_basename()] = true
		_check(names == EXPECT_NAMES[w], "%s: 장면 %d개, 순서가 ENDINGS.md 와 같다 %s" % [w, names.size(), names])
		_check(int(e.get("humming_scene", 0)) == EXPECT_HUM[w], "%s: 허밍 시작 장면 %d (기대 %d)" % [w, int(e.get("humming_scene", 0)), EXPECT_HUM[w]])
		var missing: Array = []
		for img in EXPECT_IMAGES[w]:
			if not images.has(img):
				missing.append(img)
		_check(missing.is_empty(), "%s: 엔딩 그림 %d장 모두 장면에 쓰임 (빠진 것 %s)" % [w, EXPECT_IMAGES[w].size(), missing])
		_check(str(e.get("title_image", "")) == TITLE_IMAGES[w], "%s: 클리어 후 타이틀 그림 %s" % [w, str(e.get("title_image", "")).get_file()])
		# 쓰는 그림 파일이 모두 있다
		var bad: Array = []
		for sc in e.get("scenes", []):
			for p in _paths_in(sc):
				if not ResourceLoader.exists(p):
					bad.append(p)
		for p in e.get("credits_images", []):
			if not ResourceLoader.exists(str(p)):
				bad.append(p)
		_check(bad.is_empty(), "%s: 장면·크레딧이 부르는 그림이 모두 있다 (없는 것 %s)" % [w, bad])
	# 그림 크기
	var sizes_ok := true
	var all_imgs: Array = []
	for w in EXPECT_IMAGES:
		for n in EXPECT_IMAGES[w]:
			all_imgs.append("res://art/memories/%s.png" % n)
	all_imgs.append_array(TITLE_IMAGES.values())
	for p in all_imgs:
		var t: Texture2D = load(p)
		if t == null or t.get_size() != Vector2(1672, 941):
			sizes_ok = false
			print("[probe]   크기 다름: ", p, " ", t.get_size() if t else "없음")
	_check(sizes_ok and all_imgs.size() == 14, "엔딩 그림 11장 + 타이틀 3장 = 14장 모두 1672×941")
	# ending_third_way 는 없다 (진엔딩 그림 5장으로 바뀜)
	var third_way_refs := _grep(["res://data", "res://scripts", "res://scenes"], "ending_third_way")
	_check(not FileAccess.file_exists("res://art/memories/ending_third_way.png") and third_way_refs.is_empty(), "ending_third_way.png 는 지워졌고 부르는 곳도 없다 %s" % [third_way_refs])
	# 회상·과거 그림: 진짜 그림 (임시 그림은 작은 파일이었다)
	var real := true
	for p in ["res://art/memories/memory_queen_1.png", "res://art/memories/memory_queen_2.png", "res://art/memories/memory_queen_3.png",
			"res://art/memories/memory_pump_1.png", "res://art/memories/memory_pump_2.png", "res://art/memories/memory_pump_3.png",
			"res://art/bosses/boss_sap_queen_past.png", "res://art/bosses/boss_iron_pump_past.png"]:
		var f := FileAccess.open(p, FileAccess.READ)
		var sz := f.get_length() if f else 0
		var t: Texture2D = load(p)
		if sz < 1000000 or t == null or t.get_size() != Vector2(1536, 1024):
			real = false
			print("[probe]   임시 그림 같음: ", p, " ", sz)
	_check(real, "여왕·펌프 회상 6장 + 여왕·펌프 과거 그림 2장이 진짜 그림 (1536×1024, 1MB 넘음)")


func _paths_in(sc: Dictionary) -> Array:
	var out: Array = []
	if sc.has("image"):
		out.append(str(sc["image"]))
	for l in sc.get("layers", []):
		out.append(str(l.get("tex", "")))
	for b in sc.get("beats", []):
		if b.has("image"):
			out.append(str(b["image"]))
		for l in b.get("layers", []):
			out.append(str(l.get("tex", "")))
		if b.has("swap"):
			out.append(str(b["swap"].get("tex", "")))
	return out


## 폴더들 아래 .gd / .tscn / .json 에서 글자를 찾는다 → ["파일", ...]
func _grep(dirs: Array, needle: String) -> Array:
	var hits: Array = []
	var stack: Array = dirs.duplicate()
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		for sub in da.get_directories():
			stack.append(d.path_join(sub))
		for f in da.get_files():
			if f.ends_with(".gd") or f.ends_with(".tscn") or f.ends_with(".json"):
				var p := d.path_join(f)
				if FileAccess.get_file_as_string(p).contains(needle):
					hits.append(p)
	return hits


# ---------- 2) 주제 문장 ----------
func _probe_theme_once() -> void:
	var count := 0
	var where: Array = []
	var da := DirAccess.open("res://data/dialogue")
	for f in da.get_files():
		if f.ends_with(".json"):
			var s := FileAccess.get_file_as_string("res://data/dialogue/" + f)
			var n := s.count(THEME)
			if n > 0:
				count += n
				where.append("%s×%d" % [f, n])
	var e := EndingScene.ending_data("return")
	var sc5: Dictionary = e.get("scenes", [])[4] if e.get("scenes", []).size() > 4 else {}
	var in_scene5 := false
	for b in sc5.get("beats", []):
		if str(b.get("text", "")).contains(THEME) and b.get("theme", false) and str(b.get("speaker", "")).contains("등불지기"):
			in_scene5 = true
	_check(count == 1 and in_scene5, "주제 문장은 대사 파일 전체에서 %d번 (%s), 되돌림의 끝 장면 5 등불지기의 말 %s" % [count, where, in_scene5])
	# 다른 코드에도 없다
	var code := _grep(["res://scripts", "res://scenes"], THEME)
	_check(code.is_empty(), "코드·장면 파일에는 주제 문장이 없다 %s" % [code])


# ---------- 3) 허밍은 엔딩·클리어 후 타이틀에만 ----------
func _probe_humming_refs() -> void:
	var allowed := ["res://scripts/autoload/music.gd", "res://scripts/ui/ending_scene.gd"]
	var bad: Array = []
	for needle in ["selenia_humming", "ENDING_TRACK", "title_track"]:
		for p in _grep(["res://scripts", "res://scenes", "res://data"], needle):
			if not (p in allowed) and p != "res://scripts/ui/title_screen.gd" and not p.begins_with("res://data/dialogue/endings"):
				bad.append("%s(%s)" % [p, needle])
	_check(bad.is_empty(), "selenia_humming 을 트는 곳은 엔딩·타이틀(클리어 후)·음악 표뿐 (다른 곳 %s)" % [bad])
	_check(Music.title_track(false) == "title" and Music.title_track(true) == "selenia_humming", "타이틀 곡: 클리어 전 title / 뒤 selenia_humming")


# ---------- 4) 엔딩 끝까지 ----------
func _setup_progress(w: String) -> void:
	Progress.reset()
	for a in ["double_jump", "wind", "light", "lantern"]:
		Progress.gain_ability(a)
	for f in ["has_tia_lantern", "named_selenia", "boss_bird_defeated", "boss_knight_defeated", "boss_root_defeated", "after_boss_root_defeated"]:
		Progress.set_flag(f)
	if w == "third":
		for a in ["sap_walk", "wall_break"]:
			Progress.gain_ability(a)
		Progress.set_flag("boss_pump_defeated")
		Progress.set_flag("read_scripture_4")
	Progress.grasses["moon_garden"] = {"scene": GARDEN, "name": "달빛 정원"}
	Progress.last_grass = {"id": "moon_garden", "scene": GARDEN, "name": "달빛 정원"}
	Progress.ending = w


## 엔딩을 빠르게 끝까지 돌리며 음악을 매 프레임 지켜본다. 돌려준 사전: {scene, samples...}
func _play_fast(w: String, speed := SPEED, spam := false) -> Dictionary:
	var e: EndingScene = load("res://scenes/ui/ending_scene.tscn").instantiate()
	e.time_scale = speed
	add_child(e)
	var out := {"node": e, "before_music": [], "restart": false, "stopped": false, "loops": false, "max_pos": -1.0, "stage_max": -1, "positions": 0}
	var last_pos := -1.0
	var t0 := Time.get_ticks_msec()
	while not e.end_menu_ready() and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
		if spam and e.phase == "scenes" and Engine.get_process_frames() % 2 == 0:
			e._beat_real = 9.0
			e.skip()
		out["stage_max"] = maxi(out["stage_max"], e.scripture_stage())
		var started := e.humming_scene_index >= 0
		var cur := Music.current()
		if not started:
			if cur != "":
				(out["before_music"] as Array).append(cur)
			continue
		if cur != Music.ENDING_TRACK:
			out["stopped"] = true
			continue
		if Music.current_loops():
			out["loops"] = true
		var pos := Music.playback_time(Music.ENDING_TRACK)
		if pos >= 0.0:
			out["positions"] = int(out["positions"]) + 1
			if last_pos >= 0.0 and pos < last_pos - 0.25:
				out["restart"] = true
				print("[probe]   허밍 위치가 뒤로: %.2f → %.2f" % [last_pos, pos])
			last_pos = maxf(last_pos, pos)
	out["max_pos"] = last_pos
	out["timeout"] = not e.end_menu_ready()
	return out


func _probe_ending(w: String) -> void:
	_setup_progress(w)
	if SaveGame.has_save():
		DirAccess.remove_absolute(SaveGame.PATH)
	var r := await _play_fast(w)
	var e: EndingScene = r["node"]
	_check(not r["timeout"], "%s: 끝 화면의 메뉴까지 갔다 (단계 %s)" % [w, e.phase])
	# 장면 순서
	var scene_names: Array = []
	var shown_images := {}
	var theme_count := 0
	var hum_event := -1
	var credit_imgs: Array = []
	var end_ev := {}
	var credits_ev := {}
	var echo := ""
	for ev in e.events:
		match str(ev["kind"]):
			"scene":
				scene_names.append(str(ev["name"]))
				shown_images[str(ev["image"]).get_file().get_basename()] = true
			"beat":
				if str(ev["text"]).contains(THEME):
					theme_count += 1
				if str(ev["image"]) != "":
					shown_images[str(ev["image"]).get_file().get_basename()] = true
				if str(ev.get("echo", "")) != "":
					echo = str(ev["echo"])
			"music":
				hum_event = int(ev["index"])
			"credit_image":
				credit_imgs.append(str(ev["path"]))
			"end":
				end_ev = ev
			"credits":
				credits_ev = ev
	_check(scene_names == EXPECT_NAMES[w], "%s: 장면이 순서대로 %d개 지나감" % [w, scene_names.size()])
	var miss: Array = []
	for img in EXPECT_IMAGES[w]:
		if not shown_images.has(img):
			miss.append(img)
	_check(miss.is_empty(), "%s: 엔딩 그림이 모두 화면에 나옴 (빠진 것 %s)" % [w, miss])
	_check(hum_event == EXPECT_HUM[w] - 1 and e.humming_scene_index == EXPECT_HUM[w] - 1,
		"%s: 허밍이 장면 %d 에서 시작 (기록 %d)" % [w, EXPECT_HUM[w], hum_event + 1])
	_check((r["before_music"] as Array).is_empty(), "%s: 허밍 전 장면에는 음악이 없다 (들린 곡 %s)" % [w, r["before_music"]])
	_check(not r["restart"] and not r["stopped"] and not r["loops"] and int(r["positions"]) > 10,
		"%s: 허밍이 크레딧 끝까지 다시 시작하지 않고(%s) 끊기지 않고(%s) 반복 설정 없이(%s) 흐름 (재 본 횟수 %d, 마지막 %.1f초)" % [w, not r["restart"], not r["stopped"], not r["loops"], r["positions"], r["max_pos"]])
	_check(str(credits_ev.get("music", "")) == Music.ENDING_TRACK and str(end_ev.get("music", "")) == Music.ENDING_TRACK and Music.current() == Music.ENDING_TRACK,
		"%s: 크레딧 시작·끝 화면에서도 허밍 (%s / %s)" % [w, credits_ev.get("music", ""), end_ev.get("music", "")])
	var cl := float(credits_ev.get("length", 0.0))
	_check(cl >= EndingScene.CREDITS_MIN and cl <= EndingScene.CREDITS_MAX, "%s: 크레딧 길이 %.0f초 (허밍 남은 길이에 맞춤, %d~%d)" % [w, cl, EndingScene.CREDITS_MIN, EndingScene.CREDITS_MAX])
	_check(theme_count == (1 if w == "return" else 0), "%s: 주제 문장 %d번" % [w, theme_count])
	var want_credits: Array = EndingScene.ending_data(w).get("credits_images", [])
	_check(credit_imgs == want_credits, "%s: 크레딧 그림 %d장 차례로" % [w, credit_imgs.size()])
	var front := e.front_texture()
	_check(str(end_ev.get("title_image", "")) == TITLE_IMAGES[w] and front != null and front.resource_path == TITLE_IMAGES[w],
		"%s: 끝 화면 그림 = 클리어 후 타이틀 그림 %s" % [w, front.resource_path.get_file() if front else "없음"])
	if w == "third":
		_check(int(r["stage_max"]) == 2, "third: 경전 글자가 '번영'에 줄 → '생명' 다시 적기까지 (단계 %d)" % r["stage_max"])
		_check(echo == "— 경전의 잃어버린 구절", "third: 경전 조각을 읽었으면 세계수의 둘째 말 아래 메아리 '%s'" % echo)
	# 깃발·저장
	var others_off := true
	for n in EndingScene.ENDINGS:
		if n != w and Progress.has("last_ending_" + n):
			others_off = false
	_check(Progress.has("cleared") and Progress.has("ending_" + w) and Progress.has("last_ending_" + w) and others_off and (w != "third" or Progress.has("cleared_third")),
		"%s: 깃발 cleared·ending_%s·last_ending_%s (다른 last_ending 없음 %s)" % [w, w, w, others_off])
	var saved := {}
	if SaveGame.has_save():
		saved = JSON.parse_string(FileAccess.get_file_as_string(SaveGame.PATH))
	var sf: Dictionary = saved.get("flags", {})
	_check(str(saved.get("ending", "")) == w and bool(sf.get("cleared", false)) and bool(sf.get("last_ending_" + w, false)) and str(saved.get("grass", "")) == "moon_garden",
		"%s: 저장 파일 — ending '%s', cleared %s, last_ending_%s %s, 이어질 달빛풀 '%s'" % [w, saved.get("ending", ""), sf.get("cleared", false), w, sf.get("last_ending_" + w, false), saved.get("grass", "")])
	# 이어서 탐험하기
	e.choose("explore")
	var ch: Dictionary = e.events[e.events.size() - 1]
	_check(str(ch.get("what", "")) == "explore" and str(ch.get("scene", "")) == GARDEN and Progress.next_spawn == "Grass:moon_garden",
		"%s: '이어서 탐험하기' → %s, 등장 자리 %s" % [w, str(ch.get("scene", "")).get_file(), Progress.next_spawn])
	e.queue_free()
	await _frames(3)
	Music.stop(0.0)
	await _frames(2)
	# 타이틀: 진행이 남은 채 / 앱을 새로 켠 것처럼 (진행 비움 → 저장 파일만)
	await _probe_title(w, "진행 있음")
	var keep_flags := Progress.flags.duplicate()
	Progress.reset()
	await _probe_title(w, "새로 켬")
	Progress.flags = keep_flags
	Progress.next_spawn = ""


func _probe_title(w: String, label: String) -> void:
	var st: Dictionary = load("res://scripts/ui/title_screen.gd").cleared_state()
	var title: Node = load("res://scenes/ui/title_screen.tscn").instantiate()
	add_child(title)
	await _frames(4)
	var tex: Texture2D = title.get_node("Art").texture
	var sub: String = title.get_node("Layout/Subtitle").text
	var want_sub := str(EndingScene.ending_data(w).get("title_subtitle", ""))
	_check(st["cleared"] and st["ending"] == w and tex != null and tex.resource_path == TITLE_IMAGES[w] and sub == want_sub
		and Music.current() == "selenia_humming" and Music.current_loops(),
		"%s 뒤 타이틀(%s): 마지막 엔딩 '%s', 그림 %s, 부제 '%s', 곡 %s 반복 %s" % [w, label, st["ending"], tex.resource_path.get_file() if tex else "없음", sub, Music.current(), Music.current_loops()])
	title.queue_free()
	await _frames(2)
	Music.stop(0.0)


# ---------- 마지막으로 본 엔딩이 바뀌면 ----------
func _probe_sequence() -> void:
	_setup_progress("sacrifice")
	EndingScene.mark_seen("sacrifice")
	EndingScene.mark_seen("return")
	var only_one := Progress.has("last_ending_return") and not Progress.has("last_ending_sacrifice") and not Progress.has("last_ending_third")
	_check(only_one and Progress.has("ending_sacrifice") and Progress.has("ending_return") and PostEnding.last_ending() == "return",
		"희생 → 되돌림을 차례로 보면 마지막 엔딩은 되돌림 하나 (본 엔딩 기록은 둘 다 남음)")
	SaveGame.save("moon_garden", GARDEN)
	Progress.reset()
	var st: Dictionary = load("res://scripts/ui/title_screen.gd").cleared_state()
	var look: Dictionary = load("res://scripts/ui/title_screen.gd").title_look(st)
	_check(st["ending"] == "return" and look["image"] == TITLE_IMAGES["return"], "저장 파일로 본 타이틀: 마지막 엔딩 %s → %s" % [st["ending"], str(look["image"]).get_file()])
	# 클리어 전: 기본 그림·title 곡
	if SaveGame.has_save():
		DirAccess.remove_absolute(SaveGame.PATH)
	Progress.reset()
	var st0: Dictionary = load("res://scripts/ui/title_screen.gd").cleared_state()
	var look0: Dictionary = load("res://scripts/ui/title_screen.gd").title_look(st0)
	_check(not st0["cleared"] and look0["image"] == "res://art/characters/title_selenia.png", "클리어 전 타이틀: title_selenia.png")
	# 옛 저장 (last_ending 깃발 없이 ending 값만)
	var f := FileAccess.open(SaveGame.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "flags": {"cleared": true, "ending_sacrifice": true}, "ending": "sacrifice", "grass": "moon_garden", "scene": GARDEN}))
	f.close()
	var st1: Dictionary = load("res://scripts/ui/title_screen.gd").cleared_state()
	_check(st1["ending"] == "sacrifice", "옛 저장 파일(마지막 엔딩 깃발 없음)도 저장된 엔딩 값으로 타이틀을 고른다 (%s)" % st1["ending"])
	DirAccess.remove_absolute(SaveGame.PATH)
	Progress.reset()


# ---------- 건너뛰기 연타 ----------
func _probe_skip_spam() -> void:
	for w in ["return", "third"]:
		_setup_progress(w)
		var r := await _play_fast(w, 6.0, true)
		var e: EndingScene = r["node"]
		var hum := -1
		for ev in e.events:
			if ev["kind"] == "music":
				hum = int(ev["index"])
		_check(hum == EXPECT_HUM[w] - 1 and not r["restart"] and not r["stopped"] and (r["before_music"] as Array).is_empty(),
			"%s: 건너뛰기를 연타해도 허밍은 장면 %d 에서 한 번 시작, 다시 시작·끊김 없음" % [w, hum + 1])
		e.queue_free()
		await _frames(2)
		Music.stop(0.0)
	if SaveGame.has_save():
		DirAccess.remove_absolute(SaveGame.PATH)


# ---------- 6) 엔딩 뒤 세계 ----------
func _probe_post_world() -> void:
	# 마지막 달빛풀 도착
	_setup_progress("return")
	EndingScene.mark_seen("return")
	Progress.next_spawn = "Grass:moon_garden"
	var garden: Node = load(GARDEN).instantiate()
	add_child(garden)
	await _frames(6)
	var player: Player = get_tree().get_first_node_in_group("player")
	var grass: Node2D = null
	for g in get_tree().get_nodes_in_group("moonlight_grass"):
		if g.grass_id == "moon_garden":
			grass = g
	var near := player != null and grass != null and player.global_position.distance_to(grass.global_position) < 140.0
	_check(near and Progress.next_spawn == "", "엔딩 뒤 '이어서 탐험하기' 도착: 달빛 정원의 달빛풀 곁 (%s), 소녀 상태 %s" % [near, player.state_name() if player else "-"])
	garden.queue_free()
	await _frames(3)
	# 마을의 빛 + 대사 (되돌림)
	Progress.set_flag("owen_rescued")
	Progress.set_flag("reunion_done")
	Progress.set_flag("lampkeeper_confessed")
	var v := await _village_state()
	_check(v["tint"] != null and (v["tint"] as Color).b > (v["tint"] as Color).r, "되돌림 뒤 마을: 푸른 밤빛 %s" % [v["tint"]])
	_check(str(v["tia"]).contains("별이 보여") and str(v["owen"]).contains("조금씩") and str(v["keeper"]).contains("달빛풀을 따라"),
		"되돌림 뒤 대사: 티아 '%s' / 오웬 '%s' / 등불지기 '%s'" % [v["tia"], v["owen"], v["keeper"]])
	# 희생: 마을은 그대로, 대사는 새 씨앗
	EndingScene.mark_seen("sacrifice")
	v = await _village_state()
	_check(v["tint"] == null and str(v["tia"]).contains("금빛 씨앗") and str(v["keeper"]).contains("또 하나의 씨앗"), "희생 뒤 마을: 빛 그대로(%s), 티아 '%s'" % [v["tint"], v["tia"]])
	# 제3의 길
	EndingScene.mark_seen("third")
	v = await _village_state()
	_check(v["tint"] != null and str(v["tia"]).contains("하나씩만") and str(v["owen"]).contains("거꾸로") and str(v["keeper"]).contains("생명"),
		"제3의 길 뒤 마을: 저녁빛 %s, 티아 '%s'" % [v["tint"], v["tia"]])
	# 재회가 남았으면 재회가 먼저 (엔딩 뒤에 오웬을 구해도)
	Progress.set_flag("reunion_done", false)
	var tia := _make_npc("tia")
	var first: Dictionary = tia.pick_talk()
	_check(str(first.get("when", "")) == "owen_rescued,!reunion_done", "엔딩 뒤에도 오웬과의 재회가 남았으면 재회가 먼저 (%s)" % first.get("when", ""))
	tia.queue_free()
	# 등불지기: 고백 전이면 고백이 먼저
	Progress.set_flag("lampkeeper_confessed", false)
	var keeper := _make_npc("lampkeeper")
	_check(str(keeper.pick_talk().get("when", "")).begins_with("boss_knight_defeated,!lampkeeper_confessed"), "엔딩 뒤에도 등불지기의 고백이 남았으면 고백이 먼저")
	keeper.queue_free()
	await _frames(2)
	Progress.reset()


func _make_npc(id: String) -> Npc:
	var n: Npc = load("res://scenes/npcs/npc.tscn").instantiate()
	n.npc_id = id
	add_child(n)
	return n


## 마을 방(village_02)의 엔딩 뒤 빛과, 티아·오웬·등불지기의 지금 대사 첫 줄
func _village_state() -> Dictionary:
	var room: Node = load("res://scenes/rooms/village_02.tscn").instantiate()
	add_child(room)
	await _frames(4)
	var cm: CanvasModulate = room.get_node_or_null("PostEndingTint")
	var out := {"tint": cm.color if cm else null}
	for id in ["tia", "owen", "lampkeeper"]:
		var n := _make_npc(id)
		var t: Dictionary = n.pick_talk()
		var lines: Array = t.get("lines", [])
		var first := ""
		if not lines.is_empty():
			first = str(lines[0]) if lines[0] is String else str(lines[0].get("text", ""))
			if lines.size() > 1:
				first += " / " + (str(lines[1]) if lines[1] is String else str(lines[1].get("text", "")))
		out["keeper" if id == "lampkeeper" else id] = first
		n.queue_free()
	room.queue_free()
	await _frames(3)
	return out


# ---------- 그림 확인용 스크린샷 (화면 있게) ----------
func _take_shots() -> void:
	var dir := _out if _out != "" else ProjectSettings.globalize_path("res://screenshots")
	DirAccess.make_dir_recursive_absolute(dir)
	# [엔딩, 장면 번호(0부터), 줄 번호, 기다림(초), 이름]
	var plan := [
		["sacrifice", 1, 1, 3.0, "sac_2_hand"], ["sacrifice", 3, 0, 3.5, "sac_4_voice"], ["sacrifice", 4, 1, 2.6, "sac_5_mine_ash"],
		["sacrifice", 5, 2, 3.5, "sac_6_village"], ["sacrifice", 7, 0, 5.0, "sac_8_seed"],
		["return", 2, 1, 4.0, "ret_3_sweep"], ["return", 2, 3, 4.0, "ret_3_lantern_off"], ["return", 4, 2, 3.0, "ret_5_theme"], ["return", 6, 1, 3.0, "ret_7_owen"],
		["third", 1, 5, 2.5, "true_2_souls"], ["third", 2, 0, 3.5, "true_3_spin"], ["third", 3, 1, 3.0, "true_4_voice"], ["third", 5, 1, 4.0, "true_6_green"], ["third", 6, 0, 6.0, "true_7_scripture"],
	]
	for w in ["sacrifice", "return", "third"]:
		_setup_progress(w)
		var e: EndingScene = load("res://scenes/ui/ending_scene.tscn").instantiate()
		add_child(e)
		await _frames(3)
		for p in plan:
			if p[0] != w:
				continue
			while e.phase == "scenes" and (e._scene_i < p[1] or (e._scene_i == p[1] and e._beat_i < p[2])):
				e.skip()
				await _frames(1)
			await get_tree().create_timer(p[3]).timeout
			var img := get_viewport().get_texture().get_image()
			img.save_png(dir.path_join("ending_%s.png" % p[4]))
			print("[probe] 찍음 ", dir.path_join("ending_%s.png" % p[4]))
		# 크레딧 한 장 + 끝 화면
		while e.phase == "scenes":
			e.skip()
			await _frames(1)
		await get_tree().create_timer(14.0).timeout
		get_viewport().get_texture().get_image().save_png(dir.path_join("ending_%s_credits.png" % w))
		e.skip()
		await get_tree().create_timer(6.0).timeout
		get_viewport().get_texture().get_image().save_png(dir.path_join("ending_%s_end.png" % w))
		print("[probe] 찍음 끝 화면 ", w)
		e.queue_free()
		await _frames(2)
		Music.stop(0.0)
		# 타이틀
		var title: Node = load("res://scenes/ui/title_screen.tscn").instantiate()
		add_child(title)
		await get_tree().create_timer(4.0).timeout
		get_viewport().get_texture().get_image().save_png(dir.path_join("title_after_%s.png" % w))
		title.queue_free()
		await _frames(2)
		Music.stop(0.0)
	# 되돌림 뒤 마을
	_setup_progress("return")
	EndingScene.mark_seen("return")
	var room: Node = load("res://scenes/rooms/village_02.tscn").instantiate()
	add_child(room)
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png(dir.path_join("post_return_village.png"))
	room.queue_free()
	await _frames(2)
	if SaveGame.has_save():
		DirAccess.remove_absolute(SaveGame.PATH)


# ---------- 8) 진짜 장면 바꾸기로: 선택지 → 엔딩 → 이어서 탐험 ----------
## 이 시험 노드가 장면 바꾸기에 지워지지 않게, 빈 노드를 '지금 장면'으로 세워 두고 그 자리를 Game.go_to 가 바꾸게 한다.
func _probe_full_flow() -> void:
	_setup_progress("return")
	if SaveGame.has_save():
		DirAccess.remove_absolute(SaveGame.PATH)
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	Game._busy = false
	get_tree().change_scene_to_file("res://scenes/rooms/abyss_boss.tscn")
	var room: Node = await _wait_scene("abyss_boss", 10.0)
	var choice: EndingChoice = room.get_node_or_null("Choices/Pipe") if room else null
	var player: Player = get_tree().get_first_node_in_group("player")
	_check(choice != null and room.get_node("Choices").visible and player != null, "정원의 끝: 선택지가 깨어 있다 (뿌리지기 정화 뒤)")
	if choice == null or player == null:
		return
	await _frames(30)
	Progress.ending = ""
	choice.interact(player)
	var ending: Node = await _wait_scene("ending_scene", 12.0)
	_check(ending is EndingScene and Progress.ending == "return", "'마력의 관을 끊는다' → 엔딩 장면 (되돌림, %s)" % Progress.ending)
	if not (ending is EndingScene):
		return
	var e: EndingScene = ending
	e.time_scale = SPEED
	var t0 := Time.get_ticks_msec()
	while not e.end_menu_ready() and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	_check(e.end_menu_ready() and Music.current() == Music.ENDING_TRACK, "엔딩 끝 화면까지, 허밍이 흐르는 중 (%s)" % Music.current())
	e.time_scale = 1.0
	e.choose("explore")
	var garden: Node = await _wait_scene("moon_garden", 12.0)
	await _frames(20)
	var p2: Player = get_tree().get_first_node_in_group("player")
	_check(garden != null and p2 != null and p2.state_name() == "쉬는 중" and Music.current() == Music.REST,
		"이어서 탐험하기 → 달빛 정원 도착: 소녀 %s, 곡 %s" % [p2.state_name() if p2 else "-", Music.current()])
	_check(SaveGame.has_save() and load("res://scripts/ui/title_screen.gd").cleared_state()["ending"] == "return", "엔딩이 세이브에 남음 (타이틀은 되돌림 그림)")
	# 시험 노드는 그대로 두고, 남은 방은 빈 노드로 바꿔 지운다
	var dummy2 := Node.new()
	get_tree().root.add_child(dummy2)
	var cur := get_tree().current_scene
	get_tree().current_scene = dummy2
	if cur and cur != self:
		cur.queue_free()
	await _frames(3)
	Game._busy = true
	if SaveGame.has_save():
		DirAccess.remove_absolute(SaveGame.PATH)


## 지금 장면의 파일 이름에 name 이 들어갈 때까지 기다린다 (없으면 null).
func _wait_scene(name: String, limit: float) -> Node:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < limit * 1000.0:
		await get_tree().process_frame
		var cs := get_tree().current_scene
		if cs and cs != self and cs.scene_file_path.contains(name) and cs.is_node_ready():
			return cs
	print("[probe]   장면을 기다리다 시간 초과: ", name, " (지금 ", get_tree().current_scene.scene_file_path if get_tree().current_scene else "없음", ")")
	return null

extends Node
## 음악·음량 시험 (2026-10-19 정식 곡 18곡 + 음악/효과음 음량 버스). 화면 없이 돈다.
## 실행: godot --headless --path . res://tools/probe_music.tscn
##  1) 곡 목록(Music.TRACKS) 18곡이 모두 있고 읽힌다: QOA 압축 · 48kHz 스테레오, 반복(곡 전체 앞으로) — selenia_humming 만 한 번만.
##     audio/music/ 에 목록 밖의 곡(옛 임시곡)이 남지 않았다.
##  2) 코드·방이 부르는 곡 이름(보스곡·중간 보스곡·Music.play("…"))이 모두 있다.
##  3) 방 41개 전부의 들판 곡 (잎새의 새 정화 전/후 수관), 달빛 정원·숨은 내리막.
##  4) 실제 방 이동: 같은 지역 안에서는 곡이 다시 시작하지 않고, 지역이 바뀌면 바뀐다 / 정화 뒤 수관은 되살아난 곡.
##  5) 달빛풀에서 쉬면 쉼터 곡 → 일어서면 들판 곡 / 회상 곡 붙잡기 → 정해진 시간 뒤 들판 곡.
##  6) 타이틀 곡(클리어 전 title / 뒤 selenia_humming 반복), 엔딩 곡(selenia_humming 한 번만), 뿌리지기 2페이즈 곡, 펌프 휘청임.
##  7) 버스: Music·SFX 버스가 Master 로 가고, 음악 플레이어는 Music, 효과음은 SFX. 'Master' 로 바로 보내는 플레이어가 없다.
##  8) 음량: 음악·효과음·전체 음량이 각자 자기 버스만 바꾼다 (0 = 끔), 일시정지·타이틀 설정 화면에서도. 옛 settings.json 도 읽힌다.
##  9) 수액의 여왕 박자 상수 (정식 곡에서 잰 값) 와 곡 길이.
## 마지막 줄 "[probe] 끝: 실패 N".

var _fail := 0


func _ready() -> void:
	print("[probe] 시작: 음악·음량")
	await _run()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _idle_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _run() -> void:
	Progress.reset()
	_probe_files()
	_probe_references()
	_probe_region_table()
	await _probe_room_flow()
	await _probe_rest_and_hold()
	await _probe_title_ending_boss()
	_probe_buses()
	await _probe_volume()
	_probe_queen()
	Music.stop(0.0)
	Progress.reset()


# ---------- 1) 곡 파일 ----------
func _probe_files() -> void:
	var bad := []
	for t in Music.TRACKS:
		var path: String = Music.DIR + t + ".wav"
		if not ResourceLoader.exists(path):
			bad.append(t + "(없음)")
			continue
		var st := load(path) as AudioStreamWAV
		if st == null:
			bad.append(t + "(못 읽음)")
			continue
		var want_loop := AudioStreamWAV.LOOP_DISABLED if t == Music.ENDING_TRACK else AudioStreamWAV.LOOP_FORWARD
		var frames := roundi(st.get_length() * st.mix_rate)
		if st.format != AudioStreamWAV.FORMAT_QOA or not st.stereo or st.mix_rate != 48000:
			bad.append("%s(형식 %d 스테레오 %s %dHz)" % [t, st.format, st.stereo, st.mix_rate])
		if st.loop_mode != want_loop:
			bad.append("%s(반복 %d)" % [t, st.loop_mode])
		elif want_loop == AudioStreamWAV.LOOP_FORWARD and (st.loop_begin != 0 or st.loop_end < frames - 2):
			bad.append("%s(반복 구간 %d~%d / %d)" % [t, st.loop_begin, st.loop_end, frames])
		if st.get_length() < 60.0:
			bad.append("%s(길이 %.1f초)" % [t, st.get_length()])
	_check(Music.TRACKS.size() == 18 and bad.is_empty(), "곡 %d개: 모두 있음·QOA·48kHz 스테레오·곡 전체 반복(selenia_humming 만 한 번) %s" % [Music.TRACKS.size(), bad])
	var extra := []
	for f in DirAccess.get_files_at(Music.DIR):
		if f.ends_with(".wav") and not (f.get_basename() in Music.TRACKS):
			extra.append(f)
	_check(extra.is_empty(), "audio/music/ 에 목록 밖의 곡이 없다 (옛 임시곡 theme_*·ambient_* 정리) %s" % [extra])


# ---------- 2) 부르는 곡 이름 ----------
func _probe_references() -> void:
	var names := {}   # 곡 → 어디서
	# 방의 보스곡·중간 보스곡 (씬 파일에 적힌 값과 스크립트 기본값)
	for f in DirAccess.get_files_at("res://scenes/rooms/"):
		if not f.ends_with(".tscn"):
			continue
		var props := _root_props("res://scenes/rooms/" + f)
		for k in ["boss_track", "boss_track_2", "boss_music"]:
			if props.has(k) and str(props[k]) != "":
				names[str(props[k])] = f
		var scr: Script = props.get("script")
		if scr:
			for k in ["boss_track", "boss_music"]:
				if not props.has(k):
					for p in scr.get_script_property_list():
						if p["name"] == k:
							var dv = scr.get_property_default_value(k)
							if dv != null and str(dv) != "":
								names[str(dv)] = f + "(기본값)"
	# 스크립트 안의 Music.play("이름") 글자
	var re := RegEx.create_from_string("Music\\.play\\(\"([a-z0-9_]+)\"")
	for path in _gd_files("res://scripts/"):
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			names[m.get_string(1)] = path.get_file()
	# Music 의 표
	for t in Music.REGION_TRACKS.values() + Music.ROOM_TRACKS.values() + [Music.TITLE, Music.ENDING_TRACK, Music.RECOLLECTION, Music.REST, Music.CANOPY_RESTORED]:
		names[t] = "Music"
	var missing := []
	for n in names:
		if not ResourceLoader.exists(Music.DIR + n + ".wav"):
			missing.append("%s(%s)" % [n, names[n]])
	var not_listed := []
	for n in names:
		if not (n in Music.TRACKS):
			not_listed.append(n)
	_check(missing.is_empty() and not_listed.is_empty(), "부르는 곡 %d개가 모두 있고 목록에 있다: %s %s" % [names.size(), missing, not_listed])
	var mini := {}
	for rid in ["canopy_hidden", "canopy_mini_1", "canopy_mini_2", "village_mini_1", "mine_mini_1", "abyss_mini_1"]:
		var props := _root_props("res://scenes/rooms/%s.tscn" % rid)
		mini[rid] = props.get("boss_music", "boss_bird(기본)")
	print("[probe]   중간 보스곡: %s" % [mini])
	_check(str(mini["abyss_mini_1"]) == "boss_rootkeeper_p1" and str(mini["village_mini_1"]) == "boss_knight" and str(mini["mine_mini_1"]) == "boss_knight",
		"중간 보스는 그 지역 보스곡 (심연 → boss_rootkeeper_p1, 마을·채굴장 → boss_knight, 수관 → boss_bird)")
	var abyss := _root_props("res://scenes/rooms/abyss_boss.tscn")
	_check(abyss.get("boss_track") == "boss_rootkeeper_p1" and abyss.get("boss_track_2") == "boss_rootkeeper_p2", "뿌리지기: 1페이즈 %s → 다시 일어서면 %s" % [abyss.get("boss_track"), abyss.get("boss_track_2")])
	var expect := {"canopy_boss": "boss_bird", "mine_boss": "boss_knight", "sap_lake_boss": "boss_sap_queen", "flooded_mine_boss": "boss_iron_pump"}
	var got := {}
	var ok := true
	for rid in expect:
		got[rid] = _root_props("res://scenes/rooms/%s.tscn" % rid).get("boss_track", "boss_bird(기본)")
		ok = ok and str(got[rid]).begins_with(expect[rid])
	_check(ok, "보스곡: %s" % [got])


## 씬 파일 맨 위 노드의 속성 (인스턴스를 만들지 않고 SceneState 로 읽는다)
func _root_props(path: String) -> Dictionary:
	var out := {}
	var ps := load(path) as PackedScene
	if ps == null:
		return out
	var st := ps.get_state()
	for i in st.get_node_property_count(0):
		out[str(st.get_node_property_name(0, i))] = st.get_node_property_value(0, i)
	return out


func _gd_files(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


# ---------- 3) 방 41개의 들판 곡 ----------
func _probe_region_table() -> void:
	var want := {"canopy": "field_canopy", "village": "field_village", "mine": "field_mine", "abyss": "field_abyss", "sap_lake": "field_sap_lake", "flooded_mine": "field_flooded_mine"}
	var bad := []
	var table := {}
	var n := 0
	for f in DirAccess.get_files_at("res://scenes/rooms/"):
		if not f.ends_with(".tscn"):
			continue
		var props := _root_props("res://scenes/rooms/" + f)
		var region := str(props.get("region", "canopy"))
		var rid := str(props.get("room_id", f.get_basename()))
		n += 1
		Progress.reset()
		var before := Music.region_track(region, rid)
		Progress.set_flag("boss_bird_defeated")
		var after := Music.region_track(region, rid)
		var w0: String = "field_moon_garden" if rid == "moon_garden" else want.get(region, "?")
		var w1: String = "field_canopy_restored" if region == "canopy" else w0
		if before != w0 or after != w1:
			bad.append("%s(%s: %s/%s)" % [rid, region, before, after])
		var key := "%s → %s" % [region, before if before == after else before + " / 정화 뒤 " + after]
		if rid == "moon_garden" or rid == "hidden_descent":
			key = "%s(%s) → %s" % [rid, region, before]
		table[key] = table.get(key, 0) + 1
	Progress.reset()
	for k in table:
		print("[probe]   %s : 방 %d개" % [k, table[k]])
	_check(n == 42 and bad.is_empty(), "방 %d개의 들판 곡 (수관은 새 정화 뒤 되살아난 곡, 달빛 정원 자기 곡, 숨은 내리막 = 수액의 호수) %s" % [n, bad])


# ---------- 4) 실제 방 이동 ----------
func _open_room(rid: String) -> Node:
	var room: Node = load("res://scenes/rooms/%s.tscn" % rid).instantiate()
	add_child(room)
	await _frames(4)
	return room


func _close_room(room: Node) -> void:
	room.queue_free()
	await _frames(2)


func _probe_room_flow() -> void:
	Progress.reset()
	Music.stop(0.0)
	var r1 := await _open_room("canopy_01")
	var t1 := Music.current()
	var p1 = Music._players[Music._active]
	await _wait(0.6)
	var pos1 := Music.playback_time(t1)
	await _close_room(r1)
	var r2 := await _open_room("canopy_02")
	var t2 := Music.current()
	var same_player: bool = Music._players[Music._active] == p1
	var pos2 := Music.playback_time(t2)
	_check(t1 == "field_canopy" and t2 == "field_canopy" and same_player and pos2 >= pos1, "수관 방 → 수관 방: 곡 %s → %s, 다시 시작하지 않음 (같은 플레이어 %s, 위치 %.2f → %.2f초)" % [t1, t2, same_player, pos1, pos2])
	await _close_room(r2)
	var r3 := await _open_room("village_01")
	var t3 := Music.current()
	_check(t3 == "field_village", "마을 방에 들어서면 마을 곡: %s" % t3)
	await _close_room(r3)
	Progress.set_flag("boss_bird_defeated")
	var r4 := await _open_room("canopy_03")
	var t4 := Music.current()
	_check(t4 == "field_canopy_restored", "잎새의 새를 정화한 뒤 수관: %s" % t4)
	await _close_room(r4)
	Progress.reset()
	var r5 := await _open_room("moon_garden")
	_check(Music.current() == "field_moon_garden", "달빛 정원: %s" % Music.current())
	await _close_room(r5)
	var r6 := await _open_room("abyss_02")
	_check(Music.current() == "field_abyss", "달빛 정원 → 심연 방: %s" % Music.current())
	await _close_room(r6)
	var r7 := await _open_room("hidden_descent")
	_check(Music.current() == "field_sap_lake", "숨은 내리막: %s" % Music.current())
	await _close_room(r7)
	# 아직 정화하지 않은 보스 방: 앞 방의 곡이 이어진다 (싸움이 시작되면 보스곡)
	var r8 := await _open_room("canopy_boss")
	_check(Music.current() == "field_sap_lake", "정화 전 보스 방은 앞 곡을 그대로 둔다 (지금 %s)" % Music.current())
	r8.player.global_position = r8.get_node("BossTrigger").position + Vector2(40, 0)
	await _frames(4)
	_check(r8.fight_started and Music.current() == "boss_bird", "싸움 시작 → 보스곡 %s" % Music.current())
	r8._on_boss_fallen()
	await _frames(2)
	_check(Music.current() == "", "보스가 쓰러지면 정적 ('%s')" % Music.current())
	await _close_room(r8)
	Progress.reset()
	# 중간 보스 방: 싸움 → 보스곡, 소녀가 쓰러져 일어나면 들판 곡 / 보스를 쓰러뜨리면 들판 곡
	var r9 := await _open_room("canopy_hidden")
	# 일어나는 자리는 문 밖 (게임에서는 포탈로 들어온 입구 자리) — 문 안이면 일어나자마자 싸움이 다시 시작된다
	r9.rest_point = Vector2(r9.get_node("GateIn").position.x - 300.0, r9.player.global_position.y)
	r9._start_fight()
	await _frames(2)
	var mini_track := Music.current()
	r9._on_player_died()
	var t0 := Time.get_ticks_msec()
	while Music.current() == mini_track and Time.get_ticks_msec() - t0 < 6000:
		await _frames(1)
	print("[probe]   (쓰러지고 %.1f초 뒤 곡이 바뀜 → %s)" % [(Time.get_ticks_msec() - t0) / 1000.0, Music.current()])
	await _wait(1.0)
	var after_death := Music.current()   # 1초 뒤에도 그대로 (싸움이 다시 붙지 않음)
	r9._start_fight()
	await _frames(2)
	r9._on_boss_died(true)
	await _frames(2)
	_check(mini_track == "boss_bird" and after_death == "field_canopy" and Music.current() == "field_canopy",
		"중간 보스 방: 싸움 %s → 쓰러졌다 문 밖에서 일어나면 %s → 이기면 %s (일어난 자리 x %.0f, 시작 선 x %.0f)" % [mini_track, after_death, Music.current(), r9.player.global_position.x, r9.get_node("BossTrigger").position.x])
	await _close_room(r9)
	Progress.reset()


# ---------- 5) 쉼 · 회상 곡 붙잡기 ----------
func _probe_rest_and_hold() -> void:
	Progress.reset()
	Music.stop(0.0)
	var room := await _open_room("canopy_01")
	var player: Player = room.player
	var grass: Node2D = get_tree().get_first_node_in_group("moonlight_grass")
	player.global_position = grass.global_position + Vector2(60, -4)
	await _frames(3)
	player.start_rest(grass)
	await _frames(2)
	var resting := Music.current()
	player._set_state(Player.State.IDLE)
	await _frames(2)
	var after := Music.current()
	_check(resting == Music.REST and after == "field_canopy" and not Music.is_resting(), "달빛풀에서 쉬면 %s → 일어서면 %s" % [resting, after])
	await _close_room(room)
	# 달빛풀로 이동해 와서 쉬는 자세로 도착: 쉼터 곡을 이어 간다 (들판 곡이 끼어들지 않음)
	Music.rest_begin(0.0)
	var p0 = Music._players[Music._active]
	var gid := ""
	var ps := load("res://scenes/rooms/canopy_02.tscn") as PackedScene
	var st := ps.get_state()
	for i in st.get_node_count():
		for j in st.get_node_property_count(i):
			if str(st.get_node_property_name(i, j)) == "grass_id":
				gid = str(st.get_node_property_value(i, j))
	Progress.next_spawn = "Grass:" + gid
	var room2 := await _open_room("canopy_02")
	await _frames(4)
	_check(gid != "" and Music.current() == Music.REST and Music._players[Music._active] == p0 and room2.player.state == Player.State.REST,
		"달빛풀 '%s' 로 이동해 쉬는 자세로 도착: 쉼터 곡이 끊기지 않고 이어짐 (%s, 소녀 %s)" % [gid, Music.current(), room2.player.state_name()])
	room2.player._set_state(Player.State.IDLE)
	await _frames(2)
	_check(Music.current() == "field_canopy", "도착한 곳에서 일어서면 그 방의 들판 곡: %s" % Music.current())
	await _close_room(room2)
	Progress.next_spawn = ""
	# 회상 곡 붙잡기: 회상 → 방으로 돌아와도 HOLD 초 동안 이어지다가 들판 곡
	Music.play(Music.RECOLLECTION, {"fade": 0.0, "from": 0.0})
	Music.hold(Music.RECOLLECTION, 0.6)
	Music.play_region("village", "village_01")
	await _wait(0.3)
	var held := Music.current()
	await _wait(0.6)
	_check(held == Music.RECOLLECTION and Music.current() == "field_village" and not Music.is_holding(), "회상 곡 붙잡기: 돌아온 직후 %s → 0.6초 뒤 %s" % [held, Music.current()])
	var ms := MemoryScene.HOLD_AFTER
	_check(ms >= 5.0 and ms <= 15.0, "회상 씬이 방으로 돌아간 뒤 회상 곡을 %.0f초 더 붙잡는다" % ms)
	Music.stop(0.0)


# ---------- 6) 타이틀 · 엔딩 · 보스 2페이즈 ----------
func _probe_title_ending_boss() -> void:
	_check(Music.title_track(false) == "title" and Music.title_track(true) == "selenia_humming", "타이틀 곡: 클리어 전 %s / 뒤 %s" % [Music.title_track(false), Music.title_track(true)])
	Progress.reset()
	var title_script: Script = load("res://scripts/ui/title_screen.gd")
	var cleared: bool = title_script.cleared_state()["cleared"]
	var title: Node = load("res://scenes/ui/title_screen.tscn").instantiate()
	add_child(title)
	await _idle_frames(4)   # 타이틀은 저장이 없으면 한 프레임 기다린 뒤 곡을 튼다
	var t0 := Music.current()
	var l0 := Music.current_loops()
	_check(t0 == Music.title_track(cleared) and l0, "타이틀 (클리어 %s): %s, 반복 %s" % [cleared, t0, l0])
	# 타이틀의 '설정': 일시정지 메뉴의 설정 화면을 그대로 쓴다
	var sm: PauseMenu = title.open_settings()
	await _frames(2)
	_check(sm.is_open() and not get_tree().paused and sm.row_of("music_volume") >= 0 and sm.row_of("sfx_volume") >= 0 and sm.row_of("master_volume") >= 0 and sm.row_of("save") < 0 and sm.row_of("title") < 0,
		"타이틀 설정 화면: 열림, 게임 안 멈춤, 음악·효과음·전체 음량 줄 있음, 저장·타이틀로 줄 없음")
	sm.close()
	title.queue_free()
	await _frames(2)
	Progress.set_flag("cleared")
	var title2: Node = load("res://scenes/ui/title_screen.tscn").instantiate()
	add_child(title2)
	await _idle_frames(4)
	var t1 := Music.current()
	var l1 := Music.current_loops()
	_check(t1 == "selenia_humming" and l1, "엔딩을 본 뒤 타이틀: %s (타이틀에선 반복 %s)" % [t1, l1])
	title2.queue_free()
	await _frames(2)
	Progress.reset()
	# 엔딩: 한 번만 (크레딧까지)
	var ending_script: Script = load("res://scripts/ui/ending_scene.gd")
	var et: String = ending_script.ending_track("third")
	Music.play(et, {"fade": 0.0, "from": 0.0, "loop": false})
	await _frames(2)
	_check(et == "selenia_humming" and ending_script.ending_track("return") == et and Music.current() == et and not Music.current_loops(), "엔딩 곡: 세 엔딩 모두 %s, 한 번만 (반복 %s)" % [et, Music.current_loops()])
	# 같은 곡 사본의 반복을 바꿔도 원본(캐시)은 한 번만 그대로
	var orig := load(Music.DIR + "selenia_humming.wav") as AudioStreamWAV
	_check(orig.loop_mode == AudioStreamWAV.LOOP_DISABLED, "타이틀에서 반복으로 틀어도 원본 곡 설정은 그대로 (한 번만)")
	# 무쇠 펌프 2페이즈: 곡은 그대로, 한 번 휘청
	Music.play("boss_iron_pump", 0.0, true)
	Music.falter(0.16, 1.0)
	await _wait(0.3)
	var pitch: float = Music._players[Music._active].pitch_scale
	var faltering := Music.is_faltering()
	await _wait(1.0)
	var pitch2: float = Music._players[Music._active].pitch_scale
	_check(faltering and pitch < 0.95 and is_equal_approx(pitch2, 1.0) and Music.current() == "boss_iron_pump", "펌프 2페이즈: 곡 그대로 %s, 휘청 (속도 %.2f → %.2f)" % [Music.current(), pitch, pitch2])
	# 뿌리지기: 무너졌다 다시 일어서는 순간(rise) 2페이즈 곡으로
	Progress.reset()
	var ar := await _open_room("abyss_boss")
	ar.fight_started = true
	Music.play(ar.boss_track, 0.0, true)
	ar._on_boss_telegraph("rise")
	await _frames(2)
	_check(Music.current() == "boss_rootkeeper_p2", "뿌리지기 다시 일어섬 → %s" % Music.current())
	ar.fight_started = false
	await _close_room(ar)
	# 정적 → 페이드 0 이면 바로 조용
	Music.stop(0.0)
	var any_playing := false
	for p in Music._players:
		any_playing = any_playing or p.playing
	_check(Music.current() == "" and not any_playing, "stop(0) → 바로 조용")
	# 같은 곡을 다시 부르면 그대로 (다시 시작하지 않음), from 을 주면 그 자리부터
	Music.play("field_mine", 0.0)
	var pa = Music._players[Music._active]
	Music.play("field_mine", 1.0)
	var kept: bool = Music._players[Music._active] == pa
	Music.play("field_mine", {"fade": 0.0, "from": 30.0})
	await _wait(0.2)
	var pos := Music.playback_time("field_mine")
	_check(kept and pos > 29.5 and pos < 31.5, "같은 곡은 그대로 두고, {from: 30} 은 30초 자리부터 (%.2f초)" % pos)
	Music.stop(0.0)


# ---------- 7) 버스 ----------
func _probe_buses() -> void:
	var mi := AudioServer.get_bus_index("Music")
	var si := AudioServer.get_bus_index("SFX")
	_check(mi > 0 and si > 0 and AudioServer.get_bus_send(mi) == &"Master" and AudioServer.get_bus_send(si) == &"Master", "버스: Master ← Music(%d), SFX(%d)" % [mi, si])
	_check(ResourceLoader.exists("res://default_bus_layout.tres"), "default_bus_layout.tres 가 있다")
	var music_ok := true
	for p in Music._players:
		music_ok = music_ok and p.bus == &"Music"
	var sfx_ok := true
	for p in Sfx._players:
		sfx_ok = sfx_ok and p.bus == &"SFX"
	_check(music_ok and sfx_ok, "음악 플레이어 → Music, 효과음 플레이어 → SFX")
	# 'Master' 로 바로 보내는 소리 플레이어가 코드·씬에 없다
	var direct := []
	var re := RegEx.create_from_string("bus\\s*=\\s*&?\"Master\"")
	for path in _gd_files("res://scripts/") + _tscn_files("res://scenes/"):
		if re.search(FileAccess.get_file_as_string(path)):
			direct.append(path.get_file())
	_check(direct.is_empty(), "Master 버스로 바로 보내는 플레이어 없음 %s" % [direct])


func _tscn_files(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_tscn_files(dir.path_join(d)))
	return out


# ---------- 8) 음량 ----------
func _db(bus: String) -> float:
	return AudioBuses.bus_db(bus)


func _probe_volume() -> void:
	var saved := {}
	for k in ["music_volume", "sfx_volume", "master_volume"]:
		saved[k] = Settings.get_value(k)
	Settings.set_value("master_volume", 10)
	Settings.set_value("music_volume", 10)
	Settings.set_value("sfx_volume", 10)
	var base := [_db("Master"), _db("Music"), _db("SFX")]
	_check(is_zero_approx(base[0]) and is_zero_approx(base[1]) and is_zero_approx(base[2]), "음량 10 = 세 버스 모두 0dB %s" % [base])
	Settings.set_value("sfx_volume", 3)
	var a := [_db("Master"), _db("Music"), _db("SFX")]
	_check(is_zero_approx(a[0]) and is_zero_approx(a[1]) and absf(a[2] - linear_to_db(0.3)) < 0.01, "효과음 음량 3 → SFX 만 %.1fdB (Master %.1f, Music %.1f — 전엔 Master 를 바꿔 음악도 작아졌다)" % [a[2], a[0], a[1]])
	Settings.set_value("sfx_volume", 0)
	var si := AudioServer.get_bus_index("SFX")
	_check(AudioServer.is_bus_mute(si) and is_zero_approx(_db("Music")) and is_zero_approx(_db("Master")), "효과음 음량 0 → SFX 끔, 음악은 그대로")
	Settings.set_value("sfx_volume", 10)
	Settings.set_value("music_volume", 5)
	var b := [_db("Master"), _db("Music"), _db("SFX")]
	_check(is_zero_approx(b[0]) and absf(b[1] - linear_to_db(0.5)) < 0.01 and is_zero_approx(b[2]), "음악 음량 5 → Music 만 %.1fdB" % b[1])
	Settings.set_value("music_volume", 0)
	var mi := AudioServer.get_bus_index("Music")
	_check(AudioServer.is_bus_mute(mi) and is_zero_approx(_db("SFX")), "음악 음량 0 → Music 끔, 효과음은 그대로")
	Settings.set_value("music_volume", 10)
	Settings.set_value("master_volume", 5)
	var c := [_db("Master"), _db("Music"), _db("SFX")]
	_check(absf(c[0] - linear_to_db(0.5)) < 0.01 and is_zero_approx(c[1]) and is_zero_approx(c[2]), "전체 음량 5 → Master 만 %.1fdB" % c[0])
	Settings.set_value("master_volume", 10)
	# 일시정지 메뉴의 줄로 바꾸기 (좌우 입력과 같은 길)
	var pm := PauseMenu.new()
	add_child(pm)
	pm.open(true)
	await _frames(1)
	pm.adjust_row("music_volume", -1)
	pm.adjust_row("music_volume", -1)
	var d := [_db("Master"), _db("Music"), _db("SFX")]
	_check(int(Settings.get_value("music_volume")) == 8 and is_zero_approx(d[0]) and absf(d[1] - linear_to_db(0.8)) < 0.01 and is_zero_approx(d[2]), "설정 화면에서 음악 음량 ◀◀ → 8, Music 만 %.1fdB" % d[1])
	pm.adjust_row("sfx_volume", -1)
	var e := [_db("Master"), _db("Music"), _db("SFX")]
	_check(int(Settings.get_value("sfx_volume")) == 9 and absf(e[2] - linear_to_db(0.9)) < 0.01 and absf(e[1] - linear_to_db(0.8)) < 0.01, "설정 화면에서 효과음 음량 ◀ → 9, SFX 만 바뀜")
	# 터치: 그려진 값 글자 '◀ … ▶' 의 ◀ 를 누르면 줄이기, ▶ 를 누르면 키우기 (2026-10-20 QA: 고정 칸 가운데로 가르면 짧은 값에서 거꾸로 움직였다)
	var row := pm.row_of("music_volume")
	var vr: Rect2 = pm.value_text_rect(row)
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = Vector2(vr.position.x + 8.0, vr.get_center().y)
	pm._input(ev)
	var after_left := int(Settings.get_value("music_volume"))
	ev.position = Vector2(pm.value_text_rect(row).end.x - 8.0, vr.get_center().y)
	pm._input(ev)
	var after_right := int(Settings.get_value("music_volume"))
	_check(after_left == 7 and after_right == 8, "터치로 음악 음량: ◀ 누르면 %d, ▶ 누르면 %d" % [after_left, after_right])
	# 음량 0 ('◀ 끔 ▶' — 짧은 글자): ◀ 는 그대로 0, ▶ 는 1
	Settings.set_value("music_volume", 0)
	ev.position = Vector2(pm.value_text_rect(row).position.x + 8.0, vr.get_center().y)
	pm._input(ev)
	var zero_left := int(Settings.get_value("music_volume"))
	ev.position = Vector2(pm.value_text_rect(row).end.x - 8.0, vr.get_center().y)
	pm._input(ev)
	var zero_right := int(Settings.get_value("music_volume"))
	_check(zero_left == 0 and zero_right == 1, "음량 0 ('◀ 끔 ▶'): ◀ 누르면 %d (그대로), ▶ 누르면 %d" % [zero_left, zero_right])
	Settings.set_value("music_volume", 8)
	pm.close()
	pm.queue_free()
	# 옛 settings.json (전체 음량 없음) 도 읽힌다
	var had_file := FileAccess.file_exists(Settings.PATH)
	var old_text := FileAccess.get_file_as_string(Settings.PATH) if had_file else ""
	var f := FileAccess.open(Settings.PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"lenient_guard": true, "sfx_volume": 4, "music_volume": 6, "touch_scale": 1, "debug_hud": false, "screen_shake": true}))
	f.close()
	Settings.data["master_volume"] = 10
	Settings.load_settings()
	_check(int(Settings.get_value("sfx_volume")) == 4 and int(Settings.get_value("music_volume")) == 6 and int(Settings.get_value("master_volume")) == 10 and absf(_db("SFX") - linear_to_db(0.4)) < 0.01 and absf(_db("Music") - linear_to_db(0.6)) < 0.01,
		"옛 settings.json (전체 음량 없음): 효과음 4·음악 6 읽힘, 전체 10, 버스에 반영")
	# 되돌리기
	if had_file:
		var f2 := FileAccess.open(Settings.PATH, FileAccess.WRITE)
		f2.store_string(old_text)
		f2.close()
		Settings.load_settings()
	for k in saved:
		Settings.set_value(k, saved[k])
	if not had_file:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.PATH))


# ---------- 9) 수액의 여왕 박자 ----------
func _probe_queen() -> void:
	var st := load(Music.DIR + SapQueen.TRACK + ".wav") as AudioStreamWAV
	var length := st.get_length()
	var span := SapQueen.loop_span(length)
	var bars := span / SapQueen.BAR
	_check(is_equal_approx(SapQueen.BEAT, 60.0 / 138.0) and absf(SapQueen.DOWNBEAT - 0.123) < 0.02, "여왕 박자: 138bpm 3/4, 첫 강박 %.3f초 (정식 곡에서 잰 값)" % SapQueen.DOWNBEAT)
	_check(absf(bars - roundf(bars)) < 0.001 and absf(span - length) < SapQueen.BAR * 0.1, "보스곡 %.2f초 → 한 바퀴 %d마디(%.2f초): 반복해도 박자 격자가 곡의 강박에 맞는다 (차이 %.3f초)" % [length, roundi(bars), span, length - span])
	_check(absf(SapQueen.clock_from_music(SapQueen.DOWNBEAT)) < 0.0001 and absf(SapQueen.clock_from_music(SapQueen.DOWNBEAT, 1, length) - span) < 0.0001, "곡 위치 → 박자 시계: 첫 강박 = 0, 한 바퀴 뒤 첫 강박 = 한 바퀴 길이")

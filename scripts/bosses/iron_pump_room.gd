extends BossRoom
class_name IronPumpRoom
## 무쇠 펌프의 방 (잠긴 채굴장 · 펌프실의 심장). BossRoom 을 그대로 쓰되,
## - 정화하는 순간 펌프가 빛으로 흩어지는 자리에 멈춘 펌프(PumpRemains)가 나타나 싹이 튼다 → 회상 (EXPANSION 4장 순서).
##   회상에서 돌아온 뒤에도 같은 자리·같은 방향으로 남는다 (자리는 이번 실행 동안 Progress 의 메타에 기억; 앱을 새로 켜면 기본 자리).
## - 2페이즈가 되면 음악도 흐트러진다: 보스곡은 그대로 두고(정식 곡은 한 곡) 곡이 한 번 휘청인다 (Music.falter — 테이프가 늘어지듯
##   음이 FALTER_DEPTH 만큼 처졌다가 FALTER_TIME 초에 돌아옴). boss_track_2 를 정하면 대신 그 곡으로 바꾼다.
## - Claude Code용 스크린샷 시험(--bossshots, 예전 이름 --pumpshots): 창으로 띄워 상태마다 사진을 찍는다.

const REMAINS_META := "iron_pump_remains"
## 2페이즈 순간 곡이 휘청이는 깊이(재생 속도를 이만큼 낮춤)와 길이(초). 0 이면 휘청이지 않는다.
const FALTER_DEPTH := 0.16
const FALTER_TIME := 1.4


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--bosstest" in args or "--pumpshots" in args or "--bossshots" in args:
		# 시험용: 이 방은 수액 위 걷기가 있어야만 올 수 있다 (바닥이 수액 — 없으면 시험 중 소녀가 수액에 녹는다)
		Progress.gain_ability("sap_walk")
	super._ready()
	var remains := get_node_or_null("PumpRemains")
	if remains:
		remains.visible = Progress.has(defeat_flag)
		if remains.visible and Progress.has_meta(REMAINS_META):
			var at: Vector2 = Progress.get_meta(REMAINS_META)   # (x, 좌우 배율)
			remains.position.x = at.x
			remains.scale.x = at.y
	if is_instance_valid(boss) and not Progress.has(defeat_flag):
		boss.purified.connect(_on_pump_stopped)
		boss.phase_changed.connect(_on_pump_phase)
	if "--pumpshots" in args or "--bossshots" in args:
		_bossshots()


## 정화의 손길: 펌프가 빛으로 흩어지는 그 자리에 멈춘 펌프가 나타나고 싹이 튼다 (BossRoom 이 1.8초 뒤 회상으로 넘어간다).
func _on_pump_stopped() -> void:
	var remains := get_node_or_null("PumpRemains")
	if remains == null or _rush:
		return   # 보스 러시: 멈춘 펌프도 남기지 않는다 (Progress 메타를 쓰지 않게)
	var flip := 1.0 if int(boss.facing) <= 0 else -1.0   # 멈춘 펌프 그림은 기본이 왼쪽을 본다
	remains.global_position = Vector2(boss.global_position.x, remains.global_position.y)
	remains.scale.x = flip
	Progress.set_meta(REMAINS_META, Vector2(remains.position.x, flip))
	# 쓰러진 보스와 같은 자세로 (부위 뼈대 자세를 그대로 옮겨 받는다)
	if remains.has_method("match_pose"):
		remains.match_pose(boss.get_node_or_null("Sprite"))
	if remains.has_method("sprout"):
		remains.sprout(1.6)
	else:
		remains.visible = true


## 2페이즈: 규칙이 무너지면 음악도 흐트러진다.
func _on_pump_phase(ph: int) -> void:
	if ph != 2 or not fight_started:
		return
	if boss_track_2 != "" and ResourceLoader.exists(Music.DIR + boss_track_2 + ".wav"):
		Music.play(boss_track_2, 0.4, true)
	elif FALTER_DEPTH > 0.0:
		Music.falter(FALTER_DEPTH, FALTER_TIME)


## Claude Code용 (창으로 실행): 싸움을 걸고 상태마다 screenshots/debug_pump_<순서>_<상태>.png 를 찍는다.
## 등장 · 대기 · 걷기 · 피스톤(예고/내려찍음/회복) · 분사(버팀/쏨) · 빨아들이기(겨눔/들이마심/물기) · 장갑 깨짐 · 휘청(2페이즈)
## · 2페이즈 예고(멈칫거림) · 쓰러짐(경련/꺾임/부딪힘/누움) · 정화(빛으로 흩어짐 + 멈춘 펌프와 싹).
## 콘솔에는 사진마다 보스 상태·발바닥 높이·몸의 가장 낮은 점(땅 0, 아래 +)을 찍는다.
func _bossshots() -> void:
	var tree := get_tree()
	await tree.create_timer(0.6).timeout
	var ground: float = $Markers/GroundLine.position.y
	player.global_position = Vector2(1300, ground - 2.0)
	player._invuln_timer = 9999.0
	player.hp = player.max_hp
	var n := [0]
	var snap := func(tag: String) -> void:
		n[0] += 1
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var hdr := img.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]
		img.convert(Image.FORMAT_RGBA8)
		if hdr:
			img.linear_to_srgb()
		var path := "debug_pump_%02d_%s.png" % [n[0], tag]
		img.save_png(ProjectSettings.globalize_path("res://screenshots/" + path))
		var vis = boss.get_node_or_null("Sprite")
		var pp: Dictionary = vis.probe_pose() if vis and vis.has_method("probe_pose") else {}
		print("[펌프샷] %-26s %-8s %-9s 발바닥 %s 가장 낮은 몸 %+.1f (%s)" % [path, boss.state_name(), boss.attack_phase, str(pp.get("soles", [])), float(pp.get("lowest", 0.0)), pp.get("low_bone", "")])
	# 소녀를 펌프 앞 일정 거리에 붙잡아 둔다 (카메라가 소녀를 따라가므로 펌프가 화면에 들어온다)
	var hold := func(dist: float) -> void:
		if is_instance_valid(boss) and boss.state_name() not in ["WAIT"]:
			player.global_position = Vector2(boss.global_position.x + float(boss.facing) * dist, ground - 2.0)
			player.velocity = Vector2.ZERO
			player._invuln_timer = 9999.0
			player.hp = player.max_hp
	var wait := func(sec: float, dist := 460.0) -> void:
		var t := 0.0
		while t < sec:
			hold.call(dist)
			await tree.physics_frame
			t += 1.0 / 60.0
	var until := func(cond: Callable, limit: float, dist := 460.0) -> bool:
		var t := 0.0
		while t < limit:
			if cond.call():
				return true
			hold.call(dist)
			await tree.physics_frame
			t += 1.0 / 60.0
		return false
	# 등장 (소녀가 문턱을 넘으면 BossRoom 이 싸움을 건다)
	await until.call(func() -> bool: return fight_started, 3.0)
	await wait.call(0.5)
	await snap.call("intro_sleep")
	await wait.call(0.8)
	await snap.call("intro_rise")
	await wait.call(0.35)
	await snap.call("intro_roar")
	await until.call(func() -> bool: return boss.state_name() == "IDLE", 3.0)
	await wait.call(0.3)
	await snap.call("idle")
	# 1페이즈 순서: 피스톤 → 분사 → 빨아들이기
	for atk in ["PISTON", "SPRAY", "SUCK"]:
		await until.call(func() -> bool: return boss.state_name() == atk and boss.attack_phase == "startup" and boss.phase_progress() > 0.65, 8.0)
		await snap.call(atk.to_lower() + "_windup")
		await until.call(func() -> bool: return boss.attack_phase == "active", 3.0)
		await wait.call(0.05 if atk == "PISTON" else (0.3 if atk == "SPRAY" else 0.8))
		await snap.call(atk.to_lower() + "_active")
		if atk == "SUCK":
			await until.call(func() -> bool: return boss._bit, 3.0)
			await wait.call(0.05)
			await snap.call("suck_bite")
		await until.call(func() -> bool: return boss.attack_phase == "recovery", 3.0)
		await wait.call(0.25)
		await snap.call(atk.to_lower() + "_recover")
	# 걷기: 소녀가 멀리 있으면 기어 온다
	await until.call(func() -> bool: return boss.state_name() == "IDLE", 6.0)
	boss._timer = 3.0
	await wait.call(1.2, 900.0)
	await snap.call("walk")
	await wait.call(0.4, 900.0)
	await snap.call("walk_b")
	# 장갑 깨짐
	await until.call(func() -> bool: return boss.state_name() == "IDLE", 8.0)
	boss.poise = boss.max_poise - 1.0
	boss.receive_hit(HitData.make(1.0, 60.0, player), null)
	await wait.call(0.8)
	await snap.call("broken")
	await until.call(func() -> bool: return boss.state_name() == "IDLE", 6.0)
	# 2페이즈: 휘청 → 엇박 예고
	boss.hp = boss.max_hp * 0.45
	boss.receive_hit(HitData.make(1.0, 0.0, player), null)
	await wait.call(0.15)
	await snap.call("stagger")
	await until.call(func() -> bool: return boss.attack_phase == "startup" and boss.phase_progress() > 0.5, 8.0)
	await snap.call("p2_windup")
	await until.call(func() -> bool: return boss.state_name() == "IDLE", 6.0)
	await wait.call(0.4)
	await snap.call("p2_idle")
	# 쓰러짐
	boss.hp = 1.0
	boss.receive_hit(HitData.make(5.0, 0.0, player), null)
	for at in [[0.2, "fall_jolt"], [0.75, "fall_buckle"], [1.3, "fall_crash"], [2.8, "fallen"]]:
		await wait.call(float(at[0]) - (0.0 if at[1] == "fall_jolt" else 0.0), 420.0)
		await snap.call(str(at[1]))
	# 정화: 손을 얹는다 → 빛으로 흩어지고 멈춘 펌프에 싹이 튼다
	player.global_position = Vector2(boss.global_position.x + float(boss.facing) * 200.0, ground - 2.0)
	await tree.create_timer(0.3).timeout
	Input.action_press("interact")
	await tree.physics_frame
	Input.action_release("interact")
	await until.call(func() -> bool: return boss.state_name() == "PURIFIED", 4.0, 200.0)
	await tree.create_timer(0.5).timeout
	await snap.call("purify")
	await tree.create_timer(1.0).timeout
	await snap.call("remains")
	print("[펌프샷] 끝: %d장" % n[0])
	tree.quit()

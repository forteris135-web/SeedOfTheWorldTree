extends BossRoom
class_name IronPumpRoom
## 무쇠 펌프의 방 (잠긴 채굴장 · 펌프실의 심장). BossRoom 을 그대로 쓰되,
## - 정화하는 순간 펌프가 빛으로 흩어지는 자리에 멈춘 펌프(PumpRemains)가 나타나 싹이 튼다 → 회상 (EXPANSION 4장 순서).
##   회상에서 돌아온 뒤에도 같은 자리·같은 방향으로 남는다 (자리는 이번 실행 동안 Progress 의 메타에 기억; 앱을 새로 켜면 기본 자리).
## - 2페이즈가 되면 음악도 흐트러진다: 보스곡은 그대로 두고(정식 곡은 한 곡) 곡이 한 번 휘청인다 (Music.falter — 테이프가 늘어지듯
##   음이 FALTER_DEPTH 만큼 처졌다가 FALTER_TIME 초에 돌아옴). boss_track_2 를 정하면 대신 그 곡으로 바꾼다.
## - Claude Code용 스크린샷 시험(--pumpshots).

const REMAINS_META := "iron_pump_remains"
## 2페이즈 순간 곡이 휘청이는 깊이(재생 속도를 이만큼 낮춤)와 길이(초). 0 이면 휘청이지 않는다.
const FALTER_DEPTH := 0.16
const FALTER_TIME := 1.4


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--bosstest" in args or "--pumpshots" in args:
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
	if "--pumpshots" in OS.get_cmdline_user_args():
		_pumpshots()


## 정화의 손길: 펌프가 빛으로 흩어지는 그 자리에 멈춘 펌프가 나타나고 싹이 튼다 (BossRoom 이 1.8초 뒤 회상으로 넘어간다).
func _on_pump_stopped() -> void:
	var remains := get_node_or_null("PumpRemains")
	if remains == null:
		return
	var flip := 1.0 if int(boss.facing) <= 0 else -1.0   # 그림 원본은 왼쪽을 본다
	remains.global_position = Vector2(boss.global_position.x, remains.global_position.y)
	remains.scale.x = flip
	Progress.set_meta(REMAINS_META, Vector2(remains.position.x, flip))
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


## Claude Code용: 싸움을 걸고 피스톤·분사·빨아들이기·장갑 깨짐의 순간을 screenshots/debug_pump_<상태>.png 로 찍는다 (화면 있는 실행).
func _pumpshots() -> void:
	var tree := get_tree()
	await tree.create_timer(0.6).timeout
	player.global_position = $Markers/HoverCenter.position + Vector2(0, 700)
	player._invuln_timer = 9999.0
	await tree.create_timer(1.0).timeout
	var shots := {}
	var t := 0.0
	var last := ""
	while t < 34.0 and is_instance_valid(boss):
		await tree.create_timer(0.05).timeout
		t += 0.05
		var sname: String = boss.state_name()
		if sname != last:
			print("[펌프샷] %5.1f초 %s (체력 %.0f, 장갑 %.0f, 페이즈 %d)" % [t, sname, boss.hp, boss.poise, boss.phase])
			last = sname
		if sname in ["PISTON", "SPRAY", "SUCK"] and boss.attack_phase == "active" and not shots.has(sname):
			shots[sname] = true
			await tree.create_timer(0.08 if sname == "PISTON" else 0.3).timeout
			_save_screenshot("debug_pump_%s.png" % sname.to_lower())
		if sname == "PISTON" and boss.attack_phase == "startup" and not shots.has("telegraph") and boss.phase_progress() > 0.7:
			shots["telegraph"] = true
			_save_screenshot("debug_pump_telegraph.png")
		if sname == "BROKEN" and not shots.has("BROKEN"):
			shots["BROKEN"] = true
			await tree.create_timer(0.6).timeout
			_save_screenshot("debug_pump_broken.png")
		if t > 14.0 and boss.phase == 1 and not shots.has("BROKEN"):
			boss.poise = boss.max_poise - 1.0
			boss.receive_hit(HitData.make(1.0, 60.0, player), null)
		if t > 22.0 and boss.phase == 1:
			boss.hp = boss.max_hp * 0.45
			boss.receive_hit(HitData.make(1.0, 0.0, player), null)
		if shots.size() >= 6 and t > 30.0:
			break
	print("[펌프샷] 찍은 것: %s (%.1f초)" % [shots.keys(), t])
	tree.quit()

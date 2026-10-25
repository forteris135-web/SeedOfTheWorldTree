extends Room
class_name BossRoom
## 보스가 있는 방. 안으로 들어서면 문이 닫히고 싸움이 시작된다.
## 정화하면: 회상 → 영혼이 깃듦 → 지역에 색이 돌아옴 → 능력 획득.
## 보스 러시 중(BossRush.active, 이 방이 러시의 보스 방)에는 '러시 모드': 소녀가 싸움터 안에서 바로 시작하고, 등장 연출이 짧고,
## 쓰러뜨리면 기록만 남긴 채 다음 보스 방으로 넘어간다 — 깃발·정화·회상·빛 가루·능력 없음, 소녀가 쓰러지면 결과 화면.

@export var boss_name := "잿빛 잎새의 새"
@export var boss_subtitle := "수관의 수호자"
@export var defeat_flag := "boss_bird_defeated"
@export var memory_id := "memory_bird"
@export var abilities := ["double_jump", "wind"]
@export var reward_message := "영혼이 깃들었다 — 이단 점프, 바람 공격"
@export var fallen_message := "새가 쓰러졌다. 손을 얹어라."
## 최종 보스: 회상 뒤 능력 대신 선택지가 열린다 (EndingChoice 노드들이 깨어난다).
@export var final_boss := false
## 보스곡 이름 (audio/music/)
@export var boss_track := "boss_bird"
## 2페이즈 보스곡 (비우면 바꾸지 않는다). 뿌리지기는 무너졌다 다시 일어서는 순간(RISE) boss_rootkeeper_p2 로 바뀐다.
@export var boss_track_2 := ""
## 보스를 정화하면 떨어지는 재화 '빛 가루' (2026-10-19 기획자 요청 9번). 처음 한 번만 — 깃발 "dust_<defeat_flag>" 로 막는다.
@export var dust_reward := 200

@onready var boss: Node = $Boss
@onready var gate_in: FogGate = $GateIn
@onready var gate_out: FogGate = $GateOut
@onready var trigger: Area2D = $BossTrigger
@onready var boss_hud = $BossHUD

var fight_started := false
## 보스 러시 모드 (scripts/world/boss_rush.gd)
var _rush := false


func _ready() -> void:
	_rush = BossRush.active and BossRush.index_of_scene(scene_file_path) >= 0
	super._ready()
	var arena := $Arena as ReferenceRect
	boss.arena = Rect2(arena.position, arena.size)
	boss.ground_y = $Markers/GroundLine.position.y
	if "hover_points" in boss:
		boss.hover_points = [$Markers/HoverLeft.position, $Markers/HoverCenter.position, $Markers/HoverRight.position]
	if "piles" in boss and has_node("LeafPiles"):
		boss.piles = $LeafPiles.get_children()
	boss.fallen.connect(_on_boss_fallen)
	boss.purified.connect(_on_boss_purified)
	boss.telegraph.connect(_on_boss_telegraph)
	boss_hud.bind(boss, boss_name, boss_subtitle)
	trigger.body_entered.connect(_on_trigger)
	if has_node("Choices"):
		$Choices.visible = Progress.has("after_" + defeat_flag)
		for c in $Choices.get_children():
			c.process_mode = Node.PROCESS_MODE_INHERIT if $Choices.visible else Node.PROCESS_MODE_DISABLED
	if Progress.has(defeat_flag) and not _rush:
		boss.queue_free()
		trigger.queue_free()
		if Progress.has("after_" + defeat_flag):
			pass
		else:
			# 회상에서 막 돌아왔다: 영혼이 깃들고 색이 돌아온다
			Progress.set_flag("after_" + defeat_flag)
			_after_memory()
	if _rush:
		_rush_setup()
	if "--bosstest" in OS.get_cmdline_user_args():
		_bosstest()


func _process(delta: float) -> void:
	super._process(delta)
	if _rush and fight_started:
		BossRush.tick(delta)
	# 순간이동 등으로 영역을 건너뛰어도, 문 안쪽에 들어와 있으면 싸움이 시작된다
	if not fight_started and player and is_instance_valid(trigger) and not Progress.has(defeat_flag) \
			and player.global_position.x > trigger.position.x and player.state != Player.State.DEAD:
		_on_trigger(player)


func _on_trigger(body: Node) -> void:
	if fight_started or not (body is Player) or Progress.has(defeat_flag):
		return
	fight_started = true
	gate_in.close()
	gate_out.close()
	_set_battle_camera(true)
	boss.start_fight(player)
	boss_hud.show_boss()
	Music.play(boss_track, 0.8, true)
	Juice.shake(5.0)
	if _rush:
		BossRush.fight_started()
		_rush_shorten_intro()
	_frame_intro()


## 보스 등장 구도: 이름 카드가 뜨는 동안(INTRO 남은 시간) 카메라가 소녀와 보스 가운데를 보여 준다 (2026-10-20 검수 —
## 보스가 x 2550~2600 에서 등장해 화면 오른쪽 끝에 반쯤 잘리고 터치 버튼 뒤에 가려졌다). 보스 자리·싸움은 그대로.
func _frame_intro() -> void:
	var cam := player.get_node_or_null("Camera2D") if player else null
	if cam == null or not cam.has_method("frame_with") or not is_instance_valid(boss):
		return
	var left := 1.6
	if boss.has_method("state_name") and boss.state_name() == "INTRO" and "_timer" in boss:
		left = float(boss.get("_timer"))
	cam.frame_with(boss, clampf(left - 0.6, 0.3, 2.4))


## 보스 공격 이름 글자가 보이는 시간 (초, 마지막 0.3초 옅어짐)
const TELEGRAPH_LABEL_TIME := 1.3


func _on_boss_telegraph(kind: String) -> void:
	var hud := get_node_or_null("CombatHUD")
	if hud == null:
		return
	# 보스 스크립트가 telegraph_label(kind) 로 글자를 주면 그것을 쓴다 (새 패턴은 보스 쪽만 고치면 된다; "" 이면 글자 없음)
	if is_instance_valid(boss) and boss.has_method("telegraph_label"):
		var label: String = boss.telegraph_label(kind)
		if label != "":
			# 예고(0.5~1.2초) 동안 다 보이게 조금 길게 (0.8초면 긴 예고의 끝 무렵엔 이미 옅어져 있었다 — v1.1.0 검수)
			hud.flash(label, TELEGRAPH_LABEL_TIME)
		if kind != "rise":
			return
	match kind:
		# 가드 불가는 붉은 예고 빛으로 알린다 (설명 글자는 넣지 않는다 — 2026-10-18 기획자 결정)
		"wind": hud.flash("날갯바람!")
		"slam": hud.flash("내려찍기!")
		"wall": hud.flash("뿌리 벽!")
		"rise":
			hud.show_message("뿌리지기가 다시 일어선다…", 3.0)
			# 2페이즈 곡이 터진다 (기획서 10장)
			if boss_track_2 != "":
				Music.play(boss_track_2, 0.6, true)


## 지도 탐사 요소: 이 방의 지역 보스 (정화해야 '모두 찾음' — v1.1.0 기획자 요청 24). Room._collect_explore_ids 가 부른다.
func _boss_flags() -> Array:
	return [defeat_flag] if defeat_flag != "" else []


## 쓰러졌다 (v1.1.0, D10). 2.6초 뒤:
## 1) 보스가 이미 쓰러져 정화를 기다리면 승리를 지킨다 — 문만 열고 이 방의 마지막 자리에서 일어나 다시 손을 얹으러 온다.
## 2) 그 밖에는 마지막으로 쉰 달빛풀의 방을 다시 읽는다 (Room._respawn_at_last_grass) — 이 방이면 보스가 완전히 새로 만들어져
##    싸움이 처음 상태로 돌아간다 (잎 더미·연속 공격 단계·투사체까지).
## 3) 쉰 달빛풀이 없으면 이 방을 다시 읽어 들어온 자리에서 일어난다 (Room._reload_here — 역시 싸움이 처음 상태로).
##    다시 읽을 수 없을 때(시험이 방을 자식으로 놓았을 때 등)만 예전처럼 이 자리에서 싸움을 되돌린다.
func _on_player_died() -> void:
	if _rush:
		_rush_player_died()
		return
	await get_tree().create_timer(2.6).timeout
	if player == null or not is_instance_valid(player):
		return
	if _boss_is_down():
		Progress.clear_killed()
		respawn_enemies()
		gate_in.open()
		gate_out.open()
		_clear_hostile_projectiles()
		player.revive(rest_point)
		var cam0 := player.get_node_or_null("Camera2D")
		if cam0:
			cam0.reset_smoothing()
		return
	if _respawn_at_last_grass():
		return
	if not Progress.has(defeat_flag) and is_instance_valid(boss) and _reload_here():
		return
	Progress.clear_killed()
	respawn_enemies()
	if is_instance_valid(boss):
		boss.reset_fight()
	fight_started = false
	gate_in.open()
	gate_out.open()
	boss_hud.hide_boss()
	_set_battle_camera(false)
	Music.play_region(region, room_id)
	for p in get_tree().get_nodes_in_group("projectile"):
		p.queue_free()
	player.revive(rest_point)
	var cam := player.get_node_or_null("Camera2D")
	if cam:
		if cam.has_method("clear_focus"):
			cam.clear_focus()
		cam.reset_smoothing()


## 싸움 중에는 조금 멀리서, 위쪽을 더 보여 준다.
func _set_battle_camera(on: bool) -> void:
	if player:
		player.boss_fight = on   # 보스전 동안 맞은 뒤 무적이 짧다 (Player.invuln_time_boss — 맞딜 방지)
	var cam := player.get_node_or_null("Camera2D") if player else null
	if cam == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(cam, "zoom", Vector2(0.88, 0.88) if on else Vector2(cam.base_zoom, cam.base_zoom), 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(cam, "vertical_offset", -260.0 if on else -110.0, 1.2).set_trans(Tween.TRANS_SINE)
	# 레터박스 띠가 화면 아래를 가리므로 바닥이 띠 위에 오게 아래 경계를 맞춘다
	if on and cam.has_method("keep_floor_above"):
		var ground_y: float = $Markers/GroundLine.position.y
		cam.keep_floor_above(ground_y, boss_hud.band_full_px(), 0.88)
	elif cam.has_method("restore_bounds"):
		cam.restore_bounds()


## 보스가 쓰러져(FALLEN) 정화를 기다리는 중인가
func _boss_is_down() -> bool:
	return is_instance_valid(boss) and boss.has_method("state_name") and boss.state_name() == "FALLEN"


## 날아가던 보스 쪽 투사체(잎·깃털·불꽃·수액 등)를 모두 거둔다. 소녀 것은 그대로.
func _clear_hostile_projectiles() -> void:
	for p in get_tree().get_nodes_in_group("projectile"):
		if not is_instance_valid(p) or p.get("from_player") == true or p.get("_dead") == true:
			continue
		if p.has_method("_vanish"):
			p._vanish()
		else:
			p.queue_free()


func _on_boss_fallen() -> void:
	if _rush:
		_rush_boss_fallen()
		return
	# 쓰러뜨린 뒤 남은 잎·깃털에 소녀가 쓰러지면 싸움이 처음으로 돌아가 승리가 사라졌다 (2026-10-19 검수: 새·펌프·여왕) → 모두 거둔다
	_clear_hostile_projectiles()
	Sfx.play("boss_fall", 0.0, 0.0)
	Music.stop(0.4)   # 보스곡이 끊기고 정적
	boss_hud.hide_bar()   # 막대만 사라지고 띠는 정화의 손길까지 남는다
	_set_battle_camera(false)
	var hud := get_node_or_null("CombatHUD")
	if hud:
		hud.show_message(fallen_message, 3.0)


## 보스의 빛 가루: 처음 정화할 때 한 번만 보스 자리에서 흩뿌린다. 돌려주는 값은 뿌린 양 (이미 받았으면 0).
func _drop_boss_dust() -> int:
	var flag := "dust_" + defeat_flag
	if _rush:
		return 0   # 보스 러시에는 보상이 없다
	if dust_reward <= 0 or Progress.has(flag) or boss == null or not is_instance_valid(boss):
		return 0
	Progress.set_flag(flag)
	Dust.burst(self, boss.global_position, dust_reward, player)
	return dust_reward


func _on_boss_purified() -> void:
	if _rush:
		return   # 보스 러시: 정화의 손길을 얹어도 깃발·회상 없이 그대로 (다음 방으로는 저절로 넘어간다)
	_drop_boss_dust()
	Progress.set_flag(defeat_flag)
	Purity.regions[region] = true
	Progress.next_spawn = "AfterBoss"
	Progress.pending_memory = memory_id
	Progress.memory_return_scene = scene_file_path
	# 새가 빛이 되어 흩어지고, 레터박스 띠가 천천히 내려가며 회상으로 이어진다
	boss_hud.lower_band(1.8)
	var tw := create_tween()
	tw.tween_property(boss, "modulate", Color(3, 3, 3, 0), 1.6)
	await get_tree().create_timer(1.8).timeout
	Game.go_to(Game.MEMORY_SCENE, 1.2, 1.0)


## 회상에서 돌아온 뒤: 영혼이 소녀에게 깃들고, 수관에 색이 돌아오고, 능력을 얻는다.
func _after_memory() -> void:
	gate_in.open()
	gate_out.open()
	Purity.regions[region] = false
	Purity.apply_region(region)
	await get_tree().create_timer(1.4).timeout
	if player == null:
		return
	player.input_enabled = false
	# 빛 구슬이 하늘에서 내려와 소녀의 가슴에 깃든다
	var orb := Sprite2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.75, 0.9, 0.8, 0.6), Color(0.6, 0.9, 0.7, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 128
	gt.height = 128
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	orb.texture = gt
	orb.modulate = Color(2.0, 2.4, 2.0, 1.0)
	add_child(orb)
	orb.global_position = player.global_position + Vector2(0, -700)
	var tw := create_tween()
	tw.tween_property(orb, "global_position", player.global_position + Vector2(0, -12), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	Juice.hitstop(0.12, 0.02)
	Juice.rumble(0.4, 0.8, 0.4)
	Juice.shake(6.0)
	Sfx.play("soul", 0.0, 0.0)
	orb.queue_free()
	for a in abilities:
		Progress.gain_ability(a)
	var tk := Progress.grant_boss_tokens(defeat_flag)   # v1.1.0: 보스 첫 정화의 새순 (한 번만, 러시 제외)
	purify_from(player.global_position)
	var hud := get_node_or_null("CombatHUD")
	if hud:
		var msg := reward_message
		if msg != "" and tk > 0:
			msg += "  ·  새순 +%d" % tk
		hud.show_message(msg, 4.5)
	if final_boss and has_node("Choices"):
		$Choices.visible = true
		for c in $Choices.get_children():
			c.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().create_timer(3.6).timeout
	player.input_enabled = true


# ---------- 보스 러시 모드 ----------

## 러시로 들어왔다: 소녀를 싸움터 문 안쪽 바닥에 세운다 (BossRoom._process 가 곧바로 싸움을 건다), 러시 시계를 띄운다.
func _rush_setup() -> void:
	var i := BossRush.index_of_scene(scene_file_path)
	# 보스마다 가득 찬 채로: 체력·이슬·가드는 소녀가 새로 만들어지며 채워지고, 영혼 기술 쿨다운도 비운다
	# (러시용 사전이라 떼어 둔 진행에는 닿지 않는다)
	Progress.soul_cooldowns.clear()
	if player:
		var at := Vector2(BossRush.start_x(i), $Markers/GroundLine.position.y - BossRush.FOOT_OFFSET)
		player.position = at
		player.velocity = Vector2.ZERO
		player.facing = 1
		player.last_safe_position = at
		rest_point = at
		_spawn = at
		var cam := player.get_node_or_null("Camera2D")
		if cam:
			cam.reset_smoothing()
	if get_node_or_null("BossRushHUD") == null:
		var hud := BossRushHUD.new()
		hud.name = "BossRushHUD"
		add_child(hud)


## 등장 연출을 짧게 (여왕·펌프는 곡의 박자에 맞추므로 그대로 — BossRush.BOSSES 의 intro)
func _rush_shorten_intro() -> void:
	var t := BossRush.intro_time(BossRush.index_of_scene(scene_file_path))
	if t <= 0.0 or not is_instance_valid(boss) or not ("_timer" in boss):
		return
	if boss.has_method("state_name") and boss.state_name() == "INTRO":
		boss.set("_timer", minf(float(boss.get("_timer")), t))


## 러시: 보스가 쓰러졌다 → 기록 → 숨 고르기 → 보스가 빛으로 흩어짐 → 다음 보스 방 (마지막이면 결과 화면).
func _rush_boss_fallen() -> void:
	_clear_hostile_projectiles()
	Sfx.play("boss_fall", 0.0, 0.0)
	Music.stop(0.4)
	boss_hud.hide_bar()
	_set_battle_camera(false)
	var split := BossRush.boss_down()
	if player and is_instance_valid(player):
		player._invuln_timer = 999.0   # 다음 방으로 넘어갈 때까지 다치지 않는다
	var hud := get_node_or_null("CombatHUD")
	if hud:
		hud.show_message(BossRush.text("fallen", {"time": BossRush.format_time(split)}), BossRush.ADVANCE_BEAT + BossRush.ADVANCE_FADE)
	# 일시정지 중에는 기다리지 않는다 (멈춘 채 장면이 바뀌지 않게). 타이머는 이 방의 함수에 묶는다 — 그사이 '포기하기'로
	# 방이 사라지면 연결도 함께 사라진다 (await 로 기다리면 사라진 방에서 다시 깨어나려 한다)
	get_tree().create_timer(BossRush.ADVANCE_BEAT, false).timeout.connect(_rush_fade_out)


func _rush_fade_out() -> void:
	boss_hud.lower_band(BossRush.ADVANCE_FADE)
	if is_instance_valid(boss):
		var tw := create_tween()
		tw.tween_property(boss, "modulate", Color(3, 3, 3, 0), BossRush.ADVANCE_FADE)
	get_tree().create_timer(BossRush.ADVANCE_FADE, false).timeout.connect(_rush_next)


func _rush_next() -> void:
	BossRush.advance()


## 러시: 소녀가 쓰러졌다 → 결과 화면 (어디까지 왔는지, 시간). 보스를 이미 쓰러뜨려 넘어가는 중이면 그대로 넘어간다.
func _rush_player_died() -> void:
	if BossRush.advancing:
		return
	BossRush.running = false
	get_tree().create_timer(2.6, false).timeout.connect(_rush_dead_result)


func _rush_dead_result() -> void:
	BossRush.finish("dead")


## 시험용 (tools/probe_bossrush): 보스를 곧바로 쓰러뜨린다. 싸움이 아직이면 먼저 건다. 등장·무너짐처럼 맞지 않는 순간은 지나길 기다린다.
func debug_force_defeat() -> void:
	if not is_instance_valid(boss):
		return
	if not fight_started and player:
		_on_trigger(player)
	var tries := 0
	while is_instance_valid(boss) and boss.state_name() != "FALLEN" and tries < 900:
		boss.hp = 1.0
		boss.receive_hit(HitData.make(500.0, 0.0, player), null)
		await get_tree().physics_frame
		tries += 1


## Claude Code용 자동 시험: 싸움을 걸고 상태 흐름을 찍는다.
func _bosstest() -> void:
	var tree := get_tree()
	boss.debug_log = true
	await tree.create_timer(0.6).timeout
	# 머무는 자리 700 아래, 단 바닥선(GroundLine)보다 깊지 않게 (머무는 자리를 낮춰도 바닥 속에 묻히지 않게)
	var hc: Vector2 = $Markers/HoverCenter.position
	player.global_position = Vector2(hc.x, minf(hc.y + 700.0, $Markers/GroundLine.position.y - 4.0))
	player._invuln_timer = 9999.0
	await tree.create_timer(1.0).timeout
	print("[보스시험] 싸움 시작: %s, 문 닫힘: %s" % [fight_started, gate_in.closed])
	var last := ""
	var t := 0.0
	var shots := {}
	while t < 40.0 and is_instance_valid(boss):
		await tree.create_timer(0.25).timeout
		t += 0.25
		var sname: String = boss.state_name()
		if sname != last:
			print("[보스시험] %5.1f초  %s  (체력 %.0f, 흐트러짐 %.0f, 페이즈 %d, 투사체 %d)" % [t, sname, boss.hp, boss.poise, boss.phase, tree.get_nodes_in_group("projectile").size()])
			last = sname
			if sname in ["LEAF_RAIN", "FEATHERS", "WIND", "EAT", "SWEEP", "PECK", "THRUST", "FLAME", "SLAM", "THROW", "SPIKES", "ORBS", "WALL"] and not shots.has(sname):
				shots[sname] = true
				await tree.create_timer(0.8).timeout
				_save_screenshot("debug_boss_%s_%s.png" % [boss_name, sname.to_lower()])
		# 땅에 있을 때 때려서 흐트러뜨린다 (--far 이면 처음 14초는 멀리서 지켜본다)
		var far := "--far" in OS.get_cmdline_user_args() and t < 14.0
		if far:
			player.global_position = boss.global_position + Vector2(-boss.facing * 650.0, 0)
		elif boss.is_ground() and boss.state_name() != "BROKEN" and boss.state_name() != "FALLEN":
			player.global_position = boss.global_position + Vector2(-boss.facing * 150.0, 0)
			player.facing = boss.facing
			Input.action_press("attack_light")
			await tree.physics_frame
			Input.action_release("attack_light")
		if t > 18.0 and boss.phase == 1:
			boss.hp = boss.max_hp * 0.45
			boss.receive_hit(HitData.make(1.0, 0.0, player), null)
		if t > 30.0 and boss.state_name() != "FALLEN":
			boss.hp = 1.0
			boss.receive_hit(HitData.make(5.0, 0.0, player), null)
		if boss.state_name() == "FALLEN":
			var waited := 0.0
			while not boss.is_on_floor() and waited < 4.0:
				await tree.create_timer(0.1).timeout
				waited += 0.1
			player.global_position = boss.global_position + Vector2(-boss.facing * 150.0, 0)
			await tree.create_timer(0.5).timeout
			print("[보스시험] 쓰러짐. 상호작용 가능: %s" % player.can_interact)
			_save_screenshot("debug_boss_fallen.png")
			Input.action_press("interact")
			await tree.physics_frame
			Input.action_release("interact")
			await tree.create_timer(1.2).timeout
			print("[보스시험] 정화 뒤 보스 상태: %s, 깃발: %s" % [boss.state_name(), Progress.has(defeat_flag)])
			break
	print("[보스시험] 끝 (%.1f초)" % t)
	await tree.create_timer(4.0).timeout
	_save_screenshot("debug_boss_end.png")
	tree.quit()

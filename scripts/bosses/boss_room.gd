extends Room
class_name BossRoom
## 보스가 있는 방. 안으로 들어서면 문이 닫히고 싸움이 시작된다.
## 정화하면: 회상 → 영혼이 깃듦 → 지역에 색이 돌아옴 → 능력 획득.

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
## 보스를 정화하면 떨어지는 재화 '빛 가루' (2026-10-19 기획자 요청 9번). 처음 한 번만 — 깃발 "dust_<defeat_flag>" 로 막는다.
@export var dust_reward := 200

@onready var boss: Node = $Boss
@onready var gate_in: FogGate = $GateIn
@onready var gate_out: FogGate = $GateOut
@onready var trigger: Area2D = $BossTrigger
@onready var boss_hud = $BossHUD

var fight_started := false


func _ready() -> void:
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
	if Progress.has(defeat_flag):
		boss.queue_free()
		trigger.queue_free()
		if Progress.has("after_" + defeat_flag):
			pass
		else:
			# 회상에서 막 돌아왔다: 영혼이 깃들고 색이 돌아온다
			Progress.set_flag("after_" + defeat_flag)
			_after_memory()
	if "--bosstest" in OS.get_cmdline_user_args():
		_bosstest()


func _process(delta: float) -> void:
	super._process(delta)
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


func _on_boss_telegraph(kind: String) -> void:
	var hud := get_node_or_null("CombatHUD")
	if hud == null:
		return
	# 보스 스크립트가 telegraph_label(kind) 로 글자를 주면 그것을 쓴다 (새 패턴은 보스 쪽만 고치면 된다; "" 이면 글자 없음)
	if is_instance_valid(boss) and boss.has_method("telegraph_label"):
		var label: String = boss.telegraph_label(kind)
		if label != "":
			hud.flash(label)
		if kind != "rise":
			return
	match kind:
		# 가드 불가는 붉은 예고 빛으로 알린다 (설명 글자는 넣지 않는다 — 2026-10-18 기획자 결정)
		"wind": hud.flash("날갯바람!")
		"slam": hud.flash("내려찍기!")
		"wall": hud.flash("뿌리 벽!")
		"rise":
			hud.show_message("뿌리지기가 다시 일어선다…", 3.0)
			# 주제곡이 격렬하게 터진다 (기획서 10장)
			Music.play("theme_battle", 0.6, true)


func _on_player_died() -> void:
	await get_tree().create_timer(2.6).timeout
	if player == null or not is_instance_valid(player):
		return
	respawn_enemies()
	if is_instance_valid(boss):
		boss.reset_fight()
	fight_started = false
	gate_in.open()
	gate_out.open()
	boss_hud.hide_boss()
	_set_battle_camera(false)
	Music.play_region(region)
	for p in get_tree().get_nodes_in_group("projectile"):
		p.queue_free()
	player.revive(rest_point)
	var cam := player.get_node_or_null("Camera2D")
	if cam:
		cam.reset_smoothing()


## 싸움 중에는 조금 멀리서, 위쪽을 더 보여 준다.
func _set_battle_camera(on: bool) -> void:
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


func _on_boss_fallen() -> void:
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
	if dust_reward <= 0 or Progress.has(flag) or boss == null or not is_instance_valid(boss):
		return 0
	Progress.set_flag(flag)
	Dust.burst(self, boss.global_position, dust_reward, player)
	return dust_reward


func _on_boss_purified() -> void:
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
	purify_from(player.global_position)
	var hud := get_node_or_null("CombatHUD")
	if hud:
		hud.show_message(reward_message, 4.5)
	if final_boss and has_node("Choices"):
		$Choices.visible = true
		for c in $Choices.get_children():
			c.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().create_timer(3.6).timeout
	player.input_enabled = true


## Claude Code용 자동 시험: 싸움을 걸고 상태 흐름을 찍는다.
func _bosstest() -> void:
	var tree := get_tree()
	boss.debug_log = true
	await tree.create_timer(0.6).timeout
	player.global_position = $Markers/HoverCenter.position + Vector2(0, 700)
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

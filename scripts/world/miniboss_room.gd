extends Room
class_name MiniBossRoom
## 중간 보스가 있는 숨겨진 방. 들어서면 문이 닫히고 화면 아래에 보스식 체력 바가 뜬다.
## 이기면 깃발이 서고 보상을 받는다. (일반 적과 달리 다시 나타나지 않는다)

@export var boss_name := "잿가지 거인"
@export var defeat_flag := "miniboss_canopy_defeated"
@export var reward_type := "attack"
@export var reward_amount := 0.1
@export var reward_text := "거인의 힘이 검에 깃들었다 — 공격력 +10%"
## 쓰러뜨리면 떨어지는 재화 '빛 가루' (2026-10-19 기획자 요청 9번). 보스 자신의 dust_value 는 0 으로 두고 방이 이만큼 준다 (깃발로 한 번만).
@export var dust_reward := 60

var _boss: EnemyBase
var _started := false
## 보스 씬 경로 (되살아난 보스를 찾을 때)
var _boss_scene := ""


func _ready() -> void:
	super._ready()
	_boss = get_node_or_null("Enemies/MiniBoss")
	if _boss == null or Progress.has(defeat_flag):
		return
	_boss_scene = _boss.scene_file_path
	_bind_boss()
	if "--minitest" in OS.get_cmdline_user_args():
		_minitest()


## 보스 체력 바를 묶고, 쓰러짐을 듣고, 빛 가루는 방이 주도록 보스 몫을 끈다.
func _bind_boss() -> void:
	_boss.dust_value = 0
	$BossHUD.bind(_boss, boss_name)
	if not _boss.died.is_connected(_on_boss_died):
		_boss.died.connect(_on_boss_died)


## 적이 다시 나타날 때(소녀가 쓰러졌다 일어날 때 등) 새로 만든 보스를 다시 묶는다.
## 새 보스의 노드 이름은 'MiniBoss' 가 아니다 (옛 노드가 지워지기를 기다리며 아직 그 이름을 쥐고 있다) → 씬 경로로 찾는다.
func respawn_enemies() -> void:
	super.respawn_enemies()
	_boss = _find_respawned_boss()
	if _boss:
		_bind_boss()


func _find_respawned_boss() -> EnemyBase:
	if _boss_scene == "" or Progress.has(defeat_flag):
		return null
	for c in $Enemies.get_children():
		if c is EnemyBase and not c.is_queued_for_deletion() and c.scene_file_path == _boss_scene:
			return c
	return null


func _process(delta: float) -> void:
	super._process(delta)
	if not _started and _boss and is_instance_valid(_boss) and player and player.global_position.x > $BossTrigger.position.x and not Progress.has(defeat_flag):
		_started = true
		$GateIn.close()
		$BossHUD.show_boss()
		Music.play("boss_bird", 0.8, true)
		Juice.shake(4.0)


func _on_boss_died(_purified: bool) -> void:
	if dust_reward > 0 and is_instance_valid(_boss):
		Dust.burst(self, _boss.global_position + Vector2(0, -_boss.hurt_height * 0.3), dust_reward, player)
	Progress.set_flag(defeat_flag)
	Progress.add_upgrade(reward_type, reward_amount)
	$BossHUD.hide_boss()
	$GateIn.open()
	Music.play_region(region)
	var hud := get_node_or_null("CombatHUD")
	if hud:
		hud.show_message(reward_text, 4.0)


func _on_player_died() -> void:
	await get_tree().create_timer(2.6).timeout
	if player == null or not is_instance_valid(player):
		return
	respawn_enemies()   # 새 보스를 다시 묶는다 (위 respawn_enemies)
	_started = false
	$GateIn.open()
	$BossHUD.hide_boss()
	player.revive(rest_point)
	var cam := player.get_node_or_null("Camera2D")
	if cam:
		cam.reset_smoothing()


## Claude Code용: 중간 보스 흐름을 확인한다.
func _minitest() -> void:
	var tree := get_tree()
	await tree.create_timer(0.6).timeout
	player._invuln_timer = 9999.0
	player.global_position = _boss.global_position + Vector2(-500, 0)
	var last := ""
	var t := 0.0
	var shot := false
	while t < 16.0 and is_instance_valid(_boss):
		await tree.create_timer(0.2).timeout
		t += 0.2
		var sn := _boss.state_name()
		if sn != last:
			print("[중보스] %4.1f초 %s (체력 %.0f, 문 닫힘 %s)" % [t, sn, _boss.hp, $GateIn.closed])
			last = sn
		if _boss.state == EnemyBase.State.STRIKE and not shot:
			shot = true
			await tree.create_timer(0.25).timeout
			_save_screenshot("debug_miniboss_strike.png")
	if is_instance_valid(_boss):
		_boss.hp = 1.0
		_boss.receive_hit(HitData.make(5.0, 0.0, player), null)
		await tree.create_timer(1.0).timeout
	print("[중보스] 깃발 %s, 공격 보상 %s, 소녀 공격 배수 %.2f, 문 열림 %s" % [Progress.has(defeat_flag), Progress.upgrades, player.attack_multiplier, not $GateIn.closed])
	_save_screenshot("debug_miniboss_end.png")
	tree.quit()

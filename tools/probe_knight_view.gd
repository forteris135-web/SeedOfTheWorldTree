extends Node
## 등불 기사의 패턴을 하나씩 걸어 스크린샷을 찍는다 (그림·모션 눈 확인용 — 화면 있는 실행).
## 보스 방(mine_boss)을 띄우고 싸움을 건 뒤, 행진할 때마다 force_attack 으로 패턴을 걸고
## 예비 70% / 타격 직후 / (돌진) 박힘 / (회전) 중간에 screenshots/knight_<패턴>_<때>.png 를 남긴다.
## 화면 없이(--headless) 돌리면 스크린샷 없이 흐름만 찍고 끝난다 (모든 패턴이 타격까지 가면 "실패 0").
## 실행: Godot --path <프로젝트> res://tools/probe_knight_view.tscn
##      (headless) Godot --headless --path <프로젝트> res://tools/probe_knight_view.tscn

const ROOM := "res://scenes/rooms/mine_boss.tscn"
## [패턴 이름, 소녀를 세울 거리(px, 기사 앞), 2페이즈 여부]
const PATTERNS := [
	["THRUST", 330.0, false],
	["FLAME", 620.0, false],
	["SLAM", 420.0, false],
	["WAVE", 700.0, false],
	["COMBO3", 330.0, false],
	["CHARGE", 1100.0, false],
	["THROW", 800.0, true],
	["SPIN", 420.0, true],
	["WAVE", 700.0, true],
]

var _room: Node
var _boss: LanternKnight
var _player: Player
var _fail := 0


func _ready() -> void:
	_room = load(ROOM).instantiate()
	add_child(_room)
	await get_tree().create_timer(0.6).timeout
	_boss = _room.boss
	_player = _room.player
	_player._invuln_timer = 9999.0
	_player.global_position = _room.get_node("Markers/HoverCenter").position + Vector2(0, 700)
	await get_tree().create_timer(0.8).timeout
	print("[knightview] 싸움 시작: %s" % _room.fight_started)
	if not await _until(func() -> bool: return _boss.state == LanternKnight.State.MARCH, 5.0):
		print("[knightview] 행진까지 못 감: %s" % _boss.state_name())
		_fail += 1
	await _shot("knight_march.png")
	for item in PATTERNS:
		await _pattern(item[0], item[1], item[2])
	# 무너짐 (흐트러짐 가득) — 창을 짚고 웅크려 헐떡인다
	if await _until(func() -> bool: return _boss.state == LanternKnight.State.MARCH and _boss.attack_phase == "", 8.0):
		_boss.phase = 1
		_boss.receive_hit(HitData.make(1.0, _boss.max_poise, _player), null)
		await get_tree().create_timer(0.9).timeout
		await _shot("knight_broken.png")
	# 쓰러짐: 한 무릎 → 창에 기댐 → 엎어져 누움 (몇 장)
	await _until(func() -> bool: return _boss.state == LanternKnight.State.MARCH, 6.0)
	_boss.hp = 1.0
	_boss.receive_hit(HitData.make(5.0, 0.0, _player), null)
	await get_tree().create_timer(0.5).timeout
	await _shot("knight_fallen_knee.png")
	await get_tree().create_timer(0.8).timeout
	await _shot("knight_fallen_lean.png")
	await get_tree().create_timer(0.6).timeout
	await _shot("knight_fallen_collapse.png")
	await get_tree().create_timer(1.6).timeout
	await _shot("knight_fallen.png")
	# 정화
	_boss.purified_by(_player)
	await get_tree().create_timer(0.8).timeout
	await _shot("knight_purified.png")
	print("[knightview] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _pattern(name: String, dist: float, phase2: bool) -> void:
	if not await _until(func() -> bool: return _boss.state == LanternKnight.State.MARCH and _boss.attack_phase == "", 8.0):
		print("[knightview] %s: 행진으로 못 돌아옴 (%s)" % [name, _boss.state_name()])
		_fail += 1
		return
	_boss.phase = 2 if phase2 else 1
	_boss.velocity = Vector2.ZERO
	var dir := _boss.facing
	_player.global_position = Vector2(clampf(_boss.global_position.x + dir * dist, _boss.arena.position.x + 80.0, _boss.arena.end.x - 80.0), _boss.ground_y)
	_player.facing = -dir
	_player.velocity = Vector2.ZERO
	await get_tree().physics_frame
	var st: LanternKnight.State = LanternKnight.State[name]
	_boss.force_attack(st)
	var tag := name.to_lower() + ("_p2" if phase2 else "")
	var t0 := Time.get_ticks_msec()
	# 예비 70%
	if await _until(func() -> bool: return _boss.windup_progress >= 0.7 or _boss.attack_phase != "startup", 4.0):
		await _shot("knight_%s_windup.png" % tag)
	# 타격 직후
	if await _until(func() -> bool: return _boss.attack_phase == "active" or _boss.state != st, 4.0):
		await get_tree().create_timer(0.07).timeout
		await _shot("knight_%s_active.png" % tag)
	else:
		print("[knightview] %s: 타격까지 못 감 (%s/%s)" % [name, _boss.state_name(), _boss.attack_phase])
		_fail += 1
	match name:
		"CHARGE":
			if await _until(func() -> bool: return _boss.state == LanternKnight.State.STUCK, 4.0):
				await get_tree().create_timer(0.45).timeout
				await _shot("knight_charge_stuck.png")
			else:
				print("[knightview] 돌진이 박히지 않음 (%s)" % _boss.state_name())
				_fail += 1
		"SPIN":
			await get_tree().create_timer(0.25).timeout
			await _shot("knight_spin_mid.png")
		"COMBO3":
			# 마지막 타(올려치기)의 붉은 예고와 타격
			if await _until(func() -> bool: return _boss.combo_step == 2 and _boss.windup_progress >= 0.6 or _boss.state != st, 4.0):
				await _shot("knight_combo3_red.png")
			if await _until(func() -> bool: return _boss.combo_step == 2 and _boss.attack_phase == "active" or _boss.state != st, 4.0):
				await get_tree().create_timer(0.08).timeout
				await _shot("knight_combo3_upper.png")
		"WAVE":
			await get_tree().create_timer(0.35).timeout
			await _shot("knight_%s_flying.png" % tag)
	print("[knightview] %s%s: %.1f초, 상태 %s, 투사체 %d" % [name, " (2페이즈)" if phase2 else "", (Time.get_ticks_msec() - t0) / 1000.0, _boss.state_name(), get_tree().get_nodes_in_group("projectile").size()])


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return cond.call()


func _shot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return
	# HDR 2D 화면은 선형 부동소수 그림 → sRGB 8비트로 (안 그러면 어둡게 찍힌다)
	var hdr := img.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF, Image.FORMAT_RGBH, Image.FORMAT_RGBF]
	img.convert(Image.FORMAT_RGBA8)
	if hdr:
		img.linear_to_srgb()
	img.save_png(ProjectSettings.globalize_path("res://screenshots/" + file_name))

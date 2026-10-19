extends Node
## 등불 기사 검토 지적 수정 확인 (진짜 보스 방 mine_boss 에서, 화면 없이).
##  A. 2페이즈 '검기 → 돌진' 중 멀리서 날아온 검기를 저스트 가드: 돌진은 끊기지 않고(박힘까지 감), 기사 흐트러짐은 되받은 검기의 +40 만
##  B. 기사가 쓰러지면 날아가던 검기·불꽃이 거둬지고, 그 뒤 소녀가 쓰러져도 보스가 되살아나지 않는다
##  C. 2페이즈 찌르기를 저스트 가드로 튕기면 연계(검기) 없이 행진으로
##  D. 안개 문 앞에서 쓴 검기가 문 너머에서 생기지 않는다
##  E. 높은 가지(Branch3) 위에서 버티면 1페이즈에도 검기가 소녀 쪽으로 올라온다 (30초에 두 번 넘게 맞는다)
##  F. 공격 없이 몸만 틀 때 궤적(빛의 띠) 점이 생기지 않는다
##  G. 창끝이 땅에 파묻히지 않는다(3연격 둘째·셋째 타, 돌진), 찌르기 창끝이 판정 끝에서 크게 벗어나지 않는다
## 실행: Godot --headless --path . res://tools/probe_knight_fix.tscn

const ROOM := "res://scenes/rooms/mine_boss.tscn"
var _room: Node
var _boss: LanternKnight
var _player: Player
var _vis: Node
var _fail := 0
var _hits: Array = []


func _ready() -> void:
	Engine.max_fps = 60
	_room = load(ROOM).instantiate()
	add_child(_room)
	await get_tree().create_timer(0.6).timeout
	_boss = _room.boss
	_player = _room.player
	_vis = _boss.get_node("Sprite")
	_player.hit_taken.connect(func(d: float) -> void: _hits.append([_boss.state_name(), d]))
	_player._invuln_timer = 9999.0
	_player.global_position = _room.get_node("Markers/HoverCenter").position + Vector2(0, 700)
	await get_tree().create_timer(0.8).timeout
	await _until(func() -> bool: return _boss.state == LanternKnight.State.MARCH, 5.0)
	print("[knightfix] 싸움 시작: %s, 기사 %s" % [_room.fight_started, _boss.state_name()])
	await _a()
	await _c()
	await _d()
	await _f()
	await _g()
	await _e()
	await _b()
	print("[knightfix] 끝: 실패 %d" % _fail)
	get_tree().quit(_fail)


func _check(ok: bool, line: String) -> void:
	print("[knightfix] %s → %s" % [line, "OK" if ok else "틀림!"])
	if not ok:
		_fail += 1


func _calm() -> void:
	_boss.hitbox.deactivate()
	_boss._set_state(LanternKnight.State.MARCH)
	_boss._timer = 99.0
	_boss.velocity = Vector2.ZERO
	_boss.anim_hint = ""
	_boss._high_time = 0.0
	for p in get_tree().get_nodes_in_group("projectile"):
		p.queue_free()
	for a in ["guard", "dodge", "jump", "move_left", "move_right", "move_down"]:
		Input.action_release(a)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _place(bx: float, px: float, phase: int) -> void:
	_boss.phase = phase
	_boss.hp = _boss.max_hp if phase == 1 else _boss.max_hp * 0.4
	_boss.poise = 0.0
	_boss.global_position = Vector2(bx, _boss.ground_y)
	_boss.facing = -1 if px < bx else 1
	_boss.velocity = Vector2.ZERO
	_player.global_position = Vector2(px, _boss.ground_y - 67.0)
	_player.facing = 1 if px < bx else -1
	_player.velocity = Vector2.ZERO
	_player.hp = _player.max_hp
	_player.guard = _player.max_guard
	_player._invuln_timer = 0.0
	_player._set_state(Player.State.IDLE)
	await get_tree().create_timer(0.3).timeout


## A. 2페이즈 검기 → 돌진: 멀리서 날아온 땅 검기를 저스트 가드해도 돌진은 계속되고 박힌다. 흐트러짐은 +40 (되받은 검기)만.
func _a() -> void:
	await _calm()
	await _place(3000.0, 1250.0, 2)
	_boss.force_attack(LanternKnight.State.WAVE)
	await _until(func() -> bool: return not get_tree().get_nodes_in_group("projectile").is_empty(), 3.0)
	var ground: Node = null
	for w in get_tree().get_nodes_in_group("projectile"):
		if absf(w.direction.y) < 0.01:
			ground = w
	await _until(func() -> bool: return _boss.state != LanternKnight.State.WAVE, 3.0)
	if _boss.state != LanternKnight.State.CHARGE:
		_boss.force_attack(LanternKnight.State.CHARGE)
	await _until(func() -> bool: return not is_instance_valid(ground) or ground.global_position.x - _player.global_position.x < 110.0, 3.0)
	var st_before := "%s/%s" % [_boss.state_name(), _boss.attack_phase]
	var poise0 := _boss.poise
	Input.action_press("guard")
	await _until(func() -> bool: return not is_instance_valid(ground) or ground.from_player, 0.5)
	var refl: bool = is_instance_valid(ground) and ground.from_player
	await get_tree().physics_frame
	var guard_gain := _boss.poise - poise0
	var hint_after := _boss.anim_hint
	Input.action_release("guard")
	_player._invuln_timer = 9999.0   # 돌진 창에 맞아 넘어지는 건 이 시험과 상관없다
	var stuck := await _until(func() -> bool: return _boss.state == LanternKnight.State.STUCK, 4.0)
	var total_gain := _boss.poise - poise0
	_check(refl and hint_after != "stagger" and is_equal_approx(guard_gain, 0.0) and stuck and is_equal_approx(total_gain, 40.0),
		"A 검기→돌진 중 원거리 검기 저스트 가드: 막을 때 기사 %s, 되받음 %s, 막는 순간 흐트러짐 +%.0f(0), 힌트 '%s'(stagger 아님), 돌진이 박힘까지 %s, 흐트러짐 합계 +%.0f(40)" % [
			st_before, refl, guard_gain, hint_after, stuck, total_gain])
	_player._invuln_timer = 0.0
	await _calm()


## C. 2페이즈 찌르기를 저스트 가드로 튕기면(창 Hitbox 가 just_guard) 휘청 뒤 행진 — 검기 연계 없음
func _c() -> void:
	var chained := 0
	var hinted := 0
	for i in 20:
		await _calm()
		await _place(2000.0, 1700.0, 2)
		_player._invuln_timer = 9999.0
		_boss.force_attack(LanternKnight.State.THRUST)
		await _until(func() -> bool: return _boss.attack_phase == "active", 2.0)
		_boss.on_just_guarded(_player, 0.0)
		_boss.hitbox.landed.emit("just_guard", _player)
		if _boss.anim_hint == "stagger":
			hinted += 1
		await _until(func() -> bool: return _boss.state != LanternKnight.State.THRUST, 3.0)
		if _boss.state == LanternKnight.State.WAVE:
			chained += 1
	_check(hinted == 20 and chained == 0, "C 2페이즈 찌르기 저스트 가드: 창 튕김 %d/20, 곧바로 검기로 이어짐 %d/20(0)" % [hinted, chained])
	_player._invuln_timer = 0.0
	await _calm()


## D. 왼쪽 안개 문(x 670~730) 바로 앞에서 쓴 검기는 문 안쪽에서 생긴다
func _d() -> void:
	await _calm()
	_boss.phase = 1
	_player._invuln_timer = 9999.0
	_boss.global_position = Vector2(800, _boss.ground_y)
	_boss.facing = -1
	_player.global_position = Vector2(760, _boss.ground_y - 67.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_boss.force_attack(LanternKnight.State.WAVE)
	await _until(func() -> bool: return _boss.attack_phase == "recovery", 3.0)
	var xs: Array = []
	for w in get_tree().get_nodes_in_group("projectile"):
		xs.append(roundf(w.global_position.x))
	var ok := true
	for x in xs:
		if x < 730.0:
			ok = false
	_check(ok, "D 문 앞 검기: 기사 x %.0f, 검기 생긴 자리 %s (문 오른쪽 끝 730 이상이거나 아예 안 생김)" % [_boss.global_position.x, xs])
	_player._invuln_timer = 0.0
	await _calm()


## F. 행진 중 몸만 틀 때(공격 없음) 궤적 점이 생기지 않는다
func _f() -> void:
	await _calm()
	await _place(2000.0, 1400.0, 1)
	_boss._timer = 99.0
	_player._invuln_timer = 9999.0
	await get_tree().create_timer(0.8).timeout
	_player.global_position = Vector2(_boss.global_position.x + 600.0, _boss.ground_y - 67.0)
	var max_pts := 0
	var max_tip := 0.0
	var t := 0.0
	while t < 0.8:
		await get_tree().process_frame
		t += get_process_delta_time()
		max_pts = maxi(max_pts, _vis._trail_pts.size())
		max_tip = maxf(max_tip, _vis._tip_speed)
	_check(max_pts == 0, "F 행진 중 몸 틀기: 창끝 최고 %.0f px/s 인데 궤적 점 최대 %d개(0)" % [max_tip, max_pts])
	_player._invuln_timer = 0.0
	await _calm()


## G. 창끝 자리: 땅(바닥선) 아래로 얼마나 내려가는가, 찌르기 창끝이 판정 끝보다 얼마나 멀리 그려지는가
func _g() -> void:
	var cases := [
		[LanternKnight.State.THRUST, -1, ["active"], "찌르기"],
		[LanternKnight.State.COMBO3, 0, ["active"], "3연격 첫 타"],
		[LanternKnight.State.COMBO3, 1, ["active", "recovery"], "3연격 둘째 타"],
		[LanternKnight.State.COMBO3, 2, ["startup", "active"], "3연격 올려치기"],
		[LanternKnight.State.CHARGE, -1, ["startup", "active"], "돌진"],
	]
	for c in cases:
		await _calm()
		await _place(2600.0, 1300.0, 1)
		_player._invuln_timer = 9999.0
		_boss.force_attack(c[0])
		var below := -INF
		var worst := ""
		var reach := -INF
		var box_end := 0.0
		var t := 0.0
		while t < 6.0 and _boss.state == c[0]:
			await get_tree().process_frame
			t += get_process_delta_time()
			if (c[1] < 0 or _boss.combo_step == c[1]) and _boss.attack_phase in c[2]:
				var tip: Vector2 = _vis._tip_global()
				if tip.y - _boss.ground_y > below:
					worst = "%s t%.2f 몸기울기 %.2f 창 %.2f 맞춤 %.2f 손아귀 y %+.0f" % [_boss.attack_phase, _boss.phase_progress(), _vis.rotation, _vis._weapon_bone.rotation, _vis._level, _vis._weapon_bone.global_position.y - _boss.ground_y]
				below = maxf(below, tip.y - _boss.ground_y)
				reach = maxf(reach, (tip.x - _boss.global_position.x) * float(_boss.facing))
				if _boss.attack_phase == "active" and _boss.hitbox.monitoring:
					var shape: CollisionShape2D = _boss.hitbox.get_child(0)
					var r: RectangleShape2D = shape.shape
					box_end = maxf(box_end, shape.position.x * float(_boss.facing) + r.size.x / 2.0)
		var ok := below <= 12.0
		var extra := ""
		if c[0] == LanternKnight.State.THRUST or (c[0] == LanternKnight.State.COMBO3 and c[1] == 0):
			ok = ok and reach - box_end <= 70.0
			extra = ", 창끝 최대 앞 %.0f / 판정 끝 %.0f (차 %.0f, 70 이하)" % [reach, box_end, reach - box_end]
		_check(ok, "G %s: 창끝이 바닥선 아래로 최대 %+.0fpx(12 이하)%s  [가장 낮을 때: %s]" % [c[3], below, extra, worst])
	_player._invuln_timer = 0.0
	await _calm()


## E. 높은 가지(Branch3, 위 1120) 위 1페이즈 30초: 검기를 소녀 쪽으로 올려 쏴서 두 번 넘게 맞힌다
func _e() -> void:
	await _calm()
	_boss.phase = 1
	_boss.hp = _boss.max_hp
	_boss.poise = 0.0
	_boss.global_position = Vector2(2900, _boss.ground_y)
	var spot := Vector2(2260, 1120 - 70)
	_player.global_position = spot
	_player.velocity = Vector2.ZERO
	_player._invuln_timer = 0.0
	_player.hp = _player.max_hp
	_player._set_state(Player.State.IDLE)
	await get_tree().create_timer(0.5).timeout
	_hits.clear()
	var attacks := {}
	var cb := func(st) -> void:
		var n: String = LanternKnight.State.keys()[st]
		if st in LanternKnight.ATTACK_STATES:
			attacks[n] = attacks.get(n, 0) + 1
	_boss.state_changed.connect(cb)
	_boss._timer = 0.3
	var t := 0.0
	var knocked := 0
	while t < 30.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if _player.hp < 40.0:
			_player.hp = _player.max_hp
		if _player.global_position.y > 1120 and _player.is_on_floor():
			knocked += 1
			_player.global_position = spot
			_player.velocity = Vector2.ZERO
			await get_tree().physics_frame
	_boss.state_changed.disconnect(cb)
	var total := 0.0
	var by := {}
	for h in _hits:
		total += h[1]
		by[h[0]] = by.get(h[0], 0.0) + h[1]
	_check(_hits.size() >= 2 and by.has("WAVE"), "E 높은 가지 1페이즈 30초: 맞은 횟수 %d(2 이상), 피해 %.0f, 공격별 피해 %s, 떨어짐 %d, 기사가 쓴 패턴 %s" % [
		_hits.size(), total, by, knocked, attacks])
	await _calm()


## B. 검기가 날아가는 중에 기사가 쓰러지면 검기가 거둬지고, 소녀가 그 뒤 쓰러져도 보스는 쓰러진 채로 남는다
func _b() -> void:
	await _calm()
	await _place(2000.0, 1000.0, 1)
	_player._invuln_timer = 0.0
	_player.hp = 10.0
	_boss.force_attack(LanternKnight.State.WAVE)
	await _until(func() -> bool: return not get_tree().get_nodes_in_group("projectile").is_empty(), 3.0)
	_boss.hp = 1.0
	_boss.receive_hit(HitData.make(5.0, 0.0, _player), null)
	await get_tree().create_timer(0.3).timeout
	var live := 0
	for p in get_tree().get_nodes_in_group("projectile"):
		if is_instance_valid(p) and not p._dead:
			live += 1
	await get_tree().create_timer(2.5).timeout
	var player_hp := _player.hp
	await get_tree().create_timer(1.0).timeout
	_check(_boss.state == LanternKnight.State.FALLEN and live == 0 and player_hp > 0.0,
		"B 쓰러짐 뒤 투사체: 살아 있는 검기 %d(0), 소녀 체력 %.0f(그대로), 3.8초 뒤 보스 %s(FALLEN)" % [live, player_hp, _boss.state_name()])


func _until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return true
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	return cond.call()

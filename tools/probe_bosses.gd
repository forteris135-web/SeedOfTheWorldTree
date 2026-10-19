extends Node
## 보스 그림 움직임 수치 검사 (화면 없이).
## 보스 씬을 띄우되 엔진의 자동 처리는 끄고, 내가 1/60초씩 _physics_process / _process 를 직접 불러
## 공격 한 사이클(예비 → 타격 → 되돌림 → 복귀) 동안 그림의 기울기·배율·세로 위치가 프레임 사이에 얼마나 뛰는지 찍는다.
## 또 타격 정점(가장 앞으로 기운 순간)이 히트박스가 켜지는 순간(on_active) 뒤 얼마에 오는지 적는다.
## 실행: godot --headless --path <프로젝트> res://tools/probe_bosses.tscn
## (-s 스크립트로는 자동 로드 Juice 등이 안 떠서 보스 스크립트가 컴파일되지 않는다 → 작은 씬으로 띄운다)
## 기준: 프레임 간 기울기 변화 < 0.2rad(11°), 배율 변화 < 0.1, 세로 위치 변화 < 32px 이면 "이어진다"고 본다.
## (예전 코드는 경계에서 세로 94px·배율 0.3 이 한 프레임에 뛰었다. 타격은 의도적으로 빠르므로 0.1~0.16rad/프레임은 정상.)

const DT := 1.0 / 60.0
var KNIGHT: PackedScene
var ROOT: PackedScene
var BIRD: PackedScene
var PLAYER: PackedScene

var _fail := 0


func _ready() -> void:
	# 바닥: 보스가 서 있어야 내려찍기 도약(is_on_floor)·돌진 박힘이 돈다 (정적 몸은 물리 한 틱 뒤에 공간에 들어간다)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var fs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(6000, 200)
	fs.shape = rect
	floor_body.add_child(fs)
	floor_body.position = Vector2(1200, 1100)
	add_child(floor_body)   # (루트에 더하면 루트가 아직 자식을 세우는 중이라 실패한다)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[probe] 시작")
	KNIGHT = load("res://scenes/bosses/lantern_knight.tscn")
	ROOT = load("res://scenes/bosses/root_keeper.tscn")
	BIRD = load("res://scenes/bosses/gray_leaf_bird.tscn")
	PLAYER = load("res://scenes/player/player.tscn")
	_knight()
	_root_keeper()
	_bird()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _spawn(scene: PackedScene) -> Array:
	var boss := scene.instantiate()
	get_tree().root.add_child(boss)
	# 엔진의 자동 호출은 끄고 내가 직접 1/60초씩 부른다 (process_mode 를 끄면 물리 공간에서도 빠지므로 이렇게)
	boss.set_physics_process(false)
	boss.set_process(false)
	boss.visible = true
	boss.arena = Rect2(0, 0, 2400, 1200)
	boss.ground_y = 1000.0
	boss.global_position = Vector2(1200, 1000)
	var vis: Sprite2D = boss.get_node("Sprite")
	vis.set_process(false)
	return [boss, vis]


## 한 사이클을 돌리며 그림 값을 기록한다. done 은 끝났는지 알려 주는 콜러블.
## 돌려주는 값: {max_rot, max_sx, max_sy, max_dy, peak_t, active_t, frames, states}
func _run(boss: Node, vis: Sprite2D, done: Callable, max_time := 6.0, each: Callable = Callable()) -> Dictionary:
	var prev_rot := vis.rotation
	var prev_scale := vis.scale
	var prev_y := vis.position.y
	var r := {"max_rot": 0.0, "max_sx": 0.0, "max_sy": 0.0, "max_dy": 0.0, "peak_t": -1.0, "active_t": -1.0, "frames": 0, "states": [], "at": {},
		"max_wrot": 0.0, "wrot_min": INF, "wrot_max": -INF, "actives": 0}
	var t := 0.0
	var peak := -INF
	var last_state := -1
	var last_phase := ""
	var bone: Node2D = vis.get("_weapon_bone") if "_weapon_bone" in vis else null
	var prev_wrot: float = bone.rotation if bone else 0.0
	while t < max_time:
		boss._physics_process(DT)
		vis._process(DT)
		if each.is_valid():
			each.call(t)
		t += DT
		r.frames += 1
		if bone:
			r.max_wrot = maxf(r.max_wrot, absf(bone.rotation - prev_wrot))
			r.wrot_min = minf(r.wrot_min, bone.rotation)
			r.wrot_max = maxf(r.wrot_max, bone.rotation)
			prev_wrot = bone.rotation
		if boss.state != last_state:
			last_state = boss.state
			r.states.append("%.2f %s" % [t, boss.state_name()])
		if "attack_phase" in boss and boss.attack_phase != last_phase:
			last_phase = boss.attack_phase
			if last_phase == "active":
				r.actives += 1
				if r.active_t < 0.0:
					r.active_t = t
		var d_rot := absf(vis.rotation - prev_rot)
		var d_sx := absf(absf(vis.scale.x) - absf(prev_scale.x))
		var d_sy := absf(vis.scale.y - prev_scale.y)
		var d_y := absf(vis.position.y - prev_y)
		if d_rot > r.max_rot: r.max_rot = d_rot; r.at["rot"] = "%.2f %s/%s" % [t, boss.state_name(), boss.attack_phase if "attack_phase" in boss else ""]
		if d_sx > r.max_sx: r.max_sx = d_sx; r.at["sx"] = "%.2f %s" % [t, boss.state_name()]
		if d_sy > r.max_sy: r.max_sy = d_sy; r.at["sy"] = "%.2f %s" % [t, boss.state_name()]
		if d_y > r.max_dy: r.max_dy = d_y; r.at["dy"] = "%.2f %s" % [t, boss.state_name()]
		# 앞으로 기운 정도 (바라보는 방향 기준)
		var fwd := vis.rotation * float(boss.facing)
		if fwd > peak:
			peak = fwd
			r.peak_t = t
		prev_rot = vis.rotation
		prev_scale = vis.scale
		prev_y = vis.position.y
		if done.call():
			break
	r["peak_rot"] = peak
	return r


func _report(label: String, r: Dictionary, rot_lim := 0.2, scale_lim := 0.1, dy_lim := 32.0) -> void:
	var ok: bool = r.max_rot < rot_lim and r.max_sx < scale_lim and r.max_sy < scale_lim and r.max_dy < dy_lim
	print("[probe] %s: 프레임 %d, 프레임 간 최대 변화 — 기울기 %.3f(%s)  배율x %.3f(%s)  배율y %.3f(%s)  세로 %.1fpx(%s)  → %s" % [
		label, r.frames, r.max_rot, r.at.get("rot", ""), r.max_sx, r.at.get("sx", ""), r.max_sy, r.at.get("sy", ""), r.max_dy, r.at.get("dy", ""), "이어짐" if ok else "끊김!"])
	if r.active_t >= 0.0 and r.peak_rot > 0.05:
		print("[probe]    히트박스 켜짐 %.3f초, 가장 앞으로 기운 순간 %.3f초 (정점 %.2frad, 켜진 뒤 %+.3f초)" % [r.active_t, r.peak_t, r.peak_rot, r.peak_t - r.active_t])
	print("[probe]    상태: %s" % ", ".join(r.states))
	if not ok:
		_fail += 1


func _knight() -> void:
	var pair := _spawn(KNIGHT)
	var boss = pair[0]
	var vis: Sprite2D = pair[1]
	boss.facing = -1
	boss._set_state(boss.State.MARCH)
	boss._timer = 99.0
	# 체력 1.5배 (2026-10-19 기획자 요청: 1100 → 1650)
	var hp_ok: bool = is_equal_approx(boss.max_hp, 1650.0) and is_equal_approx(boss.hp, 1650.0)
	print("[probe] 기사 체력: max_hp %.0f, hp %.0f → %s" % [boss.max_hp, boss.hp, "1650 OK" if hp_ok else "1650 아님!"])
	if not hp_ok:
		_fail += 1
	# 정지 자세로 안정시키기 (바닥에 선다)
	_run(boss, vis, func() -> bool: return false, 1.0)
	print("[probe] 기사 바닥: is_on_floor %s, y %.1f" % [boss.is_on_floor(), boss.global_position.y])
	if not boss.is_on_floor():
		_fail += 1
	# THRUST 한 사이클 (startup 0.55 → active 0.18 → recovery 0.7 → MARCH)
	boss._begin(boss.State.THRUST, 0.55)
	var r := _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss._timer < 99.0 and boss.attack_phase == "" and _settled(vis), 6.0)
	_check_active_window(r, 0.18)
	_report("기사 THRUST", r)
	_weapon_report("기사 THRUST 창", r, 0.8)
	# SLAM (큰 세로 움직임이 있는 공격)
	boss._timer = 99.0
	boss._red = true
	boss._begin(boss.State.SLAM, 1.0)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 6.0)
	_report("기사 SLAM", r)
	# 2페이즈 전환: SLAM 예고 중간에 체력 절반 아래로 → STAGGER → MARCH
	boss._timer = 99.0
	boss._begin(boss.State.SLAM, 1.0)
	_run(boss, vis, func() -> bool: return false, 0.4)
	boss.hp = boss.max_hp * 0.45
	boss.receive_hit(HitData.make(1.0, 0.0, null), null)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss._timer < 0.1, 4.0)
	_report("기사 2페이즈 전환(SLAM→STAGGER→MARCH)", r)
	# 저스트 가드: THRUST 타격 중 창이 튕김 (1페이즈로 되돌려 둔다 — 2페이즈면 되돌림 끝에 검기로 이어질 수 있다)
	boss.phase = 1
	boss.hp = boss.max_hp
	boss._timer = 99.0
	boss._begin(boss.State.THRUST, 0.55 * 0.75)
	_run(boss, vis, func() -> bool: return boss.attack_phase == "active", 2.0)
	# 창(내 Hitbox)이 저스트 가드에 막힘 = 흐트러짐(on_just_guarded) + Hitbox.landed("just_guard") → 창 튕김
	boss.on_just_guarded(null, 10.0)
	boss.hitbox.landed.emit("just_guard", null)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 4.0)
	_report("기사 저스트 가드 휘청", r)
	# 투사체(출처가 기사인 불꽃 파도 등)를 저스트 가드한 것만으로는 창이 튕기지 않는다 (흐트러짐만)
	boss._timer = 99.0
	boss._begin(boss.State.THRUST, 0.55)
	_run(boss, vis, func() -> bool: return boss.attack_phase == "active", 2.0)
	boss.on_just_guarded(null, 10.0)
	var no_bounce: bool = boss.anim_hint != "stagger" and boss.attack_phase == "active"
	print("[probe] 기사 투사체 저스트 가드: 찌르기 중 창 튕김 없음 %s (힌트 '%s', 단계 %s) → %s" % [no_bounce, boss.anim_hint, boss.attack_phase, "OK" if no_bounce else "틀림!"])
	if not no_bounce:
		_fail += 1
	_run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 4.0)
	boss.poise = 0.0
	# 방향 전환: 몸 틀기 (scale.x 가 한 프레임에 뒤집히지 않는다)
	boss._timer = 99.0
	boss.facing = 1
	var min_abs := INF
	var flipped_frames := 0
	var prev_sx := vis.scale.x
	for i in 60:
		boss._physics_process(DT)
		vis._process(DT)
		min_abs = minf(min_abs, absf(vis.scale.x))
		if absf(vis.scale.x - prev_sx) > 0.2:   # 전체 뒤집기(0.8)의 1/4 넘게 한 프레임에 뛰면 끊김
			flipped_frames += 1
		prev_sx = vis.scale.x
	print("[probe] 기사 방향 전환: 60프레임 동안 |scale.x| 최소 %.3f (0.4 기준), 한 프레임에 0.2 넘게 뛴 횟수 %d → %s" % [min_abs, flipped_frames, "몸 틀기 OK" if flipped_frames == 0 and min_abs < 0.2 else "끊김!"])
	if flipped_frames > 0 or min_abs >= 0.2:
		_fail += 1
	# 다시 1페이즈로 (아래 시험은 1페이즈 길이 기준)
	boss.phase = 1
	boss.hp = boss.max_hp
	# SLAM 웅크림→도약: 예비 앞 30% 동안 그림이 내려앉았다가(아래로), 그 뒤 몸이 진짜 뛰어오르고(위로 60px 넘게), 타격 순간엔 바닥에 돌아와 있다
	boss._timer = 99.0
	boss.facing = -1
	_run(boss, vis, func() -> bool: return false, 1.0)
	# (람다는 지역 실수를 값으로 잡으므로 사전(참조)에 기록한다) — 세로 자리는 몸 + 그림 (몸이 뛰므로 월드 기준)
	var y0: float = boss.global_position.y + vis.position.y
	var c := {"low": -INF, "high": INF, "t_low": 0.0, "t_high": 0.0, "land_dy": INF}
	boss._begin(boss.State.SLAM, 1.0)
	_run(boss, vis, func() -> bool: return boss.attack_phase != "startup", 3.0, func(t: float) -> void:
		var dy: float = boss.global_position.y + vis.position.y - y0
		if dy > c.low:
			c.low = dy; c.t_low = t
		if dy < c.high:
			c.high = dy; c.t_high = t)
	c.land_dy = boss.global_position.y - 1000.0
	var crouch_ok: bool = c.low > 5.0 and c.t_low < 0.5 and c.high < -60.0 and c.t_high > c.t_low and absf(c.land_dy) < 40.0
	print("[probe] 기사 SLAM 웅크림→도약: 예비 중 가장 내려앉음 %+.1fpx(%.2f초) → 가장 솟음 %+.1fpx(%.2f초), 타격 순간 바닥에서 %+.1fpx → %s" % [c.low, c.t_low, c.high, c.t_high, c.land_dy, "웅크림→도약→착지 OK" if crouch_ok else "틀림!"])
	if not crouch_ok:
		_fail += 1
	_run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 6.0)
	_knight_wave(boss, vis)
	_knight_combo(boss, vis)
	_knight_charge(boss, vis)
	_knight_spin(boss, vis)
	_facing_hold(boss, vis, "기사", boss.State.MARCH)
	boss.queue_free()


## 창 움직임: 한 사이클 동안 창(손아귀 축)이 크게 돌고(휘두른 폭 = 최대−최소 각도 ≥ need), 프레임 간 변화는 0.7rad(40°) 아래.
## (큰 휘두르기는 일부러 빠르다 — 3rad 를 8~9프레임에 지난다. 그보다 빠르면 잔상이 있어도 끊겨 보인다.)
func _weapon_report(label: String, r: Dictionary, need: float) -> void:
	var span: float = r.wrot_max - r.wrot_min
	var ok: bool = span >= need and r.max_wrot < 0.7
	print("[probe] %s: 휘두른 폭 %.2frad(%.2f 이상; %.2f~%.2f), 프레임 간 최대 변화 %.3frad(0.7 아래) → %s" % [label, span, need, r.wrot_min, r.wrot_max, r.max_wrot, "휘둘러짐 OK" if ok else "안 움직임/끊김!"])
	if not ok:
		_fail += 1


func _clear_projectiles() -> void:
	for p in get_tree().get_nodes_in_group("projectile"):
		p.get_parent().remove_child(p)
		p.free()


## 검기: 타격 순간 SwordWave 가 생기고(1페이즈 1갈래, 2페이즈 3갈래), 앞으로 날아가며, 저스트 가드로 되받으면 기사에게 돌아가 흐트러짐 +40.
func _knight_wave(boss: Node, vis: Sprite2D) -> void:
	_clear_projectiles()
	boss._timer = 99.0
	boss.facing = -1
	boss.poise = 0.0
	var seen := {"n": 0, "x0": 0.0, "x1": 0.0, "wave": null}
	boss._begin(boss.State.WAVE, 0.65)
	var r := _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 6.0, func(_t: float) -> void:
		var waves := get_tree().get_nodes_in_group("projectile")
		if seen.n == 0 and waves.size() > 0:
			seen.n = waves.size()
			seen.wave = waves[0]
			seen.x0 = waves[0].global_position.x
		if seen.wave != null and is_instance_valid(seen.wave):
			seen.wave._physics_process(DT)
			seen.x1 = seen.wave.global_position.x)
	_report("기사 WAVE", r)
	_weapon_report("기사 WAVE 창", r, 2.0)
	var wave = seen.wave
	var flew: float = seen.x0 - seen.x1
	var ok: bool = seen.n == 1 and wave is SwordWave and flew > 300.0 and r.active_t > 0.6 and r.active_t < 0.7
	print("[probe] 기사 검기(1페이즈): 타격 %.2f초에 검기 %d개(1 기준), 앞으로 %.0fpx 날아감(300 이상) → %s" % [r.active_t, seen.n, flew, "OK" if ok else "틀림!"])
	if not ok:
		_fail += 1
	# 되받기: 진짜 소녀가 검기 앞에서 저스트 가드(가드 상태 + 방금 누름) → player.receive_hit 이 "just_guard" →
	# 기사 쪽으로 방향이 뒤집히고 소녀 공격이 된다. 막는 순간 기사 흐트러짐은 그대로(검기 출처는 검기 자신),
	# 되받은 검기가 기사 맞는 영역에 닿을 때 +40 — 합쳐서 +40.
	if wave is SwordWave:
		var pl: Player = PLAYER.instantiate()
		get_tree().root.add_child(pl)
		pl.set_physics_process(false)
		pl.set_process(false)
		pl.global_position = wave.global_position + Vector2(60.0 * float(boss.facing), 0)   # 검기가 날아가는 쪽 앞
		pl.facing = -boss.facing
		pl._set_state(pl.State.GUARD)
		pl._guard_pressed_at = pl._now()
		var before: float = boss.poise
		wave._hit(pl.hurtbox)
		var guard_gain: float = boss.poise - before
		var to_boss: Vector2 = (boss.global_position + Vector2(0, -150) - wave.global_position).normalized()
		var toward: float = wave.direction.dot(to_boss)
		wave._hit(boss.hurtbox)
		var gained: float = boss.poise - before
		var rok: bool = wave.from_player and (wave.collision_mask & 16) != 0 and toward > 0.9 and is_equal_approx(guard_gain, 0.0) and is_equal_approx(gained, 40.0)
		print("[probe] 기사 검기 되받기(진짜 소녀 저스트 가드): 소녀 공격 %s, 기사 쪽 향함 %.2f(0.9 이상), 막는 순간 흐트러짐 +%.0f(0 기준), 맞혀서 합계 +%.0f(40 기준) → %s" % [wave.from_player, toward, guard_gain, gained, "OK" if rok else "틀림!"])
		if not rok:
			_fail += 1
		pl.queue_free()
	# 2페이즈: 3갈래
	_clear_projectiles()
	boss.phase = 2
	boss._timer = 99.0
	boss._begin(boss.State.WAVE, 0.65 * 0.75)
	_run(boss, vis, func() -> bool: return boss.attack_phase == "recovery", 3.0)
	var n2 := get_tree().get_nodes_in_group("projectile").size()
	print("[probe] 기사 검기(2페이즈): 검기 %d갈래(3 기준) → %s" % [n2, "OK" if n2 == 3 else "틀림!"])
	if n2 != 3:
		_fail += 1
	_run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 4.0)
	boss.phase = 1
	_clear_projectiles()


## 3연격: 타격 창이 세 번 켜지고, 마지막 타만 붉은 예고 + 가드 불가. 타 사이 창 자세가 끊기지 않는다.
func _knight_combo(boss: Node, vis: Sprite2D) -> void:
	boss._timer = 99.0
	boss.facing = -1
	var seen := {"red_steps": [], "unguardable_step": -1, "guardable_steps": []}
	boss.force_attack(boss.State.COMBO3)
	var r := _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 8.0, func(_t: float) -> void:
		if boss.is_red() and not seen.red_steps.has(boss.combo_step):
			seen.red_steps.append(boss.combo_step)
		if boss.attack_phase == "active" and boss.hitbox.hit != null:
			if not boss.hitbox.hit.guardable:
				seen.unguardable_step = boss.combo_step
			elif not seen.guardable_steps.has(boss.combo_step):
				seen.guardable_steps.append(boss.combo_step))
	_report("기사 COMBO3", r)
	_weapon_report("기사 COMBO3 창", r, 2.0)
	var ok: bool = r.actives == 3 and seen.red_steps == [2] and seen.unguardable_step == 2 and seen.guardable_steps == [0, 1]
	print("[probe] 기사 3연격: 타격 %d번(3 기준), 붉은 예고 타 %s([2] 기준), 가드 불가 타 %d(2 기준), 가드 가능 타 %s([0, 1] 기준) → %s" % [
		r.actives, seen.red_steps, seen.unguardable_step, seen.guardable_steps, "OK" if ok else "틀림!"])
	if not ok:
		_fail += 1
	# 저스트 가드로 첫 타가 튕기면 연격이 끊긴다 (타격 한 번뿐)
	boss._timer = 99.0
	boss.force_attack(boss.State.COMBO3)
	_run(boss, vis, func() -> bool: return boss.attack_phase == "active", 2.0)
	boss.on_just_guarded(null, 10.0)
	boss.hitbox.landed.emit("just_guard", null)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 6.0)
	var cut_ok: bool = r.actives == 0 and boss.state == boss.State.MARCH
	print("[probe] 기사 3연격 저스트 가드: 첫 타 튕긴 뒤 추가 타격 %d번(0 기준) → %s" % [r.actives, "끊김 OK" if cut_ok else "안 끊김!"])
	if not cut_ok:
		_fail += 1
	_report("기사 3연격 튕김 휘청", r)
	# 가드 불가 올려치기의 붉은 예고 길이: 1·2페이즈 모두 0.45초 이상 (공통 기준)
	for ph in [1, 2]:
		boss.phase = ph
		boss._timer = 99.0
		boss.poise = 0.0
		var red := {"t": 0.0}
		boss.force_attack(boss.State.COMBO3)
		_run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 8.0, func(_t: float) -> void:
			if boss.is_red():
				red.t += DT)
		var rok: bool = red.t >= 0.45 - 0.001
		print("[probe] 기사 올려치기 붉은 예고(%d페이즈): %.2f초 (0.45 이상) → %s" % [ph, red.t, "OK" if rok else "짧음!"])
		if not rok:
			_fail += 1
	boss.phase = 1


## 돌진 찌르기: 뒤로 물러났다(예비) 아레나를 가로질러 끝에서 창이 박힌다(STUCK 2.0초, 피해 1.3배) → 행진.
## 박힌 동안 무너지면 무너짐은 남은 박힘 시간만큼만 (돌진 한 번에 공짜 시간이 박힘 2초 + 무너짐 4.5초로 이어지지 않게).
func _knight_charge(boss: Node, vis: Sprite2D) -> void:
	boss._timer = 99.0
	boss.facing = -1
	boss.global_position = Vector2(1800, 1000)
	boss.velocity = Vector2.ZERO
	_run(boss, vis, func() -> bool: return false, 0.5)
	var seen := {"back": 0.0, "x_start": boss.global_position.x, "stuck_t": -1.0, "free_t": -1.0, "hb": false}
	boss.force_attack(boss.State.CHARGE)
	var r := _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 8.0, func(t: float) -> void:
		if boss.state == boss.State.CHARGE and boss.attack_phase == "startup":
			seen.back = maxf(seen.back, boss.global_position.x - seen.x_start)
		if boss.state == boss.State.CHARGE and boss.attack_phase == "active" and boss.hitbox._active:
			seen.hb = true
		if boss.state == boss.State.STUCK and seen.stuck_t < 0.0:
			seen.stuck_t = t
		if boss.state == boss.State.MARCH and seen.stuck_t >= 0.0 and seen.free_t < 0.0:
			seen.free_t = t)
	_report("기사 CHARGE→STUCK→MARCH", r)
	var stuck_len: float = seen.free_t - seen.stuck_t
	var x_end: float = boss.global_position.x
	var ok: bool = seen.back > 20.0 and seen.hb and seen.stuck_t > 0.0 and x_end <= 130.0 + 25.0 and absf(stuck_len - 2.0) < 0.05
	print("[probe] 기사 돌진: 예비에 뒤로 %.0fpx 물러남(20 이상), 돌진 중 판정 켜짐 %s, 아레나 끝 x=%.0f(155 이하)에서 박힘 %.2f초 → 풀림 %.2f초 (박힘 %.2f초, 2.0 기준) → %s" % [
		seen.back, seen.hb, x_end, seen.stuck_t, seen.free_t, stuck_len, "OK" if ok else "틀림!"])
	if not ok:
		_fail += 1
	# 박힌 동안 맞으면 피해 1.3배, 흐트러짐은 그대로(1배)
	boss._timer = 99.0
	boss.facing = 1
	boss.global_position = Vector2(600, 1000)
	boss.velocity = Vector2.ZERO
	_run(boss, vis, func() -> bool: return false, 0.5)
	boss.force_attack(boss.State.CHARGE)
	_run(boss, vis, func() -> bool: return boss.state == boss.State.STUCK, 6.0)
	boss.poise = 0.0
	boss.hp = boss.max_hp
	boss.receive_hit(HitData.make(10.0, 10.0, null), null)
	var pm: bool = boss.state == boss.State.STUCK and is_equal_approx(boss.poise, 10.0) and is_equal_approx(boss.max_hp - boss.hp, 13.0)
	print("[probe] 기사 박힘 무방비: 10/10 으로 쳐서 흐트러짐 %.0f(10 기준), 피해 %.0f(13 기준), 상태 %s(STUCK 유지) → %s" % [boss.poise, boss.max_hp - boss.hp, boss.state_name(), "OK" if pm else "틀림!"])
	if not pm:
		_fail += 1
	# 박힌 지 0.5초 뒤 흐트러짐이 가득 차면: 무너짐은 남은 박힘(1.5초)만큼 → 박힘부터 행진까지 2.0초 남짓
	_run(boss, vis, func() -> bool: return false, 0.5)
	var stuck_left: float = boss._timer
	boss.receive_hit(HitData.make(1.0, boss.max_poise, null), null)
	var broke: bool = boss.state == boss.State.BROKEN
	var w := {"t": 0.0}
	_run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH, 8.0, func(_t: float) -> void: w.t += DT)
	var total: float = 0.5 + w.t
	var bok: bool = broke and absf(w.t - stuck_left) < 0.1 and total < 2.7
	print("[probe] 기사 박힘→무너짐: 무너짐 %s, 무너짐 길이 %.2f초(남은 박힘 %.2f초), 박힘부터 무방비 끝까지 %.2f초(2.7 아래) → %s" % [broke, w.t, stuck_left, total, "OK" if bok else "너무 김!"])
	if not bok:
		_fail += 1
	boss.poise = 0.0
	_run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 6.0)
	boss.global_position = Vector2(1200, 1000)
	boss.facing = -1
	boss.poise = 0.0


## 등불 회전 (2페이즈): 창이 세 바퀴 돌고, 타격 중 불꽃 고리 3겹(양쪽 6개)이 낮게 퍼진다. 끝나면 창 각도가 제자리(±π 안)로 접힌다.
func _knight_spin(boss: Node, vis: Sprite2D) -> void:
	_clear_projectiles()
	boss.phase = 2
	boss._timer = 99.0
	_run(boss, vis, func() -> bool: return false, 0.5)
	var bone: Node2D = vis._weapon_bone
	var turns := {"max": 0.0, "n_mid": 0, "times": [], "seen": 0}
	boss.force_attack(boss.State.SPIN)
	var r := _run(boss, vis, func() -> bool: return boss.state == boss.State.MARCH and boss.attack_phase == "", 6.0, func(t: float) -> void:
		turns.max = maxf(turns.max, absf(bone.rotation))
		var n_now := get_tree().get_nodes_in_group("projectile").size()
		if n_now > turns.seen:
			turns.times.append(t)
			turns.seen = n_now)
	var n := get_tree().get_nodes_in_group("projectile").size()
	var low := true
	for p in get_tree().get_nodes_in_group("projectile"):
		if p.global_position.y < 1000.0 - 60.0:
			low = false
	_report("기사 SPIN", r)
	# 고리끼리 간격: 같은 속도라 내보낸 간격(0.38초)이 그대로 거리로 남는다 (뒤 고리가 앞 고리를 따라잡지 않는다)
	var speeds := {}
	for p in get_tree().get_nodes_in_group("projectile"):
		speeds[p.speed] = true
	var gaps: Array = []
	for i in range(1, turns.times.size()):
		gaps.append(snappedf(turns.times[i] - turns.times[i - 1], 0.01))
	var gap_ok: bool = turns.times.size() == 3 and speeds.size() == 1
	for g in gaps:
		if g < 0.3:
			gap_ok = false
	var ok: bool = n == 6 and low and turns.max > 2.5 * TAU and absf(bone.rotation) < PI and boss.rings_sent == 3 and gap_ok
	print("[probe] 기사 등불 회전: 고리 %d개(6 기준), 모두 낮게(바닥 60px 안) %s, 창 누적 회전 %.1f바퀴(2.5 이상), 끝난 뒤 각도 %.2f(π 안), 고리 간격 %s초(0.3 이상)·속도 %d가지(1 기준) → %s" % [
		n, low, turns.max / TAU, bone.rotation, gaps, speeds.size(), "OK" if ok else "틀림!"])
	if not ok:
		_fail += 1
	_clear_projectiles()
	boss.phase = 1


## 소녀가 보스 바로 옆(데드존 안)을 왔다 갔다 해도 몸이 매 프레임 뒤집히지 않는지,
## 멀리(데드존 밖) 넘어가도 최소 유지 시간 안에는 다시 돌지 않는지 센다.
func _facing_hold(boss: Node, vis: Sprite2D, label: String, idle_state: int) -> void:
	var player: Player = PLAYER.instantiate()
	get_tree().root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	boss.player = player
	boss._set_state(idle_state)
	boss._timer = 99.0
	boss.facing = -1
	var flips_near := 0
	var prev: int = boss.facing
	# 1) 데드존 안에서 4프레임마다 좌우 바꿈 (몸을 통과하는 상황) — 1초
	for i in 60:
		player.global_position = boss.global_position + Vector2(20.0 if (i / 4) % 2 == 0 else -20.0, 0)
		boss._physics_process(DT)
		vis._process(DT)
		if boss.facing != prev:
			flips_near += 1
		prev = boss.facing
	# 2) 데드존 밖으로 넘어감 → 한 번 돌고, 0.1초 뒤 반대쪽으로 다시 넘어가도 유지 시간 안에는 안 돈다
	var flips_far := 0
	var first_flip_t := -1.0
	var second_flip_t := -1.0
	for i in 60:
		var t := i * DT
		player.global_position = boss.global_position + Vector2(120.0 if t < 0.1 else -120.0, 0)
		boss._physics_process(DT)
		vis._process(DT)
		if boss.facing != prev:
			flips_far += 1
			if first_flip_t < 0.0:
				first_flip_t = t
			elif second_flip_t < 0.0:
				second_flip_t = t
		prev = boss.facing
	var gap := second_flip_t - first_flip_t if second_flip_t >= 0.0 else INF
	var ok: bool = flips_near == 0 and flips_far >= 1 and gap >= boss.face_hold - 0.02
	print("[probe] %s 방향 유지: 데드존 안 왕복 1초 동안 뒤집힘 %d회(0 기준), 데드존 밖 전환 %d회, 두 전환 간격 %.2f초(%.2f 이상) → %s" % [label, flips_near, flips_far, gap, boss.face_hold, "OK" if ok else "떨림!"])
	if not ok:
		_fail += 1
	boss.player = null
	player.queue_free()


func _settled(vis: Sprite2D) -> bool:
	return absf(vis.rotation) < 0.02


func _check_active_window(r: Dictionary, active_len: float) -> void:
	if r.active_t < 0.0:
		return
	var inside: bool = r.peak_t >= r.active_t - 0.001 and r.peak_t <= r.active_t + active_len + 0.001
	print("[probe]    타격 정점이 히트박스 구간(%.2f~%.2f) 안: %s" % [r.active_t, r.active_t + active_len, "예" if inside else "아니오!"])
	if not inside:
		_fail += 1


func _root_keeper() -> void:
	var pair := _spawn(ROOT)
	var boss = pair[0]
	var vis: Sprite2D = pair[1]
	boss.facing = -1
	boss._set_state(boss.State.STANCE)
	boss._timer = 99.0
	_run(boss, vis, func() -> bool: return false, 1.0)
	# SPIKES (지팡이 들어 올려 내리꽂기, 세로 움직임)
	boss.spike_marks = [1000.0, 800.0]
	boss._begin(boss.State.SPIKES, 0.9)
	var r := _run(boss, vis, func() -> bool: return boss.state == boss.State.STANCE and boss.attack_phase == "", 6.0)
	_report("뿌리지기 SPIKES", r)
	# SWEEP
	boss._timer = 99.0
	boss._begin(boss.State.SWEEP, 0.5)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.STANCE and boss.attack_phase == "", 6.0)
	_check_active_window(r, 0.2)
	_report("뿌리지기 SWEEP", r)
	# 저스트 가드 (SWEEP 타격 중)
	boss._timer = 99.0
	boss._begin(boss.State.SWEEP, 0.5)
	_run(boss, vis, func() -> bool: return boss.attack_phase == "active", 2.0)
	boss.on_just_guarded(null, 10.0)
	# 휘청 보정(stagger)이 힌트가 끝날 때 한 번에 사라지지 않는지: 힌트 끝 전후의 stagger 값 변화를 본다
	var sg := {"before": boss.stagger, "jump": 0.0, "start": boss.stagger}
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.STANCE and boss.attack_phase == "", 6.0, func(_t: float) -> void:
		sg.jump = maxf(sg.jump, absf(boss.stagger - sg.before))
		sg.before = boss.stagger)
	var stag_ok: bool = sg.start >= 0.99 and sg.jump < 0.06 and boss.stagger == 0.0
	print("[probe]    휘청 세기(stagger) 시작 %.2f → 프레임 간 최대 변화 %.3f(0.06 기준, 1→0 서서히) → 끝값 %.2f → %s" % [sg.start, sg.jump, boss.stagger, "서서히 OK" if stag_ok else "툭 사라짐!"])
	if not stag_ok:
		_fail += 1
	_report("뿌리지기 저스트 가드 휘청", r)
	# WALL
	boss._timer = 99.0
	boss._red = true
	boss._begin(boss.State.WALL, 1.1)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.STANCE and boss.attack_phase == "", 6.0)
	_report("뿌리지기 WALL", r)
	# 2페이즈: SPIKES 예고 도중 RISE 로 (쓰러졌다 일어섬; dy 점프 없어야 함)
	boss._timer = 99.0
	boss.spike_marks = [1000.0, 800.0]
	boss._begin(boss.State.SPIKES, 0.9)
	_run(boss, vis, func() -> bool: return false, 0.5)
	boss.hp = boss.max_hp * 0.45
	boss.receive_hit(HitData.make(1.0, 0.0, null), null)
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.STANCE and boss._timer < 0.2, 6.0)
	_report("뿌리지기 2페이즈(SPIKES→RISE→STANCE)", r)
	_facing_hold(boss, vis, "뿌리지기", boss.State.STANCE)
	boss.queue_free()


func _bird() -> void:
	var pair := _spawn(BIRD)
	var boss = pair[0]
	var vis: Sprite2D = pair[1]
	boss.facing = -1
	boss.set_collision_mask_value(1, true)
	boss._set_state(boss.State.GROUND_IDLE)
	boss._timer = 99.0
	_run(boss, vis, func() -> bool: return false, 1.0)
	# SWEEP (날개 휘두르기)
	boss._set_state(boss.State.SWEEP)
	boss._timer = 0.55
	boss._melee_stage = 0
	boss.attack_phase = "startup"
	boss.windup_progress = 0.0
	boss.startup_len = 0.55
	var r := _run(boss, vis, func() -> bool: return boss.state == boss.State.GROUND_IDLE and boss._timer < 0.05, 6.0)
	_check_active_window(r, 0.22)
	_report("새 SWEEP", r)
	# PECK (부리 찍기, 돌진)
	boss._timer = 99.0
	boss._set_state(boss.State.PECK)
	boss._timer = 0.45
	boss._melee_stage = 0
	boss.attack_phase = "startup"
	boss.windup_progress = 0.0
	boss.startup_len = 0.45
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.GROUND_IDLE and boss._timer < 0.05, 6.0)
	_check_active_window(r, 0.3)
	_report("새 PECK", r)
	# 공중: HOVER 에서 WIND 로, 다시 HOVER (날갯짓 위상 연속)
	boss.hover_points = [Vector2(600, 500), Vector2(1200, 500), Vector2(1800, 500)]
	boss._hover_target = Vector2(1200, 500)
	boss.set_collision_mask_value(1, false)
	boss.global_position = Vector2(1200, 520)
	boss._set_state(boss.State.HOVER)
	boss._timer = 99.0
	_run(boss, vis, func() -> bool: return false, 1.0)
	boss._set_state(boss.State.WIND)
	boss._timer = boss.wind_telegraph + boss.wind_time
	r = _run(boss, vis, func() -> bool: return boss.state == boss.State.HOVER, 4.0)
	_report("새 HOVER→WIND→HOVER", r, 0.1, 0.06, 14.0)
	# 날갯바람 끝에서 붉은색이 한 프레임에 돌아오지 않는다
	_bird_shots(boss, vis)
	boss.queue_free()


func _ok(cond: bool, label: String) -> void:
	print("[probe]    %s → %s" % [label, "OK" if cond else "실패!"])
	if not cond:
		_fail += 1


## 2026-10-19 탄막 가시성 + 체력 2배: 깃털·잎의 그림 크기(판정 대비), 테두리·심·발광·꼬리, 붉은 점·흰 띠 예고의 때, 체력 1800.
func _bird_shots(boss: Node, vis: Sprite2D) -> void:
	print("[probe] 새 탄막 가시성·체력")
	_ok(boss.max_hp == 1800.0 and boss.hp == 1800.0, "체력 최대 %.0f / 지금 %.0f (1800 기준)" % [boss.max_hp, boss.hp])
	var player: Player = PLAYER.instantiate()
	get_tree().root.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	boss.player = player
	boss.arena = Rect2(0, 0, 2400, 1200)
	boss.global_position = Vector2(1200, 520)
	boss._hover_target = boss.global_position
	boss.hover_points = [boss.global_position]
	boss.facing = -1
	player.global_position = Vector2(500, 1000)
	for p in get_tree().get_nodes_in_group("projectile"):
		p.free()
	# ---- 깃털: 쏘기 0.3초 전부터 붉은 점이 차오르고, 첫 발 직전엔 거의 1, 3발이 나간다 ----
	boss._set_state(boss.State.HOVER)
	boss._timer = 99.0
	_run(boss, vis, func() -> bool: return false, 0.3)
	boss._set_state(boss.State.FEATHERS)
	boss._timer = 0.6 + 3 * 0.15
	boss._spawned = 0
	boss.telegraph_amount = 0.0
	boss.feather_warn = 0.0
	var fw := {"early": -1.0, "before_first": -1.0, "first_t": -1.0, "flash": 0.0, "muzzle_ok": true}
	_run(boss, vis, func() -> bool: return boss.state == boss.State.HOVER, 3.0, func(t: float) -> void:
		var n := get_tree().get_nodes_in_group("projectile").size()
		if t < 0.25:
			fw.early = maxf(fw.early, boss.feather_warn)
		if n == 0:
			fw.before_first = boss.feather_warn
		elif fw.first_t < 0.0:
			fw.first_t = t
			fw.flash = boss.muzzle_flash
			var p: Projectile = get_tree().get_nodes_in_group("projectile")[0]
			# 붉은 점(muzzle_point)과 깃털이 같은 자리에서 시작한다
			fw.muzzle_ok = p.global_position.distance_to(boss.muzzle_point()) < 2.0 and vis._muzzle.global_position.distance_to(boss.muzzle_point()) < 2.0)
	var feathers: Array = get_tree().get_nodes_in_group("projectile")
	print("[probe]    붉은 점: 0.25초 전 최대 %.2f, 첫 발 직전 %.2f, 첫 발 %.2f초(번쩍 %.2f), 깃털 %d발" % [fw.early, fw.before_first, fw.first_t, fw.flash, feathers.size()])
	_ok(fw.early < 0.05, "쏘기 0.3초 전에는 붉은 점이 없다")
	_ok(fw.before_first >= 0.9, "첫 발 직전 붉은 점이 거의 다 찼다 (≥0.9)")
	_ok(fw.first_t > 0.55 and fw.first_t < 0.7, "첫 발은 예고 0.6초 뒤")
	_ok(fw.flash >= 0.9, "발사 순간 번쩍임")
	_ok(fw.muzzle_ok, "깃털·붉은 점이 부리 앞(muzzle_point)에서 시작")
	_ok(feathers.size() == 3, "1페이즈 깃털 3발")
	boss._timer = 99.0
	_run(boss, vis, func() -> bool: return false, 0.3)   # 상태가 끝난 뒤 0.3초: 붉은 점은 초당 6 으로 사라진다
	_ok(boss.feather_warn < 0.05 and not vis._muzzle.visible, "상태가 끝나고 0.3초면 붉은 점이 사라진다 (%.2f)" % boss.feather_warn)
	if feathers.size() > 0:
		var p: Projectile = feathers[0]
		# 예전 깃털 그림: 가로 size.x, 세로 size.y×0.9 (위 반 + 아래 반×0.8)
		_check_shot(p, "깃털", Vector2(76, 16), 10.0, Vector2(76.0, 16.0 * 0.9))
		_ok(p.core_color.r > 0.9 and p.core_color.g < 0.4, "깃털 심이 붉다 %s" % p.core_color)
		_ok(p.reflectable, "깃털은 되받을 수 있다")
		# 꼬리: 몇 프레임 날아가면 잔상이 쌓인다
		for i in 14:
			p._physics_process(DT)
		print("[probe]    깃털 14프레임 뒤 꼬리 %d개 (trail_count %d)" % [p.trail_size(), p.trail_count])
		_ok(p.trail_size() >= 3 and p.trail_size() <= p.trail_count, "깃털 꼬리 잔상 3개 이상")
	for p in feathers:
		p.free()
	# ---- 잎 흩날리기: 앞 0.35초는 흰 띠만(잎 없음), 그 뒤 잎이 떨어지고 띠는 0.45 로 남는다 ----
	boss._set_state(boss.State.LEAF_RAIN)
	boss._timer = boss.leaf_rain_time
	boss._spawn_accum = 0.0
	var lr := {"warn_early": 0.0, "leaves_early": 0, "warn_mid": 0.0, "band_visible": false}
	_run(boss, vis, func() -> bool: return boss.state == boss.State.HOVER, 6.0, func(t: float) -> void:
		if t > 0.15 and t < 0.3:
			lr.warn_early = maxf(lr.warn_early, boss.rain_warn)
			lr.leaves_early = maxi(lr.leaves_early, get_tree().get_nodes_in_group("projectile").size())
			lr.band_visible = lr.band_visible or vis._band.visible
		if t > 2.0 and t < 3.0:
			lr.warn_mid = boss.rain_warn)
	var leaves: Array = get_tree().get_nodes_in_group("projectile")
	print("[probe]    흰 띠: 예고 중 %.2f(잎 %d개, 띠 보임 %s), 떨어지는 중 %.2f, 잎 %d개 (%.1f초 동안)" % [lr.warn_early, lr.leaves_early, lr.band_visible, lr.warn_mid, leaves.size(), boss.leaf_rain_time])
	_ok(lr.warn_early >= 0.95 and lr.leaves_early == 0 and lr.band_visible, "예고 0.35초 동안 띠만 있고 잎은 없다")
	_ok(lr.warn_mid > 0.35 and lr.warn_mid < 0.55, "잎이 떨어지는 동안 띠는 옅게(0.45) 남는다")
	_ok(leaves.size() >= 12, "잎이 12장 이상 떨어진다")
	if leaves.size() > 0:
		var p: Projectile = leaves[0]
		# 예전 잎 그림: 마름모 가로 size.x, 세로 size.x×0.55 (size.y 는 안 썼다)
		_check_shot(p, "잎", Vector2(46, 20), 12.0, Vector2(46.0, 46.0 * 0.55))
		_ok(p.fade_in > 0.05, "잎은 생길 때 서서히 나타난다 (fade_in %.2f)" % p.fade_in)
		_ok(p.outline_color.a > 0.0 and p.outline_color.r > 0.9 and p.outline_color.g > 0.9, "잎 테두리가 희다 %s" % p.outline_color)
	_run(boss, vis, func() -> bool: return boss.rain_warn < 0.05, 2.0)
	_ok(boss.rain_warn < 0.05 and not vis._band.visible, "끝나면 띠가 사라진다 (%.2f)" % boss.rain_warn)
	for p in leaves:
		p.free()
	# ---- 소녀의 바람(GUST): 테두리·발광을 더해도 그림·발광이 판정 사각형(0.9×size) 안 ----
	var g: Projectile = load("res://scenes/combat/projectile.tscn").instantiate()
	g.kind = Projectile.Kind.GUST
	g.size = Vector2(110, 60)
	g.color = Color(0.8, 1.0, 0.85)
	get_tree().root.add_child(g)
	g.launch(Vector2.RIGHT, player, true)
	var gb := g.draw_bounds()
	var gr := g.glow_radii()
	var gc := g.glow_center()
	# 그림 식과 따로, 호 세 겹을 직접 계산해 맞춰 본다 (선 굵기 + 테두리 덧굵기 포함)
	var hand := Rect2()
	for i in 3:
		var rr: float = g._gust_radius(i)
		var cx: float = g.size.x * (0.28 - i * 0.3)
		var hw: float = (2.5 + 1.5 * (2 - i) + 2.0) * 0.5
		var b := Rect2(cx + (rr - hw) * cos(1.15), -(rr + hw) * sin(1.15), 0, 0)
		b.end = Vector2(cx + rr + hw, (rr + hw) * sin(1.15))
		hand = b if i == 0 else hand.merge(b)
	print("[probe]    바람 그림 범위(테두리 포함) %s (직접 계산 %s, 호 비율 %.3f), 발광 중심 %s 반지름 %s / 판정 ±%s" % [gb, hand, g._gust_k, gc, gr, g.size * 0.45])
	_ok(gb.position.distance_to(hand.position) < 0.01 and gb.end.distance_to(hand.end) < 0.01, "바람 그림 범위 = 직접 계산한 호")
	_ok(gb.end.x <= g.size.x * 0.45 + 0.01 and gb.position.x >= -g.size.x * 0.45 and absf(gb.position.y) <= g.size.y * 0.45 + 0.01 and gb.end.y <= g.size.y * 0.45 + 0.01, "바람 그림(테두리까지)이 판정 안")
	_ok(gc.x + gr.x <= g.size.x * 0.45 + 0.01 and gr.y <= g.size.y * 0.45 + 0.01, "바람 발광이 판정 안")
	_ok(g._glow != null and g._glow.material is CanvasItemMaterial and (g._glow.material as CanvasItemMaterial).blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "발광은 더하기 혼합 Sprite2D")
	g.free()
	# ---- 구슬(ORB) 종류: 둥근 그림, 판정 size 기준 ----
	var o: Projectile = load("res://scenes/combat/projectile.tscn").instantiate()
	o.kind = Projectile.Kind.ORB
	o.size = Vector2(40, 40)
	get_tree().root.add_child(o)
	_ok(absf(o.hit_radius() - 24.0) < 0.01 and o.draw_half_extent().x >= 20.0, "구슬: 판정 %.0f, 그림 반 %.1f" % [o.hit_radius(), o.draw_half_extent().x])
	o.free()
	# ---- 정사각형 size 로 쓰는 잎(기사 등불 44×44 등)은 예전처럼 납작한 잎 (세로 = 가로×0.55) ----
	var sq: Projectile = load("res://scenes/combat/projectile.tscn").instantiate()
	sq.kind = Projectile.Kind.LEAF
	sq.size = Vector2(44, 44)
	get_tree().root.add_child(sq)
	var sqb := sq.body_bounds()
	print("[probe]    정사각형 잎 44×44: 몸 %.1f × %.1f (예전 44 × 24.2)" % [sqb.size.x, sqb.size.y])
	_ok(sqb.size.y < 26.0 and sqb.size.x > 36.0, "정사각형 잎은 뚱뚱해지지 않는다")
	sq.free()
	# ---- 자기 _draw 를 그리는 하위 클래스(확장판 SapProjectile 같은)는 바탕 발광·꼬리를 안 붙인다 ----
	var sub_script := GDScript.new()
	sub_script.source_code = "extends Projectile\nfunc _draw() -> void:\n\tdraw_circle(Vector2.ZERO, 5.0, color)\n"
	sub_script.reload()
	var sub := Area2D.new()
	sub.set_script(sub_script)
	get_tree().root.add_child(sub)
	_ok(sub._glow == null and sub.trail_count == 0, "하위 클래스엔 바탕 발광·꼬리 없음 (발광 %s, 꼬리 %d)" % [sub._glow, sub.trail_count])
	sub.free()
	# ---- 꼬리는 삼각형 배열 하나 (잔상 수와 무관하게 그리기 호출 1번): 잔상 점 수 = 잔상 × 윤곽 점 ----
	var tp: Projectile = load("res://scenes/combat/projectile.tscn").instantiate()
	tp.kind = Projectile.Kind.FEATHER
	tp.size = Vector2(76, 16)
	tp.draw_scale = 1.8
	tp.trail_count = 5
	get_tree().root.add_child(tp)
	tp.global_position = Vector2(100, 100)
	tp.launch(Vector2.RIGHT, null, false)
	for i in 12:
		tp._physics_process(DT)
	var built: bool = tp._build_trail(Color.WHITE)
	_ok(built and tp.trail_size() == 5 and tp._tr_pts.size() == 5 * tp._sil_pts.size() and tp._tr_idx.size() == 5 * tp._sil_tris.size() and not tp._sil_tris.is_empty(),
		"꼬리 5개 = 삼각형 배열 하나 (점 %d, 삼각형 꼭짓점 %d)" % [tp._tr_pts.size(), tp._tr_idx.size()])
	tp.free()
	# ---- 깃털 동안 몸 방향 고정: 시작할 때 한 번 소녀 쪽(데드존 안이어도)을 보고, 쏘는 동안 소녀가 건너가도 그대로 ----
	boss.global_position = Vector2(1200, 520)
	boss.facing = -1
	boss._face_hold = 0.0
	player.global_position = Vector2(1250, 1000)   # 오른쪽, 데드존(80) 안
	boss._set_state(boss.State.HOVER)
	boss._pattern_index = 1                          # 1페이즈 순서의 두 번째 = 깃털
	boss._next_pattern()
	var face_start: int = boss.facing
	player.global_position = Vector2(400, 1000)     # 쏘는 동안 왼쪽으로 멀리 건너감
	var face_flip := {"n": 0}
	_run(boss, vis, func() -> bool: return boss.state != boss.State.FEATHERS, 3.0, func(_t: float) -> void:
		if boss.state == boss.State.FEATHERS and boss.facing != face_start:
			face_flip.n += 1)
	print("[probe]    깃털 시작 방향 %d (소녀 오른쪽 50px), 쏘는 동안 뒤집힌 프레임 %d, 붉은 점 자리 %s (발밑 %s)" % [face_start, face_flip.n, boss.muzzle_point(), boss.global_position])
	_ok(face_start == 1 and face_flip.n == 0, "깃털: 시작 때 소녀 쪽을 보고, 쏘는 동안은 방향 고정")
	_ok(boss.muzzle_point().y < boss.global_position.y - 150.0, "붉은 점·깃털 출발점은 부리 높이 (발밑보다 150px 넘게 위)")
	for p in get_tree().get_nodes_in_group("projectile"):
		p.free()
	# ---- 띠는 새 그림 뒤 (top_level 아님 + show_behind_parent), 새 색에 물들지 않음, 2페이즈 고리 중심 = 새 몸 가운데 ----
	boss.phase = 2
	boss._set_state(boss.State.HOVER)
	boss.rain_warn = 0.9
	vis._process(DT)
	var band: Node2D = vis._band
	print("[probe]    띠: top_level %s, 뒤에 그림 %s, 부모 = 새 그림 %s, 세계 변환 %s, 고리 중심 %s / 몸 가운데 %s, 새 modulate %s" % [
		band.top_level, band.show_behind_parent, band.get_parent() == vis, band.global_transform, band.center, boss.body_center(), vis.modulate])
	_ok(not band.top_level and band.show_behind_parent and band.get_parent() == vis and band.visible, "띠는 새 그림 뒤에 그린다 (top_level 아님)")
	_ok(band.global_transform.origin.length() < 0.01 and absf(band.global_transform.get_rotation()) < 0.001 and band.global_transform.get_scale().distance_to(Vector2.ONE) < 0.001, "띠는 세계 좌표 그대로 (새의 기울기·뒤집기 영향 없음)")
	_ok(vis.modulate == Color(1, 1, 1, 1), "새 색은 self_modulate 로만 (띠가 물들지 않는다)")
	_ok(band.center.distance_to(boss.global_position + Vector2(0, -150)) < 0.01, "2페이즈 고리 중심 = 새 몸 가운데")
	var front: Node2D = vis._band_front
	_ok(front.front and not front.top_level and not front.show_behind_parent and front.visible, "2페이즈 고리 아랫반은 새 앞에 (윗반은 뒤 — 큰 날개에 가려지지 않게)")
	boss.phase = 1
	vis._process(DT)
	_ok(band.visible and not front.visible, "1페이즈 띠는 뒤 노드만 그린다")
	boss.phase = 1
	# ---- 소녀가 잎 흩날리기·깃털 도중 쓰러짐 → reset_fight 가 예고 값을 비운다 (다시 싸울 때 옛 띠·점 번쩍임 없음) ----
	boss._set_state(boss.State.LEAF_RAIN)
	boss.rain_warn = 0.45
	boss.feather_warn = 0.62
	boss.muzzle_flash = 0.5
	boss.telegraph_amount = 0.4
	boss.reset_fight()
	vis._process(DT)
	print("[probe]    reset_fight 뒤: rain_warn %.2f, feather_warn %.2f, muzzle_flash %.2f, telegraph %.2f, 띠 보임 %s, 점 보임 %s" % [
		boss.rain_warn, boss.feather_warn, boss.muzzle_flash, boss.telegraph_amount, band.visible, vis._muzzle.visible])
	_ok(boss.rain_warn == 0.0 and boss.feather_warn == 0.0 and boss.muzzle_flash == 0.0 and boss.telegraph_amount == 0.0 and not band.visible and not vis._muzzle.visible, "reset_fight 가 예고 값을 비운다")
	# ---- 체력만 2배: 잎 삼키기 회복량은 예전(900×0.06 = 54) 그대로 ----
	_ok(absf(boss.max_hp * boss.eat_heal_ratio - 54.0) < 0.01, "잎 삼키기 회복 %.0f (예전 54 그대로)" % (boss.max_hp * boss.eat_heal_ratio))
	boss.player = null
	player.free()


## 탄막 하나의 그림 크기·테두리·발광·꼬리 설정을 검사한다.
## 그림 크기는 **예전 그림**(old_draw: 3e7e6aa 의 몸통 다각형 가로·세로)과 비교한다 — 몸통만(테두리 제외)으로 1.6~2.1배.
func _check_shot(p: Projectile, label: String, base_size: Vector2, base_radius: float, old_draw: Vector2) -> void:
	var body := p.body_bounds()
	var full := p.draw_bounds()
	var shape_r := -1.0
	for c in p.get_children():
		if c is CollisionShape2D and c.shape is CircleShape2D:
			shape_r = (c.shape as CircleShape2D).radius
	var ratio_x := body.size.x / old_draw.x
	var ratio_y := body.size.y / old_draw.y
	print("[probe]    %s: size %s, 그림 배율 %.2f → 몸 %.1f × %.1f (예전 그림 %.1f × %.1f 대비 %.2f×, %.2f×; 테두리까지 %.1f × %.1f), 판정 반지름 %.1f (모양 %.1f), 테두리 %s, 발광 %.1f, 꼬리 %d" % [
		label, p.size, p.draw_scale, body.size.x, body.size.y, old_draw.x, old_draw.y, ratio_x, ratio_y, full.size.x, full.size.y, p.hit_radius(), shape_r, p.outline_color, p.glow, p.trail_count])
	_ok(p.size == base_size and absf(p.hit_radius() - base_radius) < 0.01 and absf(shape_r - base_radius) < 0.01, "%s 판정은 그대로 (반지름 %.0f)" % [label, base_radius])
	_ok(ratio_x >= 1.6 and ratio_x <= 2.1 and ratio_y >= 1.6 and ratio_y <= 2.1, "%s 몸 그림은 예전 그림의 1.6~2.1배" % label)
	_ok(p.outline_color.a > 0.0 and p.glow > 0.0 and p.trail_count >= 3 and p.trail_count <= 5, "%s 테두리·발광·꼬리(3~5) 있음" % label)
	_ok(p._glow != null and p._glow.get_parent() == p, "%s 발광 자식 있음" % label)

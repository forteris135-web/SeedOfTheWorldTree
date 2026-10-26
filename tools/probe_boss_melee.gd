extends Node
const ArtMeasure := preload("res://tools/shot_art_measure.gd")
## Claude Code용 시험: 보스 근접 공격의 판정 = 공격 범위 예고 = 공격 이펙트 (v1.1.0 기획자 요청 1).
## 실행: godot --headless --path . res://tools/probe_boss_melee.tscn   (-- --only knight 처럼 한 보스만)
## 각 공격을 걸고 (보스 발밑·바라보는 쪽 = +x 기준 좌표로):
##  - 판정: 켜져 있던 동안 Hitbox 사각형의 합 (움직이는 공격은 쓸고 지나간 구간)
##  - 예고: 보스의 RangeTelegraph 가 예비동작 끝(타격 직전)에 그리던 사각형 — 판정과 ±2px (움직이는 공격 ±MOVE_TOL)
##  - 이펙트: 그 공격의 이펙트 그림(알파 0.25 이상 부분, 투명도 0.25 이상인 동안)의 합 — 각 변이 판정 변에서 ±max(40px, 그 치수의 15%)
## 새 내려앉기 날개바람(v1.1.0 맞딜 검수)도 같은 규칙으로 잰다. 보스가 소녀를 맞히지 않게 소녀는 무적·입력 끔. 판정 숫자는 바꾸지 않는다(이펙트·예고를 판정에 맞춘다).
## 보스 투사체 (명세 3.6): 지형 관통·바닥선, 그리고 보이는 그림 반경 = 판정 반경 ±20% (tools/shot_art_measure.gd 로 그림 픽셀을 잰다 —
## 새 잎·깃털, 기사 불꽃 파도·고리·등불·불기둥·검기, 여왕 가루·나비, 펌프 충격파·분사, 뿌리지기 달빛 구슬·씨앗 비).

const TEL_TOL := 2.0
## 움직이는 공격(돌진·미끄러짐)의 예고 허용 (물리 틱 단위 적분 차이)
const MOVE_TOL := 14.0
const FX_TOL_MIN := 40.0
const FX_TOL_FRAC := 0.15

var _fail := 0
var _trim := {}   # 그림 → 알파 0.25 이상 사각형 (그림 픽셀)
var _only := ""
## 눈 확인용 (창 모드에서만): -- --shots <폴더> → 공격마다 예고(가득 차기 직전)·이펙트(한창) 스크린샷
var _shots := ""
var _cam: Camera2D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var oi := args.find("--only")
	if oi >= 0 and oi + 1 < args.size():
		_only = args[oi + 1]
	var si := args.find("--shots")
	if si >= 0 and si + 1 < args.size() and DisplayServer.get_name() != "headless":
		_shots = args[si + 1]
		DirAccess.make_dir_recursive_absolute(_shots)
	Settings.data["screen_shake"] = false
	print("[probe] 보스 근접 공격: 판정 = 예고 = 이펙트")
	if _only in ["", "bird"]:
		await _bird()
	if _only in ["", "knight"]:
		await _knight()
	if _only in ["", "root"]:
		await _root()
	if _only in ["", "queen"]:
		await _queen()
	if _only in ["", "pump"]:
		await _pump()
	if _only in ["", "shots"]:
		await _projectile_rules()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _load_room(name: String) -> Dictionary:
	var room: Node = load("res://scenes/rooms/%s.tscn" % name).instantiate()
	add_child(room)
	await _frames(8)
	var player := get_tree().get_first_node_in_group("player") as Player
	var boss := room.get_node("Boss") as Node2D
	player._invuln_timer = 99999.0
	player.input_enabled = false
	var c: Rect2 = boss.arena
	player.global_position = Vector2(c.get_center().x - 400.0, float(boss.ground_y) - 4.0)
	await _frames(3)
	if not room.fight_started:
		room._on_trigger(player)
	Music.stop(0.0)   # 여왕 박자 시계가 실제 시간으로 (음악 재생 위치에 묶이지 않게)
	if _shots != "":
		_cam = Camera2D.new()
		_cam.zoom = Vector2(0.62, 0.62)
		room.add_child(_cam)
		_cam.make_current()
	await _frames(170)
	return {"room": room, "boss": boss, "player": player}


func _unload(r: Dictionary) -> void:
	r["room"].queue_free()
	await _frames(3)
	Fx.clear()


func _hb_rect(hb: Hitbox) -> Rect2:
	var cs: CollisionShape2D = hb._shape
	var sz: Vector2 = (cs.shape as RectangleShape2D).size
	return Rect2(cs.global_position - sz * 0.5, sz)


func _local(r: Rect2, o: Vector2, f: int) -> Rect2:
	var a := Vector2((r.position.x - o.x) * f, r.position.y - o.y)
	var b := Vector2((r.end.x - o.x) * f, r.end.y - o.y)
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


func _fmt(r: Rect2) -> String:
	if r.size == Vector2.ZERO:
		return "(없음)"
	return "x %d..%d  y %d..%d" % [roundi(r.position.x), roundi(r.end.x), roundi(r.position.y), roundi(r.end.y)]


## 그림의 알파 0.25 이상 사각형 (그림 픽셀 좌표). 한 번 재고 기억한다.
func _trim_of(tex: Texture2D) -> Rect2:
	var key := tex.resource_path
	if _trim.has(key):
		return _trim[key]
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			if img.get_pixel(x, y).a >= 0.25:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	var r := Rect2(x0, y0, x1 - x0 + 2, y1 - y0 + 2) if x1 >= 0 else Rect2()
	_trim[key] = r
	return r


## FxSprite 의 보이는 부분(알파 0.25 이상)의 월드 사각형
func _fx_rect(fx: FxSprite) -> Rect2:
	var tex := fx.texture
	var t := _trim_of(tex)
	if t.size == Vector2.ZERO:
		return Rect2()
	var base := fx.get_rect()   # 그림 사각형 (가운데·offset 반영, 자기 좌표)
	var lr := Rect2(base.position + t.position, t.size)
	var xf := fx.get_global_transform()
	var pts := [xf * lr.position, xf * Vector2(lr.end.x, lr.position.y), xf * lr.end, xf * Vector2(lr.position.x, lr.end.y)]
	var out := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		out = out.expand(p)
	return out


## 공격 하나를 재고 단언한다.
## names: 이 공격의 이펙트 이름들 (합으로 잰다). moving: 움직이는 공격(예고 허용 MOVE_TOL). per_hit: 활성마다 따로 비교할 이름 [[이름..], [이름..]].
func _measure(label: String, r: Dictionary, start: Callable, frames: int, names: Array, moving := false, per_hit: Array = []) -> void:
	var b: Node2D = r["boss"]
	var p: Player = r["player"]
	var tel: RangeTelegraph = b.get_node_or_null("RangeTelegraph") as RangeTelegraph
	var t0 := Time.get_ticks_msec()
	start.call()
	var hb_u := {}
	var origin := Vector2.INF
	var fac := 1
	var fx_u := {}        # 활성 번호 → Rect2 (월드)
	var fx_any := Rect2()
	var tel_last := {}    # 활성 번호 → 예고 사각형 (월드, 타격 직전)
	var tel_cur := Rect2()
	var act_i := -1
	var was_active := false
	var hb: Hitbox = b.hitbox
	var seen := {}
	var want_hits := maxi(per_hit.size(), 1)
	var last_active := -1000   # 센 판정이 마지막으로 켜져 있던 틱
	var counting := false      # 지금 켜진 판정을 세는 중인가 (정해진 타 수를 넘긴 다음 공격의 판정은 세지 않는다)
	var shot_tel := false
	var shot_fx := false
	var safe := label.replace(" ", "_")
	for i in frames:
		if tel and tel.is_showing():
			tel_cur = tel.rect
		if _cam:
			_cam.global_position = Vector2(b.global_position.x, float(b.ground_y) - 260.0)
			if not shot_tel and tel and tel.is_showing() and tel.progress() >= 0.8:
				shot_tel = true
				await _snap("%s/%s_1_tel.png" % [_shots, safe])
			if not shot_fx:
				for fx in Fx._active:
					if fx.born_ms >= t0 and fx.fx_name in names and fx.t > fx.life * 0.3:
						shot_fx = true
						await _snap("%s/%s_2_fx.png" % [_shots, safe])
						break
		await get_tree().physics_frame
		p._invuln_timer = 99999.0
		p.hp = p.max_hp
		if hb._active and not was_active:
			counting = act_i + 1 < want_hits
			if counting:
				act_i += 1
				if origin == Vector2.INF:
					origin = b.global_position
					fac = int(b.facing)
				tel_last[act_i] = tel_cur
				tel_cur = Rect2()
				hb_u[act_i] = _hb_rect(hb)
		elif hb._active and counting:
			hb_u[act_i] = (hb_u[act_i] as Rect2).merge(_hb_rect(hb))
		if hb._active and counting:
			last_active = i
		was_active = hb._active
		for fx in Fx._active:
			if fx.born_ms < t0 or not (fx.fx_name in names) or fx.texture == null:
				continue
			var key := fx.get_instance_id() * 1000 + fx.gen
			if not seen.has(key):
				if act_i >= want_hits - 1 and last_active >= 0 and i - last_active > 24:
					continue   # 공격이 끝나고 한참 뒤에 생긴 이펙트 (다음 공격의 것)
				seen[key] = maxi(act_i, 0)
			if fx.modulate.a < 0.25:
				continue
			var rr := _fx_rect(fx)
			var k: int = seen[key]
			fx_u[k] = rr if not fx_u.has(k) else (fx_u[k] as Rect2).merge(rr)
			fx_any = rr if fx_any.size == Vector2.ZERO else fx_any.merge(rr)
	if origin == Vector2.INF:
		origin = b.global_position
		fac = int(b.facing)
	print("[probe] ==== %s  (보스 발밑 %s, 바라봄 %d)" % [label, origin.round(), fac])
	if hb_u.is_empty():
		_check(false, "%s: 판정이 켜지지 않았다" % label)
		return
	for k in hb_u:
		var hl := _local(hb_u[k], origin, fac)
		var tl := _local(tel_last.get(k, Rect2()), origin, fac) if tel_last.get(k, Rect2()).size != Vector2.ZERO else Rect2()
		print("[probe]   판정#%d: %s" % [k, _fmt(hl)])
		print("[probe]   예고#%d: %s" % [k, _fmt(tl)])
		var tol := MOVE_TOL if moving else TEL_TOL
		_check(tl.size != Vector2.ZERO and _close(tl, hl, Vector2(tol, TEL_TOL)), "%s #%d: 예고 = 판정 (±%dpx) — 예고 %s / 판정 %s" % [label, k, int(tol), _fmt(tl), _fmt(hl)])
		var fr: Rect2 = Rect2()
		if per_hit.is_empty():
			fr = fx_any
		elif fx_u.has(k):
			fr = fx_u[k]
		if not names.is_empty():
			var fl := _local(fr, origin, fac) if fr.size != Vector2.ZERO else Rect2()
			print("[probe]   이펙트#%d %s: %s" % [k, str(names), _fmt(fl)])
			var tx := maxf(FX_TOL_MIN, hl.size.x * FX_TOL_FRAC)
			var ty := maxf(FX_TOL_MIN, hl.size.y * FX_TOL_FRAC)
			_check(fl.size != Vector2.ZERO and _close(fl, hl, Vector2(tx, ty)), "%s #%d: 이펙트 = 판정 (가로 ±%d, 세로 ±%d) — 이펙트 %s / 판정 %s" % [label, k, int(tx), int(ty), _fmt(fl), _fmt(hl)])
		if per_hit.is_empty():
			break   # 이펙트를 합으로 재는 공격은 첫 판정만 비교 (판정도 합)


func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


## 방금 보스가 쏜 투사체들 (그룹 projectile, 출처가 보스, 아직 살아 있음) 가운데 before 에 없던 것
func _new_shots(b: Node, before: Array) -> Array:
	var out := []
	for p in get_tree().get_nodes_in_group("projectile"):
		if is_instance_valid(p) and not (p in before) and p.get("source") == b and not p.get("_dead"):
			out.append(p)
	return out


## 보스 투사체 규칙 (명세 3.6): 지형을 뚫는다(pierce_terrain), 바닥선(floor_y)이 싸움터 바닥 아래, 그림/판정 반경 (참고 출력)
func _shot_rules(label: String, b: Node, spawn: Callable, need_floor := true) -> void:
	var before := get_tree().get_nodes_in_group("projectile").duplicate()
	spawn.call()
	await _frames(2)
	var shots := _new_shots(b, before)
	_check(not shots.is_empty(), "%s: 투사체가 생겼다 (%d개)" % [label, shots.size()])
	for p in shots:
		var ok := true
		var txt := ""
		if p is Projectile:
			ok = p.pierce_terrain and (not need_floor or (p.floor_y >= float(b.ground_y) and p.floor_y < 1e8))
			txt = "pierce %s, 바닥선 %.0f (보스 바닥 %.0f)" % [p.pierce_terrain, p.floor_y, b.ground_y]
			var m := ArtMeasure.projectile(p)
			_check(ArtMeasure.fits(m), "%s: 보이는 그림 반경 = 판정 반경 ±20%% — %s" % [label, ArtMeasure.describe(m)])
		elif p is RootOrb:
			ok = p.ground_y == float(b.ground_y)
			txt = "달빛 구슬: 지형 검사 없음, 바닥선 %.0f" % p.ground_y
			# 그림(_art)은 진행 방향으로 돈다 → 그 반대로 돌려 진행 방향 좌표로
			var m := ArtMeasure.metric(ArtMeasure.sprite_points(p._art, -p._art.rotation), "dir")
			var r: float = p.hit_radius()
			m["r"] = r
			m["ratio"] = m["vis"] / r
			m["ratio_min"] = m["ratio"]
			_check(ArtMeasure.fits(m), "%s: 보이는 그림 반경 = 판정 반경 ±20%% — %s" % [label, ArtMeasure.describe(m)])
		_check(ok, "%s: 보스 투사체는 지형을 뚫는다 — %s" % [label, txt])
		break


## 보스 투사체 지형 관통·바닥선·불기둥/가시 예고 (명세 3.6)
func _projectile_rules() -> void:
	print("[probe] ---- 보스 투사체: 지형 관통 · 예고 일치")
	# 1) 바탕 규칙: 지형을 뚫는 투사체는 벽을 지나가고, 몹 투사체(뚫지 않음)는 벽에 막힌다
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	var cs := CollisionShape2D.new()
	var rs := RectangleShape2D.new()
	rs.size = Vector2(40, 600)
	cs.shape = rs
	wall.add_child(cs)
	add_child(wall)
	wall.global_position = Vector2(20200, 0)
	var src := Node2D.new()
	add_child(src)
	var a := Projectile.new()
	a.pierce_terrain = true
	a.speed = 600.0
	a.lifetime = 3.0
	a.size = Vector2(40, 20)
	add_child(a)
	a.global_position = Vector2(20000, -50)
	a.launch(Vector2.RIGHT, src)
	var bproj := Projectile.new()
	bproj.speed = 600.0
	bproj.lifetime = 3.0
	bproj.size = Vector2(40, 20)
	add_child(bproj)
	bproj.global_position = Vector2(20000, 50)
	bproj.launch(Vector2.RIGHT, src)
	await _frames(60)
	_check(is_instance_valid(a) and not a._dead and a.global_position.x > 20500, "지형을 뚫는 투사체는 벽을 지나간다 (x %.0f)" % (a.global_position.x if is_instance_valid(a) else -1.0))
	_check(not is_instance_valid(bproj) or bproj._dead, "뚫지 않는 투사체(몹·중간 보스)는 벽에 막힌다")
	if is_instance_valid(a):
		a.queue_free()
	# 2) 바닥선: 지형을 뚫는 투사체가 바닥선을 지나면 그 자리에 내려앉고(landed, 위쪽 면) 사라진다
	var c := Projectile.new()
	c.pierce_terrain = true
	c.floor_y = 300.0
	c.speed = 900.0
	c.lifetime = 3.0
	add_child(c)
	c.global_position = Vector2(21000, 0)
	var got := []
	c.landed.connect(func(pos: Vector2, n: Vector2) -> void: got.append([pos, n]))
	c.launch(Vector2.DOWN, src)
	await _frames(40)
	_check(got.size() == 1 and absf(got[0][0].y - 300.0) < 0.5 and got[0][1] == Vector2.UP and (not is_instance_valid(c) or c._dead),
		"바닥선 300 을 지나면 그 자리에서 내려앉는다 (%s)" % str(got))
	wall.queue_free()
	# 3) 보스마다: 실제 쏘는 함수의 투사체가 지형을 뚫는다
	var r := await _load_room("canopy_boss")
	var bird: Node2D = r["boss"]
	await _shot_rules("새 잎", bird, func() -> void: bird._spawn_leaf())
	await _shot_rules("새 깃털", bird, func() -> void: bird._spawn_feather(0, 3))
	await _unload(r)
	r = await _load_room("mine_boss")
	var kn: Node2D = r["boss"]
	await _shot_rules("기사 불꽃 파도", kn, func() -> void: kn._spawn_flame_wave(-1))
	await _shot_rules("기사 불꽃 고리", kn, func() -> void: kn._spawn_ring(0))
	# 등불 던지기: 바닥선 = 바닥 → 바닥에 닿는 순간 불기둥 예고. 불기둥 판정 반경 = 예고 타원 반폭 = 96
	var before := get_tree().get_nodes_in_group("projectile").duplicate()
	kn._throw_lantern()
	await _frames(2)
	var lan := _new_shots(kn, before)
	_check(lan.size() == 1 and lan[0].pierce_terrain and is_equal_approx(lan[0].floor_y, float(kn.ground_y)), "기사 등불 던지기: 지형을 뚫고 바닥선 = 바닥(%.0f)" % kn.ground_y)
	if lan.size() == 1:
		var lm := ArtMeasure.projectile(lan[0])
		_check(ArtMeasure.fits(lm), "기사 던진 등불: 보이는 그림 반경 = 판정 반경 ±20%% — %s" % ArtMeasure.describe(lm))
	var pil_before := get_tree().get_nodes_in_group("projectile").duplicate()
	var marks0 := get_tree().get_nodes_in_group("knight_pillar_mark").size()
	var t := 0
	while t < 240 and get_tree().get_nodes_in_group("knight_pillar_mark").size() == marks0:
		await get_tree().physics_frame
		t += 1
	var marks := get_tree().get_nodes_in_group("knight_pillar_mark")
	_check(marks.size() > marks0, "등불이 바닥에 닿아 불기둥 예고가 섰다 (%d틱)" % t)
	if marks.size() > marks0:
		var m: Polygon2D = marks[marks.size() - 1]
		_check(absf(m.global_position.y - float(kn.ground_y)) < 1.0, "불기둥 예고는 바닥(y %.0f)에 선다 (%.0f)" % [kn.ground_y, m.global_position.y])
		var half := 0.0
		for q in m.polygon:
			half = maxf(half, absf(q.x))
		half *= LanternKnight.PILLAR_MARK_END_SCALE
		var pillar_r := maxf(160.0 * 0.6, 10.0)
		_check(absf(half - pillar_r) <= 1.0 and is_equal_approx(LanternKnight.PILLAR_RADIUS, pillar_r), "불기둥 예고 반폭 %.1f = 판정 반경 %.1f (예전 77.5)" % [half, pillar_r])
		# 불기둥 그림 (예고가 끝나면 선다): 가로·세로 반폭 모두 판정 반경 ±20%
		var tp := 0
		var pil: Array = []
		while tp < 120 and pil.is_empty():
			await get_tree().physics_frame
			tp += 1
			for q in _new_shots(kn, pil_before):
				if q is Projectile and q.speed <= 0.0:
					pil.append(q)
		_check(not pil.is_empty(), "불기둥이 섰다 (%d틱)" % tp)
		if not pil.is_empty():
			var pm2 := ArtMeasure.projectile(pil[0])
			_check(ArtMeasure.fits(pm2), "불기둥: 보이는 그림 반폭 = 판정 반경 ±20%% — %s" % ArtMeasure.describe(pm2))
	await _unload(r)
	r = await _load_room("sap_lake_boss")
	var qn: Node2D = r["boss"]
	await _shot_rules("여왕 날개가루", qn, func() -> void: qn._scatter_dust())
	await _shot_rules("여왕 나비", qn, func() -> void: qn._spawn_butterfly(0, 3))
	await _unload(r)
	r = await _load_room("flooded_mine_boss")
	var pm: Node2D = r["boss"]
	await _shot_rules("펌프 충격파", pm, func() -> void: pm._slam())
	await _shot_rules("펌프 분사", pm, func() -> void: pm._spray())
	await _unload(r)
	r = await _load_room("abyss_boss")
	var rk: Node2D = r["boss"]
	await _shot_rules("뿌리지기 달빛 구슬", rk, func() -> void: rk._spawn_orb(0.0))
	# 씨앗 비: 떨어지는 동안 판정 원 HIT_R — 그림(아래로 떨어진다: 진행 방향 = +y 를 +x 로 돌려서)
	var sd_before := get_tree().get_nodes_in_group("projectile").duplicate()
	rk._spawn_seed(rk.global_position.x - 300.0)
	await _frames(2)
	var seeds: Array = []
	for q in get_tree().get_nodes_in_group("projectile"):
		if q is RootSeed and not (q in sd_before):
			seeds.append(q)
	_check(not seeds.is_empty(), "뿌리지기 씨앗 비가 생겼다")
	if not seeds.is_empty():
		var sm := ArtMeasure.metric(ArtMeasure.sprite_points(seeds[0]._art, -PI / 2.0), "dir")
		sm["r"] = RootSeed.HIT_R
		sm["ratio"] = sm["vis"] / RootSeed.HIT_R
		sm["ratio_min"] = sm["ratio"]
		_check(ArtMeasure.fits(sm), "뿌리지기 씨앗 비: 보이는 그림 반경 = 판정 반경 ±20%% — %s" % ArtMeasure.describe(sm))
	# 뿌리 가시: 예고 바닥 폭 = 판정 폭 (110)
	var spike_src := FileAccess.get_file_as_string("res://scripts/combat/root_spike.gd")
	_check(spike_src.contains("var w := WIDTH") and is_equal_approx(RootSpike.WIDTH, 110.0), "뿌리 가시 예고 바닥 폭 = 판정 폭 %.0f (예전 110 → 160 으로 커졌다)" % RootSpike.WIDTH)
	await _unload(r)
	# 검기: 지형 검사 없음 (수명으로만 사라진다)
	var sw := FileAccess.get_file_as_string("res://scripts/bosses/sword_wave.gd")
	_check(not sw.contains("intersect_ray"), "기사 검기(SwordWave)는 지형에 막히지 않는다")
	# 검기 그림 vs 판정 상자 (가로 = 진행 방향): 보이는 세로 반폭·앞 끝이 판정 상자의 반높이·반너비 ±20%
	var wv: SwordWave = load("res://scenes/bosses/sword_wave.tscn").instantiate()
	add_child(wv)
	var box_h := wv.hit_box_size().y * 0.5
	var box_w := wv.hit_box_size().x * 0.5
	var wm := ArtMeasure.metric(ArtMeasure.sprite_points(wv._art), "dir")
	var ok_w: bool = wm["perp"] >= box_h * 0.8 and wm["perp"] <= box_h * 1.2 and wm["front"] >= box_w * 0.8 and wm["front"] <= box_w * 1.2
	_check(ok_w, "기사 검기: 보이는 그림 세로 반폭 %.1f / 판정 %.1f = %.2f배, 앞 끝 %.1f / 판정 %.1f = %.2f배 (±20%%)" % [wm["perp"], box_h, wm["perp"] / box_h, wm["front"], box_w, wm["front"] / box_w])
	wv.queue_free()


## 네 변이 각각 tol 안에서 같은가
func _close(a: Rect2, b: Rect2, tol: Vector2) -> bool:
	return absf(a.position.x - b.position.x) <= tol.x and absf(a.end.x - b.end.x) <= tol.x \
		and absf(a.position.y - b.position.y) <= tol.y and absf(a.end.y - b.end.y) <= tol.y


# ---------------- 잿빛 잎새의 새 ----------------
func _bird() -> void:
	var r := await _load_room("canopy_boss")
	var b: Node2D = r["boss"]
	var p: Player = r["player"]
	for kind in ["SWEEP", "PECK"]:
		b.global_position = Vector2(b.arena.get_center().x, b.ground_y)
		b.velocity = Vector2.ZERO
		b.set_collision_mask_value(1, true)
		b.phase = 1
		b._set_state(b.State.GROUND_IDLE)
		b._timer = 99.0
		await _frames(10)
		p.global_position = b.global_position + Vector2(-600, -4)
		b.facing = -1
		await _measure("새 " + kind, r, func() -> void:
			b.facing = -1
			b.force_melee(kind), 110, ["wing_sweep"] if kind == "SWEEP" else ["peck_burst", "peck_streak"], kind == "PECK")
	# 맞딜 응징 날개 털기 (v1.1.0 맞딜 검수): 몸 둘레(앞뒤·머리 위 460) — 예고 = 판정 = 잎 무더기
	b.global_position = Vector2(b.arena.get_center().x, b.ground_y)
	b.velocity = Vector2.ZERO
	b.set_collision_mask_value(1, true)
	b._set_state(b.State.GROUND_IDLE)
	b._timer = 99.0
	b._ground_actions = 1
	await _frames(10)
	p.global_position = b.global_position + Vector2(-600, -4)
	await _measure("새 날개 털기(응징)", r, func() -> void:
		b.crowd.t = b.crowd.trigger
		b._pick_ground_action(), 110, ["bird_land"], false)
	_check(b.get("flap") == false, "날개 털기가 끝나면 flap 꺼짐")
	# 내려앉기 날개바람 (v1.1.0 맞딜 검수): 내려오는 동안 앉을 자리에 예고 → 앉는 순간 판정 = 잎 무더기
	b.global_position = Vector2(b.arena.get_center().x, b.ground_y - 420.0)
	b.velocity = Vector2.ZERO
	b.set_collision_mask_value(1, false)
	b._set_state(b.State.HOVER)
	b._timer = 99.0
	await _frames(4)
	p.global_position = Vector2(b.arena.get_center().x - 900.0, b.ground_y - 4.0)
	await _measure("새 내려앉기 날개바람", r, func() -> void: b._begin_descend(), 200, ["bird_land"], false)
	await _unload(r)


# ---------------- 등불 기사 ----------------
func _knight() -> void:
	var r := await _load_room("mine_boss")
	var b: Node2D = r["boss"]
	var p: Player = r["player"]
	var cases := [["THRUST", ["spear_thrust"], true, []], ["COMBO3", ["spear_thrust", "spear_swing", "spear_upper"], true, [0, 1, 2]],
		["WAVE", ["spear_swing"], false, []], ["SLAM", ["knight_slam"], true, []], ["SPIN", ["knight_spin"], false, []],
		["CHARGE", ["charge_lance"], true, []]]
	for c in cases:
		var nm: String = c[0]
		b.phase = 2 if nm == "SPIN" else 1
		b.global_position = Vector2(b.arena.get_center().x + 300, b.ground_y)
		b.velocity = Vector2.ZERO
		b._set_state(b.State.MARCH)
		b._timer = 99.0
		await _frames(6)
		p.global_position = b.global_position + Vector2(-300, -4)
		b.facing = -1
		await _measure("기사 " + nm, r, func() -> void:
			b.facing = -1
			b.force_attack(b.State[nm]), 240 if nm == "COMBO3" else (220 if nm == "CHARGE" else 160), c[1], c[2], c[3])
	# 등불 휘두르기(FLAME)는 근접 판정이 없다 → 근접 호 이펙트(lantern_arc)도 없어야 한다
	b.global_position = Vector2(b.arena.get_center().x + 300, b.ground_y)
	b._set_state(b.State.MARCH)
	b._timer = 99.0
	await _frames(6)
	Fx.log_spawns = true
	Fx.spawn_log.clear()
	b.force_attack(b.State.FLAME)
	await _frames(110)
	Fx.log_spawns = false
	_check(not ("lantern_arc" in Fx.spawn_log), "기사 FLAME: 근접 판정이 없으니 근접 호 이펙트(lantern_arc)도 없다 (띄운 이펙트 %s)" % str(Fx.spawn_log.slice(0, 8)))
	# 맞딜 응징 내려찍기 (v1.1.0 맞딜 검수 2): 높은 사각형(땅에서 위로 400) × 두 번 — 첫 타격 뒤에도 붙어 있으면 둘째 (예고가 다시 차오른다)
	b.phase = 1
	b.global_position = Vector2(b.arena.get_center().x + 300, b.ground_y)
	b.velocity = Vector2.ZERO
	b._set_state(b.State.MARCH)
	b._timer = 99.0
	await _frames(6)
	p.global_position = b.global_position + Vector2(-120, -4)
	b.facing = -1
	await _measure("기사 응징 내려찍기(두 번)", r, func() -> void:
		b.facing = -1
		b.crowd.t = b.crowd.trigger
		b._choose_attack(120.0), 220, ["knight_slam"], true, [0, 1])
	await _unload(r)


# ---------------- 뿌리지기 ----------------
func _root() -> void:
	var r := await _load_room("abyss_boss")
	var b: Node2D = r["boss"]
	var p: Player = r["player"]
	var cases := [["SWEEP", ["staff_arc"], true], ["SWEEP2", ["staff_arc"], true], ["STOMP", ["root_stomp"], false], ["WALL", [], true]]
	for c in cases:
		var nm: String = c[0]
		b.phase = 2 if nm in ["STOMP", "WALL"] else 1
		b.global_position = Vector2(b.arena.get_center().x + 300, b.ground_y)
		b.velocity = Vector2.ZERO
		b._set_state(b.State.STANCE)
		b._timer = 99.0
		await _frames(6)
		p.global_position = b.global_position + Vector2(-250, -4)
		b.facing = -1
		await _measure("뿌리지기 " + nm, r, func() -> void:
			b.facing = -1
			b._chain = -1
			b.force_pattern(nm), 170, c[1], c[2])
		b._chain = -1
	# 맞딜 응징 내려찍기 (v1.1.0 맞딜 검수 2): 몸 둘레 높은 사각형(땅에서 위로 400) × 두 번 — 땅에 선 소녀가 몸 가까이(175 안)일 때
	b.phase = 1
	b.global_position = Vector2(b.arena.get_center().x + 300, b.ground_y)
	b.velocity = Vector2.ZERO
	b._set_state(b.State.STANCE)
	b._timer = 99.0
	await _frames(6)
	p.global_position = b.global_position + Vector2(-100, -4)
	await _frames(4)
	await _measure("뿌리지기 응징 내려찍기(두 번)", r, func() -> void:
		b.facing = -1
		b._chain = -1
		b.crowd.t = b.crowd.trigger
		b._choose(100.0), 200, ["root_stomp"], false, [0, 1])
	_check(b.get("punishing") == false or b.state != b.State.STOMP, "응징 내려찍기가 끝나면 punishing 꺼짐")
	b._chain = -1
	await _unload(r)


# ---------------- 수액의 여왕 ----------------
func _queen() -> void:
	var r := await _load_room("sap_lake_boss")
	var b: Node2D = r["boss"]
	var beat: float = b.BEAT
	await _measure("여왕 LAND", r, func() -> void:
		b._set_state(b.State.HOVER)
		b._next_at = b._clock + 999.0
		b._land_stone = b._pick_stone()
		b._diving = false
		b._begin(b.State.LAND, b._clock, beat * 2.0, beat, 0.0), 160, ["queen_land"], false)
	# 수액 터뜨리기 (v1.1.0 맞딜 검수 2): 내려앉은 몸에 붙어 버티면 앉은 채로 몸 둘레를 두 번 친다 (예고 = 판정 = 물보라)
	var p: Player = r["player"]
	await _frames(60)
	var stone: Node2D = b._pick_stone()
	b._set_state(b.State.LANDED)
	b.global_position = b._stone_top_center(stone)
	b.velocity = Vector2.ZERO
	b._phase_end = b._clock + 99.0
	# 앞 시험(내려앉기) 동안 소녀가 곁에 서 있어 계량기가 차 이미 시작된 터뜨리기를 지운다 (이미 LANDED 면 _set_state 가 아무것도 안 한다)
	b.crowd.reset()
	b._burst_left = 0
	b._burst_done = false   # 터뜨리기는 내려앉음마다 한 번 — 앞 시험 동안 이미 터뜨렸으면 이 내려앉음엔 다시 안 한다
	b.hitbox.deactivate()
	b._tel.clear()
	await _frames(4)
	p.global_position = b.global_position + Vector2(-120, -70)
	await _measure("여왕 수액 터뜨리기(두 번)", r, func() -> void:
		b.crowd.set("t", b.crowd.trigger), 200, ["queen_land"], false, [0, 1])
	await _unload(r)


# ---------------- 무쇠 펌프 ----------------
func _pump() -> void:
	var r := await _load_room("flooded_mine_boss")
	var b: Node2D = r["boss"]
	var p: Player = r["player"]
	var pb: float = b.BEAT
	p.global_position = b.global_position + Vector2(-700, -4)
	await _measure("펌프 PISTON", r, func() -> void:
		b.facing = -1
		b.force_attack(b.State.PISTON), 130, ["pump_slam"], false)
	await _frames(40)
	await _measure("펌프 BITE", r, func() -> void:
		b.facing = -1
		b.force_attack(b.State.SUCK), 260, ["pump_bite"], false)
	await _frames(40)
	await _measure("펌프 VENT", r, func() -> void:
		b.facing = -1
		b.force_attack(b.State.VENT), 130, ["pump_vent"], false)
	await _frames(40)
	# 맞딜 응징 김 분출 (v1.1.0 맞딜 검수 2): 첫 분출 뒤에도 몸에 붙어 있으면 2박 뒤 한 번 더 (예고가 다시 차오른다)
	p.global_position = b.global_position + Vector2(-150, -4)
	await _frames(4)
	await _measure("펌프 김 분출(두 번)", r, func() -> void:
		b.facing = -1
		b.crowd.t = b.crowd.trigger
		b._choose_attack(), 200, ["pump_vent"], false, [0, 1])
	await _unload(r)

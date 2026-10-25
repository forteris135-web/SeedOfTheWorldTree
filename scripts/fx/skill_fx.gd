extends Node
## 보스 기술 이펙트 관찰자의 바탕 (2026-10-19 이펙트 리뉴얼 F2).
## 보스 논리 스크립트(_ready 의 한 줄)가 자식으로 붙인다:  add_child(preload("res://scripts/fx/bird_fx.gd").new())
## 보스의 공개 값(state·attack_phase·facing·phase …)을 매 물리 프레임 읽어, 상태가 바뀌는 순간과 공격 단계가 바뀌는 순간에
## 이펙트(Fx.spawn)를 띄운다. 판정·움직임은 건드리지 않는다 — 그림만.
## 왜 따로 두나: 보스 그림(뼈대)은 다른 묶음이 동시에 고치고 있어, 이펙트를 그림 스크립트에 넣지 않고 이 관찰자에 모았다.
##               보스 논리 스크립트에는 붙이는 한 줄만 들어간다.
## 자식은 부모 다음에 물리 프레임이 돈다 → 같은 프레임에 보스가 바꾼 값을 본다.
##
## 하위 클래스가 덮어쓰는 것:
##   _on_state(old, new)          상태가 바뀐 순간 (enum 정수)
##   _on_phase(state, old, new)   공격 단계(startup/active/recovery)가 바뀐 순간
##   _tick(delta)                 매 프레임 (이어지는 이펙트: 바람 줄기·불티 등)

var boss: Node2D
var _prev_state := -1
var _prev_phase := ""
var _timers := {}
var _names: Array = []   # 상태 번호 → 이름 (보스 스크립트의 enum State)


func _ready() -> void:
	boss = get_parent() as Node2D
	if boss == null:
		set_physics_process(false)
		return
	_prev_state = int(val("state", -1))
	var consts: Dictionary = boss.get_script().get_script_constant_map() if boss.get_script() else {}
	var e: Dictionary = consts.get("State", {})
	_names.resize(e.size())
	for k in e:
		_names[int(e[k])] = String(k)


func _physics_process(delta: float) -> void:
	if boss == null or not boss.visible:
		_prev_state = int(val("state", -1)) if boss else -1
		_prev_phase = ""
		return
	var st := int(val("state", -1))
	var ph := String(val("attack_phase", ""))
	if st != _prev_state:
		var old := _prev_state
		_prev_state = st
		_on_state(old, st)
		_on_common_state(st)
	if ph != _prev_phase:
		var oldp := _prev_phase
		_prev_phase = ph
		_on_phase(st, oldp, ph)
	_tick(delta)


func _on_state(_old: int, _new: int) -> void:
	pass


func _on_phase(_st: int, _old: String, _new: String) -> void:
	pass


func _tick(_delta: float) -> void:
	pass


## 공용: 무너짐·쓰러짐 이펙트 (보스마다 State 이름이 같다: BROKEN, FALLEN)
func _on_common_state(st: int) -> void:
	var name := state_is(st)
	if name == "BROKEN":
		Fx.spawn("boss_break", body_point(0.5))
	elif name == "FALLEN":
		Fx.spawn("boss_fall", boss.global_position + Vector2(0, -10))


## 상태 번호 → 이름 (보스마다 enum 이 달라 이름으로 비교한다)
func state_is(st: int) -> String:
	return String(_names[st]) if st >= 0 and st < _names.size() else ""


func state_name() -> String:
	return state_is(int(val("state", -1)))


## interval 초마다 한 번 true (이름별 시계). 이어지는 이펙트를 띄울 때 쓴다.
func every(key: String, interval: float, delta: float) -> bool:
	var t: float = _timers.get(key, 0.0) - delta
	if t <= 0.0:
		_timers[key] = interval
		return true
	_timers[key] = t
	return false


## 보스 몸의 한 점: 발밑(global_position)에서 키 height 의 frac 만큼 위
func body_point(frac: float, height := 300.0) -> Vector2:
	return boss.global_position + Vector2(0, -height * frac)


func facing() -> int:
	return int(val("facing", 1))


## 보스의 값 (없거나 null 이면 def). 보스 논리가 바뀌어 이름이 사라져도 이펙트 때문에 멈추지 않게.
func val(name: String, def: Variant = null) -> Variant:
	var v: Variant = boss.get(name)
	return def if v == null else v


## 붉은 예고(가드 불가) 중인가 — 보스의 is_red() (없으면 false)
func red() -> bool:
	return boss.has_method("is_red") and bool(boss.call("is_red"))


## 바라보는 쪽 기준의 자리 (dx 는 앞쪽 +)
func ahead(dx: float, dy: float) -> Vector2:
	return boss.global_position + Vector2(dx * facing(), dy)


## 보스 그림(부위 뼈대, 보스의 자식 Sprite)이 알려 주는 자리 — 창끝·부리·지팡이 머리·손·관 입 등 (각 그림의 fx_point 이름).
## 2026-10-20 통합: 예전엔 보스 원점·판정 상자에서 고정 거리로 띄웠다 → 뼈대가 실제로 움직이는 자리를 따라간다.
## 그림이 모르거나(이름 없음·뼈대 못 읽음) 보스에서 VIS_RANGE 넘게 먼 자리를 주면 fallback (예전 고정 자리) — 이펙트 때문에 멈추지 않게.
const VIS_RANGE := 1100.0
var _vis: Node = null


func vis_point(kind: String, fallback: Vector2) -> Vector2:
	if _vis == null or not is_instance_valid(_vis):
		_vis = boss.get_node_or_null("Sprite")
	if _vis and _vis.has_method("fx_point"):
		var p: Vector2 = _vis.call("fx_point", kind)
		if p.is_finite() and p.distance_to(boss.global_position) < VIS_RANGE:
			return p
	return fallback


## v1.1.0 (기획자 요청 1: 판정 = 예고 = 이펙트): 이펙트 그림을 월드 사각형(보통 근접 판정이 덮는 구간)에 맞춰 띄운다.
## 그림이 가장 커졌을 때(표의 scale 중 큰 값)의 그림 사각형이 target 과 같은 자리·크기가 되게 가로·세로 배율(scale_xy)과 자리를 정한다.
## rot_deg: 그림을 돌리는 각도(도, 오른쪽을 볼 때 — 표의 rot 는 무시하고 이 값을 쓴다). 돌린 그림의 바깥 사각형이 target 에 맞는다.
## opts 는 Fx.spawn 의 opts (facing·rot·scale_xy 는 여기서 정한다). 그림은 거의 꽉 찬 그림들이라(여백 3~5px) 그림 사각형 = 보이는 부분.
## opts.ground_y (월드 y) 를 주면 딸린 이펙트(바닥 고리·먼지·김)를 그림의 기준점 대신 그 바닥 높이에서 띄운다 —
## 판정 사각형에 맞춘 그림의 기준점(pivot)은 바닥보다 위에 오기 때문 (내려찍기 고리가 허리 높이에 떠 보이던 것, v1.1.0 검수).
func fit_fx(fx_name: String, target: Rect2, face: int, rot_deg := 0.0, opts := {}) -> FxSprite:
	var def: Dictionary = Fx.Table.EFFECTS.get(fx_name, {})
	if def.is_empty() or target.size.x <= 1.0 or target.size.y <= 1.0:
		return null
	var tk = def["tex"]
	var tex: Texture2D = Fx.texture(tk[0] if tk is Array else tk)
	if tex == null:
		return null
	var ts := tex.get_size()
	var sc: Array = def.get("scale", [1.0, 1.0])
	var smax := maxf(float(sc[0]), float(sc[1])) * float(opts.get("scale", 1.0))
	var sxy: Vector2 = def.get("scale_xy", Vector2.ONE)
	var f := 1.0 if face >= 0 else -1.0
	var th := deg_to_rad(rot_deg)
	var cs := absf(cos(th))
	var sn := absf(sin(th))
	# 돌린 그림의 바깥 사각형 = (w·cos + h·sin, w·sin + h·cos) → 원하는 크기가 되는 그림 가로·세로 크기 (W, H)
	var W := target.size.x
	var H := target.size.y
	var gw := W
	var gh := H
	var det := cs * cs - sn * sn
	if absf(th) > 0.01 and absf(det) > 0.2:
		gw = (W * cs - H * sn) / det
		gh = (H * cs - W * sn) / det
	if gw <= 4.0 or gh <= 4.0:
		gw = W
		gh = H
		th = 0.0
	var oxy := Vector2(gw / (ts.x * smax * absf(sxy.x)), gh / (ts.y * smax * absf(sxy.y)))
	# 가장 커졌을 때의 배율 (Fx 가 쓰는 것과 같다: 표 scale_xy × opts scale_xy × facing·뒤집기 × 표 scale)
	var flip := bool(def.get("flip_v", false)) != bool(opts.get("flip_v", false))
	var scl := Vector2(sxy.x * oxy.x * f * smax, sxy.y * oxy.y * (-1.0 if flip else 1.0) * smax)
	var pivot: Vector2 = def.get("pivot", Vector2(0.5, 0.5))
	var off := (Vector2(0.5, 0.5) - pivot) * ts   # 그림 가운데가 노드 자리에서 떨어진 만큼 (배율 전)
	var rot := th * f
	var center_off := (off * scl).rotated(rot)
	var o: Dictionary = opts.duplicate()
	o["facing"] = f
	o["scale_xy"] = oxy
	o["rot"] = rot_deg - float(def.get("rot", 0.0))
	var at := target.get_center() - center_off
	var fol = opts.get("follow", null)
	if fol is Node2D and is_instance_valid(fol):
		# 따라다니는 이펙트 (돌진 등): 보스에서 떨어진 만큼을 offset 으로 (Fx 가 바라보는 쪽에 맞춰 뒤집으므로 x 는 미리 되돌린다)
		var rel: Vector2 = at - (fol as Node2D).global_position
		o["offset"] = Vector2(rel.x * f, rel.y)
	if not opts.has("ground_y"):
		return Fx.spawn(fx_name, at, o)
	o.erase("ground_y")
	o["children"] = false
	var main := Fx.spawn(fx_name, at, o)
	_spawn_children(def, Vector2(at.x, float(opts["ground_y"])), f, opts)
	return main


## 표의 딸린 이펙트를 origin 에서 띄운다 (Fx.spawn 의 딸린 이펙트와 같은 규칙: 개수·퍼짐·offset·팔레트·크기 물려받기)
func _spawn_children(def: Dictionary, origin: Vector2, f: float, opts: Dictionary) -> void:
	for ch in def.get("children", []):
		var cname: String = ch[0]
		var count: int = ch[1] if ch.size() > 1 else 1
		var spread: Vector2 = ch[2] if ch.size() > 2 else Vector2.ZERO
		var copts: Dictionary = (ch[3] as Dictionary).duplicate() if ch.size() > 3 else {}
		copts["facing"] = f * float(copts.get("facing", 1.0))
		if opts.has("palette") and not copts.has("palette"):
			copts["palette"] = opts["palette"]
		if opts.has("scale"):
			copts["scale"] = float(copts.get("scale", 1.0)) * float(opts["scale"])
		var coff: Vector2 = copts.get("offset", Vector2.ZERO)
		copts.erase("offset")
		for i in count:
			var jitter := Vector2(randf_range(-spread.x, spread.x), randf_range(-spread.y, spread.y))
			Fx.spawn(cname, origin + Vector2(coff.x * f, coff.y) + jitter, copts)

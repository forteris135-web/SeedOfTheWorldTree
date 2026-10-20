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

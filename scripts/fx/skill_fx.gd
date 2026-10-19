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
	_prev_state = int(boss.get("state"))
	var consts: Dictionary = boss.get_script().get_script_constant_map() if boss.get_script() else {}
	var e: Dictionary = consts.get("State", {})
	_names.resize(e.size())
	for k in e:
		_names[int(e[k])] = String(k)


func _physics_process(delta: float) -> void:
	if boss == null or not boss.visible:
		_prev_state = int(boss.get("state")) if boss else -1
		_prev_phase = ""
		return
	var st := int(boss.get("state"))
	var ph := String(boss.get("attack_phase")) if "attack_phase" in boss else ""
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
	return state_is(int(boss.get("state")))


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
	return int(boss.get("facing"))


## 바라보는 쪽 기준의 자리 (dx 는 앞쪽 +)
func ahead(dx: float, dy: float) -> Vector2:
	return boss.global_position + Vector2(dx * facing(), dy)

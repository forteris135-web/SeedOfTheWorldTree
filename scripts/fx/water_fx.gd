extends Node
## 수액·물 웅덩이의 물 이펙트 (2026-10-19 이펙트 리뉴얼 F2). sap_pool.gd 의 _ready 가 자식으로 붙인다 (판정과 무관).
##  - 소녀가 웅덩이에 들어설 때·내려앉을 때: 물보라 + 방울 + 물결 (떨어지는 빠르기가 클수록 크게)
##  - 걷거나 달리는 동안: 발 자리 수면에 잔물결 (STEP_GAP 마다)
##  - 뛰어오를 때·웅덩이를 박차고 나갈 때: 왕관 물보라
##  - 가끔 위에서 수액 방울이 떨어져 수면에 물결을 남긴다 (웅덩이가 화면에 보일 때만)
## 웅덩이(SapPool)의 수면 높이는 정화되면 FILL_RISE 만큼 차오르므로 그 값을 따른다.

const STEP_GAP := 0.2
const RUN_SPEED := 80.0
const JUMP_SPEED := -260.0
## 떨어지는 방울: 간격(초)과 떨어지는 높이 (Fx "drip_fall" 의 수명·중력과 맞춘다)
const DRIP_GAP := Vector2(1.3, 2.8)
const DRIP_LIFE := 0.6
const DRIP_HEIGHT := 336.0

var pool: Area2D
var _tracks := {}        # 소녀 id → {"in", "floor", "step"}
var _drip_t := 1.0
var _pending: Array = [] # [남은 시간, 자리] — 떨어지는 방울이 수면에 닿을 때 물결


func _ready() -> void:
	pool = get_parent() as Area2D
	_drip_t = randf_range(0.5, DRIP_GAP.y)
	if pool == null:
		set_physics_process(false)


func surface_y() -> float:
	var rise := 0.0
	if "_alive" in pool:
		rise = float(pool.get("_alive")) * float(pool.get("FILL_RISE"))
	return pool.global_position.y - rise + 4.0


func _physics_process(delta: float) -> void:
	var sy := surface_y()
	var seen := {}
	for b in pool.get_overlapping_bodies():
		if not (b is CharacterBody2D) or not b.is_in_group("player"):
			continue
		var id := b.get_instance_id()
		seen[id] = true
		var on_floor: bool = b.is_on_floor()
		var vel: Vector2 = b.velocity
		var x: float = b.global_position.x
		var tr: Dictionary = _tracks.get(id, {})
		if tr.is_empty():
			# 들어섰다
			tr = {"in": true, "floor": on_floor, "step": STEP_GAP}
			_tracks[id] = tr
			Fx.spawn("water_splash_in", Vector2(x, sy), {"scale": clampf(0.8 + absf(vel.y) / 1400.0, 0.8, 1.5)})
			continue
		if on_floor and not bool(tr["floor"]):
			Fx.spawn("water_splash_in", Vector2(x, sy), {"scale": 0.9})   # 내려앉음
		elif not on_floor and bool(tr["floor"]) and vel.y < JUMP_SPEED:
			Fx.spawn("water_jump", Vector2(x, sy))   # 뛰어오름
		tr["floor"] = on_floor
		if on_floor and absf(vel.x) > RUN_SPEED:
			tr["step"] = float(tr["step"]) - delta
			if float(tr["step"]) <= 0.0:
				tr["step"] = STEP_GAP * (0.75 if absf(vel.x) > 500.0 else 1.0)
				Fx.spawn("water_ripple", Vector2(x + signf(vel.x) * 10.0, sy))
	# 나갔다: 위로 박차고 나가면 물보라
	for id in _tracks.keys():
		if not seen.has(id):
			var obj := instance_from_id(id) as CharacterBody2D
			if obj and is_instance_valid(obj) and obj.velocity.y < -100.0:
				Fx.spawn("water_jump", Vector2(obj.global_position.x, sy))
			_tracks.erase(id)
	_tick_drips(delta, sy)


func _tick_drips(delta: float, sy: float) -> void:
	var i := _pending.size() - 1
	while i >= 0:
		_pending[i][0] -= delta
		if _pending[i][0] <= 0.0:
			Fx.spawn("water_ripple", Vector2(_pending[i][1], sy), {"scale": 0.8})
			_pending.remove_at(i)
		i -= 1
	_drip_t -= delta
	if _drip_t > 0.0:
		return
	_drip_t = randf_range(DRIP_GAP.x, DRIP_GAP.y)
	var w := float(pool.get("size").x) if "size" in pool else 300.0
	var x := pool.global_position.x + randf_range(w * 0.08, w * 0.92)
	if not _on_screen(Vector2(x, sy)):
		return
	Fx.spawn("drip_fall", Vector2(x, sy - DRIP_HEIGHT), {"life": DRIP_LIFE})
	_pending.append([DRIP_LIFE, x])


## 화면(카메라)에 보이는 자리인가. 카메라가 없으면(시험 등) 보인다고 친다.
func _on_screen(p: Vector2) -> bool:
	var vp := pool.get_viewport()
	if vp == null:
		return true
	var cam := vp.get_camera_2d()
	if cam == null:
		return true
	var half := vp.get_visible_rect().size * 0.5 / cam.zoom
	var c := cam.get_screen_center_position()
	return absf(p.x - c.x) < half.x + 60.0 and absf(p.y - c.y) < half.y + 200.0

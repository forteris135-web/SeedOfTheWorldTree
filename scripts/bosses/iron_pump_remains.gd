extends Node2D
## 정화된 뒤 멈춰 선 무쇠 펌프와 그 위에 튼 싹 (EXPANSION.md 4장 "펌프가 멈춰 서고 그 위로 싹이 튼다").
## 보스 방에서 깃발 boss_pump_defeated 가 서 있을 때만 보인다 (IronPumpRoom 이 켠다). 원점은 발(땅).
## 정화하는 순간에는 IronPumpRoom 이 match_pose() 로 쓰러진 보스의 자세를 그대로 옮겨 받고 sprout() 를 불러,
## 빛으로 흩어지는 펌프 자리에 같은 자세의 멈춘 펌프가 식어 가며 싹이 자라난다 (회상 전).
## 그림은 보스와 같은 부위 뼈대(art/rigs/iron_pump)를 '쓰러져 엎드린 자세(dead)'로 한 번만 세우고 멈춰 둔다 (매 프레임 움직이지 않는다).
## 예전 그림처럼 기본은 왼쪽을 본다 — 방이 이 노드의 scale.x 로 보스가 보던 쪽에 맞춘다.

const RIG_ID := "iron_pump"
## 멈춘 기계: 식어서 잿빛
const COOL := Color(0.82, 0.79, 0.76)

var _t := 0.0
## 싹이 자란 정도 (0 → 1). sprout() 가 0 에서 키운다.
var grow := 1.0
var rig: PartRig
var _motion: RigMotion
var _sprout: Node2D
var _motes: CPUParticles2D
## 싹이 트는 자리(높은 탱크 꼭대기)와 식은 핵 자리 — 이 노드의 지역 좌표
var _top := Vector2(0, -300)
var _core := Vector2(0, -140)


func _ready() -> void:
	rig = PartRig.new()
	rig.name = "Rig"
	add_child(rig)
	if rig.build(RIG_ID):
		rig.scale = Vector2(-1, 1)
		rig.material = preload("res://shaders/ash_purify.tres")
		rig.modulate = COOL
		_motion = RigMotion.new(rig)
		_motion.breath = 0.0
		_motion.ground_lock = 1.0
		_motion.ground_settle = 1.0
		_motion.set_target(_motion.pose("dead"), RigMotion.Drive.NORMAL, RigMotion.Feet.POSE)
		_motion.snap_feet()
		for i in 120:
			_motion.update(1.0 / 60.0, {})
		_find_points()
	_sprout = Node2D.new()
	_sprout.name = "Sprout"
	_sprout.draw.connect(_draw_sprout)
	add_child(_sprout)
	_motes = CPUParticles2D.new()
	_motes.amount = 10
	_motes.lifetime = 3.0
	_motes.preprocess = 3.0
	_motes.position = _top + Vector2(0, -30)
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_motes.emission_sphere_radius = 40.0
	_motes.direction = Vector2(0, -1)
	_motes.spread = 40.0
	_motes.gravity = Vector2(0, -12)
	_motes.initial_velocity_min = 8.0
	_motes.initial_velocity_max = 24.0
	_motes.scale_amount_min = 1.5
	_motes.scale_amount_max = 3.0
	_motes.color = Color(0.7, 1.0, 0.75, 0.7)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_motes.material = add
	add_child(_motes)


## 쓰러진 보스 그림(IronPumpVisual)의 지금 자세를 그대로 옮겨 받는다 (같은 뼈대라 배열을 그대로 복사).
func match_pose(vis: Node) -> void:
	if rig == null or vis == null or not ("rig" in vis):
		return
	var src: PartRig = vis.rig
	if src == null or src.rot.size() != rig.rot.size():
		return
	rig.rot = src.rot.duplicate()
	rig.off = src.off.duplicate()
	rig.scl = src.scl.duplicate()
	rig.squash_y = src.squash_y.duplicate()
	rig.root_pos = src.root_pos
	rig.body_xf = src.body_xf
	rig.apply()
	_find_points()


func _find_points() -> void:
	var socks: Dictionary = rig.data.get("sockets", {})
	for pair in [["tank_top", "_top"], ["core", "_core"]]:
		var sd = socks.get(pair[0])
		if sd is Dictionary:
			set(pair[1], rig.transform * rig.bone_point(str(sd["bone"]), PartRig._v(sd["pos"])))
	if _motes:
		_motes.position = _top + Vector2(0, -30)


func _process(delta: float) -> void:
	_t += delta
	_sprout.queue_redraw()


## 탱크 위에서 자라난 싹: 줄기와 잎 둘, 끝에 작은 빛 + 식은 핵의 희미한 초록빛
func _draw_sprout() -> void:
	_sprout.draw_circle(_core, 40.0, Color(0.5, 0.9, 0.7, 0.12 + 0.05 * sin(_t * 1.6)))
	var g := clampf(grow, 0.0, 1.0)
	if g <= 0.01:
		return
	var top := _top + Vector2(0, 4)
	var sway := sin(_t * 1.1) * 0.06
	_sprout.draw_circle(top + Vector2(0, -40), 70.0, Color(0.44, 0.81, 0.59, 0.1))
	var tip := top + Vector2(sway * 60.0, -90.0 * g)
	_sprout.draw_line(top, tip, Color(0.31, 0.68, 0.48), 7.0, true)
	_sprout.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, 30), tip + Vector2(-46, -6), tip + Vector2(-10, -26)]), Color(0.44, 0.81, 0.59))
	_sprout.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, 16), tip + Vector2(44, -24), tip + Vector2(12, -34)]), Color(0.44, 0.81, 0.59))
	_sprout.draw_circle(tip + Vector2(0, -8), 7.0, Color(1.0, 0.83, 0.42))


## 정화하는 순간의 연출: 멈춘 펌프가 나타나 식어 가고(밝게 → 잿빛), 그 위로 싹이 자란다.
func sprout(duration := 1.6) -> void:
	visible = true
	grow = 0.0
	modulate = Color(1, 1, 1, 0)
	if rig:
		rig.modulate = Color(1.6, 1.6, 1.5)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, duration * 0.5)
	if rig:
		tw.tween_property(rig, "modulate", COOL, duration).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "grow", 1.0, duration * 0.8).set_delay(duration * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

class_name Hitbox
extends Area2D
## 때리는 영역. activate() 로 잠깐 켜지고, 겹친 Hurtbox 마다 한 번씩만 맞춘다.

## (결과 문자열, 맞은 대상) — 결과: "hit", "guard", "just_guard", "guard_break", "dodge", "ignored"
signal landed(result: String, target: Node)

var hit: HitData
var _active := false
var _targets: Array = []
var _timer := 0.0
var _shape: CollisionShape2D


func _ready() -> void:
	monitoring = false
	monitorable = false
	_shape = CollisionShape2D.new()
	_shape.shape = RectangleShape2D.new()
	add_child(_shape)


## 바라보는 방향 기준(오른쪽) 사각형을 facing 에 맞춰 뒤집어 놓는다.
func set_box(rect: Rect2, facing: int) -> void:
	var r: RectangleShape2D = _shape.shape
	r.size = rect.size
	var center := rect.get_center()
	_shape.position = Vector2(center.x * facing, center.y)


func activate(data: HitData, duration: float) -> void:
	hit = data
	_active = true
	_targets.clear()
	_timer = duration
	monitoring = true


func deactivate() -> void:
	_active = false
	monitoring = false


func _physics_process(delta: float) -> void:
	if not _active:
		return
	for area in get_overlapping_areas():
		if area is Hurtbox and not _targets.has(area):
			_targets.append(area)
			var result: String = area.receive(hit)
			landed.emit(result, area.owner_node)
	_timer -= delta
	if _timer <= 0.0:
		deactivate()

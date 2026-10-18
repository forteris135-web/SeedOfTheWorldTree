extends Camera2D
## 소녀를 따라가는 카메라. 바라보는 방향으로 조금 앞을 보여 주고, 방의 경계 안에만 머문다.

## 바라보는 방향으로 앞서 보여 주는 거리 (픽셀).
@export var look_ahead := 150.0
## 앞보기가 옮겨 가는 빠르기.
@export var look_ahead_speed := 2.5
## 화면 중심을 소녀보다 이만큼 위에 둔다 (음수 = 위).
@export var vertical_offset := -110.0

var _look := 0.0
var _shake := 0.0


## 기본 확대 배율 (기획자 요청: 살짝 확대).
@export var base_zoom := 1.15


func _ready() -> void:
	position_smoothing_enabled = true
	limit_smoothed = true
	zoom = Vector2(base_zoom, base_zoom)


func _process(delta: float) -> void:
	var player := get_parent() as Player
	if player == null:
		return
	var target := player.facing * look_ahead
	_look = lerpf(_look, target, 1.0 - exp(-look_ahead_speed * delta))
	_shake = maxf(_shake - delta * 28.0, 0.0)
	var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	offset = Vector2(_look, vertical_offset) + jitter


## 방이 카메라 경계를 정해 준다.
func set_room_bounds(rect: Rect2) -> void:
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)
	reset_smoothing()


## 화면을 잠깐 흔든다 (픽셀 단위 세기).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

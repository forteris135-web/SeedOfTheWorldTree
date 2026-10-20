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
## 보스 등장 구도 (2026-10-20 검수): 이름 카드가 뜨는 동안 카메라를 소녀와 보스 가운데로 잠깐 옮긴다 —
## 보스가 화면 오른쪽 끝에 반쯤 잘려 터치 버튼 뒤에 가려졌다. frame_with(보스, 머무는 시간)으로 켠다. 판정·조작과는 상관없다.
var _focus: Node2D
var _focus_w := 0.0
var _focus_tw: Tween


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
	# 앞보기와 위쪽 보기는 카메라 자리(소녀 기준)로 옮긴다. Camera2D.offset 은 방 경계를 맞춘 '뒤에' 더해져
	# 경계를 넘어 버리기 때문에, 바닥에 서 있을 때 소녀가 화면 맨 아래(보스 체력 바 뒤)로 밀려났다.
	var at := Vector2(_look, vertical_offset)
	if _focus_w > 0.001 and is_instance_valid(_focus):
		var mid := (_focus.global_position - player.global_position) * 0.5
		at = at.lerp(Vector2(mid.x, vertical_offset + minf(mid.y, 0.0) * 0.5), _focus_w)
	position = at
	offset = jitter


## 보스 등장: blend_in 초 동안 소녀와 target 의 가운데로 옮겨 hold 초 머물렀다가 blend_out 초에 소녀 쪽으로 돌아온다.
func frame_with(target: Node2D, hold := 1.6, blend_in := 0.6, blend_out := 0.9) -> void:
	_focus = target
	if _focus_tw:
		_focus_tw.kill()
	_focus_tw = create_tween()
	_focus_tw.tween_property(self, "_focus_w", 1.0, blend_in).set_trans(Tween.TRANS_SINE)
	_focus_tw.tween_interval(hold)
	_focus_tw.tween_property(self, "_focus_w", 0.0, blend_out).set_trans(Tween.TRANS_SINE)


## 등장 구도를 바로 끈다 (싸움이 되돌려질 때)
func clear_focus() -> void:
	if _focus_tw:
		_focus_tw.kill()
	_focus_tw = null
	_focus_w = 0.0
	_focus = null


## 방의 경계 (set_room_bounds 로 받은 원래 값)
var _room_rect := Rect2()


## 방이 카메라 경계를 정해 준다.
func set_room_bounds(rect: Rect2) -> void:
	_room_rect = rect
	limit_left = int(rect.position.x)
	limit_top = int(rect.position.y)
	limit_right = int(rect.end.x)
	limit_bottom = int(rect.end.y)
	reset_smoothing()


## 보스전 레터박스: 화면 아래 inset_px 만큼이 띠로 가려지므로, 소녀가 서는 바닥(ground_y)이 띠 위에 오도록
## 아래 경계를 필요한 만큼 내린다 (바닥 아래로 띠 높이 + 여유 60px 의 세계 거리를 확보). 끝나면 restore_bounds().
func keep_floor_above(ground_y: float, inset_px: float, zoom_y: float) -> void:
	var need := inset_px / maxf(zoom_y, 0.01) + 60.0
	var want := int(ground_y + need)
	if want > limit_bottom:
		limit_bottom = want


func restore_bounds() -> void:
	if _room_rect.size != Vector2.ZERO:
		limit_bottom = int(_room_rect.end.y)


## 화면을 잠깐 흔든다 (픽셀 단위 세기).
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)

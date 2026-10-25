extends Node2D
class_name BlurWheel
## 뿌리지기 방(심연 · 정원의 끝) 배경에 흐릿하게 천천히 도는 물레방아 (v1.1.0 기획자 요청 28).
## 진엔딩 장치 그림의 톱니 테·바퀴살·굴대를 장치와 같은 비율로 미리 겹친 한 장(object_choice_pump_wheel.png —
## tools/cut_ending_devices.gd)을 돌린다. 반투명으로 그려도 테 뒤 바퀴살이 비치지 않고, 그림 한 장·계산 한 번이라 가볍다.
## 흐림은 밉맵 단계로(shaders/blur_lod.gdshader). 정화 잿빛 재질(ash_purify)은 쓰지 않고, 같은 셰이더의 ash 값으로 따라간다:
## 잿빛(Purity.level 0)에서는 무채색 회색으로(잿빛 배경 속에 혼자 갈색 얼룩으로 튀지 않게), 정화되면 원래 색을 alive_bright 배
## 밝게(어두운 배경에 묻히지 않게) — v1.1.0 검수. 물결(play_purify)이 지나가는 동안 Purity.level 을 따라 서서히 바뀐다.
## 부모 Parallax2D 의 비율로 '카메라가 방 한가운데를 볼 때 화면 가운데 + screen_offset' 자리에 둔다 (BackdropUtil.center_of).

const WHEEL_TEX := preload("res://art/objects/object_choice_pump_wheel.png")
const BLUR_SHADER := preload("res://shaders/blur_lod.gdshader")

## 도는 빠르기 (rad/s, 음수면 반대로)
@export var speed := 0.10
## 흐림 정도 (밉맵 단계)
@export var blur := 2.5
## 바퀴 지름 (월드 px — 평소 카메라 1.15배·싸움 0.88배라 화면에서는 약 600~780px)
@export var diameter := 680.0
## 화면 가운데에서 비켜 둘 자리 (월드 px, 오른쪽 + / 아래 +)
@export var screen_offset := Vector2(320, -60)
## 색·진하기 (어두운 푸른빛, 반투명)
@export var tint := Color(0.55, 0.62, 0.70, 0.55)
## 잿빛일 때 무채색에 섞는 회색(잿빛 배경 아지랑이 쪽)과 그 비율
@export var ash_color := Color(0.50, 0.50, 0.55)
@export var ash_mix := 0.22
## 정화된 뒤 밝기 배수 (1 = 그림 그대로 × tint)
@export var alive_bright := 1.8

var _sprite: Sprite2D
var _mat: ShaderMaterial
var _level := -1.0


func _ready() -> void:
	var room := BackdropUtil.room_bounds(self)
	position = BackdropUtil.center_of(self, room) + screen_offset
	modulate = tint
	_sprite = Sprite2D.new()
	_sprite.texture = WHEEL_TEX
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var mat := ShaderMaterial.new()
	mat.shader = BLUR_SHADER
	mat.set_shader_parameter("blur", blur)
	mat.set_shader_parameter("ash_color", Vector3(ash_color.r, ash_color.g, ash_color.b))
	mat.set_shader_parameter("ash_mix", ash_mix)
	_sprite.material = mat
	_mat = mat
	_apply_purity()
	var k := diameter / float(WHEEL_TEX.get_width())
	_sprite.scale = Vector2(k, k)
	add_child(_sprite)


func _process(delta: float) -> void:
	_sprite.rotation = wrapf(_sprite.rotation + speed * delta, -PI, PI)
	_apply_purity()


## 지금 방의 정화 정도(Purity.level: 0 잿빛 ~ 1 정화)를 셰이더에 (바뀔 때만)
func _apply_purity() -> void:
	if _mat == null:
		return
	var lv := clampf(Purity.level, 0.0, 1.0)
	if is_equal_approx(lv, _level):
		return
	_level = lv
	_mat.set_shader_parameter("ash", 1.0 - lv)
	_mat.set_shader_parameter("bright", lerpf(1.0, alive_bright, lv))


## 시험용: 지금 돌아간 각도
func angle() -> float:
	return _sprite.rotation if _sprite else 0.0

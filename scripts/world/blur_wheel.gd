extends Node2D
class_name BlurWheel
## 뿌리지기 방(심연 · 정원의 끝) 배경에 흐릿하게 천천히 도는 물레방아 (v1.1.0 기획자 요청 28).
## 진엔딩 장치 그림의 톱니 테·바퀴살·굴대를 장치와 같은 비율로 미리 겹친 한 장(object_choice_pump_wheel.png —
## tools/cut_ending_devices.gd)을 돌린다. 반투명으로 그려도 테 뒤 바퀴살이 비치지 않고, 그림 한 장·계산 한 번이라 가볍다.
## 흐림은 밉맵 단계로(shaders/blur_lod.gdshader). 어두운 배경의 고정색이다 (정화 잿빛 재질은 쓰지 않는다).
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

var _sprite: Sprite2D


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
	_sprite.material = mat
	var k := diameter / float(WHEEL_TEX.get_width())
	_sprite.scale = Vector2(k, k)
	add_child(_sprite)


func _process(delta: float) -> void:
	_sprite.rotation = wrapf(_sprite.rotation + speed * delta, -PI, PI)


## 시험용: 지금 돌아간 각도
func angle() -> float:
	return _sprite.rotation if _sprite else 0.0

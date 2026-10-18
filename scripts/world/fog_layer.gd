extends Sprite2D
## 흐르는 안개 한 겹. 이음매 없는 노이즈 그림을 천천히 밀어서 흐르게 한다.

@export var drift := Vector2(18, -4)       # 초당 흐르는 속도 (픽셀)
@export var fog_color := Color(1.0, 0.95, 0.82, 0.13)
@export var noise_scale := 1.0             # 클수록 큰 덩어리
@export var seed := 3

var _offset := Vector2.ZERO


func _ready() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.004 / noise_scale
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.55
	var tex := NoiseTexture2D.new()
	tex.width = 768
	tex.height = 768
	tex.seamless = true
	tex.seamless_blend_skirt = 0.25
	tex.noise = noise
	# 안개답게 밝은 부분만 남긴다
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.35, 0.6, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 1)])
	tex.color_ramp = grad
	texture = tex
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	region_enabled = true
	var room := BackdropUtil.room_bounds(self)
	var need := BackdropUtil.cover_size(self, room)
	region_rect = Rect2(Vector2.ZERO, need)
	position = BackdropUtil.center_of(self, room)
	modulate = fog_color
	material = preload("res://shaders/ash_purify.tres")


func _process(delta: float) -> void:
	_offset += drift * delta
	region_rect.position = _offset

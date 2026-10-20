extends Sprite2D
## 흐르는 안개 한 겹. 이음매 없는 노이즈 그림을 천천히 밀어서 흐르게 한다.

@export var drift := Vector2(18, -4)       # 초당 흐르는 속도 (픽셀)
@export var fog_color := Color(1.0, 0.95, 0.82, 0.13)
@export var noise_scale := 1.0             # 클수록 큰 덩어리
@export var seed := 3

var _offset := Vector2.ZERO

## 안개 그림 크기 (이음매 없이 반복된다)
const TEX_SIZE := 768
## 모든 방이 같이 쓰는 안개 그림 (noise_scale 별 하나). 노이즈 그림은 처음 그릴 때
## 메인 스레드에서 만들어져 한 겹에 약 85ms 가 걸렸다 — 방마다 새로 만들지 않고 한 번만 만든다.
static var _tex_cache := {}


## noise_scale 에 맞는 안개 그림 (한 번만 만들고 나눠 쓴다)
static func shared_texture(scale: float) -> Texture2D:
	var key := snappedf(scale, 0.01)
	if _tex_cache.has(key):
		return _tex_cache[key]
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.004 / scale
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.55
	var tex := NoiseTexture2D.new()
	tex.width = TEX_SIZE
	tex.height = TEX_SIZE
	tex.seamless = true
	tex.seamless_blend_skirt = 0.25
	tex.noise = noise
	# 안개답게 밝은 부분만 남긴다
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.35, 0.6, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 1)])
	tex.color_ramp = grad
	_tex_cache[key] = tex
	return tex


func _ready() -> void:
	var tex := shared_texture(noise_scale)
	# 방마다 무늬가 달라 보이도록 seed 로 흘리기 시작하는 자리를 바꾼다
	_offset = Vector2(fposmod(seed * 197.0, TEX_SIZE), fposmod(seed * 311.0, TEX_SIZE))
	texture = tex
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	region_enabled = true
	var room := BackdropUtil.room_bounds(self)
	var need := BackdropUtil.cover_size(self, room)
	region_rect = Rect2(_offset, need)
	position = BackdropUtil.center_of(self, room)
	modulate = fog_color
	material = preload("res://shaders/ash_purify.tres")


func _process(delta: float) -> void:
	_offset += drift * delta
	region_rect.position = _offset

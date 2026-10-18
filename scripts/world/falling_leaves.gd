extends CPUParticles2D
## 천천히 떨어지는 잎. 잎 모양 그림은 코드로 만든다.

@export var leaf_color := Color(0.78, 0.74, 0.46, 0.9)
@export var count := 36


func _ready() -> void:
	var room := BackdropUtil.room_bounds(self)
	var need := BackdropUtil.cover_size(self, room)
	position = BackdropUtil.center_of(self, room)
	texture = _make_leaf_texture()
	amount = count
	lifetime = 11.0
	preprocess = 11.0
	emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	emission_rect_extents = need / 2.0
	direction = Vector2(0.3, 1)
	spread = 30.0
	gravity = Vector2(0, 14)
	initial_velocity_min = 15.0
	initial_velocity_max = 45.0
	angular_velocity_min = -90.0
	angular_velocity_max = 90.0
	angle_min = 0.0
	angle_max = 360.0
	scale_amount_min = 0.5
	scale_amount_max = 1.0
	# 좌우로 흔들리며 떨어지게
	var curve := Curve.new()
	curve.add_point(Vector2(0, -1))
	curve.add_point(Vector2(0.5, 1))
	curve.add_point(Vector2(1, -1))
	tangential_accel_min = -20.0
	tangential_accel_max = 20.0
	color = leaf_color
	material = preload("res://shaders/ash_purify.tres")


func _make_leaf_texture() -> ImageTexture:
	var w := 28
	var h := 16
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (float(x) / w) * 2.0 - 1.0
			var v := (float(y) / h) * 2.0 - 1.0
			# 잎 모양: 한쪽이 뾰족한 타원
			var leaf := u * u + v * v * (1.6 + 0.8 * u)
			if leaf < 1.0:
				var shade := 0.85 + 0.15 * (1.0 - absf(v))
				img.set_pixel(x, y, Color(shade, shade, shade, 1.0))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)

extends Sprite2D
## 진짜 배경 그림 한 장. 부모 Parallax2D 의 비율에 맞춰 화면과 방 이동량을 덮도록 키운다.
## 정화 전에는 잿빛으로 보이게 공용 재질(ash_purify)을 쓴다.

## 그림 아래쪽을 조금 더 보여 주고 싶으면 음수, 위쪽이면 양수 (0~1, 세로 비율).
@export var vertical_bias := 0.0


func _ready() -> void:
	if texture == null:
		return
	var room := BackdropUtil.room_bounds(self)
	var need := BackdropUtil.cover_size(self, room)
	var tex := texture.get_size()
	var s := maxf(need.x / tex.x, need.y / tex.y)
	scale = Vector2(s, s)
	position = BackdropUtil.center_of(self, room) + Vector2(0, vertical_bias * tex.y * s)
	material = preload("res://shaders/ash_purify.tres")
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

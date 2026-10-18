class_name BackdropUtil
## 배경 겹들이 공통으로 쓰는 계산. 부모 Parallax2D 의 비율과 방의 크기로 "덮어야 하는 크기"를 낸다.

## 화면(아이패드 세로까지 넉넉히 2600×1900)에, 방 안에서 카메라가 움직이는 만큼 × 원근 비율을 더한 크기.
static func cover_size(node: Node, room: Rect2) -> Vector2:
	return Vector2(2600, 1900) + room.size * scroll_scale_of(node)


static func scroll_scale_of(node: Node) -> Vector2:
	var p := node.get_parent()
	while p:
		if p is Parallax2D:
			return (p as Parallax2D).scroll_scale
		p = p.get_parent()
	return Vector2.ONE


## 이 겹의 중심이 있어야 할 자리.
## Parallax2D 는 화면 왼쪽 위 모서리를 기준으로 (1 - 비율)만큼 따라 움직이므로,
## 카메라가 방 한가운데를 볼 때 겹의 중심이 화면 중심에 오도록 맞춘다.
static func center_of(node: Node, room: Rect2) -> Vector2:
	var half := Vector2(960, 540)  # 기준 화면(1920×1080)의 절반
	return half + (room.get_center() - half) * scroll_scale_of(node)


## 위로 올라가며 Room 을 찾아 경계를 돌려준다.
static func room_bounds(node: Node) -> Rect2:
	var p := node.get_parent()
	while p:
		if p is Room:
			return (p as Room).bounds
		p = p.get_parent()
	return Rect2(0, 0, 4800, 2400)

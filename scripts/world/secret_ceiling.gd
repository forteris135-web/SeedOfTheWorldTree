extends SecretWall
class_name SecretCeiling
## 비밀 천장. 천장에 매달린 옹이 덩어리. 소녀가 아래에서 점프해 **머리를 부딪치면** 부서지고,
## 안에 숨어 있던 아이템이 바닥으로 떨어진다. 공격으로는 부서지지 않는다.
## 단서: 아래쪽에 실금이 희미하게 빛나고 가끔 먼지가 떨어진다.
## 판정은 player.gd 가 move_and_slide() 뒤 is_on_ceiling() + 올라가던 속도로 보고 on_head_bump() 를 부른다.


func _init() -> void:
	breaks_by_attack = false


func _ready() -> void:
	super()   # 사각형 충돌 + 먼지 + 씨앗값(_rng_seed)
	# 충돌 모양을 그림(아래가 둥근 옹이)과 똑같이 맞춘다. 사각형 그대로면 양 끝 밑에서 '허공'에 머리를 박는다.
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng_seed
	var poly := ConvexPolygonShape2D.new()
	poly.set_point_cloud(_body_polygon(rng))   # 점 구름 → 볼록 껍질 (지터가 있어도 안전)
	for c in get_children():
		if c is CollisionShape2D:
			c.shape = poly
			c.position = Vector2.ZERO   # 사각형은 size/2 가운데였으므로 원점으로
			break


## 소녀가 아래에서 머리를 박았다 (player.gd 가 부른다). speed = 올라가던 속도(px/s).
func on_head_bump(_player: Node, speed: float) -> void:
	if _broken or speed < 150.0:
		return
	_break()


## 먼지는 아래쪽 가장자리에서 떨어진다.
func _dust_origin() -> Vector2:
	return Vector2(size.x / 2.0, size.y - 4.0)


## 매달린 옹이: 위는 천장에 붙어 넓고, 아래로 갈수록 둥글게 모인다. (_draw 와 충돌 모양이 같은 점을 쓴다)
func _body_polygon(rng: RandomNumberGenerator) -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var pts := PackedVector2Array()
	pts.append(Vector2(0, 0))
	pts.append(Vector2(w, 0))
	# 오른쪽 옆선 → 둥근 바닥 → 왼쪽 옆선
	var n := 9
	for i in n + 1:
		var t := float(i) / n           # 0 = 오른쪽 위, 1 = 왼쪽 위 (아랫선을 따라)
		var a := PI * t                 # 0 → PI
		var x := w * 0.5 + cos(a) * w * 0.5
		var y := h * 0.62 + sin(a) * h * 0.38 + rng.randf_range(-3, 3)
		pts.append(Vector2(x, y))
	return pts

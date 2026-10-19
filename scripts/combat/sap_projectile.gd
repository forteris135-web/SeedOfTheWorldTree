extends Projectile
class_name SapProjectile
## 수액의 여왕이 쓰는 투사체 (확장판). 바탕(Projectile)의 날아가기·맞추기·되받기는 그대로 쓰고 그림만 바꾼다.
##  - "dust"      날개가루: 반짝이는 작은 가루 알갱이. 천천히 떨어진다(fall_gravity). 가드 가능, 되받기 불가.
##  - "butterfly" 작은 수액 나비: 날갯짓하며 소녀를 쫓는다(homing). **저스트 가드로 되받으면** 여왕에게 돌아간다(reflectable).
## 스킨 자리: 진짜 그림이 오면 여기 _draw 를 Sprite2D 로 바꾸면 된다.

@export_enum("dust", "butterfly") var sap_kind := "dust"

var _flap := randf() * TAU
var _spin := randf_range(-2.0, 2.0)


func _physics_process(delta: float) -> void:
	super(delta)
	_flap += delta * (14.0 if sap_kind == "butterfly" else 6.0)


func _draw() -> void:
	var glow := Color(0.6, 0.95, 1.0, 0.18)
	if from_player:
		glow = Color(1.0, 0.85, 0.5, 0.25)
	match sap_kind:
		"dust":
			# 가루: 네 갈래 반짝이 + 둥근 심 + 빛 무리. 크기는 size.x.
			var r := size.x * 0.5
			var tw := 0.6 + 0.4 * sin(_flap * 2.0)
			draw_circle(Vector2.ZERO, r * 1.8, glow)
			var c := color if not from_player else Color(1.0, 0.85, 0.5)
			for i in 4:
				# 갈래 하나 = 끝점과 밑변 두 점의 삼각형 (가운데를 지나는 네모는 변이 겹쳐 삼각분할이 안 된다)
				var a := i * PI / 2.0 + _time * _spin
				var tip := Vector2(cos(a), sin(a)) * r * (1.0 + tw)
				var side := Vector2(cos(a + PI / 2.0), sin(a + PI / 2.0)) * r * 0.25
				var base := Vector2(cos(a), sin(a)) * r * 0.15
				draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color(c, 0.85))
			draw_circle(Vector2.ZERO, r * 0.45, Color(1.0, 1.0, 1.0, 0.95))
		"butterfly":
			# 나비: 몸통(작은 타원) + 양 날개(날갯짓 = 가로 폭이 접혔다 펴짐). 진행 방향이 +x (rotation 이 방향).
			var w := size.x * 0.5
			var h := size.y * 0.5
			var fold := absf(cos(_flap))   # 0 접힘 → 1 펼침
			var wing_w := w * (0.25 + 0.75 * fold)
			var c := color if not from_player else Color(1.0, 0.85, 0.5)
			draw_circle(Vector2.ZERO, w * 1.4, glow)
			for s in [-1.0, 1.0]:
				var pts := PackedVector2Array()
				var n := 10
				for i in n + 1:
					var t := float(i) / n
					var ang := lerpf(-0.2, PI + 0.2, t)
					pts.append(Vector2(cos(ang) * h * 0.9, sin(ang) * wing_w * s))
				pts.append(Vector2(-h * 0.2, 0))
				draw_colored_polygon(pts, Color(c, 0.8))
				# 날개 무늬
				draw_arc(Vector2(h * 0.15, wing_w * 0.45 * s), wing_w * 0.35, 0.0, TAU, 10, Color(1.0, 1.0, 1.0, 0.5), 1.5, true)
			draw_colored_polygon(PackedVector2Array([Vector2(h * 0.6, 0), Vector2(0, -h * 0.18), Vector2(-h * 0.7, 0), Vector2(0, h * 0.18)]), Color(0.2, 0.15, 0.12, 0.95))
			draw_circle(Vector2(h * 0.45, 0), h * 0.16, Color(1.0, 1.0, 1.0, 0.9))

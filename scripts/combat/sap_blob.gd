extends Projectile
class_name SapBlob
## 수액 방울 투사체 (무쇠 펌프·작은 펌프 공용, 확장판 잠긴 채굴장). 바탕(Projectile)의 날아가기·맞추기·되받기는 그대로 쓰고
## 그림만 바꾼다 — 자기 _draw 를 가진 하위 클래스라 바탕 그림(바람 호·테두리·발광·꼬리)은 그려지지 않는다
## (수액의 호수 묶음의 SapProjectile 과 같은 방식).
## 앞(+x)이 둥근 물방울, 뒤로 끌리는 꼬리와 작은 방울, 반짝임. 투사체가 진행 방향으로 도므로 꼬리는 늘 뒤.
## 저스트 가드로 되받으면 금빛이 되고, **중력 없이 쏜 쪽의 몸통 한가운데(맞는 영역)를 똑바로 겨눠** 돌아간다
## (바탕 규칙대로면 쏜 쪽의 발을 겨누고 중력이 남아 앞 바닥에 떨어진다).
## 그림 (2026-10-19 이펙트 리뉴얼 F2): 기획자 이펙트 시트의 꼬리 달린 물방울(그림 묶음 "sap_blob", scripts/fx/fx_art.gd).
## 아래 _draw 의 코드 그림은 그림 묶음이 없을 때만 쓴다.

const SAP_COLOR := Color(0.35, 0.82, 0.88)
const GOLD := Color(1.0, 0.85, 0.5)

## 맞는 영역을 못 찾을 때 겨누는 높이 (쏜 쪽의 원점 위로 px)
@export var aim_height := 60.0

var _t := randf() * 3.0


## 수액 방울 하나를 만든다 (아직 장면에 넣지 않음). diameter 는 그림·판정 지름.
static func make(spd: float, dmg: float, diameter: float) -> SapBlob:
	var p := SapBlob.new()
	p.kind = Projectile.Kind.GUST
	p.speed = spd
	p.damage = dmg
	p.poise = 0.0
	p.reflectable = true
	p.size = Vector2(diameter, diameter)
	p.color = SAP_COLOR
	p.look = "sap_blob"
	return p


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## 쏘는 순간 관·대롱 끝에서 짧은 물줄기가 뿜어진다 (이펙트 리뉴얼 F2 — 작은 펌프의 물줄기, 무쇠 펌프의 분사)
func launch(dir: Vector2, src: Node2D, player_owned := false) -> void:
	super.launch(dir, src, player_owned)
	if not player_owned and is_inside_tree():
		Fx.spawn("sap_jet", global_position - direction * 24.0, {"rot": rad_to_deg(direction.angle())})


func _reflect(by: Node) -> void:
	super._reflect(by)
	fall_gravity = 0.0
	if is_instance_valid(source):
		direction = (aim_point(source) - global_position).normalized()
		rotation = direction.angle()


## 되받은 방울이 겨눌 곳: 쏜 쪽 맞는 영역(Hurtbox)의 판정 모양 한가운데. 없으면 원점 위 aim_height.
func aim_point(target: Node2D) -> Vector2:
	var hb := target.get_node_or_null("Hurtbox")
	if hb:
		for c in hb.get_children():
			if c is CollisionShape2D:
				return (c as CollisionShape2D).global_position
		if hb is Node2D:
			return (hb as Node2D).global_position
	return target.global_position + Vector2(0, -aim_height)


func _draw() -> void:
	if has_art():
		_draw_art()
		return
	var tint := GOLD if from_player else color
	var r := size.x * 0.45
	var wob := 1.0 + 0.1 * sin(_t * 17.0)
	draw_circle(Vector2.ZERO, r * 2.0, Color(tint, 0.1 if not from_player else 0.18))
	draw_colored_polygon(PackedVector2Array([Vector2(-r * 2.4, 0), Vector2(-r * 0.1, -r * 0.82 * wob), Vector2(-r * 0.1, r * 0.82 * wob)]), Color(tint, 0.55))
	draw_circle(Vector2.ZERO, r * wob, Color(tint.darkened(0.3), 0.95))
	draw_circle(Vector2(r * 0.12, 0), r * 0.74 * wob, Color(tint.lightened(0.1), 1.0))
	draw_circle(Vector2(r * 0.32, -r * 0.34), r * 0.26, Color(1, 1, 1, 0.8))
	draw_circle(Vector2(-r * 2.9, sin(_t * 9.0) * r * 0.2), r * 0.24, Color(tint, 0.6))
	draw_circle(Vector2(-r * 3.6, cos(_t * 7.0) * r * 0.25), r * 0.16, Color(tint, 0.4))

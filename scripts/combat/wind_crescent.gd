extends Projectile
class_name WindCrescent
## 바람의 영혼 기술 (2026-10-19 이펙트 리뉴얼 F1): 앞으로 날아가는 민트빛 초승달 검기.
## 바탕은 예전 바람 투사체(Projectile, Kind.GUST)와 같다 — 속도·사거리·피해·흐트러짐·쿨다운은 player.gd 의 gust_* 그대로,
## 지형에 닿으면 사라지고(가운데 줄 레이캐스트) 부서지는 벽은 한 대 친다. 바뀐 것은 그림과 판정 모양뿐이다:
## 그림 = art/fx/crescent_wave.png (초승달 머리 + 뒤로 흐르는 꼬리), 민트 팔레트, 보통 섞기(밝은 그림이라 더하기로는 하얗게 뜬다).
## 판정 = 초승달 머리 부분을 덮는 사각형 (size × 0.9, 세로로 길다). 꼬리(옅은 빛줄기)는 맞히지 않는다.

const ART := "crescent_wave"
## 그림에서 초승달 머리의 가운데 (UV x). 이 점이 투사체 원점(판정 가운데)에 온다.
const HEAD_U := 0.22
## 그림 배율 (가로, 세로). 머리(UV 0~0.44) 가 판정 사각형을 채우도록 맞췄다.
const ART_SCALE := Vector2(0.86, 1.5)
## 꼬리 빛 알갱이 간격 (초)
const MOTE_GAP := 0.07

var _art: Sprite2D
var _echo: Sprite2D
var _mote_t := 0.0


func _ready() -> void:
	kind = Kind.GUST
	super._ready()
	var tex := Fx.texture(ART)
	var mat := Fx.make_material("wind", false, 0.2)
	_echo = _make_sprite(tex, mat)
	_echo.modulate = Color(1, 1, 1, 0.22)
	_art = _make_sprite(tex, mat)
	_art.modulate = Color(1.08, 1.1, 1.08, 0.95)


func _make_sprite(tex: Texture2D, mat: Material) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.material = mat
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.centered = true
	if tex:
		s.offset = Vector2((0.5 - HEAD_U) * tex.get_width(), 0.0)
	# 그림의 초승달은 왼쪽으로 볼록하다 → 가로로 뒤집어 날아가는 쪽(오른쪽, 투사체 회전이 방향을 맞춘다)으로 볼록하게
	s.scale = Vector2(-ART_SCALE.x, ART_SCALE.y)
	add_child(s)
	return s


## 그림 대신 자기 그림을 쓴다 (바탕의 바람 호는 그리지 않는다)
func _draw() -> void:
	pass


## 초승달 머리가 차지하는 사각형 (자기 좌표, 오른쪽으로 날 때). 시험이 판정 사각형과 비교한다.
func head_rect() -> Rect2:
	var tex := Fx.texture(ART)
	if tex == null:
		return Rect2()
	var w := tex.get_width() * ART_SCALE.x
	var h := tex.get_height() * ART_SCALE.y
	# 머리 = UV 0 ~ 0.44 (뒤집혀서 앞이 +)
	return Rect2(Vector2(-(0.44 - HEAD_U) * w, -h * 0.42), Vector2(0.44 * w, h * 0.84))


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _dead or _art == null:
		return
	# 살짝 일렁이고, 뒤에 그림자 한 겹이 따라오며, 꼬리에 빛 알갱이를 흘린다
	var wob := 1.0 + 0.04 * sin(_time * 30.0)
	_art.scale = Vector2(-ART_SCALE.x, ART_SCALE.y * wob)
	_echo.position = Vector2(-28.0 - 10.0 * sin(_time * 18.0), 0.0)
	_mote_t -= delta
	if _mote_t <= 0.0:
		_mote_t = MOTE_GAP
		Fx.spawn("wind_wisp", global_position - direction * 60.0 + Vector2(0, randf_range(-70.0, 70.0)), {"vel": -direction * 120.0})


## 맞는 영역에 닿았다 (바탕 Projectile._hit 과 같은 판정. 맞힌 때만 이펙트 — '무시'된 상대에 겹쳐 매 프레임 터지지 않게)
func _hit(area: Hurtbox) -> void:
	var hit := HitData.make(damage, poise, source if source else self, Vector2(260, -100))
	hit.guardable = guardable
	hit.from_player = from_player
	hit.reflected = was_reflected
	hit.hitstop = 0.04
	var result: String = area.receive(hit)
	if result == "ignored":
		return
	Fx.spawn("wind_hit", area.global_position.lerp(global_position, 0.5))
	_vanish()


func _vanish() -> void:
	if not _dead:
		Fx.spawn("wind_fade", global_position, {"rot": rad_to_deg(direction.angle())})
	super._vanish()

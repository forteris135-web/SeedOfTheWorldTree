extends Pickup
class_name DewCup
## 이슬잔 (확장판 숨겨진 방의 보상): 우산 모양 풀잎으로 만든 작은 잔 (EXPANSION.md 2장).
## v1.1.0 (기획자 요청 16): 이슬 최대치가 5 로 줄어 이슬잔은 이슬 대신 새순 2개를 준다 ("이슬잔 속에 새순 2개가 돋아 있었다").
## 그림은 이슬잔 그대로. Pickup(kind "token") 과 같은 규칙(한 번 모으면 세이브에 남음, 지도의 탐사 요소) — pickup_id 가 그대로라
## 예전에 이슬로 받은 잔은 다시 생기지 않는다 (옛 저장 파일은 SaveMigrate 가 새순으로 돌려준다).

const TEX := preload("res://art/objects/object_dew_cup.png")
const ART_SCALE := 0.22

var _sprite: Sprite2D


## 이슬잔 하나의 새순
const TOKENS := 2.0


func _ready() -> void:
	kind = "token"
	if amount <= 0.0:
		amount = TOKENS
	super()
	_sprite = Sprite2D.new()
	_sprite.texture = TEX
	_sprite.scale = Vector2(ART_SCALE, ART_SCALE)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)


func _process(delta: float) -> void:
	super(delta)
	if _sprite:
		_sprite.modulate.a = 1.0 if not _taken else _glow.modulate.a
		_sprite.rotation = sin(_t * 1.3) * 0.08


func _collect(player: Player) -> void:
	# 부모(Pickup)가 새순을 주고 기본 문구를 띄운 뒤 빛이 사라지는 것을 기다리는 동안(그 부분은 따로 흘러간다),
	# 문구를 이슬잔 것으로 바로 바꾼다
	super(player)
	var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
	if hud:
		hud.show_message(cup_text(roundi(amount)), 3.0)


## 이슬잔 안내 (skills.json "cup": "이슬잔 속에 새순 {n}개가 돋아 있었다")
static func cup_text(n: int) -> String:
	return SkillMenu.text_of("cup", "이슬잔 속에 새순 {n}개가 돋아 있었다").format({"n": n, "have": Progress.tokens})


## 구슬 대신 잔 그림을 쓰므로 바탕 원은 그리지 않는다 (빛 테두리만).
func _draw() -> void:
	if _taken and _glow.modulate.a <= 0.0:
		return
	var col: Color = COLORS.get(kind, Color.WHITE)
	var a := 1.0 if not _taken else _glow.modulate.a
	draw_arc(Vector2.ZERO, 34.0 + 2.0 * sin(_t * 2.0), 0.0, TAU, 32, Color(col, 0.3 * a), 1.5, true)

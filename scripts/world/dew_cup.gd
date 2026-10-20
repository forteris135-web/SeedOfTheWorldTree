extends Pickup
class_name DewCup
## 이슬잔 (확장판 숨겨진 방의 보상): 우산 모양 풀잎으로 만든 작은 잔. 모으면 이슬 방울 최대 개수 +1 (EXPANSION.md 2장).
## Pickup(kind "dews") 과 같은 규칙(한 번 모으면 세이브에 남음, 지도의 탐사 요소)에 그림만 임시 그림 object_dew_cup.png 를 쓴다.

const TEX := preload("res://art/objects/object_dew_cup.png")
const ART_SCALE := 0.22

var _sprite: Sprite2D


func _ready() -> void:
	kind = "dews"
	if amount <= 0.0:
		amount = 1.0
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
	# 부모(Pickup)가 성장을 적용하고 기본 문구를 띄운 뒤 빛이 사라지는 것을 기다리는 동안(그 부분은 따로 흘러간다),
	# 문구를 이슬잔 것으로 바로 바꾼다
	super(player)
	var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
	if hud:
		# 이슬이 가득(8개)하면 잔에 담긴 이슬은 회복량이 된다 (Pickup.dew_reward_text)
		hud.show_message(dew_reward_text(amount, "이슬잔 — 이슬 방울을 하나 더 담을 수 있다 (이제 %d개)" % player.max_dews, "이슬잔"), 3.0)


## 구슬 대신 잔 그림을 쓰므로 바탕 원은 그리지 않는다 (빛 테두리만).
func _draw() -> void:
	if _taken and _glow.modulate.a <= 0.0:
		return
	var col: Color = COLORS.get(kind, Color.WHITE)
	var a := 1.0 if not _taken else _glow.modulate.a
	draw_arc(Vector2.ZERO, 34.0 + 2.0 * sin(_t * 2.0), 0.0, TAU, 32, Color(col, 0.3 * a), 1.5, true)

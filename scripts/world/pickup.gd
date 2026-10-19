extends Area2D
class_name Pickup
## 떠 있는 빛나는 구슬. 소녀가 닿으면 모아져 저절로 성장한다 (자동 스펙업).
## 종류: max_hp(세계수의 수액, 최대 체력) / attack(바람의 결, 공격력) / dews(달빛 이슬, 이슬 개수) / heal(맑은 샘물, 회복량).
## 한 번 모은 것은 Progress.collected[pickup_id] 에 남아 다시 생기지 않는다.
## 비밀 벽·천장 안의 것(hidden_in)은 그 비밀이 부서질 때 나타난다 (천장이면 fall_to 로 떨어져 안착).

const COLORS := {
	"max_hp": Color(1.0, 0.58, 0.36),   # 붉은 금빛
	"attack": Color(0.93, 0.95, 1.0),   # 흰 은빛
	"dews": Color(0.56, 0.83, 1.0),     # 은청색
	"heal": Color(0.66, 0.95, 0.5),     # 초록 금빛
}

## 고유 이름: pick_<방>_<번호>
@export var pickup_id := ""
@export_enum("max_hp", "attack", "dews", "heal") var kind := "max_hp"
## 늘어나는 양 (max_hp: 체력, attack: 배수 0.05 = 5%, dews: 개수, heal: 회복량)
@export var amount := 10.0
## 이 비밀(secret_id)이 부서지기 전엔 숨어 있다
@export var hidden_in := ""
## 나타난 뒤 떨어져 안착할 자리 (월드 좌표). ZERO 면 제자리에 뜬다.
@export var fall_to := Vector2.ZERO

## 이미 모은 것 (방에 들어올 때부터). 노드는 지우지 않고 숨겨 둔다 (방의 탐사 요소 수를 세기 위해).
var collected := false
var _revealed := true
var _taken := false
var _falling := false
var _t := 0.0
var _base_y := 0.0
var _glow: Sprite2D
var _motes: CPUParticles2D


func _ready() -> void:
	add_to_group("pickup")
	collision_layer = 0
	collision_mask = 2   # 소녀 몸
	var shape := CollisionShape2D.new()
	var c := CircleShape2D.new()
	c.radius = 46.0
	shape.shape = c
	add_child(shape)
	body_entered.connect(_on_body_entered)
	var col: Color = COLORS.get(kind, Color.WHITE)
	# 더하기 혼합 발광
	_glow = Sprite2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(col, 0.6), Color(col, 0.2), Color(col, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 128
	gt.height = 128
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	_glow.texture = gt
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	_glow.modulate = Color(col.r * 1.5, col.g * 1.5, col.b * 1.5, 1.0)
	add_child(_glow)
	# 작은 빛 입자
	_motes = CPUParticles2D.new()
	_motes.amount = 8
	_motes.lifetime = 1.5
	_motes.preprocess = 1.5
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_motes.emission_sphere_radius = 14.0
	_motes.direction = Vector2(0, -1)
	_motes.spread = 60.0
	_motes.gravity = Vector2(0, -30)
	_motes.initial_velocity_min = 6.0
	_motes.initial_velocity_max = 22.0
	_motes.scale_amount_min = 1.0
	_motes.scale_amount_max = 2.4
	_motes.color = Color(col.r * 1.6, col.g * 1.6, col.b * 1.6, 0.8)
	add_child(_motes)
	_base_y = position.y

	if pickup_id != "" and Progress.is_collected(pickup_id):
		# 이미 모았다: 숨기고 멈춘다 (지우지 않음)
		collected = true
		_taken = true
		visible = false
		monitoring = false
		set_process(false)
		return
	if hidden_in != "":
		if Progress.is_collected(hidden_in):
			# 비밀은 이미 부서져 있다: 떨어진 자리에 바로 둔다
			if fall_to != Vector2.ZERO:
				global_position = fall_to
				_base_y = position.y
		else:
			_revealed = false
			visible = false
			monitoring = false
			Progress.collected_changed.connect(_on_collected_changed)


func _process(delta: float) -> void:
	_t += delta
	if _revealed and not _taken and not _falling:
		position.y = _base_y + sin(_t * 2.2) * 7.0   # 숨 쉬듯 떠오르락내리락
	var pulse := 0.85 + 0.15 * sin(_t * 3.1)
	_glow.scale = Vector2.ONE * pulse
	queue_redraw()


func _on_collected_changed(id: String) -> void:
	if id == hidden_in and not _revealed:
		reveal()


## 비밀이 부서졌다: 나타난다. fall_to 가 있으면 그리로 떨어져 안착한다.
func reveal() -> void:
	_revealed = true
	visible = true
	if fall_to != Vector2.ZERO and fall_to != global_position:
		_falling = true
		var dist := absf(fall_to.y - global_position.y)
		var dur := sqrt(2.0 * maxf(dist, 1.0) / 980.0)   # 중력 낙하 시간
		var tw := create_tween()
		tw.tween_property(self, "global_position", fall_to, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		# 살짝 튀어 오른 뒤 안착
		tw.tween_property(self, "global_position", fall_to + Vector2(0, -22), 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(self, "global_position", fall_to, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.finished.connect(func() -> void:
			_falling = false
			_base_y = position.y
			set_deferred("monitoring", true))
	else:
		set_deferred("monitoring", true)


func _on_body_entered(body: Node) -> void:
	if body is Player and _revealed and not _taken and not _falling:
		_collect(body)


## 소녀가 닿았다: 성장을 적용하고 빛이 터진 뒤 사라진다.
func _collect(player: Player) -> void:
	_taken = true
	collected = true
	set_deferred("monitoring", false)
	if pickup_id != "":
		Progress.collect(pickup_id)
	Progress.add_upgrade(kind, amount)   # → 소녀 _apply_abilities 가 저절로 다시 계산
	var text := ""
	match kind:
		"dews":
			# 늘어난 칸은 소녀 _apply_abilities 가 이미 채웠다 (여기서 또 더하면 하나가 아니라 둘이 찼다)
			player.dews_changed.emit(player.dews)
			text = "달빛 이슬이 하나 늘었다 (이제 %d개)" % player.max_dews
		"max_hp":
			text = "세계수의 수액 — 최대 체력 +%d" % int(amount)
		"attack":
			text = "바람의 결 — 공격력 +%d%%" % int(round(amount * 100.0))
		"heal":
			text = "맑은 샘물 — 회복량 +%d" % int(amount)
	var hud := get_tree().current_scene.get_node_or_null("CombatHUD")
	if hud and text != "":
		hud.show_message(text, 3.0)
	Sfx.play("soul", -4.0, 0.03)
	Juice.rumble(0.2, 0.5, 0.2)
	Fx.spawn("pickup_big", global_position)   # 이펙트 리뉴얼: 금빛 별 + 고리 + 알갱이
	# 빛 터짐
	var col: Color = COLORS.get(kind, Color.WHITE)
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 30
	burst.lifetime = 0.8
	burst.spread = 180.0
	burst.gravity = Vector2(0, -40)
	burst.initial_velocity_min = 80.0
	burst.initial_velocity_max = 260.0
	burst.scale_amount_min = 1.5
	burst.scale_amount_max = 4.0
	burst.color = Color(col.r * 1.8, col.g * 1.8, col.b * 1.8, 0.9)
	burst.emitting = true
	add_child(burst)
	_motes.emitting = false
	var tw := create_tween()
	tw.tween_property(_glow, "scale", Vector2(3.0, 3.0), 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_glow, "modulate:a", 0.0, 0.35)
	await get_tree().create_timer(1.0).timeout
	visible = false
	set_process(false)
	# 노드는 남겨 둔다 (탐사 요소 수 세기). 그림·입자는 모두 꺼졌다.
	burst.queue_free()


func _draw() -> void:
	if _taken and _glow.modulate.a <= 0.0:
		return
	var col: Color = COLORS.get(kind, Color.WHITE)
	var pulse := 0.9 + 0.1 * sin(_t * 3.1)
	var a := 1.0 if not _taken else _glow.modulate.a
	draw_circle(Vector2.ZERO, 13.0 * pulse, Color(col, 0.95 * a))
	draw_circle(Vector2(-3, -4), 5.0, Color(1.0, 1.0, 1.0, 0.85 * a))
	draw_arc(Vector2.ZERO, 19.0 + 2.0 * sin(_t * 2.0), 0.0, TAU, 28, Color(col, 0.35 * a), 1.5, true)

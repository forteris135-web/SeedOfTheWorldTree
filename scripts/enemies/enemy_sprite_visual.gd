extends Node2D
## 일반 적의 그림(art/enemies/*.png)을 상태에 맞춰 움직인다: 걸음 들썩임, 예고 젖힘, 휘두름, 피격 번쩍임, 무너짐.
## 그림은 한 장이라 팔을 따로 못 움직이므로 기울기·찌그러짐·위치로 표현한다.

@export var texture: Texture2D
## 그림 속 인물이 오른쪽을 보고 있는가 (왼쪽을 보면 false)
@export var art_faces_right := true
## 그림 크기 배율 (원본 1536×1024 기준, 키 약 150이 되게)
@export var art_scale := 0.17
## 그림의 발 위치 (그림 아래쪽 투명 여백만큼 보정, 원본 px)
@export var foot_offset := 20.0
## 구원 가능한 자: 눈빛의 따뜻한 빛
@export var warm_eye := false

@export_group("무기 팔 (따로 움직이는 겹)")
## 팔 조각 그림 (없으면 한 장짜리로 그린다)
@export var arm_texture: Texture2D
## 그림이 원본의 몇 배로 줄여진 것인가 (parts 폴더는 0.5)
@export var art_pixel_scale := 1.0
## 어깨 축 (원본 px)
@export var arm_pivot := Vector2.ZERO
## 팔 조각의 왼쪽 위가 원본에서 있던 자리 (원본 px)
@export var arm_origin := Vector2.ZERO
## 원본 그림 크기 (원본 px)
@export var art_size := Vector2(1536, 1024)
## 팔의 종류: 검(들었다 내려침) / 대롱(겨눔·반동)
@export_enum("sword", "gun") var arm_kind := "sword"

var _enemy: EnemyBase
var _sprite: Sprite2D
var _glow: Sprite2D
var _label: Label
var _t := 0.0
var _cur_rot := 0.0
var _prev_facing := 0
var _turn := 0.0        # 방향 바꿀 때 몸 틀기 (1→0)
var _ghosts: Array[Sprite2D] = []
var _ghost_timer := 0.0
var _dust: CPUParticles2D
var _was_on_floor := true
var _alert_t := -1.0
var _arm_bone: Node2D
var _arm_sprite: Sprite2D
var _arm_angle := 0.0
var _recoil := 0.0


func _ready() -> void:
	_enemy = get_parent() as EnemyBase
	_sprite = Sprite2D.new()
	_sprite.texture = texture
	_sprite.scale = Vector2(art_scale, art_scale) / art_pixel_scale
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_sprite)
	if arm_texture:
		# 어깨 축은 몸통 그림 좌표(그림 픽셀 단위, 가운데가 원점)에 둔다
		_arm_bone = Node2D.new()
		_arm_bone.position = (arm_pivot - art_size / 2.0) * art_pixel_scale
		_sprite.add_child(_arm_bone)
		_arm_sprite = Sprite2D.new()
		_arm_sprite.texture = arm_texture
		_arm_sprite.centered = false
		_arm_sprite.position = (arm_origin - arm_pivot) * art_pixel_scale
		_arm_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_arm_bone.add_child(_arm_sprite)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color("ffd46a"))
	_label.position = Vector2(-80, -230)
	_label.visible = false
	add_child(_label)
	for i in 3:
		var g := Sprite2D.new()
		g.texture = texture
		g.scale = Vector2(art_scale, art_scale) / art_pixel_scale
		g.visible = false
		g.show_behind_parent = true
		g.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		add_child(g)
		_ghosts.append(g)
	_dust = CPUParticles2D.new()
	_dust.emitting = false
	_dust.one_shot = true
	_dust.explosiveness = 1.0
	_dust.amount = 10
	_dust.lifetime = 0.5
	_dust.direction = Vector2(0, -1)
	_dust.spread = 70.0
	_dust.gravity = Vector2(0, 200)
	_dust.initial_velocity_min = 60.0
	_dust.initial_velocity_max = 160.0
	_dust.scale_amount_min = 3.0
	_dust.scale_amount_max = 6.0
	_dust.color = Color(0.75, 0.72, 0.6, 0.5)
	add_child(_dust)
	if warm_eye:
		_glow = Sprite2D.new()
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		grad.colors = PackedColorArray([Color(1, 0.85, 0.5, 0.8), Color(1, 0.8, 0.45, 0.25), Color(1, 0.8, 0.45, 0.0)])
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 64
		gt.height = 64
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1, 0.5)
		_glow.texture = gt
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_glow.material = add
		add_child(_glow)


func _process(delta: float) -> void:
	_t += delta
	if _enemy == null or texture == null:
		return
	var st := _enemy.state
	var f := float(_enemy.facing)
	var mirror := -1.0 if ((_enemy.facing > 0) != art_faces_right) else 1.0
	# 발을 원점에 맞춘다 (원본 아래쪽 여백 보정)
	var h := art_size.y * art_scale
	_sprite.position = Vector2(0, -h / 2.0 + foot_offset * art_scale + _enemy.hurt_height * 0.5)
	# 방향 전환: 몸을 틀며 잠깐 홀쭉해진다
	if _prev_facing != 0 and _prev_facing != _enemy.facing:
		_turn = 1.0
	_prev_facing = _enemy.facing
	_turn = maxf(_turn - delta * 7.0, 0.0)
	# 착지 먼지
	var on_floor := _enemy.is_on_floor()
	if on_floor and not _was_on_floor:
		_puff(8)
	_was_on_floor = on_floor
	if st == EnemyBase.State.ALERT and _alert_t < 0.0:
		_alert_t = 0.0
	elif st != EnemyBase.State.ALERT:
		_alert_t = -1.0
	if _alert_t >= 0.0:
		_alert_t += delta
	var speed := absf(_enemy.velocity.x)
	var rot := 0.0
	var sq := Vector2(1.0, 1.0 + sin(_t * 2.2) * 0.015)   # 숨쉬기
	var dy := 0.0
	var ghost := false
	match st:
		EnemyBase.State.PATROL, EnemyBase.State.CHASE:
			var step := _t * (7.0 + speed / 40.0)
			dy = -absf(sin(step)) * (4.0 + speed / 60.0)
			rot = (0.04 + speed / 4000.0) * f + sin(step) * 0.04
			sq = Vector2(1.0 - absf(sin(step)) * 0.03, 1.0 + absf(sin(step)) * 0.04)
		EnemyBase.State.ALERT:
			rot = -0.1 * f
			sq = Vector2(0.9, 1.12)
		EnemyBase.State.LUNGE:
			rot = 0.28 * f
			sq = Vector2(1.12, 0.92)
			ghost = true
		EnemyBase.State.WINDUP:
			var p := _enemy.windup_progress
			rot = -0.3 * f * p
			dy = -12.0 * p
			var shake := sin(_t * 45.0) * 0.02 * clampf((p - 0.6) / 0.4, 0.0, 1.0)
			sq = Vector2(0.95 + shake, 1.06 + p * 0.04)
		EnemyBase.State.STRIKE:
			rot = 0.38 * f
			sq = Vector2(1.14, 0.9)
			ghost = true
		EnemyBase.State.RECOVER:
			rot = 0.1 * f
			sq = Vector2(1.03, 0.98)
		EnemyBase.State.BACKSTEP:
			rot = -0.15 * f
			sq = Vector2(0.96, 1.04)
		EnemyBase.State.HIT:
			rot = -0.22 * f
			sq = Vector2(1.1, 0.9)
		EnemyBase.State.BROKEN:
			rot = 0.45 * f
			dy = 26.0 + sin(_t * 1.5) * 2.0
			sq = Vector2(1.05, 0.85)
		EnemyBase.State.DEAD:
			rot = 0.8 * f
	match _enemy.anim_hint:
		"charge":
			rot = 0.42 * f
			sq = Vector2(1.18, 0.88)
			ghost = true
		"stuck":
			rot = 0.5 * f + sin(_t * 28.0) * 0.03
			dy = 10.0
			sq = Vector2(1.05, 0.95)
	sq.x *= 1.0 - _turn * 0.35
	_cur_rot = lerpf(_cur_rot, rot, 0.25)
	_sprite.rotation = _cur_rot
	_sprite.scale = Vector2(art_scale * sq.x * mirror, art_scale * sq.y) / art_pixel_scale
	_sprite.position.y += dy
	_update_arm(delta, st, mirror)
	_update_ghosts(delta, ghost)
	if st == EnemyBase.State.STRIKE and _ghost_timer == 0.0:
		_puff(6)
	# 피격 번쩍임, 예고의 수액 빛
	var fl := _enemy.flash_amount()
	var base := Color(1, 1, 1)
	if st == EnemyBase.State.WINDUP:
		base = base.lerp(Color(1.6, 1.3, 0.9), 0.3 + 0.5 * sin(_t * 30.0) * _enemy.windup_progress)
	if _enemy.anim_hint == "red" and st == EnemyBase.State.WINDUP:
		base = Color(1.0, 1.0, 1.0).lerp(Color(2.4, 0.5, 0.4), 0.5 + 0.5 * sin(_t * 32.0))
	_sprite.modulate = base.lerp(Color(2.5, 2.5, 2.5), fl * 0.8)
	_label.visible = st == EnemyBase.State.BROKEN
	if _label.visible:
		_label.text = "%s  %s" % [InputDevice.prompt("interact"), "구원의 손길" if _enemy.savable else "정화의 손길"]
	if _glow:
		var pulse := 0.7 + 0.3 * sin(_t * 2.5)
		_glow.position = Vector2(14 * f, -h * 0.72 + dy)
		_glow.modulate = Color(1.6, 1.4, 1.0, 1.0) * pulse
		_glow.scale = Vector2(1.2, 1.2) * pulse
	queue_redraw()


## 무기 팔: 상태에 따라 어깨를 축으로 돈다. 각도는 그림 기준(양수 = 시계 방향).
func _update_arm(delta: float, st: EnemyBase.State, mirror: float) -> void:
	if _arm_bone == null:
		return
	var target := 0.0
	var k := 12.0
	var forward := 1.0 if art_faces_right else -1.0   # 그림에서 "앞"이 +x 인가
	if arm_kind == "sword":
		match st:
			EnemyBase.State.PATROL, EnemyBase.State.CHASE:
				target = sin(_t * (7.0 + absf(_enemy.velocity.x) / 40.0)) * 0.08
			EnemyBase.State.LUNGE:
				target = -0.6 * forward
				k = 18.0
			EnemyBase.State.WINDUP:
				var p := ease(_enemy.windup_progress, 0.5)
				target = -1.7 * forward * p + sin(_t * 40.0) * 0.03 * clampf((_enemy.windup_progress - 0.6) / 0.4, 0.0, 1.0)
				k = 16.0
			EnemyBase.State.STRIKE:
				target = 1.0 * forward
				k = 40.0
			EnemyBase.State.RECOVER:
				target = 0.55 * forward
				k = 6.0
			EnemyBase.State.BACKSTEP:
				target = -0.3 * forward
			EnemyBase.State.HIT:
				target = 0.4 * forward
			EnemyBase.State.BROKEN:
				target = 0.7 * forward
				k = 4.0
			EnemyBase.State.DEAD:
				target = 0.9 * forward
	else:
		# 대롱: 소녀를 겨눈다. 쏠 때 반동.
		var aim := 0.0
		if _enemy.player and st in [EnemyBase.State.CHASE, EnemyBase.State.WINDUP, EnemyBase.State.STRIKE, EnemyBase.State.RECOVER, EnemyBase.State.BACKSTEP]:
			var to := _enemy.player.global_position + Vector2(0, -40) - global_position - Vector2(0, -_enemy.hurt_height * 0.55)
			var ang := atan2(to.y, absf(to.x))    # 앞쪽 기준 위아래 각
			aim = clampf(ang, -0.7, 0.6) * forward
		match st:
			EnemyBase.State.WINDUP:
				target = aim - 0.25 * forward + sin(_t * 35.0) * 0.03 * _enemy.windup_progress
				k = 14.0
			EnemyBase.State.STRIKE:
				if _recoil <= 0.0:
					_recoil = 1.0
				target = aim
				k = 30.0
			EnemyBase.State.CHASE, EnemyBase.State.RECOVER, EnemyBase.State.BACKSTEP:
				target = aim
			EnemyBase.State.BROKEN:
				target = 0.8 * forward
				k = 4.0
			EnemyBase.State.DEAD:
				target = 0.9 * forward
			_:
				target = sin(_t * 1.8) * 0.05
	if _recoil > 0.0:
		_recoil = maxf(_recoil - delta * 6.0, 0.0)
		target += -0.35 * forward * _recoil
	_arm_angle = lerpf(_arm_angle, target, 1.0 - exp(-k * delta))
	_arm_bone.rotation = _arm_angle


func _puff(n: int) -> void:
	_dust.amount = n
	_dust.position = Vector2(0, _enemy.hurt_height * 0.5)
	_dust.restart()
	_dust.emitting = true


## 잔상: 빠르게 움직일 때 뒤에 희미한 그림을 남긴다.
func _update_ghosts(delta: float, active: bool) -> void:
	if active:
		_ghost_timer += delta
		if _ghost_timer >= 0.04:
			_ghost_timer = 0.0
			var g: Sprite2D = _ghosts.pop_front()
			g.visible = true
			g.position = _sprite.position
			g.rotation = _sprite.rotation
			g.scale = _sprite.scale
			g.modulate = Color(1.0, 0.9, 0.7, 0.35)
			_ghosts.append(g)
	else:
		_ghost_timer = 0.0
	for g in _ghosts:
		if g.visible:
			g.modulate.a -= delta * 2.2
			if g.modulate.a <= 0.0:
				g.visible = false


func _draw() -> void:
	if _enemy == null:
		return
	var st := _enemy.state
	if st == EnemyBase.State.DEAD:
		return
	if _alert_t >= 0.0 and _alert_t < 0.6:
		var font := ThemeDB.fallback_font
		var a := 1.0 - _alert_t / 0.6
		draw_string(font, Vector2(-8, -_enemy.hurt_height - 60.0 - _alert_t * 30.0), "!", HORIZONTAL_ALIGNMENT_CENTER, 16, 44, Color(1.0, 0.85, 0.5, a))
	if _enemy.hp < _enemy.max_hp or _enemy.poise > 0.0 or st == EnemyBase.State.BROKEN:
		var w := 90.0
		var top := Vector2(-w / 2.0, -_enemy.hurt_height - 40.0)
		draw_rect(Rect2(top, Vector2(w, 7)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(top, Vector2(w * _enemy.hp / _enemy.max_hp, 7)), Color("9bd48a"))
		draw_rect(Rect2(top + Vector2(0, 10), Vector2(w, 5)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(top + Vector2(0, 10), Vector2(w * _enemy.poise / _enemy.max_poise, 5)), Color("8fd3ff"))
	if st == EnemyBase.State.BROKEN:
		var pulse := 0.6 + 0.4 * sin(_t * 5.0)
		draw_circle(Vector2(0, -_enemy.hurt_height * 0.4), 60.0, Color("8fd3ff", 0.08 * pulse))

class_name EliteTraits
extends RefCounted
## 중간 보스(일반 몹 거대화) 공통 처리. 각 elite_<종류>.gd 가
##  - _ready 에서 super._ready() **앞에** apply(), 뒤에 fit_visual() 을 부르고,
##  - receive_hit 에서 exposed_hit() 으로 맞은 공격을 고친 뒤 super 를 부르고, 끝에 check_rage() 로 분노를 확인하고,
##  - _break 에서 stagger_instead() 가 true 면 무너지지 않고(크게 휘청만),
##  - _is_armored 에서 is_staggered() 면 맞아도 휘청임이 끊기지 않게 하고,
##  - 매 틱 tick() 으로 붉은 빛·휘청 시간을 돌린다.
## (상속이 한 줄이라 다섯 종류가 같은 코드를 베끼지 않도록 여기 모아 둔다.)
##
## 기본 배율 (2026-10-19 기획자 요청 "크기를 일반 몹보다 훨씬 키운다"):
##  - 크기 ×1.8 (그림·맞는 영역·몸), 공격 판정 ×1.6, 체력 ×4, 흐트러짐 ×2.5, 걷기 ×0.9
##  - 피해는 지역 보스보다 세지 않게 종류마다 따로 (수관 ×1.1 — 첫 보스 전 / 마을 ×1.3 / 채굴장 ×1.25 / 심연 ×1.35)
##  - 체력 절반 아래로 떨어지면 **분노**: 예고·회복·쉬기 시간 ×0.8, 걷기 ×1.25, 몸 뒤에 붉은 빛이 맥동한다.
##  - **무너짐(정화의 손길)은 체력 절반 이하에서만.** 그 위에서 흐트러짐이 차면 크게 휘청(1.3초)이고, 2초 동안 받는 피해 ×1.5.
##    (흐트러짐이 피해보다 빨리 차서 체력 40% 만 깎고 정화로 끝나 버리던 것 — 분노와 4배 체력이 보이지 않았다)

const SIZE_MULT := 1.8
const BOX_MULT := 1.6
const HP_MULT := 4.0
## 피해 배수 기본값 (종류별 스크립트가 apply 에 지역에 맞는 값을 넘긴다)
const DAMAGE_MULT := 1.25
const POISE_MULT := 2.5
const SPEED_MULT := 0.9
## 분노에 들어가는 체력 비율
const RAGE_HP := 0.5
## 무너질 수 있는(정화의 손길을 받을 수 있는) 체력 비율. 이보다 많으면 흐트러짐이 차도 휘청만 한다.
const PURIFY_HP := 0.5
## 크게 휘청이는 시간(초). 그동안은 공격하지 않고, 맞아도 휘청임이 끊기지 않는다.
const STAGGER_TIME := 1.3
## 휘청인 뒤 받는 피해가 커지는 시간(초, 휘청임 포함)과 배수
const EXPOSED_TIME := 2.0
const EXPOSED_DAMAGE_MULT := 1.5
## 분노 때 예고·회복·쉬기 시간 배수 (빨라진다)
const RAGE_TIME_MULT := 0.8
## 분노 때 걷기 속도 배수
const RAGE_SPEED_MULT := 1.25
## 분노 때 몸 색 (Visual.modulate 에 곱한다). 섞는 세기는 RAGE_TINT_MIN ~ +RAGE_TINT_PULSE.
## 몸은 아주 살짝만 물든다 — 붉은 예고(가드 불가)와 헷갈리지 않게. 분노는 몸 뒤의 빛과 입자가 알린다.
const RAGE_TINT := Color(1.35, 0.78, 0.7)
const RAGE_TINT_MIN := 0.08
const RAGE_TINT_PULSE := 0.07
## 분노에 들어갈 때 소리 (무너짐 'broke' 와 다른 낮은 울림)
const RAGE_SOUND := "res://audio/sfx/boss_fall.wav"


## 능력치·크기를 키운다. EnemyBase._ready() **앞에** 불러야 맞는 영역 캡슐이 커진 값으로 만들어진다.
static func apply(e: EnemyBase, hp_mult := HP_MULT, size_mult := SIZE_MULT, dmg_mult := DAMAGE_MULT) -> void:
	e.max_hp *= hp_mult
	e.max_poise *= POISE_MULT
	e.damage *= dmg_mult
	e.set("elite_damage_mult", dmg_mult)
	e.walk_speed *= SPEED_MULT
	e.hurt_radius *= size_mult
	e.hurt_height *= size_mult
	e.strike_box = Rect2(e.strike_box.position * BOX_MULT, e.strike_box.size * BOX_MULT)
	e.knockback *= 1.25
	e.hit_stun *= 0.6          # 묵직해서 맞아도 덜 멈칫한다
	e.broken_time += 0.5       # 무너지면 정화할 시간은 조금 더
	e.notice_range *= 1.4
	# 몸 충돌 (방 안에서 서 있는 캡슐). 자원은 씬의 다른 인스턴스와 공유되므로 복제해서 키운다.
	for c in e.get_children():
		if c is CollisionShape2D and c.shape:
			var s: Shape2D = c.shape.duplicate()
			if s is CapsuleShape2D:
				# 높이를 먼저: Godot 은 height >= 2*radius 를 강제하므로 반지름을 먼저 키우면 높이가 끌려 올라간다
				var h0: float = s.height
				var r0: float = s.radius
				s.height = h0 * size_mult
				s.radius = r0 * size_mult
				# 몸 바닥을 그림의 발(hurt_height 의 절반 아래)에 맞춘다.
				# 눕힌 캡슐(기계)은 바닥이 '반지름' 아래라 그대로 키우면 그림이 땅에 65px 묻혔다.
				var lying := absf(absf(c.rotation) - PI * 0.5) < 0.1
				var half: float = s.radius if lying else s.height * 0.5
				c.position = Vector2(c.position.x * size_mult, e.hurt_height * 0.5 - half)
			elif s is RectangleShape2D:
				s.size *= size_mult
				c.position *= size_mult
			else:
				c.position *= size_mult
			c.shape = s
	var vis := e.get_node_or_null("Visual")
	if vis:
		if "art_scale" in vis:
			vis.art_scale *= size_mult
		if "stride_scale" in vis:
			vis.stride_scale = size_mult        # 큰 몸은 보폭도 크다 (작은 발걸음으로 종종거리지 않게)
		if "show_overhead_bar" in vis:
			vis.show_overhead_bar = false       # 화면 아래 보스 막대가 있으니 머리 위 작은 막대는 끈다


## EnemyBase._ready() 뒤에 부른다: 그림 쪽의 고정 자리 값을 큰 몸에 맞춘다 ('정화의 손길' 글자가 가슴팍에 걸리지 않게).
static func fit_visual(e: EnemyBase) -> void:
	var vis := e.get_node_or_null("Visual")
	if vis == null:
		return
	var label = vis.get("_label")
	if label is Label:
		label.position = Vector2(-80, -e.hurt_height - 70.0)


## 분노 빛: 몸 뒤의 붉은 더하기 빛 (처음엔 꺼져 있다). Visual 보다 앞 순서에 넣어 뒤에 그려지게 한다.
static func make_aura(e: EnemyBase) -> Sprite2D:
	var aura := Sprite2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	grad.colors = PackedColorArray([Color(1.0, 0.35, 0.25, 0.55), Color(1.0, 0.3, 0.2, 0.2), Color(1.0, 0.3, 0.2, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 128
	gt.height = 128
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	aura.texture = gt
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	aura.material = add
	aura.visible = false
	aura.name = "RageAura"
	e.add_child(aura)
	e.move_child(aura, 0)
	return aura


## 휘청인 뒤(EXPOSED_TIME) 받는 피해를 키운다. 공유 HitData 를 고치지 않도록 복사해서 돌려준다.
static func exposed_hit(e: EnemyBase, hit: HitData) -> HitData:
	if float(e.get("exposed_left")) <= 0.0 or e.state == EnemyBase.State.DEAD:
		return hit
	var h := hit.copy()
	h.damage *= EXPOSED_DAMAGE_MULT
	return h


## 지금 크게 휘청이는 중인가 (맞아도 휘청임을 끊지 않는다 — _is_armored 에서 쓴다).
static func is_staggered(e: EnemyBase) -> bool:
	return float(e.get("stagger_left")) > 0.0 and e.state == EnemyBase.State.HIT


## 흐트러짐이 가득 찼다 (EnemyBase._break 앞에서 부른다). 체력이 PURIFY_HP 보다 많으면 무너지지 않고
## 크게 휘청인다: 공격이 끊기고, STAGGER_TIME 동안 멈추고, EXPOSED_TIME 동안 받는 피해 ×1.5, 흐트러짐은 0 으로.
## 처리했으면 true (그러면 _break 를 부르지 않는다).
static func stagger_instead(e: EnemyBase, permanent: bool) -> bool:
	if permanent or e.hp <= e.max_hp * PURIFY_HP or e.state == EnemyBase.State.DEAD:
		return false
	e.hitbox.deactivate()
	e.poise = 0.0
	e.poise_changed.emit(0.0, e.max_poise)
	e.set("stagger_left", STAGGER_TIME)
	e.set("exposed_left", EXPOSED_TIME)
	e._set_state(EnemyBase.State.HIT)
	e._timer = STAGGER_TIME
	e.velocity.x = e.last_hit_dir * 180.0
	e.anim_hint = ""
	Juice.shake(5.0)
	Juice.hitstop(0.05, 0.1)
	Sfx.play("guard_break", -4.0)   # 무너짐('broke')과 다른 소리: 아직 정화할 수 없다
	e._visual_call("impact", [e.last_hit_dir, 1.6])
	return true


## 맞은 뒤 부른다: 체력이 절반 아래면 분노에 들어간다 (한 번만). 들어갔으면 true.
static func check_rage(e: EnemyBase) -> bool:
	if e.get("rage") or e.hp <= 0.0 or e.hp > e.max_hp * RAGE_HP:
		return false
	e.set("rage", true)
	e.windup_time *= RAGE_TIME_MULT
	e.recover_time *= RAGE_TIME_MULT
	e.cooldown *= RAGE_TIME_MULT
	e.walk_speed *= RAGE_SPEED_MULT
	Juice.shake(7.0)
	Juice.hitstop(0.06, 0.1)
	Juice.rumble(0.5, 0.8, 0.3)
	_play_rage_sound(e)
	e._visual_call("impact", [0, 1.6])
	# 붉은 빛이 터진다
	var burst := CPUParticles2D.new()
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 40
	burst.lifetime = 0.9
	burst.position = Vector2(0, -e.hurt_height * 0.3)
	burst.direction = Vector2(0, -1)
	burst.spread = 180.0
	burst.gravity = Vector2(0, -40)
	burst.initial_velocity_min = 120.0
	burst.initial_velocity_max = 320.0
	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 5.0
	burst.color = Color(1.8, 0.6, 0.45, 0.9)
	burst.emitting = true
	e.add_child(burst)
	e.get_tree().create_timer(1.2).timeout.connect(burst.queue_free)
	return true


## 분노의 낮은 울림 (Sfx 는 높낮이를 못 바꿔서 여기서 따로 튼다. 음량 설정은 Master 버스로 따라간다).
static func _play_rage_sound(e: EnemyBase) -> void:
	var st: AudioStream = load(RAGE_SOUND)
	if st == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = "Master"
	p.volume_db = -2.0
	p.pitch_scale = 1.3
	e.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## 매 틱: 휘청 시간을 줄이고, 분노 중이면 빛이 맥동하고 몸이 아주 살짝 물든다. base_mod 는 씬에 적힌 Visual.modulate.
static func tick(e: EnemyBase, aura: Sprite2D, base_mod: Color, t: float, delta := 0.0) -> void:
	var sl := float(e.get("stagger_left"))
	if sl > 0.0:
		e.set("stagger_left", 0.0 if e.state != EnemyBase.State.HIT else maxf(sl - delta, 0.0))
	var ex := float(e.get("exposed_left"))
	if ex > 0.0:
		e.set("exposed_left", maxf(ex - delta, 0.0))
	var vis := e.get_node_or_null("Visual")
	if not e.get("rage"):
		if aura:
			aura.visible = false
		return
	var pulse := 0.75 + 0.25 * sin(t * 7.0)
	if aura:
		aura.visible = e.state != EnemyBase.State.DEAD
		aura.position = Vector2(0, -e.hurt_height * 0.15)
		var r := e.hurt_height * 1.1 / 128.0
		aura.scale = Vector2(r, r * 1.15) * (0.9 + 0.15 * pulse)
		aura.modulate = Color(1.0, 1.0, 1.0, 0.7 + 0.3 * pulse)
	if vis:
		vis.modulate = base_mod * Color(1, 1, 1).lerp(RAGE_TINT, RAGE_TINT_MIN + RAGE_TINT_PULSE * pulse)

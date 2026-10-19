extends Herbalist
class_name EliteHerbalist
## 중간 보스 '포자 어미'. 포자 적(약초꾼)의 거대화: 크기 1.8배, 체력 4배, 흐트러짐 2.5배, 피해 1.35배.
## 포자 구름이 더 넓고(×1.5) 더 아프다. 분노하면 소녀의 등 뒤에도 구름 하나를 더 뿌린다. 공통 수치는 EliteTraits 에.
## 심연 · 포자 어미의 둥지(abyss_mini_1)에 산다 (어두운 방).
##
## 심연에는 등불 능력이 있어야 오므로 싸우는 소녀는 언제나 등불을 들고 있다 → 구름은 닿자마자 타서 걷힌다(약초꾼의 약속 그대로).
## 그래서 어미는 등불로 못 막는 공격을 둘 더 쓴다 (둘 다 가드·구르기로 피한다):
##  - **몸통 후려치기**: 가까이(swipe_range) 붙으면 길게 예고하고 큰 몸으로 후려친다.
##  - **포자 덩이**: 구름을 뿌릴 때 소녀 쪽으로 천천히 따라오는 덩이를 2발(분노 3발) 던진다. 저스트 가드로 되받아칠 수 있다.

@export var elite_name := "포자 어미"
## 이 거리 안이면 구름 대신 몸통 후려치기
@export var swipe_range := 300.0
@export var swipe_damage := 22.0
## 후려치기 판정 (바라보는 방향 기준, 큰 몸에 맞춘 값)
@export var swipe_box := Rect2(10, -170, 320, 230)
@export var bolt_damage := 13.0
@export var bolt_speed := 430.0
@export var bolts_per_volley := 2

const BOLT := preload("res://scenes/combat/projectile.tscn")

var rage := false
var elite_damage_mult := 1.0
var stagger_left := 0.0
var exposed_left := 0.0
var _aura: Sprite2D
var _base_mod := Color(1, 1, 1, 1)
var _t := 0.0
## 이번 공격: "swipe"(후려치기) / "spores"(구름 + 포자 덩이)
var _mode := ""


func _ready() -> void:
	EliteTraits.apply(self, EliteTraits.HP_MULT, EliteTraits.SIZE_MULT, 1.35)
	cloud_radius *= 1.5
	cloud_dps *= elite_damage_mult
	keep_distance *= 1.2
	super._ready()
	EliteTraits.fit_visual(self)
	_aura = EliteTraits.make_aura(self)
	var vis := get_node_or_null("Visual")
	if vis:
		_base_mod = vis.modulate


func receive_hit(hit: HitData, hb: Hurtbox) -> String:
	var r := super.receive_hit(EliteTraits.exposed_hit(self, hit), hb)
	if EliteTraits.check_rage(self):
		bolts_per_volley = 3
	return r


func _break(permanent: bool) -> void:
	if EliteTraits.stagger_instead(self, permanent):
		return
	super._break(permanent)


func _is_armored(hit: HitData) -> bool:
	return EliteTraits.is_staggered(self) or super._is_armored(hit)


func _physics_process(delta: float) -> void:
	_t += delta
	EliteTraits.tick(self, _aura, _base_mod, _t, delta)
	super._physics_process(delta)


func _begin_windup() -> void:
	super._begin_windup()
	_mode = "spores"
	if player:
		var d := player.global_position - global_position
		if absf(d.x) <= swipe_range and absf(d.y) < 180.0:
			_mode = "swipe"
			facing = 1 if d.x > 0.0 else -1
			_timer = windup_time * 1.35   # 길게 예고: 큰 몸이 뒤로 젖혀진다
			anim_hint = ""


func _strike() -> void:
	if _mode == "swipe":
		_set_state(State.STRIKE)
		anim_hint = ""
		_timer = strike_time + 0.06
		var hit := HitData.make(swipe_damage, 0.0, self, Vector2(560, -230))
		hitbox.set_box(swipe_box, facing)
		hitbox.activate(hit, strike_time + 0.06)
		Juice.shake(3.0)
		return
	super._strike()   # 구름 (약초꾼)
	_throw_bolt(0)
	if rage and player:
		# 분노 중엔 소녀 뒤에도 구름 하나를 더 (등불이 없다면 앞뒤로 갇힌다)
		var away := 1.0 if player.global_position.x > global_position.x else -1.0   # 어미에서 소녀 너머 쪽
		_spawn_cloud(player.global_position + Vector2(away * 260.0, -40.0))


## 포자 덩이를 하나 던지고, 남았으면 조금 뒤 다음 것을 던진다.
func _throw_bolt(i: int) -> void:
	if player == null or state in [State.DEAD, State.BROKEN, State.HIT]:
		return
	var p: Projectile = BOLT.instantiate()
	p.kind = Projectile.Kind.LEAF
	p.speed = bolt_speed
	p.damage = bolt_damage
	p.poise = 0.0
	p.reflectable = true
	p.homing = 1.1
	p.lifetime = 3.6
	p.size = Vector2(40, 28)
	p.color = Color(0.72, 1.0, 0.55)
	get_parent().add_child(p)
	var origin := global_position + Vector2(facing * 60.0 * EliteTraits.SIZE_MULT, -hurt_height * 0.5)
	p.global_position = origin
	var aim := player.global_position + Vector2(0, -50) - origin
	# 여러 발이면 위아래로 조금씩 벌린다
	var spread := (float(i) - (bolts_per_volley - 1) * 0.5) * 0.22
	p.launch(aim.normalized().rotated(spread * facing), self, false)
	_visual_call("recoil", [1.2])
	if i + 1 < bolts_per_volley:
		get_tree().create_timer(0.22).timeout.connect(func() -> void:
			if is_instance_valid(self):
				_throw_bolt(i + 1))

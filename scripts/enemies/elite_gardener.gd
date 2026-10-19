extends Gardener
class_name EliteGardener
## 중간 보스 '정원사 장로'. 씨앗 적(정원사)의 거대화: 크기 1.8배, 체력 4배, 흐트러짐 2.5배.
## 씨앗은 한 번에 3발, 더 크고(40×28) 조금 더 아프다(×1.1 — 첫 보스 전이라). 분노하면 4발. 공통 수치는 EliteTraits 에.
## 수관 · 장로의 온실(canopy_mini_2)에 산다.

@export var elite_name := "정원사 장로"
## 씨앗 크기 (일반 정원사 26×18)
@export var elite_seed_size := Vector2(40, 28)

var rage := false
var elite_damage_mult := 1.0
var stagger_left := 0.0
var exposed_left := 0.0
var _aura: Sprite2D
var _base_mod := Color(1, 1, 1, 1)
var _t := 0.0


func _ready() -> void:
	EliteTraits.apply(self, EliteTraits.HP_MULT, EliteTraits.SIZE_MULT, 1.1)
	seed_damage *= elite_damage_mult
	seed_speed *= 1.1
	shots_per_volley = 3
	keep_distance *= 1.3
	super._ready()
	EliteTraits.fit_visual(self)
	_aura = EliteTraits.make_aura(self)
	var vis := get_node_or_null("Visual")
	if vis:
		_base_mod = vis.modulate


func receive_hit(hit: HitData, hb: Hurtbox) -> String:
	var r := super.receive_hit(EliteTraits.exposed_hit(self, hit), hb)
	if EliteTraits.check_rage(self):
		shots_per_volley = 4
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


## 큰 씨앗을 쏜다 (Gardener._shoot 와 같되 크기·높이만 장로 몸에 맞춘다).
func _shoot() -> void:
	if player == null:
		return
	var p: Projectile = PROJECTILE.instantiate()
	p.kind = Projectile.Kind.FEATHER
	p.speed = seed_speed
	p.damage = seed_damage
	p.poise = 0.0
	p.reflectable = true
	p.size = elite_seed_size
	p.color = Color(0.8, 0.6, 0.28)
	p.look = "elite_seed"   # 이펙트 리뉴얼 F2
	get_parent().add_child(p)
	var origin := global_position + Vector2(facing * 70.0 * EliteTraits.SIZE_MULT, -hurt_height * 0.55)
	p.global_position = origin
	var dir := (player.global_position + Vector2(0, -40) - origin).normalized()
	p.launch(dir, self, false)
	Fx.spawn("seed_muzzle", origin, {"rot": rad_to_deg(dir.angle()), "scale": 1.3})
	_shot += 1
	_visual_call("recoil", [1.3])
	if _shot < shots_per_volley:
		get_tree().create_timer(0.18).timeout.connect(func() -> void:
			if state == State.STRIKE:
				_shoot())

extends Guard
class_name EliteGuard
## 중간 보스 '경비대장'. 방패 돌진 적(경비병)의 거대화: 크기 1.8배, 체력 4배, 흐트러짐 2.5배.
## 돌진은 더 빠르고 아프고(×1.3) 판정이 몸에 맞게 1.6배. 방패는 연속 4번까지 막는다. 공통 수치는 EliteTraits 에.
## 마을 · 경비대장의 망루(village_mini_1)에 산다.

@export var elite_name := "경비대장"

var rage := false
var elite_damage_mult := 1.0
var stagger_left := 0.0
var exposed_left := 0.0
var _aura: Sprite2D
var _base_mod := Color(1, 1, 1, 1)
var _t := 0.0


func _ready() -> void:
	EliteTraits.apply(self, EliteTraits.HP_MULT, EliteTraits.SIZE_MULT, 1.3)
	attack_range *= 1.4
	charge_damage *= elite_damage_mult
	charge_speed *= 1.1
	charge_time *= 1.2
	block_limit = 4
	stuck_time = 2.0
	super._ready()
	EliteTraits.fit_visual(self)
	_aura = EliteTraits.make_aura(self)
	var vis := get_node_or_null("Visual")
	if vis:
		_base_mod = vis.modulate


func receive_hit(hit: HitData, hb: Hurtbox) -> String:
	var r := super.receive_hit(EliteTraits.exposed_hit(self, hit), hb)
	if EliteTraits.check_rage(self):
		charge_chance = minf(charge_chance * 1.6, 0.7)   # 분노하면 돌진을 더 자주
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


## 돌진 판정을 큰 몸에 맞춘다 (Guard._strike 가 켠 판정의 상자만 키운다).
func _strike() -> void:
	super._strike()
	if _mode == "charge" and state == State.STRIKE:
		hitbox.set_box(Rect2(Vector2(10, -110) * EliteTraits.BOX_MULT, Vector2(150, 140) * EliteTraits.BOX_MULT), facing)

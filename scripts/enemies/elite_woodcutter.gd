extends EnemyBase
class_name EliteWoodcutter
## 중간 보스 '늙은 벌목꾼'. 대검 적(나무꾼)의 거대화: 크기 1.8배, 체력 4배, 흐트러짐 2.5배, 피해 1.1배(첫 보스보다 세지 않게).
## 체력 절반 아래로 떨어지면 분노(빨라지고 붉은 빛). 무너짐(정화)은 절반 이하에서만 — 그 위에선 크게 휘청.
## 공통 수치는 EliteTraits 에. 수관 · 늙은 벌목꾼의 가지(canopy_mini_1)에 산다. 보스식 체력 바는 MiniBossRoom 이 붙인다.

@export var elite_name := "늙은 벌목꾼"

var rage := false
var elite_damage_mult := 1.0
var stagger_left := 0.0
var exposed_left := 0.0
var _aura: Sprite2D
var _base_mod := Color(1, 1, 1, 1)
var _t := 0.0


func _ready() -> void:
	EliteTraits.apply(self, EliteTraits.HP_MULT, EliteTraits.SIZE_MULT, 1.1)
	attack_range *= 1.5          # 긴 대검: 더 멀리서 휘두른다
	windup_time *= 1.1           # 묵직한 예고
	super._ready()
	EliteTraits.fit_visual(self)
	_aura = EliteTraits.make_aura(self)
	var vis := get_node_or_null("Visual")
	if vis:
		_base_mod = vis.modulate


func receive_hit(hit: HitData, hb: Hurtbox) -> String:
	var r := super.receive_hit(EliteTraits.exposed_hit(self, hit), hb)
	EliteTraits.check_rage(self)
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

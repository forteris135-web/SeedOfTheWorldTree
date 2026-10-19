extends Machine
class_name EliteMachine
## 중간 보스 '채굴 괴수'. 침식된 기계의 거대화: 크기 1.8배, 체력 3배(기계는 원래 단단해서 4배는 지루하다), 흐트러짐 2.5배,
## 피해 1.25배(들이받기 30 = 등불 기사의 가장 센 공격과 같게). 들이받기는 더 빠르고 판정이 몸에 맞게 1.6배.
## 약공격은 여전히 35%만 들어간다(씨앗 베기·낙하 공격으로) — 단, 크게 휘청인 뒤 2초 동안은 온전히. 공통 수치는 EliteTraits 에.
## 채굴장 · 괴수의 굴(mine_mini_1)에 산다.

@export var elite_name := "채굴 괴수"

var rage := false
var elite_damage_mult := 1.0
var stagger_left := 0.0
var exposed_left := 0.0
var _aura: Sprite2D
var _base_mod := Color(1, 1, 1, 1)
var _t := 0.0


func _ready() -> void:
	EliteTraits.apply(self, 3.0, EliteTraits.SIZE_MULT, 1.25)
	attack_range *= 1.4
	ram_speed *= 1.1
	ram_time *= 1.15
	super._ready()
	EliteTraits.fit_visual(self)
	_aura = EliteTraits.make_aura(self)
	var vis := get_node_or_null("Visual")
	if vis:
		_base_mod = vis.modulate


func receive_hit(hit: HitData, hb: Hurtbox) -> String:
	# 크게 휘청인 뒤(EXPOSED_TIME)에는 단단함이 풀린다: 약공격도 온전히 들어간다 (그때가 몰아칠 때)
	var saved := light_damage_ratio
	if exposed_left > 0.0:
		light_damage_ratio = 1.0
	# Machine.receive_hit 은 받은 HitData 의 피해를 직접 줄이므로, 한 휘두름이 같이 쓰는 원본을 건드리지 않게 늘 복사해 넘긴다
	var h := EliteTraits.exposed_hit(self, hit)
	if h == hit:
		h = hit.copy()
	var r := super.receive_hit(h, hb)
	light_damage_ratio = saved
	if EliteTraits.check_rage(self):
		ram_speed *= 1.15
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


## 들이받기 판정을 큰 몸에 맞춘다.
func _strike() -> void:
	super._strike()
	if _ramming and state == State.STRIKE:
		hitbox.set_box(Rect2(Vector2(0, -120) * EliteTraits.BOX_MULT, Vector2(170, 150) * EliteTraits.BOX_MULT), facing)

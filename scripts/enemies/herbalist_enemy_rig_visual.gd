extends EnemyRigVisual
class_name HerbalistEnemyRigVisual
## 약초꾼(포자 몹) 부위 뼈대 그림. EnemyRigVisual 위에 약초꾼만의 움직임을 더한다 (판정·시간은 전혀 건드리지 않는다):
##  - 뿌리기 세 박자: 예고 동안 숙이며 손을 뒤로 끌어 모으고 몸의 버섯이 숨을 들이쉬듯 부풀어 떨린다 →
##    뿌리는 순간(포자 구름이 생기는 때) 앞손을 내던지듯 펴고 버섯이 '퐁' 터지며 손끝·버섯에서 빛나는 포자 가루가 흩날린다 →
##    두 팔을 벌려 흩뿌린 뒤 천천히 거둔다 (자세는 원형 herbalist 의 windup / scatter_a / scatter_b / ready).
##  - 버섯 덮인 긴 머리·망토·천 자락·흰 머리는 늘어진 천(chain)이라 몸보다 한 박자 늦게 출렁인다 (원형 _motion 의 숨쉬기·흔들기).
##  - 물러남: 소녀가 가까이 오면 앞손을 든 채 뒷걸음질 (걷기 자세를 backstep 으로 바꿔 끼운다).
##  - 포자 어미(거대화)의 몸통 후려치기는 휘두르기 세 박자 그대로 (windup → strike), 포자 덩이를 던질 때는 반동.
##  - 구원 가능한 약초꾼: 무릎 꿇고 기다리는 동안은 두건 쓰고 눈 감은 얼굴(머리 변형 "closed"), 정화되는 순간 얼굴을 든다.
## 쓰는 법: 씬의 Visual 에 이 스크립트, rig_id = "herbalist"(또는 "herbalist_savable"). 자세는 data/rigs/_archetypes/herbalist.json.

## 부푸는 버섯 뼈 이름 (설계도에 있는 것만 쓴다)
const MUSHROOMS := ["mush_a", "mush_b"]
## 예고 동안 버섯이 부푸는 몫 / 뿌리는 순간 터지는 세기 (스프링 속도)
const SWELL := 0.18
const POP_KICK := 9.0
const RETREAT_SPEED := 40.0
## 포자 가루 색 (HDR — 1 을 넘겨 화면 글로우가 번진다)
const SPORE_COLOR := Color(1.7, 1.45, 0.8, 0.9)

static var _spore_tex: Texture2D

var _mush_bones: PackedInt32Array = []
var _mush_puff := RigMotion.Chan.new(0.0)   # 버섯 부풂 (0 = 그대로)
var _h_last_state := -1
var _h_second_burst := false
var _h_spores: CPUParticles2D
var _h_closed_eyes := false
var _h_has_closed := false


func _ready() -> void:
	super._ready()
	if rig == null or not rig.data.has("bones"):
		return
	for m in MUSHROOMS:
		var i := rig.bone_index(m)
		if i >= 0:
			_mush_bones.append(i)
	for b in rig.data["bones"]:
		if str(b.get("name", "")) == "head" and (b.get("variants", {}) as Dictionary).has("closed"):
			_h_has_closed = true
	_h_spores = CPUParticles2D.new()
	_h_spores.name = "Spores"
	_h_spores.emitting = false
	_h_spores.one_shot = true
	_h_spores.explosiveness = 0.85
	_h_spores.local_coords = false
	_h_spores.amount = 18
	_h_spores.lifetime = 1.1
	_h_spores.direction = Vector2(1, -0.4)
	_h_spores.spread = 50.0
	_h_spores.gravity = Vector2(0, -35)
	_h_spores.initial_velocity_min = 60.0
	_h_spores.initial_velocity_max = 190.0
	_h_spores.damping_min = 60.0
	_h_spores.damping_max = 120.0
	_h_spores.scale_amount_min = 0.25
	_h_spores.scale_amount_max = 0.6
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	_h_spores.color_ramp = fade
	_h_spores.color = SPORE_COLOR
	_h_spores.texture = _soft_dot()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_h_spores.material = add
	add_child(_h_spores)


func _process(delta: float) -> void:
	if not _ready_ok or _enemy == null or motion == null:
		super._process(delta)
		return
	var st := _enemy.state
	var hint: String = _enemy.anim_hint
	# 물러남: 걷기·대기 자세를 뒷걸음 자세로 잠깐 바꿔 끼운다
	var swap := {}
	if st == EnemyBase.State.CHASE and _enemy.velocity.x * float(_enemy.facing) < -RETREAT_SPEED:
		swap = {"walk": motion.poses["walk"], "idle": motion.poses["idle"]}
		motion.poses["walk"] = motion.pose("backstep")
		motion.poses["idle"] = motion.pose("backstep")
	# 버섯: 예고 동안 부풀고(떨림), 뿌리는 순간 터졌다 출렁이며 돌아온다
	var swell := 0.0
	if st == EnemyBase.State.WINDUP:
		var w := _enemy.windup_progress
		swell = SWELL * w + sin(_t * 38.0) * 0.025 * w
	if st != _h_last_state:
		if st == EnemyBase.State.STRIKE and hint == "scatter":
			_mush_puff.vel += POP_KICK
			_h_burst(1.0)
			_h_second_burst = false
		_h_last_state = st
	if st == EnemyBase.State.STRIKE and hint == "scatter" and not _h_second_burst and _enemy.phase_progress >= 0.35:
		_h_second_burst = true
		_h_burst(0.6)
	_mush_puff.spring(swell, 180.0, 11.0, minf(delta, 0.05))
	var k := clampf(1.0 + _mush_puff.v, 0.8, 1.6)
	for i in _mush_bones:
		rig.scl[i] = Vector2(k, k)
	super._process(delta)
	for key in swap:
		motion.poses[key] = swap[key]
	# 구원 가능한 자: 무릎 꿇고 기다리는 동안 눈을 감는다
	if _h_has_closed:
		var want := _enemy.savable and st == EnemyBase.State.BROKEN
		if want != _h_closed_eyes:
			_h_closed_eyes = want
			rig.set_variant("head", "closed" if want else "")


## 손끝(앞손 축 끝)에서 빛나는 포자 가루를 흩날린다. strength 0~1.
func _h_burst(strength: float) -> void:
	if _h_spores == null:
		return
	var hand := rig.bone_index("weapon")
	var at := Vector2.ZERO
	if hand >= 0:
		at = rig.to_rig_local(rig.xf[hand] * Vector2(0, rig.bone_len[hand]))
		at = rig.transform * at
	_h_spores.position = at
	_h_spores.direction = Vector2(float(visible_facing()), -0.4)
	_h_spores.amount = maxi(6, int(18 * strength))
	_h_spores.scale_amount_min = 0.25 * sqrt(art_scale)
	_h_spores.scale_amount_max = 0.6 * sqrt(art_scale)
	_h_spores.initial_velocity_max = 190.0 * sqrt(art_scale)
	_h_spores.restart()
	_h_spores.emitting = true


## 둥글고 부드러운 빛 점 (포자 가루 하나) — 한 번 만들어 모든 약초꾼이 함께 쓴다.
static func _soft_dot() -> Texture2D:
	if _spore_tex:
		return _spore_tex
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 32
	gt.height = 32
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	_spore_tex = gt
	return gt

extends EnemyRigVisual
class_name GardenerEnemyRigVisual
## 정원사(씨앗 대롱 몹) 부위 뼈대 그림. EnemyRigVisual 위에 정원사만의 움직임을 더한다 (판정·시간은 전혀 건드리지 않는다):
##  - 대롱 겨눔: 쫓기·예고·쏘기·회복·물러남 동안 어깨(위팔)가 돌아 대롱이 소녀 가슴을 겨눈다 (EnemyRigVisual 의 arm_kind = "gun").
##    쏠 때마다 대롱이 튀어 오르고 윗몸이 젖혀지며, 등에 진 씨앗 꼬투리가 반동에 출렁인다 (원형 gardener 의 움직임 지도).
##  - 물러남: 소녀가 가까이 오면 대롱을 겨눈 채 뒷걸음질하다가, 폴짝 뛰기 직전에 무릎을 굽혀 웅크리고(예비) →
##    뛰는 순간 몸을 쭉 펴며 튀어 오르고(다리는 공중에서 접힘) → 내려앉을 때 다시 웅크린다 (착지 충격).
##    뛰는 때는 Gardener 의 물러남 타이머(_timer 가 −0.4 에 닿으면 뛴다)를 읽어 맞춘다.
##  - 등의 씨앗 꼬투리·덩굴은 늘어진 천처럼 한 박자 늦게 따라오고, 숨쉴 때·걸을 때 들썩인다 (설계도 chain + 원형 _motion).
##  - 구원 가능한 정원사: 무릎 꿇고 기다리는 동안은 눈을 감은 얼굴(머리 변형 "closed"), 정화되는 순간 눈을 뜬다.
## 쓰는 법: 씬의 Visual 에 이 스크립트, rig_id = "gardener"(또는 "gardener_savable"), arm_kind = "gun". 자세는 data/rigs/_archetypes/gardener.json.

## 이 속도(px/초)보다 빨리 바라보는 반대쪽으로 움직이면 '물러남' 자세 (대롱을 겨눈 채 뒷걸음)
const RETREAT_SPEED := 40.0
## 물러나는 동안 Gardener._timer 가 이 값 아래면 다음 폴짝 뛰기(−0.4) 직전이라 웅크린다 (약 0.16초 전).
## 내려앉은 직후는 이미 이 값 아래라 착지 웅크림이 그대로 다음 도약의 예비가 된다.
const HOP_CROUCH_AT := -0.24
## 뛰는 순간 몸을 펴는 세기 (덧붙이는 스프링: crouch − = 펴짐, squash − = 세로로 늘어남)
const HOP_STRETCH := 1.8

var _g_hop_air := false
var _g_walk := {}   # 물러나는 동안 잠깐 빼 둔 원래 걷기·대기 자세 (매 프레임 새 사전을 만들지 않게)
var _g_idle := {}
var _g_closed_eyes := false
var _g_has_closed := false


func _ready() -> void:
	super._ready()
	if rig and rig.data.has("bones"):
		for b in rig.data["bones"]:
			if str(b.get("name", "")) == "head" and (b.get("variants", {}) as Dictionary).has("closed"):
				_g_has_closed = true


func _process(delta: float) -> void:
	if not _ready_ok or _enemy == null or motion == null:
		super._process(delta)
		return
	var st := _enemy.state
	var on_floor := _enemy.is_on_floor()
	# 폴짝 뛰는 순간: 웅크렸던 다리를 펴며 몸이 세로로 늘어난다 (내려앉는 웅크림은 EnemyRigVisual 이 한다)
	var hop_air := not on_floor and _enemy.velocity.y < -120.0
	if hop_air and not _g_hop_air and st in LOCO_STATES:
		motion.kick("crouch", -HOP_STRETCH)
		motion.kick("squash", -2.2)
	_g_hop_air = hop_air
	# 물러남: 걷기·대기 자세를 물러남 자세로 잠깐 바꿔 끼운다 (EnemyRigVisual 이 걷기를 섞을 때 이 자세가 쓰인다)
	var swapped := false
	if st == EnemyBase.State.CHASE and _enemy.velocity.x * float(_enemy.facing) < -RETREAT_SPEED:
		var crouch: bool = on_floor and _enemy.state_timer() < HOP_CROUCH_AT
		var rp := motion.pose("retreat_crouch" if crouch else "retreat")
		_g_walk = motion.poses["walk"]
		_g_idle = motion.poses["idle"]
		motion.poses["walk"] = rp
		motion.poses["idle"] = rp
		swapped = true
	super._process(delta)
	if swapped:
		motion.poses["walk"] = _g_walk
		motion.poses["idle"] = _g_idle
	# 구원 가능한 자: 무릎 꿇고 기다리는 동안 눈을 감는다
	if _g_has_closed:
		var want := _enemy.savable and st == EnemyBase.State.BROKEN
		if want != _g_closed_eyes:
			_g_closed_eyes = want
			rig.set_variant("head", "closed" if want else "")

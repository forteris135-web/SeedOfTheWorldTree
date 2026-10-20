extends RigMotion
class_name HookedRigMotion
## RigMotion 에 '움직이기 직전 갈고리'를 하나 단 것. 그림 쪽(EnemyRigVisual 을 이은 기계·어부 그림)이
## 상태 자세를 고른 뒤, 실제로 관절이 움직이기 직전에 목표를 조금 고칠 수 있게 한다
## (드릴 떨림, 대기 중 겨눔, 박자 흔들기, 들이받기 예고 자세 등). 공용 틀(RigMotion·EnemyRigVisual)은 그대로 둔다.

## 갈고리: func(delta: float) -> void. update() 첫머리에 불린다 (target·ground_settle 등을 고쳐도 이번 프레임에 반영된다).
var hook: Callable


func _init(part_rig: PartRig, pre_update := Callable()) -> void:
	super(part_rig)
	hook = pre_update


func update(delta: float, ctx: Dictionary) -> void:
	if hook.is_valid():
		hook.call(delta)
	super.update(delta, ctx)

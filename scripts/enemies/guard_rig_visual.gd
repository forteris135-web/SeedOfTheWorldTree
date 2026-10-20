extends EnemyRigVisual
class_name GuardRigVisual
## 방패 경비병(일반·구원형·경비대장)의 부위 뼈대 그림. EnemyRigVisual 에 경비병만의 연출을 더한다.
## 판정·시간은 Guard 그대로다 (그림이 논리를 따라간다). 방패는 앞팔(arm_f) 손에 쥔 큰 잎 방패(weapon)라
## 그림이 보는 쪽에 늘 방패가 있다 — Guard 의 방패 판정이 보는 visible_facing()/is_facing_settled() 는 부모 것 그대로.
##
## 더하는 것:
##  - 붉은 예고(돌진 준비): 예비 자세 대신 '돌진 준비'(낮게 웅크려 방패를 내리고 뒷발로 땅을 긁는다) → 돌진은 설계도 poses.charge
##  - 박힘(stuck): 방패가 벽·끝에 박힌 채 몸을 뒤로 당겼다 다시 밀어 넣으며 빼려고 버둥댄다
##  - 방패로 막음(block): 방패 팔이 몸 쪽으로 밀렸다 돌아오고 몸이 뒤로 살짝 밀린다 (푸른 번쩍임은 부모)
##  - 방패가 들림(연속 막기 한계 뒤 열린 동안): 서 있기·걷기·맞음 자세의 방패 팔이 옆으로 젖혀져 몸이 드러난다
## 자세 값은 data/rigs/guard*.json 의 poses (charge_windup, stuck_pull, shield_open 은 이 그림만 쓰는 자세).

## 박힘 버둥: 한 번 당기는 주기(초)
const STRUGGLE_PERIOD := 0.62
## 방패가 열린 동안 방패 팔 자세로 바꾸는 상태 자세들
const OPEN_POSES := ["idle", "walk", "hit", "alert", "backstep", "lunge", "air"]
## shield_open 자세가 덮어쓰는 채널 (방패 팔·몸통·머리)
const OPEN_KEYS := ["arm_f_up", "arm_f_lo", "weapon", "torso", "head", "arm_b_up", "arm_b_lo"]

var _guard_ok := false
var _orig := {}          # 자세 이름 → 원래 자세 사전 (바꿔 끼웠다 되돌린다)
var _open_set := {}      # 자세 이름 → 방패가 열린 자세 사전 (미리 만들어 둔다)
var _stuck_base := {}
var _stuck_pull := {}
var _stuck_mix := {}     # 매 프레임 값만 고쳐 쓰는 사전 (새로 만들지 않는다)
var _struggle_t := 0.0
var _struggle_n := 0
var _open_w := 0.0
var _was_open := false


func _ready() -> void:
	super._ready()
	if not _ready_ok or motion == null:
		return
	var open_pose: Dictionary = motion.pose("shield_open") if motion.has_pose("shield_open") else {}
	for n in OPEN_POSES:
		if not motion.has_pose(n):
			continue
		var src: Dictionary = motion.poses[n]
		_orig[n] = src
		var o: Dictionary = src.duplicate()
		for k in OPEN_KEYS:
			if open_pose.has(k):
				o[k] = open_pose[k]
		_open_set[n] = o
	if motion.has_pose("charge_windup"):
		_orig["windup"] = motion.poses["windup"]
	if motion.has_pose("stuck"):
		_stuck_base = motion.poses["stuck"]
		_stuck_pull = motion.poses.get("stuck_pull", _stuck_base)
		_stuck_mix = _stuck_base.duplicate()
		_orig["stuck"] = _stuck_base
	_guard_ok = true


func _process(delta: float) -> void:
	if _guard_ok and _enemy != null:
		_swap_poses(delta)
	super._process(delta)


## 이번 프레임에 부모가 고를 자세를 경비병 것으로 바꿔 끼운다 (사전 참조만 바꾼다 — 새 사전을 만들지 않는다).
func _swap_poses(delta: float) -> void:
	var st := _enemy.state
	var hint: String = _enemy.anim_hint
	# 붉은 예고(돌진 준비): 부모는 windup 과 charge 를 반씩 섞는다 → windup 자리에 '돌진 준비'를 끼운다
	if _orig.has("windup"):
		motion.poses["windup"] = motion.poses["charge_windup"] if (st == EnemyBase.State.WINDUP and hint == "red") else _orig["windup"]
	# 방패가 들려 열린 동안
	var open: bool = _enemy.is_block_open() if _enemy.has_method("is_block_open") else false
	if open != _was_open:
		_was_open = open
		for n in _open_set:
			motion.poses[n] = _open_set[n] if open else _orig[n]
		if open:
			# 방패가 위로 확 젖혀진다 (받아친 칼처럼 방패 팔이 튕겨 올라간다 — 사람 모양 지도: parry + = 무기 팔이 앞·위로)
			motion.kick("parry", 200.0)
			motion.transition(0.05)
	# 박힘: 몸을 뒤로 당겼다 다시 밀어 넣는다 (당기는 순간 몸이 뒤로 튕기고 먼지가 인다)
	if not _stuck_mix.is_empty():
		if st == EnemyBase.State.RECOVER and hint == "stuck":
			_struggle_t += delta
			var ph := fposmod(_struggle_t / STRUGGLE_PERIOD, 1.0)
			# 0.25초쯤은 박힌 채 힘을 모으다가(0) 확 당기고(1) 천천히 다시 밀어 넣는다
			var w := 0.0
			if ph > 0.35:
				var q := (ph - 0.35) / 0.65
				w = sin(PI * pow(q, 0.6))
			for k in _stuck_mix:
				_stuck_mix[k] = lerpf(float(_stuck_base.get(k, 0.0)), float(_stuck_pull.get(k, _stuck_base.get(k, 0.0))), w)
			var n := int(_struggle_t / STRUGGLE_PERIOD + 0.65)
			if n != _struggle_n:
				_struggle_n = n
				motion.kick("shove", -0.35)
				motion.kick("impact", 30.0)
				_step_puff(-20.0)
			motion.poses["stuck"] = _stuck_mix
		else:
			_struggle_t = 0.0
			_struggle_n = 0
			motion.poses["stuck"] = _stuck_base


## 방패로 막았다: 부모 연출(윗몸이 밀리고 푸른 번쩍임)에 더해 방패 팔이 몸 쪽으로 밀렸다 돌아오고 몸이 뒤로 조금 밀린다.
func block(dir: int, strength := 1.0) -> void:
	super.block(dir, strength)
	if motion == null:
		return
	motion.kick("parry", -120.0 * strength)   # 사람 모양 지도: parry − = 무기 팔이 뒤(몸 쪽)로
	motion.kick("shove", -0.25 * strength)

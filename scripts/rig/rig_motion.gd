class_name RigMotion
extends RefCounted
## 부위 뼈대(PartRig)를 움직이는 애니메이션 층. 몹·보스·NPC 의 그림(…_visual.gd)이 하나씩 들고 매 프레임 update() 를 부른다.
## 쓰는 쪽은 '지금의 목표 자세'(RigPoses 의 자세를 섞은 사전)만 정해 준다: set_target(자세, 보간 방식, 발 방식).
## 나머지는 여기서 한다:
##  1) 자세 값은 절대 '툭' 바뀌지 않는다. 상태가 바뀌면 이전 목표가 관성을 갖고 흘러가며 새 목표로 섞이고(transition),
##     모든 채널은 값+속도를 가진 스프링/감쇠로 목표를 쫓는다 (delta 기반 → FPS 에 상관없이 같은 모양).
##  2) 휘두르기 세 박자 three_beat(): 예비(당기며 끝에서 멈칫, 허리·몸통은 끝자락에 먼저 풀리기 시작)
##     → 타격(어깨가 먼저, 팔꿈치·무기가 한 박자씩 늦게 따라와 채찍처럼 지나침)
##     → 되돌림(출렁이며 준비 자세).
##  3) 발: 땅을 딛은 발은 세상에 고정(미끄러지지 않음). 걸을 때는 '걸은 거리'로 도는 걸음 위상이 두 발을 번갈아 옮기고,
##     서 있을 때·공격 중에는 자세의 발 자리에서 많이 어긋난 발만 한 걸음 옮긴다 (내딛기). 공중이면 다리를 접는다.
##  4) 다리 IK: 허벅지·정강이 두 뼈 (무릎은 앞으로) 또는 한 뼈 다리. 발이 닿지 않으면 엉덩이를 낮춘다 → 어떤 자세에서도 발바닥이 땅(y=0).
##     무릎 꿇기(kneel_*)는 무릎을 땅에 대고 정강이를 뒤로 눕힌 해와 섞는다.
##  5) 무기 땅 막기: ground_guard 부위의 껍질이 땅 아래로 들어가면 손목→팔꿈치→어깨 순으로 들어 올린다 (칼끝이 땅에 닿아 멈춘 것처럼).
##  6) 늘어진 천·잎(chain): 세상 각도로 스프링 → 몸이 돌면 한 박자 늦게 따라오고, 달리면 뒤로 날린다.
##  7) 땅 닿기(ground_lock): 무기 사슬을 뺀 몸의 가장 낮은 껍질 점이 땅 아래면 그만큼 몸 전체를 들어 올린다 (쓰러져 엎어질 때
##     머리가 땅에 박히지 않게). fall_angle/fall_pivot 은 몸을 통째로 돌리는 쓰러짐(기계·통나무 같은 몸)용으로 남겨 둔다.

## 보간 채널: 값 + 속도. 스프링·감쇠 모두 속도를 이어 가므로 어떤 전환에서도 끊기지 않는다.
class Chan:
	var v := 0.0
	var vel := 0.0

	func _init(start := 0.0) -> void:
		v = start

	## 스프링 (큰 delta 에서도 터지지 않게 잘게 나눈다)
	func spring(target: float, stiffness: float, damping: float, delta: float) -> void:
		var steps := maxi(1, ceili(delta * sqrt(stiffness) / 0.7))
		var h := delta / steps
		for i in steps:
			vel += ((target - v) * stiffness - vel * damping) * h
			v += vel * h

	## 지수 감쇠 따라가기 (속도도 기록 → 스프링으로 넘어가도 이어진다)
	func damp(target: float, speed: float, delta: float) -> void:
		var nv := lerpf(v, target, 1.0 - exp(-speed * delta))
		vel = (nv - v) / maxf(delta, 0.0001)
		v = nv


## 다리 하나
class Leg:
	var name := ""
	var sfx := "f"
	var up := -1
	var lo := -1          # -1 이면 한 뼈 다리
	var foot := -1
	var a := 0.0          # 허벅지 길이 (엉덩이 관절 → 무릎)
	var b := 0.0          # 정강이 길이 (무릎 → 발목)
	var knee_vec := Vector2.ZERO    # 허벅지 틀에서 무릎 자리
	var ankle_vec := Vector2.ZERO   # 정강이 틀에서 발목 자리
	var sole := Vector2.ZERO        # 발 틀(한 뼈 다리면 다리 틀)에서 발바닥 자리
	var foot_rest_world := 0.0      # 쉬는 자세의 발 세상 각도 (발이 땅에 평평한 각도)
	var ankle_h := 0.0              # 발바닥에서 발목까지 높이
	var knee_back := false          # 무릎이 뒤로 꺾이는 다리 (새 다리 등)
	var x := 0.0          # 발바닥 x (뼈대 단위, 몸 원점 기준, + 앞)
	var h := 0.0          # 발 높이 (땅 위, + 위)
	var swing := false
	var timed := false    # 시간으로 가는 걸음 (아니면 걸음 위상)
	var t := 0.0
	var from_x := 0.0
	var to_x := 0.0
	var dur := 0.2
	var lift := 0.0
	var planted_now := false   # 이번 프레임에 땅을 디뎠다 (먼지용)
	var knee_x := 0.0          # 무릎 꿇은 무릎의 땅 자리 (뼈대 단위, 세상에 고정 — 몸이 움직이면 발처럼 반대로)
	var knee_set := false
	var kneel_phi := 0.0       # 무릎 꿇은 발의 각도 (부드럽게 따라간다 — 고른 각도가 프레임마다 튀지 않게)
	var kneel_phi_set := false


## 보간 방식 (상태마다 고른다)
enum Drive { NORMAL, SOFT, FAST, SETTLE, HEAVY, QUICK, SLOW }
## 발 방식
enum Feet { POSE, GAIT, AIR }

## 몸·발 채널 (뼈 이름이 아닌 것)
const BODY_KEYS := ["hip_x", "hip_y", "lean", "pitch", "step_thr", "step_dur", "step_lift"]
const FOOT_PREFIX := ["foot_", "lift_", "toe_", "kneel_"]
## 걸음: 이 속도(L/초)보다 느리면 걸음 위상을 멈추고 한 걸음씩 맞춘다
const GAIT_MIN_SPEED := 0.25
## 무기 땅 막기: 땅 위 여유 (뼈대 단위)와 관절별 최대 고침 각도. 어깨부터 든다 (팔이 곧은 채 칼끝이 땅에 얹힌 모양),
## 어깨로 모자라면 팔꿈치, 그다음 손목.
const GUARD_MARGIN := 3.0
const GUARD_LIMITS := [1.3, 0.45, 0.45]   # 어깨, 팔꿈치, 손목(무기) (라디안)
## 휘두르기: 관절마다 늦게 따라오는 정도 (타격 진행도의 몫). 어깨가 끌고 팔꿈치·무기가 채찍처럼 따라온다.
const STRIKE_LAG := {"arm_f_lo": 0.1, "weapon": 0.2, "head": 0.15, "arm_b_up": 0.05, "arm_b_lo": 0.12}
## 허리·몸통·무게중심은 예비동작 끝에서 먼저 풀리기 시작한다: 타격에 들어설 때 이미 EARLY_UNWIND 몫만큼 앞으로 와 있다.
const EARLY_KEYS := ["torso", "lean", "hip_x"]
const EARLY_UNWIND := 0.4

var rig: PartRig
var poses := {}
var keys: Array = []
var ch := {}            # 채널 이름 → Chan
var target := {}
var drive := Drive.NORMAL
var feet_mode := Feet.POSE
## 다리 길이 단위 L (뼈대 단위)와 서 있는 뿌리 높이(뿌리 y, 땅 0, 위 −)
var L := 100.0
var stand_root_y := -100.0
var legs: Array[Leg] = []
var root := 0
## 마지막으로 계산된 최종 채널 값 (덧붙임 포함) — 시험·잔상이 읽는다
var fin := {}
## 덧붙이는 스프링: impact(도, + = 뒤로 젖힘), parry(도, 무기 튕김), recoil(도), crouch(L), shove(L), squash(비율)
var sp := {}
const SPRINGS := {
	"impact": [200.0, 18.0], "parry": [260.0, 20.0], "recoil": [300.0, 22.0],
	"crouch": [220.0, 22.0], "shove": [200.0, 20.0], "squash": [260.0, 18.0], "thud": [300.0, 16.0],
}
var time := 0.0
## 숨쉬기 세기 (0~1, 쓰는 쪽이 정한다)
var breath := 1.0
## 몸 기울기 배수 (거대화 몹이 앞머리를 땅에 박지 않게 줄인다)
var tilt_scale := 1.0
## 쓰러짐: 넘어가는 각도(라디안, + = 앞으로), 축(뼈대 단위), 땅 닿기 세기 (0~1)
var fall_angle := 0.0
var fall_pivot := Vector2.ZERO
var ground_lock := 0.0

var _fade_from := {}
var _fade_vel := {}
var _fade_t := 1.0
var _fade_len := 0.1
var _tgt_prev := {}
var _tgt_vel := {}
var _phase := 0.0
var _airborne := false
var _chains: Array = []   # [뼈 번호, 강성, 감쇠, 끌림, 중력, 최대(라디안), Chan(세상 각도), 처음인가]
var _guard_bones: PackedInt32Array = []
var _guard_chain: PackedInt32Array = []   # [어깨, 팔꿈치, 손목] 뼈 번호 (없으면 -1)
var _bone_keys: Array = []   # [채널 이름, 뼈 번호]
var _lock_bones: PackedInt32Array = []   # 땅 닿기에 쓰는 뼈 (무기 사슬 빼고)
var _swing_bob := 0.0


func _init(part_rig: PartRig) -> void:
	rig = part_rig
	var d := rig.data
	poses = RigPoses.build(str(d.get("archetype", "humanoid")), d.get("poses", {}))
	# 채널: base 의 모든 키 + 자세들에 나오는 뼈 이름
	var base: Dictionary = poses["base"]
	for k in base:
		keys.append(k)
	for pname in poses:
		for k in poses[pname]:
			if not keys.has(k):
				keys.append(k)
	for k in keys:
		ch[k] = Chan.new(float(base.get(k, 0.0)))
		target[k] = float(base.get(k, 0.0))
		_tgt_prev[k] = target[k]
		_tgt_vel[k] = 0.0
		if not BODY_KEYS.has(k) and not _is_foot_key(k) and rig.has_bone(k):
			_bone_keys.append([k, rig.bone_index(k)])
	for s in SPRINGS:
		sp[s] = Chan.new(0.0)
	_setup_legs()
	_setup_guard()
	for i in rig.names.size():
		var in_weapon := false
		for c in _guard_chain:
			if c >= 0 and (i == c or rig._is_descendant(i, c)):
				in_weapon = true
		if not in_weapon:
			_lock_bones.append(i)
	for i in rig.names.size():
		var b: Dictionary = d["bones"][i]
		if b.has("chain"):
			var c: Dictionary = b["chain"]
			_chains.append([i, float(c.get("stiffness", 60.0)), float(c.get("damping", 7.0)), float(c.get("drag", 0.0004)),
				float(c.get("gravity", 0.3)), deg_to_rad(float(c.get("max", 55.0))), Chan.new(0.0), true])
	fin = target.duplicate()
	_place_feet_home()
	update(0.0, {})


static func _is_foot_key(k: String) -> bool:
	for p in FOOT_PREFIX:
		if k.begins_with(p):
			return true
	return false


func _setup_legs() -> void:
	var d := rig.data
	root = 0
	var total := 0.0
	for ld in d.get("legs", []):
		var leg := Leg.new()
		leg.name = str(ld["name"])
		leg.sfx = leg.name.substr(leg.name.rfind("_") + 1) if leg.name.contains("_") else leg.name
		leg.up = rig.bone_index(str(ld["up"]))
		leg.foot = rig.bone_index(str(ld["foot"]))
		leg.knee_back = bool(ld.get("knee_back", false))
		if ld.has("lo"):
			leg.lo = rig.bone_index(str(ld["lo"]))
			leg.a = float(ld["a"])
			leg.b = float(ld["b"])
			leg.knee_vec = rig.base_pos[leg.lo]
			leg.ankle_vec = rig.base_pos[leg.foot]
		leg.sole = rig.sole.get(leg.foot, Vector2.ZERO)
		# 쉬는 자세의 발 세상 각도 = 뿌리부터 발까지 쉬는 회전의 합
		var w := 0.0
		var j := leg.foot
		while j >= 0:
			w += rig.rest[j]
			j = rig.parent[j]
		leg.foot_rest_world = w
		if leg.lo >= 0:
			leg.ankle_h = leg.sole.rotated(w).y
			total += leg.a + leg.b + leg.ankle_h
		else:
			total += leg.sole.length()
		legs.append(leg)
	if legs.is_empty():
		L = maxf(float(d.get("height", 300.0)) * 0.45, 1.0)
		stand_root_y = float(d.get("root_offset", [0, -L])[1])
		return
	L = total / legs.size()
	# 서 있는 뿌리 높이: 기본 발 자리에서 두 다리가 모두 (무릎을 조금 굽혀) 닿는 가장 높은 자리
	var base: Dictionary = poses["base"]
	var ry := -INF
	for leg in legs:
		var j0 := rig.base_pos[leg.up].rotated(rig.rest[root])
		var home := float(base.get("foot_" + leg.sfx, 0.0)) * L
		var need := 0.0
		if leg.lo >= 0:
			var r := (leg.a + leg.b) * 0.985
			var dx := home - (leg.sole.rotated(leg.foot_rest_world) * -1.0).x - j0.x
			need = -leg.ankle_h - sqrt(maxf(r * r - dx * dx, 1.0)) - j0.y
		else:
			var r1 := leg.sole.length()
			var dx1 := home - j0.x
			need = -sqrt(maxf(r1 * r1 - dx1 * dx1, 1.0)) - j0.y
		ry = maxf(ry, need)
	stand_root_y = ry


func _setup_guard() -> void:
	var d := rig.data
	for nm in d.get("ground_guard", []):
		var i := rig.bone_index(str(nm))
		if i >= 0:
			_guard_bones.append(i)
	var wc: Array = d.get("chains", {}).get(str(d.get("weapon_chain", "arm_f")), [])
	_guard_chain = PackedInt32Array([-1, -1, -1])
	for k in mini(wc.size(), 3):
		_guard_chain[k] = rig.bone_index(str(wc[k]))


func _place_feet_home() -> void:
	var base: Dictionary = poses["base"]
	for leg in legs:
		leg.x = float(base.get("foot_" + leg.sfx, 0.0)) * L
		leg.h = 0.0
		leg.swing = false


# ---------- 쓰는 쪽이 부르는 것 ----------

## 이름의 자세 (base 까지 합친 사전). 없으면 base.
func pose(name: String) -> Dictionary:
	return poses.get(name, poses["base"])


func has_pose(name: String) -> bool:
	return poses.has(name)


## 두 자세를 섞는다 (w = 0 → a, 1 → b).
func mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := {}
	var base: Dictionary = poses["base"]
	for k in keys:
		out[k] = lerpf(float(a.get(k, base.get(k, 0.0))), float(b.get(k, base.get(k, 0.0))), w)
	return out


## 지금 보이는 자세 (채널 값). 새 동작을 '지금 자세에서' 시작할 때 쓴다.
func capture() -> Dictionary:
	var out := {}
	for k in keys:
		out[k] = (ch[k] as Chan).v
	return out


## 이번 프레임의 목표. 쓰는 쪽이 매 프레임 부른다.
func set_target(p: Dictionary, mode := Drive.NORMAL, feet := Feet.POSE) -> void:
	for k in keys:
		target[k] = float(p.get(k, target[k]))
	drive = mode
	feet_mode = feet


## 상태 전환: 이전 목표가 관성을 갖고 흘러가며 len 초 동안 새 목표로 섞인다 (0 이면 바로).
func transition(len := 0.1) -> void:
	if len <= 0.0:
		_fade_t = 1.0
		return
	_fade_from = _tgt_prev.duplicate()
	_fade_vel = _tgt_vel.duplicate()
	_fade_t = 0.0
	_fade_len = len


## 덧붙이는 스프링에 충격(속도)을 준다.
func kick(name: String, velocity: float) -> void:
	if sp.has(name):
		(sp[name] as Chan).vel += velocity


func spring_value(name: String) -> float:
	return (sp[name] as Chan).v if sp.has(name) else 0.0


## 채널의 속도를 바꾼다 (저스트 가드로 막힌 칼을 되튕길 때: 지나가던 속도를 뒤집는다).
func scale_velocity(names: Array, factor: float) -> void:
	for k in names:
		if ch.has(k):
			(ch[k] as Chan).vel *= factor


## 뼈대가 좌우로 뒤집힌 순간(보이는 폭이 0 을 지날 때) 부른다: 땅에 딛은 발이 세상에서 제자리에 남도록 x 를 뒤집는다.
func flip_feet() -> void:
	for leg in legs:
		leg.x = -leg.x
		leg.from_x = -leg.from_x
		leg.to_x = -leg.to_x
		leg.knee_x = -leg.knee_x


## 발을 지금 자세의 자리로 바로 옮긴다 (순간 이동·처음 놓일 때).
func snap_feet() -> void:
	for leg in legs:
		leg.x = float(target.get("foot_" + leg.sfx, 0.0)) * L
		leg.h = 0.0
		leg.swing = false


## 휘두르기 세 박자. phase: "windup"/"strike"/"recover", p: 그 국면의 진행도(0→1).
## from: 예비가 시작될 때(또는 되돌림이 시작될 때) 보이던 자세. over: 타격 끝의 지나침 크기.
func three_beat(from: Dictionary, windup: Dictionary, strike: Dictionary, ready: Dictionary, phase: String, p: float, over := 0.16) -> Dictionary:
	var base: Dictionary = poses["base"]
	match phase:
		"windup":
			var out := mix(from, windup, Motion.anticipation(p))
			# 허리·몸통은 팔이 아직 뒤로 가는 동안(예비 끝 25%) 먼저 앞으로 풀리기 시작한다 (힘이 아래에서 위로 전해지는 휘두르기)
			var early := smoothstep(0.75, 1.0, p) * EARLY_UNWIND
			if early > 0.0:
				for k in EARLY_KEYS:
					if out.has(k):
						var w0 := float(windup.get(k, base.get(k, 0.0)))
						out[k] = float(out[k]) + (float(strike.get(k, base.get(k, 0.0))) - w0) * early
			return out
		"strike":
			var out := {}
			for k in keys:
				var lag: float = STRIKE_LAG.get(k, 0.0)
				var u := clampf((p - lag) / (1.0 - lag), 0.0, 1.0)
				var s := strike_curve(u, over * (1.0 + lag * 2.0))
				var a := float(windup.get(k, base.get(k, 0.0)))
				var b := float(strike.get(k, base.get(k, 0.0)))
				if EARLY_KEYS.has(k):
					a += (b - a) * EARLY_UNWIND   # 예비 끝에서 이미 이만큼 풀려 있다
				out[k] = lerpf(a, b, s)
			return out
		_:
			return mix(from, ready, Motion.settle(Motion.ease_in(p, 2.0), 1.5, 2.5))


## 타격 곡선 0→1: 정지에서 가속해 가운데쯤 가장 빠르고, 끝에서 over 만큼 지나쳤다 돌아온다.
static func strike_curve(q: float, over := 0.16) -> float:
	var c := clampf(q, 0.0, 1.0)
	var w := pow(c, 0.75)
	var base := w * w * (3.0 - 2.0 * w)
	return base + over * sin(PI * clampf((c - 0.4) / 0.6, 0.0, 1.0))


# ---------- 매 프레임 ----------

## ctx: speed(뼈대 단위/초, + 앞) / dx(이번 프레임 몸이 간 거리, 뼈대 단위, + 앞) / vy(뼈대 단위/초, + 아래) / grounded(bool)
func update(delta: float, ctx: Dictionary) -> void:
	delta = minf(delta, 0.05)
	time += delta
	var speed := float(ctx.get("speed", 0.0))
	var dx := float(ctx.get("dx", 0.0))
	var grounded := bool(ctx.get("grounded", true))
	var vy := float(ctx.get("vy", 0.0))

	# 1) 관성 크로스페이드
	var raw := target.duplicate()
	if _fade_t < 1.0 and delta > 0.0:
		_fade_t = minf(_fade_t + delta / maxf(_fade_len, 0.001), 1.0)
		var w := smoothstep(0.0, 1.0, _fade_t)
		var decay := exp(-delta * 18.0)
		for k in keys:
			_fade_from[k] = float(_fade_from.get(k, raw[k])) + float(_fade_vel.get(k, 0.0)) * delta
			_fade_vel[k] = float(_fade_vel.get(k, 0.0)) * decay
			raw[k] = lerpf(_fade_from[k], raw[k], w)
	for k in keys:
		if delta > 0.0:
			_tgt_vel[k] = (float(raw[k]) - float(_tgt_prev[k])) / delta
		_tgt_prev[k] = raw[k]
	# 2) 채널이 목표를 쫓는다
	for k in keys:
		var c: Chan = ch[k]
		if delta <= 0.0:
			c.v = raw[k]
			continue
		_drive_chan(c, float(raw[k]), k, delta)
	for s in SPRINGS:
		var kc: Array = SPRINGS[s]
		(sp[s] as Chan).spring(0.0, kc[0], kc[1], delta)
	# 3) 최종 값 (덧붙임)
	for k in keys:
		fin[k] = (ch[k] as Chan).v
	var imp: float = sp["impact"].v
	var par: float = sp["parry"].v
	var rec: float = sp["recoil"].v
	_add("torso", -imp * 1.0 - rec * 0.3)
	_add("head", -imp * 1.4)
	_add("arm_b_up", imp * 0.9)
	_add("arm_b_lo", imp * 0.5)
	_add("arm_f_up", imp * 0.35 - par - rec)
	_add("arm_f_lo", -par * 0.5)
	_add("weapon", -par * 0.6)
	fin["hip_x"] = float(fin["hip_x"]) - imp * 0.004 + float(sp["shove"].v)
	fin["hip_y"] = float(fin["hip_y"]) + float(sp["crouch"].v) + absf(float(sp["thud"].v)) * 0.01
	if breath > 0.0:
		var b := sin(time * 2.2)
		_add("torso", b * 1.3 * breath)
		_add("head", sin(time * 2.2 + 0.7) * 1.1 * breath)
		_add("arm_b_up", sin(time * 2.2 + 0.3) * 1.6 * breath)
		_add("arm_f_up", sin(time * 2.2 + 0.5) * 0.8 * breath)
		fin["hip_y"] = float(fin["hip_y"]) + (b * 0.5 + 0.5) * 0.008 * breath
	# 걸음에 따른 팔 흔들기 (두 발의 앞뒤 차이로)
	if legs.size() >= 2 and feet_mode == Feet.GAIT:
		var swing := clampf((legs[0].x - legs[1].x) / maxf(L * 0.6, 1.0), -1.0, 1.0)
		var amt := clampf(absf(speed) / L, 0.0, 1.0)
		_add("arm_b_up", -swing * 22.0 * amt)
		_add("arm_b_lo", -absf(swing) * 6.0 * amt)
		_add("arm_f_up", swing * 6.0 * amt)
		_add("torso", absf(swing) * 1.5 * amt)

	# 4) 몸 (뿌리·몸통·팔·머리)
	_apply_body()
	# 5) 발과 다리
	_update_feet(delta, speed, dx, grounded)
	_solve_legs()
	# 6) 몸 전체 (쓰러짐) + 땅 닿기 — 무기는 빼고 잰다 (긴 칼이 땅을 짚어 몸을 장대처럼 들어 올리지 않게)
	_apply_fall()
	# 7) 무기 땅 막기 (쓰러진 몸 기준으로)
	_ground_guard()
	# 8) 늘어진 천·잎
	_update_chains(delta, speed, vy)
	rig.apply()


func _add(k: String, v: float) -> void:
	if fin.has(k):
		fin[k] = float(fin[k]) + v


func _drive_chan(c: Chan, tgt: float, k: String, delta: float) -> void:
	var slow := 0.6 if k == "head" else 1.0
	match drive:
		Drive.SOFT:
			c.spring(tgt, 90.0 * slow, 17.0, delta)
		Drive.FAST:
			# 타격: 곡선이 시간 기반이라 팔은 바짝 따라간다. 몸통·허리는 무거워 조금 늦게 (팔보다 먼저 출발하므로 늦어도 같이 끝난다)
			if k in ["torso", "lean", "hip_x", "hip_y"]:
				c.spring(tgt, 520.0, 44.0, delta)   # 스프링: 예비에서 쌓인 속도를 이어 받아 '툭' 하지 않는다
			else:
				c.damp(tgt, 40.0 if k == "head" else 90.0, delta)
		Drive.SETTLE:
			c.spring(tgt, 150.0 * slow, 12.0, delta)
		Drive.HEAVY:
			c.spring(tgt, 60.0 * slow, 9.0, delta)
		Drive.QUICK:
			c.spring(tgt, 320.0 * slow, 30.0, delta)
		Drive.SLOW:
			c.spring(tgt, 40.0 * slow, 11.0, delta)
		_:
			c.spring(tgt, 220.0 * slow, 24.0, delta)


func _apply_body() -> void:
	var lean := deg_to_rad(float(fin["lean"]) * tilt_scale)
	rig.rot[root] = rig.rest[root] + lean
	var ry := stand_root_y + float(fin["hip_y"]) * L - _swing_bob
	var rx := float(fin["hip_x"]) * L
	# 무릎 꿇기: 가장 깊이 꿇는 다리의 무릎을 땅의 한 자리에 고정하고(knee_x), 허벅지가 그 무릎에서 서 있는 각도(pitch)로
	# 뿌리 자리를 정한다. pitch 0 = 허벅지가 똑바로 서서 엉덩이가 무릎 위, 1 = 허벅지가 앞으로 80도 눕혀져 엉덩이가 무릎 높이 (엎어짐).
	var kw := 0.0
	var kleg: Leg = null
	for leg in legs:
		var k := clampf(float(fin.get("kneel_" + leg.sfx, 0.0)), 0.0, 1.0)
		if k <= 0.01:
			leg.knee_set = false
		if k > kw and leg.lo >= 0:
			kw = k
			kleg = leg
	for leg in legs:
		var k := clampf(float(fin.get("kneel_" + leg.sfx, 0.0)), 0.0, 1.0)
		if k > 0.01 and not leg.knee_set and leg.lo >= 0:
			# 꿇기 시작: 딛은 발은 그 자리에 두고, 정강이가 발에서 앞으로 눕도록 무릎 자리를 발보다 정강이 길이만큼 앞에 잡는다
			# (서 있다 꿇으면 발끝은 남고 무릎이 앞으로 내려간다)
			leg.knee_x = leg.x + leg.b * 0.9
			leg.knee_set = true
			leg.kneel_phi_set = false
	if kleg:
		var j0 := rig.base_pos[kleg.up].rotated(rig.rot[root])
		var phi := deg_to_rad(clampf(float(fin.get("pitch", 0.0)), 0.0, 1.0) * 80.0)
		var jd := Vector2(kleg.knee_x, -L * 0.06) + Vector2(sin(phi), -cos(phi)) * kleg.a
		var rk := jd - j0
		ry = lerpf(ry, maxf(ry, rk.y), kw)
		rx = lerpf(rx, rk.x, kw)
	rig.root_pos = Vector2(rx, ry)
	for c in _chains:
		rig.rot[c[0]] = rig.rest[c[0]]   # 늘어진 천은 쉬는 각도에서 출발 (자세 채널이 있으면 아래에서 덮어쓴다)
	for bk in _bone_keys:
		var i: int = bk[1]
		if i == root:
			continue
		var v := deg_to_rad(float(fin[bk[0]]))
		if bk[0] == "torso":
			v *= lerpf(1.0, tilt_scale, 0.5)
		rig.rot[i] = v if rig.has_axis[i] == 1 else rig.rest[i] + v
	rig.compute()


func _update_feet(delta: float, speed: float, dx: float, grounded: bool) -> void:
	_swing_bob = 0.0
	for leg in legs:
		leg.planted_now = false
	if legs.is_empty():
		return
	if not grounded or feet_mode == Feet.AIR:
		# 공중: 다리를 접어 엉덩이 아래에 매단다
		_airborne = true
		for leg in legs:
			var j := rig.xf[leg.up].origin
			var home := float(fin.get("foot_" + leg.sfx, 0.0)) * L
			var tx := j.x + home * 0.5
			var hang := (leg.a + leg.b) * 0.82 + leg.ankle_h if leg.lo >= 0 else leg.sole.length() * 0.95
			var th := maxf(-(j.y + hang), 0.0)
			if delta > 0.0:
				leg.x = Motion.damp(leg.x, tx, 12.0, delta)
				leg.h = Motion.damp(leg.h, th, 14.0, delta)
			leg.swing = false
		return
	if _airborne:
		_airborne = false
		for leg in legs:
			leg.swing = false
			leg.planted_now = true
	# 딛은 발(과 꿇은 무릎)은 세상에 고정: 몸이 간 만큼 반대로
	for leg in legs:
		if leg.knee_set:
			leg.knee_x -= dx
		if leg.swing:
			leg.from_x -= dx
		else:
			leg.x -= dx
			if delta > 0.0:
				leg.h = Motion.damp(leg.h, 0.0, 30.0, delta)
	var aspeed := absf(speed) / maxf(L, 1.0)
	if feet_mode == Feet.GAIT and aspeed > GAIT_MIN_SPEED:
		# 걸음 위상 (걸은 거리로): 두 발이 반 주기 어긋나 번갈아 옮긴다
		var stride := L * clampf(0.95 + aspeed * 0.16, 0.95, 1.7)
		var swing_frac := clampf(0.38 + aspeed * 0.025, 0.38, 0.5)
		var stance := stride * (1.0 - swing_frac)
		var dir := signf(speed)
		var lift := L * clampf(0.07 + aspeed * 0.012, 0.06, 0.13)
		_phase += absf(dx) / stride
		for k in legs.size():
			var leg := legs[k]
			var home := float(fin.get("foot_" + leg.sfx, 0.0)) * L
			var ph := fposmod(_phase + (0.5 if k % 2 == 1 else 0.0), 1.0)
			var to := home + dir * stance * 0.5
			if ph < swing_frac:
				if not leg.swing or leg.timed:
					leg.swing = true
					leg.timed = false
					leg.from_x = leg.x
				leg.t = ph / swing_frac
				leg.to_x = to
				leg.x = lerpf(leg.from_x, to, smoothstep(0.0, 1.0, leg.t))
				leg.h = lift * sin(PI * leg.t)
				_swing_bob = maxf(_swing_bob, sin(PI * leg.t) * L * 0.025 * clampf(aspeed, 0.0, 1.0))
			elif leg.swing and not leg.timed:
				leg.swing = false
				leg.x = to
				leg.h = 0.0
				leg.planted_now = true
		return
	# 서 있거나 공격 중: 옮기던 발은 시간으로 마저 딛고, 딛은 발은 자세의 자리에서 많이 어긋나면 한 걸음 옮긴다
	var any_swing := false
	for leg in legs:
		var home := float(fin.get("foot_" + leg.sfx, 0.0)) * L
		if leg.swing:
			if not leg.timed:
				leg.timed = true
				leg.dur = 0.12
				leg.lift = maxf(leg.h, L * 0.04)
			leg.to_x = home
			if delta > 0.0:
				leg.t = minf(leg.t + delta / maxf(leg.dur, 0.04), 1.0)
			leg.x = lerpf(leg.from_x, home, smoothstep(0.0, 1.0, leg.t))
			leg.h = leg.lift * sin(PI * leg.t)
			if leg.t >= 1.0:
				leg.swing = false
				leg.h = 0.0
				leg.planted_now = true
			else:
				any_swing = true
	if any_swing:
		return
	var thr := float(fin.get("step_thr", 0.2)) * L
	var worst: Leg = null
	var worst_err := thr
	for leg in legs:
		var err := absf(leg.x - float(fin.get("foot_" + leg.sfx, 0.0)) * L)
		if err > worst_err:
			worst_err = err
			worst = leg
	if worst:
		worst.swing = true
		worst.timed = true
		worst.t = 0.0
		worst.from_x = worst.x
		worst.dur = clampf(float(fin.get("step_dur", 0.2)), 0.06, 0.5)
		worst.lift = float(fin.get("step_lift", 0.08)) * L * clampf(worst_err / maxf(L * 0.3, 1.0), 0.5, 1.2)


func _solve_legs() -> void:
	if legs.is_empty():
		return
	# 닿지 않는 발이 있으면 엉덩이를 낮춘다 (발바닥이 늘 땅에)
	var drop := 0.0
	for leg in legs:
		if leg.lo < 0 or float(fin.get("kneel_" + leg.sfx, 0.0)) > 0.5:
			continue
		var j := rig.xf[leg.up].origin
		var phi := leg.foot_rest_world + deg_to_rad(float(fin.get("toe_" + leg.sfx, 0.0)))
		var a := Vector2(leg.x, -leg.h) - leg.sole.rotated(phi)
		var r := (leg.a + leg.b) * 0.995
		var dxa := a.x - j.x
		if absf(dxa) >= r:
			continue
		var need_y := a.y - sqrt(r * r - dxa * dxa)
		if j.y < need_y:
			drop = maxf(drop, need_y - j.y)
	if drop > 0.0:
		rig.root_pos.y += drop
		rig.compute()
	for leg in legs:
		_solve_leg(leg)
	rig.compute()
	# 무릎 꿇은 다리: 정강이·발 그림의 가장 낮은 점이 땅에 오도록 뿌리를 올리거나 내리고 다시 푼다 (가라앉거나 뜨지 않게)
	var lift := 0.0
	var kmax := 0.0
	for leg in legs:
		var kw := clampf(float(fin.get("kneel_" + leg.sfx, 0.0)), 0.0, 1.0)
		if kw <= 0.0 or leg.lo < 0:
			continue
		var low := rig.lowest_y(PackedInt32Array([leg.lo, leg.foot]), false)
		if kw > kmax:
			kmax = kw
			lift = low * kw
	if absf(lift) > 0.5:
		rig.root_pos.y -= lift
		rig.compute()
		for leg in legs:
			_solve_leg(leg)
		rig.compute()


func _solve_leg(leg: Leg) -> void:
	var j := rig.xf[leg.up].origin
	var pw := rig.world_rot(rig.parent[leg.up]) if rig.parent[leg.up] >= 0 else 0.0
	var s := Vector2(leg.x, -leg.h)
	var kw := clampf(float(fin.get("kneel_" + leg.sfx, 0.0)), 0.0, 1.0)
	if leg.lo < 0:
		# 한 뼈 다리: 다리를 발 쪽으로 돌리고, 길이 차이는 축 방향으로 살짝 늘이거나 줄인다
		var d := s - j
		var r_w := d.angle() - leg.sole.angle()
		rig.rot[leg.up] = r_w - pw
		rig.scl[leg.up] = Vector2(1.0, clampf(d.length() / maxf(leg.sole.length(), 1.0), 0.82, 1.08))
		return
	var phi := leg.foot_rest_world + deg_to_rad(float(fin.get("toe_" + leg.sfx, 0.0)))
	var a_pt := s - leg.sole.rotated(phi)
	var d := a_pt - j
	var dist := clampf(d.length(), absf(leg.a - leg.b) + 0.5, leg.a + leg.b - 0.05)
	var cos_al := (leg.a * leg.a + dist * dist - leg.b * leg.b) / (2.0 * leg.a * dist)
	var al := acos(clampf(cos_al, -1.0, 1.0))
	var base := d.angle()
	var th1 := base + al if leg.knee_back else base - al
	var knee := j + Vector2.from_angle(th1) * leg.a
	var th2 := (a_pt - knee).angle()
	var r_up := th1 - leg.knee_vec.angle()
	var r_lo := th2 - leg.ankle_vec.angle()
	if kw > 0.0:
		# 무릎 꿇기 해: 무릎을 땅에 (엉덩이 관절보다 조금 앞), 정강이는 뒤로 눕고, 발끝이 땅을 짚는다
		var knee_k := Vector2(leg.knee_x if leg.knee_set else j.x + leg.a * 0.12, -L * 0.06)
		var th1k := (knee_k - j).angle()
		var th2k := PI + 0.3       # 정강이는 뒤로, 발목 쪽이 조금 들린다 (발끝을 세워 땅을 짚는다)
		var r_up_k := th1k - leg.knee_vec.angle()
		var r_lo_k := th2k - leg.ankle_vec.angle()
		var phi_best := _kneel_foot_angle(leg, j + Vector2.from_angle(th1k) * leg.a + Vector2.from_angle(th2k) * leg.b)
		if not leg.kneel_phi_set:
			leg.kneel_phi = phi_best
			leg.kneel_phi_set = true
		else:
			leg.kneel_phi = lerp_angle(leg.kneel_phi, phi_best, 0.25)
		var phi_k := leg.kneel_phi
		r_up = lerp_angle(r_up, r_up_k, kw)
		r_lo = lerp_angle(r_lo, r_lo_k, kw)
		phi = lerp_angle(phi, phi_k, kw)
	rig.rot[leg.up] = r_up - pw
	rig.rot[leg.lo] = r_lo - r_up
	rig.rot[leg.foot] = phi - r_lo


## 무릎 꿇은 발의 각도: 발목 자리(ankle)에서 발을 발끝 쪽으로 세워 가장 낮은 껍질 점이 땅(0)에 가장 가까운 각도 (몇 개 견줘 고른다).
func _kneel_foot_angle(leg: Leg, ankle: Vector2) -> float:
	var best := leg.foot_rest_world + 1.0
	var best_err := INF
	for k in 31:
		var phi := leg.foot_rest_world + 0.2 + k * 0.05
		var low := -INF
		for q in rig.hulls[leg.foot]:
			low = maxf(low, (ankle + q.rotated(phi)).y)
		var err := absf(low)
		if err < best_err:
			best_err = err
			best = phi
	return best


## 무기 땅 막기: 지킬 부위의 가장 낮은 껍질 점이 땅(0) 아래면 어깨 → 팔꿈치 → 손목 순으로 들어 올린다.
## 몸 전체 변환(쓰러짐, body_xf)을 포함한 '보이는' 자리로 잰다 (body_xf 는 회전·이동뿐이라 관절을 돌린 각도가 그대로 보인다).
func _ground_guard() -> void:
	if _guard_bones.is_empty():
		return
	var bx := rig.body_xf
	for iter in 4:
		var found := _deepest_guard_point(bx)
		var deepest: float = found[0]
		if deepest <= -GUARD_MARGIN:
			return
		var q: Vector2 = found[1]
		var qb: int = found[2]
		var fixed := false
		for c in 3:
			var jb := _guard_chain[c]
			if jb < 0:
				continue
			# 이 관절이 그 점을 움직일 수 있어야 한다 (점의 뼈가 이 관절이거나 그 자식)
			if qb != jb and not rig._is_descendant(qb, jb):
				continue
			var pj := bx * rig.xf[jb].origin
			var rr := (q - pj).length()
			if rr < 1.0:
				continue
			var want := (-GUARD_MARGIN - pj.y) / rr
			if want < -1.0 or want > 1.0:
				continue
			var cur := (q - pj).angle()
			var s1 := asin(want)
			var s2 := PI - s1
			var d1 := wrapf(s1 - cur, -PI, PI)
			var d2 := wrapf(s2 - cur, -PI, PI)
			var dd := d1 if absf(d1) < absf(d2) else d2
			var lim: float = GUARD_LIMITS[c]
			var used := clampf(dd, -lim, lim)
			rig.rot[jb] += used
			rig.compute_from(jb)
			fixed = true
			if absf(used - dd) < 0.001:
				break
			# 한계까지 돌렸는데 모자라면 다음 관절이 마저 든다: 점 다시 찾기
			found = _deepest_guard_point(bx)
			if float(found[0]) <= -GUARD_MARGIN:
				break
			q = found[1]
			qb = found[2]
		if not fixed:
			return


## [가장 낮은 y, 그 점, 그 뼈] — 지킬 부위들의 껍질 점 중 (body_xf 포함)
func _deepest_guard_point(bx: Transform2D) -> Array:
	var deepest := -INF
	var q := Vector2.ZERO
	var qb := -1
	for i in _guard_bones:
		var t := bx * rig.xf[i]
		for hp in rig.hulls[i]:
			var p := t * hp
			if p.y > deepest:
				deepest = p.y
				q = p
				qb = i
	return [deepest, q, qb]


func _update_chains(delta: float, speed: float, vy: float) -> void:
	for c in _chains:
		var i: int = c[0]
		var p := rig.parent[i]
		var pw := rig.world_rot(p) if p >= 0 else 0.0
		var local_want := rig.rot[i]
		var want := pw + local_want
		if rig.has_axis[i] == 1:
			want = lerp_angle(want, 0.0, float(c[4]))   # 중력: 똑바로 아래로 늘어지려 한다
		want += clampf(speed * float(c[3]), -0.6, 0.6) - clampf(vy * float(c[3]) * 0.5, -0.4, 0.4)
		var chn: Chan = c[6]
		if c[7] or delta <= 0.0:
			chn.v = want
			chn.vel = 0.0
			c[7] = false
		else:
			chn.v = pw + wrapf(chn.v - pw, -PI, PI)   # 한 바퀴 차이는 같은 각도
			chn.spring(want, c[1], c[2], delta)
		var lw: float = c[5]
		rig.rot[i] = clampf(chn.v - pw, local_want - lw, local_want + lw)
		rig.compute_from(i)


func _apply_fall() -> void:
	if absf(fall_angle) < 0.0001 and ground_lock <= 0.0:
		rig.body_xf = Transform2D.IDENTITY
		return
	var t := Transform2D(0.0, fall_pivot) * Transform2D(fall_angle, Vector2.ZERO) * Transform2D(0.0, -fall_pivot)
	rig.body_xf = t
	if ground_lock > 0.0:
		# 몸이 땅 아래로 들어간 만큼만 들어 올린다 (발은 IK 로 이미 땅에 있다 — 끌어내리지 않는다)
		var low := rig.lowest_y(_lock_bones)
		if low > 0.0:
			t.origin.y -= low * ground_lock
		rig.body_xf = t


# ---------- 시험·도구용 ----------

## 발바닥 높이들 (뼈대 단위, 땅 0, 아래 +) — body_xf 포함.
func sole_ys() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for leg in legs:
		var t := rig.body_xf * rig.xf[leg.foot]
		out.append((t * leg.sole).y)
	return out


## 지금 걸음 중인 발이 있는가
func any_swing() -> bool:
	for leg in legs:
		if leg.swing:
			return true
	return false

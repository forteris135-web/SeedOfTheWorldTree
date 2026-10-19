class_name RigPoses
## 부위 뼈대의 '원형(archetype)별 자세 모음'. 같은 원형의 뼈대(뼈 이름이 같은)는 이 자세를 함께 쓰고,
## 뼈대 설계도(data/rigs/<id>.json)의 "poses" 가 필요한 값만 덮어쓴다 → 새 몹은 대부분 데이터만으로 움직인다.
##
## 자세 = 채널 이름 → 값. 빠진 채널은 "base" 값.
##  - 몸 채널: hip_x / hip_y (다리 길이 L 의 몇 배. hip_x + = 앞, hip_y + = 아래로 웅크림), lean (엉덩이 전체 기울기, 도, + = 앞으로)
##  - 발 채널 (다리 사슬 이름 leg_f → 접미사 f): foot_f (발 자리, L 배, 몸 가운데 기준 + = 앞), lift_f (발 들기, L 배),
##    toe_f (발 각도, 도), kneel_f (0~1: 1 이면 그 무릎을 땅에 꿇는다)
##  - 걸음 채널: step_thr (발을 옮기는 어긋남, L 배), step_dur (한 걸음 시간, 초), step_lift (걸음 높이, L 배)
##  - 그 밖의 이름 = 뼈 이름. 값은 도(degree), 시계 방향 + (오른쪽을 보는 기준).
##      · 축(tip)이 있는 뼈(팔다리·무기·늘어진 천): **절대** 지역 각도. 0 = 부모 틀에서 똑바로 아래로 늘어짐.
##        아래로 늘어진 팔에 + 를 주면 뒤로, − 면 앞으로 든다. −90 = 앞으로 수평, −180 = 머리 위, −200 = 머리 위에서 조금 뒤.
##        아래팔(arm_*_lo) − = 팔꿈치를 굽힘(앞쪽으로), 무기(weapon) − = 손목을 앞으로 꺾음.
##      · 축이 없는 뼈(몸통·머리·장식): 쉬는 자세에서 **더하는** 각도. 몸통·머리 + = 앞으로 숙임.
## 팔을 머리 위로 넘겨 앞으로 내려치는 휘두르기는 각도가 '머리 위를 지나며' 이어지게 쓴다:
##   예비 −200(머리 위 뒤) → 타격 −82(앞 아래). (+160 → −82 로 쓰면 등 뒤 아래로 돌아 버린다.)
## 팔 각도는 몸통 틀 기준이라 몸통을 숙이면(+) 팔도 그만큼 뒤로 돈다: 세상에서 '앞 아래 30도'를 원하면 팔 = −60 − 몸통 각도.

const BASE := {
	"hip_x": 0.0, "hip_y": 0.05, "lean": 0.0,
	"torso": 0.0, "head": 0.0,
	"arm_f_up": -20.0, "arm_f_lo": -10.0, "weapon": 0.0,
	"arm_b_up": 8.0, "arm_b_lo": -12.0, "hand_b": 0.0,
	"foot_f": 0.2, "foot_b": -0.2, "lift_f": 0.0, "lift_b": 0.0, "toe_f": 0.0, "toe_b": 0.0,
	"kneel_f": 0.0, "kneel_b": 0.0,
	"step_thr": 0.2, "step_dur": 0.2, "step_lift": 0.08,
}

## 사람 모양 + 무기 팔 (나무꾼·정원사·약초꾼·경비병·오웬·어부 …). 뼈 이름:
## hips(뿌리) / torso / head / arm_f_up·arm_f_lo·weapon (앞팔=무기 팔) / arm_b_up·arm_b_lo·hand_b (뒷팔) /
## leg_f_up·leg_f_lo·foot_f, leg_b_up·leg_b_lo·foot_b (다리, IK) / 그 밖의 장식·천은 아무 이름 (chain 으로 흔들림).
const HUMANOID := {
	"base": {},
	"idle": {"torso": 6.0, "head": 3.0, "arm_f_up": -34.0, "arm_f_lo": -12.0, "weapon": -6.0, "arm_b_up": 6.0, "arm_b_lo": -14.0},
	## 걷기·쫓기: 앞으로 조금 숙이고 무기를 낮게 든다. 팔 흔들기·엉덩이 들썩임은 걸음이 더한다.
	"walk": {"torso": 12.0, "head": 2.0, "hip_y": 0.07, "arm_f_up": -44.0, "arm_f_lo": -14.0, "weapon": -6.0, "arm_b_up": 4.0, "arm_b_lo": -16.0},
	"backstep": {"torso": -4.0, "head": -4.0, "hip_y": 0.1, "arm_f_up": -40.0, "arm_f_lo": -18.0, "arm_b_up": 18.0},
	## 발견: 몸을 펴고 무기를 조금 든다 (펄쩍 뛰는 건 몸이 실제로 뛴다)
	"alert": {"torso": -10.0, "head": -8.0, "hip_y": 0.02, "arm_f_up": -62.0, "arm_f_lo": -20.0, "weapon": -8.0, "arm_b_up": -12.0, "arm_b_lo": -30.0},
	## 공중: 팔을 벌려 균형 (다리는 걸음이 공중 모드로 접는다)
	"air": {"torso": 4.0, "head": -4.0, "arm_f_up": -60.0, "arm_f_lo": -18.0, "arm_b_up": -28.0, "arm_b_lo": -20.0},
	## 달려듦: 크게 숙이고 무기를 뒤로 끈다
	"lunge": {"torso": 26.0, "head": 8.0, "lean": 6.0, "hip_y": 0.12, "hip_x": 0.08, "arm_f_up": 28.0, "arm_f_lo": -22.0, "weapon": -10.0, "arm_b_up": -30.0, "arm_b_lo": -40.0},
	## 휘두르기 세 박자: 예비(무게를 뒷발로, 무기를 머리 위 뒤로) → 타격(앞발을 내딛으며 앞 아래로) → 준비(되돌림이 끝나는 자세)
	"windup": {"hip_x": -0.1, "hip_y": 0.1, "lean": -4.0, "torso": -16.0, "head": -8.0, "arm_f_up": -200.0, "arm_f_lo": -28.0, "weapon": -22.0,
		"arm_b_up": -24.0, "arm_b_lo": -40.0, "foot_f": 0.24, "foot_b": -0.28, "step_thr": 0.12, "step_dur": 0.22},
	"strike": {"hip_x": 0.16, "hip_y": 0.17, "lean": 6.0, "torso": 30.0, "head": 12.0, "arm_f_up": -82.0, "arm_f_lo": -6.0, "weapon": 0.0,
		"arm_b_up": 42.0, "arm_b_lo": -8.0, "foot_f": 0.5, "foot_b": -0.3, "step_thr": 0.1, "step_dur": 0.1, "step_lift": 0.06},
	"ready": {"hip_x": 0.06, "hip_y": 0.11, "torso": 16.0, "head": 6.0, "arm_f_up": -58.0, "arm_f_lo": -10.0, "weapon": -4.0, "arm_b_up": 20.0, "arm_b_lo": -14.0,
		"foot_f": 0.4, "foot_b": -0.28, "step_thr": 0.3},
	## 피격: 윗몸이 뒤로 젖혀지고 팔이 흔들린다 (충격 스프링이 더 크게 더한다)
	"hit": {"hip_x": -0.06, "hip_y": 0.1, "torso": -14.0, "head": -16.0, "arm_f_up": -16.0, "arm_f_lo": -4.0, "arm_b_up": 30.0, "arm_b_lo": -6.0},
	## 무너짐(흐트러짐): 무릎이 꺾이고 몸이 앞으로 처진다. 무기 끝은 땅에 닿아 기댄다.
	"broken": {"hip_y": 0.36, "torso": 36.0, "head": 26.0, "arm_f_up": -58.0, "arm_f_lo": -4.0, "weapon": 0.0, "arm_b_up": -4.0, "arm_b_lo": -6.0,
		"foot_f": 0.3, "foot_b": -0.32, "kneel_b": 0.55, "step_thr": 0.4},
	## 구원 가능한 자의 무릎 꿇음 (정화를 기다린다): 뒷무릎을 땅에, 고개를 숙인다
	"kneel": {"hip_y": 0.4, "torso": 22.0, "head": 32.0, "arm_f_up": -36.0, "arm_f_lo": -4.0, "weapon": 0.0, "arm_b_up": -26.0, "arm_b_lo": -30.0,
		"foot_f": 0.32, "foot_b": -0.42, "kneel_b": 1.0, "step_thr": 0.5},
	## 구원 (정화 직후 0.5초): 무릎 꿇은 채 몸을 일으키고 고개를 든다 (빛이 된다)
	"rescued": {"hip_y": 0.34, "torso": 2.0, "head": -12.0, "arm_f_up": -8.0, "arm_f_lo": -6.0, "arm_b_up": 4.0, "arm_b_lo": -10.0,
		"foot_f": 0.32, "foot_b": -0.42, "kneel_b": 1.0, "step_thr": 0.5},
	## 쓰러짐 1단계: 두 무릎이 꺾이며 주저앉는다 (그다음 몸 전체가 넘어간다)
	"dead_knees": {"hip_y": 0.45, "torso": 30.0, "head": 34.0, "arm_f_up": -42.0, "arm_f_lo": -4.0, "arm_b_up": -6.0, "arm_b_lo": -8.0,
		"foot_f": 0.26, "foot_b": -0.3, "kneel_f": 0.7, "kneel_b": 0.9, "step_thr": 0.6},
	## 뒤로 쓰러짐 1단계 (뒤로 밀려 쓰러질 때): 무릎은 조금만 꺾이고 윗몸이 뒤로 젖혀진다
	"dead_back": {"hip_y": 0.22, "hip_x": -0.06, "torso": -22.0, "head": -26.0, "arm_f_up": -70.0, "arm_f_lo": -10.0, "arm_b_up": -40.0, "arm_b_lo": -20.0,
		"foot_f": 0.3, "foot_b": -0.18, "step_thr": 0.6},
	## 뒤로 쓰러짐 2단계: 등으로 눕는다. 무기 팔은 땅을 따라 앞으로 떨어진다 (몸이 −84도 돈 것을 되돌린 각도)
	"dead_back_lie": {"hip_y": 0.2, "torso": -8.0, "head": -16.0, "arm_f_up": 14.0, "arm_f_lo": -10.0, "weapon": -6.0, "arm_b_up": -60.0, "arm_b_lo": -30.0,
		"foot_f": 0.3, "foot_b": -0.2, "step_thr": 0.6},
	## 쓰러짐 2단계 (앞으로 넘어가는 동안): 팔다리가 힘없이 늘어지고, 무기 팔은 앞으로 뻗어 땅에 떨어진다 (몸이 +84도 도는 만큼 팔은 머리 위쪽으로)
	"dead_lie": {"hip_y": 0.4, "torso": 18.0, "head": 20.0, "arm_f_up": -140.0, "arm_f_lo": -10.0, "arm_b_up": -20.0, "arm_b_lo": -16.0,
		"foot_f": 0.2, "foot_b": -0.25, "kneel_f": 0.4, "kneel_b": 0.5, "step_thr": 0.6},
	## 그 밖의 공격 힌트 (종류별 몹이 쓴다 — 자기 설계도 poses 에서 고치면 된다)
	"shoot": {"torso": 6.0, "head": 0.0, "arm_f_up": -88.0, "arm_f_lo": -4.0, "weapon": 0.0, "arm_b_up": -40.0, "arm_b_lo": -50.0, "foot_f": 0.3, "foot_b": -0.26},
	"scatter_a": {"hip_y": 0.18, "torso": 24.0, "head": 10.0, "arm_f_up": 20.0, "arm_f_lo": -40.0, "arm_b_up": 20.0, "arm_b_lo": -40.0},
	"scatter_b": {"hip_y": 0.02, "torso": -12.0, "head": -12.0, "arm_f_up": -130.0, "arm_f_lo": -10.0, "arm_b_up": -120.0, "arm_b_lo": -10.0},
	"charge": {"hip_y": 0.14, "lean": 8.0, "torso": 30.0, "head": 10.0, "arm_f_up": -80.0, "arm_f_lo": -20.0, "arm_b_up": -40.0, "arm_b_lo": -30.0,
		"foot_f": 0.34, "foot_b": -0.4},
	"stuck": {"hip_y": 0.16, "torso": 36.0, "head": 16.0, "arm_f_up": -66.0, "arm_f_lo": -10.0, "arm_b_up": 10.0, "arm_b_lo": -20.0, "foot_f": 0.4, "foot_b": -0.36},
	## 뛰어올라 내려찍기 (거인): 도약 → 낙하(무기를 머리 위로) → 착지(깊게 웅크리며 땅을 친다)
	"leap": {"hip_y": 0.0, "torso": -8.0, "head": -10.0, "arm_f_up": -196.0, "arm_f_lo": -40.0, "weapon": -16.0, "arm_b_up": -150.0, "arm_b_lo": -20.0},
	"slam_fall": {"torso": -4.0, "head": -6.0, "arm_f_up": -186.0, "arm_f_lo": -30.0, "weapon": -10.0, "arm_b_up": -130.0, "arm_b_lo": -20.0},
	"land": {"hip_x": 0.1, "hip_y": 0.32, "lean": 4.0, "torso": 36.0, "head": 14.0, "arm_f_up": -44.0, "arm_f_lo": -4.0, "weapon": 0.0, "arm_b_up": 36.0, "arm_b_lo": -10.0,
		"foot_f": 0.42, "foot_b": -0.4, "step_thr": 0.3},
	## 구원되어 서 있는 사람 (RescuedPerson): 힘을 빼고 선다
	"npc": {"torso": 2.0, "head": 4.0, "arm_f_up": -10.0, "arm_f_lo": -10.0, "weapon": -4.0, "arm_b_up": 4.0, "arm_b_lo": -10.0, "hip_y": 0.03},
}

## 원형 이름 → 자세 모음
const SETS := {"humanoid": HUMANOID}


## 원형의 자세에 뼈대의 덮어쓰기를 합쳐 돌려준다. 결과의 각 자세는 base 까지 합친 완전한 사전이다.
static func build(archetype: String, overrides: Dictionary) -> Dictionary:
	var src: Dictionary = SETS.get(archetype, HUMANOID)
	var base: Dictionary = BASE.duplicate()
	base.merge(src.get("base", {}), true)
	if overrides.has("base"):
		base.merge(overrides["base"], true)
	var out := {"base": base}
	var names: Array = src.keys()
	for k in overrides:
		if not names.has(k) and overrides[k] is Dictionary:
			names.append(k)
	for name in names:
		if name == "base" or str(name).begins_with("_"):
			continue
		var p: Dictionary = base.duplicate()
		p.merge(src.get(name, {}), true)
		var ov = overrides.get(name, {})
		if ov is Dictionary:
			p.merge(ov, true)
		out[name] = p
	return out

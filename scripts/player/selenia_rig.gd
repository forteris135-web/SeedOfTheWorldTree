extends Node2D
## 셀레니아의 뼈대 애니메이션 (8단계, 2026-10-18 모션 개편). 부위 그림(art/characters/selenia/)을 관절로 이어 코드로 움직인다.
## 좌표 단위는 원본 부위 시트의 픽셀(PART_SCALE 로 줄인 그림을 쓰므로 안에서 곱한다). 오른쪽을 보는 기준.
## 동작: 대기·걷기·달리기·점프·낙하·구르기·약공격(3)·씨앗 베기(넓은 호)·낙하 공격·가드(보호막)·피격·회복·정화의 손길·쉬기·사망.
## (강공격은 2026-10-18 기획자 결정으로 없앴다. 그 자리에 영혼 기술이 들어간다.)
##
## 움직임 원칙 (기획자: "휘두르기가 저렴하고 단절돼 보인다"):
## 1) 자세 값은 절대 '툭' 바뀌지 않는다. 매 프레임 '목표 자세'를 만들고, 상태가 바뀌면 이전 목표가 관성을 갖고 흘러가며
##    새 목표로 섞인다(관성 크로스페이드). 그 결과를 관절마다 다른 빠르기의 Motion.damp 로 따라간다. 모두 delta 기반.
## 2) 휘두르기는 세 박자: 예비동작(뒤로 당기며 멈칫) → 타격(속도가 차올라 몸 앞을 지나고 살짝 지나침) → 되돌림(잠깐 여운 뒤 출렁).
##    진행도는 player 의 국면 남은 시간으로 계산하므로 국면 길이가 바뀌어도 모양은 같다. 타격 곡선은 예비동작 끝자락에서
##    출발해 히트박스 구간(active)의 95% 에서 끝나고, 칼이 몸 앞을 지나는 순간은 구간의 40~45% 에 온다. 히트박스 시점은 건드리지 않는다.
##    휘두르는 동안은 관절이 곡선을 거의 그대로 따라간다(ATTACK_FOLLOW_MUL). 안 그러면 0.1초짜리 휘두름이 화면에 반도 안 나온다.
## 3) 몸 전체가 따라간다: 몸통 회전이 머리·팔·망토의 위치로 전달되고(머리·망토는 회전을 한 박자 늦게 따라감), 허리가 앞뒤로 옮겨 간다.
## 4) 2차 움직임(망토·등불·머리·찌그러짐·웅크림·피격 충격)은 전부 스프링. 충격은 '속도'로 주고 스스로 돌아온다.
##
## 빛 효과(_draw)의 세기 조절 상수는 이 파일 위쪽 GUARD_* / SLASH_* / PLUNGE_* 에 모여 있다.

const PART_SCALE := 0.25        # 그림을 1/4로 줄여 두었다
const RIG_SCALE := 0.135        # 원본 px → 게임 px (키 약 132). 바꾸면 발 위치·등장 자리가 틀어진다
const FOOT_Y := 67.0            # Visual 원점(몸 중심)에서 발바닥까지 (게임 px). 찌그러짐의 기준점(발이 땅에 붙어 있게)
const LEG_LEN := 330.0          # 엉덩이에서 발까지 (원본 px). 허리를 앞뒤로 옮길 때 발이 미끄러지지 않게 다리를 기울이는 데 쓴다
const SEED := Color("ffd46a")
const SEED_HDR := Color(2.2, 1.8, 0.9)
const SKIN := Color("efe6d8")
const GUARD_BLUE := Color("8fd3ff")

## 가드 보호막: 소녀 앞에 얇고 키만 한 타원 호. 중심·세로 반지름·가로 납작함·앞쪽 각도 범위·선 두께.
## Visual 원점은 몸 가운데(머리 꼭대기 약 -51, 발바닥 FOOT_Y 67)이므로 중심 y 는 12, 세로 반지름 80 → y -64 ~ +88 (머리 위 13px, 발 아래 21px).
## (처음 값 (24,-62)/92 는 머리 위로 98px 떠 있고 무릎 아래를 안 덮었다 — 2026-10-18 검토)
const GUARD_CENTER := Vector2(24, 12)
const GUARD_RY := 80.0
const GUARD_RX_RATIO := 0.55
const GUARD_SPAN := 1.25
const GUARD_LINE := 2.5
## 씨앗 베기 흔적: 어깨를 중심으로 한 타원 초승달. 판정 상자(slash_box: 앞 340, 위 250, 아래 180) 안에 들어오게
## 앞 반지름·위 반지름·아래 반지름을 따로 둔다 (원 하나로 그리면 아래가 판정보다 50px 더 내려가 보였다 — 2026-10-18 검토).
const SLASH_RX := 300.0
const SLASH_RY_UP := 235.0
const SLASH_RY_DOWN := 172.0
## 초승달 가운데 두께 (px), 시작·끝 각도 (0 = 정면, 음수 = 위), 사라지는 시간
const SLASH_THICK := 60.0
const SLASH_A0 := -2.15
const SLASH_A1 := 1.75
const SLASH_FADE := 0.25
## 낙하 공격 착지 충격 링 (최대 반지름, 시간)
const PLUNGE_RING_R := 170.0
const PLUNGE_RING_TIME := 0.3

## 부위 정의: 이름 -> {file, pivot(그림 안의 관절 px), parent(관절이 붙는 뼈), at(부모 기준 관절 위치 px)}
## 뿌리(hip)는 두 다리 사이 엉덩이. 오른쪽을 본다. 몸통(torso)은 엉덩이(0,0)에 붙으므로 몸통 자식들의 at 은 엉덩이 기준과 같다.
const PARTS := {
	"cloak_far":  {"file": "cloak_far.png",  "pivot": Vector2(120, 40),  "parent": "torso", "at": Vector2(-40, -195)},
	"cloak_near": {"file": "cloak_near.png", "pivot": Vector2(560, 40),  "parent": "torso", "at": Vector2(-20, -185)},
	"arm_back":   {"file": "arm_back.png",   "pivot": Vector2(120, 40),  "parent": "torso", "at": Vector2(-15, -170)},
	"leg_back":   {"file": "leg_back.png",   "pivot": Vector2(95, 25),   "parent": "hip",   "at": Vector2(-22, -5)},
	"torso":      {"file": "torso.png",      "pivot": Vector2(190, 265), "parent": "hip",   "at": Vector2(0, 0)},
	"leg_front":  {"file": "leg_front.png",  "pivot": Vector2(84, 25),   "parent": "hip",   "at": Vector2(28, -5)},
	"cape":       {"file": "cape.png",       "pivot": Vector2(40, 20),   "parent": "torso", "at": Vector2(-40, -200)},
	"head":       {"file": "head.png",       "pivot": Vector2(380, 330), "parent": "torso", "at": Vector2(12, -218)},
	"arm_sword":  {"file": "arm_sword.png",  "pivot": Vector2(62, 62),   "parent": "torso", "at": Vector2(8, -165)},
}
## 그리기 순서 (뒤 → 앞). 모든 관절은 엉덩이 바로 아래 한 층에 두고(그리기 순서를 지키려고), 몸통 회전은 코드로 전달한다.
const ORDER := ["cloak_far", "cloak_near", "arm_back", "leg_back", "torso", "leg_front", "cape", "head", "arm_sword"]
## 몸통 회전을 얼마나 '회전'으로 따라갈지 (위치는 항상 100% 따라간다). 머리·망토는 여기 대신 지연 스프링을 쓴다.
const FOLLOW_ROT := {"arm_sword": 1.0, "arm_back": 1.0}

## 자세 값 이름. 각도는 라디안(몸통·머리: 양수 = 앞으로 숙임, 팔·다리: 양수 = 뒤로), hip_x/hip_y 는 원본 px(양수 = 앞 / 아래).
const KEYS := ["torso", "head", "arm_back", "arm_sword", "leg_back", "leg_front", "hip_x", "hip_y"]
const BASE := {"torso": 0.0, "head": 0.0, "arm_back": 0.1, "arm_sword": 0.3, "leg_back": 0.0, "leg_front": 0.0, "hip_x": 0.0, "hip_y": 0.0}
## 관절마다 목표를 따라가는 빠르기 (Motion.damp). 머리가 가장 느리고 다리가 가장 빠르다.
const FOLLOW_SPEED := {"torso": 40.0, "head": 30.0, "arm_back": 45.0, "arm_sword": 45.0, "leg_back": 50.0, "leg_front": 50.0, "hip_x": 45.0, "hip_y": 45.0}
## 휘두르는 동안(약공격·씨앗 베기·낙하 공격)은 머리를 뺀 관절이 이 배수만큼 빨리 따라간다. 타격 구간이 0.06초쯤이라 평소 빠르기(45)로는
## 화면의 팔이 '휘두른 자세'와 지나침에 닿기 전에 되돌림이 시작돼 버린다. 곡선 자체가 이미 부드러우니 거의 그대로 보여 준다.
const ATTACK_FOLLOW_MUL := 3.0
## 타격 곡선이 도는 시간 창: 예비동작(startup) 진행도 x 부터 히트박스 구간(active) 진행도 y 까지 한 번에 이어진다.
## 히트박스가 켜지는 순간엔 칼이 아직 거의 당긴 자리(swing 의 6%)에 있고, 몸 앞을 지나는 순간이 active 의 35~55% 에 온다.
## active 만으로는 0.06초(60fps 세 프레임 반)라 '휘두른 자세'에 닿기도 전에 끝나 버려서 조금 앞당겨 시작한다.
const STRIKE_WINDOW_LIGHT := Vector2(0.85, 0.95)
## 씨앗 베기는 예비동작이 길어(0.28초) 그 끝 8% 만 당겨 쓰고, 긴 히트박스 구간(0.18초)의 95% 에서 끝난다.
const STRIKE_WINDOW_SLASH := Vector2(0.92, 0.95)

## ---- 공격 키 자세 ----
## 되돌림이 끝나는 '준비' 자세 (다음 타로 이어지기 좋게 조금 앞으로 기운 자세)
const READY := {"torso": 0.1, "head": -0.04, "arm_back": 0.05, "arm_sword": 0.15, "leg_back": 0.25, "leg_front": -0.3, "hip_x": 0.0, "hip_y": 4.0}
## 1타 가로 베기: 뒤 위로 당겼다가 앞 아래로. 몸은 뒤로 비틀렸다가 앞으로 쏟아진다.
const WINDUP_1 := {"torso": -0.28, "head": -0.1, "arm_back": 0.35, "arm_sword": 2.0, "leg_back": 0.45, "leg_front": -0.2, "hip_x": -18.0, "hip_y": 6.0}
const STRIKE_1 := {"torso": 0.38, "head": 0.05, "arm_back": -0.4, "arm_sword": -1.15, "leg_back": 0.3, "leg_front": -0.5, "hip_x": 22.0, "hip_y": 8.0}
## 2타 올려 베기: 1타가 끝난 앞 아래 자리에서 살짝 더 가라앉았다가 앞 위로 쳐올린다. 몸이 일어선다.
const WINDUP_2 := {"torso": 0.3, "head": 0.1, "arm_back": -0.2, "arm_sword": -0.55, "leg_back": 0.35, "leg_front": -0.45, "hip_x": 6.0, "hip_y": 14.0}
const STRIKE_2 := {"torso": -0.22, "head": -0.16, "arm_back": 0.6, "arm_sword": -2.35, "leg_back": 0.2, "leg_front": -0.35, "hip_x": 14.0, "hip_y": -6.0}
## 3타 내려 찍기: 2타의 기세로 칼을 머리 뒤까지 넘겼다가(-3.3 = 뒤 어깨 위) 크게 내려찍는다. 가장 크고 무겁다.
## (-3.75 까지 넘기면 칼팔이 얼굴을 가린다. 맥에서 눈으로 본 뒤 더 넘길지 정한다.)
const WINDUP_3 := {"torso": -0.4, "head": -0.22, "arm_back": 0.9, "arm_sword": -3.3, "leg_back": 0.5, "leg_front": -0.15, "hip_x": -22.0, "hip_y": 2.0}
const STRIKE_3 := {"torso": 0.5, "head": 0.15, "arm_back": -0.6, "arm_sword": -0.85, "leg_back": 0.25, "leg_front": -0.65, "hip_x": 30.0, "hip_y": 18.0}
## 씨앗 베기: 칼을 머리 위 뒤로 크게 들어 올리며 몸을 젖혔다가(0.28초 예비) → 앞 위에서 앞 아래까지 큰 호를 그리며 내려 벤다.
## 칼팔 -3.5(뒤 어깨 위) → -0.35(앞 아래, 거의 수직) 로 3rad 넘게 돈다. 몸은 뒤로 젖혔다가 앞으로 깊게 쏟아지고 허리가 크게 앞으로.
const WINDUP_S := {"torso": -0.5, "head": -0.2, "arm_back": 0.8, "arm_sword": -3.5, "leg_back": 0.55, "leg_front": -0.1, "hip_x": -30.0, "hip_y": 10.0}
const STRIKE_S := {"torso": 0.6, "head": 0.2, "arm_back": -0.75, "arm_sword": -0.35, "leg_back": 0.3, "leg_front": -0.75, "hip_x": 38.0, "hip_y": 24.0}
## 낙하 공격: 멈칫(칼을 높이 들어 올림) → 급강하(몸을 세우고 칼끝을 아래로, 다리를 모아 올림) → 착지(깊게 웅크리고 칼을 앞 땅에 꽂음)
const PLUNGE_PAUSE := {"torso": -0.15, "head": 0.05, "arm_back": 0.6, "arm_sword": -2.4, "leg_back": 0.2, "leg_front": -0.2, "hip_x": -8.0, "hip_y": -6.0}
## 멈칫 자세에서 급강하 자세로 칼을 내리꽂는 데 걸리는 시간 (초). 더 짧으면 1/120초 프레임에서 '툭' 한다
const PLUNGE_FLIP_TIME := 0.14
const PLUNGE_DIVE := {"torso": 0.18, "head": 0.3, "arm_back": 1.4, "arm_sword": 0.5, "leg_back": 0.7, "leg_front": -0.9, "hip_x": 4.0, "hip_y": -10.0}
const PLUNGE_LAND := {"torso": 0.55, "head": 0.25, "arm_back": 0.9, "arm_sword": -0.2, "leg_back": 0.9, "leg_front": -1.2, "hip_x": 10.0, "hip_y": 110.0}

var _player: Player
var _bones := {}          # 이름 -> Node2D (관절)
var _sprites := {}        # 이름 -> Sprite2D
var _hip: Node2D
var _time := 0.0
var _flash := 0.0
var _hurt := 0.0
var _purify_ring := -1.0
var _air_ring := -1.0
var _gust_t := -1.0
var _slash_t := -1.0      # 씨앗 베기 흔적 (0→1, SLASH_FADE 초)
var _guard_ring := -1.0   # 일반 가드로 막은 순간의 충격 고리 (0→1, 0.2초)
var _plunge_ring := -1.0  # 낙하 공격 착지 충격 링 (0→1, PLUNGE_RING_TIME 초)
## 시간이 흐르는 빛 효과들: 이름 -> 1초에 얼마나 진행하는지 (1/시간)
const EFFECT_RATES := {"_purify_ring": 1.6, "_air_ring": 3.0, "_gust_t": 3.0, "_slash_t": 1.0 / SLASH_FADE, "_guard_ring": 5.0, "_plunge_ring": 1.0 / PLUNGE_RING_TIME}
var _death_t := 0.0
var _seed_glow: Sprite2D
var _lantern: Sprite2D
var _lantern_glow: Sprite2D

# 자세 파이프라인: 상태별 목표 → 관성 크로스페이드 → 관절별 damp → 2차 스프링 더하기
var _tgt := {}            # 이번 프레임의 목표 자세 (크로스페이드가 끝난 값)
var _tgt_vel := {}        # 목표 자세의 속도 (상태 전환 때 관성을 넘겨 주려고)
var _fade_from := {}      # 전환 직전의 목표 자세 (관성을 갖고 흘러가며 사라진다)
var _fade_vel := {}
var _fade_t := 1.0        # 0 → 1 (1 이면 전환 끝)
var _fade_len := 0.1
var _out := {}            # 관절의 현재 값 (화면에 보이는 자세의 바탕)
var _prev_state := -1
var _state_t := 0.0       # 지금 상태에 들어온 뒤 지난 시간
var _prev_phase := ""
var _atk_key := ""        # "상태:타" — 바뀌면 새 휘두르기가 시작된 것
var _atk_from := {}       # 휘두르기를 시작할 때의 자세 (여기서부터 당긴다)
var _gait := 0.0          # 걸은 거리 (기준 보폭 150px 로 환산). 다리 위상은 시간이 아니라 이 값으로
var _vx_smooth := 0.0     # 조금 늦게 따라오는 속도 (가속·감속 기울기용)
var _face := 1.0          # 보이는 방향 (-1..1). facing 을 부드럽게 따라가 0 을 지날 때 몸을 튼다
var _roll_rot := 0.0
var _fall_rot := 0.0
var _lower := 0.0         # 몸을 낮추는 양 (구르기 공, 쓰러짐)
var _guard_a := 0.0
var _trail_on := false
var _trail_a0 := 0.0
var _trail_a1 := 0.0
var _trail_alpha := 0.0
var _trail_r := 100.0     # 칼끝 잔상의 반지름 (씨앗 베기는 더 크다)
var _impact_pending := false
var _sp := {}             # 2차 스프링들: 이름 -> [값, 속도]
const SPRINGS := {
	# 이름: [강성, 감쇠]. 감쇠가 작을수록 출렁인다.
	"head_follow": [140.0, 16.0],   # 머리가 몸통 회전을 늦게 따라감
	"cloth_follow": [110.0, 13.0],  # 망토·겉옷이 몸통 회전을 늦게 따라감
	"cloak_near": [70.0, 8.0],
	"cloak_far": [52.0, 6.5],
	"cape": [95.0, 11.0],
	"lantern": [60.0, 6.0],
	"impact": [200.0, 18.0],        # 피격 충격 (양수 = 뒤로 젖혀짐)
	"parry": [260.0, 20.0],         # 저스트 가드 튕김
	"recoil": [300.0, 22.0],        # 칼이 닿았을 때 팔의 반동
	"squash": [260.0, 18.0],        # 찌그러짐 (양수 = 납작, 음수 = 길쭉)
	"crouch": [220.0, 22.0],        # 착지 웅크림
	"spin": [120.0, 14.0],          # 이단 점프 몸 말기
}


func _ready() -> void:
	_player = get_parent() as Player
	_hip = Node2D.new()
	_hip.name = "Hip"
	_hip.position = Vector2(0, 22)
	_hip.scale = Vector2(RIG_SCALE, RIG_SCALE)
	add_child(_hip)
	for name in ORDER:
		var p: Dictionary = PARTS[name]
		var bone := Node2D.new()
		bone.name = name
		bone.position = p["at"]
		_hip.add_child(bone)
		var spr := Sprite2D.new()
		spr.texture = load("res://art/characters/selenia/" + p["file"])
		spr.centered = false
		spr.scale = Vector2(1.0 / PART_SCALE, 1.0 / PART_SCALE)
		spr.position = -p["pivot"]
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		bone.add_child(spr)
		_bones[name] = bone
		_sprites[name] = spr
	for k in KEYS:
		_tgt[k] = BASE[k]
		_tgt_vel[k] = 0.0
		_fade_from[k] = BASE[k]
		_fade_vel[k] = 0.0
		_out[k] = BASE[k]
		_atk_from[k] = BASE[k]
	for s in SPRINGS:
		_sp[s] = [0.0, 0.0]
	# 가슴의 씨앗 빛 (발광)
	_seed_glow = Sprite2D.new()
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	grad.colors = PackedColorArray([Color(SEED, 0.9), Color(SEED, 0.25), Color(SEED, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 64
	gt.height = 64
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	_seed_glow.texture = gt
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_seed_glow.material = add
	_bones["torso"].add_child(_seed_glow)
	_seed_glow.position = Vector2(85, -120)   # 몸통 그림 속 씨앗 자리 (원본 px, 관절 기준)
	_seed_glow.scale = Vector2(2.6, 2.6)

	# 티아의 작은 등불 (받으면 허리에 매달린다)
	_lantern = Sprite2D.new()
	_lantern.texture = preload("res://art/objects/tia_lantern.png")
	_lantern.scale = Vector2(0.9, 0.9)   # 원본 px 기준(뼈대 배율로 줄어든다): 약 70px 높이
	_lantern.position = Vector2(-70, 20)
	_lantern.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_lantern.visible = Progress.has("has_tia_lantern")
	_hip.add_child(_lantern)
	_hip.move_child(_lantern, _bones["torso"].get_index() + 1)
	_lantern_glow = Sprite2D.new()
	_lantern_glow.texture = _seed_glow.texture
	_lantern_glow.material = _seed_glow.material
	_lantern_glow.modulate = Color(2.0, 1.3, 0.6, 0.8)
	_lantern_glow.scale = Vector2(3.0, 3.0)
	_lantern_glow.position = Vector2(0, 40)
	_lantern.add_child(_lantern_glow)
	Progress.flag_changed.connect(func(f, v): if f == "has_tia_lantern": _lantern.visible = v)
	_face = float(_player.facing)
	_prev_state = _player.state
	# 신호 → 충격(스프링 속도). 상태·국면 변화는 신호 대신 매 프레임 비교로 잡는다 (시험 코드가 state 를 직접 꽂아도 되게).
	_player.jumped.connect(_on_jumped)
	_player.landed.connect(_on_landed)
	_player.roll_started.connect(func(): _kick("squash", 2.0))
	_player.just_guarded.connect(func(_s): _flash = 1.0; _kick("parry", 28.0))
	_player.guard_hit.connect(func(_d): _guard_ring = 0.0; _kick("impact", 3.0); _kick("parry", 6.0))
	_player.guard_broken.connect(func(): _kick("impact", 10.0); _kick("squash", 2.0))
	_player.hit_taken.connect(func(_d): _hurt = 1.0; _impact_pending = true; _kick("squash", 2.4))
	_player.purified.connect(func(_t): _purify_ring = 0.0; _flash = 1.0)
	_player.healed.connect(func(): _flash = 0.5)
	_player.gust_cast.connect(func(): _gust_t = 0.0; _kick("recoil", 9.0))   # 커진 투사체(2026-10-19)에 맞춰 반동도 더 크게
	_player.blocked.connect(func(): _kick("recoil", 21.0); _kick("impact", 6.0))
	_player.plunge_started.connect(func(): _kick("squash", -2.5))
	_player.plunge_landed.connect(_on_plunge_landed)
	# 히트박스(@onready)는 부모가 준비된 뒤에야 있다 (자식의 _ready 가 먼저 불린다)
	if _player.is_node_ready():
		_player.hitbox.landed.connect(_on_hit_landed)
	else:
		_player.ready.connect(func(): _player.hitbox.landed.connect(_on_hit_landed))


## 스프링에 '충격'을 준다 (속도를 더한다). 자세는 스스로 출렁이며 돌아온다.
func _kick(name: String, velocity: float) -> void:
	_sp[name][1] += velocity


## 스프링 한 틱. 큰 delta(멈춤 뒤 복귀)에서도 터지지 않게 잘게 나눠 돈다.
func _spring(name: String, target: float, delta: float) -> float:
	var s: Array = _sp[name]
	var kc: Array = SPRINGS[name]
	var n := mini(1 + int(delta * 90.0), 8)
	var h := delta / n
	for i in n:
		var r := Motion.spring(s[0], target, s[1], kc[0], kc[1], h)
		s[0] = r[0]
		s[1] = r[1]
	return s[0]


func _sv(name: String) -> float:
	return _sp[name][0]


func _process(delta: float) -> void:
	delta = minf(delta, 1.0 / 20.0)
	_time += delta
	_state_t += delta
	_flash = maxf(_flash - delta * 6.0, 0.0)
	_hurt = maxf(_hurt - delta * 3.0, 0.0)
	for k in EFFECT_RATES:
		var v: float = get(k)
		if v >= 0.0:
			v += delta * EFFECT_RATES[k]
			set(k, v if v <= 1.0 else -1.0)
	var st := _player.state
	if st != _prev_state:
		_on_state_enter(st, _prev_state)
		_prev_state = st
	_death_t = minf(_death_t + delta, 1.0) if st == Player.State.DEAD else 0.0

	# 피격 충격 방향: 밀려나는 쪽(속도)은 신호 다음 프레임에야 정해진다
	if _impact_pending:
		_impact_pending = false
		var pushed_back := _player.velocity.x * _player.facing <= 0.0
		_kick("impact", 15.0 if pushed_back else -11.0)

	_apply_pose(delta, st)
	_apply_transform(delta, st)

	# 무적 깜빡임 (부드러운 맥동)
	if _player.is_invulnerable() and st != Player.State.DEAD:
		modulate.a = 0.45 + 0.55 * (0.5 + 0.5 * sin(_time * TAU / 0.14))
	else:
		modulate.a = 1.0 - 0.6 * smoothstep(0.55, 1.0, _death_t)
	# 피격 붉은 기운 / 저스트 가드 번쩍임
	var tint := Color.WHITE.lerp(Color(1.6, 0.6, 0.5), _hurt * 0.7).lerp(Color(2.5, 2.5, 2.5), _flash * 0.8)
	for name in ORDER:
		_sprites[name].modulate = tint
	queue_redraw()


## 상태가 바뀌는 순간: 이전 목표 자세가 관성을 갖고 흘러가며 새 자세로 섞이기 시작한다.
func _on_state_enter(st: Player.State, prev: int) -> void:
	_state_t = 0.0
	var fade := 0.1
	match st:
		Player.State.ATTACK, Player.State.SOUL_SLASH:
			fade = 0.0     # 휘두르기 곡선이 지금 자세에서 출발하므로 섞을 필요가 없다
		Player.State.ROLL, Player.State.HIT, Player.State.GUARD:
			fade = 0.06
		Player.State.PLUNGE:
			fade = 0.06
			_atk_from = _out.duplicate()   # 멈칫 자세는 지금 보이는 자세에서 당긴다
		Player.State.REST:
			fade = 0.35
		Player.State.DEAD:
			fade = 0.2
	# 쉬다가 일어날 때는 앉을 때(0.35초)만큼은 아니어도 천천히 (안 그러면 벌떡 일어선다)
	if prev == Player.State.REST:
		fade = maxf(fade, 0.3)
	# 부활: 쓰러진 자리와 다른 곳(달빛풀)에 다시 서므로 이어 붙일 게 없다. 쓰러진 자세·기울기를 바로 지우고
	# 웅크렸다 펴는 것으로 일어나는 느낌만 준다 (옆으로 누운 채 널빤지처럼 벌떡 서지 않게).
	if prev == Player.State.DEAD:
		fade = 0.0
		_fall_rot = 0.0
		_lower = 0.0
		_death_t = 0.0
		_fade_t = 1.0
		for k in KEYS:
			_out[k] = BASE[k]
			_tgt[k] = BASE[k]
			_tgt_vel[k] = 0.0
		for s in SPRINGS:
			_sp[s] = [0.0, 0.0]
		_kick("crouch", 6.0)
	if fade > 0.0:
		_fade_from = _tgt.duplicate()
		_fade_vel = _tgt_vel.duplicate()
		_fade_t = 0.0
		_fade_len = fade
	# 휘두르기에서 나올 때: 칼팔 각도는 한 바퀴 넘게 돌아갔을 수 있다. 같은 모양이 되는 가장 가까운 각도로 바꿔 둔다
	# (2π 차이는 그림이 똑같으므로 '툭' 하지 않는다). 세 값에 같은 양을 빼서 서로의 관계는 그대로.
	if prev == Player.State.ATTACK or prev == Player.State.SOUL_SLASH:
		var n := roundf((_out["arm_sword"] - BASE["arm_sword"]) / TAU)
		if n != 0.0:
			_out["arm_sword"] -= n * TAU
			_tgt["arm_sword"] -= n * TAU
			_fade_from["arm_sword"] -= n * TAU


# ---------- 자세 ----------

func _apply_pose(delta: float, st: Player.State) -> void:
	var t := _time
	var grounded := _player.is_on_floor()
	var raw := BASE.duplicate()
	var ph := _player.attack_phase
	var in_attack := st == Player.State.ATTACK or st == Player.State.SOUL_SLASH
	var fast := in_attack or st == Player.State.PLUNGE

	# 새 휘두르기(상태·타가 바뀌거나 다시 startup 으로)가 시작되면 지금 목표 자세에서 당기기 시작한다
	if in_attack:
		var key := "%d:%d" % [st, _player.attack_step]
		if key != _atk_key or (ph == "startup" and _prev_phase != "startup"):
			_atk_key = key
			_atk_from = _out.duplicate()   # 화면에 보이는 자세에서 당기기 시작한다 (목표가 아니라) → 첫 프레임이 튀지 않는다
		# 실제로 휘두르는 순간(국면 active 진입) 몸이 쿵 하고 눌린다. 씨앗 베기는 크게, 그리고 베기 흔적이 시작된다
		if st == Player.State.SOUL_SLASH and ph == "active" and _prev_phase != "active":
			_kick("squash", 1.7)
			_slash_t = 0.0
		elif st == Player.State.ATTACK and ph == "active" and _prev_phase != "active":
			_kick("squash", 0.6)
	else:
		_atk_key = ""
	_prev_phase = ph

	# 걸음: 시간이 아니라 걸은 거리로 (속도 0 이면 멈춘다)
	var vx := _player.velocity.x
	var sp := absf(vx)
	var ratio := clampf(sp / _player.run_speed, 0.0, 1.0)
	var dir := 1.0
	if sp > 5.0:
		dir = 1.0 if vx * _player.facing > 0.0 else -1.0
	if grounded:
		var stride := lerpf(110.0, 190.0, ratio)   # 한 걸음 주기(두 발)의 거리: 빨리 달릴수록 성큼
		_gait += sp * delta * (150.0 / stride)
	_vx_smooth = Motion.damp(_vx_smooth, vx, 9.0, delta)
	var accel_lean := clampf((vx - _vx_smooth) / 1400.0, -0.22, 0.22) * _player.facing
	var gait_ph := _gait / 150.0 * TAU
	var gs := sin(gait_ph)
	var gait_amp := 0.8 * pow(ratio, 0.7)
	var bob := Motion.step_bob(_gait, 75.0)
	var breath := sin(t * 1.6)
	var vy := _player.velocity.y
	var air := clampf(vy / maxf(_player.jump_velocity(), 1.0), -1.0, 1.0)   # -1 솟는 중 … +1 떨어지는 중
	var rise := clampf(-air, 0.0, 1.0)
	var fall := clampf(air, 0.0, 1.0)

	match st:
		Player.State.IDLE, Player.State.WALK, Player.State.RUN:
			# 걷기·달리기·멈춰 섬은 하나의 연속: 진폭·기울기·들썩임이 모두 속도 비율을 따른다
			raw["leg_front"] = -gs * gait_amp
			raw["leg_back"] = gs * gait_amp * 0.9
			raw["arm_sword"] = 0.3 + gs * gait_amp * 0.45 + breath * 0.03
			raw["arm_back"] = 0.1 - gs * gait_amp * 0.55 + breath * 0.04
			raw["hip_y"] = -(1.0 - bob) * ratio * 11.0 + breath * 2.0 * (1.0 - ratio)
			raw["torso"] = (0.05 + 0.17 * ratio) * dir + accel_lean + breath * 0.012
			raw["head"] = -0.03 * ratio * dir + sin(t * 1.6 + 0.5) * 0.02 - accel_lean * 0.3
		Player.State.JUMP, Player.State.FALL:
			# 솟을 때 몸을 늘리고 팔을 올리며, 떨어질 때 팔을 벌리고 아래를 본다. 세로 속도로 이어진다
			raw["leg_front"] = -0.35 - 0.45 * rise + 0.15 * fall
			raw["leg_back"] = 0.3 + 0.25 * rise - 0.1 * fall
			raw["arm_back"] = 0.5 + 0.3 * rise + 0.45 * fall + sin(t * 8.0) * 0.08 * fall
			raw["arm_sword"] = 0.1 - 0.35 * rise - 0.6 * fall
			raw["torso"] = 0.1 * rise - 0.08 * fall + accel_lean * 0.5
			raw["head"] = -0.06 * rise + 0.1 * fall
			raw["hip_y"] = -6.0 * rise
		Player.State.ROLL:
			# 처음 18% 동안 몸을 말고 마지막 20% 동안 편다. 회전은 _apply_transform 에서 진행도로 정확히 한 바퀴
			var p := 1.0 - clampf(_player._roll_timer / maxf(_player.roll_duration, 0.001), 0.0, 1.0)
			var curl := smoothstep(0.0, 0.18, p) * (1.0 - smoothstep(0.8, 1.0, p))
			raw["leg_front"] = -1.5 * curl - 0.3 * (1.0 - curl)
			raw["leg_back"] = 1.3 * curl + 0.25 * (1.0 - curl)
			raw["arm_back"] = 1.2 * curl
			raw["arm_sword"] = -1.0 * curl + 0.3 * (1.0 - curl)
			raw["torso"] = 0.55 * curl + 0.1
			raw["head"] = 0.5 * curl
			raw["hip_y"] = 20.0 * curl
		Player.State.ATTACK, Player.State.SOUL_SLASH:
			raw = _attack_pose()
		Player.State.PLUNGE:
			raw = _plunge_pose()
		Player.State.GUARD:
			# 방패 없이 검을 세워 막는다: 칼팔을 앞 위로 올려 칼날이 서고, 뒷손이 받친다. 가드 걷기는 발을 조금만 끈다
			raw["arm_sword"] = -1.9
			raw["arm_back"] = -0.7
			raw["torso"] = 0.06 + accel_lean * 0.4
			raw["head"] = -0.02
			raw["leg_front"] = -0.35 - gs * gait_amp * 0.3
			raw["leg_back"] = 0.3 + gs * gait_amp * 0.3
			raw["hip_y"] = 8.0 + breath * 1.0
			raw["hip_x"] = -4.0
		Player.State.HIT:
			raw["torso"] = -0.25
			raw["head"] = -0.2
			raw["arm_back"] = 0.6
			raw["arm_sword"] = 0.9
			raw["leg_front"] = -0.25
			raw["leg_back"] = 0.4
			raw["hip_y"] = 6.0
		Player.State.HEAL:
			# 이슬을 마시듯: 뒷손을 입으로 올리고 → 고개를 젖혀 마시고 → 손을 내린다 (회복 시간 진행도)
			var p := 1.0 - clampf(_player._heal_timer / maxf(_player.heal_time, 0.001), 0.0, 1.0)
			var w1 := smoothstep(0.0, 0.4, p)
			var w2 := smoothstep(0.45, 0.7, p)
			var w3 := smoothstep(0.78, 1.0, p)
			raw["arm_back"] = -2.4 * w1 - 0.2 * w2 + 1.8 * w3
			raw["head"] = 0.1 * w1 - 0.4 * w2 + 0.3 * w3
			raw["torso"] = 0.05 * w1 - 0.1 * w2 + 0.05 * w3
			raw["arm_sword"] = 0.3 + 0.2 * w1
			raw["leg_front"] = -0.2
			raw["leg_back"] = 0.15
			raw["hip_y"] = 4.0 * w1 + breath * 1.5
		Player.State.PURIFY:
			# 손을 뻗어 빛을 얹는다: 뻗는 동안 살짝 지나쳤다 멈춘다
			var w := Motion.ease_out_back(minf(_state_t / 0.35, 1.0), 1.4)
			raw["arm_back"] = -1.65 * w
			raw["arm_sword"] = 0.3 + 0.25 * w
			raw["torso"] = 0.14 * w + breath * 0.01
			raw["head"] = 0.12 * w
			raw["leg_front"] = -0.4 * w
			raw["leg_back"] = 0.3 * w
			raw["hip_x"] = 10.0 * w
			raw["hip_y"] = 6.0 * w + sin(t * 9.0) * 0.6
		Player.State.REST:
			# 웅크려 앉아 천천히 숨 쉰다
			var b := sin(t * 1.1)
			raw["leg_front"] = -1.7
			raw["leg_back"] = 1.4
			raw["torso"] = 0.3 + b * 0.03
			raw["head"] = 0.3 + b * 0.03
			raw["arm_back"] = -1.1 + b * 0.04
			raw["arm_sword"] = -0.9 + b * 0.03
			raw["hip_y"] = 154.0 + b * 3.0
		Player.State.DEAD:
			# 무너짐: 무릎이 꺾이고(0~0.4초) 고개가 떨어지며, 그다음 옆으로 쓰러진다(_apply_transform). 바로 사라지지 않는다
			var d := _death_t
			var knee := Motion.ease_in(minf(d / 0.4, 1.0), 1.6)
			raw["leg_front"] = -0.3 - 0.9 * knee
			raw["leg_back"] = 0.2 + 0.6 * knee
			raw["hip_y"] = 120.0 * knee
			raw["torso"] = 0.4 * smoothstep(0.0, 0.3, d)
			raw["head"] = 0.45 * smoothstep(0.05, 0.4, d)
			raw["arm_back"] = 1.2 * smoothstep(0.0, 0.5, d)
			raw["arm_sword"] = 0.3 + 0.7 * smoothstep(0.0, 0.5, d)
	# 공중에서 공격하면 다리는 공중 자세
	if in_attack and not grounded:
		raw["leg_front"] = -0.35 - 0.3 * rise
		raw["leg_back"] = 0.3 + 0.15 * rise
		raw["hip_y"] = 0.0

	# 방향 전환 중(보이는 방향이 0 근처): 살짝 몸을 틀고 가라앉는다
	var turn := 1.0 - absf(_face)
	raw["torso"] -= 0.12 * turn
	raw["head"] += 0.1 * turn
	raw["hip_y"] += 10.0 * turn

	# 관성 크로스페이드: 이전 목표가 제 속도로 흘러가며 새 목표에 섞인다
	if _fade_t < 1.0:
		_fade_t = minf(_fade_t + delta / maxf(_fade_len, 0.001), 1.0)
		var w := smoothstep(0.0, 1.0, _fade_t)
		var decay := exp(-delta * 18.0)
		for k in KEYS:
			_fade_from[k] += _fade_vel[k] * delta
			_fade_vel[k] *= decay
			raw[k] = lerpf(_fade_from[k], raw[k], w)
	for k in KEYS:
		_tgt_vel[k] = (raw[k] - _tgt[k]) / maxf(delta, 0.0001)
		_tgt[k] = raw[k]
		# 휘두르는 동안은 머리만 느리게, 나머지는 곡선을 거의 그대로 따라간다 (타격 구간이 짧아서)
		var spd: float = FOLLOW_SPEED[k] * (ATTACK_FOLLOW_MUL if fast and k != "head" else 1.0)
		_out[k] = Motion.damp(_out[k], raw[k], spd, delta)

	# ---- 2차 움직임 (스프링) ----
	var impact := _spring("impact", 0.0, delta)
	var parry := _spring("parry", 0.0, delta)
	var recoil := _spring("recoil", 0.0, delta)
	var crouch := _spring("crouch", 0.0, delta)
	var fin := {}
	for k in KEYS:
		fin[k] = _out[k]
	# 저스트 가드: 칼이 0.4rad 쯤 튕겨 올라갔다 돌아오고 몸이 뒤로 살짝 밀린다. 착지 웅크림: 무릎이 실제로 굽어 보이게(엉덩이 약 5px).
	fin["torso"] += -0.3 * impact - 0.12 * parry + 0.45 * crouch
	fin["head"] += -0.45 * impact + 0.04 * parry - 0.15 * crouch
	fin["arm_back"] += -0.6 * impact + 0.25 * parry + 0.15 * crouch
	fin["arm_sword"] += -0.4 * impact + 0.5 * parry + 0.5 * recoil - 0.1 * crouch
	fin["leg_front"] += -0.6 * crouch
	fin["leg_back"] += 0.5 * crouch
	fin["hip_x"] += -14.0 * impact - 20.0 * parry
	fin["hip_y"] += 180.0 * crouch
	# 허리를 앞뒤로 옮기면 발이 미끄러지지 않게 다리를 그만큼 기울인다
	var leg_fix: float = fin["hip_x"] / LEG_LEN
	fin["leg_front"] += leg_fix
	fin["leg_back"] += leg_fix

	# 몸통이 돈 만큼 머리·팔·망토의 '자리'가 따라 돈다. 팔은 회전도 그대로, 머리·망토는 늦게(스프링) 따라온다
	var torso_rot: float = fin["torso"]
	var head_follow := _spring("head_follow", torso_rot * 0.55, delta)
	var cloth_follow := _spring("cloth_follow", torso_rot, delta)
	_bones["torso"].rotation = torso_rot
	_bones["leg_front"].rotation = fin["leg_front"]
	_bones["leg_back"].rotation = fin["leg_back"]
	for name in PARTS:
		if PARTS[name]["parent"] == "torso":
			_bones[name].position = (PARTS[name]["at"] as Vector2).rotated(torso_rot)
	_bones["head"].rotation = fin["head"] + head_follow
	_bones["arm_sword"].rotation = fin["arm_sword"] + torso_rot * FOLLOW_ROT["arm_sword"]
	_bones["arm_back"].rotation = fin["arm_back"] + torso_rot * FOLLOW_ROT["arm_back"]
	_hip.position = Vector2(fin["hip_x"] * RIG_SCALE, 22.0 + fin["hip_y"] * RIG_SCALE)

	# 망토 두 자락과 겉옷: 움직임에 뒤처져 날리고(앞으로 달리면 뒤로), 떨어질 때 떠오른다. 자락마다 강성이 달라 따로 논다
	var vrel := vx * _player.facing
	var cloth_target := clampf(-vrel / 900.0, -0.5, 0.35) + clampf(vy / 1500.0, -1.0, 1.0) * 0.3
	var sway := sin(t * 2.3) * 0.02
	var near := _spring("cloak_near", cloth_target, delta)
	var far := _spring("cloak_far", cloth_target * 0.9 + 0.05, delta)
	var cape := _spring("cape", cloth_target * 0.6, delta)
	_bones["cloak_near"].rotation = near * 0.9 + sway + cloth_follow * 0.5
	_bones["cloak_far"].rotation = far * 0.7 + sway * 0.8 + 0.12 + cloth_follow * 0.5
	_bones["cape"].rotation = cape * 0.5 + cloth_follow * 0.8
	# 씨앗 빛 맥동 (씨앗 베기 예비동작 중에는 빛이 모인다)
	var pulse := 0.8 + 0.2 * sin(t * 3.0)
	if st in [Player.State.HEAL, Player.State.PURIFY, Player.State.REST]:
		pulse += 0.35 + 0.2 * sin(t * 9.0)
	elif st == Player.State.SOUL_SLASH and ph == "startup":
		var c := _phase_progress()
		pulse += c * (0.6 + 0.3 * sin(t * 14.0))
	_seed_glow.modulate = Color(1.3, 1.15, 0.8, 0.9) * pulse
	_seed_glow.scale = Vector2(2.6, 2.6) * (0.85 + pulse * 0.3)
	if _lantern and _lantern.visible:
		var lant := _spring("lantern", cloth_target * 0.6 + torso_rot * 0.3, delta)
		_lantern.rotation = lant + sin(t * 2.0) * 0.05
		_lantern_glow.modulate = Color(2.0, 1.3, 0.6, 0.7 + 0.2 * sin(t * 7.0))

	# 칼끝 잔상: 타격 구간 동안 칼이 지나간 호를 기억했다가 흐려진다
	var striking := in_attack and ph == "active" and _strike_t() > 0.0
	if striking:
		var ang := _sword_angle()
		if not _trail_on:
			_trail_on = true
			_trail_a0 = ang
			_trail_r = 170.0 if st == Player.State.SOUL_SLASH else 100.0
		_trail_a1 = ang
		_trail_alpha = 1.0
	else:
		_trail_on = false
		_trail_alpha = Motion.damp(_trail_alpha, 0.0, 16.0, delta)
	_guard_a = Motion.damp(_guard_a, 1.0 if st == Player.State.GUARD else 0.0, 16.0 if st == Player.State.GUARD else 9.0, delta)


## 지금 공격의 국면 길이 [startup, active, recovery] (초). 씨앗 베기는 약공격보다 느리다.
func _phase_lens() -> Vector3:
	if _player.state == Player.State.SOUL_SLASH:
		return Vector3(_player.slash_startup, _player.slash_active, _player.slash_recovery)
	return Vector3(_player.light_startup, _player.light_active, _player.light_recovery)


## 지금 국면의 진행도 (0 → 1). player 의 남은 시간으로 계산하므로 국면 길이가 달라도 모양이 같다.
func _phase_progress() -> float:
	var lens := _phase_lens()
	var len := 0.0
	match _player.attack_phase:
		"startup": len = lens.x
		"active": len = lens.y
		"recovery": len = lens.z
	if len <= 0.0:
		return 1.0
	return 1.0 - clampf(_player._attack_timer / len, 0.0, 1.0)


## 타격 곡선의 진행도 (0 → 1). 예비동작 끝자락(STRIKE_WINDOW.x)에서 0, 히트박스 구간의 STRIKE_WINDOW.y 에서 1.
## 두 국면을 '시간'으로 이어 붙여 하나의 창으로 보므로, 국면 길이가 바뀌어도(2페이즈 배속 등) 모양은 같다. 0 이면 아직 당기는 중.
func _strike_t() -> float:
	var win := STRIKE_WINDOW_SLASH if _player.state == Player.State.SOUL_SLASH else STRIKE_WINDOW_LIGHT
	var lens := _phase_lens()
	var s_len: float = lens.x
	var a_len: float = lens.y
	var before := s_len * (1.0 - win.x)          # startup 안에서 타격이 도는 시간
	var total := before + a_len * win.y          # 타격 전체 길이
	var elapsed := 0.0
	match _player.attack_phase:
		"startup": elapsed = maxf(_phase_progress() - win.x, 0.0) * s_len
		"active": elapsed = before + _phase_progress() * a_len
		_: return 1.0
	return clampf(elapsed / maxf(total, 0.0001), 0.0, 1.0)


## 휘두르기 세 박자. 예비(지금 자세 → 당긴 자세, 끝에서 멈칫) → 타격(당긴 자세 → 휘두른 자세, 속도가 차올라 앞을 지나며 지나침) → 되돌림(출렁이며 준비 자세).
## 약공격 1~3타와 씨앗 베기가 같은 틀을 쓴다 (당긴·휘두른 자세와 지나침·출렁임 크기만 다르다).
func _attack_pose() -> Dictionary:
	var windup: Dictionary
	var strike: Dictionary
	var over := 2.0          # 지나침의 크기 (ease_out_back 의 s)
	var bounces := 1.5
	var win := STRIKE_WINDOW_LIGHT
	if _player.state == Player.State.SOUL_SLASH:
		windup = WINDUP_S
		strike = STRIKE_S
		over = 2.6
		bounces = 2.0
		win = STRIKE_WINDOW_SLASH
	else:
		match _player.attack_step:
			1: windup = WINDUP_1; strike = STRIKE_1
			2: windup = WINDUP_2; strike = STRIKE_2
			_: windup = WINDUP_3; strike = STRIKE_3
	var p := _phase_progress()
	match _player.attack_phase:
		"startup":
			var u := _strike_t()
			if u <= 0.0:
				# 당기기는 창이 열리는 순간(win.x)에 정확히 끝나 멈칫하고, 거기서 타격 곡선이 0의 속도로 출발한다
				return _mix(_atk_from, windup, Motion.anticipation(p / maxf(win.x, 0.001)))
			return _mix(windup, strike, _strike_curve(u, over))
		"active":
			return _mix(windup, strike, _strike_curve(_strike_t(), over))
		_:
			# 되돌림: 휘두른 자세에서 잠깐 머물렀다가(앞 20%쯤, 칼이 멈추는 '여운') 출렁이며 준비 자세로.
			# settle 을 그대로 쓰면 첫 순간이 너무 가팔라 휘두른 자세가 화면에 보이기도 전에 돌아와 버린다.
			return _mix(strike, READY, Motion.settle(Motion.ease_in(p, 2.0), bounces, 2.5))


## 낙하 공격 자세: 멈칫(칼을 번쩍) → 급강하(칼끝 아래, 몸을 세움) → 착지(깊게 웅크림) → 일어남(출렁이며 준비 자세)
func _plunge_pose() -> Dictionary:
	match _player.attack_phase:
		"pause":
			var p := 1.0 - clampf(_player._attack_timer / maxf(_player.plunge_pause, 0.001), 0.0, 1.0)
			return _mix(_atk_from if not _atk_from.is_empty() else BASE, PLUNGE_PAUSE, Motion.anticipation(p))
		"dive":
			# 멈칫 자세에서 칼을 아래로 내리꽂는다: 타격 곡선(속도 0 에서 차올라 살짝 지나침)으로 이어 '툭' 하지 않는다.
			# 급강하가 시작된 뒤 지난 시간은 player 의 타이머가 음수로 계속 내려가는 것으로 안다.
			var e := maxf(-_player._attack_timer, 0.0)
			var d := _mix(PLUNGE_PAUSE, PLUNGE_DIVE, _strike_curve(e / PLUNGE_FLIP_TIME, 1.5))
			d["arm_sword"] += sin(_time * 30.0) * 0.03 * clampf(e / PLUNGE_FLIP_TIME, 0.0, 1.0)   # 바람에 칼이 떤다
			return d
		"land":
			var p := 1.0 - clampf(_player._attack_timer / maxf(_player.plunge_land_time, 0.001), 0.0, 1.0)
			return _mix(PLUNGE_DIVE, PLUNGE_LAND, Motion.ease_out(p, 3.0))
		_:
			var p := 1.0 - clampf(_player._attack_timer / maxf(_player.plunge_recovery, 0.001), 0.0, 1.0)
			return _mix(PLUNGE_LAND, READY, Motion.settle(Motion.ease_in(p, 1.5), 1.5, 2.5))


## 타격 곡선 (0→1, 1 = 휘두른 자세): 멈춘 자세에서 속도가 차오르고(앞 55%, 기울기 0 에서 출발) → 가장 빠르게 몸 앞을 지나
## → 끝에서 살짝 지나쳤다 돌아온다. 두 구간의 기울기가 만나도록 이음새 높이 A 를 계산해 속도가 끊기지 않는다.
static func _strike_curve(u: float, s: float) -> float:
	const A_T := 0.55
	var k1 := 2.0 / A_T                     # 앞 구간(포물선)의 끝 기울기 / A
	var k2 := (s + 1.0) / (1.0 - A_T)       # 뒤 구간(ease_out_back)의 시작 기울기 / (1-A)
	var a := k2 / (k1 + k2)
	var c := clampf(u, 0.0, 1.0)
	if c < A_T:
		var q := c / A_T
		return a * q * q
	return a + (1.0 - a) * Motion.ease_out_back((c - A_T) / (1.0 - A_T), s)


static func _mix(a: Dictionary, b: Dictionary, w: float) -> Dictionary:
	var out := {}
	for k in KEYS:
		out[k] = lerpf(a.get(k, BASE[k]), b.get(k, BASE[k]), w)
	return out


## 칼팔이 가리키는 화면 각도 (Visual 기준, 아래 = π/2). 칼날은 팔보다 조금 앞으로 기울어 있다.
func _sword_angle() -> float:
	return PI / 2.0 + _bones["arm_sword"].rotation - 0.5


func _sword_origin() -> Vector2:
	return _hip.position + _bones["arm_sword"].position * RIG_SCALE


# ---------- 전체 변환 (방향·찌그러짐·회전·높이) ----------

func _apply_transform(delta: float, st: Player.State) -> void:
	var f := float(_player.facing)
	# 방향 전환: 한 프레임에 뒤집지 않고 0 을 지나며 얇아졌다가 돌아선다. 지수 감쇠는 첫 프레임에 거의 다 돌아 버리므로
	# 일정한 빠르기로 돈다 (1 → -1 에 0.08초, 60fps 에서 다섯 프레임에 고르게)
	_face = move_toward(_face, f, delta * 25.0)
	var face_sx := (signf(_face) if _face != 0.0 else f) * maxf(absf(_face), 0.08)
	# 구르기: 진행도로 정확히 0 → 한 바퀴. 끊기면(피격 등) 가장 가까운 '바로 선' 각도로 돌아온다
	if st == Player.State.ROLL:
		var p := 1.0 - clampf(_player._roll_timer / maxf(_player.roll_duration, 0.001), 0.0, 1.0)
		_roll_rot = TAU * Motion.ease_in_out(p) * f
	else:
		var rest := roundf(_roll_rot / TAU) * TAU
		_roll_rot = Motion.damp(_roll_rot, rest, 20.0, delta)
		if absf(_roll_rot - rest) < 0.002:
			_roll_rot = 0.0   # 한 바퀴(2π)는 0 과 같은 그림이므로 그냥 0 으로 둔다
	# 쓰러짐: 무릎이 꺾인 뒤(0.3초~) 옆으로 넘어간다
	var lower_target := 0.0
	if st == Player.State.DEAD:
		var w := Motion.ease_in(smoothstep(0.3, 0.95, _death_t), 1.5)
		_fall_rot = -PI / 2.0 * f * w
		lower_target = 30.0 * w
	else:
		_fall_rot = Motion.damp(_fall_rot, 0.0, 12.0, delta)
	if st == Player.State.ROLL:
		var p := 1.0 - clampf(_player._roll_timer / maxf(_player.roll_duration, 0.001), 0.0, 1.0)
		lower_target = 22.0 * smoothstep(0.0, 0.18, p) * (1.0 - smoothstep(0.8, 1.0, p))
	_lower = Motion.damp(_lower, lower_target, 20.0, delta)
	var spin := _spring("spin", 0.0, delta)
	# 찌그러짐은 발을 기준으로 (발이 땅에서 뜨거나 박히지 않게 원점을 내린다)
	var sq := _spring("squash", 0.0, delta)
	sq = clampf(sq, -0.3, 0.35)
	var sx := 1.0 + sq * 0.9
	var sy := 1.0 - sq
	scale = Vector2(sx * face_sx, sy)
	position = Vector2(0.0, FOOT_Y * (1.0 - sy) + _lower)
	rotation = _roll_rot + _fall_rot + spin * f


# ---------- 빛 효과 ----------

func _draw() -> void:
	# 뼈대와 별개의 빛 효과들 (게임 px 단위, 바라보는 방향 기준)
	if _air_ring >= 0.0:
		draw_set_transform(Vector2(0, 50), 0.0, Vector2(1.0, 0.35))
		draw_arc(Vector2.ZERO, 20.0 + _air_ring * 70.0, 0, TAU, 32, Color(0.8, 1.0, 0.85, 1.0 - _air_ring), 3.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _gust_t >= 0.0:
		# 투사체 발사 연출: 영혼 색의 호 두 겹이 손끝에서 앞으로 크게 퍼진다 (투사체가 커진 만큼, 2026-10-19)
		var gc := _player.soul_color()
		var fade := 1.0 - _gust_t
		draw_arc(Vector2(44, -18), 18.0 + _gust_t * 70.0, -1.0, 1.0, 14, Color(gc.r, gc.g, gc.b, fade), 4.5 - 2.5 * _gust_t, true)
		draw_arc(Vector2(30, -18), 10.0 + _gust_t * 40.0, -0.8, 0.8, 10, Color(gc.r, gc.g, gc.b, 0.6 * fade), 2.5, true)
	if _guard_a > 0.02:
		_draw_guard_shield()
	if _guard_ring >= 0.0:
		_draw_guard_ring()
	# 칼끝 잔상: 지나간 호가 남았다가 흐려진다
	if _trail_alpha > 0.02 and absf(_trail_a1 - _trail_a0) > 0.05:
		var o := _sword_origin()
		draw_arc(o, _trail_r, _trail_a0, _trail_a1, 24, Color(SEED, 0.65 * _trail_alpha), 1.5 + 3.5 * _trail_alpha, true)
		draw_arc(o, _trail_r * 0.78, _trail_a0, _trail_a1, 20, Color(SEED, 0.3 * _trail_alpha), 1.0 + 2.0 * _trail_alpha, true)
	# 씨앗 베기 흔적: 앞·위·아래를 덮는 반투명 초승달
	if _slash_t >= 0.0:
		_draw_slash_crescent()
	# 씨앗 베기 예비동작: 칼끝에 빛이 모인다 (씨앗의 힘)
	if _player.state == Player.State.SOUL_SLASH and _player.attack_phase == "startup":
		var c := _phase_progress()
		if c > 0.05:
			var tip := _sword_origin() + Vector2(112.0, 0.0).rotated(_sword_angle())
			draw_circle(tip, 4.0 + 12.0 * c, Color(SEED, 0.4 * c))
			var ring := 1.0 - fmod(_time * 2.2, 1.0)
			draw_arc(tip, 6.0 + 45.0 * ring, 0, TAU, 24, Color(SEED, 0.45 * c * (1.0 - ring)), 2.0, true)
	# 낙하 공격: 급강하 중 칼끝 빛과 바람 줄, 착지 충격 링
	if _player.state == Player.State.PLUNGE and _player.attack_phase == "dive":
		var tip := _sword_origin() + Vector2(112.0, 0.0).rotated(_sword_angle())
		draw_circle(tip, 9.0, Color(SEED, 0.45))
		for i in 3:
			var x := -26.0 + i * 26.0
			var y0 := -120.0 - fmod(_time * 900.0 + i * 70.0, 90.0)
			draw_line(Vector2(x, y0), Vector2(x, y0 - 60.0), Color(1, 1, 1, 0.18), 2.0, true)
	if _plunge_ring >= 0.0:
		_draw_plunge_ring()
	# 정화의 손길: 뻗은 손에 빛
	if _player.state == Player.State.PURIFY:
		var arm: Node2D = _bones["arm_back"]
		var hand: Vector2 = _hip.position + (arm.position + Vector2(0.0, 380.0).rotated(arm.rotation)) * RIG_SCALE
		var g := 0.5 + 0.3 * sin(_time * 9.0)
		draw_circle(hand, 10.0 + 4.0 * g, Color(SEED, 0.35 * g))
	if _purify_ring >= 0.0:
		var rr := 20.0 + _purify_ring * 160.0
		draw_arc(Vector2(50, -20), rr, 0, TAU, 40, Color(SEED, 1.0 - _purify_ring), 5.0 * (1.0 - _purify_ring) + 1.0, true)


## 보호막 위의 점 (앞쪽 각도 a: 0 = 정면, 음수 = 위). 가로는 납작한 타원.
func _shield_point(a: float, ry: float) -> Vector2:
	return GUARD_CENTER + Vector2(cos(a) * ry * GUARD_RX_RATIO, sin(a) * ry)


## 가드 보호막: 얇고 키만 한 타원 호 + 옅은 채움 + 안쪽 가는 선. 살짝 일렁이고, 저스트 가드 때는 전체가 흰빛으로 번쩍인다.
func _draw_guard_shield() -> void:
	var a := _guard_a
	var ry := GUARD_RY + 2.0 * sin(_time * 6.0)
	var col := Color(GUARD_BLUE, 0.75 * a).lerp(Color(1, 1, 1, 0.95 * a), _flash)
	var n := 22
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in n + 1:
		var ang := lerpf(-GUARD_SPAN, GUARD_SPAN, float(i) / n)
		outer.append(_shield_point(ang, ry))
		inner.append(_shield_point(ang, ry * 0.9))
	# 옅은 채움 (호와 그 현 사이)
	draw_colored_polygon(outer, Color(GUARD_BLUE, 0.10 * a).lerp(Color(1, 1, 1, 0.35 * a), _flash))
	draw_polyline(outer, col, GUARD_LINE, true)
	draw_polyline(inner, Color(GUARD_BLUE, 0.35 * a).lerp(Color(1, 1, 1, 0.6 * a), _flash), 1.2, true)
	# 위아래 끝에 작은 빛점 (막은 뒤 잠깐 더 밝다)
	for p in [outer[0], outer[n]]:
		draw_circle(p, 2.5, Color(1, 1, 1, 0.5 * a))
	if _flash > 0.0:
		draw_circle(_shield_point(0.0, GUARD_RY) + Vector2(-16.0, -20.0), 26.0 * _flash + 8.0, Color(1, 1, 1, _flash * 0.8 * a))


## 일반 가드로 막은 순간: 보호막에서 충격 고리가 퍼지고 작은 불꽃 점이 튄다 (0.2초).
func _draw_guard_ring() -> void:
	var t := _guard_ring
	var c := _shield_point(0.0, GUARD_RY)
	c.x -= 10.0
	var fade := 1.0 - t
	draw_arc(c, 14.0 + 64.0 * Motion.ease_out(t, 2.0), 0, TAU, 28, Color(GUARD_BLUE, 0.85 * fade), 1.0 + 3.0 * fade, true)
	draw_arc(c, 6.0 + 30.0 * t, 0, TAU, 20, Color(1, 1, 1, 0.5 * fade), 1.5, true)
	for ang in [-0.95, -0.35, 0.3, 0.9]:
		var d := 18.0 + 72.0 * Motion.ease_out(t, 1.6)
		var p := c + Vector2(cos(ang) * d, sin(ang) * d * 0.8)
		draw_circle(p, 1.5 + 2.5 * fade, Color(1.0, 0.97, 0.85, 0.9 * fade))


## 초승달 위의 점: 어깨 o 에서 각도 a 로, 바깥 가장자리에서 shrink px 안쪽. 위쪽(sin<0)과 아래쪽의 세로 반지름이 다르다.
static func _slash_point(o: Vector2, a: float, shrink: float) -> Vector2:
	var ry := SLASH_RY_UP if sin(a) < 0.0 else SLASH_RY_DOWN
	return o + Vector2(cos(a) * (SLASH_RX - shrink), sin(a) * (ry - shrink))


## 씨앗 베기 흔적: 어깨를 중심으로 위 뒤(SLASH_A0)에서 앞을 지나 아래(SLASH_A1)까지 드러나는 큰 초승달. SLASH_FADE 초에 사라진다.
func _draw_slash_crescent() -> void:
	var t := _slash_t
	var o := _sword_origin()
	var reveal := Motion.ease_out(clampf(t / 0.45, 0.0, 1.0), 2.0)
	var end := lerpf(SLASH_A0, SLASH_A1, reveal)
	if end - SLASH_A0 < 0.05:
		return   # 아직 드러난 호가 없다 (점 하나짜리 다각형은 그릴 수 없다)
	var alpha := 1.0 - smoothstep(0.25, 1.0, t)
	var n := 30
	var pts := PackedVector2Array()
	var edge := PackedVector2Array()
	var edge_in := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(SLASH_A0, end, float(i) / n)
		var p := _slash_point(o, a, 0.0)
		pts.append(p)
		edge.append(p)
		edge_in.append(_slash_point(o, a, 14.0))
	for i in range(n, -1, -1):
		var a := lerpf(SLASH_A0, end, float(i) / n)
		# 안쪽은 호의 가운데가 가장 두껍고 양 끝이 뾰족한 초승달
		var w := sin(float(i) / n * PI)
		pts.append(_slash_point(o, a, lerpf(6.0, SLASH_THICK, w)))
	if pts.size() >= 3:
		draw_colored_polygon(pts, Color(1.0, 0.95, 0.8, 0.28 * alpha))
	draw_polyline(edge, Color(SEED, 0.7 * alpha), 2.0 + 3.0 * alpha, true)
	draw_polyline(edge_in, Color(1, 1, 1, 0.35 * alpha), 1.5, true)


## 낙하 공격 착지: 발밑에서 납작한 충격 링이 퍼지고 흙먼지가 양옆으로 튄다.
func _draw_plunge_ring() -> void:
	var t := _plunge_ring
	var fade := 1.0 - t
	var r := 24.0 + PLUNGE_RING_R * Motion.ease_out(t, 2.2)
	draw_set_transform(Vector2(0, FOOT_Y - 2.0), 0.0, Vector2(1.0, 0.3))
	draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(SEED, 0.9 * fade), 2.0 + 5.0 * fade, true)
	draw_arc(Vector2.ZERO, r * 0.6, 0, TAU, 32, Color(1, 1, 1, 0.5 * fade), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var k := floorf(i * 0.5) / 3.0
		var x := side * (18.0 + (70.0 + 50.0 * k) * Motion.ease_out(t, 1.8))
		var y := FOOT_Y - 6.0 - (22.0 + 18.0 * k) * sin(PI * minf(t * 1.1, 1.0))
		draw_circle(Vector2(x, y), (9.0 + 5.0 * k) * (1.0 - 0.5 * t), Color(0.72, 0.66, 0.5, 0.45 * fade))


# ---------- 신호 ----------

func _on_jumped(air: bool) -> void:
	_kick("squash", -3.0)      # 길쭉하게
	if air:
		_air_ring = 0.0
		_kick("spin", 7.0)     # 이단 점프: 짧게 몸을 말았다 편다


func _on_landed(fall_speed: float) -> void:
	var amount := clampf(fall_speed / 1600.0, 0.1, 0.35)
	_kick("squash", amount * 21.0)
	_kick("crouch", amount * 20.0)


## 낙하 공격으로 바닥에 꽂혔다: 착지보다 훨씬 깊게 찌그러지고 웅크리며 충격 링이 퍼진다.
func _on_plunge_landed() -> void:
	_kick("squash", 7.0)
	_kick("crouch", 12.0)
	_plunge_ring = 0.0


func _on_hit_landed(result: String, _target: Node) -> void:
	if result == "hit" or result == "guard":
		_kick("recoil", 14.0)

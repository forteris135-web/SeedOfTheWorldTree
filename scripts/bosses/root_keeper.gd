extends CharacterBody2D
class_name RootKeeper
## 최종 보스 '뿌리지기'. 세계수의 첫 수호자. 달빛 정원을 홀로 가꿔 왔다. 땅에서 싸운다.
## 2026-10-19 개편(기획자 요청: 단조로움·가시성): 모든 예고를 붉게·크게(가드 가능 = 주황빛, 가드 불가 = 진한 붉은색 깜빡임),
## 지팡이를 그림에서 분리해 실제로 휘두르고, 패턴을 늘리고 연계로 잇는다. 같은 패턴은 연속으로 두 번 쓰지 않는다.
## 1페이즈: 뿌리 가시 SPIKES(바닥 붉은 예고 → 솟음, 1.5배 커짐) / 지팡이 휘두르기 SWEEP(붉은 부채꼴 예고, 보랏빛 호 궤적; 가끔 되돌려 베기 SWEEP2 연계)
##          / 달빛 구슬 ORBS(지팡이 끝 붉은 고리 → 2배 크기 추적 구슬 2개) / 뿌리 손 HAND(붉은 타원 예고 → 거대한 손이 솟아 움켜쥠, 가드 불가, 잡히면 묶임)
##          / 씨앗 비 SEEDS(하늘에서 가시 씨앗 5개, 떨어질 자리에 주황 점) / 달빛 고리 RING(보스 둘레를 도는 구슬 고리가 넓어짐)
## 2페이즈(체력 절반 → 무너졌다 다시 일어서며 주제곡 RISE): 빨라지고(예비 0.7배), 가시 4개 또는 물결 6개, 구슬 4개, 손 2개, 씨앗 7개, 고리 8개,
##          + 뿌리 벽 돌진 WALL(지나갈 띠가 붉게, 가드 불가, 벽이 실제로 밀려옴) + 지팡이 내려찍기 STOMP(양쪽 바닥을 달리는 충격파 2줄 × 2번, 가드 불가, 점프로 넘김)
## 연계(_chain): 씨앗 비 → 뿌리 손, 휘두르기 → 되돌려 베기(앞에서 올려 베기) → (2페이즈) 내려찍기, 가시 → 구슬/고리, 구슬 → 가시, 손 → 휘두르기.
##   연계 직전에 소녀 쪽으로 돌아선다. 무너지면(BROKEN) 예약된 공격은 모두 거둔다. 2페이즈로 넘어갈 때 흐트러짐은 0 으로.
## 체력 0 → 쓰러짐 → 정화 → 마지막 회상 → 선택.
## BossRoom 과 맞추는 약속: start_fight / reset_fight / arena / ground_y / fallen / purified / hp_changed / poise_changed / phase_changed
##   / telegraph(kind) + telegraph_label(kind) / state_name() / debug_log / is_ground() / receive_hit / hp·poise·phase·facing
## v1.1.1 (기획자 v1.1.1 지시서 2-E: 최종 보스 대폭 개편 — 가장 쉬웠던 최종 보스를 가장 매운 보스로):
##   체력 ×1.75·공격력 ×1.25 (던전 단계·난이도 배율 위에 한 번), 2페이즈 공격력 ×1.10 더 (atk_factor),
##   새 패턴 1 '뿌리 촉수'(맵 패턴 — 공격 고르기와 따로 도는 시계, 아주 긴 사선 뿌리 2줄 / 2페이즈 4줄, 가드 불가, RootTentacle),
##   새 패턴 2 '씨앗 폭우'(BARRAGE — 하늘에서 싸움터 전체로 줄지어 떨어지는 가시 씨앗 3물결, 물결마다 틈 하나가 옮겨 가며 소녀를 몰아감;
##   2페이즈에도 그대로), 2페이즈 '폭주'(연계 확률↑·휘두르기 → 가시 새 연계·연계 앞 되돌림 짧게),
##   대사(처음 마주칠 때 싸움 전 대화 상자 + 싸우는 동안 위쪽 자막 RootKeeperSpeech, data/dialogue/root_keeper.json).

enum State { WAIT, INTRO, STANCE, SPIKES, SWEEP, ORBS, WALL, RISE, BROKEN, FALLEN, PURIFIED, HAND, SEEDS, RING, STOMP, SWEEP2, BARRAGE }
const ATTACK_STATES := [State.SPIKES, State.SWEEP, State.ORBS, State.WALL, State.HAND, State.SEEDS, State.RING, State.STOMP, State.SWEEP2, State.BARRAGE]
## 가드 불가 패턴 (붉은 예고 빛 + 그림이 붉게 깜빡임)
const RED_STATES := [State.WALL, State.HAND, State.STOMP]
## 가드 불가 예고의 깜빡임 속도(초당 횟수). 그림·뿌리 손 예고가 함께 쓴다. 빛에 민감한 사람을 위해 3 이하로 둔다.
const TELEGRAPH_BLINK_HZ := 2.5
## 휘두르기 판정 사각형 (바라보는 방향 기준, Hitbox 노드 기준 — 노드는 발밑에서 y -60). 그림의 붉은 부채꼴도 이 값을 읽는다.
const SWEEP_BOX := Rect2(-60, -200, 380, 230)
const SWEEP2_BOX := Rect2(-80, -220, 400, 250)
## 휘두를 때 앞으로 미끄러지는 첫 속도 (공격 범위 예고가 이만큼 더 앞을 덮는다)
const SWEEP_SLIDE := 300.0
const SWEEP2_SLIDE := 200.0
## 휘두르기 감속과 판정 길이 (예고가 미끄러지는 거리를 계산한다)
const SWEEP_DECEL := 2000.0
const SWEEP_ACTIVE := 0.2
## 지팡이 내려찍기·뿌리 벽 판정 (바라보는 쪽 기준, Hitbox 노드 기준). v1.1.0: 공격 범위 예고·이펙트가 이 값을 그대로 쓴다.
const STOMP_BOX := Rect2(-130, -130, 260, 150)
const WALL_BOX := Rect2(0, -260, 200, 290)
const WALL_SPEED := 1100.0
const WALL_ACTIVE := 0.6
## 맞딜 방지 계량기 (v1.1.0): 이 거리 안에 붙어 있으면 쌓이고, 다 차면 응징 (몸 가까이 땅이면 두 번 내려찍기, 떠 있거나 멀면 뿌리 창).
## v1.1.0 은 260. v1.1.0 맞딜 검수 2: 400 — 뿌리지기는 가까우면(260 안) 뒷걸음질하므로, 쫓아가 지팡이 끝 거리(350~390)에 서서
## 씨앗 베기(앞 340)·바람·빛을 쏟으며 패턴을 맞아 넘기는 소녀(달리며 영혼 봇 — 18판 중 3판 승, 봇 체력 54%)도 '붙어 있다'로 센다.
const CROWD_RANGE := 400.0
## 계량기가 '붙어 있다'로 세는 소녀의 높이 (보스 발밑에서 소녀 가운데까지, px). v1.1.0 맞딜 검수 2: 몸 둘레에서 제자리 점프·이단 점프로
## 떠 있으며 영혼 기술을 쏟는 소녀(공중 영혼 봇 — 함께 잠김을 걷은 뒤 18판 중 13판 승)도 센다 (기본 300 은 점프 꼭대기를 놓쳤다).
const CROWD_MAX_UP := 520.0
## 맞딜 응징 내려찍기 (v1.1.0 맞딜 검수 2 — 영혼 기술 함께 잠김을 걷고 그 대신): 몸에 붙어 버티는 소녀에게만 오는 내려찍기는
##  - 판정·예고·이펙트가 몸 둘레 높이까지 솟는 뿌리 분출 사각형 PUNISH_STOMP_BOX (가로 ±150, 땅에서 위로 400 — 몸 둘레에 떠 있는 소녀도 맞는다)
##  - 첫 타격 뒤에도 소녀가 계량기 자리(CrowdMeter.covers) 안에 남아 있으면 한 번 더: 첫 타격(0.3초) 뒤 PUNISH_RESTOMP 초 동안 같은 사각형에
##    붉은 예고가 다시 차오르고 둘째 타격 (첫 타격에서 0.55초 — 맞은 뒤 무적 0.5초가 끝난 뒤라, 맞고도 그 자리에 머무는 소녀는 또 맞는다.
##    예고를 보고 빠진 소녀에게는 오지 않는다).
##    둘째 충격파 쌍(0.55초)은 둘째 타격과 함께 나간다. 둘 다 가드 불가(붉은 예고), 구르기로 피한다.
## 보통 내려찍기(2페이즈 후보)는 그대로 (STOMP_BOX, 한 번).
const PUNISH_STOMP_BOX := Rect2(-150, -400, 300, 420)
const PUNISH_RESTOMP := 0.25
## 계량기가 찼을 때 소녀가 땅에 서서 몸 가까이(가로 PUNISH_STOMP_REACH 안)면 위의 두 번 내려찍기, 떠 있거나 그보다 멀면
## (지팡이 끝 거리에서 영혼 기술을 쏟거나 제자리 점프로 떠 있는 소녀 — 뒷걸음질하는 뿌리지기를 쫓아 붙는다) '뿌리 창':
## 소녀 밑을 따라오는 큰 뿌리 가시 둘 (예비 60% 까지 소녀 발밑·달리는 쪽 앞을 따라가다 굳는다, 높이 LANCE_HEIGHT —
## 이단 점프 꼭대기까지 닿는다, 예고 기둥 = 판정, 주황, 가드 가능 — 높은 자리 응징의 큰 가시와 같은 가시).
const PUNISH_STOMP_REACH := 175.0
const LANCE_HEIGHT := 600.0
const LANCE_GAP := 200.0
## 뿌리 창이 솟는 순간 소녀가 있는 자리에 LANCE_FOLLOW 초 뒤 한 번 더 솟는 큰 가시 (스스로 기둥 예고를 그리며 기다린다 — 예고 = 판정).
## 맞은 뒤 무적 0.5초가 끝난 뒤라, 맞고도 그 자리에 머무는 소녀는 또 맞는다. 옆으로 비키면 그만.
const LANCE_FOLLOW := 0.55
## 2페이즈 쉬는 시간 배수 (v1.1.0 맞딜 방지 사다리 4단계: 2페이즈 공격 사이 쉬는 시간 −15%)
const P2_REST_MULT := 0.85
## 높은 자리 응징 (v1.1.0 맞딜 검수, PerchMeter): 소녀가 바닥보다 200 넘게 높은 곳(가지 위·그 높이의 공중)에 2.5초 머물면
## 다음 공격은 '큰 뿌리 가시' — 소녀 발밑(2페이즈는 옆 하나 더)에서 소녀 발 높이 + PERCH_SPIKE_OVER 까지 솟는 가시 (가지를 뚫는다).
## 예고 = 판정 기둥(바닥에서 가시 끝까지, 주황, 가드 가능; 소녀 발밑 가시는 공격 범위 예고 사각형으로도), 예비 길이는 보통 가시와 같다.
## 옆으로 한 걸음(80px) 비키거나 가지에서 내려오거나 구르면 피한다. (가지 위에서 원거리 영혼만 쏘는 봇이 6판 중 3판 이겼다)
const PERCH_SPIKE_OVER := 150.0
const PERCH_SPIKE_MAX := 760.0
## 2페이즈 큰 가시 둘째 줄 간격 (px)
const PERCH_SPIKE_GAP := 200.0

## ---- v1.1.1 추가 배율 ----
## 숫자의 단일 출처는 Balance.BOSS_EXTRA["root"] (hp 1.75 · atk 1.25 · atk_phase2 1.10).
## hp: 체력 배율, atk: 모든 공격 피해 배율, atk_phase2: 2페이즈(체력 절반 → 다시 일어선 뒤)에 더 곱하는 배율.
## 던전 단계·난이도 배율(Balance.hp_mult / 받는 피해 쪽 Balance.incoming_damage)과는 따로, 여기서 한 번만 곱한다.
## 씨앗 폭우는 2페이즈에서도 그대로 (기획자 지시 '2페이즈에서 강화되지 않고 유지') — 2페이즈 공격력 ×1.10 도 받지 않는다.
## true 로 바꾸면 씨앗 폭우도 2페이즈 배율을 받는다.
const BARRAGE_PHASE2_ATK := false
## 2페이즈 '폭주': 연계가 예약된 공격의 되돌림 길이 배수 (연계 사이 빈틈이 짧아진다)
const P2_CHAIN_RECOVERY := 0.7

## ---- v1.1.1 새 패턴 1 '뿌리 촉수' (맵 패턴) ----
## 공격 고르기와 따로 도는 시계(_map_timer)로 주기마다 — 다른 공격과 겹칠 수 있다 (씨앗 폭우·뿌리 벽 돌진·맞딜 응징 중에는 끝날 때까지 미룬다).
## 아주 긴 뿌리 촉수가 땅에서 비스듬히(땅과 34~42도) 솟아 싸움터를 가로지른다: 1페이즈 2줄, 2페이즈 4줄. 가드 불가(붉은 띠, 구르기로 피함).
## 자리(map_layout): 싸움터 폭을 줄 수로 똑같이 나눈 간격 W 마다 한 줄 — 한 줄은 소녀가 선 자리를 덮고 나머지는 W 씩 떨어진다
## (싸움터 끝을 넘으면 반대 끝에서 돌아 들어온다). 서 있는 소녀가 맞는 땅 폭(약 360px)이 W(1페이즈 1340·2페이즈 670) 가운데라
## 줄 사이에 늘 300px 넘는 빈 땅이 남는다 (피할 틈). 땅에서 멀어질수록 높아져 가지 위·공중의 소녀도 맞는다.
const MAP_FIRST := 6.0
const MAP_INTERVAL := Vector2(10.0, 14.0)
const MAP_INTERVAL_P2 := Vector2(9.0, 12.0)
## 다시 일어선 뒤(2페이즈 시작) 첫 맵 패턴까지 (초, 싸우는 시간)
const MAP_AFTER_RISE := 3.5
## 예고 길이 (초). 줄마다 MAP_STAGGER 씩 늦게 솟는다.
const MAP_TELEGRAPH := 1.25
const MAP_TELEGRAPH_P2 := 1.05
const MAP_STAGGER := 0.12
## 맵 패턴을 건 뒤 이 시간(초) 동안은 씨앗 폭우를 고르지 않는다 (예고 1.25 + 줄 차례 + 판정 창)
const MAP_BARRAGE_GAP := 2.2
## 땅과 이루는 각 (도, 이 사이에서 줄마다 무작위)
const MAP_ANGLE := Vector2(34.0, 42.0)
## 촉수가 기운 쪽의 가로 여유가 이보다 짧으면 반대로 기운다 (벽에 막혀 짧은 촉수가 되지 않게)
const MAP_MIN_RUN := 1000.0
const MAP_MAX_LEN := 2600.0
## 촉수가 싸움터 위로 넘어가는 높이 (싸움터 윗변 위로 px)
const MAP_TOP_OVER := 400.0
## 서 있는 소녀 몸 (맞는 땅 폭 계산): 높이 132·반폭 25 (player.tscn 맞는 영역 캡슐)
const BODY_H := 132.0
const BODY_HALF := 25.0

## ---- v1.1.1 새 패턴 2 '씨앗 폭우' (BARRAGE) ----
## 지팡이를 머리 위로 들어(예비 BARRAGE_STARTUP) 하늘에서 가시 씨앗을 싸움터 전체에 줄지어 떨어뜨린다 — BARRAGE_WAVES 물결, BARRAGE_WAVE_GAP 초 간격.
## 물결마다 한 군데만 빈다(틈 반폭 BARRAGE_GAP_HALF — 터짐 반지름 70·소녀 반폭 25 를 빼면 서 있을 폭 약 330px).
## 첫 틈은 소녀에게서 BARRAGE_FIRST 만큼 옆(제자리에 서 있으면 맞는다), 다음 틈은 같은 쪽으로 BARRAGE_STEP 씩 옮겨 가며(벽에 닿으면 돌아섬)
## 소녀를 몰아간다. 씨앗마다 떨어질 자리에 주황 점 예고(RootSeed, 가드 가능)가 뜨고 BARRAGE_HOVER 초 떠서 기다렸다가 떨어진다.
## 2페이즈에서도 그대로 (빨라지지도 늘지도 않는다 — 기획자 지시).
const BARRAGE_STARTUP := 0.9
const BARRAGE_WAVES := 3
const BARRAGE_WAVE_GAP := 1.0
const BARRAGE_SPACING := 170.0
const BARRAGE_GAP_HALF := 260.0
const BARRAGE_HOVER := 0.55
const BARRAGE_FIRST := Vector2(260.0, 420.0)
const BARRAGE_STEP := Vector2(380.0, 520.0)
## 틈 가운데가 싸움터 끝에서 이만큼 안쪽에 있게 / 씨앗 줄의 양 끝 여백
const BARRAGE_EDGE := 200.0
const BARRAGE_ROW_MARGIN := 60.0

## ---- v1.1.1 대사 (기획자 지시서 2-E 추가: 스토리텔링) ----
## 처음 마주칠 때만(깃발 INTRO_FLAG) 싸움 전에 대화 상자로 몇 마디 — 셀레니아는 말하지 않는다(대사 원칙), 뿌리지기만 그녀에게 말한다.
## 싸우는 동안: 화면 위쪽 자막(RootKeeperSpeech — 입력을 막지 않는다)으로 짧은 한 마디씩
## (시작·체력 75%·60%·다시 일어섬·35%·15%·소녀가 회복할 때(두 번까지)·소녀가 쓰러지기 직전·소녀가 쓰러짐·뿌리지기가 쓰러짐).
## 대사는 data/dialogue/root_keeper.json (SCRIPT.md 8장, 임시 — 기획자가 문장만 고치면 된다). 보스 러시에는 둘 다 없다.
const DIALOGUE_PATH := "res://data/dialogue/root_keeper.json"
const INTRO_FLAG := "root_keeper_intro_seen"
## 체력 비율 → 대사 키 (그 아래로 처음 내려갈 때 한 번)
const HP_LINES := [[0.75, "hp75"], [0.6, "hp60"], [0.35, "hp35"], [0.15, "hp15"]]
## 시작 대사는 싸움이 시작되고 이만큼 뒤 (보스 등장 이름 카드(3초)가 걷힌 뒤)
const START_LINE_DELAY := 1.2
## 소녀가 쓰러지기 직전 대사: 체력 비율이 이 아래로 내려가면 (한 번)
const LOW_HP_LINE := 0.3
const HEAL_LINES_MAX := 2
const HEAL_LINE_GAP := 15.0

signal hp_changed(hp: float, max_hp: float)
signal poise_changed(poise: float, max_poise: float)
signal phase_changed(phase: int)
signal state_changed(state: State)
signal fallen
signal purified
signal telegraph(kind: String)

## 체력: 최종 보스라 새(1800)·기사(1650)보다 많게 (2026-10-19 검수: 1400 으로 남아 가장 빨리 쓰러졌다 — 기사와 같은 ×1.5)
@export var max_hp := 2100.0
## 흐트러짐 한도·무너짐 길이 (200 / 4.0초면 공격 버튼만 눌러도 무너짐이 이어졌다 — '샌드백')
@export var max_poise := 320.0
@export var poise_decay := 7.0
@export var broken_time := 3.0
@export var broken_damage_multiplier := 1.6
## 예비동작·타격 중에 받는 흐트러짐 배수 (슈퍼아머)
@export var attack_poise_multiplier := 0.5
## 무너졌다 일어선 뒤 이 시간(초) 동안은 흐트러짐이 쌓이지 않는다 (저스트 가드는 예외)
@export var poise_immune_after_broken := 2.5
@export var walk_speed := 140.0
@export var gravity := 2600.0
## 공격 피해 (기획서: 14~32)
@export var spike_damage := 20.0
@export var sweep_damage := 24.0
@export var sweep2_damage := 20.0
@export var orb_damage := 16.0
@export var ring_damage := 14.0
@export var wall_damage := 32.0
@export var hand_damage := 22.0
@export var seed_damage := 16.0
@export var stomp_wave_damage := 20.0
@export var stomp_slam_damage := 26.0
## 뿌리 손에 잡혀 묶이는 시간
@export var hand_hold := 0.7
## v1.1.1 새 패턴 피해 (기본값 — atk_factor 와 Balance 배율을 받는다): 뿌리 촉수 / 씨앗 폭우는 씨앗 비와 같은 seed_damage
@export var tentacle_damage := 24.0

var state: State = State.WAIT
var hp := 2100.0
var poise := 0.0
var phase := 1
var facing := -1
var player: Player
var arena: Rect2
var ground_y := 0.0
var attack_phase := ""   # startup / active / recovery (공격이 아니면 "")
var windup_progress := 0.0
## 지금 공격의 단계 길이(초). 그림이 진행도(남은 시간 / 길이)를 계산하는 데 쓴다.
var startup_len := 0.5
var active_len := 0.2
var recovery_len := 0.8
## 다시 일어서는 연출 길이 (RISE)
var rise_len := 3.0
## 그림에 주는 힌트: "" / "stagger"(저스트 가드로 지팡이가 튕김 — 그림만 휘청, 공격 흐름은 그대로)
var anim_hint := ""
var _hint_timer := 0.0
## 저스트 가드 휘청의 세기 (1 → 0 으로 stagger_len 동안 서서히 줄어든다). 그림은 이 값만큼 뒤로 젖힌다.
var stagger := 0.0
var stagger_len := 0.45
## 몸 돌리기 규칙: 소녀가 이만큼(px) 넘게 반대쪽에 있어야 돌고, 한 번 돌면 이 시간 동안은 다시 돌지 않는다.
@export var face_deadzone := 40.0
@export var face_hold := 0.25
var _face_hold := 0.0
## 예고 자리들 (그림이 붉은 예고를 그린다)
var spike_marks: Array = []     # 가시가 솟을 x
var spike_delays: Array = []    # 가시마다 솟기 전 기다리는 시간 (물결)
var spike_heights: Array = []   # 가시마다 솟는 높이 (비면 RootSpike.HEIGHT; 높은 자리 응징의 큰 가시만 더 높다)
var hand_targets: Array = []    # 뿌리 손이 솟을 x (예비 60% 까지는 소녀를 따라간다)
var _spike_wave := false
## 패턴 고르기: 직전 패턴(연속 금지), 예약된 연계
var _last_attack := -1
var _chain := -1
## 예약된 일(초 뒤에 부르기). create_timer 대신 상태 기계 안에서 돌려 시험·리셋이 정확하다.
var _events: Array = []
var _clock := 0.0
var _timer := 0.0
var _poise_hold := 0.0
var _poise_immune := 0.0
var _flash := 0.0
var _registered := false
var _home := Vector2.ZERO
var _red := false
var debug_log := false
## 공격 범위 예고 / 맞딜 방지 계량기 (v1.1.0)
var _tel: RangeTelegraph
var crowd := CrowdMeter.new(CROWD_RANGE)
## 낙하 공격 감쇠 시계 (v1.1.0 최종 검수 — 앞 낙하 공격 뒤 4초 안에 또 맞으면 피해 ×0.6^n·흐트러짐 ×0.5^n; scripts/combat/plunge_decay.gd)
var plunge_decay := PlungeDecay.new()
## 높은 자리 계량기 (v1.1.0 맞딜 검수) / 다음 가시가 높은 자리 응징(큰 가시)인가
var perch := PerchMeter.new()
var _perch_spikes := false
## 지금 공격이 맞딜 응징인가 (응징 공격이 끝날 때까지 흐트러짐이 쌓이지 않는다 — 두들겨 끊거나 되돌림에 무너뜨릴 수 없다)
var punishing := false
## 응징 내려찍기 횟수 (시험이 --boss-set 으로 바꿀 수 있게 실수) / 이번 내려찍기에 남은 둘째 타격 수 / 다음 _begin 이 응징인가
@export var punish_stomps := 2.0
var _stomps_left := 0
var _slams := 0
var _punish_start := false
## 이번 가시가 맞딜 응징 '뿌리 창'인가 (소녀 밑을 따라온다) / 다음 _start_attack 이 뿌리 창인가
var _lance := false
var _lance_next := false
## 뿌리 벽: 판정이 켜진 자리와 벽까지 갈 수 있는 거리 (예고·이펙트가 쓴다)
var _wall_from := Vector2.ZERO
## 뿌리 벽 돌진 거리 기억 (_wall_travel): 출발 자리·방향·거리. 새 뿌리 벽을 시작할 때 비운다
var _wall_run_from := Vector2(INF, INF)
var _wall_run_face := 0
var _wall_run := 0.0
## v1.1.1 맵 패턴 시계 (싸우는 동안만 흐른다 — _map_clock_runs). 시험이 패턴을 손으로 걸면(force_pattern) manual_control 이 켜져 저절로는 안 나온다.
var _map_timer := MAP_FIRST
var _map_struck_at := -100.0
var manual_control := false
## 마지막으로 건 씨앗 폭우의 물결 자리 (시험·그림용): [{"gap": x, "xs": [..]}, ...]
var barrage_waves: Array = []
## v1.1.1 대사: 싸움 전 대화를 거는가 (0 = 이 방이 실제 게임 장면일 때만 — 시험이 방을 자식으로 놓으면 건너뜀, 1 = 늘(시험), -1 = 안 함)
var intro_talk_mode := 0
var _talking := false
var _speech: RootKeeperSpeech
var _said := {}
var _heal_said := 0
var _heal_said_at := -100.0
var _pending_lines: Array = []   # [시각(_clock), 키]
var _lines_cache: Dictionary = {}

@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
const SPIKE := preload("res://scenes/combat/root_spike.tscn")
const HAND := preload("res://scenes/bosses/root_hand.tscn")
const SEED := preload("res://scenes/bosses/root_seed.tscn")
const ORB := preload("res://scenes/bosses/root_orb.tscn")
const SHOCKWAVE := preload("res://scenes/bosses/root_shockwave.tscn")
const WALL_FX := preload("res://scenes/bosses/root_wall.tscn")
const TENTACLE := preload("res://scenes/bosses/root_tentacle.tscn")


func _ready() -> void:
	add_to_group("boss")
	add_child(preload("res://scripts/fx/root_keeper_fx.gd").new())   # 이펙트 리뉴얼 F2: 기술 이펙트 (판정과 무관)
	_tel = RangeTelegraph.attach(self)
	crowd.max_up = CROWD_MAX_UP
	# v1.1.0 체력 배율: 보스가 놓인 방의 던전 단계 1.1^단계 × 난이도 (새·수관 ×1). reset_fight 는 max_hp 를 읽는다.
	# v1.1.1: 뿌리지기 추가 배율 ×1.75 를 한 번 더 (extra("hp"), 씬을 새로 만들 때마다 한 번 — 겹쳐 곱해지지 않는다)
	max_hp *= Balance.hp_mult(Balance.region_of(self)) * extra("hp")
	hp = max_hp
	_home = global_position
	visible = false
	_speech = RootKeeperSpeech.new()
	_speech.name = "Speech"
	add_child(_speech)


## v1.1.1 뿌리지기 추가 배율 (hp / atk / atk_phase2) = Balance.BOSS_EXTRA["root"]
static func extra(key: String) -> float:
	return Balance.boss_extra("root", key)


## 지금 공격 피해 배율 (v1.1.1): 추가 공격력 ×1.25, 2페이즈면 ×1.10 더. 던전 단계·난이도 배율은 소녀가 받을 때(Balance.incoming_damage) 따로.
func atk_factor() -> float:
	return extra("atk") * (extra("atk_phase2") if phase == 2 else 1.0)


## 기본 피해 → 이 보스가 실제로 싣는 피해 (atk_factor 를 곱한 값)
func _dmg(base: float) -> float:
	return base * atk_factor()


func start_fight(p: Player) -> void:
	player = p
	visible = true
	global_position = Vector2(arena.get_center().x + 450, ground_y)
	facing = -1
	_set_state(State.INTRO)
	_timer = 2.6
	_map_timer = MAP_FIRST
	_said.clear()
	_heal_said = 0
	_pending_lines.clear()
	if _speech:
		_speech.hud = get_parent().get_node_or_null("CombatHUD") if get_parent() else null
		_speech.clear()
	if not player.healed.is_connected(_on_player_healed):
		player.healed.connect(_on_player_healed)
		player.hp_changed.connect(_on_player_hp_changed)
		player.died.connect(_on_player_died)
	# 처음 마주칠 때만 싸움 전 대화 (BossRoom 이 등장 구도를 잡은 뒤에 — 같은 틱의 _frame_intro 가 구도를 덮어쓰지 않게 미뤄 건다)
	if _intro_talk_due():
		Progress.set_flag(INTRO_FLAG)
		_talking = true
		_start_intro_talk.call_deferred()


func reset_fight() -> void:
	_unregister()
	hp = max_hp
	poise = 0.0
	_poise_immune = 0.0
	phase = 1
	visible = false
	velocity = Vector2.ZERO
	hitbox.deactivate()
	_clear_marks()
	_clear_effects()
	_events.clear()
	_last_attack = -1
	_chain = -1
	_red = false
	_spike_wave = false
	crowd.reset()
	perch.reset()
	_perch_spikes = false
	plunge_decay.reset()
	_tel.clear()
	_map_timer = MAP_FIRST
	barrage_waves.clear()
	_pending_lines.clear()
	_said.clear()
	_heal_said = 0
	_talking = false
	if _speech:
		_speech.clear()
	global_position = _home
	_set_state(State.WAIT)
	hp_changed.emit(hp, max_hp)
	poise_changed.emit(poise, max_poise)


func _physics_process(delta: float) -> void:
	if state == State.WAIT or state == State.PURIFIED:
		return
	_flash = maxf(_flash - delta * 6.0, 0.0)
	plunge_decay.tick(delta)
	_poise_hold = maxf(_poise_hold - delta, 0.0)
	_poise_immune = maxf(_poise_immune - delta, 0.0)
	if _poise_hold <= 0.0 and poise > 0.0 and state not in [State.BROKEN, State.FALLEN, State.RISE]:
		poise = maxf(poise - poise_decay * delta, 0.0)
		poise_changed.emit(poise, max_poise)
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0
	_timer -= delta
	_clock += delta
	_tick_events()
	_tick_lines()
	# v1.1.1 맵 패턴 '뿌리 촉수': 공격 고르기와 따로 도는 시계 (다른 공격과 겹칠 수 있다)
	if player and _map_clock_runs():
		_map_timer -= delta
		if _map_timer <= 0.0 and _map_can_fire():
			_map_strike()
	_face_hold = maxf(_face_hold - delta, 0.0)
	stagger = maxf(stagger - delta / stagger_len, 0.0)
	if player:
		# 맞딜 방지: 공격할 수 있는 동안 몸 가까이 붙어 있으면 쌓인다 (무너짐·일어서기 = 빈틈에는 쌓이지 않는다)
		# (응징 공격 동안에도 쌓인다 — 내려찍기를 맞고도 계속 붙어 있으면 또 내려찍는다. 구르기로 빠지면 식는다)
		crowd.tick(delta, global_position, player.global_position, state == State.STANCE or state in ATTACK_STATES, facing)
		# 높은 자리: 공격할 수 있는 동안 소녀가 가지 높이에 머물면 쌓인다 (큰 가시 응징 중에는 쌓지 않는다)
		perch.tick(delta, ground_y, player, (state == State.STANCE or state in ATTACK_STATES) and not (state == State.SPIKES and punishing))
	if _hint_timer > 0.0:
		_hint_timer -= delta
		if _hint_timer <= 0.0:
			anim_hint = ""
	var fast := 0.7 if phase == 2 else 1.0
	match state:
		State.INTRO:
			velocity.x = 0.0
			if _talking:
				_timer = maxf(_timer, 0.6)   # 싸움 전 대화가 끝날 때까지 기다린다 (끝나고 0.6초 뒤 자세)
			if _timer <= 0.0:
				_set_state(State.STANCE)
				_timer = 0.8
				_say_later("start", START_LINE_DELAY)
		State.STANCE:
			if player:
				var dx := player.global_position.x - global_position.x
				var want_face := 1 if dx > 0.0 else -1
				if want_face != facing and absf(dx) > face_deadzone and _face_hold <= 0.0:
					facing = want_face
					_face_hold = face_hold
				# 천천히 거리를 유지한다 (너무 가까우면 물러나고, 멀면 다가온다)
				var want := 0.0
				if absf(dx) < 260.0:
					want = -want_face * walk_speed
				elif absf(dx) > 700.0:
					want = want_face * walk_speed
				velocity.x = move_toward(velocity.x, want, 800.0 * delta)
				if _timer <= 0.0:
					_choose(absf(dx))
			else:
				velocity.x = 0.0
		State.SPIKES:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			if _lance and attack_phase == "startup" and windup_progress < 0.6:
				_track_lance()
			_phase_step(delta, startup_len, 0.3, 1.0 * fast, func() -> void: _raise_spikes())
		State.SWEEP:
			velocity.x = move_toward(velocity.x, 0.0, SWEEP_DECEL * delta)
			_phase_step(delta, startup_len, SWEEP_ACTIVE, 0.8 * fast, func() -> void:
				var hit := HitData.make(_dmg(sweep_damage), 0.0, self, Vector2(560, -220))
				hitbox.set_box(SWEEP_BOX, facing)
				hitbox.activate(hit, SWEEP_ACTIVE)
				velocity.x = facing * SWEEP_SLIDE
				Sfx.play("staff_swing", -2.0, 0.1))
		State.SWEEP2:
			velocity.x = move_toward(velocity.x, 0.0, SWEEP_DECEL * delta)
			_phase_step(delta, startup_len, SWEEP_ACTIVE, 0.7 * fast, func() -> void:
				var hit := HitData.make(_dmg(sweep2_damage), 0.0, self, Vector2(520, -260))
				hitbox.set_box(SWEEP2_BOX, facing)
				hitbox.activate(hit, SWEEP_ACTIVE)
				velocity.x = facing * SWEEP2_SLIDE
				Sfx.play("staff_swing", -1.0, 0.1))
		State.ORBS:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, startup_len, 0.2, 1.1 * fast, func() -> void:
				var n := 2 if phase == 1 else 4
				var gap := 0.3 if phase == 1 else 0.22
				for i in n:
					var off := i - (n - 1) / 2.0
					_queue(i * gap, func() -> void: _spawn_orb(off)))
		State.WALL:
			_phase_step(delta, startup_len, WALL_ACTIVE, 1.3, func() -> void:
				var hit := HitData.make(_dmg(wall_damage), 0.0, self, Vector2(760, -340))
				hit.guardable = false
				_wall_from = global_position
				hitbox.set_box(WALL_BOX, facing)
				hitbox.activate(hit, WALL_ACTIVE)
				velocity.x = facing * WALL_SPEED
				Juice.shake(10.0)
				Sfx.play("root_wall", 0.0, 0.08)
				var wall: RootWall = WALL_FX.instantiate()
				wall.facing = facing
				wall.life = 0.75
				add_child(wall)
				_red = false)
			if attack_phase == "active":
				if is_on_wall():
					velocity.x = 0.0
			else:
				velocity.x = move_toward(velocity.x, 0.0, 2500.0 * delta)
		State.HAND:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			if attack_phase == "startup" and windup_progress < 0.6:
				_track_hands()
			_phase_step(delta, startup_len, 0.4, 0.9 * fast, func() -> void:
				_red = false
				for i in hand_targets.size():
					var h: RootHand = HAND.instantiate()
					h.damage = _dmg(hand_damage)
					h.hold_time = hand_hold
					h.delay = i * 0.25
					h.throw_dir = 1 if hand_targets[i] >= global_position.x else -1
					get_parent().add_child(h)
					h.global_position = Vector2(hand_targets[i], ground_y)
					h.source = self
				hand_targets.clear())
		State.SEEDS:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, startup_len, 1.3, 0.8 * fast, func() -> void:
				var n := 5 if phase == 1 else 7
				var offsets := [0.0, -260.0, 260.0, -130.0, 130.0, -390.0, 390.0]
				var px := player.global_position.x if player else global_position.x
				for i in n:
					var x: float = px + offsets[i]
					_queue(i * 0.18, func() -> void: _spawn_seed(x)))
		State.RING:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, startup_len, 2.4, 0.6 * fast, func() -> void:
				var n := 6 if phase == 1 else 8
				for i in n:
					var o: RootOrb = ORB.instantiate()
					o.mode = RootOrb.Mode.ORBIT
					o.damage = _dmg(ring_damage)
					o.center = self
					o.center_offset = Vector2(0, -200)
					o.orbit_r = 90.0
					o.orbit_grow = 280.0 if phase == 1 else 330.0
					o.orbit_max = 760.0
					o.angle = TAU * i / n
					o.angular_speed = 2.2 if phase == 1 else 2.7
					o.lifetime = 2.6
					o.ground_y = ground_y
					o.radius = 34.0
					get_parent().add_child(o)
					o.global_position = global_position + o.center_offset
					o.launch(Vector2.LEFT, self)
				Sfx.play("ring_hum", -4.0, 0.05))
		State.STOMP:
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			if attack_phase == "active" and _timer <= 0.0 and _stomps_left > 0 and player and crowd.covers(global_position, player.global_position):
				# 응징 내려찍기의 둘째 타격 (첫 타격 뒤에도 붙어 있으면): 같은 사각형에 붉은 예고가 다시 차오른다 (첫 타격에서 0.3 + PUNISH_RESTOMP 초)
				_stomps_left -= 1
				attack_phase = "startup"
				windup_progress = 0.0
				_timer = PUNISH_RESTOMP
				startup_len = PUNISH_RESTOMP
				_red = true
				_tel.show_rect(melee_reach(), true, PUNISH_RESTOMP)
			_phase_step(delta, startup_len, 0.3, 1.2, func() -> void:
				_red = false
				var hit := HitData.make(_dmg(stomp_slam_damage), 0.0, self, Vector2(620, -380))
				hit.guardable = false
				hit.hitstop = 0.08
				hitbox.set_box(PUNISH_STOMP_BOX if punishing else STOMP_BOX, 1)
				hitbox.activate(hit, 0.25)
				Juice.shake(14.0)
				Juice.rumble(0.7, 1.0, 0.3)
				Sfx.play("stomp", 0.0, 0.06)
				_slams += 1
				if _slams == 1:
					# 첫 타격: 충격파 양쪽 + 0.55초 뒤 한 쌍 더 (응징의 둘째 타격은 그 둘째 쌍과 함께 — 충격파를 더 내지 않는다)
					_spawn_shockwaves()
					_queue(0.55, func() -> void:
						Juice.shake(6.0)
						Sfx.play("stomp", -5.0, 0.06)
						_spawn_shockwaves()))
		State.BARRAGE:
			# v1.1.1 씨앗 폭우: 2페이즈에서도 같은 길이 (fast 를 곱하지 않는다)
			velocity.x = move_toward(velocity.x, 0.0, 2000.0 * delta)
			_phase_step(delta, startup_len, (BARRAGE_WAVES - 1) * BARRAGE_WAVE_GAP + 0.3, 0.9, func() -> void:
				barrage_waves = barrage_layout(player.global_position.x if player else global_position.x)
				for w in barrage_waves.size():
					var xs: Array = barrage_waves[w]["xs"]
					_queue(w * BARRAGE_WAVE_GAP, func() -> void: _spawn_barrage_wave(xs))
				Sfx.play("ring_hum", -6.0, 0.05))
		State.RISE:
			velocity.x = 0.0
			if _timer <= 0.0:
				_set_state(State.STANCE)
				_timer = 0.6
		State.BROKEN:
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			if _timer <= 0.0:
				poise = 0.0
				poise_changed.emit(poise, max_poise)
				_poise_immune = poise_immune_after_broken
				_set_state(State.STANCE)
				_timer = 0.5
		State.FALLEN:
			velocity.x = 0.0
			_update_interactable()
	move_and_slide()
	# 공격 범위 예고는 예비동작 동안 판정이 덮을 자리를 따라간다
	if attack_phase == "startup" and _tel.is_showing():
		_tel.update_rect(melee_reach())


func _phase_step(delta: float, startup: float, active: float, recovery: float, on_active: Callable) -> void:
	match attack_phase:
		"startup":
			windup_progress = 1.0 - _timer / startup
			if _timer <= 0.0:
				attack_phase = "active"
				_timer = active
				active_len = active
				_tel.end()
				on_active.call()
		"active":
			if _timer <= 0.0:
				attack_phase = "recovery"
				# v1.1.1 2페이즈 '폭주': 연계가 예약돼 있으면 되돌림을 줄여 다음 공격이 더 빨리 붙는다
				if phase == 2 and _chain >= 0:
					recovery *= P2_CHAIN_RECOVERY
				_timer = recovery
				recovery_len = recovery
		"recovery":
			if _timer <= 0.0:
				_end_attack()


## 공격이 끝났다: 예약된 연계가 있으면 바로 잇고, 없으면 자세로 돌아가 잠깐 쉰다.
func _end_attack() -> void:
	if _chain >= 0 and player:
		var c: State = _chain as State
		_chain = -1
		var dx := player.global_position.x - global_position.x
		# 휘두르기 연계는 소녀가 아직 가까울 때만 (그사이 멀어졌으면 쉬었다가 새로 고른다)
		if not (c == State.SWEEP and absf(dx) > 420.0):
			# 연계 직전에 소녀 쪽으로 돈다 (등진 채 허공을 치지 않게)
			var want_face := 1 if dx > 0.0 else -1
			if want_face != facing and absf(dx) > face_deadzone:
				facing = want_face
				_face_hold = face_hold
			_set_state(State.STANCE)
			_timer = 0.15
			_start_attack(c)
			# 되돌려 베기 뒤에는 (2페이즈) 가끔 내려찍기까지 잇는다
			if c == State.SWEEP2:
				_chain = _pick_chain(c, absf(dx))
			return
	_set_state(State.STANCE)
	_timer = (0.7 + randf() * 0.3) if phase == 1 else (0.4 + randf() * 0.3) * P2_REST_MULT


## 지금 공격 단계의 진행도 (0→1). 그림이 세 박자 곡선(예비→타격→되돌림)을 그리는 기준.
func phase_progress() -> float:
	match attack_phase:
		"startup": return clampf(windup_progress, 0.0, 1.0)
		"active": return 1.0 - clampf(_timer / maxf(active_len, 0.001), 0.0, 1.0)
		"recovery": return 1.0 - clampf(_timer / maxf(recovery_len, 0.001), 0.0, 1.0)
	return 0.0


## 지금 상태의 진행도 (0→1; RISE 같은 단순 상태용).
func state_progress(length: float) -> float:
	return 1.0 - clampf(_timer / maxf(length, 0.001), 0.0, 1.0)


func _begin(st: State, startup: float) -> void:
	_set_state(st)
	if _punish_start:
		# 응징 공격: 예고 사각형(melee_reach)이 응징 판정을 쓰도록 먼저 켠다
		_punish_start = false
		punishing = true
	attack_phase = "startup"
	windup_progress = 0.0
	_timer = startup
	startup_len = startup
	# v1.1.0: 근접 공격(휘두르기·내려찍기·뿌리 벽)은 판정과 같은 사각형으로 공격 범위를 예고한다 (가시·손·씨앗·구슬은 각자의 예고)
	if st == State.WALL:
		_wall_run_from = Vector2(INF, INF)   # 새 돌진: 안개 문·벽 자리를 다시 잰다
	if st in [State.SWEEP, State.SWEEP2, State.STOMP, State.WALL]:
		_tel.show_rect(melee_reach(), st in RED_STATES, startup)


## 지금 근접 공격의 판정이 덮을 월드 사각형 (미끄러짐·돌진은 판정이 켜진 동안 쓸고 갈 구간 전체). 근접 판정이 없는 상태면 빈 사각형.
## 공격 범위 예고·이펙트·시험이 같은 값을 쓴다.
func melee_reach() -> Rect2:
	match state:
		State.SWEEP:
			return RangeTelegraph.box_world(hitbox, SWEEP_BOX, facing, RangeTelegraph.slide_distance(SWEEP_SLIDE, SWEEP_DECEL, SWEEP_ACTIVE),
				RangeTelegraph.slide_first(SWEEP_SLIDE, SWEEP_DECEL))
		State.SWEEP2:
			return RangeTelegraph.box_world(hitbox, SWEEP2_BOX, facing, RangeTelegraph.slide_distance(SWEEP2_SLIDE, SWEEP_DECEL, SWEEP_ACTIVE),
				RangeTelegraph.slide_first(SWEEP2_SLIDE, SWEEP_DECEL))
		State.STOMP:
			return RangeTelegraph.box_world(hitbox, PUNISH_STOMP_BOX if punishing else STOMP_BOX, 1)
		State.SPIKES:
			# 높은 자리 응징의 큰 가시: 소녀 발밑 가시가 솟아 덮을 기둥 (바닥 ~ 가시 끝, 판정 폭). 보통 가시는 각자의 바닥 예고.
			if not spike_heights.is_empty() and not spike_marks.is_empty():
				var h: float = spike_heights[0]
				return Rect2(float(spike_marks[0]) - RootSpike.WIDTH / 2.0, ground_y - h, RootSpike.WIDTH, h)
		State.WALL:
			var from := global_position if attack_phase == "startup" else _wall_from
			var r := RangeTelegraph.box_world(hitbox, WALL_BOX, facing)
			r.position += from - global_position
			var step := WALL_SPEED / 60.0   # 판정이 켜지는 틱에 한 걸음 나간 뒤부터 겹침을 본다
			var travel := _wall_travel(from)
			var a := Rect2(r.position + Vector2(minf(step, travel) * facing, 0.0), r.size)
			return a.merge(Rect2(r.position + Vector2(travel * facing, 0.0), r.size))
	return Rect2()


## 뿌리 벽 돌진이 갈 수 있는 거리: 판정이 마지막으로 닿을 때까지 (WALL_SPEED × (판정 길이 - 한 틱)),
## 그 사이에 벽(안개 문·지형 벽)이 있으면 몸이 벽에 닿는 데까지.
## 한 번 잰 값을 출발 자리·방향이 같으면 다시 쓴다 (예고가 매 틱 부르므로 — 매 프레임 광선 질의를 새로 만들지 않게, 아이폰)
func _wall_travel(from: Vector2) -> float:
	if facing == _wall_run_face and from.distance_squared_to(_wall_run_from) < 1.0:
		return _wall_run
	var run := WALL_SPEED * (WALL_ACTIVE - 1.0 / 60.0)
	var half := 60.0
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs and cs.shape:
		half = cs.shape.get_rect().size.x * 0.5 * absf(cs.global_scale.x)
	var y := from.y - 60.0
	var space := get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(Vector2(from.x, y), Vector2(from.x + facing * (run + half + 4.0), y), collision_mask)
	ray.exclude = [get_rid()]
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		var c = hit.get("collider")
		if not (c is Platform and (c as Platform).one_way):
			run = minf(run, maxf(absf(float(hit["position"].x) - from.x) - half, 0.0))
	_wall_run_from = from
	_wall_run_face = facing
	_wall_run = run
	return run


# ---------- 예약된 일 ----------

func _queue(delay: float, cb: Callable) -> void:
	_events.append([_clock + delay, cb])


func _tick_events() -> void:
	if _events.is_empty():
		return
	var due: Array = []
	var rest: Array = []
	for e in _events:
		if e[0] <= _clock:
			due.append(e)
		else:
			rest.append(e)
	_events = rest
	for e in due:
		if state not in [State.FALLEN, State.PURIFIED, State.WAIT]:
			e[1].call()


# ---------- 패턴 고르기 ----------

## 거리별 후보에서 직전 패턴을 빼고 무게로 하나 고른 뒤, 확률로 연계를 예약한다.
func _choose(dist: float) -> void:
	var cands: Array = []   # [State, weight]
	# 공격을 고르는 순간에는 데드존 없이 소녀 쪽으로 돌아선다 (몸 안·등 뒤에 붙어 있으면 돌지 않아 안전지대가 됐다)
	if player and absf(player.global_position.x - global_position.x) > 4.0:
		var want_face := 1 if player.global_position.x > global_position.x else -1
		if want_face != facing:
			facing = want_face
			_face_hold = face_hold
	if crowd.ready():
		# 맞딜 방지 (v1.1.0): 몸에 붙어 버티는 소녀에게 지팡이 내려찍기 (붉은 예고·가드 불가 — 양쪽으로 충격파도 달린다)
		crowd.consume()
		_chain = -1
		if player and player.is_on_floor() and absf(player.global_position.x - global_position.x) <= PUNISH_STOMP_REACH:
			_punish_start = true
			_start_attack(State.STOMP)
			_stomps_left = maxi(int(punish_stomps) - 1, 0)
		else:
			# 떠 있거나 지팡이 끝 거리: 소녀 밑을 따라오는 큰 뿌리 가시 둘 (뿌리 창)
			_lance_next = true
			_start_attack(State.SPIKES)
			punishing = true
		return
	if perch.ready():
		# 높은 자리 응징 (v1.1.0 맞딜 검수): 소녀 발밑에서 가지 높이까지 솟는 큰 뿌리 가시 (주황 기둥 예고 = 판정, 가드 가능)
		perch.consume()
		_chain = -1
		_perch_spikes = true
		_start_attack(State.SPIKES)
		punishing = true
		return
	if dist < 330.0:
		cands = [[State.SWEEP, 50], [State.HAND, 20], [State.RING, 15], [State.SPIKES, 10]]
		if phase == 2:
			cands.append([State.STOMP, 20])
	elif dist < 700.0:
		cands = [[State.SPIKES, 30], [State.ORBS, 20], [State.HAND, 20], [State.SEEDS, 20], [State.RING, 10], [State.BARRAGE, 14]]
		if phase == 2:
			cands.append([State.STOMP, 12])
	else:
		cands = [[State.SPIKES, 25], [State.ORBS, 25], [State.SEEDS, 25], [State.HAND, 10], [State.BARRAGE, 22]]
		if phase == 2:
			cands.append([State.WALL, 30])
	# v1.1.1: 뿌리 촉수가 막 솟으려는 동안(맵 패턴을 건 뒤 MAP_BARRAGE_GAP 초)에는 씨앗 폭우를 고르지 않는다 (둘이 겹치면 피할 틈이 사라진다)
	if _clock - _map_struck_at < MAP_BARRAGE_GAP:
		cands = cands.filter(func(c: Array) -> bool: return c[0] != State.BARRAGE)
	var pick := _weighted_pick(cands)
	_chain = _pick_chain(pick, dist)
	_start_attack(pick)


func _weighted_pick(cands: Array) -> State:
	var total := 0
	for c in cands:
		if c[0] != _last_attack:
			total += c[1]
	var r := randf() * total
	for c in cands:
		if c[0] == _last_attack:
			continue
		r -= c[1]
		if r <= 0.0:
			return c[0]
	return cands[0][0] if cands[0][0] != _last_attack else cands[1][0]


## 연계 표: (지금 패턴 → 다음 패턴, 확률). 2페이즈가 더 자주 잇는다.
## v1.1.1 2페이즈 '폭주': 휘두르기 → 되돌려 베기 0.5 → 0.6, 되돌려 베기가 아니면 0.25 확률로 휘두르기 → 뿌리 가시(새 연계),
## 가시 → 달빛 고리 0.25 → 0.35, 구슬 → 가시 0.3 → 0.4, 되돌려 베기 → 내려찍기 0.3 → 0.45. 1페이즈는 그대로.
func _pick_chain(st: State, dist: float) -> int:
	var p2 := phase == 2
	match st:
		State.SEEDS:
			return State.HAND if randf() < (0.6 if p2 else 0.35) else -1
		State.SWEEP:
			if p2:
				var r := randf()
				if r < 0.6:
					return State.SWEEP2
				return State.SPIKES if r < 0.85 else -1
			return State.SWEEP2 if randf() < 0.25 else -1
		State.SPIKES:
			if p2 and randf() < 0.35:
				return State.RING
			return State.ORBS if (not p2 and randf() < 0.2) else -1
		State.ORBS:
			return State.SPIKES if (p2 and randf() < 0.4) else -1
		State.HAND:
			# 뿌리 손 → 휘두르기 연계는 없앴다: 손에 잡혀 던져진 뒤 경직(0.4초) 동안 이어지는 휘두르기를 피할 수 없었다 (통합 검토)
			return -1
		State.SWEEP2:
			return State.STOMP if (p2 and randf() < 0.45) else -1
	return -1


## 패턴 하나를 시작한다 (예고 자리·붉은 빛·예고 글자·예비 길이).
func _start_attack(st: State) -> void:
	var fast := 0.7 if phase == 2 else 1.0
	_lance = _lance_next and st == State.SPIKES   # 뿌리 창은 맞딜 응징으로 고른 가시만 (그 밖의 새 공격은 늘 끈다)
	_lance_next = false
	_last_attack = st
	_red = st in RED_STATES
	match st:
		State.SPIKES:
			_mark_spikes()
			_begin(st, 0.9 * fast)
			if not spike_heights.is_empty():
				_tel.show_rect(melee_reach(), false, startup_len)   # 큰 가시: 공격 범위 예고 = 소녀 발밑 가시의 판정 기둥
		State.SWEEP:
			_begin(st, 0.5 * fast)
		State.SWEEP2:
			# 휘두르기 바로 뒤에 붙지만 예고는 기준(0.45초, 2페이즈 0.7배)을 지킨다
			_begin(st, 0.45 * fast)
		State.ORBS:
			_begin(st, 0.8 * fast)
		State.WALL:
			telegraph.emit("wall")
			_begin(st, 1.1)
		State.HAND:
			telegraph.emit("hand")
			hand_targets.clear()
			_track_hands()
			_begin(st, 0.8 * fast)
		State.SEEDS:
			telegraph.emit("seeds")
			_begin(st, 0.7 * fast)
		State.RING:
			telegraph.emit("ring")
			_begin(st, 0.7 * fast)
		State.STOMP:
			telegraph.emit("stomp")
			_begin(st, 1.0)
		State.BARRAGE:
			# v1.1.1 씨앗 폭우: 2페이즈에서도 같은 예비 (fast 를 곱하지 않는다)
			telegraph.emit("barrage")
			barrage_waves.clear()
			_begin(st, BARRAGE_STARTUP)
		_:
			_begin(State.SWEEP, 0.5 * fast)


## 시험·스크린샷용: 이름으로 패턴을 바로 건다 ("SPIKES", "HAND", ...).
## 손으로 패턴을 거는 동안은 맵 패턴(뿌리 촉수)이 저절로 나오지 않는다 (manual_control — 시험이 촉수에 흔들리지 않게).
func force_pattern(name: String) -> void:
	manual_control = true
	_chain = -1
	var idx := State.keys().find(name)
	if idx < 0 or idx not in ATTACK_STATES:
		return
	_start_attack(idx as State)


## BossRoom 이 예고 글자로 띄울 문구 (가드 불가는 붉은 빛으로 알리고 글자는 공격 이름만).
func telegraph_label(kind: String) -> String:
	match kind:
		"wall": return "뿌리 벽!"
		"hand": return "뿌리 손!"
		"seeds": return "씨앗 비!"
		"ring": return "달빛 고리!"
		"stomp": return "내려찍기!"
		"tentacles": return "뿌리 촉수!"
		"barrage": return "씨앗 폭우!"
	return ""


# ---------- 패턴 실행 ----------

func _mark_spikes() -> void:
	var perch_mode := _perch_spikes
	_perch_spikes = false
	_clear_marks()
	if player == null:
		return
	var px := player.global_position.x
	if _lance:
		# 맞딜 응징 '뿌리 창': 소녀 발밑 + 달리는 쪽(서 있으면 보스 반대쪽) 앞에 큰 가시 둘 (예비 60% 까지 따라간다 — _track_lance)
		spike_marks = [px, px]
		spike_delays = [0.0, 0.08]
		spike_heights = [LANCE_HEIGHT, LANCE_HEIGHT]
		_track_lance()
		return
	if perch_mode:
		# 높은 자리 응징: 소녀 발밑(2페이즈는 소녀가 달리는 쪽, 서 있으면 보스 반대쪽에 하나 더)에 소녀 발 높이 + 150 까지 솟는 큰 가시
		var h := clampf(PerchMeter.height_of(player, ground_y) + PERCH_SPIKE_OVER, RootSpike.HEIGHT, PERCH_SPIKE_MAX)
		spike_marks = [px]
		spike_delays = [0.0]
		spike_heights = [h]
		if phase == 2:
			var lead := signf(player.velocity.x) if absf(player.velocity.x) > 40.0 else signf(px - global_position.x)
			if lead == 0.0:
				lead = float(-facing)
			spike_marks.append(px + lead * PERCH_SPIKE_GAP)
			spike_delays.append(0.08)
			spike_heights.append(h)
		for i in spike_marks.size():
			spike_marks[i] = _clamp_x(spike_marks[i])
		return
	if phase == 1:
		spike_marks = [px, px + facing * 220.0]
		spike_delays = [0.0, 0.08]
	else:
		_spike_wave = not _spike_wave
		if _spike_wave:
			# 물결: 뿌리지기 앞에서 소녀 쪽으로 차례로 솟는 6개
			for i in 6:
				spike_marks.append(global_position.x + facing * (200.0 + 190.0 * i))
				spike_delays.append(i * 0.09)
		else:
			spike_marks = [px - 260.0, px, px + 260.0, px + player.velocity.x * 0.6]
			spike_delays = [0.0, 0.06, 0.12, 0.18]
	for i in spike_marks.size():
		spike_marks[i] = _clamp_x(spike_marks[i])


## 뿌리 창 자리: 소녀 발밑과 달리는 쪽(서 있으면 보스 반대쪽) LANCE_GAP 앞
func _track_lance() -> void:
	if player == null or spike_marks.size() < 2:
		return
	var px := player.global_position.x
	var lead := signf(player.velocity.x) if absf(player.velocity.x) > 40.0 else signf(px - global_position.x)
	if lead == 0.0:
		lead = float(-facing)
	spike_marks[0] = _clamp_x(px)
	spike_marks[1] = _clamp_x(px + lead * LANCE_GAP)


func _clamp_x(x: float) -> float:
	if arena.size.x <= 0.0:
		return x
	return clampf(x, arena.position.x + 60.0, arena.end.x - 60.0)


func _raise_spikes() -> void:
	if _lance and player:
		# 뿌리 창의 뒤따르는 가시: 지금 소녀 자리에 LANCE_FOLLOW 초 뒤 (스스로 기둥 예고)
		spike_marks.append(_clamp_x(player.global_position.x))
		spike_delays.append(LANCE_FOLLOW)
		spike_heights.append(LANCE_HEIGHT)
	for i in spike_marks.size():
		var sp: RootSpike = SPIKE.instantiate()
		sp.damage = _dmg(spike_damage)
		sp.delay = spike_delays[i] if i < spike_delays.size() else 0.0
		if i < spike_heights.size():
			sp.spike_height = spike_heights[i]
		get_parent().add_child(sp)
		sp.global_position = Vector2(spike_marks[i], ground_y)
		sp.launch(Vector2.UP, self, false)
	Sfx.play("root_rise", 0.0, 0.08)
	_clear_marks()


func _clear_marks() -> void:
	spike_marks.clear()
	spike_delays.clear()
	spike_heights.clear()


## 뿌리 손 자리: 예비 60% 까지 소녀를 따라간다 (2페이즈는 두 번째 손이 소녀가 달리는 쪽 앞에)
func _track_hands() -> void:
	if player == null:
		return
	var px := _clamp_x(player.global_position.x)
	if hand_targets.is_empty():
		hand_targets = [px]
	else:
		hand_targets[0] = px
	if phase == 2:
		var lead := signf(player.velocity.x) if absf(player.velocity.x) > 40.0 else float(-facing)
		var second := _clamp_x(px + lead * 240.0)
		if hand_targets.size() < 2:
			hand_targets.append(second)
		else:
			hand_targets[1] = second


func _spawn_orb(offset: float) -> void:
	var o: RootOrb = ORB.instantiate()
	o.mode = RootOrb.Mode.HOMING
	o.speed = 380.0 if phase == 1 else 460.0
	o.damage = _dmg(orb_damage)
	o.lifetime = 4.5
	o.homing = 1.6 if phase == 1 else 2.0
	o.radius = 36.0
	o.ground_y = ground_y   # 지형은 뚫고 바닥 아래로 가면 사라진다 (v1.1.0)
	get_parent().add_child(o)
	o.global_position = orb_origin() + Vector2(0.0, offset * 30.0)   # 예고 고리(반지름 80) 안에서 생긴다
	var dir := Vector2(facing, -0.15 + offset * 0.22).normalized()
	o.launch(dir, self)


## 휘두르기(SWEEP/SWEEP2) 판정이 덮는 자리 (발밑 기준, 바라보는 쪽 = +x): 판정 상자 + 판정이 켜진 동안 앞으로 미끄러지는 거리.
## v1.1.0: 공격 범위 예고(RangeTelegraph)·이펙트와 같은 사각형 (melee_reach 의 발밑 기준판).
func sweep_reach(st: State) -> Rect2:
	var two := st == State.SWEEP2
	var box: Rect2 = SWEEP2_BOX if two else SWEEP_BOX
	var slide := RangeTelegraph.slide_distance(SWEEP2_SLIDE if two else SWEEP_SLIDE, SWEEP_DECEL, SWEEP_ACTIVE)
	var hy: float = hitbox.position.y if hitbox else -60.0
	return Rect2(box.position.x, hy + box.position.y, box.size.x + slide, box.size.y)


## 구슬이 생기는 자리 = 그림의 지팡이 머리 (예고 고리가 뜨는 곳). 그림이 없으면 머리 위 앞쪽.
func orb_origin() -> Vector2:
	var vis := get_node_or_null("Sprite")
	if vis and vis.has_method("head_world"):
		return vis.head_world()
	return global_position + Vector2(facing * 120.0, -460.0)


func _spawn_seed(x: float) -> void:
	var s: RootSeed = SEED.instantiate()
	s.damage = _dmg(seed_damage)
	s.ground_y = ground_y
	s.source = self
	get_parent().add_child(s)
	s.global_position = Vector2(_clamp_x(x), ground_y - RootSeed.FALL_HEIGHT)
	Sfx.play("seed_fall", -8.0, 0.2)


func _spawn_shockwaves() -> void:
	for d in [-1, 1]:
		var w: RootShockwave = SHOCKWAVE.instantiate()
		w.damage = _dmg(stomp_wave_damage)
		w.dir = d
		w.source = self
		w.min_x = arena.position.x + 20.0 if arena.size.x > 0.0 else -INF
		w.max_x = arena.end.x - 20.0 if arena.size.x > 0.0 else INF
		get_parent().add_child(w)
		w.global_position = Vector2(global_position.x + d * 90.0, ground_y)


# ---------- v1.1.1 새 패턴 1: 뿌리 촉수 (맵 패턴) ----------

## 맵 패턴 시계가 흐르는가: 싸우는 동안(자세·공격)만. 시험이 자세 타이머를 붙잡아 둔 동안(_timer ≥ 20)이나
## 패턴을 손으로 거는 동안(manual_control)은 멈춘다. 무너짐·다시 일어섬·등장에는 흐르지 않는다.
func _map_clock_runs() -> bool:
	return not manual_control and _timer < 20.0 and (state == State.STANCE or state in ATTACK_STATES)


## 지금 걸어도 되는가: 씨앗 폭우·뿌리 벽 돌진(싸움터 전체를 덮는 공격)과 맞딜 응징 동안은 끝날 때까지 미룬다.
func _map_can_fire() -> bool:
	return state not in [State.BARRAGE, State.WALL] and not punishing


## 지금 페이즈의 촉수 줄 수 (1페이즈 2, 2페이즈 4)
func map_count() -> int:
	return 2 if phase == 1 else 4


## 뿌리 촉수 자리 n 줄 (소녀 x = px). 줄마다 {"x": 밑동 x, "lean": 기운 쪽(±1), "angle": 땅과 이루는 각(rad), "rot": 노드 회전,
## "length": 길이, "center": 서 있는 소녀가 맞는 땅 폭의 가운데}. 맨 앞 줄의 땅 폭 가운데가 소녀 자리.
## 서 있는 소녀(높이 BODY_H, 반폭 BODY_HALF)가 맞는 땅 폭: 오른쪽으로 기울면 [x - h·sinθ - 반폭, x + h/sinθ + 높이/tanθ + 반폭]
## (h = 띠 반폭, 밑동 끝은 띠에 수직이라 왼쪽 위 모서리가 h·sinθ 만큼 뒤로 나온다).
func map_layout(n: int, px: float) -> Array:
	var a0 := arena.position.x if arena.size.x > 0.0 else px - 1340.0
	var a1 := arena.end.x if arena.size.x > 0.0 else px + 1340.0
	var span := a1 - a0
	var cell := span / float(n)
	var top := (arena.position.y if arena.size.y > 0.0 else ground_y - 1000.0) - MAP_TOP_OVER
	var h := RootTentacle.WIDTH / 2.0
	var lean := 1 if randf() < 0.5 else -1
	var out: Array = []
	for i in n:
		var c := a0 + fposmod(clampf(px, a0, a1) - a0 + i * cell, span)
		var th := deg_to_rad(randf_range(MAP_ANGLE.x, MAP_ANGLE.y))
		var off := (h / sin(th) + BODY_H / tan(th) - h * sin(th)) / 2.0
		var s := lean if i % 2 == 0 else -lean
		var x0 := c - s * off
		var run := (a1 + 60.0 - x0) if s > 0 else (x0 - (a0 - 60.0))
		if run < MAP_MIN_RUN:
			s = -s
			x0 = c - s * off
			run = (a1 + 60.0 - x0) if s > 0 else (x0 - (a0 - 60.0))
		var length := minf(minf(run / cos(th), (ground_y - top) / sin(th)), MAP_MAX_LEN)
		out.append({"x": x0, "lean": s, "angle": th, "rot": s * (PI / 2.0 - th), "length": length, "center": c})
	return out


## 서 있는 소녀가 맞는 땅 폭 (월드 x 구간) — 시험·자리 계산 확인용
static func map_footprint(e: Dictionary) -> Vector2:
	var th: float = e["angle"]
	var h := RootTentacle.WIDTH / 2.0
	var near := h * sin(th) + BODY_HALF
	var far := h / sin(th) + BODY_H / tan(th) + BODY_HALF
	var x0: float = e["x"]
	return Vector2(x0 - near, x0 + far) if int(e["lean"]) > 0 else Vector2(x0 - far, x0 + near)


## 맵 패턴을 건다: 붉은 띠 예고(MAP_TELEGRAPH, 2페이즈 MAP_TELEGRAPH_P2) 뒤 줄마다 MAP_STAGGER 씩 차례로 솟는다.
func _map_strike() -> void:
	var gap := MAP_INTERVAL if phase == 1 else MAP_INTERVAL_P2
	_map_timer = randf_range(gap.x, gap.y)
	if player == null:
		return
	var tel := MAP_TELEGRAPH if phase == 1 else MAP_TELEGRAPH_P2
	_map_struck_at = _clock
	var lay := map_layout(map_count(), player.global_position.x)
	for i in lay.size():
		var e: Dictionary = lay[i]
		var t: RootTentacle = TENTACLE.instantiate()
		t.damage = _dmg(tentacle_damage)
		t.delay = tel + i * MAP_STAGGER
		t.length = e["length"]
		t.rotation = e["rot"]
		t.source = self
		get_parent().add_child(t)
		t.global_position = Vector2(float(e["x"]), ground_y)
	telegraph.emit("tentacles")
	Sfx.play("end_rumble", -3.0, 0.05)
	Juice.shake(4.0)


## 시험·스크린샷용: 맵 패턴을 지금 건다 (시계와 상관없이)
func force_map_pattern() -> void:
	_map_strike()


# ---------- v1.1.1 새 패턴 2: 씨앗 폭우 ----------

## 씨앗 폭우의 물결 자리 (소녀 x = px): [{"gap": 틈 가운데, "xs": [씨앗 x...]}, ...] — 맨 위 상수 설명 참고.
func barrage_layout(px: float) -> Array:
	var a0 := arena.position.x if arena.size.x > 0.0 else px - 1340.0
	var a1 := arena.end.x if arena.size.x > 0.0 else px + 1340.0
	var lo := a0 + BARRAGE_EDGE
	var hi := a1 - BARRAGE_EDGE
	var side := 1 if randf() < 0.5 else -1
	var g := px + side * randf_range(BARRAGE_FIRST.x, BARRAGE_FIRST.y)
	if g < lo or g > hi:
		side = -side
		g = px + side * randf_range(BARRAGE_FIRST.x, BARRAGE_FIRST.y)
	g = clampf(g, lo, hi)
	var waves: Array = []
	for w in BARRAGE_WAVES:
		if w > 0:
			var step := randf_range(BARRAGE_STEP.x, BARRAGE_STEP.y)
			if g + side * step < lo or g + side * step > hi:
				side = -side
			g = clampf(g + side * step, lo, hi)
		var xs: Array = []
		var x := a0 + BARRAGE_ROW_MARGIN + (BARRAGE_SPACING * 0.5 if w % 2 == 1 else 0.0)
		while x <= a1 - BARRAGE_ROW_MARGIN:
			if absf(x - g) >= BARRAGE_GAP_HALF:
				xs.append(x)
			x += BARRAGE_SPACING
		waves.append({"gap": g, "xs": xs})
	return waves


## 씨앗 폭우 한 물결: 줄의 씨앗이 모두 함께 떠서(BARRAGE_HOVER) 주황 점 예고를 보이다가 떨어진다
func _spawn_barrage_wave(xs: Array) -> void:
	var dmg := seed_damage * (atk_factor() if BARRAGE_PHASE2_ATK else extra("atk"))
	for x in xs:
		var s: RootSeed = SEED.instantiate()
		s.damage = dmg
		s.ground_y = ground_y
		s.source = self
		s.delay = BARRAGE_HOVER
		get_parent().add_child(s)
		s.global_position = Vector2(float(x), ground_y - RootSeed.FALL_HEIGHT)
	Sfx.play("seed_fall", -3.0, 0.2)


# ---------- v1.1.1 대사 ----------

## 싸움 전 대화를 걸 때인가: 처음 마주칠 때만(INTRO_FLAG), 보스 러시가 아닐 때. intro_talk_mode 0 이면
## 이 방이 실제 게임 장면일 때만 (시험이 방을 자식으로 놓거나 --bosstest 면 건너뛴다).
func _intro_talk_due() -> bool:
	if intro_talk_mode < 0 or BossRush.active or Progress.has(INTRO_FLAG):
		return false
	if _intro_lines().is_empty():
		return false
	if intro_talk_mode > 0:
		return true
	var room := get_parent()
	return room != null and room == get_tree().current_scene and not ("--bosstest" in OS.get_cmdline_user_args())


func _lines_data() -> Dictionary:
	if _lines_cache.is_empty():
		_lines_cache = DialogueData.load_dialogue(DIALOGUE_PATH)
	return _lines_cache


func _intro_lines() -> Array:
	var out: Array = []
	var speaker := str(_lines_data().get("speaker", "뿌리지기"))
	for l in _lines_data().get("intro", []):
		if l is Dictionary:
			var d: Dictionary = (l as Dictionary).duplicate()
			if not d.has("speaker"):
				d["speaker"] = speaker
			out.append(d)
	return out


func _start_intro_talk() -> void:
	if not is_inside_tree() or state != State.INTRO:
		_talking = false
		return
	var lines := _intro_lines()
	var cam := player.get_node_or_null("Camera2D") if player else null
	if cam and cam.has_method("frame_with"):
		cam.frame_with(self, 120.0)   # 말하는 동안 소녀와 뿌리지기를 함께 보여 준다
	Dialogue.start(lines, func() -> void:
		_talking = false
		if cam and is_instance_valid(cam) and cam.has_method("frame_with"):
			cam.frame_with(self, 0.2, 0.0, 0.9))
	if not Dialogue.is_active():
		_talking = false


## 싸우는 동안 대사가 뜨는가 (보스 러시에는 없다)
func lines_enabled() -> bool:
	return _speech != null and not BossRush.active


## 키(battle 의 이름)에 맞는 한 마디를 위쪽 자막으로. 같은 키는 한 싸움에 한 번 (회복은 HEAL_LINES_MAX 번, 차례로).
## force: 지금 떠 있는 대사를 밀어내고 바로 (다시 일어섬·쓰러짐)
func _say(key: String, force := false) -> void:
	if not lines_enabled():
		return
	var idx := 0
	if key == "heal":
		idx = _heal_said
	elif _said.has(key):
		return
	var arr: Array = (_lines_data().get("battle", {}) as Dictionary).get(key, [])
	if arr.is_empty():
		return
	_said[key] = true
	var line = arr[mini(idx, arr.size() - 1)]
	var text := str(line.get("text", "")) if line is Dictionary else str(line)
	if text == "":
		return
	_speech.speaker = str(_lines_data().get("speaker", "뿌리지기"))
	_speech.say(text, clampf(1.8 + text.length() * 0.06, 3.2, 5.2), force)


## delay 초 뒤에 _say (예약된 공격과 따로 — 무너짐이 거둬 가지 않는다)
func _say_later(key: String, delay: float) -> void:
	_pending_lines.append([_clock + delay, key])


func _tick_lines() -> void:
	if _pending_lines.is_empty():
		return
	var rest: Array = []
	for e in _pending_lines:
		if e[0] <= _clock:
			if state not in [State.FALLEN, State.PURIFIED, State.WAIT]:
				_say(e[1])
		else:
			rest.append(e)
	_pending_lines = rest


## 체력이 정해진 비율 아래로 처음 내려가면 그 대사 (HP_LINES)
func _check_hp_lines() -> void:
	if max_hp <= 0.0:
		return
	var r := hp / max_hp
	for e in HP_LINES:
		if r <= float(e[0]) and not _said.has(e[1]):
			_say(e[1])
			return


func _on_player_healed() -> void:
	if state in [State.WAIT, State.INTRO, State.FALLEN, State.PURIFIED] or _heal_said >= HEAL_LINES_MAX:
		return
	if _clock - _heal_said_at < HEAL_LINE_GAP:
		return
	_say("heal")
	_heal_said += 1
	_heal_said_at = _clock


func _on_player_hp_changed(php: float, pmax: float) -> void:
	if state in [State.WAIT, State.INTRO, State.FALLEN, State.PURIFIED] or pmax <= 0.0:
		return
	if php > 0.0 and php / pmax < LOW_HP_LINE:
		_say("low")


func _on_player_died() -> void:
	if state in [State.WAIT, State.FALLEN, State.PURIFIED]:
		return
	_say("player_down", true)


## 떠 있는 패턴 효과(손·구슬·씨앗·충격파·가시)를 모두 치운다 (쓰러짐·2페이즈 전환·리셋).
func _clear_effects() -> void:
	hand_targets.clear()
	_events.clear()
	for n in get_tree().get_nodes_in_group("root_effect"):
		if is_instance_valid(n):
			n.queue_free()


# ---------- 맞기 ----------

func receive_hit(hit: HitData, _hb: Hurtbox) -> String:
	if state in [State.WAIT, State.INTRO, State.FALLEN, State.PURIFIED, State.RISE]:
		return "ignored"
	# 낙하 공격 감쇠 (4초 창 — PlungeDecay)
	hit = plunge_decay.apply(hit)
	_flash = 1.0
	var dmg := hit.damage * (broken_damage_multiplier if state == State.BROKEN else 1.0)
	hp = maxf(hp - dmg, 0.0)
	hp_changed.emit(hp, max_hp)
	# 슈퍼아머·무너짐 뒤 면역은 보통 공격에만 (저스트 가드로 되받은 구슬 등은 기술의 보상이라 그대로)
	if _poise_immune <= 0.0 or hit.reflected:
		var pm := attack_poise_multiplier if (not hit.reflected and state in ATTACK_STATES and attack_phase in ["startup", "active"]) else 1.0
		if punishing and not hit.reflected:
			pm = 0.0   # 맞딜 응징(내려찍기)은 끝날 때까지 두들겨 무너뜨릴 수 없다 — 구르기로 빠져야 한다
		_add_poise(hit.poise * pm)
	if hp <= 0.0:
		_fall()
		return "hit"
	_check_hp_lines()
	if phase == 1 and hp <= max_hp * 0.5:
		# 무너졌다 다시 일어선다 (여기서 주제곡이 터진다 — 13단계)
		phase = 2
		hitbox.deactivate()
		_clear_marks()
		_clear_effects()
		_chain = -1
		_red = false
		# 흐트러짐을 비운다: 무너진 채로 넘어와도 일어서자마자 한 대에 또 무너지지 않게 (RISE 동안은 줄지 않는다)
		poise = 0.0
		_poise_hold = 0.0
		poise_changed.emit(poise, max_poise)
		_set_state(State.RISE)
		_timer = rise_len
		# v1.1.1: 다시 일어선 뒤 곧 4줄 맵 패턴 (폭주의 시작)
		_map_timer = MAP_AFTER_RISE
		phase_changed.emit(2)
		telegraph.emit("rise")
		_say("rise", true)
		Juice.hitstop(0.2, 0.02)
		Juice.shake(14.0)
		return "hit"
	if poise >= max_poise and state != State.BROKEN:
		_break()
		Juice.hitstop(0.1, 0.05)
		Juice.shake(8.0)
	return "hit"


func on_just_guarded(_by: Player, amount: float) -> void:
	_flash = 1.0
	_add_poise(amount)
	if poise >= max_poise and state != State.BROKEN:
		_break()
	elif state == State.SWEEP or state == State.SWEEP2:
		# 지팡이가 튕겼다: 그림만 짧게 휘청인다 (공격 길이·판정은 그대로)
		anim_hint = "stagger"
		_hint_timer = stagger_len
		stagger = 1.0


## 무너진다: 지금 공격과 예약해 둔 일(남은 씨앗·구슬·둘째 충격파)을 모두 거둔다 — 몰아칠 틈을 방해하지 않게.
## 이미 떠 있는 효과(떨어지는 씨앗 등)는 그대로 끝까지 간다.
func _break() -> void:
	hitbox.deactivate()
	_chain = -1
	_red = false
	_events.clear()
	hand_targets.clear()
	_clear_marks()
	_set_state(State.BROKEN)
	_timer = broken_time


func _add_poise(amount: float) -> void:
	if amount <= 0.0:
		return
	poise = minf(poise + amount, max_poise)
	_poise_hold = 2.5
	poise_changed.emit(poise, max_poise)


func _fall() -> void:
	hitbox.deactivate()
	_unregister()
	_clear_marks()
	_clear_effects()
	_chain = -1
	_red = false
	_set_state(State.FALLEN)
	Juice.hitstop(0.2, 0.02)
	Juice.shake(12.0)
	_pending_lines.clear()
	_say("fallen", true)
	fallen.emit()


func _update_interactable() -> void:
	if player == null:
		return
	var near := absf(player.global_position.x - global_position.x) < 240.0 and absf(player.global_position.y - global_position.y) < 220.0
	if near and not _registered:
		player.register_interactable(self)
		_registered = true
	elif not near and _registered:
		_unregister()


func _unregister() -> void:
	if _registered and player:
		player.unregister_interactable(self)
	_registered = false


func interact(by: Player) -> void:
	if state == State.FALLEN:
		by.start_purify(self)


func purified_by(_by: Player) -> void:
	_unregister()
	_set_state(State.PURIFIED)
	purified.emit()


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	if debug_log:
		print("[뿌리지기] %s → %s" % [State.keys()[state], State.keys()[new_state]])
	state = new_state
	anim_hint = ""
	_hint_timer = 0.0
	punishing = false
	_stomps_left = 0
	_slams = 0
	if new_state != State.SPIKES:
		_lance = false
	if new_state not in ATTACK_STATES:
		attack_phase = ""
	if _tel:
		_tel.end()   # 공격이 바뀌거나 끊기면 예고는 걷힌다 (새 근접 공격은 _begin 이 다시 띄운다)
	state_changed.emit(new_state)


func flash_amount() -> float:
	return _flash


## 가드 불가 예고 중 (그림이 붉게 깜빡인다)
func is_red() -> bool:
	return _red and state in RED_STATES and attack_phase == "startup"


## 지금 패턴이 가드 가능한가 (그림이 예고 색을 고른다: 가드 가능 = 주황빛, 불가 = 진한 붉은색)
func is_guardable_pattern() -> bool:
	return state not in RED_STATES


func is_ground() -> bool:
	return true


func state_name() -> String:
	return State.keys()[state]

extends CharacterBody2D
class_name Player
## 셀레니아. 이동·점프·구르기(3단계) + 전투(5단계).
## 손맛에 관한 숫자는 모두 아래 @export 에 모여 있다. 느낌 피드백이 오면 여기만 고친다.
## 2026-10-18 기획자 요청: 강공격을 없애고 그 자리(R2/RT, K)에 영혼 기술. 처음부터 '씨앗' 영혼(넓은 베기)이 있다.
##   낙하 공격(공중에서 ↓ + 약공격, 또는 터치 '낙하' 버튼 = 동작 plunge), 하단 점프(한쪽 방향 발판 위에서 ↓ + 점프), 가드 보호막·막기 소리.
## 2026-10-19 기획자 요청: 바람·빛 영혼 기술 파격 상향(피해 ×4, 크기 2배쯤, 쿨 5/7초), 낙하 공격 버튼, 영혼 이름·색·쿨다운 조회 함수(HUD·터치가 쓴다).
## 2026-10-19 이펙트 리뉴얼 F1: 바람 = 날아가는 초승달 검기(WindCrescent, 판정은 보이는 초승달 머리 = 세로로 긴 사각형),
##   빛 = 레이저(SoulLaser: 손에 0.12초 모았다가 벽까지 곧게, 빛줄기 안의 적을 한 번씩 모두 맞힌다).
##   피해·흐트러짐·쿨다운·사거리는 그대로. 맞힌 자리의 불꽃(hit_spark)은 여기서 띄운다 (Fx).
## v1.1.0 (기획자 요청 2·3·6·7·10·11·12, 15·17·18 의 소녀 쪽):
##   스태미너 = 가드 게이지(초록 막대 하나). 공격 1·2·3타가 10/12/15 를 쓰고, 모자라면 그 공격을 시작하지 않는다.
##   공격·영혼 기술·낙하 공격·가드 중과 3타 후딜레이 동안은 자연 회복이 없고, 벗어난 뒤 0.5초(바람·빛은 쏜 뒤 0.7초) 기다렸다가 찬다.
##   3타 뒤 0.35초 동안은 공격·영혼 기술·낙하 공격을 받지 않는다(가드·구르기로 끊는 것은 된다). 이 멈춤은 소녀만의 타이머다 (게임 전체 시간은 그대로).
##   일반 공격 사거리 225 → 270 (판정 끝까지), 칼자국 이펙트도 판정 끝까지·청록. 씨앗 40·앞 374, 바람 120, 빛 95.2.
##   새순 단계(Progress.skill_*_mult)가 피해·범위·쿨다운에 곱해지고, 수액의 맥동(여왕)이 3타 회복 +12·회복 ×1.1·낙하 공격 ×1.3/범위 ×1.15.

enum State { IDLE, WALK, RUN, JUMP, FALL, ROLL, ATTACK, SOUL_SLASH, PLUNGE, GUARD, HIT, HEAL, PURIFY, REST, DEAD }
const LOCOMOTION := [State.IDLE, State.WALK, State.RUN, State.JUMP, State.FALL]
## 히트박스를 쓰는 공격 상태들 (나가면 히트박스를 끈다)
const ATTACK_STATES := [State.ATTACK, State.SOUL_SLASH, State.PLUNGE]
## 이 상태들에 있는 동안은 스태미너가 저절로 차지 않는다 (v1.1.0 기획자 요청 12). 벗어나면 stamina_regen_delay_after_action 뒤부터.
## 스태미너가 자연 회복되지 않는 상태 (벗어나면 stamina_regen_delay_after_action 뒤부터 찬다). 구르기도 (v1.1.0 맞딜 검수: 구르기 15)
const NO_REGEN_STATES := [State.ATTACK, State.SOUL_SLASH, State.PLUNGE, State.GUARD, State.ROLL]
## 일반 공격 판정 상자: 앞 30 부터 light_reach 까지, 위 90 · 아래 22 (소녀 가운데 기준, 오른쪽을 볼 때)
const LIGHT_BOX_BACK := 30.0
const LIGHT_BOX_TOP := -90.0
const LIGHT_BOX_H := 112.0
## 휘두름 소리 음높이 (1·2·3타가 귀로도 구별되게)
const SWING_PITCH := [1.0, 1.08, 0.92]
## 쿨다운이 이보다 적게 남으면 끝난 것으로 본다 (부동소수 찌꺼기)
const COOLDOWN_EPS := 0.001
## 영혼 기술 함께 잠김(soul_shared_lockout)의 남은 시간을 담는 칸 — 영혼별 쿨다운 사전(Progress.soul_cooldowns)에 같이 넣어
## 저절로 줄고(_physics_process), 사전을 비우는 곳(부활·러시·시험 도구)에서 함께 지워진다.
const SOUL_LOCK_KEY := "_lock"
## 바람·빛 투사체 판정이 소녀 가운데보다 뒤로 나가는 최대 거리 (px). 이보다 뒤(등 뒤)의 적은 맞지 않는다.
const SHOT_BACK_REACH := 15.0

signal state_changed(new_state: State)
signal jumped(air_jump: bool)
signal landed(fall_speed: float)
## 점프 중 천장에 머리를 박았다 (부딪힌 지형, 부딪힐 때 올라가던 속도)
signal ceiling_bumped(collider: Node, speed: float)
signal roll_started
signal hp_changed(hp: float, max_hp: float)
signal guard_changed(guard: float, max_guard: float)
signal dews_changed(dews: int)
signal attacked(step: int)
## 씨앗 영혼의 넓은 베기를 시작했다
signal soul_slash_started
## 낙하 공격을 시작했다 / 바닥에 꽂혔다
signal plunge_started
signal plunge_landed
## 한쪽 방향 발판을 ↓+점프로 통과해 내려간다
signal dropped_through(platform: Node)
signal just_guarded(source: Node)
## 일반 가드로 막았다 (막은 피해). 보호막 충격 고리와 소리가 여기에 붙는다.
signal guard_hit(damage: float)
signal guard_broken
signal hit_taken(damage: float)
signal healed
signal purify_started(target: Node)
signal purified(target: Node)
signal rest_started(grass: Node)
signal rest_ended
signal died
signal interactables_changed(can_interact: bool)
signal gust_cast
## 빛의 영혼 레이저: 모으기 시작 / 발사 (맞힌 수)
signal laser_charge_started
signal laser_fired(hits: int)
signal soul_changed(soul: String)
signal blocked
## 칼이 실제로 닿은 순간 (불꽃·히트스톱이 나는 때 — 판정보다 조금 늦을 수 있다. 아래 '타격 연출 미루기')
signal hit_impact(result: String, target: Node)
## 스태미너가 모자라 공격을 시작하지 못했다 (HUD 막대가 붉게 번쩍, 짧은 소리)
signal stamina_refused
## 수액의 맥동: 3타가 적에게 닿아 스태미너가 즉시 찼다 (찬 양)
signal stamina_pulsed(amount: float)

@export_group("걷기와 달리기")
## 걷는 속도 (픽셀/초). 화면 기준 1920×1080.
@export var walk_speed := 380.0
## 달리는 속도. 회피 버튼을 길게 누르고 있으면 달린다.
@export var run_speed := 640.0
## 땅에서 속도가 붙는 빠르기. 클수록 즉각 반응.
@export var ground_accel := 4200.0
## 땅에서 멈추는 빠르기.
@export var ground_decel := 5400.0
## 공중에서 방향을 바꾸는 빠르기 (땅보다 조금 둔하게).
@export var air_accel := 2800.0
## 회피 버튼을 이 시간(초) 넘게 누르고 있으면 구르기 대신 달리기.
@export var run_hold_time := 0.2

@export_group("점프")
## 점프 최고 높이 (픽셀). 소녀 키가 약 110.
@export var jump_height := 260.0
## 최고점까지 걸리는 시간 (초). 짧을수록 가볍고 빠른 점프.
@export var jump_time_to_apex := 0.4
## 떨어질 때 중력 배수. 1보다 크면 올라갈 때보다 빨리 떨어져 경쾌하다.
@export var fall_gravity_multiplier := 1.7
## 점프 버튼을 일찍 떼면 상승 속도를 이 비율로 줄인다 (짧은 점프).
@export var jump_cut_multiplier := 0.4
## 최대 낙하 속도.
@export var max_fall_speed := 1900.0
## 발판 끝에서 떨어진 뒤에도 이 시간(초) 안에는 점프할 수 있다 (코요테 타임).
@export var coyote_time := 0.1
## 땅에 닿기 직전에 누른 점프를 이 시간(초) 동안 기억한다.
@export var jump_buffer_time := 0.12
## 점프 횟수. 이단 점프를 얻으면 2.
@export var max_jumps := 1
## 하단 점프(↓+점프로 한쪽 방향 발판 통과): 발판과의 충돌을 이 시간(초) 동안 끈다.
@export var drop_through_time := 0.25

@export_group("구르기")
## 구르는 속도.
@export var roll_speed := 980.0
## 구르는 시간 (초). 거리 = 속도 × 시간.
@export var roll_duration := 0.3
## 구르기 뒤 다시 구를 수 있기까지의 간격 (초).
@export var roll_cooldown := 0.1
## 구르기 시간 중 앞부분 이 비율 동안은 무적.
@export var roll_invuln_ratio := 0.7

@export_group("체력과 회복")
@export var max_hp := 100.0
## 이슬 방울 개수 (달빛풀에서 다시 채워진다). 실제 값은 _apply_abilities 가 Progress.dew_max() 로 정한다 (최대 Progress.MAX_DEWS = 5).
@export var max_dews := 3
@export var heal_amount := 45.0
## 회복 동작에 걸리는 시간. 그동안 움직일 수 없고 맞으면 끊긴다.
@export var heal_time := 0.7

@export_group("약공격 (3연타)")
@export var light_damage := [12.0, 12.0, 18.0]
@export var light_poise := [20.0, 20.0, 32.0]
## 타마다의 예비동작 / 판정 / 되돌림 (초). 3타는 예비동작이 조금 길고, 되돌림 0.35초가 '후딜레이'다 (v1.1.0 기획자 요청 11).
## 3타 되돌림이 시작되면 그 길이만큼 공격·영혼 기술·낙하 공격을 받지 않는다 (light_recovery_final, _combo_lock_timer).
@export var light_startup := [0.07, 0.07, 0.09]
@export var light_active := [0.10, 0.10, 0.12]
@export var light_recovery := [0.20, 0.20, 0.35]
## 사거리: 몸 가운데에서 칼끝 판정 끝까지 (px). 225 → 270 (+20%, v1.1.0 기획자 요청 3). 판정 상자는 앞 30 부터 여기까지, 위 90·아래 22.
## 새순 '일반 공격' 단계가 오르면 Progress.skill_range_mult("normal") 만큼 더 길어진다 (칼자국 이펙트도 같이).
@export var light_reach := 270.0
## 공격하며 앞으로 살짝 나아가는 속도.
@export var light_lunge := 180.0

@export_group("씨앗 베기 (처음부터 있는 영혼 기술)")
## 느리지만 앞·위·아래를 한꺼번에 베는 큰 호. 땅·공중 모두 쓸 수 있다.
## v1.1.0 (기획자 요청 6): 피해 32 → 40 (+25%), 앞 사거리 340 → 374 (+10%).
@export var slash_damage := 40.0
@export var slash_poise := 60.0
## 예비동작(칼을 머리 뒤로 크게 들어 올림) → 타격 → 되돌림 (초)
@export var slash_startup := 0.28
@export var slash_active := 0.18
@export var slash_recovery := 0.32
@export var slash_cooldown := 1.4
## 판정 상자 (소녀 중심 기준, 오른쪽을 볼 때): 뒤로 60, 위로 250, 앞으로 374, 아래로 180
## (앞 260 은 약공격(225)보다 35px 밖에 안 넓어 '상당히 넓은 전방'이 아니었다 — 2026-10-18 검토로 340 으로, v1.1.0 에 374 로)
## 새순 '씨앗' 단계가 오르면 앞쪽 끝만 Progress.skill_range_mult("seed") 배로 (seed_slash_box).
@export var slash_box := Rect2(-60, -250, 434, 430)
@export var slash_knockback := Vector2(420, -200)

@export_group("낙하 공격 (공중에서 ↓ + 약공격)")
## 멈칫하는 시간 (칼을 아래로 겨눔) → 급강하 속도
@export var plunge_pause := 0.08
@export var plunge_speed := 1500.0
## 떨어지는 동안의 하단 판정 (발 아래 넉넉히)
@export var plunge_damage := 26.0
@export var plunge_poise := 45.0
@export var plunge_box := Rect2(-110, -40, 220, 160)
@export var plunge_knockback := Vector2(300, -260)
## 적을 맞히면 이 속도로 튕겨 오른다 (이단 점프가 있으면 공중 점프 1회도 되돌려 준다)
@export var plunge_bounce := -620.0
## 튕긴 뒤 다시 낙하 공격을 시작할 수 있기까지 (초). 그동안 누른 ↓+약공격은 기억했다가 풀리는 순간 나간다.
## (없으면 적 위에서 0.17초마다 한 번씩 맞혀 초당 100 넘는 피해가 나오고 적이 반격할 틈이 없다 — 2026-10-18 검토)
@export var plunge_relock := 0.25
## 바닥에 닿기 전에 두 번째부터 맞히는 낙하 공격의 피해 비율 (연속 튕김 약화)
@export var plunge_repeat_ratio := 0.6
## (이 공중 연속 감쇠는 바닥을 디디면 처음으로 돌아간다 — 일반 몹에게는 이 규칙만. 보스·중간 보스는 따로 **시간 창**으로 센다:
##  앞 낙하 공격이 맞은 뒤 4초 안이면 피해 ×0.6^n·흐트러짐 ×0.5^n, 착지와 상관없이 — scripts/combat/plunge_decay.gd.
##  두 규칙은 곱하지 않고 더 많이 줄이는 쪽 하나만 쓴다.)
## true = 튕길 때마다 피해가 plunge_repeat_ratio 배씩 **거듭** 줄어든다 (1 → 0.6 → 0.36 → 0.22 …, 바닥을 디디면 다시 1).
## false = 두 번째부터 늘 0.6 (v1.1.0 전). v1.1.0 검수(맞딜 방지): 낙하 공격은 스태미너를 쓰지 않아서, 보스 위에서 튕기며
## 낙하 공격만 거듭하면 보스의 땅 공격(내려찍기·휘두르기)이 위로 닿지 않는 채 초당 약 80 의 피해가 났다
## (패턴을 무시한 봇이 30판 중 13판 이김 → 흐트러짐만 막으면 1판, 거듭 줄이면 0판·보스 체력 평균 64~87% 남음).
@export var plunge_repeat_compound := true
## 바닥에 닿기 전에 두 번째부터 맞히는 낙하 공격의 흐트러짐 비율 (v1.1.0 검수 — 맞딜 방지).
## 튕기며 거듭 내려꽂을 때마다 흐트러짐 45 가 쌓여 보스(특히 무쇠 펌프)가 싸움의 절반을 무너진(피해 ×2) 채로 보냈다.
## 0 = 첫 번째(바닥을 딛고 뛴 뒤 처음 맞힌 것)만 흐트러짐을 쌓는다. 튕김은 그대로. 착지 충격(plunge_land_poise)도 그대로.
@export var plunge_repeat_poise_ratio := 0.0
## 바닥에 닿았을 때의 충격 판정 (넓고 낮게) 과 그 시간
@export var plunge_land_time := 0.12
@export var plunge_land_damage := 18.0
@export var plunge_land_poise := 35.0
@export var plunge_land_box := Rect2(-170, -60, 340, 100)
## 착지 뒤 일어서는 시간
@export var plunge_recovery := 0.22

@export_group("스태미너 (v1.1.0: 가드 게이지를 함께 쓴다)")
## 스태미너는 가드 게이지 그대로다 (guard / max_guard, 읽기 별칭 stamina / max_stamina). 최대치는 Progress.max_stamina() (100/103/106/109).
## 약공격 1·2·3타가 쓰는 스태미너 (3타 합 37). 모자라면 그 공격을 시작하지 않는다. 낙하 공격·영혼 기술은 쓰지 않는다.
@export var light_stamina_cost := [10.0, 12.0, 15.0]
## 구르기가 쓰는 스태미너 15 (v1.1.0 맞딜 검수 — 기획자 요청 10 "기존 방어 및 회피 행동의 스태미너 소모 기능은 유지":
## 기획자는 회피가 스태미너를 쓴다고 본다 → 명세 D1 의 0 을 바꿈). 모자라면(15 미만) 구르지 않고 막대가 붉게 번쩍인다(stamina_refused).
## 구르는 동안은 자연 회복이 없고(NO_REGEN_STATES), 끝난 뒤 0.5초 지나서 찬다 (공격·가드와 같은 규칙).
## (공격 뒤 되돌림을 구르기로 끊으며 보스 몸을 뚫고 지나가기만 거듭하는 맞딜 — 펌프 18판 중 12판 봇 승 — 을 막는다)
@export var roll_stamina_cost := 15.0
## 공격·영혼 기술·낙하 공격·가드에서 벗어난 뒤 자연 회복을 기다리는 시간 (초)
@export var stamina_regen_delay_after_action := 0.5
## 바람·빛(상태가 따로 없는 영혼 기술)은 쏜 순간부터 이만큼 기다린다 (쏘는 0.2초 + 0.5초)
@export var stamina_regen_delay_after_shot := 0.7
## 가드로 막은 뒤 / 가드가 깨진 뒤 기다리는 시간 (v1.1.0 값 그대로 — v1.1.1 에서 이름만 붙임)
@export var stamina_regen_delay_after_block := 0.8
@export var stamina_regen_delay_after_break := 1.5

@export_group("수액의 맥동 (수액의 여왕을 정화하면 얻는 영구 패시브)")
## 3타가 적에게 닿으면 즉시 차는 스태미너 (3타 한 번에 한 번만, 여러 적을 맞혀도)
@export var sap_pulse_stamina := 12.0
## 자연 회복 빠르기 배수 (28 → 30.8)
@export var sap_pulse_regen_mult := 1.1
## 낙하 공격(내려꽂기·착지 충격) 피해 배수와 판정 크기 배수 (상자 가운데는 그대로, 이펙트도 같이 커진다)
@export var sap_pulse_plunge_damage_mult := 1.3
@export var sap_pulse_plunge_box_mult := 1.15

@export_group("수액의 숨결 (v1.1.1: 수액의 여왕을 정화하면 얻는 또 하나의 영구 패시브)")
## 공격·구르기·가드·영혼 기술·막기·가드 깨짐으로 끊긴 스태미너 회복이 다시 시작되기까지의 기다림 배수
## (0.5 → 0.375, 바람·빛 0.7 → 0.525, 막은 뒤 0.8 → 0.6, 깨짐 1.5 → 1.125). 최대치·소모량·3타 후딜레이·맥동은 그대로.
@export var sap_breath_delay_mult := 0.75

@export_group("가드와 저스트 가드")
@export var max_guard := 100.0
## 가드 중 받는 피해 비율 (0.15 = 85% 줄임).
@export var guard_damage_ratio := 0.15
## 막은 피해 1당 깎이는 가드 게이지.
@export var guard_drain_ratio := 1.3
## 가드를 하지 않을 때 초당 회복되는 가드 게이지.
@export var guard_regen := 28.0
## 가드 버튼을 누른 뒤 이 시간(초) 안에 맞으면 저스트 가드.
## 저스트 가드 판정 (가드를 누른 뒤 이 시간 안에 맞으면). 0.15 → 0.24 로 후하게 (2026-10-18 기획자 요청).
@export var just_guard_window := 0.24
## 가드를 뗀 뒤 다시 가드할 수 있기까지 (연타 방지).
@export var guard_relock_time := 0.2
## 가드가 깨졌을 때 무방비 시간.
@export var guard_break_stun := 1.0
## 가드 중 걷는 속도 비율.
@export var guard_move_ratio := 0.4
## 저스트 가드가 적에게 주는 흐트러짐.
@export var just_guard_poise := 45.0

@export_group("바람 공격 (잿빛 잎새의 새의 영혼)")
## 2026-10-18 강화: 피해 14→24, 크기 60×34→110×60, 사거리 0.5초→0.95초(약 720px)
## 2026-10-19 파격 상향 (기획자 요청): 피해 ×4 (24→96), 크기 240×130, 사거리 1.3초(약 990px), 쿨다운 5초.
##   '한 방이 크고 자주 못 쓰는' 기술로. 씨앗 베기(처음부터 있는 것)는 그대로.
## v1.1.0 (기획자 요청 6): 피해 96 → 120 (+25%). 쿨다운은 새순 '바람' 단계로 줄어든다 (Progress.skill_cooldown_mult("wind")).
@export var gust_damage := 120.0
@export var gust_poise := 24.0   # 흐트러짐은 그대로 (요청은 피해·크기·쿨만). 30 미만이라 침식된 기계에는 여전히 35%만 들어간다
@export var gust_speed := 760.0
@export var gust_range_time := 1.3
@export var gust_cooldown := 5.0
## 2026-10-19 이펙트 리뉴얼: 초승달 검기 그림의 머리(세로로 선 초승달)에 맞춰 240×130(가로로 긴 바람 호) → 190×230.
## 판정은 예전처럼 크기 × 0.9 사각형 (171×207). 그림의 꼬리(옅은 빛줄기)는 판정에 넣지 않는다.
@export var gust_size := Vector2(190, 230)

@export_group("빛 공격 (등불 기사의 영혼)")
## 2026-10-18 강화: 피해 22→34, 크기 70×22→120×40, 사거리 0.7초→1.1초(약 1200px)
## 2026-10-19 파격 상향 (기획자 요청): 피해 ×4 (34→136), 크기 280×90, 사거리 1.4초(약 1540px), 쿨다운 7초.
## v1.1.0 (기획자 요청 7): 피해 136 → 95.2 (-30%, 광역 직선 공격이 너무 세서). 쿨다운은 새순 '빛' 단계로 줄어든다.
@export var light_shot_damage := 95.2
@export var light_shot_poise := 30.0   # 흐트러짐은 그대로 (요청은 피해·크기·쿨만)
@export var light_shot_speed := 1100.0
@export var light_shot_time := 1.4
@export var light_shot_cooldown := 7.0
## 2026-10-19 이펙트 리뉴얼: 날아가는 빛의 창 → 레이저. 사거리 = 예전에 날아가던 거리 (속도 × 수명 = 1540px),
## 빛줄기 판정 높이 = light_shot_size.y × 0.9 (81px, 예전 판정 높이 그대로). light_shot_size.x 는 더 쓰지 않는다.
@export var light_shot_size := Vector2(280, 90)
## 손에 빛을 모으는 시간 (초) — 이 동안은 움직일 수 있고, 맞으면 쏘지 않고 쿨다운을 돌려받는다
@export var light_charge_time := 0.12
## 빛줄기가 화면에 남는 시간 (초) / 그중 적을 맞히는 앞부분 (초)
@export var light_beam_time := 0.42
@export var light_beam_active := 0.08

@export_group("영혼 기술 함께 잠김")
## v1.1.0 맞딜 검수(영혼 돌려 쓰기): 어느 영혼 기술이든 쓰면 **모든** 영혼 기술이 이만큼(초) 함께 잠긴다.
## 영혼마다의 쿨다운(씨앗 1.4 · 바람 5 · 빛 7)은 그대로, 영혼 바꾸기도 그대로 즉시 — 세 쿨다운을 겹쳐 바꿔 가며 몰아 쓰지 못하게 할 뿐이다
## (패턴을 무시하고 맞으며 씨앗 → 바람 → 빛을 준비되는 대로 쏘던 봇이 여왕 18판 중 6판·뿌리지기 5판, 달려 다니며 쏘면 여왕 11판을 이겼다).
## 1.5 에서는 달려 다니는 봇이 여왕 2판·뿌리지기 3판(봇 체력 78%)을 이겨 1.65 로 올렸다 (오케스트레이터 사다리 1.5 → 최대 2.5).
## 바람·빛은 쏜 순간부터, 씨앗 베기는 누른 순간(예비동작 시작)부터 센다 — 씨앗만 쓰면 누름 사이가 예비 0.28 + 제 쿨 1.4 = 1.68 초라
## 1.65 보다 길어 리듬이 그대로다 (1.68 을 넘기면 씨앗만 쓰는 사람도 느려진다).
## 예비동작 중에 맞아 끊긴 베기·모으는 중에 끊긴 빛은 쿨다운처럼 잠김도 돌려준다. HUD 영혼 원·터치 영혼 버튼의 쿨다운 호와 남은 초에 함께 보인다.
## 대가: '잘하는 봇'(tools/probe_facetank --good)도 영혼을 바꿔 가며 쓰므로 느려졌다 (기사·뿌리지기 약 +25%, 여왕 +40%).
## → v1.1.0 맞딜 검수 2: **0 (꺼짐)**. 그 대신 보스 쪽에서 패턴을 무시하고 붙어 버티는 소녀만 응징한다 (각 보스 스크립트: 뿌리지기 두 번
## 내려찍기·뿌리 창, 기사 두 번 내려찍기, 펌프 두 번 김 분출, 여왕 수액 터뜨리기·기술 없이 무너뜨린 무너짐은 1.6초, 새 공중 씨앗 베기 지침 1·
## 잎 삼키기 끊기는 내려앉음마다 한 번). 잠그는 길(코드)은 조절용으로 남긴다 (0 보다 크게 하면 위 규칙 그대로; 시험 probe_stamina (k)).
@export var soul_shared_lockout := 0.0

## 영혼마다의 이름·설명·색 (HUD·터치 버튼·전환 알림이 함께 쓴다). 색: 씨앗 연둣빛 / 바람 민트 / 빛 금빛.
const SOUL_INFO := {
	"seed": {"name": "씨앗", "title": "씨앗의 영혼", "source": "세계수의 씨앗", "desc": "넓은 베기 — 앞·위·아래를 한 번에 벤다", "color": Color(0.85, 1.0, 0.75)},
	"wind": {"name": "바람", "title": "바람의 영혼", "source": "잿빛 잎새의 새", "desc": "초승달 검기 — 멀리 날아가 크게 친다", "color": Color(0.85, 1.0, 0.9)},
	"light": {"name": "빛", "title": "빛의 영혼", "source": "등불 기사", "desc": "빛줄기 — 벽까지 곧게 뻗어 늘어선 적을 모두 꿰뚫는다", "color": Color(1.0, 0.9, 0.7)},
}

@export_group("피격")
@export var hit_stun := 0.3
## 맞은 뒤 무적 시간.
@export var invuln_time := 0.7
## 보스전(BossRoom 이 싸움을 건 동안) 맞은 뒤 무적 시간 — v1.1.0 맞딜 방지 사다리 3단계(명세 3.7, 기획자 요청 8 마지막 문장):
## 공격 패턴을 무시하고 맞으면서 때리면 겹친 공격이 더 자주 들어온다. 일반 몹·환경은 invuln_time 그대로.
@export var invuln_time_boss := 0.5
## BossRoom 이 싸움을 시작하면 true, 끝나거나(쓰러뜨림·부활·정화) 방을 나가면 false.
var boss_fight := false

var state: State = State.IDLE
## 바라보는 방향. 1 = 오른쪽, -1 = 왼쪽.
var facing := 1
var is_running := false
## 걷기 고정 (터치의 걷기 버튼, 컨트롤러 L3). 달리기가 기본이고, 켜면 이동이 걷기가 된다 (2026-10-18 기획자 결정).
## 걷는 중에도 회피 버튼을 길게 누르면 그동안은 달린다.
var walk_locked := false
var hp := 100.0
var guard := 100.0
var dews := 3
## 스태미너 = 가드 게이지 (v1.1.0, 기획자 결정 D1). 이름은 guard / max_guard 그대로 두고 읽기 별칭만 둔다 (터치·시험 호환).
var stamina: float:
	get: return guard
var max_stamina: float:
	get: return max_guard
## 지금 상호작용(쉬기·정화)할 수 있는 대상들.
var interactables: Array = []
var can_interact: bool:
	get: return not interactables.is_empty()
## 자동 시험이나 터치 조작이 아닌, 실제 입력을 잠시 막을 때.
var input_enabled := true
## 공격 단계 (약공격 1~3), 공격 국면
##   약공격·씨앗 베기: "startup" / "active" / "recovery"
##   낙하 공격: "pause"(멈칫) / "dive"(급강하) / "land"(착지 충격) / "recovery"
var attack_step := 0
var attack_phase := ""
var purify_target: Node2D

var _dodge_running := false
var _jump_gravity := 0.0
var _jump_velocity := 0.0
var _coyote_timer := 0.0
var _buffer_timer := 0.0
var _jumps_left := 0
var _roll_timer := 0.0
var _roll_cooldown_timer := 0.0
var _dodge_hold := 0.0
var _dodge_held := false
var _was_on_floor := false
var _last_fall_speed := 0.0
var _attack_timer := 0.0
var _attack_buffered := false
var _guard_pressed_at := -1000.0
var _guard_released_at := -1000.0
var _hit_timer := 0.0
var _invuln_timer := 0.0
var _heal_timer := 0.0
var _guard_regen_delay := 0.0
## 3타 후딜레이: 남아 있는 동안 공격·영혼 기술·낙하 공격을 받지 않고(누른 것도 기억하지 않는다), 스태미너도 차지 않는다.
## 소녀만의 타이머다 — Juice.hitstop(Engine.time_scale) 을 쓰지 않으므로 게임 전체는 멈추지 않는다.
var _combo_lock_timer := 0.0
## 수액의 맥동: 이번 3타에서 이미 스태미너를 받았는가 (3타를 시작할 때 지운다)
var _pulse_awarded := false
## 콤보를 잇다가 스태미너가 모자라 끊겼다: 이번 되돌림 동안은 더 잇지 않는다 (다음 타를 시작할 때 지운다)
var _chain_refused := false
## 영혼마다 남은 쿨다운 (초): {"seed": …, "wind": …, "light": …}. 2026-10-19 검토: 바람·빛 쿨이 5~7초가 되면서
## 하나를 같이 쓰면 빛을 쏜 뒤 씨앗 베기(1.4초)까지 7초 막혔다 → 영혼마다 따로 센다. 고른 영혼을 바꿔도 각자 줄어든다.
## 영혼별 남은 쿨다운. 방마다 소녀가 새로 만들어지므로 Progress 의 사전을 함께 쓴다 (포탈을 지나도 7초가 초기화되지 않게).
var _soul_cooldowns: Dictionary = Progress.soul_cooldowns
## 지금 고른 영혼의 남은 쿨다운 (옛 이름 그대로 둔 통로 — 시험 도구들이 읽고 쓴다).
var _soul_cooldown: float:
	get:
		return float(_soul_cooldowns.get(soul, 0.0))
	set(v):
		_soul_cooldowns[soul] = maxf(v, 0.0)
## 씨앗 베기를 누르기 전의 함께 잠김 남은 시간 (예비동작 중에 끊기면 이 값으로 돌려준다)
var _slash_lock_prev := 0.0
var _interact_buffer := 0.0
var _drop_timer := 0.0
var _drop_body: Node = null
var _plunge_lock := 0.0        # 튕긴 뒤 다시 낙하 공격을 받기까지 남은 시간
var _plunge_buffered := false  # 잠금 중에 누른 ↓+약공격 (풀리면 바로 낙하 공격)
var _plunge_btn_buffered := false  # 잠금 중에 누른 낙하 공격 버튼 (↓ 없이도 풀리면 바로 낙하 공격)
var _plunge_hits := 0          # 바닥에 닿기 전에 낙하 공격으로 맞힌 횟수 (두 번째부터 피해 감쇠)
## 낙하 공격으로 튕긴 뒤 적의 몸통 부딪힘을 받지 않는 남은 시간. 튕겨 오른 동안은 계속 차 있고, 착지한 뒤 이만큼 더 간다.
const CONTACT_GRACE_AFTER_LAND := 0.5
var _contact_grace := 0.0
var _light: PointLight2D
## 포자 구름 등으로 느려진 비율 (1 = 정상). 매 프레임 되돌아온다.
var slow_factor := 1.0
## 구르기 속도 배수 (1 = 정상). 수액 웅덩이가 정한다 (수액 위 걷기 능력이 있으면 길게, 없으면 짧게). 매 프레임 되돌아온다.
var roll_factor := 1.0
## 지금 고른 영혼: "seed"(처음부터) / "wind" / "light"
var soul := ""
## 마지막으로 안전하게 서 있던 자리 (가시에 떨어지면 여기로 돌아온다).
## 가시는 몸이 닿는 순간 발동하므로 '바로 직전' 자리는 가시 판정 안일 수 있다 → 0.45초쯤 전의 자리를 쓴다
## (안전 자리 후보를 SAFE_SAMPLE 간격으로 기억해 두고 가장 오래된 것을 돌려준다).
var last_safe_position := Vector2.ZERO
var _safe_timer := 0.0
const SAFE_SAMPLE := 0.15
const SAFE_HISTORY := 4   # 0.15 × 4 = 0.6초 전까지 기억 (가장 오래된 것이 0.45~0.6초 전)
var _safe_history: Array[Vector2] = []
var _safe_sample_timer := 0.0
## 성장: 공격 배수 (구원한 사람의 보상 등)
var attack_multiplier := 1.0
var _wind := 0.0   # 이번 물리 프레임에 받는 바람 (픽셀/초²)

const WIND_CRESCENT := preload("res://scripts/combat/wind_crescent.gd")
const SOUL_LASER := preload("res://scripts/combat/soul_laser.gd")
## ↓를 '분명히' 누르고 있다고 볼 세기 (0~1). 터치 스틱은 12% 만 내려도 move_down 이 '눌림'이 되므로(action_press),
## 낙하 공격·하단 점프는 이 세기를 넘을 때만. 키보드 1.0, 터치·컨트롤러 스틱은 내린 비율 그대로(raw) 잰다.
const DOWN_HOLD_STRENGTH := 0.5

@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox


func _ready() -> void:
	_recalculate_jump()
	hp = max_hp
	guard = max_guard
	dews = max_dews
	hitbox.landed.connect(_on_hit_landed)
	add_to_group("player")
	_apply_abilities()
	Progress.ability_gained.connect(func(_a): _apply_abilities())
	_apply_settings()
	Settings.changed.connect(_apply_settings)
	# 효과음
	jumped.connect(func(_air): Sfx.play("jump"))
	landed.connect(func(v): if v > 300.0: Sfx.play("land", -6.0 + clampf(v / 400.0, 0.0, 6.0)))
	roll_started.connect(func(): Sfx.play("roll", -4.0))
	attacked.connect(func(s): _play_pitched("swing", -6.0, SWING_PITCH[clampi(s, 1, 3) - 1]))
	stamina_refused.connect(func(): Sfx.play("select", -14.0, 0.0))
	soul_slash_started.connect(func(): Sfx.play("slash_wide", -2.0, 0.04))
	plunge_started.connect(func(): Sfx.play("plunge", -4.0, 0.04))
	plunge_landed.connect(func(): Sfx.play("heavy_hit", -1.0, 0.05))
	just_guarded.connect(func(_s): Sfx.play("just_guard", 2.0, 0.02))
	guard_hit.connect(func(_d): Sfx.play("guard", 0.0, 0.05))
	guard_broken.connect(func(): Sfx.play("guard_break"))
	hit_taken.connect(func(_d): Sfx.play("hurt", -2.0))
	healed.connect(func(): Sfx.play("heal", -4.0))
	purify_started.connect(func(_t): Sfx.play("purify", -2.0, 0.0))
	gust_cast.connect(_on_gust_cast_sfx)
	laser_charge_started.connect(func(): Sfx.play("ring_hum", -10.0, 0.0))
	laser_fired.connect(func(_n): Sfx.play("sword_wave", -3.0, 0.03))
	soul_changed.connect(func(_s): Sfx.play("select", -4.0))
	rest_started.connect(func(_g): Sfx.play("bloom", -6.0, 0.0))
	died.connect(func(): Sfx.play("boss_fall", -4.0))


var _base_just_guard_window := -1.0
func _apply_settings() -> void:
	if _base_just_guard_window < 0.0:
		_base_just_guard_window = just_guard_window
	just_guard_window = _base_just_guard_window * (1.5 if Settings.get_value("lenient_guard") else 1.0)


func _apply_abilities() -> void:
	max_jumps = 2 if Progress.has_ability("double_jump") else 1
	var owned := owned_souls()
	# 처음부터 '씨앗' 영혼이 있다. 새 영혼을 얻어도 저절로 바꾸지 않는다 (고른 것은 그대로).
	# 고른 영혼은 Progress.soul 에 둔다: 소녀는 방마다 새로 만들어지므로 여기 변수만으로는 방을 옮길 때마다 '씨앗'으로 돌아간다.
	soul = Progress.soul if owned.has(Progress.soul) else "seed"
	Progress.soul = soul
	if _light:
		_light.texture_scale = 3.6 if Progress.has_ability("lantern") else 1.0
		_light.energy = 2.4 if Progress.has_ability("lantern") else 0.9
	# 성장 보상 (Progress.upgrades)
	var old_max := max_hp
	max_hp = 100.0 + Progress.upgrades.get("max_hp", 0.0)
	if max_hp != old_max:
		hp = minf(hp + (max_hp - old_max), max_hp)
	attack_multiplier = 1.0 + Progress.upgrades.get("attack", 0.0)
	# 최대 스태미너 (= 가드 게이지 최대): 새순 '스태미너' 단계마다 +3 → 100/103/106/109. 늘면 늘어난 만큼 채운다 (체력과 같은 방식).
	var old_max_guard := max_guard
	max_guard = Progress.max_stamina()
	if max_guard != old_max_guard:
		guard = clampf(guard + maxf(max_guard - old_max_guard, 0.0), 0.0, max_guard)
		guard_changed.emit(guard, max_guard)
	# 이슬도 체력처럼 늘어난 만큼 채운다. 방에 들어오면 소녀가 새로 만들어져 _ready 가 기본값 3개만 채우므로,
	# 여기서 더해 주지 않으면 산 이슬·주운 이슬이 방을 옮길 때마다 빈 칸이 됐다 (2026-10-19 검수).
	# 이슬은 최대 Progress.MAX_DEWS (v1.1.0 에 5). 넘친 이슬은 하나마다 회복량 +10 으로 바뀐다 (Progress.heal_bonus).
	var old_max_dews := max_dews
	max_dews = Progress.dew_max()
	if max_dews > old_max_dews:
		dews += max_dews - old_max_dews
	dews = mini(dews, max_dews)
	heal_amount = 45.0 + Progress.heal_bonus()   # 회복량 아이템(맑은 샘물)·성장 + 넘친 이슬
	hp_changed.emit(hp, max_hp)
	dews_changed.emit(dews)


## 점프 높이와 시간으로 중력과 초기 속도를 계산한다.
func _recalculate_jump() -> void:
	_jump_gravity = 2.0 * jump_height / (jump_time_to_apex * jump_time_to_apex)
	_jump_velocity = _jump_gravity * jump_time_to_apex


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	_tick_timers(delta, on_floor)
	_tick_impacts(delta)

	match state:
		State.DEAD, State.PURIFY, State.REST:
			_apply_gravity(delta, on_floor)
			velocity.x = move_toward(velocity.x, 0.0, ground_decel * delta)
			move_and_slide()
			if state == State.REST and input_enabled and _wants_to_leave_rest():
				_set_state(State.IDLE)
				rest_ended.emit()
			return
		State.HIT:
			_apply_gravity(delta, on_floor)
			velocity.x = move_toward(velocity.x, 0.0, 1600.0 * delta)
			move_and_slide()
			if _hit_timer <= 0.0:
				_set_state(State.IDLE)
			return
		State.HEAL:
			_apply_gravity(delta, on_floor)
			velocity.x = move_toward(velocity.x, 0.0, ground_decel * delta)
			move_and_slide()
			if _heal_timer <= 0.0:
				hp = minf(hp + heal_amount, max_hp)
				hp_changed.emit(hp, max_hp)
				healed.emit()
				_set_state(State.IDLE)
			return

	var move_input := Input.get_axis("move_left", "move_right") if input_enabled else 0.0

	_handle_dodge_and_run(delta, on_floor)
	_handle_guard(on_floor)
	_handle_attacks(delta, on_floor)
	_handle_heal(on_floor)
	_handle_interact()
	_handle_soul(on_floor)
	_apply_gravity(delta, on_floor)
	_handle_jump(on_floor)
	_handle_horizontal(delta, on_floor, move_input)
	# 날갯바람: 구르는 중에는 덜 밀린다
	if _wind != 0.0:
		velocity.x += _wind * (0.35 if state == State.ROLL else 1.0) * delta
		_wind = 0.0

	_last_fall_speed = velocity.y
	move_and_slide()
	slow_factor = 1.0
	roll_factor = 1.0
	# 점프하다 천장에 머리를 박았다 (올라가던 중 위쪽에 부딪힘): 비밀 천장이 듣는다
	if is_on_ceiling() and _last_fall_speed < -150.0:
		for i in get_slide_collision_count():
			var c := get_slide_collision(i)
			if c.get_normal().y > 0.7:
				ceiling_bumped.emit(c.get_collider(), -_last_fall_speed)
				if c.get_collider() and c.get_collider().has_method("on_head_bump"):
					c.get_collider().on_head_bump(self, -_last_fall_speed)

	# (낙하 공격의 착지는 다음 프레임 _plunge_land 가 plunge_landed 로 알린다 — 착지음·찌그러짐이 두 번 겹치지 않게)
	if is_on_floor() and not _was_on_floor and state != State.ROLL and state != State.PLUNGE:
		landed.emit(_last_fall_speed)
	_was_on_floor = is_on_floor()
	_resolve_locomotion_state()
	# 안전한 자리 기억 (땅에 서 있고, 조금 지난 뒤). 가시에 닿기 직전 자리는 피하려고 조금 전 자리를 쓴다.
	if is_on_floor() and _invuln_timer <= 0.0:
		_safe_timer += delta
		if _safe_timer > 0.35:
			_safe_sample_timer += delta
			if _safe_history.is_empty() or _safe_sample_timer >= SAFE_SAMPLE:
				_safe_sample_timer = 0.0
				_safe_history.append(global_position)
				while _safe_history.size() > SAFE_HISTORY:
					_safe_history.pop_front()
			last_safe_position = _safe_history[0]
	else:
		_safe_timer = 0.0


func _tick_timers(delta: float, on_floor: bool) -> void:
	if not on_floor and _plunge_hits > 0:
		_contact_grace = maxf(_contact_grace, CONTACT_GRACE_AFTER_LAND)
	else:
		_contact_grace = maxf(_contact_grace - delta, 0.0)
	if on_floor:
		_coyote_timer = coyote_time
		_jumps_left = max_jumps
		_plunge_hits = 0
		_plunge_buffered = false
		_plunge_btn_buffered = false
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)
		# 발판에서 걸어 떨어져 코요테 시간이 지났다: 땅 점프는 쓴 것으로 (이단 점프만 남는다).
		# 전에는 그대로 남아 있어서, 이단 점프가 없어도 떨어지는 중에 한 번 더 뛸 수 있었다 (2026-10-18).
		if _coyote_timer <= 0.0 and _jumps_left >= max_jumps:
			_jumps_left = max_jumps - 1
	_plunge_lock = maxf(_plunge_lock - delta, 0.0)
	_buffer_timer = maxf(_buffer_timer - delta, 0.0)
	_roll_cooldown_timer = maxf(_roll_cooldown_timer - delta, 0.0)
	_hit_timer = maxf(_hit_timer - delta, 0.0)
	_invuln_timer = maxf(_invuln_timer - delta, 0.0)
	_heal_timer = maxf(_heal_timer - delta, 0.0)
	_guard_regen_delay = maxf(_guard_regen_delay - delta, 0.0)
	_combo_lock_timer = maxf(_combo_lock_timer - delta, 0.0)
	for k in _soul_cooldowns.keys():
		var left: float = _soul_cooldowns[k] - delta
		# 1/60 씩 빼다 남는 부동소수 찌꺼기(0.000…1)는 0 으로: 끝나기 직전 한 프레임 '0' 이 보이거나 버튼이 꺼진 채 남지 않게
		_soul_cooldowns[k] = left if left > COOLDOWN_EPS else 0.0
	_interact_buffer = maxf(_interact_buffer - delta, 0.0)
	if _drop_timer > 0.0:
		_drop_timer -= delta
		if _drop_timer <= 0.0:
			_end_drop_through()
	# 스태미너 자연 회복: 공격·영혼 기술·낙하 공격·가드·구르기 중과 3타 후딜레이 동안은 없고, 벗어난 뒤 잠깐 기다렸다가 (_set_state 가 지연을 건다)
	if not (state in NO_REGEN_STATES) and _combo_lock_timer <= 0.0 and _guard_regen_delay <= 0.0 and guard < max_guard:
		guard = minf(guard + stamina_regen_rate() * delta, max_guard)
		guard_changed.emit(guard, max_guard)


func _apply_gravity(delta: float, on_floor: bool) -> void:
	if state == State.PLUNGE:
		return   # 낙하 공격은 속도를 직접 정한다 (멈칫 → 일정한 급강하)
	var gravity := _jump_gravity
	if velocity.y > 0.0:
		gravity *= fall_gravity_multiplier
	elif velocity.y < 0.0 and state == State.JUMP and input_enabled and Input.is_action_just_released("jump"):
		# 버튼을 일찍 뗐다: 상승 속도를 한 번만 줄여 짧은 점프로
		velocity.y *= jump_cut_multiplier
	if not on_floor:
		velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _handle_dodge_and_run(delta: float, on_floor: bool) -> void:
	if input_enabled:
		if Input.is_action_just_pressed("dodge"):
			_dodge_held = true
			_dodge_hold = 0.0
		if _dodge_held and Input.is_action_pressed("dodge"):
			_dodge_hold += delta
			if _dodge_hold >= run_hold_time:
				_dodge_running = true
		if _dodge_held and not Input.is_action_pressed("dodge"):
			_dodge_held = false
			if _dodge_hold < run_hold_time:
				_try_roll(on_floor)
			_dodge_running = false
		if Input.is_action_just_pressed("run_toggle"):
			walk_locked = not walk_locked
		if Input.is_action_just_pressed("jump"):
			_buffer_timer = jump_buffer_time
	is_running = _dodge_running or not walk_locked

	if state == State.ROLL:
		_roll_timer -= delta
		if _roll_timer <= 0.0:
			_roll_cooldown_timer = roll_cooldown
			_set_state(State.IDLE)


func _handle_guard(on_floor: bool) -> void:
	if not input_enabled:
		return
	var pressed := Input.is_action_pressed("guard")
	var can_start := on_floor and (state in LOCOMOTION or (state == State.ATTACK and attack_phase == "recovery"))
	if Input.is_action_just_pressed("guard") and can_start and _now() - _guard_released_at >= guard_relock_time:
		_guard_pressed_at = _now()
		_set_state(State.GUARD)
	if state == State.GUARD and (not pressed or not on_floor):
		_guard_released_at = _now()
		_set_state(State.IDLE)


func _handle_attacks(delta: float, on_floor: bool) -> void:
	if state in LOCOMOTION or state == State.GUARD:
		if not input_enabled:
			_plunge_buffered = false
			_plunge_btn_buffered = false
			return
		if _combo_lock_timer > 0.0:
			# 3타 후딜레이: 공격·낙하 공격을 받지 않고 누른 것도 기억하지 않는다 (가드·구르기는 따로 된다)
			_plunge_buffered = false
			_plunge_btn_buffered = false
			return
		if not on_floor and Input.is_action_just_pressed("plunge"):
			# 낙하 공격 버튼 (터치 전용 동작 'plunge', 2026-10-19 기획자 요청: 터치에서 ↓+공격이 잘 안 나가서).
			# 공중에서만 듣는다. ↓를 누르고 있지 않아도 나간다. 땅에서는 그냥 지나가서, 같은 프레임의 공격이 씹히지 않는다.
			if _plunge_lock > 0.0:
				_plunge_btn_buffered = true
			else:
				_start_plunge()
		elif Input.is_action_just_pressed("attack_light"):
			# 공중에서 ↓를 분명히 누른 채 공격 = 낙하 공격. 아니면 평소 공격(공중 포함).
			if not on_floor and _down_held():
				if _plunge_lock > 0.0:
					_plunge_buffered = true   # 튕겨 오르는 중: 기억했다가 잠금이 풀리는 순간 나간다
				else:
					_start_plunge()
			elif _can_pay(1):
				_start_light(1)
			else:
				stamina_refused.emit()   # 스태미너가 모자라 시작하지 않는다
		elif (_plunge_buffered or _plunge_btn_buffered) and not on_floor and _plunge_lock <= 0.0:
			var go := _plunge_btn_buffered or _down_held()
			_plunge_buffered = false
			_plunge_btn_buffered = false
			if go:
				_start_plunge()
		return
	if state == State.ATTACK or state == State.SOUL_SLASH:
		# 공중 공격·공중 씨앗 베기 중에 누른 낙하 버튼은 기억했다가, 휘두름이 끝나는(되돌림) 순간 낙하 공격으로 잇는다.
		# (터치에서 '점프 → 공격 → 낙하'를 조금 빨리 눌러도 씹히지 않게. 착지하면 _tick_timers 가 지운다.)
		if input_enabled and not on_floor and Input.is_action_just_pressed("plunge") and _combo_lock_timer <= 0.0:
			_plunge_btn_buffered = true
		if _plunge_btn_buffered and not on_floor and _plunge_lock <= 0.0 and attack_phase == "recovery" and _combo_lock_timer <= 0.0:
			_plunge_btn_buffered = false
			_start_plunge()
			return
	if state == State.ATTACK:
		if input_enabled and Input.is_action_just_pressed("attack_light"):
			_attack_buffered = true
		_attack_timer -= delta
		match attack_phase:
			"startup":
				if _attack_timer <= 0.0:
					attack_phase = "active"
					_attack_timer = light_active_of(attack_step)
					var dmg: float = light_damage[attack_step - 1] * attack_multiplier * Progress.skill_damage_mult("normal")
					var hit := HitData.make(dmg, light_poise[attack_step - 1], self, Vector2(260, -80) if attack_step < 3 else Vector2(520, -180))
					hit.from_player = true
					# 범위: 몸 가운데에서 판정 끝까지 light_reach (150 → 195 → v1.1.0 에 끝 225 → 270). 새순 단계로 더 길어진다.
					hitbox.set_box(light_box(), facing)
					hitbox.activate(hit, light_active_of(attack_step))
					if on_floor:
						velocity.x = facing * light_lunge
					if attack_step == 3:
						Sfx.play("heavy_hit", -6.0, 0.03)   # 3타는 휘두름에 묵직한 소리를 겹친다
			"active":
				if _attack_timer <= 0.0:
					attack_phase = "recovery"
					_attack_timer = light_recovery_of(attack_step)
					if attack_step >= 3:
						# 3타 후딜레이 시작: 소녀만의 잠금 (가드·구르기로 동작을 끊어도 잠금 시간은 계속 흐른다)
						_combo_lock_timer = light_recovery_final
						_attack_buffered = false
						_plunge_btn_buffered = false
			"recovery":
				if _attack_buffered and attack_step < 3 and not _chain_refused:
					if _can_pay(attack_step + 1):
						_start_light(attack_step + 1)
					else:
						# 스태미너가 모자라 다음 타를 시작하지 못한다: 콤보는 여기서 끝, 남은 되돌림 뒤 대기로
						_attack_buffered = false
						_chain_refused = true
						stamina_refused.emit()
				elif _attack_timer <= 0.0:
					_set_state(State.IDLE)
	elif state == State.SOUL_SLASH:
		_tick_soul_slash(delta)
	elif state == State.PLUNGE:
		# 착지·일어서는 동안 누른 약공격은 기억했다가 일어서자마자 1타로 잇는다 (씹히지 않게)
		if input_enabled and Input.is_action_just_pressed("attack_light") and attack_phase in ["land", "recovery"]:
			_attack_buffered = true
		_tick_plunge(delta, on_floor)


## ↓를 분명히 누르고 있는가 (DOWN_HOLD_STRENGTH 참고). 위·아래를 같이 누르면 아니다.
func _down_held() -> bool:
	return Input.get_action_raw_strength("move_down") - Input.get_action_raw_strength("move_up") >= DOWN_HOLD_STRENGTH


## 그 타의 스태미너가 있는가 (부동소수 찌꺼기 0.001 은 봐준다)
func _can_pay(step: int) -> bool:
	return guard + 0.001 >= light_cost_of(step)


func light_cost_of(step: int) -> float:
	return float(light_stamina_cost[clampi(step, 1, 3) - 1])


func light_startup_of(step: int) -> float:
	return float(light_startup[clampi(step, 1, 3) - 1])


func light_active_of(step: int) -> float:
	return float(light_active[clampi(step, 1, 3) - 1])


func light_recovery_of(step: int) -> float:
	return float(light_recovery[clampi(step, 1, 3) - 1])


## 3타 후딜레이 길이 (= 3타 되돌림)
var light_recovery_final: float:
	get: return light_recovery_of(3)


## 일반 공격 판정 상자 (소녀 가운데 기준, 오른쪽을 볼 때): 앞 30 부터 light_reach × 새순 '일반 공격' 범위 배율까지
func light_box() -> Rect2:
	var front := light_reach * Progress.skill_range_mult("normal")
	return Rect2(LIGHT_BOX_BACK, LIGHT_BOX_TOP, front - LIGHT_BOX_BACK, LIGHT_BOX_H)


## 씨앗 베기 판정 상자: 앞쪽 끝만 새순 '씨앗' 범위 배율로 (뒤·위·아래는 그대로)
func seed_slash_box() -> Rect2:
	var front := slash_box.end.x * Progress.skill_range_mult("seed")
	return Rect2(slash_box.position, Vector2(front - slash_box.position.x, slash_box.size.y))


## 수액의 맥동이 있으면 낙하 공격 판정 배율 (상자 가운데는 그대로)
func plunge_box_mult() -> float:
	return sap_pulse_plunge_box_mult if Progress.has_sap_pulse() else 1.0


func plunge_damage_mult() -> float:
	return sap_pulse_plunge_damage_mult if Progress.has_sap_pulse() else 1.0


## 내려꽂는 동안의 판정 상자 / 착지 충격 판정 상자 (맥동이 있으면 가운데를 그대로 두고 1.15배)
func plunge_dive_box() -> Rect2:
	return _scaled_about_center(plunge_box, plunge_box_mult())


func plunge_land_box_now() -> Rect2:
	return _scaled_about_center(plunge_land_box, plunge_box_mult())


static func _scaled_about_center(r: Rect2, k: float) -> Rect2:
	if is_equal_approx(k, 1.0):
		return r
	var sz := r.size * k
	return Rect2(r.get_center() - sz * 0.5, sz)


## 끊긴 스태미너 회복이 다시 시작되기까지의 기다림 (초): base, 수액의 숨결이 있으면 ×0.75 (음수가 되지 않게)
func regen_delay(base: float) -> float:
	return maxf(base * (sap_breath_delay_mult if Progress.has_sap_breath() else 1.0), 0.0)


## 자연 회복 빠르기 (초당): 28, 수액의 맥동이 있으면 ×1.1
func stamina_regen_rate() -> float:
	return guard_regen * (sap_pulse_regen_mult if Progress.has_sap_pulse() else 1.0)


## 3타 후딜레이가 남은 시간 (초, 0 이면 없음)
func combo_lock_left() -> float:
	return _combo_lock_timer


## 음높이를 정해 트는 소리 (1·2·3타 휘두름). Sfx.play 는 음높이를 받지 않으므로 소녀가 자기 플레이어 둘을 번갈아 쓴다.
## Sfx 안쪽은 건드리지 않고, Sfx 주석의 약속대로 bus = Sfx.BUS 라서 설정의 효과음 음량을 그대로 따른다.
## 플레이어는 처음 틀 때 한 번만 만들고 소리 파일은 한 번 읽어 둔다 (휘두를 때마다 새로 만들지 않는다).
const PITCHED_PLAYERS := 2
var _pitched_players: Array[AudioStreamPlayer] = []
var _pitched_next := 0
var _pitched_streams := {}


func _play_pitched(sfx_name: String, volume_db: float, pitch: float) -> void:
	var st: AudioStream = _pitched_streams.get(sfx_name)
	if st == null:
		var path: String = Sfx.DIR + sfx_name + ".wav"
		if not ResourceLoader.exists(path):
			return
		st = load(path)
		if st == null:
			return
		_pitched_streams[sfx_name] = st
	if _pitched_players.is_empty():
		for i in PITCHED_PLAYERS:
			var p := AudioStreamPlayer.new()
			p.name = "PitchedSfx%d" % i
			p.bus = Sfx.BUS
			p.process_mode = Node.PROCESS_MODE_ALWAYS   # Sfx 의 플레이어처럼 멈춤 화면이 떠도 끝까지 울린다
			add_child(p)
			_pitched_players.append(p)
	var ap := _pitched_players[_pitched_next]
	_pitched_next = (_pitched_next + 1) % _pitched_players.size()
	ap.stream = st
	ap.volume_db = volume_db
	ap.pitch_scale = pitch * (1.0 + randf_range(-0.03, 0.03))
	ap.play()


## 시험용: 가장 최근에 음높이를 정해 튼 소리 플레이어 (아직 없으면 null)
func last_pitched_player() -> AudioStreamPlayer:
	if _pitched_players.is_empty():
		return null
	return _pitched_players[(_pitched_next - 1 + _pitched_players.size()) % _pitched_players.size()]


func _start_light(step: int) -> void:
	attack_step = step
	attack_phase = "startup"
	_attack_timer = light_startup_of(step)
	_attack_buffered = false
	_chain_refused = false
	if step >= 3:
		_pulse_awarded = false
	# 스태미너는 시작하는 순간에 낸다 (부르는 쪽이 _can_pay 로 확인했다)
	guard = maxf(guard - light_cost_of(step), 0.0)
	guard_changed.emit(guard, max_guard)
	if input_enabled:
		var axis := Input.get_axis("move_left", "move_right")
		if absf(axis) > 0.3:
			facing = 1 if axis > 0.0 else -1
	_set_state(State.ATTACK)
	attacked.emit(step)


# ---------- 씨앗 베기 (처음부터 있는 영혼 기술) ----------

## 느리지만 넓은 베기. 땅에서는 멈춰 서서, 공중에서는 관성과 중력을 그대로 둔 채 벤다.
func _start_soul_slash() -> void:
	attack_step = 0
	attack_phase = "startup"
	_attack_timer = slash_startup
	# 쿨다운은 실제로 베는 순간(active)에 건다: 예비동작 중에 맞아 끊기면 바로 다시 쓸 수 있다
	if input_enabled:
		var axis := Input.get_axis("move_left", "move_right")
		if absf(axis) > 0.3:
			facing = 1 if axis > 0.0 else -1
	_set_state(State.SOUL_SLASH)
	# 함께 잠김은 누른 순간부터 (영혼별 쿨다운은 아래 타격 순간에 — 끊기면 둘 다 돌려준다)
	_slash_lock_prev = _set_soul_lock()
	soul_slash_started.emit()


func _tick_soul_slash(delta: float) -> void:
	_attack_timer -= delta
	match attack_phase:
		"startup":
			if _attack_timer <= 0.0:
				attack_phase = "active"
				_attack_timer = slash_active
				_soul_cooldowns["seed"] = slash_cooldown   # 예비동작 중에 영혼을 바꿔도 씨앗 쪽에 건다
				var hit := HitData.make(slash_damage * attack_multiplier * Progress.skill_damage_mult("seed"), slash_poise, self, slash_knockback)
				hit.from_player = true
				hit.hitstop = 0.08
				hit.soul = "seed"
				hitbox.set_box(seed_slash_box(), facing)
				hitbox.activate(hit, slash_active)
				Juice.shake(3.0)
				Juice.rumble(0.3, 0.5, 0.1)
		"active":
			if _attack_timer <= 0.0:
				attack_phase = "recovery"
				_attack_timer = slash_recovery
		"recovery":
			if _attack_timer <= 0.0:
				_set_state(State.IDLE)


# ---------- 낙하 공격 (공중에서 ↓ + 약공격) ----------

func _start_plunge() -> void:
	attack_step = 0
	attack_phase = "pause"
	_attack_timer = plunge_pause
	_attack_buffered = false
	velocity = Vector2(velocity.x * 0.2, 0.0)
	_set_state(State.PLUNGE)
	plunge_started.emit()


func _tick_plunge(delta: float, on_floor: bool) -> void:
	_attack_timer -= delta
	match attack_phase:
		"pause":
			velocity.y = 0.0   # 공중에 잠깐 멈춰 칼을 아래로 겨눈다
			if _attack_timer <= 0.0:
				attack_phase = "dive"
				velocity.y = plunge_speed
				# 바닥에 닿기 전 두 번째부터는 피해가 줄고 흐트러짐은 쌓이지 않는다 (적 위에서 튕기며 반복하는 것을 약하게)
				var ratio := plunge_repeat_ratio_of(_plunge_hits)
				var poise_ratio := 1.0 if _plunge_hits == 0 else plunge_repeat_poise_ratio
				# 수액의 맥동: 피해 ×1.3, 판정 ×1.15 (가운데 그대로)
				var hit := HitData.make(plunge_damage * plunge_damage_mult() * attack_multiplier * ratio, plunge_poise * poise_ratio, self, plunge_knockback)
				hit.from_player = true
				hit.hitstop = 0.06
				# 보스·중간 보스는 시간 창으로 거듭된 낙하 공격을 센다 (PlungeDecay) — 이 공중 연속 비율과 곱하지 않고 센 쪽 하나만 쓰게 알려 준다
				hit.plunge = true
				hit.plunge_chain_damage = ratio
				hit.plunge_chain_poise = poise_ratio
				hitbox.set_box(plunge_dive_box(), facing)
				hitbox.activate(hit, 10.0)   # 떨어지는 내내 켜 둔다 (맞히거나 착지하면 끈다)
		"dive":
			if on_floor:
				_plunge_land()
			else:
				velocity.y = plunge_speed   # 중력 없이 일정한 급강하
		"land":
			velocity.x = 0.0
			if _attack_timer <= 0.0:
				attack_phase = "recovery"
				_attack_timer = plunge_recovery
		"recovery":
			if _attack_buffered:
				_attack_buffered = false
				if _can_pay(1) and _combo_lock_timer <= 0.0:
					_start_light(1)
				else:
					stamina_refused.emit()
			elif _attack_timer <= 0.0:
				_set_state(State.IDLE)


## 바닥에 닿기 전에 이미 n 번 맞히고 튕겼을 때, 다음 낙하 공격의 피해 비율 (0 번이면 1)
func plunge_repeat_ratio_of(n: int) -> float:
	if n <= 0:
		return 1.0
	return pow(plunge_repeat_ratio, n) if plunge_repeat_compound else plunge_repeat_ratio


## 바닥에 꽂혔다: 넓고 낮은 충격 판정 + 흔들림.
func _plunge_land() -> void:
	attack_phase = "land"
	_attack_timer = plunge_land_time
	velocity = Vector2.ZERO
	var hit := HitData.make(plunge_land_damage * plunge_damage_mult() * attack_multiplier, plunge_land_poise, self, Vector2(380, -200))
	hit.from_player = true
	hit.hitstop = 0.04
	hit.plunge = true   # 착지 충격도 보스의 낙하 감쇠 창에서 센다 (PlungeDecay)
	hitbox.set_box(plunge_land_box_now(), facing)
	hitbox.activate(hit, plunge_land_time)
	Juice.shake(6.0)
	Juice.hitstop(0.04, 0.05)
	Juice.rumble(0.5, 0.9, 0.15)
	plunge_landed.emit()


## 떨어지다 적을 맞혔다: 작게 튕겨 오르고, 이단 점프가 있으면 공중 점프를 한 번 되돌려 준다 (연속 낙하 공격 가능).
## 이단 점프가 없는데 공중 점프를 '만들어' 주면 적을 발판 삼아 능력 관문(첫 방 천장 틈 등)을 건너뛸 수 있다 — 2026-10-18 검토.
func _plunge_bounce() -> void:
	velocity.y = plunge_bounce
	_jumps_left = maxi(_jumps_left, max_jumps - 1)
	_plunge_lock = plunge_relock
	_plunge_hits += 1
	_contact_grace = maxf(_contact_grace, CONTACT_GRACE_AFTER_LAND)
	_set_state(State.FALL)   # 바로 다음 프레임 _resolve_locomotion_state 가 JUMP/FALL 로 정리한다
	Juice.rumble(0.3, 0.6, 0.1)


func _handle_heal(on_floor: bool) -> void:
	if not input_enabled:
		return
	if Input.is_action_just_pressed("heal") and dews > 0 and on_floor and state in LOCOMOTION:
		dews -= 1
		dews_changed.emit(dews)
		_heal_timer = heal_time
		_set_state(State.HEAL)


func _handle_interact() -> void:
	if not input_enabled:
		return
	if Input.is_action_just_pressed("interact"):
		_interact_buffer = 0.25   # 공격이 끝나기 직전에 눌러도 기억했다가 실행
	if _interact_buffer > 0.0 and can_interact and state in LOCOMOTION:
		_interact_buffer = 0.0
		var best := pick_interactable()
		if best and best.has_method("interact"):
			best.interact(self)


## 손길 버튼이 고를 대상: 정화를 기다리는 적·보스(무너짐에는 제한 시간이 있다)가 먼저, 그다음은 가장 가까운 것.
## 터치 상황 버튼의 글자·그림도 이 값을 따른다 (2026-10-20 검수: 무너진 경비병 옆 포탈이 더 가까우면 정화 대신 방을 나갔고,
## 반대로 포탈이 목록에 있기만 하면 버튼이 '들어가기' 그림이었다).
func pick_interactable() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	var best_urgent := false
	for n in interactables:
		if not is_instance_valid(n):
			continue
		var urgent: bool = n is EnemyBase or (n as Node).is_in_group("boss")
		var d: float = global_position.distance_to(n.global_position)
		if (urgent and not best_urgent) or (urgent == best_urgent and d < best_d):
			best_d = d
			best = n
			best_urgent = urgent
	return best


## 보스의 날갯바람 등 바깥 힘. 매 물리 프레임 불러야 한다.
func apply_wind(force: float, _delta: float) -> void:
	if state == State.DEAD or state == State.REST or state == State.PURIFY:
		return
	_wind += force


## 가진 영혼들. '씨앗'은 처음부터 있고 늘 맨 앞.
func owned_souls() -> Array:
	var out := ["seed"]
	if Progress.has_ability("wind"):
		out.append("wind")
	if Progress.has_ability("light"):
		out.append("light")
	return out


func soul_name() -> String:
	match soul:
		"seed": return "씨앗 (세계수의 씨앗)"
		"wind": return "바람 (잿빛 잎새의 새)"
		"light": return "빛 (등불 기사)"
	return ""


## 영혼의 짧은 이름 (터치 버튼·HUD 용): 씨앗 / 바람 / 빛. 모르는 값은 그대로.
func soul_short_name(s := "") -> String:
	if s == "":
		s = soul
	return SOUL_INFO.get(s, {}).get("name", s)


## 전환 알림의 큰 글자: "바람의 영혼"
func soul_title(s := "") -> String:
	if s == "":
		s = soul
	return SOUL_INFO.get(s, {}).get("title", s)


## 전환 알림의 작은 설명 한 줄: "커다란 돌풍 — 멀리 날아가 크게 친다 / 쿨 5초"
func soul_desc(s := "") -> String:
	if s == "":
		s = soul
	var d: String = SOUL_INFO.get(s, {}).get("desc", "")
	if d == "":
		return ""
	return "%s / 쿨 %s초" % [d, _fmt_seconds(soul_cooldown_total(s))]


static func soul_color_of(s: String) -> Color:
	return SOUL_INFO.get(s, {}).get("color", Color.WHITE)


func soul_color(s := "") -> Color:
	return soul_color_of(soul if s == "" else s)


## 영혼 기술의 쿨다운 전체 길이 (초). 씨앗 1.4 / 바람 5 / 빛 7 — 바람·빛은 새순 단계만큼 짧아진다 (Progress.skill_cooldown_mult).
func soul_cooldown_total(s := "") -> float:
	if s == "":
		s = soul
	match s:
		"seed": return slash_cooldown
		"wind": return gust_cooldown * Progress.skill_cooldown_mult("wind")
		"light": return light_shot_cooldown * Progress.skill_cooldown_mult("light")
	return 0.0


## 남은 쿨다운 (초). 0 이면 쓸 수 있다. 비우면 지금 고른 영혼 (쿨다운은 영혼마다 따로 센다).
## 영혼별 쿨다운과 함께 잠김(soul_shared_lockout) 가운데 긴 쪽 — HUD·터치 버튼·입력이 모두 이 값을 본다.
func soul_cooldown_left(s := "") -> float:
	if s == "":
		s = soul
	return maxf(float(_soul_cooldowns.get(s, 0.0)), soul_lock_left())


## 그 영혼 자신의 남은 쿨다운만 (함께 잠김 빼고).
func soul_own_cooldown_left(s := "") -> float:
	if s == "":
		s = soul
	return float(_soul_cooldowns.get(s, 0.0))


## 함께 잠김 남은 시간 (초). 0 이면 잠기지 않았다.
func soul_lock_left() -> float:
	return float(_soul_cooldowns.get(SOUL_LOCK_KEY, 0.0))


## 영혼 기술을 썼다: 모든 영혼 기술을 soul_shared_lockout 초 함께 잠근다. 앞의 남은 값을 돌려준다 (끊겼을 때 되돌리려고).
func _set_soul_lock() -> float:
	var prev := soul_lock_left()
	_soul_cooldowns[SOUL_LOCK_KEY] = maxf(prev, soul_shared_lockout)
	return prev


## 쓰다 끊긴 기술의 함께 잠김을 돌려준다 (prev = 걸기 전 남은 값; 그 사이 흐른 시간만큼은 prev 도 줄어 있다).
func _refund_soul_lock(prev: float) -> void:
	var set_to := maxf(prev, soul_shared_lockout)
	var restored := soul_lock_left() - (set_to - prev)
	_soul_cooldowns[SOUL_LOCK_KEY] = restored if restored > COOLDOWN_EPS else 0.0


## 남은 비율 (1 = 방금 씀, 0 = 준비됨). 그 영혼 자신의 쿨다운이 남았으면 제 길이로 나누므로 호가 멈추지 않고 차오르고,
## 함께 잠김이 더 길면 잠김 길이(soul_shared_lockout)로 나눠 꽉 찬 호가 짧게 줄어든다. 씨앗 베기를 휘두르는 중(예비동작)에는 꽉 찬 호
## (타격 순간에 제 쿨 1.4초가 걸린다 — 그 사이 잠김 호가 줄었다 다시 차오르지 않게).
func soul_cooldown_ratio(s := "") -> float:
	if s == "":
		s = soul
	if s == "seed" and state == State.SOUL_SLASH and attack_phase == "startup":
		return 1.0
	var own := soul_own_cooldown_left(s)
	var lock := soul_lock_left()
	if lock > own and soul_shared_lockout > 0.0:
		return clampf(lock / soul_shared_lockout, 0.0, 1.0)
	var total := soul_cooldown_total(s)
	if total <= 0.0 or own <= 0.0:
		return 0.0
	return clampf(own / total, 0.0, 1.0)


## 터치 버튼·HUD 에 보이는 남은 초: "7", "6", … "1". 준비됐으면 "" ('0' 은 나오지 않는다).
func soul_cooldown_text(s := "") -> String:
	var left := soul_cooldown_left(s)
	if left <= 0.0:
		return ""
	return str(maxi(1, ceili(left - COOLDOWN_EPS)))


## 다음 영혼 (전환 버튼이 띠는 색을 고를 때). 영혼이 하나뿐이면 "".
func next_soul() -> String:
	var owned := owned_souls()
	if owned.size() <= 1:
		return ""
	var i := owned.find(soul)
	return owned[(i + 1) % owned.size()]


static func _fmt_seconds(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(int(roundf(v)))
	return "%.1f" % v


## 영혼 기술. I / K / L2 / R2 (강공격 자리). 영혼 전환은 Q / 십자키 ← →.
func _handle_soul(_on_floor: bool) -> void:
	if not input_enabled:
		return
	var owned := owned_souls()
	if owned.size() > 1 and (Input.is_action_just_pressed("soul_next") or Input.is_action_just_pressed("soul_prev")):
		var i := owned.find(soul)
		var step := 1 if Input.is_action_just_pressed("soul_next") else -1
		soul = owned[(i + step + owned.size()) % owned.size()]
		Progress.soul = soul   # 방을 옮겨도(소녀가 새로 만들어져도) 고른 영혼이 남게
		soul_changed.emit(soul)
	if soul == "":
		return
	# 약공격 되돌림 중에도 이어 쓸 수 있다 (가드·구르기와 같은 허용: 3연타 → 영혼 기술 연계). 단 3타 후딜레이 동안은 안 된다.
	var can_cast := (state in LOCOMOTION or state == State.GUARD or (state == State.ATTACK and attack_phase == "recovery")) and _combo_lock_timer <= 0.0
	if Input.is_action_just_pressed("soul_ability") and soul_cooldown_left() <= 0.0 and can_cast:
		cast_soul_skill()


## 지금 고른 영혼의 기술을 쓴다 (쿨다운·상태 검사는 부르는 쪽이 한다. 시험 도구도 부른다).
func cast_soul_skill() -> void:
	match soul:
		"seed":
			_start_soul_slash()
		"wind", "light":
			_cast_projectile()


## 바람(새의 영혼) = 초승달 검기 / 빛(기사의 영혼) = 레이저.
func _cast_projectile() -> void:
	if soul == "light":
		_cast_laser()
	else:
		_cast_wind()


## 바람의 영혼: 앞으로 날아가는 초승달 검기 (WindCrescent — 예전 바람 투사체와 같은 바탕, 그림·판정 모양만 새것)
func _cast_wind() -> void:
	var p: Projectile = WIND_CRESCENT.new()
	_soul_cooldowns["wind"] = soul_cooldown_total("wind")
	_set_soul_lock()
	_guard_regen_delay = maxf(_guard_regen_delay, regen_delay(stamina_regen_delay_after_shot))   # 쏜 뒤 0.7초(숨결 0.525)는 스태미너가 차지 않는다
	p.speed = gust_speed
	p.damage = gust_damage * attack_multiplier * Progress.skill_damage_mult("wind")
	p.poise = gust_poise
	p.lifetime = gust_range_time
	p.size = gust_size
	p.color = Color(0.8, 1.0, 0.85)
	get_parent().add_child(p)
	# 생기는 자리 (2026-10-19 검토): 판정 사각형(size×0.9)의 뒤끝이 소녀 가운데에서 SHOT_BACK_REACH 만큼 뒤에 오도록
	# 크기 절반만큼 앞으로 민다 (등 뒤의 적을 덮지 않게).
	var origin := global_position + Vector2(0.0, -20.0)
	var ahead := maxf(50.0, p.size.x * 0.45 - SHOT_BACK_REACH)
	# 벽에 붙어 쏘면 생기는 자리가 벽 속·벽 너머가 되지 않게 소녀 가운데에서 선을 그어 본다. 투사체는 처음 두 프레임 안에
	# 벽에 닿으면 적을 맞힐 틈 없이 사라지므로 그만큼 더 본다.
	var reach := ahead + p.speed * 2.0 / float(Engine.physics_ticks_per_second)
	var ray := PhysicsRayQueryParameters2D.create(origin, origin + Vector2(facing * reach, 0.0), 1)
	var space := get_world_2d().direct_space_state
	var wall := space.intersect_ray(ray)
	# 한쪽 방향 가지는 검기가 지나가므로(WindCrescent.pass_one_way) 벽으로 치지 않는다
	var skip := 0
	while not wall.is_empty() and skip < 4 and wall.get("collider") is Platform and wall["collider"].one_way:
		ray.exclude = ray.exclude + [wall["rid"]]
		wall = space.intersect_ray(ray)
		skip += 1
	if wall.is_empty():
		p.global_position = origin + Vector2(facing * ahead, 0.0)
	else:
		# 벽 바로 앞에 놓는다: 투사체는 첫 프레임에 벽에 닿아 사라지고(부서지는 벽이면 한 대 친다),
		# 소녀와 벽 사이에 낀 적은 여기서 바로 한 번 맞힌다.
		var wall_x: float = wall["position"].x
		p.global_position = Vector2(wall_x - facing * 2.0, origin.y)
		_point_blank_hit(p, origin, wall_x)
	p.launch(Vector2(facing, 0), self, true)
	gust_cast.emit()
	# 한 방이 큰 기술이 됐으니 쏘는 손맛도 크게 (2026-10-19): 흔들림 6, 진동, 아주 짧은 히트스톱
	Juice.shake(6.0)
	Juice.rumble(0.45, 0.8, 0.14)
	Juice.hitstop(0.03, 0.2)


## 빛의 영혼: 레이저 (SoulLaser). 쿨다운은 지금 건다 — 모으는 동안 끊기면 돌려준다.
func _cast_laser() -> void:
	_soul_cooldowns["light"] = soul_cooldown_total("light")
	var lock_prev := _set_soul_lock()
	_guard_regen_delay = maxf(_guard_regen_delay, regen_delay(stamina_regen_delay_after_shot))   # 쏜 뒤 0.7초(숨결 0.525)는 스태미너가 차지 않는다
	var l: SoulLaser = SOUL_LASER.new()
	l.player = self
	l.facing = facing
	l.damage = light_shot_damage * attack_multiplier * Progress.skill_damage_mult("light")
	l.poise = light_shot_poise
	l.beam_range = light_beam_range()
	l.width = light_shot_size.y * 0.9
	l.charge_time = light_charge_time
	l.show_time = light_beam_time
	l.active_time = light_beam_active
	l.cancelled.connect(func():
		_soul_cooldowns["light"] = 0.0
		_refund_soul_lock(lock_prev))
	l.fired.connect(_on_laser_fired)
	get_parent().add_child(l)
	laser_charge_started.emit()


## 레이저 사거리 (소녀 가운데에서): 예전 빛 투사체가 날아가던 거리
func light_beam_range() -> float:
	return light_shot_speed * light_shot_time


func _on_gust_cast_sfx() -> void:
	if soul == "wind":
		Sfx.play("gust", -6.0)
		Sfx.play("sword_wave", -9.0, 0.05)


func _on_laser_fired(hits: int) -> void:
	laser_fired.emit(hits)
	gust_cast.emit()   # 뼈대의 반동 (소리는 laser_fired 쪽)
	Juice.shake(6.0)
	Juice.rumble(0.45, 0.8, 0.14)
	Juice.hitstop(0.03, 0.2)


## 벽에 바짝 붙어 쏜 바람·빛: 소녀 뒤 SHOT_BACK_REACH 부터 벽까지, 투사체 판정 높이의 사각형 안의 적 하나를 바로 맞힌다
## (투사체가 맞혔을 때와 같은 피해·흐트러짐·밀기). 투사체는 벽에서 곧바로 사라지므로 두 번 맞지 않는다.
func _point_blank_hit(p: Projectile, origin: Vector2, wall_x: float) -> void:
	var back_x := origin.x - facing * SHOT_BACK_REACH
	var w := absf(wall_x - back_x)
	if w < 1.0:
		return
	var rect := RectangleShape2D.new()
	rect.size = Vector2(w, p.size.y * 0.9)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = rect
	q.transform = Transform2D(0.0, Vector2((back_x + wall_x) * 0.5, origin.y))
	q.collision_mask = 16   # 적 맞는 영역
	q.collide_with_areas = true
	q.collide_with_bodies = false
	for r in get_world_2d().direct_space_state.intersect_shape(q, 16):
		var area = r.get("collider")
		if area is Hurtbox:
			var hit := HitData.make(p.damage, p.poise, self, Vector2(260, -100))
			hit.guardable = p.guardable
			hit.from_player = true
			hit.hitstop = 0.04
			if area.receive(hit) != "ignored":
				return


## 어두운 방에서 소녀 주변을 밝힌다 (티아의 등불은 희미하게, 기사의 영혼이 깃들면 넓게).
func set_light(on: bool) -> void:
	if on and _light == null:
		_light = PointLight2D.new()
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 512
		gt.height = 512
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1, 0.5)
		_light.texture = gt
		_light.color = Color(1.0, 0.85, 0.6)
		_light.position = Vector2(0, -40)
		add_child(_light)
		_apply_abilities()
	elif _light:
		_light.enabled = on


func _handle_jump(on_floor: bool) -> void:
	if _buffer_timer > 0.0 and state in LOCOMOTION:
		# ↓를 분명히 누른 채 점프: 발밑이 한쪽 방향 발판이면 점프 대신 통과해 내려간다 (하단 점프)
		if on_floor and input_enabled and _down_held() and _try_drop_through():
			return
		if on_floor or _coyote_timer > 0.0:
			_do_jump(false)
		elif _jumps_left > 0:
			_do_jump(true)


## 발밑 지형이 one_way 발판(Platform.one_way)이면 잠깐 충돌을 끄고 떨어진다. 성공하면 true.
func _try_drop_through() -> bool:
	# 아래로 살짝 밀어 보아 막는 몸을 찾는다 (한쪽 방향 발판도 위에서 내려갈 때는 막으므로 잡힌다)
	var col := move_and_collide(Vector2(0, 6), true)
	if col == null:
		return false
	var body := col.get_collider()
	if not (body is Platform and body.one_way):
		return false
	if _drop_body and is_instance_valid(_drop_body) and _drop_body != body:
		remove_collision_exception_with(_drop_body)
	_drop_body = body
	add_collision_exception_with(body)
	_drop_timer = drop_through_time
	_buffer_timer = 0.0
	_coyote_timer = 0.0
	_jumps_left = maxi(max_jumps - 1, 0)   # 코요테 없음: 땅 점프는 쓴 것으로 (이단 점프는 남는다)
	velocity.y = maxf(velocity.y, 160.0)
	_set_state(State.FALL)
	dropped_through.emit(body)
	return true


func _end_drop_through() -> void:
	_drop_timer = 0.0
	if _drop_body and is_instance_valid(_drop_body):
		remove_collision_exception_with(_drop_body)
	_drop_body = null


func _handle_horizontal(delta: float, on_floor: bool, move_input: float) -> void:
	match state:
		State.ROLL:
			velocity.x = facing * roll_speed * roll_factor
		State.ATTACK, State.SOUL_SLASH:
			# 땅에서는 멈춰 서서 벤다. 공중에서는 관성 그대로.
			if on_floor:
				velocity.x = move_toward(velocity.x, 0.0, ground_decel * 0.8 * delta)
		State.PLUNGE:
			velocity.x = move_toward(velocity.x, 0.0, 3000.0 * delta)
		State.GUARD:
			velocity.x = move_toward(velocity.x, move_input * walk_speed * guard_move_ratio, ground_accel * delta)
			# 가드 중에는 방향을 바꾸지 않는다 (정면만 막는다)
		_:
			var target_speed := move_input * (run_speed if (is_running and absf(move_input) > 0.5) else walk_speed) * slow_factor
			var accel := air_accel
			if on_floor:
				accel = ground_accel if absf(move_input) > 0.05 else ground_decel
			velocity.x = move_toward(velocity.x, target_speed, accel * delta)
			if absf(move_input) > 0.05:
				facing = 1 if move_input > 0.0 else -1


func _resolve_locomotion_state() -> void:
	if not (state in LOCOMOTION):
		return
	if not is_on_floor():
		_set_state(State.JUMP if velocity.y < 0.0 else State.FALL)
	elif absf(velocity.x) > 20.0:
		_set_state(State.RUN if (is_running and absf(velocity.x) > walk_speed + 10.0) else State.WALK)
	else:
		_set_state(State.IDLE)


func _do_jump(air_jump: bool) -> void:
	velocity.y = -_jump_velocity
	_buffer_timer = 0.0
	_coyote_timer = 0.0
	_jumps_left -= 1
	_set_state(State.JUMP)
	jumped.emit(air_jump)


func _try_roll(on_floor: bool) -> void:
	if _roll_cooldown_timer > 0.0:
		return
	var can := state in LOCOMOTION or state == State.GUARD \
		or ((state == State.ATTACK or state == State.SOUL_SLASH) and attack_phase == "recovery")
	if not can or not (on_floor or _coyote_timer > 0.0):
		return
	# 구르기 스태미너 15: 모자라면 구르지 않는다 (막대 붉은 번쩍임 + 짧은 소리)
	if roll_stamina_cost > 0.0:
		if guard + 0.001 < roll_stamina_cost:
			stamina_refused.emit()
			return
		guard = maxf(guard - roll_stamina_cost, 0.0)
		guard_changed.emit(guard, max_guard)
	hitbox.deactivate()
	_roll_timer = roll_duration
	velocity.y = 0.0
	_set_state(State.ROLL)
	roll_started.emit()


func _wants_to_leave_rest() -> bool:
	return Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("dodge") \
		or absf(Input.get_axis("move_left", "move_right")) > 0.5


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	if state in ATTACK_STATES:
		hitbox.deactivate()
	if state in NO_REGEN_STATES and not (new_state in NO_REGEN_STATES):
		# 공격·영혼 기술·낙하 공격·가드에서 벗어났다: 짧게 기다린 뒤부터 스태미너가 찬다
		_guard_regen_delay = maxf(_guard_regen_delay, regen_delay(stamina_regen_delay_after_action))
	if state == State.SOUL_SLASH and attack_phase == "startup":
		# 예비동작 중에 끊긴 씨앗 베기: 쿨다운이 아직 안 걸렸듯 함께 잠김도 돌려준다
		_refund_soul_lock(_slash_lock_prev)
	state = new_state
	if not (new_state in ATTACK_STATES):
		attack_step = 0
		attack_phase = ""
	if not (new_state in ATTACK_STATES or new_state in LOCOMOTION):
		# 맞거나 구르거나 회복하는 등 흐름이 끊기면 기억해 둔 낙하 버튼은 버린다 (맞고 난 뒤 저절로 내리꽂지 않게)
		_plunge_btn_buffered = false
	state_changed.emit(new_state)


# ---------- 맞기 ----------

## Hurtbox 가 부른다. 결과: "hit" / "guard" / "just_guard" / "guard_break" / "dodge" / "ignored"
func receive_hit(hit: HitData, _hurtbox: Hurtbox) -> String:
	# v1.1.0: 적·보스 능력치 배율(기본 +45% × 던전 단계 × 난이도)은 여기 한 곳에서 (HitData 원본은 고치지 않는다 — 같은 객체를 여럿이 받는다)
	var dmg := Balance.incoming_damage(hit, self)
	if state == State.DEAD or state == State.PURIFY or state == State.REST:
		return "ignored"
	if _invuln_timer > 0.0:
		return "ignored"
	if state == State.ROLL and _roll_timer > roll_duration * (1.0 - roll_invuln_ratio):
		return "dodge"
	var from_dir := 1
	if hit.source:
		from_dir = 1 if hit.source.global_position.x >= global_position.x else -1
	var from_front := from_dir == facing

	if state == State.GUARD and hit.guardable and from_front:
		if hit.parryable and _now() - _guard_pressed_at <= just_guard_window:
			_guard_pressed_at = -1000.0
			Juice.hitstop(0.1, 0.03)
			Juice.rumble(0.4, 1.0, 0.18)
			Juice.shake(7.0)
			just_guarded.emit(hit.source)
			if hit.source and hit.source.has_method("on_just_guarded"):
				hit.source.on_just_guarded(self, just_guard_poise)
			return "just_guard"
		guard -= dmg * guard_drain_ratio
		hp = maxf(hp - dmg * guard_damage_ratio, 0.0)
		hp_changed.emit(hp, max_hp)
		velocity.x = -facing * 160.0
		Juice.hitstop(0.03, 0.1)
		Juice.rumble(0.2, 0.4, 0.08)
		_guard_regen_delay = regen_delay(stamina_regen_delay_after_block)
		if guard <= 0.0:
			guard = 0.0
			guard_changed.emit(guard, max_guard)
			_guard_regen_delay = regen_delay(stamina_regen_delay_after_break)
			_hit_timer = guard_break_stun
			_set_state(State.HIT)
			guard_broken.emit()
			Juice.shake(8.0)
			return "guard_break"
		guard_changed.emit(guard, max_guard)
		guard_hit.emit(dmg)   # 보호막 충격 고리 + 막는 소리
		return "guard"

	hp = maxf(hp - dmg, 0.0)
	hp_changed.emit(hp, max_hp)
	hit_taken.emit(dmg)
	velocity = Vector2(-from_dir * absf(hit.knockback.x), hit.knockback.y)
	_hit_timer = hit_stun
	_invuln_timer = invuln_time_boss if boss_fight else invuln_time
	hitbox.deactivate()
	Fx.spawn("hit_spark", _hurt_point(hit, from_dir), {"facing": -from_dir, "palette": "red", "scale": 0.85})   # 맞은 자리에 붉은 불꽃
	Juice.hitstop(hit.hitstop, 0.05)
	Juice.rumble(0.5, 0.8, 0.15)
	Juice.shake(6.0)
	if hp <= 0.0:
		_die()
	else:
		_set_state(State.HIT)
	return "hit"


## 맞은 자리 (붉은 피격 불꽃): 때린 쪽 판정 상자가 켜져 있고 소녀 몸과 겹치면 그 겹친 곳의 가운데,
## 아니면(투사체·몸통 부딪힘) 몸통에서 때린 쪽으로 조금 (2026-10-20 검수: 몹에게 맞아도 소녀 몸에 이펙트가 없었다).
func _hurt_point(hit: HitData, from_dir: int) -> Vector2:
	var body := Rect2(global_position + Vector2(-25.0, -66.0), Vector2(50.0, 132.0))
	var at := global_position + Vector2(from_dir * 18.0, -16.0)
	var src := hit.source
	if src and is_instance_valid(src):
		var hb = src.get("hitbox")
		if hb is Hitbox and is_instance_valid(hb) and hb._active and hb._shape and hb._shape.shape is RectangleShape2D:
			var sz: Vector2 = (hb._shape.shape as RectangleShape2D).size
			var r := Rect2(hb._shape.global_position - sz * 0.5, sz)
			var ov := r.intersection(body)
			if ov.has_area():
				at = ov.get_center()
				at.y = clampf(at.y, global_position.y - 50.0, global_position.y + 30.0)
	return at


## ---- 타격 연출 미루기 (2026-10-20 검수) ----
## 약공격·씨앗 베기는 판정이 켜지는 첫 틱에 이미 겹친 적을 맞히는데, 그때 칼은 아직 몸 뒤(휘두름의 6%)라
## 불꽃이 칼보다 먼저 뜨고 히트스톱이 그 틀린 장면을 멈춰 보여 줬다. 그래서 피해·흐트러짐·튕김·밀려남은 그대로 즉시,
## 불꽃·타격음·히트스톱·흔들림·진동(+ 그림의 반동, 신호 hit_impact)만 칼끝이 대상 쪽으로 지나갈 때까지 미룬다
## (칼끝이 몸 앞 IMPACT_TIP_FRONT px 또는 대상 x 를 넘으면, 늦어도 IMPACT_WAIT_MAX 초 뒤·공격이 끊기면 바로).
const IMPACT_WAIT_MAX := 0.1
const IMPACT_TIP_FRONT := 60.0
var _impacts: Array = []   # {"result", "target", "at", "big", "palette", "plunge_land", "dx", "t"}


func _on_hit_landed(result: String, target: Node) -> void:
	if result != "hit" and result != "blocked":
		hit_impact.emit(result, target)   # (막힘 "guard" 등 — 그림의 반동은 바로)
		return
	# 불꽃 색: 씨앗 베기 초록, 일반 공격 청록 (v1.1.0 칼자국과 같은 색), 낙하 공격은 그림 원래 색
	var pal := "seed" if state == State.SOUL_SLASH else ("teal" if state == State.ATTACK else "")
	var imp := {"result": result, "target": target, "at": _hit_fx_point(target),
		"big": state == State.SOUL_SLASH or state == State.PLUNGE, "palette": pal,
		"plunge_land": state == State.PLUNGE and attack_phase == "land", "dx": INF, "t": 0.0}
	if target is Node2D and is_instance_valid(target):
		imp["dx"] = ((target as Node2D).global_position.x - global_position.x) * facing
	if (state == State.ATTACK or state == State.SOUL_SLASH) and not _blade_past(imp):
		_impacts.append(imp)
	else:
		_impact_feel(imp)
	if result == "hit":
		_try_sap_pulse(target)
		# 낙하 공격으로 적을 맞혔다: 튕겨 오른다 (떨어지는 중에만. 착지 충격은 그대로)
		if state == State.PLUNGE and attack_phase == "dive":
			_plunge_bounce()
	elif result == "blocked":
		# 방패에 튕겼다: 살짝 밀려난다
		velocity.x = -facing * 260.0
		blocked.emit()
		if state == State.PLUNGE and attack_phase == "dive":
			_plunge_bounce()


## 수액의 맥동 (수액의 여왕 패시브): 3타가 적·보스에게 닿으면 스태미너를 즉시 채운다. 3타 한 번에 한 번만 (여러 적을 맞혀도).
## 자연 회복 막기(공격 중·후딜레이)와 상관없이 바로 더한다. 금 간 벽·비밀 벽·지형은 적이 아니므로 세지 않는다.
func _try_sap_pulse(target: Node) -> void:
	if _pulse_awarded or state != State.ATTACK or attack_step != 3 or not Progress.has_sap_pulse():
		return
	if not _is_foe(target):
		return
	_pulse_awarded = true
	var before := guard
	guard = minf(guard + sap_pulse_stamina, max_guard)
	guard_changed.emit(guard, max_guard)
	stamina_pulsed.emit(guard - before)


static func _is_foe(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return target is EnemyBase or target.is_in_group("boss") or target.has_method("reset_fight")


## 칼끝(그림)이 이미 대상 쪽으로 지나갔는가 (그림이 없으면 늘 지나간 것으로)
func _blade_past(imp: Dictionary) -> bool:
	var vis := get_node_or_null("Visual")
	if vis == null or not vis.has_method("sword_point"):
		return true
	var tip: Vector2 = vis.to_global(vis.sword_point(112.0))
	var tip_dx := (tip.x - global_position.x) * facing
	return tip_dx >= minf(IMPACT_TIP_FRONT, float(imp["dx"]))


## 미룬 타격 연출: 매 물리 틱 칼끝을 보고 낸다
func _tick_impacts(delta: float) -> void:
	if _impacts.is_empty():
		return
	var attacking := state == State.ATTACK or state == State.SOUL_SLASH
	var keep: Array = []
	for imp in _impacts:
		imp["t"] = float(imp["t"]) + delta
		if not attacking or float(imp["t"]) >= IMPACT_WAIT_MAX or _blade_past(imp):
			_impact_feel(imp)
		else:
			keep.append(imp)
	_impacts = keep


## 타격 연출 (불꽃·소리·히트스톱·흔들림·진동)
func _impact_feel(imp: Dictionary) -> void:
	var result: String = imp["result"]
	_spawn_hit_fx_at(imp["at"], result, bool(imp["big"]), str(imp["palette"]))
	if result == "hit":
		# 낙하 공격 착지 충격은 착지음(plunge_landed → heavy_hit)이 이미 났으니 타격음을 또 내지 않는다
		if not bool(imp["plunge_land"]):
			Sfx.play("heavy_hit" if bool(imp["big"]) else "hit", -3.0, 0.1)
		Juice.hitstop(0.05, 0.05)
		Juice.rumble(0.25, 0.5, 0.08)
		Juice.shake(3.0)
	else:
		Juice.rumble(0.1, 0.2, 0.06)
	var t: Node = imp["target"] if is_instance_valid(imp["target"]) else null
	hit_impact.emit(result, t)


## 칼이 닿은 자리: 판정 상자 안에서 상대 쪽으로
func _hit_fx_point(target: Node) -> Vector2:
	var box := _hitbox_world_rect()
	var at := box.get_center()
	if target is Node2D and is_instance_valid(target):
		at.x = clampf((target as Node2D).global_position.x, box.position.x, box.end.x)
		at.x = lerpf(at.x, box.get_center().x, 0.25)
	return at


## 칼이 닿은 자리에 불꽃 (큰 공격은 큰 불꽃, 방패에 막히면 하얀 고리)
func _spawn_hit_fx_at(at: Vector2, result: String, big: bool, palette: String) -> void:
	if result == "blocked":
		Fx.spawn("ring_pop", at, {"facing": facing, "palette": "white", "scale": 0.8})
		return
	Fx.spawn("hit_spark_big" if big else "hit_spark", at, {"facing": facing, "palette": palette})


## 지금 판정 상자 (세계 좌표)
func _hitbox_world_rect() -> Rect2:
	var cs: CollisionShape2D = hitbox._shape
	if cs == null or not (cs.shape is RectangleShape2D):
		return Rect2(global_position, Vector2.ZERO)
	var sz: Vector2 = (cs.shape as RectangleShape2D).size
	return Rect2(hitbox.global_position + cs.position - sz * 0.5, sz)


## 적의 몸통 부딪힘을 지금 받지 않는가 (낙하 공격으로 튕긴 직후). EnemyBase._tick_contact 가 묻는다.
func has_contact_grace() -> bool:
	return _contact_grace > 0.0


func _die() -> void:
	_set_state(State.DEAD)
	hitbox.deactivate()
	died.emit()


## 포자 등 조금씩 깎이는 피해 (경직 없음).
func take_damage_over_time(amount: float) -> void:
	if state == State.DEAD or state == State.REST:
		return
	hp = maxf(hp - amount, 0.0)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		_die()


## 가시나 낭떠러지: 피해를 입고 마지막 안전한 자리로 돌아온다.
func take_hazard(damage: float) -> void:
	if state == State.DEAD or _invuln_timer > 0.0:
		return
	hp = maxf(hp - damage, 0.0)
	hp_changed.emit(hp, max_hp)
	hit_taken.emit(damage)
	Juice.hitstop(0.08, 0.05)
	Juice.rumble(0.5, 0.8, 0.2)
	Juice.shake(7.0)
	Sfx.play("thorn")
	hitbox.deactivate()
	if hp <= 0.0:
		_die()
		return
	_invuln_timer = 1.2
	_hit_timer = 0.5
	_set_state(State.HIT)   # 낙하 공격 중이었어도 여기서 끝난다
	velocity = Vector2.ZERO
	input_enabled = false
	await get_tree().create_timer(0.35).timeout
	if state == State.DEAD:
		return
	global_position = last_safe_position if last_safe_position != Vector2.ZERO else global_position
	_safe_history.clear()
	_safe_sample_timer = 0.0
	velocity = Vector2.ZERO
	var cam := get_node_or_null("Camera2D")
	if cam:
		cam.reset_smoothing()
	input_enabled = true


## 방을 옮길 때 앞 방의 체력·이슬을 이어 받는다 (v1.1.0 기획자 요청 13: 방 이동으로는 회복하지 않는다).
## 체력은 1 아래로 내려가지 않는다 (방에 들어서자마자 쓰러지지 않게).
func set_vitals(new_hp: float, new_dews: int) -> void:
	hp = clampf(new_hp, 1.0, max_hp)
	dews = clampi(new_dews, 0, max_dews)
	hp_changed.emit(hp, max_hp)
	dews_changed.emit(dews)


## 방이 부른다: 마지막 달빛풀에서 다시 일어난다.
func revive(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	hp = max_hp
	guard = max_guard
	dews = max_dews
	_invuln_timer = 1.0
	_combo_lock_timer = 0.0
	_chain_refused = false
	last_safe_position = at
	_end_drop_through()
	_plunge_lock = 0.0
	_plunge_buffered = false
	_plunge_btn_buffered = false
	_plunge_hits = 0
	_set_state(State.IDLE)
	hp_changed.emit(hp, max_hp)
	guard_changed.emit(guard, max_guard)
	dews_changed.emit(dews)


# ---------- 상호작용 ----------

func register_interactable(node: Node2D) -> void:
	if not interactables.has(node):
		interactables.append(node)
		interactables_changed.emit(can_interact)


func unregister_interactable(node: Node2D) -> void:
	if interactables.has(node):
		interactables.erase(node)
		interactables_changed.emit(can_interact)


## 정화의 손길: 무릎 꿇은 적에게 손을 얹는다.
func start_purify(target: Node2D) -> void:
	if state == State.PURIFY or state == State.DEAD:
		return
	purify_target = target
	facing = 1 if target.global_position.x >= global_position.x else -1
	velocity = Vector2.ZERO
	_set_state(State.PURIFY)
	purify_started.emit(target)
	await get_tree().create_timer(0.45).timeout
	if state != State.PURIFY:
		return
	Juice.hitstop(0.12, 0.02)
	Juice.rumble(0.3, 0.7, 0.3)
	Juice.shake(4.0)
	purified.emit(target)
	if is_instance_valid(target) and target.has_method("purified_by"):
		target.purified_by(self)
	await get_tree().create_timer(0.7).timeout
	if state == State.PURIFY:
		_set_state(State.IDLE)


## 달빛풀에서 쉰다.
func start_rest(grass: Node2D) -> void:
	if state == State.DEAD:
		return
	velocity = Vector2.ZERO
	facing = 1 if grass.global_position.x >= global_position.x else -1
	hp = max_hp
	guard = max_guard
	dews = max_dews
	hp_changed.emit(hp, max_hp)
	guard_changed.emit(guard, max_guard)
	dews_changed.emit(dews)
	_set_state(State.REST)
	rest_started.emit(grass)


func state_name() -> String:
	match state:
		State.IDLE: return "대기"
		State.WALK: return "걷기"
		State.RUN: return "달리기"
		State.JUMP: return "점프"
		State.FALL: return "낙하"
		State.ROLL: return "구르기"
		State.ATTACK: return "약공격 %d" % attack_step
		State.SOUL_SLASH: return "씨앗 베기"
		State.PLUNGE: return "낙하 공격"
		State.GUARD: return "가드"
		State.HIT: return "피격"
		State.HEAL: return "회복"
		State.PURIFY: return "정화의 손길"
		State.REST: return "쉬는 중"
		State.DEAD: return "쓰러짐"
	return "?"


func jump_velocity() -> float:
	return _jump_velocity


func jump_gravity() -> float:
	return _jump_gravity


func is_invulnerable() -> bool:
	return _invuln_timer > 0.0

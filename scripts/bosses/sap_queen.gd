extends CharacterBody2D
class_name SapQueen
## 확장판 보스 '수액의 여왕' (EXPANSION.md 3장). 말라 가는 호수를 홀로 지키던 나비 정령. 날아다니는 보스.
## **3박자 리듬**: 모든 패턴이 '하나(예고)·둘(준비)·셋(공격)'으로 온다. 보스곡(boss_sap_queen, 3/4 138bpm)과 박자가 맞는다:
##   한 박 BEAT = 60/138 = 0.435초, 예고 2박(0.87초) 뒤 셋째 박에 공격. 패턴은 마디 첫 박에서 시작한다(메트로놈 _clock).
##   **기획자의 정식 곡을 잰 값** (tools/measure_tempo.gd, 2026-10-19): 137.99bpm(=138), 3/4 (낮은 음 시작점이 세 박마다 2.2배 셈),
##   첫 강박 0.123초(DOWNBEAT), 216.56초 동안 박 자리 어긋남 8ms 아래. 시계 0 = 곡의 첫 강박. 곡 한 바퀴는 166마디(216.52초)로
##   펼쳐서(loop_span) 반복해 처음으로 돌아가도 박자 격자가 곡의 강박에 다시 맞는다 (넘어가는 순간 시계가 0.04초 기다림).
##   **메트로놈은 보스곡의 재생 위치를 따라간다** (Music.playback_time). 히트스톱·일시정지 동안에도 음악은 흐르므로 보스가 음악에
##   맞춘다: 예고·공격·내려앉음의 끝은 모두 '시계 몇 초'로 정해 두고(_phase_end), 일시정지처럼 시계가 크게 건너뛰면 남은 예정을
##   마디 단위로 미룬다(_shift_deadlines — 멈춘 사이 공격이 지나가 버리거나 풀자마자 맞지 않게). 곡이 없으면 실제 시간으로 센다.
## 패턴 (전부 가드 가능 — 붉은 예고는 없다):
##   DUST        날개가루: 셋째 박에 반짝이는 가루를 부채꼴로 흩뿌린다 (구르기로 피함)
##   WAVE        수액 물결: 수면 가까이 내려와 셋째 박에 물결을 띄운다 (점프로 넘김)
##   BUTTERFLIES 나비 떼: 작은 수액 나비 3(2페이즈 5)마리가 쫓아온다 — **저스트 가드로 되받으면** 여왕에게 돌아가 흐트러짐이 쌓인다
##               (한 마리 = 저스트 가드 45 + 되받은 나비 28 + REFLECT_POISE 0 = 73 → 세 마리째에 무너짐)
##   LAND        춤추듯 내려앉기: 둘째 박 끝에 내려꽂기 시작해 **셋째 박에 정확히** 디딤돌에 앉고(착지 충격) LANDED_BEATS 박 동안 쉰다
##               — **반격의 기회**(땅에서 때릴 수 있음)
## 공중에선 받는 피해 AIR_DAMAGE_RATIO 배 (되받은 나비는 온전히). 무너지면(흐트러짐 가득) 섬으로 내려와 BROKEN.
## 2페이즈(체력 절반): CRACK(한 마디: 날개 갈라짐·수액 흘러내림) → 디딤돌 일부가 가라앉고(방의 Terrain/Sink*), 박자가 엇나간다
##   (예고 길이 ±20%, 가끔 반 박 빠르게), 가루·나비가 는다. 무너진 채 2페이즈로 넘어가면 흐트러짐은 0 으로 돌아간다.
## 체력 0 → FALLEN(섬으로 내려앉음) → 정화 → 회상 memory_queen → 수액 위 걷기(sap_walk).
## BossRoom 과의 약속: start_fight / reset_fight / arena / ground_y / hover_points / fallen / purified / hp_changed / poise_changed /
##   phase_changed / telegraph(kind) / telegraph_label(kind) / state_name() / debug_log / is_ground() / receive_hit / hp / poise / phase / facing.

enum State { WAIT, INTRO, HOVER, DUST, WAVE, BUTTERFLIES, LAND, LANDED, TAKEOFF, CRACK, BROKEN, FALLEN, PURIFIED }
const ATTACK_STATES := [State.DUST, State.WAVE, State.BUTTERFLIES, State.LAND]
const AIR_STATES := [State.HOVER, State.DUST, State.WAVE, State.BUTTERFLIES, State.LAND, State.TAKEOFF, State.CRACK]

signal hp_changed(hp: float, max_hp: float)
signal poise_changed(poise: float, max_poise: float)
signal phase_changed(phase: int)
signal state_changed(state: State)
signal fallen
signal purified
signal telegraph(kind: String)
## 박이 바뀔 때 (0 하나, 1 둘, 2 셋) — 그림·시험이 듣는다
signal beat(index: int)

## 박자 (보스곡 138bpm, 3/4 — 정식 곡에서 잰 값 137.99bpm)
const BEAT := 60.0 / 138.0
const BAR := BEAT * 3.0
## 보스곡의 첫 강박(마디 첫 박)이 곡 안에서 몇 초에 오는가 (정식 곡에서 잰 값). 메트로놈 시계 0 이 이 자리.
const DOWNBEAT := 0.123
## 내려앉아 쉬는 길이(박)와 무너진 길이
const LANDED_BEATS := 6.0
## 되받은 나비 한 마리에 덧붙는 흐트러짐 (저스트 가드 45 와 되받은 나비 자체의 28 은 따로 들어간다 → 지금 한 마리 73).
## 2026-10-19 검토: 35 였을 때 한 마리 108 이라 두 마리면 바로 무너졌다 → 0. 더 세게 하려면 10~20.
const REFLECT_POISE := 0.0
## 공중에서 받는 피해 배수
const AIR_DAMAGE_RATIO := 0.5
## 공중에서 받는 흐트러짐 배수 (되받은 나비는 온전히). v1.1.0 최종 검수(맞딜 방지): 땅에서 씨앗 베기만 쿨마다 쓰며 점프로 물결을 흘리는 봇이
## 물결을 띄우려 내려온(WAVE_DIP)·날아오르는 여왕을 베어 공중에서도 흐트러짐 60 씩 쌓아 싸움의 4분의 1 을 무너진(피해 ×2) 여왕으로 보냈다
## (18판 중 3판 봇 승). 공중의 여왕을 무너뜨리는 길은 나비 되받기(EXPANSION 3장) — 그 길은 그대로 두고 다른 공격만 0.7배
## (0.5 면 봇 18판 모두 지지만 무적 '잘하는 봇'의 잡는 시간이 약 +20%, 0.7 이면 봇 18판 모두 지고(가장 아슬한 판 여왕 체력 18%) 약 +13%).
const AIR_POISE_RATIO := 0.7
## 하늘에 머무는 높이 (디딤돌 윗면에서 위로). 몸 중심은 그림 위치(-120)만큼 더 위.
## 2026-10-19 검토: 640 이면 싸움 카메라 화면 맨 위(왼쪽 위 체력 HUD 뒤)에 들어가 가려졌다 → 400 (몸 중심이 바닥 위 520, 새와 비슷).
const HOVER_HEIGHT := 400.0
## 내려앉기의 내려꽂는 시간 (초). 셋째 박보다 이만큼 먼저 내려오기 시작해 셋째 박에 딱 앉는다.
const LAND_DIVE := 0.2
## 시계가 이보다 크게 건너뛰면(일시정지 등) 남은 예정을 마디 단위로 미룬다
const SYNC_SNAP := 0.25
## 박자를 맞출 보스곡
const TRACK := "boss_sap_queen"
## 내려앉을 수 있는 디딤돌의 최소 폭 (작은 바위는 고르지 않는다)
const LAND_MIN_WIDTH := 300.0
## 물결을 띄우려 내려오는 높이 (수면에서 위로)
const WAVE_DIP := 170.0
## 내려앉기 착지 충격 판정 (Hitbox 노드 = 발밑 기준, 좌우 같음). v1.1.0: 공격 범위 예고·이펙트가 이 값을 그대로 쓴다.
const LAND_BOX := Rect2(-170, -70, 340, 90)
## 맞딜 방지 계량기 (v1.1.0): 내려앉은 동안 이 거리 안에 붙어 있으면 쌓인다 (다 차면 아래 수액 터뜨리기).
## 다 찬 채 하늘에 있으면 다음 패턴은 소녀에게 가장 가까운 돌로 내려앉기 (지금은 내려앉은 동안만 쌓이고 차는 즉시 터뜨려 거의 오지 않는다).
const CROWD_RANGE := 280.0
## 쌓임 한도 (초). v1.1.0 에서는 2.5초(내려앉음 6박 = 2.61초의 끝에 걸려 응징이 거의 나오지 않았고, 응징은 날아올라 수액 물결 —
## 반격 창을 잘랐다). v1.1.0 맞딜 검수 2 (영혼 기술 함께 잠김을 걷고 그 대신): 1.5초 — 다음 박에 '수액 터뜨리기'(앉은 채로 몸 둘레
## BURST_BOX 를 두 번 친다, 왈츠에 맞춰 하나·둘 예고 → 셋에 첫 번째, 두 박 뒤 두 번째; 가드·저스트 가드 가능, 예고 사각형 = 판정 = 물보라).
## 그동안 여왕은 앉아 있다 (땅에서 때릴 수 있는 반격 창은 그대로 — 내려앉음은 두 번째 터뜨림 한 박 뒤까지 늘어난다).
## 터뜨리기는 내려앉음마다 한 번 (_burst_done — 곁에 붙어 있으면 터뜨리기를 거듭하며 땅에 눌러앉았다).
const LANDED_CROWD_TRIGGER := 1.5
## 계량기가 '붙어 있다'로 세는 소녀의 높이 (여왕 발밑에서 소녀 가운데까지, px). v1.1.0 맞딜 검수 2: 내려앉은 몸 둘레에서 제자리 점프·이단 점프로
## 떠 있으며 영혼 기술을 쏟는 소녀(공중 영혼 봇)도 센다 — 기본 300 은 점프 꼭대기를 놓쳐 그 봇에게는 터뜨리기가 거의 오지 않았다 (기사·뿌리지기와 같은 520).
const CROWD_MAX_UP := 520.0
## 수액 터뜨리기 판정 (Hitbox 노드 = 발밑 기준, 좌우 같음): 몸 둘레 ±320 (계량기 범위 280 + 소녀 몸 절반), 발밑에서 위로 560 —
## 계량기가 세는 높이(소녀 가운데 520)의 소녀 몸에 닿는다 (몸 둘레에 떠 있는 소녀도). 예고·물보라 이펙트가 이 사각형을 그대로 쓴다.
const BURST_BOX := Rect2(-320, -560, 640, 580)
const BURST_PULSES := 2
## 높은 자리 계량기 (v1.1.0 맞딜 검수, PerchMeter): 소녀가 디딤돌 위 200 넘게 높은 곳(가지 위·그 높이의 공중)에 PERCH_TRIGGER 초 머물면
## 다음 패턴은 '가지 나비 떼' — 여왕이 소녀 머리 위 비스듬한 자리(가로 PERCH_SIDE, 위 PERCH_ABOVE)로 올라가 나비를 PERCH_EXTRA 마리 더 풀어
## 내려보낸다. 박자·예고(하나·둘 → 셋)는 보통 나비 떼와 같고, 나비 판정 = 보이는 그림, 전부 가드 가능 — **저스트 가드로 되받으면** 보통 나비처럼
## 여왕에게 돌아가 흐트러짐이 쌓인다(기술의 보상 그대로). 가지에서 내려와 디딤돌·섬에서 싸우면 오지 않는다.
## (가지 위에서 원거리 영혼만 쏘는 봇이 6판 중 5~6판 이겼다 — 물결은 수면에만, 착지는 디딤돌에만 닿았다. 가지로 내려앉는 응징은
##  여왕을 소녀 눈높이로 데려와 오히려 더 빨리 잡혔다 → 소녀의 수평 원거리 줄 밖(머리 위)에서 쏟는다)
const PERCH_TRIGGER := 1.8
const PERCH_SIDE := 260.0
const PERCH_ABOVE := 360.0
const PERCH_EXTRA := 2

@export_group("능력치")
@export var max_hp := 1300.0
@export var max_poise := 170.0
@export var poise_decay := 8.0
@export var broken_time := 5.0
@export var broken_damage_multiplier := 1.6
## 무너졌다 날아오른 뒤 이 시간(초) 동안은 흐트러짐이 쌓이지 않는다 (v1.1.0 맞딜 방지 — 기사·뿌리지기와 같은 규칙.
## 되받은 나비는 기술의 보상이라 그대로)
@export var poise_immune_after_broken := 2.5
## 그냥 때려서 무너뜨렸을 때의 무너짐 길이 (초). v1.1.0 맞딜 검수 2 (영혼 기술 함께 잠김을 걷고 그 대신): 흐트러짐의 skill_break_share
## (4분의 1) 이상이 되받은 나비·저스트 가드(기술)에서 왔으면 broken_time(5초)·피해 1.6배 그대로, 아니면(씨앗·바람·빛·약공격만 쏟아
## 무너뜨림) 이 길이·brute_broken_damage_multiplier. 저스트 가드 한 번(45)이면 기술 몫 4분의 1(42.5)을 넘는다 — 나비를 되받거나 공격을
## 저스트 가드로 받아 내는 사람은 온전한 무너짐을 받고, 패턴을 무시하고 맞으며 쏟기만 하는 길은 짧은 비틀거림만 받는다.
## (영혼을 쏟는 봇이 내려앉은 여왕을 0.3초 만에 무너뜨리고 5초 × 1.6배를 두 번 받아 18판 중 6~11판, 공중 영혼 봇이 2.6초로도 2판을 이겼다.
##  1.6초 + 기술 몫 4분의 1: 공중 영혼 1판(봇 체력 27%) — 잘하는 봇은 기술 몫 절반 규칙일 때보다 빨라졌다)
@export var brute_broken_time := 1.6
## 그냥 때려서 무너뜨렸을 때 무너진 동안 받는 피해 배수 (기술로 무너뜨리면 broken_damage_multiplier 1.6 그대로).
## 내려앉자마자 바람·빛·씨앗을 한꺼번에 쏟는 봇은 무너진 첫 0.5초에 1.6배 × 세 기술로 여왕 체력의 3분의 1을 깎았다.
@export var brute_broken_damage_multiplier := 1.0
## 이번 무너짐의 피해 배수 (무너질 때 정한다)
var _broken_mult := 1.6

@export_group("패턴")
@export var dust_damage := 14.0
@export var dust_count := 10
@export var wave_damage := 18.0
@export var wave_speed := 540.0
@export var butterfly_damage := 14.0
@export var butterfly_count := 3
@export var butterfly_speed := 560.0
@export var land_damage := 14.0
@export var hover_speed := 5.0
@export var gravity := 2600.0

@export_group("움직임 연출")
@export var face_deadzone := 80.0
@export var face_hold := 0.35

var state: State = State.WAIT
var hp := 1300.0
var poise := 0.0
var phase := 1
var facing := -1
var player: Player
var arena: Rect2
var hover_points: Array = []
var ground_y := 0.0
var surface_y := 0.0

## 그림이 읽는 공개 값
var attack_phase := ""          # startup / active / recovery (아니면 "")
var windup_progress := 0.0
var startup_len := BEAT * 2.0
var active_len := BEAT
var recovery_len := BEAT
var telegraph_amount := 0.0     # 예고 동안 0→1
var crack_amount := 0.0         # 2페이즈 날개 갈라짐 (CRACK 에서 0→1, 그 뒤 1)
var dive_amount := 0.0          # 내려앉기의 내려꽂기 진행도 (0→1, 그림이 몸을 길게 늘인다)
var reflected_count := 0
var _landed_touch := false      # 내려앉기·무너짐·쓰러짐에서 실제로 땅에 닿았는가

var _timer := 0.0
var _clock := 0.0               # 싸움 시작부터의 메트로놈 (0 = 보스곡의 첫 강박 DOWNBEAT). 보스곡 재생 위치를 따른다
var _next_at := 0.0             # 다음 패턴을 시작할 시계 시각 (마디 첫 박)
var _phase_end := 0.0           # 지금 박자 단계(예고·공격·되돌림·내려앉음·갈라짐)가 끝나는 시계 시각
var _music_prev := -1.0         # 보스곡 재생 위치 (지난 프레임, 반복 넘김을 알아채려고)
var _music_loops := 0           # 보스곡이 몇 번 돌았나
var _music_synced := false      # 이번 싸움에서 보스곡 위치를 한 번이라도 읽었나
var _music_lost := false        # 보스곡을 따라갈 수 없게 됨 (곡이 다시 시작됨 등) → 실제 시간으로 센다
var _diving := false
var _dive_from := Vector2.ZERO
var _pattern_index := 0
var _hover_target := Vector2.ZERO
var _glide_target := Vector2.ZERO
var _poise_hold := 0.0
var _flash := 0.0
var _registered := false
var _home := Vector2.ZERO
var _bob_t := 0.0
var _face_hold := 0.0
var _land_stone: Node2D
var _stones: Array = []
var _stone_home := {}
var _sunk := false
var _spawned := 0
var _last_beat := -1
var _rng := RandomNumberGenerator.new()
var debug_log := false
## 공격 범위 예고 / 맞딜 방지 계량기 (v1.1.0)
var _tel: RangeTelegraph
var crowd := CrowdMeter.new(CROWD_RANGE, LANDED_CROWD_TRIGGER)
## 수액 터뜨리기: 다음 터뜨림 시각(박자 시계) / 남은 횟수 / 지금까지 터뜨린 횟수(이펙트 관찰자가 센다)
var _burst_at := -1.0
var _burst_left := 0
var burst_count := 0
## 이번 내려앉음에 이미 수액 터뜨리기를 했나 (내려앉음마다 한 번 — 곁에 붙어 서 있으면 터뜨리기를 거듭하며 땅에 눌러앉던 것을 막는다:
## 저스트 가드로 터뜨리기를 받아 내며 땅의 여왕을 끝없이 때릴 수 있었다. 터뜨린 뒤 남은 내려앉음엔 계량기가 쌓이지 않는다)
var _burst_done := false
## 낙하 공격 감쇠 시계 (v1.1.0 최종 검수 — 앞 낙하 공격 뒤 4초 안에 또 맞으면 피해 ×0.6^n·흐트러짐 ×0.5^n; scripts/combat/plunge_decay.gd)
var plunge_decay := PlungeDecay.new()
## 높은 자리 계량기 (v1.1.0 맞딜 검수) / 지금 나비 떼가 가지 나비 떼(높은 자리 응징)인가 / 그때 여왕이 머무는 자리
var perch := PerchMeter.new(PERCH_TRIGGER)
var _perch_volley := false
var _perch_pos := Vector2.ZERO
## 지금 공격이 맞딜 응징인가 (응징 공격 동안은 흐트러짐이 쌓이지 않는다 — 되받은 나비는 그대로)
var punishing := false
var _poise_immune := 0.0
## 지금 흐트러짐 가운데 기술(되받은 나비·저스트 가드)에서 온 몫. 흐트러짐이 줄면 함께 줄어든다 (넘지 않게).
var _skill_poise := 0.0
## 흐트러짐 가운데 기술 몫이 이 비율 이상이면 온전한 무너짐(broken_time·1.6배), 아니면 brute_broken_time·brute_broken_damage_multiplier.
## (절반이던 때 잘하는 봇의 무너짐 48번 가운데 39번이 기술 몫 0.26~0.46 이라 짧은 무너짐을 받아 잡는 시간이 +16% 였다 → 4분의 1)
var skill_break_share := 0.25
var _state_started_ms := 0

@onready var sprite: Sprite2D = $Sprite
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox

const SAP_PROJECTILE := preload("res://scenes/combat/sap_projectile.tscn")
const SAP_WAVE := preload("res://scenes/combat/sap_wave.tscn")


func _ready() -> void:
	crowd.max_up = CROWD_MAX_UP
	add_to_group("boss")
	add_child(preload("res://scripts/fx/sap_queen_fx.gd").new())   # 이펙트 리뉴얼 F2: 기술 이펙트 (판정과 무관)
	_tel = RangeTelegraph.attach(self)
	# v1.1.0 체력 배율: 보스가 놓인 방의 던전 단계 1.1^단계 × 난이도 (새·수관 ×1). reset_fight 는 max_hp 를 읽는다.
	max_hp *= Balance.hp_mult(Balance.region_of(self))
	hp = max_hp
	_home = global_position
	set_collision_mask_value(1, false)
	visible = false
	# 씨앗은 전역 우연에서 받는다 (게임에선 시작할 때마다 다르고, 시험이 seed(n) 을 주면 같은 판이 그대로 되풀이된다 —
	# 예전 randomize() 는 시험의 seed 를 무시해 맞딜 시험 결과가 판마다 달랐다)
	_rng.seed = randi()


## 방이 싸움을 시작시킨다. (디딤돌·수면은 방에서 찾는다: Terrain/Sink* 발판, SapPool)
func start_fight(p: Player) -> void:
	player = p
	visible = true
	_find_room_parts()
	global_position = Vector2(arena.get_center().x, arena.position.y - 200)
	_clock = 0.0
	_music_prev = -1.0
	_music_loops = 0
	_music_synced = false
	_music_lost = false
	_pattern_index = 0
	reflected_count = 0
	_set_state(State.INTRO)
	_timer = BAR * 2.0
	_hover_target = _hover_point(1)


func _find_room_parts() -> void:
	var room := get_parent()
	if room == null:
		return
	_stones.clear()
	var terrain := room.get_node_or_null("Terrain")
	if terrain:
		for c in terrain.get_children():
			if String(c.name).begins_with("Sink") and c is Node2D:
				_stones.append(c)
				if not _stone_home.has(c):
					_stone_home[c] = c.position
	surface_y = ground_y + 60.0
	for c in room.get_children():
		if c is SapPool:
			surface_y = c.surface_y()
			break


## 소녀가 쓰러졌을 때: 처음 상태로. 가라앉은 디딤돌도 되돌린다.
func reset_fight() -> void:
	_unregister()
	hp = max_hp
	poise = 0.0
	_skill_poise = 0.0
	phase = 1
	crack_amount = 0.0
	dive_amount = 0.0
	_diving = false
	telegraph_amount = 0.0
	reflected_count = 0
	visible = false
	velocity = Vector2.ZERO
	set_collision_mask_value(1, false)
	hitbox.deactivate()
	crowd.reset()
	_burst_done = false
	perch.reset()
	_perch_volley = false
	plunge_decay.reset()
	_tel.clear()
	_poise_immune = 0.0
	_raise_stones()
	global_position = _home
	_set_state(State.WAIT)
	hp_changed.emit(hp, max_hp)
	poise_changed.emit(poise, max_poise)


func _hover_point(i: int) -> Vector2:
	var x := arena.get_center().x
	if hover_points.size() > i:
		x = hover_points[i].x
	return Vector2(x, ground_y - HOVER_HEIGHT)


func _random_hover() -> Vector2:
	if hover_points.is_empty():
		return _hover_point(0)
	return _hover_point(_rng.randi() % hover_points.size())


# ---------- 박자 ----------
## 지금 박의 번호 (0 하나, 1 둘, 2 셋)
func beat_index() -> int:
	return int(floorf(_clock / BEAT)) % 3


## 지금 박 안의 진행도 0→1
func beat_phase() -> float:
	return fmod(_clock, BEAT) / BEAT


## t 이후의 첫 마디 첫 박
func _next_bar_after(t: float) -> float:
	return ceilf(t / BAR - 0.0001) * BAR


## 지금 박자 단계가 끝날 때까지 남은 시간 (시계 기준, 음수면 지났다)
func _left() -> float:
	return _phase_end - _clock


## 보스곡 재생 위치 → 박자 시계 (초): 첫 강박이 0, 반복은 loops 바퀴만큼 펼친다 (한 바퀴 = loop_span).
static func clock_from_music(raw: float, loops := 0, length := 0.0) -> float:
	return raw - DOWNBEAT + loops * loop_span(length)


## 곡 한 바퀴를 박자 시계로 몇 초로 칠까: 곡 길이에 가장 가까운 온 마디 수.
## 곡이 처음으로 돌아가면 다시 첫 강박부터 시작하므로, 격자도 온 마디 뒤에서 이어져야 박자가 맞는다 (정식 곡: 216.56초 → 166마디 216.52초).
static func loop_span(length: float) -> float:
	var bars := roundf(length / BAR)
	return bars * BAR if bars >= 1.0 else length


## 보스곡의 박자 시계 값(초, 반복을 펼친 값). 보스곡이 안 흐르면 NAN.
## 곡이 처음부터 다시 시작된 것 같으면(반복 넘김이 아닌데 1초 넘게 뒤로 감) 이번 싸움은 실제 시간으로 센다(_music_lost).
func _music_clock() -> float:
	var raw: float = Music.playback_time(TRACK)
	if raw < 0.0:
		_music_prev = -1.0
		return NAN
	var length: float = Music.current_length()
	if _music_prev >= 0.0:
		if length > 1.0 and raw < _music_prev - length * 0.5:
			_music_loops += 1   # 곡이 한 바퀴 돌아 처음으로 넘어갔다
		elif raw < _music_prev - 1.0:
			_music_lost = true
			return NAN
	_music_prev = raw
	return clock_from_music(raw, _music_loops, length)


## 메트로놈을 한 프레임 진행한다: 보스곡이 흐르면 그 위치를 따르고(음악이 주인), 아니면 실제 시간(히트스톱의 느려짐을 뺀
## 시간)으로 센다. 음악 위치가 잠깐 뒤로 출렁이면(소리 장치의 덩어리 단위 갱신) 시계는 멈춰 기다린다 — 뒤로 가지는 않는다.
func _advance_clock(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.0001)
	var expected := _clock + real_dt
	var next := expected
	if not _music_lost:
		var m := _music_clock()
		if not is_nan(m):
			if not _music_synced:
				_music_synced = true
				# 곡이 한참 늦게 시작됐다(시계가 이미 멀리 앞섬): 따라가려면 오래 멈춰야 하니 이번 싸움은 실제 시간으로
				if m < _clock - SYNC_SNAP:
					_music_lost = true
			if not _music_lost:
				next = maxf(m, _clock)
	var jump := next - expected
	if jump > SYNC_SNAP:
		# 일시정지(메뉴·지도) 동안 음악만 흘렀다: 시계는 음악을 따라 건너뛰고, 남은 예정은 마디 단위로 미뤄
		# 박자는 맞춘 채 멈춘 사이 공격이 지나가 버리거나 풀자마자 맞지 않게 한다
		_shift_deadlines(ceilf(jump / BAR) * BAR)
	_clock = maxf(next, _clock)


func _shift_deadlines(by: float) -> void:
	_next_at += by
	_phase_end += by


func _physics_process(delta: float) -> void:
	if state == State.WAIT or state == State.PURIFIED:
		return
	_advance_clock(delta)
	var b := beat_index()
	if b != _last_beat:
		_last_beat = b
		beat.emit(b)
	_flash = maxf(_flash - delta * 6.0, 0.0)
	plunge_decay.tick(delta)
	_poise_hold = maxf(_poise_hold - delta, 0.0)
	if _poise_hold <= 0.0 and poise > 0.0 and state not in [State.BROKEN, State.FALLEN, State.CRACK]:
		poise = maxf(poise - poise_decay * delta, 0.0)
		_skill_poise = minf(_skill_poise, poise)
		poise_changed.emit(poise, max_poise)
	_timer -= delta
	_bob_t += delta
	_face_hold = maxf(_face_hold - delta, 0.0)
	_poise_immune = maxf(_poise_immune - delta, 0.0)
	if attack_phase != "startup":
		telegraph_amount = maxf(telegraph_amount - delta * 4.0, 0.0)
	if player:
		# 맞딜 방지: 내려앉은 동안(땅에서 때릴 수 있을 때)만 쌓인다
		crowd.tick(delta, global_position, player.global_position, state == State.LANDED and not _burst_done, facing)
		# 높은 자리: 공격할 수 있는 동안(하늘·패턴·내려앉음) 소녀가 가지 높이에 머물면 쌓인다 (무너짐·갈라짐·가지 나비 떼 중은 아님)
		perch.tick(delta, ground_y, player, state in [State.HOVER, State.DUST, State.WAVE, State.BUTTERFLIES, State.LANDED, State.TAKEOFF, State.LAND] \
			and not _perch_volley)
	if player and state in [State.HOVER, State.DUST, State.BUTTERFLIES, State.LANDED, State.INTRO, State.TAKEOFF]:
		var dx := player.global_position.x - global_position.x
		var want := 1 if dx > 0.0 else -1
		if want != facing and absf(dx) > face_deadzone and _face_hold <= 0.0:
			facing = want
			_face_hold = face_hold

	match state:
		State.INTRO:
			_fly_toward(_hover_target, delta, 2.5)
			if _timer <= 0.0:
				_set_state(State.HOVER)
				_next_at = _next_bar_after(_clock)
		State.HOVER:
			_fly_toward(_hover_target, delta, hover_speed)
			if _clock >= _next_at:
				_next_pattern()
		State.DUST:
			_fly_toward(_hover_target, delta, hover_speed * 0.6)
			_phase_step(delta, func() -> void: _scatter_dust())
			if phase == 2 and attack_phase == "active" and _spawned == 1 and _left() <= active_len * 0.5:
				_spawned = 2
				_scatter_dust()   # 2페이즈: 반 박 뒤 한 번 더
		State.WAVE:
			# 하나·둘 동안 수면 가까이 내려온다, 셋에 물결, 되돌림에 다시 떠오른다
			var dip := Vector2(global_position.x, surface_y - WAVE_DIP)
			if attack_phase == "startup":
				_fly_toward(dip, delta, 4.0)
			elif attack_phase == "active":
				_fly_toward(dip + Vector2(0, -20), delta, 6.0)
			else:
				_fly_toward(_hover_target, delta, 3.0)
			_phase_step(delta, func() -> void: _launch_waves())
		State.BUTTERFLIES:
			if _perch_volley:
				_fly_toward(_perch_pos, delta, hover_speed * 0.8)   # 가지 위 소녀의 머리 위 비스듬한 자리 (소녀의 수평 원거리 줄 밖)
			else:
				_fly_toward(_hover_target + Vector2(0, 120), delta, hover_speed * 0.5)
			_phase_step(delta, func() -> void: _release_butterflies())
		State.LAND:
			_land_step(delta)
		State.LANDED:
			_ground(delta)
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			# 맞딜 방지: 내려앉은 몸에 붙어 버티는 소녀에게 수액 터뜨리기 (v1.1.0 의 '날아올라 수액 물결'은 맞딜 검수 2 에서 바꿈 — 반격 창을 잘랐다).
			# 박자 규칙: 터뜨림은 박 위에서 (하나·둘 예고 → 셋), 둘째는 두 박 뒤.
			if _burst_left > 0:
				if _clock >= _burst_at:
					_sap_burst()
					_burst_left -= 1
					if _burst_left > 0:
						_burst_at += BEAT * 2.0
						_tel.show_rect(burst_reach(), false, BEAT * 2.0)
					else:
						punishing = false   # 응징이 끝났다 — 남은 내려앉음은 다시 무너뜨릴 수 있는 빈틈
			elif crowd.ready() and not _burst_done:
				# 맞딜 방지 (v1.1.0 맞딜 검수 2): 내려앉은 몸에 붙어 버티는 소녀에게 — 다음 박부터 하나·둘 예고, 셋에 수액 터뜨리기 (내려앉음마다 한 번)
				crowd.consume()
				_burst_done = true
				_burst_at = ceilf(_clock / BEAT - 0.0001) * BEAT + BEAT * 2.0
				_burst_left = BURST_PULSES
				punishing = true
				telegraph.emit("burst")
				_tel.show_rect(burst_reach(), false, maxf(_burst_at - _clock, 0.05))
				# 반격 창이 터뜨림에 먹히지 않게: 마지막 터뜨림 한 박 뒤까지 앉아 있다
				_phase_end = maxf(_phase_end, _burst_at + BEAT * 2.0 * (BURST_PULSES - 1) + BEAT)
			elif _left() <= 0.0:
				_begin_takeoff()
		State.TAKEOFF:
			set_collision_mask_value(1, false)
			_fly_toward(_hover_target, delta, 3.0)
			if _timer <= 0.0:
				_set_state(State.HOVER)
				_next_at = _next_bar_after(_clock)
		State.CRACK:
			velocity = velocity.move_toward(Vector2.ZERO, 2000.0 * delta)
			velocity.y = sin(_bob_t * 30.0) * 60.0
			crack_amount = clampf(1.0 - _left() / BAR, 0.0, 1.0)
			if _left() <= 0.0:
				crack_amount = 1.0
				_set_state(State.HOVER)
				_hover_target = _random_hover()
				_next_at = _next_bar_after(_clock)
		State.BROKEN:
			_settle(delta)
			if _timer <= 0.0:
				poise = 0.0
				_skill_poise = 0.0
				poise_changed.emit(poise, max_poise)
				_poise_immune = poise_immune_after_broken
				_begin_takeoff()
		State.FALLEN:
			_settle(delta)
			_update_interactable()
	move_and_slide()


# ---------- 움직임 ----------
func _fly_toward(target: Vector2, delta: float, k: float) -> void:
	var bob := Vector2(0, sin(_bob_t * 2.0) * 16.0)
	var to := (target + bob) - global_position
	velocity = to * k


func _ground(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0
		_landed_touch = true


## 섬(글라이드 목표)으로 미끄러져 내려와 앉는다 (무너짐·쓰러짐).
func _settle(delta: float) -> void:
	if not _landed_touch:
		var to := _glide_target - global_position
		if absf(to.x) > 20.0 or to.y > 40.0:
			velocity = Vector2(clampf(to.x * 3.0, -700.0, 700.0), clampf(to.y * 3.0, -200.0, 900.0))
			set_collision_mask_value(1, to.y < 80.0 and absf(to.x) < 120.0)
		else:
			set_collision_mask_value(1, true)
			_ground(delta)
	else:
		set_collision_mask_value(1, true)
		_ground(delta)
		velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)


# ---------- 패턴 고르기 ----------
func _next_pattern() -> void:
	var order: Array = [State.DUST, State.WAVE, State.BUTTERFLIES, State.LAND] if phase == 1 \
		else [State.DUST, State.BUTTERFLIES, State.WAVE, State.DUST, State.BUTTERFLIES, State.LAND]
	var next: State = order[_pattern_index % order.size()]
	var perch_volley := false
	if crowd.ready():
		# 맞딜 방지 (v1.1.0): 계량기가 찬 채 하늘에 있다 → 소녀에게 가장 가까운 돌로 내려앉는다 (착지 충격)
		crowd.consume()
		next = State.LAND
		punishing = true
	elif perch.ready() and player:
		# 높은 자리 응징 (v1.1.0 맞딜 검수): 가지 위 소녀의 머리 위로 올라가 나비를 더 풀어 내려보낸다 (가드·저스트 가드로 되받기)
		perch.consume()
		next = State.BUTTERFLIES
		perch_volley = true
	else:
		_pattern_index += 1
	_hover_target = _random_hover()
	var startup := BEAT * 2.0
	if phase == 2:
		# 춤이 무너진다: 예고 길이 ±20%, 가끔 반 박 빠르게
		startup *= _rng.randf_range(0.8, 1.2)
		if _rng.randf() < 0.25:
			startup = BEAT * 1.5
	_spawned = 0
	# 예정된 마디 첫 박에서 센다 (한 프레임 늦게 알아채도 셋째 박은 음악과 맞게)
	var t0 := _next_at if _clock - _next_at < BEAT * 0.5 else _clock
	match next:
		State.DUST:
			_begin(State.DUST, t0, startup, BEAT, BEAT)
		State.WAVE:
			telegraph.emit("wave")
			_begin(State.WAVE, t0, startup, BEAT, BEAT * 2.0)
		State.BUTTERFLIES:
			telegraph.emit("butterflies")
			_begin(State.BUTTERFLIES, t0, startup, BEAT, BEAT)
			if perch_volley:
				_perch_volley = true
				punishing = true
				var side := signf(global_position.x - player.global_position.x)
				if side == 0.0:
					side = 1.0
				_perch_pos = Vector2(clampf(player.global_position.x + side * PERCH_SIDE, arena.position.x + 150.0, arena.end.x - 150.0),
					maxf(player.global_position.y - PERCH_ABOVE, arena.position.y + 160.0))
		State.LAND:
			_land_stone = _pick_stone()
			_diving = false
			dive_amount = 0.0
			telegraph.emit("land")
			_begin(State.LAND, t0, startup, BEAT, 0.0)


func _begin(st: State, t0: float, startup: float, active: float, recovery: float) -> void:
	_set_state(st)
	attack_phase = "startup"
	windup_progress = 0.0
	telegraph_amount = 0.0
	_phase_end = t0 + startup
	startup_len = startup
	active_len = active
	recovery_len = recovery
	if st == State.LAND:
		# 착지 충격의 공격 범위 예고: 내려앉을 자리 ±170 (v1.1.0 — 예전엔 디딤돌 전체 ±370 이 빛났다)
		_tel.show_rect(melee_reach(), false, maxf(_left(), 0.05))


func _phase_step(_delta: float, on_active: Callable) -> void:
	match attack_phase:
		"startup":
			windup_progress = 1.0 - clampf(_left() / maxf(startup_len, 0.001), 0.0, 1.0)
			telegraph_amount = windup_progress
			if _left() <= 0.0:
				attack_phase = "active"
				_phase_end += active_len
				_spawned = 1
				on_active.call()
		"active":
			if _left() <= 0.0:
				attack_phase = "recovery"
				_phase_end += recovery_len
		"recovery":
			if _left() <= 0.0:
				attack_phase = ""
				_set_state(State.HOVER)
				# 다음 패턴은 다음 마디 첫 박 (1페이즈는 한 마디 쉬고, 2페이즈는 바로 다음 마디)
				_next_at = _next_bar_after(_clock + (BAR * 0.6 if phase == 1 else 0.0))


## 디딤돌 고르기: 소녀와 가까운, 아직 가라앉지 않은 넓은 발판(Sink*, 폭 LAND_MIN_WIDTH 이상) 또는 섬(Island).
## 2페이즈에 가라앉기 시작한 돌은 고르지 않는다 (내려앉는 사이 물에 잠기지 않게).
func _pick_stone() -> Node2D:
	var room := get_parent()
	var candidates: Array = []
	if not _sunk:
		for s in _stones:
			if is_instance_valid(s) and s.collision_layer != 0 and s.size.x >= LAND_MIN_WIDTH:
				candidates.append(s)
	var island := room.get_node_or_null("Terrain/Island") if room else null
	if island:
		candidates.append(island)
	if candidates.is_empty():
		return null
	var best: Node2D = candidates[0]
	var best_d := INF
	for c in candidates:
		var cx: float = c.global_position.x + c.size.x / 2.0
		var d: float = absf((player.global_position.x if player else global_position.x) - cx)
		if d < best_d:
			best_d = d
			best = c
	return best


func _stone_top_center(s: Node2D) -> Vector2:
	if s == null:
		return Vector2(arena.get_center().x, ground_y)
	return Vector2(s.global_position.x + s.size.x / 2.0, s.global_position.y)


## 내려앉기: 하나·둘 동안 디딤돌 위 높이로 옮기고, 둘째 박 끝(셋째 박 LAND_DIVE 초 전)에 가속하며 내려꽂아
## **셋째 박에 딱** 앉는다(왈츠의 마지막 박). 앉는 순간 착지 충격(가드 가능).
func _land_step(delta: float) -> void:
	if _land_stone != null and (not is_instance_valid(_land_stone) or _land_stone.collision_layer == 0):
		# 디딤돌이 사라졌다(가라앉음 등): 다시 고른다 (섬은 늘 있다)
		_land_stone = _pick_stone()
		if _diving:
			_dive_from = global_position
	var top := _stone_top_center(_land_stone)
	windup_progress = 1.0 - clampf(_left() / maxf(startup_len, 0.001), 0.0, 1.0)
	telegraph_amount = windup_progress
	_tel.update_rect(melee_reach())
	var left := _left()
	if left > LAND_DIVE:
		_fly_toward(top + Vector2(0, -280.0), delta, 5.0)
		return
	if not _diving:
		_diving = true
		_dive_from = global_position
		_landed_touch = false
	var k := 1.0 - clampf(left / LAND_DIVE, 0.0, 1.0)
	dive_amount = k
	if left <= 0.0:
		global_position = top
		velocity = Vector2.ZERO
		set_collision_mask_value(1, true)
		_touch_down()
		return
	# 가속하며 내려꽂는다 (시계 기준이라 히트스톱이 끼어도 셋째 박에 닿는다)
	var want := _dive_from.lerp(top, k * k)
	velocity = (want - global_position) / maxf(delta, 0.00001)


func _touch_down() -> void:
	_landed_touch = true
	_diving = false
	dive_amount = 0.0
	attack_phase = ""
	_set_state(State.LANDED)
	_burst_done = false
	# 셋째 박(예정 시각)부터 LANDED_BEATS 박
	_phase_end = maxf(_phase_end, _clock - BEAT * 0.5) + BEAT * LANDED_BEATS
	var hit := HitData.make(land_damage, 0.0, self, Vector2(420, -260))
	hit.hitstop = 0.05
	hitbox.set_box(LAND_BOX, 1)
	hitbox.activate(hit, 0.2)
	Juice.shake(7.0)
	Sfx.play("land", -2.0, 0.05)


## 지금 근접 공격(내려앉기 착지 충격)의 판정이 덮을 월드 사각형. 내려앉는 중이면 내려앉을 자리, 앉은 뒤면 지금 자리.
## 공격 범위 예고·이펙트·시험이 같은 값을 쓴다. 근접 공격이 아니면 빈 사각형.
func melee_reach() -> Rect2:
	if state == State.LAND:
		var top := _stone_top_center(_land_stone)
		return Rect2(top + hitbox.position + LAND_BOX.position, LAND_BOX.size)
	if state == State.LANDED:
		if _burst_left > 0:
			return burst_reach()
		return RangeTelegraph.box_world(hitbox, LAND_BOX, 1)
	return Rect2()


## 수액 터뜨리기의 판정이 덮을 월드 사각형 (예고·이펙트·시험이 같은 값)
func burst_reach() -> Rect2:
	return RangeTelegraph.box_world(hitbox, BURST_BOX, 1)


## 수액 터뜨리기 한 번: 앉은 채로 몸 둘레를 친다 (가드 가능 — 저스트 가드면 흐트러짐이 쌓인다)
func _sap_burst() -> void:
	var hit := HitData.make(wave_damage, 0.0, self, Vector2(520, -300))
	hit.hitstop = 0.05
	hitbox.set_box(BURST_BOX, 1)
	hitbox.activate(hit, 0.2)
	burst_count += 1
	Juice.shake(6.0)
	Sfx.play("land", 0.0, 0.08)


func _begin_takeoff() -> void:
	hitbox.deactivate()
	_diving = false
	dive_amount = 0.0
	_hover_target = _random_hover()
	set_collision_mask_value(1, false)
	_set_state(State.TAKEOFF)
	_timer = BAR
	_landed_touch = false


# ---------- 공격 ----------
func _scatter_dust() -> void:
	var count := dust_count if phase == 1 else dust_count + 4
	var base_dir := Vector2(0, 1)
	if player:
		base_dir = (player.global_position - global_position).normalized()
	for i in count:
		var p: SapProjectile = SAP_PROJECTILE.instantiate()
		p.sap_kind = "dust"
		p.look = "queen_dust"   # (SapProjectile 이 _ready 에서 정하던 것을 미리 — _pierce 가 판정 반지름을 읽는다)
		p.kind = Projectile.Kind.FEATHER
		p.speed = _rng.randf_range(300.0, 440.0) if phase == 1 else _rng.randf_range(340.0, 500.0)
		p.damage = dust_damage
		p.poise = 0.0
		p.lifetime = 4.0
		p.fall_gravity = 520.0
		p.size = Vector2(22, 22)
		p.color = Color(0.7, 0.95, 1.0)
		p.guardable = true
		_pierce(p)
		get_parent().add_child(p)
		var spread := (float(i) / maxf(count - 1, 1) - 0.5) * 2.2
		var dir := Vector2(sin(spread), cos(spread)).normalized()
		# 절반은 소녀 쪽으로 모인다
		if i % 2 == 0 and player:
			dir = base_dir.rotated(spread * 0.35)
		p.global_position = global_position + Vector2(spread * 90.0, -120.0)
		p.launch(dir, self, false)
	Sfx.play("gust", -10.0, 0.1)


func _launch_waves() -> void:
	var dirs: Array = []
	if player:
		dirs.append(1.0 if player.global_position.x > global_position.x else -1.0)
	else:
		dirs.append(float(facing))
	if phase == 2:
		dirs.append(-dirs[0])
	for d in dirs:
		var w: SapWave = SAP_WAVE.instantiate()
		w.speed = wave_speed if phase == 1 else wave_speed * 1.15
		w.damage = wave_damage
		w.limit_left = arena.position.x - 100.0
		w.limit_right = arena.end.x + 100.0
		get_parent().add_child(w)
		w.global_position = Vector2(global_position.x + d * 60.0, surface_y)
		w.launch(Vector2(d, 0), self, false)
	Juice.shake(4.0)


func _release_butterflies() -> void:
	var count := butterfly_count if phase == 1 else butterfly_count + 2
	if _perch_volley:
		count += PERCH_EXTRA   # 가지 나비 떼: 두 마리 더
	for i in count:
		get_tree().create_timer(i * 0.12).timeout.connect(func() -> void:
			if state in [State.FALLEN, State.PURIFIED, State.WAIT, State.BROKEN]:
				return
			_spawn_butterfly(i, count))


func _spawn_butterfly(index: int, count: int) -> void:
	var p: SapProjectile = SAP_PROJECTILE.instantiate()
	p.sap_kind = "butterfly"
	p.look = "queen_butterfly"
	p.kind = Projectile.Kind.FEATHER
	p.speed = butterfly_speed if phase == 1 else butterfly_speed * 1.15
	p.damage = butterfly_damage
	p.poise = 0.0
	p.reflectable = true
	p.homing = 1.3
	p.lifetime = 5.0
	p.size = Vector2(34, 26)
	p.color = Color(0.55, 0.9, 1.0)
	_pierce(p)
	get_parent().add_child(p)
	var origin := global_position + Vector2(facing * 90.0 + (index - (count - 1) / 2.0) * 40.0, -140.0)
	p.global_position = origin
	var target := player.global_position + Vector2(0, -40) if player else origin + Vector2(facing * 100.0, 200.0)
	var dir := (target - origin).normalized().rotated((index - (count - 1) / 2.0) * 0.2)
	p.launch(dir, self, false)
	p.reflected.connect(func(_pr): Sfx.play("select", -4.0, 0.1))


## v1.1.0 (기획자 요청 4): 보스 투사체는 지형(디딤돌·섬·가지)을 뚫고 지나간다. 호수 바닥(가장 낮은 디딤) 아래로 내려가면 사라진다.
func _pierce(p: Projectile) -> void:
	p.pierce_terrain = true
	p.use_art_hit_radius()   # v1.1.0 통합: 판정 = 보이는 그림 (그림 묶음의 hit_r)
	var bed := ground_y + 120.0
	var room := get_parent()
	var lake_bed := room.get_node_or_null("Terrain/LakeBed") as Node2D if room else null
	if lake_bed:
		bed = lake_bed.global_position.y
	p.floor_y = maxf(bed, ground_y) + p.hit_radius() + 4.0


# ---------- 2페이즈: 디딤돌 가라앉기 ----------
func _sink_stones() -> void:
	if _sunk:
		return
	_sunk = true
	for s in _stones:
		if not is_instance_valid(s):
			continue
		var tw := create_tween()
		tw.tween_property(s, "position:y", _stone_home[s].y + 220.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		# 그림: 호수 바닥 속에 비치지 않게 — 몸통 결·뒤 그림자(묶음 맨 아래 겹)도 함께 (TerrainArt.set_host_alpha)
		tw.parallel().tween_method(func(a: float) -> void: TerrainArt.set_host_alpha(a, s), 1.0, 0.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			if is_instance_valid(s):
				s.collision_layer = 0
				s.visible = false)   # 몸통 결(묶음 맨 아래 겹)까지 숨긴다


func _raise_stones() -> void:
	_sunk = false
	for s in _stones:
		if not is_instance_valid(s):
			continue
		s.position = _stone_home[s]
		s.collision_layer = 1
		TerrainArt.set_host_alpha(1.0, s)
		s.visible = true


# ---------- 맞기 ----------
func receive_hit(hit: HitData, _hb: Hurtbox) -> String:
	if state in [State.WAIT, State.INTRO, State.FALLEN, State.PURIFIED, State.CRACK]:
		return "ignored"
	# 낙하 공격 감쇠 (4초 창 — PlungeDecay)
	hit = plunge_decay.apply(hit)
	_flash = 1.0
	var dmg := hit.damage
	var gained := hit.poise
	var reflected := hit.from_player and hit.source == self
	if reflected:
		# 되받은 나비: 피해 온전히 + 흐트러짐 크게
		gained += REFLECT_POISE
		reflected_count += 1
	elif state == State.BROKEN:
		dmg *= _broken_mult
	elif not is_ground():
		dmg *= AIR_DAMAGE_RATIO
		gained *= AIR_POISE_RATIO
	if (punishing or _poise_immune > 0.0) and not reflected:
		gained = 0.0   # 맞딜 응징 중·무너졌다 날아오른 직후에는 무너뜨릴 수 없다
	hp = maxf(hp - dmg, 0.0)
	hp_changed.emit(hp, max_hp)
	_add_poise(gained, reflected)
	if hp <= 0.0:
		_fall()
		return "hit"
	if phase == 1 and hp <= max_hp * 0.5:
		_enter_phase2()
		return "hit"
	if poise >= max_poise and state != State.BROKEN:
		_break()
	return "hit"


func on_just_guarded(_by: Player, amount: float) -> void:
	_flash = 1.0
	_add_poise(amount, true)
	if poise >= max_poise and state != State.BROKEN:
		_break()


## skill: 되받은 나비·저스트 가드에서 온 흐트러짐 (무너짐 길이를 고른다 — brute_broken_time)
func _add_poise(amount: float, skill := false) -> void:
	if amount <= 0.0:
		return
	var before := poise
	poise = minf(poise + amount, max_poise)
	if skill:
		_skill_poise += poise - before
	_poise_hold = 2.5
	poise_changed.emit(poise, max_poise)


## 이번 무너짐의 길이: 흐트러짐의 skill_break_share(4분의 1) 이상이 기술(되받은 나비·저스트 가드)이면 broken_time, 아니면 brute_broken_time
func broken_length() -> float:
	if poise <= 0.0 or _skill_poise / poise >= skill_break_share:
		return broken_time
	return minf(brute_broken_time, broken_time)


func _break() -> void:
	hitbox.deactivate()
	attack_phase = ""
	_diving = false
	dive_amount = 0.0
	_glide_target = _island_top()
	_landed_touch = state == State.LANDED
	_timer = broken_length()
	_broken_mult = broken_damage_multiplier if _timer >= broken_time else brute_broken_damage_multiplier
	_set_state(State.BROKEN)
	Juice.hitstop(0.1, 0.05)
	Juice.shake(8.0)
	Sfx.play("broke", -2.0)


func _island_top() -> Vector2:
	var room := get_parent()
	var island := room.get_node_or_null("Terrain/Island") if room else null
	if island:
		return _stone_top_center(island)
	return Vector2(arena.get_center().x, ground_y)


func _enter_phase2() -> void:
	phase = 2
	hitbox.deactivate()
	attack_phase = ""
	_diving = false
	dive_amount = 0.0
	set_collision_mask_value(1, false)
	velocity = Vector2(0, -200)
	# 무너진(BROKEN) 채 넘어와도 흐트러짐은 비운다 (안 비우면 갈라짐 뒤 한 대에 또 무너진다 — 2026-10-19 검토)
	poise = 0.0
	_skill_poise = 0.0
	_poise_hold = 0.0
	poise_changed.emit(poise, max_poise)
	_set_state(State.CRACK)
	_phase_end = _clock + BAR
	phase_changed.emit(2)
	telegraph.emit("crack")
	_sink_stones()
	Juice.hitstop(0.15, 0.03)
	Juice.shake(12.0)
	Sfx.play("broke", 0.0, 0.0)


func _fall() -> void:
	hitbox.deactivate()
	attack_phase = ""
	_diving = false
	dive_amount = 0.0
	_glide_target = _island_top()
	_landed_touch = false
	velocity = Vector2(0, 300)
	_unregister()
	_set_state(State.FALLEN)
	Juice.hitstop(0.15, 0.03)
	Juice.shake(12.0)
	fallen.emit()


func _update_interactable() -> void:
	if player == null or not is_on_floor():
		return
	var near := absf(player.global_position.x - global_position.x) < 260.0 and absf(player.global_position.y - global_position.y) < 220.0
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


# ---------- 공개 보조 ----------
func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	if debug_log:
		print("[여왕] %s %.2f초 → %s (박 %d, 시계 %.2f)" % [State.keys()[state], (Time.get_ticks_msec() - _state_started_ms) / 1000.0, State.keys()[new_state], beat_index(), _clock])
	_state_started_ms = Time.get_ticks_msec()
	state = new_state
	_burst_left = 0
	if new_state not in [State.LAND, State.WAVE]:
		punishing = false   # 응징(내려앉기, 또는 물결)이 끝나면 꺼진다 — 내려앉은 뒤(LANDED)는 다시 무너뜨릴 수 있는 빈틈
	_perch_volley = false   # 가지 나비 떼는 그 나비 떼 동안만 (_next_pattern 이 _begin 뒤에 다시 켠다)
	if new_state not in ATTACK_STATES:
		attack_phase = ""
	if _tel and new_state != State.LAND:
		_tel.end()   # 내려앉기가 끝나거나(착지) 끊기면 예고는 걷힌다
	state_changed.emit(new_state)


func flash_amount() -> float:
	return _flash


## 지금 공격 단계의 진행도 (0→1). 그림의 세 박자 곡선 기준.
func phase_progress() -> float:
	match attack_phase:
		"startup": return clampf(windup_progress, 0.0, 1.0)
		"active": return 1.0 - clampf(_left() / maxf(active_len, 0.001), 0.0, 1.0)
		"recovery": return 1.0 - clampf(_left() / maxf(recovery_len, 0.001), 0.0, 1.0)
	return 0.0


## 붉은 예고는 없다 (전부 가드 가능).
func is_red() -> bool:
	return false


## 땅에 있어서 제대로 때릴 수 있는가 (내려앉음·무너짐·쓰러짐이 땅에 닿은 뒤)
func is_ground() -> bool:
	if state == State.LANDED:
		return true
	return state in [State.BROKEN, State.FALLEN] and _landed_touch


## BossRoom 이 예고 글자로 띄운다 (가드 불가는 없으니 공격 이름만).
func telegraph_label(kind: String) -> String:
	match kind:
		"wave": return "수액 물결!"
		"butterflies": return "나비 떼!"
		"burst": return "수액 터뜨리기!"
	return ""


func state_name() -> String:
	return State.keys()[state]

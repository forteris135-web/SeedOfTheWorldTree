extends CharacterBody2D
class_name GrayLeafBird
## 첫 보스 '잿빛 잎새의 새' (기획서 6장 보스 상세).
## 하늘: 잿빛 잎 흩날리기 / 깃털 화살(저스트 가드로 되받기) / 날갯바람(가드 불가).
## 지침: 땅으로 내려와 잿빛 잎을 삼키려 한다(끊으면 크게 흐트러짐). 날개 휘두르기·부리 찍기.
## 2페이즈(체력 절반): 잎 회오리, 더 많은 깃털, 짧아진 내려오기, 거세진 반격.
## 체력이 다하면 쓰러져 정화의 손길을 기다린다.
## 2026-10-19 기획자 요청: 체력 2배(1800), 탄막 가시성 — 잎·깃털 그림 1.8배(판정은 그대로)+테두리+발광+꼬리,
## 깃털은 쏘기 feather_warn_time 전부터 부리 앞 붉은 점(feather_warn), 잎 흩날리기는 떨어질 구간 위 흰 띠(rain_warn).
## 체력만 2배: 잎 삼키기 회복은 비율을 절반(0.03)으로 내려 회복량(54)은 예전 그대로.

enum State { WAIT, INTRO, HOVER, LEAF_RAIN, FEATHERS, WIND, DESCEND, GROUND_IDLE, WALK_TO_PILE, EAT, SWEEP, PECK, TAKEOFF, BROKEN, FALLEN, PURIFIED }
const AIR_STATES := [State.HOVER, State.LEAF_RAIN, State.FEATHERS, State.WIND]
const GROUND_STATES := [State.GROUND_IDLE, State.WALK_TO_PILE, State.EAT, State.SWEEP, State.PECK]

signal hp_changed(hp: float, max_hp: float)
signal poise_changed(poise: float, max_poise: float)
signal phase_changed(phase: int)
signal state_changed(state: State)
signal fallen
signal purified
signal telegraph(kind: String)   # "wind" 등 붉은 예고

@export_group("능력치")
## 2026-10-19 기획자 요청: 900 → 1800 (2배). 지침 조건(깃털 되받기·점프 공격 횟수, 24초)은 그대로.
@export var max_hp := 1800.0
@export var max_poise := 150.0
## 맞지 않을 때 초당 줄어드는 흐트러짐.
@export var poise_decay := 8.0
@export var broken_time := 5.0
## 무너진 동안 받는 피해 배수.
@export var broken_damage_multiplier := 1.6
## 무너졌다 일어선 뒤 이 시간(초) 동안은 흐트러짐이 쌓이지 않는다 (v1.1.0 맞딜 방지 — 기사·뿌리지기와 같은 규칙.
## 공격 버튼만 두들겨 무너짐을 잇따라 만드는 '샌드백'을 막는다. 되받은 깃털은 기술의 보상이라 그대로)
@export var poise_immune_after_broken := 2.5
## 공중의 새가 소녀의 영혼 기술(씨앗 베기)에 맞았을 때 쌓이는 지침 (v1.1.0 맞딜 검수 2 — 영혼 기술 함께 잠김을 걷고 그 대신):
## 예전엔 흐트러짐 25 넘는 공격이라 무거운 공격(2)으로 셌다 → 점프 약공격과 같은 1. 제자리 점프로 떠 있으며 베기만 거듭하는 봇
## (공중 영혼 — 18판 중 3판 승, 이긴 판 봇 체력 63%)이 두 번 베면 새가 지쳐 내려와, 잎 삼키기를 끊어 5초 무너짐을 거듭 받았다.
## 기획서 6장 '깃털 반사(지침 +2)·점프 공격 네 번'의 길은 그대로.
@export var slash_fatigue := 1.0

@export_group("하늘")
@export var hover_speed := 5.0            # 목표 지점으로 다가가는 빠르기
@export var hover_rest := 1.2             # 패턴 사이 쉬는 시간 (2페이즈 0.8)
@export var air_time_max := 24.0          # 이 시간이 지나면 지쳐서 내려온다
@export var descend_fatigue := 4          # 깃털 반사·점프 공격이 이만큼 쌓이면 내려온다 (2페이즈 3)
@export var leaf_rain_time := 3.5         # 앞 rain_warn_time 동안은 띠 예고만, 그 뒤 잎이 떨어진다
## 잎이 떨어지기 전 흰 띠 예고 시간 (떨어질 구간 위쪽)
@export var rain_warn_time := 0.35
@export var leaf_interval := 0.2          # 2페이즈 0.13
@export var leaf_damage := 10.0
@export var feather_count := 3            # 2페이즈 5
@export var feather_damage := 14.0
@export var feather_speed := 1000.0
## 첫 깃털을 쏘기 전 부리 앞 붉은 점 예고 시간 (예고 0.6초의 끝부분)
@export var feather_warn_time := 0.3
## 탄막 바탕 그림·발광 배율 (판정은 그대로). 2026-10-19 기획자 요청으로 1.8 이었으나 v1.1.0 (요청 4 '예고 = 판정', 명세 3.6)에서
## 보이는 그림을 판정 반경 ±20% 로 맞추며 1.0 (그림 묶음 배율은 scripts/fx/fx_art.gd — 발광 원 크기만 이 값을 따른다)
@export var shot_draw_scale := 1.8
## 잎이 생길 때 서서히 나타나는 시간 (화면 안에서 툭 생겨나 보이지 않게)
@export var leaf_fade_in := 0.12
@export var wind_telegraph := 0.8
@export var wind_time := 1.5
@export var wind_force := 2600.0          # 소녀를 밀어내는 가속 (픽셀/초²)

@export_group("땅")
@export var ground_time := 9.0            # 2페이즈 7
@export var walk_speed := 240.0
@export var eat_time := 2.6
## 잎 삼키기 회복 비율. 체력 2배(1800)에 맞춰 0.06 → 0.03 — 회복량 54 는 예전(900×0.06)과 같다 ("체력만 2배").
@export var eat_heal_ratio := 0.03
@export var eat_interrupt_poise := 50.0
@export var sweep_windup := 0.55          # 2페이즈 0.4
@export var sweep_damage := 20.0
@export var peck_windup := 0.45
@export var peck_damage := 16.0
@export var gravity := 2600.0

@export_group("움직임 연출")
## 소녀가 이만큼(px) 넘게 반대쪽으로 가야 몸을 돌린다 (바로 밑을 지날 때 매 프레임 뒤집히지 않게)
@export var face_deadzone := 80.0
## 한 번 돌면 이 시간 동안은 다시 돌지 않는다
@export var face_hold := 0.35
## 이륙 전 웅크리는 시간 (TAKEOFF 1.1초 안에 포함, 상태 길이는 그대로)
@export var takeoff_crouch := 0.2

var state: State = State.WAIT
var hp := 1800.0
var poise := 0.0
var phase := 1
var facing := -1
var player: Player
var arena: Rect2
var hover_points: Array = []
var ground_y := 0.0
var piles: Array = []

var _timer := 0.0
var _air_timer := 0.0
var _fatigue := 0.0
var _pattern_index := 0
var _hover_target := Vector2.ZERO
var _spawn_accum := 0.0
var _spawned := 0
var _poise_hold := 0.0
var _flash := 0.0
var _target_pile: Node2D
var _ground_timer := 0.0
var _ground_actions := 0
var _registered := false
var _hit_this_phase := false
var _home := Vector2.ZERO
var _bob_t := 0.0
var _wind_dir := 1
var _face_hold := 0.0
## 공격 범위 예고 (v1.1.0) / 맞딜 방지 계량기 (v1.1.0)
var _tel: RangeTelegraph
var crowd := CrowdMeter.new(CROWD_RANGE)
## 낙하 공격 감쇠 시계 (v1.1.0 최종 검수 — 앞 낙하 공격 뒤 4초 안에 또 맞으면 피해 ×0.6^n·흐트러짐 ×0.5^n; scripts/combat/plunge_decay.gd)
var plunge_decay := PlungeDecay.new()
## 높은 자리 계량기 (v1.1.0 맞딜 검수) / 지금 깃털 화살이 깃털 세례(높은 자리 응징)인가 / 그때 머무는 자리
var perch := PerchMeter.new(PERCH_TRIGGER)
var _perch_volley := false
var _perch_pos := Vector2.ZERO
## 지금 공격이 맞딜 응징인가 (응징 공격은 흐트러짐이 쌓이지 않는다 — 두들겨 끊을 수 없다. 구르기로 피해야 한다)
var punishing := false
var _poise_immune := 0.0
## 이번 내려앉음에 잎 삼키기를 이미 끊었나 (끊은 흐트러짐 +eat_interrupt_poise 는 내려앉음마다 한 번만 — v1.1.0 맞딜 검수 2)
var _eat_cut := false

## 그림이 읽는 공개 값들 (기사·뿌리지기와 같은 약속)
var attack_phase := ""          # SWEEP/PECK 의 startup / active / recovery (아니면 "")
var windup_progress := 0.0      # startup 동안 0→1
var startup_len := 0.5
var active_len := 0.22
var recovery_len := 0.9
## 깃털 화살 예고 (0→1 로 차오르고, 쏘기 시작하면 사라진다). 피격 번쩍임과 다른 색으로 보인다.
var telegraph_amount := 0.0
## 움찔 (잎 삼키기를 끊겼을 때 1 에서 0.6초에 걸쳐 0 으로)
var stagger := 0.0
## 이륙 전 웅크리는 중
var crouching := false
## 잎 흩날리기 예고 띠 세기 (0→1 로 차오르고, 잎이 떨어지는 동안 0.45 로 남았다가, 끝나면 사라진다)
var rain_warn := 0.0
## 깃털 발사 예고: 부리 앞 붉은 점 (첫 발 feather_warn_time 전부터 0→1, 쏘는 동안 0.55 유지)
var feather_warn := 0.0
## 한 발 쏠 때마다 1 로 튀고 빠르게 사라지는 번쩍임 (붉은 점 위)
var muzzle_flash := 0.0

@onready var sprite: Sprite2D = $Sprite
@onready var hitbox: Hitbox = $Hitbox
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var body_shape: CollisionShape2D = $CollisionShape2D

const PROJECTILE := preload("res://scenes/combat/projectile.tscn")
## 근접 판정 (바라보는 쪽 기준, Hitbox 노드(발밑 y -60) 기준 — v1.1.0: 예고·이펙트가 이 값을 그대로 쓴다)
const SWEEP_BOX := Rect2(-40, -120, 330, 180)
const PECK_BOX := Rect2(80, -90, 200, 110)
## 부리 찍기: 앞으로 튀어 나가는 첫 속도와 감속 (판정이 켜진 0.3초 동안 앞으로 쓸고 간다)
const PECK_SPEED := 520.0
const PECK_DECEL := 900.0
const PECK_ACTIVE := 0.3
const SWEEP_ACTIVE := 0.22
## 맞딜 방지 계량기 (v1.1.0): 땅에서 이 거리 안에 붙어 있으면 쌓이고, 다 차면 몸 둘레 날개 털기 (맞딜 마무리 검수 — 예전엔 앞만 치는 날개 휘두르기)
const CROWD_RANGE := 280.0
## 내려앉기 날개바람 (v1.1.0 맞딜 검수): 잎 더미로 내려앉는 순간 날개로 몸 높이 둘레를 친다 (Hitbox 노드 기준 — 바닥선 x ±300,
## 높이 180..460 = 땅에 선 소녀(머리 134)는 맞지 않고, 내려앉을 자리 둘레에 **떠 있는** 소녀만; 땅에 선 새의 원점은 몸 충돌 캡슐 때문에
## 바닥선보다 GROUND_REST 아래라 상자를 그만큼 올려 둔다). 내려오는 동안 앉을 자리에 이 사각형이 주황으로 차오른다 (예고 = 판정 = 잎 무더기
## 이펙트, 가드 가능). 새가 내려앉을 자리 둘레에서 떠 있으며(점프·이단 점프) 베기만 거듭하는 소녀가 지쳐 내려온 새의 잎 삼키기를 곧바로
## 끊어 무너뜨리던 것(공중 맞딜 봇 18판 중 8판 승)에. 땅에서 내려오는 새를 베는 길은 그대로 둔다 (잘하는 봇의 잡는 시간을 지키려고).
const LANDING_BOX := Rect2(-300, -430, 600, 280)
## 맞딜 응징 날개 털기 (몸 둘레, 땅부터 높이 460 — 땅 맞딜도 맞는다)
const FLAP_BOX := Rect2(-300, -430, 600, 460)
## 땅에 선 새의 원점 = 바닥선 + 이 값 (가로로 누운 몸 캡슐: 가운데 -140, 반지름 110 → 바닥이 원점 위 30). 내려앉는 순간 바로 이 자리에 둔다
## (예전엔 바닥선에 두어 몇 프레임 동안 30px 떨어졌다 — 날개바람 판정이 함께 내려가 예고와 어긋났다)
const GROUND_REST := 30.0
const LANDING_DAMAGE := 16.0
## 이 새의 내려앉기 날개바람 피해 (LANDING_DAMAGE × v1.1.1 보스 추가 공격 배율 — _ready 에서 한 번)
var _landing_damage := LANDING_DAMAGE
## 높은 자리 계량기 (v1.1.0 맞딜 검수, PerchMeter): 새가 하늘에 있는 동안 소녀가 바닥 위 200 넘게 높은 곳(가지 위·점프·이단 점프)에
## PERCH_TRIGGER 초 머물면, 다음 하늘 패턴은 '깃털 세례' — 소녀 머리 위 비스듬한 자리(가로 PERCH_SIDE, 위 PERCH_ABOVE)로 올라가
## 깃털을 PERCH_EXTRA 발 더 쏜다 (예고·붉은 점·깃털 판정 = 보이는 그림은 보통 깃털 화살과 같고 가드 가능 — **저스트 가드로 되받으면**
## 보통처럼 새에게 돌아가 지침 +2). 땅에 내려와 있을 때 계량기가 차면 (땅 공격이 닿지 않는 머리 위에 떠 있는 소녀) 곧바로 날아오른다.
## 제자리에서 뛰어 떠 있으며 새를 베기만 하던 봇(공중 맞딜 18판 중 4판 승)에.
const PERCH_TRIGGER := 1.8
const PERCH_SIDE := 300.0
const PERCH_ABOVE := 420.0
const PERCH_EXTRA := 2
## 깃털 세례 동안 소녀 머리 위로 올라가는가 (false 면 보통 머무는 자리에서 쏜다)
const PERCH_RISE := true
## 하늘에서 받는 흐트러짐 배수 (되받은 깃털은 온전히) — v1.1.0 맞딜 검수, 수액의 여왕(SapQueen.AIR_POISE_RATIO)과 같은 규칙.
## 하늘의 새를 무너뜨리는 길은 깃털 되받기와 '지치게 해서 내려온 새의 잎 삼키기 끊기'(기획서 6장). 떠 있으며 베기만 거듭해 하늘에서
## 바로 무너뜨리던 공중 맞딜 봇에.
const AIR_POISE_RATIO := 0.7
## 부리 끝 바로 앞 (오른쪽을 볼 때; 예전 한 장 그림의 부리 ≈ 몸 가운데에서 (+210, −70), 깃털 자세로 살짝 젖힘 — 깃털이 생기는 판정 출발점이라 그대로 둔다)
const MUZZLE_OFFSET := Vector2(230.0, -235.0)
## 그림 가운데 (Sprite position)
const BODY_OFFSET := Vector2(0.0, -150.0)


func _ready() -> void:
	add_to_group("boss")
	add_child(preload("res://scripts/fx/bird_fx.gd").new())   # 이펙트 리뉴얼 F2: 기술 이펙트 (판정과 무관)
	# v1.1.0 체력 배율: 보스가 놓인 방의 던전 단계 1.1^단계 × 난이도. reset_fight 는 max_hp 를 읽는다.
	# v1.1.1: × 새 Normal 기준 1.15(hp_mult 안) × 보스별 추가(Balance.BOSS_EXTRA["bird"]) — 한 번만. 공격도 내 공격 값에 한 번.
	max_hp *= Balance.hp_mult(Balance.region_of(self)) * Balance.boss_extra("bird", "hp")
	Balance.scale_boss_damage(self, ["leaf_damage", "feather_damage", "sweep_damage", "peck_damage", "_landing_damage"], Balance.boss_extra("bird", "atk"))
	hp = max_hp
	_home = global_position
	set_collision_mask_value(1, false)
	visible = false
	hitbox.landed.connect(_on_hit_landed)
	_tel = RangeTelegraph.attach(self)


## 방이 싸움을 시작시킨다.
func start_fight(p: Player) -> void:
	player = p
	visible = true
	_clear_telegraphs()
	global_position = Vector2(arena.get_center().x, arena.position.y - 300)
	_set_state(State.INTRO)
	_timer = 2.2
	_hover_target = hover_points[1] if hover_points.size() > 1 else arena.get_center()


## 소녀가 쓰러졌을 때: 처음 상태로.
func reset_fight() -> void:
	_unregister()
	hp = max_hp
	poise = 0.0
	phase = 1
	_fatigue = 0.0
	_air_timer = 0.0
	_pattern_index = 0
	_eat_cut = false
	visible = false
	velocity = Vector2.ZERO
	set_collision_mask_value(1, false)
	hitbox.deactivate()
	global_position = _home
	_clear_telegraphs()
	crowd.reset()
	perch.reset()
	_perch_volley = false
	plunge_decay.reset()
	_tel.clear()
	_poise_immune = 0.0
	_set_state(State.WAIT)
	hp_changed.emit(hp, max_hp)
	poise_changed.emit(poise, max_poise)


## 예고·연출 값을 모두 비운다. WAIT 에선 _physics_process 가 바로 돌아가 값이 줄지 않으므로,
## 소녀가 잎 흩날리기·깃털 도중에 쓰러졌다 다시 싸울 때 옛 띠·붉은 점이 번쩍이지 않게 여기서 0 으로.
func _clear_telegraphs() -> void:
	rain_warn = 0.0
	feather_warn = 0.0
	muzzle_flash = 0.0
	telegraph_amount = 0.0
	stagger = 0.0
	crouching = false


func _physics_process(delta: float) -> void:
	if state == State.WAIT or state == State.PURIFIED:
		return
	_flash = maxf(_flash - delta * 6.0, 0.0)
	plunge_decay.tick(delta)
	_poise_hold = maxf(_poise_hold - delta, 0.0)
	if _poise_hold <= 0.0 and poise > 0.0 and state != State.BROKEN and state != State.FALLEN:
		poise = maxf(poise - poise_decay * delta, 0.0)
		poise_changed.emit(poise, max_poise)
	_timer -= delta
	_bob_t += delta
	_face_hold = maxf(_face_hold - delta, 0.0)
	_poise_immune = maxf(_poise_immune - delta, 0.0)
	stagger = maxf(stagger - delta / 0.6, 0.0)
	if state != State.FEATHERS:
		telegraph_amount = maxf(telegraph_amount - delta * 4.0, 0.0)
		feather_warn = maxf(feather_warn - delta * 6.0, 0.0)
	if state != State.LEAF_RAIN:
		rain_warn = maxf(rain_warn - delta * 3.0, 0.0)
	muzzle_flash = maxf(muzzle_flash - delta * 9.0, 0.0)
	crouching = state == State.TAKEOFF and _timer > 1.1 - takeoff_crouch
	if player:
		# 맞딜 방지: 땅에 내려와 있을 때만 쌓인다 (하늘의 새에게 붙을 수는 없다)
		crowd.tick(delta, global_position, player.global_position, state in GROUND_STATES, facing)
		# 높은 자리: 새가 하늘에서 공격할 수 있는 동안 소녀가 높은 곳(가지·점프 꼭대기)에 머물면 쌓인다 (깃털 세례 중은 아님)
		perch.tick(delta, ground_y, player, (state in AIR_STATES or state in GROUND_STATES) and not _perch_volley)
	if player and state != State.FEATHERS and state in AIR_STATES + [State.INTRO, State.GROUND_IDLE, State.EAT]:
		# 데드존 + 최소 유지 시간: 소녀가 바로 밑을 지나도 매 프레임 뒤집히지 않는다.
		# 깃털 화살 동안은 고정 (시작할 때 한 번 소녀 쪽을 본다) — 붉은 점·깃털 출발점이 반대편으로 건너뛰지 않게.
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
				_timer = hover_rest
		State.HOVER:
			_air_timer += delta
			_fly_toward(_hover_target, delta, hover_speed)
			if _should_descend():
				_begin_descend()
			elif _timer <= 0.0:
				_next_pattern()
		State.LEAF_RAIN:
			_air_timer += delta
			_fly_toward(_hover_target, delta, hover_speed * 0.6)
			var elapsed := leaf_rain_time - _timer
			if elapsed < rain_warn_time:
				# 예고: 떨어질 구간 위쪽에 흰 띠가 빠르게 차오른다 (아직 잎은 없다)
				rain_warn = clampf(elapsed / 0.12, 0.0, 1.0)
			else:
				rain_warn = Motion.damp(rain_warn, 0.45, 6.0, delta)
				_spawn_accum += delta
				var interval := leaf_interval if phase == 1 else leaf_interval * 0.65
				while _spawn_accum >= interval:
					_spawn_accum -= interval
					_spawn_leaf()
			if _timer <= 0.0:
				_set_state(State.HOVER)
				_timer = _rest()
		State.FEATHERS:
			_air_timer += delta
			_fly_toward(_perch_pos if _perch_volley and PERCH_RISE else _hover_target, delta, hover_speed * (0.8 if _perch_volley and PERCH_RISE else 0.3))
			var count := _feather_total()
			# 예고 0.6초 뒤 0.15초 간격으로 쏜다
			var t_since := (0.6 + count * 0.15) - _timer
			# 예고: 0.6초 동안 차오르고 쏘기 시작하면 0.3초에 걸쳐 사라진다
			telegraph_amount = clampf(t_since / 0.6, 0.0, 1.0) if t_since < 0.6 else maxf(1.0 - (t_since - 0.6) / 0.3, 0.0)
			# 부리 앞 붉은 점: 첫 발 feather_warn_time 전부터 차오르고, 쏘는 동안은 0.55 로 남는다
			if t_since < 0.6:
				feather_warn = clampf((t_since - (0.6 - feather_warn_time)) / maxf(feather_warn_time, 0.01), 0.0, 1.0)
			else:
				feather_warn = Motion.damp(feather_warn, 0.55, 10.0, delta)
			var should_have := clampi(int(floor((t_since - 0.6) / 0.15)) + 1, 0, count)
			while _spawned < should_have:
				_spawn_feather(_spawned, count)
				_spawned += 1
				muzzle_flash = 1.0
			if _timer <= 0.0:
				_set_state(State.HOVER)
				_timer = _rest()
		State.WIND:
			_air_timer += delta
			_fly_toward(_hover_target, delta, hover_speed * 0.4)
			if _timer <= wind_time and player:
				player.apply_wind(_wind_dir * wind_force, delta)
			if _timer <= 0.0:
				_set_state(State.HOVER)
				_timer = _rest()
		State.DESCEND:
			var target := Vector2(global_position.x, ground_y)
			if _target_pile:
				target.x = _target_pile.global_position.x + facing * -120.0
			_fly_toward(target, delta, 3.5)
			if _tel.is_showing():
				_tel.update_rect(landing_reach())
			if absf(global_position.y - ground_y) < 12.0:
				global_position.y = ground_y + GROUND_REST
				global_position.x = _descend_x()   # 예고한 자리에 정확히 앉는다 (남은 거리는 몇 px — 날개바람 판정 = 예고)
				set_collision_mask_value(1, true)
				_set_state(State.GROUND_IDLE)
				_ground_timer = ground_time if phase == 1 else ground_time * 0.78
				_ground_actions = 0
				_eat_cut = false
				_timer = 0.5
				Juice.shake(6.0)
				_landing_gust()
		State.GROUND_IDLE:
			_ground(delta)
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			if _timer <= 0.0:
				_pick_ground_action()
		State.WALK_TO_PILE:
			_ground(delta)
			if _target_pile == null or not is_instance_valid(_target_pile) or not _target_pile.available:
				_set_state(State.GROUND_IDLE)
				_timer = 0.3
			else:
				var dx := _target_pile.global_position.x - global_position.x
				facing = 1 if dx > 0.0 else -1
				if absf(dx) < 150.0:
					velocity.x = 0.0
					_set_state(State.EAT)
					_timer = eat_time
				else:
					velocity.x = move_toward(velocity.x, facing * walk_speed, 1200.0 * delta)
		State.EAT:
			_ground(delta)
			velocity.x = 0.0
			if _timer <= 0.0:
				hp = minf(hp + max_hp * eat_heal_ratio, max_hp)
				hp_changed.emit(hp, max_hp)
				if _target_pile and is_instance_valid(_target_pile):
					_target_pile.consume()
				_set_state(State.GROUND_IDLE)
				_timer = 0.6
		State.SWEEP:
			_ground(delta)
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			_melee_phase("sweep")
		State.PECK:
			_ground(delta)
			_melee_phase("peck")
		State.TAKEOFF:
			set_collision_mask_value(1, false)
			if crouching:
				# 이륙 전 잠깐 웅크린다 (그 뒤 날아오름; 상태 길이는 1.1초 그대로)
				velocity = velocity.move_toward(Vector2.ZERO, 3000.0 * delta)
			else:
				_fly_toward(_hover_target, delta, 2.5)
			if _timer <= 0.0:
				_set_state(State.HOVER)
				_timer = _rest()
				_air_timer = 0.0
				_fatigue = 0.0
		State.BROKEN:
			_settle_to_ground(delta)
			velocity.x = move_toward(velocity.x, 0.0, 1800.0 * delta)
			if _timer <= 0.0:
				poise = 0.0
				poise_changed.emit(poise, max_poise)
				_poise_immune = poise_immune_after_broken
				_begin_takeoff()
		State.FALLEN:
			_settle_to_ground(delta)
			velocity.x = 0.0
			_update_interactable()
	move_and_slide()


## 2페이즈 쉬는 시간 배수 (v1.1.0 맞딜 방지 사다리 4단계: 2페이즈 공격 사이 쉬는 시간 −15%)
const P2_REST_MULT := 0.85


func _rest() -> float:
	return hover_rest if phase == 1 else hover_rest * 0.65 * P2_REST_MULT


func _fly_toward(target: Vector2, delta: float, k: float) -> void:
	var bob := Vector2(0, sin(_bob_t * 2.2) * 18.0)
	var to := (target + bob) - global_position
	velocity = to * k


func _ground(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		velocity.y = 0.0


## 발판을 통과해 주 바닥까지 내려와 눕는다.
func _settle_to_ground(delta: float) -> void:
	if global_position.y < ground_y - 30.0 and not is_on_floor():
		set_collision_mask_value(1, false)
		velocity.y = minf(velocity.y + gravity * delta, 1400.0)
	else:
		set_collision_mask_value(1, true)
		_ground(delta)


func _should_descend() -> bool:
	var need := descend_fatigue if phase == 1 else maxi(descend_fatigue - 1, 2)
	return _fatigue >= float(need) - 0.001 or _air_timer >= air_time_max


func _next_pattern() -> void:
	var order := [State.LEAF_RAIN, State.FEATHERS, State.WIND, State.FEATHERS] if phase == 1 else [State.LEAF_RAIN, State.FEATHERS, State.WIND, State.FEATHERS, State.LEAF_RAIN, State.WIND]
	var next: State = order[_pattern_index % order.size()]
	var perch_volley := false
	if perch.ready() and player:
		# 높은 자리 응징 (v1.1.0 맞딜 검수): 순서를 건너뛰지 않고 이번 패턴만 깃털 세례로
		perch.consume()
		next = State.FEATHERS
		perch_volley = true
	else:
		_pattern_index += 1
	# 다음 머무를 자리
	if hover_points.size() > 0:
		_hover_target = hover_points[randi() % hover_points.size()]
	match next:
		State.LEAF_RAIN:
			_set_state(State.LEAF_RAIN)
			_timer = leaf_rain_time
			_spawn_accum = 0.0
		State.FEATHERS:
			_set_state(State.FEATHERS)
			if perch_volley:
				_perch_volley = true
				punishing = true
				var side := signf(global_position.x - player.global_position.x)
				if side == 0.0:
					side = 1.0
				_perch_pos = Vector2(clampf(player.global_position.x + side * PERCH_SIDE, arena.position.x + 160.0, arena.end.x - 160.0),
					minf(_hover_target.y, maxf(player.global_position.y - PERCH_ABOVE, arena.position.y + 380.0)))
			if player and absf(player.global_position.x - global_position.x) > 1.0:
				facing = 1 if player.global_position.x > global_position.x else -1
				_face_hold = face_hold
			var count := _feather_total()
			_timer = 0.6 + count * 0.15
			_spawned = 0
			telegraph_amount = 0.0   # 예고는 telegraph_amount 로 (피격 번쩍임과 구분)
			feather_warn = 0.0
		State.WIND:
			_set_state(State.WIND)
			_timer = wind_telegraph + wind_time
			_wind_dir = 1 if (player and player.global_position.x > global_position.x) else -1
			telegraph.emit("wind")


## 이번 깃털 화살의 발 수 (2페이즈 +2, 깃털 세례 +PERCH_EXTRA)
func _feather_total() -> int:
	var n := feather_count if phase == 1 else feather_count + 2
	if _perch_volley:
		n += PERCH_EXTRA
	return n


func _spawn_leaf() -> void:
	var p: Projectile = PROJECTILE.instantiate()
	p.kind = Projectile.Kind.LEAF
	p.speed = randf_range(170.0, 260.0)
	p.damage = leaf_damage
	p.poise = 0.0
	p.lifetime = 7.0
	p.fall_gravity = 40.0
	p.size = Vector2(46, 20)               # 판정 기준 (반지름 12) — 그대로
	p.draw_scale = shot_draw_scale         # 발광 원 배율 (그림은 판정 크기 — fx_art.gd)
	p.color = Color(0.5, 0.52, 0.49)       # 잿빛 잎
	p.outline_color = Color(0.98, 0.99, 0.95, 1.0)   # 흰 테두리
	p.core_color = Color(0.3, 0.31, 0.28, 1.0)       # 잎맥
	p.glow = 0.7                           # 0.9 는 잿빛 몸이 희게 바랬다(스크린샷 확인) → 흰 테두리가 주역, 발광은 보조
	p.trail_count = 4
	p.fade_in = leaf_fade_in               # 화면 안에서 생겨도 툭 나타나지 않게
	p.look = "bird_leaf"                   # 이펙트 리뉴얼 F2: 그림 (scripts/fx/fx_art.gd)
	_pierce(p)
	var dir := Vector2(randf_range(-0.25, 0.25), 1.0)
	var pos: Vector2
	if phase == 1:
		# 싸움터 위 +20 (16:9 화면에선 화면 위 바깥)에서 생겨 미끄러져 들어오고, 흰 띠(+160)를 지나 내려온다
		pos = Vector2(randf_range(arena.position.x + 80, arena.end.x - 80), arena.position.y + 20)
	else:
		# 회오리: 새 몸 주위(흰 고리 자리)에서 바깥으로 돌며 흩어진다
		var a := _spawned * 0.9
		_spawned += 1
		pos = body_center() + Vector2(cos(a), sin(a)) * 160.0
		dir = (Vector2(cos(a + 1.2), sin(a + 1.2)) + Vector2(0, 1.2)).normalized()
		p.speed = 300.0
	get_parent().add_child(p)
	p.global_position = pos
	p.launch(dir, self, false)


func _spawn_feather(index: int, count: int) -> void:
	if player == null:
		return
	var p: Projectile = PROJECTILE.instantiate()
	p.kind = Projectile.Kind.FEATHER
	p.speed = feather_speed
	p.damage = feather_damage
	p.poise = 0.0
	p.reflectable = true
	p.size = Vector2(76, 16)               # 판정 기준 (반지름 10) — 그대로
	p.draw_scale = shot_draw_scale         # 발광 원 배율 (그림은 판정 크기 — fx_art.gd)
	p.color = Color(0.86, 0.9, 0.94)       # 은빛
	p.outline_color = Color(1.0, 1.0, 1.0, 1.0)
	p.core_color = Color(1.0, 0.25, 0.2, 1.0)        # 붉은 심
	p.glow = 1.0
	p.trail_count = 5
	p.look = "bird_feather"                # 이펙트 리뉴얼 F2: 금빛 깃털 그림
	_pierce(p)
	get_parent().add_child(p)
	var origin := muzzle_point()
	p.global_position = origin
	var spread := (index - (count - 1) / 2.0) * 0.12
	var dir := (player.global_position + Vector2(0, -40) - origin).normalized().rotated(spread)
	p.launch(dir, self, false)
	p.reflected.connect(func(_pr): _fatigue += 2.0)


## v1.1.0 (기획자 요청 4): 보스 투사체는 지형(가지·벽)을 뚫고 지나간다. 바닥 아래(아무도 맞을 수 없는 곳)로 내려가면 사라진다.
func _pierce(p: Projectile) -> void:
	p.pierce_terrain = true
	p.use_art_hit_radius()   # v1.1.0 통합: 판정 = 보이는 그림 (그림 묶음의 hit_r)
	p.floor_y = ground_y + p.hit_radius() + 4.0


## 깃털이 나가는 자리 (부리 끝 바로 앞; global_position 은 발밑이고 그림은 150px 위). 붉은 점 예고도 여기에 그린다.
func muzzle_point() -> Vector2:
	return global_position + MUZZLE_OFFSET * Vector2(facing, 1.0)


## 새 몸 가운데 (그림 Sprite 자리). 2페이즈 잎 회오리와 그 예고 고리의 중심.
func body_center() -> Vector2:
	return global_position + BODY_OFFSET


## BossRoom 이 예고 글자를 띄울 때 묻는다 (가드 불가는 붉은 빛이 원칙, 글자는 공격 이름만).
func telegraph_label(kind: String) -> String:
	match kind:
		"wind": return "날갯바람!"
	return ""


func _begin_descend() -> void:
	_target_pile = _nearest_available_pile()
	set_collision_mask_value(1, false)
	_set_state(State.DESCEND)
	# 내려앉기 날개바람의 공격 범위 예고: 앉을 자리에 판정 사각형. 차오르는 시간 ≈ 내려오는 시간(높이를 초당 3.5 배로 좁혀 가며 12px 안에서 앉음;
	# 몸이 위아래로 18px 출렁여 조금 일찍 앉을 수 있으니 30px 기준으로 짧게 잡아, 늦게 차는 일 없이 앉기 전에 가득 찬다)
	var dy := maxf(ground_y - global_position.y, 31.0)
	_tel.show_rect(landing_reach(), false, clampf(log(dy / 30.0) / 3.5, 0.3, 2.0))


## 내려앉을 자리 x (잎 더미 앞, 없으면 지금 x)
func _descend_x() -> float:
	if _target_pile and is_instance_valid(_target_pile):
		return _target_pile.global_position.x + facing * -120.0
	return global_position.x


## 내려앉기 날개바람의 판정이 덮을 월드 사각형 (내려오는 중이면 앉을 자리, 앉은 뒤면 지금 자리). 예고·이펙트·시험이 같은 값을 쓴다.
func landing_reach() -> Rect2:
	var x := _descend_x() if state == State.DESCEND else global_position.x
	return Rect2(Vector2(x, ground_y + GROUND_REST) + Vector2(0.0, hitbox.position.y) + LANDING_BOX.position, LANDING_BOX.size)


## 내려앉는 순간: 날개로 몸 둘레를 내리친다 (가드 가능)
func _landing_gust() -> void:
	var hit := HitData.make(_landing_damage, 0.0, self, Vector2(560, -300))
	hit.hitstop = 0.05
	hitbox.set_box(LANDING_BOX, 1)
	hitbox.activate(hit, 0.2)


func _nearest_available_pile() -> Node2D:
	var best: Node2D = null
	var best_d := INF
	for pile in piles:
		if is_instance_valid(pile) and pile.available:
			var d: float = absf(pile.global_position.x - global_position.x)
			if d < best_d:
				best_d = d
				best = pile
	return best


func _pick_ground_action() -> void:
	_ground_timer -= 0.0
	if _ground_actions >= (4 if phase == 1 else 5) + 2:
		# 응징만 거듭하다 땅에 눌러앉지 않게 (v1.1.0 맞딜 검수: 등 뒤에 붙은 봇에게 날개 휘두르기만 16번 헛치며 날아오르지 않던 것)
		_begin_takeoff()
		return
	if crowd.ready() and player:
		# 맞딜 방지 (v1.1.0): 몸에 붙어 버티는 소녀에게는 잎 더미·날아오르기보다 먼저 — 몸 둘레 날개 털기 (앞뒤·머리 위 460 까지;
		# v1.1.0 맞딜 검수: 예전엔 소녀 쪽으로 돌아 앞만 치는 날개 휘두르기라, 예비동작 동안 등 뒤로 다시 돌아가면 늘 헛쳤다)
		crowd.consume()
		facing = 1 if player.global_position.x > global_position.x else -1
		_face_hold = face_hold
		_ground_actions += 1
		flap = true
		_start_melee(State.SWEEP)
		punishing = true
		return
	if perch.ready() and player:
		# 높은 자리 응징 (v1.1.0 맞딜 검수): 땅 공격이 닿지 않는 머리 위에 떠 있는 소녀 — 땅에 머물지 않고 날아오른다
		# (계량기는 비우지 않는다 — 하늘에 오르면 다음 패턴이 깃털 세례)
		_begin_takeoff()
		return
	if _ground_actions == 0 and _target_pile and is_instance_valid(_target_pile) and _target_pile.available:
		_ground_actions += 1
		_set_state(State.WALK_TO_PILE)
		return
	if _ground_actions >= (4 if phase == 1 else 5):
		_begin_takeoff()
		return
	_ground_actions += 1
	if player:
		facing = 1 if player.global_position.x > global_position.x else -1
	var dist := absf(player.global_position.x - global_position.x) if player else 999.0
	if dist > 260.0 or randf() < 0.4:
		_start_melee(State.PECK)
	else:
		_start_melee(State.SWEEP)


## 근접 공격(날개 휘두르기·부리 찍기)을 시작한다: 예고 길이와 공격 범위 예고(RangeTelegraph, 판정과 같은 사각형).
func _start_melee(st: State) -> void:
	_set_state(st)
	if st == State.PECK:
		_timer = peck_windup if phase == 1 else peck_windup * 0.8
	else:
		_timer = sweep_windup if phase == 1 else sweep_windup * 0.75
	_melee_stage = 0
	attack_phase = "startup"
	windup_progress = 0.0
	startup_len = _timer
	_tel.show_rect(melee_reach(), false, _timer)


## 시험·연출용: 근접 공격을 바로 건다 ("SWEEP" / "PECK")
func force_melee(kind: String) -> void:
	_start_melee(State.PECK if kind == "PECK" else State.SWEEP)


## 지금 근접 공격의 판정이 덮을 월드 사각형 (부리 찍기는 앞으로 튀어 나가며 쓸고 갈 구간 전체). 예고·이펙트·시험이 같은 값을 쓴다.
func melee_reach() -> Rect2:
	if state == State.SWEEP and flap:
		return RangeTelegraph.box_world(hitbox, FLAP_BOX, 1)
	if state == State.PECK:
		return RangeTelegraph.box_world(hitbox, PECK_BOX, facing, RangeTelegraph.slide_distance(PECK_SPEED, PECK_DECEL, PECK_ACTIVE),
			RangeTelegraph.slide_first(PECK_SPEED, PECK_DECEL))
	return RangeTelegraph.box_world(hitbox, SWEEP_BOX, facing)


var _melee_stage := 0
## 지금 날개 휘두르기가 몸 둘레 날개 털기(맞딜 응징)인가 — 판정·예고·이펙트가 FLAP_BOX (몸 둘레, 땅부터 높이 460)
var flap := false
func _melee_phase(kind: String) -> void:
	if _melee_stage == 0:
		# 예고 중 (공격 범위 예고는 보스가 미끄러져도 판정 자리를 따라간다)
		windup_progress = 1.0 - clampf(_timer / maxf(startup_len, 0.001), 0.0, 1.0)
		_tel.update_rect(melee_reach())
		if _timer <= 0.0:
			_melee_stage = 1
			attack_phase = "active"
			_tel.end()
			if kind == "sweep":
				var hit := HitData.make(sweep_damage, 0.0, self, Vector2(520, -220))
				hitbox.set_box(FLAP_BOX if flap else SWEEP_BOX, 1 if flap else facing)
				hitbox.activate(hit, SWEEP_ACTIVE)
				_timer = SWEEP_ACTIVE
			else:
				var hit2 := HitData.make(peck_damage, 0.0, self, Vector2(420, -160))
				hitbox.set_box(PECK_BOX, facing)
				hitbox.activate(hit2, PECK_ACTIVE)
				velocity.x = facing * PECK_SPEED
				_timer = PECK_ACTIVE
			active_len = _timer
			Juice.shake(3.0)
	elif _melee_stage == 1:
		if kind == "peck":
			velocity.x = move_toward(velocity.x, 0.0, PECK_DECEL * get_physics_process_delta_time())
		if _timer <= 0.0:
			_melee_stage = 2
			attack_phase = "recovery"
			_timer = 0.9 if phase == 1 else 0.65 * P2_REST_MULT
			recovery_len = _timer
	else:
		velocity.x = move_toward(velocity.x, 0.0, 1600.0 * get_physics_process_delta_time())
		if _timer <= 0.0:
			_set_state(State.GROUND_IDLE)
			_timer = 0.35


func _begin_takeoff() -> void:
	hitbox.deactivate()
	_hover_target = hover_points[randi() % hover_points.size()] if hover_points.size() > 0 else arena.get_center()
	_set_state(State.TAKEOFF)
	_timer = 1.1


# ---------- 맞기 ----------

func receive_hit(hit: HitData, _hurtbox: Hurtbox) -> String:
	if state in [State.WAIT, State.INTRO, State.FALLEN, State.PURIFIED]:
		return "ignored"
	# 낙하 공격 감쇠 (4초 창 — PlungeDecay). 지침(무거운 공격 +2)은 줄이기 전 공격(raw)으로 센다
	var raw := hit
	hit = plunge_decay.apply(hit)
	_flash = 1.0
	var dmg := hit.damage
	if state == State.BROKEN:
		dmg *= broken_damage_multiplier
	hp = maxf(hp - dmg, 0.0)
	hp_changed.emit(hp, max_hp)
	var gained := hit.poise
	if state == State.EAT:
		if not _eat_cut:
			gained += eat_interrupt_poise   # 잎 삼키기를 끊었다 (내려앉음마다 한 번만 — 다시 삼키다 끊겨도 움찔만)
			_eat_cut = true
		hitbox.deactivate()
		_set_state(State.GROUND_IDLE)
		_timer = 1.2
		stagger = 1.0   # 뒤로 움찔 (그림)
		Juice.shake(5.0)
	elif state in AIR_STATES:
		if raw.from_player and raw.soul != "":
			_fatigue += slash_fatigue   # 공중에서 맞은 영혼 기술(씨앗 베기)은 점프 약공격만큼 지친다
		else:
			_fatigue += 1.0 if not raw.from_player or raw.poise < 25.0 else 2.0
	if not is_ground() and not (hit.from_player and hit.source == self):
		gained *= AIR_POISE_RATIO   # 하늘(내려오기·날아오르기 포함)에서는 흐트러짐 0.7배 (되받은 깃털은 온전히)
	if (punishing or _poise_immune > 0.0) and not (hit.from_player and hit.source == self):
		gained = 0.0   # 맞딜 응징 중·무너졌다 일어선 직후에는 무너뜨릴 수 없다 (되받은 깃털은 기술의 보상이라 그대로)
	_add_poise(gained)
	if hp <= 0.0:
		_fall()
		return "hit"
	if phase == 1 and hp <= max_hp * 0.5:
		_enter_phase2()
	if poise >= max_poise and state != State.BROKEN:
		_break()
	return "hit"


func _add_poise(amount: float) -> void:
	if amount <= 0.0:
		return
	poise = minf(poise + amount, max_poise)
	_poise_hold = 2.5
	poise_changed.emit(poise, max_poise)


func _break() -> void:
	hitbox.deactivate()
	set_collision_mask_value(1, true)
	_set_state(State.BROKEN)
	_timer = broken_time
	Juice.hitstop(0.1, 0.05)
	Juice.shake(8.0)


func _enter_phase2() -> void:
	phase = 2
	phase_changed.emit(2)
	Juice.shake(10.0)
	_flash = 1.0


func _fall() -> void:
	hitbox.deactivate()
	set_collision_mask_value(1, true)
	velocity = Vector2(0, 600)
	_unregister()
	_set_state(State.FALLEN)
	Juice.hitstop(0.15, 0.03)
	Juice.shake(12.0)
	fallen.emit()


func _update_interactable() -> void:
	if player == null or not is_on_floor():
		return
	var near := absf(player.global_position.x - global_position.x) < 260.0 and absf(player.global_position.y - global_position.y) < 200.0
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


func _on_hit_landed(_result: String, _target: Node) -> void:
	pass


var debug_log := false
var _state_started_ms := 0


func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	if debug_log:
		print("[새] %s %.2f초 → %s" % [State.keys()[state], (Time.get_ticks_msec() - _state_started_ms) / 1000.0, State.keys()[new_state]])
	_state_started_ms = Time.get_ticks_msec()
	state = new_state
	punishing = false   # 응징은 그 공격 한 번 (새 공격은 응징이 아니다 — _start_melee 뒤 응징이면 다시 켠다)
	if new_state != State.SWEEP:
		flap = false
	_perch_volley = false   # 깃털 세례도 그 깃털 화살 동안만 (_next_pattern 이 _set_state 뒤에 다시 켠다)
	if new_state != State.SWEEP and new_state != State.PECK:
		attack_phase = ""
		if _tel:
			_tel.end()   # 근접 공격이 끊기면 예고도 걷힌다
	state_changed.emit(new_state)


func flash_amount() -> float:
	return _flash


## 지금 공격 단계의 진행도 (0→1). 그림이 세 박자 곡선(예비→타격→되돌림)을 그리는 기준.
func phase_progress() -> float:
	match attack_phase:
		"startup": return clampf(windup_progress, 0.0, 1.0)
		"active": return 1.0 - clampf(_timer / maxf(active_len, 0.001), 0.0, 1.0)
		"recovery": return 1.0 - clampf(_timer / maxf(recovery_len, 0.001), 0.0, 1.0)
	return 0.0


## 붉은 예고 (가드 불가 날갯바람의 예고 동안)
func is_red() -> bool:
	return state == State.WIND and _timer > wind_time


func is_ground() -> bool:
	return state in GROUND_STATES or state in [State.BROKEN, State.FALLEN]


func state_name() -> String:
	return State.keys()[state]

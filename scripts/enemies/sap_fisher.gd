extends EnemyBase
class_name SapFisher
## 수액 어부 (확장판 · 수액의 호수). 호수에서 수액을 긷던 사람. 수액에 젖은 **긴 낚싯줄을 채찍처럼** 휘두른다.
## 중거리(사거리 WHIP_RANGE): 가까이 오면 뒤로 물러나고(BACKSTEP·폴짝), 멀면 다가온다.
## 가르치는 것: 거리 조절과 **3박 리듬의 예고** — 예고 2박 동안 줄을 두 번 흔들고(하나·둘) 세 번째 박에 휘두른다(셋).
## 박자는 수액의 여왕과 같은 138bpm (한 박 0.435초 → 예고 0.87초). 가드 가능, 저스트 가드로 되받으면 크게 휘청.
## 그림은 EnemySpriteVisual + 낚싯줄을 코드로 그리는 SapFisherVisual (sap_fisher_visual.gd).

const BEAT := 60.0 / 138.0
## 채찍 사거리(px)와 판정 높이
const WHIP_RANGE := 300.0
const WHIP_H := 90.0

## 이보다 가까우면 뒤로 물러난다
@export var keep_distance := 190.0
## 뒤로 물러날 때 폴짝 뛰는 세기 (0 이면 걷기만)
@export var hop_speed := 360.0


func _ready() -> void:
	super()
	windup_time = BEAT * 2.0          # 하나·둘
	strike_time = 0.18                # 셋
	strike_box = Rect2(30, -WHIP_H - 20, WHIP_RANGE, WHIP_H)


func _physics_process(delta: float) -> void:
	# 바탕 상태 기계를 쓰되, 거리 유지만 바꾼다 (정원사·약초꾼과 같은 방식)
	if state == State.CHASE and player and _sees_player(notice_range * 1.4):
		var dx := player.global_position.x - global_position.x
		facing = 1 if dx > 0.0 else -1
		if absf(dx) < keep_distance and _can_walk(-facing):
			_tick_common(delta)
			if is_on_floor() and _timer <= -0.5 and hop_speed > 0.0:
				velocity.y = -hop_speed   # 폴짝 물러난다
				_timer = 0.0
			velocity.x = move_toward(velocity.x, -facing * walk_speed * 1.15, 1800.0 * delta)
			if not is_on_floor():
				velocity.y += gravity * delta
			move_and_slide()
			return
	if anim_hint == "whip" and state not in [State.WINDUP, State.STRIKE, State.RECOVER]:
		anim_hint = ""
	super(delta)


func _begin_windup() -> void:
	super()
	anim_hint = "whip"


func _strike() -> void:
	super()
	anim_hint = "whip"
	Sfx.play("swing", -3.0, 0.08)


## 예고의 박(0: 하나, 1: 둘). 그림이 줄을 흔드는 기준.
func windup_beat() -> int:
	return clampi(int(floorf(windup_progress * 2.0)), 0, 1)

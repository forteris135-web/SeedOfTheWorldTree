class_name Motion
## 움직임(애니메이션) 보조 함수 모음. 적·보스·소녀가 함께 쓴다.
## 원칙 (2026-10-18 기획자: "휘두르기가 저렴하고 단절돼 보인다"):
## - 자세는 절대 '툭' 바뀌지 않는다. 모든 자세 값은 목표값으로 스프링/감쇠 보간한다.
## - 휘두르기는 세 박자: 예비동작(천천히 뒤로 당기며 멈칫) → 타격(아주 빠르게, 살짝 지나침) → 되돌림(출렁이며 제자리).
## - 몸 전체가 따라간다: 팔만 돌지 않고 어깨·허리가 비틀리고, 무게 중심이 앞뒤로 옮겨 가고, 발이 땅을 디딘다.
## - 2차 움직임: 망토·머리카락·장식은 몸보다 한 박자 늦게 따라온다 (스프링).


## 감쇠 스프링 한 틱. 돌려주는 값: [새 값, 새 속도]. stiffness 가 클수록 빠르고, damping 이 작을수록 더 출렁인다.
static func spring(value: float, target: float, velocity: float, stiffness: float, damping: float, delta: float) -> Array:
	var accel := (target - value) * stiffness - velocity * damping
	velocity += accel * delta
	value += velocity * delta
	return [value, velocity]


## 지수 감쇠 보간 (프레임 독립). speed 가 클수록 빨리 따라간다. 대략 3/speed 초면 목표에 거의 닿는다.
static func damp(value: float, target: float, speed: float, delta: float) -> float:
	return lerpf(value, target, 1.0 - exp(-speed * delta))


static func damp_vec(value: Vector2, target: Vector2, speed: float, delta: float) -> Vector2:
	return value.lerp(target, 1.0 - exp(-speed * delta))


static func damp_angle(value: float, target: float, speed: float, delta: float) -> float:
	return lerp_angle(value, target, 1.0 - exp(-speed * delta))


## 0→1 곡선들
static func ease_in(t: float, p := 2.0) -> float:
	return pow(clampf(t, 0.0, 1.0), p)


static func ease_out(t: float, p := 2.0) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), p)


static func ease_in_out(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c * (3.0 - 2.0 * c)


## 끝에서 살짝 지나쳤다 돌아온다 (s 가 클수록 더 지나침).
static func ease_out_back(t: float, s := 1.7) -> float:
	var c := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + c * c * ((s + 1.0) * c + s)


## 예비동작 (0→1, 1 = 가장 뒤로 당긴 자세): 처음엔 빠르게 당기고 끝에서 멈칫한다.
static func anticipation(t: float) -> float:
	return ease_out(t, 2.5)


## 타격 (0→1, 1 = 휘두름 끝): 아주 빠르게 나가며 끝에서 살짝 지나친다.
static func strike(t: float) -> float:
	return ease_out_back(t, 2.2)


## 되돌림 (0→1, 1 = 제자리): 감쇠 진동으로 출렁이며 멈춘다.
static func settle(t: float, bounces := 2.0, decay := 4.0) -> float:
	var c := clampf(t, 0.0, 1.0)
	return 1.0 - exp(-decay * c) * cos(bounces * PI * c) * (1.0 - c)


## 휘두르기 한 동작을 하나의 값으로 (0→1 진행도 → 자세 비율): 뒤로 당김(-1) → 앞으로(+1) → 제자리(0).
## windup, strike_len 은 전체에서 차지하는 비율. 나머지가 되돌림.
static func swing(t: float, windup := 0.45, strike_len := 0.2) -> float:
	var c := clampf(t, 0.0, 1.0)
	if c < windup:
		return -anticipation(c / windup)
	elif c < windup + strike_len:
		return lerpf(-1.0, 1.0, strike(( c - windup) / strike_len))
	else:
		return lerpf(1.0, 0.0, settle((c - windup - strike_len) / maxf(1.0 - windup - strike_len, 0.001)))


## 숨쉬기·들썩임 같은 주기 운동.
static func breathe(time: float, rate := 1.6, amount := 1.0) -> float:
	return sin(time * rate * TAU) * amount


## 걸음 주기 (거리 기준): 발 디딤마다 몸이 살짝 뜨고 내려앉는 모양 (0~1).
static func step_bob(distance: float, stride := 90.0) -> float:
	return absf(sin(distance / stride * PI))

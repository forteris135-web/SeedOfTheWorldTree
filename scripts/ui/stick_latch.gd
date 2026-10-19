extends RefCounted
class_name StickLatch
## 메뉴용 스틱(축) 입력: "한 번 밀기 = 한 칸".
## 스틱을 미는 동안 축 값이 바뀔 때마다 이벤트가 오고, 끝까지 밀어 둔 채의 작은 떨림에도 이벤트가 온다.
## 그래서 이벤트마다 is_action_pressed 로 세면 한 번 밀었는데 줄이 여러 칸 넘어간다 (검토 지적: 4줄 메뉴에서 7칸).
## 여기서는 세기가 PRESS 를 넘는 순간에만 한 칸 움직이고, 가운데(RELEASE 아래)로 돌아오거나 반대쪽으로 밀어야 다음 칸을 받는다.
## 버튼·키·십자키 이벤트는 건드리지 않는다 (feed 가 false — 평소처럼 처리한다).
## 쓰는 곳: TravelMenu(위·아래), GrassMenu(좌·우 탭), StatMenu(위·아래).

## 동작 세기(데드존을 뺀 0~1) — 이만큼 밀면 한 칸
const PRESS := 0.5
## 이 아래로 돌아오면 다음 밀기를 받는다
const RELEASE := 0.2

var _dir := 0
## 마지막 feed 의 결과: -1(neg 쪽으로 한 칸) / 0(움직이지 않음) / +1(pos 쪽으로 한 칸)
var step := 0


## event 가 neg/pos 동작에 묶인 스틱 움직임이면 true 를 돌려주고 step 에 결과를 담는다. 아니면 false.
func feed(event: InputEvent, neg: Array, pos: Array) -> bool:
	step = 0
	if not (event is InputEventJoypadMotion):
		return false
	var matched := false
	var sn := 0.0
	var sp := 0.0
	for a in neg:
		if InputMap.has_action(a) and event.is_action(a):
			matched = true
			sn = maxf(sn, event.get_action_strength(a))
	for a in pos:
		if InputMap.has_action(a) and event.is_action(a):
			matched = true
			sp = maxf(sp, event.get_action_strength(a))
	if not matched:
		return false
	if sn < RELEASE and sp < RELEASE:
		_dir = 0
	elif sp >= PRESS and _dir != 1:
		_dir = 1
		step = 1
	elif sn >= PRESS and _dir != -1:
		_dir = -1
		step = -1
	return true


## 메뉴를 열 때: 지난번에 밀어 둔 상태를 잊는다.
func reset() -> void:
	_dir = 0
	step = 0

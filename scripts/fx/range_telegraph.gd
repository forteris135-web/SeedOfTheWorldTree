extends Node2D
class_name RangeTelegraph
## 보스 근접 공격의 '공격 범위 예고' (v1.1.0 기획자 요청 1: 실제 타격 판정 = 공격 범위 예고 = 공격 이펙트).
## 실제 판정 사각형과 **같은 자리·같은 크기**의 사각형을 그린다. 앞으로 미끄러지거나 돌진하는 공격은
## 공격 동안 판정이 쓸고 지나갈 구간 전체를 그린다 (보스가 계산해 넘긴다 — box_world 의 sweep).
## 예비동작 동안: 테두리가 옅게 → 진하게, 안쪽 채움이 바닥에서 위로 0 → 가득 차오른다. 타격이 시작되면 빠르게 걷힌다.
## 색: 막을 수 있는 공격 = 주황 COLOR_GUARD, 가드 불가 = 진한 붉은빛 COLOR_RED ('가드 불가는 늘 진한 붉은빛' 원칙).
##
## 쓰는 법 (보스 스크립트):
##   _tel = RangeTelegraph.attach(self)                       # _ready 에서 한 번 (채움은 보스 그림 뒤, 테두리는 앞에 그려진다)
##   _tel.show_rect(RangeTelegraph.box_world(hitbox, BOX, facing, slide), unguardable, startup)   # 예비동작 시작
##   _tel.update_rect(...)                                    # 예비동작 동안 보스가 움직이면 매 틱 (진행은 그대로)
##   _tel.end()                                               # 타격 시작 (또는 공격이 끊김)
## 아이폰 부담: 사각형 3~4개를 그리는 노드 둘 (보스마다 하나, 매 프레임 새로 만드는 것 없음).
## 채움은 보스 그림 **뒤**(지형 위), 테두리·바닥 번쩍 선은 보스 그림 **앞**(FRONT_Z) — 몸 둘레를 치는 공격(내려찍기·등불 회전·김 분출)은
## 사각형 대부분이 보스 몸에 가려져 채움만으로는 안 보였다 (v1.1.0 검수).

const COLOR_GUARD := Color(1.0, 0.75, 0.30, 0.28)
const COLOR_RED := Color(1.0, 0.15, 0.10, 0.38)
## 걷히는 시간 (초)
const FADE_OUT := 0.1
## 테두리 굵기 (px)
const LINE_W := 3.0
## 가드 불가 예고의 안쪽 밝은 선 (붉게 빛나는 보스 몸 위에서도 붉은 테두리가 읽히게 — v1.1.0 검수: 뿌리지기 내려찍기는
## 사각형이 몸 폭과 거의 같아 채움이 몸에 가려지고, 붉은 몸 위의 붉은 3px 테두리만 남아 잘 안 보였다)
const RED_INNER_W := 2.0
const RED_INNER_COLOR := Color(1.0, 0.86, 0.80)
## 처음부터 보이는 옅은 바탕 (채움 세기의 비율) — 사각형 전체가 어디까지인지 예고 첫 프레임부터 보이게
const BASE_FILL := 0.3
## 가드 불가 예고의 맥동 (초당 횟수, 빛에 민감한 사람을 위해 3 이하)
const RED_PULSE_HZ := 2.5
## 테두리 겹의 그리기 순서 (보스·소녀 0 보다 위, 이펙트 6·앞 물 3 보다 아래)
const FRONT_Z := 1

## 지금 그리는 사각형 (월드 좌표)
var rect := Rect2()
var unguardable := false
var duration := 0.5
var _t := 0.0
var _out := -1.0
var _on := false
var _front: Node2D   # 테두리 겹 (보스 그림 앞)


## 보스(부모)에 붙인다: 첫 자식으로 넣어 채움이 보스 그림·이펙트보다 **뒤**에 그려진다 (지형 위, 보스·소녀 아래).
## 테두리는 자식 겹(z FRONT_Z)이라 보스 그림 앞에 보인다.
static func attach(boss: Node2D) -> RangeTelegraph:
	var t := RangeTelegraph.new()
	t.name = "RangeTelegraph"
	boss.add_child(t)
	boss.move_child(t, 0)
	return t


## 판정 상자(Hitbox.set_box 와 같은 뜻: 바라보는 쪽 기준, Hitbox 노드 원점 기준) → 월드 사각형.
## sweep: 판정이 켜진 동안 바라보는 쪽으로 미끄러지는 거리(px, + = 앞) — 판정이 마지막으로 닿는 자리. 그만큼 앞으로 늘린다.
## sweep_from: 판정이 처음 닿는 자리까지 이미 움직인 거리 (판정이 켜지는 틱에 한 걸음 움직인 뒤 처음 겹침을 본다).
static func box_world(hb: Node2D, box: Rect2, face: int, sweep := 0.0, sweep_from := 0.0) -> Rect2:
	var c := box.get_center()
	var o := hb.global_position + Vector2(c.x * float(face), c.y)
	var r := Rect2(o - box.size * 0.5, box.size)
	if sweep != 0.0 or sweep_from != 0.0:
		var a := Rect2(r.position + Vector2(sweep_from * float(face), 0.0), r.size)
		r = a.merge(Rect2(r.position + Vector2(sweep * float(face), 0.0), r.size))
	return r


## 판정이 켜진 동안 미끄러지는 거리 (px) = 판정이 마지막으로 닿는 자리: 첫 속도 v0 에서 매 틱 decel 로 줄며,
## 판정이 켜진 틱부터 꺼지기 한 틱 전까지(active 초 - 한 틱) 움직인 거리 (보스 스크립트의 한 틱 순서와 같게 센다).
## decel_first: 판정이 켜지는 틱에도 이미 감속하는가 (그 틱에 속도를 준 뒤 감속 줄이 뒤에 오는 보스).
static func slide_distance(v0: float, decel: float, active: float, decel_first := false, dt := 1.0 / 60.0) -> float:
	var v := absf(v0)
	var d := 0.0
	var n := maxi(int(roundf(active / dt)) - 1, 1)
	for i in n:
		if decel_first or i > 0:
			v = maxf(v - decel * dt, 0.0)
		d += v * dt
	return d


## 판정이 켜지는 틱에 움직이는 첫 걸음 (px) — box_world 의 sweep_from
static func slide_first(v0: float, decel: float, decel_first := false, dt := 1.0 / 60.0) -> float:
	var v := absf(v0)
	if decel_first:
		v = maxf(v - decel * dt, 0.0)
	return v * dt


func _ready() -> void:
	visible = false
	set_process(false)
	_front = Node2D.new()
	_front.name = "Outline"
	_front.z_index = FRONT_Z
	add_child(_front)
	_front.draw.connect(_draw_front)


func _redraw() -> void:
	queue_redraw()
	if _front:
		_front.queue_redraw()


## 예비동작 시작: 사각형을 0 부터 차오르게 그린다 (dur 초에 가득).
func show_rect(world_rect: Rect2, ug: bool, dur: float) -> void:
	rect = world_rect
	unguardable = ug
	duration = maxf(dur, 0.05)
	_t = 0.0
	_out = -1.0
	_on = true
	visible = true
	set_process(true)
	_pin()
	_redraw()


## 예비동작 동안 자리만 옮긴다 (차오름은 그대로)
func update_rect(world_rect: Rect2) -> void:
	if not _on:
		return
	if world_rect != rect:
		rect = world_rect
		_redraw()


## 타격이 시작됐다 (또는 끊겼다): 빠르게 걷힌다.
func end() -> void:
	if not _on or _out >= 0.0:
		return
	_out = 0.0


## 곧바로 지운다 (보스가 쓰러짐·리셋)
func clear() -> void:
	_on = false
	_out = -1.0
	visible = false
	set_process(false)


## 예고 중인가 (걷히는 중은 아니다)
func is_showing() -> bool:
	return _on and _out < 0.0


func progress() -> float:
	return clampf(_t / duration, 0.0, 1.0)


func _pin() -> void:
	# 부모(보스)가 움직여도 월드 좌표 그대로 그린다 (top_level 은 맨 위로 올라가 보스·소녀를 덮으므로 쓰지 않는다)
	global_position = Vector2.ZERO
	global_rotation = 0.0
	global_scale = Vector2.ONE


func _process(delta: float) -> void:
	if not _on:
		set_process(false)
		return
	if _out >= 0.0:
		_out += delta
		if _out >= FADE_OUT:
			clear()
			return
	else:
		_t = minf(_t + delta, duration)
	_pin()
	_redraw()


func _draw() -> void:
	if not _on or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var p := progress()
	var e := 1.0 - (1.0 - p) * (1.0 - p)
	var a := _alpha()
	var col := COLOR_RED if unguardable else COLOR_GUARD
	var c := _rgb()
	# 옅은 바탕 (사각형 전체) + 바닥에서 위로 차오르는 채움
	draw_rect(rect, Color(c, col.a * BASE_FILL * a))
	var h := rect.size.y * e
	if h > 0.5:
		draw_rect(Rect2(rect.position.x, rect.end.y - h, rect.size.x, h), Color(c, col.a * (1.0 - BASE_FILL) * a))
	# 테두리·바닥 번쩍 선은 앞 겹(_draw_front)이 그린다


## 앞 겹: 테두리 옅게 → 진하게 (사각형 안쪽에 그려 바깥 경계 = 판정 경계) + 다 차오르기 직전 바닥 선이 밝게 (곧 친다)
func _draw_front() -> void:
	if not _on or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var p := progress()
	var e := 1.0 - (1.0 - p) * (1.0 - p)
	var a := _alpha()
	var c := _rgb()
	var ln := Rect2(rect.position + Vector2(LINE_W, LINE_W) * 0.5, rect.size - Vector2(LINE_W, LINE_W))
	_front.draw_rect(ln, Color(c.lightened(0.15), (0.45 + 0.5 * e) * a), false, LINE_W)
	if unguardable and rect.size.x > LINE_W * 4.0 and rect.size.y > LINE_W * 4.0:
		# 붉은 테두리 바로 안쪽에 밝은 선 한 줄 (바깥 경계 = 판정 경계는 그대로 붉은 테두리)
		var inset := LINE_W + RED_INNER_W * 0.5
		var inner := Rect2(rect.position + Vector2(inset, inset), rect.size - Vector2(inset, inset) * 2.0)
		_front.draw_rect(inner, Color(RED_INNER_COLOR, (0.35 + 0.5 * e) * a), false, RED_INNER_W)
	if p > 0.7:
		_front.draw_line(Vector2(rect.position.x, rect.end.y - 1.5), Vector2(rect.end.x, rect.end.y - 1.5), Color(1, 1, 1, 0.5 * (p - 0.7) / 0.3 * a), 3.0)


## 지금 투명도 (걷힘·가드 불가 맥동 포함)
func _alpha() -> float:
	var a := 1.0 if _out < 0.0 else clampf(1.0 - _out / FADE_OUT, 0.0, 1.0)
	if unguardable:
		a *= 0.8 + 0.2 * sin(_t * TAU * RED_PULSE_HZ)
	return a


func _rgb() -> Color:
	var col := COLOR_RED if unguardable else COLOR_GUARD
	return Color(col.r, col.g, col.b)

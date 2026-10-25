extends Portal
class_name HiddenPortal
## 숨은 입구 포탈 (확장판): 처음엔 포탈이 아니라 **어두운 틈**으로만 보인다 (문 그림은 거의 안 보이고, 빛·가루 없음, 지도에도 없음).
## 소녀가 **가까이(REVEAL_RANGE) 다가가면** 틈이 벌어지며 포탈이 드러난다 (빛 터짐·소리·안내 글). 드러난 것은 깃발(seen_flag)로
## 기억해 다음부터는 처음부터 포탈이고 지도에도 ◆ 로 찍힌다.
## v1.1.0(기획자 요청 19 — 수액의 호수 입구를 찾기 쉽게): 틈을 더 크고 진하게, 등불이 없어도 HINT_RANGE 안에서 옅은 청록 맥동 빛이 새어 나오고,
##   **등불과 상관없이** REVEAL_RANGE 안에 오면 '본 것'(깃발·지도 ◆·잠긴 포탈 모습)이 된다. 들어가는 조건은 그대로 능력(requires_ability, 보통 "lantern") —
##   없이 손길을 내밀면 locked_message 안내(다른 잠긴 포탈과 같은 규칙). 등불 없이 드러날 때는 reveal_message 대신 locked_message 를 띄운다.
## seen_flag 가 비어 있으면 예전처럼 능력이 있어야만 드러난다.
## 쓰는 곳: 마을 등불 골목(village_02) 왼쪽 구석(x 720) → 숨은 내리막(hidden_descent). tools/link_sap_lake.py 가 끼워 넣는다.

## 틈의 크기 (가로·세로, 바닥 기준 위로). v1.1.0: 입구를 찾기 쉽게 다시 크고 진하게 (2026-10-19 의 50×210·0.62 는 너무 안 보였다).
const CRACK_W := 72.0
const CRACK_H := 250.0
## 틈의 진하기 (0~1)
const CRACK_ALPHA := 0.92
const CRACK_INNER := Color(0.12, 0.3, 0.42)
## 소녀가 이 거리(px) 안에 들어오면 드러난다 ('본 것' — 등불과 상관없이)
const REVEAL_RANGE := 400.0
## 이 거리 안에 들어오면 틈 안쪽이 점점 밝아진다 (드러나기 직전의 단서). 등불이 있으면 따뜻한 빛, 없으면 옅은 청록 맥동(수액 냄새)
const HINT_RANGE := 700.0
const HINT_TEAL := Color(0.35, 0.95, 0.85)
## 등불이 없을 때 틈 둘레로 새어 나오는 청록 안개의 진하기 (단서가 가장 셀 때, 더하기 혼합의 부드러운 빛)
const HINT_MIST := 0.32

## 드러났음을 기억하는 깃발 (비우면 등불만 있으면 처음부터 드러나 있다)
@export var seen_flag := "seen_hidden_descent"
## 드러날 때 띄우는 안내 (비우면 안 띄운다)
@export var reveal_message := ""

var _revealed := false
var _reveal_t := 1.0   # 드러나는 연출 진행도 (0→1)
var _crack_seed := 0
var _hint := 0.0       # 등불이 가까워질수록 0→1
var _crack_poly := PackedVector2Array()
var _crack_left := PackedVector2Array()
var _crack_right := PackedVector2Array()
var _crack_inner := PackedVector2Array()
var _mist: Sprite2D   # 등불 없이 다가올 때 틈에서 새어 나오는 청록 안개 (문 빛과 같은 부드러운 원 그림)


func _ready() -> void:
	super()
	_crack_seed = int(global_position.x * 5.0 + global_position.y * 11.0)
	_build_crack()
	_revealed = _is_known()
	_reveal_t = 1.0 if _revealed else 0.0
	_mist = Sprite2D.new()
	_mist.texture = _glow.texture
	_mist.material = _glow.material
	_mist.position = Vector2(0, -CRACK_H * 0.45)
	_mist.scale = Vector2(0.75, 1.35)
	_mist.visible = false
	add_child(_mist)
	move_child(_mist, 0)
	if not _revealed:
		# 드러나기 전에는 지도에 포탈 자리로 찍히지 않게 (Room._register_on_map 은 "portal" 무리를 센다)
		remove_from_group("portal")
	_apply_hidden()
	Progress.ability_gained.connect(_on_ability_gained)


func _is_known() -> bool:
	if requires_ability == "":
		return true
	if seen_flag != "":
		return Progress.has(seen_flag)
	return Progress.has_ability(requires_ability)


func _on_ability_gained(ability: String) -> void:
	if _revealed or ability != requires_ability:
		return
	if seen_flag == "":
		_reveal()
	# 깃발을 쓰는 틈은 다가갈 때 드러난다 (_process)


## 틈이 벌어지며 포탈이 드러난다.
func _reveal() -> void:
	if _revealed:
		return
	_revealed = true
	_reveal_t = 0.0
	if seen_flag != "":
		Progress.set_flag(seen_flag)
	if not is_in_group("portal"):
		add_to_group("portal")
	_add_to_map()
	_apply_hidden()
	flash()
	Sfx.play("bloom", -4.0, 0.0)
	Juice.shake(3.0)
	# 등불이 있으면 '길이 보인다', 없으면 '잠긴 길' 안내
	var msg := reveal_message if _can_enter() else locked_message
	if msg != "":
		var hud := get_tree().current_scene.get_node_or_null("CombatHUD") if get_tree().current_scene else null
		if hud:
			hud.show_message(msg, 3.0)
		_warned_at = Time.get_ticks_msec() / 1000.0   # 곧바로 손길을 내밀어도 같은 안내가 겹치지 않게


## 이 방의 지도 기록에 포탈 자리를 더한다 (방에 들어설 때는 숨어 있어서 빠져 있었다).
func _add_to_map() -> void:
	var room := _room()
	if room == null or str(room.get("room_id")) == "":
		return
	var entry: Dictionary = Progress.visited_rooms.get(room.room_id, {})
	if entry.is_empty():
		return
	var portals: Array = entry.get("portals", [])
	if not portals.has(position):
		portals.append(position)
	entry["portals"] = portals


## 숨은 상태: 문 그림은 거의 어둡고 빛·가루는 꺼 둔다. 드러나면 되돌린다.
func _apply_hidden() -> void:
	_glow.visible = _revealed
	_motes.emitting = _revealed
	if not _revealed:
		_sprite.modulate = Color(0.2, 0.2, 0.25, 0.45)
	queue_redraw()


## 틈이 드러나 포탈이 되었는가 (터치 상황 버튼 글자가 묻는다)
func is_revealed() -> bool:
	return _revealed


## 들어갈 수 있는가 (능력)
func _can_enter() -> bool:
	return requires_ability == "" or Progress.has_ability(requires_ability)


## 시험용: 틈 안쪽 단서 빛의 세기 (0~1, 등불 있음 / 없음)
func hint_level() -> float:
	return _hint


func _process(delta: float) -> void:
	super(delta)
	if not _revealed:
		# 드러나기 전에는 머리 위 '잠긴 길' 글자를 띄우지 않는다 (그냥 어두운 틈 — 손길을 내밀면 안내만 뜬다)
		_prompt.visible = false
		# 소녀가 다가오면 틈 안쪽이 밝아지다가(등불 = 따뜻한 빛, 없음 = 청록 맥동), 충분히 가까우면 드러난다
		var want := 0.0
		var p: Player = get_tree().get_first_node_in_group("player") as Player
		if p and requires_ability != "":
			var d := p.global_position.distance_to(global_position + Vector2(0, -CRACK_H * 0.5))
			want = clampf(1.0 - (d - REVEAL_RANGE) / (HINT_RANGE - REVEAL_RANGE), 0.0, 1.0)
			if d <= REVEAL_RANGE and (seen_flag != "" or Progress.has_ability(requires_ability)):
				_reveal()
		_hint = move_toward(_hint, want, delta * 2.0)
		var mist_on := _hint > 0.01 and not _can_enter()
		_mist.visible = mist_on
		if mist_on:
			var pulse := 0.5 + 0.5 * sin(_time * (1.4 + 3.0 * _hint))
			_mist.modulate = Color(HINT_TEAL, HINT_MIST * _hint * (0.6 + 0.4 * pulse))
		queue_redraw()
	elif _reveal_t < 1.0:
		_mist.visible = false
		_reveal_t = minf(_reveal_t + delta / 1.2, 1.0)
		_sprite.modulate = Color(0.2, 0.2, 0.25, 0.45).lerp(Color(1, 1, 1, 1), _reveal_t)
		queue_redraw()


## 틈 모양은 한 번만 만든다 (들쭉날쭉한 세로 금).
func _build_crack() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _crack_seed
	_crack_left.clear()
	_crack_right.clear()
	var n := 9
	for i in n + 1:
		var t := float(i) / n
		var y := -CRACK_H * t
		var w := CRACK_W * 0.5 * sin(t * PI) * (0.6 + 0.4 * rng.randf()) + 3.0
		# 들쭉날쭉함은 바깥쪽으로만 더해 왼쪽·오른쪽 금이 서로 엇갈리지 않게 (엇갈리면 다각형이 꼬여 안 그려진다)
		_crack_left.append(Vector2(-w - rng.randf_range(0, 4) * sin(t * PI), y))
		_crack_right.append(Vector2(w + rng.randf_range(0, 4) * sin(t * PI), y))
	_crack_poly.clear()
	for p in _crack_left:
		_crack_poly.append(p)
	for i in range(_crack_right.size() - 1, -1, -1):
		_crack_poly.append(_crack_right[i])
	_crack_inner.clear()
	for p in _crack_poly:
		_crack_inner.append(p * Vector2(0.45, 0.8) + Vector2(0, -CRACK_H * 0.08))


func _draw() -> void:
	# 어두운 틈: 안쪽은 아주 희미한 푸른 빛 (등불 없이는 '뭔가 있다' 정도만, 등불이 가까워지면 밝아진다)
	var k := 1.0 - _reveal_t
	if k <= 0.01 or _crack_poly.is_empty():
		return
	draw_colored_polygon(_crack_poly, Color(0.03, 0.03, 0.04, CRACK_ALPHA * k))
	var pulse := 0.5 + 0.5 * sin(_time * (1.4 + 3.0 * _hint))
	var lit := _can_enter()
	var warm := Color(1.0, 0.85, 0.55) if lit else HINT_TEAL
	# 등불이 없을 때의 청록 빛은 옅게 맥동만 (수액 냄새가 새어 나온다)
	var glow_a := (0.5 * _hint) if lit else (0.32 * _hint * (0.55 + 0.45 * pulse))
	draw_colored_polygon(_crack_inner, Color(CRACK_INNER.lerp(warm, _hint * (0.6 if lit else 0.75)), (0.18 + 0.12 * pulse + glow_a) * k))
	draw_polyline(_crack_left, Color(0.0, 0.0, 0.0, 0.6 * k), 2.0, true)
	draw_polyline(_crack_right, Color(0.0, 0.0, 0.0, 0.6 * k), 2.0, true)

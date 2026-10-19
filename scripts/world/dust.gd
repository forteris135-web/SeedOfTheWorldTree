extends Node2D
class_name Dust
## 재화 '빛 가루' 알갱이 (2026-10-19 기획자 요청 9번). 적이 쓰러지거나 정화될 때 몸에서 튀어 오른 뒤 소녀에게 날아가 흡수된다.
## 흡수되면 Progress.add_dust(value) 와 작은 소리. 소녀가 없거나(쓰러짐 등) 너무 오래 걸리면 저절로 흡수되고,
## 방을 떠나면서 사라질 때(_exit_tree)도 값을 잃지 않는다 — 떨어진 빛 가루는 반드시 소녀의 것이 된다.
## (하나뿐인 예외: 그사이 세이브를 불러왔으면 불러온 게임에는 더하지 않는다 — _same_game)
## 만들 때는 Dust.burst(부모, 자리, 총량, 소녀) 를 쓴다 — 총량을 여러 알갱이로 나눠 흩뿌린다.
## 세기 조절 상수는 아래 위에 모여 있다.

signal absorbed(value: int)

const SCENE_PATH := "res://scenes/world/dust.tscn"
const COLOR := Color(1.0, 0.92, 0.62)
## 알갱이 수: 총량을 이 값으로 나눈 만큼 (최소·최대 사이)
const PER_GRAIN := 3
const GRAINS_MIN := 2
const GRAINS_MAX := 14
## 튀어 오르는 시간(초) 범위 — 그 뒤 소녀에게 날아간다
const HOP_MIN := 0.3
const HOP_MAX := 0.55
const HOP_VEL_X := 300.0
const HOP_VEL_Y_MIN := 320.0
const HOP_VEL_Y_MAX := 640.0
const GRAVITY := 1500.0
## 날아가는 최고 속도와 가속 (픽셀/초)
const HOME_SPEED := 2000.0
const HOME_ACCEL := 2600.0
## 소녀의 가슴(씨앗) 자리: 소녀 원점(몸 가운데 — 캡슐 높이 134, 발은 원점 +67)에서 조금 아래.
## 가슴 씨앗 빛은 원점보다 약 8px 아래에 있다 (좌우는 보는 방향 따라 ±13 이라 가운데로 둔다).
const CHEST_OFFSET := Vector2(0, 8)
## 이 거리 안이면 흡수
const ABSORB_DIST := 38.0
## 이 시간(초)이 지나면 어디 있든 흡수 (소녀가 없을 때 등)
const MAX_LIFE := 4.0
## 소리 간격(ms) — 여러 알갱이가 한꺼번에 흡수될 때 소리가 겹치지 않게
const SFX_GAP_MS := 45
const TRAIL_LEN := 6

static var _last_sfx_ms := 0
static var _glow_tex: Texture2D

var value := 1
var _vel := Vector2.ZERO
var _hop := 0.4
var _life := 0.0
var _speed := 0.0
var _player: Node2D
var _absorbed := false
var _seed := 0.0
var _trail: Array[Vector2] = []
var _glow: Sprite2D
## 태어날 때의 진행 기록 (Progress.flags 사전 그 자체). 세이브를 불러오면 SaveGame.load_game 이 이 사전을 통째로
## 새것으로 바꾸므로, 다르면 '불러오기 전의 게임'에서 떨어진 가루다 → 값을 더하지 않는다
## (일시정지 메뉴 '불러오기' 뒤 페이드 동안 날던 가루가 불러온 세이브 값 위에 얹히지 않게).
var _ledger: Dictionary = Progress.flags


## 총량 total 을 알갱이로 나눠 at 에서 흩뿌린다. player 를 주면 바로 그쪽으로 날아가고, 없으면 "player" 그룹에서 찾는다.
## 돌려주는 값: 만든 알갱이들 (값의 합 = total). total 이 0 이하이거나 부모가 없으면 빈 배열.
static func burst(parent: Node, at: Vector2, total: int, player: Node2D = null) -> Array:
	var out: Array = []
	if total <= 0 or parent == null or not is_instance_valid(parent):
		return out
	var n := clampi(int(ceil(float(total) / PER_GRAIN)), GRAINS_MIN, GRAINS_MAX)
	n = mini(n, total)   # 알갱이 하나는 적어도 1
	var base := total / n
	var rem := total % n
	var scene := load(SCENE_PATH) as PackedScene
	for i in n:
		var d: Dust = scene.instantiate() if scene else Dust.new()
		d.value = base + (1 if i < rem else 0)
		d._player = player
		d._hop = randf_range(HOP_MIN, HOP_MAX)
		d._vel = Vector2(randf_range(-HOP_VEL_X, HOP_VEL_X), -randf_range(HOP_VEL_Y_MIN, HOP_VEL_Y_MAX))
		d._seed = randf() * TAU
		parent.add_child(d)
		d.global_position = at + Vector2(randf_range(-22.0, 22.0), randf_range(-30.0, 10.0))
		out.append(d)
	return out


func _ready() -> void:
	add_to_group("dust")
	z_index = 5
	if _glow_tex == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		grad.colors = PackedColorArray([Color(COLOR, 0.55), Color(COLOR, 0.18), Color(COLOR, 0.0)])
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.width = 64
		gt.height = 64
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		_glow_tex = gt
	_glow = Sprite2D.new()
	_glow.texture = _glow_tex
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add
	# HDR 글로우 문턱(1.0)을 넘겨 발광
	_glow.modulate = Color(1.7, 1.6, 1.2, 1.0)
	_glow.scale = Vector2.ONE * (0.5 + sqrt(float(value)) * 0.12)
	add_child(_glow)


func _process(delta: float) -> void:
	if _absorbed:
		return
	_life += delta
	if _life < _hop:
		# 튀어 오름: 포물선
		_vel.y += GRAVITY * delta
		_vel.x = move_toward(_vel.x, 0.0, 320.0 * delta)
		global_position += _vel * delta
	else:
		if _player == null or not is_instance_valid(_player):
			_player = get_tree().get_first_node_in_group("player") as Node2D
		var p := _player as Player
		var target_ok := p != null and is_instance_valid(p) and p.state != Player.State.DEAD
		if target_ok:
			var target: Vector2 = p.global_position + CHEST_OFFSET
			var to := target - global_position
			var dist := to.length()
			_speed = minf(_speed + HOME_ACCEL * delta, HOME_SPEED)
			var want := to / maxf(dist, 1.0) * _speed
			_vel = _vel.lerp(want, 1.0 - exp(-7.0 * delta))
			var step := _vel * delta
			if dist <= ABSORB_DIST or step.length() >= dist:
				global_position = target
				_absorb(true)
				return
			global_position += step
		else:
			# 소녀가 없으면(쓰러져 있으면) 제자리에 떠서 기다린다
			_vel = _vel.lerp(Vector2(0, -24.0), 1.0 - exp(-4.0 * delta))
			global_position += _vel * delta
	if _life > MAX_LIFE:
		_absorb(false)
		return
	_trail.push_front(global_position)
	if _trail.size() > TRAIL_LEN:
		_trail.pop_back()
	var pulse := 0.85 + 0.15 * sin(_life * 14.0 + _seed)
	_glow.scale = Vector2.ONE * (0.5 + sqrt(float(value)) * 0.12) * pulse
	queue_redraw()


## 흡수: 값을 더하고 작은 번쩍임 뒤 사라진다.
func _absorb(by_player: bool) -> void:
	if _absorbed:
		return
	_absorbed = true
	if _same_game():
		Progress.add_dust(value)
		absorbed.emit(value)
	if by_player:
		Fx.spawn("pickup_sparkle", global_position)   # 이펙트 리뉴얼: 흡수 반짝임
		var now := Time.get_ticks_msec()
		if now - _last_sfx_ms >= SFX_GAP_MS:
			_last_sfx_ms = now
			Sfx.play("blip", -12.0, 0.25)
	set_process(false)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(2.4, 2.4), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.12)
	tw.finished.connect(queue_free)


## 방을 떠나는 등 흡수되기 전에 사라지면 값은 그대로 소녀의 것이 된다 (빛 가루는 잃지 않는다).
func _exit_tree() -> void:
	if not _absorbed:
		_absorbed = true
		if _same_game():
			Progress.add_dust(value)


## 이 알갱이가 떨어진 뒤로 세이브를 불러오지 않았는가 (위 _ledger 설명)
func _same_game() -> bool:
	return is_same(Progress.flags, _ledger)


func _draw() -> void:
	var r := 2.6 + sqrt(float(value)) * 0.7
	var n := _trail.size()
	for i in range(1, n):
		var k := 1.0 - float(i) / n
		draw_line(_trail[i - 1] - global_position, _trail[i] - global_position, Color(COLOR, 0.5 * k), r * 1.4 * k, true)
	var pulse := 0.85 + 0.15 * sin(_life * 14.0 + _seed)
	draw_circle(Vector2.ZERO, r * 1.9 * pulse, Color(COLOR, 0.22))
	draw_circle(Vector2.ZERO, r * pulse, Color(COLOR, 0.95))
	draw_circle(Vector2(-r * 0.25, -r * 0.25), r * 0.45, Color(1, 1, 1, 0.9))

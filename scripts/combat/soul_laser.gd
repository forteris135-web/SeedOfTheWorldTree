extends Node2D
class_name SoulLaser
## 빛의 영혼 기술 (2026-10-19 이펙트 리뉴얼 F1): 레이저.
## 흐름: 모으기(charge_time 초, 소녀의 칼 쥔 손에 빛이 모인다) → 발사(그 순간 앞으로 곧게 뻗어 벽에서 멈춘다)
##       → 빛줄기가 잠깐 남아 깜빡이다 사라진다 (show_time 초).
## 판정: 소녀 가운데 뒤 SHOT_BACK_REACH 부터 빛줄기 끝(벽 또는 사거리)까지, 높이 width 의 사각형.
##       발사 뒤 active_time 동안 그 안에 든 적을 '주인마다 한 번씩' 맞힌다 (여러 적을 한꺼번에 꿰뚫는다).
## 사거리는 예전 빛 투사체가 날아가던 거리 (속도 × 수명 = 1540px), 피해·흐트러짐·쿨다운은 그대로 (player.gd 의 light_*).
## 벽: 지형(층 1)에서 멈춘다. 한쪽 방향 가지(one_way 발판)는 지나간다. 끝이 '때리면 부서지는 벽'이면 한 대 친다.
## 모으는 동안 소녀가 맞거나 쓰러지거나 쉬면 쏘지 않고, 쿨다운을 돌려준다 (씨앗 베기 예비동작이 끊긴 것과 같은 규칙).
## 그림: art/fx/laser_start · laser_body · laser_end · orb_glow 를 빛(금빛) 팔레트로, 더하기 섞기 (밝기 배수는 1 안쪽 —
##   방의 글로우가 '스크린' 섞기라 값이 너무 크면 회색으로 죽는다).

signal fired(hits: int)
signal cancelled

const BACK_REACH := 15.0          # player.gd SHOT_BACK_REACH 와 같은 값
const HAND_OFFSET := Vector2(44, -20)   # 빛줄기가 시작하는 자리 (소녀 가운데 기준, 오른쪽을 볼 때)
const BEAM_Y := -20.0             # 빛줄기 높이 (소녀 가운데 기준) — 예전 투사체가 나가던 높이
const MAX_HITS := 24

var player: Node2D
var facing := 1
var damage := 136.0
var poise := 30.0
var beam_range := 1540.0
var width := 81.0
var charge_time := 0.12
var active_time := 0.08
var show_time := 0.42

var origin := Vector2.ZERO        # 발사한 자리 (빛줄기 시작)
var end_point := Vector2.ZERO     # 빛줄기 끝 (벽 또는 사거리)
var hit_wall := false
var phase := "charge"             # charge / beam
var hit_count := 0

var _t := 0.0
var _hit_owners := {}
var _charge: Sprite2D
var _start: Sprite2D
var _body: Sprite2D
var _end: Sprite2D
var _mat: ShaderMaterial
var _query: PhysicsShapeQueryParameters2D
var _rect: RectangleShape2D


func _ready() -> void:
	z_index = 6
	_mat = Fx.make_material("light", true, 0.12)
	_charge = _sprite("orb_glow", Vector2(0.5, 0.5))
	_start = _sprite("laser_start", Vector2(0.56, 0.5))
	_body = _sprite("laser_body", Vector2(0.0, 0.5))
	_end = _sprite("laser_end", Vector2(0.7, 0.53))
	_start.visible = false
	_body.visible = false
	_end.visible = false
	_charge.scale = Vector2.ONE * 0.15
	_follow_hand()


func _sprite(tex_name: String, pivot: Vector2) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Fx.texture(tex_name)
	s.material = _mat
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.centered = true
	if s.texture:
		s.offset = (Vector2(0.5, 0.5) - pivot) * s.texture.get_size()
	add_child(s)
	return s


## 모으는 동안 손 자리 (뼈대가 있으면 칼 쥔 손, 없으면 앞쪽 고정 자리)
func _hand() -> Vector2:
	if player == null or not is_instance_valid(player):
		return global_position
	var vis := player.get_node_or_null("Visual")
	if vis and vis.has_method("hand_global"):
		return vis.hand_global()
	return player.global_position + Vector2(HAND_OFFSET.x * facing, HAND_OFFSET.y)


func _follow_hand() -> void:
	_charge.global_position = _hand()


func _physics_process(delta: float) -> void:
	_t += delta
	if phase == "charge":
		if player == null or not is_instance_valid(player) or _interrupted():
			cancelled.emit()
			queue_free()
			return
		_follow_hand()
		var k := clampf(_t / maxf(charge_time, 0.001), 0.0, 1.0)
		_charge.scale = Vector2.ONE * lerpf(0.15, 0.6, k * k)
		_charge.modulate = Color(1.0, 0.97, 0.9, 0.4 + 0.6 * k)
		if _t >= charge_time:
			_fire()
		return
	# 빛줄기
	var bt := _t - charge_time
	if bt <= active_time + 0.0001:
		_apply_hits()
	if bt >= show_time:
		queue_free()
		return
	_update_beam(bt)


## 모으는 동안 끊겼는가 (맞음·쓰러짐·쉬기·정화)
func _interrupted() -> bool:
	if not ("state" in player):
		return false
	var st = player.get("state")
	return st == Player.State.HIT or st == Player.State.DEAD or st == Player.State.REST or st == Player.State.PURIFY


func _fire() -> void:
	phase = "beam"
	if player and is_instance_valid(player) and "facing" in player:
		facing = int(player.get("facing"))
	var pc: Vector2 = player.global_position
	origin = pc + Vector2(HAND_OFFSET.x * facing, BEAM_Y)
	var far := pc + Vector2(beam_range * facing, BEAM_Y)
	# 벽 찾기: 소녀 가운데에서 선을 긋는다 (손이 벽 속에 들어가 있어도 벽 앞에서 멈추게)
	var space := get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(Vector2(pc.x, pc.y + BEAM_Y), far, 1)
	var hit := space.intersect_ray(ray)
	var guard_n := 0
	while not hit.is_empty() and guard_n < 8:
		var c = hit.get("collider")
		if c is Platform and c.one_way:
			ray.exclude = ray.exclude + [hit["rid"]]
			hit = space.intersect_ray(ray)
			guard_n += 1
		else:
			break
	end_point = far
	hit_wall = not hit.is_empty()
	if hit_wall:
		end_point = Vector2(hit["position"].x, far.y)
		var col = hit.get("collider")
		if col and col.has_method("receive_hit"):
			col.receive_hit(_make_hit(), null)
	# 손이 벽 너머가 되지 않게
	if (end_point.x - origin.x) * facing < 0.0:
		origin.x = end_point.x
	_rect = RectangleShape2D.new()
	_query = PhysicsShapeQueryParameters2D.new()
	_query.shape = _rect
	_query.collision_mask = 16   # 적 맞는 영역
	_query.collide_with_areas = true
	_query.collide_with_bodies = false
	var back_x := pc.x - facing * BACK_REACH
	var len := absf(end_point.x - back_x)
	_rect.size = Vector2(maxf(len, 1.0), width)
	_query.transform = Transform2D(0.0, Vector2((back_x + end_point.x) * 0.5, origin.y))
	_charge.visible = false
	_start.visible = true
	_body.visible = true
	_end.visible = true
	_start.global_position = origin
	_body.global_position = origin
	_end.global_position = end_point
	_start.scale = Vector2(0.27 * facing, 0.27)
	_end.scale = Vector2(0.42 * facing, 0.42)
	_apply_hits()
	_update_beam(0.0)
	Fx.spawn("laser_flash", origin, {"facing": facing})
	if hit_wall:
		Fx.spawn("laser_wall", end_point, {"facing": facing})
	fired.emit(hit_count)


func _make_hit() -> HitData:
	var h := HitData.make(damage, poise, player if is_instance_valid(player) else self, Vector2(260, -100))
	h.from_player = true
	h.hitstop = 0.04
	h.soul = "light"
	return h


## 빛줄기 안의 적을 주인마다 한 번씩 맞힌다
func _apply_hits() -> void:
	if _query == null:
		return
	var found := get_world_2d().direct_space_state.intersect_shape(_query, MAX_HITS)
	var first := hit_count == 0
	for r in found:
		var area = r.get("collider")
		if not (area is Hurtbox):
			continue
		var owner_node: Node = area.owner_node
		var key = owner_node if owner_node else area
		if _hit_owners.has(key):
			continue
		var result: String = area.receive(_make_hit())
		if result == "ignored":
			continue
		_hit_owners[key] = true
		hit_count += 1
		Fx.spawn("laser_hit", Vector2(area.global_position.x, origin.y), {"facing": facing})
	if first and hit_count > 0:
		Sfx.play("heavy_hit", -3.0, 0.08)
		Juice.hitstop(0.05, 0.05)
		Juice.shake(4.0)


## 빛줄기 모양: 처음에 굵게 번쩍였다가 가늘어지며 깜빡이다 사라진다
func _update_beam(bt: float) -> void:
	var u := clampf(bt / maxf(show_time, 0.001), 0.0, 1.0)
	var len := absf(end_point.x - origin.x)
	var tw: float = float(_body.texture.get_width()) if _body.texture else 512.0
	var th: float = float(_body.texture.get_height()) if _body.texture else 49.0
	var swell := 1.0 + 0.6 * (1.0 - smoothstep(0.0, 0.12, u))     # 쏘는 순간 굵게
	var thin := 1.0 - 0.75 * smoothstep(0.45, 1.0, u)              # 끝에 가늘어짐
	var flick := 0.88 + 0.12 * sin(bt * 70.0) * sin(bt * 31.0 + 1.0)
	var h := width * 0.82 * swell * thin * flick
	_body.scale = Vector2(len / tw * facing, h / th)
	var a := 1.0 - smoothstep(0.55, 1.0, u)
	_body.modulate = Color(0.95, 0.92, 0.85, a)
	_start.modulate = Color(0.95, 0.92, 0.85, a)
	_end.modulate = Color(0.95, 0.92, 0.85, a * (1.0 if hit_wall else 0.55))
	var sk := 0.27 * (1.0 + 0.3 * (1.0 - smoothstep(0.0, 0.2, u))) * (0.8 + 0.2 * flick)
	_start.scale = Vector2(sk * facing, sk)
	var ek := 0.42 * (0.8 + 0.4 * smoothstep(0.0, 0.15, u)) * (0.85 + 0.15 * flick)
	if not hit_wall:
		ek *= 0.6
	_end.scale = Vector2(ek * facing, ek)
	_end.visible = len > 30.0

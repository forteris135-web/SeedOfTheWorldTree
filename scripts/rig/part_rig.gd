extends Node2D
class_name PartRig
## 부위 뼈대(파트 리그). art/rigs/<id>/rig.json (tools/rig_cut.gd 가 만든다)을 읽어 부위 그림(Sprite2D)을 관절로 잇는다.
## 이 노드의 원점 = 몸 가운데 아래의 **땅**(발바닥 높이). 뼈대는 늘 **오른쪽을 본다** (왼쪽은 scale.x 를 뒤집어서).
## 쓰는 법은 RIGS.md. 움직임(자세·걸음·IK)은 RigMotion 이 rot/off/scl 배열에 적고 apply() 로 그림에 옮긴다.
##
## 구조 (모바일 성능을 위해):
##  - 뼈(bone)는 노드가 아니라 배열의 변환(Transform2D)이다. apply() 가 부모→자식 순서로 한 번에 계산한다.
##  - 그림(Sprite2D)은 뼈 계층과 상관없이 '그리기 순서(z)'대로 한 줄로 늘어선다 → 뒷팔은 몸통 뒤, 칼팔은 몸통 앞처럼
##    계층과 앞뒤를 따로 정할 수 있다 (노드 계층이면 자식이 늘 부모 위에 그려져서 이게 안 된다).
##  - 뼈에 무엇을 붙이려면 attach(뼈, 노드, 자리): 매 apply() 에 그 뼈를 따라간다 (눈빛·불빛 등).
##  - 피격 번쩍임은 부위 전체가 함께 쓰는 셰이더(flash)로, 색·투명도는 이 노드의 modulate 로.
##  - 잔상은 미리 만든 그림 묶음을 돌려 쓴다 (매 프레임 노드를 만들지 않는다).
##
## 좌표: '뼈대 단위' = 원본 시트 px (뒤집은 뒤). _skel 노드가 game_scale 로 줄여 게임 px 로 바꾼다.
## 각도: 라디안, 시계 방향 + (Godot 그대로). 축(tip)이 있는 부위(팔다리)는 회전 0 = 부모 틀에서 똑바로 아래.

const FLASH_SHADER := preload("res://shaders/rig_flash.gdshader")

## art/rigs/<id>/rig.json 의 id. 비워 두면 build() 를 직접 불러야 한다.
@export var rig_id := ""

var data: Dictionary = {}
var game_scale := 0.15
## 뼈 이름 → 번호
var index := {}
var names: PackedStringArray = []
var parent: PackedInt32Array = []
## 관절 자리(부모 틀, 뼈대 단위)와 쉬는 자세 회전
var base_pos: PackedVector2Array = []
var rest: PackedFloat32Array = []
## 축(tip)이 있는 부위인가 (팔다리: 회전 0 = 똑바로 아래)
var has_axis: PackedByteArray = []
## 움직임이 적는 값: 지역 회전 / 더하는 자리 / 지역 배율
var rot: PackedFloat32Array = []
var off: PackedVector2Array = []
var scl: PackedVector2Array = []
## 뼈대 뿌리(첫 뼈)의 자리 (뼈대 단위, 이 노드 원점 = 땅 기준)와 몸 전체 변환(쓰러짐 등). apply() 가 쓴다.
var root_pos := Vector2.ZERO
var body_xf := Transform2D.IDENTITY
## apply() 결과: 뼈의 변환 (뼈대 뿌리 틀 = _skel 기준, 뼈대 단위)
var xf: Array[Transform2D] = []
## 껍질 점 (뼈 틀, 뼈대 단위) — 땅 닿기·쓰러짐·시험에 쓴다
var hulls: Array[PackedVector2Array] = []
var sole := {}            # 뼈 번호 → 발바닥 점 (뼈 틀)
var bone_len: PackedFloat32Array = []

var _skel: Node2D
var _sprites: Array[Sprite2D] = []
var _sprite_bone: PackedInt32Array = []
var _sprite_local: Array[Transform2D] = []
var _bone_sprite: PackedInt32Array = []   # 뼈 번호 → 그림 번호 (없으면 -1)
var _default_tex := {}    # 뼈 번호 → [텍스처, pivot, rot]
var _variants := {}       # 뼈 번호 → {이름: [텍스처, pivot, rot]}
var _attached: Array = [] # [노드, 뼈 번호, 자리]
var _mat: ShaderMaterial
var _ghost_root: Node2D
var _ghosts: Array = []   # 각 원소: {sprites: Array[Sprite2D], a: float}
var _ghost_bones: PackedInt32Array = []
var _ghost_next := 0
var _built := false
var _flash_amt := 0.0
var _flash_col := Color(1.6, 1.6, 1.6)
var _dissolve_amt := 0.0
var _dissolve_col := Color(1.4, 0.9, 0.5)

static var _cache := {}


func _ready() -> void:
	if rig_id != "" and not _built:
		build(rig_id)


## rig.json 을 읽어 그림을 만든다. 같은 id 는 한 번만 읽어 둔다 (적이 여럿이어도 파일을 다시 읽지 않는다).
static func load_data(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var path := "res://art/rigs/%s/rig.json" % id
	if not FileAccess.file_exists(path):
		push_error("뼈대 파일이 없다: " + path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("뼈대 파일을 읽지 못했다: " + path)
		return {}
	_cache[id] = parsed
	return parsed


func build(id: String) -> bool:
	rig_id = id
	data = load_data(id)
	if data.is_empty():
		return false
	_built = true
	game_scale = float(data.get("game_scale", 0.15))
	_mat = ShaderMaterial.new()
	_mat.shader = FLASH_SHADER
	material = _mat
	_ghost_root = Node2D.new()
	_ghost_root.name = "Ghosts"
	_ghost_root.use_parent_material = false
	add_child(_ghost_root)
	_skel = Node2D.new()
	_skel.name = "Skel"
	_skel.use_parent_material = true
	_skel.scale = Vector2(game_scale, game_scale)
	add_child(_skel)
	var bones: Array = data["bones"]
	var n := bones.size()
	parent.resize(n); base_pos.resize(n); rest.resize(n); has_axis.resize(n)
	rot.resize(n); off.resize(n); scl.resize(n); bone_len.resize(n); _bone_sprite.resize(n)
	xf.resize(n); hulls.resize(n)
	for i in n:
		var b: Dictionary = bones[i]
		index[b["name"]] = i
		names.append(b["name"])
	for i in n:
		var b: Dictionary = bones[i]
		parent[i] = index.get(b["parent"], -1) if str(b["parent"]) != "" else -1
		base_pos[i] = _v(b["pos"])
		rest[i] = deg_to_rad(float(b["rest"]))
		has_axis[i] = 1 if b.has("len") else 0
		bone_len[i] = float(b.get("len", 0.0))
		rot[i] = rest[i]
		off[i] = Vector2.ZERO
		scl[i] = Vector2.ONE
		xf[i] = Transform2D.IDENTITY
		_bone_sprite[i] = -1
		var hp := PackedVector2Array()
		for q in b.get("hull", []):
			hp.append(_v(q))
		hulls[i] = hp
		if b.has("sole"):
			sole[i] = _v(b["sole"])
	# 그림: z 가 작은 것부터 (같으면 설계도 순서)
	var order: Array = range(n)
	order.sort_custom(func(a, c):
		var za := int(bones[a].get("z", 0))
		var zc := int(bones[c].get("z", 0))
		if za != zc:
			return za < zc
		return a < c)
	for i in order:
		var b: Dictionary = bones[i]
		if not b.has("tex") or bool(b.get("hidden", false)):
			continue
		var tex: Texture2D = load(b["tex"])
		if tex == null:
			push_error("부위 그림이 없다: " + str(b["tex"]))
			continue
		var spr := Sprite2D.new()
		spr.name = str(b["name"])
		spr.texture = tex
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		spr.use_parent_material = true
		var pv := _v(b["pivot"])
		spr.offset = -pv
		if b.has("modulate"):
			var m: Array = b["modulate"]
			spr.self_modulate = Color(m[0], m[1], m[2], m[3] if m.size() > 3 else 1.0)
		_skel.add_child(spr)
		_bone_sprite[i] = _sprites.size()
		_sprites.append(spr)
		_sprite_bone.append(i)
		var k := float(b.get("tex_scale", 2.0))
		_sprite_local.append(Transform2D(deg_to_rad(float(b["rot"])), Vector2(k, k), 0.0, Vector2.ZERO))
		_default_tex[i] = [tex, pv, deg_to_rad(float(b["rot"]))]
		if b.has("variants"):
			var vs := {}
			for vname in b["variants"]:
				var vd: Dictionary = b["variants"][vname]
				var vt: Texture2D = load(vd["tex"])
				if vt:
					vs[vname] = [vt, _v(vd["pivot"]), deg_to_rad(float(vd["rot"]))]
			_variants[i] = vs
	apply()
	return true


static func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


func bone_index(bone_name: String) -> int:
	return index.get(bone_name, -1)


func has_bone(bone_name: String) -> bool:
	return index.has(bone_name)


## 쉬는 자세로 되돌린다.
func reset_pose() -> void:
	for i in rot.size():
		rot[i] = rest[i]
		off[i] = Vector2.ZERO
		scl[i] = Vector2.ONE
	body_xf = Transform2D.IDENTITY


## 뼈 변환을 계산하고 그림·붙인 노드를 옮긴다. 움직임 쪽이 한 프레임에 한 번 부른다.
func apply() -> void:
	compute()
	_skel.transform = Transform2D(0.0, Vector2(game_scale, game_scale), 0.0, Vector2.ZERO) * body_xf
	for s in _sprites.size():
		_sprites[s].transform = xf[_sprite_bone[s]] * _sprite_local[s]
	for a in _attached:
		var node: Node2D = a[0]
		if is_instance_valid(node):
			node.position = to_rig_local(xf[a[1]] * (a[2] as Vector2))


## 뼈 변환만 계산한다 (그림은 안 옮김). 움직임이 IK·땅 닿기를 고치려고 중간에 부른다.
func compute() -> void:
	for i in rot.size():
		var local := Transform2D(rot[i], scl[i], 0.0, base_pos[i] + off[i])
		var p := parent[i]
		if p < 0:
			local.origin = root_pos + off[i]
			xf[i] = local
		else:
			xf[i] = xf[p] * local


## 한 뼈의 변환을 그 부모 기준으로 다시 계산한다 (자식들은 compute_from 으로).
func compute_from(i: int) -> void:
	for j in range(i, rot.size()):
		if j != i and not _is_descendant(j, i):
			continue
		var local := Transform2D(rot[j], scl[j], 0.0, base_pos[j] + off[j])
		var p := parent[j]
		xf[j] = local if p < 0 else xf[p] * local
		if p < 0:
			xf[j].origin = root_pos + off[j]


func _is_descendant(j: int, i: int) -> bool:
	var p := parent[j]
	while p >= 0:
		if p == i:
			return true
		p = parent[p]
	return false


## 뼈의 세계(뼈대 뿌리 틀) 회전
func world_rot(i: int) -> float:
	return xf[i].get_rotation()


## 뼈대 단위 점(뿌리 틀) → 이 노드의 지역 좌표(게임 px). body_xf(쓰러짐 등)를 포함한다.
func to_rig_local(p: Vector2) -> Vector2:
	return (body_xf * p) * game_scale


## 뼈 틀의 점 → 이 노드의 지역 좌표(게임 px).
func bone_point(bone_name: String, local := Vector2.ZERO) -> Vector2:
	var i := bone_index(bone_name)
	if i < 0:
		return Vector2.ZERO
	return to_rig_local(xf[i] * local)


## 노드를 뼈에 붙인다: apply() 마다 position 만 따라간다 (회전은 따라가지 않는다 — 빛·입자용).
func attach(bone_name: String, node: Node2D, local := Vector2.ZERO) -> void:
	var i := bone_index(bone_name)
	if i < 0:
		return
	if node.get_parent() == null:
		add_child(node)
	_attached.append([node, i, local])


## 부위 그림을 바꾼다 (얼굴·구원형 머리·부서짐 등). "" 이면 기본 그림.
func set_variant(bone_name: String, variant: String) -> void:
	var i := bone_index(bone_name)
	if i < 0 or _bone_sprite[i] < 0:
		return
	var v: Array = _default_tex[i]
	if variant != "" and _variants.has(i) and (_variants[i] as Dictionary).has(variant):
		v = _variants[i][variant]
	var s := _bone_sprite[i]
	_sprites[s].texture = v[0]
	_sprites[s].offset = -(v[1] as Vector2)
	var k := _sprite_local[s].get_scale().x
	_sprite_local[s] = Transform2D(float(v[2]), Vector2(k, k), 0.0, Vector2.ZERO)


## 보는 쪽과 크기를 한 번에 (뼈대는 오른쪽을 보는 그림 — 왼쪽이면 scale.x 를 뒤집는다).
## 움직임(RigMotion)을 쓰면 뒤집는 프레임에 motion.flip_feet() 도 불러야 딛은 발이 세상에 남는다.
func set_facing(right: bool, k := 1.0) -> void:
	scale = Vector2(k if right else -k, k)


func sprite_of(bone_name: String) -> Sprite2D:
	var i := bone_index(bone_name)
	return _sprites[_bone_sprite[i]] if i >= 0 and _bone_sprite[i] >= 0 else null


## 피격 번쩍임 (0~1) 과 그 색 (HDR 가능: 1 을 넘기면 글로우가 번진다). 값이 바뀔 때만 셰이더에 넘긴다.
func set_flash(amount: float, col := Color(1.6, 1.6, 1.6)) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if amount != _flash_amt:
		_flash_amt = amount
		_mat.set_shader_parameter("flash", amount)
	if col != _flash_col:
		_flash_col = col
		_mat.set_shader_parameter("flash_color", col)


## 흩어져 사라짐 (0 = 그대로, 1 = 다 사라짐)과 사라지는 가장자리 색
func set_dissolve(amount: float, edge := Color(1.4, 0.9, 0.5)) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if amount != _dissolve_amt:
		_dissolve_amt = amount
		_mat.set_shader_parameter("dissolve", amount)
	if edge != _dissolve_col:
		_dissolve_col = edge
		_mat.set_shader_parameter("dissolve_edge", edge)


func dissolve_amount() -> float:
	return _dissolve_amt


## 껍질 점들을 이 노드의 지역 좌표(뼈대 단위가 아니라 body_xf 포함 뼈대 단위)로 돌며 가장 낮은 y (땅이 0, 아래 +)
## bones 가 비면 모든 부위. compute() 뒤에 부른다.
func lowest_y(bones: PackedInt32Array = PackedInt32Array(), with_body := true) -> float:
	var m := -INF
	var list := bones if bones.size() > 0 else PackedInt32Array(range(xf.size()))
	for i in list:
		var t := (body_xf * xf[i]) if with_body else xf[i]
		for q in hulls[i]:
			m = maxf(m, (t * q).y)
	return m


## 가장 높은 y (머리 꼭대기 쪽, 음수)
func highest_y() -> float:
	var m := INF
	for i in xf.size():
		var t := body_xf * xf[i]
		for q in hulls[i]:
			m = minf(m, (t * q).y)
	return m


## 모든 부위를 덮는 상자 (뼈대 단위, body_xf 포함)
func bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for i in xf.size():
		var t := body_xf * xf[i]
		for q in hulls[i]:
			var p := t * q
			if first:
				r = Rect2(p, Vector2.ZERO)
				first = false
			else:
				r = r.expand(p)
	return r


# ---------- 잔상 ----------

## 잔상에 넣을 부위들 (이름). 처음 snapshot 때 그림 묶음을 count 개 만들어 돌려 쓴다.
func setup_ghosts(bone_names: Array, count := 6) -> void:
	_ghost_bones = PackedInt32Array()
	for nm in bone_names:
		var i := bone_index(str(nm))
		if i >= 0 and _bone_sprite[i] >= 0:
			_ghost_bones.append(i)
	for g in _ghosts:
		for s in g["sprites"]:
			s.queue_free()
	_ghosts.clear()
	for c in count:
		var list: Array[Sprite2D] = []
		for i in _ghost_bones:
			var s := Sprite2D.new()
			s.centered = false
			s.visible = false
			s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			_ghost_root.add_child(s)
			list.append(s)
		_ghosts.append({"sprites": list, "a": 0.0})
	_ghost_next = 0


## 지금 자세를 잔상 한 장으로 남긴다 (색·투명도 col). 잔상은 이 노드의 부모 좌표가 아니라 이 노드 기준이라
## 몸과 함께 움직인다 — 짧게(0.3초 안) 사라지므로 괜찮다.
func snapshot_ghost(col: Color) -> void:
	if _ghosts.is_empty():
		return
	var g: Dictionary = _ghosts[_ghost_next]
	_ghost_next = (_ghost_next + 1) % _ghosts.size()
	var list: Array = g["sprites"]
	for k in _ghost_bones.size():
		var i := _ghost_bones[k]
		var src := _sprites[_bone_sprite[i]]
		var s: Sprite2D = list[k]
		s.texture = src.texture
		s.offset = src.offset
		s.transform = _skel.transform * src.transform
		s.modulate = col
		s.visible = true
	g["a"] = col.a


## 잔상을 흐리게 한다 (매 프레임).
func fade_ghosts(delta: float, speed := 3.5) -> void:
	for g in _ghosts:
		if g["a"] <= 0.0:
			continue
		g["a"] = maxf(float(g["a"]) - delta * speed, 0.0)
		for s in g["sprites"]:
			s.modulate.a = g["a"]
			if g["a"] <= 0.0:
				s.visible = false


func hide_ghosts() -> void:
	for g in _ghosts:
		g["a"] = 0.0
		for s in g["sprites"]:
			s.visible = false

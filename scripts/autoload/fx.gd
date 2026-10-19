extends Node
## 이펙트 도우미 (자동 로드 Fx, 2026-10-19 이펙트 리뉴얼 F1).
## 그림 이펙트를 이름으로 띄운다:  Fx.spawn("hit_spark", 자리, {"facing": -1, "scale": 1.2})
## 이름과 모양(그림·섞기·수명·크기·투명도·회전·팔레트·호 드러내기·딸린 이펙트)은 scripts/fx/fx_table.gd 의 표에 있다.
## 자세한 쓰는 법은 scripts/fx/README.md.
##
## 아이폰을 위해:
## - 이펙트 노드(FxSprite)는 미리 만들어 두고 돌려 쓴다 (풀). 한꺼번에 MAX_ACTIVE 개까지만 보인다.
##   가득 차면 우선순위가 낮고(먼지·빛 알갱이) 오래된 것부터 비켜 주고, 비켜 줄 것이 없으면 새 것을 띄우지 않는다.
## - 매 프레임 할 일은 여기 _process 한 곳에서 몰아서 한다. 프레임마다 새로 만드는 것이 없다.
## - 그림(art/fx/)은 처음에 한 번 읽어 둔다. 팔레트·호 드러내기가 없는 이펙트는 공용 재질 두 개(더하기·섞기)를 함께 써서 묶어 그린다.
## - 방이 바뀌면 떠 있던 이펙트를 모두 거둔다 (옛 방 자리에 남지 않게).
##
## 이펙트는 이 노드 밑의 겹(_layer)에 그려진다: 화면(카메라) 기준 세계 좌표 그대로, z_index 6(소녀·적 앞)이 기본.

const Table := preload("res://scripts/fx/fx_table.gd")
const FxSpriteScript := preload("res://scripts/fx/fx_sprite.gd")
const SHADER_ADD := preload("res://shaders/fx_add.gdshader")
const SHADER_MIX := preload("res://shaders/fx_mix.gdshader")
const ART_DIR := "res://art/fx/"

## 한꺼번에 보이는 이펙트 수의 상한 (아이폰 11 Pro 기준으로 넉넉하게)
const MAX_ACTIVE := 72

var _layer: Node2D
var _pool: Array[FxSprite] = []
var _active: Array[FxSprite] = []
var _tex := {}          # 그림 이름 -> Texture2D
var _frames := {}       # 이펙트 이름 -> [Texture2D, ...] (frames 가 있는 것만)
var _mat_add: CanvasItemMaterial
var _mat_mix: CanvasItemMaterial
var _scene: Node
## 시험용 집계
var spawned_total := 0
var dropped_total := 0
var stolen_total := 0


func _ready() -> void:
	_layer = Node2D.new()
	_layer.name = "FxLayer"
	add_child(_layer)
	_mat_add = CanvasItemMaterial.new()
	_mat_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_mat_add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_mat_mix = CanvasItemMaterial.new()
	_mat_mix.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	for name in Table.EFFECTS:
		var def: Dictionary = Table.EFFECTS[name]
		var texs: Array = def["tex"] if def["tex"] is Array else [def["tex"]]
		var loaded: Array = []
		for tn in texs:
			loaded.append(texture(tn))
		if texs.size() > 1:
			_frames[name] = loaded


## 그림 이름(art/fx/<이름>.png)으로 텍스처. 처음 부를 때 읽어 둔다. 다른 노드(레이저·초승달 검기·보호막)도 이걸 쓴다.
func texture(tex_name: String) -> Texture2D:
	if not _tex.has(tex_name):
		var t: Texture2D = load(ART_DIR + tex_name + ".png")
		if t == null:
			push_warning("Fx: 그림이 없다 " + tex_name)
		_tex[tex_name] = t
	return _tex[tex_name]


func has_effect(name: String) -> bool:
	return Table.EFFECTS.has(name)


func effect_names() -> Array:
	return Table.EFFECTS.keys()


func active_count() -> int:
	return _active.size()


## 쉬고 있는 이펙트 노드 수 / 지금까지 만든 이펙트 노드 수 (쉬는 것 + 떠 있는 것, 상한을 넘지 않는다)
func pool_size() -> int:
	return _pool.size()


func total_nodes() -> int:
	return _pool.size() + _active.size()


## 이펙트를 띄운다. 돌려주는 값: 띄운 이펙트 (모르는 이름이거나 가득 차 못 띄우면 null).
## opts (모두 생략 가능):
##   facing   1 / -1  보는 방향 (왼쪽이면 그림·회전·속도·offset 이 좌우로 뒤집힌다)
##   scale    크기 배수          rot      더할 회전 (도, 오른쪽을 볼 때 기준)
##   color    색 (표의 color 대신)  energy  밝기 배수 (1 보다 크면 HDR 글로우)
##   palette  팔레트 이름 (표의 palette 대신; "" 이면 원래 색)   keep  원래 색을 남기는 비율
##   follow   Node2D — 이 노드를 따라다닌다 (offset 만큼 떨어져서)   offset  Vector2
##   vel      Vector2 속도 (표 대신)   life  수명 (표 대신)   z  그리기 순서
##   flip_v   위아래 뒤집기         scale_xy  가로·세로 배율 (표에 곱한다)
##   driven   true 면 호 드러내기 머리를 부른 쪽이 set_reveal 로 움직이고, 다 그리면 release 한다 (소녀 칼질)
##   children false 면 딸린 이펙트를 띄우지 않는다
func spawn(name: String, pos: Vector2, opts := {}) -> FxSprite:
	var def: Dictionary = Table.EFFECTS.get(name, {})
	if def.is_empty():
		push_warning("Fx: 모르는 이펙트 " + name)
		return null
	var sc := get_tree().current_scene if is_inside_tree() else null
	if sc != _scene:
		# 방이 막 바뀌었다 (새 방의 _ready 에서 띄우는 이펙트): 옛 방 이펙트를 먼저 거둔다
		_scene = sc
		clear()
	var fx := _take(int(def.get("priority", 1)))
	if fx == null:
		dropped_total += 1
		return null
	spawned_total += 1
	fx.gen += 1
	fx.fx_name = name
	fx.born_ms = Time.get_ticks_msec()
	var facing := -1.0 if float(opts.get("facing", 1.0)) < 0.0 else 1.0
	var tex_key = def["tex"]
	fx.texture = texture(tex_key[0] if tex_key is Array else tex_key)
	var pivot: Vector2 = def.get("pivot", Vector2(0.5, 0.5))
	var ts := fx.texture.get_size() if fx.texture else Vector2.ONE
	fx.centered = true
	fx.offset = (Vector2(0.5, 0.5) - pivot) * ts
	fx.global_position = pos
	_apply_material(fx, def, opts, ts)
	fx.setup(def, opts, facing)
	if _frames.has(name):
		fx.set_frames(_frames[name])
	# 딸린 이펙트: [이름, 개수, 퍼짐(Vector2 px), {opts}]  — 개수만큼 흩어 띄운다
	if bool(opts.get("children", true)):
		for ch in def.get("children", []):
			var cname: String = ch[0]
			var count: int = ch[1] if ch.size() > 1 else 1
			var spread: Vector2 = ch[2] if ch.size() > 2 else Vector2.ZERO
			var copts: Dictionary = (ch[3] as Dictionary).duplicate() if ch.size() > 3 else {}
			copts["facing"] = facing * float(copts.get("facing", 1.0))
			if opts.has("palette") and not copts.has("palette"):
				copts["palette"] = opts["palette"]
			if opts.has("scale"):
				copts["scale"] = float(copts.get("scale", 1.0)) * float(opts["scale"])
			var coff: Vector2 = copts.get("offset", Vector2.ZERO)
			copts.erase("offset")
			for i in count:
				var jitter := Vector2(randf_range(-spread.x, spread.x), randf_range(-spread.y, spread.y))
				spawn(cname, pos + Vector2(coff.x * facing, coff.y) + jitter, copts)
	return fx


## 팔레트·호 드러내기가 있으면 이 이펙트만의 셰이더 재질, 없으면 공용 재질.
func _apply_material(fx: FxSprite, def: Dictionary, opts: Dictionary, ts: Vector2) -> void:
	var add := String(def.get("blend", "add")) == "add"
	var pal_name: String = opts.get("palette", def.get("palette", ""))
	var wipe: Dictionary = def.get("wipe", {})
	if pal_name == "" and wipe.is_empty():
		fx.material = _mat_add if add else _mat_mix
		return
	var m := fx.shader_material()
	m.shader = SHADER_ADD if add else SHADER_MIX
	set_palette(m, pal_name, float(opts.get("keep", def.get("keep", 0.0))))
	m.set_shader_parameter(&"wipe_on", not wipe.is_empty())
	if not wipe.is_empty():
		m.set_shader_parameter(&"wipe_center", wipe.get("center", Vector2(0.5, 0.5)))
		m.set_shader_parameter(&"wipe_aspect", Vector2(ts.x / maxf(ts.y, 1.0), 1.0))
		m.set_shader_parameter(&"wipe_a0", deg_to_rad(float(wipe.get("a0", 0.0))))
		m.set_shader_parameter(&"wipe_span", deg_to_rad(float(wipe.get("span", 180.0))))
		m.set_shader_parameter(&"wipe_soft", float(wipe.get("soft", 0.12)))
		m.set_shader_parameter(&"wipe_glow", float(wipe.get("glow", 0.6)))
		m.set_shader_parameter(&"wipe_gap_hide", float(wipe.get("gap_hide", 0.0)))
		m.set_shader_parameter(&"wipe_tail", 4.0)
		m.set_shader_parameter(&"wipe_head", -float(wipe.get("soft", 0.12)))
	fx.material = m


## 셰이더 재질에 팔레트를 넣는다 (fx_mix / fx_add 셰이더를 쓰는 다른 노드도 부른다). 이름이 없거나 ""면 팔레트를 끈다.
static func set_palette(m: ShaderMaterial, pal_name: String, keep := 0.0) -> void:
	var pal: Array = Table.PALETTES.get(pal_name, [])
	m.set_shader_parameter(&"palette_on", not pal.is_empty())
	if not pal.is_empty():
		m.set_shader_parameter(&"pal_dark", pal[0])
		m.set_shader_parameter(&"pal_mid", pal[1])
		m.set_shader_parameter(&"pal_light", pal[2])
		m.set_shader_parameter(&"pal_keep", keep)


## 같은 (팔레트, 섞기, 남김) 조합끼리 함께 쓰는 재질 (F2: 투사체·보스 기술 그림용). 여러 노드가 한 재질을 쓰면
## 묶어 그려지고(그리기 호출이 줄어든다), 노드마다 재질을 새로 만들지 않는다. 받은 재질은 고치지 말 것 (모두에게 바뀐다).
## pal_name 이 "" 이고 add 가 false 면 팔레트 없는 보통 섞기 셰이더 재질.
var _shared_mats := {}
func shared_material(pal_name: String, add := false, keep := 0.0) -> ShaderMaterial:
	var key := "%s|%s|%.2f" % [pal_name, add, keep]
	var m: ShaderMaterial = _shared_mats.get(key)
	if m == null:
		m = make_material(pal_name, add, keep)
		_shared_mats[key] = m
	return m


## fx_mix / fx_add 셰이더로 새 재질을 만든다 (레이저·초승달 검기·보호막처럼 Fx 밖에서 그리는 그림용).
static func make_material(pal_name: String, add := true, keep := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER_ADD if add else SHADER_MIX
	set_palette(m, pal_name, keep)
	m.set_shader_parameter(&"wipe_on", false)
	return m


## 풀에서 하나 꺼낸다. 가득 찼으면 우선순위가 낮고 오래된 것을 거둬 쓴다 (새 것보다 높은 것은 건드리지 않는다).
func _take(prio: int) -> FxSprite:
	if _active.size() >= MAX_ACTIVE:
		var victim := -1
		for i in _active.size():
			var a := _active[i]
			if a.priority > prio or a.driven:
				continue
			if victim < 0 or a.priority < _active[victim].priority \
					or (a.priority == _active[victim].priority and a.born_ms < _active[victim].born_ms):
				victim = i
		if victim < 0:
			return null
		stolen_total += 1
		_recycle(victim)
	var fx: FxSprite
	if _pool.is_empty():
		fx = FxSpriteScript.new()
		fx.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_layer.add_child(fx)
	else:
		fx = _pool.pop_back()
	_active.append(fx)
	return fx


func _recycle(i: int) -> void:
	var fx := _active[i]
	fx.finish()
	_active[i] = _active[_active.size() - 1]
	_active.pop_back()
	_pool.append(fx)


## 살아 있는가 (들고 있던 이펙트가 끝나 다른 이펙트로 다시 쓰이지 않았는가)
func alive(fx: FxSprite, gen: int) -> bool:
	return fx != null and is_instance_valid(fx) and fx.active and fx.gen == gen


## 끌려가는 이펙트의 머리 위치 (0~1)
func set_reveal(fx: FxSprite, gen: int, v: float) -> void:
	if alive(fx, gen):
		fx.set_reveal(v)


## 끌어 주던 이펙트를 놓는다 (남은 수명대로 사라진다)
func release(fx: FxSprite, gen: int) -> void:
	if alive(fx, gen):
		fx.release()


## 바로 거둔다
func kill(fx: FxSprite, gen: int) -> void:
	if alive(fx, gen):
		var i := _active.find(fx)
		if i >= 0:
			_recycle(i)


## 떠 있는 이펙트를 모두 거둔다
func clear() -> void:
	for i in range(_active.size() - 1, -1, -1):
		_recycle(i)


func _process(delta: float) -> void:
	var sc := get_tree().current_scene
	if sc != _scene:
		_scene = sc
		clear()
		return
	var i := _active.size() - 1
	while i >= 0:
		if i < _active.size() and not _active[i].tick(delta):
			_recycle(i)
		i -= 1

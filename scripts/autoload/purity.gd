extends Node
## 지역의 "되살아남" 상태. 정화 전에는 잿빛, 정화하면 색이 돌아온다. (기획서 2장 "눈")
## 배경·안개·잎에 붙은 공용 재질(ash_purify)의 값을 한곳에서 바꾼다.

## 번짐이 진행되는 동안 0→1 로 알려 준다 (지형 테두리 색 등 다른 것들이 따라오게).
signal progress(value: float)
signal region_changed(region: String, purified: bool)

## 공용 재질: 가운데 겹(안개·잎·기록물…) / 더하기(빛) / 배경 그림(far) / 배경 장식(prop — 배경 그림과 같고 아지랑이를 prop_haze 만큼 더) /
## 앞 지형(fore) / 가시(thorn — 앞 지형과 같고 잿빛에서도 원래 색을 조금 남김) / 앞 지형 뒤 그림자 — 정화 값(purity·center·radius·ash_lut)은 모두 함께 받는다
const MATERIALS := [preload("res://shaders/ash_purify.tres"), preload("res://shaders/ash_purify_add.tres"), preload("res://shaders/ash_purify_far.tres"), preload("res://shaders/ash_purify_prop.tres"), preload("res://shaders/ash_purify_fore.tres"), preload("res://shaders/ash_purify_thorn.tres"), preload("res://shaders/terrain_shadow.tres")]
const FAR_MAT := preload("res://shaders/ash_purify_far.tres")
const PROP_MAT := preload("res://shaders/ash_purify_prop.tres")
const FORE_MAT := preload("res://shaders/ash_purify_fore.tres")
const THORN_MAT := preload("res://shaders/ash_purify_thorn.tres")
const SHADOW_MAT := preload("res://shaders/terrain_shadow.tres")

## 지역별 정화 여부. (세이브는 14단계에서)
var regions := {"canopy": false, "village": false, "mine": false, "abyss": false}
var _tween: Tween

## ---- 정화 전후 차이 (v1.1.0 기획자 요청 5) ----
## 지금 방의 정화 정도 (progress 신호의 마지막 값: 0 잿빛 ~ 1 정화). 안개·빛줄기·떨어지는 잎·풀포기가 읽는다.
var level := 0.0
## 번지는 물결 (play_purify): 중심(화면 비율 좌표)·반지름(화면 높이 = 1 — ash_purify 셰이더와 같은 단위). 물결이 없으면 wave_active = false.
var wave_center := Vector2(0.5, 0.5)
var wave_radius := 0.0
var wave_active := false
## 어두운 방(Room.dark): 정화된 지역이면 CanvasModulate 색을 하얀색 쪽으로 이만큼 밝힌다 (Room.dark_color.lerp(WHITE, DARK_LIFT))
const DARK_LIFT := 0.25
## 정화된 방에 Purity 가 붙이는 풀포기 노드 이름 (BloomDecor)
const BLOOM_NAME := "BloomDecor"
var _dark_cm: CanvasModulate
var _dark_base := Color.BLACK


func _ready() -> void:
	# 방이 뜨기 전(타이틀 등)에도 표가 비어 있지 않게 첫 지역 팔레트를 넣어 둔다
	_set_param("ash_lut", ash_lut("canopy"))
	apply_depth({})


func is_purified(region: String) -> bool:
	return regions.get(region, false)


## 지역별 잿빛 색조 (data/terrain/<지역>.json 에 "ash" 팔레트가 없을 때 기본 팔레트를 이 색으로 만든다 — ash_spec. 셰이더에는 넣지 않는다).
const ASH_TINTS := {"canopy": Vector3(0.66, 0.70, 0.78), "village": Vector3(0.78, 0.72, 0.66), "mine": Vector3(0.70, 0.62, 0.58), "abyss": Vector3(0.62, 0.60, 0.76), "sap_lake": Vector3(0.60, 0.70, 0.78), "flooded_mine": Vector3(0.72, 0.60, 0.56)}


## 잿빛 팔레트 표 (64×8): 0번 줄 무채색, 1~6번 줄 색상 띠. 셰이더(ash_purify)가 원래 색 → 잿빛 색을 이 표에서 찾는다.
const LUT_W := 64
const LUT_ROWS := 8
const HUE_NAMES := ["red", "yellow", "green", "cyan", "blue", "magenta"]
var _luts := {}


## 게임이 끝날 때: 풀포기의 나눠 쓰는 그림을 놓는다 (static 이라 그대로 두면 끝날 때 '남은 그림' 경고)
func _exit_tree() -> void:
	BloomDecor.release()


## 방이 시작될 때: 그 지역의 상태(와 잿빛 팔레트)를 바로 적용한다.
## 정화된 지역이면 방에 풀포기(BloomDecor)를 다 핀 채로 붙이고, 어두운 방이면 조금 밝힌다 — 방이 다 준비된 뒤(call_deferred)에.
func apply_region(region: String) -> void:
	if _tween:
		_tween.kill()   # 앞 방의 물결이 남아 있으면 멈춘다 (아래에서 상태를 바로 맞춘다)
	wave_active = false
	wave_radius = 0.0
	var p := 1.0 if is_purified(region) else 0.0
	_set_param("ash_lut", ash_lut(region))
	_set_param("purity", p)
	_set_param("radius", 0.0)
	_emit(p)
	call_deferred("_attach_room_effects", region)


## 앞뒤 가르기 기본값 — 아무것도 안 함. 방의 그림 옷 데이터("depth", TerrainSkin.depth_of)가 덮어쓴다 (TERRAIN.md 5장).
##   ash / alive (정화 전 / 후): haze·haze_color·contrast·sat·value = 배경 그림, prop_haze = 배경 장식(TerrainProp)에 더 얹는 아지랑이
##   (배경 그림보다 진한 크레인·교수대의 들보가 발판으로 보이지 않게), fore_contrast·fore_value·fore_sat = 앞 지형, shadow = 뒤 그림자 진하기
##   shadow_lod (그림자 흐림, 밉맵 단계), shadow_offset [x, y] (px), shadow_color_ash / shadow_color_alive,
##   thorn_keep (가시가 정화 전에도 원래 색을 남기는 비율 0~1 — 붉은 수정 가시처럼 잿빛에서 위험이 안 읽히는 지역만)
const DEPTH_STATE := {"haze": 0.0, "haze_color": "#cccccc", "contrast": 1.0, "sat": 1.0, "value": 1.0, "prop_haze": 0.0, "fore_contrast": 1.0, "fore_value": 1.0, "fore_sat": 1.0, "shadow": 0.0}
const DEPTH_DEFAULT := {"shadow_lod": 3.5, "shadow_offset": [0.0, 4.0], "shadow_color_ash": "#0b0c10", "shadow_color_alive": "#0e0905", "thorn_keep": 0.0}
## 지금 방에 넣은 값 (시험용)
var depth := {}


## 방이 시작될 때 (Room._ready): 배경 그림·앞 지형·뒤 그림자 재질에 그 방의 앞뒤 가르기 값을 넣는다.
func apply_depth(spec: Dictionary) -> void:
	var a: Dictionary = DEPTH_STATE.duplicate()
	a.merge(spec.get("ash", {}), true)
	var b: Dictionary = DEPTH_STATE.duplicate()
	b.merge(spec.get("alive", {}), true)
	var g: Dictionary = DEPTH_DEFAULT.duplicate()
	for k in spec:
		if k != "ash" and k != "alive":
			g[k] = spec[k]
	depth = {"ash": a, "alive": b, "shared": g}
	var v2 := func(key: String) -> Vector2: return Vector2(float(a[key]), float(b[key]))
	for m in [FAR_MAT, PROP_MAT, FORE_MAT, THORN_MAT]:
		m.set_shader_parameter("depth_on", true)
	for m in [FAR_MAT, PROP_MAT]:
		m.set_shader_parameter("haze_color_ash", _col(a["haze_color"]))
		m.set_shader_parameter("haze_color_alive", _col(b["haze_color"]))
		m.set_shader_parameter("contrast", v2.call("contrast"))
		m.set_shader_parameter("sat", v2.call("sat"))
		m.set_shader_parameter("value", v2.call("value"))
	FAR_MAT.set_shader_parameter("haze", v2.call("haze"))
	PROP_MAT.set_shader_parameter("haze", Vector2(clampf(float(a["haze"]) + float(a["prop_haze"]), 0.0, 1.0), clampf(float(b["haze"]) + float(b["prop_haze"]), 0.0, 1.0)))
	for m in [FORE_MAT, THORN_MAT]:
		m.set_shader_parameter("contrast", v2.call("fore_contrast"))
		m.set_shader_parameter("sat", v2.call("fore_sat"))
		m.set_shader_parameter("value", v2.call("fore_value"))
	THORN_MAT.set_shader_parameter("ash_keep", clampf(float(g["thorn_keep"]), 0.0, 1.0))
	SHADOW_MAT.set_shader_parameter("strength", v2.call("shadow"))
	SHADOW_MAT.set_shader_parameter("lod", float(g["shadow_lod"]))
	var off: Array = g["shadow_offset"]
	SHADOW_MAT.set_shader_parameter("offset", Vector2(float(off[0]), float(off[1])))
	SHADOW_MAT.set_shader_parameter("color_ash", _col(g["shadow_color_ash"]))
	SHADOW_MAT.set_shader_parameter("color_alive", _col(g["shadow_color_alive"]))


## 색이 번져 돌아오는 연출. screen_center 는 화면 비율 좌표(0~1).
## 물결 테두리가 지나는 자리마다 풀포기가 돋고(BloomDecor), 안개가 걷히고, 빛줄기가 밝아지고, 잎이 푸르러진다 (progress 를 따라).
func play_purify(region: String, screen_center: Vector2, duration := 3.5) -> void:
	regions[region] = true
	region_changed.emit(region, true)
	if _tween:
		_tween.kill()
	_set_param("center", screen_center)
	_set_param("purity", 0.0)
	_set_param("radius", 0.0)
	wave_center = screen_center
	wave_radius = 0.0
	wave_active = true
	_emit(0.0)
	var room := _room_for(region)
	if room:
		_find_dark(room)
		_bloom(room, true, false)
	_tween = create_tween()
	_tween.tween_method(func(r: float) -> void:
		_set_param("radius", r)
		wave_radius = r
		_emit(clampf(r / 1.6, 0.0, 1.0)), 0.0, 2.6, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func() -> void:
		_set_param("purity", 1.0)
		_set_param("radius", 0.0)
		wave_active = false
		wave_radius = 0.0
		_emit(1.0))


## 테스트용: 다시 잿빛으로.
func reset_region(region: String) -> void:
	regions[region] = false
	region_changed.emit(region, false)
	if _tween:
		_tween.kill()
	wave_active = false
	wave_radius = 0.0
	_set_param("purity", 0.0)
	_set_param("radius", 0.0)
	_emit(0.0)
	call_deferred("_attach_room_effects", region)


## progress 신호 (정화 정도를 기억해 두고, 어두운 방의 밝기도 따라 바꾼다)
func _emit(v: float) -> void:
	level = v
	progress.emit(v)
	_apply_dark(v)


## apply_region 뒤 (방이 다 준비된 다음 — Room._ready 가 CanvasModulate 를 apply_region 뒤에 만든다):
## 정화된 지역이면 풀포기를 다 핀 채로 붙이고, 아니면 뗀다. 어두운 방이면 CanvasModulate 를 찾아 지금 정화 정도대로 밝힌다.
## 풀포기·묘목 모양 그림(BloomDecor 지역별 5개)은 지역이 잿빛이어도 여기서 미리 만든다.
func _attach_room_effects(region: String) -> void:
	# 풀포기·묘목 모양 그림은 잿빛 방에서도 미리 (방 들어오는 프레임에 — 첫 묘목이 돋는 순간 끊기지 않게)
	BloomDecor.warm(region)
	if wave_active:
		return   # 물결 중에는 play_purify 가 맡는다
	var room := _room_for(region)
	if room == null:
		return
	_bloom(room, is_purified(region), true)
	_find_dark(room)
	_apply_dark(level)


## 지금 방 (그 지역의). 보통은 current_scene. 시험(probe)이 방을 자기 아래에 띄웠으면 나무에서 찾는다 (가장 나중 것).
func _room_for(region: String) -> Room:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	var cs := tree.current_scene
	if cs is Room and not cs.is_queued_for_deletion() and (cs as Room).region == region:
		return cs as Room
	var best: Room = null
	for r in tree.root.find_children("*", "Room", true, false):
		if r is Room and r.is_inside_tree() and not r.is_queued_for_deletion() and (r as Room).region == region:
			best = r as Room
	return best


## 방의 풀포기: want 면 있게(bloomed — 다 핀 채로 / false — 숨긴 채 물결을 기다림), 아니면 지운다.
func _bloom(room: Room, want: bool, bloomed: bool) -> BloomDecor:
	var d := room.get_node_or_null(BLOOM_NAME) as BloomDecor
	if d and d.is_queued_for_deletion():
		d = null
	if not want:
		if d:
			d.name = BLOOM_NAME + "_old"
			d.queue_free()
		return null
	if d == null:
		d = BloomDecor.new()
		d.name = BLOOM_NAME
		room.add_child(d)
		# 지형 바로 앞(가시·물건·적·소녀보다 뒤)에 그린다
		var terrain := room.get_node_or_null("Terrain")
		if terrain:
			room.move_child(d, terrain.get_index() + 1)
		d.setup(room, bloomed)
	elif bloomed:
		d.bloom_all()
	else:
		d.begin_wave()
	return d


## 지금 방의 풀포기 (없으면 null — 시험용)
func bloom_decor() -> BloomDecor:
	if not is_inside_tree():
		return null
	var cs := get_tree().current_scene
	var room: Room = cs as Room if cs is Room else null
	if room == null:
		for r in get_tree().root.find_children("*", "Room", true, false):
			if r is Room and not r.is_queued_for_deletion():
				room = r as Room
	if room == null:
		return null
	var d := room.get_node_or_null(BLOOM_NAME) as BloomDecor
	return d if d and not d.is_queued_for_deletion() else null


## 어두운 방의 CanvasModulate (Room._ready 가 만든 것 — 색이 dark_color) 를 기억한다
func _find_dark(room: Room) -> void:
	_dark_cm = null
	if not room.dark:
		return
	for c in room.get_children():
		if not (c is CanvasModulate) or c.is_queued_for_deletion():
			continue
		var cm := c as CanvasModulate
		if cm.has_meta("purity_dark") or cm.color.is_equal_approx(room.dark_color):
			cm.set_meta("purity_dark", true)   # 밝힌 뒤에는 색이 달라지므로 표시해 둔다
			_dark_cm = cm
			_dark_base = room.dark_color
			return


func _apply_dark(v: float) -> void:
	if not is_instance_valid(_dark_cm):
		return
	_dark_cm.color = _dark_base.lerp(Color.WHITE, DARK_LIFT * clampf(v, 0.0, 1.0))


## 지역의 잿빛 팔레트 표. data/terrain/<지역>.json 의 "ash": {"neutral": [[밝기, "#색"], …], "hues": {"green": […], …}}
## (밝기 0~1 → 그 밝기의 잿빛 색, 사이는 이어 칠함). 없으면 ASH_TINTS 색조로 기본 팔레트를 만든다 (옛 셰이더보다 밝게 —
## 기획자 의견: 잿빛 지형이 너무 어둡다).
func ash_lut(region: String) -> ImageTexture:
	if _luts.has(region):
		return _luts[region]
	var spec := ash_spec(region)
	var img := Image.create(LUT_W, LUT_ROWS, false, Image.FORMAT_RGBA8)
	var neutral: Array = spec["neutral"]
	var hues: Dictionary = spec.get("hues", {})
	for x in LUT_W:
		var l := float(x) / float(LUT_W - 1)
		img.set_pixel(x, 0, ramp(neutral, l))
		for h in 6:
			img.set_pixel(x, 1 + h, ramp(hues.get(HUE_NAMES[h], neutral), l))
		img.set_pixel(x, 7, img.get_pixel(x, 1))
	var tex := ImageTexture.create_from_image(img)
	_luts[region] = tex
	return tex


## 지역의 잿빛 팔레트 설명 (데이터 파일 또는 기본값)
func ash_spec(region: String) -> Dictionary:
	var path := "res://data/terrain/%s.json" % region
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and d.get("ash") is Dictionary and (d["ash"] as Dictionary).has("neutral"):
			return d["ash"]
	var t: Vector3 = ASH_TINTS.get(region, Vector3(0.66, 0.70, 0.78))
	var tint := Color(t.x, t.y, t.z)
	var light := tint.lerp(Color.WHITE, 0.35) * 0.9
	return {"neutral": [[0.0, tint * 0.12], [0.5, tint * 0.55], [1.0, Color(light.r, light.g, light.b)]]}


## 밝기 l 에서 단계 색 (stops: [[위치, 색 또는 "#색"], …], 위치 순)
static func ramp(stops: Array, l: float) -> Color:
	if stops.is_empty():
		return Color(l, l, l)
	var prev_t := float(stops[0][0])
	var prev_c := _col(stops[0][1])
	if l <= prev_t:
		return prev_c
	for i in range(1, stops.size()):
		var t := float(stops[i][0])
		var c := _col(stops[i][1])
		if l <= t:
			return prev_c.lerp(c, (l - prev_t) / maxf(t - prev_t, 0.0001))
		prev_t = t
		prev_c = c
	return prev_c


static func _col(v) -> Color:
	if v is Color:
		return Color(v.r, v.g, v.b, 1.0)
	if v is String:
		return Color.html(v)
	if v is Array:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return Color.WHITE


func _set_param(param: String, value) -> void:
	for m in MATERIALS:
		m.set_shader_parameter(param, value)

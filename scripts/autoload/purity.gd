extends Node
## 지역의 "되살아남" 상태. 정화 전에는 잿빛, 정화하면 색이 돌아온다. (기획서 2장 "눈")
## 배경·안개·잎에 붙은 공용 재질(ash_purify)의 값을 한곳에서 바꾼다.

## 번짐이 진행되는 동안 0→1 로 알려 준다 (지형 테두리 색 등 다른 것들이 따라오게).
signal progress(value: float)
signal region_changed(region: String, purified: bool)

## 공용 재질: 가운데 겹(안개·잎·기록물…) / 더하기(빛) / 배경 그림(far) / 앞 지형(fore) / 앞 지형 뒤 그림자 — 정화 값(purity·center·radius·ash_lut)은 모두 함께 받는다
const MATERIALS := [preload("res://shaders/ash_purify.tres"), preload("res://shaders/ash_purify_add.tres"), preload("res://shaders/ash_purify_far.tres"), preload("res://shaders/ash_purify_fore.tres"), preload("res://shaders/terrain_shadow.tres")]
const FAR_MAT := preload("res://shaders/ash_purify_far.tres")
const FORE_MAT := preload("res://shaders/ash_purify_fore.tres")
const SHADOW_MAT := preload("res://shaders/terrain_shadow.tres")

## 지역별 정화 여부. (세이브는 14단계에서)
var regions := {"canopy": false, "village": false, "mine": false, "abyss": false}
var _tween: Tween


func _ready() -> void:
	# 방이 뜨기 전(타이틀 등)에도 표가 비어 있지 않게 첫 지역 팔레트를 넣어 둔다
	_set_param("ash_lut", ash_lut("canopy"))
	apply_depth({})


func is_purified(region: String) -> bool:
	return regions.get(region, false)


## 지역별 잿빛 색조 (data/terrain/<지역>.json 에 "ash" 팔레트가 없을 때 기본 팔레트를 이 색으로 만든다).
const ASH_TINTS := {"canopy": Vector3(0.66, 0.70, 0.78), "village": Vector3(0.78, 0.72, 0.66), "mine": Vector3(0.70, 0.62, 0.58), "abyss": Vector3(0.62, 0.60, 0.76), "sap_lake": Vector3(0.60, 0.70, 0.78), "flooded_mine": Vector3(0.72, 0.60, 0.56)}


## 잿빛 팔레트 표 (64×8): 0번 줄 무채색, 1~6번 줄 색상 띠. 셰이더(ash_purify)가 원래 색 → 잿빛 색을 이 표에서 찾는다.
const LUT_W := 64
const LUT_ROWS := 8
const HUE_NAMES := ["red", "yellow", "green", "cyan", "blue", "magenta"]
var _luts := {}


## 방이 시작될 때: 그 지역의 상태(와 잿빛 팔레트)를 바로 적용한다.
func apply_region(region: String) -> void:
	var p := 1.0 if is_purified(region) else 0.0
	_set_param("ash_tint", ASH_TINTS.get(region, Vector3(0.66, 0.70, 0.78)))
	_set_param("ash_lut", ash_lut(region))
	_set_param("purity", p)
	_set_param("radius", 0.0)
	progress.emit(p)


## 앞뒤 가르기 기본값 — 아무것도 안 함. 방의 그림 옷 데이터("depth", TerrainSkin.depth_of)가 덮어쓴다 (TERRAIN.md 5장).
##   ash / alive (정화 전 / 후): haze·haze_color·contrast·sat·value = 배경 그림, fore_contrast·fore_value·fore_sat = 앞 지형, shadow = 뒤 그림자 진하기
##   shadow_lod (그림자 흐림, 밉맵 단계), shadow_offset [x, y] (px), shadow_color_ash / shadow_color_alive
const DEPTH_STATE := {"haze": 0.0, "haze_color": "#cccccc", "contrast": 1.0, "sat": 1.0, "value": 1.0, "fore_contrast": 1.0, "fore_value": 1.0, "fore_sat": 1.0, "shadow": 0.0}
const DEPTH_DEFAULT := {"shadow_lod": 3.5, "shadow_offset": [0.0, 4.0], "shadow_color_ash": "#0b0c10", "shadow_color_alive": "#0e0905"}
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
	FAR_MAT.set_shader_parameter("haze", v2.call("haze"))
	FAR_MAT.set_shader_parameter("haze_color_ash", _col(a["haze_color"]))
	FAR_MAT.set_shader_parameter("haze_color_alive", _col(b["haze_color"]))
	FAR_MAT.set_shader_parameter("contrast", v2.call("contrast"))
	FAR_MAT.set_shader_parameter("sat", v2.call("sat"))
	FAR_MAT.set_shader_parameter("value", v2.call("value"))
	FORE_MAT.set_shader_parameter("contrast", v2.call("fore_contrast"))
	FORE_MAT.set_shader_parameter("sat", v2.call("fore_sat"))
	FORE_MAT.set_shader_parameter("value", v2.call("fore_value"))
	SHADOW_MAT.set_shader_parameter("strength", v2.call("shadow"))
	SHADOW_MAT.set_shader_parameter("lod", float(g["shadow_lod"]))
	var off: Array = g["shadow_offset"]
	SHADOW_MAT.set_shader_parameter("offset", Vector2(float(off[0]), float(off[1])))
	SHADOW_MAT.set_shader_parameter("color_ash", _col(g["shadow_color_ash"]))
	SHADOW_MAT.set_shader_parameter("color_alive", _col(g["shadow_color_alive"]))


## 색이 번져 돌아오는 연출. screen_center 는 화면 비율 좌표(0~1).
func play_purify(region: String, screen_center: Vector2, duration := 3.5) -> void:
	regions[region] = true
	region_changed.emit(region, true)
	if _tween:
		_tween.kill()
	_set_param("center", screen_center)
	_set_param("purity", 0.0)
	_set_param("radius", 0.0)
	_tween = create_tween()
	_tween.tween_method(func(r: float) -> void:
		_set_param("radius", r)
		progress.emit(clampf(r / 1.6, 0.0, 1.0)), 0.0, 2.6, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func() -> void:
		_set_param("purity", 1.0)
		_set_param("radius", 0.0)
		progress.emit(1.0))


## 테스트용: 다시 잿빛으로.
func reset_region(region: String) -> void:
	regions[region] = false
	region_changed.emit(region, false)
	if _tween:
		_tween.kill()
	_set_param("purity", 0.0)
	_set_param("radius", 0.0)
	progress.emit(0.0)


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

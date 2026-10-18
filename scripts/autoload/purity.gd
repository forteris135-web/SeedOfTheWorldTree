extends Node
## 지역의 "되살아남" 상태. 정화 전에는 잿빛, 정화하면 색이 돌아온다. (기획서 2장 "눈")
## 배경·안개·잎에 붙은 공용 재질(ash_purify)의 값을 한곳에서 바꾼다.

## 번짐이 진행되는 동안 0→1 로 알려 준다 (지형 테두리 색 등 다른 것들이 따라오게).
signal progress(value: float)
signal region_changed(region: String, purified: bool)

const MATERIALS := [preload("res://shaders/ash_purify.tres"), preload("res://shaders/ash_purify_add.tres")]

## 지역별 정화 여부. (세이브는 14단계에서)
var regions := {"canopy": false, "village": false, "mine": false, "abyss": false}
var _tween: Tween


func is_purified(region: String) -> bool:
	return regions.get(region, false)


## 방이 시작될 때: 그 지역의 상태를 바로 적용한다.
const ASH_TINTS := {"canopy": Vector3(0.66, 0.70, 0.78), "village": Vector3(0.78, 0.72, 0.66), "mine": Vector3(0.70, 0.62, 0.58), "abyss": Vector3(0.62, 0.60, 0.76)}


func apply_region(region: String) -> void:
	var p := 1.0 if is_purified(region) else 0.0
	_set_param("ash_tint", ASH_TINTS.get(region, Vector3(0.66, 0.70, 0.78)))
	_set_param("purity", p)
	_set_param("radius", 0.0)
	progress.emit(p)


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


func _set_param(param: String, value) -> void:
	for m in MATERIALS:
		m.set_shader_parameter(param, value)

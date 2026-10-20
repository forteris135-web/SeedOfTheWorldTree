class_name MachineLamp
extends Node2D
## 기계 표시등 (잠긴 채굴장 — 판정 없음). 기획자가 따로 그린 다섯 색 구슬 등(노랑·파랑·초록·빨강·보라)을 쓴다.
## 깃발(Progress)에 따라 색이 바뀌는 신호등으로 쓸 수 있다 — 예: 무쇠 펌프 문 옆 등은 펌프를 정화하기 전 빨강, 정화 뒤 초록.
## 잿빛 재질을 거치지 않아 잿빛 세상에서도 색이 보인다 (표시등은 읽혀야 하므로). 1 넘는 밝기로 그려 글로우가 번진다.
## 매 프레임 하는 일은 숨쉬기(self_modulate 한 번)뿐이다.
##
## - lamp: 평소(깃발 전) 조각 — lamp_y 노랑 / lamp_b 파랑 / lamp_g 초록 / lamp_r 빨강 / lamp_p 보라
## - lamp_on: 깃발이 서면 바꿀 조각 (비우면 늘 lamp)
## - flag: Progress 깃발 이름 (비우면 늘 lamp)
## - glow: 밝기 배수 (1 보다 크면 글로우)
## - pulse: 숨쉬기 세기 (0 이면 가만히) / pulse_speed: 빠르기

@export var lamp := "lamp_r"
@export var lamp_on := ""
@export var flag := ""
@export var art_scale := 0.45
@export var glow := 1.35
@export var pulse := 0.18
@export var pulse_speed := 1.6
## 지역 강제 (비우면 방의 지역)
@export var region := ""

var _skin: TerrainSkin
var _t := 0.0
var _on := false


func _ready() -> void:
	var r := region if region != "" else TerrainStyle.region_of(self)
	_skin = TerrainSkin.for_region(r)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_t = fmod(global_position.x * 0.011, TAU)
	_update_state()
	if flag != "" and not Progress.flag_changed.is_connected(_on_flag):
		Progress.flag_changed.connect(_on_flag)
	set_process(pulse > 0.0)


func _on_flag(f: String, _v: bool) -> void:
	if f == flag:
		_update_state()


func _update_state() -> void:
	_on = flag != "" and lamp_on != "" and Progress.has(flag)
	queue_redraw()


## 지금 그리는 조각 (시험용)
func current_piece() -> String:
	return lamp_on if _on else lamp


func _process(delta: float) -> void:
	_t += delta
	var b := glow * (1.0 + pulse * sin(_t * pulse_speed))
	self_modulate = Color(b, b, b, 1.0)


func _draw() -> void:
	var name := current_piece()
	if _skin == null or not _skin.pieces.has(name):
		return
	var size := _skin.size_of(name) * art_scale
	draw_texture_rect_region(_skin.atlas, Rect2(-size * 0.5, size), _skin.rect_of(name))

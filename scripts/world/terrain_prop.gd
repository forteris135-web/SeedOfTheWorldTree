class_name TerrainProp
extends Node2D
## 지역 그림 옷(TerrainSkin) atlas 의 조각 하나를 세워 두는 장식 (판정 없음 — 겉모습만).
## 채굴장의 크레인·비계 틀·등불 선반, 잠긴 채굴장의 기계 벽·기계 문·관 기둥·바위처럼 기획자가 따로 그려 준 그림을 방에 놓는다.
## 방 파일에서 Props(지형 Terrain 보다 앞 순서 = 뒤에 그려짐) 아래에 두면 지형·소녀 뒤 배경 장식이 된다.
## 재질은 ash_purify_prop: 배경 그림(ash_purify_far)과 같고 아지랑이를 그림 옷 depth 의 prop_haze 만큼 더 — 아지랑이 뒤로 물러나 발판으로 오해받지 않는다 (TERRAIN.md 5장).
##
## - piece: 조각 이름 (data/terrain/<지역>.json 의 cut.pieces 이름 — 보통 역할 decor, 다른 역할 조각도 된다)
## - anchor: 조각 안 기준점 (0~1). 기본 (0.5, 1) = 밑동 가운데 → 노드 자리가 밑동(바닥에 닿는 곳)
## - art_scale: 크기 (atlas 조각 1px → 월드 px)
## - shade: 색 곱하기 (1 보다 작으면 어둡게 — 뒤 장식이 발판으로 오해받지 않게)
## 정화 전에는 공용 잿빛 재질로 지역 잿빛 색이 된다. 그림 옷이 없는 지역이면 아무것도 그리지 않는다.

@export var piece := "":
	set(v):
		piece = v
		_skin = null
		queue_redraw()
## 지역 강제 (비우면 조상 Room 의 region)
@export var region := "":
	set(v):
		region = v
		_skin = null
		queue_redraw()
@export var anchor := Vector2(0.5, 1.0):
	set(v):
		anchor = v
		queue_redraw()
@export var art_scale := 1.0:
	set(v):
		art_scale = v
		queue_redraw()
@export var flip_h := false:
	set(v):
		flip_h = v
		queue_redraw()
@export var shade := Color(1, 1, 1, 1):
	set(v):
		shade = v
		queue_redraw()

var _skin: TerrainSkin


func _ready() -> void:
	material = preload("res://shaders/ash_purify_prop.tres")   # 배경 장식 재질: 배경 그림과 같고 아지랑이를 depth 의 prop_haze 만큼 더 (발판으로 오해받지 않게 — TERRAIN.md 5장)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _get_skin() -> TerrainSkin:
	if _skin == null:
		var r := region if region != "" else TerrainStyle.region_of(self)
		_skin = TerrainSkin.for_region(r)
	return _skin


## 조각이 놓인 상자 (노드 기준, 시험·배치용)
func art_rect() -> Rect2:
	var s := _get_skin()
	if s == null or not s.pieces.has(piece):
		return Rect2()
	var size := s.size_of(piece) * art_scale
	return Rect2(-anchor * size, size)


func _draw() -> void:
	var s := _get_skin()
	if s == null or not s.pieces.has(piece):
		return
	var src := s.rect_of(piece)
	var r := art_rect()
	if flip_h:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
	draw_texture_rect_region(s.atlas, r, src, Color(s.tint.r * shade.r, s.tint.g * shade.g, s.tint.b * shade.b, shade.a))

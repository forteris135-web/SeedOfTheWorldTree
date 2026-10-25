extends Node2D
## 정화되거나 쓰러진 적이 남기는 작은 묘목. 죽음이 아니라 나무로 돌아가 쉬는 것.
## (v1.1.0 기획자 요청 5) 정화된 땅에 돋는 풀포기(BloomDecor)의 '어린 나무'와 같은 그림·같은 지역 색으로 그린다 —
## 바람에 살랑이는 것도 같다. GROW_SPEED 로 자라고(약 1.25초), 다 자란 뒤에는 매 프레임 다시 그리지 않는다.

## 자라는 빠르기 (1/초) / 다 자란 크기 (풀포기 어린 나무 그림 기준 배율)
const GROW_SPEED := 0.8
const SIZE := 1.1
## 어린 나무 그림의 번호 (BloomDecor 모양 종류)
const SAPLING_KIND := 4

var _t := 0.0
var _mesh: Mesh


func _ready() -> void:
	_mesh = BloomDecor.kind_mesh(TerrainStyle.region_of(self), SAPLING_KIND)
	material = BloomDecor.shared_material()


func _process(delta: float) -> void:
	_t = minf(_t + delta * GROW_SPEED, 1.0)
	queue_redraw()
	if _t >= 1.0:
		set_process(false)


func _draw() -> void:
	var g := ease(_t, 0.4)
	draw_circle(Vector2(0, -10), 34.0 * g, Color("6fcf97", 0.08))
	if g > 0.001 and _mesh:
		draw_mesh(_mesh, null, Transform2D(0.0, Vector2(g, g) * SIZE, 0.0, Vector2.ZERO))

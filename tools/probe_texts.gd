extends SceneTree
## 안내 글자·수상한 지형 검사 (화면 없이 수치로).
## 실행: godot --headless --path . -s res://tools/probe_texts.gd
## 확인하는 것:
##  1) 발판 라벨(label_text)이 플레이 중엔 숨고, '개발 표시'를 켜면 보이고, 끄면 다시 숨는지
##  2) suspicious 발판·경사에 빛(SuspiciousHint)과 빛 가루(CPUParticles2D)가 생기고, 일반 발판엔 없는지
##  3) 빛의 맥동이 매끄러운지 (프레임 간 알파 변화량의 최대치)
##  4) 수상한 발판의 이끼 색이 일반보다 창백한지

var _frames := 0
var _alphas: Array[float] = []
var _secret: Platform
var _fail := 0
var _room: Node
var _poly: TerrainPolygon


func _check(ok: bool, what: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", what])
	if not ok:
		_fail += 1


func _initialize() -> void:
	var settings := root.get_node_or_null("Settings")
	_check(settings != null, "Settings 자동 로드가 있다")
	var scene: PackedScene = load("res://scenes/rooms/canopy_01.tscn")
	var room := scene.instantiate()
	# 통합자가 켤 예정인 값을 미리 켜 본다 (씬 파일은 손대지 않음)
	_secret = room.get_node("Terrain/Secret")
	_secret.suspicious = true
	var poly := TerrainPolygon.new()
	poly.polygon = PackedVector2Array([Vector2(0, 0), Vector2(300, -60), Vector2(300, 80), Vector2(0, 80)])
	poly.suspicious = true
	poly.position = Vector2(3000, 1500)
	room.get_node("Terrain").add_child(poly)
	root.add_child(room)
	current_scene = room
	_room = room
	_poly = poly


## 방의 _ready 는 첫 프레임에 돈다. 그 뒤에 검사한다.
func _checks() -> void:
	var settings := root.get_node_or_null("Settings")
	var room := _room
	var poly := _poly

	# 1) 라벨
	var labels: Array[Label] = []
	for t in room.get_node("Terrain").get_children():
		for c in t.get_children():
			if c is Label:
				labels.append(c)
	_check(labels.size() >= 7, "첫 방 발판 라벨 %d개를 찾음" % labels.size())
	var any_visible := false
	for l in labels:
		any_visible = any_visible or l.visible
	_check(not any_visible, "개발 표시 꺼짐: 라벨이 모두 숨어 있다")
	if settings:
		settings.set_value("debug_hud", true)
		var all_visible := true
		for l in labels:
			all_visible = all_visible and l.visible
		_check(all_visible, "개발 표시 켬: 라벨이 모두 보인다")
		settings.set_value("debug_hud", false)
		any_visible = false
		for l in labels:
			any_visible = any_visible or l.visible
		_check(not any_visible, "개발 표시 끔: 라벨이 다시 숨는다")

	# 2) 수상한 단서 노드
	_check(_secret._hint != null and _secret._motes != null, "비밀 발판에 빛과 빛 가루가 생김 (입자 %d개)" % (_secret._motes.amount if _secret._motes else 0))
	_check(_secret._motes != null and _secret._motes.amount <= 8, "입자 수가 적다 (8개 이하)")
	var floor1: Platform = room.get_node("Terrain/Floor1")
	_check(floor1._hint == null and floor1._motes == null, "일반 발판에는 단서가 없다")
	_check(poly._hint != null and poly._motes != null, "수상한 경사에도 빛과 빛 가루가 생김")
	_check(poly._hint._edges.size() == 1, "경사의 위 변 %d개에 빛" % poly._hint._edges.size())

	# 4) 이끼 색
	var normal := floor1._moss()
	var pale := _secret._moss()
	_check(pale.get_luminance() > normal.get_luminance() + 0.1, "수상한 이끼가 더 창백하다 (밝기 %.2f → %.2f)" % [normal.get_luminance(), pale.get_luminance()])

	# 5) 소녀 위에 덧그려지지 않도록 빛 띠의 z_index 는 0
	_check(_secret._hint.z_index == 0, "빛 띠 z_index = %d (소녀보다 아래)" % _secret._hint.z_index)

	# 6) 면 고르기: 아랫면(천장)·옆면(벽)에서는 빛 띠와 빛 가루가 그 면 바깥쪽으로 간다
	var terrain := room.get_node("Terrain")
	var ceil := Platform.new()
	ceil.size = Vector2(400, 100)
	ceil.decorate = false
	ceil.suspicious_face = 1   # 아래
	ceil.suspicious = true
	ceil.position = Vector2(3400, 1200)
	terrain.add_child(ceil)
	var e := ceil._hint._edges[0]
	var dir: Vector2 = e[1] - e[0]
	var nrm := Vector2(dir.y, -dir.x).normalized()
	_check(nrm.y > 0.9, "아랫면: 법선이 아래를 향함 (%.1f, %.1f)" % [nrm.x, nrm.y])
	var outer: Vector2 = (e[0] + e[1]) * 0.5 + nrm * Platform.HINT_HEIGHT
	_check(outer.y > ceil.size.y, "아랫면: 빛 띠 바깥 꼭짓점 y=%.0f > h=%.0f" % [outer.y, ceil.size.y])
	_check(ceil._motes.gravity.y > 0.0 and ceil._motes.position.y > ceil.size.y, "아랫면: 빛 가루가 아래로 떨어짐 (gravity.y=%.1f, 자리 y=%.0f)" % [ceil._motes.gravity.y, ceil._motes.position.y])
	_check(ceil._motes.emission_rect_extents.x > ceil._motes.emission_rect_extents.y, "아랫면: 입자 범위가 가로로 넓음 (%.0f×%.0f)" % [ceil._motes.emission_rect_extents.x, ceil._motes.emission_rect_extents.y])

	var wall := Platform.new()
	wall.size = Vector2(100, 400)
	wall.decorate = false
	wall.suspicious_face = 3   # 오른쪽
	wall.suspicious = true
	wall.position = Vector2(3800, 1200)
	terrain.add_child(wall)
	var e2 := wall._hint._edges[0]
	var dir2: Vector2 = e2[1] - e2[0]
	var nrm2 := Vector2(dir2.y, -dir2.x).normalized()
	_check(nrm2.x > 0.9, "오른쪽 벽: 법선이 오른쪽을 향함 (%.1f, %.1f)" % [nrm2.x, nrm2.y])
	_check(wall._motes.gravity.x > 0.0 and wall._motes.position.x > wall.size.x, "오른쪽 벽: 빛 가루가 옆으로 새어 나감 (gravity.x=%.1f, 자리 x=%.0f)" % [wall._motes.gravity.x, wall._motes.position.x])
	_check(wall._motes.emission_rect_extents.y > wall._motes.emission_rect_extents.x, "오른쪽 벽: 입자 범위가 세로로 김 (%.0f×%.0f)" % [wall._motes.emission_rect_extents.x, wall._motes.emission_rect_extents.y])
	# 왼쪽 면도 법선 확인
	wall.suspicious_face = 2
	var e3 := wall._hint._edges[0]
	var dir3: Vector2 = e3[1] - e3[0]
	var nrm3 := Vector2(dir3.y, -dir3.x).normalized()
	_check(nrm3.x < -0.9, "왼쪽 벽: 법선이 왼쪽을 향함 (%.1f, %.1f)" % [nrm3.x, nrm3.y])

	# 7) _ready 뒤에 끄고 켜도 단서가 따라감 (찾은 뒤 단서 끄기용)
	ceil.suspicious = false
	_check(ceil._hint == null and ceil._motes == null and not ceil.is_processing(), "끄면 빛·빛 가루가 사라지고 _process 도 꺼짐")
	ceil.suspicious = true
	_check(ceil._hint != null and ceil._motes != null and ceil.is_processing(), "다시 켜면 빛·빛 가루가 생기고 _process 도 켜짐")
	poly.suspicious = false
	_check(poly._hint == null and poly._motes == null, "경사도 끄면 단서가 사라짐")
	poly.suspicious = true
	_check(poly._hint != null and poly._motes != null, "경사도 다시 켜면 단서가 생김")


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		_checks()
	if _frames > 2 and _secret and _secret._hint:
		_alphas.append(_secret._hint.modulate.a)
	if _frames < 240:
		return false
	# 3) 맥동 연속성
	var max_jump := 0.0
	var lo := INF
	var hi := -INF
	for i in range(1, _alphas.size()):
		max_jump = maxf(max_jump, absf(_alphas[i] - _alphas[i - 1]))
	for a in _alphas:
		lo = minf(lo, a)
		hi = maxf(hi, a)
	_check(max_jump < 0.02, "빛 맥동이 매끄럽다 (프레임 간 최대 변화 %.4f, 범위 %.2f~%.2f)" % [max_jump, lo, hi])
	_check(hi - lo > 0.1, "빛이 실제로 숨 쉰다 (범위 %.2f)" % (hi - lo))
	print("[probe] 끝: 실패 %d" % _fail)
	quit(1 if _fail > 0 else 0)
	return true

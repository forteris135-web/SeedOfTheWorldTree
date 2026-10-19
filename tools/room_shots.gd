extends SceneTree
## 방 스크린샷 (화면 있는 실행 — 창이 잠깐 뜬다). 지형 그림이 잘 맞는지 눈으로 볼 때 쓴다.
## 실행:
##   godot --path . -s res://tools/room_shots.gd -- canopy_01 [--ash | --alive] [--zoom=0.55] [--at=x,y;x,y] [--hud] [--out=폴더]
##   - 기본: 방 전체를 zoom 배율의 화면으로 바둑판처럼 나눠 찍는다 → screenshots/room_<방>_<번호>.png
##   - --at 을 주면 그 자리들만 찍는다 (가까이 보기: --zoom=1.6 이면 화면 1px ≈ 월드 1px)
##   - --ash / --alive 는 Room 이 읽어 정화 전·후를 고른다 (파일 이름에 _ash / _alive 가 붙는다)
##   - HUD·터치 버튼은 숨긴다 (--hud 면 그대로)
## 맞춤 확인: 소녀가 서는 윗면(충돌 윗면)과 그림의 윗면이 붙어 있는지, 이음매·뜬 조각이 없는지 본다.
## 개발 표시 대신 --lines 를 주면 충돌 윗면을 얇은 빨간 선으로 겹쳐 그린다.

var _room: Node
var _cam: Camera2D
var _views: Array = []
var _i := -1
var _t := 0.0
var _wait := 0.0
var _zoom := 0.55
var _name := ""
var _out_dir := "res://screenshots"
var _suffix := ""
var _lines := false
var _busy := false


func _arg(n: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(n + "="):
			return a.trim_prefix(n + "=")
	return default


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_name = args[0] if not args.is_empty() and not args[0].begins_with("--") else "canopy_01"
	_zoom = float(_arg("--zoom", "0.55"))
	_out_dir = _arg("--out", "res://screenshots")
	_suffix = "_ash" if "--ash" in args else ("_alive" if "--alive" in args else "")
	_lines = "--lines" in args
	var scene: PackedScene = load("res://scenes/rooms/%s.tscn" % _name)
	_room = scene.instantiate()
	root.add_child(_room)
	current_scene = _room


func _plan() -> void:
	var at := _arg("--at", "")
	if at != "":
		for s in at.split(";"):
			var p := s.split(",")
			_views.append(Vector2(float(p[0]), float(p[1])))
		return
	var b: Rect2 = _room.get("bounds")
	var vp := Vector2(1920, 1080) / _zoom
	var nx := maxi(1, int(ceil(b.size.x / (vp.x * 0.92))))
	var ny := maxi(1, int(ceil(b.size.y / (vp.y * 0.92))))
	for j in ny:
		for i in nx:
			var cx := b.position.x + vp.x * 0.5 + (b.size.x - vp.x) * (float(i) / maxf(nx - 1, 1) if nx > 1 else 0.5)
			var cy := b.position.y + vp.y * 0.5 + (b.size.y - vp.y) * (float(j) / maxf(ny - 1, 1) if ny > 1 else 0.5)
			if b.size.x < vp.x:
				cx = b.get_center().x
			if b.size.y < vp.y:
				cy = b.get_center().y
			_views.append(Vector2(cx, cy))


func _take_camera() -> void:
	var player := get_first_node_in_group("player")
	if player:
		var pc := player.get_node_or_null("Camera2D")
		if pc:
			pc.enabled = false
	_cam = Camera2D.new()
	_cam.zoom = Vector2(_zoom, _zoom)
	_room.add_child(_cam)
	_cam.make_current()
	if not ("--hud" in OS.get_cmdline_user_args()):
		_hide_ui(root)
	if _lines:
		var ov := LineOverlay.new()
		ov.room = _room
		ov.z_index = 100
		_room.add_child(ov)


func _hide_ui(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer and c.layer >= 1:
			c.visible = false
		_hide_ui(c)


func _process(delta: float) -> bool:
	_t += delta
	if _cam == null:
		if _t > 0.6:
			_take_camera()
			_plan()
			_next()
		return false
	if _busy:
		return false
	_wait -= delta
	if _wait <= 0.0 and _i < _views.size():
		_busy = true
		_save()
	return _i >= _views.size()


func _next() -> void:
	_i += 1
	if _i < _views.size():
		_cam.position = _views[_i]
		_cam.reset_smoothing()
		_wait = 0.35 if _i > 0 else 2.4   # 처음에는 화면이 밝아지고 정화 상태가 자리 잡을 때까지


func _save() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/room_%s%s_%d.png" % [_out_dir, _name, _suffix, _i])
	if img and not img.is_empty():
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		img.save_png(path)
		print("[shots] %s  카메라 %s 배율 %.2f" % [path, _views[_i], _zoom])
	_busy = false
	_next()
	if _i >= _views.size():
		quit(0)


## 충돌 윗면(발판·경사 윗변)을 빨간 선으로 겹쳐 그린다 (맞춤 확인용).
class LineOverlay extends Node2D:
	var room: Node

	func _draw() -> void:
		var terrain := room.get_node_or_null("Terrain")
		if terrain == null:
			return
		for t in terrain.get_children():
			if t is Platform:
				var p: Vector2 = t.global_position
				draw_line(p, p + Vector2(t.size.x, 0), Color(1, 0.1, 0.1, 0.9), 2.0)
				draw_rect(Rect2(p, t.size), Color(1, 0.1, 0.1, 0.35), false, 1.0)
			elif t is TerrainPolygon:
				var poly: PackedVector2Array = t.polygon
				var o: Vector2 = t.global_position
				for i in poly.size():
					var a := poly[i] + o
					var b := poly[(i + 1) % poly.size()] + o
					draw_line(a, b, Color(1, 0.1, 0.1, 0.6), 1.5)

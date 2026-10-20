extends SceneTree
## 방 스크린샷 (화면 있는 실행 — 창이 잠깐 뜬다). 지형 그림이 잘 맞는지, 앞 지형이 배경에서 읽히는지 눈으로 볼 때 쓴다.
## 실행:
##   godot --path . -s res://tools/room_shots.gd -- canopy_01 [--ash | --alive] [--zoom=0.55] [--at=x,y;x,y] [--hud] [--out=폴더]
##   - 기본: 방 전체를 zoom 배율의 화면으로 바둑판처럼 나눠 찍는다 → screenshots/room_<방>_<번호>.png
##   - --at 을 주면 그 자리들만 찍는다 (가까이 보기: --zoom=1.6 이면 화면 1px ≈ 월드 1px)
##   - --ash / --alive 는 Room 이 읽어 정화 전·후를 고른다 (파일 이름에 _ash / _alive 가 붙는다)
##   - HUD·터치 버튼은 숨긴다 (--hud 면 그대로)
## 여러 방 한꺼번에 (한 번 실행으로 — 모든 방 점검용):
##   godot --path . -s res://tools/room_shots.gd -- all --states=ash,alive --spot=player --scale=0.5 --out=<폴더>
##   - 방 이름 자리에 쉼표로 여러 방, 또는 all (scenes/rooms/*.tscn 전부)
##   - --states=ash,alive : 방마다 정화 전·후를 차례로 찍는다 (방을 띄우기 전에 Purity 상태를 정한다)
##   - --spot=player : 바둑판 대신 소녀가 들어오는 자리 한 곳을 게임 배율(--zoom 을 안 주면 1.15)로
##   - --scale=0.5 : 저장할 때 그림을 줄인다 (디스크·보기 가볍게)
##   - --lantern 은 Room 이 읽는다 (어두운 방에서 등불 빛을 켜고 찍기)
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
var _spot := ""
var _scale := 1.0
## 차례로 찍을 [방, 상태] 목록 (상태 "" 는 Room 이 명령줄 --ash/--alive 를 읽는 대로)
var _jobs: Array = []
var _job := -1


func _arg(n: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(n + "="):
			return a.trim_prefix(n + "=")
	return default


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var names_arg := args[0] if not args.is_empty() and not args[0].begins_with("--") else "canopy_01"
	_spot = _arg("--spot", "")
	_zoom = float(_arg("--zoom", "1.15" if _spot != "" else "0.55"))
	_out_dir = _arg("--out", "res://screenshots")
	_scale = clampf(float(_arg("--scale", "1.0")), 0.1, 1.0)
	_lines = "--lines" in args
	var names: Array = []
	if names_arg == "all":
		for f in DirAccess.get_files_at("res://scenes/rooms"):
			if f.ends_with(".tscn"):
				names.append(f.get_basename())
		names.sort()
	else:
		names = Array(names_arg.split(","))
	var states: Array = []
	var st := _arg("--states", "")
	if st != "":
		states = Array(st.split(","))
	else:
		states = ["ash" if "--ash" in args else ("alive" if "--alive" in args else "")]
	for n in names:
		for s in states:
			_jobs.append([n, s])
	_next_job()


## 다음 [방, 상태]를 띄운다 (앞 방은 지운다)
func _next_job() -> void:
	if _room:
		_room.queue_free()
		_room = null
	_cam = null
	_views.clear()
	_i = -1
	_t = 0.0
	_job += 1
	if _job >= _jobs.size():
		quit(0)
		return
	_name = _jobs[_job][0]
	var state: String = _jobs[_job][1]
	_suffix = "_" + state if state != "" else ""
	var scene: PackedScene = load("res://scenes/rooms/%s.tscn" % _name)
	_room = scene.instantiate()
	# 상태를 정한 경우: 방이 뜨기 전에 그 지역의 정화 여부를 정해 둔다 (방·웅덩이·표시등이 _ready 에서 읽는다)
	if state != "" and "region" in _room:
		var purity := root.get_node("Purity")
		purity.regions[str(_room.get("region"))] = state == "alive"
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
	if _spot == "player":
		var player := get_first_node_in_group("player") as Node2D
		var c := player.global_position + Vector2(0, -80) if player else b.get_center()
		# 방 경계 안으로 (게임 카메라처럼)
		c.x = clampf(c.x, b.position.x + vp.x * 0.5, maxf(b.position.x + vp.x * 0.5, b.end.x - vp.x * 0.5))
		c.y = clampf(c.y, b.position.y + vp.y * 0.5, maxf(b.position.y + vp.y * 0.5, b.end.y - vp.y * 0.5))
		_views.append(c)
		return
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
	if _room == null:
		return false
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
	return false


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
		if _scale < 0.999:
			img.resize(roundi(img.get_width() * _scale), roundi(img.get_height() * _scale), Image.INTERPOLATE_BILINEAR)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		img.save_png(path)
		print("[shots] %s  카메라 %s 배율 %.2f" % [path, _views[_i], _zoom])
	_busy = false
	_next()
	if _i >= _views.size():
		_next_job()


## 충돌 윗면(발판·경사 윗변)을 빨간 선으로 겹쳐 그린다 (맞춤 확인용).
## 클래스 이름(Platform 등)을 쓰지 않는다 — 이 스크립트가 자동 로드보다 먼저 읽힐 때 그 클래스들이 따라 읽히면
## 자동 로드(Progress)를 못 찾아 소녀 그림까지 깨진다.
class LineOverlay extends Node2D:
	var room: Node

	func _draw() -> void:
		var terrain := room.get_node_or_null("Terrain")
		if terrain == null:
			return
		for t in terrain.get_children():
			if "polygon" not in t and "size" in t:
				var p: Vector2 = t.global_position
				draw_line(p, p + Vector2(t.size.x, 0), Color(1, 0.1, 0.1, 0.9), 2.0)
				draw_rect(Rect2(p, t.size), Color(1, 0.1, 0.1, 0.35), false, 1.0)
			elif "polygon" in t:
				var poly: PackedVector2Array = t.polygon
				var o: Vector2 = t.global_position
				for i in poly.size():
					var a := poly[i] + o
					var b := poly[(i + 1) % poly.size()] + o
					draw_line(a, b, Color(1, 0.1, 0.1, 0.6), 1.5)

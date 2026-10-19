extends SceneTree
## 지형 디테일 눈 확인용 스크린샷 (화면 있는 실행). 방을 띄우고 원하는 자리에 카메라를 두고 PNG 를 남긴다.
## 실행 (창이 잠깐 뜬다):
##   godot --path . -s res://tools/probe_terrain_shot.gd -- --room=canopy_01 --at=2000,1000 --zoom=1.0 --alive --out=terrain_canopy01.png
##   --room=<방 id>  --at=<x,y 월드 좌표>  --zoom=<배율, 기본 1.0 / 평소 플레이 배율은 1.15>
##   --out=<screenshots/ 안의 파일 이름, 또는 / 로 시작하는 절대 경로>
##   --alive / --ash 는 Room 이 읽어 정화 전후를 고른다. --detail=0 이면 옛 수준으로 그린다(비교용).
##   --region=sap_lake 처럼 주면 방의 모든 지형이 그 지역 팔레트로 그려진다 (아직 방이 없는 확장 지역 미리 보기).

var _t := 0.0
var _room: Node
var _out := "terrain_shot.png"
var _at := Vector2(1000, 1000)
var _zoom := 1.0
var _saved := false


func _arg(name: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.trim_prefix(name + "=")
	return default


func _initialize() -> void:
	var room_id := _arg("--room", "canopy_01")
	_out = _arg("--out", "terrain_%s.png" % room_id)
	var at := _arg("--at", "1000,1000").split(",")
	_at = Vector2(float(at[0]), float(at[1]))
	_zoom = float(_arg("--zoom", "1.0"))
	TerrainStyle.detail = int(_arg("--detail", "1"))
	var scene: PackedScene = load("res://scenes/rooms/%s.tscn" % room_id)
	_room = scene.instantiate()
	var region := _arg("--region", "")
	if region != "":
		_force_region(_room, region)
	root.add_child(_room)
	current_scene = _room
	print("[shot] %s 카메라 %s 배율 %.2f detail=%d" % [room_id, _at, _zoom, TerrainStyle.detail])


var _cam: Camera2D


## 방이 뜨기 전에 모든 지형의 style_region 을 바꾼다 (Platform / TerrainPolygon / Thorns).
func _force_region(node: Node, region: String) -> void:
	if "style_region" in node:
		node.set("style_region", region)
	for c in node.get_children():
		_force_region(c, region)


## 소녀의 카메라를 끄고 내 카메라를 쓴다 (방이 다 뜬 다음 프레임에).
func _take_camera() -> void:
	var player := get_first_node_in_group("player")
	if player:
		var pc := player.get_node_or_null("Camera2D")
		if pc:
			pc.enabled = false
	_cam = Camera2D.new()
	_cam.position = _at
	_cam.zoom = Vector2(_zoom, _zoom)
	_room.add_child(_cam)
	_cam.make_current()


func _process(delta: float) -> bool:
	_t += delta
	if _cam == null and _t > 0.3:
		_take_camera()
	if _t > 2.6 and not _saved:
		_saved = true
		_save()
	return _t > 3.2


func _save() -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		var path := _out if _out.begins_with("/") else ProjectSettings.globalize_path("res://screenshots/" + _out)
		img.save_png(path)
		print("[shot] 저장: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	else:
		print("[shot] 실패: 화면을 못 읽음")
	quit(0)

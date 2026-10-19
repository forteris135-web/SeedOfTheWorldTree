extends Node
## 무쇠 펌프 조립 그림 만들기 (창으로 실행 — 그림을 실제로 그려서 저장한다):
##   Godot --path . res://tools/pump_render.tscn [-- <뼈대 id, 기본 iron_pump> <저장 경로, 기본 res://art/bosses/boss_iron_pump_now.png> [--pose idle]]
## 부위 뼈대를 대기 자세로 세워 투명 바탕 1536×1024 에 왼쪽을 보게(예전 임시 그림과 같은 방향) 그린다. 발바닥은 아래에서 34px 위.
## 또렷하게 뽑으려면 같은 설계도를 out_scale 1.0 으로 자른 뼈대(예: iron_pump_hd — 저장소에 두지 않는다)를 주면 된다.

const W := 1536
const H := 1024
const FEET_Y := 990


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var pos: Array = []
	var pose_name := "idle"
	var i := 0
	while i < args.size():
		if args[i] == "--pose" and i + 1 < args.size():
			pose_name = args[i + 1]
			i += 1
		elif not args[i].begins_with("--"):
			pos.append(args[i])
		i += 1
	var rig_id: String = pos[0] if pos.size() > 0 else "iron_pump"
	var out: String = pos[1] if pos.size() > 1 else "res://art/bosses/boss_iron_pump_now.png"
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var rig := PartRig.new()
	vp.add_child(rig)
	if not rig.build(rig_id):
		get_tree().quit(1)
		return
	var m := RigMotion.new(rig)
	m.breath = 0.0
	m.set_target(m.pose(pose_name), RigMotion.Drive.NORMAL, RigMotion.Feet.POSE)
	m.snap_feet()
	for f in 180:
		m.update(1.0 / 60.0, {})
	# 시트 픽셀 1:1 (뼈대 단위 = 시트 px) — 그림 폭이 캔버스에 들어가게 필요하면 줄인다
	var b := rig.bounds()
	var k := minf(1.0, minf((W - 40.0) / maxf(b.size.x, 1.0), (FEET_Y - 20.0) / maxf(-b.position.y, 1.0)))
	var s := k / rig.game_scale
	rig.scale = Vector2(-s, s)
	var cx := (b.position.x + b.size.x * 0.5) * k
	rig.position = Vector2(W * 0.5 + cx, FEET_Y)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	# 투명 바탕에 섞어 그리면 반투명 가장자리 색이 알파만큼 어두워진다(미리 곱한 색) → 알파로 나눠 되돌린다 (밝은 바탕에서 검은 테두리가 안 보이게)
	var d := img.get_data()
	for p in range(0, d.size(), 4):
		var a := d[p + 3]
		if a > 0 and a < 255:
			var f := 255.0 / a
			d[p] = mini(int(d[p] * f + 0.5), 255)
			d[p + 1] = mini(int(d[p + 1] * f + 0.5), 255)
			d[p + 2] = mini(int(d[p + 2] * f + 0.5), 255)
	img = Image.create_from_data(W, H, false, Image.FORMAT_RGBA8, d)
	img.save_png(ProjectSettings.globalize_path(out))
	print("[pump_render] %s → %s (배율 %.2f, 상자 %s)" % [rig_id, ProjectSettings.globalize_path(out), k, str(b)])
	get_tree().quit()

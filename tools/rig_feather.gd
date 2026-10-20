extends SceneTree
## 부위 뼈대 그림의 '자른 선'을 부드럽게 (페더) — tools/rig_cut.gd 로 자른 **뒤에** 돌린다.
## 완성 그림 한 장을 몸통·치마처럼 두 겹으로 자르면, 자른 선이 그림 속을 가로지른다. 두 겹이 겹친 띠에서
## 반투명 잎 가장자리가 두 번 칠해지고 자른 선이 곧은 줄로 비친다(몸통이 조금만 기울어도 더 보인다).
## 설계도 부위에 "feather" 를 적으면 그 선분 가까이에서 알파를 0 → 1 로 천천히 올린다 → 겹친 띠가 서로 녹아든다.
##
##   "feather": [{"from": [x0, y0], "to": [x1, y1], "px": 36}, …]     (좌표는 rig_cut 과 같이 원본 시트 px)
##   선분에서 px 안쪽까지 알파가 smoothstep 으로 0 → 1. 선분 '양쪽' 모두에 걸리니, 자른 경계 위에 선분을 둔다.
##
## 사용 (프로젝트 폴더에서, 병렬 작업이면 /Users/wj/Projects/SeedWT/godot 래퍼로):
##   Godot --headless --path . --script tools/rig_cut.gd -- <id>
##   Godot --headless --path . --script tools/rig_feather.gd -- <id>
##   (그다음 늘 하던 대로 tools/cloud_bootstrap.sh 로 가져오기)
## 그림 좌표 = (시트 좌표 − 시트 pivot) × 배율 + 그림 pivot. faces:"left"·mirror 부위도 rig_cut 과 같은 규칙으로 뒤집어 계산한다.


func _init() -> void:
	var ids := OS.get_cmdline_user_args()
	if ids.is_empty():
		print("사용: ... --script tools/rig_feather.gd -- <id> [<id> ...]")
		quit(1)
		return
	var fail := 0
	for id in ids:
		if not _feather(id):
			fail += 1
	quit(1 if fail > 0 else 0)


func _feather(id: String) -> bool:
	var spec_path := "res://data/rigs/%s.json" % id
	var rig_path := "res://art/rigs/%s/rig.json" % id
	var spec = JSON.parse_string(FileAccess.get_file_as_string(spec_path))
	var rig = JSON.parse_string(FileAccess.get_file_as_string(rig_path))
	if not (spec is Dictionary) or not (rig is Dictionary):
		push_error("설계도나 rig.json 을 읽지 못했다: " + id)
		return false
	var flip := str(spec.get("faces", "right")) == "left"
	var sheet_w := 0.0
	if flip:
		var img := Image.load_from_file(ProjectSettings.globalize_path(str(spec["sheet"])))
		sheet_w = float(img.get_width())
	var bones := {}
	for b in rig["bones"]:
		bones[str(b["name"])] = b
	var parts: Dictionary = spec["parts"]
	var n := 0
	for name in parts:
		var part: Dictionary = parts[name]
		if not part.has("feather") or part.has("from"):
			continue
		var b: Dictionary = bones.get(name, {})
		if b.is_empty():
			push_error("rig.json 에 없는 부위: " + str(name))
			return false
		var png := ProjectSettings.globalize_path(str(b["tex"]))
		var tex := Image.load_from_file(png)
		if tex == null:
			push_error("그림을 읽지 못했다: " + png)
			return false
		tex.convert(Image.FORMAT_RGBA8)
		var k := 1.0 / float(b.get("tex_scale", 2.0))
		var pv_tex := Vector2(b["pivot"][0], b["pivot"][1])
		var pv_sheet := _sheet_pt(part["pivot"], part, flip, sheet_w)
		var segs: Array = []
		for f in part["feather"]:
			var a := (_sheet_pt(f["from"], part, flip, sheet_w) - pv_sheet) * k + pv_tex
			var c := (_sheet_pt(f["to"], part, flip, sheet_w) - pv_sheet) * k + pv_tex
			segs.append([a, c, maxf(float(f.get("px", 30.0)) * k, 1.0)])
		var w := tex.get_width()
		var h := tex.get_height()
		var data := tex.get_data()
		for y in h:
			for x in w:
				var i := (y * w + x) * 4 + 3
				if data[i] == 0:
					continue
				var p := Vector2(x + 0.5, y + 0.5)
				var m := 1.0
				for s in segs:
					var d := _seg_dist(p, s[0], s[1])
					if d < s[2]:
						m *= smoothstep(0.0, s[2], d)
				if m < 1.0:
					data[i] = int(round(data[i] * m))
		var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
		out.save_png(png)
		n += 1
		print("[rig_feather] %s/%s: 선 %d개 부드럽게" % [id, name, segs.size()])
	print("[rig_feather] %s: 부위 %d개" % [id, n])
	return true


## 설계도 좌표(원본 시트) → 뼈대 좌표 (rig_cut._to_rig 와 같은 뒤집기)
static func _sheet_pt(pt, part: Dictionary, flip: bool, sheet_w: float) -> Vector2:
	var v := Vector2(float(pt[0]), float(pt[1]))
	if flip:
		v.x = sheet_w - v.x
	if bool(part.get("mirror", false)):
		var pv := Vector2(float(part["pivot"][0]), float(part["pivot"][1]))
		if flip:
			pv.x = sheet_w - pv.x
		v.x = 2.0 * pv.x - v.x
	return v


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

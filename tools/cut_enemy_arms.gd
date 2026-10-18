extends SceneTree
## 적 그림을 몸통/무기 팔 두 겹으로 나눈다. 팔 영역은 아래 다각형(원본 px)으로 정한다.
## 결과: art/enemies/parts/<이름>_body.png, <이름>_arm.png (둘 다 1/2 크기) + parts.json (어깨 축, 팔 조각의 위치).
## 사용: Godot --headless --path . --script tools/cut_enemy_arms.gd

const HALF := 0.5
const CUTS := {
	"enemy_woodcutter": {
		"pivot": Vector2(900, 450),
		"arm": [Vector2(935, 385), Vector2(820, 345), Vector2(690, 375), Vector2(520, 450), Vector2(250, 605), Vector2(30, 750), Vector2(10, 900), Vector2(40, 990), Vector2(200, 970), Vector2(420, 890), Vector2(600, 795), Vector2(760, 645), Vector2(870, 565), Vector2(950, 480)],
		"erase": [],
	},
	"enemy_woodcutter_savable": {
		"pivot": Vector2(760, 440),
		"arm": [Vector2(795, 375), Vector2(675, 330), Vector2(450, 425), Vector2(225, 605), Vector2(75, 775), Vector2(20, 900), Vector2(60, 1000), Vector2(165, 985), Vector2(385, 866), Vector2(612, 738), Vector2(762, 618), Vector2(820, 520)],
		"erase": [],
	},
	"enemy_gardener": {
		"pivot": Vector2(850, 380),
		"arm": [Vector2(820, 300), Vector2(900, 295), Vector2(1000, 345), Vector2(1215, 415), Vector2(1215, 520), Vector2(1120, 525), Vector2(960, 475), Vector2(830, 435)],
		"erase": [Rect2(1215, 330, 330, 460)],
	},
	"enemy_gardener_savable": {
		"pivot": Vector2(640, 375),
		"arm": [Vector2(690, 310), Vector2(560, 310), Vector2(430, 375), Vector2(305, 425), Vector2(305, 505), Vector2(400, 505), Vector2(520, 475), Vector2(640, 435), Vector2(700, 385)],
		"erase": [Rect2(0, 180, 305, 650)],
	},
}


func _init() -> void:
	var meta := {}
	for name in CUTS:
		var c: Dictionary = CUTS[name]
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://art/enemies/%s.png" % name))
		var w := img.get_width()
		var h := img.get_height()
		for r in c["erase"]:
			img.fill_rect(Rect2i(r.position, r.size), Color(0, 0, 0, 0))
		var poly: PackedVector2Array = PackedVector2Array(c["arm"])
		var bbox := Rect2i(Vector2i(w, h), Vector2i.ZERO)
		var minx := w; var maxx := 0; var miny := h; var maxy := 0
		for p in poly:
			minx = mini(minx, int(p.x)); maxx = maxi(maxx, int(p.x)); miny = mini(miny, int(p.y)); maxy = maxi(maxy, int(p.y))
		var arm := Image.create(maxx - minx + 1, maxy - miny + 1, false, Image.FORMAT_RGBA8)
		var body := img.duplicate()
		for y in range(miny, maxy + 1):
			for x in range(minx, maxx + 1):
				if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
					arm.set_pixel(x - minx, y - miny, img.get_pixel(x, y))
					body.set_pixel(x, y, Color(0, 0, 0, 0))
		body.resize(int(w * HALF), int(h * HALF), Image.INTERPOLATE_LANCZOS)
		arm.resize(maxi(int(arm.get_width() * HALF), 1), maxi(int(arm.get_height() * HALF), 1), Image.INTERPOLATE_LANCZOS)
		body.save_png(ProjectSettings.globalize_path("res://art/enemies/parts/%s_body.png" % name))
		arm.save_png(ProjectSettings.globalize_path("res://art/enemies/parts/%s_arm.png" % name))
		meta[name] = {"pivot": [c["pivot"].x, c["pivot"].y], "arm_pos": [minx, miny], "size": [w, h]}
		print("%s: 몸통 %dx%d, 팔 %dx%d (원본 %d,%d), 어깨 %s" % [name, body.get_width(), body.get_height(), arm.get_width(), arm.get_height(), minx, miny, c["pivot"]])
	var f := FileAccess.open(ProjectSettings.globalize_path("res://art/enemies/parts/parts.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	quit()

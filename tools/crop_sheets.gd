extends SceneTree
## 한 장에 두 상태가 있는 그림을 둘로 자른다. (Godot로 실행: Godot --headless --path . --script tools/crop_sheets.gd)
## 자를 범위는 아래 표에 적는다: [원본, 결과, x, y, 너비, 높이]

const CROPS := [
	["res://art/objects/moonlight_grass_sheet.png", "res://art/objects/moonlight_grass_closed.png", 0, 0, 548, 1024],
	["res://art/objects/moonlight_grass_sheet.png", "res://art/objects/moonlight_grass_open.png", 520, 0, 1016, 1024],
	["res://art/objects/tia_lantern_sheet.png", "res://art/objects/tia_lantern.png", 0, 0, 768, 1024],
	["res://art/objects/tia_lantern_sheet.png", "res://art/objects/tia_lantern_off.png", 768, 0, 768, 1024],
]


func _init() -> void:
	for c in CROPS:
		var img := Image.load_from_file(ProjectSettings.globalize_path(c[0]))
		if img == null:
			print("못 읽음: ", c[0])
			continue
		var region := img.get_region(Rect2i(c[2], c[3], c[4], c[5]))
		var err := region.save_png(ProjectSettings.globalize_path(c[1]))
		print("%s  →  %s  (%dx%d) %s" % [c[0].get_file(), c[1].get_file(), region.get_width(), region.get_height(), "ok" if err == OK else "실패 %d" % err])
	quit()

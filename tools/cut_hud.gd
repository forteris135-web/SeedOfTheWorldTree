extends SceneTree
## 투명 HUD 시트(art/ui/hud_sheet.png, 2156×729)에서 조각을 잘라낸다.
## 사용: Godot --headless --path . --script tools/cut_hud.gd
## 좌표는 모두 시트 기준. combat_hud.gd 의 상수와 같아야 한다.

const SHEET := "res://art/ui/hud_sheet.png"
const DEWS := [Rect2i(405, 445, 150, 210), Rect2i(560, 445, 150, 210), Rect2i(735, 445, 155, 210)]
const CUTS := {
	"hud_emblem.png": Rect2i(0, 0, 560, 729),
	"hud_bar_hp.png": Rect2i(540, 60, 1616, 258),
	"hud_bar_guard.png": Rect2i(540, 318, 1616, 185),
	"hud_dew_1.png": DEWS[0],
	"hud_dew_2.png": DEWS[1],
	"hud_dew_3.png": DEWS[2],
}


func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	for name in CUTS:
		var rect: Rect2i = CUTS[name]
		var piece := img.get_region(rect)
		# 엠블럼·가드 막대 조각에서는 이슬 자리를 비운다 (이슬은 따로 그려 상태에 따라 어둡게 한다)
		if name == "hud_emblem.png" or name == "hud_bar_guard.png":
			for d in DEWS:
				var inter: Rect2i = rect.intersection(d)
				if inter.has_area():
					piece.fill_rect(Rect2i(inter.position - rect.position, inter.size), Color(0, 0, 0, 0))
		var err := piece.save_png(ProjectSettings.globalize_path("res://art/ui/" + name))
		print("%s  %dx%d  %s" % [name, piece.get_width(), piece.get_height(), "ok" if err == OK else "실패"])
	quit()

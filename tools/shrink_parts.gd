extends SceneTree
## 셀레니아 부위 조각을 1/4로 줄여 저장한다 (게임에서는 약 0.46배로 그려 지글거림을 줄인다).
const DIR := "res://art/characters/selenia/"
const NAMES := {
	"part_03.png": "head.png", "part_04.png": "torso.png", "part_06.png": "arm_back.png", "part_05.png": "arm_sword.png",
	"part_08.png": "leg_back.png", "part_07.png": "leg_front.png", "part_01.png": "cloak_near.png", "part_02.png": "cloak_far.png",
	"part_09.png": "cape.png",
}
const FACTOR := 0.25

func _init() -> void:
	for src in NAMES:
		var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + src))
		var w := int(round(img.get_width() * FACTOR))
		var h := int(round(img.get_height() * FACTOR))
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
		img.save_png(ProjectSettings.globalize_path(DIR + NAMES[src]))
		print("%s → %s  %dx%d" % [src, NAMES[src], w, h])
	quit()

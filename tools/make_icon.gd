extends SceneTree
## 앱 아이콘: 타이틀 일러스트에서 소녀의 얼굴과 등불이 보이는 정사각형을 잘라 1024×1024 로 저장한다.
## 모서리는 iOS 가 알아서 둥글게 만든다 (투명 없음).
func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://art/characters/title_selenia.png"))
	# 원본 1672×941. 소녀는 왼쪽 ~ 가운데. 얼굴(약 x 520, y 390)과 등불이 들어오게 정사각형 920 을 잡는다.
	var side := 920
	var rect := Rect2i(120, 10, side, side)
	var crop := img.get_region(rect)
	crop.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	# 가장자리를 살짝 어둡게 (비네트) 해서 작은 크기에서도 얼굴이 도드라지게
	for y in 1024:
		for x in 1024:
			var d := Vector2(x - 512, y - 512).length() / 724.0
			var k := 1.0 - clampf((d - 0.55) / 0.45, 0.0, 1.0) * 0.55
			var c := crop.get_pixel(x, y)
			crop.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k, 1.0))
	crop.save_png(ProjectSettings.globalize_path("res://art/ui/app_icon.png"))
	var small := crop.duplicate()
	small.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	small.save_png(ProjectSettings.globalize_path("res://icon.png"))
	print("아이콘 저장")
	quit()

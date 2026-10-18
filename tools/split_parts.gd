extends SceneTree
## 부위 분리 그림(selenia_parts.png)에서 서로 떨어진 조각을 자동으로 찾아 각각 PNG로 저장한다.
## 사용: Godot --headless --path . --script tools/split_parts.gd
## 결과: art/characters/selenia/part_N.png + parts.json (위치·크기). 이름은 사람이 보고 붙인다.

const SRC := "res://art/characters/selenia_parts.png"
const OUT_DIR := "res://art/characters/selenia/"
const ALPHA := 0.3
const GAP := 1
const MIN_PIXELS := 400


func _init() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(SRC))
	var w := img.get_width()
	var h := img.get_height()
	# 1) 불투명 마스크 (조금 부풀려서 끊긴 부분을 잇는다)
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		for x in w:
			solid[y * w + x] = 1 if img.get_pixel(x, y).a > ALPHA else 0
	var grown := solid.duplicate()
	for y in h:
		for x in w:
			if solid[y * w + x] == 0:
				var found := false
				for dy in range(-GAP, GAP + 1):
					var yy := y + dy
					if yy < 0 or yy >= h: continue
					for dx in range(-GAP, GAP + 1):
						var xx := x + dx
						if xx < 0 or xx >= w: continue
						if solid[yy * w + xx] == 1:
							found = true
							break
					if found: break
				if found:
					grown[y * w + x] = 1
	# 2) 연결 성분
	var label := PackedInt32Array()
	label.resize(w * h)
	var count := 0
	var boxes: Array = []
	for y in h:
		for x in w:
			if grown[y * w + x] == 1 and label[y * w + x] == 0:
				count += 1
				var stack: Array[int] = [y * w + x]
				label[y * w + x] = count
				var minx := x; var maxx := x; var miny := y; var maxy := y; var n := 0
				while not stack.is_empty():
					var i: int = stack.pop_back()
					var px := i % w
					var py := i / w
					if solid[i] == 1: n += 1
					minx = mini(minx, px); maxx = maxi(maxx, px); miny = mini(miny, py); maxy = maxi(maxy, py)
					for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
						var nx: int = px + d[0]
						var ny: int = py + d[1]
						if nx < 0 or ny < 0 or nx >= w or ny >= h: continue
						var j := ny * w + nx
						if grown[j] == 1 and label[j] == 0:
							label[j] = count
							stack.append(j)
				if n >= MIN_PIXELS:
					boxes.append({"id": count, "rect": Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1), "pixels": n})
	boxes.sort_custom(func(a, b): return a["pixels"] > b["pixels"])
	# 3) 저장 (다른 조각의 픽셀은 지운 채로)
	var meta := []
	var k := 0
	for b in boxes:
		k += 1
		var r: Rect2i = b["rect"]
		var piece := Image.create(r.size.x, r.size.y, false, Image.FORMAT_RGBA8)
		for y in r.size.y:
			for x in r.size.x:
				var gx := r.position.x + x
				var gy := r.position.y + y
				if label[gy * w + gx] == b["id"]:
					piece.set_pixel(x, y, img.get_pixel(gx, gy))
		piece.save_png(ProjectSettings.globalize_path(OUT_DIR + "part_%02d.png" % k))
		meta.append({"file": "part_%02d.png" % k, "x": r.position.x, "y": r.position.y, "w": r.size.x, "h": r.size.y, "pixels": b["pixels"]})
		print("part_%02d  x %d y %d  %dx%d  (%d px)" % [k, r.position.x, r.position.y, r.size.x, r.size.y, b["pixels"]])
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT_DIR + "parts.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	quit()

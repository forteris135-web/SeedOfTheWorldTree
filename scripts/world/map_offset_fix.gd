extends Node
class_name MapOffsetFix
## 옛 저장 파일의 지도 바로잡기 (확장판 · 잠긴 채굴장). 지도는 '가 본 방'의 자리(offset)를 저장해 두고 그대로 그린다.
## 확장판은 책임자의 방(mine_deep)을 오른쪽으로 넓히면서 심연 방들의 지도 자리를 밀었으므로(tools/link_flooded_mine.py),
## 1편 저장으로 이어하면 넓어진 책임자의 방과 아직 다시 가지 않은 심연 방이 지도에서 겹친다.
## 이 노드는 넓어진 책임자의 방에 들어서는 순간(= 그 방의 지도 칸이 넓어지는 순간) 저장된 옛 자리를 새 자리로 고친다.
## moves: room_id -> [옛 자리 Vector2, 새 자리 Vector2]. 옛 자리와 같을 때만 고친다 (이미 새 자리면 그대로).

@export var moves := {}


func _ready() -> void:
	fix(Progress.visited_rooms)


func fix(rooms: Dictionary) -> int:
	var n := 0
	for id in moves:
		var entry = rooms.get(id)
		var pair = moves[id]
		if not (entry is Dictionary) or not entry.has("offset") or not (pair is Array) or pair.size() < 2:
			continue
		var off: Vector2 = entry["offset"]
		if off.is_equal_approx(pair[0]):
			entry["offset"] = pair[1]
			n += 1
	return n

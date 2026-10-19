extends Node
class_name MapOffsetFix
## 옛 저장 파일의 지도 바로잡기 (확장판 · 잠긴 채굴장). 지도는 '가 본 방'의 자리(offset)를 저장해 두고 그대로 그린다.
## 확장판은 책임자의 방(mine_deep)을 오른쪽으로 넓히면서 심연 방들의 지도 자리를 밀었으므로(tools/link_flooded_mine.py),
## 1편 저장으로 이어하면 넓어진 책임자의 방과 아직 다시 가지 않은 심연 방이 지도에서 겹친다.
## 이 노드는 넓어진 책임자의 방에 들어서는 순간(= 그 방의 지도 칸이 넓어지는 순간) 저장된 옛 자리를 새 자리로 고친다.
## moves: room_id -> [옛 자리 Vector2, 새 자리 Vector2]. 옛 자리와 같을 때만 고친다 (이미 새 자리면 그대로).

@export var moves := {}

## 저장 파일을 읽을 때 한 번에 고치는 표 (SaveGame.load_game 이 부른다). 위 노드는 mine_deep 에 들어설 때만 고쳐서,
## 심연 달빛풀에서 이어하면 책임자의 방에 다시 가기 전까지 지도에서 심연 방 둘이 겹쳤다 (2026-10-19 검수).
## hidden_descent: 입구를 HUD 밑에서 빼느라 오른쪽으로 옮기며 지도 자리도 맞춰 밀었다 (마을 숨은 틈 바로 아래).
const SAVE_MOVES := {
	"abyss_01": [Vector2(39300, 500), Vector2(41100, 500)],
	"abyss_02": [Vector2(43500, 100), Vector2(45300, 100)],
	"abyss_boss": [Vector2(50100, -200), Vector2(51900, -200)],
	"abyss_mini_1": [Vector2(43800, -1400), Vector2(45600, -1400)],
	"moon_garden": [Vector2(47100, 300), Vector2(48900, 300)],
	"hidden_descent": [Vector2(24320, -923), Vector2(23540, -923)],
}


func _ready() -> void:
	fix(Progress.visited_rooms)


## 저장 파일에서 읽은 지도 기록을 새 자리로 고친다. 고친 방 수를 돌려준다.
static func fix_saved(rooms: Dictionary) -> int:
	var f := MapOffsetFix.new()
	f.moves = SAVE_MOVES
	var n := f.fix(rooms)
	f.free()
	return n


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

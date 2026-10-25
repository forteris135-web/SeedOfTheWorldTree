class_name RoomIndex
extends RefCounted
## 방 이름의 단일 출처 (지도·달빛풀 이동·저장 칸이 같은 이름을 쓴다). 지금은 틀만 있다 — 채우는 것은 W1 (data/map/rooms_index.json).
const REGION_LABEL := {"canopy": "수관", "village": "마을", "mine": "채굴장", "flooded_mine": "잠긴 채굴장", "sap_lake": "수액의 호수", "abyss": "심연"}
static func region_label(region: String) -> String: return REGION_LABEL.get(region, region)
static func room_name(room_id: String, fallback := "") -> String: return fallback   # W1 이 data/map/rooms_index.json 으로 채운다
static func grass_room_name(grass_id: String, fallback := "") -> String: return fallback
static func room_of_grass(grass_id: String) -> String: return ""

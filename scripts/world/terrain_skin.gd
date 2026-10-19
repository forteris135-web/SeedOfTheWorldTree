class_name TerrainSkin
extends RefCounted
## 지역 지형의 '그림 옷' (그림 조각 기반 지형 — 설명서는 TERRAIN.md).
## data/terrain/<지역>.json (사람이 쓰는 설명: 배율·색·역할별 조각 목록) 과
## art/terrain/<지역>/pieces.json (tools/terrain_cut.gd 가 잰 값: atlas 자리·윗선·걷는 구간) 을 함께 읽는다.
## 그림 옷이 없는 지역(아직 그림이 안 온 곳)은 null → 지형은 옛 방식(TerrainStyle, 코드로 그리기)으로 그린다.
##
## 역할(role) — 조각마다 pieces.json 에 적혀 있고, data 의 "roles" 로 덮어쓰거나 거를 수 있다:
##   branch : 떠 있는 가지 발판 (얇은 발판·얇은 경사). 걷는 구간을 충돌 윗면에 맞춰 늘이거나 이어 붙인다.
##   slab   : 짧은 한쪽 방향(one_way) 발판용 떠 있는 판.
##   ground : 큰 바닥·덩어리 윗면에 이어 까는 띠 (윗면에서 band px 아래까지만 그리고 fade px 동안 몸통 결로 녹아든다).
##   hang   : 천장·덩어리 아랫면·드러난 옆면에 매다는 장식 (덩굴·꽃).
##   bush   : 윗면에 가끔 얹는 작은 덤불.
##   thorn  : 가시 (Thorns). cracked : 금 간 벽 (SecretWall·SecretCeiling·CrackedWall).

const DATA_DIR := "res://data/terrain/"
const ART_DIR := "res://art/terrain/"

## 시험용: false 면 모든 지역이 옛 그림으로 그린다 (tools/probe_terrain 이 옛 방식도 따로 시험한다).
static var enabled := true
static var _cache := {}

var region := ""
var data := {}
var pieces := {}
var roles := {}
var atlas: Texture2D
var atlas_size := Vector2.ONE
var fill: Texture2D
var fill_v: Texture2D
var step := 8
## 그림 px → 월드 px
var scale := 1.0
## 정화 후 기준 색 (곱하기). 배경보다 살짝 어둡게 해 앞 지형이 읽히게 한다.
var tint := Color(1, 1, 1)
## 발 딛는 선이 충돌 윗면보다 이만큼 위에 오게 (잎 사이에 발이 살짝 묻히게)
var lift := 4.0


## 지역 이름 → 그림 옷 (없으면 null). 한 번 읽으면 기억한다.
static func for_region(region: String) -> TerrainSkin:
	if not enabled:
		return null
	if _cache.has(region):
		return _cache[region]
	var skin: TerrainSkin = null
	var path := DATA_DIR + region + ".json"
	if FileAccess.file_exists(path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary and bool(d.get("enabled", true)):
			var s := TerrainSkin.new()
			if s._load(region, d):
				skin = s
	_cache[region] = skin
	return skin


## 지형 노드가 쓸 그림 옷: override 가 있으면 그 지역, 없으면 조상 Room 의 region.
## 방 하나만 지역과 다른 그림 옷을 입히려면 방(Room) 노드에 메타 "terrain_skin" 을 둔다
## (예: 숨은 내리막 — 지역은 sap_lake 그대로(정화·음악·잿빛 표), 지형 그림만 data/terrain/sap_descent.json).
static func for_node(node: Node, override := "") -> TerrainSkin:
	if override == "":
		var room := TerrainStyle.room_of(node)
		if room != null and room.has_meta("terrain_skin"):
			override = str(room.get_meta("terrain_skin"))
	return for_region(override if override != "" else TerrainStyle.region_of(node))


## 시험용: 기억한 것을 비운다 (그림을 다시 자른 뒤 등).
static func clear_cache() -> void:
	_cache.clear()


func _load(r: String, d: Dictionary) -> bool:
	region = r
	data = d
	var meta_path := ART_DIR + r + "/pieces.json"
	if not FileAccess.file_exists(meta_path):
		return false
	var m = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not (m is Dictionary):
		return false
	pieces = m.get("pieces", {})
	step = int(m.get("step", 8))
	var a: Array = m.get("atlas", [1, 1])
	atlas_size = Vector2(float(a[0]), float(a[1]))
	var ap := ART_DIR + r + "/atlas.png"
	if not ResourceLoader.exists(ap):
		return false
	atlas = load(ap)
	if ResourceLoader.exists(ART_DIR + r + "/fill.png"):
		fill = load(ART_DIR + r + "/fill.png")
	if ResourceLoader.exists(ART_DIR + r + "/fill_v.png"):
		fill_v = load(ART_DIR + r + "/fill_v.png")
	scale = float(d.get("scale", 1.0))
	lift = float(d.get("lift", 4.0))
	var t: Array = d.get("tint", [1, 1, 1])
	tint = Color(float(t[0]), float(t[1]), float(t[2]))
	# 역할 표: pieces.json 의 role 로 모으고, data 의 roles 가 있으면 그 목록으로 덮어쓴다 (조각 빼기·순서 바꾸기)
	for n in pieces:
		var role := str(pieces[n].get("role", ""))
		if role == "":
			continue
		if not roles.has(role):
			roles[role] = []
		roles[role].append(n)
	var over: Dictionary = d.get("roles", {})
	for role in over:
		var list: Array = []
		for n in over[role]:
			if pieces.has(n):
				list.append(n)
		roles[role] = list
	return true


func has_role(role: String) -> bool:
	return roles.has(role) and not (roles[role] as Array).is_empty()


func list(role: String) -> Array:
	return roles.get(role, [])


## 역할별 설정 (data 의 "params": {역할: {…}}), 없으면 기본값
func param(role: String, key: String, default):
	var p: Dictionary = data.get("params", {}).get(role, {})
	return p.get(key, default)


## data 의 "fill" 설정 값
func fill_param(key: String, default: float) -> float:
	return float(data.get("fill", {}).get(key, default))


## 조각의 atlas 안 자리 (px)
func rect_of(name: String) -> Rect2:
	var r: Array = pieces[name]["rect"]
	return Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))


## 조각 안 가로 u(원래 px)에서의 발 딛는 선 (걷는 구간 밖은 끝 값 그대로 — 끝 부분은 휘지 않는다)
func top_at(name: String, u: float) -> float:
	var m: Dictionary = pieces[name]
	var top: Array = m.get("top", [])
	if top.is_empty():
		return 0.0
	var walk: Array = m.get("walk", [0, float(m["size"][0])])
	u = clampf(u, float(walk[0]), float(walk[1]))
	var f := u / step
	var i := clampi(int(f), 0, top.size() - 1)
	var j := mini(i + 1, top.size() - 1)
	var a := float(top[i])
	var b := float(top[j])
	if a < 0.0:
		a = b
	if b < 0.0:
		b = a
	if a < 0.0:
		return float(m.get("walk_y", 0.0))
	return lerpf(a, b, f - i)


func walk_of(name: String) -> Vector2:
	var m: Dictionary = pieces[name]
	var walk: Array = m.get("walk", [0, float(m["size"][0])])
	return Vector2(float(walk[0]), float(walk[1]))


func size_of(name: String) -> Vector2:
	var s: Array = pieces[name]["size"]
	return Vector2(float(s[0]), float(s[1]))

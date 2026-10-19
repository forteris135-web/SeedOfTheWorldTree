class_name TerrainSkin
extends RefCounted
## 지역 지형의 '그림 옷' (그림 조각 기반 지형 — 설명서는 TERRAIN.md).
## data/terrain/<지역>.json (사람이 쓰는 설명: 배율·색·역할별 조각 목록) 과
## art/terrain/<지역>/pieces.json (tools/terrain_cut.gd 가 잰 값: atlas 자리·윗선·걷는 구간) 을 함께 읽는다.
## 그림 옷이 없는 지역(아직 그림이 안 온 곳)은 null → 지형은 옛 방식(TerrainStyle, 코드로 그리기)으로 그린다.
##
## 역할(role) — 조각마다 pieces.json 에 적혀 있고, data 의 "roles" 로 덮어쓰거나 거를 수 있다 (표는 TERRAIN.md 2장).
## 지형 코드(TerrainArt)가 쓰는 역할 — 그림 옷에 그 조각이 있을 때만 켜진다:
##   발 딛는 곳 : branch(떠 있는 가지) · slab(짧은 한쪽 방향 판) · log(한쪽 방향이 아닌 얇은 단 — 굵은 통나무) · ground(큰 윗면 띠)
##   윗면 장식  : bush(가끔 덤불) · prop(띄엄띄엄 세우는 난간·등불 줄 토막)
##   아랫면·옆면: hang(매단 덩굴·등불) · hang_side(옆면에 박는 걸이) · ceiling(천장 들보·관) · wall(높은 옆면의 줄기·기둥) · pillar(세로로 긴 덩어리 전체를 감싸는 기둥)
##   웅덩이     : water(웅덩이 몸통) · wave(수면 물결 띠) — SapPool 이 쓴다
##   가시·금 간 벽: thorn (Thorns) · cracked / cracked_layer / shard (CrackedArt)
## 지형 코드가 쓰지 않는 역할: decor (TerrainProp·Waterwheel·MachineLamp 가 이름으로 꺼내 쓰는 단독 장식), source (몸통 결 재료),
##   fork / slope / arch (수관에 잘라 두었지만 아직 쓰는 코드가 없다).

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


## 지형 노드가 쓸 그림 옷. 고르는 차례:
##  1) override (노드의 style_region) 가 있으면 그 그림 옷
##  2) 조상 Room 의 지역 설명(data/terrain/<지역>.json)에 "room_skins": {방 id: 그림 옷 이름} 이 있고 그 방이 있으면 그 그림 옷
##     (같은 지역 안에서 방마다 다른 시트 — 심연의 달빛 정원·정원의 끝 = abyss_garden, 수액의 호수의 숨은 내리막 = sap_descent)
##  3) 조상 Room 의 region 그림 옷
## 방마다 다른 그림 옷이어도 잿빛 팔레트·정화·음악은 지역 것 그대로다 (Room.region 은 바뀌지 않는다).
static func for_node(node: Node, override := "") -> TerrainSkin:
	if override != "":
		return for_region(override)
	return for_room(TerrainStyle.room_of(node), TerrainStyle.region_of(node))


## 방의 그림 옷 (room_skins 를 따른다). room 이 null 이면 region 그림 옷.
static func for_room(room: Node, region := "") -> TerrainSkin:
	if region == "" and room != null and "region" in room:
		region = str(room.get("region"))
	var skin := for_region(region)
	if skin != null and room != null and "room_id" in room:
		var other := str((skin.data.get("room_skins", {}) as Dictionary).get(str(room.get("room_id")), ""))
		if other != "":
			var s2 := for_region(other)
			if s2 != null:
				return s2
	return skin


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


## 방마다 다른 정화 후 기준 색 (data 의 "room_tint": {방 id: [r, g, b]} — 배경이 밤처럼 어두운 방은 지형을 조금 밝게,
## 낮처럼 환한 방은 조금 어둡게 해 앞 지형이 배경과 갈라져 읽히게). 없으면 tint.
func tint_for(room: Node) -> Color:
	var rt: Dictionary = data.get("room_tint", {})
	if room != null and not rt.is_empty() and "room_id" in room:
		var id := str(room.get("room_id"))
		if rt.has(id):
			var t: Array = rt[id]
			return Color(float(t[0]), float(t[1]), float(t[2]))
	return tint


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

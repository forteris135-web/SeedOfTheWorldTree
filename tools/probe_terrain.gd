extends Node
## 지형 시험. 실행: godot --headless --path . res://tools/probe_terrain.tscn
## (--headless 를 빼고 돌리면 실제 화면 렌더러로 비용을 잰다 — 창이 잠깐 뜬다.)
## 지형은 두 가지 방식이 함께 있다: 그림 조각 지형(TerrainArt, 그림 옷이 있는 지역 — 지금은 방 41곳 전부)과
## 코드로 그리는 옛 지형(TerrainStyle, 그림이 아직 없는 지역). 1)~8) 은 옛 방식 시험이라 TerrainSkin.enabled 를 끄고 돈다.
##  1) TerrainStyle 표: 여섯 지역 모두 필요한 키가 있고, 모르는 지역은 수관으로 떨어진다.
##  2) 지역 찾기·겹: 진짜 방(canopy_01)의 지형이 조상 Room 의 region 을 읽고, 발판·경사에 겹(윗면 빛/장식)이 있고
##     비밀 벽에는 없다. Room 이 없으면 수관, style_region 으로 강제. 기본 이끼 색은 지역 색, 따로 정한 색은 그대로.
##  3) 지역별 장식: 지역마다 가지·덩어리·경사·가시를 그려 그 지역 장식만 나오는지 센다.
##     채굴장 이끼가 수관보다 크게 줄지 않는다. detail=0 이면 옛 수준만. decorate=false 벽은 장식이 없다.
##  4) 상한: 아주 긴 발판(40000px)도 장식 수가 CAP 안이다.
##  5) 비용: 같은 방을 '옛 코드(tools/terrain_legacy_draw.gd, 기준 커밋 그대로)'와 새 코드로 각각 여러 번 다시 그려
##     가장 빠른 값을 비교한다 (방 5곳 합 2배 이내). 정화 연출 한 프레임(테두리 색만 바뀜)은 윗면 빛 겹만 다시 그리고,
##     그 비용이 옛 코드의 '방 전체 다시 그리기'보다 훨씬 작다.
##  6) 색 setter: 같은 값은 안 그림, 테두리 색은 윗면 빛 겹만, 몸통 색은 몸통+장식만.
##  7) 모양 (방 17곳 전부): 몸통 안 장식(결·홈·옹이·녹물·볼트·금속판)은 실루엣 안, 매달린 것은 다른 지형 속에 없고
##     (보스 방 세 곳 입구 선반 EntryLedge 는 아랫면이 바닥에 묻혀 매달린 것이 0개), 얇은 경사 밑 뿌리는 짧고,
##     가시 끝은 옛 높이(1.05h) 안이다.
##  8) 어두운 방(심연 두 곳)에서는 버섯 몇 무리가 실제 빛(PointLight2D)을 낸다. 밝은 방에는 없다.
##  9) 그림 조각 지형 — 그림 옷 지역(수관·마을·채굴장·잠긴 채굴장·심연·수액의 호수)의 방 41곳 전부를 같은 기준으로 (지역마다 다른 허용치는 그림 옷의 params.probe):
##     a) 그림 옷마다 역할별 조각·atlas(2048 이하)·몸통 결·금 간 벽 그림·걷는 구간, 단독 장식(decor)은 지형 역할에 섞이지 않음, room_skins 대상이 있다.
##     b) 방마다: 지형·가시·비밀 벽이 모두 그림, 방에 맞는 그림 옷(room_skins), 충돌 모양 그대로, 한쪽 방향 발판의 빛 점선,
##        드러난 윗면마다 발밑 8px 이 그림으로 90% 넘게 덮이고 그림 윗선(빽빽한 윗면)이 충돌 윗면 −10~+10px (뒤 난간은 probe.rail, 윗면에 선 버섯·등불은 probe.deco 만큼 빼고),
##        드러난 충돌 끝 밖 발 높이에 그림이 OVERHANG_MAX 넘게 남지 않음, 몸통 결은 묶음 맨 아래 겹, 가시 그림이 판정을 덮고 끝이 0.5h 넘게 솟지 않음.
##        (그림 픽셀을 직접 찾아본다: 삼각형 → UV → atlas 알파)
##     c) 그림 옷을 끈 방과 켠 방의 충돌 모양(지형·가시·웅덩이)이 똑같다.
##     d) 가시 네 방향(가로·세로 상자) — 그림 상자·판정 자리. e) 비용: 방에 들어올 때 한 번(평균 60ms 미만), 노드 하나 그리기 호출 4번 이하,
##        정화 연출 프레임에 다시 만들지 않음. f) 잿빛 표(지역마다, 모든 줄 밝기 순서, 옛 셰이더보다 어둡지 않음, 데이터 파일에서).
##     g) 금 간 벽·비밀 천장 단계·부서짐, 기록물 그림. h) 수액 웅덩이: 물 그림·비침·물가·수면·아래끝, 판정 그대로.
##     i) 지역마다 따로 정한 것: 마을 흔들다리 조각, 벽·천장 조각, 심연 room_skins·통나무·어두운 방 작은 빛·장식 달빛풀·잿빛 색, 호수 배경.
## 마지막에 "[probe] 끝: 실패 N" 을 찍고 그 수로 종료한다.

const Legacy := preload("res://tools/terrain_legacy_draw.gd")
const REGIONS := ["canopy", "village", "mine", "abyss", "sap_lake", "flooded_mine"]
const NEED_KEYS := ["moss", "moss_light", "vine", "leaf", "leaf_light", "flower_px", "glint_px", "mushroom_px", "plate_px", "strap_px", "chain_px", "rust_px", "drip_px", "smear_px", "bead_px", "sheen", "root_px", "stone_px", "web_p", "thorn_tip", "thorn_glow", "moss_density", "beard_px", "grass_px", "sprig_px", "bark_lift", "bark_alpha", "ridge_px", "knot_px", "glow_depth"]
const ROOMS := ["canopy_01", "canopy_02", "canopy_03", "canopy_04", "canopy_hidden", "canopy_boss", "village_01", "village_02", "village_shrine", "mine_01", "mine_02", "mine_deep", "mine_boss", "abyss_01", "abyss_02", "moon_garden", "abyss_boss"]
const COST_ROOMS := ["canopy_01", "mine_02", "village_02", "abyss_02", "canopy_boss"]
const REPEAT := 5
## 드러난 충돌 끝 밖 발 높이에 그림이 남아도 되는 거리 (px) — TerrainArt.CLIP_START 남짓
const OVERHANG_MAX := 34.0

var _fail := 0
var _room: Node


class FakeRoom extends Node2D:
	var region := "canopy"


func _check(ok: bool, text: String) -> void:
	print("[probe] %s %s" % ["OK " if ok else "FAIL", text])
	if not ok:
		_fail += 1


func _ready() -> void:
	print("[probe] 지형 디테일 시험 시작 (%s)" % ("화면 없이" if DisplayServer.get_name() == "headless" else "실제 렌더러"))
	var args := OS.get_cmdline_user_args()
	if "--profile" in args:
		# 비용 나눠 보기만: godot --headless --path . res://tools/probe_terrain.tscn -- --profile
		await _profile("canopy_01")
		get_tree().quit(0)
		return
	if "--cost" in args:
		# 비용 비교만 (실제 렌더러로 잴 때 창이 오래 뜨지 않게): ... -- --cost
		TerrainSkin.enabled = false
		await _probe_cost()
		TerrainSkin.enabled = true
		await _probe_art_cost(_art_room_ids())
		print("[probe] 끝: 실패 %d" % _fail)
		get_tree().quit(1 if _fail > 0 else 0)
		return
	if "--art" in args:
		# 그림 조각 지형만: ... -- --art
		await _probe_art()
		print("[probe] 끝: 실패 %d" % _fail)
		get_tree().quit(1 if _fail > 0 else 0)
		return
	# 1)~8) 옛 방식 (그림 옷을 끄고)
	TerrainSkin.enabled = false
	_probe_table()
	await _probe_region_lookup()
	await _probe_region_decor()
	await _probe_caps()
	await _probe_cost()
	await _probe_setters()
	await _probe_geometry()
	await _probe_glow_lights()
	TerrainSkin.enabled = true
	await _probe_art()
	print("[probe] 끝: 실패 %d" % _fail)
	get_tree().quit(1 if _fail > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _load_room(id: String) -> Node:
	var room: Node = load("res://scenes/rooms/%s.tscn" % id).instantiate()
	add_child(room)
	await _frames(3)
	return room


func _free_room(room: Node) -> void:
	room.queue_free()
	await _frames(2)


# ---------- 1) 표 ----------
func _probe_table() -> void:
	for r in REGIONS:
		var st := TerrainStyle.get_style(r)
		var missing := []
		for k in NEED_KEYS:
			if not st.has(k):
				missing.append(k)
		_check(missing.is_empty() and st["region"] == r, "%s 팔레트에 필요한 키가 다 있다 (빠진 것 %s)" % [r, missing])
	_check(TerrainStyle.get_style("nowhere")["region"] == "canopy", "모르는 지역은 수관 팔레트로")
	_check(TerrainStyle.get_style("abyss")["moss"] != TerrainStyle.get_style("canopy")["moss"], "심연 이끼 색이 수관과 다르다")
	_check(TerrainStyle.n_of(1000.0, 0.0, "flower") == 0 and TerrainStyle.n_of(1000.0, 70.0, "flower") == 14 and TerrainStyle.n_of(100000.0, 70.0, "flower") == TerrainStyle.CAP["flower"], "n_of: 0px 는 없음, 1000/70 = 14, 상한에서 멈춤")
	_check(TerrainStyle.CIRCLE_T.size() > 0 and TerrainStyle.STAR_T.size() > 0 and TerrainStyle.CIRCLE_T.size() % 3 == 0, "단위 도형(삼각형 목록)이 준비됨 (원 %d점)" % TerrainStyle.CIRCLE_T.size())


# ---------- 2) 지역 찾기·겹 ----------
func _probe_region_lookup() -> void:
	var room := await _load_room("canopy_01")
	var floor1: Platform = room.get_node("Terrain/Floor1")
	_check(floor1._style["region"] == "canopy", "canopy_01 의 발판이 조상 Room 에서 지역 'canopy' 를 읽음")
	_check(floor1.moss_color == TerrainStyle.get_style("canopy")["moss"], "기본 이끼 색이 지역 색으로 바뀜")
	var thorns: Thorns = room.get_node("Hazards/PitThorns")
	_check(thorns._style["region"] == "canopy", "가시도 지역을 읽음")
	var slope: TerrainPolygon = room.get_node("Terrain/Slope1")
	_check(slope._style["region"] == "canopy", "경사도 지역을 읽음")
	_check(floor1.get_node_or_null("EdgeLayer") is TerrainStyle.Layer and floor1.get_node_or_null("DecorLayer") is TerrainStyle.Layer, "발판에 윗면 빛 겹·장식 겹이 있다")
	_check(slope.get_node_or_null("EdgeLayer") != null and slope.get_node_or_null("DecorLayer") != null, "경사에도 두 겹이 있다")
	# 경사 아래 변의 두께: Slope2(얇은 경사, 외곽 상자 높이는 210)는 60, Slope1(두꺼운 언덕)은 두껍다
	var slope2: TerrainPolygon = room.get_node("Terrain/Slope2")
	var th2 := _bottom_thickness(slope2)
	var th1 := _bottom_thickness(slope)
	_check(absf(th2 - 60.0) < 1.5 and th1 >= TerrainPolygon.THICK_MIN, "경사 두께는 실제 두께로 잰다 (Slope2 %.0f → 얇음, Slope1 %.0f → 두꺼움)" % [th2, th1])
	var sw: Node = room.get_node("Terrain/SecretWall1")
	_check(sw.get_node_or_null("EdgeLayer") == null and sw.get_node_or_null("DecorLayer") == null, "비밀 벽은 자기 그림을 써서 겹이 없다")
	var edge_layer: CanvasItem = floor1.get_node("EdgeLayer")
	_check(edge_layer.use_parent_material, "겹은 부모의 잿빛 재질을 쓴다")
	_check(Platform.draw_calls > 0 and Platform.layer_calls > 0, "headless 에서도 그리기가 돈다 (몸통 %d번, 겹 %d번)" % [Platform.draw_calls, Platform.layer_calls])
	await _free_room(room)
	# Room 없이
	var holder := Node2D.new()
	add_child(holder)
	var p := Platform.new()
	p.size = Vector2(300, 40)
	holder.add_child(p)
	var q := Platform.new()
	q.size = Vector2(300, 40)
	q.style_region = "abyss"
	q.moss_color = Color(0.9, 0.1, 0.1)
	holder.add_child(q)
	await _frames(1)
	_check(p._style["region"] == "canopy", "Room 이 없으면 수관 팔레트")
	_check(q._style["region"] == "abyss", "style_region 으로 강제하면 그 지역 팔레트")
	_check(q.moss_color == Color(0.9, 0.1, 0.1), "따로 정한 이끼 색은 그대로")
	_check(q.vine_color == TerrainStyle.get_style("abyss")["vine"], "정하지 않은 덩굴 색은 지역 색")
	var fake := FakeRoom.new()
	fake.region = "mine"
	add_child(fake)
	var sub := Node2D.new()
	fake.add_child(sub)
	var t := Thorns.new()
	sub.add_child(t)
	await _frames(1)
	_check(t._style["region"] == "mine", "region 속성이 있는 조상(손자여도)에서 지역을 읽음")
	holder.queue_free()
	fake.queue_free()
	await _frames(1)


## 경사의 가장 긴 아래 변의 두께
func _bottom_thickness(poly: TerrainPolygon) -> float:
	var best := 0.0
	var best_len := 0.0
	for i in poly.polygon.size():
		var a := poly.polygon[i]
		var b := poly.polygon[(i + 1) % poly.polygon.size()]
		if TerrainPolygon._is_bottom(b - a) and (b - a).length() > best_len:
			best_len = (b - a).length()
			best = poly._thickness_above(a, b)
	return best


# ---------- 3) 지역별 장식 ----------
## 지역 하나의 지형 세트를 가짜 Room 아래에 만들고 trace 로 센다.
func _draw_set(region: String, detail: int, with_wall := false) -> Dictionary:
	var fake := FakeRoom.new()
	fake.region = region
	add_child(fake)
	var branch := Platform.new()
	branch.size = Vector2(600, 40)
	branch.one_way = true
	branch.position = Vector2(100, 100)
	fake.add_child(branch)
	var block := Platform.new()
	block.size = Vector2(1500, 300)
	block.position = Vector2(100, 400)
	fake.add_child(block)
	if with_wall:
		var wall := Platform.new()
		wall.size = Vector2(100, 1000)
		wall.decorate = false
		wall.position = Vector2(-200, 0)
		fake.add_child(wall)
	var slope := TerrainPolygon.new()
	slope.polygon = PackedVector2Array([Vector2(0, 0), Vector2(500, -150), Vector2(1000, -150), Vector2(1000, 300), Vector2(0, 300)])
	slope.position = Vector2(1800, 400)
	fake.add_child(slope)
	var thorns := Thorns.new()
	thorns.size = Vector2(320, 60)
	thorns.position = Vector2(900, 340)
	fake.add_child(thorns)
	await _frames(1)
	TerrainStyle.detail = detail
	TerrainStyle.trace_counts = {}
	TerrainStyle.trace_points = []
	TerrainStyle.trace = true
	for n in [branch, block, slope]:
		n._redraw_all()
	thorns.queue_redraw()
	await _frames(2)
	TerrainStyle.trace = false
	var counts: Dictionary = TerrainStyle.trace_counts.duplicate()
	fake.queue_free()
	await _frames(1)
	TerrainStyle.detail = 1
	return counts


func _has(c: Dictionary, k: String) -> bool:
	return int(c.get(k, 0)) > 0


func _probe_region_decor() -> void:
	var expect := {
		"canopy": {"yes": ["꽃", "풀", "새싹", "잎묶음", "수염", "뿌리", "옹이", "홈", "결", "윗면빛", "덩굴", "가시", "점선", "돌", "모서리이끼", "옆혹"], "no": ["버섯", "금속판", "띠쇠", "반사빛", "방울", "녹물", "윤기"]},
		"village": {"yes": ["반사빛", "꽃", "풀", "수염", "옹이"], "no": ["버섯", "금속판", "방울", "녹물"]},
		"mine": {"yes": ["금속판", "띠쇠", "볼트", "사슬", "녹물", "옹이", "풀"], "no": ["꽃", "버섯", "방울", "반사빛", "수염", "새싹"]},
		"abyss": {"yes": ["버섯", "뿌리", "수염", "옹이"], "no": ["꽃", "금속판", "방울", "반사빛"]},
		"sap_lake": {"yes": ["방울", "구슬", "윤기", "번짐"], "no": ["꽃", "버섯", "금속판", "녹물"]},
		"flooded_mine": {"yes": ["녹물", "번짐", "금속판", "방울"], "no": ["꽃", "버섯", "반사빛", "윤기", "수염"]},
	}
	var moss := {}
	for r in REGIONS:
		var c := await _draw_set(r, 1)
		moss[r] = int(c.get("이끼", 0))
		var bad := []
		for k in expect[r]["yes"]:
			if not _has(c, k):
				bad.append("없음:" + k)
		for k in expect[r]["no"]:
			if _has(c, k):
				bad.append("있으면 안 됨:" + k)
		var total := 0
		for k in c:
			total += int(c[k])
		_check(bad.is_empty(), "%s 장식: 조각 %d개 %s %s" % [r, total, c, bad])
		_check(int(c.get("잎묶음", 0)) == 2, "%s 가지 양 끝에 잎 묶음 2개 (%d)" % [r, int(c.get("잎묶음", 0))])
	_check(moss["mine"] >= int(moss["canopy"] * 0.8), "채굴장 이끼가 수관만큼 있다 (수관 %d / 채굴장 %d)" % [moss["canopy"], moss["mine"]])
	var mine := TerrainStyle.get_style("mine")
	var mine_moss: Color = mine["moss"]
	_check(mine_moss.get_luminance() > 0.4, "채굴장 이끼가 검은 몸통에서 보이는 밝기 (%.2f)" % mine_moss.get_luminance())
	# 옛 수준
	var c0 := await _draw_set("abyss", 0)
	var extras := ["꽃", "풀", "새싹", "버섯", "옹이", "홈", "뿌리", "돌", "거미줄", "잎묶음", "윗면빛", "수염", "모서리이끼", "옆혹"]
	var leaked := []
	for k in extras:
		if _has(c0, k):
			leaked.append(k)
	_check(leaked.is_empty() and _has(c0, "결") and _has(c0, "이끼") and _has(c0, "점선") and _has(c0, "가시") and _has(c0, "덩굴"), "detail=0: 옛 수준만 (결·이끼·점선·가시·덩굴 있음, 새 장식 없음 %s)" % [leaked])
	# 벽(decorate=false)은 장식이 없다: 떨어진 벽 하나를 더해도 수가 같다
	var with_wall := await _draw_set("canopy", 1, true)
	var without := await _draw_set("canopy", 1, false)
	var same := with_wall.size() == without.size()
	for k in with_wall:
		if int(with_wall[k]) != int(without.get(k, 0)):
			same = false
	_check(same, "decorate=false 벽은 아무 장식도 더하지 않는다")


# ---------- 4) 상한 ----------
func _probe_caps() -> void:
	var fake := FakeRoom.new()
	fake.region = "mine"
	add_child(fake)
	var huge := Platform.new()
	huge.size = Vector2(40000, 400)
	fake.add_child(huge)
	await _frames(1)
	TerrainStyle.trace_counts = {}
	TerrainStyle.trace = true
	huge._redraw_all()
	await _frames(2)
	TerrainStyle.trace = false
	var c: Dictionary = TerrainStyle.trace_counts.duplicate()
	var total := 0
	for k in c:
		total += int(c[k])
	var over := []
	for k in [["이끼", "moss"], ["잎", "leaf"], ["결", "streak"], ["홈", "ridge"], ["옹이", "knot"], ["뿌리", "root"], ["돌", "stone"], ["금속판", "plate"], ["띠쇠", "strap"], ["사슬", "chain"], ["풀", "grass"]]:
		if int(c.get(k[0], 0)) > int(TerrainStyle.CAP[k[1]]):
			over.append(k[0])
	# 녹물은 몸통 녹물(상한 rust) + 금속판마다 2줄 + 띠쇠마다 1줄까지
	if int(c.get("녹물", 0)) > int(TerrainStyle.CAP["rust"]) + 2 * int(TerrainStyle.CAP["plate"]) + int(TerrainStyle.CAP["strap"]):
		over.append("녹물")
	_check(over.is_empty() and total <= 1600, "40000px 덩어리: 장식 %d개, 상한 넘은 것 %s" % [total, over])
	var huge_branch := Platform.new()
	huge_branch.size = Vector2(40000, 40)
	huge_branch.position = Vector2(0, 800)
	fake.add_child(huge_branch)
	await _frames(1)
	TerrainStyle.trace_counts = {}
	TerrainStyle.trace = true
	huge_branch._redraw_all()
	await _frames(2)
	TerrainStyle.trace = false
	total = 0
	for k in TerrainStyle.trace_counts:
		if k != "점선":
			total += int(TerrainStyle.trace_counts[k])
	_check(total <= 1600, "40000px 가지: 점선 빼고 장식 %d개 (1600 이하)" % total)
	fake.queue_free()
	await _frames(1)


# ---------- 5) 비용 ----------
## 방의 그림 지형(발판·경사·가시; 자기 그림을 쓰는 비밀 벽은 뺀다)
func _terrain_nodes(room: Node) -> Array:
	var out := []
	for t in room.get_node("Terrain").get_children():
		if (t is Platform and not (t is SecretWall)) or t is TerrainPolygon:
			out.append(t)
	var hz := room.get_node_or_null("Hazards")
	if hz:
		for t in hz.get_children():
			if t is Thorns:
				out.append(t)
	return out


func _redraw_new(nodes: Array) -> int:
	Platform.draw_usec = 0
	for n in nodes:
		if n is Thorns:
			n.queue_redraw()
		else:
			n._redraw_all()
	await _frames(2)
	return Platform.draw_usec


func _redraw_legacy(stand_ins: Array) -> int:
	Legacy.draw_usec = 0
	for s in stand_ins:
		s.queue_redraw()
	await _frames(2)
	return Legacy.draw_usec


func _probe_cost() -> void:
	var sum_old := 0.0
	var sum_new := 0.0
	var worst := 0.0
	for id in COST_ROOMS:
		var room := await _load_room(id)
		var nodes := _terrain_nodes(room)
		var holder := Node2D.new()
		add_child(holder)
		var stand_ins := []
		for n in nodes:
			var s: Node2D = Legacy.new()
			s.copy_from(n)
			holder.add_child(s)
			stand_ins.append(s)
		await _frames(2)
		# 옛 코드를 연달아 REPEAT 번, 새 코드를 연달아 REPEAT 번 (가장 빠른 값)
		var best_old := INF
		for i in REPEAT:
			best_old = minf(best_old, float(await _redraw_legacy(stand_ins)))
		var best_new := INF
		for i in REPEAT:
			best_new = minf(best_new, float(await _redraw_new(nodes)))
		var ratio := best_new / maxf(best_old, 1.0)
		worst = maxf(worst, ratio)
		sum_old += best_old
		sum_new += best_new
		print("[probe] %s 지형 %d개 다시 그리기: 옛 코드 %.2fms → 새 코드 %.2fms (%.2f배)" % [id, nodes.size(), best_old / 1000.0, best_new / 1000.0, ratio])
		if id == "canopy_01":
			await _probe_purify_frame(room, nodes, best_old)
		holder.queue_free()
		await _free_room(room)
	var total := sum_new / maxf(sum_old, 1.0)
	print("[probe] 방 %d곳 합: 옛 코드 %.2fms → 새 코드 %.2fms (%.2f배, 가장 큰 방 %.2f배)" % [COST_ROOMS.size(), sum_old / 1000.0, sum_new / 1000.0, total, worst])
	if DisplayServer.get_name() == "headless":
		# 화면 없이 돌면 GPU 쪽 일(옛 코드가 도형마다 만들던 정점 버퍼)이 빠져서 옛 코드가 실제보다 약 9배 싸게 나온다
		# (맥 실측: 옛 코드 canopy_01 화면 없이 0.9ms / 실제 렌더러 8.5ms). 그래서 여기서는 스크립트 쪽 비용만 넉넉한 상한으로 지키고,
		# '2배 이내' 판정은 실제 렌더러로 돌 때 한다:  godot --path . res://tools/probe_terrain.tscn -- --cost
		print("[probe] (화면 없이: 스크립트 비용만. 실제 렌더러 비교는 --headless 없이 -- --cost 로)")
		# 화면 없이 재는 값은 참고용 느슨한 상한이다 (통합 뒤 맥에서 3.1~4.2배로 흔들림). 진짜 기준은 실제 렌더러 -- --cost 의 2배 이내(통합 때 0.52배).
		_check(total <= 5.0, "화면 없이 잰 스크립트 비용이 옛 코드의 5배 이내 (%.2f배)" % total)
	else:
		_check(total <= 2.0, "실제 렌더러: 새 그림의 다시 그리기 비용이 옛 코드의 2배 이내 (%.2f배)" % total)
	_check(sum_new / 1000.0 / COST_ROOMS.size() < 30.0, "방 하나 평균 %.1fms < 30ms" % (sum_new / 1000.0 / COST_ROOMS.size()))


## 정화 연출 한 프레임: Room 처럼 모든 지형의 테두리 색만 바꾼다 → 윗면 빛 겹만 다시 그려야 한다.
func _probe_purify_frame(room: Node, nodes: Array, legacy_full: float) -> void:
	await _frames(2)
	var body0 := Platform.draw_calls
	var layer0 := Platform.layer_calls
	var edge0 := Platform.edge_calls
	var best := INF
	for i in REPEAT:
		Platform.draw_usec = 0
		var col := Color(0.62, 0.70, 0.80, 0.55).lerp(Color(1.0, 0.89, 0.62, 0.8), 0.1 + 0.15 * i)
		for t in room.get_node("Terrain").get_children():
			if "edge_color" in t and not (t is SecretWall):
				t.edge_color = col
		await _frames(2)
		best = minf(best, float(Platform.draw_usec))
	var layered := 0
	for n in nodes:
		if not (n is Thorns):
			layered += 1
	var body_redraws := Platform.draw_calls - body0
	var decor_redraws := (Platform.layer_calls - layer0) - (Platform.edge_calls - edge0)
	_check(body_redraws == 0 and decor_redraws == 0, "정화 프레임: 몸통·장식은 다시 안 그린다 (몸통 %d번, 장식 %d번)" % [body_redraws, decor_redraws])
	_check(Platform.edge_calls - edge0 == layered * REPEAT, "정화 프레임: 윗면 빛 겹만 매번 다시 그린다 (%d번 = 지형 %d × %d)" % [Platform.edge_calls - edge0, layered, REPEAT])
	print("[probe] 정화 한 프레임(테두리 색만): 새 코드 %.2fms / 옛 코드는 방 전체를 다시 그렸음 %.2fms" % [best / 1000.0, legacy_full / 1000.0])
	# 화면 없이 재면 스크립트만 재서 비율이 흔들린다(통합 뒤 맥에서 13~42%) → 화면 없을 땐 50%, 실제 렌더러에서는 35% (통합 때 13%)
	var limit := 0.5 if DisplayServer.get_name() == "headless" else 0.35
	_check(best <= legacy_full * limit, "정화 프레임 비용이 옛 코드의 %d%% 이하 (%.0f%%)" % [int(limit * 100.0), best / maxf(legacy_full, 1.0) * 100.0])


# ---------- 6) setter ----------
func _probe_setters() -> void:
	var room := await _load_room("canopy_01")
	var p: Platform = room.get_node("Terrain/Floor1")
	await _frames(2)
	var b0 := Platform.draw_calls
	var l0 := Platform.layer_calls
	var e0 := Platform.edge_calls
	p.color = p.color
	p.edge_color = p.edge_color
	await _frames(2)
	_check(Platform.draw_calls == b0 and Platform.layer_calls == l0, "같은 색을 다시 넣으면 안 그린다 (몸통 %d→%d, 겹 %d→%d)" % [b0, Platform.draw_calls, l0, Platform.layer_calls])
	p.edge_color = Color(0.1, 0.2, 0.3, 0.5)
	await _frames(2)
	_check(Platform.draw_calls == b0 and Platform.edge_calls == e0 + 1 and Platform.layer_calls == l0 + 1, "테두리 색이 바뀌면 윗면 빛 겹만 한 번 그린다 (몸통 +%d, 윗면 빛 +%d, 겹 전체 +%d)" % [Platform.draw_calls - b0, Platform.edge_calls - e0, Platform.layer_calls - l0])
	_check(p.edge_color == Color(0.1, 0.2, 0.3, 0.5), "마지막 값이 남아 있다")
	b0 = Platform.draw_calls
	l0 = Platform.layer_calls
	e0 = Platform.edge_calls
	p.color = Color(0.12, 0.1, 0.08)
	await _frames(2)
	_check(Platform.draw_calls == b0 + 1 and Platform.layer_calls - l0 == 1 and Platform.edge_calls == e0, "몸통 색이 바뀌면 몸통 + 장식 겹만 그린다 (몸통 +%d, 겹 +%d, 윗면 빛 +%d)" % [Platform.draw_calls - b0, Platform.layer_calls - l0, Platform.edge_calls - e0])
	await _free_room(room)


# ---------- 7) 모양 ----------
func _silhouette(n: Node) -> PackedVector2Array:
	if n is Platform:
		var body: PackedVector2Array = n._geo.get("body", PackedVector2Array())
		if body.is_empty():
			var s: Vector2 = n.size
			return PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)])
		return body
	if n is TerrainPolygon:
		return n.polygon
	return PackedVector2Array()


## 방의 Terrain 아래 모든 단단한 지형(전역 좌표): 발판 사각형, 경사 다각형 — 프로브가 따로 계산한다.
func _solids(room: Node) -> Array:
	var out := []
	for t in room.get_node("Terrain").get_children():
		if t is Platform:
			out.append([t, Rect2(t.global_position, t.size)])
		elif t is TerrainPolygon:
			out.append([t, Transform2D(0.0, t.global_position) * (t.polygon as PackedVector2Array)])
	return out


func _inside_other(solids: Array, me: Node, gp: Vector2) -> String:
	for s in solids:
		if s[0] == me:
			continue
		if s[1] is Rect2:
			if (s[1] as Rect2).has_point(gp):
				return s[0].name
		elif Geometry2D.is_point_in_polygon(gp, s[1]):
			return s[0].name
	return ""


func _probe_geometry() -> void:
	var outside := []
	var buried := []
	var entry_hanging := {}
	var slope_roots := []
	var thorn_bad := []
	var inner_total := 0
	var hang_total := 0
	for id in ROOMS:
		var room := await _load_room(id)
		var nodes := _terrain_nodes(room)
		TerrainStyle.trace_points = []
		TerrainStyle.trace = true
		for n in nodes:
			if n is Thorns:
				n.queue_redraw()
			else:
				n._redraw_all()
		await _frames(2)
		TerrainStyle.trace = false
		var solids := _solids(room)
		for rec in TerrainStyle.trace_points:
			var kind: String = rec[0]
			var node: Node = rec[1]
			var p: Vector2 = rec[2]
			if node == null or not is_instance_valid(node):
				continue
			if kind.begins_with("안:"):
				inner_total += 1
				var sil := _silhouette(node)
				if sil.size() >= 3 and not Geometry2D.is_point_in_polygon(p, sil):
					# 경계 위(0.75px 안)는 안으로 친다
					var closest := INF
					for i in sil.size():
						var cp := Geometry2D.get_closest_point_to_segment(p, sil[i], sil[(i + 1) % sil.size()])
						closest = minf(closest, cp.distance_to(p))
					if closest > 0.75:
						outside.append("%s/%s %s (%.0f,%.0f) %.1fpx 밖" % [id, node.name, kind, p.x, p.y, closest])
			elif kind.begins_with("밑:"):
				hang_total += 1
				var gp: Vector2 = (node as Node2D).global_position + p + Vector2(0, 8)
				var other := _inside_other(solids, node, gp)
				if other != "":
					buried.append("%s/%s %s → %s 속" % [id, node.name, kind, other])
				if node.name == "EntryLedge":
					entry_hanging[id] = int(entry_hanging.get(id, 0)) + 1
			elif kind == "뿌리길이" and id == "canopy_01" and node.name == "Slope2":
				slope_roots.append(p)
			elif kind == "가시끝":
				var h: float = (node as Thorns).size.y
				if p.y < h * 0.6 - h * 1.05 - 0.5:
					thorn_bad.append("%s/%s 끝 y=%.1f (h=%.0f)" % [id, node.name, p.y, h])
		await _free_room(room)
	_check(outside.is_empty(), "방 17곳: 몸통 안 장식 %d개가 모두 실루엣 안 (밖 %d개 %s)" % [inner_total, outside.size(), outside.slice(0, 6)])
	_check(buried.is_empty(), "방 17곳: 매달린 것 %d개 중 다른 지형 속에 그린 것 없음 (%d개 %s)" % [hang_total, buried.size(), buried.slice(0, 6)])
	_check(entry_hanging.is_empty(), "보스 방 입구 선반(아랫면이 바닥에 묻힘)에는 매달린 것이 없다 %s" % [entry_hanging])
	var long_root := false
	var thick_flag := false
	for v in slope_roots:
		long_root = long_root or v.x > 64.5
		thick_flag = thick_flag or v.y > 0.5
	_check(not long_root and not thick_flag, "canopy_01 Slope2(두께 60) 밑 뿌리는 얇은 가지 규칙 (뿌리 %d개, 가장 긴 것 %.0fpx)" % [slope_roots.size(), _max_x(slope_roots)])
	_check(thorn_bad.is_empty(), "가시 끝이 옛 높이(1.05h) 안 %s" % [thorn_bad.slice(0, 4)])


func _max_x(arr: Array) -> float:
	var m := 0.0
	for v in arr:
		m = maxf(m, v.x)
	return m


# ---------- 8) 어두운 방의 버섯 빛 ----------
func _count_glow(room: Node) -> int:
	var n := 0
	for l in get_tree().get_nodes_in_group("terrain_glow_light"):
		if room.is_ancestor_of(l):
			n += 1
	return n


func _probe_glow_lights() -> void:
	for id in ["abyss_01", "abyss_02", "abyss_boss", "canopy_01"]:
		var room := await _load_room(id)
		await _frames(3)
		var n := _count_glow(room)
		var dark := bool(room.get("dark"))
		if dark:
			_check(n >= 1 and n <= TerrainStyle.GLOW_LIGHTS_PER_ROOM, "%s(어두운 방): 버섯 빛 %d개 (1~%d)" % [id, n, TerrainStyle.GLOW_LIGHTS_PER_ROOM])
		else:
			_check(n == 0, "%s(밝은 방): 버섯 빛 없음 (%d)" % [id, n])
		await _free_room(room)


# ---------- 비용 나눠 보기 (--profile) ----------
func _measure_parts(nodes: Array) -> Array:
	var best := [INF, INF, INF, INF]
	for r in REPEAT:
		Platform.body_usec = 0
		Platform.edge_usec = 0
		Platform.decor_usec = 0
		var total := float(await _redraw_new(nodes))
		best[0] = minf(best[0], total)
		best[1] = minf(best[1], Platform.body_usec)
		best[2] = minf(best[2], Platform.edge_usec)
		best[3] = minf(best[3], Platform.decor_usec)
	return best


func _profile(id: String) -> void:
	var room := await _load_room(id)
	var nodes := _terrain_nodes(room)
	var holder := Node2D.new()
	add_child(holder)
	var stand_ins := []
	for n in nodes:
		var s: Node2D = Legacy.new()
		s.copy_from(n)
		holder.add_child(s)
		stand_ins.append(s)
	await _frames(2)
	var best_old := INF
	for i in REPEAT:
		best_old = minf(best_old, float(await _redraw_legacy(stand_ins)))
	var b := await _measure_parts(nodes)
	print("[probe] %s 옛 코드 %.2fms / 새 코드 %.2fms = 몸통(가시 포함) %.2f + 윗면 빛 %.2f + 장식 %.2f" % [id, best_old / 1000.0, b[0] / 1000.0, b[1] / 1000.0, b[2] / 1000.0, b[3] / 1000.0])
	var st: Dictionary = TerrainStyle.get_style(TerrainStyle.region_of(nodes[0]))
	for key in ["grass_px", "flower_px", "sprig_px", "beard_px", "root_px", "stone_px", "knot_px", "ridge_px", "glow_depth"]:
		if not st.has(key):
			continue
		var keep = st[key]
		var base := await _measure_parts(nodes)
		st[key] = 0.0
		var r := await _measure_parts(nodes)
		st[key] = keep
		print("[probe]   %s 끄면 %.2fms (−%.2f)" % [key, r[0] / 1000.0, (base[0] - r[0]) / 1000.0])
	var d0 = st["moss_density"]
	var base2 := await _measure_parts(nodes)
	st["moss_density"] = 0.0
	var r2 := await _measure_parts(nodes)
	st["moss_density"] = d0
	print("[probe]   이끼·잎 끄면 %.2fms (−%.2f)" % [r2[0] / 1000.0, (base2[0] - r2[0]) / 1000.0])
	TerrainStyle.detail = 0
	var r3 := await _measure_parts(nodes)
	TerrainStyle.detail = 1
	print("[probe]   detail0 %.2fms = 몸통 %.2f + 윗면 빛 %.2f + 장식 %.2f" % [r3[0] / 1000.0, r3[1] / 1000.0, r3[2] / 1000.0, r3[3] / 1000.0])
	holder.queue_free()
	await _free_room(room)


# ---------- 9) 그림 조각 지형 ----------
## 모든 그림 옷 지역의 방 전부를 한 기준으로 잰다 (방 목록은 scenes/rooms/*.tscn 의 region 으로 찾는다 — 지역을 새로 입혀도 이 시험을 고칠 필요가 없다).
## 지역마다 다른 것은 데이터로: 그림 옷의 params.probe (rail: 뒤 난간이 발 선 위로 솟은 조각의 윗선 허용 px, deco: 윗면에 선 장식(버섯·등불)을 윗선에서 뺄 높이 px).
const ART_REGIONS := ["canopy", "village", "mine", "flooded_mine", "abyss", "sap_lake"]
## 지형 코드가 쓰는 역할 (decor·source 등은 쓰지 않는다 — TERRAIN.md 2장)
const CODE_ROLES := ["branch", "slab", "log", "ground", "bush", "prop", "hang", "hang_side", "ceiling", "wall", "pillar", "water", "wave", "thorn"]
var _atlas_img: Image


func _probe_art() -> void:
	TerrainSkin.clear_cache()
	var ids := _art_room_ids()
	_check(ids.size() == 41, "그림 옷 지역의 방 %d곳 (41)" % ids.size())
	_probe_art_skins()
	await _probe_art_rooms(ids)
	await _probe_art_colliders(ids)
	await _probe_thorn_facing()
	await _probe_art_cost(ids)
	_probe_palette()
	await _probe_cracked()
	await _probe_record()
	await _probe_pools(ids)
	await _probe_region_extras()


## 그림 옷 지역의 방 이름 전부 (지역 순)
func _art_room_ids() -> Array:
	var out := []
	for r in ART_REGIONS:
		out.append_array(_rooms_of_region(r))
	return out


## 그림 옷 이름 전부 (data/terrain/*.json 중 자르기 설명이 있고 켜진 것 — 지역 + 방별 그림 옷)
static func _art_skin_names() -> Array:
	var out := []
	for f in DirAccess.get_files_at("res://data/terrain"):
		if f.ends_with(".json") and not f.begins_with("_") and TerrainSkin.for_region(f.get_basename()) != null:
			out.append(f.get_basename())
	out.sort()
	return out


## a) 그림 옷마다: 역할별 조각, atlas·몸통 결·금 간 벽 그림, 걷는 구간, atlas 크기, 단독 장식(decor)은 지형 역할에 섞이지 않음
func _probe_art_skins() -> void:
	var names := _art_skin_names()
	_check(names.size() >= 8, "그림 옷 %d벌 %s" % [names.size(), names])
	for n in names:
		var skin := TerrainSkin.for_region(n)
		var walkers: Array = skin.list("branch") + skin.list("slab") + skin.list("log")
		_check(not walkers.is_empty() and skin.has_role("ground") and skin.has_role("hang"), "%s 역할: 가지 %d·판 %d·통나무 %d·바닥 %d·매달림 %d·가시 %d·벽 %d·천장 %d·기둥 %d·세움 %d·물 %d" % [n, skin.list("branch").size(), skin.list("slab").size(), skin.list("log").size(), skin.list("ground").size(), skin.list("hang").size(), skin.list("thorn").size(), skin.list("wall").size(), skin.list("ceiling").size(), skin.list("pillar").size(), skin.list("prop").size(), skin.list("water").size()])
		_check(skin.atlas != null and skin.fill != null and skin.fill_v != null and skin.atlas_size.x <= 2048 and skin.atlas_size.y <= 2048, "%s: atlas(%dx%d, 2048 이하)·몸통 결(가로/세로), 금 간 벽 그림 %s (방의 가시·금 간 벽이 그림인지는 b 에서)" % [n, skin.atlas_size.x, skin.atlas_size.y, CrackedArt.can_build(skin)])
		var bad := []
		for p in walkers + skin.list("ground"):
			var w := skin.walk_of(p)
			if w.y - w.x < 60.0:
				bad.append(p)
		var mixed := []
		for role in CODE_ROLES:
			for p in skin.list(role):
				if str(skin.pieces[p].get("role", "")) == "decor":
					mixed.append("%s→%s" % [p, role])
		_check(bad.is_empty() and mixed.is_empty(), "%s: 걷는 조각마다 걷는 구간 60px 넘음 %s, 단독 장식(decor)이 지형 역할에 없음 %s" % [n, bad, mixed])
		for room_id in (skin.data.get("room_skins", {}) as Dictionary):
			var other := str(skin.data["room_skins"][room_id])
			_check(TerrainSkin.for_region(other) != null and _rooms_of_region(n).has(room_id), "%s room_skins: %s → %s (방·그림 옷이 있다)" % [n, room_id, other])
	_check(TerrainSkin.for_region("nowhere") == null, "그림 옷이 없는 지역은 null (옛 방식으로 그린다)")


## b) 방마다: 지형·가시·비밀 벽이 모두 그림, 방에 맞는 그림 옷(room_skins), 충돌 모양 그대로, 발밑 덮임·윗선, 끝 밖 그림, 몸통 결 겹, 한쪽 방향 단서, 가시 그림
func _probe_art_rooms(ids: Array) -> void:
	var not_art := []
	var wrong_skin := []
	var collider_bad := []
	var feet_bad := []
	var top_bad := []
	var dash_bad := []
	var tops_checked := 0
	var tops_all: Array = []
	var worst_cov := 1.0
	var worst_name := ""
	var ends_checked := 0
	var over_bad := []
	var over_all := []
	var fill_bad := []
	var tip_bad := []
	var tip_worst := 0.0
	var depth_bad := []
	var verbose := "--verbose" in OS.get_cmdline_user_args()
	for id in ids:
		var room := await _load_room(id)
		var want := TerrainSkin.for_room(room)
		depth_bad.append_array(_depth_issues(id, room))
		var solids := _solids(room)
		var bounds: Rect2 = room.get("bounds")
		for t in room.get_node("Terrain").get_children():
			var nm := "%s/%s" % [id, t.name]
			var art_n = t.get("_art")
			if t is SecretWall or t is CrackedWall:
				var cr = t.get("_crack")
				if cr == null and not (t.get("_broken") == true):
					not_art.append(nm)
				elif cr != null and (cr as CrackedArt).skin != want:
					wrong_skin.append("%s(%s)" % [nm, (cr as CrackedArt).skin.region])
				continue
			if (t is Platform or t is TerrainPolygon) and not t.is_art():
				not_art.append(nm)
				continue
			if not (art_n is TerrainArt):
				continue
			var art: TerrainArt = art_n
			if str(t.get("style_region")) == "" and art.skin != want:
				wrong_skin.append("%s(%s, 방은 %s)" % [nm, art.skin.region, want.region])
			# 몸통 결은 부모 묶음 맨 아래 겹 (나중 형제의 몸통이 앞 형제의 끝 조각을 덮지 않게)
			if not art.fill_in_layer():
				fill_bad.append(nm)
			# 앞뒤 가르기: 앞 지형 재질, 조각이 있으면 뒤 그림자
			if t.material != FORE_MAT:
				depth_bad.append("%s 앞 지형 재질 아님" % nm)
			if (art._bufs[TerrainArt.BUF_ATLAS]["idx"] as PackedInt32Array).size() >= 3 and not art.has_shadow():
				depth_bad.append("%s 뒤 그림자 없음" % nm)
			# 한쪽 방향 발판의 빛 점선 단서
			if t is Platform and t.one_way and (art._bufs[TerrainArt.BUF_PLAIN]["idx"] as PackedInt32Array).size() < 6:
				dash_bad.append(nm)
			# 충돌 모양
			if t is Platform:
				var cs: CollisionShape2D = _first_shape(t)
				if not (cs != null and cs.shape is RectangleShape2D and (cs.shape as RectangleShape2D).size == t.size and cs.position == t.size / 2.0 and cs.one_way_collision == bool(t.one_way)):
					collider_bad.append(nm)
			elif t is TerrainPolygon:
				var cp: CollisionPolygon2D = null
				for c in t.get_children():
					if c is CollisionPolygon2D:
						cp = c
				if cp == null or cp.polygon != t.polygon:
					collider_bad.append(nm)
			var skin := art.skin
			var deco := float(skin.param("probe", "deco", 0.0))
			var rail := maxf(float(skin.param("probe", "rail", 10.0)), 10.0)
			for seg in _top_segments(t):
				# 드러난 끝 밖 발 높이에 남는 그림 (서지 못하는 자리가 발판처럼 보이지 않게)
				for side in [-1.0, 1.0]:
					var far := _overhang(t, art, seg[0] if side < 0.0 else seg[1], side, solids, bounds)
					if far < 0.0:
						continue
					ends_checked += 1
					over_all.append([far, "%s %s" % [nm, "왼끝" if side < 0.0 else "오른끝"]])
					if far > OVERHANG_MAX:
						over_bad.append("%s %s %.0fpx" % [nm, "왼끝" if side < 0.0 else "오른끝", far])
				# 발 딛는 자리
				var r := _feet_check(t, seg[0], seg[1], solids, bounds, 140.0 if deco > 0.0 else 60.0)
				if r.is_empty():
					continue
				tops_checked += 1
				if float(r["cov"]) < worst_cov:
					worst_cov = r["cov"]
					worst_name = nm
				if float(r["cov"]) < 0.9:
					feet_bad.append("%s 덮임 %.0f%%" % [nm, float(r["cov"]) * 100.0])
				# 발 딛는 선을 손으로 정한 조각(난간·등불이 솟은 다리 — pieces.json 의 line)은 바닥판이 충돌 윗면 2px 아래부터 80% 넘게 차 있는지
				if art.pick != "" and bool(skin.pieces.get(art.pick, {}).get("line", false)):
					if float(r["cov2"]) < 0.8:
						top_bad.append("%s 바닥판 %.0f%%" % [nm, float(r["cov2"]) * 100.0])
					continue
				# 윗선: 윗면에 선 장식(deco px 넘게 솟은 곳)은 빼고 잰다 — 장식이 윗면의 3/4 을 넘으면 실패 (그림 전체가 뜬 것과 구분)
				var diffs: Array = r["diffs"]
				var vals := diffs.filter(func(v): return v >= -deco) if deco > 0.0 else diffs
				var med: float = vals[vals.size() / 2] if not vals.is_empty() else -99.0
				tops_all.append(med)
				if verbose:
					print("[probe]   %s 윗선 %+.0fpx 덮임 %.0f%%" % [nm, med, float(r["cov"]) * 100.0])
				if vals.size() < maxi(4, int(diffs.size() * 0.25)) or med < -rail or med > 10.0:
					top_bad.append("%s 윗선 %+.0fpx (허용 −%.0f, 장식 뺀 %d/%d)" % [nm, med, rail, vals.size(), diffs.size()])
		var hz := room.get_node_or_null("Hazards")
		if hz:
			for th in hz.get_children():
				if not (th is Thorns):
					continue
				var tart = th.get("_art")
				if tart == null:
					not_art.append("%s/%s" % [id, th.name])
					continue
				var cs2: CollisionShape2D = _first_shape(th)
				var hr := Thorns.hit_rect(th.size, th.facing_dir)
				var old_rect := Vector2(th.size.x - 8, th.size.y * 0.7)
				if cs2 == null or (cs2.shape as RectangleShape2D).size != hr.size or cs2.position != hr.get_center() or (th.facing_dir == 0 and hr.size != old_rect):
					collider_bad.append("%s/%s(가시)" % [id, th.name])
				# 가시 끝 높이: 그림 끝이 상자 위로 0.5h 넘게 솟지 않는다 (판정보다 훨씬 높은 가시를 발이 지나가 보이지 않게)
				var ab := _art_bounds(tart)
				var lh := Thorns.frame_size(th.size, th.facing_dir)
				var allowed := _thorn_allowed(th.size, th.facing_dir, float((tart as TerrainArt).skin.param("thorn", "sink", 10.0)))
				tip_worst = maxf(tip_worst, -ab.position.y / lh.y if th.facing_dir == 0 else 0.0)
				if not allowed.encloses(ab) or ab.intersection(hr).get_area() < hr.get_area() * 0.95:
					tip_bad.append("%s/%s 그림 %s 판정 %s" % [id, th.name, ab, hr])
		await _free_room(room)
	_check(not_art.is_empty(), "방 %d곳: 지형·가시·비밀 벽·금 간 벽이 모두 그림 조각 (아닌 것 %s)" % [ids.size(), not_art.slice(0, 8)])
	_check(wrong_skin.is_empty(), "방마다 맞는 그림 옷 (지역 그림 옷, room_skins 가 있으면 그것; 틀린 것 %s)" % [wrong_skin.slice(0, 6)])
	_check(collider_bad.is_empty(), "방 %d곳: 충돌 모양이 그대로 (다른 것 %s)" % [ids.size(), collider_bad.slice(0, 8)])
	_check(dash_bad.is_empty(), "한쪽 방향 발판마다 빛 점선 단서 (없는 것 %s)" % [dash_bad.slice(0, 6)])
	_check(tops_checked > 250 and feet_bad.is_empty(), "드러난 윗면 %d곳: 발밑(충돌 윗면 8px 아래)이 그림으로 90%% 넘게 덮임 (가장 낮은 %s %.0f%%) %s" % [tops_checked, worst_name, worst_cov * 100.0, feet_bad.slice(0, 6)])
	tops_all.sort()
	_check(top_bad.is_empty(), "드러난 윗면 %d곳: 그림 윗선(빽빽한 윗면)이 충돌 윗면 −10~+10px (뒤 난간 조각은 params.probe.rail, 선 장식은 params.probe.deco 만큼 뺌; 중앙값 %+.0fpx, 범위 %+.0f~%+.0f) %s" % [tops_checked, tops_all[tops_all.size() / 2] if not tops_all.is_empty() else 0.0, tops_all[0] if not tops_all.is_empty() else 0.0, tops_all[-1] if not tops_all.is_empty() else 0.0, top_bad.slice(0, 6)])
	over_all.sort_custom(func(x, y): return x[0] > y[0])
	if verbose:
		for o in over_all.slice(0, 12):
			print("[probe]   끝 밖 그림 %3.0fpx  %s" % [o[0], o[1]])
	_check(ends_checked > 250 and over_bad.is_empty(), "드러난 충돌 끝 %d곳: 끝 밖 발 높이(윗면 +2·+8px)에 그림이 %.0fpx 넘게 남지 않는다 (가장 긴 %s) %s" % [ends_checked, OVERHANG_MAX, ("%.0fpx %s" % [over_all[0][0], over_all[0][1]]) if not over_all.is_empty() else "-", over_bad.slice(0, 6)])
	_check(fill_bad.is_empty(), "몸통 결은 지형 묶음 맨 아래 겹에 그린다 (모든 몸통 → 모든 조각; 아닌 것 %s)" % [fill_bad.slice(0, 6)])
	_check(tip_bad.is_empty(), "방의 가시: 그림이 판정을 덮고, 끝이 상자 위로 0.5h 넘게 솟지 않는다 (가장 높은 %.2fh) %s" % [tip_worst, tip_bad.slice(0, 4)])
	_check(depth_bad.is_empty(), "앞뒤 가르기 (방 %d곳): 배경 그림·배경 장식은 배경 재질, 지형은 앞 지형 재질 + 뒤 그림자, 웅덩이는 그림자 없음, 방의 값이 그림 옷 데이터대로이고 범위 안 %s" % [ids.size(), depth_bad.slice(0, 6)])


const FAR_MAT := preload("res://shaders/ash_purify_far.tres")
const FORE_MAT := preload("res://shaders/ash_purify_fore.tres")
const SHADOW_MAT := preload("res://shaders/terrain_shadow.tres")


## 앞뒤 가르기 (TERRAIN.md 5장) — 방 하나: 배경 그림(ArtBackdrop)·배경 장식(TerrainProp·Waterwheel)은 배경 재질, 웅덩이 물은 그림자 없음,
## Purity 가 넣은 값 = 그 방의 그림 옷 데이터(TerrainSkin.depth_of), 값의 범위 (배경은 정화 전에 더 흐리고 대비가 낮다, 앞 지형은 너무 어둡지 않다).
func _depth_issues(id: String, room: Node) -> Array:
	var out := []
	for n in room.find_children("*", "Sprite2D", true, false):
		if n.get_script() == preload("res://scripts/world/art_backdrop.gd") and n.material != FAR_MAT:
			out.append("%s/%s 배경 그림 재질 아님" % [id, n.name])
	for n in room.find_children("*", "Node2D", true, false):
		if (n is TerrainProp or n is Waterwheel) and n.material != FAR_MAT:
			out.append("%s/%s 배경 장식 재질 아님" % [id, n.name])
	for pool in room.find_children("*", "SapPool", true, false):
		for a in pool.find_children("*", "TerrainArt", true, false):
			if (a as TerrainArt).has_shadow():
				out.append("%s/%s 물이 그림자를 드리운다" % [id, pool.name])
	var spec := TerrainSkin.depth_of(room)
	var d: Dictionary = Purity.depth
	if not spec.has("ash") or not spec.has("alive"):
		out.append("%s 그림 옷 데이터에 depth 가 없다" % id)
		return out
	for st in ["ash", "alive"]:
		for k in (spec[st] as Dictionary):
			if str(d[st].get(k)) != str(spec[st][k]):
				out.append("%s %s.%s 이 %s ≠ 데이터 %s" % [id, st, k, d[st].get(k), spec[st][k]])
	var a: Dictionary = d["ash"]
	var b: Dictionary = d["alive"]
	if not (float(a["haze"]) >= float(b["haze"]) and float(a["contrast"]) <= float(b["contrast"]) and float(a["contrast"]) <= 1.0):
		out.append("%s 배경: 정화 전이 더 흐리고 대비가 낮아야 (흐림 %.2f/%.2f, 대비 %.2f/%.2f)" % [id, a["haze"], b["haze"], a["contrast"], b["contrast"]])
	for st in [a, b]:
		if float(st["fore_value"]) < 0.8 or float(st["fore_value"]) > 1.15 or float(st["shadow"]) < 0.0 or float(st["shadow"]) > 1.0 or float(st["haze"]) > 0.5:
			out.append("%s 범위 밖 (앞 지형 밝기 %.2f, 그림자 %.2f, 흐림 %.2f)" % [id, st["fore_value"], st["shadow"], st["haze"]])
	if FAR_MAT.get_shader_parameter("haze") != Vector2(float(a["haze"]), float(b["haze"])) or SHADOW_MAT.get_shader_parameter("strength") != Vector2(float(a["shadow"]), float(b["shadow"])) or FORE_MAT.get_shader_parameter("value") != Vector2(float(a["fore_value"]), float(b["fore_value"])):
		out.append("%s 재질 값이 방의 값과 다르다" % id)
	return out


## c) 충돌은 그대로: 그림 옷을 끈 채(옛 방식) 읽은 방과 켠 채 읽은 방의 지형·가시·웅덩이 충돌 모양·자리가 똑같다
func _probe_art_colliders(ids: Array) -> void:
	var bad := []
	var total := 0
	for id in ids:
		TerrainSkin.enabled = false
		var r0 := await _load_room(id)
		var s0 := _collider_sig(r0)
		await _free_room(r0)
		TerrainSkin.enabled = true
		var r1 := await _load_room(id)
		var s1 := _collider_sig(r1)
		await _free_room(r1)
		total += s1.size()
		if s0 != s1:
			bad.append("%s (옛 %d개 / 그림 %d개)" % [id, s0.size(), s1.size()])
			if "--verbose" in OS.get_cmdline_user_args():
				for i in mini(s0.size(), s1.size()):
					if s0[i] != s1[i]:
						print("[probe]   옛  %s\n[probe]   그림 %s" % [s0[i], s1[i]])
	_check(total > 400 and bad.is_empty(), "방 %d곳 충돌 모양 %d개: 그림 옷을 끈 방과 켠 방이 똑같다 (다른 방 %s)" % [ids.size(), total, bad])


## 지형·가시·웅덩이 아래 모든 충돌 모양의 (부모 이름, 종류, 전역 자리, 모양 값, 한쪽 방향) 목록
func _collider_sig(room: Node) -> Array:
	var out := []
	for group_name in ["Terrain", "Hazards"]:
		var grp := room.get_node_or_null(group_name)
		if grp:
			_collect_sig(grp, out)
	for c in room.get_children():
		if c is SapPool:
			_collect_sig(c, out)
	out.sort()
	return out


func _collect_sig(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is CollisionShape2D:
			var cs := c as CollisionShape2D
			var desc := ""
			if cs.shape is RectangleShape2D:
				desc = "rect %s" % [(cs.shape as RectangleShape2D).size]
			elif cs.shape is ConvexPolygonShape2D:
				desc = "convex %s" % [(cs.shape as ConvexPolygonShape2D).points]
			elif cs.shape != null:
				desc = cs.shape.get_class()
			out.append("%s|shape|%s|%s|ow=%s|dis=%s" % [_sig_name(n), cs.global_position.round(), desc, cs.one_way_collision, cs.disabled])
		elif c is CollisionPolygon2D:
			var cp := c as CollisionPolygon2D
			out.append("%s|poly|%s|%s|ow=%s" % [_sig_name(n), cp.global_position.round(), cp.polygon, cp.one_way_collision])
		_collect_sig(c, out)


## 부모 이름 (자동으로 붙은 '@Area2D@123' 같은 이름은 종류만)
static func _sig_name(n: Node) -> String:
	var s := str(n.name)
	return n.get_class() if s.begins_with("@") else s


## 윗면 끝 e(노드 좌표)가 드러난 끝이면 그 밖 발 높이(윗면 +2·+8px)에서 이 노드의 조각 그림(알파 0.5 넘음)이 이어지는 거리(px),
## 드러난 끝이 아니면(다른 지형이 이어지거나 방 밖) −1.
func _overhang(t: Node2D, art: TerrainArt, e: Vector2, side: float, solids: Array, bounds: Rect2) -> float:
	var ge := t.global_position + e
	var probe := ge + Vector2(side * 6.0, 6.0)
	if _inside_other(solids, null, probe) != "" or not bounds.has_point(probe):
		return -1.0
	var near: Array = []
	for tr in _atlas_tris(art):
		var bb: Rect2 = tr[3]
		if bb.end.y >= e.y - 2.0 and bb.position.y <= e.y + 10.0 and bb.end.x >= e.x - 270.0 and bb.position.x <= e.x + 270.0:
			near.append(tr)
	var far := 0.0
	var d := 6.0
	while d <= 260.0:
		var p := e + Vector2(side * d, 8.0)
		if _inside_other(solids, null, t.global_position + p) != "":
			break
		if maxf(_alpha_at(near, p), _alpha_at(near, p + Vector2(0, -6))) > 0.5:
			far = d
		d += 4.0
	return far


## 조각 그림이 그려지는 상자 (노드 좌표, 거의 투명한 꼭짓점은 뺀다)
func _art_bounds(art: TerrainArt) -> Rect2:
	if art == null:
		return Rect2()
	var b: Dictionary = art._bufs[TerrainArt.BUF_ATLAS]
	var pts: PackedVector2Array = b["pts"]
	var cols: PackedColorArray = b["cols"]
	var xf := art.transform
	var out := Rect2()
	var first := true
	for i in pts.size():
		if cols[i].a < 0.02:
			continue
		var q := xf * pts[i]
		if first:
			out = Rect2(q, Vector2.ZERO)
			first = false
		else:
			out = out.expand(q)
	return out


## 가시 그림이 있어도 되는 상자 (노드 좌표): 길이 쪽 양 끝 26px, 밑동 쪽 sink+4px, 끝 쪽 0.5H 까지.
func _thorn_allowed(sz: Vector2, facing: int, sink: float) -> Rect2:
	var lh := Thorns.frame_size(sz, facing)
	var local := Rect2(-26.0, -lh.y * 0.5, lh.x + 52.0, lh.y * 1.5 + sink + 4.0)
	var xf := Thorns.frame_of(sz, facing)
	var a := xf * local.position
	var b := xf * local.end
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())


func _first_shape(n: Node) -> CollisionShape2D:
	for c in n.get_children():
		if c is CollisionShape2D:
			return c
	return null


## 지형의 윗면들 (노드 기준 [a, b], 왼→오). 장식을 끈 덩어리(벽·천장·가시 구덩이 바닥 — 서는 곳이 아님)는 뺀다.
func _top_segments(t: Node) -> Array:
	if t is Platform:
		if not t.decorate and not t._is_thin():
			return []
		return [[Vector2.ZERO, Vector2(t.size.x, 0)]]
	var out := []
	var poly: PackedVector2Array = t.polygon
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		if TerrainArt._edge_kind(b - a) == 0:
			out.append([a, b])
	return out


## 윗면 a→b 의 드러난 자리마다: 발밑(8px·2px 아래)이 조각 그림으로 덮였는가, 그림 윗선(빽빽한 윗면)이 충돌 윗면에서 얼마나 떨어졌나.
## scan: 윗선을 찾기 시작하는 높이 (충돌 윗면 위 px — 윗면에 선 장식까지 보려면 크게).
## 돌려주는 값: {cov, cov2: 덮인 비율, diffs: 윗선 차이들(px, 위가 −, 정렬됨)} — 드러난 자리가 없으면 빈 사전.
func _feet_check(t: Node2D, a: Vector2, b: Vector2, solids: Array, bounds: Rect2, scan := 60.0) -> Dictionary:
	var art: TerrainArt = t.get("_art")
	if art == null:
		return {}
	var tris := _atlas_tris(art)
	var n := maxi(2, int((b.x - a.x) / 16.0))
	var hits := 0
	var hits2 := 0
	var total := 0
	var diffs: Array = []
	for i in n:
		var x := lerpf(a.x, b.x, (i + 0.5) / n)
		if x - a.x < 14.0 or b.x - x < 14.0:
			continue   # 끝 14px 는 둥근 끝이라 뺀다
		var y := lerpf(a.y, b.y, (x - a.x) / maxf(b.x - a.x, 0.001))
		var gp := t.global_position + Vector2(x, y)
		if not bounds.has_point(gp + Vector2(0, -8)) or _inside_other(solids, t, gp + Vector2(0, -10)) != "":
			continue   # 다른 지형에 덮인 윗면 (서 있을 수 없는 곳)
		total += 1
		# 이 세로줄에 걸친 삼각형만 고른다
		var col: Array = []
		for tr in tris:
			var bb: Rect2 = tr[3]
			if x >= bb.position.x and x <= bb.end.x and bb.end.y >= y - scan and bb.position.y <= y + 60.0:
				col.append(tr)
		if _alpha_at(col, Vector2(x, y + 8.0)) > 0.5:
			hits += 1
		if _alpha_at(col, Vector2(x, y + 2.0)) > 0.5:
			hits2 += 1
		elif "--verbose" in OS.get_cmdline_user_args():
			print("[probe]   발밑 빔: %s x=%.0f/%.0f" % [t.name, x - a.x, b.x - a.x])
		# 그림 윗선: 위 scan px 에서 아래로 내려가며 처음으로 12px 이어서 불투명한 곳 (자르기 도구의 '빽빽한 윗면'과 같은 기준)
		var run := 0
		var yy := y - scan
		while yy < y + 60.0:
			if _alpha_at(col, Vector2(x, yy)) > 0.5:
				run += 1
				if run >= 6:
					diffs.append(yy - 10.0 - y)
					break
			else:
				run = 0
			yy += 2.0
	if total == 0:
		return {}
	diffs.sort()
	return {"cov": float(hits) / total, "cov2": float(hits2) / total, "diffs": diffs}


## 조각(atlas) 삼각형 목록: [[p0,p1,p2],[uv0,uv1,uv2],[a0,a1,a2], 상자] (노드 기준)
func _atlas_tris(art: TerrainArt) -> Array:
	_use_atlas(art.skin.region)   # 알파는 그 지형의 그림 옷 atlas 에서 읽는다
	var b: Dictionary = art._bufs[TerrainArt.BUF_ATLAS]
	var pts: PackedVector2Array = b["pts"]
	var uvs: PackedVector2Array = b["uvs"]
	var cols: PackedColorArray = b["cols"]
	var idx: PackedInt32Array = b["idx"]
	var out := []
	var off := art.position
	var i := 0
	while i + 2 < idx.size():
		var ia := idx[i]
		var ib := idx[i + 1]
		var ic := idx[i + 2]
		var q := PackedVector2Array([pts[ia] + off, pts[ib] + off, pts[ic] + off])
		var bb := Rect2(q[0], Vector2.ZERO).expand(q[1]).expand(q[2])
		out.append([q, PackedVector2Array([uvs[ia], uvs[ib], uvs[ic]]), [cols[ia].a, cols[ib].a, cols[ic].a], bb])
		i += 3
	return out


## 그림 옷 atlas 그림 (알파 읽기용, 그림 옷마다 한 번 읽어 둔다)
var _atlas_imgs := {}
func _use_atlas(region: String) -> void:
	if not _atlas_imgs.has(region):
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://art/terrain/%s/atlas.png" % region))
		img.convert(Image.FORMAT_RGBA8)
		_atlas_imgs[region] = img
	_atlas_img = _atlas_imgs[region]


## 그 자리에 그려지는 조각 그림의 알파 (겹친 삼각형 중 가장 진한 것)
func _alpha_at(tris: Array, p: Vector2) -> float:
	var best := 0.0
	var w := _atlas_img.get_width()
	var h := _atlas_img.get_height()
	for tr in tris:
		var bb: Rect2 = tr[3]
		if p.y < bb.position.y or p.y > bb.end.y:
			continue
		var q: PackedVector2Array = tr[0]
		var bc := _bary(p, q[0], q[1], q[2])
		if bc.x < -0.001 or bc.y < -0.001 or bc.z < -0.001:
			continue
		var uvp: PackedVector2Array = tr[1]
		var uv := uvp[0] * bc.x + uvp[1] * bc.y + uvp[2] * bc.z
		var va: Array = tr[2]
		var vcol := float(va[0]) * bc.x + float(va[1]) * bc.y + float(va[2]) * bc.z
		var px := clampi(int(uv.x * w), 0, w - 1)
		var py := clampi(int(uv.y * h), 0, h - 1)
		best = maxf(best, _atlas_img.get_pixel(px, py).a * vcol)
		if best > 0.95:
			break
	return best


static func _bary(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 0.000001:
		return Vector3(-1, -1, -1)
	var v := (v2.x * v1.y - v1.x * v2.y) / den
	var w := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - v - w, v, w)


## d) 가시 방향 (위·아래·왼쪽·오른쪽): 옆을 향하면 가시가 세로로 늘어서고, 판정도 같은 쪽(밑동 쪽 70%)에 놓인다.
## 그림 상자가 판정을 덮고, 노드 상자에서 크게 벗어나지 않는지(길이 쪽 26px, 밑동 쪽 sink+4, 끝 쪽 0.5H) 잰다.
func _probe_thorn_facing() -> void:
	var fake := FakeRoom.new()
	fake.region = "canopy"
	add_child(fake)
	var skin := TerrainSkin.for_region("canopy")
	var sink := float(skin.param("thorn", "sink", 10.0)) if skin else 10.0
	var cases := [[Vector2(240, 60), 0], [Vector2(240, 60), 1], [Vector2(60, 240), 2], [Vector2(60, 240), 3], [Vector2(300, 60), 1], [Vector2(60, 300), 2], [Vector2(60, 300), 3], [Vector2(300, 60), 3]]
	var made := []
	for i in cases.size():
		var t := Thorns.new()
		t.size = cases[i][0]
		t.facing_dir = cases[i][1]
		t.position = Vector2(0, 500 * i)
		fake.add_child(t)
		made.append(t)
	await _frames(1)
	var bad := []
	for i in made.size():
		var t: Thorns = made[i]
		var art: TerrainArt = t.get("_art")
		var tag := "%s 방향%d" % [t.size, t.facing_dir]
		if art == null or art.triangle_count() == 0:
			bad.append(tag + " 그림 없음")
			continue
		var cs := _first_shape(t)
		var hr := Thorns.hit_rect(t.size, t.facing_dir)
		if cs == null or (cs.shape as RectangleShape2D).size != hr.size or cs.position != hr.get_center():
			bad.append(tag + " 판정 자리 다름")
			continue
		# 판정은 밑동 쪽 면에 붙는다
		var base_ok := false
		match t.facing_dir:
			0: base_ok = is_equal_approx(hr.end.y, t.size.y)
			1: base_ok = is_zero_approx(hr.position.y)
			2: base_ok = is_equal_approx(hr.end.x, t.size.x)
			3: base_ok = is_zero_approx(hr.position.x)
		var ab := _art_bounds(art)
		var allowed := _thorn_allowed(t.size, t.facing_dir, sink)
		var cover := ab.intersection(hr).get_area() / maxf(hr.get_area(), 1.0)
		if not base_ok or not allowed.encloses(ab) or cover < 0.95:
			bad.append("%s 그림 %s 판정 %s 덮음 %.0f%%" % [tag, ab, hr, cover * 100.0])
	_check(bad.is_empty(), "가시 네 방향(가로·세로 상자 %d가지): 그림이 판정을 덮고 상자 둘레를 벗어나지 않음, 판정은 밑동 쪽 %s" % [cases.size(), bad.slice(0, 4)])
	# 옛 방식(코드로 그리기)도 같은 틀로 돌려 그린다 — 오류 없이 그려지는지만
	TerrainSkin.enabled = false
	var legacy := Thorns.new()
	legacy.size = Vector2(60, 240)
	legacy.facing_dir = 2
	fake.add_child(legacy)
	await _frames(2)
	TerrainSkin.enabled = true
	var lcs := _first_shape(legacy)
	_check(legacy.get("_art") == null and lcs != null and lcs.position == Thorns.hit_rect(legacy.size, 2).get_center(), "옛 방식 가시도 방향대로 판정 (왼쪽을 향하면 오른쪽 면에)")
	fake.queue_free()
	await _frames(1)


## e) 비용: 만들기 시간·삼각형·그리기 호출, 정화 프레임에 다시 안 만들기
func _probe_art_cost(ids: Array) -> void:
	var sum := 0.0
	var worst := 0.0
	var worst_id := ""
	var tri_max := 0
	var calls_bad := []
	for id in ids:
		TerrainArt.build_usec = 0
		TerrainArt.tri_count = 0
		var room := await _load_room(id)
		var ms := TerrainArt.build_usec / 1000.0
		sum += ms
		if ms > worst:
			worst = ms
			worst_id = id
		tri_max = maxi(tri_max, TerrainArt.tri_count)
		for t in room.get_node("Terrain").get_children():
			var art: TerrainArt = t.get_node_or_null("Art")
			if art:
				var bufs := 0
				for bb in art._bufs:
					if (bb["idx"] as PackedInt32Array).size() >= 3:
						bufs += 1
				if bufs > 4:
					calls_bad.append("%s/%s" % [id, t.name])
		if id == "canopy_01":
			# 정화 연출 프레임: Room 이 테두리 색·몸통 색을 바꿔도 다시 만들지 않는다
			var b0 := TerrainArt.build_count
			var d0 := Platform.draw_calls
			var l0 := Platform.layer_calls
			for i in 6:
				room._on_purity_progress(i / 5.0)
				await _frames(1)
			_check(TerrainArt.build_count == b0 and Platform.draw_calls == d0 and Platform.layer_calls == l0, "정화 연출 프레임: 그림 지형을 다시 만들지·그리지 않는다 (만들기 +%d, 옛 그리기 +%d/+%d)" % [TerrainArt.build_count - b0, Platform.draw_calls - d0, Platform.layer_calls - l0])
		print("[probe] %s 그림 지형 만들기 %.1fms, 삼각형 %d" % [id, ms, TerrainArt.tri_count])
		await _free_room(room)
	var avg := sum / maxf(ids.size(), 1)
	_check(avg < 60.0, "그림 지형 만들기: 방 하나 평균 %.1fms < 60ms (가장 긴 %s %.1fms)" % [avg, worst_id, worst])
	_check(tri_max < 40000, "방 하나 삼각형 %d개 < 40000 (아이폰 11 Pro 에 넉넉함)" % tri_max)
	_check(calls_bad.is_empty(), "노드 하나에 그리기 호출 4번 이하 %s" % [calls_bad])


## f) 팔레트 (잿빛 표): 지역마다 64×8, 무채색 줄 밝기 순서, 옛 셰이더보다 어둡지 않음, 데이터 파일에서
func _probe_palette() -> void:
	for r in REGIONS:
		var tex: ImageTexture = Purity.ash_lut(r)
		var ok := tex != null and tex.get_width() == Purity.LUT_W and tex.get_height() == Purity.LUT_ROWS
		var img := tex.get_image() if tex else null
		var mono := true
		var not_dark := true
		if img:
			for row in Purity.LUT_ROWS:
				var prev := -1.0
				for x in Purity.LUT_W:
					var l := img.get_pixel(x, row).get_luminance()
					if l < prev - 0.01:
						mono = false
					prev = l
			# 옛 셰이더: ((lum - 0.5) * 0.7 + 0.5) * 색조 * 0.82 — 가운데 밝기(0.5)에서 그보다 어둡지 않게
			var t: Vector3 = Purity.ASH_TINTS.get(r, Vector3(0.66, 0.70, 0.78))
			var old_mid := Color(t.x, t.y, t.z).get_luminance() * 0.5 * 0.82
			not_dark = img.get_pixel(Purity.LUT_W / 2, 0).get_luminance() >= old_mid - 0.01
		var spec := Purity.ash_spec(r)
		_check(ok and mono and not_dark and spec.has("hues"), "%s 잿빛 표 64×8, 모든 줄 밝기 순서 %s, 옛 셰이더보다 어둡지 않음 %s, data/terrain/%s.json 에서 (색상 띠 %d개)" % [r, mono, not_dark, r, (spec.get("hues", {}) as Dictionary).size()])
	var mat: ShaderMaterial = preload("res://shaders/ash_purify.tres")
	Purity.apply_region("canopy")
	_check(mat.get_shader_parameter("ash_lut") == Purity.ash_lut("canopy"), "apply_region 이 공용 재질에 그 지역 잿빛 표를 넣는다")


## g) 금 간 벽 (비밀 벽·비밀 천장): 맞을수록·머리를 박을수록 열림, 부서지면 조각이 떨어진다
func _probe_cracked() -> void:
	var room := await _load_room("canopy_01")
	var wall: SecretWall = room.get_node("Terrain/SecretWall1")
	var crack: CrackedArt = wall.get("_crack")
	_check(crack != null, "canopy_01 비밀 벽이 금 간 나무 그림을 쓴다")
	if crack:
		var a0: float = crack._open.modulate.a
		var hit := HitData.new()
		hit.from_player = true
		wall.receive_hit(hit, null)
		await _frames(2)
		var a1: float = crack._open.modulate.a
		_check(a1 > a0 + 0.2, "한 대 맞으면 갈라진 그림이 드러난다 (열림 %.2f → %.2f)" % [a0, a1])
		wall.receive_hit(hit, null)
		wall.receive_hit(hit, null)
		await _frames(2)
		var debris := 0
		for c in wall.get_parent().get_children():
			if c is CrackedArt.CrackDebris:
				debris = c.get_child_count()
		_check(wall._broken and not crack.visible and debris >= 4, "세 대 맞으면 부서지고 그림 조각 %d개가 떨어진다" % debris)
	await _free_room(room)
	var r3 := await _load_room("canopy_03")
	var ceil: SecretCeiling = r3.get_node("Terrain/SecretCeiling1")
	_check(ceil.get("_crack") != null and (ceil.get("_crack") as CrackedArt).flip_v, "비밀 천장(옹이)도 금 간 나무 그림 (위아래 뒤집어 밑동이 천장에)")
	var cs := _first_shape(ceil)
	_check(cs != null and cs.shape is ConvexPolygonShape2D, "비밀 천장 충돌은 옹이 모양 그대로")
	await _free_room(r3)
	var r2 := await _load_room("canopy_02")
	var cw: CrackedWall = r2.get_node("Terrain/CrackedWall1")
	_check(cw.get("_crack") != null and not cw._sprite.visible, "금 간 벽(확장판)도 수관에서는 금 간 나무 그림")
	await _free_room(r2)
	var r4 := await _load_room("abyss_02")
	var sc: SecretCeiling = r4.get_node("Terrain/SecretCeiling1")
	var c4 = sc.get("_crack")
	if c4:
		var a4: float = (c4 as CrackedArt)._open.modulate.a
		sc.on_head_bump(null, 600.0)
		await _frames(2)
		_check((c4 as CrackedArt)._open.modulate.a > a4 + 0.2 or sc._broken, "abyss_02 비밀 천장: 머리를 박으면 갈라진 그림이 드러난다 (열림 %.2f → %.2f)" % [a4, (c4 as CrackedArt)._open.modulate.a])
	else:
		_check(false, "abyss_02 비밀 천장이 금 간 나무 그림을 쓴다")
	await _free_room(r4)


func _probe_record() -> void:
	var holder := Node2D.new()
	add_child(holder)
	var rec := Record.new()
	rec.kind = "note"
	holder.add_child(rec)
	var st := Record.new()
	st.kind = "stone"
	holder.add_child(st)
	var pg := Record.new()
	pg.kind = "page"
	holder.add_child(pg)
	var bk := Record.new()
	bk.kind = "book"
	holder.add_child(bk)
	await _frames(1)
	_check(rec._sheet != null and rec._sheet.texture == Record.PARCHMENT, "기록물(쪽지)은 양피지 그림")
	_check(st._sheet == null, "비석은 그대로 돌")
	_check(pg._sheet != null and pg._sheet.texture == Record.PAGE_TEX, "경전 조각(page)은 확장판 자리 그림 object_scripture_page.png")
	_check(bk._sheet != null and absf(bk._sheet.rotation_degrees) < 20.0, "책(book) 양피지는 옆으로 눕지 않는다 (기울기 %.0f도)" % (bk._sheet.rotation_degrees if bk._sheet else 0.0))
	holder.queue_free()
	await _frames(1)


## 그 지역(region)의 방 이름들 (scenes/rooms/*.tscn 의 region = "…" 줄로 찾는다)
static func _rooms_of_region(r: String) -> Array:
	var out := []
	var d := DirAccess.open("res://scenes/rooms")
	if d == null:
		return out
	var files := d.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".tscn"):
			continue
		if FileAccess.get_file_as_string("res://scenes/rooms/" + f).contains('region = "%s"' % r):
			out.append(f.get_basename())
	return out


## h) 수액 웅덩이 (모든 방): 그림 옷의 물 그림으로 그리고 — 비치고(위가 옅고 깊을수록 진함), 웅덩이 폭을 덮고, 그림 수면은 맞는 영역의 윗변,
##    몸통 아래끝은 바닥 윗면 아래에서 사라지고, 막힌 끝은 지형 속으로·열린 끝은 물가로 서서히 — **판정·surface_y 는 그대로**.
func _probe_pools(ids: Array) -> void:
	var bad := []
	var n := 0
	var alphas := []
	for id in ids:
		var path := "res://scenes/rooms/%s.tscn" % id
		if not FileAccess.get_file_as_string(path).contains("sap_pool"):
			continue
		var room := await _load_room(id)
		for pool in room.find_children("*", "SapPool", true, false):
			n += 1
			var nm := "%s/%s" % [id, pool.name]
			var cs: CollisionShape2D = pool._shape
			var rect := cs.shape as RectangleShape2D
			if rect.size != Vector2(pool.size.x, pool.size.y * 0.8) or cs.position != Vector2(pool.size.x / 2.0, pool.size.y * 0.6):
				bad.append("%s 판정이 바뀜" % nm)
			if pool.surface_y() != pool.global_position.y:
				bad.append("%s surface_y 가 바뀜" % nm)
			var body: TerrainArt = pool.get("_body")
			var water: Node2D = pool.get("_art")
			if body == null or water == null:
				bad.append("%s 물 그림 없음" % nm)
				continue
			var top: float = pool.size.y * SapPool.SURFACE_FRAC - SapPool.FILL_RISE * float(pool.get("_alive"))
			if absf(water.position.y - top) > 0.5:
				bad.append("%s 그림 수면 %.1f ≠ %.1f" % [nm, water.position.y, top])
			var ab := _art_bounds(body)
			# (막힌 끝은 지형 속 TUCK px 동안 사라지므로 그만큼은 비어도 된다)
			var tol := SapPool.TUCK + 8.0
			if ab.position.x > tol or ab.end.x < pool.size.x - tol or ab.position.y > 1.0:
				bad.append("%s 그림 %s 이 웅덩이 폭 %.0f 을 덮지 않음" % [nm, ab, pool.size.x])
			if ab.position.x < -SapPool.SHORE_OUT - 2.0 or ab.end.x > pool.size.x + SapPool.SHORE_OUT + 2.0:
				bad.append("%s 그림이 물가보다 멀리 %s" % [nm, ab])
			# 비침: 물빛(위가 옅고 깊을수록 진한 그라데이션) + 결(옅은 그림) — 위·깊은 곳의 덮임이 0.9 미만
			var deep: TerrainArt = pool.get("_deep")
			if deep == null:
				bad.append("%s 물빛 겹 없음" % nm)
				continue
			var dcols: PackedColorArray = deep._bufs[TerrainArt.BUF_PLAIN]["cols"]
			var dpts: PackedVector2Array = deep._bufs[TerrainArt.BUF_PLAIN]["pts"]
			var d_top := 0.0
			var d_mid := 0.0
			for i in dpts.size():
				if absf(dpts[i].y) < 0.5:
					d_top = maxf(d_top, dcols[i].a)
				elif dcols[i].a > 0.0:
					d_mid = maxf(d_mid, dcols[i].a)
			var da: float = deep.modulate.a
			var ba: float = body.modulate.a
			var cover_top := 1.0 - (1.0 - d_top * da) * (1.0 - ba * 0.75)
			var cover_mid := 1.0 - (1.0 - d_mid * da) * (1.0 - ba)
			alphas.append("%s %.2f/%.2f" % [pool.name, cover_top, cover_mid])
			if not (d_top < d_mid and cover_mid < 0.9 and cover_top < 0.6):
				bad.append("%s 비치지 않음 (위 %.2f 깊은 곳 %.2f)" % [nm, cover_top, cover_mid])
			# 아래끝: 바닥 윗면(없으면 웅덩이 바닥) 아래 FLOOR_SINK 안에서 사라진다 (그려진 바위 바닥이 보이지 않게)
			var floor_y: float = minf(pool._floor_below(), pool.size.y)
			if ab.end.y + top > floor_y + SapPool.FLOOR_SINK + SapPool.FILL_RISE + 2.0:
				bad.append("%s 몸통 아래끝 %.0f 이 바닥 %.0f 아래로 길다" % [nm, ab.end.y + top, floor_y])
		await _free_room(room)
	_check(n >= 12 and bad.is_empty(), "수액 웅덩이 %d곳: 물빛·결 두 겹, 비침(덮임 위 0.6·깊은 곳 0.9 미만), 폭·물가, 수면 = 맞는 영역 윗변, 아래끝 바닥에서 사라짐, 판정·surface_y 그대로 %s" % [n, bad.slice(0, 6)])
	print("[probe]   웅덩이 덮임(위/깊은 곳): %s" % [alphas])


## i) 지역마다 따로 정한 것 (데이터·방 파일): 지역 그림 옷 시험(9 a~h)은 위에서 모든 지역을 같은 기준으로 쟀다.
func _probe_region_extras() -> void:
	# 마을: 방 파일에서 정한 발판 조각 (등불 골목 계단 P3 = 흔들다리)
	var v2 := await _load_room("village_02")
	var p3: TerrainArt = v2.get_node("Terrain/P3").get("_art")
	_check(p3 != null and p3.pick == "bridge_a", "마을 등불 골목 P3: 방 파일의 terrain_piece 로 흔들다리(bridge_a) (%s)" % [p3.pick if p3 else "-"])
	await _free_room(v2)
	# 채굴장·잠긴 채굴장·호수: 높은 옆면의 벽 조각, 아랫면의 천장 조각 (wall·ceiling 역할)
	for pair in [["mine_02", "mine"], ["flooded_mine_01", "flooded_mine"], ["sap_lake_02", "sap_lake"], ["hidden_descent", "sap_descent"]]:
		var room := await _load_room(pair[0])
		var skin := TerrainSkin.for_region(pair[1])
		var walls := 0
		var ceils := 0
		for t in room.get_node("Terrain").get_children():
			var art = t.get("_art")
			if art is TerrainArt:
				walls += _role_quads(art, "wall")
				ceils += _role_quads(art, "ceiling")
		_check(walls > 0 and (ceils > 0 or not skin.has_role("ceiling")), "%s: 높은 옆면에 벽 조각 %d 토막, 천장 조각 %d 토막 (%s)" % [pair[0], walls, ceils, pair[1]])
		await _free_room(room)
	# 심연: 정원 두 방은 room_skins 로 정원 그림 옷, 한쪽 방향이 아닌 얇은 단은 통나무(log), 어두운 방의 작은 빛, 장식 달빛풀
	var a := TerrainSkin.for_region("abyss")
	var rs: Dictionary = a.data.get("room_skins", {})
	_check(rs.get("moon_garden", "") == "abyss_garden" and rs.get("abyss_boss", "") == "abyss_garden", "심연 room_skins: 달빛 정원·정원의 끝 = abyss_garden (%s)" % [rs])
	var logs := 0
	var thin_solid := 0
	for id in ["abyss_01", "abyss_02", "abyss_hidden_1", "abyss_hidden_2", "abyss_mini_1", "moon_garden", "abyss_boss"]:
		var room := await _load_room(id)
		await _frames(2)
		for t in room.get_node("Terrain").get_children():
			if t is Platform and not t.one_way and t._is_thin() and t.get("_art") is TerrainArt and (t.get("_art") as TerrainArt).skin.has_role("log"):
				thin_solid += 1
				if (t.get("_art") as TerrainArt).pick in (t.get("_art") as TerrainArt).skin.list("log") or (t.get("_art") as TerrainArt).pick == "":
					logs += 1
		var glow := _count_glow(room)
		if bool(room.get("dark")):
			_check(glow >= 1 and glow <= TerrainStyle.GLOW_LIGHTS_PER_ROOM, "%s(어두운 방): 수정·버섯 자리의 작은 빛 %d개 (1~%d)" % [id, glow, TerrainStyle.GLOW_LIGHTS_PER_ROOM])
		else:
			_check(glow == 0, "%s(밝은 방): 작은 빛 없음 (%d)" % [id, glow])
		if id == "moon_garden":
			_check(_count_decor_grass(room) == 6, "달빛 정원의 장식 달빛풀 %d개 그대로 (6)" % _count_decor_grass(room))
		await _free_room(room)
	_check(thin_solid > 0 and logs == thin_solid, "심연: 한쪽 방향이 아닌 얇은 단 %d곳이 통나무(log) %d곳" % [thin_solid, logs])
	var mid := Purity.ash_lut("abyss").get_image().get_pixel(Purity.LUT_W / 2, 0)
	_check(mid.b > mid.g and mid.s < 0.15 and mid.get_luminance() >= 0.42, "심연 잿빛은 보랏빛이 살짝 도는 밝은 회색 (가운데 %s)" % mid.to_html(false))
	# 수액의 호수: 배경 세 장은 기획자 그림
	var bad := []
	var pairs := {"res://art/backgrounds/bg_sap_lake_1.png": "res://익스펜션/그림/배경/4-1.PNG", "res://art/backgrounds/bg_sap_lake_boss.png": "res://익스펜션/그림/배경/4-2.PNG", "res://art/backgrounds/bg_hidden_descent.png": "res://익스펜션/그림/배경/5.PNG"}
	for k in pairs:
		var tex: Texture2D = load(k)
		var src := ProjectSettings.globalize_path(pairs[k])
		if tex == null or tex.get_size() != Vector2(1536, 1024) or (FileAccess.file_exists(src) and FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(k)).size() != FileAccess.get_file_as_bytes(src).size()):
			bad.append(k)
	_check(bad.is_empty(), "수액의 호수 배경 세 장이 기획자 그림 (1536×1024) %s" % [bad])


## TerrainArt 의 atlas 사각형 중 그 역할 조각(uv 가 조각 자리 안)을 쓰는 꼭짓점 묶음 수 (토막 수 어림)
func _role_quads(art: TerrainArt, role: String) -> int:
	var skin := art.skin
	if not skin.has_role(role):
		return 0
	var rects := []
	for n in skin.list(role):
		var r := skin.rect_of(n)
		rects.append(Rect2(r.position / skin.atlas_size, r.size / skin.atlas_size).grow(0.0005))
	var uvs: PackedVector2Array = art._bufs[TerrainArt.BUF_ATLAS]["uvs"]
	var hits := 0
	for uv in uvs:
		for rr in rects:
			if (rr as Rect2).has_point(uv):
				hits += 1
				break
	return hits / 8


## 장식 달빛풀(decor — 무리에 끼지 않는다) 수
func _count_decor_grass(n: Node) -> int:
	var k := 0
	for c in n.get_children():
		if "decor" in c and "grass_id" in c and bool(c.get("decor")) and (c as CanvasItem).visible:
			k += 1
		k += _count_decor_grass(c)
	return k

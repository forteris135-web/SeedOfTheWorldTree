extends Node
## 지형 시험. 실행: godot --headless --path . res://tools/probe_terrain.tscn
## (--headless 를 빼고 돌리면 실제 화면 렌더러로 비용을 잰다 — 창이 잠깐 뜬다.)
## 지형은 두 가지 방식이 함께 있다: 그림 조각 지형(TerrainArt, 그림 옷이 있는 지역 — 지금은 수관)과
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
##  9) 그림 조각 지형 (수관 방 전부):
##     a) 그림 옷이 읽히고(조각·atlas·몸통 결), 수관 방의 모든 지형·가시·비밀 벽·금 간 벽이 그림 조각으로 그려진다.
##     b) 발 딛는 자리: 드러난 모든 윗면(발판·경사, 장식을 끈 벽·천장·구덩이 바닥은 빼고)에서 충돌 윗면 8px 아래가 그림(조각)으로 덮여 있고(빈 곳 10% 미만),
##        그림의 윗선(빽빽한 윗면: 불투명이 12px 이어지기 시작하는 곳)이 충돌 윗면과 ±10px 안 (잎이 발목까지 살짝 덮는 정도) — 소녀가 그림 위에 서 있고 떠 보이지 않는다.
##        (그림 픽셀을 직접 찾아본다: 삼각형 → UV → atlas 알파)
##     c) 충돌은 그대로: 발판 사각형·경사 다각형·가시 판정이 크기에서 계산한 값과 같다.
##     d) 비용: 만들기는 방에 들어올 때 한 번(방 하나 평균 60ms 미만), 노드 하나에 그리기 호출 4번 이하,
##        정화 연출 프레임(Room 이 테두리 색을 바꿈)에도 다시 만들지·그리지 않는다.
##     e) 팔레트: 지역 잿빛 표(64×8)가 만들어지고, 무채색 줄이 밝기 순서를 지키며, 옛 셰이더보다 어둡지 않다.
##     f) 금 간 벽: 맞을수록 열린 그림이 드러나고, 부서지면 그림 조각이 떨어진다. 기록물은 양피지 그림.
## 마지막에 "[probe] 끝: 실패 N" 을 찍고 그 수로 종료한다.

const Legacy := preload("res://tools/terrain_legacy_draw.gd")
const REGIONS := ["canopy", "village", "mine", "abyss", "sap_lake", "flooded_mine"]
const NEED_KEYS := ["moss", "moss_light", "vine", "leaf", "leaf_light", "flower_px", "glint_px", "mushroom_px", "plate_px", "strap_px", "chain_px", "rust_px", "drip_px", "smear_px", "bead_px", "sheen", "root_px", "stone_px", "web_p", "thorn_tip", "thorn_glow", "moss_density", "beard_px", "grass_px", "sprig_px", "bark_lift", "bark_alpha", "ridge_px", "knot_px", "glow_depth"]
const ROOMS := ["canopy_01", "canopy_02", "canopy_03", "canopy_04", "canopy_hidden", "canopy_boss", "village_01", "village_02", "village_shrine", "mine_01", "mine_02", "mine_deep", "mine_boss", "abyss_01", "abyss_02", "moon_garden", "abyss_boss"]
const COST_ROOMS := ["canopy_01", "mine_02", "village_02", "abyss_02", "canopy_boss"]
## 그림 조각 지형 방 (수관)
const ART_ROOMS := ["canopy_01", "canopy_02", "canopy_03", "canopy_04", "canopy_05", "canopy_06", "canopy_07", "canopy_boss", "canopy_hidden", "canopy_hidden_1", "canopy_hidden_2", "canopy_mini_1", "canopy_mini_2", "mine_01", "mine_02", "mine_boss", "mine_deep", "mine_hidden_1", "mine_hidden_2", "mine_mini_1", "flooded_mine_01", "flooded_mine_02", "flooded_mine_boss", "flooded_mine_hidden_1"]
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
		await _probe_art_cost()
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
var _atlas_img: Image


func _probe_art() -> void:
	TerrainSkin.clear_cache()
	var skin := TerrainSkin.for_region("canopy")
	_check(skin != null, "수관 그림 옷이 읽힌다")
	if skin == null:
		return
	_check(skin.has_role("branch") and skin.has_role("slab") and skin.has_role("ground") and skin.has_role("hang") and skin.has_role("thorn"), "역할별 조각: 가지 %d·판 %d·바닥 %d·매달림 %d·가시 %d" % [skin.list("branch").size(), skin.list("slab").size(), skin.list("ground").size(), skin.list("hang").size(), skin.list("thorn").size()])
	_check(skin.atlas != null and skin.fill != null and skin.fill_v != null, "atlas·몸통 결(가로/세로) 그림이 있다")
	_check(CrackedArt.can_build(skin), "금 간 벽 그림 세 장(닫힘·열림·틈 빛)이 있다")
	var bad_walk := []
	for n in skin.list("branch") + skin.list("slab") + skin.list("ground"):
		var w := skin.walk_of(n)
		if w.y - w.x < 60.0:
			bad_walk.append(n)
	_check(bad_walk.is_empty(), "걷는 조각마다 걷는 구간이 60px 넘게 있다 %s" % [bad_walk])
	_check(TerrainSkin.for_region("nowhere") == null, "그림 옷이 없는 지역은 null (옛 방식으로 그린다)")
	_atlas_img = Image.load_from_file(ProjectSettings.globalize_path("res://art/terrain/canopy/atlas.png"))
	_atlas_img.convert(Image.FORMAT_RGBA8)
	await _probe_art_rooms(skin)
	await _probe_thorn_facing()
	await _probe_art_cost()
	_probe_palette()
	await _probe_cracked(skin)
	await _probe_record()


func _probe_art_rooms(skin: TerrainSkin) -> void:
	var not_art := []
	var collider_bad := []
	var feet_bad := []
	var top_bad := []
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
	var sink := float(skin.param("thorn", "sink", 10.0))
	for id in ART_ROOMS:
		var room := await _load_room(id)
		var solids := _solids(room)
		var bounds: Rect2 = room.get("bounds")
		for t in room.get_node("Terrain").get_children():
			# f) 몸통 결은 부모 묶음 맨 아래 겹 (나중 형제의 몸통이 앞 형제의 끝 조각을 덮지 않게)
			var art_n = t.get("_art")
			if art_n is TerrainArt and not (art_n as TerrainArt).fill_in_layer():
				fill_bad.append("%s/%s" % [id, t.name])
			# e) 드러난 끝 밖 발 높이에 남는 그림 (서지 못하는 자리가 발판처럼 보이지 않게)
			if art_n is TerrainArt and not (t is SecretWall or t is CrackedWall):
				for seg in _top_segments(t):
					for side in [-1.0, 1.0]:
						var far := _overhang(t, art_n, seg[0] if side < 0.0 else seg[1], side, solids, bounds)
						if far < 0.0:
							continue
						ends_checked += 1
						over_all.append([far, "%s/%s %s" % [id, t.name, "왼끝" if side < 0.0 else "오른끝"]])
						if far > OVERHANG_MAX:
							over_bad.append("%s/%s %s %.0fpx" % [id, t.name, "왼끝" if side < 0.0 else "오른끝", far])
			if t is SecretWall or t is CrackedWall:
				if t.get("_crack") == null and not (t.get("_broken") == true):
					not_art.append("%s/%s" % [id, t.name])
				continue
			if (t is Platform or t is TerrainPolygon) and not t.is_art():
				not_art.append("%s/%s" % [id, t.name])
				continue
			# c) 충돌 모양
			if t is Platform:
				var cs: CollisionShape2D = _first_shape(t)
				var ok: bool = cs != null and cs.shape is RectangleShape2D and (cs.shape as RectangleShape2D).size == t.size and cs.position == t.size / 2.0 and cs.one_way_collision == bool(t.one_way)
				if not ok:
					collider_bad.append("%s/%s" % [id, t.name])
			elif t is TerrainPolygon:
				var cp: CollisionPolygon2D = null
				for c in t.get_children():
					if c is CollisionPolygon2D:
						cp = c
				if cp == null or cp.polygon != t.polygon:
					collider_bad.append("%s/%s" % [id, t.name])
			# b) 발 딛는 자리
			for seg in _top_segments(t):
				var r := _feet_check(t, seg[0], seg[1], solids, bounds)
				if r.is_empty():
					continue
				tops_checked += 1
				if float(r["cov"]) < worst_cov:
					worst_cov = r["cov"]
					worst_name = "%s/%s" % [id, t.name]
				if float(r["cov"]) < 0.9:
					feet_bad.append("%s/%s 덮임 %.0f%%" % [id, t.name, float(r["cov"]) * 100.0])
				tops_all.append(float(r["top"]))
				# 위쪽 허용: 기본 10px. 뒤 난간이 발 선 위로 솟은 조각을 쓰는 지역(채굴장 다리·수로)은 data 의 params.probe.rail 까지
				var rail := float((t.get("_art") as TerrainArt).skin.param("probe", "rail", 10.0))
				if float(r["top"]) < -maxf(rail, 10.0) or float(r["top"]) > 10.0:
					top_bad.append("%s/%s 윗선 %+.0fpx" % [id, t.name, float(r["top"])])
		var hz := room.get_node_or_null("Hazards")
		if hz:
			for th in hz.get_children():
				if th is Thorns:
					if th.get("_art") == null:
						not_art.append("%s/%s" % [id, th.name])
					var cs2: CollisionShape2D = _first_shape(th)
					var hr := Thorns.hit_rect(th.size, th.facing_dir)
					var old_rect := Vector2(th.size.x - 8, th.size.y * 0.7)
					if cs2 == null or (cs2.shape as RectangleShape2D).size != hr.size or cs2.position != hr.get_center() or (th.facing_dir == 0 and hr.size != old_rect):
						collider_bad.append("%s/%s(가시)" % [id, th.name])
					# g) 가시 끝 높이: 그림 끝이 상자 위로 0.5h 넘게 솟지 않는다 (판정보다 훨씬 높은 가시를 발이 지나가 보이지 않게)
					var ab := _art_bounds(th.get("_art"))
					var lh := Thorns.frame_size(th.size, th.facing_dir)
					var allowed := _thorn_allowed(th.size, th.facing_dir, sink)
					var tip_up := -ab.position.y / lh.y if th.facing_dir == 0 else 0.0
					tip_worst = maxf(tip_worst, tip_up)
					if not allowed.encloses(ab) or ab.intersection(hr).get_area() < hr.get_area() * 0.95:
						tip_bad.append("%s/%s 그림 %s 판정 %s" % [id, th.name, ab, hr])
		await _free_room(room)
	_check(not_art.is_empty(), "수관 %d곳: 지형·가시·비밀 벽이 모두 그림 조각 (아닌 것 %s)" % [ART_ROOMS.size(), not_art.slice(0, 8)])
	_check(collider_bad.is_empty(), "수관 %d곳: 충돌 모양이 그대로 (다른 것 %s)" % [ART_ROOMS.size(), collider_bad.slice(0, 8)])
	_check(feet_bad.is_empty(), "드러난 윗면 %d곳: 발밑(충돌 윗면 8px 아래)이 그림으로 90%% 넘게 덮임 (가장 낮은 %s %.0f%%) %s" % [tops_checked, worst_name, worst_cov * 100.0, feet_bad.slice(0, 6)])
	tops_all.sort()
	var med_all: float = tops_all[tops_all.size() / 2] if not tops_all.is_empty() else 0.0
	_check(top_bad.is_empty(), "드러난 윗면 %d곳: 그림 윗선(빽빽한 윗면)이 충돌 윗면 ±10px 안 — 뒤 난간 조각은 지역 params.probe.rail 까지 (전체 중앙값 %+.0fpx, 범위 %+.0f~%+.0f) %s" % [tops_checked, med_all, tops_all[0] if not tops_all.is_empty() else 0.0, tops_all[-1] if not tops_all.is_empty() else 0.0, top_bad.slice(0, 6)])
	over_all.sort_custom(func(x, y): return x[0] > y[0])
	if "--verbose" in OS.get_cmdline_user_args():
		for r in over_all.slice(0, 12):
			print("[probe]   끝 밖 그림 %3.0fpx  %s" % [r[0], r[1]])
	_check(ends_checked > 100 and over_bad.is_empty(), "드러난 충돌 끝 %d곳: 끝 밖 발 높이(윗면 +2·+8px)에 그림이 %.0fpx 넘게 남지 않는다 (가장 긴 %s) %s" % [ends_checked, OVERHANG_MAX, ("%.0fpx %s" % [over_all[0][0], over_all[0][1]]) if not over_all.is_empty() else "-", over_bad.slice(0, 6)])
	_check(fill_bad.is_empty(), "몸통 결은 지형 묶음 맨 아래 겹에 그린다 (모든 몸통 → 모든 조각; 아닌 것 %s)" % [fill_bad.slice(0, 6)])
	_check(tip_bad.is_empty(), "방의 가시: 그림이 판정을 덮고, 끝이 상자 위로 0.5h 넘게 솟지 않는다 (가장 높은 %.2fh) %s" % [tip_worst, tip_bad.slice(0, 4)])


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


## 윗면 a→b 의 드러난 자리마다: 발밑(8px 아래)이 조각 그림으로 덮였는가, 그림 윗선이 충돌 윗면에서 얼마나 떨어졌나.
## 돌려주는 값: {cov: 덮인 비율, top: 윗선 차이의 중앙값(px, 위가 −)} — 드러난 자리가 없으면 빈 사전.
func _feet_check(t: Node2D, a: Vector2, b: Vector2, solids: Array, bounds: Rect2) -> Dictionary:
	var art: TerrainArt = t.get("_art")
	if art == null:
		return {}
	var tris := _atlas_tris(art)
	var n := maxi(2, int((b.x - a.x) / 16.0))
	var hits := 0
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
			if x >= bb.position.x and x <= bb.end.x and bb.end.y >= y - 60.0 and bb.position.y <= y + 60.0:
				col.append(tr)
		if _alpha_at(col, Vector2(x, y + 8.0)) > 0.5:
			hits += 1
		elif "--verbose" in OS.get_cmdline_user_args():
			print("[probe]   발밑 빔: %s x=%.0f/%.0f" % [t.name, x - a.x, b.x - a.x])
		# 그림 윗선: 위 60px 에서 아래로 내려가며 처음으로 12px 이어서 불투명한 곳 (자르기 도구의 '빽빽한 윗면'과 같은 기준)
		var run := 0
		var yy := y - 60.0
		var found := INF
		while yy < y + 60.0:
			if _alpha_at(col, Vector2(x, yy)) > 0.5:
				run += 1
				if run >= 6:
					found = yy - 10.0 - y
					break
			else:
				run = 0
			yy += 2.0
		if found < INF:
			diffs.append(found)
	if total == 0:
		return {}
	diffs.sort()
	var med: float = diffs[diffs.size() / 2] if not diffs.is_empty() else 99.0
	return {"cov": float(hits) / total, "top": med}


## 조각(atlas) 삼각형 목록: [[p0,p1,p2],[uv0,uv1,uv2],[a0,a1,a2], 상자] (노드 기준)
func _atlas_tris(art: TerrainArt) -> Array:
	_use_atlas(art.skin.region)   # 알파는 그 지형의 지역 atlas 에서 읽는다
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


## 지역 atlas 그림 (알파 읽기용, 지역마다 한 번 읽어 둔다)
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


## 가시 방향 (위·아래·왼쪽·오른쪽): 옆을 향하면 가시가 세로로 늘어서고, 판정도 같은 쪽(밑동 쪽 70%)에 놓인다.
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


## d) 비용: 만들기 시간·삼각형·그리기 호출, 정화 프레임에 다시 안 만들기
func _probe_art_cost() -> void:
	var sum := 0.0
	var worst := 0.0
	var worst_id := ""
	var tri_max := 0
	var calls_bad := []
	for id in ART_ROOMS:
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
	var avg := sum / ART_ROOMS.size()
	_check(avg < 60.0, "그림 지형 만들기: 방 하나 평균 %.1fms < 60ms (가장 긴 %s %.1fms)" % [avg, worst_id, worst])
	_check(tri_max < 40000, "방 하나 삼각형 %d개 < 40000 (아이폰 11 Pro 에 넉넉함)" % tri_max)
	_check(calls_bad.is_empty(), "노드 하나에 그리기 호출 4번 이하 %s" % [calls_bad])


## e) 팔레트 (잿빛 표)
func _probe_palette() -> void:
	for r in REGIONS:
		var tex: ImageTexture = Purity.ash_lut(r)
		var ok := tex != null and tex.get_width() == Purity.LUT_W and tex.get_height() == Purity.LUT_ROWS
		var img := tex.get_image() if tex else null
		var mono := true
		var not_dark := true
		if img:
			var prev := -1.0
			for x in Purity.LUT_W:
				var l := img.get_pixel(x, 0).get_luminance()
				if l < prev - 0.01:
					mono = false
				prev = l
			# 옛 셰이더: ((lum - 0.5) * 0.7 + 0.5) * 색조 * 0.82 — 가운데 밝기(0.5)에서 그보다 어둡지 않게
			var t: Vector3 = Purity.ASH_TINTS.get(r, Vector3(0.66, 0.70, 0.78))
			var old_mid := Color(t.x, t.y, t.z).get_luminance() * 0.5 * 0.82
			not_dark = img.get_pixel(Purity.LUT_W / 2, 0).get_luminance() >= old_mid - 0.01
		_check(ok and mono and not_dark, "%s 잿빛 표 64×8, 무채색 줄 밝기 순서 %s, 옛 셰이더보다 어둡지 않음 %s" % [r, mono, not_dark])
	var spec := Purity.ash_spec("canopy")
	_check(spec.has("hues") and (spec["hues"] as Dictionary).has("green"), "수관 잿빛 팔레트는 데이터 파일(data/terrain/canopy.json)에서 읽는다 (색상 띠 %d개)" % (spec.get("hues", {}) as Dictionary).size())
	var mat: ShaderMaterial = preload("res://shaders/ash_purify.tres")
	Purity.apply_region("canopy")
	_check(mat.get_shader_parameter("ash_lut") == Purity.ash_lut("canopy"), "apply_region 이 공용 재질에 그 지역 잿빛 표를 넣는다")


## f) 금 간 벽 (비밀 벽): 맞을수록 열림, 부서지면 조각이 떨어진다
func _probe_cracked(skin: TerrainSkin) -> void:
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

extends SceneTree
## 이펙트 그림 자르기 (2026-10-19 이펙트 리뉴얼 F1). 기획자의 이펙트 시트(익스펜션/그림/이펙트/, 읽기 전용)에서
## 쓸 조각을 잘라 art/fx/<이름>.png 로 저장한다. 잘라 둔 그림은 저장소에 들어 있으므로 다시 돌릴 일은 거의 없다
## (조각을 더 뽑거나 크기를 바꿀 때만). 다른 묶음(F2 보스 이펙트 등)도 아래 PIECES 에 줄을 더해 쓰면 된다.
##
## 사용: Godot --headless --path . -s res://tools/cut_fx.gd [-- 이름 이름 ...]   (이름을 주면 그 조각만)
##
## 자르는 법 (조각마다):
##  1) 시트에서 '씨앗 상자'(seed: 조각의 불투명한 몸통이 들어 있는 상자, tools/sheet_catalog.gd 목록의 rect 를 그대로 써도 된다)
##     둘레 margin px 까지를 창으로 잡는다.
##  2) 창 안에서 불투명(알파 > 0.5) 덩어리를 찾아, 씨앗 상자와 겹치는 덩어리만 남긴다 (옆 조각이 창에 들어와도 지워진다).
##  3) 남긴 덩어리에서 halo px 안쪽의 반투명 빛(번짐)만 살리고, 그 바깥은 부드럽게 지운다.
##  4) SheetCatalog.defringe 로 반투명 가장자리의 붉은·노란 찌꺼기 색을 정리한다 (시트마다 들어 있다).
##  5) 투명한 둘레를 잘라 내고, 긴 변이 max px 이 넘으면 줄인다.
##  mode "strip": 덩어리 고르기 없이 상자 그대로 자르고 위아래 가장자리를 흐리게 (레이저 몸통처럼 가로로 늘려 쓰는 띠)
##  edge_fade: 창의 네 변에서 이 px 안쪽부터 알파를 줄인다 (다른 그림과 붙어 있는 조각을 억지로 떼어 낼 때)
##  erase: 결과 그림(UV) 안에서 지울 상자들 [[x0, y0, x1, y1], ...] — 가장자리 16px 은 부드럽게 (초승달 안쪽에 떠 있는 꽃잎 등)
## 결과 그림마다 mipmaps 를 켠 .import 를 같이 쓴다 (게임에서 줄여 그리므로).

const SRC := "res://익스펜션/그림/이펙트/"
const OUT := "res://art/fx/"
const Catalog := preload("res://tools/sheet_catalog.gd")

const SEL := "셀레니아 이펙트(팔레트 스왑 장려).PNG"
const SEL2 := "셀레니아 2.PNG"
const LIB := "f9e779ec2e377070f1a41d5fab07c9a9e0f66e78 2.png"
const BOSS2 := "보스 이펙트 2.PNG"
## F2 (보스·적 기술 이펙트, 물 이펙트)
const BOSS1 := "보스 이펙트 1.PNG"
const WATER := "물 이펙트.png"
const CRYS := "PNG image.png"
const ROOTS := "c5ae2537b7ac497b3e4df78f9ff7a95127255eb6 2.png"
const MIX1 := "41d289b89b9cb809263c4ca6a4685335085833f2 2.png"

## 이름: [시트, 씨앗 상자 [x0,y0,x1,y1], 최대 긴 변 px, 추가 설정]
## 추가 설정: margin(창 여유, 기본 36) halo(빛 번짐 살리는 거리, 기본 22) mode("strip") edge_fade(px) window([x0,y0,x1,y1] 창을 직접)
const PIECES := {
	# ---- 셀레니아 칼질 (파란·흰 초승달, 팔레트 바꿔 쓰기 좋다) ----
	"slash_crescent": [SEL, [441, 54, 594, 188], 256, {}],          # 작은 초승달 베기 (위 끝이 굵고 아래로 흘러내림)
	"slash_rise": [SEL, [169, 68, 419, 174], 320, {}],              # 가늘게 올려 긋는 칼선
	"slash_sweep": [SEL, [649, 51, 852, 199], 288, {}],             # 위에서 아래로 쓸어내리는 호
	"slash_hook": [SEL, [30, 52, 176, 179], 224, {}],               # 갈고리처럼 감기는 짧은 호
	"slash_long": [SEL, [1200, 73, 1411, 236], 320, {"window": [1185, 40, 1440, 250], "edge_fade": 10}],            # 길게 내려 긋는 칼선
	"slash_big": [SEL, [1000, 241, 1422, 502], 512, {"window": [990, 222, 1440, 506], "edge_fade": 10, "erase": [[0.0, 0.28, 0.42, 0.78]]}],  # 큰 초승달 (씨앗 넓은 베기·3타). 안쪽 꽃잎은 지움
	"crescent_wave": [SEL, [392, 511, 801, 642], 448, {}],          # 꼬리 달린 초승달 검기 (바람 영혼)
	"crescent_small": [SEL, [31, 513, 133, 626], 160, {}],          # 작은 초승달
	"wisp_beam": [SEL, [65, 657, 649, 745], 512, {}],               # 가로로 흐르는 빛줄기 (구르기 잔상)
	"wisp_beam2": [SEL, [797, 685, 1382, 804], 512, {}],            # 끝이 반짝이는 긴 빛줄기 (낙하 공격 꼬리)
	"burst_pillar": [SEL, [34, 773, 288, 1061], 320, {}],           # 솟구치는 빛 기둥 (아래가 땅)
	"ground_burst": [SEL, [909, 852, 1419, 1059], 448, {}],         # 땅에서 터지는 넓은 빛 (낙하 공격 착지)
	# ---- 셀레니아 2 (빛 기둥·보호막·레이저·별빛) ----
	"pillar_lily": [SEL2, [72, 73, 240, 381], 320, {"window": [36, 30, 250, 400], "edge_fade": 10}], # 백합 빛 기둥 (회복)
	"pillar_spiral": [SEL2, [372, 47, 590, 418], 384, {"window": [356, 28, 598, 428], "edge_fade": 10}],  # 감아 오르는 빛 기둥 (정화)
	"dome": [SEL2, [705, 60, 1000, 375], 384, {"window": [690, 40, 1012, 392], "edge_fade": 8}],      # 유리 보호막 (가드)
	"shield_arc": [SEL2, [1030, 71, 1180, 330], 256, {"window": [1022, 52, 1192, 338], "edge_fade": 8}],   # 육각무늬 초승달 방패 (막기 번쩍임)
	"laser_start": [SEL2, [33, 420, 330, 706], 288, {"window": [26, 400, 330, 700], "edge_fade": 18}],
	"laser_body": [SEL2, [330, 536, 1150, 614], 512, {"mode": "strip"}],
	"laser_end": [SEL2, [1150, 398, 1440, 706], 288, {"window": [1150, 394, 1444, 712], "edge_fade": 14}],
	"orb_glow": [SEL2, [361, 440, 445, 515], 128, {"margin": 14}],  # 작은 빛 구슬 (모으는 빛)
	"star_crescent": [SEL2, [29, 674, 294, 925], 320, {"margin": 26}],  # 별빛 + 초승달 (무너짐)
	"star_burst": [SEL2, [326, 669, 560, 905], 288, {"margin": 12}],    # 별처럼 터지는 빛 (저스트 가드·타격)
	"crystal_burst": [SEL2, [562, 690, 764, 965], 288, {"margin": 20}], # 수정 조각 분수 (정화 끝)
	"moon_burst": [SEL2, [766, 642, 1072, 962], 320, {"margin": 20}],   # 달빛 소용돌이 (영혼 전환)
	"ripple": [SEL2, [65, 968, 327, 1056], 320, {"margin": 20}],    # 물결 고리 (땅 고리)
	# ---- 그림 모음 (고리·반짝임·연기) ----
	"ring": [LIB, [1287, 13, 1392, 125], 192, {"margin": 14}],      # 빛 고리
	"glint": [LIB, [1420, 161, 1520, 206], 128, {"margin": 12}],    # 네 갈래 반짝임 (줍기·빛 알갱이)
	"smoke_ring": [LIB, [1152, 905, 1292, 1016], 224, {"margin": 14}],  # 연기 고리 (쓰러짐 먼지)
	# ---- 보스 이펙트 2 (김 = 먼지로 바꿔 쓴다) ----
	"puff": [BOSS2, [160, 830, 309, 949], 192, {"window": [152, 812, 318, 948], "edge_fade": 16}],  # 뭉게 김 (착지 먼지)
	# ===================== F2: 보스·적 기술 이펙트 =====================
	# ---- 보스 이펙트 1 (금빛 잎·깃털: 잿빛 잎새의 새) ----
	"feather_gold": [BOSS1, [1180, 10, 1436, 128], 256, {"window": [1168, 0, 1448, 134], "edge_fade": 8}],   # 금빛 깃털 화살 (꼬리 달림, 오른쪽 아래를 향함)
	"leaf_bolt": [BOSS1, [600, 105, 760, 165], 192, {"window": [588, 96, 772, 172], "edge_fade": 8}],         # 작은 금빛 씨앗·잎 탄 (꼬리 달림, 오른쪽을 향함)
	"leaf_comet": [BOSS1, [80, 19, 292, 100], 256, {"window": [60, 8, 300, 112], "edge_fade": 8}],           # 잎이 감긴 씨앗 혜성 (중간 크기)
	"gust_crescent": [BOSS1, [880, 280, 1071, 625], 448, {"window": [600, 262, 1090, 640], "edge_fade": 12}], # 긴 꼬리의 큰 바람 초승달
	"gust_double": [BOSS1, [1106, 310, 1436, 619], 384, {"window": [1096, 290, 1448, 630], "edge_fade": 10}], # 두 겹 바람 초승달
	"leaf_swirl": [BOSS1, [1119, 644, 1436, 831], 384, {"window": [1104, 630, 1448, 845], "edge_fade": 10}],  # 잎 소용돌이 (회오리)
	"leaf_stream": [BOSS1, [14, 601, 765, 821], 512, {"window": [0, 590, 780, 832], "edge_fade": 10}],        # 길게 흐르는 잎 줄기 (날갯바람)
	"leaf_burst": [BOSS1, [66, 852, 360, 1074], 320, {"window": [10, 790, 372, 1086], "edge_fade": 10}],      # 땅에서 터지는 잎 무더기
	"leaf_b": [BOSS1, [23, 1007, 69, 1032], 96, {"margin": 8, "halo": 10}],     # 낱장 잎 (잎 더미·흩날리는 잎)
	"leaf_c": [BOSS1, [344, 1021, 400, 1048], 96, {"margin": 8, "halo": 10}],   # 낱장 잎 (조금 큰 것)
	# ---- 보스 이펙트 2 (물·김·물방울·나비) ----
	"geyser": [BOSS2, [16, 22, 253, 407], 320, {"window": [6, 8, 262, 418], "edge_fade": 8}],                 # 솟는 물기둥 (수액 기둥·불기둥)
	"bubble_trail": [BOSS2, [860, 90, 1061, 188], 288, {"window": [780, 70, 1072, 196], "edge_fade": 10}],     # 꼬리 달린 큰 물방울 (달빛 구슬·수액 방울)
	"bubble_small": [BOSS2, [658, 225, 820, 289], 192, {"window": [648, 210, 830, 300], "edge_fade": 8}],     # 꼬리 달린 작은 물방울
	"butterfly": [BOSS2, [1292, 19, 1419, 215], 192, {"window": [1270, 6, 1440, 230], "edge_fade": 8}],       # 수액 나비
	"water_laser": [BOSS2, [18, 571, 416, 656], 384, {"window": [8, 556, 440, 668], "edge_fade": 8}],         # 짧은 물줄기 (작은 펌프 분사)
	"drop": [BOSS2, [1035, 550, 1083, 749], 128, {"window": [1026, 540, 1092, 756], "edge_fade": 6}],       # 물방울 (떨어지는 방울)
	"splash_crown": [BOSS2, [16, 653, 251, 811], 256, {"window": [6, 640, 262, 822], "edge_fade": 8}],       # 왕관처럼 튀는 물보라
	"steam_column": [BOSS2, [450, 840, 545, 935], 224, {"window": [430, 820, 562, 952], "edge_fade": 20}],   # 위로 솟는 김 (굴뚝은 잘라 냄)
	"water_crescent_big": [BOSS2, [1300, 830, 1400, 1060], 288, {"window": [1150, 790, 1448, 1086], "edge_fade": 10}],
	# ---- 물 이펙트 ----
	"ripple_drop": [WATER, [769, 351, 1100, 485], 288, {"window": [730, 338, 1110, 498], "edge_fade": 10}],  # 방울 하나와 동심원 물결
	"water_splash": [WATER, [33, 702, 360, 918], 256, {"window": [10, 690, 372, 930], "edge_fade": 10}],     # 물보라 (튀어 오르는 물)
	"water_curl": [WATER, [758, 77, 1212, 253], 320, {"window": [740, 40, 1225, 300], "edge_fade": 10}],     # 부서지는 물마루 (오른쪽으로 말림)
	"water_strip": [WATER, [1110, 569, 1506, 676], 320, {"window": [1096, 540, 1518, 690], "edge_fade": 10}],  # 옆으로 흩뿌리는 물줄기
	# ---- 보랏빛 수정·초승달 (PNG image) ----
	"moon_arc": [CRYS, [537, 514, 942, 797], 384, {"window": [520, 495, 960, 810], "edge_fade": 10}],        # 꽃잎 섞인 보랏빛 초승달 (지팡이 휘두르기)
	# ---- 뒤틀린 뿌리·씨앗 (c5ae) ----
	"root_hand_open": [ROOTS, [10, 15, 286, 451], 320, {"window": [0, 0, 292, 466], "edge_fade": 8}],        # 손가락을 벌린 뿌리 손
	"root_hand_grip": [ROOTS, [285, 97, 465, 460], 320, {"window": [280, 80, 472, 470], "edge_fade": 8}],    # 움켜쥔 뿌리 손
	"seed_fall": [ROOTS, [82, 483, 203, 819], 224, {"window": [40, 470, 240, 830], "edge_fade": 8}],         # 빛 꼬리를 달고 떨어지는 가시 씨앗 (아래를 향함)
	"seed_burst": [ROOTS, [517, 836, 730, 1063], 256, {"window": [500, 826, 745, 1076], "edge_fade": 8}],    # 씨앗이 땅에 닿아 터지는 빛
	# ---- 41d289 (창 빛줄기·뿌리 가시·뿌리 덩어리) ----
	"lance_streak": [MIX1, [217, 141, 484, 208], 320, {"window": [205, 128, 500, 218], "edge_fade": 8}],     # 창끝처럼 뾰족한 빛줄기 (찌르기 궤적)
	"root_spike_art": [MIX1, [178, 745, 323, 976], 288, {"window": [162, 728, 355, 1004], "edge_fade": 24}],  # 땅에서 솟는 뿌리 가시 (밑동에 꽃)
	"root_surge": [MIX1, [182, 530, 493, 729], 352, {"window": [170, 520, 505, 740], "edge_fade": 10}],       # 앞으로 덮쳐 오는 뿌리 덩어리 (뿌리 벽)
	"root_burst": [MIX1, [820, 849, 952, 1008], 192, {"window": [805, 835, 965, 1018], "edge_fade": 8}],     # 흙과 뿌리 가시가 터지는 작은 덩어리 (충격파)
	# ---- 그림 모음 f9e7 (등불·버섯·구름) ----
	"lantern": [LIB, [505, 760, 545, 885], 160, {"margin": 16}],                                              # 작은 등불 (던지는 등불)
	"mushroom": [LIB, [165, 760, 305, 890], 224, {"window": [152, 740, 318, 900], "edge_fade": 8}],         # 빛나는 버섯 (포자 터짐)
	"spore_ring": [LIB, [990, 905, 1129, 1014], 192, {"window": [975, 890, 1140, 1022], "edge_fade": 8}],   # 꽃잎 섞인 둥근 안개 (포자 구름)
}

const ALPHA_SOLID := 0.5


func _init() -> void:
	var only := OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var sheets := {}
	var n := 0
	for name in PIECES:
		if not only.is_empty() and not only.has(name):
			continue
		var def: Array = PIECES[name]
		var sheet: String = def[0]
		if not sheets.has(sheet):
			var img := Image.load_from_file(ProjectSettings.globalize_path(SRC + sheet))
			if img == null:
				printerr("시트를 못 읽었다: ", sheet)
				continue
			img.convert(Image.FORMAT_RGBA8)
			sheets[sheet] = img
		var out := cut_piece(sheets[sheet], def[1], def[3])
		for r in def[3].get("erase", []):
			_erase(out, r)
		var maxside: int = def[2]
		var s := minf(1.0, float(maxside) / float(maxi(out.get_width(), out.get_height())))
		if s < 1.0:
			out.resize(maxi(1, roundi(out.get_width() * s)), maxi(1, roundi(out.get_height() * s)), Image.INTERPOLATE_LANCZOS)
		var path := ProjectSettings.globalize_path(OUT + name + ".png")
		out.save_png(path)
		_write_import(path)
		print("[cut_fx] %s ← %s %s → %dx%d" % [name, sheet, def[1], out.get_width(), out.get_height()])
		n += 1
	print("[cut_fx] 끝: %d 조각" % n)
	quit()


static func cut_piece(sheet: Image, seed: Array, opts: Dictionary) -> Image:
	var sw := sheet.get_width()
	var sh := sheet.get_height()
	var margin: int = opts.get("margin", 36)
	var halo: float = opts.get("halo", 22.0)
	var win := Rect2i(seed[0] - margin, seed[1] - margin, seed[2] - seed[0] + margin * 2, seed[3] - seed[1] + margin * 2)
	if opts.has("window"):
		var w: Array = opts["window"]
		win = Rect2i(w[0], w[1], w[2] - w[0], w[3] - w[1])
	if opts.get("mode", "") == "strip":
		win = Rect2i(seed[0], seed[1], seed[2] - seed[0], seed[3] - seed[1])
	win = win.intersection(Rect2i(0, 0, sw, sh))
	var img := sheet.get_region(win)
	var w := img.get_width()
	var h := img.get_height()
	var d := img.get_data()
	if opts.get("mode", "") == "strip":
		# 띠: 위아래 가장자리 25% 를 부드럽게 흐린다 (가로로 늘려 쓰므로 좌우는 그대로)
		for y in h:
			var k := minf(float(y), float(h - 1 - y)) / (h * 0.25)
			var f := clampf(k, 0.0, 1.0)
			f = f * f * (3.0 - 2.0 * f)
			for x in w:
				var p := (y * w + x) * 4 + 3
				d[p] = int(d[p] * f)
		img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, d)
		return Catalog.defringe(img, 0.6)
	# 1) 불투명 덩어리 (8방향)
	var athr := int(ALPHA_SOLID * 255.0)
	var label := PackedInt32Array()
	label.resize(w * h)
	var keep_ids := {}
	var seed_local := Rect2i(seed[0] - win.position.x, seed[1] - win.position.y, seed[2] - seed[0], seed[3] - seed[1])
	var stack := PackedInt32Array()
	var cid := 0
	for start in w * h:
		if d[start * 4 + 3] <= athr or label[start] != 0:
			continue
		cid += 1
		var touches_seed := false
		var cnt := 0
		stack.clear()
		stack.append(start)
		label[start] = cid
		while stack.size() > 0:
			var q := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			cnt += 1
			var qx := q % w
			var qy := q / w
			if not touches_seed and seed_local.has_point(Vector2i(qx, qy)):
				touches_seed = true
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var nx: int = qx + dx
					var ny: int = qy + dy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var nq := ny * w + nx
					if label[nq] == 0 and d[nq * 4 + 3] > athr:
						label[nq] = cid
						stack.append(nq)
		if touches_seed and cnt >= 6:
			keep_ids[cid] = true
	# 2) 남긴 덩어리까지의 거리 (체스판 거리 근사, 두 번 훑기)
	var big := 1 << 20
	var dist := PackedInt32Array()
	dist.resize(w * h)
	for p in w * h:
		dist[p] = 0 if keep_ids.has(label[p]) else big
	for y in h:
		for x in w:
			var p := y * w + x
			var v := dist[p]
			if x > 0: v = mini(v, dist[p - 1] + 1)
			if y > 0: v = mini(v, dist[p - w] + 1)
			if x > 0 and y > 0: v = mini(v, dist[p - w - 1] + 1)
			if x < w - 1 and y > 0: v = mini(v, dist[p - w + 1] + 1)
			dist[p] = v
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var p := y * w + x
			var v := dist[p]
			if x < w - 1: v = mini(v, dist[p + 1] + 1)
			if y < h - 1: v = mini(v, dist[p + w] + 1)
			if x < w - 1 and y < h - 1: v = mini(v, dist[p + w + 1] + 1)
			if x > 0 and y < h - 1: v = mini(v, dist[p + w - 1] + 1)
			dist[p] = v
	# 3) 덩어리 밖은 거리에 따라 부드럽게 지우고, 남긴 덩어리가 아닌 불투명 픽셀(옆 조각)은 지운다
	var fade: float = opts.get("edge_fade", 0.0)
	for y in h:
		for x in w:
			var p := y * w + x
			var a := d[p * 4 + 3]
			if a == 0:
				continue
			var f := 1.0
			if label[p] != 0 and not keep_ids.has(label[p]):
				f = 0.0
			elif dist[p] > 0:
				var t := clampf(1.0 - float(dist[p]) / halo, 0.0, 1.0)
				f = t * t * (3.0 - 2.0 * t)
			if fade > 0.0:
				var e := minf(minf(float(x), float(w - 1 - x)), minf(float(y), float(h - 1 - y)))
				var g := clampf(e / fade, 0.0, 1.0)
				f *= g * g * (3.0 - 2.0 * g)
			d[p * 4 + 3] = int(a * f)
	img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, d)
	img = Catalog.defringe(img, 0.6)
	# 4) 투명한 둘레 잘라 내기 (2px 여유)
	var used := img.get_used_rect()
	if used.size.x <= 0:
		return img
	used = used.grow(2).intersection(Rect2i(0, 0, w, h))
	return img.get_region(used)


static func _erase(img: Image, r: Array) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := int(r[0] * w)
	var y0 := int(r[1] * h)
	var x1 := int(r[2] * w)
	var y1 := int(r[3] * h)
	const SOFT := 16.0
	for y in range(maxi(y0 - 16, 0), mini(y1 + 16, h)):
		for x in range(maxi(x0 - 16, 0), mini(x1 + 16, w)):
			var dx := maxf(float(x0 - x), float(x - x1))
			var dy := maxf(float(y0 - y), float(y - y1))
			var d := maxf(dx, dy)   # 상자 밖이면 양수
			var k := clampf(d / SOFT, 0.0, 1.0)
			if k >= 1.0:
				continue
			var c := img.get_pixel(x, y)
			c.a *= k
			img.set_pixel(x, y, c)


static func _write_import(png_path: String) -> void:
	var imp := png_path + ".import"
	if FileAccess.file_exists(imp):
		var txt := FileAccess.get_file_as_string(imp)
		if txt.contains("mipmaps/generate=true"):
			return
		txt = txt.replace("mipmaps/generate=false", "mipmaps/generate=true")
		var f := FileAccess.open(imp, FileAccess.WRITE)
		f.store_string(txt)
		return
	var f2 := FileAccess.open(imp, FileAccess.WRITE)
	f2.store_string("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\nmipmaps/generate=true\n")

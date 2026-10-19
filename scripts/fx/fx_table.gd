extends RefCounted
## 이펙트 표 (2026-10-19 이펙트 리뉴얼 F1). Fx.spawn("이름", 자리, opts) 의 '이름'이 여기 열쇠다.
## 그림은 art/fx/<tex>.png (tools/cut_fx.gd 가 기획자의 이펙트 시트에서 잘라 둔 것).
## 쓰는 법과 새 이펙트 더하는 법은 scripts/fx/README.md.
##
## 한 줄의 칸 (생략하면 괄호 안 기본값):
##   tex       그림 이름, 또는 여러 장 ["a", "b"] → 수명 동안 고르게 넘긴다 (프레임 묶음)
##   blend     "add"(빛, 기본) / "mix"(먼지·연기처럼 보통으로 덮기)
##   life      수명 초 (0.3)
##   scale     [처음 배율, 끝 배율] ([1, 1]) — 그림 픽셀 기준. ease 는 커지는 곡선의 세기 (2 = 빨리 커지다 느려짐)
##   scale_xy  가로·세로 배율 (Vector2(1, 1)) — 납작한 고리 등
##   fade_in   수명의 이 비율 동안 나타난다 (0)   fade_out  수명의 이 비율부터 사라진다 (0.6)
##   rot       회전(도, 오른쪽을 볼 때)  rot_rand  ± 무작위 회전  spin  도/초
##   vel       속도 px/초 (오른쪽 기준)  vel_rand  ± 무작위  gravity  아래로 px/초²  drag  감속 (1/초)
##   pivot     그림 안의 기준점 (UV, Vector2(0.5, 0.5)) — 땅에서 솟는 기둥은 (0.5, 0.95)
##   color     색 곱하기 (흰색)   energy  밝기 배수 (1; 1 보다 크면 HDR 글로우로 번진다)
##   palette   팔레트 이름 (아래 PALETTES, 없으면 그림 원래 색)   keep  원래 색을 남기는 비율 (0)
##   flicker   깜빡임 세기 0~1    flip_v  위아래 뒤집기
##   z         그리기 순서 (6 = 소녀·적 앞)   priority  0 먼지·알갱이 / 1 보통 / 2 중요 (가득 차면 낮은 것부터 비킨다)
##   wipe      호 드러내기 {center: UV 중심, a0: 시작 각도(도, 그림 기준·y 아래), span: 도는 각도(+ 시계 방향),
##             soft: 경계 너비, time: 머리가 끝까지 가는 수명 비율, tail_end: 끝날 때 남는 꼬리 (4 = 다 남음), glow: 머리 밝기}
##   hold      끌려가는(driven) 동안 멈춰 있는 수명 비율 (0.5)
##   children  딸린 이펙트 [[이름, 개수, 퍼짐 Vector2(px), {opts}], ...]
##
## 소녀의 칼질(slash_*)은 뼈대(selenia_rig.gd)가 휘두르기 진행에 맞춰 호의 머리를 끌고 간다 (driven).
## 그림 안의 호 모양(중심·시작 각도·도는 각도)은 그림마다 정해져 있어 ARCS 에 모아 두었다 (회전·뒤집기와 상관없다).

## 그림마다의 호 모양 (wipe 에 그대로 넣는다): 얇은 시작 끝 → 굵은 머리 쪽으로 시계 방향
## (각도는 tools 로 그림의 밝은 띠가 놓인 각도 범위를 재어 정했다: slash_crescent -130°~+85°, slash_big -150°~+130°)
## gap_hide 1: 호 범위 밖(큰 초승달 안쪽에 떠 있는 꽃잎들)은 그리지 않는다.
const ARC_CRESCENT := {"center": Vector2(0.3, 0.55), "a0": -134.0, "span": 224.0, "soft": 0.14, "time": 0.4, "tail_end": 0.2, "glow": 0.35, "gap_hide": 1.0}
const ARC_BIG := {"center": Vector2(0.42, 0.52), "a0": -153.0, "span": 288.0, "soft": 0.12, "time": 0.4, "tail_end": 0.25, "glow": 0.3, "gap_hide": 1.0}
const ARC_SWEEP := {"center": Vector2(0.15, 0.95), "a0": -95.0, "span": 105.0, "soft": 0.16, "time": 0.4, "tail_end": 0.2, "glow": 0.5}

## 팔레트: [어두운색, 가운데색, 밝은색] — 그림의 밝기를 이 세 색으로 다시 칠한다
const PALETTES := {
	"seed": [Color(0.05, 0.2, 0.08), Color(0.45, 0.82, 0.38), Color(0.93, 1.0, 0.82)],
	"wind": [Color(0.0, 0.22, 0.2), Color(0.22, 0.78, 0.62), Color(0.82, 1.0, 0.93)],
	"light": [Color(0.32, 0.15, 0.02), Color(1.0, 0.70, 0.22), Color(1.0, 0.98, 0.86)],
	"gold": [Color(0.3, 0.17, 0.04), Color(0.95, 0.75, 0.32), Color(1.0, 0.97, 0.85)],
	"heal": [Color(0.04, 0.22, 0.14), Color(0.48, 0.95, 0.62), Color(1.0, 1.0, 0.9)],
	"dust": [Color(0.22, 0.18, 0.14), Color(0.6, 0.54, 0.44), Color(0.9, 0.86, 0.76)],
	"ash": [Color(0.16, 0.16, 0.18), Color(0.5, 0.5, 0.54), Color(0.86, 0.86, 0.9)],
	"white": [Color(0.28, 0.33, 0.45), Color(0.76, 0.82, 0.92), Color(1.0, 1.0, 1.0)],
	"red": [Color(0.28, 0.02, 0.02), Color(1.0, 0.32, 0.2), Color(1.0, 0.9, 0.8)],
	"purple": [Color(0.14, 0.04, 0.28), Color(0.68, 0.42, 1.0), Color(0.98, 0.9, 1.0)],
	"blue": [Color(0.04, 0.1, 0.3), Color(0.38, 0.6, 0.98), Color(0.95, 0.98, 1.0)],
}

const EFFECTS := {
	# ===================== 셀레니아: 약공격 3연타 (뼈대가 끌고 간다) =====================
	# 1타 가로 베기: 칼이 뒤에서 아래를 지나 앞으로 (화면에서 반시계)
	"slash1": {"tex": "slash_crescent", "blend": "mix", "life": 0.3, "scale": [0.95, 1.0], "ease": 2.0, "fade_out": 0.55,
		"flip_v": true, "rot": 30.0, "pivot": Vector2(0.3, 0.55), "energy": 1.08, "hold": 0.4, "priority": 2,
		"wipe": ARC_CRESCENT},
	# 2타 올려 베기: 앞 아래에서 머리 위로 (반시계)
	"slash2": {"tex": "slash_crescent", "blend": "mix", "life": 0.3, "scale": [0.9, 0.95], "ease": 2.0, "fade_out": 0.55,
		"flip_v": true, "rot": -15.0, "pivot": Vector2(0.3, 0.55), "energy": 1.08, "hold": 0.4, "priority": 2,
		"wipe": ARC_CRESCENT},
	# 3타 내려 찍기: 머리 뒤에서 위를 넘어 앞 아래로 (시계) — 가장 크고 밝다
	"slash3": {"tex": "slash_big", "blend": "mix", "life": 0.36, "scale": [0.45, 0.48], "ease": 2.0, "fade_out": 0.5,
		"rot": -5.0, "pivot": Vector2(0.42, 0.52), "energy": 1.1, "hold": 0.4, "priority": 2,
		"wipe": ARC_BIG},
	# ===================== 셀레니아: 영혼 기술 =====================
	# 씨앗 '넓은 베기': 큰 초승달 (초록 팔레트). 판정 상자(앞 340, 위 250, 아래 180)를 거의 채운다
	"seed_slash": {"tex": "slash_big", "blend": "mix", "life": 0.5, "scale": [1.0, 1.03], "scale_xy": Vector2(1.3, 1.45), "ease": 2.0,
		"fade_out": 0.45, "pivot": Vector2(0.42, 0.52), "palette": "seed", "keep": 0.3, "color": Color(1, 1, 1, 0.85),
		"energy": 1.08, "hold": 0.4, "priority": 2,
		"wipe": ARC_BIG},
	# 바람·빛이 적에 닿았을 때
	"wind_hit": {"tex": "star_burst", "life": 0.3, "scale": [0.3, 0.55], "ease": 3.0, "fade_out": 0.3, "rot_rand": 180.0,
		"palette": "wind", "energy": 1.1, "children": [["ring_pop", 1, Vector2.ZERO, {"palette": "wind"}]]},
	"laser_hit": {"tex": "star_burst", "life": 0.32, "scale": [0.3, 0.55], "ease": 3.0, "fade_out": 0.3, "rot_rand": 180.0,
		"palette": "light", "energy": 1.1, "children": [["ring_pop", 1, Vector2.ZERO, {"palette": "light"}]]},
	# 바람 초승달 검기: 꼬리에 흘리는 빛 알갱이 / 벽에 닿거나 사라질 때
	"wind_wisp": {"tex": "glint", "life": 0.4, "scale": [0.28, 0.12], "ease": 1.0, "fade_out": 0.3, "rot_rand": 30.0, "drag": 2.0,
		"palette": "wind", "energy": 1.1, "priority": 0},
	"wind_fade": {"tex": "crescent_small", "life": 0.28, "scale": [1.1, 1.6], "ease": 3.0, "fade_out": 0.1, "palette": "wind",
		"energy": 1.0, "priority": 1},
	# 레이저: 쏘는 순간 손의 번쩍임 / 벽에 닿은 자리
	"laser_flash": {"tex": "star_burst", "life": 0.22, "scale": [0.25, 0.45], "ease": 3.0, "fade_out": 0.3, "palette": "light", "keep": 0.2,
		"energy": 1.1, "priority": 2},
	"laser_wall": {"tex": "star_crescent", "life": 0.4, "scale": [0.3, 0.5], "ease": 3.0, "fade_out": 0.35, "rot": 180.0, "palette": "light",
		"energy": 1.05, "priority": 1},
	# 영혼 전환: 달빛 소용돌이 + 고리 (opts.palette 로 새 영혼 색)
	"soul_switch": {"tex": "moon_burst", "life": 0.5, "scale": [0.28, 0.42], "ease": 3.0, "fade_in": 0.08, "fade_out": 0.45,
		"pivot": Vector2(0.5, 0.62), "energy": 1.0, "priority": 1,
		"children": [["ring_pop", 1, Vector2(0, 0), {"offset": Vector2(0, -8), "scale": 1.4}]]},
	# ===================== 셀레니아: 움직임·방어·회복 =====================
	# 낙하 공격: 내리꽂는 동안 머리 위로 남는 빛줄기 (소녀를 따라간다, 착지하면 놓는다)
	"plunge_trail": {"tex": "wisp_beam2", "life": 0.42, "scale": [0.5, 0.55], "scale_xy": Vector2(1.0, 0.8), "rot": 90.0,
		"pivot": Vector2(0.97, 0.5), "fade_in": 0.05, "fade_out": 0.35, "color": Color(1, 1, 1, 0.8), "hold": 0.3, "priority": 1},
	# 낙하 공격 착지: 땅에서 터지는 빛 + 납작한 고리 + 양옆 먼지
	"plunge_impact": {"tex": "ground_burst", "blend": "mix", "life": 0.42, "scale": [0.36, 0.52], "ease": 3.0, "fade_out": 0.3,
		"pivot": Vector2(0.5, 0.78), "energy": 1.05, "priority": 2,
		"children": [["ground_ring", 1, Vector2.ZERO, {"scale": 1.3}], ["dust_puff", 1, Vector2(6, 0), {"vel": Vector2(-150, -30), "offset": Vector2(-30, -10)}],
			["dust_puff", 1, Vector2(6, 0), {"vel": Vector2(150, -30), "offset": Vector2(30, -10)}]]},
	# 땅 위 납작한 빛 고리 (착지·충격)
	"ground_ring": {"tex": "ripple", "life": 0.4, "scale": [0.3, 0.75], "ease": 3.0, "fade_out": 0.3, "scale_xy": Vector2(1.0, 0.7),
		"pivot": Vector2(0.5, 0.6), "color": Color(1, 1, 1, 0.8), "priority": 1},
	# 착지 먼지: 발밑 납작한 먼지 고리 + 양옆으로 퍼지는 작은 뭉게 먼지
	"land_dust": {"tex": "ripple", "blend": "mix", "life": 0.35, "scale": [0.22, 0.42], "ease": 3.0, "fade_out": 0.3,
		"scale_xy": Vector2(1.0, 0.45), "pivot": Vector2(0.5, 0.6), "palette": "dust", "color": Color(1, 1, 1, 0.7), "priority": 0,
		"children": [["dust_puff", 1, Vector2(4, 0), {"vel": Vector2(-90, -20), "offset": Vector2(-20, -6), "scale": 0.7}],
			["dust_puff", 1, Vector2(4, 0), {"vel": Vector2(90, -20), "offset": Vector2(20, -6), "scale": 0.7}]]},
	"dust_puff": {"tex": "puff", "blend": "mix", "life": 0.45, "scale": [0.22, 0.4], "ease": 2.0, "fade_out": 0.25, "rot_rand": 20.0,
		"drag": 3.0, "palette": "dust", "color": Color(1, 1, 1, 0.75), "priority": 0},
	# 구르기: 몸 뒤로 흐르는 빛줄기 (소녀를 따라간다)
	"dodge_trail": {"tex": "wisp_beam", "life": 0.34, "scale": [0.36, 0.44], "scale_xy": Vector2(1.0, 1.5), "pivot": Vector2(0.92, 0.5),
		"fade_in": 0.1, "fade_out": 0.3, "color": Color(1, 1, 1, 0.45), "priority": 1},
	# 이단 점프: 발밑의 납작한 바람 고리
	"air_ring": {"tex": "ring", "life": 0.3, "scale": [0.35, 1.0], "ease": 3.0, "fade_out": 0.3, "scale_xy": Vector2(1.0, 0.32),
		"palette": "wind", "energy": 1.1, "priority": 0},
	# 가드로 막음: 앞쪽 방패 번쩍임
	"guard_hit": {"tex": "shield_arc", "life": 0.24, "scale": [0.42, 0.5], "ease": 3.0, "fade_out": 0.3, "energy": 1.1, "priority": 1,
		"children": [["ring_pop", 1, Vector2.ZERO, {"scale": 0.7}]]},
	# 저스트 가드: 별처럼 터지는 빛 + 넓게 퍼지는 고리
	"just_guard": {"tex": "star_burst", "life": 0.36, "scale": [0.28, 0.55], "ease": 3.0, "fade_out": 0.35, "rot_rand": 25.0,
		"energy": 1.15, "palette": "gold", "keep": 0.35, "priority": 2,
		"children": [["ring_pop", 1, Vector2.ZERO, {"scale": 1.6, "palette": "white"}]]},
	"ring_pop": {"tex": "ring", "life": 0.28, "scale": [0.3, 0.9], "ease": 3.0, "fade_out": 0.25, "energy": 1.05, "priority": 1},
	# 회복: 발밑에서 솟는 백합 빛 기둥 + 떠오르는 빛 알갱이
	"heal": {"tex": "pillar_lily", "life": 0.85, "scale": [0.42, 0.48], "ease": 2.0, "fade_in": 0.12, "fade_out": 0.5,
		"pivot": Vector2(0.5, 0.93), "color": Color(0.85, 0.9, 0.85, 1.0), "priority": 1,
		"children": [["mote", 5, Vector2(36, 20), {"offset": Vector2(0, -30), "palette": "heal"}]]},
	# 정화의 손길: 대상 위에 감아 오르는 금빛 기둥 + 별빛 + 떠오르는 알갱이
	"purify": {"tex": "pillar_spiral", "life": 1.0, "scale": [0.5, 0.56], "ease": 2.0, "fade_in": 0.1, "fade_out": 0.5,
		"pivot": Vector2(0.5, 0.92), "palette": "gold", "keep": 0.25, "color": Color(0.8, 0.78, 0.7, 1.0), "priority": 1,
		"children": [["purify_flash", 1, Vector2.ZERO, {"offset": Vector2(0, -70)}], ["mote", 8, Vector2(46, 30), {"offset": Vector2(0, -60), "palette": "gold"}]]},
	"purify_flash": {"tex": "crystal_burst", "life": 0.55, "scale": [0.35, 0.6], "ease": 3.0, "fade_out": 0.35, "palette": "gold", "keep": 0.2,
		"energy": 1.0, "priority": 1},
	# 떠오르는 작은 빛 알갱이 (회복·정화·줍기)
	"mote": {"tex": "glint", "life": 0.9, "scale": [0.22, 0.12], "ease": 1.0, "fade_in": 0.12, "fade_out": 0.45, "vel": Vector2(0, -90),
		"vel_rand": Vector2(40, 35), "drag": 0.8, "spin": 60.0, "rot_rand": 40.0, "energy": 1.2, "priority": 0},
	# 셀레니아가 쓰러짐: 하얀 연기 고리 + 알갱이
	"selenia_down": {"tex": "smoke_ring", "blend": "mix", "life": 0.9, "scale": [0.45, 0.8], "ease": 2.0, "fade_out": 0.4, "vel": Vector2(0, -25),
		"palette": "white", "color": Color(1, 1, 1, 0.5), "priority": 1,
		"children": [["mote", 6, Vector2(40, 20), {"palette": "white"}]]},
	# ===================== 적·줍기 (모든 적·보스 공용) =====================
	# 소녀의 공격이 닿은 자리
	"hit_spark": {"tex": "star_burst", "life": 0.22, "scale": [0.18, 0.36], "ease": 3.0, "fade_out": 0.35, "rot_rand": 180.0,
		"energy": 1.1, "priority": 1, "children": [["hit_glint", 1]]},
	"hit_glint": {"tex": "glint", "life": 0.16, "scale": [0.5, 1.1], "ease": 3.0, "fade_out": 0.3, "rot_rand": 30.0, "energy": 1.2, "priority": 0},
	# 큰 타격 (씨앗 베기·낙하 공격)
	"hit_spark_big": {"tex": "star_burst", "life": 0.3, "scale": [0.28, 0.55], "ease": 3.0, "fade_out": 0.35, "rot_rand": 180.0,
		"energy": 1.15, "priority": 1, "children": [["hit_glint", 1, Vector2.ZERO, {"scale": 1.5}], ["ring_pop", 1, Vector2.ZERO, {"scale": 0.8}]]},
	# 적의 흐트러짐이 가득 차 무너짐: 금빛 별 + 고리
	"break_burst": {"tex": "star_crescent", "life": 0.55, "scale": [0.35, 0.62], "ease": 3.0, "fade_out": 0.4, "palette": "gold", "keep": 0.2,
		"energy": 1.1, "priority": 2, "children": [["ring_pop", 1, Vector2.ZERO, {"scale": 2.2, "palette": "gold"}]]},
	# 적이 쓰러져 사라짐: 잿빛 연기 고리 + 양옆 먼지
	"death_dust": {"tex": "smoke_ring", "blend": "mix", "life": 0.8, "scale": [0.5, 0.95], "ease": 2.0, "fade_out": 0.35, "vel": Vector2(0, -30),
		"palette": "ash", "color": Color(1, 1, 1, 0.6), "priority": 1,
		"children": [["dust_puff", 1, Vector2(10, 4), {"vel": Vector2(-110, -40), "offset": Vector2(-30, 10), "palette": "ash"}],
			["dust_puff", 1, Vector2(10, 4), {"vel": Vector2(110, -40), "offset": Vector2(30, 10), "palette": "ash"}]]},
	# 빛 가루·이슬·성장 구슬을 주웠을 때
	"pickup_sparkle": {"tex": "glint", "life": 0.22, "scale": [0.2, 0.45], "ease": 3.0, "fade_out": 0.3, "spin": 120.0, "rot_rand": 90.0, "palette": "gold",
		"energy": 1.2, "priority": 0},
	"pickup_big": {"tex": "star_burst", "life": 0.45, "scale": [0.25, 0.5], "ease": 3.0, "fade_out": 0.35, "palette": "gold", "keep": 0.3,
		"energy": 1.1, "priority": 1, "children": [["ring_pop", 1, Vector2.ZERO, {"scale": 1.6, "palette": "gold"}], ["mote", 6, Vector2(30, 20), {"palette": "gold"}]]},
}

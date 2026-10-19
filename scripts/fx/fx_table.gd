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
	# ---- F2 (보스·적 기술) ----
	"fire": [Color(0.32, 0.07, 0.0), Color(1.0, 0.6, 0.18), Color(1.0, 0.96, 0.72)],    # 등불 기사의 불꽃 (주황~노랑: 가드 가능)
	"ember": [Color(0.22, 0.02, 0.0), Color(0.95, 0.32, 0.06), Color(1.0, 0.78, 0.4)],  # 불씨 (더 붉다)
	"sap": [Color(0.02, 0.16, 0.2), Color(0.32, 0.8, 0.85), Color(0.9, 1.0, 1.0)],      # 수액 (청록)
	"spore": [Color(0.1, 0.18, 0.04), Color(0.68, 0.95, 0.4), Color(1.0, 1.0, 0.82)],   # 포자 (연두)
	"moon": [Color(0.1, 0.08, 0.3), Color(0.62, 0.66, 1.0), Color(0.97, 0.97, 1.0)],    # 달빛 (푸른 보랏빛)
	"danger": [Color(0.22, 0.02, 0.02), Color(0.95, 0.2, 0.12), Color(1.0, 0.82, 0.7)], # 가드 불가 (진한 붉은빛)
	"steam": [Color(0.42, 0.44, 0.48), Color(0.82, 0.84, 0.88), Color(1.0, 1.0, 1.0)],  # 김
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
		"pivot": Vector2(0.5, 0.93), "color": Color(0.95, 1.0, 0.95, 1.0), "priority": 1,
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
	# 프레임 묶음의 예: 반짝임(glint) → 고리(ring) 두 장을 수명 동안 넘긴다
	"pickup_sparkle": {"tex": ["glint", "ring"], "life": 0.24, "scale": [0.2, 0.45], "ease": 3.0, "fade_out": 0.3, "spin": 120.0, "rot_rand": 90.0, "palette": "gold",
		"energy": 1.2, "priority": 0},
	"pickup_big": {"tex": "star_burst", "life": 0.45, "scale": [0.25, 0.5], "ease": 3.0, "fade_out": 0.35, "palette": "gold", "keep": 0.3,
		"energy": 1.1, "priority": 1, "children": [["ring_pop", 1, Vector2.ZERO, {"scale": 1.6, "palette": "gold"}], ["mote", 6, Vector2(30, 20), {"palette": "gold"}]]},

	# =====================================================================================
	# ===================== F2: 보스·적 기술 이펙트, 물 이펙트 (2026-10-19) =====================
	# 대부분 보스·적 논리에 붙은 이펙트 관찰자(scripts/fx/*_fx.gd)나 공격 노드(투사체·뿌리·수액)가 띄운다.
	# 가드 불가 공격의 예고·불꽃은 "danger"(진한 붉은빛) 팔레트로 — 붉은 예고 원칙.
	# ===================== 공용: 불씨·불꽃·김·물방울 =====================
	# 위로 떠오르는 불씨 (등불 기사)
	"ember": {"tex": "glint", "life": 0.8, "scale": [0.24, 0.1], "ease": 1.0, "fade_in": 0.1, "fade_out": 0.5, "vel": Vector2(0, -110),
		"vel_rand": Vector2(70, 40), "drag": 0.8, "spin": 90.0, "rot_rand": 40.0, "palette": "ember", "energy": 1.15, "priority": 0},
	# 가드 불가 예고 동안 몸에서 피어오르는 붉은 불티
	"danger_ember": {"tex": "glint", "life": 0.6, "scale": [0.3, 0.12], "ease": 1.0, "fade_in": 0.1, "fade_out": 0.45, "vel": Vector2(0, -170),
		"vel_rand": Vector2(50, 40), "drag": 0.6, "rot_rand": 30.0, "palette": "danger", "energy": 1.15, "priority": 1},
	# 튀는 불똥 (기계 드릴·창이 박힘·펌프)
	"spark": {"tex": "glint", "life": 0.38, "scale": [0.26, 0.08], "ease": 1.0, "fade_out": 0.5, "vel": Vector2(0, -170), "vel_rand": Vector2(300, 220),
		"gravity": 1100.0, "rot_rand": 90.0, "palette": "fire", "energy": 1.15, "priority": 0},
	# 김 (무쇠 펌프)
	"steam_puff": {"tex": "puff", "blend": "mix", "life": 0.9, "scale": [0.35, 0.85], "ease": 2.0, "fade_out": 0.4, "vel": Vector2(0, -90),
		"vel_rand": Vector2(40, 25), "drag": 1.2, "rot_rand": 40.0, "palette": "steam", "keep": 0.3, "color": Color(1, 1, 1, 0.6), "priority": 0},
	"danger_steam": {"tex": "puff", "blend": "mix", "life": 0.6, "scale": [0.3, 0.7], "ease": 2.0, "fade_out": 0.4, "vel": Vector2(0, -120),
		"vel_rand": Vector2(50, 30), "drag": 1.2, "rot_rand": 40.0, "palette": "danger", "keep": 0.25, "color": Color(1, 1, 1, 0.7), "priority": 1},
	# 김 구멍에서 위로 뿜는 김 줄기 (무쇠 펌프)
	"vent_steam": {"tex": "steam_column", "blend": "mix", "life": 0.75, "scale": [0.45, 0.85], "ease": 2.0, "fade_out": 0.45, "pivot": Vector2(0.5, 0.95),
		"vel": Vector2(0, -40), "palette": "steam", "keep": 0.3, "color": Color(1, 1, 1, 0.65), "priority": 0},
	"danger_vent": {"tex": "steam_column", "blend": "mix", "life": 0.55, "scale": [0.45, 0.8], "ease": 2.0, "fade_out": 0.45, "pivot": Vector2(0.5, 0.95),
		"vel": Vector2(0, -60), "palette": "danger", "keep": 0.25, "color": Color(1, 1, 1, 0.75), "priority": 1},
	# 수액 방울 (튀어 오르다 떨어진다) / 떨어지는 방울
	"sap_droplet": {"tex": "drop", "blend": "mix", "life": 0.55, "scale": [0.32, 0.26], "ease": 1.0, "fade_out": 0.6, "vel": Vector2(0, -260),
		"vel_rand": Vector2(170, 90), "gravity": 1300.0, "rot_rand": 30.0, "palette": "sap", "keep": 0.45, "priority": 0},
	"sap_drip": {"tex": "drop", "blend": "mix", "life": 0.55, "scale": [0.3, 0.34], "ease": 1.0, "fade_in": 0.1, "fade_out": 0.8, "vel": Vector2(0, 40),
		"gravity": 1500.0, "palette": "sap", "keep": 0.45, "priority": 0},
	"sap_glint": {"tex": "glint", "life": 0.6, "scale": [0.26, 0.1], "ease": 1.0, "fade_out": 0.45, "vel_rand": Vector2(120, 120), "drag": 2.0,
		"spin": 140.0, "rot_rand": 90.0, "palette": "sap", "energy": 1.15, "priority": 0},
	# 붉은 예고 고리 (불기둥이 설 자리 등): 바닥에 납작하게 깜빡인다
	"danger_ring": {"tex": "ripple", "life": 0.4, "scale": [0.22, 0.5], "ease": 2.0, "fade_in": 0.25, "fade_out": 0.8, "scale_xy": Vector2(1.0, 0.6),
		"pivot": Vector2(0.5, 0.6), "palette": "danger", "energy": 1.1, "flicker": 0.3, "priority": 2},
	# 보스가 무너짐 / 쓰러짐 (공용 이펙트를 크게)
	"boss_break": {"tex": "star_crescent", "life": 0.7, "scale": [0.6, 1.05], "ease": 3.0, "fade_out": 0.45, "palette": "gold", "keep": 0.2,
		"energy": 1.1, "priority": 2, "children": [["ring_pop", 1, Vector2.ZERO, {"scale": 3.6, "palette": "gold"}], ["mote", 8, Vector2(70, 50), {"palette": "gold"}]]},
	"boss_fall": {"tex": "smoke_ring", "blend": "mix", "life": 1.1, "scale": [0.9, 1.7], "ease": 2.0, "fade_out": 0.4, "vel": Vector2(0, -30),
		"palette": "ash", "color": Color(1, 1, 1, 0.6), "priority": 2,
		"children": [["dust_puff", 3, Vector2(60, 6), {"vel": Vector2(-180, -40), "offset": Vector2(-90, 10), "scale": 1.6}],
			["dust_puff", 3, Vector2(60, 6), {"vel": Vector2(180, -40), "offset": Vector2(90, 10), "scale": 1.6}]]},
	# ===================== 잿빛 잎새의 새 =====================
	# 날갯바람 예고: 새 몸에 모여드는 붉은 바람 소용돌이 (가드 불가)
	"gust_gather": {"tex": "gust_double", "blend": "mix", "life": 0.8, "scale": [1.5, 0.55], "ease": 1.5, "fade_in": 0.15, "fade_out": 0.8,
		"spin": 300.0, "palette": "red", "keep": 0.2, "energy": 1.1, "z": 7, "priority": 2},
	# 날갯바람: 화면을 가로지르는 붉은 금빛 바람 줄기 (opts.vel 로 바람 방향)
	"gust_streak": {"tex": "leaf_stream", "blend": "mix", "life": 0.75, "scale": [0.55, 0.7], "ease": 1.0, "fade_in": 0.15, "fade_out": 0.55,
		"palette": "red", "keep": 0.3, "color": Color(1, 1, 1, 0.55), "priority": 1},
	"gust_crescent_fly": {"tex": "gust_crescent", "blend": "mix", "life": 0.6, "scale": [0.42, 0.55], "ease": 1.0, "fade_in": 0.12, "fade_out": 0.5,
		"palette": "red", "keep": 0.3, "color": Color(1, 1, 1, 0.85), "priority": 1},
	# 바람에 굴러가는 잎 / 잎 더미에서 부리로 빨려 드는 잎
	"gust_leaf": {"tex": "leaf_c", "blend": "mix", "life": 0.9, "scale": [0.7, 0.55], "ease": 1.0, "fade_out": 0.7, "spin": 620.0, "rot_rand": 180.0,
		"palette": "ash", "keep": 0.5, "priority": 0},
	"leaf_suck": {"tex": "leaf_b", "blend": "mix", "life": 0.5, "scale": [0.75, 0.3], "ease": 1.0, "fade_in": 0.1, "fade_out": 0.7, "spin": 500.0,
		"rot_rand": 180.0, "palette": "ash", "keep": 0.45, "priority": 0},
	# 2페이즈 잎 회오리: 새 몸을 감싸 도는 잎 소용돌이 (새를 따라간다, opts.life = 흩날리기 길이)
	"leaf_tornado": {"tex": "leaf_swirl", "blend": "mix", "life": 3.5, "scale": [1.15, 1.35], "ease": 1.0, "fade_in": 0.08, "fade_out": 0.88,
		"spin": 240.0, "palette": "ash", "keep": 0.55, "color": Color(1, 1, 1, 0.85), "z": 7, "priority": 2},
	# 깃털 화살이 나가는 순간 부리 앞 금빛 번쩍임
	"feather_flash": {"tex": "star_burst", "life": 0.2, "scale": [0.16, 0.32], "ease": 3.0, "fade_out": 0.3, "rot_rand": 180.0, "palette": "gold",
		"energy": 1.1, "priority": 1},
	# 내려앉기 / 날아오르기: 발밑에서 잎 무더기가 터진다
	"bird_land": {"tex": "leaf_burst", "blend": "mix", "life": 0.65, "scale": [0.8, 1.15], "ease": 3.0, "fade_out": 0.4, "pivot": Vector2(0.5, 0.86),
		"palette": "ash", "keep": 0.5, "priority": 1,
		"children": [["dust_puff", 2, Vector2(20, 4), {"vel": Vector2(-200, -40), "offset": Vector2(-60, -6), "scale": 1.3}],
			["dust_puff", 2, Vector2(20, 4), {"vel": Vector2(200, -40), "offset": Vector2(60, -6), "scale": 1.3}]]},
	# 날개 휘두르기: 앞을 쓸어내리는 잿빛 바람 초승달
	"wing_sweep": {"tex": "gust_crescent", "blend": "mix", "life": 0.34, "scale": [0.6, 0.7], "ease": 3.0, "fade_out": 0.45, "palette": "ash",
		"keep": 0.55, "energy": 1.05, "priority": 2, "children": [["gust_leaf", 3, Vector2(60, 40)]]},
	# 부리 찍기: 부리 끝의 별빛 + 잎 부스러기
	"peck_burst": {"tex": "star_burst", "life": 0.28, "scale": [0.32, 0.6], "ease": 3.0, "fade_out": 0.35, "rot_rand": 180.0, "palette": "ash", "keep": 0.4,
		"energy": 1.1, "priority": 1, "children": [["gust_leaf", 2, Vector2(20, 20)]]},
	# 잎 삼키기를 끊었을 때 / 잎 더미가 먹혀 흩어질 때
	"pile_burst": {"tex": "leaf_burst", "blend": "mix", "life": 0.55, "scale": [0.4, 0.6], "ease": 3.0, "fade_out": 0.4, "pivot": Vector2(0.5, 0.86),
		"palette": "ash", "keep": 0.5, "priority": 1, "children": [["gust_leaf", 4, Vector2(60, 20)]]},
	# ===================== 등불 기사 =====================
	# 창 찌르기: 창끝을 따라 앞으로 뻗는 불빛 줄기 (뒤끝 기준으로 자란다)
	"spear_thrust": {"tex": "lance_streak", "blend": "mix", "life": 0.28, "scale": [1.25, 1.6], "ease": 3.0, "fade_out": 0.4, "scale_xy": Vector2(1.0, 0.75),
		"pivot": Vector2(0.04, 0.58), "palette": "fire", "keep": 0.2, "energy": 1.05, "priority": 2,
		"children": [["ember", 3, Vector2(120, 20), {"offset": Vector2(220, 0)}]]},
	# 창·등불 휘두르기: 앞을 가르는 불꽃 초승달
	"spear_swing": {"tex": "gust_crescent", "blend": "mix", "life": 0.32, "scale": [0.6, 0.68], "ease": 3.0, "fade_out": 0.45, "palette": "fire", "keep": 0.15,
		"energy": 1.05, "priority": 2, "children": [["ember", 4, Vector2(80, 60)]]},
	# 3연격 마지막 올려치기 (가드 불가): 진한 붉은 초승달
	"spear_upper": {"tex": "gust_crescent", "blend": "mix", "life": 0.36, "scale": [0.62, 0.72], "ease": 3.0, "fade_out": 0.45, "rot": -70.0,
		"palette": "danger", "keep": 0.2, "energy": 1.08, "priority": 2, "children": [["danger_ember", 4, Vector2(60, 80)]]},
	# 등불 휘두르기 → 불꽃 파도: 앞쪽의 큰 불꽃 호
	"lantern_arc": {"tex": "gust_double", "blend": "mix", "life": 0.4, "scale": [0.55, 0.66], "ease": 3.0, "fade_out": 0.45, "palette": "fire", "keep": 0.12,
		"energy": 1.05, "priority": 2, "children": [["ember", 6, Vector2(90, 70)]]},
	# 내려찍기 착지 (가드 불가): 땅에서 터지는 불꽃 + 납작한 붉은 고리 + 양옆 먼지 + 불씨
	"knight_slam": {"tex": "ground_burst", "blend": "mix", "life": 0.5, "scale": [0.5, 0.72], "ease": 3.0, "fade_out": 0.35, "pivot": Vector2(0.5, 0.78),
		"palette": "fire", "keep": 0.15, "energy": 1.05, "priority": 2,
		"children": [["ground_ring", 1, Vector2.ZERO, {"scale": 2.6, "palette": "danger"}],
			["dust_puff", 2, Vector2(20, 4), {"vel": Vector2(-240, -50), "offset": Vector2(-100, -8), "scale": 1.5}],
			["dust_puff", 2, Vector2(20, 4), {"vel": Vector2(240, -50), "offset": Vector2(100, -8), "scale": 1.5}],
			["ember", 8, Vector2(160, 30), {"offset": Vector2(0, -40)}]]},
	# 돌진: 뒤로 끌리는 불빛 줄기 (몸을 따라간다)
	"charge_streak": {"tex": "wisp_beam", "life": 0.26, "scale": [0.5, 0.56], "scale_xy": Vector2(1.0, 0.7), "pivot": Vector2(0.95, 0.5),
		"fade_in": 0.1, "fade_out": 0.4, "palette": "fire", "color": Color(1, 1, 1, 0.55), "priority": 1},
	# 창이 벽에 박힘: 불똥 + 별빛
	"spear_stuck": {"tex": "star_burst", "life": 0.36, "scale": [0.42, 0.8], "ease": 3.0, "fade_out": 0.35, "rot_rand": 180.0, "palette": "fire",
		"energy": 1.1, "priority": 1, "children": [["spark", 8, Vector2(10, 10)], ["dust_puff", 2, Vector2(20, 30)]]},
	# 등불 회전: 고리 한 겹마다 퍼지는 불꽃 고리
	"fire_ring": {"tex": "ring", "life": 0.42, "scale": [0.8, 3.2], "ease": 3.0, "fade_out": 0.35, "scale_xy": Vector2(1.0, 0.42), "palette": "fire",
		"energy": 1.08, "priority": 1, "children": [["ember", 5, Vector2(110, 30)]]},
	# 불기둥이 솟는 순간 바닥의 불꽃
	"fire_pillar_burst": {"tex": "ground_burst", "blend": "mix", "life": 0.45, "scale": [0.3, 0.45], "ease": 3.0, "fade_out": 0.35, "pivot": Vector2(0.5, 0.78),
		"palette": "fire", "keep": 0.15, "priority": 1, "children": [["ember", 8, Vector2(50, 20), {"offset": Vector2(0, -60)}]]},
	# 검기가 날아가는 순간 창끝의 번쩍임
	"wave_flash": {"tex": "star_crescent", "life": 0.3, "scale": [0.22, 0.4], "ease": 3.0, "fade_out": 0.35, "palette": "fire", "keep": 0.2,
		"energy": 1.05, "priority": 1},
	# ===================== 뿌리지기 =====================
	# 지팡이 휘두르기: 꽃잎 섞인 보랏빛 초승달 (되돌려 베기는 위아래 뒤집어 올려 벤다)
	"staff_arc": {"tex": "moon_arc", "blend": "mix", "life": 0.38, "scale": [0.68, 0.76], "ease": 3.0, "fade_out": 0.45, "energy": 1.05, "priority": 2,
		"children": [["mote", 4, Vector2(90, 60), {"palette": "moon"}]]},
	# 달빛 구슬이 생길 때 지팡이 머리의 번쩍임
	"orb_charge": {"tex": "star_burst", "life": 0.3, "scale": [0.22, 0.45], "ease": 3.0, "fade_out": 0.35, "rot_rand": 180.0, "palette": "moon",
		"energy": 1.1, "priority": 1, "children": [["ring_pop", 1, Vector2.ZERO, {"palette": "moon"}]]},
	# 지팡이 내려찍기 (가드 불가): 붉은 뿌리 덩어리 터짐 + 붉은 고리 + 먼지
	"root_stomp": {"tex": "root_burst", "blend": "mix", "life": 0.55, "scale": [0.7, 1.0], "ease": 3.0, "fade_out": 0.4, "pivot": Vector2(0.5, 0.9),
		"palette": "danger", "keep": 0.5, "priority": 2,
		"children": [["ground_ring", 1, Vector2.ZERO, {"scale": 2.6, "palette": "danger"}],
			["dust_puff", 2, Vector2(20, 4), {"vel": Vector2(-220, -50), "offset": Vector2(-80, -8), "scale": 1.4}],
			["dust_puff", 2, Vector2(20, 4), {"vel": Vector2(220, -50), "offset": Vector2(80, -8), "scale": 1.4}]]},
	# 2페이즈에 다시 일어서는 순간: 감아 오르는 달빛 기둥 + 빛 알갱이
	"rise_pillar": {"tex": "pillar_spiral", "life": 2.6, "scale": [0.7, 0.82], "ease": 2.0, "fade_in": 0.15, "fade_out": 0.6, "pivot": Vector2(0.5, 0.92),
		"palette": "moon", "keep": 0.25, "color": Color(0.9, 0.9, 1.0, 0.95), "priority": 2,
		"children": [["mote", 10, Vector2(80, 40), {"offset": Vector2(0, -120), "palette": "moon"}]]},
	# 달빛 고리가 퍼지기 시작할 때
	"ring_flash": {"tex": "ring", "life": 0.45, "scale": [0.6, 2.4], "ease": 3.0, "fade_out": 0.35, "palette": "moon", "energy": 1.08, "priority": 1},
	# 씨앗이 땅에 닿아 터짐 / 뿌리 손이 솟는 자리의 흙 터짐
	"seed_land": {"tex": "seed_burst", "blend": "mix", "life": 0.4, "scale": [0.3, 0.5], "ease": 3.0, "fade_out": 0.35, "pivot": Vector2(0.5, 0.86),
		"priority": 1},
	"root_burst_fx": {"tex": "root_burst", "blend": "mix", "life": 0.45, "scale": [0.5, 0.75], "ease": 3.0, "fade_out": 0.35, "pivot": Vector2(0.5, 0.9),
		"priority": 1, "children": [["dust_puff", 2, Vector2(50, 6), {"scale": 1.2}]]},
	# ===================== 수액의 여왕 =====================
	# 날개가루를 흩뿌리는 순간: 날개에서 터지는 수액빛 별 + 반짝이
	"wing_dust_burst": {"tex": "star_burst", "life": 0.35, "scale": [0.3, 0.6], "ease": 3.0, "fade_out": 0.35, "rot_rand": 180.0, "palette": "sap",
		"energy": 1.1, "priority": 1, "children": [["sap_glint", 6, Vector2(50, 30)]]},
	# 나비 떼를 풀어 놓는 순간
	"butterfly_burst": {"tex": "ring", "life": 0.4, "scale": [0.4, 1.6], "ease": 3.0, "fade_out": 0.35, "palette": "sap", "energy": 1.08, "priority": 1,
		"children": [["sap_glint", 5, Vector2(40, 30)]]},
	# 수면을 치는 물보라 (물결을 띄울 때·내려앉을 때)
	"sap_splash": {"tex": "water_splash", "blend": "mix", "life": 0.5, "scale": [0.42, 0.6], "ease": 3.0, "fade_out": 0.4, "pivot": Vector2(0.5, 0.9),
		"palette": "sap", "keep": 0.45, "priority": 1, "children": [["sap_droplet", 4, Vector2(40, 6), {"offset": Vector2(0, -30)}]]},
	"queen_land": {"tex": "splash_crown", "blend": "mix", "life": 0.55, "scale": [0.6, 0.85], "ease": 3.0, "fade_out": 0.4, "pivot": Vector2(0.5, 0.85),
		"palette": "sap", "keep": 0.45, "priority": 2,
		"children": [["ground_ring", 1, Vector2.ZERO, {"scale": 2.2, "palette": "sap"}], ["sap_droplet", 6, Vector2(80, 6), {"offset": Vector2(0, -20)}]]},
	# ===================== 무쇠 펌프 · 작은 펌프 · 물 =====================
	# 피스톤이 땅을 침: 물보라 + 왕관 물보라 + 김 + 납작한 고리
	"pump_slam": {"tex": "water_splash", "blend": "mix", "life": 0.55, "scale": [0.6, 0.85], "ease": 3.0, "fade_out": 0.4, "pivot": Vector2(0.5, 0.9),
		"palette": "sap", "keep": 0.4, "priority": 2,
		"children": [["ground_ring", 1, Vector2.ZERO, {"scale": 2.6, "palette": "sap"}], ["steam_puff", 3, Vector2(70, 10), {"offset": Vector2(0, -30)}],
			["sap_droplet", 6, Vector2(60, 6), {"offset": Vector2(0, -30)}]]},
	# 관·대롱에서 수액이 뿜어지는 순간: 짧은 물줄기 + 방울 (opts.rot 로 쏘는 방향)
	"sap_jet": {"tex": "water_laser", "blend": "mix", "life": 0.2, "scale": [0.3, 0.42], "ease": 3.0, "fade_out": 0.3, "pivot": Vector2(0.06, 0.5),
		"palette": "sap", "keep": 0.45, "priority": 1, "children": [["sap_droplet", 2, Vector2(10, 10)]]},
	# 빨아들이기: 관으로 빨려 드는 물줄기 조각·방울 (opts.vel)
	"suck_strip": {"tex": "water_strip", "blend": "mix", "life": 0.45, "scale": [0.42, 0.3], "ease": 1.0, "fade_in": 0.2, "fade_out": 0.6,
		"palette": "sap", "keep": 0.4, "color": Color(1, 1, 1, 0.7), "priority": 0},
	"pump_bite": {"tex": "star_burst", "life": 0.3, "scale": [0.3, 0.55], "ease": 3.0, "fade_out": 0.35, "rot_rand": 180.0, "palette": "sap",
		"energy": 1.1, "priority": 1, "children": [["sap_droplet", 4, Vector2(20, 20)]]},
	# 장갑이 깨짐: 김이 터지고 불똥이 튄다
	"pump_break": {"tex": "star_crescent", "life": 0.55, "scale": [0.5, 0.9], "ease": 3.0, "fade_out": 0.4, "palette": "gold", "keep": 0.2, "energy": 1.1,
		"priority": 2, "children": [["steam_puff", 5, Vector2(90, 40)], ["spark", 8, Vector2(30, 30)]]},
	# 바닥에서 수액이 솟기 전 부글거림 (수액 기둥 예고)
	"sap_bubble": {"tex": "ripple_drop", "blend": "mix", "life": 0.6, "scale": [0.18, 0.3], "ease": 2.0, "fade_in": 0.3, "fade_out": 0.7,
		"scale_xy": Vector2(1.0, 0.6), "pivot": Vector2(0.5, 0.75), "palette": "sap", "keep": 0.4, "priority": 1},
	# 소녀가 수액·물 위를 걷거나 내려앉을 때 (scripts/fx/water_fx.gd)
	"water_ripple": {"tex": "ripple_drop", "blend": "mix", "life": 0.6, "scale": [0.16, 0.34], "ease": 2.0, "fade_out": 0.4, "scale_xy": Vector2(1.0, 0.5),
		"pivot": Vector2(0.5, 0.72), "palette": "sap", "keep": 0.5, "color": Color(1, 1, 1, 0.7), "priority": 0},
	"water_splash_in": {"tex": "water_splash", "blend": "mix", "life": 0.42, "scale": [0.3, 0.42], "ease": 3.0, "fade_out": 0.4, "pivot": Vector2(0.5, 0.9),
		"palette": "sap", "keep": 0.45, "priority": 1,
		"children": [["sap_droplet", 3, Vector2(30, 4), {"offset": Vector2(0, -16), "scale": 0.8}], ["water_ripple", 1, Vector2.ZERO, {"scale": 1.4}]]},
	"water_jump": {"tex": "splash_crown", "blend": "mix", "life": 0.36, "scale": [0.24, 0.34], "ease": 3.0, "fade_out": 0.4, "pivot": Vector2(0.5, 0.85),
		"palette": "sap", "keep": 0.45, "priority": 1, "children": [["sap_droplet", 2, Vector2(20, 4), {"offset": Vector2(0, -16), "scale": 0.7}]]},
	# 위에서 떨어지는 물방울 (수액 웅덩이 위) — 수면에 닿는 자리에서 물결은 water_fx 가 따로 띄운다
	"drip_fall": {"tex": "drop", "blend": "mix", "life": 0.6, "scale": [0.28, 0.32], "ease": 1.0, "fade_in": 0.15, "vel": Vector2(0, 80), "gravity": 1600.0,
		"fade_out": 0.92, "palette": "sap", "keep": 0.5, "color": Color(1, 1, 1, 0.85), "priority": 0},
	# 수액 어부의 낚싯줄 채찍: 줄을 따라 흩뿌려지는 수액
	"whip_splash": {"tex": "water_strip", "blend": "mix", "life": 0.34, "scale": [0.75, 0.9], "ease": 3.0, "fade_out": 0.4, "pivot": Vector2(0.04, 0.55),
		"palette": "sap", "keep": 0.4, "priority": 1, "children": [["sap_droplet", 4, Vector2(110, 10), {"offset": Vector2(170, 0)}]]},
	# ===================== 몹 =====================
	# 씨앗을 쏘는 순간: 대롱 끝 금빛 번쩍임 + 작은 먼지
	"seed_muzzle": {"tex": "star_burst", "life": 0.18, "scale": [0.12, 0.24], "ease": 3.0, "fade_out": 0.3, "rot_rand": 180.0, "palette": "gold",
		"energy": 1.05, "priority": 1, "children": [["dust_puff", 1, Vector2.ZERO, {"scale": 0.6}]]},
	# 포자 구름이 생길 때: 빛나는 버섯 모양 포자가 피어오른다 + 포자 알갱이
	"spore_burst": {"tex": "mushroom", "blend": "mix", "life": 0.9, "scale": [0.3, 0.7], "ease": 3.0, "fade_out": 0.45, "vel": Vector2(0, -30),
		"pivot": Vector2(0.5, 0.9), "palette": "spore", "keep": 0.3, "color": Color(1, 1, 1, 0.85), "priority": 1,
		"children": [["spore_mote", 6, Vector2(60, 30), {"offset": Vector2(0, -60)}]]},
	"spore_mote": {"tex": "glint", "life": 1.0, "scale": [0.2, 0.08], "ease": 1.0, "fade_in": 0.15, "fade_out": 0.5, "vel": Vector2(0, -40),
		"vel_rand": Vector2(40, 25), "drag": 0.6, "spin": 60.0, "rot_rand": 40.0, "palette": "spore", "energy": 1.1, "priority": 0},
	# 등불에 포자가 타서 걷힘
	"spore_burn": {"tex": "ring", "life": 0.45, "scale": [0.8, 2.6], "ease": 3.0, "fade_out": 0.4, "palette": "fire", "energy": 1.08, "priority": 1,
		"children": [["ember", 10, Vector2(110, 80)]]},
	# 경비병 방패 치기: 방패 앞의 번쩍임 + 먼지
	"shield_bash": {"tex": "shield_arc", "life": 0.26, "scale": [0.42, 0.55], "ease": 3.0, "fade_out": 0.35, "palette": "gold", "keep": 0.35,
		"energy": 1.05, "priority": 1, "children": [["ring_pop", 1, Vector2.ZERO, {"scale": 0.9, "palette": "gold"}], ["dust_puff", 1, Vector2(10, 4), {"offset": Vector2(0, 60)}]]},
	# 돌진(가드 불가) 동안 발밑에 붉은 바람 줄기
	"charge_dust": {"tex": "wisp_beam", "life": 0.24, "scale": [0.42, 0.48], "scale_xy": Vector2(1.0, 0.6), "pivot": Vector2(0.95, 0.5),
		"fade_in": 0.1, "fade_out": 0.4, "palette": "danger", "color": Color(1, 1, 1, 0.5), "priority": 0,
		"children": [["dust_puff", 1, Vector2(10, 4), {"offset": Vector2(-20, 50), "scale": 0.8}]]},
	# 방패·몸이 벽에 박힘 / 기계가 부딪힘
	"slam_impact": {"tex": "star_burst", "life": 0.3, "scale": [0.28, 0.52], "ease": 3.0, "fade_out": 0.35, "rot_rand": 180.0, "palette": "gold", "keep": 0.3,
		"energy": 1.08, "priority": 1, "children": [["spark", 6, Vector2(10, 10)], ["dust_puff", 2, Vector2(20, 30)]]},
	# 기계 드릴의 불똥 (들이받는 동안)
	"drill_spark": {"tex": "star_burst", "life": 0.14, "scale": [0.1, 0.18], "ease": 3.0, "fade_out": 0.3, "rot_rand": 180.0, "palette": "fire",
		"energy": 1.1, "priority": 0, "children": [["spark", 3, Vector2(6, 6)]]},
}

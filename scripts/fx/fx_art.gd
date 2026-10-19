extends RefCounted
## 투사체 그림 묶음 (2026-10-19 이펙트 리뉴얼 F2). Projectile 의 look = "이름" 이 여기 열쇠다.
## 코드로 그린 깃털·잎·바람 호·구슬 대신 기획자 이펙트 시트에서 잘라 둔 그림(art/fx/<tex>.png)을 그린다.
## **판정은 바뀌지 않는다** (Projectile.size·hit_radius 그대로) — 그림만 바뀐다.
##
## 한 줄의 칸 (생략하면 괄호 안 기본값):
##   tex           그림 이름 (art/fx/)
##   scale         그림 배율 (1). Vector2 면 가로·세로 따로
##   rot           그림을 돌려 '날아가는 쪽 = 오른쪽'에 맞추는 각도 (도, 0)
##   head          그림 안에서 판정 가운데(투사체 원점)에 올 자리 (UV, Vector2(0.5, 0.5)) — 깃털 머리, 물방울 몸 등
##   flip_x        그림을 좌우로 뒤집어 쓴다 (왼쪽을 향해 그려진 그림)
##   palette, keep 팔레트 이름 (fx_table.gd 의 PALETTES)과 원래 색을 남기는 비율 (없으면 그림 원래 색)
##   add           더하기 섞기 (false = 보통 섞기). 큰 그림은 보통 섞기 — scripts/fx/README.md '섞기·밝기 규칙'
##   color         색 곱하기 (흰색)
##   glow          투사체 바탕의 발광 원 세기 (그대로 두려면 생략)
##   trail         꼬리 잔상 개수 (그대로 두려면 생략)   trail_alpha  잔상 투명도 (0.3)
##   spin          그림만 도는 빠르기 (도/초, 잎이 굴러가며 떨어지는 것)
##   flap          날갯짓 빠르기 (라디안/초 — 가로 폭이 접혔다 펴진다, 나비)
##   upright       투사체 방향과 상관없이 그림을 똑바로 세운다 (나비: 왼쪽으로 날면 좌우만 뒤집힌다)
##   reflect       저스트 가드로 되받았을 때 바꾸는 팔레트 ("gold")
##   pulse         크기 맥동 세기 (0)

const LOOKS := {
	# ---------- 잿빛 잎새의 새 ----------
	# 깃털 화살: 금빛 깃털 (꼬리의 빛 가닥이 날아온 길). 깃털 머리(오른쪽 아래)가 판정 자리.
	"bird_feather": {"tex": "feather_gold", "scale": 0.74, "rot": -17.0, "head": Vector2(0.8, 0.6), "glow": 0.55, "trail": 3,
		"trail_alpha": 0.28, "color": Color(1.05, 1.02, 0.98)},
	# 잿빛 잎: 금빛 씨앗 잎을 잿빛으로 (금빛 결이 조금 남는다). 굴러가며 떨어진다.
	"bird_leaf": {"tex": "leaf_bolt", "scale": 0.58, "rot": 10.0, "head": Vector2(0.72, 0.5), "palette": "ash", "keep": 0.42,
		"glow": 0.45, "trail": 2, "trail_alpha": 0.25, "color": Color(1.12, 1.12, 1.1)},
	# ---------- 등불 기사 ----------
	# 땅을 달리는 불꽃 파도·등불 회전 불꽃 고리: 물 초승달을 불꽃 팔레트로 (볼록한 쪽이 앞)
	"knight_flame": {"tex": "water_crescent_big", "scale": Vector2(0.52, 0.46), "head": Vector2(0.62, 0.55), "palette": "fire", "keep": 0.12,
		"glow": 0.9, "trail": 3, "trail_alpha": 0.3, "pulse": 0.05},
	# 던지는 등불: 작은 등불 그림이 돌며 날아간다 (불빛 발광)
	"knight_lantern": {"tex": "lantern", "scale": 0.92, "spin": 420.0, "glow": 1.4, "trail": 3, "trail_alpha": 0.22},
	# 불기둥: 물기둥을 불꽃 팔레트로 (바닥에서 솟는다 — 투사체 원점은 기둥 가운데)
	"knight_pillar": {"tex": "geyser", "scale": Vector2(0.62, 0.6), "rot": 90.0, "palette": "fire", "keep": 0.1, "glow": 1.0, "trail": 0,
		"pulse": 0.06},
	# ---------- 무쇠 펌프 · 작은 펌프 ----------
	# 피스톤 충격파: 땅을 달리는 물 초승달
	"pump_shock": {"tex": "water_crescent_big", "scale": Vector2(0.4, 0.3), "head": Vector2(0.62, 0.6), "palette": "sap", "keep": 0.35,
		"glow": 0.7, "trail": 3, "trail_alpha": 0.3, "pulse": 0.05},
	# 수액 방울 (SapBlob): 꼬리 달린 물방울 (그림은 왼쪽으로 날아가므로 뒤집는다)
	"sap_blob": {"tex": "bubble_small", "scale": 0.6, "flip_x": true, "head": Vector2(0.7, 0.48), "palette": "sap", "keep": 0.45,
		"trail": 0, "pulse": 0.06},
	# ---------- 수액의 여왕 ----------
	"queen_dust": {"tex": "glint", "scale": 0.46, "add": true, "palette": "sap", "keep": 0.2, "spin": 160.0, "pulse": 0.25, "trail": 0},
	"queen_butterfly": {"tex": "butterfly", "scale": 0.38, "upright": true, "flap": 14.0, "palette": "sap", "keep": 0.45, "trail": 0},
	# ---------- 몹 ----------
	# 정원사 씨앗: 작은 금빛 씨앗 탄
	"gardener_seed": {"tex": "leaf_bolt", "scale": 0.36, "rot": 10.0, "head": Vector2(0.75, 0.5), "glow": 0.6, "trail": 2, "trail_alpha": 0.22},
	"elite_seed": {"tex": "leaf_comet", "scale": 0.42, "rot": 12.0, "head": Vector2(0.75, 0.48), "glow": 0.7, "trail": 2, "trail_alpha": 0.22},
	# 약초꾼 어미의 포자 덩이: 둥근 포자 안개
	"spore_bolt": {"tex": "spore_ring", "scale": 0.32, "palette": "spore", "keep": 0.25, "spin": 90.0, "glow": 0.7, "trail": 2,
		"trail_alpha": 0.25, "pulse": 0.1},
}


static func has(look: String) -> bool:
	return LOOKS.has(look)


static func get_look(look: String) -> Dictionary:
	return LOOKS.get(look, {})

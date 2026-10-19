# 지형 그림 조각 시스템 (TERRAIN)

기획자가 준 **투명 배경 지형 그림 시트**에서 조각을 잘라, 방의 발판·바닥·경사·벽에 입히는 방식이다.
코드로 그리던 옛 지형(`TerrainStyle`, 이끼·덩굴을 도형으로 그림)을 지역별로 하나씩 바꿔 간다.
**충돌(발판 사각형·경사 다각형)은 그대로**고, 겉모습만 바뀐다. 그림 옷이 없는 지역은 옛 방식으로 그대로 그린다.

지금 그림 옷이 있는 지역: **수관(canopy)** 13방 전부.

---

## 1. 무엇이 어디에 있나

| 파일 | 하는 일 |
|---|---|
| `data/terrain/<지역>.json` | 사람이 쓰는 지역 설명: 자를 조각 목록(시트·상자·역할), 색, 몸통 결 만들기, 잿빛 팔레트, 역할별 세기 |
| `tools/terrain_cut.gd` | 자르기 도구: 시트 → `art/terrain/<지역>/` (atlas.png, fill.png, fill_v.png, pieces.json) + 미리보기 |
| `art/terrain/<지역>/pieces.json` | 도구가 잰 값: 조각의 atlas 자리, 발 딛는 선(top), 걷는 구간(walk), 두께(depth) |
| `scripts/world/terrain_skin.gd` | `TerrainSkin`: 위 두 파일을 읽은 '그림 옷'. 없으면 null → 옛 방식 |
| `scripts/world/terrain_art.gd` | `TerrainArt`: 발판·경사·가시의 자식으로 붙어 조각을 이어 붙인 겉모습을 한 번 만든다 |
| `scripts/world/cracked_art.gd` | `CrackedArt`: 금 간 나무 벽 그림 (비밀 벽·비밀 천장·금 간 벽) — 맞을수록 갈라지고, 부서지면 조각이 떨어진다 |
| `scripts/autoload/purity.gd` | 잿빛 팔레트 표(64×8)를 지역마다 만들어 공용 재질에 넣는다 |
| `shaders/ash_purify*.gdshader` | 팔레트 바꾸기 셰이더 (정화 전 잿빛 ↔ 정화 후 원래 색, 한 점에서 번지는 연출) |
| `tools/room_shots.gd` | 방 스크린샷 (정화 전·후, 바둑판 또는 원하는 자리) |
| `tools/probe_terrain.tscn` | 시험 (9번 항목이 그림 조각 지형) |

`Platform`(`platform.gd`)·`TerrainPolygon`(`terrain_polygon.gd`)·`Thorns`(`thorns.gd`)는 `_ready` 에서
`TerrainSkin.for_node(self)` 로 지역 그림 옷을 찾고, 있으면 `TerrainArt` 를 만들어 붙인다 (없으면 옛 그리기).
지역은 조상 `Room` 의 `region` (노드의 `style_region` 으로 강제할 수 있다).

---

## 2. 조각의 역할 (role)

| 역할 | 쓰는 곳 | 붙이는 법 |
|---|---|---|
| `branch` | 떠 있는 얇은 발판(높이 90 이하·폭 120 이상), 얇은 경사 | 걷는 구간을 발판 폭에 맞춘다: 한 조각(크기 0.85~1.2배, 가로 늘이기 ±15%)이 맞으면 그것, 아니면 왼끝 + 가운데 토막들 + 오른끝을 40px 겹쳐 이어 붙인다 |
| `slab` | 짧은 한쪽 방향(one_way) 발판 (폭 `params.slab.max_w` 이하, 양 끝이 드러난 것) | 위와 같음 |
| `ground` | 큰 바닥·덩어리·두꺼운 경사의 드러난 윗면 | 윗면을 따라 토막을 이어 깐다. 발 선 아래 `band` px 까지만 그리고 `fade` px 동안 몸통 결로 녹아든다. 절벽 끝은 끝 조각(뿌리가 늘어진 부분), 이웃 지형으로 이어지면 `overlap` px 겹쳐 서서히 사라진다 |
| `hang` | 드러난 아랫면(천장·덩어리 밑), 드러난 높은 옆면 | 덩굴·꽃 조각을 띄엄띄엄 매단다 |
| `bush` | 큰 윗면 | 가끔 작은 덤불 |
| `thorn` | 가시(Thorns) | 크기를 섞어 두 줄로 겹쳐 세운다. 밑동은 밑면에 `sink` px 묻고, 끝은 상자 높이의 `reach_min`~`reach_max` 배(밑면에서 잰 값, 판정 끝은 0.7). 방향(`facing_dir`) 0 위·1 아래·2 왼쪽·3 오른쪽 — 옆을 향하면 세로로 늘어서고 판정(`Thorns.hit_rect`)도 같은 틀로 돈다 |
| `shard` | 금 간 벽이 부서질 때 | 껍질 파편 |
| `cracked` (+`_closed`, `_glow`) | 금 간 벽 | `extras` 의 `kind: "cracked"` 가 세 장을 만든다 (아래 4장) |
| `source` | 몸통 결 재료만 | `"atlas": false` — atlas 에 안 들어간다 |

몸통(덩어리 안쪽)은 **이음매 없는 나무껍질 결**(`fill.png` 가로 결, `fill_v.png` 세로 결 — 벽·기둥처럼 세로로 긴 덩어리)을
전역 좌표로 깔아서 이웃 덩어리와 결이 이어진다. 윗면에서 멀어질수록 어두워지고(`fill.deep`), 드러난 가장자리는 조금 어둡다(`fill.rim`).
드러난 옆변·아랫변은 그림에서만 살짝 울퉁불퉁하다(충돌은 곧은 그대로).

**드러남**: 옆 지형(같은 부모 아래 발판·경사 — 부서지는 벽은 뺀다)에 덮였거나 방 경계 밖이면 장식·띠·끝 조각을 붙이지 않는다.

**드러난 끝 밖 자르기** (서지 못하는 자리가 발판처럼 보이지 않게): 조각의 걷는 구간 밖(둥근 끝·늘어진 뿌리, 최대 260px)은
충돌 끝 밖에서 비스듬한 선(끝에서 `CLIP_START` 22px 밖에서 발 높이를 지나 바깥으로 갈수록 1.4배로 내려감, 18px 동안 서서히, ±6px 물결) 위쪽을 지운다.
그래서 발 높이에는 충돌 끝 밖으로 그림이 20px 남짓만 남고, 아래로 처진 뿌리·덩굴만 보인다 (`TerrainArt.piece` 의 `clip_l`/`clip_r`).
가지 끝이 이웃 지형에 붙어 있으면 이웃 속으로 28px 밀어 넣으며 서서히 사라지고, 바닥 띠는 같은 높이로 이어지는 이웃에만 110px 겹치며
위로 솟은 벽에 닿으면 8px 만 들어간다 (벽 면에 이끼가 번져 보이지 않게). 같은 크기 발판이 가까이 쌓이면 다른 조각·반대 뒤집기를 고른다.

**그리는 순서**: 몸통 결은 각 발판의 자식이 아니라 부모 묶음(보통 `Terrain`) 맨 아래 겹에 그린다 (RenderingServer 캔버스 항목, `_make_fill_item`).
그래서 모든 몸통 → 모든 조각 순서가 되어, 나중 형제의 몸통이 앞 형제의 끝 조각·뿌리를 덮어 세로로 잘린 자국이 생기지 않는다.
몸통은 1px 넓혀 깔아 맞닿는 곳에 밝은 틈이 보이지 않게 한다.

---

## 3. 새 지역 그림 옷 만들기 (다른 지역 담당자용)

1. **시트 보기**: 조각 상자를 미리 찾아 둔 목록이 있으면 그걸 쓴다. 없으면
   `godot --headless --path . --script tools/sheet_catalog.gd -- 익스펜션/그림/지형/<시트>.PNG --out <폴더>`
   → `<폴더>/<시트>/overview.png`(상자 번호), `catalog.json`(상자 x,y,w,h).
2. **설명 쓰기**: `data/terrain/canopy.json` 을 복사해 `data/terrain/<지역>.json` 으로.
   - `region`, `name`, `cut.sheet`(시트 경로, `res://익스펜션/...` — 읽기만 한다)
   - `cut.pieces`: `{"name", "role", "src": [x, y, w, h]}` — src 는 대략적인 상자면 된다. 상자에 가장 많이 든 덩어리(+상자에 절반 넘게 든 덩어리)를 자른다.
     옆 조각이 섞이면 `"keep": "largest"`. 다른 시트에서 가져오면 `"sheet"`. 크면 `"scale": 0.5`.
     자동으로 잰 걷는 구간이 이상하면 `"walk": [x0, x1]`(조각 안 px)로 바로잡는다.
     덩어리를 고른 뒤 상자를 더 좁히려면 `"clip": [x, y, w, h]`(시트 px) — 그 사각형 밖은 잘라 낸다 (곧은 사각형 자르기만 된다).
   - `cut.fill`: 몸통 결 재료(`from`: 조각 이름들)와 고를 색 범위(`hue` 도, `sat`, `val`), 네모 크기(`patch`), 결 방향(`vertical`), 밝기(`bright`)
   - `cut.extras`: 금 간 벽 (`{"name": "cracked", "kind": "cracked", "sheet", "src", "out_scale", "bright"}`)
   - `roles`: 역할별 조각 목록을 덮어쓴다 (같은 이름을 여러 번 쓰면 더 자주 나온다 — 예: 바닥 띠 `["ground_a", "ground_a", "ledge_a"]`)
   - `params.ground.caps`: 절벽 끝에 쓸 바닥 조각 (끝이 자연스럽게 끝나는 것만)
   - `tint`(정화 후 색 곱하기, 1 이하), `lift`(발 선을 충돌 윗면보다 몇 px 위에), `fill`(몸통 밝기), `params`(역할별 세기), `ash`(잿빛 팔레트, 4장)
3. **자르기**: `/Users/wj/Projects/SeedWT/godot --headless --path . -s res://tools/terrain_cut.gd -- <지역>`
   → `art/terrain/<지역>/` 와 `screenshots/terrain_<지역>_pieces.png` (빨간 선 = 발 딛는 선, 초록 = 걷는 구간 끝, 옅은 빨강 = 걷는 구간 밖).
   그 다음 **꼭** `tools/cloud_bootstrap.sh` (또는 `godot --headless --import`) — 안 하면 게임이 옛 그림을 쓴다.
4. **확인**: 아래 5장. 그 지역 방을 `ART_ROOMS`(tools/probe_terrain.gd)에 더하면 시험이 맞춤까지 잰다.
5. 그림 옷을 잠깐 끄려면 `data/terrain/<지역>.json` 에 `"enabled": false`.

`data/terrain/_objects.json` 은 지역이 아닌 단독 그림(기록물 양피지 `art/objects/record_parchment.png`)을 자르는 설명이다 (`enabled: false`).
기록물: 벽보·책·쪽지는 양피지 그림, 비석은 돌(코드 그림), 확장판 경전 조각(page)은 EXPANSION 자리 그림 `art/objects/object_scripture_page.png` 그대로.

### 지금 안 되는 것 (다른 지역 담당자가 알아 둘 것)
- **조각 나누기는 '이어진 덩어리' + `keep: "largest"` 뿐**이다. 시트에서 붙어 있는 두 그림을 다각형으로 가르거나 지우는 기능은 없다 (`clip` 은 사각형만).
  붙어 있으면 기획자에게 떼어 달라고 하거나, 상자를 좁혀 `clip` 으로 자른다.
- **벽·천장 전용 역할이 없다.** 벽·기둥·천장은 몸통 결(`fill_v` 세로 결)과 매단 장식만으로 그린다 — 돌·쇠 벽 지역은 결 무늬만 보인다.
- `fork`·`slope`·`arch` 역할(수관의 branch_d·slope_a·arch_a)은 atlas 에 잘라 두었지만 **아직 어떤 코드도 쓰지 않는다** (갈래 가지·경사 조각·아치는 나중 일).

### 발 딛는 선 (맞춤의 핵심)
도구가 조각마다 열(세로줄)별로 **빽빽한 윗면**(불투명 픽셀이 12px 이어지기 시작하는 높이)을 찾고,
8px 마다 ±56px 안의 60% 백분위 → 이웃과 평균으로 고른 선을 `pieces.json` 의 `top` 에 적는다 (잎 끝 몇 장은 무시).
**걷는 구간**(`walk`)은 선이 가운데 높이에서 크게 벗어나지 않고 아래가 차 있는 가장 긴 구간이며,
끝 24px 의 90% 이상이 발 선 8px 아래까지 차 있을 때까지 안쪽으로 줄인다 (둥근 끝 위에 충돌 끝이 오지 않게).
게임은 이 선을 펴서 충돌 윗면에 놓는다 → 소녀는 늘 그림 위에 서 있다.

---

## 4. 잿빛 ↔ 정화 (팔레트 바꾸기)

`ash_purify` 셰이더는 원래 색의 **밝기와 색상**으로 지역의 잿빛 표(64×8 그림)를 찾아 바꾼다:
0번 줄 = 무채색(밝기 → 잿빛 색), 1~6번 줄 = 빨강·노랑·초록·청록·파랑·자홍 띠. 채도가 낮으면 무채색 줄.
밝기 순서가 지켜져 그림이 뭉개지지 않고 잎·껍질·꽃이 서로 다른 잿빛으로 남는다. 1 넘는 빛(발광)은 밝기를 지킨다.

표는 `data/terrain/<지역>.json` 의 `ash` 로 정한다:
```json
"ash": {
  "neutral": [[0.0, "#14161b"], [0.55, "#7d828b"], [1.0, "#e6e8ea"]],
  "hues": {"green": [[0.0, "#121619"], [0.6, "#7e888a"], [1.0, "#e2e7e6"]], "yellow": [...]}
}
```
(밝기 0~1 → 그 밝기의 잿빛 색, 사이는 이어 칠함. 정하지 않은 색상 띠는 무채색 줄을 쓴다.)
`ash` 가 없는 지역은 `Purity.ASH_TINTS` 색조로 기본 표를 만든다 (옛 셰이더보다 중간 밝기가 밝다 — 기획자 의견 "잿빛이 너무 어둡다").
`Purity.apply_region` 이 방에 들어올 때 그 지역 표를 공용 재질에 넣고, `play_purify` 는 그대로 한 점에서 번진다.
배경·안개·잎·빛줄기·지형·가시·금 간 벽 모두 같은 공용 재질이라 함께 바뀐다. 정화된 곳(purity 1)은 표를 찾지 않는다(가벼움).

---

## 5. 맞춤 확인하는 법

- **방 스크린샷** (창이 잠깐 뜬다):
  `godot --path . -s res://tools/room_shots.gd -- canopy_01 --alive`
  → `screenshots/room_canopy_01_alive_<n>.png` (방 전체를 바둑판으로). `--ash` 는 정화 전.
  가까이: `--zoom=1.6 "--at=1300,900;3300,1900"` (화면 1px ≈ 월드 1px 은 1.5 안팎).
  **`--lines`** 를 주면 충돌 윗면을 빨간 선으로 겹쳐 그린다 → 그림 윗면이 선에 붙어 있는지 본다.
- **시험**: `godot --headless --path . res://tools/probe_terrain.tscn -- --art`
  (수관 13방: 모든 지형이 그림, 충돌 그대로, 드러난 윗면마다 발밑 8px 이 그림으로 90% 넘게 덮이고 그림 윗선이 충돌 윗면 ±10px,
  **드러난 충돌 끝 밖 발 높이에 그림이 34px 넘게 남지 않음**, 몸통 결이 묶음 맨 아래 겹, 방의 가시 그림이 판정을 덮고 끝이 상자 위 0.5h 이하,
  가시 네 방향(가로·세로 상자)의 그림 상자·판정 자리, 만들기 비용, 정화 프레임에 다시 안 만들기, 잿빛 표, 금 간 벽 단계·부서짐, 기록물 그림.)
  `--verbose` 면 발밑이 빈 자리와 끝 밖 그림이 긴 곳을 찍는다.
- **실제 렌더러 비용**: `godot --path . res://tools/probe_terrain.tscn -- --cost`
- **지형 감사**: `python3 -I tools/audit_rooms.py` 오류 0 (충돌은 바꾸지 않으므로 그대로여야 한다).

## 6. 성능 (아이폰 11 Pro 기준 — 실기기 확인은 아직)
- 겉모습은 방에 들어올 때 한 번 만든다 (맥에서 수관 방 평균 약 13ms, 가장 큰 방 약 26ms — 폰은 2~3배일 수 있다). 매 프레임 다시 그리지 않고, 정화 연출 중에도 안 바뀐다 (셰이더만).
- 노드 하나에 그리기 호출 최대 4번(가로 결·세로 결·atlas·색만; 몸통 결 둘은 묶음 맨 아래 항목), 방 하나 삼각형 1만 4천 개 안팎.
- 맥 실제 렌더러에서 잰 것: 렌더 스레드 CPU 시간이 옛 코드 지형의 약 0.2~0.5배, 그리기 호출도 적다 (canopy_01 잿빛 17 대 27).
  **GPU 칠하기 비용(겹쳐 칠하기)은 이 렌더러에서 잴 수 없어 재지 않았다** — 잿빛 셰이더는 정화 전 화면의 잿빛 재질 겹마다 색상 계산 + 표 찾기 3번을 한다.
  아이폰 11 Pro 의 잿빛 수관 방에서 프레임을 꼭 확인할 것. (`probe_terrain -- --cost` 의 '0.49배'는 옛 방식 두 가지끼리의 비교다.)
- atlas 는 GPU 압축(VRAM 압축 — 모바일은 ETC2, `compress/high_quality` 를 켜면 ASTC)·밉맵, 몸통 결은 512×512 반복.

---

## 7. 수액의 호수 (sap_lake · sap_descent) — 추가된 것

- 그림 옷 두 벌: `data/terrain/sap_lake.json` (호숫가의 뿌리·수면 자국 벽·호수 한가운데 — 금빛 뿌리 발판 시트 78493128 + 물 지형 시트),
  `data/terrain/sap_descent.json` (숨은 내리막 — 어두운 뿌리·폭포 시트 C082DF1A).
- **방 하나만 다른 그림 옷**: 방(Room) 노드 메타 `terrain_skin = "sap_descent"` → `TerrainSkin.for_node` 가 그 그림 옷을 쓴다.
  지역(`region`)은 그대로라 정화·음악·잿빛 표는 지역 것(sap_lake)을 쓴다.
- **`wall` 역할** (`scripts/world/terrain_wall.gd`, 추가만 — wall 조각이 없는 그림 옷은 그대로): 덩어리의 드러난 높은 옆면(`min_h` 이상)을
  세로로 긴 줄기·기둥 조각으로 덮는다. 바깥 가장자리는 충돌 옆면 밖으로 `out` px, 안쪽 가장자리는 `inner_fade` 동안 몸통 결로 녹는다.
  `params.wall`: `width`, `out`, `min_h`, `inner_fade`, `v_lo`/`v_hi`(조각 안에서 쓰는 세로 구간 — 빛 구멍처럼 되풀이되면 티 나는 부분은 뺀다), `top_inset`.
- **`water`·`wave` 역할** (`scripts/world/sap_water_art.gd`): 수액 웅덩이(SapPool)의 겉모습. 그 방의 그림 옷에 water 조각이 있으면
  몸통(수면 조각 가운데 토막을 이어 붙임)·물결 띠를 그림으로 그리고, SapPool 은 빛 띠·방울·잔물결만 얹는다. **판정·수면 높이는 그대로.**
  끝이 지형에 막혔으면 곧게, 열려 있으면 비스듬한 물가 끝(판정 끝 밖으로 조금, 서서히 사라짐). water 조각이 없는 지역(잠긴 채굴장)은 옛 그림 그대로.
  `params.water`: `alpha`(정화 후), `alpha_ash`(정화 전), `wave_alpha`.
- `params.ground.flip_right_cap` (기본 꺼짐): 오른쪽 절벽 끝에 끝 조각의 왼끝을 뒤집어 쓴다 (오른끝이 내리막 비탈인 조각용).
- 시험: `godot --headless --path . res://tools/probe_lake_terrain.tscn` (probe_terrain 의 재기 도우미를 물려 쓰는 호수 전용 시험 — 방 4곳 맞춤·끝 밖 그림·
  가시·벽 조각·웅덩이 그림·배경·비용). 다른 지역도 같은 식으로 `extends "res://tools/probe_terrain.gd"` 해 방 목록·atlas 만 바꿔 쓸 수 있다.
- 배경: `art/backgrounds/bg_sap_lake_1.png`(4-1)·`bg_sap_lake_boss.png`(4-2)·`bg_hidden_descent.png`(5) 는 기획자 그림. `tools/make_placeholders_lake.gd` 는 더는 배경을 만들지 않는다.

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
| `thorn` | 가시(Thorns) | 크기를 섞어 두 줄로 겹쳐 세운다. 밑동은 바닥에 묻고 끝은 판정 위로 |
| `shard` | 금 간 벽이 부서질 때 | 껍질 파편 |
| `cracked` (+`_closed`, `_glow`) | 금 간 벽 | `extras` 의 `kind: "cracked"` 가 세 장을 만든다 (아래 4장) |
| `source` | 몸통 결 재료만 | `"atlas": false` — atlas 에 안 들어간다 |

몸통(덩어리 안쪽)은 **이음매 없는 나무껍질 결**(`fill.png` 가로 결, `fill_v.png` 세로 결 — 벽·기둥처럼 세로로 긴 덩어리)을
전역 좌표로 깔아서 이웃 덩어리와 결이 이어진다. 윗면에서 멀어질수록 어두워지고(`fill.deep`), 드러난 가장자리는 조금 어둡다(`fill.rim`).
드러난 옆변·아랫변은 그림에서만 살짝 울퉁불퉁하다(충돌은 곧은 그대로).

**드러남**: 옆 지형(같은 부모 아래 발판·경사 — 부서지는 벽은 뺀다)에 덮였거나 방 경계 밖이면 장식·띠·끝 조각을 붙이지 않는다.

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
  만들기 비용, 정화 프레임에 다시 안 만들기, 잿빛 표, 금 간 벽 단계·부서짐, 기록물 그림.)
  `--verbose` 면 발밑이 빈 자리를 찍는다.
- **실제 렌더러 비용**: `godot --path . res://tools/probe_terrain.tscn -- --cost`
- **지형 감사**: `python3 -I tools/audit_rooms.py` 오류 0 (충돌은 바꾸지 않으므로 그대로여야 한다).

## 6. 성능 (아이폰 11 Pro 기준)
- 겉모습은 방에 들어올 때 한 번 만든다 (수관 방 평균 약 13ms). 매 프레임 다시 그리지 않고, 정화 연출 중에도 안 바뀐다 (셰이더만).
- 노드 하나에 그리기 호출 최대 4번(가로 결·세로 결·atlas·색만), 방 하나 삼각형 2만 개 안팎.
- atlas 는 GPU 압축(ASTC)·밉맵, 몸통 결은 512×512 반복.

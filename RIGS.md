# 부위 뼈대 (파트 리그) 안내서

몹·보스의 그림을 **부위별 그림 + 관절**로 움직이는 방법을 한곳에 모은 문서다.
(2026-10-20 나무꾼으로 처음 만들고, 같은 날 몹 13종·보스 5종을 만든 뒤 한 문서로 정리함)

기획자가 부위를 따로 그려 준 시트(`익스펜션/그림/리뉴얼-몹`, `리뉴얼-보스`, `몹`, `보스`)를 잘라 관절로 잇고,
코드가 자세를 만들어 움직인다. 발은 땅을 딛고, 휘두르기는 허리 → 어깨 → 팔꿈치 → 무기 순서로 채찍처럼 나가고,
쓰러질 때는 무릎이 꺾인 뒤 엎어지거나 엉덩방아를 찧는다. **판정·시간은 건드리지 않는다 — 그림이 논리를 따라간다.**

병렬 작업 폴더에서는 Godot 을 늘 래퍼 `/Users/wj/Projects/SeedWT/godot` 로, `perl -e 'alarm 300; exec @ARGV'` 로 감싸서 돌린다.
아래 예의 `G` 는 그 래퍼다. `익스펜션/` 은 기획자 원본이라 **읽기만** 한다 (작업 폴더에 없으면 본 저장소의 `익스펜션` 을 가리키는 심볼릭 링크를 만든다).

---

## 0. 한눈에

### 파일

| 파일 | 하는 일 |
|---|---|
| `data/rigs/<id>.json` | **설계도** (사람이 쓴다): 어느 시트의 어느 조각이 어느 부위인지, 관절 자리, 부모, 앞뒤 순서, 자세 고치기 |
| `data/rigs/_archetypes/<이름>.json` | **원형**: 사람 모양이 아닌 몸(새·기계·기사·뿌리지기·여왕 …)의 자세 모음과 움직임 지도 (3장) |
| `tools/rig_cut.gd` | 자르기 도구: 조각 번호 미리보기, 시트 확대 보기, 부위 자르기 → `art/rigs/<id>/` |
| `tools/rig_feather.gd` | 자른 선 녹이기(페더): 완성 그림을 두 겹으로 자른 선이 비칠 때, rig_cut **다음에** 돌린다 (1장 4번) |
| `art/rigs/<id>/*.png`, `rig.json` | 잘린 부위 그림(가장자리 정리·밉맵) + 실행용 뼈대 (도구가 만든다 — 손으로 고치지 않는다) |
| `scripts/rig/part_rig.gd` | `PartRig` — 뼈대 노드: 부위 그림을 관절로 잇고 그린다 (변형 그림, 번쩍임·흩어짐 셰이더, 잔상, 덧고침 도우미) |
| `scripts/rig/rig_motion.gd` | `RigMotion` — 움직임: 스프링 보간, 세 박자 휘두르기, 걸음·발 디딤, 다리 IK, 무릎 꿇기, 무기 땅 막기, 천 흔들림, 땅 닿기·내려놓기 |
| `scripts/rig/rig_poses.gd` | `RigPoses` — 사람 모양(humanoid) 자세 모음 + 원형 파일 읽기. **`SETS` 는 고치지 않는다** (새 원형은 파일로) |
| `scripts/enemies/enemy_rig_visual.gd` | `EnemyRigVisual` — 일반 몹의 Visual (EnemySpriteVisual 과 공개 함수가 같다) |
| `scripts/enemies/hooked_rig_motion.gd` | `HookedRigMotion` — RigMotion + '움직이기 직전 갈고리' (몹 그림이 목표 자세를 한 번 더 고친다) |
| `scripts/enemies/enemy_mech_visual.gd` | `EnemyMechVisual` — 기계 몹 공용 (드릴 돌기·빛·김·불꽃·늘 겨누는 대롱·배를 땅에 대는 쓰러짐) |
| `shaders/rig_flash.gdshader` | 부위 공용 재질: 피격 번쩍임, 흩어져 사라짐 (부위 지역 좌표의 부드러운 얼룩) |
| `tools/rig_preview.tscn` | 확인 화면 (창으로): 부위·관절 표시, 자세별 스크린샷, 실제 몹 씬의 동작 필름 |
| `tools/probe_rigs.tscn` | 모든 뼈대 공통 검사 (7장) |

### 지금 있는 뼈대 (18개)

| 뼈대 id | 원형 | 쓰는 씬 (Visual 스크립트) | 메모 |
|---|---|---|---|
| `woodcutter` | humanoid | woodcutter · elite_woodcutter(×1.8) · ash_giant(×1.72, 어둡게) (`EnemyRigVisual`) | 첫 시범. 잎칼 `ground_guard`, 치마 `hips` soft |
| `woodcutter_savable` | humanoid | woodcutter_savable (`EnemyRigVisual`) · 구원된 나무꾼·광부 하론의 집 | 사람 얼굴 변형 |
| `gardener`, `gardener_savable` | gardener (humanoid 상속) | gardener · elite_gardener · gardener_savable (`GardenerEnemyRigVisual`) | 대롱 `arm_kind = "gun"`, 씨앗 꼬투리·덩굴 chain, 구원형 눈 감은 얼굴 |
| `herbalist`, `herbalist_savable` | herbalist (humanoid 상속) | herbalist · elite_herbalist · herbalist_savable (`HerbalistEnemyRigVisual`) | 버섯 부풂·포자 가루, 어두운 방 버섯 빛 |
| `guard`, `guard_savable` | humanoid | guard · elite_guard · guard_savable (`GuardRigVisual`) | 방패 = 앞팔의 `weapon`, 잎 치마 `tasset` soft, 자세 바꿔 끼우기 |
| `owen` | humanoid | owen (`OwenRigVisual`) | 곡괭이 두 손 쥐기(뒷손 두 뼈 IK, 소켓 `grip_b`), 헬멧·허리 등불 빛, 얼굴 3가지 |
| `machine` | drill_beast | machine · elite_machine (`EnemyMechVisual`) | 다리 넷, 드릴 빛 줄 셰이더 `drill_spin.gdshader` |
| `small_pump` | pipe_walker | small_pump (`EnemyMechVisual`) | 무릎이 뒤로 꺾이는 다리 넷·대각선 걸음, 늘 겨누는 대롱 |
| `sap_fisher`, `sap_fisher_savable` | humanoid | sap_fisher · sap_fisher_savable (`sap_fisher_visual.gd`) | 줄 물리 낚싯줄(숨은 부위 `whip_*` 를 직접 그림) |
| `gray_leaf_bird` | bird | 보스 잿빛 잎새의 새 (`gray_leaf_bird_visual.gd`) | 날개 안/바깥·접은 날개·머리 3종, `leg_unit_reach`, 떠 있는 높이 `set_root_lift` |
| `lantern_knight` | knight (humanoid 상속) | 보스 등불 기사 (`lantern_knight_visual.gd`) | 두 손 창 IK, 등불 진자, 몸 틀 때 정면 투구 변형 |
| `root_keeper` | root_keeper | 보스 뿌리지기 (`root_keeper_visual.gd`) | 치마 속 숨은 다리, 지팡이 짚기·땅 막기, 페더·구멍 메움 부위 |
| `sap_queen` | sap_queen | 보스 수액의 여왕 (`sap_queen_visual.gd`) | 다리 IK 안 씀(`legs` 없음), 발끝 뼈 `pointe_*`, 날갯짓은 덧고침 |
| `iron_pump` | iron_pump | 보스 무쇠 펌프 (`iron_pump_visual.gd`) · 멈춘 펌프 (`iron_pump_remains.gd`) | 무릎 뒤로 꺾이는 다리 둘, 돌아설 때 다리 맞바꾸기, 걷기 시작 위상 |

구원된 사람(`RescuedPerson`)도 같은 뼈대로 선다: 몹 Visual 의 `npc_rig`(들판) / `data/dialogue/relocations*.json` 의 `"rig"`(집).
지금 구원형 뼈대를 쓰는 집: 나무꾼·정원사·경비병·오웬·약초꾼·어부·광부 하론 (마을의 사람 오웬 NPC 는 아직 예전 한 장 그림).

### 원형 (자세 모음)

| 원형 | 파일 | 쓰는 뼈대 |
|---|---|---|
| humanoid | `RigPoses.HUMANOID` (코드) | 나무꾼·경비병·오웬·어부 (그리고 아래 `extends` 원형의 바탕) |
| gardener / herbalist / knight | `_archetypes/*.json` (`"extends": "humanoid"`) | 정원사 / 약초꾼 / 등불 기사 |
| bird / drill_beast / pipe_walker / root_keeper / sap_queen / iron_pump | `_archetypes/*.json` (상속 없음, `_motion` 지도 필수) | 새 / 기계 / 작은 펌프 / 뿌리지기 / 여왕 / 무쇠 펌프 |

---

## 1. 자르기 순서 (한 캐릭터에 30~60분)

1. **조각 번호 보기**: 설계도에 `sheet`·`faces`·`segment` 만 적고(2장) 실행한다.
   ```
   G --headless --path . --script tools/rig_cut.gd -- <id> --dump
   ```
   `screenshots/rig_cut/<id>/labels_main.png` (조각마다 색·경계선·가운데 번호, 100px 격자에 좌표 숫자)와 `labels_main.json`(번호별 상자) 이 나온다.
   **이 그림을 Read 로 열어 본다.** 서로 닿은 부위가 한 조각이면 `segment.erode` 를 키우거나(4 → 6) 다각형으로 자른다.
2. **관절 좌표 읽기**: 관절 근처를 크게 본다 (격자 25px, 숫자는 50px 마다).
   ```
   G --headless --path . --script tools/rig_cut.gd -- <id> --crop <x> <y> <w> <h> --grid 25 --zoom 1.6
   ```
   → `screenshots/rig_cut/<id>/crop_main_<x>_<y>.png`. 어깨·팔꿈치·손목·엉덩이·무릎·발목의 **회전 중심**과 발바닥(sole)을 원본 px 로 적는다.
   관절은 '살이 겹치는 둥근 곳의 가운데'에 둔다 (모서리에 두면 돌 때 틈이 벌어진다).
3. **설계도 쓰기**: 부위마다 `comps`(조각 번호) 와 필요하면 `clip`/`cut` 다각형, `pivot`, `parent`, `attach`, `z` (2장).
4. **자르기**: `G --headless --path . --script tools/rig_cut.gd -- <id>` → `art/rigs/<id>/`.
   완성 그림을 두 겹(몸통·치마처럼)으로 잘라 자른 선이 그림 속을 가로지르면 부위에 `"feather"` 를 적고
   `G --headless --path . --script tools/rig_feather.gd -- <id>` 를 이어 돌린다 (선분 둘레 알파를 0 → 1 로 녹인다, 뿌리지기 설계도 참고).
   그다음 **반드시** `GODOT=/Users/wj/Projects/SeedWT/godot tools/cloud_bootstrap.sh` (새 그림 가져오기·밉맵).
5. **부위 확인** (창으로): `G --path . res://tools/rig_preview.tscn -- <id> --parts`
   → `screenshots/rig_<id>_parts.png`: 부위마다 같은 크기 칸에 맞춰 키운 그림(칸 아래 이름·z·배율) + 빨강 = 관절(pivot), 파랑 = 축 끝(tip), 노랑 = 자식이 붙는 자리, 초록 = 발바닥.
   자식의 노랑 점이 부모 그림의 관절 자리에 있어야 한다.
6. **자세 확인** (창으로): `G --path . --resolution 1600x900 res://tools/rig_preview.tscn -- <id> --zoom 3.5 [--joints] [--poses idle,windup,strike,kneel]`
   → 자세마다 `screenshots/rig_<id>_<자세>.png` + 모아 보기 `rig_<id>_poses.png`. 발을 크게: `--zoom 9 --cam_y 0.12`.
   **틈(관절 사이 배경이 비침), 튀어나옴, 앞뒤 순서(z), 발이 땅에 붙는지**를 본다.
   (보스 그림처럼 그림 스크립트가 부위 배율을 따로 주는 뼈대는 이 사진에 그 배율이 빠져 보인다 — 보스 필름 도구로 본다.)
7. **실제 몹 동작 필름** (창으로, 씬의 Visual 을 바꾼 뒤):
   `G --path . --resolution 1600x900 res://tools/rig_preview.tscn -- --enemy res://scenes/enemies/<몹>.tscn --zoom 3 --seq idle,walk,attack,hit,broken,dead,dead_back,kneel --every 0.05 --crop 0.45`
   → `screenshots/rig_<몹>_<동작>.png` (0.05초 간격 칸). 예고 → 타격 → 되돌림이 세 박자로 읽히는지, 발이 미끄러지지 않는지.
   동작은 몇 개든 된다 (바닥이 동작 수만큼 넓어진다). 대롱 몹은 `aim`, 잿가지 거인은 `slam`.
   `kneel` 은 `<몹>_savable.tscn` 이 있으면 그것으로, 오웬처럼 씬 자체가 구원형이면 그대로 찍는다. `dead_back` 은 방패 몹의 방패를 열어 두고 친다.
   몹 AI 가 고르는 공격(들이받기·리듬 쏘기·채찍)은 `tools/rig_film_ai.tscn` (7장).
8. **검사**: `G --headless --path . res://tools/probe_rigs.tscn` (실패 0), 그리고 그 몹의 방 시험·전용 검사 (7장).
9. 4~7 을 **틈이 없고 움직임이 자연스러울 때까지** 되풀이한다. 스크린샷은 `screenshots/` 라 저장소에 올리지 않는다
   (예전 스크린샷 몇 장이 이미 git 에 들어 있어 방 시험이 그것을 고쳐 쓴다 — `git add` 는 `art/rigs data/rigs scripts …` 처럼 폴더를 집어서,
   커밋 전에 `git checkout -- screenshots/`).

---

## 2. 설계도 `data/rigs/<id>.json`

좌표는 **모두 원본 시트 px** (미리보기 격자 숫자 그대로). 각도는 **도(degree)**.

```jsonc
{
  "id": "woodcutter",
  "sheet": "res://익스펜션/그림/리뉴얼-몹/AF637C8F-….PNG",   // 읽기만 한다 (익스펜션/ 은 절대 고치지 않는다)
  "faces": "left",              // 시트 속 인물이 보는 쪽. left 면 도구가 모두 뒤집는다 → 실행용 뼈대는 늘 오른쪽을 본다
  "segment": {"alpha": 0.5, "erode": 4, "min_pixels": 1500, "soft_alpha": 0.03, "min_small": 150},
  "out_scale": 0.5,             // 잘린 그림 크기 = 시트의 몇 배 (몹 0.35~1.0, 보스 0.55~0.9). 부위별 "scale" 로 더 곱할 수 있다
  "game_scale": 0.152,          // 시트 px → 게임 px (나무꾼: 키 1021 → 155). 크기 기준은 GAME_DESIGN 8장
  "archetype": "humanoid",      // 자세 모음 (humanoid 또는 data/rigs/_archetypes/<이름>.json). 잘못 쓰면 경고 + 검사 실패
  "extra_sheets": {"face": {"path": "res://익스펜션/…"}},   // 다른 시트의 부위·변형을 쓸 때 (부위에 "sheet": "face")
  "chains": {                   // 사슬: 이름 → [위, 아래, 끝]. 팔다리 축의 기본값(다음 마디 관절 쪽)과 다리 IK·무기 땅 막기가 쓴다
    "leg_f": ["leg_f_up", "leg_f_lo", "foot_f"],
    "arm_f": ["arm_f_up", "arm_f_lo", "weapon"]
  },
  "legs": ["leg_f", "leg_b"],   // 땅을 딛는 다리 (사슬 이름). 무릎이 뒤로 꺾이면 {"chain": "leg_b", "knee_back": true}. 한 뼈 다리는 사슬 [다리] 하나.
                                //   몇 개든 된다 (기계 넷 — 짝수/홀수 번호가 번갈아 딛는다). 비우면 발 디딤을 건너뛴다 (여왕)
  "weapon_chain": "arm_f",      // 무기 팔 사슬 (땅 막기: 어깨 → 팔꿈치 → 손목 순으로 든다). 무기가 없으면 "none" (팔이 땅 닿기에서 빠지지 않게)
  "ground_guard": ["weapon", "arm_f_lo"],   // 땅 아래로 들어가면 안 되는 부위 (칼끝이 땅에 닿아 멈춘 것처럼)
  "ghost": ["torso", "arm_f_up", "arm_f_lo", "weapon"],   // 휘두를 때 잔상으로 남길 부위
  "soft": ["hips"],             // 부드러운 부위 (치마·날개처럼 몸을 받치지 않는 그림 — 아래). chain 부위는 저절로 부드럽다
  "sockets": {"eye": {"bone": "head", "at": [452, 128]}},  // 뼈에 붙는 자리 (눈빛·등불·대롱 끝·손잡이 등). PartRig.bone_point/attach
  "poses": { "idle": {"arm_f_up": -46, "weapon": -16} },   // 원형 자세 고치기 (3장)
  "parts": { … }
}
```

### 부위 (`parts.<이름>`)

| 키 | 뜻 |
|---|---|
| `comps` | 조각 번호들 (`--dump` 그림의 번호). 조각 하나에 여러 부위가 붙어 있으면 같은 번호를 여러 부위가 쓰고 `clip` 으로 나눈다 |
| `clip` | 다각형들 `[[[x,y],…], …]`: 이 안만 남긴다. 번호 없이 `clip` 만 쓰면 다각형 안의 모든 픽셀 |
| `cut` | 다각형들: 이 안을 지운다 (예: 골반 조각에서 앞다리 부분 빼기) |
| `add` | 다각형들: 번호와 상관없이 이 안의 픽셀을 더한다 |
| `grow` | 다각형 경계를 이만큼(px, 기본 3) 넓힌다 → 이웃 부위와 살짝 겹쳐 이음매가 비치지 않는다 (`cut` 은 그만큼 좁힌다, 음수면 안쪽으로) |
| `pivot` | 이 부위가 도는 관절 (원본 px) — **필수** |
| `parent` | 부모 부위 이름. 없으면 뿌리 (뿌리는 하나 — 보통 골반 `hips`) |
| `attach` | 부모 그림 위에서 이 관절이 붙는 자리 (원본 px). 없으면 `pivot` 과 같은 자리 (같은 시트에서 이어 그려진 부위) |
| `tip` | 축 끝 (팔다리·무기·늘어진 천). 있으면 이 부위는 **축 부위**: 회전 0 = 부모 틀에서 똑바로 아래. 사슬 안이면 다음 마디의 관절이 기본값 |
| `rot` | 축 각도 더하기 (도) |
| `rest` | 쉬는 자세의 세상 각도 (도, 축 부위는 0 = 똑바로 아래). 없으면 시트에 그려진 각도 그대로 |
| `z` | 그리기 순서 (작을수록 뒤). 뼈 계층과 상관없다 — 뒷팔(−7)이 몸통(0) 뒤, 칼팔(+6)이 앞 |
| `sole` | 발바닥 한 점 (다리 끝 부위에 필수). 땅에 닿는 점 — 신발 바닥 가운데 |
| `mirror` | 그림을 좌우로 뒤집어 쓴다 (`pivot` 축 거울). 앞발 그림이 뒤를 보고 그려졌을 때 |
| `scale` | 이 부위만 더 크게/작게 자른다 (`out_scale` 에 곱함) |
| `from` | 다른 부위의 그림을 그대로 쓴다 (예: 같은 다리 그림을 앞뒤 다리에, 기계 다리 넷). 자기 `parent`/`attach`/`z` 는 따로 |
| `variants` | 바꿔 끼우는 그림: `{"face": {"sheet": "face", "comps": [3], "pivot": [x, y]}}` → `PartRig.set_variant("head", "face")`. `pivot` 은 그 그림에서 같은 관절 자리 |
| `chain` | 늘어진 천·잎·머리카락: `{"stiffness": 45, "damping": 6, "drag": 0.0003, "gravity": 0.4, "max": 35}` — 몸보다 한 박자 늦게 따라오고 달리면 뒤로 날린다 |
| `feather` | 자른 선 녹이기 `[{"from": [x0, y0], "to": [x1, y1], "px": 36}, …]` (rig_feather.gd 가 읽는다) |
| `modulate` | 이 부위 색 `[r, g, b, a]` (뒷팔·뒷다리를 앞쪽 그림으로 다시 쓸 때 어둡게) |
| `hidden` | 그리지 않는 뼈 (자리만, 예: 무기 끝 소켓용, 치마 속 다리, 어부 낚싯줄 조각) |

**부드러운 부위** (설계도 맨 위 `"soft": [이름…]` + `chain` 부위 전부): 무릎 꿇기·엉덩방아·누움에서 땅에 닿아도 **몸을 받쳐 띄우지 않는다**
(땅 닿기·내려놓기 잴 때 뺀다). 대신 땅 아래로 들어가는 만큼 늘어진 천은 먼저 관절을 돌려 땅 위에 눕히고, 남으면 그림을 관절 기준으로
땅 쪽으로 눌러 접는다(`squash_y`, 최대 0.35배, 옆으로 조금 퍼짐). 치마·잎 치마(`hips`, `tasset`, `skirt`)·새와 여왕의 날개·뿌리지기의 구멍 메움 조각이 soft.
자식까지 모두 부드러운 늘어진 천(`chain` — 정원사 등의 씨앗 꼬투리·덩굴, 망토)은 접고도 땅 아래로 보이면(관절까지 묻히는 등) 관절을 축으로
한 바퀴 16 각도를 견줘 가장 덜 묻히는 쪽(같으면 덜 도는 쪽)으로 빼낸다 — 자식(덩굴 끝)도 함께 잰다. 지난 프레임 각도에 바꿈 벌점을 주어 떨지 않는다
(2026-10-20: 정원사가 뒤로 쓰러질 때 덩굴이 바닥 아래 32px 까지 지형 위에 비쳤다).
다리·팔처럼 단단한 부위는 넣지 않는다 (몸이 땅에 박힌다). 날개처럼 그림 쪽이 따로 땅 위로 들어 올리는 soft 부위는 들어 올린 뒤 `set_bone_squash(i, 1.0)` 로 접힘을 푼다 (새).

### 사람 모양 + 무기 팔 (humanoid) 뼈 이름 약속

자세 모음(RigPoses.HUMANOID)이 이 이름을 쓴다. 같은 이름이면 **설계도만으로** 움직인다 (나무꾼·경비병·오웬·어부·정원사·약초꾼·기사).

```
hips (뿌리, 골반·허리 띠)
 ├ torso (몸통)            ├ head (머리)
 │                          ├ shoulder_f (앞어깨 덮개 — 팔 위에 그릴 때, 선택)
 │                          ├ arm_f_up → arm_f_lo → weapon   (앞팔 = 무기 팔: 위팔 → 아래팔 → 무기·손)
 │                          ├ arm_b_up → arm_b_lo [→ hand_b] (뒷팔)
 │                          └ cape 등 늘어진 천 (chain)
 ├ leg_f_up → leg_f_lo → foot_f   (앞다리: 허벅지 → 정강이 → 발, sole 필수)
 └ leg_b_up → leg_b_lo → foot_b   (뒷다리)
```
'앞' = 인물이 보는 쪽(오른쪽을 보는 뼈대에서 화면에 가까운 쪽 팔). 방패(경비병)는 앞팔 손의 `weapon` 을 방패로 두고 자세에서 각도를 준다.
대롱(정원사·작은 펌프)은 `weapon`(또는 `aim_bone`) 을 대롱으로 — 씬의 Visual 에 `arm_kind = "gun"` 이면 쫓기·예고·쏘기·회복·물러남 동안
위팔(`arm_f_up`)을 돌려 대롱 뼈의 축이 소녀 가슴을 겨눈다 (위 −0.7 ~ 아래 +0.6 라디안, 예고 땐 0.25 치켜듦). 대롱 뼈의 **축(tip)이 대롱 끝을 향하게** 자른다.

**발 채널과 겹치는 이름 주의**: `foot_` `toe_` `kneel_` `lift_` 로 시작하는 이름은 발 채널로 읽힌다. 다리 IK 를 쓰지 않는 발끝 뼈는
다른 이름으로 짓는다 (여왕: `pointe_f`/`pointe_b`).

---

## 3. 자세 짓기

자세 = 채널 이름 → 값. RigPoses 머리말에 전체 약속이 있다. 요약:

- **몸**: `hip_x`, `hip_y` (다리 길이 L 의 몇 배, `hip_y` + = 웅크림), `lean` (골반째 기울기, 도, + = 앞으로)
- **발**: `foot_f`/`foot_b` (발 자리, L 배, + = 앞), `toe_f` (발 각도), `kneel_f` (0 아니면 1 — 그 무릎을 꿇는다), `pitch` (0~1, 꿇은 무릎에서 허벅지가 앞으로 눕는 정도)
- **걸음**: `step_thr` (발이 이만큼 어긋나면 한 걸음, L 배), `step_dur`, `step_lift`
- **뼈 이름**: 축 부위는 **절대 각도** (0 = 부모 틀에서 똑바로 아래, −90 = 앞으로 수평, −180 = 머리 위),
  축 없는 부위(몸통·머리·날개)는 쉬는 자세에 **더하는** 각도 (+ = 앞으로 숙임).
- 팔 각도는 몸통 틀 기준: 몸통을 30도 숙이면 같은 팔 각도도 30도 더 뒤로 보인다. **세상에서 원하는 각도 − 몸통 각도**.
- 머리 위로 넘겨 내려치는 휘두르기는 각도가 머리 위를 지나며 이어지게: 예비 `−200` → 타격 `−88`. (`+160` 으로 쓰면 등 뒤 아래로 돈다.)
- 어느 자세에도(base 포함) 나오지 않는 뼈는 늘 쉬는 각도에 있다 (다리는 IK, `chain` 부위는 흔들림이 움직인다) — 움직일 뼈는 `base` 에 0 으로라도 적는다.
- 그림 스크립트만 읽는 채널도 원형에 둘 수 있다 (뿌리지기 `slide`, 기사 `spear`·`hand_x`·`plant`, 새 `fold_f`) — 뼈 이름이 아니면 각도로 쓰이지 않는다.

원형 자세 이름 (EnemyRigVisual 이 상태에 맞춰 고른다): `idle walk backstep alert air lunge windup strike ready hit broken kneel rescued
dead_knees dead_lie dead_back dead_back_lie shoot scatter_a scatter_b charge stuck leap slam_fall land npc`. 보스는 이름을 자유롭게 짓는다 (`wing_beat`, `thrust_windup` …).

**쓰러짐 두 가지** (EnemyRigVisual, 길이는 EnemyBase 그대로):
- 앞으로 (등 뒤에서 맞음·정화): `dead_knees`(한 무릎 꿇기) → `dead_lie`(두 무릎을 꿇은 채 앞으로 고꾸라져 가슴·머리를 땅에 묻음).
  그림 쪽이 **내려놓기**를 함께 올리고(땅 닿기 1), RigMotion 은 꿇은 무릎이 있으면 몸 전체(body_xf)를 드는 대신 **엉덩이를 축 무릎을 중심으로
  허벅지 길이만큼의 원 위로** 옮긴다 → 무릎·정강이는 땅에 남고, 얇은 몸은 허벅지가 눕고 가슴이 두꺼운 몸은 허벅지가 서서 엉덩이가 들린다.
  다른 쪽 무릎은 허벅지가 닿는 땅 자리로 미끄러져 오고, 정강이·발이 묻히면 그 무릎을 조금씩 띄운다(`knee_rise`), 허벅지가 다 서도 모자라면
  정강이를 땅 쪽으로 기울여 발끝을 땅에 댄다. 축 무릎은 쉽게 바꾸지 않는다(`KNEEL_PIVOT_HYST`). 몸을 숙이는 몫은 골반(`lean`)보다 허리(`torso`)에 둔다
  — 골반째 90도 숙이면 앞뒤 엉덩이 관절(옆에서 본 그림이라 앞뒤로 벌어져 있다)이 위아래로 벌어져 뒷다리가 땅에 닿지 못한다.
  (2026-10-20 검수 전엔 몸 전체를 들어 가슴만 땅에 닿고 엉덩이·무릎·발이 28~47px 떠 '널빤지'처럼 엎드렸다.) 등불 기사의 엎드림도 같은 방법.
- 뒤로 (앞에서 맞아 밀림 — 흔한 경우): `dead_back`(엉덩방아) → `dead_back_lie`(골반째 `lean` −84 로 뒤로 굴러 등으로 눕기).
  이때 그림 쪽이 **내려놓기**(`motion.ground_settle`)를 올린다: 다리·무기 사슬·부드러운 부위를 뺀 몸의 가장 낮은 점을 **정확히** 땅에 두고
  다리는 IK 로 딛은 발에 맞춘다 → 닿는 점이 엉덩이·뒷손 → 등 → 뒤통수로 옮겨 가며 구르듯 눕는다.
  누울 때 팔 각도는 몸통 틀 기준이라 0 = 발 쪽으로 몸을 따라 눕는다. 칼팔은 `+` 로 땅 쪽에 떨어뜨리면 땅 막기가 땅 위에 얹는다.
  발 자리(`foot_*`)가 다리 길이보다 멀면 엉덩이가 끌려 내려가 몸이 들리니 0.4~0.6 L 로.
- 몸통이 없는 짐승·기계(EnemyMechVisual)는 다리가 꺾여 배가 땅에 닿는다 (밀린 쪽 다리부터, 발은 들지 않고 미끄러지며 벌어짐 — `slide_feet_to_pose`).
  정화로 쓰러지면 기계는 멈춰 선 채 힘이 빠진다.
- 거대화 몹의 `tilt_scale`(몸 기울기 줄이기)은 서 있는 동안만 — 쓰러질 땐 1 로 돌아가 끝까지 눕는다.

### 원형 파일 `data/rigs/_archetypes/<이름>.json`

```jsonc
{
  "extends": "humanoid",          // 선택: 다른 원형의 자세를 물려받고 아래 값이 자세별로 덮어쓴다
  "base": {"wing_f": 0, "wing_b": 0},   // 움직일 뼈는 base 에 0 으로라도
  "idle": {"wing_f": -20}, "windup": {…}, "strike": {…},
  "_motion": {                    // 움직임 지도 (RigPoses.HUMANOID_MOTION 과 같은 키, 빠진 키는 사람 값)
    "strike_lag": {"wing_f": 0.15},          // 타격에서 늦게 따라오는 몫 (채찍)
    "early": ["torso", "lean"], "heavy": ["torso", "lean", "hip_y"],
    "impact": {"torso": -1.0, "neck": -1.2},  // 맞았을 때 젖혀지는 채널·배수
    "parry": {"wing_f": -1.0}, "recoil": {"neck": -0.6}, "parry_bounce": ["wing_f", "torso"],
    "breath": {"torso": [1.3, 0.0]},          // [세기(도), 위상]. 그림이 박마다 따로 들썩이면 비운다 (무쇠 펌프)
    "swing": {"wing_b": -10}, "swing_abs": {},  // 걸음 팔 흔들기
    "leg_unit_reach": 0.95        // 선택: 다리 길이 단위 L = 두 마디(허벅지+정강이) 길이 × 이 값 (새처럼 발 높이가 큰 다리 — 0/없음 = 다리+발 높이)
  }
}
```
뼈 이름이 사람과 다르면 `_motion` 을 꼭 적는다 — 안 적으면 사람 팔 이름에만 충격·받아침·숨쉬기가 더해져 새·기계는 맞아도 움찔하지 않는다.
**`rig_poses.gd` 의 `SETS` 는 고치지 않는다** (여럿이 동시에 원형을 더하면 한 파일이 부딪힌다). 모르는 이름을 쓰면 경고가 나고 probe_rigs 가 실패한다.

**움직임 원칙** (RigMotion 머리말): 자세는 절대 '툭' 바뀌지 않는다 — 상태가 바뀌면 이전 목표가 관성을 갖고 흘러가며 섞이고
모든 채널이 스프링/감쇠로 쫓는다 (delta 기반). 휘두르기 `three_beat(from, windup, strike, ready, 국면, 진행도)`:
예비(당기며 끝에서 멈칫, 허리는 끝자락에 먼저 풀림) → 타격(어깨 먼저, 팔꿈치·무기 늦게 채찍처럼, 끝에서 지나침) → 되돌림(출렁이며 준비).
진행도는 EnemyBase 의 `windup_progress`/`phase_progress` 를 그대로 쓰므로 국면 길이가 바뀌어도 모양은 같다.
여러 장면을 잇는 연속기(3연격·도약 내려찍기)는 `motion.sample_clip([[0.0, "windup"], [0.35, "strike_1", "strike"], …], 지난 시간)`.

---

## 4. 몹 그림 (EnemyRigVisual)

씬의 `Visual` 노드 스크립트를 `res://scripts/enemies/enemy_rig_visual.gd`(또는 그것을 이은 스크립트)로 바꾸고 예전 값(texture, arm_*, art_scale, foot_offset …)을 지운 뒤:

```
[node name="Visual" type="Node2D" parent="."]
script = ExtResource("2_visual")
rig_id = "woodcutter"
```
- 크기: `art_scale` (1 = 설계도 `game_scale` 그대로). 거대화 중간 보스는 EliteTraits 가 1.8 배로 키운다. 잿가지 거인은 씬에 `art_scale = 1.72`.
- 구원형: `warm_eye = true`, `npc_rig = "<구원형 id>"` (구원된 사람도 같은 뼈대로 선다), `texture` = 한 장 그림(뼈대가 없을 때 대신).
  집(`data/dialogue/relocations*.json`)에도 `"rig": "<id>"` 를 적으면 집에서도 뼈대로 선다.
- 발이 닿는 땅 = 몸 충돌 캡슐의 바닥 (저절로 찾는다 — 누운 캡슐의 기계도 EnemyMechVisual 이 찾는다).
- 공개 함수·값은 예전 그림과 같다 (kick/impact/parried/block/recoil/fall, visible_facing/is_facing_settled, show_overhead_bar,
  arm_front/arm_front_limit/tilt_scale, _label …) — EnemyBase·EliteTraits·경비병 판정이 그대로 동작한다.
- `npc_look()` 은 구원된 사람을 세울 땅(`floor_y` = 몸 캡슐 바닥)도 돌려준다 — EnemyBase 가 그 자리에 세운다 (hurt_height 절반은 캡슐 바닥보다 5px 아래였다).
- `turn_min_width`: 돌아설 때 줄이는 폭의 한계 (사람 모양 0 = 폭이 0 을 지나며 몸을 튼다, 몸이 긴 기계 0.5 = 절반까지 줄이고 쿵 뒤집기 — EnemyMechVisual).
- 움직임 층을 바꿔 쓰려면 `_make_motion()` 을 덮어쓴다 (기계·어부의 HookedRigMotion — 두 번 만들지 않게).
- 몹 상태의 속 값은 공개 함수로 읽는다: `EnemyBase.state_timer()`, `Guard.is_block_open()`.
- 화면 밖에서 대기·순찰 중인 몹은 뼈대를 쉰다 (`_cull_quiet` — VisibleOnScreenNotifier2D, 화면 없는 시험에서는 꺼짐). 다른 상태는 화면 밖에서도 움직인다.
- 한 번 공중이 되면 땅에 닿을 때까지 공중 자세 (폴짝 뛴 꼭대기에서 세로 속도가 잠깐 작아져도 걸음을 시작하지 않는다).
  뼈대는 늘 오른쪽을 보므로 `art_faces_right` 는 참으로 친다 (probe_guard 도 그렇게 잰다).
- `anim_hint` 별 자세: red(붉은 예고) / charge / stuck / shoot / scatter / leap / fall / land — 이름은 그대로, 자세는 원형에서.
- 시험이 예전 그림의 속(`_sprite`, `_arm_bone`)을 읽으면 `vis is EnemyRigVisual` 로 갈라 뼈대 값을 읽는다 (tools/probe_enemies.gd 의 `_pose` 참고).

### 몹만의 연출을 더하는 방법 (상속)

공용 파일(enemy_rig_visual.gd)은 고치지 않고 **자기 파일에서 EnemyRigVisual 을 이어** 더한다. probe_rigs 는 이은 스크립트의 씬도 저절로 찾는다.

| 방법 | 예 | 하는 법 |
|---|---|---|
| **자세 바꿔 끼우기** | 경비병(돌진 준비·박힘 버둥·방패 들림), 정원사·약초꾼(물러날 때 `walk`/`idle` → `backstep`) | `_process` 에서 `motion.poses[이름]` 을 상태에 맞는 자세 사전으로 바꾼 뒤 `super._process(delta)`, 필요하면 원래 자세로 되돌린다. 자세 사전은 `_ready` 에서 미리 만들어 둔다 (매 프레임 새 사전 금지) |
| **움직이기 직전 갈고리** | 기계(드릴 떨림·들이받기 예고·쓰러질 때 다리 벌림), 어부(펌프질) | `motion = HookedRigMotion.new(rig, _pre_motion)` — `_pre_motion(delta)` 에서 `motion.target[…]` 을 고친다. 발을 끌어 벌릴 땐 `motion.slide_feet_to_pose(속도, delta)` |
| **업데이트 뒤 덧고침** | 오웬(뒷손 두 뼈 IK 로 자루 쥐기), 약초꾼(버섯 배율) | `super._process` 뒤에 `rig.set_bone_rot(i, 각도, false)` … `rig.compute_from(맨 위 뼈)` → `rig.apply()` (6장) |
| **덧그림** | 어부 낚싯줄(숨은 부위 `whip_*` 조각을 줄 물리로) | `rig.skeleton_node()` 에 Sprite2D 를 손 그림 바로 아래 순서로 넣어 같은 셰이더(`use_parent_material`)를 쓴다 |
| **빛·입자** | 오웬 등불, 기계 등불·김·불꽃, 약초꾼 버섯 빛(어두운 방에서만 PointLight2D) | `rig.attach(뼈, 노드, 자리)` 또는 `rig.bone_point(뼈, 자리)`. 빛 텍스처는 몹끼리 함께 쓴다 (모바일 메모리) |
| **변형 얼굴** | 구원형 무릎 꿇는 동안 눈 감음, 정화되면 눈 뜸 | `rig.set_variant("head", "closed")` / `""` |

**EnemyMechVisual** (기계 몹 공용, `EnemyRigVisual` 상속): 도는 부위(`spin_bone`, 드릴 빛 줄 셰이더 + 떨림), 빛나는 소켓(`glow_sockets`)·부위(`glow_parts`),
김(`steam_socket`)·불꽃(`spark_socket`), 늘 겨누는 대롱(`aim_always_range`), 쏠 때만 보이는 부위(분사), 쓰러짐(정화 = 선 채로 / 부서짐 = 배가 땅에).
자세는 `drill_beast.json`·`pipe_walker.json`. 새 기계 몹은 설계도 + 원형 + 씬의 이 값들만으로 만든다.

---

## 5. 보스 그림 (직접 묶기)

보스 그림(`scripts/bosses/*_visual.gd`)은 상태가 보스마다 달라서 EnemyRigVisual 대신 직접 묶는다.
보스 씬의 그림 노드 이름·종류(`Sprite`, Sprite2D)는 보스 논리·시험이 찾으므로 그대로 두고, 예전 텍스처·자리·배율만 지우고 자식으로 PartRig 를 둔다.

```gdscript
var rig := PartRig.new()
var motion: RigMotion
func _ready() -> void:
	add_child(rig)
	rig.build("gray_leaf_bird")          # art/rigs/gray_leaf_bird/rig.json
	motion = RigMotion.new(rig)
	rig.setup_ghosts(["torso", "wing_f_in"], 6)
func _process(delta: float) -> void:
	var p := motion.pose("idle")
	match boss.state:                    # 보스 상태 → 자세 (세 박자는 three_beat, 진행도는 보스의 phase_progress)
		…
	motion.set_target(p, RigMotion.Drive.SOFT, RigMotion.Feet.POSE)   # 날고 있으면 Feet.AIR
	motion.update(delta, {"speed": vx / k, "dx": dx / k, "vy": vy / k, "grounded": on_floor})   # k = rig.game_scale * 배율, 보이는 방향 기준 + = 앞
	# (덧고침이 있으면 여기서 — 6장) …
	rig.position = Vector2(0, floor_y)   # 원점 = 발이 닿는 땅
	rig.scale = Vector2(facing * 배율, 배율)   # 좌우를 뒤집은 프레임엔 motion.flip_feet()
	rig.set_flash(boss.flash_amount() * 0.75)
```

보스 자세는 원형 파일을 만들거나(3장) 설계도 `poses` 에 자세 이름을 새로 지어 넣는다 (`motion.pose("wing_beat")`). 다섯 보스가 쓴 방법:

| 하고 싶은 것 | 방법 (쓴 보스) |
|---|---|
| 쓰러져 눕기 | `motion.ground_lock = 1` (몸이 땅에 박히지 않게) + 누워 쉬는 자세면 `motion.ground_settle` (정확히 땅에 붙이기). 엎드림·옆으로 눕기·무릎→기댐→엎어짐 순서는 자세 섞기로 (모두) |
| 날거나 떠 있기 | `Feet.AIR` (다리를 접어 매단다) + `motion.set_root_lift(높이, 공중이면 true)` 로 서 있는 뿌리를 띄운다 (새) |
| 다리 IK 없이 땅에 앉기 | 설계도 `legs` 를 비우고 땅에선 `ground_settle = 1` 로 가장 낮은 점을 땅에 (여왕) |
| 빠른 주기 움직임 (날갯짓·등불 흔들림) | 위상 누적기(`_phase += rate * delta`) — 느린 것은 자세 사전을 `duplicate()` 해 채널에 `sin(위상) * 세기` 를 더하고, 스프링에 뭉개지면 안 되는 빠른 것은 update 뒤 `rig.turn_bone(i, 각, false)` 후 `rig.apply()` (여왕) |
| 두 손 무기 | 앞손 IK → 무기를 세상 각도로 → 뒷손 두 뼈 IK 로 손잡이 소켓 (기사·오웬) |
| 무기 땅 짚기·땅 막기 (축 없는 뼈·무기 사슬 밖) | update 뒤 껍질의 가장 낮은 점을 재서 `rig.turn_bone` / `rig.set_bone_offset` 으로 들어 올린다. 지난 프레임의 해를 먼저 써서 프레임마다 해가 튀지 않게 (뿌리지기 지팡이·새 날개·펌프 대포) |
| 진자 (매단 등불) | 매단 자리의 세상 가속도로 각을 적분하고 `rig.set_bone_rot` (기사) |
| 망토를 누운 몸에 늘어뜨리기 | `motion.set_chain_setting("cape", 중력, 최대각)` (기사) |
| 걷기 시작 발 맞추기 | `motion.set_gait_phase(위상[, true])` — 아무 위상에서 시작하면 뒤에 디딘 발이 끌려가 엉덩이가 툭 떨어진다 (기사·펌프) |
| 돌아서기 | 폭을 줄였다가 부호가 바뀌는 프레임에 `flip_feet()`. 옆모습 짐승은 이어서 `swap_leg_sides(0, 1)` (앞다리가 뒷다리가 된다 — 펌프). 폭은 절반 가까이(`TURN_MIN_W` 0.45)까지만 줄이고 그 프레임에 쿵 뒤집는다 — 0 까지 줄이면 한두 프레임 종잇장으로 보였다 (펌프·새·기사, 기사는 그 사이 정면 투구 변형) |
| 걸음에 맞춘 흔들림 | `motion.gait_phase()` 로 몸·머리를 박마다 흔든다 (기사) |
| 쓰러진 자세 이어받기 | 같은 뼈대의 다른 PartRig 에 `copy_pose_from(src)` (멈춘 펌프) |
| 시험이 읽는 값 | 그림에 `probe_pose()` 를 둔다 — probe_bosses 의 `_vpose` 는 배열 `[기울기, 배율, 세로 자리]` 를 읽는다 (기사). 사전을 돌려주는 그림(펌프)은 전용 검사가 읽는다 |

판정(히트박스)·시간은 보스 스크립트 그대로 두고, 무기 끝·투사체 나오는 자리가 필요하면 `rig.bone_point("weapon", 끝 자리)` 로 읽는다.
투사체가 나오는 자리(논리 상수)가 그림과 다르면 **그림을 그 자리에 맞춘다** (새 깃털은 날개 앞깃 끝에서, 여왕 가루·나비는 손 근처에서).

---

## 6. 공개 도우미 — 속 값을 직접 고치지 않는다

그림 스크립트·시험은 `_` 로 시작하는 RigMotion·PartRig 의 속 값을 고치거나 읽지 않는다 (틀이 바뀌면 조용히 깨진다).
필요한 것이 없으면 아래처럼 작은 공개 함수를 더한다.

**RigMotion**
| 함수 / 값 | 뜻 |
|---|---|
| `poses`, `target` (읽기·쓰기) | 자세 사전(바꿔 끼우기 가능), 이번 프레임 목표(갈고리에서 고치기 가능) |
| `breath`, `tilt_scale`, `ground_lock`, `ground_settle`, `fall_angle`/`fall_pivot` (쓰기) | 숨쉬기 세기, 몸 기울기 배수, 땅 닿기·내려놓기 세기, 통째 쓰러짐 |
| `fin`, `legs`, `L`, `stand_root_y`, `keys` (읽기만) | 최종 채널 값, 다리(Leg 의 `x`/`h`/`planted_now` 읽기), 다리 길이 단위, 서 있는 뿌리 높이 |
| `channel(이름)` | 채널의 스프링 값 (덧붙임 뺀 값 — 덧붙임까지는 `fin`) |
| `gait_phase()` / `set_gait_phase(p, land_feet := false)` | 걸음 위상 읽기 / 정하기 (걷기 시작 발 맞추기) |
| `swap_leg_sides(a, b)` | 두 다리의 디딘 자리 맞바꾸기 (`flip_feet()` 다음, 옆모습 짐승이 돌아설 때) |
| `set_root_lift(h, move_hanging_feet)` / `root_lift()` | 떠 있는 높이 (서 있는 뿌리를 설계도 값에서 올린다) |
| `slide_feet_to_pose(speed, delta)` | 발을 들지 않고 자세의 발 자리로 미끄러뜨림 (update 전에) |
| `is_airborne()` | 공중 자세(다리를 접어 매단 상태)인가 |
| `lock_bones()` / `settle_bones()` / `soft_bones()` / `body_lowest_y()` | 땅 닿기·내려놓기에 쓰는 뼈들, 부드러운 부위, 몸의 가장 낮은 점 (시험이 잰다) |
| `chain_setting(뼈)` / `set_chain_setting(뼈, 중력, 최대각)` | 늘어진 천 설정 |
| `kick(이름, 속도)`, `spring_value`, `scale_velocity`, `flip_feet`, `snap_feet`, `transition`, `capture`, `mix`, `three_beat`, `sample_clip`, `sole_ys`, `any_swing` | 그 밖의 원래 공개 함수 |

**PartRig** (덧고침: motion.update() 뒤 → 고치고 → `apply()` 한 번)
| 함수 | 뜻 |
|---|---|
| `bone_rot(i)` / `turn_bone(i, 각, recompute := true)` / `set_bone_rot(i, 각, recompute)` / `set_bone_world_rot(i, 세상 각, recompute)` | 지역 회전 읽기 / 더 돌리기 / 정하기 / 세상 각도로 정하기 (recompute = 그 뼈와 자식 변환을 바로 다시 계산) |
| `bone_offset(i)` / `set_bone_offset(i, 자리, recompute)` | 관절 자리에 더하는 자리 (자루를 손 안에서 미끄러뜨리기) |
| `bone_scale(i)` / `set_bone_scale(i, 배율)` | 부위 배율 (부위 크기 맞춤·날개 접기·버섯 부풂) |
| `bone_squash(i)` / `set_bone_squash(i, k)` | 부드러운 부위가 눌린 정도 |
| `compute_from(i)` / `apply()` | 여러 뼈를 recompute=false 로 고친 뒤 맨 위 뼈부터 다시 계산 / 그림에 옮기기 (apply 가 compute 한다) |
| `bone_xf(i)`, `xf`, `body_xf`, `hulls`, `bone_len`, `base_pos`, `parent` (읽기) | 뼈 변환·껍질 점 등 |
| `copy_pose_from(src)` | 같은 뼈대의 다른 PartRig 자세를 그대로 (뼈 수가 다르면 false) |
| `skeleton_node()` | 부위 그림이 놓인 노드 (덧그림을 부위 사이에 끼울 때) |
| `bone_point`, `to_rig_local`, `attach`, `set_variant`, `sprite_of`, `set_facing`, `set_flash`, `set_dissolve`, `lowest_y`, `highest_y`, `bounds`, 잔상 함수 | 그 밖의 원래 공개 함수 |

---

## 7. 검사와 필름 도구

**검사 (화면 없이, 전체 회귀 `regress.sh` 가 모두 돌린다)**
| 도구 | 보는 것 |
|---|---|
| `tools/probe_rigs.tscn` | 모든 뼈대: 읽히는지, 뼈 계층·부위 그림·다리/땅 막기 이름·원형·soft 이름·변형 그림, 발 ±4px(대기·걷기·공격·무너짐·피격·무릎), 몸·무기가 땅 아래 4px 넘게 안 들어감, NaN, 상자, 비용. 뼈대 몹 씬(이은 Visual 포함)의 앞·뒤 쓰러짐(몸통 ≤ 키의 30%·머리 ≤ 35%·무기 ≤ 45%, 앞으로는 다리 뼈마다 가장 낮은 점 ≤ 키의 12%·뒤로는 두 다리 중 한 점 ≤ 12%, 몸통 없는 기계는 배가 땅에), 대롱 겨눔(진짜 대롱 몹으로) |
| `probe_enemies`, `probe_guard` | 몹 공통 동작·받아치기, 경비병 방패가 보는 쪽에 그려지는지·늦게 돌기·막기 한계 |
| `probe_gardener_herbalist` | 정원사·약초꾼 6종 실제 AI: 발 디딤·겨눔·반동·웅크림·버섯·포자·구원 |
| `probe_bosses` | 보스 다섯의 패턴 흐름·타격 정점이 판정 구간 안·탄막. 새(`_bird_run`)·뿌리지기(`_root_watch`)는 뼈 값으로, 기사는 `probe_pose` 로. **무기 끝 자리 vs 켜진 판정 상자**(`_weapon_sync`): 기사 찌르기·3연격 첫 타 창끝 높이·앞 끝, 내려찍기 창끝이 판정 폭 안 땅에 닿는 때, 검기가 나갈 때 창이 몸 앞, 새 쪼기 부리 |
| `probe_knight_rig`, `probe_queen`, `probe_pump_rig`, `probe_root_visual`·`probe_root_fixes` | 보스별 뼈대 전용 검사 (발·몸 깊이·튐·누움(기사: 다리 뼈마다 키의 8% 안)·정화·비용) |
| `probe_lake -- --hidden`, `probe_mine -- --linked`, `probe_npcs` | 어부·여왕 박자, 펌프·멈춘 펌프, 구원된 사람·집 |
| `tools/test.sh <보스 방> --bosstest 260` (보스 5곳) | 실제 방에서 정화까지 |

**필름 (창으로 — 결과는 screenshots/, 저장소에 올리지 않는다)**
| 도구 | 찍는 것 |
|---|---|
| `tools/rig_preview.tscn` | `--parts` 부위 격자 / 자세 사진(`--lock` = 땅 닿기·내려놓기를 켜고 쓰러진 자세를 게임처럼) / `--enemy <씬> --seq …` 몹 동작 필름 (상태를 직접 걸어서) |
| `tools/rig_film_ai.tscn` | 몹 AI 그대로 (소녀를 정한 거리에): `--seq idle,walk,ram,slam,shoot,whip,attack,hit,broken,dead,dead_back,purify,kneel` |
| `probe_gardener_herbalist.tscn -- --film <gardener\|herbalist>` / `-- --shots` | 평평한 바닥 실제 AI 필름 / 실제 방 장면 |
| `tools/bird_film.tscn`, `tools/bird_room_shots.tscn` | 새 동작 필름 / 실제 보스 방 상태별 사진 |
| `tools/knight_film.tscn [-- --p2 --at 0.62]`, `tools/probe_knight_view.tscn` | 기사 동작 필름 / 실제 방 패턴 사진 |
| `tools/root_keeper_film.tscn [-- --phase 2]` | 뿌리지기 동작 필름 + 땅 닿기 수치 |
| `tools/queen_film.tscn -- --film / --game / --render / --fallback` | 여왕 필름 / 실제 방·보스곡 박자 장면 / 조립 그림 / 대신 그림 |
| `tools/pump_film.tscn [-- --shot piston:0.95]`, `tools/pump_render.tscn`, `flooded_mine_boss.tscn -- --bossshots` | 펌프 필름 / 조립 그림 / 실제 방 사진 |

---

## 8. 교훈과 함정

- **가장자리의 쓰레기 색**: 이 시트들은 반투명 가장자리에 빨강·노랑 RGB 가 묻어 있다. rig_cut 은 자른 부위마다 `defringe` 한다
  (tools/sheet_catalog.gd). 새 도구로 자를 때도 꼭 `defringe`.
- **상자가 겹친다**: 부위 상자끼리 겹치므로 상자로 자르지 말고 **조각 마스크**(comps)로 자른다.
- **닿아 있는 부위**: 부위가 서로 닿아 한 조각이면 `segment.erode` 를 키우거나 `clip`/`cut` 다각형으로 나눈다. `erode` 를 바꾸면 **번호가 바뀐다**.
- **관절 틈**: 관절 둘레는 두 부위가 겹쳐야 한다. 다각형 경계를 관절 둥근 곳 너머로 잡고(`grow` 3px 가 기본), 위에 그리는 부위(z 큼)가 덮게 한다.
  목둘레 깃처럼 틈을 가리는 부위는 z 를 몸통 위로 (여왕).
- **완성 그림에서 자른 부위**: 따로 그린 옷 조각이 완성 모습과 맞지 않으면 완성 그림을 자르고, 자른 선은 페더로 녹이고, 팔·지팡이에 가려졌던
  구멍은 같은 그림의 옷감 조각을 숨은 부드러운 부위로 메운다 (뿌리지기 `fill_*`).
- **발목이 네모로 잘려 보인다**: 발 `clip` 을 직사각형 대신 윗변이 둥근 돔으로 (발 관절 둘레까지 정강이와 겹치게).
- **뒷팔·뒷다리가 없는 시트**: 앞쪽 그림을 `from` 으로 다시 쓰고 `modulate` 로 어둡게 (경비병·오웬·기사). 기획자에게 따로 그린 그림을 부탁한다.
- **색이 진하게 보임**: 셰이더 fragment 의 `COLOR` 는 이미 텍스처 × modulate 다. 텍스처를 또 곱하지 않는다 (rig_flash 참고).
- **HDR 스크린샷**: 2D HDR 화면을 그대로 저장하면 어둡다 — `rig_preview.gd` 의 `_grab()` 처럼 RGBA8 로 바꾼 뒤 `linear_to_srgb()`.
- **필름 칸이 빈 회색**: 창이 가려지거나 화면이 잠기면 그 뒤 칸이 단색으로 찍힌다 (파일이 수 KB). 동작을 몇 개씩 나눠 다시 찍는다 — 그림 탓이 아니다.
- **서 있는 높이 계산의 발바닥 부호** (2026-10-20 고침): 예전 `_setup_legs` 는 발바닥 오프셋을 반대 부호로 더해, 발바닥이 발목에서 멀리 떨어진 다리(기계)가
  크게 웅크린 채 섰다. 고친 뒤 다른 뼈대의 서 있는 높이 차이는 게임에서 3px 아래였다 (기계는 18px). 새 뼈대는 고친 식 기준으로 맞춘다.
- **걸음이 엉덩이를 떨어뜨린다**: 방향이 바뀌거나 걷기 시작할 때 뒤에 디딘 발이 멀리 남으면 다리가 닿지 않아 엉덩이가 내려앉는다
  → 틀이 그 발부터 옮기고(GAIT_RESYNC) 엉덩이 낮춤에 한계(DROP_MAX, L 의 0.3)를 둔다. 보스처럼 보폭이 빠듯하면 `set_gait_phase` 로 시작 위상도 맞춘다.
- **새 다리처럼 발이 높은 다리**: 발 높이까지 L 에 넣으면 보폭이 다리가 닿는 거리보다 길어진다 → 원형 `_motion.leg_unit_reach`.
- **긴 무기**: 칼끝이 땅에 파고들면 `ground_guard` 에 무기 부위를 넣는다 (어깨부터 들어 올린다). 자세에서 팔을 더 앞으로 드는 게 먼저.
  무기 사슬 밖의 부위(대포·지팡이·날개)는 그림 쪽에서 따로 막는다 (5장).
- **반쯤 꿇기 금지**: `kneel` 은 0 아니면 1. 0.5 는 무릎이 땅 위에 떠서 어색하다 (섞이는 동안만 중간값).
- **뼈대는 오른쪽을 본다**: 그림 쪽은 `scale.x` 부호로 뒤집는다. 뒤집는 순간 `motion.flip_feet()` (딛은 발이 세상에 남게).
- **치마·망토·날개가 몸을 띄운다**: 무릎 꿇기·누움에서 몸이 떠 보이면 늘어진 그림을 `soft` 에 넣는다. 다리에 붙어 그려진 천 자락·정강이 잎도
  다각형으로 떼어 chain 부위로 만들면 쓰러질 때 몸을 받치지 않는다 (정원사·약초꾼).
- **방패 몹 시험**: 앞에서 치면 방패가 막아 쓰러지지 않는다 — 쓰러짐을 찍거나 잴 땐 `_block_open` 을 열어 둔다 (probe_rigs·rig_preview).
- **매 프레임 새 사전**: 자세 바꿔 끼우기·상수 목록은 `_ready` 에서 만들어 돌려 쓴다 (모바일 비용). 뼈대 하나는 맥에서 0.1~0.2ms, 아이폰은 2~3배로 본다.
- **판정 상자는 Hitbox 노드 자리만큼 올라가 있다**: 보스 히트박스 노드가 (0, −60) 에 있어 `set_box(Rect2(…, -150, …))` 의 실제 높이는 60px 더 위다.
  자세를 맞출 땐 숫자가 아니라 `probe_bosses` 의 `_weapon_sync`(또는 켜진 상자를 겹쳐 그린 필름)로 무기 끝이 상자 안에 드는지 본다
  (2026-10-20: 기사 찌르기 창끝이 정강이 높이·상자 밖, 내려찍기 창이 상자 밖 470px, 검기가 창보다 먼저, 새 부리가 상자 위에서 멈췄다).
- **타격 시작에 맞는 순간이 오는 공격**(내려찍기 충격파·뿌리 가시·검기 발사): 휘두르기를 타격 앞부분(`minf(p / 0.2~0.3, 1)`)에 몰거나 예비 끝자락에 당겨
  (뿌리지기 `SPIKE_STRIKE_AT`, 기사 `SLAM_PRE_SPEAR`) 그림의 '닿는 순간'이 판정이 켜지는 때와 겹치게 한다. 판정·시간은 바꾸지 않는다.
- **골반째 크게 숙이면 뒷다리가 뜬다**: 옆에서 본 그림이라 앞뒤 엉덩이 관절이 가로로 벌어져 있다 — 골반을 90도 숙이면 그 간격이 세로가 되어
  뒤 엉덩이가 20px 넘게 높아진다. 엎드림은 숙이는 몫을 허리(`torso`)에 둔다.
- **probe 숫자가 실행마다 조금 다르다**: 보스·몹 AI 가 공격을 무작위로 고르므로 (기사·펌프·정원사 검사) 숫자 차이는 흔들림이다 — 판정은 '실패 0' 으로 본다.
- **익스펜션/ 은 읽기만**: 원본 시트를 고치거나 옮기지 않는다. 잘린 그림만 `art/rigs/` 에.
- **probe_rigs**: 새 뼈대를 넣으면 저절로 검사된다. 실패하면 먼저 rig_preview 로 그 자세를 찍어 본다.

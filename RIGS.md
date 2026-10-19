# 부위 뼈대 (파트 리그) 만드는 법

몹·보스의 그림을 **부위별 그림 + 관절**로 움직이는 방법을 적은 문서다. (2026-10-20, 나무꾼으로 처음 만듦)
기획자가 부위를 따로 그려 준 시트(`익스펜션/그림/리뉴얼-몹`, `리뉴얼-보스`, `몹`, `보스`)를 잘라 관절로 잇고,
코드가 자세를 만들어 움직인다. 발은 땅을 딛고, 휘두르기는 허리 → 어깨 → 팔꿈치 → 무기 순서로 채찍처럼 나가고,
쓰러질 때는 무릎이 꺾인 뒤 엎어지거나 엉덩방아를 찧는다. **판정·시간은 건드리지 않는다 — 그림이 논리를 따라간다.**

| 파일 | 하는 일 |
|---|---|
| `data/rigs/<id>.json` | **설계도** (사람이 쓴다, 저장소에 둔다): 어느 시트의 어느 조각이 어느 부위인지, 관절 자리, 부모, 앞뒤 순서, 자세 고치기 |
| `tools/rig_cut.gd` | 자르기 도구: 조각 번호 미리보기, 시트 확대 보기, 부위 자르기 → `art/rigs/<id>/` |
| `art/rigs/<id>/*.png`, `rig.json` | 잘린 부위 그림(가장자리 정리·밉맵) + 실행용 뼈대 (도구가 만든다 — 손으로 고치지 않는다) |
| `tools/rig_preview.tscn` | 확인 화면 (창으로 띄운다): 부위·관절 표시, 자세별 스크린샷, 실제 몹 씬의 동작 필름 |
| `scripts/rig/part_rig.gd` | `PartRig` — 뼈대 노드: 부위 그림을 관절로 잇고 그린다 (변형 그림, 번쩍임·흩어짐 셰이더, 잔상) |
| `scripts/rig/rig_motion.gd` | `RigMotion` — 움직임: 스프링 보간, 세 박자 휘두르기, 걸음·발 디딤, 다리 IK, 무릎 꿇기, 무기 땅 막기, 천 흔들림, 땅 닿기 |
| `scripts/rig/rig_poses.gd` | `RigPoses` — 원형(archetype)별 자세 모음. 설계도의 `poses` 가 덮어쓴다 |
| `scripts/enemies/enemy_rig_visual.gd` | `EnemyRigVisual` — 일반 몹의 Visual (EnemySpriteVisual 을 갈아 끼운다) |
| `shaders/rig_flash.gdshader` | 부위 공용 재질: 피격 번쩍임, 흩어져 사라짐 |
| `tools/probe_rigs.tscn` | 검사: 모든 뼈대가 읽히는지, 발이 땅에 붙는지, 땅에 파고들지 않는지, NaN·상자·비용 |

병렬 작업 폴더에서는 Godot 을 늘 래퍼 `/Users/wj/Projects/SeedWT/godot` 로, `perl -e 'alarm 300; exec @ARGV'` 로 감싸서 돌린다.
아래 예의 `G` 는 그 래퍼다.

---

## 1. 자르기 순서 (한 캐릭터에 30~60분)

1. **조각 번호 보기**: 설계도에 `sheet`·`faces`·`segment` 만 적고(아래 2장) 실행한다.
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
4. **자르기**: `G --headless --path . --script tools/rig_cut.gd -- <id>` → `art/rigs/<id>/`. 그다음 **반드시**
   `GODOT=/Users/wj/Projects/SeedWT/godot tools/cloud_bootstrap.sh` (새 그림 가져오기·밉맵).
5. **부위 확인** (창으로): `G --path . res://tools/rig_preview.tscn -- <id> --parts`
   → `screenshots/rig_<id>_parts.png`: 부위마다 그림 + 빨강 = 관절(pivot), 파랑 = 축 끝(tip), 노랑 = 자식이 붙는 자리, 초록 = 발바닥.
   자식의 노랑 점이 부모 그림의 관절 자리에 있어야 한다.
6. **자세 확인** (창으로): `G --path . --resolution 1600x900 res://tools/rig_preview.tscn -- <id> --zoom 3.5 [--joints] [--poses idle,windup,strike,kneel]`
   → 자세마다 `screenshots/rig_<id>_<자세>.png` + 모아 보기 `rig_<id>_poses.png`. 발을 크게: `--zoom 9 --cam_y 0.12`.
   **틈(관절 사이 배경이 비침), 튀어나옴, 앞뒤 순서(z), 발이 땅에 붙는지**를 본다.
7. **실제 몹 동작 필름** (창으로, 씬의 Visual 을 바꾼 뒤):
   `G --path . --resolution 1600x900 res://tools/rig_preview.tscn -- --enemy res://scenes/enemies/<몹>.tscn --zoom 3 --seq idle,walk,attack,hit,broken,dead,dead_back,kneel --every 0.05 --crop 0.45`
   → `screenshots/rig_<몹>_<동작>.png` (0.05초 간격 칸). 예고 → 타격 → 되돌림이 세 박자로 읽히는지, 발이 미끄러지지 않는지.
8. **검사**: `G --headless --path . res://tools/probe_rigs.tscn` (실패 0), 그리고 그 몹의 방 시험.
9. 4~7 을 **틈이 없고 움직임이 자연스러울 때까지** 되풀이한다. 스크린샷은 `screenshots/` 라 저장소에 올리지 않는다.

---

## 2. 설계도 `data/rigs/<id>.json`

좌표는 **모두 원본 시트 px** (미리보기 격자 숫자 그대로). 각도는 **도(degree)**.

```jsonc
{
  "id": "woodcutter",
  "sheet": "res://익스펜션/그림/리뉴얼-몹/AF637C8F-….PNG",   // 읽기만 한다 (익스펜션/ 은 절대 고치지 않는다)
  "faces": "left",              // 시트 속 인물이 보는 쪽. left 면 도구가 모두 뒤집는다 → 실행용 뼈대는 늘 오른쪽을 본다
  "segment": {"alpha": 0.5, "erode": 4, "min_pixels": 1500, "soft_alpha": 0.03, "min_small": 150},
  "out_scale": 0.5,             // 잘린 그림 크기 = 시트의 몇 배 (몹 0.5, 보스 0.8~1.0). 부위별 "scale" 로 더 곱할 수 있다
  "game_scale": 0.152,          // 시트 px → 게임 px (나무꾼: 키 1021 → 155). 크기 기준은 GAME_DESIGN 8장
  "archetype": "humanoid",      // 자세 모음 (RigPoses.SETS). 새 원형은 4장
  "extra_sheets": {"face": {"path": "res://익스펜션/…"}},   // 다른 시트의 부위·변형을 쓸 때 (부위에 "sheet": "face")
  "chains": {                   // 사슬: 이름 → [위, 아래, 끝]. 팔다리 축의 기본값(다음 마디 관절 쪽)과 다리 IK·무기 땅 막기가 쓴다
    "leg_f": ["leg_f_up", "leg_f_lo", "foot_f"],
    "arm_f": ["arm_f_up", "arm_f_lo", "weapon"]
  },
  "legs": ["leg_f", "leg_b"],   // 땅을 딛는 다리 (사슬 이름). 무릎이 뒤로 꺾이면 {"chain": "leg_b", "knee_back": true}. 한 뼈 다리는 사슬 [다리] 하나
  "weapon_chain": "arm_f",      // 무기 팔 사슬 (땅 막기: 어깨 → 팔꿈치 → 손목 순으로 든다)
  "ground_guard": ["weapon", "arm_f_lo"],   // 땅 아래로 들어가면 안 되는 부위 (칼끝이 땅에 닿아 멈춘 것처럼)
  "ghost": ["torso", "arm_f_up", "arm_f_lo", "weapon"],   // 휘두를 때 잔상으로 남길 부위
  "sockets": {"eye": {"bone": "head", "at": [452, 128]}},  // 뼈에 붙는 자리 (구원형 눈빛 등). PartRig.bone_point/attach
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
| `grow` | 다각형 경계를 이만큼(px, 기본 3) 넓힌다 → 이웃 부위와 살짝 겹쳐 이음매가 비치지 않는다 (`cut` 은 그만큼 좁힌다) |
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
| `from` | 다른 부위의 그림을 그대로 쓴다 (예: 같은 다리 그림을 앞뒤 다리에). 자기 `parent`/`attach`/`z` 는 따로 |
| `variants` | 바꿔 끼우는 그림: `{"face": {"sheet": "face", "comps": [3], "pivot": [x, y]}}` → `PartRig.set_variant("head", "face")`. `pivot` 은 그 그림에서 같은 관절 자리 |
| `chain` | 늘어진 천·잎·머리카락: `{"stiffness": 45, "damping": 6, "drag": 0.0003, "gravity": 0.4, "max": 35}` — 몸보다 한 박자 늦게 따라오고 달리면 뒤로 날린다 |
| `modulate` | 이 부위 색 `[r, g, b, a]` |
| `hidden` | 그리지 않는 뼈 (자리만, 예: 무기 끝 소켓용) |

### 사람 모양 + 무기 팔 (humanoid) 뼈 이름 약속

자세 모음(RigPoses.HUMANOID)이 이 이름을 쓴다. 같은 이름이면 정원사·약초꾼·경비병·오웬·어부도 **설계도만으로** 움직인다.

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
'앞' = 인물이 보는 쪽(오른쪽을 보는 뼈대에서 화면에 가까운 쪽 팔). 방패(경비병)는 `arm_b_lo` 아래 `shield` 같은 부위로 두고
자세에서 각도를 준다. 대롱(정원사)은 `weapon` 을 대롱으로.

---

## 3. 자세 짓기

자세 = 채널 이름 → 값. RigPoses 머리말에 전체 약속이 있다. 요약:

- **몸**: `hip_x`, `hip_y` (다리 길이 L 의 몇 배, `hip_y` + = 웅크림), `lean` (골반째 기울기, 도, + = 앞으로)
- **발**: `foot_f`/`foot_b` (발 자리, L 배, + = 앞), `toe_f` (발 각도), `kneel_f` (0 아니면 1 — 그 무릎을 꿇는다), `pitch` (0~1, 꿇은 무릎에서 허벅지가 앞으로 눕는 정도)
- **걸음**: `step_thr` (발이 이만큼 어긋나면 한 걸음, L 배), `step_dur`, `step_lift`
- **뼈 이름**: 축 부위는 **절대 각도** (0 = 부모 틀에서 똑바로 아래, −90 = 앞으로 수평, −180 = 머리 위),
  축 없는 부위(몸통·머리)는 쉬는 자세에 **더하는** 각도 (+ = 앞으로 숙임).
- 팔 각도는 몸통 틀 기준: 몸통을 30도 숙이면 같은 팔 각도도 30도 더 뒤로 보인다. **세상에서 원하는 각도 − 몸통 각도**.
- 머리 위로 넘겨 내려치는 휘두르기는 각도가 머리 위를 지나며 이어지게: 예비 `−200` → 타격 `−88`. (`+160` 으로 쓰면 등 뒤 아래로 돈다.)

원형 자세 이름 (그림 쪽이 상태에 맞춰 고른다): `idle walk backstep alert air lunge windup strike ready hit broken kneel rescued
dead_knees dead_lie dead_back dead_back_lie shoot scatter_a scatter_b charge stuck leap slam_fall land npc`.
뼈대마다 다른 값은 설계도 `poses` 에 그 채널만 적는다 (나무꾼은 칼이 길어서 팔을 더 앞으로).

**움직임 원칙** (RigMotion 머리말): 자세는 절대 '툭' 바뀌지 않는다 — 상태가 바뀌면 이전 목표가 관성을 갖고 흘러가며 섞이고
모든 채널이 스프링/감쇠로 쫓는다 (delta 기반). 휘두르기 `three_beat(from, windup, strike, ready, 국면, 진행도)`:
예비(당기며 끝에서 멈칫, 허리는 끝자락에 먼저 풀림) → 타격(어깨 먼저, 팔꿈치·무기 늦게 채찍처럼, 끝에서 지나침) → 되돌림(출렁이며 준비).
진행도는 EnemyBase 의 `windup_progress`/`phase_progress` 를 그대로 쓰므로 국면 길이가 바뀌어도 모양은 같다.

---

## 4. 몹의 그림 바꾸기 (EnemySpriteVisual → EnemyRigVisual)

씬의 `Visual` 노드 스크립트를 `res://scripts/enemies/enemy_rig_visual.gd` 로 바꾸고 예전 값(texture, arm_* , art_scale, foot_offset …)을 지운 뒤:

```
[node name="Visual" type="Node2D" parent="."]
script = ExtResource("2_visual")
rig_id = "woodcutter"
```
- 크기: `art_scale` (1 = 설계도 `game_scale` 그대로). 거대화 중간 보스는 EliteTraits 가 1.8 배로 키운다. 잿가지 거인은 씬에 `art_scale = 1.72`.
- 구원형: `warm_eye = true`, `npc_rig = "<구원형 id>"` (구원된 사람도 같은 뼈대로 선다), `texture` = 한 장 그림(뼈대가 없을 때 대신).
  집(`data/dialogue/relocations*.json`)에도 `"rig": "<id>"` 를 적으면 집에서도 뼈대로 선다.
- 발이 닿는 땅 = 몸 충돌 캡슐의 바닥 (저절로 찾는다). 공개 함수·값은 예전과 같다 (kick/impact/parried/block/recoil/fall,
  visible_facing/is_facing_settled, show_overhead_bar, arm_front/arm_front_limit/tilt_scale, _label …) — EnemyBase·EliteTraits·경비병 그대로 동작.
- `anim_hint` 별 자세: red(붉은 예고) / charge / stuck / shoot / scatter / leap / fall / land — 이름은 그대로, 자세는 RigPoses 에서.
- 시험이 예전 그림의 속(`_sprite`, `_arm_bone`)을 읽으면 `vis is EnemyRigVisual` 로 갈라 뼈대 값을 읽는다 (tools/probe_enemies.gd 의 `_pose` 참고).

**기계·여러 다리 몹**: 뼈 이름이 다르면 `RigPoses.SETS` 에 새 원형(예: `"mech"`)을 더하고 같은 자세 이름(idle/walk/windup/strike/…)으로
그 원형의 뼈 각도를 적는다. 다리는 몇 개든 된다 (걸음은 번호 짝수/홀수가 번갈아). 한 뼈 다리는 사슬을 `["leg_x"]` 하나로.
몸 전체가 통째로 넘어지는 쓰러짐(통나무·기계)은 그림 쪽에서 `motion.fall_angle`/`fall_pivot` 을 쓴다 (사람은 관절 자세로 쓰러진다).

## 5. 보스에 쓰기

보스 그림(`scripts/bosses/*_visual.gd`)은 상태가 보스마다 달라서 EnemyRigVisual 대신 직접 묶는다:

```gdscript
var rig := PartRig.new()
var motion: RigMotion
func _ready() -> void:
	add_child(rig)
	rig.build("gray_leaf_bird")          # art/rigs/gray_leaf_bird/rig.json
	motion = RigMotion.new(rig)
	rig.setup_ghosts(["torso", "wing_f"], 6)
func _process(delta: float) -> void:
	var p := motion.pose("idle")
	match boss.state:                    # 보스 상태 → 자세 (세 박자는 three_beat 로, 진행도는 보스의 phase_progress)
		…
	motion.set_target(p, RigMotion.Drive.SOFT, RigMotion.Feet.POSE)   # 날고 있으면 Feet.AIR
	motion.update(delta, {"speed": vx / k, "dx": dx / k, "vy": vy / k, "grounded": on_floor})   # k = rig.game_scale * 배율, 보이는 방향 기준 + = 앞
	rig.position = Vector2(0, floor_y)   # 원점 = 발이 닿는 땅
	rig.scale = Vector2(facing * 배율, 배율)   # 좌우를 뒤집은 프레임엔 motion.flip_feet()
	rig.set_flash(boss.flash_amount() * 0.75)
```
보스 자세는 `RigPoses.SETS` 에 원형을 더하거나(새·기사·뿌리지기) 설계도 `poses` 에 자세 이름을 새로 지어 넣는다 (`motion.pose("wing_beat")`).
판정(히트박스)·시간은 보스 스크립트 그대로 두고, 무기 끝 자리가 필요하면 `rig.bone_point("weapon", 끝 자리)` 로 읽는다.

---

## 6. 함정

- **가장자리의 쓰레기 색**: 이 시트들은 반투명 가장자리에 빨강·노랑 RGB 가 묻어 있다. rig_cut 은 자른 부위마다 `defringe` 한다
  (tools/sheet_catalog.gd). 새 도구로 자를 때도 꼭 `defringe`.
- **상자가 겹친다**: 부위 상자끼리 겹치므로 상자로 자르지 말고 **조각 마스크**(comps)로 자른다. 도구는 그렇게 한다.
- **닿아 있는 부위**: 부위가 서로 닿아 한 조각이면 `segment.erode` 를 키우거나(가는 이음에서 끊긴다) `clip`/`cut` 다각형으로 나눈다.
  `erode` 를 바꾸면 **번호가 바뀐다** — 설계도를 다시 맞춘다.
- **관절 틈**: 관절 둘레는 두 부위가 겹쳐야 한다. 다각형 경계를 관절 둥근 곳 너머로 잡고(`grow` 3px 가 기본), 위에 그리는 부위(z 큼)가 덮게 한다.
- **색이 진하게 보임**: 셰이더 fragment 의 `COLOR` 는 이미 텍스처 × modulate 다. 텍스처를 또 곱하지 않는다 (rig_flash 참고).
- **HDR 스크린샷**: 2D HDR 화면을 그대로 저장하면 어둡다 — `rig_preview.gd` 의 `_grab()` 처럼 RGBA8 로 바꾼 뒤 `linear_to_srgb()`.
- **긴 무기**: 칼끝이 땅에 파고들면 `ground_guard` 에 무기 부위를 넣는다 (어깨부터 들어 올린다). 자세에서 팔을 더 앞으로 드는 게 먼저.
- **반쯤 꿇기 금지**: `kneel` 은 0 아니면 1. 0.5 는 무릎이 땅 위에 떠서 어색하다 (섞이는 동안만 중간값).
- **뼈대는 오른쪽을 본다**: 그림 쪽은 `scale.x` 부호로 뒤집는다. 뒤집는 순간 `motion.flip_feet()` (딛은 발이 세상에 남게).
- **익스펜션/ 은 읽기만**: 원본 시트를 고치거나 옮기지 않는다. 잘린 그림만 `art/rigs/` 에.
- **probe_rigs**: 새 뼈대를 넣으면 저절로 검사된다. 발 ±4px, 몸·무기가 땅 아래 4px 넘게 들어가지 않기, NaN, 상자, 8개 비용.

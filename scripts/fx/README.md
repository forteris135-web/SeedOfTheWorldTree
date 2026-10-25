# 이펙트 시스템 (Fx) — 쓰는 법

2026-10-19 이펙트 리뉴얼 F1 에서 만들었다. 그림 이펙트를 이름으로 띄우는 공용 도구다.
다른 묶음(보스 이펙트 F2, 지형, 적 등)도 이 시스템에 이펙트를 더해 쓰면 된다.

## 파일

| 파일 | 하는 일 |
|---|---|
| `scripts/autoload/fx.gd` | 자동 로드 `Fx`. 풀(미리 만들어 둔 그림 노드)·상한·매 프레임 갱신·`spawn()` |
| `scripts/fx/fx_sprite.gd` | 이펙트 하나 (`FxSprite`, 풀이 돌려 쓴다 — 직접 만들지 말 것) |
| `scripts/fx/fx_table.gd` | **이펙트 표** (이름 → 그림·섞기·수명·크기·투명도·회전·팔레트·호 드러내기·딸린 이펙트) + 팔레트 |
| `shaders/fx.gdshaderinc`, `fx_mix.gdshader`, `fx_add.gdshader` | 팔레트 바꾸기(그라데이션 맵)와 호 드러내기(wipe) 셰이더 |
| `art/fx/*.png` | 잘라 둔 이펙트 그림 (밉맵 켬) |
| `tools/cut_fx.gd` | 기획자 시트(`익스펜션/그림/이펙트/`, 읽기 전용)에서 그림을 자르는 도구. 조각 목록 `PIECES` |
| `tools/probe_fx.tscn` | 화면 없는 시험 (모든 이펙트가 뜨고 풀로 돌아오는지, 상한, 레이저·초승달 검기 판정) |
| `tools/probe_fx_shots.tscn` | 화면 있는 스크린샷 (셀레니아 동작별, `--only gallery` 는 표 전체) |

## 띄우기

```gdscript
Fx.spawn("hit_spark", 자리)                                  # 세계 좌표
Fx.spawn("break_burst", 자리, {"facing": -1, "scale": 1.3})  # 왼쪽을 볼 때 좌우 뒤집힘
Fx.spawn("soul_switch", 자리, {"palette": "wind", "follow": 소녀, "offset": Vector2(0, -6)})
```

opts (모두 생략 가능): `facing`(1/-1) `scale` `rot`(도) `color` `energy` `palette` `keep` `follow`(Node2D) `offset`
`vel` `life` `z` `flip_v` `scale_xy` `driven` `children`(false 면 딸린 이펙트 없이). 자세한 뜻은 `fx.gd` 의 `spawn` 주석.

- 돌려받은 `FxSprite` 는 이펙트가 끝나면 다른 이펙트로 다시 쓰인다. 들고 있다가 만지려면 `var gen := fx.gen` 을 같이
  기억해 두고 `Fx.alive(fx, gen)` / `Fx.release(fx, gen)` / `Fx.kill(fx, gen)` / `Fx.set_reveal(fx, gen, 0~1)` 로.
- `driven` 이펙트(소녀 칼질처럼 호의 머리를 부르는 쪽이 끌고 가는 것)는 `release` 해 줘야 사라진다.
- 방이 바뀌면 떠 있던 이펙트는 모두 거둔다.
- 이펙트는 `Fx` 밑의 겹에 그려진다 (화면 기준 세계 좌표, z_index 기본 6 = 소녀·적 앞). 빛을 받지 않는다(unshaded) —
  어두운 방(CanvasModulate)에서도 제 밝기.

## 새 이펙트 더하기

1. 그림이 필요하면 `tools/cut_fx.gd` 의 `PIECES` 에 한 줄 (시트, 씨앗 상자, 최대 크기) 더하고
   `godot --headless --path . -s res://tools/cut_fx.gd -- 이름` → `art/fx/이름.png`. 그다음 `tools/cloud_bootstrap.sh` (임포트).
   시트의 조각 위치는 `tools/sheet_catalog.gd` 목록(catalog.json 의 rect)을 그대로 씨앗 상자로 쓰면 된다.
2. `fx_table.gd` 의 `EFFECTS` 에 한 줄. 칸의 뜻은 파일 맨 위 주석.
3. `tools/probe_fx.tscn` 을 돌리면 새 이펙트도 자동으로 '뜨고 돌아오는지' 시험된다. 눈 확인은 `probe_fx_shots --only gallery`.

## 섞기·밝기 규칙 (중요)

- 방의 글로우가 **스크린 섞기**라 화면 값이 1 을 크게 넘으면 오히려 **회색 얼룩**으로 죽는다
  (더하기 이펙트가 여러 겹 + 밝기 배수 1.5 이상일 때 실제로 나왔다).
- 그래서 **큰 그림(칼질·초승달·기둥·땅 터짐)은 `"blend": "mix"`**, 더하기(`add`, 기본)는 작은 반짝임·고리에만,
  `energy` 는 1.2 안쪽으로 쓴다. 그림 자체가 밝아서 이걸로 충분히 빛나 보인다.

## 팔레트 (그라데이션 맵)

`fx_table.gd` 의 `PALETTES`: `seed`(초록) `wind`(민트) `light`·`gold`(금빛) `heal` `dust` `ash` `white` `red` `purple` `blue`.
그림의 밝기를 [어두운색, 가운데색, 밝은색] 세 색으로 다시 칠한다. 파란·흰 그림 하나로 여러 색을 낸다.
`keep` 은 원래 색을 남기는 비율 (0.2~0.35 면 그림의 결이 조금 더 산다).
Fx 밖의 노드(레이저, 초승달 검기 등)도 `Fx.make_material("light", true)` 로 같은 셰이더 재질을 만들어 쓸 수 있다.

## 호 드러내기 (wipe)

칼자국이 칼을 따라 그려지게 한다. 그림 안의 호 중심(UV)·시작 각도·도는 각도는 **그림마다** 정해져 있어
`fx_table.gd` 의 `ARC_*` 에 모아 두었다 (회전·뒤집기를 해도 그대로 쓴다). `gap_hide` 1 이면 호 범위 밖은 그리지 않는다.

## 아이폰 성능

- 풀 + 상한 `Fx.MAX_ACTIVE`(72). 가득 차면 우선순위(`priority` 0 먼지·알갱이 / 1 보통 / 2 중요)가 낮고 오래된 것부터 비킨다.
- 매 프레임 할 일은 `Fx._process` 한 곳에서 몰아서, 새로 만드는 것 없음. 팔레트·호 드러내기가 없는 이펙트는 공용 재질 두 개를
  함께 써서 묶어 그린다.
- 그림은 처음 한 번 읽어 둔다 (30여 장, 긴 변 512px 이하).

## 지금 있는 이펙트 (F1)

셀레니아: `slash1~3`(3연타, 뼈대가 끌고 감) `seed_slash` `plunge_trail` `plunge_dive` `plunge_impact` `ground_ring` `land_dust` `dust_puff`
`dodge_trail` `air_ring` `guard_hit` `just_guard` `heal` `purify` `purify_flash` `mote` `selenia_down` `soul_switch`
영혼 기술: `wind_wisp` `wind_fade` `wind_hit` `laser_flash` `laser_wall` `laser_hit` (그림 노드: `WindCrescent`, `SoulLaser`)
공용: `hit_spark` `hit_spark_big` `hit_glint` `ring_pop` `break_burst`(적 무너짐) `death_dust`(적 쓰러짐) `pickup_sparkle` `pickup_big`
보호막(가드 중 유리 구)과 칼끝·손에 모이는 빛은 `selenia_rig.gd` 의 자식 그림이다 (`_make_shield`, `_make_tip_glow`).

---

## F2: 보스·적 기술 이펙트 + 물 이펙트 (2026-10-19)

판정은 하나도 바꾸지 않았다 — 그림만. 시트에 불 그림이 없어 등불 기사의 불꽃은 금빛·물 그림을 `fire` 팔레트로 칠해 쓴다.
**가드 불가 공격의 예고·불꽃은 언제나 `danger`(진한 붉은빛) 팔레트**, 가드 가능한 불꽃은 `fire`(주황~노랑).

### 세 가지 길

| 무엇 | 어디 | 어떻게 |
|---|---|---|
| 날아가는 투사체 (깃털·잎·불꽃 파도·등불·불기둥·펌프 충격파·수액 방울·나비·가루·씨앗) | `scripts/fx/fx_art.gd` 의 `LOOKS` | `Projectile.look = "bird_feather"` 한 줄. 코드 그림 대신 그 그림을 그리고 꼬리 잔상도 같은 그림. 되받으면 금빛 |
| 보스의 순간들 (휘두르기 호·착지·붉은 예고 불티·바람 줄기·회오리·김 …) | `scripts/fx/<보스>_fx.gd` (바탕 `skill_fx.gd`) | 보스 `_ready` 의 한 줄 `add_child(preload(...).new())`. 보스의 공개 값(state·attack_phase·facing·is_red() …)을 매 물리 프레임 읽어 상태·공격 단계가 바뀌는 순간 `Fx.spawn` |
| 공격 노드 그림 (뿌리 가시·뿌리 손·달빛 구슬·씨앗·충격파·뿌리 벽·검기·수액 물결·수액 기둥·포자 구름·잎 더미) | 각 노드 스크립트 (`scripts/combat/`, `scripts/bosses/root_*.gd`, `sword_wave.gd`, `scripts/world/leaf_pile.gd`) | 자식 Sprite2D + `Fx.shared_material(팔레트, 더하기, 남김)`. 그림이 없으면 예전 코드 그림으로 돌아간다 |

몹(정원사·경비병·기계·수액 어부)은 각 몹 스크립트의 공격 순간에 `Fx.spawn` 한 줄. 작은 펌프·무쇠 펌프의 물줄기는 `SapBlob.launch`.
물 이펙트는 `scripts/fx/water_fx.gd` (수액 웅덩이 `sap_pool.gd` 의 `_ready` 한 줄). 물보라·잔물결은 웅덩이가 그리는 수면(`SapPool.surface_top()` — 지형 리뉴얼 뒤 맞는 영역 윗변, 판정 수면 `surface_y()` 보다 조금 아래)에 난다. 물 모습 자체(물빛·결·물결 띠)는 웅덩이가 그린다 (`TERRAIN.md` 6장).

### 관찰자(skill_fx) 규칙

- 보스 그림(뼈대)은 다른 묶음이 고치므로 이펙트는 그림 스크립트에 넣지 않았다. 관찰자는 보스의 값만 읽는다.
- 값은 `val("이름", 기본값)` 으로 읽는다 — 보스 논리가 바뀌어 이름이 사라져도 이펙트 때문에 멈추지 않는다.
- 공용: 무너짐(BROKEN) → `boss_break`, 쓰러짐(FALLEN) → `boss_fall`.
- 따라다니는 긴 이펙트(새의 바람 소용돌이·잎 회오리)는 상태가 바뀌면 `Fx.end_soon` 으로 부드럽게 거둔다.

### 이펙트 ↔ 부위 뼈대 (2026-10-20 통합)

보스·몹 그림이 부위 뼈대(RIGS.md)로 바뀌어 창·지팡이·부리·관이 실제로 움직이므로, **몸의 한 부분에서 나는 이펙트는 그 부분을 따라간다.**
- 보스: 관찰자가 `vis_point("이름", 예전 고정 자리)` 로 묻는다 → 보스의 `Sprite`(그림) 의 `fx_point(이름)`. 그림이 모르거나(Vector2.INF)
  보스에서 너무 멀면(`VIS_RANGE`) 예전 고정 자리 — 뼈대를 못 읽어도 이펙트 때문에 멈추지 않는다.
  이름: 기사 `spear_tip`·`spear_grip`·`spear_mid`·`lantern`·`head`·`chest` / 새 `beak`·`wing_tip`·`wing_tip_back`·`chest`
  / 뿌리지기 `staff_head`·`staff_mid`·`lantern`·`hand`·`chest` / 여왕 `hand_f`·`hand_b`·`hands`·`wing_f`·`wing_b`·`chest`
  / 무쇠 펌프 `mouth`(=`piston`)·`muzzle`·`core`·`vent`·`outlet`. 각 그림에 `weapon_tip_global()`·`bone_global(뼈, 자리)`(·`muzzle_global()`)도 있다.
- 몹: 몹 논리가 `fx_point("이름", 예전 고정 자리)`(EnemyBase) 로 묻는다 → `EnemyRigVisual.fx_point`: `weapon_tip`·`muzzle`·`weapon`(방패 면)·`hand`·`chest`·`head`,
  그 밖엔 설계도 sockets 이름(`drill_tip`·`core`·`valve` …), 어부는 `whip_tip`·`hand`. 대롱 몹(정원사·거대 정원사·작은 펌프)은 `shot_origin()` 으로
  씨앗·수액이 **대롱 끝에서** 나간다 (예전 고정 자리에서 최대 60px — 판정 출발점이 크게 튀지 않게).
- 판정 상자를 덮는 이펙트(찌르기 줄기·휘두르기 초승달·내려찍기 터짐·물결)는 판정 기준 자리를 그대로 두고, 높이만 뼈대를 따른다(기사 찌르기).
- **한 공격엔 한 겹:** 그림 쪽의 코드 띠(기사 창끝 띠·뿌리지기 지팡이 보랏빛 띠·펌프 빨아들이기 띠·새 깃털 코드 번쩍임)는 껐다 —
  이 그림 이펙트와 겹쳐 두 겹으로 보였다. 남긴 코드 연출: 기사 등불 회전의 주황 등불 띠(바닥 고리만으론 등불이 도는 길이 안 보인다),
  어부 낚싯줄 끝 자국(줄을 따라가는 가는 선), 여왕 내리꽂기 꼬리·박자 고리, 새 깃털 예고(붉은 점·고리), 뼈대 잔상, 작은 불씨·먼지 알갱이.
- 가드 불가 공격은 계속 진한 붉은빛 (그림의 붉은 깜빡임 + 붉은 불티·`danger` 팔레트) — 크림·보랏빛 코드 띠가 사라져 더 또렷하다.

### 새로 생긴 것

- 팔레트: `fire` `ember` `sap` `spore` `moon` `danger` `steam`
- `Fx.shared_material(팔레트, 더하기, 남김)` (같은 조합끼리 재질 하나 → 묶어 그리기), `Fx.end_soon(fx, gen)`,
  시험용 `Fx.log_spawns` / `Fx.spawn_log`
- 그림 34장 (`tools/cut_fx.gd` 의 F2 줄): 보스 이펙트 1(금빛 깃털·잎·바람 초승달·잎 회오리·낱장 잎), 보스 이펙트 2(물기둥·물방울·나비·물줄기·김·물 초승달),
  물 이펙트(물결·물보라·물마루·물줄기), PNG image(보랏빛 초승달), c5ae(뿌리 손·씨앗·씨앗 터짐), 41d289(창 빛줄기·뿌리 가시·뿌리 덩어리), f9e7(등불·버섯·포자 안개)
- 시험: `tools/probe_fx_boss.tscn` (화면 없음 — 그림 묶음 판정 그대로, 보스 다섯 기술별 이펙트, 공격 노드 그림, 몹, 물, 상한),
  `tools/probe_fx_boss_shots.tscn -- --boss bird|knight|root|queen|pump|mobs|water [--only 기술,…]` (창 모드 스크린샷, headless 면 바로 끝)

### 세기 조절

- 투사체 그림 크기·색: `fx_art.gd` 의 `LOOKS` (scale, palette, keep, glow, trail)
- 순간 이펙트 크기·수명·색: `fx_table.gd` 의 F2 줄
- 바람 줄기 간격: `bird_fx.gd` 의 `STREAK_GAP`/`CRESCENT_GAP`/`LEAF_GAP`, 물결 간격: `water_fx.gd` 의 `STEP_GAP`, 방울 간격 `DRIP_GAP`
- 노드 그림 배율: 각 노드 스크립트 위의 `ART_SCALE` 상수

### 메모리

그림은 F1 30장 + F2 34장 = 64장, 디스크 약 7MB, 밉맵 포함 VRAM 약 17MB (Fx 가 처음에 모두 읽어 둔다 — 싸움 중 처음 쓰는 순간의 끊김 없음).

## v1.1.0 (2026-10-25 통합)
- **팔레트 `teal`** (중간색 #00B0AB): 셀레니아 일반 공격 `slash1~3`(keep 0.15, 칼자국 끝 = 판정 끝 ±20px — 새순 범위 배율만큼 scale_xy 도 커진다,
  자리는 `selenia_rig.gd` SLASH_FX_OFFSET)과 일반 공격 타격 불꽃. 바람(민트)·수액(청록)과 구별되게 더 진하다.
- 새 `plunge_dive`(내려꽂는 동안 발밑 판정을 덮는 아래로 향한 초승달), `plunge_impact` 는 착지 판정(±170) 가운데에서, 고리·먼지는 발밑. 수액의 맥동이면 둘 다 ×1.15.
  `seed_slash` scale_xy (1.43, 1.45).
- **정화:** `purify` 기둥은 seed 팔레트(keep 0.6)·×1.15·색 곱 (0.72, 0.84, 0.70) + 잎 6장 `purify_leaf`·`purify_leaf_b`, `purify_flash`·`mote` 는 금빛 그대로.
- **보스 근접 공격 = 판정 = 예고:** `scripts/fx/range_telegraph.gd`(RangeTelegraph — 채움은 보스 뒤, 테두리는 z 1 로 보스 앞; 막을 수 있음 주황 / 가드 불가 진한 붉은색
  + 붉은 테두리 바로 안쪽에 밝은 선 2px(붉게 빛나는 보스 몸 위에서도 읽히게 — 통합 검수), 움직이는 공격은 쓸고 갈 구간), `SkillFx.fit_fx(name, world_rect, facing, rot_deg, opts)`(follow, ground_y — 바닥 고리·먼지·김은 바닥 높이에서).
  새 항목 `peck_streak` `knight_spin` `charge_lance` `pump_vent` `vent_warn` `vent_leak`. `peck_burst`·`pump_bite` 는 무작위 회전 없음.
  `root_stomp`·`queen_land`·`pump_slam` 의 ground_ring 은 판정 폭에 맞춤.
- **보스 투사체: 보이는 그림 = 판정** (`scripts/fx/fx_art.gd` 머리말). 그림 크기·발광은 2026-10-19 '탄을 크게' 그대로이고, 판정 원을 보이는 그림(알파 ≥ 0.25,
  뒤로 끌리는 꼬리·발광·잔상 제외)에 맞췄다 — 그림 묶음의 `hit_r` 를 보스의 `_pierce` 가 `Projectile.use_art_hit_radius()` 로 넣는다(몹은 같은 그림이어도 그대로).
  뿌리지기 달빛 구슬 `RootOrb.HIT_PER_R`, 씨앗 비 `RootSeed.HIT_R`, 기사 검기 `SwordWave.HIT_BOX_K`. 그림 배율을 바꾸면 이 값도 함께 고친다 —
  `tools/probe_boss_melee.tscn -- --only shots` 가 그림 픽셀을 재어(`tools/shot_art_measure.gd`) ±20% 를 확인한다. 그림 묶음 칸 `wobble`(잎 흔들림), flip_x 그림의 head 는 뒤집은 그림 기준.

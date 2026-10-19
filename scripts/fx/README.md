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

셀레니아: `slash1~3`(3연타, 뼈대가 끌고 감) `seed_slash` `plunge_trail` `plunge_impact` `ground_ring` `land_dust` `dust_puff`
`dodge_trail` `air_ring` `guard_hit` `just_guard` `heal` `purify` `purify_flash` `mote` `selenia_down` `soul_switch`
영혼 기술: `wind_wisp` `wind_fade` `wind_hit` `laser_flash` `laser_wall` `laser_hit` (그림 노드: `WindCrescent`, `SoulLaser`)
공용: `hit_spark` `hit_spark_big` `hit_glint` `ring_pop` `break_burst`(적 무너짐) `death_dust`(적 쓰러짐) `pickup_sparkle` `pickup_big`
보호막(가드 중 유리 구)과 칼끝·손에 모이는 빛은 `selenia_rig.gd` 의 자식 그림이다 (`_make_shield`, `_make_tip_glow`).

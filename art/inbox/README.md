# art/inbox — 받은 그림을 넣는 곳

ChatGPT에서 받은 그림은 이름 상관없이 **이 폴더에 모아 두면** 된다. 그 뒤 Claude Code에게 "inbox 정리해 줘"라고 하면
`EXPANSION.md` 11장(확장판) / `ART_PROMPTS.md`(1편)의 **약속된 파일 이름**으로 바꿔 제자리에 옮긴다.

직접 하고 싶다면: 아래 표의 이름으로 바꿔 그 자리에 **덮어쓰기**만 하면 끝이다. 지금 그 자리에는 코드로 만든 **임시 그림**(스킨 자리)이
같은 크기(1536×1024)로 들어 있어서, 덮어쓰면 게임이 곧바로 진짜 그림을 쓴다 (배율은 그대로. 그림 속 인물의 **방향**과 어부의 **낚싯대 끝 자리**만 아래 메모대로 한 줄 맞추면 된다).

## 확장판 · 수액의 호수 (임시 그림이 들어 있는 자리)

| 그림 | 파일 이름 | 메모 |
|---|---|---|
| 수액의 여왕 (지금) | `art/bosses/boss_sap_queen_now.png` | **이제 부위 뼈대로 움직인다** (2026-10-20: 기획자 부위 시트 `익스펜션/그림/보스/1B276E19-….PNG` → `data/rigs/sap_queen.json` → `art/rigs/sap_queen/`). 이 파일은 뼈대를 못 읽을 때만 대신 뜨는 조립 그림이다 — `tools/queen_film.tscn -- --render` 가 만든다(덮어쓰지 않는다). 그림을 바꾸려면 부위 시트를 새로 주고 RIGS.md 대로 다시 자른다 |
| 수액의 여왕 (과거, 회상용) | `art/bosses/boss_sap_queen_past.png` | 가로 3:2 |
| 수액 어부 | `art/enemies/enemy_sap_fisher.png` | 투명 배경. **오른쪽을 보는** 옆모습(임시 그림 기준). 왼쪽을 보는 그림이면 `scenes/enemies/sap_fisher.tscn` 의 Visual → `art_faces_right` 를 false 로. **낚싯대만 그리고 줄은 그리지 않는다** (줄은 게임이 대 끝에서 그려 채찍처럼 휘두른다 — 그림에도 줄이 있으면 두 가닥으로 보인다). 대 끝 자리가 임시 그림과 다르면 Visual → `rod_tip_uv`(그림 가로·세로 비율, 오른쪽을 볼 때 기준, 임시 그림은 0.88, 0.14)를 맞춘다. 대가 없는 그림이면 `use_rod_tip` 을 끄면 손 자리에서 줄이 나온다 |
| 수액 어부 (구원 가능) | `art/enemies/enemy_sap_fisher_savable.png` | 위와 같음 (`sap_fisher_savable.tscn`). 구원한 뒤 사당의 '집'에 선 모습은 `data/dialogue/relocations_expansion.json` 의 `fisher_lake` 값(`art_faces_right` true, `art_scale` 0.22)을 따로 쓴다 — 그림 방향·크기를 바꾸면 여기도 같이 맞춘다 |
| 숨은 내리막 배경 | `art/backgrounds/bg_hidden_descent.png` | 가로 3:2 |
| 수액의 호수 1 배경 | `art/backgrounds/bg_sap_lake_1.png` | 가로 3:2 (호수 방 두 곳이 함께 씀) |
| 수액의 호수 보스 싸움터 배경 | `art/backgrounds/bg_sap_lake_boss.png` | 가로 3:2 |
| 여왕 회상 ①②③ | `art/memories/memory_queen_1.png`, `_2.png`, `_3.png` | 가로 3:2 |

- 임시 그림을 다시 만들려면: `Godot --headless --path . --script tools/make_placeholders_lake.gd`
- 잠긴 채굴장(무쇠 펌프·작은 펌프·금 간 벽·이슬잔·경전 조각·펌프 회상·제3의 길 엔딩)은 EXPANSION.md 11장의 이름을 그대로 쓴다.
- 진짜 그림을 넣은 뒤 Godot 편집기를 한 번 열면(또는 `Godot --headless --path . --import`) 새로 읽어 들인다.

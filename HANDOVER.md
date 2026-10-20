# 인수인계서 — 클라우드 세션 → 로컬(맥) 작업 (2026-10-19)

이 문서는 클라우드 Claude Code 세션에서 하던 일을 맥(로컬)에서 이어받기 위한 안내다.
자세한 규칙은 `GAME_DESIGN.md`(기획서, 특히 0장·8장), 단계별 기록은 `CLAUDE.md` 진행 기록을 본다.

## 1. 지금 상태 한 줄 요약
- GitHub `main` 최신 커밋 **865822e** 가 기준이다. 모든 작업은 여기에 합쳐져 있고 화면 없는 자동 시험은 전부 통과했다.
- 1편의 뼈대(타이틀 → 수관 → 보스 새 → 마을 → 채굴장 → 등불 기사 → 심연 → 뿌리지기 → 엔딩 2종)는 처음부터 끝까지 이어진다.
- 마지막 두 번의 큰 작업(모션 개편·비밀 요소·지도 색 / 요청 10개 반영)은 **클라우드에서 그림 없이** 만들었다. 숫자와 상태 흐름은 자동 시험으로 확인했지만 **눈과 귀로 보는 확인은 하나도 안 됐다.** 로컬에서 가장 먼저 할 일이 이것이다.

## 2. 로컬로 가져오기
```bash
cd ~/<프로젝트 폴더>          # 전에 push 했던 그 폴더
git pull origin main
```
- 저장소 주소가 `https://github.com/forteris135-web/SeedOfTheWorldTree.git` 로 바뀌었다(대소문자). 옛 주소로도 되지만 경고가 나오면 `git remote set-url origin https://github.com/forteris135-web/SeedOfTheWorldTree.git`.
- GitHub 에 작업용 브랜치 `wp2/player`·`wp2/levels`·`wp2/guard`·`wp2/hud` 네 개가 남아 있다. 전부 main 에 합쳐진 것이라 GitHub 페이지에서 지워도 되고 그냥 둬도 된다(클라우드에서는 삭제 요청이 막혀 못 지웠다).
- 로컬에서 Godot 편집기로 처음 열면 새 파일(효과음 `plunge.wav`·`slash_wide.wav`, probe 씬 등)을 한 번 임포트한다. 몇 분 걸릴 수 있다.

## 3. 로컬에서 바로 해야 할 확인 (우선순위 순)
맥에서 `project.godot` 을 열고 ▶ 로 실행한 뒤, 아래를 눈으로 본다. 문제가 있으면 괄호의 파일·상수를 조절한다.

1. **씨앗 베기** (K 또는 R2, 첫 방에서 바로): 칼을 머리 위 뒤로 들었다가 앞 위→앞 아래로 쓸어 베고 큰 초승달 흔적이 남는지, 위·아래의 적도 맞는지. (`scripts/player/player.gd` slash_*, `scripts/player/selenia_rig.gd` WINDUP_S/STRIKE_S·SLASH_RX 등)
2. **낙하 공격** (점프 중 S+J): 멈칫 → 내리꽂기 → 착지 충격 링. 적 위에서 튕기는 느낌. (`plunge_*`, rig `PLUNGE_RING_R`)
3. **가드 보호막** (L): 머리부터 발까지 키만 한 하늘빛 타원, 막을 때 고리와 '퍽' 소리. (rig `GUARD_CENTER/GUARD_RY`, 소리는 `tools/gen_sfx.gd` 의 "guard")
4. **채굴장 입구** (마을 끝 포탈 → 내려가는 갱도): 선반 가운데 가시를 달리기 점프로 넘고, 선반 끝에서 디딤 가지를 밟아 바닥까지. 가시에 닿으면 15 깎이고 조금 전 자리로 돌아오며 다시 찔리지 않는지.
5. **경비병** (마을 입구의 거리): 방패가 소녀 쪽을 향하는지, 등 뒤로 구르면 반 박자 늦게 돌아서는지, 정면 4번째 타격은 맞는지. (`scripts/enemies/guard.gd` 맨 위 export, `scenes/enemies/guard.tscn`)
6. **HUD**: 비밀 아이템·구원 보상 뒤 이슬 개수·막대 길이·검/물방울 아이콘·영혼 색 원. (`scripts/ui/combat_hud.gd` 맨 위 상수)
7. **얇은 가지 발판**: 아래에서 뛰어 올라서기, 위에서 S+Space 로 내려가기, 밑면 점선이 보이는지. (`scripts/world/platform.gd` ONE_WAY_DASH_*)
8. **보스전 레터박스**: 띠 모양·보스 막대·정화 뒤 띠가 내려가며 회상으로. (`scripts/ui/boss_hud.gd`)
9. **적·보스·셀레니아 모션** 전반(앞 작업): 끊김·'툭' 없이 세 박자로 보이는지. (각 visual 파일 상단 상수)
10. **터치**(아이폰): 오른쪽 다섯 버튼 + 왼쪽 회복·전환, 노치와 겹침, 낙하 공격의 ↓ 문턱(스틱 절반). (`scripts/ui/touch_controls.gd` `_buttons()`, `player.gd` `DOWN_HOLD_STRENGTH`)

## 4. 기획자가 정해야 할 것 (코드는 한 줄짜리 변경)
- **새 영혼 자동 전환**: 보스를 정화해 바람·빛을 얻는 순간 고른 영혼을 그 영혼으로 바꿀지. 지금은 씨앗 그대로(Q / 십자키 ←→ 로 전환).
- **첫 보스(새)와 낙하 공격**: 새가 공중에 있을 때 낙하 공격 두 번이면 내려온다. 너무 쉬우면 `scripts/bosses/gray_leaf_bird.gd` 의 피로 계산을 손본다.
- **경비병 강도**: 정면 약공격 6대면 무너진다. 더 단단하길 원하면 `guard.gd` 의 `block_open_time` 0 / `block_limit` 4~5.
- **잎의 회랑 비밀 천장**이 60px 왼쪽(990)으로 옮겨졌다. 자리가 어색하면 `scenes/rooms/canopy_03.tscn` 의 SecretStalk·SecretCeiling1·Pickup1 을 함께 옮긴다.

## 5. 시험 도구 (맥에서도 그대로 된다)
- 방 시험: `tools/test.sh <방> <플래그> [초]` — Godot 경로는 스크립트가 흔한 자리를 찾고, 없으면 `GODOT=/Applications/Godot.app/Contents/MacOS/Godot tools/test.sh ...`.
  - 자주 쓰는 것: `canopy_01 --autotest`, `canopy_boss --bosstest 200`(mine_boss·abyss_boss 도), `canopy_hidden --minitest`, `canopy_01 --portaltest`, `--grasstest`, `--savetest`, `--nooktest`, `--remaptest`, `--secrettest`(canopy_01·03·04, mine_01, village_01, abyss_02), `--rescuetest`(canopy_01, village_01, mine_02, abyss_02), `village_01 --villagetest`, `canopy_boss --camtest`.
- 독립 시험(probe): `godot --headless --path . res://tools/probe_player.tscn` (guard·hud·levels·enemies·bosses·map_scene 도 같은 식), `-s res://tools/probe_selenia.gd`, `-s res://tools/probe_texts.gd`. `probe_levels` 는 5분쯤 걸린다. 끝줄 "[probe] 끝: 실패 0" 이면 통과.
- 전체 회귀: `GODOT=<Godot 실행 파일> tools/regress.sh` — 방 시험·보스 다섯 곳·방 41개 로드·probe 전부·지형 감사·포탈 연결 검사 (로그 `.regress/`, 줄마다 `err 0`·FAIL 없음이어야 통과).
- 지형 점검(Godot 없이 Python3 만): `python3 tools/audit_rooms.py` (와 `--locked`) → 41개 방 "오류 0" 이어야 한다. 소녀 수치(점프·속도)를 바꾸면 이 파일 맨 위 상수도 맞춘다.
- 그림이 있는 시험: `-- --screenshot`, `-- --rigtest`(연습장) 는 맥에서만 스크린샷이 찍힌다(`screenshots/`).
- **절대 돌리지 말 것**: `tools/make_rooms.py`(옛 방 생성기 — 다시 돌리면 포탈·비밀·디딤 가지·one_way 가 날아간다). 방은 `.tscn` 을 직접 고친다.

## 6. 내보내기
- **아이폰**: `tools/export_ios.sh` → `build/ios/SeedOfTheWorldTree.xcodeproj` → Xcode 에서 ▶ (`IPHONE_SETUP.md`). 무료 계정이라 7일마다 다시 ▶. 클라우드에서는 못 했으므로 **지금 아이폰에 깔린 판은 오래된 것**이다.
- **안드로이드**: `tools/export_android.sh` → `build/android/SeedOfTheWorldTree.apk` (`ANDROID_SETUP.md`). 클라우드에서 만든 APK(v0.7, 대화창으로 보냄)는 **서명 키가 맥과 달라** 맥에서 만든 것과 덮어 설치가 안 된다. 어느 쪽이든 바꿀 때는 앱을 지우고 설치.
- 디버그 서명뿐이다. 스토어용 릴리스 서명·AAB 는 아직 없다.

## 7. 폴더·파일 길잡이
- `scripts/player/` 소녀(`player.gd` 상태 기계, `selenia_rig.gd` 뼈대 애니메이션, `game_camera.gd`)
- `scripts/enemies/` 적(`enemy_base.gd` 공통 상태 기계, `enemy_rig_visual.gd`·`enemy_mech_visual.gd` 부위 뼈대 그림·모션 — RIGS.md, 종류별 스크립트), `scripts/bosses/` 보스 셋 + `boss_room.gd`
- `scripts/world/` 방(`room.gd` — 방 바탕 + 모든 `--…test`), 발판·경사·가시·포탈·달빛풀·비밀 벽/천장·아이템
- `scripts/ui/` HUD·보스 HUD·터치·지도·메뉴·키 바꾸기·이동 메뉴·타이틀·회상·엔딩
- `scripts/autoload/` Progress(진행·능력·성장·고른 영혼), SaveGame, Settings, Keymap, InputDevice, Sfx, Music, Juice, **Fx**(공용 이펙트 — `scripts/fx/README.md`), Purity, Dialogue, Game
- `scenes/rooms/` 방 41개(확장판 포함), `data/dialogue/` 대사·기록물·회상·엔딩 JSON, `audio/sfx/`(합성 효과음, `tools/gen_sfx.gd`), `audio/music/`(기획자의 정식 곡 18곡, 곡 표는 GAME_DESIGN.md 10장; 옛 합성 도구 `tools/gen_music.swift` 는 `audio/_temp_music/` 에 씀), `music/theme/` 원본(절대 덮어쓰지 않음)
- 설명서: `RIGS.md`(몹·보스 부위 뼈대 그림·모션), `TERRAIN.md`(그림 조각 지형·그림 옷·잿빛 팔레트), `ENDINGS.md`(엔딩 지시서 — 기획자 원본), `scripts/fx/README.md`(이펙트).
- `tools/` 시험·생성·내보내기 스크립트. `tools/add_secrets.py`·`tools/make_portals.py`·`tools/add_portals.py` 도 자리 표 기록용이지 다시 돌릴 용도가 아니다.

## 8. 아직 안 한 것 (남은 단계)
- 12 회상 다듬기(그림·문장), 13 진짜 음악(지금은 합성 임시곡, WAV 31MB → OGG 로 줄이기), 14 포장 나머지(한글 글꼴 번들 — 지금은 기기 글꼴, 무료 효과음 에셋 교체, 지도 다듬기), 16 최종 테스트.
- 보류: 수영(2편 보관함), 플레이 스토어 릴리스 서명.
- 그림: 일반 마을 경비병 그림(얼굴 침식)은 받아서 교체됨. 경비병 그림을 다시 받으면 `guard.tscn` 의 `art_faces_right` 만 그림 방향에 맞춘다.

## 9. 클라우드 세션에서 배운 주의점
- `Input.action_press` 는 상태만 바꾸고 이벤트를 안 보낸다(터치 지도/메뉴 버그의 원인). 이벤트로 듣는 동작은 `InputEventAction` 도 보내야 한다.
- `Camera2D.offset` 은 방 경계 클램프 뒤에 더해진다(보스 바에 소녀가 가려지던 원인). 위쪽 보기는 카메라 `position` 으로.
- `Parallax2D` 는 화면 왼쪽 위 기준이다.
- Hitbox 는 한 휘두름에 닿은 모든 상대에게 **같은 HitData 객체**를 넘긴다. 상대마다 값을 바꾸려면 `hit.copy()`.
- headless 로는 그림·소리를 못 본다. 수치 시험(probe)과 눈 확인을 늘 짝지어라.

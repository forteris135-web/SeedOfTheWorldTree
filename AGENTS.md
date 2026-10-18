# 프로젝트: 세계수의 씨앗 (가제)

Godot 4로 만드는 아이폰·아이패드용 2D 횡스크롤 메트로배니아 + 소울라이크 게임.
입력: 듀얼센스, 엑스박스 컨트롤러, 키보드(아이패드 매직 키보드 포함), 터치.

## 먼저 읽을 것
- `GAME_DESIGN.md` : 기획서. 모든 판단의 기준. 특히 "0. Codex에게" 장의 작업 지침을 따른다.
- `SCRIPT.md` : 이야기와 대사의 기준.
- `ART_PROMPTS.md` : ChatGPT 그림 요청 목록과 파일 이름 약속.

## 핵심 약속 (요약)
- 나는 코딩을 모르는 **기획자 겸 테스터 겸 아트 디렉터**다. 설명은 쉬운 한국어로.
- 항상 **실행 가능한 상태**를 유지하고, 단계가 끝나면 **무엇을 테스트할지** 알려 준다.
- Godot 편집기나 Xcode에서 내가 직접 눌러야 하는 건 **어디서 무엇을 누르는지** 하나씩 안내한다.
- **1편 범위**를 지킨다. 범위가 커질 것 같으면 먼저 묻는다.
- 대사는 코드에 직접 넣지 않고 별도 데이터 파일로 관리한다.
- `music/theme/`의 원본 파일은 절대 덮어쓰지 않는다.
- **구원할 수 있는 사람은 반드시 구원된다.** 이 원칙을 바꾸는 구현은 하지 않는다.

## 진행 기록
- 각 개발 단계를 마칠 때마다 아래에 한 줄씩 기록해 줘. (다음에 이어서 작업할 때 참고)

- 2026-10-18 **1단계 환경 세팅 완료:** Godot 4.7.2 프로젝트 생성(`project.godot`, 모바일 렌더러, 1920×1080 가로, 늘림 방식 canvas_items/expand), 조작표 그대로 입력 맵 등록(14개 동작), 장치 감지 자동 로드 `scripts/autoload/input_device.gd`, 입력 확인 화면 `scenes/debug/input_test.tscn`. 폴더 구조(art/, music/, screenshots/, data/dialogue/) 생성. 기획자가 듀얼센스·엑스박스·키보드 입력 확인 마침.
- 2026-10-18 **2단계 아이폰·아이패드 첫 설치 (맥 쪽 완료):** 내보내기 템플릿 4.7.2 설치(`~/Library/Application Support/Godot/export_templates/4.7.2.stable/`), iOS 설정 `export_presets.cfg`(Xcode 프로젝트만 생성, 아이폰+아이패드, 번들 ID `com.wj.seedoftheworldtree`, Team ID는 임시 `XXXXXXXXXX` → 기획자 Apple ID 로그인 후 진짜 값으로 교체할 것), `build/ios/SeedOfTheWorldTree.xcodeproj` 내보내기 성공. 안내문 `IPHONE_SETUP.md`. 남은 것(기획자): Xcode 라이선스 동의, Apple ID 로그인, 아이폰·아이패드에 ▶로 설치. 다시 내보낼 때: `Godot --headless --path . --export-debug "iOS" build/ios/SeedOfTheWorldTree.xcodeproj`

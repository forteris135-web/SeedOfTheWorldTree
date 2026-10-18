#!/bin/bash
# 화면 없이(headless) 자동 시험을 돌린다. 프로젝트 폴더 어디서 실행해도 된다.
# 사용: tools/test.sh <방 이름> <시험 플래그> [시간 제한(초), 기본 90]
#   예) tools/test.sh canopy_01 --autotest
#       tools/test.sh canopy_boss --bosstest 120
#       tools/test.sh village_02 --screenshot      (방이 오류 없이 뜨는지만)
# Godot 실행 파일은 GODOT 환경변수로 준다. 없으면 흔한 자리들을 찾아본다.
# 출력: 시험이 찍는 [..] 줄과 SCRIPT ERROR / Parse Error 줄만 남긴다. 마지막 줄 "exit N" 은 종료 코드 (124 = 시간 초과).
set -u
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
ROOM="${1:?방 이름}"
FLAG="${2:?시험 플래그}"
LIMIT="${3:-90}"
G="${GODOT:-}"
for c in "$G" /tmp/claude-0/-home-user/c632609b-bc85-55ec-8d51-8895afedec3f/scratchpad/bin/godot "$HOME/godot" /Applications/Godot.app/Contents/MacOS/Godot /Users/wj/Downloads/Godot.app/Contents/MacOS/Godot; do
  if [ -n "$c" ] && [ -x "$c" ]; then G="$c"; break; fi
done
[ -x "$G" ] || { echo "Godot 실행 파일을 못 찾았다. GODOT=/path/to/godot tools/test.sh ..."; exit 2; }
case "$ROOM" in
  res://*) SCENE="$ROOM" ;;
  *) SCENE="res://scenes/rooms/$ROOM.tscn" ;;
esac
# FLAG 는 따옴표 없이 넘겨서 "--screenshot --map" 처럼 여러 플래그를 한 번에 줄 수 있게 한다
# shellcheck disable=SC2086
timeout "$LIMIT" "$G" --headless --path "$PROJECT" "$SCENE" -- $FLAG 2>&1 \
  | grep -E "^\[|SCRIPT ERROR|Parse Error|ERROR: Failed to load|^ERROR: .*\.gd" \
  | grep -v "resources still in use\|ObjectDB instances"
echo "exit ${PIPESTATUS[0]}"

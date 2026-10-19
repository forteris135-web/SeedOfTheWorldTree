#!/bin/bash
# 클라우드 작업용: 새 작업 폴더(git worktree)에서 Godot 캐시를 준비한다.
# 1) 본 저장소의 .godot 캐시를 복사해 그림 재임포트를 건너뛰고 2) 새 스크립트·씬이 등록되게 --import 를 한 번 돈다.
# 사용: tools/cloud_bootstrap.sh            (작업 폴더 어디서 실행해도 됨)
set -u
# macOS 에는 timeout 이 없다: perl alarm 으로 대신한다 (시간 초과 종료 코드 142)
tmo(){ if command -v timeout >/dev/null 2>&1; then timeout "$@"; else perl -e 'alarm shift; exec @ARGV' "$@"; fi; }
PROJECT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="${MAIN_PROJECT:-$([ -d /Users/wj/Projects/SeedOfTheWorldTree ] && echo /Users/wj/Projects/SeedOfTheWorldTree || echo /home/user/seedoftheworldtree)}"
G="${GODOT:-}"; for c in "$G" /Users/wj/Downloads/Godot.app/Contents/MacOS/Godot /Applications/Godot.app/Contents/MacOS/Godot /tmp/claude-0/-home-user/c632609b-bc85-55ec-8d51-8895afedec3f/scratchpad/bin/godot; do [ -n "$c" ] && [ -x "$c" ] && { G="$c"; break; }; done
if [ ! -d "$PROJECT/.godot" ] && [ -d "$MAIN/.godot" ] && [ "$PROJECT" != "$MAIN" ]; then
  cp -r "$MAIN/.godot" "$PROJECT/.godot"
  echo "캐시 복사함: $MAIN/.godot → $PROJECT/.godot"
fi
tmo 900 "$G" --headless --path "$PROJECT" --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error" | head -20
echo "import 끝 (exit ${PIPESTATUS[0]})"
